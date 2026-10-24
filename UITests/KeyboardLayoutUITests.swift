import XCTest
import UIKit

/// Layouts, the main keyboard's arrangement, its keys' layers and gestures, pad templates.
@MainActor
final class KeyboardLayoutUITests: UniboardUITestCase {
    func testLayoutsAreAddedRemovedAndKeepAtLeastOne() {
        resetAppLayouts()
        addTeardownBlock { @MainActor [self] in resetAppLayouts() }
        openAppLayouts()
        let english = app.descendants(matching: .any)["layouts.enabled.en"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        english.swipeLeft()
        XCTAssertFalse(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 1), "The only layout cannot be removed")
        addAppLayout("Greek", id: "el")
        addAppLayout("Russian", id: "ru")
        // A row's identifier also reaches its texts; keep each row once, in order.
        func enabled() -> [String] {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "layouts.enabled."))
                .allElementsBoundByIndex.map(\.identifier).reduce(into: []) { ids, id in if ids.last != id { ids.append(id) } }
        }
        XCTAssertEqual(enabled(), ["layouts.enabled.en", "layouts.enabled.el", "layouts.enabled.ru"])
        attachScreenshot("Layouts lists the enabled keyboards in switching order")
        removeAppLayout("en")
        XCTAssertEqual(enabled(), ["layouts.enabled.el", "layouts.enabled.ru"])
        app.navigationBars.buttons.firstMatch.tap()
        let link = app.buttons["keyboardLayouts"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("Ελληνικά, Русский"), link.label)
        // Keyboard › Main Keyboard edits each layout chosen in Settings.
        openMainKeyboardEditor()
        let alpha = app.buttons["mainKeyboard.key.letter.03B1"].firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5), "Main Keyboard shows the first layout's letters")
        XCTAssertFalse(app.buttons["mainKeyboard.key.letter.q"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["mainKeyboard.layout"].firstMatch.waitForExistence(timeout: 5))
        let russian = app.buttons["Русский"].firstMatch
        XCTAssertTrue(russian.waitForExistence(timeout: 5))
        russian.tap()
        XCTAssertTrue(app.buttons["mainKeyboard.key.letter.0436"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(alpha.exists)
        attachScreenshot("Main Keyboard shows the chosen layout's letters")
        app.navigationBars.buttons.firstMatch.tap()
    }

    func testKeyboardKeySettingsSavesExactChoicesDisablesAndRestoresDefaults() {
        resetAppKey("letter.q")
        openAppSettings()
        XCTAssertTrue(app.buttons["keyboardLayouts"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboardKeySettings"].exists, "Settings no longer has a separate Customize Keys screen")
        openMainKeyboardEditor()
        // Function keys move but have no layers.
        let shift = app.buttons["mainKeyboard.key.{shift}"].firstMatch
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        shift.tap()
        XCTAssertFalse(app.buttons["layers.swipeUp"].firstMatch.waitForExistence(timeout: 1), "Shift has no layers")
        selectMainKeyboardKey("letter.q")
        let gesture = app.buttons["layers.swipeUp"].firstMatch
        gesture.tap()
        // The editor lists the default candidates; replace them with one choice.
        XCTAssertTrue(app.staticTexts["keySettings.isDefault"].waitForExistence(timeout: 5))
        let removeAll = app.buttons["keySettings.removeAll"].firstMatch
        revealByScrolling(removeAll, in: app)
        removeAll.tap()
        XCTAssertTrue(app.staticTexts["keySettings.off"].waitForExistence(timeout: 5))
        app.buttons["keySettings.addChoice"].tap()
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
        XCTAssertTrue(saved, "Saving must return to the key's layers with its exact saved choice")
        attachScreenshot("Main Keyboard saves a literal multi-character swipe choice")

        app.terminate()
        app.launchArguments = []
        app.launch()
        openMainKeyboardEditor()
        selectMainKeyboardKey("letter.q")
        XCTAssertTrue(gesture.waitUntilValueEquals("xy"), "Explicit key settings survive an ordinary app relaunch")
        gesture.tap()
        XCTAssertTrue(app.buttons["keySettings.save"].firstMatch.waitForExistence(timeout: 5))
        let removeAllSaved = app.buttons["keySettings.removeAll"].firstMatch
        revealByScrolling(removeAllSaved, in: app)
        removeAllSaved.tap()
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(gesture.waitUntilValueEquals("Off"))
        gesture.tap()
        XCTAssertTrue(app.staticTexts["keySettings.off"].waitForExistence(timeout: 5), "Removing every choice turns the gesture off")
        let reset = app.buttons["keySettings.resetGesture"].firstMatch
        revealByScrolling(reset, in: app)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        XCTAssertTrue(app.staticTexts["keySettings.isDefault"].waitForExistence(timeout: 5))
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(gesture.waitForExistence(timeout: 5))
        // Q has no superscript or subscript, so its default swipe up is empty
        // too; reopening tells the restored default from the explicit Off.
        gesture.tap()
        XCTAssertTrue(app.staticTexts["keySettings.isDefault"].waitForExistence(timeout: 5), "Reset to Default restores the saved defaults")
        revealByScrolling(reset, in: app)
        XCTAssertFalse(reset.isEnabled)
        attachScreenshot("Disabled swipe and restored defaults are separate saved states")
        app.navigationBars.buttons.firstMatch.tap()
    }

    func testSymbolKeysSaveExactChoicesPersistAndRestoreDefaults() {
        openSymbolKeys()
        XCTAssertFalse(app.buttons["keySettings.key.letter.q"].exists, "Letters are edited in Main Keyboard")
        XCTAssertFalse(app.buttons["keySettings.key.digit.1"].exists, "Numbers are edited in Main Keyboard")
        XCTAssertFalse(app.descendants(matching: .any)["keySettings.layout"].exists, "Symbol keys are the same in every layout")
        let period = app.buttons["keySettings.key.symbol.002E"].firstMatch
        func openPeriod() {
            revealByScrolling(period, in: app)
            period.tap()
            XCTAssertTrue(app.descendants(matching: .any)["keySettings.detail.symbol.002E"].firstMatch.waitForExistence(timeout: 5))
        }
        let restore = app.buttons["keySettings.resetKey"].firstMatch
        let gesture = app.buttons["keySettings.gesture.swipeUp"].firstMatch
        openPeriod()
        if restore.isEnabled {
            restore.tap()
            app.buttons["Restore defaults"].tap()
        }
        XCTAssertTrue(gesture.waitUntilValueEquals("Default"))
        gesture.tap()
        XCTAssertTrue(app.buttons["keySettings.save"].firstMatch.waitForExistence(timeout: 5))
        let removeAll = app.buttons["keySettings.removeAll"].firstMatch
        revealByScrolling(removeAll, in: app)
        removeAll.tap()
        app.buttons["keySettings.addChoice"].tap()
        let choice = app.textFields["keySettings.choice.0"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        choice.typeText("xy")
        XCTAssertTrue(choice.waitUntilValueEquals("xy"))
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(gesture.waitUntilValueEquals("xy"), "Saving returns to the key with its exact choice")
        attachScreenshot("Symbol Keys saves a literal swipe-up choice on the period key")

        app.terminate()
        app.launchArguments = []
        app.launch()
        openSymbolKeys()

        // Restore All shows its full scope before asking; dismissing the confirmation keeps every choice.
        let restoreAll = app.buttons["keySettings.resetAll"].firstMatch
        revealByScrolling(restoreAll, in: app)
        XCTAssertEqual(restoreAll.label, "Restore All Key Defaults")
        XCTAssertTrue(restoreAll.isEnabled, "A saved symbol choice enables Restore All")
        let scope = app.staticTexts["keySettings.resetAll.scope"].firstMatch
        XCTAssertTrue(scope.exists)
        XCTAssertEqual(scope.label, "Resets letters, numbers and symbols, and every layout’s arrangement.")
        restoreAll.tap()
        let confirmTitle = app.staticTexts["Restore all key defaults?"].firstMatch
        XCTAssertTrue(confirmTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["keySettings.resetAll.confirm"].firstMatch.label, "Restore All Key Defaults")
        attachScreenshot("Restore All asks before resetting every key")
        scope.tap()
        XCTAssertTrue(confirmTitle.waitForNonExistence(timeout: 5))

        openPeriod()
        XCTAssertTrue(gesture.waitUntilValueEquals("xy"), "Symbol key choices survive an ordinary app relaunch and a dismissed Restore All")
        XCTAssertTrue(restore.isEnabled)
        restore.tap()
        app.buttons["Restore defaults"].tap()
        XCTAssertTrue(gesture.waitUntilValueEquals("Default"))
        XCTAssertFalse(restore.isEnabled)
        attachScreenshot("Restoring the period key's defaults")

        // Find a key narrows the symbol grid.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Symbol Keys"].waitForExistence(timeout: 5))
        let search = app.searchFields["Find a key"].firstMatch
        if !(search.waitForExistence(timeout: 2) && search.isHittable) { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("§")
        XCTAssertTrue(app.buttons["keySettings.key.symbol.00A7"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["keySettings.key.symbol.002E"].firstMatch.waitForNonExistence(timeout: 5), "Search hides other symbol keys")
        attachScreenshot("Find a key filters Symbol Keys")
    }

    func testSystemKeyboardWidePadHasStockFunctionsAndExactTypingAcrossRotation() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Wide iPad layout requires the owned iPad QA device")
        configurePadLayout("ansiNumbers")
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
        flickMainKey(app.buttons["keyboard.typing.key.q"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐"), "Down inserts a styled capital, not the other case")
        XCTAssertTrue(caps.waitUntilValueEquals("on"))
        rightShift.tap()
        XCTAssertTrue(caps.waitUntilValueEquals("off"))
        app.buttons["keyboard.typing.key.q"].tap()
        app.buttons["keyboard.typing.key.,"].tap()
        app.buttons["keyboard.typing.key.."].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,."))
        app.buttons["keyboard.return"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,.\n"))
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,."))
        // Letters carry no symbol hints: Up inserts the modifier letter in the shown case.
        let aKey = app.buttons["keyboard.typing.key.a"].firstMatch
        let modifierA = aKey.label == "A" ? "ᴬ" : "ᵃ"
        flickMainKey(aKey, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,." + modifierA))
        let eKey = app.buttons["keyboard.typing.key.e"].firstMatch
        let modifierE = eKey.label == "E" ? "ᴱ" : "ᵉ"
        flickMainKey(eKey, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,." + modifierA + modifierE))
        for _ in 0..<2 { app.buttons["keyboard.typing.delete"].tap() }
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,."))
        attachScreenshot("Stock iPad three letter rows without symbol hints, gray modifiers, blue Return")
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
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,."))
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        if shift.value as? String != "lowercase" { shift.tap() }
        app.buttons["keyboard.typing.key.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,.1"))
        shift.tap()
        app.buttons["keyboard.typing.key.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,.1!"))
        shift.tap()
        app.buttons["keyboard.typing.key.["].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,.1!{"))
        caps.tap()
        app.buttons["keyboard.typing.key.1"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("\tA𝐐q,.1!{1"), "Caps Lock changes letters, not digits")
        caps.tap()
        app.buttons["keyboard.return"].tap()
        app.buttons["keyboard.typing.key.1"].tap()
        let expected = "\tA𝐐q,.1!{1\n1"
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

    func testSystemKeyboardPadAppPresetsApplyWithoutFullAccess() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad settings require the owned iPad QA device")
        defer { XCUIDevice.shared.orientation = .portrait; restoreEnglishKeyboard() }
        for layout in ["ansi", "stock", "ansiNumbers"] {
            XCUIDevice.shared.orientation = .portrait
            configurePadLayout(layout)
            let input = openSystemKeyboardHost(unicodeBrowse: false)
            settleKeyboardOrientation(.landscapeLeft, toolbarVisible: false)
            assertLandscapePadGeometry(numberRow: layout == "ansiNumbers", ansi: layout != "stock")
            let a = app.buttons["keyboard.typing.key.a"].firstMatch
            a.tap()
            XCTAssertTrue(input.waitUntilValueEquals("A"), "Ordinary taps stay QWERTY for every preset")
            flickMainKey(a, up: true)
            XCTAssertTrue(input.waitUntilValueEquals("Aᵃ"), "Up inserts the modifier letter on every preset")
            app.buttons["keyboard.typing.numbers"].tap()
            XCTAssertEqual(app.buttons.matching(identifier: "keyboard.return").count, 1)
            XCTAssertTrue(app.buttons["keyboard.return"].firstMatch.isHittable)
            XCTAssertFalse(app.buttons["keyboard.typing.key.1"].exists)
            app.buttons["keyboard.typing.letters"].tap()
            assertLandscapePadGeometry(numberRow: layout == "ansiNumbers", ansi: layout != "stock")
            attachScreenshot("App-only iPad preset \(layout) with Full Access off")
            settleKeyboardOrientation(.portrait, toolbarVisible: false)
            restoreEnglishKeyboard()
        }
        configurePadLayout("ansiNumbers")
    }

    func testSystemKeyboardPadFixedTemplateKeepsNumberRowAndShiftSlideAcrossRotation() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Owned iPad QA fixture")
        configurePadLayout("ansiNumbers")
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

    func testSystemKeyboardFixedTemplateHasNoTopRowAndTheDigitsAsItsFirstRow() throws {
        try requirePhoneKeyboardIntegration()
        defer { restoreEnglishKeyboard() }
        let input = openSystemKeyboardHost(initialText: "Fixed ", unicodeBrowse: false)
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        let digits = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.typing.number."))
        XCTAssertEqual(digits.count, 10)
        let surface = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        XCTAssertEqual(surface.height, 237, accuracy: 1, "The number row, three rows and the footer; no top row")
        for key in [q, app.buttons["keyboard.typing.key.a"].firstMatch, app.buttons["keyboard.typing.key.m"].firstMatch,
                    app.buttons["keyboard.space"].firstMatch] + digits.allElementsBoundByAccessibilityElement {
            XCTAssertEqual(key.frame.height, 41.4, accuracy: 1)
            XCTAssertTrue(surface.insetBy(dx: -1, dy: -1).contains(key.frame))
        }
        let one = app.buttons["keyboard.typing.number.1"].firstMatch
        XCTAssertLessThan(one.frame.maxY, q.frame.minY, "The digits are the first row")
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.resize"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.resize.direction"].firstMatch.exists)
        XCTAssertFalse(app.scrollViews["keyboard.typing.favorites"].firstMatch.exists, "No symbols row above the keys")
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.search"].firstMatch.exists, "No search field above the keys")
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertEqual(toggle.label, "Show Unicode toolbar")
        XCTAssertEqual(toggle.value as? String, "off")
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
        attachScreenshot("Fixed layout without a top row")
        // U still opens search, which brings its own field.
        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.waitUntilValueEquals("on"))
        attachScreenshot("U opens search; the key shows as an ordinary key while the toolbar shows")
        closeKeyboardSearch()
        XCTAssertTrue(toggle.waitUntilValueEquals("off"))
    }

    func testSystemKeyboardDistinctLetterGesturesAndSystemShiftSlide() throws {
        try requirePhoneKeyboardIntegration()
        let context = "Literal "
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }

        let iKey = app.buttons["keyboard.typing.key.i"].firstMatch
        let oKey = app.buttons["keyboard.typing.key.o"].firstMatch
        flickMainKey(iKey, up: true)
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱ"), "Up inserts the modifier letter, not a symbol")
        flickMainKey(iKey, up: true, horizontal: 36)
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢ"), "Sliding sideways reaches the subscript")
        flickMainKey(oKey, up: true)
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢᵒ"))
        flickMainKey(oKey, up: false)
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢᵒ𝐨"), "Down inserts a styled form, not the other case")
        chooseHeldKeyboardOption(iKey, optionCount: 7, selectedIndex: 1, extraActions: 0)
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢᵒ𝐨ì"))
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        let q = app.buttons["keyboard.typing.key.q"].firstMatch
        shift.press(forDuration: 0.6, thenDragTo: q)
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢᵒ𝐨ìQ"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        shift.press(forDuration: 0.6)
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"))
        q.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢᵒ𝐨ìQQ"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        shift.doubleTap()
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"))
        typeHostTypingKeys("qw", layout: "letters")
        XCTAssertTrue(input.waitUntilValueEquals(context + "ⁱᵢᵒ𝐨ìQQQW"))
        shift.tap()
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        attachScreenshot("Distinct letter accents, modifier and styled forms, and system Shift gestures")
    }

    func testSystemKeyboardSwitchesLayoutsWithTheSpaceBarAndRemembersTheChoice() throws {
        try requirePhoneKeyboardIntegration()
        resetAppLayouts()
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); resetAppLayouts() }
        openAppLayouts()
        addAppLayout("Greek", id: "el")
        addAppLayout("Russian", id: "ru")
        let context = "Switch "
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false)
        let space = app.buttons["keyboard.space"].firstMatch
        XCTAssertTrue(space.waitForExistence(timeout: 5))
        // The keyboard remembers the layout of an earlier run. English is then
        // the first of the others, right after the current layout.
        if space.value as? String != "English" {
            XCTAssertTrue(["Ελληνικά", "Русский"].contains(space.value as? String ?? ""), "With several layouts the space bar names the current one")
            chooseHeldKeyboardOption(space, optionCount: 3, selectedIndex: 1, extraActions: 0)
        }
        XCTAssertTrue(space.waitUntilValueEquals("English"), "With several layouts the space bar names the current one")
        chooseHeldKeyboardOption(space, optionCount: 3, selectedIndex: 1, extraActions: 0)
        XCTAssertTrue(space.waitUntilValueEquals("Ελληνικά"))
        XCTAssertEqual(input.value as? String, context, "Switching types nothing")
        let alpha = app.buttons["keyboard.typing.key.α"].firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard.typing.key.q"].exists)
        alpha.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "α"))
        flickMainKey(alpha, up: false)
        XCTAssertTrue(input.waitUntilValueEquals(context + "α𝛂"), "Down offers mathematical Greek")
        app.buttons["keyboard.typing.shift"].tap()
        alpha.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "α𝛂Α"))
        space.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "α𝛂Α "), "A tap on the named space bar still types a space")
        attachScreenshot("Greek layout chosen by holding the space bar")
        // The chooser lists the current layout first, then the others in order.
        chooseHeldKeyboardOption(space, optionCount: 3, selectedIndex: 2, extraActions: 0)
        XCTAssertTrue(space.waitUntilValueEquals("Русский"))
        app.buttons["keyboard.typing.key.ж"].firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "α𝛂Α ж"))
        chooseHeldKeyboardOption(app.buttons["keyboard.typing.key.е"].firstMatch, optionCount: 2, selectedIndex: 1, extraActions: 0)
        XCTAssertTrue(input.waitUntilValueEquals(context + "α𝛂Α жё"), "Russian е holds ё")
        let reopened = openSystemKeyboardHost(unicodeBrowse: false)
        XCTAssertTrue(app.buttons["keyboard.space"].firstMatch.waitUntilValueEquals("Русский"), "The keyboard remembers the last layout")
        XCTAssertTrue(app.buttons["keyboard.typing.key.ж"].firstMatch.exists)
        _ = reopened
    }

    func testSystemKeyboardDrawsTheAppArrangementAndNamedResults() throws {
        try requirePhoneKeyboardIntegration()
        openAppPages()
        app.buttons["pages.keyboard"].firstMatch.tap()
        app.buttons["mainKeyboard.key.letter.q"].firstMatch.tap()
        app.buttons["mainKeyboard.right"].firstMatch.tap()
        app.buttons["mainKeyboard.more"].firstMatch.tap()
        app.buttons["mainKeyboard.add.Tab"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mainKeyboard.key.{tab}"].firstMatch.waitForExistence(timeout: 5))
        addTeardownBlock { @MainActor [self] in
            restoreEnglishKeyboard()
            openAppPages()
            app.buttons["pages.keyboard"].firstMatch.tap()
            app.buttons["mainKeyboard.more"].firstMatch.tap()
            app.buttons["mainKeyboard.reset"].firstMatch.tap()
        }
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        let tab = app.buttons["keyboard.typing.tab"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "The keyboard draws the app's Tab key")
        let q = app.buttons["keyboard.typing.key.q"].firstMatch, w = app.buttons["keyboard.typing.key.w"].firstMatch
        XCTAssertGreaterThan(q.frame.minX, w.frame.minX, "Q follows W as arranged")
        tab.tap()
        XCTAssertTrue(input.waitUntilValueEquals("\t"), "Tab types a tab")
        attachScreenshot("The keyboard draws the app's arrangement")
        app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.tap()
        enterKeyboardQuery("thai character")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'keyboard.character.'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        attachScreenshot("Search results show the code point and a wrapped name")
    }

    func testSystemKeyboardWithoutDigitsKeepsThemOnThe123PageAndInSearch() throws {
        try requirePhoneKeyboardIntegration()
        resetAppKey("letter.w")
        // A failed assertion stops the test, so restore the default in teardown rather than a defer.
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); resetMainKeyboard() }
        openMainKeyboardEditor()
        // Digits are ordinary keys: each one can go, and the number row with them.
        for digit in "1234567890" {
            let key = app.buttons["mainKeyboard.key.digit.\(digit)"].firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5))
            key.tap()
            app.buttons["mainKeyboard.remove"].firstMatch.tap()
            XCTAssertTrue(key.waitUntilAbsent())
        }
        let q = app.buttons["mainKeyboard.key.letter.q"].firstMatch
        attachScreenshot("The main keyboard without digits")
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        let w = app.buttons["keyboard.typing.key.w"].firstMatch
        XCTAssertTrue(w.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard.typing.number.1"].firstMatch.exists, "The arrangement has no digits")
        let surface = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        XCTAssertEqual(surface.height, 237 - 41.4 - 4, accuracy: 1, "Three rows: one row and one gap shorter")
        attachScreenshot("Keyboard without the number row")
        flickMainKey(w, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("ᵂ"), "W swipes up to its modifier letter, not a digit")
        let numbers = app.buttons["keyboard.typing.numbers"].firstMatch
        XCTAssertEqual(numbers.label, "Numbers", "Without digits on screen, the page key offers the 123 page")
        numbers.tap()
        let one = app.buttons["keyboard.typing.key.1"].firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5), "The 123 page keeps its stock digit row")
        one.tap()
        XCTAssertTrue(input.waitUntilValueEquals("ᵂ1"))
        app.buttons["keyboard.typing.letters"].firstMatch.tap()
        reopenKeyboardSearch(expectedQuery: "No query")
        XCTAssertTrue(app.buttons["keyboard.query.1"].firstMatch.exists, "Unicode search keeps its own digit row")
        closeKeyboardSearch()
        // Add Number Row puts all ten back as the first row.
        openMainKeyboardEditor()
        app.buttons["mainKeyboard.more"].firstMatch.tap()
        let add = app.buttons["mainKeyboard.add.digits"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "Add Number Row")
        add.tap()
        let first = app.buttons["mainKeyboard.key.digit.1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.maxY, q.frame.minY, "The number row is the first row again")
    }

    /// A digit drags like any key: dropped on Q it lands before Q, in the
    /// letters' row, and the keyboard draws and types it there.
    func testMainKeyboardDragsADigitIntoTheLettersAndTheKeyboardTypesIt() throws {
        openMainKeyboardEditor()
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); resetMainKeyboard() }
        let one = app.buttons["mainKeyboard.key.digit.1"].firstMatch
        let two = app.buttons["mainKeyboard.key.digit.2"].firstMatch
        let q = app.buttons["mainKeyboard.key.letter.q"].firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5)); XCTAssertTrue(q.exists)
        XCTAssertLessThan(one.frame.maxY, q.frame.minY, "The standard keyboard starts with the number row")
        one.press(forDuration: 1, thenDragTo: q, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(one.waitUntilFrame { abs($0.midY - q.frame.midY) < 2 }, "1 joins the letters' row")
        XCTAssertLessThan(one.frame.minX, q.frame.minX, "1 lands before Q")
        XCTAssertLessThan(two.frame.maxY, q.frame.minY, "The other digits stay in the number row")
        XCTAssertFalse(app.staticTexts["mainKeyboard.error"].exists)
        attachScreenshot("A digit dragged into the letters")
        // Saved once: it is still there after leaving and reopening the editor.
        app.navigationBars.buttons.firstMatch.tap()
        openMainKeyboardEditor()
        XCTAssertTrue(one.waitUntilFrame { abs($0.midY - q.frame.midY) < 2 })
        guard keyboardIntegrationEnabled else { return }
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        let key = app.buttons["keyboard.typing.number.1"].firstMatch, typingQ = app.buttons["keyboard.typing.key.q"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertEqual(key.frame.midY, typingQ.frame.midY, accuracy: 1, "The keyboard draws 1 where the app put it")
        XCTAssertLessThan(key.frame.minX, typingQ.frame.minX)
        key.tap()
        XCTAssertTrue(input.waitUntilValueEquals("1"), "A moved digit still types itself")
        attachScreenshot("The keyboard draws the dragged digit")
    }

    func testSystemKeyboardOpenHoldChooserKeepsItsGroup() throws {
        try requirePhoneKeyboardIntegration()
        let context = "Literal "
        let input = openSystemKeyboardHost(initialText: context, unicodeBrowse: false, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        XCTAssertTrue(app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.waitUntilValueEquals("off"))
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.options"].firstMatch.exists,
                       "Character order is unavailable while ordinary typing replaces the picker")
        // C is in the last row of letters, so its accents open above it.
        // (With no top row, a key one row from the top opens them below.)
        let cKey = app.buttons["keyboard.typing.key.c"].firstMatch
        // Before, dragging down from an open hold switched to the Down forms.
        // Now the accents stay, and lifting away from them inserts nothing.
        flickMainKey(cKey, up: false, pressDuration: 0.65)
        sleep(1)
        XCTAssertEqual(input.value as? String, context, "An open hold chooser does not switch to the Down forms")
        app.buttons["keyboard.typing.key.q"].firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "q"), "The next tap stays literal")
        let star = app.buttons["keyboard.openFavorites"].firstMatch
        star.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.pages.pager"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.options"].firstMatch.exists,
                       "Symbol pages do not expose Unicode result ordering")
        star.tap()
        openUnicodeBrowse()
        selectKeyboardSection("symbols")
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.options"].firstMatch.exists,
                       "Unicode results are always in code point order, with no order menu")
        app.buttons["keyboard.openTyping"].firstMatch.tap()
        XCTAssertEqual(input.value as? String, context + "q")
        attachScreenshot("An open hold keeps its accents, with no order menu")
    }

    func testSystemKeyboardAppConfiguredFlicksPreserveLiteralTextAndShift() throws {
        try requireKeyboardIntegration()
        configureAppKeyGesture(keyID: "letter.q", gesture: "swipeUp", choices: ["xy", "cd"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "longPress", choices: ["h"])
        configureAppKeyGesture(keyID: "letter.q", gesture: "swipeDown", choices: ["d"])
        configureAppKeyGesture(keyID: "digit.1", gesture: "swipeDown", choices: ["_"])
        configureAppKeyGesture(keyID: "digit.1", gesture: "swipeUp", choices: ["!"])
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        defer { restoreEnglishKeyboard() }
        let shift = app.buttons["keyboard.typing.shift"].firstMatch
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "The fresh sentence-capitalizing host starts uppercase")
        XCTAssertEqual(app.buttons["keyboard.typing.key.q"].firstMatch.label, "Q", "A tap always types the key itself")
        flickMainKey(app.buttons["keyboard.typing.key.a"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("𝐀"), "The default down flick follows the visible uppercase")
        XCTAssertTrue(shift.waitUntilValueEquals("uppercase"), "A default down flick preserves automatic uppercase across host callbacks")
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
        flickMainKey(q, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("qxyd"), "Long press, up and down must each use only their own mapping")
        app.buttons["keyboard.typing.delete"].tap()
        XCTAssertTrue(input.waitUntilValueEquals("qxy"))
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"), "A literal flick preserves visible Shift")
        flickMainKey(app.buttons["keyboard.typing.number.1"].firstMatch, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_"), "A configured digit downward flick inserts its literal choice without a digit tap")
        flickMainKey(app.buttons["keyboard.typing.number.1"].firstMatch, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!"), "The auxiliary number row reads the same physical-key override")

        let a = app.buttons["keyboard.typing.key.a"].firstMatch
        flickMainKey(a, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!𝐚"), "The default down flick chooses a styled form in the current case")
        XCTAssertTrue(shift.waitUntilValueEquals("lowercase"))
        flickMainKey(a, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!𝐚ᵃ"), "The default upward flick inserts the modifier letter without a letter tap")
        flickMainKey(app.buttons["keyboard.typing.key.w"].firstMatch, up: true)
        flickMainKey(app.buttons["keyboard.typing.key.p"].firstMatch, up: true)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!𝐚ᵃʷᵖ"), "W and P flick up to their modifier letters")
        shift.doubleTap()
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"))
        flickMainKey(a, up: false)
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!𝐚ᵃʷᵖ𝐀"))
        XCTAssertTrue(shift.waitUntilValueEquals("capsLock"), "A down flick must not consume Caps Lock")
        q.tap()
        XCTAssertTrue(input.waitUntilValueEquals("qxy_!𝐚ᵃʷᵖ𝐀Q"))
        attachScreenshot("Real main-key flicks insert exact settings and retain lowercase or locked Shift")

        restoreEnglishKeyboard()
        resetAppKey("letter.q")
        resetAppKey("digit.1")
    }

    func testArrangeEditsKeyLayersAndTheMainKeyboard() {
        openAppPages()
        let symbols = app.buttons["pages.page.stock-symbols"].firstMatch
        XCTAssertTrue(symbols.waitForExistence(timeout: 5))
        symbols.tap()
        openArrange()
        let first = app.buttons["arrange.0.0"].firstMatch, tenth = app.buttons["arrange.0.9"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(first.frame.minX, app.frame.minX, "Arrange fits the screen")
        XCTAssertLessThanOrEqual(tenth.frame.maxX, app.frame.maxX, "Arrange fits the screen")
        first.tap()
        let up = app.buttons["layers.swipeUp"].firstMatch
        XCTAssertTrue(up.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["layers.longPress"].exists && app.buttons["layers.swipeDown"].exists)
        up.tap()
        app.buttons["layer.addChoice"].firstMatch.tap()
        let field = app.textFields["layer.choice.0"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("x")
        app.buttons["layer.save"].firstMatch.tap()
        XCTAssertTrue(up.waitUntilValueEquals("x"), "The swipe-up layer keeps its new choice")
        attachScreenshot("Arrange shows the selected key's three layers")
        up.tap()
        let saved = app.textFields["layer.choice.0"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        saved.typeText(XCUIKeyboardKey.delete.rawValue)
        app.buttons["layer.save"].firstMatch.tap()
        XCTAssertTrue(up.waitUntilValueEquals("Off"))

        openAppPages()
        let keyboard = app.buttons["pages.keyboard"].firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.tap()
        let q = app.buttons["mainKeyboard.key.letter.q"].firstMatch
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.buttons["mainKeyboard.key.letter.p"].firstMatch.frame.maxX, app.frame.maxX)
        q.tap()
        XCTAssertTrue(app.buttons["layers.swipeDown"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("The main keyboard's Q key shows its three layers")
        let key = app.buttons["layers.tap"].firstMatch
        XCTAssertTrue(key.waitUntilValueEquals("q"), "The key types itself until changed")
        key.tap()
        XCTAssertFalse(app.buttons["layer.addChoice"].exists, "The key itself has one value, edited in place")
        let output = app.textFields["layer.choice.0"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        output.tap()
        output.typeText(XCUIKeyboardKey.delete.rawValue + "x")
        app.buttons["layer.save"].firstMatch.tap()
        XCTAssertTrue(key.waitUntilValueEquals("x"), "The changed key types x")
        key.tap()
        let changed = app.textFields["layer.choice.0"].firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 5))
        changed.tap()
        changed.typeText(XCUIKeyboardKey.delete.rawValue)
        app.buttons["layer.save"].firstMatch.tap()
        XCTAssertTrue(key.waitUntilValueEquals("q"), "No value restores the key's own text")
        // Letters, Shift and Delete move like a page's keys, and Tab can join them.
        let w = app.buttons["mainKeyboard.key.letter.w"].firstMatch
        XCTAssertLessThan(q.frame.minX, w.frame.minX)
        app.buttons["mainKeyboard.right"].firstMatch.tap()
        XCTAssertTrue(q.waitUntilFrame { $0.minX > w.frame.minX }, "Q moved right of W")
        app.buttons["mainKeyboard.more"].firstMatch.tap()
        app.buttons["mainKeyboard.add.Tab"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mainKeyboard.key.{tab}"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.buttons["mainKeyboard.key.letter.p"].firstMatch.frame.maxX, app.frame.maxX, "The rows still fit")
        attachScreenshot("The main keyboard rearranged with Tab")
        app.buttons["mainKeyboard.more"].firstMatch.tap()
        app.buttons["mainKeyboard.reset"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mainKeyboard.key.{tab}"].firstMatch.waitUntilAbsent())
        XCTAssertTrue(q.waitUntilFrame { $0.minX < w.frame.minX }, "Standard Layout restores the rows")
    }
}
