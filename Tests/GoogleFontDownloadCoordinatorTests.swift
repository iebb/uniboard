#if canImport(UIKit)
import XCTest
@testable import Uniboard

private struct RejectingFontTransport: GoogleFontTransport {
    let delay: UInt64
    let error: FontLibraryFailure?
    func fetch(url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data {
        try await Task.sleep(nanoseconds: delay)
        if let error { throw error }
        progress(4, 4)
        return Data([0, 1, 0, 0])
    }
}

private actor CountingFontTransport: GoogleFontTransport {
    private(set) var calls = 0
    func fetch(url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data {
        calls += 1
        throw FontLibraryFailure.transport
    }
}

@MainActor
final class GoogleFontDownloadCoordinatorTests: XCTestCase {
    private func setup(transport: any GoogleFontTransport, commit: String = GoogleFontCatalog.trustedRepositoryCommit) -> (GoogleFontDownloadCoordinator, CustomFontStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = CustomFontStore(directory: directory)
        let data = Data([0, 1, 0, 0])
        let file = GoogleFontFile(id: "file", repositoryPath: "ofl/test/Test.ttf", bytes: 4, sha256: CustomFontStore.digest(data), expectedPostScriptNames: ["Test"], licenseIDs: ["license"])
        let license = GoogleFontLicense(id: "license", name: "Fixture", repositoryPath: "ofl/test/OFL.txt", sha256: CustomFontStore.digest(Data("fixture".utf8)), text: "fixture")
        let family = GoogleFontFamily(id: "family", name: "Test", styles: [
            .init(id: "regular", name: "Regular", fileID: "file", postScriptName: "Test"),
            .init(id: "bold", name: "Bold", fileID: "file", postScriptName: "Test", variationInstance: ["wght": 700])])
        let catalog = GoogleFontCatalogSnapshot(schemaVersion: 1, repositoryCommit: commit, snapshotDate: "2026-10-23", families: [family], files: [file], licenses: [license])
        return (GoogleFontDownloadCoordinator(catalog: catalog, store: store, transport: transport), store)
    }

    func testUntrustedCommitNeverStartsTransport() async {
        let transport = CountingFontTransport()
        let (coordinator, _) = setup(transport: transport, commit: String(repeating: "a", count: 40))
        do { try await coordinator.download(styleID: "regular"); XCTFail("Untrusted pin") } catch { }
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(coordinator.states["file"], .failed(.invalidFile))
    }

    func testInvalidFontDoesNotCommitAndCanRetry() async {
        let (coordinator, store) = setup(transport: RejectingFontTransport(delay: 1, error: nil))
        for _ in 0..<2 {
            do { try await coordinator.download(styleID: "regular"); XCTFail("Header is not a valid font") } catch { }
            XCTAssertEqual(coordinator.states["file"], .failed(.invalidFile))
            XCTAssertTrue(store.fonts.isEmpty)
        }
    }

    func testConfirmedOfflineIsDistinctAndRetainsLibrary() async throws {
        let (coordinator, store) = setup(transport: RejectingFontTransport(delay: 1, error: .offline))
        _ = try store.addInstalled(postScriptName: "Helvetica")
        let generation = store.revision
        do { try await coordinator.download(styleID: "regular"); XCTFail() } catch { }
        XCTAssertEqual(coordinator.states["file"], .failed(.offline))
        XCTAssertEqual(store.revision, generation)
    }

    func testCancellationAndSharedVariableFileState() async throws {
        let (coordinator, store) = setup(transport: RejectingFontTransport(delay: 10_000_000_000, error: nil))
        let first = Task { try await coordinator.download(styleID: "regular") }
        await Task.yield()
        let second = Task { try await coordinator.download(styleID: "bold") }
        await Task.yield()
        try await coordinator.cancel(fileID: "file")
        _ = try? await first.value; _ = try? await second.value
        XCTAssertEqual(coordinator.states["file"], .cancelled)
        XCTAssertTrue(store.fonts.isEmpty)
        try await coordinator.remove(fileID: "file")
        XCTAssertEqual(coordinator.states["file"], .ready)
    }
}
#endif
