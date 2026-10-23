import XCTest

/// Real navigation and bundled metadata. Live binary transfer is explicitly opt-in.
/// These tests make no screenshot/rendering correctness claim from accessibility alone.
@MainActor
final class FontExplorationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testGoogleCatalogSearchIsLocalAndOpensExactFamily() {
        openCatalogFromSettings()
        let searchField = app.searchFields["Search fonts by name"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.isHittable, "Catalog search must be discoverable without a pull-down gesture")
        search("Roboto", placeholder: "Search fonts by name")
        let family = app.buttons["googleFonts.family.Roboto"].firstMatch
        XCTAssertTrue(family.waitForExistence(timeout: 15))
        family.tap()
        XCTAssertTrue(app.navigationBars["Roboto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Downloaded fonts are for use in Uniboard. They aren’t installed for other apps."].exists)
        XCTAssertTrue(app.staticTexts["Styles"].exists)
        // No action has requested a binary; ready or previously saved state are both legitimate.
        let activeTransfer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Downloading…"))
        XCTAssertEqual(activeTransfer.count, 0)
    }

    func testCharacterFontsInspectWithoutChangingCopyAction() {
        openLatinCharacterFonts()
        XCTAssertTrue(app.staticTexts["Fonts change the preview here. Other apps choose how inserted text looks."].exists)
        search("Helvetica", placeholder: "Search available fonts")
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "characterFonts.face.")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 60), "The public inventory should verify a local Latin face; no mocked tile is injected")
        let inspectedFamily = tile.label.components(separatedBy: ",").first ?? "Helvetica"
        tile.tap()
        XCTAssertTrue(app.staticTexts["Available in the app only"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["fontDetail.remove"].exists, "A system/included face cannot be removed")
        navigateBack(from: inspectedFamily, to: "Fonts for This Character")
        navigateBack(from: "Fonts for This Character", to: "Character")
        let copy = app.buttons["copyCharacter"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        if !copy.isHittable { reveal(copy, towardTop: true) }
        XCTAssertTrue(copy.isHittable)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertEqual(copy.label, "Copy Character", "Inspecting fonts must not execute or replace the original copy action")
        XCTAssertTrue(app.staticTexts["characterProperties.codepoints"].label.contains("U+0041"))
        copy.tap()
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Copied"), object: copy)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 5), .completed)
    }

    func testLiveSelectedRobotoFileDownloadsAndAppearsInComparison() throws {
        guard ProcessInfo.processInfo.environment["UNIBOARD_GOOGLE_FONT_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("Real Google font download acceptance requires explicit network-test opt-in")
        }
        openLatinCharacterFonts()
        search("Roboto", placeholder: "Search available fonts")
        let browse = app.buttons["Browse Google Fonts"].firstMatch
        reveal(browse)
        browse.tap()
        search("Roboto", placeholder: "Search fonts by name")
        let family = app.buttons["googleFonts.family.Roboto"].firstMatch
        XCTAssertTrue(family.waitForExistence(timeout: 15))
        family.tap()
        let downloaded = app.descendants(matching: .any)["fontDetail.downloaded"].firstMatch
        let download = app.buttons["fontDetail.download"].firstMatch
        reveal(download, alternative: downloaded)
        let wasAlreadyDownloaded = downloaded.exists
        if !wasAlreadyDownloaded {
            XCTAssertTrue(download.isHittable)
            download.tap()
        }
        XCTAssertTrue(downloaded.waitForExistence(timeout: 180), "Real pinned download must validate and publish its selected file")
        let preview = app.descendants(matching: .any)["fontDetail.verifiedPreview"].firstMatch
        reveal(preview, towardTop: true)
        XCTAssertTrue(preview.waitForExistence(timeout: 60), "Downloaded does not imply coverage: a separate engine check must find this exact style for A")
        // Go back through the retained catalog and verify the new local comparison result.
        navigateBack(from: "Roboto", to: "Google Fonts")
        navigateBack(from: "Google Fonts", to: "Fonts for This Character")
        search("Roboto", placeholder: "Search available fonts")
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "characterFonts.face.", "Roboto")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 60))
        tile.tap()
        XCTAssertTrue(app.staticTexts["Downloaded"].waitForExistence(timeout: 5))
        if !wasAlreadyDownloaded {
            let manage = app.buttons["Manage Download"].firstMatch
            reveal(manage)
            manage.tap()
            let remove = app.buttons["fontDetail.remove"].firstMatch
            reveal(remove)
            remove.tap()
            let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Remove Download", "fontDetail.remove")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            XCTAssertTrue(app.buttons["fontDetail.download"].waitForExistence(timeout: 15))
        }
    }

    /// A sheet and its presenting Explore screen both expose navigation bars.
    /// Never use app.navigationBars.buttons.firstMatch: that may hit Explore's toolbar.
    private func navigateBack(from title: String, to previousTitle: String) {
        let bar = app.navigationBars[title].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Expected inspector bar \(title)")
        let namedBack = bar.buttons[previousTitle].firstMatch
        let genericBack = bar.buttons["Back"].firstMatch
        let back = namedBack.exists ? namedBack : genericBack
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Expected Back to \(previousTitle) inside \(title)")
        XCTAssertTrue(back.isHittable)
        back.tap()
        let destination = app.navigationBars[previousTitle].firstMatch
        // Navigation bars are containers, not touch targets; test a real control
        // within the intended destination instead of the container's isHittable.
        let destinationControl = previousTitle == "Character"
            ? destination.buttons["Done"].firstMatch
            : destination.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@ OR label == %@ OR label == %@",
                "BackButton", "Back", "Character", "Fonts for This Character")).firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            destination.exists && destinationControl.exists && destinationControl.isHittable
        }, object: destination)
        let outcome = XCTWaiter.wait(for: [visible], timeout: 10)
        if outcome != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Font navigation after Back from \(title)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(outcome, .completed,
                       "Back must return to the sheet's interactive \(previousTitle), not the presenting Explore screen")
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

    private func openLatinCharacterFonts() {
        selectTab("Explore")
        let field = app.textFields["unicodeSearch"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("u+0041")
        let character = app.buttons["character-U+0041"].firstMatch
        XCTAssertTrue(character.waitForExistence(timeout: 10))
        character.tap()
        let fonts = app.buttons["characterFonts.open"].firstMatch
        reveal(fonts)
        fonts.tap()
        XCTAssertTrue(app.navigationBars["Fonts for This Character"].waitForExistence(timeout: 5))
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        if tab.waitForExistence(timeout: 3) { tab.tap(); return }
        let floating = app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if floating.exists { floating.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func search(_ query: String, placeholder: String) {
        let field = app.searchFields[placeholder].firstMatch
        if !field.exists { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let value = field.value as? String, value != placeholder, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(query + "\n")
    }

    private func reveal(_ element: XCUIElement, alternative: XCUIElement? = nil, towardTop: Bool = false) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            if let alternative, alternative.exists && alternative.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists, "Expected real UI element \(element.identifier)")
    }
}
