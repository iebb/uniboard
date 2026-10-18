import XCTest
import UIKit

@MainActor
final class UniboardUITests: XCTestCase {
    private var app: XCUIApplication!

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
        // The current official 18.0 and 19.0-development sources may contain
        // identical assigned scalars. Verify honest status in each catalog;
        // a future draft must not be represented with fabricated characters.
        assertControlValue("unicodeEdition", equals: "draft")
        for edition in ["draft", "latest"] {
            selectAppEdition(edition)
            searchUnicode("U+0041")
            let assigned = assertCharacterVisible("U+0041")
            XCTAssertTrue(assigned.waitUntilValueEquals("Unicode 1.1"))
            assigned.tap()
            assertCharacterProperty("status", equals: "Assigned")
            assertCharacterProperty("age", equals: "1.1")
            app.buttons["Done"].tap()

            searchUnicode("U+0378")
            let unassigned = assertCharacterVisible("U+0378")
            XCTAssertTrue(unassigned.waitUntilValueEquals("Unassigned"))
            unassigned.tap()
            assertCharacterProperty("status", equals: "Unassigned")
            assertCharacterProperty("category", contains: "Cn")
            attachScreenshot("\(edition) catalog accurately reports unassigned U+0378")
            app.buttons["Done"].tap()
        }
        assertControlValue("unicodeEdition", equals: "latest")

        // A real relaunch intentionally omits the test-reset argument, so this
        // checks persisted user choice rather than a test-only injection.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        assertControlValue("unicodeEdition", equals: "latest")
        searchUnicode("U+0378")
        XCTAssertTrue(assertCharacterVisible("U+0378").waitUntilValueEquals("Unassigned"))
        dismissAppSearchKeyboard()
        attachScreenshot("Latest catalog selection persists after ordinary relaunch")
    }

    func testDefaultNewestFirstUsesNumericUnicodeAges() {
        assertControlValue("unicodeSort", equals: "newestFirst")
        attachScreenshot("Default Explore displays newest Unicode characters first")
        searchUnicode("heart")
        dismissAppSearchKeyboard()
        XCTAssertTrue(character("U+1FA77").waitForExistence(timeout: 10), "Heart results should replace the initial discovery grid")

        // These ages deliberately cross the lexical boundary: "6.0" sorts
        // after "15.0" as text, but before it as a Unicode version.
        let samples = collectCharacterAges(until: ["U+1FA77", "U+1F49E", "U+2661"])
        XCTAssertGreaterThanOrEqual(samples.count, 3)
        attachScreenshot("Numeric newest-first heart results across Unicode ages")
        for (newer, older) in zip(samples, samples.dropFirst()) {
            XCTAssertFalse(version(newer.age, precedes: older.age),
                "Newest-first must order numeric ages: \(newer.codepoint) \(newer.age) precedes \(older.codepoint) \(older.age)")
        }
        let required = [("U+1FA77", [15, 0]), ("U+1F49E", [6, 0]), ("U+2661", [1, 1])]
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

    func testOptionalUnicodeFontsDefaultOffAndAppChoicePersists() {
        let fonts = appUnicodeFontsSwitch()
        XCTAssertTrue(fonts.waitUntilValueEquals("0"), "Extra preview fonts must default off")
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

    func testSystemKeyboardOptionalFontsAreLocalAndPreserveExactInsertion() throws {
        try requireKeyboardIntegration()
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("0"))
        setAppUnicodeFonts(true)
        app.launchArguments = []
        var input = openSystemKeyboardHost()
        defer {
            XCUIDevice.shared.orientation = .portrait
            if app.buttons["keyboard.properties.close"].firstMatch.exists {
                app.buttons["keyboard.properties.close"].firstMatch.tap()
            }
            if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
            if app.buttons["keyboard.options"].firstMatch.exists || app.buttons["keyboard.unicodeFonts"].firstMatch.exists { selectKeyboardFonts(false) }
            restoreEnglishKeyboard()
        }
        assertControlValue("keyboard.unicodeFonts", equals: "Off")
        enterKeyboardQuery("u+0558")
        let armenian = app.buttons["keyboard.character.U+0558"].firstMatch
        XCTAssertTrue(armenian.waitForExistence(timeout: 10))
        XCTAssertFalse((armenian.value as? String ?? "").contains("Preview font:"))
        XCTAssertEqual(input.value as? String, "")
        attachScreenshot("Keyboard fonts remain independently off despite app setting on")
        selectKeyboardFonts(true)
        XCTAssertTrue(armenian.waitUntilValueEquals("Preview font: GNU Unifont"))
        armenian.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+0558", nameContaining: "Armenian small eh")
        let source = app.staticTexts["keyboard.properties.fontSource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(source), "GNU Unifont")
        XCTAssertEqual(input.value as? String, "", "Font-backed inspection must not insert a preview")
        attachScreenshot("Bundled Armenian glyph inspection preserves original Unicode properties")
        app.buttons["keyboard.properties.close"].tap()
        armenian.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\u{0558}"))
        assertLastItemFontToolbarIsVisible()
        attachScreenshot("Optional font preview inserts the original scalar with intact portrait toolbar")
        closeKeyboardSearch()

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return frame.width > frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        assertLastItemFontToolbarIsVisible()
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
        assertLastItemFontToolbarIsVisible()
        attachScreenshot("Supplementary fallback glyph inserts exact text in compact landscape")
        closeKeyboardSearch()
        keyboardOption("keyboard.inspectLast").tap()
        assertKeyboardProperties(codepoints: "U+10940", nameContaining: "Sidetic letter n01")
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.fontSource"].firstMatch), "GNU Unifont Upper")
        XCTAssertEqual(input.value as? String, "\u{0558}\u{10940}")
        attachScreenshot("Compact Fonts and last-item inspector remain usable after insertion")
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
        assertControlValue("keyboard.unicodeFonts", equals: "On")
        XCTAssertEqual(input.value as? String, "")
        selectKeyboardFonts(false)
        input = openSystemKeyboardHost()
        assertControlValue("keyboard.unicodeFonts", equals: "Off")
        XCTAssertEqual(input.value as? String, "")
        attachScreenshot("Keyboard extra fonts off persists after ordinary host relaunch")
        restoreEnglishKeyboard()
        let back = app.navigationBars["Try Uniboard"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("1"),
                      "Disabling keyboard preview fonts must not change the app preference")
        setAppUnicodeFonts(false)
    }


    func testSystemKeyboardCompactLayoutPreservesVisibleHostAndExactInput() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        normalizeKeyboardBrowseHeight(input: input, context: context)
        selectKeyboardFonts(false)
        assertControlValue("keyboard.unicodeFonts", equals: "Off")
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
        normalizeKeyboardBrowseHeight(input: input, context: context)

        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        attachResizeFrameDiagnostics(input: input)
        XCTAssertTrue(grip.isHittable)
        assertResizeHeight(300)
        assertCompactKeyboardGeometry("resizable.portrait.initial", input: input, searching: false,
                                      expectedSurfaceHeight: 300)
        grip.tap()
        assertResizeHeight(420)
        assertCompactKeyboardGeometry("resizable.portrait.expanded", input: input, searching: false,
                                      expectedSurfaceHeight: 420)
        grip.tap()
        assertResizeHeight(220)
        assertCompactKeyboardGeometry("resizable.portrait.collapsed", input: input, searching: false,
                                      expectedSurfaceHeight: 220)

        // Drag the actual top grip upwards from the compact surface. Read the
        // resulting native value rather than assuming gesture interpolation.
        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: grip.frame.midX, dy: grip.frame.midY - 85))
        start.press(forDuration: 0.2, thenDragTo: end)
        let intermediate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let height = self.keyboardResizeHeight() else { return false }
            return height > 240 && height < 335
        }, object: grip)
        XCTAssertEqual(XCTWaiter.wait(for: [intermediate], timeout: 5), .completed,
                       "Dragging must choose an intermediate browse height within 220–420 points")
        let manualHeight = keyboardResizeHeight() ?? 0
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
        XCTAssertTrue(rocket.waitForExistence(timeout: 5), "Done must retain the filtered result after folding query keys")
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

        // With query keys folded, these controls operate on the real host
        // document even though the query and filtered catalog stay visible.
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
        print("UNIBOARD_RESPONSIVE_FIXTURE version=1.1-audit centerDepth=9 expectedBaseline=300")
        let context = "The host keeps its original text."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        normalizeKeyboardBrowseHeight(input: input, context: context)

        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        attachResizeFrameDiagnostics(input: input)
        assertResizeHeight(300)
        assertResizeGripAtTop(input: input)
        XCTAssertTrue(search.waitUntilValueEquals("No query"))
        attachScreenshot("Crisp native placeholder and grip at the keyboard top")

        // The runner records the complete screen independently. These explicit
        // velocities and wall-clock markers locate each continuous gesture in
        // that recording and the controller's DEBUG resize telemetry. Endpoint
        // During a drag the target preview changes while the host/window stays
        // fixed. The recording and DEBUG samples prove that behavior and the
        // single smooth commit after release; endpoints alone cannot prove it.
        dragKeyboardGrip(deltaY: -120, velocity: 80, label: "slow.expand", input: input, context: context)
        dragKeyboardGrip(deltaY: 120, velocity: 80, label: "slow.contract", input: input, context: context)
        dragKeyboardGrip(deltaY: -100, velocity: 600, label: "fast.expand", input: input, context: context)
        dragKeyboardGrip(deltaY: 100, velocity: 600, label: "fast.contract", input: input, context: context)
        let manualHeight = keyboardResizeHeight() ?? 0

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
        XCTAssertTrue(rocket.isHittable, "Folding must retain the actual filtered result")
        XCTAssertEqual(input.value as? String, context)
        assertResizeGripAtTop(input: input)
        attachScreenshot("Responsive keyboard retains folded rocket search and visible host")
        rocket.tap()
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
        XCTAssertTrue(rocket.isHittable)
        XCTAssertEqual(input.value as? String, context + "🚀")
        attachScreenshot("Responsive keyboard restores its manual height and folded query after rotation")
    }

    func testSystemKeyboardContinuousResizeMotion() throws {
        try requirePhonePortraitResizeIntegration()
        print("UNIBOARD_CONTINUOUS_MOTION_FIXTURE version=1.1-audit centerDepth=9 expectedBaseline=300")
        let context = "Continuous resizing preserves this host text."
        let input = openSystemKeyboardHost(initialText: context)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        normalizeKeyboardBrowseHeight(input: input, context: context)
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        attachResizeFrameDiagnostics(input: input)
        assertResizeHeight(300)
        assertResizeGripAtTop(input: input)
        dragKeyboardGrip(deltaY: -120, velocity: 80, label: "slow.expand", input: input, context: context)
        dragKeyboardGrip(deltaY: 120, velocity: 80, label: "slow.contract", input: input, context: context)
        dragKeyboardGrip(deltaY: -100, velocity: 600, label: "fast.expand", input: input, context: context)
        dragKeyboardGrip(deltaY: 100, velocity: 600, label: "fast.contract", input: input, context: context)
    }

    func testSystemKeyboardManualHeightPersistsAcrossHostRelaunchAndRotation() throws {
        try requirePhonePortraitResizeIntegration()
        let firstContext = "Manual keyboard height belongs to the keyboard."
        var input = openSystemKeyboardHost(initialText: firstContext)
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        normalizeKeyboardBrowseHeight(input: input, context: firstContext)
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        let fixedBottom = grip.frame.minY + 300
        grip.tap()
        assertResizeHeight(420)
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            grip.exists && abs(grip.frame.minY - (fixedBottom - 420)) <= 1
        }, object: grip)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        dragKeyboardGrip(deltaY: 115, velocity: 240, label: "persistence.choose305",
                         input: input, context: firstContext)
        assertResizeHeight(305)
        enterKeyboardQuery("cat")
        closeKeyboardSearch()
        assertResizeHeight(305)
        XCTAssertEqual(input.value as? String, firstContext)

        // This is an actual host termination/relaunch, not a simulated
        // mid-drag cancellation. The extension's own preference must survive
        // the containing app's normal test reset and real keyboard handoff.
        let resumedContext = "A new host session keeps the chosen keyboard height."
        input = openSystemKeyboardHost(initialText: resumedContext)
        assertResizeHeight(305)
        assertCompactKeyboardGeometry("persistent-height.relaunched", input: input, searching: false,
                                      expectedSurfaceHeight: 305)
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("No query"),
                      "A prior session's query is cleared through the visible action before this case uses search")
        settleKeyboardOrientation(.landscapeLeft)
        assertCompactKeyboardGeometry("persistent-height.landscape", input: input, searching: false,
                                      expectedSurfaceHeight: 220)
        settleKeyboardOrientation(.portrait)
        assertResizeHeight(305)
        assertCompactKeyboardGeometry("persistent-height.returned", input: input, searching: false,
                                      expectedSurfaceHeight: 305)
        XCTAssertEqual(input.value as? String, resumedContext)

        // A five-point movement is below pan recognition. This exercises the
        // visible endpoint tap plus a full real drag used to establish a 300-point
        // baseline when another case leaves a nearby persisted preference.
        normalizeKeyboardBrowseHeight(input: input, context: resumedContext)
        assertResizeHeight(300)
        XCTAssertEqual(input.value as? String, resumedContext)
        attachScreenshot("Visible normalization restores the 300-point baseline without changing host text")
    }

    private func dragKeyboardGrip(deltaY: CGFloat, velocity: CGFloat, label: String,
                                  input: XCUIElement, context: String) {
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        let preview = app.descendants(matching: .any)["keyboard.resize.preview"].firstMatch
        let before = keyboardResizeHeight() ?? 0
        XCTAssertFalse(preview.exists, "The target preview must be hidden before a new gesture")
        XCTAssertTrue(grip.isHittable)
        let frame = grip.frame
        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: frame.midX, dy: frame.midY + deltaY))
        let began = Date().timeIntervalSince1970
        print("UNIBOARD_CONTINUOUS_DRAG_BEGIN \(label) epoch=\(began) height=\(before) deltaY=\(deltaY) velocity=\(velocity)")
        start.press(forDuration: 0.15, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: 0.2)
        let finished = Date().timeIntervalSince1970
        let expected = min(420, max(220, CGFloat(before) - deltaY))
        let expectedGripY = frame.minY + CGFloat(before) - expected
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            grip.exists && abs(grip.frame.minY - expectedGripY) <= 1
        }, object: grip)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "The single post-release height animation must settle at the requested position")
        XCTAssertTrue(preview.waitUntilAbsent(), "Releasing the grip must dismiss the target preview")
        let settledEpoch = Date().timeIntervalSince1970
        let after = keyboardResizeHeight() ?? 0
        XCTAssertTrue((220...420).contains(after))
        XCTAssertEqual(CGFloat(after), expected, accuracy: 3,
                       "The final height must track the actual finger displacement without remote-window feedback")
        if deltaY < 0 { XCTAssertGreaterThan(after - before, 40) }
        else { XCTAssertGreaterThan(before - after, 40) }
        XCTAssertLessThanOrEqual(abs(CGFloat(after - before)), abs(deltaY) + 30,
                                 "The resize must follow the finger without amplifying its movement")
        XCTAssertEqual(input.value as? String, context, "Dragging the grip must not insert or delete host text")
        assertResizeHeight(after)
        assertResizeGripAtTop(input: input)
        let value: [String: Any] = ["gesture": label, "beganEpoch": began, "finishedEpoch": finished,
            "requestedDeltaY": deltaY, "velocityPointsPerSecond": velocity,
            "heightBefore": before, "heightAfter": after, "animationSettledEpoch": settledEpoch,
            "previewAbsentAfterRelease": !preview.exists,
            "hostUnchanged": (input.value as? String) == context,
            "motionContract": "Changing target preview and fixed host during drag; one smooth height commit after release",
            "intermediateSmoothnessEvidence": "Independent original screen recording plus complete preview, release and layout DEBUG telemetry"]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Continuous native resize gesture \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("UNIBOARD_CONTINUOUS_DRAG_END " + String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\n", with: ""))
        attachScreenshot("Continuous native resize \(label) preserves the host")
    }

    private func normalizeKeyboardBrowseHeight(input: XCUIElement, context: String) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent())
        guard var height = keyboardResizeHeight() else {
            XCTFail("The real keyboard must report its current browse height")
            return
        }
        XCTAssertTrue((220...420).contains(height))
        guard height != 300 else { return }

        // Preferences belong to the extension, so an app test reset cannot
        // reset them. Establish the baseline through the same visible grip a
        // user operates. A tiny delta cannot recognize a pan; first tap to a
        // distant endpoint rather than accidentally interpreting it as a tap.
        if abs(height - 300) <= 40 {
            let expected = height < 320 ? 420 : 220
            let expectedY = grip.frame.minY + CGFloat(height - expected)
            grip.tap()
            assertResizeHeight(expected)
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                grip.exists && abs(grip.frame.minY - expectedY) <= 1
            }, object: grip)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            height = expected
        }
        print("UNIBOARD_RESIZE_PRECONDITION actualHeight=\(height) targetHeight=300")
        dragKeyboardGrip(deltaY: CGFloat(height - 300), velocity: 240,
                         label: "precondition.normalize", input: input, context: context)
        assertResizeHeight(300)
    }

    private func assertResizeGripAtTop(input: XCUIElement,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        let gripFrame = grip.frame
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch.frame
        let footer = app.buttons["keyboard.return"].firstMatch.frame
        let surfaces = app.otherElements.containing(.any, identifier: "keyboard.search").allElementsBoundByIndex
            .map(\.frame).filter { $0.width > app.frame.width * 0.7 && $0.contains(search)
                && $0.contains(footer) && $0.insetBy(dx: -1, dy: -1).contains(gripFrame) }
            .sorted { $0.height < $1.height }
        XCTAssertEqual(gripFrame.height, 18, accuracy: 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(gripFrame.width, app.frame.width * 0.9, file: file, line: line)
        XCTAssertFalse(surfaces.isEmpty, "Expected the keyboard root containing its native grip", file: file, line: line)
        if let surface = surfaces.first {
            XCTAssertEqual(gripFrame.minY, surface.minY, accuracy: 1,
                           "The grip must begin at the keyboard's top without a blank band", file: file, line: line)
            if let height = keyboardResizeHeight() {
                XCTAssertEqual(surface.height, CGFloat(height), accuracy: 1, file: file, line: line)
            }
        }
        assertHostEditorIsVisibleAboveKeyboard(input, file: file, line: line)
    }

    private func keyboardResizeHeight() -> Int? {
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
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
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let ancestors = app.otherElements.containing(.any, identifier: "keyboard.search").allElementsBoundByIndex
        let value: [String: Any] = ["app": rect(app.frame), "grip": rect(grip.frame),
            "search": rect(search.frame), "hostEditor": rect(input.frame),
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
        let grip = app.descendants(matching: .any)["keyboard.resize"].firstMatch
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
        normalizeKeyboardBrowseHeight(input: input, context: context)
        enterKeyboardQuery("u+2603")
        let snowman = app.buttons["keyboard.character.U+2603"].firstMatch
        XCTAssertTrue(snowman.waitForExistence(timeout: 10))
        snowman.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+2603", nameContaining: "snowman")
        XCTAssertEqual(input.value as? String, context, "Holding inspects the scalar without inserting it")
        assertCompactKeyboardGeometry("portrait.properties", input: input, searching: false, inspecting: true)
        attachScreenshot("Compact glass Unicode properties keep host context visible without insertion")
        app.buttons["keyboard.properties.close"].tap()
        openKeyboardOptions()
        let remove = app.buttons["Remove from favorites"].firstMatch
        if remove.exists {
            remove.tap()
            openKeyboardOptions()
        }
        let save = app.buttons["Save to favorites"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        save.tap()
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
        XCTAssertTrue(app.staticTexts["On this keyboard"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(snowman.waitForExistence(timeout: 5), "The saved scalar must appear in actual Saved content")
        snowman.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "☃"))
        attachScreenshot("Compact Saved section inserts the original saved scalar")
        keyboardOption("keyboard.inspectLast").tap()
        XCTAssertTrue(app.staticTexts["keyboard.properties.name"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+2603")
        XCTAssertEqual(input.value as? String, context + "☃")
        app.buttons["keyboard.properties.close"].tap()
        openKeyboardOptions()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        selectKeyboardEdition("latest")
        selectKeyboardOrder("codepoint")
        selectKeyboardFonts(true)
        selectKeyboardFonts(false)
        selectKeyboardEdition("draft")
        selectKeyboardOrder("newest")
        assertControlValue("keyboard.unicodeFonts", equals: "Off")
        XCTAssertEqual(input.value as? String, context + "☃", "Menus must not enter text into the host")
        selectKeyboardSection("symbols")
        assertCompactKeyboardGeometry("portrait.menus.closed", input: input, searching: false)
    }

    private func settleKeyboardOrientation(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return landscape ? frame.width > frame.height : frame.width < frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5))
    }

    private func assertCompactKeyboardGeometry(_ mode: String, input: XCUIElement, searching: Bool,
                                               inspecting: Bool = false, expectedSurfaceHeight: CGFloat? = nil,
                                               file: StaticString = #filePath, line: UInt = #line) {
        func rect(_ frame: CGRect) -> [String: Double] {
            ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        }
        assertDeleteIsOnlyAtTopRight(file: file, line: line)
        assertKeyboardControlsAreVisible(isSearching: searching, file: file, line: line)
        assertHostEditorIsVisibleAboveKeyboard(input, file: file, line: line)
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch.frame
        let footer = app.buttons["keyboard.return"].firstMatch.frame
        let candidates = app.otherElements.containing(.any, identifier: "keyboard.search").allElementsBoundByIndex
            .map(\.frame).filter { $0.width > app.frame.width * 0.7 && $0.contains(search) && $0.contains(footer) }
            .sorted { $0.height < $1.height }
        let landscape = app.frame.width > app.frame.height
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let maximum: CGFloat = expectedSurfaceHeight ?? (pad ? (searching || inspecting ? 380 : 340)
            : landscape ? 220 : (searching || inspecting ? 340 : 300))
        XCTAssertFalse(candidates.isEmpty, "Expected the actual keyboard surface ancestor", file: file, line: line)
        if let surface = candidates.first {
            XCTAssertLessThanOrEqual(surface.height, maximum + 1, "Keyboard must leave host space instead of reverting to tall chrome", file: file, line: line)
            if let expectedSurfaceHeight {
                XCTAssertEqual(surface.height, expectedSurfaceHeight, accuracy: 1,
                               "The measured keyboard surface must match its reported resize height", file: file, line: line)
            }
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(surface), "Keyboard surface must not extend above or outside the display", file: file, line: line)
        }
        let resize = app.descendants(matching: .any)["keyboard.resize"].firstMatch
        let resizeValue = resize.exists ? resize.value as? String ?? "Unavailable" : "Unavailable"
        let value: [String: Any] = ["mode": mode, "app": rect(app.frame), "hostEditor": rect(input.frame),
            "hostText": input.value as? String ?? "", "hostIsHittable": input.isHittable,
            "surfaceCandidates": candidates.map(rect), "search": rect(search), "footer": rect(footer),
            "visibleControlSpan": footer.maxY - search.minY, "maximumSurfaceHeight": maximum,
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
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        selectKeyboardEdition("draft")
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

    func testSystemKeyboardCatalogChoiceIsLocalAndPersists() throws {
        try requireKeyboardIntegration()
        var input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        selectKeyboardEdition("latest")
        enterKeyboardQuery("u+0378")
        let unassigned = app.buttons["keyboard.character.U+0378"].firstMatch
        XCTAssertTrue(unassigned.waitForExistence(timeout: 10))
        XCTAssertTrue(unassigned.waitUntilLabelHasSuffix(", Unassigned"))
        XCTAssertEqual(input.value as? String, "")
        closeKeyboardSearch()
        selectKeyboardEdition("draft")
        enterKeyboardQuery("u+0041")
        let assigned = app.buttons["keyboard.character.U+0041"].firstMatch
        XCTAssertTrue(assigned.waitForExistence(timeout: 10))
        XCTAssertTrue(assigned.waitUntilLabelHasSuffix(", U1.1"))
        XCTAssertEqual(input.value as? String, "")
        closeKeyboardSearch()
        selectKeyboardEdition("latest")
        attachScreenshot("Extension independently selects the latest Unicode catalog")

        // Relaunching the host creates another keyboard session. The extension
        // must retain its own choice without changing the app's preference.
        input = openSystemKeyboardHost()
        assertControlValue("keyboard.edition", equals: "latest")
        XCTAssertEqual(input.value as? String, "")
        attachScreenshot("Keyboard catalog choice persists into a new host session")
        restoreEnglishKeyboard()
        let back = app.navigationBars["Try Uniboard"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        appTab("Explore").tap()
        assertControlValue("unicodeEdition", equals: "draft")
    }

    func testSystemKeyboardSearchAndInsertion() throws {
        try requireKeyboardIntegration()
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        selectKeyboardOrder("newest")
        assertControlValue("keyboard.order", equals: "newestFirst")
        assertDeleteIsOnlyAtTopRight()
        assertKeyboardControlsAreVisible(isSearching: false)
        attachScreenshot("Single delete key at the top right of the real keyboard")
        enterKeyboardQuery("u+1f680")
        assertDeleteIsOnlyAtTopRight()
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
        assertDeleteIsOnlyAtTopRight()
        assertKeyboardControlsAreVisible(isSearching: false)
        attachScreenshot("Compact landscape keyboard keeps native controls visible")
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        assertDeleteIsOnlyAtTopRight()
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
        let menu = app.descendants(matching: .any)["keyboard.section"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The keyboard section trigger must return after a prior menu closes")
        if menu.value as? String == section { return }
        menu.tap()
        let option = app.descendants(matching: .any)["keyboard.tab.\(section)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        assertControlValue("keyboard.section", equals: section)
    }

    private func openKeyboardOptions() {
        let option = app.descendants(matching: .any)["keyboard.edition"].firstMatch
        if option.exists { return }
        let menu = app.descendants(matching: .any)["keyboard.options"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The keyboard options trigger must return before opening another menu")
        menu.tap()
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The actual options menu must open")
    }

    private func closeKeyboardOptions() {
        let option = app.descendants(matching: .any)["keyboard.edition"].firstMatch
        if option.exists {
            // The toolbar trigger can disappear from AX while its popup is
            // open. Dismiss by tapping the host navigation title, outside the
            // popup and editor, so neither caret nor host contents can change.
            let navigation = app.navigationBars["Try Uniboard"].firstMatch
            XCTAssertTrue(navigation.waitForExistence(timeout: 5))
            navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(option.waitUntilAbsent())
        }
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.options"].firstMatch.waitForExistence(timeout: 5))
    }

    private func keyboardOption(_ identifier: String) -> XCUIElement {
        openKeyboardOptions()
        var item = app.descendants(matching: .any)[identifier].firstMatch
        if identifier == "keyboard.inspectLast", !item.waitForExistence(timeout: 2) {
            // iOS 27's native Menu can omit the identifier on this dynamic
            // action while retaining its real, actionable button label.
            item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Inspect ")).firstMatch
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Expected keyboard option \(identifier): \(app.debugDescription)")
        if identifier == "keyboard.inspectLast" {
            let menu = app.collectionViews.containing(.button, identifier: "keyboard.edition").firstMatch
            for _ in 0..<3 {
                guard menu.exists else { break }
                if isInsideScrollViewport(item, in: menu) { break }
                menu.swipeUp()
            }
            XCTAssertTrue(isInsideScrollViewport(item, in: menu), "The actual Inspect action must be reachable in its native menu")
        }
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
        appTab("Setup").tap()
        XCTAssertTrue(app.navigationBars["Set up Uniboard"].firstMatch.waitForExistence(timeout: 5))
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

    private func selectKeyboardFonts(_ enabled: Bool) {
        let menu = keyboardOption("keyboard.unicodeFonts")
        menu.tap()
        let option = app.descendants(matching: .any)["keyboard.unicodeFonts.\(enabled ? "on" : "off")"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        assertControlValue("keyboard.unicodeFonts", equals: enabled ? "On" : "Off")
    }

    private func assertLastItemFontToolbarIsVisible(file: StaticString = #filePath, line: UInt = #line) {
        let favorite = app.buttons.matching(NSPredicate(format: "label IN %@",
            ["Save to favorites", "Remove from favorites"])).firstMatch
        openKeyboardOptions()
        defer { closeKeyboardOptions() }
        let controls = [app.descendants(matching: .any)["keyboard.unicodeFonts"].firstMatch,
                        app.descendants(matching: .any)["keyboard.inspectLast"].firstMatch, favorite]
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Expected Fonts, Inspect and Save after insertion", file: file, line: line)
            XCTAssertTrue(control.isHittable, file: file, line: line)
            let frame = control.frame
            XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0,
                          "Last-item toolbar control has an invalid frame", file: file, line: line)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame),
                          "Last-item toolbar control must not be clipped: \(frame)", file: file, line: line)
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

    private func openSystemKeyboardHost(initialText: String = "") -> XCUIElement {
        enableUniboardInSettings()
        // Reload UIKit's enabled-keyboard configuration after changing it in
        // Settings, and start from a settled foreground navigation state.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let setup = appTab("Setup")
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        let setupPage = app.navigationBars["Set up Uniboard"].firstMatch
        for _ in 0..<3 {
            setup.tap()
            if setupPage.waitForExistence(timeout: 2) { break }
        }
        // iPad's sidebar button opens the page without reporting a selected
        // trait. Verify the destination itself before opening its host editor.
        XCTAssertTrue(setupPage.exists, "Setup must be open before opening the keyboard host: \(app.debugDescription)")
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
        selectUniboardKeyboard()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 10),
            "Expected the real Uniboard keyboard extension: \(app.debugDescription)")
        XCTAssertEqual(input.value as? String, initialText)
        if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
        selectKeyboardSection("symbols")
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        if let retainedQuery = search.value as? String, retainedQuery != "No query", !retainedQuery.isEmpty {
            let clear = app.buttons["keyboard.search.clear"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            clear.tap()
            XCTAssertTrue(search.waitUntilValueEquals("No query"))
            XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(),
                          "Clearing a prior folded query must keep browsing active")
            XCTAssertEqual(input.value as? String, initialText,
                           "Visible query cleanup must not alter the seeded host document")
        }
        return input
    }

    private func enterKeyboardQuery(_ query: String) {
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
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitUntilValueEquals(expectedQuery), "Reopening must preserve the existing query")
    }

    private func closeKeyboardSearch() {
        app.buttons["keyboard.return"].tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent())
    }

    private func restoreEnglishKeyboard() {
        let propertiesClose = app.buttons["keyboard.properties.close"].firstMatch
        if propertiesClose.exists { propertiesClose.tap() }
        if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
        let extensionGlobe = app.buttons["keyboard.globe"].firstMatch
        let globe = extensionGlobe.exists ? extensionGlobe : app.buttons["Next keyboard"].firstMatch
        if globe.exists {
            globe.press(forDuration: 1)
            let english = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "English")).firstMatch
            if english.waitForExistence(timeout: 3) { english.tap() }
        }
    }

    private func assertDeleteIsOnlyAtTopRight(file: StaticString = #filePath, line: UInt = #line) {
        let deletes = app.buttons.matching(identifier: "keyboard.delete")
        XCTAssertEqual(deletes.count, 1, "There must be one delete key, with no duplicate bottom control", file: file, line: line)
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
        var identifiers = ["keyboard.search", "keyboard.delete", "keyboard.section", "keyboard.options",
                           "keyboard.space", "keyboard.return"]
        if isSearching { identifiers += ["keyboard.query.q", "keyboard.query.p", "keyboard.query.u"] }
        let screen = app.frame.insetBy(dx: -1, dy: -1)
        for identifier in identifiers {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Expected keyboard control \(identifier)", file: file, line: line)
            XCTAssertTrue(control.isHittable, "Keyboard control \(identifier) must remain tappable", file: file, line: line)
            let frame = control.frame
            XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0,
                          "Keyboard control \(identifier) must have a finite visible frame", file: file, line: line)
            XCTAssertTrue(screen.contains(frame), "Keyboard control \(identifier) is clipped outside the screen: \(frame)", file: file, line: line)
        }
    }

    private func assertHostEditorIsVisibleAboveKeyboard(_ input: XCUIElement,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        let frame = input.frame
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(input.isHittable, "The native host editor must remain tappable", file: file, line: line)
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height >= 44,
                      "The host needs a visible editing area, not a collapsed frame: \(frame)", file: file, line: line)
        XCTAssertTrue(app.frame.contains(frame), "The host editor must remain inside the display", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, search.frame.minY,
                                 "The native keyboard must leave the entire editor visible above its search header", file: file, line: line)
    }

    private func selectKeyboardEdition(_ edition: String) {
        let selector = keyboardOption("keyboard.edition")
        selector.tap()
        let option = app.descendants(matching: .any)["keyboard.edition.\(edition)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        assertControlValue("keyboard.edition", equals: edition)
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
        for _ in 0..<6 {
            if isInsideScrollViewport(propertyName, in: propertyScroll)
                && isInsideScrollViewport(points, in: propertyScroll) { break }
            propertyScroll.swipeDown()
        }
        XCTAssertTrue(isInsideScrollViewport(propertyName, in: propertyScroll), "The inspector must return to its name after scrolling through all properties")
        XCTAssertTrue(isInsideScrollViewport(points, in: propertyScroll))
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

    private func selectAppEdition(_ edition: String) {
        let selector = app.descendants(matching: .any)["unicodeEdition"].firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()
        let option = app.descendants(matching: .any)["edition.\(edition)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected catalog edition option \(edition)")
        attachScreenshot("Offline catalog menu offers latest release and development draft")
        option.tap()
        assertControlValue("unicodeEdition", equals: edition)
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
        let optionFields = ["keyboard.edition": 0, "keyboard.order": 1, "keyboard.unicodeFonts": 2]
        if let index = optionFields[identifier] {
            // Selection dismisses the native submenu before the extension
            // toolbar reappears. Its brief absence must not choose a fallback
            // query for the submenu that has just closed.
            let options = app.descendants(matching: .any)["keyboard.options"].firstMatch
            XCTAssertTrue(options.waitForExistence(timeout: 5), "Expected the visible options summary after selecting \(identifier)")
            let predicate = NSPredicate { element, _ in
                guard let element = element as? XCUIElement, let value = element.value as? String else { return false }
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.indices.contains(index) else { return false }
                return index == 2 ? parts[index] == "extra fonts \(expected.lowercased())" : parts[index] == expected
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: options)], timeout: 5), .completed,
                           "Expected \(identifier)=\(expected) in the visible options summary, got \(accessibleText(options))")
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
            if element.exists && element.isHittable { return }
            application.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected a visible settings or setup control: \(application.debugDescription)")
        XCTAssertTrue(element.isHittable)
    }

    private func selectUniboardKeyboard() {
        if app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 2) { return }
        let keyboard = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Uniboard")).firstMatch
        for _ in 0..<2 {
            let globe = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5), "Expected the system keyboard globe key: \(app.debugDescription)")
            globe.press(forDuration: 1)
            if dismissKeyboardSwitcherTipIfPresent() { continue }
            if keyboard.waitForExistence(timeout: 3) {
                keyboard.tap()
                return
            }
            break
        }
        // iPad can dismiss the native mode picker when a long press releases.
        // Cycle its real system key instead; the extension identifier remains
        // required before any insertion or layout assertion can run.
        for _ in 0..<6 {
            dismissKeyboardSwitcherTipIfPresent()
            if app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 1) { return }
            let next = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 3), "Expected the native input-mode switch key: \(app.debugDescription)")
            next.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5),
                      "Expected the installed Uniboard extension after native keyboard switching: \(app.debugDescription)")
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
