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
    static let maximumBytes = 512 * 1024
    static let maximumCount = 4096
    struct Snapshot: Codable { var version = 1; var texts: [String] }
    enum Issue: Error { case unavailable, invalid, capacity }
    struct Result { let texts: [String]; let baseline: [String]; let written: Bool }
    let container: () -> URL?
    var read: (URL) throws -> Data? = readFile
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }

    init(container: @escaping () -> URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)
    }) { self.container = container }

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

    func synchronize(base: [String], local: [String], canWrite: Bool) throws -> Result {
        guard let root = container(), root.isFileURL else { throw Issue.unavailable }
        let url = root.appendingPathComponent(Self.filename)
        func remoteTexts() throws -> [String] {
            let remote: [String]
            if let data = try read(url) {
                guard !data.isEmpty, data.count <= Self.maximumBytes,
                      let state = try? JSONDecoder().decode(Snapshot.self, from: data), state.version == 1,
                      Self.valid(state.texts) else { throw Issue.invalid }
                remote = state.texts
            } else { remote = base }
            return remote
        }
        guard canWrite else {
            let remote = try remoteTexts()
            return Result(texts: try Self.merge(base: base, local: local, remote: remote), baseline: remote, written: false)
        }
        let lock = root.appendingPathComponent("favorites-v1.lock").withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        }
        guard lock >= 0 else { throw Issue.unavailable }
        defer { close(lock) }
        var lockInfo = stat()
        guard fstat(lock, &lockInfo) == 0, (lockInfo.st_mode & S_IFMT) == S_IFREG else { throw Issue.invalid }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Issue.unavailable }
        defer { flock(lock, LOCK_UN) }
        let texts = try Self.merge(base: base, local: local, remote: remoteTexts())
        let data = try JSONEncoder().encode(Snapshot(texts: texts))
        guard data.count <= Self.maximumBytes else { throw Issue.capacity }
        // Reject links even though atomic replacement would not follow one.
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw Issue.invalid }
        try write(data, url)
        return Result(texts: texts, baseline: texts, written: true)
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
