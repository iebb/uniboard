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
    var select: (UnicodeCharacter) -> Void
    /// The block on show; the navigator at the top switches it.
    @State private var block: UnicodeBlock
    @State private var characters: [UnicodeCharacter] = []
    @State private var hasMore = true
    @State private var showNavigator = false
    /// Tiles, or this block as a code chart; wide screens add 32 per row.
    @AppStorage("blockGridDensity") private var density: GridDensity = .three
    @State private var width: CGFloat = 0
    @State private var chart = CodeChartController()
    @EnvironmentObject private var preferences: CatalogPreferences
    private var shown: GridDensity { density.fitting(width) }

    init(block: UnicodeBlock, select: @escaping (UnicodeCharacter) -> Void) {
        _block = State(initialValue: block)
        self.select = select
    }

    var body: some View {
        Group {
            if shown == .three {
                tiles
            } else {
                // The chart's pinned header names the block and opens the navigator.
                CodeChartView(catalog: preferences.catalog, density: shown, controller: chart,
                              navigate: { _ in showNavigator = true }, only: block.start, select: select)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Color.groupedBackground)
        .navigationTitle(block.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Characters per Row", selection: $density) {
                        ForEach(GridDensity.offered(width: width)) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: { Image(systemName: shown.symbol) }
                .accessibilityLabel("View options")
                .accessibilityValue("\(shown.rawValue)")
                .accessibilityIdentifier("blockDensity")
            }
        }
        .onAppear { if characters.isEmpty && hasMore { loadMore() } }
        .onChange(of: preferences.edition) { _, _ in reload() }
        // Preferring ConScript renames its characters.
        .onChange(of: preferences.catalog.usesConScript) { _, _ in reload() }
        .sheet(isPresented: $showNavigator) {
            BlockNavigator(blocks: preferences.catalog.blocks, current: block.start) { chosen in
                block = chosen
                reload()
            }
        }
    }

    private var tiles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { showNavigator = true } label: {
                    HStack(spacing: 6) {
                        Text(block.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        Spacer(minLength: 8)
                        Text(block.rangeLabel).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(block.name), \(block.rangeLabel)")
                .accessibilityHint("Jump to another block")
                .accessibilityIdentifier("blockNavigator")
                CatalogControls()
                CharacterGrid(characters: characters, onReachEnd: { if hasMore { loadMore() } }, select: select)
                if characters.isEmpty && !hasMore {
                    EmptyCollection(symbol: "square.dashed", title: "No Assigned Characters", message: block.name.contains("Surrogate") ? "Surrogate code points encode other characters and cannot be inserted on their own." : "This block has no assigned characters in the selected Unicode edition.")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
    }

    private func loadMore() {
        let page = preferences.catalog.characters(in: block, offset: characters.count, limit: 256)
        characters += page
        hasMore = page.count == 256
    }
    private func reload() { characters = []; hasMore = true; loadMore() }
}
