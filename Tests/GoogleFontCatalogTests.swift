#if canImport(UIKit)
import XCTest
import CryptoKit
@testable import Uniboard

final class GoogleFontCatalogTests: XCTestCase {
    private func fixture(path: String = "ofl/test/Test.ttf", pin: String = GoogleFontCatalog.trustedRepositoryCommit, bytes: Int64 = 100, reason: String? = nil) -> GoogleFontCatalogSnapshot {
        let text = "Full license notice\n"
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return GoogleFontCatalogSnapshot(schemaVersion: 1, repositoryCommit: pin, snapshotDate: "2026-10-23", families: [GoogleFontFamily(id: "test", name: "Fixture Sans", styles: [GoogleFontStyle(id: "regular", name: "Regular", fileID: "file", postScriptName: "Fixture-Regular")])], files: [GoogleFontFile(id: "file", repositoryPath: path, bytes: bytes, sha256: String(repeating: "a", count: 64), expectedPostScriptNames: ["Fixture-Regular"], licenseIDs: ["license"], unavailableReason: reason)], licenses: [GoogleFontLicense(id: "license", name: "Test License", repositoryPath: "ofl/test/OFL.txt", sha256: hash, text: text)])
    }
    func testLocalSearchAndPinnedURL() throws {
        let catalog = try GoogleFontCatalog(snapshot: fixture())
        XCTAssertEqual(catalog.search("FIXTURE").count, 1)
        XCTAssertTrue(catalog.search("absent").isEmpty)
        let url = try catalog.downloadURL(for: XCTUnwrap(catalog.file(id: "file")))
        XCTAssertEqual(url.host, "raw.githubusercontent.com")
        XCTAssertTrue(url.path.contains(GoogleFontCatalog.trustedRepositoryCommit))
    }
    func testRejectsTraversalAndUntrustedPin() {
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: fixture(path: "ofl/test/../evil.ttf")))
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: fixture(pin: String(repeating: "b", count: 40))))
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: fixture(path: "ofl/test/%2e%2e.ttf")))
    }
    func testOversizedFilesRemainSearchableButNotDownloadable() throws {
        let size = GoogleFontCatalog.maximumFileBytes + 1
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: fixture(bytes: size)))
        let catalog = try GoogleFontCatalog(snapshot: fixture(bytes: size, reason: "Exceeds 40 MiB"))
        XCTAssertEqual(catalog.search("").count, 1)
        XCTAssertThrowsError(try catalog.downloadURL(for: XCTUnwrap(catalog.file(id: "file"))))
    }
    func testRoundTripAndMalformedData() throws {
        let catalog = try GoogleFontCatalog.decode(JSONEncoder().encode(fixture()))
        XCTAssertEqual(catalog.snapshot.families.first?.name, "Fixture Sans")
        XCTAssertThrowsError(try GoogleFontCatalog.decode(Data("{}".utf8)))
    }
    func testRejectsDuplicateIdentifiersAndUnresolvedReferences() throws {
        let value = fixture()
        let duplicate = GoogleFontCatalogSnapshot(schemaVersion: value.schemaVersion, repositoryCommit: value.repositoryCommit, snapshotDate: value.snapshotDate, families: value.families, files: value.files + value.files, licenses: value.licenses)
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: duplicate))
        let missing = GoogleFontCatalogSnapshot(schemaVersion: value.schemaVersion, repositoryCommit: value.repositoryCommit, snapshotDate: value.snapshotDate, families: [GoogleFontFamily(id: "broken", name: "Broken", styles: [GoogleFontStyle(id: "bad", name: "Regular", fileID: "absent", postScriptName: "Broken")])], files: value.files, licenses: value.licenses)
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: missing))
    }
    func testCompleteBundledCatalogLoadsOffline() throws {
        let catalog = try GoogleFontCatalog.load()
        XCTAssertEqual(catalog.snapshot.families.count, 2065)
        XCTAssertFalse(catalog.search("Noto Sans").isEmpty)
        XCTAssertFalse(catalog.search("Roboto").isEmpty)
    }
}
#endif
