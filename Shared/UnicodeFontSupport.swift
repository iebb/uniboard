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
        cache.countLimit = 8_192
        return cache
    }()
    /// Scalars the stock fonts cannot draw, shared by the missing-glyph tint
    /// and the font choice so each preview is shaped once.
    private static let stockMissing: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 8_192
        return cache
    }()
    /// Resolved preview fonts by asset and point size.
    private static let resolvedFonts: NSCache<NSString, UIFont> = {
        let cache = NSCache<NSString, UIFont>()
        cache.countLimit = 64
        return cache
    }()
    private static var graphicsFonts: [Int: CGFont] = [:]
    /// A 32-point instance of each loaded font for coverage checks.
    private static var referenceFonts: [Int: CTFont] = [:]
    /// Assets whose file is not installed or does not open, until downloads change.
    private static var unavailableFonts: Set<Int> = []
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
    /// Color emoji fallbacks, tried in catalog order only for emoji text that
    /// the stock fonts cannot draw as complete glyphs.
    private static let emojiFilenames = Set(UnicodeFontPackCatalog.bundled.packs
        .filter { $0.id == "emoji" }.flatMap(\.fonts).map(\.asset.filename))

    private static func isEmojiAsset(_ asset: Asset) -> Bool { emojiFilenames.contains(asset.filename) }

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
        stockMisses.removeAllObjects()
        stockMissing.removeAllObjects()
        resolvedFonts.removeAllObjects()
        graphicsFonts.removeAll()
        referenceFonts.removeAll()
        unavailableFonts.removeAll()
        fontRecency.removeAll()
    }

    static func font(for text: String, size: CGFloat, enabled: Bool) -> UIFont {
        let size = normalizedPointSize(size)
        let system = UIFont.systemFont(ofSize: size)
        guard enabled, !text.isEmpty else { return system }
        refreshDownloadedFonts()
        let index = choice(for: text, system: system)
        guard index != systemChoice else { return system }
        let key = "\(index)@\(size)" as NSString
        if let cached = resolvedFonts.object(forKey: key) { return cached }
        guard let graphics = graphicsFont(at: index) else { return system }
        let font = CTFontCreateWithGraphicsFont(graphics, size, nil, nil) as UIFont
        resolvedFonts.setObject(font, forKey: key)
        return font
    }

    private static let systemReference = UIFont.systemFont(ofSize: 32) as CTFont

    /// Whether the system font has a glyph for every UTF-16 unit of `text`.
    private static func systemFontDraws(_ text: String) -> Bool {
        var characters = Array(text.utf16)
        guard !characters.isEmpty, characters.count <= 8 else { return false }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(systemReference, &characters, &glyphs, characters.count)
    }

    /// The scalars of `text` that the stock fonts draw as a placeholder.
    private static func stockMissingCodePoints(in text: String) -> [UInt32] {
        if let cached = stockMissing.object(forKey: text as NSString) as? [UInt32] { return cached }
        // Most previews are drawn by the system font itself; only text it
        // lacks needs a full shaping pass through the fallback cascade.
        let missing = systemFontDraws(text) ? [] : missingCodePoints(in: text, font: .systemFont(ofSize: 32))
        stockMissing.setObject(missing as NSArray, forKey: text as NSString)
        return missing
    }

    static func sourceName(for text: String, size: CGFloat, enabled: Bool) -> String? {
        guard enabled, !text.isEmpty else { return nil }
        refreshDownloadedFonts()
        let index = choice(for: text, system: .systemFont(ofSize: normalizedPointSize(size)))
        return assets.indices.contains(index) ? assets[index].displayName : nil
    }

    static func normalizedPointSize(_ size: CGFloat) -> CGFloat {
        size.isFinite && size > 0 ? min(512, max(1, size)) : UIFont.systemFontSize
    }

    /// Emoji presentation, emoji sequences, and scalars this runtime's Unicode
    /// tables do not know yet but an emoji fallback covers. VS15 keeps text.
    static func isEmojiText(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { $0.value == 0xFE0E }) { return false }
        return scalars.contains { scalar in
            let value = scalar.value
            return value == 0xFE0F || value == 0x200D || value == 0x20E3 || (0xE0020...0xE007F).contains(value)
                || (0x1F3FB...0x1F3FF).contains(value) || scalar.properties.isEmojiPresentation
                || (scalar.properties.generalCategory == .unassigned
                    && assets.contains { isEmojiAsset($0) && $0.contains(value) })
        }
    }

    /// Stock or fallback rendering is accepted only when nothing tofus and no
    /// emoji sequence falls apart into more glyphs than visible characters.
    private static func drawsEmoji(_ text: String, font: UIFont) -> Bool {
        missingCodePoints(in: text, font: font).isEmpty && visibleGlyphCount(in: text, font: font) <= text.count
    }

    private static func choice(for text: String, system: UIFont) -> Int {
        if let cached = choices.object(forKey: text as NSString) { return cached.intValue }
        var selected = systemChoice
        if isEmojiText(text) {
            if stockFontsMiss(text, emoji: true) {
                for (index, asset) in assets.enumerated() where isEmojiAsset(asset) {
                    guard let reference = referenceFont(at: index) else { continue }
                    let candidate = reference as UIFont
                    if drawsEmoji(text, font: candidate), inks(text, font: candidate) {
                        selected = index
                        break
                    }
                }
            }
        } else {
            let missing = stockMissingCodePoints(in: text)
            if !missing.isEmpty {
                for (index, asset) in assets.enumerated() where !isEmojiAsset(asset) && missing.allSatisfy(asset.contains) {
                    guard let candidate = referenceFont(at: index) else { continue }
                    // A whitelist alone is insufficient: reject corrupt/non-drawing
                    // glyphs rather than replace one placeholder with another.
                    if missing.allSatisfy({ hasArtwork($0, in: candidate) }),
                       missingCodePoints(in: text, font: candidate as UIFont).isEmpty {
                        selected = index
                        break
                    }
                }
            }
        }
        choices.setObject(NSNumber(value: selected), forKey: text as NSString)
        return selected
    }

    /// A color glyph can exist in the cmap yet draw nothing (for example COLR
    /// paint on a runtime without support), so render once and look for ink.
    private static func inks(_ text: String, font: UIFont) -> Bool {
        let width = 64 * max(1, text.count), height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.textPosition = CGPoint(x: 8, y: 16)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font])), context)
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }

    private static func graphicsFont(at index: Int) -> CGFont? {
        if let cached = graphicsFonts[index] {
            fontRecency.removeAll { $0 == index }
            fontRecency.append(index)
            return cached
        }
        // A missing download is checked once per download revision, not on
        // every preview that its ranges cover.
        guard !unavailableFonts.contains(index) else { return nil }
        guard assets.indices.contains(index), let url = resourceURL(assets[index].filename),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              font.postScriptName as String? == assets[index].postScriptName else {
            unavailableFonts.insert(index)
            return nil
        }
        graphicsFonts[index] = font
        fontRecency.append(index)
        while fontRecency.count > maximumLoadedFonts {
            let evicted = fontRecency.removeFirst()
            graphicsFonts.removeValue(forKey: evicted)
            referenceFonts.removeValue(forKey: evicted)
        }
        return font
    }

    /// A 32-point instance of a loaded font, made once while it stays loaded.
    private static func referenceFont(at index: Int) -> CTFont? {
        guard let graphics = graphicsFont(at: index) else { return nil }
        if let cached = referenceFonts[index] { return cached }
        let font = CTFontCreateWithGraphicsFont(graphics, 32, nil, nil)
        referenceFonts[index] = font
        return font
    }

    private static func hasArtwork(_ point: UInt32, in font: CTFont) -> Bool {
        guard let scalar = Unicode.Scalar(point) else { return false }
        let text = String(scalar)
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        guard let glyph = glyphs.first, glyph != 0 else { return false }
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

    /// Visible glyphs in the shaped line. Ligature-deleted slots and
    /// zero-advance joiners/selectors are not counted, so a supported emoji
    /// sequence is one glyph and an unsupported one draws its separate parts.
    static func visibleGlyphCount(in text: String, font: UIFont) -> Int {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var count = 0
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let length = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: length)
            var advances = [CGSize](repeating: .zero, count: length)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            count += zip(glyphs, advances).filter { $0.0 != 0xFFFF && $0.1.width > 0.5 }.count
        }
        return count
    }

    private static let stockMisses: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 4_096
        return cache
    }()

    /// Whether iOS's own fonts cannot draw `text` completely: a placeholder,
    /// or an emoji sequence split into pieces. A fallback preview still counts,
    /// since other apps will not have that font.
    static func stockFontsMiss(_ text: String, emoji: Bool = false) -> Bool {
        guard !text.isEmpty else { return false }
        let key = "\(emoji ? 1 : 0)\(text)" as NSString
        if let cached = stockMisses.object(forKey: key) { return cached.boolValue }
        let system = UIFont.systemFont(ofSize: 32)
        let miss = emoji || isEmojiText(text) ? !drawsEmoji(text, font: system)
            : !stockMissingCodePoints(in: text).isEmpty
        stockMisses.setObject(NSNumber(value: miss), forKey: key)
        return miss
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
