import XCTest
import UIKit

@MainActor
final class ExplicitRowsUITests: UniboardUITestCase {
    private func addText(_ text: String) {
        let add = app.buttons["page.addText"].firstMatch
        revealByScrolling(add, in: app)
        add.tap()
        let field = app.textFields["page.addText.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(text)
        app.alerts.buttons["Add"].tap()
    }
    private func segment(_ id: String) -> XCUIElement { app.buttons["arrange.alignment.\(id)"].firstMatch }
    private func choose(_ id: String) {
        let button = segment(id)
        revealByScrolling(button, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(button.waitUntilSelected())
        XCTAssertFalse(app.staticTexts["arrange.error"].exists)
    }
    func testPageAlignmentsMixedAndRowInheritance() {
        deleteAppPages(named: "qarows14")
        addTeardownBlock { @MainActor [self] in deleteAppPages(named: "qarows14") }
        _ = createAppPage("qarows14")
        XCTAssertTrue(app.staticTexts["No keys yet"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["arrange.alignment"].exists)
        addText("abcd")
        let tile = { (row: Int, index: Int) in self.app.buttons["arrange.\(row).\(index)"].firstMatch }
        XCTAssertTrue(tile(0, 3).waitForExistence(timeout: 5))
        let canvas = app.descendants(matching: .any)["arrange.canvas"].firstMatch
        let inner = canvas.frame.insetBy(dx: 8, dy: 8)
        let width = tile(0, 0).frame.width
        choose("left")
        XCTAssertEqual(tile(0, 0).frame.minX, inner.minX, accuracy: 1)
        choose("center")
        XCTAssertEqual((tile(0, 0).frame.minX + tile(0, 3).frame.maxX) / 2, inner.midX, accuracy: 1)
        choose("right")
        XCTAssertEqual(tile(0, 3).frame.maxX, inner.maxX, accuracy: 1)
        choose("spread")
        XCTAssertEqual(tile(0, 0).frame.minX, inner.minX, accuracy: 1)
        XCTAssertEqual(tile(0, 3).frame.maxX, inner.maxX, accuracy: 1)
        XCTAssertEqual(tile(0, 0).frame.width, width, accuracy: 0.5)
        attachScreenshot("Explicit page Spread keeps key widths and full inner edges")
        tile(0, 2).tap()
        XCTAssertTrue(app.staticTexts["Row 1"].exists)
        app.buttons["arrange.newRow"].tap()
        XCTAssertTrue(tile(1, 0).waitForExistence(timeout: 5))
        XCTAssertTrue(segment("spread").isSelected, "Split inherits source alignment")
        choose("center")
        tile(1, 0).tap()
        XCTAssertTrue(app.staticTexts["Mixed"].exists)
        XCTAssertFalse(["left", "center", "right", "spread"].contains { segment($0).isSelected })
        attachScreenshot("All Rows Mixed has no selected alignment segment")
        tile(1, 0).tap()
        app.buttons["arrange.joinRow"].tap()
        XCTAssertTrue(segment("spread").waitUntilSelected(), "Join keeps the upper row alignment")
        app.buttons["page.more"].tap()
        XCTAssertTrue(app.buttons["Rows of Ten, Align Left"].waitForExistence(timeout: 5))
        app.buttons["arrange.reset"].tap()
        XCTAssertTrue(segment("left").waitUntilSelected())
    }
    func testMainABCOnlyAlignmentAndStandardReset() {
        resetAppLayouts()
        resetMainKeyboard()
        let left = segment("left")
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        app.buttons["mainKeyboard.key.letter.a"].tap()
        XCTAssertTrue(app.staticTexts["Row 3"].exists)
        choose("left")
        app.buttons["mainKeyboard.more"].tap()
        app.buttons["mainKeyboard.reset"].tap()
        XCTAssertTrue(segment("center").waitUntilSelected(), "Standard Layout restores legacy Center adapter")
        app.buttons["Numbers and Symbols"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["arrange.alignment"].exists)
        app.buttons["More Symbols"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["arrange.alignment"].exists)
        attachScreenshot("123 and More Symbols have no alignment control")
    }
    func testFavoritesHasNoAddOrAlignmentAndStarDoesNotSnapBack() {
        openAppFavorites()
        XCTAssertFalse(app.buttons["page.addUnicode"].exists)
        XCTAssertFalse(app.buttons["page.addText"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["arrange.alignment"].exists)
        let star = app.switches["page.star"].firstMatch
        revealByScrolling(star, in: app)
        XCTAssertTrue(star.exists)
        if star.value as? String == "0" { tapSwitch(star) }
        XCTAssertTrue(star.waitUntilValueEquals("1"))
        XCTAssertFalse(star.isEnabled)
        XCTAssertTrue(app.staticTexts["When on, the ★ key opens Favorites."].exists)
        attachScreenshot("Dynamic Favorites retains star card without add or alignment controls")
    }
    func testAddActionsDefaultAX2AndAX5() {
        deleteAppPages(named: "qaadd14")
        _ = createAppPage("qaadd14")
        app.navigationBars.buttons.firstMatch.tap()
        addTeardownBlock { @MainActor [self] in
            app.terminate(); app.launchArguments = Self.setUpLaunchArguments; app.launch()
            deleteAppPages(named: "qaadd14")
        }
        for (name, category) in [("Default", "UICTContentSizeCategoryL"), ("AX2", "UICTContentSizeCategoryAccessibilityL"), ("AX5", "UICTContentSizeCategoryAccessibilityXXXL")] {
            app.terminate()
            app.launchArguments = Self.setUpLaunchArguments + ["-UIPreferredContentSizeCategoryName", category]
            app.launch()
            openAppPages()
            let page = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pages.page.' AND label CONTAINS 'qaadd14'")).firstMatch
            XCTAssertTrue(page.waitForExistence(timeout: 5)); page.tap()
            let unicode = app.buttons["page.addUnicode"].firstMatch, text = app.buttons["page.addText"].firstMatch
            revealByScrolling(text, in: app)
            XCTAssertEqual(unicode.frame.width, text.frame.width, accuracy: 0.5)
            XCTAssertEqual(unicode.frame.minX, 16, accuracy: 0.5)
            XCTAssertEqual(unicode.frame.maxX, app.frame.width - 16, accuracy: 0.5)
            XCTAssertEqual(text.frame.minX, 16, accuracy: 0.5)
            XCTAssertEqual(text.frame.maxX, app.frame.width - 16, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(unicode.frame.height, 52)
            XCTAssertGreaterThanOrEqual(text.frame.height, 52)
            XCTAssertTrue(unicode.label.contains("Add from Unicode"))
            XCTAssertTrue(text.label.contains("Add Text"))
            attachScreenshot("Full-width add actions \(name)")
        }
    }
    private func restoreHold(_ keyID: String) {
        openMainKeyboardEditor()
        selectMainKeyboardKey(keyID)
        let layer = app.buttons["layers.longPress"].firstMatch
        revealByScrolling(layer, in: app); layer.tap()
        let reset = app.buttons["keySettings.resetGesture"].firstMatch
        revealByScrolling(reset, in: app)
        if reset.isEnabled { reset.tap() }
        app.buttons["keySettings.save"].tap()
        XCTAssertTrue(layer.waitForExistence(timeout: 5))
    }
    func testPunctuationHoldNotesAreReadOnlyAndYieldToSavedChoices() {
        let question = "symbol.003F", dollar = "symbol.0024"
        addTeardownBlock { @MainActor [self] in
            restoreHold(question)
            restoreHold(dollar)
        }
        for (id, script, spoken) in [(question, "arabic", "When using Arabic: Arabic Question Mark"),
                                      (dollar, "hebrew", "When using Hebrew: New Sheqel Sign")] {
            restoreHold(id)
            let note = app.descendants(matching: .any)["layers.holdNote.\(script)"].firstMatch
            revealByScrolling(note, in: app)
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            XCTAssertEqual(note.label, spoken)
            XCTAssertFalse(app.buttons["layers.holdNote.\(script)"].exists, "The explanation is not an editable chip")
            attachScreenshot("Default Hold note \(script) isolates its punctuation symbol")
            configureAppKeyGesture(keyID: id, gesture: "longPress", choices: ["X"])
            XCTAssertFalse(note.exists, "Saved Hold choices suppress layout-only additions")
        }
    }
    func testRealKeyboardUsesSavedExplicitSpreadPage() throws {
        try requirePhoneKeyboardIntegration()
        deleteAppPages(named: "qareal14")
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard(); deleteAppPages(named: "qareal14") }
        _ = createAppPage("qareal14")
        addText("abcd")
        choose("spread")
        let star = app.switches["page.star"].firstMatch
        revealByScrolling(star, in: app); tapSwitch(star)
        XCTAssertTrue(star.waitUntilValueEquals("1"))
        let input = openSystemKeyboardHost(unicodeBrowse: false)
        app.buttons["keyboard.openFavorites"].firstMatch.tap()
        let a = symbolBoardKey("a"), b = symbolBoardKey("b"), c = symbolBoardKey("c"), d = symbolBoardKey("d")
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        XCTAssertEqual(a.frame.minX, 8, accuracy: 1)
        XCTAssertEqual(d.frame.maxX, app.frame.width - 8, accuracy: 1)
        XCTAssertEqual(b.frame.minX - a.frame.maxX, c.frame.minX - b.frame.maxX, accuracy: 1)
        a.tap(); d.tap()
        XCTAssertTrue(input.waitUntilValueEquals("ad"))
        attachScreenshot("Real keyboard Spread matches saved explicit row membership and edges")
    }
}
