import SwiftUI

@MainActor
final class CatalogPreferences: ObservableObject {
    static let shared = CatalogPreferences()
    @Published private(set) var edition: UnicodeEdition
    @Published private(set) var editionSaveError: String?
    @Published private(set) var useUnicodeFonts: Bool
    @Published private(set) var showsCollapseKey: Bool
    /// The retired Top Row and Number Row choices, kept as stored so a save
    /// writes them back unchanged for an earlier version. Nothing reads them.
    private var retired: (showsSymbolBar: Bool, searchBarInsteadOfSymbols: Bool, showsNumberRow: Bool)
    @Published private(set) var showsTextPreview: Bool
    @Published private(set) var showsUCSUR: Bool
    @Published private(set) var prefersUCSUR: Bool
    @Published private(set) var layouts: [String]
    @Published private(set) var padLayout: KeyboardPadLayout
    @Published private(set) var padSymbolMapping: KeyboardPadSymbolMapping
    /// When letter keys use capitals automatically; Follow App by default.
    @Published private(set) var autoCapitalization: AutoCapitalizationMode
    @Published private(set) var autoCapitalizationSaveError: String?
    private let autoCapitalizationSetting: AutoCapitalizationSetting
    private let editionSettings: UnicodeEditionSettings
    private let fontRules: FontRuleStore?

    /// `fontRules` nil leaves the rules previews use unchanged.
    init(editionSettings: UnicodeEditionSettings = .shared, fontRules: FontRuleStore? = .shared,
         autoCapitalization: AutoCapitalizationSetting = .shared) {
        self.editionSettings = editionSettings
        autoCapitalizationSetting = autoCapitalization
        self.autoCapitalization = autoCapitalization.load()
        self.fontRules = fontRules
        let snapshot = editionSettings.loadSnapshot()
        edition = snapshot.edition
        useUnicodeFonts = snapshot.useUnicodeFonts
        showsCollapseKey = snapshot.showsCollapseKey
        retired = (snapshot.showsSymbolBar, snapshot.searchBarInsteadOfSymbols, snapshot.showsNumberRow)
        showsTextPreview = snapshot.showsTextPreview
        showsUCSUR = snapshot.showsUCSUR
        prefersUCSUR = snapshot.prefersUCSUR
        UnicodeFontSupport.prefersConScript = snapshot.showsUCSUR && snapshot.prefersUCSUR
        layouts = snapshot.layouts
        padLayout = snapshot.padLayout
        padSymbolMapping = snapshot.padSymbolMapping
        // Extra Unicode Fonts is the master switch: off pauses rules, never deletes them.
        UnicodeFontSupport.rulesEnabled = snapshot.useUnicodeFonts
        reloadFontRules()
    }
    /// Reads the saved font rules again (validated against the base Unicode
    /// block table) and redraws every preview when they changed.
    func reloadFontRules() {
        guard let fontRules else { return }
        let rules = fontRules.load(blocks: UnicodeCatalog.shared.blocks) ?? []
        guard rules != UnicodeFontSupport.ruleSet.rules else { return }
        UnicodeFontSupport.ruleSet = FontRuleSet(rules: rules)
        objectWillChange.send()
    }
    /// With ConScript preferred, Private Use reads as the registry assigns it.
    var catalog: UnicodeCatalog {
        !showsUCSUR ? edition.catalog : prefersUCSUR ? edition.catalog.withConScript() : edition.catalog.withConScriptSearch()
    }
    var emojis: EmojiCatalog { edition.emojiCatalog }
    func selectEdition(_ selection: UnicodeEdition) {
        edit { $0.edition = selection }
    }
    func selectUnicodeFonts(_ enabled: Bool) {
        edit { $0.useUnicodeFonts = enabled }
    }
    /// Redraws every preview after downloaded fonts are installed or removed.
    func fontFilesChanged() {
        UnicodeFontSupport.refreshDownloadedFonts(force: true)
        objectWillChange.send()
    }
    func selectCollapseKey(_ enabled: Bool) {
        edit { $0.showsCollapseKey = enabled }
    }
    func selectTextPreview(_ enabled: Bool) { edit { $0.showsTextPreview = enabled } }
    func selectUCSUR(_ enabled: Bool) { edit { $0.showsUCSUR = enabled } }
    func selectPrefersUCSUR(_ enabled: Bool) { edit { $0.prefersUCSUR = enabled } }
    /// True for a ConScript Private Use character while that option is on.
    func isUCSUR(_ codePoint: UInt32) -> Bool { showsUCSUR && UCSUR.block(containing: codePoint) != nil }
    /// The keyboard's base layouts in switching order. False when the list is
    /// empty, too long, repeats a layout or could not be saved.
    @discardableResult func selectLayouts(_ ids: [String]) -> Bool {
        guard UnicodeEditionSettings.layouts(ids) == ids else { return false }
        edit { $0.layouts = ids }
        return layouts == ids
    }
    var alphabets: [KeyboardAlphabet] { layouts.compactMap(KeyboardAlphabet.alphabet(id:)) }
    func selectPadLayout(_ layout: KeyboardPadLayout) { edit { $0.padLayout = layout } }
    private func edit(_ change: (inout UnicodeEditionSettings.Snapshot) -> Void) {
        var value = UnicodeEditionSettings.Snapshot(edition: edition, useUnicodeFonts: useUnicodeFonts,
            showsCollapseKey: showsCollapseKey, showsSymbolBar: retired.showsSymbolBar,
            searchBarInsteadOfSymbols: retired.searchBarInsteadOfSymbols,
            showsNumberRow: retired.showsNumberRow, layouts: layouts, showsTextPreview: showsTextPreview, showsUCSUR: showsUCSUR,
            prefersUCSUR: prefersUCSUR,
            padLayout: padLayout, padSymbolMapping: padSymbolMapping)
        change(&value)
        save(value)
    }
    private func save(_ snapshot: UnicodeEditionSettings.Snapshot) {
        guard editionSettings.save(snapshot) else {
            editionSaveError = "Couldn’t save these keyboard settings. Please try again."
            return
        }
        apply(snapshot)
        editionSaveError = nil
    }
    private func apply(_ snapshot: UnicodeEditionSettings.Snapshot) {
        if edition != snapshot.edition { edition = snapshot.edition }
        if useUnicodeFonts != snapshot.useUnicodeFonts {
            useUnicodeFonts = snapshot.useUnicodeFonts
            if !useUnicodeFonts { UnicodeFontSupport.clearCache() }
        }
        UnicodeFontSupport.rulesEnabled = useUnicodeFonts
        if showsCollapseKey != snapshot.showsCollapseKey { showsCollapseKey = snapshot.showsCollapseKey }
        retired = (snapshot.showsSymbolBar, snapshot.searchBarInsteadOfSymbols, snapshot.showsNumberRow)
        if showsTextPreview != snapshot.showsTextPreview { showsTextPreview = snapshot.showsTextPreview }
        if showsUCSUR != snapshot.showsUCSUR { showsUCSUR = snapshot.showsUCSUR }
        if prefersUCSUR != snapshot.prefersUCSUR { prefersUCSUR = snapshot.prefersUCSUR }
        UnicodeFontSupport.prefersConScript = showsUCSUR && prefersUCSUR
        if layouts != snapshot.layouts { layouts = snapshot.layouts }
        if padLayout != snapshot.padLayout { padLayout = snapshot.padLayout }
        if padSymbolMapping != snapshot.padSymbolMapping { padSymbolMapping = snapshot.padSymbolMapping }
    }
    func refreshEdition() {
        apply(editionSettings.loadSnapshot())
        reloadFontRules()
        let mode = autoCapitalizationSetting.load()
        if autoCapitalization != mode { autoCapitalization = mode }
    }
    /// Saves at once; the keyboard reads it the next time it appears.
    func selectAutoCapitalization(_ mode: AutoCapitalizationMode) {
        guard autoCapitalizationSetting.save(mode) else {
            autoCapitalizationSaveError = "Couldn’t save these keyboard settings. Please try again."
            return
        }
        autoCapitalizationSaveError = nil
        if autoCapitalization != mode { autoCapitalization = mode }
    }
    func reset(preservingEdition: Bool = false) {
        // UI-test launches preserve the complete shared snapshot so opening
        // the host cannot undo an app setting that the keyboard must read.
        if !preservingEdition { save(.init(edition: .latest)) }
    }
}


/// The edition selector in the app's Settings tab.
struct CatalogEditionPicker: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var body: some View {
        Picker("Version", selection: Binding(get: { preferences.edition }, set: { preferences.selectEdition($0) })) {
            // Newest first: the draft, then each final release.
            ForEach([UnicodeEdition.draft, .latest, .previous, .older]) { edition in
                Text(edition.title).tag(edition)
                    .accessibilityIdentifier("edition.\(edition.rawValue)")
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("unicodeEdition")
        .accessibilityLabel("Unicode version")
        .accessibilityValue(preferences.edition.rawValue)
    }
}

/// The selected edition, shown where characters are browsed, and a menu
/// that switches it. Characters are always listed from the lowest code point.
struct CatalogControls: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var body: some View {
        Menu {
            Picker("Version", selection: Binding(get: { preferences.edition }, set: { preferences.selectEdition($0) })) {
                ForEach([UnicodeEdition.draft, .latest, .previous, .older]) { edition in
                    Text(edition.title).tag(edition)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(preferences.edition.title)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Unicode version")
        .accessibilityIdentifier("unicodeEdition.current")
        .accessibilityValue(preferences.edition.rawValue)
    }
}
