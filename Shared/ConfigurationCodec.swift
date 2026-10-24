import Foundation

/// A valid import: the configuration it holds and what the review shows.
struct DecodedConfiguration: Sendable {
    let configuration: UniboardConfiguration
    /// Sections the file leaves out, in schema order: they reset to defaults.
    let missingSections: [ConfigurationSection]
    /// The file's actual size in bytes.
    let byteCount: Int
    /// The file's `schema_version`.
    let formatVersion: Int
    /// Every face a rule uses, in first-use order.
    let faces: [FontFaceReference]
    /// Retired settings the file has, in file order; none is applied.
    let ignoredSettings: [ConfigurationIgnoredSetting]
}

/// Why a file can't be imported: messages in docs/font-rules-copy.md's
/// format, first cause first. They name fields and locations only, never
/// file contents or custom key text.
struct ConfigurationProblems: Error, Equatable, Sendable {
    let messages: [String]
}

/// The TOML exchange format (docs/configuration-format.md). App only.
enum ConfigurationCodec {
    static let formatVersion = 1
    static let maximumBytes = TOMLLimits.standard.maximumBytes
    /// Validation stops collecting after this many problems.
    static let maximumProblems = 1000
    static let tooLarge = "This file exceeds the 4 MB import limit."
    static let unreadable = "The file couldn’t be opened. Choose it again in Files."
    static let missingVersion = "The file is missing its configuration version."
    static let unsupportedVersion = "This configuration version isn’t supported by this version of Uniboard."

    /// "Uniboard-Configuration-YYYY-MM-DD.toml", the local date.
    static func exportFilename(date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "Uniboard-Configuration-%04d-%02d-%02d.toml", parts.year!, parts.month!, parts.day!)
    }

    // MARK: Export

    /// Deterministic UTF-8 TOML; nil (never truncated) over the import limit.
    /// `inLibrary` adds the informational `in_library` flag to each face.
    static func encode(_ configuration: UniboardConfiguration, inLibrary: ((FontFaceReference) -> Bool)? = nil) -> Data? {
        let data = Data(TOMLDocument.write(document(configuration, inLibrary: inLibrary)).utf8)
        return data.count <= maximumBytes ? data : nil
    }

    static func document(_ configuration: UniboardConfiguration, inLibrary: ((FontFaceReference) -> Bool)? = nil) -> TOMLTable {
        let c = configuration
        var root = TOMLTable()
        root["schema_version"] = .integer(Int64(formatVersion))
        var settings = TOMLTable()
        settings["unicode_edition"] = .string(c.settings.edition.selectionIdentifier)
        settings["extra_unicode_fonts"] = .boolean(c.settings.useUnicodeFonts)
        settings["private_use_area"] = .boolean(c.browse.showsPrivateUse)
        settings["conscript"] = .boolean(c.settings.showsUCSUR)
        settings["prefer_conscript"] = .boolean(c.settings.prefersUCSUR)
        settings["text_preview"] = .boolean(c.settings.showsTextPreview)
        settings["hide_keyboard_key"] = .boolean(c.settings.showsCollapseKey)
        settings["ipad_landscape_layout"] = .string(c.settings.padLayout.rawValue)
        settings["ipad_symbol_mapping"] = .string(c.settings.padSymbolMapping.rawValue)
        settings["auto_capitalization"] = .string(c.autoCapitalization.rawValue)
        var browse = TOMLTable()
        browse["explore_grid_density"] = .integer(Int64(c.browse.exploreGridDensity))
        browse["block_grid_density"] = .integer(Int64(c.browse.blockGridDensity))
        browse["tile_columns"] = .integer(Int64(c.browse.tileColumns))
        browse["explore_plane"] = .integer(Int64(c.browse.explorePlane))
        browse["explore_descending"] = .boolean(c.browse.exploreDescending)
        browse["emoji_sort_order"] = .string(c.browse.emojiSortOrder.rawValue)
        settings["browse"] = .table(browse)
        root["settings"] = .table(settings)

        var keyboard = TOMLTable()
        keyboard["layouts"] = strings(c.settings.layouts)
        let keys = c.keys.overrides.keys.sorted().map { id -> TOMLValue in
            var entry = TOMLTable()
            entry["id"] = .string(id)
            for (name, gesture) in gestureKeys {
                if let values = c.keys.overrides[id]!.candidates(for: gesture) { entry[name] = strings(values) }
            }
            return .table(entry)
        }
        if !keys.isEmpty { keyboard["key"] = .array(keys) }
        let arrangements = c.keys.arrangements.keys.sorted().map { id -> TOMLValue in
            let arrangement = c.keys.arrangements[id]!
            return .table(TOMLTable(["layout": .string(id), "keys": strings(arrangement.keys), "places": .string(arrangement.layout)]))
        }
        if !arrangements.isEmpty { keyboard["arrangement"] = .array(arrangements) }
        root["keyboard"] = .table(keyboard)

        var pages = TOMLTable()
        pages["star_page"] = .string(c.starPageID)
        pages["page"] = .array(c.pages.map { page in
            var entry = TOMLTable()
            entry["id"] = .string(page.id)
            entry["name"] = .string(page.name)
            if let layout = page.layout { entry["layout"] = .string(layout) }
            let keys = page.keys.map { key -> TOMLValue in
                var item = TOMLTable(["id": .string(key.id), "text": .string(key.text), "variants": strings(key.variants)])
                if let up = key.up { item["up"] = strings(up) }
                if let down = key.down { item["down"] = strings(down) }
                return .table(item)
            }
            if !keys.isEmpty { entry["key"] = .array(keys) }
            return .table(entry)
        })
        root["pages"] = .table(pages)
        root["favorites"] = .table(TOMLTable(["texts": strings(c.favorites)]))

        let faces = uniqueFaces(c.fontRules)
        var fonts = TOMLTable()
        if !faces.isEmpty {
            fonts["face"] = .array(faces.enumerated().map { index, face in
                var entry = TOMLTable(["ref": .string(reference(index)), "source": .string(face.source.rawValue), "family": .string(face.family),
                                       "style": .string(face.style), "postscript_name": .string(face.postScriptName)])
                let axes: [String: Double]
                switch face.identity {
                case let .file(sha256, faceIndex, variations):
                    entry["sha256"] = .string(sha256)
                    entry["face_index"] = .integer(Int64(faceIndex))
                    axes = variations
                case let .process(_, variations):
                    axes = variations
                }
                if !axes.isEmpty {
                    var table = TOMLTable()
                    for tag in axes.keys.sorted() { table[tag] = .float(axes[tag]!) }
                    entry["variations"] = .table(table)
                }
                if let google = face.googleFaceID { entry["google_face"] = .string(google) }
                if let inLibrary { entry["in_library"] = .boolean(inLibrary(face)) }
                return .table(entry)
            })
        }
        root["fonts"] = .table(fonts)
        var rules = TOMLTable()
        if !c.fontRules.isEmpty {
            rules["rule"] = .array(c.fontRules.map { rule in
                var entry = TOMLTable()
                switch rule.selector {
                case let .codePoint(value):
                    entry["code_point"] = .string(FontRuleScalar.label(value))
                case let .range(first, last):
                    entry["range"] = strings([FontRuleScalar.label(first), FontRuleScalar.label(last)])
                case let .block(block):
                    entry["block"] = .string(block.name)
                    entry["block_range"] = strings([FontRuleScalar.label(block.first), FontRuleScalar.label(block.last)])
                    entry["block_unicode_version"] = .string(block.unicodeVersion)
                }
                entry["font"] = .string(reference(faces.firstIndex(of: rule.face)!))
                return .table(entry)
            })
        }
        root["font_rules"] = .table(rules)
        root["image_colors"] = .table(TOMLTable(["preset": .string(c.imageColors.preset), "custom_text": .string(c.imageColors.customText),
                                                  "custom_background": .string(c.imageColors.customBackground),
                                                  "image_scale": .integer(Int64(c.imageColors.scale))]))
        return root
    }

    static let gestureKeys: [(String, KeyboardKeySettings.Gesture)] = [
        ("tap", .tap), ("shifted_tap", .shiftedTap), ("long_press", .longPress), ("swipe_up", .swipeUp), ("swipe_down", .swipeDown),
    ]

    private static func strings(_ values: [String]) -> TOMLValue { .array(values.map { .string($0) }) }

    private static func reference(_ index: Int) -> String { "font-\(index + 1)" }

    /// The faces rules use, each once, in first-use order.
    static func uniqueFaces(_ rules: [FontRule]) -> [FontFaceReference] {
        var seen = Set<FontFaceReference>()
        return rules.map(\.face).filter { seen.insert($0).inserted }
    }

    // MARK: Import

    /// Reads and validates the whole file before anything is written.
    static func decode(_ data: Data) -> Result<DecodedConfiguration, ConfigurationProblems> {
        guard data.count <= maximumBytes else { return .failure(ConfigurationProblems(messages: [tooLarge])) }
        let root: TOMLTable
        do { root = try TOMLDocument.parse(data) } catch {
            // parse throws only TOMLError, whose description names the line and column.
            return .failure(ConfigurationProblems(messages: [String(describing: error)]))
        }
        guard let version = root["schema_version"] else { return .failure(ConfigurationProblems(messages: [missingVersion])) }
        guard version.integerValue == Int64(formatVersion) else { return .failure(ConfigurationProblems(messages: [unsupportedVersion])) }
        let reader = ConfigurationReader()
        let configuration = reader.read(root)
        guard reader.problems.isEmpty else { return .failure(ConfigurationProblems(messages: reader.problems)) }
        return .success(DecodedConfiguration(configuration: configuration,
            missingSections: ConfigurationSection.allCases.filter { root[$0.rawValue] == nil },
            byteCount: data.count, formatVersion: formatVersion, faces: uniqueFaces(configuration.fontRules),
            ignoredSettings: reader.ignored))
    }

    /// The import message for a rule problem; `path` names the rule list.
    static func message(for issue: FontRuleIssue, rules: [FontRule], path: String = "font_rules.rule") -> String {
        switch issue {
        case let .invalidCodePoint(rule): return "Check \(path)[\(rule + 1)]: code points from U+0000 to U+10FFFF."
        case let .surrogate(rule): return "Check \(path)[\(rule + 1)]: code points outside the surrogates U+D800–U+DFFF."
        case let .reversedRange(rule): return "Check \(path)[\(rule + 1)].range: the first code point can’t come after the last."
        case let .unknownBlock(_, name): return "The Unicode block \(displayed(name)) isn’t recognized."
        case let .duplicate(rule, _, _): return "\(selectorLabel(rules[rule].selector)) appears more than once."
        case let .invalidFace(rule): return "The font reference in \(path)[\(rule + 1)].font isn’t valid."
        case let .tooManyRules(limit): return "\(path) exceeds the limit of \(limit.formatted())."
        case let .tooManyRanges(limit): return "Range rules in \(path) exceed the limit of \(limit.formatted())."
        case let .tooManyFaces(limit): return "Fonts used in \(path) exceed the limit of \(limit.formatted())."
        }
    }

    /// "Code point rule U+16A0", "Range rule U+2190–U+21FF", "Unicode block rule Runic".
    static func selectorLabel(_ selector: FontRuleSelector) -> String {
        switch selector {
        case let .codePoint(value): return "Code point rule " + FontRuleScalar.label(value)
        case let .range(first, last): return "Range rule " + FontRuleScalar.label(first) + "–" + FontRuleScalar.label(last)
        case let .block(block): return "Unicode block rule " + displayed(block.name)
        }
    }

    /// File text shown in a message: as it is when short and visible,
    /// otherwise as an escaped TOML string, never more than 64 scalars.
    static func displayed(_ text: String) -> String {
        let quoted = TOMLWriter.quoted(text)
        if !text.isEmpty, text.unicodeScalars.count <= 64, quoted.unicodeScalars.count == text.unicodeScalars.count + 2 { return text }
        return bounded(quoted)
    }

    /// A key as written in a field path: bare, or quoted and escaped.
    static func fieldKey(_ key: String) -> String { bounded(TOMLWriter.key(key)) }

    private static func bounded(_ text: String) -> String {
        text.unicodeScalars.count <= 64 ? text : String(String.UnicodeScalarView(text.unicodeScalars.prefix(64))) + "…"
    }
}

/// Walks a parsed file. Every problem is collected, in file order.
private final class ConfigurationReader {
    private(set) var problems: [String] = []
    private(set) var ignored: [ConfigurationIgnoredSetting] = []

    private func problem(_ message: String) {
        if problems.count < ConfigurationCodec.maximumProblems { problems.append(message) }
    }

    private func check(_ field: String, _ expected: String) { problem("Check \(field): \(expected).") }

    private func path(_ parent: String, _ key: String) -> String {
        parent.isEmpty ? key : parent + "." + key
    }

    /// Reports keys a table doesn't allow.
    private func allow(_ table: TOMLTable, _ parent: String, _ keys: Set<String>) {
        for key in table.keys where !keys.contains(key) {
            problem("Unrecognized setting: \(path(parent, ConfigurationCodec.fieldKey(key))).")
        }
    }

    /// nil when absent or not a table (reported).
    private func table(_ table: TOMLTable, _ key: String, _ parent: String) -> TOMLTable? {
        guard let value = table[key] else { return nil }
        guard let result = value.tableValue else { check(path(parent, key), "a table"); return nil }
        return result
    }

    /// [] when absent; a static array of tables is accepted too.
    private func tables(_ table: TOMLTable, _ key: String, _ parent: String) -> [TOMLTable]? {
        guard let value = table[key] else { return nil }
        guard let items = value.arrayValue, items.allSatisfy({ $0.tableValue != nil }) else {
            check(path(parent, key), "a list of tables, written [[\(path(parent, key))]]")
            return []
        }
        return items.map { $0.tableValue! }
    }

    private func bool(_ table: TOMLTable, _ key: String, _ parent: String, _ fallback: Bool) -> Bool {
        guard let value = table[key] else { return fallback }
        guard let result = value.booleanValue else { check(path(parent, key), "true or false"); return fallback }
        return result
    }

    private func text(_ table: TOMLTable, _ key: String, _ parent: String) -> String? {
        guard let value = table[key] else { return nil }
        guard let result = value.stringValue else { check(path(parent, key), "text in quotes"); return nil }
        return result
    }

    /// A required string; a missing one is reported.
    private func required(_ table: TOMLTable, _ key: String, _ parent: String) -> String? {
        if table[key] == nil { check(path(parent, key), "a value; it’s missing") }
        return text(table, key, parent)
    }

    private func choice<T>(_ table: TOMLTable, _ key: String, _ parent: String, _ fallback: T, _ options: [(String, T)]) -> T {
        guard let value = table[key] else { return fallback }
        guard let name = value.stringValue, let match = options.first(where: { $0.0 == name }) else {
            check(path(parent, key), Self.list(options.map { "\"\($0.0)\"" }))
            return fallback
        }
        return match.1
    }

    private func integer(_ table: TOMLTable, _ key: String, _ parent: String, _ fallback: Int, _ allowed: (Int) -> Bool, _ expected: String) -> Int {
        guard let value = table[key] else { return fallback }
        guard let number = value.integerValue.map(Int.init), allowed(number) else { check(path(parent, key), expected); return fallback }
        return number
    }

    private func strings(_ value: TOMLValue, _ field: String) -> [String]? {
        guard let items = value.arrayValue, items.allSatisfy({ $0.stringValue != nil }) else { check(field, "a list of text in quotes"); return nil }
        return items.map { $0.stringValue! }
    }

    /// Texts that must each be valid and unique by exact scalars.
    private func texts(_ value: TOMLValue, _ field: String, maximum: Int, scalars: Int) -> [String]? {
        guard let values = strings(value, field) else { return nil }
        guard values.count <= maximum else { problem("\(field) exceeds the limit of \(maximum.formatted())."); return nil }
        var seen = Set<[UInt16]>()
        var valid = true
        for (index, text) in values.enumerated() {
            if text.isEmpty || text.unicodeScalars.prefix(scalars + 1).count > scalars {
                check("\(field)[\(index + 1)]", "text of 1 to \(scalars) code points"); valid = false
            } else if !seen.insert(Array(text.utf16)).inserted {
                problem("\(field)[\(index + 1)] appears more than once."); valid = false
            }
        }
        return valid ? values : nil
    }

    static func list(_ items: [String]) -> String {
        items.count == 1 ? items[0] : items.dropLast().joined(separator: ", ") + " or " + items.last!
    }

    // MARK: Sections

    func read(_ root: TOMLTable) -> UniboardConfiguration {
        var c = UniboardConfiguration.factoryDefaults
        allow(root, "", Set(["schema_version"] + ConfigurationSection.allCases.map(\.rawValue) + ["fonts"]))
        if let settings = table(root, "settings", "") { readSettings(settings, into: &c) }
        if let keyboard = table(root, "keyboard", "") { readKeyboard(keyboard, into: &c) }
        if let pages = table(root, "pages", "") { readPages(pages, into: &c) }
        if let favorites = table(root, "favorites", "") { readFavorites(favorites, into: &c) }
        let faces = table(root, "fonts", "").map(readFaces) ?? [:]
        if let rules = table(root, "font_rules", "") { readRules(rules, faces: faces, into: &c) }
        if let colors = table(root, "image_colors", "") { readColors(colors, into: &c) }
        return c
    }

    private func readSettings(_ t: TOMLTable, into c: inout UniboardConfiguration) {
        let p = "settings"
        // Retired switches: any value is ignored, never applied or checked.
        ignored = t.keys.compactMap { key in
            ConfigurationIgnoredSetting.retiredSettings[key].map { ConfigurationIgnoredSetting(name: $0, key: path(p, ConfigurationCodec.fieldKey(key))) }
        }
        allow(t, p, Set(["unicode_edition", "extra_unicode_fonts", "private_use_area", "conscript", "prefer_conscript", "text_preview",
                         "hide_keyboard_key", "ipad_landscape_layout", "ipad_symbol_mapping", "auto_capitalization", "browse"])
                     .union(ConfigurationIgnoredSetting.retiredSettings.keys))
        let editions = [UnicodeEdition.latest, .draft, .previous, .older].map { ($0.selectionIdentifier, $0) }
            .filter { UnicodeEdition.resolve(selectionIdentifier: $0.0) == $0.1 }
        c.settings.edition = choice(t, "unicode_edition", p, .latest, editions)
        c.settings.useUnicodeFonts = bool(t, "extra_unicode_fonts", p, false)
        c.browse.showsPrivateUse = bool(t, "private_use_area", p, false)
        c.settings.showsUCSUR = bool(t, "conscript", p, false)
        c.settings.prefersUCSUR = bool(t, "prefer_conscript", p, false)
        c.settings.showsTextPreview = bool(t, "text_preview", p, false)
        c.settings.showsCollapseKey = bool(t, "hide_keyboard_key", p, false)
        c.settings.padLayout = choice(t, "ipad_landscape_layout", p, .ansiNumbers, KeyboardPadLayout.allCases.map { ($0.rawValue, $0) })
        c.settings.padSymbolMapping = choice(t, "ipad_symbol_mapping", p, .standard, KeyboardPadSymbolMapping.allCases.map { ($0.rawValue, $0) })
        c.autoCapitalization = choice(t, "auto_capitalization", p, .followApp, AutoCapitalizationMode.allCases.map { ($0.rawValue, $0) })
        guard let browse = table(t, "browse", p) else { return }
        let b = "settings.browse"
        allow(browse, b, ["explore_grid_density", "block_grid_density", "tile_columns", "explore_plane", "explore_descending", "emoji_sort_order"])
        let density = "3, 8, 16 or 32"
        c.browse.exploreGridDensity = integer(browse, "explore_grid_density", b, 3, ConfigurationBrowse.densities.contains, density)
        c.browse.blockGridDensity = integer(browse, "block_grid_density", b, 3, ConfigurationBrowse.densities.contains, density)
        c.browse.tileColumns = integer(browse, "tile_columns", b, 3, ConfigurationBrowse.tileColumnRange.contains, "a whole number from 2 to 256")
        c.browse.explorePlane = integer(browse, "explore_plane", b, -1, ConfigurationBrowse.planeRange.contains, "-1 for all planes, or 0 to 16")
        c.browse.exploreDescending = bool(browse, "explore_descending", b, false)
        c.browse.emojiSortOrder = choice(browse, "emoji_sort_order", b, .codePoint, UnicodeSortOrder.allCases.map { ($0.rawValue, $0) })
    }

    private func readKeyboard(_ t: TOMLTable, into c: inout UniboardConfiguration) {
        let p = "keyboard"
        allow(t, p, ["layouts", "key", "arrangement"])
        if let value = t["layouts"], let ids = strings(value, "keyboard.layouts") {
            if !(1...UnicodeEditionSettings.maximumLayouts).contains(ids.count) {
                check("keyboard.layouts", "1 to \(UnicodeEditionSettings.maximumLayouts) layouts")
            } else {
                var seen = Set<String>()
                for (index, id) in ids.enumerated() {
                    if KeyboardAlphabet.alphabet(id: id) == nil { check("keyboard.layouts[\(index + 1)]", "a layout id such as \"en\"") }
                    else if !seen.insert(id).inserted { problem("Layout \(id) appears more than once.") }
                }
                c.settings.layouts = ids
            }
        }
        var overrides: [String: KeyboardKeySettings.Overrides] = [:]
        var keyIDs = Set<String>()
        for (index, entry) in (tables(t, "key", p) ?? []).enumerated() {
            let e = "keyboard.key[\(index + 1)]"
            allow(entry, e, Set(["id"] + ConfigurationCodec.gestureKeys.map(\.0)))
            var values: [KeyboardKeySettings.Gesture: [String]] = [:]
            for (name, gesture) in ConfigurationCodec.gestureKeys {
                guard let value = entry[name] else { continue }
                let limit = gesture.maximumChoices
                values[gesture] = texts(value, path(e, name), maximum: limit, scalars: KeyboardVariantPolicy.maximumScalars)
            }
            guard let id = required(entry, "id", e) else { continue }
            guard KeyboardKeySettings.descriptor(for: id) != nil else { check(path(e, "id"), "a key id such as \"letter.a\""); continue }
            guard keyIDs.insert(id).inserted else { problem("Key \(id) appears more than once."); continue }
            overrides[id] = KeyboardKeySettings.Overrides(tap: values[.tap], shiftedTap: values[.shiftedTap], longPress: values[.longPress],
                                                         swipeUp: values[.swipeUp], swipeDown: values[.swipeDown])
            if KeyboardKeySettings.Gesture.allCases.allSatisfy({ values[$0] == nil }) { overrides[id] = nil }
        }
        var arrangements: [String: MainKeyboardArrangement] = [:]
        var arranged = Set<String>()
        for (index, entry) in (tables(t, "arrangement", p) ?? []).enumerated() {
            let e = "keyboard.arrangement[\(index + 1)]"
            allow(entry, e, ["layout", "keys", "places"])
            let keys = entry["keys"].flatMap { strings($0, path(e, "keys")) }
            let places = required(entry, "places", e)
            if entry["keys"] == nil { check(path(e, "keys"), "a value; it’s missing") }
            guard let id = required(entry, "layout", e) else { continue }
            guard let alphabet = KeyboardAlphabet.alphabet(id: id) else { check(path(e, "layout"), "a layout id such as \"en\""); continue }
            guard arranged.insert(id).inserted else { problem("The arrangement for \(id) appears more than once."); continue }
            guard let keys, let places else { continue }
            let arrangement = MainKeyboardArrangement(keys: keys, layout: places)
            guard arrangement.isValid(for: alphabet) else {
                check(e, "every letter of the layout once, Shift and Delete once, Tab, Caps Lock and each digit at most once, and one place for each key in up to 4 rows")
                continue
            }
            if arrangement != .standard(for: alphabet) { arrangements[id] = arrangement }
        }
        c.keys = KeyboardKeySettings.Snapshot(overrides: overrides, arrangements: arrangements)
        if problems.isEmpty, KeyboardKeySettings.encode(c.keys) == nil { problem("[keyboard] exceeds the limit of 256 KB.") }
    }

    private func readPages(_ t: TOMLTable, into c: inout UniboardConfiguration) {
        let p = "pages"
        allow(t, p, ["star_page", "page"])
        let star = text(t, "star_page", p) ?? SymbolPageRules.favoritesID
        if let entries = tables(t, "page", p) {
            guard entries.count <= SymbolPageRules.maximumBoards else { problem("pages.page exceeds the limit of \(SymbolPageRules.maximumBoards)."); return }
            var pages: [SymbolBoard] = []
            var valid = true
            for (index, entry) in entries.enumerated() {
                if let page = readPage(entry, "pages.page[\(index + 1)]") {
                    if pages.contains(where: { $0.id == page.id }) { problem("Page \(page.id) appears more than once."); valid = false }
                    pages.append(page)
                } else { valid = false }
            }
            guard valid else { return }
            for id in [SymbolPageRules.stockID, SymbolPageRules.favoritesID] where !pages.contains(where: { $0.id == id }) {
                check("pages.page", "a page with id \"\(id)\""); valid = false
            }
            guard valid else { return }
            c.pages = pages
        }
        guard c.pages.contains(where: { $0.id == star }) else { check("pages.star_page", "the id of a page in pages.page"); return }
        c.starPageID = star
        if SymbolPageSettings.encode(SymbolPageSettings.Snapshot(pages: c.pages, starPageID: star)) == nil { problem("[pages] exceeds the limit of 512 KB.") }
    }

    private func readPage(_ entry: TOMLTable, _ e: String) -> SymbolBoard? {
        allow(entry, e, ["id", "name", "layout", "key"])
        let before = problems.count
        let id = required(entry, "id", e)
        if let id, !SymbolPageRules.validID(id) { check(path(e, "id"), "1 to 80 letters, digits, “.”, “-” or “_”") }
        let name = required(entry, "name", e)
        if let name, SymbolPageRules.validName(name) != name { check(path(e, "name"), "a name of 1 to 32 characters without spaces at either end") }
        let layout = text(entry, "layout", e)
        if let layout, SymbolPageLayout(layout) == nil { check(path(e, "layout"), "rows of k (key), h (half gap) and g (gap) separated by /") }
        var keys: [SymbolBoardKey] = []
        if let items = tables(entry, "key", e) {
            if id == SymbolPageRules.favoritesID { check(path(e, "key"), "no keys: the Favorites page’s keys come from [favorites]") }
            else if items.count > SymbolPageRules.maximumKeys { problem("\(path(e, "key")) exceeds the limit of \(SymbolPageRules.maximumKeys).") }
            else {
                for (index, item) in items.enumerated() {
                    let k = path(e, "key") + "[\(index + 1)]"
                    guard let key = readKey(item, k) else { continue }
                    if keys.contains(where: { $0.id == key.id }) { problem("\(path(k, "id")) appears more than once.") }
                    else if keys.contains(where: { SymbolBoardKey.exact($0.text, key.text) }) { problem("\(path(k, "text")) appears more than once.") }
                    keys.append(key)
                }
            }
        }
        guard problems.count == before, let id, let name else { return nil }
        return SymbolBoard(id: id, name: name, keys: keys, layout: layout)
    }

    private func readKey(_ item: TOMLTable, _ k: String) -> SymbolBoardKey? {
        allow(item, k, ["id", "text", "variants", "up", "down"])
        let before = problems.count
        let id = required(item, "id", k)
        if let id, !SymbolPageRules.validID(id) { check(path(k, "id"), "1 to 80 letters, digits, “.”, “-” or “_”") }
        let text = required(item, "text", k)
        if let text, !SymbolPageRules.validText(text) { check(path(k, "text"), "text of 1 to \(SymbolPageRules.maximumTextScalars) code points") }
        let scalars = SymbolPageRules.maximumTextScalars, limit = SymbolPageRules.maximumVariants
        let variants = item["variants"].flatMap { texts($0, path(k, "variants"), maximum: limit, scalars: scalars) } ?? []
        if let text, variants.contains(where: { SymbolBoardKey.exact($0, text) }) { problem("\(path(k, "variants")) repeats the key’s text.") }
        // An empty swipe list is the same as none: the gesture is off.
        let up = item["up"].flatMap { texts($0, path(k, "up"), maximum: limit, scalars: scalars) }
        let down = item["down"].flatMap { texts($0, path(k, "down"), maximum: limit, scalars: scalars) }
        guard problems.count == before, let id, let text else { return nil }
        return SymbolBoardKey(id: id, text: text, variants: variants, up: up?.isEmpty == false ? up : nil, down: down?.isEmpty == false ? down : nil)
    }

    private func readFavorites(_ t: TOMLTable, into c: inout UniboardConfiguration) {
        allow(t, "favorites", ["texts"])
        guard let value = t["texts"],
              let texts = texts(value, "favorites.texts", maximum: FavoriteSync.maximumCount, scalars: SymbolPageRules.maximumTextScalars) else { return }
        c.favorites = texts
        if FavoriteSync.replacementPayload(texts) == nil { problem("[favorites] exceeds the limit of 512 KB.") }
    }

    private func readFaces(_ t: TOMLTable) -> [String: FontFaceReference] {
        allow(t, "fonts", ["face"])
        var faces: [String: FontFaceReference] = [:]
        for (index, entry) in (tables(t, "face", "fonts") ?? []).enumerated() {
            let e = "fonts.face[\(index + 1)]"
            allow(entry, e, ["ref", "source", "family", "style", "postscript_name", "sha256", "face_index", "variations", "google_face", "in_library"])
            let before = problems.count
            let ref = required(entry, "ref", e)
            if let ref, !Self.validReference(ref) { check(path(e, "ref"), "1 to 64 lowercase letters, digits, “.”, “-” or “_”") }
            let source = choice(entry, "source", e, FontSource?.none, [FontSource.included, .downloaded, .imported, .installed, .system, .available].map { ($0.rawValue, Optional($0)) })
            if entry["source"] == nil { check(path(e, "source"), "a value; it’s missing") }
            let family = required(entry, "family", e), style = required(entry, "style", e), name = required(entry, "postscript_name", e)
            let sha256 = text(entry, "sha256", e)
            let faceIndex = integer(entry, "face_index", e, 0, { _ in true }, "a whole number from 0 to 65535")
            if entry["face_index"] != nil, sha256 == nil { check(path(e, "face_index"), "only with sha256") }
            if sha256 == nil, entry["sha256"] == nil, source != .installed, source != .system, source != nil { check(path(e, "sha256"), "64 lowercase hexadecimal digits; it’s missing") }
            var axes: [String: Double] = [:]
            if let variations = table(entry, "variations", e) {
                for (tag, value) in variations.entries {
                    guard let number = value.floatValue ?? value.integerValue.map({ Double($0) }) else { check(path(path(e, "variations"), ConfigurationCodec.fieldKey(tag)), "a number"); continue }
                    axes[tag] = number
                }
            }
            if let google = entry["google_face"], google.stringValue == nil { check(path(e, "google_face"), "text in quotes") }
            if let flag = entry["in_library"], flag.booleanValue == nil { check(path(e, "in_library"), "true or false") }
            guard problems.count == before, let ref, let source, let family, let style, let name else { continue }
            let identity: FontFaceReference.Identity = sha256.map { .file(sha256: $0, faceIndex: faceIndex, variations: axes) } ?? .process(postScriptName: name, variations: axes)
            let face = FontFaceReference(source: source, family: family, style: style, postScriptName: name, identity: identity,
                                         googleFaceID: entry["google_face"]?.stringValue)
            guard face.isValid else { problem("The font reference in \(e) isn’t valid."); continue }
            guard faces[ref] == nil else { problem("Font reference \(ref) appears more than once."); continue }
            faces[ref] = face
        }
        return faces
    }

    private static func validReference(_ ref: String) -> Bool {
        (1...64).contains(ref.utf8.count) && ref.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }
    }

    /// "U+16A0": 1–6 hex digits; whether it's a usable scalar is checked later.
    private static func scalar(_ text: String) -> UInt32? {
        guard text.hasPrefix("U+"), (1...6).contains(text.utf8.count - 2),
              text.utf8.dropFirst(2).allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return UInt32(text.dropFirst(2), radix: 16)
    }

    private func bounds(_ value: TOMLValue, _ field: String) -> (UInt32, UInt32)? {
        let values = strings(value, field)?.compactMap(Self.scalar)
        guard let values, values.count == 2, value.arrayValue?.count == 2 else {
            if values != nil { check(field, "two code points, such as [\"U+2190\", \"U+21FF\"]") }
            return nil
        }
        return (values[0], values[1])
    }

    private func readRules(_ t: TOMLTable, faces: [String: FontFaceReference], into c: inout UniboardConfiguration) {
        allow(t, "font_rules", ["rule"])
        var rules: [FontRule] = []
        var valid = true
        for (index, entry) in (tables(t, "rule", "font_rules") ?? []).enumerated() {
            let e = "font_rules.rule[\(index + 1)]"
            allow(entry, e, ["code_point", "range", "block", "block_range", "block_unicode_version", "font"])
            let before = problems.count
            var selector: FontRuleSelector?
            let kinds = ["code_point", "range", "block"].filter { entry[$0] != nil }
            if kinds.count != 1 { check(e, "exactly one of code_point, range or block") }
            if let value = text(entry, "code_point", e) {
                if let scalar = Self.scalar(value) { selector = .codePoint(scalar) } else { check(path(e, "code_point"), "a code point such as \"U+16A0\"") }
            }
            if let value = entry["range"], let range = bounds(value, path(e, "range")) { selector = .range(first: range.0, last: range.1) }
            if let name = text(entry, "block", e) {
                let table = FontRuleBlock(named: name)
                let given = entry["block_range"].flatMap { bounds($0, path(e, "block_range")) }
                if let given, table.map({ $0.first != given.0 || $0.last != given.1 }) ?? true { problem("The Unicode block \(ConfigurationCodec.displayed(name)) isn’t recognized.") }
                selector = .block(table ?? FontRuleBlock(name: name, first: 0, last: 0, unicodeVersion: ""))
            }
            if entry["block_range"] != nil || entry["block_unicode_version"] != nil, entry["block"] == nil { check(e, "block_range and block_unicode_version only with block") }
            if let version = entry["block_unicode_version"], version.stringValue == nil { check(path(e, "block_unicode_version"), "text in quotes") }
            let ref = required(entry, "font", e)
            let face = ref.flatMap { faces[$0] }
            if ref != nil, face == nil { check(path(e, "font"), "the ref of a [[fonts.face]] entry") }
            guard problems.count == before, let selector, let face else { valid = false; continue }
            rules.append(FontRule(selector: selector, face: face))
        }
        guard valid else { return }
        for issue in FontRuleValidator.validate(rules, blocks: UnicodeCatalog.shared.blocks) {
            problem(ConfigurationCodec.message(for: issue, rules: rules))
        }
        guard problems.isEmpty else { return }
        c.fontRules = rules
        if FontRuleStore.encode(rules, blocks: UnicodeCatalog.shared.blocks) == nil { problem("[font_rules] exceeds the limit of 1 MB.") }
    }

    private func readColors(_ t: TOMLTable, into c: inout UniboardConfiguration) {
        let p = "image_colors"
        allow(t, p, ["preset", "custom_text", "custom_background", "image_scale"])
        let fallback = ImageColorSettings.defaultValue
        c.imageColors.preset = choice(t, "preset", p, fallback.preset, ImageColorSettings.presetOrder.map { ($0, $0) })
        if let value = text(t, "custom_text", p) {
            if ImageColorSettings.isValid(ImageColorSettings.Value(preset: fallback.preset, customText: value, customBackground: fallback.customBackground)) {
                c.imageColors.customText = value
            } else { check(path(p, "custom_text"), "a color such as \"#000000\"") }
        }
        if let value = text(t, "custom_background", p) {
            if ImageColorSettings.isValid(ImageColorSettings.Value(preset: fallback.preset, customText: fallback.customText, customBackground: value)) {
                c.imageColors.customBackground = value
            } else { check(path(p, "custom_background"), "a color such as \"#FFFFFF\", or \"transparent\"") }
        }
        c.imageColors.scale = integer(t, "image_scale", p, fallback.scale, { KeyboardImageScale(rawValue: $0) != nil }, "1, 2 or 3")
    }
}
