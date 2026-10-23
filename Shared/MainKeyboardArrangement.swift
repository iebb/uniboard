import Foundation
import CoreGraphics

/// The main keyboard's letter rows as the app arranged them: the layout's
/// letters with Shift and Delete, and optionally Tab and Caps Lock, in up to
/// three rows with half-width and full-width gaps. Its places are stored like
/// a page's, so the same editing moves keys, gaps and row breaks.
struct MainKeyboardArrangement: Codable, Equatable, Sendable {
    static let shift = "{shift}", delete = "{delete}", tab = "{tab}", caps = "{caps}"
    static let functionKeys = [shift, delete, tab, caps]
    /// The keyboard keeps its height, so letters stay in three rows.
    static let maximumRows = 3

    /// Letters and function keys in the order their places take them.
    var keys: [String]
    /// The rows of places, as `SymbolPageLayout` text.
    var layout: String

    enum Cell: Hashable { case key(String), halfGap, gap }

    /// The layout's own rows, with Shift and Delete around the last one.
    static func standard(for alphabet: KeyboardAlphabet) -> MainKeyboardArrangement {
        let rows = alphabet.rows
        return MainKeyboardArrangement(keys: rows[0] + rows[1] + [shift] + rows[2] + [delete],
            layout: [rows[0].count, rows[1].count, rows[2].count + 2].map { String(repeating: "k", count: $0) }.joined(separator: "/"))
    }

    static func isFunction(_ key: String) -> Bool { functionKeys.contains(key) }

    var places: SymbolPageLayout? { SymbolPageLayout(layout) }

    /// Every letter once, Shift and Delete once, Tab and Caps Lock at most
    /// once, each in a place, in at most three rows.
    func isValid(for alphabet: KeyboardAlphabet) -> Bool {
        guard let places, places.rows.count <= Self.maximumRows, places.keySlots == keys.count,
              places.rows.allSatisfy({ $0.contains(.key) }) else { return false }
        let functions = keys.filter(Self.isFunction)
        return KeyboardAlphabet.isArrangement(keys.filter { !Self.isFunction($0) }, of: alphabet.keys)
            && functions.contains(Self.shift) && functions.contains(Self.delete) && Set(functions).count == functions.count
    }

    /// The rows as the keyboard draws them.
    var rows: [[Cell]] {
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

    /// Each row's letters, always three rows, for typing and wide iPad rows.
    var letterRows: [[String]] {
        let letters = rows.map { $0.compactMap { cell -> String? in
            if case .key(let key) = cell, !Self.isFunction(key) { return key }
            return nil
        } }
        return letters + Array(repeating: [], count: max(0, Self.maximumRows - letters.count))
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
