import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardEnglishInputPolicyTests: XCTestCase {
    private let document = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let mode = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private var scope: KeyboardEnglishInputScope {
        KeyboardEnglishInputScope(documentIdentifier: document, modeIdentifier: mode)
    }

    func testExplicitCapitalizationModesAndMissingEmptyEditorContext() {
        for before: String? in [nil, "", "hello", "hello. "] {
            XCTAssertFalse(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .none, before: before))
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .allCharacters, before: before))
        }
        for mode in [KeyboardAutomaticCapitalization.words, .sentences] {
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: mode, before: nil))
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: mode, before: ""))
        }
        XCTAssertEqual(KeyboardAutomaticCapitalization.allCases.count, 4)
    }

    func testWordBoundariesSupportUnicodeWhitespaceAndOpeningPunctuation() {
        for before in ["hello ", "hello\t", "hello\n", "hello\u{00A0}", "hello\u{2003}",
                       "hello\u{3000}", "\"", "“", "(", "mother-", "🙂"] {
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .words, before: before), before)
        }
    }

    func testWordContinuationIncludesUnicodeLettersNumbersCombiningMarksAndIdentifiers() {
        for before in ["word", "é", "e\u{0301}", "α", "東京", "١٢", "x_", "don'", "don’", "e\u{0301}’", "क्\u{200D}", "\u{0301}", "\u{200C}"] {
            XCTAssertFalse(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .words, before: before), before)
        }
        for before in ["'", "’", " '", " ’"] {
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .words, before: before), before)
        }
    }

    func testSentenceStartsAfterNewlinesAndLeadingQuotes() {
        for before in [" ", "\t", "“", "'", "([“", "hello\n", "hello\r\n“", "hello\u{0085}",
                       "hello\u{2028}", "hello\u{2029} ‘", "hello\u{000B}", "hello\u{000C}"] {
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .sentences, before: before), before)
        }
    }

    func testSentenceTerminatorsCanPrecedeClosingAndOpeningQuotes() {
        for before in ["Hello. ", "Hello!\t", "Hello?” ", "“Hello.” “", "Hello.) [", "Done… ",
                       "終わり。　", "Really⁉ ", "Done！ ", "Done？ ", "Done． ", "Done｡ ", "Done؟ ", "Done‼ ", "Done⁇ ", "Done⁈ "] {
            XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .sentences, before: before), before)
        }
    }

    func testDecimalsDomainsAndMidSentenceQuotesDoNotInventSentenceStarts() {
        for before in ["hello ", "3.", "3.14 ", "v1.2.3 ", "example.com ", "hello.", "hello!", "hello?",
                       "hello “", "hello) ", "x_", "word\u{0301} "] {
            XCTAssertFalse(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .sentences, before: before), before)
        }
    }

    func testBoundedCapitalizationUsesTheSuffixWithoutSplittingScalars() {
        let prefix = String(repeating: "🙂", count: 10_000)
        XCTAssertTrue(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .sentences, before: prefix+". “"))
        XCTAssertFalse(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .words, before: prefix+"e\u{0301}"))
        XCTAssertFalse(KeyboardEnglishInputPolicy.shouldCapitalize(mode: .sentences, before: prefix+". "+String(repeating: "a", count: 129)))
    }

    func testTwoDeliberateSpacesReplaceOnlyTheVerifiedSpaceAndThirdIsLiteral() {
        var state = KeyboardDoubleSpaceState()
        XCTAssertEqual(state.spaceTap(before: "Hello", at: 1, scope: scope), .insertSpace)
        XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.3, scope: scope), .replacePreviousSpaceWithPeriod)
        XCTAssertEqual(state.spaceTap(before: "Hello. ", at: 1.4, scope: scope), .insertSpace)
        XCTAssertEqual(state.spaceTap(before: "Hello.  ", at: 1.5, scope: scope), .insertSpace)
    }

    func testLettersNumbersClosingQuotesAndCombiningWordsAreEligible() {
        for word in ["hello", "42", "١٢", "Ⅻ", "½", "α", "東京", "e\u{0301}", "“hello”", "'hello'", "«hello»", "‹hello›", "「hello」", "『hello』", "(hello)", "word]", "word}", "word）", "word］", "word｝", "word])", "word】"] {
            var state = KeyboardDoubleSpaceState()
            XCTAssertEqual(state.spaceTap(before: word, at: 1, scope: scope), .insertSpace)
            XCTAssertEqual(state.spaceTap(before: word+" ", at: 1.1, scope: scope), .replacePreviousSpaceWithPeriod, word)
        }
    }

    func testWhitespacePunctuationSymbolsEmojiAndStandaloneQuotesNeverAuthorizeDeletion() {
        for before in ["", " ", "word ", "word\t", "word\n", "word\u{00A0}", "word.", "word!", "word?", "“done!”", "word.)", "🙂", "1️⃣", "🇯🇵", "\"", "’", ")", "]", "）", "】", "\u{0301}", "_"] {
            var state = KeyboardDoubleSpaceState()
            XCTAssertEqual(state.spaceTap(before: before, at: 1, scope: scope), .insertSpace)
            XCTAssertEqual(state.spaceTap(before: before+" ", at: 1.1, scope: scope), .insertSpace, before)
        }
    }

    func testMissingOrMismatchedHostContextNeverDeletes() {
        for second: String? in [nil, "Hello", "Hello  ", "Other ", "Hello\u{00A0}", "Hello\n", ""] {
            var state = KeyboardDoubleSpaceState()
            _ = state.spaceTap(before: "Hello", at: 1, scope: scope)
            XCTAssertEqual(state.spaceTap(before: second, at: 1.1, scope: scope), .insertSpace)
        }
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: nil, at: 1, scope: scope)
        XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.1, scope: scope), .insertSpace)
    }

    func testCanonicalEquivalenceDoesNotMakeAnEditedContextExact() {
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: "cafe\u{0301}", at: 1, scope: scope)
        XCTAssertEqual(state.spaceTap(before: "café ", at: 1.1, scope: scope), .insertSpace)
    }

    func testDifferentDocumentModeAndUnknownScopeInvalidateTheSequence() {
        let otherDocument = KeyboardEnglishInputScope(documentIdentifier: UUID(), modeIdentifier: mode)
        let otherMode = KeyboardEnglishInputScope(documentIdentifier: document, modeIdentifier: UUID())
        for secondScope: KeyboardEnglishInputScope? in [nil, otherDocument, otherMode] {
            var state = KeyboardDoubleSpaceState()
            _ = state.spaceTap(before: "Hello", at: 1, scope: scope)
            XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.1, scope: secondScope), .insertSpace)
        }
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: "Hello", at: 1, scope: nil)
        XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.1, scope: scope), .insertSpace)
    }

    func testQueryAndDisabledModesInsertLiteralSpacesAndResetPendingHostTap() {
        for query in [true, false] {
            var state = KeyboardDoubleSpaceState()
            _ = state.spaceTap(before: "Hello", at: 1, scope: scope)
            XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.1, scope: scope, isQuery: query, enabled: query), .insertSpace)
            XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.2, scope: scope), .insertSpace)
        }
    }

    func testInterveningEditResetCannotDeleteAnIdenticalRestoredSuffix() {
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: "Hello", at: 1, scope: scope)
        state.reset()
        state.reset()
        XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1.1, scope: scope), .insertSpace)
    }

    func testStrictMonotonicTimestampAndInclusiveTimeoutBoundary() {
        for (second, expected): (TimeInterval, KeyboardSpaceTapAction) in [
            (1.75, .replacePreviousSpaceWithPeriod), (1.750001, .insertSpace),
            (1, .insertSpace), (0.9, .insertSpace), (-1, .insertSpace),
            (.nan, .insertSpace), (.infinity, .insertSpace), (-.infinity, .insertSpace)] {
            var state = KeyboardDoubleSpaceState()
            _ = state.spaceTap(before: "Hello", at: 1, scope: scope)
            XCTAssertEqual(state.spaceTap(before: "Hello ", at: second, scope: scope), expected)
        }
        XCTAssertEqual(KeyboardDoubleSpaceState.doubleSpaceInterval, 0.75)
    }

    func testInvalidInitialTimesNeverArmDeletionAndDoNotTrap() {
        for first: TimeInterval in [.nan, .infinity, -.infinity, -1] {
            var state = KeyboardDoubleSpaceState()
            _ = state.spaceTap(before: "Hello", at: first, scope: scope)
            XCTAssertEqual(state.spaceTap(before: "Hello ", at: 1, scope: scope), .insertSpace)
        }
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: "Hello", at: .greatestFiniteMagnitude, scope: scope)
        XCTAssertEqual(state.spaceTap(before: "Hello ", at: .greatestFiniteMagnitude, scope: scope), .insertSpace)
        _ = state.spaceTap(before: "Hello", at: 0, scope: scope)
        XCTAssertEqual(state.spaceTap(before: "Hello ", at: 0.1, scope: scope), .replacePreviousSpaceWithPeriod)
    }

    func testChangedContextCanStartAFreshDeliberatePairButNeverDeleteOnMismatch() {
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: "Hello", at: 1, scope: scope)
        XCTAssertEqual(state.spaceTap(before: "Goodbye", at: 1.1, scope: scope), .insertSpace)
        XCTAssertEqual(state.spaceTap(before: "Goodbye ", at: 1.2, scope: scope), .replacePreviousSpaceWithPeriod)
    }

    func testLongUnicodeContextIsBoundedAndVerifiesItsActualSpace() {
        let prefix = String(repeating: "🙂", count: 10_000)
        let context = prefix+String(repeating: "é", count: 127)+"Z"
        var state = KeyboardDoubleSpaceState()
        _ = state.spaceTap(before: context, at: 1, scope: scope)
        XCTAssertEqual(state.spaceTap(before: context+" ", at: 1.1, scope: scope), .replacePreviousSpaceWithPeriod)
        _ = state.spaceTap(before: context, at: 2, scope: scope)
        XCTAssertEqual(state.spaceTap(before: context+"x ", at: 2.1, scope: scope), .insertSpace)
    }
}
