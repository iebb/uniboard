import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Symbol pages are configured in the app. The app writes this one file;
/// the keyboard only reads it, so pages reach the keyboard without Full
/// Access. Favorites keys sync separately, so the Favorites page is stored
/// here only for its place in the order.
struct SymbolPageSettings {
    struct Snapshot: Codable, Equatable {
        /// Every page in display order. The Favorites entry carries no keys.
        var pages: [SymbolBoard]
        var starPageID: String
    }

    static let groupIdentifier = UnicodeEditionSettings.groupIdentifier
    static let filename = "symbol-pages-v1.json"
    static let maximumPayloadBytes = 512 * 1024
    static let shared = SymbolPageSettings()

    typealias ContainerProvider = () -> URL?
    typealias PrefixReader = (URL, Int) throws -> Data
    typealias AtomicWriter = (Data, URL) throws -> Void
    private let containerURL: ContainerProvider
    private let readPrefix: PrefixReader
    private let writeAtomically: AtomicWriter

    /// The default reads the current shared configuration generation, or
    /// the group root before migration.
    init(containerURL: @escaping ContainerProvider = {
        SharedConfigurationLocation.shared.currentDirectory()
    }, readPrefix: @escaping PrefixReader = SymbolPageSettings.readFilePrefix,
         writeAtomically: @escaping AtomicWriter = SymbolPageSettings.writeFileAtomically) {
        self.containerURL = containerURL; self.readPrefix = readPrefix; self.writeAtomically = writeAtomically
    }

    /// nil when no pages have been configured yet, or the file is unusable.
    func load() -> Snapshot? {
        guard let container = containerURL(), container.isFileURL,
              let data = try? readPrefix(container.appendingPathComponent(Self.filename), Self.maximumPayloadBytes + 1) else { return nil }
        return Self.decode(data)
    }

    /// nil when the payload is empty, oversized, malformed or of an unknown schema.
    static func decode(_ data: Data) -> Snapshot? {
        guard !data.isEmpty, data.count <= maximumPayloadBytes,
              let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == 1 else { return nil }
        return Snapshot(pages: file.pages, starPageID: file.starPageID)
    }

    /// The store's own encoding (sorted keys); nil over the size cap.
    static func encode(_ snapshot: Snapshot) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(File(schemaVersion: 1, pages: snapshot.pages, starPageID: snapshot.starPageID)),
              data.count <= maximumPayloadBytes else { return nil }
        return data
    }

    /// Only the containing app calls this.
    @discardableResult func save(_ snapshot: Snapshot) -> Bool {
        guard let container = containerURL(), container.isFileURL, let data = Self.encode(snapshot) else { return false }
        do { try writeAtomically(data, container.appendingPathComponent(Self.filename)); return true }
        catch { return false }
    }

    private struct File: Codable {
        let schemaVersion: Int
        let pages: [SymbolBoard]
        let starPageID: String
    }

    private enum FileError: Error { case unavailable }

    private static func readFilePrefix(_ url: URL, maximumBytes: Int) throws -> Data {
        // Read the fixed child without following a link or blocking on a FIFO.
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw FileError.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw FileError.unavailable }
        var data = Data()
        while data.count < maximumBytes {
            let chunk = try handle.read(upToCount: maximumBytes - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    private static func writeFileAtomically(_ data: Data, to url: URL) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw FileError.unavailable }
        try data.write(to: url, options: [.atomic])
    }
}
