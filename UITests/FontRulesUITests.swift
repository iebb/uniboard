import XCTest
import UIKit

/// Settings › Font Rules: adding, editing, reordering and removing rules, the
/// Extra Unicode Fonts switch pausing them, and Try Text. Fonts come from
/// the DEBUG library fixture (Papyrus and Chalkduster as installed faces).
@MainActor
final class FontRulesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(ruleFixture: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UniboardFontLibraryFixture", "installed"]
        if let ruleFixture { app.launchArguments += ["-UniboardFontRuleFixture", ruleFixture] }
        app.launch()
    }

    // MARK: Tests

    func testAddEditReorderAndRemoveRules() {
        launch()
        setUnicodeFonts(true)
        let entry = app.buttons["fontRules"].firstMatch
        XCTAssertTrue(accessibleText(entry).contains("None") || entry.label.contains("None"), "No rules: \(entry.label)")
        openFontRules()
        XCTAssertTrue(element("fontRules.empty").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["fontRules.edit"].exists, "Edit appears only when rules exist")

        // Add a code point rule.
        addRule("fontRules.add.codePoint", label: "Code Point")
        typeInto("fontRuleEditor.codePoint", "U+0041")
        XCTAssertTrue(element("fontRuleEditor.summary").waitForExistence(timeout: 5))
        XCTAssertTrue(element("fontRuleEditor.chooseFont").waitForExistence(timeout: 5), "A valid selector without a font asks for one")
        XCTAssertFalse(app.buttons["fontRuleEditor.save"].isEnabled)
        chooseFont("Papyrus")
        save()
        let codePointRow = row(containing: "Latin Capital Letter A")
        XCTAssertTrue(codePointRow.waitForExistence(timeout: 5))
        XCTAssertTrue((codePointRow.value as? String ?? "").contains("Papyrus"))
        XCTAssertTrue(element("fontRules.section.codePoints").exists)

        // A duplicate is refused with its own message.
        addRule("fontRules.add.codePoint", label: "Code Point")
        typeInto("fontRuleEditor.codePoint", "A")
        XCTAssertTrue(element("fontRuleEditor.duplicate").waitForExistence(timeout: 5))
        XCTAssertEqual(element("fontRuleEditor.duplicate").label, "A rule for this code point already exists.")
        XCTAssertFalse(app.buttons["fontRuleEditor.save"].isEnabled)
        // A joined character is more than one code point; it is never silently shortened.
        typeInto("fontRuleEditor.codePoint", "e\u{301}")
        XCTAssertTrue(element("fontRuleEditor.error").waitForExistence(timeout: 5))
        XCTAssertEqual(element("fontRuleEditor.error").label, "Enter one code point. This text contains more than one.")
        app.buttons["fontRuleEditor.cancel"].tap()
        let discard = app.buttons["fontRuleEditor.discard"].firstMatch.exists ? app.buttons["fontRuleEditor.discard"].firstMatch
            : app.buttons["Discard Changes"].firstMatch
        _ = app.buttons["Discard Changes"].firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Unsaved changes ask before discarding")
        discard.tap()
        XCTAssertTrue(app.navigationBars["Font Rules"].waitForExistence(timeout: 5))

        // Two equal-width ranges; the later one wins ties.
        addRange("U+0041", "U+005A", font: "Chalkduster")
        addRange("U+0061", "U+007A", font: "Papyrus")
        let upper = row(containing: "U+0041–U+005A")
        let lower = row(containing: "U+0061–U+007A")
        XCTAssertTrue(upper.waitForExistence(timeout: 5) && lower.waitForExistence(timeout: 5))
        XCTAssertTrue(upper.label.contains("26 code points"))
        XCTAssertLessThan(upper.frame.minY, lower.frame.minY, "Rules keep their saved order")

        // Reorder within Ranges.
        app.buttons["fontRules.edit"].tap()
        XCTAssertTrue(element("fontRules.rangeOrderCaption").waitForExistence(timeout: 5))
        drag(lower, above: upper)
        XCTAssertTrue(lower.waitUntilFrame { $0.minY < upper.frame.minY }, "Dragging moves the rule up")
        app.buttons["fontRules.edit"].tap()
        XCTAssertTrue(element("fontRules.rangeOrderCaption").waitUntilAbsent())
        attachScreenshot("Font Rules after reordering ranges")

        // The order is saved: it survives leaving and reopening.
        app.navigationBars["Font Rules"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fontRules"].label.contains("3") || accessibleText(app.buttons["fontRules"]).contains("3"))
        openFontRules()
        XCTAssertTrue(row(containing: "U+0061–U+007A").waitForExistence(timeout: 5))
        XCTAssertLessThan(row(containing: "U+0061–U+007A").frame.minY, row(containing: "U+0041–U+005A").frame.minY)

        // Edit: change the code point rule's font.
        row(containing: "Latin Capital Letter A").tap()
        XCTAssertTrue(app.navigationBars["Edit Rule"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("fontRuleEditor.kind").exists, "The kind is fixed when editing")
        chooseFont("Chalkduster")
        save()
        XCTAssertTrue(row(containing: "Latin Capital Letter A").waitUntilValueContains("Chalkduster"))

        // Remove by swipe, then from the editor.
        let removed = row(containing: "U+0061–U+007A")
        removed.swipeLeft()
        let remove = app.buttons["Remove Rule"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(removed.waitUntilAbsent())
        row(containing: "U+0041–U+005A").tap()
        let editorRemove = app.buttons["fontRuleEditor.remove"].firstMatch
        XCTAssertTrue(editorRemove.waitForExistence(timeout: 5))
        editorRemove.tap()
        XCTAssertTrue(row(containing: "U+0041–U+005A").waitUntilAbsent())
        XCTAssertFalse(element("fontRules.section.ranges").exists)
        XCTAssertTrue(row(containing: "Latin Capital Letter A").exists)
    }

    func testExtraUnicodeFontsOffPausesRulesAndEditingNeverTurnsItOn() {
        launch(ruleFixture: "sample")
        setUnicodeFonts(false)
        openFontRules()
        let notice = element("fontRules.notice.text")
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "Rules apply only when Extra Unicode Fonts is on.")
        XCTAssertEqual(app.buttons["fontRules.notice.turnOn"].label, "Turn on Extra Unicode Fonts")
        // Paused, not deleted: both rules are still listed.
        XCTAssertTrue(app.buttons["fontRules.row.fixture-a"].exists)
        XCTAssertTrue(app.buttons["fontRules.row.fixture-latin"].exists)
        typeInto("fontRules.tryText.field", "A")
        XCTAssertTrue(element("fontRules.tryText.result.0").waitUntilValueContains("Using default fonts"))

        // Editing while off saves, and leaves the switch off.
        app.buttons["fontRules.row.fixture-latin"].tap()
        XCTAssertTrue(app.navigationBars["Edit Rule"].waitForExistence(timeout: 5))
        chooseFont("Papyrus")
        save()
        XCTAssertTrue(app.buttons["fontRules.row.fixture-latin"].waitUntilValueContains("Papyrus"))
        XCTAssertTrue(element("fontRules.notice").exists, "Saving a rule never turns Extra Unicode Fonts on")
        attachScreenshot("Font Rules paused while Extra Unicode Fonts is off")

        // Turn On is the explicit way to apply them.
        app.buttons["fontRules.notice.turnOn"].tap()
        XCTAssertTrue(element("fontRules.notice").waitUntilAbsent())
        XCTAssertTrue(element("fontRules.tryText.result.0").waitUntilValueContains("Using Papyrus"))
        app.navigationBars["Font Rules"].buttons.firstMatch.tap()
        let fonts = app.switches["extraUnicodeFonts"].firstMatch
        revealByScrolling(fonts)
        XCTAssertTrue(fonts.waitUntilValueEquals("1"))
        setUnicodeFonts(false)
    }

    func testTryTextNamesTheFontForEachCharacter() {
        launch(ruleFixture: "sample")
        setUnicodeFonts(true)
        openFontRules()
        typeInto("fontRules.tryText.field", "AB")
        let summary = element("fontRules.tryText.summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Multiple fonts used")
        let first = element("fontRules.tryText.result.0"), second = element("fontRules.tryText.result.1")
        XCTAssertTrue(first.waitUntilValueContains("Using Papyrus, Code point rule"))
        XCTAssertTrue(second.waitUntilValueContains("Using Chalkduster, Unicode block rule Basic Latin"))
        attachScreenshot("Try Text shows one result per character when fonts differ")

        // One shared result is one row naming the font.
        typeInto("fontRules.tryText.field", "BC")
        XCTAssertTrue(summary.waitUntilAbsent())
        XCTAssertTrue(first.waitUntilValueContains("Using Chalkduster"))
        XCTAssertEqual(first.label, "BC")
        XCTAssertFalse(second.exists)

        // A character no rule covers uses the default fonts.
        typeInto("fontRules.tryText.field", "→")
        XCTAssertTrue(first.waitUntilValueContains("Using default fonts, Default fonts"))
        // Joined characters stay one row, with the note.
        typeInto("fontRules.tryText.field", "e\u{301}")
        XCTAssertTrue(element("fontRules.tryText.joinedNote").waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
    }

    // MARK: Steps

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func row(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "fontRules.row.", text)).firstMatch
    }

    private func openSettings() {
        let tab = app.tabBars.buttons["Settings"].firstMatch.exists ? app.tabBars.buttons["Settings"].firstMatch : app.buttons["Settings"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        for _ in 0..<4 where !app.navigationBars["Settings"].exists {
            tab.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func setUnicodeFonts(_ enabled: Bool) {
        openSettings()
        let fonts = app.switches["extraUnicodeFonts"].firstMatch
        revealByScrolling(fonts)
        let value = enabled ? "1" : "0"
        if fonts.value as? String != value {
            fonts.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
        }
        XCTAssertTrue(fonts.waitUntilValueEquals(value))
    }

    private func openFontRules() {
        if !app.navigationBars["Settings"].exists { openSettings() }
        let entry = app.buttons["fontRules"].firstMatch
        revealByScrolling(entry)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Font Rules"].waitForExistence(timeout: 5))
    }

    private func addRule(_ identifier: String, label: String) {
        let add = app.buttons["fontRules.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let item = app.buttons[identifier].firstMatch.exists ? app.buttons[identifier].firstMatch : app.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.navigationBars["Add Rule"].waitForExistence(timeout: 5))
    }

    private func addRange(_ from: String, _ to: String, font: String) {
        addRule("fontRules.add.range", label: "Range")
        let kind = element("fontRuleEditor.kind")
        if kind.exists, !app.textFields["fontRuleEditor.from"].exists { kind.buttons["Range"].tap() }
        typeInto("fontRuleEditor.from", from)
        typeInto("fontRuleEditor.to", to)
        XCTAssertTrue(element("fontRuleEditor.summary").waitForExistence(timeout: 5))
        chooseFont(font)
        let coverage = element("fontRuleEditor.coverage")
        XCTAssertTrue(coverage.waitForExistence(timeout: 10))
        XCTAssertTrue(coverage.label.hasPrefix("Supports ") && coverage.label.hasSuffix(" of 26 code points"), coverage.label)
        save()
    }

    private func typeInto(_ identifier: String, _ text: String) {
        let field = app.textFields[identifier].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    private func chooseFont(_ postScriptName: String) {
        let link = app.buttons["fontRuleEditor.font"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.isEnabled)
        link.tap()
        XCTAssertTrue(app.navigationBars["Preferred Font"].waitForExistence(timeout: 5))
        // The picker lists every family; search by PostScript name, and open
        // the family when the name matches it rather than one style.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The search field shows without pulling the list")
        search.tap()
        search.typeText(postScriptName)
        let face = app.buttons["fontPicker.face.\(postScriptName)"].firstMatch
        let family = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "fontPicker.family.")).firstMatch
        if !face.waitForExistence(timeout: 10), family.exists { family.tap() }
        if !face.waitForExistence(timeout: 30) {
            attachScreenshot("Preferred Font without \(postScriptName)")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Preferred Font hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("The installed fixture face \(postScriptName) is offered")
            return
        }
        XCTAssertTrue(element("fontPicker.section.yourFonts").exists || app.staticTexts["Your Fonts"].exists)
        face.tap()
        XCTAssertTrue(app.navigationBars["Preferred Font"].waitUntilAbsent())
        XCTAssertTrue(link.waitUntilValueContains(postScriptName) || link.label.contains(postScriptName))
    }

    private func save() {
        let save = app.buttons["fontRuleEditor.save"].firstMatch
        XCTAssertTrue(save.waitUntilEnabled())
        save.tap()
        XCTAssertTrue(app.navigationBars["Font Rules"].waitForExistence(timeout: 5))
        XCTAssertTrue(save.waitUntilAbsent())
    }

    /// Drags a row by its reorder handle (trailing edge, in Edit mode) to
    /// just above the target row.
    private func drag(_ row: XCUIElement, above target: XCUIElement) {
        let cell = app.cells.containing(.button, identifier: row.identifier).firstMatch
        let targetCell = app.cells.containing(.button, identifier: target.identifier).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5) && targetCell.exists)
        attachScreenshot("Font Rules in Edit mode")
        let handle = cell.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Reorder")).firstMatch
        let start = handle.exists ? handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : cell.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -22, dy: 0))
        let finish = targetCell.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0)).withOffset(CGVector(dx: -22, dy: -8))
        // One retry: under simulator load the first long press can fail to
        // pick the row up, leaving it in place (seen once in run e4cb01cc).
        var moved = false
        for _ in 0..<2 where !moved {
            start.press(forDuration: 1.2, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 1)
            moved = row.waitUntilFrame({ $0.minY < target.frame.minY })
        }
        if !moved {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Edit mode hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    private func revealByScrolling(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists, element.isHittable, app.frame.contains(element.frame) { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// waitUntilValueEquals, waitUntilAbsent and waitUntilFrame: the shared
// XCUIElement helpers in UniboardUITests.swift.
private extension XCUIElement {
    func waitUntilValueContains(_ expected: String, timeout: TimeInterval = 5) -> Bool {
        wait(NSPredicate(format: "value CONTAINS %@", expected), timeout)
    }

    func waitUntilEnabled(timeout: TimeInterval = 5) -> Bool {
        wait(NSPredicate(format: "enabled == true"), timeout)
    }

    private func wait(_ predicate: NSPredicate, _ timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
