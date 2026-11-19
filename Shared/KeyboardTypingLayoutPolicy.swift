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

/// ABC keeps its arrangement geometry. Symbol pages share that content height,
/// with three stock rows, four merged rows, or the retained ANSI extra row.
struct KeyboardTypingLayoutPlan: Equatable {
    let keyHeight: CGFloat
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let numberRowCount: Int
    let mainRowsCount: Int
    let extraSymbolRowCount: Int
    var auxiliaryRowCount: Int { numberRowCount + extraSymbolRowCount }
    var rowCount: Int { mainRowsCount + auxiliaryRowCount }
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

    static func usesShiftedTap(for key: String, state: KeyboardTypingState, ansiPad: Bool) -> Bool {
        guard state.layout == .letters else { return false }
        if state.alphabet.isCasedLetter(key) { return state.shift != .lowercase }
        return ansiPad && state.shiftsANSISymbols && shiftedANSI[key] != nil
    }

    /// Only ABC has auxiliary digits. ANSI #+= retains its non-digit symbols;
    /// 123 always has its stock digit row, never an auxiliary row.
    static func auxiliaryRow(for layout: KeyboardTypingLayout, ansiPad: Bool = false) -> [String] {
        switch layout {
        case .letters: return digits
        case .numbers: return []
        case .symbols: return ansiPad ? extraSymbols : []
        }
    }

    static func auxiliaryRowOutput(for key: String, layout: KeyboardTypingLayout, ansiPad: Bool = false) -> String? {
        auxiliaryRow(for: layout, ansiPad: ansiPad).contains(key) ? key : nil
    }

    /// Fallback symbol pages stay stock despite outgoing auxiliary/wide/ANSI
    /// preferences. Only the shared eligibility decision admits merged rows.
    static func rows(for layout: KeyboardTypingLayout, hasAuxiliaryRow: Bool, widePad: Bool = false, ansiPad: Bool = false,
                     padLayout: KeyboardPadLayout = .ansiNumbers, alphabet: KeyboardAlphabet = .english, mergedSymbols: Bool = false) -> [[String]] {
        if layout == .symbols && mergedSymbols { return KeyboardMergedSymbolsPolicy.rows }
        if layout == .letters && widePad && ansiPad && padLayout != .stock { return padLayout == .ansiNumbers ? ansiRows : compactANSIRows }
        let base = layout.rows(for: alphabet)
        if layout == .letters && widePad { return Array(base.prefix(2)) + [base[2] + [",", "."]] }
        return base
    }

    /// Membership follows the rendered core rows. Auxiliary keys remain a
    /// separate route; stale auxiliary/wide/ANSI flags cannot broaden a page.
    static func output(for key: String, state: KeyboardTypingState, hasAuxiliaryRow: Bool, widePad: Bool = false, ansiPad: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers, mergedSymbols: Bool = false) -> String? {
        guard rows(for: state.layout, hasAuxiliaryRow: hasAuxiliaryRow, widePad: widePad, ansiPad: ansiPad, padLayout: padLayout,
                   alphabet: state.alphabet, mergedSymbols: mergedSymbols)
            .contains(where: { row in row.contains { $0.utf16.elementsEqual(key.utf16) } }) else { return nil }
        if state.layout == .letters && ansiPad && widePad && padLayout != .stock && state.shiftsANSISymbols, let shifted = shiftedANSI[key] { return shifted }
        return state.label(for: key)
    }

    static func padPlan(availableWidth: CGFloat, isPad: Bool, layout: KeyboardTypingLayout, isLandscape: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers,
                        alphabet: KeyboardAlphabet = .english) -> KeyboardPadTypingLayoutPlan? {
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
        // Tab and Delete, Caps Lock and Return, and both Shifts with comma and
        // period take 2, 3 and 5 key widths. English fills 12 units in each row;
        // longer rows narrow every key so the widest row still fits.
        let rows = alphabet.rows
        let units = CGFloat(max(12, rows[0].count + 2, rows[1].count + 3, rows[2].count + 5))
        let key = (availableWidth - gap * (units - 1)) / units
        return KeyboardPadTypingLayoutPlan(keySpacing: gap, characterWidth: key,
            capsWidth: key * 1.35 + gap / 2, returnWidth: key * 1.65 + gap / 2,
            shiftWidth: key * 1.5 + gap / 2, tabWidth: key, deleteWidth: key,
            rightShiftWidth: key * 1.5 + gap / 2, backslashWidth: key, isANSI: false, hasNumberRow: false)
    }

    /// Heights exclude the shared toolbar, grip and footer. ABC's row count
    /// still determines the outer budget; symbol rows divide that same content
    /// height, rather than leaving the former fourth row blank.
    /// `phonePortrait` (the iPhone portrait default layout) keeps every page on
    /// the same 45-point rows 56 apart instead, so switching pages never moves
    /// a row; shorter pages leave their top rows empty.
    static func plan(availableHeight: CGFloat, availableWidth: CGFloat,
                     compact: Bool, layout: KeyboardTypingLayout,
                     isPad: Bool = false, isLandscape: Bool = false,
                     padLayout: KeyboardPadLayout = .ansiNumbers,
                     keyRows: Int = MainKeyboardArrangement.maximumRows, mergedSymbols: Bool = false,
                     phonePortrait: Bool = false) -> KeyboardTypingLayoutPlan? {
        if phonePortrait && !isPad {
            return phonePortraitPlan(availableHeight: availableHeight, availableWidth: availableWidth,
                                     layout: layout, keyRows: keyRows, mergedSymbols: mergedSymbols)
        }
        let spacing: CGFloat = isPad && availableWidth >= 650 ? 6 : rowSpacing
        let keySpacing: CGFloat = isPad ? 7 : 5
        guard availableHeight.isFinite, availableWidth.isFinite,
              availableHeight > spacing * 3, availableWidth > keySpacing * 9 else { return nil }
        let ansi = usesANSI(availableWidth: availableWidth, isPad: isPad,
            isLandscape: isLandscape, padLayout: padLayout)
        let fullANSI = ansi && padLayout == .ansiNumbers
        let arrangementAuxiliary = min(1, max(0, keyRows - 3))
        let numberRows = layout == .letters && !fullANSI ? arrangementAuxiliary : 0
        // Preserve the ANSI symbols where they were already drawn. This is
        // not a number row and must never admit digit presses on #+=.
        let extraRows = layout == .symbols && ansi ? arrangementAuxiliary : 0
        let mainRows = layout == .symbols && mergedSymbols ? 4 : layout == .letters && fullANSI ? 4 : 3
        let rows = CGFloat(mainRows + numberRows + extraRows)
        let ideal = typingKeyHeight(availableWidth: availableWidth, isPad: isPad)
        let abcRows = CGFloat(fullANSI ? 4 : 3 + arrangementAuxiliary)
        let contentHeight = min(availableHeight, abcRows * ideal + (abcRows - 1) * spacing)
        let height = layout == .letters ? min(ideal, (availableHeight - spacing * (rows - 1)) / rows)
            : (contentHeight - spacing * (rows - 1)) / rows
        return KeyboardTypingLayoutPlan(keyHeight: height, rowSpacing: spacing, keySpacing: keySpacing,
            numberRowCount: numberRows, mainRowsCount: mainRows, extraSymbolRowCount: extraRows)
    }

    private static func phonePortraitPlan(availableHeight: CGFloat, availableWidth: CGFloat, layout: KeyboardTypingLayout,
                                          keyRows: Int, mergedSymbols: Bool) -> KeyboardTypingLayoutPlan? {
        let spacing = KeyboardPhonePortraitGeometry.rowGap
        let keySpacing = KeyboardPhonePortraitGeometry.keyGap
        guard availableHeight.isFinite, availableWidth.isFinite,
              availableHeight > spacing * 3, availableWidth > keySpacing * 9 else { return nil }
        let numberRows = layout == .letters ? min(1, max(0, keyRows - 3)) : 0
        let mainRows = layout == .symbols && mergedSymbols ? 4 : 3
        // A short host scene shrinks the keys rather than dropping a row,
        // by ABC's row count so every page keeps the same rows.
        let rows = CGFloat(max(mainRows + numberRows, 3 + min(1, max(0, keyRows - 3))))
        let key = KeyboardPhonePortraitGeometry.Rows(width: availableWidth + 16).keyHeight
        let height = min(key, (availableHeight - spacing * (rows - 1)) / rows)
        return KeyboardTypingLayoutPlan(keyHeight: height, rowSpacing: spacing, keySpacing: keySpacing,
            numberRowCount: numberRows, mainRowsCount: mainRows, extraSymbolRowCount: 0)
    }

    /// Shared editor/extension symbol rendering context. Callers supply the
    /// actual container width, not a device-wide screen size or an idiom guess.
    static func showsSymbolReturn(availableWidth: CGFloat, isPad: Bool) -> Bool {
        isPad && availableWidth.isFinite && availableWidth >= 650
    }

    static func symbolSwitchTitle(to layout: KeyboardTypingLayout, isPad: Bool,
                                  ansiPad: Bool = false, padLayout: KeyboardPadLayout = .stock) -> String {
        layout == .symbols ? "#+=" : ansiPad && padLayout == .ansiNumbers ? "=<>" : isPad ? ".?123" : "123"
    }

    /// A single membership decision for tap, hold and swipe factories. Digits
    /// embedded in a custom ABC arrangement are allowed, but stale auxiliary
    /// flags can never turn a stock symbol page into an invisible digit row.
    static func routedOutput(for key: String, state: KeyboardTypingState, hasAuxiliaryRow: Bool,
                             isAuxiliaryKey: Bool, widePad: Bool, ansiPad: Bool,
                             padLayout: KeyboardPadLayout, arrangement: MainKeyboardArrangement, mergedSymbols: Bool = false) -> String? {
        if isAuxiliaryKey {
            if state.layout == .letters && MainKeyboardArrangement.isDigit(key) {
                guard hasAuxiliaryRow || arrangement.keys.contains(key) else { return nil }
            } else {
                guard hasAuxiliaryRow, state.layout == .symbols, ansiPad, padLayout != .stock,
                      arrangement.keyRows(widePad: true) > 3 else { return nil }
            }
            return auxiliaryRowOutput(for: key, layout: state.layout, ansiPad: ansiPad)
        }
        return output(for: key, state: state, hasAuxiliaryRow: hasAuxiliaryRow,
                      widePad: widePad, ansiPad: ansiPad, padLayout: padLayout, mergedSymbols: mergedSymbols)
    }

    /// Letter rows of a caseless layout, which has no Shift: every letter
    /// one width, set by the widest row with its function keys, other rows
    /// centred. Row 3's Delete, and Arabic Diacritics before it, share the
    /// width the letters leave, never narrower than a letter. Nil for cased
    /// layouts, which keep Shift's fixed width, or for unusable geometry.
    static func caselessKeyWidths(for alphabet: KeyboardAlphabet, available: CGFloat,
                                  spacing: CGFloat) -> (letter: CGFloat, function: CGFloat)? {
        guard alphabet.isCaseless, available.isFinite, spacing.isFinite, spacing >= 0 else { return nil }
        let rows = alphabet.rows, functions = alphabet.hasShiftSlot ? 2 : 1
        let lastRow = rows[2].count + functions
        let count = max(rows[0].count, rows[1].count, lastRow)
        let letter = (available - spacing * CGFloat(count - 1)) / CGFloat(count)
        guard letter > 0 else { return nil }
        let left = available - CGFloat(rows[2].count) * letter - spacing * CGFloat(lastRow - 1)
        return (letter, max(letter, left / CGFloat(functions)))
    }

    /// A separate literal digit row must not broaden the current page's key
    /// membership or consume manual Shift/caps state.
    static func numberRowOutput(for key: String) -> String? {
        var bytes = key.utf8.makeIterator()
        guard let byte = bytes.next(), (48...57).contains(byte), bytes.next() == nil else { return nil }
        return key
    }
}

/// The actual stable ABC rendering branch, shared by merge eligibility and the
/// extension. Explicit rows suppress ANSI; legacy wide layouts project their
/// own rows, including a full number row even when saved digit IDs are absent.
struct KeyboardABCRendering {
    let arrangement: MainKeyboardArrangement
    let alphabet: KeyboardAlphabet
    let widePad: Bool
    let ansiPad: Bool
    let arranged: Bool
    let hasAuxiliaryRow: Bool
    let rows: [[String]]
    var rowCount: Int { rows.count + (hasAuxiliaryRow && !arranged ? 1 : 0) }

    init(alphabet: KeyboardAlphabet, arrangement: MainKeyboardArrangement,
         availableWidth: CGFloat, isPad: Bool, isLandscape: Bool, padLayout: KeyboardPadLayout) {
        self.arrangement = arrangement
        self.alphabet = alphabet.arranged(arrangement.letterRows)
        let explicit = !arrangement.isLegacy
        let pad = explicit ? nil : KeyboardTypingLayoutPolicy.padPlan(availableWidth: availableWidth,
            isPad: isPad, layout: .letters, isLandscape: isLandscape, padLayout: padLayout, alphabet: alphabet)
        widePad = pad != nil
        ansiPad = pad?.isANSI == true
        arranged = explicit || pad == nil && arrangement != .standard(for: alphabet) && arrangement != .letters(for: alphabet)
        hasAuxiliaryRow = !(ansiPad && padLayout == .ansiNumbers)
            && arrangement.keyRows(widePad: widePad) > 3
        rows = arranged ? arrangement.rows.map { $0.compactMap { cell in
            if case .key(let key) = cell { return MainKeyboardArrangement.isFunction(key) ? nil : key }
            return nil
        } } : KeyboardTypingLayoutPolicy.rows(for: .letters, hasAuxiliaryRow: hasAuxiliaryRow,
            widePad: widePad, ansiPad: ansiPad, padLayout: padLayout, alphabet: self.alphabet)
    }

    /// Use the same routing and tap override chain as a rendered character key.
    /// Shift/hold/swipe state deliberately does not participate in eligibility.
    func plainTapOutputs(settings: KeyboardKeySettings.Snapshot, padLayout: KeyboardPadLayout) -> Set<String> {
        var state = KeyboardTypingState()
        state.selectAlphabet(alphabet)
        let auxiliary = hasAuxiliaryRow && !arranged
            ? KeyboardTypingLayoutPolicy.auxiliaryRow(for: .letters) : []
        let keys = rows.flatMap { $0 } + auxiliary
        return Set(keys.compactMap { key in
            let isAuxiliary = auxiliary.contains(key) || arranged && MainKeyboardArrangement.isDigit(key)
            guard let id = KeyboardKeySettings.identifier(forCharacter: key),
                  let original = KeyboardTypingLayoutPolicy.routedOutput(for: key, state: state,
                    hasAuxiliaryRow: hasAuxiliaryRow, isAuxiliaryKey: isAuxiliary,
                    widePad: widePad, ansiPad: ansiPad, padLayout: padLayout, arrangement: arrangement) else { return nil }
            return settings.tapOutput(for: id, defaultText: original, shifted: false)
        })
    }
}

/// Presentation only: no key settings, identifiers or arrangements are changed.
enum KeyboardMergedSymbolsPolicy {
    static let rows: [[String]] = [KeyboardTypingLayout.symbols.rows[0], KeyboardTypingLayout.symbols.rows[1],
                                   KeyboardTypingLayout.numbers.rows[1], KeyboardTypingLayout.symbols.rows[2]]

    enum Eligibility: Equatable {
        case merged, missingDigits, insufficientSpace
        var isEligible: Bool { self == .merged }
    }

    static func eligibility(settings: KeyboardKeySettings.Snapshot, alphabet: KeyboardAlphabet,
                            availableWidth: CGFloat, isPad: Bool, isLandscape: Bool = false,
                            padLayout: KeyboardPadLayout = .stock,
                            normalKeyHeight: CGFloat = KeyboardTypingLayoutPolicy.regularKeyHeight) -> Eligibility {
        let rendering = KeyboardABCRendering(alphabet: alphabet, arrangement: settings.effectiveArrangement(for: alphabet),
            availableWidth: availableWidth, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout)
        // The reason comes from actual routed tap outputs, not saved key labels.
        // Missing/remapped digits wins even when geometry also prevents merging.
        guard Set(MainKeyboardArrangement.digits).isSubset(of: rendering.plainTapOutputs(settings: settings, padLayout: padLayout)) else { return .missingDigits }
        guard normalKeyHeight.isFinite, normalKeyHeight + 0.0001 >= KeyboardTypingLayoutPolicy.regularKeyHeight,
              availableWidth.isFinite, availableWidth > (isPad ? 7 : 5) * 9,
              !isPad || availableWidth < 650, rendering.rowCount == 4 else { return .insufficientSpace }
        return .merged
    }

    /// Compatibility entry point: no rendering behavior changes for callers.
    static func isEligible(settings: KeyboardKeySettings.Snapshot, alphabet: KeyboardAlphabet,
                           availableWidth: CGFloat, isPad: Bool, isLandscape: Bool = false,
                           padLayout: KeyboardPadLayout = .stock,
                           normalKeyHeight: CGFloat = KeyboardTypingLayoutPolicy.regularKeyHeight) -> Bool {
        eligibility(settings: settings, alphabet: alphabet, availableWidth: availableWidth, isPad: isPad,
            isLandscape: isLandscape, padLayout: padLayout, normalKeyHeight: normalKeyHeight).isEligible
    }

    static func transitionMessage(from before: Eligibility, to after: Eligibility) -> String? {
        guard before.isEligible != after.isEligible else { return nil }
        switch after {
        case .merged: return "Symbols now fit on one page because ABC types all ten digits. Your key actions are unchanged."
        case .missingDigits: return "123 and #+= are separate again because ABC no longer types all ten digits. Your key actions are unchanged."
        case .insufficientSpace: return "123 and #+= are separate again because the symbols no longer fit on one page. Your key actions are unchanged."
        }
    }

    static func page(_ page: KeyboardTypingLayout, merged: Bool) -> KeyboardTypingLayout {
        merged && page == .numbers ? .symbols : page
    }

    static func punctuationWidth(available: CGFloat, spacing: CGFloat, deleteWidth: CGFloat) -> CGFloat {
        max(0, (available - deleteWidth - spacing * 5) / 5)
    }
}

/// iPhone portrait with the stock rows (the default layout): Apple's iOS 26
/// keyboard. Every letter is one width on Apple's columns, rows sit 56 points
/// apart counted up from the bottom row, and the bottom row lines up with the
/// letters. Saved arrangements, iPad, landscape and the floating keyboard
/// keep their own geometry. Horizontal positions are from the keyboard's left
/// edge; rows are counted up from the bottom row.
struct KeyboardPhonePortraitGeometry: Equatable {
    struct Span: Equatable {
        let x: CGFloat
        let width: CGFloat
        var maxX: CGFloat { x + width }
    }

    static let sideMargin: CGFloat = 8
    static let keyGap: CGFloat = 8
    static let rowGap: CGFloat = 11
    static let keyHeight: CGFloat = 45
    static let bottomPadding: CGFloat = 7
    static let topPadding: CGFloat = 4
    /// The toolbar's place and the gap under it: the band above the top key
    /// row is 52 points, as tall as Apple's suggestion strip.
    static let toolbarHeight: CGFloat = 42
    static let toolbarGap: CGFloat = 6
    static var topBand: CGFloat { topPadding + toolbarHeight + toolbarGap }
    static var rowPitch: CGFloat { keyHeight + rowGap }

    /// The keyboard's height with `keyRows` rows above the bottom row:
    /// 272 points with three, 328 with the number row too.
    static func height(keyRows: Int) -> CGFloat { Rows.large.height(keyRows: keyRows) }

    /// Apple's rows by keyboard width (spec 1.1 §6); columns don't change.
    /// Plus and Pro Max (430 points and wider): 45-point keys, the 52-point
    /// band and 7 points under the bottom row, the constants above. Narrower
    /// phones: 43-point keys 54 apart and a 51.3-point band. Apple's bottom
    /// row there ends 17.7 points above the globe, below the bottom edge an
    /// extension is given, so nothing goes under the bottom row and every
    /// row sits as close to Apple's as the keyboard can draw.
    struct Rows: Equatable {
        let keyHeight: CGFloat
        let bottomPadding: CGFloat
        /// Between the toolbar's place and the top key row.
        let toolbarGap: CGFloat
        var rowGap: CGFloat { KeyboardPhonePortraitGeometry.rowGap }
        var rowPitch: CGFloat { keyHeight + rowGap }
        var topBand: CGFloat { KeyboardPhonePortraitGeometry.topPadding + KeyboardPhonePortraitGeometry.toolbarHeight + toolbarGap }

        static let large = Rows(keyHeight: KeyboardPhonePortraitGeometry.keyHeight, bottomPadding: KeyboardPhonePortraitGeometry.bottomPadding,
                                toolbarGap: KeyboardPhonePortraitGeometry.toolbarGap)
        static let compact = Rows(keyHeight: 43, bottomPadding: 0, toolbarGap: 5.3)
        static let largeMinimumWidth: CGFloat = 430
        /// `width` is the keyboard's.
        init(width: CGFloat) { self = width >= Self.largeMinimumWidth ? .large : .compact }
        private init(keyHeight: CGFloat, bottomPadding: CGFloat, toolbarGap: CGFloat) {
            self.keyHeight = keyHeight; self.bottomPadding = bottomPadding; self.toolbarGap = toolbarGap
        }

        /// 272 / 328 points on the large phones, 256.3 / 310.3 on the others.
        func height(keyRows: Int) -> CGFloat {
            let rows = CGFloat(max(1, keyRows))
            return topBand + (rows + 1) * keyHeight + rows * rowGap + bottomPadding
        }
    }

    /// Top of the row `index` rows above the bottom row, where `bottom` is
    /// the bottom row's bottom edge (7 points above the keyboard's).
    static func rowTop(aboveBottomRow index: Int, bottom: CGFloat) -> CGFloat {
        bottom - keyHeight - CGFloat(index) * rowPitch
    }

    let width: CGFloat
    /// Letter columns: English has ten. Other layouts use their widest row,
    /// counting Shift and Delete as at least a key each.
    let columns: Int

    init?(width: CGFloat, alphabet: KeyboardAlphabet = .english) {
        let rows = alphabet.rows
        guard width.isFinite, rows.count == 3 else { return nil }
        let functions = alphabet.isCaseless ? (alphabet.hasShiftSlot ? 2 : 1) : 2
        self.width = width
        columns = max(rows[0].count, rows[1].count, rows[2].count + functions)
        guard keyWidth >= 1 else { return nil }
    }

    private var m: CGFloat { Self.sideMargin }
    private var g: CGFloat { Self.keyGap }
    private var available: CGFloat { width - 2 * m }
    /// k = (W − 16 − 9 × 8) / 10 for English.
    var keyWidth: CGFloat { (available - CGFloat(columns - 1) * g) / CGFloat(columns) }
    var pitch: CGFloat { keyWidth + g }

    /// `count` letter-wide keys centred on the columns: the Q row starts at
    /// the margin and the A row half a key in.
    func characterRow(count: Int) -> [Span] {
        let start = m + CGFloat(columns - count) * pitch / 2
        return (0..<max(0, count)).map { Span(x: start + CGFloat($0) * pitch, width: keyWidth) }
    }

    /// The last letter row. Cased layouts put Shift at the left margin and
    /// Delete at the right, two gaps from the letters as Apple's are (one gap
    /// when two would leave them narrower than a letter). Caseless layouts
    /// keep one gap, with Delete and any Diacritics key at least a letter wide.
    func lastLetterRow(letters count: Int, alphabet: KeyboardAlphabet = .english) -> (leading: Span?, letters: [Span], trailing: Span) {
        let letters = CGFloat(count) * keyWidth + CGFloat(max(0, count - 1)) * g
        if alphabet.isCaseless {
            let functions = alphabet.hasShiftSlot ? 2 : 1
            let function = max(keyWidth, (available - letters - CGFloat(functions) * g) / CGFloat(functions))
            let total = letters + CGFloat(functions) * (function + g)
            var x = m + (available - total) / 2
            var leading: Span?
            if alphabet.hasShiftSlot { leading = Span(x: x, width: function); x += function + g }
            let keys = (0..<count).map { Span(x: x + CGFloat($0) * pitch, width: keyWidth) }
            return (leading, keys, Span(x: x + letters + g, width: function))
        }
        var gap = 2 * g
        if (available - letters - 2 * gap) / 2 < keyWidth { gap = g }
        let function = (available - letters - 2 * gap) / 2
        let start = m + function + gap
        let keys = (0..<count).map { Span(x: start + CGFloat($0) * pitch, width: keyWidth) }
        return (Span(x: m, width: function), keys, Span(x: start + letters + gap, width: function))
    }

    /// The 123 and #+= pages: the page key and Delete take English's Shift
    /// and Delete places (1.5 keys less two gaps), and five punctuation keys
    /// share the space between them. The merged page has no page key there.
    func punctuationRow(count: Int, leadingKey: Bool) -> (leading: Span?, keys: [Span], trailing: Span) {
        let function = 1.5 * pitch - 2 * g
        let trailing = Span(x: width - m - function, width: function)
        let start = leadingKey ? m + function + 2 * g : m
        let end = trailing.x - 2 * g
        let keys = max(1, count)
        let key = (end - start - CGFloat(keys - 1) * g) / CGFloat(keys)
        return (leadingKey ? Span(x: m, width: function) : nil,
                (0..<count).map { Span(x: start + CGFloat($0) * (key + g), width: key) }, trailing)
    }

    /// The bottom row: `smallKeys` keys (U, page, ☆, and Globe or Collapse
    /// when shown) one letter wide from the margin; Return from K's column
    /// to the margin; Space between them, one gap from each.
    func bottomRow(smallKeys: Int, showsReturn: Bool = true) -> (small: [Span], space: Span, returnKey: Span?) {
        let small = (0..<max(0, smallKeys)).map { Span(x: m + CGFloat($0) * pitch, width: keyWidth) }
        let returnX = m + (CGFloat(columns) - 2.5) * pitch
        let returnKey = showsReturn ? Span(x: returnX, width: width - m - returnX) : nil
        let spaceX = m + CGFloat(max(0, smallKeys)) * pitch
        let spaceEnd = returnKey.map { $0.x - g } ?? width - m
        return (small, Span(x: spaceX, width: spaceEnd - spaceX), returnKey)
    }
}

/// Apple's keyboard has no dead zones: a tap in a gap goes to the nearest
/// key. Each key's touch area reaches halfway into the gaps beside it, above
/// and below it; the first and last key of a row reach the keyboard's edges,
/// the bottom row reaches its bottom, and the top row reaches up half a row
/// gap. Visible key frames, and so accessibility frames, do not change.
enum KeyboardKeyHitRegions {
    /// Indices of `frames` grouped into rows, top to bottom, each left to right.
    static func rows(of frames: [CGRect], tolerance: CGFloat = 1) -> [[Int]] {
        var rows: [[Int]] = []
        for index in frames.indices.sorted(by: { frames[$0].minY < frames[$1].minY }) {
            if let last = rows.last?.first, abs(frames[last].minY - frames[index].minY) <= tolerance {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        return rows.map { $0.sorted { frames[$0].minX < frames[$1].minX } }
    }

    /// Touch areas for rows of visible frames, each row left to right.
    static func regions(rows: [[CGRect]], bounds: CGRect) -> [[CGRect]] {
        let rows = rows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return [] }
        let tops = rows.map { $0.map(\.minY).min() ?? 0 }
        let bottoms = rows.map { $0.map(\.maxY).max() ?? 0 }
        return rows.indices.map { r in
            let top: CGFloat
            if r == 0 { top = rows.count > 1 ? tops[0] - max(0, tops[1] - bottoms[0]) / 2 : tops[0] }
            else { top = (bottoms[r - 1] + tops[r]) / 2 }
            let bottom = r == rows.count - 1 ? max(bounds.maxY, bottoms[r]) : (bottoms[r] + tops[r + 1]) / 2
            let row = rows[r]
            return row.indices.map { i in
                let left = i == 0 ? min(bounds.minX, row[i].minX) : (row[i - 1].maxX + row[i].minX) / 2
                let right = i == row.count - 1 ? max(bounds.maxX, row[i].maxX) : (row[i].maxX + row[i + 1].minX) / 2
                return CGRect(x: left, y: top, width: right - left, height: bottom - top)
            }
        }
    }

    /// The key whose touch area holds `point`, as (row, index in row).
    static func key(at point: CGPoint, regions: [[CGRect]]) -> (row: Int, index: Int)? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        for (r, row) in regions.enumerated() {
            for (i, region) in row.enumerated() where point.x >= region.minX && point.x < region.maxX
                && point.y >= region.minY && point.y < region.maxY {
                return (r, i)
            }
        }
        // The far right and bottom edges belong to the last key.
        for (r, row) in regions.enumerated() {
            for (i, region) in row.enumerated() where point.x >= region.minX && point.x <= region.maxX
                && point.y >= region.minY && point.y <= region.maxY {
                return (r, i)
            }
        }
        return nil
    }
}
