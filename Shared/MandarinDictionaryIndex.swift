import Foundation
import SQLite3

public enum MandarinDictionaryError: Error, Equatable {
    case invalidReading
    case invalidSource(String)
    case invalidFormat(source: String, line: Int)
    case incompatibleDatabase
    case database(String)
    case destinationExists
    case cancelled
}

public struct MandarinDictionaryCandidate: Equatable, Sendable {
    public let text: String
    /// Canonical apostrophe-separated, tone-free reading; v means ü.
    public let reading: String
    public let tones: [Int]
    public let score: Int
}

public struct MandarinDictionaryPage: Equatable, Sendable {
    public let candidates: [MandarinDictionaryCandidate]
    /// Offset in the deduplicated matching results of the same capped search.
    public let nextOffset: Int?
    /// At most 512 source records are examined, even when more exist.
    public let searchWasCapped: Bool
}

/// Runtime reader ONLY. No network, imports, compilation, schema execution, or
/// user-supplied SQL. The pack installer must authenticate the compiled artifact
/// before supplying its URL. A schema/ABI check is defense-in-depth, not a signature.
/// Synchronous and lock-serialized; owner decides the off-main lookup executor.
public final class MandarinDictionaryIndex {
    public static let schemaVersion = 1
    public static let engineABI = "uniboard-pinyin-1"
    public static let compilerVersion = "wanxiang-simplified-subset-1"
    public static let maximumExaminedRows = 512
    public static let maximumCandidates = 48

    private var database: OpaquePointer?
    private let lock = NSLock()

    public init(url: URL) throws {
        guard url.isFileURL else { throw MandarinDictionaryError.incompatibleDatabase }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw MandarinDictionaryError.incompatibleDatabase
        }
        database = handle
        do {
            sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 8192)
            sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 8192)
            sqlite3_limit(handle, SQLITE_LIMIT_ATTACHED, 0)
            sqlite3_busy_timeout(handle, 100)
            try MandarinSQLite.execute(handle, "PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; PRAGMA cache_size=-1024; PRAGMA mmap_size=0;")
            guard try MandarinSQLite.integer(handle, "PRAGMA application_id") == MandarinSQLite.applicationID,
                  try MandarinSQLite.integer(handle, "PRAGMA user_version") == Self.schemaVersion else {
                throw MandarinDictionaryError.incompatibleDatabase
            }
            var schema: [String: String] = [:]
            let statement = try MandarinSQLite.prepare(handle, "SELECT name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")
            defer { sqlite3_finalize(statement) }
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                guard schema.count < 3,
                      let name = MandarinSQLite.text(statement, 0),
                      let sql = MandarinSQLite.text(statement, 1) else {
                    throw MandarinDictionaryError.incompatibleDatabase
                }
                schema[name] = sql
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE, schema == MandarinSQLite.schema else {
                throw MandarinDictionaryError.incompatibleDatabase
            }
            let metadata = try MandarinSQLite.prepare(handle, "SELECT value FROM metadata WHERE key=?")
            defer { sqlite3_finalize(metadata) }
            for (key, expected) in [("engineABI", Self.engineABI), ("compilerVersion", Self.compilerVersion),
                                    ("outputPolicy", "simplified-conservative-subset-not-full-t2s")] {
                sqlite3_reset(metadata); sqlite3_clear_bindings(metadata)
                try MandarinSQLite.bind(metadata, 1, key)
                guard sqlite3_step(metadata) == SQLITE_ROW,
                      MandarinSQLite.text(metadata, 0) == expected else {
                    throw MandarinDictionaryError.incompatibleDatabase
                }
            }
        } catch {
            sqlite3_close(handle); database = nil
            throw error
        }
    }

    deinit { if let database { sqlite3_close(database) } }

    /// Exact full-word/phrase lookup by default, NOT a sentence model. Prefix
    /// completion is an explicit option. Paging never expands beyond top 512 rows.
    public func lookup(_ rawInput: String, prefix: Bool = false, offset: Int = 0,
                       limit: Int = 48) throws -> MandarinDictionaryPage {
        let query = try MandarinPinyinReading(rawInput)
        guard (0...Self.maximumExaminedRows).contains(offset),
              (1...Self.maximumCandidates).contains(limit) else { throw MandarinDictionaryError.invalidReading }
        lock.lock(); defer { lock.unlock() }
        guard let database else { throw MandarinDictionaryError.incompatibleDatabase }
        let whereClause = prefix ? "flat>=? AND flat<?" : "flat=?"
        // Prefix ranges are lexicographic ASCII intervals; no LIKE wildcards.
        // A prefix range is capped in index order BEFORE local score sorting;
        // sorting the entire prefix range inside SQL would defeat bounded work.
        let order = prefix ? "flat, weight DESC, reading, tones, output" : "weight DESC, reading, tones, output"
        let statement = try MandarinSQLite.prepare(database,
            "SELECT reading, tones, output, weight FROM entries WHERE \(whereClause) ORDER BY \(order) LIMIT 512")
        defer { sqlite3_finalize(statement) }
        try MandarinSQLite.bind(statement, 1, query.flat)
        if prefix { try MandarinSQLite.bind(statement, 2, query.flat + "{") }
        var matches: [MandarinDictionaryCandidate] = []
        var seen: [Data: Int] = [:]
        var examined = 0
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            examined += 1
            guard let reading = MandarinSQLite.text(statement, 0, maximumBytes: 256),
                  let toneString = MandarinSQLite.text(statement, 1, maximumBytes: 32),
                  let output = MandarinSQLite.text(statement, 2, maximumBytes: 1024),
                  sqlite3_column_type(statement, 3) == SQLITE_INTEGER else {
                throw MandarinDictionaryError.incompatibleDatabase
            }
            let syllables = reading.components(separatedBy: "'")
            let tones = toneString.utf8.map { Int($0) - 48 }
            let weight = sqlite3_column_int64(statement, 3)
            guard !output.isEmpty, weight >= 0, weight <= Int64(Int.max),
                  syllables.count == tones.count, syllables.count <= 32,
                  syllables.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (97...122).contains($0) } }),
                  tones.allSatisfy({ (1...5).contains($0) }) else {
                throw MandarinDictionaryError.incompatibleDatabase
            }
            if query.matches(syllables: syllables, tones: tones, prefix: prefix) {
                let identity = Data(output.utf8)
                let candidate = MandarinDictionaryCandidate(text: output, reading: reading, tones: tones, score: Int(weight))
                if let position = seen[identity] {
                    if candidate.score > matches[position].score { matches[position] = candidate }
                } else {
                    seen[identity] = matches.count
                    matches.append(candidate)
                }
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw MandarinSQLite.error(database) }
        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.reading != $1.reading { return $0.reading < $1.reading }
            if $0.tones != $1.tones { return $0.tones.lexicographicallyPrecedes($1.tones) }
            return Data($0.text.utf8).lexicographicallyPrecedes(Data($1.text.utf8))
        }
        let end = min(matches.count, offset + limit)
        let page = offset < end ? Array(matches[offset..<end]) : []
        return .init(candidates: page, nextOffset: end < matches.count ? end : nil,
                     searchWasCapped: examined == Self.maximumExaminedRows)
    }
}

/// Shared implementation detail; all externally influenced VALUES are bound.
/// Only these fixed schema strings and fixed statements are executable.
enum MandarinSQLite {
    static let applicationID = 0x554D5059
    static let schema: [String: String] = [
        "metadata": "CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID",
        "entries": "CREATE TABLE entries(flat TEXT NOT NULL, reading TEXT NOT NULL, tones TEXT NOT NULL, output TEXT NOT NULL, weight INTEGER NOT NULL CHECK(weight>=0), PRIMARY KEY(reading,tones,output)) WITHOUT ROWID",
        "entries_lookup": "CREATE INDEX entries_lookup ON entries(flat,weight DESC,reading,tones,output)"
    ]
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func error(_ db: OpaquePointer) -> MandarinDictionaryError {
        // Do not expose host text/custom words in errors. SQLite's diagnostic is
        // intentionally not copied because it can contain database payloads.
        .database("SQLite code \(sqlite3_extended_errcode(db))")
    }
    static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error(db) }
    }
    static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw error(db)
        }
        return statement
    }
    static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw MandarinDictionaryError.database("bind failed")
        }
    }
    static func text(_ statement: OpaquePointer, _ column: Int32, maximumBytes: Int = 8192) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count <= maximumBytes, let pointer = sqlite3_column_text(statement, column) else { return nil }
        let bytes = UnsafeBufferPointer(start: pointer, count: count)
        guard !bytes.contains(0) else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }
    static func integer(_ db: OpaquePointer, _ sql: String) throws -> Int {
        let statement = try prepare(db, sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw error(db) }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
