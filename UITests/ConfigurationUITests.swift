import XCTest
import UIKit

/// Settings › Configuration: export, the Review Import sheet for a changed,
/// identical and invalid file, Replace, Edit Configuration, and Undo Last
/// Configuration Change. Files come
/// from the DEBUG `-UniboardConfigurationFixture` hook, which stands in for
/// the Files picker.
@MainActor
final class ConfigurationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(fixture: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        if let fixture { app.launchArguments += ["-UniboardConfigurationFixture", fixture] }
        app.launch()
    }

    // MARK: Tests

    func testReviewReplaceAndUndoAChangedConfiguration() {
        launch(fixture: "changed")
        setUnicodeFonts(false)
        openConfiguration()
        XCTAssertTrue(app.staticTexts[header].exists, "Header explains what the file holds")
        XCTAssertTrue(app.staticTexts[privacy].exists, "The privacy note shows before exporting")
        let colors = element("configuration.keyboardColors")
        revealByScrolling(colors)
        XCTAssertEqual(colors.label, "Copy Image colors and scale chosen in the keyboard without Full Access aren’t included in this file.")
        attachScreenshot("configuration")

        tapImport()
        let settings = element("reviewImport.change.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["This will replace your current configuration. Review the changes before continuing."].exists)
        XCTAssertTrue(app.staticTexts["Uniboard-Configuration-Fixture.toml"].exists)
        XCTAssertTrue(element("reviewImport.fileCaption").label.hasSuffix("· Format version 1"), element("reviewImport.fileCaption").label)
        // The switch change opens the Settings row, first line.
        XCTAssertTrue(app.staticTexts["Extra Unicode Fonts: Off → On"].waitForExistence(timeout: 5))
        XCTAssertEqual(settings.label, "Settings, Will change")
        XCTAssertTrue(element("reviewImport.change.favorites").label.hasSuffix("Will change"))
        // The file leaves out [image_colors]; they are already the defaults
        // here, so resetting them changes nothing, but the footer still says so.
        XCTAssertEqual(element("reviewImport.change.imageColors").label, "Copy Image, Unchanged")
        XCTAssertTrue(element("reviewImport.missingSections").exists)
        XCTAssertTrue(app.staticTexts["Your current favorites and custom key layouts will be replaced."].exists)
        let fonts = element("reviewImport.fonts")
        revealByScrolling(fonts)
        XCTAssertTrue(fonts.label.contains("1 font unavailable"), fonts.label)
        XCTAssertTrue(fonts.label.contains("Fixture Sans Regular"), fonts.label)
        // Each rule that uses the missing font, which is still imported.
        XCTAssertTrue(fonts.label.contains("Code point rule U+2603"), fonts.label)
        XCTAssertTrue(fonts.label.contains("Font unavailable"), fonts.label)
        XCTAssertFalse(element("reviewImport.ignoredFooter").exists, "No Ignored settings section without retired keys")
        // The bottom bar's button: full width less the 16 pt insets, 50 pt tall.
        let button = app.buttons["reviewImport.primary"]
        XCTAssertEqual(button.frame.height, 50, accuracy: 1.5)
        XCTAssertEqual(button.frame.width, app.frame.width - 32, accuracy: 1.5)
        attachScreenshot("review-import")
        // Scrolled to the bottom: the missing sections footer, the overwrite card and the backup note.
        let backup = element("reviewImport.backup")
        revealByScrolling(backup)
        app.swipeUp()
        XCTAssertTrue(backup.isHittable)
        XCTAssertEqual(backup.label, "Your previous configuration will be kept so you can undo this import.")
        attachScreenshot("review-import-bottom")

        // Nothing changed before Replace.
        app.buttons["reviewImport.cancel"].tap()
        XCTAssertTrue(element("reviewImport.primary").waitUntilAbsent())
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(revealExtraUnicodeFonts().value as? String, "0", "Reviewing never turns the switch on")

        openConfiguration()
        tapImport()
        let primary = app.buttons["reviewImport.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertEqual(primary.label, "Replace Configuration")
        primary.tap()
        XCTAssertTrue(element("reviewImport.imported").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reviewImport.fontDownloads"].exists || element("reviewImport.fontDownloads").exists,
                      "Missing fonts lead to Font Downloads")
        attachScreenshot("imported")
        app.buttons["reviewImport.done"].tap()

        let undo = app.buttons["configuration.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.label.contains("Imported "), undo.label)
        attachScreenshot("undo-row")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealExtraUnicodeFonts().waitUntilValueEquals("1"), "Replace turned Extra Unicode Fonts on")

        openConfiguration()
        undo.tap()
        let restore = app.buttons["Restore Previous Configuration"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Undo last configuration change?"].exists)
        restore.tap()
        XCTAssertTrue(element("configuration.undoCaption").waitForExistence(timeout: 5))
        XCTAssertEqual(element("configuration.undoCaption").label, "Previous configuration restored")
        XCTAssertTrue(app.buttons["configuration.undo"].waitUntilAbsent(), "Only one import can be undone")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealExtraUnicodeFonts().waitUntilValueEquals("0"), "Undo restored the switch")
    }

    func testAnIdenticalFileHasNoChangesToImport() {
        launch(fixture: "identical")
        openConfiguration()
        tapImport()
        XCTAssertTrue(element("reviewImport.noChanges").waitForExistence(timeout: 10))
        XCTAssertEqual(element("reviewImport.noChanges").label, "No changes to import")
        for category in ["settings", "layoutsAndKeys", "favorites", "fontsAndRules", "imageColors"] {
            XCTAssertTrue(element("reviewImport.change.\(category)").label.hasSuffix("Unchanged"), category)
        }
        XCTAssertFalse(element("reviewImport.overwrite").exists)
        XCTAssertFalse(element("reviewImport.fonts").exists)
        let primary = app.buttons["reviewImport.primary"]
        XCTAssertEqual(primary.label, "Done")
        attachScreenshot("no-changes")
        primary.tap()
        XCTAssertTrue(primary.waitUntilAbsent())
        XCTAssertFalse(element("reviewImport.imported").exists, "Never “Configuration imported” when nothing was applied")
        XCTAssertTrue(app.navigationBars["Configuration"].exists)
    }

    /// A file with another Copy Image scale: the renamed Copy Image row
    /// lists "Image scale: 3× → 2×" in the same plain format.
    func testADifferentImageScaleIsListedUnderCopyImage() {
        launch(fixture: "scale")
        openConfiguration()
        tapImport()
        let row = element("reviewImport.change.imageColors")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.hasPrefix("Copy Image"), row.label)
        XCTAssertTrue(row.label.contains("Will change"), row.label)
        for category in ["settings", "layoutsAndKeys", "favorites", "fontsAndRules"] {
            XCTAssertTrue(element("reviewImport.change.\(category)").label.hasSuffix("Unchanged"), category)
        }
        row.tap()
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Image scale: ")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(["Image scale: 3× → 2×", "Image scale: 1× → 2×", "Image scale: 2× → 1×"].contains(line.label), line.label)
        attachScreenshot("review-import-scale")
        app.buttons["reviewImport.cancel"].tap()
        XCTAssertTrue(element("reviewImport.primary").waitUntilAbsent())
    }

    func testRetiredSettingsAreIgnoredAndListed() {
        launch(fixture: "legacy")
        openConfiguration()
        tapImport()
        XCTAssertTrue(element("reviewImport.noChanges").waitForExistence(timeout: 10), "Ignored settings are never a change")
        for category in ["settings", "layoutsAndKeys", "favorites", "fontsAndRules", "imageColors"] {
            XCTAssertTrue(element("reviewImport.change.\(category)").label.hasSuffix("Unchanged"), category)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Number Row:'")).firstMatch.exists)
        let topRow = element("reviewImport.ignored.settings.top_row")
        let numberRow = element("reviewImport.ignored.settings.number_row")
        revealByScrolling(numberRow)
        XCTAssertTrue(app.staticTexts["Ignored settings"].exists || app.staticTexts["IGNORED SETTINGS"].exists)
        XCTAssertEqual(topRow.label, "Ignored setting, Top Row")
        XCTAssertEqual(topRow.value as? String, "settings.top_row")
        XCTAssertEqual(numberRow.label, "Ignored setting, Number Row")
        XCTAssertEqual(element("reviewImport.ignoredFooter").label,
                       "These older settings won’t be applied. Your editable keyboard layout takes precedence.")
        XCTAssertFalse(element("reviewImport.overwrite").exists)
        let primary = app.buttons["reviewImport.primary"]
        XCTAssertEqual(primary.label, "Done")
        attachScreenshot("ignored-settings")
        primary.tap()
        XCTAssertTrue(primary.waitUntilAbsent())
        XCTAssertFalse(app.buttons["configuration.undo"].exists, "Nothing was imported")
    }

    func testAnInvalidFileExplainsTheFirstProblemAndListsTheRest() {
        launch(fixture: "invalid")
        openConfiguration()
        tapImport()
        XCTAssertTrue(element("reviewImport.errorTitle").waitForExistence(timeout: 10))
        XCTAssertEqual(element("reviewImport.errorTitle").label, "Couldn’t import configuration")
        XCTAssertTrue(app.staticTexts["Your current configuration hasn’t changed."].exists)
        let first = element("reviewImport.firstProblem")
        XCTAssertTrue(first.exists)
        XCTAssertFalse(first.label.contains("\"yes\""), "Problems never echo file contents")
        let more = element("reviewImport.moreProblems")
        XCTAssertTrue(more.exists)
        XCTAssertTrue(more.label.hasSuffix("More Problems") || more.label.hasSuffix("More Problem"), more.label)
        attachScreenshot("import-error")
        app.buttons["reviewImport.done"].tap()
        XCTAssertTrue(app.navigationBars["Configuration"].waitForExistence(timeout: 5))
    }

    /// Edit Configuration: a broken edit is listed and never applied; a small
    /// valid edit goes through Review Changes, and Undo restores it.
    func testEditValidateApplyAndUndo() {
        launch()
        setUnicodeFonts(false)
        openConfiguration()
        let edit = app.buttons["configuration.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.label.hasPrefix("Edit Configuration"), edit.label)
        edit.tap()
        let text = app.textViews["configurationEditor.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertEqual(text.label, "Configuration text")
        let apply = app.buttons["configurationEditor.apply"]
        let validate = app.buttons["configurationEditor.validate"]
        XCTAssertFalse(apply.isEnabled, "Apply waits for an edit")
        XCTAssertTrue(app.staticTexts[editorHelper].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Opens without the keyboard")
        let lines = (text.value as? String ?? "").components(separatedBy: "\n")
        XCTAssertGreaterThan(lines.count, 5)
        XCTAssertEqual(lines[4], "extra_unicode_fonts = false")
        attachScreenshot("editor")

        // Past the end of line 5, below the 12 pt inset.
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        text.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: text.frame.width - 24, dy: 12 + font.lineHeight * 4.5)).tap()
        text.typeText("x")
        XCTAssertTrue((text.value as? String ?? "").contains("extra_unicode_fonts = falsex\n"), "The cursor was at the end of line 5")
        XCTAssertTrue(app.staticTexts["Edits haven’t been checked."].exists)
        validate.tap()
        let invalid = app.staticTexts["Fix these errors before applying"]
        XCTAssertTrue(invalid.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your settings haven’t changed."].exists)
        let problem = element("configurationEditor.problem.0")
        XCTAssertTrue(problem.label.hasPrefix("Check line 5, column "), problem.label)
        XCTAssertFalse(problem.label.contains("\u{200B}"), "VoiceOver reads the checker's message")
        XCTAssertLessThan(invalid.frame.minY, problem.frame.minY)
        XCTAssertLessThan(problem.frame.minY, app.staticTexts["Your settings haven’t changed."].frame.minY,
                          "The error comes before “Your settings haven’t changed.” (rev. 4)")
        attachScreenshot("editor-invalid")
        apply.tap()
        XCTAssertTrue(invalid.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Review Changes"].waitForExistence(timeout: 2), "An invalid edit is never reviewed")

        text.typeText(XCUIKeyboardKey.delete.rawValue + String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "true")
        XCTAssertTrue((text.value as? String ?? "").contains("extra_unicode_fonts = true\n"))
        validate.tap()
        let valid = app.staticTexts["Configuration is valid. Your settings haven’t changed."]
        XCTAssertTrue(valid.waitForExistence(timeout: 10))
        attachScreenshot("editor-valid")
        // Cancel with edits asks first, with the keyboard down; Keep Editing
        // (on iPhone, a tap outside the popover) keeps the text.
        app.buttons["configurationEditor.cancel"].tap()
        let discard = app.buttons["Discard Edits"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Discard edits?"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitUntilAbsent(), "Nothing types behind the dialog")
        let keep = app.buttons["Keep Editing"]
        if keep.exists { keep.tap() } else { text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap() }
        XCTAssertTrue(discard.waitUntilAbsent())
        XCTAssertTrue((text.value as? String ?? "").contains("extra_unicode_fonts = true\n"), "Keep Editing keeps the text")

        apply.tap()

        XCTAssertTrue(app.navigationBars["Review Changes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["These edits will replace your current configuration."].exists)
        XCTAssertTrue(app.staticTexts["Extra Unicode Fonts: Off → On"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("reviewImport.fileCaption").exists, "No file name or size line")
        XCTAssertFalse(app.buttons["reviewImport.cancel"].exists, "Back is the way out")
        let primary = app.buttons["reviewImport.primary"]
        XCTAssertEqual(primary.label, "Apply")
        attachScreenshot("review-changes")
        primary.tap()
        let applied = element("reviewImport.imported")
        XCTAssertTrue(applied.waitForExistence(timeout: 10))
        XCTAssertEqual(applied.label, "Configuration applied")
        app.buttons["reviewImport.done"].tap()
        XCTAssertTrue(text.waitUntilAbsent(), "Done closes the editor")

        let caption = element("configuration.undoCaption")
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, "Configuration applied")
        let undo = app.buttons["configuration.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.label.contains("Undo Last Configuration Change"), undo.label)
        XCTAssertTrue(undo.label.contains("Applied "), undo.label)
        attachScreenshot("editor-undo-row")
        undo.tap()
        let restore = app.buttons["Restore Previous Configuration"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Undo last configuration change?"].exists)
        restore.tap()
        XCTAssertTrue(caption.waitUntilLabelEquals("Previous configuration restored"))
        XCTAssertTrue(undo.waitUntilAbsent())
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealExtraUnicodeFonts().waitUntilValueEquals("0"), "Undo restored the switch")
    }

    func testExportOpensTheShareSheet() {
        launch()
        openConfiguration()
        app.buttons["configuration.export"].tap()
        // The caption lasts 3 s from the moment the sheet opens: capture it right away.
        // The row's caption may be its own text or part of the row button's label.
        let ready = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Configuration ready to share")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "The share sheet opens and the row says the file is ready")
        attachScreenshot("export-share")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'exported' OR label CONTAINS[c] 'saved'")).firstMatch.exists)
        XCTAssertTrue(ready.waitUntilAbsent(timeout: 6), "The caption goes after 3 s")
    }

    // MARK: Steps

    private let header = "Save your settings, layouts, favorites, font rules and Copy Image options in a TOML file, or import a configuration from Files."
    private let editorHelper = "Edit your configuration in TOML. Validate checks your edits without changing your settings. Apply saves them."
    private let privacy = "Favorites and custom key text are included and may be personal. Typing history, scratchpad text and font files aren’t included."

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func extraUnicodeFonts() -> XCUIElement { app.switches["extraUnicodeFonts"].firstMatch }

    /// Back in Settings the form is still scrolled to Configuration, below the switch.
    private func revealExtraUnicodeFonts() -> XCUIElement {
        let fonts = extraUnicodeFonts()
        for _ in 0..<6 where !(fonts.exists && fonts.isHittable) { app.swipeDown() }
        revealByScrolling(fonts)
        return fonts
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
        let fonts = extraUnicodeFonts()
        revealByScrolling(fonts)
        let value = enabled ? "1" : "0"
        if fonts.value as? String != value {
            fonts.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
        }
        XCTAssertTrue(fonts.waitUntilValueEquals(value))
    }

    private func openConfiguration() {
        if !app.navigationBars["Settings"].exists { openSettings() }
        let entry = app.buttons["configuration"].firstMatch
        revealByScrolling(entry)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Configuration"].waitForExistence(timeout: 5))
    }

    private func tapImport() {
        let row = app.buttons["configuration.import"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    private func revealByScrolling(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists, element.isHittable, app.frame.contains(element.frame) { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = "configuration-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// waitUntilValueEquals and waitUntilAbsent: the shared XCUIElement helpers in
// UniboardUITests.swift.
