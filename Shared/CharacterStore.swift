import Foundation
import Combine

/// Collections belong to the current app/extension sandbox. No Full Access is needed.
@MainActor
final class CharacterStore: ObservableObject {
    static let shared = CharacterStore()
    @Published private(set) var favorites: [UInt32]
    @Published private(set) var recents: [UInt32]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = (defaults.array(forKey: "favoriteCodePoints") as? [NSNumber] ?? []).map(\.uint32Value)
        recents = (defaults.array(forKey: "recentCodePoints") as? [NSNumber] ?? []).map(\.uint32Value)
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

    func reset() {
        favorites = []
        recents = []
        defaults.removeObject(forKey: "favoriteCodePoints")
        defaults.removeObject(forKey: "recentCodePoints")
    }
}
