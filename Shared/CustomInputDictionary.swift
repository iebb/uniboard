import Foundation

/// These limits count Unicode scalars, not Characters or UTF-16 code units.
public enum CustomInputDictionaryLimits {
    public static let importBytes = 1_048_576
    public static let entryLinesPerImport = 10_000
    public static let totalEntries = 50_000
    /// Bounds empty-collection metadata independently of the entry limit.
    public static let totalCollections = 1_024
    public static let fieldScalars = 256
    public static let defaultWeight = 100
    public static let maximumWeight = 10_000
    // Every diagnostic is reachable in review. Still bounded by the existing
    // 1 MiB file and 10,000 entry-line limits; no source text is retained here.
    public static let retainedErrors = entryLinesPerImport
    public static let retainedExamples = 5
}

/// A normalized lookup reading and an EXACT output. Never normalize the output.
public struct CustomInputDictionaryEntry: Codable, Hashable, Sendable {
    public let reading: String
    public let output: String
    public let weight: Int

    public init(reading: String, output: String, weight: Int = CustomInputDictionaryLimits.defaultWeight) {
        self.reading = reading
        self.output = output
        self.weight = weight
    }

    /// Swift String equality is canonically equivalent; dictionary identity is not.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.weight == rhs.weight
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(weight)
    }

    public var identity: CustomInputDictionaryEntryIdentity {
        .init(readingUTF8: Data(reading.utf8), outputUTF8: Data(output.utf8))
    }
}

public struct CustomInputDictionaryEntryIdentity: Hashable, Sendable {
    public let readingUTF8: Data
    public let outputUTF8: Data
}

public struct CustomInputDictionaryCollection: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let modeID: String
    public let enabled: Bool
    public let entries: [CustomInputDictionaryEntry]

    public init(id: UUID = UUID(), name: String, modeID: String, enabled: Bool = true,
                entries: [CustomInputDictionaryEntry]) {
        self.id = id
        self.name = name
        self.modeID = modeID
        self.enabled = enabled
        self.entries = entries
    }
}

/// Inject the audited engine's mode allow-list and spelling rules. This layer
/// deliberately knows no romaji, pinyin, romaja or English shortcut scheme.
/// The normalizer must be deterministic/idempotent and return nil for unsupported
/// readings. It is called only after the raw field passes structural validation.
public struct CustomInputDictionaryRules {
    public let isSupportedMode: (String) -> Bool
    public let normalizeReading: (_ modeID: String, _ reading: String) -> String?

    public init(isSupportedMode: @escaping (String) -> Bool,
                normalizeReading: @escaping (_ modeID: String, _ reading: String) -> String?) {
        self.isSupportedMode = isSupportedMode
        self.normalizeReading = normalizeReading
    }

    public func supports(modeID: String) -> Bool {
        CustomInputDictionaryValidation.fieldIssue(modeID, reading: true) == nil && isSupportedMode(modeID)
    }

    public func validate(reading: String, output: String, weight: Int = CustomInputDictionaryLimits.defaultWeight,
                         modeID: String) -> Result<CustomInputDictionaryEntry, CustomInputDictionaryValidationIssue> {
        guard supports(modeID: modeID) else { return .failure(.unsupportedMode) }
        if let issue = CustomInputDictionaryValidation.fieldIssue(reading, reading: true) { return .failure(issue) }
        if let issue = CustomInputDictionaryValidation.fieldIssue(output, reading: false) { return .failure(issue) }
        guard (0...CustomInputDictionaryLimits.maximumWeight).contains(weight) else { return .failure(.invalidWeight) }
        guard let normalized = normalizeReading(modeID, reading), !normalized.hasPrefix("#") else {
            // # is reserved at the start of an entry line by the exchange format.
            return .failure(.unsupportedReading)
        }
        if let issue = CustomInputDictionaryValidation.fieldIssue(normalized, reading: true) { return .failure(issue) }
        return .success(.init(reading: normalized, output: output, weight: weight))
    }
}

/// Structured reasons only: presentation/localization belongs to the app.
public enum CustomInputDictionaryValidationIssue: Error, Equatable, Sendable {
    case unsupportedMode
    case missingTab
    case columnCount
    case emptyReading
    case emptyOutput
    case readingTooLong
    case outputTooLong
    case forbiddenCharacter
    case unsupportedReading
    case invalidWeight
}

public enum CustomInputDictionaryFileIssue: Equatable, Sendable {
    case invalidUTF8
    case tooLarge
    case tooManyEntryLines
    case tooManyTotalEntries
    case tooManyCollections
    case unsupportedMode
    case noEntries
}

public struct CustomInputDictionaryRowError: Equatable, Sendable {
    public let line: Int
    public let issue: CustomInputDictionaryValidationIssue
}

public struct CustomInputDictionaryExample: Equatable, Sendable {
    public let line: Int
    public let entry: CustomInputDictionaryEntry
}

/// A pure, bounded import plan. Merely creating or cancelling one never writes.
/// validRowCount includes duplicates/combined rows; entries contains unique pairs.
/// duplicateRowCount counts repeated exact triples (normalized reading, exact
/// output, resolved weight). combinedCount counts distinct weights combined into
/// an existing pair; the highest weight wins (omitted = 100). Repeats of a lower
/// weight still count as exact duplicates even after a higher weight was seen.
/// Different outputs, including canonically equivalent scalar sequences, remain
/// separate candidates. Entry order follows the first occurrence of each pair.
public struct CustomInputDictionaryPreview: Sendable {
    public let baseRevision: UUID
    public let modeID: String
    public let entries: [CustomInputDictionaryEntry]
    public let entryLineCount: Int
    public let validRowCount: Int
    public let invalidRowCount: Int
    public let duplicateRowCount: Int
    public let combinedCount: Int
    public let rowErrors: [CustomInputDictionaryRowError]
    public let examples: [CustomInputDictionaryExample]
    public let fileIssues: [CustomInputDictionaryFileIssue]
    public var uniqueEntryCount: Int { entries.count }
    public var omittedErrorCount: Int { max(0, invalidRowCount - rowErrors.count) }
    public var canApply: Bool { invalidRowCount == 0 && fileIssues.isEmpty && !entries.isEmpty }

    fileprivate init(baseRevision: UUID, modeID: String, entries: [CustomInputDictionaryEntry] = [],
                     entryLineCount: Int = 0, validRowCount: Int = 0, invalidRowCount: Int = 0,
                     duplicateRowCount: Int = 0, combinedCount: Int = 0, rowErrors: [CustomInputDictionaryRowError] = [],
                     examples: [CustomInputDictionaryExample] = [], fileIssues: [CustomInputDictionaryFileIssue]) {
        self.baseRevision = baseRevision
        self.modeID = modeID
        self.entries = entries
        self.entryLineCount = entryLineCount
        self.validRowCount = validRowCount
        self.invalidRowCount = invalidRowCount
        self.duplicateRowCount = duplicateRowCount
        self.combinedCount = combinedCount
        self.rowErrors = rowErrors
        self.examples = examples
        self.fileIssues = fileIssues
    }
}

public enum CustomInputDictionaryParser {
    public static func preview(data: Data, modeID: String, baseRevision: UUID, existingEntryCount: Int,
                               existingCollectionCount: Int = 0, rules: CustomInputDictionaryRules) -> CustomInputDictionaryPreview {
        func rejected(_ issue: CustomInputDictionaryFileIssue) -> CustomInputDictionaryPreview {
            .init(baseRevision: baseRevision, modeID: modeID, fileIssues: [issue])
        }
        guard data.count <= CustomInputDictionaryLimits.importBytes else { return rejected(.tooLarge) }
        guard let text = String(data: data, encoding: .utf8) else { return rejected(.invalidUTF8) }
        guard rules.supports(modeID: modeID) else { return rejected(.unsupportedMode) }
        var bytes = text.utf8[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        var entries: [CustomInputDictionaryEntry] = []
        var firstLines: [Int] = []
        var indices: [CustomInputDictionaryEntryIdentity: Int] = [:]
        var seenTriples = Set<CustomInputDictionaryEntry>()
        var errors: [CustomInputDictionaryRowError] = []
        var issues: [CustomInputDictionaryFileIssue] = []
        var entryLines = 0, valid = 0, invalid = 0, duplicates = 0, combined = 0
        // Split bytes rather than Characters: Swift treats CRLF as one Character.
        for (offset, rawLine) in bytes.split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            var lineBytes = rawLine
            if lineBytes.last == 0x0D && rawLine.endIndex != bytes.endIndex { lineBytes = lineBytes.dropLast() }
            let line = String(decoding: lineBytes, as: UTF8.self)
            if line.hasPrefix("#") || (lineBytes.isEmpty || (!lineBytes.contains(0x09) && line.unicodeScalars.allSatisfy({ CharacterSet.whitespaces.contains($0) }))) { continue }
            entryLines += 1
            if entryLines > CustomInputDictionaryLimits.entryLinesPerImport {
                issues.append(.tooManyEntryLines)
                break
            }
            let columns = lineBytes.split(separator: 0x09, omittingEmptySubsequences: false)
                .map { String(decoding: $0, as: UTF8.self) }
            let result: Result<CustomInputDictionaryEntry, CustomInputDictionaryValidationIssue>
            if columns.count == 1 {
                result = .failure(.missingTab)
            } else if columns.count != 2 && columns.count != 3 {
                result = .failure(.columnCount)
            } else {
                let weightText = columns.count == 3 ? columns[2] : "100"
                if !weightText.isEmpty && weightText.utf8.allSatisfy({ (48...57).contains($0) }),
                   let weight = Int(weightText) {
                    result = rules.validate(reading: columns[0], output: columns[1], weight: weight, modeID: modeID)
                } else {
                    result = .failure(.invalidWeight)
                }
            }
            switch result {
            case let .failure(issue):
                invalid += 1
                if errors.count < CustomInputDictionaryLimits.retainedErrors { errors.append(.init(line: offset + 1, issue: issue)) }
            case let .success(entry):
                valid += 1
                let newTriple = seenTriples.insert(entry).inserted
                if let index = indices[entry.identity] {
                    if newTriple { combined += 1 } else { duplicates += 1 }
                    if entry.weight > entries[index].weight { entries[index] = entry }
                } else {
                    indices[entry.identity] = entries.count
                    entries.append(entry)
                    firstLines.append(offset + 1)
                }
            }
        }
        if entries.isEmpty && invalid == 0 { issues.append(.noEntries) }
        if existingEntryCount < 0 || existingEntryCount > CustomInputDictionaryLimits.totalEntries ||
            entries.count > CustomInputDictionaryLimits.totalEntries - max(0, existingEntryCount) {
            issues.append(.tooManyTotalEntries)
        }
        if existingCollectionCount < 0 || existingCollectionCount >= CustomInputDictionaryLimits.totalCollections {
            issues.append(.tooManyCollections)
        }
        let examples = entries.prefix(CustomInputDictionaryLimits.retainedExamples).enumerated().map {
            CustomInputDictionaryExample(line: firstLines[$0.offset], entry: $0.element)
        }
        return .init(baseRevision: baseRevision, modeID: modeID, entries: entries, entryLineCount: entryLines,
                     validRowCount: valid, invalidRowCount: invalid, duplicateRowCount: duplicates, combinedCount: combined,
                     rowErrors: errors, examples: examples, fileIssues: issues)
    }
}

/// Internal shared structural checks, including validation of persisted snapshots.
enum CustomInputDictionaryValidation {
    static func fieldIssue(_ value: String, reading: Bool) -> CustomInputDictionaryValidationIssue? {
        if value.isEmpty { return reading ? .emptyReading : .emptyOutput }
        if value.unicodeScalars.count > CustomInputDictionaryLimits.fieldScalars { return reading ? .readingTooLong : .outputTooLong }
        if value.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 9 || CharacterSet.newlines.contains($0) }) {
            return .forbiddenCharacter
        }
        return nil
    }

    static func structurallyValid(_ entry: CustomInputDictionaryEntry) -> Bool {
        fieldIssue(entry.reading, reading: true) == nil && !entry.reading.hasPrefix("#") &&
        fieldIssue(entry.output, reading: false) == nil && (0...CustomInputDictionaryLimits.maximumWeight).contains(entry.weight)
    }
}

public enum CustomInputDictionaryExport {
    public enum Weights: Equatable { case omitDefault, explicit }

    /// No header. The initial empty comment protects a first reading beginning
    /// with U+FEFF from being mistaken for the optional file BOM on reimport.
    /// Valid collections always have exportable readings (# is reserved).
    /// A single exact TSV file. A large manually grown collection can exceed
    /// the import file limits; use tsvParts for bounded, reimportable backup files.
    public static func tsv(_ collection: CustomInputDictionaryCollection, weights: Weights = .omitDefault) throws -> Data {
        var text = "#\n"
        for entry in collection.entries { text.append(try line(entry, weights: weights)) }
        return Data(text.utf8)
    }

    /// Preserves every entry in order, partitioning only at entry boundaries.
    /// Each part satisfies BOTH import bounds (bytes and entry lines). Reimport
    /// creates a separate collection per part, as required by the import contract.
    public static func tsvParts(_ collection: CustomInputDictionaryCollection, weights: Weights = .omitDefault) throws -> [Data] {
        let prefix = Data("#\n".utf8)
        var parts: [Data] = []
        var part = prefix
        var entryCount = 0
        for entry in collection.entries {
            let bytes = Data(try line(entry, weights: weights).utf8)
            if entryCount == CustomInputDictionaryLimits.entryLinesPerImport || part.count + bytes.count > CustomInputDictionaryLimits.importBytes {
                parts.append(part)
                part = prefix
                entryCount = 0
            }
            part.append(bytes)
            entryCount += 1
        }
        parts.append(part)
        return parts
    }

    private static func line(_ entry: CustomInputDictionaryEntry, weights: Weights) throws -> String {
        guard CustomInputDictionaryValidation.structurallyValid(entry) else { throw CustomInputDictionaryExportError.invalidEntry }
        var text = entry.reading + "\t" + entry.output
        if weights == .explicit || entry.weight != CustomInputDictionaryLimits.defaultWeight { text += "\t\(entry.weight)" }
        return text + "\n"
    }
}

public enum CustomInputDictionaryExportError: Error { case invalidEntry }
