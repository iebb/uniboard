import Foundation

/// Persists the search index in the app group, where the app and keyboard
/// share one memory-mapped copy. The containing app builds it on a
/// background task; the keyboard only maps a valid file and otherwise keeps
/// scanning the catalog. A file built from other catalog data, by another
/// format version, or damaged, is ignored and replaced on the next build.
final class UnicodeSearchIndexStore: @unchecked Sendable {
    static let filename = "UnicodeSearchIndex-v\(UnicodeSearchIndex.formatVersion).bin"
    /// Under the group's Library/Caches: never backed up, and rebuilt if purged.
    static let shared = UnicodeSearchIndexStore(directory: FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)?
        .appendingPathComponent("Library/Caches/SearchIndex", isDirectory: true))

    let directory: URL?
    private let lock = NSLock()
    private let buildLock = NSLock()
    private var current: UnicodeSearchIndex?
    /// The file `current` maps; nil when it is only in memory.
    private var currentFile: URL?

    init(directory: URL?) {
        self.directory = directory
    }

    var fileURL: URL? { directory?.appendingPathComponent(Self.filename) }

    /// The persisted index of `catalog`'s data, mapped once and then reused
    /// while its file remains. Never builds, so it is cheap enough to ask on
    /// every search.
    func installedIndex(for catalog: UnicodeCatalog) -> UnicodeSearchIndex? {
        guard let identity = catalog.searchIndexIdentity else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let current, current.identity == identity,
           currentFile.map({ FileManager.default.fileExists(atPath: $0.path) }) ?? true { return current }
        guard let url = fileURL, let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let index = UnicodeSearchIndex(data: data, identity: identity) else { return nil }
        current = index
        currentFile = url
        return index
    }

    /// Maps the persisted index, or builds it and writes it atomically. Blocks
    /// while building: call it from a low-priority background task only.
    /// Without a writable directory the built index is kept in memory.
    @discardableResult
    func prepare(for catalog: UnicodeCatalog) -> UnicodeSearchIndex? {
        buildLock.lock()
        defer { buildLock.unlock() }
        if let existing = installedIndex(for: catalog) { return existing }
        guard let identity = catalog.searchIndexIdentity, let built = catalog.makeSearchIndex() else { return nil }
        var data = built, file: URL?
        if let url = fileURL, (try? Self.write(built, to: url)) != nil,
           let mapped = try? Data(contentsOf: url, options: .alwaysMapped) {
            data = mapped
            file = url
        }
        let index = UnicodeSearchIndex(data: data, identity: identity)
        lock.lock()
        current = index
        currentFile = file
        lock.unlock()
        return index
    }

    /// Writes a temporary file beside `url`, then renames it into place, so a
    /// reader maps either the old file or the complete new one.
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
