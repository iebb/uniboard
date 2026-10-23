import SwiftUI

/// The main keyboard drawn as it types. Its letters, Shift, Delete and the
/// optional Tab and Caps Lock keys move like a page's keys, with gaps and up
/// to three rows; the number row keeps its order. Selecting a letter or digit
/// shows what it types and its swipe-up, hold and swipe-down choices.
struct MainKeyboardEditorView: View {
    typealias Layout = SymbolPageLayout
    typealias Arrangement = MainKeyboardArrangement
    private enum Selection: Equatable { case digit(String), place(Layout.Position) }

    @EnvironmentObject private var preferences: CatalogPreferences
    @ObservedObject private var keys = KeyboardKeyPreferences.shared
    @State private var alphabetID = ""
    @State private var selection: Selection?
    @State private var width: CGFloat = 300
    @State private var failed = false
    private let spacing: CGFloat = 5
    private let digits = Array("1234567890").map(String.init)

    private var alphabet: KeyboardAlphabet {
        preferences.alphabets.first { $0.id == alphabetID } ?? preferences.alphabets.first ?? .english
    }
    /// The saved arrangement, or the layout's own rows.
    private var arrangement: Arrangement {
        keys.snapshot.arrangement(for: alphabet.id).flatMap { $0.isValid(for: alphabet) ? $0 : nil } ?? .standard(for: alphabet)
    }
    private var places: Layout { arrangement.places ?? Layout(rows: []) }
    private var keyWidth: CGFloat { Arrangement.keyWidth(for: arrangement.rows, available: width, spacing: spacing) }
    private var position: Layout.Position? { if case .place(let position) = selection { return position }; return nil }
    /// The key in a place, by name.
    private func key(at position: Layout.Position) -> String? {
        places.keyIndex(at: position).flatMap { arrangement.keys.indices.contains($0) ? arrangement.keys[$0] : nil }
    }
    /// The selected letter or digit, whose layers can be edited.
    private var descriptor: KeyboardKeySettings.Descriptor? {
        switch selection {
        case .digit(let digit): return KeyboardKeySettings.identifier(forCharacter: digit).flatMap(KeyboardKeySettings.descriptor(for:))
        case .place(let position):
            return key(at: position).flatMap { Arrangement.isFunction($0) ? nil : $0 }
                .flatMap(KeyboardKeySettings.identifier(forCharacter:)).flatMap(KeyboardKeySettings.descriptor(for:))
        case nil: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if preferences.alphabets.count > 1 {
                        Picker("Layout", selection: Binding(get: { alphabet.id }, set: { alphabetID = $0; selection = nil })) {
                            ForEach(preferences.alphabets) { Text($0.nativeName).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("mainKeyboard.layout")
                    }
                    canvas
                    if let descriptor { layers(descriptor) }
                    if failed {
                        Text("This arrangement could not be saved.").font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("mainKeyboard.error")
                    }
                }
                .padding(16)
            }
            // Measured outside the keys, so they always fit the screen.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(0, $0 - 32 - 16) }
            .background(Color(.systemGroupedBackground))
            Divider()
            controls.padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    optionalKey(Arrangement.tab, title: "Tab", row: 0)
                    optionalKey(Arrangement.caps, title: "Caps Lock", row: 1)
                    Button { selection = nil; failed = !keys.saveArrangement(nil, alphabetID: alphabet.id) } label: {
                        Label("Standard Layout", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(keys.snapshot.arrangement(for: alphabet.id) == nil)
                    .accessibilityIdentifier("mainKeyboard.reset")
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More").accessibilityIdentifier("mainKeyboard.more")
            }
        }
        .onAppear { keys.refresh() }
    }

    private var canvas: some View {
        VStack(spacing: 6) {
            HStack(spacing: spacing) {
                ForEach(digits, id: \.self) { digit in
                    tile(digit, selected: selection == .digit(digit)) { selection = selection == .digit(digit) ? nil : .digit(digit) }
                        .accessibilityIdentifier("mainKeyboard.key.\(KeyboardKeySettings.identifier(forCharacter: digit) ?? digit)")
                }
            }
            ForEach(places.rows.indices, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(places.rows[row].indices, id: \.self) { index in place(Layout.Position(row: row, index: index)) }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainKeyboard.keys")
    }

    @ViewBuilder private func place(_ position: Layout.Position) -> some View {
        let item = places.rows[position.row][position.index]
        let selected = selection == .place(position)
        if item == .key, let key = key(at: position) {
            tile(key, selected: selected, width: Arrangement.width(of: .key(key), keyWidth: keyWidth, spacing: spacing)) {
                selection = selected ? nil : .place(position)
            }
            .draggable("\(position.row),\(position.index)") { Text(Self.label(key)).font(.title2).padding(8) }
            .dropDestination(for: String.self) { items, _ in drop(items, at: position) }
            .accessibilityIdentifier("mainKeyboard.key.\(Arrangement.isFunction(key) ? key : KeyboardKeySettings.identifier(forCharacter: key) ?? key)")
        } else {
            let cell: Arrangement.Cell = item == .halfGap ? .halfGap : .gap
            Button { selection = selected ? nil : .place(position) } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: selected ? 2.5 : 1, dash: selected ? [] : [3, 3]))
                    .frame(width: Arrangement.width(of: cell, keyWidth: keyWidth, spacing: spacing), height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dropDestination(for: String.self) { items, _ in drop(items, at: position) }
            .accessibilityLabel(item == .halfGap ? "Half-width gap" : "Full-width gap")
            .accessibilityIdentifier("mainKeyboard.gap.\(position.row).\(position.index)")
        }
    }

    /// A key as the keyboard draws it: Shift, Delete, Tab and Caps Lock in
    /// the darker grey of iOS's own function keys.
    private func tile(_ key: String, selected: Bool, width: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        let function = Arrangement.isFunction(key)
        // A changed key shows what it now types.
        let shown = function ? key : KeyboardKeySettings.identifier(forCharacter: key)
            .flatMap { keys.snapshot.tapOutput(for: $0, defaultText: key, shifted: false) } ?? key
        return Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(function ? Color.functionKey : Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
                if let symbol = Self.symbol(key) {
                    Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                } else {
                    Text(symbolKeyPreview(shown)).font(.system(size: 22)).minimumScaleFactor(0.4).lineLimit(1).padding(2)
                }
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
            .frame(width: width ?? keyWidth, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Key \(Self.label(key))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func symbol(_ key: String) -> String? {
        switch key {
        case Arrangement.shift: return "shift"
        case Arrangement.delete: return "delete.left"
        case Arrangement.tab: return "arrow.right.to.line"
        case Arrangement.caps: return "capslock"
        default: return nil
        }
    }
    private static func label(_ key: String) -> String {
        switch key {
        case Arrangement.shift: return "Shift"
        case Arrangement.delete: return "Delete"
        case Arrangement.tab: return "Tab"
        case Arrangement.caps: return "Caps Lock"
        default: return key
        }
    }

    /// The selected key's own output and its three candidate layers.
    private func layers(_ descriptor: KeyboardKeySettings.Descriptor) -> some View {
        KeyLayersPanel(layers: [.tap, .swipeUp, .longPress, .swipeDown], choices: { gesture in
            // No saved choices means the built-in defaults; the key itself types its own text.
            let values = keys.snapshot.candidates(for: descriptor.id, gesture: gesture)
            if gesture == .tap { return ([values?.first ?? descriptor.text ?? descriptor.title], values == nil) }
            return (values ?? KeyboardVariantPolicy.defaultCandidates(for: descriptor.id, gesture: gesture, alphabet: alphabet), values == nil)
        }, destination: { (gesture: KeyboardKeySettings.Gesture) -> AnyView in
            let original = keys.snapshot.candidates(for: descriptor.id, gesture: gesture)
            guard gesture == .tap else {
                return AnyView(KeyboardGestureSettingsView(descriptor: descriptor, gesture: gesture, alphabet: alphabet,
                                                           keys: keys, current: original))
            }
            // One value, edited in place; the key's own text, or none, restores it.
            let own = descriptor.text ?? descriptor.title
            return AnyView(KeyLayerEditor(title: "Key · \(descriptor.title)", choices: [original?.first ?? own], maximum: 1) { values in
                let value = values.first.flatMap { $0 == own ? nil : $0 }
                return keys.save(value.map { [$0] }, keyID: descriptor.id, gesture: .tap, replacing: original)
            })
        }, save: { changed in
            keys.save(layers: changed.mapValues { Optional($0) }, keyID: descriptor.id)
        })
    }

    private var controls: some View {
        let position = position
        let item = position.flatMap(places.item(at:))
        let rows = places.rows
        let removable = position.flatMap(key(at:)).map { $0 == Arrangement.tab || $0 == Arrangement.caps } ?? (item != nil)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                control("Move Left", "arrow.left", id: "mainKeyboard.left", enabled: (position?.index ?? 0) > 0) {
                    guard let p = position else { return }
                    move(from: p, to: .init(row: p.row, index: p.index - 1), select: .init(row: p.row, index: p.index - 1))
                }
                control("Move Right", "arrow.right", id: "mainKeyboard.right", enabled: position.map { $0.index + 1 < rows[$0.row].count } ?? false) {
                    guard let p = position else { return }
                    move(from: p, to: .init(row: p.row, index: p.index + 2), select: .init(row: p.row, index: p.index + 1))
                }
                control("Move Up", "arrow.up", id: "mainKeyboard.up", enabled: (position?.row ?? 0) > 0) {
                    guard let p = position else { return }
                    let index = min(p.index, rows[p.row - 1].count)
                    move(from: p, to: .init(row: p.row - 1, index: index), select: .init(row: p.row - 1, index: index))
                }
                control("Move Down", "arrow.down", id: "mainKeyboard.down", enabled: position.map { $0.row + 1 < rows.count } ?? false) {
                    guard let p = position else { return }
                    let index = min(p.index, rows[p.row + 1].count)
                    // A row emptied by the move goes away, so the next row takes its place.
                    let row = rows[p.row].count == 1 ? p.row : p.row + 1
                    move(from: p, to: .init(row: p.row + 1, index: index), select: .init(row: row, index: index))
                }
            }
            HStack(spacing: 8) {
                control("Half Gap", "rectangle.lefthalf.inset.filled", id: "mainKeyboard.halfGap",
                        enabled: position.map { places.canInsert(.halfGap, inRow: $0.row) } ?? false) { insert(.halfGap) }
                control("Gap", "rectangle.dashed", id: "mainKeyboard.gap",
                        enabled: position.map { places.canInsert(.gap, inRow: $0.row) } ?? false) { insert(.gap) }
                control("New Row", "return", id: "mainKeyboard.newRow",
                        enabled: (position?.index ?? 0) > 0 && rows.count < Arrangement.maximumRows) {
                    guard let p = position else { return }
                    edit(select: .place(.init(row: p.row + 1, index: 0))) { places, _ in places.breakRow(at: p) }
                }
                if position?.index == 0 && (position?.row ?? 0) > 0 {
                    control("Join Rows", "arrow.turn.left.up", id: "mainKeyboard.joinRow", enabled: true) {
                        guard let p = position else { return }
                        let index = rows[p.row - 1].count
                        edit(select: .place(.init(row: p.row - 1, index: index))) { places, _ in places.joinRow(p.row) }
                    }
                } else {
                    control("Remove", "minus.circle", id: "mainKeyboard.remove", enabled: item != nil && removable) {
                        guard let p = position else { return }
                        if item == .key, let index = places.keyIndex(at: p) {
                            edit(select: nil) { places, keys in places.removeKeySlot(index); keys.remove(at: index); return true }
                        } else {
                            edit(select: nil) { places, _ in places.removeGap(at: p) }
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
        .disabled(!enabled || position == nil)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    /// Adds Tab or Caps Lock at the start of a row, or removes it.
    @ViewBuilder private func optionalKey(_ key: String, title: String, row: Int) -> some View {
        if let index = arrangement.keys.firstIndex(of: key) {
            Button { edit(select: nil) { places, keys in places.removeKeySlot(index); keys.remove(at: index); return true } } label: {
                Label("Remove \(title)", systemImage: "minus.circle")
            }
            .accessibilityIdentifier("mainKeyboard.remove.\(title)")
        } else {
            Button {
                edit(select: nil) { places, keys in
                    guard let index = places.insertKeySlot(atStartOf: min(row, places.rows.count - 1)) else { return false }
                    keys.insert(key, at: index)
                    return true
                }
            } label: { Label("Add \(title)", systemImage: "plus.circle") }
            .accessibilityIdentifier("mainKeyboard.add.\(title)")
        }
    }

    private func insert(_ gap: Layout.Item) {
        guard let p = position else { return }
        edit(select: .place(p)) { places, _ in places.insertGap(gap, at: p) }
    }

    /// Applies a change to the places and keys, then saves it.
    private func edit(select next: Selection?, _ change: (inout Layout, inout [String]) -> Bool) {
        var places = places, order = arrangement.keys
        guard change(&places, &order) else { return }
        save(Arrangement(keys: order, layout: places.text), select: next)
    }

    private func move(from source: Layout.Position, to destination: Layout.Position, select next: Layout.Position?) {
        var places = places, order = arrangement.keys
        var keyMove: Layout.KeyMove?
        guard places.move(from: source, to: destination, keyMove: &keyMove) else { return }
        if let keyMove { order.move(fromOffsets: [keyMove.from], toOffset: keyMove.to > keyMove.from ? keyMove.to + 1 : keyMove.to) }
        save(Arrangement(keys: order, layout: places.text), select: next.map { .place($0) })
    }

    /// A dragged key lands before the place it is dropped on.
    private func drop(_ items: [String], at destination: Layout.Position) -> Bool {
        let parts = items.first?.split(separator: ",").compactMap { Int($0) } ?? []
        guard parts.count == 2 else { return false }
        let source = Layout.Position(row: parts[0], index: parts[1])
        guard source != destination else { return false }
        move(from: source, to: destination, select: nil)
        return !failed
    }

    private func save(_ next: Arrangement, select: Selection?) {
        failed = !keys.saveArrangement(next, alphabetID: alphabet.id)
        if !failed { selection = select }
    }
}

extension Color {
    /// iOS's own darker grey for Shift, Delete and other function keys.
    static let functionKey = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.27, green: 0.29, blue: 0.33, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    })
}
