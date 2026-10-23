import Foundation
import CoreText
import CryptoKit

/// A font the person added in the app. Its coverage comes from the font's
/// own character map, read once when it is added.
struct CustomFont: Codable, Equatable, Identifiable, Sendable {
    let filename: String
    let displayName: String
    let postScriptName: String
    let sha256: String
    let ranges: [[UInt32]]
    /// Installed on the device rather than copied in; opened by PostScript name.
    var installed: Bool? = nil
    var id: String { filename }
}

/// Fonts added in the app for previews, tried before every other preview
/// font so Private Use and unsupported characters can be drawn. They live in
/// the App Group, so the keyboard reads them without Full Access.
final class CustomFontStore: @unchecked Sendable {
    enum Failure: Error { case unavailable, tooLarge, notAFont, tooMany }
    static let maximumFonts = 16
    static let maximumBytes = 40 * 1024 * 1024
    static let shared = CustomFontStore(directory: FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)?
        .appendingPathComponent("CustomFonts-v1", isDirectory: true))
    let directory: URL?
    // Accessed only under writerLock; readers never retain a stale cache on I/O errors.
    var manifestCache: FontLibraryManifestCache?

    /// The caller supplies a private library leaf beneath a trusted OS container.
    /// Canonicalize that container (e.g. /var -> /private/var), NOT the library
    /// leaf: a symlink substituted for CustomFonts-v1 must still be rejected.
    init(directory: URL?) {
        self.directory = directory.map { requested in
            requested.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent(requested.lastPathComponent, isDirectory: true)
        }
    }

    var fonts: [CustomFont] { (try? readManifest().fonts) ?? [] }
    var revision: String { (try? readManifest().generation) ?? "" }

    func url(forFilename filename: String) -> URL? {
        guard !filename.hasPrefix("Installed-"), fonts.contains(where: { $0.filename == filename }) else { return nil }
        return url(forRelativePath: filename)
    }

    /// Uses a font installed on the device, such as one from a font app, by its PostScript name.
    @discardableResult func addInstalled(postScriptName: String) throws -> CustomFont {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        guard let directory else { throw Failure.unavailable }
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        // An unknown name silently falls back to another font; refuse that.
        guard CTFontCopyPostScriptName(font) as String == postScriptName,
              postScriptName.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil else { throw Failure.notAFont }
        let filename = "Installed-" + postScriptName
        var fonts = try readManifest().fonts
        if let existing = fonts.first(where: { $0.filename == filename }) { return existing }
        guard fonts.count < Self.maximumFonts else { throw Failure.tooMany }
        let ranges = Self.ranges(CTFontCopyCharacterSet(font))
        guard !ranges.isEmpty else { throw Failure.notAFont }
        let custom = CustomFont(filename: filename, displayName: CTFontCopyFullName(font) as String,
                                postScriptName: postScriptName, sha256: "", ranges: ranges, installed: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fonts.append(custom)
        try save(fonts, in: directory)
        return custom
    }

    /// Adds a TrueType or OpenType font, or returns the same font if it was already added.
    @discardableResult func add(_ data: Data) throws -> CustomFont {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        guard let directory else { throw Failure.unavailable }
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        let magic = Array(data.prefix(4))
        guard [[0x4F, 0x54, 0x54, 0x4F], [0, 1, 0, 0], [0x74, 0x72, 0x75, 0x65]].contains(magic),
              let provider = CGDataProvider(data: data as CFData), let graphics = CGFont(provider),
              let postScriptName = graphics.postScriptName as String? else { throw Failure.notAFont }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var fonts = try readManifest().fonts
        if let existing = fonts.first(where: { $0.sha256 == digest }) {
            try ensureImmutableBinary(data, filename: existing.filename)
            var manifest = try readManifest()
            let indexes = manifest.downloads.indices.filter { manifest.downloads[$0].filename == existing.filename }
            if indexes.contains(where: { !manifest.downloads[$0].retainsImportedEntry }) {
                for index in indexes { manifest.downloads[index].retainsImportedEntry = true }
                try commitManifest(manifest)
            }
            return existing
        }
        guard fonts.count < Self.maximumFonts else { throw Failure.tooMany }
        let font = CTFontCreateWithGraphicsFont(graphics, 12, nil, nil)
        let ranges = Self.ranges(CTFontCopyCharacterSet(font))
        guard !ranges.isEmpty else { throw Failure.notAFont }
        let custom = CustomFont(filename: "Custom-\(digest).\(magic == [0x4F, 0x54, 0x54, 0x4F] ? "otf" : "ttf")",
                                displayName: CTFontCopyFullName(font) as String, postScriptName: postScriptName,
                                sha256: digest, ranges: ranges)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = url(forRelativePath: custom.filename) else { throw Failure.unavailable }
        _ = destination
        try ensureImmutableBinary(data, filename: custom.filename)
        fonts.append(custom)
        try save(fonts, in: directory)
        return custom
    }

    func remove(_ font: CustomFont) throws {
        Self.writerLock.lock(); defer { Self.writerLock.unlock() }
        guard let directory else { throw Failure.unavailable }
        // Retain immutable bytes for readers holding a previous snapshot.
        try save(try readManifest().fonts.filter { $0.filename != font.filename }, in: directory)
    }

    private func save(_ fonts: [CustomFont], in directory: URL) throws {
        var manifest = try readManifest()
        manifest.fonts = fonts
        let names = Set(fonts.map(\.filename))
        manifest.downloads.removeAll { !names.contains($0.filename) }
        try commitManifest(manifest)
    }

    static func validFilename(_ name: String) -> Bool {
        name.range(of: #"^(Custom-[0-9a-f]{16,64}\.(ttf|otf)|Installed-[A-Za-z0-9._-]{1,100})$"#, options: .regularExpression) != nil
    }

    /// Scalar ranges a character set covers, without surrogates.
    static func ranges(_ set: CFCharacterSet) -> [[UInt32]] {
        var ranges: [[UInt32]] = []
        var start: UInt32?
        for plane in 0...16 where CFCharacterSetHasMemberInPlane(set, CFIndex(plane)) {
            let first = UInt32(plane) << 16
            for point in first...(first | 0xFFFF) {
                let member = !(0xD800...0xDFFF).contains(point) && CFCharacterSetIsLongCharacterMember(set, point)
                if member, start == nil { start = point }
                if !member, let open = start { ranges.append([open, point - 1]); start = nil }
            }
            if let open = start { ranges.append([open, first | 0xFFFF]); start = nil }
        }
        return ranges
    }
}
