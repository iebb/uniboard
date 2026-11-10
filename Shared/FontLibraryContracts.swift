import Foundation

struct FontFaceID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}
enum FontSource: String, Codable, Hashable, Sendable { case system, included, downloaded, installed, imported, available }
enum FontLocator: Codable, Hashable, Sendable {
    case process(postScriptName: String, variations: [String: Double])
    case file(relativePath: String, sha256: String, faceIndex: Int, variations: [String: Double])
}
struct FontFaceRecord: Codable, Hashable, Identifiable, Sendable {
    let id: FontFaceID
    let family: String
    let style: String
    let postScriptName: String
    let source: FontSource
    let locator: FontLocator
    let assetID: String?
    /// The same face in another catalog file (1.4: a pinned single-style
    /// instance and its named instance in the variable file). Content
    /// identities only (`relativePath` is empty); a rule naming one resolves
    /// to the other when only one file is kept. Old manifests omit this; the
    /// bundled catalog supplies the same relationships in memory at read time.
    var equivalents: [FontLocator]? = nil
}
struct FontLibrarySnapshot: Codable, Sendable {
    let generation: String
    let faces: [FontFaceRecord]
    let customEntryCount: Int
}
enum FontLibraryFailure: Error, Equatable, Sendable {
    case offline, transport, invalidFile, registration
    case tooLarge(limitBytes: Int64), tooMany(limit: Int)
    case storageUnavailable, storageFailure
}
enum GoogleFontDownloadState: Equatable, Sendable {
    case ready, queued, downloading(received: Int64, expected: Int64?), preparing
    case downloaded(assetID: String), cancelled, failed(FontLibraryFailure)
}
/// Persisted independently of the app-only Google catalog.
struct FontLibraryLicense: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let repositoryPath: String
    let sha256: String
    let text: String
}
/// The one gstatic shape the app fetches and stores receipts for (app and keyboard share it).
enum GoogleFontURLShape {
    static let instanceHost = "fonts.gstatic.com"
    static let instanceIDPrefix = "gstatic:"
    /// "s/<lowercase family>/v<digits>/<base64url>.ttf" and nothing else.
    static func isInstancePath(_ path: String) -> Bool {
        path.range(of: #"^s/[a-z0-9]+/v[0-9]+/[A-Za-z0-9_-]+\.ttf$"#, options: .regularExpression) != nil
    }
}

/// Where downloaded bytes came from. nil (1.3 receipts) means the pinned GitHub repository.
enum FontLibrarySourceKind: String, Codable, Sendable { case repository, gstatic }
struct FontLibraryReceipt: Codable, Sendable {
    let fileID: String
    let repositoryCommit: String
    /// For a gstatic instance: the pinned repository file whose cmap and version it matched.
    let repositoryPath: String
    let snapshotDate: String
    let sha256: String
    let licenses: [FontLibraryLicense]
    var sourceKind: FontLibrarySourceKind? = nil
    /// The exact URL fetched, for the receipt; never used to fetch again.
    var sourceURL: String? = nil
}

struct FontLibraryReadState: Sendable {
    let snapshot: FontLibrarySnapshot
    let receipts: [String: FontLibraryReceipt]
    let assetIDs: [String: String]
}

/// Read-only projection of the shipped catalog, shared by app and keyboard.
/// Only exact content hash + face index + complete instance coordinates establish
/// equivalence. Names, Google IDs, receipts and imported filenames are not evidence.
/// No manifest/binary/reference is migrated and no network request is made.
struct FontCatalogEquivalenceIndex: Sendable {
    private let byIdentity: [String: [FontLocator]]
    static let empty = FontCatalogEquivalenceIndex(byIdentity: [:])

    func equivalents(for locator: FontLocator) -> [FontLocator] {
        guard case .file = locator, let key = FontFaceReference.identityKey(of: locator) else { return [] }
        return byIdentity[key] ?? []
    }

    private struct Projection: Decodable {
        let schemaVersion: Int
        let repositoryCommit: String
        let files: [File]
        let families: [Family]
        struct File: Decodable { let id: String; let sha256: String; let unavailableReason: String? }
        struct Family: Decodable { let styles: [Style] }
        struct Style: Decodable {
            let fileID: String
            let variationInstance: [String: Double]?
            let instance: Instance?
        }
        struct Instance: Decodable { let path: String; let sha256: String }
    }

    /// Decode only identity fields, not licenses/coverage/display metadata. Fail
    /// closed if the resource is absent, from a different pin, or malformed.
    static func decode(_ data: Data) -> FontCatalogEquivalenceIndex? {
        guard data.count <= 32 * 1024 * 1024,
              let catalog = try? JSONDecoder().decode(Projection.self, from: data),
              catalog.schemaVersion == 2,
              catalog.repositoryCommit == "e7db6ca603fd4862010383ff17ffd6cc4ffac1c0",
              Set(catalog.files.map(\.id)).count == catalog.files.count else { return nil }
        let files = Dictionary(uniqueKeysWithValues: catalog.files.map { ($0.id, $0) })
        var pairs: [String: [FontLocator]] = [:]
        func validHash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        func append(_ locator: FontLocator, to key: String) {
            if !(pairs[key] ?? []).contains(locator) { pairs[key, default: []].append(locator) }
        }
        for family in catalog.families {
            for style in family.styles {
                guard let instance = style.instance else { continue }
                guard let file = files[style.fileID], file.unavailableReason == nil,
                      validHash(file.sha256), validHash(instance.sha256), file.sha256 != instance.sha256,
                      GoogleFontURLShape.isInstancePath(instance.path),
                      let axes = style.variationInstance, !axes.isEmpty,
                      axes.allSatisfy({ $0.key.utf8.count == 4 && $0.value.isFinite }),
                      FontFaceReference.tags(axes) == axes else { return nil }
                let shared = FontLocator.file(relativePath: "", sha256: file.sha256, faceIndex: 0, variations: axes)
                let own = FontLocator.file(relativePath: "", sha256: instance.sha256, faceIndex: 0, variations: [:])
                guard let sharedKey = FontFaceReference.identityKey(of: shared),
                      let ownKey = FontFaceReference.identityKey(of: own) else { return nil }
                append(own, to: sharedKey)
                append(shared, to: ownKey)
            }
        }
        return FontCatalogEquivalenceIndex(byIdentity: pairs)
    }

    static let bundled: FontCatalogEquivalenceIndex = {
        #if canImport(UIKit)
        // The extension reads its containing app's immutable resource, not the
        // App Group or an external path. It works without keyboard Full Access.
        // Keep only the compact identity index after this one lazy decode.
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension == "appex",
           let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()),
           app.bundleURL.pathExtension == "app" { bundles.append(app) }
        for bundle in bundles {
            guard let url = bundle.url(forResource: "equivalences", withExtension: "json", subdirectory: "GoogleFonts"),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 32 * 1024 * 1024,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let index = decode(data) else { continue }
            return index
        }
        return .empty
        #else
        return .empty
        #endif
    }()
}

/// File-oriented projection, not a new storage/deduplication policy. One row is
/// one existing capacity entry; receipts, families and styles are not entries.
struct FontManagedEntry: Identifiable, Equatable, Sendable {
    let filename: String
    let sha256: String
    let displayName: String
    let installed: Bool
    let faces: [FontFaceRecord]
    /// Verified local binary bytes only. nil for unavailable files AND installed references.
    let verifiedBytes: Int64?
    var receiptIDs: [String] = []
    var id: String { filename }
    var styleCount: Int { faces.count }

    func uses(_ reference: FontFaceReference) -> Bool {
        faces.contains { $0.identityKeys.contains(reference.identityKey) }
    }
}

struct FontManagementSnapshot: Sendable {
    let generation: String
    let entries: [FontManagedEntry]
    var files: [FontManagedEntry] { entries.filter { !$0.installed } }
    var installed: [FontManagedEntry] { entries.filter(\.installed) }
    var used: Int { entries.count }
    /// No zero-byte substitution for an unreadable binary.
    var verifiedTotalBytes: Int64? {
        guard files.allSatisfy({ $0.verifiedBytes != nil }) else { return nil }
        return files.reduce(0) { $0 + ($1.verifiedBytes ?? 0) }
    }

    func references(to entry: FontManagedEntry, rules: [FontRule]) -> [FontManagedRuleUse] {
        rules.compactMap { rule in
            guard entry.uses(rule.face) else { return nil }
            let styles = entry.faces.filter { $0.identityKeys.contains(rule.face.identityKey) }.map(\.style)
            let alternatives = entries.filter { $0.id != entry.id && !$0.installed && $0.verifiedBytes != nil && $0.uses(rule.face) }
            return FontManagedRuleUse(rule: rule, styles: styles, otherFilenames: alternatives.map(\.filename))
        }
    }
}

struct FontManagedRuleUse: Identifiable, Equatable, Sendable {
    let rule: FontRule
    let styles: [String]
    let otherFilenames: [String]
    var id: String { rule.id }
}

enum FontManagementFailure: Error { case changed, rulesUnavailable }
