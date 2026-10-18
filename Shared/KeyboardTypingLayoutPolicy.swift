import Foundation

enum KeyboardPadLayout: String, CaseIterable {
    case stock, ansi, ansiNumbers
    var title: String {
        switch self {
        case .stock: return "iPad · 3 rows"
        case .ansi: return "Compact ANSI · 3 rows"
        case .ansiNumbers: return "ANSI + numbers · 4 rows"
        }
    }
}

enum KeyboardPadSymbolMapping: String, CaseIterable {
    case standard, iPad, none
    var title: String {
        switch self {
        case .standard: return "Standard symbol page"
        case .iPad: return "iPad symbols"
        case .none: return "Off"
        }
    }
}

/// The English panel uses additional rows, rather than stretching its keycaps.
struct KeyboardTypingLayoutPlan: Equatable {
    let keyHeight: CGFloat
    let rowSpacing: CGFloat
    /// Matches the ten-key number row, independently of vertical row spacing.
    let keySpacing: CGFloat
    /// Bounded by three main rows, one auxiliary row and four favorite rows.
    let rowCapacity: Int
    /// Compatibility name: an auxiliary row, complementary to the current page.
    let numberRowCount: Int
    let favoriteRowsCount: Int
    let favoritesPerRow: Int
    let favoriteKeyWidth: CGFloat
    var mainRowsCount: Int = 3
    var topRowsCount: Int { numberRowCount + favoriteRowsCount }
    var rowCount: Int { mainRowsCount + topRowsCount }
    var contentHeight: CGFloat { CGFloat(rowCount) * keyHeight + CGFloat(rowCount - 1) * rowSpacing }
}

/// Twelve character-width units leave room for native-style iPad functions.
/// Keep the compact layout for floating keyboards and narrow multitasking panes.
struct KeyboardPadTypingLayoutPlan: Equatable {
    let keySpacing: CGFloat
    let characterWidth: CGFloat
    let capsWidth: CGFloat
    let returnWidth: CGFloat
    let shiftWidth: CGFloat
    let tabWidth: CGFloat
    let deleteWidth: CGFloat
    let rightShiftWidth: CGFloat
    let backslashWidth: CGFloat
    let isANSI: Bool
    let hasNumberRow: Bool
}

enum KeyboardTypingLayoutPolicy {
    static let regularKeyHeight: CGFloat = 36
    static let compactKeyHeight: CGFloat = 36
    static let rowSpacing: CGFloat = 4
    static let maximumRows = 8
    static let maximumFavoriteRows = 4
    static let favoriteColumns = 10
    static func typingKeyHeight(availableWidth: CGFloat, isPad: Bool) -> CGFloat {
        isPad && availableWidth.isFinite && availableWidth >= 650 ? 52 : regularKeyHeight
    }
    private static let digits = Array("1234567890").map(String.init)
    private static let auxiliarySymbols = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
    private static let secondarySymbols = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
    private static let extraSymbols = ["§", "±", "×", "÷", "°", "©", "®", "™", "…", "·"]
    static let ansiRows: [[String]] = ["`1234567890-=", "qwertyuiop[]\\", "asdfghjkl;'", "zxcvbnm,./"]
        .map { row in row.map { String($0) } }
    static let compactANSIRows: [[String]] = ["qwertyuiop[]", "asdfghjkl;'", "zxcvbnm,./\\"]
        .map { row in row.map { String($0) } }
    private static let shiftedANSI = ["`": "~", "1": "!", "2": "@", "3": "#", "4": "$",
        "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
        "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"]

    static func usesANSI(availableWidth: CGFloat, isPad: Bool, isLandscape: Bool, padLayout: KeyboardPadLayout = .ansiNumbers) -> Bool {
        isPad && isLandscape && availableWidth.isFinite && availableWidth >= 980 && padLayout != .stock
    }

    static func ansiAlternateOutput(for key: String, state: KeyboardTypingState) -> String? {
        guard state.layout == .letters, let alternate = shiftedANSI[key] else { return nil }
        return state.shiftsANSISymbols ? key : alternate
    }

    /// The number page already contains its sole digit row. Its auxiliary row
    /// supplies symbols; the letters and symbols pages instead gain digits.
    static func auxiliaryRow(for layout: KeyboardTypingLayout, ansiPad: Bool = false) -> [String] {
        if ansiPad && layout == .symbols { return extraSymbols }
        return layout == .numbers ? auxiliarySymbols : digits
    }

    static func auxiliaryRowOutput(for key: String, layout: KeyboardTypingLayout, ansiPad: Bool = false) -> String? {
        auxiliaryRow(for: layout, ansiPad: ansiPad).contains(key) ? key : nil
    }

    /// The expanded number page is entered from QWERTY's persistent digit
    /// row. Its own main rows supply symbols instead of repeating any digits.
    static func rows(for layout: KeyboardTypingLayout, hasAuxiliaryRow: Bool, widePad: Bool = false, ansiPad: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers) -> [[String]] {
        if layout == .letters && widePad && ansiPad && padLayout != .stock { return padLayout == .ansiNumbers ? ansiRows : compactANSIRows }
        if layout == .letters && widePad { return Array(layout.rows.prefix(2)) + [layout.rows[2] + [",", "."]] }
        guard layout == .numbers && hasAuxiliaryRow else { return layout.rows }
        return [secondarySymbols] + layout.rows.dropFirst()
    }

    /// Membership follows the rendered core rows. Auxiliary keys remain a
    /// separate route, and a stale three-row digit button cannot broaden it.
    static func output(for key: String, state: KeyboardTypingState, hasAuxiliaryRow: Bool, widePad: Bool = false, ansiPad: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers) -> String? {
        guard rows(for: state.layout, hasAuxiliaryRow: hasAuxiliaryRow, widePad: widePad, ansiPad: ansiPad, padLayout: padLayout)
            .contains(where: { row in row.contains { $0.utf16.elementsEqual(key.utf16) } }) else { return nil }
        if ansiPad && widePad && padLayout != .stock && state.shiftsANSISymbols, let shifted = shiftedANSI[key] { return shifted }
        return state.label(for: key)
    }

    static func padPlan(availableWidth: CGFloat, isPad: Bool, layout: KeyboardTypingLayout, isLandscape: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers) -> KeyboardPadTypingLayoutPlan? {
        guard isPad, layout == .letters, availableWidth.isFinite, availableWidth >= 650 else { return nil }
        let gap: CGFloat = 7
        if usesANSI(availableWidth: availableWidth, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout) {
            let key = (availableWidth - gap * 14) / 15
            func span(_ units: CGFloat) -> CGFloat { key * units + gap * (units - 1) }
            return KeyboardPadTypingLayoutPlan(keySpacing: gap, characterWidth: key,
                capsWidth: span(1.75), returnWidth: span(2.25), shiftWidth: span(2.25),
                tabWidth: span(1.5), deleteWidth: span(padLayout == .ansiNumbers ? 2 : 1.5), rightShiftWidth: span(padLayout == .ansiNumbers ? 2.75 : 1.75),
                backslashWidth: padLayout == .ansiNumbers ? span(1.5) : key, isANSI: true, hasNumberRow: padLayout == .ansiNumbers)
        }
        let key = (availableWidth - gap * 11) / 12
        return KeyboardPadTypingLayoutPlan(keySpacing: gap, characterWidth: key,
            capsWidth: key * 1.35 + gap / 2, returnWidth: key * 1.65 + gap / 2,
            shiftWidth: key * 1.5 + gap / 2, tabWidth: key, deleteWidth: key,
            rightShiftWidth: key * 1.5 + gap / 2, backslashWidth: key, isANSI: false, hasNumberRow: false)
    }

    /// The English page can skip a redundant numeric-only entry label when its
    /// persistent digits already fit. The destination remains the full page.
    static func entryTitle(auxiliaryRowVisible: Bool) -> String {
        auxiliaryRowVisible ? "#+=" : "123"
    }

    /// Heights are the space inside the typing panel, excluding the shared
    /// toolbar, grip and footer. The ordinary three rows remain on every page.
    static func plan(availableHeight: CGFloat, availableWidth: CGFloat,
                     compact: Bool, layout: KeyboardTypingLayout,
                     favoriteCount: Int, isPad: Bool = false,
                     favoriteThreshold: Int = 5, isLandscape: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers) -> KeyboardTypingLayoutPlan? {
        let keySpacing: CGFloat = isPad ? 7 : 5
        let gaps = CGFloat(favoriteColumns - 1) * keySpacing
        // The number row has exactly ten keys. A width at or below its gap
        // budget cannot produce positive-width keys, even with scrolling.
        guard availableHeight.isFinite, availableWidth.isFinite,
              availableHeight > rowSpacing * 2, availableWidth > gaps else { return nil }
        // iPad keeps three character rows. Digits and punctuation live on
        // down-flicks rather than adding duplicate rows above the letters.
        if isPad {
            let ansi = usesANSI(availableWidth: availableWidth, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout) && padLayout == .ansiNumbers
            let rows = ansi ? 4 : 3
            let auxiliary = ansi && layout != .letters ? 1 : 0
            let spacing: CGFloat = availableWidth >= 650 && availableHeight > 12 ? 6 : rowSpacing
            guard availableHeight > CGFloat(rows - 1) * spacing else { return nil }
            let height = min(typingKeyHeight(availableWidth: availableWidth, isPad: true),
                             (availableHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            return KeyboardTypingLayoutPlan(keyHeight: height, rowSpacing: spacing, keySpacing: keySpacing,
                rowCapacity: rows, numberRowCount: auxiliary, favoriteRowsCount: 0,
                favoritesPerRow: favoriteColumns, favoriteKeyWidth: (availableWidth - gaps) / CGFloat(favoriteColumns), mainRowsCount: rows - auxiliary)
        }
        let standard: CGFloat = compact ? compactKeyHeight : regularKeyHeight
        let baselineHeight: CGFloat = standard * 3 + rowSpacing * 2
        let keyHeight: CGFloat
        let capacity: Int
        if availableHeight < baselineHeight {
            keyHeight = (availableHeight - rowSpacing * 2) / 3
            capacity = 3
        } else {
            keyHeight = standard
            // Clamp before converting to Int, including for extreme finite
            // inputs. Normal scene sizes never approach this bound.
            let rows: CGFloat = ((availableHeight + rowSpacing) / (standard + rowSpacing)).rounded(.down)
            capacity = Int(Swift.min(CGFloat(maximumRows), Swift.max(3, rows)))
        }
        let columns = favoriteColumns
        let favoriteWidth = (availableWidth - gaps) / CGFloat(columns)
        let numbers = capacity >= 4 ? 1 : 0
        let count = Swift.max(0, favoriteCount)
        let neededRows = count / columns + (count % columns == 0 ? 0 : 1)
        let threshold = Swift.max(5, favoriteThreshold)
        let favorites = layout == .letters && numbers == 1 && capacity >= threshold
            ? Swift.min(maximumFavoriteRows, Swift.min(capacity - 4, neededRows)) : 0
        return KeyboardTypingLayoutPlan(keyHeight: keyHeight, rowSpacing: rowSpacing, keySpacing: keySpacing,
            rowCapacity: capacity, numberRowCount: numbers, favoriteRowsCount: favorites,
            favoritesPerRow: columns, favoriteKeyWidth: favoriteWidth)
    }

    /// A separate literal digit row must not broaden the current page's key
    /// membership or consume manual Shift/caps state.
    static func numberRowOutput(for key: String) -> String? {
        var bytes = key.utf8.makeIterator()
        guard let byte = bytes.next(), (48...57).contains(byte), bytes.next() == nil else { return nil }
        return key
    }
}
