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

    var text: String { String(String.UnicodeScalarView(codePoints.compactMap { Unicode.Scalar($0) })) }
    var codePointLabel: String { codePoints.map { String(format: "U+%04X", $0) }.joined(separator: " ") }
    var versionSortKey: Int { unicodeVersionKey(emojiVersion) }
    var unicodeVersionSortKey: Int { unicodeVersionKey(unicodeVersion) }
}

/// The complete official fully-qualified keyboard set, including full sequences.
final class EmojiCatalog: @unchecked Sendable {
    static let shared = EmojiCatalog()
    static let latest = EmojiCatalog(edition: .latest)
    let edition: UnicodeEdition
    let version: String
    let unicodeVersion: String
    let resourceError: String?
    /// Newest Emoji introduction first, with deterministic code-point tie breaks.
    let entries: [UnicodeEmojiEntry]
    private let searchStrings: [String]
    private let texts: [String]

    private struct Document: Decodable {
        let version: String
        let unicodeVersion: String
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
           !document.entries.isEmpty,
           Set(document.entries.map(\.id)).count == document.entries.count,
           document.entries.allSatisfy({ !$0.codePoints.isEmpty && $0.codePoints.allSatisfy({ Unicode.Scalar($0) != nil }) }) {
            version = document.version
            unicodeVersion = document.unicodeVersion
            entries = document.entries.sorted { Self.precedes($0, $1, order: .newestFirst) }
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

    func orderedEntries(order: UnicodeSortOrder = .newestFirst) -> [UnicodeEmojiEntry] {
        order == .newestFirst ? entries : entries.sorted { Self.precedes($0, $1, order: order) }
    }

    func entries(offset: Int = 0, limit: Int = 256,
                 order: UnicodeSortOrder = .newestFirst) -> [UnicodeEmojiEntry] {
        guard offset >= 0, limit > 0 else { return [] }
        return Array(orderedEntries(order: order).dropFirst(offset).prefix(limit))
    }

    func search(_ query: String, limit: Int = 240,
                order: UnicodeSortOrder = .newestFirst) -> [UnicodeEmojiEntry] {
        guard limit > 0 else { return [] }
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
            let matches = entries.filter { entry in
                entry.codePoints == points || entry.codePoints.filter { $0 != 0xFE0F } == points.filter { $0 != 0xFE0F }
                    || (points.count == 1 && entry.codePoints.contains(points[0]))
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
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var matches: [UnicodeEmojiEntry] = []
        for index in entries.indices where words.allSatisfy({ searchStrings[index].contains($0) }) {
            matches.append(entries[index])
        }
        return Array(matches.sorted { left, right in
            let leftExact = Self.normalized(left.name) == normalized
            let rightExact = Self.normalized(right.name) == normalized
            if leftExact != rightExact { return leftExact }
            return Self.precedes(left, right, order: order)
        }.prefix(limit))
    }

    private static func precedes(_ left: UnicodeEmojiEntry, _ right: UnicodeEmojiEntry,
                                 order: UnicodeSortOrder) -> Bool {
        if order != .codePoint && left.versionSortKey != right.versionSortKey {
            return order == .newestFirst ? left.versionSortKey > right.versionSortKey : left.versionSortKey < right.versionSortKey
        }
        return left.codePoints.lexicographicallyPrecedes(right.codePoints)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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
            guard let cp = UInt32(value.dropFirst(8).trimmingCharacters(in: .whitespaces)), Unicode.Scalar(cp) != nil else { return nil }
            return [cp]
        }
        let words = value.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "-" })
        guard !words.isEmpty else { return nil }
        var points: [UInt32] = []
        for word in words {
            let lower = word.lowercased()
            let digits: Substring
            if lower.hasPrefix("u+") || lower.hasPrefix("0x") { digits = lower.dropFirst(2) }
            else if (4...6).contains(lower.count), lower.contains(where: { $0.isNumber }) { digits = lower[...] }
            else { return nil }
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let cp = UInt32(digits, radix: 16), Unicode.Scalar(cp) != nil else { return nil }
            points.append(cp)
        }
        return points
    }
}
