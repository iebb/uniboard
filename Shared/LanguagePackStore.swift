import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Conservative *additional free space*, not installed size or a reservation.
/// Old publications/leases remain on disk and are never credited as reclaimable.
public struct LanguagePackSpacePlan: Equatable, Sendable {
    public let requiredBytes: Int64
    public static let headroom: Int64 = 32 * 1_024 * 1_024

    /// Retained sources + one incoming transport copy + installed stage + local
    /// compiled output and license + two SQLite-sized temporary/journal/sort copies + headroom.
    /// Stage -> version is a rename, not another payload copy. For Japanese there
    /// is no local compilation; extraction writes directly into the staged payload.
    public init(sourceBytes: [Int64], installedBytes: Int64, compiledBytes: Int64 = 0) throws {
        guard !sourceBytes.isEmpty, sourceBytes.allSatisfy({ $0 > 0 && $0 <= LanguagePackDescriptor.maximumArchiveBytes }),
              installedBytes > 0, installedBytes <= LanguagePackDescriptor.maximumInstalledBytes,
              compiledBytes >= 0, compiledBytes <= installedBytes else {
            throw SpaceError.invalidEstimate
        }
        let localCompiledPayload = compiledBytes > 0 ? installedBytes : 0
        let parts = sourceBytes + [sourceBytes.max()!, installedBytes, localCompiledPayload,
                                  compiledBytes, compiledBytes, Self.headroom,
                                  Int64(LanguagePackDescriptor.maximumManifestBytes)]
        var total: Int64 = 0
        for part in parts {
            let sum = total.addingReportingOverflow(part)
            guard !sum.overflow else { throw SpaceError.invalidEstimate }
            total = sum.partialValue
        }
        requiredBytes = total
    }

    public enum Assessment: Equatable, Sendable {
        case sufficient(required: Int64, available: Int64)
        case insufficient(required: Int64, available: Int64)
        case unknown(required: Int64)
    }
    public enum SpaceError: Error, Equatable, Sendable {
        case invalidEstimate, capacityUnknown(required: Int64)
        case insufficient(required: Int64, available: Int64)
    }
    public typealias CapacityProvider = @Sendable (URL) -> Int64?

    /// Call off-main. Probe both temporary and publication locations. Requiring
    /// the whole budget at each is deliberately conservative across volumes and
    /// avoids double-counting free space when both paths are on the same volume.
    public func assess(at locations: [URL], capacity: CapacityProvider) -> Assessment {
        var minimum: Int64?
        var unknown = locations.isEmpty
        for location in locations {
            guard let bytes = capacity(location), bytes >= 0 else { unknown = true; continue }
            minimum = min(minimum ?? bytes, bytes)
        }
        if let minimum, minimum < requiredBytes { return .insufficient(required: requiredBytes, available: minimum) }
        if unknown { return .unknown(required: requiredBytes) }
        return .sufficient(required: requiredBytes, available: minimum!)
    }

    public func requireCapacity(at locations: [URL], capacity: CapacityProvider) throws {
        switch assess(at: locations, capacity: capacity) {
        case .sufficient: return
        case .unknown(let required): throw SpaceError.capacityUnknown(required: required)
        case .insufficient(let required, let available): throw SpaceError.insufficient(required: required, available: available)
        }
    }


}

/// Synchronous filesystem core. Call app-side operations off the main thread.
/// The injected root must be a dedicated, trusted App Group directory, not the
/// shared container root (custom words/preferences must live elsewhere).
/// No network, extraction, engine initialization, or typed/user data is involved.
public struct LanguagePackStore: Sendable {
    public let root: URL
    private static let fm = FileManager.default
    private static let metadataName = "descriptor.json"
    private static let payloadName = "payload"
    private static let leaseName = ".lease"

    /// Canonicalize the trusted injected location once (e.g. Darwin's /var alias).
    /// Foundation may leave /var unresolved when the final child does not exist.
    /// Payload and store-created child paths are still checked without following links.
    public init(root: URL) { self.root = Self.canonicalTrustedLocation(root) }

    /// Verifies a downloaded archive without reading it all into memory. The caller
    /// must also enforce this size limit DURING download and safely bound extraction.
    public static func verifyArchive(at url: URL, descriptor: LanguagePackDescriptor) throws {
        try descriptor.validate()
        // The downloader's directory is a trusted injected location, just like root.
        // Do not resolve the archive itself: O_NOFOLLOW must still reject a file link.
        let parent = canonicalTrustedLocation(url.deletingLastPathComponent())
        try verifyFile(parent.appendingPathComponent(url.lastPathComponent), byteCount: descriptor.archiveByteCount, sha256: descriptor.archiveSHA256)
    }

    /// App only. `populate` writes regular data files into the supplied empty payload
    /// directory. Do not retain/mutate that directory after returning. A future extractor
    /// must reject archive traversal/links BEFORE writing anything, not just hereafter.
    /// `expectedRevision == nil` means there must currently be no active pointer.
    /// Every publication gets a fresh revision, even for the same upstream version.
    @discardableResult
    public func install(manifestData: Data, expectedRevision: String?,
                        populate: (URL) throws -> Void,
                        checkpoint: ((LanguagePackPublicationCheckpoint) throws -> Void)? = nil) throws -> ValidatedInstalledLanguagePack {
        let descriptor = try LanguagePackDescriptor.validated(from: manifestData)
        try prepare()
        let writer = try Self.openLock(root.appendingPathComponent(".writer.lock"), exclusive: true)
        defer { close(writer) }
        let current = try pointer(modeID: descriptor.modeID)
        guard current?.revision == expectedRevision else {
            throw LanguagePackError.revisionConflict(expected: expectedRevision, actual: current?.revision)
        }
        let revision = UUID().uuidString.lowercased()
        let stage = root.appendingPathComponent("staging").appendingPathComponent(revision)
        let version = root.appendingPathComponent("versions").appendingPathComponent(revision)
        try Self.makeDirectory(stage)
        var renamed = false
        var published = false
        defer {
            // Only our freshly minted UUID paths. Never remove caller-supplied paths.
            if !published { try? Self.fm.removeItem(at: renamed ? version : stage) }
        }
        try Self.writeNew(Data(revision.utf8), to: stage.appendingPathComponent(".owner"))
        let payload = stage.appendingPathComponent(Self.payloadName)
        try Self.makeDirectory(payload)
        try populate(payload)
        try Self.checkDirectory(stage)
        try Self.verifyPayload(payload, descriptor: descriptor)
        // Populate owns only payload; reject accidental/hostile sibling artifacts too.
        guard try Set(Self.fm.contentsOfDirectory(atPath: stage.path)) == Set([Self.payloadName, ".owner"]),
              try Self.readSmall(stage.appendingPathComponent(".owner"), limit: 64) == Data(revision.utf8) else {
            throw LanguagePackError.invalidPayload("unexpected staging metadata")
        }
        try Self.writeNew(manifestData, to: stage.appendingPathComponent(Self.metadataName))
        try Self.writeNew(Data(), to: stage.appendingPathComponent(Self.leaseName))
        try checkpoint?(.verifiedStage)
        try Self.rename(stage, version)
        renamed = true
        try Self.syncDirectory(root.appendingPathComponent("versions"))
        try checkpoint?(.renamedVersion)
        let next = Pointer(format: 1, modeID: descriptor.modeID, revision: revision)
        try checkpoint?(.beforePointerPublication)
        try publish(next)
        published = true
        return ValidatedInstalledLanguagePack(revision: revision,
                                             path: version.appendingPathComponent(Self.payloadName), descriptor: descriptor)
    }

    /// Chooser-only publication information. This is NOT a verified pack or a
    /// read lease: it provides no payload URL and must never authorize engine use.
    public struct PublishedMetadata: Equatable, Sendable {
        public let revision: String
        public let descriptor: LanguagePackDescriptor
    }

    public enum MetadataResolution: Sendable {
        case absent, missing, unreadable
        case incompatible(requiredABI: String, installedABI: String)
        case corrupt(String)
        case available(PublishedMetadata)
    }

    /// Bounded chooser readiness: reads only the publication pointer, descriptor
    /// and owner marker, then stats the descriptor's bounded list of files. Never
    /// opens/reads/hashes payload bytes, recursively enumerates payloads, or retains
    /// a lease. Same-size corruption is deliberately detected ONLY by resolve().
    /// Coordination keeps publication/reclamation stable throughout inspection.
    public func publishedMetadata(modeID: String, engineABI: String) -> MetadataResolution {
        guard LanguagePackDescriptor.isIdentifier(modeID) else { return .corrupt("invalid mode identifier") }
        do {
            guard try Self.exists(root) else { return .absent }
            try Self.checkAncestors(root)
            let coordination = try Self.openLock(root.appendingPathComponent(".writer.lock"), exclusive: false)
            defer { close(coordination) }
            guard let active = try pointer(modeID: modeID) else { return .missing }
            let directory = root.appendingPathComponent("versions").appendingPathComponent(active.revision)
            try Self.checkAncestors(directory)
            let descriptor = try LanguagePackDescriptor.validated(from: Self.readSmall(directory.appendingPathComponent(Self.metadataName), limit: LanguagePackDescriptor.maximumManifestBytes))
            guard descriptor.modeID == modeID else { return .corrupt("descriptor mode mismatch") }
            guard descriptor.engineABI == engineABI else {
                return .incompatible(requiredABI: engineABI, installedABI: descriptor.engineABI)
            }
            guard try Self.readSmall(directory.appendingPathComponent(".owner"), limit: 64) == Data(active.revision.utf8) else {
                throw LanguagePackError.corruptStore("invalid version owner")
            }
            let leaseInfo = try Self.info(directory.appendingPathComponent(Self.leaseName))
            guard leaseInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), leaseInfo.st_nlink == 1 else {
                throw LanguagePackError.corruptStore("invalid lease file")
            }
            let payload = directory.appendingPathComponent(Self.payloadName)
            try Self.checkDirectory(payload)
            for file in descriptor.files {
                let url = payload.appendingPathComponent(file.path)
                try Self.checkAncestors(url.deletingLastPathComponent())
                let attributes = try Self.info(url)
                guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                      attributes.st_nlink == 1, attributes.st_mode & mode_t(0o111) == 0,
                      Int64(attributes.st_size) == file.byteCount else {
                    throw LanguagePackError.invalidPayload("file presence, type or size")
                }
            }
            return .available(.init(revision: active.revision, descriptor: descriptor))
        } catch LanguagePackError.filesystem(_, let code) where code == EACCES || code == EPERM {
            return .unreadable
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            return .unreadable
        } catch {
            return .corrupt(String(describing: error))
        }
    }

    /// Keyboard safe: opens existing files READ ONLY, briefly takes the coordination
    /// lock, then acquires a per-version shared lease before releasing coordination.
    /// All files are verified with bounded streaming reads. Keep/reuse the returned
    /// lease rather than calling this on every keystroke.
    public func resolve(modeID: String, engineABI: String) -> LanguagePackResolution {
        guard LanguagePackDescriptor.isIdentifier(modeID) else { return .corrupt("invalid mode identifier") }
        do {
            guard try Self.exists(root) else { return .absent }
            try Self.checkAncestors(root)
            let coordination = try Self.openLock(root.appendingPathComponent(".writer.lock"), exclusive: false)
            var coordinationHeld = true
            defer { if coordinationHeld { close(coordination) } }
            guard let active = try pointer(modeID: modeID) else { return .missing }
            let directory = root.appendingPathComponent("versions").appendingPathComponent(active.revision)
            try Self.checkDirectory(root.appendingPathComponent("versions"))
            try Self.checkDirectory(directory)
            let fd = try Self.openLock(directory.appendingPathComponent(Self.leaseName), exclusive: false)
            close(coordination)
            coordinationHeld = false
            var transferred = false
            defer { if !transferred { close(fd) } }
            let descriptor = try LanguagePackDescriptor.validated(from: Self.readSmall(directory.appendingPathComponent(Self.metadataName), limit: LanguagePackDescriptor.maximumManifestBytes))
            guard descriptor.modeID == modeID else { return .corrupt("descriptor mode mismatch") }
            guard descriptor.engineABI == engineABI else {
                return .incompatible(requiredABI: engineABI, installedABI: descriptor.engineABI)
            }
            try Self.checkVersionContents(directory)
            let payload = directory.appendingPathComponent(Self.payloadName)
            try Self.verifyPayload(payload, descriptor: descriptor)
            let pack = ValidatedInstalledLanguagePack(revision: active.revision, path: payload, descriptor: descriptor)
            transferred = true
            return .available(LanguagePackReadLease(pack: pack, release: { close(fd) }))
        } catch LanguagePackError.filesystem(_, let code) where code == EACCES || code == EPERM {
            return .unreadable
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            return .unreadable
        } catch {
            return .corrupt(String(describing: error))
        }
    }

    /// Removal authority is ONLY a strictly validated publication pointer, never
    /// readiness/ABI/payload validity. No payload path is exposed or followed.
    /// Keep this token from confirmation through removal; do not refetch a newer
    /// revision on confirmation or a concurrent replacement could be removed.
    public struct RemovablePublication: Equatable, Sendable {
        public let modeID: String
        public let revision: String
    }

    public func removablePublication(modeID: String) throws -> RemovablePublication? {
        guard let revision = try activeRevision(modeID: modeID) else { return nil }
        return .init(modeID: modeID, revision: revision)
    }

    public func remove(_ publication: RemovablePublication) throws {
        try remove(modeID: publication.modeID, expectedRevision: publication.revision)
    }

    /// App-side compare-and-swap token lookup, including for incompatible/corrupt
    /// payloads. This grants NO read lease and must not be used to open engine files.
    public func activeRevision(modeID: String) throws -> String? {
        guard LanguagePackDescriptor.isIdentifier(modeID) else { throw LanguagePackError.invalidManifest("invalid mode") }
        guard try Self.exists(root) else { return nil }
        try Self.checkAncestors(root)
        let coordination = try Self.openLock(root.appendingPathComponent(".writer.lock"), exclusive: false)
        defer { close(coordination) }
        return try pointer(modeID: modeID)?.revision
    }

    /// App only. Deactivation is immediate. Returns before leased files are deleted.
    /// A waiting app-side reclaimer wakes when the last cross-process lease closes.
    /// If the app dies first, call reclaimUnusedVersions on its next launch.
    public func remove(modeID: String, expectedRevision: String?) throws {
        try remove(modeID: modeID, expectedRevision: expectedRevision, syncAfterUnlink: Self.syncDirectory)
    }

    /// Internal fault-injection seam replaces only post-commit directory sync.
    /// Pointer validation, compare-and-swap, unlink, locks and reclamation are real.
    func remove(modeID: String, expectedRevision: String?, syncAfterUnlink: (URL) throws -> Void) throws {
        guard LanguagePackDescriptor.isIdentifier(modeID) else { throw LanguagePackError.invalidManifest("invalid mode") }
        try prepare()
        let writer = try Self.openLock(root.appendingPathComponent(".writer.lock"), exclusive: true)
        var removed: String?
        do {
            let current = try pointer(modeID: modeID)
            guard current?.revision == expectedRevision else {
                throw LanguagePackError.revisionConflict(expected: expectedRevision, actual: current?.revision)
            }
            if let current {
                let url = pointerURL(modeID)
                guard unlink(url.path) == 0 else { throw Self.io("remove pointer") }
                removed = current.revision
                // Unlink is the commit point, just as rename is for publish().
                // A durability-sync failure cannot restore the old publication;
                // reporting failure here would leave the chooser's removed token
                // falsely active. Keep sync best-effort after the commit.
                try? syncAfterUnlink(root.appendingPathComponent("active"))
            }
            close(writer)
        } catch {
            close(writer)
            throw error
        }
        // Pointer unlink is the commit point. Damaged/foreign version contents
        // may prevent safe reclamation; never report that as failed deactivation
        // or relax the reclaimer's ownership/path/lease checks to force deletion.
        try? reclaimUnusedVersions()
        if let revision = removed {
            let storeRoot = root
            DispatchQueue.global(qos: .utility).async {
                let store = LanguagePackStore(root: storeRoot)
                let lease = storeRoot.appendingPathComponent("versions").appendingPathComponent(revision).appendingPathComponent(Self.leaseName)
                // Wait without holding the writer lock. Process death releases flock.
                if let fd = try? Self.openLock(lease, exclusive: true) {
                    close(fd)
                    try? store.reclaimUnusedVersions()
                }
            }
        }
    }

    /// App only. Never blocks on a live converter. Reclaims inactive immutable
    /// revisions and stages abandoned by dead writers; refuses malformed/foreign
    /// directory names and never follows links. No custom-word path is touched.
    public func reclaimUnusedVersions() throws {
        try prepare()
        let writer = try Self.openLock(root.appendingPathComponent(".writer.lock"), exclusive: true)
        defer { close(writer) }
        let activeDirectory = root.appendingPathComponent("active")
        var referenced = Set<String>()
        for name in try Self.fm.contentsOfDirectory(atPath: activeDirectory.path) {
            if name.hasPrefix(".pending-"), Self.isRevision(String(name.dropFirst(9))) {
                let stale = activeDirectory.appendingPathComponent(name)
                _ = try Self.readSmall(stale, limit: 4_096)
                guard unlink(stale.path) == 0 else { throw Self.io("remove stale pointer") }
                continue
            }
            guard name.hasSuffix(".json"), LanguagePackDescriptor.isIdentifier(String(name.dropLast(5))) else {
                throw LanguagePackError.corruptStore("foreign active pointer")
            }
            if let value = try pointer(modeID: String(name.dropLast(5))) { referenced.insert(value.revision) }
        }
        for name in try Self.fm.contentsOfDirectory(atPath: root.appendingPathComponent("versions").path) {
            guard Self.isRevision(name), !referenced.contains(name) else { continue }
            let directory = root.appendingPathComponent("versions").appendingPathComponent(name)
            try Self.checkDirectory(directory)
            try Self.checkVersionContents(directory)
            guard let fd = try Self.tryExclusiveLock(directory.appendingPathComponent(Self.leaseName)) else { continue }
            defer { close(fd) }
            try Self.fm.removeItem(at: directory)
        }
        // All writers hold coordination throughout populate/verification/publication.
        for name in try Self.fm.contentsOfDirectory(atPath: root.appendingPathComponent("staging").path) {
            guard Self.isRevision(name) else { continue }
            let stage = root.appendingPathComponent("staging").appendingPathComponent(name)
            try Self.checkDirectory(stage)
            guard (try? Self.readSmall(stage.appendingPathComponent(".owner"), limit: 64)) == Data(name.utf8) else { continue }
            try Self.fm.removeItem(at: stage)
        }
    }

    private struct Pointer: Codable {
        let format: Int
        let modeID: String
        let revision: String
    }

    private func pointerURL(_ modeID: String) -> URL {
        root.appendingPathComponent("active").appendingPathComponent(modeID + ".json")
    }

    private func pointer(modeID: String) throws -> Pointer? {
        try Self.checkDirectory(root.appendingPathComponent("active"))
        let url = pointerURL(modeID)
        guard try Self.exists(url) else { return nil }
        let value: Pointer
        do { value = try JSONDecoder().decode(Pointer.self, from: Self.readSmall(url, limit: 4_096)) }
        catch let error as LanguagePackError { throw error }
        catch { throw LanguagePackError.corruptStore("invalid active pointer") }
        guard value.format == 1, value.modeID == modeID, Self.isRevision(value.revision) else {
            throw LanguagePackError.corruptStore("invalid pointer identity")
        }
        return value
    }

    private func publish(_ pointer: Pointer) throws {
        let active = root.appendingPathComponent("active")
        let temp = active.appendingPathComponent(".pending-" + UUID().uuidString.lowercased())
        defer { try? Self.fm.removeItem(at: temp) }
        try Self.writeNew(JSONEncoder().encode(pointer), to: temp)
        try Self.rename(temp, pointerURL(pointer.modeID))
        // The rename is the commit point. A subsequent directory-sync failure must
        // not cause install's cleanup to remove the now-published version.
        try? Self.syncDirectory(active)
    }

    private func prepare() throws {
        guard root.isFileURL else { throw LanguagePackError.corruptStore("non-file root") }
        // Check existing ancestors before FileManager is allowed to create anything.
        try Self.checkAncestors(root.deletingLastPathComponent())
        if !(try Self.exists(root)) {
            do { try Self.makeDirectory(root) }
            catch { if !(try Self.exists(root)) { throw error } }
        }
        try Self.checkAncestors(root)
        for name in ["versions", "staging", "active"] {
            let url = root.appendingPathComponent(name)
            if !(try Self.exists(url)) {
                do { try Self.makeDirectory(url) }
                catch { if !(try Self.exists(url)) { throw error } }
            }
            try Self.checkDirectory(url)
        }
        let lockURL = root.appendingPathComponent(".writer.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDONLY | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Self.io("create coordination lock") }
        defer { close(fd) }
        try Self.checkRegular(fd)
    }

    private static func verifyPayload(_ payload: URL, descriptor: LanguagePackDescriptor) throws {
        try checkDirectory(payload)
        let expected = Dictionary(uniqueKeysWithValues: descriptor.files.map { ($0.path, $0) })
        var directories = Set<String>()
        for file in descriptor.files {
            var parts = file.path.split(separator: "/").map(String.init)
            parts.removeLast()
            while !parts.isEmpty {
                directories.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }
        var seen = Set<String>()
        func walk(_ directory: URL, prefix: String) throws {
            for name in try fm.contentsOfDirectory(atPath: directory.path) {
                let path = prefix + name
                let url = directory.appendingPathComponent(name)
                let attributes = try info(url)
                if attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                    guard directories.contains(path) else { throw LanguagePackError.invalidPayload("unexpected directory") }
                    try walk(url, prefix: path + "/")
                } else {
                    guard let file = expected[path], seen.insert(path).inserted else {
                        throw LanguagePackError.invalidPayload("unexpected file")
                    }
                    try verifyFile(url, byteCount: file.byteCount, sha256: file.sha256)
                }
            }
        }
        try walk(payload, prefix: "")
        guard seen.count == expected.count else { throw LanguagePackError.invalidPayload("missing files") }
    }

    private static func verifyFile(_ url: URL, byteCount: Int64, sha256: String) throws {
        try checkAncestors(url.deletingLastPathComponent())
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw io("open payload") }
        defer { close(fd) }
        let before = try checkRegular(fd)
        guard Int64(before.st_size) == byteCount, before.st_mode & mode_t(0o111) == 0 else {
            throw LanguagePackError.invalidPayload("file size or executable permission")
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var total: Int64 = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if count < 0 { if errno == EINTR { continue }; throw io("read payload") }
            if count == 0 { break }
            total += Int64(count)
            guard total <= byteCount else { throw LanguagePackError.invalidPayload("file grew during verification") }
            buffer.withUnsafeBytes { raw in hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: raw[..<count])) }
        }
        let after = try checkRegular(fd)
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard total == byteCount, after.st_size == before.st_size, digest == sha256 else {
            throw LanguagePackError.invalidPayload("file hash or size mismatch")
        }
    }

    private static func checkVersionContents(_ directory: URL) throws {
        let names = try Set(fm.contentsOfDirectory(atPath: directory.path))
        guard names == Set([metadataName, payloadName, leaseName, ".owner"]),
              try readSmall(directory.appendingPathComponent(".owner"), limit: 64) == Data(directory.lastPathComponent.utf8) else {
            throw LanguagePackError.corruptStore("unexpected version metadata")
        }
    }

    private static func isRevision(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    private static func exists(_ url: URL) throws -> Bool {
        var value = stat()
        if lstat(url.path, &value) == 0 { return true }
        if errno == ENOENT { return false }
        throw io("stat")
    }

    private static func info(_ url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw io("stat") }
        return value
    }

    private static func checkDirectory(_ url: URL) throws {
        guard try info(url).st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw LanguagePackError.corruptStore("not a regular directory")
        }
    }

    /// Only use at trusted injection boundaries, NEVER for payload descendants.
    /// Resolve the nearest existing ancestor with POSIX realpath, then append any
    /// not-yet-created suffix. Foundation's resolver can preserve the /var alias
    /// for absent descendants, defeating an otherwise correct lstat walk.
    private static func canonicalTrustedLocation(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        let original = url.standardizedFileURL
        var ancestor = original
        var suffix: [String] = []
        while true {
            if let resolved = realpath(ancestor.path, nil) {
                let path = String(cString: resolved)
                free(resolved)
                var canonical = URL(fileURLWithPath: path, isDirectory: true)
                for component in suffix.reversed() { canonical.appendPathComponent(component) }
                return canonical
            }
            // Permission/I/O failures remain failures at the normal validation
            // boundary; canonicalization must not reinterpret them as absence.
            guard errno == ENOENT, ancestor.path != "/" else { return original }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
    }

    private static func checkAncestors(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw LanguagePackError.corruptStore("invalid root") }
        var path = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            path.appendPathComponent(component)
            try checkDirectory(path)
        }
    }

    @discardableResult
    private static func checkRegular(_ fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw io("fstat") }
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_nlink == 1 else {
            throw LanguagePackError.invalidPayload("link or irregular file")
        }
        return value
    }

    private static func makeDirectory(_ url: URL) throws {
        guard mkdir(url.path, mode_t(0o700)) == 0 else { throw io("mkdir") }
    }

    private static func openLock(_ url: URL, exclusive: Bool) throws -> Int32 {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw io("open lock") }
        do {
            try checkRegular(fd)
            while flock(fd, exclusive ? LOCK_EX : LOCK_SH) != 0 {
                if errno != EINTR { throw io("flock") }
            }
            return fd
        } catch { close(fd); throw error }
    }

    private static func tryExclusiveLock(_ url: URL) throws -> Int32? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw io("open lease") }
        do {
            try checkRegular(fd)
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
            if errno == EWOULDBLOCK || errno == EAGAIN { close(fd); return nil }
            throw io("try flock")
        } catch { close(fd); throw error }
    }

    private static func readSmall(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw io("open metadata") }
        defer { close(fd) }
        let attributes = try checkRegular(fd)
        guard attributes.st_size >= 0, Int64(attributes.st_size) <= Int64(limit) else { throw LanguagePackError.corruptStore("metadata size") }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw io("read metadata") }
            if count == 0 { return result }
            guard result.count + count <= limit else { throw LanguagePackError.corruptStore("metadata grew") }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeNew(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw io("create metadata") }
        defer { close(fd) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw io("write metadata") }
                guard count > 0 else { throw LanguagePackError.corruptStore("short write") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw io("sync metadata") }
    }

    private static func rename(_ from: URL, _ to: URL) throws {
        #if canImport(Darwin)
        let result = Darwin.rename(from.path, to.path)
        #else
        let result = Glibc.rename(from.path, to.path)
        #endif
        guard result == 0 else { throw io("rename") }
    }

    private static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw io("open directory") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw io("sync directory") }
    }

    private static func io(_ operation: String) -> LanguagePackError {
        .filesystem(operation: operation, code: errno)
    }
}
