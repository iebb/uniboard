#if canImport(UIKit)
import XCTest
import UIKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import Uniboard

@MainActor
final class KeyboardPreviewImageExportTests: XCTestCase {
    /// Ten points per character keeps the layout arithmetic exact.
    private let measure: (String) -> CGFloat = { CGFloat($0.count) * 10 }
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    // MARK: Visible text only

    func testExcerptKeepsEverythingThatFits() {
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: "Hello ", after: "world", availableWidth: 200, measure: measure)
        XCTAssertEqual(excerpt, KeyboardPreviewExcerpt(before: "Hello ", after: "world", beforeTruncated: false, afterTruncated: false))
        XCTAssertEqual(excerpt.visibleText, "Hello world")
    }

    func testExcerptShowsOnlyTheVisibleEndOfLongTextBeforeTheCaret() {
        let hidden = "HIDDENSENTINEL "
        let before = hidden + String(repeating: "a", count: 30) + "near"
        // 100 pt minus caret and slack leaves 96 pt: the ellipsis and eight characters.
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: "", availableWidth: 100, measure: measure)
        XCTAssertEqual(excerpt.before, "…aaaanear")
        XCTAssertTrue(excerpt.beforeTruncated)
        XCTAssertFalse(excerpt.visibleText.contains("HIDDEN"))
        XCTAssertFalse(excerpt.visibleText.contains("SENTINEL"))
        XCTAssertLessThanOrEqual(measure(excerpt.before), 100 - KeyboardTextPreviewLayout.caretWidth - KeyboardTextPreviewLayout.fittingSlack)
    }

    func testExcerptKeepsBeforePriorityAndTruncatesHiddenTextAfterTheCaret() {
        let after = "next" + String(repeating: "z", count: 30) + " TAILSENTINEL"
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: "abc", after: after, availableWidth: 100, measure: measure)
        XCTAssertEqual(excerpt.before, "abc")
        XCTAssertEqual(excerpt.after, "nextz…")
        XCTAssertTrue(excerpt.afterTruncated)
        XCTAssertFalse(excerpt.visibleText.contains("TAIL"))
        XCTAssertLessThanOrEqual(measure(excerpt.before) + measure(excerpt.after), 96)
    }

    func testBothSidesTruncatedNeverRevealHiddenContext() {
        let before = "BEFORESENTINEL" + String(repeating: "b", count: 40)
        let after = String(repeating: "c", count: 20) + "AFTERSENTINEL"
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: after, availableWidth: 150, measure: measure)
        XCTAssertTrue(excerpt.beforeTruncated)
        XCTAssertTrue(excerpt.afterTruncated)
        XCTAssertTrue(excerpt.before.hasPrefix("…"))
        XCTAssertEqual(excerpt.after, "…", "Earlier text has priority; later text keeps an honest marker")
        XCTAssertFalse(excerpt.visibleText.contains("SENTINEL"))
        XCTAssertLessThanOrEqual(measure(excerpt.before) + measure(excerpt.after), 146)
    }

    func testOtherLinesAreHiddenContextMarkedWithAnEllipsis() {
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: "PREVIOUS LINE\nab", after: "cd\nNEXT LINE",
                                                        availableWidth: 400, measure: measure)
        XCTAssertEqual(excerpt.before, "…ab")
        XCTAssertEqual(excerpt.after, "cd…")
        XCTAssertFalse(excerpt.visibleText.contains("LINE"))
    }

    func testCombiningSequencesAndEmojiAreNeverSplit() {
        let before = "x" + String(repeating: "e\u{301}", count: 10) + "👩🏽‍💻"
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: "", availableWidth: 60, measure: measure)
        XCTAssertEqual(excerpt.before, "…e\u{301}e\u{301}e\u{301}👩🏽‍💻")
    }

    func testRealFontLayoutFitsTheRowAndMatchesMeasuredWidth() {
        let before = "CONTEXTSENTINEL " + String(repeating: "Uniboard keyboard ", count: 3)
        let width: CGFloat = 220
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: "after the caret", availableWidth: width)
        XCTAssertFalse(excerpt.visibleText.contains("SENTINEL"))
        let used = KeyboardTextPreviewLayout.width(of: excerpt.before) + KeyboardTextPreviewLayout.width(of: excerpt.after)
        XCTAssertLessThanOrEqual(used, width - KeyboardTextPreviewLayout.caretWidth)
        XCTAssertTrue(excerpt.beforeTruncated)
    }

    func testExcerptIsMeasuredAgainAfterAFontChange() {
        let before = "Font generation " + UUID().uuidString
        let prefersConScript = UnicodeFontSupport.prefersConScript
        defer { UnicodeFontSupport.prefersConScript = prefersConScript }
        let first = KeyboardTextPreviewLayout.excerpt(before: before, after: "after", availableWidth: 200)
        let measured = KeyboardTextPreviewLayout.measuredLayoutCount
        XCTAssertEqual(KeyboardTextPreviewLayout.excerpt(before: before, after: "after", availableWidth: 200), first)
        XCTAssertEqual(KeyboardTextPreviewLayout.measuredLayoutCount, measured, "Unchanged text and fonts reuse the layout")

        let generation = UnicodeFontSupport.fontGeneration
        UnicodeFontSupport.clearCache()
        XCTAssertNotEqual(UnicodeFontSupport.fontGeneration, generation)
        XCTAssertEqual(KeyboardTextPreviewLayout.excerpt(before: before, after: "after", availableWidth: 200), first)
        XCTAssertEqual(KeyboardTextPreviewLayout.measuredLayoutCount, measured + 1, "A font cache reset measures again")

        let beforeToggle = UnicodeFontSupport.fontGeneration
        UnicodeFontSupport.prefersConScript.toggle()
        XCTAssertNotEqual(UnicodeFontSupport.fontGeneration, beforeToggle)
        let toggled = KeyboardTextPreviewLayout.excerpt(before: before, after: "after", availableWidth: 200)
        XCTAssertEqual(KeyboardTextPreviewLayout.measuredLayoutCount, measured + 2, "The ConScript preference measures again")
        XCTAssertEqual(toggled, KeyboardTextPreviewLayout.excerpt(before: before, after: "after", availableWidth: 200,
                                                                  measurer: KeyboardTextPreviewLayout.Measurer()))
        XCTAssertEqual(KeyboardTextPreviewLayout.measuredLayoutCount, measured + 2)
    }

    func testSingleLineMeasurementMatchesMeasuringEachCandidate() {
        let samples = [
            "Typing quickly in Uniboard, AVATAR To WAVE",
            "cafe\u{301} nai\u{308}ve o\u{323}\u{302} gjpq\u{0303}\u{0323} x\u{301}\u{302}\u{303}",
            "👩🏽‍💻 🍎🇯🇵 family 👨‍👩‍👧‍👦 ok ✌️ 1️⃣ 🏳️‍🌈",
            "mixed שלום עולם with text e\u{301}🍎",
        ]
        for sample in samples {
            for text in [sample, String(sample.prefix(7)), String(sample.suffix(9)), "…" + sample, sample + "…"] {
                XCTAssertEqual(KeyboardTextPreviewLayout.Measurer().width(of: text), legacyWidth(text), text)
                XCTAssertEqual(KeyboardTextPreviewLayout.width(of: text), legacyWidth(text), text)
            }
            let cases = [(sample, ""), ("", sample), (sample, sample), ("PREVIOUS\n" + sample, sample + "\nNEXT")]
            for (before, after) in cases {
                for width: CGFloat in [0, 20, 45, 90, 150, 220, 320, 900] {
                    var legacyCalls = 0
                    let legacy = KeyboardTextPreviewLayout.excerpt(before: before, after: after, availableWidth: width,
                                                                   measure: { legacyCalls += 1; return self.legacyWidth($0) })
                    var resolved: [String: Int] = [:]
                    let measurer = KeyboardTextPreviewLayout.Measurer(font: {
                        resolved[$0, default: 0] += 1
                        return KeyboardTextPreviewLayout.font(for: $0)
                    })
                    let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: after, availableWidth: width,
                                                                    measurer: measurer)
                    XCTAssertEqual(excerpt, legacy, "\(before.debugDescription) | \(after.debugDescription) at \(width)")
                    XCTAssertEqual(resolved.values.max() ?? 1, 1, "Each character's font is resolved once per layout")
                    XCTAssertLessThanOrEqual(measurer.shapedLineCount, legacyCalls)
                }
            }
        }
    }

    // MARK: Rendering

    func testRendersAnOpaquePNGAtThreeTimesScale() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "Hello", after: " world", beforeTruncated: false, afterTruncated: false)
        let image = try render(excerpt, traits: light)
        XCTAssertEqual(image.scale, 3)
        XCTAssertEqual(CGFloat(image.pixelWidth), image.pointSize.width * 3, accuracy: 0.01)
        XCTAssertEqual(CGFloat(image.pixelHeight), image.pointSize.height * 3, accuracy: 0.01)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(cgImage.width, image.pixelWidth)
        XCTAssertEqual(cgImage.height, image.pixelHeight)
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(cgImage.alphaInfo), "PNG has no alpha channel")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual((properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0, 216, accuracy: 1)
        // Logical size covers the text plus eight points of padding either side.
        let textWidth = KeyboardTextPreviewLayout.width(of: "Hello") + 2 + KeyboardTextPreviewLayout.width(of: " world")
        XCTAssertGreaterThanOrEqual(image.pointSize.width, textWidth + 16 - 1)
        XCTAssertLessThan(image.pointSize.width, textWidth + 16 + 4)
        let pixels = try rgba(cgImage)
        XCTAssertEqual(pixels.pixel(0, 0), [255, 255, 255, 255], "Light appearance backs text with opaque white")
        XCTAssertTrue(pixels.hasDarkInk, "Text is drawn in the resolved label color")
    }

    func testDarkAppearanceUsesOpaqueBlackBackingAndLightText() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "Dark", after: "", beforeTruncated: false, afterTruncated: false)
        let image = try render(excerpt, traits: dark)
        let cgImage = try XCTUnwrap(UIImage(data: image.png)?.cgImage)
        let pixels = try rgba(cgImage)
        XCTAssertEqual(pixels.pixel(0, 0), [0, 0, 0, 255])
        XCTAssertEqual(pixels.pixel(cgImage.width - 1, cgImage.height - 1), [0, 0, 0, 255])
        XCTAssertTrue(pixels.hasLightInk)
    }

    func testRenderedImageContainsOnlyTheVisibleExcerpt() throws {
        let hidden = "HIDDENSENTINEL HIDDENSENTINEL "
        let before = hidden + String(repeating: "visible ", count: 6)
        let width: CGFloat = 180
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: "", availableWidth: width)
        let image = try render(excerpt, traits: light, width: width)
        XCTAssertFalse(image.visibleText.contains("HIDDEN"))
        XCTAssertEqual(image.visibleText, excerpt.visibleText)
        // The canvas is bounded by the row, never by the full host context.
        XCTAssertLessThanOrEqual(image.pointSize.width, width + 2 * KeyboardPreviewImageRenderer.padding + 1)
        let full = KeyboardTextPreviewLayout.width(of: before)
        XCTAssertLessThan(image.pointSize.width, full)
        // Rendering the frozen excerpt again yields the identical picture.
        XCTAssertEqual(try render(excerpt, traits: light, width: width).png, image.png)
    }

    func testDescendersAndCombiningMarksAreNotClippedByPadding() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "gjpq\u{0303}\u{0323}", after: "", beforeTruncated: false, afterTruncated: false)
        let image = try render(excerpt, traits: light)
        let cgImage = try XCTUnwrap(UIImage(data: image.png)?.cgImage)
        let pixels = try rgba(cgImage)
        let edge = Int(KeyboardPreviewImageRenderer.padding * 3) - 3
        for x in 0..<cgImage.width {
            for y in Array(0..<edge) + Array((cgImage.height - edge)..<cgImage.height) {
                XCTAssertEqual(pixels.pixel(x, y), [255, 255, 255, 255], "Padding stays clear at (\(x), \(y))")
                if pixels.pixel(x, y) != [255, 255, 255, 255] { return }
            }
        }
    }

    func testColorEmojiKeepItsColors() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "🍎", after: "", beforeTruncated: false, afterTruncated: false)
        let image = try render(excerpt, traits: light)
        let pixels = try rgba(try XCTUnwrap(UIImage(data: image.png)?.cgImage))
        XCTAssertTrue(pixels.hasSaturatedColor, "Emoji are not flattened to the text color")
    }

    func testRenderUsesThePreviewFontRuns() throws {
        var requested: [String] = []
        let excerpt = KeyboardPreviewExcerpt(before: "ab", after: "c", beforeTruncated: false, afterTruncated: false)
        _ = KeyboardPreviewImageRenderer.render(excerpt, availableWidth: 200, visibleHeight: 42,
            foreground: .black, background: .white, font: { requested.append($0); return .systemFont(ofSize: 18) })
        XCTAssertEqual(requested, ["a", "b", "c"], "Each displayed character uses its own preview font")
    }

    // MARK: Empty and bounded

    func testEmptyWhitespaceAndInvisibleExcerptsAreNotRendered() {
        for (before, after) in [("", ""), ("   ", "\t"), ("\u{200B}", "\u{2060}"), ("…", "")] {
            let excerpt = KeyboardPreviewExcerpt(before: before, after: after, beforeTruncated: before == "…", afterTruncated: false)
            let result = KeyboardPreviewImageRenderer.render(excerpt, availableWidth: 200, visibleHeight: 42,
                                                             foreground: .black, background: .white)
            XCTAssertEqual(result.failureValue, .empty, "\(before.debugDescription) \(after.debugDescription)")
            let export = KeyboardPreviewImageExport.prepare(excerpt: excerpt, availableWidth: 200, visibleHeight: 42,
                foreground: .black, background: .white, hasFullAccess: true)
            XCTAssertEqual(export.phase, .empty)
            XCTAssertNil(export.image)
            XCTAssertFalse(export.canCopy, "Copy Image is disabled with nothing to copy")
        }
    }

    func testOversizedCanvasFailsInsteadOfDroppingText() {
        let long = String(repeating: "W", count: 400)
        let excerpt = KeyboardPreviewExcerpt(before: long, after: "", beforeTruncated: false, afterTruncated: false)
        let result = KeyboardPreviewImageRenderer.render(excerpt, availableWidth: 100_000, visibleHeight: 42,
                                                         foreground: .black, background: .white)
        XCTAssertEqual(result.failureValue, .tooLarge)
        let export = KeyboardPreviewImageExport.prepare(excerpt: excerpt, availableWidth: 100_000, visibleHeight: 42,
            foreground: .black, background: .white, hasFullAccess: true)
        XCTAssertEqual(export.phase, .renderFailed)
        XCTAssertFalse(export.canCopy)
    }

    // MARK: Clipboard

    func testWithoutFullAccessNothingIsWrittenAndTheRestrictionIsReported() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "Hi", after: "", beforeTruncated: false, afterTruncated: false)
        let export = KeyboardPreviewImageExport.prepare(excerpt: excerpt, availableWidth: 200, visibleHeight: 42,
            foreground: .black, background: .white, hasFullAccess: false)
        XCTAssertEqual(export.phase, .fullAccessRequired)
        XCTAssertNotNil(export.image, "The picture still previews; only copying is unavailable")
        XCTAssertFalse(export.canCopy)
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.string = "existing"
        let count = pasteboard.changeCount
        XCTAssertEqual(KeyboardPreviewClipboard.write(try XCTUnwrap(export.image), to: pasteboard, hasFullAccess: false), .fullAccessRequired)
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string, "existing", "Existing clipboard is untouched")
    }

    func testCopyPlacesThePNGOnThePasteboard() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "Copy", after: "", beforeTruncated: false, afterTruncated: false)
        let export = KeyboardPreviewImageExport.prepare(excerpt: excerpt, availableWidth: 200, visibleHeight: 42,
            foreground: .black, background: .white, hasFullAccess: true)
        XCTAssertEqual(export.phase, .ready)
        XCTAssertTrue(export.canCopy)
        let image = try XCTUnwrap(export.image)
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        XCTAssertEqual(KeyboardPreviewClipboard.write(image, to: pasteboard, hasFullAccess: true), .copied)
        XCTAssertEqual(pasteboard.data(forPasteboardType: UTType.png.identifier), image.png)
        XCTAssertTrue(pasteboard.hasImages)
    }

    // MARK: Colors

    private let sample = KeyboardPreviewExcerpt(before: "HELLO ✦ ", after: "Hi there", beforeTruncated: false, afterTruncated: false)

    func testEachPresetHasExactGlyphAndPaddingPixels() throws {
        let expected: [(KeyboardImageColorPreset, text: [UInt8], padding: [UInt8])] = [
            (.blackOnWhite, [0, 0, 0, 255], [255, 255, 255, 255]),
            (.blackOnClear, [0, 0, 0, 255], [0, 0, 0, 0]),
            (.whiteOnBlack, [255, 255, 255, 255], [0, 0, 0, 255]),
            (.whiteOnClear, [255, 255, 255, 255], [0, 0, 0, 0]),
        ]
        XCTAssertEqual(expected.map(\.0) + [.custom], KeyboardImageColorPreset.allCases)
        for (preset, text, padding) in expected {
            let colors = try XCTUnwrap(preset.fixedColors)
            let image = try render(sample, colors: colors)
            let cgImage = try decode(image)
            let opaqueInfos: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
            XCTAssertEqual(opaqueInfos.contains(cgImage.alphaInfo), !colors.isTransparent,
                           "\(preset): only transparent presets carry alpha")
            XCTAssertEqual(image.scale, 3)
            let pixels = try rgba(cgImage)
            XCTAssertTrue(pixels.contains(text), "\(preset): fully covered glyph pixels are exactly the text color")
            assertPadding(pixels, equals: padding, "\(preset)")
        }
    }

    func testCustomColorsAndSizeMatchThePresets() throws {
        let red = KeyboardImageRGB(0xFF3B30), blue = KeyboardImageRGB(0x007AFF)
        let opaque = try render(sample, colors: KeyboardImageColors(text: red, background: .color(blue)))
        let opaquePixels = try rgba(try decode(opaque))
        XCTAssertTrue(opaquePixels.contains([0xFF, 0x3B, 0x30, 255]))
        assertPadding(opaquePixels, equals: [0x00, 0x7A, 0xFF, 255], "red on blue")
        let clear = try render(sample, colors: KeyboardImageColors(text: red, background: .transparent))
        let clearPixels = try rgba(try decode(clear))
        XCTAssertTrue(clearPixels.contains([0xFF, 0x3B, 0x30, 255]))
        assertPadding(clearPixels, equals: [0, 0, 0, 0], "red on transparent")
        // Colors never change the excerpt, padding or scale.
        let reference = try render(sample, colors: KeyboardImageColorChoice.default.colors)
        for image in [opaque, clear] {
            XCTAssertEqual(image.pixelWidth, reference.pixelWidth)
            XCTAssertEqual(image.pixelHeight, reference.pixelHeight)
            XCTAssertEqual(image.visibleText, reference.visibleText)
        }
    }

    func testTransparentEdgesCarryPureTextColorWithoutFringe() throws {
        let red = KeyboardImageRGB(0xFF3B30)
        for text in [KeyboardImageRGB.black, .white, red] {
            let image = try render(sample, colors: KeyboardImageColors(text: text, background: .transparent))
            let pixels = try rgba(try decode(image))
            var edges = 0
            for index in 0..<(pixels.width * pixels.height) {
                let pixel = pixels.pixel(index % pixels.width, index / pixels.width)
                let alpha = Int(pixel[3])
                guard alpha > 0 else {
                    XCTAssertEqual(pixel, [0, 0, 0, 0], "Clear pixels are fully clear"); continue
                }
                guard alpha < 255 else { continue }
                edges += 1
                // Premultiplied, a pure text-colored edge is text × alpha.
                for (channel, value) in [text.red, text.green, text.blue].enumerated() {
                    let expected = Double(value) * Double(alpha) / 255
                    if abs(Double(pixel[channel]) - expected) > 2 {
                        XCTFail("\(text.hexString): fringe at \(index % pixels.width),\(index / pixels.width): \(pixel)")
                        return
                    }
                }
            }
            XCTAssertGreaterThan(edges, 20, "Antialiased edges keep partial alpha")
        }
    }

    func testLightAndDarkKeyboardsProduceIdenticalBytes() throws {
        var choices = KeyboardImageColorPreset.allCases.map { KeyboardImageColorChoice(preset: $0) }
        choices.append(KeyboardImageColorChoice(preset: .custom, customText: KeyboardImageRGB(0xAF52DE), customBackground: .transparent))
        for choice in choices {
            var lightExport: KeyboardPreviewImageExport?
            var darkExport: KeyboardPreviewImageExport?
            light.performAsCurrent {
                lightExport = KeyboardPreviewImageExport.prepare(excerpt: sample, availableWidth: 300, visibleHeight: 42,
                    colors: choice.colors, hasFullAccess: true)
            }
            dark.performAsCurrent {
                darkExport = KeyboardPreviewImageExport.prepare(excerpt: sample, availableWidth: 300, visibleHeight: 42,
                    colors: choice.colors, hasFullAccess: true)
            }
            let lightPNG = try XCTUnwrap(lightExport?.image?.png), darkPNG = try XCTUnwrap(darkExport?.image?.png)
            XCTAssertEqual(lightPNG, darkPNG, "\(choice.preset)")
        }
    }

    func testColorEmojiAreUnchangedInEveryPreset() throws {
        let excerpt = KeyboardPreviewExcerpt(before: "A🍎", after: "💙", beforeTruncated: false, afterTruncated: false)
        let clear = try rgba(try decode(try render(excerpt, colors: KeyboardImageColors(text: .white, background: .transparent))))
        // Fully opaque, saturated emoji pixels: never blended with any background.
        let samples = (0..<(clear.width * clear.height)).compactMap { index -> (Int, Int, [UInt8])? in
            let (x, y) = (index % clear.width, index / clear.width), pixel = clear.pixel(x, y)
            guard pixel[3] == 255, Int(pixel.prefix(3).max()!) - Int(pixel.prefix(3).min()!) > 80 else { return nil }
            return (x, y, pixel)
        }
        XCTAssertGreaterThan(samples.count, 50)
        var colorsToTry = KeyboardImageColorPreset.allCases.compactMap(\.fixedColors)
        colorsToTry.append(KeyboardImageColors(text: KeyboardImageRGB(0x34C759), background: .color(KeyboardImageRGB(0xFF9500))))
        for colors in colorsToTry {
            let image = try render(excerpt, colors: colors)
            XCTAssertTrue(image.containsColorGlyphs)
            let pixels = try rgba(try decode(image))
            XCTAssertEqual(pixels.width, clear.width)
            for (x, y, expected) in samples where zip(pixels.pixel(x, y), expected).contains(where: { abs(Int($0) - Int($1)) > 2 }) {
                XCTFail("\(colors.spokenName): emoji pixel \(x),\(y) \(pixels.pixel(x, y)) != \(expected)")
                break
            }
        }
        XCTAssertFalse(try render(sample, colors: KeyboardImageColorChoice.default.colors).containsColorGlyphs)
    }

    func testPersistenceStoresOnlyThePresetAndTwoColors() throws {
        let suite = "KeyboardImageColorStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(KeyboardImageColorStore.load(from: defaults), .default)
        XCTAssertEqual(KeyboardImageColorStore.load(from: defaults).preset, .blackOnWhite, "Black on White by default")

        let choice = KeyboardImageColorChoice(preset: .custom, customText: KeyboardImageRGB(0xFF3B30), customBackground: .transparent)
        KeyboardImageColorStore.save(choice, to: defaults)
        XCTAssertEqual(KeyboardImageColorStore.load(from: defaults), choice)
        let stored = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        XCTAssertEqual(Set(stored.keys), Set(KeyboardImageColorStore.keys))
        XCTAssertEqual(stored[KeyboardImageColorStore.presetKey] as? String, "custom")
        XCTAssertEqual(stored[KeyboardImageColorStore.customTextKey] as? String, "#FF3B30")
        XCTAssertEqual(stored[KeyboardImageColorStore.customBackgroundKey] as? String, "transparent")

        // A preset keeps the custom colors for later.
        var preset = choice
        preset.preset = .whiteOnClear
        KeyboardImageColorStore.save(preset, to: defaults)
        XCTAssertEqual(KeyboardImageColorStore.load(from: defaults), preset)
        XCTAssertEqual(KeyboardImageColorStore.load(from: defaults).colors, KeyboardImageColors(text: .white, background: .transparent))

        // Unknown values fall back without failing.
        defaults.set("rainbow", forKey: KeyboardImageColorStore.presetKey)
        defaults.set("red", forKey: KeyboardImageColorStore.customTextKey)
        defaults.set("#12345", forKey: KeyboardImageColorStore.customBackgroundKey)
        XCTAssertEqual(KeyboardImageColorStore.load(from: defaults), .default)
    }

    func testReadabilityGuardAndCheckerboardTones() throws {
        for preset in KeyboardImageColorPreset.allCases {
            XCTAssertEqual(KeyboardImageColorChoice(preset: preset).colors.readability, .readable, "\(preset)")
        }
        let gray = KeyboardImageRGB(0x8E8E93), orange = KeyboardImageRGB(0xFF9500)
        XCTAssertEqual(KeyboardImageRGB.contrastRatio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(KeyboardImageColors(text: gray, background: .color(gray)).readability, .sameColor)
        XCTAssertEqual(KeyboardImageColors(text: orange, background: .color(.white)).readability, .lowContrast)
        XCTAssertEqual(KeyboardImageColors(text: gray, background: .color(.white)).readability, .readable, "3.26:1 passes")
        XCTAssertEqual(KeyboardImageColors(text: .white, background: .color(.white)).readability, .sameColor)
        XCTAssertEqual(KeyboardImageColors(text: orange, background: .transparent).readability, .readable, "No check for transparent")

        let same = KeyboardPreviewImageExport.prepare(excerpt: sample, availableWidth: 300, visibleHeight: 42,
            colors: KeyboardImageColors(text: gray, background: .color(gray)), hasFullAccess: true)
        XCTAssertNotNil(same.image)
        XCTAssertFalse(same.canCopy, "Same text and background disables Copy Image")
        XCTAssertEqual(KeyboardImageColorCopy.readabilityNote(same.readability), "Choose different text and background colors.")
        let low = KeyboardPreviewImageExport.prepare(excerpt: sample, availableWidth: 300, visibleHeight: 42,
            colors: KeyboardImageColors(text: orange, background: .color(.white)), hasFullAccess: true)
        XCTAssertTrue(low.canCopy, "Low contrast only cautions")
        XCTAssertEqual(KeyboardImageColorCopy.readabilityNote(low.readability), "This text may be hard to read.")

        let light = (KeyboardImageRGB(0xFFFFFF), KeyboardImageRGB(0xE5E5EA))
        let dark = (KeyboardImageRGB(0x2C2C2E), KeyboardImageRGB(0x3A3A3C))
        XCTAssertTrue(KeyboardImageColors.checkerboardTones(forText: .black) == light)
        XCTAssertTrue(KeyboardImageColors.checkerboardTones(forText: KeyboardImageRGB(0xFF3B30)) == light)
        XCTAssertTrue(KeyboardImageColors.checkerboardTones(forText: .white) == dark)
    }

    func testRecoloringKeepsTheFrozenExcerptAndResetsSuccess() throws {
        var export = KeyboardPreviewImageExport.prepare(excerpt: sample, availableWidth: 300, visibleHeight: 42,
            colors: KeyboardImageColorChoice.default.colors, hasFullAccess: true)
        export.phase = .copied
        let clear = try XCTUnwrap(export.recolored(KeyboardImageColors(text: .white, background: .transparent), hasFullAccess: true))
        XCTAssertEqual(clear.id, export.id)
        XCTAssertEqual(clear.excerpt, sample)
        XCTAssertEqual(clear.phase, .ready, "The copied picture no longer matches the thumbnail")
        XCTAssertNotEqual(clear.image?.png, export.image?.png)
        export.phase = .copying
        XCTAssertNil(export.recolored(KeyboardImageColors(text: .white, background: .transparent), hasFullAccess: true),
                     "Colors cannot change while copying")
        let restricted = try XCTUnwrap(clear.recolored(KeyboardImageColorChoice.default.colors, hasFullAccess: false))
        XCTAssertEqual(restricted.phase, .fullAccessRequired)
        XCTAssertNotNil(restricted.image, "Colors still preview without Full Access")
    }

    func testExplanationAndAccessibilityDescribeTheColorsButNotHiddenText() throws {
        let before = "HIDDENSENTINEL " + String(repeating: "visible ", count: 8)
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: before, after: "", availableWidth: 180)
        for colors in KeyboardImageColorPreset.allCases.compactMap(\.fixedColors) {
            let image = try render(excerpt, colors: colors, width: 180)
            XCTAssertFalse(image.visibleText.contains("SENTINEL"))
            XCTAssertFalse(image.accessibilityValue.contains("SENTINEL"))
            XCTAssertTrue(image.accessibilityValue.hasPrefix(excerpt.visibleText))
            XCTAssertLessThanOrEqual(image.pointSize.width, 180 + 2 * KeyboardPreviewImageRenderer.padding + 1)
        }
        let clear = try render(sample, colors: KeyboardImageColors(text: .white, background: .transparent))
        XCTAssertEqual(clear.accessibilityValue, "HELLO ✦ Hi there, White on Transparent")
        XCTAssertEqual(KeyboardImageColors(text: KeyboardImageRGB(0xFF3B30), background: .color(KeyboardImageRGB(0x007AFF))).spokenName,
                       "Red on Blue")
        XCTAssertEqual(KeyboardImageColorCopy.caption(KeyboardImageColorChoice(preset: .whiteOnClear)), "Colors · White on Transparent")
        XCTAssertEqual(KeyboardImageColorCopy.explanationSuffix(colors: clear.colors, containsColorGlyphs: false),
                       " Transparent areas show the background where you paste. The checkerboard isn’t copied.")
        XCTAssertEqual(KeyboardImageColorCopy.explanationSuffix(colors: KeyboardImageColorChoice.default.colors, containsColorGlyphs: true),
                       " Emoji keep their original colors.")
        XCTAssertEqual(KeyboardImageColorCopy.explanationSuffix(colors: KeyboardImageColorChoice.default.colors, containsColorGlyphs: false), "")
    }

    // MARK: Helpers

    private func render(_ excerpt: KeyboardPreviewExcerpt, colors: KeyboardImageColors, width: CGFloat = 300) throws -> KeyboardPreviewImage {
        switch KeyboardPreviewImageRenderer.render(excerpt, availableWidth: width, visibleHeight: 42, colors: colors) {
        case .success(let image): return image
        case .failure(let failure): throw failure
        }
    }

    private func decode(_ image: KeyboardPreviewImage) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Every pixel of the outer padding band (less a little ink slack) is `expected`.
    private func assertPadding(_ pixels: Pixels, equals expected: [UInt8], _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let band = Int(KeyboardPreviewImageRenderer.padding * 3) - 3
        XCTAssertEqual(pixels.pixel(0, 0), expected, message, file: file, line: line)
        XCTAssertEqual(pixels.pixel(pixels.width - 1, pixels.height - 1), expected, message, file: file, line: line)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where x < band || y < band || x >= pixels.width - band || y >= pixels.height - band {
                if pixels.pixel(x, y) != expected {
                    XCTFail("\(message): padding \(x),\(y) is \(pixels.pixel(x, y))", file: file, line: line)
                    return
                }
            }
        }
    }

    /// The original measurement: one attributed string and line per candidate.
    private func legacyWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let result = NSMutableAttributedString()
        for character in text {
            result.append(NSAttributedString(string: String(character),
                attributes: [.font: KeyboardTextPreviewLayout.font(for: String(character))]))
        }
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(result), nil, nil, nil))
    }

    private func render(_ excerpt: KeyboardPreviewExcerpt, traits: UITraitCollection, width: CGFloat = 300) throws -> KeyboardPreviewImage {
        let result = KeyboardPreviewImageRenderer.render(excerpt, availableWidth: width, visibleHeight: 42,
            foreground: UIColor.label.resolvedColor(with: traits), background: UIColor.systemBackground.resolvedColor(with: traits))
        switch result {
        case .success(let image): return image
        case .failure(let failure): throw failure
        }
    }

    private struct Pixels {
        let width: Int, height: Int, bytes: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { let i = (y * width + x) * 4; return Array(bytes[i..<i + 4]) }
        func contains(_ rgba: [UInt8]) -> Bool { stride(from: 0, to: bytes.count, by: 4).contains { Array(bytes[$0..<$0 + 4]) == rgba } }
        private var all: [[UInt8]] { stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0..<$0 + 4]) } }
        var hasDarkInk: Bool { all.contains { Int($0[0]) + Int($0[1]) + Int($0[2]) < 200 } }
        var hasLightInk: Bool { all.contains { Int($0[0]) + Int($0[1]) + Int($0[2]) > 600 } }
        var hasSaturatedColor: Bool { all.contains { ($0.prefix(3).max()! - $0.prefix(3).min()!) > 80 } }
    }

    private func rgba(_ image: CGImage) throws -> Pixels {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Pixels(width: image.width, height: image.height, bytes: bytes)
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let failure) = self { return failure }; return nil }
}
#endif
