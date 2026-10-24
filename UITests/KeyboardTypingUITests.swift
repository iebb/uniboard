import XCTest
import UIKit

/// English typing, Return, the 123 page, auto-capitalization and compact layouts.
@MainActor
final class KeyboardTypingUITests: UniboardUITestCase {
    func testSystemKeyboardEnglishTypingAndUnicodeQueryRouting() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals("off"))
        XCTAssertFalse(app.buttons["keyboard.collapse"].exists)
        // English typing keeps the Unicode toolbar hidden: U opens search with
        // its own keys, so the search field and header delete live there.
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let space = app.buttons["keyboard.space"].firstMatch
        let delete = app.buttons["keyboard.delete"].firstMatch
        let lowerDelete = app.buttons["keyboard.typing.delete"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "The sentence-capitalizing host begins with a capital")
        assertHeaderDeleteAtTopRight()
        XCTAssertFalse(search.exists, "English typing has no search field until U opens search")
        attachScreenshot("Default English QWERTY offers sentence capitalization with the Unicode toolbar hidden")

        typeHostTypingKeys("hello")
        XCTAssertTrue(input.waitUntilValueEquals("Hello"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        lowerDelete.tap()
        XCTAssertTrue(input.waitUntilValueEquals("Hell"))
        typeHostTypingKeys("o")
        XCTAssertTrue(input.waitUntilValueEquals("Hello"))
        assertRetainedQueryThroughU("No query", "The lower English delete must edit only the host")
        space.tap()
        typeHostTypingKeys("world")
        XCTAssertTrue(input.waitUntilValueEquals("Hello world"))
        // One synthesized double tap exercises the actual two Space touches
        // within the documented shortcut interval; separate AX taps can idle
        // for longer than that interval and would test a different gesture.
        space.doubleTap()
        XCTAssertTrue(input.waitUntilValueEquals("Hello world. "))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        typeHostTypingKeys("next")
        XCTAssertTrue(input.waitUntilValueEquals("Hello world. Next"))
        app.buttons["keyboard.return"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("Hello world. Next\n"))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"), "A user can override automatic sentence capitalization")
        typeHostTypingKeys("i")
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        typeHostTypingKeys("p")
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"), "Manual Shift applies once")
        typeHostTypingKeys("q")
        shift.doubleTap()
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"))
        typeHostTypingKeys("abc")
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"), "Locked Shift survives multiple letters")
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        typeHostTypingKeys("d")
        var expected = "Hello world. Next\niPqABCd"
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        attachScreenshot("English sentence, one-shot Shift and caps lock produce exact native host text")

        // The digit row is on the main keyboard, above the letters.
        let one = app.buttons["keyboard.typing.number.1"].firstMatch
        XCTAssertTrue(one.waitUntilValueEquals("letters"), "The main keyboard shows its digit row")
        one.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1"))
        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.symbols"].firstMatch.waitUntilValueEquals("numbers"))
        typeHostTypingKeys("?", layout: "numbers")
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1?"))
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.'")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1"))
        typeHostTypingKeys("?", layout: "numbers")
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1?"))
        app.buttons["keyboard.typing.symbols"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.letters"].firstMatch.waitUntilValueEquals("symbols"))
        typeHostTypingKeys("[]", layout: "symbols")
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1?[]"))
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.'")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1?["))
        typeHostTypingKeys("]", layout: "symbols")
        XCTAssertTrue(input.waitUntilValueEquals(expected + "1?[]"))
        app.buttons["keyboard.typing.letters"].tap()
        typeHostTypingKeys("e")
        expected += "1?[]e"
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        assertHeaderDeleteAtTopRight()
        lowerDelete.tap()
        expected.removeLast()
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        assertRetainedQueryThroughU("No query", "Host letters, punctuation and delete never edit Unicode search")

        openUnicodeBrowse()
        selectKeyboardSection("emojis")
        enterKeyboardQuery("head shaking horizontally")
        XCTAssertEqual(input.value as? String, expected)
        let emoji = app.buttons["keyboard.emoji.1F642-200D-2194-FE0F"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        emoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected + "🙂‍↔️"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       expected.unicodeScalars.map(\.value) + [0x1F642, 0x200D, 0x2194, 0xFE0F])
        closeKeyboardSearch()
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        lowerDelete.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected), "The lower English backspace removes the complete inserted emoji grapheme")
        assertRetainedQueryThroughU("head shaking horizontally", "Done and English delete keep the exact local query")

        enterKeyboardQuery("cat")
        search.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 36, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        assertLowerDeleteInKeyRow("keyboard.query.delete", beside: "keyboard.query.-")
        app.buttons["keyboard.query.delete"].tap()
        XCTAssertTrue(search.waitUntilValueEquals("arrowcat"))
        space.doubleTap()
        XCTAssertTrue(search.waitUntilValueEquals("arrow  cat"), "Query Space stays literal; it never applies host double-space punctuation")
        XCTAssertEqual(input.value as? String, expected, "Query case, cursor and deletion stay independent of the host")
        attachScreenshot("Unicode query preserves literal case and double spaces at its moved caret")
        closeKeyboardSearch()
        typeHostTypingKeys("x")
        expected += "x"
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        assertRetainedQueryThroughU("arrow  cat", "English typing after Done retains the exact local query")
        openUnicodeBrowse()
        XCTAssertTrue(search.waitUntilValueEquals("arrow  cat"))
        let clear = app.buttons["keyboard.search.clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        XCTAssertEqual(input.value as? String, expected)
        selectKeyboardSection("symbols")
        enterKeyboardQuery("u+1f680")
        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 10))
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected + "🚀"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       expected.unicodeScalars.map(\.value) + [0x1F680])
        closeKeyboardSearch()
        // U opens search with its keys; there the header delete edits the
        // host, not the query, and U returns to English typing.
        ensureUnicodeToolbarVisible()
        assertHeaderDeleteAtTopRight()
        delete.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        XCTAssertTrue(search.waitUntilValueEquals("u+1f680"), "The header delete edits the host, not the query")
        app.buttons["keyboard.toggleUnicodeToolbar"].tap()
        assertHostTypingPanel()
        XCTAssertTrue(app.buttons["keyboard.typing.shift"].waitUntilValueEquals("lowercase"))
        // e, then its seven English accents: è é ê ë ē ė ę.
        chooseHeldKeyboardOption(app.buttons["keyboard.typing.key.e"].firstMatch,
                                 optionCount: 8, selectedIndex: 2, extraActions: 0)
        XCTAssertTrue(input.waitUntilValueEquals(expected + "é"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value), expected.unicodeScalars.map(\.value) + [0xE9])
        lowerDelete.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        assertRetainedQueryThroughU("u+1f680", "English diacritic selection must not edit the retained Unicode query")
        attachScreenshot("English and Unicode share exact host insertion while retaining an isolated local query")
    }

    /// Settings → Keyboard → Auto-Capitalization sits after Customize Keys,
    /// lists the five modes with Follow App by default, and Words makes the
    /// real keyboard start each new word with a capital.
    func testAutoCapitalizationSettingWordsCapitalizesEachNewWordInTheKeyboard() throws {
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); setAppAutoCapitalization("follow_app") }
        openAppSettings()
        let row = app.buttons["keyboardAutoCapitalization"].firstMatch
        revealByScrolling(row, in: app)
        let customize = app.descendants(matching: .any)["keyboardKeySettings"].firstMatch
        XCTAssertTrue(customize.exists)
        XCTAssertGreaterThan(row.frame.minY, customize.frame.minY, "Auto-Capitalization follows Customize Keys")
        XCTAssertTrue(row.label.contains("Auto-Capitalization"), row.label)
        XCTAssertTrue(row.label.contains("Follow App") || (row.value as? String) == "Follow App", "Follow App is the default: \(row.label)")
        row.tap()
        XCTAssertTrue(app.navigationBars["Auto-Capitalization"].firstMatch.waitForExistence(timeout: 5))
        let modes = ["follow_app", "off", "sentences", "words", "all_characters"]
        var previousY = -CGFloat.infinity
        for mode in modes {
            let option = app.buttons["autoCapitalization.\(mode)"].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), mode)
            XCTAssertGreaterThan(option.frame.minY, previousY, "The modes are listed in order")
            XCTAssertGreaterThanOrEqual(option.frame.height, 44, "Each mode is a full-row target")
            previousY = option.frame.minY
        }
        XCTAssertTrue(app.buttons["autoCapitalization.follow_app"].firstMatch.isSelected)
        let words = app.buttons["autoCapitalization.words"].firstMatch
        XCTAssertEqual(words.label, "Words")
        XCTAssertEqual(words.value as? String, "Start detected words with a capital letter.")
        words.tap()
        XCTAssertTrue(words.waitUntilSelected())
        XCTAssertFalse(app.buttons["autoCapitalization.follow_app"].firstMatch.isSelected, "Only one mode is checked")
        attachScreenshot("Auto-Capitalization with Words chosen")
        app.navigationBars["Auto-Capitalization"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Words") || (row.value as? String) == "Words", "The row shows the choice: \(row.label)")

        try requirePhoneKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        typeHostTypingKeys("a")
        XCTAssertTrue(input.waitUntilValueEquals("A"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        typeHostTypingKeys("b")
        app.buttons["keyboard.space"].firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals("Ab "))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "Words capitalizes after a space, where the host's Sentences would not")
        typeHostTypingKeys("c")
        XCTAssertTrue(input.waitUntilValueEquals("Ab C"))
        attachScreenshot("Words capitalizes each new word in the keyboard")
    }

    func testSystemKeyboardEnglishReturnActionsRestoreLetterKeys() throws {
        try requireKeyboardIntegration()
        var input = openSystemKeyboardHost(unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let q = app.buttons["keyboard.typing.key.q"].firstMatch

        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        openUnicodeBrowse()
        selectKeyboardSection("symbols")
        enterKeyboardQuery("u+0061")
        let literalA = app.buttons["keyboard.character.U+0061"].firstMatch
        XCTAssertTrue(literalA.waitForExistence(timeout: 10))
        literalA.tap()
        XCTAssertTrue(input.waitUntilValueEquals("a"), "Unicode insertion must preserve the original lowercase scalar")
        closeKeyboardSearch()
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"), "Returning to English must refresh sentence case from the actual host document")
        typeHostTypingKeys("b")
        XCTAssertTrue(input.waitUntilValueEquals("ab"), "A stale initial capital must not uppercase the next host letter")
        attachScreenshot("English capitalization refreshes after literal Unicode insertion")

        // Start another real empty host document for the page handoff checks;
        // do not erase text or change the keyboard through hidden test state.
        restoreEnglishKeyboard()
        input = openSystemKeyboardHost(unicodeBrowse: false)
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.symbols"].firstMatch.waitUntilValueEquals("numbers"))
        openUnicodeBrowse()
        let abc = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        XCTAssertTrue(abc.waitUntilValueEquals("query"), "Unicode opens straight into search")
        abc.tap()
        assertHostTypingPanel()
        XCTAssertTrue(q.waitUntilValueEquals("letters"), "ABC must restore letter keys instead of the prior number page")
        XCTAssertTrue(q.isHittable)
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        XCTAssertEqual(input.value as? String, "", "Page changes and ABC must not enter host text")
        typeHostTypingKeys("q")
        XCTAssertTrue(input.waitUntilValueEquals("Q"))
        attachScreenshot("ABC returns from Unicode to actual English letters after the number page")

        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.symbols"].firstMatch.waitUntilValueEquals("numbers"))
        app.buttons["keyboard.typing.symbols"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.letters"].firstMatch.waitUntilValueEquals("symbols"))
        enterKeyboardQuery("cat")
        XCTAssertEqual(input.value as? String, "Q")
        closeKeyboardSearch()
        XCTAssertTrue(q.waitUntilValueEquals("letters"), "Done must restore English letter keys instead of the prior symbol page")
        XCTAssertTrue(q.isHittable)
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        // English typing unmounts the Unicode toolbar; U reopens it to read the query.
        assertRetainedKeyboardQuery("cat")
        typeHostTypingKeys("q")
        XCTAssertTrue(input.waitUntilValueEquals("Qq"))
        assertRetainedKeyboardQuery("cat", "Restored host letters must not change the retained local query")
        attachScreenshot("Done returns from a Unicode query to actual English letters after the symbol page")
    }

    func testSystemKeyboardEnglishNumberPageRefreshesSentenceCase() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let numbers = app.buttons["keyboard.typing.numbers"].firstMatch
        let letters = app.buttons["keyboard.typing.letters"].firstMatch
        // The digit row is on the main keyboard; on the number page the same
        // row stays, so digits are typed from either page.
        let one = app.buttons["keyboard.typing.number.1"].firstMatch
        let two = app.buttons["keyboard.typing.number.2"].firstMatch

        XCTAssertTrue(input.waitUntilValueEquals(""))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        XCTAssertTrue(one.waitUntilValueEquals("letters"), "The main keyboard shows its digit row")
        XCTAssertTrue(one.isHittable)
        one.tap()
        XCTAssertTrue(input.waitUntilValueEquals("1"))
        assertHostTypingPanel()
        XCTAssertTrue(app.buttons["keyboard.typing.key.a"].firstMatch.waitUntilValueEquals("letters"),
                      "A digit from the main keyboard leaves the letters page in place")
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"),
                      "A host digit must refresh the stale initial capital")
        typeHostTypingKeys("a")
        XCTAssertTrue(input.waitUntilValueEquals("1a"))
        attachScreenshot("A digit from the main keyboard's number row refreshes lowercase")

        numbers.tap()
        XCTAssertTrue(letters.waitUntilValueEquals("numbers"))
        typeHostTypingKeys(".", layout: "numbers")
        XCTAssertTrue(input.waitUntilValueEquals("1a."))
        app.buttons["keyboard.space"].firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals("1a. "))
        letters.tap()
        assertHostTypingPanel()
        XCTAssertTrue(app.buttons["keyboard.typing.key.b"].firstMatch.waitUntilValueEquals("letters"))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"),
                      "ABC must refresh sentence capitalization after number-page punctuation and Space")
        XCTAssertEqual(input.value as? String, "1a. ", "Page changes must preserve the exact host text")
        attachScreenshot("ABC refreshes sentence capitalization after number-page period and Space")

        numbers.tap()
        XCTAssertTrue(letters.waitUntilValueEquals("numbers"))
        XCTAssertTrue(two.waitUntilValueEquals("numbers"), "The digit row stays on the number page")
        two.tap()
        XCTAssertTrue(input.waitUntilValueEquals("1a. 2"))
        letters.tap()
        assertHostTypingPanel()
        XCTAssertTrue(app.buttons["keyboard.typing.key.b"].firstMatch.waitUntilValueEquals("letters"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"),
                      "ABC must refresh the sentence capital after a number-page digit")
        XCTAssertEqual(input.value as? String, "1a. 2", "Switching back to letters must not insert text")
        typeHostTypingKeys("b")
        XCTAssertTrue(input.waitUntilValueEquals("1a. 2b"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        assertHeaderDeleteAtTopRight()
        assertRetainedQueryThroughU("No query", "Host page and case changes must not enter a local query")
        attachScreenshot("ABC refreshes lowercase after a number-page digit")
    }

    func testSystemKeyboardCompactLayoutPreservesVisibleHostAndExactInput() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        setAppUnicodeFonts(false)
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }

        assertKeyboardHasNoSettingsMenu()
        // Unicode opens straight into search, with its keys.
        assertCompactKeyboardGeometry("portrait.opened", input: input, searching: true)
        enterKeyboardQuery("u+1f680")
        XCTAssertEqual(input.value as? String, context)
        assertCompactKeyboardGeometry("portrait.search", input: input, searching: true)
        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 10))
        XCTAssertTrue(rocket.isHittable)
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        attachScreenshot("Compact glass keyboard portrait rocket insertion with visible host context")
        selectKeyboardSection("emojis")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.exists, "Emoji selection keeps the active query interface")
        enterKeyboardQuery("head shaking horizontally")
        XCTAssertEqual(input.value as? String, context + "🚀")
        let emoji = app.buttons["keyboard.emoji.1F642-200D-2194-FE0F"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        emoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀🙂‍↔️"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x1F680, 0x1F642, 0x200D, 0x2194, 0xFE0F])
        closeKeyboardSearch()
        app.buttons["keyboard.typing.delete"].tap() // Done returns to typing, whose Delete is the lower key
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"), "Delete removes the complete ZWJ grapheme")
        selectKeyboardSection("symbols")
        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("landscape.browse", input: input, searching: false)
        enterKeyboardQuery("u+1f680")
        assertCompactKeyboardGeometry("landscape.search", input: input, searching: true)
        XCTAssertTrue(rocket.waitForExistence(timeout: 10))
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀🚀"))
        attachScreenshot("Compact glass keyboard landscape preserves host context and exact insertion")
        closeKeyboardSearch()
        app.buttons["keyboard.typing.delete"].tap() // Done returns to typing, whose Delete is the lower key
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        settleKeyboardOrientation(.portrait)
        assertCompactKeyboardGeometry("portrait.returned.browse", input: input, searching: false)
        enterKeyboardQuery("u+1f680")
        assertCompactKeyboardGeometry("portrait.returned.search", input: input, searching: true)
        XCTAssertEqual(input.value as? String, context + "🚀", "Rotation and query controls never leak into the host")
        attachScreenshot("Compact glass keyboard returns to portrait without stale landscape layout")
        closeKeyboardSearch()
    }
}
