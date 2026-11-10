#if canImport(UIKit)
import UIKit

/// Main-actor isolation owns UITextChecker; only immutable result values leave it.
/// No learning, ignored-word lists, storage, logging or remote services are used.
@available(iOS 17.0, *)
@MainActor
protocol EnglishSuggestionProviding {
    func suggestions(for word: String) -> KeyboardEnglishSpellingResult
}

/// Offline OS English spelling help, NOT a CJK converter or a downloadable pack.
/// Dictionary presence and empty guesses are surfaced without sample fallbacks.
/// OS dictionaries/rankings vary by device/OS; fake-provider unit tests do not
/// establish that any particular spelling produces an actual OS suggestion.
@available(iOS 17.0, *)
@MainActor
final class EnglishSuggestionProvider: EnglishSuggestionProviding {
    private let checker = UITextChecker()
    let language: String

    /// A specific installed English dictionary is required; do not silently use
    /// another language or advertise a dictionary which is not on this device.
    init(language: String = "en_US") {
        self.language = language
    }

    var isDictionaryAvailable: Bool {
        let identifier = language.replacingOccurrences(of: "-", with: "_")
        return (identifier == "en" || identifier.hasPrefix("en_"))
            && UITextChecker.availableLanguages.contains(language)
    }

    func suggestions(for word: String) -> KeyboardEnglishSpellingResult {
        guard isDictionaryAvailable else {
            return result(word, availability: .dictionaryUnavailable, spelling: .unknown)
        }
        guard KeyboardAutocorrectionPolicy.isASCIIWord(word) else {
            return result(word, spelling: .unknown)
        }
        let fullRange = NSRange(location: 0, length: word.utf16.count)
        let misspelling = checker.rangeOfMisspelledWord(
            in: word, range: fullRange, startingAt: 0, wrap: false, language: language)
        guard misspelling.location != NSNotFound else {
            return result(word, spelling: .validWord)
        }
        // A partial spelling range must never authorize replacing the full token.
        guard misspelling.location == fullRange.location, misspelling.length == fullRange.length else {
            return result(word, spelling: .unknown)
        }
        let guesses = checker.guesses(forWordRange: fullRange, in: word, language: language) ?? []
        // Keep the real OS order for explicit suggestions, while the pure policy
        // derives confidence from all proposals, never from first-guess ranking.
        let limit = KeyboardAutocorrectionPolicy.maximumProposals // 12, bounded within 8...16
        return KeyboardEnglishSpellingResult(
            word: word, availability: .available, spelling: .misspelledWholeWord,
            rankedProposals: Array(guesses.prefix(limit)), proposalsAreComplete: guesses.count <= limit)
    }

    private func result(_ word: String,
                        availability: KeyboardEnglishSpellingResult.Availability = .available,
                        spelling: KeyboardEnglishSpellingResult.Spelling) -> KeyboardEnglishSpellingResult {
        KeyboardEnglishSpellingResult(word: word, availability: availability, spelling: spelling,
                                      rankedProposals: [], proposalsAreComplete: true)
    }
}
#endif
