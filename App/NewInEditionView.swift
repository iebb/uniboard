import SwiftUI

/// What the selected Unicode edition adds over the previous one.
struct NewInEditionView: View {
    var select: (UnicodeCharacter) -> Void
    var selectEmoji: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var preferences: CatalogPreferences
    @AppStorage("exploreGridDensity") private var density: GridDensity = .three
    @State private var chart = CodeChartController()
    @State private var pages = 1
    @State private var contentWidth: CGFloat = 0
    private var catalog: UnicodeCatalog { preferences.catalog }

    var body: some View {
        let emoji = preferences.emojis.addedEntries
        let count = catalog.addedCount
        Group {
            if density == .three || count == 0 {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        summary(emoji: emoji, count: count)
                        if count == 0 {
                            EmptyCollection(symbol: "sparkles", title: "Nothing New Yet",
                                            message: "This edition doesn’t add any characters over the previous one so far.")
                        } else {
                            let characters = catalog.addedCharacters(limit: pages * density.pageSize)
                            CharacterGrid(characters: characters, density: density, width: contentWidth,
                                          onReachEnd: { if characters.count >= pages * density.pageSize { pages += 1 } },
                                          select: select)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 780)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { contentWidth = $0 }
                    .frame(maxWidth: .infinity)
                }
            } else {
                CodeChartView(catalog: catalog, density: density, addedOnly: true, controller: chart,
                              leading: AnyView(summary(emoji: emoji, count: count)), select: select)
            }
        }
        .background(Color.groupedBackground)
        .navigationTitle("New in \(preferences.edition.title)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: density) { _, _ in pages = 1 }
        .onChange(of: preferences.edition) { _, _ in pages = 1 }
    }

    /// New emoji, then the heading for the new characters below them.
    private func summary(emoji: [UnicodeEmojiEntry], count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !emoji.isEmpty {
                SectionLabel(title: "Emoji", trailing: emoji.count.formatted())
                EmojiGrid(entries: emoji, select: selectEmoji).padding(.bottom, 12)
            }
            SectionLabel(title: "Characters", trailing: count.formatted())
        }
        .padding(.bottom, 12)
    }
}
