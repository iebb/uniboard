import Foundation
import Combine
import CoreFoundation

/// Text is deliberately compared by UTF-16, not String's canonical equality.
/// A keyboard must preserve the exact original scalar/emoji sequence.
struct SymbolBoardKey: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    /// Hold choices.
    var variants: [String]
    /// Swipe-up and swipe-down choices; nil leaves the gesture off.
    var up: [String]? = nil
    var down: [String]? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && exact(lhs.text, rhs.text) && exact(lhs.variants, rhs.variants)
            && exact(lhs.up ?? [], rhs.up ?? []) && exact(lhs.down ?? [], rhs.down ?? [])
    }
    static func exact(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { exact($0, $1) }
    }
    static func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }
}

struct SymbolBoard: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var keys: [SymbolBoardKey]
    /// The page's rows as `SymbolPageLayout` text; nil lays keys out in rows of ten.
    var layout: String? = nil
}

struct SymbolBoardPickerTarget: Equatable {
    let boardID: String
    /// nil adds an original key; a key ID appends an exact variant.
    let keyID: String?
}

/// Pages are configured in the app and shared through `SymbolPageSettings`;
/// the keyboard only reads them. The built-in Favorites page shares only
/// explicit saved symbols through the App Group, with a local three-way merge
/// baseline. The open page stays local to each process.
@MainActor
final class SymbolBoardStore: ObservableObject {
    private static let isApp = Bundle.main.bundleURL.pathExtension != "appex"
    static let shared = SymbolBoardStore(sync: .shared, pages: .shared, sharedWriteAllowed: isApp, configuresPages: isApp)
    static let storageKey = "keyboard.symbolBoards.v1"
    static let stockID = "stock-symbols"
    static let favoritesID = "migrated-favorites"
    static let maximumBoards = 16
    static let maximumKeys = 256
    static let maximumMigratedFavorites = 4096
    static let maximumVariants = 16
    static let maximumTextScalars = 64
    static let maximumPayloadBytes = 512 * 1024

    enum LoadIssue: String {
        case unwritable = "Pages could not be saved. Close and reopen the keyboard before editing."
        case unreadable = "Saved pages could not be read. Their original data has been kept."
        case unsupportedVersion = "These pages use a newer format. Their original data has been kept."
        case oversized = "Saved pages exceed the storage limit. Their original data has been kept."
        case legacyTooLarge = "Original favorites have been retained. Editing is disabled because they exceed the import limit. Only entries available in the selected Unicode edition are shown below."
    }
    private struct State: Codable {
        var version: Int
        var activeBoardID: String
        var preferredStarBoardID: String?
        var boards: [SymbolBoard]
        var favoriteBaseline: [String]? = nil
    }
    @Published private(set) var boards: [SymbolBoard]
    @Published private(set) var activeBoardID: String
    @Published private(set) var preferredStarBoardID: String
    @Published private(set) var loadIssue: LoadIssue?
    /// One complete Data value is persisted before adopting any in-memory
    /// fields. An injected writer must leave prior bytes untouched on failure.
    enum SyncStatus { case local, current, fullAccessRequired, unavailable }
    @Published private(set) var syncStatus: SyncStatus = .local
    private let sync: FavoriteSync?
    private let pages: SymbolPageSettings?
    /// Only the app creates, edits and orders pages; the keyboard keeps its
    /// own open page and Favorites edits.
    let configuresPages: Bool
    private var sharedWriteAllowed: Bool
    private var favoriteBaseline: [String] = []
    private var syncing = false
    private let persist: (Data) -> Bool
    var activeBoard: SymbolBoard { Self.selectedBoard(in: boards, activeBoardID: activeBoardID) }
    var preferredStarBoard: SymbolBoard { Self.selectedBoard(in: boards, activeBoardID: preferredStarBoardID) }
    /// Persistence validates the reference before adopting state. This also
    /// defines a safe selection for a transient empty or missing-ID input.
    static func selectedBoard(in boards: [SymbolBoard], activeBoardID: String) -> SymbolBoard {
        if let selected = boards.first(where: { $0.id == activeBoardID }) { return selected }
        if let first = boards.first { return first }
        return initialBoards(favorites: [])[0]
    }
    var hasLegacyFallback: Bool { loadIssue == .legacyTooLarge }
    var canEdit: Bool { loadIssue == nil }

    init(defaults: UserDefaults = .standard, persist: ((Data) -> Bool)? = nil,
         sync: FavoriteSync? = nil, pages: SymbolPageSettings? = nil,
         sharedWriteAllowed: Bool = false, configuresPages: Bool = true) {
        self.sync = sync
        self.pages = pages
        self.configuresPages = configuresPages
        self.sharedWriteAllowed = sharedWriteAllowed
        defer { refreshPages(); refreshFavorites() }
        self.persist = persist ?? { data in
            defaults.set(data, forKey: SymbolBoardStore.storageKey)
            // UserDefaults offers no durable-disk acknowledgement. Readback
            // verifies the complete local value before UI state is adopted.
            return defaults.data(forKey: SymbolBoardStore.storageKey) == data
        }
        boards = Self.initialBoards(favorites: [])
        activeBoardID = Self.stockID
        preferredStarBoardID = Self.favoritesID
        if let stored = defaults.object(forKey: Self.storageKey) {
            guard let data = stored as? Data else { loadIssue = .unreadable; return }
            guard data.count <= Self.maximumPayloadBytes else { loadIssue = .oversized; return }
            guard var state = try? JSONDecoder().decode(State.self, from: data) else { loadIssue = .unreadable; return }
            guard state.version == 1 || state.version == 2 else { loadIssue = .unsupportedVersion; return }
            // Read migration never overwrites the original v1 payload. Its
            // first successful mutation writes v2 with this explicit choice.
            if state.version == 1 { state.preferredStarBoardID = Self.favoritesID }
            guard state.favoriteBaseline.map(FavoriteSync.valid) ?? true, let preferred = state.preferredStarBoardID, Self.valid(state) else { loadIssue = .unreadable; return }
            favoriteBaseline = state.favoriteBaseline ?? []
            boards = state.boards
            activeBoardID = state.activeBoardID
            preferredStarBoardID = preferred
        } else {
            guard let favorites = Self.legacyFavorites(in: defaults) else { loadIssue = .legacyTooLarge; return }
            let state = State(version: 2, activeBoardID: Self.stockID, preferredStarBoardID: Self.favoritesID,
                              boards: Self.initialBoards(favorites: favorites))
            guard let data = Self.encoded(state) else { loadIssue = .legacyTooLarge; return }
            guard self.persist(data) else { loadIssue = .unwritable; return }
            boards = state.boards
        }
    }

    func key(boardID: String, keyID: String) -> SymbolBoardKey? {
        boards.first { $0.id == boardID }?.keys.first { $0.id == keyID }
    }
    func contains(_ text: String) -> Bool {
        boards.contains { $0.keys.contains { SymbolBoardKey.exact($0.text, text) } }
    }
    /// An empty selected board leaves the fixed strip useful without changing
    /// the user's preferred Star board or their active-board preference.
    var typingBoard: SymbolBoard {
        if activeBoard.keys.isEmpty, let stock = boards.first(where: { $0.id == Self.stockID }) { return stock }
        return activeBoard
    }

    @discardableResult func selectBoard(_ id: String) -> Bool {
        guard boards.contains(where: { $0.id == id }) else { return false }
        // Selecting the board already shown requires no persistence. This
        // also keeps a valid current board usable while editing is locked.
        if activeBoardID == id { return true }
        return commit(boards, active: id)
    }
    /// Choosing a temporary board never changes the star's preferred target.
    @discardableResult func setPreferredStarBoard(_ id: String) -> Bool {
        guard boards.contains(where: { $0.id == id }) else { return false }
        return commit(boards, preferred: id)
    }
    @discardableResult func selectPreferredStarBoard() -> Bool {
        selectBoard(preferredStarBoardID)
    }
    @discardableResult func createBoard(named name: String) -> String? {
        guard boards.count < Self.maximumBoards, let name = Self.validName(name) else { return nil }
        let id = UUID().uuidString.lowercased()
        return commit(boards + [SymbolBoard(id: id, name: name, keys: [])], active: id) ? id : nil
    }
    @discardableResult func renameBoard(_ id: String, to name: String) -> Bool {
        guard let name = Self.validName(name), let index = boards.firstIndex(where: { $0.id == id }) else { return false }
        var next = boards
        next[index].name = name
        return commit(next)
    }
    @discardableResult func deleteBoard(_ id: String) -> Bool {
        guard id != Self.stockID, id != Self.favoritesID, boards.contains(where: { $0.id == id }) else { return false }
        return commit(boards.filter { $0.id != id }, active: activeBoardID == id ? Self.stockID : activeBoardID,
                      preferred: preferredStarBoardID == id ? Self.favoritesID : preferredStarBoardID)
    }
    func canMoveBoard(_ id: String, by offset: Int) -> Bool {
        guard canEdit, offset == -1 || offset == 1,
              let index = boards.firstIndex(where: { $0.id == id }) else { return false }
        return boards.indices.contains(index + offset)
    }
    @discardableResult func moveBoard(_ id: String, by offset: Int) -> Bool {
        guard canMoveBoard(id, by: offset), let index = boards.firstIndex(where: { $0.id == id }) else { return false }
        let target = index + offset
        var next = boards
        next.swapAt(index, target)
        return commit(next)
    }
    /// List-style reordering, as the app's Pages screen offers it.
    @discardableResult func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        guard canEdit, let next = Self.moving(boards, fromOffsets: source, toOffset: destination) else { return false }
        return next.map(\.id) == boards.map(\.id) || commit(next)
    }
    @discardableResult func moveKeys(boardID: String, fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        guard let index = boards.firstIndex(where: { $0.id == boardID }),
              let keys = Self.moving(boards[index].keys, fromOffsets: source, toOffset: destination) else { return false }
        var next = boards
        next[index].keys = keys
        return next == boards || commit(next)
    }
    private static func moving<T>(_ items: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T]? {
        guard !source.isEmpty, source.allSatisfy(items.indices.contains), (0...items.count).contains(destination) else { return nil }
        let moved = source.sorted().map { items[$0] }
        var rest = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moved, at: destination - source.filter { $0 < destination }.count)
        return rest
    }
    @discardableResult func add(text: String, to boardID: String) -> String? {
        if boardID == Self.favoritesID { refreshFavorites() }
        guard canEdit, Self.validText(text), let index = boards.firstIndex(where: { $0.id == boardID }) else { return nil }
        if let existing = boards[index].keys.first(where: { SymbolBoardKey.exact($0.text, text) }) { return existing.id }
        guard boards[index].keys.count < Self.keyLimit(boardID) else { return nil }
        let key = SymbolBoardKey(id: UUID().uuidString.lowercased(), text: text, variants: [])
        var next = boards
        // Only the app edits rows; in the keyboard, new Favorites flow on in rows of ten.
        if configuresPages, var layout = next[index].layout.flatMap(SymbolPageLayout.init) {
            layout = layout.fitted(keyCount: next[index].keys.count)
            layout.appendKey()
            next[index].layout = layout.text
        }
        next[index].keys.append(key)
        return commit(next) ? key.id : nil
    }
    @discardableResult func removeKey(boardID: String, keyID: String) -> Bool {
        guard let index = boards.firstIndex(where: { $0.id == boardID }),
              let position = boards[index].keys.firstIndex(where: { $0.id == keyID }) else { return false }
        var next = boards
        // Only the app edits rows; in the keyboard, new Favorites flow on in rows of ten.
        if configuresPages, var layout = next[index].layout.flatMap(SymbolPageLayout.init) {
            layout = layout.fitted(keyCount: next[index].keys.count)
            layout.removeKeySlot(position)
            next[index].layout = layout.rows.isEmpty ? nil : layout.text
        }
        next[index].keys.remove(at: position)
        return commit(next)
    }
    @discardableResult func moveKey(boardID: String, keyID: String, by offset: Int) -> Bool {
        guard let board = boards.firstIndex(where: { $0.id == boardID }),
              let index = boards[board].keys.firstIndex(where: { $0.id == keyID }), offset == -1 || offset == 1 else { return false }
        let target = index + offset
        guard boards[board].keys.indices.contains(target) else { return false }
        var next = boards
        next[board].keys.swapAt(index, target)
        return commit(next)
    }
    /// A page file another app install can import: each custom page's name,
    /// keys, variants and rows. Favorites and the built-in Symbols page stay out.
    private struct PageFile: Codable {
        struct Page: Codable {
            let name: String
            let keys: [Key]
            var layout: String?
        }
        struct Key: Codable {
            let text: String
            let variants: [String]
            var up: [String]? = nil
            var down: [String]? = nil
        }
        let schemaVersion: Int
        let pages: [Page]
    }

    var customPages: [SymbolBoard] { boards.filter { $0.id != Self.stockID && $0.id != Self.favoritesID } }

    func exportedPages() -> Data? {
        let file = PageFile(schemaVersion: 1, pages: customPages.map { board in
            PageFile.Page(name: board.name, keys: board.keys.map { PageFile.Key(text: $0.text, variants: $0.variants, up: $0.up, down: $0.down) },
                          layout: board.layout)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(file)
    }

    /// Adds a file's pages as new pages, returning how many. nil when the file
    /// is not a page file, is invalid, or the pages would not fit.
    @discardableResult func importPages(_ data: Data) -> Int? {
        guard data.count <= Self.maximumPayloadBytes, let file = try? JSONDecoder().decode(PageFile.self, from: data),
              file.schemaVersion == 1, !file.pages.isEmpty, boards.count + file.pages.count <= Self.maximumBoards else { return nil }
        let imported = file.pages.map { page in
            SymbolBoard(id: UUID().uuidString.lowercased(), name: page.name, keys: page.keys.map {
                SymbolBoardKey(id: UUID().uuidString.lowercased(), text: $0.text, variants: $0.variants, up: $0.up, down: $0.down)
            }, layout: page.layout)
        }
        // Committing validates every name, key, variant and row.
        return commit(boards + imported) ? imported.count : nil
    }

    /// Saves a page's rows, nil for rows of ten, and reorders its keys when a
    /// key moved to another slot, as one change.
    @discardableResult func setLayout(boardID: String, layout: SymbolPageLayout?, keyMove: SymbolPageLayout.KeyMove? = nil) -> Bool {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return false }
        var next = boards
        if let keyMove {
            let count = next[index].keys.count
            guard next[index].keys.indices.contains(keyMove.from), (0..<count).contains(keyMove.to),
                  let keys = Self.moving(next[index].keys, fromOffsets: [keyMove.from],
                                         toOffset: keyMove.to > keyMove.from ? keyMove.to + 1 : keyMove.to) else { return false }
            next[index].keys = keys
        }
        guard layout.map({ SymbolPageLayout($0.text) != nil }) ?? true else { return false }
        next[index].layout = layout?.text
        return next == boards || commit(next)
    }
    @discardableResult func setVariants(boardID: String, keyID: String, variants: [String]) -> Bool {
        guard let board = boards.firstIndex(where: { $0.id == boardID }),
              let index = boards[board].keys.firstIndex(where: { $0.id == keyID }),
              variants.allSatisfy(Self.validText) else { return false }
        let original = boards[board].keys[index].text
        let unique = Self.uniqueExact(variants.filter { !SymbolBoardKey.exact($0, original) })
        guard unique.count <= Self.maximumVariants else { return false }
        var next = boards
        next[board].keys[index].variants = unique
        return commit(next)
    }
    /// Saves a key's hold, swipe-up and swipe-down choices as one change,
    /// such as a choice dragged from one to another.
    @discardableResult func setLayers(boardID: String, keyID: String, variants: [String], up: [String], down: [String]) -> Bool {
        guard let board = boards.firstIndex(where: { $0.id == boardID }),
              let index = boards[board].keys.firstIndex(where: { $0.id == keyID }),
              (variants + up + down).allSatisfy(Self.validText) else { return false }
        let original = boards[board].keys[index].text
        var next = boards
        next[board].keys[index].variants = Self.uniqueExact(variants.filter { !SymbolBoardKey.exact($0, original) })
        next[board].keys[index].up = up.isEmpty ? nil : Self.uniqueExact(up)
        next[board].keys[index].down = down.isEmpty ? nil : Self.uniqueExact(down)
        // Saving checks each layer's size.
        return commit(next)
    }
    /// Saves a key's swipe-up or swipe-down choices; none turns the swipe off.
    @discardableResult func setSwipe(boardID: String, keyID: String, up: Bool, choices: [String]) -> Bool {
        guard let board = boards.firstIndex(where: { $0.id == boardID }),
              let index = boards[board].keys.firstIndex(where: { $0.id == keyID }),
              choices.allSatisfy(Self.validText) else { return false }
        let unique = Self.uniqueExact(choices)
        guard unique.count <= Self.maximumVariants else { return false }
        var next = boards
        if up { next[board].keys[index].up = unique.isEmpty ? nil : unique } else { next[board].keys[index].down = unique.isEmpty ? nil : unique }
        return commit(next)
    }

    private func commit(_ next: [SymbolBoard], active: String? = nil, preferred: String? = nil) -> Bool {
        guard canEdit else { return false }
        let selectedPreferred = preferred ?? preferredStarBoardID
        let state = State(version: 2, activeBoardID: active ?? activeBoardID,
                          preferredStarBoardID: selectedPreferred, boards: next, favoriteBaseline: sync == nil ? nil : favoriteBaseline)
        guard let data = Self.encoded(state) else { return false }
        if let pages, Self.shareable(next) != Self.shareable(boards) || selectedPreferred != preferredStarBoardID {
            // A page change is published to the shared file before it is adopted.
            guard configuresPages, pages.save(.init(pages: Self.shareable(next), starPageID: selectedPreferred)) else { return false }
        }
        guard persist(data) else { return false }
        let favoritesChanged = boards.first { $0.id == Self.favoritesID }?.keys != next.first { $0.id == Self.favoritesID }?.keys
        boards = next
        activeBoardID = state.activeBoardID
        preferredStarBoardID = selectedPreferred
        if !syncing && favoritesChanged { refreshFavorites() }
        return true
    }
    var favoriteTexts: [String] { boards.filter { $0.id == Self.favoritesID }.flatMap(\.keys).map(\.text) }
    func isFavorite(_ text: String) -> Bool { favoriteTexts.contains { SymbolBoardKey.exact($0, text) } }

    /// Adopts the app's pages, keeping this process's Favorites keys and open
    /// page. Without a shared file there are no custom pages: pages made
    /// inside earlier keyboards are not carried over.
    func refreshPages() {
        guard let pages, canEdit else { return }
        let favorites = boards.filter { $0.id == Self.favoritesID }.flatMap(\.keys)
        let snapshot = pages.load()
        var next = snapshot?.pages ?? Self.initialBoards(favorites: [])
        var preferred = snapshot?.starPageID ?? Self.favoritesID
        if let index = next.firstIndex(where: { $0.id == Self.favoritesID }) { next[index].keys = favorites }
        let candidate = State(version: 2, activeBoardID: Self.stockID, preferredStarBoardID: preferred, boards: next)
        if !Self.valid(candidate) {
            next = Self.initialBoards(favorites: favorites)
            preferred = Self.favoritesID
        }
        let active = next.contains { $0.id == activeBoardID } ? activeBoardID : Self.stockID
        if boards != next { boards = next }
        if preferredStarBoardID != preferred { preferredStarBoardID = preferred }
        if activeBoardID != active { activeBoardID = active }
    }

    /// Pages as shared with the keyboard: Favorites keys sync separately.
    private static func shareable(_ boards: [SymbolBoard]) -> [SymbolBoard] {
        boards.map { $0.id == favoritesID ? SymbolBoard(id: $0.id, name: $0.name, keys: [], layout: $0.layout) : $0 }
    }

    /// Called on presentation and foregrounding; never on each layout or key tap.
    func refreshFavorites(canWrite: Bool? = nil) {
        if let canWrite { sharedWriteAllowed = canWrite }
        guard let sync, canEdit, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let result = try sync.synchronize(base: favoriteBaseline, local: favoriteTexts, canWrite: sharedWriteAllowed)
            let baseline = result.baseline
            var next = boards
            guard let index = next.firstIndex(where: { $0.id == Self.favoritesID }) else { return }
            let old = Dictionary(uniqueKeysWithValues: next[index].keys.map { (Array($0.text.utf16), $0) })
            next[index].keys = result.texts.map { old[Array($0.utf16)] ?? SymbolBoardKey(id: UUID().uuidString.lowercased(), text: $0, variants: []) }
            let state = State(version: 2, activeBoardID: activeBoardID, preferredStarBoardID: preferredStarBoardID,
                              boards: next, favoriteBaseline: baseline)
            guard let data = Self.encoded(state), persist(data) else { syncStatus = .unavailable; return }
            favoriteBaseline = baseline
            if boards != next { boards = next }
            syncStatus = result.written ? .current : .fullAccessRequired
        } catch { syncStatus = .unavailable }
    }

    @discardableResult func clearFavorites() -> Bool {
        var next = boards
        guard let index = next.firstIndex(where: { $0.id == Self.favoritesID }) else { return false }
        next[index].keys = []
        return commit(next)
    }

    private static func keyLimit(_ id: String) -> Int { id == favoritesID ? maximumMigratedFavorites : maximumKeys }
    private static func validText(_ text: String) -> Bool { !text.isEmpty && text.unicodeScalars.prefix(maximumTextScalars + 1).count <= maximumTextScalars }
    private static func validName(_ name: String) -> String? {
        let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.utf8.count <= 512, result.unicodeScalars.prefix(129).count <= 128, result.count <= 32,
              !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return result
    }
    private static func validID(_ id: String) -> Bool {
        (1...80).contains(id.utf8.count) && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }
    private static func valid(_ state: State) -> Bool {
        guard state.favoriteBaseline.map(FavoriteSync.valid) ?? true, let preferred = state.preferredStarBoardID,
              (2...maximumBoards).contains(state.boards.count),
              state.boards.contains(where: { $0.id == stockID }), state.boards.contains(where: { $0.id == favoritesID }),
              state.boards.contains(where: { $0.id == state.activeBoardID }),
              state.boards.contains(where: { $0.id == preferred }),
              Set(state.boards.map(\.id)).count == state.boards.count else { return false }
        return state.boards.allSatisfy { board in
            guard validID(board.id), validName(board.name) == board.name, board.keys.count <= keyLimit(board.id),
                  board.layout.map({ SymbolPageLayout($0) != nil }) ?? true,
                  Set(board.keys.map(\.id)).count == board.keys.count,
                  uniqueExact(board.keys.map(\.text)).count == board.keys.count else { return false }
            return board.keys.allSatisfy { key in
                validID(key.id) && validText(key.text) && key.variants.count <= maximumVariants
                    && key.variants.allSatisfy(validText)
                    && uniqueExact([key.text] + key.variants).count == key.variants.count + 1
                    && [key.up, key.down].allSatisfy { swipe in
                        swipe.map { !$0.isEmpty && $0.count <= maximumVariants && $0.allSatisfy(validText) && uniqueExact($0).count == $0.count } ?? true
                    }
            }
        }
    }
    private static func encoded(_ state: State) -> Data? {
        guard valid(state), let data = try? JSONEncoder().encode(state), data.count <= maximumPayloadBytes else { return nil }
        return data
    }
    private static func uniqueExact(_ strings: [String]) -> [String] {
        var seen = Set<[UInt16]>()
        return strings.filter { seen.insert(Array($0.utf16)).inserted }
    }
    private static func legacyFavorites(in defaults: UserDefaults) -> [SymbolBoardKey]? {
        var texts: [String] = []
        var seen = Set<[UInt16]>()
        func append(_ text: String) -> Bool {
            if seen.insert(Array(text.utf16)).inserted { texts.append(text) }
            return texts.count <= maximumMigratedFavorites
        }
        for value in defaults.array(forKey: "favoriteCodePoints") ?? [] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let raw = number.doubleValue
            guard raw.isFinite, raw >= 0, raw <= 0x10FFFF, raw.rounded(.towardZero) == raw,
                  let scalar = Unicode.Scalar(UInt32(raw)) else { continue }
            guard append(String(scalar)) else { return nil }
        }
        for value in defaults.array(forKey: "favoriteEmojiSequences") ?? [] {
            guard let id = value as? String else { continue }
            // An oversized old sequence cannot be silently discarded. Leave
            // the legacy collection readable instead of persisting a subset.
            guard id.utf8.count <= maximumTextScalars * 7 else { return nil }
            let parts = id.split(separator: "-", omittingEmptySubsequences: false)
            let points = parts.compactMap { UInt32($0, radix: 16) }
            guard !parts.isEmpty, points.count == parts.count,
                  points.allSatisfy({ Unicode.Scalar($0) != nil }),
                  points.map({ String(format: "%04X", $0) }).joined(separator: "-") == id else { continue }
            let text = String(String.UnicodeScalarView(points.compactMap(Unicode.Scalar.init)))
            guard validText(text), append(text) else { return nil }
        }
        return texts.enumerated().map {
            SymbolBoardKey(id: "legacy.\($0.offset)", text: $0.element, variants: [])
        }
    }
    private static func initialBoards(favorites: [SymbolBoardKey]) -> [SymbolBoard] {
        let stock: [(String, [String])] = [
            ("!", ["¡", "‼"]), ("?", ["¿", "‽"]), ("@", []), ("#", []),
            ("$", ["€", "£", "¥", "¢", "₹", "₩"]), ("%", ["‰", "‱"]), ("&", []), ("*", ["×", "⋅"]),
            ("(", ["[", "{"]), (")", ["]", "}"]), ("+", ["±", "∓"]), ("−", ["-", "–", "—"]),
            ("=", ["≠", "≈", "≡"]), ("<", ["≤", "≪"]), (">", ["≥", "≫"]), ("/", ["÷", "\\"]),
            ("°", []), ("©", ["®", "™"]), ("•", ["·", "…"]), ("→", ["←", "↑", "↓", "↔"]),
            ("✓", ["✔", "✕", "✗"]), ("§", ["¶"]), ("_", []), ("|", ["¦"])
        ]
        return [SymbolBoard(id: stockID, name: "Symbols", keys: stock.enumerated().map {
            SymbolBoardKey(id: "stock.\($0.offset)", text: $0.element.0, variants: $0.element.1)
        }), SymbolBoard(id: favoritesID, name: "Favorites", keys: favorites)]
    }
}
