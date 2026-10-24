import XCTest
import UIKit

/// Unicode search in the keyboard: query keys, results, deletes and the app's catalog.
@MainActor
final class KeyboardSearchUITests: UniboardUITestCase {
    func testSystemKeyboardSearchOffersTextAndEmojiFormsSeparately() throws {
        try requirePhoneKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: true, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("snowman")
        let text = app.buttons["keyboard.emoji.2603-FE0E"].firstMatch, emoji = app.buttons["keyboard.emoji.2603-FE0F"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), "The text form is its own result")
        XCTAssertTrue(emoji.exists, "So is the emoji form")
        attachScreenshot("A searched character with both forms appears twice")
        emoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals("☃\u{FE0F}"))
        text.tap()
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value), [0x2603, 0xFE0F, 0x2603, 0xFE0E])
    }

    func testAppSearchDoneStaysInsideKeyboardAndDismissesWithoutChangingQuery() throws {
        try requirePhoneKeyboardIntegration()
        _ = openSystemKeyboardHost(unicodeBrowse: false, afterSetUpLaunch: true)
        restoreEnglishKeyboard()
        app.terminate(); app.launch()
        selectAppTab("Explore")
        searchUnicode("snow")
        let field = app.textFields["unicodeSearch"].firstMatch
        XCTAssertTrue(field.waitUntilValueEquals("snow"))
        selectUniboardKeyboard(input: field, expectedHost: "snow")
        let done = app.buttons["keyboard.return"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done key")
        guard let root = measuredKeyboardSurfaceFrame() else { XCTFail("Expected the actual keyboard allocation"); return }
        XCTAssertTrue(root.insetBy(dx: -1, dy: -1).contains(done.frame))
        XCTAssertFalse(app.toolbars.buttons["Done"].firstMatch.exists, "No floating app-owned Done accessory remains")
        attachScreenshot("Live search uses the Done key inside Uniboard")
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.uniboardKeyboardIsVisible() }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(field.waitUntilValueEquals("snow"), "Done dismisses without inserting a newline or changing the query")
        attachScreenshot("Keyboard Done dismisses while retaining the exact live search")
    }

    /// In Unicode search a tap edits the query; holding a character key types
    /// it into the host exactly once and leaves the query as it was.
    func testSystemKeyboardQueryHoldTypesTheKeyIntoTheHostOnce() throws {
        try requirePhoneKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        // U opens search with its own keys.
        ensureUnicodeToolbarVisible()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"))
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        typeKeyboardQueryKeys("ca")
        XCTAssertTrue(search.waitUntilValueEquals("ca"), "Taps edit the query")
        XCTAssertEqual(input.value as? String, "", "Query taps never edit the host")

        let t = app.buttons["keyboard.query.t"].firstMatch
        XCTAssertTrue(t.waitForExistence(timeout: 5))
        XCTAssertEqual(t.label, "t", "The hold keeps the key's label")
        // Well past the 0.4 s threshold: still a single insert, no repeat.
        t.press(forDuration: 1.2)
        XCTAssertTrue(input.waitUntilValueEquals("t"), "Holding t types it into the host: \(input.value as? String ?? "nil")")
        XCTAssertTrue(search.waitUntilValueEquals("ca"), "Holding leaves the query unchanged")
        assertValueRemainsAfterRelease(input, equals: "t")
        XCTAssertEqual(search.value as? String, "ca", "Releasing the hold adds no query character")
        attachScreenshot("Holding a search key typed t into the host while the query stays ca")

        typeKeyboardQueryKeys("r")
        XCTAssertTrue(search.waitUntilValueEquals("car"), "A tap after the hold edits the query again")
        XCTAssertEqual(input.value as? String, "t")
        attachScreenshot("A tap after the hold continues the query as car")
    }

    func testSystemKeyboardSearchKeysKeepTypingHeightAndDeletesUseSeparateDestinations() throws {
        try requireKeyboardIntegration()
        var context = "Keep the receiving document."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        enterKeyboardQuery("cat")
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let upper = app.buttons["keyboard.delete"].firstMatch
        let lower = app.buttons["keyboard.query.delete"].firstMatch
        let digit = app.buttons["keyboard.query.1"].firstMatch
        let letter = app.buttons["keyboard.query.q"].firstMatch
        for key in [digit, letter, lower] {
            XCTAssertTrue(key.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(key.frame.height, 41)
            XCTAssertEqual(key.frame.height, upper.frame.height, accuracy: 1)
            XCTAssertTrue(app.frame.contains(key.frame))
        }
        search.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 36, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        lower.tap()
        XCTAssertTrue(search.waitUntilValueEquals("arrowcat"), "The lower Delete removes before the local middle caret")
        upper.tap()
        context.removeLast()
        XCTAssertTrue(input.waitUntilValueEquals(context), "The header Delete edits the host while search is focused")
        XCTAssertTrue(search.waitUntilValueEquals("arrowcat"), "The header Delete preserves the query and its caret")
        XCTAssertFalse(app.buttons["keyboard.query.:"].exists)
        typeKeyboardQueryKeys(" ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        XCTAssertEqual(input.value as? String, context)
        // Repeated discrete taps must not leave either native key latched off.
        for expected in ["arrowcat", "arrocat", "arrcat", "arcat", "acat", "cat"] {
            lower.tap()
            XCTAssertTrue(search.waitUntilValueEquals(expected))
        }
        upper.tap()
        context.removeLast()
        XCTAssertTrue(input.waitUntilValueEquals(context), "The header Delete still targets the host at the query start")
        XCTAssertTrue(search.waitUntilValueEquals("cat"))
        lower.tap()
        XCTAssertTrue(search.waitUntilValueEquals("cat"), "Lower Delete at query start does not fall through to host")
        typeKeyboardQueryKeys("u+2603")
        XCTAssertTrue(search.waitUntilValueEquals("u+2603cat"))
        XCTAssertEqual(input.value as? String, context)
        enterKeyboardQuery("u+2603")
        // U+2603 has text and emoji forms, so search shows it as two emoji-form keys.
        let snowman = app.buttons["keyboard.emoji.2603-FE0E"].firstMatch
        XCTAssertTrue(snowman.waitForExistence(timeout: 10))
        snowman.press(forDuration: 0.8)
        app.buttons["keyboard.properties.close"].tap()
        lower.tap()
        XCTAssertTrue(search.waitUntilValueEquals("u+260"), "Returning from properties must leave query deletion usable")
        typeKeyboardQueryKeys("3")
        lower.press(forDuration: 0.8)
        let remaining = search.value as? String ?? ""
        XCTAssertTrue("u+2603".hasPrefix(remaining == "No query" ? "" : remaining))
        XCTAssertLessThan(remaining == "No query" ? 0 : remaining.count, 5)
        assertValueRemainsAfterRelease(search, equals: remaining)
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Full-height search keys with separate host and query Delete controls")
        closeKeyboardSearch()
        ensureUnicodeToolbarVisible()
        upper.tap()
        XCTAssertTrue(input.waitUntilValueEquals(String(context.dropLast())), "Returning to English restores host Delete")
        XCTAssertTrue(search.waitUntilValueEquals(remaining))
    }

    func testSystemKeyboardQueryResultStripScrollsWithoutInserting() throws {
        try requirePhoneKeyboardIntegration()
        let context = "Scrolling does not type."
        let input = openSystemKeyboardHost(initialText: context, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("arrow")
        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.character."))
        let first = results.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let original = first.frame
        let originalKey = app.buttons[first.identifier].firstMatch
        XCTAssertTrue(app.frame.contains(original))
        let visible = results.allElementsBoundByIndex.filter { self.app.frame.contains($0.frame) && $0.frame.width > 0 }
        XCTAssertGreaterThan(visible.count, 3)
        guard let last = visible.last else { return XCTFail("Expected visible search result keys") }
        let start = last.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !originalKey.exists || originalKey.frame.minX < original.minX - 20
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, "Drag must actually scroll the result strip")
        XCTAssertEqual(input.value as? String, context, "Scrolling from a character key must never insert it")
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("arrow"))
        XCTAssertGreaterThanOrEqual(app.buttons["keyboard.query.q"].firstMatch.frame.height, 41)
        attachScreenshot("Search result keys scroll horizontally without shrinking query keys or inserting")
    }

    func testSystemKeyboardLandscapeScalarAndEmojiResultsStayClear() throws {
        try requireKeyboardIntegration()
        let context = "Every character belongs here."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, afterSetUpLaunch: true)
        defer {
            XCUIDevice.shared.orientation = .portrait
            restoreEnglishKeyboard()
        }
        XCTAssertTrue(app.buttons["keyboard.typing.key.q"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Daily English keyboard with the fixed number row and no optional toolbar")
        enterKeyboardQuery("u+1f680")
        settleKeyboardOrientation(.landscapeLeft)
        let scalar = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(scalar.waitForExistence(timeout: 10))
        XCTAssertTrue(scalar.isHittable)
        XCTAssertTrue(app.frame.contains(scalar.frame))
        // iPhone landscape search uses Apple's 32-point landscape key rows (KeyboardLayoutPolicy.compactSearchKeyHeight).
        XCTAssertGreaterThanOrEqual(app.buttons["keyboard.query.q"].firstMatch.frame.height, 32)
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Landscape scalar results have fully visible unmasked keycaps")
        closeKeyboardSearch()
        selectKeyboardSection("emojis")
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        let emoji = app.buttons["keyboard.emoji.1F680"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        XCTAssertTrue(emoji.isHittable)
        XCTAssertTrue(app.frame.contains(emoji.frame))
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Landscape emoji results have fully visible unmasked keycaps")
        // Switching back reruns the kept query against symbols rather than
        // reusing the emoji results.
        closeKeyboardSearch()
        selectKeyboardSection("symbols")
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        XCTAssertTrue(app.buttons["keyboard.character.U+1F680"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, context, "Changing the result kind must not insert text")
    }

    func testSystemKeyboardHeldDeleteKeepsQueryAndHostScopesSeparate() throws {
        try requireKeyboardIntegration()
        let context = "Retain this host context."
        let input = openSystemKeyboardHost(initialText: context, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        let query = "abcdefghijklmnop"
        enterKeyboardQuery(query)
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let delete = app.buttons["keyboard.delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))

        app.buttons["keyboard.query.delete"].press(forDuration: 0.75)
        let remainingQuery = search.value as? String ?? ""
        XCTAssertFalse(remainingQuery.isEmpty)
        XCTAssertTrue(query.hasPrefix(remainingQuery), "Held search delete may only remove the query suffix")
        XCTAssertGreaterThanOrEqual(query.count - remainingQuery.count, 2,
                                    "The real hold must exercise repeating deletion, not only one tap")
        XCTAssertEqual(input.value as? String, context, "Query deletion must never reach the host")
        assertValueRemainsAfterRelease(search, equals: remainingQuery)
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Held query delete stops on release without changing host text")

        // Keep search focused while holding the toolbar's host Delete.
        XCTAssertTrue(search.waitUntilValueEquals(remainingQuery))
        delete.press(forDuration: 0.75)
        let remainingHost = input.value as? String ?? ""
        XCTAssertFalse(remainingHost.isEmpty)
        XCTAssertTrue(context.hasPrefix(remainingHost), "Toolbar delete may only remove the host suffix")
        XCTAssertGreaterThanOrEqual(context.count - remainingHost.count, 2,
                                    "The real toolbar hold must exercise repeating host deletion")
        XCTAssertEqual(search.value as? String, remainingQuery, "Toolbar host deletion must retain the query")
        assertValueRemainsAfterRelease(input, equals: remainingHost)
        XCTAssertTrue(search.waitUntilValueEquals(remainingQuery))
        attachScreenshot("Held host delete stops on release and preserves the focused query")
    }

    func testSystemKeyboardUsesAppCatalogChoiceWithoutEditionSelector() throws {
        try requireKeyboardIntegration()
        let context = "App settings choose the offline Unicode catalog."
        defer { restoreEnglishKeyboard() }
        let choices: [(String, [(String, String)])] = [
            ("older", [("10940", "")]),
            ("previous", [("10940", "17.0"), ("0558", "")]),
            ("latest", [("0558", "18.0")])
        ]
        for (edition, fixtures) in choices {
            selectAppEdition(edition)
            let input = openSystemKeyboardHost(initialText: context)
            // The keyboard has no edition readout or setter. Its actual
            // assigned/unassigned results below prove the app-owned choice.
            assertKeyboardHasNoSettingsMenu()
            for (codepoint, age) in fixtures {
                enterKeyboardQuery("u+\(codepoint.lowercased())")
                let result = app.buttons["keyboard.character.U+\(codepoint)"].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 10))
                XCTAssertTrue(result.waitUntilLabelHasSuffix(age.isEmpty ? ", Unassigned" : ", U\(age)"))
                XCTAssertEqual(input.value as? String, context, "App edition synchronization must not edit the host")
                closeKeyboardSearch()
                assertKeyboardHasNoSettingsMenu()
            }
            attachScreenshot("Real keyboard follows app Settings \(edition) without a catalog selector")
        }
        restoreEnglishKeyboard()
        selectAppEdition("latest")
    }
}
