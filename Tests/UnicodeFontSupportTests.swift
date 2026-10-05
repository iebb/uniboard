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

    func testEveryBundledFaceAndLicenseIsUsable() throws {
        XCTAssertEqual(UnicodeFontSupport.assets.count, 3)
        for asset in UnicodeFontSupport.assets {
            let url = try XCTUnwrap(UnicodeFontSupport.resourceURL(asset.filename))
            let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
            let graphics = try XCTUnwrap(CGFont(provider))
            XCTAssertEqual(graphics.postScriptName as String?, asset.postScriptName)
            let font = CTFontCreateWithGraphicsFont(graphics, 32, nil, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, asset.postScriptName)
            let licenseURL = try XCTUnwrap(UnicodeFontSupport.resourceURL(asset.licenseFilename))
            XCTAssertTrue(try String(contentsOf: licenseURL).contains("SIL OPEN FONT LICENSE"))
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
        let fallback = UnicodeFontSupport.font(for: text, size: 32, enabled: true)
        XCTAssertNotNil(UnicodeFontSupport.sourceName(for: text, size: 32, enabled: true))
        XCTAssertTrue(fallback.fontName.lowercased().contains("unifont"))
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
        for text in ["A", "Ω", "🚀", "🙂‍↔️", "☃️", "🇯🇵", "\u{1FAEB}", "\u{0378}"] {
            let font = UnicodeFontSupport.font(for: text, size: 32, enabled: true)
            XCTAssertEqual(font.fontDescriptor, UIFont.systemFont(ofSize: 32).fontDescriptor, text)
            XCTAssertNil(UnicodeFontSupport.sourceName(for: text, size: 32, enabled: true), text)
        }
    }

    func testFontPreferencesAreLocalDefaultOffAndPersistIndependently() {
        let suite = "Uniboard.Fonts.Test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = CatalogPreferences(defaults: defaults)
        XCTAssertFalse(app.useUnicodeFonts)
        app.useUnicodeFonts = true
        XCTAssertTrue(CatalogPreferences(defaults: defaults).useUnicodeFonts)
        XCTAssertFalse(defaults.bool(forKey: "keyboardUnicodeFonts"))
        app.reset()
        XCTAssertFalse(CatalogPreferences(defaults: defaults).useUnicodeFonts)
    }
}
#endif
