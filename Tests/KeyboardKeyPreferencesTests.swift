#if canImport(UIKit)
import Foundation
import Combine
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardKeyPreferencesTests: XCTestCase {
    private typealias Settings = KeyboardKeySettings
    private enum Failure: Error { case unavailable }
    private final class SharedFile {
        var bytes: Data?
        var failReads = false
        var failWrites = false
        var reads = 0
        var attempts = 0
        var successfulWrites = 0
        var beforeWrite: (() -> Void)?

        init(_ value: Settings.Snapshot? = nil) throws {
            if let value { bytes = try JSONEncoder().encode(value) }
        }
        func replaceExternally(_ value: Settings.Snapshot) throws { bytes = try JSONEncoder().encode(value) }
        func stored() throws -> Settings.Snapshot { try JSONDecoder().decode(Settings.Snapshot.self, from: XCTUnwrap(bytes)) }
        var settings: Settings {
            Settings(containerURL: { URL(fileURLWithPath: "/injected-key-preferences") }, readPrefix: { _, maximum in
                self.reads += 1
                XCTAssertEqual(maximum, Settings.maximumPayloadBytes + 1)
                guard !self.failReads else { throw Failure.unavailable }
                guard let bytes = self.bytes else { throw CocoaError(.fileReadNoSuchFile) }
                return bytes
            }, writeAtomically: { data, url in
                self.attempts += 1
                XCTAssertEqual(url.lastPathComponent, Settings.filename)
                if self.failWrites { throw Failure.unavailable }
                self.beforeWrite?()
                self.bytes = data
                self.successfulWrites += 1
            })
        }
    }
    private var initial: Settings.Snapshot { .init(overrides: ["letter.a": .init(longPress: ["à"], swipeDown: [])]) }

    func testInitializationReadsOnlyAppAuthoredSnapshotAndMissingFileUsesDefaults() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        XCTAssertEqual(preferences.snapshot, initial)
        XCTAssertNil(preferences.saveError)
        XCTAssertEqual(storage.reads, 1); XCTAssertEqual(storage.attempts, 0)
        let missing = try SharedFile()
        let fresh = KeyboardKeyPreferences(settings: missing.settings)
        XCTAssertEqual(fresh.snapshot, .defaults)
        XCTAssertNil(fresh.saveError)
        XCTAssertEqual(missing.attempts, 0)
    }

    func testFailedWriteKeepsBothStoredAndPublishedPreferencesWithoutPrematureEmission() async throws {
        let storage = try SharedFile(initial); let oldBytes = storage.bytes
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        var publications: [Settings.Snapshot] = []
        let observation = preferences.$snapshot.dropFirst().sink { publications.append($0) }
        defer { observation.cancel() }
        storage.failWrites = true
        XCTAssertFalse(preferences.save(["A"], keyID: "letter.a", gesture: .longPress, replacing: ["à"]))
        XCTAssertEqual(preferences.snapshot, initial); XCTAssertEqual(storage.bytes, oldBytes)
        XCTAssertTrue(publications.isEmpty)
        XCTAssertEqual(storage.attempts, 1); XCTAssertEqual(storage.successfulWrites, 0)
        XCTAssertFalse(preferences.saveError?.isEmpty ?? true)
    }

    func testSuccessfulWritePublishesOnlyAfterExactBytesAreStored() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        let old = preferences.snapshot
        var checkedBeforeWrite = false
        storage.beforeWrite = {
            checkedBeforeWrite = true
            XCTAssertEqual(preferences.snapshot, old)
            XCTAssertEqual(try? storage.stored(), old)
        }
        var publications: [Settings.Snapshot] = []; var persistedAtPublication: [Settings.Snapshot?] = []
        let observation = preferences.$snapshot.dropFirst().sink { value in
            publications.append(value); persistedAtPublication.append(try? storage.stored())
        }
        defer { observation.cancel(); storage.beforeWrite = nil }
        XCTAssertTrue(preferences.save(["👩‍💻", "e\u{301}"], keyID: "letter.a", gesture: .swipeUp, replacing: nil))
        XCTAssertTrue(checkedBeforeWrite)
        XCTAssertEqual(publications, [preferences.snapshot])
        XCTAssertEqual(persistedAtPublication, [preferences.snapshot])
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.a", gesture: .swipeUp), ["👩‍💻", "e\u{301}"])
        XCTAssertNil(preferences.saveError)
    }

    func testRetryAfterFailedWriteClearsErrorWithoutLosingTheOriginalSlot() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        storage.failWrites = true
        XCTAssertFalse(preferences.save([], keyID: "letter.a", gesture: .longPress, replacing: ["à"]))
        XCTAssertNotNil(preferences.saveError)
        storage.failWrites = false
        XCTAssertTrue(preferences.save([], keyID: "letter.a", gesture: .longPress, replacing: ["à"]))
        XCTAssertNil(preferences.saveError)
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.a", gesture: .longPress), [])
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.a", gesture: .swipeDown), [])
        XCTAssertEqual(try storage.stored(), preferences.snapshot)
        XCTAssertEqual(storage.attempts, 2); XCTAssertEqual(storage.successfulWrites, 1)
    }

    func testSameSlotConflictUsesExactUTF16RatherThanCanonicalStringEquality() async throws {
        let nfc = Settings.Snapshot(overrides: ["letter.e": .init(longPress: ["é"])])
        let nfd = Settings.Snapshot(overrides: ["letter.e": .init(longPress: ["e\u{301}"])])
        let storage = try SharedFile(nfc)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        try storage.replaceExternally(nfd)
        var publications = 0
        let observation = preferences.$snapshot.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        XCTAssertFalse(preferences.save(["x"], keyID: "letter.e", gesture: .longPress, replacing: ["é"]))
        XCTAssertEqual(storage.attempts, 0); XCTAssertEqual(publications, 0)
        XCTAssertEqual(try storage.stored(), nfd); XCTAssertEqual(preferences.snapshot, nfc)
        XCTAssertNotNil(preferences.saveError)
        preferences.refresh()
        XCTAssertEqual(preferences.snapshot, nfd); XCTAssertEqual(publications, 1)
        XCTAssertTrue(preferences.save(["x"], keyID: "letter.e", gesture: .longPress, replacing: ["e\u{301}"]))
        XCTAssertNil(preferences.saveError)
        XCTAssertEqual(Array(try XCTUnwrap(preferences.snapshot.candidates(for: "letter.e", gesture: .longPress)?.first).utf16), [0x78])
    }

    func testOptimisticConflictsDistinguishDisabledMissingOrderAndListLength() async throws {
        let cases: [([String]?, [String]?)] = [(nil, []), ([], nil), (["a"], ["a", "b"]), (["a", "b"], ["b", "a"])]
        for (original, changed) in cases {
            let before = Settings.Snapshot.defaults.updating(original, for: "letter.a", gesture: .swipeUp)!
            let after = Settings.Snapshot.defaults.updating(changed, for: "letter.a", gesture: .swipeUp)!
            let storage = try SharedFile(before)
            let preferences = KeyboardKeyPreferences(settings: storage.settings)
            try storage.replaceExternally(after)
            XCTAssertFalse(preferences.save(["x"], keyID: "letter.a", gesture: .swipeUp, replacing: original))
            XCTAssertEqual(storage.attempts, 0); XCTAssertEqual(preferences.snapshot, before)
            XCTAssertEqual(try storage.stored(), after)
        }
    }

    func testSavingOneSlotMergesFreshOtherSlotsAndOtherKeys() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        let externallyChanged = Settings.Snapshot(overrides: [
            "letter.a": .init(longPress: ["à"], swipeUp: ["↑"], swipeDown: []),
            "digit.0": .init(swipeDown: ["⁰"])
        ])
        try storage.replaceExternally(externallyChanged)
        XCTAssertTrue(preferences.save(["á"], keyID: "letter.a", gesture: .longPress, replacing: ["à"]))
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.a", gesture: .longPress), ["á"])
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.a", gesture: .swipeUp), ["↑"])
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.a", gesture: .swipeDown), [])
        XCTAssertEqual(preferences.snapshot.candidates(for: "digit.0", gesture: .swipeDown), ["⁰"])
        XCTAssertEqual(try storage.stored(), preferences.snapshot)
    }

    func testInvalidKeysAndCandidatesFailBeforeTheWriterOrPublishedValueChanges() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        XCTAssertFalse(preferences.save(["x"], keyID: "utility.globe", gesture: .swipeUp, replacing: nil))
        for invalid in [[""], ["x", "x"], [String(repeating: "a", count: 65)], Array(repeating: "x", count: 17)] {
            XCTAssertFalse(preferences.save(invalid, keyID: "letter.z", gesture: .swipeUp, replacing: nil))
        }
        XCTAssertEqual(storage.attempts, 0); XCTAssertEqual(preferences.snapshot, initial)
        XCTAssertNotNil(preferences.saveError)
        XCTAssertTrue(preferences.save(["é", "e\u{301}", "👩‍💻"], keyID: "letter.z", gesture: .swipeUp, replacing: nil))
        XCTAssertEqual(preferences.snapshot.candidates(for: "letter.z", gesture: .swipeUp)?.count, 3)
        XCTAssertNil(preferences.saveError)
    }

    func testRefreshReadsWithoutWritesAndEmitsOnlyExactChangedSnapshots() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        var publications: [Settings.Snapshot] = []
        let observation = preferences.$snapshot.dropFirst().sink { publications.append($0) }
        defer { observation.cancel() }
        preferences.refresh(); XCTAssertTrue(publications.isEmpty)
        let nfc = Settings.Snapshot(overrides: ["letter.e": .init(longPress: ["é"])])
        let nfd = Settings.Snapshot(overrides: ["letter.e": .init(longPress: ["e\u{301}"])])
        try storage.replaceExternally(nfc); preferences.refresh()
        try storage.replaceExternally(nfd); preferences.refresh(); preferences.refresh()
        XCTAssertEqual(publications, [nfc, nfd])
        storage.bytes = Data("corrupt".utf8); preferences.refresh()
        XCTAssertEqual(publications, [nfc, nfd])
        XCTAssertEqual(preferences.snapshot, nfd)
        XCTAssertNotNil(preferences.saveError)
        XCTAssertEqual(storage.bytes, Data("corrupt".utf8)); XCTAssertEqual(storage.attempts, 0)
        try storage.replaceExternally(nfd); preferences.refresh()
        XCTAssertEqual(publications, [nfc, nfd]); XCTAssertNil(preferences.saveError)
    }

    func testPerKeyAndAllResetsPersistAtomicallyAndRespectFailure() async throws {
        let all = Settings.Snapshot(overrides: ["letter.a": .init(longPress: ["a"]), "digit.1": .init(swipeDown: ["①"])])
        let storage = try SharedFile(all); let original = storage.bytes
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        storage.failWrites = true
        XCTAssertFalse(preferences.reset(keyID: "letter.a")); XCTAssertEqual(preferences.snapshot, all)
        XCTAssertFalse(preferences.resetAll()); XCTAssertEqual(preferences.snapshot, all)
        XCTAssertEqual(storage.bytes, original)
        let attempts = storage.attempts
        XCTAssertFalse(preferences.reset(keyID: "unknown")); XCTAssertEqual(storage.attempts, attempts)
        storage.failWrites = false
        XCTAssertTrue(preferences.reset(keyID: "letter.a"))
        XCTAssertNil(preferences.snapshot.overrides["letter.a"])
        XCTAssertEqual(preferences.snapshot.candidates(for: "digit.1", gesture: .swipeDown), ["①"])
        XCTAssertEqual(try storage.stored(), preferences.snapshot); XCTAssertNil(preferences.saveError)
        XCTAssertTrue(preferences.resetAll()); XCTAssertEqual(preferences.snapshot, .defaults)
        XCTAssertEqual(try storage.stored(), .defaults); XCTAssertNil(preferences.saveError)
        XCTAssertEqual(storage.successfulWrites, 2)
    }

    func testMissingGroupCannotClaimSuccessfulSaveOrReset() async throws {
        let settings = Settings(containerURL: { nil }, readPrefix: { _, _ in XCTFail("No group read"); return Data() },
                                writeAtomically: { _, _ in XCTFail("No group write") })
        let preferences = KeyboardKeyPreferences(settings: settings)
        XCTAssertEqual(preferences.snapshot, .defaults)
        XCTAssertFalse(preferences.save(["a"], keyID: "letter.a", gesture: .swipeUp, replacing: nil))
        XCTAssertFalse(preferences.resetAll()); XCTAssertNotNil(preferences.saveError)
        XCTAssertEqual(preferences.snapshot, .defaults)
    }

    func testUnavailableReadCannotOverwriteAnOriginallyNondefaultSlot() async throws {
        let storage = try SharedFile(initial)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        storage.failReads = true
        XCTAssertFalse(preferences.save(["a"], keyID: "letter.a", gesture: .longPress, replacing: ["à"]))
        XCTAssertEqual(storage.attempts, 0); XCTAssertEqual(preferences.snapshot, initial)
        XCTAssertEqual(try storage.stored(), initial)
        XCTAssertNotNil(preferences.saveError)
    }

    func testOriginallyDefaultSlotCannotClobberUnreadableOtherKeysAndExplicitResetCanRecover() async throws {
        let original = try JSONEncoder().encode(initial)
        let invalidBytes = [Data("corrupt".utf8),
                            original + Data(repeating: 0x20, count: Settings.maximumPayloadBytes + 1 - original.count),
                            Data(#"{"schemaVersion":99,"overrides":[]}"#.utf8), original]
        for (index, bytes) in invalidBytes.enumerated() {
            let storage = try SharedFile(initial)
            let preferences = KeyboardKeyPreferences(settings: storage.settings)
            storage.bytes = bytes; storage.failReads = index == 3
            XCTAssertFalse(preferences.save(["z"], keyID: "letter.z", gesture: .swipeUp, replacing: nil))
            XCTAssertFalse(preferences.reset(keyID: "letter.a"))
            XCTAssertEqual(storage.attempts, 0); XCTAssertEqual(storage.bytes, bytes)
            XCTAssertEqual(preferences.snapshot, initial); XCTAssertNotNil(preferences.saveError)
            let reads = storage.reads
            XCTAssertTrue(preferences.resetAll(), "The separate confirmed reset intentionally replaces unreadable bytes")
            XCTAssertEqual(storage.reads, reads, "Reset-all must not require a successful merge read")
            XCTAssertEqual(storage.successfulWrites, 1); XCTAssertEqual(try storage.stored(), .defaults)
            XCTAssertEqual(preferences.snapshot, .defaults); XCTAssertNil(preferences.saveError)
        }
    }

    func testInitiallyCorruptConfigurationShowsErrorWithoutEnablingImplicitOverwrite() async throws {
        let storage = try SharedFile(); storage.bytes = Data("corrupt".utf8)
        let preferences = KeyboardKeyPreferences(settings: storage.settings)
        XCTAssertEqual(preferences.snapshot, .defaults); XCTAssertNotNil(preferences.saveError)
        XCTAssertFalse(preferences.save(["x"], keyID: "letter.x", gesture: .longPress, replacing: nil))
        XCTAssertFalse(preferences.reset(keyID: "letter.x")); XCTAssertEqual(storage.attempts, 0)
        storage.failWrites = true
        XCTAssertFalse(preferences.resetAll()); XCTAssertEqual(storage.bytes, Data("corrupt".utf8))
        XCTAssertNotNil(preferences.saveError)
        storage.failWrites = false
        XCTAssertTrue(preferences.resetAll()); XCTAssertEqual(try storage.stored(), .defaults)
        XCTAssertNil(preferences.saveError)
    }
}
#endif
