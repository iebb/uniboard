import Foundation

/// Pure, bounded matching of local language hints. Neither hints nor suggestions
/// are settings: never persist, export, log, or transmit them.
public enum LanguageSuggestionPolicy {
    public static let maximumHintsPerSource = 64
    public static let maximumIdentifierBytes = 128

    /// Language-level identity, deliberately independent of input methods,
    /// installation, enablement, or the currently visible download catalog.
    public enum Language: String, CaseIterable, Equatable, Sendable {
        case japanese, mandarin, korean
    }

    public enum Provenance: Equatable, Sendable {
        case activeKeyboard, preferredLanguage
    }

    public struct Suggestion: Equatable, Sendable {
        public let language: Language
        public let provenance: Provenance
    }

    /// Only normalized language/script/region are retained, not keyboard identity
    /// or raw identifiers. General language codes can also support layout matching.
    public struct LanguageHint: Equatable, Hashable, Sendable {
        public let languageCode: String
        public let scriptCode: String?
        public let regionCode: String?
    }

    /// A screen-local value. Intentionally not Codable and not a shared singleton.
    public struct Snapshot: Equatable, Sendable {
        public let activeLanguages: [LanguageHint]
        public let preferredLanguages: [LanguageHint]
        public let suggestions: [Suggestion]

        public static let empty = Snapshot(activeLanguages: [], preferredLanguages: [], suggestions: [])
    }

    public static func suggestions(activeKeyboardLanguages: [String?],
                                   preferredLanguages: [String]) -> [Suggestion] {
        snapshot(activeKeyboardLanguages: activeKeyboardLanguages,
                 preferredLanguages: preferredLanguages).suggestions
    }

    public static func snapshot(activeKeyboardLanguages: [String?],
                                preferredLanguages: [String]) -> Snapshot {
        let active = normalizedHints(activeKeyboardLanguages.prefix(maximumHintsPerSource))
        let preferred = normalizedHints(preferredLanguages.prefix(maximumHintsPerSource).map { Optional($0) })
        let activeMatches = Set(active.compactMap(suggestedLanguage))
        var seen = Set<Language>()
        var result: [Suggestion] = []

        // Active input modes are not an ordered language preference. Rank that
        // tier by catalog order, independent of the system's enumeration order.
        for language in Language.allCases where activeMatches.contains(language) {
            seen.insert(language)
            result.append(Suggestion(language: language, provenance: .activeKeyboard))
        }
        // Preserve the person's preferred-language order within the weaker tier.
        for hint in preferred {
            guard let language = suggestedLanguage(hint), seen.insert(language).inserted else { continue }
            result.append(Suggestion(language: language, provenance: .preferredLanguage))
        }
        return Snapshot(activeLanguages: active, preferredLanguages: preferred, suggestions: result)
    }

    private static func suggestedLanguage(_ hint: LanguageHint) -> Language? {
        switch hint.languageCode {
        case "ja": return .japanese
        case "ko": return .korean // Never infer romaja versus two-set Hangul.
        case "zh":
            // Explicit script wins over region, including contradictory regions.
            if let script = hint.scriptCode { return script == "Hans" ? .mandarin : nil }
            return hint.regionCode == "CN" || hint.regionCode == "SG" ? .mandarin : nil
        default: return nil
        }
    }

    private static func normalizedHints<S: Sequence>(_ identifiers: S) -> [LanguageHint]
        where S.Element == String? {
        var seen = Set<LanguageHint>()
        var result: [LanguageHint] = []
        for identifier in identifiers {
            guard let identifier, let hint = normalize(identifier), seen.insert(hint).inserted else { continue }
            result.append(hint)
        }
        return result
    }

    /// Conservative BCP-47 core parser, also accepting Apple's underscore form.
    /// Validate suffixes but never mine a variant/extension for script evidence.
    private static func normalize(_ identifier: String) -> LanguageHint? {
        // Read at most limit+1 bytes even for a hostile very large string.
        let bytes = Array(identifier.utf8.prefix(maximumIdentifierBytes + 1))
        guard !bytes.isEmpty, bytes.count <= maximumIdentifierBytes,
              bytes.allSatisfy({ isAlpha($0) || isDigit($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let components = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let first = components.first, (2...3).contains(first.utf8.count),
              first.utf8.allSatisfy(isAlpha), !components.contains("") else { return nil }
        let language = first.lowercased()
        guard !["und", "mul", "zxx"].contains(language) else { return nil }
        var index = 1
        var script: String?
        var region: String?
        if index < components.count, components[index].utf8.count == 4,
           components[index].utf8.allSatisfy(isAlpha) {
            let lower = components[index].lowercased()
            script = lower.prefix(1).uppercased() + lower.dropFirst()
            index += 1
        }
        if index < components.count {
            let part = components[index]
            if (part.utf8.count == 2 && part.utf8.allSatisfy(isAlpha))
                || (part.utf8.count == 3 && part.utf8.allSatisfy(isDigit)) {
                region = part.uppercased()
                index += 1
            }
        }
        var variants = Set<String>()
        while index < components.count, components[index].utf8.count > 1 {
            let part = components[index].lowercased()
            let size = part.utf8.count
            guard (5...8).contains(size) || (size == 4 && part.utf8.first.map(isDigit) == true),
                  variants.insert(part).inserted else { return nil }
            index += 1
        }
        var extensions = Set<String>()
        while index < components.count {
            let singleton = components[index].lowercased()
            guard singleton.utf8.count == 1, extensions.insert(singleton).inserted else { return nil }
            index += 1
            let start = index
            let minimum = singleton == "x" ? 1 : 2
            while index < components.count, (minimum...8).contains(components[index].utf8.count) {
                index += 1
            }
            guard index > start else { return nil }
            if singleton == "x" { break }
        }
        guard index == components.count else { return nil }
        return LanguageHint(languageCode: language, scriptCode: script, regionCode: region)
    }

    private static func isAlpha(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
}
