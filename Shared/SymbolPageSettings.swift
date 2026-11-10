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
              let file = try? JSONDecoder().decode(File.self, from: data), (1...2).contains(file.schemaVersion),
              file.schemaVersion >= 2 || file.pages.allSatisfy(\.isLegacy),
              file.pages.allSatisfy({ $0.id != SymbolPageRules.favoritesID || ($0.isLegacy && $0.keys.isEmpty) }) else { return nil }
        if file.pages.contains(where: { !$0.isLegacy }), !SymbolPageRules.validPages(file.pages, starPageID: file.starPageID) { return nil }
        return Snapshot(pages: file.pages, starPageID: file.starPageID)
    }

    /// The store's own encoding (sorted keys); nil over the size cap.
    static func encode(_ snapshot: Snapshot) -> Data? {
        if snapshot.pages.contains(where: { !$0.isLegacy }), !SymbolPageRules.validPages(snapshot.pages, starPageID: snapshot.starPageID) { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(File(schemaVersion: snapshot.pages.contains { !$0.isLegacy } ? 2 : 1, pages: snapshot.pages, starPageID: snapshot.starPageID)),
              data.count <= maximumPayloadBytes else { return nil }
        return data
    }

    /// Only the containing app calls this.
    @discardableResult func save(_ snapshot: Snapshot) -> Bool {
        guard let container = containerURL(), container.isFileURL, let data = Self.encode(snapshot) else { return false }
        do {
            return try ArrangementPublication.withLock(directory: container) {
                guard containerURL() == container else { return false }
                try writeAtomically(data, container.appendingPathComponent(Self.filename))
                return true
            }
        } catch { return false }
    }

    struct ArrangementRevision: Equatable {
        let context: ArrangementPublication.Context
        let favoriteBytes: Data?
    }
    struct ArrangementPublicationResult {
        let snapshot: Snapshot
        let revision: ArrangementRevision
    }
    /// Missing/corrupt state cannot authorize Undo. Reads are made again while
    /// holding the configuration/Favorites writer lock, not at a view boundary.
    func arrangementRevision() -> ArrangementRevision? {
        guard let directory = containerURL(), load() != nil,
              let context = ArrangementPublication.context(in: directory,
                excluding: [Self.filename, FavoriteSync.filename]) else { return nil }
        do {
            let favorites = try FavoriteSync.readFile(directory.appendingPathComponent(FavoriteSync.filename))
            if let favorites, FavoriteSync.decode(favorites) == nil { return nil }
            return .init(context: context, favoriteBytes: favorites)
        } catch { return nil }
    }

    /// Replaces only the edited page in freshly loaded authoritative state.
    /// `seed` is permitted for a first direct edit, never a restore.
    func replaceArrangement(expected: SymbolBoard, replacement: SymbolBoard,
                            revision: ArrangementRevision?, seed: Snapshot? = nil,
                            favoriteGuard: Bool = false) -> ArrangementPublicationResult? {
        guard expected.id == replacement.id, let directory = containerURL() else { return nil }
        return try? ArrangementPublication.withLock(directory: directory) {
            guard containerURL() == directory,
                  let context = ArrangementPublication.context(in: directory,
                    excluding: [Self.filename, FavoriteSync.filename]),
                  revision == nil || revision?.context == context else { throw FileError.unavailable }
            let favoriteBytes = try FavoriteSync.readFile(directory.appendingPathComponent(FavoriteSync.filename))
            if let favoriteBytes, FavoriteSync.decode(favoriteBytes) == nil { throw FileError.unavailable }
            if favoriteGuard, let revision, revision.favoriteBytes != favoriteBytes { throw FileError.unavailable }
            let url = directory.appendingPathComponent(Self.filename)
            let bytes = try FavoriteSync.readFile(url)
            let current: Snapshot
            if let bytes {
                guard let decoded = Self.decode(bytes), SymbolPageRules.validPages(decoded.pages, starPageID: decoded.starPageID) else { throw FileError.unavailable }
                current = decoded
            } else {
                guard revision == nil, let seed else { throw FileError.unavailable }
                current = seed
            }
            guard let index = current.pages.firstIndex(where: { $0.id == expected.id }),
                  current.pages[index] == expected else { throw FileError.unavailable }
            var next = current
            next.pages[index] = replacement
            guard SymbolPageRules.validPages(next.pages, starPageID: next.starPageID),
                  let data = Self.encode(next), containerURL() == directory else { throw FileError.unavailable }
            if next != current || bytes == nil { try writeAtomically(data, url) }
            return ArrangementPublicationResult(snapshot: next,
                revision: .init(context: context, favoriteBytes: favoriteBytes))
        }
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
