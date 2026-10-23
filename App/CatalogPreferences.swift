import SwiftUI

@MainActor
final class CatalogPreferences: ObservableObject {
    static let shared = CatalogPreferences()
    @Published private(set) var edition: UnicodeEdition
    @Published private(set) var editionSaveError: String?
    @Published private(set) var useUnicodeFonts: Bool
    @Published private(set) var showsCollapseKey: Bool
    @Published private(set) var showsSymbolBar: Bool
    @Published private(set) var searchBarInsteadOfSymbols: Bool
    @Published private(set) var showsNumberRow: Bool
    @Published private(set) var showsTextPreview: Bool
    @Published private(set) var showsUCSUR: Bool
    @Published private(set) var prefersUCSUR: Bool
    @Published private(set) var layouts: [String]
    @Published private(set) var padLayout: KeyboardPadLayout
    @Published private(set) var padSymbolMapping: KeyboardPadSymbolMapping
    private let editionSettings: UnicodeEditionSettings

    init(editionSettings: UnicodeEditionSettings = .shared) {
        self.editionSettings = editionSettings
        let snapshot = editionSettings.loadSnapshot()
        edition = snapshot.edition
        useUnicodeFonts = snapshot.useUnicodeFonts
        showsCollapseKey = snapshot.showsCollapseKey
        showsSymbolBar = snapshot.showsSymbolBar
        searchBarInsteadOfSymbols = snapshot.searchBarInsteadOfSymbols
        showsNumberRow = snapshot.showsNumberRow
        showsTextPreview = snapshot.showsTextPreview
        showsUCSUR = snapshot.showsUCSUR
        prefersUCSUR = snapshot.prefersUCSUR
        UnicodeFontSupport.prefersConScript = snapshot.showsUCSUR && snapshot.prefersUCSUR
        layouts = snapshot.layouts
        padLayout = snapshot.padLayout
        padSymbolMapping = snapshot.padSymbolMapping
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
    func selectSymbolBar(_ enabled: Bool) { edit { $0.showsSymbolBar = enabled } }
    func selectSearchBarInsteadOfSymbols(_ enabled: Bool) { edit { $0.searchBarInsteadOfSymbols = enabled } }
    func selectNumberRow(_ enabled: Bool) { edit { $0.showsNumberRow = enabled } }
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
    /// The keyboard's optional row above the keys, as one choice.
    var topRow: KeyboardTopRow {
        guard showsSymbolBar else { return .off }
        return searchBarInsteadOfSymbols ? .search : .symbols
    }
    func selectTopRow(_ row: KeyboardTopRow) {
        edit {
            $0.showsSymbolBar = row != .off
            if row != .off { $0.searchBarInsteadOfSymbols = row == .search }
        }
    }
    func selectPadLayout(_ layout: KeyboardPadLayout) { edit { $0.padLayout = layout } }
    private func edit(_ change: (inout UnicodeEditionSettings.Snapshot) -> Void) {
        var value = UnicodeEditionSettings.Snapshot(edition: edition, useUnicodeFonts: useUnicodeFonts,
            showsCollapseKey: showsCollapseKey, showsSymbolBar: showsSymbolBar, searchBarInsteadOfSymbols: searchBarInsteadOfSymbols,
            showsNumberRow: showsNumberRow, layouts: layouts, showsTextPreview: showsTextPreview, showsUCSUR: showsUCSUR,
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
        if showsCollapseKey != snapshot.showsCollapseKey { showsCollapseKey = snapshot.showsCollapseKey }
        if showsSymbolBar != snapshot.showsSymbolBar { showsSymbolBar = snapshot.showsSymbolBar }
        if searchBarInsteadOfSymbols != snapshot.searchBarInsteadOfSymbols { searchBarInsteadOfSymbols = snapshot.searchBarInsteadOfSymbols }
        if showsNumberRow != snapshot.showsNumberRow { showsNumberRow = snapshot.showsNumberRow }
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
    }
    func reset(preservingEdition: Bool = false) {
        // UI-test launches preserve the complete shared snapshot so opening
        // the host cannot undo an app setting that the keyboard must read.
        if !preservingEdition { save(.init(edition: .latest)) }
    }
}

enum KeyboardTopRow: String, CaseIterable {
    case off, symbols, search
    var title: String {
        switch self {
        case .off: return "Off"
        case .symbols: return "Symbols"
        case .search: return "Search"
        }
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
