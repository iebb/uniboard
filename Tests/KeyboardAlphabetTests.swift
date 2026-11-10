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
                             "el", "ru", "uk", "bg", "sr-Cyrl", "he", "ar"])
        XCTAssertFalse(ids.contains("hy"), "Armenian is not in 1.4")
        for alphabet in KeyboardAlphabet.catalog {
            XCTAssertEqual(KeyboardAlphabet.alphabet(id: alphabet.id), alphabet)
            XCTAssertFalse(alphabet.nativeName.isEmpty)
            XCTAssertFalse(alphabet.englishName.isEmpty)
        }
        XCTAssertNil(KeyboardAlphabet.alphabet(id: "xx"))
        XCTAssertEqual(Set(KeyboardAlphabet.catalog).count, ids.count, "Alphabets hash by their identifier")
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

    func testHebrewAndArabicAreCaselessRightToLeftRowsInVisualOrder() throws {
        let hebrew = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "he"))
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        XCTAssertEqual(hebrew.nativeName, "עברית")
        XCTAssertEqual(arabic.nativeName, "العربية")
        XCTAssertEqual([hebrew.script, arabic.script], [.hebrew, .arabic])
        XCTAssertEqual(KeyboardAlphabet.Script.allCases, [.latin, .greek, .cyrillic, .hebrew, .arabic])
        XCTAssertEqual(hebrew.rows.map { $0.joined() }, ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"])
        XCTAssertEqual(arabic.rows.map { $0.joined() }, ["ضصثقفغعهخحج", "شسيبلاتنمكة", "ءظطذدزروى"])
        XCTAssertEqual(hebrew.keys.count, 27, "22 letters and 5 final forms")
        XCTAssertEqual(arabic.keys.count, 31)
        for alphabet in [hebrew, arabic] {
            XCTAssertTrue(alphabet.isCaseless, alphabet.id)
            XCTAssertEqual(alphabet.lettersKeyTitle, "ABC")
            for key in alphabet.keys {
                XCTAssertFalse(alphabet.isCasedLetter(key), key)
                XCTAssertEqual(alphabet.uppercase(key), key)
                XCTAssertEqual(key.unicodeScalars.first?.properties.generalCategory, .otherLetter, key)
            }
        }
        for alphabet in KeyboardAlphabet.catalog where alphabet.script != .hebrew && alphabet.script != .arabic {
            XCTAssertFalse(alphabet.isCaseless, alphabet.id)
            XCTAssertTrue(alphabet.hasShiftSlot, alphabet.id)
            XCTAssertTrue(alphabet.diacritics.isEmpty, alphabet.id)
        }
        XCTAssertFalse(hebrew.hasShiftSlot, "Hebrew has no Shift and nothing in its place")
        XCTAssertTrue(arabic.hasShiftSlot, "Arabic Diacritics takes Shift's place")
        // Hold choices are exact strings: a letter and its points, never normalized.
        XCTAssertEqual(hebrew.variants["ש"]?.map { $0.unicodeScalars.map(\.value) },
                       [[0x5E9, 0x5C1], [0x5E9, 0x5BC, 0x5C1], [0x5E9, 0x5C2], [0x5E9, 0x5BC, 0x5C2]])
        XCTAssertNil(hebrew.variants["כ"], "Unconfirmed on a device")
        XCTAssertEqual(arabic.variants["ا"], ["أ", "إ", "آ", "ء"])
        XCTAssertNil(arabic.variants["ف"])
    }

    func testArabicDiacriticsAreEightSingleCombiningMarksWithUnicodeNames() throws {
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        XCTAssertEqual(arabic.diacritics.map(\.name), ["Fatha", "Damma", "Kasra", "Sukun", "Shadda", "Fathatan", "Dammatan", "Kasratan"])
        XCTAssertEqual(arabic.diacritics.map { $0.mark.unicodeScalars.map(\.value) },
                       [[0x64E], [0x64F], [0x650], [0x652], [0x651], [0x64B], [0x64C], [0x64D]])
        for diacritic in arabic.diacritics {
            let scalar = try XCTUnwrap(diacritic.mark.unicodeScalars.first)
            XCTAssertEqual(scalar.properties.generalCategory, .nonspacingMark)
            XCTAssertEqual(scalar.properties.name, "ARABIC " + diacritic.name.uppercased())
            XCTAssertFalse(diacritic.mark.unicodeScalars.contains("\u{25CC}"), "The dotted circle is only drawn")
        }
        XCTAssertTrue(KeyboardAlphabet.english.diacritics.isEmpty)
        XCTAssertTrue(try XCTUnwrap(KeyboardAlphabet.alphabet(id: "he")).diacritics.isEmpty)
    }

    func testOnlyArabicAndHebrewAddPunctuationToSharedKeys() throws {
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        let hebrew = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "he"))
        XCTAssertEqual(arabic.punctuationHoldChoice(for: ",")?.text, "\u{060C}")
        XCTAssertEqual(arabic.punctuationHoldChoice(for: "?")?.text, "\u{061F}")
        XCTAssertEqual(arabic.punctuationHoldChoice(for: ";")?.text, "\u{061B}")
        XCTAssertNil(arabic.punctuationHoldChoice(for: "$"))
        XCTAssertEqual(hebrew.punctuationHoldChoice(for: "$")?.text, "\u{20AA}")
        XCTAssertNil(hebrew.punctuationHoldChoice(for: ","))
        for alphabet in KeyboardAlphabet.catalog where !alphabet.isCaseless {
            for key in [",", "?", ";", "$"] { XCTAssertNil(alphabet.punctuationHoldChoice(for: key), alphabet.id) }
        }
        for choice in KeyboardPunctuationChoice.all {
            let scalar = try XCTUnwrap(choice.text.unicodeScalars.first)
            XCTAssertEqual(choice.text.unicodeScalars.count, 1)
            XCTAssertEqual(scalar.properties.name, choice.name.uppercased(), choice.name)
        }
        XCTAssertEqual(KeyboardPunctuationChoice.choices(for: "?").map(\.name), ["Arabic Question Mark"])
        XCTAssertEqual(KeyboardPunctuationChoice.choices(for: "$").map(\.text), ["₪"])
        XCTAssertTrue(KeyboardPunctuationChoice.choices(for: ".").isEmpty)
        let note = try XCTUnwrap(KeyboardPunctuationChoice.editorNotes(for: "?", savedHoldChoices: []).first)
        XCTAssertEqual(note.noteLabel, "When using Arabic:")
        XCTAssertEqual(note.noteAccessibilityLabel, "When using Arabic: Arabic Question Mark")
        let shekel = try XCTUnwrap(KeyboardPunctuationChoice.editorNotes(for: "$", savedHoldChoices: []).first)
        XCTAssertEqual(shekel.noteLabel, "When using Hebrew:")
        XCTAssertEqual(shekel.noteAccessibilityLabel, "When using Hebrew: New Sheqel Sign")
        XCTAssertTrue(KeyboardPunctuationChoice.editorNotes(for: "?", savedHoldChoices: ["¿"]).isEmpty)
        XCTAssertTrue(KeyboardPunctuationChoice.editorNotes(for: ".", savedHoldChoices: []).isEmpty)
    }
}
