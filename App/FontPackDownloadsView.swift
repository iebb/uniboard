import SwiftUI

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
    @Published private(set) var progress: Double = 0
    @Published private(set) var installed: [String: Int] = [:]
    @Published private(set) var stored: Set<String> = []
    @Published private(set) var message: String?
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

    func download(_ pack: UnicodeFontPack) {
        guard activePack == nil, !pack.fonts.isEmpty else { return }
        guard store.directory != nil else {
            message = "Shared font storage is unavailable. Reopen the app and try again."
            return
        }
        let id = UUID()
        runID = id
        activePack = pack.id
        message = nil
        progress = 0
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
                message = "Downloaded. Enable Extra Unicode fonts to use these previews in the app and keyboard."
            } catch {
                if Task.isCancelled {
                    message = "Download cancelled. Completed fonts are kept; retry to download the rest."
                } else {
                    message = "The font download could not be verified. Check your connection and try again; completed fonts are kept."
                }
            }
            UnicodeFontSupport.clearCache()
            reload()
            activePack = nil
            runID = nil
            task = nil
        }
    }

    private func recordProgress(font: UnicodeFontDownload, received: Int64, pack: UnicodeFontPack, run: UUID) {
        guard runID == run, UnicodeFontPackCatalog.acceptsProgress(received, expected: font.bytes) else { return }
        receivedByFont[font.asset.filename] = max(receivedByFont[font.asset.filename, default: 0], received)
        progress = min(1, Double(receivedByFont.values.reduce(0, +)) / Double(pack.bytes))
    }

    func cancel() { task?.cancel() }

    func remove(_ pack: UnicodeFontPack) {
        guard activePack == nil else { return }
        do {
            for font in pack.fonts { try store.remove(font) }
            message = "Download removed. Bundled fonts remain available."
        } catch { message = "Some font files could not be removed. Reopen this page and try again." }
        UnicodeFontSupport.clearCache()
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

struct FontPackDownloadsView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    @StateObject private var downloads = FontPackDownloads.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Extra Unicode fonts", isOn: Binding(get: { preferences.useUnicodeFonts },
                    set: { preferences.selectUnicodeFonts($0) }))
                    .font(.headline).accessibilityIdentifier("fontDownloads.enable")
                Text("Keep the built-in fonts, or download just the extra previews you need. Downloads are optional, stored on this device, and work offline in both the app and keyboard without Full Access.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Text("Measured against iOS 27. Fonts improve previews only; other apps choose their own fonts. Some newer characters still have no suitable bundled or downloadable glyph.")
                    .font(.caption).foregroundStyle(Palette.muted)
                ForEach(UnicodeFontPackCatalog.bundled.packs) { pack in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(pack.title).font(.headline).foregroundStyle(Palette.ink)
                        Text(pack.detail).font(.subheadline).foregroundStyle(Palette.muted)
                        let count = downloads.installed[pack.id, default: 0]
                        Text("\(ByteCountFormatter.string(fromByteCount: pack.bytes, countStyle: .file)) · \(count)/\(pack.fonts.count) fonts downloaded")
                            .font(.caption).foregroundStyle(Palette.muted)
                        if downloads.activePack == pack.id {
                            ProgressView(value: downloads.progress)
                                .accessibilityIdentifier("fontDownloads.progress.\(pack.id)")
                            Button("Cancel download") { downloads.cancel() }
                        } else {
                            HStack {
                                if count < pack.fonts.count {
                                    Button(count == 0 ? "Download" : "Download remaining fonts") { downloads.download(pack) }
                                        .accessibilityIdentifier("fontDownloads.download.\(pack.id)")
                                } else { Label("Available offline", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                                Spacer()
                                if downloads.stored.contains(pack.id) {
                                    Button("Remove", role: .destructive) { downloads.remove(pack) }
                                        .accessibilityIdentifier("fontDownloads.remove.\(pack.id)")
                                }
                            }.disabled(downloads.activePack != nil)
                        }
                    }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("fontDownloads.pack.\(pack.id)")
                }
                if let message = downloads.message {
                    Text(message).font(.subheadline).foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("fontDownloads.message")
                }
                Text("Downloads contact GitHub’s file CDN. No typing, search terms or favorites are included in download requests. Font licenses and source information are available in Settings.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(20)
        }
        .background(Palette.background)
        .navigationTitle("Optional font downloads")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { downloads.reload() }
    }
}
