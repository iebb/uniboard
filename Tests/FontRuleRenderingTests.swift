#if canImport(UIKit)
import XCTest
import UIKit
import CoreText
@testable import Uniboard

/// Font rules drawn through `UnicodeFontSupport` with the pinned Roboto
/// variable font, imported into a temporary font library.
@MainActor
final class FontRuleRenderingTests: XCTestCase {
    private var directory: URL!
    private var library: CustomFontStore!
    private var robotoData: Data!
    private var savedLoader: FontRuleFaceLoader!
    private var savedRules = FontRuleSet.empty
    private var savedEnabled = false
    private let robotoHash = "d7598e12c5dbef095ff8272cfc55da0250bd07fbdecbac8a530b9b277872a134"

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Roboto-Pinned", withExtension: "ttf"))
        robotoData = try Data(contentsOf: url)
        XCTAssertEqual(CustomFontStore.digest(robotoData), robotoHash)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FontRuleRendering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        library = CustomFontStore(directory: directory.appendingPathComponent("CustomFonts-v1", isDirectory: true))
        savedLoader = UnicodeFontSupport.ruleFaceLoader
        savedRules = UnicodeFontSupport.ruleSet
        savedEnabled = UnicodeFontSupport.rulesEnabled
        UnicodeFontSupport.ruleFaceLoader = FontRuleFaceLoader(
            library: library, downloads: UnicodeFontDownloadStore(directory: directory.appendingPathComponent("PreviewFonts-v1")),
            packFonts: [], bundledAssets: [], bundledURL: { _ in nil })
        UnicodeFontSupport.ruleSet = .empty
        UnicodeFontSupport.rulesEnabled = true
    }

    override func tearDown() async throws {
        UnicodeFontSupport.ruleSet = savedRules
        UnicodeFontSupport.rulesEnabled = savedEnabled
        UnicodeFontSupport.ruleFaceLoader = savedLoader
        try? FileManager.default.removeItem(at: directory)
    }

    private func roboto(_ variations: [String: Double] = [:], postScriptName: String = "Roboto-Regular", style: String = "Regular",
                        hash: String? = nil) -> FontFaceReference {
        FontFaceReference(source: .downloaded, family: "Roboto", style: style, postScriptName: postScriptName,
                          identity: .file(sha256: hash ?? robotoHash, faceIndex: 0, variations: variations))
    }

    private func use(_ rules: [FontRule]) {
        UnicodeFontSupport.ruleSet = FontRuleSet(rules: rules)
    }

    private func name(_ font: UIFont) -> String { CTFontCopyPostScriptName(font as CTFont) as String }

    private func addRoboto() throws {
        let added = try library.add(robotoData)
        XCTAssertEqual(added.sha256, robotoHash)
        XCTAssertEqual(added.postScriptName, "Roboto-Regular")
    }

    func testRuleDrawsItsCodePointAndTheSwitchPausesItWithoutDeletingIt() throws {
        try addRoboto()
        let system = UIFont.systemFont(ofSize: 32)
        XCTAssertEqual(UnicodeFontSupport.font(for: "A", size: 32, enabled: true).fontDescriptor, system.fontDescriptor,
                       "Without rules, text keeps today's fonts")
        use([FontRule(id: "a", selector: .codePoint(0x41), face: roboto())])
        let applied = UnicodeFontSupport.resolution(for: "A", size: 32, enabled: true, anchor: .scalar(0x41))
        XCTAssertEqual(applied.source, .rule(FontRuleMatch(ruleIndex: 0, kind: .codePoint)))
        XCTAssertEqual(applied.faceName, "Roboto")
        XCTAssertEqual(name(applied.font), "Roboto-Regular")
        XCTAssertEqual(applied.font.pointSize, 32)
        XCTAssertTrue(applied.skipped.isEmpty)
        XCTAssertEqual(UnicodeFontSupport.sourceName(for: "A", size: 32, enabled: true), "Roboto")
        XCTAssertEqual(UnicodeFontSupport.font(for: "B", size: 32, enabled: true).fontDescriptor, system.fontDescriptor)
        XCTAssertEqual(UnicodeFontSupport.resolution(for: "A", size: 32, enabled: false).source, .system,
                       "A preview with Extra Unicode Fonts off draws stock fonts")

        let generation = UnicodeFontSupport.fontGeneration
        UnicodeFontSupport.rulesEnabled = false
        XCTAssertNotEqual(UnicodeFontSupport.fontGeneration, generation, "Measured previews are stale once rules pause")
        let paused = UnicodeFontSupport.resolution(for: "A", size: 32, enabled: true)
        XCTAssertEqual(paused.source, .system)
        XCTAssertEqual(paused.font.fontDescriptor, system.fontDescriptor)
        XCTAssertNil(UnicodeFontSupport.sourceName(for: "A", size: 32, enabled: true))
        XCTAssertEqual(UnicodeFontSupport.ruleSet.rules.count, 1, "Off pauses rules; it never deletes them")
        UnicodeFontSupport.rulesEnabled = true
        XCTAssertEqual(name(UnicodeFontSupport.font(for: "A", size: 32, enabled: true)), "Roboto-Regular")
    }

    func testUnavailableOrUndrawableFacesFallThroughWithTheirReason() throws {
        try addRoboto()
        let missing = roboto(hash: String(repeating: "0", count: 64))
        let wrongName = roboto(postScriptName: "Roboto-Black")
        use([
            FontRule(id: "a", selector: .codePoint(0x41), face: missing),
            FontRule(id: "b", selector: .codePoint(0x42), face: wrongName),
            FontRule(id: "runic", selector: .codePoint(0x16A0), face: roboto()),
            FontRule(id: "latin", selector: .range(first: 0x41, last: 0x5A), face: roboto(["wght": 700], postScriptName: "Roboto-Bold", style: "Bold")),
        ])
        let a = UnicodeFontSupport.resolution(for: "A", size: 20, enabled: true)
        XCTAssertEqual(a.skipped, [.init(match: FontRuleMatch(ruleIndex: 0, kind: .codePoint), reason: .unavailable)])
        XCTAssertEqual(a.source, .rule(FontRuleMatch(ruleIndex: 3, kind: .range)), "The next matching rule applies")
        XCTAssertEqual(a.faceName, "Roboto Bold")
        XCTAssertEqual(UnicodeFontSupport.unavailability(of: missing), .missingFile)

        let b = UnicodeFontSupport.resolution(for: "B", size: 20, enabled: true)
        XCTAssertEqual(b.skipped.map(\.reason), [.unavailable])
        XCTAssertEqual(UnicodeFontSupport.unavailability(of: wrongName), .identityMismatch,
                       "A file with the right hash but another face is not that face")

        let runic = UnicodeFontSupport.resolution(for: "\u{16A0}", size: 20, enabled: true)
        XCTAssertEqual(runic.skipped, [.init(match: FontRuleMatch(ruleIndex: 2, kind: .codePoint), reason: .cannotDisplay)])
        XCTAssertNotEqual(runic.source, .rule(FontRuleMatch(ruleIndex: 2, kind: .codePoint)), "Roboto has no Runic, so default fonts draw it")
        XCTAssertNotEqual(name(runic.font), "Roboto-Regular")
    }

    func testFontAddedLaterActivatesItsSavedRule() throws {
        use([FontRule(id: "a", selector: .codePoint(0x41), face: roboto())])
        let before = UnicodeFontSupport.resolution(for: "A", size: 24, enabled: true)
        XCTAssertEqual(before.skipped.map(\.reason), [.unavailable])
        XCTAssertEqual(before.source, .system)
        try addRoboto()
        XCTAssertTrue(UnicodeFontSupport.refreshDownloadedFonts(force: true), "A library change is a font refresh")
        let after = UnicodeFontSupport.resolution(for: "A", size: 24, enabled: true)
        XCTAssertEqual(after.source, .rule(FontRuleMatch(ruleIndex: 0, kind: .codePoint)))
        XCTAssertEqual(name(after.font), "Roboto-Regular")
    }

    func testVariationInstanceIdentityAndRetainedOwnershipChain() throws {
        try addRoboto()
        let bold = roboto(["wght": 700, "wdth": 100], postScriptName: "Roboto-Bold", style: "Bold")
        let clamped = roboto(["wght": 5000])
        use([FontRule(id: "a", selector: .codePoint(0x41), face: bold),
             FontRule(id: "b", selector: .codePoint(0x42), face: clamped)])
        var font: UIFont? = UnicodeFontSupport.font(for: "A", size: 64, enabled: true)
        let coordinates = FontRuleFaceLoader.effectiveCoordinates(try XCTUnwrap(font) as CTFont)
        XCTAssertEqual(try XCTUnwrap(coordinates[2003265652]).doubleValue, 700, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(coordinates[2003072104]).doubleValue, 100, accuracy: 0.0001)
        let owner = try XCTUnwrap(LoadedRuleFont.owner(of: try XCTUnwrap(font)), "Every rule font owns its CoreText chain")
        XCTAssertNotNil(owner.graphics)
        XCTAssertNotNil(owner.dataProvider)
        XCTAssertNotNil(owner.data)
        XCTAssertEqual(UnicodeFontSupport.resolution(for: "B", size: 64, enabled: true).skipped.map(\.reason), [.unavailable])
        XCTAssertEqual(UnicodeFontSupport.unavailability(of: clamped), .identityMismatch,
                       "A requested instance the font can't make is not that face")

        // The cache lets the face go; the font on screen keeps drawing.
        UnicodeFontSupport.clearCache()
        XCTAssertEqual(UnicodeFontSupport.loadedRuleFaceCount, 0)
        var pixels = [UInt8](repeating: 0, count: 128 * 96 * 4)
        autoreleasepool {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "A", attributes: [.font: font!]))
            font = nil
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 128 * 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.textPosition = CGPoint(x: 16, y: 20)
                CTLineDraw(line, context)
            }
        }
        XCTAssertTrue(pixels.contains { $0 != 0 }, "A variable rule face still draws after its cache entry is gone")
    }

    func testRuleFacesLoadLazilyInTheirOwnCacheOfFour() throws {
        try addRoboto()
        let weights: [Double] = [100, 200, 300, 500, 600, 800]
        use(weights.enumerated().map { index, weight in
            FontRule(id: "w\(index)", selector: .codePoint(0x41 + UInt32(index)),
                     face: roboto(["wght": weight], postScriptName: "Roboto", style: "W\(Int(weight))"))
        })
        XCTAssertEqual(UnicodeFontSupport.loadedRuleFaceCount, 0, "Nothing loads before a preview needs it")
        var fonts: [UIFont] = []
        for (index, weight) in weights.enumerated() {
            let text = String(UnicodeScalar(0x41 + UInt32(index))!)
            let resolution = UnicodeFontSupport.resolution(for: text, size: 30, enabled: true)
            XCTAssertEqual(resolution.source, .rule(FontRuleMatch(ruleIndex: index, kind: .codePoint)), text)
            let coordinate = FontRuleFaceLoader.effectiveCoordinates(resolution.font as CTFont)[2003265652]?.doubleValue
            XCTAssertEqual(coordinate ?? 0, weight, accuracy: 0.0001)
            fonts.append(resolution.font)
            XCTAssertLessThanOrEqual(UnicodeFontSupport.loadedRuleFaceCount, UnicodeFontSupport.maximumLoadedRuleFaces)
        }
        XCTAssertEqual(UnicodeFontSupport.loadedRuleFaceCount, UnicodeFontSupport.maximumLoadedRuleFaces)
        XCTAssertEqual(UnicodeFontSupport.loadedFontCount, 0, "Rule faces never evict or load fallback fonts")
        XCTAssertTrue(fonts.allSatisfy { LoadedRuleFont.owner(of: $0) != nil })
        let loads = UnicodeFontSupport.ruleFaceLoadCount
        _ = UnicodeFontSupport.font(for: "F", size: 30, enabled: true)
        XCTAssertEqual(UnicodeFontSupport.ruleFaceLoadCount, loads, "A cached decision and font open nothing again")
    }

    func testAnchorsScaffoldsAndPlaceholders() throws {
        try addRoboto()
        XCTAssertEqual(UnicodeCharacter(codePoint: 0x20, name: "SPACE", detail: "", blockName: "Basic Latin", category: "Zs").fontRuleAnchor, FontRuleAnchor.none)
        XCTAssertEqual(UnicodeCharacter(codePoint: 0x200B, name: "ZWSP", detail: "", blockName: "General Punctuation", category: "Cf", isInvisible: true).fontRuleAnchor, FontRuleAnchor.none)
        XCTAssertEqual(UnicodeCharacter(codePoint: 0x0378, name: "", detail: "", blockName: "Greek", category: "Cn").fontRuleAnchor, FontRuleAnchor.none)
        let acute = UnicodeCharacter(codePoint: 0x0301, name: "COMBINING ACUTE ACCENT", detail: "", blockName: "Combining Diacritical Marks", category: "Mn")
        XCTAssertEqual(acute.displayText, "\u{25CC}\u{0301}")
        XCTAssertEqual(acute.fontRuleAnchor, .scalar(0x0301))
        XCTAssertEqual(UnicodeFontSupport.ruleAnchor(of: "\u{25CC}\u{0301}", .automatic), 0x0301, "A scaffold defers to its mark")
        XCTAssertEqual(UnicodeFontSupport.ruleAnchor(of: "\u{25CC}", .automatic), 0x25CC)
        XCTAssertEqual(UnicodeFontSupport.ruleAnchor(of: "e\u{0301}", .automatic), 0x65)
        XCTAssertEqual(UnicodeFontSupport.ruleAnchor(of: "\u{1F469}\u{200D}\u{1F4BB}", .automatic), 0x1F469)
        XCTAssertNil(UnicodeFontSupport.ruleAnchor(of: "A", .none))

        use([FontRule(id: "acute", selector: .codePoint(0x0301), face: roboto()),
             FontRule(id: "circle", selector: .codePoint(0x25CC), face: roboto(["wght": 900], postScriptName: "Roboto-Black", style: "Black"))])
        // CoreText draws a cluster whose base the face lacks in a fallback
        // font, mark included; Roboto has no "◌", so its mark rule is passed
        // over rather than named for pixels it doesn't draw.
        let mark = UnicodeFontSupport.resolution(for: acute.displayText, size: 40, enabled: true, anchor: acute.fontRuleAnchor)
        XCTAssertEqual(mark.skipped, [.init(match: FontRuleMatch(ruleIndex: 0, kind: .codePoint), reason: .cannotDisplay)],
                       "The mark's rule, not the dotted circle's")
        XCTAssertNotEqual(mark.faceName, "Roboto Black")
        let carried = UnicodeFontSupport.resolution(for: "e\u{0301}", size: 40, enabled: true, anchor: .scalar(0x0301))
        XCTAssertEqual(carried.source, .rule(FontRuleMatch(ruleIndex: 0, kind: .codePoint)), "A face that draws the whole cluster takes the mark's rule")
        XCTAssertEqual(name(carried.font), "Roboto-Regular")
        let placeholder = UnicodeFontSupport.resolution(for: "\u{25CC}", size: 40, enabled: true, anchor: .none)
        XCTAssertFalse(placeholder.faceName == "Roboto Black", "A placeholder picture takes no rule")
        XCTAssertTrue(placeholder.skipped.isEmpty)
    }

    func testMixedTextStaysExactAndCopyImageDrawsThePreviewFonts() throws {
        try addRoboto()
        let latin = try XCTUnwrap(FontRuleBlock(named: "Basic Latin"))
        XCTAssertEqual(latin.first, 0)
        XCTAssertEqual(latin.last, 0x7F)
        use([FontRule(id: "latin", selector: .block(latin), face: roboto(["wght": 700], postScriptName: "Roboto-Bold", style: "Bold"))])
        let text = "Ae\u{0301} \u{05D0}\u{1F469}\u{200D}\u{1F4BB}\u{2603}\u{FE0F}x"
        let excerpt = KeyboardTextPreviewLayout.excerpt(before: text, after: "", availableWidth: 2_000)
        XCTAssertEqual(Array(excerpt.visibleText.unicodeScalars), Array(text.unicodeScalars), "Rendering never changes the text")
        let measurer = KeyboardTextPreviewLayout.Measurer()
        for character in text {
            let cluster = String(character)
            XCTAssertEqual(name(measurer.font(for: cluster)), name(KeyboardTextPreviewLayout.font(for: cluster)), cluster)
        }
        XCTAssertEqual(name(KeyboardTextPreviewLayout.font(for: "A")), "Roboto-Bold")
        XCTAssertEqual(name(KeyboardTextPreviewLayout.font(for: "e\u{0301}")), "Roboto-Bold", "A cluster follows its base letter")
        XCTAssertNotEqual(name(KeyboardTextPreviewLayout.font(for: "\u{1F469}\u{200D}\u{1F4BB}")), "Roboto-Bold")
        XCTAssertNotEqual(name(KeyboardTextPreviewLayout.font(for: "\u{05D0}")), "Roboto-Bold")

        // Copy Image shapes the same runs as the row.
        let line = CTLineCreateWithAttributedString(KeyboardTextPreviewLayout.attributedText(text))
        let rowLine = measurer.line(text)
        func runFonts(_ line: CTLine) -> [String] {
            (CTLineGetGlyphRuns(line) as! [CTRun]).map { run in
                CTFontCopyPostScriptName((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String
            }
        }
        XCTAssertEqual(runFonts(line), runFonts(rowLine))
        XCTAssertEqual(runFonts(line).first, "Roboto-Bold")
        let image = try KeyboardPreviewImageRenderer.render(excerpt, availableWidth: 2_000, visibleHeight: 44,
                                                            foreground: .black, background: .white).get()
        XCTAssertEqual(image.visibleText, excerpt.visibleText)

        let generation = UnicodeFontSupport.fontGeneration
        use([])
        XCTAssertNotEqual(UnicodeFontSupport.fontGeneration, generation, "A rules change measures the preview again")
        XCTAssertNotEqual(name(KeyboardTextPreviewLayout.font(for: "A")), "Roboto-Bold")
    }

    func testRuleRenderingMakesNoNetworkRequests() throws {
        RequestSpy.count = 0
        URLProtocol.registerClass(RequestSpy.self)
        defer { URLProtocol.unregisterClass(RequestSpy.self) }
        try addRoboto()
        use([FontRule(id: "a", selector: .codePoint(0x41), face: roboto()),
             FontRule(id: "b", selector: .codePoint(0x42), face: roboto(hash: String(repeating: "1", count: 64))),
             FontRule(id: "c", selector: .codePoint(0x43), face: FontFaceReference(source: .installed, family: "Nope", style: "Regular",
                                                                                 postScriptName: "NoSuchFont-Regular",
                                                                                 identity: .process(postScriptName: "NoSuchFont-Regular", variations: [:])))])
        for text in ["A", "B", "C"] { _ = UnicodeFontSupport.resolution(for: text, size: 20, enabled: true) }
        XCTAssertEqual(UnicodeFontSupport.resolution(for: "C", size: 20, enabled: true).skipped.map(\.reason), [.unavailable],
                       "An installed face that isn't on the device never becomes another font")
        XCTAssertEqual(RequestSpy.count, 0)
    }

    func testInstalledFaceLoadsByPostScriptNameOnly() throws {
        let installed = FontFaceReference(source: .installed, family: "Chalkduster", style: "Regular", postScriptName: "Chalkduster",
                                          identity: .process(postScriptName: "Chalkduster", variations: [:]))
        guard CTFontCopyPostScriptName(CTFontCreateWithName("Chalkduster" as CFString, 12, nil)) as String == "Chalkduster" else {
            throw XCTSkip("Chalkduster isn't installed on this runtime")
        }
        use([FontRule(id: "a", selector: .codePoint(0x41), face: installed)])
        let resolution = UnicodeFontSupport.resolution(for: "A", size: 28, enabled: true)
        XCTAssertEqual(name(resolution.font), "Chalkduster")
        XCTAssertEqual(resolution.faceName, "Chalkduster")
        XCTAssertNil(LoadedRuleFont.owner(of: resolution.font)?.graphics)
    }
}

private final class RequestSpy: URLProtocol {
    static var count = 0
    override class func canInit(with request: URLRequest) -> Bool { count += 1; return false }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
#endif
