#if canImport(UIKit)
import UIKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// The text the keyboard's preview row actually shows either side of the
/// caret. Only this excerpt is ever drawn, rendered or copied; the bounded
/// host context it was cut from never leaves the layout function.
struct KeyboardPreviewExcerpt: Equatable {
    /// Displayed text before the caret, including a leading truncation
    /// ellipsis when earlier text is hidden.
    var before: String
    /// Displayed text after the caret, including a trailing truncation
    /// ellipsis when later text is hidden.
    var after: String
    var beforeTruncated: Bool
    var afterTruncated: Bool
    /// Drawn as one shaped line with an overlaid caret (the movable preview
    /// cursor), not as two texts with a caret-wide gap.
    var isSingleLine = false

    static let empty = KeyboardPreviewExcerpt(before: "", after: "", beforeTruncated: false, afterTruncated: false)

    /// The plain-text equivalent of what is visible, in logical order.
    var visibleText: String { before + after }

    /// Whether anything other than whitespace, invisible format characters
    /// and truncation ellipses is shown.
    var hasVisibleCharacters: Bool {
        var text = Substring(before)
        if beforeTruncated, text.hasPrefix(KeyboardTextPreviewLayout.ellipsis) { text = text.dropFirst() }
        var tail = Substring(after)
        if afterTruncated, tail.hasSuffix(KeyboardTextPreviewLayout.ellipsis) { tail = tail.dropLast() }
        return (text + tail).unicodeScalars.contains { scalar in
            !scalar.properties.isWhitespace && scalar.properties.generalCategory != .format
                && scalar.properties.generalCategory != .control
        }
    }
}

/// Decides which characters of the bounded host context fit in the preview
/// row. The row draws exactly this result, so the exported image and the
/// on-screen preview share one definition of "visible".
@MainActor
enum KeyboardTextPreviewLayout {
    static let fontSize: CGFloat = 18
    static let caretWidth: CGFloat = 2
    /// The trailing Inspect and Preview actions buttons inside the row,
    /// 44 points each, so a frozen excerpt equals the visible text.
    static let actionsButtonWidth: CGFloat = 2 * actionButtonWidth
    static let actionButtonWidth: CGFloat = 44
    /// Measurement slack, so SwiftUI's own rounding never truncates again.
    static let fittingSlack: CGFloat = 2
    nonisolated static let ellipsis = "…"

    /// The font the preview row uses for one displayed character.
    static func font(for character: String) -> UIFont {
        UnicodeFontSupport.font(for: character, size: fontSize, enabled: true)
    }

    /// Per-character font runs, matching the preview row's `AttributedString`.
    static func attributedText(_ text: String, font: (String) -> UIFont = font(for:),
                               foreground: UIColor? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        guard result.length > 0 else { return result }
        if let foreground {
            result.addAttributes([.foregroundColor: foreground,
                                  NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground.cgColor],
                                 range: NSRange(location: 0, length: result.length))
        }
        var location = 0
        for character in text {
            let length = character.utf16.count
            result.addAttribute(.font, value: font(String(character)), range: NSRange(location: location, length: length))
            location += length
        }
        return result
    }

    static func width(of text: String, font: (String) -> UIFont = font(for:)) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(attributedText(text, font: font))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Measures preview text for one layout pass: each character's font is
    /// resolved once, and each distinct string is shaped into one line once.
    @MainActor
    final class Measurer {
        private let resolve: @MainActor (String) -> UIFont
        private var fonts: [String: UIFont] = [:]
        private var lines: [String: CTLine] = [:]
        private var widths: [String: CGFloat] = [:]

        init(font: @escaping @MainActor (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) { resolve = font }

        /// Distinct strings shaped so far.
        var shapedLineCount: Int { lines.count }

        func font(for character: String) -> UIFont {
            if let font = fonts[character] { return font }
            let font = resolve(character)
            fonts[character] = font
            return font
        }

        func line(_ text: String) -> CTLine {
            if let line = lines[text] { return line }
            let line = CTLineCreateWithAttributedString(KeyboardTextPreviewLayout.attributedText(text, font: font(for:)))
            lines[text] = line
            return line
        }

        /// Identical to `KeyboardTextPreviewLayout.width(of:)` with the same fonts.
        func width(of text: String) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            if let width = widths[text] { return width }
            let width = CGFloat(CTLineGetTypographicBounds(line(text), nil, nil, nil))
            widths[text] = width
            return width
        }

        /// The advance each of `characters` contributes to the shaped line of
        /// `text`, in which they start `utf16Offset` units in. Read from the
        /// glyph runs, so it holds for either direction; a ligature counts
        /// toward the character it starts in.
        func characterWidths(in text: String, characters: [Character], utf16Offset: Int) -> [CGFloat] {
            var owner = [Int](repeating: -1, count: text.utf16.count)
            var location = utf16Offset
            for (index, character) in characters.enumerated() {
                let end = min(owner.count, location + character.utf16.count)
                if location < end { for unit in location..<end { owner[unit] = index } }
                location += character.utf16.count
            }
            var widths = [CGFloat](repeating: 0, count: characters.count)
            guard !text.isEmpty else { return widths }
            for run in CTLineGetGlyphRuns(line(text)) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var indices = [CFIndex](repeating: 0, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                for (index, advance) in zip(indices, advances) where owner.indices.contains(index) && owner[index] >= 0 {
                    widths[owner[index]] += advance.width
                }
            }
            return widths
        }
    }

    private struct CacheKey: Equatable {
        let before: String, after: String, width: CGFloat
        /// The fonts the layout was measured with: a font refresh, cache
        /// reset or ConScript preference change measures again.
        let fontGeneration: Int, prefersConScript: Bool
    }
    private static var lastLayout: (key: CacheKey, excerpt: KeyboardPreviewExcerpt)?
    /// How many layouts were measured with real fonts rather than reused.
    private(set) static var measuredLayoutCount = 0

    /// The excerpt the preview shows in `availableWidth` points of text area
    /// (the row minus its padding and actions button), measured with the
    /// preview's own fonts. Main thread only.
    static func excerpt(before: String, after: String, availableWidth: CGFloat) -> KeyboardPreviewExcerpt {
        // Notice downloaded or added fonts before reusing a layout measured without them.
        UnicodeFontSupport.refreshDownloadedFonts()
        let key = CacheKey(before: before, after: after, width: availableWidth,
                           fontGeneration: UnicodeFontSupport.fontGeneration,
                           prefersConScript: UnicodeFontSupport.prefersConScript)
        if let lastLayout, lastLayout.key == key { return lastLayout.excerpt }
        let result = excerpt(before: before, after: after, availableWidth: availableWidth, measurer: Measurer())
        measuredLayoutCount += 1
        lastLayout = (key, result)
        return result
    }

    /// The same layout as measuring each candidate string on its own, using
    /// each side's single shaped line to guess where truncation falls and
    /// confirming that guess with exact measurements.
    static func excerpt(before: String, after: String, availableWidth: CGFloat,
                        measurer: Measurer) -> KeyboardPreviewExcerpt {
        layout(before: before, after: after, availableWidth: availableWidth, measure: measurer.width(of:),
               characterWidths: { measurer.characterWidths(in: $0, characters: $1, utf16Offset: $2) })
    }

    static func excerpt(before: String, after: String, availableWidth: CGFloat,
                        measure: (String) -> CGFloat) -> KeyboardPreviewExcerpt {
        layout(before: before, after: after, availableWidth: availableWidth, measure: measure, characterWidths: nil)
    }

    /// Only the caret's line is shown: earlier and later lines are hidden
    /// context, marked with an ellipsis exactly like horizontal truncation.
    /// The earlier text has priority, as in the original preview row.
    /// `characterWidths`, when given, only speeds up the search; `measure`
    /// alone decides what fits.
    private static func layout(before: String, after: String, availableWidth: CGFloat,
                               measure: (String) -> CGFloat,
                               characterWidths: ((String, [Character], Int) -> [CGFloat])?) -> KeyboardPreviewExcerpt {
        var beforeLine = Substring(before), afterLine = Substring(after)
        var beforeHidden = false, afterHidden = false
        if let index = beforeLine.lastIndex(where: \.isNewline) {
            beforeLine = beforeLine[beforeLine.index(after: index)...]
            beforeHidden = true
        }
        if let index = afterLine.firstIndex(where: \.isNewline) {
            afterLine = afterLine[..<index]
            afterHidden = true
        }
        let total = availableWidth.isFinite ? max(0, availableWidth - caretWidth - fittingSlack) : 0
        let beforeText = String(beforeLine), afterText = String(afterLine)
        let beforeShaped = beforeHidden ? ellipsis + beforeText : beforeText
        let afterShaped = afterHidden ? afterText + ellipsis : afterText
        let beforeWidth = measure(beforeShaped)
        let afterWidth = measure(afterShaped)
        if beforeWidth + afterWidth <= total {
            return KeyboardPreviewExcerpt(before: beforeShaped, after: afterShaped,
                                          beforeTruncated: beforeHidden, afterTruncated: afterHidden)
        }
        let ellipsisWidth = measure(ellipsis)
        let reserve = afterText.isEmpty && !afterHidden ? 0 : min(afterWidth, ellipsisWidth)
        let shownBefore: String
        let beforeTruncated: Bool
        if beforeWidth <= total - reserve {
            shownBefore = beforeShaped
            beforeTruncated = beforeHidden
        } else {
            let characters = Array(beforeText)
            let budget = total - reserve
            let guess = characterWidths.map { widthsIn in
                estimatedCount(widthsIn(beforeShaped, characters, beforeHidden ? ellipsis.utf16.count : 0).reversed(),
                               start: ellipsisWidth, budget: budget)
            }
            let count = largestFitting(characters.count, budget: budget, guess: guess) { n in
                measure(ellipsis + String(characters.suffix(n)))
            }
            shownBefore = count.map { ellipsis + String(characters.suffix($0)) } ?? ""
            beforeTruncated = !characters.isEmpty || beforeHidden
        }
        let remaining = total - (shownBefore.isEmpty ? 0 : measure(shownBefore))
        let shownAfter: String
        let afterTruncated: Bool
        if afterWidth <= remaining {
            shownAfter = afterShaped
            afterTruncated = afterHidden
        } else {
            let characters = Array(afterText)
            let guess = characterWidths.map { widthsIn in
                estimatedCount(widthsIn(afterShaped, characters, 0), start: ellipsisWidth, budget: remaining)
            }
            let count = largestFitting(characters.count, budget: remaining, guess: guess) { n in
                measure(String(characters.prefix(n)) + ellipsis)
            }
            shownAfter = count.map { String(characters.prefix($0)) + ellipsis } ?? ""
            afterTruncated = !characters.isEmpty || afterHidden
        }
        return KeyboardPreviewExcerpt(before: shownBefore, after: shownAfter,
                                      beforeTruncated: beforeTruncated, afterTruncated: afterTruncated)
    }

    /// How many leading `widths` fit in `budget` after `start`.
    private static func estimatedCount<Widths: Sequence>(_ widths: Widths, start: CGFloat, budget: CGFloat) -> Int
    where Widths.Element == CGFloat {
        var count = 0, used = start
        for width in widths {
            guard used + width <= budget else { break }
            used += width
            count += 1
        }
        return count
    }

    /// The largest `n` in 0...limit whose measured width fits, or nil when
    /// not even the bare ellipsis fits. A `guess` near the answer settles it
    /// in two measurements; a poor one only narrows the binary search, so
    /// for widths that grow with `n` the result never depends on it.
    private static func largestFitting(_ limit: Int, budget: CGFloat, guess: Int? = nil,
                                       width: (Int) -> CGFloat) -> Int? {
        guard budget > 0, width(0) <= budget else { return nil }
        var low = 0, high = limit
        if let guess, guess > 0, guess <= limit {
            if width(guess) <= budget {
                if guess == limit || width(guess + 1) > budget { return guess }
                low = guess + 1
            } else {
                high = guess - 1
            }
        }
        while low < high {
            let mid = (low + high + 1) / 2
            if width(mid) <= budget { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

// MARK: Copy Image colors

/// A fixed sRGB color. Copy Image never uses semantic or dynamic colors, so
/// the picture is identical whether the keyboard is light or dark.
struct KeyboardImageRGB: Hashable, Sendable {
    let red: UInt8, green: UInt8, blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) { self.red = red; self.green = green; self.blue = blue }

    /// `0xRRGGBB`.
    init(_ hex: UInt32) {
        self.init(red: UInt8((hex >> 16) & 0xFF), green: UInt8((hex >> 8) & 0xFF), blue: UInt8(hex & 0xFF))
    }

    /// `#RRGGBB`, the stored form; anything else is rejected.
    init?(hexString: String) {
        guard hexString.count == 7, hexString.first == "#",
              hexString.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(hexString.dropFirst(), radix: 16) else { return nil }
        self.init(value)
    }

    /// The nearest 8-bit sRGB value of an already resolved color.
    init(resolving color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) { r = 0; g = 0; b = 0 }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(red: byte(r), green: byte(g), blue: byte(b))
    }

    var hexString: String { String(format: "#%02X%02X%02X", red, green, blue) }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
    var uiColor: UIColor { UIColor(cgColor: cgColor) }

    /// WCAG 2 relative luminance, 0 (black) to 1 (white).
    var relativeLuminance: Double {
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1 to 21.
    static func contrastRatio(_ a: KeyboardImageRGB, _ b: KeyboardImageRGB) -> Double {
        let (l1, l2) = (a.relativeLuminance, b.relativeLuminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    static let black = KeyboardImageRGB(0x000000)
    static let white = KeyboardImageRGB(0xFFFFFF)
}

enum KeyboardImageBackground: Hashable, Sendable {
    /// Every non-glyph pixel has alpha 0.
    case transparent
    case color(KeyboardImageRGB)

    /// Stored as `transparent` or `#RRGGBB`.
    var storedValue: String {
        switch self {
        case .transparent: return "transparent"
        case .color(let rgb): return rgb.hexString
        }
    }

    init?(storedValue: String) {
        if storedValue == "transparent" { self = .transparent }
        else if let rgb = KeyboardImageRGB(hexString: storedValue) { self = .color(rgb) }
        else { return nil }
    }
}

/// The text color and background one Copy Image picture is drawn in.
struct KeyboardImageColors: Hashable, Sendable {
    var text: KeyboardImageRGB
    var background: KeyboardImageBackground

    enum Readability: Equatable {
        case readable
        /// Text and background are the same color: nothing to copy.
        case sameColor
        /// Opaque background below `minimumContrast`: copying still allowed.
        case lowContrast
    }

    static let minimumContrast = 3.0

    var isTransparent: Bool { background == .transparent }

    /// A transparent background is never checked: the destination is unknown.
    var readability: Readability {
        guard case .color(let background) = background else { return .readable }
        if background == text { return .sameColor }
        return KeyboardImageRGB.contrastRatio(text, background) < Self.minimumContrast ? .lowContrast : .readable
    }

    /// The preview-only checkerboard behind transparent areas, contrasting
    /// with the text color rather than the keyboard appearance.
    static func checkerboardTones(forText text: KeyboardImageRGB) -> (KeyboardImageRGB, KeyboardImageRGB) {
        text.relativeLuminance <= 0.5
            ? (KeyboardImageRGB(0xFFFFFF), KeyboardImageRGB(0xE5E5EA))
            : (KeyboardImageRGB(0x2C2C2E), KeyboardImageRGB(0x3A3A3C))
    }
    var checkerboardTones: (KeyboardImageRGB, KeyboardImageRGB) { Self.checkerboardTones(forText: text) }

    /// "White on Transparent", "Red on Blue"…
    var spokenName: String {
        let text = KeyboardImagePalette.name(of: text), background = KeyboardImagePalette.name(of: background)
        return String(localized: "\(text) on \(background)")
    }
}

/// The fixed swatches offered for Custom; no system color picker, which
/// would open outside the keyboard's bounds.
enum KeyboardImagePalette {
    struct Swatch: Hashable, Identifiable {
        let name: String
        let rgb: KeyboardImageRGB
        var id: String { rgb.hexString }
    }

    static let colors: [Swatch] = [
        Swatch(name: String(localized: "Black"), rgb: KeyboardImageRGB(0x000000)),
        Swatch(name: String(localized: "White"), rgb: KeyboardImageRGB(0xFFFFFF)),
        Swatch(name: String(localized: "Gray"), rgb: KeyboardImageRGB(0x8E8E93)),
        Swatch(name: String(localized: "Red"), rgb: KeyboardImageRGB(0xFF3B30)),
        Swatch(name: String(localized: "Orange"), rgb: KeyboardImageRGB(0xFF9500)),
        Swatch(name: String(localized: "Green"), rgb: KeyboardImageRGB(0x34C759)),
        Swatch(name: String(localized: "Blue"), rgb: KeyboardImageRGB(0x007AFF)),
        Swatch(name: String(localized: "Purple"), rgb: KeyboardImageRGB(0xAF52DE)),
    ]

    /// Transparent first, then the palette.
    static let backgrounds: [KeyboardImageBackground] = [.transparent] + colors.map { .color($0.rgb) }

    static func name(of rgb: KeyboardImageRGB) -> String {
        colors.first { $0.rgb == rgb }?.name ?? rgb.hexString
    }

    static func name(of background: KeyboardImageBackground) -> String {
        switch background {
        case .transparent: return String(localized: "Transparent")
        case .color(let rgb): return name(of: rgb)
        }
    }
}

enum KeyboardImageColorPreset: String, CaseIterable, Identifiable, Sendable {
    case blackOnWhite, blackOnClear, whiteOnBlack, whiteOnClear, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blackOnWhite: return String(localized: "Black on White")
        case .blackOnClear: return String(localized: "Black on Transparent")
        case .whiteOnBlack: return String(localized: "White on Black")
        case .whiteOnClear: return String(localized: "White on Transparent")
        case .custom: return String(localized: "Custom")
        }
    }

    var accessibilityLabel: String { self == .custom ? String(localized: "Custom colors") : label }

    /// Nil for Custom, whose colors are the user's.
    var fixedColors: KeyboardImageColors? {
        switch self {
        case .blackOnWhite: return KeyboardImageColors(text: .black, background: .color(.white))
        case .blackOnClear: return KeyboardImageColors(text: .black, background: .transparent)
        case .whiteOnBlack: return KeyboardImageColors(text: .white, background: .color(.black))
        case .whiteOnClear: return KeyboardImageColors(text: .white, background: .transparent)
        case .custom: return nil
        }
    }
}

/// The remembered Copy Image choice: a preset id, the two Custom colors
/// and the scale. They travel together, so the scale is stored, shared and
/// imported exactly like the colors.
struct KeyboardImageColorChoice: Equatable, Sendable {
    var preset: KeyboardImageColorPreset = .blackOnWhite
    var customText: KeyboardImageRGB = .black
    var customBackground: KeyboardImageBackground = .color(.white)
    var scale: KeyboardImageScale = .default

    static let `default` = KeyboardImageColorChoice()

    var colors: KeyboardImageColors {
        preset.fixedColors ?? KeyboardImageColors(text: customText, background: customBackground)
    }
}

/// Remembers the choice in the keyboard's own defaults. Only the preset id,
/// two colors and the scale are ever written; never any text. Needs neither
/// Full Access nor an App Group.
enum KeyboardImageColorStore {
    static let presetKey = "copyImage.colors.preset"
    static let customTextKey = "copyImage.colors.customText"
    static let customBackgroundKey = "copyImage.colors.customBackground"
    static let scaleKey = "copyImage.scale"
    static let keys = [presetKey, customTextKey, customBackgroundKey, scaleKey]

    static func load(from defaults: UserDefaults = .standard) -> KeyboardImageColorChoice {
        var choice = KeyboardImageColorChoice.default
        if let raw = defaults.string(forKey: presetKey), let preset = KeyboardImageColorPreset(rawValue: raw) {
            choice.preset = preset
        }
        if let raw = defaults.string(forKey: customTextKey), let text = KeyboardImageRGB(hexString: raw) {
            choice.customText = text
        }
        if let raw = defaults.string(forKey: customBackgroundKey), let background = KeyboardImageBackground(storedValue: raw) {
            choice.customBackground = background
        }
        if let raw = defaults.object(forKey: scaleKey) as? Int, let scale = KeyboardImageScale(rawValue: raw) {
            choice.scale = scale
        }
        return choice
    }

    static func save(_ choice: KeyboardImageColorChoice, to defaults: UserDefaults = .standard) {
        defaults.set(choice.preset.rawValue, forKey: presetKey)
        defaults.set(choice.customText.hexString, forKey: customTextKey)
        defaults.set(choice.customBackground.storedValue, forKey: customBackgroundKey)
        defaults.set(choice.scale.rawValue, forKey: scaleKey)
    }

    /// The revision of the shared choice this keyboard last adopted or published.
    static let sharedRevisionKey = "copyImage.colors.sharedRevision"

    /// On panel open. A shared choice with a revision this keyboard hasn't
    /// seen (the app's import or undo) replaces the local one; this works
    /// without Full Access. With Full Access and nothing shared yet, the local
    /// choice is published once. Never per keystroke.
    static func load(from defaults: UserDefaults = .standard, shared: ImageColorSettings, hasFullAccess: Bool) -> KeyboardImageColorChoice {
        if let stored = shared.load() {
            if stored.revision != defaults.string(forKey: sharedRevisionKey), let choice = KeyboardImageColorChoice(stored.value) {
                save(choice, to: defaults)
                defaults.set(stored.revision, forKey: sharedRevisionKey)
            }
        } else if hasFullAccess, shared.isUnpublished() {
            publish(load(from: defaults), to: defaults, shared: shared)
        }
        return load(from: defaults)
    }

    /// Always saved locally; shared too when the keyboard has Full Access.
    /// A busy or failed shared write keeps the choice local.
    static func save(_ choice: KeyboardImageColorChoice, to defaults: UserDefaults = .standard, shared: ImageColorSettings, hasFullAccess: Bool) {
        save(choice, to: defaults)
        if hasFullAccess { publish(choice, to: defaults, shared: shared) }
    }

    private static func publish(_ choice: KeyboardImageColorChoice, to defaults: UserDefaults, shared: ImageColorSettings) {
        if let stored = try? shared.save(choice.sharedValue) { defaults.set(stored.revision, forKey: sharedRevisionKey) }
    }
}

extension KeyboardImageColorChoice {
    /// nil when the shared preset, colors or scale aren't ones this build knows.
    init?(_ value: ImageColorSettings.Value) {
        guard let preset = KeyboardImageColorPreset(rawValue: value.preset), let text = KeyboardImageRGB(hexString: value.customText),
              let background = KeyboardImageBackground(storedValue: value.customBackground),
              let scale = KeyboardImageScale(rawValue: value.scale) else { return nil }
        self.init(preset: preset, customText: text, customBackground: background, scale: scale)
    }

    var sharedValue: ImageColorSettings.Value {
        ImageColorSettings.Value(preset: preset.rawValue, customText: customText.hexString, customBackground: customBackground.storedValue,
                                 scale: scale.rawValue)
    }
}

/// Copy Image color strings, kept together so wording is easy to change.
enum KeyboardImageColorCopy {
    static var sameColor: String { String(localized: "Choose different text and background colors.") }
    static var lowContrast: String { String(localized: "This text may be hard to read.") }
    static var transparentNote: String {
        String(localized: "Transparent areas show the background where you paste. The checkerboard isn’t copied.")
    }
    static var colorGlyphNote: String { String(localized: "Emoji keep their original colors.") }
    static var groupLabel: String { String(localized: "Image colors") }
    static var textLine: String { String(localized: "Text") }
    static var backgroundLine: String { String(localized: "Background") }

    static func caption(_ choice: KeyboardImageColorChoice) -> String {
        String(localized: "Colors · \(choice.preset.label)")
    }

    static var sizeGroupLabel: String { String(localized: "Image size") }

    /// The size caption when there is no size to show.
    static var sizeTitle: String { String(localized: "Size") }
    /// Appended when the chosen scale had to be lowered to fit the canvas limits.
    static var reducedNote: String { String(localized: " · reduced to fit") }

    /// "Size · 1,260 × 132 pixels": the size actually copied, grouped for the
    /// locale; "Size" alone when there is none.
    static func sizeCaption(_ size: KeyboardImagePixelSize?, locale: Locale = .current) -> String {
        guard let size else { return sizeTitle }
        let width = size.width.formatted(.number.locale(locale)), height = size.height.formatted(.number.locale(locale))
        return String(localized: "Size · \(width) × \(height) pixels") + (size.isReduced ? reducedNote : "")
    }

    /// The caption's VoiceOver label, "Size, 1,260 by 132 pixels".
    static func sizeCaptionAccessibilityLabel(_ size: KeyboardImagePixelSize?, locale: Locale = .current) -> String {
        guard let size else { return sizeTitle }
        return String(localized: "Size, \(pixelsValue(size, locale: locale))") + (size.isReduced ? reducedNote : "")
    }

    /// The selected chip's VoiceOver value, "318 by 114 pixels".
    static func pixelsValue(_ size: KeyboardImagePixelSize, locale: Locale = .current) -> String {
        let width = size.width.formatted(.number.locale(locale)), height = size.height.formatted(.number.locale(locale))
        return String(localized: "\(width) by \(height) pixels")
    }

    /// The chip's VoiceOver label, "2 times scale".
    static func scaleLabel(_ scale: KeyboardImageScale) -> String {
        String(localized: "\(scale.rawValue) times scale")
    }

    /// The caution shown in place of the colors caption, if any.
    static func readabilityNote(_ readability: KeyboardImageColors.Readability) -> String? {
        switch readability {
        case .readable: return nil
        case .sameColor: return sameColor
        case .lowContrast: return lowContrast
        }
    }

    /// Sentences appended to the panel's explanation paragraph.
    static func explanationSuffix(colors: KeyboardImageColors, containsColorGlyphs: Bool) -> String {
        var sentences: [String] = []
        if colors.isTransparent { sentences.append(transparentNote) }
        if containsColorGlyphs { sentences.append(colorGlyphNote) }
        return sentences.map { " " + $0 }.joined()
    }
}

/// A frozen, rendered picture of the visible preview text.
struct KeyboardPreviewImage: Equatable {
    let png: Data
    let pixelWidth: Int
    let pixelHeight: Int
    /// Logical size in points; pixels are `scale` times this.
    let pointSize: CGSize
    /// The pixels per point drawn at, and the PNG's DPI over 72.
    let scale: CGFloat
    /// The scale chosen; `scale` is lower only when this one exceeds the canvas limits.
    let requestedScale: KeyboardImageScale
    /// The logical canvas in points, the same at every scale.
    let canvasSize: CGSize
    /// Plain-text equivalent of exactly the rendered text.
    let visibleText: String
    /// The colors it was drawn in. Transparent pictures carry alpha.
    let colors: KeyboardImageColors
    /// Whether any drawn glyph comes from a color font, such as emoji.
    let containsColorGlyphs: Bool

    /// The thumbnail's accessibility value: the visible text, then the colors.
    var accessibilityValue: String { visibleText + ", " + colors.spokenName }
}

/// Draws the preview excerpt as a PNG: the same font runs, size and
/// caret-split shaping as the row, without caret, controls, glass or border.
/// Opaque backgrounds give an opaque PNG; a transparent one draws the glyphs
/// straight onto a clear premultiplied canvas, so edges carry the text color
/// at partial alpha and never a keyed-out fringe.
@MainActor
enum KeyboardPreviewImageRenderer {
    enum Failure: Error, Equatable {
        /// No visible ink: nothing honest to copy.
        case empty
        /// The bounded canvas for extension memory would be exceeded.
        case tooLarge
        case encodingFailed
    }

    /// Today's scale when none is chosen.
    static let scale: CGFloat = KeyboardImageScale.default.factor
    static let padding: CGFloat = 8
    static let maximumPixelWidth = KeyboardImageCanvas.maximumPixelWidth
    static let maximumPixelHeight = KeyboardImageCanvas.maximumPixelHeight
    static let maximumPixelCount = KeyboardImageCanvas.maximumPixelCount

    /// - Parameters:
    ///   - availableWidth: the text area the excerpt was laid out in; ink
    ///     outside it is clipped exactly as the row clips it.
    ///   - visibleHeight: the row's height; each text is centered in it.
    static func render(_ excerpt: KeyboardPreviewExcerpt, availableWidth: CGFloat, visibleHeight: CGFloat,
                       foreground: UIColor, background: UIColor, scale: KeyboardImageScale = .default,
                       font: (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) -> Result<KeyboardPreviewImage, Failure> {
        render(excerpt, availableWidth: availableWidth, visibleHeight: visibleHeight,
               colors: KeyboardImageColors(text: KeyboardImageRGB(resolving: foreground),
                                           background: .color(KeyboardImageRGB(resolving: background))),
               scale: scale, font: font)
    }

    /// `scale` changes only the pixel count and DPI: the canvas, text runs
    /// and clipping are laid out in points, identically at every scale.
    static func render(_ excerpt: KeyboardPreviewExcerpt, availableWidth: CGFloat, visibleHeight: CGFloat,
                       colors: KeyboardImageColors, scale requested: KeyboardImageScale = .default,
                       font: (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) -> Result<KeyboardPreviewImage, Failure> {
        guard excerpt.hasVisibleCharacters else { return .failure(.empty) }
        let foreground = colors.text.uiColor
        struct Run {
            let line: CTLine; let x: CGFloat; let baseline: CGFloat; let width: CGFloat
            let ascent: CGFloat; let descent: CGFloat; let leading: CGFloat
        }
        var runs: [Run] = []
        var x: CGFloat = 0
        let texts = excerpt.isSingleLine ? [excerpt.before + excerpt.after] : [excerpt.before, excerpt.after]
        for (index, text) in texts.enumerated() {
            if index == 1 { x += KeyboardTextPreviewLayout.caretWidth }
            guard !text.isEmpty else { continue }
            let line = CTLineCreateWithAttributedString(
                KeyboardTextPreviewLayout.attributedText(text, font: font, foreground: foreground))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            // The row centers each text's line box vertically on its own. Like
            // SwiftUI's, the box is ascent above the baseline and descent plus
            // leading below it.
            runs.append(Run(line: line, x: x, baseline: -(ascent - descent - leading) / 2, width: width,
                            ascent: ascent, descent: descent, leading: leading))
            x += width
        }
        let window = CGRect(x: 0, y: -max(1, visibleHeight) / 2,
                            width: max(0, availableWidth), height: max(1, visibleHeight))
        var content = CGRect.null
        var ink = CGRect.null
        for run in runs {
            let typographic = CGRect(x: run.x, y: run.baseline - run.descent - run.leading, width: run.width,
                                     height: run.ascent + run.descent + run.leading)
            // Glyph image bounds cover bitmap emoji; outline bounds cover marks.
            for bounds in [CTLineGetImageBounds(run.line, nil), CTLineGetBoundsWithOptions(run.line, .useGlyphPathBounds)]
            where !bounds.isNull && bounds.width > 0 && bounds.height > 0 {
                ink = ink.union(bounds.offsetBy(dx: run.x, dy: run.baseline))
            }
            content = content.union(typographic)
        }
        let visibleInk = ink.intersection(window)
        guard !visibleInk.isNull, visibleInk.width > 0, visibleInk.height > 0 else { return .failure(.empty) }
        content = content.union(ink).intersection(window)
        let canvas = content.insetBy(dx: -padding, dy: -padding)
        // The same sizes a picker shows: a scale over the limits steps down.
        guard let size = KeyboardImageCanvas.pixelSize(canvas: canvas.size, scale: requested) else { return .failure(.tooLarge) }
        let pixelWidth = size.width, pixelHeight = size.height, scale = size.scale.factor
        let alphaInfo: CGImageAlphaInfo = colors.isTransparent ? .premultipliedLast : .noneSkipLast
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: alphaInfo.rawValue)
        else { return .failure(.encodingFailed) }
        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        switch colors.background {
        case .transparent:
            context.clear(bounds)
        case .color(let background):
            context.setFillColor(background.cgColor)
            context.fill(bounds)
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -canvas.minX, y: -canvas.minY)
        context.clip(to: content)
        context.textMatrix = .identity
        for run in runs {
            context.textPosition = CGPoint(x: run.x, y: run.baseline)
            CTLineDraw(run.line, context)
        }
        guard let image = context.makeImage() else { return .failure(.encodingFailed) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return .failure(.encodingFailed) }
        let dpi = size.scale.dpi
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth as String: dpi, kCGImagePropertyDPIHeight as String: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return .failure(.encodingFailed) }
        return .success(KeyboardPreviewImage(png: data as Data, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            pointSize: CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale),
            scale: scale, requestedScale: requested, canvasSize: canvas.size, visibleText: excerpt.visibleText, colors: colors,
            containsColorGlyphs: runs.contains { usesColorGlyphs($0.line) }))
    }

    /// Whether CoreText drew any of `line` from a color font (emoji and other
    /// color glyphs keep their own colors in every preset).
    static func usesColorGlyphs(_ line: CTLine) -> Bool {
        (CTLineGetGlyphRuns(line) as! [CTRun]).contains { run in
            guard CTRunGetGlyphCount(run) > 0,
                  let attributes = CTRunGetAttributes(run) as? [CFString: Any],
                  let value = attributes[kCTFontAttributeName] else { return false }
            let font = value as! CTFont
            return CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs)
        }
    }
}

/// One Copy Image panel: a frozen excerpt and image, and where copying is.
struct KeyboardPreviewImageExport: Equatable {
    enum Phase: Equatable {
        case ready
        /// Nothing renderable is visible; Copy Image stays disabled.
        case empty
        /// The excerpt could not be rendered faithfully; nothing is copied.
        case renderFailed
        /// Full Access is off. Apple documents open access as required for a
        /// keyboard extension to use the general pasteboard; typing still works.
        case fullAccessRequired
        case copying
        case copied
        case copyFailed
    }

    let id: UUID
    let excerpt: KeyboardPreviewExcerpt
    /// The frozen row geometry the excerpt was laid out and clipped in.
    let availableWidth: CGFloat
    let visibleHeight: CGFloat
    let colors: KeyboardImageColors
    /// The chosen scale; the picture may use a lower one (see `KeyboardImageCanvas`).
    let scale: KeyboardImageScale
    let image: KeyboardPreviewImage?
    var phase: Phase

    @MainActor
    static func prepare(excerpt: KeyboardPreviewExcerpt, availableWidth: CGFloat, visibleHeight: CGFloat,
                        foreground: UIColor, background: UIColor, hasFullAccess: Bool,
                        font: (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) -> KeyboardPreviewImageExport {
        prepare(excerpt: excerpt, availableWidth: availableWidth, visibleHeight: visibleHeight,
                colors: KeyboardImageColors(text: KeyboardImageRGB(resolving: foreground),
                                            background: .color(KeyboardImageRGB(resolving: background))),
                hasFullAccess: hasFullAccess, font: font)
    }

    @MainActor
    static func prepare(excerpt: KeyboardPreviewExcerpt, availableWidth: CGFloat, visibleHeight: CGFloat,
                        colors: KeyboardImageColors, scale: KeyboardImageScale = .default, hasFullAccess: Bool, id: UUID = UUID(),
                        font: (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) -> KeyboardPreviewImageExport {
        let image: KeyboardPreviewImage?
        let phase: Phase
        switch KeyboardPreviewImageRenderer.render(excerpt, availableWidth: availableWidth, visibleHeight: visibleHeight,
                                                   colors: colors, scale: scale, font: font) {
        case .success(let rendered): image = rendered; phase = hasFullAccess ? .ready : .fullAccessRequired
        case .failure(.empty): image = nil; phase = .empty
        case .failure: image = nil; phase = .renderFailed
        }
        return KeyboardPreviewImageExport(id: id, excerpt: excerpt, availableWidth: availableWidth,
                                          visibleHeight: visibleHeight, colors: colors, scale: scale, image: image, phase: phase)
    }

    /// The same frozen excerpt and panel drawn in other colors or at another
    /// scale (nil keeps this one). The host is never read again; a Success
    /// state returns to Ready because the copied picture no longer matches
    /// the thumbnail. Nil while copying.
    @MainActor
    func recolored(_ colors: KeyboardImageColors, scale: KeyboardImageScale? = nil, hasFullAccess: Bool,
                   font: (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) -> KeyboardPreviewImageExport? {
        guard phase != .copying else { return nil }
        return Self.prepare(excerpt: excerpt, availableWidth: availableWidth, visibleHeight: visibleHeight,
                            colors: colors, scale: scale ?? self.scale, hasFullAccess: hasFullAccess, id: id, font: font)
    }

    /// The pixel size the picture would be copied at for `scale`, without
    /// rendering ("1260 × 132 px"); exactly the rendered size for the
    /// current scale. Nil when there is no picture.
    func pixelSize(for scale: KeyboardImageScale) -> KeyboardImagePixelSize? {
        image.flatMap { KeyboardImageCanvas.pixelSize(canvas: $0.canvasSize, scale: scale) }
    }

    /// The panel's thumbnail: the picture itself at 3× or more, otherwise the
    /// same canvas drawn again at 3× so a lower copy scale never blurs it
    /// (the layout is identical at every scale). Nil when there is no picture.
    @MainActor
    func thumbnail(font: (String) -> UIFont = KeyboardTextPreviewLayout.font(for:)) -> UIImage? {
        guard let image else { return nil }
        var source = image
        if image.scale < KeyboardImageScale.default.factor,
           case .success(let sharper) = KeyboardPreviewImageRenderer.render(excerpt, availableWidth: availableWidth,
                                                                            visibleHeight: visibleHeight, colors: colors,
                                                                            scale: .default, font: font) {
            source = sharper
        }
        return UIImage(data: source.png, scale: source.scale)
    }

    /// Custom colors that match exactly leave nothing to see.
    var readability: KeyboardImageColors.Readability { colors.readability }

    var canCopy: Bool {
        guard image != nil, readability != .sameColor else { return false }
        switch phase {
        case .ready, .copyFailed: return true
        default: return false
        }
    }
}

/// Places a rendered image on a pasteboard only on an explicit request. The
/// pasteboard is never read; `changeCount` alone confirms the write.
enum KeyboardPreviewClipboard {
    enum Outcome: Equatable { case copied, fullAccessRequired, unavailable }

    static func write(_ image: KeyboardPreviewImage, to pasteboard: UIPasteboard, hasFullAccess: Bool) -> Outcome {
        guard hasFullAccess else { return .fullAccessRequired }
        let before = pasteboard.changeCount
        pasteboard.setData(image.png, forPasteboardType: UTType.png.identifier)
        return pasteboard.changeCount != before ? .copied : .unavailable
    }
}
#endif
