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
        padLayout = snapshot.padLayout
        padSymbolMapping = snapshot.padSymbolMapping
    }
    var catalog: UnicodeCatalog { edition.catalog }
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
            showsNumberRow: showsNumberRow, padLayout: padLayout, padSymbolMapping: padSymbolMapping)
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

/// The only edition selector lives in the app's Settings tab.
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

/// The selected edition, shown where characters are listed. Characters are
/// always listed from the lowest code point.
struct CatalogControls: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var body: some View {
        Text(preferences.edition.title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("unicodeEdition.current")
            .accessibilityValue(preferences.edition.rawValue)
    }
}
