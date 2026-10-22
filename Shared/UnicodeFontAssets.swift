import Foundation
import CryptoKit

/// Bundled metadata is the only source of font identities. A download cannot
/// introduce its own filename, coverage, URL, license or expected digest.
struct UnicodeFontAsset: Decodable, Sendable {
    let filename: String
    let displayName: String
    let postScriptName: String
    let sha256: String
    let sourceURL: String
    let licenseFilename: String
    let ranges: [[UInt32]]

    var isValid: Bool {
        guard Self.isResourceFilename(filename), Self.isResourceFilename(licenseFilename),
              !displayName.isEmpty, !postScriptName.isEmpty,
              sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              displayName.utf8.count <= 256, postScriptName.utf8.count <= 160,
              sourceURL.utf8.count <= 2048,
              let source = URL(string: sourceURL), source.scheme == "https", source.host != nil,
              source.user == nil, source.password == nil,
              !ranges.isEmpty, ranges.count <= 20_000 else { return false }
        var previous: UInt32?
        for range in ranges {
            guard range.count == 2, range[0] <= range[1], range[1] <= 0x10FFFF,
                  !(range[0] <= 0xDFFF && range[1] >= 0xD800),
                  previous.map({ $0 < range[0] }) ?? true else { return false }
            previous = range[1]
        }
        return true
    }

    static func isResourceFilename(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    func contains(_ point: UInt32) -> Bool {
        var lower = 0, upper = ranges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            let range = ranges[middle]
            guard range.count == 2 else { return false }
            if point < range[0] { upper = middle }
            else if point > range[1] { lower = middle + 1 }
            else { return true }
        }
        return false
    }
}

struct UnicodeFontDownload: Decodable, Sendable {
    let asset: UnicodeFontAsset
    let bytes: Int64
    let downloadURL: String

    var isValid: Bool {
        asset.isValid && bytes > 0 && bytes <= 40 * 1024 * 1024
            && asset.filename.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                || (97...122).contains($0) || [45, 46, 95].contains($0) })
            && (asset.filename.hasSuffix(".ttf") || asset.filename.hasSuffix(".otf"))
            && UnicodeFontPackCatalog.downloadBases.contains { downloadURL == $0 + asset.filename }
    }
}

struct UnicodeFontPack: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let fonts: [UnicodeFontDownload]
    var bytes: Int64 { fonts.reduce(0) { $0 + $1.bytes } }
}

struct UnicodeFontPackCatalog: Decodable, Sendable {
    static let downloadBase = "https://github.com/iebb/uniboard/releases/download/fonts-1.1-20261022/"
    static let completionDownloadBase = "https://github.com/iebb/uniboard/releases/download/fonts-1.1-20261022-complete/"
    /// Upstream Noto Color Emoji rebuilt as sbix, which Core Text draws on every
    /// supported iOS version; pinned to a dated release, never `latest`.
    static let emojiDownloadBase = "https://github.com/iebb/emojifonts/releases/download/2026.10.22/"
    static let downloadBases = [downloadBase, completionDownloadBase, emojiDownloadBase]
    static let maximumTotalBytes: Int64 = 96 * 1024 * 1024
    static let maximumCatalogBytes = 2 * 1024 * 1024
    let schemaVersion: Int
    let unicodeVersion: String
    let packs: [UnicodeFontPack]

    var isValid: Bool {
        guard schemaVersion == 1, unicodeVersion == "18.0.0", packs.count <= 8,
              Set(packs.map(\.id)).count == packs.count,
              packs.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 40
                  && $0.id.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
                  && !$0.title.isEmpty && !$0.detail.isEmpty && !$0.fonts.isEmpty }) else { return false }
        let fonts = packs.flatMap(\.fonts)
        return fonts.count <= 80 && fonts.allSatisfy(\.isValid)
            && Set(fonts.map { $0.asset.filename }).count == fonts.count
            && Set(fonts.map { $0.asset.postScriptName }).count == fonts.count
            && fonts.reduce(Int64(0)) { $0 + $1.bytes } <= Self.maximumTotalBytes
    }

    static func load(data: Data) -> Self? {
        guard data.count <= maximumCatalogBytes,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }

    static let bundled = loadBundled(resourceURL: Bundle.main.url(forResource: "DownloadableFonts", withExtension: "json", subdirectory: "Fonts"))

    static func loadBundled(resourceURL: URL?) -> Self {
        guard let url = resourceURL, let data = try? Data(contentsOf: url), let value = load(data: data) else {
            return Self(schemaVersion: 1, unicodeVersion: "18.0.0", packs: [])
        }
        return value
    }

    static func allowsRedirect(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host?.lowercased() ?? "")
    }

    static func acceptsProgress(_ written: Int64, expected: Int64) -> Bool {
        expected > 0 && expected <= 40 * 1024 * 1024 && written >= 0 && written <= expected
    }
}

/// The app installs verified files atomically into its App Group. The keyboard
/// only reads them; it never downloads, installs system fonts or needs network.
struct UnicodeFontDownloadStore: Sendable {
    struct FileMetadata: Sendable {
        let regular: Bool
        let symlink: Bool
        let bytes: Int64?
        let modified: Date?
    }
    typealias MetadataReader = @Sendable (URL) throws -> FileMetadata
    struct Receipt: Codable {
        let sha256: String
        let bytes: Int64
        let modified: Double
    }
    enum Failure: Error { case unavailable, invalidAsset, invalidSize, invalidFont, checksumMismatch }
    let directory: URL?
    var metadata: MetadataReader = { try Self.readMetadata($0) }
    static let shared = UnicodeFontDownloadStore(directory: FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)?
        .appendingPathComponent("PreviewFonts-v1", isDirectory: true))

    func installedURL(for font: UnicodeFontDownload) -> URL? {
        guard font.isValid, let directory, directory.isFileURL else { return nil }
        let file = directory.appendingPathComponent(font.asset.filename)
        let receiptURL = file.appendingPathExtension("receipt.json")
        guard let values = try? metadata(file), values.regular, !values.symlink,
              values.bytes == font.bytes, let modified = values.modified,
              let data = try? Self.readBounded(receiptURL, limit: 512),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.sha256 == font.asset.sha256, receipt.bytes == font.bytes,
              receipt.modified == modified.timeIntervalSince1970 else { return nil }
        return file
    }

    func install(_ temporary: URL, font: UnicodeFontDownload) throws {
        guard font.isValid, temporary.isFileURL else { throw Failure.invalidAsset }
        guard let directory, directory.isFileURL else { throw Failure.unavailable }
        let values = try metadata(temporary)
        guard values.regular, !values.symlink, values.bytes == font.bytes else { throw Failure.invalidSize }
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        var digest = SHA256(), total: Int64 = 0
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            total += Int64(chunk.count)
            guard total <= font.bytes else { throw Failure.invalidSize }
            if total == Int64(chunk.count) {
                let magic = Array(chunk.prefix(4))
                guard magic == [0x4F, 0x54, 0x54, 0x4F] || magic == [0, 1, 0, 0] else { throw Failure.invalidFont }
            }
            digest.update(data: chunk)
        }
        guard total == font.bytes else { throw Failure.invalidSize }
        guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == font.asset.sha256 else { throw Failure.checksumMismatch }
        try Self.prepareDirectory(directory)
        let incoming = directory.appendingPathComponent(".incoming-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: incoming) }
        try FileManager.default.copyItem(at: temporary, to: incoming)
        let destination = directory.appendingPathComponent(font.asset.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: incoming)
        } else { try FileManager.default.moveItem(at: incoming, to: destination) }
        let attributes = try metadata(destination)
        guard let modified = attributes.modified else { throw Failure.invalidFont }
        let receipt = Receipt(sha256: font.asset.sha256, bytes: font.bytes, modified: modified.timeIntervalSince1970)
        try JSONEncoder().encode(receipt).write(to: destination.appendingPathExtension("receipt.json"), options: .atomic)
        try updateRevision(in: directory)
    }

    func remove(_ font: UnicodeFontDownload) throws {
        guard font.isValid, let directory, directory.isFileURL else { throw Failure.unavailable }
        let file = directory.appendingPathComponent(font.asset.filename)
        for url in [file.appendingPathExtension("receipt.json"), file] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try updateRevision(in: directory)
    }

    var revision: String {
        guard let directory, let data = try? Self.readBounded(directory.appendingPathComponent("revision.txt"), limit: 64) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func readBounded(_ url: URL, limit: Int) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            guard let part = try handle.read(upToCount: limit + 1 - data.count), !part.isEmpty else { break }
            data.append(part)
        }
        return data.count <= limit ? data : nil
    }

    static func readMetadata(_ url: URL) throws -> FileMetadata {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        return FileMetadata(regular: values.isRegularFile == true, symlink: values.isSymbolicLink == true,
                            bytes: values.fileSize.map(Int64.init), modified: values.contentModificationDate)
    }

    private static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    private func updateRevision(in directory: URL) throws {
        try Self.prepareDirectory(directory)
        try Data(UUID().uuidString.utf8).write(to: directory.appendingPathComponent("revision.txt"), options: .atomic)
    }
}
