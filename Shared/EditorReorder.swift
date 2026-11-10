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

// MARK: - Explicit row editing and shared physical geometry

/// New edits never reflow existing cells. Row identity is retained by editing
/// nested rows, not by assigning alignment to a flattened row index afterward.
enum ExplicitRowEditing {
    static let limit = 12.0
    enum Action {
        case halfGap(SymbolPageLayout.Position), gap(SymbolPageLayout.Position)
        case split(SymbolPageLayout.Position), join(Int), remove(SymbolPageLayout.Position)
    }
    static func units<K>(_ row: KeyboardRow<K>, keyUnits: (K) -> Double) -> Double {
        row.cells.reduce(0) { $0 + ($1.key.map(keyUnits) ?? ($1 == .halfGap ? 0.5 : 1)) }
    }
    static func fits<K>(_ rows: [KeyboardRow<K>], keyUnits: (K) -> Double) -> Bool {
        rows.allSatisfy { units($0, keyUnits: keyUnits) <= limit }
    }
    /// Existing overlong rows may only keep or reduce their width during repair.
    static func allowed<K>(_ next: [KeyboardRow<K>], previous: [KeyboardRow<K>], keyUnits: (K) -> Double) -> Bool {
        let oldOver = previous.map { units($0, keyUnits: keyUnits) }.filter { $0 > limit }.sorted(by: >)
        let newOver = next.map { units($0, keyUnits: keyUnits) }.filter { $0 > limit }.sorted(by: >)
        return newOver.count <= oldOver.count && zip(newOver, oldOver).allSatisfy { $0 <= $1 }
    }
    static func move<K>(_ rows: [KeyboardRow<K>], from source: SymbolPageLayout.Position,
                        to destination: SymbolPageLayout.Position, keyUnits: (K) -> Double) -> [KeyboardRow<K>]? {
        guard EditorReorder.isItem(source, in: rows.map { $0.cells.count }),
              EditorReorder.isPlace(destination, in: rows.map { $0.cells.count }) else { return nil }
        if source.row != destination.row {
            let cell = rows[source.row].cells[source.index]
            let extra = cell.key.map(keyUnits) ?? (cell == .halfGap ? 0.5 : 1)
            guard units(rows[destination.row], keyUnits: keyUnits) + extra <= limit else { return nil }
        }
        var next = rows
        let cell = next[source.row].cells.remove(at: source.index)
        let target = EditorReorder.landing(from: source, to: destination, rowCounts: rows.map { $0.cells.count }, removesEmptyRows: false)
        next[target.row].cells.insert(cell, at: target.index)
        if next[source.row].cells.isEmpty { next.remove(at: source.row) }
        guard next.allSatisfy({ $0.cells.contains { $0.key != nil } }) else { return nil }
        return next
    }
    static func applying<K>(_ action: Action, to rows: [KeyboardRow<K>], maximumRows: Int,
                            keyUnits: (K) -> Double) -> [KeyboardRow<K>]? {
        var next = rows
        switch action {
        case .halfGap(let p), .gap(let p):
            guard EditorReorder.isItem(p, in: rows.map { $0.cells.count }) else { return nil }
            let half: Bool
            if case .halfGap = action { half = true } else { half = false }
            guard units(rows[p.row], keyUnits: keyUnits) + (half ? 0.5 : 1) <= limit else { return nil }
            next[p.row].cells.insert(half ? .halfGap : .gap, at: p.index)
        case .split(let p):
            guard EditorReorder.isItem(p, in: rows.map { $0.cells.count }), p.index > 0, rows.count < maximumRows else { return nil }
            let tail = Array(next[p.row].cells[p.index...])
            next[p.row].cells.removeSubrange(p.index...)
            next.insert(KeyboardRow(alignment: rows[p.row].alignment, cells: tail), at: p.row + 1)
        case .join(let row):
            guard row > 0, rows.indices.contains(row), units(rows[row - 1], keyUnits: keyUnits) + units(rows[row], keyUnits: keyUnits) <= limit else { return nil }
            let lower = next.remove(at: row)
            next[row - 1].cells += lower.cells
        case .remove(let p):
            guard EditorReorder.isItem(p, in: rows.map { $0.cells.count }) else { return nil }
            next[p.row].cells.remove(at: p.index)
            if !next[p.row].cells.contains(where: { $0.key != nil }) { next.remove(at: p.row) }
        }
        guard next.allSatisfy({ $0.cells.contains { $0.key != nil } }), allowed(next, previous: rows, keyUnits: keyUnits) else { return nil }
        return next
    }
    static func mainUnits(_ key: String) -> Double { MainKeyboardArrangement.isFunction(key) ? 1.5 : 1 }
    static func page(_ board: SymbolBoard, rows: [SymbolBoard.Row]) -> SymbolBoard {
        // Until repaired, use the old representation so its keyboard drawing is
        // unchanged. No overlong new-format data is ever emitted.
        if board.id == SymbolPageRules.favoritesID || board.isLegacy && !fits(rows, keyUnits: { _ in 1 }) {
            return SymbolBoard(id: board.id, name: board.name, keys: rows.flatMap { $0.cells.compactMap(\.key) }, layout: SymbolBoard.Row.layout(rows))
        }
        return SymbolBoard(id: board.id, name: board.name, rows: rows)
    }
    static func main(_ current: MainKeyboardArrangement, rows: [MainKeyboardArrangement.Row]) -> MainKeyboardArrangement {
        if current.isLegacy && !fits(rows, keyUnits: mainUnits) {
            return MainKeyboardArrangement(keys: rows.flatMap { $0.cells.compactMap(\.key) }, layout: MainKeyboardArrangement.Row.layout(rows))
        }
        return MainKeyboardArrangement(rows: rows)
    }
}

extension EditorReorder {
    static func explicitPage(_ board: SymbolBoard, from source: Position, to destination: Position) -> Move<SymbolBoard>? {
        let rows = board.resolvedRows
        guard let next = ExplicitRowEditing.move(rows, from: source, to: destination, keyUnits: { _ in 1 }) else { return nil }
        let value = ExplicitRowEditing.page(board, rows: next)
        if value.isLegacy {
            let layout = SymbolPageLayout.resolved(value.layout, keyCount: value.keys.count)
            guard isStable(layout, keyCount: value.keys.count) else { return nil }
        }
        return Move(value: value, source: source, destination: destination,
                    landing: landing(from: source, to: destination, rowCounts: rows.map { $0.cells.count }, removesEmptyRows: true),
                    changesValue: next != rows)
    }
    static func explicitMainKeyboard(_ arrangement: MainKeyboardArrangement, from source: Position, to destination: Position,
                                     alphabet: KeyboardAlphabet) -> Move<MainKeyboardArrangement>? {
        let rows = arrangement.resolvedRows
        guard let next = ExplicitRowEditing.move(rows, from: source, to: destination, keyUnits: ExplicitRowEditing.mainUnits) else { return nil }
        let value = ExplicitRowEditing.main(arrangement, rows: next)
        guard value.isValid(for: alphabet) else { return nil }
        if value.isLegacy {
            guard let places = value.places, isStable(places, keyCount: value.keys.count) else { return nil }
        }
        return Move(value: value, source: source, destination: destination,
                    landing: landing(from: source, to: destination, rowCounts: rows.map { $0.cells.count }, removesEmptyRows: true), changesValue: next != rows)
    }
}

/// Shared editor/keyboard row placement. Physical x coordinates deliberately
/// ignore layout direction. Widths stay unchanged; only origins are pixel rounded.
enum ExplicitRowGeometry {
    static func origins(widths: [CGFloat], available: CGFloat, spacing: CGFloat,
                        alignment: KeyboardRowAlignment, scale: CGFloat) -> [CGFloat] {
        guard !widths.isEmpty else { return [] }
        let spare = max(0, available - widths.reduce(0, +) - spacing * CGFloat(widths.count - 1))
        var x: CGFloat
        switch alignment {
        case .left: x = 0
        case .right: x = spare
        case .center: x = spare / 2
        case .spaced: x = widths.count == 1 ? spare / 2 : 0
        }
        let between = spacing + (alignment == .spaced && widths.count > 1 ? spare / CGFloat(widths.count - 1) : 0)
        let pixelScale = scale > 0 && scale.isFinite ? scale : 1
        return widths.map { width in
            defer { x += width + between }
            return (x * pixelScale).rounded() / pixelScale
        }
    }
}
