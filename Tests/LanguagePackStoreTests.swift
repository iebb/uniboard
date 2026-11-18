import XCTest
import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class LanguagePackStoreTests: XCTestCase {
    private var sandbox: URL!
    private var store: LanguagePackStore!
    private let bytes = Data("small real dictionary fixture\n".utf8)
    private let mode = "japanese-romaji"
    private let abi = "fixture-engine-v1"

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
        store = LanguagePackStore(root: sandbox.appendingPathComponent("packs"))
        PayloadVerificationCache.shared.removeAll()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
        store = nil
        sandbox = nil
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func descriptor(version: String = "1", payload: Data? = nil, path: String = "Dictionary/words.dat") -> LanguagePackDescriptor {
        let data = payload ?? bytes
        return LanguagePackDescriptor(packID: "fixture-pack", version: version, modeID: mode, engineABI: abi,
                                      sourceURL: URL(string: "https://data.example.test/pinned/archive")!,
                                      allowedHosts: ["data.example.test"], archiveByteCount: Int64(data.count),
                                      archiveSHA256: digest(data), installedBytes: Int64(data.count), fileCount: 1,
                                      files: [.init(path: path, byteCount: Int64(data.count), sha256: digest(data))],
                                      licenseNotice: "Fixture data created for these tests; no upstream data copied.",
                                      sourceNotice: "Locally generated test fixture, not a production dictionary.")
    }

    private func manifest(_ value: LanguagePackDescriptor) throws -> Data { try JSONEncoder().encode(value) }

    private func changed(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: manifest(descriptor())) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func populate(_ directory: URL, data: Data? = nil) throws {
        let dictionary = directory.appendingPathComponent("Dictionary")
        try FileManager.default.createDirectory(at: dictionary, withIntermediateDirectories: false)
        try (data ?? bytes).write(to: dictionary.appendingPathComponent("words.dat"))
    }

    @discardableResult
    private func install(version: String = "1", expected: String? = nil) throws -> ValidatedInstalledLanguagePack {
        try store.install(manifestData: manifest(descriptor(version: version)), expectedRevision: expected) { try populate($0) }
    }

    private func acquire() throws -> LanguagePackReadLease {
        switch store.resolve(modeID: mode, engineABI: abi) {
        case .available(let lease): return lease
        default: XCTFail("expected available verified pack"); throw LanguagePackError.corruptStore("test resolution")
        }
    }

    func testDiskBudgetIncludesSourcesTransportCopyCompileStageAndSQLiteTemporaries() throws {
        let plan = try LanguagePackSpacePlan(sourceBytes: [100, 20], installedBytes: 510, compiledBytes: 500)
        let manifestBudget = Int64(LanguagePackDescriptor.maximumManifestBytes)
        let baseBudget: Int64 = 2240 // 120 + 100 + 2 * 510 + 2 * 500
        let expectedPlanBytes: Int64 = baseBudget + LanguagePackSpacePlan.headroom + manifestBudget
        XCTAssertEqual(plan.requiredBytes, expectedPlanBytes)
        let japanese = try LanguagePackSpacePlan(sourceBytes: [100], installedBytes: 500)
        let expectedJapaneseBytes: Int64 = 700 + LanguagePackSpacePlan.headroom + manifestBudget
        XCTAssertEqual(japanese.requiredBytes, expectedJapaneseBytes)
        XCTAssertThrowsError(try LanguagePackSpacePlan(sourceBytes: [Int64.max], installedBytes: 1))
        XCTAssertThrowsError(try LanguagePackSpacePlan(sourceBytes: [1], installedBytes: 1, compiledBytes: 2))
    }

    func testInjectedCapacityLowUnknownAndSufficientPreservePublication() throws {
        let original = try install()
        let plan = try LanguagePackSpacePlan(sourceBytes: [100], installedBytes: 500)
        let required = plan.requiredBytes
        let locations = [store.root, sandbox!]
        XCTAssertEqual(plan.assess(at: locations, capacity: { _ in 1 }), .insufficient(required: required, available: 1))
        XCTAssertEqual(plan.assess(at: locations, capacity: { _ in nil }), .unknown(required: required))
        XCTAssertEqual(plan.assess(at: locations, capacity: { _ in -1 }), .unknown(required: required))
        XCTAssertEqual(plan.assess(at: locations, capacity: { _ in required }), .sufficient(required: required, available: required))
        let storePath = store.root
        XCTAssertEqual(plan.assess(at: locations, capacity: { $0 == storePath ? required : nil }), .unknown(required: required))
        XCTAssertThrowsError(try plan.requireCapacity(at: locations, capacity: { _ in nil }))
        XCTAssertThrowsError(try plan.requireCapacity(at: locations, capacity: { _ in 0 }))
        XCTAssertNoThrow(try plan.requireCapacity(at: locations, capacity: { _ in required }))
        XCTAssertEqual(try store.activeRevision(modeID: mode), original.revision)
        let lease = try acquire(); defer { lease.release() }
        XCTAssertEqual(lease.pack.revision, original.revision)
    }

    func testDamagedAndIncompatiblePublicationsRemainRemovableWithoutReadiness() throws {
        let pack = try install()
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        guard case .incompatible = store.resolve(modeID: mode, engineABI: "new-abi") else { return XCTFail("ABI") }
        XCTAssertEqual(token.revision, pack.revision)
        try FileManager.default.removeItem(at: pack.path.appendingPathComponent("Dictionary/words.dat"))
        guard case .corrupt = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("damage") }
        XCTAssertEqual(try store.removablePublication(modeID: mode), token)
        try store.remove(token)
        XCTAssertNil(try store.removablePublication(modeID: mode))
    }

    func testPostUnlinkSyncFailureStillReportsCommittedRemovalAndPreservesMyWords() throws {
        let pack = try install()
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        let wordsURL = sandbox.appendingPathComponent("My Words.json")
        let words = Data("custom-words-must-survive-removal".utf8)
        try words.write(to: wordsURL)
        let pointer = store.root.appendingPathComponent("active/" + mode + ".json")
        var syncCalls = 0
        XCTAssertNoThrow(try store.remove(modeID: token.modeID, expectedRevision: token.revision, syncAfterUnlink: { directory in
            syncCalls += 1
            XCTAssertEqual(directory, self.store.root.appendingPathComponent("active"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: pointer.path), "fault must occur after unlink commit")
            throw LanguagePackError.filesystem(operation: "injected directory sync", code: EIO)
        }))
        XCTAssertEqual(syncCalls, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pointer.path))
        XCTAssertNil(try store.activeRevision(modeID: mode))
        XCTAssertNil(try store.removablePublication(modeID: mode))
        guard case .missing = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("publication must be removed") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: pack.path.path), "ordinary unleased payload can still be reclaimed")
        XCTAssertEqual(try Data(contentsOf: wordsURL), words)
    }

    func testEntirelyMissingVersionStillAllowsValidatedPointerRemoval() throws {
        let pack = try install()
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        try FileManager.default.removeItem(at: pack.path.deletingLastPathComponent())
        guard case .corrupt = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("dangling pointer must not be ready") }
        XCTAssertEqual(try store.removablePublication(modeID: mode), token)
        XCTAssertNoThrow(try store.remove(token))
        XCTAssertNil(try store.activeRevision(modeID: mode))
        XCTAssertNil(try store.removablePublication(modeID: mode))
    }

    func testReadableValidPointerWithUnreadablePayloadStillAllowsRemoval() throws {
        if geteuid() == 0 { throw XCTSkip("root bypasses filesystem permissions") }
        let pack = try install()
        let payload = pack.path.appendingPathComponent("Dictionary/words.dat")
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        XCTAssertEqual(chmod(payload.path, mode_t(0o000)), 0)
        defer { _ = chmod(payload.path, mode_t(0o600)) }
        guard case .unreadable = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("payload must be unreadable") }
        XCTAssertEqual(try store.removablePublication(modeID: mode), token)
        XCTAssertNoThrow(try store.remove(token))
        XCTAssertNil(try store.activeRevision(modeID: mode))
        XCTAssertNil(try store.removablePublication(modeID: mode))
    }

    func testSymlinkAndHardlinkActivePointersGrantNoRemovalAuthorityOrExternalMutation() throws {
        let pack = try install()
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        let pointer = store.root.appendingPathComponent("active/" + mode + ".json")
        let validPointer = try Data(contentsOf: pointer)
        for hardlink in [false, true] {
            let external = sandbox.appendingPathComponent(hardlink ? "external-hardlink.json" : "external-symlink.json")
            try validPointer.write(to: external)
            try FileManager.default.removeItem(at: pointer)
            if hardlink {
                try FileManager.default.linkItem(at: external, to: pointer)
            } else {
                try FileManager.default.createSymbolicLink(at: pointer, withDestinationURL: external)
            }
            XCTAssertThrowsError(try store.removablePublication(modeID: mode), "linked pointer must not authorize removal")
            XCTAssertThrowsError(try store.activeRevision(modeID: mode))
            XCTAssertThrowsError(try store.remove(token), "a previously valid confirmation cannot bypass current pointer guards")
            XCTAssertEqual(try Data(contentsOf: external), validPointer)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pointer.path), "must not unlink a rejected pointer")
            XCTAssertEqual(try Data(contentsOf: pack.path.appendingPathComponent("Dictionary/words.dat")), bytes)
            try FileManager.default.removeItem(at: pointer)
            try validPointer.write(to: pointer)
            XCTAssertEqual(try Data(contentsOf: external), validPointer)
        }
        XCTAssertEqual(try store.removablePublication(modeID: mode), token)
    }

    func testConfirmedRemovalTokenCannotDeleteReplacementAndHonorsLease() throws {
        let first = try install()
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        let lease = try acquire(); defer { lease.release() }
        let second = try install(expected: first.revision)
        XCTAssertThrowsError(try store.remove(token))
        XCTAssertEqual(try store.activeRevision(modeID: mode), second.revision)
        let currentLease = try acquire(); defer { currentLease.release() }
        let currentToken = try XCTUnwrap(store.removablePublication(modeID: mode))
        try store.remove(currentToken)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path.path))
        XCTAssertEqual(try Data(contentsOf: first.path.appendingPathComponent("Dictionary/words.dat")), bytes)
    }

    func testMalformedPointerNeverGrantsRemovalAuthorityAndForeignVersionIsNotDeleted() throws {
        let pack = try install()
        let token = try XCTUnwrap(store.removablePublication(modeID: mode))
        let pointer = store.root.appendingPathComponent("active/" + mode + ".json")
        let validPointer = try Data(contentsOf: pointer)
        try Data("{\"format\":1,\"modeID\":\"japanese-romaji\",\"revision\":\"../foreign\"}".utf8).write(to: pointer)
        XCTAssertThrowsError(try store.removablePublication(modeID: mode))
        XCTAssertThrowsError(try store.remove(token))
        try validPointer.write(to: pointer)
        let foreign = pack.path.deletingLastPathComponent().appendingPathComponent("foreign")
        try bytes.write(to: foreign)
        // Deactivation succeeds, but the guarded reclaimer refuses foreign contents.
        try store.remove(token)
        XCTAssertNil(try store.activeRevision(modeID: mode))
        XCTAssertEqual(try Data(contentsOf: foreign), bytes)
    }

    func testRoundTripHasImmutableRevisionNotUpstreamVersionAndPreservesNotices() throws {
        let first = try install()
        let lease = try acquire()
        defer { lease.release() }
        XCTAssertEqual(lease.pack, first)
        XCTAssertNotEqual(first.revision, first.descriptor.version)
        XCTAssertEqual(try Data(contentsOf: first.path.appendingPathComponent("Dictionary/words.dat")), bytes)
        XCTAssertEqual(lease.pack.descriptor.licenseNotice, descriptor().licenseNotice)
        XCTAssertEqual(lease.pack.descriptor.sourceNotice, descriptor().sourceNotice)
        let second = try install(expected: first.revision)
        XCTAssertNotEqual(first.revision, second.revision)
        XCTAssertNotEqual(first.path, second.path)
        XCTAssertEqual(second.descriptor.version, first.descriptor.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path.path))
    }

    func testAbsentMissingIncompatibleAndMissingVersionAreDistinct() throws {
        guard case .absent = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("absent store") }
        let pack = try install()
        guard case .missing = store.resolve(modeID: "other-mode", engineABI: abi) else { return XCTFail("missing mode") }
        guard case .incompatible(let required, let installed) = store.resolve(modeID: mode, engineABI: "next-ABI") else {
            return XCTFail("incompatible engine")
        }
        XCTAssertEqual(required, "next-ABI")
        XCTAssertEqual(installed, abi)
        XCTAssertEqual(try store.activeRevision(modeID: mode), pack.revision, "app can obtain a removal token despite ABI mismatch")
        try FileManager.default.removeItem(at: pack.path.deletingLastPathComponent())
        guard case .corrupt = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("dangling pointer is corrupt, not ordinary missing") }
    }

    func testUnreadableIsNotMissing() throws {
        if geteuid() == 0 { throw XCTSkip("root bypasses filesystem permissions") }
        _ = try install()
        let lock = store.root.appendingPathComponent(".writer.lock")
        XCTAssertEqual(chmod(lock.path, mode_t(0o000)), 0)
        defer { _ = chmod(lock.path, mode_t(0o600)) }
        guard case .unreadable = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("unreadable state") }
    }

    func testChooserMetadataDoesNotHashPayloadButActivationStillDoes() throws {
        let pack = try install()
        let payload = pack.path.appendingPathComponent("Dictionary/words.dat")
        // Same length, wrong hash: stat-only readiness may advertise the choice,
        // but cannot grant a lease or authorize opening an engine.
        try Data(repeating: 120, count: bytes.count).write(to: payload)
        guard case .available(let metadata) = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("chooser inspection must not hash payload bytes")
        }
        XCTAssertEqual(metadata.revision, pack.revision)
        XCTAssertEqual(metadata.descriptor, pack.descriptor)
        guard case .corrupt = store.resolve(modeID: mode, engineABI: abi) else {
            return XCTFail("activation must still reject the actual payload hash")
        }
    }

    func testChooserMetadataNeverOpensPayloadFiles() throws {
        if geteuid() == 0 { throw XCTSkip("root bypasses filesystem permissions") }
        let pack = try install()
        let payload = pack.path.appendingPathComponent("Dictionary/words.dat")
        XCTAssertEqual(chmod(payload.path, mode_t(0o000)), 0)
        defer { _ = chmod(payload.path, mode_t(0o600)) }
        guard case .available = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("metadata must work without permission to read payload contents")
        }
        guard case .unreadable = store.resolve(modeID: mode, engineABI: abi) else {
            return XCTFail("activation must open/read the payload and fail without permission")
        }
    }

    func testChooserMetadataChecksABIAndRegularFilePresence() throws {
        guard case .absent = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("absent store")
        }
        let pack = try install()
        guard case .missing = store.publishedMetadata(modeID: "other-mode", engineABI: abi) else {
            return XCTFail("missing pointer")
        }
        guard case .incompatible = store.publishedMetadata(modeID: mode, engineABI: "next-ABI") else {
            return XCTFail("metadata must validate engine ABI")
        }
        let payload = pack.path.appendingPathComponent("Dictionary/words.dat")
        try FileManager.default.removeItem(at: payload)
        guard case .corrupt = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("metadata must require declared file presence")
        }
        let foreign = sandbox.appendingPathComponent("foreign-data")
        try bytes.write(to: foreign)
        try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: foreign)
        guard case .corrupt = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("metadata must not follow file links")
        }
    }

    func testMetadataIsNotAnActivationOrCommitTokenAfterPointerReplacement() throws {
        let first = try install()
        guard case .available(let metadata) = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("initial metadata")
        }
        let oldLease = try acquire()
        defer { oldLease.release() }
        let second = try install(version: "2", expected: first.revision)
        XCTAssertNotEqual(try store.activeRevision(modeID: mode), metadata.revision,
                          "activation/commit must recheck publication after asynchronous work")
        XCTAssertNotEqual(try store.activeRevision(modeID: mode), oldLease.pack.revision,
                          "a retained runtime lease protects lifetime, not publication validity")
        let currentLease = try acquire()
        defer { currentLease.release() }
        XCTAssertEqual(currentLease.pack.revision, second.revision)
        guard case .available(let current) = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("replacement metadata")
        }
        XCTAssertEqual(current.revision, second.revision)
        try store.remove(modeID: mode, expectedRevision: second.revision)
        guard case .missing = store.publishedMetadata(modeID: mode, engineABI: abi) else {
            return XCTFail("removal must immediately revoke chooser readiness")
        }
        XCTAssertNil(try store.activeRevision(modeID: mode))
    }

    func testManifestBoundsAndMetadataValidation() throws {
        XCTAssertEqual(LanguagePackDescriptor.maximumFileCount, 4_096)
        XCTAssertEqual(LanguagePackDescriptor.maximumManifestBytes, 2 * 1_024 * 1_024)
        XCTAssertEqual(LanguagePackDescriptor.maximumInstalledBytes, 256 * 1_024 * 1_024)
        XCTAssertThrowsError(try LanguagePackDescriptor.validated(from: Data(repeating: 32, count: LanguagePackDescriptor.maximumManifestBytes + 1)))
        XCTAssertThrowsError(try LanguagePackDescriptor.validated(from: Data("{".utf8)))
        let badFields: [(String, Any)] = [
            ("formatVersion", 999), ("packID", "../foreign"), ("modeID", ""), ("engineABI", "../engine"),
            ("fileCount", 4_097), ("installedBytes", 256 * 1_024 * 1_024 + 1),
            ("archiveByteCount", 0), ("archiveByteCount", 256 * 1_024 * 1_024 + 1),
            ("archiveSHA256", String(repeating: "A", count: 64)), ("archiveSHA256", "1234"),
            ("sourceURL", "http://data.example.test/archive"), ("sourceURL", "https://evil.test/archive"),
            ("sourceURL", "https://user:password@data.example.test/archive"),
            ("sourceURL", "https://data.example.test:444/archive"),
            ("allowedHosts", ["DATA.example.test"]), ("allowedHosts", ["data.example.test", "data.example.test"]),
            ("licenseNotice", "  "), ("sourceNotice", "")
        ]
        for (key, value) in badFields {
            let data = try changed { $0[key] = value }
            XCTAssertThrowsError(try LanguagePackDescriptor.validated(from: data), "should reject \(key)")
        }
        let wrongSize = try changed { $0["installedBytes"] = bytes.count + 1 }
        XCTAssertThrowsError(try LanguagePackDescriptor.validated(from: wrongSize))
    }

    func testStrictPathsHashesDuplicatesAndPrefixCollisions() throws {
        let badPaths = ["", "/absolute", "../escape", "a/../b", "./a", "a/./b", "a//b", "a/", "a\\b", "a\0b", "a\nb", "e\u{301}.dat"]
        for path in badPaths {
            XCTAssertThrowsError(try descriptor(path: path).validate(), "reject \(path.debugDescription)")
        }
        for hash in [String(repeating: "F", count: 64), String(repeating: "g", count: 64), "", "00"] {
            let data = try changed { object in
                var files = object["files"] as! [[String: Any]]
                files[0]["sha256"] = hash
                object["files"] = files
            }
            XCTAssertThrowsError(try LanguagePackDescriptor.validated(from: data))
        }
        for paths in [["a", "a"], ["A", "a"], ["a", "a/child"]] {
            let data = try changed { object in
                let file = (object["files"] as! [[String: Any]])[0]
                object["files"] = paths.map { path -> [String: Any] in var f = file; f["path"] = path; return f }
                object["fileCount"] = 2
                object["installedBytes"] = bytes.count * 2
            }
            XCTAssertThrowsError(try LanguagePackDescriptor.validated(from: data))
        }
    }

    func testSHAAndSizeVerificationLeavePriorPointerUsable() throws {
        let original = try install()
        let badPayloads = [Data(repeating: 120, count: bytes.count), Data(bytes.dropLast()), bytes + Data([1])]
        for bad in badPayloads {
            XCTAssertThrowsError(try store.install(manifestData: manifest(descriptor(version: "2")), expectedRevision: original.revision) {
                try populate($0, data: bad)
            })
            let lease = try acquire()
            XCTAssertEqual(lease.pack.revision, original.revision)
            lease.release()
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("staging").path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("versions").path), [original.revision])
    }

    func testRejectsExtraMissingSymlinkHardlinkAndExecutablePayloads() throws {
        let original = try install()
        let foreign = sandbox.appendingPathComponent("foreign-data")
        try bytes.write(to: foreign)
        let mutations: [(URL) throws -> Void] = [
            { directory in try self.bytes.write(to: directory.appendingPathComponent("extra")) },
            { directory in try FileManager.default.createDirectory(at: directory.appendingPathComponent("unexpected"), withIntermediateDirectories: false) },
            { directory in try FileManager.default.removeItem(at: directory.appendingPathComponent("Dictionary/words.dat")) },
            { directory in
                let file = directory.appendingPathComponent("Dictionary/words.dat")
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
            },
            { directory in
                let dictionary = directory.appendingPathComponent("Dictionary")
                try FileManager.default.removeItem(at: dictionary)
                try FileManager.default.createSymbolicLink(at: dictionary, withDestinationURL: self.sandbox)
            },
            { directory in
                let file = directory.appendingPathComponent("Dictionary/words.dat")
                try FileManager.default.removeItem(at: file)
                try FileManager.default.linkItem(at: foreign, to: file)
            },
            { directory in
                let file = directory.appendingPathComponent("Dictionary/words.dat")
                try FileManager.default.removeItem(at: file)
                guard mkfifo(file.path, mode_t(0o600)) == 0 else { throw LanguagePackError.corruptStore("test mkfifo") }
            },
            { directory in
                let file = directory.appendingPathComponent("Dictionary/words.dat")
                guard chmod(file.path, mode_t(0o700)) == 0 else { throw LanguagePackError.corruptStore("test chmod") }
            }
        ]
        for mutate in mutations {
            XCTAssertThrowsError(try store.install(manifestData: manifest(descriptor(version: "2")), expectedRevision: original.revision) {
                try populate($0)
                try mutate($0)
            })
            XCTAssertEqual(try Data(contentsOf: foreign), bytes, "must not mutate/delete symlink or hardlink targets")
            let lease = try acquire()
            XCTAssertEqual(lease.pack.revision, original.revision)
            lease.release()
        }
    }

    func testArchiveVerificationUsesActualHashAndByteCount() throws {
        let archive = sandbox.appendingPathComponent("archive")
        try bytes.write(to: archive)
        try LanguagePackStore.verifyArchive(at: archive, descriptor: descriptor())
        try Data(repeating: 120, count: bytes.count).write(to: archive)
        XCTAssertThrowsError(try LanguagePackStore.verifyArchive(at: archive, descriptor: descriptor()))
        try bytes.dropLast().write(to: archive)
        XCTAssertThrowsError(try LanguagePackStore.verifyArchive(at: archive, descriptor: descriptor()))
    }

    func testAllInjectedPrepublicationFaultsKeepLastGoodAndCleanOwnedPaths() throws {
        enum Fault: Error { case injected }
        let original = try install()
        for target in 0..<3 {
            var checkpoints = 0
            XCTAssertThrowsError(try store.install(manifestData: manifest(descriptor(version: "2")), expectedRevision: original.revision,
                                                   populate: { try populate($0) }, checkpoint: { _ in
                defer { checkpoints += 1 }
                if checkpoints == target { throw Fault.injected }
            }))
            let lease = try acquire()
            XCTAssertEqual(lease.pack.revision, original.revision)
            lease.release()
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("staging").path), [])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("versions").path), [original.revision])
        }
    }

    func testPartialPopulationFailureAndForeignStageAreNotDeleted() throws {
        enum Fault: Error { case interrupted }
        let original = try install()
        let foreign = store.root.appendingPathComponent("staging/foreign-folder")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        try bytes.write(to: foreign.appendingPathComponent("keep"))
        let foreignUUID = store.root.appendingPathComponent("staging").appendingPathComponent(UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at: foreignUUID, withIntermediateDirectories: false)
        try bytes.write(to: foreignUUID.appendingPathComponent("keep"))
        XCTAssertThrowsError(try store.install(manifestData: manifest(descriptor(version: "2")), expectedRevision: original.revision) {
            try bytes.write(to: $0.appendingPathComponent("partial"))
            throw Fault.interrupted
        })
        try store.reclaimUnusedVersions()
        XCTAssertEqual(try Data(contentsOf: foreign.appendingPathComponent("keep")), bytes)
        XCTAssertEqual(try Data(contentsOf: foreignUUID.appendingPathComponent("keep")), bytes)
        XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("staging").path)),
                       Set(["foreign-folder", foreignUUID.lastPathComponent]))
    }

    func testConflictDoesNotInvokePopulationOrReplacePointer() throws {
        let original = try install()
        XCTAssertThrowsError(try store.install(manifestData: manifest(descriptor(version: "2")), expectedRevision: nil) { _ in
            XCTFail("conflict must precede population")
        }) { error in
            XCTAssertEqual(error as? LanguagePackError, .revisionConflict(expected: nil, actual: original.revision))
        }
        XCTAssertThrowsError(try store.remove(modeID: mode, expectedRevision: "stale"))
        let lease = try acquire()
        XCTAssertEqual(lease.pack.revision, original.revision)
        lease.release()
    }

    func testConcurrentIndependentAppWritersSerializeAndSecondConflicts() throws {
        let original = try install()
        let data = try manifest(descriptor(version: "2"))
        let storeA = LanguagePackStore(root: store.root)
        let storeB = LanguagePackStore(root: store.root)
        let payloadBytes = bytes
        let populated = expectation(description: "first writer holds lock")
        let secondAttempt = expectation(description: "second writer begins")
        let firstDone = expectation(description: "first writer publishes")
        let secondDone = expectation(description: "second writer conflicts")
        let resume = DispatchSemaphore(value: 0)
        defer { resume.signal() }
        DispatchQueue.global().async {
            defer { firstDone.fulfill() }
            do {
                try storeA.install(manifestData: data, expectedRevision: original.revision) { directory in
                    let subdirectory = directory.appendingPathComponent("Dictionary")
                    try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: false)
                    try payloadBytes.write(to: subdirectory.appendingPathComponent("words.dat"))
                    populated.fulfill()
                    _ = resume.wait(timeout: .now() + 10)
                }
            } catch { XCTFail("first writer failed: \(error)") }
        }
        wait(for: [populated], timeout: 5)
        DispatchQueue.global().async {
            defer { secondDone.fulfill() }
            secondAttempt.fulfill()
            do {
                try storeB.install(manifestData: data, expectedRevision: original.revision) { _ in
                    XCTFail("second writer cannot populate stale revision")
                }
                XCTFail("second writer must reject the stale expected revision")
            } catch let error as LanguagePackError {
                guard case .revisionConflict(let expected, let actual) = error else {
                    return XCTFail("expected revision conflict, got \(error)")
                }
                XCTAssertEqual(expected, original.revision)
                XCTAssertNotEqual(actual, original.revision)
                XCTAssertNotNil(actual)
            } catch {
                XCTFail("expected revision conflict, got \(error)")
            }
        }
        wait(for: [secondAttempt], timeout: 5)
        resume.signal()
        wait(for: [firstDone, secondDone], timeout: 10)
        let lease = try acquire()
        XCTAssertNotEqual(lease.pack.revision, original.revision)
        lease.release()
    }

    func testRemoveImmediatelyDeactivatesButMultipleReadersRetainLazyFilesUntilRelease() throws {
        let original = try install()
        let first = try acquire()
        let second = try acquire()
        let customWords = sandbox.appendingPathComponent("custom-words")
        try Data("user words stored elsewhere".utf8).write(to: customWords)
        #if canImport(Darwin)
        let versionFD = open(original.path.deletingLastPathComponent().path, O_EVTONLY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(versionFD, 0)
        guard versionFD >= 0 else { first.release(); second.release(); return }
        let reclaimed = expectation(description: "last reader release permits deletion")
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: versionFD, eventMask: .delete, queue: .global())
        source.setEventHandler { reclaimed.fulfill() }
        source.setCancelHandler { close(versionFD) }
        source.resume()
        defer { source.cancel() }
        #endif
        try store.remove(modeID: mode, expectedRevision: original.revision)
        guard case .missing = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("remove must immediately hide pointer") }
        try store.reclaimUnusedVersions()
        XCTAssertEqual(try Data(contentsOf: original.path.appendingPathComponent("Dictionary/words.dat")), bytes)
        first.release()
        first.release() // Idempotent; must not close a subsequently reused descriptor.
        try store.reclaimUnusedVersions()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path.path))
        second.release()
        try store.reclaimUnusedVersions()
        #if canImport(Darwin)
        // A background waiter may momentarily own the lease lock while the explicit
        // nonblocking sweep runs; wait for the observable deletion, not a timing race.
        wait(for: [reclaimed], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path.path))
        #endif
        XCTAssertEqual(try String(contentsOf: customWords), "user words stored elsewhere")
    }

    func testUpdateAndReclaimPreserveReaderAndNewActiveVersion() throws {
        let original = try install()
        var lease: LanguagePackReadLease? = try acquire()
        let next = try install(version: "2", expected: original.revision)
        try store.reclaimUnusedVersions()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path.path))
        XCTAssertEqual(lease?.pack.revision, original.revision)
        lease = nil // deinit releases the cross-process flock too.
        try store.reclaimUnusedVersions()
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: next.path.path))
        let active = try acquire()
        XCTAssertEqual(active.pack.revision, next.revision)
        active.release()
    }

    func testJapaneseFileCountAndPinyinSizeFitInitialLimits() throws {
        let files = (0..<3_397).map { index in
            LanguagePackDescriptor.File(path: "Dictionary/\(index).dat", byteCount: 0, sha256: digest(Data()))
        }
        let japanese = LanguagePackDescriptor(packID: "fixture", version: "1", modeID: mode, engineABI: abi,
                                             sourceURL: descriptor().sourceURL, allowedHosts: descriptor().allowedHosts,
                                             archiveByteCount: 1, archiveSHA256: digest(Data([0])), installedBytes: 0,
                                             fileCount: files.count, files: files, licenseNotice: "Fixture", sourceNotice: "Fixture")
        try japanese.validate()
        let fortySevenMiB: Int64 = 47 * 1_024 * 1_024
        let pinyin = LanguagePackDescriptor(packID: "fixture", version: "1", modeID: "pinyin", engineABI: abi,
                                          sourceURL: descriptor().sourceURL, allowedHosts: descriptor().allowedHosts,
                                          archiveByteCount: 1, archiveSHA256: digest(Data([0])), installedBytes: fortySevenMiB,
                                          fileCount: 1, files: [.init(path: "data", byteCount: fortySevenMiB, sha256: digest(Data()))],
                                          licenseNotice: "Fixture", sourceNotice: "Fixture")
        try pinyin.validate() // Metadata bounds only; these invented bytes would fail installation hashing.
    }

    func testResolverWorksWithReadOnlyStoreFiles() throws {
        let original = try install()
        let version = original.path.deletingLastPathComponent()
        let directories = [store.root, store.root.appendingPathComponent("versions"), store.root.appendingPathComponent("active"),
                           version, original.path, original.path.appendingPathComponent("Dictionary")]
        let files = [store.root.appendingPathComponent(".writer.lock"), store.root.appendingPathComponent("active/\(mode).json"),
                     version.appendingPathComponent(".lease"), version.appendingPathComponent(".owner"),
                     version.appendingPathComponent("descriptor.json"), original.path.appendingPathComponent("Dictionary/words.dat")]
        defer {
            for directory in directories { _ = chmod(directory.path, mode_t(0o700)) }
            for file in files { _ = chmod(file.path, mode_t(0o600)) }
        }
        for file in files { XCTAssertEqual(chmod(file.path, mode_t(0o400)), 0) }
        for directory in directories.reversed() { XCTAssertEqual(chmod(directory.path, mode_t(0o500)), 0) }
        let lease = try acquire()
        XCTAssertEqual(lease.pack.revision, original.revision)
        lease.release()
    }

    #if canImport(Darwin)
    func testAppAutomaticallyReclaimsRemovedVersionWhenLastLeaseCloses() throws {
        let original = try install()
        let lease = try acquire()
        let version = original.path.deletingLastPathComponent()
        let fd = open(version.path, O_EVTONLY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        let deleted = expectation(description: "app reclaimer deletes inactive leased revision")
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .delete, queue: .global())
        source.setEventHandler { deleted.fulfill() }
        source.setCancelHandler { close(fd) }
        source.resume()
        defer { source.cancel() }
        try store.remove(modeID: mode, expectedRevision: original.revision)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path.path))
        lease.release()
        wait(for: [deleted], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: version.path))
    }
    #endif

    func testTamperedInstalledPayloadAndPointerAreCorrupt() throws {
        let original = try install()
        try Data(repeating: 120, count: bytes.count).write(to: original.path.appendingPathComponent("Dictionary/words.dat"))
        guard case .corrupt = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("tampered payload") }
        let pointer = store.root.appendingPathComponent("active/\(mode).json")
        try Data("{\"format\":1,\"modeID\":\"\(mode)\",\"revision\":\"../foreign\"}".utf8).write(to: pointer)
        guard case .corrupt = store.resolve(modeID: mode, engineABI: abi) else { return XCTFail("unsafe pointer") }
        XCTAssertThrowsError(try store.reclaimUnusedVersions(), "must not reclaim around untrusted active pointer")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path.path))
    }

    // MARK: - In-process payload verification cache

    private typealias Identity = PayloadVerificationCache.FileIdentity

    /// Mutable injected clock for the racy-timestamp guard. Scripted values are
    /// returned first (one per call), then the fixed value, then "an hour ahead"
    /// so that every fixture file counts as settled (not racy).
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval?
        private var scripted: [TimeInterval] = []
        func set(_ newValue: TimeInterval?) { lock.lock(); value = newValue; lock.unlock() }
        func script(_ values: [TimeInterval]) { lock.lock(); scripted = values; lock.unlock() }
        func now() -> TimeInterval {
            lock.lock(); defer { lock.unlock() }
            if !scripted.isEmpty { return scripted.removeFirst() }
            return value ?? Date().timeIntervalSince1970 + 3_600
        }
    }

    private func settledCache(_ clock: TestClock = TestClock()) -> PayloadVerificationCache {
        PayloadVerificationCache(now: { clock.now() })
    }

    private func cachedStore(_ cache: PayloadVerificationCache) -> LanguagePackStore {
        LanguagePackStore(root: store.root, verificationCache: cache)
    }

    private enum Outcome: Equatable { case available(String), corrupt, other }

    private func resolveOnce(_ target: LanguagePackStore) -> Outcome {
        switch target.resolve(modeID: mode, engineABI: abi) {
        case .available(let lease): defer { lease.release() }; return .available(lease.pack.revision)
        case .corrupt: return .corrupt
        default: return .other
        }
    }

    private func wordsURL(_ pack: ValidatedInstalledLanguagePack) -> URL {
        pack.path.appendingPathComponent("Dictionary/words.dat")
    }

    private func identity(_ url: URL) throws -> Identity {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw LanguagePackError.filesystem(operation: "test stat", code: errno) }
        return Identity(value)
    }

    private func setTimes(_ fd: Int32, seconds: Int64, nanoseconds: Int64) throws {
        let time = timespec(tv_sec: Int(seconds), tv_nsec: Int(nanoseconds))
        var times = [time, time]
        guard futimens(fd, &times) == 0 else { throw LanguagePackError.filesystem(operation: "test futimens", code: errno) }
    }

    /// Same inode, same size, new bytes; optionally forces a chosen mtime afterwards.
    private func overwriteInPlace(_ url: URL, with data: Data, mtime: (seconds: Int64, nanoseconds: Int64)? = nil) throws {
        let fd = open(url.path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw LanguagePackError.filesystem(operation: "test open", code: errno) }
        defer { close(fd) }
        let written = data.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
        guard written == data.count else { throw LanguagePackError.filesystem(operation: "test pwrite", code: errno) }
        if let mtime { try setTimes(fd, seconds: mtime.seconds, nanoseconds: mtime.nanoseconds) }
    }

    /// New inode atomically renamed over `url`, carrying the given mtime.
    private func replaceViaRename(_ url: URL, with data: Data, mtime: (seconds: Int64, nanoseconds: Int64)) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".replacement-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw LanguagePackError.filesystem(operation: "test create", code: errno) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        do {
            guard written == data.count else { throw LanguagePackError.filesystem(operation: "test write", code: errno) }
            try setTimes(fd, seconds: mtime.seconds, nanoseconds: mtime.nanoseconds)
        } catch { close(fd); throw error }
        close(fd)
        #if canImport(Darwin)
        let result = Darwin.rename(temporary.path, url.path)
        #else
        let result = Glibc.rename(temporary.path, url.path)
        #endif
        guard result == 0 else { throw LanguagePackError.filesystem(operation: "test rename", code: errno) }
    }

    func testDefaultStoresShareOneProcessWideVerificationCache() {
        XCTAssertTrue(LanguagePackStore(root: store.root).verificationCache === PayloadVerificationCache.shared)
        XCTAssertTrue(store.verificationCache === LanguagePackStore(root: sandbox).verificationCache)
    }

    func testRepeatedResolveOfUnchangedVerifiedFileSkipsRehash() throws {
        let pack = try install()
        let cache = settledCache()
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 1, hits: 0, records: 1))
        // Fresh store values (as the keyboard creates per activation) share the cache.
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 1, hits: 2, records: 1))
        XCTAssertEqual(cache.count, 1)
        // A new revision of identical bytes is a different key: hashed again.
        let next = try install(expected: pack.revision)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(next.revision))
        XCTAssertEqual(cache.statistics.hashes, 2)
    }

    func testSameSizeInPlaceRewriteWithBumpedMtimeInvalidatesCache() throws {
        let pack = try install()
        let url = wordsURL(pack)
        let cache = settledCache()
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        let original = try identity(url)
        usleep(50_000) // Test clock bypasses the racy guard; let coarse ctime clocks tick.
        try overwriteInPlace(url, with: Data(repeating: 120, count: bytes.count),
                             mtime: (original.modificationSeconds + 60, original.modificationNanoseconds))
        let mutated = try identity(url)
        XCTAssertEqual(mutated.inode, original.inode, "simulation must keep the inode")
        XCTAssertEqual(mutated.size, original.size, "simulation must keep the size")
        XCTAssertNotEqual(mutated.modificationSeconds, original.modificationSeconds)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .corrupt)
        XCTAssertEqual(cache.statistics.hashes, 2)
        XCTAssertEqual(cache.statistics.hits, 0)
        // Putting the right bytes back is re-verified from scratch, then cached again.
        try overwriteInPlace(url, with: bytes)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 3, hits: 1, records: 2))
    }

    func testInPlaceRewriteThatRestoresMtimeIsStillCaughtByCtime() throws {
        let pack = try install()
        let url = wordsURL(pack)
        let cache = settledCache()
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        let original = try identity(url)
        usleep(50_000) // Let coarse-grained filesystem clocks tick before the rewrite.
        try overwriteInPlace(url, with: Data(repeating: 120, count: bytes.count),
                             mtime: (original.modificationSeconds, original.modificationNanoseconds))
        let mutated = try identity(url)
        XCTAssertEqual(mutated.inode, original.inode)
        XCTAssertEqual(mutated.size, original.size)
        XCTAssertEqual(mutated.modificationSeconds, original.modificationSeconds, "userland can forge mtime")
        XCTAssertEqual(mutated.modificationNanoseconds, original.modificationNanoseconds)
        XCTAssertNotEqual(mutated, original, "but not ctime")
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .corrupt)
        XCTAssertEqual(cache.statistics.hashes, 2)
    }

    func testReplacementViaRenameHasNewInodeAndIsRehashed() throws {
        let pack = try install()
        let url = wordsURL(pack)
        let cache = settledCache()
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        let original = try identity(url)
        let mtime: (seconds: Int64, nanoseconds: Int64) = (original.modificationSeconds, original.modificationNanoseconds)
        try replaceViaRename(url, with: bytes, mtime: mtime) // identical bytes, size and mtime
        let replaced = try identity(url)
        XCTAssertNotEqual(replaced.inode, original.inode)
        XCTAssertEqual(replaced.size, original.size)
        XCTAssertEqual(replaced.modificationSeconds, original.modificationSeconds)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics.hashes, 2, "new inode must be hashed, not trusted")
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics.hashes, 2)
        try replaceViaRename(url, with: Data(repeating: 120, count: bytes.count), mtime: mtime)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .corrupt)
        XCTAssertEqual(cache.statistics.hashes, 3)
    }

    func testFailedVerificationIsNeverCached() throws {
        let pack = try install()
        let cache = settledCache()
        try overwriteInPlace(wordsURL(pack), with: Data(repeating: 120, count: bytes.count))
        for attempt in 1...3 {
            XCTAssertEqual(resolveOnce(cachedStore(cache)), .corrupt)
            XCTAssertEqual(cache.statistics, .init(hashes: attempt, hits: 0, records: 0))
            XCTAssertEqual(cache.count, 0)
        }
        // A cached success is dropped as soon as a mismatching identity forces a hash.
        try overwriteInPlace(wordsURL(pack), with: bytes)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.count, 1)
        usleep(50_000) // Test clock bypasses the racy guard; let coarse ctime clocks tick.
        try overwriteInPlace(wordsURL(pack), with: Data(repeating: 121, count: bytes.count))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .corrupt)
        XCTAssertEqual(cache.count, 0)
    }

    func testRecentlyChangedOrFutureDatedFilesAreNotTrustedFromTimestamps() throws {
        let pack = try install()
        let changed = try identity(wordsURL(pack)).changeTime
        let clock = TestClock()
        let cache = settledCache(clock)
        clock.set(changed + 1) // within the racy window
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 2, hits: 0, records: 0))
        clock.set(changed - 100) // clock behind the file: never trusted
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 3, hits: 0, records: 0))
        clock.set(changed + PayloadVerificationCache.defaultRacyWindow + 1)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 4, hits: 1, records: 1))
    }

    func testRacyGuardUsesTimeVerificationStartedNotFinished() throws {
        let pack = try install()
        let changed = try identity(wordsURL(pack)).changeTime
        let clock = TestClock()
        let cache = settledCache(clock)
        // Verification starts 1 s after the last inode change (inside the 2 s
        // window); any later reading of the clock -- as if hashing took 100 s --
        // would be outside it. The start time must win: nothing is recorded.
        clock.script([changed + 1])
        clock.set(changed + 100)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 1, hits: 0, records: 0))
        XCTAssertEqual(cache.count, 0)
        // Next verification starts at +100 s: settled, so recorded, then reused.
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 2, hits: 1, records: 1))

        // Same rule at the cache API: start time inside the window or before the
        // ctime (future-dated) is refused even though `now()` is far later.
        let direct = settledCache()
        let key = PayloadVerificationCache.PackKey(payloadPath: "/r/versions/a/payload", packID: "p", version: "1",
                                                   archiveSHA256: String(repeating: "a", count: 64))
        let file = PayloadVerificationCache.FileKey(relativePath: "f", byteCount: 1, sha256: String(repeating: "b", count: 64))
        let stamp = Identity(device: 1, inode: 2, size: 1, mode: 0o100600, modificationSeconds: 100,
                             modificationNanoseconds: 0, changeSeconds: 100, changeNanoseconds: 0)
        for start in [101.0, 102.0 - 0.000_001, 99.0] {
            direct.recordVerified(file, in: key, identity: stamp, startedAt: start)
            XCTAssertFalse(direct.isVerified(file, in: key, identity: stamp), "start \(start)")
        }
        direct.recordVerified(file, in: key, identity: stamp, startedAt: 102)
        XCTAssertTrue(direct.isVerified(file, in: key, identity: stamp))
    }

    func testRemoveAllResetsEntriesAndCounters() throws {
        let pack = try install()
        let cache = settledCache()
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 1, hits: 1, records: 1))
        cache.removeAll()
        XCTAssertEqual(cache.statistics, .init())
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(resolveOnce(cachedStore(cache)), .available(pack.revision))
        XCTAssertEqual(cache.statistics, .init(hashes: 1, hits: 0, records: 1))
    }

    func testReclaimingRevisionForgetsItsCacheEntries() throws {
        let first = try install()
        let cache = settledCache()
        let target = cachedStore(cache)
        XCTAssertEqual(resolveOnce(target), .available(first.revision))
        let second = try install(expected: first.revision)
        XCTAssertEqual(resolveOnce(target), .available(second.revision))
        XCTAssertEqual(cache.count, 2)
        try target.reclaimUnusedVersions() // first is inactive and unleased
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path.path))
        XCTAssertEqual(cache.count, 1, "only the reclaimed revision is forgotten")
        XCTAssertEqual(resolveOnce(target), .available(second.revision))
        XCTAssertEqual(cache.statistics.hits, 1)
        cache.forget(payloadPath: second.path.path)
        XCTAssertEqual(cache.count, 0)
    }

    func testVerificationCacheRequiresEveryKeyAndIdentityFieldToMatch() {
        let cache = settledCache()
        let pack = PayloadVerificationCache.PackKey(payloadPath: "/r/versions/a/payload", packID: "p", version: "1",
                                                    archiveSHA256: String(repeating: "a", count: 64))
        let file = PayloadVerificationCache.FileKey(relativePath: "d/f", byteCount: 10, sha256: String(repeating: "b", count: 64))
        let base = Identity(device: 1, inode: 2, size: 10, mode: 0o100600, modificationSeconds: 100,
                            modificationNanoseconds: 5, changeSeconds: 100, changeNanoseconds: 6)
        cache.recordVerified(file, in: pack, identity: base, startedAt: cache.now())
        XCTAssertTrue(cache.isVerified(file, in: pack, identity: base))
        func variant(device: Int64 = 1, inode: UInt64 = 2, size: Int64 = 10, mode: UInt32 = 0o100600,
                     ms: Int64 = 100, mns: Int64 = 5, cs: Int64 = 100, cns: Int64 = 6) -> Identity {
            Identity(device: device, inode: inode, size: size, mode: mode, modificationSeconds: ms,
                     modificationNanoseconds: mns, changeSeconds: cs, changeNanoseconds: cns)
        }
        for changed in [variant(device: 9), variant(inode: 9), variant(size: 11), variant(mode: 0o100400),
                        variant(ms: 101), variant(mns: 7), variant(cs: 101), variant(cns: 7)] {
            XCTAssertFalse(cache.isVerified(file, in: pack, identity: changed), "\(changed)")
        }
        let otherPacks = [
            PayloadVerificationCache.PackKey(payloadPath: "/r/versions/b/payload", packID: "p", version: "1", archiveSHA256: pack.archiveSHA256),
            PayloadVerificationCache.PackKey(payloadPath: pack.payloadPath, packID: "q", version: "1", archiveSHA256: pack.archiveSHA256),
            PayloadVerificationCache.PackKey(payloadPath: pack.payloadPath, packID: "p", version: "2", archiveSHA256: pack.archiveSHA256),
            PayloadVerificationCache.PackKey(payloadPath: pack.payloadPath, packID: "p", version: "1", archiveSHA256: String(repeating: "c", count: 64))
        ]
        for other in otherPacks { XCTAssertFalse(cache.isVerified(file, in: other, identity: base)) }
        for other in [PayloadVerificationCache.FileKey(relativePath: "d/g", byteCount: 10, sha256: file.sha256),
                      PayloadVerificationCache.FileKey(relativePath: "d/f", byteCount: 11, sha256: file.sha256),
                      PayloadVerificationCache.FileKey(relativePath: "d/f", byteCount: 10, sha256: String(repeating: "c", count: 64))] {
            XCTAssertFalse(cache.isVerified(other, in: pack, identity: base))
        }
        cache.beginHash(file, in: pack)
        XCTAssertFalse(cache.isVerified(file, in: pack, identity: base), "a started re-hash drops the old success")
        XCTAssertEqual(cache.count, 0)
    }

    func testMemoryReliefKeepsTheVerificationCacheAndReleasesEmojiLookupIndexes() throws {
        let cache = PayloadVerificationCache.shared
        let stamp = Identity(device: 1, inode: 2, size: 1, mode: 0o100600, modificationSeconds: 1,
                             modificationNanoseconds: 0, changeSeconds: 1, changeNanoseconds: 0)
        let file = PayloadVerificationCache.FileKey(relativePath: "f", byteCount: 1, sha256: String(repeating: "b", count: 64))
        let pack = PayloadVerificationCache.PackKey(payloadPath: "/memory-relief/versions/1/payload", packID: "p", version: "1",
                                                    archiveSHA256: String(repeating: "a", count: 64))
        defer { cache.forget(payloadPath: pack.payloadPath) }
        cache.recordVerified(file, in: pack, identity: stamp, startedAt: cache.now())
        XCTAssertTrue(cache.isVerified(file, in: pack, identity: stamp))
        let emoji = EmojiCatalog.shared.limited(to: .latest)
        let rocket = try XCTUnwrap(emoji.entry(text: "\u{1F680}"))
        XCTAssertTrue(emoji.hasLookupIndexes)

        KeyboardMemoryRelief.releaseRebuildableCaches()

        XCTAssertTrue(cache.isVerified(file, in: pack, identity: stamp),
                      "the next activation must not re-hash a whole pack after a memory warning")
        XCTAssertFalse(emoji.hasLookupIndexes)
        XCTAssertEqual(emoji.entries.count, EmojiCatalog.shared.limited(to: .latest).entries.count, "shown entries are kept")
        XCTAssertEqual(emoji.entry(text: "\u{1F680}"), rocket, "the next lookup rebuilds the same answer")
    }

    func testVerificationCacheIsBounded() {
        let cache = settledCache()
        let stamp = Identity(device: 1, inode: 2, size: 1, mode: 0o100600, modificationSeconds: 1,
                             modificationNanoseconds: 0, changeSeconds: 1, changeNanoseconds: 0)
        let file = PayloadVerificationCache.FileKey(relativePath: "f", byteCount: 1, sha256: String(repeating: "b", count: 64))
        let packs = (0..<(PayloadVerificationCache.maximumPacks + 2)).map {
            PayloadVerificationCache.PackKey(payloadPath: "/r/versions/\($0)/payload", packID: "p", version: "1",
                                            archiveSHA256: String(repeating: "a", count: 64))
        }
        for pack in packs { cache.recordVerified(file, in: pack, identity: stamp, startedAt: 1_000) }
        XCTAssertEqual(cache.count, PayloadVerificationCache.maximumPacks)
        XCTAssertFalse(cache.isVerified(file, in: packs[0], identity: stamp), "least recently used revision evicted")
        XCTAssertFalse(cache.isVerified(file, in: packs[1], identity: stamp))
        XCTAssertTrue(cache.isVerified(file, in: packs.last!, identity: stamp))
        cache.removeAll()
        let big = packs[0]
        for index in 0...LanguagePackDescriptor.maximumFileCount {
            cache.recordVerified(.init(relativePath: "f\(index)", byteCount: 1, sha256: file.sha256), in: big, identity: stamp, startedAt: 1_000)
        }
        XCTAssertLessThanOrEqual(cache.count, LanguagePackDescriptor.maximumFileCount)
        XCTAssertLessThanOrEqual(cache.count, PayloadVerificationCache.maximumEntries)
    }

    func testConcurrentResolvesAreSafeAndConverge() throws {
        let pack = try install()
        let cache = settledCache()
        let target = cachedStore(cache)
        let iterations = 32
        let lock = NSLock()
        var outcomes: [Outcome] = []
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let outcome = resolveOnce(target)
            lock.lock(); outcomes.append(outcome); lock.unlock()
        }
        XCTAssertEqual(outcomes, [Outcome](repeating: .available(pack.revision), count: iterations))
        let stats = cache.statistics
        XCTAssertGreaterThanOrEqual(stats.hashes, 1)
        XCTAssertEqual(stats.hashes + stats.hits, iterations, "one file: each resolve either hits or hashes once")
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(resolveOnce(target), .available(pack.revision))
        XCTAssertEqual(cache.statistics.hashes, stats.hashes, "converged: no further hashing")
        // Concurrent resolves after an in-place corruption never report the bad bytes as verified.
        usleep(50_000) // Test clock bypasses the racy guard; let coarse ctime clocks tick.
        try overwriteInPlace(wordsURL(pack), with: Data(repeating: 120, count: bytes.count))
        outcomes.removeAll()
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let outcome = resolveOnce(target)
            lock.lock(); outcomes.append(outcome); lock.unlock()
        }
        XCTAssertEqual(outcomes, [Outcome](repeating: .corrupt, count: iterations))
        XCTAssertEqual(cache.count, 0)
    }
}
