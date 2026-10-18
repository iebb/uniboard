#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardHostInputTraitsTests: XCTestCase {
    private final class MissingTraits: NSObject, UITextInputTraits {}

    func testMissingOptionalProtocolGettersUseDocumentedDefaultsWithoutBridgingNil() {
        let traits = KeyboardHostInputTraits(reading: MissingTraits())
        XCTAssertEqual(traits.keyboardType, .default)
        XCTAssertEqual(traits.capitalization, .sentences)
        XCTAssertEqual(traits.returnKey, .default)
        XCTAssertNil(traits.textContentType)
        XCTAssertTrue(traits.permitsEnglishAssistance)
    }

    func testImplementedContentGetterReturningNilRemainsOptional() {
        let field = UITextField()
        field.textContentType = nil
        let traits = KeyboardHostInputTraits(reading: field)
        XCTAssertNil(traits.textContentType)
        XCTAssertTrue(traits.permitsEnglishAssistance)
    }

    func testIdentifierAddressAndCodeSemanticsDisableAssistanceEvenOnOrdinaryKeyboards() {
        let field = UITextField()
        for keyboard in [UIKeyboardType.default, .asciiCapable, .twitter] {
            field.keyboardType = keyboard
            for content: UITextContentType in [.URL, .emailAddress, .username, .password, .newPassword, .oneTimeCode] {
                field.textContentType = content
                XCTAssertFalse(KeyboardHostInputTraits(reading: field).permitsEnglishAssistance,
                               "Semantic \(content.rawValue) must keep literal input")
            }
        }
    }

    func testOrdinaryNamesAndUnknownFutureSemanticsKeepEnglishAssistance() {
        let field = UITextField()
        field.keyboardType = .default
        for content: UITextContentType? in [nil, .name, .givenName, .familyName, .nickname,
                                           UITextContentType(rawValue: "futureCustomSemanticType")] {
            field.textContentType = content
            XCTAssertTrue(KeyboardHostInputTraits(reading: field).permitsEnglishAssistance)
        }
    }

    func testNonEnglishKeyboardTypesRemainLiteralWithoutSemanticContent() {
        let field = UITextField()
        field.textContentType = nil
        for keyboard: UIKeyboardType in [.URL, .emailAddress, .numbersAndPunctuation, .numberPad,
                                         .decimalPad, .phonePad, .namePhonePad, .webSearch, .asciiCapableNumberPad] {
            field.keyboardType = keyboard
            XCTAssertFalse(KeyboardHostInputTraits(reading: field).permitsEnglishAssistance)
        }
    }

    func testSameDocumentContentChangeIsASignatureBoundaryWithoutTextOrPageChange() {
        let field = UITextField(), document = UUID()
        field.text = "unchanged suffix "
        field.keyboardType = .default
        field.autocapitalizationType = .sentences
        field.returnKeyType = .default
        field.textContentType = nil
        let original = KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field))
        for content: UITextContentType in [.emailAddress, .URL, .username, .password, .newPassword, .oneTimeCode] {
            field.textContentType = content
            let updated = KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field))
            XCTAssertEqual(updated.documentIdentifier, original.documentIdentifier)
            XCTAssertEqual(updated.traits.keyboardType, original.traits.keyboardType)
            XCTAssertEqual(updated.traits.capitalization, original.traits.capitalization)
            XCTAssertEqual(updated.traits.returnKey, original.traits.returnKey)
            XCTAssertNotEqual(updated, original)
            XCTAssertFalse(updated.traits.permitsEnglishAssistance)
            XCTAssertEqual(field.text, "unchanged suffix ")
        }
        field.textContentType = nil
        XCTAssertEqual(KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field)), original)
    }

    func testSignatureAlsoRetainsDocumentAndExistingTraitBoundaries() {
        let field = UITextField(), document = UUID()
        let original = KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field))
        XCTAssertNotEqual(KeyboardHostInputSignature(documentIdentifier: UUID(), traits: original.traits), original)
        field.keyboardType = .emailAddress
        XCTAssertNotEqual(KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field)), original)
        field.keyboardType = original.traits.keyboardType
        field.autocapitalizationType = .allCharacters
        XCTAssertNotEqual(KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field)), original)
        field.autocapitalizationType = original.traits.capitalization
        field.returnKeyType = .send
        XCTAssertNotEqual(KeyboardHostInputSignature(documentIdentifier: document, traits: .init(reading: field)), original)
    }
}
#endif
