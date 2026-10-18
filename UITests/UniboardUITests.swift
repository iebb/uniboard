import XCTest
import UIKit

@MainActor
final class UniboardUITests: XCTestCase {
    private var app: XCUIApplication!
    private struct KeyboardOptionsSnapshot {
        let triggerFrame: CGRect
        let hostText: String
        let queryValue: String
        let optionsValue: String
    }
    private var keyboardOptionsSnapshot: KeyboardOptionsSnapshot?

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.height > self.app.frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
    }

    func testSearchByCharacterNameAndLiteral() {
        searchUnicode("snowman")
        assertCharacterVisible("U+2603")

        searchUnicode("☃")
        let snowman = assertCharacterVisible("U+2603")
        snowman.tap()

        XCTAssertTrue(app.buttons["copyCharacter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["U+2603"].exists)
    }

    func testKeyboardKeySettingsSavesExactChoicesDisablesAndRestoresDefaults() {
        openAppSettings()
        let settings = app.buttons["keyboardKeySettings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        revealByScrolling(settings, in: app)
        settings.tap()
        for id in ["space", "shift", "delete", "return", "layout", "favorites", "unicode", "collapse"] {
            XCTAssertFalse(app.buttons["keySettings.key.utility.\(id)"].exists)
        }
        XCTAssertFalse(app.staticTexts["Function keys"].exists)
        let key = app.buttons["keySettings.key.letter.q"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap()
        XCTAssertTrue(app.navigationBars["Q key"].waitForExistence(timeout: 5), "The selected grid key must open its own editor")
        let gesture = app.buttons["keySettings.gesture.swipeUp"].firstMatch
        XCTAssertTrue(gesture.waitForExistence(timeout: 5))
        gesture.tap()
        let behavior = app.segmentedControls["keySettings.behavior"]
        XCTAssertTrue(behavior.waitForExistence(timeout: 5))
        behavior.buttons["Custom"].tap()
        let choice = app.textFields["keySettings.choice.0"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        choice.typeText("xy")
        XCTAssertTrue(choice.waitUntilValueEquals("xy"))
        app.buttons["keySettings.save"].tap()
        let saved = gesture.waitUntilValueEquals("xy")
        if !saved {
            attachScreenshot("Key settings save failure before teardown")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Actual key settings save failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(saved, "Saving must return to the key page with its exact saved choice")
        attachScreenshot("App key settings save a literal multi-character swipe choice")

        app.terminate()
        app.launchArguments = []
        app.launch()
        openAppSettings()
        app.buttons["keyboardKeySettings"].tap()
        app.buttons["keySettings.key.letter.q"].tap()
        XCTAssertTrue(app.navigationBars["Q key"].waitForExistence(timeout: 5))
        XCTAssertTrue(gesture.waitUntilValueEquals("xy"), "Explicit key settings survive an ordinary app relaunch")
        gesture.tap()
        XCTAssertTrue(behavior.waitForExistence(timeout: 5))
        behavior.buttons["Off"].tap()
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(gesture.waitUntilValueEquals("Off"))
        gesture.tap()
        XCTAssertTrue(behavior.buttons["Off"].isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["keySettings.resetKey"].tap()
        app.buttons["Restore defaults"].tap()
        XCTAssertTrue(gesture.waitUntilValueEquals("Default"))
        XCTAssertFalse(app.buttons["keySettings.resetKey"].isEnabled)
        attachScreenshot("Disabled swipe and restored per-key defaults are separate saved states")
    }

    func testSearchBySupplementaryCodepointAndAlias() {
        searchUnicode("U+1F680")
        let rocket = assertCharacterVisible("U+1F680")
        dismissAppSearchKeyboard()
        attachScreenshot("Search by code point finds the original rocket")
        rocket.tap()

        XCTAssertTrue(app.buttons["copyCharacter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["U+1F680"].exists)
        app.buttons["Done"].tap()

        searchUnicode("ohm")
        assertCharacterVisible("U+2126")
    }

    func testSearchByBlockName() {
        searchUnicode("Mathematical Operators")
        assertCharacterVisible("U+2200")

        searchUnicode("Hiragana")
        assertCharacterVisible("U+3041")
    }

    func testSuzhouNumeralsSearchExposesNamesListAndNumericProperties() {
        searchUnicode("suzhou numerals")
        assertCharacterVisible("U+3021")
        dismissAppSearchKeyboard()
        for scalar in 0x3021...0x3029 {
            revealResultCharacter(String(format: "U+%04X", scalar))
        }
        attachScreenshot("Suzhou numerals section search finds the nine Hangzhou-named characters")
        revealResultCharacter("U+3021").tap()
        assertCharacterProperty("name", equals: "Hangzhou Numeral One")
        assertCharacterProperty("section", contains: "Suzhou numerals")
        assertCharacterProperty("notes", contains: "misnomer")
        assertCharacterProperty("notes", contains: "Hangzhou")
        assertCharacterProperty("numericValue", equals: "1")
        attachScreenshot("Official Hangzhou name retains Suzhou section, naming note and numeric value")
        app.buttons["Done"].tap()

        searchUnicode("hangzhou numerals")
        assertCharacterVisible("U+3021")
        dismissAppSearchKeyboard()
        for scalar in 0x3021...0x3029 {
            revealResultCharacter(String(format: "U+%04X", scalar))
        }
    }

    @discardableResult
    private func revealResultCharacter(_ codepoint: String) -> XCUIElement {
        let results = app.scrollViews.containing(.textField, identifier: "unicodeSearch").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        let result = character(codepoint)
        for _ in 0..<8 {
            if isInsideScrollViewport(result, in: results) { break }
            if result.exists && result.frame.midY < results.frame.minY {
                results.swipeDown()
            } else {
                results.swipeUp()
            }
        }
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Expected required search result \(codepoint)")
        XCTAssertTrue(isInsideScrollViewport(result, in: results),
                      "Required result \(codepoint) must be tappable after scrolling the actual results")
        return result
    }

    func testFavoriteCanBeFoundAndRemovedInSaved() {
        searchUnicode("snowman")
        assertCharacterVisible("U+2603").tap()

        let favorite = app.buttons["toggleFavorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        revealByScrolling(favorite, in: app)
        XCTAssertEqual(favorite.label, "Add to favorites")
        favorite.tap()
        XCTAssertTrue(favorite.waitUntilLabelEquals("Remove from favorites"))
        app.buttons["Done"].tap()

        appTab("Saved").tap()
        let favorites = app.otherElements["savedFavorites"].firstMatch
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        let savedSnowman = favorites.buttons["character-U+2603"].firstMatch
        XCTAssertTrue(savedSnowman.waitForExistence(timeout: 5))
        savedSnowman.tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        revealByScrolling(favorite, in: app)
        XCTAssertEqual(favorite.label, "Remove from favorites")
        favorite.tap()
        XCTAssertTrue(favorite.waitUntilLabelEquals("Add to favorites"))
        app.buttons["Done"].tap()

        let removed = favorites.buttons["character-U+2603"].firstMatch
        let absent = NSPredicate(format: "exists == false")
        expectation(for: absent, evaluatedWith: removed)
        waitForExpectations(timeout: 5)
    }

    func testBrowseUnicodeBlockAndOpenCharacter() {
        appTab("Blocks").tap()
        let blockSearch = app.descendants(matching: .any)["blockSearch"].firstMatch
        XCTAssertTrue(blockSearch.waitForExistence(timeout: 5))
        blockSearch.tap()
        blockSearch.typeText("Arrows")

        let arrows = app.buttons["Arrows"].firstMatch
        XCTAssertTrue(arrows.waitForExistence(timeout: 5))
        arrows.tap()
        attachScreenshot("Browse the real Arrows block and its characters")
        assertCharacterVisible("U+2190").tap()

        XCTAssertTrue(app.buttons["copyCharacter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["U+2190"].exists)
    }

    func testCatalogSelectionPreservesLookupStatusAndLocalChoice() {
        // Edition survives ordinary test launches, so establish this fixture
        // through its real Settings UI rather than resetting shared storage.
        selectAppEdition("latest")
        for tab in ["Explore", "Emojis", "Blocks", "Saved"] {
            appTab(tab).tap()
            XCTAssertFalse(app.descendants(matching: .any)["unicodeEdition"].firstMatch.exists,
                           "Only Settings may expose a catalog edition selector")
            XCTAssertFalse(app.buttons["unicodeEdition.current"].firstMatch.exists,
                           "A catalog version outside Settings is read-only")
        }
        for (edition, has17, has18) in [("older", false, false), ("previous", true, false),
                                       ("latest", true, true), ("draft", true, true)] {
            selectAppEdition(edition)
            assertAppCatalogScalar("U+0041", assigned: true, age: "1.1")
            assertAppCatalogScalar("U+0378", assigned: false)
            assertAppCatalogScalar("U+10940", assigned: has17, age: has17 ? "17.0" : nil)
            assertAppCatalogScalar("U+0558", assigned: has18, age: has18 ? "18.0" : nil)
            attachScreenshot("Settings-selected \(edition) preserves its actual historical assignments")
        }

        // A historical version remains17 after a real relaunch. Draft19 may
        // honestly share18's assignments; no nonexistent19-only scalar is used.
        selectAppEdition("previous")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openAppSettings()
        assertControlValue("unicodeEdition", equals: "previous")
        appTab("Explore").tap()
        assertAppCatalogScalar("U+10940", assigned: true, age: "17.0")
        assertAppCatalogScalar("U+0558", assigned: false)
        attachScreenshot("Historical Unicode17 selection persists after ordinary relaunch")
        selectAppEdition("latest")
    }

    private func assertAppCatalogScalar(_ codepoint: String, assigned: Bool, age: String? = nil) {
        searchUnicode(codepoint)
        let result = assertCharacterVisible(codepoint)
        if let age {
            XCTAssertTrue(result.waitUntilValueEquals("Unicode \(age)"))
        } else {
            XCTAssertTrue(result.waitUntilValueEquals("Unassigned"))
        }
        result.tap()
        assertCharacterProperty("status", equals: assigned ? "Assigned" : "Unassigned")
        if let age { assertCharacterProperty("age", equals: age) }
        else { assertCharacterProperty("category", contains: "Cn") }
        app.buttons["Done"].tap()
    }

    func testDefaultCodePointOrderAndExplicitNewestUsesNumericUnicodeAges() {
        assertControlValue("unicodeSort", equals: "codePoint")
        let initialTiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "character-U+"))
            .allElementsBoundByAccessibilityElement.compactMap { tile -> (CGRect, UInt32)? in
                let frame = tile.frame
                guard usableHeightFrame(frame), app.frame.contains(frame),
                      let point = UInt32(tile.identifier.replacingOccurrences(of: "character-U+", with: ""), radix: 16) else { return nil }
                return (frame, point)
            }.sorted { abs($0.0.minY - $1.0.minY) > 5 ? $0.0.minY < $1.0.minY : $0.0.minX < $1.0.minX }
        XCTAssertGreaterThan(initialTiles.count, 1)
        for (before, after) in zip(initialTiles, initialTiles.dropFirst()) { XCTAssertLessThan(before.1, after.1) }
        attachScreenshot("Fresh Explore uses ascending code point order")
        app.buttons["unicodeSort"].tap()
        app.buttons["sort.newestFirst"].tap()
        assertControlValue("unicodeSort", equals: "newestFirst")
        searchUnicode("heart")
        dismissAppSearchKeyboard()
        XCTAssertTrue(character("U+1FA77").waitForExistence(timeout: 10), "Heart results should replace the initial discovery grid")

        // These ages deliberately cross the lexical boundary: "6.0" sorts
        // after "15.0" as text, but before it as a Unicode version.
        // Each required name contains the complete word HEART, so this checks
        // numeric ordering within the full-word tier, not across search tiers.
        let samples = collectCharacterAges(until: ["U+1FA77", "U+1F49D", "U+2661"])
        XCTAssertGreaterThanOrEqual(samples.count, 3)
        attachScreenshot("Numeric newest-first heart results across Unicode ages")
        for (newer, older) in zip(samples, samples.dropFirst()) {
            XCTAssertFalse(version(newer.age, precedes: older.age),
                "Newest-first must order numeric ages: \(newer.codepoint) \(newer.age) precedes \(older.codepoint) \(older.age)")
        }
        let required = [("U+1FA77", [15, 0]), ("U+1F49D", [6, 0]), ("U+2661", [1, 1])]
        var previousIndex = -1
        for (codepoint, age) in required {
            guard let index = samples.firstIndex(where: { $0.codepoint == codepoint }) else {
                XCTFail("Expected \(codepoint) in the heart results")
                return
            }
            XCTAssertEqual(samples[index].age, age)
            XCTAssertGreaterThan(index, previousIndex)
            previousIndex = index
        }
    }

    func testEmojiDetailsAndScratchpadPreserveWholeZWJSequence() {
        appTab("Emojis").tap()
        search("woman technologist", fieldIdentifier: "emojiSearch")
        dismissAppSearchKeyboard()
        let emoji = app.buttons["emoji-1F469-200D-1F4BB"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        attachScreenshot("Whole emoji sequence in app search results")
        emoji.tap()
        let codepoints = app.descendants(matching: .any)["emojiProperties.codepoints"].firstMatch
        XCTAssertTrue(codepoints.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(codepoints), "U+1F469 U+200D U+1F4BB")
        XCTAssertTrue(app.buttons["copyEmoji"].exists)
        attachScreenshot("Woman technologist whole sequence details")
        let add = app.buttons["addEmojiToScratchpad"].firstMatch
        revealByScrolling(add, in: app)
        add.tap()
        app.buttons["Done"].tap()
        appTab("Explore").tap()
        let scratchpad = app.buttons["openScratchpad"].firstMatch
        revealByScrolling(scratchpad, in: app)
        scratchpad.tap()
        let input = app.textViews["scratchpadInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.waitUntilValueEquals("👩‍💻"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map { $0.value }, [0x1F469, 0x200D, 0x1F4BB])
        attachScreenshot("Scratchpad preserves exact whole emoji sequence")
    }

    func testUnsupportedGlyphStillShowsNameDescriptionAndProperties() {
        selectAppEdition("latest")
        searchUnicode("U+1FAEB")
        let crackingFace = assertCharacterVisible("U+1FAEB")
        XCTAssertTrue(crackingFace.waitUntilValueEquals("Unicode 18.0"))
        crackingFace.press(forDuration: 1)
        assertCharacterProperty("name", contains: "cracking face")
        assertCharacterProperty("codepoints", equals: "U+1FAEB")
        assertCharacterProperty("age", equals: "18.0")
        let description = app.descendants(matching: .any)["characterProperties.description"].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertFalse(accessibleText(description).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "An unavailable font glyph must not hide its descriptive Unicode metadata")
        attachScreenshot("Unicode18 cracking face retains meaning when the font lacks its glyph")
    }

    func testOptionalUnicodeFontsAppChoicePersistsAndPreservesExactText() {
        selectAppEdition("latest")
        setAppUnicodeFonts(false)
        let fonts = appUnicodeFontsSwitch()
        XCTAssertTrue(fonts.waitUntilValueEquals("0"), "The visible App Settings choice must be off before testing native previews")
        appTab("Explore").tap()
        searchUnicode("U+0558")
        dismissAppSearchKeyboard()
        assertCharacterVisible("U+0558").tap()
        assertCharacterProperty("name", contains: "Armenian small eh")
        assertCharacterProperty("codepoints", equals: "U+0558")
        XCTAssertTrue(app.staticTexts["characterGlyph"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["characterProperties.fontSource"].firstMatch.exists,
                       "An off setting must preserve the native preview font")
        attachScreenshot("Extra fonts off preserves the native Armenian preview and meaning")
        app.buttons["Done"].tap()

        setAppUnicodeFonts(true)
        appTab("Explore").tap()
        searchUnicode("U+0558")
        dismissAppSearchKeyboard()
        assertCharacterVisible("U+0558").tap()
        assertCharacterProperty("fontSource", contains: "GNU Unifont")
        assertCharacterProperty("codepoints", equals: "U+0558")
        attachScreenshot("Extra fonts on displays the missing Unicode18 Armenian glyph")
        let add = app.buttons["addToScratchpad"].firstMatch
        revealByScrolling(add, in: app)
        add.tap()
        app.buttons["Done"].tap()
        let scratchpad = app.buttons["openScratchpad"].firstMatch
        revealByScrolling(scratchpad, in: app)
        scratchpad.tap()
        let input = app.textViews["scratchpadInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.waitUntilValueEquals("\u{0558}"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map { $0.value }, [0x0558],
                       "A preview font must not add a placeholder or change copied text")
        app.buttons["Done"].tap()

        // The normal relaunch deliberately omits the testing preference reset.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("1"))
        let licenses = app.descendants(matching: .any)["fontLicenses"].firstMatch
        revealByScrolling(licenses, in: app)
        licenses.tap()
        let licenseText = app.staticTexts["fontLicenseText"].firstMatch
        XCTAssertTrue(licenseText.waitForExistence(timeout: 5))
        for text in ["Unifont", "Noto", "SIL OPEN FONT LICENSE"] {
            XCTAssertTrue(accessibleText(licenseText).contains(text), "Bundled font credits must include \(text)")
        }
        app.navigationBars["Font licenses"].buttons.firstMatch.tap()
        setAppUnicodeFonts(false)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("0"), "Turning fonts off must also persist")
        attachScreenshot("App preview-font choice persists and can be disabled")
    }

    func testSystemKeyboardEnglishTypingAndUnicodeQueryRouting() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals("off"))
        guard let initialHeight = measuredKeyboardHeight() else { XCTFail("Expected the actual persisted keyboard height"); return }
        XCTAssertTrue((220...420).contains(initialHeight), "An explicit saved height remains valid before visible normalization")
        XCTAssertFalse(app.buttons["keyboard.collapse"].exists)
        ensureUnicodeToolbarVisible()
        stepKeyboardHeightToBound(220, input: input, context: "")
        app.buttons["keyboard.toggleUnicodeToolbar"].tap()
        XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals("off"))
        XCTAssertEqual(measuredKeyboardHeight(), 220, "Real downward row steps reach the compact daily layout")
        assertFixedTypingKeycapsAndRows()
        XCTAssertEqual(input.value as? String, "")
        attachScreenshot("Visible row-step normalization reaches four English rows with the Unicode toolbar hidden")
        ensureUnicodeToolbarVisible()
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let space = app.buttons["keyboard.space"].firstMatch
        let delete = app.buttons["keyboard.delete"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "The sentence-capitalizing host begins with a capital")
        assertHeaderDeleteAtTopRight()
        attachScreenshot("Default English QWERTY offers sentence capitalization and persistent top-right delete")

        typeHostTypingKeys("hello")
        XCTAssertTrue(input.waitUntilValueEquals("Hello"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("Hell"))
        typeHostTypingKeys("o")
        XCTAssertTrue(input.waitUntilValueEquals("Hello"))
        XCTAssertTrue(search.waitUntilValueEquals("No query"), "The lower English delete must edit only the host")
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

        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.symbols"].firstMatch.waitUntilValueEquals("numbers"))
        typeHostTypingKeys("1?", layout: "numbers")
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
        delete.tap()
        expected.removeLast()
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        XCTAssertTrue(search.waitUntilValueEquals("No query"), "Host letters, punctuation and delete never edit Unicode search")

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
        XCTAssertTrue(search.waitUntilValueEquals("head shaking horizontally"))
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected), "The lower English backspace removes the complete inserted emoji grapheme")
        XCTAssertTrue(search.waitUntilValueEquals("head shaking horizontally"))

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
        XCTAssertTrue(search.waitUntilValueEquals("arrow  cat"), "English typing after Done retains the exact local query")
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
        delete.tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        XCTAssertTrue(search.waitUntilValueEquals("u+1f680"))
        XCTAssertTrue(app.buttons["keyboard.typing.shift"].waitUntilValueEquals("lowercase"))
        chooseHeldKeyboardOption(app.buttons["keyboard.typing.key.e"].firstMatch,
                                 optionCount: 8, selectedIndex: 2, extraActions: 0)
        XCTAssertTrue(input.waitUntilValueEquals(expected + "é"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value), expected.unicodeScalars.map(\.value) + [0xE9])
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected))
        XCTAssertTrue(search.waitUntilValueEquals("u+1f680"), "English diacritic selection must not edit the retained Unicode query")
        attachScreenshot("English and Unicode share exact host insertion while retaining an isolated local query")
    }

    func testSystemKeyboardClearingQueryKeepsSearchFocusAndHost() throws {
        try requireKeyboardIntegration()
        let context = "Clearing search must keep this document unchanged."
        let input = openSystemKeyboardHost(initialText: context)
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("cat")
        // The existing helper presses the actual Clear button and requires
        // an empty query before typing. Keep its physical tap unchanged.
        enterKeyboardQuery("dog")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"))
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Clear targets only the query and retains the query keyboard beside the English control")
    }

    func testSystemKeyboardWidePadHasStockFunctionsAndExactTypingAcrossRotation() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Wide iPad layout requires the owned iPad QA device")
        configurePadSettings(layout: "ansiNumbers", mapping: "standard")
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let caps = app.buttons["keyboard.typing.capsLock"].firstMatch
        let tab = app.buttons["keyboard.typing.tab"].firstMatch
        let rightShift = app.buttons["keyboard.typing.shift.right"].firstMatch
        func geometry() {
            for id in ["keyboard.typing.tab", "keyboard.typing.capsLock", "keyboard.typing.shift",
                       "keyboard.typing.shift.right", "keyboard.typing.delete", "keyboard.return",
                       "keyboard.typing.key.,", "keyboard.typing.key.."] {
                let key = app.buttons[id].firstMatch
                XCTAssertTrue(key.waitForExistence(timeout: 5), id)
                XCTAssertTrue(key.isHittable, id)
                XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(key.frame), id)
                XCTAssertEqual(key.frame.height, 52, accuracy: 1, id)
                XCTAssertGreaterThanOrEqual(key.frame.width, 44, id)
            }
            XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
            XCTAssertFalse(app.buttons["keyboard.typing.number.1"].exists)
            XCTAssertFalse(app.otherElements["keyboard.typing.favorites"].exists)
            XCTAssertEqual(app.buttons["keyboard.space"].firstMatch.frame.height, 52, accuracy: 1)
            XCTAssertLessThanOrEqual(app.buttons["keyboard.space"].firstMatch.frame.maxY - tab.frame.minY, 224)
            XCTAssertEqual(caps.frame.minY - tab.frame.maxY, 6, accuracy: 1)
            XCTAssertEqual(tab.frame.midY, app.buttons["keyboard.typing.key.q"].firstMatch.frame.midY, accuracy: 1)
            XCTAssertEqual(caps.frame.midY, app.buttons["keyboard.return"].firstMatch.frame.midY, accuracy: 1)
            XCTAssertLessThan(app.buttons["keyboard.return"].firstMatch.frame.maxY, app.buttons["keyboard.space"].firstMatch.frame.minY)
        }
        geometry()
        tab.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\t"))
        caps.tap()
        XCTAssertTrue(caps.waitUntilValueEquals("on"))
        app.buttons["keyboard.typing.key.a"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA"))
        flickMainKey(app.buttons["keyboard.typing.key.q"].firstMatch, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("\tAq"))
        XCTAssertTrue(caps.waitUntilValueEquals("on"))
        rightShift.tap()
        XCTAssertTrue(caps.waitUntilValueEquals("off"))
        app.buttons["keyboard.typing.key.q"].tap()
        app.buttons["keyboard.typing.key.,"].tap()
        app.buttons["keyboard.typing.key.."].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,."))
        app.buttons["keyboard.return"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.\n"))
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,."))
        // Down-flicks insert the printed secondary glyph; ordinary taps keep
        // their letter and up-flicks keep opposite-case semantics.
        flickMainKey(app.buttons["keyboard.typing.key.q"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1"))
        flickMainKey(app.buttons["keyboard.typing.key.a"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1-"))
        flickMainKey(app.buttons["keyboard.typing.key.."].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1-?"))
        for _ in 0..<3 { app.buttons["keyboard.typing.delete"].tap() }
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,."))
        attachScreenshot("Stock iPad three letter rows secondary flick hints gray modifiers blue Return")
        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.letters"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
        XCTAssertEqual(app.buttons["keyboard.typing.key.1"].firstMatch.frame.height, 52, accuracy: 1)
        app.buttons["keyboard.typing.letters"].tap()
        geometry()
        app.buttons["keyboard.toggleUnicodeToolbar"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5))
        geometry()
        app.buttons["keyboard.toggleUnicodeToolbar"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForNonExistence(timeout: 5))
        geometry()
        settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false)
        assertLandscapePadGeometry(numberRow: true, ansi: true)
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,."))
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        if shift.value as? String != "lowercase" { shift.tap() }
        app.buttons["keyboard.typing.key.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1"))
        shift.tap()
        app.buttons["keyboard.typing.key.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1!"))
        shift.tap()
        app.buttons["keyboard.typing.key.["].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1!{"))
        caps.tap()
        app.buttons["keyboard.typing.key.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,.1!{1"), "Caps Lock changes letters, not digits")
        caps.tap()
        app.buttons["keyboard.return"].tap()
        app.buttons["keyboard.typing.key.1"].tap()
        let expected = "\tAqq,.1!{1\n1"
        XCTAssertTrue(input.waitUntilValueEquals(expected), "Sentence capitalization must not shift a digit into punctuation")
        attachScreenshot("Landscape ANSI equal keycaps with number row tinted modifiers and two right Space controls")
        app.buttons["keyboard.typing.numbers"].tap()
        for digit in "1234567890" { XCTAssertFalse(app.buttons["keyboard.typing.key.\(digit)"].exists) }
        XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
        app.buttons["keyboard.typing.symbols"].tap()
        for digit in "1234567890" { XCTAssertFalse(app.buttons["keyboard.typing.key.\(digit)"].exists) }
        app.buttons["keyboard.typing.auxiliary.§"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(expected + "§"))
        app.buttons["keyboard.typing.letters"].tap()
        assertLandscapePadGeometry(numberRow: true, ansi: true)
        app.buttons["keyboard.collapse"].tap()
        XCTAssertTrue(app.buttons["keyboard.space"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, expected + "§")
        input.tap()
        XCTAssertTrue(app.buttons["keyboard.space"].waitForExistence(timeout: 5))
        assertLandscapePadGeometry(numberRow: true, ansi: true)
        settleKeyboardOrientation(.portrait, toolbarVisible: false)
        geometry()
    }

    func testSystemKeyboardPadAppPresetsAndSymbolMappingsApplyWithoutFullAccess() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad settings require the owned iPad QA device")
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        for (layout, mapping, down) in [("stock", "iPad", "@"), ("ansi", "none", ""), ("ansiNumbers", "standard", "-")] {
            XCUIDevice.shared.orientation = .portrait
            configurePadSettings(layout: layout, mapping: mapping)
            let input = openSystemKeyboardHost(unicodeBrowse: false)
            settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false)
            assertLandscapePadGeometry(numberRow: layout == "ansiNumbers", ansi: layout != "stock")
            let a = app.buttons["keyboard.typing.key.a"].firstMatch
            a.tap()
            XCTAssertTrue(input.waitUntilValueEquals("A"), "Ordinary taps stay QWERTY for every symbol mapping")
            flickMainKey(a, up: false)
            XCTAssertTrue(input.waitUntilValueEquals("A" + down))
            app.buttons["keyboard.typing.numbers"].tap()
            XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
            XCTAssertTrue(app.buttons["keyboard.return"].firstMatch.isHittable)
            XCTAssertEqual(app.buttons["keyboard.typing.key.1"].exists, layout != "ansiNumbers")
            app.buttons["keyboard.typing.letters"].tap()
            assertLandscapePadGeometry(numberRow: layout == "ansiNumbers", ansi: layout != "stock")
            attachScreenshot("App-only iPad preset \(layout) symbol mapping \(mapping) with Full Access off")
            settleKeyboardOrientation(.portrait, toolbarVisible: false)
            restoreEnglishKeyboard()
        }
        configurePadSettings(layout: "ansiNumbers", mapping: "standard")
    }

    private func configurePadSettings(layout: String, mapping: String) {
        openAppSettings()
        for (identifier, value) in [("padLayout", layout), ("padSymbolMapping", mapping)] {
            let picker = app.descendants(matching: .any)[identifier].firstMatch
            let scroll = app.scrollViews.containing(.any, identifier: "unicodeEdition").firstMatch
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            for _ in 0..<8 {
                let viewport = scroll.frame.intersection(app.frame)
                let frame = picker.frame
                if usableHeightFrame(frame), viewport.contains(frame), picker.isHittable { break }
                if frame.minY < viewport.minY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            }
            XCTAssertTrue(scroll.frame.intersection(app.frame).contains(picker.frame), "The retained Settings scroll position must reveal the actual picker")
            XCTAssertTrue(picker.isHittable)
            picker.tap()
            let option = app.descendants(matching: .any)["\(identifier).option.\(value)"].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            XCTAssertTrue(picker.waitUntilValueEquals(value))
            XCTAssertFalse(app.staticTexts["unicodeEdition.saveError"].exists)
        }
    }

    private func assertLandscapePadGeometry(numberRow: Bool, ansi: Bool,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let space = app.buttons["keyboard.space"].firstMatch
        let page = app.buttons["keyboard.typing.numbers"].firstMatch
        let hide = app.buttons["keyboard.collapse"].firstMatch
        let top = app.buttons["keyboard.typing.key.\(numberRow ? "1" : "q")"].firstMatch
        for id in ["keyboard.typing.tab", "keyboard.typing.capsLock", "keyboard.typing.shift", "keyboard.typing.shift.right",
                   "keyboard.typing.delete", "keyboard.return", "keyboard.space", "keyboard.collapse", "keyboard.typing.numbers"] {
            let key = app.buttons[id].firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5), id, file: file, line: line)
            XCTAssertTrue(key.isHittable, id, file: file, line: line)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(key.frame), id, file: file, line: line)
            XCTAssertEqual(key.frame.height, 52, accuracy: 1, id, file: file, line: line)
            XCTAssertGreaterThanOrEqual(key.frame.width, 44, id, file: file, line: line)
        }
        XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1, file: file, line: line)
        XCTAssertGreaterThan(page.frame.minX, space.frame.maxX, file: file, line: line)
        XCTAssertGreaterThan(hide.frame.minX, page.frame.maxX, file: file, line: line)
        XCTAssertEqual(page.frame.midY, space.frame.midY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(hide.frame.midY, space.frame.midY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(space.frame.maxY - top.frame.minY, numberRow ? 282 : 224, accuracy: 1, file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.key.["].exists, ansi, file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.key.1"].exists, numberRow, file: file, line: line)
        XCTAssertFalse(app.buttons["keyboard.typing.number.1"].exists, file: file, line: line)
        XCTAssertFalse(app.otherElements["keyboard.typing.favorites"].exists, file: file, line: line)
    }

    func testSystemKeyboardTapRemapsAndThreeIndependentGestures() throws {
        try requireKeyboardIntegration()
        configureAppKeyGesture(keyID: "letter.q", gesture: "tap", choices: ["w"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "shiftedTap", choices: ["Ω"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "longPress", choices: ["h"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "swipeUp", choices: ["u"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "swipeDown", choices: ["d"])
        configureAppKeyGesture(keyID: "digit.1", gesture: "tap", choices: ["2"])
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        XCTAssertEqual(q.label, "Ω", "The keycap reflects its exact shifted tap mapping")
        q.tap()
        XCTAssertTrue(input.waitUntilValueEquals("Ω"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        XCTAssertEqual(q.label, "w")
        q.tap()
        q.press(forDuration: 0.65)
        flickMainKey(q, up: true)
        flickMainKey(q, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("Ωwhud"), "Tap, long press, up and down must each use only their own mapping")
        app.buttons["keyboard.typing.number.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("Ωwhud2"), "Digit remaps apply to the auxiliary physical key too")
        flickMainKey(app.buttons["keyboard.typing.key.w"].firstMatch, up: false)
        flickMainKey(app.buttons["keyboard.typing.key.p"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("Ωwhud2\\•"), "Visible digits replace W/P down-flicks with the complementary symbol-page characters")
        attachScreenshot("Independent remapped tap hold up down and nonduplicate top letter flicks")
        restoreEnglishKeyboard()
        openAppSettings()
        app.buttons["keyboardKeySettings"].tap()
        app.buttons["keySettings.key.letter.q"].tap()
        app.buttons["keySettings.gesture.tap"].tap()
        app.segmentedControls["keySettings.behavior"].buttons["Off"].tap()
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(app.buttons["keySettings.gesture.tap"].waitUntilValueEquals("Off"))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let fresh = openSystemKeyboardHost(unicodeBrowse: false)
        if shift.value as? String != "lowercase" { shift.tap() }
        q.tap()
        XCTAssertEqual(fresh.value as? String, "", "Disabled ordinary tap must not insert the original physical letter")
        flickMainKey(q, up: true)
        q.press(forDuration: 0.65)
        flickMainKey(q, up: false)
        XCTAssertTrue(fresh.waitUntilValueEquals("uhd"), "Disabling tap does not disable the three independent gestures")
        restoreEnglishKeyboard()
        resetAppKey("letter.q")
        resetAppKey("digit.1")
    }

    func testSystemKeyboardAppConfiguredFlicksPreserveLiteralTextAndShift() throws {
        try requireKeyboardIntegration()
        configureAppKeyGesture(keyID: "letter.q", gesture: "swipeUp", choices: ["xy", "cd"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "longPress", choices: ["h"])
        configureAppKeyGesture(keyID: "digit.1", gesture: "swipeDown", choices: ["_"])
        configureAppKeyGesture(keyID: "digit.1", gesture: "swipeUp", choices: ["!"])
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "The fresh sentence-capitalizing host starts uppercase")
        flickMainKey(app.buttons["keyboard.typing.key.a"].firstMatch, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("a"))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "A default opposite-case flick preserves automatic uppercase across host callbacks")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(""))
        if shift.value as? String != "lowercase" { shift.tap() }
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        q.tap()
        XCTAssertTrue(input.waitUntilValueEquals("q"), "A custom hold/flick must not replace ordinary tap output")
        flickMainKey(q, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy"), "Actual app-authored choices reach the keyboard with Full Access off")
        flickMainKey(q, up: true, horizontal: 36)
        XCTAssertTrue(input.waitUntilValueEquals("qxycd"), "After the up flick, sliding right selects the second literal choice")
        app.buttons["keyboard.typing.delete"].tap()
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("qxy"))
        q.press(forDuration: 0.65)
        XCTAssertTrue(input.waitUntilValueEquals("qxyh"), "A configured long press inserts its exact candidate without an ordinary q tap")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("qxy"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"), "A literal flick preserves visible Shift")
        flickMainKey(app.buttons["keyboard.typing.number.1"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_"), "A configured digit downward flick inserts its literal choice without a digit tap")
        flickMainKey(app.buttons["keyboard.typing.number.1"].firstMatch, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!"), "The auxiliary number row reads the same physical-key override")

        let a = app.buttons["keyboard.typing.key.a"].firstMatch
        flickMainKey(a, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!A"), "The default up flick chooses the opposite case")
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        flickMainKey(a, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!A"), "Unconfigured downward movement must not become an ordinary tap")
        shift.doubleTap()
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"))
        flickMainKey(a, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!Aa"))
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"), "The opposite-case flick must not consume Caps Lock")
        q.tap()
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!AaQ"))
        attachScreenshot("Real main-key flicks insert exact settings and retain lowercase or locked Shift")

        restoreEnglishKeyboard()
        resetAppKey("letter.q")
        resetAppKey("digit.1")
    }

    private func resetAppKey(_ keyID: String) {
        openAppSettings()
        app.buttons["keyboardKeySettings"].tap()
        let key = app.buttons["keySettings.key.\(keyID)"].firstMatch
        revealByScrolling(key, in: app)
        key.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keySettings.detail.\(keyID)"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["keySettings.resetKey"].tap()
        app.buttons["Restore defaults"].tap()
        XCTAssertTrue(app.buttons["keySettings.gesture.swipeUp"].waitUntilValueEquals("Default"))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func flickMainKey(_ key: XCUIElement, up: Bool, horizontal: CGFloat = 0,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(key.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(key.isHittable, file: file, line: line)
        let start = key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let distance = max(28, abs(horizontal) + 12)
        let vertical = start.withOffset(CGVector(dx: 0, dy: up ? -distance : distance))
        if horizontal == 0 {
            start.press(forDuration: 0.05, thenDragTo: vertical)
        } else {
            let finish = vertical.withOffset(CGVector(dx: horizontal, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    private func configureAppKeyGesture(keyID: String, gesture: String, choices: [String]) {
        openAppSettings()
        let settings = app.buttons["keyboardKeySettings"].firstMatch
        revealByScrolling(settings, in: app)
        settings.tap()
        let key = app.buttons["keySettings.key.\(keyID)"].firstMatch
        revealByScrolling(key, in: app)
        key.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keySettings.detail.\(keyID)"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["keySettings.gesture.\(gesture)"].tap()
        app.segmentedControls["keySettings.behavior"].buttons["Custom"].tap()
        for (index, value) in choices.enumerated() {
            if index > 0 { app.buttons["keySettings.addChoice"].tap() }
            let field = app.textFields["keySettings.choice.\(index)"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(value)
            XCTAssertTrue(field.waitUntilValueEquals(value))
        }
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(app.buttons["keySettings.gesture.\(gesture)"].waitUntilValueEquals(choices.joined(separator: "  ")))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func typeHostTypingKeys(_ text: String, layout: String = "letters") {
        assertHostTypingPanel()
        for key in text {
            let button = app.buttons["keyboard.typing.key.\(key)"].firstMatch
            XCTAssertTrue(button.waitUntilValueEquals(layout), "Expected the real \(layout) key \(key)")
            XCTAssertTrue(button.isHittable)
            button.tap()
        }
    }

    func testSystemKeyboardFavoritesKeyPreservesQueryCaretAndExactHost() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Favorites preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        selectSymbolBoard("migrated-favorites", input: input, context: context, returnToTyping: true,
                          preferredStarBoardID: "migrated-favorites")
        let favoriteKey = app.buttons["keyboard.openFavorites"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let favorites = app.buttons["Favorites"].firstMatch
        let recent = app.buttons["Recent"].firstMatch
        let originalHeight = keyboardResizeHeight()
        XCTAssertNotNil(originalHeight)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        favoriteKey.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.section"].firstMatch.waitUntilValueEquals("saved"))
        XCTAssertTrue(favorites.waitUntilSelected())
        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        XCTAssertEqual(favoriteKey.label, "Back to English keyboard")
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        XCTAssertEqual(input.value as? String, context)
        if let originalHeight { assertResizeHeight(originalHeight) }
        favoriteKey.tap()
        assertHostTypingPanel()
        XCTAssertEqual(favoriteKey.label, "Symbol keyboard")
        XCTAssertTrue(favoriteKey.waitUntilValueEquals("typing"))
        XCTAssertEqual(input.value as? String, context)
        favoriteKey.tap()
        XCTAssertTrue(favorites.waitUntilSelected())
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(recent.waitUntilSelected())
        XCTAssertEqual(favoriteKey.label, "Symbol keyboard", "Recent keeps the star so one tap selects the preferred board")
        let abc = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        XCTAssertTrue(abc.waitUntilValueEquals("unicode"))
        abc.tap()
        assertHostTypingPanel()
        XCTAssertEqual(input.value as? String, context)

        // Exercise actual query recognition early; a missing key is a failure,
        // never repaired by repeated taps or a hidden search-state reset.
        openUnicodeBrowse()
        enterKeyboardQuery("u+2603")
        let snowman = app.buttons["keyboard.character.U+2603"].firstMatch
        XCTAssertTrue(snowman.waitForExistence(timeout: 10))
        snowman.press(forDuration: 1)
        saveInspectedKeyToBoard("migrated-favorites", input: input, context: context)
        XCTAssertEqual(input.value as? String, context, "Inspection and saving must not insert a character")
        app.buttons["keyboard.properties.close"].tap()
        enterKeyboardQuery("cat")
        search.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 36, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        assertFavoritesKeyImmediatelyPrecedesSpace()
        favoriteKey.tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent())
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.section"].firstMatch.waitUntilValueEquals("saved"))
        XCTAssertTrue(favorites.waitUntilSelected(), "The direct star must choose Favorites even after Recent was selected")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        XCTAssertEqual(input.value as? String, context)
        // Search results and Saved use different native tile instances.
        // Resolve the Saved identifier afresh after that panel replacement.
        let savedSnowman = symbolBoardKey("☃")
        XCTAssertTrue(savedSnowman.waitForExistence(timeout: 5))
        let savedScroll = app.scrollViews.containing(.button, identifier: savedSnowman.identifier).firstMatch
        XCTAssertTrue(savedScroll.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if savedSnowman.exists, savedScroll.frame.intersection(app.frame).contains(savedSnowman.frame), savedSnowman.isHittable { break }
            savedScroll.swipeUp()
        }
        XCTAssertTrue(savedSnowman.exists)
        XCTAssertTrue(savedScroll.frame.intersection(app.frame).contains(savedSnowman.frame))
        XCTAssertTrue(savedSnowman.isHittable)
        XCTAssertEqual(savedSnowman.frame.height, 36, accuracy: 1)
        let savedCapFrame = savedSnowman.frame
        savedSnowman.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "☃"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x2603])
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        attachScreenshot("Direct Favorites inserts the saved snowman without editing the retained query")
        recent.tap()
        XCTAssertTrue(recent.waitUntilSelected())
        let recentSnowman = app.buttons.matching(identifier: "keyboard.character.U+2603").firstMatch
        XCTAssertTrue(recentSnowman.waitForExistence(timeout: 5))
        let recentGrid = app.scrollViews.containing(.button, identifier: "keyboard.character.U+2603").firstMatch
        XCTAssertTrue(recentGrid.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            let viewport = recentGrid.frame.intersection(app.frame)
            guard usableHeightFrame(viewport) else { XCTFail("Expected the actual Recent viewport"); return }
            let frame = recentSnowman.exists ? recentSnowman.frame : .null
            if usableHeightFrame(frame), viewport.contains(frame), recentSnowman.isHittable { break }
            let downward = usableHeightFrame(frame) && frame.minY < viewport.minY
            let start = recentGrid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let finish = start.withOffset(CGVector(dx: 0, dy: min(44, viewport.height * 0.3) * (downward ? 1 : -1)))
            start.press(forDuration: 0.1, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(recentSnowman.exists && usableHeightFrame(recentSnowman.frame)
            && recentGrid.frame.intersection(app.frame).contains(recentSnowman.frame))
        assertRecentKeycaps(in: recentGrid, referenceWidth: savedCapFrame.width)
        assertKeyboardCharacterIsFullyVisible(recentSnowman, identifier: "keyboard.character.U+2603")
        XCTAssertTrue(recentSnowman.isHittable)
        attachScreenshot("Recent uses the same rounded glyph-only number-width keycaps and screen margins")
        recentSnowman.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "☃☃"))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "☃"))
        recentSnowman.press(forDuration: 1)
        let recentName = app.staticTexts["keyboard.properties.name"].firstMatch
        XCTAssertTrue(recentName.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(recentName).localizedCaseInsensitiveContains("snowman"))
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+2603")
        XCTAssertEqual(input.value as? String, context + "☃", "Holding a Recent key inspects without inserting")
        app.buttons["keyboard.properties.close"].tap()
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        favorites.tap()
        XCTAssertTrue(favorites.waitUntilSelected())

        // The magnifier is outside the text viewport: reopen without choosing
        // a new caret. Inserting x must prove the old middle caret survived.
        search.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 20, dy: search.frame.height / 2)).tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        typeKeyboardQueryKeys("x")
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        XCTAssertEqual(input.value as? String, context + "☃")
        assertLowerDeleteInKeyRow("keyboard.query.delete", beside: "keyboard.query.-")
        app.buttons["keyboard.query.delete"].tap()
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"), "The lower query delete must preserve the suffix at the retained middle caret")
        XCTAssertEqual(input.value as? String, context + "☃", "The lower query delete must not touch the host")
        typeKeyboardQueryKeys("x")
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        closeKeyboardSearch()
        assertHostTypingPanel()
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        stepKeyboardHeightToBound(220, input: input, context: context + "☃")
        assertResizeHeight(220)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        favoriteKey.tap()
        XCTAssertTrue(favorites.waitUntilSelected())
        assertResizeHeight(220)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        attachScreenshot("Favorites and Space remain contained at the minimum portrait height")
        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("favorites.landscape", input: input, searching: false, expectedSurfaceHeight: 220)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        XCTAssertEqual(input.value as? String, context + "☃")
        settleKeyboardOrientation(.portrait)
        assertResizeHeight(220)
        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        favoriteKey.tap()
        assertHostTypingPanel()
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        XCTAssertEqual(input.value as? String, context + "☃")
        normalizeKeyboardBrowseHeight(input: input, context: context + "☃")
    }

    private func assertFavoritesKeyImmediatelyPrecedesSpace(file: StaticString = #filePath, line: UInt = #line) {
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let space = app.buttons["keyboard.space"].firstMatch
        let enter = app.buttons["keyboard.return"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(space.waitForExistence(timeout: 5), file: file, line: line)
        let starFrame = star.frame, spaceFrame = space.frame, returnFrame = enter.frame
        for frame in [starFrame, spaceFrame] {
            XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite,
                          file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.width, frame == spaceFrame ? 44 : 36, file: file, line: line)
            XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame), file: file, line: line)
        }
        XCTAssertEqual(starFrame.midY, spaceFrame.midY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(starFrame.height, spaceFrame.height, accuracy: 1, file: file, line: line)
        XCTAssertEqual(spaceFrame.midY, returnFrame.midY, accuracy: 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(spaceFrame.minX - starFrame.maxX, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(spaceFrame.minX - starFrame.maxX, 9, "The star belongs immediately before Space", file: file, line: line)
        XCTAssertTrue(star.isHittable, file: file, line: line)
        XCTAssertTrue(space.isHittable, file: file, line: line)
    }

    func testSystemKeyboardFixedKeycapsAdaptRowsAndFavoriteInsertion() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Fixed keycaps preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        saveKeyboardFavoriteFixture(section: "symbols", query: "u+2603",
                                    identifier: "keyboard.character.U+2603", input: input, context: context)
        saveKeyboardFavoriteFixture(section: "emojis", query: "woman technologist",
                                    identifier: "keyboard.emoji.1F469-200D-1F4BB", input: input, context: context)
        selectSymbolBoard("migrated-favorites", input: input, context: context, returnToTyping: true,
                          preferredStarBoardID: "migrated-favorites")
        enterKeyboardQuery("cat")
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        search.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 36, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        closeKeyboardSearch()

        let fourRowHeight = normalizeKeyboardBrowseHeight(input: input, context: context)
        assertFixedTypingKeycapsAndRows()
        for (delta, label) in [(-90.0, "fixed-rows.fifth"), (90.0, "fixed-rows.fourth"),
                               (90.0, "fixed-rows.third")] {
            dragKeyboardGrip(deltaY: delta, velocity: 240, label: label, input: input, context: context)
            assertFixedTypingKeycapsAndRows()
            XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
            XCTAssertEqual(input.value as? String, context)
        }
        XCTAssertEqual(measuredKeyboardHeight(), max(220, fourRowHeight - 40))
        for bound in [220, 420] {
            stepKeyboardHeightToBound(bound, input: input, context: context)
            assertResizeHeight(bound)
            XCTAssertEqual(measuredKeyboardHeight(), bound)
            assertFixedTypingKeycapsAndRows()
            XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
            XCTAssertEqual(input.value as? String, context)
            attachScreenshot("Fixed typing keycaps and adaptive top rows at the \(bound)-point bound")
        }
        let scalar = symbolBoardKey("☃", typing: true)
        let emoji = symbolBoardKey("👩‍💻", typing: true)
        XCTAssertTrue(scalar.waitForExistence(timeout: 5))
        XCTAssertTrue(emoji.waitForExistence(timeout: 5))
        XCTAssertTrue(scalar.isHittable)
        XCTAssertTrue(emoji.isHittable)
        scalar.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "☃"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x2603])
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context))

        let heldEmoji = symbolBoardKey("👩‍💻", typing: true)
        inspectSymbolBoardKey(heldEmoji, optionCount: 1, input: input, context: context)
        let name = app.staticTexts["keyboard.properties.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(name).localizedCaseInsensitiveContains("woman technologist"))
        XCTAssertEqual(input.value as? String, context, "Holding an English favorite inspects without inserting")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        attachScreenshot("English favorite long hold preserves host and retained Unicode query")
        app.buttons["keyboard.properties.close"].tap()
        let abc = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        if abc.exists { abc.tap() }
        assertHostTypingPanel()
        let restoredEmoji = symbolBoardKey("👩‍💻", typing: true)
        XCTAssertTrue(restoredEmoji.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredEmoji.isHittable)
        restoredEmoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "👩‍💻"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x1F469, 0x200D, 0x1F4BB])
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context), "The complete favorite ZWJ sequence remains one host grapheme")
        let number = app.buttons["keyboard.typing.number.1"].firstMatch
        XCTAssertTrue(number.waitUntilValueEquals("letters"))
        number.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "1"))
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context))

        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let lowerDelete = app.buttons["keyboard.typing.delete"].firstMatch
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        number.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "1"))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "An auxiliary digit preserves manual one-shot Shift")
        typeHostTypingKeys("a")
        XCTAssertTrue(input.waitUntilValueEquals(context + "1A"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"), "The following letter consumes one-shot Shift")
        typeHostTypingKeys("b")
        XCTAssertTrue(input.waitUntilValueEquals(context + "1Ab"))
        for suffix in ["1A", "1", ""] {
            lowerDelete.tap()
            XCTAssertTrue(input.waitUntilValueEquals(context + suffix))
        }

        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        shift.doubleTap()
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"))
        number.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "1"))
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"), "An auxiliary digit preserves Caps Lock")
        typeHostTypingKeys("cd")
        XCTAssertTrue(input.waitUntilValueEquals(context + "1CD"))
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"), "Locked Shift survives the digit and following letters")
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        for suffix in ["1C", "1", ""] {
            lowerDelete.tap()
            XCTAssertTrue(input.waitUntilValueEquals(context + suffix))
        }
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"), "Number-row case handling must leave the retained Unicode query unchanged")

        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.symbols"].firstMatch.waitUntilValueEquals("numbers"))
        assertExpandedSymbolPageHasNoDigits()
        app.buttons["keyboard.typing.auxiliary.#"].tap()
        typeHostTypingKeys("€", layout: "numbers")
        XCTAssertTrue(input.waitUntilValueEquals(context + "#€"), "Both symbol rows insert their exact configured punctuation")
        lowerDelete.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "#"))
        lowerDelete.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context))
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        attachScreenshot("Expanded symbol page keeps normal key widths and replaces redundant digits with symbols")
        app.buttons["keyboard.typing.letters"].tap()
        assertFixedTypingKeycapsAndRows()
        search.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 20, dy: search.frame.height / 2)).tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        typeKeyboardQueryKeys("x")
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"), "Favorite taps, holds and number-row insertion preserve the hidden query caret")
        XCTAssertEqual(input.value as? String, context)
        closeKeyboardSearch()
        normalizeKeyboardBrowseHeight(input: input, context: context)
    }

    private func saveKeyboardFavoriteFixture(section: String, query: String, identifier: String,
                                             input: XCUIElement, context: String) {
        openUnicodeBrowse()
        selectKeyboardSection(section)
        enterKeyboardQuery(query)
        let item = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertTrue(item.isHittable)
        item.press(forDuration: 1)
        saveInspectedKeyToBoard("migrated-favorites", input: input, context: context)
        XCTAssertEqual(input.value as? String, context)
        app.buttons["keyboard.properties.close"].tap()
        let abc = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        XCTAssertTrue(abc.waitForExistence(timeout: 5))
        abc.tap()
        assertHostTypingPanel()
        XCTAssertEqual(input.value as? String, context)
    }

    private func selectSymbolBoard(_ boardID: String, input: XCUIElement, context: String,
                                   returnToTyping: Bool = false, preferredStarBoardID: String? = nil) {
        let footer = app.buttons["keyboard.openFavorites"].firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        footer.press(forDuration: 1)
        let manager = app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch
        XCTAssertTrue(manager.waitForExistence(timeout: 5))
        if let preferredStarBoardID {
            setPreferredSymbolBoardInManager(preferredStarBoardID, input: input, context: context)
        }
        let choice = app.buttons["keyboard.boards.select.\(boardID)"].firstMatch
        let scroll = app.scrollViews["keyboard.boards.scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if choice.exists, usableHeightFrame(choice.frame), scroll.frame.intersection(app.frame).contains(choice.frame), choice.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(choice.exists && usableHeightFrame(choice.frame) && scroll.frame.intersection(app.frame).contains(choice.frame))
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        XCTAssertTrue(manager.waitUntilAbsent())
        XCTAssertEqual(input.value as? String, context, "Selecting a board must not type into the host")
        if returnToTyping {
            XCTAssertTrue(footer.waitUntilValueEquals("favorites"))
            footer.tap()
            assertHostTypingPanel()
        }
        ensureUnicodeToolbarVisible()
    }

    private func setPreferredSymbolBoardInManager(_ boardID: String, input: XCUIElement, context: String) {
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@",
            "keyboard.boards.select.", "Selected")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let previousSelection = selected.identifier
        let target = app.buttons["keyboard.boards.makeDefault.\(boardID)"].firstMatch
        // The current default is deliberately disabled; reveal its selectable
        // board row, then require the actual action's geometry before tapping.
        revealSymbolBoardControl(app.buttons["keyboard.boards.select.\(boardID)"].firstMatch)
        let viewport = app.scrollViews["keyboard.boards.scroll"].firstMatch.frame.intersection(app.frame)
        XCTAssertTrue(target.exists && usableHeightFrame(target.frame) && viewport.contains(target.frame))
        if target.value as? String != "Star default" {
            XCTAssertTrue(target.isEnabled && target.isHittable)
            target.tap()
        }
        XCTAssertTrue(target.waitUntilValueEquals("Star default"))
        XCTAssertFalse(target.isEnabled, "The chosen Star default is visibly distinct from a temporary selection")
        XCTAssertTrue(app.buttons[previousSelection].firstMatch.waitUntilValueEquals("Selected"),
                      "Changing the Star default must leave the current board selected")
        XCTAssertEqual(input.value as? String, context, "Changing the Star default must not insert into the host")
    }

    func testSystemKeyboardPreferredStarBoardSurvivesTemporaryChoiceRelaunchAndDeletion() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Star preference preserves this host."
        var input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        selectSymbolBoard("migrated-favorites", input: input, context: context,
                          preferredStarBoardID: "migrated-favorites")
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        star.press(forDuration: 1)
        assertSymbolBoardOverlay(input: input, context: context)
        app.buttons["keyboard.boards.create"].tap()
        typeSymbolBoardLocalPad("starpref")
        revealSymbolBoardControl(app.buttons["keyboard.boards.pad.save"].firstMatch)
        app.buttons["keyboard.boards.pad.save"].tap()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@",
            "keyboard.boards.select.", "Selected")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let boardID = String(selected.identifier.dropFirst("keyboard.boards.select.".count))
        XCTAssertFalse(["stock-symbols", "migrated-favorites"].contains(boardID))
        setPreferredSymbolBoardInManager(boardID, input: input, context: context)
        let stock = app.buttons["keyboard.boards.select.stock-symbols"].firstMatch
        revealSymbolBoardControl(stock)
        stock.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch.waitUntilAbsent())
        XCTAssertTrue(app.buttons["Symbols"].firstMatch.waitUntilSelected())
        XCTAssertEqual(input.value as? String, context)
        star.tap()
        assertHostTypingPanel()
        star.tap()
        XCTAssertTrue(app.buttons["starpref"].firstMatch.waitUntilSelected(),
                      "A temporary stock choice cannot replace the configured Star target")
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("The Star default and temporary active board are independent choices")

        // An ordinary receiving-app relaunch must keep the saved Star choice.
        app.terminate()
        app.launchArguments = []
        app.launch()
        input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        star.tap()
        XCTAssertTrue(app.buttons["starpref"].firstMatch.waitUntilSelected())
        star.press(forDuration: 1)
        assertSymbolBoardOverlay(input: input, context: context)
        revealSymbolBoardControl(app.buttons["keyboard.boards.select.\(boardID)"].firstMatch)
        XCTAssertTrue(app.buttons["keyboard.boards.makeDefault.\(boardID)"].firstMatch.waitUntilValueEquals("Star default"))
        let edit = app.buttons["keyboard.boards.edit.\(boardID)"].firstMatch
        revealSymbolBoardControl(edit)
        edit.tap()
        let remove = app.buttons["keyboard.boards.delete"].firstMatch
        revealSymbolBoardControl(remove)
        remove.tap()
        XCTAssertTrue(app.buttons["keyboard.boards.select.\(boardID)"].firstMatch.waitUntilAbsent())
        let fallback = app.buttons["keyboard.boards.makeDefault.migrated-favorites"].firstMatch
        revealSymbolBoardControl(app.buttons["keyboard.boards.select.migrated-favorites"].firstMatch)
        XCTAssertTrue(fallback.waitUntilValueEquals("Star default"))
        XCTAssertEqual(input.value as? String, context)
        app.buttons["keyboard.boards.close"].tap()
        star.tap()
        assertHostTypingPanel()
        star.tap()
        XCTAssertTrue(app.buttons["Favorites"].firstMatch.waitUntilSelected(),
                      "Deleting the configured board must restore Favorites as the Star target")
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Deleting the preferred board restores the Favorites Star default")
    }

    private func saveInspectedKeyToBoard(_ boardID: String, input: XCUIElement, context: String) {
        let save = app.buttons["keyboard.properties.favorite"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let choice = app.buttons["keyboard.boards.save.\(boardID)"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.boards.saveTarget"].firstMatch.waitUntilAbsent())
        XCTAssertEqual(input.value as? String, context, "The save target chooser never inserts the selected Unicode text")
    }

    private func symbolBoardKey(_ text: String, typing: Bool = false) -> XCUIElement {
        let prefix = typing ? "keyboard.typing.favorite." : "keyboard.board."
        let points = text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", prefix, ", " + points)).firstMatch
    }

    private func inspectSymbolBoardKey(_ key: XCUIElement, optionCount: Int,
                                       input: XCUIElement, context: String) {
        chooseHeldKeyboardOption(key, optionCount: optionCount, selectedIndex: optionCount,
                                 extraActions: 2)
        XCTAssertTrue(app.buttons["keyboard.properties.close"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, context, "Selecting Inspect from a held key must never insert its original or variants")
    }

    private func chooseHeldKeyboardOption(_ key: XCUIElement, optionCount: Int, selectedIndex: Int,
                                          extraActions: Int = 2) {
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        guard let root = measuredKeyboardSurfaceFrame(), usableHeightFrame(key.frame), app.frame.contains(key.frame) else {
            XCTFail("A hold-and-slide needs the actual visible key and keyboard root"); return
        }
        // The native popup has original/variants then Inspect and Edit. Choose
        // its documented Inspect cell with one continuous real held gesture.
        let count = optionCount + extraActions
        XCTAssertTrue((0..<count).contains(selectedIndex))
        let columns = min(count, max(1, Int(((root.width - 8) / 42).rounded(.down))))
        let rows = (count + columns - 1) / columns
        let cellWidth = min(CGFloat(48), (root.width - 8) / CGFloat(columns))
        let cellHeight = min(CGFloat(48), (root.height - 8) / CGFloat(rows))
        let width = CGFloat(columns) * cellWidth, height = CGFloat(rows) * cellHeight
        let anchor = key.frame
        let x = min(root.maxX - 4 - width, max(root.minX + 4, anchor.midX - width / 2))
        let above = anchor.minY - 6 - height
        let y = min(root.maxY - 4 - height, max(root.minY + 4, above >= root.minY + 4 ? above : anchor.maxY + 6))
        let point = CGPoint(x: x + (CGFloat(selectedIndex % columns) + 0.5) * cellWidth,
                            y: y + (CGFloat(selectedIndex / columns) + 0.5) * cellHeight)
        XCTAssertTrue(root.contains(point))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    func testSystemKeyboardSymbolBoardsPreserveExactVariantsAndLocalConfiguration() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Symbol boards preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        selectSymbolBoard("stock-symbols", input: input, context: context, returnToTyping: true)
        normalizeKeyboardBrowseHeight(input: input, context: context)
        dragKeyboardGrip(deltaY: -90, velocity: 240, label: "boards.single-favorite-row", input: input, context: context)
        assertFixedTypingKeycapsAndRows()
        let first = symbolBoardKey("!", typing: true)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let stripMatches = app.scrollViews.matching(identifier: "keyboard.typing.favorites")
        let strip = stripMatches.firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertEqual(stripMatches.count, 1, "The inline board needs one stable scroll viewport, independent of its lazy keys")
        let last = symbolBoardKey("|", typing: true)
        var dragCount = 0
        for _ in 0..<8 {
            if last.exists, usableHeightFrame(last.frame), strip.frame.intersection(app.frame).contains(last.frame), last.isHittable { break }
            strip.swipeLeft(); dragCount += 1
            XCTAssertEqual(input.value as? String, context, "Horizontal scrolling must cancel the underlying key press")
            XCTAssertTrue(strip.exists, "Virtualizing the first key must not invalidate the scroll viewport")
            XCTAssertEqual(stripMatches.count, 1)
        }
        XCTAssertGreaterThan(dragCount, 0, "The stock board must overflow the one-row inline viewport")
        XCTAssertTrue(last.exists)
        XCTAssertTrue(strip.frame.intersection(app.frame).contains(last.frame))
        let firstRemainsVisible = first.exists && usableHeightFrame(first.frame)
            && strip.frame.intersection(app.frame).contains(first.frame)
        XCTAssertFalse(firstRemainsVisible, "The final viewport must remain usable after the original first-key anchor scrolls away")
        XCTAssertEqual(last.frame.height, 36, accuracy: 1)
        XCTAssertTrue(last.isHittable)
        attachScreenshot("Glyph-only normal keycaps reveal all stock symbols through horizontal scrolling")
        last.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "|"))
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context))
        inspectSymbolBoardKey(symbolBoardKey("|", typing: true), optionCount: 2, input: input, context: context)
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+007C")
        app.buttons["keyboard.properties.close"].tap()
        app.buttons["keyboard.openTyping"].tap()

        openUnicodeBrowse()
        enterKeyboardQuery("cat")
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        search.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 36, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        closeKeyboardSearch()
        app.buttons["keyboard.openFavorites"].press(forDuration: 1)
        assertSymbolBoardOverlay(input: input, context: context)
        XCTAssertTrue(app.buttons["keyboard.boards.create"].waitForExistence(timeout: 5))
        app.buttons["keyboard.boards.create"].tap()
        assertSymbolBoardOverlay(input: input, context: context)
        typeSymbolBoardLocalPad("qaboard")
        stepSymbolBoardEditorAndPreserveEntry("qaboard", input: input, context: context)
        revealSymbolBoardControl(app.buttons["keyboard.boards.pad.save"].firstMatch)
        app.buttons["keyboard.boards.pad.save"].tap()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "keyboard.boards.select.", "Selected")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let boardID = String(selected.identifier.dropFirst("keyboard.boards.select.".count))
        XCTAssertFalse(["stock-symbols", "migrated-favorites"].contains(boardID))
        app.buttons["keyboard.boards.edit.\(boardID)"].tap()
        app.buttons["keyboard.boards.addKey"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.boards.picker"].firstMatch.waitForExistence(timeout: 5))
        enterKeyboardQuery("u+2603")
        let snowman = app.buttons["keyboard.character.U+2603"].firstMatch
        XCTAssertTrue(snowman.waitForExistence(timeout: 10))
        snowman.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, context, "The Unicode picker saves into a board without inserting into the host")
        app.buttons["keyboard.boards.edit.\(boardID)"].tap()
        let editKey = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.boards.key.")).firstMatch
        XCTAssertTrue(editKey.waitForExistence(timeout: 5))
        editKey.tap()
        assertSymbolBoardOverlay(input: input, context: context)
        revealSymbolBoardControl(app.buttons["keyboard.boards.addVariantUnicode"].firstMatch)
        app.buttons["keyboard.boards.addVariantUnicode"].tap()
        selectKeyboardSection("emojis")
        enterKeyboardQuery("woman technologist")
        let emoji = app.buttons["keyboard.emoji.1F469-200D-1F4BB"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        emoji.tap()
        XCTAssertTrue(app.buttons["keyboard.boards.close"].waitForExistence(timeout: 5))
        assertSymbolBoardOverlay(input: input, context: context)
        XCTAssertEqual(input.value as? String, context)
        app.buttons["keyboard.boards.close"].tap()
        settleKeyboardOrientation(.landscapeLeft)
        app.buttons["keyboard.openFavorites"].press(forDuration: 1)
        assertSymbolBoardOverlay(input: input, context: context)
        app.buttons["keyboard.boards.edit.\(boardID)"].tap()
        let compactKeyEdit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.boards.key.")).firstMatch
        revealSymbolBoardControl(compactKeyEdit)
        compactKeyEdit.tap()
        assertSymbolBoardOverlay(input: input, context: context)
        let localVariant = app.buttons["keyboard.boards.addVariantLocal"].firstMatch
        revealSymbolBoardControl(localVariant)
        localVariant.tap()
        assertSymbolBoardOverlay(input: input, context: context)
        typeSymbolBoardLocalPad("v")
        revealSymbolBoardControl(app.buttons["keyboard.boards.pad.save"].firstMatch)
        app.buttons["keyboard.boards.pad.save"].tap()
        let removeTemporaryVariant = app.buttons["keyboard.boards.variant.remove.1"].firstMatch
        revealSymbolBoardControl(removeTemporaryVariant)
        removeTemporaryVariant.tap()
        XCTAssertTrue(removeTemporaryVariant.waitUntilAbsent(), "A real local variant edit must save without touching the host")
        app.buttons["keyboard.boards.back"].tap()
        assertSymbolBoardOverlay(input: input, context: context)
        app.buttons["keyboard.boards.back"].tap()
        assertSymbolBoardOverlay(input: input, context: context)
        app.buttons["keyboard.boards.close"].tap()
        settleKeyboardOrientation(.portrait)
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        let configured = symbolBoardKey("☃")
        XCTAssertTrue(configured.waitForExistence(timeout: 5))
        XCTAssertEqual(configured.frame.height, 36, accuracy: 1)
        chooseHeldKeyboardOption(configured, optionCount: 2, selectedIndex: 1)
        XCTAssertTrue(input.waitUntilValueEquals(context + "👩‍💻"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value), context.unicodeScalars.map(\.value) + [0x1F469, 0x200D, 0x1F4BB])
        app.buttons["keyboard.openFavorites"].tap()
        assertHostTypingPanel()
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context))

        app.buttons["keyboard.openFavorites"].press(forDuration: 1)
        app.buttons["keyboard.boards.edit.\(boardID)"].tap()
        app.buttons["keyboard.boards.rename"].tap()
        for _ in 0..<7 {
            revealSymbolBoardControl(app.buttons["keyboard.boards.pad.delete"].firstMatch)
            app.buttons["keyboard.boards.pad.delete"].tap()
        }
        typeSymbolBoardLocalPad("renamed")
        revealSymbolBoardControl(app.buttons["keyboard.boards.pad.save"].firstMatch)
        app.buttons["keyboard.boards.pad.save"].tap()
        XCTAssertTrue(app.staticTexts["renamed"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["keyboard.boards.delete"].tap()
        XCTAssertTrue(app.buttons["keyboard.boards.select.\(boardID)"].waitUntilAbsent())
        app.buttons["keyboard.boards.close"].tap()
        app.buttons["keyboard.openFavorites"].tap()
        assertHostTypingPanel()
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        search.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("x")
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"), "Configuration, variants and board deletion restore the exact retained middle caret")
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Local symbol-board configuration preserves exact Unicode variants and the host document")
        closeKeyboardSearch()
    }

    private func assertRecentKeycaps(in grid: XCUIElement, referenceWidth: CGFloat,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let viewport = grid.frame.intersection(app.frame)
        guard usableHeightFrame(viewport) else { XCTFail("Expected the real Recent viewport", file: file, line: line); return }
        let frames = grid.buttons.allElementsBoundByAccessibilityElement
            .filter { $0.identifier.hasPrefix("keyboard.character.") || $0.identifier.hasPrefix("keyboard.emoji.") }
            .map(\.frame).filter { usableHeightFrame($0) && viewport.contains($0) }
        XCTAssertFalse(frames.isEmpty, file: file, line: line)
        for frame in frames {
            XCTAssertEqual(frame.height, 36, accuracy: 1, file: file, line: line)
            XCTAssertEqual(frame.width, referenceWidth, accuracy: 1, "Recent matches saved/number-column width", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX + 7, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX - 7, file: file, line: line)
        }
        let ordered = frames.sorted { abs($0.minY-$1.minY) > 1 ? $0.minY < $1.minY : $0.minX < $1.minX }
        for (left, right) in zip(ordered, ordered.dropFirst()) where abs(left.minY-right.minY) <= 1 {
            XCTAssertEqual(right.minX-left.maxX, 5, accuracy: 1, "Recent preserves normal phone key spacing", file: file, line: line)
        }
    }

    private func assertSymbolBoardOverlay(input: XCUIElement, context: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let manager = app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch
        let header = app.descendants(matching: .any)["keyboard.boards.header"].firstMatch
        let scroll = app.scrollViews["keyboard.boards.scroll"].firstMatch
        XCTAssertTrue(manager.waitForExistence(timeout: 5), file: file, line: line)
        guard usableHeightFrame(manager.frame), app.frame.contains(manager.frame),
              header.exists, scroll.exists, usableHeightFrame(header.frame), usableHeightFrame(scroll.frame) else {
            XCTFail("Configuration needs a finite opaque panel, header and bounded scroll viewport", file: file, line: line); return
        }
        let panel = manager.frame, headerFrame = header.frame, viewport = scroll.frame
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let roots = app.otherElements.containing(.any, identifier: "keyboard.boards.manager")
            .allElementsBoundByAccessibilityElement.map(\.frame).filter { frame in
                self.usableHeightFrame(frame) && self.app.frame.contains(frame) && abs(frame.width-self.app.frame.width) <= 1
                    && frame.contains(panel) && (!grip.exists || frame.contains(grip.frame))
            }.sorted { $0.height < $1.height }
        guard let root = roots.first else { XCTFail("Expected the actual full-width root containing the board overlay", file: file, line: line); return }
        let gripHeight: CGFloat = grip.exists ? grip.frame.height : 0
        let geometry = XCTAttachment(string: "manager=\(panel) header=\(headerFrame) viewport=\(viewport) root=\(root) gripHeight=\(gripHeight)")
        geometry.name = "Actual symbol-board accessibility container and inner viewport bounds"
        geometry.lifetime = .keepAlways
        add(geometry)
        // The remote landscape keyboard container also contains iOS's
        // lateral globe/dictation gutters and bottom safe-area band. Its
        // hosted extension panel must stay centred and wholly contained.
        // Portrait exposes the extension's exact allocation instead.
        if app.frame.width > app.frame.height {
            XCTAssertEqual(panel.midX, root.midX, accuracy: 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(panel.width, root.width * 0.7, file: file, line: line)
            XCTAssertEqual(panel.height, 220, accuracy: 1, file: file, line: line)
            XCTAssertLessThanOrEqual(panel.maxY, root.maxY, file: file, line: line)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Original landscape hosted panel and system keyboard gutters"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        } else {
            XCTAssertEqual(panel.minX-root.minX, 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(root.maxX-panel.maxX, 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(root.maxY-panel.maxY, 0, accuracy: 1, file: file, line: line)
        }
        XCTAssertEqual(panel.minY-root.minY, gripHeight, accuracy: 1, file: file, line: line)
        // The explicit panel container includes the caller's outer padding.
        // Measure its real scroll viewport, never the OS-owned gutters.
        XCTAssertEqual(viewport.minX-panel.minX, 8, accuracy: 1, file: file, line: line)
        XCTAssertEqual(panel.maxX-viewport.maxX, 8, accuracy: 1, file: file, line: line)
        XCTAssertEqual(panel.maxY-viewport.maxY, 8, accuracy: 1, file: file, line: line)
        // This AX group reports the union of its 32-point navigation
        // controls, centred inside the actual 36-point header layout band.
        let headerBand = CGRect(x: viewport.minX, y: panel.minY + 8, width: viewport.width, height: 36)
        XCTAssertEqual(headerFrame.height, 32, accuracy: 1, file: file, line: line)
        XCTAssertEqual(headerFrame.midY, headerBand.midY, accuracy: 1, file: file, line: line)
        XCTAssertTrue(headerBand.contains(headerFrame), file: file, line: line)
        XCTAssertEqual(viewport.minY-headerBand.maxY, 6, accuracy: 1, file: file, line: line)
        XCTAssertTrue(panel.contains(headerFrame) && panel.contains(viewport), file: file, line: line)
        XCTAssertGreaterThanOrEqual(viewport.minY-headerFrame.maxY, 4, file: file, line: line)
        for id in ["keyboard.boards.back", "keyboard.boards.close"] {
            let control = app.buttons[id].firstMatch
            if id == "keyboard.boards.back" && !control.exists { continue }
            let navigationGeometry = XCTAttachment(string: "\(id) frame=\(control.frame) headerBand=\(headerBand)")
            navigationGeometry.name = "Actual symbol-board navigation bounds"
            navigationGeometry.lifetime = .keepAlways
            add(navigationGeometry)
            // Navigation belongs to the full layout band. AX focus unions
            // can round a shared edge by a fraction of a display pixel.
            guard control.exists, usableHeightFrame(control.frame),
                  headerBand.insetBy(dx: -0.5, dy: -0.5).contains(control.frame),
                  app.frame.insetBy(dx: -0.5, dy: -0.5).contains(control.frame) else {
                XCTFail("Board navigation must remain fully inside its fixed header", file: file, line: line); return
            }
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, file: file, line: line)
            XCTAssertGreaterThanOrEqual(control.frame.height, 32, file: file, line: line)
            XCTAssertTrue(control.isHittable, file: file, line: line)
        }
        // This six-point separator is deliberately inert. Its opaque panel
        // must intercept the underlying toolbar/key instead of forwarding it.
        let point = CGPoint(x: panel.midX, y: (headerFrame.maxY+viewport.minY)/2)
        XCTAssertTrue(panel.contains(point), file: file, line: line)
        app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x-app.frame.minX, dy: point.y-app.frame.minY)).tap()
        XCTAssertTrue(manager.exists, file: file, line: line)
        XCTAssertTrue(input.waitUntilValueEquals(context), file: file, line: line)
        attachScreenshot("Opaque symbol-board editor owns its full header/body/footer area without host insertion")
    }

    private func stepSymbolBoardEditorAndPreserveEntry(_ entryText: String, input: XCUIElement, context: String) {
        let manager = app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch
        let entry = app.descendants(matching: .any)["keyboard.boards.entry"].firstMatch
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        XCTAssertTrue(entry.waitUntilValueEquals(entryText))
        guard manager.exists, grip.exists, usableHeightFrame(manager.frame), usableHeightFrame(grip.frame),
              app.frame.contains(grip.frame) else { XCTFail("Expected the visible portrait editor and native resize grip"); return }
        let panel = manager.frame, handle = grip.frame
        let roots = app.otherElements.containing(.any, identifier: "keyboard.boards.manager")
            .allElementsBoundByAccessibilityElement.map(\.frame).filter { frame in
                self.usableHeightFrame(frame) && self.app.frame.contains(frame) && abs(frame.width-self.app.frame.width) <= 1
                    && frame.contains(panel) && frame.contains(handle)
            }.sorted { $0.height < $1.height }
        guard let before = roots.first else { XCTFail("Expected the actual editor keyboard surface"); return }
        let current = Int(before.height.rounded())
        let upward = current < 420
        let expected = min(420, max(220, current + (upward ? 40 : -40)))
        XCTAssertTrue(grip.isHittable)
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: handle.midX-app.frame.minX, dy: handle.midY+(upward ? -90 : 90)-app.frame.minY))
        grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        assertResizeHeight(expected)
        XCTAssertEqual(grip.frame.minY, before.maxY-CGFloat(expected), accuracy: 1)
        XCTAssertTrue(manager.exists, "Resizing must preserve the mounted local editor session")
        XCTAssertTrue(entry.waitUntilValueEquals(entryText), "The exact nonempty local entry survives one row step")
        XCTAssertEqual(input.value as? String, context)
        assertSymbolBoardOverlay(input: input, context: context)
        attachScreenshot("Symbol-board local entry survives resizing and permits a fresh guarded Save")
        // The caller now presses the real Save button and verifies the new
        // board appears, proving the lifetime guard was not left stale.
    }

    private func typeSymbolBoardLocalPad(_ text: String) {
        for character in text {
            let key = app.buttons["keyboard.boards.pad.\(character)"].firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5))
            revealSymbolBoardControl(key)
            XCTAssertTrue(key.isHittable)
            key.tap()
        }
    }

    private func revealSymbolBoardControl(_ control: XCUIElement) {
        let scroll = app.scrollViews["keyboard.boards.scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for step in 0..<8 {
            let viewport = scroll.frame.intersection(app.frame)
            guard usableHeightFrame(viewport) else { XCTFail("Expected the actual configuration viewport"); return }
            print("UNIBOARD_EDITOR_REVEAL step=\(step) target=\(control.identifier) viewport=\(viewport) targetFrame=\(control.exists ? String(describing: control.frame) : "absent")")
            if control.exists, usableHeightFrame(control.frame), viewport.contains(control.frame), control.isHittable { return }
            let down = control.exists && usableHeightFrame(control.frame) && control.frame.minY < viewport.minY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: min(44, viewport.height * 0.3) * (down ? 1 : -1)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let revealed = control.exists && usableHeightFrame(control.frame) && scroll.frame.intersection(app.frame).contains(control.frame)
        if !revealed {
            attachScreenshot("Original symbol-board target reveal failure")
            let diagnostic = XCTAttachment(string: "target=\(control.identifier) frame=\(control.exists ? String(describing: control.frame) : "absent") viewport=\(scroll.frame)\n\(app.debugDescription)")
            diagnostic.name = "Original symbol-board viewport and target after bounded physical scrolling"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }
        XCTAssertTrue(revealed)
        XCTAssertTrue(control.isHittable)
    }

    private func assertFixedTypingKeycapsAndRows(file: StaticString = #filePath, line: UInt = #line) {
        assertHostTypingPanel(file: file, line: line)
        let q = app.buttons["keyboard.typing.key.q"].firstMatch.frame
        let a = app.buttons["keyboard.typing.key.a"].firstMatch.frame
        let m = app.buttons["keyboard.typing.key.m"].firstMatch.frame
        let toolbarOn = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.value as? String == "on"
        guard let surface = measuredKeyboardSurfaceFrame() else { XCTFail("Expected actual typing root", file: file, line: line); return }
        let bodyHeight = surface.height - (toolbarOn ? 100 : 64)
        XCTAssertGreaterThan(bodyHeight, 12, file: file, line: line)
        XCTAssertEqual(q.height, a.height, accuracy: 1, file: file, line: line)
        XCTAssertEqual(a.height, m.height, accuracy: 1, file: file, line: line)
        XCTAssertLessThanOrEqual(q.height, 36 + 1, "Extra height adds rows rather than stretching caps", file: file, line: line)
        if bodyHeight >= 116 { XCTAssertEqual(q.height, 36, accuracy: 1, file: file, line: line) }
        XCTAssertEqual(a.minY - q.maxY, 4, accuracy: 1, file: file, line: line)
        XCTAssertEqual(m.minY - a.maxY, 4, accuracy: 1, file: file, line: line)
        let digitFrames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.typing.number."))
            .allElementsBoundByAccessibilityElement.map(\.frame)
        XCTAssertEqual(digitFrames.count, bodyHeight >= 156 ? 10 : 0, file: file, line: line)
        for frame in digitFrames {
            XCTAssertTrue(usableHeightFrame(frame), file: file, line: line)
            XCTAssertTrue(app.frame.contains(frame), file: file, line: line)
            XCTAssertEqual(frame.height, q.height, accuracy: 1, file: file, line: line)
            XCTAssertEqual(q.minY - frame.maxY, 4, accuracy: 1, file: file, line: line)
        }
        let favoriteFrames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.typing.favorite."))
            .allElementsBoundByAccessibilityElement.map(\.frame).filter { self.usableHeightFrame($0) && self.app.frame.contains($0) }
        if bodyHeight < 196 { XCTAssertTrue(favoriteFrames.isEmpty, file: file, line: line) }
        else {
            XCTAssertFalse(favoriteFrames.isEmpty, "Saved fixtures occupy available fifth rows above digits", file: file, line: line)
            for frame in favoriteFrames {
                XCTAssertEqual(frame.height, q.height, accuracy: 1, file: file, line: line)
                if let digit = digitFrames.first {
                    XCTAssertLessThan(frame.maxY, digit.minY, file: file, line: line)
                    XCTAssertEqual(frame.width, digit.width, accuracy: 1,
                                   "Saved symbol keys use the same ten-column width as the number row", file: file, line: line)
                }
            }
        }
        // Cache plain frames before sorting so comparisons never issue AX calls.
        var rowFrames = [q, a, m] + digitFrames.prefix(1) + favoriteFrames
        rowFrames.sort { $0.minY < $1.minY }
        var previous: CGRect?
        for frame in rowFrames {
            if let before = previous, abs(before.minY - frame.minY) > 1 {
                XCTAssertEqual(frame.minY - before.maxY, 4, accuracy: 1,
                               "Adaptive rows must not introduce giant vertical gaps", file: file, line: line)
            }
            if previous == nil || abs(previous!.minY - frame.minY) > 1 { previous = frame }
        }
    }

    private func assertExpandedSymbolPageHasNoDigits(file: StaticString = #filePath, line: UInt = #line) {
        for digit in "0123456789" {
            XCTAssertFalse(app.buttons["keyboard.typing.key.\(digit)"].exists, file: file, line: line)
            XCTAssertFalse(app.buttons["keyboard.typing.number.\(digit)"].exists, file: file, line: line)
        }
        let auxiliary = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
            .map { app.buttons["keyboard.typing.auxiliary.\($0)"].firstMatch }
        let core = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
            .map { app.buttons["keyboard.typing.key.\($0)"].firstMatch }
        for control in auxiliary + core {
            XCTAssertTrue(control.waitForExistence(timeout: 5), file: file, line: line)
            let frame = control.frame
            guard usableHeightFrame(frame), app.frame.contains(frame) else {
                XCTFail("Expanded symbols must have finite, fully visible keycaps", file: file, line: line); return
            }
            XCTAssertTrue(control.isHittable, file: file, line: line)
            XCTAssertEqual(frame.height, 36, accuracy: 1, file: file, line: line)
            XCTAssertEqual(frame.width, auxiliary[0].frame.width, accuracy: 1,
                           "Symbol pages use the same ten-column key widths", file: file, line: line)
        }
        XCTAssertEqual(core[0].frame.minY - auxiliary[0].frame.maxY, 4, accuracy: 1, file: file, line: line)
    }

    func testSystemKeyboardEnglishReturnActionsRestoreLetterKeys() throws {
        try requireKeyboardIntegration()
        var input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch

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
        XCTAssertTrue(abc.waitUntilValueEquals("unicode"))
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
        XCTAssertTrue(search.waitUntilValueEquals("cat"))
        typeHostTypingKeys("q")
        XCTAssertTrue(input.waitUntilValueEquals("Qq"))
        XCTAssertTrue(search.waitUntilValueEquals("cat"), "Restored host letters must not change the retained local query")
        attachScreenshot("Done returns from a Unicode query to actual English letters after the symbol page")
    }

    func testSystemKeyboardEnglishNumberPageRefreshesSentenceCase() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let numbers = app.buttons["keyboard.typing.numbers"].firstMatch
        let letters = app.buttons["keyboard.typing.letters"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch

        XCTAssertTrue(input.waitUntilValueEquals(""))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        numbers.tap()
        XCTAssertTrue(letters.waitUntilValueEquals("numbers"))
        typeHostTypingKeys("1", layout: "numbers")
        XCTAssertTrue(input.waitUntilValueEquals("1"))
        letters.tap()
        assertHostTypingPanel()
        XCTAssertTrue(app.buttons["keyboard.typing.key.a"].firstMatch.waitUntilValueEquals("letters"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"),
                      "ABC must refresh the stale initial capital after a host digit")
        XCTAssertEqual(input.value as? String, "1", "Switching back to letters must not insert text")
        typeHostTypingKeys("a")
        XCTAssertTrue(input.waitUntilValueEquals("1a"))
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        attachScreenshot("ABC refreshes lowercase after typing a host digit on the number page")

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
        typeHostTypingKeys("b")
        XCTAssertTrue(input.waitUntilValueEquals("1a. B"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        XCTAssertTrue(search.waitUntilValueEquals("No query"), "Host page and case changes must not enter a local query")
        assertHeaderDeleteAtTopRight()
        attachScreenshot("ABC refreshes sentence capitalization after number-page period and Space")
    }

    func testSystemKeyboardHeldDeleteKeepsQueryAndHostScopesSeparate() throws {
        try requireKeyboardIntegration()
        let context = "Retain this host context."
        let input = openSystemKeyboardHost(initialText: context)
        defer { restoreEnglishKeyboard() }
        let query = "abcdefghijklmnop"
        enterKeyboardQuery(query)
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let delete = app.buttons["keyboard.delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))

        delete.press(forDuration: 0.75)
        let remainingQuery = search.value as? String ?? ""
        XCTAssertFalse(remainingQuery.isEmpty)
        XCTAssertTrue(query.hasPrefix(remainingQuery), "Held search delete may only remove the query suffix")
        XCTAssertGreaterThanOrEqual(query.count - remainingQuery.count, 2,
                                    "The real hold must exercise repeating deletion, not only one tap")
        XCTAssertEqual(input.value as? String, context, "Query deletion must never reach the host")
        assertValueRemainsAfterRelease(search, equals: remainingQuery)
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Held query delete stops on release without changing host text")

        closeKeyboardSearch()
        XCTAssertTrue(search.waitUntilValueEquals(remainingQuery))
        delete.press(forDuration: 0.75)
        let remainingHost = input.value as? String ?? ""
        XCTAssertFalse(remainingHost.isEmpty)
        XCTAssertTrue(context.hasPrefix(remainingHost), "Folded delete may only remove the host suffix")
        XCTAssertGreaterThanOrEqual(context.count - remainingHost.count, 2,
                                    "The real folded hold must exercise repeating host deletion")
        XCTAssertEqual(search.value as? String, remainingQuery, "Folded host deletion must retain the query")
        assertValueRemainsAfterRelease(input, equals: remainingHost)
        XCTAssertTrue(search.waitUntilValueEquals(remainingQuery))
        attachScreenshot("Held host delete stops on release and preserves the folded query")
    }

    func testSystemKeyboardReadsAppFontSettingsAndPreservesExactInsertion() throws {
        try requireKeyboardIntegration()
        selectAppEdition("latest")
        setAppUnicodeFonts(false)
        setAppCollapseKey(false)
        app.launchArguments = []
        var input = openSystemKeyboardHost()
        defer {
            XCUIDevice.shared.orientation = .portrait
            if app.buttons["keyboard.properties.close"].firstMatch.exists {
                app.buttons["keyboard.properties.close"].firstMatch.tap()
            }
            if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
            restoreEnglishKeyboard()
        }
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        XCTAssertFalse(app.buttons["keyboard.collapse"].exists)
        enterKeyboardQuery("u+0558")
        let armenian = app.buttons["keyboard.character.U+0558"].firstMatch
        XCTAssertTrue(armenian.waitForExistence(timeout: 10))
        XCTAssertFalse((armenian.value as? String ?? "").contains("Preview font:"))
        XCTAssertEqual(input.value as? String, "")
        attachScreenshot("App Settings fonts off preserves the native keyboard glyph preview")
        restoreEnglishKeyboard()
        setAppUnicodeFonts(true)
        setAppCollapseKey(true)
        input = openSystemKeyboardHost()
        XCTAssertTrue(app.buttons["keyboard.collapse"].firstMatch.waitForExistence(timeout: 5),
                      "The keyboard reads its optional collapse-key choice from App Settings")
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        enterKeyboardQuery("u+0558")
        let enabledArmenian = app.buttons["keyboard.character.U+0558"].firstMatch
        XCTAssertTrue(enabledArmenian.waitUntilValueEquals("Preview font: GNU Unifont"))
        enabledArmenian.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+0558", nameContaining: "Armenian small eh")
        let source = app.staticTexts["keyboard.properties.fontSource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(source), "GNU Unifont")
        XCTAssertEqual(input.value as? String, "", "Font-backed inspection must not insert a preview")
        attachScreenshot("Bundled Armenian glyph inspection preserves original Unicode properties")
        app.buttons["keyboard.properties.close"].tap()
        app.buttons.matching(identifier: "keyboard.character.U+0558").firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\u{0558}"))
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        attachScreenshot("Optional font preview inserts the original scalar with intact portrait toolbar")
        closeKeyboardSearch()

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return frame.width > frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        enterKeyboardQuery("u+10940")
        assertKeyboardControlsAreVisible(isSearching: true)
        assertHostEditorIsVisibleAboveKeyboard(input)
        let sidetic = app.buttons["keyboard.character.U+10940"].firstMatch
        XCTAssertTrue(sidetic.waitForExistence(timeout: 10))
        XCTAssertTrue(sidetic.waitUntilValueEquals("Preview font: GNU Unifont Upper"))
        XCTAssertTrue(sidetic.isHittable)
        XCTAssertEqual(input.value as? String, "\u{0558}", "Query typing must stay inside the extension")
        sidetic.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\u{0558}\u{10940}"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map { $0.value }, [0x0558, 0x10940])
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        attachScreenshot("Supplementary fallback glyph inserts exact text in compact landscape")
        closeKeyboardSearch()
        openUnicodeBrowse()
        let returnedSidetic = app.buttons.matching(identifier: "keyboard.character.U+10940").firstMatch
        XCTAssertTrue(returnedSidetic.waitForExistence(timeout: 5))
        XCTAssertTrue(returnedSidetic.isHittable)
        returnedSidetic.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+10940", nameContaining: "Sidetic letter n01")
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.fontSource"].firstMatch), "GNU Unifont Upper")
        XCTAssertEqual(input.value as? String, "\u{0558}\u{10940}")
        attachScreenshot("Compact font settings and direct Unicode inspection remain usable after insertion")
        app.buttons["keyboard.properties.close"].tap()

        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return frame.width < frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        selectKeyboardSection("emojis")
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilLabelEquals("Search emoji sequences"))
        attachScreenshot("Portrait emoji section settles before querying native sequence")
        enterKeyboardQuery("head shaking horizontally")
        let emoji = app.buttons["keyboard.emoji.1F642-200D-2194-FE0F"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        XCTAssertFalse((emoji.value as? String ?? "").contains("Preview font:"), "Whole emoji sequences must retain iOS rendering")
        emoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\u{0558}\u{10940}🙂‍↔️"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map { $0.value },
                       [0x0558, 0x10940, 0x1F642, 0x200D, 0x2194, 0xFE0F])
        attachScreenshot("Extra character fonts preserve complete native emoji sequence insertion")
        closeKeyboardSearch()
        for expected in ["\u{0558}\u{10940}", "\u{0558}", ""] {
            app.buttons["keyboard.delete"].tap()
            XCTAssertTrue(input.waitUntilValueEquals(expected), "Delete must remove each complete original character")
        }

        input = openSystemKeyboardHost()
        enterKeyboardQuery("u+0558")
        XCTAssertTrue(app.buttons["keyboard.character.U+0558"].firstMatch.waitUntilValueEquals("Preview font: GNU Unifont"),
                      "The app-owned font choice persists across ordinary host relaunch")
        XCTAssertEqual(input.value as? String, "")
        restoreEnglishKeyboard()
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("1"))
        setAppUnicodeFonts(false)
        setAppCollapseKey(false)
        input = openSystemKeyboardHost()
        XCTAssertFalse(app.buttons["keyboard.collapse"].firstMatch.exists)
        enterKeyboardQuery("u+0558")
        let disabledArmenian = app.buttons["keyboard.character.U+0558"].firstMatch
        XCTAssertTrue(disabledArmenian.waitForExistence(timeout: 10))
        XCTAssertFalse((disabledArmenian.value as? String ?? "").contains("Preview font:"))
        XCTAssertEqual(input.value as? String, "")
        disabledArmenian.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\u{0558}"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value), [0x0558])
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        attachScreenshot("App Settings fonts and collapse off are reflected by the relaunched keyboard")
    }


    func testSystemKeyboardOpenCompanionAppRoutesToSettingsOrShowsDeniedGuidance() throws {
        try requireKeyboardIntegration()
        let context = "Opening settings must not type into this host."
        let input = openSystemKeyboardHost(initialText: context)
        defer { if input.exists { restoreEnglishKeyboard() } }
        enterKeyboardQuery("cat")
        XCTAssertEqual(input.value as? String, context)
        XCTAssertTrue(app.navigationBars["Try Uniboard"].exists)
        XCTAssertFalse(app.navigationBars["Settings"].exists,
                       "The host must be on its pushed screen before exercising the Settings route")
        assertCompanionAppMenuActuation(input: input, context: context, query: "cat")
    }

    private func assertCompanionAppMenuActuation(input: XCUIElement, context: String, query: String,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(input.waitUntilValueEquals(context), file: file, line: line)
        XCTAssertTrue(search.waitUntilValueEquals(query), file: file, line: line)
        openKeyboardOptions()
        // The remote native popup removes the covered query control from
        // accessibility. Require its actual pre-popup snapshot instead;
        // denied navigation also verifies the live query after dismissal.
        XCTAssertEqual(keyboardOptionsSnapshot?.hostText, context, file: file, line: line)
        XCTAssertEqual(keyboardOptionsSnapshot?.queryValue, query, file: file, line: line)
        guard let popup = nativeKeyboardOptionsPopup() else {
            XCTFail("Require the actual native options popup before opening the companion app", file: file, line: line); return
        }
        let action = app.descendants(matching: .any)["keyboard.openCompanionApp"].firstMatch
        guard revealNativeKeyboardOption(action, in: popup), usableHeightFrame(action.frame),
              popup.frame.intersection(app.frame).insetBy(dx: -1, dy: -1).contains(action.frame) else {
            XCTFail("Open companion app must be fully visible in its actual native popup", file: file, line: line); return
        }
        XCTAssertTrue(action.isHittable, file: file, line: line)
        XCTAssertEqual(input.value as? String, context, file: file, line: line)
        attachScreenshot("Actual companion app menu action before its single tap")
        action.tap()
        keyboardOptionsSnapshot = nil

        let settings = app.navigationBars["Settings"].firstMatch
        let selector = app.descendants(matching: .any)["unicodeEdition"].firstMatch
        let guidance = app.descendants(matching: .any)["keyboard.openCompanionApp.guidance"].firstMatch
        let explanation = app.staticTexts["Open Uniboard from the Home Screen to change settings."].firstMatch
        func settingsAreVisible() -> Bool {
            guard settings.exists, !app.navigationBars["Try Uniboard"].exists, !input.exists,
                  selector.exists, usableHeightFrame(selector.frame), app.frame.contains(selector.frame) else { return false }
            return selector.isHittable
        }
        func deniedGuidanceIsVisible() -> Bool {
            guard guidance.exists, explanation.exists, usableHeightFrame(guidance.frame),
                  usableHeightFrame(explanation.frame), app.frame.contains(guidance.frame),
                  guidance.frame.contains(explanation.frame) else { return false }
            return explanation.isHittable
        }
        let outcome = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            settingsAreVisible() || deniedGuidanceIsVisible()
        }, object: app)
        guard XCTWaiter.wait(for: [outcome], timeout: 10) == .completed else {
            attachScreenshot("Companion app action produced neither real Settings nor explicit denial guidance")
            XCTFail("One real menu tap must open Settings or show the explicit Home Screen guidance", file: file, line: line); return
        }
        XCTAssertTrue(popup.waitUntilAbsent(), file: file, line: line)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), file: file, line: line)
        let openedSettings = settingsAreVisible()
        let denied = deniedGuidanceIsVisible()
        XCTAssertNotEqual(openedSettings, denied, "Exactly one actual route outcome must be visible", file: file, line: line)
        if openedSettings {
            // The route deliberately recreates the Settings navigation stack.
            // Its removed host view cannot supply an after-navigation text read.
            XCTAssertFalse(input.exists, file: file, line: line)
            XCTAssertFalse(guidance.exists, file: file, line: line)
            attachScreenshot("Open companion app actually navigates from the host to App Settings")
        } else {
            XCTAssertTrue(denied, file: file, line: line)
            XCTAssertTrue(app.navigationBars["Try Uniboard"].exists, file: file, line: line)
            XCTAssertTrue(input.waitUntilValueEquals(context), file: file, line: line)
            XCTAssertTrue(search.waitUntilValueEquals(query), file: file, line: line)
            assertHostEditorIsVisibleAboveKeyboard(input, file: file, line: line)
            attachScreenshot("OS-denied companion opening leaves exact host and query with explicit Home Screen guidance")
        }
        let receipt: [String: Any] = ["actionTaps": 1,
            "outcome": openedSettings ? "actual-settings-navigation" : "explicit-os-denied-guidance",
            "hostTextVerifiedBeforeTap": context, "queryVerifiedBeforeTap": query,
            "postNavigationHostReadAvailable": !openedSettings,
            "manualNavigationOrRetryUsed": false]
        let data = try! JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Native companion app route outcome"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSystemKeyboardCompactLayoutPreservesVisibleHostAndExactInput() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        setAppUnicodeFonts(false)
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        normalizeKeyboardBrowseHeight(input: input, context: context)
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        assertCompactKeyboardGeometry("portrait.browse", input: input, searching: false)
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
        app.buttons["keyboard.delete"].tap()
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
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        settleKeyboardOrientation(.portrait)
        assertCompactKeyboardGeometry("portrait.returned.browse", input: input, searching: false)
        enterKeyboardQuery("u+1f680")
        assertCompactKeyboardGeometry("portrait.returned.search", input: input, searching: true)
        XCTAssertEqual(input.value as? String, context + "🚀", "Rotation and query controls never leak into the host")
        attachScreenshot("Compact glass keyboard returns to portrait without stale landscape layout")
        closeKeyboardSearch()
    }

    func testSystemKeyboardPortraitResizeAndFoldedSearchPreserveInput() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Host context stays visible."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let initialHeight = normalizeKeyboardBrowseHeight(input: input, context: context)

        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        attachResizeFrameDiagnostics(input: input)
        XCTAssertTrue(grip.isHittable)
        assertResizeHeight(initialHeight)
        assertCompactKeyboardGeometry("resizable.portrait.initial", input: input, searching: false,
                                      expectedSurfaceHeight: CGFloat(initialHeight))
        stepKeyboardHeightToBound(420, input: input, context: context)
        assertCompactKeyboardGeometry("resizable.portrait.expanded", input: input, searching: false,
                                      expectedSurfaceHeight: 420)
        stepKeyboardHeightToBound(220, input: input, context: context)
        assertCompactKeyboardGeometry("resizable.portrait.collapsed", input: input, searching: false,
                                      expectedSurfaceHeight: 220)

        // A qualifying upward gesture adds exactly one row at release,
        // irrespective of this gesture's85-point travel.
        dragKeyboardGrip(deltaY: -85, velocity: 240, label: "manual.one-row-from-minimum",
                         input: input, context: context)
        let intermediate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let height = self.keyboardResizeHeight() else { return false }
            return height > 240 && height < 335
        }, object: grip)
        XCTAssertEqual(XCTWaiter.wait(for: [intermediate], timeout: 5), .completed,
                       "One upward row step from220 must settle at260 points")
        let manualHeight = keyboardResizeHeight() ?? 0
        XCTAssertEqual(manualHeight, 260)
        XCTAssertGreaterThan(manualHeight, 240)
        XCTAssertLessThan(manualHeight, 335)
        assertCompactKeyboardGeometry("resizable.portrait.manual", input: input, searching: false,
                                      expectedSurfaceHeight: CGFloat(manualHeight))
        XCTAssertEqual(input.value as? String, context)

        enterKeyboardQuery("cat")
        let queryField = app.descendants(matching: .any)["keyboard.search"].firstMatch
        // The real native field's text viewport begins 34 points from its
        // leading edge, after the search icon. Tap the start of its short,
        // unscrolled text rather than assuming insertion always appends.
        queryField.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 36, dy: queryField.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(queryField.waitUntilValueEquals("arrow cat"),
                      "Tapping at the beginning must move the caret before the existing query")
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(queryField.waitUntilValueEquals("arrowcat"),
                      "Backspace must delete before the moved caret while preserving its suffix")
        XCTAssertEqual(input.value as? String, context, "Caret placement and local query editing must not enter host text")
        attachScreenshot("Native query caret follows tapped text and preserves the suffix during insertion and deletion")

        enterKeyboardQuery("suzhou numerals")
        let numeral = app.buttons["keyboard.character.U+3021"].firstMatch
        XCTAssertTrue(numeral.waitForExistence(timeout: 10))
        numeral.press(forDuration: 1)
        let numeralName = app.staticTexts["keyboard.properties.name"].firstMatch
        XCTAssertTrue(numeralName.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(numeralName).localizedCaseInsensitiveContains("Hangzhou numeral one"))
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+3021")
        XCTAssertEqual(input.value as? String, context, "Holding a Suzhou search result must inspect without inserting")
        assertCompactKeyboardGeometry("resizable.portrait.suzhou.properties", input: input, searching: false,
                                      inspecting: true, expectedSurfaceHeight: 340)
        attachScreenshot("Native Suzhou numeral properties preserve the official Hangzhou name and visible host")
        let section = app.staticTexts["keyboard.properties.section"].firstMatch
        let notes = app.staticTexts["keyboard.properties.notes"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(section).localizedCaseInsensitiveContains("Suzhou numerals"))
        XCTAssertTrue(accessibleText(notes).localizedCaseInsensitiveContains("Hangzhou"))
        XCTAssertTrue(accessibleText(notes).localizedCaseInsensitiveContains("misnomer"))
        let propertyScroll = app.scrollViews.containing(.staticText, identifier: "keyboard.properties.description").firstMatch
        XCTAssertTrue(propertyScroll.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if isReadableInScrollViewport(notes, in: propertyScroll) { break }
            let viewport = propertyScroll.frame
            let direction: CGFloat = notes.frame.midY < viewport.midY ? 1 : -1
            let start = propertyScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: direction * min(40, viewport.height * 0.25)))
            // A flick can pass a middle note between snapshots. Slow, short
            // drags with an end hold stop at readable content without inertia.
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(isReadableInScrollViewport(notes, in: propertyScroll), "The section naming note must be reachable and readable inside the native inspector")
        attachScreenshot("Suzhou section and Hangzhou misnomer note remain readable in the native inspector")
        XCTAssertEqual(input.value as? String, context)
        app.buttons["keyboard.properties.close"].tap()
        enterKeyboardQuery("u+1f680")
        assertResizeHeight(340)
        assertCompactKeyboardGeometry("resizable.portrait.search", input: input, searching: true,
                                      expectedSurfaceHeight: 340)
        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, context, "Query editing must not enter host text")
        closeKeyboardSearch()
        assertResizeHeight(manualHeight)
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+1f680"))
        openUnicodeBrowse()
        XCTAssertTrue(rocket.waitForExistence(timeout: 5), "Explicit Browse must restore the filtered result retained by Done")
        XCTAssertTrue(rocket.isHittable)
        XCTAssertTrue(app.buttons["keyboard.search.clear"].firstMatch.isHittable,
                      "A folded query must still offer its clear action")
        assertCompactKeyboardGeometry("resizable.portrait.folded.results", input: input, searching: false,
                                      expectedSurfaceHeight: CGFloat(manualHeight))
        XCTAssertEqual(input.value as? String, context, "Done folds search without changing the host")
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x1F680])

        // Browse controls operate on the real host while the retained query
        // and filtered catalog remain visible; local query keys are closed.
        app.buttons["keyboard.space"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀 "))
        app.buttons["keyboard.return"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀 \n"))
        for expected in [context + "🚀 ", context + "🚀"] {
            app.buttons["keyboard.delete"].tap()
            XCTAssertTrue(input.waitUntilValueEquals(expected))
        }
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+1f680"))
        XCTAssertTrue(rocket.exists)

        reopenKeyboardSearch(expectedQuery: "u+1f680")
        assertResizeHeight(340)
        XCTAssertEqual(input.value as? String, context + "🚀")
        closeKeyboardSearch()
        let clear = app.buttons["keyboard.search.clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("No query"))
        XCTAssertTrue(clear.waitUntilAbsent())
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(),
                      "Clearing a folded query must not reopen query editing")
        assertResizeHeight(manualHeight)
        reopenKeyboardSearch(expectedQuery: "No query")
        closeKeyboardSearch()

        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("resizable.landscape", input: input, searching: false,
                                      expectedSurfaceHeight: 220)
        XCTAssertEqual(input.value as? String, context + "🚀")
        settleKeyboardOrientation(.portrait)
        assertResizeHeight(manualHeight)
        assertCompactKeyboardGeometry("resizable.portrait.restored", input: input, searching: false,
                                      expectedSurfaceHeight: CGFloat(manualHeight))
        XCTAssertEqual(input.value as? String, context + "🚀", "Rotation must preserve host input and manual browse height")
    }

    func testSystemKeyboardResponsiveResizeAndCrispQueryPreserveContext() throws {
        try requirePhonePortraitResizeIntegration()
        print("UNIBOARD_RESPONSIVE_FIXTURE version=1.1-row-step centerDepth=7 rowStep=40 minimumTravel=12")
        let context = "The host keeps its original text."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let initialHeight = normalizeKeyboardBrowseHeight(input: input, context: context)

        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        attachResizeFrameDiagnostics(input: input)
        assertResizeHeight(initialHeight)
        assertResizeGripAtTop(input: input)
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        attachScreenshot("Crisp native placeholder and grip at the keyboard top")

        // These are discrete row gestures. Distance and speed do not select
        // arbitrary heights, and no preview/editor is shown while dragging.
        // Original video and numeric telemetry bind the single release apply.
        dragKeyboardGrip(deltaY: -120, velocity: 80, label: "slow.expand", input: input, context: context)
        dragKeyboardGrip(deltaY: 120, velocity: 80, label: "slow.contract", input: input, context: context)
        dragKeyboardGrip(deltaY: -100, velocity: 600, label: "fast.expand", input: input, context: context)
        dragKeyboardGrip(deltaY: 100, velocity: 600, label: "fast.contract", input: input, context: context)
        let manualHeight = measuredKeyboardHeight() ?? 0
        XCTAssertEqual(manualHeight, initialHeight, "Opposite slow/fast row gestures restore the same actual window")

        enterKeyboardQuery("cat")
        assertResizeHeight(max(340, manualHeight))
        attachScreenshot("Crisp native cat query before moving its caret")
        search.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 36, dy: search.frame.height / 2)).tap()
        typeKeyboardQueryKeys("arrow ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(search.waitUntilValueEquals("arrowcat"),
                      "Backspace at the moved caret must preserve the query suffix")
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Crisp native middle caret preserves arrow and cat during editing")
        let unicodeToggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        unicodeToggle.tap()
        XCTAssertTrue(unicodeToggle.waitUntilValueEquals("off"))
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilAbsent())
        assertHostTypingPanel()
        XCTAssertEqual(input.value as? String, context)
        ensureUnicodeToolbarVisible()
        XCTAssertTrue(search.waitUntilValueEquals("arrowcat"))
        search.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: search.frame.height / 2)).tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        typeKeyboardQueryKeys(" ")
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"), "U hides and restores the local query without moving its middle caret")
        XCTAssertEqual(input.value as? String, context)

        let longQuery = "mathematical bold italic capital sigma"
        enterKeyboardQuery(longQuery)
        XCTAssertTrue(search.waitUntilValueEquals(longQuery))
        attachScreenshot("Crisp native long query clips horizontally at the visible caret")
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(search.waitUntilValueEquals(String(longQuery.dropLast())))
        XCTAssertEqual(input.value as? String, context, "Query clipping and local editing must not enter host text")

        enterKeyboardQuery("u+1f680")
        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 10))
        closeKeyboardSearch()
        assertResizeHeight(manualHeight)
        XCTAssertTrue(search.waitUntilValueEquals("u+1f680"))
        openUnicodeBrowse()
        // Done replaces searchContent with the English panel; Browse then
        // mounts a different result tile. Do not reuse the old search element.
        let retainedRocket = app.buttons.matching(identifier: "keyboard.character.U+1F680").firstMatch
        XCTAssertTrue(retainedRocket.waitForExistence(timeout: 5))
        assertKeyboardCharacterIsFullyVisible(retainedRocket, identifier: "keyboard.character.U+1F680")
        XCTAssertTrue(retainedRocket.isHittable, "Explicit Browse must restore the actual filtered result retained by Done")
        XCTAssertEqual(input.value as? String, context)
        assertResizeGripAtTop(input: input)
        attachScreenshot("Responsive keyboard retains folded rocket search and visible host")
        retainedRocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x1F680])

        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("responsive.landscape.folded", input: input, searching: false,
                                      expectedSurfaceHeight: 220)
        XCTAssertEqual(input.value as? String, context + "🚀")
        settleKeyboardOrientation(.portrait)
        assertResizeHeight(manualHeight)
        assertResizeGripAtTop(input: input)
        XCTAssertTrue(search.waitUntilValueEquals("u+1f680"))
        let returnedRocket = app.buttons.matching(identifier: "keyboard.character.U+1F680").firstMatch
        XCTAssertTrue(returnedRocket.waitForExistence(timeout: 5))
        assertKeyboardCharacterIsFullyVisible(returnedRocket, identifier: "keyboard.character.U+1F680")
        XCTAssertTrue(returnedRocket.isHittable)
        XCTAssertEqual(input.value as? String, context + "🚀")
        attachScreenshot("Responsive keyboard restores its manual height and folded query after rotation")
    }

    func testSystemKeyboardLandscapeOptionsAcceptsVisibleCenterTouch() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Landscape menu preserves this document."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        _ = normalizeKeyboardBrowseHeight(input: input, context: context)
        enterKeyboardQuery("u+1f680")
        closeKeyboardSearch()
        openUnicodeBrowse()
        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 5))
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.width > self.app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        let options = app.descendants(matching: .any)["keyboard.options"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        let probe = XCTAttachment(string: "type=\(options.elementType.rawValue) frame=\(options.frame) isHittable=\(options.isHittable)\n\(app.debugDescription)")
        probe.name = "Original landscape options AX projection before the actual centre touch"
        probe.lifetime = .keepAlways
        add(probe)
        attachScreenshot("Original landscape options before actual native menu interaction")
        // Observe real popup opening, actions and dismissal rather than
        // substituting an accessibility hitpoint prediction for the touch.
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+1f680"))
        XCTAssertEqual(input.value as? String, context + "🚀")
        attachScreenshot("Actual landscape options menu closes without changing host or retained query")
    }

    func testSystemKeyboardRowStepsRejectTapsAndClampAtBounds() throws {
        try requirePhonePortraitResizeIntegration()
        let context = "Discrete height steps preserve this host."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let baseline = normalizeKeyboardBrowseHeight(input: input, context: context)
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let originalFrame = grip.frame
        grip.tap()
        assertResizeHeight(baseline)
        XCTAssertEqual(grip.frame.minY, originalFrame.minY, accuracy: 1)
        assertNoHeightSelectionUI()
        XCTAssertEqual(input.value as? String, context)
        dragKeyboardGrip(deltaY: 6, velocity: 80, label: "below-threshold", input: input, context: context)
        dragKeyboardGrip(deltaY: 30, deltaX: 80, velocity: 240, label: "predominantly-horizontal",
                         input: input, context: context)
        assertResizeHeight(baseline)
        XCTAssertTrue(search.waitUntilValueEquals("No query"))

        stepKeyboardHeightToBound(420, input: input, context: context)
        dragKeyboardGrip(deltaY: -120, velocity: 600, label: "upper-bound.no-op", input: input, context: context,
                         feedbackDuringHold: "none")
        assertResizeHeight(420)
        dragKeyboardGrip(deltaY: 90, velocity: 80, label: "upper-bound.one-row-down", input: input, context: context,
                         feedbackDuringHold: "down")
        assertResizeHeight(380)
        stepKeyboardHeightToBound(220, input: input, context: context)
        dragKeyboardGrip(deltaY: 120, velocity: 600, label: "lower-bound.no-op", input: input, context: context,
                         feedbackDuringHold: "none")
        assertResizeHeight(220)
        dragKeyboardGrip(deltaY: -90, velocity: 80, label: "lower-bound.one-row-up", input: input, context: context,
                         feedbackDuringHold: "up")
        assertResizeHeight(260)
        let browseHeight = normalizeKeyboardBrowseHeight(input: input, context: context)

        enterKeyboardQuery("cat")
        assertResizeHeight(340)
        dragKeyboardGrip(deltaY: 90, velocity: 80, label: "query.lower-bound.no-op", input: input, context: context)
        assertResizeHeight(340)
        dragKeyboardGrip(deltaY: -120, velocity: 600, label: "query.one-row-up", input: input, context: context)
        assertResizeHeight(380)
        dragKeyboardGrip(deltaY: 90, velocity: 80, label: "query.one-row-down", input: input, context: context)
        assertResizeHeight(340)
        XCTAssertTrue(search.waitUntilValueEquals("cat"))
        closeKeyboardSearch()
        assertResizeHeight(browseHeight)
        XCTAssertTrue(search.waitUntilValueEquals("cat"))
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("One-row release gestures expose no preview and preserve the retained local query")
    }

    func testSystemKeyboardManualHeightPersistsAcrossHostRelaunchAndRotation() throws {
        try requirePhonePortraitResizeIntegration()
        let firstContext = "Manual keyboard height belongs to the keyboard."
        var input = openSystemKeyboardHost(initialText: firstContext)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let baseline = normalizeKeyboardBrowseHeight(input: input, context: firstContext)
        dragKeyboardGrip(deltaY: -90, velocity: 240, label: "persistence.add-one-row",
                         input: input, context: firstContext)
        let savedHeight = baseline + 40
        assertResizeHeight(savedHeight)
        XCTAssertEqual(measuredKeyboardHeight(), savedHeight)
        enterKeyboardQuery("cat")
        closeKeyboardSearch()
        assertResizeHeight(savedHeight)
        XCTAssertEqual(input.value as? String, firstContext)

        // This is an actual host termination/relaunch. The keyboard's own
        // stepped preference survives the containing app's normal test reset.
        let resumedContext = "A new host session keeps the chosen keyboard height."
        input = openSystemKeyboardHost(initialText: resumedContext)
        assertResizeHeight(savedHeight)
        assertCompactKeyboardGeometry("persistent-height.relaunched", input: input, searching: false,
                                      expectedSurfaceHeight: CGFloat(savedHeight))
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("No query"),
                      "A prior session's query is cleared through the visible action before this case uses search")
        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("persistent-height.landscape", input: input, searching: false,
                                      expectedSurfaceHeight: 220)
        settleKeyboardOrientation(.portrait)
        assertResizeHeight(savedHeight)
        assertCompactKeyboardGeometry("persistent-height.returned", input: input, searching: false,
                                      expectedSurfaceHeight: CGFloat(savedHeight))
        XCTAssertEqual(input.value as? String, resumedContext)

        let restored = normalizeKeyboardBrowseHeight(input: input, context: resumedContext)
        XCTAssertEqual(restored, baseline)
        XCTAssertEqual(input.value as? String, resumedContext)
        attachScreenshot("Visible one-row normalization restores the reachable baseline without changing host text")
    }

    private func dragKeyboardGrip(deltaY: CGFloat, deltaX: CGFloat = 0, velocity: CGFloat, label: String,
                                  input: XCUIElement, context: String, feedbackDuringHold: String? = nil) {
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        guard let surface = measuredKeyboardSurfaceFrame() else {
            XCTFail("Missing actual keyboard surface before the row gesture"); return
        }
        let before = Int(surface.height.rounded())
        let unicodePanel = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        let mode = unicodePanel.exists ? unicodePanel.value as? String : nil
        let lowerBound = mode == "query" || mode == "inspection" ? 340 : 220
        assertNoHeightSelectionUI()
        XCTAssertTrue(grip.isHittable)
        let frame = grip.frame
        XCTAssertTrue(usableHeightFrame(frame))
        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: frame.midX + deltaX - app.frame.minX, dy: frame.midY + deltaY - app.frame.minY))
        let qualifies = abs(deltaY) >= 12 && abs(deltaY) > abs(deltaX)
        let expected = qualifies ? min(420, max(lowerBound, before + (deltaY < 0 ? 40 : -40))) : before
        let expectedFeedback = qualifies && expected != before ? (deltaY < 0 ? "up" : "down") : "none"
        if let feedbackDuringHold {
            XCTAssertEqual(feedbackDuringHold, expectedFeedback,
                           "The bound-feedback fixture must match the actual pregesture height and movement")
        }
        // The public main-actor gesture API is synchronous. A one-second
        // terminal hold makes the active-pan feedback observable in original
        // video; it does not pretend an after-release AX read observed it.
        let holdDuration: TimeInterval = feedbackDuringHold == nil ? 0.2 : 1.0
        let began = Date().timeIntervalSince1970
        print("UNIBOARD_ROW_STEP_BEGIN \(label) epoch=\(began) currentHeight=\(before) deltaX=\(deltaX) deltaY=\(deltaY)")
        start.press(forDuration: 0.15, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: holdDuration)
        let finished = Date().timeIntervalSince1970
        assertCommittedHeight(CGFloat(expected), fixedBottom: surface.maxY, input: input, context: context)
        assertNoHeightSelectionUI()
        let value: [String: Any] = ["gesture": label, "interaction": "release-one-row-no-preview",
            "beganEpoch": began, "finishedEpoch": finished, "deltaX": deltaX, "deltaY": deltaY,
            "velocityPointsPerSecond": velocity, "minimumVerticalTravel": 12, "rowStep": 40,
            "terminalHoldSeconds": holdDuration, "expectedDirectionDuringTerminalHold": expectedFeedback,
            "requiresOriginalVideoFeedbackAssertion": feedbackDuringHold != nil,
            "expectedWindowHeightDuringTerminalHold": before,
            "feedbackProofLimit": "For flagged bound cases, original frames and native feedback samples must show none outward at the bound, and up/down on the fresh inward gesture. This synchronous XCTest only asserts postrelease feedback absence and exact endpoint; it cannot supply the midgesture visual verdict.",
            "actualWindowHeightBefore": before, "expectedHeightAfterRelease": expected,
            "actualWindowHeightAfterRelease": measuredKeyboardHeight() ?? -1,
            "requestedAXHeightAfterRelease": keyboardResizeHeight() ?? -1,
            "fixedBottomBefore": surface.maxY, "expectedAllocationRequestsWhileDragging": 0,
            "expectedReleaseAllocationRequests": before == expected ? 0 : 1,
            "hostUnchanged": (input.value as? String) == context,
            "offlineVideoAndFullTelemetryRequired": true,
            "proofLimit": "Synchronous XCTest cannot inspect the midgesture window. Original recording and native lifecycle timestamps must independently show no preview/editor and no allocation before release; no live resize/FPS/latency claim."]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Native keyboard one-row gesture \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("UNIBOARD_ROW_STEP_END " + String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\n", with: ""))
        attachScreenshot("One-row keyboard gesture \(label) preserves the exact host")
    }

    private func assertNoHeightSelectionUI(file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["keyboard.resize.preview", "keyboard.resize.editor", "keyboard.resize.live"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].firstMatch.exists,
                           "Discrete row gestures must not expose a height preview or editor", file: file, line: line)
        }
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.resize.direction"].firstMatch.exists,
                       "Direction-only feedback must disappear after the gesture ends", file: file, line: line)
    }

    private func assertCommittedHeight(_ expected: CGFloat, fixedBottom: CGFloat,
                                        input: XCUIElement, context: String) {
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard grip.exists, let current = self.keyboardResizeHeight() else { return false }
            return abs(CGFloat(current) - expected) <= 3
                && abs(grip.frame.minY - (fixedBottom - expected)) <= 1
        }, object: grip)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "Release must apply at most one row and settle actual keyboard geometry")
        let actual = keyboardResizeHeight() ?? 0
        XCTAssertTrue((220...420).contains(actual))
        XCTAssertEqual(CGFloat(actual), expected, accuracy: 3)
        XCTAssertEqual(measuredKeyboardHeight(), Int(expected.rounded()))
        XCTAssertEqual(input.value as? String, context, "Height controls must not enter or delete host text")
        assertResizeHeight(actual)
        assertResizeGripAtTop(input: input)
    }

    private func stepKeyboardHeightToBound(_ bound: Int, input: XCUIElement, context: String) {
        guard bound == 220 || bound == 420 else { XCTFail("Only the physical bounds are universally reachable by40-point steps"); return }
        for index in 0..<6 {
            guard let current = measuredKeyboardHeight() else { XCTFail("Missing actual settled height"); return }
            if current == bound { assertResizeHeight(bound); return }
            dragKeyboardGrip(deltaY: bound > current ? -90 : 90, velocity: 240,
                             label: "bound.\(bound).step\(index)", input: input, context: context)
        }
        XCTAssertEqual(measuredKeyboardHeight(), bound, "A bounded sequence of real row gestures must reach the requested bound")
        assertResizeHeight(bound)
    }

    @discardableResult
    private func normalizeKeyboardBrowseHeight(input: XCUIElement, context: String) -> Int {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return 0 }
        ensureUnicodeToolbarVisible()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent())
        // A clamp changes the reachable40-point lattice. Use the full-width
        // four-row band rather than fabricating an arbitrary260-point reset.
        for index in 0..<6 {
            guard let current = measuredKeyboardHeight() else { XCTFail("Missing actual keyboard height"); return 0 }
            if (256..<296).contains(current) {
                if keyboardResizeHeight() != current {
                    // A mode transition can retain an old requested AX value.
                    // Two real opposite steps synchronize it with this actual
                    // surface without changing the resulting browse height.
                    dragKeyboardGrip(deltaY: -90, velocity: 240, label: "baseline.reconcile.up", input: input, context: context)
                    dragKeyboardGrip(deltaY: 90, velocity: 240, label: "baseline.reconcile.down", input: input, context: context)
                }
                assertResizeHeight(current)
                return current
            }
            dragKeyboardGrip(deltaY: current < 256 ? -90 : 90, velocity: 240,
                             label: "baseline.step\(index)", input: input, context: context)
        }
        XCTFail("Real one-row gestures did not reach a four-row browse height")
        return measuredKeyboardHeight() ?? 0
    }

    private func usableHeightFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    private func assertResizeGripAtTop(input: XCUIElement,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let gripFrame = grip.frame
        let surface = measuredKeyboardSurfaceFrame()
        XCTAssertEqual(gripFrame.height, 14, accuracy: 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(gripFrame.width, app.frame.width * 0.9, file: file, line: line)
        XCTAssertNotNil(surface, "Expected the keyboard root containing its native grip", file: file, line: line)
        if let surface {
            XCTAssertEqual(gripFrame.minY, surface.minY, accuracy: 1,
                           "The grip must begin at the keyboard's top without a blank band", file: file, line: line)
            if let height = keyboardResizeHeight() {
                XCTAssertEqual(surface.height, CGFloat(height), accuracy: 1, file: file, line: line)
            }
        }
        assertHostEditorIsVisibleAboveKeyboard(input, file: file, line: line)
    }

    private func measuredKeyboardSurfaceFrame() -> CGRect? {
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let footer = app.buttons["keyboard.return"].firstMatch
        guard toggle.exists, star.exists, footer.exists else { return nil }
        var anchors = [toggle.frame, star.frame, footer.frame]
        let gripFrame = grip.exists ? grip.frame : nil
        if let gripFrame { anchors.append(gripFrame) }
        else {
            let top = [app.descendants(matching: .any)["keyboard.search"].firstMatch,
                       app.buttons["keyboard.typing.key.q"].firstMatch,
                       app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.board.")).firstMatch,
                       app.buttons["Recent"].firstMatch].first { $0.exists && self.usableHeightFrame($0.frame) && self.app.frame.contains($0.frame) }
            guard let top else { return nil }
            anchors.append(top.frame)
        }
        guard anchors.allSatisfy(usableHeightFrame) else { return nil }
        return app.otherElements.containing(.any, identifier: "keyboard.toggleUnicodeToolbar")
            .allElementsBoundByAccessibilityElement.map(\.frame).filter { frame in
                self.usableHeightFrame(frame) && frame.width >= self.app.frame.width * 0.7
                    && (gripFrame == nil || abs(frame.minY - gripFrame!.minY) <= 1)
                    && anchors.allSatisfy { frame.insetBy(dx: -1, dy: -1).contains($0) }
                    && self.app.frame.insetBy(dx: -1, dy: -1).contains(frame)
            }.min(by: { $0.height < $1.height })
    }

    private func measuredKeyboardHeight() -> Int? {
        measuredKeyboardSurfaceFrame().map { Int($0.height.rounded()) }
    }

    private func keyboardResizeHeight() -> Int? {
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        guard grip.exists else { return nil }
        let value = grip.value as? String ?? ""
        return value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    private func attachResizeFrameDiagnostics(input: XCUIElement) {
        func rect(_ frame: CGRect) -> [String: NSObject] {
            let values: [String: CGFloat] = ["x": frame.minX, "y": frame.minY,
                                             "width": frame.width, "height": frame.height]
            return values.mapValues { value -> NSObject in
                value.isFinite ? NSNumber(value: Double(value)) : NSString(string: String(describing: value))
            }
        }
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        let ancestors = app.otherElements.containing(.any, identifier: "keyboard.toggleUnicodeToolbar").allElementsBoundByAccessibilityElement
        let value: [String: Any] = ["app": rect(app.frame), "grip": rect(grip.frame),
            "unicodeToggle": rect(toggle.frame), "hostEditor": rect(input.frame),
            "gripValue": grip.value as? String ?? "Unavailable",
            "keyboardAncestors": ancestors.map { rect($0.frame) }]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Native resize frames before querying hittability"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("UNIBOARD_RESIZE_INITIAL_FRAMES " + String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\n", with: ""))
        attachScreenshot("Native resize grip and complete host before querying hittability")
    }

    private func assertResizeHeight(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        let grip = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.keyboardResizeHeight() == expected
        }, object: grip)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "Resize grip should report \(expected) points, got \(String(describing: grip.value))", file: file, line: line)
    }

    func testSystemKeyboardCompactMenusAndInspectionPreserveContext() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        let input = openSystemKeyboardHost(initialText: context)
        defer { restoreEnglishKeyboard() }
        selectSymbolBoard("migrated-favorites", input: input, context: context)
        normalizeKeyboardBrowseHeight(input: input, context: context)
        enterKeyboardQuery("u+2603")
        let snowman = app.buttons["keyboard.character.U+2603"].firstMatch
        XCTAssertTrue(snowman.waitForExistence(timeout: 10))
        snowman.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+2603", nameContaining: "snowman")
        XCTAssertEqual(input.value as? String, context, "Holding inspects the scalar without inserting it")
        assertCompactKeyboardGeometry("portrait.properties", input: input, searching: false, inspecting: true)
        attachScreenshot("Compact glass Unicode properties keep host context visible without insertion")
        saveInspectedKeyToBoard("migrated-favorites", input: input, context: context)
        app.buttons["keyboard.properties.close"].tap()
        selectKeyboardSection("blocks")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(), "Blocks must exit query mode")
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+2603"))
        let basicLatin = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Basic Latin")).firstMatch
        XCTAssertTrue(basicLatin.waitForExistence(timeout: 5), "The actual block list must replace search results")
        XCTAssertTrue(basicLatin.isHittable)
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Compact section menu opens Blocks while retaining the local query")
        selectKeyboardSection("symbols")
        reopenKeyboardSearch(expectedQuery: "u+2603")
        selectKeyboardSection("saved")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(), "Saved must exit query mode")
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+2603"))
        let savedSnowman = symbolBoardKey("☃")
        XCTAssertTrue(savedSnowman.waitForExistence(timeout: 5), "The saved scalar must appear in actual Saved content")
        savedSnowman.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "☃"))
        attachScreenshot("Compact Saved section inserts the original saved scalar")
        inspectSymbolBoardKey(symbolBoardKey("☃"), optionCount: 1, input: input, context: context + "☃")
        XCTAssertTrue(app.staticTexts["keyboard.properties.name"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+2603")
        XCTAssertEqual(input.value as? String, context + "☃")
        app.buttons["keyboard.properties.favorite"].tap()
        XCTAssertTrue(app.buttons["keyboard.boards.save.cancel"].waitForExistence(timeout: 5))
        app.buttons["keyboard.boards.save.cancel"].tap()
        XCTAssertEqual(input.value as? String, context + "☃")
        app.buttons["keyboard.properties.close"].tap()
        assertKeyboardHasNoEditionSelector()
        selectKeyboardOrder("codepoint")
        assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
        selectKeyboardOrder("newest")
        XCTAssertEqual(input.value as? String, context + "☃", "Menus must not enter text into the host")
        selectKeyboardSection("symbols")
        assertCompactKeyboardGeometry("portrait.menus.closed", input: input, searching: false)
    }

    private func settleKeyboardOrientation(_ orientation: UIDeviceOrientation, toolbarVisible: Bool = true) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return landscape ? frame.width > frame.height : frame.width < frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        let anchor = toolbarVisible ? "keyboard.search" : "keyboard.toggleUnicodeToolbar"
        XCTAssertTrue(app.descendants(matching: .any)[anchor].firstMatch.waitForExistence(timeout: 5))
    }

    private func assertCompactKeyboardGeometry(_ mode: String, input: XCUIElement, searching: Bool,
                                               inspecting: Bool = false, expectedSurfaceHeight: CGFloat? = nil,
                                               file: StaticString = #filePath, line: UInt = #line) {
        func rect(_ frame: CGRect) -> [String: Double] {
            ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        }
        assertHeaderDeleteAtTopRight(file: file, line: line)
        assertKeyboardControlsAreVisible(isSearching: searching, file: file, line: line)
        assertHostEditorIsVisibleAboveKeyboard(input, file: file, line: line)
        let searchElement = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let search = searchElement.exists ? searchElement.frame : .zero
        let footer = app.buttons["keyboard.return"].firstMatch.frame
        let candidates = measuredKeyboardSurfaceFrame().map { [$0] } ?? []
        let landscape = app.frame.width > app.frame.height
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let effectiveExpected = expectedSurfaceHeight ?? (!pad && !landscape ? keyboardResizeHeight().map { CGFloat($0) } : nil)
        let maximum: CGFloat = effectiveExpected ?? (pad ? (searching || inspecting ? 380 : 340)
            : landscape ? 220 : (searching || inspecting ? 340 : 220))
        XCTAssertFalse(candidates.isEmpty, "Expected the actual keyboard surface ancestor", file: file, line: line)
        if let surface = candidates.first {
            XCTAssertLessThanOrEqual(surface.height, maximum + 1, "Keyboard must leave host space instead of reverting to tall chrome", file: file, line: line)
            if let effectiveExpected {
                XCTAssertEqual(surface.height, effectiveExpected, accuracy: 1,
                               "The measured keyboard surface must match its reported resize height", file: file, line: line)
            }
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(surface), "Keyboard surface must not extend above or outside the display", file: file, line: line)
        }
        let resize = app.descendants(matching: .any).matching(identifier: "keyboard.resize").firstMatch
        let resizeValue = resize.exists ? resize.value as? String ?? "Unavailable" : "Unavailable"
        let value: [String: Any] = ["mode": mode, "app": rect(app.frame), "hostEditor": rect(input.frame),
            "hostText": input.value as? String ?? "", "hostIsHittable": input.isHittable,
            "surfaceCandidates": candidates.map(rect), "search": rect(search), "footer": rect(footer),
            "visibleControlSpan": footer.maxY - (candidates.first?.minY ?? footer.minY), "maximumSurfaceHeight": maximum,
            "resizeValue": resizeValue]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Compact native keyboard geometry \(mode)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("UNIBOARD_COMPACT_GEOMETRY " + String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\n", with: ""))
        attachScreenshot("Compact native keyboard \(mode)")
    }

    func testSystemKeyboardUnsupportedGlyphInspectionDoesNotInsert() throws {
        try requireKeyboardIntegration()
        selectAppEdition("latest")
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("u+1faeb")
        let crackingFace = app.buttons["keyboard.character.U+1FAEB"].firstMatch
        XCTAssertTrue(crackingFace.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "")
        crackingFace.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+1FAEB", nameContaining: "cracking face")
        let age = app.descendants(matching: .any)["keyboard.properties.age"].firstMatch
        XCTAssertEqual(accessibleText(age), "Unicode 18.0")
        XCTAssertEqual(input.value as? String, "", "Inspecting an unsupported glyph must never insert a placeholder or scalar")
        attachScreenshot("Real keyboard inspects unsupported cracking-face glyph without insertion")
        app.buttons["keyboard.properties.close"].tap()
        XCTAssertEqual(input.value as? String, "")
        closeKeyboardSearch()
    }

    func testSystemKeyboardUsesAppCatalogChoiceWithoutEditionSelector() throws {
        try requireKeyboardIntegration()
        let context = "App settings choose the offline Unicode catalog."
        defer { restoreEnglishKeyboard() }
        let choices: [(String, [(String, String)])] = [
            ("older", [("10940", "")]),
            ("previous", [("10940", "17.0"), ("0558", "")]),
            ("latest", [("0558", "18.0")]),
            ("draft", [("0558", "18.0")])
        ]
        for (edition, fixtures) in choices {
            selectAppEdition(edition)
            let input = openSystemKeyboardHost(initialText: context)
            // The keyboard has no edition readout or setter. Its actual
            // assigned/unassigned results below prove the app-owned choice.
            assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
            for (codepoint, age) in fixtures {
                enterKeyboardQuery("u+\(codepoint.lowercased())")
                let result = app.buttons["keyboard.character.U+\(codepoint)"].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 10))
                XCTAssertTrue(result.waitUntilLabelHasSuffix(age.isEmpty ? ", Unassigned" : ", U\(age)"))
                XCTAssertEqual(input.value as? String, context, "App edition synchronization must not edit the host")
                closeKeyboardSearch()
                assertKeyboardSettingsMenuOnlyOrderAndOpenApp()
            }
            attachScreenshot("Real keyboard follows app Settings \(edition) without a catalog selector")
        }
        restoreEnglishKeyboard()
        selectAppEdition("latest")
    }

    private func assertKeyboardHasNoEditionSelector() {
        openKeyboardOptions()
        let popup = nativeKeyboardOptionsPopup()
        XCTAssertNotNil(popup, "Require the actual native options menu before checking its available actions")
        for id in ["keyboard.edition", "keyboard.edition.latest", "keyboard.edition.previous",
                   "keyboard.edition.older", "keyboard.edition.draft"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists,
                           "Edition selection belongs only to app Settings")
        }
        closeKeyboardOptions(popup)
    }

    func testSystemKeyboardSearchAndInsertion() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        selectKeyboardOrder("newest")
        assertControlValue("keyboard.order", equals: "newestFirst")
        assertHeaderDeleteAtTopRight()
        assertKeyboardControlsAreVisible(isSearching: false)
        attachScreenshot("Single delete key at the top right of the real keyboard")
        enterKeyboardQuery("u+1f680")
        assertHeaderDeleteAtTopRight()
        assertKeyboardControlsAreVisible(isSearching: true)
        XCTAssertEqual(input.value as? String, "", "Search keys must edit the extension query, not the host document")

        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 10))
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals("🚀"), "A supplementary Unicode character should reach the host TextEditor")
        attachScreenshot("System keyboard search and Unicode insertion")

        closeKeyboardSearch()
        XCTAssertEqual(input.value as? String, "🚀", "Closing search must preserve the host document")

        // Reopening after a tab switch must rerun the unchanged query against
        // the active catalog type, rather than reusing stale scalar results.
        selectKeyboardSection("emojis")
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        XCTAssertTrue(app.buttons["keyboard.emoji.1F680"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "🚀", "Changing the result kind must not insert text")
        closeKeyboardSearch()
        selectKeyboardSection("symbols")
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        XCTAssertTrue(app.buttons["keyboard.character.U+1F680"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "🚀")
        closeKeyboardSearch()
        app.buttons["keyboard.space"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("🚀 "))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("🚀"))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(""), "Delete must remove a supplementary character as a complete character")

        // A compact keyboard must retain the same usable controls and insert
        // into the same native text document after rotation.
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return frame.width > frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        assertHeaderDeleteAtTopRight()
        assertKeyboardControlsAreVisible(isSearching: false)
        attachScreenshot("Compact landscape keyboard keeps native controls visible")
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        assertHeaderDeleteAtTopRight()
        assertKeyboardControlsAreVisible(isSearching: true)
        assertHostEditorIsVisibleAboveKeyboard(input)
        XCTAssertEqual(input.value as? String, "")
        let landscapeRocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(landscapeRocket.waitForExistence(timeout: 10))
        XCTAssertTrue(landscapeRocket.isHittable)
        landscapeRocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals("🚀"))
        attachScreenshot("Compact landscape search preserves Unicode host insertion")
        closeKeyboardSearch()
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(""))
    }

    func testSystemKeyboardLongPressShowsPropertiesWithoutInsertion() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("u+2603")
        let snowman = app.buttons["keyboard.character.U+2603"].firstMatch
        XCTAssertTrue(snowman.waitForExistence(timeout: 10))
        snowman.press(forDuration: 1)

        assertKeyboardProperties(codepoints: "U+2603", nameContaining: "snowman")
        XCTAssertEqual(input.value as? String, "", "Holding a character must inspect it without inserting it")
        attachScreenshot("Long press exposes character properties without insertion")
        app.buttons["keyboard.properties.close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.properties"].firstMatch.waitUntilAbsent())
        XCTAssertEqual(input.value as? String, "", "Closing properties must not trigger the character tap action")
        snowman.tap()
        XCTAssertTrue(input.waitUntilValueEquals("☃"), "A separate plain tap should still insert the original scalar")
        closeKeyboardSearch()
    }

    func testSystemKeyboardInsertsWholeZWJEmojiAndVariationSelectorWithoutLeakingQuery() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        selectKeyboardSection("emojis")
        enterKeyboardQuery("head shaking horizontally")
        XCTAssertEqual(input.value as? String, "", "Emoji search must remain inside the extension")

        let emoji = app.buttons["keyboard.emoji.1F642-200D-2194-FE0F"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        emoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals("🙂‍↔️"), "The host must receive the full head-shaking ZWJ sequence and its variation selector")
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map { $0.value }, [0x1F642, 0x200D, 0x2194, 0xFE0F])
        attachScreenshot("Whole emoji ZWJ sequence inserted into host")
        closeKeyboardSearch()
        app.buttons["keyboard.space"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("🙂‍↔️ "))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("🙂‍↔️"))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(""), "Delete must remove the complete emoji grapheme")
    }


    private func selectKeyboardSection(_ section: String) {
        openUnicodeBrowse()
        let menu = app.descendants(matching: .any)["keyboard.section"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The keyboard section trigger must return after a prior menu closes")
        if menu.value as? String == section { return }
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let option = app.descendants(matching: .any)["keyboard.tab.\(section)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        assertControlValue("keyboard.section", equals: section)
    }

    private func openKeyboardOptions() {
        let option = app.descendants(matching: .any)["keyboard.order"].firstMatch
        if option.exists { return }
        ensureUnicodeToolbarVisible()
        let menu = app.descendants(matching: .any)["keyboard.options"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The keyboard options trigger must return before opening another menu")
        let input = app.textViews["keyboardTestInput"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let frame = menu.frame
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame), "The real options trigger must be on screen")
        guard let hostText = input.value as? String,
              let queryValue = search.value as? String,
              let optionsValue = menu.value as? String else {
            XCTFail("The options dismissal precondition must preserve readable host, query and options values")
            return
        }
        keyboardOptionsSnapshot = KeyboardOptionsSnapshot(triggerFrame: frame, hostText: hostText,
                                                          queryValue: queryValue, optionsValue: optionsValue)
        // iPad's observed accessibility tap point was near the rounded cap's
        // corner. Target its centre explicitly while keeping real menu checks.
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The actual options menu must open")
    }

    private func closeKeyboardOptions(_ nativePopup: XCUIElement? = nil) {
        defer { keyboardOptionsSnapshot = nil }
        let option = app.descendants(matching: .any)["keyboard.order"].firstMatch
        if nativePopup?.exists == true || option.exists {
            // A host-app tap does not reliably dismiss a remote keyboard
            // popup. Use the actual source-button frame observed before it
            // opened; the native menu consumes this tap without an action.
            guard let snapshot = keyboardOptionsSnapshot else {
                XCTFail("A native menu dismissal requires its observed keyboard source-button frame")
                return
            }
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: snapshot.triggerFrame.midX - app.frame.minX,
                         dy: snapshot.triggerFrame.midY - app.frame.minY)).tap()
        }
        if let nativePopup {
            XCTAssertTrue(nativePopup.waitUntilAbsent(), "The actual native popup must close after its items scroll offscreen")
        }
        XCTAssertTrue(option.waitUntilAbsent(), "The actual native options popup must close")
        let menu = app.descendants(matching: .any)["keyboard.options"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        if let snapshot = keyboardOptionsSnapshot {
            XCTAssertTrue(app.textViews["keyboardTestInput"].firstMatch.waitUntilValueEquals(snapshot.hostText))
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals(snapshot.queryValue))
            XCTAssertTrue(menu.waitUntilValueEquals(snapshot.optionsValue), "Dismissing must not select a menu action")
        }
    }

    private func assertValueRemainsAfterRelease(_ element: XCUIElement, equals expected: String,
                                               file: StaticString = #filePath, line: UInt = #line) {
        let changedAfterRelease = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !element.exists || element.value as? String != expected
        }, object: element)
        changedAfterRelease.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedAfterRelease], timeout: 0.6), .completed,
                       "A released delete press must not keep editing", file: file, line: line)
        XCTAssertEqual(element.value as? String, expected, file: file, line: line)
    }

    private func keyboardOption(_ identifier: String) -> XCUIElement {
        openKeyboardOptions()
        let item = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Expected keyboard option \(identifier): \(app.debugDescription)")
        return item
    }

    private func selectKeyboardOrder(_ order: String) {
        keyboardOption("keyboard.order").tap()
        let option = app.descendants(matching: .any)["keyboard.order.\(order)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let value = ["newest": "newestFirst", "oldest": "oldestFirst", "codepoint": "codePoint"][order]!
        assertControlValue("keyboard.order", equals: value)
    }

    private func appTab(_ title: String) -> XCUIElement {
        // iPhone retains the classic TabBar. iPadOS 27 exposes each floating
        // tab as a _UIFloatingTabBarItemCell with the same exact visible label.
        let legacy = app.tabBars.buttons[title].firstMatch
        if legacy.exists { return legacy }
        let floating = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if floating.exists { return floating }
        return app.buttons[title].firstMatch
    }

    private func appUnicodeFontsSwitch() -> XCUIElement {
        openAppSettings()
        let fonts = app.switches["extraUnicodeFonts"].firstMatch
        revealByScrolling(fonts, in: app)
        return fonts
    }

    private func setAppUnicodeFonts(_ enabled: Bool) {
        let fonts = appUnicodeFontsSwitch()
        let value = enabled ? "1" : "0"
        if fonts.value as? String != value { fonts.tap() }
        XCTAssertTrue(fonts.waitUntilValueEquals(value))
    }

    private func setAppCollapseKey(_ enabled: Bool) {
        openAppSettings()
        let collapse = app.switches["showKeyboardCollapseKey"].firstMatch
        revealByScrolling(collapse, in: app)
        let value = enabled ? "1" : "0"
        if collapse.value as? String != value { collapse.tap() }
        XCTAssertTrue(collapse.waitUntilValueEquals(value))
    }

    private func nativeKeyboardOptionsPopup() -> XCUIElement? {
        // Preserve the actual AX element after Order scrolls out of view.
        app.collectionViews.allElementsBoundByAccessibilityElement.first(where: {
            $0.descendants(matching: .any)["keyboard.order"].firstMatch.exists
        })
    }

    private func revealNativeKeyboardOption(_ control: XCUIElement, in popup: XCUIElement) -> Bool {
        func usable(_ frame: CGRect) -> Bool {
            frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite
                && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
        }
        func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 0.5 && abs(a.minY - b.minY) <= 0.5
                && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
        }
        func settledAndVisible() -> Bool {
            var previous: (CGRect, CGRect, CGRect)?
            var stableSince: TimeInterval?
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard popup.exists, control.exists else { previous = nil; stableSince = nil; return false }
                let appFrame = self.app.frame
                let popupFrame = popup.frame
                let frame = control.frame
                let viewport = popupFrame.intersection(appFrame)
                guard usable(appFrame), usable(popupFrame), usable(viewport), usable(frame),
                      popupFrame.insetBy(dx: -1, dy: -1).contains(frame),
                      appFrame.insetBy(dx: -1, dy: -1).contains(frame),
                      viewport.insetBy(dx: -1, dy: -1).contains(frame) else {
                    previous = nil; stableSince = nil; return false
                }
                let now = ProcessInfo.processInfo.systemUptime
                let same = previous.map { nearlyEqual($0.0, frame) && nearlyEqual($0.1, popupFrame)
                    && nearlyEqual($0.2, appFrame) } ?? false
                if !same { stableSince = now }
                previous = (frame, popupFrame, appFrame)
                // Do not accept a transient frame during native-menu momentum.
                return now - (stableSince ?? now) >= 0.3 && control.isHittable
            }, object: control)
            return XCTWaiter.wait(for: [visible], timeout: 3) == .completed
        }

        // Four bounded gestures, with a final settled visibility check.
        for attempt in 0...4 {
            if settledAndVisible() { return true }
            guard popup.exists else { return false }
            let appFrame = app.frame
            let popupFrame = popup.frame
            let viewport = popupFrame.intersection(appFrame)
            guard usable(appFrame), usable(popupFrame), usable(viewport) else { return false }
            let frame = control.exists ? control.frame : .null
            print("UNIBOARD_NATIVE_MENU_REVEAL attempt=\(attempt) popup=\(popupFrame) app=\(appFrame) visible=\(viewport) control=\(frame)")
            guard attempt < 4 else { return false }
            var downward = false
            var distance = viewport.height * 0.3
            if usable(frame) {
                guard frame.height <= viewport.height + 2 else { return false }
                if frame.minY < viewport.minY {
                    downward = true
                    distance = min(distance, max(24, viewport.minY - frame.minY + 6))
                } else if frame.maxY > viewport.maxY {
                    distance = min(distance, max(24, frame.maxY - viewport.maxY + 6))
                } else {
                    // A contained but masked/unstable control needs another
                    // bounded observation, not a speculative scroll.
                    continue
                }
            }
            // Native scroll recognition consumes the first ~10 points. A
            // tiny clipping correction must still cross that threshold; 24pt
            // remains capped by the original 30%-viewport maximum.
            let startY = viewport.minY + viewport.height * (downward ? 0.35 : 0.65)
            let endY = startY + (downward ? distance : -distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX,
                                                  dy: startY - appFrame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX,
                                                dy: endY - appFrame.minY))
            // Slow motion plus a terminal hold suppresses a fling past a
            // multiline row. Both points stay in popup intersect display.
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return false
    }

    private func assertKeyboardSettingsMenuOnlyOrderAndOpenApp(file: StaticString = #filePath, line: UInt = #line) {
        openKeyboardOptions()
        guard let popup = nativeKeyboardOptionsPopup() else {
            XCTFail("Expected the native options popup collection", file: file, line: line)
            return
        }
        defer { closeKeyboardOptions(popup) }
        for identifier in ["keyboard.edition", "keyboard.unicodeFonts", "keyboard.showCollapseKey", "keyboard.inspectLast", "keyboard.saveLast"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].firstMatch.exists,
                           "Keyboard options contain only ordering and opening the companion app", file: file, line: line)
        }
        XCTAssertFalse(app.buttons["Save to symbol board"].firstMatch.exists)
        let controls = [app.descendants(matching: .any)["keyboard.order"].firstMatch,
                        app.descendants(matching: .any)["keyboard.openCompanionApp"].firstMatch]
        for control in controls {
            XCTAssertTrue(revealNativeKeyboardOption(control, in: popup),
                          "Order and Open companion app must each settle fully on screen and be hittable", file: file, line: line)
            let frame = control.frame
            XCTAssertTrue(popup.frame.insetBy(dx: -1, dy: -1).contains(frame),
                          "Each native menu action must be fully revealed in its actual scroll viewport", file: file, line: line)
            XCTAssertTrue(control.isHittable, file: file, line: line)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame),
                          "A keyboard setting must not be clipped: \(frame)", file: file, line: line)
        }
    }

    private func requirePhonePortraitResizeIntegration() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                      "Manual portrait resizing is a phone feature; iPad uses its adaptive layout.")
    }

    private func requireKeyboardIntegration() throws {
        let enabled = ProcessInfo.processInfo.environment["UNIBOARD_KEYBOARD_INTEGRATION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--keyboard-integration")
        try XCTSkipUnless(enabled, "Set UNIBOARD_KEYBOARD_INTEGRATION=1 in the UI test runner to exercise the installed system keyboard.")
    }

    private func openSystemKeyboardHost(initialText: String = "", unicodeBrowse: Bool = true) -> XCUIElement {
        enableUniboardInSettings()
        // Reload UIKit's enabled-keyboard configuration after changing it in
        // Settings, and start from a settled foreground navigation state.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let settings = appTab("Settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let settingsPage = app.navigationBars["Settings"].firstMatch
        for _ in 0..<3 {
            settings.tap()
            if settingsPage.waitForExistence(timeout: 2) { break }
        }
        // iPad's sidebar button opens the page without reporting a selected
        // trait. Verify the destination itself before opening its host editor.
        XCTAssertTrue(settingsPage.exists, "Settings must be open before opening the keyboard host: \(app.debugDescription)")
        let tryKeyboard = app.descendants(matching: .any)["tryKeyboard"].firstMatch
        revealByScrolling(tryKeyboard, in: app)
        tryKeyboard.tap()
        let input = app.textViews["keyboardTestInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        if !initialText.isEmpty {
            // Seed through the actual English keyboard before selecting the
            // extension. Avoid repeated remote keyboard scene handoffs merely
            // to prepare context for geometry and insertion assertions.
            restoreEnglishKeyboard()
            input.tap()
            input.typeText(initialText)
            XCTAssertTrue(input.waitUntilValueEquals(initialText))
        }
        selectUniboardKeyboard(input: input, expectedHost: initialText)
        XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.waitForExistence(timeout: 10),
            "Expected the real Uniboard keyboard extension: \(app.debugDescription)")
        XCTAssertEqual(input.value as? String, initialText)
        if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
        if unicodeBrowse {
            openUnicodeBrowse()
            selectKeyboardSection("symbols")
        } else {
            // This path proves the actual default instead of silently
            // navigating away from a Unicode panel left by another case.
            assertHostTypingPanel()
            XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals("off"), "The daily English keyboard starts without the Unicode toolbar")
            let hiddenQueryMatches = app.descendants(matching: .any).matching(identifier: "keyboard.search")
            if hiddenQueryMatches.firstMatch.exists {
                // Preserve the unexpected live AX objects before teardown.
                // A zero/offscreen frame must never be queried for a hit point.
                let description = app.debugDescription
                print("UNIBOARD_UNEXPECTED_HIDDEN_QUERY_AX " + description)
                let hierarchy = XCTAttachment(string: description)
                hierarchy.name = "Unexpected hidden query accessibility hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                let matches: [[String: Any]] = hiddenQueryMatches.allElementsBoundByAccessibilityElement.map { element in
                    let frame = element.frame
                    return ["elementType": element.elementType.rawValue, "frame": String(describing: frame),
                            "enabled": element.isEnabled, "label": element.label, "value": element.value as? String ?? ""]
                }
                let data = try! JSONSerialization.data(withJSONObject: matches, options: [.prettyPrinted, .sortedKeys])
                print("UNIBOARD_UNEXPECTED_HIDDEN_QUERY_MATCHES " + String(data: data, encoding: .utf8)!)
                let matchDetails = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                matchDetails.name = "Unexpected hidden query exact identifier matches"
                matchDetails.lifetime = .keepAlways
                add(matchDetails)
            }
            XCTAssertFalse(hiddenQueryMatches.firstMatch.exists)
            XCTAssertFalse(app.buttons["keyboard.options"].firstMatch.exists)
            XCTAssertFalse(app.buttons["keyboard.collapse"].firstMatch.exists, "The collapse key is disabled by default")
            attachScreenshot("Default compact English keyboard keeps the Unicode toolbar hidden")
        }
        // Inspect/clear retained data through the real U control, then restore
        // the default hidden toolbar for callers testing ordinary English.
        ensureUnicodeToolbarVisible()
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        if let retainedQuery = search.value as? String, retainedQuery != "No query", !retainedQuery.isEmpty {
            let clear = app.buttons["keyboard.search.clear"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            clear.tap()
            XCTAssertTrue(search.waitUntilValueEquals("No query"))
            XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(),
                          "Visible query cleanup must not activate local query keys")
            XCTAssertEqual(input.value as? String, initialText,
                           "Visible query cleanup must not alter the seeded host document")
        }
        if !unicodeBrowse {
            app.buttons["keyboard.toggleUnicodeToolbar"].tap()
            XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals("off"))
            assertHostTypingPanel()
        }
        return input
    }

    private func enterKeyboardQuery(_ query: String) {
        ensureUnicodeToolbarVisible()
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        attachScreenshot("System keyboard before search")
        search.tap()
        let firstQueryKey = app.buttons["keyboard.query.u"].firstMatch
        let didOpenSearch = firstQueryKey.waitForExistence(timeout: 5)
        attachScreenshot("System keyboard after opening search")
        XCTAssertTrue(didOpenSearch, "Search should show extension query keys: \(app.debugDescription)")
        if let oldQuery = search.value as? String, oldQuery != "No query" {
            // The query now has a movable caret. Clear through the visible
            // action instead of assuming backward deletion starts at its end.
            let clear = app.buttons["keyboard.search.clear"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            clear.tap()
            XCTAssertTrue(search.waitUntilValueEquals("No query"))
        }
        typeKeyboardQueryKeys(query)
        XCTAssertTrue(search.waitUntilValueEquals(query), "The visible keyboard search query should match its keys")
    }

    private func typeKeyboardQueryKeys(_ text: String) {
        for key in text {
            let id = key == " " ? "keyboard.space" : "keyboard.query.\(key)"
            let queryKey = app.buttons[id].firstMatch
            XCTAssertTrue(queryKey.waitForExistence(timeout: 5), "Expected query key \(key): \(app.debugDescription)")
            queryKey.tap()
        }
    }

    private func reopenKeyboardSearch(expectedQuery: String) {
        ensureUnicodeToolbarVisible()
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitUntilValueEquals(expectedQuery), "Reopening must preserve the existing query")
    }

    private func closeKeyboardSearch() {
        let input = app.textViews["keyboardTestInput"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let hostText = input.value as? String
        let query = search.value as? String
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"))
        app.buttons["keyboard.return"].tap()
        assertHostTypingPanel()
        XCTAssertTrue(input.waitUntilValueEquals(hostText ?? ""), "Done returns English typing without editing the host")
        XCTAssertTrue(search.waitUntilValueEquals(query ?? "No query"), "Done retains the exact local query")
    }

    private func assertHostTypingPanel(file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), file: file, line: line)
        if toggle.value as? String == "on" {
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.openUnicode"].firstMatch.waitUntilValueEquals("typing"),
                          "Expected the real English typing panel", file: file, line: line)
        }
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(), file: file, line: line)
        let hostKey = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.typing.key.")).firstMatch
        XCTAssertTrue(hostKey.waitForExistence(timeout: 5), "English mode must expose actual host typing keys", file: file, line: line)
        XCTAssertTrue(hostKey.isHittable, file: file, line: line)
    }

    private func openUnicodeBrowse() {
        ensureUnicodeToolbarVisible()
        let browse = app.descendants(matching: .any)["keyboard.openUnicode"].firstMatch
        if browse.exists {
            let input = app.textViews["keyboardTestInput"].firstMatch
            let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
            let host = input.value as? String
            let query = search.value as? String
            XCTAssertTrue(browse.waitUntilValueEquals("typing"))
            browse.tap()
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("unicode"))
            XCTAssertTrue(input.waitUntilValueEquals(host ?? ""), "Opening Browse must preserve host text")
            XCTAssertTrue(search.waitUntilValueEquals(query ?? "No query"), "Opening Browse must retain the local query")
        } else {
            let typing = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
            XCTAssertTrue(typing.waitForExistence(timeout: 5), "Expected the real Unicode/query/inspection panel")
            XCTAssertTrue(["unicode", "query", "inspection"].contains(typing.value as? String ?? ""))
        }
    }

    private func ensureUnicodeToolbarVisible() {
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String == "off" { toggle.tap() }
        XCTAssertTrue(toggle.waitUntilValueEquals("on"))
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5))
    }

    private func restoreEnglishKeyboard() {
        let propertiesClose = app.buttons["keyboard.properties.close"].firstMatch
        if propertiesClose.exists { propertiesClose.tap() }
        if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
        let typing = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        if typing.exists { typing.tap(); assertHostTypingPanel() }
        // Leave a real, ordinary letters panel for the next keyboard session.
        let letters = app.buttons["keyboard.typing.letters"].firstMatch
        if letters.exists { letters.tap() }
        let extensionGlobe = app.buttons["keyboard.globe"].firstMatch
        let globe = extensionGlobe.exists ? extensionGlobe : app.buttons["Next keyboard"].firstMatch
        if globe.exists {
            globe.press(forDuration: 1)
            let english = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "English")).firstMatch
            if english.waitForExistence(timeout: 3) { english.tap() }
        }
    }

    private func assertKeyboardCharacterIsFullyVisible(_ character: XCUIElement, identifier: String,
                                                        file: StaticString = #filePath, line: UInt = #line) {
        let grid = app.scrollViews.containing(.button, identifier: identifier).firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5), file: file, line: line)
        let frame = character.frame
        let viewport = grid.frame.intersection(app.frame)
        XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
                      && frame.width > 0 && frame.height > 0, file: file, line: line)
        XCTAssertTrue(viewport.width.isFinite && viewport.height.isFinite && viewport.width > 0 && viewport.height > 0,
                      file: file, line: line)
        XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame),
                      "The current panel's character must be fully within its real scroll viewport", file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame), file: file, line: line)
    }

    private func assertLowerDeleteInKeyRow(_ identifier: String, beside referenceID: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let controls = app.buttons.matching(identifier: identifier)
        XCTAssertEqual(controls.count, 1, "Expected one lower delete for the active key panel", file: file, line: line)
        let lower = controls.firstMatch
        let reference = app.buttons[referenceID].firstMatch
        XCTAssertTrue(lower.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(reference.waitForExistence(timeout: 5), file: file, line: line)
        let frame = lower.frame
        XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite,
                      file: file, line: line)
        XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame), file: file, line: line)
        XCTAssertEqual(frame.midY, reference.frame.midY, accuracy: 1,
                       "The lower delete belongs to the existing final key row", file: file, line: line)
        XCTAssertGreaterThan(frame.midX, reference.frame.midX, file: file, line: line)
        XCTAssertGreaterThan(frame.minY, app.buttons["keyboard.delete"].firstMatch.frame.maxY,
                             "The lower control is separate from the retained header delete", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, app.buttons["keyboard.space"].firstMatch.frame.minY,
                                 "The lower delete must fit above the existing footer without adding a row", file: file, line: line)
        XCTAssertTrue(lower.isHittable, file: file, line: line)
    }

    private func assertHeaderDeleteAtTopRight(file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.value as? String == "off" {
            XCTAssertFalse(app.buttons["keyboard.delete"].firstMatch.exists, "A hidden Unicode toolbar does not expose header controls", file: file, line: line)
            return
        }
        let deletes = app.buttons.matching(identifier: "keyboard.delete")
        XCTAssertEqual(deletes.count, 1, "There must be exactly one header delete control", file: file, line: line)
        let delete = deletes.firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(delete.isHittable, file: file, line: line)
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let space = app.buttons["keyboard.space"].firstMatch
        XCTAssertLessThanOrEqual(abs(delete.frame.midY - search.frame.midY), 18,
            "Delete should align with the top search header", file: file, line: line)
        XCTAssertGreaterThan(delete.frame.midX, app.frame.minX + app.frame.width * 0.8,
            "Delete should be on the right edge of the keyboard", file: file, line: line)
        XCTAssertGreaterThan(delete.frame.midX, search.frame.midX, file: file, line: line)
        XCTAssertLessThan(delete.frame.maxY, space.frame.minY,
            "Delete must be above the character and bottom-control areas", file: file, line: line)
    }

    private func assertKeyboardControlsAreVisible(isSearching: Bool,
                                                  file: StaticString = #filePath, line: UInt = #line) {
        let toolbarOn = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.value as? String == "on"
        var identifiers = ["keyboard.toggleUnicodeToolbar", "keyboard.openFavorites", "keyboard.space", "keyboard.return"]
        if toolbarOn { identifiers += ["keyboard.search", "keyboard.delete", "keyboard.options"] }
        if isSearching {
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"), file: file, line: line)
            identifiers += ["keyboard.openTyping", "keyboard.section", "keyboard.query.q", "keyboard.query.p", "keyboard.query.u"]
        } else if app.buttons["keyboard.typing.key.q"].firstMatch.exists {
            assertHostTypingPanel(file: file, line: line)
            identifiers += ["keyboard.typing.key.q", "keyboard.typing.key.p", "keyboard.typing.shift"]
            if toolbarOn { identifiers += ["keyboard.openUnicode"] }
        } else if toolbarOn {
            identifiers += ["keyboard.openTyping", "keyboard.section"]
        }
        let screen = app.frame.insetBy(dx: -1, dy: -1)
        let verifyOptionsByTouch = toolbarOn
        for identifier in identifiers {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Expected keyboard control \(identifier)", file: file, line: line)
            if identifier != "keyboard.options" || !verifyOptionsByTouch {
                XCTAssertTrue(control.isHittable, "Keyboard control \(identifier) must remain tappable", file: file, line: line)
            }
            let frame = control.frame
            XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0,
                          "Keyboard control \(identifier) must have a finite visible frame", file: file, line: line)
            XCTAssertTrue(screen.contains(frame), "Keyboard control \(identifier) is clipped outside the screen: \(frame)", file: file, line: line)
        }
        if verifyOptionsByTouch {
            // Remote menus can report isHittable=false after rotation or a
            // host relaunch. Require the physical centre touch to open the
            // actual popup, then verify its items and dismissal.
            assertKeyboardSettingsMenuOnlyOrderAndOpenApp(file: file, line: line)
        }
    }

    private func assertHostEditorIsVisibleAboveKeyboard(_ input: XCUIElement,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        let frame = input.frame
        XCTAssertTrue(input.isHittable, "The native host editor must remain tappable", file: file, line: line)
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height >= 44,
                      "The host needs a visible editing area, not a collapsed frame: \(frame)", file: file, line: line)
        XCTAssertTrue(app.frame.contains(frame), "The host editor must remain inside the display", file: file, line: line)
        guard let surface = measuredKeyboardSurfaceFrame() else { XCTFail("Expected an actual visible keyboard root", file: file, line: line); return }
        XCTAssertLessThanOrEqual(frame.maxY, surface.minY,
                                 "The native keyboard must leave the entire editor visible above its actual root", file: file, line: line)
    }

    private func assertKeyboardProperties(codepoints: String, nameContaining name: String) {
        let panel = app.descendants(matching: .any)["keyboard.properties"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        for property in ["name", "description", "codepoints", "age", "utf8", "block", "category", "script", "bidi", "combiningClass", "decomposition"] {
            let element = app.descendants(matching: .any)["keyboard.properties.\(property)"].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected full character property \(property)")
            XCTAssertFalse(accessibleText(element).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let propertyName = app.descendants(matching: .any)["keyboard.properties.name"].firstMatch
        XCTAssertTrue(accessibleText(propertyName).localizedCaseInsensitiveContains(name))
        let points = app.descendants(matching: .any)["keyboard.properties.codepoints"].firstMatch
        XCTAssertEqual(accessibleText(points), codepoints)
        let description = app.descendants(matching: .any)["keyboard.properties.description"].firstMatch
        XCTAssertFalse(accessibleText(description).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Properties should retain descriptive metadata even when a glyph cannot render")
        attachScreenshot("Keyboard inspector name and properties without insertion")
        let lastProperty = app.staticTexts["keyboard.properties.decomposition"].firstMatch
        let propertyScroll = app.scrollViews.containing(.staticText, identifier: "keyboard.properties.description").firstMatch
        XCTAssertTrue(propertyScroll.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if isInsideScrollViewport(lastProperty, in: propertyScroll) { break }
            propertyScroll.swipeUp()
        }
        XCTAssertTrue(isInsideScrollViewport(lastProperty, in: propertyScroll), "The full properties must remain reachable inside the keyboard's scroll area")
        attachScreenshot("Complete Unicode properties remain reachable in the keyboard")
        func readableProperty(_ element: XCUIElement) -> Bool {
            guard element.exists, propertyScroll.exists else { return false }
            let frame = element.frame
            let viewport = propertyScroll.frame.intersection(app.frame)
            let valid: (CGRect) -> Bool = { rect in
                rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite
                    && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
            }
            guard valid(frame), valid(viewport), viewport.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
            return isInsideScrollViewport(element, in: propertyScroll)
                && isReadableInScrollViewport(element, in: propertyScroll)
        }
        for _ in 0..<6 {
            if readableProperty(propertyName) { break }
            propertyScroll.swipeDown()
        }
        XCTAssertTrue(readableProperty(propertyName), "The inspector must return to its readable name after scrolling through all properties")
        // The compact landscape pane is 84pt tall. The glyph/name header and
        // Preview font row put Code point below it; reveal each separately.
        for _ in 0..<6 {
            if readableProperty(points) { break }
            guard points.exists, propertyScroll.exists else { break }
            let frame = points.frame
            let appFrame = app.frame
            let viewport = propertyScroll.frame.intersection(appFrame)
            guard frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite,
                  frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0,
                  viewport.minX.isFinite && viewport.minY.isFinite && viewport.maxX.isFinite && viewport.maxY.isFinite,
                  viewport.width.isFinite && viewport.height.isFinite && viewport.width > 0 && viewport.height > 0 else { break }
            let downward = frame.minY < viewport.minY
            print("UNIBOARD_PROPERTY_REVEAL codepoints=\(frame) viewport=\(viewport)")
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX,
                dy: viewport.minY + viewport.height * (downward ? 0.25 : 0.75) - appFrame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX,
                dy: viewport.minY + viewport.height * (downward ? 0.75 : 0.25) - appFrame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(readableProperty(points), "The exact code point must be separately reachable and readable in the native inspector")
        attachScreenshot("Exact code point remains readable in the native inspector")
    }

    private func isInsideScrollViewport(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        guard element.exists && scrollView.exists else { return false }
        let frame = element.frame
        let viewport = scrollView.frame
        guard frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite,
              frame.width > 0 && frame.height > 0,
              viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        // iOS 27 can throw an AX activation-point error for an offscreen
        // property. Establish viewport containment before asking hittability.
        return element.isHittable
    }

    private func isReadableInScrollViewport(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        guard element.exists && scrollView.exists else { return false }
        let frame = element.frame
        let viewport = scrollView.frame
        guard frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0,
              viewport.width > 0 && viewport.height > 0 else { return false }
        let visible = frame.intersection(viewport)
        guard !visible.isNull, visible.height >= min(frame.height, viewport.height) * 0.9 else { return false }
        return element.isHittable
    }

    private func openAppSettings() {
        if app.navigationBars["Try Uniboard"].exists {
            restoreEnglishKeyboard()
            let back = app.navigationBars["Try Uniboard"].buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        dismissAppSearchKeyboard()
        let settings = appTab("Settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    private func selectAppEdition(_ edition: String) {
        openAppSettings()
        let selector = app.descendants(matching: .any)["unicodeEdition"].firstMatch
        let settingsScroll = app.scrollViews.containing(.any, identifier: "unicodeEdition").firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if selector.isHittable && settingsScroll.frame.intersection(app.frame).contains(selector.frame) { break }
            // This first Settings section can be above the retained position
            // after reading font licenses; only scroll its actual container.
            settingsScroll.swipeDown()
        }
        XCTAssertTrue(settingsScroll.frame.intersection(app.frame).contains(selector.frame))
        XCTAssertTrue(selector.isHittable)
        selector.tap()
        let versions = ["latest": "18", "previous": "17", "older": "16", "draft": "19"]
        let option = app.descendants(matching: .any)["edition.\(edition)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected Settings catalog edition option \(edition)")
        if let number = versions[edition] {
            XCTAssertTrue(option.label.contains(number), "Each catalog choice must display its actual Unicode version")
        }
        attachScreenshot("Settings is the only catalog selector and offers four bundled versions")
        option.tap()
        assertControlValue("unicodeEdition", equals: edition)
        appTab("Explore").tap()
        XCTAssertFalse(app.descendants(matching: .any)["unicodeEdition"].firstMatch.exists)
    }

    private func assertCharacterProperty(_ property: String, equals expected: String) {
        let element = app.descendants(matching: .any)["characterProperties.\(property)"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(element), expected)
    }

    private func assertCharacterProperty(_ property: String, contains expected: String) {
        let element = app.descendants(matching: .any)["characterProperties.\(property)"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(element).localizedCaseInsensitiveContains(expected))
    }

    private func dismissAppSearchKeyboard() {
        let done = app.buttons["Done"].firstMatch
        if done.exists && done.isHittable { done.tap() }
    }

    private func assertControlValue(_ identifier: String, equals expected: String) {
        if identifier == "keyboard.order" {
            // Selection dismisses the submenu before the toolbar reappears.
            // The options trigger now exposes only its current ordering.
            let options = app.descendants(matching: .any)["keyboard.options"].firstMatch
            XCTAssertTrue(options.waitForExistence(timeout: 5), "Expected the visible options summary after selecting Order")
            XCTAssertTrue(options.waitUntilValueEquals(expected),
                          "Expected Order=\(expected), got \(accessibleText(options))")
            return
        }
        let control = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let matches = NSPredicate(format: "value == %@ OR label == %@", expected, expected)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: control)], timeout: 5), .completed,
            "Expected \(identifier) to expose \(expected), got \(accessibleText(control))")
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func collectCharacterAges(until required: Set<String>) -> [(codepoint: String, age: [Int])] {
        var observations: [(codepoint: String, age: [Int])] = []
        var seen: Set<String> = []
        let pattern = try! NSRegularExpression(pattern: #"\d+\.\d+(?:\.\d+)?"#)
        for _ in 0..<12 {
            // AX property reads cross the process boundary. Snapshot each new
            // tile once, then sort plain data rather than repeatedly resolving
            // XCUIElements from inside a comparison closure.
            let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "character-U+")).allElementsBoundByIndex
                .compactMap { tile -> (codepoint: String, ageText: String, frame: CGRect)? in
                    let codepoint = String(tile.identifier.dropFirst("character-".count))
                    guard !seen.contains(codepoint), tile.isHittable else { return nil }
                    let ageText = tile.value as? String ?? ""
                    let frame = tile.frame
                    return (codepoint, ageText, frame)
                }
                .sorted { lhs, rhs in
                    abs(lhs.frame.minY - rhs.frame.minY) > 5 ? lhs.frame.minY < rhs.frame.minY : lhs.frame.minX < rhs.frame.minX
                }
            for tile in tiles {
                let codepoint = tile.codepoint
                guard seen.insert(codepoint).inserted else { continue }
                let ageText = tile.ageText
                guard let match = pattern.firstMatch(in: ageText, range: NSRange(ageText.startIndex..., in: ageText)),
                    let range = Range(match.range, in: ageText) else {
                    XCTFail("Character \(codepoint) must expose its Unicode age; value was \(ageText)")
                    return observations
                }
                observations.append((codepoint, ageText[range].split(separator: ".").compactMap { Int($0) }))
            }
            if required.isSubset(of: seen) { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        return observations
    }

    private func version(_ lhs: [Int], precedes rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private func enableUniboardInSettings() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()

        for _ in 0..<6 {
            if settings.navigationBars["Settings"].exists { break }
            let back = settings.navigationBars.buttons.matching(NSPredicate(
                format: "label IN %@",
                ["Settings", "General", "Keyboard", "Keyboards", "Back"]
            )).firstMatch
            guard back.exists else { break }
            back.tap()
        }
        tapSettingsItem("General", in: settings)
        tapSettingsItem("Keyboard", in: settings)
        tapSettingsItem("Keyboards", in: settings)

        let existingKeyboard = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Uniboard")).firstMatch
        if existingKeyboard.exists { return }

        let addKeyboard = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Add New Keyboard")).firstMatch
        revealByScrolling(addKeyboard, in: settings)
        addKeyboard.tap()
        let uniboard = settings.descendants(matching: .any)["Uniboard"].firstMatch
        revealByScrolling(uniboard, in: settings)
        uniboard.tap()
        XCTAssertTrue(existingKeyboard.waitForExistence(timeout: 5), "Uniboard should appear in the enabled system keyboard list")
    }

    private func attachScreenshot(_ name: String) {
        // The keyboard belongs to a separate process. A full-screen capture
        // also avoids application-window crops after landscape rotation.
        // Materialize PNG bytes now, before a later orientation change can
        // affect the deferred screenshot representation in the test bundle.
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapSettingsItem(_ title: String, in settings: XCUIApplication) {
        // iOS 27 calls the keyboard preferences page "Keyboards", which is
        // also the enabled-keyboards row. Searching all StaticTexts selects
        // the navigation title; restrict selection to tappable body content.
        let cell = settings.cells.containing(.staticText, identifier: title).firstMatch
        let button = settings.buttons[title].firstMatch
        let bodyText = settings.scrollViews.staticTexts[title].firstMatch
        let item = cell.exists ? cell : button.exists ? button : bodyText
        revealByScrolling(item, in: settings)
        item.tap()
    }

    private func revealByScrolling(_ element: XCUIElement, in application: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists {
                let frame = element.frame
                // Virtualized native Settings cells can exist with an infinite,
                // zero-size frame. Never ask XCTest for such a hit point.
                if usableHeightFrame(frame), application.frame.contains(frame), element.isHittable { return }
            }
            application.swipeUp()
        }
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("Expected a visible settings or setup control: \(application.debugDescription)")
            return
        }
        let frame = element.frame
        guard usableHeightFrame(frame), application.frame.contains(frame) else {
            XCTFail("Expected a finite, fully onscreen settings or setup control: \(frame)")
            return
        }
        XCTAssertTrue(element.isHittable)
    }

    private func systemKeyboardGlobeIsVisible(_ globe: XCUIElement) -> Bool {
        guard globe.exists else { return false }
        let globeFrame = globe.frame
        // The native globe's accessibility frame can extend a fraction of a
        // point past the display edge (874.4 on this 874-point phone). Keep a
        // bounded rounding allowance; the keyboard itself must remain fully
        // onscreen and the real globe still has to provide a valid hit point.
        let roundedDisplayBounds = app.frame.insetBy(dx: -1, dy: -1)
        guard usableHeightFrame(globeFrame), roundedDisplayBounds.contains(globeFrame) else { return false }
        let visibleKeyboard = app.keyboards.allElementsBoundByAccessibilityElement.contains { keyboard in
            let frame = keyboard.frame
            return self.usableHeightFrame(frame) && self.app.frame.contains(frame)
        }
        // Verify geometry before asking for a hit point: an offscreen native
        // keyboard can remain in AX after hardware input hides its window.
        return visibleKeyboard && globe.isHittable
    }

    private func uniboardKeyboardIsVisible() -> Bool {
        let anchors = ["keyboard.toggleUnicodeToolbar", "keyboard.openFavorites", "keyboard.space"].map {
            app.descendants(matching: .any).matching(identifier: $0).firstMatch
        }
        for anchor in anchors {
            guard anchor.exists else { return false }
            let frame = anchor.frame
            guard usableHeightFrame(frame), app.frame.contains(frame) else { return false }
        }
        return anchors.allSatisfy { $0.isHittable }
    }

    private func waitForVisibleUniboardAfterSwitch(input: XCUIElement, expectedHost: String) {
        let visible = NSPredicate { _, _ in self.uniboardKeyboardIsVisible() }
        let initial = XCTNSPredicateExpectation(predicate: visible, object: app)
        if XCTWaiter.wait(for: [initial], timeout: 5) != .completed {
            attachScreenshot("Uniboard window hidden after native switch before one focus-restoring tap")
            XCTAssertEqual(input.value as? String, expectedHost)
            guard input.exists, usableHeightFrame(input.frame), app.frame.contains(input.frame) else {
                XCTFail("A real visible host input is required to restore focus after switching keyboards")
                return
            }
            XCTAssertTrue(input.isHittable)
            // Restore the same focused document once. Do not resend input,
            // reselect an input mode or accept the offscreen remote AX tree.
            input.tap()
            XCTAssertTrue(input.waitUntilValueEquals(expectedHost))
            let restored = XCTNSPredicateExpectation(predicate: visible, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed,
                           "The actual Uniboard U, symbol-board and Space controls must be onscreen and hittable: \(app.debugDescription)")
        }
        XCTAssertEqual(input.value as? String, expectedHost,
                       "Native keyboard focus restoration must preserve the exact document")
        attachScreenshot("Actual Uniboard controls visible after native keyboard switch")
    }

    private func selectUniboardKeyboard(input: XCUIElement, expectedHost: String) {
        if uniboardKeyboardIsVisible() { return }
        let systemGlobe = app.buttons["Next keyboard"].firstMatch
        if !systemKeyboardGlobeIsVisible(systemGlobe) {
            attachScreenshot("System keyboard absent before one controlled host retap")
            XCTAssertTrue(input.exists)
            XCTAssertTrue(usableHeightFrame(input.frame) && app.frame.contains(input.frame))
            XCTAssertTrue(input.isHittable)
            XCTAssertEqual(input.value as? String, expectedHost)
            // One real input tap may restore a keyboard hidden during native
            // English typeText. No global hardware setting or repeated tap is
            // changed to force the test through this precondition.
            input.tap()
            XCTAssertTrue(input.waitUntilValueEquals(expectedHost))
        }
        let softwareKeyboardReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.uniboardKeyboardIsVisible() || self.systemKeyboardGlobeIsVisible(systemGlobe)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [softwareKeyboardReady], timeout: 5), .completed,
                       "The real software keyboard and globe must be fully onscreen and hittable before extension handoff: \(app.debugDescription)")
        XCTAssertEqual(input.value as? String, expectedHost, "Software-keyboard recovery must preserve the exact seeded host")
        if uniboardKeyboardIsVisible() { return }
        attachScreenshot("Visible native software keyboard before Uniboard handoff")
        let keyboard = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Uniboard")).firstMatch
        for _ in 0..<2 {
            let globe = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5), "Expected the system keyboard globe key: \(app.debugDescription)")
            XCTAssertTrue(systemKeyboardGlobeIsVisible(globe), "A remote AX keyboard below the display is not a usable software keyboard")
            XCTAssertEqual(input.value as? String, expectedHost)
            let pickerAnchor = globe.frame
            globe.press(forDuration: 1)
            if dismissKeyboardSwitcherTipIfPresent() { continue }
            if keyboard.waitForExistence(timeout: 3) {
                keyboard.tap()
                waitForVisibleUniboardAfterSwitch(input: input, expectedHost: expectedHost)
                return
            }
            if UIDevice.current.userInterfaceIdiom == .pad,
               ProcessInfo.processInfo.environment["UNIBOARD_IPAD_LAST_KEYBOARD"] == "ad.neko.uniboard.keyboard" {
                // Explicit QA fixture only: the harness verifies English,
                // Emoji, Uniboard in that order before launch. iPadOS 18.5
                // can show this native menu without exposing its rows in AX.
                // Its last row is immediately above the actual globe anchor.
                let point = CGPoint(x: pickerAnchor.midX, y: pickerAnchor.minY - pickerAnchor.height / 2)
                guard usableHeightFrame(pickerAnchor), app.frame.contains(pickerAnchor), app.frame.contains(point),
                      app.state == .runningForeground else {
                    XCTFail("The verified iPad keyboard-picker fixture must remain fully onscreen")
                    return
                }
                XCTAssertEqual(input.value as? String, expectedHost)
                attachScreenshot("Verified three-keyboard iPad fixture before selecting its last native picker row")
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
                // Selection never counts as success by itself: require the
                // real U, Star and Space controls onscreen, and unchanged text.
                waitForVisibleUniboardAfterSwitch(input: input, expectedHost: expectedHost)
                return
            }
            break
        }
        // iPad can dismiss the native mode picker when a long press releases.
        // Cycle its real system key instead; the extension identifier remains
        // required before any insertion or layout assertion can run.
        for _ in 0..<6 {
            dismissKeyboardSwitcherTipIfPresent()
            if uniboardKeyboardIsVisible() { return }
            if app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.exists,
               !systemKeyboardGlobeIsVisible(app.buttons["Next keyboard"].firstMatch) {
                waitForVisibleUniboardAfterSwitch(input: input, expectedHost: expectedHost)
                return
            }
            let next = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 3), "Expected the native input-mode switch key: \(app.debugDescription)")
            XCTAssertTrue(systemKeyboardGlobeIsVisible(next))
            next.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5),
                      "Expected the installed Uniboard extension after native keyboard switching: \(app.debugDescription)")
        waitForVisibleUniboardAfterSwitch(input: input, expectedHost: expectedHost)
    }

    @discardableResult
    private func dismissKeyboardSwitcherTipIfPresent() -> Bool {
        // Apple presents this first-use sheet over the iPad switch key. Match
        // its exact heading so unrelated app or system dialogs stay untouched.
        let heading = app.staticTexts["Quickly Change Keyboards"].firstMatch
        guard heading.exists else { return false }
        let button = app.buttons["Continue"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(heading.waitUntilAbsent())
        return true
    }

    private func searchUnicode(_ query: String) {
        search(query, fieldIdentifier: "unicodeSearch")
    }

    private func search(_ query: String, fieldIdentifier: String) {
        let field = app.descendants(matching: .any)[fieldIdentifier].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        field.typeText(query)
    }

    private func character(_ codepoint: String) -> XCUIElement {
        app.buttons["character-\(codepoint)"].firstMatch
    }

    @discardableResult
    private func assertCharacterVisible(
        _ codepoint: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let result = character(codepoint)
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Expected \(codepoint) in character results", file: file, line: line)
        return result
    }
}

private extension XCUIElement {
    func waitUntilLabelEquals(_ expectedLabel: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expectedLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitUntilLabelHasSuffix(_ suffix: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label ENDSWITH %@", suffix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitUntilValueEquals(_ expectedValue: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitUntilAbsent(timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitUntilSelected(timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
