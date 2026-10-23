import SwiftUI
import UniformTypeIdentifiers

/// The keyboard's pages, configured here and shown there in this order:
/// Favorites, the Symbols page and any custom pages.
struct PagesView: View {
    var select: (UnicodeCharacter) -> Void
    @Binding var scratchpad: String
    @ObservedObject private var boards = SymbolBoardStore.shared
    @State private var naming = false
    @State private var newName = ""
    @State private var failed = false
    @State private var exporting = false
    @State private var importing = false

    var body: some View {
        List {
            Section {
                NavigationLink { MainKeyboardEditorView() } label: {
                    Label("Keyboard", systemImage: "keyboard")
                }
                .accessibilityIdentifier("pages.keyboard")
            }
            Section {
                ForEach(boards.boards) { board in
                    NavigationLink {
                        // Every page is edited as the keyboard draws it.
                        PageArrangeView(boardID: board.id, savedList: board.id == SymbolBoardStore.favoritesID
                                        ? AnyView(SavedView(select: select, scratchpad: $scratchpad)) : nil)
                    } label: {
                        PageRow(board: board, opensWithStar: board.id == boards.preferredStarBoardID)
                    }
                    .deleteDisabled(!Self.removable(board.id))
                    .accessibilityIdentifier("pages.page.\(board.id)")
                }
                .onMove { failed = !boards.moveBoards(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    let ids = offsets.map { boards.boards[$0].id }.filter(Self.removable)
                    failed = !ids.allSatisfy { boards.deleteBoard($0) }
                }
            }
            if failed {
                Text("This change could not be saved. Check the page file, name and storage limits.")
                    .foregroundStyle(.red).accessibilityIdentifier("pages.error")
            }
            if let issue = boards.loadIssue {
                Text(issue.rawValue).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pages")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { exporting = true } label: { Label("Export Pages", systemImage: "square.and.arrow.up") }
                        .disabled(boards.customPages.isEmpty)
                    Button { importing = true } label: { Label("Import Pages", systemImage: "square.and.arrow.down") }
                        .disabled(!boards.canEdit)
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More").accessibilityIdentifier("pages.more")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; naming = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New page").accessibilityIdentifier("pages.new")
                    .disabled(!boards.canEdit || boards.boards.count >= SymbolBoardStore.maximumBoards)
            }
        }
        .alert("New Page", isPresented: $naming) {
            TextField("Name", text: $newName).accessibilityIdentifier("pages.new.name")
            Button("Cancel", role: .cancel) {}
            Button("Create") { failed = boards.createBoard(named: newName) == nil }
        }
        .onAppear { boards.refreshPages() }
        .fileExporter(isPresented: $exporting, document: boards.exportedPages().map(PagesDocument.init),
                      contentType: .json, defaultFilename: "Uniboard Pages") { result in
            if case .failure = result { failed = true }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            failed = (try? Data(contentsOf: url)).flatMap(boards.importPages) == nil
        }
    }

    private static func removable(_ id: String) -> Bool {
        id != SymbolBoardStore.stockID && id != SymbolBoardStore.favoritesID
    }
}

/// A page file for the share sheet and Files.
private struct PagesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct PageRow: View {
    let board: SymbolBoard
    let opensWithStar: Bool
    var body: some View {
        let favorites = board.id == SymbolBoardStore.favoritesID
        Label {
            HStack {
                Text(board.name)
                Spacer(minLength: 8)
                if opensWithStar { Text("★").foregroundStyle(.secondary).accessibilityHidden(true) }
            }
        } icon: {
            Image(systemName: favorites ? "star.fill" : "square.grid.2x2")
                .foregroundStyle(favorites ? Color.yellow : Color.accentColor)
        }
        .accessibilityValue(opensWithStar ? "Opens with ★" : "")
    }
}

/// Typed text as separate characters, without line breaks.
func singleCharacters(_ text: String) -> [String] {
    text.filter { !$0.isNewline }.map(String.init)
}

/// Spaces, controls and lone combining marks need a visible stand-in.
func symbolKeyPreview(_ text: String) -> String {
    if text == " " { return "␠" }
    guard let first = text.unicodeScalars.first else { return "◌" }
    if text.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }) { return "◌" }
    if [.nonspacingMark, .spacingMark, .enclosingMark].contains(first.properties.generalCategory) { return "◌" + text }
    return text
}
