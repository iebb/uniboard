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
struct FontLibraryReceipt: Codable, Sendable {
    let fileID: String
    let repositoryCommit: String
    let repositoryPath: String
    let snapshotDate: String
    let sha256: String
    let licenses: [FontLibraryLicense]
}

struct FontLibraryReadState: Sendable {
    let snapshot: FontLibrarySnapshot
    let receipts: [String: FontLibraryReceipt]
    let assetIDs: [String: String]
}
