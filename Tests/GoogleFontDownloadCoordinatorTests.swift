#if canImport(UIKit)
import XCTest
import CoreText
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

/// Serves the pinned Roboto variable file and its gstatic Condensed Bold
/// instance, recording every URL asked for.
private actor PinnedFixtureTransport: GoogleFontTransport {
    let files: [URL: Data]
    private(set) var requested: [URL] = []
    init(files: [URL: Data]) { self.files = files }
    func fetch(url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data {
        requested.append(url)
        guard let data = files[url] else { throw FontLibraryFailure.transport }
        progress(Int64(data.count), Int64(data.count))
        return data
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
        let activeState = coordinator.states["file"]
        coordinator.refreshLibrary()
        XCTAssertEqual(coordinator.states["file"], activeState, "Refresh must not replace active progress with Ready")
        try await coordinator.cancel(fileID: "file")
        _ = try? await first.value; _ = try? await second.value
        XCTAssertEqual(coordinator.states["file"], .cancelled)
        XCTAssertTrue(store.fonts.isEmpty)
        try await coordinator.remove(fileID: "file")
        XCTAssertEqual(coordinator.states["file"], .ready)
    }

    // MARK: 1.4 option B: pinned single-style instances, both files kept (design §8)

    private static let robotoFile = "ofl/roboto/Roboto[wdth,wght].ttf"
    private static let instancePath = "s/roboto/v51/KFOMCnqEu92Fr1ME7kSn66aGLdTylR4MQXC89YmC2DPNWuYjammT.ttf"

    private func robotoSetup(duplicateReceipt: Bool = false) throws -> (GoogleFontDownloadCoordinator, CustomFontStore, PinnedFixtureTransport, GoogleFontInstance) {
        let variable = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "Roboto-Pinned", withExtension: "ttf")))
        let license = try String(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "OFL", withExtension: "txt")), encoding: .utf8)
        // Not a bundle resource: read beside this source file.
        let instanceData = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Roboto/RobotoCondensed-Bold-gstatic.ttf"))
        let instance = GoogleFontInstance(path: Self.instancePath, bytes: Int64(instanceData.count), sha256: CustomFontStore.digest(instanceData),
                                          postScriptName: "RobotoCondensed-Bold")
        XCTAssertEqual(instance.sha256, "486878765ccabadd9bffe0eca15dd8c565cea25137bdc25ee075d477a79333b2")
        let file = GoogleFontFile(id: Self.robotoFile, repositoryPath: Self.robotoFile, bytes: Int64(variable.count),
                                  sha256: CustomFontStore.digest(variable), expectedPostScriptNames: ["Roboto-Regular"], licenseIDs: ["ofl/roboto/OFL.txt"])
        let family = GoogleFontFamily(id: "ofl/roboto", name: "Roboto", styles: [
            .init(id: "regular", name: "Regular", fileID: file.id, postScriptName: "Roboto-Regular", variationInstance: ["wght": 400, "wdth": 100]),
            .init(id: "condensedBold", name: "Condensed Bold", fileID: file.id, postScriptName: "Roboto-CondensedBold",
                  variationInstance: ["wght": 700, "wdth": 75], instance: instance)])
        let duplicate = GoogleFontFile(id: "ofl/roboto/Duplicate.ttf", repositoryPath: "ofl/roboto/Duplicate.ttf", bytes: file.bytes,
                                       sha256: file.sha256, expectedPostScriptNames: file.expectedPostScriptNames, licenseIDs: file.licenseIDs)
        let duplicateFamily = GoogleFontFamily(id: "duplicate", name: "Duplicate receipt fixture", styles: [
            .init(id: "duplicateRegular", name: "Regular", fileID: duplicate.id, postScriptName: "Roboto-Regular",
                  variationInstance: ["wght": 400, "wdth": 100])])
        let catalog = GoogleFontCatalogSnapshot(schemaVersion: 2, repositoryCommit: GoogleFontCatalog.trustedRepositoryCommit, snapshotDate: "2026-10-23",
                                                families: duplicateReceipt ? [family, duplicateFamily] : [family],
                                                files: duplicateReceipt ? [file, duplicate] : [file],
                                                licenses: [GoogleFontLicense(id: "ofl/roboto/OFL.txt", name: "SIL Open Font License 1.1",
                                                                             repositoryPath: "ofl/roboto/OFL.txt",
                                                                             sha256: CustomFontStore.digest(Data(license.utf8)), text: license)])
        let trusted = try GoogleFontCatalog(snapshot: catalog)
        var fixtureFiles = [try trusted.downloadURL(for: file): variable,
                            try trusted.downloadURL(for: instance): instanceData]
        if duplicateReceipt { fixtureFiles[try trusted.downloadURL(for: duplicate)] = variable }
        let transport = PinnedFixtureTransport(files: fixtureFiles)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = CustomFontStore(directory: directory)
        return (GoogleFontDownloadCoordinator(catalog: catalog, store: store, transport: transport), store, transport, instance)
    }

    private func reference(_ store: CustomFontStore, where match: (FontFaceRecord) -> Bool) throws -> FontFaceReference {
        try XCTUnwrap(store.localLibrary.faces.first(where: match).flatMap(FontFaceReference.init(record:)))
    }


    func testRefreshAfterManagedRemovalMakesStyleDownloadableAgainAndKeepsOtherFile() async throws {
        let (coordinator, store, transport, instance) = try robotoSetup()
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        try await coordinator.download(styleID: "regular", scope: .file)
        let snapshot = try store.readManagementSnapshot()
        let entry = try XCTUnwrap(snapshot.files.first { $0.receiptIDs.contains(instance.id) })
        try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: [], readRules: { [] })
        XCTAssertEqual(coordinator.states[instance.id], .downloaded(assetID: entry.filename), "Reproduce the stale catalog row")
        coordinator.refreshLibrary()
        XCTAssertEqual(coordinator.states[instance.id], .ready, "Return from Manage File offers Download, not Manage File")
        guard case .downloaded = coordinator.states[Self.robotoFile] else { return XCTFail("Unrelated shared file lost") }
        XCTAssertEqual(coordinator.freeFileSpaces, CustomFontStore.maximumFonts - 1)
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        let requested = await transport.requested
        XCTAssertEqual(requested.count, 3, "Explicit redownload reaches transport and republishes membership")
        XCTAssertEqual(coordinator.states[instance.id], .downloaded(assetID: entry.filename))
        XCTAssertNotNil(store.receipt(fileID: instance.id))
    }

    func testRefreshClearsEveryRemovedReceiptSharingOneBinary() async throws {
        let (coordinator, store, _, _) = try robotoSetup(duplicateReceipt: true)
        let duplicateID = "ofl/roboto/Duplicate.ttf"
        try await coordinator.download(styleID: "regular")
        try await coordinator.download(styleID: "duplicateRegular")
        let snapshot = try store.readManagementSnapshot()
        let entry = try XCTUnwrap(snapshot.files.first)
        XCTAssertEqual(snapshot.used, 1)
        XCTAssertEqual(Set(entry.receiptIDs), [Self.robotoFile, duplicateID])
        try store.removeManagedEntry(entry, expectedGeneration: snapshot.generation, expectedRules: [], readRules: { [] })
        coordinator.refreshLibrary()
        XCTAssertEqual(coordinator.states[Self.robotoFile], .ready)
        XCTAssertEqual(coordinator.states[duplicateID], .ready)
        XCTAssertEqual(coordinator.freeFileSpaces, CustomFontStore.maximumFonts)
    }

    func testRefreshReportsCorruptLibraryWithoutPretendingDownloadWasRemoved() async throws {
        let (coordinator, store, _, instance) = try robotoSetup()
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        let before = coordinator.states[instance.id]
        let manifestURL = try XCTUnwrap(store.directory).appendingPathComponent("library-v2.json")
        let valid = try Data(contentsOf: manifestURL)
        try Data("corrupt".utf8).write(to: manifestURL, options: .atomic)
        coordinator.refreshLibrary()
        XCTAssertNotNil(coordinator.libraryFailure)
        XCTAssertEqual(coordinator.states[instance.id], before)
        try valid.write(to: manifestURL, options: .atomic)
        coordinator.refreshLibrary()
        XCTAssertNil(coordinator.libraryFailure)
        XCTAssertEqual(coordinator.states[instance.id], before)
    }

    func testInstanceDownloadIsOneSmallFileFromThePinnedGstaticPath() async throws {
        let (coordinator, store, transport, instance) = try robotoSetup()
        XCTAssertEqual(coordinator.freeFileSpaces, CustomFontStore.maximumFonts)
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        let requested = await transport.requested
        XCTAssertEqual(requested.map(\.absoluteString), ["https://fonts.gstatic.com/" + Self.instancePath])
        XCTAssertEqual(coordinator.states[instance.id], .downloaded(assetID: "Custom-\(instance.sha256).ttf"))
        XCTAssertEqual(coordinator.states[Self.robotoFile], .ready, "The shared file isn't touched")
        XCTAssertEqual(coordinator.freeFileSpaces, CustomFontStore.maximumFonts - 1)
        let receipt = try XCTUnwrap(store.receipt(fileID: instance.id))
        XCTAssertEqual(receipt.sourceKind, .gstatic)
        XCTAssertEqual(receipt.sourceURL, "https://fonts.gstatic.com/" + Self.instancePath)
        XCTAssertEqual(receipt.repositoryPath, Self.robotoFile, "Validated against the pinned repository file")
        XCTAssertEqual(receipt.sha256, instance.sha256)
        XCTAssertEqual(receipt.licenses.map(\.id), ["ofl/roboto/OFL.txt"])
        // The face record carries the static file's own name and the variable instance as its equivalent.
        let face = try XCTUnwrap(store.localLibrary.faces.first)
        XCTAssertEqual(face.postScriptName, "RobotoCondensed-Bold")
        XCTAssertEqual(face.family, "Roboto")
        XCTAssertEqual(face.style, "Condensed Bold")
        XCTAssertTrue(face.isStaticFile)
        XCTAssertEqual(face.equivalents, [.file(relativePath: "", sha256: "d7598e12c5dbef095ff8272cfc55da0250bd07fbdecbac8a530b9b277872a134",
                                                faceIndex: 0, variations: ["wght": 700, "wdth": 75])])
        let loaded = try FontRuleFaceLoader(library: store).load(FontFaceReference(record: face)!).get()
        XCTAssertEqual(loaded.postScriptName, "RobotoCondensed-Bold")
    }

    func testSharedFileNeverRemovesTheSeparateDownloadAndEitherRemovalKeepsTheStyle() async throws {
        let (coordinator, store, _, instance) = try robotoSetup()
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        let instanceReference = try reference(store) { $0.isStaticFile }
        try await coordinator.download(styleID: "condensedBold", scope: .file)
        // Both kept; the shared file counted +1 (§10 check 11).
        XCTAssertEqual(coordinator.freeFileSpaces, CustomFontStore.maximumFonts - 2)
        guard case .downloaded = coordinator.states[instance.id] else { return XCTFail("Separate download removed") }
        guard case .downloaded = coordinator.states[Self.robotoFile] else { return XCTFail("Shared file missing") }
        XCTAssertEqual(store.fonts.count, 2)
        let variableReference = try reference(store) { $0.postScriptName == "Roboto-CondensedBold" }
        // Shown once: the variable file's Condensed Bold collapses behind the static one; Regular stays.
        let shown = FontFaceRecord.collapsingEquivalents(store.localLibrary.faces)
        XCTAssertEqual(shown.map(\.postScriptName).sorted(), ["Roboto-Regular", "RobotoCondensed-Bold"])
        // The same face either way; the own (static) file draws it.
        XCTAssertTrue(variableReference.isSameFace(as: store.localLibrary.faces.first { $0.isStaticFile }!))
        XCTAssertEqual(variableReference.candidates(in: store.localLibrary.faces).first?.postScriptName, "RobotoCondensed-Bold")
        let loader = FontRuleFaceLoader(library: store)
        XCTAssertEqual(try loader.load(variableReference).get().postScriptName, "RobotoCondensed-Bold")
        XCTAssertEqual(try loader.load(instanceReference).get().postScriptName, "RobotoCondensed-Bold")

        // Remove the separate file: both saved references still resolve, now to the variable instance.
        try await coordinator.remove(fileID: instance.id)
        XCTAssertEqual(coordinator.states[instance.id], .ready)
        guard case .downloaded = coordinator.states[Self.robotoFile] else { return XCTFail("Removing one file removed the other") }
        XCTAssertEqual(coordinator.freeFileSpaces, CustomFontStore.maximumFonts - 1)
        for saved in [variableReference, instanceReference] {
            let loaded = try loader.load(saved).get()
            XCTAssertEqual(FontRuleFaceLoader.effectiveCoordinates(loaded.reference)[NSNumber(value: 0x7767_6874)]?.doubleValue, 700)
        }

        // Download it again, then remove the shared file instead: both references resolve to the separate file.
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        try await coordinator.remove(fileID: Self.robotoFile)
        XCTAssertEqual(store.fonts.count, 1)
        for saved in [variableReference, instanceReference] {
            XCTAssertEqual(try loader.load(saved).get().postScriptName, "RobotoCondensed-Bold")
        }
        // Saved references are values; nothing rewrote them.
        XCTAssertEqual(variableReference.postScriptName, "Roboto-CondensedBold")
        XCTAssertEqual(instanceReference.postScriptName, "RobotoCondensed-Bold")
    }

    /// Reproduce a library-v2.json actually shaped like 1.3: no equivalents
    /// on any face, and no 1.4 source fields in repository receipts.
    private func makeManifestLegacy(_ store: CustomFontStore) throws -> Data {
        let url = try XCTUnwrap(store.directory).appendingPathComponent("library-v2.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var downloads = try XCTUnwrap(json["downloads"] as? [[String: Any]])
        for i in downloads.indices {
            var faces = try XCTUnwrap(downloads[i]["faces"] as? [[String: Any]])
            for j in faces.indices { faces[j].removeValue(forKey: "equivalents") }
            downloads[i]["faces"] = faces
            var receipt = try XCTUnwrap(downloads[i]["receipt"] as? [String: Any])
            receipt.removeValue(forKey: "sourceKind"); receipt.removeValue(forKey: "sourceURL")
            downloads[i]["receipt"] = receipt
        }
        json["downloads"] = downloads
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        XCTAssertTrue(try store.readManifest().downloads.flatMap(\.faces).allSatisfy { $0.equivalents == nil })
        return data
    }

    func testLegacySharedManifestAndNewOwnDownloadCollapseAndKeepBothSavedReferencesAfterEitherRemoval() async throws {
        try await checkLegacyOverlap(importOwn: false)
    }

    func testLegacySharedManifestAndImportedPinnedOwnFileCollapseAndKeepBothReferencesAfterEitherRemoval() async throws {
        try await checkLegacyOverlap(importOwn: true)
    }

    private func checkLegacyOverlap(importOwn: Bool) async throws {
        let (coordinator, store, transport, instance) = try robotoSetup()
        try await coordinator.download(styleID: "condensedBold", scope: .file)
        let legacyData = try makeManifestLegacy(store)
        let manifestURL = try XCTUnwrap(store.directory).appendingPathComponent("library-v2.json")
        let generation = store.revision
        let sharedID = try XCTUnwrap(store.localLibrary.faces.first { $0.postScriptName == "Roboto-CondensedBold" }).id
        let variableReference = try reference(store) { $0.id == sharedID }
        let binaryURL = try XCTUnwrap(store.url(forRelativePath: XCTUnwrap(store.fonts.first).filename))
        let binaryBefore = try Data(contentsOf: binaryURL)
        XCTAssertEqual(try store.readLibraryState().snapshot.faces.first { $0.id == sharedID }?.equivalents,
                       [.file(relativePath: "", sha256: instance.sha256, faceIndex: 0, variations: [:])])
        XCTAssertEqual(try Data(contentsOf: manifestURL), legacyData, "Read-time enrichment never migrates the manifest")
        // Already downloaded: no transport, no manifest generation/receipt rewrite.
        try await coordinator.download(styleID: "condensedBold", scope: .file)
        let earlyRequests = await transport.requested
        XCTAssertEqual(earlyRequests.count, 1)
        XCTAssertEqual(store.revision, generation)
        XCTAssertEqual(try Data(contentsOf: manifestURL), legacyData)

        let instanceData = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Roboto/RobotoCondensed-Bold-gstatic.ttf"))
        func importInstance() throws { _ = try store.add(instanceData) }
        if importOwn { try importInstance() }
        else { try await coordinator.download(styleID: "condensedBold", scope: .instance) }
        let ownRecord = try XCTUnwrap(store.localLibrary.faces.first { $0.isStaticFile })
        let ownReference = try XCTUnwrap(FontFaceReference(record: ownRecord))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let savedReferences = try encoder.encode([variableReference, ownReference])
        // The references contain no derived aliases and remain byte-for-byte values.
        XCTAssertEqual(store.fonts.count, 2)
        XCTAssertEqual(FontFaceRecord.collapsingEquivalents(store.localLibrary.faces).count, 2, "Regular and Condensed Bold, not three faces")
        XCTAssertEqual(FontPickerInventory.entries(store.localLibrary.faces, evidence: nil).count, 2)
        let loader = FontRuleFaceLoader(library: CustomFontStore(directory: store.directory)) // relaunch reader
        for saved in [variableReference, ownReference] {
            XCTAssertEqual(try loader.load(saved).get().postScriptName, instance.postScriptName)
        }

        if importOwn { try store.remove(try XCTUnwrap(store.fonts.first { $0.sha256 == instance.sha256 })) }
        else { try await coordinator.remove(fileID: instance.id) }
        XCTAssertEqual(store.fonts.count, 1)
        for saved in [variableReference, ownReference] {
            let font = try loader.load(saved).get().reference
            let axes = FontRuleFaceLoader.effectiveCoordinates(font)
            XCTAssertEqual(axes[NSNumber(value: 0x7767_6874)]?.doubleValue, 700)
            XCTAssertEqual(axes[NSNumber(value: 0x7764_7468)]?.doubleValue, 75)
        }
        XCTAssertEqual(try Data(contentsOf: binaryURL), binaryBefore)
        XCTAssertEqual(store.localLibrary.faces.first { $0.id == sharedID }?.id, sharedID)

        if importOwn { try importInstance() }
        else { try await coordinator.download(styleID: "condensedBold", scope: .instance) }
        try await coordinator.remove(fileID: Self.robotoFile)
        XCTAssertEqual(store.fonts.count, 1)
        for saved in [variableReference, ownReference] {
            XCTAssertEqual(try loader.load(saved).get().postScriptName, instance.postScriptName)
        }
        XCTAssertEqual(try encoder.encode([variableReference, ownReference]), savedReferences)
        let requests = await transport.requested
        XCTAssertEqual(requests.count, importOwn ? 1 : 3, "No read/resolve operation starts networking")
    }

    func testPinnedOwnAndSharedInstancesAgreeOnCoverageRevisionAndMetrics() async throws {
        let (coordinator, store, _, _) = try robotoSetup()
        try await coordinator.download(styleID: "condensedBold", scope: .file)
        try await coordinator.download(styleID: "condensedBold", scope: .instance)
        let variable = try reference(store) { $0.postScriptName == "Roboto-CondensedBold" }
        let own = try reference(store) { $0.isStaticFile }
        let loader = FontRuleFaceLoader(library: store)
        // Bypass preference for the own file: compare the two real binaries.
        let sharedFont = try loader.load(variable, at: XCTUnwrap(loader.locate(variable))).get().reference
        let ownFont = try loader.load(own, at: XCTUnwrap(loader.locate(own))).get().reference
        XCTAssertTrue(CFEqual(CTFontCopyCharacterSet(sharedFont), CTFontCopyCharacterSet(ownFont)))
        let sharedHead = try XCTUnwrap(CTFontCopyTable(sharedFont, CTFontTableTag(0x6865_6164), []) as Data?)
        let ownHead = try XCTUnwrap(CTFontCopyTable(ownFont, CTFontTableTag(0x6865_6164), []) as Data?)
        XCTAssertEqual(sharedHead.subdata(in: 4..<8), ownHead.subdata(in: 4..<8), "Pinned fontRevision matches")
        var characters = Array("Ag09éΩЖ".utf16)
        var sharedGlyphs = [CGGlyph](repeating: 0, count: characters.count)
        var ownGlyphs = sharedGlyphs
        XCTAssertTrue(CTFontGetGlyphsForCharacters(sharedFont, &characters, &sharedGlyphs, characters.count))
        XCTAssertTrue(CTFontGetGlyphsForCharacters(ownFont, &characters, &ownGlyphs, characters.count))
        var sharedAdvances = [CGSize](repeating: .zero, count: characters.count)
        var ownAdvances = sharedAdvances
        CTFontGetAdvancesForGlyphs(sharedFont, .horizontal, &sharedGlyphs, &sharedAdvances, characters.count)
        CTFontGetAdvancesForGlyphs(ownFont, .horizontal, &ownGlyphs, &ownAdvances, characters.count)
        for i in characters.indices { XCTAssertEqual(sharedAdvances[i].width, ownAdvances[i].width, accuracy: 0.5) }
    }

    func testAStyleWithoutAnInstanceCannotDownloadOneAndUnknownInstancesAreRejected() async throws {
        let (coordinator, _, transport, _) = try robotoSetup()
        do { try await coordinator.download(styleID: "regular", scope: .instance); XCTFail("No verified instance") } catch { }
        do { try await coordinator.remove(fileID: "gstatic:s/roboto/v51/Other.ttf"); XCTFail("Not in the catalog") } catch { }
        let requested = await transport.requested
        XCTAssertTrue(requested.isEmpty)
    }

    func testURLPolicyPinsBothHostsExactly() throws {
        XCTAssertTrue(GoogleFontURLPolicy.isPinned(URL(string: "https://fonts.gstatic.com/" + Self.instancePath)!))
        XCTAssertTrue(GoogleFontURLPolicy.isPinned(try GoogleFontURLPolicy.url(commit: GoogleFontCatalog.trustedRepositoryCommit, path: Self.robotoFile)))
        for bad in ["http://fonts.gstatic.com/" + Self.instancePath, "https://fonts.gstatic.com:443/" + Self.instancePath,
                    "https://fonts.gstatic.com/" + Self.instancePath + "?x=1", "https://fonts.googleapis.com/" + Self.instancePath,
                    "https://fonts.gstatic.com/s/roboto/v51/../x.ttf", "https://fonts.gstatic.com/s/Roboto/v51/x.ttf",
                    "https://fonts.gstatic.com/s/roboto/v51/x.woff2", "https://user@fonts.gstatic.com/" + Self.instancePath,
                    "https://example.com/" + Self.instancePath] {
            XCTAssertFalse(GoogleFontURLPolicy.isPinned(URL(string: bad)!), bad)
        }
    }
}
#endif
