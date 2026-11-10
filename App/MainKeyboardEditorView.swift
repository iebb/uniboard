import SwiftUI

/// The main keyboard drawn as it types: letters and the eligible merged #+=
/// page, or the existing letters, 123 and #+= sections. On the letters, digits, Shift, Delete
/// and the optional Tab and Caps Lock keys move like a page's keys, with gaps
/// and up to four rows; digits can be removed and added back. Selecting a
/// letter, digit or symbol key shows what it types and its swipe-up, hold
/// and swipe-down choices, with a per-key restore. Find a key searches every
/// section.
struct MainKeyboardEditorView: View {
    typealias Layout = SymbolPageLayout
    typealias Arrangement = MainKeyboardArrangement
    private enum Selection: Equatable {
        /// A place on the letters' arrangement.
        case place(Layout.Position)
        /// A key by its settings identifier: on 123 and #+=, or a found key no canvas draws.
        case key(String)
    }

    @EnvironmentObject private var preferences: CatalogPreferences
    @ObservedObject private var keys = KeyboardKeyPreferences.shared
    @State private var alphabetID = ""
    /// Opens on the letters each visit; not remembered.
    @State private var section: MainKeyboardSection = .letters
    @State private var selection: Selection?
    @State private var rowScope = ArrangementRowScope()
    @State private var undoNote: String?
    @State private var undoFailed = false
    @State private var transitionBanner: String?
    @State private var observedEditID: UUID?
    @State private var hasAppeared = false
    @State private var editorVisible = false
    private var scopedRow: Int? { rowScope.clamped(rowCount: places.rows.count).row }
    @State private var width: CGFloat = 300
    @State private var containerSize: CGSize = .zero
    @State private var failed = false
    @State private var query = ""
    @State private var searching = false
    @State private var confirmsRestoreAll = false
    @State private var confirmsRestoreKey = false
    @StateObject private var drag = EditorDragSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var motion
    /// What a drag lifted from; any other arrangement refuses its drop.
    private var dragFingerprint: String {
        let currentAlphabet = alphabet
        return Self.fingerprint(keys.snapshot.effectiveArrangement(for: currentAlphabet), alphabet: currentAlphabet)
    }
    private static func fingerprint(_ current: Arrangement, alphabet: KeyboardAlphabet) -> String {
        alphabet.id + "|" + current.resolvedRows.map { $0.alignment.rawValue }.joined() + "|" + current.layout + "|" + current.keys.joined(separator: "\u{1F}")
    }
    private var spacing: CGFloat { isPad ? 7 : 5 }
    private static let top = "mainKeyboard.top"
    /// Existing device classification; symbol functions additionally require
    /// the measured container width, just like the extension.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var alphabet: KeyboardAlphabet {
        preferences.alphabets.first { $0.id == alphabetID } ?? preferences.alphabets.first ?? .english
    }
    /// The saved arrangement, or the number row and the layout's own rows.
    private var arrangement: Arrangement { keys.snapshot.effectiveArrangement(for: alphabet) }
    private var places: Layout {
        let current = arrangement
        if let rows = current.explicitRows { return Layout(rows: rows.map { $0.cells.map { $0.key != nil ? .key : $0 == .halfGap ? .halfGap : .gap } }) }
        return current.places ?? Layout(rows: [])
    }
    private var wideRows: [Int] {
        let rows = arrangement.resolvedRows
        return rows.indices.filter { ExplicitRowEditing.units(rows[$0], keyUnits: ExplicitRowEditing.mainUnits) > ExplicitRowEditing.limit }
    }
    /// Only stock legacy rows use the keyboard's caseless geometry. Explicit
    /// and customized rows retain their existing extension/persistence contract.
    static func caselessCanvasWidths(for current: Arrangement, alphabet: KeyboardAlphabet,
                                     available: CGFloat, spacing: CGFloat) -> (letter: CGFloat, function: CGFloat)? {
        guard alphabet.isCaseless, current.isLegacy,
              current == .standard(for: alphabet) || current == .letters(for: alphabet) else { return nil }
        return KeyboardTypingLayoutPolicy.caselessKeyWidths(for: alphabet, available: available, spacing: spacing)
    }
    private var hasDiacriticsPlaceholder: Bool { alphabet.isCaseless && !alphabet.diacritics.isEmpty }
    private func isDiacriticsPlaceholder(_ position: Layout.Position) -> Bool {
        hasDiacriticsPlaceholder && key(at: position) == Arrangement.shift
    }
    private static func diacriticsPosition(in current: Arrangement, ignoringDigitRows: Bool = false) -> Layout.Position? {
        let rows = current.rows.filter { cells in
            !(ignoringDigitRows && !cells.isEmpty && cells.allSatisfy { cell in
                if case .key(let key) = cell { return Arrangement.isDigit(key) }
                return false
            })
        }
        for (row, cells) in rows.enumerated() {
            if let index = cells.firstIndex(of: .key(Arrangement.shift)) { return .init(row: row, index: index) }
        }
        return nil
    }
    /// UI-only protection: retain the cap's index and its row within the
    /// letter canvas. Whole digit-only rows may appear or disappear (including
    /// when their last digit is moved); gaps and mixed rows still count.
    static func preservesDiacriticsPlace(_ next: Arrangement, in current: Arrangement, alphabet: KeyboardAlphabet) -> Bool {
        guard alphabet.isCaseless, !alphabet.diacritics.isEmpty else { return true }
        guard let fixed = diacriticsPosition(in: current, ignoringDigitRows: true) else { return false }
        return fixed == diacriticsPosition(in: next, ignoringDigitRows: true)
    }
    static func canvasMove(_ current: Arrangement, from source: Layout.Position, to destination: Layout.Position,
                           alphabet: KeyboardAlphabet) -> EditorReorder.Move<Arrangement>? {
        guard !(alphabet.isCaseless && !alphabet.diacritics.isEmpty && source == diacriticsPosition(in: current)),
              let move = EditorReorder.explicitMainKeyboard(current, from: source, to: destination, alphabet: alphabet),
              preservesDiacriticsPlace(move.value, in: current, alphabet: alphabet) else { return nil }
        return move
    }
    private var mergedSymbols: Bool {
        KeyboardMergedSymbolsPolicy.isEligible(settings: keys.snapshot, alphabet: alphabet,
            availableWidth: max(0, containerSize.width - 16), isPad: isPad,
            isLandscape: containerSize.width > containerSize.height,
            padLayout: alphabet == .english ? preferences.padLayout : .stock)
    }
    private var sections: [MainKeyboardSection] { mergedSymbols ? [.letters, .symbols] : MainKeyboardSection.allCases }
    private func sectionLabel(_ section: MainKeyboardSection) -> String {
        mergedSymbols && section == .symbols ? "Symbols" : section.accessibilityLabel
    }
    private var isSearching: Bool { !query.isEmpty }
    /// The selected place while it is on an item of the keyboard as it is now.
    private var position: Layout.Position? {
        if case .place(let position) = selection, !isDiacriticsPlaceholder(position) { return EditorReorder.selection(position, in: places) }
        return nil
    }
    /// The key in a place, by name.
    private func key(at position: Layout.Position) -> String? {
        let rows = arrangement.rows
        guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.index),
              case .key(let key) = rows[position.row][position.index] else { return nil }
        return key
    }
    /// The selected letter, digit or symbol key, whose layers can be edited.
    private var descriptor: KeyboardKeySettings.Descriptor? {
        switch selection {
        case .place(let position):
            return key(at: position).flatMap { Arrangement.isFunction($0) ? nil : $0 }
                .flatMap(KeyboardKeySettings.identifier(forCharacter:)).flatMap(KeyboardKeySettings.descriptor(for:))
        case .key(let id): return KeyboardKeySettings.descriptor(for: id)
        case nil: return nil
        }
    }
    /// Whether Restore All has anything to do, as in 1.3.
    private var canRestoreAll: Bool {
        !(keys.snapshot.overrides.isEmpty && keys.snapshot.arrangements.isEmpty && keys.saveError == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 0).id(Self.top)
                        if isSearching { results(proxy) } else { editor }
                    }
                    .padding(16)
                }
                // Measured outside the keys, so they always fit the screen.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(0, $0 - 32 - 16) }
                .background(Color(.systemGroupedBackground))
            }
            if let undoNote {
                Label(undoNote, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(undoFailed ? Color.red : Color.secondary).padding(.horizontal, 16).padding(.vertical, 8)
            }
            // Only the letters move; 123 and #+= keep the keyboard's own places.
            if section == .letters && !isSearching {
                Divider()
                controls.disabled(drag.source != nil).padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .navigationTitle("Main Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a key")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { restoreArrangement() } label: { Label("Undo Arrangement", systemImage: "arrow.uturn.backward") }
                    .disabled(keys.arrangementUndoAlphabetID != alphabet.id || drag.source != nil)
                    .accessibilityHint("Restores the arrangement before your last change on this page.")
                    .accessibilityIdentifier("mainKeyboard.undo")
            }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .onAppear {
            editorVisible = true
            keys.refresh(); drag.fit(rowCounts: places.rows.map(\.count))
            if hasAppeared { presentSuccessfulEdit() }
            else { observedEditID = keys.successfulEdit?.id; hasAppeared = true }
        }
        .onDisappear { editorVisible = false; drag.reset(); keys.invalidateArrangementUndo(); transitionBanner = nil }
        .onChange(of: keys.successfulEdit?.id) { _, _ in if editorVisible { presentSuccessfulEdit() } }
        .onChange(of: selection) { _, _ in
            if let position { rowScope = .init(row: position.row) }
        }
        .onChange(of: places.rows.count) { _, count in rowScope = rowScope.clamped(rowCount: count) }
        .onChange(of: alphabet.id) { _, _ in
            keys.invalidateArrangementUndo(); rowScope = .init(); transitionBanner = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { drag.reset() } }
        .onChange(of: mergedSymbols) { _, merged in
            if merged && section == .numbers { show(.symbols) }
        }
        .onChange(of: dragFingerprint) { _, _ in drag.reset(); drag.fit(rowCounts: places.rows.map(\.count)) }
    }

    private func restoreArrangement() {
        undoFailed = false
        switch keys.undoArrangement(alphabetID: alphabet.id) {
        case .restored:
            undoNote = nil; selection = nil; rowScope = .init(); drag.reset()
            UIAccessibility.post(notification: .announcement, argument: "Arrangement restored")
        case .invalidated: undoNote = ArrangementCopy.invalidated
        case .failed: undoNote = ArrangementCopy.restoreFailed; undoFailed = true
        }
    }

    /// Only a successful explicit preferences write emits this event. Refresh,
    /// rotation and appearance never synthesize an edit or compare old geometry.
    private func presentSuccessfulEdit() {
        guard let edit = keys.successfulEdit, edit.id != observedEditID else { return }
        observedEditID = edit.id
        undoNote = nil
        func result(_ snapshot: KeyboardKeySettings.Snapshot) -> KeyboardMergedSymbolsPolicy.Eligibility {
            KeyboardMergedSymbolsPolicy.eligibility(settings: snapshot, alphabet: alphabet,
                availableWidth: max(0, containerSize.width - 16), isPad: isPad,
                isLandscape: containerSize.width > containerSize.height,
                padLayout: alphabet == .english ? preferences.padLayout : .stock)
        }
        guard let message = KeyboardMergedSymbolsPolicy.transitionMessage(from: result(edit.before), to: result(edit.after)) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { transitionBanner = message }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    // MARK: Header and canvas

    @ViewBuilder private var editor: some View {
        if let transitionBanner {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(.tint)
                Text(transitionBanner).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                Button { self.transitionBanner = nil } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .transition(.opacity)
            .accessibilityIdentifier("mainKeyboard.symbolTransition")
        }
        VStack(alignment: .leading, spacing: 6) {
            Picker("Section", selection: Binding(get: { section }, set: { show($0) })) {
                ForEach(sections, id: \.self) { choice in
                    Text(choice.title(for: alphabet)).accessibilityLabel(sectionLabel(choice)).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mergedSymbols)
            .accessibilityIdentifier("mainKeyboard.section")
            Group {
                if mergedSymbols { Text("Choose letters or symbols to edit their keys.") }
                else { Text("Choose letters, numbers or symbols to edit their keys.") }
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        if section == .letters && preferences.alphabets.count > 1 {
            HStack {
                Text("Layout").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("Layout", selection: Binding(get: { alphabet.id }, set: { drag.reset(); alphabetID = $0; selection = nil })) {
                    ForEach(preferences.alphabets) { Text($0.nativeName).tag($0.id) }
                }
                .pickerStyle(.menu)
                .font(.subheadline)
                .accessibilityIdentifier("mainKeyboard.layout")
            }
            .frame(minHeight: 44)
        }
        if let layer = MainKeyboardSymbolLayer(section: section, arrangement: arrangement, isPad: isPad,
                                               availableWidth: max(0, containerSize.width - 16),
                                               isLandscape: containerSize.width > containerSize.height,
                                               padLayout: alphabet == .english ? preferences.padLayout : .stock, mergedSymbols: mergedSymbols) {
            VStack(alignment: .leading, spacing: 8) {
                symbolCanvas(layer)
                if mergedSymbols {
                    Text("ABC already types all ten digits, so the symbols fit on one page. Separate 123 and #+= pages return if ABC no longer types every digit or the layout no longer fits. Saved key choices stay unchanged.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            }
        } else {
            canvas
        }
        if section == .letters {
            EditorRowWidthNote(rows: wideRows)
            if UIDevice.current.userInterfaceIdiom == .phone && alphabet.id == KeyboardAlphabet.english.id {
                landscapeNumberRowNote
            }
            RowAlignmentCard(row: scopedRow, alignments: arrangement.resolvedRows.map(\.alignment), widthLimitExceeded: !wideRows.isEmpty, selectRow: { row in selection = nil; rowScope = .init(row: row) }, apply: align)
                .disabled(drag.source != nil)
        }
        if let descriptor {
            layers(descriptor).disabled(drag.source != nil)
            restoreKeyRow(descriptor)
        }
        if let error = keys.saveError {
            Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("mainKeyboard.saveError")
        }
        if failed {
            Text("This arrangement could not be saved.").font(.footnote).foregroundStyle(.red)
                .accessibilityIdentifier("mainKeyboard.error")
        }
    }

    @ViewBuilder private var landscapeNumberRowNote: some View {
        Group {
            switch arrangement.landscapeNumberRowNote {
            case .none:
                EmptyView()
            case .digitsOnly:
                Text("In landscape on iPhone, Mandarin and Japanese hide the number row so you can see what you're typing. Use the 123 key for digits there. Your arrangement doesn't change.")
            case .mixed:
                Text("In landscape on iPhone, Mandarin and Japanese hide the number row only when it holds nothing but digits. Your number row has other keys, so it stays, and there's less room to see your text.")
            }
        }
        .font(.footnote).foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    /// Switches section, as the segments and the canvas's switch key do.
    private func show(_ next: MainKeyboardSection) {
        let next = mergedSymbols && next == .numbers ? MainKeyboardSection.symbols : next
        guard next != section else { return }
        drag.reset()
        selection = nil
        rowScope = .init()
        keys.invalidateArrangementUndo()
        section = next
    }

    /// Captured values, not lookups into the mutable arrangement. SwiftUI and
    /// the UIKit drag host may still ask an outgoing tile to render after a save.
    private struct CanvasCell: Identifiable {
        let id: String
        let position: Layout.Position
        let cell: Arrangement.Cell
        let width: CGFloat
    }
    private struct CanvasRow: Identifiable {
        // Rows have no stored identity; retain the existing positional row ID.
        // Its content, alignment and end target all belong to this same snapshot.
        let id: Int
        let alignment: KeyboardRowAlignment
        let cells: [CanvasCell]
        let tooWide: Bool
        var end: Layout.Position { .init(row: id, index: cells.count) }
    }

    private var canvas: some View {
        let currentAlphabet = alphabet
        let current = keys.snapshot.effectiveArrangement(for: currentAlphabet)
        let fingerprint = Self.fingerprint(current, alphabet: currentAlphabet)
        let resolvedRows = current.resolvedRows
        let caselessWidths = Self.caselessCanvasWidths(for: current, alphabet: currentAlphabet, available: width, spacing: spacing)
        let keyWidth = caselessWidths?.letter ?? Arrangement.keyWidth(for: current.rows, available: width, spacing: spacing)
        let rows = resolvedRows.enumerated().map { row, value in
            let cells = value.cells.enumerated().map { index, item in
                let position = Layout.Position(row: row, index: index)
                let cell: Arrangement.Cell
                switch item {
                case .key(let key): cell = .key(key)
                case .halfGap: cell = .halfGap
                case .gap: cell = .gap
                }
                let id = item.key.map { "key:" + $0 } ?? drag.tileID(position)
                let cellWidth: CGFloat
                if let widths = caselessWidths, let key = item.key,
                   key == Arrangement.shift || key == Arrangement.delete { cellWidth = widths.function }
                else { cellWidth = Arrangement.width(of: cell, keyWidth: keyWidth, spacing: spacing) }
                return CanvasCell(id: id, position: position, cell: cell, width: cellWidth)
            }
            return CanvasRow(id: row, alignment: value.alignment, cells: cells,
                             tooWide: ExplicitRowEditing.units(value, keyUnits: ExplicitRowEditing.mainUnits) > ExplicitRowEditing.limit)
        }
        let canvasRows = CGFloat(max(3, rows.count))
        return VStack(spacing: 6) {
            ForEach(rows) { row in
                ExplicitKeyboardRow(alignment: row.alignment, spacing: spacing, scale: displayScale) {
                    ForEach(row.cells) { entry in
                        place(entry, current: current, alphabet: currentAlphabet, fingerprint: fingerprint)
                            .matchedGeometryEffect(id: entry.id, in: motion)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .background { EditorRowBand(selected: scopedRow == row.id && !drag.isDragging, tooWide: row.tooWide) }
                .overlay(alignment: .trailing) {
                    let end = row.end
                    EditorDragSurface(session: drag, position: end, fingerprint: fingerprint,
                                      currentFingerprint: { dragFingerprint }, draggable: false,
                                      accepts: { dragFingerprint == fingerprint && Self.canvasMove(current, from: $0, to: end, alphabet: currentAlphabet) != nil },
                                      commit: { guard dragFingerprint == fingerprint else { return }; drop($0, at: end) }) {
                        Color.clear.frame(width: 12, height: 44).contentShape(Rectangle())
                    }.offset(x: 8)
                    .overlay { EditorInsertionMark().opacity(drag.target == end ? 1 : 0) }
                }
            }
        }
        .frame(minHeight: canvasRows * 44 + (canvasRows - 1) * 6, alignment: .center)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainKeyboard.keys")
    }

    /// The 123 or #+= page: rows of ten keys at the letters' key width; on
    /// the last row the switch key and Delete take the Shift and Delete width
    /// and the punctuation shares the rest, as on the keyboard.
    private func symbolCanvas(_ layer: MainKeyboardSymbolLayer) -> some View {
        let available = width
        let keyWidth = max(0, (available - spacing * 9) / 10)
        let function = keyWidth * 1.5 + spacing / 2
        func fixedWidth(of cell: MainKeyboardSymbolLayer.Cell) -> CGFloat? {
            switch cell {
            case .key: return nil
            case .switchKey, .delete: return function
            case .returnKey: return function * 1.5
            }
        }
        return VStack(spacing: 6) {
            ForEach(Array(layer.rows.enumerated()), id: \.offset) { row in
                let cells = row.element
                let fixed = cells.compactMap(fixedWidth(of:)).reduce(0, +)
                let keyCount = cells.filter { fixedWidth(of: $0) == nil }.count
                // Ten keys fill a row; fewer, beside function keys, share what is left.
                let shared = mergedSymbols && cells.count == 6
                    ? KeyboardMergedSymbolsPolicy.punctuationWidth(available: available, spacing: spacing, deleteWidth: function)
                    : fixed == 0 ? keyWidth : max(0, (available - fixed - spacing * CGFloat(cells.count - 1)) / CGFloat(max(keyCount, 1)))
                HStack(spacing: spacing) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { entry in
                        symbolCell(entry.element, width: fixedWidth(of: entry.element) ?? shared,
                                   height: layer.canvasKeyHeight, switchTitle: layer.switchKeyTitle,
                                   section: layer.section, merged: mergedSymbols)
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

    @ViewBuilder private func symbolCell(_ cell: MainKeyboardSymbolLayer.Cell, width: CGFloat, height: CGFloat, switchTitle: String, section capturedSection: MainKeyboardSection, merged: Bool) -> some View {
        switch cell {
        case .key(let text):
            let id = KeyboardKeySettings.identifier(forCharacter: text) ?? text
            let selected = selection == .key(id)
            tile(text, selected: selected, width: width, height: height) {
                guard section == capturedSection, mergedSymbols == merged else { return }
                selection = selected ? nil : .key(id)
            }
                .accessibilityIdentifier("mainKeyboard.key.\(id)")
        case .switchKey(let target):
            Button {
                guard section == capturedSection, mergedSymbols == merged else { return }
                show(target)
            } label: {
                functionCap(width: width, height: height) {
                    Text(switchTitle)
                        .font(.system(size: 16)).minimumScaleFactor(0.5).lineLimit(1).padding(2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MainKeyboardSymbolLayer.switchLabel(to: target))
            .accessibilityIdentifier("mainKeyboard.switch")
        case .delete:
            // Drawn so the page looks like the keyboard; it does nothing here.
            functionCap(width: width, height: height) { Image(systemName: "delete.left").font(.system(size: 18, weight: .medium)) }
                .accessibilityHidden(true)
        case .returnKey:
            functionCap(width: width, height: height) { Image(systemName: "return").font(.system(size: 18, weight: .medium)) }
                .accessibilityHidden(true)
        }
    }

    private func functionCap<Label: View>(width: CGFloat, height: CGFloat = 44, @ViewBuilder label: () -> Label) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.functionKey)
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            label()
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func place(_ entry: CanvasCell, current: Arrangement,
                                    alphabet: KeyboardAlphabet, fingerprint: String) -> some View {
        let position = entry.position
        let cell = entry.cell
        let selected = selection == .place(position)
        let active = drag.source == position
        if alphabet.isCaseless && !alphabet.diacritics.isEmpty && cell == .key(Arrangement.shift) {
            // A display-only Arabic Diacritics cap, never a selectable Button
            // or drag/drop surface (design §7.3). The circle is preview-only.
            functionCap(width: entry.width) {
                Text(symbolKeyPreview(alphabet.diacritics[0].mark))
                    .font(.system(size: 22)).minimumScaleFactor(0.4).lineLimit(1).padding(2)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            EditorDragSurface(session: drag, position: position, fingerprint: fingerprint,
                              currentFingerprint: { dragFingerprint },
                              draggable: true,
                              accepts: { dragFingerprint == fingerprint && Self.canvasMove(current, from: $0, to: position, alphabet: alphabet) != nil },
                              commit: { guard dragFingerprint == fingerprint else { return }; drop($0, at: position) }) {
                if case .key(let key) = cell {
                    tile(key, selected: selected && !active, width: entry.width) {
                        guard section == .letters, dragFingerprint == fingerprint, !drag.isDragging else { return }
                        selection = selected ? nil : .place(position)
                    }
                    .accessibilityIdentifier("mainKeyboard.key.\(Arrangement.isFunction(key) ? key : KeyboardKeySettings.identifier(forCharacter: key) ?? key)")
                } else {
                    Button {
                        guard section == .letters, dragFingerprint == fingerprint, !drag.isDragging else { return }
                        selection = selected ? nil : .place(position)
                    } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.5),
                                          style: StrokeStyle(lineWidth: selected ? 2.5 : 1, dash: selected ? [] : [3, 3]))
                            .frame(width: entry.width, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cell == .halfGap ? "Half-width gap" : "Full-width gap")
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
    }

    /// A key as the keyboard draws it: Shift, Delete, Tab and Caps Lock in
    /// the darker grey of iOS's own function keys. A key with saved choices
    /// shows a dot, and VoiceOver reads it as Customized.
    private func tile(_ key: String, selected: Bool, width: CGFloat, height: CGFloat = 44, action: @escaping () -> Void) -> some View {
        let function = Arrangement.isFunction(key)
        let id = function ? nil : KeyboardKeySettings.identifier(forCharacter: key)
        // A changed key shows what it now types.
        let shown = id.flatMap { keys.snapshot.tapOutput(for: $0, defaultText: key, shifted: false) } ?? key
        let customized = id.map { keys.snapshot.overrides[$0] != nil } ?? false
        return Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(function ? Color.functionKey : Color.editorKeyTile)
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
                if let symbol = Self.symbol(key) {
                    Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                } else {
                    Text(symbolKeyPreview(shown)).font(.system(size: 22)).minimumScaleFactor(0.4).lineLimit(1).padding(2)
                }
                if customized {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
                }
                // Hidden from the moment a drag lifts, so its preview never shows it.
                if selected { EditorSelectionBorder(cornerRadius: 7) }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Key \(Self.label(key))")
        .accessibilityValue((customized ? "Customized" : "") + (position.map { wideRows.contains($0.row) } == true ? ", Row too wide" : ""))
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

    // MARK: Layers and restore

    /// The selected key's own output and its three candidate layers.
    private func layers(_ descriptor: KeyboardKeySettings.Descriptor) -> some View {
        KeyLayersPanel(layers: [.tap, .swipeUp, .longPress, .swipeDown], holdNotes: KeyboardPunctuationChoice.editorNotes(
            for: descriptor.text ?? descriptor.title,
            savedHoldChoices: keys.snapshot.candidates(for: descriptor.id, gesture: .longPress) ?? []
        ), choices: { gesture in
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

    /// Restores one key's saved choices: every layer, its tap output included.
    private func restoreKeyRow(_ descriptor: KeyboardKeySettings.Descriptor) -> some View {
        let saved = keys.snapshot.overrides[descriptor.id] != nil
        return Button(role: .destructive) { confirmsRestoreKey = true } label: {
            Text("Restore this key’s defaults")
                .foregroundStyle(saved ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .frame(minHeight: 52)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!saved || drag.source != nil)
        .accessibilityIdentifier("mainKeyboard.resetKey")
        // Anchored to the row, so the popover's arrow points at it.
        .confirmationDialog("Restore this key’s defaults?", isPresented: $confirmsRestoreKey, titleVisibility: .visible) {
            Button("Restore defaults", role: .destructive) { keys.reset(keyID: descriptor.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: More menu

    private var moreMenu: some View {
        Menu {
            // Arranging applies to the letters only.
            if section == .letters {
                Section {
                    optionalKey(Arrangement.tab, title: "Tab", row: 0)
                    optionalKey(Arrangement.caps, title: "Caps Lock", row: 1)
                    addDigits
                    Button { selection = nil; failed = !keys.saveArrangement(nil, alphabetID: alphabet.id) } label: {
                        Label("Standard Layout", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(keys.snapshot.arrangement(for: alphabet.id) == nil)
                    .accessibilityIdentifier("mainKeyboard.reset")
                }
            }
            Section {
                Button(role: .destructive) { confirmsRestoreAll = true } label: {
                    Label {
                        Text("Restore All Key Defaults")
                        Text("Resets letters, numbers and symbols, and every layout’s arrangement.")
                    } icon: { Image(systemName: "arrow.counterclockwise.circle") }
                }
                .disabled(!canRestoreAll)
                .accessibilityIdentifier("mainKeyboard.resetAll")
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .disabled(drag.source != nil)
        .accessibilityLabel("More").accessibilityIdentifier("mainKeyboard.more")
        // Attached to the ⋯ button, so the popover's arrow points at it.
        .confirmationDialog("Restore all key defaults?", isPresented: $confirmsRestoreAll, titleVisibility: .visible) {
            Button("Restore All Key Defaults", role: .destructive) {
                if keys.resetAll() { drag.reset(); selection = nil; failed = false }
            }
            .accessibilityIdentifier("mainKeyboard.resetAll.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets all letter, number and symbol key actions, including taps, and restores the standard key arrangement and number row for every layout. Your symbol pages, favorites, enabled layouts and other settings are kept.")
        }
    }

    // MARK: Find a key

    @ViewBuilder private func results(_ proxy: ScrollViewProxy) -> some View {
        let groups = MainKeyboardKeySearch.search(query, alphabet: alphabet, arrangement: arrangement, isPad: isPad, mergedSymbols: mergedSymbols)
        if groups.isEmpty {
            ContentUnavailableView("No matching keys", systemImage: "magnifyingglass", description: Text("Try another search."))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .accessibilityIdentifier("mainKeyboard.noResults")
        }
        ForEach(groups, id: \.section) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.section.title(for: alphabet))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityLabel(sectionLabel(group.section))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mainKeyboard.results.\(group.section.rawValue)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 8)], spacing: 8) {
                    ForEach(group.keys) { descriptor in
                        let customized = keys.snapshot.overrides[descriptor.id] != nil
                        Button { choose(descriptor, in: group.section, proxy: proxy) } label: {
                            VStack(spacing: 4) {
                                Text(descriptor.title).font(.title3)
                                Circle().fill(customized ? Color.accentColor : Color.clear).frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Configure \(descriptor.title) key")
                        .accessibilityValue(customized ? "Customized" : "")
                        .accessibilityIdentifier("mainKeyboard.result.\(descriptor.id)")
                    }
                }
            }
        }
    }

    /// Ends the search and shows the found key selected in its section, at the top.
    private func choose(_ descriptor: KeyboardKeySettings.Descriptor, in found: MainKeyboardSection, proxy: ScrollViewProxy) {
        // An outgoing search result can outlive a change in the page set.
        let found = mergedSymbols ? (descriptor.kind == .character ? MainKeyboardSection.symbols : .letters) : found
        query = ""
        searching = false
        drag.reset()
        section = found
        let place = found == .letters ? letterPlace(descriptor.id) : nil
        selection = place.map { Selection.place($0) } ?? Selection.key(descriptor.id)
        DispatchQueue.main.async { proxy.scrollTo(Self.top, anchor: .top) }
    }

    /// Where a letter is on the arrangement.
    private func letterPlace(_ id: String) -> Layout.Position? {
        let rows = arrangement.rows
        for (row, cells) in rows.enumerated() {
            for (index, cell) in cells.enumerated() {
                if case .key(let key) = cell, KeyboardKeySettings.identifier(forCharacter: key) == id {
                    return .init(row: row, index: index)
                }
            }
        }
        return nil
    }

    // MARK: Arranging the letters

    private var controls: some View {
        let position = position
        let item = position.flatMap(places.item(at:))
        let rows = places.rows
        // Shift, Delete and the letters always stay; digits, Tab and Caps Lock may go.
        let removable = position.flatMap(key(at:)).map { $0 == Arrangement.tab || $0 == Arrangement.caps || Arrangement.isDigit($0) } ?? (item != nil)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                control("Move Left", "arrow.left", id: "mainKeyboard.left", enabled: position.map { $0.index > 0 && canMove($0, to: .init(row: $0.row, index: $0.index - 1)) } ?? false) {
                    guard let p = position else { return }
                    move(from: p, to: .init(row: p.row, index: p.index - 1), select: .init(row: p.row, index: p.index - 1))
                }
                control("Move Right", "arrow.right", id: "mainKeyboard.right", enabled: position.map { $0.index + 1 < rows[$0.row].count && canMove($0, to: .init(row: $0.row, index: $0.index + 2)) } ?? false) {
                    guard let p = position else { return }
                    move(from: p, to: .init(row: p.row, index: p.index + 2), select: .init(row: p.row, index: p.index + 1))
                }
                control("Move Up", "arrow.up", id: "mainKeyboard.up", enabled: position.map { $0.row > 0 && canMove($0, to: .init(row: $0.row - 1, index: min($0.index, rows[$0.row - 1].count))) } ?? false) {
                    guard let p = position else { return }
                    let index = min(p.index, rows[p.row - 1].count)
                    move(from: p, to: .init(row: p.row - 1, index: index), select: .init(row: p.row - 1, index: index))
                }
                control("Move Down", "arrow.down", id: "mainKeyboard.down", enabled: position.map { $0.row + 1 < rows.count && canMove($0, to: .init(row: $0.row + 1, index: min($0.index, rows[$0.row + 1].count))) } ?? false) {
                    guard let p = position else { return }
                    let index = min(p.index, rows[p.row + 1].count)
                    // A row emptied by the move goes away, so the next row takes its place.
                    let row = rows[p.row].count == 1 ? p.row : p.row + 1
                    move(from: p, to: .init(row: p.row + 1, index: index), select: .init(row: row, index: index))
                }
            }
            HStack(spacing: 8) {
                control("Half Gap", "rectangle.lefthalf.inset.filled", id: "mainKeyboard.halfGap",
                        enabled: position.map { canEditRows(.halfGap($0)) } ?? false) { insert(.halfGap) }
                control("Gap", "rectangle.dashed", id: "mainKeyboard.gap",
                        enabled: position.map { canEditRows(.gap($0)) } ?? false) { insert(.gap) }
                control("New Row", "return", id: "mainKeyboard.newRow",
                        enabled: position.map { canEditRows(.split($0)) } ?? false) {
                    guard let p = position else { return }
                    editRows(.split(p), select: .place(.init(row: p.row + 1, index: 0)))
                }
                if position?.index == 0 && (position?.row ?? 0) > 0 {
                    control("Join Rows", "arrow.turn.left.up", id: "mainKeyboard.joinRow", enabled: position.map { canEditRows(.join($0.row)) } ?? false) {
                        guard let p = position else { return }
                        let index = rows[p.row - 1].count
                        editRows(.join(p.row), select: .place(.init(row: p.row - 1, index: index)))
                    }
                } else {
                    control("Remove", "minus.circle", id: "mainKeyboard.remove", enabled: item != nil && removable && (!hasDiacriticsPlaceholder || position.map { canEditRows(.remove($0)) } == true)) {
                        guard let p = position else { return }
                        editRows(.remove(p), select: nil)
                    }
                }
            }
        }
    }

    private func control(_ title: String, _ icon: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let fingerprint = dragFingerprint
        return Button {
            guard section == .letters, dragFingerprint == fingerprint else { return }
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        // Keep four icon-only controls inside the viewport at AX sizes;
        // spoken labels and the Large Content Viewer remain available.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .disabled(!enabled || position == nil)
        .accessibilityLabel(title)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: icon) }
        .accessibilityIdentifier(id)
    }

    /// Adds Tab or Caps Lock at the start of a row of letters, counted
    /// from the first one so a number row above them is skipped, or removes it.
    @ViewBuilder private func optionalKey(_ key: String, title: String, row letterRow: Int) -> some View {
        let fingerprint = dragFingerprint
        let row = (arrangement.firstLetterRow ?? 0) + letterRow
        if let index = arrangement.keys.firstIndex(of: key) {
            Button {
                guard section == .letters, dragFingerprint == fingerprint else { return }
                if let p = placeForKeyIndex(index) { editRows(.remove(p), select: nil) }
            } label: {
                Label("Remove \(title)", systemImage: "minus.circle")
            }
            .accessibilityIdentifier("mainKeyboard.remove.\(title)")
        } else {
            Button {
                guard section == .letters, dragFingerprint == fingerprint else { return }
                var rows = arrangement.resolvedRows
                let target = min(row, rows.count - 1)
                guard target >= 0, ExplicitRowEditing.units(rows[target], keyUnits: ExplicitRowEditing.mainUnits) + 1.5 <= ExplicitRowEditing.limit else { return }
                rows[target].cells.insert(.key(key), at: 0)
                save(ExplicitRowEditing.main(arrangement, rows: rows), select: nil)
            } label: { Label("Add \(title)", systemImage: "plus.circle") }
            .disabled(!canAddFunction(to: row))
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
                guard let next = addingDigits() else { failed = true; return }
                save(next, select: nil)
            } label: { Label(all ? "Add Number Row" : "Add Missing Digits", systemImage: "plus.circle") }
            .disabled(addingDigits() == nil)
            .accessibilityIdentifier("mainKeyboard.add.digits")
        }
    }

    private func insert(_ gap: Layout.Item) {
        guard let p = position else { return }
        editRows(gap == .halfGap ? .halfGap(p) : .gap(p), select: .place(p))
    }

    private func canMove(_ source: Layout.Position, to destination: Layout.Position) -> Bool {
        Self.canvasMove(arrangement, from: source, to: destination, alphabet: alphabet) != nil
    }
    private func canEditRows(_ action: ExplicitRowEditing.Action) -> Bool {
        guard let rows = ExplicitRowEditing.applying(action, to: arrangement.resolvedRows, maximumRows: Arrangement.maximumRows, keyUnits: ExplicitRowEditing.mainUnits) else { return false }
        let next = ExplicitRowEditing.main(arrangement, rows: rows)
        return next.isValid(for: alphabet) && Self.preservesDiacriticsPlace(next, in: arrangement, alphabet: alphabet)
    }
    private func editRows(_ action: ExplicitRowEditing.Action, select next: Selection?) {
        guard let rows = ExplicitRowEditing.applying(action, to: arrangement.resolvedRows, maximumRows: Arrangement.maximumRows, keyUnits: ExplicitRowEditing.mainUnits) else { return }
        save(ExplicitRowEditing.main(arrangement, rows: rows), select: next)
    }
    private func align(_ alignment: KeyboardRowAlignment) {
        var rows = arrangement.resolvedRows
        guard ExplicitRowEditing.fits(rows, keyUnits: ExplicitRowEditing.mainUnits) else { return }
        for index in rows.indices where scopedRow == nil || index == scopedRow { rows[index].alignment = alignment }
        withAnimation(.editorReorder(reduceMotion: reduceMotion)) { save(Arrangement(rows: rows), select: selection) }
    }
    private func placeForKeyIndex(_ keyIndex: Int) -> Layout.Position? {
        let currentPlaces = places
        for (row, cells) in currentPlaces.rows.enumerated() {
            for index in cells.indices {
                let p = Layout.Position(row: row, index: index)
                if currentPlaces.keyIndex(at: p) == keyIndex { return p }
            }
        }
        return nil
    }
    private func canAddFunction(to row: Int) -> Bool {
        let rows = arrangement.resolvedRows
        return rows.indices.contains(row) && ExplicitRowEditing.units(rows[row], keyUnits: ExplicitRowEditing.mainUnits) + 1.5 <= ExplicitRowEditing.limit
    }
    private func addingDigits() -> Arrangement? {
        let missing = arrangement.missingDigits
        guard !missing.isEmpty else { return nil }
        var rows = arrangement.resolvedRows
        if let last = rows.lastIndex(where: { $0.cells.contains { $0.key.map(Arrangement.isDigit) ?? false } }) {
            guard ExplicitRowEditing.units(rows[last], keyUnits: ExplicitRowEditing.mainUnits) + Double(missing.count) <= ExplicitRowEditing.limit else { return nil }
            rows[last].cells += missing.map { .key($0) }
        } else {
            guard rows.count < Arrangement.maximumRows else { return nil }
            rows.insert(.init(alignment: rows.first?.alignment ?? .center, cells: missing.map { .key($0) }), at: 0)
        }
        let next = ExplicitRowEditing.main(arrangement, rows: rows)
        return Self.preservesDiacriticsPlace(next, in: arrangement, alphabet: alphabet) ? next : nil
    }

    /// The arrow buttons: the VoiceOver and Switch Control way to move.
    private func move(from source: Layout.Position, to destination: Layout.Position, select next: Layout.Position?) {
        guard let move = Self.canvasMove(arrangement, from: source, to: destination, alphabet: alphabet) else { return }
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
        guard let move = Self.canvasMove(arrangement, from: source, to: destination, alphabet: alphabet),
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
        guard Self.preservesDiacriticsPlace(move.value, in: arrangement, alphabet: alphabet) else { return false }
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
        guard Self.preservesDiacriticsPlace(next, in: arrangement, alphabet: alphabet) else { return }
        failed = !keys.saveArrangement(next, alphabetID: alphabet.id)
        if !failed { selection = select }
    }
}

extension Color {
    static let editorKeyTile = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray3 : .secondarySystemGroupedBackground
    })
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

        var canDrag: Bool {
            parent.draggable && isEnabled && (parent.currentFingerprint?() ?? parent.fingerprint) == parent.fingerprint
        }

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
