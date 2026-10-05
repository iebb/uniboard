import SwiftUI

struct BlocksView: View {
    var select: (UnicodeCharacter) -> Void
    @State private var query = ""
    @EnvironmentObject private var preferences: CatalogPreferences
    private var catalog: UnicodeCatalog { preferences.catalog }

    private var blocks: [UnicodeBlock] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if tokens.isEmpty { return catalog.blocks }
        return catalog.blocks.filter { block in
            tokens.allSatisfy { block.name.lowercased().contains($0) || block.rangeLabel.lowercased().contains($0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Explore the alphabet.\nAnd everything after.")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(Palette.ink)
                    Text("\(catalog.blocks.count) blocks, ordered by code point.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }.padding(.top, 6)
                SearchBar(text: $query, placeholder: "Find a block, like Arrows or Hiragana", identifier: "blockSearch")
                CatalogControls()

                LazyVStack(spacing: 10) {
                    ForEach(blocks) { block in
                        NavigationLink {
                            BlockDetailView(block: block, select: select)
                        } label: {
                            HStack(spacing: 15) {
                                Text(block.symbol)
                                    .font(Font(UnicodeFontSupport.font(for: block.symbol, size: 27, enabled: preferences.useUnicodeFonts)))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 44, height: 48)
                                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(block.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                                    Text(block.rangeLabel).font(.caption.monospaced()).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                            }
                            .padding(14)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(block.name)
                        .accessibilityValue(block.rangeLabel)
                    }
                }
                if blocks.isEmpty { EmptyCollection(symbol: "rectangle.stack", title: "No matching blocks", message: "Try a script name, such as Greek, or a symbol family, such as Arrows.") }
            }
            .padding(.horizontal, 22).padding(.bottom, 30)
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Unicode blocks")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct BlockDetailView: View {
    let block: UnicodeBlock
    var select: (UnicodeCharacter) -> Void
    @State private var characters: [UnicodeCharacter] = []
    @State private var hasMore = true
    @EnvironmentObject private var preferences: CatalogPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(block.name).font(.system(size: 33, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                    Text(block.rangeLabel).font(.subheadline.monospaced()).foregroundStyle(Palette.accent)
                    Text("Tap a character to see its name, description, and copy options.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                CatalogControls()
                CharacterGrid(characters: characters, select: select)
                if characters.isEmpty && !hasMore {
                    EmptyCollection(symbol: "square.dashed", title: "No assigned characters", message: block.name.contains("Surrogate") ? "Surrogate code points encode other characters and cannot be inserted on their own." : "This block has no assigned characters in the selected Unicode edition.")
                }
                if hasMore {
                    Button("Load more characters") { loadMore() }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(16)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("loadMoreCharacters")
                }
                Text("Some characters may need a font that supports their script. Combining marks are previewed on a dotted circle; only the mark is copied.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle(block.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if characters.isEmpty && hasMore { loadMore() } }
        .onChange(of: preferences.edition) { _, _ in reload() }
        .onChange(of: preferences.order) { _, _ in reload() }
    }

    private func loadMore() {
        let page = preferences.catalog.characters(in: block, offset: characters.count, limit: 256, order: preferences.order)
        characters += page
        hasMore = page.count == 256
    }
    private func reload() { characters = []; hasMore = true; loadMore() }
}
