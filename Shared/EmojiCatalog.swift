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
    static let latest = EmojiCatalog(edition: .latest)
    static let previous = EmojiCatalog(edition: .previous)
    static let older = EmojiCatalog(edition: .older)
    let edition: UnicodeEdition
    let version: String
    let unicodeVersion: String
    let resourceError: String?
    /// Ascending scalar-sequence order, including every variation selector/ZWJ.
    let entries: [UnicodeEmojiEntry]
    private let searchStrings: [String]
    private let texts: [String]

    private struct Document: Decodable {
        let version: String
        let unicodeVersion: String
        let edition: String?
        let entries: [UnicodeEmojiEntry]
    }

    init(edition: UnicodeEdition = .draft, resourceURL: URL? = nil) {
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
            entries = document.entries.sorted { Self.precedes($0, $1, order: .codePoint) }
            searchStrings = entries.map { Self.normalized($0.name + " " + $0.group + " " + $0.subgroup) }
            texts = entries.map(\.text)
            resourceError = nil
        } else {
            version = "Unavailable"
            unicodeVersion = "Unavailable"
            entries = []
            searchStrings = []
            texts = []
            resourceError = "The offline emoji catalog could not be loaded."
        }
    }

    func orderedEntries(order: UnicodeSortOrder = .codePoint) -> [UnicodeEmojiEntry] {
        guard !Task.isCancelled else { return [] }
        return order == .codePoint ? entries : entries.sorted { Self.precedes($0, $1, order: order) }
    }

    func entries(offset: Int = 0, limit: Int = 256,
                 order: UnicodeSortOrder = .codePoint) -> [UnicodeEmojiEntry] {
        guard offset >= 0, limit > 0, !Task.isCancelled else { return [] }
        return Array(orderedEntries(order: order).dropFirst(offset).prefix(limit))
    }

    func search(_ query: String, limit: Int = 240,
                order: UnicodeSortOrder = .codePoint) -> [UnicodeEmojiEntry] {
        guard limit > 0, !Task.isCancelled, CatalogSearchQueryPolicy.accepts(query) else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries(limit: limit, order: order) }
        if let exact = texts.firstIndex(of: trimmed) { return [entries[exact]] }
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
            for (index, entry) in entries.enumerated() {
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
        for index in entries.indices {
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
