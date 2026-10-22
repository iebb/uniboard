import Foundation

enum KeyboardPadLayout: String, CaseIterable {
    case stock, ansi, ansiNumbers
    var title: String {
        switch self {
        case .stock: return "iPad"
        case .ansi: return "Compact ANSI"
        case .ansiNumbers: return "Full ANSI"
        }
    }
}

enum KeyboardPadSymbolMapping: String, CaseIterable {
    case standard, iPad, macOS, none
    var title: String {
        switch self {
        case .standard: return "Standard symbol page"
        case .iPad: return "iPad symbols"
        case .macOS: return "macOS Option symbols"
        case .none: return "Off"
        }
    }
}

/// Three typing rows, plus the digit row unless Settings turns it off.
struct KeyboardTypingLayoutPlan: Equatable {
    let keyHeight: CGFloat
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let numberRowCount: Int
    let mainRowsCount: Int
    var rowCount: Int { mainRowsCount + numberRowCount }
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
    static let regularKeyHeight: CGFloat = 36 * 1.15
    static let rowSpacing: CGFloat = 4
    /// Remote input windows can lack a scene or retain its portrait geometry.
    /// When the rendered keyboard is wider, use its own display's portrait
    /// edge. Never use the process-wide main screen for this fallback.
    static func isLandscapeContext(viewWidth: CGFloat, sceneSize: CGSize?, displaySize: CGSize?,
                                   orientationIsLandscape: Bool = false) -> Bool {
        guard viewWidth.isFinite, viewWidth > 0 else { return false }
        if orientationIsLandscape { return true }
        if let sceneSize, sceneSize.width.isFinite, sceneSize.height.isFinite,
           sceneSize.width > 0, sceneSize.height > 0, viewWidth <= sceneSize.width + 1 {
            return sceneSize.width > sceneSize.height
        }
        guard let displaySize, displaySize.width.isFinite, displaySize.height.isFinite,
              displaySize.width > 0, displaySize.height > 0 else { return false }
        return viewWidth > min(displaySize.width, displaySize.height) + 1
            && viewWidth <= max(displaySize.width, displaySize.height) + 1
    }
    static func typingKeyHeight(availableWidth: CGFloat, isPad: Bool) -> CGFloat {
        isPad && availableWidth.isFinite && availableWidth >= 650 ? 52 * 1.15 : regularKeyHeight
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

    static func usesShiftedTap(for key: String, state: KeyboardTypingState, ansiPad: Bool) -> Bool {
        guard state.layout == .letters else { return false }
        if key.utf8.count == 1, let byte = key.utf8.first, (97...122).contains(byte) {
            return state.shift != .lowercase
        }
        return ansiPad && state.shiftsANSISymbols && shiftedANSI[key] != nil
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

    /// Heights are the space inside the typing panel, excluding the shared
    /// toolbar, grip and footer. The ordinary three rows remain on every page.
    /// A full ANSI layout keeps its own digit row whatever `showsNumberRow` says.
    static func plan(availableHeight: CGFloat, availableWidth: CGFloat,
                     compact: Bool, layout: KeyboardTypingLayout,
                     isPad: Bool = false, isLandscape: Bool = false,
                     padLayout: KeyboardPadLayout = .ansiNumbers,
                     showsNumberRow: Bool = true) -> KeyboardTypingLayoutPlan? {
        let spacing: CGFloat = isPad && availableWidth >= 650 ? 6 : rowSpacing
        let keySpacing: CGFloat = isPad ? 7 : 5
        guard availableHeight.isFinite, availableWidth.isFinite,
              availableHeight > spacing * 3, availableWidth > keySpacing * 9 else { return nil }
        let ansiNumbers = usesANSI(availableWidth: availableWidth, isPad: isPad,
            isLandscape: isLandscape, padLayout: padLayout) && padLayout == .ansiNumbers && layout == .letters
        let ideal = typingKeyHeight(availableWidth: availableWidth, isPad: isPad)
        let numberRows = !ansiNumbers && showsNumberRow ? 1 : 0
        let rows = CGFloat((ansiNumbers ? 4 : 3) + numberRows)
        return KeyboardTypingLayoutPlan(keyHeight: min(ideal, (availableHeight - spacing * (rows - 1)) / rows),
            rowSpacing: spacing, keySpacing: keySpacing, numberRowCount: numberRows,
            mainRowsCount: ansiNumbers ? 4 : 3)
    }

    /// A separate literal digit row must not broaden the current page's key
    /// membership or consume manual Shift/caps state.
    static func numberRowOutput(for key: String) -> String? {
        var bytes = key.utf8.makeIterator()
        guard let byte = bytes.next(), (48...57).contains(byte), bytes.next() == nil else { return nil }
        return key
    }
}
