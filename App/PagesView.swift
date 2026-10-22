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
                ForEach(boards.boards) { board in
                    NavigationLink {
                        if board.id == SymbolBoardStore.favoritesID {
                            SavedView(select: select, scratchpad: $scratchpad)
                        } else {
                            PageEditorView(boardID: board.id, select: select)
                        }
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

/// One page's keys, in the keyboard's order. Each key can carry variants,
/// which the keyboard offers when the key is held.
struct PageEditorView: View {
    let boardID: String
    var select: (UnicodeCharacter) -> Void
    @ObservedObject private var boards = SymbolBoardStore.shared
    @State private var picking = false
    @State private var typing = false
    @State private var typed = ""
    @State private var renaming = false
    @State private var name = ""
    @State private var failed = false
    private var board: SymbolBoard? { boards.boards.first { $0.id == boardID } }

    var body: some View {
        List {
            if let board {
                Section {
                    NavigationLink("Arrange Keys") { PageArrangeView(boardID: boardID) }
                        .accessibilityIdentifier("page.arrange")
                }
                Section {
                    ForEach(Array(board.keys.enumerated()), id: \.element.id) { index, key in
                        NavigationLink { KeyVariantsView(boardID: boardID, keyID: key.id) } label: { KeyRow(key: key) }
                            .accessibilityIdentifier("page.key.\(index)")
                    }
                    .onMove { failed = !boards.moveKeys(boardID: boardID, fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        let ids = offsets.map { board.keys[$0].id }
                        failed = !ids.allSatisfy { boards.removeKey(boardID: boardID, keyID: $0) }
                    }
                    Button { picking = true } label: { Label("Add from Unicode", systemImage: "character.book.closed") }
                        .accessibilityIdentifier("page.addUnicode")
                    Button { typed = ""; typing = true } label: { Label("Add Text", systemImage: "plus") }
                        .accessibilityIdentifier("page.addText")
                } header: {
                    Text("Keys")
                }
                Section {
                    Toggle("Opens with ★", isOn: Binding(get: { boards.preferredStarBoardID == boardID }, set: { on in
                        failed = !boards.setPreferredStarBoard(on ? boardID : SymbolBoardStore.favoritesID)
                    }))
                    .accessibilityIdentifier("page.star")
                }
            }
            if failed {
                Text("This change could not be saved. Check the text and storage limits.")
                    .foregroundStyle(.red).accessibilityIdentifier("page.error")
            }
        }
        .navigationTitle(board?.name ?? "Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename") { name = board?.name ?? ""; renaming = true }.accessibilityIdentifier("page.rename")
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
        .alert("Add Text", isPresented: $typing) {
            TextField("Characters", text: $typed).accessibilityIdentifier("page.addText.field")
            Button("Cancel", role: .cancel) {}
            // Each character becomes a key of its own.
            Button("Add") { failed = !singleCharacters(typed).allSatisfy { boards.add(text: $0, to: boardID) != nil } }
        }
        .alert("Rename Page", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { failed = !boards.renameBoard(boardID, to: name) }
        }
        .sheet(isPresented: $picking) {
            KeyboardKeyUnicodePicker { text in failed = boards.add(text: text, to: boardID) == nil }
        }
    }
}

private struct KeyRow: View {
    let key: SymbolBoardKey
    @EnvironmentObject private var preferences: CatalogPreferences
    private var name: String? {
        guard key.text.unicodeScalars.count == 1, let scalar = key.text.unicodeScalars.first else { return nil }
        return preferences.catalog.character(at: scalar.value)?.name
    }
    var body: some View {
        HStack(spacing: 14) {
            Text(symbolKeyPreview(key.text)).font(.title2).frame(minWidth: 36)
            VStack(alignment: .leading, spacing: 2) {
                if let name { Text(name).font(.subheadline).lineLimit(1) }
                Text(key.text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                if !key.variants.isEmpty {
                    Text(key.variants.map(symbolKeyPreview).joined(separator: "  ")).font(.footnote).lineLimit(1)
                }
            }
        }
    }
}

/// A key's variants, in the order the keyboard's hold chooser shows them.
struct KeyVariantsView: View {
    let boardID: String
    let keyID: String
    @ObservedObject private var boards = SymbolBoardStore.shared
    @State private var picking = false
    @State private var typing = false
    @State private var typed = ""
    @State private var failed = false
    private var key: SymbolBoardKey? { boards.key(boardID: boardID, keyID: keyID) }

    var body: some View {
        List {
            if let key {
                Section {
                    ForEach(Array(key.variants.enumerated()), id: \.offset) { index, variant in
                        Text(symbolKeyPreview(variant)).font(.title2).accessibilityIdentifier("variants.item.\(index)")
                    }
                    .onMove { from, to in
                        var next = key.variants; next.move(fromOffsets: from, toOffset: to)
                        failed = !boards.setVariants(boardID: boardID, keyID: keyID, variants: next)
                    }
                    .onDelete { offsets in
                        var next = key.variants; next.remove(atOffsets: offsets)
                        failed = !boards.setVariants(boardID: boardID, keyID: keyID, variants: next)
                    }
                    if key.variants.isEmpty { Text("No variants. Holding this key inspects it.").foregroundStyle(.secondary) }
                    Button { picking = true } label: { Label("Add from Unicode", systemImage: "character.book.closed") }
                        .accessibilityIdentifier("variants.addUnicode")
                    Button { typed = ""; typing = true } label: { Label("Add Text", systemImage: "plus") }
                        .accessibilityIdentifier("variants.addText")
                } header: {
                    Text("Variants of \(symbolKeyPreview(key.text))")
                } footer: {
                    Text("Up to \(SymbolBoardStore.maximumVariants) variants. Each keeps its exact Unicode text.")
                }
            }
            if failed {
                Text("This variant could not be saved. It may repeat the key or another variant.")
                    .foregroundStyle(.red).accessibilityIdentifier("variants.error")
            }
        }
        .navigationTitle("Variants")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .bottomBar) { EditButton() } }
        .alert("Add Variant", isPresented: $typing) {
            TextField("Characters", text: $typed)
            Button("Cancel", role: .cancel) {}
            Button("Add") { add(singleCharacters(typed)) }
        }
        .sheet(isPresented: $picking) { KeyboardKeyUnicodePicker { add([$0]) } }
    }

    private func add(_ texts: [String]) {
        guard let key, !texts.isEmpty else { return }
        failed = !boards.setVariants(boardID: boardID, keyID: keyID, variants: key.variants + texts)
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
