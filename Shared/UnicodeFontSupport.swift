#if canImport(UIKit)
import UIKit
import CoreText

/// Preview-only fallback. Font files are opened directly, never registered with
/// the process or installed systemwide, so turning this off restores iOS fonts.
@MainActor
enum UnicodeFontSupport {
    typealias Asset = UnicodeFontAsset

    private struct Manifest: Decodable { let fonts: [Asset] }
    private static let choices: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 2_048
        return cache
    }()
    private static var graphicsFonts: [Int: CGFont] = [:]
    private static var fontRecency: [Int] = []
    static let maximumLoadedFonts = 4
    private static var downloadRevision = ""
    private static var lastRevisionCheck = -Double.infinity
    private static let systemChoice = -1

    static let bundledAssets: [Asset] = {
        guard let url = resourceURL("manifest.json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.fonts.allSatisfy(\.isValid),
              Set(manifest.fonts.map(\.filename)).count == manifest.fonts.count,
              Set(manifest.fonts.map(\.postScriptName)).count == manifest.fonts.count else { return [] }
        return manifest.fonts
    }()

    static let assets: [Asset] = {
        let downloads = UnicodeFontPackCatalog.bundled.packs.flatMap(\.fonts).map(\.asset)
        let noto = downloads.filter { $0.displayName.hasPrefix("Noto") }
        let other = downloads.filter { !$0.displayName.hasPrefix("Noto") }
        let bundledNoto = bundledAssets.filter { $0.displayName.hasPrefix("Noto") }
        return noto + bundledNoto + other + bundledAssets.filter { !$0.displayName.hasPrefix("Noto") }
    }()
    private static let downloadable = Dictionary(uniqueKeysWithValues:
        UnicodeFontPackCatalog.bundled.packs.flatMap(\.fonts).map { ($0.asset.filename, $0) })
    private static let emojiPreviewAssets = UnicodeFontPackCatalog.bundled.packs
        .filter { $0.id == "emoji-latest" }.flatMap(\.fonts).map(\.asset)

    private static func isEmojiPreview(_ point: UInt32) -> Bool {
        emojiPreviewAssets.contains { $0.contains(point) }
    }

    static var loadedFontCount: Int { graphicsFonts.count }

    @discardableResult
    static func refreshDownloadedFonts(force: Bool = false) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastRevisionCheck >= 0.5 else { return false }
        lastRevisionCheck = now
        let revision = UnicodeFontDownloadStore.shared.revision
        guard revision != downloadRevision else { return false }
        downloadRevision = revision
        clearCache()
        return true
    }

    static func resourceURL(_ filename: String) -> URL? {
        guard Asset.isResourceFilename(filename) else { return nil }
        if let bundled = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "Fonts") { return bundled }
        guard let font = downloadable[filename] else { return nil }
        return UnicodeFontDownloadStore.shared.installedURL(for: font)
    }

    static func clearCache() {
        choices.removeAllObjects()
        graphicsFonts.removeAll()
        fontRecency.removeAll()
    }

    static func font(for text: String, size: CGFloat, enabled: Bool) -> UIFont {
        let size = normalizedPointSize(size)
        let system = UIFont.systemFont(ofSize: size)
        guard enabled, !text.isEmpty, !preservesEmoji(text) else { return system }
        refreshDownloadedFonts()
        let index = choice(for: text, system: system)
        guard index != systemChoice, let graphics = graphicsFont(at: index) else { return system }
        return CTFontCreateWithGraphicsFont(graphics, size, nil, nil) as UIFont
    }

    static func sourceName(for text: String, size: CGFloat, enabled: Bool) -> String? {
        guard enabled, !text.isEmpty, !preservesEmoji(text) else { return nil }
        refreshDownloadedFonts()
        let index = choice(for: text, system: .systemFont(ofSize: normalizedPointSize(size)))
        return assets.indices.contains(index) ? assets[index].displayName : nil
    }

    static func normalizedPointSize(_ size: CGFloat) -> CGFloat {
        size.isFinite && size > 0 ? min(512, max(1, size)) : UIFont.systemFontSize
    }

    /// Only the audited standalone emoji (optionally with VS16) may use the
    /// color preview pack. Joined/modifier/flag sequences retain Apple's shaping.
    private static func preservesEmoji(_ text: String) -> Bool {
        let points = text.unicodeScalars.map(\.value)
        if let first = points.first, isEmojiPreview(first),
           points.count == 1 || (points.count == 2 && points[1] == 0xFE0F) { return false }
        return text.unicodeScalars.contains {
            $0.value == 0xFE0F || $0.value == 0x200D || (0xE0020...0xE007F).contains($0.value)
                || $0.properties.isEmojiPresentation
        }
    }

    private static func choice(for text: String, system: UIFont) -> Int {
        if let cached = choices.object(forKey: text as NSString) { return cached.intValue }
        let missing = missingCodePoints(in: text, font: system)
        var selected = systemChoice
        if !missing.isEmpty {
            for (index, asset) in assets.enumerated() where missing.allSatisfy(asset.contains) {
                guard let graphics = graphicsFont(at: index) else { continue }
                let candidate = CTFontCreateWithGraphicsFont(graphics, 32, nil, nil)
                // A whitelist alone is insufficient: reject corrupt/non-drawing
                // glyphs rather than replace one placeholder with another.
                if missing.allSatisfy({ hasArtwork($0, in: candidate) }),
                   missingCodePoints(in: text, font: candidate as UIFont).isEmpty {
                    selected = index
                    break
                }
            }
        }
        choices.setObject(NSNumber(value: selected), forKey: text as NSString)
        return selected
    }

    private static func graphicsFont(at index: Int) -> CGFont? {
        if let cached = graphicsFonts[index] {
            fontRecency.removeAll { $0 == index }
            fontRecency.append(index)
            return cached
        }
        guard assets.indices.contains(index), let url = resourceURL(assets[index].filename),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              font.postScriptName as String? == assets[index].postScriptName else { return nil }
        graphicsFonts[index] = font
        fontRecency.append(index)
        while fontRecency.count > maximumLoadedFonts {
            graphicsFonts.removeValue(forKey: fontRecency.removeFirst())
        }
        return font
    }

    private static func hasArtwork(_ point: UInt32, in font: CTFont) -> Bool {
        guard let scalar = Unicode.Scalar(point) else { return false }
        let text = String(scalar)
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        guard let glyph = glyphs.first, glyph != 0 else { return false }
        // COLR glyphs draw through paint layers and may have no base outline.
        // Only pinned, bitmap-verified standalone emoji may take this path.
        if isEmojiPreview(point), CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs) { return true }
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return false }
        return !path.isEmpty
    }

    /// Core Text's actual shaped runs include iOS fallback fonts. LastResort
    /// glyphs have nonzero IDs, so checking glyph zero alone misses many tofus.
    static func missingCodePoints(in text: String, font: UIFont) -> [UInt32] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var missingRanges: [CFRange] = []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            let name = (CTFontCopyPostScriptName(runFont) as String).lowercased()
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            if name.contains("lastresort") {
                missingRanges.append(CTRunGetStringRange(run))
            } else if glyphs.contains(0) {
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                for i in glyphs.indices where glyphs[i] == 0 {
                    missingRanges.append(CFRange(location: indices[i], length: 1))
                }
            }
        }
        var offset = 0
        var missing: [UInt32] = []
        for scalar in text.unicodeScalars {
            let length = scalar.value > 0xFFFF ? 2 : 1
            defer { offset += length }
            if scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format
                || scalar.properties.isDefaultIgnorableCodePoint { continue }
            if missingRanges.contains(where: { $0.location < offset + length && $0.location + $0.length > offset }) {
                missing.append(scalar.value)
            }
        }
        return missing
    }

    static var licenseText: String {
        guard !assets.isEmpty else { return "Bundled font license information is unavailable." }
        let heading = "Extra Unicode fonts\n\nBundled fonts and optional downloaded subsets are used only when Extra Unicode fonts is enabled. Downloads are managed in the app and work offline afterwards. They do not change fonts in other apps.\n\n"
        let names = assets.map { "\($0.displayName)\nSource: \($0.sourceURL)" }.joined(separator: "\n\n")
        let filenames = Array(Set(assets.map(\.licenseFilename))).sorted()
        let licenses = filenames.compactMap { filename -> String? in
            guard let url = resourceURL(filename), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return text
        }.joined(separator: "\n\n────────\n\n")
        return heading + names + "\n\n" + licenses
    }
}
#endif
