import XCTest

/// design/styles-grid: the Normal / Italic grid on Google font family pages,
/// walked through the real catalog with screenshots for review (§9). Downloads
/// are real network transfers; when one can't finish the test records it and
/// keeps going, so the not-downloaded screens are still captured.
@MainActor
final class StyleGridUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
        super.tearDown()
    }

    func testStylesGridScreens() {
        app.launch()
        openCatalogFromSettings()

        // 1. ABeeZee: one row, Regular and Italic tiles.
        openFamily("ABeeZee")
        XCTAssertEqual(styleCells.count, 2)
        let regular = cell("Regular")
        XCTAssertTrue(regular.exists)
        XCTAssertTrue(regular.isSelected, "Regular upright is selected by default")
        XCTAssertEqual(regular.value as? String, "Not downloaded")
        XCTAssertEqual(downloadButton.label, "Download Style")
        screenshot("1-abeezee")
        back(from: "ABeeZee")

        // 2. Lato: 9 rows x 2 tiles; download Bold so one tile draws its sample.
        openFamily("Lato")
        XCTAssertEqual(styleCells.count, 18)
        let boldItalic = cell("Bold Italic")
        reveal(boldItalic)
        boldItalic.tap()
        XCTAssertTrue(boldItalic.isSelected)
        XCTAssertFalse(cell("Regular").isSelected, "Only one cell is selected")
        XCTAssertEqual(boldItalic.value as? String, "Not downloaded")
        let bold = cell("Bold")
        bold.tap()
        XCTAssertTrue(bold.isSelected)
        XCTAssertFalse(boldItalic.isSelected)
        reveal(downloadButton)
        XCTAssertEqual(downloadButton.label, "Download Style")
        let latoDownloaded = download()
        // The whole 9 x 2 grid with its corner badges, between the bars.
        reveal(cell("Thin"), towardTop: true)
        scroll(cell("Thin"), toY: 190)
        XCTAssertTrue(cell("Black Italic").isHittable)
        screenshot("2-lato")
        if latoDownloaded { remove(expectingMessage: "This removes the downloaded font from Uniboard. You can download it again later.") }
        back(from: "Lato")

        // 3. Roboto: column containers; download the italic file.
        openFamily("Roboto")
        XCTAssertEqual(styleCells.count, 18, "The Normal width set: 9 weights x 2")
        let italic = cell("Italic")
        italic.tap()
        XCTAssertEqual(italic.value as? String, "Not downloaded, File contains 18 styles")
        reveal(downloadButton)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@",
            "This file contains 18 styles across Normal and Condensed. Downloading or removing it affects them all.")).firstMatch.exists)
        XCTAssertEqual(downloadButton.label, "Download File (18 Styles)")
        // The block under the grid: name, file line, sentence and button.
        let block = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Roboto-Italic[wdth,wght].ttf")).firstMatch
        scroll(block, toY: 260)
        screenshot("3a-roboto-selected-block")
        let robotoDownloaded = download()
        reveal(cell("Thin Italic"), towardTop: true)
        screenshot("3-roboto")

        // 4. The Width menu keeps the weight and slope.
        let menu = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "fontDetail.styleSet", "Width")).firstMatch
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        let condensed = app.buttons["Condensed"].firstMatch
        XCTAssertTrue(condensed.waitForExistence(timeout: 5))
        screenshot("4-width-menu")
        condensed.tap()
        let condensedItalic = cell("Condensed Italic")
        XCTAssertTrue(condensedItalic.waitForExistence(timeout: 5))
        XCTAssertTrue(condensedItalic.isSelected, "Switching width keeps Regular Italic selected")
        screenshot("4b-roboto-condensed")
        if robotoDownloaded {
            remove(expectingMessage: "This removes all 18 styles in this file from Uniboard. You can download it again later.")
        }
        back(from: "Roboto")

        // 5. Commissioner: one file across both columns.
        openFamily("Commissioner")
        XCTAssertEqual(styleCells.count, 18)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Shared styles file")).firstMatch.exists)
        screenshot("5-commissioner")
        back(from: "Commissioner")

        // 6. Oswald: one column and the caption.
        openFamily("Oswald")
        XCTAssertEqual(styleCells.count, 6)
        XCTAssertTrue(app.staticTexts["No italic styles in this family."].exists)
        XCTAssertEqual(styleCells.matching(NSPredicate(format: "label CONTAINS %@", "Italic")).count, 0, "No synthetic italics")
        scroll(cell("ExtraLight"), toY: 220)
        XCTAssertTrue(app.staticTexts["No italic styles in this family."].isHittable)
        screenshot("6-oswald")
        back(from: "Oswald")

        // 8. Recursive: the Variant menu, italics in the same set.
        openFamily("Recursive")
        XCTAssertEqual(styleCells.count, 16)
        for _ in 0..<4 { app.swipeDown() }
        let variant = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "fontDetail.styleSet", "Variant")).firstMatch
        XCTAssertTrue(variant.isHittable)
        variant.tap()
        for option in ["Mono Linear", "Mono Casual", "Sans Linear", "Sans Casual"] {
            XCTAssertTrue(app.buttons[option].firstMatch.waitForExistence(timeout: 5), option)
        }
        screenshot("8-recursive-variant-menu")
        app.buttons["Sans Casual"].firstMatch.tap()
        XCTAssertTrue(cell("Sans Casual Regular").waitForExistence(timeout: 5))
        XCTAssertTrue(cell("Sans Casual Regular").isSelected)
        back(from: "Recursive")
    }

    func testStylesGridAtAccessibilitySize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        openCatalogFromSettings()
        openFamily("Roboto")
        let thin = cell("Thin")
        reveal(thin)
        XCTAssertEqual(thin.value as? String, "Not downloaded, File contains 18 styles")
        // Through the whole grid, one screen at a time, down to the Download button.
        for _ in 0..<4 { app.swipeDown() }
        var page = 1
        screenshot("7-accessibility-\(page)")
        while page < 10, !(downloadButton.exists && downloadButton.isHittable && downloadButton.frame.maxY < app.frame.maxY - 110) {
            drag(by: 520)
            page += 1
            screenshot("7-accessibility-\(page)")
        }
        XCTAssertTrue(downloadButton.isHittable)
        for element in styleCells.allElementsBoundByIndex where element.isHittable {
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 0.5, "\(element.label) doesn't run off the screen")
        }
    }

    // MARK: Helpers

    /// Slow drags (no momentum) until the element's top sits near `target` points.
    private func scroll(_ element: XCUIElement, toY target: CGFloat) {
        for _ in 0..<8 {
            guard element.exists else { drag(by: 400); continue }
            let delta = element.frame.minY - target
            if abs(delta) < 16 { return }
            drag(by: max(-480, min(480, delta)))
        }
    }

    /// Moves the content up by `distance` points (down when negative), from the
    /// leading margin so no cell is touched.
    private func drag(by distance: CGFloat) {
        let startY = distance > 0 ? app.frame.maxY - 200 : 240
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 24, dy: startY))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }
    private var styleCells: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fontDetail.style."))
    }
    private func cell(_ name: String) -> XCUIElement {
        styleCells.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private var downloadButton: XCUIElement { app.buttons["fontDetail.download"].firstMatch }

    /// Downloads the selected style's file; false if it didn't finish in time.
    private func download() -> Bool {
        let downloaded = app.descendants(matching: .any)["fontDetail.downloaded"].firstMatch
        reveal(downloadButton, alternative: downloaded)
        if !downloaded.exists { downloadButton.tap() }
        guard downloaded.waitForExistence(timeout: 120) else {
            let note = XCTAttachment(string: "Download didn't finish; screens show the not-downloaded state.\n" + app.debugDescription)
            note.name = "download-unfinished"
            note.lifetime = .keepAlways
            add(note)
            return false
        }
        return true
    }

    private func remove(expectingMessage message: String) {
        let remove = app.buttons["fontDetail.remove"].firstMatch
        reveal(remove)
        remove.tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5), "Remove message: \(message)")
        screenshot("remove-dialog-" + (message.contains("all") ? "shared" : "single"))
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Remove Download", "fontDetail.remove")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 15))
    }

    private func openCatalogFromSettings() {
        selectTab("Settings")
        let downloads = app.buttons["fontDownloads"].firstMatch
        reveal(downloads)
        downloads.tap()
        let browse = app.buttons["fontDownloads.browseGoogle"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
        browse.tap()
        XCTAssertTrue(app.navigationBars["Google Fonts"].waitForExistence(timeout: 5))
    }

    private func openFamily(_ name: String) {
        let field = app.searchFields["Search fonts by name"].firstMatch
        if !field.exists { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let value = field.value as? String, value != "Search fonts by name", !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(name + "\n")
        let family = app.buttons["googleFonts.family.\(name)"].firstMatch
        XCTAssertTrue(family.waitForExistence(timeout: 15))
        family.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Styles"].waitForExistence(timeout: 5))
        let first = styleCells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        reveal(first)
    }

    private func back(from title: String) {
        let bar = app.navigationBars[title].firstMatch
        let named = bar.buttons["Google Fonts"].firstMatch
        (named.exists ? named : bar.buttons.firstMatch).tap()
        XCTAssertTrue(app.navigationBars["Google Fonts"].waitForExistence(timeout: 5))
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        if tab.waitForExistence(timeout: 3) { tab.tap(); return }
        let floating = app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if floating.exists { floating.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func reveal(_ element: XCUIElement, alternative: XCUIElement? = nil, towardTop: Bool = false) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            if let alternative, alternative.exists && alternative.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists, "Expected real UI element \(element.identifier)")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = "styles-grid-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
