import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class AutoCapitalizationPolicyTests: XCTestCase {
    func testSettingsWording() {
        XCTAssertEqual(AutoCapitalizationMode.allCases.map(\.title), ["Follow App", "Off", "Sentences", "Words", "All Characters"])
        XCTAssertEqual(AutoCapitalizationMode.allCases.map(\.summary), [
            "Use the typing app’s capitalization preference.",
            "Use capitals only when you choose Shift or Caps Lock.",
            "Start detected sentences with a capital letter.",
            "Start detected words with a capital letter.",
            "Use capitals for letter keys that support them."])
        XCTAssertEqual(AutoCapitalizationCopy.title, "Auto-Capitalization")
        XCTAssertEqual(AutoCapitalizationCopy.header, "Choose when letter keys use capitals automatically. This affects new typing, not existing text.")
        XCTAssertEqual(AutoCapitalizationCopy.footer, "Some fields turn off automatic capitals. Languages without capital letters are unchanged.")
        XCTAssertEqual(AutoCapitalizationCopy.footerDetail, "Custom key text, pasted text and symbols stay exactly as entered.")
        XCTAssertEqual(AutoCapitalizationCopy.change(from: .followApp, to: .allCharacters), "Auto-Capitalization: Follow App → All Characters")
    }

    func testHostTraitMappingMatchesUIKitRawValues() {
        XCTAssertEqual(KeyboardAutoCapitalizationPolicy.hostMode(rawValue: 0), KeyboardAutomaticCapitalization.none)
        XCTAssertEqual(KeyboardAutoCapitalizationPolicy.hostMode(rawValue: 1), .words)
        XCTAssertEqual(KeyboardAutoCapitalizationPolicy.hostMode(rawValue: 2), .sentences)
        XCTAssertEqual(KeyboardAutoCapitalizationPolicy.hostMode(rawValue: 3), .allCharacters)
        XCTAssertEqual(KeyboardAutoCapitalizationPolicy.hostMode(rawValue: 99), .sentences)
    }

    func testFollowAppKeepsTheHostAndOtherModesOverrideIt() {
        for host in KeyboardAutomaticCapitalization.allCases {
            XCTAssertEqual(KeyboardAutoCapitalizationPolicy.effectiveMode(setting: .followApp, host: host, permitsAssistance: true), host)
            XCTAssertEqual(KeyboardAutoCapitalizationPolicy.effectiveMode(setting: .off, host: host, permitsAssistance: true), KeyboardAutomaticCapitalization.none)
            XCTAssertEqual(KeyboardAutoCapitalizationPolicy.effectiveMode(setting: .sentences, host: host, permitsAssistance: true), .sentences)
            XCTAssertEqual(KeyboardAutoCapitalizationPolicy.effectiveMode(setting: .words, host: host, permitsAssistance: true), .words)
            XCTAssertEqual(KeyboardAutoCapitalizationPolicy.effectiveMode(setting: .allCharacters, host: host, permitsAssistance: true), .allCharacters)
            // URL, email, credentials and other restricted fields: never automatic capitals.
            for setting in AutoCapitalizationMode.allCases {
                XCTAssertEqual(KeyboardAutoCapitalizationPolicy.effectiveMode(setting: setting, host: host, permitsAssistance: false),
                               KeyboardAutomaticCapitalization.none)
            }
        }
    }

    func testDecisionsAtStartPunctuationWordsAndRestrictedFields() {
        func capitalize(_ setting: AutoCapitalizationMode, host: Int = 2, permits: Bool = true, _ before: String?) -> Bool {
            KeyboardAutoCapitalizationPolicy.shouldCapitalize(setting: setting, hostRawValue: host, permitsAssistance: permits, before: before)
        }
        // Follow App is today's behavior for each host request.
        XCTAssertTrue(capitalize(.followApp, ""))
        XCTAssertTrue(capitalize(.followApp, "Hi. "))
        XCTAssertFalse(capitalize(.followApp, "Hi "))
        XCTAssertFalse(capitalize(.followApp, host: 0, ""))
        XCTAssertTrue(capitalize(.followApp, host: 1, "Hi "))
        // Off prevents automatic capitals even where the app asks for them.
        XCTAssertFalse(capitalize(.off, host: 3, ""))
        XCTAssertFalse(capitalize(.off, nil))
        // Sentences: start, after a terminator and space, after a newline;
        // not inside decimals or domains, and not before the space.
        XCTAssertTrue(capitalize(.sentences, host: 0, nil))
        XCTAssertTrue(capitalize(.sentences, host: 0, "Done. "))
        XCTAssertTrue(capitalize(.sentences, host: 0, "Done\n"))
        XCTAssertFalse(capitalize(.sentences, host: 0, "3."))
        XCTAssertFalse(capitalize(.sentences, host: 0, "example."))
        XCTAssertFalse(capitalize(.sentences, host: 0, "e.g. the"))
        // Words: after a space, not inside a word or after an apostrophe.
        XCTAssertTrue(capitalize(.words, host: 0, "new "))
        XCTAssertFalse(capitalize(.words, host: 0, "new"))
        XCTAssertFalse(capitalize(.words, host: 0, "don’"))
        XCTAssertTrue(capitalize(.allCharacters, host: 0, "abc"))
        // Restricted fields stay literal in every mode.
        for setting in AutoCapitalizationMode.allCases { XCTAssertFalse(capitalize(setting, permits: false, "")) }
    }
}
