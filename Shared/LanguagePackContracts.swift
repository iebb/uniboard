import Foundation

/// Data-only metadata supplied by the containing app's trusted, pinned catalog.
/// Decoding is not validation: use `validated(from:)` at the filesystem boundary.
public struct LanguagePackDescriptor: Codable, Equatable, Sendable {
    public static let manifestFormatVersion = 1
    public static let maximumManifestBytes = 2 * 1_024 * 1_024
    public static let maximumFileCount = 4_096
    public static let maximumInstalledBytes: Int64 = 256 * 1_024 * 1_024
    public static let maximumArchiveBytes: Int64 = 256 * 1_024 * 1_024

    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let byteCount: Int64
        public let sha256: String

        public init(path: String, byteCount: Int64, sha256: String) {
            self.path = path
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public let formatVersion: Int
    public let packID: String
    public let version: String
    public let modeID: String
    public let engineABI: String
    public let sourceURL: URL
    public let allowedHosts: [String]
    public let archiveByteCount: Int64
    public let archiveSHA256: String
    public let installedBytes: Int64
    public let fileCount: Int
    public let files: [File]
    /// Complete license/copyright and source attribution text, not just an SPDX label.
    public let licenseNotice: String
    public let sourceNotice: String

    public init(formatVersion: Int = Self.manifestFormatVersion, packID: String, version: String,
                modeID: String, engineABI: String, sourceURL: URL, allowedHosts: [String],
                archiveByteCount: Int64, archiveSHA256: String, installedBytes: Int64,
                fileCount: Int, files: [File], licenseNotice: String, sourceNotice: String) {
        self.formatVersion = formatVersion
        self.packID = packID
        self.version = version
        self.modeID = modeID
        self.engineABI = engineABI
        self.sourceURL = sourceURL
        self.allowedHosts = allowedHosts
        self.archiveByteCount = archiveByteCount
        self.archiveSHA256 = archiveSHA256
        self.installedBytes = installedBytes
        self.fileCount = fileCount
        self.files = files
        self.licenseNotice = licenseNotice
        self.sourceNotice = sourceNotice
    }

    public static func validated(from data: Data) throws -> Self {
        guard data.count <= maximumManifestBytes else { throw LanguagePackError.invalidManifest("manifest size") }
        let descriptor: Self
        do { descriptor = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw LanguagePackError.invalidManifest("invalid JSON descriptor") }
        try descriptor.validate()
        return descriptor
    }

    public func validate() throws {
        func require(_ condition: Bool, _ reason: String) throws {
            guard condition else { throw LanguagePackError.invalidManifest(reason) }
        }
        try require(formatVersion == Self.manifestFormatVersion, "unsupported manifest format")
        for identifier in [packID, version, modeID, engineABI] {
            try require(Self.isIdentifier(identifier), "invalid identifier")
        }
        try require(!allowedHosts.isEmpty && allowedHosts.count <= 16, "invalid allowed hosts")
        try require(Set(allowedHosts).count == allowedHosts.count, "duplicate hosts")
        for host in allowedHosts {
            try require(!host.isEmpty && host.utf8.count <= 253 && host == host.lowercased()
                        && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
                            !$0.isEmpty && $0.utf8.count <= 63 && $0.first != "-" && $0.last != "-"
                            && $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
                        }, "invalid host")
        }
        try require(sourceURL.scheme == "https" && sourceURL.user == nil && sourceURL.password == nil
                    && sourceURL.fragment == nil && (sourceURL.port == nil || sourceURL.port == 443)
                    && allowedHosts.contains(sourceURL.host?.lowercased() ?? ""), "untrusted source URL")
        try require(archiveByteCount > 0 && archiveByteCount <= Self.maximumArchiveBytes, "archive size")
        try require(Self.isSHA256(archiveSHA256), "archive hash")
        try require(fileCount > 0 && fileCount <= Self.maximumFileCount && fileCount == files.count, "file count")
        try require(installedBytes >= 0 && installedBytes <= Self.maximumInstalledBytes, "installed size")
        try require(!licenseNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !sourceNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "missing notices")
        var paths = Set<String>()
        var total: Int64 = 0
        for file in files {
            try require(Self.isPayloadPath(file.path), "invalid payload path")
            // Reject Unicode/case aliases as well as exact duplicates on case-insensitive App Group volumes.
            let key = file.path.precomposedStringWithCanonicalMapping.lowercased()
            try require(paths.insert(key).inserted, "duplicate or aliased payload path")
            try require(file.byteCount >= 0 && file.byteCount <= Self.maximumInstalledBytes, "file size")
            total += file.byteCount // At most 4096 * 256 MiB: cannot overflow Int64.
            try require(total <= Self.maximumInstalledBytes, "payload too large")
            try require(Self.isSHA256(file.sha256), "file hash")
        }
        for path in paths {
            var components = path.split(separator: "/").map(String.init)
            components.removeLast()
            while !components.isEmpty {
                try require(!paths.contains(components.joined(separator: "/")), "file/directory collision")
                components.removeLast()
            }
        }
        try require(total == installedBytes, "installed size mismatch")
        try require(JSONEncoder().encode(self).count <= Self.maximumManifestBytes, "manifest size")
    }

    static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value != "." && value != ".."
        && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
            || $0 == 45 || $0 == 95 || $0 == 46
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func isPayloadPath(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 1_024, !value.contains("\\"),
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              value.utf8.elementsEqual(value.precomposedStringWithCanonicalMapping.utf8) else { return false }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255
        }
    }
}

public enum LanguagePackError: Error, Equatable, Sendable {
    case invalidManifest(String)
    case invalidPayload(String)
    case revisionConflict(expected: String?, actual: String?)
    case filesystem(operation: String, code: Int32)
    case corruptStore(String)
}

public struct ValidatedInstalledLanguagePack: Equatable, Sendable {
    /// Unique immutable installation identity, not the upstream version string.
    public let revision: String
    public let path: URL
    public let descriptor: LanguagePackDescriptor
}

/// Holds an OS shared lock until released/deinitialized. Keep this alive for the ENTIRE
/// converter lifetime, including lazy shard loads. It never writes to the App Group.
/// Do not call release while a converter still uses `pack.path`.
public final class LanguagePackReadLease {
    public let pack: ValidatedInstalledLanguagePack
    private let lock = NSLock()
    private var releaseAction: (() -> Void)?

    init(pack: ValidatedInstalledLanguagePack, release: @escaping () -> Void) {
        self.pack = pack
        self.releaseAction = release
    }

    public func release() {
        lock.lock()
        let action = releaseAction
        releaseAction = nil
        lock.unlock()
        action?()
    }

    deinit { release() }
}

public enum LanguagePackResolution {
    /// Store root does not exist (no installation has ever been prepared here).
    case absent
    /// No published pointer for this mode (including explicit removal).
    case missing
    case unreadable
    case incompatible(requiredABI: String, installedABI: String)
    case corrupt(String)
    case available(LanguagePackReadLease)
}

public enum LanguagePackPublicationCheckpoint: Sendable {
    case verifiedStage
    case renamedVersion
    case beforePointerPublication
}
