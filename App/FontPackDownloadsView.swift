import SwiftUI
import UniformTypeIdentifiers

private final class FontDownloadBudget: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expected: Int64
    let progress: @Sendable (Int64) -> Void
    init(expected: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.expected = expected
        self.progress = progress
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard UnicodeFontPackCatalog.acceptsProgress(totalBytesWritten, expected: expected),
              totalBytesExpectedToWrite < 0 || totalBytesExpectedToWrite == expected else {
            downloadTask.cancel()
            return
        }
        progress(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(UnicodeFontPackCatalog.allowsRedirect) == true ? request : nil)
    }
}

@MainActor
private final class FontPackDownloads: ObservableObject {
    static let shared = FontPackDownloads()
    @Published private(set) var activePack: String?
    /// Packs waiting their turn, in the order they were requested.
    @Published private(set) var queue: [String] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var installed: [String: Int] = [:]
    @Published private(set) var stored: Set<String> = []
    /// The last failure of each pack, shown on the pack with a Retry button.
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var message: String?
    private var cancelledActive = false
    private let store = UnicodeFontDownloadStore.shared
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()
    private var task: Task<Void, Never>?
    private var runID: UUID?
    private var receivedByFont: [String: Int64] = [:]

    init() {
        // Only the app writes this staging namespace. A previous process may
        // have been stopped between a verified copy and its atomic move.
        if let directory = store.directory,
           let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix(".incoming-") {
                if UUID(uuidString: String(file.lastPathComponent.dropFirst(10))) != nil {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        reload()
    }
    deinit { task?.cancel(); session.invalidateAndCancel() }

    func reload() {
        let names = Set(store.directory.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? [])
        stored = Set(UnicodeFontPackCatalog.bundled.packs.filter { pack in
            pack.fonts.contains { names.contains($0.asset.filename) || names.contains($0.asset.filename + ".receipt.json") }
        }.map(\.id))
        installed = Dictionary(uniqueKeysWithValues: UnicodeFontPackCatalog.bundled.packs.map { pack in
            (pack.id, pack.fonts.filter { store.installedURL(for: $0) != nil }.count)
        })
    }

    var packs: [UnicodeFontPack] { UnicodeFontPackCatalog.bundled.packs }

    func isComplete(_ pack: UnicodeFontPack) -> Bool { installed[pack.id, default: 0] == pack.fonts.count }

    /// Bytes still to download for every pack that is not yet complete.
    var remainingBytes: Int64 {
        packs.filter { !isComplete($0) }.reduce(0) { total, pack in
            total + pack.fonts.filter { store.installedURL(for: $0) == nil }.reduce(0) { $0 + $1.bytes }
        }
    }
    var downloadedBytes: Int64 {
        packs.reduce(0) { total, pack in
            total + pack.fonts.filter { store.installedURL(for: $0) != nil }.reduce(0) { $0 + $1.bytes }
        }
    }

    /// Queues a pack; packs download one at a time in request order.
    func download(_ pack: UnicodeFontPack) {
        guard !pack.fonts.isEmpty, activePack != pack.id, !queue.contains(pack.id) else { return }
        guard store.directory != nil else {
            message = "Shared font storage is unavailable. Reopen the app and try again."
            return
        }
        // Downloading a pack is a request to use it: turn previews on.
        if !CatalogPreferences.shared.useUnicodeFonts { CatalogPreferences.shared.selectUnicodeFonts(true) }
        failures[pack.id] = nil
        message = nil
        queue.append(pack.id)
        startNextIfIdle()
    }

    func downloadAll() {
        for pack in packs where !isComplete(pack) { download(pack) }
    }

    private func startNextIfIdle() {
        guard activePack == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let pack = packs.first(where: { $0.id == id }) else { startNextIfIdle(); return }
        run(pack)
    }

    private func run(_ pack: UnicodeFontPack) {
        let id = UUID()
        runID = id
        activePack = pack.id
        cancelledActive = false
        progress = 0
        receivedBytes = 0
        let store = store, session = session
        task = Task {
            let existing = pack.fonts.filter { store.installedURL(for: $0) != nil }
            let pending = pack.fonts.filter { store.installedURL(for: $0) == nil }
            receivedByFont = Dictionary(uniqueKeysWithValues: existing.map { ($0.asset.filename, $0.bytes) })
            var finishedCount = existing.count
            do {
                let operation: @Sendable (UnicodeFontDownload) async throws -> UnicodeFontDownload = { [self] font in
                    try Task.checkCancellation()
                    try await Self.fetch(font, session: session, store: store) { [self] received in
                        Task { @MainActor in
                            self.recordProgress(font: font, received: received, pack: pack, run: id)
                        }
                    }
                    return font
                }
                try await withThrowingTaskGroup(of: UnicodeFontDownload.self) { group in
                    var next = 0
                    for _ in 0..<min(3, pending.count) {
                        let font = pending[next]
                        next += 1
                        group.addTask { try await operation(font) }
                    }
                    while let font = try await group.next() {
                        finishedCount += 1
                        installed[pack.id] = finishedCount
                        recordProgress(font: font, received: font.bytes, pack: pack, run: id)
                        if next < pending.count {
                            let font = pending[next]
                            next += 1
                            group.addTask { try await operation(font) }
                        }
                    }
                }
                progress = 1
                message = "Downloaded. The app and keyboard now use these fonts for previews iOS can’t draw."
            } catch {
                if Task.isCancelled || cancelledActive {
                    message = "Download cancelled. Completed fonts are kept; retry to download the rest."
                } else {
                    failures[pack.id] = "Couldn’t download or verify this pack. Completed fonts are kept."
                    message = "The font download could not be verified. Check your connection and try again; completed fonts are kept."
                }
            }
            UnicodeFontSupport.clearCache()
            CatalogPreferences.shared.fontFilesChanged()
            reload()
            activePack = nil
            runID = nil
            task = nil
            startNextIfIdle()
        }
    }

    private func recordProgress(font: UnicodeFontDownload, received: Int64, pack: UnicodeFontPack, run: UUID) {
        guard runID == run, UnicodeFontPackCatalog.acceptsProgress(received, expected: font.bytes) else { return }
        receivedByFont[font.asset.filename] = max(receivedByFont[font.asset.filename, default: 0], received)
        receivedBytes = min(pack.bytes, receivedByFont.values.reduce(0, +))
        progress = min(1, Double(receivedBytes) / Double(pack.bytes))
    }

    /// Cancels a queued or downloading pack; other queued packs continue.
    func cancel(_ pack: UnicodeFontPack) {
        if let index = queue.firstIndex(of: pack.id) { queue.remove(at: index); return }
        guard activePack == pack.id else { return }
        cancelledActive = true
        task?.cancel()
    }

    func remove(_ pack: UnicodeFontPack) {
        guard activePack != pack.id else { return }
        queue.removeAll { $0 == pack.id }
        failures[pack.id] = nil
        do {
            for font in pack.fonts { try store.remove(font) }
            message = "Download removed. Bundled fonts remain available."
        } catch { message = "Some font files could not be removed. Reopen this page and try again." }
        UnicodeFontSupport.clearCache()
        CatalogPreferences.shared.fontFilesChanged()
        reload()
    }

    private nonisolated static func fetch(_ font: UnicodeFontDownload, session: URLSession,
                                         store: UnicodeFontDownloadStore,
                                         progress: @escaping @Sendable (Int64) -> Void) async throws {
        guard font.isValid, let url = URL(string: font.downloadURL) else { throw UnicodeFontDownloadStore.Failure.invalidAsset }
        let budget = FontDownloadBudget(expected: font.bytes, progress: progress)
        let (temporary, response) = try await session.download(for: URLRequest(url: url), delegate: budget)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, UnicodeFontPackCatalog.allowsRedirect(finalURL),
              http.expectedContentLength < 0 || http.expectedContentLength == font.bytes else {
            throw UnicodeFontDownloadStore.Failure.invalidFont
        }
        try store.install(temporary, font: font)
    }
}

/// The system font picker, listing fonts installed on the device.
private struct InstalledFontPicker: UIViewControllerRepresentable {
    let picked: (String?) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = true
        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIFontPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let picked: (String?) -> Void
        init(picked: @escaping (String?) -> Void) { self.picked = picked }
        func fontPickerViewControllerDidPickFont(_ picker: UIFontPickerViewController) {
            picked(picker.selectedFontDescriptor.map { UIFont(descriptor: $0, size: 12).fontName })
        }
        func fontPickerViewControllerDidCancel(_ picker: UIFontPickerViewController) { picked(nil) }
    }
}

struct FontPackDownloadsView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    @StateObject private var downloads = FontPackDownloads.shared
    @State private var customFonts = CustomFontStore.shared.fonts
    @State private var importing = false
    @State private var importFailed = false
    @State private var pickingInstalled = false

    var body: some View {
        Form {
            Section {
                Toggle("Extra Unicode Fonts", isOn: Binding(get: { preferences.useUnicodeFonts },
                    set: { preferences.selectUnicodeFonts($0) }))
                    .accessibilityIdentifier("fontDownloads.enable")
                if downloads.remainingBytes > 0 {
                    Button {
                        downloads.downloadAll()
                    } label: {
                        LabeledContent {
                            Text(size(downloads.remainingBytes)).foregroundStyle(.secondary)
                        } label: {
                            Label("Download All", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(downloads.packs.filter { !downloads.isComplete($0) }.allSatisfy {
                        downloads.activePack == $0.id || downloads.queue.contains($0.id)
                    })
                    .accessibilityIdentifier("fontDownloads.downloadAll")
                }
                if downloads.downloadedBytes > 0 {
                    LabeledContent("Downloaded", value: size(downloads.downloadedBytes))
                }
            } footer: {
                Text("When iOS can’t draw a character or emoji, these fonts draw its preview in the app and keyboard. Downloads are optional, stored on this device and work offline, without Full Access. Other apps keep their own fonts.")
            }
            Section {
                ForEach(downloads.packs) { pack in
                    row(pack)
                        .swipeActions {
                            if downloads.stored.contains(pack.id) && downloads.activePack != pack.id {
                                Button("Remove", role: .destructive) { downloads.remove(pack) }
                            }
                        }
                }
            } header: {
                Text("Packs")
            } footer: {
                Text("Cancelling keeps completed fonts, and a retry downloads only what’s missing.")
            }
            Section {
                ForEach(customFonts) { font in
                    Text(font.displayName)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            try? CustomFontStore.shared.remove(font)
                            reloadCustomFonts()
                        }
                    }
                    .accessibilityIdentifier("fontDownloads.custom.\(font.filename)")
                }
                Button { importing = true } label: { Label("Add Font File", systemImage: "doc.badge.plus") }
                    .disabled(customFonts.count >= CustomFontStore.maximumFonts)
                    .accessibilityIdentifier("fontDownloads.addFont")
                Button { pickingInstalled = true } label: { Label("Use Installed Font", systemImage: "textformat") }
                    .disabled(customFonts.count >= CustomFontStore.maximumFonts)
                    .accessibilityIdentifier("fontDownloads.useInstalled")
                if importFailed {
                    Text("This file could not be added as a font.").foregroundStyle(.red)
                        .accessibilityIdentifier("fontDownloads.addFont.error")
                }
            } header: {
                Text("Your Fonts")
            }
            Section {
                if let message = downloads.message {
                    Text(message)
                        .accessibilityIdentifier("fontDownloads.message")
                }
            } footer: {
                Text("Downloads contact GitHub’s file CDN. No typing, search terms or favorites are included in download requests. Font licenses and source information are available in Settings.")
            }
        }
        .navigationTitle("Font Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { downloads.reload(); reloadCustomFonts() }
        .sheet(isPresented: $pickingInstalled) {
            InstalledFontPicker { name in
                pickingInstalled = false
                guard let name else { return }
                let added = try? CustomFontStore.shared.addInstalled(postScriptName: name)
                importFailed = added == nil
                if added != nil { preferences.selectUnicodeFonts(true) }
                reloadCustomFonts()
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.font]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let added = (try? Data(contentsOf: url)).flatMap { try? CustomFontStore.shared.add($0) }
            importFailed = added == nil
            if added != nil { preferences.selectUnicodeFonts(true) }
            reloadCustomFonts()
        }
    }

    /// Your fonts are tried before the packs, in the app and the keyboard.
    private func reloadCustomFonts() {
        customFonts = CustomFontStore.shared.fonts
        preferences.fontFilesChanged()
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    @ViewBuilder private func row(_ pack: UnicodeFontPack) -> some View {
        let active = downloads.activePack == pack.id
        let queued = downloads.queue.contains(pack.id)
        let complete = downloads.isComplete(pack)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.title).font(.headline)
                    Text(pack.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if active || queued {
                    Button { downloads.cancel(pack) } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel download")
                } else if complete {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                        .accessibilityHidden(true)
                } else {
                    Button { downloads.download(pack) } label: { Image(systemName: "arrow.down.circle").font(.title2) }
                        .accessibilityLabel(downloads.installed[pack.id, default: 0] == 0 ? "Download" : "Download remaining fonts")
                        .accessibilityIdentifier("fontDownloads.download.\(pack.id)")
                }
            }
            if active {
                ProgressView(value: downloads.progress)
                    .accessibilityIdentifier("fontDownloads.progress.\(pack.id)")
                Text("\(size(downloads.receivedBytes)) of \(size(pack.bytes))")
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            } else if queued {
                Text("Waiting · \(size(pack.bytes))").font(.footnote).foregroundStyle(.secondary)
            } else if let failure = downloads.failures[pack.id] {
                HStack {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { downloads.download(pack) }.font(.footnote.weight(.semibold))
                }
            } else if complete {
                HStack {
                    Text("Available offline · \(size(pack.bytes))").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) { downloads.remove(pack) }
                        .font(.footnote)
                        .accessibilityIdentifier("fontDownloads.remove.\(pack.id)")
                }
            } else {
                let count = downloads.installed[pack.id, default: 0]
                Text(count == 0 ? size(pack.bytes) : "\(count) of \(pack.fonts.count) fonts · \(size(pack.bytes))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fontDownloads.pack.\(pack.id)")
    }
}
