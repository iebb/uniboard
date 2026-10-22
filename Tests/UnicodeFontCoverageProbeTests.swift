#if canImport(UIKit)
import XCTest
import Foundation
@testable import Uniboard
import UIKit
import CoreText

/// Native QA probe. Its JSON and actual UIKit bitmaps are retained as XCTest attachments.
/// This intentionally measures shaped CTRun glyphs, rather than treating each UTF-16
/// surrogate or emoji variation selector as an independent visible glyph.
private enum UnicodeFontCoverageProbe {
    struct Fixture: Codable {
        let id: String
        let text: String
        let purpose: String
    }

    struct GlyphRun: Codable, Equatable {
        let fontName: String
        let fontFamily: String
        let utf16RangeStart: Int
        let utf16RangeLength: Int
        let glyphIDs: [UInt16]
        let sourceUTF16Indices: [Int]
        let hasZeroGlyph: Bool
        let hasLastResortFont: Bool
    }

    struct Observation: Codable {
        let fixture: Fixture
        let enabled: Bool
        let requestedFontName: String
        let unicodeScalars: [String]
        let utf16Count: Int
        let runs: [GlyphRun]
        let advance: Double
        let bitmapName: String
    }

    struct Report: Codable {
        let operatingSystem: String
        let model: String
        let note: String
        let observations: [Observation]
    }

    static let fixtures: [Fixture] = [
        .init(id: "garay-mark-preview", text: "\u{25CC}\u{10D69}", purpose: "Supplementary mark and dotted-circle must stay in one preview face"),
        .init(id: "tulu-mark-preview", text: "\u{25CC}\u{113B8}", purpose: "Spacing mark specimen must not fall back as a mixed cluster"),
        .init(id: "native-latin", text: "A", purpose: "Existing native letter control"),
        .init(id: "native-omega", text: "Ω", purpose: "Existing native symbol control"),
        .init(id: "znamenny-1CF00-preview", text: "\u{25CC}\u{1CF00}", purpose: "Complete supplementary combining-mark preview must also retain the dotted circle"),
        .init(id: "sidetic-10940", text: "\u{10940}", purpose: "Unicode 17 Sidetic; supplementary candidate"),
        .init(id: "tolong-siki-11DB0", text: "\u{11DB0}", purpose: "Unicode 17 Tolong Siki; supplementary candidate"),
        .init(id: "garay-10D40", text: "\u{10D40}", purpose: "Unicode 16 Garay digit; supplementary candidate"),
        .init(id: "armenian-0558", text: "\u{0558}", purpose: "Unicode 18 Armenian modifier; BMP candidate"),
        .init(id: "hebrew-05C8-preview", text: "\u{25CC}\u{05C8}", purpose: "Unicode 18 combining mark with actual app dotted-circle preview"),
        .init(id: "combining-1AD3-preview", text: "\u{25CC}\u{1AD3}", purpose: "Unicode 17 combining mark with dotted-circle preview"),
        .init(id: "snowman-2603", text: "\u{2603}", purpose: "Existing system glyph control"),
        .init(id: "unassigned-0378", text: "\u{0378}", purpose: "Unassigned negative coverage control; not app placeholder"),
        .init(id: "emoji-rocket", text: "\u{1F680}", purpose: "System emoji must remain unchanged"),
        .init(id: "emoji-cracking-face", text: "\u{1FAEB}", purpose: "Unicode 18 emoji: use the audited optional Noto color subset only when native rendering is missing"),
        .init(id: "emoji-zwj-vs16", text: "\u{1F642}\u{200D}\u{2194}\u{FE0F}", purpose: "Complete emoji ZWJ and variation-selector control")
    ]

    /// Measure the production resolver in the actual iOS test-host process.
    /// Baseline is always production enabled=false, rather than a macOS font estimate.
    @MainActor
    static func write(to directory: URL,
                      font: (_ text: String, _ size: CGFloat, _ enabled: Bool) -> UIFont) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var observations: [Observation] = []
        for fixture in fixtures {
            for enabled in [false, true] {
                let previewFont = font(fixture.text, 56, enabled)
                let bitmapName = "\(fixture.id)-\(enabled ? "on" : "off").png"
                let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 132)).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 300, height: 132))
                    (fixture.text as NSString).draw(in: CGRect(x: 20, y: 28, width: 260, height: 92),
                        withAttributes: [.font: previewFont, .foregroundColor: UIColor.black])
                }
                guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: directory.appendingPathComponent(bitmapName))
                let shaped = shape(fixture.text, font: previewFont)
                observations.append(.init(fixture: fixture, enabled: enabled,
                    requestedFontName: previewFont.fontName,
                    unicodeScalars: fixture.text.unicodeScalars.map { String(format: "U+%04X", $0.value) },
                    utf16Count: fixture.text.utf16.count, runs: shaped.runs,
                    advance: shaped.advance, bitmapName: bitmapName))
            }
        }
        let report = Report(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            model: UIDevice.current.model,
            note: "Raw shaped runs and rendered bitmaps. Zero/LastResort glyphs indicate missing visible scalar candidates; zero-width ZWJ/VS controls must not be counted as independent visible failures. System-font coverage is measured on this actual iOS runtime.",
            observations: observations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("coverage.json"))
    }

    static func shape(_ text: String, font: UIFont) -> (runs: [GlyphRun], advance: Double) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = (CTLineGetGlyphRuns(line) as NSArray).map { value -> GlyphRun in
            let run = value as! CTRun
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            if count > 0 {
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let resolvedFont = attributes[kCTFontAttributeName] as! CTFont
            let name = CTFontCopyPostScriptName(resolvedFont) as String
            let family = CTFontCopyFamilyName(resolvedFont) as String
            let range = CTRunGetStringRange(run)
            return .init(fontName: name, fontFamily: family,
                utf16RangeStart: range.location, utf16RangeLength: range.length,
                glyphIDs: glyphs, sourceUTF16Indices: indices,
                hasZeroGlyph: glyphs.contains(0),
                hasLastResortFont: name.localizedCaseInsensitiveContains("LastResort")
                    || family.localizedCaseInsensitiveContains("LastResort"))
        }
        return (runs, CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}


@MainActor
final class UnicodeFontCoverageProbeTests: XCTestCase {
    override func setUp() async throws { UnicodeFontSupport.clearCache() }
    override func tearDown() async throws { UnicodeFontSupport.clearCache() }

    func testActualIOSCoverageAndNativeEmojiRendering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Uniboard-Font-Probe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try UnicodeFontCoverageProbe.write(to: directory) { text, size, enabled in
            UnicodeFontSupport.font(for: text, size: size, enabled: enabled)
        }
        let reportData = try Data(contentsOf: directory.appendingPathComponent("coverage.json"))
        let reportAttachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
        reportAttachment.name = "Actual iOS optional-font CoreText coverage and resolved glyph runs"
        reportAttachment.lifetime = .keepAlways
        add(reportAttachment)
        let report = try JSONDecoder().decode(UnicodeFontCoverageProbe.Report.self, from: reportData)
        for observation in report.observations {
            let bitmap = XCTAttachment(data: try Data(contentsOf: directory.appendingPathComponent(observation.bitmapName)),
                                       uniformTypeIdentifier: "public.png")
            bitmap.name = "Unicode preview \(observation.fixture.id) \(observation.enabled ? "ON" : "OFF")"
            bitmap.lifetime = .keepAlways
            add(bitmap)
            XCTAssertTrue(observation.advance.isFinite && observation.advance >= 0,
                          "Every shaped preview must have finite, nonnegative metrics")
        }
        let system = UIFont.systemFont(ofSize: 56)
        // Unifont downloads on demand with the preview basics.
        let basics = UnicodeFontSupport.resourceURL("unifont-18.0.01.otf") != nil
        for id in ["armenian-0558", "sidetic-10940"] {
            let before = try observation(id, enabled: false, in: report)
            let after = try observation(id, enabled: true, in: report)
            let missing = UnicodeFontSupport.missingCodePoints(in: before.fixture.text, font: system)
            if !missing.isEmpty && !basics { continue }
            if !missing.isEmpty {
                XCTAssertNotEqual(after.requestedFontName, before.requestedFontName)
                XCTAssertNotNil(UnicodeFontSupport.sourceName(for: after.fixture.text, size: 56, enabled: true))
                XCTAssertFalse(after.runs.isEmpty)
                XCTAssertTrue(after.runs.allSatisfy { !$0.hasZeroGlyph && !$0.hasLastResortFont },
                              "Enabled preview must produce genuine shaped glyphs, not a LastResort hex box")
                XCTAssertTrue(UnicodeFontSupport.missingCodePoints(in: after.fixture.text,
                    font: UnicodeFontSupport.font(for: after.fixture.text, size: 56, enabled: true)).isEmpty)
                let beforePNG = try Data(contentsOf: directory.appendingPathComponent(before.bitmapName))
                let afterPNG = try Data(contentsOf: directory.appendingPathComponent(after.bitmapName))
                XCTAssertNotEqual(afterPNG, beforePNG, "The recovered glyph must visibly change its actual UIKit bitmap")
            } else {
                XCTAssertEqual(after.requestedFontName, before.requestedFontName,
                               "A future native font that covers the fixture should keep its native rendering")
            }
        }

        for id in ["garay-mark-preview", "tulu-mark-preview", "hebrew-05C8-preview", "combining-1AD3-preview", "znamenny-1CF00-preview"] {
            let after = try observation(id, enabled: true, in: report)
            let selected = UnicodeFontSupport.sourceName(for: after.fixture.text, size: 56, enabled: true)
            if selected != nil {
                XCTAssertTrue(after.runs.allSatisfy { !$0.hasZeroGlyph && !$0.hasLastResortFont },
                              "The entire chosen preview, including its dotted-circle base, must shape successfully")
                XCTAssertTrue(UnicodeFontSupport.missingCodePoints(in: after.fixture.text,
                    font: UnicodeFontSupport.font(for: after.fixture.text, size: 56, enabled: true)).isEmpty)
            }
        }

        for id in ["native-latin", "native-omega", "unassigned-0378", "emoji-rocket", "emoji-cracking-face", "emoji-zwj-vs16"] {
            let before = try observation(id, enabled: false, in: report)
            let after = try observation(id, enabled: true, in: report)
            if id == "emoji-cracking-face", after.requestedFontName != before.requestedFontName {
                XCTAssertEqual(UnicodeFontSupport.sourceName(for: after.fixture.text, size: 56, enabled: true), "Noto Color Emoji (preview subset)")
                XCTAssertTrue(after.runs.allSatisfy { !$0.hasZeroGlyph && !$0.hasLastResortFont })
                XCTAssertNotEqual(try Data(contentsOf: directory.appendingPathComponent(after.bitmapName)),
                    try Data(contentsOf: directory.appendingPathComponent(before.bitmapName)))
                continue
            }
            XCTAssertEqual(after.requestedFontName, before.requestedFontName, id)
            XCTAssertEqual(after.runs, before.runs, "Native fallback fonts and shaped emoji glyphs must remain identical: \(id)")
            let beforePNG = try Data(contentsOf: directory.appendingPathComponent(before.bitmapName))
            let afterPNG = try Data(contentsOf: directory.appendingPathComponent(after.bitmapName))
            XCTAssertEqual(afterPNG, beforePNG, "Enabling extra fonts must not alter this native preview: \(id)")
            XCTAssertNil(UnicodeFontSupport.sourceName(for: after.fixture.text, size: 56, enabled: true))
        }

        // Bundled CGFonts must not modify the process-wide system cascade.
        let baseline = try observation("armenian-0558", enabled: false, in: report)
        XCTAssertEqual(UnicodeFontCoverageProbe.shape(baseline.fixture.text, font: system).runs, baseline.runs)
        UnicodeFontSupport.clearCache()
        XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0)
    }

    private func observation(_ id: String, enabled: Bool, in report: UnicodeFontCoverageProbe.Report) throws
        -> UnicodeFontCoverageProbe.Observation {
        try XCTUnwrap(report.observations.first { $0.fixture.id == id && $0.enabled == enabled })
    }
}
#endif
