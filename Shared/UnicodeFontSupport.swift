#if canImport(UIKit)
import UIKit
import CoreText

/// Preview-only fallback. Font files are opened directly, never registered with
/// the process or installed systemwide, so turning this off restores iOS fonts.
@MainActor
enum UnicodeFontSupport {
    struct Asset: Decodable {
        let filename: String
        let displayName: String
        let postScriptName: String
        let sha256: String
        let sourceURL: String
        let licenseFilename: String
        let ranges: [[UInt32]]

        var isValid: Bool {
            guard Self.isResourceFilename(filename), Self.isResourceFilename(licenseFilename),
                  !displayName.isEmpty, !postScriptName.isEmpty,
                  sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  let source = URL(string: sourceURL), source.scheme == "https", source.host != nil,
                  !ranges.isEmpty else { return false }
            var previous: UInt32?
            for range in ranges {
                guard range.count == 2, range[0] <= range[1], range[1] <= 0x10FFFF,
                      !(range[0] <= 0xDFFF && range[1] >= 0xD800),
                      previous.map({ $0 < range[0] }) ?? true else { return false }
                previous = range[1]
            }
            return true
        }

        fileprivate static func isResourceFilename(_ value: String) -> Bool {
            !value.isEmpty && value != "." && value != ".." && !value.contains("/")
                && !value.contains("\\") && !value.contains("\0")
        }

        func contains(_ point: UInt32) -> Bool {
            var lower = 0, upper = ranges.count
            while lower < upper {
                let middle = (lower + upper) / 2
                let range = ranges[middle]
                guard range.count == 2 else { return false }
                if point < range[0] { upper = middle }
                else if point > range[1] { lower = middle + 1 }
                else { return true }
            }
            return false
        }
    }

    private struct Manifest: Decodable { let fonts: [Asset] }
    private static let choices: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 2_048
        return cache
    }()
    private static var graphicsFonts: [Int: CGFont] = [:]
    private static let systemChoice = -1

    static let assets: [Asset] = {
        guard let url = resourceURL("manifest.json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.fonts.allSatisfy(\.isValid),
              Set(manifest.fonts.map(\.filename)).count == manifest.fonts.count,
              Set(manifest.fonts.map(\.postScriptName)).count == manifest.fonts.count else { return [] }
        return manifest.fonts
    }()

    static var loadedFontCount: Int { graphicsFonts.count }

    static func resourceURL(_ filename: String) -> URL? {
        guard Asset.isResourceFilename(filename) else { return nil }
        return Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "Fonts")
    }

    static func clearCache() {
        choices.removeAllObjects()
        graphicsFonts.removeAll()
    }

    static func font(for text: String, size: CGFloat, enabled: Bool) -> UIFont {
        let size = normalizedPointSize(size)
        let system = UIFont.systemFont(ofSize: size)
        guard enabled, !text.isEmpty, !preservesEmoji(text) else { return system }
        let index = choice(for: text, system: system)
        guard index != systemChoice, let graphics = graphicsFont(at: index) else { return system }
        return CTFontCreateWithGraphicsFont(graphics, size, nil, nil) as UIFont
    }

    static func sourceName(for text: String, size: CGFloat, enabled: Bool) -> String? {
        guard enabled, !text.isEmpty, !preservesEmoji(text) else { return nil }
        let index = choice(for: text, system: .systemFont(ofSize: normalizedPointSize(size)))
        return assets.indices.contains(index) ? assets[index].displayName : nil
    }

    static func normalizedPointSize(_ size: CGFloat) -> CGFloat {
        size.isFinite && size > 0 ? min(512, max(1, size)) : UIFont.systemFontSize
    }

    /// Qualified and joined emoji retain Apple's color font and shaping.
    private static func preservesEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains {
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
                if missing.allSatisfy({ hasOutline($0, in: candidate) }),
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
        if let cached = graphicsFonts[index] { return cached }
        guard assets.indices.contains(index), let url = resourceURL(assets[index].filename),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              font.postScriptName as String? == assets[index].postScriptName else { return nil }
        graphicsFonts[index] = font
        return font
    }

    private static func hasOutline(_ point: UInt32, in font: CTFont) -> Bool {
        guard let scalar = Unicode.Scalar(point) else { return false }
        let text = String(scalar)
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        guard let glyph = glyphs.first, glyph != 0,
              let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return false }
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
        let heading = "Extra Unicode fonts\n\nThese unmodified fonts are bundled for offline previews and used only when Extra Unicode fonts is enabled. They do not change fonts in other apps.\n\n"
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
