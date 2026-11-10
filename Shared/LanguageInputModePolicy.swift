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

/// Why an enabled language isn't ready in the keyboard. Only `.unreadable`
/// (no permission, or no shared container) is shown to the person; missing,
/// damaged and mismatched downloads keep their existing handling.
enum LanguageModeUnavailability: Equatable, Sendable {
    /// The shared container or the language's files can't be read.
    case unreadable
    /// Not downloaded (no store, or no active download for this mode).
    case missing
    /// Corrupt or built for another engine version.
    case damaged
    /// Installed, but not the pinned version in the settings.
    case mismatched
}

/// Pure keyboard decisions for the space-bar list and the remembered mode.
enum LanguageInputChoicePolicy {
    /// Space-bar choices: Direct Typing, then every enabled mode that's ready OR
    /// enabled but unreadable (it stays, and explains itself when chosen).
    /// Modes turned off in Use in Keyboard and Romaja are never offered.
    static func choices(enabled: LanguageInputSettings.Value, ready: [LanguageInputMode],
                        unavailable: [LanguageInputMode: LanguageModeUnavailability]) -> [LanguageInputMode] {
        var result: [LanguageInputMode] = [.direct]
        for mode in LanguageInputSettings.modeOrder where mode != .direct && mode != .koreanRomaja && enabled.isEnabled(mode) {
            if ready.contains(mode) || unavailable[mode] == .unreadable { result.append(mode) }
        }
        return result
    }

    enum RememberedDecision: Equatable, Sendable {
        /// The stored value was already handled.
        case none
        /// Already in the stored mode; just record that it was seen.
        case adopt
        /// Switch through the normal selection path.
        case switchTo(LanguageInputMode)
        /// Not now (unfinished text, a conversion in progress, or the mode isn't
        /// offered). Keep the stored value and try again on a later refresh.
        case wait
    }

    /// Run on each keyboard refresh. `stored` is nil when it couldn't be read.
    /// `lastSeen` is the stored value this keyboard last applied, wrote, or saw
    /// when its own write failed, so a choice the keyboard couldn't save isn't
    /// undone by an older value. Never switches over unfinished text, a running
    /// conversion or a pending write (`isBusy`), nor once the person has typed
    /// since the keyboard appeared. Without Full Access it never switches INTO a
    /// language: the keyboard couldn't open it and couldn't save Direct Typing
    /// either, so every opening would show the Full Access panel again. The
    /// language stays in the space-bar list for a deliberate choice.
    static func rememberedDecision(stored: LanguageInputMode?, lastSeen: LanguageInputMode?,
                                   current: LanguageInputMode, choices: [LanguageInputMode],
                                   hasComposition: Bool, isBusy: Bool,
                                   hasTypedSinceAppear: Bool = false,
                                   hasFullAccess: Bool = true) -> RememberedDecision {
        guard let stored, stored != lastSeen else { return .none }
        if stored == current { return .adopt }
        guard !hasComposition, !isBusy, !hasTypedSinceAppear else { return .wait }
        guard stored != .koreanRomaja, stored == .direct || choices.contains(stored) else { return .wait }
        guard stored == .direct || hasFullAccess else { return .wait }
        return .switchTo(stored)
    }

    /// `lastSeen` after the person picks `chosen` in the keyboard. A saved
    /// choice is what's stored now. If saving failed (no Full Access, or an I/O
    /// error), the value that IS stored counts as seen, so this keyboard keeps
    /// the person's in-session choice instead of switching back to it.
    static func lastSeenAfterChoice(_ chosen: LanguageInputMode, saved: Bool,
                                    storedBefore: LanguageInputMode?, previous: LanguageInputMode?) -> LanguageInputMode? {
        saved ? chosen : (storedBefore ?? previous)
    }

    /// A layout (alphabet) change within Direct Typing is not a language choice:
    /// it must not overwrite a pending app choice. Only a real mode change writes.
    static func choiceShouldBeStored(_ chosen: LanguageInputMode, previous: LanguageInputMode) -> Bool {
        chosen != .koreanRomaja && chosen != previous
    }

    /// App: when it drops `dropped` (turned off, removed, no longer ready), it
    /// stores Direct Typing only if that mode is what's stored, never over a
    /// newer keyboard choice of a different mode.
    static func appShouldStoreDirect(stored: LanguageInputMode?, dropped: LanguageInputMode) -> Bool {
        dropped != .direct && stored == dropped
    }
}

/// What the keyboard's recovery panel says when an enabled language can't be
/// read. Picked by what the keyboard actually knows: its Full Access state.
enum LanguageUnreadableNotice: Equatable, Sendable {
    case fullAccessRequired
    case couldNotLoad

    /// nil for Direct Typing, Romaja, and any reason other than unreadable
    /// (a download that's simply missing keeps "Download required…").
    static func state(for mode: LanguageInputMode, unavailable: LanguageModeUnavailability?,
                      hasFullAccess: Bool) -> LanguageUnreadableNotice? {
        guard mode != .direct, mode != .koreanRomaja, unavailable == .unreadable else { return nil }
        return hasFullAccess ? .couldNotLoad : .fullAccessRequired
    }

    /// `language` is the keyboard's own picker label (日本語, 拼音, Two-Set Hangul).
    func title(language: String) -> String {
        switch self {
        case .fullAccessRequired: return LanguageUnreadableCopy.fullAccessTitle
        case .couldNotLoad: return LanguageUnreadableCopy.couldNotLoadTitle(language)
        }
    }

    func body(language: String) -> String {
        switch self {
        case .fullAccessRequired: return LanguageUnreadableCopy.fullAccessBody(language)
        case .couldNotLoad: return LanguageUnreadableCopy.couldNotLoadBody(language)
        }
    }

    /// One line: the VoiceOver hint for the space-bar choice.
    func compact(language: String) -> String {
        switch self {
        case .fullAccessRequired: return LanguageUnreadableCopy.fullAccessCompact(language)
        case .couldNotLoad: return LanguageUnreadableCopy.couldNotLoadCompact(language)
        }
    }

    /// The VoiceOver value for the space-bar choice.
    var accessibilityValue: String {
        switch self {
        case .fullAccessRequired: return LanguageUnreadableCopy.fullAccessValue
        case .couldNotLoad: return LanguageUnreadableCopy.couldNotLoadValue
        }
    }
}

/// Every string for an enabled language the keyboard can't read, in one place.
/// No error codes, paths, "container" or "App Group". Lists use ListFormatter.
enum LanguageUnreadableCopy {
    // COPY: Camo — Full Access is off.
    static let fullAccessTitle = "Full Access required"
    static func fullAccessBody(_ language: String) -> String {
        "\(language) needs Full Access. Allow Full Access for Uniboard in your keyboard settings to use it. Direct Typing is still available."
    }
    static func fullAccessBody(languages: [String]) -> String {
        "\(list(languages)) need Full Access. Allow Full Access for Uniboard in your keyboard settings to use them. Direct Typing is still available."
    }
    static func fullAccessCompact(_ language: String) -> String { "Allow Full Access to use \(language)." }
    static let fullAccessCompactSeveral = "Allow Full Access to use downloaded languages."

    // COPY: Camo — Full Access is on, but the files still can't be read.
    static func couldNotLoadTitle(_ language: String) -> String { "Couldn’t load \(language)" }
    static let couldNotLoadTitleSeveral = "Couldn’t load your languages"
    static func couldNotLoadBody(_ language: String) -> String {
        "The keyboard couldn’t read \(language) from Uniboard. Open Uniboard to check it in Languages. Direct Typing is still available."
    }
    static func couldNotLoadBody(languages: [String]) -> String {
        "The keyboard couldn’t read \(list(languages)) from Uniboard. Open Uniboard to check them in Languages. Direct Typing is still available."
    }
    static func couldNotLoadCompact(_ language: String) -> String { "Couldn’t load \(language). Open Uniboard to check it." }
    static let couldNotLoadCompactSeveral = "Couldn’t load some languages. Open Uniboard to check them."

    // COPY: Camo — VoiceOver values for the space-bar choice (from the design spec).
    static let fullAccessValue = "Needs Full Access"
    static let couldNotLoadValue = "Couldn’t load"

    /// The system's list formatting, never hand-joined.
    static func list(_ languages: [String], locale: Locale = .current) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: languages) ?? languages.first ?? ""
    }
}
