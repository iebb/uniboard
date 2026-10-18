import Foundation
import CoreGraphics

/// Exact Unicode strings are input data: canonically equivalent spellings
/// remain separate choices and are never normalized before insertion.
enum KeyboardVariantPolicy {
    static let maximumVariants = 16
    static let maximumScalars = 64
    static let swipeThreshold: CGFloat = 12
    static let horizontalChoiceStride: CGFloat = 36

    static func defaultSwipeUp(for key: String, state: KeyboardTypingState) -> [String] {
        guard state.layout == .letters, key.utf8.count == 1,
              let byte = key.utf8.first, (97...122).contains(byte) else { return [] }
        let uppercase = state.shift == .lowercase
        let original = uppercase ? key.uppercased() : key
        return options(text: original, variants: englishVariants(for: key, uppercase: uppercase))
    }

    static func defaultSwipeDown(for key: String, state: KeyboardTypingState, widePad: Bool) -> [String] {
        guard widePad, state.layout == .letters else { return [] }
        let keys = Array("qwertyuiopasdfghjklzxcvbnm,.").map(String.init)
        let values = Array("1234567890@#¥&*()'\"%-+=/;:!?").map(String.init)
        guard let index = keys.firstIndex(of: key) else { return [] }
        let text = values[index]
        return options(text: text, variants: stockVariants(for: text))
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
        return Int(min(CGFloat(count - 1), max(0, offset)))
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

    init?(anchor: CGRect, container: CGRect, count: Int) {
        let values = [anchor.minX, anchor.minY, anchor.width, anchor.height,
                      container.origin.x, container.origin.y, container.width, container.height]
        guard values.allSatisfy({ $0.isFinite }), anchor.width > 0, anchor.height > 0,
              container.width >= 24, container.height >= 24,
              (container.origin.x + container.width).isFinite,
              (container.origin.y + container.height).isFinite, count > 0, count <= 19 else { return nil }
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
        let x = min(container.origin.x + container.width - inset - popupWidth,
                    max(minX, anchor.midX - popupWidth / 2))
        let desiredY = useAbove ? anchor.minY - gap - popupHeight : anchor.maxY + gap
        let y = min(container.origin.y + container.height - inset - popupHeight, max(minY, desiredY))
        guard [x, y, popupWidth, popupHeight, cellWidth, cellHeight].allSatisfy({ $0.isFinite }),
              cellWidth >= 24, cellHeight >= 24,
              y + popupHeight <= anchor.minY - gap || y >= anchor.maxY + gap else { return nil }
        frame = CGRect(x: x, y: y, width: popupWidth, height: popupHeight)
        cells = (0..<count).map { index in
            CGRect(x: CGFloat(index % columns) * cellWidth, y: CGFloat(index / columns) * cellHeight,
                   width: cellWidth, height: cellHeight)
        }
    }

    func index(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return cells.firstIndex { cell in
            point.x >= cell.minX && point.x <= cell.maxX && point.y >= cell.minY && point.y <= cell.maxY
        }
    }
}
