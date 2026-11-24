import Foundation
import XCTest
import CryptoKit
@testable import UniboardCore

@MainActor
final class ConversionRuntimeTests: XCTestCase {
    @MainActor final class Fixture {
        let root: URL
        let store: LanguagePackStore
        let settings: LanguageInputSettings
        let coordinator: KeyboardLanguageCoordinator
        let mode: LanguageInputMode
        var valid = true
        init(_ mode: LanguageInputMode) throws {
            self.mode = mode
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.root = root
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let payload = root.appendingPathComponent("payload")
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
            if mode == .japaneseRomaji {
                let mock = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CONVERSION_DICTIONARY_MOCK"]!)
                try FileManager.default.copyItem(at: mock, to: payload.appendingPathComponent("Dictionary"))
            } else {
                func resource(_ text: String, _ name: String) throws -> (MandarinDictionaryResource, URL) {
                    let data = Data(text.utf8), url = root.appendingPathComponent(name)
                    try data.write(to: url)
                    return (.init(filename: name, bytes: data.count, sha256: MandarinDictionaryCompiler.hash(data), downloadURL: URL(string: "https://fixture.example/" + name)!), url)
                }
                let rows = try resource("# fixture\n你好\tnǐ hǎo\t100\n你\tnǐ\t90\n", "words.tsv")
                let mapping = try resource("# fixture\n國\t国\n", "mapping.txt")
                let phrases = try resource("# fixture\n瞭解\t了解\n", "phrases.txt")
                let compatibility = try resource("# fixture\n豈\t豈\n", "compatibility.txt")
                _ = try MandarinDictionaryCompiler.compileVerified(sources: [.init(resource: rows.0, url: rows.1, header: ["# fixture"], expectedValidRows: 2, quarantined: [:])], mappingFiles: [mapping, phrases, compatibility], destinationURL: root.appendingPathComponent("Mandarin.sqlite"))
                try FileManager.default.copyItem(at: root.appendingPathComponent("Mandarin.sqlite"), to: payload.appendingPathComponent("Mandarin.sqlite"))
            }
            func files(at directory: URL, prefix: String = "") throws -> [LanguagePackDescriptor.File] {
                var output: [LanguagePackDescriptor.File] = []
                for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
                    let url = directory.appendingPathComponent(name)
                    var directoryKind: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directoryKind) else { continue }
                    if directoryKind.boolValue { output += try files(at: url, prefix: prefix + name + "/") }
                    else {
                        let data = try Data(contentsOf: url)
                        output.append(.init(path: prefix + name, byteCount: Int64(data.count), sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
                    }
                }
                return output
            }
            let files = try files(at: payload)
            let descriptor = LanguagePackDescriptor(packID: "runtime-fixture", version: "1", modeID: mode.rawValue, engineABI: mode.conversionEngineABI!, sourceURL: URL(string: "https://fixture.example/archive")!, allowedHosts: ["fixture.example"], archiveByteCount: 1, archiveSHA256: String(repeating: "a", count: 64), installedBytes: files.reduce(0) { $0 + $1.byteCount }, fileCount: files.count, files: files, licenseNotice: "Upstream AzooKey DictionaryMock under its repository license; Mandarin synthetic fixture.", sourceNotice: "Runtime regression fixture only.")
            store = LanguagePackStore(root: root.appendingPathComponent("packs"))
            _ = try store.install(manifestData: JSONEncoder().encode(descriptor), expectedRevision: nil) { stage in
                for child in try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil) {
                    try FileManager.default.copyItem(at: child, to: stage.appendingPathComponent(child.lastPathComponent))
                }
            }
            let settingsRoot = root
            settings = LanguageInputSettings(directory: { settingsRoot })
            XCTAssertTrue(settings.save(.init(enabledModes: [.direct, mode])))
            let packs = store.root
            coordinator = KeyboardLanguageCoordinator(root: { packs }, settings: settings, indexDirectory: { nil })
            coordinator.validateAnchor = { [weak self] in self?.valid == true }
        }
        func close() { coordinator.cancel(); _ = coordinator.select(.direct); try? FileManager.default.removeItem(at: root) }
    }
    func eventually(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<1_000 { if condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Timed out waiting for actual adapter"); throw CancellationError()
    }
    func activate(_ f: Fixture) async throws {
        await f.coordinator.refreshResources()
        XCTAssertTrue(f.coordinator.select(f.mode))
        try await eventually { !f.coordinator.isLoading }
        XCTAssertEqual(f.coordinator.status, .ready)
    }
    func ready(_ f: Fixture, _ raw: String) async throws {
        XCTAssertTrue(f.coordinator.append(raw))
        try await eventually { !f.coordinator.isConverting }
        XCTAssertEqual(f.coordinator.status, .ready)
    }
    func exercise(_ mode: LanguageInputMode, raw: String, expected: String) async throws {
        let f = try Fixture(mode); defer { f.close() }
        try await activate(f)
        try await ready(f, raw)
        XCTAssertTrue(f.coordinator.candidates.contains { $0.output == expected && $0.source == (mode == .japaneseRomaji ? .hiragana : .engine) }, "Actual dictionary must produce a word candidate")
        XCTAssertTrue(f.coordinator.candidates.contains { $0.output == raw && $0.source == .literal })
        let outputs = f.coordinator.candidates.map(\.output)
        XCTAssertEqual(Set(outputs).count, outputs.count)
        let first = try XCTUnwrap(outputs.first)
        let old = f.coordinator.token
        XCTAssertEqual(f.coordinator.commitDefault(token: old, space: true), [.commit(text: first + mode.conversionSpaceSuffix, remainingInput: "")])
        XCTAssertEqual(f.coordinator.commitDefault(token: old), [])
        try await ready(f, raw)
        XCTAssertEqual(f.coordinator.commitDefault(token: f.coordinator.token), [.commit(text: first, remainingInput: "")], "Return commits without inserting a newline")
        try await ready(f, raw)
        var writes = f.coordinator.commitDefault(token: f.coordinator.token)
        writes.append(.commit(text: "!", remainingInput: ""))
        XCTAssertEqual(writes, [.commit(text: first, remainingInput: ""), .commit(text: "!", remainingInput: "")])
        try await ready(f, raw)
        XCTAssertTrue(f.coordinator.backspace())
        try await eventually { !f.coordinator.isConverting }
        XCTAssertEqual(f.coordinator.rawInput, String(raw.dropLast()))
        f.coordinator.cancel()
        XCTAssertTrue(f.coordinator.select(.direct))
        XCTAssertTrue(f.coordinator.candidates.isEmpty)
    }
    func testJapaneseReleaseDictionaryCandidatesAndBoundaries() async throws { try await exercise(.japaneseRomaji, raw: "shikai", expected: "しかい") }
    func testMandarinDictionaryCandidatesAndBoundaries() async throws { try await exercise(.mandarinPinyin, raw: "nihao", expected: "你好") }
    func race(_ mode: LanguageInputMode, _ raw: String) async throws {
        let f = try Fixture(mode); defer { f.close() }
        try await activate(f)
        XCTAssertTrue(f.coordinator.append(raw))
        let pending = f.coordinator.token
        XCTAssertEqual(f.coordinator.commitDefault(token: pending), [])
        XCTAssertTrue(f.coordinator.backspace())
        try await eventually { !f.coordinator.isConverting }
        XCTAssertNotEqual(pending, f.coordinator.token)
        XCTAssertEqual(f.coordinator.commitDefault(token: pending), [])
        f.coordinator.cancel()
        XCTAssertTrue(f.coordinator.append(raw))
        f.coordinator.cancel()
        XCTAssertTrue(f.coordinator.select(.direct))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(f.coordinator.mode, .direct)
        XCTAssertTrue(f.coordinator.candidates.isEmpty)
    }
    func testJapanesePendingNewerCompositionAndSwitch() async throws { try await race(.japaneseRomaji, "shikai") }
    func testMandarinPendingNewerCompositionAndSwitch() async throws { try await race(.mandarinPinyin, "nihao") }
    #if ASYNC_CONVERSION
    func orderedBoundaries(_ mode: LanguageInputMode, raw: String) async throws {
        let f = try Fixture(mode); defer { f.close() }
        try await activate(f)
        try await ready(f, raw)
        let word = try XCTUnwrap(f.coordinator.candidates.first { $0.source != .literal }?.output)
        f.coordinator.cancel()
        var events: [String] = []
        func commit(_ suffix: String, space: Bool = false) {
            let effects = f.coordinator.commitDefault(token: f.coordinator.token, space: space)
            XCTAssertEqual(effects.count, 1)
            if case .commit(let text, _) = effects.first { events.append(text + suffix) }
        }
        XCTAssertTrue(f.coordinator.append(raw))
        XCTAssertTrue(f.coordinator.isConverting)
        XCTAssertTrue(f.coordinator.deferBoundary(token: f.coordinator.token) { commit("!", space: true) })
        XCTAssertTrue(f.coordinator.deferInput { events.append("next-input"); _ = f.coordinator.append(raw) })
        XCTAssertTrue(f.coordinator.deferInput {
            XCTAssertTrue(f.coordinator.deferBoundary(token: f.coordinator.token) { commit("") })
        })
        XCTAssertTrue(f.coordinator.deferInput { events.append("return-after-commit") })
        XCTAssertTrue(events.isEmpty, "Boundary never blocks or writes before the conversion result")
        try await eventually { events.count == 4 && !f.coordinator.isConverting }
        XCTAssertEqual(events, [word + mode.conversionSpaceSuffix + "!", "next-input", word, "return-after-commit"])
        XCTAssertFalse(f.coordinator.hasComposition)

        // Every queued key runs, even when an earlier key starts new work.
        // Backspace must edit that new buffer before Return waits on its result.
        events.removeAll()
        XCTAssertTrue(f.coordinator.append(raw))
        XCTAssertTrue(f.coordinator.deferBoundary(token: f.coordinator.token) { commit("") })
        for scalar in raw.unicodeScalars {
            XCTAssertTrue(f.coordinator.deferInput { _ = f.coordinator.append(String(scalar)) })
        }
        XCTAssertTrue(f.coordinator.deferInput { _ = f.coordinator.append("a") })
        XCTAssertTrue(f.coordinator.deferInput { XCTAssertTrue(f.coordinator.backspace()) })
        XCTAssertTrue(f.coordinator.deferInput {
            XCTAssertTrue(f.coordinator.deferBoundary(token: f.coordinator.token) { commit("") })
        })
        try await eventually { events.count == 2 && !f.coordinator.isConverting }
        XCTAssertEqual(events, [word, word])
        XCTAssertFalse(f.coordinator.hasComposition)
    }
    func testJapanesePendingBoundaryFIFOIncludingNewWordAndReturn() async throws { try await orderedBoundaries(.japaneseRomaji, raw: "shikai") }
    func testMandarinPendingBoundaryFIFOIncludingNewWordAndReturn() async throws { try await orderedBoundaries(.mandarinPinyin, raw: "nihao") }

    func revokedBoundary(_ mode: LanguageInputMode, raw: String) async throws {
        let f = try Fixture(mode); defer { f.close() }
        try await activate(f)
        for reset in 0..<3 {
            XCTAssertTrue(f.coordinator.append(raw))
            var writes = 0
            XCTAssertTrue(f.coordinator.deferBoundary(token: f.coordinator.token) { writes += 1 })
            XCTAssertTrue(f.coordinator.deferInput { writes += 1 })
            if reset == 0 { f.coordinator.cancel() }
            else if reset == 1 { f.coordinator.documentChanged() }
            else { f.valid = false }
            try await eventually { !f.coordinator.isConverting }
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(writes, 0, "Reset/anchor revocation must discard the entire old boundary queue")
            f.valid = true
            f.coordinator.cancel()
        }
        // A reset during the first action discards later session events too.
        var writes = 0
        XCTAssertTrue(f.coordinator.append(raw))
        XCTAssertTrue(f.coordinator.deferBoundary(token: f.coordinator.token) {
            writes += 1
            f.coordinator.documentChanged()
        })
        XCTAssertTrue(f.coordinator.deferInput { writes += 1 })
        try await eventually { !f.coordinator.isConverting }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(f.coordinator.select(.direct))
    }
    func testJapanesePendingBoundaryCancelDocumentAndAnchorRevocation() async throws { try await revokedBoundary(.japaneseRomaji, raw: "shikai") }
    func testMandarinPendingBoundaryCancelDocumentAndAnchorRevocation() async throws { try await revokedBoundary(.mandarinPinyin, raw: "nihao") }

    func retainedCandidates(_ mode: LanguageInputMode, raw: String) async throws {
        let f = try Fixture(mode); defer { f.close() }
        try await activate(f)
        try await ready(f, raw)
        let old = try XCTUnwrap(f.coordinator.displayResult)
        XCTAssertTrue(f.coordinator.backspace())
        XCTAssertEqual(f.coordinator.displayResult, old, "Candidate display stays stable during replacement work")
        XCTAssertEqual(f.coordinator.choose(id: old.candidates[0].id, token: old.token), [], "Retained display grants no commit authority")
        try await eventually { !f.coordinator.isConverting }
        XCTAssertNotEqual(f.coordinator.displayResult?.token, old.token)
        f.coordinator.cancel()
        XCTAssertNil(f.coordinator.displayResult, "Explicit cancellation clears retained candidates")
    }
    func testJapanesePreservesDisplayWithoutStaleCandidateAuthority() async throws { try await retainedCandidates(.japaneseRomaji, raw: "shikai") }
    func testMandarinPreservesDisplayWithoutStaleCandidateAuthority() async throws { try await retainedCandidates(.mandarinPinyin, raw: "nihao") }
    #endif

}
