import XCTest
import UIKit

/// Shared setUp and helpers for every Uniboard UI test class. Test classes
/// are grouped by feature area; docs/ui-test-shards.md maps source areas to
/// classes and lists the smoke, per-area and full-run commands.
@MainActor
class UniboardUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// The DEBUG app turns the keyboard's text preview off or on at launch,
    /// so no test inherits it and preview tests skip two trips to Settings.
    static let setUpLaunchArguments = ["--uitesting", "--text-preview", "off"]
    static let textPreviewLaunchArguments = ["--uitesting", "--text-preview", "on"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = Self.setUpLaunchArguments
        app.launch()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.height > self.app.frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
    }

    func openAppLayouts() {
        openAppSettings()
        let link = app.buttons["keyboardLayouts"].firstMatch
        revealByScrolling(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["Layouts"].waitForExistence(timeout: 5))
    }

    func addAppLayout(_ query: String, id: String) {
        app.buttons["layouts.add"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(query)
        XCTAssertTrue(field.waitUntilValueEquals(query), "Layout search accepts the complete query")
        let row = app.buttons["layouts.catalog.\(id)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Search finds \(query)")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.value as? String == query && row.exists && row.isHittable
        }, object: row)
        let searchReady = XCTWaiter.wait(for: [ready], timeout: 5) == .completed
        attachDiagnostics("Layout \(id) search before selection")
        XCTAssertTrue(searchReady, "The filtered layout must be hittable before selection")
        row.tap()
        // Capture each transition before assertions can stop the test or teardown navigates away.
        // Search can hide the sheet title while the underlying Layouts bar remains in AX.
        let catalogRowGone = row.waitUntilAbsent()
        let searchGone = field.waitUntilAbsent()
        let dismissed = catalogRowGone && searchGone
        let returned = app.navigationBars["Layouts"].firstMatch.waitForExistence(timeout: 5)
        let added = app.descendants(matching: .any)["layouts.enabled.\(id)"].firstMatch.waitForExistence(timeout: 5)
        let error = app.descendants(matching: .any)["layouts.error"].firstMatch
        let saveFailed = error.exists
        let errorText = saveFailed ? error.label : "No layouts.error"
        attachDiagnostics("Layout \(id) after selection: dismissed=\(dismissed), parent=\(returned), added=\(added), \(errorText)")
        XCTAssertTrue(dismissed, "Selecting \(query) must dismiss Add Layout")
        XCTAssertTrue(returned, "Selecting \(query) must return to Layouts")
        XCTAssertFalse(saveFailed, "Adding \(query) must not show layouts.error: \(errorText)")
        XCTAssertTrue(added, "Adding \(query) must create layouts.enabled.\(id)")
    }

    func removeAppLayout(_ id: String) {
        let row = app.descendants(matching: .any)["layouts.enabled.\(id)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(row.waitUntilAbsent())
    }

    /// Leaves English as the only layout, as a fresh install has it.
    func resetAppLayouts() {
        openAppLayouts()
        if !app.descendants(matching: .any)["layouts.enabled.en"].firstMatch.exists { addAppLayout("English", id: "en") }
        let others = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@",
                                                                            "layouts.enabled.", "layouts.enabled.en"))
        for _ in 0..<8 where others.firstMatch.exists {
            removeAppLayout(String(others.firstMatch.identifier.dropFirst("layouts.enabled.".count)))
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @discardableResult
    func revealResultCharacter(_ codepoint: String) -> XCUIElement {
        let results = app.scrollViews["exploreResults"].firstMatch
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

    func assertAppCatalogScalar(_ codepoint: String, assigned: Bool, age: String? = nil) {
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

    func assertPadFooter(pageID: String, file: StaticString = #filePath, line: UInt = #line) {
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

    func configurePadLayout(_ layout: String) {
        openAppSettings()
        for (identifier, value) in [("padLayout", layout)] {
            let picker = app.descendants(matching: .any)[identifier].firstMatch
            let scroll = settingsList()
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

    func assertLandscapePadGeometry(numberRow: Bool, ansi: Bool,
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
        if app.buttons["keyboard.typing.key.["].exists != ansi {
            attachScreenshot("Actual iPad layout before the ANSI assertion")
            let diagnostic = XCTAttachment(string: "app=\(app.frame) keyboard=\(String(describing: measuredKeyboardSurfaceFrame()))\n\(app.debugDescription)")
            diagnostic.name = "Original rendered iPad layout and physical key identities"
            diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        XCTAssertEqual(app.buttons["keyboard.typing.key.["].exists, ansi, "ANSI punctuation must follow the selected wide landscape preset", file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.key.1"].exists, numberRow, file: file, line: line)
        XCTAssertEqual(app.buttons["keyboard.typing.number.1"].exists, !numberRow, file: file, line: line)
        XCTAssertFalse(app.otherElements["keyboard.typing.favorites"].exists, file: file, line: line)
    }

    /// Keyboard › Main Keyboard: restores every layer of a main-keyboard
    /// key to its default, the key's own tap output included.
    func resetAppKey(_ keyID: String) {
        openMainKeyboardEditor()
        selectMainKeyboardKey(keyID)
        for gesture in ["swipeUp", "longPress", "swipeDown"] {
            let layer = app.buttons["layers.\(gesture)"].firstMatch
            revealByScrolling(layer, in: app)
            layer.tap()
            let save = app.buttons["keySettings.save"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            // Reset to Default is disabled when the layer already has its defaults.
            let reset = app.buttons["keySettings.resetGesture"].firstMatch
            revealByScrolling(reset, in: app)
            if reset.isEnabled {
                reset.tap()
                XCTAssertTrue(app.staticTexts["keySettings.isDefault"].waitForExistence(timeout: 5))
                save.tap()
            } else {
                app.navigationBars.buttons.firstMatch.tap()
            }
            XCTAssertTrue(layer.waitForExistence(timeout: 5))
        }
        // No value restores the key's own text.
        let tap = app.buttons["layers.tap"].firstMatch
        revealByScrolling(tap, in: app)
        tap.tap()
        let output = app.textFields["layer.choice.0"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        if let value = output.value as? String, !value.isEmpty, value != output.placeholderValue {
            output.tap()
            output.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        app.buttons["layer.save"].firstMatch.tap()
        XCTAssertTrue(tap.waitForExistence(timeout: 5))
    }

    /// Selects a key on the open main keyboard editor so its layers show.
    func selectMainKeyboardKey(_ keyID: String) {
        let key = app.buttons["mainKeyboard.key.\(keyID)"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5), keyID)
        key.tap()
        XCTAssertTrue(app.buttons["layers.swipeUp"].firstMatch.waitForExistence(timeout: 5), "\(keyID) shows its layers")
    }

    func flickMainKey(_ key: XCUIElement, up: Bool, horizontal: CGFloat = 0, pressDuration: TimeInterval = 0.05,
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
            start.press(forDuration: pressDuration, thenDragTo: vertical)
        } else {
            XCTAssertTrue(app.frame.contains(CGPoint(x: x + horizontal, y: frame.midY + (up ? -distance : distance))),
                          "The gesture's actual endpoint must be on screen", file: file, line: line)
            let finish = vertical.withOffset(CGVector(dx: horizontal, dy: 0))
            start.press(forDuration: pressDuration, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    /// Keyboard › Main Keyboard: replaces one layer of a key with exact choices.
    func configureAppKeyGesture(keyID: String, gesture: String, choices: [String]) {
        openMainKeyboardEditor()
        selectMainKeyboardKey(keyID)
        let layer = app.buttons["layers.\(gesture)"].firstMatch
        revealByScrolling(layer, in: app)
        layer.tap()
        XCTAssertTrue(app.buttons["keySettings.save"].firstMatch.waitForExistence(timeout: 5))
        // A long default list can leave Remove All below the fold, not yet created.
        let removeAll = app.buttons["keySettings.removeAll"].firstMatch
        revealByScrolling(removeAll, in: app)
        removeAll.tap()
        for (index, value) in choices.enumerated() {
            app.buttons["keySettings.addChoice"].tap()
            let field = app.textFields["keySettings.choice.\(index)"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(value)
            XCTAssertTrue(field.waitUntilValueEquals(value))
        }
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(layer.waitUntilValueEquals(choices.joined(separator: " ")))
    }

    func typeHostTypingKeys(_ text: String, layout: String = "letters") {
        assertHostTypingPanel()
        for key in text {
            let button = app.buttons["keyboard.typing.key.\(key)"].firstMatch
            XCTAssertTrue(button.waitUntilValueEquals(layout), "Expected the real \(layout) key \(key)")
            XCTAssertTrue(button.isHittable)
            button.tap()
        }
    }

    /// Adds the text, then the emoji snowman to the open page from the picker.
    func addSnowmanPresentations() {
        for (form, points) in [("text", "U+2603 U+FE0E"), ("emoji", "U+2603 U+FE0F")] {
            let add = app.buttons["page.addUnicode"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("snowman")
            let row = app.buttons["picker.\(form).U+2603"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "The picker offers the \(form) form on its own")
            XCTAssertTrue(row.label.contains(points), row.label)
            row.tap()
            XCTAssertTrue(field.waitUntilAbsent())
        }
    }

    /// A page opens as its canvas.
    func openArrange() {
        XCTAssertTrue(app.descendants(matching: .any)["arrange.canvas"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Selects a page key and adds a hold choice from the Unicode picker.
    func addAppPageKeyHoldChoice(_ key: XCUIElement, query: String, codepoint: String) {
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap()
        let hold = app.buttons["layers.longPress"].firstMatch
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        hold.tap()
        app.buttons["layer.chooseUnicode"].firstMatch.tap()
        pickAppUnicode(query: query, codepoint: codepoint)
        app.buttons["layer.save"].firstMatch.tap()
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        XCTAssertNotEqual(hold.value as? String, "Off", "The key keeps its new hold choice")
    }

    /// The retained query, read where it is shown: with the toolbar hidden,
    /// U reopens search to read it, then hides it again.
    func assertRetainedKeyboardQuery(_ expected: String, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), file: file, line: line)
        guard toggle.value as? String == "off" else {
            XCTAssertTrue(search.waitUntilValueEquals(expected), message, file: file, line: line)
            return
        }
        XCTAssertFalse(search.exists, "The toolbar is hidden", file: file, line: line)
        toggle.tap()
        XCTAssertTrue(toggle.waitUntilValueEquals("on"), file: file, line: line)
        XCTAssertTrue(search.waitUntilValueEquals(expected), message, file: file, line: line)
        toggle.tap()
        XCTAssertTrue(toggle.waitUntilValueEquals("off"), file: file, line: line)
        assertHostTypingPanel(file: file, line: line)
    }

    func assertFavoritesKeyImmediatelyPrecedesSpace(file: StaticString = #filePath, line: UInt = #line) {
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

    func setKeyboardFullAccess(_ enabled: Bool) {
        enableUniboardInSettings(openingSettings: true)
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let row = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Uniboard")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let access = settings.switches["Allow Full Access"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        let value = enabled ? "1" : "0"
        // A tap on the switch's centre can miss it; tap its knob, and once more if nothing changed.
        for _ in 0..<2 where access.value as? String != value {
            access.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -30, dy: 0)).tap()
            if enabled {
                // The confirmation can belong to Settings or to SpringBoard.
                let allowLabel = NSPredicate(format: "label == 'Allow'")
                let allow = settings.alerts.buttons.matching(allowLabel).firstMatch
                let systemAllow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(allowLabel).firstMatch
                if allow.waitForExistence(timeout: 3) { allow.tap() } else if systemAllow.exists { systemAllow.tap() }
            }
            if access.waitUntilValueEquals(value, timeout: 2) { break }
        }
        XCTAssertTrue(access.waitUntilValueEquals(value))
    }

    func saveKeyboardFavoriteFixture(section: String, query: String, identifier: String,
                                     input: XCUIElement, context: String) {
        openUnicodeBrowse()
        selectKeyboardSection(section)
        enterKeyboardQuery(query)
        let item = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        XCTAssertTrue(item.isHittable)
        item.press(forDuration: 1)
        saveInspectedTextToFavorites(input: input, context: context)
        XCTAssertEqual(input.value as? String, context)
        app.buttons["keyboard.properties.close"].tap()
        let abc = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
        XCTAssertTrue(abc.waitForExistence(timeout: 5))
        abc.tap()
        assertHostTypingPanel()
        XCTAssertEqual(input.value as? String, context)
    }

    func selectSymbolBoard(_ boardID: String, input: XCUIElement, context: String, returnToTyping: Bool = false) {
        let footer = app.buttons["keyboard.openFavorites"].firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        if footer.value as? String != "favorites" { footer.tap() }
        let tab = app.buttons["keyboard.pages.tab.\(boardID)"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        XCTAssertTrue(tab.waitUntilSelected())
        XCTAssertEqual(input.value as? String, context, "Opening a page must not type into the host")
        if returnToTyping {
            XCTAssertTrue(footer.waitUntilValueEquals("favorites"))
            footer.tap()
            assertHostTypingPanel()
        }
    }

    func saveInspectedTextToFavorites(input: XCUIElement, context: String) {
        let save = app.buttons["keyboard.properties.favorite"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        if save.value as? String != "saved" { save.tap() }
        XCTAssertTrue(save.waitUntilValueEquals("saved"))
        XCTAssertEqual(input.value as? String, context, "Saving never inserts the inspected Unicode text")
    }

    func swipeSymbolPage(left: Bool, file: StaticString = #filePath, line: UInt = #line) {
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

    func waitForSymbolPage(_ id: String) -> Bool {
        let tab = app.buttons["keyboard.pages.tab.\(id)"].firstMatch
        let pager = app.descendants(matching: .any)["keyboard.pages.pager"].firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            tab.exists && tab.isSelected && pager.exists && (pager.value as? String) == tab.label
        }, object: app)
        return XCTWaiter.wait(for: [settled], timeout: 5) == .completed
    }

    func symbolBoardKey(_ text: String, typing: Bool = false) -> XCUIElement {
        let prefix = typing ? "keyboard.typing.favorite." : "keyboard.board."
        let points = text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", prefix, ", " + points)).firstMatch
    }

    func inspectSymbolBoardKey(_ key: XCUIElement, optionCount: Int,
                               input: XCUIElement, context: String) {
        chooseHeldKeyboardOption(key, optionCount: optionCount, selectedIndex: optionCount,
                                 extraActions: 1)
        XCTAssertTrue(app.buttons["keyboard.properties.close"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, context, "Selecting Inspect from a held key must never insert its original or variants")
    }

    func chooseHeldKeyboardOption(_ key: XCUIElement, optionCount: Int, selectedIndex: Int,
                                  extraActions: Int = 1) {
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        guard let root = measuredKeyboardSurfaceFrame(), usableHeightFrame(key.frame), app.frame.contains(key.frame) else {
            XCTFail("A hold-and-slide needs the actual visible key and keyboard root"); return
        }
        // The native popup has original/variants then Inspect. Choose a cell
        // with one continuous real held gesture.
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

    func assertRecentKeycaps(in grid: XCUIElement, referenceWidth: CGFloat,
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

    func assertExpandedSymbolPageHasNoDigits(file: StaticString = #filePath, line: UInt = #line) {
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

    func usableHeightFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    func measuredKeyboardSurfaceFrame() -> CGRect? {
        let surface = app.descendants(matching: .any)["keyboard.surface"].firstMatch
        guard surface.exists, usableHeightFrame(surface.frame), app.frame.insetBy(dx: -1, dy: -1).contains(surface.frame) else { return nil }
        return surface.frame
    }

    func measuredKeyboardHeight() -> Int? {
        measuredKeyboardSurfaceFrame().map { Int($0.height.rounded()) }
    }

    func settleKeyboardOrientation(_ orientation: UIDeviceOrientation, toolbarVisible: Bool = true) {
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

    func assertCompactKeyboardGeometry(_ mode: String, input: XCUIElement, searching: Bool,
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
        // Mirrors KeyboardLayoutPolicy.metrics on iPhone portrait: search (and inspection
        // opened from search) is 7.75 key rows + 4 gaps + 18 chrome (key * 7.75 + 34 ≈ 355);
        // browsing Unicode adds two rows to at most 4 key rows (key * 7 + 30 ≈ 320).
        // The text preview row is off in these tests.
        let key: CGFloat = 36 * 1.15
        let portrait = app.frame.height > app.frame.width
        // A snapshot, because the element can vanish between `exists` and `value`.
        let mode = (try? app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.snapshot())?.value as? String
        let portraitSearch = portrait && (searching || inspecting || mode == "query")
        let portraitBrowse = portrait && (mode == "unicode" || mode == "inspection")
        let maximum: CGFloat = effectiveExpected
            ?? (pad ? 396 : portraitSearch ? key * 7.75 + 34 : portraitBrowse ? key * 7 + 30 : 280)
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

    func assertKeyboardHasNoEditionSelector() {
        for id in ["keyboard.edition", "keyboard.edition.latest", "keyboard.edition.previous",
                   "keyboard.edition.older", "keyboard.edition.draft"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists,
                           "Edition selection belongs only to app Settings")
        }
    }

    func selectKeyboardSection(_ section: String) {
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

    func assertValueRemainsAfterRelease(_ element: XCUIElement, equals expected: String,
                                               file: StaticString = #filePath, line: UInt = #line) {
        let changedAfterRelease = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !element.exists || element.value as? String != expected
        }, object: element)
        changedAfterRelease.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changedAfterRelease], timeout: 0.6), .completed,
                       "A released delete press must not keep editing", file: file, line: line)
        XCTAssertEqual(element.value as? String, expected, file: file, line: line)
    }

    func openAppPages() {
        if app.navigationBars["Try Uniboard"].exists {
            restoreEnglishKeyboard()
            let back = app.navigationBars["Try Uniboard"].buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        dismissAppSearchKeyboard()
        selectAppTab("Keyboard")
        for _ in 0..<3 {
            let back = app.navigationBars.buttons["Keyboard"].firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTAssertTrue(app.navigationBars["Keyboard"].waitForExistence(timeout: 5))
    }

    /// Favorites is the first page under the app's Keyboard tab.
    func openAppFavorites() {
        openAppPages()
        let favorites = app.buttons["pages.page.migrated-favorites"].firstMatch
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
    }

    /// The Favorites page opens on its canvas; Saved's list is behind List.
    func openAppSavedFavorites() {
        openAppFavorites()
        let savedList = app.buttons["page.list"].firstMatch
        XCTAssertTrue(savedList.waitForExistence(timeout: 5))
        savedList.tap()
    }

    /// Creates a page in the app and opens it; returns its row in Keyboard.
    func createAppPage(_ name: String) -> XCUIElement {
        openAppPages()
        app.buttons["pages.new"].firstMatch.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name)
        app.alerts.buttons["Create"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "pages.page.", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        return row
    }

    func addAppPageKey(query: String, codepoint: String) {
        let add = app.buttons["page.addUnicode"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        pickAppUnicode(query: query, codepoint: codepoint)
    }

    func pickAppUnicode(query: String, codepoint: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(query)
        // Results reload while typing; wait for the exact row to settle.
        let result = app.buttons["picker.\(codepoint)"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Expected \(codepoint) for \(query)")
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        result.tap()
        XCTAssertTrue(field.waitUntilAbsent())
    }

    /// Removes pages an earlier, interrupted run may have left, so ★ opens Favorites again.
    func deleteAppPages(named name: String) {
        openAppPages()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "pages.page.", name))
        for _ in 0..<5 where rows.firstMatch.exists {
            deleteAppPage(app.buttons[rows.firstMatch.identifier].firstMatch)
        }
    }

    func deleteAppPage(_ row: XCUIElement) {
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(row.waitUntilAbsent())
    }

    /// Right after launch the floating tab bar can still be settling and drop
    /// or misdirect a tap, so tap until the tab is selected or its page shows.
    func selectAppTab(_ title: String) {
        let tab = appTab(title)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing the \(title) tab")
        for _ in 0..<4 {
            tab.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.appTab(title).isSelected || self.app.navigationBars[title].exists
            }, object: app)
            if XCTWaiter.wait(for: [selected], timeout: 2) == .completed { return }
        }
    }

    func appTab(_ title: String) -> XCUIElement {
        // iPhone retains the classic TabBar. iPadOS 27 exposes each floating
        // tab as a _UIFloatingTabBarItemCell with the same exact visible label.
        let legacy = app.tabBars.buttons[title].firstMatch
        if legacy.exists { return legacy }
        let floating = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if floating.exists { return floating }
        return app.buttons[title].firstMatch
    }

    /// Unifont and the other preview basics download on demand.
    func ensurePreviewBasics() {
        openAppSettings()
        let link = app.buttons["fontDownloads"].firstMatch
        revealByScrolling(link, in: app)
        link.tap()
        let pack = app.descendants(matching: .any)["fontDownloads.pack.preview-basics"].firstMatch
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        let ready = pack.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Available offline")).firstMatch
        if !ready.exists {
            app.buttons["fontDownloads.download.preview-basics"].firstMatch.tap()
            let failure = pack.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@", "Couldn’t download or verify this pack.")).firstMatch
            let message = app.staticTexts["fontDownloads.message"].firstMatch
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                ready.exists || failure.exists || (message.exists && (
                    message.label.hasPrefix("Shared font storage is unavailable.") ||
                    message.label.hasPrefix("Download cancelled.") ||
                    message.label.hasPrefix("The font download could not be verified.")))
            }, object: pack)
            let completed = XCTWaiter.wait(for: [finished], timeout: 180) == .completed
            let available = ready.exists
            if !completed || !available { attachDiagnostics("Preview basics download failed or timed out") }
            XCTAssertTrue(completed && available, "Preview basics must be available offline, not merely finish downloading")
        }
        app.navigationBars["Font Downloads"].buttons.firstMatch.tap()
    }

    func appUnicodeFontsSwitch() -> XCUIElement {
        openAppSettings()
        let fonts = app.switches["extraUnicodeFonts"].firstMatch
        revealByScrolling(fonts, in: app)
        return fonts
    }

    func setAppUnicodeFonts(_ enabled: Bool) {
        let fonts = appUnicodeFontsSwitch()
        let value = enabled ? "1" : "0"
        if fonts.value as? String != value { tapSwitch(fonts) }
        XCTAssertTrue(fonts.waitUntilValueEquals(value))
    }

    func setAppUCSUR(_ enabled: Bool) {
        openAppSettings()
        let ucsur = app.switches["showUCSUR"].firstMatch
        revealByScrolling(ucsur, in: app)
        let value = enabled ? "1" : "0"
        if ucsur.value as? String != value { tapSwitch(ucsur) }
        XCTAssertTrue(ucsur.waitUntilValueEquals(value))
    }

    func setAppPrefersUCSUR(_ enabled: Bool) {
        openAppSettings()
        let prefer = app.switches["preferUCSUR"].firstMatch
        revealByScrolling(prefer, in: app)
        let value = enabled ? "1" : "0"
        if prefer.value as? String != value { tapSwitch(prefer) }
        XCTAssertTrue(prefer.waitUntilValueEquals(value))
    }

    /// A Form toggle row spans its label, which does not flip the switch;
    /// tap the trailing switch itself, as a person would.
    func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
    }

    /// Keyboard › Main Keyboard: the main keyboard's editor.
    func openMainKeyboardEditor() {
        openAppPages()
        let keyboard = app.buttons["pages.keyboard"].firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mainKeyboard.keys"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Keyboard › Symbol Keys: the symbol keys' own swipe and hold choices.
    func openSymbolKeys() {
        openAppPages()
        let symbolKeys = app.buttons["pages.symbolKeys"].firstMatch
        XCTAssertTrue(symbolKeys.waitForExistence(timeout: 5))
        symbolKeys.tap()
        XCTAssertTrue(app.navigationBars["Symbol Keys"].waitForExistence(timeout: 5))
    }

    /// Standard Layout: the number row and the layout's own rows.
    func resetMainKeyboard() {
        openMainKeyboardEditor()
        app.buttons["mainKeyboard.more"].firstMatch.tap()
        let reset = app.buttons["mainKeyboard.reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        // Already standard: Standard Layout is disabled, so close the menu instead.
        if reset.isEnabled { reset.tap() } else {
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func setAppTextPreview(_ enabled: Bool) {
        openAppSettings()
        let preview = app.switches["showKeyboardTextPreview"].firstMatch
        revealByScrolling(preview, in: app)
        let value = enabled ? "1" : "0"
        if preview.value as? String != value { tapSwitch(preview) }
        // Right after launch the tap can land while Settings is still sliding in.
        if !preview.waitUntilValueEquals(value, timeout: 2) { tapSwitch(preview) }
        XCTAssertTrue(preview.waitUntilValueEquals(value))
    }

    func setAppAutoCapitalization(_ mode: String) {
        openAppSettings()
        let row = app.buttons["keyboardAutoCapitalization"].firstMatch
        revealByScrolling(row, in: app)
        row.tap()
        let option = app.buttons["autoCapitalization.\(mode)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        if !option.isSelected { option.tap() }
        XCTAssertTrue(option.waitUntilSelected())
        app.navigationBars["Auto-Capitalization"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func setAppCollapseKey(_ enabled: Bool) {
        openAppSettings()
        let collapse = app.switches["showKeyboardCollapseKey"].firstMatch
        revealByScrolling(collapse, in: app)
        let value = enabled ? "1" : "0"
        if collapse.value as? String != value { tapSwitch(collapse) }
        XCTAssertTrue(collapse.waitUntilValueEquals(value))
    }

    /// Settings live only in the app, and results are always in code point
    /// order, so the keyboard has no options menu at all.
    func assertKeyboardHasNoSettingsMenu(file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["keyboard.options", "keyboard.edition", "keyboard.unicodeFonts", "keyboard.showCollapseKey", "keyboard.inspectLast",
                           "keyboard.saveLast", "keyboard.openCompanionApp", "keyboard.openCompanionApp.guidance"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].firstMatch.exists, file: file, line: line)
        }
        XCTAssertFalse(app.buttons["Save to page"].firstMatch.exists, file: file, line: line)
    }

    // MARK: DEBUG cursor probe (docs/preview-cursor-findings.md)

    /// Measurement only, not a regression test: pairs each step of the
    /// keyboard's DEBUG-only cursor probe (KeyboardCursorProbe) with the
    /// host's own value, in a UITextView, a UITextField and a Safari
    /// textarea. Results are printed as CURSORPROBE lines.
    // MARK: Preview cursor (design/preview-cursor rev. 2)

    func openPreviewCursorFixture(_ sentinel: String) throws -> (XCUIElement, XCUIElement, String) {
        try requirePhoneKeyboardIntegration()
        app.launchArguments = Self.textPreviewLaunchArguments
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard() }
        let fixtures = [
            "previewfixture1": "Cafe\u{301} \u{5D1}\u{5BC}\u{5E8}\u{5D0} \u{1F469}\u{200D}\u{1F4BB}",
            "previewfixture2": "\u{5E9}\u{5DC}\u{5D5}\u{5DD} abc"
        ]
        let fixture = try XCTUnwrap(fixtures[sentinel])
        let input = openSystemKeyboardHost(initialText: sentinel, unicodeBrowse: false)
        // The DEBUG keyboard seeds text a test can't type (KeyboardCursorProbe).
        let seed = app.buttons["keyboard.debug.cursorProbe"].firstMatch
        XCTAssertTrue(seed.waitForExistence(timeout: 10))
        seed.tap()
        XCTAssertTrue(input.waitUntilValueEquals(fixture, timeout: 15), "Seeded: \(String(describing: input.value))")
        let preview = app.descendants(matching: .any)["keyboard.textPreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        // The probe's own insert isn't a host callback: one typed and deleted
        // marker refreshes the preview with the seeded line.
        XCTAssertEqual(markCursor(input: input, original: fixture), fixture.utf16.count)
        sleep(1)
        return (input, preview, fixture)
    }

    /// Taps the preview every 10 points from `start`, marks where the app's
    /// cursor went and asserts it is a whole-character boundary. Only if some
    /// `required` group (any one offset of it) was missed does it tap the
    /// points 5 between, which gives the old 5-point sweep. Returns the
    /// UTF-16 offsets.
    func sweepPreviewTaps(input: XCUIElement, preview: XCUIElement, fixture: String,
                          from start: CGFloat, through end: CGFloat, required: [Set<Int>]) -> Set<Int> {
        var boundaries: Set<Int> = [0]
        var offset = 0
        for character in fixture { offset += character.utf16.count; boundaries.insert(offset) }
        var landed: Set<Int> = []
        for pass in 0..<2 {
            if pass == 1 && required.allSatisfy({ !$0.isDisjoint(with: landed) }) { break }
            for x in stride(from: start + CGFloat(pass) * 5, through: end, by: 10) {
                tapPreview(preview, at: x)
                guard let position = markCursor(input: input, original: fixture) else {
                    XCTFail("Tap at x \(x) left the text changed: \(String(describing: input.value))")
                    return landed
                }
                XCTAssertTrue(boundaries.contains(position), "Tap at x \(x) landed inside a cluster at \(position)")
                landed.insert(position)
            }
        }
        return landed
    }

    func tapPreview(_ preview: XCUIElement, at x: CGFloat) {
        // Never within the 300 ms after a key touch-up (§5).
        usleep(400_000)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: x, dy: 0)).tap()
        usleep(700_000)
    }

    /// Types one marker letter at the app's cursor, reads where it went
    /// (UTF-16 offset in `original`), and deletes it again.
    func markCursor(input: XCUIElement, original: String) -> Int? {
        app.buttons["keyboard.typing.key.q"].firstMatch.tap()
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", original), object: input)
        _ = XCTWaiter.wait(for: [typed], timeout: 3)
        let value = input.value as? String ?? ""
        let a = Array(original.utf16), b = Array(value.utf16)
        var position: Int?
        if b.count == a.count + 1 {
            var index = 0
            while index < a.count && a[index] == b[index] { index += 1 }
            if Array(b[(index + 1)...]) == Array(a[index...]) { position = index }
        }
        app.buttons["keyboard.typing.delete"].firstMatch.tap()
        XCTAssertTrue(input.waitUntilValueEquals(original), "Marker removed: \(String(describing: input.value))")
        return position
    }

    func requirePhoneKeyboardIntegration() throws {
        try requireKeyboardIntegration()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                      "This case verifies the phone keyboard template.")
    }

    var keyboardIntegrationEnabled: Bool {
        ProcessInfo.processInfo.environment["UNIBOARD_KEYBOARD_INTEGRATION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--keyboard-integration")
    }

    func requireKeyboardIntegration() throws {
        try XCTSkipUnless(keyboardIntegrationEnabled, "Set UNIBOARD_KEYBOARD_INTEGRATION=1 in the UI test runner to exercise the installed system keyboard.")
    }

    /// `afterSetUpLaunch`: the caller has not touched the app since setUp
    /// launched it, so unless Settings opens here that launch is as fresh as
    /// a relaunch would be.
    func openSystemKeyboardHost(initialText: String = "", unicodeBrowse: Bool = true, searchBarVisible: Bool = false,
                                afterSetUpLaunch: Bool = false) -> XCUIElement {
        let openedSettings = enableUniboardInSettings()
        if openedSettings || !afterSetUpLaunch || app.launchArguments != Self.setUpLaunchArguments {
            // Reload UIKit's enabled-keyboard configuration after changing it in
            // Settings, and start from a settled foreground navigation state.
            app.terminate()
            app.launch()
        }
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
            // The tests leave English up; switch only if it is not showing.
            let systemGlobe = app.buttons["Next keyboard"].firstMatch
            let anyKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.uniboardKeyboardIsVisible() || self.systemKeyboardGlobeIsVisible(systemGlobe)
            }, object: app)
            _ = XCTWaiter.wait(for: [anyKeyboard], timeout: 3)
            let englishLetters = app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", "q")).firstMatch
            if uniboardKeyboardIsVisible() || !systemKeyboardGlobeIsVisible(systemGlobe) || !englishLetters.exists {
                restoreEnglishKeyboard()
            }
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
            // selectKeyboardSection opens Unicode browse first.
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
        // Inspect/clear retained data through the real U control (which opens
        // search with its keys), then return to English typing with U for
        // callers testing ordinary English. Browse mode already shows search;
        // typing mode opens it only if a query may be left from earlier.
        guard unicodeBrowse || Self.keyboardQueryMayBeKept else { return input }
        ensureUnicodeToolbarVisible()
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        Self.keyboardQueryMayBeKept = false
        if let retainedQuery = search.value as? String, retainedQuery != "No query", !retainedQuery.isEmpty {
            let clear = app.buttons["keyboard.search.clear"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            clear.tap()
            XCTAssertTrue(search.waitUntilValueEquals("No query"))
            XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.exists, "Clearing keeps search and its keys open")
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

    func enterKeyboardQuery(_ query: String) {
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

    /// Set when a test types a query, which the keyboard keeps across
    /// sessions; cleared once openSystemKeyboardHost has seen or cleared it.
    static var keyboardQueryMayBeKept = true

    func typeKeyboardQueryKeys(_ text: String) {
        Self.keyboardQueryMayBeKept = true
        for key in text {
            let id = key == " " ? "keyboard.space" : "keyboard.query.\(key)"
            let queryKey = app.buttons[id].firstMatch
            XCTAssertTrue(queryKey.waitForExistence(timeout: 5), "Expected query key \(key): \(app.debugDescription)")
            queryKey.tap()
        }
    }

    func reopenKeyboardSearch(expectedQuery: String) {
        ensureUnicodeToolbarVisible()
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitUntilValueEquals(expectedQuery), "Reopening must preserve the existing query")
    }

    func closeKeyboardSearch() {
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

    func assertHostTypingPanel(file: StaticString = #filePath, line: UInt = #line) {
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

    func openUnicodeBrowse() {
        ensureUnicodeToolbarVisible()
        let browse = app.descendants(matching: .any)["keyboard.openUnicode"].firstMatch
        if browse.exists {
            let input = app.textViews["keyboardTestInput"].firstMatch
            let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
            let host = input.value as? String
            let query = search.value as? String
            XCTAssertTrue(browse.waitUntilValueEquals("typing"))
            browse.tap()
            // Unicode opens search with its keys, never the browse grid.
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"))
            XCTAssertTrue(input.waitUntilValueEquals(host ?? ""), "Opening Unicode must preserve host text")
            XCTAssertTrue(search.waitUntilValueEquals(query ?? "No query"), "Opening Unicode must retain the local query")
        } else {
            let typing = app.descendants(matching: .any)["keyboard.openTyping"].firstMatch
            XCTAssertTrue(typing.waitForExistence(timeout: 5), "Expected the real Unicode/query/inspection panel")
            XCTAssertTrue(["unicode", "query", "inspection"].contains(typing.value as? String ?? ""))
        }
    }

    /// From English typing, U opens search with its own keys; the toolbar,
    /// search field and header delete exist only there. With a Unicode panel
    /// already open (or on symbol pages) U is left as it is or only shows the
    /// toolbar.
    func ensureUnicodeToolbarVisible() {
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String == "off" {
            let fromTyping = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.typing.key.")).firstMatch.exists
            toggle.tap()
            if fromTyping {
                XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"),
                              "U opens search with its own keys")
                XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
            }
        }
        XCTAssertTrue(toggle.waitUntilValueEquals("on"))
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitForExistence(timeout: 5))
    }

    /// English typing has no search field, so check the retained query the way
    /// a user would: U opens search showing it, and U again returns to English
    /// typing with the host unchanged.
    func assertRetainedQueryThroughU(_ expected: String, _ message: String = "",
                                     file: StaticString = #filePath, line: UInt = #line) {
        let input = app.textViews["keyboardTestInput"].firstMatch
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        let host = input.value as? String ?? ""
        XCTAssertTrue(toggle.waitUntilValueEquals("off"), "English typing keeps the Unicode toolbar hidden", file: file, line: line)
        XCTAssertFalse(search.exists, file: file, line: line)
        ensureUnicodeToolbarVisible()
        XCTAssertTrue(search.waitUntilValueEquals(expected), message, file: file, line: line)
        XCTAssertTrue(input.waitUntilValueEquals(host), "Opening search must not edit the host", file: file, line: line)
        toggle.tap()
        XCTAssertTrue(toggle.waitUntilValueEquals("off"), file: file, line: line)
        assertHostTypingPanel(file: file, line: line)
        XCTAssertTrue(input.waitUntilValueEquals(host), "Closing search with U must not edit the host", file: file, line: line)
    }

    func restoreEnglishKeyboard() {
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

    func assertKeyboardCharacterIsFullyVisible(_ character: XCUIElement, identifier: String,
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

    func assertLowerDeleteInKeyRow(_ identifier: String, beside referenceID: String,
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
        // The header delete belongs to the Unicode toolbar; with U off there is none.
        let header = app.buttons["keyboard.delete"].firstMatch
        if header.exists {
            XCTAssertGreaterThan(frame.minY, header.frame.maxY,
                                 "The lower control is separate from the retained header delete", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(frame.maxY, app.buttons["keyboard.space"].firstMatch.frame.minY,
                                 "The lower delete must fit above the existing footer without adding a row", file: file, line: line)
        XCTAssertTrue(lower.isHittable, file: file, line: line)
    }

    func assertHeaderDeleteAtTopRight(file: StaticString = #filePath, line: UInt = #line) {
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

    func assertKeyboardControlsAreVisible(isSearching: Bool,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let toolbarOn = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch.value as? String == "on"
        var identifiers = ["keyboard.toggleUnicodeToolbar", "keyboard.openFavorites", "keyboard.space", "keyboard.return"]
        if toolbarOn { identifiers += ["keyboard.search", "keyboard.delete"] }
        XCTAssertFalse(app.descendants(matching: .any)["keyboard.options"].firstMatch.exists, file: file, line: line)
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

    func assertHostEditorIsVisibleAboveKeyboard(_ input: XCUIElement,
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

    func assertKeyboardProperties(codepoints: String, nameContaining name: String) {
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

    func isInsideScrollViewport(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
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

    func isReadableInScrollViewport(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        guard element.exists && scrollView.exists else { return false }
        let frame = element.frame
        let viewport = scrollView.frame
        guard frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0,
              viewport.width > 0 && viewport.height > 0 else { return false }
        let visible = frame.intersection(viewport)
        guard !visible.isNull, visible.height >= min(frame.height, viewport.height) * 0.9 else { return false }
        return element.isHittable
    }

    func openAppSettings() {
        if app.navigationBars["Try Uniboard"].exists {
            restoreEnglishKeyboard()
            let back = app.navigationBars["Try Uniboard"].buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        dismissAppSearchKeyboard()
        selectAppTab("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    /// App Settings is a native Form, exposed as a collection view.
    func settingsList() -> XCUIElement {
        app.collectionViews["settingsForm"].firstMatch
    }

    func selectAppEdition(_ edition: String) {
        openAppSettings()
        let selector = app.descendants(matching: .any)["unicodeEdition"].firstMatch
        let settingsScroll = settingsList()
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
        selectAppTab("Explore")
        XCTAssertFalse(app.descendants(matching: .any)["unicodeEdition"].firstMatch.exists)
    }

    func assertCharacterProperty(_ property: String, equals expected: String) {
        let element = app.descendants(matching: .any)["characterProperties.\(property)"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(element), expected)
    }

    func assertCharacterProperty(_ property: String, contains expected: String) {
        let element = app.descendants(matching: .any)["characterProperties.\(property)"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(element).localizedCaseInsensitiveContains(expected))
    }

    func dismissAppSearchKeyboard() {
        let done = app.buttons["Done"].firstMatch
        if done.exists && done.isHittable { done.tap() }
    }

    func assertControlValue(_ identifier: String, equals expected: String) {
        let control = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let matches = NSPredicate(format: "value == %@ OR label == %@", expected, expected)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: control)], timeout: 5), .completed,
            "Expected \(identifier) to expose \(expected), got \(accessibleText(control))")
    }

    func accessibleText(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    /// Set once Settings has shown Uniboard among the enabled keyboards. The
    /// simulator keeps that list for the whole test run.
    static var uniboardEnabledInSettings = false

    /// Makes sure Uniboard is an enabled keyboard. Returns whether Settings
    /// was opened; `openingSettings` always opens it at Keyboards.
    @discardableResult
    func enableUniboardInSettings(openingSettings: Bool = false) -> Bool {
        if Self.uniboardEnabledInSettings && !openingSettings { return false }
        defer { Self.uniboardEnabledInSettings = true }
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
        if existingKeyboard.exists { return true }

        let addKeyboard = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Add New Keyboard")).firstMatch
        revealByScrolling(addKeyboard, in: settings)
        addKeyboard.tap()
        let uniboard = settings.descendants(matching: .any)["Uniboard"].firstMatch
        revealByScrolling(uniboard, in: settings)
        uniboard.tap()
        XCTAssertTrue(existingKeyboard.waitForExistence(timeout: 5), "Uniboard should appear in the enabled system keyboard list")
        return true
    }

    func attachDiagnostics(_ name: String) {
        attachScreenshot(name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) — accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func attachScreenshot(_ name: String) {
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

    func tapSettingsItem(_ title: String, in settings: XCUIApplication) {
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

    func revealByScrolling(_ element: XCUIElement, in application: XCUIApplication) {
        // Virtualized native Settings cells can exist with an infinite,
        // zero-size frame. Never ask XCTest for such a hit point.
        func visible() -> Bool {
            let frame = element.frame
            return self.usableHeightFrame(frame) && application.frame.contains(frame) && element.isHittable
        }
        var scrolledPast = false, settled = false
        for _ in 0..<8 {
            if element.exists {
                let frame = element.frame
                if visible() { return }
                // A row already within the screen's height may still be sliding
                // in with a pushed page; let it settle instead of scrolling it away.
                if !settled, usableHeightFrame(frame), frame.minY >= application.frame.minY,
                   frame.maxY <= application.frame.maxY {
                    settled = true
                    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        element.exists && visible() }, object: element)
                    if XCTWaiter.wait(for: [ready], timeout: 2) == .completed { return }
                }
                // Earlier swipes can carry a short Settings page past the row;
                // scroll back toward it, even while it is briefly virtualized.
                if usableHeightFrame(frame) { scrolledPast = frame.minY < application.frame.minY }
            }
            if scrolledPast { application.swipeDown() } else { application.swipeUp() }
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

    func systemKeyboardGlobeIsVisible(_ globe: XCUIElement) -> Bool {
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

    func uniboardKeyboardIsVisible() -> Bool {
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

    func waitForVisibleUniboardAfterSwitch(input: XCUIElement, expectedHost: String) {
        let visible = NSPredicate { _, _ in self.uniboardKeyboardIsVisible() }
        let initial = XCTNSPredicateExpectation(predicate: visible, object: app)
        var shown = XCTWaiter.wait(for: [initial], timeout: 5) == .completed
        let systemGlobe = app.buttons["Next keyboard"].firstMatch
        if !shown, systemKeyboardGlobeIsVisible(systemGlobe) {
            // Cold start: the first extension launch after install can drop
            // the pick and leave the system keyboard up. Re-pick once.
            attachScreenshot("System keyboard still up after Uniboard pick; one globe retry")
            XCTAssertEqual(input.value as? String, expectedHost)
            systemGlobe.press(forDuration: 1)
            dismissKeyboardSwitcherTipIfPresent()
            let item = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Uniboard")).firstMatch
            if item.waitForExistence(timeout: 3) { item.tap() }
            let retried = XCTNSPredicateExpectation(predicate: visible, object: app)
            shown = XCTWaiter.wait(for: [retried], timeout: 15) == .completed
        }
        if !shown {
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

    func selectUniboardKeyboard(input: XCUIElement, expectedHost: String) {
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
    func dismissKeyboardSwitcherTipIfPresent() -> Bool {
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

    func searchUnicode(_ query: String) {
        search(query, fieldIdentifier: "unicodeSearch")
    }

    func search(_ query: String, fieldIdentifier: String) {
        let field = app.descendants(matching: .any)[fieldIdentifier].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        field.typeText(query)
    }

    func character(_ codepoint: String) -> XCUIElement {
        app.buttons["character-\(codepoint)"].firstMatch
    }

    @discardableResult
    func assertCharacterVisible(
        _ codepoint: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let result = character(codepoint)
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Expected \(codepoint) in character results", file: file, line: line)
        return result
    }
}

extension XCUIElement {
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

    func waitUntilFrame(timeout: TimeInterval = 5, _ condition: @escaping (CGRect) -> Bool) -> Bool {
        let predicate = NSPredicate { object, _ in (object as? XCUIElement).map { $0.exists && condition($0.frame) } ?? false }
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
