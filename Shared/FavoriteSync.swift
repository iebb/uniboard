import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Only explicit favorites cross this boundary. Never host text, queries or recents.
/// Readers need no Full Access. Writers serialize their read/merge/atomic replace
/// under a nonblocking advisory lock; a failed write leaves local edits pending.
struct FavoriteSync {
    static let shared = FavoriteSync()
    static let filename = "favorites-v1.json"
    /// Also the shared configuration's writer lock; it stays in the group root.
    static let lockFilename = "favorites-v1.lock"
    static let maximumBytes = 512 * 1024
    static let maximumCount = 4096
    /// Version 2 carries the id of the import or undo that replaced the list
    /// wholesale. Ordinary syncs keep whatever id they read.
    struct Snapshot: Codable { var version = 1; var texts: [String]; var replacementID: String? = nil }
    enum Issue: Error { case unavailable, invalid, capacity }
    struct Result { let texts: [String]; let baseline: [String]; let written: Bool; let replacementID: String? }
    /// The directory holding the favorites file.
    let container: () -> URL?
    /// The directory holding the lock file.
    let lockContainer: () -> URL?
    var read: (URL) throws -> Data? = readFile
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }

    /// The file and its lock in one directory.
    init(container: @escaping () -> URL?) { self.container = container; lockContainer = container }

    /// The file in the current configuration generation, resolved only after
    /// the lock is held; the lock in the group root.
    init(location: SharedConfigurationLocation = .shared) {
        container = location.currentDirectory; lockContainer = location.root
    }

    static func valid(_ texts: [String]) -> Bool {
        texts.count <= maximumCount && Set(texts.map { Array($0.utf16) }).count == texts.count
            && texts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.prefix(65).count <= 64 }
    }

    /// Three-way set merge. Local removals win over an unchanged shared value;
    /// unrelated shared additions survive. A deliberate local reorder retains
    /// its relative order without dropping symbols newly added by the other side.
    static func merge(base: [String], local: [String], remote: [String]) throws -> [String] {
        guard valid(base), valid(local), valid(remote) else { throw Issue.invalid }
        let old = Set(base.map { Array($0.utf16) }), own = Set(local.map { Array($0.utf16) })
        let removed = old.subtracting(own)
        let additions = local.filter { !old.contains(Array($0.utf16)) }
        var seen = Set<[UInt16]>()
        var result = (additions + remote).filter { !removed.contains(Array($0.utf16)) && seen.insert(Array($0.utf16)).inserted }
        let common = old.intersection(own)
        if base.filter({ common.contains(Array($0.utf16)) }).map({ Array($0.utf16) })
            != local.filter({ common.contains(Array($0.utf16)) }).map({ Array($0.utf16) }) {
            let available = Set(result.map { Array($0.utf16) })
            result = local.filter { available.contains(Array($0.utf16)) } + result.filter { !own.contains(Array($0.utf16)) }
        }
        guard valid(result) else { throw Issue.capacity }
        return result
    }

    /// `replacementID` is the replacement this process last adopted. A
    /// different one on disk means an import or undo replaced the list: it is
    /// adopted wholesale instead of merged, so pending local edits don't
    /// bring back what the replacement removed.
    func synchronize(base: [String], local: [String], canWrite: Bool, replacementID: String? = nil) throws -> Result {
        guard canWrite else {
            let remote = try remoteState(base: base).snapshot
            if let replaced = adopted(remote, replacementID, written: false) { return replaced }
            return Result(texts: try Self.merge(base: base, local: local, remote: remote.texts), baseline: remote.texts, written: false,
                          replacementID: remote.replacementID ?? replacementID)
        }
        guard let lockRoot = lockContainer(), lockRoot.isFileURL else { throw Issue.unavailable }
        let lock = lockRoot.appendingPathComponent(Self.lockFilename).withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        }
        guard lock >= 0 else { throw Issue.unavailable }
        defer { close(lock) }
        var lockInfo = stat()
        guard fstat(lock, &lockInfo) == 0, (lockInfo.st_mode & S_IFMT) == S_IFREG else { throw Issue.invalid }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Issue.unavailable }
        defer { flock(lock, LOCK_UN) }
        let (url, remote) = try remoteState(base: base)
        if let replaced = adopted(remote, replacementID, written: true) { return replaced }
        let texts = try Self.merge(base: base, local: local, remote: remote.texts)
        let data = try JSONEncoder().encode(Snapshot(version: remote.replacementID == nil ? 1 : 2, texts: texts, replacementID: remote.replacementID))
        guard data.count <= Self.maximumBytes else { throw Issue.capacity }
        // Reject links even though atomic replacement would not follow one.
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw Issue.invalid }
        try write(data, url)
        return Result(texts: texts, baseline: texts, written: true, replacementID: remote.replacementID ?? replacementID)
    }

    private func remoteState(base: [String]) throws -> (url: URL, snapshot: Snapshot) {
        guard let root = container(), root.isFileURL else { throw Issue.unavailable }
        let url = root.appendingPathComponent(Self.filename)
        guard let data = try read(url) else { return (url, Snapshot(texts: base)) }
        guard let state = Self.decode(data) else { throw Issue.invalid }
        return (url, state)
    }

    private func adopted(_ remote: Snapshot, _ replacementID: String?, written: Bool) -> Result? {
        guard let id = remote.replacementID, id != replacementID else { return nil }
        return Result(texts: remote.texts, baseline: remote.texts, written: written, replacementID: id)
    }

    /// A usable shared file: version 1 without, or version 2 with, a replacement id.
    static func decode(_ data: Data) -> Snapshot? {
        guard !data.isEmpty, data.count <= maximumBytes, let state = try? JSONDecoder().decode(Snapshot.self, from: data),
              state.version == 1 ? state.replacementID == nil : state.version == 2 && state.replacementID.map(SharedConfigurationLocation.isRevision) == true,
              valid(state.texts) else { return nil }
        return state
    }

    /// The favorites file an import or undo writes: the exact list under a
    /// new replacement id.
    static func replacementPayload(_ texts: [String], id: String = UUID().uuidString) -> Data? {
        guard valid(texts), SharedConfigurationLocation.isRevision(id),
              let data = try? JSONEncoder().encode(Snapshot(version: 2, texts: texts, replacementID: id)), data.count <= maximumBytes else { return nil }
        return data
    }

    /// For Undo: the same list under a new replacement id; unusable data is
    /// kept as it is. (A backup without a favorites file carries the current
    /// one over instead: see `SharedConfigurationLocation.undoLastImport`.)
    static func renewedReplacement(_ data: Data) -> Data {
        decode(data).flatMap { replacementPayload($0.texts) } ?? data
    }

    static func readFile(_ url: URL) throws -> Data? {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw Issue.unavailable
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw Issue.invalid }
        return try handle.read(upToCount: maximumBytes + 1) ?? Data()
    }
}
