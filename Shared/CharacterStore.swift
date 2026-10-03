import Foundation
import Combine

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
        favorites = (defaults.array(forKey: "favoriteCodePoints") as? [NSNumber] ?? []).map(\.uint32Value)
        recents = (defaults.array(forKey: "recentCodePoints") as? [NSNumber] ?? []).map(\.uint32Value)
        favoriteEmojiIDs = defaults.stringArray(forKey: "favoriteEmojiSequences") ?? []
        recentEmojiIDs = defaults.stringArray(forKey: "recentEmojiSequences") ?? []
    }

    func isFavorite(_ codePoint: UInt32) -> Bool { favorites.contains(codePoint) }

    func toggleFavorite(_ codePoint: UInt32) {
        if isFavorite(codePoint) { favorites.removeAll { $0 == codePoint } }
        else { favorites.insert(codePoint, at: 0) }
        defaults.set(favorites.map { NSNumber(value: $0) }, forKey: "favoriteCodePoints")
    }

    func recordUse(_ codePoint: UInt32) {
        recents.removeAll { $0 == codePoint }
        recents.insert(codePoint, at: 0)
        recents = Array(recents.prefix(60))
        defaults.set(recents.map { NSNumber(value: $0) }, forKey: "recentCodePoints")
    }

    var favoriteCharacters: [UnicodeCharacter] { favorites.compactMap { UnicodeCatalog.shared.character(at: $0) } }
    var recentCharacters: [UnicodeCharacter] { recents.compactMap { UnicodeCatalog.shared.character(at: $0) } }

    func favoriteCharacters(in catalog: UnicodeCatalog) -> [UnicodeCharacter] {
        favorites.compactMap { catalog.character(at: $0) }.filter { $0.category != "Cn" }
    }
    func recentCharacters(in catalog: UnicodeCatalog) -> [UnicodeCharacter] {
        recents.compactMap { catalog.character(at: $0) }.filter { $0.category != "Cn" }
    }
    func isFavoriteEmoji(_ id: String) -> Bool { favoriteEmojiIDs.contains(id) }
    func toggleFavoriteEmoji(_ entry: UnicodeEmojiEntry) {
        if isFavoriteEmoji(entry.id) { favoriteEmojiIDs.removeAll { $0 == entry.id } }
        else { favoriteEmojiIDs.insert(entry.id, at: 0) }
        defaults.set(favoriteEmojiIDs, forKey: "favoriteEmojiSequences")
    }
    func recordEmojiUse(_ entry: UnicodeEmojiEntry) {
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
