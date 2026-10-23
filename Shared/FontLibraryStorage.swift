import Foundation
import CoreText
import CryptoKit
import Darwin

struct FontLibraryDownload: Codable {
    let filename: String
    let receipt: FontLibraryReceipt
    let faces: [FontFaceRecord]
    var retainsImportedEntry: Bool
}
struct FontLibraryManifest: Codable {
    var generation: String
    var fonts: [CustomFont]
    var downloads: [FontLibraryDownload]
}
/// Atomic replacement changes inode; nanosecond change/modify times also detect in-place edits.
struct FontLibraryManifestIdentity: Equatable {
    let filename: String
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}
struct FontLibraryManifestCache {
    let identity: FontLibraryManifestIdentity
    let manifest: FontLibraryManifest
}
extension CustomFontStore {
    // All instances and legacy mutations share the same app-process writer.
    static let writerLock = NSRecursiveLock()

    private func manifestIdentity(filename: String) throws -> FontLibraryManifestIdentity? {
        guard let url = url(forRelativePath: filename) else { throw FontLibraryFailure.storageFailure }
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        if result != 0 {
            if errno == ENOENT { return nil }
            throw FontLibraryFailure.storageFailure
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw FontLibraryFailure.storageFailure }
        return .init(filename: filename, device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
                     modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                     changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    private func currentManifestIdentity() throws -> FontLibraryManifestIdentity? {
        if let current = try manifestIdentity(filename: "library-v2.json") { return current }
        return try manifestIdentity(filename: "fonts.json")
    }

    func readManifest() throws -> FontLibraryManifest {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        guard directory != nil else { manifestCache = nil; throw FontLibraryFailure.storageUnavailable }
        do {
            // At most three attempts if an external app process replaces the manifest during a read.
            for _ in 0..<3 {
                guard let identity = try currentManifestIdentity() else {
                    manifestCache = nil
                    return FontLibraryManifest(generation: "", fonts: [], downloads: [])
                }
                if let cached = manifestCache, cached.identity == identity { return cached.manifest }
                manifestCache = nil
                let legacy = identity.filename == "fonts.json"
                let limit = (legacy ? 4 : 8) * 1024 * 1024
                guard identity.size >= 0, identity.size <= Int64(limit),
                      let url = url(forRelativePath: identity.filename) else { throw FontLibraryFailure.storageFailure }
                let data = try Self.boundedRead(url, limit: limit)
                // Never associate bytes read across a rename with the previous file identity.
                guard try currentManifestIdentity() == identity else { continue }
                let manifest: FontLibraryManifest
                if legacy {
                    manifest = .init(generation: Self.digest(data), fonts: try JSONDecoder().decode([CustomFont].self, from: data), downloads: [])
                } else { manifest = try JSONDecoder().decode(FontLibraryManifest.self, from: data) }
                try Self.validateManifest(manifest)
                manifestCache = .init(identity: identity, manifest: manifest)
                return manifest
            }
            throw FontLibraryFailure.storageFailure
        } catch {
            manifestCache = nil
            throw error
        }
    }

    func commitManifest(_ value: FontLibraryManifest) throws {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        guard let directory else { throw FontLibraryFailure.storageUnavailable }
        guard url(forRelativePath: "library-v2.json") != nil else { throw FontLibraryFailure.storageFailure }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard directory.standardizedFileURL.pathComponents == directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents else { throw FontLibraryFailure.storageFailure }
        var value = value
        value.generation = UUID().uuidString
        try Self.validateManifest(value)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8 * 1024 * 1024 else { throw FontLibraryFailure.storageFailure }
        try data.write(to: directory.appendingPathComponent("library-v2.json"), options: .atomic)
        manifestCache = nil
    }

    /// No membership check: a previously acquired snapshot retains immutable bytes.
    func url(forRelativePath path: String) -> URL? {
        guard let directory, !path.isEmpty, !path.hasPrefix("/"),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\"), !path.contains("\0") else { return nil }
        let root = directory.standardizedFileURL
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        // Compare filesystem components, not URL equality: resolving an absent directory
        // can drop its trailing-slash directory hint without changing the actual path.
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents,
              rootComponents == root.resolvingSymlinksInPath().standardizedFileURL.pathComponents,
              candidateComponents == candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents else { return nil }
        // Foundation may leave an entire path unresolved when its terminal file is
        // absent. lstat each existing component, including dangling links, instead
        // of trusting whole-path resolution to detect a symlink in a parent.
        var componentURL = root
        let descendants = Array(candidateComponents.dropFirst(rootComponents.count))
        for index in 0...descendants.count {
            if index > 0 { componentURL.appendPathComponent(descendants[index - 1]) }
            var info = stat()
            let outcome = componentURL.path.withCString { pointer -> (Int32, Int32) in
                let result = lstat(pointer, &info)
                return (result, errno)
            }
            if outcome.0 != 0 {
                guard outcome.1 == ENOENT else { return nil }
                continue // New library/terminal file is legitimate, but no I/O happens here.
            }
            let kind = info.st_mode & mode_t(S_IFMT)
            guard kind != mode_t(S_IFLNK) else { return nil }
            if index < descendants.count {
                guard kind == mode_t(S_IFDIR) else { return nil }
            } else {
                guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else { return nil }
            }
        }
        return candidate
    }

    var localLibrary: FontLibrarySnapshot {
        guard let manifest = try? readManifest() else { return .init(generation: "unavailable", faces: [], customEntryCount: 0) }
        return snapshot(manifest)
    }

    private func snapshot(_ manifest: FontLibraryManifest) -> FontLibrarySnapshot {
        let downloaded = Set(manifest.downloads.map(\.filename))
        let legacy = manifest.fonts.filter { !downloaded.contains($0.filename) }.map { font in
            FontFaceRecord(id: .init(rawValue: "custom:" + font.filename), family: font.displayName, style: "Regular",
                           postScriptName: font.postScriptName, source: font.installed == true ? .installed : .imported,
                           locator: font.installed == true ? .process(postScriptName: font.postScriptName, variations: [:]) :
                            .file(relativePath: font.filename, sha256: font.sha256, faceIndex: 0, variations: [:]), assetID: font.filename)
        }
        return .init(generation: manifest.generation, faces: legacy + manifest.downloads.flatMap(\.faces), customEntryCount: manifest.fonts.count)
    }

    func receipt(fileID: String) -> FontLibraryReceipt? {
        (try? readManifest())?.downloads.first { $0.receipt.fileID == fileID }?.receipt
    }

    /// One bounded decode for all receipts/assets and the matching generation.
    func readLibraryState() throws -> FontLibraryReadState {
        do {
            let manifest = try readManifest()
            return .init(snapshot: snapshot(manifest), receipts: Dictionary(uniqueKeysWithValues: manifest.downloads.map { ($0.receipt.fileID, $0.receipt) }),
                         assetIDs: Dictionary(uniqueKeysWithValues: manifest.downloads.map { ($0.receipt.fileID, $0.filename) }))
        } catch let failure as FontLibraryFailure { throw failure }
        catch { throw FontLibraryFailure.storageFailure }
    }

    var libraryFailure: FontLibraryFailure? {
        do { _ = try readLibraryState(); return nil }
        catch { return (error as? FontLibraryFailure) ?? .storageFailure }
    }

    static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: min(65536, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw FontLibraryFailure.storageFailure
    }

    /// Missing bytes can be restored from validated input; never overwrite divergent immutable bytes.
    func ensureImmutableBinary(_ data: Data, filename: String) throws {
        guard let url = url(forRelativePath: filename) else { throw FontLibraryFailure.storageFailure }
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Self.boundedRead(url, limit: Self.maximumBytes) == data else { throw FontLibraryFailure.storageFailure }
        } else { try data.write(to: url, options: .atomic) }
    }

    private static func validateManifest(_ value: FontLibraryManifest) throws {
        func require(_ condition: Bool) throws { if !condition { throw FontLibraryFailure.storageFailure } }
        func unique(_ ids: [String]) -> Bool { !ids.contains("") && Set(ids).count == ids.count }
        func hash(_ text: String) -> Bool { text.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
        func path(_ text: String) -> Bool {
            !text.isEmpty && !text.contains(where: { "\\?#%".contains($0) || $0.isNewline || $0.asciiValue == 0 }) &&
            text.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        }
        try require(value.generation.utf8.count <= 128 && (value.fonts.isEmpty || !value.generation.isEmpty))
        try require(value.fonts.count <= maximumFonts && unique(value.fonts.map(\.filename)))
        try require(unique(value.fonts.filter { $0.installed != true }.map(\.sha256)))
        for font in value.fonts {
            try require(validFilename(font.filename) && !font.postScriptName.isEmpty && !font.displayName.isEmpty)
            try require(font.installed == true ? (font.filename == "Installed-" + font.postScriptName && font.sha256.isEmpty) : (!font.filename.hasPrefix("Installed-") && hash(font.sha256)))
            if font.installed != true {
                let basename = (font.filename as NSString).deletingPathExtension
                try require(basename == "Custom-" + font.sha256 || basename == "Custom-" + String(font.sha256.prefix(16)))
            }
            var last: UInt32?
            for range in font.ranges {
                try require(range.count == 2)
                try require(range[0] <= range[1] && range[1] <= 0x10ffff && (range[1] < 0xd800 || range[0] > 0xdfff) && (last == nil || range[0] > last!))
                last = range[1]
            }
        }
        try require(unique(value.downloads.map { $0.receipt.fileID }))
        try require(unique(value.downloads.flatMap { $0.faces.map { $0.id.rawValue } }))
        for download in value.downloads {
            let receipt = download.receipt
            guard let font = value.fonts.first(where: { $0.filename == download.filename }) else { throw FontLibraryFailure.storageFailure }
            try require(font.installed != true && hash(receipt.sha256) && receipt.sha256 == font.sha256 && path(receipt.repositoryPath))
            try require(receipt.repositoryCommit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil)
            try require(receipt.snapshotDate.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil)
            try require(!receipt.licenses.isEmpty && unique(receipt.licenses.map(\.id)))
            for license in receipt.licenses {
                try require(!license.name.isEmpty && !license.text.isEmpty && path(license.repositoryPath) && hash(license.sha256) && digest(Data(license.text.utf8)) == license.sha256)
            }
            try require(!download.faces.isEmpty)
            for face in download.faces {
                try require(face.source == .downloaded && face.assetID == download.filename && !face.family.isEmpty && !face.style.isEmpty && !face.postScriptName.isEmpty)
                guard case let .file(relativePath, sha256, faceIndex, variations) = face.locator else { throw FontLibraryFailure.storageFailure }
                try require(relativePath == download.filename && sha256 == receipt.sha256 && faceIndex == 0 && variations.allSatisfy { $0.key.utf8.count == 4 && $0.value.isFinite })
            }
            try require(value.downloads.filter { $0.filename == download.filename }.allSatisfy { $0.retainsImportedEntry == download.retainsImportedEntry })
        }
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Synchronous transaction: cancellation is checked again immediately before publication.
    @discardableResult
    func installGoogleFont(data: Data, receipt: FontLibraryReceipt, faces: [FontFaceRecord], expectedPostScriptNames: [String],
                           checkCancellation: () throws -> Void = {}) throws -> String {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        try checkCancellation()
        guard let directory else { throw FontLibraryFailure.storageUnavailable }
        guard data.count <= Self.maximumBytes else { throw FontLibraryFailure.tooLarge(limitBytes: Int64(Self.maximumBytes)) }
        guard Self.digest(data) == receipt.sha256, !receipt.licenses.isEmpty,
              receipt.licenses.allSatisfy({ Self.digest(Data($0.text.utf8)) == $0.sha256 }),
              [[UInt8](arrayLiteral: 0,1,0,0), [0x4f,0x54,0x54,0x4f], [0x74,0x72,0x75,0x65]].contains(Array(data.prefix(4))),
              let provider = CGDataProvider(data: data as CFData), let graphics = CGFont(provider),
              let name = graphics.postScriptName as String?, Set(expectedPostScriptNames) == Set([name]),
              !faces.isEmpty else { throw FontLibraryFailure.invalidFile }
        let font = CTFontCreateWithGraphicsFont(graphics, 12, nil, nil)
        guard CTFontCopyPostScriptName(font) as String == name else { throw FontLibraryFailure.registration }
        var manifest = try readManifest()

        let existing = manifest.fonts.first { $0.sha256 == receipt.sha256 }
        guard existing != nil || manifest.fonts.count < Self.maximumFonts else { throw FontLibraryFailure.tooMany(limit: Self.maximumFonts) }
        let filename = existing?.filename ?? "Custom-\(receipt.sha256).ttf"
        guard let binaryURL = url(forRelativePath: filename) else { throw FontLibraryFailure.storageFailure }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let alreadyOnDisk = FileManager.default.fileExists(atPath: binaryURL.path)
        var published = false
        defer { if !published && !alreadyOnDisk { try? FileManager.default.removeItem(at: binaryURL) } }
        try ensureImmutableBinary(data, filename: filename)
        if existing == nil {
            manifest.fonts.append(CustomFont(filename: filename, displayName: CTFontCopyFullName(font) as String,
                                             postScriptName: name, sha256: receipt.sha256, ranges: Self.ranges(CTFontCopyCharacterSet(font))))
        }
        let storedFaces = faces.map { face in
            let variations: [String: Double]
            switch face.locator { case .file(_, _, _, let axes), .process(_, let axes): variations = axes }
            return FontFaceRecord(id: face.id, family: face.family, style: face.style, postScriptName: face.postScriptName,
                                  source: .downloaded, locator: .file(relativePath: filename, sha256: receipt.sha256, faceIndex: 0, variations: variations), assetID: filename)
        }
        if let previous = manifest.downloads.first(where: { $0.receipt.fileID == receipt.fileID }), previous.filename != filename {
            throw FontLibraryFailure.storageFailure
        }
        let retainImported = existing != nil && (!manifest.downloads.contains(where: { $0.filename == filename }) || manifest.downloads.contains(where: { $0.filename == filename && $0.retainsImportedEntry }))
        manifest.downloads.removeAll { $0.receipt.fileID == receipt.fileID }
        manifest.downloads.append(.init(filename: filename, receipt: receipt, faces: storedFaces, retainsImportedEntry: retainImported))
        // Receipt and complete licenses are part of the SAME atomic manifest as membership.
        try checkCancellation()
        try commitManifest(manifest)
        published = true
        return filename
    }

    func removeGoogleFont(fileID: String) throws {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        var manifest = try readManifest()
        guard let download = manifest.downloads.first(where: { $0.receipt.fileID == fileID }) else { return }
        manifest.downloads.removeAll { $0.receipt.fileID == fileID }
        if !download.retainsImportedEntry && !manifest.downloads.contains(where: { $0.filename == download.filename }) {
            manifest.fonts.removeAll { $0.filename == download.filename }
        }
        try commitManifest(manifest)
    }
}
