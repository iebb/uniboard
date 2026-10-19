import XCTest
import UIKit

@MainActor
final class UniboardUITests: XCTestCase {
    private var app: XCUIApplication!
    private struct KeyboardOptionsSnapshot {
        let dismissalPoints: [CGPoint]
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

        app.buttons["keyboard.toggleUnicodeToolbar"].tap()
        XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals("off"))
        XCTAssertEqual(measuredKeyboardHeight(), 220, "Real downward row steps reach the compact daily layout")
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

        app.buttons["keyboard.typing.number.1"].tap()
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
                                 optionCount: 9, selectedIndex: 2, extraActions: 0)
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
                XCTAssertEqual(key.frame.height, 59.8, accuracy: 1, id)
                XCTAssertGreaterThanOrEqual(key.frame.width, 44, id)
            }
            XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
            XCTAssertTrue(app.buttons["keyboard.typing.number.1"].exists)
            XCTAssertFalse(app.otherElements["keyboard.typing.favorites"].exists)
            XCTAssertEqual(app.buttons["keyboard.space"].firstMatch.frame.height, 59.8, accuracy: 1)
            XCTAssertLessThanOrEqual(app.buttons["keyboard.space"].firstMatch.frame.maxY - tab.frame.minY, 256)
            XCTAssertEqual(caps.frame.minY - tab.frame.maxY, 6, accuracy: 1)
            XCTAssertEqual(tab.frame.midY, app.buttons["keyboard.typing.key.q"].firstMatch.frame.midY, accuracy: 1)
            XCTAssertEqual(caps.frame.midY, app.buttons["keyboard.return"].firstMatch.frame.midY, accuracy: 1)
            XCTAssertLessThan(app.buttons["keyboard.return"].firstMatch.frame.maxY, app.buttons["keyboard.space"].firstMatch.frame.minY)
            assertPadFooter(pageID: "keyboard.typing.numbers")
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
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,._"))
        flickMainKey(app.buttons["keyboard.typing.key.a"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,._-"))
        flickMainKey(app.buttons["keyboard.typing.key.."].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,._-?"))
        for _ in 0..<3 { app.buttons["keyboard.typing.delete"].tap() }
        XCTAssertTrue(input.waitUntilValueEquals("\tAqq,."))
        attachScreenshot("Stock iPad three letter rows secondary flick hints gray modifiers blue Return")
        app.buttons["keyboard.typing.numbers"].tap()
        XCTAssertTrue(app.buttons["keyboard.typing.letters"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
        XCTAssertTrue(app.buttons["keyboard.return"].firstMatch.isHittable)
        assertPadFooter(pageID: "keyboard.typing.letters")
        XCTAssertEqual(app.buttons["keyboard.typing.auxiliary.["].firstMatch.frame.height, 59.8, accuracy: 1)
        app.buttons["keyboard.typing.symbols"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
        XCTAssertTrue(app.buttons["keyboard.return"].firstMatch.isHittable)
        assertPadFooter(pageID: "keyboard.typing.letters")
        app.buttons["keyboard.typing.letters"].tap()
        geometry()
        app.buttons["keyboard.toggleUnicodeToolbar"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5))
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
        for (layout, mapping, down) in [("stock", "iPad", "@"), ("ansi", "none", ""), ("ansiNumbers", "standard", "-"), ("stock", "macOS", "å")] {
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
            XCTAssertFalse(app.buttons["keyboard.typing.key.1"].exists)
            app.buttons["keyboard.typing.letters"].tap()
            assertLandscapePadGeometry(numberRow: layout == "ansiNumbers", ansi: layout != "stock")
            attachScreenshot("App-only iPad preset \(layout) symbol mapping \(mapping) with Full Access off")
            settleKeyboardOrientation(.portrait, toolbarVisible: false)
            restoreEnglishKeyboard()
        }
        configurePadSettings(layout: "ansiNumbers", mapping: "standard")
    }

    func testSystemKeyboardPadFixedTemplateKeepsNumberRowAndShiftSlideAcrossRotation() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Owned iPad QA fixture")
        configurePadSettings(layout: "ansiNumbers", mapping: "standard")
        let input = openSystemKeyboardHost(initialText: "Pad ", unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        for landscape in [false, true] {
            if landscape { settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false) }
            let top = app.buttons[landscape ? "keyboard.typing.key.1" : "keyboard.typing.number.1"].firstMatch
            let q = app.buttons["keyboard.typing.key.q"].firstMatch
            for key in [top, q, app.buttons["keyboard.typing.key.a"].firstMatch, app.buttons["keyboard.typing.key.m"].firstMatch,
                        app.buttons["keyboard.space"].firstMatch, app.buttons["keyboard.typing.tab"].firstMatch,
                        app.buttons["keyboard.typing.capsLock"].firstMatch, app.buttons["keyboard.typing.shift.right"].firstMatch] {
                XCTAssertTrue(key.waitForExistence(timeout: 5)); XCTAssertTrue(key.isHittable)
                XCTAssertEqual(key.frame.height, 59.8, accuracy: 1)
                XCTAssertTrue(app.frame.contains(key.frame))
            }
            XCTAssertFalse(app.descendants(matching: .any)["keyboard.resize"].firstMatch.exists)
            assertPadFooter(pageID: "keyboard.typing.numbers")
            app.buttons["keyboard.typing.shift"].press(forDuration: 0.6, thenDragTo: q)
            XCTAssertTrue(input.waitUntilValueEquals(landscape ? "Pad QQ" : "Pad Q"))
            attachScreenshot("Fixed iPad number row, larger keys, stock modifiers, landscape \(landscape)")
        }
    }

    func testSystemKeyboardFixedTemplateAndExclusiveTopBarSettings() throws {
        try requirePhoneKeyboardIntegration()
        defer { restoreEnglishKeyboard(); configureTopBar(symbols: true, search: false) }
        for (symbols, search) in [(true, false), (true, true), (false, false)] {
            configureTopBar(symbols: symbols, search: search)
            let input = openSystemKeyboardHost(initialText: "Fixed ", unicodeBrowse: false, searchBarVisible: symbols && search)
            let q = app.buttons["keyboard.typing.key.q"].firstMatch
            let digits = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.typing.number."))
            XCTAssertEqual(digits.count, 10)
            let surface = try XCTUnwrap(measuredKeyboardSurfaceFrame())
            XCTAssertEqual(surface.height, symbols ? 268.4 : 227, accuracy: 1)
            for key in [q, app.buttons["keyboard.typing.key.a"].firstMatch, app.buttons["keyboard.typing.key.m"].firstMatch,
                        app.buttons["keyboard.space"].firstMatch] + digits.allElementsBoundByAccessibilityElement {
                XCTAssertEqual(key.frame.height, 41.4, accuracy: 1)
                XCTAssertTrue(surface.insetBy(dx: -1, dy: -1).contains(key.frame))
            }
            XCTAssertFalse(app.descendants(matching: .any)["keyboard.resize"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["keyboard.resize.direction"].firstMatch.exists)
            let strip = app.scrollViews["keyboard.typing.favorites"].firstMatch
            XCTAssertEqual(strip.exists, symbols && !search)
            XCTAssertEqual(app.descendants(matching: .any)["keyboard.search"].firstMatch.exists, symbols && search)
            if strip.exists {
                let visible = strip.buttons.allElementsBoundByAccessibilityElement.map(\.frame).filter { $0.intersects(strip.frame) }
                XCTAssertFalse(visible.isEmpty)
                for frame in visible {
                    XCTAssertEqual(frame.height, 41.4, accuracy: 1)
                    XCTAssertEqual(frame.minY, strip.frame.minY, accuracy: 1, "Exactly one fully visible top row")
                }
                strip.swipeLeft()
                XCTAssertEqual(input.value as? String, "Fixed ", "Scrolling the symbol strip must not type")
            }
            // Remote accessibility hit-point forecasts differ on iOS 27.
            // Verify the real onscreen targets by physical coordinate taps
            // and exact host output, after the frame-containment checks above.
            var expected = "Fixed "
            let targets = Array("1234567890").map { ("keyboard.typing.number.\($0)", String($0)) }
                + [("keyboard.typing.key.q", "q"), ("keyboard.typing.key.a", "a"),
                   ("keyboard.typing.key.m", "m"), ("keyboard.space", " ")]
            for (identifier, text) in targets {
                let key = app.buttons[identifier].firstMatch
                let frame = key.frame
                XCTAssertTrue(surface.insetBy(dx: -1, dy: -1).contains(frame))
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                    dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY)).tap()
                expected += text
                XCTAssertTrue(input.waitUntilValueEquals(expected), "Actual touch on \(identifier) must insert exactly \(text)")
            }
            attachScreenshot("Fixed layout symbol bar \(symbols) search replacement \(search)")
            restoreEnglishKeyboard()
        }
    }

    private func configureTopBar(symbols: Bool, search: Bool) {
        openAppSettings()
        func set(_ identifier: String, _ enabled: Bool) {
            let control = app.switches[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            let scroll = app.scrollViews.containing(.any, identifier: "unicodeEdition").firstMatch
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            for _ in 0..<10 {
                let viewport = scroll.frame.intersection(app.frame)
                let frame = control.frame
                if usableHeightFrame(frame), viewport.contains(frame), control.isHittable { break }
                if usableHeightFrame(frame), frame.minY < viewport.minY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            }
            XCTAssertTrue(scroll.frame.intersection(app.frame).contains(control.frame))
            XCTAssertTrue(control.isHittable)
            if (control.value as? String == "1") != enabled { control.tap() }
            XCTAssertTrue(control.waitUntilValueEquals(enabled ? "1" : "0"))
        }
        set("showsSymbolBar", true)
        set("searchBarInsteadOfSymbols", search)
        set("showsSymbolBar", symbols)
        XCTAssertEqual(app.switches["searchBarInsteadOfSymbols"].firstMatch.exists, symbols)
    }

    func testSystemKeyboardDistinctLetterGesturesAndSystemShiftSlide() throws {
        try requirePhoneKeyboardIntegration()
        let context = "Literal "
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }

        let iKey = app.buttons["keyboard.typing.key.i"].firstMatch
        let oKey = app.buttons["keyboard.typing.key.o"].firstMatch
        flickMainKey(iKey, up: false)
        XCTAssertTrue(input.waitUntilValueEquals(context + "£"))
        flickMainKey(iKey, up: false, horizontal: 36)
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ"))
        flickMainKey(oKey, up: false)
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ¥"))
        flickMainKey(oKey, up: true)
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ¥O"))
        chooseHeldKeyboardOption(iKey, optionCount: 7, selectedIndex: 1, extraActions: 0)
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ¥Oì"))
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        shift.press(forDuration: 0.6, thenDragTo: q)
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ¥OìQ"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        shift.press(forDuration: 0.6)
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        q.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ¥OìQQ"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        shift.doubleTap()
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"))
        typeHostTypingKeys("qw", layout: "letters")
        XCTAssertTrue(input.waitUntilValueEquals(context + "£ˆ¥OìQQQW"))
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        attachScreenshot("Distinct letter accents, case flicks, symbols, and system Shift gestures")
    }

    func testSystemKeyboardMacOptionCandidatesKeepCaseFlicksIndependent() throws {
        try requireKeyboardIntegration()
        if UIDevice.current.userInterfaceIdiom == .pad { configurePadSettings(layout: "stock", mapping: "macOS") }
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        flickMainKey(q, up: false, horizontal: 36)
        XCTAssertTrue(input.waitUntilValueEquals("œ"))
        flickMainKey(q, up: false, horizontal: -36)
        XCTAssertTrue(input.waitUntilValueEquals("œŒ"), "Shift–Option stays literal, independent of Shift state")
        let displayedQ = q.label
        XCTAssertTrue(["q", "Q"].contains(displayedQ), "The actual key label establishes the case-flick precondition")
        let expected = "œŒ" + (displayedQ == "q" ? "Q" : "q")
        flickMainKey(q, up: true)
        XCTAssertTrue(input.waitUntilValueEquals(expected), "Up-flick inputs the opposite case of the displayed key")
        if UIDevice.current.userInterfaceIdiom == .pad {
            flickMainKey(app.buttons["keyboard.typing.key.a"].firstMatch, up: false)
            XCTAssertTrue(input.waitUntilValueEquals(expected + "å"))
            assertPadFooter(pageID: "keyboard.typing.numbers")
        }
        attachScreenshot("macOS Option and Shift Option candidates retain independent case flicks")
        if UIDevice.current.userInterfaceIdiom == .pad {
            restoreEnglishKeyboard()
            configurePadSettings(layout: "ansiNumbers", mapping: "standard")
        }
    }

    private func assertPadFooter(pageID: String, file: StaticString = #filePath, line: UInt = #line) {
        let space = app.buttons["keyboard.space"].firstMatch
        let page = app.buttons[pageID].firstMatch
        let hide = app.buttons["keyboard.collapse"].firstMatch
        for id in ["keyboard.toggleUnicodeToolbar", "keyboard.openFavorites"] {
            let key = app.buttons[id].firstMatch
            XCTAssertTrue(key.isHittable, id, file: file, line: line)
            XCTAssertLessThan(key.frame.maxX, space.frame.minX, file: file, line: line)
        }
        for key in [page, hide] {
            XCTAssertTrue(key.isHittable, file: file, line: line)
            XCTAssertGreaterThan(key.frame.minX, space.frame.maxX, file: file, line: line)
            XCTAssertEqual(key.frame.height, 59.8, accuracy: 1, file: file, line: line)
            XCTAssertGreaterThan(key.frame.width, 60, file: file, line: line)
            XCTAssertEqual(key.frame.midY, space.frame.midY, accuracy: 1, file: file, line: line)
        }
        XCTAssertGreaterThan(hide.frame.minX, page.frame.maxX, file: file, line: line)
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
            XCTAssertEqual(key.frame.height, 59.8, accuracy: 1, id, file: file, line: line)
            XCTAssertGreaterThanOrEqual(key.frame.width, 44, id, file: file, line: line)
        }
        XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1, file: file, line: line)
        XCTAssertGreaterThan(page.frame.minX, space.frame.maxX, file: file, line: line)
        XCTAssertGreaterThan(hide.frame.minX, page.frame.maxX, file: file, line: line)
        XCTAssertEqual(page.frame.midY, space.frame.midY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(hide.frame.midY, space.frame.midY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(space.frame.maxY - top.frame.minY, numberRow ? 321 : 255.2, accuracy: 1, file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.key.["].exists, ansi, file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.key.1"].exists, numberRow, file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.number.1"].exists, !numberRow, file: file, line: line)
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
        let frame = key.frame
        guard usableHeightFrame(frame), app.frame.contains(frame) else {
            XCTFail("A character gesture requires a visible keycap", file: file, line: line); return
        }
        // A leftward candidate on Q must finish on screen. Starting near
        // its trailing edge keeps the physical gesture inside the keyboard.
        let x = min(frame.maxX - 2, max(frame.minX + 2,
            min(app.frame.maxX - horizontal - 4, max(frame.midX, app.frame.minX - horizontal + 4))))
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: x - app.frame.minX, dy: frame.midY - app.frame.minY))
        let distance = max(28, abs(horizontal) + 12)
        let vertical = start.withOffset(CGVector(dx: 0, dy: up ? -distance : distance))
        if horizontal == 0 {
            start.press(forDuration: 0.05, thenDragTo: vertical)
        } else {
            XCTAssertTrue(app.frame.contains(CGPoint(x: x + horizontal, y: frame.midY + (up ? -distance : distance))),
                          "The gesture's actual endpoint must be on screen", file: file, line: line)
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
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: true)
        let context = "Favorites preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, searchBarVisible: true)
        defer {
            XCUIDevice.shared.orientation = .portrait
            restoreEnglishKeyboard()
            configureTopBar(symbols: true, search: false)
        }
        selectSymbolBoard("migrated-favorites", input: input, context: context, returnToTyping: true,
                          preferredStarBoardID: "migrated-favorites")
        let favoriteKey = app.buttons["keyboard.openFavorites"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let favorites = app.buttons["Favorites"].firstMatch
        let recent = app.buttons["Recent"].firstMatch
        let originalHeight = measuredKeyboardHeight()
        XCTAssertNotNil(originalHeight)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        favoriteKey.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.section"].firstMatch.waitUntilValueEquals("saved"))
        XCTAssertTrue(favorites.waitUntilSelected())
        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        XCTAssertEqual(favoriteKey.label, "Back to English keyboard")
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        XCTAssertEqual(input.value as? String, context)
        if let originalHeight { XCTAssertEqual(measuredKeyboardHeight(), originalHeight) }
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
        XCTAssertEqual(favoriteKey.label, "Back to English keyboard", "Star returns to English from every symbol page, including Recent")
        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        favoriteKey.tap()
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
        XCTAssertEqual(savedSnowman.frame.height, 41.4, accuracy: 1)
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


        assertFavoritesKeyImmediatelyPrecedesSpace()
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        favoriteKey.tap()
        XCTAssertTrue(favorites.waitUntilSelected())

        assertFavoritesKeyImmediatelyPrecedesSpace()
        attachScreenshot("Favorites and Space remain contained at the minimum portrait height")
        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("favorites.landscape", input: input, searching: false, expectedSurfaceHeight: 278.4)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        XCTAssertEqual(input.value as? String, context + "☃")
        settleKeyboardOrientation(.portrait)

        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        favoriteKey.tap()
        assertHostTypingPanel()
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        XCTAssertEqual(input.value as? String, context + "☃")

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

    func testSystemKeyboardFavoritesSyncWithSavedAndKeepHostLiteral() throws {
        try requirePhoneKeyboardIntegration()
        setKeyboardFullAccess(false)
        var input = openSystemKeyboardHost(initialText: "Sync test.", unicodeBrowse: false)
        defer { restoreEnglishKeyboard(); setKeyboardFullAccess(false); app.activate() }
        restoreEnglishKeyboard()
        app.navigationBars["Try Uniboard"].buttons["Settings"].tap()
        appTab("Explore").tap()
        searchUnicode("u+2603")
        assertCharacterVisible("U+2603").tap()
        let favorite = app.buttons["toggleFavorite"].firstMatch
        revealByScrolling(favorite, in: app)
        XCTAssertEqual(favorite.label, "Add to favorites")
        favorite.tap()
        XCTAssertTrue(favorite.waitUntilLabelEquals("Remove from favorites"))
        app.buttons["Done"].tap()
        appTab("Saved").tap()
        XCTAssertTrue(app.otherElements["savedFavorites"].buttons["character-U+2603"].firstMatch.waitForExistence(timeout: 5))
        func reopenHost() -> XCUIElement {
            appTab("Settings").tap()
            let tryKeyboard = app.descendants(matching: .any)["tryKeyboard"].firstMatch
            revealByScrolling(tryKeyboard, in: app); tryKeyboard.tap()
            let host = app.textViews["keyboardTestInput"].firstMatch
            XCTAssertTrue(host.waitForExistence(timeout: 5)); host.tap()
            selectUniboardKeyboard(input: host, expectedHost: "")
            return host
        }
        input = reopenHost()
        selectSymbolBoard("migrated-favorites", input: input, context: "")
        let snowman = symbolBoardKey("☃")
        XCTAssertTrue(snowman.waitForExistence(timeout: 5), "App Saved must reach the actual extension without Full Access")
        snowman.tap()
        XCTAssertTrue(input.waitUntilValueEquals("☃"))
        attachScreenshot("App Saved favorite appears in the real keyboard with Full Access off")
        restoreEnglishKeyboard()
        app.navigationBars["Try Uniboard"].buttons["Settings"].tap()
        appTab("Saved").tap()
        app.otherElements["savedFavorites"].buttons["character-U+2603"].firstMatch.tap()
        revealByScrolling(favorite, in: app); favorite.tap()
        XCTAssertTrue(favorite.waitUntilLabelEquals("Add to favorites"))
        app.buttons["Done"].tap()
        input = reopenHost()
        selectSymbolBoard("migrated-favorites", input: input, context: "")
        XCTAssertFalse(symbolBoardKey("☃").exists, "App removal must not be resurrected by the extension cache")
        setKeyboardFullAccess(true)
        app.activate()
        // iOS may restart both processes when this permission changes. Reopen
        // through real navigation rather than retaining an invalid editor AX.
        input = reopenHost()
        saveKeyboardFavoriteFixture(section: "symbols", query: "u+2665", identifier: "keyboard.character.U+2665", input: input, context: "")
        restoreEnglishKeyboard()
        app.navigationBars["Try Uniboard"].buttons["Settings"].tap()
        appTab("Saved").tap()
        XCTAssertTrue(app.otherElements["savedFavorites"].buttons["character-U+2665"].firstMatch.waitForExistence(timeout: 5),
                      "Keyboard save must reach Saved when Full Access permits shared writes")
        attachScreenshot("Keyboard favorite returns to companion Saved with Full Access on")
    }

    private func setKeyboardFullAccess(_ enabled: Bool) {
        enableUniboardInSettings()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let row = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Uniboard")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let access = settings.switches["Allow Full Access"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        if (access.value as? String == "1") != enabled {
            access.tap()
            if enabled {
                let allow = settings.alerts.buttons["Allow"].firstMatch
                if allow.waitForExistence(timeout: 3) { allow.tap() }
            }
        }
        XCTAssertTrue(access.waitUntilValueEquals(enabled ? "1" : "0"))
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
        try requirePhoneKeyboardIntegration()
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

    private func swipeSymbolPage(left: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let pager = app.descendants(matching: .any)["keyboard.pages.pager"].firstMatch
        guard pager.exists, usableHeightFrame(pager.frame), app.frame.contains(pager.frame) else {
            XCTFail("A page drag needs the real visible keyboard viewport", file: file, line: line); return
        }
        let frame = pager.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.minX + frame.width * (left ? 0.8 : 0.2) - app.frame.minX,
                                               dy: frame.midY - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: frame.minX + frame.width * (left ? 0.2 : 0.8) - app.frame.minX,
                                             dy: frame.midY - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    private func waitForSymbolPage(_ id: String) -> Bool {
        let tab = app.buttons["keyboard.pages.tab.\(id)"].firstMatch
        let pager = app.descendants(matching: .any)["keyboard.pages.pager"].firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            tab.exists && tab.isSelected && pager.exists && (pager.value as? String) == tab.label
        }, object: app)
        return XCTWaiter.wait(for: [settled], timeout: 5) == .completed
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
        let primaryColumn = (min(optionCount, columns) - 1) / 2
        let x = min(root.maxX - 4 - width, max(root.minX + 4, anchor.midX - (CGFloat(primaryColumn) + 0.5) * cellWidth))
        let above = anchor.minY - 6 - height
        let y = min(root.maxY - 4 - height, max(root.minY + 4, above >= root.minY + 4 ? above : anchor.maxY + 6))
        var visualOrder: [Int] = []
        for start in stride(from: 0, to: optionCount, by: columns) {
            let rowCount = min(columns, optionCount - start)
            visualOrder += (0..<rowCount).filter { $0 % 2 == 0 }.reversed().map { start + $0 }
            visualOrder += (0..<rowCount).filter { $0 % 2 == 1 }.map { start + $0 }
        }
        visualOrder += optionCount..<count
        let position = visualOrder.firstIndex(of: selectedIndex)!
        let point = CGPoint(x: x + (CGFloat(position % columns) + 0.5) * cellWidth,
                            y: y + (CGFloat(position / columns) + 0.5) * cellHeight)
        XCTAssertTrue(root.contains(point))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    func testAppSearchDoneStaysInsideKeyboardAndDismissesWithoutChangingQuery() throws {
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: false)
        _ = openSystemKeyboardHost(unicodeBrowse: false)
        restoreEnglishKeyboard()
        app.terminate(); app.launch()
        appTab("Explore").tap()
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

    func testSystemKeyboardIPadSymbolPagesRotateWithoutChangingToolbar() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Owned iPad fixture only")
        configureTopBar(symbols: true, search: false)
        let context = "iPad pages preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        star.tap()
        XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        swipeSymbolPage(left: false)
        XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        let bang = symbolBoardKey("!")
        XCTAssertTrue(bang.waitForExistence(timeout: 5))
        XCTAssertEqual(bang.frame.height, 59.8, accuracy: 1)
        func tapVisible(_ control: XCUIElement) {
            guard let root = measuredKeyboardSurfaceFrame(), usableHeightFrame(control.frame), root.contains(control.frame) else {
                XCTFail("Require the actual visible iPad key inside the keyboard allocation"); return
            }
            let frame = control.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX-app.frame.minX, dy: frame.midY-app.frame.minY)).tap()
        }
        tapVisible(bang)
        XCTAssertTrue(input.waitUntilValueEquals(context + "!"))
        tapVisible(app.buttons["keyboard.pages.delete"].firstMatch)
        XCTAssertTrue(input.waitUntilValueEquals(context))
        settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false)
        XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        XCTAssertEqual(bang.frame.height, 59.8, accuracy: 1)
        attachScreenshot("Landscape iPad symbol pages retain full keycaps and U-off")
        swipeSymbolPage(left: true); XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        swipeSymbolPage(left: true); XCTAssertTrue(waitForSymbolPage("recent"))
        let recent = app.buttons["keyboard.character.U+0021"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); tapVisible(recent)
        XCTAssertTrue(input.waitUntilValueEquals(context + "!"))
        settleKeyboardOrientation(.portrait, toolbarVisible: false)
        XCTAssertTrue(waitForSymbolPage("recent"))
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        tapVisible(app.buttons["keyboard.pages.delete"].firstMatch)
        XCTAssertTrue(input.waitUntilValueEquals(context))
        attachScreenshot("Portrait iPad restores Recent without opening the search bar")
        star.tap(); assertHostTypingPanel()
    }

    func testSystemKeyboardSymbolPagesSynchronizeVisiblePageAndKeys() throws {
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: false)
        let context = "Page sync "
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        star.tap()
        XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        swipeSymbolPage(left: false)
        XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        let bang = symbolBoardKey("!")
        XCTAssertTrue(bang.waitForExistence(timeout: 5))
        func tapVisible(_ control: XCUIElement) {
            guard let root = measuredKeyboardSurfaceFrame(), usableHeightFrame(control.frame), root.contains(control.frame) else {
                XCTFail("Require an actual visible symbol-page key"); return
            }
            let frame = control.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX-app.frame.minX, dy: frame.midY-app.frame.minY)).tap()
        }
        tapVisible(bang); XCTAssertTrue(input.waitUntilValueEquals(context + "!"))
        tapVisible(app.buttons["keyboard.pages.delete"].firstMatch)
        XCTAssertTrue(input.waitUntilValueEquals(context))
        swipeSymbolPage(left: true); XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        XCTAssertFalse(symbolBoardKey("!").exists, "An off-page board must not expose active character keys")
        swipeSymbolPage(left: false); XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Visible symbol page, highlighted tab and accepted key actions stay synchronized")
        star.tap(); assertHostTypingPanel()
    }

    func testSystemKeyboardSymbolPagesPreserveVisibleSearchBarAndKeys() throws {
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: true)
        let context = "Visible toolbar pages."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, searchBarVisible: true)
        defer { restoreEnglishKeyboard(); configureTopBar(symbols: true, search: false) }
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        star.tap()
        XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        XCTAssertTrue(toggle.waitUntilValueEquals("on"))
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        swipeSymbolPage(left: false)
        XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        let bang = symbolBoardKey("!")
        XCTAssertTrue(bang.waitForExistence(timeout: 5))
        for control in [bang, app.buttons["keyboard.pages.delete"].firstMatch] {
            guard let root = measuredKeyboardSurfaceFrame(), usableHeightFrame(control.frame), root.contains(control.frame) else {
                XCTFail("A real symbol-page key must be fully inside the visible keyboard"); return
            }
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(input.waitUntilValueEquals(control.identifier == bang.identifier ? context + "!" : context))
        }
        swipeSymbolPage(left: true)
        XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        toggle.tap()
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        XCTAssertFalse(search.exists)
        swipeSymbolPage(left: false)
        XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        toggle.tap()
        XCTAssertTrue(toggle.waitUntilValueEquals("on"))
        XCTAssertTrue(waitForSymbolPage("stock-symbols"))
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Paging and actual key actions preserve U through live toolbar changes")
        star.tap(); assertHostTypingPanel()
    }

    func testSystemKeyboardSymbolPagesCreateSwipeAndDeleteWithToolbarHidden() throws {
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: false)
        let context = "Pages preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        star.press(forDuration: 1)
        assertSymbolBoardOverlay(input: input, context: context)
        var created: [String] = []
        for name in ["qaone", "qatwo"] {
            let create = app.buttons["keyboard.boards.create"].firstMatch
            tapSymbolBoardControl(create)
            let add = app.buttons["keyboard.boards.pad.save"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5)); XCTAssertFalse(add.isEnabled)
            let entryHierarchy = XCTAttachment(string: app.debugDescription)
            entryHierarchy.name = "New page keyboard and local letter control identities"
            entryHierarchy.lifetime = .keepAlways; self.add(entryHierarchy)
            assertSymbolBoardOverlay(input: input, context: context)
            typeSymbolBoardLocalPad(name)
            XCTAssertTrue(add.isEnabled)
            assertSymbolBoardOverlay(input: input, context: context)
            attachScreenshot("New page has a contained name field, keycaps and Add action")
            tapSymbolBoardControl(add)
            let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "keyboard.boards.select.", "Selected")).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 5))
            created.append(String(selected.identifier.dropFirst("keyboard.boards.select.".count)))
        }
        let ids = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.boards.select."))
            .allElementsBoundByAccessibilityElement.map { String($0.identifier.dropFirst("keyboard.boards.select.".count)) }
        XCTAssertGreaterThanOrEqual(ids.count, 4)
        let first = app.buttons["keyboard.boards.select.\(ids[0])"].firstMatch
        tapSymbolBoardControl(first)
        XCTAssertTrue(waitForSymbolPage(ids[0]))
        XCTAssertTrue(toggle.waitUntilValueEquals("off"), "Opening or editing pages must preserve U-off")
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.search"].firstMatch.exists)
        for id in Array(ids.dropFirst()) + ["recent"] {
            swipeSymbolPage(left: true)
            XCTAssertTrue(waitForSymbolPage(id), "Each horizontal gesture advances exactly one page")
            XCTAssertTrue(toggle.waitUntilValueEquals("off"))
            XCTAssertEqual(input.value as? String, context, "Swiping cancels key presses instead of inserting")
        }
        swipeSymbolPage(left: true)
        XCTAssertTrue(waitForSymbolPage("recent"), "The last page does not wrap or lose selection")
        swipeSymbolPage(left: false)
        XCTAssertTrue(waitForSymbolPage(ids.last!))
        attachScreenshot("All saved pages and Recent are reachable with one-page horizontal swipes")
        for id in created {
            star.press(forDuration: 1)
            let edit = app.buttons["keyboard.boards.edit.\(id)"].firstMatch
            tapSymbolBoardControl(edit)
            let remove = app.buttons["keyboard.boards.delete"].firstMatch
            tapSymbolBoardControl(remove)
            XCTAssertTrue(app.buttons["keyboard.boards.select.\(id)"].firstMatch.waitUntilAbsent())
            tapSymbolBoardControl(app.buttons["keyboard.boards.close"].firstMatch)
            XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        }
        star.tap()
        assertHostTypingPanel()
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        XCTAssertEqual(input.value as? String, context)
    }

    func testSystemKeyboardSymbolBoardsPreserveExactVariantsAndLocalConfiguration() throws {
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: false)
        let context = "Symbol boards preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        selectSymbolBoard("stock-symbols", input: input, context: context, returnToTyping: true)


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
        XCTAssertEqual(last.frame.height, 41.4, accuracy: 1)
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
        settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false)
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
        settleKeyboardOrientation(.portrait, toolbarVisible: false)
        let toolbarToggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toolbarToggle.waitUntilValueEquals("off"))
        XCTAssertFalse(search.exists)
        toolbarToggle.tap()
        XCTAssertTrue(waitForSymbolPage(boardID))
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        let configured = symbolBoardKey("☃")
        XCTAssertTrue(configured.waitForExistence(timeout: 5))
        XCTAssertEqual(configured.frame.height, 41.4, accuracy: 1)
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
        ensureUnicodeToolbarVisible()
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
            XCTAssertEqual(frame.height, 41.4, accuracy: 1, file: file, line: line)
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
        XCTAssertTrue(manager.waitForExistence(timeout: 5), file: file, line: line)
        let entry = app.descendants(matching: .any)["keyboard.boards.entryPanel"].firstMatch
        let scroll = app.scrollViews["keyboard.boards.scroll"].firstMatch
        let content = entry.exists ? entry : scroll
        guard usableHeightFrame(manager.frame), app.frame.contains(manager.frame),
              header.exists, content.exists, usableHeightFrame(header.frame), usableHeightFrame(content.frame) else {
            XCTFail("Page editing needs an on-screen opaque panel, header and bounded content", file: file, line: line); return
        }
        let panel = manager.frame
        XCTAssertTrue(panel.insetBy(dx: -1, dy: -1).contains(header.frame), file: file, line: line)
        XCTAssertTrue(panel.insetBy(dx: -1, dy: -1).contains(content.frame), file: file, line: line)
        XCTAssertLessThanOrEqual(header.frame.maxY, content.frame.minY + 1, file: file, line: line)
        for control in header.buttons.allElementsBoundByAccessibilityElement {
            XCTAssertTrue(panel.contains(control.frame), "Every header action stays inside the keyboard", file: file, line: line)
        }
        if entry.exists {
            for control in entry.buttons.allElementsBoundByAccessibilityElement {
                XCTAssertTrue(usableHeightFrame(control.frame) && panel.contains(control.frame),
                              "The naming pad must fit without scrolling or clipping", file: file, line: line)
            }
        }
        XCTAssertTrue(input.waitUntilValueEquals(context), file: file, line: line)
        attachScreenshot("Page configuration and its local keyboard stay inside the extension")
    }

    private func typeSymbolBoardLocalPad(_ text: String) {
        let field = app.descendants(matching: .any)["keyboard.boards.entry"].firstMatch
        var expected = field.value as? String ?? ""
        for character in text {
            let key = app.buttons["keyboard.boards.pad.\(character)"].firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5))
            tapSymbolBoardControl(key)
            expected.append(character)
            XCTAssertTrue(field.waitUntilValueEquals(expected), "Every real local-key tap must edit the name/variant, never the receiving document")
        }
    }

    private func revealSymbolBoardControl(_ control: XCUIElement) {
        let manager = app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch
        if control.exists, manager.exists, usableHeightFrame(control.frame), manager.frame.contains(control.frame) { return }
        let scroll = app.scrollViews["keyboard.boards.scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for step in 0..<8 {
            let viewport = scroll.frame.intersection(app.frame)
            guard usableHeightFrame(viewport) else { XCTFail("Expected the actual configuration viewport"); return }
            print("UNIBOARD_EDITOR_REVEAL step=\(step) target=\(control.identifier) viewport=\(viewport) targetFrame=\(control.exists ? String(describing: control.frame) : "absent")")
            if control.exists, usableHeightFrame(control.frame), viewport.contains(control.frame) { return }
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
    }

    private func tapSymbolBoardControl(_ control: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        revealSymbolBoardControl(control)
        let manager = app.descendants(matching: .any)["keyboard.boards.manager"].firstMatch
        let frame = control.frame
        guard manager.exists, usableHeightFrame(frame), manager.frame.contains(frame), app.frame.contains(frame), control.isEnabled else {
            XCTFail("A configuration tap needs an enabled, fully visible control inside the current panel", file: file, line: line); return
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY)).tap()
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
            XCTAssertEqual(frame.height, 41.4, accuracy: 1, file: file, line: line)
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
        assertKeyboardSettingsMenuOnlyOrder()
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
        assertKeyboardSettingsMenuOnlyOrder()
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
        assertKeyboardSettingsMenuOnlyOrder()
        attachScreenshot("Optional font preview inserts the original scalar with intact portrait toolbar")
        closeKeyboardSearch()

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return frame.width > frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        assertKeyboardSettingsMenuOnlyOrder()
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
        assertKeyboardSettingsMenuOnlyOrder()
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
        assertKeyboardSettingsMenuOnlyOrder()
        attachScreenshot("App Settings fonts and collapse off are reflected by the relaunched keyboard")
    }


    func testSystemKeyboardCompactLayoutPreservesVisibleHostAndExactInput() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        setAppUnicodeFonts(false)
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }

        assertKeyboardSettingsMenuOnlyOrder()
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


    func testSystemKeyboardLandscapeOptionsAcceptsVisibleCenterTouch() throws {
        try requirePhoneKeyboardIntegration()
        configureTopBar(symbols: true, search: true)
        let context = "Landscape menu preserves this document."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard(); configureTopBar(symbols: true, search: false) }

        enterKeyboardQuery("u+1f680")
        closeKeyboardSearch()
        openUnicodeBrowse()
        let rocket = app.buttons["keyboard.character.U+1F680"].firstMatch
        XCTAssertTrue(rocket.waitForExistence(timeout: 5))
        rocket.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "🚀"))
        assertKeyboardSettingsMenuOnlyOrder()
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
        assertKeyboardSettingsMenuOnlyOrder()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+1f680"))
        XCTAssertEqual(input.value as? String, context + "🚀")
        for order in ["newest", "oldest", "codepoint"] {
            selectKeyboardOrder(order)
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+1f680"))
            XCTAssertEqual(input.value as? String, context + "🚀")
        }
        attachScreenshot("Direct sorting choices work and dismiss in portrait and landscape without changing input")
    }


    private func usableHeightFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }


    private func measuredKeyboardSurfaceFrame() -> CGRect? {
        let surface = app.descendants(matching: .any)["keyboard.surface"].firstMatch
        guard surface.exists, usableHeightFrame(surface.frame), app.frame.insetBy(dx: -1, dy: -1).contains(surface.frame) else { return nil }
        return surface.frame
    }

    private func measuredKeyboardHeight() -> Int? {
        measuredKeyboardSurfaceFrame().map { Int($0.height.rounded()) }
    }


    func testSystemKeyboardCompactMenusAndInspectionPreserveContext() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        let input = openSystemKeyboardHost(initialText: context)
        defer { restoreEnglishKeyboard() }
        selectSymbolBoard("migrated-favorites", input: input, context: context)

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
        assertKeyboardSettingsMenuOnlyOrder()
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
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let effectiveExpected = expectedSurfaceHeight
        let maximum: CGFloat = effectiveExpected ?? (pad ? 396 : 280)
        XCTAssertFalse(candidates.isEmpty, "Expected the actual keyboard surface ancestor", file: file, line: line)
        if let surface = candidates.first {
            XCTAssertLessThanOrEqual(surface.height, maximum + 1, "Keyboard must leave host space instead of reverting to tall chrome", file: file, line: line)
            if let effectiveExpected {
                XCTAssertEqual(surface.height, effectiveExpected, accuracy: 1,
                               "The measured keyboard surface must match its fixed template height", file: file, line: line)
            }
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(surface), "Keyboard surface must not extend above or outside the display", file: file, line: line)
        }
        let value: [String: Any] = ["mode": mode, "app": rect(app.frame), "hostEditor": rect(input.frame),
            "hostText": input.value as? String ?? "", "hostIsHittable": input.isHittable,
            "surfaceCandidates": candidates.map(rect), "search": rect(search), "footer": rect(footer),
            "visibleControlSpan": footer.maxY - (candidates.first?.minY ?? footer.minY), "maximumSurfaceHeight": maximum]
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
            assertKeyboardSettingsMenuOnlyOrder()
            for (codepoint, age) in fixtures {
                enterKeyboardQuery("u+\(codepoint.lowercased())")
                let result = app.buttons["keyboard.character.U+\(codepoint)"].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 10))
                XCTAssertTrue(result.waitUntilLabelHasSuffix(age.isEmpty ? ", Unassigned" : ", U\(age)"))
                XCTAssertEqual(input.value as? String, context, "App edition synchronization must not edit the host")
                closeKeyboardSearch()
                assertKeyboardSettingsMenuOnlyOrder()
            }
            attachScreenshot("Real keyboard follows app Settings \(edition) without a catalog selector")
        }
        restoreEnglishKeyboard()
        selectAppEdition("latest")
    }

    private func assertKeyboardHasNoEditionSelector() {
        openKeyboardOptions()
        guard let popup = nativeKeyboardOptionsPopup() else {
            XCTFail("Require the actual native options menu before checking its available actions"); return
        }
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
        let option = keyboardSortOption("codepoint")
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
        guard let surface = measuredKeyboardSurfaceFrame(), usableHeightFrame(surface) else {
            XCTFail("Menu dismissal needs the real keyboard surface before presentation"); return
        }
        let footer = app.buttons["keyboard.space"].firstMatch.frame
        guard usableHeightFrame(footer), surface.contains(footer) else {
            XCTFail("Menu dismissal needs the visible keyboard footer"); return
        }
        let gapY = footer.minY - 2
        let points = [surface.minX + 2, surface.maxX - 2, surface.midX].map { CGPoint(x: $0, y: gapY) }
        guard points.allSatisfy(surface.contains) else { XCTFail("Dismissal points must remain inside the keyboard"); return }
        keyboardOptionsSnapshot = KeyboardOptionsSnapshot(dismissalPoints: points, hostText: hostText,
                                                          queryValue: queryValue, optionsValue: optionsValue)
        // iPad's observed accessibility tap point was near the rounded cap's
        // corner. Target its centre explicitly while keeping real menu checks.
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The actual options menu must open")
    }

    private func keyboardSortOption(_ order: String) -> XCUIElement {
        let titles = ["newest": "Newest first", "oldest": "Oldest first", "codepoint": "Code point"]
        guard let title = titles[order] else { XCTFail("Unknown test sort option"); return app.buttons["missing.sort.option"] }
        // UIKit's remote menu drops custom SwiftUI identifiers on iOS 27.
        return app.buttons[title].firstMatch
    }

    private func closeKeyboardOptions(_ nativePopup: XCUIElement) {
        defer { keyboardOptionsSnapshot = nil }
        let option = keyboardSortOption("codepoint")
        if nativePopup.exists || option.exists {
            guard let snapshot = keyboardOptionsSnapshot,
                  usableHeightFrame(nativePopup.frame),
                  let point = snapshot.dismissalPoints.first(where: { !nativePopup.frame.insetBy(dx: -4, dy: -4).contains($0) }) else {
                XCTFail("Dismissal requires a measured blank keyboard gap outside the actual popup"); return
            }
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY)).tap()
        }
        XCTAssertTrue(nativePopup.waitUntilAbsent(), "The actual native popup must close")
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

    private func selectKeyboardOrder(_ order: String) {
        openKeyboardOptions()
        let option = keyboardSortOption(order)
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        let frame = option.frame
        XCTAssertTrue(usableHeightFrame(frame) && app.frame.contains(frame))
        app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY)).tap()
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
        // Identify the actual popup through a stable visible sort action.
        app.collectionViews.allElementsBoundByAccessibilityElement.first(where: {
            $0.buttons["Code point"].firstMatch.exists
        })
    }

    private func assertKeyboardSettingsMenuOnlyOrder(file: StaticString = #filePath, line: UInt = #line) {
        openKeyboardOptions()
        guard let popup = nativeKeyboardOptionsPopup() else {
            XCTFail("Expected the native options popup collection", file: file, line: line)
            return
        }
        defer { closeKeyboardOptions(popup) }
        for identifier in ["keyboard.edition", "keyboard.unicodeFonts", "keyboard.showCollapseKey", "keyboard.inspectLast", "keyboard.saveLast", "keyboard.openCompanionApp", "keyboard.openCompanionApp.guidance"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].firstMatch.exists,
                           "Keyboard options contain only ordering", file: file, line: line)
        }
        XCTAssertFalse(app.buttons["Save to page"].firstMatch.exists)
        let controls = ["newest", "oldest", "codepoint"].map { keyboardSortOption($0) }
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(control.isEnabled, file: file, line: line)
            let frame = control.frame
            XCTAssertTrue(usableHeightFrame(frame), file: file, line: line)
            XCTAssertTrue(popup.frame.insetBy(dx: -1, dy: -1).contains(frame),
                          "Each native menu action must be fully revealed in its actual scroll viewport", file: file, line: line)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame),
                          "A keyboard setting must not be clipped: \(frame)", file: file, line: line)
        }
    }

    private func requirePhoneKeyboardIntegration() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                      "This case verifies the phone keyboard template.")
    }

    private func requireKeyboardIntegration() throws {
        let enabled = ProcessInfo.processInfo.environment["UNIBOARD_KEYBOARD_INTEGRATION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--keyboard-integration")
        try XCTSkipUnless(enabled, "Set UNIBOARD_KEYBOARD_INTEGRATION=1 in the UI test runner to exercise the installed system keyboard.")
    }

    private func openSystemKeyboardHost(initialText: String = "", unicodeBrowse: Bool = true, searchBarVisible: Bool = false) -> XCUIElement {
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
            XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals(searchBarVisible ? "on" : "off"))
            if !searchBarVisible {
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
            }
            let widePad = UIDevice.current.userInterfaceIdiom == .pad && app.buttons["keyboard.typing.tab"].firstMatch.exists
            XCTAssertEqual(app.buttons["keyboard.collapse"].firstMatch.exists, widePad,
                "Wide iPad keeps Hide beside Space; compact layouts default to no collapse key")
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
            if app.buttons["keyboard.openTyping"].firstMatch.exists {
                app.buttons["keyboard.toggleUnicodeToolbar"].tap()
            }
            XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].waitUntilValueEquals(searchBarVisible ? "on" : "off"))
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
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        if toggle.value as? String == "off" {
            XCTAssertFalse(search.exists)
            toggle.tap()
            XCTAssertTrue(search.waitUntilValueEquals(query ?? "No query"), "U reopens the exact retained query")
            toggle.tap()
            XCTAssertTrue(toggle.waitUntilValueEquals("off"))
            assertHostTypingPanel()
            XCTAssertFalse(search.exists)
        } else {
            XCTAssertTrue(search.waitUntilValueEquals(query ?? "No query"), "Done retains the exact local query")
        }
        XCTAssertTrue(input.waitUntilValueEquals(hostText ?? ""))
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
            // Selection dismisses the sorting menu before the toolbar reappears.
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
            globe.press(forDuration: 1)
            if dismissKeyboardSwitcherTipIfPresent() { continue }
            if keyboard.waitForExistence(timeout: 3) {
                keyboard.tap()
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
