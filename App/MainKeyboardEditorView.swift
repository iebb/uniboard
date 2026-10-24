import SwiftUI

/// The main keyboard drawn as it types. Its digits, letters, Shift, Delete
/// and the optional Tab and Caps Lock keys move like a page's keys, with gaps
/// and up to four rows. Digits can be removed and added back. Selecting a
/// letter or digit shows what it types and its swipe-up, hold and swipe-down
/// choices.
struct MainKeyboardEditorView: View {
    typealias Layout = SymbolPageLayout
    typealias Arrangement = MainKeyboardArrangement
    private enum Selection: Equatable { case place(Layout.Position) }

    @EnvironmentObject private var preferences: CatalogPreferences
    @ObservedObject private var keys = KeyboardKeyPreferences.shared
    @State private var alphabetID = ""
    @State private var selection: Selection?
    @State private var width: CGFloat = 300
    @State private var failed = false
    @StateObject private var drag = EditorDragSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var motion
    /// What a drag lifted from; any other arrangement refuses its drop.
    private var dragFingerprint: String { alphabet.id + "|" + arrangement.layout + "|" + arrangement.keys.joined(separator: "\u{1F}") }
    private let spacing: CGFloat = 5

    private var alphabet: KeyboardAlphabet {
        preferences.alphabets.first { $0.id == alphabetID } ?? preferences.alphabets.first ?? .english
    }
    /// The saved arrangement, or the number row and the layout's own rows.
    private var arrangement: Arrangement { keys.snapshot.effectiveArrangement(for: alphabet) }
    private var places: Layout { arrangement.places ?? Layout(rows: []) }
    private var keyWidth: CGFloat { Arrangement.keyWidth(for: arrangement.rows, available: width, spacing: spacing) }
    /// The selected place while it is on an item of the keyboard as it is now.
    private var position: Layout.Position? {
        if case .place(let position) = selection { return EditorReorder.selection(position, in: places) }
        return nil
    }
    /// The key in a place, by name.
    private func key(at position: Layout.Position) -> String? {
        places.keyIndex(at: position).flatMap { arrangement.keys.indices.contains($0) ? arrangement.keys[$0] : nil }
    }
    /// The selected letter or digit, whose layers can be edited.
    private var descriptor: KeyboardKeySettings.Descriptor? {
        switch selection {
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
                        Picker("Layout", selection: Binding(get: { alphabet.id }, set: { drag.reset(); alphabetID = $0; selection = nil })) {
                            ForEach(preferences.alphabets) { Text($0.nativeName).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("mainKeyboard.layout")
                    }
                    canvas
                    if let descriptor { layers(descriptor).disabled(drag.source != nil) }
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
            controls.disabled(drag.source != nil).padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    optionalKey(Arrangement.tab, title: "Tab", row: 0)
                    optionalKey(Arrangement.caps, title: "Caps Lock", row: 1)
                    addDigits
                    Button { selection = nil; failed = !keys.saveArrangement(nil, alphabetID: alphabet.id) } label: {
                        Label("Standard Layout", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(keys.snapshot.arrangement(for: alphabet.id) == nil)
                    .accessibilityIdentifier("mainKeyboard.reset")
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(drag.source != nil)
                .accessibilityLabel("More").accessibilityIdentifier("mainKeyboard.more")
            }
        }
        .onAppear { keys.refresh(); drag.fit(rowCounts: places.rows.map(\.count)) }
        .onDisappear { drag.reset() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { drag.reset() } }
        .onChange(of: dragFingerprint) { _, _ in drag.reset(); drag.fit(rowCounts: places.rows.map(\.count)) }
    }

    private var canvas: some View {
        VStack(spacing: 6) {
            ForEach(places.rows.indices, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(places.rows[row].indices.map { index in
                        let position = Layout.Position(row: row, index: index)
                        return EditorTilePosition(id: tileIdentity(position), position: position)
                    }) { entry in
                        place(entry.position)
                            .matchedGeometryEffect(id: entry.id, in: motion)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainKeyboard.keys")
    }

    /// Keys animate by name; gaps by their tracked identity.
    private func tileIdentity(_ position: Layout.Position) -> String {
        key(at: position).map { "key:" + $0 } ?? drag.tileID(position)
    }

    @ViewBuilder private func place(_ position: Layout.Position) -> some View {
        let item = places.rows[position.row][position.index]
        let selected = selection == .place(position)
        let active = drag.source == position
        let current = arrangement, currentAlphabet = self.alphabet
        EditorDragSurface(session: drag, position: position, fingerprint: dragFingerprint,
                          currentFingerprint: { dragFingerprint },
                          draggable: EditorReorder.canDragMainKeyboardItem(at: position, in: current),
                          accepts: { EditorReorder.mainKeyboard(current, from: $0, to: position, alphabet: currentAlphabet) != nil },
                          commit: { drop($0, at: position) }) {
            if item == .key, let key = key(at: position) {
                tile(key, selected: selected && !active, width: Arrangement.width(of: .key(key), keyWidth: keyWidth, spacing: spacing)) {
                    guard !drag.isDragging else { return }
                    selection = selected ? nil : .place(position)
                }
                .accessibilityIdentifier("mainKeyboard.key.\(Arrangement.isFunction(key) ? key : KeyboardKeySettings.identifier(forCharacter: key) ?? key)")
            } else {
                let cell: Arrangement.Cell = item == .halfGap ? .halfGap : .gap
                Button { if !drag.isDragging { selection = selected ? nil : .place(position) } } label: {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.5),
                                      style: StrokeStyle(lineWidth: selected ? 2.5 : 1, dash: selected ? [] : [3, 3]))
                        .frame(width: Arrangement.width(of: cell, keyWidth: keyWidth, spacing: spacing), height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .halfGap ? "Half-width gap" : "Full-width gap")
                .accessibilityIdentifier("mainKeyboard.gap.\(position.row).\(position.index)")
            }
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
                // Hidden from the moment a drag lifts, so its preview never shows it.
                if selected { EditorSelectionBorder(cornerRadius: 7) }
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
            let saved = keys.save(layers: changed.mapValues { Optional($0) }, keyID: descriptor.id)
            failed = !saved
            return saved
        })
    }

    private var controls: some View {
        let position = position
        let item = position.flatMap(places.item(at:))
        let rows = places.rows
        // Shift, Delete and the letters always stay; digits, Tab and Caps Lock may go.
        let removable = position.flatMap(key(at:)).map { $0 == Arrangement.tab || $0 == Arrangement.caps || Arrangement.isDigit($0) } ?? (item != nil)
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

    /// Adds Tab or Caps Lock at the start of a row of letters, counted
    /// from the first one so a number row above them is skipped, or removes it.
    @ViewBuilder private func optionalKey(_ key: String, title: String, row letterRow: Int) -> some View {
        let row = (arrangement.firstLetterRow ?? 0) + letterRow
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

    /// Puts removed digits back: the whole number row as the first row, or
    /// the missing ones after the last digit. Hidden while every digit is there.
    @ViewBuilder private var addDigits: some View {
        let missing = arrangement.missingDigits
        if !missing.isEmpty {
            let all = missing.count == Arrangement.digits.count
            Button {
                guard let next = arrangement.addingDigits() else { failed = true; return }
                save(next, select: nil)
            } label: { Label(all ? "Add Number Row" : "Add Missing Digits", systemImage: "plus.circle") }
            .disabled(arrangement.addingDigits() == nil)
            .accessibilityIdentifier("mainKeyboard.add.digits")
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

    /// The arrow buttons: the VoiceOver and Switch Control way to move.
    private func move(from source: Layout.Position, to destination: Layout.Position, select next: Layout.Position?) {
        guard let move = EditorReorder.mainKeyboard(arrangement, from: source, to: destination, alphabet: alphabet) else { return }
        let label = key(at: source).map(Self.label) ?? String(localized: "Gap")
        guard commit(move, select: { _ in next.map { Selection.place($0) } }) else { return }
        if let next {
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Moved \(label) to row \(next.row + 1), place \(next.index + 1)"))
        }
    }

    /// A drop: computed once from the saved arrangement, saved once. Hover
    /// never gets here, and a refused or unchanged drop saves nothing.
    private func drop(_ source: Layout.Position, at destination: Layout.Position) {
        guard EditorReorder.canDragMainKeyboardItem(at: source, in: arrangement),
              let move = EditorReorder.mainKeyboard(arrangement, from: source, to: destination, alphabet: alphabet),
              move.changesValue else { return }
        // Selection follows the item it was on, not its old row and place.
        let selected = position.flatMap(drag.identity(at:))
        let kept = selection
        commit(move) { identities in
            guard case .place = kept else { return kept }
            return selected.flatMap(identities).map { Selection.place($0) }
        }
    }

    /// Saves a computed move through the store, animating the settle. Nothing
    /// else changes unless it saved, so a failed save leaves the old keys.
    @discardableResult
    private func commit(_ move: EditorReorder.Move<Arrangement>, select: ((Int) -> Layout.Position?) -> Selection?) -> Bool {
        // Only a place on the saved keyboard is selected; never one past a row's end.
        let next = move.value.places ?? Layout(rows: [])
        func valid(_ choice: Selection?) -> Selection? {
            guard case .place(let place) = choice else { return choice }
            return EditorReorder.selection(place, in: next).map { Selection.place($0) }
        }
        guard move.changesValue else { selection = valid(select { drag.position(ofIdentity: $0) }); return true }
        var saved = false
        withAnimation(.editorReorder(reduceMotion: reduceMotion)) {
            failed = !keys.saveArrangement(move.value, alphabetID: alphabet.id)
            saved = !failed
            if saved {
                drag.moveIdentity(from: move.source, to: move.destination, removesEmptyRows: true)
                selection = valid(select { drag.position(ofIdentity: $0) })
            }
        }
        return saved
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

// MARK: - Local editor drag sessions

/// One editor's drag: which item is lifted and where the insertion line is,
/// plus stable tile identities. It never holds or writes the arrangement; the
/// rules live in `EditorDragState` and `EditorReorder`.
final class EditorDragSession: ObservableObject {
    typealias Position = SymbolPageLayout.Position
    @Published private(set) var state = EditorDragState()
    @Published private(set) var identities = EditorTileIdentities()
    /// This editor, so another editor's or app's drags are never accepted.
    let origin = UUID()
    /// Lifted by UIKit, shown as lifted once its preview has been taken.
    fileprivate var pending: EditorDragState.Lift?

    var source: Position? { state.source }
    var target: Position? { state.target }
    var isDragging: Bool { state.isActive || pending != nil }

    /// Cancel, dismissal, backgrounding or a changed arrangement: nothing to undo.
    func reset() {
        pending = nil
        update { $0.cancel() }
    }

    fileprivate func cancel(token: UUID?) {
        guard let token else { return }
        if pending?.token == token { pending = nil }
        if state.lift?.token == token { update { $0.cancel() } }
    }

    fileprivate func showLift() {
        guard let lift = pending else { return }
        pending = nil
        update { $0.begin(at: lift.source, fingerprint: lift.fingerprint, token: lift.token) }
    }

    fileprivate func hover(_ destination: Position, token: UUID?, fingerprint: String, accepts: (Position) -> Bool) -> Bool {
        update { $0.hover(destination, token: token, fingerprint: fingerprint, isValid: accepts) }
    }

    fileprivate func leave(_ destination: Position) { update { $0.leave(destination) } }

    fileprivate func finish(token: UUID?, fingerprint: String) -> Position? {
        update { $0.finish(token: token, fingerprint: fingerprint) }
    }

    /// Publishes only real changes, so pointer updates do not redraw the editor.
    private func update<Result>(_ change: (inout EditorDragState) -> Result) -> Result {
        var next = state
        let result = change(&next)
        if next != state { state = next }
        return result
    }

    // Identities

    func fit(rowCounts: [Int]) {
        var next = identities
        next.fit(rowCounts: rowCounts)
        if next != identities { identities = next }
    }
    func tileID(_ position: Position) -> String {
        identities.id(at: position).map { "t\($0)" } ?? "p\(position.row),\(position.index)"
    }
    func identity(at position: Position) -> Int? { identities.id(at: position) }
    func position(ofIdentity id: Int) -> Position? { identities.position(of: id) }
    func moveIdentity(from source: Position, to destination: Position, removesEmptyRows: Bool) {
        identities.move(from: source, to: destination, removesEmptyRows: removesEmptyRows)
    }
}

/// The insertion line: drawn over the gap before the place a drop lands in,
/// never taking any row width.
struct EditorInsertionMark: View {
    var height: CGFloat = 40
    var body: some View {
        ZStack {
            Capsule().frame(width: 2, height: height)
            VStack(spacing: 0) {
                Circle().frame(width: 4, height: 4)
                Spacer(minLength: 0)
                Circle().frame(width: 4, height: 4)
            }
            .frame(width: 4, height: height)
        }
        .foregroundStyle(.tint)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What a drag carries: only which editor and which drag it belongs to.
final class EditorDragToken {
    let origin: UUID
    let token: UUID
    init(origin: UUID, token: UUID) { self.origin = origin; self.token = token }
}

/// Whether a drag is lifting the hosted item, so it can hide what its lift
/// preview must not show, such as a selection border.
private struct EditorDragLiftingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var editorDragLifting: Bool {
        get { self[EditorDragLiftingKey.self] }
        set { self[EditorDragLiftingKey.self] = newValue }
    }
}

/// A selected tile's border. It hides as soon as its tile is lifted, before
/// UIKit takes the preview, and stays hidden for the rest of the drag.
struct EditorSelectionBorder: View {
    var cornerRadius: CGFloat
    @Environment(\.editorDragLifting) private var lifting
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2.5)
            .opacity(lifting ? 0 : 1)
    }
}

/// What a surface hosts: the parent's content plus what a UIKit-hosted view
/// does not inherit from it, such as `.disabled`.
struct EditorDragSurfaceRoot<Content: View>: View {
    let content: Content
    let isEnabled: Bool
    let lifting: Bool
    let hidesAccessibility: Bool
    var body: some View {
        content
            .disabled(!isEnabled)
            .environment(\.editorDragLifting, lifting)
            .accessibilityHidden(hidesAccessibility)
    }
}

/// Hosts the *same* cap shown at rest and gives it UIKit's native lift: the
/// system preview follows the finger, returns on cancel and reports every end
/// of a drag, including drops outside. No second scale, shadow or follower is
/// stacked on top. Drop targets use it without dragging.
struct EditorDragSurface<Content: View>: UIViewRepresentable {
    typealias Position = SymbolPageLayout.Position
    let session: EditorDragSession
    let position: Position
    /// The arrangement this surface was drawn for; hovering checks it.
    let fingerprint: String
    /// The arrangement as it is when a drop lands, read then rather than at
    /// the last render, so a change that has not redrawn yet refuses the drop.
    var currentFingerprint: (() -> String)? = nil
    var draggable = true
    /// Combined with the environment's, which the hosted content never sees.
    var isEnabled = true
    /// For content inside an element that speaks for it: the hosted views
    /// would otherwise still be exposed to VoiceOver on their own.
    var hidesAccessibility = false
    var cornerRadius: CGFloat = 7
    /// Whether the item lifted from a place may land here.
    let accepts: (Position) -> Bool
    /// Commits the drop of the item lifted from a place; at most once a drag.
    let commit: (Position) -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let coordinator = context.coordinator
        coordinator.isEnabled = isEnabled && context.environment.isEnabled
        coordinator.render()
        let view: UIView = coordinator.host.view
        view.backgroundColor = .clear
        view.accessibilityElementsHidden = hidesAccessibility
        let drag = UIDragInteraction(delegate: coordinator)
        drag.isEnabled = coordinator.canDrag
        view.addInteraction(drag)
        view.addInteraction(UIDropInteraction(delegate: coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isEnabled = isEnabled && context.environment.isEnabled
        coordinator.render()
        view.accessibilityElementsHidden = hidesAccessibility
        for case let drag as UIDragInteraction in view.interactions { drag.isEnabled = coordinator.canDrag }
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        context.coordinator.host.sizeThatFits(in: CGSize(width: proposal.width ?? 10_000, height: proposal.height ?? 10_000))
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        // A tile that goes away mid-drag (its row changed) takes its drag with it.
        coordinator.parent.session.cancel(token: coordinator.liftedToken)
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
        var parent: EditorDragSurface
        let host: UIHostingController<EditorDragSurfaceRoot<Content>>
        fileprivate var liftedToken: UUID?
        var isEnabled = true
        /// From the lift until the drag ends; the content hides its selection border.
        private var lifting = false

        var canDrag: Bool { parent.draggable && isEnabled }

        init(_ parent: EditorDragSurface) {
            self.parent = parent
            host = UIHostingController(rootView: EditorDragSurfaceRoot(content: parent.content(), isEnabled: true,
                                                                      lifting: false, hidesAccessibility: parent.hidesAccessibility))
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
        }

        func render() {
            host.rootView = EditorDragSurfaceRoot(content: parent.content(), isEnabled: isEnabled, lifting: lifting,
                                                  hidesAccessibility: parent.hidesAccessibility)
        }

        private func setLifting(_ value: Bool) {
            guard lifting != value else { return }
            lifting = value
            render()
            // Applied now, so the preview UIKit takes next already reflects it.
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        /// Ends this surface's lift, whether or not a drag ever began.
        private func endLift(token: UUID?) {
            let token = token ?? liftedToken
            parent.session.cancel(token: token)
            // A later lift of this surface keeps its own state.
            guard token == liftedToken else { return }
            liftedToken = nil
            setLifting(false)
        }

        private func token(of session: UIDragDropSession) -> EditorDragToken? {
            guard session.items.count == 1, let token = session.items.first?.localObject as? EditorDragToken,
                  token.origin == parent.session.origin else { return nil }
            return token
        }

        // MARK: Drag

        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            let editor = parent.session
            guard canDrag, !editor.isDragging else { return [] }
            let lift = EditorDragState.Lift(token: UUID(), source: parent.position, fingerprint: parent.fingerprint)
            editor.pending = lift
            liftedToken = lift.token
            setLifting(true)
            // The lift is shown, or the drag ends, within moments of this. If
            // neither happens no session started, and nothing may stay lifted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak editor] in
                guard let self, let editor, editor.pending?.token == lift.token else { return }
                self.endLift(token: lift.token)
            }
            let item = UIDragItem(itemProvider: NSItemProvider())
            item.localObject = EditorDragToken(origin: editor.origin, token: lift.token)
            return [item]
        }

        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
            guard let view = interaction.view, view.window != nil else {
                // No preview, so no lift to show: the drag cannot block taps.
                endLift(token: (item.localObject as? EditorDragToken)?.token)
                return nil
            }
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: parent.cornerRadius)
            return UITargetedDragPreview(view: view, parameters: parameters)
        }

        func dragInteraction(_ interaction: UIDragInteraction, willAnimateLiftWith animator: UIDragAnimating, session: UIDragSession) {
            // The preview is taken by now, so dimming the source cannot dim it.
            parent.session.showLift()
            let token = liftedToken
            animator.addCompletion { [weak self, weak editor = parent.session] position in
                guard position == .start else { return }
                editor?.cancel(token: token)
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in self?.endLift(token: token) }
            }
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
            parent.session.showLift()
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
            endLift(token: token(of: session)?.token ?? liftedToken)
        }

        // MARK: Drop

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil && token(of: session) != nil
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            parent.session.showLift()
            let valid = parent.session.hover(parent.position, token: token(of: session)?.token,
                                             fingerprint: parent.fingerprint, accepts: parent.accepts)
            return UIDropProposal(operation: valid ? .move : .forbidden)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            parent.session.leave(parent.position)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            // Checked against the arrangement as it is now, not as last drawn.
            let current = parent.currentFingerprint?() ?? parent.fingerprint
            guard let source = parent.session.finish(token: token(of: session)?.token, fingerprint: current),
                  current == parent.fingerprint, parent.accepts(source) else { return }
            parent.commit(source)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            parent.session.leave(parent.position)
        }
    }
}

/// A tile's place with the identity it animates by.
struct EditorTilePosition: Identifiable {
    let id: String
    let position: SymbolPageLayout.Position
}

extension Animation {
    /// The settle after a committed reorder; none with Reduce Motion.
    static func editorReorder(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.90, blendDuration: 0)
    }
    /// Source dimming, and the insertion line (80 ms), or 100 ms opacity with Reduce Motion.
    static func editorFade(_ duration: Double, reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.1 : duration)
    }
}
