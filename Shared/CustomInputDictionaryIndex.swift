import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CustomInputDictionaryIndexError: Error, Equatable {
    case invalidSnapshot
    case invalidLookup
    case missingIndex
    case invalidDatabase
    case fileTooLarge
    case cancelled
    case revisionConflict(expected: UUID?, actual: UUID?)
    case sqlite(code: Int32)
    case publicationFailed(code: Int32)
}

public struct CustomInputDictionaryIndexedCandidate: Equatable, Sendable {
    public let output: String
    public let weight: Int

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.weight == rhs.weight && lhs.output.utf8.elementsEqual(rhs.output.utf8)
    }
}

public struct CustomInputDictionaryIndexCompilation: Equatable, Sendable {
    public let revision: UUID
    public let enabledSourceEntries: Int
    public let indexedCandidates: Int
    public let indexedReadings: Int
}

/// App-worker compiler ONLY. The keyboard opens the compiled index below, never
/// the source snapshot/JSON. All mode/readings are already engine-normalized;
/// mode IDs remain injected strings, not assumptions about an engine's scheme.
public enum CustomInputDictionaryIndexCompiler {
    /// nil means no published index may exist. For replacement, pass the revision
    /// observed before scheduling compilation. Competing compilations cannot
    /// silently overwrite a newer publication. Store and index publication are
    /// separate: the app must schedule/retry compilation of its CURRENT snapshot.
    /// App-store rebuilds must set requireCurrentSource to guard the source through
    /// publication; standalone compilation of supplied snapshots leaves it false.
    @discardableResult
    public static func compile(snapshot: CustomInputDictionarySnapshot, directory: URL,
                               expectedPublishedRevision: UUID? = nil,
                               requireCurrentSource: Bool = false,
                               isCancelled: () -> Bool = { false }) throws -> CustomInputDictionaryIndexCompilation {
        guard directory.isFileURL else { throw CustomInputDictionaryIndexError.invalidSnapshot }
        let groups = try aggregate(snapshot, isCancelled: isCancelled)
        let directory = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appendingPathComponent(".custom-input-index-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-journal", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: stage.path + suffix) }
        }
        var handle: OpaquePointer?
        defer { if let handle = handle { sqlite3_close(handle) } }
        let openStatus = sqlite3_open_v2(stage.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard openStatus == SQLITE_OK, let db = handle else { throw CustomInputDictionaryIndexError.sqlite(code: openStatus) }
        try CustomInputIndexSQLite.execute(db, "PRAGMA page_size=4096; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA cache_size=-2048; PRAGMA mmap_size=0; PRAGMA trusted_schema=OFF;")
        try CustomInputIndexSQLite.execute(db, "PRAGMA max_page_count=\(CustomInputDictionaryIndex.maximumFileBytes / CustomInputIndexSQLite.pageBytes); PRAGMA application_id=\(CustomInputIndexSQLite.applicationID); PRAGMA user_version=1;")
        for name in CustomInputIndexSQLite.schema.keys.sorted() { try CustomInputIndexSQLite.execute(db, CustomInputIndexSQLite.schema[name]!) }
        let stats = try populate(db, snapshot: snapshot, groups: groups, isCancelled: isCancelled)
        // Full integrity work happens ONLY app-side, before closing and publishing.
        guard try CustomInputIndexSQLite.singleText(db, "PRAGMA quick_check(1)") == "ok",
              try CustomInputIndexSQLite.integer(db, "SELECT COUNT(*) FROM entries") == stats.indexedCandidates else {
            throw CustomInputDictionaryIndexError.invalidDatabase
        }
        let metadata = try CustomInputIndexSQLite.validate(db)
        guard metadata.revision == snapshot.revision && metadata.rows == stats.indexedCandidates else {
            throw CustomInputDictionaryIndexError.invalidDatabase
        }
        let closeStatus = sqlite3_close(db)
        guard closeStatus == SQLITE_OK else { throw CustomInputDictionaryIndexError.sqlite(code: closeStatus) }
        handle = nil
        try CustomInputIndexSQLite.checkFile(stage)
        guard !FileManager.default.fileExists(atPath: stage.path + "-wal"),
              !FileManager.default.fileExists(atPath: stage.path + "-journal"),
              !FileManager.default.fileExists(atPath: stage.path + "-shm") else {
            throw CustomInputDictionaryIndexError.invalidDatabase
        }
        if requireCurrentSource {
            // Keep the validated source revision stable through the index CAS and
            // rename. A source edit during staging must not publish stale words.
            try CustomInputDictionarySnapshotReader(directory: directory).withCurrentRevision(snapshot.revision) {
                try publish(stage: stage, directory: directory, expected: expectedPublishedRevision, isCancelled: isCancelled)
            }
        } else {
            try publish(stage: stage, directory: directory, expected: expectedPublishedRevision, isCancelled: isCancelled)
        }
        return stats // No fallible work after the atomic rename.
    }

    private struct ReadingKey: Hashable {
        let mode: Data
        let reading: Data
    }
    private struct Groups {
        var values: [ReadingKey: [Data: Int]] = [:]
        var enabledSourceEntries = 0
    }

    private static func aggregate(_ snapshot: CustomInputDictionarySnapshot, isCancelled: () -> Bool) throws -> Groups {
        guard snapshot.collections.count <= CustomInputDictionaryLimits.totalCollections else { throw CustomInputDictionaryIndexError.invalidSnapshot }
        var result = Groups()
        var ids = Set<UUID>()
        var total = 0
        for collection in snapshot.collections {
            if isCancelled() { throw CustomInputDictionaryIndexError.cancelled }
            total += collection.entries.count
            guard total <= CustomInputDictionaryLimits.totalEntries, ids.insert(collection.id).inserted,
                  CustomInputDictionaryValidation.fieldIssue(collection.name, reading: false) == nil,
                  CustomInputDictionaryValidation.fieldIssue(collection.modeID, reading: true) == nil else {
                throw CustomInputDictionaryIndexError.invalidSnapshot
            }
            let mode = Data(collection.modeID.utf8)
            var seen = Set<CustomInputDictionaryEntryIdentity>()
            for entry in collection.entries {
                if isCancelled() { throw CustomInputDictionaryIndexError.cancelled }
                guard CustomInputDictionaryValidation.structurallyValid(entry), seen.insert(entry.identity).inserted else {
                    throw CustomInputDictionaryIndexError.invalidSnapshot
                }
                guard collection.enabled else { continue }
                result.enabledSourceEntries += 1
                let key = ReadingKey(mode: mode, reading: Data(entry.reading.utf8))
                let output = Data(entry.output.utf8)
                let old = result.values[key]?[output] ?? -1
                result.values[key, default: [:]][output] = max(old, entry.weight)
            }
        }
        return result
    }

    private static func populate(_ db: OpaquePointer, snapshot: CustomInputDictionarySnapshot, groups: Groups,
                                 isCancelled: () -> Bool) throws -> CustomInputDictionaryIndexCompilation {
        try CustomInputIndexSQLite.execute(db, "BEGIN IMMEDIATE")
        let insert = try CustomInputIndexSQLite.prepare(db, "INSERT INTO entries(mode,reading,weight,output) VALUES(?,?,?,?)")
        defer { sqlite3_finalize(insert) }
        var rows = 0
        let keys = groups.values.keys.sorted {
            $0.mode == $1.mode ? $0.reading.lexicographicallyPrecedes($1.reading) : $0.mode.lexicographicallyPrecedes($1.mode)
        }
        for key in keys {
            if isCancelled() { throw CustomInputDictionaryIndexError.cancelled }
            // Exact UTF-8 output dedup, maximum weight, NEVER sum weights. A
            // binary output tie-break is deterministic across collection order.
            let candidates = groups.values[key]!.sorted {
                $0.value == $1.value ? $0.key.lexicographicallyPrecedes($1.key) : $0.value > $1.value
            }.prefix(CustomInputDictionaryIndex.maximumCandidates)
            for candidate in candidates {
                if isCancelled() { throw CustomInputDictionaryIndexError.cancelled }
                sqlite3_reset(insert); sqlite3_clear_bindings(insert)
                try CustomInputIndexSQLite.bind(insert, 1, key.mode)
                try CustomInputIndexSQLite.bind(insert, 2, key.reading)
                guard sqlite3_bind_int(insert, 3, Int32(candidate.value)) == SQLITE_OK else { throw CustomInputIndexSQLite.error(db) }
                try CustomInputIndexSQLite.bind(insert, 4, candidate.key)
                guard sqlite3_step(insert) == SQLITE_DONE else { throw CustomInputIndexSQLite.error(db) }
                rows += 1
            }
        }
        let metadata = try CustomInputIndexSQLite.prepare(db, "INSERT INTO metadata(revision,row_count) VALUES(?,?)")
        defer { sqlite3_finalize(metadata) }
        try CustomInputIndexSQLite.bind(metadata, 1, Data(snapshot.revision.uuidString.utf8))
        guard sqlite3_bind_int(metadata, 2, Int32(rows)) == SQLITE_OK,
              sqlite3_step(metadata) == SQLITE_DONE else { throw CustomInputIndexSQLite.error(db) }
        if isCancelled() { throw CustomInputDictionaryIndexError.cancelled }
        try CustomInputIndexSQLite.execute(db, "COMMIT")
        return .init(revision: snapshot.revision, enabledSourceEntries: groups.enabledSourceEntries,
                     indexedCandidates: rows, indexedReadings: keys.count)
    }

    private static let publicationLock = NSLock()

    private static func publish(stage: URL, directory: URL, expected: UUID?, isCancelled: () -> Bool) throws {
        publicationLock.lock()
        defer { publicationLock.unlock() }
        let target = directory.appendingPathComponent(CustomInputDictionaryIndex.filename)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { location in
            result = Result {
                let actual = try CustomInputIndexSQLite.existingRevision(location)
                guard actual == expected else { throw CustomInputDictionaryIndexError.revisionConflict(expected: expected, actual: actual) }
                if isCancelled() { throw CustomInputDictionaryIndexError.cancelled }
                // Same directory/filesystem. POSIX rename atomically replaces the
                // pathname while already-open immutable readers retain the inode.
                guard rename(stage.path, location.path) == 0 else {
                    throw CustomInputDictionaryIndexError.publicationFailed(code: errno)
                }
            }
        }
        if let result = result { try result.get(); return }
        if let coordinationError = coordinationError { throw coordinationError }
        throw CustomInputDictionaryIndexError.invalidDatabase
    }
}

/// Bounded keyboard reader. No snapshot/JSON decoding, importer, normalizer,
/// network, writes or learned history. Exactly one covering B-tree range supplies
/// at most 48 rows; no full-table scan/grouping/sort is required at lookup time.
/// Lock-serialized synchronous I/O: the owner supplies the appropriate executor.
public final class CustomInputDictionaryIndex {
    public static let filename = "custom-input-dictionary-index-v1.sqlite3"
    public static let maximumCandidates = 48
    /// Each row has <=3*256*4 bytes of UTF-8 plus <64 record bytes. With 4096-byte
    /// pages it needs at most one overflow page; conservatively charge another
    /// complete B-tree page per row, plus 256 pages for metadata/ancestors.
    /// This is a disk bound, NOT a request to read/map this many bytes into RAM.
    public static let maximumFileBytes = (CustomInputDictionaryLimits.totalEntries * 2 + 256) * 4096

    public let revision: UUID
    public let indexedCandidateCount: Int
    private let url: URL
    private let database: OpaquePointer
    private let lock = NSLock()

    /// A validated publication revision, or nil ONLY for an absent index.
    /// Corruption, incompatible schema and I/O errors are never treated as absence.
    /// App recovery uses this off-main; it does not read the source JSON.
    public static func publishedRevision(directory: URL) throws -> UUID? {
        try CustomInputIndexSQLite.existingRevision(directory.standardizedFileURL.appendingPathComponent(filename))
    }

    public convenience init(directory: URL) throws {
        try self.init(url: directory.standardizedFileURL.appendingPathComponent(Self.filename))
    }

    private init(url: URL) throws {
        let db = try CustomInputIndexSQLite.openReadOnly(url)
        do {
            let metadata = try CustomInputIndexSQLite.validate(db)
            revision = metadata.revision
            indexedCandidateCount = metadata.rows
        } catch {
            sqlite3_close(db)
            throw error
        }
        database = db
        self.url = url
    }

    deinit { sqlite3_close(database) }

    /// Explicit invalidation: opens the CURRENT published inode. This instance
    /// remains immutable/readable at its old revision. Compare revisions and swap
    /// at a safe composition boundary, invalidating stale candidate tokens.
    public func reopened() throws -> CustomInputDictionaryIndex { try .init(url: url) }

    /// Pass the engine-normalized lookup reading, never normalize output. Limit
    /// is clamped to 48; zero returns []. Negative limits/invalid fields fail.
    /// The integration adapter creates source=.custom candidates and consumes
    /// ORIGINAL request input scalars, not this normalized reading's length.
    public func lookup(modeID: String, normalizedReading: String, limit: Int = 48) throws -> [CustomInputDictionaryIndexedCandidate] {
        guard limit >= 0,
              modeID.utf8.prefix(1025).count <= 1024,
              normalizedReading.utf8.prefix(1025).count <= 1024,
              CustomInputDictionaryValidation.fieldIssue(modeID, reading: true) == nil,
              CustomInputDictionaryValidation.fieldIssue(normalizedReading, reading: true) == nil else {
            throw CustomInputDictionaryIndexError.invalidLookup
        }
        if limit == 0 { return [] }
        lock.lock(); defer { lock.unlock() }
        let statement = try CustomInputIndexSQLite.prepare(database,
            "SELECT output,weight FROM entries WHERE mode=? AND reading=? ORDER BY weight DESC,output LIMIT ?")
        defer { sqlite3_finalize(statement) }
        try CustomInputIndexSQLite.bind(statement, 1, Data(modeID.utf8))
        try CustomInputIndexSQLite.bind(statement, 2, Data(normalizedReading.utf8))
        let count = min(limit, Self.maximumCandidates)
        guard sqlite3_bind_int(statement, 3, Int32(count)) == SQLITE_OK else { throw CustomInputIndexSQLite.error(database) }
        var candidates: [CustomInputDictionaryIndexedCandidate] = []
        var seen = Set<Data>()
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard candidates.count < count,
                  let bytes = CustomInputIndexSQLite.blob(statement, 0, maximumBytes: 1024),
                  let output = String(data: bytes, encoding: .utf8),
                  CustomInputDictionaryValidation.fieldIssue(output, reading: false) == nil,
                  sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
                  seen.insert(bytes).inserted else { throw CustomInputDictionaryIndexError.invalidDatabase }
            let weight = sqlite3_column_int64(statement, 1)
            guard (0...Int64(CustomInputDictionaryLimits.maximumWeight)).contains(weight) else { throw CustomInputDictionaryIndexError.invalidDatabase }
            candidates.append(.init(output: output, weight: Int(weight)))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CustomInputIndexSQLite.error(database) }
        return candidates
    }
}

private enum CustomInputIndexSQLite {
    static let pageBytes = 4096
    static let applicationID = 0x55434449
    static let schema = [
        "metadata": "CREATE TABLE metadata(revision BLOB NOT NULL CHECK(typeof(revision)='blob' AND length(revision)=36),row_count INTEGER NOT NULL CHECK(row_count BETWEEN 0 AND 50000))",
        // Primary-key order IS the lookup index; no duplicated output/reading
        // payload in a secondary index. Compiler guarantees unique output/pair.
        "entries": "CREATE TABLE entries(mode BLOB NOT NULL CHECK(typeof(mode)='blob' AND length(mode) BETWEEN 1 AND 1024),reading BLOB NOT NULL CHECK(typeof(reading)='blob' AND length(reading) BETWEEN 1 AND 1024),weight INTEGER NOT NULL CHECK(weight BETWEEN 0 AND 10000),output BLOB NOT NULL CHECK(typeof(output)='blob' AND length(output) BETWEEN 1 AND 1024),PRIMARY KEY(mode,reading,weight DESC,output)) WITHOUT ROWID"
    ]
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func error(_ db: OpaquePointer) -> CustomInputDictionaryIndexError {
        // SQLite diagnostics may include private values; expose numeric codes only.
        .sqlite(code: sqlite3_extended_errcode(db))
    }

    static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error(db) }
    }

    static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement = statement else { throw error(db) }
        return statement
    }

    static func bind(_ statement: OpaquePointer, _ index: Int32, _ data: Data) throws {
        let status = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
        }
        guard status == SQLITE_OK else { throw CustomInputDictionaryIndexError.sqlite(code: status) }
    }

    static func blob(_ statement: OpaquePointer, _ column: Int32, maximumBytes: Int) -> Data? {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= maximumBytes, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    static func integer(_ db: OpaquePointer, _ sql: String) throws -> Int {
        let statement = try prepare(db, sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else { throw error(db) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    static func singleText(_ db: OpaquePointer, _ sql: String) throws -> String {
        let statement = try prepare(db, sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              sqlite3_column_bytes(statement, 0) <= 64, let bytes = sqlite3_column_text(statement, 0) else { throw error(db) }
        return String(cString: bytes)
    }

    static func checkFile(_ url: URL) throws {
        guard url.isFileURL else { throw CustomInputDictionaryIndexError.invalidDatabase }
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            throw CustomInputDictionaryIndexError.missingIndex
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CustomInputDictionaryIndexError.invalidDatabase }
        guard let size = values.fileSize, size >= pageBytes, size <= CustomInputDictionaryIndex.maximumFileBytes else { throw CustomInputDictionaryIndexError.fileTooLarge }
    }

    static func openReadOnly(_ url: URL) throws -> OpaquePointer {
        try checkFile(url)
        var handle: OpaquePointer?
        // immutable=1 is valid because publication ALWAYS replaces an inode;
        // nobody edits a published database. No journals/locks/reopens are needed.
        let status = sqlite3_open_v2(url.absoluteString + "?immutable=1", &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI, nil)
        guard status == SQLITE_OK, let db = handle else {
            if let handle = handle { sqlite3_close(handle) }
            throw CustomInputDictionaryIndexError.sqlite(code: status)
        }
        do {
            sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 4096)
            sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 4096)
            sqlite3_limit(db, SQLITE_LIMIT_ATTACHED, 0)
            sqlite3_busy_timeout(db, 100)
            try execute(db, "PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; PRAGMA cache_size=-256; PRAGMA mmap_size=0;")
            guard sqlite3_db_readonly(db, "main") == 1 else { throw CustomInputDictionaryIndexError.invalidDatabase }
        } catch { sqlite3_close(db); throw error }
        return db
    }

    static func validate(_ db: OpaquePointer) throws -> (revision: UUID, rows: Int) {
        guard try integer(db, "PRAGMA application_id") == applicationID,
              try integer(db, "PRAGMA user_version") == 1,
              try integer(db, "PRAGMA page_size") == pageBytes,
              try integer(db, "PRAGMA page_count") <= CustomInputDictionaryIndex.maximumFileBytes / pageBytes,
              try singleText(db, "PRAGMA journal_mode") == "delete" else { throw CustomInputDictionaryIndexError.invalidDatabase }
        var objects: [String: String] = [:]
        let statement = try prepare(db, "SELECT name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' LIMIT 3")
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard objects.count < 2,
                  sqlite3_column_type(statement, 0) == SQLITE_TEXT,
                  sqlite3_column_bytes(statement, 0) <= 16,
                  sqlite3_column_type(statement, 1) == SQLITE_TEXT,
                  sqlite3_column_bytes(statement, 1) <= 1024,
                  let name = sqlite3_column_text(statement, 0), let sql = sqlite3_column_text(statement, 1) else {
                throw CustomInputDictionaryIndexError.invalidDatabase
            }
            objects[String(cString: name)] = String(cString: sql)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE, objects == schema else { throw CustomInputDictionaryIndexError.invalidDatabase }
        let metadata = try prepare(db, "SELECT revision,row_count FROM metadata LIMIT 2")
        defer { sqlite3_finalize(metadata) }
        guard sqlite3_step(metadata) == SQLITE_ROW,
              let bytes = blob(metadata, 0, maximumBytes: 36), bytes.count == 36,
              let string = String(data: bytes, encoding: .utf8), let revision = UUID(uuidString: string),
              sqlite3_column_type(metadata, 1) == SQLITE_INTEGER else { throw CustomInputDictionaryIndexError.invalidDatabase }
        let rows = sqlite3_column_int64(metadata, 1)
        guard (0...Int64(CustomInputDictionaryLimits.totalEntries)).contains(rows),
              sqlite3_step(metadata) == SQLITE_DONE else { throw CustomInputDictionaryIndexError.invalidDatabase }
        return (revision, Int(rows))
    }

    static func existingRevision(_ url: URL) throws -> UUID? {
        do { try checkFile(url) }
        catch CustomInputDictionaryIndexError.missingIndex { return nil }
        let db = try openReadOnly(url)
        defer { sqlite3_close(db) }
        return try validate(db).revision
    }
}
