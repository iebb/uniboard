import Foundation
import CoreGraphics

/// A page's rows: key slots that the page's keys fill in order, half-width
/// and full-width gaps, and row breaks. It is stored as compact text, such as
/// "kkkkk/hkkkk", so it never names a key: the Favorites page, whose keys sync
/// separately, keeps its rows. Keys beyond the slots continue in automatic rows.
struct SymbolPageLayout: Equatable {
    enum Item: Character, Equatable {
        case key = "k", halfGap = "h", gap = "g"
        /// Width in key widths.
        var units: Double { self == .halfGap ? 0.5 : 1 }
    }
    /// One rendered cell: a key by its index in the page, or a gap.
    enum Cell: Hashable {
        case key(Int), halfGap, gap
    }
    struct Position: Hashable {
        var row: Int
        var index: Int
    }

    static let automaticColumns = 10
    static let maximumRowUnits = 16.0
    static let maximumRows = 64
    static let maximumLength = 2048

    private(set) var rows: [[Item]]

    init(rows: [[Item]]) { self.rows = rows }

    /// nil for text that is not a layout this version understands.
    init?(_ text: String) {
        guard !text.isEmpty, text.utf8.count <= Self.maximumLength else { return nil }
        var rows: [[Item]] = []
        for part in text.split(separator: "/", omittingEmptySubsequences: false) {
            let items = part.compactMap(Item.init(rawValue:))
            guard items.count == part.count, !items.isEmpty, Self.units(items) <= Self.maximumRowUnits else { return nil }
            rows.append(items)
        }
        guard rows.count <= Self.maximumRows else { return nil }
        self.rows = rows
    }

    var text: String { rows.map { String($0.map(\.rawValue)) }.joined(separator: "/") }
    var keySlots: Int { rows.reduce(0) { $0 + $1.filter { $0 == .key }.count } }

    /// Rows of ten, as pages are laid out without a layout of their own.
    static func automatic(keyCount: Int) -> SymbolPageLayout {
        let count = max(0, keyCount)
        let full = count / automaticColumns, rest = count % automaticColumns
        return SymbolPageLayout(rows: Array(repeating: Array(repeating: .key, count: automaticColumns), count: full)
            + (rest > 0 ? [Array(repeating: .key, count: rest)] : []))
    }

    /// The stored layout when it is valid, otherwise rows of ten.
    static func resolved(_ text: String?, keyCount: Int) -> SymbolPageLayout {
        text.flatMap(SymbolPageLayout.init) ?? automatic(keyCount: keyCount)
    }

    static func units(_ items: [Item]) -> Double { items.reduce(0) { $0 + $1.units } }

    /// The page as the keyboard draws it. Slots without a key end their row,
    /// rows left without a key are dropped, and keys beyond the slots continue
    /// in rows of ten.
    func cells(keyCount: Int) -> [[Cell]] {
        var result: [[Cell]] = []
        var next = 0
        for row in rows where next < keyCount {
            var cells: [Cell] = []
            var hasKey = false
            for item in row {
                if item == .key {
                    if next == keyCount { break }
                    cells.append(.key(next)); next += 1; hasKey = true
                } else {
                    cells.append(item == .halfGap ? .halfGap : .gap)
                }
            }
            // Gaps after the page's last key would only pad an unfinished row.
            if next == keyCount { while let last = cells.last, last == .halfGap || last == .gap { cells.removeLast() } }
            if hasKey { result.append(cells) }
        }
        while next < keyCount {
            let end = min(keyCount, next + Self.automaticColumns)
            result.append((next..<end).map(Cell.key))
            next = end
        }
        return result
    }

    /// Every slot filled exactly: unused slots are removed and missing ones
    /// added in rows of ten, so the editor shows what the keyboard does.
    func fitted(keyCount: Int) -> SymbolPageLayout {
        SymbolPageLayout(rows: cells(keyCount: keyCount).map { row in
            row.map { cell in
                switch cell { case .key: return .key; case .halfGap: return .halfGap; case .gap: return .gap }
            }
        })
    }

    /// One key width for the whole page: ten keys fill a row, and a longer
    /// row narrows every key so it still fits. Two half gaps and their spacing
    /// make one full gap, which matches a key and its spacing.
    static func keyWidth(for cells: [[Cell]], available: CGFloat, spacing: CGFloat) -> CGFloat {
        guard available.isFinite, available > 0, spacing.isFinite, spacing >= 0 else { return 0 }
        var width = (available - spacing * CGFloat(automaticColumns - 1)) / CGFloat(automaticColumns)
        for row in cells where !row.isEmpty {
            let halves = CGFloat(row.filter { $0 == .halfGap }.count)
            let wholes = CGFloat(row.count) - halves
            let fit = (available - spacing * (CGFloat(row.count - 1) - halves / 2)) / (wholes + halves / 2)
            width = min(width, fit)
        }
        return max(0, width)
    }

    static func gapWidth(_ cell: Cell, keyWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        cell == .halfGap ? max(0, (keyWidth - spacing) / 2) : keyWidth
    }

    // MARK: Editing

    func item(at position: Position) -> Item? {
        rows.indices.contains(position.row) && rows[position.row].indices.contains(position.index)
            ? rows[position.row][position.index] : nil
    }

    /// The index of the page key in a key slot.
    func keyIndex(at position: Position) -> Int? {
        guard item(at: position) == .key else { return nil }
        let before = rows.prefix(position.row).reduce(0) { $0 + $1.filter { $0 == .key }.count }
        return before + rows[position.row].prefix(position.index).filter { $0 == .key }.count
    }

    func canInsert(_ item: Item, inRow row: Int) -> Bool {
        rows.indices.contains(row) && Self.units(rows[row]) + item.units <= Self.maximumRowUnits
    }

    /// A gap before `position`, or at the end of its row when the index is the row's count.
    mutating func insertGap(_ item: Item, at position: Position) -> Bool {
        guard item != .key, canInsert(item, inRow: position.row),
              (0...rows[position.row].count).contains(position.index) else { return false }
        rows[position.row].insert(item, at: position.index)
        return true
    }

    /// Removes a gap. Key slots go with their key.
    mutating func removeGap(at position: Position) -> Bool {
        guard let item = item(at: position), item != .key else { return false }
        rows[position.row].remove(at: position.index)
        if rows[position.row].isEmpty { rows.remove(at: position.row) }
        return true
    }

    /// Starts a new row at `position`.
    mutating func breakRow(at position: Position) -> Bool {
        guard item(at: position) != nil, position.index > 0, rows.count < Self.maximumRows else { return false }
        let tail = Array(rows[position.row][position.index...])
        rows[position.row].removeSubrange(position.index...)
        rows.insert(tail, at: position.row + 1)
        return true
    }

    /// Joins a row onto the end of the row above it.
    mutating func joinRow(_ row: Int) -> Bool {
        guard row > 0, rows.indices.contains(row), Self.units(rows[row - 1] + rows[row]) <= Self.maximumRowUnits else { return false }
        rows[row - 1] += rows.remove(at: row)
        return true
    }

    /// How the page's keys must be reordered after a move: the moved key's
    /// index before and after.
    struct KeyMove: Equatable {
        let from: Int
        let to: Int
    }

    /// Moves an item to before `destination`, or to the end of its row when
    /// the index is the row's count. A key's slot moves with its key. False
    /// when the move is not possible; `keyMove` is set when keys reorder.
    mutating func move(from source: Position, to destination: Position, keyMove: inout KeyMove?) -> Bool {
        keyMove = nil
        guard let item = item(at: source), rows.indices.contains(destination.row),
              (0...rows[destination.row].count).contains(destination.index) else { return false }
        let sameRow = source.row == destination.row
        if !sameRow && Self.units(rows[destination.row]) + item.units > Self.maximumRowUnits { return false }
        let keyFrom = keyIndex(at: source)
        var next = self
        next.rows[source.row].remove(at: source.index)
        var target = destination
        if sameRow && destination.index > source.index { target.index -= 1 }
        next.rows[target.row].insert(item, at: target.index)
        if next.rows[source.row].isEmpty {
            next.rows.remove(at: source.row)
            if target.row > source.row { target.row -= 1 }
        }
        // Slots alike may not change the text, but the key still moves.
        if let keyFrom, let keyTo = next.keyIndex(at: target), keyFrom != keyTo { keyMove = KeyMove(from: keyFrom, to: keyTo) }
        self = next
        return true
    }

    /// A new key's slot, at the end of the last row while it has room.
    mutating func appendKey() {
        if let last = rows.indices.last, Self.units(rows[last]) + 1 <= Double(Self.automaticColumns) {
            rows[last].append(.key)
        } else if rows.count < Self.maximumRows {
            rows.append([.key])
        }
    }

    /// A new key slot at the start of `row`, returning the index the key takes.
    mutating func insertKeySlot(atStartOf row: Int) -> Int? {
        guard rows.indices.contains(row), Self.units(rows[row]) + 1 <= Self.maximumRowUnits else { return nil }
        rows[row].insert(.key, at: 0)
        return rows.prefix(row).reduce(0) { $0 + $1.filter { $0 == .key }.count }
    }

    /// Drops the slot of a removed key, keeping the rest of the arrangement.
    mutating func removeKeySlot(_ keyIndex: Int) {
        var seen = 0
        for row in rows.indices {
            for index in rows[row].indices where rows[row][index] == .key {
                if seen == keyIndex {
                    rows[row].remove(at: index)
                    if !rows[row].contains(.key) { rows.remove(at: row) }
                    return
                }
                seen += 1
            }
        }
    }
}

// MARK: - Versioned explicit rows (not legacy slot templates)

/// Physical alignment. `spaced` keeps widths and distributes free space
/// between cells; a singleton is centered. Geometry belongs to the renderer.
enum KeyboardRowAlignment: String, Codable, CaseIterable, Sendable {
    case left, right, center, spaced
}

/// Exactly one semantic key payload or one typed gap. There are no key indices
/// in explicit data: moving a cell moves its complete payload.
enum KeyboardRowCell<Key: Codable & Equatable>: Codable, Equatable {
    case key(Key), halfGap, gap

    private enum CodingKeys: String, CodingKey { case key, gap }
    init(from decoder: Decoder) throws {
        try ExplicitRowCoding.allow(decoder, ["key", "gap"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.key) != c.contains(.gap) else { throw ExplicitRowCoding.invalid }
        if c.contains(.key) {
            if Key.self == SymbolBoardKey.self {
                let payload = try c.superDecoder(forKey: .key)
                try ExplicitRowCoding.allow(payload, ["id", "text", "variants", "up", "down"])
                self = .key(try Key(from: payload))
            } else { self = .key(try c.decode(Key.self, forKey: .key)) }
        } else {
            switch try c.decode(String.self, forKey: .gap) {
            case "half": self = .halfGap
            case "full": self = .gap
            default: throw ExplicitRowCoding.invalid
            }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let key): try c.encode(key, forKey: .key)
        case .halfGap: try c.encode("half", forKey: .gap)
        case .gap: try c.encode("full", forKey: .gap)
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.key(a), .key(b)):
            if let a = a as? String, let b = b as? String { return a.utf16.elementsEqual(b.utf16) }
            return a == b
        case (.halfGap, .halfGap), (.gap, .gap): return true
        default: return false
        }
    }
    var key: Key? { if case .key(let key) = self { return key }; return nil }
    var units: Double {
        switch self {
        case .halfGap: return 0.5
        case .gap: return 1
        case .key(let key):
            return (key as? String).map(MainKeyboardArrangement.isFunction) == true ? 1.5 : 1
        }
    }
}
extension KeyboardRowCell: Sendable where Key: Sendable {}

struct KeyboardRow<Key: Codable & Equatable>: Codable, Equatable {
    var alignment: KeyboardRowAlignment
    var cells: [KeyboardRowCell<Key>]
    init(alignment: KeyboardRowAlignment = .left, cells: [KeyboardRowCell<Key>]) {
        self.alignment = alignment; self.cells = cells
    }
    private enum CodingKeys: String, CodingKey { case alignment, cells }
    init(from decoder: Decoder) throws {
        try ExplicitRowCoding.allow(decoder, ["alignment", "cells"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alignment = try c.decode(KeyboardRowAlignment.self, forKey: .alignment)
        cells = try c.decode([KeyboardRowCell<Key>].self, forKey: .cells)
        if units > Self.maximumRowUnits {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: ExplicitRowCoding.widthProblem))
        }
        guard Self.valid([self]) else { throw ExplicitRowCoding.invalid }
    }
    /// Explicit edits/imports use the narrow-device storage limit. The old
    /// SymbolPageLayout parser deliberately retains its 16-unit limit.
    static var maximumRowUnits: Double { 12 }
    var units: Double { cells.reduce(0) { $0 + $1.units } }
    /// Limits are storage limits, not a responsive wrapping/overflow policy.
    static func valid(_ rows: [Self], maximumRows: Int = SymbolPageLayout.maximumRows) -> Bool {
        rows.count <= maximumRows && rows.allSatisfy {
            !$0.cells.isEmpty && $0.cells.contains(where: { $0.key != nil })
                && $0.units <= Self.maximumRowUnits
        }
    }
    static func legacy(keys: [Key], layout: String?, alignment: KeyboardRowAlignment) -> [Self] {
        SymbolPageLayout.resolved(layout, keyCount: keys.count).cells(keyCount: keys.count).map { row in
            Self(alignment: alignment, cells: row.map {
                switch $0 { case .key(let i): return .key(keys[i]); case .halfGap: return .halfGap; case .gap: return .gap }
            })
        }
    }
    static func layout(_ rows: [Self]) -> String {
        rows.map { row in String(row.cells.map { cell -> Character in
            switch cell { case .key: return "k"; case .halfGap: return "h"; case .gap: return "g" }
        }) }.joined(separator: "/")
    }
    /// Legacy list mutation adapter. Surviving row alignment stays attached
    /// to that row; new keys overflow in automatic rows, never a second order.
    static func replacingKeys(_ rows: [Self], with keys: [Key], alignment: KeyboardRowAlignment) -> [Self] {
        var next = 0
        var result: [Self] = []
        let removing = keys.count < rows.reduce(0) { $0 + $1.cells.compactMap(\.key).count }
        func sameIdentity(_ a: Key, _ b: Key) -> Bool {
            if let a = a as? SymbolBoardKey, let b = b as? SymbolBoardKey { return a.id == b.id }
            return KeyboardRowCell<Key>.key(a) == .key(b)
        }
        for row in rows {
            let cells = row.cells.compactMap { cell -> KeyboardRowCell<Key>? in
                guard case .key(let original) = cell else { return cell }
                if removing, !keys.contains(where: { sameIdentity(original, $0) }) { return nil }
                guard next < keys.count else { return nil }
                defer { next += 1 }; return .key(keys[next])
            }
            if cells.contains(where: { $0.key != nil }) { result.append(Self(alignment: row.alignment, cells: cells)) }
        }
        for key in keys.dropFirst(next) {
            let cell = KeyboardRowCell<Key>.key(key)
            if let last = result.indices.last, result[last].units + cell.units <= Double(SymbolPageLayout.automaticColumns) {
                result[last].cells.append(cell)
            } else { result.append(Self(alignment: result.last?.alignment ?? alignment, cells: [cell])) }
        }
        return result
    }
    /// An exact slot projection, unlike legacy fitting, retains trailing gaps.
    /// Callers supply one payload for every key slot.
    static func slots(keys: [Key], layout: SymbolPageLayout, alignment: KeyboardRowAlignment) -> [Self] {
        var next = 0
        return layout.rows.map { row in
            Self(alignment: alignment, cells: row.map { item in
                switch item {
                case .key: defer { next += 1 }; return .key(keys[next])
                case .halfGap: return .halfGap
                case .gap: return .gap
                }
            })
        }
    }
    static func replacingLayout(_ rows: [Self], with layout: String?, alignment: KeyboardRowAlignment) -> [Self] {
        let keys = rows.flatMap { $0.cells.compactMap(\.key) }
        let projected: [Self]
        if let places = layout.flatMap(SymbolPageLayout.init), places.keySlots == keys.count {
            projected = slots(keys: keys, layout: places, alignment: alignment)
        } else { projected = legacy(keys: keys, layout: layout, alignment: alignment) }
        return projected.enumerated().map { index, row in
            var row = row
            if rows.indices.contains(index) { row.alignment = rows[index].alignment }
            return row
        }
    }
}
extension KeyboardRow: Sendable where Key: Sendable {}

/// Reject ambiguous or future cell/model fields rather than silently dropping
/// semantics. Envelope decoders separately gate the version carrying rows.
enum ExplicitRowCoding {
    enum Invalid: Error { case data }
    static let invalid = Invalid.data
    static let widthProblem = "Explicit row exceeds 12 standard-key widths."
    struct RowWidthProblem: Error { let message: String }
    static func widthMessage(label: String, row: Int, field: String) -> String {
        "\(label), row \(row): This row exceeds the limit of 12 standard-key widths. Move keys or remove gaps before applying. (\(field))"
    }
    private struct FieldPresence: Decodable {
        init(from decoder: Decoder) {}
    }
    static func allow(_ decoder: Decoder, _ allowed: Set<String>) throws {
        let fields = try [String: FieldPresence](from: decoder)
        guard Set(fields.keys).isSubset(of: allowed) else { throw invalid }
    }
}
