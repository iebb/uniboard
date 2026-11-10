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
    /// Schema 2: one variable style with a pinned single-style instance.
    private func instanceFixture(schema: Int = 2, path: String = "s/fixturesans/v3/AbC_d-1.ttf", variable: Bool = true,
                                 extra: GoogleFontInstance? = nil) -> GoogleFontCatalogSnapshot {
        let value = fixture()
        let instance = GoogleFontInstance(path: path, bytes: 50, sha256: String(repeating: "c", count: 64), postScriptName: "FixtureSans-Bold")
        var styles = [GoogleFontStyle(id: "bold", name: "Bold", fileID: "file", postScriptName: "Fixture-Bold",
                                      variationInstance: variable ? ["wght": 700] : nil, instance: instance)]
        if let extra { styles.append(GoogleFontStyle(id: "other", name: "Black", fileID: "file", postScriptName: "Fixture-Black", variationInstance: ["wght": 900], instance: extra)) }
        return GoogleFontCatalogSnapshot(schemaVersion: schema, repositoryCommit: value.repositoryCommit, snapshotDate: value.snapshotDate,
                                         families: [GoogleFontFamily(id: "test", name: "Fixture Sans", styles: styles)], files: value.files, licenses: value.licenses)
    }
    func testInstancesArePinnedToGstaticPathsOnly() throws {
        let catalog = try GoogleFontCatalog(snapshot: instanceFixture())
        let instance = try XCTUnwrap(catalog.snapshot.families[0].styles[0].instance)
        XCTAssertEqual(instance.id, "gstatic:s/fixturesans/v3/AbC_d-1.ttf")
        XCTAssertEqual(catalog.instance(id: instance.id), instance)
        XCTAssertEqual(catalog.file(forInstance: instance.id)?.id, "file")
        XCTAssertEqual(try catalog.downloadURL(for: instance).absoluteString, "https://fonts.gstatic.com/s/fixturesans/v3/AbC_d-1.ttf")
        // Not part of this catalog: refused even with the same shape.
        XCTAssertThrowsError(try catalog.downloadURL(for: GoogleFontInstance(path: instance.path, bytes: 51, sha256: instance.sha256, postScriptName: "X")))
        for bad in ["s/fixturesans/v3/../x.ttf", "s/Fixture/v3/x.ttf", "s/fixturesans/3/x.ttf", "s/fixturesans/v3/x.woff2",
                    "https://fonts.gstatic.com/s/fixturesans/v3/x.ttf", "s/fixturesans/v3/x.ttf?y", "/s/fixturesans/v3/x.ttf", "s/fixturesans/v3/a/b.ttf"] {
            XCTAssertThrowsError(try GoogleFontCatalog(snapshot: instanceFixture(path: bad)), bad)
        }
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: instanceFixture(schema: 1)), "Instances need schema 2")
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: instanceFixture(variable: false)), "Only a named instance of a variable file")
        // One path, one set of bytes.
        let conflicting = GoogleFontInstance(path: "s/fixturesans/v3/AbC_d-1.ttf", bytes: 60, sha256: String(repeating: "d", count: 64), postScriptName: "FixtureSans-Black")
        XCTAssertThrowsError(try GoogleFontCatalog(snapshot: instanceFixture(extra: conflicting)))
        let same = GoogleFontInstance(path: "s/fixturesans/v3/AbC_d-1.ttf", bytes: 50, sha256: String(repeating: "c", count: 64), postScriptName: "FixtureSans-Bold")
        XCTAssertNoThrow(try GoogleFontCatalog(snapshot: instanceFixture(extra: same)), "A repeated named instance shares its file")
    }
    func testSharedEquivalenceIndexAgreesWithEveryPinnedCatalogInstance() throws {
        let catalog = try GoogleFontCatalog.load()
        let index = try XCTUnwrap(FontCatalogEquivalenceIndex.decode(JSONEncoder().encode(catalog.snapshot)))
        // Missing app-only resource must fail, never skip or fall back to the full catalog.
        let compactURL = try XCTUnwrap(Bundle.main.url(forResource: "equivalences", withExtension: "json", subdirectory: "GoogleFonts"))
        let compactData = try Data(contentsOf: compactURL)
        XCTAssertLessThanOrEqual(compactData.count, 2 * 1024 * 1024)
        let compact = try XCTUnwrap(FontCatalogEquivalenceIndex.decode(compactData))
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: compactData) as? [String: Any])
        let files = try XCTUnwrap(metadata["files"] as? [[String: Any]])
        let families = try XCTUnwrap(metadata["families"] as? [[String: Any]])
        XCTAssertEqual(files.count, 730)
        XCTAssertEqual(families.count, 552)
        let styles = try families.flatMap { try XCTUnwrap($0["styles"] as? [[String: Any]]) }
        XCTAssertEqual(styles.count, 5439)
        // Provenance is a generation/test consistency check, not runtime digest trust.
        let fullURL = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "GoogleFonts"))
        let fullData = try Data(contentsOf: fullURL)
        let digest = SHA256.hash(data: fullData).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(metadata["catalogSHA256"] as? String, digest)
        for family in catalog.snapshot.families {
            for style in family.styles {
                guard let instance = style.instance else { continue }
                let file = try XCTUnwrap(catalog.file(id: style.fileID))
                let shared = FontLocator.file(relativePath: "", sha256: file.sha256, faceIndex: 0,
                                              variations: try XCTUnwrap(style.variationInstance))
                let own = FontLocator.file(relativePath: "", sha256: instance.sha256, faceIndex: 0, variations: [:])
                XCTAssertTrue(index.equivalents(for: shared).contains(own), style.id)
                XCTAssertTrue(index.equivalents(for: own).contains(shared), style.id)
                for locator in [shared, own] {
                    let expected = Set(index.equivalents(for: locator))
                    XCTAssertEqual(Set(compact.equivalents(for: locator)), expected, style.id)
                    XCTAssertEqual(Set(FontCatalogEquivalenceIndex.bundled.equivalents(for: locator)), expected, style.id)
                }
            }
        }
    }

    func testCompleteBundledCatalogLoadsOffline() throws {
        let catalog = try GoogleFontCatalog.load()
        XCTAssertEqual(catalog.snapshot.schemaVersion, 2)
        let instances = catalog.snapshot.families.flatMap(\.styles).compactMap(\.instance)
        XCTAssertEqual(instances.count, 5439)
        XCTAssertEqual(Set(instances.map(\.path)).count, 5437)
        XCTAssertTrue(instances.allSatisfy { (try? catalog.downloadURL(for: $0))?.host == "fonts.gstatic.com" })
        XCTAssertEqual(catalog.snapshot.families.count, 2065)
        XCTAssertFalse(catalog.search("Noto Sans").isEmpty)
        XCTAssertFalse(catalog.search("Roboto").isEmpty)
    }
}
#endif
