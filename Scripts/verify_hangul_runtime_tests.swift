import Combine
import Foundation
import XCTest
@testable import UniboardCore

/// Standalone native harness copied into a temporary package by
/// verify_hangul_runtime.sh. Actual coordinator/worker/adapter/store/core; only
/// the unrelated Japanese third-party engine is a fail-fast compile-only stub.
@MainActor
final class HangulCoordinatorNativeTests: XCTestCase {
    @MainActor private final class Fixture {
        let directory: URL
        let source: URL
        let settings: LanguageInputSettings
        let store: LanguagePackStore
        let words: URL
        let coordinator: KeyboardLanguageCoordinator
        var installed: ValidatedInstalledLanguagePack?

        init(install: Bool = true) throws {
            source = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["HANGUL_FIXTURE_PATH"]))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("hangul-coordinator-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let preferences = directory.appendingPathComponent("preferences")
            try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: false)
            settings = LanguageInputSettings(directory: { preferences })
            guard settings.save(.init(enabledModes: [.direct, .koreanTwoSetHangul])) else {
                throw NSError(domain: "HangulFixturePreferences", code: 1)
            }
            store = LanguagePackStore(root: directory.appendingPathComponent("packs"))
            words = directory.appendingPathComponent("MyWords")
            // Closures capture a separate counter so initialization needn't
            // capture self before all let properties are initialized.
            let spy = Spy()
            let packRoot = store.root
            coordinator = KeyboardLanguageCoordinator(root: { packRoot }, settings: settings, indexDirectory: {
                spy.indexCalls += 1
                return spy.words
            })
            spy.words = words
            self.spy = spy
            coordinator.validateAnchor = { spy.anchorCalls += 1; return spy.anchorValid }
            if install { installed = try publish(expected: nil) }
        }
        final class Spy {
            var indexCalls = 0
            var anchorCalls = 0
            var anchorValid = true
            var words: URL?
        }
        let spy: Spy
        func publish(expected: String?) throws -> ValidatedInstalledLanguagePack {
            let data = try Data(contentsOf: source.appendingPathComponent("descriptor.json"))
            let descriptor = try LanguagePackDescriptor.validated(from: data)
            let archive = source.appendingPathComponent("hangul-2set.tar.gz")
            try LanguagePackStore.verifyArchive(at: archive, descriptor: descriptor)
            return try store.install(manifestData: data, expectedRevision: expected) { stage in
                try LanguagePackArchive.extract(archive: archive, descriptor: descriptor, into: stage,
                    archiveRoot: "hangul-2set-1", limits: .init(decodedBytes: 16_384, entryCount: 3, individualFileBytes: 16_384))
            }
        }
        func close() {
            coordinator.cancel()
            _ = coordinator.select(.direct)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for actual coordinator worker", file: file, line: line)
        throw NSError(domain: "HangulNativeTimeout", code: 1)
    }
    private func activate(_ f: Fixture) async throws {
        await f.coordinator.refreshResources()
        XCTAssertTrue(f.coordinator.choices.contains(.koreanTwoSetHangul))
        XCTAssertTrue(f.coordinator.select(.koreanTwoSetHangul))
        try await eventually { !f.coordinator.isLoading }
        XCTAssertEqual(f.coordinator.status, .ready)
        XCTAssertEqual(f.coordinator.token.packRevision, f.installed?.revision)
    }
    private func ready(_ f: Fixture, raw: String = "gksrnr") async throws -> LanguageCompositionToken {
        XCTAssertTrue(f.coordinator.append(raw))
        try await eventually { !f.coordinator.isConverting }
        XCTAssertEqual(f.coordinator.status, .ready)
        XCTAssertEqual(f.coordinator.candidates.count, 1)
        XCTAssertEqual(f.coordinator.candidates.first?.source, .engine)
        return f.coordinator.token
    }

    func testMissingDownloadedPackNeverActivatesOrOpensIndex() async throws {
        let f = try Fixture(install: false); defer { f.close() }
        await f.coordinator.refreshResources()
        XCTAssertEqual(f.coordinator.choices, [.direct])
        XCTAssertFalse(f.coordinator.select(.koreanTwoSetHangul))
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testActualCoordinatorZeroIndexCallsAcrossActivationRefreshConversionAndRevisionReplacement() async throws {
        let f = try Fixture(); defer { f.close() }
        let first = CustomInputDictionarySnapshot(revision: UUID(), collections: [
            .init(name: "Isolation probe", modeID: "koreanTwoSetHangul", entries: [
                .init(reading: "gksrnr", output: "MUST-NOT-MERGE")
            ])
        ])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: first, directory: f.words)
        try await activate(f)
        let token = try await ready(f)
        XCTAssertEqual(f.coordinator.preedit, "한국")
        XCTAssertEqual(token.dictionaryRevision, 0)
        let second = CustomInputDictionarySnapshot(revision: UUID(), collections: [])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: second, directory: f.words,
                                                       expectedPublishedRevision: first.revision)
        XCTAssertNotEqual(try CustomInputDictionaryIndex(directory: f.words).revision, first.revision)
        await f.coordinator.refreshResources()
        XCTAssertEqual(f.coordinator.token, token, "Korean must ignore genuine My Words publication changes")
        XCTAssertNil(f.coordinator.englishCustomOutputs(for: "hello"))
        XCTAssertTrue(f.coordinator.protectsEnglishCustomReading("hello"))
        XCTAssertEqual(f.coordinator.commitDefault(token: token, space: true), [.commit(text: "한국 ", remainingInput: "")])
        XCTAssertEqual(f.coordinator.commitDefault(token: token, space: true), [])
        XCTAssertGreaterThan(f.spy.anchorCalls, 0)
        XCTAssertEqual(f.spy.indexCalls, 0, "No directory resolution means no worker/index read is possible")
    }

    func testActualPendingReadyTapReturnReplayAndEditGuards() async throws {
        let f = try Fixture(); defer { f.close() }
        try await activate(f)
        XCTAssertTrue(f.coordinator.append("rk"))
        let pending = f.coordinator.token
        XCTAssertTrue(f.coordinator.isConverting)
        XCTAssertEqual(f.coordinator.commitDefault(token: pending, space: true), [])
        XCTAssertEqual(f.coordinator.commitLiteral(token: pending), [])
        try await eventually { !f.coordinator.isConverting }
        XCTAssertEqual(f.coordinator.commitDefault(token: f.coordinator.token), [.commit(text: "가", remainingInput: "")])
        XCTAssertEqual(f.coordinator.commitDefault(token: pending), [])
        let tapped = try await ready(f, raw: "Rk")
        let id = try XCTUnwrap(f.coordinator.candidates.first?.id)
        XCTAssertEqual(f.coordinator.choose(id: id, token: tapped), [.commit(text: "까", remainingInput: "")])
        XCTAssertEqual(f.coordinator.choose(id: id, token: tapped), [])
        let old = try await ready(f, raw: "rk")
        XCTAssertTrue(f.coordinator.append("s"))
        XCTAssertEqual(f.coordinator.commitDefault(token: old, space: true), [])
        try await eventually { !f.coordinator.isConverting }
        XCTAssertEqual(f.coordinator.preedit, "간")
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testAnchorRevocationRejectsPendingResultAndReadyCommitAndDocumentToken() async throws {
        let f = try Fixture(); defer { f.close() }
        try await activate(f)
        XCTAssertTrue(f.coordinator.append("rk"))
        let pending = f.coordinator.token
        f.spy.anchorValid = false
        try await eventually { !f.coordinator.isConverting }
        XCTAssertFalse(f.coordinator.hasComposition)
        XCTAssertEqual(f.coordinator.commitDefault(token: pending, space: true), [])
        f.spy.anchorValid = true
        let ready = try await ready(f)
        f.spy.anchorValid = false
        XCTAssertEqual(f.coordinator.commitDefault(token: ready, space: true), [])
        XCTAssertFalse(f.coordinator.hasComposition)
        f.spy.anchorValid = true
        let beforeFocus = try await self.ready(f)
        f.coordinator.documentChanged()
        XCTAssertNotEqual(f.coordinator.token.documentID, beforeFocus.documentID)
        XCTAssertEqual(f.coordinator.commitDefault(token: beforeFocus), [])
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testCoordinatorRetainsRealLeaseUntilRemovedPublicationRevokesCommit() async throws {
        let f = try Fixture(); defer { f.close() }
        try await activate(f)
        let token = try await ready(f)
        let installed = try XCTUnwrap(f.installed)
        // No test-owned lease exists: surviving inactive payload proves the
        // actual coordinator's adapter owns a real cross-process store lease.
        try f.store.remove(modeID: "koreanTwoSetHangul", expectedRevision: installed.revision)
        XCTAssertNil(try f.store.activeRevision(modeID: "koreanTwoSetHangul"))
        try f.store.reclaimUnusedVersions()
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path.path))
        XCTAssertEqual(f.coordinator.commitDefault(token: token, space: true), [])
        XCTAssertEqual(f.coordinator.status, .missingResources)
        XCTAssertEqual(f.coordinator.rawInput, "gksrnr")
        XCTAssertEqual(f.coordinator.commitLiteral(token: f.coordinator.token), [])
        // Revocation releases the owner's lease; the real reclaimer now deletes
        // the inactive revision (an already-finished Task may retain it briefly).
        try await eventually { !FileManager.default.fileExists(atPath: installed.path.path) }
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testPackReplacementAndPreferenceDisableRevokeOldCommit() async throws {
        let f = try Fixture(); defer { f.close() }
        try await activate(f)
        let old = try await ready(f)
        let replacement = try f.publish(expected: f.installed?.revision)
        XCTAssertNotEqual(replacement.revision, old.packRevision)
        XCTAssertEqual(f.coordinator.commitDefault(token: old, space: true), [])
        XCTAssertEqual(f.coordinator.rawInput, "gksrnr")
        f.coordinator.cancel()
        f.installed = replacement
        await f.coordinator.refreshResources()
        try await eventually { !f.coordinator.isLoading }
        let current = try await ready(f)
        XCTAssertTrue(f.settings.save(.defaults))
        XCTAssertEqual(f.coordinator.commitDefault(token: current, space: true), [])
        XCTAssertEqual(f.coordinator.rawInput, "gksrnr")
        f.coordinator.cancel()
        XCTAssertEqual(f.coordinator.mode, .direct)
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testUnchangedRefreshAndRevalidationPublishNothing() async throws {
        let f = try Fixture(); defer { f.close() }
        try await activate(f)
        var publications = 0
        let subscription = f.coordinator.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        // Refresh re-derives preferences, choices and reasons and revalidates
        // the active pack; with nothing changed it must not re-render anything.
        await f.coordinator.refreshResources()
        await f.coordinator.refreshResources()
        XCTAssertEqual(publications, 0, "An unchanged refresh/revalidation must not publish")
        XCTAssertEqual(f.coordinator.choices, [.direct, .koreanTwoSetHangul])
        XCTAssertEqual(f.coordinator.status, .ready)
        XCTAssertEqual(f.coordinator.mode, .koreanTwoSetHangul)
        // A real change still publishes, exactly as before.
        XCTAssertTrue(f.settings.save(.defaults))
        await f.coordinator.refreshResources()
        XCTAssertGreaterThan(publications, 0)
        XCTAssertEqual(f.coordinator.choices, [.direct])
        XCTAssertEqual(f.coordinator.mode, .direct)
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testInPlaceUnavailableReasonStillPublishes() async throws {
        let f = try Fixture(); defer { f.close() }
        await f.coordinator.refreshResources()
        XCTAssertTrue(f.coordinator.choices.contains(.koreanTwoSetHangul))
        // The publication disappears after the chooser listed it, so the
        // activation fails and records the reason with an in-place subscript.
        let installed = try XCTUnwrap(f.installed)
        try f.store.remove(modeID: "koreanTwoSetHangul", expectedRevision: installed.revision)
        XCTAssertTrue(f.coordinator.select(.koreanTwoSetHangul))
        XCTAssertTrue(f.coordinator.isLoading)
        XCTAssertNil(f.coordinator.unavailableModes[.koreanTwoSetHangul])
        var publications = 0
        let subscription = f.coordinator.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        try await eventually { !f.coordinator.isLoading }
        XCTAssertEqual(f.coordinator.unavailableModes[.koreanTwoSetHangul], .missing)
        XCTAssertEqual(f.coordinator.status, .missingResources)
        // isLoading true -> false, then unavailableModes[selected] = .missing.
        // resourceStatus was already .missingResources, so it doesn't publish.
        XCTAssertEqual(publications, 2, "The in-place unavailableModes[selected] write must publish")
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testInPlaceRemovalFromChoicesStillPublishes() async throws {
        let f = try Fixture(); defer { f.close() }
        try await activate(f)
        XCTAssertEqual(f.coordinator.choices, [.direct, .koreanTwoSetHangul])
        let installed = try XCTUnwrap(f.installed)
        try f.store.remove(modeID: "koreanTwoSetHangul", expectedRevision: installed.revision)
        var publications = 0
        let subscription = f.coordinator.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        // The next key revalidates, finds the publication gone and revokes the
        // active resource, which drops the mode with enabledModes.removeAll {}.
        XCTAssertTrue(f.coordinator.append("r"), "A broken converter still consumes the key")
        XCTAssertFalse(f.coordinator.hasComposition)
        XCTAssertEqual(f.coordinator.choices, [.direct])
        XCTAssertEqual(f.coordinator.status, .missingResources)
        // state.changeResources, resourceStatus .ready -> .missingResources, and
        // the in-place enabledModes.removeAll {}: one publication each.
        XCTAssertEqual(publications, 3, "The in-place enabledModes.removeAll {} must publish")
        XCTAssertEqual(f.spy.indexCalls, 0)
    }

    func testActualAdapterRejectsStaleRevisionAndNonstandardMapping() async throws {
        let f = try Fixture(); defer { f.close() }
        guard case .available(let lease) = f.store.resolve(modeID: "koreanTwoSetHangul", engineABI: "uniboard-hangul-1") else {
            return XCTFail("verified fixture lease missing")
        }
        let bytes = try Data(contentsOf: lease.pack.path.appendingPathComponent("mapping.json"))
        let mapping = try KoreanHangulLanguageConverter.prepare(mappingJSON: bytes)
        let adapter = try KoreanHangulLanguageConverter(mapping: mapping, lease: lease)
        let stale = LanguageCompositionToken(documentID: UUID(), mode: .koreanTwoSetHangul,
            revision: 1, packRevision: "old-revision", dictionaryRevision: 0)
        let result = try await adapter.convert(.init(token: stale, rawInput: "rk"))
        XCTAssertEqual(result.status, .missingResources)
        XCTAssertTrue(result.candidates.isEmpty)
        let bad = try XCTUnwrap(String(data: bytes, encoding: .utf8)).replacingOccurrences(of: "ㅁ", with: "ㄱ")
        XCTAssertThrowsError(try KoreanHangulLanguageConverter.prepare(mappingJSON: Data(bad.utf8)))
        XCTAssertThrowsError(try KoreanHangulLanguageConverter.prepare(mappingJSON: Data(repeating: 32, count: 16_385)))
        XCTAssertEqual(f.spy.indexCalls, 0)
    }
}
