import Foundation
import CoreGraphics

/// The main keyboard's rows as the app arranged them: the number row, the
/// layout's letters with Shift and Delete, and optionally Tab and Caps Lock,
/// in up to four rows with half-width and full-width gaps. Its places are
/// stored like a page's, so the same editing moves keys, gaps and row breaks.
/// Digits are ordinary keys: each at most once, anywhere, or not at all.
struct MainKeyboardArrangement: Codable, Equatable, Sendable {
    static let shift = "{shift}", delete = "{delete}", tab = "{tab}", caps = "{caps}"
    static let functionKeys = [shift, delete, tab, caps]
    static let digits = Array("1234567890").map(String.init)
    /// The number row and three rows of letters.
    static let maximumRows = 4
    /// Typing and wide iPad layouts always get three rows of letters.
    static let letterRowCount = 3

    typealias Row = KeyboardRow<String>
    private var legacyKeys: [String]
    private var legacyLayout: String
    private(set) var explicitRows: [Row]?
    var isLegacy: Bool { explicitRows == nil }
    var resolvedRows: [Row] { explicitRows ?? Row.legacy(keys: legacyKeys, layout: legacyLayout, alignment: .center) }
    /// Compatibility projections; nested cells alone own explicit order.
    var keys: [String] {
        get { explicitRows?.flatMap { $0.cells.compactMap(\.key) } ?? legacyKeys }
        set {
            if let rows = explicitRows { explicitRows = Row.replacingKeys(rows, with: newValue, alignment: .center) }
            else { legacyKeys = newValue }
        }
    }
    var layout: String {
        get { explicitRows.map(Row.layout) ?? legacyLayout }
        set {
            if let rows = explicitRows { explicitRows = Row.replacingLayout(rows, with: newValue, alignment: .center) }
            else { legacyLayout = newValue }
        }
    }
    init(keys: [String], layout: String) { legacyKeys = keys; legacyLayout = layout }
    init(rows: [Row]) { legacyKeys = []; legacyLayout = ""; explicitRows = rows }
    @discardableResult mutating func setExplicitRows(_ rows: [Row]) -> Bool {
        guard !rows.isEmpty, Row.valid(rows, maximumRows: Self.maximumRows) else { return false }
        self = Self(rows: rows); return true
    }
    @discardableResult mutating func convertToExplicitRows() -> Bool { setExplicitRows(resolvedRows) }
    private enum CodingKeys: String, CodingKey { case keys, layout, rows }
    init(from decoder: Decoder) throws {
        try ExplicitRowCoding.allow(decoder, ["keys", "layout", "rows"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.rows) {
            guard !c.contains(.keys), !c.contains(.layout) else { throw ExplicitRowCoding.invalid }
            let rows = try c.decode([Row].self, forKey: .rows)
            self.init(rows: rows)
            guard !rows.isEmpty, Row.valid(rows, maximumRows: Self.maximumRows) else { throw ExplicitRowCoding.invalid }
        } else { self.init(keys: try c.decode([String].self, forKey: .keys), layout: try c.decode(String.self, forKey: .layout)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let rows = explicitRows {
            guard !rows.isEmpty, Row.valid(rows, maximumRows: Self.maximumRows) else { throw ExplicitRowCoding.invalid }
            try c.encode(rows, forKey: .rows)
        } else { try c.encode(legacyKeys, forKey: .keys); try c.encode(legacyLayout, forKey: .layout) }
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.explicitRows == rhs.explicitRows && lhs.layout == rhs.layout
            && SymbolBoardKey.exact(lhs.keys, rhs.keys)
    }

    enum Cell: Hashable { case key(String), halfGap, gap }

    /// The default keyboard: the number row, then the layout's own rows with
    /// Shift and Delete around the last one.
    static func standard(for alphabet: KeyboardAlphabet) -> MainKeyboardArrangement {
        letters(for: alphabet).prependingNumberRow
    }

    /// The layout's own rows without the number row. A caseless layout has
    /// no Shift; Arabic keeps the place for its Diacritics key.
    static func letters(for alphabet: KeyboardAlphabet) -> MainKeyboardArrangement {
        let rows = alphabet.rows
        let leading = alphabet.hasShiftSlot ? [shift] : []
        return MainKeyboardArrangement(keys: rows[0] + rows[1] + leading + rows[2] + [delete],
            layout: [rows[0].count, rows[1].count, rows[2].count + leading.count + 1].map { String(repeating: "k", count: $0) }.joined(separator: "/"))
    }

    static func isFunction(_ key: String) -> Bool { functionKeys.contains(key) }
    static func isDigit(_ key: String) -> Bool { digits.contains(key) }

    enum DigitRowKind: Equatable {
        case none, digitsOnly, mixed

        /// Gaps do not participate; an empty row must never qualify by vacuity.
        static func classify(keys: [String]) -> Self {
            guard keys.contains(where: MainKeyboardArrangement.isDigit) else { return .none }
            return keys.allSatisfy(MainKeyboardArrangement.isDigit) ? .digitsOnly : .mixed
        }
    }

    /// One classifier for presentation and the editor's saved-arrangement note.
    /// Read legacy slots directly: rendering adapters can discard empty rows or
    /// trailing gaps, neither of which is an edit this projection may make.
    var digitRowKinds: [DigitRowKind] {
        if let explicitRows {
            return explicitRows.map { DigitRowKind.classify(keys: $0.cells.compactMap(\.key)) }
        }
        guard let places, places.keySlots == keys.count else { return [] }
        var index = 0
        return places.rows.map { row in
            let end = index + row.filter { $0 == .key }.count
            defer { index = end }
            return DigitRowKind.classify(keys: Array(keys[index..<end]))
        }
    }

    /// Any mixed digit row takes precedence, even beside another pure row.
    var landscapeNumberRowNote: DigitRowKind {
        let kinds = digitRowKinds
        if kinds.contains(.mixed) { return .mixed }
        return kinds.contains(.digitsOnly) ? .digitsOnly : .none
    }

    /// Presentation only. Remove complete pure-digit rows, never individual
    /// cells from mixed rows. Preserve legacy rendering and explicit alignment.
    var hidingPureDigitRows: MainKeyboardArrangement {
        let kinds = digitRowKinds
        guard kinds.contains(.digitsOnly) else { return self }
        if let explicitRows {
            return Self(rows: explicitRows.enumerated().compactMap { index, row in
                kinds[index] == .digitsOnly ? nil : row
            })
        }
        guard let places else { return self }
        var index = 0
        var retainedKeys: [String] = []
        var retainedRows: [[SymbolPageLayout.Item]] = []
        for (rowIndex, row) in places.rows.enumerated() {
            let end = index + row.filter { $0 == .key }.count
            if kinds[rowIndex] != .digitsOnly {
                retainedKeys += keys[index..<end]
                retainedRows.append(row)
            }
            index = end
        }
        return Self(keys: retainedKeys, layout: SymbolPageLayout(rows: retainedRows).text)
    }

    /// The digits this keyboard does not have, in number-row order.
    var missingDigits: [String] { Self.digits.filter { !keys.contains($0) } }

    /// The rows the keyboard is tall: at least three, so the other pages fit.
    var typingRowCount: Int { max(Self.letterRowCount, places?.rows.count ?? 0) }

    /// The typing rows above the footer on every page. A wide iPad draws
    /// its own letter rows, with the number row above them only while this
    /// arrangement has digits.
    func keyRows(widePad: Bool) -> Int {
        guard widePad, isLegacy else { return typingRowCount }
        return missingDigits.count < Self.digits.count ? Self.maximumRows : Self.letterRowCount
    }

    /// The first row holding a letter: 1 below the standard number row.
    var firstLetterRow: Int? {
        rows.firstIndex { $0.contains { cell in
            if case .key(let key) = cell { return !Self.isFunction(key) && !Self.isDigit(key) }
            return false
        } }
    }

    /// The missing digits put back: the whole number row as its own first
    /// row, or the missing ones at the end of the row holding the last digit.
    /// Nil when nothing is missing or there is no room.
    func addingDigits() -> MainKeyboardArrangement? {
        let missing = missingDigits
        guard !missing.isEmpty, let places, places.keySlots == keys.count else { return nil }
        // No digit left: all ten go back as their own first row.
        guard let last = keys.lastIndex(where: Self.isDigit) else {
            return places.rows.count < Self.maximumRows ? prependingNumberRow : nil
        }
        var rows = places.rows
        var row = 0, before = 0
        while before + rows[row].filter({ $0 == .key }).count <= last {
            before += rows[row].filter { $0 == .key }.count
            row += 1
        }
        rows[row] += Array(repeating: .key, count: missing.count)
        guard SymbolPageLayout.units(rows[row]) <= SymbolPageLayout.maximumRowUnits else { return nil }
        var next = keys
        next.insert(contentsOf: missing, at: before + rows[row].filter { $0 == .key }.count - missing.count)
        if let explicitRows {
            let result = Row.slots(keys: next, layout: SymbolPageLayout(rows: rows), alignment: .center)
            let updated = result.enumerated().map { index, row in
                Row(alignment: explicitRows[index].alignment, cells: row.cells)
            }
            return Row.valid(updated, maximumRows: Self.maximumRows) ? Self(rows: updated) : nil
        }
        return MainKeyboardArrangement(keys: next, layout: SymbolPageLayout(rows: rows).text)
    }

    /// These rows with the stock number row: every digit taken from where it
    /// is, rows left without a key dropped, then all ten as their own first
    /// row, as `standard` has them. Letters, gaps and other keys stay put.
    /// Nil when the layout is unreadable or the rows leave no room on top.
    func withStockNumberRow() -> MainKeyboardArrangement? {
        if let rows = explicitRows {
            let remaining = rows.compactMap { row -> Row? in
                let cells = row.cells.filter { cell in cell.key.map { !Self.isDigit($0) } ?? true }
                return cells.contains(where: { $0.key != nil }) ? Row(alignment: row.alignment, cells: cells) : nil
            }
            guard !remaining.isEmpty, remaining.count < Self.maximumRows else { return nil }
            return Self(rows: [Row(alignment: .center, cells: Self.digits.map { .key($0) })] + remaining)
        }
        guard var places, places.keySlots == keys.count else { return nil }
        var next = keys
        for index in keys.indices.reversed() where Self.isDigit(keys[index]) {
            places.removeKeySlot(index); next.remove(at: index)
        }
        guard !places.rows.isEmpty, places.rows.count < Self.maximumRows else { return nil }
        return MainKeyboardArrangement(keys: next, layout: places.text).prependingNumberRow
    }

    /// The number row added as a new first row above these rows. Used on
    /// arrangements without digits, which then have the standard top row.
    var prependingNumberRow: MainKeyboardArrangement {
        if let rows = explicitRows { return Self(rows: [Row(alignment: .center, cells: Self.digits.map { .key($0) })] + rows) }
        return MainKeyboardArrangement(keys: Self.digits + keys, layout: String(repeating: "k", count: Self.digits.count) + "/" + layout)
    }

    var places: SymbolPageLayout? { SymbolPageLayout(layout) }

    /// Every letter once, Shift and Delete once, Tab, Caps Lock and each
    /// digit at most once, each in a place, in at most four rows. A caseless
    /// layout has no Caps Lock, and Shift's place only for Arabic Diacritics.
    func isValid(for alphabet: KeyboardAlphabet) -> Bool {
        guard explicitRows.map({ Row.valid($0, maximumRows: Self.maximumRows) }) ?? true,
              let places, places.rows.count <= Self.maximumRows, places.keySlots == keys.count,
              places.rows.allSatisfy({ $0.contains(.key) }) else { return false }
        let functions = keys.filter(Self.isFunction), numbers = keys.filter(Self.isDigit)
        if explicitRows != nil {
            let letters = keys.filter { !Self.isFunction($0) && !Self.isDigit($0) }.map { Array($0.utf16) }
            let expected = alphabet.keys.map { Array($0.utf16) }
            guard letters.count == expected.count, Set(letters) == Set(expected) else { return false }
        }
        return KeyboardAlphabet.isArrangement(keys.filter { !Self.isFunction($0) && !Self.isDigit($0) }, of: alphabet.keys)
            && functions.contains(Self.shift) == alphabet.hasShiftSlot && functions.contains(Self.delete)
            && !(alphabet.isCaseless && functions.contains(Self.caps)) && Set(functions).count == functions.count
            && Set(numbers).count == numbers.count
    }

    /// What versions before the number row joined the arrangement could
    /// store: no digits and at most three rows.
    var isLetterOnly: Bool { missingDigits.count == Self.digits.count && (places?.rows.count ?? 0) <= Self.letterRowCount }

    /// The rows as the keyboard draws them.
    var rows: [[Cell]] {
        if let rows = explicitRows {
            return rows.map { $0.cells.map { cell in
                switch cell { case .key(let key): return .key(key); case .halfGap: return .halfGap; case .gap: return .gap }
            } }
        }
        guard let places else { return [] }
        return places.cells(keyCount: keys.count).map { row in
            row.map { cell in
                switch cell {
                case .key(let index): return .key(keys[index])
                case .halfGap: return .halfGap
                case .gap: return .gap
                }
            }
        }
    }

    /// The rows' letters, always three rows, for typing and wide iPad rows.
    /// Rows without letters, such as the number row, are left out, and a
    /// fourth row of letters joins the third.
    var letterRows: [[String]] {
        let letters = rows.map { $0.compactMap { cell -> String? in
            if case .key(let key) = cell, !Self.isFunction(key), !Self.isDigit(key) { return key }
            return nil
        } }.filter { !$0.isEmpty }
        let count = Self.letterRowCount
        let joined = letters.count > count ? Array(letters.prefix(count - 1)) + [letters.dropFirst(count - 1).flatMap { $0 }] : letters
        return joined + Array(repeating: [], count: max(0, count - joined.count))
    }

    /// One key width for every row: ten letters fill a row and a longer row
    /// narrows every key. A function key is one and a half letters wide.
    static func keyWidth(for rows: [[Cell]], available: CGFloat, spacing: CGFloat) -> CGFloat {
        guard available.isFinite, available > 0, spacing.isFinite, spacing >= 0 else { return 0 }
        var width = (available - spacing * 9) / 10
        for row in rows where !row.isEmpty {
            let units = row.reduce(0.0) { $0 + Self.units($1) }
            // Function keys add half a spacing each; half gaps give half a spacing back.
            let extra = row.reduce(0.0) { total, cell in
                if case .key(let key) = cell, isFunction(key) { return total + spacing / 2 }
                return cell == .halfGap ? total - spacing / 2 : total
            }
            width = min(width, (available - spacing * CGFloat(row.count - 1) - extra) / units)
        }
        return max(0, width)
    }

    static func width(of cell: Cell, keyWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        switch cell {
        case .key(let key): return isFunction(key) ? keyWidth * 1.5 + spacing / 2 : keyWidth
        case .halfGap: return max(0, (keyWidth - spacing) / 2)
        case .gap: return keyWidth
        }
    }

    private static func units(_ cell: Cell) -> CGFloat {
        switch cell {
        case .key(let key): return isFunction(key) ? 1.5 : 1
        case .halfGap: return 0.5
        case .gap: return 1
        }
    }
}

/// A geometry-scoped view of the saved arrangement. The original width basis
/// travels with the rows so hiding the widest row never widens retained keys.
/// Digit action identifiers/settings stay shared with the ordinary 123 page.
struct KeyboardTypingPresentation: Equatable {
    let arrangement: MainKeyboardArrangement
    let widthBasis: MainKeyboardArrangement
    let isCompactConversion: Bool
    var allowsMergedSymbols: Bool { !isCompactConversion }

    init(arrangement: MainKeyboardArrangement, mode: LanguageInputMode,
         isPhone: Bool, isCompactLayout: Bool, isTyping: Bool = true) {
        let conversion: Bool
        switch mode {
        case .mandarinPinyin, .japaneseRomaji, .koreanRomaja: conversion = true
        case .direct, .koreanTwoSetHangul: conversion = false
        }
        isCompactConversion = isPhone && isCompactLayout && isTyping && conversion
        widthBasis = arrangement
        self.arrangement = isCompactConversion ? arrangement.hidingPureDigitRows : arrangement
    }
}

// MARK: - Main Keyboard sections

/// Main Keyboard's three sections, one for each typing page of the keyboard:
/// the letters, the 123 page and the #+= page.
enum MainKeyboardSection: String, CaseIterable, Sendable {
    case letters, numbers, symbols

    /// The keyboard page the section edits.
    var layout: KeyboardTypingLayout {
        switch self {
        case .letters: return .letters
        case .numbers: return .numbers
        case .symbols: return .symbols
        }
    }

    /// The section's visible title, as the keyboard's own key for that page
    /// reads; the letters follow the layout.
    func title(for alphabet: KeyboardAlphabet) -> String {
        switch self {
        case .letters: return alphabet.lettersKeyTitle
        case .numbers: return "123"
        case .symbols: return "#+="
        }
    }

    /// What VoiceOver reads for the section, whatever its visible title.
    var accessibilityLabel: String {
        switch self {
        case .letters: return "Letters"
        case .numbers: return "Numbers and Symbols"
        case .symbols: return "More Symbols"
        }
    }
}

/// The 123 or #+= page as the keyboard draws it on a device, for Main
/// Keyboard's canvas. The keys never move; only their layers change.
struct MainKeyboardSymbolLayer: Equatable, Sendable {
    enum Cell: Hashable, Sendable {
        /// A symbol or digit key, by the text it shows.
        case key(String)
        /// The key that switches to the other symbol page.
        case switchKey(MainKeyboardSection)
        case delete
        /// Return, drawn on a wide iPad after Delete.
        case returnKey
    }

    let section: MainKeyboardSection
    let rows: [[Cell]]
    let switchKeyTitle: String
    let canvasKeyHeight: CGFloat

    /// Only letters use the saved arrangement directly. Symbol pages need
    /// actual container geometry to match narrow/floating and ANSI keyboards.
    init?(section: MainKeyboardSection, arrangement: MainKeyboardArrangement, isPad: Bool,
          availableWidth: CGFloat = 0, isLandscape: Bool = false, padLayout: KeyboardPadLayout = .stock, mergedSymbols: Bool = false) {
        guard section != .letters else { return nil }
        self.init(page: mergedSymbols ? .symbols : section, arrangement: arrangement, isPad: isPad,
                  availableWidth: availableWidth, isLandscape: isLandscape, padLayout: padLayout, mergedSymbols: mergedSymbols)
    }

    /// The 123 or #+= page; `page` is never the letters.
    fileprivate init(page section: MainKeyboardSection, arrangement: MainKeyboardArrangement, isPad: Bool,
                     availableWidth: CGFloat = 0, isLandscape: Bool = false, padLayout: KeyboardPadLayout = .stock, mergedSymbols: Bool = false) {
        if mergedSymbols {
            let mergedRows: [[String]] = KeyboardMergedSymbolsPolicy.rows
            var rows: [[Cell]] = mergedRows.dropLast().map { $0.map(Cell.key) }
            rows.append(mergedRows[3].map(Cell.key) + [.delete])
            self.section = .symbols
            self.rows = rows
            self.switchKeyTitle = ""
            self.canvasKeyHeight = 44
            return
        }
        let wide = KeyboardTypingLayoutPolicy.showsSymbolReturn(availableWidth: availableWidth, isPad: isPad)
        let ansi = KeyboardTypingLayoutPolicy.usesANSI(availableWidth: availableWidth, isPad: isPad,
                                                      isLandscape: isLandscape, padLayout: padLayout)
        let extraSymbols = section == .symbols && ansi && arrangement.keyRows(widePad: wide) > 3
        let base = KeyboardTypingLayoutPolicy.rows(for: section.layout, hasAuxiliaryRow: false)
        var rows: [[Cell]] = extraSymbols
            ? [KeyboardTypingLayoutPolicy.auxiliaryRow(for: .symbols, ansiPad: true).map(Cell.key)] : []
        rows += base.dropLast().map { $0.map(Cell.key) }
        rows += base.suffix(1).map { last -> [Cell] in
            [.switchKey(section == .numbers ? .symbols : .numbers)] + last.map(Cell.key) + [.delete] + (wide ? [.returnKey] : [])
        }
        self.section = section
        self.rows = rows
        self.switchKeyTitle = Self.switchTitle(to: section == .numbers ? .symbols : .numbers,
                                               isPad: isPad, ansiPad: ansi, padLayout: padLayout)
        let abcRows = CGFloat(max(3, arrangement.rows.count))
        canvasKeyHeight = (abcRows * 44 + (abcRows - 1) * 6 - CGFloat(rows.count - 1) * 6) / CGFloat(rows.count)
    }

    /// The switch key's title, shared with the actual keyboard.
    static func switchTitle(to target: MainKeyboardSection, isPad: Bool,
                            ansiPad: Bool = false, padLayout: KeyboardPadLayout = .stock) -> String {
        KeyboardTypingLayoutPolicy.symbolSwitchTitle(to: target.layout, isPad: isPad,
                                                      ansiPad: ansiPad, padLayout: padLayout)
    }

    /// The switch key's VoiceOver label.
    static func switchLabel(to target: MainKeyboardSection) -> String {
        target == .symbols ? "Switch to More Symbols" : "Switch to Numbers and Symbols"
    }

    /// The keys drawn, each once, in drawing order.
    var keyIDs: [String] {
        var seen = Set<String>()
        return rows.flatMap { $0 }.compactMap { cell -> String? in
            guard case .key(let text) = cell, let id = KeyboardKeySettings.identifier(forCharacter: text),
                  seen.insert(id).inserted else { return nil }
            return id
        }
    }
}

/// Find a key: every key Main Keyboard edits, each listed once, grouped by
/// the section that has it. Letters are the layout's; a key on both 123 and
/// #+= is listed under 123; symbol keys no canvas draws on this device, such
/// as the wide iPad's extra symbols, are listed under #+=.
enum MainKeyboardKeySearch {
    struct Group: Equatable, Sendable {
        let section: MainKeyboardSection
        let keys: [KeyboardKeySettings.Descriptor]
    }

    /// Every group, before searching.
    static func groups(alphabet: KeyboardAlphabet, arrangement: MainKeyboardArrangement, isPad: Bool, mergedSymbols: Bool = false) -> [Group] {
        let descriptors = KeyboardKeySettings.descriptors
        // English lists A to Z; other layouts list their letters in keyboard order.
        let letters = alphabet == .english ? descriptors.filter { $0.kind == .letter && $0.id.count == "letter.a".count }
            : alphabet.keys.compactMap { KeyboardKeySettings.identifier(forCharacter: $0) }
                .compactMap(KeyboardKeySettings.descriptor(for:)).filter { $0.kind == .letter }
        if mergedSymbols {
            let digits = descriptors.filter { $0.kind == .digit }
            let drawn = MainKeyboardSymbolLayer(page: .symbols, arrangement: arrangement, isPad: isPad, mergedSymbols: true).keyIDs
            let listed = Set(drawn)
            let others = descriptors.filter { $0.kind == .character && !listed.contains($0.id) }
            return [Group(section: .letters, keys: letters + digits),
                    Group(section: .symbols, keys: drawn.compactMap(KeyboardKeySettings.descriptor(for:)) + others)]
        }
        let numbers = MainKeyboardSymbolLayer(page: .numbers, arrangement: arrangement, isPad: isPad).keyIDs
        let listed = Set(numbers)
        let drawn = MainKeyboardSymbolLayer(page: .symbols, arrangement: arrangement, isPad: isPad).keyIDs
            .filter { !listed.contains($0) }
        let shown = listed.union(drawn)
        let others = descriptors.filter { $0.kind != .letter && !shown.contains($0.id) }.map(\.id)
        return [Group(section: .letters, keys: letters),
                Group(section: .numbers, keys: numbers.compactMap(KeyboardKeySettings.descriptor(for:))),
                Group(section: .symbols, keys: (drawn + others).compactMap(KeyboardKeySettings.descriptor(for:)))]
    }

    /// The groups with a key matching the query, as in 1.3: its title or
    /// identifier contains it, ignoring case.
    static func search(_ query: String, alphabet: KeyboardAlphabet, arrangement: MainKeyboardArrangement, isPad: Bool, mergedSymbols: Bool = false) -> [Group] {
        groups(alphabet: alphabet, arrangement: arrangement, isPad: isPad, mergedSymbols: mergedSymbols).compactMap { group in
            let keys = group.keys.filter { matches($0, query: query) }
            return keys.isEmpty ? nil : Group(section: group.section, keys: keys)
        }
    }

    static func matches(_ descriptor: KeyboardKeySettings.Descriptor, query: String) -> Bool {
        query.isEmpty || descriptor.title.localizedCaseInsensitiveContains(query)
            || descriptor.id.localizedCaseInsensitiveContains(query)
    }
}
