import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class JapaneseInputReadingTests: XCTestCase {
    func testWholeBufferRecognitionIncludesUnfinishedSyllables() throws {
        for (input, kana) in [("n", "n"), ("k", "k"), ("sh", "sh"), ("ny", "ny"),
                              ("ky", "ky"), ("nihong", "にほんg"), ("kk", "っk")] {
            let reading = try XCTUnwrap(JapaneseInputReading.parse(input), input)
            XCTAssertEqual(reading.kana, kana, input)
            XCTAssertFalse(reading.isComplete, input)
            XCTAssertNotNil(JapaneseInputReading.normalize(mode: .japaneseRomaji, rawInput: input))
            XCTAssertNil(JapaneseInputReading.normalizedCustomReading(input == "n" ? "k" : input))
        }
    }

    func testCoreExamplesAndCommonAliases() throws {
        for (input, kana) in [("nihongo", "にほんご"), ("NIHONGO", "にほんご"),
                              ("toukyou", "とうきょう"), ("watashi", "わたし"),
                              ("kyouhaiitenkidesu", "きょうはいいてんきです"),
                              ("arigatou", "ありがとう"), ("konnichiha", "こんにちは"),
                              ("shi", "し"), ("si", "し"), ("chi", "ち"), ("ti", "ち"),
                              ("tsu", "つ"), ("tu", "つ"), ("fu", "ふ"), ("hu", "ふ"),
                              ("sha", "しゃ"), ("sya", "しゃ"), ("ja", "じゃ"),
                              ("gakkou", "がっこう")] {
            let reading = try XCTUnwrap(JapaneseInputReading.parse(input), input)
            XCTAssertEqual(reading.kana, kana, input)
            XCTAssertTrue(reading.isComplete, input)
            XCTAssertEqual(JapaneseInputReading.normalizedCustomReading(input), kana, input)
        }
        // Use the documented doubled-consonant spelling, not arbitrary reverse transliteration.
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("maccha"), "まっちゃ")
        XCTAssertNil(JapaneseInputReading.parse("matcha"))
    }

    func testExplicitNBoundariesAndFinalN() {
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("n"), "ん")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("nn"), "ん")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("kan"), "かん")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("kan'i"), "かんい")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("shin'you"), "しんよう")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("nya"), "にゃ")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("n'ya"), "んや")
        XCTAssertEqual(JapaneseInputReading.parse("n'")?.kana, "ん")
        XCTAssertNil(JapaneseInputReading.parse("ka'na"))
        XCTAssertNil(JapaneseInputReading.parse("'"))
    }

    func testKanaAndCustomReadingCanonicalizationNeverTouchesOutput() {
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("ニホンゴ"), "にほんご")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("にほんご"), "にほんご")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("ガッコウ"), "がっこう")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("か\u{3099}"), "が")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("ウ\u{3099}"), "ゔ")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("ko-hi-"), "こーひー")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("日本語"), nil)
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("ｶﾅ"), nil)
        XCTAssertNil(JapaneseInputReading.normalizedCustomReading(""))
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("にhonご"), "にほんご")
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading("xyaxtsuvula"), "ゃっゔぁ")
    }

    func testRecognizerRejectsUnsupportedModesAndInvalidWholeInputs() {
        for mode in [LanguageInputMode.direct, .mandarinPinyin, .koreanRomaja] {
            XCTAssertNil(JapaneseInputReading.normalize(mode: mode, rawInput: "nihongo"))
        }
        for input in ["ni hon", "ni\n", "ni\t", "ni\0", "ni🙂", "ni1", "ni.", "https://a", "ka@a",
                      "é", "ＮＩ", "niqz", "に\u{3099}", "\u{3099}"] {
            XCTAssertNil(JapaneseInputReading.parse(input), input)
            XCTAssertNil(JapaneseInputReading.normalizedCustomReading(input), input)
        }
        XCTAssertNotNil(JapaneseInputReading.parse(""))
    }

    func testScalarBoundAndOriginalInputAreIndependentOfNormalizedKana() throws {
        XCTAssertNotNil(JapaneseInputReading.parse(String(repeating: "a", count: 256)))
        XCTAssertNil(JapaneseInputReading.parse(String(repeating: "a", count: 257)))
        // Original decomposed kana has two scalars but one normalized kana scalar.
        let original = "か\u{3099}"
        var state = LanguageCompositionState(documentID: UUID(), mode: .japaneseRomaji)
        XCTAssertEqual(state.append(original, origin: .normalKeyTap,
                                    normalize: { JapaneseInputReading.normalize(mode: $0, rawInput: $1) }), .accepted)
        XCTAssertEqual(Array(state.rawInput.unicodeScalars), Array(original.unicodeScalars))
        XCTAssertEqual(state.rawInput.unicodeScalars.count, 2)
        let request = try XCTUnwrap(state.requestConversion())
        XCTAssertEqual(Array(request.rawInput.unicodeScalars), Array(original.unicodeScalars))
        XCTAssertEqual(JapaneseInputReading.normalizedCustomReading(request.rawInput)?.unicodeScalars.count, 1)
    }

    func testLiteralUppercaseAndIncompleteStateAreNotRewritten() throws {
        var state = LanguageCompositionState(documentID: UUID(), mode: .japaneseRomaji)
        for key in ["N", "I", "H", "O", "N", "G"] {
            XCTAssertEqual(state.append(key, origin: .normalKeyTap,
                                        normalize: { JapaneseInputReading.normalize(mode: $0, rawInput: $1) }), .accepted)
        }
        XCTAssertEqual(state.rawInput, "NIHONG")
        XCTAssertEqual(JapaneseInputReading.parse(state.rawInput)?.kana, "にほんg")
        let previous = state.rawInput
        XCTAssertEqual(state.append("!", origin: .normalKeyTap,
                                    normalize: { JapaneseInputReading.normalize(mode: $0, rawInput: $1) }), .unsupportedInput)
        XCTAssertEqual(state.rawInput, previous)
    }
}
