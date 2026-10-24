import XCTest
import UIKit

/// Pages, the Star page, Favorites and Saved, in the app and the keyboard.
@MainActor
final class PagesUITests: UniboardUITestCase {
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

        openAppFavorites()
        let savedList = app.buttons["page.list"].firstMatch
        XCTAssertTrue(savedList.waitForExistence(timeout: 5))
        savedList.tap()
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

    func testPagesAreConfiguredInTheAppWithKeysVariantsAndTheStarPage() {
        deleteAppPages(named: "qaone")
        addTeardownBlock { @MainActor [self] in deleteAppPages(named: "qaone") }
        let page = createAppPage("qaone")
        addAppPageKey(query: "infinity", codepoint: "U+221E")
        let key = app.buttons["arrange.0.0"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertEqual(key.value as? String, "U+221E")
        addAppPageKeyHoldChoice(key, query: "almost equal to", codepoint: "U+2248")
        attachScreenshot("A page key's hold choices are edited on the page")
        key.tap()
        let star = app.switches["page.star"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        tapSwitch(star)
        XCTAssertTrue(star.waitUntilValueEquals("1"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(page.waitUntilValueEquals("Opens with ★"), "\(String(describing: page.value))")
        attachScreenshot("Pages lists Favorites, Symbols and custom pages in keyboard order")
        deleteAppPage(page)
        let favorites = app.buttons["pages.page.migrated-favorites"].firstMatch
        XCTAssertTrue(favorites.waitUntilValueEquals("Opens with ★"), "Deleting the Star page returns ★ to Favorites")
    }

    func testPagesArrangeKeysIntoRowsWithHalfAndFullGaps() {
        deleteAppPages(named: "qarows")
        addTeardownBlock { @MainActor [self] in deleteAppPages(named: "qarows") }
        _ = createAppPage("qarows")
        for (query, codepoint) in [("infinity", "U+221E"), ("almost equal to", "U+2248"), ("n-ary summation", "U+2211")] {
            addAppPageKey(query: query, codepoint: codepoint)
        }
        openArrange()
        let tile = { (row: Int, index: Int) in self.app.buttons["arrange.\(row).\(index)"].firstMatch }
        XCTAssertEqual(tile(0, 2).label, "Key ∑", "Without rows of its own a page fills rows of ten")
        tile(0, 0).tap()
        XCTAssertFalse(app.buttons["arrange.newRow"].isEnabled, "A row cannot break before its first key")
        tile(0, 1).tap()
        app.buttons["arrange.newRow"].tap()
        XCTAssertTrue(tile(1, 0).waitForExistence(timeout: 5))
        XCTAssertEqual(tile(1, 0).label, "Key ≈")
        app.buttons["arrange.halfGap"].tap()
        XCTAssertTrue(tile(1, 0).waitUntilLabelEquals("Half-width gap"))
        XCTAssertEqual(tile(1, 1).label, "Key ≈")
        tile(1, 2).tap()
        app.buttons["arrange.gap"].tap()
        XCTAssertTrue(tile(1, 2).waitUntilLabelEquals("Full-width gap"))
        XCTAssertEqual(tile(1, 3).label, "Key ∑")
        app.buttons["arrange.left"].tap()
        XCTAssertTrue(tile(1, 1).waitUntilLabelEquals("Full-width gap"), "A selected gap moves left past a key")
        XCTAssertEqual(tile(1, 2).label, "Key ≈")
        app.buttons["arrange.remove"].tap()
        XCTAssertTrue(tile(1, 1).waitUntilLabelEquals("Key ≈"))
        tile(1, 2).tap()
        app.buttons["arrange.up"].tap()
        XCTAssertTrue(tile(0, 1).waitUntilLabelEquals("Key ∑"), "Moving a key up takes it to the row above")
        attachScreenshot("A page arranged into rows with a half-width gap")
        app.buttons["page.more"].firstMatch.tap()
        app.buttons["arrange.reset"].firstMatch.tap()
        XCTAssertTrue(tile(0, 2).waitUntilLabelEquals("Key ≈"))
        XCTAssertFalse(tile(1, 0).exists)
    }

    /// Holding a key lifts it; dropping it on another puts it before that one,
    /// and letting go outside the canvas leaves the page as it was.
    func testPagesDragAKeyBeforeAnotherAndCancelKeepsTheOrder() {
        deleteAppPages(named: "qadrag")
        addTeardownBlock { @MainActor [self] in deleteAppPages(named: "qadrag") }
        let page = createAppPage("qadrag")
        for (query, codepoint) in [("infinity", "U+221E"), ("almost equal to", "U+2248"), ("n-ary summation", "U+2211")] {
            addAppPageKey(query: query, codepoint: codepoint)
        }
        openArrange()
        let tile = { (row: Int, index: Int) in self.app.buttons["arrange.\(row).\(index)"].firstMatch }
        XCTAssertTrue(tile(0, 2).waitUntilLabelEquals("Key ∑"))
        XCTAssertEqual(tile(0, 0).label, "Key ∞")

        tile(0, 0).press(forDuration: 1, thenDragTo: app.navigationBars.firstMatch, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(tile(0, 0).waitUntilLabelEquals("Key ∞"), "Dropped outside, nothing moves")
        XCTAssertEqual(tile(0, 1).label, "Key ≈")
        XCTAssertEqual(tile(0, 2).label, "Key ∑")
        XCTAssertFalse(app.staticTexts["arrange.error"].exists)

        tile(0, 0).press(forDuration: 1, thenDragTo: tile(0, 2), withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(tile(0, 1).waitUntilLabelEquals("Key ∞"), "∞ lands before ∑, not in its place")
        XCTAssertEqual(tile(0, 0).label, "Key ≈")
        XCTAssertEqual(tile(0, 2).label, "Key ∑")
        XCTAssertFalse(tile(0, 3).exists, "No key is duplicated")
        attachScreenshot("A page key dragged before another")

        // The move was saved once: it is still there after leaving and reopening the page.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
        openArrange()
        XCTAssertTrue(tile(0, 1).waitUntilLabelEquals("Key ∞"))
        XCTAssertEqual(tile(0, 0).label, "Key ≈")
    }

    func testTextAndEmojiFormsShowSideBySideAndJoinAPageSeparately() {
        searchUnicode("snowman")
        assertCharacterVisible("U+2603").tap()
        XCTAssertTrue(app.descendants(matching: .any)["characterGlyph"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["characterGlyph.emoji"].firstMatch.exists, "Both presentations show")
        XCTAssertTrue(app.buttons["copyTextPresentation"].exists)
        XCTAssertTrue(app.buttons["copyEmojiPresentation"].exists)
        attachScreenshot("Snowman text and emoji presentations side by side")
        app.buttons["Done"].tap()
        deleteAppPages(named: "qaforms")
        addTeardownBlock { @MainActor [self] in deleteAppPages(named: "qaforms") }
        _ = createAppPage("qaforms")
        addSnowmanPresentations()
        XCTAssertTrue(app.buttons["arrange.0.0"].firstMatch.waitUntilValueEquals("U+2603 U+FE0E"))
        XCTAssertEqual(app.buttons["arrange.0.1"].firstMatch.value as? String, "U+2603 U+FE0F", "Both forms are separate keys")
        attachScreenshot("A page holds the text and emoji snowman as two keys")
    }

    func testSystemKeyboardPageInsertsTextAndEmojiFormsExactly() throws {
        try requirePhoneKeyboardIntegration()
        deleteAppPages(named: "qaforms")
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); deleteAppPages(named: "qaforms") }
        _ = createAppPage("qaforms")
        addSnowmanPresentations()
        let star = app.switches["page.star"].firstMatch
        revealByScrolling(star, in: app)
        tapSwitch(star)
        XCTAssertTrue(star.waitUntilValueEquals("1"))
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        app.buttons["keyboard.openFavorites"].firstMatch.tap()
        XCTAssertTrue(app.buttons["qaforms"].firstMatch.waitUntilSelected())
        let text = symbolBoardKey("☃\u{FE0E}"), emoji = symbolBoardKey("☃\u{FE0F}")
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(emoji.exists, "Both forms are keys of their own")
        text.tap()
        emoji.tap()
        XCTAssertTrue(input.waitUntilValueEquals("☃\u{FE0E}☃\u{FE0F}"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value), [0x2603, 0xFE0E, 0x2603, 0xFE0F],
                       "Each key inserts its exact presentation sequence")
        chooseHeldKeyboardOption(text, optionCount: 2, selectedIndex: 1)
        XCTAssertTrue(input.waitUntilValueEquals("☃\u{FE0E}☃\u{FE0F}☃\u{FE0F}"), "Holding a text-form key offers the emoji form")
        attachScreenshot("The keyboard page holds the text and emoji snowman")
    }

    func testSystemKeyboardDrawsAppArrangedRowsAndGaps() throws {
        try requirePhoneKeyboardIntegration()
        deleteAppPages(named: "qarows")
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); deleteAppPages(named: "qarows") }
        _ = createAppPage("qarows")
        for (query, codepoint) in [("infinity", "U+221E"), ("almost equal to", "U+2248"), ("n-ary summation", "U+2211")] {
            addAppPageKey(query: query, codepoint: codepoint)
        }
        let star = app.switches["page.star"].firstMatch
        revealByScrolling(star, in: app)
        tapSwitch(star)
        XCTAssertTrue(star.waitUntilValueEquals("1"))
        openArrange()
        app.buttons["arrange.0.1"].firstMatch.tap()
        app.buttons["arrange.newRow"].tap()
        app.buttons["arrange.halfGap"].tap()
        XCTAssertTrue(app.buttons["arrange.1.0"].firstMatch.waitUntilLabelEquals("Half-width gap"))
        _ = openSystemKeyboardHost(initialText: "Rows ", unicodeBrowse: false)
        app.buttons["keyboard.openFavorites"].firstMatch.tap()
        XCTAssertTrue(app.buttons["qarows"].firstMatch.waitUntilSelected(), "★ opens the arranged page")
        let infinity = symbolBoardKey("∞"), almostEqual = symbolBoardKey("≈"), sum = symbolBoardKey("∑")
        XCTAssertTrue(almostEqual.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(almostEqual.frame.minY, infinity.frame.maxY, "The second key starts the next row")
        XCTAssertEqual(almostEqual.frame.minX - infinity.frame.minX, (infinity.frame.width + 5) / 2, accuracy: 1,
                       "A half-width gap indents the row by half a key")
        XCTAssertEqual(sum.frame.minY, almostEqual.frame.minY, accuracy: 1)
        XCTAssertEqual(almostEqual.frame.width, infinity.frame.width, accuracy: 0.5)
        attachScreenshot("The keyboard draws the page's rows and half-width gap")
    }

    func testSystemKeyboardListsAppConfiguredPagesAndKeepsTheStarPage() throws {
        try requirePhoneKeyboardIntegration()
        deleteAppPages(named: "qaone")
        let page = createAppPage("qaone")
        addAppPageKey(query: "infinity", codepoint: "U+221E")
        let key = app.buttons["arrange.0.0"].firstMatch
        addAppPageKeyHoldChoice(key, query: "almost equal to", codepoint: "U+2248")
        key.tap()
        let star = app.switches["page.star"].firstMatch
        tapSwitch(star)
        XCTAssertTrue(star.waitUntilValueEquals("1"))
        addTeardownBlock { @MainActor [self] in deleteAppPages(named: "qaone") }
        _ = page
        let context = "Pages come from the app."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        let starKey = app.buttons["keyboard.openFavorites"].firstMatch
        starKey.tap()
        XCTAssertTrue(app.buttons["qaone"].firstMatch.waitUntilSelected(), "★ opens the page the app marked")
        let infinity = symbolBoardKey("∞")
        XCTAssertTrue(infinity.waitForExistence(timeout: 5))
        chooseHeldKeyboardOption(infinity, optionCount: 2, selectedIndex: 1)
        XCTAssertTrue(input.waitUntilValueEquals(context + "≈"), "Holding a page key offers its app-configured variants")
        // The page menu drops down over the keyboard instead of a separate screen.
        app.buttons["keyboard.boards.open"].firstMatch.tap()
        let favorites = app.buttons.matching(NSPredicate(format: "label == %@", "Favorites")).element(boundBy: 1)
        // The menu opens in the keyboard extension, which the host's idle wait does not cover: wait for each menu copy.
        for name in ["Symbols", "Favorites", "Recent"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", name)).element(boundBy: 1).waitForExistence(timeout: 5), "The menu lists \(name)")
        }
        attachScreenshot("The keyboard's page menu opens pages configured in the app")
        favorites.tap()
        XCTAssertTrue(app.buttons["Favorites"].firstMatch.waitUntilSelected())
        starKey.tap()
        assertHostTypingPanel()
        starKey.tap()
        XCTAssertTrue(app.buttons["qaone"].firstMatch.waitUntilSelected(), "Opening another page keeps the Star page")
        XCTAssertEqual(input.value as? String, context + "≈")
    }

    func testSystemKeyboardFavoritesKeyPreservesQueryCaretAndExactHost() throws {
        try requirePhoneKeyboardIntegration()
        let context = "Favorites preserve this host."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, afterSetUpLaunch: true)
        defer {
            XCUIDevice.shared.orientation = .portrait
            restoreEnglishKeyboard()
        }
        selectSymbolBoard("migrated-favorites", input: input, context: context, returnToTyping: true)
        let favoriteKey = app.buttons["keyboard.openFavorites"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let favorites = app.buttons["Favorites"].firstMatch
        let recent = app.buttons["Recent"].firstMatch
        let originalHeight = measuredKeyboardHeight()
        XCTAssertNotNil(originalHeight)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        favoriteKey.tap()
        XCTAssertTrue(favorites.waitUntilSelected())
        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        XCTAssertEqual(favoriteKey.label, "Back to English keyboard")
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.section"].firstMatch.exists, "The toolbar stays hidden")
        XCTAssertFalse(search.exists, "Pages keep the toolbar hidden, as typing had it")
        XCTAssertEqual(input.value as? String, context)
        // Pages count as browsing, which shows two more rows (since ba91faf); keys keep their height.
        if let originalHeight {
            XCTAssertEqual(Double(measuredKeyboardHeight() ?? 0), Double(originalHeight) + 2 * 41.4, accuracy: 1)
        }
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
        // ★ has no text/emoji presentation forms, so search lists it as one
        // character key (U+2603 now lists two presentation items).
        openUnicodeBrowse()
        enterKeyboardQuery("u+2605")
        let blackStar = app.buttons["keyboard.character.U+2605"].firstMatch
        XCTAssertTrue(blackStar.waitForExistence(timeout: 10))
        blackStar.press(forDuration: 1)
        saveInspectedTextToFavorites(input: input, context: context)
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
        let savedStar = symbolBoardKey("★")
        XCTAssertTrue(savedStar.waitForExistence(timeout: 5))
        let savedScroll = app.scrollViews.containing(.button, identifier: savedStar.identifier).firstMatch
        XCTAssertTrue(savedScroll.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if savedStar.exists, savedScroll.frame.intersection(app.frame).contains(savedStar.frame), savedStar.isHittable { break }
            savedScroll.swipeUp()
        }
        XCTAssertTrue(savedStar.exists)
        XCTAssertTrue(savedScroll.frame.intersection(app.frame).contains(savedStar.frame))
        XCTAssertTrue(savedStar.isHittable)
        XCTAssertEqual(savedStar.frame.height, 41.4, accuracy: 1)
        let savedCapFrame = savedStar.frame
        savedStar.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "★"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map(\.value),
                       context.unicodeScalars.map(\.value) + [0x2605])
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"))
        attachScreenshot("Direct Favorites inserts the saved star without editing the retained query")
        recent.tap()
        XCTAssertTrue(recent.waitUntilSelected())
        let recentStar = app.buttons.matching(identifier: "keyboard.character.U+2605").firstMatch
        XCTAssertTrue(recentStar.waitForExistence(timeout: 5))
        let recentGrid = app.scrollViews.containing(.button, identifier: "keyboard.character.U+2605").firstMatch
        XCTAssertTrue(recentGrid.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            let viewport = recentGrid.frame.intersection(app.frame)
            guard usableHeightFrame(viewport) else { XCTFail("Expected the actual Recent viewport"); return }
            let frame = recentStar.exists ? recentStar.frame : .null
            if usableHeightFrame(frame), viewport.contains(frame), recentStar.isHittable { break }
            let downward = usableHeightFrame(frame) && frame.minY < viewport.minY
            let start = recentGrid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let finish = start.withOffset(CGVector(dx: 0, dy: min(44, viewport.height * 0.3) * (downward ? 1 : -1)))
            start.press(forDuration: 0.1, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(recentStar.exists && usableHeightFrame(recentStar.frame)
            && recentGrid.frame.intersection(app.frame).contains(recentStar.frame))
        assertRecentKeycaps(in: recentGrid, referenceWidth: savedCapFrame.width)
        assertKeyboardCharacterIsFullyVisible(recentStar, identifier: "keyboard.character.U+2605")
        XCTAssertTrue(recentStar.isHittable)
        attachScreenshot("Recent uses the same rounded glyph-only number-width keycaps and screen margins")
        recentStar.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "★★"))
        app.buttons["keyboard.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "★"))
        recentStar.press(forDuration: 1)
        let recentName = app.staticTexts["keyboard.properties.name"].firstMatch
        XCTAssertTrue(recentName.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(recentName).localizedCaseInsensitiveContains("black star"))
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+2605")
        XCTAssertEqual(input.value as? String, context + "★", "Holding a Recent key inspects without inserting")
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
        XCTAssertEqual(input.value as? String, context + "★")
        assertLowerDeleteInKeyRow("keyboard.query.delete", beside: "keyboard.query.-")
        app.buttons["keyboard.query.delete"].tap()
        XCTAssertTrue(search.waitUntilValueEquals("arrow cat"), "The lower query delete must preserve the suffix at the retained middle caret")
        XCTAssertEqual(input.value as? String, context + "★", "The lower query delete must not touch the host")
        typeKeyboardQueryKeys("x")
        XCTAssertTrue(search.waitUntilValueEquals("arrow xcat"))
        closeKeyboardSearch()
        assertHostTypingPanel()
        assertRetainedKeyboardQuery("arrow xcat")


        assertFavoritesKeyImmediatelyPrecedesSpace()
        assertLowerDeleteInKeyRow("keyboard.typing.delete", beside: "keyboard.typing.key.m")
        favoriteKey.tap()
        XCTAssertTrue(favorites.waitUntilSelected())

        assertFavoritesKeyImmediatelyPrecedesSpace()
        attachScreenshot("Favorites and Space remain contained at the minimum portrait height")
        settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false)
        // The landscape template (278.4 with the toolbar) without the hidden
        // toolbar row, plus the two rows pages add while browsing (ba91faf).
        assertCompactKeyboardGeometry("favorites.landscape", input: input, searching: false, expectedSurfaceHeight: 278.4 - 41.4 + 2 * 41.4)
        assertFavoritesKeyImmediatelyPrecedesSpace()
        // Pages keep the toolbar hidden; the query is checked with U once typing returns.
        XCTAssertFalse(search.exists, "Pages keep the toolbar hidden, as typing had it")
        XCTAssertEqual(input.value as? String, context + "★")
        settleKeyboardOrientation(.portrait, toolbarVisible: false)

        XCTAssertTrue(favoriteKey.waitUntilValueEquals("favorites"))
        favoriteKey.tap()
        assertHostTypingPanel()
        assertRetainedKeyboardQuery("arrow xcat", "Rotation and Favorites keep the retained query")
        XCTAssertEqual(input.value as? String, context + "★")
    }

    func testSystemKeyboardFavoritesSyncWithSavedAndKeepHostLiteral() throws {
        try requirePhoneKeyboardIntegration()
        setKeyboardFullAccess(false)
        // Reload UIKit's keyboard configuration after the Settings change.
        app.terminate()
        app.launch()
        var input: XCUIElement
        defer { restoreEnglishKeyboard(); setKeyboardFullAccess(false); app.activate() }
        selectAppTab("Explore")
        searchUnicode("u+2603")
        assertCharacterVisible("U+2603").tap()
        let favorite = app.buttons["toggleFavorite"].firstMatch
        revealByScrolling(favorite, in: app)
        XCTAssertEqual(favorite.label, "Add to favorites")
        favorite.tap()
        XCTAssertTrue(favorite.waitUntilLabelEquals("Remove from favorites"))
        app.buttons["Done"].tap()
        openAppSavedFavorites()
        XCTAssertTrue(app.otherElements["savedFavorites"].buttons["character-U+2603"].firstMatch.waitForExistence(timeout: 5))
        func reopenHost() -> XCUIElement {
            selectAppTab("Settings")
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
        openAppSavedFavorites()
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
        openAppSavedFavorites()
        XCTAssertTrue(app.otherElements["savedFavorites"].buttons["character-U+2665"].firstMatch.waitForExistence(timeout: 5),
                      "Keyboard save must reach Saved when Full Access permits shared writes")
        attachScreenshot("Keyboard favorite returns to companion Saved with Full Access on")
    }

    func testSystemKeyboardIPadSymbolPagesRotateWithoutChangingToolbar() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Owned iPad fixture only")
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

    func testSystemKeyboardSymbolPagesPreserveVisibleSearchBarAndKeys() throws {
        try requirePhoneKeyboardIntegration()
        let context = "Visible toolbar pages."
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        star.tap()
        XCTAssertTrue(waitForSymbolPage("migrated-favorites"))
        // Typing has no top row, so pages open with the toolbar hidden; U shows it.
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
        toggle.tap()
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
        XCTAssertFalse(symbolBoardKey("!").exists, "An off-page board must not expose active character keys")
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
}
