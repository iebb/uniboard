#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class AppSearchFieldTests: XCTestCase {
    private func withVisibleField(_ body: (AppSearchTextField) throws -> Void) throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        let field = AppSearchTextField()
        field.frame = CGRect(x: 16, y: 100, width: 358, height: 40)
        controller.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        try body(field)
    }

    private func select(_ range: NSRange, in field: UITextField) throws {
        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: range.location))
        let end = try XCTUnwrap(field.position(from: start, offset: range.length))
        field.selectedTextRange = field.textRange(from: start, to: end)
    }

    private func selectedRange(in field: UITextField) throws -> NSRange {
        let range = try XCTUnwrap(field.selectedTextRange)
        return NSRange(location: field.offset(from: field.beginningOfDocument, to: range.start),
                       length: field.offset(from: range.start, to: range.end))
    }

    func testLiteralSearchTraitsDynamicTypeAndTextFieldIdentity() async {
        let field = AppSearchTextField()
        field.configure(text: "", placeholder: "Search Unicode", identifier: "unicodeSearch") { _ in }
        XCTAssertEqual(field.accessibilityIdentifier, "unicodeSearch")
        XCTAssertEqual(field.accessibilityLabel, "Search Unicode")
        XCTAssertEqual(field.placeholder, "Search Unicode")
        XCTAssertEqual(field.autocapitalizationType, .none)
        XCTAssertEqual(field.autocorrectionType, .no)
        XCTAssertEqual(field.spellCheckingType, .no)
        XCTAssertEqual(field.smartQuotesType, .no)
        XCTAssertEqual(field.smartDashesType, .no)
        XCTAssertEqual(field.smartInsertDeleteType, .no)
        XCTAssertEqual(field.returnKeyType, .done)
        XCTAssertEqual(field.clearButtonMode, .never)
        XCTAssertTrue(field.adjustsFontForContentSizeCategory)
        XCTAssertEqual(field.font, UIFont.preferredFont(forTextStyle: .body))
        XCTAssertTrue(field.delegate === field)
    }

    func testNativeEditingEventsPublishTheExactUnicodeQuery() async {
        let field = AppSearchTextField()
        var edits: [String] = []
        field.configure(text: "", placeholder: "Search", identifier: "unicodeSearch") { edits.append($0) }
        for query in ["u+1f680", "woman technologist", "👩‍💻", "e\u{301}", ""] {
            field.text = query
            field.sendActions(for: .editingChanged)
        }
        XCTAssertEqual(edits.map { Array($0.utf16) },
                       ["u+1f680", "woman technologist", "👩‍💻", "e\u{301}", ""].map { Array($0.utf16) })
    }

    func testUnchangedBindingRefreshPreservesNativeSelectionAndUsesTheNewestCallback() async throws {
        try withVisibleField { field in
            var oldEdits = 0
            var newEdits: [String] = []
            field.configure(text: "arrow cat", placeholder: "Search", identifier: "unicodeSearch") { _ in oldEdits += 1 }
            XCTAssertTrue(field.becomeFirstResponder())
            try select(NSRange(location: 6, length: 3), in: field)
            field.configure(text: "arrow cat", placeholder: "Updated search", identifier: "blockSearch") { newEdits.append($0) }
            XCTAssertEqual(try selectedRange(in: field), NSRange(location: 6, length: 3))
            XCTAssertTrue(field.isFirstResponder)
            XCTAssertEqual(field.accessibilityIdentifier, "blockSearch")
            XCTAssertEqual(oldEdits, 0)
            field.text = "arrow dog"
            field.sendActions(for: .editingChanged)
            XCTAssertEqual(newEdits, ["arrow dog"])
            XCTAssertEqual(oldEdits, 0)
        }
    }

    func testExternalClearIsIntentionalAndDoesNotEchoAnotherBindingWrite() async throws {
        try withVisibleField { field in
            var edits: [String] = []
            field.configure(text: "u+1f680", placeholder: "Search", identifier: "unicodeSearch") { edits.append($0) }
            XCTAssertTrue(field.becomeFirstResponder())
            try select(NSRange(location: 2, length: 4), in: field)
            field.configure(text: "", placeholder: "Search", identifier: "unicodeSearch") { edits.append($0) }
            XCTAssertEqual(field.text, "")
            XCTAssertEqual(try selectedRange(in: field), NSRange(location: 0, length: 0))
            XCTAssertTrue(field.isFirstResponder)
            XCTAssertTrue(edits.isEmpty, "The binding already contains the external clear")
        }
    }

    func testCanonicallyEquivalentExternalTextStillUpdatesExactUTF16() async {
        let field = AppSearchTextField()
        let composed = "é", decomposed = "e\u{301}"
        XCTAssertEqual(composed, decomposed)
        field.configure(text: composed, placeholder: "Search", identifier: "unicodeSearch") { _ in XCTFail("Configure cannot publish") }
        field.configure(text: decomposed, placeholder: "Search", identifier: "unicodeSearch") { _ in XCTFail("Configure cannot publish") }
        XCTAssertEqual(Array((field.text ?? "").utf16), Array(decomposed.utf16))
    }

    func testKeyboardDoneResignsWithoutChangingOrPublishingTheQuery() async throws {
        try withVisibleField { field in
            var edits: [String] = []
            field.configure(text: "u+0041", placeholder: "Search", identifier: "unicodeSearch") { edits.append($0) }
            XCTAssertTrue(field.becomeFirstResponder())
            XCTAssertEqual(field.delegate?.textFieldShouldReturn?(field), true)
            XCTAssertFalse(field.isFirstResponder)
            XCTAssertEqual(field.text, "u+0041")
            XCTAssertTrue(edits.isEmpty)
        }
    }

    func testSearchHasNoAccessoryOrFloatingConfirmationControls() async {
        let field = AppSearchTextField()
        XCTAssertNil(field.inputAccessoryView)
        field.configure(text: "arrows", placeholder: "Search", identifier: "unicodeSearch") { _ in }
        XCTAssertNil(field.inputAccessoryView, "Done belongs to the keyboard, not an app accessory toolbar")
        XCTAssertEqual(field.returnKeyType, .done)
    }
}
#endif
