import Foundation

/// A browsing preference, never a preferred insertion tone or a saved-entry transform.
enum SkinToneVariants: String, CaseIterable, Sendable {
    case all
    case fewer

    var title: String {
        switch self {
        case .all: return "All Variants"
        case .fewer: return "Fewer Variants"
        }
    }
}

/// Pure shared app/keyboard projection. Compare scalar arrays, not Swift Strings
/// (which compare canonically equivalent text). Only remove tone modifiers when
/// constructing a lookup key; never return that constructed sequence to callers.
enum EmojiBrowsingPolicy {
    static func project(_ entries: [UnicodeEmojiEntry], skinToneVariants: SkinToneVariants,
                        query: String = "") -> [UnicodeEmojiEntry] {
        guard skinToneVariants == .fewer,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return entries }
        let sequences = Set(entries.map(\.codePoints))
        var result: [UnicodeEmojiEntry] = []
        result.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            if index & 255 == 0 && Task.isCancelled { return [] }
            let base = entry.codePoints.filter { !(0x1F3FB...0x1F3FF).contains($0) }
            // Keep unmatched whole sequences, including mixed-tone/multi-person
            // sequences whose untoned spelling requires different ZWJ/VS components.
            if base.count == entry.codePoints.count || !sequences.contains(base) {
                result.append(entry)
            }
        }
        return result
    }
}

/// Independent local app/keyboard browsing preference. The app writes and posts
/// changedNotification only after success; the keyboard reads on appear/notification.
/// Stored at the App Group ROOT, deliberately outside configuration generations:
/// imports, undo and legacy configuration migration must not reset this choice.
/// Missing, unsupported or unreadable data preserves the legacy full catalog.
struct EmojiBrowsingSetting {
    static let filename = "emoji-browsing-v1.json"
    static let maximumPayloadBytes = 256
    static let changedNotification = "ad.neko.uniboard.emojiBrowsingChanged"
    static let shared = EmojiBrowsingSetting()

    private struct File: Codable {
        let schemaVersion: Int
        let fewerVariants: Bool
    }

    let directory: () -> URL?

    init(directory: @escaping () -> URL? = { SharedConfigurationLocation.shared.root() }) {
        self.directory = directory
    }

    func load() -> SkinToneVariants {
        guard let directory = directory(),
              let data = try? SharedConfigurationLocation.readRegularFile(
                directory.appendingPathComponent(Self.filename), limit: Self.maximumPayloadBytes + 1)
        else { return .all }
        return Self.decode(data) ?? .all
    }

    @discardableResult func save(_ value: SkinToneVariants) -> Bool {
        guard let directory = directory(),
              (try? SharedConfigurationLocation.replaceFile(Self.encode(value),
                at: directory.appendingPathComponent(Self.filename))) != nil else { return false }
        return true
    }

    static func encode(_ value: SkinToneVariants) -> Data {
        // Fixed Boolean and schema; encoding cannot fail.
        try! SharedConfigurationLocation.encoder.encode(File(schemaVersion: 1, fewerVariants: value == .fewer))
    }

    static func decode(_ data: Data) -> SkinToneVariants? {
        guard data.count <= maximumPayloadBytes,
              let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == 1 else { return nil }
        return file.fewerVariants ? .fewer : .all
    }
}
