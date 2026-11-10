import Foundation
import CryptoKit
import zlib
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum LanguagePackArchiveError: Error, Equatable, Sendable {
    case cancelled
    case invalidArchive(String)
    case limitExceeded(String)
    case payloadMismatch(String)
    case storage(operation: String, code: Int32)
}

/// App-side, data-only tar.gz reader. Exclude this file from the keyboard target.
/// Call on a worker executor, normally inside LanguagePackStore.install's populate
/// closure. On failure discard the supplied stage; it may contain partial files.
/// The descriptor MUST come from the bundled, audited catalog, not from the archive.
public enum LanguagePackArchive {
    public static let japaneseArchiveRoot = "azooKey_dictionary_storage-832fbb0d3039dfaa4b2183956f3d96f6b07eec4d"

    public struct Limits: Sendable {
        public let decodedBytes: Int64
        public let entryCount: Int
        public let individualFileBytes: Int64
        public init(decodedBytes: Int64 = 256 * 1_024 * 1_024,
                    entryCount: Int = 8_192, individualFileBytes: Int64 = 64 * 1_024 * 1_024) {
            self.decodedBytes = decodedBytes
            self.entryCount = entryCount
            self.individualFileBytes = individualFileBytes
        }
    }

    /// Strips exactly one pinned archive root; preserves Dictionary/... and LICENSE
    /// (or other explicitly cataloged paths). Every other regular file is consumed
    /// and bounded, never written. No executable permissions or archive modes apply.
    public static func extract(archive: URL, descriptor: LanguagePackDescriptor,
                               into emptyDirectory: URL,
                               archiveRoot: String = japaneseArchiveRoot,
                               limits: Limits = Limits(),
                               checkCancellation: @escaping () throws -> Void = { try Task.checkCancellation() }) throws {
        func check() throws {
            do { try checkCancellation() }
            catch { throw LanguagePackArchiveError.cancelled }
        }
        try check()
        try descriptor.validate()
        guard LanguagePackDescriptor.isPayloadPath(archiveRoot), !archiveRoot.contains("/"),
              limits.decodedBytes > 0, limits.decodedBytes <= 512 * 1_024 * 1_024,
              limits.entryCount > 0, limits.entryCount <= 65_536,
              limits.individualFileBytes >= 0,
              limits.individualFileBytes <= LanguagePackDescriptor.maximumInstalledBytes else {
            throw LanguagePackArchiveError.invalidArchive("invalid extraction policy")
        }
        // Never add a 'trusted archive' bypass: this also rejects changed archive bytes
        // if a caller invokes extraction independently of the transport.
        try LanguagePackStore.verifyArchive(at: archive, descriptor: descriptor)
        try check()
        let stage = try Stage(emptyDirectory)
        defer { stage.closeRoot() }
        let reader = try GzipReader(archive, maximumDecoded: limits.decodedBytes, check: check)
        defer { reader.closeReader() }
        let expected = Dictionary(uniqueKeysWithValues: descriptor.files.map { ($0.path, $0) })
        var extracted = Set<String>()
        var explicitPaths = Set<String>()
        // Includes implicit ancestors, so casing aliases in directory prefixes fail too.
        var spellings = [String: String]()
        var regularPaths = Set<String>()
        var directoryPaths = Set<String>()
        var entries = 0
        var globalCommentSeen = false

        func register(_ path: String, directory: Bool) throws {
            guard explicitPaths.insert(path).inserted else { throw invalid("duplicate archive path") }
            let components = path.split(separator: "/").map(String.init)
            for count in 1...components.count {
                let prefix = components.prefix(count).joined(separator: "/")
                let key = prefix.precomposedStringWithCanonicalMapping.lowercased()
                if let old = spellings[key], old != prefix { throw invalid("aliased archive path") }
                spellings[key] = prefix
                if count < components.count {
                    guard !regularPaths.contains(prefix) else { throw invalid("file/directory collision") }
                    directoryPaths.insert(prefix)
                }
            }
            if directory {
                directoryPaths.insert(path)
            } else {
                guard !directoryPaths.contains(path) else { throw invalid("file/directory collision") }
                regularPaths.insert(path)
            }
        }

        while true {
            try check()
            let block = try reader.exact(512)
            if block.allSatisfy({ $0 == 0 }) {
                guard try reader.exact(512).allSatisfy({ $0 == 0 }) else { throw invalid("missing second tar end marker") }
                // Tar record padding may be zero-filled, but no concatenated tar,
                // concatenated gzip member, or nonzero trailing bytes are accepted.
                while let remainder = try reader.chunk() {
                    guard remainder.allSatisfy({ $0 == 0 }) else { throw invalid("trailing tar data") }
                }
                guard reader.decoded % 512 == 0 else { throw invalid("partial trailing tar block") }
                break
            }
            entries += 1
            guard entries <= limits.entryCount else { throw LanguagePackArchiveError.limitExceeded("archive entry count") }
            let header = try Header(block)
            guard header.size <= limits.individualFileBytes else { throw LanguagePackArchiveError.limitExceeded("individual entry size") }
            if header.type == 103 { // GitHub's bounded global PAX commit comment.
                guard !globalCommentSeen, header.path == "pax_global_header", header.size <= 16_384 else {
                    throw invalid("global PAX header limit or name")
                }
                globalCommentSeen = true
                try validateGlobalComment(try reader.exact(Int(header.size)))
                try consumePadding(header.size, reader: reader)
                continue
            }
            guard header.type == 0 || header.type == 48 || header.type == 53 else {
                throw invalid("links, special files and path overrides are forbidden")
            }
            let directory = header.type == 53
            guard !directory || header.size == 0 else { throw invalid("directory contains data") }
            var path = header.path
            if directory, path.hasSuffix("/") { path.removeLast() }
            guard LanguagePackDescriptor.isPayloadPath(path),
                  path == archiveRoot || path.hasPrefix(archiveRoot + "/") else { throw invalid("unsafe or foreign archive path") }
            guard path != archiveRoot || directory else { throw invalid("archive root is not a directory") }
            try register(path, directory: directory)
            let relative = path == archiveRoot ? "" : String(path.dropFirst(archiveRoot.count + 1))
            if directory { continue } // Create only directories needed by selected files.
            let file = expected[relative]
            if let file, file.byteCount != header.size { throw LanguagePackArchiveError.payloadMismatch("catalog file size") }
            let output: Int32? = try file.map { _ in try stage.create(relative) }
            defer { if let output { _ = close(output) } }
            var remaining = header.size
            var hasher = SHA256()
            while remaining > 0 {
                try check()
                let bytes = try reader.exact(Int(min(remaining, 65_536)))
                if let output {
                    hasher.update(data: bytes)
                    try writeAll(bytes, fd: output)
                }
                remaining -= Int64(bytes.count)
            }
            if let file {
                let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                guard digest == file.sha256 else { throw LanguagePackArchiveError.payloadMismatch("catalog file hash") }
                extracted.insert(relative)
            }
            try consumePadding(header.size, reader: reader)
        }
        guard extracted.count == expected.count else { throw LanguagePackArchiveError.payloadMismatch("missing catalog files") }
        try check()
    }

    private static func invalid(_ reason: String) -> LanguagePackArchiveError { .invalidArchive(reason) }

    private static func consumePadding(_ size: Int64, reader: GzipReader) throws {
        let padding = Int((512 - size % 512) % 512)
        guard try reader.exact(padding).allSatisfy({ $0 == 0 }) else { throw invalid("nonzero tar padding") }
    }

    private struct Header {
        let path: String
        let size: Int64
        let type: UInt8
        init(_ data: Data) throws {
            let bytes = [UInt8](data)
            func text(_ start: Int, _ count: Int) throws -> String {
                let field = Array(bytes[start..<(start + count)])
                let end = field.firstIndex(of: 0) ?? field.count
                guard field[end...].allSatisfy({ $0 == 0 }),
                      let value = String(bytes: field[..<end], encoding: .utf8) else { throw invalid("invalid tar text field") }
                return value
            }
            func octal(_ start: Int, _ count: Int, emptyAllowed: Bool = false) throws -> Int64 {
                let field = Array(bytes[start..<(start + count)])
                var index = 0
                while index < field.count && field[index] == 32 { index += 1 }
                var value: Int64 = 0
                var digits = 0
                while index < field.count && (48...55).contains(field[index]) {
                    guard value <= (Int64.max - 7) / 8 else { throw invalid("tar numeric overflow") }
                    value = value * 8 + Int64(field[index] - 48)
                    digits += 1; index += 1
                }
                guard (digits > 0 || emptyAllowed), field[index...].allSatisfy({ $0 == 0 || $0 == 32 }) else {
                    throw invalid("invalid octal field")
                }
                return value
            }
            guard Array(bytes[257..<263]) == Array("ustar\0".utf8),
                  Array(bytes[263..<265]) == Array("00".utf8),
                  bytes[500..<512].allSatisfy({ $0 == 0 }) else { throw invalid("unsupported tar format") }
            let checksum = try octal(148, 8)
            let sum = bytes.enumerated().reduce(Int64(0)) { $0 + Int64((148..<156).contains($1.offset) ? 32 : $1.element) }
            guard checksum == sum else { throw invalid("tar header checksum") }
            _ = try octal(100, 8) // mode, uid, gid and mtime: validate, never apply.
            _ = try octal(108, 8)
            _ = try octal(116, 8)
            size = try octal(124, 12)
            _ = try octal(136, 12)
            _ = try octal(329, 8, emptyAllowed: true)
            _ = try octal(337, 8, emptyAllowed: true)
            let name = try text(0, 100)
            let prefix = try text(345, 155)
            guard !name.isEmpty, try text(157, 100).isEmpty else { throw invalid("empty name or link target") }
            path = prefix.isEmpty ? name : prefix + "/" + name
            type = bytes[156]
        }
    }

    private static func validateGlobalComment(_ data: Data) throws {
        // PAX records are '<decimal byte length> <key>=<value>\n'. Only comment
        // is accepted; no path/linkpath/size/sparse/vendor override interpretation.
        let bytes = [UInt8](data)
        var offset = 0
        var seen = false
        while offset < bytes.count {
            var end = offset
            var length = 0
            while end < bytes.count && (48...57).contains(bytes[end]) {
                guard end - offset < 6 else { throw invalid("PAX length") }
                length = length * 10 + Int(bytes[end] - 48); end += 1
            }
            guard end > offset, end < bytes.count, bytes[end] == 32,
                  length > end - offset + 1, length <= bytes.count - offset,
                  bytes[offset + length - 1] == 10 else { throw invalid("malformed PAX record") }
            let record = Array(bytes[(end + 1)..<(offset + length - 1)])
            guard !seen, record.starts(with: Array("comment=".utf8)),
                  record.dropFirst(8).allSatisfy({ (32...126).contains($0) }) else { throw invalid("unsupported PAX metadata") }
            seen = true
            offset += length
        }
        guard seen else { throw invalid("empty PAX global header") }
    }

    private static func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw LanguagePackArchiveError.storage(operation: "write extracted file", code: errno) }
                offset += count
            }
        }
    }

    /// Descriptor-relative openat traversal: no followed links, no overwrite, no
    /// applying owner/mode/mtime from tar. Stage root is owned exclusively by caller.
    private final class Stage {
        let root: Int32
        init(_ url: URL) throws {
            guard url.isFileURL else { throw invalid("non-file staging URL") }
            root = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard root >= 0 else { throw LanguagePackArchiveError.storage(operation: "open stage", code: errno) }
            guard let directory = fdopendir(dup(root)) else {
                let code = errno; close(root)
                throw LanguagePackArchiveError.storage(operation: "read stage", code: code)
            }
            defer { closedir(directory) }
            var empty = true
            while let entry = readdir(directory) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
                }
                if name != "." && name != ".." { empty = false; break }
            }
            if !empty { close(root); throw invalid("stage must be empty") }
        }
        func closeRoot() { _ = close(root) }
        func create(_ path: String) throws -> Int32 {
            let parts = path.split(separator: "/").map(String.init)
            var parent = dup(root)
            guard parent >= 0 else { throw LanguagePackArchiveError.storage(operation: "duplicate stage handle", code: errno) }
            defer { close(parent) }
            for component in parts.dropLast() {
                if mkdirat(parent, component, mode_t(0o700)) != 0 && errno != EEXIST {
                    throw LanguagePackArchiveError.storage(operation: "create payload directory", code: errno)
                }
                let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw LanguagePackArchiveError.storage(operation: "open payload directory", code: errno) }
                close(parent); parent = next
            }
            let fd = openat(parent, parts.last!, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { throw LanguagePackArchiveError.storage(operation: "create payload file", code: errno) }
            return fd
        }
    }

    /// At most ~192 KiB of gzip/input/output buffering, independent of archive size.
    /// z_stream remains at one stable allocated address for zlib's entire lifetime.
    private final class GzipReader {
        let stream: UnsafeMutablePointer<z_stream>
        let file: FileHandle
        let maximumDecoded: Int64
        let check: () throws -> Void
        var input = Data()
        var inputOffset = 0
        var output = Data()
        var outputOffset = 0
        var decoded: Int64 = 0
        var ended = false
        var inputEnded = false
        init(_ url: URL, maximumDecoded: Int64, check: @escaping () throws -> Void) throws {
            self.maximumDecoded = maximumDecoded
            self.check = check
            do { file = try FileHandle(forReadingFrom: url) }
            catch { throw LanguagePackArchiveError.storage(operation: "open gzip", code: Int32((error as NSError).code)) }
            stream = .allocate(capacity: 1)
            stream.initialize(to: z_stream())
            guard inflateInit2_(stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                stream.deinitialize(count: 1); stream.deallocate(); try? file.close()
                throw invalid("gzip initialization")
            }
        }
        func closeReader() {
            inflateEnd(stream); stream.deinitialize(count: 1); stream.deallocate(); try? file.close()
        }
        func exact(_ count: Int) throws -> Data {
            var result = Data()
            result.reserveCapacity(count)
            while result.count < count {
                if outputOffset == output.count, !(try refill()) { throw invalid("truncated tar") }
                let amount = min(count - result.count, output.count - outputOffset)
                result.append(output[outputOffset..<(outputOffset + amount)])
                outputOffset += amount
            }
            return result
        }
        func chunk() throws -> Data? {
            if outputOffset == output.count, !(try refill()) { return nil }
            let result = Data(output[outputOffset...]); outputOffset = output.count
            return result
        }
        func readInput() throws -> Data {
            do { return try file.read(upToCount: 65_536) ?? Data() }
            catch { throw LanguagePackArchiveError.storage(operation: "read gzip", code: Int32((error as NSError).code)) }
        }
        func refill() throws -> Bool {
            output = Data(); outputOffset = 0
            while !ended {
                try check()
                if inputOffset == input.count && !inputEnded {
                    input = try readInput(); inputOffset = 0
                    inputEnded = input.isEmpty
                }
                var buffer = [UInt8](repeating: 0, count: 65_536)
                var consumed = 0
                var produced = 0
                let result: Int32 = input.withUnsafeBytes { raw in
                    buffer.withUnsafeMutableBytes { destination in
                        stream.pointee.next_in = raw.bindMemory(to: Bytef.self).baseAddress.map {
                            UnsafeMutablePointer(mutating: $0.advanced(by: inputOffset))
                        }
                        stream.pointee.avail_in = uInt(input.count - inputOffset)
                        stream.pointee.next_out = destination.bindMemory(to: Bytef.self).baseAddress!
                        stream.pointee.avail_out = uInt(destination.count)
                        let status = inflate(stream, Z_NO_FLUSH)
                        consumed = input.count - inputOffset - Int(stream.pointee.avail_in)
                        produced = destination.count - Int(stream.pointee.avail_out)
                        // Never leave pointers to Swift scoped buffers in z_stream.
                        stream.pointee.next_in = nil; stream.pointee.next_out = nil
                        return status
                    }
                }
                inputOffset += consumed
                decoded += Int64(produced)
                guard decoded <= maximumDecoded else { throw LanguagePackArchiveError.limitExceeded("decoded gzip bytes") }
                guard result == Z_OK || result == Z_STREAM_END else { throw invalid("invalid gzip stream or CRC") }
                if result == Z_STREAM_END {
                    ended = true
                    guard inputOffset == input.count, try readInput().isEmpty else { throw invalid("trailing gzip data") }
                } else if consumed == 0 && produced == 0 { throw invalid("stalled gzip stream") }
                if produced > 0 { output = Data(buffer.prefix(produced)); return true }
            }
            return false
        }
    }
}
