import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class ConfigurationCodecTests: XCTestCase {
    private static let hash = String(repeating: "ab", count: 32)
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
        super.tearDown()
    }

    private func fileFace(_ family: String = "Junicode", style: String = "Bold", axes: [String: Double] = [:], google: String? = nil) -> FontFaceReference {
        FontFaceReference(source: .downloaded, family: family, style: style, postScriptName: family + "-" + style,
                          identity: .file(sha256: Self.hash, faceIndex: 1, variations: axes), googleFaceID: google)
    }

    private func installedFace(_ name: String = "Chalkduster") -> FontFaceReference {
        FontFaceReference(source: .installed, family: name, style: "Regular", postScriptName: name, identity: .process(postScriptName: name, variations: [:]))
    }

    private func runic() throws -> FontRuleBlock { try XCTUnwrap(FontRuleBlock(named: "Runic")) }

    /// Every category away from its defaults, with text the writer escapes.
    private func richConfiguration() throws -> UniboardConfiguration {
        var c = UniboardConfiguration.factoryDefaults
        c.settings.edition = .draft
        c.settings.useUnicodeFonts = true
        c.settings.showsUCSUR = true
        c.settings.prefersUCSUR = true
        c.settings.showsSymbolBar = false
        c.settings.searchBarInsteadOfSymbols = true
        c.settings.showsNumberRow = false
        c.settings.showsTextPreview = true
        c.settings.showsCollapseKey = true
        c.settings.padLayout = .ansi
        c.settings.padSymbolMapping = .macOS
        c.settings.layouts = ["en", "el"]
        c.autoCapitalization = .words
        c.browse = ConfigurationBrowse()
        c.browse.exploreGridDensity = 16
        c.browse.blockGridDensity = 8
        c.browse.tileColumns = 5
        c.browse.explorePlane = 1
        c.browse.showsPrivateUse = true
        c.browse.exploreDescending = true
        c.browse.emojiSortOrder = .newestFirst
        let standard = MainKeyboardArrangement.standard(for: .english)
        c.keys = KeyboardKeySettings.Snapshot(
            overrides: ["letter.a": .init(tap: ["á"], longPress: [], swipeUp: ["ä", "å"]), "digit.1": .init(shiftedTap: ["!"], swipeDown: ["¹"])],
            arrangements: ["en": MainKeyboardArrangement(keys: standard.keys.reversed(), layout: standard.layout)])
        var pages = c.pages
        pages.insert(SymbolBoard(id: "custom.1", name: "Ünïcode", keys: [
            SymbolBoardKey(id: "k1", text: "👩\u{200D}💻", variants: ["☺\u{FE0F}", "a\u{0007}b"], up: ["\u{E0041}"], down: ["\""]),
            SymbolBoardKey(id: "k2", text: "e\u{301}", variants: []),
        ], layout: "kkh/g"), at: 1)
        c.pages = pages
        c.starPageID = "custom.1"
        c.favorites = ["★", "👩\u{200D}💻", "e\u{301}", "é", "\\"]
        let bold = fileFace(axes: ["wght": 700, "wdth": 87.5], google: "google:1:2")
        c.fontRules = [
            FontRule(selector: .codePoint(0x16A0), face: bold),
            FontRule(selector: .range(first: 0x2190, last: 0x21FF), face: installedFace()),
            FontRule(selector: .block(try runic()), face: bold),
        ]
        c.imageColors = ImageColorSettings.Value(preset: "custom", customText: "#123456", customBackground: "transparent", scale: 2)
        return c
    }

    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigurationProblems> {
        ConfigurationCodec.decode(Data(text.utf8))
    }

    private func problems(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        switch decode(text) {
        case .success: XCTFail("decoded", file: file, line: line); return []
        case let .failure(problems): return problems.messages
        }
    }

    private func decoded(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> DecodedConfiguration {
        switch decode(text) {
        case let .success(result): return result
        case let .failure(problems): XCTFail(problems.messages.joined(separator: "\n"), file: file, line: line); throw problems
        }
    }

    private let header = "schema_version = 1\n"

    // MARK: Model

    func testCategoriesAndSectionsHaveTitlesSymbolsAndCategories() {
        XCTAssertEqual(ConfigurationCategory.allCases.map(\.title), ["Settings", "Layouts and Keys", "Favorites", "Font Choices and Rules", "Copy Image"])
        XCTAssertEqual(ConfigurationCategory.allCases.map(\.symbol), ["gearshape", "keyboard", "star", "textformat.alt", "paintpalette"])
        XCTAssertEqual(ConfigurationSection.allCases.map(\.category), [.settings, .layoutsAndKeys, .layoutsAndKeys, .favorites, .fontsAndRules, .imageColors])
        XCTAssertEqual(ConfigurationSection.allCases.map(\.rawValue), ["settings", "keyboard", "pages", "favorites", "font_rules", "image_colors"])
    }

    func testBrowseReadsDefaultsForUnsetValuesAndWritesEveryValue() {
        XCTAssertEqual(ConfigurationBrowse(AppPresentationSettings.Values()), ConfigurationBrowse())
        let values = AppPresentationSettings.Values(integers: ["exploreGridDensity": 8, "blockGridDensity": 16, "tileColumns": 4, "explorePlane": 2],
                                                    booleans: ["exploreShowsPrivateUse": true, "exploreDescending": true],
                                                    strings: ["emojiSortOrder": "oldestFirst"])
        let browse = ConfigurationBrowse(values)
        XCTAssertEqual(browse.exploreGridDensity, 8)
        XCTAssertEqual(browse.blockGridDensity, 16)
        XCTAssertEqual(browse.tileColumns, 4)
        XCTAssertEqual(browse.explorePlane, 2)
        XCTAssertTrue(browse.showsPrivateUse)
        XCTAssertTrue(browse.exploreDescending)
        XCTAssertEqual(browse.emojiSortOrder, .oldestFirst)
        XCTAssertEqual(browse.values, values)
        XCTAssertEqual(ConfigurationBrowse(AppPresentationSettings.Values(strings: ["emojiSortOrder": "nope"])).emojiSortOrder, .codePoint)
    }

    func testCaptureReadsCompiledFilesAndFallsBackToDefaults() throws {
        XCTAssertEqual(UniboardConfiguration.capture(directory: nil, presentation: .init(), favorites: []), .factoryDefaults)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigurationCapture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanup.append { try? FileManager.default.removeItem(at: directory) }
        let rich = try richConfiguration()
        let files = try XCTUnwrap(rich.compile())
        XCTAssertEqual(Set(files.keys), [UnicodeEditionSettings.filename, KeyboardKeySettings.filename, SymbolPageSettings.filename, FavoriteSync.filename,
                                         FontRuleStore.filename, ImageColorSettings.filename, AutoCapitalizationSetting.filename, AppPresentationSettings.filename])
        for (name, data) in files { try data.write(to: directory.appendingPathComponent(name)) }
        let captured = UniboardConfiguration.capture(directory: directory, presentation: rich.browse.values, favorites: rich.favorites)
        XCTAssertEqual(captured, rich)

        // Pages that fail the rules read as the stock pages.
        var broken = rich
        broken.pages.removeAll { $0.id == SymbolPageRules.stockID }
        try XCTUnwrap(SymbolPageSettings.encode(.init(pages: broken.pages, starPageID: broken.starPageID))).write(to: directory.appendingPathComponent(SymbolPageSettings.filename))
        let fallback = UniboardConfiguration.capture(directory: directory, presentation: rich.browse.values, favorites: [])
        XCTAssertEqual(fallback.pages, UniboardConfiguration.factoryDefaults.pages)
        XCTAssertEqual(fallback.starPageID, SymbolPageRules.favoritesID)
        XCTAssertNil(broken.compile())
    }

    func testCategoriesCompareByExactScalarsAndIgnoreRuleIDs() throws {
        let rich = try richConfiguration()
        var other = rich
        other.fontRules = rich.fontRules.map { FontRule(selector: $0.selector, face: $0.face) }
        XCTAssertEqual(other, rich)
        other.favorites[3] = "e\u{301}x"
        XCTAssertFalse(other.matches(rich, in: .favorites))
        XCTAssertTrue(other.matches(rich, in: .settings))
        var renamed = rich
        renamed.pages[1].name = "U\u{308}nïcode"
        XCTAssertFalse(renamed.matches(rich, in: .layoutsAndKeys))
        var layouts = rich
        layouts.settings.layouts = ["en"]
        XCTAssertTrue(layouts.matches(rich, in: .settings))
        XCTAssertFalse(layouts.matches(rich, in: .layoutsAndKeys))
        var colors = rich
        colors.imageColors.preset = "whiteOnBlack"
        XCTAssertFalse(colors.matches(rich, in: .imageColors))
        var rules = rich
        rules.fontRules.removeLast()
        XCTAssertFalse(rules.matches(rich, in: .fontsAndRules))
    }

    // MARK: Export

    func testExportFilenameUsesTheLocalDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        XCTAssertEqual(ConfigurationCodec.exportFilename(date: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar),
                       "Uniboard-Configuration-2027-01-15.toml")
    }

    func testDefaultsExportInSchemaOrder() throws {
        let text = try XCTUnwrap(String(data: try XCTUnwrap(ConfigurationCodec.encode(.factoryDefaults)), encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("schema_version = 1\n"))
        let order = ["[settings]", "[settings.browse]", "[keyboard]", "[pages]", "[[pages.page]]", "[favorites]", "[image_colors]"]
        let positions = order.map { text.range(of: $0)?.lowerBound }
        XCTAssertFalse(positions.contains(nil))
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted())
        XCTAssertFalse(text.contains("[[keyboard.key]]"))
        XCTAssertFalse(text.contains("fonts.face"))
        XCTAssertFalse(text.contains("font_rules.rule"))
        let result = try decoded(text)
        XCTAssertEqual(result.configuration, .factoryDefaults)
        XCTAssertEqual(result.missingSections, [])
        XCTAssertEqual(result.faces, [])
        XCTAssertEqual(result.formatVersion, 1)
        XCTAssertEqual(result.byteCount, text.utf8.count)
    }

    func testRichExportRoundTripsByteForByteAndWritesNothingPrivate() throws {
        let rich = try richConfiguration()
        let data = try XCTUnwrap(ConfigurationCodec.encode(rich, inLibrary: { $0.source == .installed }))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\\u200D"))
        XCTAssertTrue(text.contains("\\uFE0F"))
        XCTAssertTrue(text.contains("\\u0007"))
        XCTAssertTrue(text.contains("\\U000E0041"))
        XCTAssertTrue(text.contains("in_library = true"))
        XCTAssertTrue(text.contains("in_library = false"))
        XCTAssertTrue(text.contains("google_face = \"google:1:2\""))
        XCTAssertTrue(text.contains("block_range = [\"U+16A0\", \"U+16FF\"]"))
        XCTAssertEqual(text.components(separatedBy: "[[fonts.face]]").count - 1, 2)
        // Retired switches are never exported (Ato msg408).
        for word in ["scratchpad", "recent", "keyboardLayout", "activeBoardID", "replacement", "revision", "/Users", "file:",
                     "symbol_bar", "search_instead_of_symbols", "number_row", "top_row"] {
            XCTAssertFalse(text.contains(word), word)
        }
        let result = try decoded(text)
        XCTAssertEqual(result.configuration, rich)
        XCTAssertEqual(result.faces, ConfigurationCodec.uniqueFaces(rich.fontRules))
        XCTAssertEqual(result.faces.count, 2)
        XCTAssertEqual(result.ignoredSettings, [])
        XCTAssertEqual(ConfigurationCodec.encode(result.configuration, inLibrary: { $0.source == .installed }), data)
        XCTAssertEqual(ConfigurationCodec.encode(rich), ConfigurationCodec.encode(result.configuration))
    }

    /// The largest n in 0...upper for which `fits` holds; `fits` is monotone.
    private func largest(_ upper: Int, _ fits: (Int) -> Bool) -> Int {
        var low = 0, high = upper
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle) { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// 64 scalars: the prefix, then tag characters, the longest escape the writer makes.
    private func tagged(_ prefix: String) -> String {
        prefix + String(repeating: "\u{E0041}", count: 64 - prefix.unicodeScalars.count)
    }

    /// Every store filled to its own cap with text the writer escapes most.
    func testMaximalExportStaysWithinTheImportLimitAndImports() throws {
        var c = try richConfiguration()
        func pages(_ count: Int) -> [SymbolBoard] {
            SymbolPageRules.initialBoards(favorites: []) + (0..<14).map { page in
                SymbolBoard(id: "p\(page)", name: "Page \(page)", keys: (0..<max(0, min(256, count - page * 256))).map { key in
                    SymbolBoardKey(id: "k\(key)", text: tagged("\(key)"), variants: [])
                })
            }
        }
        c.pages = pages(largest(14 * 256) { SymbolPageSettings.encode(.init(pages: pages($0), starPageID: SymbolPageRules.favoritesID)) != nil })
        c.starPageID = SymbolPageRules.favoritesID
        func favorites(_ count: Int) -> [String] { (0..<count).map { tagged(String($0)) } }
        c.favorites = favorites(largest(FavoriteSync.maximumCount) { FavoriteSync.replacementPayload(favorites($0)) != nil })
        let ids = (Array("abcdefghijklmnopqrstuvwxyz").map { "letter.\($0)" } + (0...9).map { "digit.\($0)" })
        func keys(_ count: Int) -> KeyboardKeySettings.Snapshot {
            let choices = (0..<16).map { tagged(String($0)) }
            return KeyboardKeySettings.Snapshot(overrides: Dictionary(uniqueKeysWithValues: ids.prefix(count).map {
                ($0, KeyboardKeySettings.Overrides(longPress: choices, swipeUp: choices, swipeDown: choices))
            }))
        }
        c.keys = keys(largest(ids.count) { KeyboardKeySettings.encode(keys($0)) != nil })
        let faces = (0..<FontRuleLimits.maximumFaces).map { index in
            FontFaceReference(source: .downloaded, family: String(repeating: "F", count: 60) + "\(index)", style: "Bold Condensed Italic",
                              postScriptName: String(repeating: "P", count: 60) + "\(index)",
                              identity: .file(sha256: Self.hash, faceIndex: index, variations: ["wght": 700.5, "wdth": 75]), googleFaceID: "google:abc:\(index)")
        }
        c.fontRules = (0..<FontRuleLimits.maximumRules).map { index in
            index < FontRuleLimits.maximumRangeRules
                ? FontRule(selector: .range(first: 0x10000 + UInt32(index) * 2, last: 0x10001 + UInt32(index) * 2), face: faces[index % faces.count])
                : FontRule(selector: .codePoint(0x20000 + UInt32(index)), face: faces[index % faces.count])
        }
        XCTAssertNotNil(FontRuleStore.encode(c.fontRules))
        XCTAssertNotNil(c.compile())

        let data = try XCTUnwrap(ConfigurationCodec.encode(c, inLibrary: { _ in true }))
        XCTAssertLessThanOrEqual(data.count, ConfigurationCodec.maximumBytes)
        XCTAssertGreaterThan(data.count, 2_000_000)
        guard case let .success(result) = ConfigurationCodec.decode(data) else { return XCTFail("a maximal export didn’t import") }
        XCTAssertEqual(result.configuration, c)

        c.favorites += (0..<3000).map { tagged("x\($0)") }
        XCTAssertNil(ConfigurationCodec.encode(c))
    }

    // MARK: Decode

    func testFileLevelProblems() throws {
        guard case let .failure(large) = ConfigurationCodec.decode(Data(count: ConfigurationCodec.maximumBytes + 1)) else { return XCTFail("decoded") }
        XCTAssertEqual(large.messages, [ConfigurationCodec.tooLarge])
        XCTAssertEqual(ConfigurationCodec.tooLarge, "This file exceeds the 4 MB import limit.")
        let syntax = problems("a = ")
        XCTAssertEqual(syntax.count, 1)
        XCTAssertTrue(syntax[0].hasPrefix("Check line 1, column "), syntax[0])
        XCTAssertEqual(problems("[settings]\n"), [ConfigurationCodec.missingVersion])
        XCTAssertEqual(problems("schema_version = 2\n"), [ConfigurationCodec.unsupportedVersion])
        XCTAssertEqual(problems("schema_version = \"1\"\n"), [ConfigurationCodec.unsupportedVersion])
        XCTAssertEqual(problems(header + "extra = 1\n[\"odd key\"]\n"), ["Unrecognized setting: extra.", "Unrecognized setting: \"odd key\"."])
        XCTAssertEqual(problems(header + "settings = 1\n"), ["Check settings: a table."])
    }

    func testMissingSectionsResetToDefaults() throws {
        let result = try decoded(header)
        XCTAssertEqual(result.configuration, .factoryDefaults)
        XCTAssertEqual(result.missingSections, ConfigurationSection.allCases)
    }

    func testSettingsProblems() {
        let text = header + """
        [settings]
        unicode_edition = "1.0.0"
        extra_unicode_fonts = 1
        ipad_landscape_layout = "wide"
        auto_capitalization = "Words"
        other = true
        [settings.browse]
        explore_grid_density = 4
        block_grid_density = 32.0
        tile_columns = 1
        explore_plane = 17
        emoji_sort_order = 3
        mystery = 1
        """
        XCTAssertEqual(problems(text), [
            "Unrecognized setting: settings.other.",
            "Check settings.unicode_edition: \(editionChoices()).",
            "Check settings.extra_unicode_fonts: true or false.",
            "Check settings.ipad_landscape_layout: \"stock\", \"ansi\" or \"ansiNumbers\".",
            "Check settings.auto_capitalization: \"follow_app\", \"off\", \"sentences\", \"words\" or \"all_characters\".",
            "Unrecognized setting: settings.browse.mystery.",
            "Check settings.browse.explore_grid_density: 3, 8, 16 or 32.",
            "Check settings.browse.block_grid_density: 3, 8, 16 or 32.",
            "Check settings.browse.tile_columns: a whole number from 2 to 256.",
            "Check settings.browse.explore_plane: -1 for all planes, or 0 to 16.",
            "Check settings.browse.emoji_sort_order: \"newestFirst\", \"oldestFirst\" or \"codePoint\".",
        ])
    }

    private func editionChoices() -> String {
        let names = [UnicodeEdition.latest, .draft, .previous, .older]
            .filter { UnicodeEdition.resolve(selectionIdentifier: $0.selectionIdentifier) == $0 }.map { "\"\($0.selectionIdentifier)\"" }
        return names.dropLast().joined(separator: ", ") + " or " + names.last!
    }

    func testRetiredSettingsAreListedNeverReadOrChecked() throws {
        let rich = try richConfiguration()
        var document = ConfigurationCodec.document(rich)
        var settings = try XCTUnwrap(document["settings"]?.tableValue)
        settings["number_row"] = .boolean(true)
        settings["top_row"] = .string("anything")
        settings["search_instead_of_symbols"] = .integer(3)
        settings["symbol_bar"] = .boolean(true)
        document["settings"] = .table(settings)
        let result = try decoded(TOMLDocument.write(document))
        XCTAssertEqual(result.ignoredSettings, [
            ConfigurationIgnoredSetting(name: "Number Row", key: "settings.number_row"),
            ConfigurationIgnoredSetting(name: "Top Row", key: "settings.top_row"),
            ConfigurationIgnoredSetting(name: "Top Row", key: "settings.search_instead_of_symbols"),
            ConfigurationIgnoredSetting(name: "Top Row", key: "settings.symbol_bar"),
        ])
        // Never read: the decoded values are the defaults, whatever the file says.
        let defaults = UnicodeEditionSettings.Snapshot(edition: .latest)
        XCTAssertEqual(result.configuration.settings.showsNumberRow, defaults.showsNumberRow)
        XCTAssertEqual(result.configuration.settings.showsSymbolBar, defaults.showsSymbolBar)
        XCTAssertEqual(result.configuration.settings.searchBarInsteadOfSymbols, defaults.searchBarInsteadOfSymbols)
        // An otherwise identical file has no changes; nothing in the diff names them.
        XCTAssertEqual(result.configuration, rich)
        let diff = ConfigurationDiff(current: rich, incoming: result.configuration, missingSections: result.missingSections)
        XCTAssertTrue(diff.isIdentical)
        XCTAssertFalse(diff.changes.flatMap(\.lines).contains { $0.contains("Number Row") || $0.contains("Symbol") })
        // Retired values alone never differ.
        var flipped = rich
        flipped.settings.showsNumberRow.toggle()
        flipped.settings.showsSymbolBar.toggle()
        flipped.settings.searchBarInsteadOfSymbols.toggle()
        XCTAssertTrue(flipped.matches(rich, in: .settings))
        XCTAssertEqual(flipped.settings.withoutRetired, rich.settings.withoutRetired)
        let kept = rich.settings.keepingRetired(from: flipped.settings)
        XCTAssertEqual(kept.showsNumberRow, flipped.settings.showsNumberRow)
        XCTAssertEqual(kept.showsSymbolBar, flipped.settings.showsSymbolBar)
        XCTAssertEqual(kept.searchBarInsteadOfSymbols, flipped.settings.searchBarInsteadOfSymbols)
        // A section without them lists none.
        XCTAssertEqual(try decoded(header + "[settings]\nextra_unicode_fonts = true\n").ignoredSettings, [])
    }

    func testPartialSettingsUseDefaultsForAbsentKeys() throws {
        let result = try decoded(header + "[settings]\nextra_unicode_fonts = true\n[settings.browse]\ntile_columns = 200\n")
        var expected = UniboardConfiguration.factoryDefaults
        expected.settings.useUnicodeFonts = true
        expected.browse.tileColumns = 200
        XCTAssertEqual(result.configuration, expected)
        XCTAssertEqual(result.missingSections, [.keyboard, .pages, .favorites, .fontRules, .imageColors])
    }

    func testKeyboardProblems() {
        XCTAssertEqual(problems(header + "[keyboard]\nlayouts = []\n"), ["Check keyboard.layouts: 1 to 8 layouts."])
        XCTAssertEqual(problems(header + "[keyboard]\nlayouts = [1]\n"), ["Check keyboard.layouts: a list of text in quotes."])
        XCTAssertEqual(problems(header + "[keyboard]\nlayouts = [\"en\", \"xx\", \"en\"]\nkey = 1\narrangement = [1]\n"), [
            "Check keyboard.layouts[2]: a layout id such as \"en\".",
            "Layout en appears more than once.",
            "Check keyboard.key: a list of tables, written [[keyboard.key]].",
            "Check keyboard.arrangement: a list of tables, written [[keyboard.arrangement]].",
        ])
        let keys = header + """
        [keyboard]
        [[keyboard.key]]
        tap = ["a", "b"]
        [[keyboard.key]]
        id = "letter.zz"
        [[keyboard.key]]
        id = "letter.a"
        long_press = ["", "x", "x"]
        swipe_up = 3
        hold = []
        [[keyboard.key]]
        id = "letter.b"
        [[keyboard.key]]
        id = "letter.b"
        """
        XCTAssertEqual(problems(keys), [
            "keyboard.key[1].tap exceeds the limit of 1.",
            "Check keyboard.key[1].id: a value; it’s missing.",
            "Check keyboard.key[2].id: a key id such as \"letter.a\".",
            "Unrecognized setting: keyboard.key[3].hold.",
            "Check keyboard.key[3].long_press[1]: text of 1 to 64 code points.",
            "keyboard.key[3].long_press[3] appears more than once.",
            "Check keyboard.key[3].swipe_up: a list of text in quotes.",
            "Key letter.b appears more than once.",
        ])
        let arrangements = header + """
        [keyboard]
        [[keyboard.arrangement]]
        keys = ["q"]
        [[keyboard.arrangement]]
        layout = "zz"
        keys = ["q"]
        places = "k"
        [[keyboard.arrangement]]
        layout = "en"
        places = "k"
        [[keyboard.arrangement]]
        layout = "en"
        keys = ["q"]
        places = "k"
        [[keyboard.arrangement]]
        layout = "el"
        keys = ["q"]
        places = "k"
        """
        XCTAssertEqual(problems(arrangements), [
            "Check keyboard.arrangement[1].places: a value; it’s missing.",
            "Check keyboard.arrangement[1].layout: a value; it’s missing.",
            "Check keyboard.arrangement[2].layout: a layout id such as \"en\".",
            "Check keyboard.arrangement[3].keys: a value; it’s missing.",
            "The arrangement for en appears more than once.",
            "Check keyboard.arrangement[5]: every letter of the layout once, Shift and Delete once, Tab, Caps Lock and each digit at most once, and one place for each key in up to 4 rows.",
        ])
    }

    func testKeyboardExplicitEmptyListsDifferFromAbsentAndStandardArrangementsAreDropped() throws {
        let standard = MainKeyboardArrangement.standard(for: .english)
        let text = header + """
        [keyboard]
        layouts = ["el", "en"]
        [[keyboard.key]]
        id = "letter.a"
        long_press = []
        [[keyboard.key]]
        id = "letter.b"
        [[keyboard.arrangement]]
        layout = "en"
        keys = [\(standard.keys.map { "\"\($0)\"" }.joined(separator: ", "))]
        places = "\(standard.layout)"
        """
        let keys = try decoded(text).configuration
        XCTAssertEqual(keys.settings.layouts, ["el", "en"])
        XCTAssertEqual(keys.keys.overrides, ["letter.a": .init(longPress: [])])
        XCTAssertEqual(keys.keys.arrangements, [:])
    }

    func testPagesProblems() {
        XCTAssertEqual(problems(header + "[pages]\nstar_page = \"none\"\n"), ["Check pages.star_page: the id of a page in pages.page."])
        let tooMany = header + "[pages]\n" + String(repeating: "[[pages.page]]\nid = \"x\"\nname = \"X\"\n", count: 17)
        XCTAssertEqual(problems(tooMany), ["pages.page exceeds the limit of 16."])
        let missing = header + "[pages]\n[[pages.page]]\nid = \"custom\"\nname = \"Custom\"\n"
        XCTAssertEqual(problems(missing), ["Check pages.page: a page with id \"stock-symbols\".", "Check pages.page: a page with id \"migrated-favorites\"."])
        let pages = header + """
        [pages]
        [[pages.page]]
        id = "stock-symbols"
        name = "Symbols"
        [[pages.page]]
        id = "stock-symbols"
        name = " Spaced "
        layout = "kx"
        tint = 1
        [[pages.page]]
        id = "bad id"
        [[pages.page]]
        id = "migrated-favorites"
        name = "Favorites"
        [[pages.page.key]]
        id = "f"
        text = "★"
        [[pages.page]]
        id = "many"
        name = "Many"
        \(String(repeating: "[[pages.page.key]]\nid = \"k\"\ntext = \"k\"\n", count: 257))
        [[pages.page]]
        id = "keys"
        name = "Keys"
        [[pages.page.key]]
        id = "a"
        text = "a"
        variants = ["a", "b"]
        up = []
        down = [""]
        size = 1
        [[pages.page.key]]
        text = ""
        [[pages.page.key]]
        id = "b"
        text = "b"
        [[pages.page.key]]
        id = "b"
        text = "c"
        [[pages.page.key]]
        id = "c"
        text = "b"
        [[pages.page.key]]
        id = "bad id"
        text = "\(String(repeating: "x", count: 65))"
        """
        XCTAssertEqual(problems(pages), [
            "Unrecognized setting: pages.page[2].tint.",
            "Check pages.page[2].name: a name of 1 to 32 characters without spaces at either end.",
            "Check pages.page[2].layout: rows of k (key), h (half gap) and g (gap) separated by /.",
            "Check pages.page[3].id: 1 to 80 letters, digits, “.”, “-” or “_”.",
            "Check pages.page[3].name: a value; it’s missing.",
            "Check pages.page[4].key: no keys: the Favorites page’s keys come from [favorites].",
            "pages.page[5].key exceeds the limit of 256.",
            "Unrecognized setting: pages.page[6].key[1].size.",
            "pages.page[6].key[1].variants repeats the key’s text.",
            "Check pages.page[6].key[1].down[1]: text of 1 to 64 code points.",
            "Check pages.page[6].key[2].id: a value; it’s missing.",
            "Check pages.page[6].key[2].text: text of 1 to 64 code points.",
            "pages.page[6].key[4].id appears more than once.",
            "pages.page[6].key[5].text appears more than once.",
            "Check pages.page[6].key[6].id: 1 to 80 letters, digits, “.”, “-” or “_”.",
            "Check pages.page[6].key[6].text: text of 1 to 64 code points.",
        ])
        let duplicate = header + """
        [pages]
        [[pages.page]]
        id = "stock-symbols"
        name = "Symbols"
        [[pages.page]]
        id = "stock-symbols"
        name = "Again"
        """
        XCTAssertEqual(problems(duplicate), ["Page stock-symbols appears more than once."])
    }

    func testPagesKeepEmptySwipesOffAndStarDefaultsToFavorites() throws {
        let text = header + """
        [pages]
        [[pages.page]]
        id = "migrated-favorites"
        name = "Favorites"
        [[pages.page]]
        id = "stock-symbols"
        name = "Symbols"
        layout = "kk"
        [[pages.page.key]]
        id = "a"
        text = "a"
        up = []
        down = ["d"]
        """
        let c = try decoded(text).configuration
        XCTAssertEqual(c.starPageID, SymbolPageRules.favoritesID)
        XCTAssertEqual(c.pages.map(\.id), [SymbolPageRules.favoritesID, SymbolPageRules.stockID])
        XCTAssertEqual(c.pages[1].keys, [SymbolBoardKey(id: "a", text: "a", variants: [], up: nil, down: ["d"])])
        XCTAssertEqual(c.pages[1].layout, "kk")
    }

    func testFavoritesProblemsAndLimits() throws {
        XCTAssertEqual(problems(header + "[favorites]\ntexts = [\"a\", \"a\"]\nmore = 1\n"),
                       ["Unrecognized setting: favorites.more.", "favorites.texts[2] appears more than once."])
        let many = (0...FavoriteSync.maximumCount).map { "\"\($0)\"" }.joined(separator: ",")
        XCTAssertEqual(problems(header + "[favorites]\ntexts = [\(many)]\n"), ["favorites.texts exceeds the limit of 4,096."])
        // Canonically equivalent texts are different favorites.
        XCTAssertEqual(try decoded(header + "[favorites]\ntexts = [\"é\", \"e\\u0301\"]\n").configuration.favorites, ["é", "e\u{301}"])
        XCTAssertEqual(try decoded(header + "[favorites]\n").configuration.favorites, [])
        // Over the store's 512 KB once encoded: 4,096 favorites of 64 tag characters.
        let tags = String(repeating: "\\U000E0041", count: 60)
        let oversized = (0..<FavoriteSync.maximumCount).map { "\"\(tags)\(String(format: "%04d", $0))\"" }.joined(separator: ",")
        XCTAssertEqual(problems(header + "[favorites]\ntexts = [\(oversized)]\n"), ["[favorites] exceeds the limit of 512 KB."])
    }

    func testFontProblems() throws {
        let text = header + """
        [fonts]
        extra = 1
        [[fonts.face]]
        ref = "Font 1"
        source = "cloud"
        family = "F"
        style = "S"
        postscript_name = "F-S"
        face_index = 1
        variations = { wght = "bold", "a b" = true }
        google_face = 1
        in_library = "yes"
        tag = 1
        [[fonts.face]]
        ref = "font-2"
        family = "F"
        style = "S"
        postscript_name = "F-S"
        [[fonts.face]]
        ref = "font-3"
        source = "downloaded"
        family = "F"
        style = "S"
        postscript_name = "F-S"
        [[fonts.face]]
        ref = "font-4"
        source = "downloaded"
        family = "F"
        style = "S"
        postscript_name = "F-S"
        sha256 = "nothex"
        face_index = -1
        [[fonts.face]]
        ref = "font-5"
        source = "installed"
        family = "F"
        style = "S"
        postscript_name = "F-S"
        [[fonts.face]]
        ref = "font-5"
        source = "installed"
        family = "F"
        style = "S"
        postscript_name = "F-S"
        """
        XCTAssertEqual(problems(text), [
            "Unrecognized setting: fonts.extra.",
            "Unrecognized setting: fonts.face[1].tag.",
            "Check fonts.face[1].ref: 1 to 64 lowercase letters, digits, “.”, “-” or “_”.",
            "Check fonts.face[1].source: \"included\", \"downloaded\", \"imported\", \"installed\", \"system\" or \"available\".",
            "Check fonts.face[1].face_index: only with sha256.",
            "Check fonts.face[1].variations.wght: a number.",
            "Check fonts.face[1].variations.\"a b\": a number.",
            "Check fonts.face[1].google_face: text in quotes.",
            "Check fonts.face[1].in_library: true or false.",
            "Check fonts.face[2].source: a value; it’s missing.",
            "Check fonts.face[3].sha256: 64 lowercase hexadecimal digits; it’s missing.",
            "The font reference in fonts.face[4] isn’t valid.",
            "Font reference font-5 appears more than once.",
        ])
    }

    func testRulesProblems() throws {
        let face = """
        [[fonts.face]]
        ref = "font-1"
        source = "installed"
        family = "Chalkduster"
        style = "Regular"
        postscript_name = "Chalkduster"
        variations = { wght = 400 }

        """
        let text = header + face + """
        [font_rules]
        [[font_rules.rule]]
        font = "font-1"
        [[font_rules.rule]]
        code_point = "16A0"
        font = "font-2"
        [[font_rules.rule]]
        range = ["U+2190"]
        block_unicode_version = 1
        font = "font-1"
        [[font_rules.rule]]
        block = "Runic"
        block_range = ["U+16A0", "U+16A1"]
        font = "font-1"
        [[font_rules.rule]]
        code_point = "U+0041"
        block_range = ["U+0", "U+1"]
        weight = 1
        [[font_rules.rule]]
        block = "Nowhere"
        block_range = ["U+0", "U+1"]
        font = "font-1"
        """
        XCTAssertEqual(problems(text), [
            "Check font_rules.rule[1]: exactly one of code_point, range or block.",
            "Check font_rules.rule[2].code_point: a code point such as \"U+16A0\".",
            "Check font_rules.rule[2].font: the ref of a [[fonts.face]] entry.",
            "Check font_rules.rule[3].range: two code points, such as [\"U+2190\", \"U+21FF\"].",
            "Check font_rules.rule[3]: block_range and block_unicode_version only with block.",
            "Check font_rules.rule[3].block_unicode_version: text in quotes.",
            "The Unicode block Runic isn’t recognized.",
            "Unrecognized setting: font_rules.rule[5].weight.",
            "Check font_rules.rule[5]: block_range and block_unicode_version only with block.",
            "Check font_rules.rule[5].font: a value; it’s missing.",
            "The Unicode block Nowhere isn’t recognized.",
        ])
        let validated = header + face + """
        [[font_rules.rule]]
        code_point = "U+D800"
        font = "font-1"
        [[font_rules.rule]]
        block = "Nowhere"
        font = "font-1"
        [[font_rules.rule]]
        range = ["U+21FF", "U+2190"]
        font = "font-1"
        """
        XCTAssertEqual(problems(validated), [
            "Check font_rules.rule[1]: code points outside the surrogates U+D800–U+DFFF.",
            "The Unicode block Nowhere isn’t recognized.",
            "Check font_rules.rule[3].range: the first code point can’t come after the last.",
        ])
        let rules = header + face + """
        [[font_rules.rule]]
        block = "Runic"
        block_range = ["U+16A0", "U+16FF"]
        block_unicode_version = "1.0"
        font = "font-1"
        [[font_rules.rule]]
        range = ["U+1F600", "U+1F64F"]
        font = "font-1"
        """
        let result = try decoded(rules)
        XCTAssertEqual(result.configuration.fontRules.map(\.selector), [.block(try runic()), .range(first: 0x1F600, last: 0x1F64F)])
        XCTAssertEqual(result.faces, [FontFaceReference(source: .installed, family: "Chalkduster", style: "Regular", postScriptName: "Chalkduster",
                                                        identity: .process(postScriptName: "Chalkduster", variations: ["wght": 400]))])
        XCTAssertEqual(problems(header + "[font_rules]\nrule = [1]\n"), ["Check font_rules.rule: a list of tables, written [[font_rules.rule]]."])
    }

    func testRuleLimitsAreErrors() {
        let face = "[[fonts.face]]\nref = \"f\"\nsource = \"installed\"\nfamily = \"F\"\nstyle = \"R\"\npostscript_name = \"F\"\n"
        let rules = (0...FontRuleLimits.maximumRules).map { "[[font_rules.rule]]\ncode_point = \"U+\(String($0 + 0x100, radix: 16))\"\nfont = \"f\"\n" }.joined()
        XCTAssertEqual(problems(header + face + rules), ["font_rules.rule exceeds the limit of 1,024."])
    }

    func testImageColorProblemsAndValues() throws {
        XCTAssertEqual(problems(header + "[image_colors]\npreset = \"sepia\"\ncustom_text = \"red\"\ncustom_background = \"#12345G\"\n"), [
            "Check image_colors.preset: \"blackOnWhite\", \"blackOnClear\", \"whiteOnBlack\", \"whiteOnClear\" or \"custom\".",
            "Check image_colors.custom_text: a color such as \"#000000\".",
            "Check image_colors.custom_background: a color such as \"#FFFFFF\", or \"transparent\".",
        ])
        let colors = try decoded(header + "[image_colors]\npreset = \"custom\"\ncustom_text = \"#abcdef\"\ncustom_background = \"#00FF00\"\n").configuration.imageColors
        XCTAssertEqual(colors, ImageColorSettings.Value(preset: "custom", customText: "#abcdef", customBackground: "#00FF00"))
        XCTAssertEqual(colors.scale, 3, "A file without image_scale means 3")
    }

    func testImageScaleAcceptsOnlyOneTwoOrThree() throws {
        for (value, scale) in [("1", 1), ("2", 2), ("3", 3)] {
            XCTAssertEqual(try decoded(header + "[image_colors]\nimage_scale = \(value)\n").configuration.imageColors.scale, scale)
        }
        for value in ["0", "4", "-3", "3.0", "\"3\"", "true"] {
            XCTAssertEqual(problems(header + "[image_colors]\nimage_scale = \(value)\n"), ["Check image_colors.image_scale: 1, 2 or 3."], value)
        }
        // Exported, and read back.
        var c = UniboardConfiguration.factoryDefaults
        c.imageColors.scale = 1
        let text = String(decoding: try XCTUnwrap(ConfigurationCodec.encode(c)), as: UTF8.self)
        XCTAssertTrue(text.contains("image_scale = 1\n"), text)
        XCTAssertEqual(try decoded(text).configuration, c)
        XCTAssertTrue(String(decoding: try XCTUnwrap(ConfigurationCodec.encode(.factoryDefaults)), as: UTF8.self).contains("image_scale = 3\n"))
        // Scale alone is a change to the Copy Image section.
        let diff = ConfigurationDiff(current: .factoryDefaults, incoming: c)
        XCTAssertEqual(diff.change(.imageColors).status, .changed)
        XCTAssertEqual(diff.change(.imageColors).lines, ["Image scale: 3× → 1×"])
        XCTAssertFalse(c.matches(.factoryDefaults, in: .imageColors))
    }

    func testProblemsAreCapped() {
        let unknown = (0..<1100).map { "k\($0) = 1\n" }.joined()
        XCTAssertEqual(problems(header + unknown).count, ConfigurationCodec.maximumProblems)
    }

    // MARK: Messages

    func testRuleMessagesAndLabels() throws {
        let block = try runic()
        let rules = [FontRule(selector: .codePoint(0x41), face: installedFace()), FontRule(selector: .range(first: 1, last: 2), face: installedFace()),
                     FontRule(selector: .block(block), face: installedFace())]
        XCTAssertEqual(ConfigurationCodec.message(for: .invalidCodePoint(rule: 0), rules: rules), "Check font_rules.rule[1]: code points from U+0000 to U+10FFFF.")
        XCTAssertEqual(ConfigurationCodec.message(for: .duplicate(rule: 1, original: 0, kind: .range), rules: rules), "Range rule U+0001–U+0002 appears more than once.")
        XCTAssertEqual(ConfigurationCodec.message(for: .duplicate(rule: 2, original: 0, kind: .block), rules: rules), "Unicode block rule Runic appears more than once.")
        XCTAssertEqual(ConfigurationCodec.message(for: .duplicate(rule: 0, original: 0, kind: .codePoint), rules: rules), "Code point rule U+0041 appears more than once.")
        XCTAssertEqual(ConfigurationCodec.message(for: .invalidFace(rule: 1), rules: rules), "The font reference in font_rules.rule[2].font isn’t valid.")
        XCTAssertEqual(ConfigurationCodec.message(for: .tooManyRules(limit: 1024), rules: rules), "font_rules.rule exceeds the limit of 1,024.")
        XCTAssertEqual(ConfigurationCodec.message(for: .tooManyRanges(limit: 256), rules: rules), "Range rules in font_rules.rule exceed the limit of 256.")
        XCTAssertEqual(ConfigurationCodec.message(for: .tooManyFaces(limit: 256), rules: rules), "Fonts used in font_rules.rule exceed the limit of 256.")
        XCTAssertEqual(ConfigurationCodec.message(for: .unknownBlock(rule: 0, name: "X"), rules: rules, path: "rules"), "The Unicode block X isn’t recognized.")
    }

    func testDisplayedTextIsBoundedAndEscaped() {
        XCTAssertEqual(ConfigurationCodec.displayed("Runic"), "Runic")
        XCTAssertEqual(ConfigurationCodec.displayed(""), "\"\"")
        XCTAssertEqual(ConfigurationCodec.displayed("a\u{200D}b"), "\"a\\u200Db\"")
        XCTAssertEqual(ConfigurationCodec.displayed(String(repeating: "x", count: 64)), String(repeating: "x", count: 64))
        XCTAssertEqual(ConfigurationCodec.displayed(String(repeating: "x", count: 65)), "\"" + String(repeating: "x", count: 63) + "…")
        XCTAssertEqual(ConfigurationCodec.fieldKey("plain"), "plain")
        XCTAssertEqual(ConfigurationCodec.fieldKey("a b"), "\"a b\"")
    }

    // MARK: Diff

    func testIdenticalImportHasNoChanges() throws {
        let rich = try richConfiguration()
        let diff = ConfigurationDiff(current: rich, incoming: rich, missingSections: [.favorites])
        XCTAssertTrue(diff.isIdentical)
        XCTAssertFalse(diff.showsMissingSections)
        XCTAssertFalse(diff.replacesFavoritesOrKeys)
        XCTAssertFalse(diff.changesExtraUnicodeFonts)
        XCTAssertEqual(diff.changes.map(\.status), Array(repeating: .unchanged, count: 5))
        XCTAssertEqual(diff.changes.map(\.category), ConfigurationCategory.allCases)
        XCTAssertEqual(ConfigurationChangeStatus.unchanged.title, "Unchanged")
        XCTAssertEqual(ConfigurationChangeStatus.changed.title, "Will change")
        XCTAssertEqual(ConfigurationChangeStatus.reset.title, "Will reset to defaults")
    }

    func testDiffListsEverySettingChangeWithExtraUnicodeFontsFirst() throws {
        let rich = try richConfiguration()
        let diff = ConfigurationDiff(current: .factoryDefaults, incoming: rich)
        XCTAssertFalse(diff.isIdentical)
        XCTAssertTrue(diff.changesExtraUnicodeFonts)
        XCTAssertTrue(diff.replacesFavoritesOrKeys)
        let settings = diff.change(.settings)
        XCTAssertEqual(settings.status, .changed)
        XCTAssertEqual(settings.lines, [
            "Extra Unicode Fonts: Off → On",
            "Unicode Version: \(UnicodeEdition.latest.title) → \(UnicodeEdition.draft.title)",
            "Private Use Area: Off → On",
            "ConScript (UCSUR): Off → On",
            "Prefer ConScript over PUA: Off → On",
            "Text Preview: Off → On",
            "Hide Keyboard Key: Off → On",
            "iPad Landscape Layout: Full ANSI → Compact ANSI",
            "iPad Symbol Mapping: Standard symbol page → macOS Option symbols",
            AutoCapitalizationCopy.change(from: .followApp, to: .words),
            "Explore Grid: Tiles → 16 per Row",
            "Blocks Grid: Tiles → 8 per Row",
            "Tile Columns: 3 → 5",
            "Explore Plane: All Planes → Plane 1",
            "Explore Order: Ascending → Descending",
            "Emoji Order: Code point → Newest first",
        ])
        XCTAssertEqual(ConfigurationDiff(current: rich, incoming: .factoryDefaults).change(.settings).lines.first, "Extra Unicode Fonts: On → Off")
        XCTAssertEqual(diff.change(.layoutsAndKeys).lines, [
            "Layouts: English → English, Ελληνικά",
            "Customizes the 1 key",
            "Customizes the A key",
            "Rearranges the English keyboard",
            "Adds page Ünïcode",
            "Star key opens: Favorites → Ünïcode",
        ])
        XCTAssertEqual(diff.change(.favorites).lines, ["Adds 5 favorites"])
        XCTAssertEqual(diff.change(.fontsAndRules).lines, [
            "Adds code point rule U+16A0: Junicode Bold",
            "Adds range rule U+2190–U+21FF: Chalkduster Regular",
            "Adds Unicode block rule Runic: Junicode Bold",
        ])
        XCTAssertEqual(diff.change(.imageColors).lines, ["Image colors: Black on White → Custom", "Custom Text Color: #000000 → #123456",
                                                          "Custom Background: #FFFFFF → Transparent", "Image scale: 3× → 2×"])
        XCTAssertEqual(ConfigurationDiff(current: rich, incoming: .factoryDefaults).change(.imageColors).lines.last, "Image scale: 2× → 3×")
    }

    func testDiffNamesAStarPageMissingFromThePagesByItsID() throws {
        var current = try richConfiguration(), incoming = current
        current.starPageID = "custom.gone"
        incoming.starPageID = SymbolPageRules.stockID
        let diff = ConfigurationDiff(current: current, incoming: incoming, missingSections: [])
        XCTAssertEqual(diff.change(.layoutsAndKeys).lines, ["Star key opens: custom.gone → Symbols"])
    }

    func testDiffDescribesRemovalsReordersAndResets() throws {
        let rich = try richConfiguration()
        var next = rich
        next.settings.layouts = ["xx"]
        next.keys = KeyboardKeySettings.Snapshot(overrides: ["letter.a": .init(tap: ["à"]), "custom.key": .init(tap: ["x"])])
        next.pages.swapAt(0, 2)
        next.pages.removeAll { $0.id == "custom.1" }
        next.pages.append(SymbolBoard(id: "custom.1", name: "Renamed", keys: [SymbolBoardKey(id: "z", text: "z", variants: [])], layout: nil))
        next.pages[1].keys.removeLast()
        next.starPageID = SymbolPageRules.stockID
        next.favorites = ["\\", "👩\u{200D}💻", "new"]
        next.fontRules = [FontRule(selector: .block(try runic()), face: installedFace("Papyrus")),
                          FontRule(selector: .codePoint(0x16A0), face: rich.fontRules[0].face)]
        next.imageColors.preset = "whiteOnClear"
        let diff = ConfigurationDiff(current: rich, incoming: next, missingSections: [.favorites, .imageColors])
        XCTAssertEqual(diff.change(.layoutsAndKeys).lines, [
            "Layouts: English, Ελληνικά → xx",
            "Customizes the custom.key key",
            "Restores the 1 key",
            "Changes the A key",
            "Restores the standard English keyboard",
            "Page Symbols: 24 keys → 23 keys",
            "Renames page Ünïcode to Renamed",
            "Page Renamed: 2 keys → 1 key",
            "Changes the rows of page Renamed",
            "Reorders pages",
            "Star key opens: Ünïcode → Symbols",
        ])
        XCTAssertEqual(diff.change(.favorites).status, .reset)
        XCTAssertEqual(diff.change(.favorites).lines, ["Adds 1 favorite", "Removes 3 favorites", "Reorders favorites"])
        XCTAssertEqual(diff.change(.fontsAndRules).status, .changed)
        XCTAssertEqual(diff.change(.fontsAndRules).lines, [
            "Removes range rule U+2190–U+21FF",
            "Unicode block rule Runic: Junicode Bold → Papyrus Regular",
            "Reorders font rules",
        ])
        XCTAssertEqual(diff.change(.imageColors).lines, ["Image colors: Custom → White on Transparent"])
        XCTAssertEqual(diff.change(.imageColors).status, .reset)
        XCTAssertEqual(diff.change(.settings).status, .unchanged)
        XCTAssertTrue(diff.showsMissingSections)
        XCTAssertEqual(diff.missingSections, [.favorites, .imageColors])

        var keysOnly = rich
        keysOnly.pages[1].keys.reverse()
        XCTAssertEqual(ConfigurationDiff(current: rich, incoming: keysOnly).change(.layoutsAndKeys).lines, ["Changes keys on page Ünïcode"])
        var favoritesOnly = rich
        favoritesOnly.favorites = ["★"]
        let favorites = ConfigurationDiff(current: rich, incoming: favoritesOnly)
        XCTAssertTrue(favorites.replacesFavoritesOrKeys)
        XCTAssertFalse(favorites.changesExtraUnicodeFonts)
        XCTAssertEqual(favorites.change(.favorites).lines, ["Removes 4 favorites"])
    }

    /// Ato msg408: rules for fonts this device lacks are imported all the
    /// same; the review warns once per font and names each rule.
    func testFontWarningsNameEachMissingFontAndItsRules() throws {
        let rich = try richConfiguration()
        let bold = rich.fontRules[0].face, chalk = rich.fontRules[1].face
        XCTAssertEqual(ConfigurationFontWarning.warnings(rules: rich.fontRules, unavailable: []), [])
        XCTAssertEqual(ConfigurationFontWarning.warnings(rules: rich.fontRules, unavailable: [chalk, bold]), [
            ConfigurationFontWarning(font: ConfigurationDiff.faceName(bold), rules: ["Code point rule U+16A0", "Unicode block rule Runic"]),
            ConfigurationFontWarning(font: "Chalkduster Regular", rules: ["Range rule U+2190–U+21FF"]),
        ])
        XCTAssertEqual(ConfigurationFontWarning.warnings(rules: [], unavailable: [chalk]), [])
        XCTAssertEqual(ConfigurationFontWarning.ruleStatus, "Font unavailable")
        // The decoded rules keep every face, available or not.
        let result = try decoded(String(decoding: try XCTUnwrap(ConfigurationCodec.encode(rich)), as: UTF8.self))
        XCTAssertEqual(result.configuration.fontRules.map(\.face), [bold, chalk, bold])
    }

    func testDiffLabelHelpers() {
        XCTAssertEqual(ConfigurationDiff.preset("blackOnClear"), "Black on Transparent")
        XCTAssertEqual(ConfigurationDiff.preset("whiteOnBlack"), "White on Black")
        XCTAssertEqual(ConfigurationDiff.preset("blackOnWhite"), "Black on White")
        XCTAssertEqual(ConfigurationDiff.preset("custom"), "Custom")
        XCTAssertEqual(ConfigurationDiff.density(32), "32 per Row")
        XCTAssertEqual(ConfigurationDiff.plane(0), "Plane 0")
        XCTAssertEqual(ConfigurationDiff.keyCount(1), "1 key")
        XCTAssertEqual(ConfigurationDiff.favoriteCount(4096), "4,096 favorites")
        XCTAssertEqual(ConfigurationDiff.layoutName("zz"), "zz")
    }
}
