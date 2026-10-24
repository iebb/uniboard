import XCTest
import UIKit

/// Companion-app search, Blocks, Explore and character details; no keyboard.
@MainActor
final class AppBrowsingUITests: UniboardUITestCase {
    func testSearchByCharacterNameAndLiteral() {
        searchUnicode("snowman")
        assertCharacterVisible("U+2603")

        searchUnicode("☃")
        let snowman = assertCharacterVisible("U+2603")
        snowman.tap()

        XCTAssertTrue(app.buttons["copyCharacter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["U+2603"].exists)
    }

    func testSearchBySupplementaryCodepointAndAlias() {
        searchUnicode("U+1F680")
        let rocket = assertCharacterVisible("U+1F680")
        dismissAppSearchKeyboard()
        attachScreenshot("Search by code point finds the original rocket")
        rocket.tap()

        XCTAssertTrue(app.buttons["copyCharacter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["U+1F680"].exists)
        app.buttons["Done"].tap()

        searchUnicode("ohm")
        assertCharacterVisible("U+2126")
    }

    func testSearchByBlockName() {
        searchUnicode("Mathematical Operators")
        assertCharacterVisible("U+2200")

        searchUnicode("Hiragana")
        assertCharacterVisible("U+3041")
    }

    func testSuzhouNumeralsSearchExposesNamesListAndNumericProperties() {
        searchUnicode("suzhou numerals")
        assertCharacterVisible("U+3021")
        dismissAppSearchKeyboard()
        for scalar in 0x3021...0x3029 {
            revealResultCharacter(String(format: "U+%04X", scalar))
        }
        attachScreenshot("Suzhou numerals section search finds the nine Hangzhou-named characters")
        revealResultCharacter("U+3021").tap()
        assertCharacterProperty("name", equals: "HANGZHOU NUMERAL ONE")
        assertCharacterProperty("section", contains: "Suzhou numerals")
        assertCharacterProperty("notes", contains: "misnomer")
        assertCharacterProperty("notes", contains: "Hangzhou")
        assertCharacterProperty("numericValue", equals: "1")
        attachScreenshot("Official Hangzhou name retains Suzhou section, naming note and numeric value")
        app.buttons["Done"].tap()

        searchUnicode("hangzhou numerals")
        assertCharacterVisible("U+3021")
        dismissAppSearchKeyboard()
        for scalar in 0x3021...0x3029 {
            revealResultCharacter(String(format: "U+%04X", scalar))
        }
    }

    func testBrowseUnicodeBlockAndOpenCharacter() {
        selectAppTab("Blocks")
        let blockSearch = app.descendants(matching: .any)["blockSearch"].firstMatch
        XCTAssertTrue(blockSearch.waitForExistence(timeout: 5))
        blockSearch.tap()
        blockSearch.typeText("Arrows")

        let arrows = app.buttons["Arrows"].firstMatch
        XCTAssertTrue(arrows.waitForExistence(timeout: 5))
        arrows.tap()
        attachScreenshot("Browse the real Arrows block and its characters")
        assertCharacterVisible("U+2190").tap()

        XCTAssertTrue(app.buttons["copyCharacter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["U+2190"].exists)
    }

    func testBlockPageShowsSixteenPerRowChart() {
        selectAppTab("Blocks")
        let blockSearch = app.descendants(matching: .any)["blockSearch"].firstMatch
        XCTAssertTrue(blockSearch.waitForExistence(timeout: 5))
        blockSearch.tap()
        blockSearch.typeText("Arrows")
        let arrows = app.buttons["Arrows"].firstMatch
        XCTAssertTrue(arrows.waitForExistence(timeout: 5))
        arrows.tap()
        let options = app.buttons["blockDensity"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["16 per Row"].firstMatch.tap()
        XCTAssertTrue(options.waitUntilValueEquals("16"))
        XCTAssertTrue(app.descendants(matching: .any)["codeChart"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["character-U+2190"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["character-U+2200"].firstMatch.exists, "The chart holds only this block")
        attachScreenshot("Arrows block at 16 per row")
        app.buttons["block.next"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["character-U+2200"].firstMatch.waitForExistence(timeout: 5),
                      "Next opens Mathematical Operators")
        app.buttons["block.previous"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["character-U+2190"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["chartBlockNavigator"].firstMatch.press(forDuration: 1)
        // The preview exposes blockInfo as combined text; do not assume an Other element type.
        XCTAssertTrue(app.buttons["Copy Range"].firstMatch.waitForExistence(timeout: 5), "Holding a block name shows its info")
        attachDiagnostics("Block info immediately after Copy Range appears")
        let blockInfo = app.descendants(matching: .any)["blockInfo"].firstMatch
        XCTAssertTrue(blockInfo.waitForExistence(timeout: 5))
        XCTAssertTrue(blockInfo.label.contains("Since, Unicode 1.1"), blockInfo.label)
        attachScreenshot("Holding a block name shows its info")
        app.buttons["Copy Range"].firstMatch.tap()
        options.tap()
        app.buttons["Tiles"].firstMatch.tap()
        XCTAssertTrue(options.waitUntilValueEquals("3"))
    }

    func testCatalogSelectionPreservesLookupStatusAndLocalChoice() {
        // Edition survives ordinary test launches, so establish this fixture
        // through its real Settings UI rather than resetting shared storage.
        selectAppEdition("latest")
        for tab in ["Explore", "Emoji", "Blocks", "Keyboard"] {
            appTab(tab).tap()
            let version = app.buttons["unicodeEdition.current"].firstMatch
            if tab == "Keyboard" {
                XCTAssertFalse(version.exists, "Keyboard shows no version")
            } else {
                XCTAssertTrue(version.waitForExistence(timeout: 5), "\(tab) shows a version menu")
                XCTAssertEqual(version.value as? String, "latest")
            }
        }
        for (edition, has17, has18) in [("older", false, false), ("previous", true, false),
                                       ("latest", true, true), ("draft", true, true)] {
            selectAppEdition(edition)
            assertAppCatalogScalar("U+0041", assigned: true, age: "1.1")
            assertAppCatalogScalar("U+0378", assigned: false)
            assertAppCatalogScalar("U+10940", assigned: has17, age: has17 ? "17.0" : nil)
            assertAppCatalogScalar("U+0558", assigned: has18, age: has18 ? "18.0" : nil)
            attachScreenshot("Settings-selected \(edition) preserves its actual historical assignments")
        }

        // A historical version remains17 after a real relaunch. Draft19 may
        // honestly share18's assignments; no nonexistent19-only scalar is used.
        selectAppEdition("previous")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        openAppSettings()
        assertControlValue("unicodeEdition", equals: "previous")
        selectAppTab("Explore")
        assertAppCatalogScalar("U+10940", assigned: true, age: "17.0")
        assertAppCatalogScalar("U+0558", assigned: false)
        attachScreenshot("Historical Unicode17 selection persists after ordinary relaunch")
        selectAppEdition("latest")
    }

    func testExploreListsCharactersInAscendingCodePointOrder() {
        XCTAssertFalse(app.buttons["unicodeSort"].exists, "Characters are always listed from the lowest code point")
        let initialTiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "character-U+"))
            .allElementsBoundByAccessibilityElement.compactMap { tile -> (CGRect, UInt32)? in
                let frame = tile.frame
                guard usableHeightFrame(frame), app.frame.contains(frame),
                      let point = UInt32(tile.identifier.replacingOccurrences(of: "character-U+", with: ""), radix: 16) else { return nil }
                return (frame, point)
            }.sorted { abs($0.0.minY - $1.0.minY) > 5 ? $0.0.minY < $1.0.minY : $0.0.minX < $1.0.minX }
        XCTAssertGreaterThan(initialTiles.count, 1)
        for (before, after) in zip(initialTiles, initialTiles.dropFirst()) { XCTAssertLessThan(before.1, after.1) }
        attachScreenshot("Explore uses ascending code point order")
    }

    func testExplorePinchZoomsPastSevenColumnsAndBack() {
        selectAppTab("Explore")
        let options = app.buttons["exploreDensity"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        if (options.value as? String) != "3" {
            options.tap()
            app.buttons["Tiles"].firstMatch.tap()
            XCTAssertTrue(options.waitUntilValueEquals("3"))
        }
        let grid = app.scrollViews["exploreResults"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["character-U+0020"].firstMatch.waitForExistence(timeout: 10))

        // The scroll view runs under the floating tab bar, so a pinch over the
        // whole scroll view would touch a tab; pinch on a tile in the visible middle instead.
        let tabBar = app.tabBars.firstMatch
        let visible: CGRect = {
            let frame = grid.frame
            let bottom = tabBar.exists ? min(frame.maxY, tabBar.frame.minY) : min(frame.maxY, app.frame.maxY)
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottom - frame.minY)
        }()
        /// Identifiers and frames of the tiles lying fully inside the visible grid, from one snapshot.
        func visibleTiles() -> [(id: String, frame: CGRect)] {
            guard let root = try? app.snapshot() else { return [] }
            var tiles: [(id: String, frame: CGRect)] = []
            var stack: [XCUIElementSnapshot] = [root]
            let bounds = visible.insetBy(dx: -1, dy: -1)
            while let node = stack.popLast() {
                if node.identifier.hasPrefix("character-U+"), usableHeightFrame(node.frame), bounds.contains(node.frame) {
                    tiles.append((node.identifier, node.frame))
                }
                stack.append(contentsOf: node.children)
            }
            return tiles
        }
        /// Frames of the topmost row of tiles lying fully inside the visible grid.
        func firstRow() -> [CGRect] {
            let frames = visibleTiles().map(\.frame)
            guard let top = frames.map(\.minY).min() else { return [] }
            return frames.filter { abs($0.minY - top) < 5 }.sorted { $0.minX < $1.minX }
        }
        /// Pinches once and waits for the column count to settle, returning it.
        func pinch(zoomOut: Bool, from count: Int) -> Int {
            let center = CGPoint(x: visible.midX, y: visible.midY)
            let distance = { (frame: CGRect) in hypot(frame.midX - center.x, frame.midY - center.y) }
            guard let target = visibleTiles().min(by: { distance($0.frame) < distance($1.frame) }) else {
                XCTFail("No visible tile to pinch")
                return -1
            }
            let tile = app.buttons[target.id].firstMatch
            if zoomOut { tile.pinch(withScale: 0.5, velocity: -1) } else { tile.pinch(withScale: 2, velocity: 1) }
            if app.buttons["copyCharacter"].firstMatch.waitForExistence(timeout: 1) {
                attachDiagnostics("A pinch opened the character inspector")
                XCTFail("Pinching on \(target.id) opened the character inspector instead of zooming")
                return -1
            }
            if !grid.waitForExistence(timeout: 2) {
                print("PINCH LOST GRID: state \(app.state.rawValue)\n\(app.debugDescription)")
                attachDiagnostics("Explore grid missing after a pinch")
                XCTFail("The Explore grid disappeared after a pinch")
                return -1
            }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in firstRow().count != count }, object: nil)
            _ = XCTWaiter.wait(for: [changed], timeout: 3)
            sleep(1) // let the snappy column animation finish before measuring frames
            return firstRow().count
        }

        // The grid keeps 16pt margins inside its 780pt maximum; tiles stay >= 32pt with 8pt gaps.
        let gridWidth = min(grid.frame.width, 780) - 32
        let expectedMaximum = Int(((gridWidth + 8) / 40).rounded(.down))
        var columns = firstRow().count
        XCTAssertGreaterThanOrEqual(columns, 2, "Explore shows a tile grid")
        var zoomOutCounts = [columns]
        for _ in 0..<12 {
            let next = pinch(zoomOut: true, from: columns)
            zoomOutCounts.append(next)
            if next == columns && columns >= expectedMaximum { break }
            columns = next
        }
        let row = firstRow()
        let widths = row.map(\.width)
        let summary = "columns \(row.count) (expected maximum \(expectedMaximum) for grid width \(gridWidth)), tile widths \(widths), pinch sequence \(zoomOutCounts)"
        print("PINCH ZOOM MAX: \(summary)")
        let measurement = XCTAttachment(string: summary)
        measurement.name = "Maximum zoom measurement"
        measurement.lifetime = .keepAlways
        add(measurement)
        attachScreenshot("Explore at maximum zoom past 7 columns")
        XCTAssertGreaterThan(row.count, 7, "Pinching zooms out past 7 columns: \(summary)")
        XCTAssertEqual(row.count, expectedMaximum, "Zoom stops at the narrowest 32pt tiles: \(summary)")
        for width in widths { XCTAssertGreaterThanOrEqual(width, 32, "Every tile stays at least 32pt wide: \(summary)") }
        XCTAssertEqual(pinch(zoomOut: true, from: row.count), row.count, "Pinching further keeps the maximum")

        // Spreading the fingers zooms back in, one column per pinch, to 7 or fewer and then the default 3.
        columns = row.count
        var zoomInCounts = [columns]
        while columns > 3, zoomInCounts.count < 12 {
            let next = pinch(zoomOut: false, from: columns)
            zoomInCounts.append(next)
            XCTAssertEqual(next, columns - 1, "Each spread removes one column: \(zoomInCounts)")
            columns = next
        }
        print("PINCH ZOOM IN: \(zoomInCounts)")
        XCTAssertLessThanOrEqual(columns, 7, "Spreading returns to 7 or fewer columns: \(zoomInCounts)")
        XCTAssertEqual(columns, 3, "The shared column preference is restored for later tests")
        attachScreenshot("Explore zoomed back in to 3 columns")
    }

    func testEmojiSortByVersionAndExploreHighToLow() {
        selectAppTab("Emoji")
        let order = app.buttons["emojiOrder"].firstMatch
        XCTAssertTrue(order.waitForExistence(timeout: 5))
        order.tap()
        app.buttons["Newest first"].firstMatch.tap()
        XCTAssertTrue(order.waitUntilValueEquals("Newest first"))
        attachScreenshot("Emoji sorted newest first")
        order.tap()
        app.buttons["Code point"].firstMatch.tap()
        XCTAssertTrue(order.waitUntilValueEquals("Code point"))
        selectAppTab("Explore")
        let options = app.buttons["exploreDensity"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Tiles"].firstMatch.tap()
        options.tap()
        app.buttons["High to Low"].firstMatch.tap()
        // Plane 14's last variation selector is the highest character shown by default.
        XCTAssertTrue(app.descendants(matching: .any)["character-U+E01EF"].firstMatch.waitForExistence(timeout: 10),
                      "High to low starts at the top of the code space")
        attachScreenshot("Explore from the highest code point")
        options.tap()
        app.buttons["Low to High"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["character-U+0020"].firstMatch.waitForExistence(timeout: 10))
    }

    func testConScriptCharactersShowTheirBlock() {
        setAppUCSUR(true)
        setAppPrefersUCSUR(false)
        selectAppTab("Explore")
        searchUnicode("U+F8D0")
        dismissAppSearchKeyboard()
        let klingon = character("U+F8D0")
        XCTAssertTrue(klingon.waitForExistence(timeout: 10))
        attachScreenshot("ConScript character tinted blue")
        XCTAssertTrue(klingon.label.contains("PRIVATE USE-F8D0"), "Without Prefer, the Unicode name stays")
        klingon.tap()
        let block = app.descendants(matching: .any)["characterProperties.ucsur"].firstMatch
        revealByScrolling(block, in: app)
        XCTAssertEqual(accessibleText(block), "Klingon")
        XCTAssertEqual(accessibleText(app.descendants(matching: .any)["characterProperties.ucsurName"].firstMatch), "KLINGON LETTER A")
        attachScreenshot("ConScript metadata in details")
        app.swipeDown(velocity: .fast)
        setAppPrefersUCSUR(true)
        selectAppTab("Explore")
        searchUnicode("U+F8D0")
        dismissAppSearchKeyboard()
        XCTAssertTrue(klingon.waitForExistence(timeout: 10))
        XCTAssertTrue(klingon.label.contains("KLINGON LETTER A"), "Prefer ConScript names the character: \(klingon.label)")
        attachScreenshot("ConScript name preferred")
        // Opening the character also puts the search keyboard away.
        klingon.tap()
        app.swipeDown(velocity: .fast)
        setAppPrefersUCSUR(false)
        setAppUCSUR(false)
    }

    func testEmojiDetailsAndScratchpadPreserveWholeZWJSequence() {
        selectAppTab("Emoji")
        search("woman technologist", fieldIdentifier: "emojiSearch")
        dismissAppSearchKeyboard()
        let emoji = app.buttons["emoji-1F469-200D-1F4BB"].firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 10))
        attachScreenshot("Whole emoji sequence in app search results")
        emoji.tap()
        let codepoints = app.descendants(matching: .any)["emojiProperties.codepoints"].firstMatch
        XCTAssertTrue(codepoints.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(codepoints), "U+1F469 U+200D U+1F4BB")
        XCTAssertTrue(app.buttons["copyEmoji"].exists)
        attachScreenshot("Woman technologist whole sequence details")
        let add = app.buttons["addEmojiToScratchpad"].firstMatch
        revealByScrolling(add, in: app)
        add.tap()
        app.buttons["Done"].tap()
        selectAppTab("Explore")
        let scratchpad = app.buttons["openScratchpad"].firstMatch
        revealByScrolling(scratchpad, in: app)
        scratchpad.tap()
        let input = app.textViews["scratchpadInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.waitUntilValueEquals("👩‍💻"))
        XCTAssertEqual((input.value as? String)?.unicodeScalars.map { $0.value }, [0x1F469, 0x200D, 0x1F4BB])
        attachScreenshot("Scratchpad preserves exact whole emoji sequence")
    }

    func testUnsupportedGlyphStillShowsNameDescriptionAndProperties() {
        selectAppEdition("latest")
        searchUnicode("U+1FAEB")
        let crackingFace = assertCharacterVisible("U+1FAEB")
        XCTAssertTrue(crackingFace.waitUntilValueEquals("Unicode 18.0"))
        crackingFace.press(forDuration: 1)
        assertCharacterProperty("name", contains: "cracking face")
        assertCharacterProperty("codepoints", equals: "U+1FAEB")
        assertCharacterProperty("age", equals: "18.0")
        let description = app.descendants(matching: .any)["characterProperties.description"].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertFalse(accessibleText(description).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "An unavailable font glyph must not hide its descriptive Unicode metadata")
        attachScreenshot("Unicode18 cracking face retains meaning when the font lacks its glyph")
    }
}
