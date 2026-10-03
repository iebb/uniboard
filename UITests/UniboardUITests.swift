import XCTest

@MainActor
final class UniboardUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
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
        assertControlValue("keyboard.order", equals: "newestFirst")
        assertDeleteIsOnlyAtTopRight()
        attachScreenshot("Single delete key at the top right of the real keyboard")
        enterKeyboardQuery("u+1f680")
        assertDeleteIsOnlyAtTopRight()
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
        app.buttons["keyboard.tab.emojis"].tap()
        reopenKeyboardSearch(expectedQuery: "u+1f680")
        XCTAssertTrue(app.buttons["keyboard.emoji.1F680"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "🚀", "Changing the result kind must not insert text")
        closeKeyboardSearch()
        app.buttons["keyboard.tab.symbols"].tap()
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
        let emojis = app.buttons["keyboard.tab.emojis"].firstMatch
        XCTAssertTrue(emojis.waitForExistence(timeout: 5))
        emojis.tap()
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

    private func appTab(_ title: String) -> XCUIElement {
        // iPhone retains the classic TabBar. iPadOS 27 exposes each floating
        // tab as a _UIFloatingTabBarItemCell with the same exact visible label.
        let legacy = app.tabBars.buttons[title].firstMatch
        if legacy.exists { return legacy }
        let floating = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if floating.exists { return floating }
        return app.buttons[title].firstMatch
    }

    private func requireKeyboardIntegration() throws {
        let enabled = ProcessInfo.processInfo.environment["UNIBOARD_KEYBOARD_INTEGRATION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--keyboard-integration")
        try XCTSkipUnless(enabled, "Set UNIBOARD_KEYBOARD_INTEGRATION=1 in the UI test runner to exercise the installed system keyboard.")
    }

    private func openSystemKeyboardHost() -> XCUIElement {
        enableUniboardInSettings()
        // Reload UIKit's enabled-keyboard configuration after changing it in
        // Settings, and start from a settled foreground navigation state.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let setup = appTab("Setup")
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            setup.tap()
            if setup.waitUntilSelected(timeout: 2) { break }
        }
        XCTAssertTrue(setup.isSelected, "Setup must be selected before opening the keyboard host: \(app.debugDescription)")
        let tryKeyboard = app.descendants(matching: .any)["tryKeyboard"].firstMatch
        revealByScrolling(tryKeyboard, in: app)
        tryKeyboard.tap()
        let input = app.textViews["keyboardTestInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        selectUniboardKeyboard()
        XCTAssertTrue(app.buttons["keyboard.search"].firstMatch.waitForExistence(timeout: 10),
            "Expected the real Uniboard keyboard extension: \(app.debugDescription)")
        XCTAssertEqual(input.value as? String, "")
        if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
        let symbols = app.buttons["keyboard.tab.symbols"].firstMatch
        XCTAssertTrue(symbols.waitForExistence(timeout: 5))
        symbols.tap()
        return input
    }

    private func enterKeyboardQuery(_ query: String) {
        let search = app.buttons["keyboard.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        attachScreenshot("System keyboard before search")
        search.tap()
        let firstQueryKey = app.buttons["keyboard.query.u"].firstMatch
        let didOpenSearch = firstQueryKey.waitForExistence(timeout: 5)
        attachScreenshot("System keyboard after opening search")
        XCTAssertTrue(didOpenSearch, "Search should show extension query keys: \(app.debugDescription)")
        if let oldQuery = search.value as? String, oldQuery != "No query" {
            for _ in oldQuery { app.buttons["keyboard.delete"].tap() }
        }
        for key in query {
            let id = key == " " ? "keyboard.space" : "keyboard.query.\(key)"
            let queryKey = app.buttons[id].firstMatch
            XCTAssertTrue(queryKey.waitForExistence(timeout: 5), "Expected query key \(key): \(app.debugDescription)")
            queryKey.tap()
        }
        XCTAssertTrue(search.waitUntilValueEquals(query), "The visible keyboard search query should match its keys")
    }

    private func reopenKeyboardSearch(expectedQuery: String) {
        let search = app.buttons["keyboard.search"].firstMatch
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
        let search = app.buttons["keyboard.search"].firstMatch
        let space = app.buttons["keyboard.space"].firstMatch
        XCTAssertLessThanOrEqual(abs(delete.frame.midY - search.frame.midY), 18,
            "Delete should align with the top search header", file: file, line: line)
        XCTAssertGreaterThan(delete.frame.midX, app.frame.minX + app.frame.width * 0.8,
            "Delete should be on the right edge of the keyboard", file: file, line: line)
        XCTAssertGreaterThan(delete.frame.midX, search.frame.midX, file: file, line: line)
        XCTAssertLessThan(delete.frame.maxY, space.frame.minY,
            "Delete must be above the character and bottom-control areas", file: file, line: line)
    }

    private func selectKeyboardEdition(_ edition: String) {
        let selector = app.descendants(matching: .any)["keyboard.edition"].firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
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
        let lastProperty = app.staticTexts["keyboard.properties.decomposition"].firstMatch
        let propertyScroll = app.scrollViews.containing(.staticText, identifier: "keyboard.properties.description").firstMatch
        XCTAssertTrue(propertyScroll.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if lastProperty.isHittable { break }
            propertyScroll.swipeUp()
        }
        XCTAssertTrue(lastProperty.isHittable, "The full properties must remain reachable inside the keyboard's scroll area")
        attachScreenshot("Complete Unicode properties remain reachable in the keyboard")
        for _ in 0..<6 {
            if propertyName.isHittable && points.isHittable { break }
            propertyScroll.swipeDown()
        }
        XCTAssertTrue(propertyName.isHittable)
        XCTAssertTrue(points.isHittable)
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
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
        if app.buttons["keyboard.search"].firstMatch.waitForExistence(timeout: 2) { return }
        let globe = app.buttons["Next keyboard"].firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 5), "Expected the system keyboard globe key: \(app.debugDescription)")
        globe.press(forDuration: 1)

        let keyboard = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Uniboard")).firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Expected Uniboard in the system input-mode menu: \(app.debugDescription)")
        keyboard.tap()
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
