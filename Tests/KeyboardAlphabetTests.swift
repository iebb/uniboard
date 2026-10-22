import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardAlphabetTests: XCTestCase {
    func testCatalogStartsWithEnglishAndHasUniqueStableIdentifiers() {
        let ids = KeyboardAlphabet.catalog.map(\.id)
        XCTAssertEqual(ids.first, "en")
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, ["en", "de", "fr", "es", "it", "pt", "sv", "fi", "nb", "da", "pl", "cs", "hu", "ro", "tr",
                             "el", "ru", "uk", "bg", "sr-Cyrl"])
        for alphabet in KeyboardAlphabet.catalog {
            XCTAssertEqual(KeyboardAlphabet.alphabet(id: alphabet.id), alphabet)
            XCTAssertFalse(alphabet.nativeName.isEmpty)
            XCTAssertFalse(alphabet.englishName.isEmpty)
        }
        XCTAssertNil(KeyboardAlphabet.alphabet(id: "xx"))
    }

    func testEveryLayoutHasThreeRowsOfSingleDistinctKeysThatFitAPhone() {
        for alphabet in KeyboardAlphabet.catalog {
            XCTAssertEqual(alphabet.rows.count, 3, alphabet.id)
            for row in alphabet.rows { XCTAssertTrue((7...12).contains(row.count), "\(alphabet.id) \(row)") }
            XCTAssertEqual(Set(alphabet.keys).count, alphabet.keys.count, alphabet.id)
            for key in alphabet.keys {
                XCTAssertEqual(key.count, 1, "\(alphabet.id) \(key)")
                XCTAssertEqual(alphabet.lowercase(key), key, "Rows hold lowercase keys: \(alphabet.id) \(key)")
            }
            for (key, choices) in alphabet.variants {
                XCTAssertTrue(alphabet.keys.contains(key), "\(alphabet.id) variants for a missing key \(key)")
                XCTAssertFalse(choices.contains(key))
                XCTAssertEqual(Set(choices).count, choices.count)
            }
        }
    }

    func testCasingFollowsEachLanguage() throws {
        let turkish = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "tr"))
        XCTAssertEqual(turkish.uppercase("i"), "İ")
        XCTAssertEqual(turkish.uppercase("ı"), "I")
        XCTAssertEqual(turkish.lowercase("I"), "ı")
        XCTAssertEqual(KeyboardAlphabet.english.uppercase("i"), "I")
        let greek = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "el"))
        XCTAssertEqual(greek.uppercase("ς"), "Σ")
        XCTAssertEqual(greek.uppercase("ά"), "Ά")
        XCTAssertFalse(greek.isCasedLetter(";"), "The Greek question mark has no capital")
        XCTAssertTrue(greek.isCasedLetter("α"))
        let russian = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ru"))
        XCTAssertEqual(russian.uppercase("ё"), "Ё")
        XCTAssertFalse(KeyboardAlphabet.english.isCasedLetter("α"), "Only the alphabet's own keys are its letters")
        for alphabet in KeyboardAlphabet.catalog {
            for key in alphabet.keys where alphabet.isCasedLetter(key) && key != "ς" {
                XCTAssertEqual(alphabet.lowercase(alphabet.uppercase(key)), key, "\(alphabet.id) \(key)")
            }
        }
    }

    func testTypingStateLabelsAndAcceptsOnlyTheCurrentAlphabet() throws {
        let greek = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "el"))
        var state = KeyboardTypingState()
        XCTAssertEqual(state.output(for: "q"), "q")
        XCTAssertNil(state.output(for: "α"))
        state.selectAlphabet(greek)
        XCTAssertEqual(state.output(for: "α"), "α")
        XCTAssertNil(state.output(for: "q"), "QWERTY keys no longer belong to the letters page")
        state.pressShift(at: 1)
        XCTAssertEqual(state.output(for: "α"), "Α")
        XCTAssertEqual(state.output(for: ";"), ";")
        state.selectAlphabet(.english)
        XCTAssertEqual(state.shift, .lowercase, "Switching drops a one-shot capital")
        state.pressShift(at: 2); state.pressShift(at: 2.1)
        XCTAssertEqual(state.shift, .capsLock)
        state.selectAlphabet(greek)
        XCTAssertEqual(state.shift, .capsLock, "Caps Lock survives a switch")
        XCTAssertEqual(KeyboardTypingLayoutPolicy.rows(for: .letters, hasAuxiliaryRow: true, alphabet: greek), greek.rows)
        XCTAssertEqual(KeyboardTypingLayoutPolicy.rows(for: .letters, hasAuxiliaryRow: false, widePad: true, alphabet: greek)[2],
                       greek.rows[2] + [",", "."])
        XCTAssertTrue(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "α", state: state, ansiPad: false))
    }
}
