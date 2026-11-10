#if canImport(UIKit)
import XCTest
import CoreText
@testable import Uniboard

private actor FixtureFontTransport: GoogleFontTransport {
    let data: Data
    private(set) var calls = 0
    init(data: Data) { self.data = data }
    func fetch(url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data {
        calls += 1; return data
    }
}

final class FontLibraryStorageTests: XCTestCase {
    private func store(directoryHint: Bool = false) -> CustomFontStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: directoryHint)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return CustomFontStore(directory: root)
    }

    /// Extract one public process font into an independently owned SFNT buffer.
    /// Never mutate Data bridged from CTFontCopyTable: it can alias read-only pages.
    private func fixture() throws -> (Data, String) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        guard let rawTags = CTFontCopyAvailableTables(font, CTFontTableOptions(rawValue: 0)) else {
            throw XCTSkip("Runtime has no extractable public font tables")
        }
        let count = CFArrayGetCount(rawTags)
        guard count > 0, count <= 4095 else { throw FontLibraryFailure.invalidFile }
        // This CFArray contains integer CTFontTableTag values, not NSNumber objects.
        let tags: [UInt32] = (0..<count).map { index in
            UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(rawTags, index)))
        }
        var tables: [(UInt32, [UInt8])] = []
        var totalBytes = 12 + count * 16
        for tag in tags {
            guard let borrowed = CTFontCopyTable(font, tag, CTFontTableOptions(rawValue: 0)) else { throw FontLibraryFailure.invalidFile }
            let length = CFDataGetLength(borrowed)
            guard length >= 0, length <= CustomFontStore.maximumBytes - totalBytes - 3 else { throw FontLibraryFailure.invalidFile }
            totalBytes += (length + 3) & ~3
            // CFDataGetBytes makes an explicit copy into allocated Swift array storage.
            var owned = [UInt8](repeating: 0, count: length)
            if length > 0 {
                try owned.withUnsafeMutableBufferPointer { buffer in
                    guard let destination = buffer.baseAddress else { throw FontLibraryFailure.invalidFile }
                    CFDataGetBytes(borrowed, CFRange(location: 0, length: length), destination)
                }
            }
            if tag == 0x68656164 {
                guard owned.count >= 12 else { throw FontLibraryFailure.invalidFile }
                for index in 8..<12 { owned[index] = 0 }
            }
            tables.append((tag, owned))
        }
        tables.sort { $0.0 < $1.0 }
        guard Set(tags).count == count else { throw FontLibraryFailure.invalidFile }
        func u16(_ x: Int) -> [UInt8] { [UInt8((x >> 8) & 255), UInt8(x & 255)] }
        func u32(_ x: UInt32) -> [UInt8] { [UInt8((x >> 24) & 255), UInt8((x >> 16) & 255), UInt8((x >> 8) & 255), UInt8(x & 255)] }
        func checksum(_ bytes: [UInt8]) -> UInt32 {
            var result: UInt32 = 0
            for start in stride(from: 0, to: bytes.count, by: 4) {
                var word: UInt32 = 0
                for index in 0..<4 {
                    word = (word << 8) | (start + index < bytes.count ? UInt32(bytes[start + index]) : 0)
                }
                result = result &+ word
            }
            return result
        }
        var power = 1, exponent = 0
        while power * 2 <= count { power *= 2; exponent += 1 }
        var header = u32(tables.contains { $0.0 == 0x43464620 || $0.0 == 0x43464632 } ? 0x4f54544f : 0x00010000)
        header += u16(count); header += u16(power * 16); header += u16(exponent); header += u16(count * 16 - power * 16)
        var body: [UInt8] = []
        var headOffset: Int?
        for (tag, bytes) in tables {
            let offset = 12 + count * 16 + body.count
            if tag == 0x68656164 { headOffset = offset }
            header += u32(tag); header += u32(checksum(bytes)); header += u32(UInt32(offset)); header += u32(UInt32(bytes.count))
            body += bytes
            while body.count % 4 != 0 { body.append(0) }
        }
        var output = header + body
        guard let offset = headOffset, offset + 12 <= output.count else { throw FontLibraryFailure.invalidFile }
        let adjustment = u32(0xb1b0afba &- checksum(output))
        for index in 0..<4 { output[offset + 8 + index] = adjustment[index] }
        XCTAssertEqual(checksum(output), 0xb1b0afba)
        let data = Data(output) // The only Data creation; owns copied mutable storage.
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let graphics = try XCTUnwrap(CGFont(provider), "Rebuilt fixture must open before exercising storage")
        let name = CTFontCopyPostScriptName(font) as String
        XCTAssertEqual(graphics.postScriptName as String?, name)
        return (data, name)
    }

    func testValidCommitVariableDedupRelaunchRemovalAndLateCancellation() throws {
        // Match the production app-group root construction, including its directory hint.
        let store = store(directoryHint: true)
        XCTAssertTrue(store.directory!.hasDirectoryPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory!.path))
        XCTAssertNotNil(store.url(forRelativePath: "library-v2.json"))
        let (data, name) = try fixture()
        let license = FontLibraryLicense(id: "l", name: "Runtime fixture", repositoryPath: "test/license", sha256: CustomFontStore.digest(Data("test".utf8)), text: "test")
        let receipt = FontLibraryReceipt(fileID: "test", repositoryCommit: String(repeating: "a", count: 40), repositoryPath: "test/font.ttf", snapshotDate: "2026-10-23", sha256: CustomFontStore.digest(data), licenses: [license])
        let faces = ["regular", "bold"].map { style in FontFaceRecord(id: .init(rawValue: style), family: "Fixture", style: style, postScriptName: name, source: .downloaded, locator: .process(postScriptName: name, variations: [:]), assetID: nil) }
        XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: ["Incorrect-PostScript-Name"]))
        var wrongHash = data; wrongHash.append(0)
        XCTAssertThrowsError(try store.installGoogleFont(data: wrongHash, receipt: receipt, faces: faces, expectedPostScriptNames: [name]))
        XCTAssertThrowsError(try store.installGoogleFont(data: Data(count: CustomFontStore.maximumBytes + 1), receipt: receipt, faces: faces, expectedPostScriptNames: [name]))
        XCTAssertTrue(store.fonts.isEmpty)
        var checks = 0
        XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name], checkCancellation: {
            checks += 1; if checks == 2 { throw CancellationError() }
        }))
        XCTAssertEqual(checks, 2)
        XCTAssertTrue(store.fonts.isEmpty)
        let id = try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory!.path))
        XCTAssertNotNil(store.url(forRelativePath: id))
        XCTAssertEqual(try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name]), id)
        let relaunched = CustomFontStore(directory: store.directory)
        XCTAssertEqual(relaunched.localLibrary.faces.count, 2)
        XCTAssertEqual(relaunched.localLibrary.customEntryCount, 1)
        XCTAssertEqual(relaunched.receipt(fileID: "test")?.licenses.first?.text, "test")
        let path = try XCTUnwrap(relaunched.url(forRelativePath: id))
        try relaunched.removeGoogleFont(fileID: "test")
        XCTAssertTrue(relaunched.localLibrary.faces.isEmpty)
        XCTAssertEqual(try Data(contentsOf: path), data, "Old snapshot bytes remain readable")
        // Both import orderings preserve independently acquired ownership.
        _ = try store.add(data)
        _ = try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name])
        try store.removeGoogleFont(fileID: "test")
        XCTAssertEqual(store.fonts.count, 1)
        try store.remove(XCTUnwrap(store.fonts.first))
        _ = try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name])
        let beforeImport = store.revision
        _ = try store.add(data)
        XCTAssertNotEqual(beforeImport, store.revision)
        try store.removeGoogleFont(fileID: "test")
        XCTAssertEqual(store.fonts.count, 1)
        // A matching manifest hash does not justify missing/corrupt bytes.
        let importedFont = try XCTUnwrap(store.fonts.first)
        let importedURL = try XCTUnwrap(store.url(forFilename: importedFont.filename))
        try FileManager.default.removeItem(at: importedURL)
        _ = try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name])
        XCTAssertEqual(try Data(contentsOf: importedURL), data)
        // Receipt membership and locators must agree, even in syntactically valid JSON.
        let manifestURL = store.directory!.appendingPathComponent("library-v2.json")
        let validManifestData = try Data(contentsOf: manifestURL)
        var malformed = try store.readManifest()
        let download = try XCTUnwrap(malformed.downloads.first)
        let face = try XCTUnwrap(download.faces.first)
        let unsafe = FontFaceRecord(id: face.id, family: face.family, style: face.style, postScriptName: face.postScriptName, source: .downloaded,
                                   locator: .file(relativePath: "../escape", sha256: receipt.sha256, faceIndex: 0, variations: [:]), assetID: download.filename)
        malformed.downloads[0] = .init(filename: download.filename, receipt: download.receipt, faces: [unsafe], retainsImportedEntry: true)
        try JSONEncoder().encode(malformed).write(to: manifestURL)
        XCTAssertThrowsError(try store.readLibraryState())
        try validManifestData.write(to: manifestURL)
        let beforeCorruption = store.revision
        try Data("corruption".utf8).write(to: importedURL)
        XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name]))
        XCTAssertThrowsError(try store.add(data))
        XCTAssertEqual(store.revision, beforeCorruption)
        XCTAssertEqual(try Data(contentsOf: importedURL), Data("corruption".utf8))

    }

    @MainActor
    func testCoordinatorReconcilesLegacyRemovalBeforeDownloadedFastPath() async throws {
        let store = store()
        let (data, name) = try fixture()
        let file = GoogleFontFile(id: "f", repositoryPath: "ofl/fixture/font.ttf", bytes: Int64(data.count), sha256: CustomFontStore.digest(data), expectedPostScriptNames: [name], licenseIDs: ["l"])
        let license = GoogleFontLicense(id: "l", name: "Test", repositoryPath: "ofl/fixture/OFL.txt", sha256: CustomFontStore.digest(Data("test".utf8)), text: "test")
        let family = GoogleFontFamily(id: "family", name: "Fixture", styles: [.init(id: "s", name: "Regular", fileID: "f", postScriptName: name)])
        let catalog = GoogleFontCatalogSnapshot(schemaVersion: 1, repositoryCommit: GoogleFontCatalog.trustedRepositoryCommit, snapshotDate: "2026-10-23", families: [family], files: [file], licenses: [license])
        let transport = FixtureFontTransport(data: data)
        let coordinator = GoogleFontDownloadCoordinator(catalog: catalog, store: store, transport: transport)
        try await coordinator.download(styleID: "s")
        let custom = try XCTUnwrap(store.fonts.first)
        try store.remove(custom)
        XCTAssertNil(store.receipt(fileID: "f"))
        try await coordinator.download(styleID: "s")
        let calls = await transport.calls
        XCTAssertEqual(calls, 2)
        XCTAssertNotNil(store.receipt(fileID: "f"))
    }

    func testMalformedLegacyAndDuplicateManifestFailClosed() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory!, withIntermediateDirectories: true)
        let bad = CustomFont(filename: "../escape.ttf", displayName: "Bad", postScriptName: "Bad", sha256: "", ranges: [])
        let legacy = store.directory!.appendingPathComponent("fonts.json")
        let bytes = try JSONEncoder().encode([bad]); try bytes.write(to: legacy)
        XCTAssertThrowsError(try store.readLibraryState())
        XCTAssertEqual(store.libraryFailure, .storageFailure)
        XCTAssertThrowsError(try store.addInstalled(postScriptName: "Helvetica"))
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
        try FileManager.default.removeItem(at: legacy)
        _ = try store.addInstalled(postScriptName: "Helvetica")
        var manifest = try store.readManifest()
        manifest.fonts.append(try XCTUnwrap(manifest.fonts.first))
        try JSONEncoder().encode(manifest).write(to: store.directory!.appendingPathComponent("library-v2.json"))
        XCTAssertThrowsError(try store.readLibraryState())
    }

    func testManifestCacheDetectsOtherStoreMigrationMutationCorruptionAndAbsence() throws {
        let reader = store()
        let writer = CustomFontStore(directory: reader.directory)
        try FileManager.default.createDirectory(at: reader.directory!, withIntermediateDirectories: true)
        let legacyURL = reader.directory!.appendingPathComponent("fonts.json")
        let original = CustomFont(filename: "Installed-Helvetica", displayName: "Helvetica", postScriptName: "Helvetica", sha256: "", ranges: [[65,90]], installed: true)
        try JSONEncoder().encode([original]).write(to: legacyURL, options: .atomic)
        XCTAssertEqual(reader.fonts, [original])
        let legacyGeneration = reader.revision
        let identity = try XCTUnwrap(reader.manifestCache?.identity)
        for _ in 0..<10 { XCTAssertEqual(reader.revision, legacyGeneration); XCTAssertEqual(reader.fonts, [original]) }
        XCTAssertEqual(reader.manifestCache?.identity, identity)
        XCTAssertEqual(identity.filename, "fonts.json")

        // A different store instance has its own cache but uses the same writer lock.
        try writer.remove(original)
        XCTAssertTrue(reader.fonts.isEmpty)
        XCTAssertNotEqual(reader.revision, legacyGeneration)
        XCTAssertEqual(reader.manifestCache?.identity.filename, "library-v2.json")
        _ = try writer.addInstalled(postScriptName: "Helvetica")
        XCTAssertEqual(reader.fonts.count, 1)
        let validGeneration = reader.revision
        let manifestURL = reader.directory!.appendingPathComponent("library-v2.json")
        let validBytes = try Data(contentsOf: manifestURL)
        // Same byte count and restored modification date still changes inode/ctime.
        let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        try Data(repeating: 120, count: validBytes.count).write(to: manifestURL, options: .atomic)
        if let modificationDate = attributes[.modificationDate] { try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: manifestURL.path) }
        XCTAssertThrowsError(try reader.readLibraryState())
        XCTAssertNil(reader.manifestCache)
        XCTAssertEqual(reader.libraryFailure, .storageFailure)
        XCTAssertThrowsError(try reader.readLibraryState(), "Corruption must not be hidden by a formerly valid cache")
        try validBytes.write(to: manifestURL, options: .atomic)
        XCTAssertEqual(reader.revision, validGeneration)
        XCTAssertNil(reader.libraryFailure)

        try FileManager.default.removeItem(at: manifestURL)
        XCTAssertEqual(reader.revision, legacyGeneration, "Legacy fallback is selected anew when v2 disappears")
        XCTAssertEqual(reader.fonts, [original])
        try FileManager.default.removeItem(at: legacyURL)
        XCTAssertEqual(reader.revision, "")
        XCTAssertTrue(reader.fonts.isEmpty)
        XCTAssertNil(reader.manifestCache)
    }

    func testBoundedReadRejectsLimitPlusOne() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory!, withIntermediateDirectories: true)
        let url = store.directory!.appendingPathComponent("bounded")
        try Data(count: 1025).write(to: url)
        XCTAssertThrowsError(try CustomFontStore.boundedRead(url, limit: 1024))
        XCTAssertEqual(try CustomFontStore.boundedRead(url, limit: 1025).count, 1025)
    }

    func testTrustedContainerAliasCanonicalizesWithoutFollowingLibraryLeaf() throws {
        let container = store(directoryHint: true).directory!
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let aliasParent = store(directoryHint: true).directory!
        try FileManager.default.createDirectory(at: aliasParent, withIntermediateDirectories: true)
        let alias = aliasParent.appendingPathComponent("trusted-container", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: container.path)
        let library = CustomFontStore(directory: alias.appendingPathComponent("CustomFonts-v1", isDirectory: true))
        XCTAssertEqual(library.directory?.deletingLastPathComponent().pathComponents, container.resolvingSymlinksInPath().pathComponents)
        XCTAssertNotNil(library.url(forRelativePath: "library-v2.json"))
        _ = try library.addInstalled(postScriptName: "Helvetica")
        XCTAssertEqual(library.fonts.count, 1)
        // Only the trusted parent was canonicalized. A substituted library leaf is refused.
        let hostileLeaf = container.appendingPathComponent("substituted-library", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: hostileLeaf.path, withDestinationPath: aliasParent.path)
        let hostile = CustomFontStore(directory: alias.appendingPathComponent("substituted-library", isDirectory: true))
        XCTAssertNil(hostile.url(forRelativePath: "library-v2.json"))
        XCTAssertThrowsError(try hostile.readLibraryState())
    }

    func testTemporaryDirectoryOSAliasWhenAvailable() throws {
        let canonical = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path.hasPrefix("/private/var/") else { throw XCTSkip("Runtime temporary container has no /var OS alias") }
        let alias = URL(fileURLWithPath: String(canonical.path.dropFirst("/private".count)), isDirectory: true)
        let name = UUID().uuidString
        let requested = alias.appendingPathComponent(name, isDirectory: true)
        let library = CustomFontStore(directory: requested)
        addTeardownBlock { try? FileManager.default.removeItem(at: canonical.appendingPathComponent(name, isDirectory: true)) }
        XCTAssertNotNil(library.url(forRelativePath: "library-v2.json"))
        XCTAssertEqual(try library.readLibraryState().snapshot.customEntryCount, 0)
        _ = try library.addInstalled(postScriptName: "Helvetica")
        XCTAssertEqual(library.fonts.count, 1)
        XCTAssertNotNil(library.url(forRelativePath: "library-v2.json"))
    }

    func testDirectoryHintRootResolvesAbsentAndExistingButRejectsSymlinks() throws {
        let store = store(directoryHint: true)
        let hintedRoot = try XCTUnwrap(store.directory)
        XCTAssertTrue(hintedRoot.hasDirectoryPath)
        XCTAssertNotNil(store.url(forRelativePath: "library-v2.json"))
        XCTAssertEqual(try store.readLibraryState().snapshot.customEntryCount, 0)
        try FileManager.default.createDirectory(at: hintedRoot, withIntermediateDirectories: true)
        XCTAssertNotNil(store.url(forRelativePath: "library-v2.json"))
        let link = hintedRoot.appendingPathComponent("redirect", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: FileManager.default.temporaryDirectory.path)
        XCTAssertNil(store.url(forRelativePath: "redirect/font.ttf"))
        let linkedStore = CustomFontStore(directory: link)
        XCTAssertNil(linkedStore.url(forRelativePath: "font.ttf"))
        XCTAssertThrowsError(try linkedStore.readLibraryState())
    }

    func testUnsafePathsAndSymlinkAreRejected() throws {
        let store = store()
        for path in ["../x", "/tmp/x", "a/../b", "a//b", "a\\b", "a\0b"] { XCTAssertNil(store.url(forRelativePath: path)) }
        try FileManager.default.createDirectory(at: store.directory!, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: store.directory!.appendingPathComponent("escape").path, withDestinationPath: "/tmp")
        XCTAssertNil(store.url(forRelativePath: "escape/font.ttf"))
        XCTAssertNil(store.url(forRelativePath: "escape/missing-parent/missing-font.ttf"))
        let dangling = store.directory!.appendingPathComponent("dangling", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: dangling.path, withDestinationPath: store.directory!.appendingPathComponent("missing-target").path)
        XCTAssertNil(store.url(forRelativePath: "dangling/font.ttf"))
        XCTAssertNil(store.url(forRelativePath: "dangling"))
        let ordinary = store.directory!.appendingPathComponent("ordinary")
        try Data("not a directory".utf8).write(to: ordinary)
        XCTAssertNil(store.url(forRelativePath: "ordinary/font.ttf"))
        XCTAssertNotNil(store.url(forRelativePath: "new-parent/new-font.ttf"))
    }

    func testLegacyMigrationIsNonDestructiveAndRemovalCommitsMembership() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory!, withIntermediateDirectories: true)
        let font = CustomFont(filename: "Installed-Helvetica", displayName: "Helvetica", postScriptName: "Helvetica", sha256: "", ranges: [[65,90]], installed: true)
        let bytes = try JSONEncoder().encode([font])
        let legacy = store.directory!.appendingPathComponent("fonts.json")
        try bytes.write(to: legacy)
        XCTAssertEqual(store.fonts, [font])
        let generation = store.revision
        try store.remove(font)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
        XCTAssertNotEqual(generation, store.revision)
        XCTAssertTrue(CustomFontStore(directory: store.directory).fonts.isEmpty)
    }

    func testQuotaSixteenAndSeventeenthAndConcurrentWriters() throws {
        let store = store()
        let names = (CTFontManagerCopyAvailablePostScriptNames() as! [String]).filter {
            $0.range(of: "^[A-Za-z0-9._-]{1,100}$", options: .regularExpression) != nil
        }
        var added = 0
        for name in names where added < 16 {
            if (try? store.addInstalled(postScriptName: name)) != nil { added += 1 }
        }
        XCTAssertEqual(added, 16)
        XCTAssertEqual(store.localLibrary.customEntryCount, 16)
        guard let other = names.first(where: { name in !store.fonts.contains { $0.postScriptName == name } }) else { return XCTFail("Need 17 system faces") }
        XCTAssertThrowsError(try store.addInstalled(postScriptName: other))
        XCTAssertEqual(store.fonts.count, 16)
        let concurrent = self.store()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in _ = try? concurrent.addInstalled(postScriptName: "Helvetica") }
        XCTAssertEqual(concurrent.fonts.count, 1)
    }

    func testGstaticReceiptAndEquivalentsRoundTripAndBadShapesFailClosed() throws {
        let store = store()
        let (data, name) = try fixture()
        let license = FontLibraryLicense(id: "l", name: "Runtime fixture", repositoryPath: "test/license", sha256: CustomFontStore.digest(Data("test".utf8)), text: "test")
        let path = "s/roboto/v51/KFOMCnqEu92Fr1ME7kSn66aGLdTylUAMQXC89YmC2DPNWuYjammT.ttf"
        func receipt(fileID: String = "gstatic:" + path, url: String? = "https://fonts.gstatic.com/" + path) -> FontLibraryReceipt {
            var value = FontLibraryReceipt(fileID: fileID, repositoryCommit: String(repeating: "a", count: 40), repositoryPath: "ofl/roboto/Roboto[wdth,wght].ttf",
                                           snapshotDate: "2026-10-23", sha256: CustomFontStore.digest(data), licenses: [license])
            value.sourceKind = .gstatic; value.sourceURL = url
            return value
        }
        let variableHash = String(repeating: "b", count: 64)
        func faces(_ equivalents: [FontLocator]) -> [FontFaceRecord] {
            [FontFaceRecord(id: .init(rawValue: "bold"), family: "Fixture", style: "Bold", postScriptName: name, source: .downloaded,
                            locator: .process(postScriptName: name, variations: [:]), assetID: nil, equivalents: equivalents)]
        }
        let equivalent = FontLocator.file(relativePath: "", sha256: variableHash, faceIndex: 0, variations: ["wght": 700, "wdth": 100])
        // Wrong host, wrong path shape, mismatched id, missing URL: nothing is committed.
        for bad in [receipt(url: "https://fonts.googleapis.com/" + path), receipt(url: "https://fonts.gstatic.com/s/roboto/v51/../x.ttf"),
                    receipt(fileID: "gstatic:s/roboto/v51/other.ttf"), receipt(url: nil)] {
            XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: bad, faces: faces([equivalent]), expectedPostScriptNames: [name]))
        }
        // An equivalent must be a content identity, not a path, and not this file.
        for bad in [FontLocator.file(relativePath: "Custom-x.ttf", sha256: variableHash, faceIndex: 0, variations: [:]),
                    FontLocator.file(relativePath: "", sha256: CustomFontStore.digest(data), faceIndex: 0, variations: [:]),
                    FontLocator.process(postScriptName: name, variations: [:])] {
            XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: receipt(), faces: faces([bad]), expectedPostScriptNames: [name]))
        }
        XCTAssertTrue(store.fonts.isEmpty)
        try store.installGoogleFont(data: data, receipt: receipt(), faces: faces([equivalent]), expectedPostScriptNames: [name])
        let relaunched = CustomFontStore(directory: store.directory)
        let stored = try XCTUnwrap(relaunched.receipt(fileID: "gstatic:" + path))
        XCTAssertEqual(stored.sourceKind, .gstatic)
        XCTAssertEqual(stored.sourceURL, "https://fonts.gstatic.com/" + path)
        XCTAssertEqual(relaunched.localLibrary.faces.first?.equivalents, [equivalent])
    }

    func testInvalidHashMagicAndCancellationDoNotChangeManifest() throws {
        let store = store()
        _ = try store.addInstalled(postScriptName: "Helvetica")
        let before = store.revision
        let data = Data("invalid font".utf8)
        let receipt = FontLibraryReceipt(fileID: "x", repositoryCommit: String(repeating: "a", count: 40), repositoryPath: "ofl/x/x.ttf", snapshotDate: "2026-10-23", sha256: CustomFontStore.digest(data), licenses: [])
        XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: receipt, faces: [], expectedPostScriptNames: ["X"]))
        XCTAssertThrowsError(try store.installGoogleFont(data: data, receipt: receipt, faces: [], expectedPostScriptNames: ["X"], checkCancellation: { throw CancellationError() }))
        XCTAssertEqual(store.revision, before)
        XCTAssertEqual(store.fonts.count, 1)
    }

    func testCorruptManifestFailsClosedInsteadOfOverwritingUserData() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.directory!, withIntermediateDirectories: true)
        let url = store.directory!.appendingPathComponent("library-v2.json")
        let bytes = Data("broken".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try store.addInstalled(postScriptName: "Helvetica"))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testRedirectDelegateRejectsEvenSameHostRedirect() throws {
        let delegate = RejectFontRedirects()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://raw.githubusercontent.com/google/fonts/main/font.ttf")!
        let task = session.dataTask(with: url)
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var called = false
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: url)) { request in
            called = true; XCTAssertNil(request)
        }
        XCTAssertTrue(called)
    }

    func testPinnedURLPolicyRejectsTraversalAndUnpinnedRefs() throws {
        let commit = String(repeating: "a", count: 40)
        for path in ["../font.ttf", "/font.ttf", "ofl//font.ttf", "ofl/%2e%2e/font.ttf", "ofl/f.ttf?secret=x", "ofl\\f.ttf"] {
            XCTAssertThrowsError(try GoogleFontURLPolicy.url(commit: commit, path: path))
        }
        XCTAssertThrowsError(try GoogleFontURLPolicy.url(commit: "main", path: "ofl/test/test.ttf"))
        XCTAssertEqual(try GoogleFontURLPolicy.url(commit: commit, path: "ofl/test/Test[wght].ttf").host, "raw.githubusercontent.com")
    }
}

extension FontLibraryStorageTests {
    private func managementFixture(_ store: CustomFontStore, id: String = "management") throws -> (Data, String) {
        let (data, name) = try fixture()
        let license = FontLibraryLicense(id: "management", name: "Fixture", repositoryPath: "test/license",
                                         sha256: CustomFontStore.digest(Data("test".utf8)), text: "test")
        let receipt = FontLibraryReceipt(fileID: id, repositoryCommit: String(repeating: "a", count: 40),
                                         repositoryPath: "test/font.ttf", snapshotDate: "2026-10-31",
                                         sha256: CustomFontStore.digest(data), licenses: [license])
        let faces = ["Normal", "Condensed Bold Italic"].enumerated().map { index, style in
            FontFaceRecord(id: .init(rawValue: id + "-" + style), family: "Management Fixture", style: style,
                           postScriptName: name, source: .downloaded,
                           locator: .process(postScriptName: name, variations: ["wght": Double(400 + index * 300)]), assetID: nil)
        }
        _ = try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: [name])
        return (data, name)
    }

    func testManagementGroupsActualBinaryNotReceiptsAndVerifiesSize() throws {
        let store = store()
        let (data, name) = try managementFixture(store)
        _ = try managementFixture(store, id: "second-receipt")
        _ = try store.addInstalled(postScriptName: name)
        let snapshot = try store.readManagementSnapshot()
        XCTAssertEqual(snapshot.used, 2)
        XCTAssertEqual(snapshot.files.count, 1)
        XCTAssertEqual(snapshot.installed.count, 1)
        XCTAssertEqual(snapshot.files.first?.receiptIDs.count, 2)
        XCTAssertEqual(snapshot.files.first?.styleCount, 2)
        XCTAssertEqual(snapshot.files.first?.faces.map(\.style), ["Normal", "Condensed Bold Italic"])
        XCTAssertEqual(snapshot.verifiedTotalBytes, Int64(data.count))
        XCTAssertNil(snapshot.installed.first?.verifiedBytes)
        let entry = try XCTUnwrap(snapshot.files.first)
        let binary = try XCTUnwrap(store.url(forRelativePath: entry.filename))
        try Data("corrupt".utf8).write(to: binary)
        let corrupt = try store.readManagementSnapshot()
        XCTAssertEqual(corrupt.used, 2)
        XCTAssertNil(corrupt.files.first?.verifiedBytes)
        XCTAssertNil(corrupt.verifiedTotalBytes)
        try FileManager.default.removeItem(at: binary)
        XCTAssertNil(try store.readManagementSnapshot().files.first?.verifiedBytes)
    }

    func testManagementRemovalKeepsAllRulesOtherMembershipAndImmutableBytes() throws {
        let store = store()
        let (data, name) = try managementFixture(store)
        _ = try store.addInstalled(postScriptName: name)
        let snapshot = try store.readManagementSnapshot()
        let entry = try XCTUnwrap(snapshot.files.first)
        let reference = try XCTUnwrap(entry.faces.first.flatMap(FontFaceReference.init(record:)))
        let rules = [FontRule(id: "kept", selector: .codePoint(65), face: reference)]
        let encodedRules = try XCTUnwrap(FontRuleStore.encode(rules))
        let binary = try XCTUnwrap(store.url(forRelativePath: entry.filename))
        try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: rules, readRules: { rules })
        XCTAssertEqual(try store.readManagementSnapshot().used, 1)
        XCTAssertEqual(try store.readManagementSnapshot().installed.count, 1)
        XCTAssertEqual(try Data(contentsOf: binary), data)
        XCTAssertEqual(FontRuleStore.encode(rules), encodedRules)
        XCTAssertNil(store.receipt(fileID: "management"))
    }

    func testManagementCancelAndStaleWritersNeverRemoveMembership() throws {
        let store = store()
        let (_, name) = try managementFixture(store)
        let snapshot = try store.readManagementSnapshot()
        let entry = try XCTUnwrap(snapshot.files.first)
        var checks = 0
        XCTAssertThrowsError(try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: [], readRules: { [] }, checkCancellation: {
            checks += 1
            if checks == 2 { throw CancellationError() }
        }))
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(store.revision, snapshot.generation)
        let otherWriter = CustomFontStore(directory: store.directory)
        _ = try otherWriter.addInstalled(postScriptName: name)
        XCTAssertThrowsError(try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: [], readRules: { [] }))
        XCTAssertEqual(try store.readManagementSnapshot().used, 2)
        let fresh = try store.readManagementSnapshot()
        let reference = try XCTUnwrap(entry.faces.first.flatMap(FontFaceReference.init(record:)))
        let addedRule = FontRule(id: "new", selector: .codePoint(65), face: reference)
        var reads = 0
        XCTAssertThrowsError(try store.removeManagedEntry(entry, expectedGeneration: fresh.generation, expectedRules: [], readRules: {
            reads += 1
            return reads == 1 ? [] : [addedRule]
        }))
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(store.revision, fresh.generation)
        XCTAssertThrowsError(try store.removeManagedEntry(entry, expectedGeneration: fresh.generation, expectedRules: [], readRules: { nil }))
        XCTAssertEqual(store.revision, fresh.generation)
    }

    func testManagementCorruptManifestIsNotAnEmptyLibraryAndCannotBeRemoved() throws {
        let store = store()
        _ = try managementFixture(store)
        let snapshot = try store.readManagementSnapshot()
        let entry = try XCTUnwrap(snapshot.files.first)
        let url = try XCTUnwrap(store.directory).appendingPathComponent("library-v2.json")
        let corrupt = Data("not a manifest".utf8)
        try corrupt.write(to: url, options: .atomic)
        XCTAssertThrowsError(try store.readManagementSnapshot())
        XCTAssertThrowsError(try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: [], readRules: { [] }))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testManagementInstalledReferencesUseExistingSixteenEntryQuota() throws {
        let store = store()
        let (data, _) = try fixture()
        var installedNames: [String] = []
        let names = CTFontManagerCopyAvailablePostScriptNames() as! [String]
        for name in names where installedNames.count < CustomFontStore.maximumFonts {
            do {
                _ = try store.addInstalled(postScriptName: name)
                installedNames.append(name)
            } catch CustomFontStore.Failure.notAFont { continue }
        }
        XCTAssertEqual(installedNames.count, 16)
        let snapshot = try store.readManagementSnapshot()
        XCTAssertEqual(snapshot.used, 16)
        XCTAssertEqual(snapshot.files.count, 0)
        XCTAssertEqual(snapshot.installed.count, 16)
        XCTAssertThrowsError(try store.add(data))
        // Existing references remain idempotent even at capacity.
        _ = try store.addInstalled(postScriptName: XCTUnwrap(installedNames.first))
        let entry = try XCTUnwrap(snapshot.installed.first)
        try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: [], readRules: { [] })
        XCTAssertEqual(try store.readManagementSnapshot().used, 15)
        XCTAssertEqual(CTFontCopyPostScriptName(CTFontCreateWithName(installedNames[0] as CFString, 12, nil)) as String, installedNames[0])
        _ = try store.add(data)
        XCTAssertEqual(try store.readManagementSnapshot().used, 16)
    }
}
#endif
