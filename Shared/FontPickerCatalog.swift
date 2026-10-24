import Foundation
#if canImport(CoreText)
import CoreText
#endif

// The Preferred Font picker's logic (design/font-picker/design.md), kept
// apart from SwiftUI so it can be tested: its copy, which faces are listed
// and in which section, family grouping and style order, multi-word search,
// the sections a query and the support results build, and the order those
// results settle into once checking ends. Nothing here loads a font.

/// The picker's copy (design/font-picker §8, revised by the copywriter):
/// each string defined once here, counts as one sentence each.
enum FontPickerCopy {
    static let searchPrompt = "Search family or style"
    static let selected = "Selected"
    static let systemFonts = "System Fonts"
    static let otherDeviceFonts = "Other Device Fonts"
    static let regular = "Regular"
    static let appOnly = "App Only"
    static let appOnlyAccessibility = "App only, not on the keyboard"
    static let appOnlyFooter = "These fonts are available in the app, but not the keyboard. The keyboard uses the next matching rule or its default fonts."
    static let keyboardUnverified = "Keyboard Unverified"
    static let keyboardUnverifiedAccessibility = "Keyboard unverified"
    static let keyboardUnverifiedFooter = "Available in the app. Keyboard availability hasn’t been confirmed."
    static let cannotDisplayCharacter = "Can’t display this character"
    static let unsupportedCharacterFooter = "These fonts can’t display this character."
    static let unsupportedRangeFooter = "These fonts can’t display any of these characters."

    /// "{n} styles": a family of one face shows its style name instead.
    static func styles(_ count: Int) -> String { "\(count.formatted()) styles" }

    /// While searching, when only some of a family's faces match.
    static func styles(_ matching: Int, of total: Int) -> String { "\(matching.formatted()) of \(total.formatted()) styles" }

    /// VoiceOver, on a family row holding the chosen face.
    static func styleSelected(_ style: String) -> String { style + " selected" }

    static func checking(_ checked: Int, of total: Int) -> String { "Checking Fonts… \(checked.formatted()) of \(total.formatted())" }

    static func checkingAccessibility(_ checked: Int, of total: Int) -> String { "Checking fonts, \(checked.formatted()) of \(total.formatted())" }

    static func noMatches(_ query: String) -> String { "No fonts match “" + query + "”." }

    /// The VoiceOver result count after typing stops; family rows count as font families.
    static func resultCount(_ families: Int) -> String {
        switch families {
        case 0: return "No fonts"
        case 1: return "1 font family"
        default: return "\(families.formatted()) font families"
        }
    }
}

/// The picker's font sections, in display order.
enum FontPickerSection: Int, CaseIterable, Comparable, Sendable {
    case yours, google, preview, system, other

    var title: String {
        switch self {
        case .yours: return "Your Fonts"
        case .google: return "Google Fonts"
        case .preview: return "Preview Fonts"
        case .system: return FontPickerCopy.systemFonts
        case .other: return FontPickerCopy.otherDeviceFonts
        }
    }

    var identifier: String {
        switch self {
        case .yours: return "yourFonts"
        case .google: return "googleFonts"
        case .preview: return "previewFonts"
        case .system: return "systemFonts"
        case .other: return "otherDeviceFonts"
        }
    }

    /// `isPack`: a downloaded face from a Uniboard preview pack (`pack:` file).
    init(source: FontSource, isPack: Bool) {
        switch source {
        case .imported, .installed: self = .yours
        case .included: self = .preview
        case .downloaded: self = isPack ? .preview : .google
        case .system: self = .system
        case .available: self = .other
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Private system UI faces ("."-prefixed, such as `.SFUI-Regular`) and
    /// LastResort, which draws a placeholder for every code point, never show.
    static func isListed(postScriptName: String, family: String) -> Bool {
        !postScriptName.hasPrefix(".") && !family.hasPrefix(".") && postScriptName != "LastResort"
    }

    /// iOS's own font folder: /System/Library/Fonts on a device, under the
    /// runtime's RuntimeRoot in the Simulator.
    static func isSystemFontFile(_ path: String) -> Bool {
        path.hasPrefix("/System/Library/Fonts/") || path.contains("/RuntimeRoot/System/Library/Fonts/")
    }
}

/// Whether the keyboard can draw a face, as far as anything confirms it.
enum KeyboardFontStatus: Hashable, Sendable {
    /// A file in the App Group or a system font, or confirmed by the keyboard.
    case available
    /// No evidence either way: "Keyboard Unverified". Never App Only.
    case unverified
    /// The keyboard confirmed it can't open it: "App Only".
    case appOnly

    var tag: String? {
        switch self {
        case .available: return nil
        case .unverified: return FontPickerCopy.keyboardUnverified
        case .appOnly: return FontPickerCopy.appOnly
        }
    }

    /// VoiceOver text for the tag.
    var accessibilityText: String? {
        switch self {
        case .available: return nil
        case .unverified: return FontPickerCopy.keyboardUnverifiedAccessibility
        case .appOnly: return FontPickerCopy.appOnlyAccessibility
        }
    }

    /// The footer of a section with at least one row tagged this way.
    var footer: String? {
        switch self {
        case .available: return nil
        case .unverified: return FontPickerCopy.keyboardUnverifiedFooter
        case .appOnly: return FontPickerCopy.appOnlyFooter
        }
    }
}

/// The PostScript names the keyboard process could open, recorded by the
/// keyboard each time it appears, with the iOS build it ran on. Only the
/// same iOS build counts as evidence; with none, process faces stay unverified.
struct KeyboardFontEvidence: Equatable, Sendable {
    static let filename = "keyboard-fonts-v1.json"
    static let maximumPayloadBytes = 4 * 1024 * 1024
    let systemVersion: String
    let postScriptNames: Set<String>

    init(systemVersion: String, postScriptNames: [String]) {
        self.systemVersion = systemVersion
        self.postScriptNames = Set(postScriptNames.filter { !$0.hasPrefix(".") })
    }

    private struct Payload: Codable {
        var schemaVersion = 1
        let systemVersion: String
        let postScriptNames: [String]
    }

    /// Deterministic: sorted names and keys.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Payload(systemVersion: systemVersion, postScriptNames: postScriptNames.sorted())),
              data.count <= Self.maximumPayloadBytes else { return nil }
        return data
    }

    /// Nil when empty, oversized, malformed or of an unknown schema.
    static func decode(_ data: Data) -> KeyboardFontEvidence? {
        guard !data.isEmpty, data.count <= maximumPayloadBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.schemaVersion == 1,
              !payload.systemVersion.isEmpty else { return nil }
        return KeyboardFontEvidence(systemVersion: payload.systemVersion, postScriptNames: payload.postScriptNames)
    }

    /// Faces from files in the App Group or the app bundle, and iOS's own
    /// /System/Library/Fonts, are always available. Installed and other device
    /// faces need this evidence from the current iOS build; without it they
    /// stay unverified, and a name it lacks is App Only.
    static func status(source: FontSource, postScriptName: String, evidence: KeyboardFontEvidence?, systemVersion: String) -> KeyboardFontStatus {
        switch source {
        case .imported, .downloaded, .included, .system: return .available
        case .installed, .available:
            guard let evidence, evidence.systemVersion == systemVersion else { return .unverified }
            return evidence.postScriptNames.contains(postScriptName) ? .available : .appOnly
        }
    }
}

/// Reads and writes `KeyboardFontEvidence` in the App Group root. Only the
/// keyboard writes, and only when something changed.
struct KeyboardFontEvidenceStore {
    typealias Reader = (URL) throws -> Data
    typealias Writer = (Data, URL) throws -> Void
    /// The App Group root, beside (not inside) the configuration generations:
    /// this is a device fact, never exported or imported.
    static let appGroup = KeyboardFontEvidenceStore(root: {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)
    })
    let root: () -> URL?
    var read: Reader = { try Data(contentsOf: $0) }
    var write: Writer = { try $0.write(to: $1, options: [.atomic]) }

    private var url: URL? {
        guard let root = root(), root.isFileURL else { return nil }
        return root.appendingPathComponent(KeyboardFontEvidence.filename)
    }

    func load() -> KeyboardFontEvidence? {
        guard let url, let data = try? read(url) else { return nil }
        return KeyboardFontEvidence.decode(data)
    }

    /// True when `evidence` was written; false when unchanged or not writable.
    @discardableResult func record(_ evidence: KeyboardFontEvidence) -> Bool {
        guard let url, load() != evidence, let data = evidence.encoded() else { return false }
        do {
            try write(data, url)
            return true
        } catch {
            return false
        }
    }
}

/// Weight (100–900), width (percent, 100 normal) and slope of a face, for
/// the style order. Each comes from a variation instance if set, else the
/// font's traits, else its style name.
struct FontStyleTraits: Equatable, Sendable {
    var weight: Int
    var width: Double
    var italic: Bool

    /// CoreText's weight trait (−1…1) at the nearest CSS weight.
    static func weight(trait: Double) -> Int {
        let table: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return table.min { abs($0.0 - trait) < abs($1.0 - trait) }!.1
    }

    /// CoreText's width trait (−1…1, 0 normal) as a percentage.
    static func width(trait: Double) -> Double {
        abs(trait) < 0.01 ? 100 : min(200, max(50, 100 + trait * 100))
    }

    private static let weightWords: [(String, Int)] = [
        ("hairline", 100), ("thin", 100), ("extralight", 200), ("ultralight", 200), ("light", 300),
        ("semibold", 600), ("demibold", 600), ("extrabold", 800), ("ultrabold", 800), ("heavy", 800),
        ("extrablack", 900), ("ultrablack", 900), ("black", 900), ("bold", 700), ("medium", 500),
    ]
    private static let widthWords: [(String, Double)] = [
        ("ultracondensed", 50), ("extracondensed", 62.5), ("semicondensed", 87.5), ("condensed", 75),
        ("compressed", 62.5), ("narrow", 75), ("ultraexpanded", 200), ("extraexpanded", 150),
        ("semiexpanded", 112.5), ("expanded", 125), ("extended", 125), ("wide", 125),
    ]

    /// From a style name alone ("Bold Condensed Italic"); words not found mean normal.
    static func named(_ style: String) -> FontStyleTraits {
        let compact = style.lowercased().filter { $0.isLetter }
        return FontStyleTraits(weight: weightWords.first { compact.contains($0.0) }?.1 ?? 400,
                               width: widthWords.first { compact.contains($0.0) }?.1 ?? 100,
                               italic: compact.contains("italic") || compact.contains("oblique"))
    }

    /// `variations` by OpenType tag (`wght`, `wdth`, `ital`, `slnt`); the traits are CoreText's.
    static func resolve(style: String, variations: [String: Double], weightTrait: Double?, widthTrait: Double?, italicTrait: Bool) -> FontStyleTraits {
        let fromName = Self.named(style)
        let resolvedWeight = variations["wght"].map { Int(min(1000, max(1, $0)).rounded()) } ?? weightTrait.map(Self.weight(trait:)) ?? fromName.weight
        let resolvedWidth = variations["wdth"] ?? widthTrait.map(Self.width(trait:)) ?? fromName.width
        let italic = italicTrait || (variations["ital"] ?? 0) >= 0.5 || (variations["slnt"] ?? 0) != 0 || fromName.italic
        return FontStyleTraits(weight: resolvedWeight, width: resolvedWidth, italic: italic)
    }
}

/// One listed face, with everything the list needs precomputed.
struct FontPickerFace: Identifiable, Equatable, Sendable {
    let id: String
    let family: String
    let style: String
    let postScriptName: String
    let section: FontPickerSection
    let traits: FontStyleTraits
    let keyboard: KeyboardFontStatus
    /// Folded family, style and PostScript name, for search.
    let searchKey: String

    init(id: String, family: String, style: String, postScriptName: String, section: FontPickerSection,
         traits: FontStyleTraits, keyboard: KeyboardFontStatus = .available) {
        self.id = id
        self.family = family
        self.style = style
        self.postScriptName = postScriptName
        self.section = section
        self.traits = traits
        self.keyboard = keyboard
        searchKey = FontPickerQuery.fold(family + "\n" + style + "\n" + postScriptName)
    }

    /// "Regular" when the font names no style.
    var styleName: String { style.isEmpty ? FontPickerCopy.regular : style }

    /// Width (normal first, then narrower → wider), weight, upright before italic.
    static func styleOrder(_ lhs: FontPickerFace, _ rhs: FontPickerFace) -> Bool {
        func key(_ face: FontPickerFace) -> (Int, Double, Int, Int) {
            (face.traits.width == 100 ? 0 : 1, face.traits.width, face.traits.weight, face.traits.italic ? 1 : 0)
        }
        let (left, right) = (key(lhs), key(rhs))
        if left != right { return left < right }
        return (lhs.styleName, lhs.postScriptName, lhs.id) < (rhs.styleName, rhs.postScriptName, rhs.id)
    }
}

/// The faces of one family in one section, in style order.
struct FontPickerFamily: Identifiable, Equatable, Sendable {
    let section: FontPickerSection
    let name: String
    let faces: [FontPickerFace]
    let folded: String

    init(section: FontPickerSection, name: String, faces: [FontPickerFace]) {
        self.section = section
        self.name = name
        self.faces = faces.sorted(by: FontPickerFace.styleOrder)
        folded = FontPickerQuery.fold(name)
    }

    var id: String { "\(section.rawValue)|\(name)" }

    /// The lowest (normal width ? 0 : 1, italic ? 1 : 0, |weight − 400|,
    /// weight): normal width, then upright, then the weight nearest 400 (the
    /// lighter on a tie). An italics-only family shows Regular Italic, not Thin.
    var representative: FontPickerFace {
        func key(_ face: FontPickerFace) -> (Int, Int, Int, Int) {
            (face.traits.width == 100 ? 0 : 1, face.traits.italic ? 1 : 0, abs(face.traits.weight - 400), face.traits.weight)
        }
        return faces.min { key($0) < key($1) }!
    }

    /// The tag on the family row: when every face shares one; otherwise
    /// each style row shows its own.
    var keyboard: KeyboardFontStatus {
        Set(faces.map(\.keyboard)).count == 1 ? faces[0].keyboard : .available
    }

    /// Style names used by more than one face, whose rows add the PostScript name.
    var repeatedStyleNames: Set<String> {
        var seen = Set<String>(), repeated = Set<String>()
        for face in faces where !seen.insert(face.styleName).inserted { repeated.insert(face.styleName) }
        return repeated
    }

    /// Families by (section, exact family name): sections in order, names
    /// alphabetical (localized, case-insensitive) within each.
    static func grouping(_ faces: [FontPickerFace]) -> [FontPickerFamily] {
        let grouped = Dictionary(grouping: faces) { FamilyKey(section: $0.section, name: $0.family) }
        return grouped.map { FontPickerFamily(section: $0.key.section, name: $0.key.name, faces: $0.value) }
            .sorted(by: alphabetical)
    }

    private struct FamilyKey: Hashable {
        let section: FontPickerSection
        let name: String
    }

    static func alphabetical(_ lhs: FontPickerFamily, _ rhs: FontPickerFamily) -> Bool {
        if lhs.section != rhs.section { return lhs.section < rhs.section }
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? lhs.name < rhs.name : order == .orderedAscending
    }
}

/// A query split on whitespace; every word must appear in a face's family,
/// style or PostScript name, ignoring case and diacritics.
struct FontPickerQuery: Equatable, Sendable {
    let words: [String]

    init(_ text: String) {
        words = Self.fold(text).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var isEmpty: Bool { words.isEmpty }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    func matches(_ key: String) -> Bool { words.allSatisfy { key.contains($0) } }
}

/// Whether a face can draw what the picker is for.
enum FontPickerSupport: Equatable, Sendable {
    case checking
    /// Verified to draw the code point.
    case supported
    /// Not verified either way; never counted as unsupported.
    case unknown
    /// Verified unable to draw the code point.
    case unsupported
    /// Valid scalars of the range or block the face maps.
    case coverage(Int)
    /// The face's file couldn't be loaded; never counted as unsupported.
    case missing

    /// Verified unable: dimmed and disabled in place.
    var isUnable: Bool { self == .unsupported || self == .coverage(0) }

    var isUsable: Bool {
        switch self {
        case .supported: return true
        case let .coverage(count): return count > 0
        case .checking, .unknown, .unsupported, .missing: return false
        }
    }
}

/// One family row as listed: the faces a search leaves, and whether the
/// search forces it open.
struct FontPickerRow: Identifiable, Equatable, Sendable {
    let family: FontPickerFamily
    let faces: [FontPickerFace]
    /// Shown open with only `faces`: matched by style, not by family name.
    let isFiltered: Bool
    var id: String { family.id }

    /// "Regular", "{n} styles" or, while filtered, "{k} of {n} styles".
    var subtitle: String {
        if family.faces.count == 1 { return family.faces[0].styleName }
        return isFiltered ? FontPickerCopy.styles(faces.count, of: family.faces.count) : FontPickerCopy.styles(family.faces.count)
    }
}

struct FontPickerSectionContent: Identifiable, Equatable, Sendable {
    let section: FontPickerSection
    let rows: [FontPickerRow]
    var id: FontPickerSection { section }

    /// Tags present on the rows' faces, App Only first, for the footer.
    var keyboardFooters: [String] {
        let statuses = Set(rows.flatMap { $0.faces.map(\.keyboard) })
        return [KeyboardFontStatus.appOnly, .unverified].filter(statuses.contains).compactMap(\.footer)
    }
}

/// What the list shows for a query and the support known so far.
struct FontPickerContent: Equatable, Sendable {
    let sections: [FontPickerSectionContent]
    /// Families every face of which is verified unable, after checking ends.
    let unsupported: [FontPickerRow]

    var familyCount: Int { sections.reduce(unsupported.count) { $0 + $1.rows.count } }
    var isEmpty: Bool { familyCount == 0 }

    /// `ranked` once every check has finished (or failed): within each section,
    /// families whose best face can draw it first, then the rest, each
    /// alphabetical; families whose faces are all verified unable move to
    /// `unsupported`. Before that nothing moves.
    static func build(_ families: [FontPickerFamily], query: FontPickerQuery,
                      support: [String: FontPickerSupport], ranked: Bool) -> FontPickerContent {
        var bySection: [FontPickerSection: [FontPickerRow]] = [:]
        var unsupported: [FontPickerRow] = []
        for family in families {
            guard let row = row(family, query: query) else { continue }
            if ranked, family.faces.allSatisfy({ support[$0.id]?.isUnable == true }) {
                unsupported.append(row)
            } else {
                bySection[family.section, default: []].append(row)
            }
        }
        let sections = FontPickerSection.allCases.compactMap { section -> FontPickerSectionContent? in
            guard var rows = bySection[section] else { return nil }
            if ranked {
                let usable = rows.filter { $0.family.faces.contains { support[$0.id]?.isUsable == true } }
                let ids = Set(usable.map(\.id))
                rows = usable + rows.filter { !ids.contains($0.id) }
            }
            return FontPickerSectionContent(section: section, rows: rows)
        }
        return FontPickerContent(sections: sections, unsupported: unsupported.sorted { alphabetical($0.family, $1.family) })
    }

    private static func alphabetical(_ lhs: FontPickerFamily, _ rhs: FontPickerFamily) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? FontPickerFamily.alphabetical(lhs, rhs) : order == .orderedAscending
    }

    /// The family as a search shows it, or nil when nothing in it matches.
    static func row(_ family: FontPickerFamily, query: FontPickerQuery) -> FontPickerRow? {
        if query.matches(family.folded) { return FontPickerRow(family: family, faces: family.faces, isFiltered: false) }
        let faces = family.faces.filter { query.matches($0.searchKey) }
        return faces.isEmpty ? nil : FontPickerRow(family: family, faces: faces, isFiltered: true)
    }

    /// The order to check support in: the selected face, then faces matching
    /// the query, then the rest, each in display order. Only `pending` faces.
    static func checkOrder(_ families: [FontPickerFamily], selected: String?, query: FontPickerQuery,
                           pending: Set<String>) -> [String] {
        var matching: [String] = [], rest: [String] = []
        for family in families {
            let familyMatches = query.isEmpty || query.matches(family.folded)
            for face in family.faces where pending.contains(face.id) && face.id != selected {
                if familyMatches || query.matches(face.searchKey) { matching.append(face.id) } else { rest.append(face.id) }
            }
        }
        let first = selected.flatMap { pending.contains($0) ? [$0] : nil } ?? []
        return first + matching + rest
    }
}

#if canImport(CoreText)
extension KeyboardFontEvidence {
    /// What this process can open, on this iOS build. The keyboard records it.
    static func current(systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) -> KeyboardFontEvidence {
        KeyboardFontEvidence(systemVersion: systemVersion, postScriptNames: CTFontManagerCopyAvailablePostScriptNames() as! [String])
    }
}
#endif
