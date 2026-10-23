import SwiftUI

/// Inspection only: selecting a face or style never changes global font preferences.
struct FontFaceDetailView: View {
    private let face: FontFaceRecord?
    private let inspection: FontInspection?
    private let family: GoogleFontFamily?
    private let catalog: GoogleFontCatalog?
    private let coordinator: GoogleFontDownloadCoordinator?
    private let text: String?

    init(face: FontFaceRecord, inspection: FontInspection) {
        self.face = face; self.inspection = inspection
        family = nil; catalog = nil; coordinator = nil; text = nil
    }
    init(family: GoogleFontFamily, catalog: GoogleFontCatalog, coordinator: GoogleFontDownloadCoordinator, text: String? = nil) {
        self.family = family; self.catalog = catalog; self.coordinator = coordinator; self.text = text
        face = nil; inspection = nil
    }
    var body: some View {
        if let face, let inspection {
            LocalFontFaceDetail(face: face, inspection: inspection)
        } else if let family, let catalog, let coordinator {
            CatalogFontFaceDetail(family: family, catalog: catalog, coordinator: coordinator, text: text)
        }
    }
}

private struct LocalFontFaceDetail: View {
    let face: FontFaceRecord
    let inspection: FontInspection
    @StateObject private var browser = GoogleFontsViewModel()
    @StateObject private var licenses = FontReceiptViewModel()
    var body: some View {
        List {
            Section("Preview") {
                VerifiedFontPreview(face: face, inspection: inspection, pointSize: 144)
                    .frame(minHeight: 252).padding(.vertical, 16).accessibilityLabel("Preview of \(inspection.characterName)")
                Text(face.style)
                Text(face.source.explorationLabel)
                Text(codepoints(inspection.previewText)).font(.footnote.monospaced()).textSelection(.enabled)
                Text(fontPreviewDisclaimer).font(.footnote)
                Text("Available in the app only").font(.footnote).foregroundStyle(.secondary)
            }
            if let receipt = licenses.receipt {
                Section("License") {
                    ForEach(receipt.licenses, id: \.id) { license in
                        NavigationLink(license.name) { FontLicenseText(name: license.name, text: license.text) }
                    }
                }
            }
            if let failure = licenses.failure { Text(FontDownloadCopy.message(for: failure)) }
            if face.source == .downloaded, let catalog = browser.catalog, let coordinator = browser.coordinator,
               let selection = licenses.selection {
                NavigationLink("Manage Download") {
                    CatalogFontFaceDetail(family: selection.family, catalog: catalog, coordinator: coordinator,
                                          text: inspection.previewText,
                                          initialStyleID: selection.style.id)
                }
            }
        }
        .navigationTitle(face.family).navigationBarTitleDisplayMode(.inline)
        .task {
            if face.source == .downloaded {
                await browser.load()
                if let catalog = browser.catalog { await licenses.load(face: face, catalog: catalog) }
            }
        }
    }
}

/// File-keyed state is observed directly from the real download coordinator.
private struct CatalogFontFaceDetail: View {
    let family: GoogleFontFamily
    let catalog: GoogleFontCatalog
    @ObservedObject var coordinator: GoogleFontDownloadCoordinator
    let text: String?
    @StateObject private var licenses = FontReceiptViewModel()
    @State private var selectedStyleID: String
    @State private var confirmingRemoval = false
    @State private var operationError: String?
    @State private var verifiedFace: FontFaceRecord?
    @State private var checkingPreview = false
    @State private var previewMessage = "Exact font support could not be verified."
    @State private var previewRevision = UUID()
    @State private var operationRunning = false
    /// 17pt at the default size; scales with the body text style at larger (accessibility) sizes.
    @ScaledMetric(relativeTo: .body) private var styleIconSize: CGFloat = 17

    init(family: GoogleFontFamily, catalog: GoogleFontCatalog, coordinator: GoogleFontDownloadCoordinator,
         text: String?, initialStyleID: String? = nil) {
        self.family = family; self.catalog = catalog; self.coordinator = coordinator; self.text = text
        _selectedStyleID = State(initialValue: initialStyleID ?? FontDetailSelection.defaultStyleID(in: family))
    }
    private var style: GoogleFontStyle? { family.styles.first { $0.id == selectedStyleID } }
    private var file: GoogleFontFile? { style.flatMap { catalog.file(id: $0.fileID) } }
    private var state: GoogleFontDownloadState { file.flatMap { coordinator.states[$0.id] } ?? .ready }
    private var inspection: FontInspection { FontInspection(originalText: text ?? "Aa", characterName: text == nil ? "Sample" : "Selected character") }
    private var isDownloaded: Bool { if case .downloaded = state { return true }; return false }

    var body: some View {
        List {
            Section {
                Text("Google Fonts").foregroundStyle(.secondary)
                Text("Downloaded fonts are for use in Uniboard. They aren’t installed for other apps.").font(.footnote)
                Text("Catalog snapshot: \(catalog.snapshot.snapshotDate)").font(.caption)
            }
            Section("Styles") {
                ForEach(family.styles) { option in
                    let target = catalog.file(id: option.fileID)
                    let status = target.map { StyleFileStatus(file: $0, state: coordinator.states[$0.id]) }
                    Button {
                        selectedStyleID = option.id
                        operationError = nil
                        verifiedFace = nil
                        previewRevision = UUID()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            // Label colors, not the button tint: only the icons carry the accent.
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.name).font(.body).foregroundStyle(Color(uiColor: .label))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let target {
                                    Text(ByteCountFormatter.string(fromByteCount: target.bytes, countStyle: .file))
                                        .font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if selectedStyleID == option.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: styleIconSize)).foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                            if let status { styleStatusIcon(status) }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("fontDetail.style.\(option.id)")
                        .accessibilityValue(status?.accessibilityValue ?? Text(verbatim: ""))
                        .accessibilityAddTraits(selectedStyleID == option.id ? .isSelected : [])
                        .disabled(operationRunning)
                }
                if let file {
                    Text("File: \(file.repositoryPath)").font(.caption).textSelection(.enabled)
                    if family.styles.filter({ $0.fileID == file.id }).count > 1 {
                        Text("These styles share one font file. Downloading or removing it affects all styles in that file.").font(.footnote)
                    }
                }
            }
            Section("Preview") {
                if let verifiedFace {
                    VerifiedFontPreview(face: verifiedFace, inspection: inspection, pointSize: 144)
                        .frame(minHeight: 252).padding(.vertical, 16).accessibilityIdentifier("fontDetail.verifiedPreview")
                } else if checkingPreview {
                    ProgressView("Checking available fonts…")
                } else if isDownloaded {
                    Text("Preview unavailable").font(.headline)
                    Text(previewMessage).font(.footnote)
                    Button("Check Again") { previewRevision = UUID() }
                } else {
                    Text("Download this style to preview it here")
                }
                Text(codepoints(inspection.previewText)).font(.footnote.monospaced()).textSelection(.enabled)
                Text(fontPreviewDisclaimer).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if let failure = coordinator.libraryFailure { Text(FontDownloadCopy.message(for: failure)) }
                downloadControls
                if let operationError { Text(operationError).foregroundStyle(.red) }
                Text("Up to 16 imported, installed or downloaded font files; 40 MiB maximum per file. Remove a downloaded font or manage Your Fonts in Font Downloads to make room.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let file, let reason = file.unavailableReason {
                    Text(reason).font(.footnote)
                    Text("Choose another style or file.").font(.footnote)
                }
            }
            Section("License") {
                if let failure = licenses.failure { Text(FontDownloadCopy.message(for: failure)) }
                if let file {
                    if let receipt = licenses.receipt, receipt.fileID == file.id {
                        ForEach(receipt.licenses, id: \.id) { license in
                            NavigationLink(license.name) { FontLicenseText(name: license.name, text: license.text) }
                        }
                    } else {
                        ForEach(file.licenseIDs, id: \.self) { id in
                            if let license = catalog.license(id: id) {
                                NavigationLink(license.name) { FontLicenseText(name: license.name, text: license.text) }
                            }
                        }
                    }
                }
            }
            if isDownloaded {
                Section {
                    Button("Remove Download", role: .destructive) { confirmingRemoval = true }.accessibilityIdentifier("fontDetail.remove")
                        .disabled(operationRunning)
                }
            }
        }
        .navigationTitle(family.name).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(family.name) \(style?.name ?? "")?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) { perform(.remove) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the downloaded font from Uniboard. You can download it again later.")
        }
        .task(id: previewRevision) {
            if let file, isDownloaded, licenses.receipt?.fileID != file.id { await licenses.load(fileID: file.id) }
            await checkPreview()
        }
        .onChange(of: state) { _, _ in previewRevision = UUID() }
    }

    /// Decorative: the row's accessibilityValue carries the same state for VoiceOver.
    @ViewBuilder private func styleStatusIcon(_ status: StyleFileStatus) -> some View {
        Group {
            switch status {
            case .notDownloaded:
                Image(systemName: "arrow.down.circle").font(.system(size: styleIconSize)).foregroundStyle(.tint)
            case .downloading:
                ProgressView().controlSize(.small).tint(.accentColor)
                    .frame(minWidth: styleIconSize, minHeight: styleIconSize)
            case .downloaded:
                Image(systemName: "checkmark.circle.fill").font(.system(size: styleIconSize)).foregroundStyle(.tint)
            case .unavailable:
                Image(systemName: "exclamationmark.circle").font(.system(size: styleIconSize))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var downloadControls: some View {
        switch state {
        case .ready, .cancelled:
            if state == .cancelled { Text("Download cancelled") }
            downloadButton("Download Style")
        case .queued:
            ProgressView("Waiting to download…")
            Button("Cancel") { perform(.cancel) }
        case .downloading(let received, let expected):
            if let expected, expected > 0 {
                ProgressView(value: min(Double(received) / Double(expected), 1))
                Text("Downloading… \(min(100, Int(Double(received) / Double(expected) * 100)))%")
            } else { ProgressView("Downloading…") }
            Button("Cancel") { perform(.cancel) }
        case .preparing: ProgressView("Preparing font…")
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle").accessibilityIdentifier("fontDetail.downloaded")
            Text("Available in the app only").font(.footnote)
        case .failed(let failure):
            Text(FontDownloadCopy.message(for: failure))
            downloadButton("Try Again")
        }
    }
    private func downloadButton(_ label: String) -> some View {
        Button(label) { perform(.download) }.accessibilityIdentifier("fontDetail.download")
            .disabled(operationRunning || file == nil || file?.unavailableReason != nil || (file?.bytes ?? 0) > GoogleFontCatalog.maximumFileBytes)
    }
    private enum Operation { case download, cancel, remove }
    private func perform(_ operation: Operation) {
        guard let style, let file else { return }
        operationError = nil
        if operation != .cancel { operationRunning = true }
        Task { @MainActor in
            defer {
                operationRunning = false
                previewRevision = UUID()
                NotificationCenter.default.post(name: .fontExplorationLibraryChanged, object: nil)
            }
            do {
                switch operation {
                case .download: try await coordinator.download(styleID: style.id)
                case .cancel: try await coordinator.cancel(fileID: file.id)
                case .remove: try await coordinator.remove(fileID: file.id)
                }
            } catch is CancellationError {
                // The coordinator publishes the authoritative cancelled state.
            } catch let failure as FontLibraryFailure {
                operationError = FontDownloadCopy.message(for: failure)
            } catch { operationError = operation == .remove ? "Couldn’t remove this download. Try again in a moment." : "Couldn’t download this font. Try again in a moment." }
        }
    }
    private func checkPreview() async {
        let revision = previewRevision
        verifiedFace = nil
        guard isDownloaded, let file, let style else { checkingPreview = false; return }
        checkingPreview = true
        previewMessage = inspection.isApplicable ? "Exact font support could not be verified." : "Font preview is not applicable to this invisible character."
        defer { if revision == previewRevision { checkingPreview = false } }
        let engine = FontComparisonEngine()
        do {
            for try await update in await engine.scan(inspection) {
                guard !Task.isCancelled, revision == previewRevision else { return }
                if let face = update.verified.first(where: { FontDetailIdentity.matches($0, file: file, style: style) }) {
                    verifiedFace = face
                    return
                }
                if update.isComplete, update.unknownCount == 0, inspection.isApplicable {
                    previewMessage = "This font couldn’t display the character."
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            previewMessage = "Couldn’t check font support. Try again in a moment."
        }
    }
}

/// Per-file status shown on every style row; styles sharing a file share this state.
private enum StyleFileStatus: Equatable {
    case notDownloaded, downloading, downloaded
    case unavailable(reason: String)

    init(file: GoogleFontFile, state: GoogleFontDownloadState?) {
        switch state ?? .ready {
        case .downloaded: self = .downloaded
        case .queued, .downloading, .preparing: self = .downloading
        case .ready, .cancelled, .failed:
            if let reason = file.unavailableReason {
                self = .unavailable(reason: reason)
            } else if file.bytes > GoogleFontCatalog.maximumFileBytes {
                self = .unavailable(reason: FontDownloadCopy.message(for: .tooLarge(limitBytes: GoogleFontCatalog.maximumFileBytes)))
            } else {
                self = .notDownloaded
            }
        }
    }

    var accessibilityValue: Text {
        switch self {
        case .notDownloaded: return Text("Not downloaded")
        case .downloading: return Text("Downloading")
        case .downloaded: return Text("Downloaded")
        case .unavailable(let reason): return Text(verbatim: reason)
        }
    }
}

enum FontDetailSelection {
    static func defaultStyleID(in family: GoogleFontFamily) -> String {
        family.styles.first(where: { $0.name.caseInsensitiveCompare("Regular") == .orderedSame })?.id
            ?? family.styles.first?.id ?? ""
    }
}

enum FontDownloadCopy {
    static func message(for failure: FontLibraryFailure) -> String {
        switch failure {
        case .offline: return "No internet connection. Connect to the internet to browse and download fonts."
        case .invalidFile, .registration: return "Couldn’t use this font. The downloaded file couldn’t be loaded."
        case .tooLarge: return "This file exceeds the 40 MiB per-file limit. Choose another style or file."
        case .tooMany(let limit): return "The \(limit)-font limit has been reached. Remove a downloaded font or manage Your Fonts in Font Downloads, then try again."
        case .storageUnavailable: return "Font storage is unavailable. Reopen Uniboard and try again."
        case .storageFailure: return "Couldn’t save this font. Check available storage, then try again."
        case .transport: return "Couldn’t download this font. Try again in a moment."
        }
    }
}

private struct FontLicenseText: View {
    let name: String
    let text: String
    var body: some View {
        ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    }
}

/// Storage is read once per requested receipt/operation, never from View.body.
@MainActor
private final class FontReceiptViewModel: ObservableObject {
    @Published private(set) var receipt: FontLibraryReceipt?
    @Published private(set) var selection: FontCatalogFaceSelection?
    @Published private(set) var failure: FontLibraryFailure?
    private var request = UUID()
    func load(face: FontFaceRecord, catalog: GoogleFontCatalog) async {
        let token = UUID()
        request = token
        do {
            let state = try await Task.detached(priority: .userInitiated) {
                try CustomFontStore.shared.readLibraryState()
            }.value
            guard token == request, !Task.isCancelled else { return }
            selection = FontDetailIdentity.selection(for: face, catalog: catalog, state: state)
            receipt = selection.flatMap { state.receipts[$0.style.fileID] }
            failure = nil
        } catch {
            guard token == request, !Task.isCancelled else { return }
            failure = (error as? FontLibraryFailure) ?? .storageFailure
        }
    }
    func load(fileID: String) async {
        let token = UUID()
        request = token
        do {
            let state = try await Task.detached(priority: .userInitiated) {
                try CustomFontStore.shared.readLibraryState()
            }.value
            guard token == request, !Task.isCancelled else { return }
            receipt = state.receipts[fileID]
            failure = nil
        } catch {
            guard token == request, !Task.isCancelled else { return }
            failure = (error as? FontLibraryFailure) ?? .storageFailure
        }
    }
}

struct FontCatalogFaceSelection {
    let family: GoogleFontFamily
    let style: GoogleFontStyle
}

/// Persisted IDs are navigation identities; aliases may have the same physical face.
enum FontDetailIdentity {
    static func matches(_ face: FontFaceRecord, file: GoogleFontFile, style: GoogleFontStyle) -> Bool {
        guard style.fileID == file.id, case let .file(_, _, index, axes) = face.locator, index == 0,
              PublicFontInventory.canonicalAxes(axes) != nil,
              PublicFontInventory.canonicalAxes(style.variationInstance ?? [:]) != nil else { return false }
        let requested = FontLocator.file(relativePath: "", sha256: file.sha256, faceIndex: 0,
                                         variations: style.variationInstance ?? [:])
        return PublicFontInventory.identity(face.locator) == PublicFontInventory.identity(requested)
    }

    static func selection(for face: FontFaceRecord, catalog: GoogleFontCatalog,
                          state: FontLibraryReadState) -> FontCatalogFaceSelection? {
        guard case let .file(path, _, _, _) = face.locator else { return nil }
        let candidates = catalog.snapshot.families.flatMap { family in
            family.styles.compactMap { style -> FontCatalogFaceSelection? in
                guard let file = catalog.file(id: style.fileID),
                      let asset = state.assetIDs[file.id],
                      asset == face.assetID || asset == path,
                      let receipt = state.receipts[file.id], receipt.sha256 == file.sha256,
                      matches(face, file: file, style: style) else { return nil }
                return FontCatalogFaceSelection(family: family, style: style)
            }
        }
        func rank(_ candidate: FontCatalogFaceSelection) -> Int {
            if face.id.rawValue == "google:\(candidate.style.fileID):\(candidate.style.id)" { return 0 }
            if face.family == candidate.family.name && face.style == candidate.style.name { return 1 }
            return 2
        }
        return candidates.sorted {
            (rank($0), $0.family.id, $0.style.id) < (rank($1), $1.family.id, $1.style.id)
        }.first
    }
}
