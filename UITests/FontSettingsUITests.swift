import XCTest
import UIKit

/// Optional Unicode fonts in app Settings and the keyboard's preview glyphs.
@MainActor
final class FontSettingsUITests: UniboardUITestCase {
    func testOptionalFontDownloadCatalogIsOnlyInAppSettings() {
        openAppSettings()
        let link = app.buttons["fontDownloads"].firstMatch
        revealByScrolling(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["Font Downloads"].firstMatch.waitForExistence(timeout: 5))
        for id in ["preview-basics", "historic-symbols", "han-supplementary", "han-latest"] {
            let pack = app.descendants(matching: .any)["fontDownloads.pack.\(id)"].firstMatch
            revealByScrolling(pack, in: app)
            XCTAssertTrue(pack.exists)
        }
        attachScreenshot("Optional font packs show explicit sizes, offline use and app-only controls")
    }

    func testSystemKeyboardDownloadedNotoFontAndResumableDownloadWithFullAccessOff() throws {
        try requireKeyboardIntegration()
        guard ProcessInfo.processInfo.environment["UNIBOARD_FONT_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("Live optional-font download acceptance is opt-in")
        }
        setKeyboardFullAccess(false)
        app.activate()
        selectAppEdition("latest")
        setAppUnicodeFonts(true)
        openAppSettings()
        let link = app.buttons["fontDownloads"].firstMatch
        revealByScrolling(link, in: app)
        link.tap()
        let remove = app.buttons["fontDownloads.remove.historic-symbols"].firstMatch
        if remove.exists { remove.tap() }
        let download = app.buttons["fontDownloads.download.historic-symbols"].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()
        let cancel = app.buttons["Cancel download"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        let message = app.staticTexts["fontDownloads.message"].firstMatch
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@", "cancelled"), object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 15), .completed)
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()
        // Leaving and reopening must observe the same app-wide operation.
        app.navigationBars["Font Downloads"].buttons.firstMatch.tap()
        revealByScrolling(link, in: app)
        link.tap()
        let pack = app.descendants(matching: .any)["fontDownloads.pack.historic-symbols"].firstMatch
        let ready = pack.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Available offline")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 180))
        XCTAssertFalse(app.buttons["fontDownloads.download.historic-symbols"].exists)
        attachScreenshot("Noto-first downloads complete, survive navigation and are available offline")
        for id in ["han-supplementary", "han-latest"] {
            let pack = app.descendants(matching: .any)["fontDownloads.pack.\(id)"].firstMatch
            revealByScrolling(pack, in: app)
            let remove = app.buttons["fontDownloads.remove.\(id)"].firstMatch
            if remove.exists { remove.tap() }
            let download = app.buttons["fontDownloads.download.\(id)"].firstMatch
            revealByScrolling(download, in: app)
            XCTAssertTrue(download.waitForExistence(timeout: 5))
            download.tap()
            let ready = pack.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Available offline")).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 180), "The large Han pack must complete through the real bounded downloader")
        }
        attachScreenshot("All three independently removable font packs are available offline")
        app.navigationBars["Font Downloads"].buttons.firstMatch.tap()
        app.launchArguments = []
        let input = openSystemKeyboardHost()
        defer {
            if app.buttons["keyboard.properties.close"].firstMatch.exists { app.buttons["keyboard.properties.close"].firstMatch.tap() }
            if app.buttons["keyboard.query.u"].firstMatch.exists { closeKeyboardSearch() }
            restoreEnglishKeyboard()
        }
        enterKeyboardQuery("u+16a70")
        let tangsa = app.buttons["keyboard.character.U+16A70"].firstMatch
        XCTAssertTrue(tangsa.waitUntilValueEquals("Preview font: Noto Sans Tangsa (preview subset)"))
        XCTAssertEqual(input.value as? String, "")
        tangsa.press(forDuration: 1)
        let source = app.staticTexts["keyboard.properties.fontSource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(source), "Noto Sans Tangsa (preview subset)")
        XCTAssertEqual(input.value as? String, "", "Downloading and inspecting never inserts text")
        app.buttons["keyboard.properties.close"].firstMatch.tap()
        app.buttons["keyboard.character.U+16A70"].firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\u{16A70}"))
        attachScreenshot("Downloaded Noto font reaches the keyboard with Full Access off and inserts the original scalar")
        var expected = "\u{16A70}"
        for (point, family) in [("20001", "Jigmo2"), ("30000", "Jigmo3"), ("20001", "Jigmo2")] {
            enterKeyboardQuery("u+" + point)
            let key = app.buttons["keyboard.character.U+\(point)"].firstMatch
            XCTAssertTrue(key.waitUntilValueEquals("Preview font: \(family) (preview subset)"))
            key.press(forDuration: 0.8)
            XCTAssertTrue(source.waitForExistence(timeout: 5))
            XCTAssertEqual(accessibleText(source), "\(family) (preview subset)")
            XCTAssertEqual(input.value as? String, expected, "Large font previews must preserve document text")
            app.buttons["keyboard.properties.close"].firstMatch.tap()
            key.tap()
            expected += String(Unicode.Scalar(UInt32(point, radix: 16)!)!)
            XCTAssertTrue(input.waitUntilValueEquals(expected), "Switching large Han fonts must keep the real extension responsive and insert once")
        }
        attachScreenshot("Both large Han subsets remain responsive in the keyboard and preserve original supplementary scalars")
    }

    func testOptionalUnicodeFontsAppChoicePersistsAndPreservesExactText() {
        selectAppEdition("latest")
        ensurePreviewBasics()
        setAppUnicodeFonts(false)
        let fonts = appUnicodeFontsSwitch()
        XCTAssertTrue(fonts.waitUntilValueEquals("0"), "The visible App Settings choice must be off before testing native previews")
        selectAppTab("Explore")
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
        selectAppTab("Explore")
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
        app.navigationBars["Font Licenses"].buttons.firstMatch.tap()
        setAppUnicodeFonts(false)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("0"), "Turning fonts off must also persist")
        attachScreenshot("App preview-font choice persists and can be disabled")
    }

    func testFontRulesDrawPreviewsOnlyWhileExtraUnicodeFontsIsOn() {
        // DEBUG fixture: A → Papyrus (code point), Basic Latin → Chalkduster (block).
        app.terminate()
        app.launchArguments = ["--uitesting", "-UniboardFontRuleFixture", "sample"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        setAppUnicodeFonts(true)
        for (codePoint, face) in [("U+0041", "Papyrus"), ("U+0042", "Chalkduster")] {
            selectAppTab("Explore")
            searchUnicode(codePoint)
            dismissAppSearchKeyboard()
            assertCharacterVisible(codePoint).tap()
            assertCharacterProperty("fontSource", contains: face)
            assertCharacterProperty("codepoints", equals: codePoint)
            attachScreenshot("\(codePoint) previews in its rule's face \(face)")
            app.buttons["Done"].tap()
        }

        let fonts = appUnicodeFontsSwitch()
        XCTAssertTrue(fonts.waitUntilValueEquals("1"))
        tapSwitch(fonts)
        let turnedOff = fonts.waitUntilValueEquals("0")
        if !turnedOff {
            attachScreenshot("Extra Unicode Fonts after tapping it off")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "App hierarchy after tapping Extra Unicode Fonts off"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(turnedOff)
        selectAppTab("Explore")
        searchUnicode("U+0041")
        dismissAppSearchKeyboard()
        assertCharacterVisible("U+0041").tap()
        assertCharacterProperty("codepoints", equals: "U+0041")
        XCTAssertFalse(app.staticTexts["characterProperties.fontSource"].firstMatch.exists,
                       "Extra Unicode Fonts off pauses font rules")
        app.buttons["Done"].tap()

        // Paused, not deleted: turning fonts back on applies the same rule.
        setAppUnicodeFonts(true)
        selectAppTab("Explore")
        searchUnicode("U+0041")
        dismissAppSearchKeyboard()
        assertCharacterVisible("U+0041").tap()
        assertCharacterProperty("fontSource", contains: "Papyrus")
        app.buttons["Done"].tap()

        setAppUnicodeFonts(false)
        app.terminate()
        app.launchArguments = ["--uitesting", "-UniboardFontRuleFixture", "clear"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testSystemKeyboardReadsAppFontSettingsAndPreservesExactInsertion() throws {
        try requireKeyboardIntegration()
        selectAppEdition("latest")
        ensurePreviewBasics()
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
        assertKeyboardHasNoSettingsMenu()
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
        assertKeyboardHasNoSettingsMenu()
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
        assertKeyboardHasNoSettingsMenu()
        attachScreenshot("Optional font preview inserts the original scalar with intact portrait toolbar")
        closeKeyboardSearch()

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return frame.width > frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        assertKeyboardHasNoSettingsMenu()
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
        assertKeyboardHasNoSettingsMenu()
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
            app.buttons["keyboard.typing.delete"].tap() // Done returns to typing, whose Delete is the lower key
            XCTAssertTrue(input.waitUntilValueEquals(expected), "Delete must remove each complete original character")
        }

        restoreEnglishKeyboard()
        XCTAssertTrue(appUnicodeFontsSwitch().waitUntilValueEquals("1"), "The app-owned font choice persists")
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
        assertKeyboardHasNoSettingsMenu()
        attachScreenshot("App Settings fonts and collapse off are reflected by the relaunched keyboard")
    }
}
