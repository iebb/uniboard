import XCTest
import UIKit

/// The keyboard's text preview row: cursor, Inspect Text and Copy Image.
@MainActor
final class TextPreviewUITests: UniboardUITestCase {
    func testUnicodeKeyOpensSearchUnderTheTextPreview() throws {
        try requirePhoneKeyboardIntegration()
        // The one test that turns the preview on with the Settings switch;
        // the next setUp launch turns it off again. Any relaunch with the
        // setUp arguments turns it off too, so enable Uniboard in Settings
        // (which needs a relaunch) before flipping the switch, and open the
        // host without relaunching.
        if enableUniboardInSettings() {
            app.terminate()
            app.launch()
        }
        setAppTextPreview(true)
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard() }
        _ = openSystemKeyboardHost(initialText: "ab", unicodeBrowse: false, afterSetUpLaunch: true)
        let toggle = app.buttons["keyboard.toggleUnicodeToolbar"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.openTyping"].firstMatch.waitUntilValueEquals("query"),
                      "U opens search with its keys, not the browse grid")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitForExistence(timeout: 5))
        let preview = app.descendants(matching: .any)["keyboard.textPreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "The text preview stays above search")
        attachScreenshot("U opens search under the text preview")
    }

    /// iPhone portrait: Copy Image grows the keyboard by 96 points, so
    /// choosing Custom shows both swatch lines and a 44-point Copy without
    /// scrolling; closing the panel returns the keyboard to its height.
    func testCopyImagePanelGrowsTheKeyboardSoCustomColorsShowWithoutScrolling() throws {
        try requirePhoneKeyboardIntegration()
        app.launchArguments = Self.textPreviewLaunchArguments
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard() }
        _ = openSystemKeyboardHost(initialText: "Copy this", unicodeBrowse: false)
        let actions = app.buttons["keyboard.textPreview.actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        let closed = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        actions.tap()
        let panel = app.descendants(matching: .any)["keyboard.previewImage.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        // Copy Image with Full Access; without it, OK in the same 44-point action.
        let copy = app.buttons.matching(NSPredicate(format: "identifier IN %@",
            ["keyboard.previewImage.copy", "keyboard.previewImage.ok"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        sleep(1) // The 0.2 second height change settles.
        let open = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        XCTAssertEqual(open.height - closed.height, 96, accuracy: 1, "The panel adds 96 points in iPhone portrait")
        XCTAssertEqual(open.maxY, closed.maxY, accuracy: 1, "The keyboard grows upward")
        XCTAssertTrue(open.insetBy(dx: -1, dy: -1).contains(panel.frame), "The panel covers the keyboard, inside it")
        XCTAssertGreaterThan(panel.frame.height, open.height - 12, "The card covers the whole keyboard, inset 4 points")
        XCTAssertFalse(app.buttons["keyboard.typing.key.q"].firstMatch.isHittable, "No key shows through the panel")
        let custom = app.buttons["keyboard.previewImage.colors.custom"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        let wasCustom = custom.isSelected
        custom.tap()
        XCTAssertTrue(custom.waitUntilSelected())
        for line in ["text", "background"] {
            let swatch = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "keyboard.previewImage.\(line).")).firstMatch
            XCTAssertTrue(swatch.waitForExistence(timeout: 5))
            XCTAssertTrue(swatch.isHittable, "The \(line) line shows without scrolling")
            XCTAssertTrue(panel.frame.contains(swatch.frame), "The \(line) line is inside the panel")
        }
        XCTAssertEqual(copy.frame.height, 44, accuracy: 1, "The panel's action is a 44-point button")
        XCTAssertTrue(copy.isHittable)
        XCTAssertTrue(panel.frame.contains(copy.frame))
        attachScreenshot("Copy Image with Custom colors on a taller keyboard")

        // A low-contrast pair: the note replaces the caption, clear of the footer.
        func selectedSwatch(_ line: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true",
                                             "keyboard.previewImage.\(line).")).firstMatch
        }
        let previous = ["text", "background"].map { selectedSwatch($0).identifier }
        app.buttons["keyboard.previewImage.text.#FF9500"].firstMatch.tap()
        app.buttons["keyboard.previewImage.background.#FF3B30"].firstMatch.tap()
        let note = app.descendants(matching: .any)["keyboard.previewImage.readability"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleText(note).contains("This text may be hard to read."), accessibleText(note))
        XCTAssertFalse(app.staticTexts["Colors · Custom"].exists, "The note takes the caption's place")
        XCTAssertTrue(note.isHittable)
        XCTAssertLessThan(note.frame.maxY, copy.frame.minY - 8, "The footer separator never clips the note")
        XCTAssertLessThan(note.frame.maxY, custom.frame.minY + 1, "The note sits on the caption line, above the chips")
        let colorsGroup = app.descendants(matching: .any)["keyboard.previewImage.colors"].firstMatch
        XCTAssertEqual(colorsGroup.label, "Image colors", "The group's VoiceOver label is unchanged")
        attachScreenshot("Copy Image low-contrast Custom colors show the note on the caption line")
        for identifier in previous where !identifier.isEmpty { app.buttons[identifier].firstMatch.tap() }
        if !wasCustom { app.buttons["keyboard.previewImage.colors.blackOnWhite"].firstMatch.tap() }
        app.buttons["keyboard.previewImage.close"].firstMatch.tap()
        XCTAssertTrue(panel.waitUntilAbsent())
        sleep(1)
        let after = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        XCTAssertEqual(after.height, closed.height, accuracy: 1, "Closing returns the keyboard to its height")
        XCTAssertEqual(app.buttons["keyboard.typing.key.q"].firstMatch.frame.height, 41.4, accuracy: 1, "Keys never changed size")
    }

    /// Copy Image's Size block (design/copy-image/size-choice): with a preset,
    /// the caption and the three 44-point chips show without scrolling, a tap
    /// selects at once, updates the caption, and the choice is remembered.
    func testCopyImageSizeChipsShowWithoutScrollingAndAreRemembered() throws {
        try requirePhoneKeyboardIntegration()
        app.launchArguments = Self.textPreviewLaunchArguments
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard() }
        _ = openSystemKeyboardHost(initialText: "Copy this", unicodeBrowse: false)
        let actions = app.buttons["keyboard.textPreview.actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["keyboard.previewImage.panel"].firstMatch
        func openPanel() {
            actions.tap()
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            sleep(1) // The 0.2 second height change settles.
        }
        func chip(_ scale: Int) -> XCUIElement { app.buttons["keyboard.previewImage.size.\(scale)"].firstMatch }
        let caption = app.staticTexts["keyboard.previewImage.size.caption"].firstMatch
        openPanel()
        let preset = app.buttons["keyboard.previewImage.colors.blackOnWhite"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        let previousColors = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true",
                                                               "keyboard.previewImage.colors.")).firstMatch.identifier
        preset.tap()
        XCTAssertTrue(preset.waitUntilSelected())
        let previousScale = (1...3).first { chip($0).isSelected } ?? 3
        let copy = app.buttons.matching(NSPredicate(format: "identifier IN %@",
            ["keyboard.previewImage.copy", "keyboard.previewImage.ok"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertTrue(caption.label.hasPrefix("Size, ") && caption.label.hasSuffix(" pixels"), caption.label)
        var previousFrame: CGRect?
        for scale in 1...3 {
            let element = chip(scale)
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            XCTAssertTrue(element.isHittable, "\(scale)× shows without scrolling")
            XCTAssertEqual(element.frame.width, 44, accuracy: 1)
            XCTAssertEqual(element.frame.height, 44, accuracy: 1)
            XCTAssertLessThan(element.frame.maxY, copy.frame.minY - 8, "\(scale)× sits above the pinned footer")
            XCTAssertEqual(element.label, "\(scale) times scale")
            XCTAssertGreaterThan(element.frame.minY, preset.frame.maxY, "Size follows Colors")
            if let previousFrame { XCTAssertEqual(element.frame.minX - previousFrame.maxX, 12, accuracy: 1, "12 points apart") }
            previousFrame = element.frame
        }
        let other = previousScale == 2 ? 1 : 2
        let before = caption.label
        chip(other).tap()
        XCTAssertTrue(chip(other).waitUntilSelected())
        XCTAssertEqual((1...3).filter { chip($0).isSelected }, [other], "Exactly one size is selected")
        XCTAssertNotEqual(caption.label, before, "The caption shows the new pixel size")
        XCTAssertEqual(chip(other).value as? String, String(caption.label.dropFirst("Size, ".count)),
                       "The selected chip's value is the size it copies")
        attachScreenshot("Copy Image size chips with \(other)× selected")
        app.buttons["keyboard.previewImage.close"].firstMatch.tap()
        XCTAssertTrue(panel.waitUntilAbsent())
        // Remembered when the panel opens again.
        openPanel()
        XCTAssertTrue(chip(other).waitUntilSelected(), "The size is remembered")
        chip(previousScale).tap()
        XCTAssertTrue(chip(previousScale).waitUntilSelected())
        if !previousColors.isEmpty, previousColors != preset.identifier { app.buttons[previousColors].firstMatch.tap() }
        app.buttons["keyboard.previewImage.close"].firstMatch.tap()
        XCTAssertTrue(panel.waitUntilAbsent())
    }

    /// The Inspect button sits beside ⋯ as two adjacent 44-point targets;
    /// the panel inspects the visible excerpt in the Copy Image container
    /// and closing it restores the keyboard and the host text.
    func testInspectTextPanelInspectsThePreviewAndClosingRestoresTheKeyboard() throws {
        try requirePhoneKeyboardIntegration()
        app.launchArguments = Self.textPreviewLaunchArguments
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard() }
        let input = openSystemKeyboardHost(initialText: "Abc", unicodeBrowse: false)
        let preview = app.descendants(matching: .any)["keyboard.textPreview"].firstMatch
        let inspect = app.buttons["keyboard.textPreview.inspect"].firstMatch
        let actions = app.buttons["keyboard.textPreview.actions"].firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.exists)
        XCTAssertEqual(inspect.label, "Inspect preview text")
        XCTAssertEqual(actions.label, "Preview actions")
        XCTAssertEqual(inspect.frame.width, 44, accuracy: 1, "Inspect has its own 44-point target")
        XCTAssertEqual(actions.frame.width, 44, accuracy: 1, "⋯ has its own 44-point target")
        XCTAssertEqual(inspect.frame.maxX, actions.frame.minX, accuracy: 1, "Inspect sits directly before ⋯")
        // The preview's accessibility frame hugs the drawn text, so it only has to end before Inspect.
        XCTAssertLessThanOrEqual(preview.frame.maxX, inspect.frame.minX + 1, "The text never runs under Inspect")
        XCTAssertEqual(inspect.frame.midY, preview.frame.midY, accuracy: 2, "The icons are centred in the row")
        XCTAssertGreaterThanOrEqual(inspect.frame.height, 41)
        attachScreenshot("Preview row with grey Inspect and ⋯ icons")

        let closed = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        inspect.tap()
        let panel = app.descendants(matching: .any)["keyboard.inspect.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        sleep(1) // The 0.2 second height change settles.
        let open = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        XCTAssertEqual(open.height - closed.height, 96, accuracy: 1, "Inspect grows the keyboard like Copy Image")
        XCTAssertEqual(open.maxY, closed.maxY, accuracy: 1, "The keyboard grows upward")
        XCTAssertTrue(open.insetBy(dx: -1, dy: -1).contains(panel.frame), "The panel covers the keyboard, inside it")
        XCTAssertFalse(app.buttons["keyboard.typing.key.q"].firstMatch.isHittable, "No key shows through the panel")
        XCTAssertFalse(actions.isEnabled, "⋯ is unavailable while Inspect Text is open")

        let sample = app.descendants(matching: .any)["keyboard.inspect.sample"].firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        XCTAssertEqual(sample.value as? String, "Abc", "The frozen visible excerpt")
        let totals = app.descendants(matching: .any)["keyboard.inspect.totals"].firstMatch
        XCTAssertEqual(accessibleText(totals), "3 code points · 3 grapheme clusters · 3 UTF-16 code units")
        for form in ["NFC", "NFD", "NFKC", "NFKD"] {
            XCTAssertTrue(app.buttons["keyboard.inspect.chip.\(form)"].firstMatch.exists, form)
        }
        for cluster in 0..<3 {
            XCTAssertTrue(app.descendants(matching: .any)["keyboard.inspect.cluster.\(cluster)"].firstMatch.exists, "One card per cluster")
        }
        let first = app.buttons["keyboard.inspect.codePoint.0"].firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertEqual(first.label, "U+0041, LATIN CAPITAL LETTER A")
        // minHeight 44; a fractional origin converts to screen space with float error.
        XCTAssertGreaterThanOrEqual(first.frame.height, 44 - 0.01)
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.inspect.details.0"].firstMatch.waitForExistence(timeout: 5),
                      "Tapping a code point expands its properties")
        XCTAssertTrue((first.value as? String ?? "").hasSuffix("expanded"), String(describing: first.value))

        let copyText = app.buttons["keyboard.inspect.copyText"].firstMatch
        let copyCodePoints = app.buttons["keyboard.inspect.copyCodePoints"].firstMatch
        for button in [copyText, copyCodePoints] {
            XCTAssertTrue(button.exists)
            XCTAssertEqual(button.frame.height, 44, accuracy: 1, "Copy buttons are 44-point targets")
            XCTAssertTrue(panel.frame.contains(button.frame))
        }
        let notice = app.descendants(matching: .any)["keyboard.inspect.copyNotice"].firstMatch
        if notice.exists {
            // Without Full Access the panel still inspects; copying alone is blocked.
            XCTAssertEqual(accessibleText(notice), "To copy from the inspector, allow Full Access for Uniboard in your keyboard settings. You can still inspect text and type without it.")
            XCTAssertFalse(copyText.isEnabled)
        }
        attachScreenshot("Inspect Text with the first code point expanded")

        app.buttons["keyboard.inspect.close"].firstMatch.tap()
        XCTAssertTrue(panel.waitUntilAbsent())
        sleep(1)
        let after = try XCTUnwrap(measuredKeyboardSurfaceFrame())
        XCTAssertEqual(after.height, closed.height, accuracy: 1, "Closing returns the keyboard to its height")
        XCTAssertEqual(input.value as? String, "Abc", "Inspecting never changes the host text")
        XCTAssertTrue(actions.isEnabled)
        XCTAssertTrue(app.buttons["keyboard.typing.key.q"].firstMatch.isHittable)
    }

    /// Checks 1 and 2: taps across "Café בּרא 👩‍💻" land the app's cursor on
    /// whole characters only, including between ר and א, before and after
    /// the whole é and the whole emoji.
    func testPreviewCursorTapsLandOnWholeCharacters() throws {
        let (input, preview, fixture) = try openPreviewCursorFixture("previewfixture1")
        attachScreenshot("Preview cursor: Café בּרא 👩‍💻 as one shaped line")
        let landed = sweepPreviewTaps(input: input, preview: preview, fixture: fixture,
                                      from: 3, through: min(preview.frame.width - 30, 190), required: [[9], [11], [5, 6]])
        XCTAssertTrue(landed.contains(9), "A tap lands between ר and א: \(landed.sorted())")
        XCTAssertTrue(landed.contains(11), "A tap lands before the whole emoji: \(landed.sorted())")
        XCTAssertTrue(landed.contains(6) || landed.contains(5), "A tap lands after the whole é: \(landed.sorted())")
        for inside in [4, 7, 12, 13, 14, 15] {
            XCTAssertFalse(landed.contains(inside), "Never inside a cluster (\(inside))")
        }
        attachScreenshot("Preview cursor after the last tap")
    }

    /// Check 10: "שלום abc" is right-aligned and a tap between ל and ו puts
    /// the app's cursor between them in reading order.
    func testPreviewCursorRightToLeftLine() throws {
        let (input, preview, fixture) = try openPreviewCursorFixture("previewfixture2")
        attachScreenshot("Preview cursor: right-aligned שלום abc")
        let width = preview.frame.width
        let landed = sweepPreviewTaps(input: input, preview: preview, fixture: fixture,
                                      from: max(3, width - 130), through: width - 3, required: [[2], [0], [fixture.utf16.count]])
        XCTAssertTrue(landed.contains(2), "A tap lands between ל and ו: \(landed.sorted())")
        XCTAssertTrue(landed.contains(0), "The logical start is at the right: \(landed.sorted())")
        XCTAssertTrue(landed.contains(fixture.utf16.count), "Past the visual end (left): the line end: \(landed.sorted())")
    }

    /// Checks 3, 8 and 6: a mid-line tap in a long line, an edge hold that
    /// steps toward the start, Copy Image of the visible text, and a tap in
    /// the app that resets the preview. Then checks 5, 11 and 12: typing never
    /// moves the cursor, and nothing moves while the app has a selection.
    func testPreviewCursorLongLineDragAndCopyImage() throws {
        try requirePhoneKeyboardIntegration()
        app.launchArguments = Self.textPreviewLaunchArguments
        addTeardownBlock { @MainActor [self] in restoreEnglishKeyboard() }
        let text = "The quick brown fox jumps over the lazy dog while the preview keeps scrolling"
        let input = openSystemKeyboardHost(initialText: text, unicodeBrowse: false)
        let preview = app.descendants(matching: .any)["keyboard.textPreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        attachScreenshot("Preview cursor: long line, cursor at the end")
        tapPreview(preview, at: preview.frame.width / 2)
        attachScreenshot("Preview cursor: mid-line tap, nothing slid")
        let middle = try XCTUnwrap(markCursor(input: input, original: text), "The tap moved the app's cursor")
        XCTAssertLessThan(middle, text.utf16.count - 3, "The cursor moved into the line")
        XCTAssertGreaterThan(middle, 10)

        // Hold at the left edge: steady steps, faster after one second.
        usleep(400_000)
        let start = preview.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: preview.frame.width / 2, dy: 0))
        let edge = preview.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 6, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: edge, withVelocity: .default, thenHoldForDuration: 2)
        sleep(1)
        attachScreenshot("Preview cursor: after holding at the left edge")
        let stepped = try XCTUnwrap(markCursor(input: input, original: text), "The edge hold moved the app's cursor")
        XCTAssertLessThan(stepped, middle - 10, "Edge stepping walked toward the line start")

        // Copy Image freezes exactly the visible text.
        let inspect = app.buttons["keyboard.textPreview.inspect"].firstMatch
        inspect.tap()
        let sample = app.descendants(matching: .any)["keyboard.inspect.sample"].firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        let visible = sample.value as? String ?? ""
        XCTAssertFalse(visible.isEmpty)
        XCTAssertTrue(text.contains(visible), "Inspect freezes a run of the visible line: \(visible)")
        app.buttons["keyboard.inspect.close"].firstMatch.tap()
        let actions = app.buttons["keyboard.textPreview.actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        let thumbnail = app.descendants(matching: .any)["keyboard.previewImage.thumbnail"].firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        XCTAssertTrue((thumbnail.value as? String ?? "").contains(visible), "The picture equals the visible text")
        attachScreenshot("Preview cursor: Copy Image of the visible text")
        app.buttons["keyboard.previewImage.close"].firstMatch.tap()

        // A tap in the app's text moves the cursor there; the preview follows.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        sleep(1)
        attachScreenshot("Preview cursor: reset after a tap in the app")
        XCTAssertEqual(input.value as? String, text, "Nothing typed or lost")

        // Checks 5, 11 and 12, in the same session: typing never moves the
        // cursor, and nothing moves while the app has a selection. A tap at
        // the end of the app's text puts its cursor back there first.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
        sleep(1)
        // Type on the number row and letters for about ten seconds.
        var expected = text
        let started = Date()
        let keys = ["keyboard.typing.number.1", "keyboard.typing.number.2", "keyboard.typing.number.3",
                    "keyboard.typing.key.a", "keyboard.typing.key.s"]
        var index = 0
        while Date().timeIntervalSince(started) < 10 {
            let key = app.buttons[keys[index % keys.count]].firstMatch
            key.tap()
            expected += String(keys[index % keys.count].last!)
            index += 1
        }
        XCTAssertTrue(input.waitUntilValueEquals(expected), "Every key typed at the end: \(String(describing: input.value))")

        // Select a word in the app: the preview moves nothing.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 20, dy: 18)).doubleTap()
        sleep(1)
        attachScreenshot("Preview cursor: a word selected in the app")
        tapPreview(preview, at: 8)
        sleep(1)
        XCTAssertEqual(input.value as? String, expected, "Nothing moved or replaced")
        attachScreenshot("Preview cursor: tap ignored while the app has a selection")
        // Deselect by tapping at the end; the preview works again.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
        sleep(1)
        tapPreview(preview, at: 8)
        let landed = markCursor(input: input, original: expected)
        XCTAssertNotNil(landed)
        XCTAssertLessThan(landed ?? .max, expected.utf16.count, "The tap moved the cursor into the line")
    }
}
