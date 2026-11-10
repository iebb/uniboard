import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class LanguageSuggestionPolicyTests: XCTestCase {
    private typealias Policy = LanguageSuggestionPolicy

    func testEmptyAndNilHintsDoNotSuggestAnything() {
        XCTAssertEqual(Policy.snapshot(activeKeyboardLanguages: [], preferredLanguages: []), .empty)
        XCTAssertEqual(Policy.snapshot(activeKeyboardLanguages: [nil, "", "emoji"],
                                       preferredLanguages: ["", "und", "mul", "zxx"]), .empty)
    }

    func testInvalidIdentifiersAreIgnoredSafely() {
        let invalid = [" ", " ja", "ja ", "ja--JP", "ja-", "-ja", "ja@keyboard", "ja.JP", "j",
                       "123", "🙂", "日本語", "ko/kr", "zh-Hans-!", "ja-abc", "ko-KR-KR",
                       "zh-Hans-Hant", "ja-u", "ja-x", "ja-u-ca-u-nu", "ja-abcde-abcde"]
        XCTAssertEqual(Policy.snapshot(activeKeyboardLanguages: invalid.map { Optional($0) },
                                       preferredLanguages: invalid), .empty)
    }

    func testLanguageLevelMappingAndProvenance() {
        let result = Policy.suggestions(activeKeyboardLanguages: ["ja-JP"],
                                        preferredLanguages: ["zh-Hans", "ko-KR", "en-US"])
        XCTAssertEqual(result.map(\.language), [.japanese, .mandarin, .korean])
        XCTAssertEqual(result.map(\.provenance), [.activeKeyboard, .preferredLanguage, .preferredLanguage])
    }

    func testActiveMatchesRankBeforePreferredAndUseCatalogOrder() {
        let result = Policy.suggestions(activeKeyboardLanguages: ["ko-KR", "ja-JP"],
                                        preferredLanguages: ["zh-Hans", "ko", "ja"])
        XCTAssertEqual(result.map(\.language), [.japanese, .korean, .mandarin])
        XCTAssertEqual(result.map(\.provenance), [.activeKeyboard, .activeKeyboard, .preferredLanguage])
        XCTAssertEqual(result, Policy.suggestions(activeKeyboardLanguages: ["ja-JP", "ko-KR"],
                                                 preferredLanguages: ["zh-Hans", "ko", "ja"]))
    }

    func testPreferredOrderIsPreservedNotReplacedWithCatalogOrder() {
        XCTAssertEqual(Policy.suggestions(activeKeyboardLanguages: [],
                                          preferredLanguages: ["ko", "zh-CN", "ja"]).map(\.language),
                       [.korean, .mandarin, .japanese])
    }

    func testDuplicateLanguagesAndSourcesProduceOneSuggestionWithStrongestProvenance() {
        let result = Policy.suggestions(activeKeyboardLanguages: ["ja", "ja-JP", "ja", "zh-SG"],
                                        preferredLanguages: ["ja", "zh-Hans", "zh-CN", "ko", "ko-KR"])
        XCTAssertEqual(result.map(\.language), [.japanese, .mandarin, .korean])
        XCTAssertEqual(result.map(\.provenance), [.activeKeyboard, .activeKeyboard, .preferredLanguage])
    }

    func testKoreanIsOneMethodNeutralLanguage() {
        let result = Policy.suggestions(activeKeyboardLanguages: ["ko", "ko-KR", "ko-Hang-KR"],
                                        preferredLanguages: ["ko", "ko-KP"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.language, .korean)
        XCTAssertEqual(result.first?.provenance, .activeKeyboard)
    }

    func testSimplifiedChineseRequiresKnownScriptOrSupportedRegion() {
        for identifier in ["zh-Hans", "zh-Hans-CN", "zh-CN", "zh-SG", "ZH_hAnS_sg", "zh-Hans-TW"] {
            XCTAssertEqual(Policy.suggestions(activeKeyboardLanguages: [identifier], preferredLanguages: [])
                .map(\.language), [.mandarin], identifier)
        }
    }

    func testTraditionalAndUnspecifiedChineseDoNotSuggestSimplifiedMandarin() {
        for identifier in ["zh", "zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-Hant-CN",
                           "zh-Hant-SG", "zh-Latn-CN", "zh-US", "zh-419"] {
            XCTAssertTrue(Policy.suggestions(activeKeyboardLanguages: [identifier],
                                              preferredLanguages: [identifier]).isEmpty, identifier)
        }
    }

    func testTraditionalActiveHintDoesNotUpgradeSimplifiedPreferredProvenance() {
        let result = Policy.suggestions(activeKeyboardLanguages: ["zh-Hant-TW", "zh"],
                                        preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(result.map(\.language), [.mandarin])
        XCTAssertEqual(result.first?.provenance, .preferredLanguage)
    }

    func testSnapshotPreservesScriptAndGeneralLanguageCodesForLocalLayoutMatching() {
        let snapshot = Policy.snapshot(activeKeyboardLanguages: ["ZH_hAnT_tw", "zh-Hans-CN", "AR_sa", "ar-SA"],
                                        preferredLanguages: ["he-IL", "en-US", "fr-FR"])
        XCTAssertEqual(snapshot.activeLanguages.map(\.languageCode), ["zh", "zh", "ar"])
        XCTAssertEqual(snapshot.activeLanguages.map(\.scriptCode), ["Hant", "Hans", nil])
        XCTAssertEqual(snapshot.activeLanguages.map(\.regionCode), ["TW", "CN", "SA"])
        XCTAssertEqual(snapshot.preferredLanguages.map(\.languageCode), ["he", "en", "fr"])
    }

    func testValidVariantsAndExtensionsDoNotSupplyChineseScriptEvidence() {
        XCTAssertTrue(Policy.suggestions(activeKeyboardLanguages: ["zh-x-Hans", "zh-u-co-hans"],
                                          preferredLanguages: ["zh-abcde"]).isEmpty)
        let result = Policy.suggestions(activeKeyboardLanguages: ["ja-JP-u-ca-japanese", "ko-KR-x-test"],
                                        preferredLanguages: ["zh-Hans-CN-u-nu-hanidec"])
        XCTAssertEqual(result.map(\.language), [.japanese, .korean, .mandarin])
    }

    func testArraysAreBoundedBeforeMappingAndDoNotSearchPastLimit() {
        let active: [String?] = Array(repeating: nil, count: Policy.maximumHintsPerSource) + ["ja"]
        let preferred = Array(repeating: "emoji", count: Policy.maximumHintsPerSource) + ["ko"]
        XCTAssertEqual(Policy.snapshot(activeKeyboardLanguages: active, preferredLanguages: preferred), .empty)
        let lastAllowed: [String?] = Array(repeating: nil, count: Policy.maximumHintsPerSource - 1) + ["ja"]
        XCTAssertEqual(Policy.suggestions(activeKeyboardLanguages: lastAllowed, preferredLanguages: [])
            .map(\.language), [.japanese])
    }

    func testOverlongIdentifiersAreRejectedNotTruncatedIntoValidHints() {
        let tooLong = "ja-x-" + String(repeating: "a", count: Policy.maximumIdentifierBytes)
        let huge = String(repeating: "🙂", count: 10_000)
        XCTAssertEqual(Policy.snapshot(activeKeyboardLanguages: [tooLong, huge],
                                       preferredLanguages: [tooLong, huge]), .empty)
    }

    func testSnapshotIsReplacementNotAccumulatedHistory() {
        let previous = Policy.snapshot(activeKeyboardLanguages: ["ja"], preferredLanguages: ["ko"])
        XCTAssertEqual(previous.suggestions.count, 2)
        XCTAssertEqual(Policy.snapshot(activeKeyboardLanguages: [], preferredLanguages: []), .empty)
    }
}
