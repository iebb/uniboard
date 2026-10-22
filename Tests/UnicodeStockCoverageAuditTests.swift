#if canImport(UIKit)
import XCTest
import UIKit
import CoreText
@testable import Uniboard

/// Opt-in whole-catalog audit on an actual iOS runtime. A cmap union on macOS
/// cannot establish which fallback fonts UIKit will use on iOS.
@MainActor
final class UnicodeStockCoverageAuditTests: XCTestCase {
    struct BlockResult: Codable {
        let name: String
        let start: UInt32
        let end: UInt32
        var tested: Int = 0
        var stockMissing: [UInt32] = []
        var emojiMissing: [UInt32] = []
        var optionalMissing: [UInt32] = []
        var recovered: [UInt32] = []
    }
    struct Report: Codable {
        let os: String
        let model: String
        let catalog: String
        let mode: String
        let methodology: String
        let elapsedSeconds: Double
        let blocks: [BlockResult]
    }

    func testAssignedGraphicCoverageByBlockOnActualIOS() throws {
        let mode = ProcessInfo.processInfo.environment["UNIBOARD_FONT_AUDIT"] ?? ""
        guard mode == "stock" || mode == "complete" else {
            throw XCTSkip("Whole-catalog native audit is opt-in: UNIBOARD_FONT_AUDIT=stock or complete")
        }
        let catalog = UnicodeCatalog.latest
        XCTAssertNil(catalog.resourceError)
        XCTAssertTrue(catalog.version.hasPrefix("18."))
        if ProcessInfo.processInfo.environment["UNIBOARD_FONT_AUDIT_INSTALL"] == "1" {
            let input = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
                .appendingPathComponent("FontAuditAssets", isDirectory: true)
            for font in UnicodeFontPackCatalog.bundled.packs.flatMap(\.fonts) {
                try UnicodeFontDownloadStore.shared.install(input.appendingPathComponent(font.asset.filename), font: font)
                let installed = try XCTUnwrap(UnicodeFontDownloadStore.shared.installedURL(for: font))
                let provider = try XCTUnwrap(CGDataProvider(url: installed as CFURL))
                let graphics = try XCTUnwrap(CGFont(provider))
                XCTAssertEqual(graphics.postScriptName as String?, font.asset.postScriptName)
            }
        }
        UnicodeFontSupport.clearCache()
        let system = UIFont.systemFont(ofSize: 32)
        let emojiPoints = Set(EmojiCatalog.latest.entries.flatMap { $0.text.unicodeScalars.map(\.value) })
        let start = Date()
        var blocks: [BlockResult] = []
        for block in catalog.blocks {
            var result = BlockResult(name: block.name, start: block.start, end: block.end)
            var offset = 0
            while true {
                let page = catalog.characters(in: block, offset: offset, limit: 512)
                if page.isEmpty { break }
                offset += page.count
                for character in page {
                    guard let scalar = Unicode.Scalar(character.codePoint),
                          ["L", "M", "N", "P", "S"].contains(String(character.category.prefix(1))),
                          !character.isInvisible, !scalar.properties.isDefaultIgnorableCodePoint,
                          character.codePoint != 0x2800 else { continue }
                    result.tested += 1
                    let preview = character.displayText
                    let missing = autoreleasepool {
                        UnicodeFontSupport.missingCodePoints(in: preview, font: system)
                    }
                    guard missing.contains(character.codePoint) else { continue }
                    result.stockMissing.append(character.codePoint)
                    if emojiPoints.contains(character.codePoint) {
                        result.emojiMissing.append(character.codePoint)
                    }
                    if mode == "complete" {
                        let recovered = autoreleasepool {
                            let candidate = UnicodeFontSupport.font(for: preview, size: 32, enabled: true)
                            return !UnicodeFontSupport.missingCodePoints(in: preview, font: candidate).contains(character.codePoint)
                        }
                        if recovered { result.recovered.append(character.codePoint) }
                        else { result.optionalMissing.append(character.codePoint) }
                        XCTAssertLessThanOrEqual(UnicodeFontSupport.loadedFontCount, UnicodeFontSupport.maximumLoadedFonts)
                    }
                }
            }
            blocks.append(result)
            print("FONT_AUDIT \(block.name): \(result.tested) tested, \(result.stockMissing.count) stock missing")
        }
        if mode == "stock" { XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0) }
        if mode == "complete", ProcessInfo.processInfo.environment["UNIBOARD_FONT_AUDIT_INSTALL"] == "1" {
            XCTAssertEqual(blocks.reduce(0) { $0 + $1.optionalMissing.count }, 0,
                "The complete pinned Unicode 18 preview set must close every measured stock gap")
            try verifyStandaloneColorEmojiPreviews()
        }
        let report = Report(os: ProcessInfo.processInfo.operatingSystemVersionString,
            model: UIDevice.current.model, catalog: catalog.version, mode: mode,
            methodology: "Assigned L/M/N/P/S scalars in the bundled release; excludes invisible/default-ignorable/Braille blank. Uses exact production displayText, including dotted-circle combining previews, and actual CoreText shaped runs. Missing means glyph zero or LastResort covering that scalar. The nine audited missing standalone emoji may use the optional Noto COLR subset; joined and already-supported emoji preserve native rendering. This checks scalar preview coverage, not complex-script spelling or arbitrary emoji sequences.",
            elapsedSeconds: Date().timeIntervalSince(start), blocks: blocks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "Unicode 18 whole-catalog iOS \(mode) glyph coverage by block"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(blocks.reduce(0) { $0 + $1.tested }, 150_000)
        UnicodeFontSupport.clearCache()
    }

    private func verifyStandaloneColorEmojiPreviews() throws {
        let pack = try XCTUnwrap(UnicodeFontPackCatalog.bundled.packs.first { $0.id == "emoji-latest" })
        let points = pack.fonts.flatMap { $0.asset.ranges.flatMap { Array($0[0]...$0[1]) } }
        XCTAssertEqual(points.count, 9)
        for point in points {
            for suffix in ["", "\u{FE0F}"] {
                let text = String(try XCTUnwrap(Unicode.Scalar(point))) + suffix
                let font = UnicodeFontSupport.font(for: text, size: 48, enabled: true)
                XCTAssertTrue(UnicodeFontSupport.missingCodePoints(in: text, font: font).isEmpty)
                if !UnicodeFontSupport.missingCodePoints(in: text, font: .systemFont(ofSize: 48)).isEmpty {
                    XCTAssertEqual(font.fontName, pack.fonts[0].asset.postScriptName)
                    XCTAssertTrue(CTFontGetSymbolicTraits(font as CTFont).contains(.traitColorGlyphs))
                }
                let off = UnicodeFontSupport.font(for: text, size: 48, enabled: false)
                XCTAssertEqual(off.fontDescriptor, UIFont.systemFont(ofSize: 48).fontDescriptor)
            }
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 200)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
            for (index, point) in points.enumerated() {
                let text = String(Unicode.Scalar(point)!)
                text.draw(at: CGPoint(x: 20 + index % 5 * 115, y: 10 + index / 5 * 95), withAttributes: [
                    .font: UnicodeFontSupport.font(for: text, size: 48, enabled: true), .foregroundColor: UIColor.black])
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Nine Unicode 18 emoji using the exact optional Noto color subset"
        attachment.lifetime = .keepAlways
        add(attachment)
        for text in ["🚀", "🙂‍↔️", "👍🏽", "🇯🇵", "☃️", "\u{1FAEB}\u{200D}\u{1F680}"] {
            let on = UnicodeFontSupport.font(for: text, size: 48, enabled: true)
            let off = UnicodeFontSupport.font(for: text, size: 48, enabled: false)
            XCTAssertEqual(on.fontDescriptor, off.fontDescriptor, text)
        }
    }
}
#endif
