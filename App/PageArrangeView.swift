import SwiftUI

/// A page drawn as the keyboard shows it. Add keys, arrange them into rows
/// with half-width and full-width gaps, and select a key to edit its swipe-up,
/// hold and swipe-down choices; keys can also be dragged onto a place.
struct PageArrangeView: View {
    typealias Layout = SymbolPageLayout
    let boardID: String
    /// Opens the Favorites and Recently Used lists, for Favorites.
    var savedList: AnyView? = nil
    @ObservedObject private var boards = SymbolBoardStore.shared
    @State private var selection: Layout.Position?
    @State private var picking = false
    @State private var typing = false
    @State private var typed = ""
    @State private var renaming = false
    @State private var name = ""
    /// Favorites come from saving characters, so they are not added or removed here.
    private var isFavorites: Bool { boardID == SymbolBoardStore.favoritesID }
    /// The width the keys and gaps of a row share.
    @State private var canvasWidth: CGFloat = 300
    @State private var failed = false
    @StateObject private var drag = EditorDragSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var motion
    /// What a drag lifted from; any other arrangement refuses its drop.
    private var dragFingerprint: String {
        boardID + "|" + layout.text + "|" + (board?.keys.map(\.id).joined(separator: "\u{1F}") ?? "")
    }
    private let spacing: CGFloat = 5
    /// The drop target that ends every row.
    private let rowEnd: CGFloat = 12
    private var board: SymbolBoard? { boards.boards.first { $0.id == boardID } }
    private var keyCount: Int { board?.keys.count ?? 0 }
    /// Exactly the keyboard's rows: every slot holds a key.
    private var layout: Layout { Layout.resolved(board?.layout, keyCount: keyCount).fitted(keyCount: keyCount) }
    /// The selection while it is on an item of the page as it is now.
    private var selected: Layout.Position? { EditorReorder.selection(selection, in: layout) }
    private var selectedItem: Layout.Item? { selected.flatMap(layout.item(at:)) }
    private var selectedKey: SymbolBoardKey? {
        selected.flatMap(layout.keyIndex(at:)).flatMap { board?.keys.indices.contains($0) == true ? board?.keys[$0] : nil }
    }
    /// A key as the store holds it now, not as the last render captured it.
    private func liveKey(_ id: String) -> SymbolBoardKey? { board?.keys.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if keyCount == 0 {
                        Text(isFavorites ? "Save characters to add them here." : "No keys yet.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        canvas
                    }
                    if let key = selectedKey {
                        layers(key).disabled(drag.source != nil)
                    } else {
                        pageOptions.disabled(drag.source != nil)
                    }
                    if failed {
                        Text("This arrangement could not be saved.").font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("arrange.error")
                    }
                }
                .padding(16)
            }
            // Measured outside the canvas, so wider keys can never widen the screen.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                canvasWidth = max(0, width - 32 - 16 - rowEnd - spacing)
            }
            .background(Color(.systemGroupedBackground))
            Divider()
            controls.disabled(drag.source != nil).padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
        }
        .navigationTitle(board?.name ?? "Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let savedList {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { savedList } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("Favorites and Recently Used").accessibilityIdentifier("page.list")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !isFavorites {
                        Button { name = board?.name ?? ""; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                            .accessibilityIdentifier("page.rename")
                    }
                    Button { selection = nil; save(nil) } label: { Label("Rows of Ten", systemImage: "square.grid.3x3") }
                        .disabled(board?.layout == nil)
                        .accessibilityIdentifier("arrange.reset")
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(drag.source != nil)
                .accessibilityLabel("More").accessibilityIdentifier("page.more")
            }
        }
        .onAppear { boards.refreshPages(); drag.fit(rowCounts: layout.rows.map(\.count)) }
        .onDisappear { drag.reset() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { drag.reset() } }
        .onChange(of: dragFingerprint) { _, _ in drag.reset(); drag.fit(rowCounts: layout.rows.map(\.count)) }
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

    /// Shown while no key is selected: adding keys and the ★ page.
    private var pageOptions: some View {
        VStack(spacing: 8) {
            if !isFavorites {
                HStack(spacing: 8) {
                    Button { picking = true } label: { Label("Add from Unicode", systemImage: "character.book.closed").frame(maxWidth: .infinity) }
                        .accessibilityIdentifier("page.addUnicode")
                    Button { typed = ""; typing = true } label: { Label("Add Text", systemImage: "plus").frame(maxWidth: .infinity) }
                        .accessibilityIdentifier("page.addText")
                }
                .buttonStyle(.bordered)
                .disabled(!boards.canEdit || keyCount >= SymbolBoardStore.maximumKeys)
            }
            Toggle("Opens with ★", isOn: Binding(get: { boards.preferredStarBoardID == boardID }, set: { on in
                failed = !boards.setPreferredStarBoard(on ? boardID : SymbolBoardStore.favoritesID)
            }))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("page.star")
        }
    }

    private var canvas: some View {
        let cells = layout.cells(keyCount: keyCount)
        let width = Layout.keyWidth(for: cells, available: canvasWidth, spacing: spacing)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(layout.rows.indices, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(layout.rows[row].indices.map { index in
                        let position = Layout.Position(row: row, index: index)
                        return EditorTilePosition(id: tileIdentity(position), position: position)
                    }) { entry in
                        tile(entry.position, keyWidth: width)
                            .matchedGeometryEffect(id: entry.id, in: motion)
                    }
                    // Dropping here puts an item at the end of the row.
                    let end = Layout.Position(row: row, index: layout.rows[row].count)
                    let current = layout
                    EditorDragSurface(session: drag, position: end, fingerprint: dragFingerprint,
                                      currentFingerprint: { dragFingerprint }, draggable: false,
                                      accepts: { EditorReorder.page(current, from: $0, to: end) != nil },
                                      commit: { drop($0, at: end) }) {
                        Color.clear.frame(width: rowEnd, height: 44).contentShape(Rectangle())
                    }
                    .overlay(alignment: .leading) {
                        EditorInsertionMark().offset(x: -(spacing / 2 + 2))
                            .opacity(drag.target == end ? 1 : 0)
                            .animation(.editorFade(0.08, reduceMotion: reduceMotion), value: drag.target == end)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // A container keeps each tile's own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arrange.canvas")
    }

    /// Keys animate by their own identity; gaps by their tracked one.
    private func tileIdentity(_ position: Layout.Position) -> String {
        if let index = layout.keyIndex(at: position), let keys = board?.keys, keys.indices.contains(index) { return "key:" + keys[index].id }
        return drag.tileID(position)
    }

    @ViewBuilder private func tile(_ position: Layout.Position, keyWidth: CGFloat) -> some View {
        let item = layout.rows[position.row][position.index]
        let selected = selection == position
        let key = layout.keyIndex(at: position).flatMap { board?.keys.indices.contains($0) == true ? board?.keys[$0] : nil }
        let cell: Layout.Cell = item == .key ? .key(0) : item == .halfGap ? .halfGap : .gap
        let width = item == .key ? keyWidth : Layout.gapWidth(cell, keyWidth: keyWidth, spacing: spacing)
        let active = drag.source == position
        let current = layout
        EditorDragSurface(session: drag, position: position, fingerprint: dragFingerprint,
                          currentFingerprint: { dragFingerprint },
                          accepts: { EditorReorder.page(current, from: $0, to: position) != nil },
                          commit: { drop($0, at: position) }) {
            Button { if !drag.isDragging { selection = selected ? nil : position } } label: {
                ZStack {
                    if let key {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
                        Text(symbolKeyPreview(key.text)).font(.system(size: 22)).minimumScaleFactor(0.4).lineLimit(1).padding(2)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text(item == .halfGap ? "½" : "1").font(.caption2).foregroundStyle(.secondary)
                    }
                    // Hidden from the moment a drag lifts, so its preview never shows it.
                    if selected && !active { EditorSelectionBorder(cornerRadius: 7) }
                }
                .frame(width: width, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(key.map { "Key \(symbolKeyPreview($0.text))" } ?? (item == .halfGap ? "Half-width gap" : "Full-width gap"))
            .accessibilityValue(key.map { $0.text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ") }
                                ?? "Row \(position.row + 1), place \(position.index + 1)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("arrange.\(position.row).\(position.index)")
        }
        .opacity(active ? 0.35 : 1)
        .animation(.editorFade(0.12, reduceMotion: reduceMotion), value: active)
        // Centred in the gap before the place; inside the canvas at a row's start.
        .overlay(alignment: .leading) {
            EditorInsertionMark().offset(x: position.index == 0 ? 0 : -(spacing / 2 + 2))
                .opacity(drag.target == position ? 1 : 0)
                .animation(.editorFade(0.08, reduceMotion: reduceMotion), value: drag.target == position)
        }
    }

    /// The selected key's swipe-up, hold and swipe-down choices.
    private func layers(_ key: SymbolBoardKey) -> some View {
        // Read through the store, so a drop checks and saves the key as it is now.
        let id = key.id
        return KeyLayersPanel(choices: { gesture in (choices(liveKey(id) ?? key, gesture) ?? [], false) }, destination: { gesture in
            KeyLayerEditor(title: "\(gesture.title) · \(symbolKeyPreview(key.text))", choices: choices(key, gesture) ?? []) { values in
                switch gesture {
                case .longPress: return boards.setVariants(boardID: boardID, keyID: key.id, variants: values)
                default: return boards.setSwipe(boardID: boardID, keyID: key.id, up: gesture == .swipeUp, choices: values)
                }
            }
        }, save: { changed in
            guard let key = liveKey(id) else { failed = true; return false }
            let saved = boards.setLayers(boardID: boardID, keyID: key.id, variants: changed[.longPress] ?? key.variants,
                                         up: changed[.swipeUp] ?? key.up ?? [], down: changed[.swipeDown] ?? key.down ?? [])
            failed = !saved
            return saved
        })
    }

    private func choices(_ key: SymbolBoardKey, _ gesture: KeyboardKeySettings.Gesture) -> [String]? {
        switch gesture {
        case .swipeUp: return key.up
        case .swipeDown: return key.down
        default: return key.variants
        }
    }

    private var controls: some View {
        let position = selected
        let item = selectedItem
        let current = layout
        let rows = current.rows
        /// Only moves the keyboard would keep as saved.
        let canMove = { (p: Layout.Position, to: Layout.Position) in EditorReorder.page(current, from: p, to: to) != nil }
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                control("Move Left", "arrow.left", id: "arrange.left",
                        enabled: position.map { $0.index > 0 && canMove($0, .init(row: $0.row, index: $0.index - 1)) } ?? false) {
                    guard let p = position else { return }
                    move(from: p, to: .init(row: p.row, index: p.index - 1), select: .init(row: p.row, index: p.index - 1))
                }
                control("Move Right", "arrow.right", id: "arrange.right",
                        enabled: position.map { $0.index + 1 < rows[$0.row].count && canMove($0, .init(row: $0.row, index: $0.index + 2)) } ?? false) {
                    guard let p = position else { return }
                    move(from: p, to: .init(row: p.row, index: p.index + 2), select: .init(row: p.row, index: p.index + 1))
                }
                control("Move Up", "arrow.up", id: "arrange.up", enabled: position.map {
                    $0.row > 0 && canMove($0, .init(row: $0.row - 1, index: min($0.index, rows[$0.row - 1].count)))
                } ?? false) {
                    guard let p = position else { return }
                    let index = min(p.index, rows[p.row - 1].count)
                    move(from: p, to: .init(row: p.row - 1, index: index), select: .init(row: p.row - 1, index: index))
                }
                control("Move Down", "arrow.down", id: "arrange.down", enabled: position.map {
                    $0.row + 1 < rows.count && canMove($0, .init(row: $0.row + 1, index: min($0.index, rows[$0.row + 1].count)))
                } ?? false) {
                    guard let p = position else { return }
                    let index = min(p.index, rows[p.row + 1].count)
                    // A row emptied by the move goes away, so the next row takes its place.
                    let row = rows[p.row].count == 1 ? p.row : p.row + 1
                    move(from: p, to: .init(row: p.row + 1, index: index), select: .init(row: row, index: index))
                }
            }
            HStack(spacing: 8) {
                control("Half Gap", "rectangle.lefthalf.inset.filled", id: "arrange.halfGap",
                        enabled: position.map { layout.canInsert(.halfGap, inRow: $0.row) } ?? false) { insert(.halfGap) }
                control("Gap", "rectangle.dashed", id: "arrange.gap",
                        enabled: position.map { layout.canInsert(.gap, inRow: $0.row) } ?? false) { insert(.gap) }
                control("New Row", "return", id: "arrange.newRow", enabled: (position?.index ?? 0) > 0) {
                    guard let p = position else { return }
                    edit(select: .init(row: p.row + 1, index: 0)) { $0.breakRow(at: p) }
                }
                if position?.index == 0 && (position?.row ?? 0) > 0 {
                    control("Join Rows", "arrow.turn.left.up", id: "arrange.joinRow", enabled: true) {
                        guard let p = position else { return }
                        let index = rows[p.row - 1].count
                        edit(select: .init(row: p.row - 1, index: index)) { $0.joinRow(p.row) }
                    }
                } else {
                    control("Remove", "minus.circle", id: "arrange.remove", enabled: item != nil && (item != .key || !isFavorites)) {
                        guard let p = position else { return }
                        if item == .key, let key = selectedKey {
                            failed = !boards.removeKey(boardID: boardID, keyID: key.id)
                            if !failed { selection = nil }
                        } else {
                            edit(select: nil) { $0.removeGap(at: p) }
                        }
                    }
                }
            }
        }
    }

    private func control(_ title: String, _ icon: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled || selected == nil)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private func insert(_ gap: Layout.Item) {
        guard let p = selected else { return }
        edit(select: p) { $0.insertGap(gap, at: p) }
    }

    private func edit(select next: Layout.Position?, _ change: (inout Layout) -> Bool) {
        var value = layout
        guard change(&value) else { return }
        save(value)
        if !failed { selection = EditorReorder.selection(next, in: value.fitted(keyCount: keyCount)) }
    }

    /// The arrow buttons: the VoiceOver and Switch Control way to move.
    private func move(from source: Layout.Position, to destination: Layout.Position, select next: Layout.Position?) {
        guard let move = EditorReorder.page(layout, from: source, to: destination) else { return }
        let label = layout.keyIndex(at: source).flatMap { index in board?.keys.indices.contains(index) == true ? board?.keys[index] : nil }
            .map { symbolKeyPreview($0.text) } ?? String(localized: "Gap")
        guard commit(move, select: { _ in next }) else { return }
        if let next {
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Moved \(label) to row \(next.row + 1), place \(next.index + 1)"))
        }
    }

    /// A drop: computed once from the saved page, saved once. Hover never
    /// gets here, and a refused or unchanged drop saves nothing.
    private func drop(_ source: Layout.Position, at destination: Layout.Position) {
        guard let move = EditorReorder.page(layout, from: source, to: destination), move.changesValue else { return }
        // Selection follows the item it was on, not its old row and place.
        let kept = selected.flatMap(drag.identity(at:))
        commit(move) { identities in kept.flatMap(identities) }
    }

    /// Saves a computed move through the store, animating the settle. Nothing
    /// else changes unless it saved, so a failed save leaves the old page.
    @discardableResult
    private func commit(_ move: EditorReorder.Move<EditorReorder.PageMove>,
                        select: ((Int) -> Layout.Position?) -> Layout.Position?) -> Bool {
        // Only a place on the saved page is selected; never one past a row's end.
        let next = move.value.layout
        guard move.changesValue else { selection = EditorReorder.selection(select { drag.position(ofIdentity: $0) }, in: next); return true }
        var saved = false
        withAnimation(.editorReorder(reduceMotion: reduceMotion)) {
            save(next, keyMove: move.value.keyMove)
            saved = !failed
            if saved {
                drag.moveIdentity(from: move.source, to: move.destination, removesEmptyRows: true)
                selection = EditorReorder.selection(select { drag.position(ofIdentity: $0) }, in: next)
            }
        }
        return saved
    }

    private func save(_ value: Layout?, keyMove: Layout.KeyMove? = nil) {
        failed = !boards.setLayout(boardID: boardID, layout: value, keyMove: keyMove)
    }
}
