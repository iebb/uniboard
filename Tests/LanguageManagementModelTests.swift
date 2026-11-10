#if canImport(Uniboard)
import XCTest
import Combine
import CryptoKit
@testable import Uniboard

final class LanguageManagementModelTests: XCTestCase {
    private var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    @MainActor
    func testActualModelDeliveryRejectsReorderedCancelledCompletedAndPreviousGenerationEvents() {
        let model = LanguageManagementModel(root: nil)
        let first = model.beginDownloadOperation(.mandarinPinyin)
        model.acceptProgress(.verifying, token: first, mode: .mandarinPinyin, sequence: 2)
        model.acceptProgress(.downloading(0.1), token: first, mode: .mandarinPinyin, sequence: 1)
        XCTAssertEqual(model.operation, .verifying)
        XCTAssertEqual(model.operatingMode, .mandarinPinyin)
        model.cancelDownload()
        XCTAssertTrue(model.isCancelling)
        model.acceptProgress(.compiling(.indexing), token: first, mode: .mandarinPinyin, sequence: 3)
        XCTAssertEqual(model.operation, .verifying)
        XCTAssertNil(model.cancelledMode, "A cancellation request is not confirmed terminal cancellation")
        model.finishDownloadOperation(first)
        model.acceptProgress(.activating, token: first, mode: .mandarinPinyin, sequence: 4)
        XCTAssertEqual(model.operation, .idle)
        XCTAssertNil(model.operatingMode)
        let next = model.beginDownloadOperation(.mandarinPinyin)
        model.acceptProgress(.downloading(0.2), token: next, mode: .mandarinPinyin, sequence: 1)
        model.acceptProgress(.verifying, token: first, mode: .mandarinPinyin, sequence: 100)
        model.finishDownloadOperation(first)
        XCTAssertEqual(model.operation, .downloading(0.2))
        model.acceptProgress(.verifying, token: next, mode: .japaneseRomaji, sequence: 2)
        XCTAssertEqual(model.operation, .downloading(0.2))
        model.finishDownloadOperation(next)
    }

    @MainActor
    func testCompilerUpdatesCoalesceAndPreserveLastEventWithoutRevivingCancelledOperation() async throws {
        let model = LanguageManagementModel(root: nil)
        let token = model.beginDownloadOperation(.mandarinPinyin)
        var updates: [LanguageManagementModel.Operation] = []
        let observer = model.$operation.dropFirst().sink { updates.append($0) }
        defer { observer.cancel() }
        model.acceptProgress(.compiling(.rows(processed: 1, total: 100)), token: token, mode: .mandarinPinyin, sequence: 1)
        for value in 2...100 {
            model.acceptProgress(.compiling(.rows(processed: value, total: 100)), token: token, mode: .mandarinPinyin, sequence: value)
        }
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(model.lastCompilationProgress, .rows(processed: 100, total: 100))
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(model.operation, .compiling(.rows(processed: 100, total: 100)))
        model.acceptProgress(.compiling(.indexing), token: token, mode: .mandarinPinyin, sequence: 101)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.operation, .compiling(.indexing), "Completed row count must become real indeterminate indexing")
        XCTAssertEqual(model.operatingMode, .mandarinPinyin)
        model.acceptProgress(.compiling(.finalCheck), token: token, mode: .mandarinPinyin, sequence: 102)
        model.cancelDownload()
        model.finishDownloadOperation(token)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.operation, .idle)
    }

    func testStorageAssessmentIsOffMainUsesMeasuredValuesAndBlocksUnknown() async throws {
        let catalog = try LanguagePackCatalog.load(bundle: bundle)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for available in [nil, 0, Int64.max] as [Int64?] {
            let worker = LanguageManagementWorker(root: root, settings: .init(directory: { nil }), capacity: { _ in
                XCTAssertFalse(Thread.isMainThread)
                return available
            })
            let state = await worker.assessStorage(mode: .koreanTwoSetHangul, catalog: catalog, databaseBytes: nil)
            let expected = try LanguagePackSpacePlan(sourceBytes: [2324], installedBytes: 5960).requiredBytes
            XCTAssertEqual(state.requiredBytes, expected)
            XCTAssertEqual(state.availableBytes, available)
            XCTAssertEqual(state.permitsDownload, available == Int64.max)
        }
        let worker = LanguageManagementWorker(root: root, settings: .init(directory: { nil }))
        let unknown = await worker.assessStorage(mode: .mandarinPinyin, catalog: catalog, databaseBytes: nil)
        XCTAssertEqual(unknown, .requirementUnknown)
    }

    func testRealBundledKoreanMetadataHasRequiredMappingAndExplicitABI() throws {
        let catalog = try LanguagePackCatalog.load(bundle: bundle)
        let korean = try XCTUnwrap(catalog.koreanTwoSet)
        XCTAssertEqual(korean.packID, "korean-hangul-2set")
        XCTAssertEqual(korean.archiveByteCount, 2324)
        XCTAssertEqual(korean.installedBytes, 5960)
        XCTAssertEqual(korean.archiveSHA256, "a895f37d5e2f329f505587aa8bd44af5cf7b36d774c092f31faa93f6136f3952")
        XCTAssertEqual(korean.sourceURL.absoluteString, "https://uniboard.ieb.app/data/korean/hangul-2set/1/hangul-2set.tar.gz")
        XCTAssertEqual(LanguagePackCatalog.engineABI(for: .koreanTwoSetHangul), "uniboard-hangul-1")
        XCTAssertNil(LanguagePackCatalog.engineABI(for: .koreanRomaja))
        XCTAssertNil(LanguagePackCatalog.engineABI(for: .direct))
        XCTAssertEqual(Set(korean.files.map(\.path)), Set(["mapping.json", "SOURCE.txt", "LICENSE.txt"]))
        XCTAssertNil(bundle.url(forResource: "mapping", withExtension: "json"), "Actual mapping must never be bundled")
    }

    @MainActor
    func testAbsentSiblingModesRemainDownloadRequiredAfterKoreanInstallAndDamageStillErrors() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LanguagePackStore(root: root.appendingPathComponent("packs"))
        let worker = LanguageManagementWorker(root: store.root, settings: .init(directory: { nil }))
        let before = await worker.snapshot()
        for mode in [LanguageInputMode.japaneseRomaji, .mandarinPinyin, .koreanTwoSetHangul] {
            XCTAssertNil(before.problems[mode], "An absent store is not a damaged download")
        }
        let entries = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".map {
            ["key": String($0), "jamo": KoreanTwoSetKeyboard.label(for: String($0))!]
        }
        let mapping = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": entries])
        let notice = Data("Generated offline test fixture".utf8)
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let descriptor = LanguagePackDescriptor(packID: "korean-hangul-2set", version: "1",
            modeID: LanguageInputMode.koreanTwoSetHangul.rawValue, engineABI: "uniboard-hangul-1",
            sourceURL: URL(string: "https://fixture.invalid/fixture.tar.gz")!, allowedHosts: ["fixture.invalid"],
            archiveByteCount: 1, archiveSHA256: hash(Data([0])), installedBytes: Int64(mapping.count + notice.count * 2), fileCount: 3,
            files: [.init(path: "mapping.json", byteCount: Int64(mapping.count), sha256: hash(mapping)),
                    .init(path: "LICENSE.txt", byteCount: Int64(notice.count), sha256: hash(notice)),
                    .init(path: "SOURCE.txt", byteCount: Int64(notice.count), sha256: hash(notice))],
            licenseNotice: "Generated fixture", sourceNotice: "Generated fixture; not downloadable")
        let korean = try store.install(manifestData: JSONEncoder().encode(descriptor), expectedRevision: nil) { stage in
            try mapping.write(to: stage.appendingPathComponent("mapping.json"))
            try notice.write(to: stage.appendingPathComponent("LICENSE.txt"))
            try notice.write(to: stage.appendingPathComponent("SOURCE.txt"))
        }
        let model = LanguageManagementModel(root: store.root, settings: .init(directory: { nil }))
        func refreshModel() async {
            let refreshed = expectation(description: "Language snapshot finished")
            let observer = model.$isChecking.dropFirst().filter { !$0 }.first().sink { _ in refreshed.fulfill() }
            model.refresh()
            await fulfillment(of: [refreshed], timeout: 5)
            observer.cancel()
        }
        await refreshModel()
        XCTAssertTrue(model.isReady(.koreanTwoSetHangul))
        XCTAssertNil(model.resourceProblems[.koreanTwoSetHangul])
        for mode in [LanguageInputMode.japaneseRomaji, .mandarinPinyin] {
            guard case .missing = store.resolve(modeID: mode.rawValue, engineABI: mode.conversionEngineABI!) else {
                return XCTFail("Initialized store must report an absent sibling pointer as missing")
            }
            XCTAssertEqual(model.status(mode), "Language download required")
            XCTAssertNil(model.resourceProblems[mode])
            XCTAssertNil(model.installed[mode])
            XCTAssertNil(model.removable[mode])
            XCTAssertFalse(model.canRemove(mode))
        }
        // A valid active pointer whose payload has gone missing is NOT the
        // same state as a mode that has never had an active publication.
        try FileManager.default.removeItem(at: korean.path.appendingPathComponent("mapping.json"))
        await refreshModel()
        XCTAssertFalse(model.isReady(.koreanTwoSetHangul))
        XCTAssertEqual(model.resourceProblems[.koreanTwoSetHangul], "Download couldn’t be verified")
        XCTAssertEqual(model.status(.koreanTwoSetHangul), "Download couldn’t be verified")
        XCTAssertEqual(model.removable[.koreanTwoSetHangul]?.revision, korean.revision)
        XCTAssertTrue(model.canRemove(.koreanTwoSetHangul), "Known damaged active publication remains safely removable")
        for mode in [LanguageInputMode.japaneseRomaji, .mandarinPinyin] {
            XCTAssertEqual(model.status(mode), "Language download required")
            XCTAssertNil(model.resourceProblems[mode])
            XCTAssertFalse(model.canRemove(mode))
        }
    }

    @MainActor
    func testDamagedPublicationRemovalUsesCapturedTokenAndRejectsReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LanguagePackStore(root: root.appendingPathComponent("packs"))
        let mapping = Data("invalid fixture mapping".utf8)
        let notice = Data("test fixture".utf8)
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let descriptor = LanguagePackDescriptor(packID: "korean-hangul-2set", version: "1",
            modeID: LanguageInputMode.koreanTwoSetHangul.rawValue, engineABI: "uniboard-hangul-1",
            sourceURL: URL(string: "https://fixture.invalid/fixture.tar.gz")!, allowedHosts: ["fixture.invalid"],
            archiveByteCount: 1, archiveSHA256: hash(Data([0])), installedBytes: Int64(mapping.count + notice.count * 2), fileCount: 3,
            files: [.init(path: "mapping.json", byteCount: Int64(mapping.count), sha256: hash(mapping)),
                    .init(path: "LICENSE.txt", byteCount: Int64(notice.count), sha256: hash(notice)),
                    .init(path: "SOURCE.txt", byteCount: Int64(notice.count), sha256: hash(notice))],
            licenseNotice: "Generated fixture", sourceNotice: "Generated fixture; not downloadable")
        func install(expected: String?) throws -> ValidatedInstalledLanguagePack {
            try store.install(manifestData: JSONEncoder().encode(descriptor), expectedRevision: expected) { stage in
                try mapping.write(to: stage.appendingPathComponent("mapping.json"))
                try notice.write(to: stage.appendingPathComponent("LICENSE.txt"))
                try notice.write(to: stage.appendingPathComponent("SOURCE.txt"))
            }
        }
        let first = try install(expected: nil)
        let model = LanguageManagementModel(root: store.root, settings: .init(directory: { root }))
        let refreshed = expectation(description: "Snapshot finished")
        let refreshObserver = model.$isChecking.dropFirst().filter { !$0 }.first().sink { _ in refreshed.fulfill() }
        model.refresh()
        await fulfillment(of: [refreshed], timeout: 5)
        refreshObserver.cancel()
        XCTAssertNil(model.installed[.koreanTwoSetHangul], "Matching ABI and file hashes are not sufficient; mapping content must validate")
        XCTAssertEqual(model.resourceProblems[.koreanTwoSetHangul], "Download couldn’t be verified")
        XCTAssertTrue(model.canRemove(.koreanTwoSetHangul))
        let captured = try XCTUnwrap(model.removalRequest(for: .koreanTwoSetHangul))
        XCTAssertEqual(captured.revision, first.revision)
        let replacement = try install(expected: first.revision)
        let finished = expectation(description: "Removal reconciled")
        let removeObserver = model.$operation.dropFirst().filter { $0 == .idle }.first().sink { _ in finished.fulfill() }
        model.remove(captured)
        await fulfillment(of: [finished], timeout: 5)
        removeObserver.cancel()
        XCTAssertEqual(try store.activeRevision(modeID: descriptor.modeID), replacement.revision)
        XCTAssertEqual(model.removable[.koreanTwoSetHangul]?.revision, replacement.revision)
        XCTAssertEqual(model.errorMessage, "This language download changed. Review it in Languages and try again.")
    }

    /// Opt-in source-host smoke check; no user data or language hints involved.
    func testOptInRealKoreanArchiveInstallEnableAndRemove() async throws {
        guard ProcessInfo.processInfo.environment["UNIBOARD_LIVE_PACK_CHECK"] == "1" else {
            throw XCTSkip("Explicit live-pack verification was not requested")
        }
        let descriptor = try XCTUnwrap(LanguagePackCatalog.load(bundle: bundle).koreanTwoSet)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settingsDirectory = root.appendingPathComponent("settings")
        try FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = LanguageInputSettings(directory: { settingsDirectory })
        let worker = LanguageManagementWorker(root: root.appendingPathComponent("packs"), settings: settings)
        let pack = try await worker.downloadArchive(descriptor, archiveRoot: "hangul-2set-1", progress: { _ in })
        XCTAssertEqual(pack.descriptor, descriptor)
        XCTAssertFalse(settings.load().isEnabled(.koreanTwoSetHangul), "Download must not enable")
        let snapshot = await worker.snapshot()
        XCTAssertNotNil(snapshot.installed[.koreanTwoSetHangul])
        let publication = try XCTUnwrap(snapshot.removable[.koreanTwoSetHangul])
        let enabled = try await worker.save(.enabled(.koreanTwoSetHangul, true))
        XCTAssertTrue(enabled.isEnabled(.koreanTwoSetHangul))
        XCTAssertEqual(enabled.packReferences.first?.packID, "korean-hangul-2set")
        _ = try await worker.save(.enabled(.koreanTwoSetHangul, false))
        try await worker.remove(publication)
        let removed = await worker.snapshot()
        XCTAssertNil(removed.installed[.koreanTwoSetHangul])
        XCTAssertNil(removed.removable[.koreanTwoSetHangul])
    }

    func testPayloadValidationRejectsMissingMalformedOversizedAndNonstandardMapping() throws {
        let descriptor = try XCTUnwrap(LanguagePackCatalog.load(bundle: bundle).koreanTwoSet)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try LanguagePackCatalog.validateKoreanPayload(at: root, descriptor: descriptor))
        let url = root.appendingPathComponent("mapping.json")
        for invalid in [Data("{}".utf8), Data(repeating: 32, count: 16_385)] {
            try invalid.write(to: url)
            XCTAssertThrowsError(try LanguagePackCatalog.validateKoreanPayload(at: root, descriptor: descriptor))
        }
        var entries = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".map {
            ["key": String($0), "jamo": KoreanTwoSetKeyboard.label(for: String($0))!]
        }
        let good = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": entries])
        try good.write(to: url)
        XCTAssertNoThrow(try LanguagePackCatalog.validateKoreanPayload(at: root, descriptor: descriptor))
        let composer = KoreanHangulComposer(mapping: try .init(jsonData: good))
        for (keys, expected) in [("rk", "가"), ("Rk", "까"), ("rhk", "과"), ("rkqt", "값"), ("rkqtk", "갑사")] {
            XCTAssertEqual(try composer.compose(keys), expected)
        }
        entries[0]["jamo"] = "ㄱ" // Structurally valid, but not standard A/ㅁ.
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": entries]).write(to: url)
        XCTAssertThrowsError(try LanguagePackCatalog.validateKoreanPayload(at: root, descriptor: descriptor))
    }
}
#endif
