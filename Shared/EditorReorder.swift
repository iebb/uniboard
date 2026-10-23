import Foundation

/// The rules every keyboard editor's drag follows, kept apart from SwiftUI so
/// they can be tested. Hovering never changes anything; a drop is checked
/// against the arrangement the drag lifted from and computed once; and a
/// cancelled, refused or stale drop leaves the saved arrangement as it was.
/// Items always land before the place they are dropped on, or at the end of
/// a row when the index is the row's count. Nothing is ever swapped.
enum EditorReorder {
    typealias Position = SymbolPageLayout.Position

    /// A computed move: the value to save, the places it was dropped from and
    /// on, where the item lands, and whether saving would change anything (a
    /// drop on itself is not a change).
    struct Move<Value: Equatable>: Equatable {
        let value: Value
        let source: Position
        let destination: Position
        let landing: Position
        let changesValue: Bool
    }

    /// A page's move: its new rows and how its keys reorder.
    struct PageMove: Equatable {
        let layout: SymbolPageLayout
        let keyMove: SymbolPageLayout.KeyMove?
    }

    /// Where the item at `source` ends up when it is put before `destination`.
    /// Within a row, removing it first shifts the places after it back by one;
    /// when `removesEmptyRows` and it leaves a row of its own, later rows move up.
    static func landing(from source: Position, to destination: Position, rowCounts: [Int], removesEmptyRows: Bool) -> Position {
        var result = destination
        if source.row == destination.row && destination.index > source.index { result.index -= 1 }
        if removesEmptyRows, source.row != destination.row, destination.row > source.row,
           rowCounts.indices.contains(source.row), rowCounts[source.row] == 1 { result.row -= 1 }
        return result
    }

    /// Moves one element of `rows` to before `destination`. The result holds
    /// exactly the same elements; nil when either place does not exist.
    static func move<Element>(_ rows: [[Element]], from source: Position, to destination: Position, removesEmptyRows: Bool) -> [[Element]]? {
        guard isItem(source, in: rows.map(\.count)), isPlace(destination, in: rows.map(\.count)) else { return nil }
        var next = rows
        let element = next[source.row].remove(at: source.index)
        // The row is not removed yet, so only the in-row shift applies here.
        let target = landing(from: source, to: destination, rowCounts: rows.map(\.count), removesEmptyRows: false)
        next[target.row].insert(element, at: target.index)
        if removesEmptyRows && next[source.row].isEmpty { next.remove(at: source.row) }
        return next
    }

    static func isItem(_ position: Position, in rowCounts: [Int]) -> Bool {
        rowCounts.indices.contains(position.row) && position.index >= 0 && position.index < rowCounts[position.row]
    }

    static func isPlace(_ position: Position, in rowCounts: [Int]) -> Bool {
        rowCounts.indices.contains(position.row) && position.index >= 0 && position.index <= rowCounts[position.row]
    }

    // MARK: Editors

    /// A page's key or gap, moved with its row rules (row widths, emptied rows).
    /// Refused when the keyboard would not draw the result as saved: a row
    /// left with only gaps, or gaps after the last key, would silently vanish.
    static func page(_ layout: SymbolPageLayout, from source: Position, to destination: Position) -> Move<PageMove>? {
        let counts = layout.rows.map(\.count)
        guard isItem(source, in: counts), isPlace(destination, in: counts) else { return nil }
        var next = layout
        var keyMove: SymbolPageLayout.KeyMove?
        guard next.move(from: source, to: destination, keyMove: &keyMove), isStable(next, keyCount: next.keySlots) else { return nil }
        return Move(value: PageMove(layout: next, keyMove: keyMove), source: source, destination: destination,
                    landing: landing(from: source, to: destination, rowCounts: counts, removesEmptyRows: true),
                    changesValue: next != layout || keyMove != nil)
    }

    /// Whether the keyboard draws `layout` exactly as stored, with nothing
    /// dropped, so a move never saves places that would be lost.
    static func isStable(_ layout: SymbolPageLayout, keyCount: Int) -> Bool {
        layout.fitted(keyCount: keyCount) == layout
    }

    /// A selection kept only while it is on an item of `layout`, so a move or
    /// another change never leaves it pointing past a row's end.
    static func selection(_ position: Position?, in layout: SymbolPageLayout) -> Position? {
        position.flatMap { layout.item(at: $0) == nil ? nil : $0 }
    }

    /// Only the main keyboard's keys drag; its gaps keep their arrow buttons.
    static func canDragMainKeyboardItem(at position: Position, in arrangement: MainKeyboardArrangement) -> Bool {
        arrangement.places?.item(at: position) == .key
    }

    /// The main keyboard rearranged, when the result is still a whole, valid
    /// keyboard: every letter once, Shift and Delete, at most three rows.
    static func mainKeyboard(_ arrangement: MainKeyboardArrangement, from source: Position, to destination: Position,
                             alphabet: KeyboardAlphabet) -> Move<MainKeyboardArrangement>? {
        guard let places = arrangement.places, places.keySlots == arrangement.keys.count else { return nil }
        let counts = places.rows.map(\.count)
        guard isItem(source, in: counts), isPlace(destination, in: counts) else { return nil }
        var next = places
        var keyMove: SymbolPageLayout.KeyMove?
        guard next.move(from: source, to: destination, keyMove: &keyMove), isStable(next, keyCount: arrangement.keys.count) else { return nil }
        var keys = arrangement.keys
        if let keyMove {
            guard keys.indices.contains(keyMove.from), keys.indices.contains(keyMove.to) else { return nil }
            keys.insert(keys.remove(at: keyMove.from), at: keyMove.to)
        }
        let result = MainKeyboardArrangement(keys: keys, layout: next.text)
        guard result.isValid(for: alphabet) else { return nil }
        return Move(value: result, source: source, destination: destination,
                    landing: landing(from: source, to: destination, rowCounts: counts, removesEmptyRows: true),
                    changesValue: result != arrangement)
    }

    /// A key's layer choices, one row per layer. Locked rows (the key's own
    /// output) neither give nor take a choice; another row refuses a choice it
    /// already has or one past `maximum`. Rows stay even when emptied.
    static func choices(_ rows: [[String]], from source: Position, to destination: Position,
                        locked: Set<Int> = [], maximum: Int) -> Move<[[String]]>? {
        guard !locked.contains(source.row), !locked.contains(destination.row),
              let next = move(rows, from: source, to: destination, removesEmptyRows: false) else { return nil }
        if source.row != destination.row {
            let value = rows[source.row][source.index]
            guard !rows[destination.row].contains(value), rows[destination.row].count < maximum else { return nil }
        }
        return Move(value: next, source: source, destination: destination,
                    landing: landing(from: source, to: destination, rowCounts: rows.map(\.count), removesEmptyRows: false),
                    changesValue: next != rows)
    }
}

/// One drag, from lift to drop or cancel. It holds only where the drag came
/// from and where it would land; never the arrangement itself, so nothing it
/// does can change saved data. A drop is accepted once, for the drag's own
/// token, and only while the arrangement is the one it lifted from.
struct EditorDragState: Equatable {
    typealias Position = SymbolPageLayout.Position
    struct Lift: Equatable {
        let token: UUID
        let source: Position
        let fingerprint: String
    }

    private(set) var lift: Lift?
    /// The place the insertion line marks; only ever a valid destination.
    private(set) var target: Position?

    var source: Position? { lift?.source }
    var isActive: Bool { lift != nil }

    /// Starts a drag. Refused while another is under way.
    @discardableResult
    mutating func begin(at source: Position, fingerprint: String, token: UUID = UUID()) -> UUID? {
        guard lift == nil else { return nil }
        lift = Lift(token: token, source: source, fingerprint: fingerprint)
        target = nil
        return token
    }

    /// The lifted place, for this drag's own token while nothing has changed.
    func source(for token: UUID?, fingerprint: String) -> Position? {
        guard let lift, let token, lift.token == token, lift.fingerprint == fingerprint else { return nil }
        return lift.source
    }

    /// Marks `destination` when a drop there is valid, otherwise clears its
    /// mark. Returns whether a drop there would be accepted.
    @discardableResult
    mutating func hover(_ destination: Position, token: UUID?, fingerprint: String, isValid: (Position) -> Bool) -> Bool {
        guard let source = source(for: token, fingerprint: fingerprint), isValid(source) else {
            if target == destination { target = nil }
            return false
        }
        target = destination
        return true
    }

    /// The drag left `destination`.
    mutating func leave(_ destination: Position) {
        if target == destination { target = nil }
    }

    /// Cancelled, dropped outside, dismissed or backgrounded: nothing to undo.
    mutating func cancel() {
        lift = nil
        target = nil
    }

    /// Ends the drag and returns its source when the drop is this drag's and
    /// still current. A second drop of the same drag gets nil.
    mutating func finish(token: UUID?, fingerprint: String) -> Position? {
        defer { cancel() }
        return source(for: token, fingerprint: fingerprint)
    }

    /// Ends the drag with a drop on `destination`, computing the move once.
    mutating func drop<Value: Equatable>(on destination: Position, token: UUID?, fingerprint: String,
                              propose: (Position, Position) -> EditorReorder.Move<Value>?) -> EditorReorder.Move<Value>? {
        guard let source = finish(token: token, fingerprint: fingerprint) else { return nil }
        return propose(source, destination)
    }
}

/// Stable identities for an editor's tiles, so a moved key or gap animates as
/// itself rather than morphing into its neighbour. They follow successful
/// moves and are renewed only when the rows change shape some other way.
struct EditorTileIdentities: Equatable {
    typealias Position = SymbolPageLayout.Position
    private(set) var rows: [[Int]] = []
    private var next = 0

    init(rowCounts: [Int] = []) { fit(rowCounts: rowCounts) }

    mutating func fit(rowCounts: [Int]) {
        guard rows.map(\.count) != rowCounts else { return }
        var fresh: [[Int]] = []
        for count in rowCounts {
            var ids: [Int] = []
            for _ in 0..<max(0, count) { ids.append(next); next += 1 }
            fresh.append(ids)
        }
        rows = fresh
    }

    func id(at position: Position) -> Int? {
        EditorReorder.isItem(position, in: rows.map(\.count)) ? rows[position.row][position.index] : nil
    }

    func position(of id: Int) -> Position? {
        for (row, ids) in rows.enumerated() {
            if let index = ids.firstIndex(of: id) { return Position(row: row, index: index) }
        }
        return nil
    }

    @discardableResult
    mutating func move(from source: Position, to destination: Position, removesEmptyRows: Bool) -> Bool {
        guard let moved = EditorReorder.move(rows, from: source, to: destination, removesEmptyRows: removesEmptyRows) else { return false }
        rows = moved
        return true
    }
}
