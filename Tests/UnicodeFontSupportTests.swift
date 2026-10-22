#if canImport(UIKit)
import XCTest
import UIKit
import CoreText
@testable import Uniboard

@MainActor
final class UnicodeFontSupportTests: XCTestCase {
    override func setUp() async throws { UnicodeFontSupport.clearCache() }
    override func tearDown() async throws { UnicodeFontSupport.clearCache() }

    func testDefaultOffDoesNotLoadFontsAndDoesNotChangeSystemRendering() {
        for text in ["A", "Ω", "\u{0558}", "\u{10940}", "\u{0378}", "◌\u{05C8}"] {
            let font = UnicodeFontSupport.font(for: text, size: 32, enabled: false)
            XCTAssertEqual(font.fontDescriptor, UIFont.systemFont(ofSize: 32).fontDescriptor)
            XCTAssertNil(UnicodeFontSupport.sourceName(for: text, size: 32, enabled: false))
        }
        XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0)
    }

    func testPreviewBasicsDownloadOnDemandAndTheirLicensesShip() throws {
        XCTAssertEqual(UnicodeFontSupport.bundledAssets.count, 4)
        let basics = try XCTUnwrap(UnicodeFontPackCatalog.bundled.packs.first)
        XCTAssertEqual(basics.id, "preview-basics")
        XCTAssertEqual(basics.fonts.map(\.asset.filename), UnicodeFontSupport.bundledAssets.map(\.filename))
        XCTAssertNil(Bundle.main.url(forResource: "unifont-18.0.01.otf", withExtension: nil, subdirectory: "Fonts"),
                     "Preview fonts are not bundled")
        XCTAssertEqual(UnicodeFontSupport.assets.count, Set(UnicodeFontSupport.assets.map(\.filename)).count)
        XCTAssertEqual(UnicodeFontSupport.assets.last?.postScriptName, "UnifontUpper", "Unifont stays the last fallback")
        for asset in UnicodeFontSupport.bundledAssets {
            let licenseURL = try XCTUnwrap(UnicodeFontSupport.resourceURL(asset.licenseFilename))
            XCTAssertTrue(try String(contentsOf: licenseURL).contains("SIL OPEN FONT LICENSE"))
            // Only an installed download opens; check its identity when present.
            guard let url = UnicodeFontSupport.resourceURL(asset.filename) else { continue }
            let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
            let graphics = try XCTUnwrap(CGFont(provider))
            XCTAssertEqual(graphics.postScriptName as String?, asset.postScriptName)
            let font = CTFontCreateWithGraphicsFont(graphics, 32, nil, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, asset.postScriptName)
            XCTAssertFalse(asset.ranges.isEmpty)
            XCTAssertTrue(asset.ranges.allSatisfy { $0.count == 2 && $0[0] <= $0[1] })
        }
        XCTAssertTrue(UnicodeFontSupport.licenseText.contains("Unifont"))
        XCTAssertTrue(UnicodeFontSupport.licenseText.contains("Noto"))
    }

    func testActualMissingGlyphGainsAnOutlineWithoutGlobalFontRegistration() throws {
        // Armenian Unicode18 is absent on the oldest supported iOS QA runtime.
        let text = "\u{0558}"
        let system = UIFont.systemFont(ofSize: 32)
        let missingBefore = UnicodeFontSupport.missingCodePoints(in: text, font: system)
        guard !missingBefore.isEmpty else { throw XCTSkip("This iOS runtime already renders the fixture; coverage probe records it separately.") }
        guard UnicodeFontSupport.resourceURL("unifont-18.0.01.otf") != nil else { throw XCTSkip("Preview basics are downloaded on demand") }
        let fallback = UnicodeFontSupport.font(for: text, size: 32, enabled: true)
        XCTAssertNotNil(UnicodeFontSupport.sourceName(for: text, size: 32, enabled: true))
        XCTAssertNotEqual(fallback.fontName, system.fontName)
        XCTAssertTrue(UnicodeFontSupport.missingCodePoints(in: text, font: fallback).isEmpty)
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let font = fallback as CTFont
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        let glyph = try XCTUnwrap(glyphs.first)
        XCTAssertNotEqual(glyph, 0)
        XCTAssertFalse(try XCTUnwrap(CTFontCreatePathForGlyph(font, glyph, nil)).isEmpty)
        // Merely opening a CGFont must not change the system fallback cascade.
        XCTAssertEqual(UnicodeFontSupport.missingCodePoints(in: text, font: system), missingBefore)
        let disabled = UnicodeFontSupport.font(for: text, size: 32, enabled: false)
        XCTAssertEqual(disabled.fontDescriptor, system.fontDescriptor)
        UnicodeFontSupport.clearCache()
        XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0)
    }

    func testSupportedTextEmojiAndReservedSlotsStayOnSystemFonts() {
        // Text iOS draws completely, text presentation, sequences no fallback
        // draws as one glyph, and unassigned slots never switch fonts.
        for text in ["A", "Ω", "🚀", "🙂‍↔️", "☃️", "🇯🇵", "\u{1FAEB}\u{200D}\u{1F680}",
                     "\u{1FAEB}\u{FE0E}", "\u{1FAEB}\u{1F3FB}", "\u{0378}"] {
            let font = UnicodeFontSupport.font(for: text, size: 32, enabled: true)
            XCTAssertEqual(font.fontDescriptor, UIFont.systemFont(ofSize: 32).fontDescriptor, text)
            XCTAssertNil(UnicodeFontSupport.sourceName(for: text, size: 32, enabled: true), text)
        }
    }

    func testEmojiTextAndGlyphCountsDetectSplitSequencesAtRuntime() {
        for text in ["🚀", "☃️", "🇯🇵", "👍🏽", "#️⃣", "🙂‍↔️"] {
            XCTAssertTrue(UnicodeFontSupport.isEmojiText(text), text)
            XCTAssertEqual(UnicodeFontSupport.visibleGlyphCount(in: text, font: .systemFont(ofSize: 32)), 1, text)
            XCTAssertFalse(UnicodeFontSupport.stockFontsMiss(text, emoji: true), text)
        }
        for text in ["A", "Ω", "☃", "\u{2603}\u{FE0E}", "1"] {
            XCTAssertFalse(UnicodeFontSupport.isEmojiText(text), text)
            XCTAssertFalse(UnicodeFontSupport.stockFontsMiss(text), text)
        }
        // Not a recommended sequence: iOS draws two rockets, so it must count as split.
        let split = "\u{1F680}\u{200D}\u{1F680}"
        XCTAssertEqual(UnicodeFontSupport.visibleGlyphCount(in: split, font: .systemFont(ofSize: 32)), 2)
        XCTAssertTrue(UnicodeFontSupport.stockFontsMiss(split, emoji: true))
        XCTAssertTrue(UnicodeFontSupport.stockFontsMiss("\u{0378}"))
        // A Unicode 18 letter that a bundled fallback draws still counts:
        // other apps showing it will not have that font.
        let armenian = "\u{0558}"
        XCTAssertNotEqual(UnicodeFontSupport.font(for: armenian, size: 32, enabled: true).fontName,
                          UIFont.systemFont(ofSize: 32).fontName)
        XCTAssertTrue(UnicodeFontSupport.stockFontsMiss(armenian))
        UnicodeFontSupport.clearCache()
    }

    func testFontPreferencesDefaultOffAndPersistInTheAppOwnedSharedSnapshot() {
        let suite = "Uniboard.Fonts.Test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var sharedBytes = Data()
        let settings = UnicodeEditionSettings(containerURL: { URL(fileURLWithPath: "/font-preference-fixture") },
            readPrefix: { _, _ in sharedBytes }, writeAtomically: { data, _ in sharedBytes = data })
        let app = CatalogPreferences(editionSettings: settings)
        XCTAssertFalse(app.useUnicodeFonts)
        app.selectUnicodeFonts(true)
        XCTAssertTrue(CatalogPreferences(editionSettings: settings).useUnicodeFonts)
        XCTAssertTrue(settings.loadSnapshot().useUnicodeFonts)
        XCTAssertFalse(defaults.bool(forKey: "keyboardUnicodeFonts"))
        app.reset()
        XCTAssertFalse(CatalogPreferences(editionSettings: settings).useUnicodeFonts)
    }

    func testInvalidAndExtremePointSizesHaveFiniteBoundedFallbacks() {
        for input: CGFloat in [.nan, .infinity, -.infinity, -100, 0, .leastNonzeroMagnitude, .greatestFiniteMagnitude] {
            let size = UnicodeFontSupport.normalizedPointSize(input)
            XCTAssertTrue(size.isFinite)
            XCTAssertTrue((1...512).contains(size))
            for enabled in [false, true] {
                let font = UnicodeFontSupport.font(for: "A", size: input, enabled: enabled)
                XCTAssertEqual(font.pointSize, size)
                XCTAssertNil(UnicodeFontSupport.sourceName(for: "A", size: input, enabled: enabled))
            }
        }
        XCTAssertEqual(UnicodeFontSupport.normalizedPointSize(32), 32)
        XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0)
    }

    func testEmptyControlAndFormattingTextDoesNotLoadOptionalFonts() {
        for text in ["", "\u{0}", "\n\t", "\u{200B}", "\u{200D}", "\u{FE0E}", "\u{FE0F}", "\u{E0100}", "\u{034F}"] {
            XCTAssertTrue(UnicodeFontSupport.missingCodePoints(in: text, font: .systemFont(ofSize: 32)).isEmpty, text.debugDescription)
            XCTAssertNil(UnicodeFontSupport.sourceName(for: text, size: 32, enabled: true))
            XCTAssertEqual(UnicodeFontSupport.font(for: text, size: 32, enabled: true).fontDescriptor,
                           UIFont.systemFont(ofSize: 32).fontDescriptor)
        }
        XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0)
    }

    func testFontManifestRejectsInvalidAndUnsortedRanges() {
        func asset(_ ranges: [[UInt32]]) -> UnicodeFontSupport.Asset {
            .init(filename: "font.otf", displayName: "Fixture", postScriptName: "Fixture-Regular",
                  sha256: String(repeating: "a", count: 64), sourceURL: "https://example.com/font.otf",
                  licenseFilename: "OFL.txt", ranges: ranges)
        }
        let valid = asset([[0, 0xD7FF], [0xE000, 0x10FFFF]])
        XCTAssertTrue(valid.isValid)
        for point: UInt32 in [0, 0x41, 0xD7FF, 0xE000, 0x1F680, 0x10FFFF] { XCTAssertTrue(valid.contains(point)) }
        XCTAssertFalse(valid.contains(0xD800))
        XCTAssertFalse(valid.contains(0x110000))
        for ranges: [[UInt32]] in [[], [[]], [[1]], [[1, 2, 3]], [[2, 1]], [[0x110000, 0x110000]],
                                    [[0xD7FF, 0xE000]], [[4, 8], [1, 2]], [[1, 4], [4, 8]]] {
            XCTAssertFalse(asset(ranges).isValid, "\(ranges)")
        }
        XCTAssertTrue(UnicodeFontSupport.assets.allSatisfy(\.isValid))
    }

    func testFontResourcesCannotEscapeTheirBundledDirectory() {
        for filename in ["", ".", "..", "../Info.plist", "Fonts/font.otf", "\\font.otf", "/tmp/font.otf", "bad\0font.otf"] {
            XCTAssertNil(UnicodeFontSupport.resourceURL(filename))
        }
        let invalid = UnicodeFontSupport.Asset(filename: "../font.otf", displayName: "Fixture",
            postScriptName: "Fixture", sha256: String(repeating: "a", count: 64),
            sourceURL: "https://example.com/font.otf", licenseFilename: "OFL.txt", ranges: [[1, 2]])
        XCTAssertFalse(invalid.isValid)
    }

    func testInvalidAppPreferencesRecoverToSafeDefaults() {
        let suite = "Uniboard.Preferences.Test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown edition", forKey: "appUnicodeEdition")
        defaults.set(123, forKey: "appUnicodeSort")
        defaults.set("YES", forKey: "appUnicodeFonts")
        let preferences = CatalogPreferences(
            editionSettings: UnicodeEditionSettings(containerURL: { nil }))
        XCTAssertEqual(preferences.edition, .latest)
        XCTAssertFalse(preferences.useUnicodeFonts)
    }

    func testSharedEditionAndFontsPersistWhileLegacyKeyboardLocalOptionsAreIgnored() {
        let suite = "Uniboard.Preferences.Test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("draft", forKey: "keyboardUnicodeEdition")
        defaults.set("oldestFirst", forKey: "keyboardUnicodeSort")
        defaults.set(true, forKey: "keyboardUnicodeFonts")
        var sharedSelection: Data?
        let editionSettings = UnicodeEditionSettings(
            containerURL: { URL(fileURLWithPath: "/uniboard-preferences-fixture", isDirectory: true) },
            readPrefix: { _, _ in sharedSelection ?? Data() },
            writeAtomically: { bytes, _ in sharedSelection = bytes })
        let preferences = CatalogPreferences(editionSettings: editionSettings)
        preferences.selectEdition(.previous)
        preferences.selectUnicodeFonts(true)
        let restored = CatalogPreferences(editionSettings: editionSettings)
        XCTAssertEqual(restored.edition, .previous)
        XCTAssertEqual(editionSettings.load(), .previous)
        XCTAssertTrue(restored.useUnicodeFonts)
        XCTAssertTrue(editionSettings.loadSnapshot().useUnicodeFonts)
        restored.reset()
        XCTAssertEqual(CatalogPreferences(editionSettings: editionSettings).edition, .latest)
        XCTAssertEqual(defaults.string(forKey: "keyboardUnicodeEdition"), "draft")
        XCTAssertEqual(defaults.string(forKey: "keyboardUnicodeSort"), "oldestFirst")
        XCTAssertTrue(defaults.bool(forKey: "keyboardUnicodeFonts"))
    }
}
#endif
