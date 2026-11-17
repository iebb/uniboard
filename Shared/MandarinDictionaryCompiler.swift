import Foundation
import CryptoKit
import SQLite3

public struct MandarinDictionaryResource: Equatable, Sendable {
    public let filename: String
    public let bytes: Int
    public let sha256: String
    public let downloadURL: URL
}

public struct MandarinSimplifiedMappingURLs: Sendable {
    public let characters: URL
    public let phrases: URL
    public let compatibility: URL
    public init(characters: URL, phrases: URL, compatibility: URL) {
        self.characters = characters; self.phrases = phrases; self.compatibility = compatibility
    }
}

public struct MandarinDictionaryCompilationStats: Codable, Equatable, Sendable {
    public let compilerVersion: String
    public let sourceRows: [String: Int]
    public let quarantinedLines: [String: [Int]]
    public let simplifiedChangedRows: Int
    public let uniqueRows: Int
    public let combinedRows: Int
    public let outputPolicy: String
}

/// Row fraction describes insertion only, not the whole installation. Indexing
/// and final checks intentionally have no invented percentage or ETA.
public enum MandarinCompilationProgress: Equatable, Sendable {
    case verifyingSources
    case preparingMappings
    case rows(processed: Int, total: Int)
    case indexing
    case finalCheck
}

private final class MandarinCompilationCancellation {
    let check: () -> Bool
    init(_ check: @escaping () -> Bool) { self.check = check }
}

/// App-side ONLY. Exclude this file (and CryptoKit compilation work) from the
/// keyboard target. Downloading and atomic publication belong to the pack store.
/// Public compile accepts only the exact audited corpus/mappings, never arbitrary
/// Rime schemas, scripts, SQL or imported dictionaries. Use off the UI executor.
public enum MandarinDictionaryCompiler {
    public static let corpusCommit = "aa9947f3f513ff88a3f7ce4e342fcb519d517025"
    public static let mappingCommit = "26753884f1984add422f3b0249ccee8613deaff6"
    public static let jichu = resource("jichu.dict.yaml", 48_469_368,
        "74abd0a8013d5bbc0f397280fa0949d83234f005690e1631786e9ba9b466a74e", corpus: true)
    public static let zi = resource("zi.dict.yaml", 616_550,
        "dbb68f8b4ef93e48bf3632b3c4bc00b810c6bbb2e101635d6e14752444abe7c9", corpus: true)
    public static let characters = resource("TSCharacters.txt", 104_516,
        "737c21c66f55a419dd6956cb3089476cdefc5a36877452631617696df1e5d925", corpus: false)
    public static let phrases = resource("TSPhrases.txt", 8_786,
        "362fa1b9a7d6edd04b462a32e12c9fef3adae822ab1dee9c83561cc37c06cb1f", corpus: false)
    public static let compatibility = resource("CJK_Compatibility_Ideographs.txt", 39_074,
        "663cc10b7de7c7cee3ff9df1ee963977d6c26c00b23f8fe670fab481283ed4f9", corpus: false)

    private static func resource(_ name: String, _ bytes: Int, _ hash: String, corpus: Bool) -> MandarinDictionaryResource {
        let base = corpus
            ? "https://raw.githubusercontent.com/amzxyz/rime-wanxiang/\(corpusCommit)/dicts/"
            : "https://raw.githubusercontent.com/BYVoid/OpenCC/\(mappingCommit)/data/dictionary/"
        return .init(filename: name, bytes: bytes, sha256: hash, downloadURL: URL(string: base + name)!)
    }

    public static func compile(jichuURL: URL, ziURL: URL, mappingURLs: MandarinSimplifiedMappingURLs,
                               destinationURL: URL,
                               isCancelled: @escaping () -> Bool = { false },
                               progress: (MandarinCompilationProgress) -> Void = { _ in }) throws -> MandarinDictionaryCompilationStats {
        let specifications: [MandarinSourceSpecification] = [
            .init(resource: jichu, url: jichuURL, header: ["# Rime dictionary", "# encoding: utf-8", "# ------基础词库-------", "---", "name: jichu", "version: \"LTS\"", "sort: by_weight", "..."], expectedValidRows: 1_453_824,
                  quarantined: [1_288_863: "把玩了一阵\tbǎ wán le yí zhèn", 1_359_721: "西汉前少帝\txī hàn qián shǎo dì", 1_453_762: "宜乎百姓之谓我爱也\tyí hū bǎi xìng zhī wèi wǒ ài yě\t10s"]),
            .init(resource: zi, url: ziURL, header: ["# Rime dictionary", "# encoding: utf-8", "#https://github.com/amzxyz/RIME-LMDG", "---", "name: zi", "version: \"LTS\"", "sort: by_weight", "..."], expectedValidRows: 51_050, quarantined: [:])
        ]
        return try compileVerified(sources: specifications,
            mappingFiles: [(characters, mappingURLs.characters), (phrases, mappingURLs.phrases),
                           (compatibility, mappingURLs.compatibility)], destinationURL: destinationURL,
            isCancelled: isCancelled, progress: progress)
    }

    /// Internal seam for clearly synthetic tests only. The public API above pins
    /// hashes, row counts, fixed headers and exact quarantined source lines.
    static func compileVerified(sources: [MandarinSourceSpecification],
                                mappingFiles: [(MandarinDictionaryResource, URL)], destinationURL: URL,
                                isCancelled: @escaping () -> Bool = { false },
                                progress: (MandarinCompilationProgress) -> Void = { _ in },
                                now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws -> MandarinDictionaryCompilationStats {
        do {
            return try compileBody(sources: sources, mappingFiles: mappingFiles, destinationURL: destinationURL,
                                   isCancelled: isCancelled, progress: progress, now: now)
        } catch {
            // Includes SQLITE_INTERRUPT from indexing/counting, not only row loops.
            if isCancelled() { throw MandarinDictionaryError.cancelled }
            throw error
        }
    }

    private static func compileBody(sources: [MandarinSourceSpecification],
                                    mappingFiles: [(MandarinDictionaryResource, URL)], destinationURL: URL,
                                    isCancelled: @escaping () -> Bool,
                                    progress: (MandarinCompilationProgress) -> Void,
                                    now: () -> TimeInterval) throws -> MandarinDictionaryCompilationStats {
        if isCancelled() { throw MandarinDictionaryError.cancelled }
        progress(.verifyingSources)
        guard destinationURL.isFileURL, !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw MandarinDictionaryError.destinationExists
        }
        // Verify ALL inputs before creating a database. Parsing also rehashes the
        // actual streamed bytes to detect changes between verification and use.
        for source in sources { try verify(source.resource, at: source.url, isCancelled: isCancelled) }
        guard mappingFiles.count == 3 else { throw MandarinDictionaryError.invalidSource("mapping set") }
        var mappingData: [Data] = []
        for (resource, url) in mappingFiles {
            try verify(resource, at: url, isCancelled: isCancelled)
            let mappingHandle = try FileHandle(forReadingFrom: url)
            let data: Data
            do {
                data = try mappingHandle.read(upToCount: resource.bytes + 1) ?? Data()
                try mappingHandle.close()
            } catch {
                try? mappingHandle.close()
                throw error
            }
            guard data.count == resource.bytes, hash(data) == resource.sha256 else {
                throw MandarinDictionaryError.invalidSource(resource.filename)
            }
            mappingData.append(data)
        }
        progress(.preparingMappings)
        if isCancelled() { throw MandarinDictionaryError.cancelled }
        let simplified = try MandarinSimplifiedSubset(characters: mappingData[0], phrases: mappingData[1], compatibility: mappingData[2])
        // Reserve the caller's unpublished destination exclusively. Never open
        // or delete an unrelated file that appeared while inputs were verified.
        try Data().write(to: destinationURL, options: .withoutOverwriting)
        var database: OpaquePointer?
        var completed = false
        defer {
            if let database { sqlite3_close(database) }
            if !completed {
                try? FileManager.default.removeItem(at: destinationURL)
                try? FileManager.default.removeItem(atPath: destinationURL.path + "-journal")
            }
        }
        guard sqlite3_open_v2(destinationURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = database else { throw MandarinDictionaryError.database("create failed") }
        let cancellation = MandarinCompilationCancellation(isCancelled)
        sqlite3_progress_handler(db, 1_000, { context in
            guard let context else { return 0 }
            return Unmanaged<MandarinCompilationCancellation>.fromOpaque(context).takeUnretainedValue().check() ? 1 : 0
        }, Unmanaged.passUnretained(cancellation).toOpaque())
        defer {
            sqlite3_progress_handler(db, 0, nil, nil)
            withExtendedLifetime(cancellation) {}
        }
        try MandarinSQLite.execute(db, "PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA cache_size=-4096; PRAGMA temp_store=FILE; PRAGMA trusted_schema=OFF;")
        try MandarinSQLite.execute(db, "PRAGMA application_id=\(MandarinSQLite.applicationID); PRAGMA user_version=\(MandarinDictionaryIndex.schemaVersion);")
        try MandarinSQLite.execute(db, MandarinSQLite.schema["metadata"]!)
        try MandarinSQLite.execute(db, MandarinSQLite.schema["entries"]!)
        try MandarinSQLite.execute(db, "BEGIN IMMEDIATE")
        let insert = try MandarinSQLite.prepare(db,
            "INSERT INTO entries(flat,reading,tones,output,weight) VALUES(?,?,?,?,?) ON CONFLICT(reading,tones,output) DO UPDATE SET weight=MAX(entries.weight,excluded.weight)")
        defer { sqlite3_finalize(insert) }
        var rows: [String: Int] = [:], quarantined: [String: [Int]] = [:]
        var changed = 0
        let totalRows = sources.reduce(0) { $0 + $1.expectedValidRows }
        var processedRows = 0
        var lastProgressTime = now()
        progress(.rows(processed: 0, total: totalRows))
        for source in sources {
            let reader = try MandarinUTF8Lines(url: source.url)
            var valid = 0, seenQuarantine: [Int] = []
            while let (lineNumber, line) = try reader.next() {
                if isCancelled() { throw MandarinDictionaryError.cancelled }
                guard reader.byteCount <= source.resource.bytes else {
                    throw MandarinDictionaryError.invalidSource(source.resource.filename)
                }
                if lineNumber <= source.header.count {
                    guard line == source.header[lineNumber - 1] else {
                        throw MandarinDictionaryError.invalidFormat(source: source.resource.filename, line: lineNumber)
                    }
                    continue
                }
                if let audited = source.quarantined[lineNumber] {
                    guard line == audited else {
                        throw MandarinDictionaryError.invalidFormat(source: source.resource.filename, line: lineNumber)
                    }
                    seenQuarantine.append(lineNumber)
                    continue
                }
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count == 3, !fields[0].isEmpty, fields[0].unicodeScalars.count <= 256,
                      !fields[2].isEmpty, fields[2].utf8.allSatisfy({ (48...57).contains($0) }),
                      let weight = Int64(fields[2]), weight >= 0,
                      !line.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 13 }) else {
                    throw MandarinDictionaryError.invalidFormat(source: source.resource.filename, line: lineNumber)
                }
                try autoreleasepool {
                    let phonetics: (syllables: [String], tones: [Int])
                    do { phonetics = try MandarinPinyinReading.sourceSyllables(String(fields[1])) }
                    catch { throw MandarinDictionaryError.invalidFormat(source: source.resource.filename, line: lineNumber) }
                    let original = String(fields[0])
                    let output = simplified.convert(original)
                    if Data(original.utf8) != Data(output.utf8) { changed += 1 }
                    sqlite3_reset(insert); sqlite3_clear_bindings(insert)
                    try MandarinSQLite.bind(insert, 1, phonetics.syllables.joined())
                    try MandarinSQLite.bind(insert, 2, phonetics.syllables.joined(separator: "'"))
                    try MandarinSQLite.bind(insert, 3, phonetics.tones.map(String.init).joined())
                    try MandarinSQLite.bind(insert, 4, output)
                    guard sqlite3_bind_int64(insert, 5, weight) == SQLITE_OK, sqlite3_step(insert) == SQLITE_DONE else {
                        throw MandarinSQLite.error(db)
                    }
                    valid += 1
                    processedRows += 1
                }
                // Count actual successfully inserted/combined rows. Sample the
                // clock only every 1024 rows; emit at most ten row updates/sec.
                if processedRows % 1_024 == 0 {
                    let time = now()
                    if time - lastProgressTime >= 0.1 {
                        progress(.rows(processed: processedRows, total: totalRows))
                        lastProgressTime = time
                    }
                }
            }
            guard reader.lineNumber >= source.header.count, reader.byteCount == source.resource.bytes,
                  reader.digest == source.resource.sha256, valid == source.expectedValidRows,
                  seenQuarantine.sorted() == source.quarantined.keys.sorted() else {
                throw MandarinDictionaryError.invalidSource(source.resource.filename)
            }
            rows[source.resource.filename] = valid
            quarantined[source.resource.filename] = seenQuarantine
        }
        if isCancelled() { throw MandarinDictionaryError.cancelled }
        progress(.rows(processed: processedRows, total: totalRows))
        progress(.indexing)
        let unique = try MandarinSQLite.integer(db, "SELECT COUNT(*) FROM entries")
        let stats = MandarinDictionaryCompilationStats(compilerVersion: MandarinDictionaryIndex.compilerVersion,
            sourceRows: rows, quarantinedLines: quarantined, simplifiedChangedRows: changed,
            uniqueRows: unique, combinedRows: rows.values.reduce(0, +) - unique,
            outputPolicy: "simplified-conservative-subset-not-full-t2s")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let statsJSON = String(decoding: try encoder.encode(stats), as: UTF8.self)
        let sourceJSON = String(decoding: try encoder.encode(sources.map { "\($0.resource.filename):\($0.resource.bytes):\($0.resource.sha256)" }), as: UTF8.self)
        let mappingsJSON = String(decoding: try encoder.encode(mappingFiles.map { "\($0.0.filename):\($0.0.bytes):\($0.0.sha256)" }), as: UTF8.self)
        let metadata = try MandarinSQLite.prepare(db, "INSERT INTO metadata(key,value) VALUES(?,?)")
        defer { sqlite3_finalize(metadata) }
        let values = ["engineABI": MandarinDictionaryIndex.engineABI,
                      "compilerVersion": MandarinDictionaryIndex.compilerVersion,
                      "outputPolicy": stats.outputPolicy, "statistics": statsJSON,
                      "sources": sourceJSON, "mappings": mappingsJSON,
                      "corpusCommit": corpusCommit, "mappingCommit": mappingCommit,
                      "attribution": "Wanxiang / 万象词库 / 万象拼音 — amzxyz — CC BY 4.0; simplified adaptation uses OpenCC Apache-2.0. Original notices and modification details must accompany the pack."]
        for key in values.keys.sorted() {
            sqlite3_reset(metadata); sqlite3_clear_bindings(metadata)
            try MandarinSQLite.bind(metadata, 1, key)
            try MandarinSQLite.bind(metadata, 2, values[key]!)
            guard sqlite3_step(metadata) == SQLITE_DONE else { throw MandarinSQLite.error(db) }
        }
        try MandarinSQLite.execute(db, "COMMIT")
        try MandarinSQLite.execute(db, MandarinSQLite.schema["entries_lookup"]!)
        if isCancelled() { throw MandarinDictionaryError.cancelled }
        progress(.finalCheck)
        if isCancelled() { throw MandarinDictionaryError.cancelled }
        // LIFO defers finalize metadata/insert, then close the database before
        // returning. No WAL/sidecar is needed by the caller.
        completed = true
        return stats
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func verify(_ resource: MandarinDictionaryResource, at url: URL,
                               isCancelled: () -> Bool) throws {
        guard url.isFileURL else { throw MandarinDictionaryError.invalidSource(resource.filename) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256(), count = 0
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            if isCancelled() { throw MandarinDictionaryError.cancelled }
            count += chunk.count
            guard count <= resource.bytes else { throw MandarinDictionaryError.invalidSource(resource.filename) }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == resource.bytes, digest == resource.sha256 else {
            throw MandarinDictionaryError.invalidSource(resource.filename)
        }
    }
}

struct MandarinSourceSpecification {
    let resource: MandarinDictionaryResource
    let url: URL
    let header: [String]
    let expectedValidRows: Int
    let quarantined: [Int: String]
}

/// Bounded UTF-8 line reader. LF is required by the pinned upstream format; no
/// replacement-character decoding, silent blank-line skip or arbitrary YAML.
private final class MandarinUTF8Lines {
    private let handle: FileHandle
    private var buffer = Data()
    private var offset = 0
    private var finished = false
    private var hasher = SHA256()
    private(set) var byteCount = 0
    private(set) var lineNumber = 0
    var digest: String { let copy = hasher; return copy.finalize().map { String(format: "%02x", $0) }.joined() }

    init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
    deinit { try? handle.close() }
    func next() throws -> (Int, String)? {
        while true {
            if let newline = buffer[offset...].firstIndex(of: 10) {
                let bytes = buffer[offset..<newline]
                guard bytes.count <= 4096, let line = String(data: bytes, encoding: .utf8) else {
                    throw MandarinDictionaryError.invalidFormat(source: "UTF-8", line: lineNumber + 1)
                }
                offset = newline + 1
                lineNumber += 1
                return (lineNumber, line)
            }
            guard buffer.count - offset <= 4096 else {
                throw MandarinDictionaryError.invalidFormat(source: "line length", line: lineNumber + 1)
            }
            if finished {
                guard offset < buffer.count else { return nil }
                guard let line = String(data: buffer[offset...], encoding: .utf8) else {
                    throw MandarinDictionaryError.invalidFormat(source: "UTF-8", line: lineNumber + 1)
                }
                buffer.removeAll(keepingCapacity: true); offset = 0; lineNumber += 1
                return (lineNumber, line)
            }
            // Compact only once per chunk, not once per dictionary row.
            if offset > 0 { buffer = Data(buffer[offset...]); offset = 0 }
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty { finished = true }
            else { byteCount += chunk.count; hasher.update(data: chunk); buffer.append(chunk) }
        }
    }
}

/// Deliberately conservative subset, not full upstream t2s. Default first mapping
/// only: compatibility -> longest phrase -> character mappings. No custom-output
/// API is exposed; this is applied solely while compiling the pinned vocabulary.
private struct MandarinSimplifiedSubset {
    let characters: [Data: String]
    let phrases: [Data: String]
    let compatibility: [Data: String]
    let maximumPhraseLength: Int

    init(characters: Data, phrases: Data, compatibility: Data) throws {
        self.characters = try Self.parse(characters)
        self.phrases = try Self.parse(phrases)
        self.compatibility = try Self.parse(compatibility)
        maximumPhraseLength = self.phrases.keys.map { String(decoding: $0, as: UTF8.self).unicodeScalars.count }.max() ?? 0
    }
    private static func parse(_ data: Data) throws -> [Data: String] {
        guard data.count <= 200_000, let text = String(data: data, encoding: .utf8) else {
            throw MandarinDictionaryError.invalidSource("OpenCC mapping")
        }
        var result: [Data: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty,
                  let output = fields[1].split(separator: " ").first, !output.isEmpty,
                  result[Data(fields[0].utf8)] == nil else { throw MandarinDictionaryError.invalidSource("OpenCC row") }
            result[Data(fields[0].utf8)] = String(output)
        }
        return result
    }
    func convert(_ source: String) -> String {
        let compatible = source.unicodeScalars.map { compatibility[Data(String($0).utf8)] ?? String($0) }.joined()
        let scalars = Array(compatible.unicodeScalars)
        var result = "", position = 0
        while position < scalars.count {
            var replacement: String?, consumed = 1
            let maxLength = min(maximumPhraseLength, scalars.count - position)
            if maxLength > 0 {
                for length in stride(from: maxLength, through: 1, by: -1) {
                    let key = scalars[position..<(position + length)].map(String.init).joined()
                    if let phrase = phrases[Data(key.utf8)] { replacement = phrase; consumed = length; break }
                }
            }
            let selected = replacement ?? String(scalars[position])
            result += selected.unicodeScalars.map { characters[Data(String($0).utf8)] ?? String($0) }.joined()
            position += consumed
        }
        return result
    }
}
