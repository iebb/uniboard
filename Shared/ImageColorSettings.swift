import Foundation

/// The Copy Image color and scale choice, shared through the current configuration
/// generation so the containing app sees what was chosen in the keyboard.
/// Only a preset id, two colors and a scale are stored, never text. The keyboard
/// writes it only with Full Access; without it, its choice stays local.
/// A new revision on every write tells the other process to adopt it.
struct ImageColorSettings {
    struct Value: Codable, Equatable, Sendable {
        var preset: String
        /// `#RRGGBB`.
        var customText: String
        /// `#RRGGBB` or `transparent`.
        var customBackground: String
        /// Pixels per point of the copied picture: 1, 2 or 3.
        var scale: Int = KeyboardImageScale.default.rawValue
    }
    struct Stored: Equatable, Sendable {
        var value: Value
        var revision: String
    }
    private struct File: Codable {
        let schemaVersion: Int
        let revision: String
        let preset: String
        let customText: String
        let customBackground: String
        /// Absent in files written before the scale choice: 3×.
        let scale: Int?
    }

    static let filename = "image-colors-v1.json"
    static let maximumPayloadBytes = 1024
    /// In the Copy Image panel's order.
    static let presetOrder = ["blackOnWhite", "blackOnClear", "whiteOnBlack", "whiteOnClear", "custom"]
    static let presets = Set(presetOrder)
    static let defaultValue = Value(preset: "blackOnWhite", customText: "#000000", customBackground: "#FFFFFF")
    static let shared = ImageColorSettings()

    let location: SharedConfigurationLocation

    init(location: SharedConfigurationLocation = .shared) { self.location = location }

    /// nil when nothing was shared yet or the file is unusable.
    func load() -> Stored? {
        guard let directory = location.currentDirectory(),
              let data = try? SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(Self.filename),
                                                                          limit: Self.maximumPayloadBytes + 1) else { return nil }
        return Self.decode(data)
    }

    /// True only when the migrated configuration has no colors file at all;
    /// an unusable file is kept as it is, never overwritten by a first publish.
    func isUnpublished() -> Bool {
        guard location.currentGeneration() != nil, let directory = location.currentDirectory() else { return false }
        do { return try SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(Self.filename), limit: 0) == nil }
        catch { return false }
    }

    /// Writes under the configuration lock into the current generation, never
    /// into the group root before migration. Throws when the value is
    /// invalid, the lock is busy, the configuration isn't migrated yet or
    /// the write fails.
    @discardableResult func save(_ value: Value) throws -> Stored {
        let stored = Stored(value: value, revision: UUID().uuidString)
        guard let data = Self.encode(stored) else { throw SharedConfigurationLocation.Failure.invalid }
        try location.withWriterLock {
            guard location.currentGeneration() != nil, let directory = location.currentDirectory() else { throw SharedConfigurationLocation.Failure.unavailable }
            try SharedConfigurationLocation.replaceFile(data, at: directory.appendingPathComponent(Self.filename))
        }
        return stored
    }

    static func isValid(_ value: Value) -> Bool {
        presets.contains(value.preset) && isHex(value.customText) && (value.customBackground == "transparent" || isHex(value.customBackground))
            && KeyboardImageScale(rawValue: value.scale) != nil
    }

    private static func isHex(_ text: String) -> Bool {
        text.utf8.count == 7 && text.hasPrefix("#") && text.utf8.dropFirst().allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    static func encode(_ stored: Stored) -> Data? {
        guard isValid(stored.value), SharedConfigurationLocation.isRevision(stored.revision) else { return nil }
        return try? SharedConfigurationLocation.encoder.encode(File(schemaVersion: 1, revision: stored.revision, preset: stored.value.preset,
            customText: stored.value.customText, customBackground: stored.value.customBackground, scale: stored.value.scale))
    }

    static func decode(_ data: Data) -> Stored? {
        guard data.count <= maximumPayloadBytes, let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == 1 else { return nil }
        let stored = Stored(value: Value(preset: file.preset, customText: file.customText, customBackground: file.customBackground,
                                         scale: file.scale ?? KeyboardImageScale.default.rawValue), revision: file.revision)
        return encode(stored) == nil ? nil : stored
    }

    /// The same colors under a fresh revision; unusable data is kept as it is.
    static func renewedRevision(_ data: Data) -> Data {
        decode(data).flatMap { encode(Stored(value: $0.value, revision: UUID().uuidString)) } ?? data
    }
}

/// Copy Image's resolution: pixels per point. It changes only the copied
/// picture's pixel count and DPI; the logical canvas, text and layout are the
/// same at every scale.
enum KeyboardImageScale: Int, CaseIterable, Comparable, Sendable {
    case x1 = 1, x2, x3

    /// Today's behavior.
    static let `default` = KeyboardImageScale.x3

    var factor: CGFloat { CGFloat(rawValue) }
    /// "3×".
    var label: String { "\(rawValue)×" }
    /// The PNG's DPI metadata: 72 per point.
    var dpi: Double { 72 * Double(rawValue) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The pixel size a Copy Image picture is actually produced at.
struct KeyboardImagePixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
    /// The scale drawn at: the one asked for, or a lower one when that
    /// would exceed the canvas limits.
    let scale: KeyboardImageScale
    let requested: KeyboardImageScale

    /// The requested scale didn't fit the limits.
    var isReduced: Bool { scale != requested }
    /// "1260 × 132 px".
    var label: String { "\(width) × \(height) px" }
}

/// The bounded canvas Copy Image draws into, small enough for keyboard
/// extension memory. Pure, so a picker can show sizes without rendering.
enum KeyboardImageCanvas {
    /// Generous for a 13-inch iPad's landscape row at 3×.
    static let maximumPixelWidth = 4800
    static let maximumPixelHeight = 1200
    static let maximumPixelCount = 2_400_000

    /// The size a logical `canvas` (in points) is produced at for `scale`:
    /// each side rounded up to whole pixels. When `scale` exceeds a limit the
    /// next lower scale that fits is used, so the size shown is always the
    /// size copied. Nil when even 1× doesn't fit, or the canvas is empty.
    static func pixelSize(canvas: CGSize, scale: KeyboardImageScale) -> KeyboardImagePixelSize? {
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 else { return nil }
        for candidate in KeyboardImageScale.allCases.reversed() where candidate <= scale {
            let width = (canvas.width * candidate.factor).rounded(.up), height = (canvas.height * candidate.factor).rounded(.up)
            guard width <= CGFloat(maximumPixelWidth), height <= CGFloat(maximumPixelHeight),
                  Int(width) * Int(height) <= maximumPixelCount else { continue }
            return KeyboardImagePixelSize(width: Int(width), height: Int(height), scale: candidate, requested: scale)
        }
        return nil
    }
}
