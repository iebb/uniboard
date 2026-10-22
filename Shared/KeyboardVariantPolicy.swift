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

    static func defaultSwipeDown(for key: String, state: KeyboardTypingState) -> [String] {
        guard state.layout == .letters, key.utf8.count == 1,
              let byte = key.utf8.first, (97...122).contains(byte) else { return [] }
        let uppercase = state.shift == .lowercase
        let original = uppercase ? key.uppercased() : key
        return options(text: original, variants: englishVariants(for: key, uppercase: uppercase))
    }

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
            isAuxiliaryKey ? [] : defaultSwipeDown(for: key, state: state)
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
        // Preserve chooser ownership when swapping the default directions:
        // current-case hold, opposite-case Down, then symbol Up alternatives.
        for index in [0, 2, 1] where overrides[index] == nil {
            for text in choices[index].dropFirst() { append(text, to: index) }
        }
        return GestureCandidates(longPress: result[0], swipeUp: result[1], swipeDown: result[2])
    }

    /// A key's built-in candidates for one gesture, as the iPhone keyboard
    /// offers them in lowercase with the number row: letters from the letter
    /// page, digits from the number row, and symbols from the first page that
    /// has them.
    static func defaultCandidates(for keyID: String, gesture: KeyboardKeySettings.Gesture,
                                  mapping: KeyboardPadSymbolMapping) -> [String] {
        guard let descriptor = KeyboardKeySettings.descriptor(for: keyID), let key = descriptor.text else { return [] }
        var state = KeyboardTypingState()
        if descriptor.kind == .character,
           let layout = KeyboardTypingLayout.allCases.first(where: { $0.rows.flatMap { $0 }.contains(key) }) {
            state.selectLayout(layout)
        }
        let auxiliary = descriptor.kind == .digit
        let groups = gestureCandidates(for: key, original: key, state: state, isAuxiliaryKey: auxiliary,
                                       widePad: false, ansiPad: false, mapping: mapping,
                                       hasNumberRow: state.layout == .letters, settings: .defaults)
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
