#if canImport(UIKit)
import Foundation
import CoreText
import CryptoKit

enum FontPresentation: String, Hashable, Sendable { case original, text, emoji }
enum FontScaffold: String, Hashable, Sendable { case automatic, none, dottedCircle }
struct FontInspection: Sendable {
    let originalText: String
    let characterName: String
    let presentation: FontPresentation
    let scaffold: FontScaffold
    init(originalText: String, characterName: String, presentation: FontPresentation = .original, scaffold: FontScaffold = .automatic) {
        self.originalText = originalText; self.characterName = characterName
        self.presentation = presentation; self.scaffold = scaffold
    }
    /// Only a single base scalar, optionally followed by VS15/16, can be safely switched.
    var canChoosePresentation: Bool {
        let scalars = Array(originalText.unicodeScalars)
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        return scalars.count == 1 || (scalars.count == 2 && [0xFE0E, 0xFE0F].contains(scalars[1].value))
    }
    var previewText: String {
        guard presentation != .original, canChoosePresentation, let base = originalText.unicodeScalars.first else { return originalText }
        return String(base) + (presentation == .text ? "\u{FE0E}" : "\u{FE0F}")
    }
    var isApplicable: Bool {
        originalText.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator: return false
            default: return !((0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value))
            }
        }
    }
    var usesDottedCircle: Bool {
        if scaffold == .dottedCircle { return true }
        guard scaffold == .automatic, let first = originalText.unicodeScalars.first else { return false }
        return [.nonspacingMark, .spacingMark, .enclosingMark].contains(first.properties.generalCategory)
    }
    var requiresUnprovedShaping: Bool {
        let values = previewText.unicodeScalars.map(\.value)
        if values.contains(where: { $0 == 0x200D || $0 == 0x200C || $0 == 0x20E3 || (0xFE00...0xFE0F).contains($0) || (0xE0100...0xE01EF).contains($0) || (0x1F3FB...0x1F3FF).contains($0) || (0xE0020...0xE007F).contains($0) }) { return true }
        // No language-specific shaping oracle: do not infer semantic sequence support from same-font runs.
        if values.count > 1 && previewText.unicodeScalars.contains(where: { [.nonspacingMark, .spacingMark, .enclosingMark].contains($0.properties.generalCategory) }) { return true }
        return values.count > 1 && values.contains { $0 > 0x052F }
    }
}
struct FontScanUpdate: Sendable {
    let generation: UInt64
    let checked: Int
    let total: Int
    let verified: [FontFaceRecord]
    let unknownCount: Int
    let isComplete: Bool
}
protocol FontComparing: Sendable {
    func inventorySnapshot() async throws -> FontLibrarySnapshot
    func scan(_ inspection: FontInspection) async -> AsyncThrowingStream<FontScanUpdate, Error>
    func invalidate() async
}
protocol FontInventoryProviding: Sendable {
    func snapshot() async throws -> FontLibrarySnapshot
    func fileURL(for face: FontFaceRecord) -> URL?
    func revisionFingerprint() throws -> String?
}
extension FontInventoryProviding {
    func revisionFingerprint() throws -> String? { nil }
}

struct PublicFontInventory: FontInventoryProviding {
    let store: CustomFontStore
    init(store: CustomFontStore = .shared) { self.store = store }
    func revisionFingerprint() throws -> String? {
        try store.readLibraryState().snapshot.generation + "|" + UnicodeFontDownloadStore.shared.revision
    }
    /// A variable sfnt may expose many *named instance* descriptors. Only the binary
    /// header distinguishes it from a physical TrueType/OpenType collection.
    static func isSingleFaceSFNT(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 4) else { return false }
        return [[0, 1, 0, 0], [0x4F, 0x54, 0x54, 0x4F], [0x74, 0x72, 0x75, 0x65]].contains(Array(bytes))
    }
    private static func fileDigest(_ url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let bytes = try handle.read(upToCount: 256 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            digest.update(data: bytes)
            await Task.yield()
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func variations(_ descriptor: CTFontDescriptor) -> [String: Double] {
        guard let axes = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [NSNumber: NSNumber] else { return [:] }
        return Dictionary(uniqueKeysWithValues: axes.map { ($0.key.stringValue, $0.value.doubleValue) })
    }
    /// OpenType axis tags and CoreText decimal NSNumber identifiers name the same axis.
    static func axisIdentifier(_ key: String) -> UInt32? {
        if let numeric = UInt32(key) { return numeric }
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (32...126).contains($0) }) else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    static func canonicalAxes(_ axes: [String: Double]) -> [UInt32: Double]? {
        var result: [UInt32: Double] = [:]
        for (key, value) in axes {
            guard let identifier = axisIdentifier(key), value.isFinite else { return nil }
            if let previous = result[identifier], previous != value { return nil }
            result[identifier] = value
        }
        return result
    }
    static func axisKey(_ axes: [String: Double]) -> String {
        guard let canonical = canonicalAxes(axes) else {
            return "invalid:" + axes.keys.sorted().map { "\($0)=\(axes[$0]!)" }.joined(separator: ",")
        }
        return canonical.keys.sorted().map { "\($0)=\(canonical[$0]!)" }.joined(separator: ",")
    }
    /// Keep persisted navigation IDs unchanged. Physical identity is only a dedup key.
    /// Prefer a Google receipt-backed face over imported aliases, then stable ID order.
    static func localRepresentatives(_ faces: [FontFaceRecord]) -> [FontFaceRecord] {
        func priority(_ face: FontFaceRecord) -> Int {
            if face.source == .downloaded && face.id.rawValue.hasPrefix("google:") { return 0 }
            switch face.source {
            case .downloaded: return 1
            case .imported: return 2
            case .installed: return 3
            case .included: return 4
            case .system: return 5
            case .available: return 6
            }
        }
        var seen = Set<FontFaceID>()
        return faces.sorted { (priority($0), $0.id.rawValue) < (priority($1), $1.id.rawValue) }
            .filter { seen.insert(identity($0.locator)).inserted }
    }
    static func identity(_ locator: FontLocator) -> FontFaceID {
        switch locator {
        case let .process(name, axes): return FontFaceID(rawValue: "ps:\(name):\(axisKey(axes))")
        case let .file(_, hash, index, axes): return FontFaceID(rawValue: "file:\(hash):\(index):\(axisKey(axes))")
        }
    }
    func fileURL(for face: FontFaceRecord) -> URL? {
        guard case let .file(path, _, _, _) = face.locator else { return nil }
        if path.hasPrefix("bundle:") { return Bundle.main.resourceURL?.appendingPathComponent(String(path.dropFirst(7))) }
        if path.hasPrefix("pack:") {
            let name = String(path.dropFirst(5))
            guard let item = UnicodeFontPackCatalog.bundled.packs.flatMap(\.fonts).first(where: { $0.asset.filename == name }) else { return nil }
            return UnicodeFontDownloadStore.shared.installedURL(for: item)
        }
        return store.url(forRelativePath: path)
    }
    func snapshot() async throws -> FontLibrarySnapshot {
        // Missing manifests on a new install are an empty snapshot; corruption and
        // unavailable shared storage must fail the scan rather than hide local faces.
        let local = try store.readLibraryState().snapshot
        var records: [FontFaceID: FontFaceRecord] = [:]
        var physical: [String: FontFaceRecord] = [:]
        func add(_ record: FontFaceRecord, url: URL?) {
            let physicalID = Self.identity(record.locator)
            if records[physicalID] == nil { records[physicalID] = record }
            if let url { physical[url.standardizedFileURL.path + "|" + record.postScriptName + "|" + Self.axisKey({ if case let .file(_, _, _, axes) = record.locator { return axes }; return [:] }())] = record }
        }
        for face in Self.localRepresentatives(local.faces) {
            add(face, url: fileURL(for: face))
        }
        // Record URL evidence for alternate immutable paths as well, without replacing
        // the preferred persisted representative selected above.
        for face in local.faces { add(face, url: fileURL(for: face)) }
        func addFile(_ url: URL, path: String, source: FontSource, digest: String? = nil) async throws {
            await Task.yield(); try Task.checkCancellation()
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return }
            let hash: String
            if let digest { hash = digest } else { hash = try await Self.fileDigest(url) }
            let singlePhysicalFace = Self.isSingleFaceSFNT(url)
            for (index, descriptor) in descriptors.enumerated() {
                await Task.yield(); try Task.checkCancellation()
                guard let ps = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { continue }
                let locator = FontLocator.file(relativePath: path, sha256: hash, faceIndex: singlePhysicalFace ? 0 : index, variations: Self.variations(descriptor))
                let face = FontFaceRecord(id: Self.identity(locator), family: CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String ?? ps, style: CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular", postScriptName: ps, source: source, locator: locator, assetID: nil)
                add(face, url: url)
            }
        }
        if let root = Bundle.main.resourceURL, let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("Fonts"), includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where ["ttf", "otf", "ttc", "otc"].contains(url.pathExtension.lowercased()) {
                try Task.checkCancellation()
                try await addFile(url, path: "bundle:" + String(url.path.dropFirst(root.path.count + 1)), source: .included)
            }
        }
        for item in UnicodeFontPackCatalog.bundled.packs.flatMap(\.fonts) {
            try Task.checkCancellation()
            if let url = UnicodeFontDownloadStore.shared.installedURL(for: item) { try await addFile(url, path: "pack:" + item.asset.filename, source: .downloaded, digest: item.asset.sha256) }
        }
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        var descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        let describedNames = Set(descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String })
        for name in CTFontManagerCopyAvailablePostScriptNames() as! [String] where !describedNames.contains(name) {
            descriptors.append(CTFontDescriptorCreateWithNameAndSize(name as CFString, 0))
        }
        for descriptor in descriptors {
            await Task.yield(); try Task.checkCancellation()
            guard let ps = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { continue }
            let axes = Self.variations(descriptor)
            let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
            if let url, physical[url.standardizedFileURL.path + "|" + ps + "|" + Self.axisKey(axes)] != nil { continue }
            let locator = FontLocator.process(postScriptName: ps, variations: axes)
            let id = Self.identity(locator)
            if records[id] == nil {
                let source: FontSource = url.map { FontPickerSection.isSystemFontFile($0.path) } == true ? .system : .available
                records[id] = FontFaceRecord(id: id, family: CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String ?? ps, style: CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular", postScriptName: ps, source: source, locator: locator, assetID: nil)
            }
        }
        let faces = records.values.sorted { ($0.family, $0.style, $0.id.rawValue) < ($1.family, $1.style, $1.id.rawValue) }
        let generation = local.generation + "|" + UnicodeFontDownloadStore.shared.revision + "|" + faces.map(\.id.rawValue).joined(separator: "|")
        return FontLibrarySnapshot(generation: generation, faces: faces, customEntryCount: local.customEntryCount)
    }
}

enum FontProof: Equatable, Sendable { case verified, unsupported, unknown }
/// All CoreText values returned here stay on the caller's executor. Never stored in Sendable wrappers.
enum FontLineVerifier {
    /// CoreText variable-font copies can borrow tables from their original CGFont.
    /// Keep that entire ownership chain alive, including after load returns and
    /// after shaping returns a CTLine. This object never crosses actor boundaries.
    final class LoadedFont: NSObject {
        let font: CTFont
        let graphics: CGFont?
        let dataProvider: CGDataProvider?
        let data: CFData?
        init(font: CTFont, graphics: CGFont?, dataProvider: CGDataProvider?, data: CFData?) {
            self.font = font; self.graphics = graphics
            self.dataProvider = dataProvider; self.data = data
        }
    }
    static let backingAttribute = NSAttributedString.Key("ad.neko.uniboard.fontBacking")
    /// CoreText reports only non-default variation coordinates. An absent coordinate
    /// is the font's declared fvar default, NOT an ignored request and NOT zero.
    /// Unknown axes remain absent, so ignored/clamped non-default requests still fail.
    static func effectiveCoordinates(_ font: CTFont) -> [NSNumber: NSNumber] {
        var result: [NSNumber: NSNumber] = [:]
        if let definitions = CTFontCopyVariationAxes(font) as? [[String: Any]] {
            for definition in definitions {
                guard let axis = definition[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                      let value = definition[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber,
                      value.doubleValue.isFinite else { continue }
                result[axis] = value
            }
        }
        if let overrides = CTFontCopyVariation(font) as? [NSNumber: NSNumber] {
            for (axis, value) in overrides where value.doubleValue.isFinite { result[axis] = value }
        }
        return result
    }
    static func load(_ face: FontFaceRecord, size: CGFloat, provider: any FontInventoryProviding) -> LoadedFont? {
        var graphics: CGFont?
        var backingData: CFData?
        var backingProvider: CGDataProvider?
        let descriptor: CTFontDescriptor
        let axes: [String: Double]
        switch face.locator {
        case let .process(name, variations):
            descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, size); axes = variations
        case let .file(_, _, index, variations):
            guard index == 0, let url = provider.fileURL(for: face), PublicFontInventory.isSingleFaceSFNT(url),
                  let bytes = try? Data(contentsOf: url),
                  let data = CGDataProvider(data: bytes as CFData), let direct = CGFont(data) else { return nil }
            backingData = bytes as CFData
            backingProvider = data
            // Open the physical sfnt directly. Named variable descriptors are NOT
            // collection face indices, and their names must not redirect loading.
            graphics = direct
            descriptor = CTFontDescriptorCreateWithAttributes([:] as CFDictionary)
            axes = variations
        }
        guard let canonicalAxes = PublicFontInventory.canonicalAxes(axes) else { return nil }
        let variation = Dictionary(uniqueKeysWithValues: canonicalAxes.map { (NSNumber(value: $0.key), NSNumber(value: $0.value)) })
        let adjusted = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontVariationAttribute: variation] as CFDictionary)
        let font: CTFont
        if let graphics { font = CTFontCreateWithGraphicsFont(graphics, size, nil, adjusted) }
        else { font = CTFontCreateWithFontDescriptor(adjusted, size, nil) }
        let resource = LoadedFont(font: font, graphics: graphics, dataProvider: backingProvider, data: backingData)
        defer { withExtendedLifetime(resource) {} }
        guard CTFontCopyPostScriptName(font) as String == face.postScriptName else { return nil }
        let effective = effectiveCoordinates(font)
        for (axis, requested) in variation {
            guard let actual = effective[axis]?.doubleValue, abs(actual - requested.doubleValue) <= 0.0001 else { return nil }
        }
        return resource
    }
    static func line(face: FontFaceRecord, inspection: FontInspection, size: CGFloat, provider: any FontInventoryProviding) -> (FontProof, CTLine?) {
        guard inspection.isApplicable else { return (.unknown, nil) }
        guard let resource = load(face, size: size, provider: provider) else { return (.unknown, nil) }
        defer { withExtendedLifetime(resource) {} }
        let font = resource.font
        let prefix = inspection.usesDottedCircle ? "\u{25CC}" : ""
        let text = prefix + inspection.previewText
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true, backingAttribute: resource])
        let line = CTLineCreateWithAttributedString(attributed)
        let relevantStart = prefix.utf16.count
        var relevantGlyphs = 0
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let range = CTRunGetStringRange(run)
            guard range.location + range.length > relevantStart else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let raw = attributes[kCTFontAttributeName] else { return (.unknown, nil) }
            let actual = raw as! CTFont
            // CFEqual compares descriptors/graphics identity, not just the human-readable name.
            guard CFEqual(CTFontCopyGraphicsFont(actual, nil), CTFontCopyGraphicsFont(font, nil)),
                  CFEqual(CTFontCopyVariation(actual) ?? [:] as CFDictionary, CTFontCopyVariation(font) ?? [:] as CFDictionary) else { return (.unsupported, nil) }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for i in 0..<count where indices[i] >= relevantStart {
                guard glyphs[i] != 0 else { return (.unsupported, nil) }
                relevantGlyphs += 1
            }
        }
        guard relevantGlyphs > 0 else { return (.unknown, nil) }
        guard !inspection.requiresUnprovedShaping else { return (.unknown, nil) }
        return (.verified, line)
    }
}

actor FontComparisonEngine: FontComparing {
    static let shared = FontComparisonEngine()
    private let provider: any FontInventoryProviding
    private let cacheLimit: Int
    private var generation: UInt64 = 0
    private var scanTask: Task<Void, Never>?
    private struct Key: Hashable {
        let bytes: Data
        let originalBytes: Data
        let face: FontFaceID
        let inventory: String
        let presentation: FontPresentation
        let scaffold: FontScaffold
    }
    private var cache: [Key: FontProof] = [:]
    private var recency: [Key] = []
    var cachedResultCount: Int { cache.count }
    private(set) var cacheHitCount = 0
    private var inventoryCache: (fingerprint: String, snapshot: FontLibrarySnapshot)?
    init(provider: any FontInventoryProviding = PublicFontInventory(), cacheLimit: Int = 512) {
        self.provider = provider; self.cacheLimit = max(0, cacheLimit)
    }
    func inventorySnapshot() async throws -> FontLibrarySnapshot {
        let fingerprint = try provider.revisionFingerprint()
        if let fingerprint, let cached = inventoryCache, cached.fingerprint == fingerprint { return cached.snapshot }
        let token = generation
        let snapshot = try await provider.snapshot()
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        if let fingerprint, fingerprint == (try provider.revisionFingerprint()) {
            inventoryCache = (fingerprint, snapshot)
        }
        return snapshot
    }
    func invalidate() { scanTask?.cancel(); scanTask = nil; generation &+= 1; cache.removeAll(); recency.removeAll(); inventoryCache = nil }
    /// Proofs for chosen faces only (the preferred-font picker), sharing this
    /// engine's verifier and cache without cancelling a running scan.
    func proofs(for inspection: FontInspection, faces: [FontFaceRecord]) async throws -> [FontFaceID: FontProof] {
        let snapshot = try await inventorySnapshot()
        let bytes = Data(inspection.previewText.utf8), originalBytes = Data(inspection.originalText.utf8)
        var result: [FontFaceID: FontProof] = [:]
        for face in faces {
            await Task.yield()
            try Task.checkCancellation()
            let key = Key(bytes: bytes, originalBytes: originalBytes, face: face.id, inventory: snapshot.generation, presentation: inspection.presentation, scaffold: inspection.scaffold)
            if let cached = cache[key] {
                cacheHitCount += 1
                result[face.id] = cached
                continue
            }
            let proof = autoreleasepool { FontLineVerifier.line(face: face, inspection: inspection, size: 64, provider: provider).0 }
            if cacheLimit > 0 {
                if cache.count >= cacheLimit, !recency.isEmpty { cache.removeValue(forKey: recency.removeFirst()) }
                if cache.count < cacheLimit { cache[key] = proof; recency.append(key) }
            }
            result[face.id] = proof
        }
        return result
    }
    func scan(_ inspection: FontInspection) -> AsyncThrowingStream<FontScanUpdate, Error> {
        scanTask?.cancel()
        generation &+= 1
        let token = generation
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let task = Task { await self.run(inspection, token: token, continuation: continuation) }
            self.scanTask = task
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    private func run(_ inspection: FontInspection, token: UInt64, continuation: AsyncThrowingStream<FontScanUpdate, Error>.Continuation) async {
        do {
            try Task.checkCancellation()
            let snapshot = try await inventorySnapshot()
            guard token == generation else { throw CancellationError() }
            var verified: [FontFaceRecord] = [], unknown = 0, checked = 0
            func update(_ complete: Bool) -> FontScanUpdate { FontScanUpdate(generation: token, checked: checked, total: snapshot.faces.count, verified: verified, unknownCount: unknown, isComplete: complete) }
            continuation.yield(update(false))
            let bytes = Data(inspection.previewText.utf8), originalBytes = Data(inspection.originalText.utf8)
            func keyFor(_ face: FontFaceRecord) -> Key {
                Key(bytes: bytes, originalBytes: originalBytes, face: face.id, inventory: snapshot.generation, presentation: inspection.presentation, scaffold: inspection.scaffold)
            }
            // Protect entries this scan has not consumed. Sequential rescans larger
            // than the cache must not evict their own pending hits on initial misses.
            var pendingHits = Set(snapshot.faces.map(keyFor).filter { cache[$0] != nil })
            for face in snapshot.faces {
                await Task.yield()
                try Task.checkCancellation()
                guard token == generation else { throw CancellationError() }
                let key = keyFor(face)
                pendingHits.remove(key)
                let proof: FontProof
                if let cached = cache[key] {
                    proof = cached; cacheHitCount += 1
                    recency.removeAll { $0 == key }; recency.append(key)
                }
                else {
                    proof = autoreleasepool { FontLineVerifier.line(face: face, inspection: inspection, size: 64, provider: provider).0 }
                    if cacheLimit > 0 {
                        if cache.count >= cacheLimit, let index = recency.firstIndex(where: { !pendingHits.contains($0) }) {
                            cache.removeValue(forKey: recency.remove(at: index))
                        }
                        if cache.count < cacheLimit { cache[key] = proof; recency.append(key) }
                    }
                }
                switch proof { case .verified: verified.append(face); case .unknown: unknown += 1; case .unsupported: break }
                checked += 1
                if checked % 16 == 0 { continuation.yield(update(false)) }
            }
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            continuation.yield(update(true)); continuation.finish()
        } catch { continuation.finish(throwing: error) }
    }
}
#endif
