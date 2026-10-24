import Foundation

// The whole portable configuration (docs/configuration-format.md §4) as the
// stores hold it. App only: the keyboard never sees TOML or this model; it
// reads the JSON snapshots `compile()` produces through each store's own
// encoder, so every store stays the authority on its own format and size.

/// The five rows of Review Import, in order.
enum ConfigurationCategory: String, CaseIterable, Sendable {
    case settings, layoutsAndKeys, favorites, fontsAndRules, imageColors

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .layoutsAndKeys: return "Layouts and Keys"
        case .favorites: return "Favorites"
        case .fontsAndRules: return "Font Choices and Rules"
        case .imageColors: return "Copy Image"
        }
    }

    var symbol: String {
        switch self {
        case .settings: return "gearshape"
        case .layoutsAndKeys: return "keyboard"
        case .favorites: return "star"
        case .fontsAndRules: return "textformat.alt"
        case .imageColors: return "paintpalette"
        }
    }
}

/// The file's top-level sections. A missing one means its factory defaults.
enum ConfigurationSection: String, CaseIterable, Sendable {
    case settings, keyboard, pages, favorites
    case fontRules = "font_rules"
    case imageColors = "image_colors"

    var category: ConfigurationCategory {
        switch self {
        case .settings: return .settings
        case .keyboard, .pages: return .layoutsAndKeys
        case .favorites: return .favorites
        case .fontRules: return .fontsAndRules
        case .imageColors: return .imageColors
        }
    }
}

/// The app's browse preferences (`@AppStorage`), with the defaults the
/// views use when a key is unset.
struct ConfigurationBrowse: Equatable, Sendable {
    static let densities: Set<Int> = [3, 8, 16, 32]
    static let tileColumnRange = 2...256
    static let planeRange = -1...16

    var exploreGridDensity = 3
    var blockGridDensity = 3
    var tileColumns = 3
    var explorePlane = -1
    var showsPrivateUse = false
    var exploreDescending = false
    var emojiSortOrder: UnicodeSortOrder = .codePoint

    init() {}

    /// Unset or unusable values read as the defaults, as in the views.
    init(_ values: AppPresentationSettings.Values) {
        exploreGridDensity = values.integers["exploreGridDensity"] ?? 3
        blockGridDensity = values.integers["blockGridDensity"] ?? 3
        tileColumns = values.integers["tileColumns"] ?? 3
        explorePlane = values.integers["explorePlane"] ?? -1
        showsPrivateUse = values.booleans["exploreShowsPrivateUse"] ?? false
        exploreDescending = values.booleans["exploreDescending"] ?? false
        emojiSortOrder = values.strings["emojiSortOrder"].flatMap(UnicodeSortOrder.init(rawValue:)) ?? .codePoint
    }

    /// Every value set explicitly, so the app adopts exactly these.
    var values: AppPresentationSettings.Values {
        AppPresentationSettings.Values(
            integers: ["exploreGridDensity": exploreGridDensity, "blockGridDensity": blockGridDensity,
                       "tileColumns": tileColumns, "explorePlane": explorePlane],
            booleans: ["exploreShowsPrivateUse": showsPrivateUse, "exploreDescending": exploreDescending],
            strings: ["emojiSortOrder": emojiSortOrder.rawValue])
    }
}

struct UniboardConfiguration: Sendable {
    /// Edition, Extra Unicode Fonts, keyboard switches and the layouts list.
    var settings: UnicodeEditionSettings.Snapshot
    var autoCapitalization: AutoCapitalizationMode
    var browse: ConfigurationBrowse
    var keys: KeyboardKeySettings.Snapshot
    /// Every page in display order; the Favorites page carries no keys.
    var pages: [SymbolBoard]
    var starPageID: String
    var favorites: [String]
    var fontRules: [FontRule]
    var imageColors: ImageColorSettings.Value

    static let factoryDefaults = UniboardConfiguration(
        settings: UnicodeEditionSettings.Snapshot(edition: .latest), autoCapitalization: .followApp, browse: ConfigurationBrowse(),
        keys: .defaults, pages: SymbolPageRules.initialBoards(favorites: []), starPageID: SymbolPageRules.favoritesID,
        favorites: [], fontRules: [], imageColors: ImageColorSettings.defaultValue)

    /// The configuration in effect: every store read from one generation
    /// `directory`, the way the app and keyboard read it. Unusable files
    /// read as their store's defaults. `favorites` is the app's own list.
    static func capture(directory: URL?, presentation: AppPresentationSettings.Values, favorites: [String]) -> UniboardConfiguration {
        let provider: () -> URL? = { directory }
        let stored = SymbolPageSettings(containerURL: provider).load()
        var pages = stored?.pages.map { SymbolBoard(id: $0.id, name: $0.name, keys: $0.id == SymbolPageRules.favoritesID ? [] : $0.keys, layout: $0.layout) }
            ?? factoryDefaults.pages
        var star = stored?.starPageID ?? SymbolPageRules.favoritesID
        if !SymbolPageRules.validPages(pages, starPageID: star) { pages = factoryDefaults.pages; star = SymbolPageRules.favoritesID }
        let colors = directory.flatMap { try? SharedConfigurationLocation.readRegularFile($0.appendingPathComponent(ImageColorSettings.filename),
                                                                                         limit: ImageColorSettings.maximumPayloadBytes + 1) }
            .flatMap(ImageColorSettings.decode)?.value
        return UniboardConfiguration(
            settings: UnicodeEditionSettings(containerURL: provider).loadSnapshot(),
            autoCapitalization: AutoCapitalizationSetting(directory: provider).load(),
            browse: ConfigurationBrowse(presentation),
            keys: KeyboardKeySettings(containerURL: provider).loadSnapshot(),
            pages: pages, starPageID: star, favorites: favorites,
            fontRules: FontRuleStore(directory: provider).load(blocks: UnicodeCatalog.shared.blocks) ?? [],
            imageColors: colors ?? ImageColorSettings.defaultValue)
    }

    /// One payload per snapshot file, each from its store's own encoder;
    /// nil when any store refuses its part. Favorites get a new replacement
    /// id and colors a new revision, so both processes adopt them.
    func compile(replacementID: String = UUID().uuidString, revision: String = UUID().uuidString) -> [String: Data]? {
        guard SymbolPageRules.validPages(pages, starPageID: starPageID),
              let edition = UnicodeEditionSettings.encode(settings),
              let keyData = KeyboardKeySettings.encode(keys),
              let pageData = SymbolPageSettings.encode(SymbolPageSettings.Snapshot(pages: pages, starPageID: starPageID)),
              let favoriteData = FavoriteSync.replacementPayload(favorites, id: replacementID),
              let ruleData = FontRuleStore.encode(fontRules, blocks: UnicodeCatalog.shared.blocks),
              let colorData = ImageColorSettings.encode(ImageColorSettings.Stored(value: imageColors, revision: revision)) else { return nil }
        return [
            UnicodeEditionSettings.filename: edition,
            KeyboardKeySettings.filename: keyData,
            SymbolPageSettings.filename: pageData,
            FavoriteSync.filename: favoriteData,
            FontRuleStore.filename: ruleData,
            ImageColorSettings.filename: colorData,
            AutoCapitalizationSetting.filename: AutoCapitalizationSetting.encode(autoCapitalization),
            AppPresentationSettings.filename: AppPresentationSettings.encode(browse.values),
        ]
    }

    /// The part of the configuration one category covers is the same.
    func matches(_ other: UniboardConfiguration, in category: ConfigurationCategory) -> Bool {
        switch category {
        case .settings:
            // Retired switches are never exported, imported or shown (Ato msg408).
            var lhs = settings.withoutRetired, rhs = other.settings.withoutRetired
            lhs.layouts = []; rhs.layouts = []
            return lhs == rhs && autoCapitalization == other.autoCapitalization && browse == other.browse
        case .layoutsAndKeys:
            return settings.layouts == other.settings.layouts && keys == other.keys && starPageID == other.starPageID
                && pages.count == other.pages.count
                && zip(pages, other.pages).allSatisfy { $0 == $1 && SymbolBoardKey.exact($0.name, $1.name) }
        case .favorites:
            return SymbolBoardKey.exact(favorites, other.favorites)
        case .fontsAndRules:
            // Rule ids are local and never exported.
            return fontRules.count == other.fontRules.count
                && zip(fontRules, other.fontRules).allSatisfy { $0.selector == $1.selector && $0.face == $1.face }
        case .imageColors:
            return imageColors == other.imageColors
        }
    }
}

/// A retired setting an older file still has: never applied, and listed
/// under "Ignored settings" in Review Import (Ato msg408, Camo msg409).
struct ConfigurationIgnoredSetting: Equatable, Sendable {
    /// The setting's former name, "Number Row".
    let name: String
    /// The key as written in the file, "settings.number_row".
    let key: String

    /// `[settings]` keys of the switches N1 removed, with their former names:
    /// the Top Row picker (stored as `symbol_bar` and
    /// `search_instead_of_symbols`) and the Number Row switch. The editable
    /// keyboard layout replaced them.
    static let retiredSettings: [String: String] = [
        "top_row": "Top Row", "symbol_bar": "Top Row", "search_instead_of_symbols": "Top Row", "number_row": "Number Row",
    ]
}

extension UnicodeEditionSettings.Snapshot {
    /// The retired Top Row and Number Row values set to their defaults.
    var withoutRetired: Self { keepingRetired(from: Self(edition: edition)) }

    /// These settings with `other`'s retired Top Row and Number Row values,
    /// which an import never changes: they stay as stored for earlier versions.
    func keepingRetired(from other: Self) -> Self {
        var result = self
        result.showsSymbolBar = other.showsSymbolBar
        result.searchBarInsteadOfSymbols = other.searchBarInsteadOfSymbols
        result.showsNumberRow = other.showsNumberRow
        return result
    }
}

extension UniboardConfiguration: Equatable {
    /// Strings compare by their exact scalars, never canonical equivalence.
    static func == (lhs: UniboardConfiguration, rhs: UniboardConfiguration) -> Bool {
        ConfigurationCategory.allCases.allSatisfy { lhs.matches(rhs, in: $0) }
    }
}
