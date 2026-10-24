import Foundation
import CryptoKit

/// What an index was built from. A different catalog (a new Unicode version,
/// regenerated data or an app update) has a different digest, so its index
/// is never reused.
struct UnicodeSearchIndexIdentity: Equatable, Sendable {
    /// SHA-256 of the complete catalog file.
    let catalogDigest: Data
    let catalogBytes: Int
    let recordCount: Int
    let version: String
}

/// A compact, memory-mappable word index over the catalog's folded search
/// texts. Catalog text only: no query or other user text is ever stored.
///
/// It only narrows which records a search examines. Search terms never hold a
/// space and the folded texts separate words with single spaces, so a term
/// occurs in a text exactly when it occurs inside one of the text's words.
/// The index lists, for each distinct word, the records (and shared NamesList
/// context texts) that contain it. Every candidate is still matched against
/// the catalog's own bytes, so results and their order equal a full scan.
///
/// Little-endian layout; every section is an array of UInt32 except the words:
///
///     0   "UBSIDX01"            8   format version     12  header size (160)
///     16  catalog SHA-256       48  SHA-256 of every byte after the header
///     80  catalog bytes         84  records            88  contexts
///     92  words                 96  word bytes         100 record postings
///     104 context postings      108 context members    112 version length
///     128 catalog version label (UTF-8, at most 32 bytes, zero padded)
///     160 word starts [words + 1]       record posting starts [words + 1]
///         context posting starts [words + 1]   member starts [contexts + 1]
///         record postings   context postings   context members   word bytes
struct UnicodeSearchIndex: Sendable {
    static let formatVersion: UInt32 = 1
    static let headerSize = 160
    static let maximumVersionBytes = 32
    private static let magic = Array("UBSIDX01".utf8)

    let identity: UnicodeSearchIndexIdentity
    private let data: Data
    private let contextCount: Int
    private let wordCount: Int
    private let wordStarts: Int
    private let primaryStarts: Int
    private let contextStarts: Int
    private let memberStarts: Int
    private let primaryPostings: Int
    private let contextPostings: Int
    private let members: Int
    private let wordBytes: Int

    var byteCount: Int { data.count }

    /// Opens a persisted (normally memory-mapped) index. Nil unless its header
    /// names `identity` and the format version, and its size, checksum and
    /// offsets are intact: a stale or damaged file is rebuilt, never trusted.
    init?(data: Data, identity: UnicodeSearchIndexIdentity) {
        guard data.count >= Self.headerSize else { return nil }
        let fields = data.withUnsafeBytes { bytes in (0..<12).map { Int(Self.u32(bytes, 80 + 4 * $0)) } }
        let records = fields[1], contexts = fields[2], words = fields[3], wordLength = fields[4]
        let postings = fields[5], contextPostingCount = fields[6], memberCount = fields[7], versionLength = fields[8]
        let version = Array(identity.version.utf8)
        let sections = 3 * (words + 1) + contexts + 1 + postings + contextPostingCount + memberCount
        guard data.prefix(8).elementsEqual(Self.magic),
              data.withUnsafeBytes({ Self.u32($0, 8) == Self.formatVersion && Self.u32($0, 12) == UInt32(Self.headerSize) }),
              data[data.startIndex + 16..<data.startIndex + 48].elementsEqual(identity.catalogDigest),
              fields[0] == identity.catalogBytes, records == identity.recordCount,
              versionLength == version.count,
              data[data.startIndex + 128..<data.startIndex + 128 + min(versionLength, Self.maximumVersionBytes)].elementsEqual(version),
              data.count == Self.headerSize + 4 * sections + wordLength,
              data[data.startIndex + 48..<data.startIndex + 80].elementsEqual(SHA256.hash(data: data.dropFirst(Self.headerSize)))
        else { return nil }
        self.identity = identity
        self.data = data
        contextCount = contexts
        wordCount = words
        wordStarts = Self.headerSize
        primaryStarts = wordStarts + 4 * (words + 1)
        contextStarts = primaryStarts + 4 * (words + 1)
        memberStarts = contextStarts + 4 * (words + 1)
        primaryPostings = memberStarts + 4 * (contexts + 1)
        contextPostings = primaryPostings + 4 * postings
        members = contextPostings + 4 * contextPostingCount
        wordBytes = members + 4 * memberCount
        // The checksum proves the file is what a build wrote; the offsets are
        // still checked once so that no later read can leave its section.
        let intact = data.withUnsafeBytes { bytes in
            Self.ascending(bytes, at: wordStarts, count: words + 1, last: wordLength)
                && Self.ascending(bytes, at: primaryStarts, count: words + 1, last: postings)
                && Self.ascending(bytes, at: contextStarts, count: words + 1, last: contextPostingCount)
                && Self.ascending(bytes, at: memberStarts, count: contexts + 1, last: memberCount)
                && Self.below(bytes, at: primaryPostings, count: postings, limit: records)
                && Self.below(bytes, at: contextPostings, count: contextPostingCount, limit: contexts)
                && Self.below(bytes, at: members, count: memberCount, limit: records)
        }
        guard intact else { return nil }
    }

    /// Sorted indexes of the catalog records whose search text or context text
    /// contains every token: a superset of the records a full scan matches.
    func candidates(for tokens: [[UInt8]]) -> [Int] {
        data.withUnsafeBytes { bytes in
            let recordWords = (identity.recordCount + 63) / 64
            var result: [UInt64]?
            for token in tokens {
                if Task.isCancelled { return [] }
                var records = [UInt64](repeating: 0, count: recordWords)
                var contexts = [UInt64](repeating: 0, count: (contextCount + 63) / 64)
                var start = wordBytes + Int(Self.u32(bytes, wordStarts))
                for word in 0..<wordCount {
                    let end = wordBytes + Int(Self.u32(bytes, wordStarts + 4 * word + 4))
                    if Self.contains(token, bytes: bytes, start: start, end: end) {
                        Self.mark(bytes, from: primaryPostings, starts: primaryStarts, item: word, into: &records)
                        Self.mark(bytes, from: contextPostings, starts: contextStarts, item: word, into: &contexts)
                    }
                    start = end
                }
                for context in Self.setBits(of: contexts) {
                    Self.mark(bytes, from: members, starts: memberStarts, item: context, into: &records)
                }
                if let previous = result {
                    for slot in records.indices { records[slot] &= previous[slot] }
                }
                if !records.contains(where: { $0 != 0 }) { return [] }
                result = records
            }
            return Self.setBits(of: result ?? [])
        }
    }

    /// Builds the index of every explicit record's search and context text.
    /// `texts` gives a record's two byte ranges in `bytes`; contexts shared by
    /// many records are interned once by range. Nil if cancelled or invalid.
    static func build(identity: UnicodeSearchIndexIdentity, bytes: UnsafeRawBufferPointer,
                      texts: (Int) -> (primary: Range<Int>, context: Range<Int>)) -> Data? {
        let version = Array(identity.version.utf8)
        guard identity.catalogDigest.count == 32, version.count <= maximumVersionBytes else { return nil }
        var wordIDs: [[UInt8]: Int] = [:]
        var words: [[UInt8]] = []
        var primary: [[UInt32]] = [], contextual: [[UInt32]] = []
        var contextIDs: [Range<Int>: Int] = [:]
        var contextMembers: [[UInt32]] = []
        func eachWord(in range: Range<Int>, _ body: (Int) -> Void) {
            var start = range.lowerBound
            for position in range.lowerBound...range.upperBound where position == range.upperBound || bytes[position] == 0x20 {
                if position > start {
                    let word = Array(bytes[start..<position])
                    if let id = wordIDs[word] { body(id) } else {
                        wordIDs[word] = words.count
                        words.append(word)
                        primary.append([])
                        contextual.append([])
                        body(words.count - 1)
                    }
                }
                start = position + 1
            }
        }
        for record in 0..<identity.recordCount {
            if record & 1023 == 0 && Task.isCancelled { return nil }
            let (text, context) = texts(record)
            eachWord(in: text) { if primary[$0].last != UInt32(record) { primary[$0].append(UInt32(record)) } }
            if context.isEmpty { continue }
            if let id = contextIDs[context] {
                contextMembers[id].append(UInt32(record))
            } else {
                let id = contextMembers.count
                contextIDs[context] = id
                contextMembers.append([UInt32(record)])
                eachWord(in: context) { if contextual[$0].last != UInt32(id) { contextual[$0].append(UInt32(id)) } }
            }
        }
        var body: [UInt8] = []
        func append(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { body.append(contentsOf: $0) }
        }
        func appendStarts(_ lists: [[UInt32]]) {
            var total = 0
            append(0)
            for list in lists { total += list.count; append(total) }
        }
        var wordTotal = 0
        append(0)
        for word in words { wordTotal += word.count; append(wordTotal) }
        appendStarts(primary)
        appendStarts(contextual)
        appendStarts(contextMembers)
        for list in primary + contextual + contextMembers { for value in list { append(Int(value)) } }
        for word in words { body.append(contentsOf: word) }
        var header = magic
        let counts = [Int(formatVersion), headerSize]
        for value in counts { withUnsafeBytes(of: UInt32(value).littleEndian) { header.append(contentsOf: $0) } }
        header.append(contentsOf: identity.catalogDigest)
        header.append(contentsOf: SHA256.hash(data: body))
        let fields = [identity.catalogBytes, identity.recordCount, contextMembers.count, words.count, wordTotal,
                      primary.reduce(0) { $0 + $1.count }, contextual.reduce(0) { $0 + $1.count },
                      contextMembers.reduce(0) { $0 + $1.count }, version.count, 0, 0, 0]
        for value in fields { withUnsafeBytes(of: UInt32(value).littleEndian) { header.append(contentsOf: $0) } }
        header.append(contentsOf: version + [UInt8](repeating: 0, count: maximumVersionBytes - version.count))
        return Data(header + body)
    }

    private static func u32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    private static func ascending(_ bytes: UnsafeRawBufferPointer, at offset: Int, count: Int, last: Int) -> Bool {
        var previous: UInt32 = 0
        for item in 0..<count {
            let value = u32(bytes, offset + 4 * item)
            if value < previous { return false }
            previous = value
        }
        return u32(bytes, offset) == 0 && Int(previous) == last
    }

    private static func below(_ bytes: UnsafeRawBufferPointer, at offset: Int, count: Int, limit: Int) -> Bool {
        for item in 0..<count where Int(u32(bytes, offset + 4 * item)) >= limit { return false }
        return true
    }

    /// Sets the bit of every posting in item's list.
    private static func mark(_ bytes: UnsafeRawBufferPointer, from postings: Int, starts: Int, item: Int,
                             into bits: inout [UInt64]) {
        let first = Int(u32(bytes, starts + 4 * item)), last = Int(u32(bytes, starts + 4 * item + 4))
        for posting in first..<last {
            let value = Int(u32(bytes, postings + 4 * posting))
            bits[value >> 6] |= 1 << UInt64(value & 63)
        }
    }

    private static func setBits(of bits: [UInt64]) -> [Int] {
        var result: [Int] = []
        for (slot, word) in bits.enumerated() {
            var remaining = word
            while remaining != 0 {
                result.append(slot * 64 + remaining.trailingZeroBitCount)
                remaining &= remaining - 1
            }
        }
        return result
    }

    /// Whether `token` occurs in bytes[start..<end].
    private static func contains(_ token: [UInt8], bytes: UnsafeRawBufferPointer, start: Int, end: Int) -> Bool {
        let count = token.count
        var candidate = start
        while candidate + count <= end {
            var matched = 0
            while matched < count && bytes[candidate + matched] == token[matched] { matched += 1 }
            if matched == count { return true }
            candidate += 1
        }
        return false
    }
}
