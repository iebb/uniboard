import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

@MainActor
final class SharedConfigurationLocationTests: XCTestCase {
    private struct Interrupted: Error {}
    private typealias Report = SharedConfigurationLocation.RecoveryReport
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
        super.tearDown()
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SharedConfiguration-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cleanup.append { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeDefaults() -> UserDefaults {
        let name = "Uniboard.SharedConfiguration.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        cleanup.append { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func put(_ data: Data, _ name: String, in directory: URL) throws {
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func bytes(_ url: URL) -> Data? { FileManager.default.contents(atPath: url.path) }

    private func names(_ directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    private func folder(_ root: URL) -> URL { root.appendingPathComponent(SharedConfigurationLocation.folderName, isDirectory: true) }

    private func generation(_ root: URL, _ number: Int) -> URL {
        folder(root).appendingPathComponent(SharedConfigurationLocation.directoryName(number), isDirectory: true)
    }

    private let presentation = AppPresentationSettings.encode(.init(integers: ["tileColumns": 4]))

    /// A lock held through a second open file description, like another process.
    private func holdLock(_ root: URL) -> Int32 {
        let descriptor = open(root.appendingPathComponent(FavoriteSync.lockFilename).path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        return descriptor
    }

    private func migrated(_ root: URL) throws -> (SharedConfigurationLocation, ConfigurationPointer) {
        let location = SharedConfigurationLocation(root: { root })
        guard case let .applied(pointer) = location.migrateIfNeeded(presentation: presentation) else {
            XCTFail("Migration didn't apply"); throw Interrupted()
        }
        return (location, pointer)
    }

    private func payloads(favorites: [String] = ["Ψ", "e\u{301}"], mode: AutoCapitalizationMode = .words,
                          app: AppPresentationSettings.Values = .init(integers: ["blockGridDensity": 8])) throws -> [String: Data] {
        let edition = UnicodeEditionSettings.Snapshot(edition: .latest, useUnicodeFonts: false, showsCollapseKey: true)
        return [
            UnicodeEditionSettings.filename: try XCTUnwrap(UnicodeEditionSettings.encode(edition)),
            KeyboardKeySettings.filename: try XCTUnwrap(KeyboardKeySettings.encode(.defaults)),
            SymbolPageSettings.filename: try XCTUnwrap(SymbolPageSettings.encode(.init(pages: [], starPageID: SymbolBoardStore.favoritesID))),
            FavoriteSync.filename: try XCTUnwrap(FavoriteSync.replacementPayload(favorites, id: "import-1")),
            FontRuleStore.filename: try XCTUnwrap(FontRuleStore.encode([rule("one", .codePoint(0x41))])),
            ImageColorSettings.filename: try XCTUnwrap(ImageColorSettings.encode(.init(value: .init(preset: "custom", customText: "#FF3B30",
                                                                                         customBackground: "transparent"), revision: "colors-1"))),
            AutoCapitalizationSetting.filename: AutoCapitalizationSetting.encode(mode),
            AppPresentationSettings.filename: AppPresentationSettings.encode(app),
        ]
    }

    private func face(_ name: String = "Junicode") -> FontFaceReference {
        FontFaceReference(source: .imported, family: name, style: "Regular", postScriptName: name + "-Regular",
                          identity: .file(sha256: String(repeating: "ab", count: 32), faceIndex: 0, variations: [:]))
    }

    private func rule(_ id: String, _ selector: FontRuleSelector) -> FontRule { FontRule(id: id, selector: selector, face: face()) }

    // MARK: Names and pointer

    func testGenerationNamesDigestsAndRevisions() {
        XCTAssertEqual(SharedConfigurationLocation.directoryName(1), "g-000001")
        XCTAssertEqual(SharedConfigurationLocation.generationNumber("g-000123"), 123)
        for name in ["g-000000", "g-00001", "g-0000001", "x-000001", "g-00000a", "g-00000١"] {
            XCTAssertNil(SharedConfigurationLocation.generationNumber(name), name)
        }
        XCTAssertTrue(SharedConfigurationLocation.isDigest(String(repeating: "0a", count: 32)))
        XCTAssertFalse(SharedConfigurationLocation.isDigest(String(repeating: "0A", count: 32)))
        XCTAssertFalse(SharedConfigurationLocation.isDigest(String(repeating: "0", count: 63)))
        XCTAssertTrue(SharedConfigurationLocation.isRevision("Az-09"))
        for text in ["", "a_b", "é", String(repeating: "a", count: 65)] { XCTAssertFalse(SharedConfigurationLocation.isRevision(text), text) }
        XCTAssertEqual(SharedConfigurationLocation.snapshotFiles, SharedConfigurationLocation.snapshotFiles.sorted())
        XCTAssertEqual(Set(SharedConfigurationLocation.snapshotFiles), Set(ConfigurationSnapshotValidation.validators.keys))
        XCTAssertEqual(SharedConfigurationLocation.fileLimits[FontRuleStore.filename], 1024 * 1024)
    }

    func testPointerStatesRefuseNewerAndDamagedPointers() throws {
        let digest = String(repeating: "c", count: 64)
        let valid = ConfigurationPointer(generation: 3, directory: "g-000003", previous: "g-000002", importFingerprint: digest, importedAt: 1_800_000_000)
        let encoded = try SharedConfigurationLocation.encoder.encode(valid)
        XCTAssertEqual(SharedConfigurationLocation.pointerState(encoded), .valid(valid))
        XCTAssertEqual(SharedConfigurationLocation.pointerState(Data(#"{"schemaVersion":2,"anything":true}"#.utf8)), .unsupported)
        XCTAssertEqual(SharedConfigurationLocation.pointerState(Data("nope".utf8)), .invalid)
        XCTAssertEqual(SharedConfigurationLocation.pointerState(Data(#"{"schemaVersion":1}"#.utf8)), .invalid)
        XCTAssertEqual(SharedConfigurationLocation.pointerState(encoded + Data(repeating: 32, count: 4096)), .invalid)
        for pointer in [
            ConfigurationPointer(generation: 3, directory: "g-000002"),
            ConfigurationPointer(generation: 3, directory: "g-000003", previous: "g-000003"),
            ConfigurationPointer(generation: 3, directory: "g-000003", previous: "previous"),
            ConfigurationPointer(generation: 3, directory: "g-000003", importFingerprint: "abc"),
        ] {
            XCTAssertFalse(pointer.isValid)
            XCTAssertEqual(SharedConfigurationLocation.pointerState(try SharedConfigurationLocation.encoder.encode(pointer)), .invalid)
        }
        // JSON can't carry an infinite time; a pointer built with one is still refused.
        XCTAssertFalse(ConfigurationPointer(generation: 3, directory: "g-000003", importedAt: .infinity).isValid)
        XCTAssertTrue(ConfigurationPointer(generation: 1, directory: "g-000001").isValid)
        XCTAssertNil(ConfigurationUndoStatus(fingerprint: digest, hasNewerEdits: false).importedAt)
        XCTAssertNil(ConfigurationUndoStatus(fingerprint: digest, hasNewerEdits: false).source)
    }

    /// The change source is optional: a pointer written before it existed,
    /// or naming a source this build doesn't know, stays valid.
    func testPointerChangeSourceIsOptionalAndLenient() throws {
        let digest = String(repeating: "c", count: 64)
        let older = Data(#"{"directory":"g-000003","generation":3,"importFingerprint":"\#(digest)","previous":"g-000002","schemaVersion":1}"#.utf8)
        guard case let .valid(pointer) = SharedConfigurationLocation.pointerState(older) else { return XCTFail("An older pointer stays valid") }
        XCTAssertNil(pointer.changeSource)
        let newer = ConfigurationPointer(generation: 3, directory: "g-000003", previous: "g-000002", importFingerprint: digest, changeSource: "sync")
        XCTAssertTrue(newer.isValid)
        XCTAssertEqual(SharedConfigurationLocation.pointerState(try SharedConfigurationLocation.encoder.encode(newer)), .valid(newer))
        XCTAssertEqual(ConfigurationChangeSource(rawValue: "import"), .importFile)
        XCTAssertEqual(ConfigurationChangeSource(rawValue: "editor"), .editor)
        XCTAssertNil(ConfigurationChangeSource(rawValue: "sync"))
    }

    func testAnEditorApplyRecordsItsSourceAndUndoesLikeAnImport() throws {
        let root = try makeRoot()
        var (location, _) = try migrated(root)
        location.now = { Date(timeIntervalSince1970: 1_800_000_000) }
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        let files = try payloads()
        guard case let .applied(pointer) = location.apply(files, expecting: expected, currentPresentation: presentation, source: .editor)
        else { return XCTFail() }
        XCTAssertEqual(pointer.changeSource, "editor")
        XCTAssertEqual(pointer.previous, "g-000001", "The same backup an import keeps")
        let applied = try XCTUnwrap(files[AppPresentationSettings.filename])
        let status = try XCTUnwrap(location.undoStatus(presentation: applied))
        XCTAssertEqual(status.source, .editor)
        XCTAssertEqual(status.importedAt, Date(timeIntervalSince1970: 1_800_000_000))
        guard case let .applied(restored) = location.undoLastImport(expecting: status.fingerprint, currentPresentation: applied) else { return XCTFail() }
        XCTAssertNil(restored.changeSource, "Undo isn't itself undoable")
        XCTAssertNil(location.undoStatus(presentation: presentation))
    }

    func testReadingWithoutAContainerOrPointerFallsBackToTheRoot() throws {
        XCTAssertEqual(SharedConfigurationLocation(root: { nil }).readPointer(), .missing)
        XCTAssertNil(SharedConfigurationLocation(root: { nil }).currentDirectory())
        XCTAssertEqual(SharedConfigurationLocation(root: { URL(string: "https://example.com")! }).readPointer(), .missing)
        let root = try makeRoot()
        let location = SharedConfigurationLocation(root: { root })
        XCTAssertEqual(location.readPointer(), .missing)
        XCTAssertEqual(location.currentDirectory(), root)
        XCTAssertNil(location.currentGeneration())
        XCTAssertNil(location.currentFingerprint(presentation: presentation))
        XCTAssertNil(location.lastGoodGeneration())
        XCTAssertNil(location.undoStatus(presentation: presentation))
        try FileManager.default.createDirectory(at: folder(root).appendingPathComponent(SharedConfigurationLocation.pointerFilename),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(location.readPointer(), .invalid, "A pointer that isn't a regular file is damaged, not missing")
        XCTAssertEqual(location.currentDirectory(), root)
        _ = SharedConfigurationLocation.shared.currentDirectory()
    }

    // MARK: Migration

    func testMigrationCopiesRootFilesByteForByteAndLeavesThemUntouched() throws {
        let root = try makeRoot()
        let malformedEdition = Data("{\"schemaVersion\": 9, broken".utf8)
        let keys = Data("{ \"schemaVersion\" : 3, \"overrides\" : [] }\n".utf8)
        let pages = try XCTUnwrap(SymbolPageSettings.encode(.init(pages: [], starPageID: "custom-page")))
        let favorites = Data(#"{"version":1,"texts":["Ψ","e\u0301","👩‍💻"]}"#.utf8)
        let originals = [UnicodeEditionSettings.filename: malformedEdition, KeyboardKeySettings.filename: keys,
                         SymbolPageSettings.filename: pages, FavoriteSync.filename: favorites, "unrelated.txt": Data("keep".utf8)]
        for (name, data) in originals { try put(data, name, in: root) }
        let dates = try originals.keys.reduce(into: [String: Date]()) {
            $0[$1] = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent($1).path)[.modificationDate] as? Date
        }
        let rootEdition = UnicodeEditionSettings(containerURL: { root }).loadSnapshot()
        let rootKeys = KeyboardKeySettings(containerURL: { root }).loadForEditing()
        let rootPages = SymbolPageSettings(containerURL: { root }).load()
        let rootFavorites = try FavoriteSync(container: { root }).synchronize(base: [], local: [], canWrite: false).texts

        let (location, pointer) = try migrated(root)
        XCTAssertEqual(pointer, ConfigurationPointer(generation: 1, directory: "g-000001"))
        XCTAssertEqual(location.readPointer(), .valid(pointer))
        XCTAssertEqual(location.currentGeneration(), 1)
        let current = generation(root, 1)
        XCTAssertEqual(location.currentDirectory()?.standardizedFileURL, current.standardizedFileURL)
        for (name, data) in originals where name != "unrelated.txt" { XCTAssertEqual(bytes(current.appendingPathComponent(name)), data, name) }
        XCTAssertEqual(bytes(current.appendingPathComponent(AppPresentationSettings.filename)), presentation)
        XCTAssertEqual(names(current), Set(originals.keys).subtracting(["unrelated.txt"]).union([AppPresentationSettings.filename,
                                                                                                   SharedConfigurationLocation.manifestFilename]),
                       "Missing files stay missing: no rules, colors or capitalization file is invented")
        for (name, data) in originals {
            XCTAssertEqual(bytes(root.appendingPathComponent(name)), data, name)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)[.modificationDate] as? Date, dates[name])
        }
        XCTAssertEqual(names(root), Set(originals.keys).union([SharedConfigurationLocation.folderName, FavoriteSync.lockFilename]))

        let edition = UnicodeEditionSettings(containerURL: location.currentDirectory)
        XCTAssertEqual(edition.loadSnapshot(), rootEdition)
        XCTAssertEqual(KeyboardKeySettings(containerURL: location.currentDirectory).loadForEditing(), rootKeys)
        XCTAssertEqual(SymbolPageSettings(containerURL: location.currentDirectory).load(), rootPages)
        XCTAssertEqual(try FavoriteSync(location: location).synchronize(base: [], local: [], canWrite: false).texts, rootFavorites)
        XCTAssertEqual(location.migrateIfNeeded(presentation: Data()), .alreadyMigrated)
        XCTAssertEqual(location.lastGoodGeneration(), "g-000001")

        // Later edits go to the generation; the root keeps what an older build knows.
        XCTAssertTrue(edition.save(.init(edition: .latest)))
        XCTAssertEqual(bytes(root.appendingPathComponent(UnicodeEditionSettings.filename)), malformedEdition)
        XCTAssertNotEqual(bytes(current.appendingPathComponent(UnicodeEditionSettings.filename)), malformedEdition)
    }

    func testMigrationKeepsUnreadableAndOversizedRootFilesUnusable() throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(FavoriteSync.filename), withIntermediateDirectories: false)
        try put(Data(repeating: 0x20, count: 900), UnicodeEditionSettings.filename, in: root)
        XCTAssertThrowsError(try FavoriteSync(container: { root }).synchronize(base: [], local: [], canWrite: false))
        let (location, _) = try migrated(root)
        let current = generation(root, 1)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent(FavoriteSync.filename).path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertThrowsError(try FavoriteSync(location: location).synchronize(base: [], local: [], canWrite: false))
        XCTAssertEqual(bytes(current.appendingPathComponent(UnicodeEditionSettings.filename))?.count, UnicodeEditionSettings.maximumPayloadBytes + 1,
                       "Only the reader's own bound is copied, which is still oversized")
        XCTAssertEqual(UnicodeEditionSettings(containerURL: location.currentDirectory).loadSnapshot(), .init(edition: .latest))
        XCTAssertEqual(location.lastGoodGeneration(), "g-000001")
    }

    func testABusyOrUnavailableLockChangesNothing() throws {
        let root = try makeRoot()
        try put(Data("x".utf8), FavoriteSync.filename, in: root)
        let location = SharedConfigurationLocation(root: { root })
        let descriptor = holdLock(root)
        XCTAssertEqual(location.migrateIfNeeded(presentation: presentation), .busy)
        XCTAssertNil(location.recover())
        XCTAssertThrowsError(try location.withWriterLock { () }) { XCTAssertEqual($0 as? SharedConfigurationLocation.Failure, .busy) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder(root).path))
        flock(descriptor, LOCK_UN)
        close(descriptor)
        XCTAssertEqual(try location.withWriterLock { 7 }, 7)

        XCTAssertEqual(SharedConfigurationLocation(root: { nil }).migrateIfNeeded(presentation: presentation), .unavailable)
        let directoryLock = try makeRoot()
        try FileManager.default.createDirectory(at: directoryLock.appendingPathComponent(FavoriteSync.lockFilename), withIntermediateDirectories: false)
        XCTAssertEqual(SharedConfigurationLocation(root: { directoryLock }).migrateIfNeeded(presentation: presentation), .unavailable)
        let fifoLock = try makeRoot()
        XCTAssertEqual(mkfifo(fifoLock.appendingPathComponent(FavoriteSync.lockFilename).path, S_IRUSR | S_IWUSR), 0)
        XCTAssertEqual(SharedConfigurationLocation(root: { fifoLock }).migrateIfNeeded(presentation: presentation), .unavailable)
    }

    // MARK: Apply and undo

    func testApplyPublishesANewGenerationAndUndoRestoresTheBackup() throws {
        let root = try makeRoot()
        let favorites = Data(#"{"version":1,"texts":["a"]}"#.utf8)
        try put(favorites, FavoriteSync.filename, in: root)
        var (location, _) = try migrated(root)
        location.now = { Date(timeIntervalSince1970: 1_800_000_000) }
        let colors = ImageColorSettings(location: location)
        let before = try colors.save(.init(preset: "whiteOnBlack", customText: "#000000", customBackground: "#ffffff"))
        let livePresentation = AppPresentationSettings.encode(.init(integers: ["tileColumns": 6], booleans: ["exploreDescending": true]))
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: livePresentation))
        XCTAssertNotEqual(location.currentFingerprint(presentation: presentation), expected, "App presentation defaults are part of the fingerprint")
        let files = try payloads()

        guard case let .applied(pointer) = location.apply(files, expecting: expected, currentPresentation: livePresentation) else { return XCTFail() }
        XCTAssertEqual(pointer.generation, 2)
        XCTAssertEqual(pointer.previous, "g-000001")
        XCTAssertEqual(location.currentGeneration(), 2)
        XCTAssertEqual(bytes(generation(root, 1).appendingPathComponent(AppPresentationSettings.filename)), livePresentation,
                       "The backup holds the app defaults that were live before the import")
        for (name, data) in files { XCTAssertEqual(bytes(generation(root, 2).appendingPathComponent(name)), data, name) }
        let imported = try XCTUnwrap(files[AppPresentationSettings.filename])
        XCTAssertEqual(pointer.importFingerprint, location.currentFingerprint(presentation: imported))
        XCTAssertEqual(pointer.importedAt, 1_800_000_000)
        XCTAssertEqual(pointer.changeSource, "import", "An apply records an import unless told otherwise")
        XCTAssertEqual(location.undoStatus(presentation: imported), ConfigurationUndoStatus(fingerprint: pointer.importFingerprint!, hasNewerEdits: false,
                                                                                           importedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                                                                           source: .importFile))
        XCTAssertEqual(FontRuleStore(directory: location.currentDirectory).load(), [rule("one", .codePoint(0x41))])
        XCTAssertEqual(AutoCapitalizationSetting(directory: location.currentDirectory).load(), .words)

        XCTAssertEqual(location.undoStatus(presentation: presentation)?.hasNewerEdits, true, "A changed app default is a newer edit")
        XCTAssertTrue(AutoCapitalizationSetting(directory: location.currentDirectory).save(.off))
        let status = try XCTUnwrap(location.undoStatus(presentation: imported))
        XCTAssertTrue(status.hasNewerEdits)
        XCTAssertEqual(location.undoLastImport(expecting: pointer.importFingerprint!, currentPresentation: imported), .conflict)
        XCTAssertEqual(location.currentGeneration(), 2)

        guard case let .applied(restored) = location.undoLastImport(expecting: status.fingerprint, currentPresentation: imported) else { return XCTFail() }
        XCTAssertEqual(restored, ConfigurationPointer(generation: 3, directory: "g-000003"))
        let current = generation(root, 3)
        XCTAssertEqual(bytes(current.appendingPathComponent(AppPresentationSettings.filename)), livePresentation)
        XCTAssertNil(bytes(current.appendingPathComponent(AutoCapitalizationSetting.filename)))
        let restoredFavorites = try XCTUnwrap(FavoriteSync.decode(try XCTUnwrap(bytes(current.appendingPathComponent(FavoriteSync.filename)))))
        XCTAssertEqual(restoredFavorites.texts, ["a"])
        XCTAssertNotNil(restoredFavorites.replacementID, "Both processes adopt the restored list wholesale")
        let restoredColors = try XCTUnwrap(colors.load())
        XCTAssertEqual(restoredColors.value, before.value)
        XCTAssertNotEqual(restoredColors.revision, before.revision)
        XCTAssertNil(location.undoStatus(presentation: livePresentation))
        XCTAssertEqual(location.undoLastImport(expecting: status.fingerprint, currentPresentation: livePresentation), .unavailable)

        XCTAssertEqual(location.recover(), Report(repairedPointer: false, removed: ["g-000001", "g-000002"]))
        XCTAssertEqual(names(folder(root)), [SharedConfigurationLocation.pointerFilename, "g-000003"])
    }

    func testUndoKeepsMigratedUnreadableFilesUnreadable() throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(FavoriteSync.filename), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(ImageColorSettings.filename), withIntermediateDirectories: false)
        let (location, _) = try migrated(root)
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case let .applied(pointer) = location.apply(try payloads(), expecting: expected, currentPresentation: presentation),
              let fingerprint = pointer.importFingerprint else { return XCTFail() }
        let imported = try XCTUnwrap(try payloads()[AppPresentationSettings.filename])
        XCTAssertEqual(location.undoLastImport(expecting: fingerprint, currentPresentation: imported), .applied(.init(generation: 3, directory: "g-000003")))
        for name in [FavoriteSync.filename, ImageColorSettings.filename] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: generation(root, 3).appendingPathComponent(name).path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue, name)
        }
    }

    func testUndoWithoutBackupFavoritesCarriesTheCurrentFavoritesOver() throws {
        let root = try makeRoot()
        let (location, _) = try migrated(root)
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case let .applied(pointer) = location.apply(try payloads(), expecting: expected, currentPresentation: presentation) else { return XCTFail() }
        let imported = try XCTUnwrap(try payloads()[AppPresentationSettings.filename])
        let importedFavorites = try XCTUnwrap(bytes(generation(root, 2).appendingPathComponent(FavoriteSync.filename)))
        XCTAssertEqual(location.undoLastImport(expecting: pointer.importFingerprint!, currentPresentation: imported),
                       .applied(.init(generation: 3, directory: "g-000003")))
        // The backup never had a favorites file: they lived only in each process. Undo
        // must not restore that as an empty list; the current list stays, byte for byte.
        XCTAssertEqual(bytes(generation(root, 3).appendingPathComponent(FavoriteSync.filename)), importedFavorites)
        XCTAssertEqual(FavoriteSync.decode(importedFavorites)?.texts, ["Ψ", "e\u{301}"])
        XCTAssertNil(bytes(generation(root, 3).appendingPathComponent(ImageColorSettings.filename)))
    }

    func testUndoWithoutAnyFavoritesFileLeavesFavoritesMissing() throws {
        let root = try makeRoot()
        let (location, _) = try migrated(root)
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        var files = try payloads()
        guard case let .applied(pointer) = location.apply(files, expecting: expected, currentPresentation: presentation) else { return XCTFail() }
        // An edit after the import removed the current favorites file too.
        try FileManager.default.removeItem(at: generation(root, 2).appendingPathComponent(FavoriteSync.filename))
        files[FavoriteSync.filename] = nil
        let imported = try XCTUnwrap(try payloads()[AppPresentationSettings.filename])
        let status = try XCTUnwrap(location.undoStatus(presentation: imported))
        XCTAssertTrue(status.hasNewerEdits)
        XCTAssertNotNil(pointer.importedAt)
        XCTAssertEqual(location.undoLastImport(expecting: status.fingerprint, currentPresentation: imported),
                       .applied(.init(generation: 3, directory: "g-000003")))
        XCTAssertNil(bytes(generation(root, 3).appendingPathComponent(FavoriteSync.filename)), "Missing stays missing: never an empty list")
    }

    func testApplyRefusesInvalidStaleOrUnmigratedConfigurations() throws {
        let root = try makeRoot()
        let location = SharedConfigurationLocation(root: { root })
        let files = try payloads()
        let digest = String(repeating: "0", count: 64)
        XCTAssertEqual(location.apply(files, expecting: digest, currentPresentation: presentation), .unavailable)
        var missing = files
        missing[FontRuleStore.filename] = nil
        XCTAssertEqual(location.apply(missing, expecting: digest, currentPresentation: presentation), .invalidPayload)
        var extra = files
        extra["other.json"] = Data()
        XCTAssertEqual(location.apply(extra, expecting: digest, currentPresentation: presentation), .invalidPayload)
        var merged = files
        merged[FavoriteSync.filename] = Data(#"{"version":1,"texts":["a"]}"#.utf8)
        XCTAssertEqual(location.apply(merged, expecting: digest, currentPresentation: presentation), .invalidPayload,
                       "An import's favorites always replace the list")
        for name in SharedConfigurationLocation.snapshotFiles {
            var broken = files
            broken[name] = Data("{}".utf8)
            XCTAssertEqual(location.apply(broken, expecting: digest, currentPresentation: presentation), .invalidPayload, name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder(root).path))

        let (migratedLocation, _) = try migrated(root)
        XCTAssertEqual(migratedLocation.apply(files, expecting: digest, currentPresentation: presentation), .conflict)
        let expected = try XCTUnwrap(migratedLocation.currentFingerprint(presentation: presentation))
        let presentationFile = generation(root, 1).appendingPathComponent(AppPresentationSettings.filename)
        try FileManager.default.removeItem(at: presentationFile)
        try FileManager.default.createSymbolicLink(at: presentationFile, withDestinationURL: root.appendingPathComponent("elsewhere"))
        XCTAssertEqual(migratedLocation.apply(files, expecting: expected, currentPresentation: presentation), .failed(.stage))
        XCTAssertEqual(migratedLocation.currentGeneration(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("elsewhere").path))
    }

    func testAnInterruptionAtEveryStepKeepsTheLastGoodGeneration() throws {
        for step in [ConfigurationStep.stage, .verify, .publish, .pointer] {
            let root = try makeRoot()
            var (location, before): (SharedConfigurationLocation, ConfigurationPointer) = try migrated(root)
            let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
            location.fault = { if $0 == step { throw Interrupted() } }
            XCTAssertEqual(location.apply(try payloads(), expecting: expected, currentPresentation: presentation), .failed(step))
            XCTAssertEqual(location.readPointer(), .valid(before), step.rawValue)
            XCTAssertEqual(names(folder(root)), [SharedConfigurationLocation.pointerFilename, "g-000001"], step.rawValue)
            XCTAssertEqual(location.currentFingerprint(presentation: presentation), expected)

            let fresh = try makeRoot()
            try put(Data("edition".utf8), UnicodeEditionSettings.filename, in: fresh)
            var first = SharedConfigurationLocation(root: { fresh })
            first.fault = { if $0 == step { throw Interrupted() } }
            XCTAssertEqual(first.migrateIfNeeded(presentation: presentation), .failed(step))
            XCTAssertEqual(first.readPointer(), .missing)
            XCTAssertEqual(first.currentDirectory(), fresh)
            XCTAssertEqual(names(folder(fresh)), [])
            XCTAssertEqual(bytes(fresh.appendingPathComponent(UnicodeEditionSettings.filename)), Data("edition".utf8))
            first.fault = { _ in }
            XCTAssertEqual(first.migrateIfNeeded(presentation: presentation), .applied(.init(generation: 1, directory: "g-000001")))
        }
    }

    func testApplyReplacesAnOrphanedGenerationDirectory() throws {
        let root = try makeRoot()
        let (location, _) = try migrated(root)
        try FileManager.default.createDirectory(at: generation(root, 2), withIntermediateDirectories: false)
        try put(Data("stale".utf8), "stale.json", in: generation(root, 2))
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case .applied = location.apply(try payloads(), expecting: expected, currentPresentation: presentation) else { return XCTFail() }
        XCTAssertFalse(names(generation(root, 2)).contains("stale.json"))
    }

    // MARK: Recovery

    func testRecoveryRemovesLeftoversAndRepairsOrResetsADamagedPointer() throws {
        let root = try makeRoot()
        XCTAssertEqual(SharedConfigurationLocation(root: { root }).recover(), Report())
        let (location, _) = try migrated(root)
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case .applied = location.apply(try payloads(), expecting: expected, currentPresentation: presentation) else { return XCTFail() }
        // An apply that stopped after renaming its generation, plus stray files.
        try FileManager.default.copyItem(at: generation(root, 2), to: generation(root, 3))
        let manifest = generation(root, 3).appendingPathComponent(SharedConfigurationLocation.manifestFilename)
        try Data(String(decoding: try XCTUnwrap(bytes(manifest)), as: UTF8.self).replacingOccurrences(of: "\"generation\":2", with: "\"generation\":3").utf8).write(to: manifest)
        try FileManager.default.createDirectory(at: folder(root).appendingPathComponent("staging-123"), withIntermediateDirectories: false)
        try put(Data(), ".current.json.ABC.tmp", in: folder(root))
        try put(Data(), "notes.txt", in: folder(root))
        XCTAssertEqual(location.lastGoodGeneration(), "g-000003")
        XCTAssertEqual(location.recover(), Report(repairedPointer: false, removed: [".current.json.ABC.tmp", "g-000003", "staging-123"]))
        XCTAssertEqual(names(folder(root)), [SharedConfigurationLocation.pointerFilename, "g-000001", "g-000002", "notes.txt"],
                       "The current generation and the Undo backup stay")

        // A damaged pointer: readers use the newest complete generation, recovery rebuilds it.
        try put(Data("{".utf8), SharedConfigurationLocation.pointerFilename, in: folder(root))
        XCTAssertEqual(location.currentDirectory()?.lastPathComponent, "g-000002")
        XCTAssertNil(location.currentGeneration())
        XCTAssertEqual(location.recover(), Report(repairedPointer: true, removed: ["g-000001"]))
        XCTAssertEqual(location.readPointer(), .valid(.init(generation: 2, directory: "g-000002")))

        // Incomplete generations don't count; without any, migration starts over.
        try FileManager.default.removeItem(at: generation(root, 2).appendingPathComponent(FontRuleStore.filename))
        try FileManager.default.createDirectory(at: generation(root, 4), withIntermediateDirectories: false)
        try put(Data(#"{"files":[],"generation":5,"schemaVersion":1}"#.utf8), SharedConfigurationLocation.manifestFilename, in: generation(root, 4))
        try put(Data("{".utf8), SharedConfigurationLocation.pointerFilename, in: folder(root))
        XCTAssertNil(location.lastGoodGeneration())
        XCTAssertEqual(location.currentDirectory(), root)
        XCTAssertEqual(location.recover(), Report(repairedPointer: false, removed: ["g-000002", "g-000004"]))
        XCTAssertEqual(location.readPointer(), .missing)
        XCTAssertEqual(location.migrateIfNeeded(presentation: presentation), .applied(.init(generation: 1, directory: "g-000001")))
    }

    func testRecoveryLeavesANewerSchemaAlone() throws {
        let root = try makeRoot()
        let (location, _) = try migrated(root)
        try put(Data(#"{"schemaVersion":2,"generation":7}"#.utf8), SharedConfigurationLocation.pointerFilename, in: folder(root))
        try FileManager.default.createDirectory(at: folder(root).appendingPathComponent("staging-1"), withIntermediateDirectories: false)
        XCTAssertEqual(location.readPointer(), .unsupported)
        XCTAssertEqual(location.currentDirectory(), root)
        XCTAssertEqual(location.recover(), Report(repairedPointer: false, removed: ["staging-1"]))
        XCTAssertTrue(names(folder(root)).contains("g-000001"))
        XCTAssertEqual(location.migrateIfNeeded(presentation: presentation), .alreadyMigrated)
    }

    func testRecoveryRunMigratesOnceAndAdoptsAppPresentationDefaults() throws {
        let root = try makeRoot()
        let defaults = makeDefaults()
        defaults.set(5, forKey: "tileColumns")
        defaults.set(7, forKey: "exploreGridDensity")
        defaults.set(true, forKey: "explorePlane")
        defaults.set(true, forKey: "exploreDescending")
        defaults.set(1, forKey: "exploreShowsPrivateUse")
        defaults.set(UnicodeSortOrder.newestFirst.rawValue, forKey: "emojiSortOrder")
        defaults.set("scratch", forKey: "scratchpad")
        let location = SharedConfigurationLocation(root: { root })
        XCTAssertEqual(ConfigurationRecovery.run(location: location, defaults: defaults), .applied(.init(generation: 1, directory: "g-000001")))
        XCTAssertEqual(defaults.integer(forKey: ConfigurationRecovery.appliedGenerationKey), 1)
        let captured = AppPresentationSettings.decode(try XCTUnwrap(bytes(generation(root, 1).appendingPathComponent(AppPresentationSettings.filename))))
        XCTAssertEqual(captured, .init(integers: ["tileColumns": 5], booleans: ["exploreDescending": true], strings: ["emojiSortOrder": "newestFirst"]))
        XCTAssertEqual(ConfigurationRecovery.run(location: location, defaults: defaults), .alreadyMigrated)
        XCTAssertFalse(ConfigurationRecovery.adoptCurrentPresentation(location: location, defaults: defaults))

        let current = AppPresentationSettings.encode(AppPresentationSettings.capture(defaults))
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: current))
        guard case .applied = location.apply(try payloads(), expecting: expected, currentPresentation: current) else { return XCTFail() }
        // The app stopped before adopting; the next launch finishes it.
        XCTAssertEqual(ConfigurationRecovery.run(location: location, defaults: defaults), .alreadyMigrated)
        XCTAssertEqual(defaults.integer(forKey: ConfigurationRecovery.appliedGenerationKey), 2)
        XCTAssertNil(defaults.object(forKey: "tileColumns"))
        XCTAssertNil(defaults.object(forKey: "emojiSortOrder"))
        XCTAssertNil(defaults.object(forKey: "exploreDescending"))
        XCTAssertEqual(defaults.integer(forKey: "blockGridDensity"), 8)
        XCTAssertEqual(defaults.string(forKey: "scratchpad"), "scratch", "Scratchpad never takes part")

        // An unusable presentation file changes no default but is still marked adopted.
        try put(Data("{".utf8), AppPresentationSettings.filename, in: generation(root, 2))
        defaults.set(1, forKey: ConfigurationRecovery.appliedGenerationKey)
        XCTAssertTrue(ConfigurationRecovery.adoptCurrentPresentation(location: location, defaults: defaults))
        XCTAssertEqual(defaults.integer(forKey: "blockGridDensity"), 8)
        XCTAssertEqual(defaults.integer(forKey: ConfigurationRecovery.appliedGenerationKey), 2)
    }

    func testAppPresentationValuesAreBoundedAndTyped() {
        let defaults = makeDefaults()
        defaults.set(2.5, forKey: "tileColumns")
        defaults.set(16, forKey: "blockGridDensity")
        defaults.set(-1, forKey: "explorePlane")
        defaults.set("codePoint", forKey: "emojiSortOrder")
        defaults.set(false, forKey: "exploreShowsPrivateUse")
        XCTAssertEqual(AppPresentationSettings.capture(defaults), .init(integers: ["blockGridDensity": 16, "explorePlane": -1],
                                                                        booleans: ["exploreShowsPrivateUse": false], strings: ["emojiSortOrder": "codePoint"]))
        defaults.set("random", forKey: "emojiSortOrder")
        XCTAssertNil(AppPresentationSettings.capture(defaults).strings["emojiSortOrder"])
        for invalid in [#"{"integers":{"tileColumns":1},"booleans":{},"strings":{}}"#, #"{"integers":{},"booleans":{"other":true},"strings":{}}"#,
                        #"{"integers":{},"booleans":{},"strings":{"emojiSortOrder":"x"}}"#, "[]",
                        #"{"integers":{},"booleans":{},"strings":{}}"# + String(repeating: " ", count: 4096)] {
            XCTAssertNil(AppPresentationSettings.decode(Data(invalid.utf8)), invalid)
        }
        XCTAssertEqual(AppPresentationSettings.decode(Data(#"{"integers":{},"booleans":{},"strings":{}}"#.utf8)), .init())
        let restored = AppPresentationSettings.Values(integers: ["tileColumns": 3], booleans: ["exploreDescending": true],
                                                      strings: ["emojiSortOrder": "oldestFirst"])
        AppPresentationSettings.apply(restored, to: defaults)
        XCTAssertEqual(AppPresentationSettings.capture(defaults), restored, "Unset keys are removed, set ones restored")
    }

    // MARK: Favorites replacement

    func testFavoritesReplacementPayloadsAndDecoding() throws {
        let v1 = Data(#"{"version":1,"texts":["a"]}"#.utf8)
        XCTAssertEqual(FavoriteSync.decode(v1)?.texts, ["a"])
        XCTAssertNil(FavoriteSync.decode(v1)?.replacementID)
        for invalid in [#"{"version":1,"texts":["a"],"replacementID":"r"}"#, #"{"version":2,"texts":["a"]}"#,
                        #"{"version":2,"texts":["a"],"replacementID":"bad id"}"#, #"{"version":3,"texts":[],"replacementID":"r"}"#,
                        #"{"version":2,"texts":["a","a"],"replacementID":"r"}"#, ""] {
            XCTAssertNil(FavoriteSync.decode(Data(invalid.utf8)), invalid)
        }
        let payload = try XCTUnwrap(FavoriteSync.replacementPayload(["Ψ"], id: "r-1"))
        XCTAssertEqual(FavoriteSync.decode(payload)?.replacementID, "r-1")
        XCTAssertEqual(FavoriteSync.decode(payload)?.version, 2)
        XCTAssertNil(FavoriteSync.replacementPayload(["a", "a"]))
        XCTAssertNil(FavoriteSync.replacementPayload(["a"], id: "no spaces"))
        let renewed = try XCTUnwrap(FavoriteSync.decode(try XCTUnwrap(FavoriteSync.renewedReplacement(payload))))
        XCTAssertEqual(renewed.texts, ["Ψ"])
        XCTAssertNotEqual(renewed.replacementID, "r-1")
        XCTAssertEqual(FavoriteSync.renewedReplacement(Data("junk".utf8)), Data("junk".utf8))
    }

    func testAReplacedFavoritesListIsAdoptedWholesaleOnce() throws {
        let root = try makeRoot()
        let sync = FavoriteSync(container: { root })
        try put(try XCTUnwrap(FavoriteSync.replacementPayload(["x", "y"], id: "r1")), FavoriteSync.filename, in: root)
        let read = try sync.synchronize(base: ["a"], local: ["a", "b"], canWrite: false)
        XCTAssertEqual(read.texts, ["x", "y"])
        XCTAssertEqual(read.baseline, ["x", "y"])
        XCTAssertFalse(read.written)
        XCTAssertEqual(read.replacementID, "r1")
        let write = try sync.synchronize(base: ["a"], local: ["a", "b"], canWrite: true, replacementID: "r0")
        XCTAssertEqual(write.texts, ["x", "y"])
        XCTAssertTrue(write.written)
        XCTAssertEqual(FavoriteSync.decode(try XCTUnwrap(bytes(root.appendingPathComponent(FavoriteSync.filename))))?.texts, ["x", "y"])

        let merged = try sync.synchronize(base: ["x", "y"], local: ["x", "y", "z"], canWrite: true, replacementID: "r1")
        XCTAssertEqual(Set(merged.texts), ["x", "y", "z"])
        XCTAssertEqual(merged.replacementID, "r1")
        let file = try XCTUnwrap(FavoriteSync.decode(try XCTUnwrap(bytes(root.appendingPathComponent(FavoriteSync.filename)))))
        XCTAssertEqual(file.version, 2)
        XCTAssertEqual(file.replacementID, "r1", "Ordinary syncs keep the replacement id")
        XCTAssertEqual(try sync.synchronize(base: ["x", "y", "z"], local: ["x"], canWrite: false, replacementID: "r1").texts, ["x"])

        try put(Data(#"{"version":1,"texts":["v1"]}"#.utf8), FavoriteSync.filename, in: root)
        XCTAssertEqual(try sync.synchronize(base: [], local: [], canWrite: false, replacementID: "r1").replacementID, "r1")
        XCTAssertEqual(try sync.synchronize(base: [], local: ["w"], canWrite: true).replacementID, nil)
        XCTAssertEqual(FavoriteSync.decode(try XCTUnwrap(bytes(root.appendingPathComponent(FavoriteSync.filename))))?.version, 1)
    }

    func testFavoritesSyncUsesTheCurrentGenerationAndTheRootLock() throws {
        let root = try makeRoot()
        let (location, _) = try migrated(root)
        let sync = FavoriteSync(location: location)
        XCTAssertTrue(try sync.synchronize(base: [], local: ["Ψ"], canWrite: true).written)
        XCTAssertEqual(FavoriteSync.decode(try XCTUnwrap(bytes(generation(root, 1).appendingPathComponent(FavoriteSync.filename))))?.texts, ["Ψ"])
        XCTAssertNil(bytes(root.appendingPathComponent(FavoriteSync.filename)))
        let descriptor = holdLock(root)
        defer { close(descriptor) }
        XCTAssertThrowsError(try sync.synchronize(base: [], local: ["Ψ", "x"], canWrite: true))
        XCTAssertThrowsError(try FavoriteSync(location: SharedConfigurationLocation(root: { nil })).synchronize(base: [], local: [], canWrite: true))
    }

    func testSymbolBoardStoreAdoptsAReplacementAndRemembersIt() throws {
        let root = try makeRoot()
        let defaults = makeDefaults()
        let sync = FavoriteSync(container: { root })
        let app = SymbolBoardStore(defaults: defaults, sync: sync, sharedWriteAllowed: true)
        XCTAssertNotNil(app.add(text: "local", to: SymbolBoardStore.favoritesID))
        XCTAssertEqual(app.favoriteTexts, ["local"])
        try put(try XCTUnwrap(FavoriteSync.replacementPayload(["imported"], id: "r1")), FavoriteSync.filename, in: root)
        app.adoptReplacement()
        XCTAssertEqual(app.favoriteTexts, ["imported"])
        let reopened = SymbolBoardStore(defaults: defaults, sync: sync, sharedWriteAllowed: true)
        XCTAssertEqual(reopened.favoriteTexts, ["imported"])
        XCTAssertNotNil(reopened.add(text: "new", to: SymbolBoardStore.favoritesID))
        XCTAssertEqual(Set(reopened.favoriteTexts), ["imported", "new"], "After adopting, edits merge as usual")
        XCTAssertEqual(FavoriteSync.decode(try XCTUnwrap(bytes(root.appendingPathComponent(FavoriteSync.filename))))?.replacementID, "r1")

        let data = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(state["favoriteReplacementID"] as? String, "r1")
        state["favoriteReplacementID"] = "not valid"
        defaults.set(try JSONSerialization.data(withJSONObject: state), forKey: SymbolBoardStore.storageKey)
        XCTAssertFalse(SymbolBoardStore(defaults: defaults, sync: sync).canEdit)
    }

    // MARK: Font rules

    func testFontRuleStoreSavesValidatedRulesAndKeepsUnusableFiles() throws {
        let root = try makeRoot()
        let store = FontRuleStore(directory: { root })
        XCTAssertNil(FontRuleStore(directory: { nil }).load())
        XCTAssertFalse(FontRuleStore(directory: { nil }).save([]))
        XCTAssertEqual(store.load(), [])
        let runic = try XCTUnwrap(FontRuleBlock(named: "Runic"))
        let rules = [rule("b", .block(runic)), rule("r", .range(first: 0x1F600, last: 0x1F64F)), rule("c", .codePoint(0x10FFFD))]
        XCTAssertTrue(store.save(rules))
        XCTAssertEqual(store.load(), rules)
        XCTAssertEqual(store.load(blocks: UnicodeCatalog.shared.blocks), rules)
        let saved = bytes(root.appendingPathComponent(FontRuleStore.filename))
        XCTAssertEqual(FontRuleStore.encode(rules), saved, "Deterministic")

        for invalid in [[rule("a", .codePoint(0x41)), rule("a", .codePoint(0x42))], [rule("", .codePoint(0x41))],
                        [rule(String(repeating: "i", count: 129), .codePoint(0x41))], [rule("tab\t", .codePoint(0x41))],
                        [rule("s", .codePoint(0xD800))], [FontRule(id: "f", selector: .codePoint(0x41), face: face(""))],
                        [rule("x", .block(FontRuleBlock(name: "Runic", first: 0x16A0, last: 0x16A1, unicodeVersion: "17.0")))]] {
            XCTAssertFalse(store.save(invalid))
            XCTAssertNil(FontRuleStore.encode(invalid, blocks: UnicodeCatalog.shared.blocks))
        }
        XCTAssertEqual(bytes(root.appendingPathComponent(FontRuleStore.filename)), saved, "Refused, never trimmed")
        let unknown = [rule("x", .block(FontRuleBlock(name: "Made Up", first: 0x16A0, last: 0x16A1, unicodeVersion: "17.0")))]
        XCTAssertNotNil(FontRuleStore.encode(unknown), "Without a block table only the shape is checked")

        let faceJSON = String(decoding: try SharedConfigurationLocation.encoder.encode(face()), as: UTF8.self)
        for invalid in ["junk", #"{"schemaVersion":2,"rules":[]}"#,
                        #"{"schemaVersion":1,"rules":[{"id":"a","codePoint":65,"range":[65,66],"face":\#(faceJSON)}]}"#,
                        #"{"schemaVersion":1,"rules":[{"id":"a","range":[65,66,67],"face":\#(faceJSON)}]}"#,
                        #"{"schemaVersion":1,"rules":[{"id":"a","face":\#(faceJSON)}]}"#,
                        #"{"schemaVersion":1,"rules":[]}"# + String(repeating: " ", count: FontRuleStore.maximumPayloadBytes)] {
            XCTAssertNil(FontRuleStore.decode(Data(invalid.utf8)), String(invalid.prefix(80)))
        }
        try put(Data("junk".utf8), FontRuleStore.filename, in: root)
        XCTAssertNil(store.load())
        XCTAssertEqual(bytes(root.appendingPathComponent(FontRuleStore.filename)), Data("junk".utf8))
        try FileManager.default.removeItem(at: root.appendingPathComponent(FontRuleStore.filename))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(FontRuleStore.filename), withIntermediateDirectories: false)
        XCTAssertNil(store.load())
        XCTAssertFalse(store.save(rules))
        _ = FontRuleStore.shared.directory()
    }

    func testFontRuleSnapshotReaderDecodesOnlyWhenTheFileChanged() throws {
        let root = try makeRoot()
        let store = FontRuleStore(directory: { root })
        let reader = FontRuleSnapshotReader(store: store)
        XCTAssertFalse(reader.refresh(), "No file means no rules")
        XCTAssertEqual(reader.decodeCount, 1)
        XCTAssertFalse(reader.refresh())
        XCTAssertEqual(reader.decodeCount, 1, "Unchanged: nothing is decoded")
        let rules = [rule("a", .codePoint(0x41))]
        XCTAssertTrue(store.save(rules))
        XCTAssertTrue(reader.refresh())
        XCTAssertEqual(reader.rules, rules)
        XCTAssertEqual(reader.decodeCount, 2)
        XCTAssertFalse(reader.refresh())
        XCTAssertEqual(reader.decodeCount, 2)
        XCTAssertTrue(store.save(rules))
        XCTAssertFalse(reader.refresh(), "A rewrite with the same rules is no change")
        XCTAssertEqual(reader.decodeCount, 3)
        try put(Data("junk".utf8), FontRuleStore.filename, in: root)
        XCTAssertTrue(reader.refresh())
        XCTAssertEqual(reader.rules, [], "An unusable file reads as no rules")
        XCTAssertFalse(FontRuleSnapshotReader(store: FontRuleStore(directory: { nil })).refresh())
        _ = FontRuleSnapshotReader().rules
    }

    // MARK: Image colors and capitalization

    func testImageColorsAreSharedOnlyAfterMigrationUnderTheLock() throws {
        let root = try makeRoot()
        let unmigrated = ImageColorSettings(location: SharedConfigurationLocation(root: { root }))
        let value = ImageColorSettings.Value(preset: "custom", customText: "#a1b2c3", customBackground: "transparent")
        XCTAssertNil(unmigrated.load())
        XCTAssertFalse(unmigrated.isUnpublished())
        XCTAssertThrowsError(try unmigrated.save(value))
        XCTAssertNil(bytes(root.appendingPathComponent(ImageColorSettings.filename)), "Nothing new is written into the group root")

        let (location, _) = try migrated(root)
        let colors = ImageColorSettings(location: location)
        XCTAssertTrue(colors.isUnpublished())
        XCTAssertNil(colors.load())
        let stored = try colors.save(value)
        XCTAssertEqual(colors.load(), stored)
        XCTAssertFalse(colors.isUnpublished())
        let next = try colors.save(ImageColorSettings.defaultValue)
        XCTAssertNotEqual(next.revision, stored.revision, "Every write is a new revision")
        for invalid in [ImageColorSettings.Value(preset: "rainbow", customText: "#000000", customBackground: "#FFFFFF"),
                        .init(preset: "custom", customText: "#00000G", customBackground: "#FFFFFF"),
                        .init(preset: "custom", customText: "000000", customBackground: "#FFFFFF"),
                        .init(preset: "custom", customText: "#000000", customBackground: "clear")] {
            XCTAssertFalse(ImageColorSettings.isValid(invalid))
            XCTAssertThrowsError(try colors.save(invalid))
        }
        XCTAssertEqual(colors.load(), next)

        let descriptor = holdLock(root)
        XCTAssertThrowsError(try colors.save(value)) { XCTAssertEqual($0 as? SharedConfigurationLocation.Failure, .busy) }
        close(descriptor)

        let file = generation(root, 1).appendingPathComponent(ImageColorSettings.filename)
        try put(Data("junk".utf8), ImageColorSettings.filename, in: generation(root, 1))
        XCTAssertNil(colors.load())
        XCTAssertFalse(colors.isUnpublished(), "An unusable file is not replaced by a first publish")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(colors.isUnpublished())
        XCTAssertNil(ImageColorSettings(location: SharedConfigurationLocation(root: { nil })).load())
        _ = ImageColorSettings.shared.location
    }

    func testImageColorPayloadsAndRenewedRevisions() throws {
        let stored = ImageColorSettings.Stored(value: ImageColorSettings.defaultValue, revision: "r1")
        let data = try XCTUnwrap(ImageColorSettings.encode(stored))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       ##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"blackOnWhite","revision":"r1","scale":3,"schemaVersion":1}"##)
        XCTAssertEqual(ImageColorSettings.decode(data), stored)
        // Files written before the scale choice read as 3×.
        let older = ImageColorSettings.decode(Data(##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"blackOnWhite","revision":"r1","schemaVersion":1}"##.utf8))
        XCTAssertEqual(older, stored)
        XCTAssertEqual(older?.value.scale, 3)
        var two = stored
        two.value.scale = 2
        XCTAssertEqual(ImageColorSettings.decode(try XCTUnwrap(ImageColorSettings.encode(two)))?.value.scale, 2)
        for scale in [0, 4, -1] {
            var invalid = stored
            invalid.value.scale = scale
            XCTAssertFalse(ImageColorSettings.isValid(invalid.value))
            XCTAssertNil(ImageColorSettings.encode(invalid))
        }
        XCTAssertNil(ImageColorSettings.encode(.init(value: ImageColorSettings.defaultValue, revision: "bad revision")))
        for invalid in [##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"blackOnWhite","revision":"r1","schemaVersion":2}"##,
                        ##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"blackOnWhite","revision":"","schemaVersion":1}"##,
                        ##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"other","revision":"r1","schemaVersion":1}"##,
                        ##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"blackOnWhite","revision":"r1","scale":5,"schemaVersion":1}"##,
                        ##"{"customBackground":"#FFFFFF","customText":"#000000","preset":"blackOnWhite","revision":"r1","scale":"3","schemaVersion":1}"##,
                        "junk", String(repeating: " ", count: 1025)] {
            XCTAssertNil(ImageColorSettings.decode(Data(invalid.utf8)), invalid)
        }
        let renewed = try XCTUnwrap(ImageColorSettings.decode(ImageColorSettings.renewedRevision(data)))
        XCTAssertEqual(renewed.value, stored.value)
        XCTAssertNotEqual(renewed.revision, "r1")
        XCTAssertEqual(ImageColorSettings.renewedRevision(Data("junk".utf8)), Data("junk".utf8))
    }

    // MARK: Copy Image scale

    func testImageScalesAndTheirLabels() {
        XCTAssertEqual(KeyboardImageScale.allCases.map(\.rawValue), [1, 2, 3])
        XCTAssertEqual(KeyboardImageScale.default, .x3, "3×, today's behavior")
        XCTAssertEqual(KeyboardImageScale.allCases.map(\.label), ["1×", "2×", "3×"])
        XCTAssertEqual(KeyboardImageScale.allCases.map(\.factor), [1, 2, 3])
        XCTAssertEqual(KeyboardImageScale.allCases.map(\.dpi), [72, 144, 216])
        XCTAssertLessThan(KeyboardImageScale.x1, .x2)
        XCTAssertEqual(ImageColorSettings.defaultValue.scale, 3)
    }

    func testPixelSizesAtEachScaleRoundUpTheSameCanvas() throws {
        let canvas = CGSize(width: 420.4, height: 44.1)
        let sizes = try KeyboardImageScale.allCases.map { try XCTUnwrap(KeyboardImageCanvas.pixelSize(canvas: canvas, scale: $0)) }
        XCTAssertEqual(sizes.map(\.width), [421, 841, 1262])
        XCTAssertEqual(sizes.map(\.height), [45, 89, 133])
        XCTAssertEqual(sizes.map(\.scale), KeyboardImageScale.allCases)
        XCTAssertFalse(sizes.contains(where: \.isReduced))
        XCTAssertEqual(sizes[2].label, "1262 × 133 px")
    }

    func testAScaleOverTheCanvasLimitsStepsDownToWhatIsProduced() throws {
        let limit = CGFloat(KeyboardImageCanvas.maximumPixelWidth)
        // Exactly at the width limit at 3× still fits.
        let edge = try XCTUnwrap(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: limit / 3, height: 40), scale: .x3))
        XCTAssertEqual(edge.width, KeyboardImageCanvas.maximumPixelWidth)
        XCTAssertFalse(edge.isReduced)
        // Wider than 4800 px at 3×: drawn at 2×, and that is the size shown.
        let wide = try XCTUnwrap(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 2000, height: 40), scale: .x3))
        XCTAssertEqual(wide, KeyboardImagePixelSize(width: 4000, height: 80, scale: .x2, requested: .x3))
        XCTAssertTrue(wide.isReduced)
        // Too tall for 2×: 1×.
        let tall = try XCTUnwrap(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 100, height: 700), scale: .x3))
        XCTAssertEqual(tall, KeyboardImagePixelSize(width: 100, height: 700, scale: .x1, requested: .x3))
        // Within each side's limit but over the pixel count at 3× and 2×.
        let area = try XCTUnwrap(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 2300, height: 600), scale: .x2))
        XCTAssertEqual(area, KeyboardImagePixelSize(width: 2300, height: 600, scale: .x1, requested: .x2))
        // A lower request never goes up.
        XCTAssertEqual(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 10, height: 10), scale: .x1)?.scale, .x1)
        // Nothing fits, or nothing to draw.
        XCTAssertNil(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 5000, height: 10), scale: .x3))
        XCTAssertNil(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 0, height: 10), scale: .x3))
        XCTAssertNil(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 10, height: 0), scale: .x3))
        XCTAssertNil(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: CGFloat.infinity, height: 10), scale: .x3))
        XCTAssertNil(KeyboardImageCanvas.pixelSize(canvas: CGSize(width: 10, height: CGFloat.nan), scale: .x3))
    }

    func testAutoCapitalizationDefaultsToFollowApp() throws {
        let root = try makeRoot()
        let setting = AutoCapitalizationSetting(directory: { root })
        XCTAssertEqual(setting.load(), .followApp)
        XCTAssertEqual(AutoCapitalizationMode.allCases.map(\.rawValue), ["follow_app", "off", "sentences", "words", "all_characters"])
        for mode in AutoCapitalizationMode.allCases {
            XCTAssertTrue(setting.save(mode))
            XCTAssertEqual(setting.load(), mode)
        }
        XCTAssertEqual(String(decoding: AutoCapitalizationSetting.encode(.allCharacters), as: UTF8.self), #"{"mode":"all_characters","schemaVersion":1}"#)
        for invalid in [#"{"mode":"shout","schemaVersion":1}"#, #"{"mode":"off","schemaVersion":2}"#, "junk",
                        #"{"mode":"off","schemaVersion":1}"# + String(repeating: " ", count: 256)] {
            XCTAssertNil(AutoCapitalizationSetting.decode(Data(invalid.utf8)), invalid)
            try put(Data(invalid.utf8), AutoCapitalizationSetting.filename, in: root)
            XCTAssertEqual(setting.load(), .followApp)
        }
        XCTAssertEqual(AutoCapitalizationSetting(directory: { nil }).load(), .followApp)
        XCTAssertFalse(AutoCapitalizationSetting(directory: { nil }).save(.off))
        _ = AutoCapitalizationSetting.shared.directory()
    }

    // MARK: Store payload helpers

    func testStorePayloadHelpersMatchTheirReaders() throws {
        let pages = SymbolPageSettings.Snapshot(pages: [], starPageID: "p")
        XCTAssertEqual(SymbolPageSettings.decode(try XCTUnwrap(SymbolPageSettings.encode(pages))), pages)
        XCTAssertNil(SymbolPageSettings.decode(Data()))
        XCTAssertNil(SymbolPageSettings.decode(Data(#"{"schemaVersion":2,"pages":[],"starPageID":"p"}"#.utf8)))
        XCTAssertEqual(KeyboardKeySettings.decode(try XCTUnwrap(KeyboardKeySettings.encode(.defaults))), .defaults)
        XCTAssertNil(KeyboardKeySettings.decode(Data()))
        let edition = UnicodeEditionSettings.Snapshot(edition: .latest)
        XCTAssertEqual(UnicodeEditionSettings.decode(try XCTUnwrap(UnicodeEditionSettings.encode(edition))), edition)
        XCTAssertNil(UnicodeEditionSettings.decode(Data("{}".utf8)))
        let numberRowOff = UnicodeEditionSettings.Snapshot(edition: .latest, useUnicodeFonts: true, showsCollapseKey: true)
        var withoutNumbers = numberRowOff
        withoutNumbers.showsNumberRow = !numberRowOff.showsNumberRow
        let encoded = try XCTUnwrap(UnicodeEditionSettings.encode(withoutNumbers))
        XCTAssertEqual(UnicodeEditionSettings.decode(encoded)?.showsNumberRow, withoutNumbers.showsNumberRow, "The Number Row choice is kept as it is")
    }
}
