import Foundation

/// Read-only projections. Offsets always refer to source order, never a sorted row.
public enum MyWordsEntrySort: String, CaseIterable, Sendable {
    case original = "Original Order", reading = "Reading", weight = "Weight"
    public var heading: String {
        switch self {
        case .original: return "Entries"
        case .reading: return "Entries · By Reading"
        case .weight: return "Entries · By Weight"
        }
    }
}

public struct MyWordsEntryReference: Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        public let collectionID: UUID
        public let index: Int
        public let revision: UUID
        public let identity: CustomInputDictionaryEntryIdentity
    }
    public let id: ID
    public let dictionaryName: String
    public let modeID: String
    public let entry: CustomInputDictionaryEntry
    public init(collection: CustomInputDictionaryCollection, index: Int, revision: UUID) {
        let entry = collection.entries[index]
        id = .init(collectionID: collection.id, index: index, revision: revision, identity: entry.identity)
        dictionaryName = collection.name
        modeID = collection.modeID
        self.entry = entry
    }
}

public struct MyWordsSearchResult: Sendable {
    public let entries: [MyWordsEntryReference]
    public let hasMore: Bool
    public static let empty = MyWordsSearchResult(entries: [], hasMore: false)
}

public enum MyWordsPresentation {
    public static func matches(_ entry: CustomInputDictionaryEntry, query: String) -> Bool {
        query.isEmpty || entry.reading.localizedCaseInsensitiveContains(query) || entry.output.localizedCaseInsensitiveContains(query)
    }

    /// Source-order scan includes disabled collections; examines one extra match
    /// to report truncation truthfully, without inventing an exhaustive count.
    public static func search(_ snapshot: CustomInputDictionarySnapshot, query: String, modeID: String? = nil) -> MyWordsSearchResult {
        guard !query.isEmpty else { return .empty }
        var result: [MyWordsEntryReference] = []
        for collection in snapshot.collections where modeID == nil || collection.modeID == modeID {
            for (index, entry) in collection.entries.enumerated() where matches(entry, query: query) {
                if result.count == 100 { return .init(entries: result, hasMore: true) }
                result.append(.init(collection: collection, index: index, revision: snapshot.revision))
            }
        }
        return .init(entries: result, hasMore: false)
    }

    /// Locale-independent UTF-8 reading order, descending numeric weight, then
    /// exact reading/output bytes and original offset. Never rewrites source.
    public static func sortedIndices(_ entries: [CustomInputDictionaryEntry], query: String, sort: MyWordsEntrySort) -> [Int] {
        let indices = entries.indices.filter { matches(entries[$0], query: query) }
        guard sort != .original else { return indices }
        return indices.sorted { left, right in
            let a = entries[left], b = entries[right]
            if sort == .weight && a.weight != b.weight { return a.weight > b.weight }
            if !a.reading.utf8.elementsEqual(b.reading.utf8) { return a.reading.utf8.lexicographicallyPrecedes(b.reading.utf8) }
            if !a.output.utf8.elementsEqual(b.output.utf8) { return a.output.utf8.lexicographicallyPrecedes(b.output.utf8) }
            return left < right
        }
    }

    public static func isUnchangedPair(reading: String, output: String, source: CustomInputDictionaryEntry) -> Bool {
        reading.utf8.elementsEqual(source.reading.utf8) && output.utf8.elementsEqual(source.output.utf8)
    }
}

public struct MyWordsPage: Equatable, Sendable {
    public let index: Int
    public let pages: Int
    public let range: Range<Int>
    public init(total: Int, page: Int, size: Int) {
        let total = max(0, total), size = max(1, size)
        pages = max(1, (total + size - 1) / size)
        index = min(max(0, page), pages - 1)
        let start = index * size
        range = start..<min(total, start + size)
    }
    public func label(noun: String, total: Int) -> String {
        guard !range.isEmpty else { return "\(noun) 0 of \(total)" }
        return "\(noun) \(range.lowerBound + 1)–\(range.upperBound) of \(total)"
    }
}

/// A frozen scalar sequence; stand-ins are display-only and never replace text.
public struct MyWordsOutputInspection: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let scalars: [Scalar]
    public struct Scalar: Identifiable, Sendable {
        public let id: Int
        public let value: UInt32
        public let glyph: String
        public let name: String
        public let usesStandIn: Bool
        public var codePoint: String { String(format: "U+%04X", value) }
    }
    public init(_ text: String) {
        self.text = text
        scalars = text.unicodeScalars.enumerated().map { offset, scalar in
            let category = scalar.properties.generalCategory
            let mark = category == .nonspacingMark || category == .spacingMark || category == .enclosingMark
            let invisible = category == .format || category == .control || category == .lineSeparator || category == .paragraphSeparator
                || (scalar.properties.isDefaultIgnorableCodePoint && !mark)
            let space = category == .spaceSeparator
            let name: String
            switch scalar.value {
            case 0x0000: name = "Null"
            case 0x0009: name = "Character Tabulation"
            case 0x000A: name = "Line Feed"
            case 0x000D: name = "Carriage Return"
            case 0x007F: name = "Delete"
            case 0x200B: name = "Zero Width Space"
            case 0x200C: name = "Zero Width Non-Joiner"
            case 0x200D: name = "Zero Width Joiner"
            case 0x2060: name = "Word Joiner"
            case 0xFEFF: name = "Zero Width No-Break Space"
            default:
                // Same title-casing vocabulary as the existing spokenName
                // inspector helper; no catalog name is invented when absent.
                name = scalar.properties.name.map {
                    $0.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
                } ?? "Not available"
            }
            return Scalar(id: offset, value: scalar.value,
                          glyph: space ? "␠" : invisible ? "◌" : mark ? "◌" + String(scalar) : String(scalar),
                          name: name, usesStandIn: mark || invisible || space)
        }
    }
}
