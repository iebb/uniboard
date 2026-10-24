import XCTest
import UIKit

/// The quick default check (docs/ui-test-shards.md): one keyboard session
/// that switches Uniboard in, types English, inserts a searched character and
/// a page key. The smoke command adds a few short app tests by name.
@MainActor
final class SmokeUITests: UniboardUITestCase {
    func testKeyboardTypesEnglishInsertsASearchResultAndAPageKey() throws {
        try requirePhoneKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        typeHostTypingKeys("hi")
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (input.value as? String)?.lowercased() == "hi"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 5), .completed,
                       "English keys type into the host: \(String(describing: input.value))")
        let host = (input.value as? String ?? "") + " "
        app.buttons["keyboard.space"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(host))
        enterKeyboardQuery("u+2192")
        XCTAssertEqual(input.value as? String, host, "Query keys edit the query, not the host")
        // U+2192 has no emoji form, so it is a single character key (U+2603 shows as text and emoji forms).
        let arrow = app.buttons["keyboard.character.U+2192"].firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: 10))
        arrow.tap()
        XCTAssertTrue(input.waitUntilValueEquals(host + "\u{2192}"), "A search result inserts its character")
        closeKeyboardSearch()
        selectSymbolBoard("stock-symbols", input: input, context: host + "\u{2192}")
        let bang = symbolBoardKey("!")
        XCTAssertTrue(bang.waitForExistence(timeout: 5))
        bang.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(input.waitUntilValueEquals(host + "\u{2192}!"), "A page key inserts its character")
        attachScreenshot("Smoke: English, a search result and a page key in one session")
    }
}
