import Foundation

enum ConfigurationChangeStatus: Equatable, Sendable {
    case unchanged, changed, reset

    var title: String {
        switch self {
        case .unchanged: return "Unchanged"
        case .changed: return "Will change"
        case .reset: return "Will reset to defaults"
        }
    }
}

struct ConfigurationCategoryChange: Equatable, Sendable {
    let category: ConfigurationCategory
    let status: ConfigurationChangeStatus
    /// Every actual change as a plain line. Custom key text is never shown.
    let lines: [String]
}

/// What an import would replace, category by category (Review Import).
struct ConfigurationDiff: Equatable, Sendable {
    /// The five categories in display order.
    let changes: [ConfigurationCategoryChange]
    /// Sections the file leaves out; they reset to defaults.
    let missingSections: [ConfigurationSection]

    init(current: UniboardConfiguration, incoming: UniboardConfiguration, missingSections: [ConfigurationSection] = []) {
        self.missingSections = missingSections
        changes = ConfigurationCategory.allCases.map { category in
            guard !current.matches(incoming, in: category) else { return ConfigurationCategoryChange(category: category, status: .unchanged, lines: []) }
            let sections = ConfigurationSection.allCases.filter { $0.category == category }
            let status: ConfigurationChangeStatus = sections.allSatisfy(missingSections.contains) ? .reset : .changed
            return ConfigurationCategoryChange(category: category, status: status, lines: Self.lines(category, current, incoming))
        }
    }

    var isIdentical: Bool { changes.allSatisfy { $0.status == .unchanged } }

    func change(_ category: ConfigurationCategory) -> ConfigurationCategoryChange { changes.first { $0.category == category }! }

    /// The import turns Extra Unicode Fonts on or off: the Settings row starts expanded.
    var changesExtraUnicodeFonts: Bool { change(.settings).lines.first?.hasPrefix(Self.extraUnicodeFonts) == true }

    /// "Your current favorites and custom key layouts will be replaced."
    var replacesFavoritesOrKeys: Bool { change(.favorites).status != .unchanged || change(.layoutsAndKeys).status != .unchanged }

    /// "Sections missing from this file will reset to defaults." Only when
    /// something actually changes.
    var showsMissingSections: Bool { !missingSections.isEmpty && !isIdentical }

    static let extraUnicodeFonts = "Extra Unicode Fonts: "

    // MARK: Lines

    static func onOff(_ value: Bool) -> String { value ? "On" : "Off" }

    private static func line<T: Equatable>(_ name: String, _ old: T, _ new: T, _ text: (T) -> String) -> [String] {
        old == new ? [] : ["\(name): \(text(old)) → \(text(new))"]
    }

    static func density(_ value: Int) -> String { value == 3 ? "Tiles" : "\(value) per Row" }

    static func plane(_ value: Int) -> String { value < 0 ? "All Planes" : "Plane \(value)" }

    static func preset(_ id: String) -> String {
        ["blackOnWhite": "Black on White", "blackOnClear": "Black on Transparent", "whiteOnBlack": "White on Black",
         "whiteOnClear": "White on Transparent"][id] ?? "Custom"
    }

    static func layoutName(_ id: String) -> String { KeyboardAlphabet.alphabet(id: id)?.nativeName ?? id }

    static func faceName(_ face: FontFaceReference) -> String { face.family + " " + face.style }

    private static func lines(_ category: ConfigurationCategory, _ old: UniboardConfiguration, _ new: UniboardConfiguration) -> [String] {
        switch category {
        case .settings: return settingsLines(old, new)
        case .layoutsAndKeys: return layoutLines(old, new) + pageLines(old, new)
        case .favorites: return favoriteLines(old.favorites, new.favorites)
        case .fontsAndRules: return ruleLines(old.fontRules, new.fontRules)
        case .imageColors:
            let a = old.imageColors, b = new.imageColors
            return line("Image colors", a.preset, b.preset, preset)
                + line("Custom Text Color", a.customText, b.customText) { $0 }
                + line("Custom Background", a.customBackground, b.customBackground) { $0 == "transparent" ? "Transparent" : $0 }
                + line("Image scale", a.scale, b.scale) { "\($0)×" }
        }
    }

    private static func settingsLines(_ old: UniboardConfiguration, _ new: UniboardConfiguration) -> [String] {
        let a = old.settings, b = new.settings, x = old.browse, y = new.browse
        var result = line("Extra Unicode Fonts", a.useUnicodeFonts, b.useUnicodeFonts, onOff)
        result += line("Unicode Version", a.edition, b.edition) { $0.title }
        result += line("Private Use Area", x.showsPrivateUse, y.showsPrivateUse, onOff)
        result += line("ConScript (UCSUR)", a.showsUCSUR, b.showsUCSUR, onOff)
        result += line("Prefer ConScript over PUA", a.prefersUCSUR, b.prefersUCSUR, onOff)
        result += line("Text Preview", a.showsTextPreview, b.showsTextPreview, onOff)
        result += line("Hide Keyboard Key", a.showsCollapseKey, b.showsCollapseKey, onOff)
        result += line("iPad Landscape Layout", a.padLayout, b.padLayout) { $0.title }
        result += line("iPad Symbol Mapping", a.padSymbolMapping, b.padSymbolMapping) { $0.title }
        if old.autoCapitalization != new.autoCapitalization { result.append(AutoCapitalizationCopy.change(from: old.autoCapitalization, to: new.autoCapitalization)) }
        result += line("Explore Grid", x.exploreGridDensity, y.exploreGridDensity, density)
        result += line("Blocks Grid", x.blockGridDensity, y.blockGridDensity, density)
        result += line("Tile Columns", x.tileColumns, y.tileColumns) { "\($0)" }
        result += line("Explore Plane", x.explorePlane, y.explorePlane, plane)
        result += line("Explore Order", x.exploreDescending, y.exploreDescending) { $0 ? "Descending" : "Ascending" }
        result += line("Emoji Order", x.emojiSortOrder, y.emojiSortOrder) { $0.title }
        return result
    }

    private static func layoutLines(_ old: UniboardConfiguration, _ new: UniboardConfiguration) -> [String] {
        var result = line("Layouts", old.settings.layouts, new.settings.layouts) { $0.map(layoutName).joined(separator: ", ") }
        let a = old.keys.overrides, b = new.keys.overrides
        for id in Set(a.keys).union(b.keys).sorted() where a[id] != b[id] {
            let title = KeyboardKeySettings.descriptor(for: id)?.title ?? id
            result.append(a[id] == nil ? "Customizes the \(title) key" : b[id] == nil ? "Restores the \(title) key" : "Changes the \(title) key")
        }
        let c = old.keys.arrangements, d = new.keys.arrangements
        for id in Set(c.keys).union(d.keys).sorted() where c[id] != d[id] {
            result.append(d[id] == nil ? "Restores the standard \(layoutName(id)) keyboard" : "Rearranges the \(layoutName(id)) keyboard")
        }
        return result
    }

    private static func pageLines(_ old: UniboardConfiguration, _ new: UniboardConfiguration) -> [String] {
        func name(_ id: String, _ pages: [SymbolBoard]) -> String { pages.first { $0.id == id }?.name ?? id }
        let a = old.pages, b = new.pages
        var result: [String] = []
        for page in b where !a.contains(where: { $0.id == page.id }) { result.append("Adds page \(page.name)") }
        for page in a where !b.contains(where: { $0.id == page.id }) { result.append("Removes page \(page.name)") }
        for page in a {
            guard let next = b.first(where: { $0.id == page.id }) else { continue }
            if !SymbolBoardKey.exact(page.name, next.name) { result.append("Renames page \(page.name) to \(next.name)") }
            if page.keys != next.keys {
                result.append(page.keys.count == next.keys.count ? "Changes keys on page \(next.name)"
                              : "Page \(next.name): \(keyCount(page.keys.count)) → \(keyCount(next.keys.count))")
            }
            if page.layout != next.layout { result.append("Changes the rows of page \(next.name)") }
        }
        let common = Set(a.map(\.id)).intersection(b.map(\.id))
        if a.map(\.id).filter(common.contains) != b.map(\.id).filter(common.contains) { result.append("Reorders pages") }
        if old.starPageID != new.starPageID { result.append("Star key opens: \(name(old.starPageID, a)) → \(name(new.starPageID, b))") }
        return result
    }

    static func keyCount(_ count: Int) -> String { count == 1 ? "1 key" : "\(count) keys" }

    static func favoriteCount(_ count: Int) -> String { count == 1 ? "1 favorite" : "\(count.formatted()) favorites" }

    private static func favoriteLines(_ old: [String], _ new: [String]) -> [String] {
        let a = Set(old.map { Array($0.utf16) }), b = Set(new.map { Array($0.utf16) })
        let added = b.subtracting(a).count, removed = a.subtracting(b).count
        var result: [String] = []
        if added > 0 { result.append("Adds \(favoriteCount(added))") }
        if removed > 0 { result.append("Removes \(favoriteCount(removed))") }
        let common = a.intersection(b)
        if old.map({ Array($0.utf16) }).filter(common.contains) != new.map({ Array($0.utf16) }).filter(common.contains) { result.append("Reorders favorites") }
        return result
    }

    private static func ruleLines(_ old: [FontRule], _ new: [FontRule]) -> [String] {
        var result: [String] = []
        for rule in new where !old.contains(where: { $0.selector == rule.selector }) {
            result.append("Adds \(ConfigurationCodec.selectorLabel(rule.selector).lowercasedFirst): \(faceName(rule.face))")
        }
        for rule in old {
            guard let next = new.first(where: { $0.selector == rule.selector }) else {
                result.append("Removes \(ConfigurationCodec.selectorLabel(rule.selector).lowercasedFirst)"); continue
            }
            if next.face != rule.face { result.append("\(ConfigurationCodec.selectorLabel(rule.selector)): \(faceName(rule.face)) → \(faceName(next.face))") }
        }
        let common = old.map(\.selector).filter { selector in new.contains { $0.selector == selector } }
        if common != new.map(\.selector).filter({ selector in old.contains { $0.selector == selector } }) { result.append("Reorders font rules") }
        return result
    }
}

/// A font an imported rule names that this device can't load. The rules are
/// still imported and apply once the font is available (Ato msg408); nothing
/// is downloaded or deleted.
struct ConfigurationFontWarning: Equatable, Sendable {
    /// "Snowman Sans Regular".
    let font: String
    /// The rules that use it, in rule order: "Code point rule U+2603".
    let rules: [String]

    /// The state wording for each of those rules (docs/font-rules-copy.md).
    static let ruleStatus = "Font unavailable"

    /// One warning per unavailable face, in first-use order.
    static func warnings(rules: [FontRule], unavailable: [FontFaceReference]) -> [ConfigurationFontWarning] {
        ConfigurationCodec.uniqueFaces(rules).filter(unavailable.contains).map { face in
            ConfigurationFontWarning(font: ConfigurationDiff.faceName(face),
                                     rules: rules.filter { $0.face == face }.map { ConfigurationCodec.selectorLabel($0.selector) })
        }
    }
}

private extension String {
    /// "Code point rule U+16A0" → "code point rule U+16A0"; "Unicode" keeps its capital.
    var lowercasedFirst: String { hasPrefix("Unicode") ? self : prefix(1).lowercased() + dropFirst() }
}
