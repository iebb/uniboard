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
    /// The language whose case mapping applies, such as Turkish dotted and dotless i.
    let languageCode: String
    /// Three rows of lowercase keys, at most 12 each.
    let rows: [[String]]

    var keys: [String] { rows.flatMap { $0 } }
    var locale: Locale { Locale(identifier: languageCode) }

    func uppercase(_ key: String) -> String { key.uppercased(with: locale) }
    func lowercase(_ key: String) -> String { key.lowercased(with: locale) }
    /// A key of this alphabet whose capital differs, so Shift changes it.
    func isCasedLetter(_ key: String) -> Bool { keys.contains(key) && uppercase(key) != key }
}

extension KeyboardAlphabet: Equatable, Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension KeyboardAlphabet {
    private static func rows(_ rows: String...) -> [[String]] { rows.map { $0.map(String.init) } }

    static let english = KeyboardAlphabet(id: "en", nativeName: "English", englishName: "English", script: .latin,
        languageCode: "en", rows: rows("qwertyuiop", "asdfghjkl", "zxcvbnm"))

    static let catalog: [KeyboardAlphabet] = [english]
    private static let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    static func alphabet(id: String) -> KeyboardAlphabet? { byID[id] }
}
