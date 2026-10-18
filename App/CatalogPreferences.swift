import SwiftUI

@MainActor
final class CatalogPreferences: ObservableObject {
    static let shared = CatalogPreferences()
    @Published private(set) var edition: UnicodeEdition
    @Published private(set) var editionSaveError: String?
    @Published var order: UnicodeSortOrder {
        didSet { defaults.set(order.rawValue, forKey: "appUnicodeSort") }
    }
    @Published private(set) var useUnicodeFonts: Bool
    @Published private(set) var showsCollapseKey: Bool
    private let defaults: UserDefaults
    private let editionSettings: UnicodeEditionSettings

    init(defaults: UserDefaults = .standard, editionSettings: UnicodeEditionSettings = .shared) {
        self.defaults = defaults
        self.editionSettings = editionSettings
        let snapshot = editionSettings.loadSnapshot()
        edition = snapshot.edition
        order = defaults.string(forKey: "appUnicodeSort").flatMap(UnicodeSortOrder.init(rawValue:)) ?? .codePoint
        useUnicodeFonts = snapshot.useUnicodeFonts
        showsCollapseKey = snapshot.showsCollapseKey
    }
    var catalog: UnicodeCatalog { edition.catalog }
    var emojis: EmojiCatalog { edition.emojiCatalog }
    func selectEdition(_ selection: UnicodeEdition) {
        save(.init(edition: selection, useUnicodeFonts: useUnicodeFonts, showsCollapseKey: showsCollapseKey))
    }
    func selectUnicodeFonts(_ enabled: Bool) {
        save(.init(edition: edition, useUnicodeFonts: enabled, showsCollapseKey: showsCollapseKey))
    }
    func selectCollapseKey(_ enabled: Bool) {
        save(.init(edition: edition, useUnicodeFonts: useUnicodeFonts, showsCollapseKey: enabled))
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
    }
    func refreshEdition() {
        apply(editionSettings.loadSnapshot())
    }
    func reset(preservingEdition: Bool = false) {
        // UI-test launches preserve the complete shared snapshot so opening
        // the host cannot undo an app setting that the keyboard must read.
        if !preservingEdition { save(.init(edition: .latest)) }
        order = .codePoint
    }
}

/// The only edition selector lives in the app's Settings tab.
struct CatalogEditionPicker: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var body: some View {
        Menu {
            ForEach(UnicodeEdition.allCases) { edition in
                Button { preferences.selectEdition(edition) } label: {
                    Label(edition.title, systemImage: preferences.edition == edition ? "checkmark" : "circle")
                }
                .accessibilityIdentifier("edition.\(edition.rawValue)")
            }
        } label: {
            HStack {
                Label(preferences.edition.title, systemImage: "books.vertical")
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
        }
        .accessibilityIdentifier("unicodeEdition")
        .accessibilityLabel("Unicode version")
        .accessibilityValue(preferences.edition.rawValue)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.accent)
    }
}

struct CatalogControls: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var showSort = true
    var body: some View {
        HStack(spacing: 12) {
            Label(preferences.edition.title, systemImage: "books.vertical")
                .accessibilityIdentifier("unicodeEdition.current")
                .accessibilityValue(preferences.edition.rawValue)
            Spacer(minLength: 0)
            if showSort {
                Menu {
                    ForEach(UnicodeSortOrder.allCases) { order in
                        Button { preferences.order = order } label: {
                            Label(order.title, systemImage: preferences.order == order ? "checkmark" : "circle")
                        }
                        .accessibilityIdentifier("sort.\(order.rawValue)")
                    }
                } label: {
                    Label {
                        Text(preferences.order.title)
                            .accessibilityIdentifier("unicodeSort.current")
                            .accessibilityValue(preferences.order.rawValue)
                    } icon: { Image(systemName: "arrow.up.arrow.down") }
                }
                .accessibilityIdentifier("unicodeSort")
                .accessibilityLabel("Sort characters")
                .accessibilityValue(preferences.order.rawValue)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.accent)
        .padding(.vertical, 8)
    }
}
