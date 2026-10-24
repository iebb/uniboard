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

    /// Letters, digits and function keys in the order their places take them.
    var keys: [String]
    /// The rows of places, as `SymbolPageLayout` text.
    var layout: String

    enum Cell: Hashable { case key(String), halfGap, gap }

    /// The default keyboard: the number row, then the layout's own rows with
    /// Shift and Delete around the last one.
    static func standard(for alphabet: KeyboardAlphabet) -> MainKeyboardArrangement {
        letters(for: alphabet).prependingNumberRow
    }

    /// The layout's own rows without the number row.
    static func letters(for alphabet: KeyboardAlphabet) -> MainKeyboardArrangement {
        let rows = alphabet.rows
        return MainKeyboardArrangement(keys: rows[0] + rows[1] + [shift] + rows[2] + [delete],
            layout: [rows[0].count, rows[1].count, rows[2].count + 2].map { String(repeating: "k", count: $0) }.joined(separator: "/"))
    }

    static func isFunction(_ key: String) -> Bool { functionKeys.contains(key) }
    static func isDigit(_ key: String) -> Bool { digits.contains(key) }

    /// The digits this keyboard does not have, in number-row order.
    var missingDigits: [String] { Self.digits.filter { !keys.contains($0) } }

    /// The rows the keyboard is tall: at least three, so the other pages fit.
    var typingRowCount: Int { max(Self.letterRowCount, places?.rows.count ?? 0) }

    /// The typing rows above the footer on every page. A wide iPad draws
    /// its own letter rows, with the number row above them only while this
    /// arrangement has digits.
    func keyRows(widePad: Bool) -> Int {
        guard widePad else { return typingRowCount }
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
        return MainKeyboardArrangement(keys: next, layout: SymbolPageLayout(rows: rows).text)
    }

    /// The number row added as a new first row above these rows. Used on
    /// arrangements without digits, which then have the standard top row.
    var prependingNumberRow: MainKeyboardArrangement {
        MainKeyboardArrangement(keys: Self.digits + keys, layout: String(repeating: "k", count: Self.digits.count) + "/" + layout)
    }

    var places: SymbolPageLayout? { SymbolPageLayout(layout) }

    /// Every letter once, Shift and Delete once, Tab, Caps Lock and each
    /// digit at most once, each in a place, in at most four rows.
    func isValid(for alphabet: KeyboardAlphabet) -> Bool {
        guard let places, places.rows.count <= Self.maximumRows, places.keySlots == keys.count,
              places.rows.allSatisfy({ $0.contains(.key) }) else { return false }
        let functions = keys.filter(Self.isFunction), numbers = keys.filter(Self.isDigit)
        return KeyboardAlphabet.isArrangement(keys.filter { !Self.isFunction($0) && !Self.isDigit($0) }, of: alphabet.keys)
            && functions.contains(Self.shift) && functions.contains(Self.delete) && Set(functions).count == functions.count
            && Set(numbers).count == numbers.count
    }

    /// What versions before the number row joined the arrangement could
    /// store: no digits and at most three rows.
    var isLetterOnly: Bool { missingDigits.count == Self.digits.count && (places?.rows.count ?? 0) <= Self.letterRowCount }

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
