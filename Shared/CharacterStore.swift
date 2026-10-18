import Foundation
import Combine
import CoreFoundation

/// Collections belong to the current app/extension sandbox. No Full Access is needed.
@MainActor
final class CharacterStore: ObservableObject {
    static let shared = CharacterStore()
    @Published private(set) var favorites: [UInt32]
    @Published private(set) var recents: [UInt32]
    @Published private(set) var favoriteEmojiIDs: [String]
    @Published private(set) var recentEmojiIDs: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Self.restoredCodePoints(defaults.array(forKey: "favoriteCodePoints"))
        recents = Array(Self.restoredCodePoints(defaults.array(forKey: "recentCodePoints")).prefix(60))
        favoriteEmojiIDs = Self.restoredEmojiIDs(defaults.array(forKey: "favoriteEmojiSequences"))
        recentEmojiIDs = Array(Self.restoredEmojiIDs(defaults.array(forKey: "recentEmojiSequences")).prefix(60))
    }

    // Preferences can outlive an app version or contain partially migrated
    // values. Reject invalid scalars before numeric conversion and keep the
    // first occurrence so SwiftUI identities and collection order stay stable.
    private static func restoredCodePoints(_ values: [Any]?) -> [UInt32] {
        var seen = Set<UInt32>()
        return (values ?? []).compactMap { value in
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let raw = number.doubleValue
            guard raw.isFinite, raw >= 0, raw <= 0x10FFFF, raw.rounded(.towardZero) == raw else { return nil }
            let point = UInt32(raw)
            guard Unicode.Scalar(point) != nil, seen.insert(point).inserted else { return nil }
            return point
        }
    }

    private static func isCanonicalEmojiID(_ id: String) -> Bool {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard (4...6).contains(part.utf8.count),
                  part.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
                  let point = UInt32(part, radix: 16), Unicode.Scalar(point) != nil else { return false }
            return String(format: "%04X", point) == part
        }
    }

    private static func restoredEmojiIDs(_ values: [Any]?) -> [String] {
        var seen = Set<String>()
        return (values ?? []).compactMap { value in
            guard let id = value as? String, isCanonicalEmojiID(id), seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private static func validEntry(_ entry: UnicodeEmojiEntry) -> Bool {
        !entry.codePoints.isEmpty && entry.codePoints.allSatisfy { Unicode.Scalar($0) != nil }
            && entry.id == entry.codePoints.map { String(format: "%04X", $0) }.joined(separator: "-")
    }

    func isFavorite(_ codePoint: UInt32) -> Bool { favorites.contains(codePoint) }

    func toggleFavorite(_ codePoint: UInt32) {
        guard Unicode.Scalar(codePoint) != nil else { return }
        if isFavorite(codePoint) { favorites.removeAll { $0 == codePoint } }
        else { favorites.insert(codePoint, at: 0) }
        defaults.set(favorites.map { NSNumber(value: $0) }, forKey: "favoriteCodePoints")
    }

    func recordUse(_ codePoint: UInt32) {
        guard Unicode.Scalar(codePoint) != nil else { return }
        recents.removeAll { $0 == codePoint }
        recents.insert(codePoint, at: 0)
        recents = Array(recents.prefix(60))
        defaults.set(recents.map { NSNumber(value: $0) }, forKey: "recentCodePoints")
    }

    var favoriteCharacters: [UnicodeCharacter] { favoriteCharacters(in: .shared) }
    var recentCharacters: [UnicodeCharacter] { recentCharacters(in: .shared) }

    func favoriteCharacters(in catalog: UnicodeCatalog) -> [UnicodeCharacter] {
        favorites.compactMap { catalog.character(at: $0) }.filter { $0.category != "Cn" }
    }
    func recentCharacters(in catalog: UnicodeCatalog) -> [UnicodeCharacter] {
        recents.compactMap { catalog.character(at: $0) }.filter { $0.category != "Cn" }
    }
    func isFavoriteEmoji(_ id: String) -> Bool { favoriteEmojiIDs.contains(id) }
    func toggleFavoriteEmoji(_ entry: UnicodeEmojiEntry) {
        guard Self.validEntry(entry) else { return }
        if isFavoriteEmoji(entry.id) { favoriteEmojiIDs.removeAll { $0 == entry.id } }
        else { favoriteEmojiIDs.insert(entry.id, at: 0) }
        defaults.set(favoriteEmojiIDs, forKey: "favoriteEmojiSequences")
    }
    func recordEmojiUse(_ entry: UnicodeEmojiEntry) {
        guard Self.validEntry(entry) else { return }
        recentEmojiIDs.removeAll { $0 == entry.id }
        recentEmojiIDs.insert(entry.id, at: 0)
        recentEmojiIDs = Array(recentEmojiIDs.prefix(60))
        defaults.set(recentEmojiIDs, forKey: "recentEmojiSequences")
    }
    func favoriteEmojiEntries(in catalog: EmojiCatalog) -> [UnicodeEmojiEntry] {
        let entries = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.id, $0) })
        return favoriteEmojiIDs.compactMap { entries[$0] }
    }
    func recentEmojiEntries(in catalog: EmojiCatalog) -> [UnicodeEmojiEntry] {
        let entries = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.id, $0) })
        return recentEmojiIDs.compactMap { entries[$0] }
    }

    func reset() {
        favorites = []
        recents = []
        favoriteEmojiIDs = []
        recentEmojiIDs = []
        defaults.removeObject(forKey: "favoriteCodePoints")
        defaults.removeObject(forKey: "recentCodePoints")
        defaults.removeObject(forKey: "favoriteEmojiSequences")
        defaults.removeObject(forKey: "recentEmojiSequences")
    }
}
