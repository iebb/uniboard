import Foundation
import CoreText
import CryptoKit

/// A font the person added in the app. Its coverage comes from the font's
/// own character map, read once when it is added.
struct CustomFont: Codable, Equatable, Identifiable {
    let filename: String
    let displayName: String
    let postScriptName: String
    let sha256: String
    let ranges: [[UInt32]]
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

    init(directory: URL?) { self.directory = directory }

    var fonts: [CustomFont] {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("fonts.json")),
              data.count <= 4 * 1024 * 1024,
              let fonts = try? JSONDecoder().decode([CustomFont].self, from: data) else { return [] }
        return fonts.filter { Self.validFilename($0.filename) }
    }

    /// Changes whenever a font is added or removed.
    var revision: String {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("revision.txt")),
              data.count <= 64 else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func url(forFilename filename: String) -> URL? {
        guard Self.validFilename(filename), let directory, fonts.contains(where: { $0.filename == filename }) else { return nil }
        return directory.appendingPathComponent(filename)
    }

    /// Adds a TrueType or OpenType font, or returns the same font if it was already added.
    @discardableResult func add(_ data: Data) throws -> CustomFont {
        guard let directory else { throw Failure.unavailable }
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        let magic = Array(data.prefix(4))
        guard [[0x4F, 0x54, 0x54, 0x4F], [0, 1, 0, 0], [0x74, 0x72, 0x75, 0x65]].contains(magic),
              let provider = CGDataProvider(data: data as CFData), let graphics = CGFont(provider),
              let postScriptName = graphics.postScriptName as String? else { throw Failure.notAFont }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var fonts = fonts
        if let existing = fonts.first(where: { $0.sha256 == digest }) { return existing }
        guard fonts.count < Self.maximumFonts else { throw Failure.tooMany }
        let font = CTFontCreateWithGraphicsFont(graphics, 12, nil, nil)
        let ranges = Self.ranges(CTFontCopyCharacterSet(font))
        guard !ranges.isEmpty else { throw Failure.notAFont }
        let custom = CustomFont(filename: "Custom-\(digest.prefix(16)).\(magic == [0x4F, 0x54, 0x54, 0x4F] ? "otf" : "ttf")",
                                displayName: CTFontCopyFullName(font) as String, postScriptName: postScriptName,
                                sha256: digest, ranges: ranges)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(custom.filename), options: .atomic)
        fonts.append(custom)
        try save(fonts, in: directory)
        return custom
    }

    func remove(_ font: CustomFont) throws {
        guard let directory else { throw Failure.unavailable }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(font.filename))
        try save(fonts.filter { $0.filename != font.filename }, in: directory)
    }

    private func save(_ fonts: [CustomFont], in directory: URL) throws {
        try JSONEncoder().encode(fonts).write(to: directory.appendingPathComponent("fonts.json"), options: .atomic)
        try Data(UUID().uuidString.utf8).write(to: directory.appendingPathComponent("revision.txt"), options: .atomic)
    }

    private static func validFilename(_ name: String) -> Bool {
        name.range(of: #"^Custom-[0-9a-f]{16}\.(ttf|otf)$"#, options: .regularExpression) != nil
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
