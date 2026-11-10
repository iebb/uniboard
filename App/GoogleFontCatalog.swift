import Foundation
import CryptoKit

public struct GoogleFontCatalogSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let repositoryCommit: String
    public let snapshotDate: String
    public let families: [GoogleFontFamily]
    public let files: [GoogleFontFile]
    public let licenses: [GoogleFontLicense]

    public init(schemaVersion: Int, repositoryCommit: String, snapshotDate: String, families: [GoogleFontFamily], files: [GoogleFontFile], licenses: [GoogleFontLicense]) {
        self.schemaVersion = schemaVersion
        self.repositoryCommit = repositoryCommit
        self.snapshotDate = snapshotDate
        self.families = families
        self.files = files
        self.licenses = licenses
    }
}

public struct GoogleFontFamily: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let styles: [GoogleFontStyle]

    public init(id: String, name: String, styles: [GoogleFontStyle]) {
        self.id = id
        self.name = name
        self.styles = styles
    }
}

public struct GoogleFontStyle: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let fileID: String
    public let postScriptName: String
    public let variationInstance: [String: Double]?
    /// Schema 2: the same named instance as one pinned static file on fonts.gstatic.com.
    public let instance: GoogleFontInstance?

    public init(id: String, name: String, fileID: String, postScriptName: String, variationInstance: [String: Double]? = nil,
                instance: GoogleFontInstance? = nil) {
        self.id = id
        self.name = name
        self.fileID = fileID
        self.postScriptName = postScriptName
        self.variationInstance = variationInstance
        self.instance = instance
    }
}

/// A single-style static TTF resolved at catalog-build time through the Google
/// Fonts CSS2 API and accepted only when its cmap and font revision equal the
/// pinned repository file's (Scripts/generate-google-font-catalog.py). The app
/// never calls the API: it fetches exactly this path from fonts.gstatic.com and
/// checks the size, SHA-256 and PostScript name (name ID 6).
public struct GoogleFontInstance: Codable, Sendable, Equatable, Hashable {
    /// "s/<family>/v<n>/<name>.ttf", relative to https://fonts.gstatic.com/.
    public let path: String
    public let bytes: Int64
    public let sha256: String
    /// The static file's own name ID 6 ("RobotoCondensed-Bold"), not the variable instance's.
    public let postScriptName: String

    public init(path: String, bytes: Int64, sha256: String, postScriptName: String) {
        self.path = path; self.bytes = bytes; self.sha256 = sha256; self.postScriptName = postScriptName
    }

    /// The download/receipt identity; never a repository path.
    public var id: String { GoogleFontCatalog.instanceIDPrefix + path }
    public var filename: String { (path as NSString).lastPathComponent }
}

public struct GoogleFontFile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let repositoryPath: String
    public let bytes: Int64
    public let sha256: String
    public let expectedPostScriptNames: [String]
    public let licenseIDs: [String]
    public let unavailableReason: String?

    public init(id: String, repositoryPath: String, bytes: Int64, sha256: String, expectedPostScriptNames: [String], licenseIDs: [String], unavailableReason: String? = nil) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.bytes = bytes
        self.sha256 = sha256
        self.expectedPostScriptNames = expectedPostScriptNames
        self.licenseIDs = licenseIDs
        self.unavailableReason = unavailableReason
    }
}

public struct GoogleFontLicense: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let repositoryPath: String
    public let sha256: String
    public let text: String

    public init(id: String, name: String, repositoryPath: String, sha256: String, text: String) {
        self.id = id
        self.name = name
        self.repositoryPath = repositoryPath
        self.sha256 = sha256
        self.text = text
    }
}

/// Offline-only metadata. No networking or font registration occurs here.
public struct GoogleFontCatalog: Sendable {
    public static let trustedRepositoryCommit = "e7db6ca603fd4862010383ff17ffd6cc4ffac1c0"
    public static let maximumFileBytes: Int64 = 40 * 1024 * 1024
    public static let instanceHost = GoogleFontURLShape.instanceHost
    public static let instanceIDPrefix = GoogleFontURLShape.instanceIDPrefix
    public let snapshot: GoogleFontCatalogSnapshot
    private let filesByID: [String: GoogleFontFile]
    private let licensesByID: [String: GoogleFontLicense]
    /// Instance id → (instance, the repository file it stands in for).
    private let instancesByID: [String: (instance: GoogleFontInstance, fileID: String)]

    public enum CatalogError: Error, LocalizedError {
        case resourceMissing
        case invalid(String)
        public var errorDescription: String? {
            switch self {
            case .resourceMissing: return "Couldn’t load Google Fonts. The bundled catalog is missing."
            case .invalid(let reason): return "Couldn’t load Google Fonts: \(reason)"
            }
        }
    }

    public init(snapshot: GoogleFontCatalogSnapshot) throws {
        try Self.validate(snapshot)
        self.snapshot = snapshot
        filesByID = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.id, $0) })
        licensesByID = Dictionary(uniqueKeysWithValues: snapshot.licenses.map { ($0.id, $0) })
        var instances: [String: (instance: GoogleFontInstance, fileID: String)] = [:]
        for family in snapshot.families { for style in family.styles { if let instance = style.instance { instances[instance.id] = (instance, style.fileID) } } }
        instancesByID = instances
    }

    public static func load(bundle: Bundle = .main) throws -> GoogleFontCatalog {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "GoogleFonts")
                ?? bundle.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> GoogleFontCatalog {
        guard data.count <= 32 * 1024 * 1024 else { throw CatalogError.invalid("Catalog is too large") }
        return try GoogleFontCatalog(snapshot: JSONDecoder().decode(GoogleFontCatalogSnapshot.self, from: data))
    }

    public func search(_ query: String) -> [GoogleFontFamily] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.families.filter { text.isEmpty || $0.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    public func file(id: String) -> GoogleFontFile? { filesByID[id] }
    public func license(id: String) -> GoogleFontLicense? { licensesByID[id] }
    public func instance(id: String) -> GoogleFontInstance? { instancesByID[id]?.instance }
    /// The repository file an instance was validated against; its licenses apply.
    public func file(forInstance id: String) -> GoogleFontFile? { instancesByID[id].flatMap { filesByID[$0.fileID] } }

    /// Only a catalog instance; host and scheme come from app code, the path is re-checked.
    public func downloadURL(for instance: GoogleFontInstance) throws -> URL {
        guard instancesByID[instance.id]?.instance == instance, Self.safeInstancePath(instance.path),
              instance.bytes > 0, instance.bytes <= Self.maximumFileBytes,
              file(forInstance: instance.id)?.unavailableReason == nil,
              let url = URL(string: "https://\(Self.instanceHost)/" + instance.path) else {
            throw CatalogError.invalid("Instance is unavailable or is not part of this catalog")
        }
        return url
    }

    /// "s/<lowercase family>/v<digits>/<base64url>.ttf" and nothing else.
    static func safeInstancePath(_ path: String) -> Bool { GoogleFontURLShape.isInstancePath(path) }

    /// URL authority and commit never come from a downloadable payload.
    public func downloadURL(for file: GoogleFontFile) throws -> URL {
        guard filesByID[file.id] == file, Self.safePath(file.repositoryPath),
              file.unavailableReason == nil, file.bytes <= Self.maximumFileBytes else {
            throw CatalogError.invalid("File is unavailable or is not part of this catalog")
        }
        let root = URL(string: "https://raw.githubusercontent.com/google/fonts/\(Self.trustedRepositoryCommit)/")!
        return root.appendingPathComponent(file.repositoryPath)
    }

    private static func safePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 3 && ["ofl", "apache", "ufl"].contains(String(parts[0]))
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
            && !path.contains(where: { "\\?#%".contains($0) || $0.isNewline || $0.asciiValue == 0 })
    }

    private static func validate(_ value: GoogleFontCatalogSnapshot) throws {
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition { throw CatalogError.invalid(reason) }
        }
        func digest(_ text: String) -> Bool {
            text.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        func unique(_ ids: [String]) -> Bool { !ids.contains("") && Set(ids).count == ids.count }
        try require(value.schemaVersion == 1 || value.schemaVersion == 2, "Unsupported schema")
        try require(value.repositoryCommit == trustedRepositoryCommit, "Untrusted repository commit")
        try require(value.snapshotDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, "Invalid snapshot date")
        try require(!value.families.isEmpty && !value.files.isEmpty && !value.licenses.isEmpty, "Empty catalog")
        try require(unique(value.families.map(\.id)) && unique(value.files.map(\.id)) && unique(value.licenses.map(\.id)), "Duplicate or empty identifiers")
        let fileMap = Dictionary(uniqueKeysWithValues: value.files.map { ($0.id, $0) })
        let licenseIDs = Set(value.licenses.map(\.id))
        for license in value.licenses {
            try require(safePath(license.repositoryPath) && !license.name.isEmpty && !license.text.isEmpty && digest(license.sha256), "Invalid license")
            let hash = SHA256.hash(data: Data(license.text.utf8)).map { String(format: "%02x", $0) }.joined()
            try require(hash == license.sha256, "License checksum mismatch")
        }
        for file in value.files {
            try require(safePath(file.repositoryPath) && file.bytes > 0 && digest(file.sha256), "Invalid file")
            try require(!file.expectedPostScriptNames.isEmpty && unique(file.expectedPostScriptNames), "Missing face identities")
            try require((!file.licenseIDs.isEmpty || file.unavailableReason != nil) && unique(file.licenseIDs) && Set(file.licenseIDs).isSubset(of: licenseIDs), "Missing file license")
            try require(file.unavailableReason == nil || !file.unavailableReason!.isEmpty, "Empty availability reason")
            if file.bytes > maximumFileBytes || !["ttf", "otf"].contains((file.repositoryPath as NSString).pathExtension.lowercased()) {
                try require(file.unavailableReason != nil, "Unsupported file lacks reason")
            }
        }
        var allStyleIDs = [String]()
        var referenced = Set<String>()
        var instances: [String: GoogleFontInstance] = [:]
        for family in value.families {
            try require(!family.name.isEmpty && !family.styles.isEmpty, "Empty family")
            for style in family.styles {
                try require(!style.name.isEmpty && !style.postScriptName.isEmpty && fileMap[style.fileID] != nil, "Invalid style reference")
                if let axes = style.variationInstance {
                    try require(!axes.isEmpty && axes.allSatisfy { $0.key.utf8.count == 4 && $0.value.isFinite }, "Invalid variation coordinates")
                }
                if let instance = style.instance {
                    // Schema 2 only; an instance stands in for a named instance of an available variable file.
                    try require(value.schemaVersion == 2 && style.variationInstance != nil && fileMap[style.fileID]?.unavailableReason == nil,
                                "Unexpected instance")
                    try require(safeInstancePath(instance.path) && instance.bytes > 0 && instance.bytes <= maximumFileBytes
                                && digest(instance.sha256) && !instance.postScriptName.isEmpty
                                && !instance.postScriptName.contains(where: { $0.isNewline || $0.asciiValue == 0 }), "Invalid instance")
                    // One path, one set of bytes.
                    if let other = instances[instance.path] { try require(other == instance, "Conflicting instance") }
                    instances[instance.path] = instance
                }
                allStyleIDs.append(style.id); referenced.insert(style.fileID)
            }
        }
        try require(unique(allStyleIDs) && referenced == Set(fileMap.keys), "Duplicate styles or unreferenced files")
    }
}
