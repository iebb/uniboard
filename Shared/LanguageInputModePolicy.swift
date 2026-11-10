import Foundation

/// Runtime capabilities are independent of persisted identities and enablement.
/// Romaja remains a round-trippable identity, not an implemented grammar.
public extension LanguageInputMode {
    var conversionEngineABI: String? {
        switch self {
        case .japaneseRomaji: return "azookey-80b8204f1cdfb364bb2ed355cf52c7ebb2519a0c"
        case .mandarinPinyin: return "uniboard-pinyin-1"
        case .koreanTwoSetHangul: return "uniboard-hangul-1"
        case .direct, .koreanRomaja: return nil
        }
    }
    var supportsConversionMyWords: Bool { self == .japaneseRomaji || self == .mandarinPinyin }
    var offersLiteralConversion: Bool { self != .koreanTwoSetHangul }
    var conversionSpaceSuffix: String { self == .koreanTwoSetHangul ? " " : "" }
}

/// Presentation/physical-key policy only. These labels NEVER compose text.
/// The conversion adapter requires authenticated downloaded mapping data.
public enum KoreanTwoSetKeyboard {
    public static let rows = [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")].map { $0.map(String.init) }
    private static let lower = Array("ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡ").map(String.init)
    private static let shifted = ["q": "ㅃ", "w": "ㅉ", "e": "ㄸ", "r": "ㄲ", "t": "ㅆ", "o": "ㅒ", "p": "ㅖ"]
    private static let names = ["ㄱ":"기역", "ㄲ":"쌍기역", "ㄴ":"니은", "ㄷ":"디귿", "ㄸ":"쌍디귿", "ㄹ":"리을", "ㅁ":"미음", "ㅂ":"비읍", "ㅃ":"쌍비읍", "ㅅ":"시옷", "ㅆ":"쌍시옷", "ㅇ":"이응", "ㅈ":"지읒", "ㅉ":"쌍지읒", "ㅊ":"치읓", "ㅋ":"키읔", "ㅌ":"티읕", "ㅍ":"피읖", "ㅎ":"히읗", "ㅏ":"아", "ㅐ":"애", "ㅑ":"야", "ㅒ":"얘", "ㅓ":"어", "ㅔ":"에", "ㅕ":"여", "ㅖ":"예", "ㅗ":"오", "ㅛ":"요", "ㅜ":"우", "ㅠ":"유", "ㅡ":"으", "ㅣ":"이"]
    public static func accepts(_ raw: String) -> Bool {
        !raw.isEmpty && raw.unicodeScalars.prefix(257).count <= 256
            && raw.unicodeScalars.allSatisfy { (65...90).contains($0.value) || (97...122).contains($0.value) }
    }
    public static func keyID(_ key: String, shifted: Bool) -> String {
        shifted ? key.uppercased() : key.lowercased()
    }
    public static func label(for keyID: String) -> String? {
        let key = keyID.lowercased()
        guard keyID.utf8.count == 1, let index = rows.flatMap({ $0 }).firstIndex(of: key) else { return nil }
        if keyID != key, let label = shifted[key] { return label }
        return lower[index]
    }
    public static func shiftedVariant(for key: String) -> String? { shifted[key.lowercased()] }
    public static func accessibleName(for label: String) -> String { names[label] ?? label }
}

/// A held jamo owns its touch-down raw key ID, not the current Shift state.
/// Context includes the controller's document/interaction/rendered-mode guard.
extension KoreanTwoSetKeyboard {
    static func acceptsHeldKey(contextIsCurrent: Bool, mode: LanguageInputMode,
                               captured: KeyboardTypingState, current: KeyboardTypingState) -> Bool {
        contextIsCurrent && mode == .koreanTwoSetHangul
            && captured.layout == current.layout
            && captured.alphabet.id == current.alphabet.id
            && captured.alphabet.rows == current.alphabet.rows
    }
}
