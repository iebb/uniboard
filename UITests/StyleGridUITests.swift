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

        // 1. ABeeZee: one row, Regular and Italic tiles; static files are own files (case A2).
        openFamily("ABeeZee")
        XCTAssertEqual(styleCells.count, 2)
        let regular = cell("Regular")
        XCTAssertTrue(regular.exists)
        XCTAssertTrue(regular.isSelected, "Regular upright is selected by default")
        XCTAssertTrue((regular.value as? String)?.hasPrefix("Not downloaded, Separate file, ") == true, "\(String(describing: regular.value))")
        XCTAssertTrue(downloadButton.label.hasPrefix("Download Regular"), downloadButton.label)
        XCTAssertFalse(fileButton.exists)
        screenshot("1-abeezee")
        back(from: "ABeeZee")

        // 2. Lato: 9 rows x 2 tiles, no width row, no tile arrows; download Bold.
        openFamily("Lato")
        XCTAssertEqual(styleCells.count, 18)
        XCTAssertFalse(app.staticTexts["Standard"].exists, "One width: no width names")
        let boldItalic = cell("Bold Italic")
        reveal(boldItalic)
        boldItalic.tap()
        XCTAssertTrue(boldItalic.isSelected)
        XCTAssertFalse(cell("Regular").isSelected, "Only one cell is selected")
        let bold = cell("Bold")
        bold.tap()
        XCTAssertTrue(bold.isSelected)
        XCTAssertFalse(boldItalic.isSelected)
        reveal(downloadButton)
        XCTAssertTrue(downloadButton.label.hasPrefix("Download Bold"), downloadButton.label)
        let latoDownloaded = download()
        reveal(cell("Thin"), towardTop: true)
        scroll(cell("Thin"), toY: 190)
        screenshot("2-lato")
        if latoDownloaded { remove(expectingMessage: "This removes the downloaded font from Uniboard. You can download it again later.") }
        back(from: "Lato")

        // 3. Roboto: 4 width columns, no Width menu (screen 1).
        openFamily("Roboto")
        XCTAssertEqual(styleCells.count, 36, "9 weights x (Standard, Condensed) x (Normal, Italic)")
        XCTAssertFalse(app.buttons["fontDetail.styleSet"].exists, "Widths are columns, not a menu")
        XCTAssertTrue(app.staticTexts["Standard"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Condensed"].firstMatch.exists)
        let condensedBold = cell("Condensed Bold")
        reveal(condensedBold)
        condensedBold.tap()
        XCTAssertTrue((condensedBold.value as? String)?.hasPrefix("Not downloaded, Separate file, ") == true)
        reveal(fileButton)
        XCTAssertTrue(downloadButton.label.hasPrefix("Download Condensed Bold"), downloadButton.label)
        XCTAssertTrue(fileButton.label.hasPrefix("Download File (18 Styles)"), fileButton.label)
        XCTAssertTrue(fileButton.label.contains("Includes 18 styles in one file."), fileButton.label)
        XCTAssertTrue(fileButton.label.contains("Normal styles in Standard and Condensed widths."), fileButton.label)
        XCTAssertFalse(fileButton.label.contains("Existing downloads are kept."), "Nothing downloaded yet")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "RobotoCondensed-Bold.ttf")).firstMatch.exists)
        screenshot("3a-roboto-condensed-bold-block")
        reveal(cell("Thin"), towardTop: true)
        screenshot("3-roboto")

        // 4. Bold alone, then the upright file: both kept, shown once (screen 6, §10 checks 11).
        let robotoBold = cell("Bold")
        reveal(robotoBold)
        robotoBold.tap()
        let freeBefore = freeSpaces()
        let boldDownloaded = download()
        if boldDownloaded {
            XCTAssertEqual(freeSpaces(), freeBefore.map { $0 - 1 })
            XCTAssertTrue((robotoBold.value as? String)?.hasPrefix("Downloaded, Separate file, ") == true)
            reveal(fileButton)
            XCTAssertTrue(fileButton.label.contains("Includes 18 styles in one file. Existing downloads are kept."), fileButton.label)
            fileButton.tap()
            let removeFile = app.buttons["fontDetail.remove.file"].firstMatch
            if removeFile.waitForExistence(timeout: 120) {
                XCTAssertTrue(removeFile.label.hasPrefix("Remove File (18 Styles)"), removeFile.label)
                XCTAssertTrue(app.buttons["fontDetail.remove"].firstMatch.exists, "The separate file keeps its own Remove row")
                XCTAssertEqual(freeSpaces(), freeBefore.map { $0 - 2 }, "The shared file counts +1; nothing was removed")
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "fontDetail.downloaded").count, 1, "Downloaded rows once")
                reveal(robotoBold, towardTop: true)
                scroll(robotoBold, toY: 300)
                screenshot("6-roboto-both-files-kept")
                // Remove the shared file: Bold stays downloaded from its own file.
                remove(identifier: "fontDetail.remove.file", confirm: "Remove File (18 Styles)",
                       expectingMessage: "Uniboard will stop using this download. Styles available from other files will stay available. The file may remain stored on this device.")
                XCTAssertTrue((robotoBold.value as? String)?.hasPrefix("Downloaded") == true)
            }
            remove(expectingMessage: "This removes the downloaded font from Uniboard. You can download it again later.")
        }
        back(from: "Roboto")

        // 5. Commissioner: one file across both groups.
        openFamily("Commissioner")
        XCTAssertEqual(styleCells.count, 18)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Shared styles, 1 file, 18 styles")).firstMatch.exists)
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

        // 7. Inconsolata: 9 width columns scroll; 72 styles in its file (screen 2).
        openFamily("Inconsolata")
        XCTAssertEqual(styleCells.count, 72)
        XCTAssertTrue(app.staticTexts["Standard"].firstMatch.exists)
        let condensedSemiBold = cell("Condensed SemiBold")
        reveal(condensedSemiBold)
        condensedSemiBold.tap()
        reveal(fileButton)
        XCTAssertTrue(downloadButton.label.hasPrefix("Download Condensed SemiBold"), downloadButton.label)
        XCTAssertTrue(fileButton.label.hasPrefix("Download File (72 Styles)"), fileButton.label)
        reveal(cell("ExtraLight"), towardTop: true)
        screenshot("7-inconsolata-scroll")
        back(from: "Inconsolata")

        // 8. Noto Sans Telugu UI: no verified single-style files, so only the shared file (case B, screen 3).
        openFamily("Noto Sans Telugu UI")
        reveal(downloadButton)
        XCTAssertTrue(downloadButton.label.hasPrefix("Download File ("), downloadButton.label)
        XCTAssertFalse(fileButton.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "This style is available here in a file containing")).firstMatch.exists)
        screenshot("8-noto-sans-telugu-ui-shared-only")
        back(from: "Noto Sans Telugu UI")

        // 9. Recursive: the Variant menu, italics in the same set.
        openFamily("Recursive")
        XCTAssertEqual(styleCells.count, 16)
        for _ in 0..<4 { app.swipeDown() }
        let variant = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "fontDetail.styleSet", "Variant")).firstMatch
        XCTAssertTrue(variant.isHittable)
        variant.tap()
        for option in ["Mono Linear", "Mono Casual", "Sans Linear", "Sans Casual"] {
            XCTAssertTrue(app.buttons[option].firstMatch.waitForExistence(timeout: 5), option)
        }
        screenshot("9-recursive-variant-menu")
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
        XCTAssertTrue((thin.value as? String)?.hasPrefix("Not downloaded, Separate file, ") == true)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Normal styles: 1 file · 18 styles")).firstMatch.exists)
        // Through the whole grid, one screen at a time, down to the Download button.
        for _ in 0..<4 { app.swipeDown() }
        var page = 1
        screenshot("10-accessibility-\(page)")
        while page < 16, !(downloadButton.exists && downloadButton.isHittable && downloadButton.frame.maxY < app.frame.maxY - 110) {
            drag(by: 520)
            page += 1
            screenshot("10-accessibility-\(page)")
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
    /// The shared file's row under a single-style row.
    private var fileButton: XCUIElement { app.buttons["fontDetail.download.file"].firstMatch }

    /// The number in the §7 footer ("Room for 12 more…"); 0 when full.
    private func freeSpaces() -> Int? {
        let footer = app.staticTexts["fontDetail.capacity"].firstMatch
        reveal(footer)
        guard footer.exists else { return nil }
        if footer.label.hasPrefix("All ") { return 0 }
        return footer.label.split(separator: " ").compactMap { Int($0) }.first
    }

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

    private func remove(identifier: String = "fontDetail.remove", confirm title: String = "Remove Download", expectingMessage message: String) {
        let remove = app.buttons[identifier].firstMatch
        reveal(remove)
        remove.tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5), "Remove message: \(message)")
        screenshot("remove-dialog-" + identifier)
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", title, identifier)).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 15) || app.buttons["fontDetail.remove"].waitForExistence(timeout: 1))
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
        let field = app.textFields["googleFonts.search"].firstMatch
        if !field.exists { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let value = field.value as? String, value != field.placeholderValue, !value.isEmpty {
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
