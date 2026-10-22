#if canImport(UIKit)
import XCTest
import UIKit
@testable import Uniboard

/// Opt-in audit of every fully qualified emoji, including sequences, on the
/// iOS runtime under test. The scalar audit cannot see a ZWJ, modifier, flag or
/// keycap sequence that the stock font draws as separate pieces.
@MainActor
final class UnicodeEmojiSequenceAuditTests: XCTestCase {
    struct Entry: Codable {
        let codePoints: String
        let name: String
        let emojiVersion: String
        let stock: String
        let withFallback: String?
    }
    struct Report: Codable {
        let os: String
        let catalog: String
        let methodology: String
        let tested: Int
        let unsupported: [Entry]
    }

    func testEveryFullyQualifiedEmojiOnActualIOS() throws {
        guard ProcessInfo.processInfo.environment["UNIBOARD_EMOJI_AUDIT"] == "1" else {
            throw XCTSkip("Whole-catalog emoji audit is opt-in: UNIBOARD_EMOJI_AUDIT=1")
        }
        let catalog = EmojiCatalog.latest
        XCTAssertNil(catalog.resourceError)
        if ProcessInfo.processInfo.environment["UNIBOARD_EMOJI_AUDIT_INSTALL"] == "1" {
            // Pinned emoji pack files copied into Documents/FontAuditAssets.
            let input = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
                .appendingPathComponent("FontAuditAssets", isDirectory: true)
            let pack = try XCTUnwrap(UnicodeFontPackCatalog.bundled.packs.first { $0.id == "emoji" })
            for font in pack.fonts {
                try UnicodeFontDownloadStore.shared.install(input.appendingPathComponent(font.asset.filename), font: font)
                XCTAssertNotNil(UnicodeFontDownloadStore.shared.installedURL(for: font))
            }
        }
        UnicodeFontSupport.clearCache()
        UnicodeFontSupport.refreshDownloadedFonts(force: true)
        let system = UIFont.systemFont(ofSize: 32)
        func outcome(_ text: String, _ font: UIFont) -> String {
            if !UnicodeFontSupport.missingCodePoints(in: text, font: font).isEmpty { return "missing" }
            return UnicodeFontSupport.visibleGlyphCount(in: text, font: font) == 1 ? "ok" : "split"
        }
        var unsupported: [Entry] = []
        for entry in catalog.entries {
            let text = entry.text
            let stock = autoreleasepool { outcome(text, system) }
            guard stock != "ok" else { continue }
            let fallback = autoreleasepool { () -> String? in
                let preview = UnicodeFontSupport.font(for: text, size: 32, enabled: true)
                return preview.fontName == system.fontName ? nil : outcome(text, preview)
            }
            unsupported.append(Entry(codePoints: entry.codePointLabel, name: entry.name, emojiVersion: entry.emojiVersion,
                                     stock: stock, withFallback: fallback))
            print("EMOJI_AUDIT \(stock) fallback=\(fallback ?? "none") E\(entry.emojiVersion) \(entry.codePointLabel) \(entry.name)")
        }
        print("EMOJI_AUDIT_SUMMARY tested=\(catalog.entries.count) unsupported=\(unsupported.count) "
              + "recovered=\(unsupported.filter { $0.withFallback == "ok" }.count)")
        let report = Report(os: ProcessInfo.processInfo.operatingSystemVersionString, catalog: catalog.version,
            methodology: "Every fully qualified emoji in the bundled release, shaped as exact text with the 32-point system font. Missing means glyph zero or LastResort; split means more than one visible glyph, i.e. iOS draws the components separately. withFallback is the Extra Unicode fonts result when emoji packs are installed, or null when no fallback applies.",
            tested: catalog.entries.count, unsupported: unsupported)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "Fully qualified emoji iOS stock support"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(catalog.entries.count, 3_900)
        UnicodeFontSupport.clearCache()
    }
}
#endif
