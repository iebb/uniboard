import Foundation
import CoreGraphics

/// Exact Unicode strings are input data: canonically equivalent spellings
/// remain separate choices and are never normalized before insertion.
enum KeyboardVariantPolicy {
    static let maximumVariants = 16
    static let maximumScalars = 64
    static let swipeThreshold: CGFloat = 12
    static let horizontalChoiceStride: CGFloat = 36
    private static let standardPadSymbols: [String: String] = {
        let keys = KeyboardTypingLayout.letters.rows.flatMap { $0 }
        let rows = KeyboardTypingLayout.numbers.rows
        let top = rows[0]
        let home = Array(rows[1].prefix(9))
        let bottom = rows[2] + Array(rows[1].suffix(1)) + [KeyboardTypingLayout.symbols.rows[0][0]]
        return Dictionary(uniqueKeysWithValues: zip(keys, top + home + bottom))
    }()

    // Snapshot of Apple's com.apple.keylayout.US, ANSI keyboard type 40.
    // Option dead keys use their literal spacing forms, never composition.
    // Keep Shift–Option outputs exact: e.g. Option-S = ß, Shift–Option-S = Í.
    private static let macOSKeys = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./").map(String.init)
    private static let macOSShiftedKeys = Array("~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?").map(String.init)
    private static let macOSOption = Array("`¡™£¢∞§¶•ªº–≠œ∑´®†¥¨ˆøπ“‘«åß∂ƒ©˙∆˚¬…æΩ≈ç√∫˜µ≤≥÷").map(String.init)
    private static let macOSShiftOption = Array("`⁄€‹›ﬁﬂ‡°·‚—±Œ„´‰ˇÁ¨ˆØ∏”’»ÅÍÎÏ˝ÓÔ\u{F8FF}ÒÚÆ¸˛Ç◊ı˜Â¯˘¿").map(String.init)

    static func macOSOptionCandidates(for key: String) -> [String] {
        guard let index = macOSKeys.firstIndex(of: key) ?? macOSShiftedKeys.firstIndex(of: key),
              macOSOption.indices.contains(index), macOSShiftOption.indices.contains(index) else { return [] }
        return candidates(override: [macOSOption[index], macOSShiftOption[index]], defaults: [])
    }

    /// Swipe down offers other presentation forms of the same character:
    /// super- and subscripts, mathematical styles, then circled, fullwidth and
    /// similar forms. Letters keep the current case; Shift is unchanged.
    static func defaultSwipeDown(for key: String, state: KeyboardTypingState) -> [String] {
        guard key.unicodeScalars.count == 1, let value = key.unicodeScalars.first?.value else { return [] }
        let forms: [String]
        if state.layout == .letters, (0x61...0x7A).contains(value) {
            forms = letterForms(Int(value - 0x61), uppercase: state.shift != .lowercase)
        } else if (0x30...0x39).contains(value) {
            forms = digitForms(Int(value - 0x30))
        } else {
            forms = symbolForms[key] ?? []
        }
        guard let first = forms.first else { return [] }
        return options(text: first, variants: Array(forms.dropFirst()))
    }

    private static func scalars(_ values: [UInt32]) -> [String] {
        values.compactMap { $0 == 0 ? nil : Unicode.Scalar($0).map { String(Character($0)) } }
    }
    private static let superscriptLower: [UInt32] = [0x1D43, 0x1D47, 0x1D9C, 0x1D48, 0x1D49, 0x1DA0, 0x1D4D, 0x02B0, 0x2071,
        0x02B2, 0x1D4F, 0x02E1, 0x1D50, 0x207F, 0x1D52, 0x1D56, 0, 0x02B3, 0x02E2, 0x1D57, 0x1D58, 0x1D5B, 0x02B7, 0x02E3, 0x02B8, 0x1DBB]
    private static let superscriptUpper: [UInt32] = [0x1D2C, 0x1D2E, 0, 0x1D30, 0x1D31, 0, 0x1D33, 0x1D34, 0x1D35,
        0x1D36, 0x1D37, 0x1D38, 0x1D39, 0x1D3A, 0x1D3C, 0x1D3E, 0, 0x1D3F, 0, 0x1D40, 0x1D41, 0x2C7D, 0x1D42, 0, 0, 0]
    private static let subscriptLower: [UInt32] = [0x2090, 0, 0, 0, 0x2091, 0, 0, 0x2095, 0x1D62,
        0x2C7C, 0x2096, 0x2097, 0x2098, 0x2099, 0x2092, 0x209A, 0, 0x1D63, 0x209B, 0x209C, 0x1D64, 0x1D65, 0, 0x2093, 0, 0]
    private static let smallCapitals: [UInt32] = [0x1D00, 0x0299, 0x1D04, 0x1D05, 0x1D07, 0xA730, 0x0262, 0x029C, 0x026A,
        0x1D0A, 0x1D0B, 0x029F, 0x1D0D, 0x0274, 0x1D0F, 0x1D18, 0, 0x0280, 0xA731, 0x1D1B, 0x1D1C, 0x1D20, 0x1D21, 0, 0x028F, 0x1D22]
    /// Capital A of each Mathematical Alphanumeric style; lowercase follows 26 later.
    private static let mathStyles: [UInt32] = [
        0x1D400, 0x1D434, 0x1D468, // bold, italic, bold italic
        0x1D49C, 0x1D4D0, 0x1D504, 0x1D538, // script, bold script, fraktur, double-struck
        0x1D5D4, 0x1D670 // sans-serif bold, monospace
    ]
    /// Letters encoded earlier in Letterlike Symbols leave holes in those styles.
    private static let mathHoles: [UInt32: UInt32] = [
        0x1D455: 0x210E,
        0x1D49D: 0x212C, 0x1D4A0: 0x2130, 0x1D4A1: 0x2131, 0x1D4A3: 0x210B, 0x1D4A4: 0x2110,
        0x1D4A7: 0x2112, 0x1D4A8: 0x2133, 0x1D4AD: 0x211B, 0x1D4BA: 0x212F, 0x1D4BC: 0x210A, 0x1D4C4: 0x2134,
        0x1D506: 0x212D, 0x1D50B: 0x210C, 0x1D50C: 0x2111, 0x1D515: 0x211C, 0x1D51D: 0x2128,
        0x1D53A: 0x2102, 0x1D53F: 0x210D, 0x1D545: 0x2115, 0x1D547: 0x2119, 0x1D548: 0x211A,
        0x1D549: 0x211D, 0x1D551: 0x2124
    ]

    static func letterForms(_ index: Int, uppercase: Bool) -> [String] {
        guard (0..<26).contains(index) else { return [] }
        let offset = UInt32(index) + (uppercase ? 0 : 26)
        let math = mathStyles.map { base in mathHoles[base + offset] ?? base + offset }
        let letter = UInt32(index)
        if uppercase {
            return scalars([superscriptUpper[index]] + math + [0x24B6 + letter, 0xFF21 + letter])
        }
        return scalars([superscriptLower[index], subscriptLower[index]] + math
            + [0x24D0 + letter, 0x249C + letter, 0xFF41 + letter, smallCapitals[index]])
    }

    static func digitForms(_ digit: Int) -> [String] {
        guard (0...9).contains(digit) else { return [] }
        let d = UInt32(digit)
        let superscript: UInt32 = digit < 4 ? [0x2070, 0x00B9, 0x00B2, 0x00B3][digit] : 0x2070 + d
        return scalars([superscript, 0x2080 + d, 0x1D7CE + d, 0x1D7D8 + d, 0x1D7EC + d, 0x1D7F6 + d,
            digit == 0 ? 0x24EA : 0x245F + d, digit == 0 ? 0x24FF : 0x2775 + d,
            digit == 0 ? 0 : 0x2473 + d, digit == 0 ? 0 : 0x2487 + d, 0xFF10 + d])
    }

    private static let symbolForms: [String: [String]] = [
        "+": ["⁺", "₊", "＋"], "-": ["⁻", "₋", "－"], "=": ["⁼", "₌", "＝"],
        "(": ["⁽", "₍", "（"], ")": ["⁾", "₎", "）"]
    ]

    static func defaultSwipeUp(for key: String, state: KeyboardTypingState, widePad: Bool, ansiPad: Bool = false,
                                 mapping: KeyboardPadSymbolMapping = .iPad, hasNumberRow: Bool = false) -> [String] {
        guard (widePad || hasNumberRow), state.layout == .letters, (!widePad || mapping != .none) else { return [] }
        if hasNumberRow, let index = KeyboardTypingLayout.letters.rows[0].firstIndex(of: key) {
            let symbols = KeyboardTypingLayoutPolicy.rows(for: .numbers, hasAuxiliaryRow: true)[0]
            guard symbols.indices.contains(index) else { return [] }
            let text = symbols[index]
            // A letter's secondary legend is one mapped symbol. Expanding the
            // currency family here made U/I/O display the same chooser; those
            // families remain available by holding the actual symbol keys.
            return [text]
        }
        guard widePad else { return [] }
        if mapping == .macOS { return macOSOptionCandidates(for: key) }
        if ansiPad, let text = KeyboardTypingLayoutPolicy.ansiAlternateOutput(for: key, state: state) {
            return options(text: text, variants: stockVariants(for: text))
        }
        if mapping == .standard, let text = standardPadSymbols[key] {
            return options(text: text, variants: stockVariants(for: text))
        }
        let keys = Array("qwertyuiopasdfghjklzxcvbnm,.").map(String.init)
        let values = Array("1234567890@#¥&*()'\"%-+=/;:!?").map(String.init)
        guard let index = keys.firstIndex(of: key) else { return [] }
        let text = values[index]
        return options(text: text, variants: stockVariants(for: text))
    }

    struct GestureCandidates {
        let longPress: [String]
        let swipeUp: [String]
        let swipeDown: [String]
    }

    /// Resolve the three independent choosers together. Explicit settings win,
    /// followed by each default's primary action, then unused alternatives.
    /// Persistence is untouched; exact Unicode spellings remain distinct.
    static func gestureCandidates(for key: String, original: String, state: KeyboardTypingState,
                                  isAuxiliaryKey: Bool, widePad: Bool, ansiPad: Bool,
                                  mapping: KeyboardPadSymbolMapping, hasNumberRow: Bool,
                                  settings: KeyboardKeySettings.Snapshot) -> GestureCandidates {
        let keyID = KeyboardKeySettings.identifier(forCharacter: key) ?? ""
        let gestures: [KeyboardKeySettings.Gesture] = [.longPress, .swipeUp, .swipeDown]
        let defaults = [
            options(text: original, variants: englishVariants(for: key, uppercase: state.shift != .lowercase)),
            mapping == .none ? [] : candidates(override: nil, defaults:
                defaultSwipeUp(for: key, state: state, widePad: widePad || !isAuxiliaryKey, ansiPad: ansiPad,
                                 mapping: mapping, hasNumberRow: hasNumberRow)
                + macOSOptionCandidates(for: key)),
            defaultSwipeDown(for: key, state: state)
        ]
        let overrides = gestures.map { settings.candidates(for: keyID, gesture: $0) }
        var choices = zip(overrides, defaults).map { candidates(override: $0.0, defaults: $0.1) }
        if KeyboardKeySettings.descriptor(for: keyID)?.kind != .letter, overrides[1] == nil {
            // Currency/punctuation keys keep their complete stock hold family.
            // A default Option output already in that family is not a second
            // action on Up. Explicit Up mappings still take priority.
            let held = choices[0]
            choices[1].removeAll { contains($0, in: held) }
        }
        var seen = Set<[UInt16]>()
        var result = [[String]](repeating: [], count: 3)
        func append(_ text: String, to index: Int) {
            if seen.insert(Array(text.utf16)).inserted { result[index].append(text) }
        }
        for index in gestures.indices where overrides[index] != nil {
            for text in choices[index] { append(text, to: index) }
        }
        for index in [2, 1, 0] where overrides[index] == nil {
            if let first = choices[index].first { append(first, to: index) }
        }
        // Preserve chooser ownership: current-case hold, Down's presentation
        // forms, then symbol Up alternatives.
        for index in [0, 2, 1] where overrides[index] == nil {
            for text in choices[index].dropFirst() { append(text, to: index) }
        }
        return GestureCandidates(longPress: result[0], swipeUp: result[1], swipeDown: result[2])
    }

    /// A key's built-in candidates for one gesture, as the iPhone keyboard
    /// offers them in lowercase: letters from the letter page, digits from the
    /// number row (or the 123 page without it), and symbols from the first
    /// page that has them.
    static func defaultCandidates(for keyID: String, gesture: KeyboardKeySettings.Gesture,
                                  mapping: KeyboardPadSymbolMapping, hasNumberRow: Bool = true) -> [String] {
        guard let descriptor = KeyboardKeySettings.descriptor(for: keyID), let key = descriptor.text else { return [] }
        var state = KeyboardTypingState()
        if descriptor.kind == .character,
           let layout = KeyboardTypingLayout.allCases.first(where: { $0.rows.flatMap { $0 }.contains(key) }) {
            state.selectLayout(layout)
        }
        let auxiliary = descriptor.kind == .digit && hasNumberRow
        if descriptor.kind == .digit && !hasNumberRow { state.selectLayout(.numbers) }
        let groups = gestureCandidates(for: key, original: key, state: state, isAuxiliaryKey: auxiliary,
                                       widePad: false, ansiPad: false, mapping: mapping,
                                       hasNumberRow: hasNumberRow && state.layout == .letters, settings: .defaults)
        switch gesture {
        case .longPress: return groups.longPress
        case .swipeUp: return groups.swipeUp
        case .swipeDown: return groups.swipeDown
        case .tap, .shiftedTap: return []
        }
    }

    static func candidates(override: [String]?, defaults: [String]) -> [String] {
        let values = override ?? defaults
        let limit = override == nil ? maximumVariants + 1 : maximumVariants
        var seen = Set<[UInt16]>()
        return values.prefix(limit).filter { validText($0) && seen.insert(Array($0.utf16)).inserted }
    }

    /// Direction is chosen once, before horizontal choice selection begins.
    static func swipeDirection(delta: CGPoint) -> KeyboardKeySettings.Gesture? {
        guard delta.x.isFinite, delta.y.isFinite, abs(delta.y) >= swipeThreshold,
              abs(delta.y) > abs(delta.x) else { return nil }
        return delta.y < 0 ? .swipeUp : .swipeDown
    }

    static func horizontalChoice(deltaX: CGFloat, count: Int,
                                 stride: CGFloat = horizontalChoiceStride) -> Int? {
        guard deltaX.isFinite, stride.isFinite, stride > 0, count > 0, count <= maximumVariants + 1 else { return nil }
        let offset = (deltaX / stride).rounded(.toNearestOrAwayFromZero)
        guard offset.isFinite else { return nil }
        let primary = (count - 1) / 2
        let position = Int(min(CGFloat(count - 1), max(0, CGFloat(primary) + offset)))
        return centerOutIndices(count: count)[position]
    }

    /// Logical choice zero stays in the middle. Subsequent choices alternate
    /// right and left: seven choices read 7, 5, 3, 1, 2, 4, 6 on screen.
    static func centerOutIndices(count: Int) -> [Int] {
        guard (1...19).contains(count) else { return [] }
        return Array((0..<count).filter { $0.isMultiple(of: 2) }.reversed())
            + (0..<count).filter { !$0.isMultiple(of: 2) }
    }

    static func validText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.prefix(maximumScalars + 1).count <= maximumScalars
    }

    static func options(text: String, variants: [String]) -> [String] {
        guard validText(text) else { return [] }
        var seen: Set<[UInt16]> = [Array(text.utf16)]
        var result = [text]
        for variant in variants.prefix(maximumVariants) where validText(variant) {
            if seen.insert(Array(variant.utf16)).inserted { result.append(variant) }
        }
        return result
    }

    static func contains(_ text: String, in options: [String]) -> Bool {
        options.contains { $0.utf16.elementsEqual(text.utf16) }
    }

    /// Familiar English diacritics; these are literal choices, not corrections.
    static func englishVariants(for key: String, uppercase: Bool) -> [String] {
        let choices: [String]
        switch key {
        case "a": choices = ["à", "á", "â", "ä", "æ", "ã", "å", "ā"]
        case "e": choices = ["è", "é", "ê", "ë", "ē", "ė", "ę"]
        case "i": choices = ["ì", "í", "î", "ï", "ī", "į"]
        case "o": choices = ["ò", "ó", "ô", "ö", "œ", "õ", "ø", "ō"]
        case "u": choices = ["ù", "ú", "û", "ü", "ū"]
        case "c": choices = ["ç", "ć", "č"]
        case "n": choices = ["ñ", "ń"]
        case "s": choices = ["ß", "ś", "š"]
        case "y": choices = ["ÿ", "ý"]
        case "l": choices = ["ł"]
        case "z": choices = ["ž", "ź", "ż"]
        case "d": choices = ["ð", "đ"]
        case "t": choices = ["þ"]
        default: return stockVariants(for: key)
        }
        return uppercase ? choices.map { $0 == "ß" ? "ẞ" : $0.uppercased() } : choices
    }

    static func stockVariants(for text: String) -> [String] {
        let family: [String]
        switch text {
        case "$", "€", "£", "¥", "₩", "₹", "¢", "₽", "₺", "₫", "฿":
            family = ["$", "¢", "€", "£", "¥", "₩", "₹", "₽", "₺", "₫", "฿"]
        case "-", "–", "—", "−", "‑": family = ["-", "–", "—", "−", "‑"]
        case "\"", "“", "”", "„", "«", "»": family = ["\"", "“", "”", "„", "«", "»"]
        case "'", "‘", "’", "‚", "‹", "›": family = ["'", "‘", "’", "‚", "‹", "›"]
        case "=", "≠", "≈", "≡": family = ["=", "≠", "≈", "≡"]
        case "+", "±", "∓": family = ["+", "±", "∓"]
        case "*", "×", "⋅": family = ["*", "×", "⋅"]
        case "/", "÷", "\\": family = ["/", "÷", "\\"]
        case "<", "≤", "≪": family = ["<", "≤", "≪"]
        case ">", "≥", "≫": family = [">", "≥", "≫"]
        case ".", "…", "·", "•": family = [".", "…", "·", "•"]
        case "?", "¿": family = ["?", "¿"]
        case "!", "¡": family = ["!", "¡"]
        case "%", "‰", "‱": family = ["%", "‰", "‱"]
        case "0": family = ["0", "°", "º"]
        default: return []
        }
        return family.filter { !$0.utf16.elementsEqual(text.utf16) }
    }
}

/// Popup geometry is contained within the keyboard root, including at its top
/// edge and on narrow layouts. No keyboard/window resize is needed to show it.
struct KeyboardVariantPopupLayout {
    let frame: CGRect
    let cells: [CGRect]

    init?(anchor: CGRect, container: CGRect, count: Int, choiceCount: Int? = nil) {
        let values = [anchor.minX, anchor.minY, anchor.width, anchor.height,
                      container.origin.x, container.origin.y, container.width, container.height]
        guard values.allSatisfy({ $0.isFinite }), anchor.width > 0, anchor.height > 0,
              container.width >= 24, container.height >= 24,
              (container.origin.x + container.width).isFinite,
              (container.origin.y + container.height).isFinite, count > 0, count <= 19 else { return nil }
        let choices = choiceCount ?? count
        guard (1...count).contains(choices) else { return nil }
        let inset: CGFloat = 4
        let width = container.width - inset * 2
        let height = container.height - inset * 2
        let gap: CGFloat = 6
        let minX = container.origin.x + inset, minY = container.origin.y + inset
        let maxY = container.origin.y + container.height - inset
        let aboveSpace = min(height, max(0, anchor.minY - gap - minY))
        let belowSpace = min(height, max(0, maxY - anchor.maxY - gap))
        let available = max(aboveSpace, belowSpace)
        var columns = min(count, max(1, Int(min(19, (width / 42).rounded(.down)))))
        let maximumColumns = min(count, max(1, Int(min(19, (width / 24).rounded(.down)))))
        var rows = (count + columns - 1) / columns
        while CGFloat(rows) * 24 > available && columns < maximumColumns {
            columns += 1
            rows = (count + columns - 1) / columns
        }
        guard width / CGFloat(columns) >= 24, available >= CGFloat(rows) * 24 else { return nil }
        let idealHeight = CGFloat(rows) * 48
        let useAbove = aboveSpace >= idealHeight || (belowSpace < idealHeight && aboveSpace >= belowSpace)
        let sideHeight = useAbove ? aboveSpace : belowSpace
        let cellWidth = min(48, width / CGFloat(columns))
        let cellHeight = min(48, sideHeight / CGFloat(rows))
        let popupWidth = cellWidth * CGFloat(columns)
        let popupHeight = cellHeight * CGFloat(rows)
        let primaryColumn = (min(choices, columns) - 1) / 2
        let x = min(container.origin.x + container.width - inset - popupWidth,
                    max(minX, anchor.midX - (CGFloat(primaryColumn) + 0.5) * cellWidth))
        let desiredY = useAbove ? anchor.minY - gap - popupHeight : anchor.maxY + gap
        let y = min(container.origin.y + container.height - inset - popupHeight, max(minY, desiredY))
        guard [x, y, popupWidth, popupHeight, cellWidth, cellHeight].allSatisfy({ $0.isFinite }),
              cellWidth >= 24, cellHeight >= 24,
              y + popupHeight <= anchor.minY - gap || y >= anchor.maxY + gap else { return nil }
        frame = CGRect(x: x, y: y, width: popupWidth, height: popupHeight)
        var order: [Int] = []
        for start in stride(from: 0, to: choices, by: columns) {
            order += KeyboardVariantPolicy.centerOutIndices(count: min(columns, choices - start)).map { start + $0 }
        }
        order += choices..<count // Inspect/Edit retain their logical trailing slots.
        var arranged = Array(repeating: CGRect.zero, count: count)
        for (position, logicalIndex) in order.enumerated() {
            arranged[logicalIndex] = CGRect(x: CGFloat(position % columns) * cellWidth,
                y: CGFloat(position / columns) * cellHeight, width: cellWidth, height: cellHeight)
        }
        cells = arranged
    }

    func index(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return cells.firstIndex { cell in
            point.x >= cell.minX && point.x <= cell.maxX && point.y >= cell.minY && point.y <= cell.maxY
        }
    }
}
