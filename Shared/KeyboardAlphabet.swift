import Foundation

/// One base keyboard: its letter rows and the language rules for its case.
/// The digit and symbol pages are shared by every alphabet.
struct KeyboardAlphabet: Identifiable, Sendable {
    enum Script: String, CaseIterable, Sendable { case latin, greek, cyrillic }

    /// Stable identifier stored in app settings, such as "en" or "sr-Cyrl".
    let id: String
    let nativeName: String
    let englishName: String
    let script: Script
    /// The keyboard's language, also used for Turkish casing.
    let languageCode: String
    /// Three rows of lowercase keys, at most 12 each.
    let rows: [[String]]
    /// Long-press choices for lowercase keys, before any shared Latin accents.
    /// Capitals follow `uppercase(_:)`.
    var variants: [String: [String]] = [:]

    var keys: [String] { rows.flatMap { $0 } }
    var locale: Locale { Locale(identifier: languageCode) }

    /// Only Turkish dotted and dotless i need the language's rules; Greek
    /// rules would drop the accent from a capital such as Ά.
    private var casingLocale: Locale? { languageCode == "tr" ? locale : nil }
    func uppercase(_ key: String) -> String { key.uppercased(with: casingLocale) }
    func lowercase(_ key: String) -> String { key.lowercased(with: casingLocale) }
    /// A key of this alphabet whose capital differs, so Shift changes it.
    func isCasedLetter(_ key: String) -> Bool { keys.contains(key) && uppercase(key) != key }

    /// The same keys in `rows`, three rows of any length; anything else
    /// leaves the standard rows.
    func arranged(_ rows: [[String]]?) -> KeyboardAlphabet {
        guard let rows, rows.count == 3, Self.isArrangement(rows.flatMap { $0 }, of: keys) else { return self }
        return KeyboardAlphabet(id: id, nativeName: nativeName, englishName: englishName, script: script,
                                languageCode: languageCode, rows: rows, variants: variants)
    }
    /// Whether `order` holds exactly `keys`, each once.
    static func isArrangement(_ order: [String], of keys: [String]) -> Bool {
        order.count == keys.count && order.sorted() == keys.sorted() && Set(order).count == order.count
    }
}

extension KeyboardAlphabet: Equatable, Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension KeyboardAlphabet {
    private static func rows(_ rows: String...) -> [[String]] { rows.map { $0.map(String.init) } }

    static let english = KeyboardAlphabet(id: "en", nativeName: "English", englishName: "English", script: .latin,
        languageCode: "en", rows: rows("qwertyuiop", "asdfghjkl", "zxcvbnm"))

    /// Keys follow Apple's stock iOS arrangement for each language.
    static let catalog: [KeyboardAlphabet] = [
        english,
        latin("de", "Deutsch", "German", rows("qwertzuiopü", "asdfghjklöä", "yxcvbnm"),
              ["s": ["ß"], "a": ["à", "á", "â"], "e": ["é", "è", "ê"], "o": ["ó", "ò", "ô"], "u": ["ú", "ù", "û"]]),
        latin("fr", "Français", "French", rows("azertyuiop", "qsdfghjklm", "wxcvbn'"),
              ["a": ["à", "â", "æ"], "c": ["ç"], "e": ["é", "è", "ê", "ë"], "i": ["î", "ï"], "o": ["ô", "œ"],
               "u": ["ù", "û", "ü"], "y": ["ÿ"]]),
        latin("es", "Español", "Spanish", rows("qwertyuiop", "asdfghjklñ", "zxcvbnm"),
              ["a": ["á"], "e": ["é"], "i": ["í"], "o": ["ó"], "u": ["ú", "ü"]]),
        latin("it", "Italiano", "Italian", rows("qwertyuiop", "asdfghjkl", "zxcvbnm"),
              ["a": ["à"], "e": ["è", "é"], "i": ["ì", "í"], "o": ["ò", "ó"], "u": ["ù", "ú"]]),
        latin("pt", "Português", "Portuguese", rows("qwertyuiop", "asdfghjkl", "zxcvbnm"),
              ["a": ["á", "à", "â", "ã"], "c": ["ç"], "e": ["é", "ê"], "i": ["í"], "o": ["ó", "ô", "õ"], "u": ["ú", "ü"]]),
        latin("sv", "Svenska", "Swedish", rows("qwertyuiopå", "asdfghjklöä", "zxcvbnm"), ["e": ["é"]]),
        latin("fi", "Suomi", "Finnish", rows("qwertyuiopå", "asdfghjklöä", "zxcvbnm"), ["s": ["š"], "z": ["ž"]]),
        latin("nb", "Norsk", "Norwegian", rows("qwertyuiopå", "asdfghjkløæ", "zxcvbnm"), ["e": ["é"], "o": ["ò", "ó", "ô"]]),
        latin("da", "Dansk", "Danish", rows("qwertyuiopå", "asdfghjklæø", "zxcvbnm"), ["e": ["é"]]),
        latin("pl", "Polski", "Polish", rows("qwertyuiop", "asdfghjkl", "zxcvbnm"),
              ["a": ["ą"], "c": ["ć"], "e": ["ę"], "l": ["ł"], "n": ["ń"], "o": ["ó"], "s": ["ś"], "z": ["ż", "ź"]]),
        latin("cs", "Čeština", "Czech", rows("qwertzuiopú", "asdfghjklů", "yxcvbnm"),
              ["a": ["á"], "c": ["č"], "d": ["ď"], "e": ["é", "ě"], "i": ["í"], "n": ["ň"], "o": ["ó"], "r": ["ř"],
               "s": ["š"], "t": ["ť"], "u": ["ú", "ů"], "y": ["ý"], "z": ["ž"]]),
        latin("hu", "Magyar", "Hungarian", rows("qwertzuiopőú", "asdfghjkléáű", "yxcvbnmöüó"),
              ["i": ["í"], "o": ["ö", "ő", "ó"], "u": ["ü", "ű", "ú"]]),
        latin("ro", "Română", "Romanian", rows("qwertyuiopă", "asdfghjklșț", "zxcvbnm"),
              ["a": ["â", "ă"], "i": ["î"], "s": ["ș"], "t": ["ț"]]),
        latin("tr", "Türkçe", "Turkish", rows("qwertyuıopğü", "asdfghjklşi", "zxcvbnmöç"),
              ["a": ["â"], "i": ["î"], "u": ["û"]]),
        KeyboardAlphabet(id: "el", nativeName: "Ελληνικά", englishName: "Greek", script: .greek, languageCode: "el",
            rows: rows(";ςερτυθιοπ", "ασδφγηξκλ", "ζχψωβνμ"),
            variants: ["α": ["ά"], "ε": ["έ"], "η": ["ή"], "ι": ["ί", "ϊ", "ΐ"], "ο": ["ό"], "υ": ["ύ", "ϋ", "ΰ"], "ω": ["ώ"]]),
        KeyboardAlphabet(id: "ru", nativeName: "Русский", englishName: "Russian", script: .cyrillic, languageCode: "ru",
            rows: rows("йцукенгшщзх", "фывапролджэ", "ячсмитьбю"),
            variants: ["е": ["ё"], "ь": ["ъ"]]),
        KeyboardAlphabet(id: "uk", nativeName: "Українська", englishName: "Ukrainian", script: .cyrillic, languageCode: "uk",
            rows: rows("йцукенгшщзхї", "фівапролджє", "ячсмитьбю"),
            variants: ["г": ["ґ"], "ь": ["ʼ"]]),
        KeyboardAlphabet(id: "bg", nativeName: "Български", englishName: "Bulgarian", script: .cyrillic, languageCode: "bg",
            rows: rows("явертъуиопч", "асдфгхйклшщ", "зьцжбнмю"),
            variants: ["и": ["ѝ"]]),
        KeyboardAlphabet(id: "sr-Cyrl", nativeName: "Српски", englishName: "Serbian (Cyrillic)", script: .cyrillic, languageCode: "sr",
            rows: rows("љњертзуиопш", "асдфгхјклчћ", "ѕџцвбнмђж"))
    ]

    private static func latin(_ id: String, _ nativeName: String, _ englishName: String, _ rows: [[String]],
                              _ variants: [String: [String]]) -> KeyboardAlphabet {
        KeyboardAlphabet(id: id, nativeName: nativeName, englishName: englishName, script: .latin,
                         languageCode: id, rows: rows, variants: variants)
    }
    private static let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    static func alphabet(id: String) -> KeyboardAlphabet? { byID[id] }
}
