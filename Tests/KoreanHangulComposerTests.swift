import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KoreanHangulComposerTests: XCTestCase {
    private typealias Composer = KoreanHangulComposer
    private typealias Mapping = KoreanHangulComposer.KeyMapping

    // Reference keyboard data is deliberately test-only. Production callers
    // must obtain and validate the actual data pack before making a composer.
    private lazy var standardMapping = try! Mapping(entries: referenceEntries())

    private func makeComposer() -> Composer { Composer(mapping: standardMapping) }

    // Independent keyboard spellings in Unicode L/V/T order, not engine tables.
    private let leadingKeys = ["r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g"]
    private let vowelKeys = ["k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l"]
    private let finalKeys = ["", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "qt", "t", "T", "d", "w", "c", "z", "x", "v", "g"]

    private func assertExact(_ actual: String, _ expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.unicodeScalars), Array(expected.unicodeScalars), file: file, line: line)
    }

    private func syllable(_ leading: Int, _ vowel: Int, _ final: Int = 0) -> String {
        String(Unicode.Scalar(0xAC00 + leading * 588 + vowel * 28 + final)!)
    }

    func testRequiredExamplesAndWords() throws {
        let composer = makeComposer()
        for (raw, expected) in [
            ("", ""), ("rk", "가"), ("rksk", "가나"), ("rkr", "각"),
            ("rkrk", "가가"), ("Rk", "까"), ("rhk", "과"),
            ("rkqt", "값"), ("rkqtk", "갑사"), ("gksrmf", "한글"),
            ("dkssudgktpdy", "안녕하세요"), ("gksrnrdj", "한국어"),
            ("ekfr", "닭"), ("ekfrk", "달가"), ("dlfrj", "일거")
        ] {
            assertExact(try composer.compose(raw), expected)
        }
        // Pure conversion must not silently change the optional editable buffer.
        XCTAssertEqual(composer.rawInput, "")
        XCTAssertEqual(composer.output, "")
    }

    func testAll11172ModernSyllablesHaveExactlyTheExpectedUnicodeScalar() throws {
        let composer = makeComposer()
        var count = 0
        for (l, leading) in leadingKeys.enumerated() {
            for (v, vowel) in vowelKeys.enumerated() {
                for (t, final) in finalKeys.enumerated() {
                    let raw = leading + vowel + final
                    let result = try composer.compose(raw)
                    let scalars = Array(result.unicodeScalars)
                    XCTAssertEqual(scalars.count, 1, raw)
                    XCTAssertEqual(scalars.first?.value, UInt32(0xAC00 + l * 588 + v * 28 + t), raw)
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 11_172)
        assertExact(try composer.compose("glg"), "힣")
    }

    func testAll52KeysAndShiftSemantics() throws {
        let composer = makeComposer()
        let lower = Array("abcdefghijklmnopqrstuvwxyz")
        let expected = Array("ㅁㅠㅊㅇㄷㄹㅎㅗㅑㅓㅏㅣㅡㅜㅐㅔㅂㄱㄴㅅㅕㅍㅈㅌㅛㅋ")
        let shifted = ["r": "ㄲ", "e": "ㄸ", "q": "ㅃ", "t": "ㅆ", "w": "ㅉ", "o": "ㅒ", "p": "ㅖ"]
        for (index, character) in lower.enumerated() {
            let raw = String(character)
            assertExact(try composer.compose(raw), String(expected[index]))
            assertExact(try composer.compose(raw.uppercased()), shifted[raw] ?? String(expected[index]))
        }
        for (raw, expected) in [
            ("Rk", "까"), ("Ek", "따"), ("Qk", "빠"), ("Tk", "싸"), ("Wk", "짜"),
            ("rO", "걔"), ("rP", "계"), ("rkR", "갂"), ("rkT", "갔"),
            ("rkRk", "가까"), ("rkTk", "가싸"),
            ("rkEk", "가따"), ("rkQk", "가빠"), ("rkWk", "가짜"),
            ("rrk", "ㄱ가"), ("rkrr", "각ㄱ"), ("rktt", "갓ㅅ")
        ] {
            assertExact(try composer.compose(raw), expected)
        }
    }

    func testSevenCompoundVowelsWithAndWithoutOnsets() throws {
        let composer = makeComposer()
        for (keys, jamo, syllable) in [
            ("hk", "ㅘ", "과"), ("ho", "ㅙ", "괘"), ("hl", "ㅚ", "괴"),
            ("nj", "ㅝ", "궈"), ("np", "ㅞ", "궤"), ("nl", "ㅟ", "귀"),
            ("ml", "ㅢ", "긔")
        ] {
            assertExact(try composer.compose(keys), jamo)
            assertExact(try composer.compose("r" + keys), syllable)
        }
        // Standard two-set uses separate ㅐ/ㅔ keys, not an inferred ㅣ suffix.
        for (keys, expected) in [("kl", "ㅏㅣ"), ("jl", "ㅓㅣ"), ("hkl", "ㅘㅣ"),
                                 ("njl", "ㅝㅣ"), ("hO", "ㅗㅒ"), ("nP", "ㅜㅖ"),
                                 ("kk", "ㅏㅏ"), ("rkk", "가ㅏ")] {
            assertExact(try composer.compose(keys), expected)
        }
    }

    func testAllCompoundFinalsSplitAndSimpleFinalsMoveBeforeEveryVowel() throws {
        let composer = makeComposer()
        // Each expected remainder/onset is specified independently of the engine.
        let splits: [String: (remaining: Int, onset: String)] = [
            "rt": (1, "t"), "sw": (4, "w"), "sg": (4, "g"),
            "fr": (8, "r"), "fa": (8, "a"), "fq": (8, "q"),
            "ft": (8, "t"), "fx": (8, "x"), "fv": (8, "v"),
            "fg": (8, "g"), "qt": (17, "t")
        ]
        for final in finalKeys.dropFirst() {
            let split = splits[final] ?? (remaining: 0, onset: final)
            let onset = try XCTUnwrap(leadingKeys.firstIndex(of: split.onset))
            for (v, vowel) in vowelKeys.enumerated() {
                let raw = "rk" + final + vowel
                assertExact(try composer.compose(raw), syllable(0, 0, split.remaining) + syllable(onset, v))
            }
        }
    }

    func testIncompleteAndNoncombiningSequencesStayExact() throws {
        let composer = makeComposer()
        for (raw, expected) in [
            ("r", "ㄱ"), ("k", "ㅏ"), ("rt", "ㄱㅅ"), ("qt", "ㅂㅅ"),
            ("rr", "ㄱㄱ"), ("kr", "ㅏㄱ"), ("krk", "ㅏ가"),
            ("rkqtr", "값ㄱ"), ("rkqtrk", "값가"), ("rkrsk", "각나"),
            ("rkRr", "갂ㄱ"), ("rkTt", "갔ㅅ"), ("rkrhk", "가과"),
            ("rhkrtk", "곽사"), ("rhkE", "과ㄸ")
        ] {
            assertExact(try composer.compose(raw), expected)
        }
        // Two-set key IDs are literal keyboard positions, not romaja words.
        XCTAssertNotEqual(try composer.compose("hangul"), "한글")
    }

    func testBackspaceUndoesKeysAcrossCompoundsAndResyllabification() throws {
        for (raw, outputs) in [
            ("rkqtk", ["갑사", "값", "갑", "가", "ㄱ", ""]),
            ("rhk", ["과", "고", "ㄱ", ""]),
            ("Rk", ["까", "ㄲ", ""]),
            ("rO", ["걔", "ㄱ", ""]),
            ("rkRk", ["가까", "갂", "가", "ㄱ", ""]),
            ("rhkrtk", ["곽사", "곿", "곽", "과", "고", "ㄱ", ""])
        ] {
            var composer = makeComposer()
            try composer.append(raw)
            for (index, expected) in outputs.enumerated() {
                if index > 0 { XCTAssertTrue(composer.backspace()) }
                assertExact(composer.output, expected)
                XCTAssertEqual(composer.rawInput, String(raw.prefix(raw.count - index)))
            }
            XCTAssertFalse(composer.backspace())
        }
    }

    func testEveryModernSyllableCanBeAppendedAndDeletedKeywise() throws {
        // Every possible final and vowel, under every onset, also exercises
        // reparse on all prefixes (not deletion of a rendered Character).
        for leading in leadingKeys {
            for vowel in vowelKeys {
                for final in finalKeys {
                    let raw = leading + vowel + final
                    var composer = makeComposer()
                    var prefix = ""
                    for key in raw {
                        prefix.append(key)
                        try composer.append(String(key))
                        assertExact(composer.output, try makeComposer().compose(prefix))
                        XCTAssertEqual(composer.rawInput, prefix)
                    }
                    while !prefix.isEmpty {
                        prefix.removeLast()
                        XCTAssertTrue(composer.backspace())
                        assertExact(composer.output, try makeComposer().compose(prefix))
                        XCTAssertEqual(composer.rawInput, prefix)
                    }
                    XCTAssertFalse(composer.backspace())
                }
            }
        }
    }

    func testBoundedInputAndAtomicFailures() throws {
        var composer = makeComposer()
        let maximum = String(repeating: "rk", count: 128)
        try composer.append(maximum)
        XCTAssertEqual(composer.rawInput.unicodeScalars.count, 256)
        assertExact(composer.output, String(repeating: "가", count: 128))
        try composer.append("")
        XCTAssertThrowsError(try composer.append("r")) { error in
            XCTAssertEqual(error as? Composer.InputError, .inputTooLong)
        }
        XCTAssertThrowsError(try composer.replaceRawInput(String(repeating: "r", count: 257))) { error in
            XCTAssertEqual(error as? Composer.InputError, .inputTooLong)
        }
        XCTAssertEqual(composer.rawInput, maximum)
        assertExact(composer.output, String(repeating: "가", count: 128))
        XCTAssertTrue(composer.backspace())
        try composer.append("k")
        XCTAssertEqual(composer.rawInput, maximum)
        try composer.replaceRawInput("rk")
        XCTAssertThrowsError(try composer.append("s!")) { error in
            XCTAssertEqual(error as? Composer.InputError, .unsupportedKey(index: 3, scalar: 33))
        }
        XCTAssertEqual(composer.rawInput, "rk")
        assertExact(composer.output, "가")
        XCTAssertThrowsError(try composer.replaceRawInput("🙂"))
        XCTAssertEqual(composer.rawInput, "rk")
        assertExact(composer.output, "가")
        try composer.replaceRawInput("")
        XCTAssertEqual(composer.output, "")
        XCTAssertFalse(composer.backspace())
    }

    func testRejectsEveryNonletterASCIIAndUnicodeWithoutLossyFallback() throws {
        let composer = makeComposer()
        for code in UInt32(0)...127 where !(65...90).contains(code) && !(97...122).contains(code) {
            XCTAssertThrowsError(try composer.compose("rk" + String(Unicode.Scalar(code)!))) { error in
                XCTAssertEqual(error as? Composer.InputError, .unsupportedKey(index: 2, scalar: code))
            }
        }
        for invalid in ["ㄱ", "가", "ᄀ", "ᅡ", "ᆨ", "é", "e\u{0301}", "Ｒ", "🙂", "\u{200D}", "\u{FEFF}"] {
            XCTAssertThrowsError(try composer.compose(invalid), invalid)
        }
        XCTAssertThrowsError(try composer.compose("e\u{0301}")) { error in
            XCTAssertEqual(error as? Composer.InputError, .unsupportedKey(index: 1, scalar: 0x301))
        }
        XCTAssertThrowsError(try composer.compose(String(repeating: "r", count: 10_000))) { error in
            XCTAssertEqual(error as? Composer.InputError, .inputTooLong)
        }
    }

    private func referenceEntries() -> [Mapping.Entry] {
        let keys = Array("abcdefghijklmnopqrstuvwxyz")
        let values = Array("ㅁㅠㅊㅇㄷㄹㅎㅗㅑㅓㅏㅣㅡㅜㅐㅔㅂㄱㄴㅅㅕㅍㅈㅌㅛㅋ")
        let shifted = ["r": "ㄲ", "e": "ㄸ", "q": "ㅃ", "t": "ㅆ", "w": "ㅉ", "o": "ㅒ", "p": "ㅖ"]
        return keys.enumerated().flatMap { index, key -> [Mapping.Entry] in
            let lower = String(key)
            return [.init(key: lower, jamo: String(values[index])),
                    .init(key: lower.uppercased(), jamo: shifted[lower] ?? String(values[index]))]
        }
    }

    func testValidatedDeclarativeMappingInjectionAndOrderIndependence() throws {
        let entries = referenceEntries()
        let injected = Composer(mapping: try Mapping(entries: Array(entries.reversed())))
        for leading in leadingKeys {
            for vowel in vowelKeys {
                for final in finalKeys {
                    let raw = leading + vowel + final
                    assertExact(try injected.compose(raw), try makeComposer().compose(raw))
                }
            }
        }
        // Structural validation permits an explicitly supplied alternative map;
        // it must actually drive composition, not silently use the reference map.
        var changed = entries
        let r = try XCTUnwrap(changed.firstIndex(where: { $0.key == "r" }))
        changed[r] = .init(key: "r", jamo: "ㄴ")
        let alternative = Composer(mapping: try Mapping(entries: changed))
        assertExact(try alternative.compose("rk"), "나")
        assertExact(try makeComposer().compose("rk"), "가")

        // All 21 modern vowels may be data outputs, even compound vowels. Such
        // an atomic mapped vowel still takes one key to delete.
        let k = try XCTUnwrap(changed.firstIndex(where: { $0.key == "k" }))
        changed[k] = .init(key: "k", jamo: "ㅘ")
        var atomic = Composer(mapping: try Mapping(entries: changed))
        try atomic.append("rk")
        assertExact(atomic.output, "놔")
        XCTAssertTrue(atomic.backspace())
        assertExact(atomic.output, "ㄴ")
    }

    func testMappingRejectsIncompleteDuplicateAndMalformedData() throws {
        let entries = referenceEntries()
        for invalid in [[], Array(entries.dropLast()), entries + [entries[0]]] {
            XCTAssertThrowsError(try Mapping(entries: invalid)) { error in
                XCTAssertEqual(error as? Mapping.ValidationError, .incorrectEntryCount)
            }
        }
        var duplicate = entries
        duplicate[1] = entries[0]
        XCTAssertThrowsError(try Mapping(entries: duplicate)) { error in
            XCTAssertEqual(error as? Mapping.ValidationError, .duplicateKey("a"))
        }
        for key in ["", "ab", "1", " ", "é", "Ａ", "a\u{0301}", "\0", String(repeating: "a", count: 10_000)] {
            var invalid = entries
            invalid[0] = .init(key: key, jamo: "ㄱ")
            XCTAssertThrowsError(try Mapping(entries: invalid)) { error in
                XCTAssertEqual(error as? Mapping.ValidationError, .invalidKey(entry: 0))
            }
        }
        for value in ["", "ㄱㅏ", "ㄳ", "ㄵ", "ㅄ", "가", "ᄀ", "ᅡ", "ᆨ", "ㅤ", "ㆆ", "A", "🙂", String(repeating: "ㄱ", count: 10_000)] {
            var invalid = entries
            invalid[0] = .init(key: "a", jamo: value)
            XCTAssertThrowsError(try Mapping(entries: invalid)) { error in
                XCTAssertEqual(error as? Mapping.ValidationError, .invalidJamo(entry: 0))
            }
        }
    }

    private struct MappingDocument: Encodable {
        let schemaVersion: Int
        let entries: [Mapping.Entry]
    }

    func testBoundedVersionedJSONMapping() throws {
        let data = try JSONEncoder().encode(MappingDocument(schemaVersion: 1, entries: referenceEntries()))
        let composer = Composer(mapping: try Mapping(jsonData: data))
        assertExact(try composer.compose("rkqtk"), "갑사")
        assertExact(try composer.compose("Rk"), "까")
        XCTAssertLessThan(data.count, Mapping.maximumJSONBytes)

        // Exactly the maximum byte count remains legal; the bound is on bytes,
        // not JSON characters or the number of decoded mapping entries.
        var padded = data
        padded.append(Data(repeating: 32, count: Mapping.maximumJSONBytes - data.count))
        let atLimit = Composer(mapping: try Mapping(jsonData: padded))
        assertExact(try atLimit.compose("rhk"), "과")
        padded.append(32)
        XCTAssertThrowsError(try Mapping(jsonData: padded)) { error in
            XCTAssertEqual(error as? Mapping.ValidationError, .dataTooLarge)
        }
        for version in [-1, 0, 2] {
            let unsupported = try JSONEncoder().encode(MappingDocument(schemaVersion: version, entries: referenceEntries()))
            XCTAssertThrowsError(try Mapping(jsonData: unsupported)) { error in
                XCTAssertEqual(error as? Mapping.ValidationError, .unsupportedSchemaVersion)
            }
        }
        for invalid in ["", "{}", "[]", "null", "not JSON",
                        #"{"schemaVersion":1,"entries":"wrong type"}"#,
                        #"{"schemaVersion":1,"entries":[{"key":"r"}]}"#,
                        #"{"schemaVersion":"1","entries":[]}"#] {
            XCTAssertThrowsError(try Mapping(jsonData: Data(invalid.utf8))) { error in
                XCTAssertEqual(error as? Mapping.ValidationError, .invalidJSON)
            }
        }
        XCTAssertThrowsError(try Mapping(jsonData: Data([0xFF, 0xFE, 0xFF]))) { error in
            XCTAssertEqual(error as? Mapping.ValidationError, .invalidJSON)
        }
        let empty = try JSONEncoder().encode(MappingDocument(schemaVersion: 1, entries: []))
        XCTAssertThrowsError(try Mapping(jsonData: empty)) { error in
            XCTAssertEqual(error as? Mapping.ValidationError, .incorrectEntryCount)
        }
        var duplicate = referenceEntries()
        duplicate[1] = duplicate[0]
        let duplicated = try JSONEncoder().encode(MappingDocument(schemaVersion: 1, entries: duplicate))
        XCTAssertThrowsError(try Mapping(jsonData: duplicated)) { error in
            XCTAssertEqual(error as? Mapping.ValidationError, .duplicateKey("a"))
        }
    }

    func testValueCopiesDoNotShareMutableCompositionState() throws {
        var original = makeComposer()
        try original.append("rkqt")
        var copy = original
        try copy.append("k")
        assertExact(copy.output, "갑사")
        assertExact(original.output, "값")
        XCTAssertTrue(original.backspace())
        assertExact(original.output, "갑")
        assertExact(copy.output, "갑사")
    }
}
