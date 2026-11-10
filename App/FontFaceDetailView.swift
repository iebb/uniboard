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
    /// nil until the user picks a cell: the grid's default cell is selected.
    @State private var selectedStyleID: String?
    @StateObject private var samples = StyleSampleLoader()
    @State private var operationError: String?
    @State private var verifiedFace: FontFaceRecord?
    @State private var checkingPreview = false
    @State private var previewMessage = "Exact font support could not be verified."
    @State private var previewRevision = UUID()
    @State private var operationRunning = false

    init(family: GoogleFontFamily, catalog: GoogleFontCatalog, coordinator: GoogleFontDownloadCoordinator,
         text: String?, initialStyleID: String? = nil) {
        self.family = family; self.catalog = catalog; self.coordinator = coordinator; self.text = text
        _selectedStyleID = State(initialValue: initialStyleID)
    }
    /// Built from the coordinator's file states, so the downloaded copy of a
    /// duplicated face is the one shown and selected.
    private var grid: StyleGrid {
        let downloaded = coordinator.states.compactMap { id, state -> String? in
            if case .downloaded = state { return id }; return nil
        }
        return StyleGrid.make(family: family, catalog: catalog, downloadedFileIDs: Set(downloaded))
    }
    /// The selected cell and its set; a style hidden as a duplicate selects the cell showing its face.
    private func selection(in grid: StyleGrid) -> (set: StyleGrid.StyleSet, cell: StyleGrid.Cell)? {
        selectedStyleID.flatMap { grid.location(of: $0) } ?? grid.defaultCell
    }
    private var current: (set: StyleGrid.StyleSet, cell: StyleGrid.Cell)? { selection(in: grid) }
    private var style: GoogleFontStyle? {
        let id = current?.cell.style.id ?? selectedStyleID
        return family.styles.first { $0.id == id }
    }
    /// The repository file the style comes from (licenses, availability).
    private var file: GoogleFontFile? { style.flatMap { catalog.file(id: $0.fileID) } }
    private var ownFile: StyleGridDownload? { current.flatMap { grid.ownFile(of: $0.cell) } }
    private var sharedFile: StyleGridDownload? { current.flatMap { grid.sharedFile(of: $0.cell) } }
    private func state(_ download: StyleGridDownload?) -> GoogleFontDownloadState {
        download.flatMap { coordinator.states[$0.id] } ?? .ready
    }
    private func isDownloaded(_ download: StyleGridDownload?) -> Bool {
        if case .downloaded = state(download) { return download != nil }; return false
    }
    private var anyDownloaded: Bool { isDownloaded(ownFile) || isDownloaded(sharedFile) }
    /// The file that draws the style: own first (§8).
    private var drawingFile: StyleGridDownload? {
        isDownloaded(ownFile) ? ownFile : isDownloaded(sharedFile) ? sharedFile : nil
    }
    private var inspection: FontInspection { FontInspection(originalText: text ?? "Aa", characterName: text == nil ? "Sample" : "Selected character") }
    private var noRoom: Bool { coordinator.freeFileSpaces == 0 }

    var body: some View {
        List {
            Section {
                Text("Google Fonts").foregroundStyle(.secondary)
                Text("Downloaded fonts are for use in Uniboard. They aren’t installed for other apps.").font(.footnote)
                Text("Catalog snapshot: \(catalog.snapshot.snapshotDate)").font(.caption)
            }
            stylesSection
            Section("Preview") {
                if let verifiedFace {
                    VerifiedFontPreview(face: verifiedFace, inspection: inspection, pointSize: 144)
                        .frame(minHeight: 252).padding(.vertical, 16).accessibilityIdentifier("fontDetail.verifiedPreview")
                } else if checkingPreview {
                    ProgressView("Checking available fonts…")
                } else if anyDownloaded {
                    Text("Preview unavailable").font(.headline)
                    Text(previewMessage).font(.footnote)
                    Button("Check Again") { previewRevision = UUID() }
                } else {
                    Text("Download this style to preview it here")
                }
                Text(codepoints(inspection.previewText)).font(.footnote.monospaced()).textSelection(.enabled)
                Text(fontPreviewDisclaimer).font(.footnote).foregroundStyle(.secondary)
            }
            Section("License") {
                if let failure = licenses.failure { Text(FontDownloadCopy.message(for: failure)) }
                if let file {
                    if let receipt = licenses.receipt, receipt.fileID == drawingFile?.id {
                        ForEach(receipt.licenses, id: \.id) { license in
                            NavigationLink(license.name) { FontLicenseText(name: license.name, text: license.text) }
                        }
                    } else {
                        // A single-style instance carries its repository file's licenses.
                        ForEach(file.licenseIDs, id: \.self) { id in
                            if let license = catalog.license(id: id) {
                                NavigationLink(license.name) { FontLicenseText(name: license.name, text: license.text) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(family.name).navigationBarTitleDisplayMode(.inline)
        .task(id: previewRevision) {
            coordinator.refreshLibrary()
            if let drawing = drawingFile, licenses.receipt?.fileID != drawing.id { await licenses.load(fileID: drawing.id) }
            await checkPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fontExplorationLibraryChanged)) { _ in previewRevision = UUID() }
        .onChange(of: state(ownFile)) { _, _ in previewRevision = UUID() }
        .onChange(of: state(sharedFile)) { _, _ in previewRevision = UUID() }
    }

    /// §6's derived name ("Condensed Bold", "Bold Italic"), not the catalog's.
    private var selectedName: String {
        let grid = grid
        return selection(in: grid).map { grid.displayName(of: $0.cell, in: $0.set) } ?? style?.name ?? ""
    }

    /// Exactly like today's row button: selecting resets the error and the preview.
    private func select(_ cell: StyleGrid.Cell) {
        selectedStyleID = cell.style.id
        operationError = nil
        verifiedFace = nil
        previewRevision = UUID()
    }

    /// design/styles-grid-1.4: the Variant menu (non-width sets only), the
    /// grid, the selected style and its rows, with the capacity footer (§7).
    private var stylesSection: some View {
        let grid = grid
        let current = selection(in: grid)
        return Section {
            if let current {
                if let title = grid.menuTitle {
                    Picker(title, selection: Binding(get: { current.set.id }, set: { id in
                        guard let set = grid.sets.first(where: { $0.id == id }) else { return }
                        select(grid.cell(switchingFrom: current.cell, to: set))
                    })) {
                        ForEach(grid.sets) { Text($0.option).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .disabled(operationRunning)
                    .accessibilityIdentifier("fontDetail.styleSet")
                }
                StyleGridView(grid: grid, set: current.set, selectedStyleID: current.cell.style.id,
                              files: gridFiles, states: coordinator.states, sampleText: text,
                              disabled: operationRunning, samples: samples, select: select)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                selectedStyleRow(grid: grid, current: current)
            } else {
                Text(StyleGridCopy.noStyles).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            if let failure = coordinator.libraryFailure { Text(FontDownloadCopy.message(for: failure)) }
            if current != nil { actionRows(grid: grid) }
            if let operationError { Text(operationError).foregroundStyle(.red) }
            if let file, let reason = file.unavailableReason {
                Text(reason).font(.footnote)
                Text("Choose another style or file.").font(.footnote)
            }
        } header: {
            Text("Styles")
        } footer: {
            Text(FontFileManagementCopy.remaining(coordinator.freeFileSpaces) + " 40 MiB maximum per file.")
                .accessibilityIdentifier("fontDetail.capacity")
        }
    }

    private var gridFiles: [String: GoogleFontFile] {
        Dictionary(family.styles.compactMap { catalog.file(id: $0.fileID) }.map { ($0.id, $0) }) { first, _ in first }
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// §6 row 1: the name; the file(s) giving the style (both when both are
    /// downloaded, case G, smallest first); the shared-only note.
    private func selectedStyleRow(grid: StyleGrid, current: (set: StyleGrid.StyleSet, cell: StyleGrid.Cell)) -> some View {
        let own = grid.ownFile(of: current.cell)
        let shared = grid.sharedFile(of: current.cell)
        let listed: [StyleGridDownload]
        if isDownloaded(own) && isDownloaded(shared) {
            listed = [own!, shared!].sorted { $0.bytes < $1.bytes }
        } else {
            listed = [own ?? shared].compactMap { $0 }
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(grid.displayName(of: current.cell, in: current.set)).font(.body).foregroundStyle(Color(uiColor: .label))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(listed, id: \.id) { item in
                    Text(verbatim: item.filename + " · " + size(item.bytes))
                }
            }
            .font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel)).textSelection(.enabled)
            if own == nil, let shared {
                Text(StyleGridCopy.sharedOnly(shared.styleCount))
                    .font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// §6 action rows: downloaded rows once, then the own file's row, then the shared file's.
    @ViewBuilder private func actionRows(grid: StyleGrid) -> some View {
        let own = ownFile, shared = sharedFile
        if anyDownloaded {
            Label("Downloaded", systemImage: "checkmark.circle").accessibilityIdentifier("fontDetail.downloaded")
        }
        // Case E: no single download once the shared file gives the style.
        let showsOwn = own != nil && !(isDownloaded(shared) && !isDownloaded(own) && isIdle(own!))
        if let own, showsOwn {
            fileRows(own, grid: grid, isOwn: true, other: shared, secondary: false)
        }
        if let shared {
            fileRows(shared, grid: grid, isOwn: false, other: own, secondary: showsOwn)
        }
    }

    private func isIdle(_ download: StyleGridDownload) -> Bool {
        switch state(download) {
        case .ready, .cancelled, .failed: return true
        default: return false
        }
    }

    /// `secondary`: the shared file's row under the own file's; identifiers get ".file".
    @ViewBuilder private func fileRows(_ download: StyleGridDownload, grid: StyleGrid, isOwn: Bool, other: StyleGridDownload?,
                                       secondary: Bool) -> some View {
        let suffix = secondary ? ".file" : ""
        switch state(download) {
        case .ready, .cancelled, .failed:
            if state(download) == .cancelled { Text("Download cancelled") }
            if case .failed(let failure) = state(download) { Text(FontDownloadCopy.message(for: failure)) }
            let retry: Bool = { if case .failed = state(download) { return true }; return false }()
            actionButton(title: retry ? "Try Again" : (isOwn ? StyleGridCopy.downloadStyle(selectedName) : StyleGridCopy.downloadFile(download.styleCount)),
                         caption: isOwn ? nil : downloadCaption(download, grid: grid), size: download.bytes, role: nil,
                         identifier: "fontDetail.download" + suffix) { perform(.download, download) }
                .disabled(operationRunning || noRoom || !downloadable(download))
        case .queued:
            ProgressView("Waiting to download…")
            Button("Cancel") { perform(.cancel, download) }.accessibilityIdentifier("fontDetail.cancel" + suffix)
        case .downloading(let received, let expected):
            if let expected, expected > 0 {
                let percent = min(100, Int(Double(received) / Double(expected) * 100))
                ProgressView(value: min(Double(received) / Double(expected), 1))
                Text(isOwn ? StyleGridCopy.downloadingStyle(selectedName, percent: percent)
                     : StyleGridCopy.downloadingFile(download.styleCount, percent: percent))
            } else { ProgressView("Downloading…") }
            Button("Cancel") { perform(.cancel, download) }.accessibilityIdentifier("fontDetail.cancel" + suffix)
        case .preparing: ProgressView("Preparing font…")
        case .downloaded:
            // All removal paths share the file-oriented reference check and
            // guarded confirmation. A catalog receipt is not a separate file.
            NavigationLink {
                FontFileDetailView(receiptID: download.id)
            } label: {
                Label("Manage File", systemImage: "doc")
            }
            .accessibilityIdentifier("fontDetail.manage" + suffix)

        }
    }

    /// "Includes {n} styles in one file." + " Existing downloads are kept." + the width line.
    private func downloadCaption(_ shared: StyleGridDownload, grid: StyleGrid) -> String {
        let kept = grid.cells(coveredBy: shared.id).contains { cell in
            grid.ownFile(of: cell).map { coordinator.states[$0.id].map { if case .downloaded = $0 { return true }; return false } ?? false } ?? false
        }
        var caption = StyleGridCopy.includes(shared.styleCount) + (kept ? StyleGridCopy.existingKept : "")
        if let line = grid.coverageLine(fileID: shared.id) { caption += "\n" + line }
        return caption
    }

    private func downloadable(_ download: StyleGridDownload) -> Bool {
        guard let file, file.unavailableReason == nil else { return false }
        return download.bytes <= GoogleFontCatalog.maximumFileBytes
    }

    /// Title in tint (or red), 17 pt; the size trailing, part of the hit area.
    private func actionButton(title: String, caption: String?, size bytes: Int64?, role: ButtonRole?, identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    if let caption {
                        Text(caption).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let bytes {
                    Text(size(bytes)).font(.body).monospacedDigit().foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }

    private enum Operation { case download, cancel }
    private func perform(_ operation: Operation, _ download: StyleGridDownload) {
        guard let style else { return }
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
                case .download: try await coordinator.download(styleID: style.id, scope: download.isInstance ? .instance : .file)
                case .cancel: try await coordinator.cancel(fileID: download.id)
                }
            } catch is CancellationError {
                // The coordinator publishes the authoritative cancelled state.
            } catch let failure as FontLibraryFailure {
                operationError = FontDownloadCopy.message(for: failure)
            } catch { operationError = "Couldn’t download this font. Try again in a moment." }
        }
    }
    private func checkPreview() async {
        let revision = previewRevision
        verifiedFace = nil
        guard anyDownloaded, let file, let style else { checkingPreview = false; return }
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

/// Per-file status behind the styles grid's badges and VoiceOver values; styles sharing a file share this state.
enum StyleFileStatus: Equatable {
    case notDownloaded, downloading, downloaded
    case unavailable(reason: String)

    init(file: GoogleFontFile, state: GoogleFontDownloadState?) {
        self.init(unavailableReason: file.unavailableReason, bytes: file.bytes, state: state)
    }

    init(unavailableReason: String?, bytes: Int64, state: GoogleFontDownloadState?) {
        switch state ?? .ready {
        case .downloaded: self = .downloaded
        case .queued, .downloading, .preparing: self = .downloading
        case .ready, .cancelled, .failed:
            if let reason = unavailableReason {
                self = .unavailable(reason: reason)
            } else if bytes > GoogleFontCatalog.maximumFileBytes {
                self = .unavailable(reason: FontDownloadCopy.message(for: .tooLarge(limitBytes: GoogleFontCatalog.maximumFileBytes)))
            } else {
                self = .notDownloaded
            }
        }
    }

    /// VoiceOver's value for a style cell or file header.
    var label: String {
        switch self {
        case .notDownloaded: return "Not downloaded"
        case .downloading: return "Downloading"
        case .downloaded: return "Downloaded"
        case .unavailable(let reason): return reason
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
            receipt = selection.flatMap { selection in
                selection.style.instance.flatMap { face.locatorSHA == $0.sha256 ? state.receipts[$0.id] : nil } ?? state.receipts[selection.style.fileID]
            }
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

extension FontFaceRecord {
    var locatorSHA: String? { if case let .file(_, sha256, _, _) = locator { return sha256 }; return nil }
}

struct FontCatalogFaceSelection {
    let family: GoogleFontFamily
    let style: GoogleFontStyle
}

/// Persisted IDs are navigation identities; aliases may have the same physical face.
enum FontDetailIdentity {
    /// The style's face from its repository file (with its instance
    /// coordinates) or from its pinned single-style instance (none).
    static func matches(_ face: FontFaceRecord, file: GoogleFontFile, style: GoogleFontStyle) -> Bool {
        guard style.fileID == file.id, case let .file(_, sha256, index, axes) = face.locator, index == 0,
              PublicFontInventory.canonicalAxes(axes) != nil,
              PublicFontInventory.canonicalAxes(style.variationInstance ?? [:]) != nil else { return false }
        if let instance = style.instance, sha256 == instance.sha256 {
            return PublicFontInventory.identity(face.locator)
                == PublicFontInventory.identity(.file(relativePath: "", sha256: instance.sha256, faceIndex: 0, variations: [:]))
        }
        let requested = FontLocator.file(relativePath: "", sha256: file.sha256, faceIndex: 0,
                                         variations: style.variationInstance ?? [:])
        return PublicFontInventory.identity(face.locator) == PublicFontInventory.identity(requested)
    }

    static func selection(for face: FontFaceRecord, catalog: GoogleFontCatalog,
                          state: FontLibraryReadState) -> FontCatalogFaceSelection? {
        guard case let .file(path, _, _, _) = face.locator else { return nil }
        let candidates = catalog.snapshot.families.flatMap { family in
            family.styles.compactMap { style -> FontCatalogFaceSelection? in
                guard let file = catalog.file(id: style.fileID), matches(face, file: file, style: style) else { return nil }
                // The downloaded file this face record lives in: the repository file or the style's instance.
                let downloadID = style.instance.map { face.locatorSHA == $0.sha256 ? $0.id : file.id } ?? file.id
                let sha = downloadID == file.id ? file.sha256 : style.instance!.sha256
                guard let asset = state.assetIDs[downloadID], asset == face.assetID || asset == path,
                      let receipt = state.receipts[downloadID], receipt.sha256 == sha else { return nil }
                return FontCatalogFaceSelection(family: family, style: style)
            }
        }
        func rank(_ candidate: FontCatalogFaceSelection) -> Int {
            if face.id.rawValue == "google:\(candidate.style.fileID):\(candidate.style.id)"
                || face.id.rawValue == "google:\(GoogleFontCatalog.instanceIDPrefix)\(candidate.style.id)" { return 0 }
            if face.family == candidate.family.name && face.style == candidate.style.name { return 1 }
            return 2
        }
        return candidates.sorted {
            (rank($0), $0.family.id, $0.style.id) < (rank($1), $1.family.id, $1.style.id)
        }.first
    }
}
