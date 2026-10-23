#if canImport(UIKit)
import XCTest
import UIKit
import CoreText
import CryptoKit
@testable import Uniboard

final class FontComparisonEngineTests: XCTestCase {
    private struct FixtureProvider: FontInventoryProviding {
        let faces: [FontFaceRecord]
        var urls: [FontFaceID: URL] = [:]
        func snapshot() throws -> FontLibrarySnapshot { FontLibrarySnapshot(generation: "fixture", faces: faces, customEntryCount: 0) }
        func fileURL(for face: FontFaceRecord) -> URL? { urls[face.id] }
    }
    private func face(_ name: String = "Helvetica") -> FontFaceRecord {
        let font = CTFontCreateWithName(name as CFString, 64, nil)
        let ps = CTFontCopyPostScriptName(font) as String
        let locator = FontLocator.process(postScriptName: ps, variations: [:])
        return FontFaceRecord(id: PublicFontInventory.identity(locator), family: CTFontCopyFamilyName(font) as String, style: "Regular", postScriptName: ps, source: .available, locator: locator, assetID: nil)
    }
    private func inspect(_ text: String) -> FontInspection { FontInspection(originalText: text, characterName: "Fixture") }
    private func final(_ engine: FontComparisonEngine, _ inspection: FontInspection) async throws -> FontScanUpdate {
        var result: FontScanUpdate?
        for try await update in await engine.scan(inspection) { result = update }
        return try XCTUnwrap(result)
    }
    func testExactUTF8AndPresentationKeys() async throws {
        XCTAssertEqual("é", "e\u{301}") // Swift String hashing would conflate these.
        let engine = FontComparisonEngine(provider: FixtureProvider(faces: [face()]))
        _ = try await final(engine, inspect("é"))
        _ = try await final(engine, inspect("e\u{301}"))
        let count = await engine.cachedResultCount
        XCTAssertEqual(count, 2)
        let text = FontInspection(originalText: "❤", characterName: "Heart", presentation: .text)
        let emoji = FontInspection(originalText: "❤", characterName: "Heart", presentation: .emoji)
        XCTAssertEqual(Array(text.previewText.utf8), Array("❤\u{FE0E}".utf8))
        XCTAssertEqual(Array(emoji.previewText.utf8), Array("❤\u{FE0F}".utf8))
        let retained = FontInspection(originalText: "❤\u{FE0E}", characterName: "Heart", presentation: .emoji)
        XCTAssertEqual(Array(retained.previewText.utf8), Array("❤\u{FE0F}".utf8))
        XCTAssertEqual(Array(retained.originalText.utf8), Array("❤\u{FE0E}".utf8))
        XCTAssertTrue(retained.canChoosePresentation)
        let sequence = FontInspection(originalText: "👩‍💻", characterName: "Technologist", presentation: .text)
        XCTAssertFalse(sequence.canChoosePresentation)
        XCTAssertEqual(Array(sequence.previewText.utf8), Array(sequence.originalText.utf8))
        _ = try await final(engine, text); _ = try await final(engine, emoji)
        let updatedCount = await engine.cachedResultCount
        XCTAssertEqual(updatedCount, 4)
    }
    func testCoreTextFallbackIsNotCreditedToRequestedFace() throws {
        let requested = face()
        let provider = FixtureProvider(faces: [requested])
        let resource = try XCTUnwrap(FontLineVerifier.load(requested, size: 64, provider: provider))
        defer { withExtendedLifetime(resource) {} }
        let font = resource.font
        var foundFallback = false
        for text in ["😀", "漢", "\u{20000}", "अ"] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            let hasFallback = runs.contains { run in
                let actual = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                return CTFontCopyPostScriptName(actual) as String != requested.postScriptName
            }
            if hasFallback {
                foundFallback = true
                XCTAssertNotEqual(FontLineVerifier.line(face: requested, inspection: inspect(text), size: 64, provider: provider).0, .verified)
            }
        }
        XCTAssertTrue(foundFallback, "Fixture must actually exercise CoreText fallback on this runtime")
        XCTAssertEqual(FontLineVerifier.line(face: requested, inspection: inspect("A"), size: 64, provider: provider).0, .verified)
    }
    func testSequenceAndInvisibleProofIsConservative() {
        let requested = face("AppleColorEmoji")
        let provider = FixtureProvider(faces: [requested])
        for text in ["👩‍💻", "क्ष", "❤\u{FE0E}", "❤\u{FE0F}", "🇬🇧", "1\u{FE0F}\u{20E3}"] {
            XCTAssertTrue(inspect(text).requiresUnprovedShaping)
            XCTAssertNotEqual(FontLineVerifier.line(face: requested, inspection: inspect(text), size: 64, provider: provider).0, .verified)
        }
        for text in ["\u{200D}", "\u{0000}", "\u{200B}", " ", "\u{FE0F}"] {
            XCTAssertFalse(inspect(text).isApplicable)
            XCTAssertEqual(FontLineVerifier.line(face: requested, inspection: inspect(text), size: 64, provider: provider).0, .unknown)
        }
        XCTAssertTrue(inspect("\u{301}").usesDottedCircle)
        XCTAssertEqual(Array(inspect("\u{301}").originalText.utf8), [0xCC, 0x81])
        XCTAssertFalse(inspect("\u{20000}").requiresUnprovedShaping)
        XCTAssertEqual(inspect("\u{20000}").originalText.utf16.count, 2)
    }
    func testMarkScaffoldDoesNotGetCopiedAndActualMarkMustBeVerified() {
        let requested = face()
        let inspection = inspect("\u{301}")
        let result = FontLineVerifier.line(face: requested, inspection: inspection, size: 64, provider: FixtureProvider(faces: [requested]))
        XCTAssertEqual(inspection.originalText.unicodeScalars.map(\.value), [0x301])
        if result.0 == .verified { XCTAssertNotNil(result.1) }
        // Unassigned combining-diacritic-block scalar cannot become supported through its circle.
        XCTAssertNotEqual(FontLineVerifier.line(face: requested, inspection: inspect("\u{0378}"), size: 64, provider: FixtureProvider(faces: [requested])).0, .verified)
    }
    func testFileIdentityDoesNotCollapseSamePostScriptNameOrVariation() {
        let a = FontLocator.file(relativePath: "a.ttf", sha256: "aaa", faceIndex: 0, variations: [:])
        let alias = FontLocator.file(relativePath: "alias.ttf", sha256: "aaa", faceIndex: 0, variations: [:])
        let b = FontLocator.file(relativePath: "b.ttf", sha256: "bbb", faceIndex: 0, variations: [:])
        XCTAssertEqual(PublicFontInventory.identity(a), PublicFontInventory.identity(alias))
        XCTAssertNotEqual(PublicFontInventory.identity(a), PublicFontInventory.identity(b))
        XCTAssertNotEqual(PublicFontInventory.identity(a), PublicFontInventory.identity(.file(relativePath: "a.ttf", sha256: "aaa", faceIndex: 1, variations: [:])))
        XCTAssertNotEqual(PublicFontInventory.identity(a), PublicFontInventory.identity(.file(relativePath: "a.ttf", sha256: "aaa", faceIndex: 0, variations: ["2003265652": 700])))
    }
    func testDirectFileLoadingWithSameNameAndDifferentBinaryIdentity() throws {
        let original = face()
        let font = CTFontCreateWithName(original.postScriptName as CFString, 64, nil)
        guard let source = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
              let data = try? Data(contentsOf: source),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(source as CFURL) as? [CTFontDescriptor], descriptors.count == 1 else {
            throw XCTSkip("Runtime does not expose a readable single-face font fixture")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var records: [FontFaceRecord] = [], urls: [FontFaceID: URL] = [:]
        for index in 0..<2 {
            var bytes = data
            // Trailing bytes change file identity, not its real font name or tables.
            bytes.append(contentsOf: Array(repeating: UInt8(0), count: index * 4))
            let url = directory.appendingPathComponent("fixture-\(index).ttf")
            try bytes.write(to: url)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let locator = FontLocator.file(relativePath: url.lastPathComponent, sha256: hash, faceIndex: 0, variations: [:])
            let record = FontFaceRecord(id: PublicFontInventory.identity(locator), family: original.family, style: original.style, postScriptName: original.postScriptName, source: .imported, locator: locator, assetID: nil)
            records.append(record); urls[record.id] = url
        }
        XCTAssertNotEqual(records[0].id, records[1].id)
        XCTAssertEqual(records[0].postScriptName, records[1].postScriptName)
        let provider = FixtureProvider(faces: records, urls: urls)
        for record in records {
            let loaded = try XCTUnwrap(FontLineVerifier.load(record, size: 64, provider: provider))
            XCTAssertEqual(CTFontCopyPostScriptName(loaded.font) as String, original.postScriptName)
            XCTAssertEqual(FontLineVerifier.line(face: record, inspection: inspect("A"), size: 64, provider: provider).0, .verified)
        }
    }
    func testFullPublicInventoryExceedsSavedPreferenceLimit() async throws {
        let inventory = try await FontComparisonEngine().inventorySnapshot()
        XCTAssertGreaterThan(inventory.faces.count, 16)
        XCTAssertEqual(Set(inventory.faces.map(\.id)).count, inventory.faces.count)
        let publicNames = Set(CTFontManagerCopyAvailablePostScriptNames() as! [String])
        XCTAssertTrue(publicNames.isSubset(of: Set(inventory.faces.map(\.postScriptName))), "Every public face must survive enumeration")
        let engine = FontComparisonEngine(provider: FixtureProvider(faces: inventory.faces), cacheLimit: 8)
        let update = try await final(engine, inspect("A"))
        XCTAssertEqual(update.checked, inventory.faces.count)
        XCTAssertEqual(update.total, inventory.faces.count)
        XCTAssertTrue(update.isComplete)
        let cached = await engine.cachedResultCount
        XCTAssertLessThanOrEqual(cached, 8)
    }
    func testInvalidationSupersedesOldGenerationAndClearsCache() async throws {
        let engine = FontComparisonEngine(provider: FixtureProvider(faces: Array(repeating: face(), count: 500)))
        let stream = await engine.scan(inspect("A"))
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        await engine.invalidate()
        do {
            while let update = try await iterator.next() { XCTAssertFalse(update.isComplete) }
        } catch { XCTAssertTrue(error is CancellationError) }
        let final = try await final(engine, inspect("Ω"))
        XCTAssertGreaterThan(final.generation, try XCTUnwrap(first).generation)
        await engine.invalidate()
        let count = await engine.cachedResultCount
        XCTAssertEqual(count, 0)
    }
    private actor CountingProvider: FontInventoryProviding {
        nonisolated let faces: [FontFaceRecord]
        private(set) var snapshotCount = 0
        init(faces: [FontFaceRecord]) { self.faces = faces }
        nonisolated func revisionFingerprint() throws -> String? { "fixture-revision" }
        nonisolated func fileURL(for face: FontFaceRecord) -> URL? { nil }
        func snapshot() async throws -> FontLibrarySnapshot {
            snapshotCount += 1
            return FontLibrarySnapshot(generation: "fixture-revision", faces: faces, customEntryCount: 0)
        }
    }
    func testInventoryAndCoverageReuseBeyondCacheCapacity() async throws {
        let base = face()
        let faces = (0..<600).map { index in
            FontFaceRecord(id: FontFaceID(rawValue: "fixture-\(index)"), family: base.family, style: base.style, postScriptName: base.postScriptName, source: base.source, locator: base.locator, assetID: nil)
        }
        let provider = CountingProvider(faces: faces)
        let engine = FontComparisonEngine(provider: provider, cacheLimit: 512)
        _ = try await final(engine, inspect("A"))
        let before = await engine.cacheHitCount
        _ = try await final(engine, inspect("A"))
        let after = await engine.cacheHitCount
        XCTAssertEqual(after - before, 512, "Initial misses must not evict pending hits")
        let count = await provider.snapshotCount
        XCTAssertEqual(count, 1, "Unchanged revision must reuse full metadata inventory")
        await engine.invalidate()
        _ = try await final(engine, inspect("A"))
        let refreshedCount = await provider.snapshotCount
        XCTAssertEqual(refreshedCount, 2)
    }
    func testPersistedGoogleIDSurvivesInventoryScanAndDetailLookup() async throws {
        let base = face()
        let font = CTFontCreateWithName(base.postScriptName as CFString, 64, nil)
        guard let source = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(source as CFURL) as? [CTFontDescriptor], descriptors.count == 1,
              let data = try? Data(contentsOf: source) else {
            throw XCTSkip("Runtime has no readable single-face integration fixture")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CustomFontStore(directory: directory)
        let digest = CustomFontStore.digest(data)
        let licenseText = "Test fixture only; runtime system font is not redistributed."
        let license = FontLibraryLicense(id: "test-license", name: "Runtime fixture", repositoryPath: "fixtures/LICENSE", sha256: CustomFontStore.digest(Data(licenseText.utf8)), text: licenseText)
        let receipt = FontLibraryReceipt(fileID: "fixture-file", repositoryCommit: String(repeating: "a", count: 40), repositoryPath: "fixtures/font.ttf", snapshotDate: "2026-10-23", sha256: digest, licenses: [license])
        let persistedID = FontFaceID(rawValue: "google:fixture-file:regular")
        let requested = FontFaceRecord(id: persistedID, family: base.family, style: "Regular", postScriptName: base.postScriptName, source: .downloaded, locator: .file(relativePath: "fixture.ttf", sha256: digest, faceIndex: 0, variations: [:]), assetID: nil)
        _ = try store.installGoogleFont(data: data, receipt: receipt, faces: [requested], expectedPostScriptNames: [base.postScriptName])
        let persisted = try store.readLibraryState().snapshot
        XCTAssertNotNil(persisted.faces.first { $0.id == persistedID })
        let engine = FontComparisonEngine(provider: PublicFontInventory(store: store))
        let inventory = try await engine.inventorySnapshot()
        let inventoryFace = try XCTUnwrap(inventory.faces.first { $0.id == persistedID })
        XCTAssertEqual(inventoryFace.source, .downloaded)
        let result = try await final(engine, inspect("A"))
        let scanned = try XCTUnwrap(result.verified.first { $0.id == persistedID })
        // This is the exact-ID lookup used by detail/navigation, not a PS-name alias lookup.
        XCTAssertEqual(persisted.faces.first { $0.id == scanned.id }, inventoryFace)
        XCTAssertNotNil(scanned.assetID)
    }
    func testPhysicalDedupPreservesStableGoogleRepresentativeAndCanonicalAxes() {
        let named = FontLocator.file(relativePath: "a.ttf", sha256: "hash", faceIndex: 0, variations: ["wght": 700])
        let numeric = FontLocator.file(relativePath: "alias.ttf", sha256: "hash", faceIndex: 0, variations: ["2003265652": 700])
        XCTAssertEqual(PublicFontInventory.identity(named), PublicFontInventory.identity(numeric))
        XCTAssertEqual(PublicFontInventory.canonicalAxes(["wght": 700]), [2003265652: 700])
        XCTAssertNil(PublicFontInventory.canonicalAxes(["wght": 700, "2003265652": 400]))
        let google = FontFaceRecord(id: FontFaceID(rawValue: "google:file:bold"), family: "Fixture", style: "Bold", postScriptName: "Fixture", source: .downloaded, locator: named, assetID: "asset")
        let imported = FontFaceRecord(id: FontFaceID(rawValue: "imported:alias"), family: "Fixture", style: "Bold", postScriptName: "Fixture", source: .imported, locator: numeric, assetID: "alias")
        XCTAssertEqual(PublicFontInventory.localRepresentatives([imported, google]), [google])
        XCTAssertEqual(PublicFontInventory.localRepresentatives([google, imported]), [google])
        XCTAssertEqual(google.id.rawValue, "google:file:bold")
    }
    @MainActor
    func testPinnedDownloadedRobotoRegularVariablePreview() throws {
        // google/fonts e7db6ca603fd4862010383ff17ffd6cc4ffac1c0,
        // ofl/roboto/Roboto[wdth,wght].ttf; OFL accompanies the fixture.
        let pinnedHash = "d7598e12c5dbef095ff8272cfc55da0250bd07fbdecbac8a530b9b277872a134"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Roboto-Pinned", withExtension: "ttf"), "Add Tests/Fixtures/Roboto/Roboto-Pinned.ttf to test Copy Bundle Resources")
        let face = FontFaceRecord(id: FontFaceID(rawValue: "pinned-roboto-regular-test"), family: "Roboto", style: "Regular", postScriptName: "Roboto-Regular", source: .downloaded, locator: .file(relativePath: url.lastPathComponent, sha256: pinnedHash, faceIndex: 0, variations: ["wght": 400, "wdth": 100]), assetID: nil)
        let boldID = FontFaceID(rawValue: "pinned-roboto-bold-test")
        let provider = FixtureProvider(faces: [face], urls: [face.id: url, boldID: url])
        XCTAssertEqual(CustomFontStore.digest(try Data(contentsOf: url)), pinnedHash)
        XCTAssertTrue(PublicFontInventory.isSingleFaceSFNT(url))
        // CoreText may enumerate a descriptor per named variation, not per physical face.
        let descriptors = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
        XCTAssertFalse(descriptors.isEmpty)
        let resource = try XCTUnwrap(FontLineVerifier.load(face, size: 64, provider: provider), "Pinned variable sfnt must load physical index zero regardless of named descriptor count")
        defer { withExtendedLifetime(resource) {} }
        let font = resource.font
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, face.postScriptName)
        let coordinates = FontLineVerifier.effectiveCoordinates(font)
        XCTAssertEqual(try XCTUnwrap(coordinates[2003265652]).doubleValue, 400, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(coordinates[2003072104]).doubleValue, 100, accuracy: 0.0001)
        let result = FontLineVerifier.line(face: face, inspection: inspect("Aa"), size: 64, provider: provider)
        XCTAssertEqual(result.0, .verified)
        let retainedLine = try XCTUnwrap(result.1)
        for run in CTLineGetGlyphRuns(retainedLine) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let backing = try XCTUnwrap(attributes[FontLineVerifier.backingAttribute.rawValue] as? FontLineVerifier.LoadedFont)
            XCTAssertNotNil(backing.graphics)
            XCTAssertNotNil(backing.dataProvider)
            XCTAssertNotNil(backing.data)
        }
        guard case let .file(path, hash, index, _) = face.locator else { return XCTFail("Expected pinned file") }
        let bold = FontFaceRecord(id: FontFaceID(rawValue: "pinned-roboto-bold-test"), family: "Roboto", style: "Bold", postScriptName: "Roboto-Bold", source: .downloaded, locator: .file(relativePath: path, sha256: hash, faceIndex: index, variations: ["wght": 700, "wdth": 100]), assetID: face.assetID)
        let boldResource = try XCTUnwrap(FontLineVerifier.load(bold, size: 64, provider: provider))
        defer { withExtendedLifetime(boldResource) {} }
        let boldFont = boldResource.font
        let boldCoordinates = FontLineVerifier.effectiveCoordinates(boldFont)
        XCTAssertEqual(try XCTUnwrap(boldCoordinates[2003265652]).doubleValue, 700, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(boldCoordinates[2003072104]).doubleValue, 100, accuracy: 0.0001)
        XCTAssertEqual(FontLineVerifier.line(face: bold, inspection: inspect("Aa"), size: 64, provider: provider).0, .verified)
        // Regression must execute configure (including metrics) AND real UIKit drawing.
        // A verifier-only test never reached the live inspector's crashing path.
        for requested in [face, bold] {
            let view = VerifiedFontLineView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
            autoreleasepool {
                view.configure(face: requested, inspection: inspect("Aa"), pointSize: 64, provider: provider)
            }
            XCTAssertEqual(view.accessibilityValue, "Available in the app only")
            XCTAssertTrue(view.intrinsicContentSize.width.isFinite)
            XCTAssertTrue(view.intrinsicContentSize.height.isFinite)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
                view.draw(view.bounds)
            }
            let cgImage = try XCTUnwrap(image.cgImage)
            let pixels = try XCTUnwrap(cgImage.dataProvider?.data) as Data
            XCTAssertTrue(pixels.contains { $0 != 0 }, "Verified Roboto must draw actual ink, not merely avoid crashing")
            XCTAssertGreaterThan(view.fittedContentRect.width, 0)
            XCTAssertGreaterThan(view.fittedContentRect.height, 0)
            view.configure(face: requested, inspection: inspect("Aa"), pointSize: 64, provider: provider)
            XCTAssertEqual(view.shapingCount, 1)
        }
    }
    func testCollectionFaceCannotQualifyWithoutPhysicalIndexProof() throws {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        var visited = Set<URL>()
        for descriptor in CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? [] {
            guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
                  visited.insert(url).inserted, !PublicFontInventory.isSingleFaceSFNT(url),
                  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], descriptors.count > 1,
                  let ps = CTFontDescriptorCopyAttribute(descriptors[0], kCTFontNameAttribute) as? String else { continue }
            let locator = FontLocator.file(relativePath: url.lastPathComponent, sha256: "collection-fixture", faceIndex: 0, variations: [:])
            let requested = FontFaceRecord(id: PublicFontInventory.identity(locator), family: ps, style: "Collection fixture", postScriptName: ps, source: .available, locator: locator, assetID: nil)
            let provider = FixtureProvider(faces: [requested], urls: [requested.id: url])
            XCTAssertNil(FontLineVerifier.load(requested, size: 64, provider: provider))
            XCTAssertEqual(FontLineVerifier.line(face: requested, inspection: inspect("A"), size: 64, provider: provider).0, .unknown)
            return
        }
        throw XCTSkip("No readable public multi-face collection fixture on this runtime")
    }
    func testIgnoredOrInvalidVariationNeverQualifies() {
        let base = face()
        for axes in [["not-an-axis": 700.0], ["2003265652": 999999.0]] {
            let locator = FontLocator.process(postScriptName: base.postScriptName, variations: axes)
            let requested = FontFaceRecord(id: PublicFontInventory.identity(locator), family: base.family, style: base.style, postScriptName: base.postScriptName, source: base.source, locator: locator, assetID: nil)
            XCTAssertEqual(FontLineVerifier.line(face: requested, inspection: inspect("A"), size: 64, provider: FixtureProvider(faces: [requested])).0, .unknown)
        }
    }
    func testRealVariableAxisEffectiveCoordinatesWhenAvailable() throws {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        for descriptor in CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? [] {
            let font = CTFontCreateWithFontDescriptor(descriptor, 64, nil)
            guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]], let axis = axes.first,
                  let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                  let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber,
                  let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber,
                  maximum.doubleValue > minimum.doubleValue else { continue }
            let coordinate = minimum.doubleValue + (maximum.doubleValue - minimum.doubleValue) * 0.25
            let ps = CTFontCopyPostScriptName(font) as String
            let axisBytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: identifier.uint32Value >> $0) }
            let axisTag = String(bytes: axisBytes, encoding: .ascii) ?? identifier.stringValue
            XCTAssertEqual(PublicFontInventory.axisIdentifier(axisTag), identifier.uint32Value)
            let locator = FontLocator.process(postScriptName: ps, variations: [axisTag: coordinate])
            let requested = FontFaceRecord(id: PublicFontInventory.identity(locator), family: ps, style: "Variable fixture", postScriptName: ps, source: .available, locator: locator, assetID: nil)
            let loaded = FontLineVerifier.load(requested, size: 64, provider: FixtureProvider(faces: [requested]))
            // Unsupported application is unknown; an awarded instance MUST match requested axes.
            if let loaded {
                let effective = FontLineVerifier.effectiveCoordinates(loaded.font)
                XCTAssertEqual(try XCTUnwrap(effective[identifier]).doubleValue, coordinate, accuracy: 0.0001)
            } else {
                XCTAssertEqual(FontLineVerifier.line(face: requested, inspection: inspect("A"), size: 64, provider: FixtureProvider(faces: [requested])).0, .unknown)
            }
            return
        }
        throw XCTSkip("No publicly enumerated variable font axis on this runtime")
    }
    @MainActor
    func testPreviewIdenticalUpdatesDoNotReshapeAndByteDistinctTextDoes() {
        let view = VerifiedFontLineView()
        let requested = face()
        view.configure(face: requested, inspection: inspect("é"), pointSize: 64)
        view.configure(face: requested, inspection: inspect("é"), pointSize: 64)
        XCTAssertEqual(view.shapingCount, 1)
        view.configure(face: requested, inspection: inspect("e\u{301}"), pointSize: 64)
        XCTAssertEqual(view.shapingCount, 2)
        view.frame = CGRect(x: 0, y: 0, width: 80, height: 96)
        view.configure(face: requested, inspection: inspect(String(repeating: "Italic overhang A", count: 20)), pointSize: 144)
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { context in view.layer.render(in: context.cgContext) }
        XCTAssertEqual(image.size, view.bounds.size)
        XCTAssertGreaterThan(view.fittedContentRect.width, 0)
        XCTAssertGreaterThanOrEqual(view.fittedContentRect.minX, 12)
        XCTAssertGreaterThanOrEqual(view.fittedContentRect.minY, 12)
        XCTAssertLessThanOrEqual(view.fittedContentRect.maxX, view.bounds.width - 12)
        XCTAssertLessThanOrEqual(view.fittedContentRect.maxY, view.bounds.height - 12)
    }
    func testConsumerCancellationStopsScan() async throws {
        let engine = FontComparisonEngine(provider: FixtureProvider(faces: Array(repeating: face(), count: 10_000)), cacheLimit: 2)
        let task = Task {
            for try await update in await engine.scan(inspect("A")) {
                if Task.isCancelled { return false }
                if update.isComplete { return true }
            }
            return false
        }
        task.cancel()
        do { let completed = try await task.value; XCTAssertFalse(completed) }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
#endif
