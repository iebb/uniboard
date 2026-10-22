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
