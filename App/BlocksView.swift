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
        List {
            Section {
                SearchBar(text: $query, placeholder: "Block name or range", identifier: "blockSearch")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(blocks) { block in
                    NavigationLink {
                        BlockDetailView(block: block, select: select)
                    } label: {
                        let symbol = catalog.representative(of: block)
                        HStack(spacing: 12) {
                            Text(symbol)
                                .font(Font(UnicodeFontSupport.font(for: symbol, size: 22, enabled: preferences.useUnicodeFonts)))
                                .frame(width: 36, height: 36)
                                .background(UnicodeFontSupport.stockFontsMiss(symbol)
                                    ? Color.missingGlyph : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.name)
                                Text(block.rangeLabel).font(.footnote.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(block.name)
                    .accessibilityValue(block.rangeLabel)
                }
            } header: {
                Text(query.isEmpty ? "\(catalog.blocks.count) blocks" : "\(blocks.count) of \(catalog.blocks.count) blocks")
            }

            if blocks.isEmpty {
                EmptyCollection(symbol: "rectangle.stack", title: "No Matching Blocks", message: "Try a script name, such as Greek, or a symbol family, such as Arrows.")
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Blocks")
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
            VStack(alignment: .leading, spacing: 16) {
                Text(block.rangeLabel).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                CatalogControls()
                CharacterGrid(characters: characters, onReachEnd: { if hasMore { loadMore() } }, select: select)
                if characters.isEmpty && !hasMore {
                    EmptyCollection(symbol: "square.dashed", title: "No Assigned Characters", message: block.name.contains("Surrogate") ? "Surrogate code points encode other characters and cannot be inserted on their own." : "This block has no assigned characters in the selected Unicode edition.")
                }
                Text("Some characters may need a font that supports their script. Combining marks are previewed on a dotted circle; only the mark is copied.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .navigationTitle(block.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if characters.isEmpty && hasMore { loadMore() } }
        .onChange(of: preferences.edition) { _, _ in reload() }
    }

    private func loadMore() {
        let page = preferences.catalog.characters(in: block, offset: characters.count, limit: 256)
        characters += page
        hasMore = page.count == 256
    }
    private func reload() { characters = []; hasMore = true; loadMore() }
}
