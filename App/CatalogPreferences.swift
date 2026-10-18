import SwiftUI

@MainActor
final class CatalogPreferences: ObservableObject {
    static let shared = CatalogPreferences()
    @Published var edition: UnicodeEdition {
        didSet { defaults.set(edition.rawValue, forKey: "appUnicodeEdition") }
    }
    @Published var order: UnicodeSortOrder {
        didSet { defaults.set(order.rawValue, forKey: "appUnicodeSort") }
    }
    @Published var useUnicodeFonts: Bool {
        didSet {
            defaults.set(useUnicodeFonts, forKey: "appUnicodeFonts")
            if !useUnicodeFonts { UnicodeFontSupport.clearCache() }
        }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edition = defaults.string(forKey: "appUnicodeEdition").flatMap(UnicodeEdition.init(rawValue:)) ?? .draft
        order = defaults.string(forKey: "appUnicodeSort").flatMap(UnicodeSortOrder.init(rawValue:)) ?? .newestFirst
        useUnicodeFonts = LocalPreferencePolicy.boolean(forKey: "appUnicodeFonts", in: defaults)
    }
    var catalog: UnicodeCatalog { edition.catalog }
    var emojis: EmojiCatalog { edition.emojiCatalog }
    func reset() { edition = .draft; order = .newestFirst; useUnicodeFonts = false }
}

struct CatalogControls: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    var showSort = true
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(UnicodeEdition.allCases) { edition in
                    Button { preferences.edition = edition } label: {
                        Label(edition.title, systemImage: preferences.edition == edition ? "checkmark" : "circle")
                    }
                    .accessibilityIdentifier("edition.\(edition.rawValue)")
                }
            } label: {
                Label {
                    Text(preferences.edition.title)
                        .accessibilityIdentifier("unicodeEdition.current")
                        .accessibilityValue(preferences.edition.rawValue)
                } icon: { Image(systemName: "books.vertical") }
            }
            .accessibilityIdentifier("unicodeEdition")
            .accessibilityLabel("Unicode version")
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
