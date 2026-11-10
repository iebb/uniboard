import Foundation

/// A fully-qualified emoji sequence. Insert text as a whole, including VS/ZWJ.
struct UnicodeEmojiEntry: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let codePoints: [UInt32]
    let name: String
    let emojiVersion: String
    /// Maximum official Unicode Age of the components, not Emoji introduction.
    let unicodeVersion: String
    let group: String
    let subgroup: String

    var text: String {
        let scalars = codePoints.compactMap { Unicode.Scalar($0) }
        guard !scalars.isEmpty, scalars.count == codePoints.count else { return "" }
        return String(String.UnicodeScalarView(scalars))
    }
    var codePointLabel: String { codePoints.map { String(format: "U+%04X", $0) }.joined(separator: " ") }
    var versionSortKey: Int { unicodeVersionKey(emojiVersion) }
    var unicodeVersionSortKey: Int { unicodeVersionKey(unicodeVersion) }
}

/// The complete official fully-qualified keyboard set, including full sequences.
final class EmojiCatalog: @unchecked Sendable {
    static let shared = EmojiCatalog()
    static let latest = shared.limited(to: .latest)
    static let previous = shared.limited(to: .previous)
    static let older = shared.limited(to: .older)
    let edition: UnicodeEdition
    let version: String
    let unicodeVersion: String
    let resourceError: String?
    /// Ascending scalar-sequence order, including every variation selector/ZWJ.
    let entries: [UnicodeEmojiEntry]
    /// Every CLDR group in the order the catalog file lists them (the
    /// Unicode chart order). Final editions keep the full list, so a group
    /// with no emoji yet still has a row (and counts 0).
    let groups: [String]
    private let groupCounts: [String: Int]
    /// Each group's first emoji in catalog file order.
    private let firstInGroup: [String: String]
    private let searchStrings: [String]
    private let texts: [String]
    /// Entries by id and by exact UTF-16 text, built on first lookup.
    private let lookupLock = NSLock()
    private var lookup: (byID: [String: UnicodeEmojiEntry], byText: [[UInt16]: UnicodeEmojiEntry])?

    private struct Document: Decodable {
        let version: String
        let unicodeVersion: String
        let edition: String?
        let entries: [UnicodeEmojiEntry]
    }

    /// Loads the bundled draft set. Final editions are limited views of it.
    init(resourceURL: URL? = nil) {
        let edition = UnicodeEdition.draft
        self.edition = edition
        let filename = "EmojiCatalog-\(edition.rawValue)"
        let url: URL?
        if let resourceURL {
            url = resourceURL.pathExtension == "json" ? resourceURL
                : resourceURL.appendingPathComponent(filename + ".json")
        } else {
            #if SWIFT_PACKAGE
            let bundles = [Bundle.module, Bundle.main, Bundle(for: EmojiCatalog.self)]
            #else
            let bundles = [Bundle.main, Bundle(for: EmojiCatalog.self)]
            #endif
            url = bundles.lazy.compactMap { $0.url(forResource: filename, withExtension: "json") }.first
        }
        if let url, let data = try? Data(contentsOf: url),
           let document = try? JSONDecoder().decode(Document.self, from: data),
           unicodeVersionKey(document.version) > 0, unicodeVersionKey(document.unicodeVersion) > 0,
           unicodeVersionKey(document.version) == unicodeVersionKey(document.unicodeVersion),
           document.version.hasSuffix(" draft") == (edition == .draft),
           document.unicodeVersion.hasSuffix(" draft") == (edition == .draft),
           document.edition == nil || document.edition == edition.rawValue,
           !document.entries.isEmpty,
           Set(document.entries.map(\.id)).count == document.entries.count,
           document.entries.allSatisfy({ entry in
               !entry.codePoints.isEmpty && entry.codePoints.allSatisfy({ Unicode.Scalar($0) != nil })
                   && entry.id == entry.codePoints.map({ String(format: "%04X", $0) }).joined(separator: "-")
                   && !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   && !entry.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   && !entry.subgroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   && !entry.emojiVersion.hasSuffix(" draft")
                   && unicodeVersionKey(entry.emojiVersion) > 0 && unicodeVersionKey(entry.emojiVersion) <= unicodeVersionKey(document.version)
                   && (unicodeVersionKey(entry.unicodeVersion) > 0 && unicodeVersionKey(entry.unicodeVersion) <= unicodeVersionKey(document.unicodeVersion)
                       || edition == .draft && entry.unicodeVersion == "Pending draft age")
           }) {
            version = document.version
            unicodeVersion = document.unicodeVersion
            groups = Self.groupOrder(document.entries)
            firstInGroup = document.entries.reduce(into: [:]) { if $0[$1.group] == nil { $0[$1.group] = $1.text } }
            entries = document.entries.sorted { Self.precedes($0, $1, order: .codePoint) }
            groupCounts = Self.counts(entries)
            searchStrings = entries.map { Self.normalized($0.name + " " + $0.group + " " + $0.subgroup) }
            texts = entries.map(\.text)
            resourceError = nil
        } else {
            version = "Unavailable"
            unicodeVersion = "Unavailable"
            entries = []
            groups = []
            groupCounts = [:]
            firstInGroup = [:]
            searchStrings = []
            texts = []
            resourceError = "The offline emoji catalog could not be loaded."
        }
    }

    /// A final edition: the emoji introduced by its version or earlier.
    func limited(to edition: UnicodeEdition) -> EmojiCatalog {
        edition == .draft ? self : EmojiCatalog(base: self, edition: edition)
    }

    private init(base: EmojiCatalog, edition: UnicodeEdition) {
        self.edition = edition
        let key = unicodeVersionKey(edition.versionLabel)
        unicodeVersion = key > 0 ? edition.versionLabel : "Unavailable"
        version = key > 0 ? edition.versionLabel.split(separator: ".").prefix(2).joined(separator: ".") : "Unavailable"
        entries = key > 0 ? base.entries.filter {
            unicodeVersionKey($0.emojiVersion) <= key && (1...key).contains(unicodeVersionKey($0.unicodeVersion))
        } : []
        groups = key > 0 ? base.groups : []
        firstInGroup = base.firstInGroup
        groupCounts = Self.counts(entries)
        searchStrings = entries.map { Self.normalized($0.name + " " + $0.group + " " + $0.subgroup) }
        texts = entries.map(\.text)
        resourceError = key > 0 ? base.resourceError : "The offline emoji catalog could not be loaded."
    }

    private static func groupOrder(_ entries: [UnicodeEmojiEntry]) -> [String] {
        var seen = Set<String>()
        return entries.map(\.group).filter { seen.insert($0).inserted }
    }

    private static func counts(_ entries: [UnicodeEmojiEntry]) -> [String: Int] {
        entries.reduce(into: [:]) { $0[$1.group, default: 0] += 1 }
    }

    /// The first entry with `id`.
    func entry(id: String) -> UnicodeEmojiEntry? { lookupIndexes().byID[id] }

    /// The first entry whose text has exactly `text`'s UTF-16 code units
    /// (not canonical equivalence, which String's `==` uses).
    func entry(text: String) -> UnicodeEmojiEntry? { lookupIndexes().byText[Array(text.utf16)] }

    private func lookupIndexes() -> (byID: [String: UnicodeEmojiEntry], byText: [[UInt16]: UnicodeEmojiEntry]) {
        lookupLock.lock()
        defer { lookupLock.unlock() }
        if let lookup { return lookup }
        var byID: [String: UnicodeEmojiEntry] = [:], byText: [[UInt16]: UnicodeEmojiEntry] = [:]
        byID.reserveCapacity(entries.count)
        byText.reserveCapacity(entries.count)
        for (entry, text) in zip(entries, texts) {
            if byID[entry.id] == nil { byID[entry.id] = entry }
            let key = Array(text.utf16)
            if byText[key] == nil { byText[key] = entry }
        }
        lookup = (byID, byText)
        return (byID, byText)
    }

    /// Emoji (sequences, not code points) this edition lists in `group`.
    func count(inGroup group: String) -> Int { groupCounts[group] ?? 0 }

    /// How many of this catalog's groups `hidden` leaves shown.
    func shownGroupCount(hiding hidden: Set<String>) -> Int { groups.filter { !hidden.contains($0) }.count }

    /// The category sheet's fixed sample (all Emoji 1.0, so in every
    /// edition), or the group's first emoji in catalog order.
    func sample(forGroup group: String) -> String? { Self.groupSamples[group] ?? firstInGroup[group] }
    static let groupSamples: [String: String] = [
        "Smileys & Emotion": "\u{1F600}", "People & Body": "\u{1F44B}", "Animals & Nature": "\u{1F436}",
        "Food & Drink": "\u{1F34E}", "Travel & Places": "\u{1F697}", "Activities": "\u{26BD}",
        "Objects": "\u{1F4A1}", "Symbols": "\u{1F523}", "Flags": "\u{1F3C1}",
    ]

    /// Every entry in `order`, leaving out the `hidden` groups before any
    /// paging, so a page is always full of shown emoji.
    func orderedEntries(order: UnicodeSortOrder = .codePoint, hiding hidden: Set<String> = [],
                        skinToneVariants: SkinToneVariants = .all) -> [UnicodeEmojiEntry] {
        guard !Task.isCancelled else { return [] }
        let shown = hidden.isEmpty ? entries : entries.filter { !hidden.contains($0.group) }
        let projected = EmojiBrowsingPolicy.project(shown, skinToneVariants: skinToneVariants)
        return order == .codePoint ? projected : projected.sorted { Self.precedes($0, $1, order: order) }
    }

    /// Emoji this release introduces, in code-point order.
    var addedEntries: [UnicodeEmojiEntry] { entries.filter { $0.emojiVersion == version } }

    /// One page in `order`. `hidden` groups are left out before paging.
    func entries(offset: Int = 0, limit: Int = 256,
                 order: UnicodeSortOrder = .codePoint, hiding hidden: Set<String> = [],
                 skinToneVariants: SkinToneVariants = .all) -> [UnicodeEmojiEntry] {
        guard offset >= 0, limit > 0, !Task.isCancelled else { return [] }
        return Array(orderedEntries(order: order, hiding: hidden, skinToneVariants: skinToneVariants).dropFirst(offset).prefix(limit))
    }

    /// Matches from the shown groups only: `hidden` groups never match,
    /// so `limit` results are all shown emoji.
    func search(_ query: String, limit: Int = 240,
                order: UnicodeSortOrder = .codePoint, hiding hidden: Set<String> = [],
                skinToneVariants: SkinToneVariants = .all) -> [UnicodeEmojiEntry] {
        guard limit > 0, !Task.isCancelled, CatalogSearchQueryPolicy.accepts(query) else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return entries(limit: limit, order: order, hiding: hidden, skinToneVariants: skinToneVariants)
        }
        // All nonempty searches bypass tone decluttering, including tone names,
        // pasted mixed-tone sequences and modifier/code-point searches. Categories
        // still apply, as before; results retain their original scalar sequences.
        if let exact = texts.firstIndex(of: trimmed) { return hidden.contains(entries[exact].group) ? [] : [entries[exact]] }
        let points: [UInt32]?
        if let hex = Self.parseCodePoints(trimmed) {
            points = hex
        } else if trimmed.unicodeScalars.contains(where: { $0.value > 0x7F })
                    && !trimmed.unicodeScalars.contains(where: Self.isLetter) {
            points = trimmed.unicodeScalars.map(\.value)
        } else {
            points = nil
        }
        if let points {
            var matches: [UnicodeEmojiEntry] = []
            for (index, entry) in entries.enumerated() where !hidden.contains(entry.group) {
                if index & 255 == 0 && Task.isCancelled { return [] }
                if entry.codePoints == points || entry.codePoints.filter({ $0 != 0xFE0F }) == points.filter({ $0 != 0xFE0F })
                    || (points.count == 1 && entry.codePoints.contains(points[0])) { matches.append(entry) }
            }
            return Array(matches.sorted { left, right in
                let leftExact = left.codePoints == points
                let rightExact = right.codePoints == points
                if leftExact != rightExact { return leftExact }
                return Self.precedes(left, right, order: order)
            }.prefix(limit))
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("u+") || lower.hasPrefix("0x") || lower.hasPrefix("decimal:") { return [] }
        let normalized = Self.normalized(trimmed)
        let words = CatalogSearchQueryPolicy.terms(in: normalized)
        guard !words.isEmpty else { return [] }
        var matches: [(entry: UnicodeEmojiEntry, whole: Bool)] = []
        for index in entries.indices where !hidden.contains(entries[index].group) {
            if index & 255 == 0 && Task.isCancelled { return [] }
            if words.allSatisfy({ !Task.isCancelled && searchStrings[index].contains($0) }) {
                let whole = words.allSatisfy { !Task.isCancelled && CatalogSearchQueryPolicy.containsWholeTerm($0, in: searchStrings[index]) }
                matches.append((entries[index], whole))
            }
        }
        return Array(matches.sorted { left, right in
            if left.whole != right.whole { return left.whole }
            return Self.precedes(left.entry, right.entry, order: order)
        }.prefix(limit).map(\.entry))
    }

    private static func precedes(_ left: UnicodeEmojiEntry, _ right: UnicodeEmojiEntry,
                                 order: UnicodeSortOrder) -> Bool {
        if order != .codePoint && left.versionSortKey != right.versionSortKey {
            return order == .newestFirst ? left.versionSortKey > right.versionSortKey : left.versionSortKey < right.versionSortKey
        }
        return left.codePoints.lexicographicallyPrecedes(right.codePoints)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    private static func parseCodePoints(_ value: String) -> [UInt32]? {
        if value.lowercased().hasPrefix("decimal:") {
            let digits = value.dropFirst(8).trimmingCharacters(in: .whitespaces)
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let cp = UInt32(digits), Unicode.Scalar(cp) != nil else { return nil }
            return [cp]
        }
        // Hyphens delimit canonical IDs; they never denote a signed scalar or
        // an empty component. Ordinary hyphenated names still use text search.
        var hasComponent = false, afterSeparator = false
        for character in value where !character.isWhitespace {
            if character == "," || character == "-" {
                guard hasComponent && !afterSeparator else { return nil }
                afterSeparator = true
            } else { hasComponent = true; afterSeparator = false }
        }
        guard hasComponent && !afterSeparator else { return nil }
        let words = value.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "-" })
        guard !words.isEmpty else { return nil }
        var points: [UInt32] = []
        for word in words {
            let lower = word.lowercased()
            let digits: Substring
            if lower.hasPrefix("u+") || lower.hasPrefix("0x") { digits = lower.dropFirst(2) }
            else if (4...6).contains(lower.count), lower.contains(where: { $0.isNumber }) { digits = lower[lower.startIndex..<lower.endIndex] }
            else { return nil }
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let cp = UInt32(digits, radix: 16), Unicode.Scalar(cp) != nil else { return nil }
            points.append(cp)
        }
        return points
    }
}

/// The emoji categories (CLDR group names) hidden from emoji browsing and
/// emoji search in the app and the keyboard. Only hidden names are stored,
/// so a group a later catalog adds starts shown. Lives in the current
/// configuration generation: the app writes, the keyboard only reads.
/// Missing or unusable data means every category is shown.
struct EmojiCategorySetting {
    static let filename = "emoji-categories-v1.json"
    static let maximumPayloadBytes = 8192
    static let maximumGroups = 32
    static let maximumNameBytes = 64
    /// Posted (Darwin) by the app after each save; the keyboard re-reads.
    static let changedNotification = "ad.neko.uniboard.emojiCategoriesChanged"
    static let shared = EmojiCategorySetting()

    private struct File: Codable {
        let hidden: [String]
        let schemaVersion: Int
    }

    let directory: () -> URL?

    init(directory: @escaping () -> URL? = { SharedConfigurationLocation.shared.currentDirectory() }) {
        self.directory = directory
    }

    func load() -> Set<String> {
        guard let directory = directory(),
              let data = try? SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(Self.filename),
                                                                          limit: Self.maximumPayloadBytes + 1) else { return [] }
        return Self.decode(data) ?? []
    }

    /// Only the containing app calls this.
    @discardableResult func save(_ hidden: Set<String>) -> Bool {
        guard let data = Self.encode(hidden), let directory = directory(),
              (try? SharedConfigurationLocation.replaceFile(data, at: directory.appendingPathComponent(Self.filename))) != nil else { return false }
        return true
    }

    /// A group name: 1 to 64 UTF-8 bytes, no control characters and no
    /// spaces at either end.
    static func isValidName(_ name: String) -> Bool {
        (1...maximumNameBytes).contains(name.utf8.count) && name.trimmingCharacters(in: .whitespacesAndNewlines) == name
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    static func isValid(_ hidden: Set<String>) -> Bool { hidden.count <= maximumGroups && hidden.allSatisfy(isValidName) }

    /// Sorted names; nil for an unusable set.
    static func encode(_ hidden: Set<String>) -> Data? {
        guard isValid(hidden) else { return nil }
        // Strings and an integer: encoding can't fail.
        return try! SharedConfigurationLocation.encoder.encode(File(hidden: hidden.sorted(), schemaVersion: 1))
    }

    static func decode(_ data: Data) -> Set<String>? {
        guard data.count <= maximumPayloadBytes, let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == 1,
              Set(file.hidden).count == file.hidden.count, isValid(Set(file.hidden)) else { return nil }
        return Set(file.hidden)
    }

    /// `hidden` in the catalog's group order, then names it doesn't list, sorted.
    static func ordered(_ hidden: Set<String>, groups: [String] = EmojiCatalog.shared.groups) -> [String] {
        groups.filter(hidden.contains) + hidden.subtracting(groups).sorted()
    }
}

/// How the app's emoji grid sizes its tiles (design §3). Columns are
/// chosen by the app's pinch and size menu; 0 means Automatic.
enum EmojiTileLayout {
    static let automaticMinimumWidth = 96.0
    static let spacing = 8.0
    /// Tiles this wide or wider show the emoji's name.
    static let nameMinimumWidth = 80.0
    /// Tiles this wide or wider use the larger name font.
    static let largeNameMinimumWidth = 150.0
    static let automaticColumnsBeforeMeasuring = 3
    private static let glyphPoints: [(width: Double, glyph: Double)] = [(34, 20), (54, 28), (80, 32), (118, 34), (181, 64), (250, 96)]

    /// The 1.3 layout: as many 96-point tiles as fit, at least two.
    static func automaticColumns(in width: Double) -> Int {
        guard width > 0 else { return automaticColumnsBeforeMeasuring }
        return max(2, Int(((width + spacing) / (automaticMinimumWidth + spacing)).rounded(.down)))
    }

    /// The glyph's point size for a tile `width` wide: linear between the
    /// table's points, clamped at both ends, rounded to a whole point.
    static func glyphSize(tileWidth width: Double) -> Double {
        guard width > glyphPoints[0].width else { return glyphPoints[0].glyph }
        for (low, high) in zip(glyphPoints, glyphPoints.dropFirst()) where width < high.width {
            return (low.glyph + (high.glyph - low.glyph) * (width - low.width) / (high.width - low.width)).rounded()
        }
        return glyphPoints[glyphPoints.count - 1].glyph
    }

    static func showsName(tileWidth width: Double) -> Bool { width >= nameMinimumWidth }
    static func usesLargeName(tileWidth width: Double) -> Bool { width >= largeNameMinimumWidth }
}
