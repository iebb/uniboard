#if canImport(UIKit)
import XCTest
import CryptoKit
@testable import Uniboard

private struct ExplorationTestEngine: FontComparing {
    let values: [FontScanUpdate]
    var fails = false
    func inventorySnapshot() async throws -> FontLibrarySnapshot {
        .init(generation: "test", faces: values.last?.verified ?? [], customEntryCount: 0)
    }
    func invalidate() async {}
    func scan(_ inspection: FontInspection) async -> AsyncThrowingStream<FontScanUpdate, Error> {
        AsyncThrowingStream { continuation in
            values.forEach { continuation.yield($0) }
            if fails { continuation.finish(throwing: FontLibraryFailure.registration) }
            else { continuation.finish() }
        }
    }
}

@MainActor
final class FontExplorationViewModelTests: XCTestCase {
    private let inspection = FontInspection(originalText: "A", characterName: "LATIN CAPITAL LETTER A")
    private func face(_ name: String = "Example") -> FontFaceRecord {
        .init(id: .init(rawValue: name), family: name, style: "Regular", postScriptName: name,
              source: .system, locator: .process(postScriptName: name, variations: [:]), assetID: nil)
    }
    func testPartialCountsNeverLookFinal() async {
        let model = FontExplorationViewModel(engine: ExplorationTestEngine(values: [
            .init(generation: 1, checked: 4, total: 100, verified: [face()], unknownCount: 2, isComplete: false)
        ]))
        await model.scan(inspection)
        XCTAssertEqual(model.countLabel, "4 of 100 checked")
        XCTAssertEqual(model.faces.count, 1)
        XCTAssertFalse(model.failed)
    }
    func testFinalCountsAreFacesNotFilteredSearchResults() async {
        let model = FontExplorationViewModel(engine: ExplorationTestEngine(values: [
            .init(generation: 1, checked: 80, total: 80, verified: [face("Alpha"), face("Beta")], unknownCount: 3, isComplete: true)
        ]))
        await model.scan(inspection)
        model.query = "alpha"
        XCTAssertEqual(model.faces.map(\.family), ["Alpha"])
        XCTAssertEqual(model.countLabel, "2 fonts available")
        model.query = "regular"
        XCTAssertEqual(model.faces.count, 2)
        model.query = "absent"
        XCTAssertTrue(model.faces.isEmpty)
        XCTAssertEqual(model.update?.unknownCount, 3)
    }
    func testScanErrorRetainsVerifiedPartialResults() async {
        let model = FontExplorationViewModel(engine: ExplorationTestEngine(values: [
            .init(generation: 1, checked: 1, total: 90, verified: [face()], unknownCount: 0, isComplete: false)
        ], fails: true))
        await model.scan(inspection)
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.checking)
        XCTAssertEqual(model.faces.count, 1)
        XCTAssertEqual(model.countLabel, "1 of 90 checked")
    }
    func testSingularAndEmptyFinalCounts() async {
        for count in [0, 1] {
            let model = FontExplorationViewModel(engine: ExplorationTestEngine(values: [
                .init(generation: 1, checked: 50, total: 50, verified: count == 1 ? [face()] : [], unknownCount: 0, isComplete: true)
            ]))
            await model.scan(inspection)
            XCTAssertEqual(model.countLabel, count == 1 ? "1 font available" : "0 fonts available")
        }
    }
    func testDefaultSelectionUsesStyleIdentityAndSharedFile() {
        let bold = GoogleFontStyle(id: "bold", name: "Bold", fileID: "variable", postScriptName: "Example")
        let regular = GoogleFontStyle(id: "regular", name: "Regular", fileID: "variable", postScriptName: "Example")
        let family = GoogleFontFamily(id: "example", name: "Example", styles: [bold, regular])
        XCTAssertEqual(FontDetailSelection.defaultStyleID(in: family), regular.id)
        XCTAssertEqual(family.styles.map(\.fileID), ["variable", "variable"])
    }
    func testLimitsAndInvalidFileHaveActionableDistinctCopy() {
        XCTAssertTrue(FontDownloadCopy.message(for: .tooMany(limit: 16)).contains("Remove"))
        XCTAssertTrue(FontDownloadCopy.message(for: .tooLarge(limitBytes: 40 * 1024 * 1024)).contains("40 MiB"))
        XCTAssertNotEqual(FontDownloadCopy.message(for: .invalidFile), FontDownloadCopy.message(for: .transport))
    }
    func testPresentationPreservesExactOriginalSequence() {
        let original = "e\u{301}\u{FE0F}"
        let value = FontInspection(originalText: original, characterName: "Sequence", presentation: .text)
        XCTAssertEqual(Array(value.originalText.utf8), Array(original.utf8))
        XCTAssertEqual(Array(value.previewText.utf8), Array(original.utf8))
        XCTAssertFalse(FontInspection(originalText: "\u{200D}", characterName: "JOINER").isApplicable)
    }
    func testExplicitEmojiPresentationKeepsOriginalBytes() {
        let original = "\u{2764}\u{FE0F}"
        let value = FontInspection(originalText: original, characterName: "HEART", presentation: .text)
        XCTAssertTrue(value.canChoosePresentation)
        XCTAssertEqual(Array(value.originalText.utf8), Array(original.utf8))
        XCTAssertEqual(Array(value.previewText.utf8), Array("\u{2764}\u{FE0E}".utf8))
        XCTAssertFalse(FontInspection(originalText: "👩‍💻", characterName: "TECHNOLOGIST").canChoosePresentation)
    }
    func testPhysicalAliasesMatchNormalizedAxesAndSelectDeterministically() throws {
        let hash = String(repeating: "a", count: 64)
        let file = GoogleFontFile(id: "file", repositoryPath: "ofl/example/Example.ttf", bytes: 100,
                                  sha256: hash, expectedPostScriptNames: ["Example"], licenseIDs: ["license"])
        let a = GoogleFontStyle(id: "a", name: "Regular", fileID: file.id, postScriptName: "Example", variationInstance: ["wght": 400])
        let b = GoogleFontStyle(id: "b", name: "Alias", fileID: file.id, postScriptName: "Example", variationInstance: ["wght": 400])
        let family = GoogleFontFamily(id: "family", name: "Example", styles: [b, a])
        let text = "License notice"
        let licenseHash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let license = GoogleFontLicense(id: "license", name: "License", repositoryPath: "ofl/example/OFL.txt", sha256: licenseHash, text: text)
        let catalog = try GoogleFontCatalog(snapshot: .init(schemaVersion: 1, repositoryCommit: GoogleFontCatalog.trustedRepositoryCommit,
            snapshotDate: "2026-10-23", families: [family], files: [file], licenses: [license]))
        let locator = FontLocator.file(relativePath: "saved.ttf", sha256: hash, faceIndex: 0, variations: ["2003265652": 400])
        let physical = FontFaceRecord(id: PublicFontInventory.identity(locator), family: "Other alias", style: "Other",
                                     postScriptName: "Example", source: .downloaded, locator: locator, assetID: "saved.ttf")
        XCTAssertTrue(FontDetailIdentity.matches(physical, file: file, style: a))
        XCTAssertTrue(FontDetailIdentity.matches(physical, file: file, style: b))
        let receipt = FontLibraryReceipt(fileID: file.id, repositoryCommit: catalog.snapshot.repositoryCommit,
            repositoryPath: file.repositoryPath, snapshotDate: catalog.snapshot.snapshotDate, sha256: hash, licenses: [])
        let state = FontLibraryReadState(snapshot: .init(generation: "test", faces: [physical], customEntryCount: 1),
                                         receipts: [file.id: receipt], assetIDs: [file.id: "saved.ttf"])
        XCTAssertEqual(FontDetailIdentity.selection(for: physical, catalog: catalog, state: state)?.style.id, "a")
        let persisted = FontFaceRecord(id: .init(rawValue: "google:file:b"), family: physical.family, style: physical.style,
                                      postScriptName: physical.postScriptName, source: .downloaded, locator: locator, assetID: "saved.ttf")
        XCTAssertEqual(FontDetailIdentity.selection(for: persisted, catalog: catalog, state: state)?.style.id, "b")
        let bold = GoogleFontStyle(id: "bold", name: "Bold", fileID: file.id, postScriptName: "Example", variationInstance: ["wght": 700])
        XCTAssertFalse(FontDetailIdentity.matches(physical, file: file, style: bold))
        let noReceipts = FontLibraryReadState(snapshot: state.snapshot, receipts: [:], assetIDs: [:])
        XCTAssertNil(FontDetailIdentity.selection(for: physical, catalog: catalog, state: noReceipts))
    }
    func testLiveCatalogViewModelLoadsOnlyMetadata() async {
        let model = GoogleFontsViewModel()
        await model.load()
        XCTAssertNotNil(model.catalog)
        XCTAssertNotNil(model.coordinator)
        model.query = "Roboto"
        XCTAssertTrue(model.families.contains { $0.name == "Roboto" })
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.failed)
    }
}
#endif
