import SwiftUI

struct ContentView: View {
    private enum AppTab: Hashable { case explore, emojis, blocks, saved, settings }
    @State private var selectedTab: AppTab = .explore
    @State private var settingsPresentationID = UUID()
    @AppStorage("scratchpad") private var scratchpad = ""
    @State private var selectedCharacter: UnicodeCharacter?
    @State private var selectedEmoji: UnicodeEmojiEntry?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ExploreView(scratchpad: $scratchpad, select: select, selectEmoji: selectEmoji)
            }
            .tabItem { Label("Explore", systemImage: "square.grid.2x2") }
            .tag(AppTab.explore)

            NavigationStack {
                EmojisView(scratchpad: $scratchpad, select: selectEmoji)
            }
            .tabItem { Label("Emoji", systemImage: "face.smiling") }
            .tag(AppTab.emojis)

            NavigationStack { BlocksView(select: select) }
                .tabItem { Label("Blocks", systemImage: "rectangle.stack") }
                .tag(AppTab.blocks)

            NavigationStack { SavedView(select: select, scratchpad: $scratchpad) }
                .tabItem { Label("Saved", systemImage: "star") }
                .tag(AppTab.saved)

            NavigationStack { SetupView() }
                .id(settingsPresentationID)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onOpenURL { url in
            guard CompanionAppRoute.isSettings(url) else { return }
            selectedCharacter = nil
            selectedEmoji = nil
            settingsPresentationID = UUID()
            selectedTab = .settings
        }
        .sheet(item: $selectedCharacter) { character in
            CharacterDetailView(character: character, scratchpad: $scratchpad)
        }
        .sheet(item: $selectedEmoji) { emoji in
            EmojiDetailView(emoji: emoji, scratchpad: $scratchpad)
        }
    }

    private func select(_ character: UnicodeCharacter) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        selectedCharacter = character
    }

    private func selectEmoji(_ emoji: UnicodeEmojiEntry) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        selectedEmoji = emoji
    }
}

@MainActor
final class CatalogSearch: ObservableObject {
    @Published var results: [UnicodeCharacter] = []
    @Published var searching = false
    private var task: Task<Void, Never>?

    func update(_ query: String, catalog: UnicodeCatalog, limit: Int = 240) {
        task?.cancel()
        results = []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            searching = false
            return
        }
        searching = true
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard !Task.isCancelled else { return }
            let matches = await CatalogWorker.run {
                catalog.search(query, limit: limit)
            }
            guard !Task.isCancelled, let self else { return }
            self.results = matches
            self.searching = false
        }
    }

    deinit { task?.cancel() }
}

struct ExploreView: View {
    @Binding var scratchpad: String
    var select: (UnicodeCharacter) -> Void
    var selectEmoji: (UnicodeEmojiEntry) -> Void
    @State private var query = ""
    @State private var pages = 1
    @AppStorage("exploreGridDensity") private var density: GridDensity = .three
    @State private var showScratchpad = false
    @State private var showNavigator = false
    @State private var openedBlock: UnicodeBlock?
    /// A block chosen in the navigator, jumped to once the sheet has closed
    /// and the chart's layout has settled.
    @State private var pendingJump: UInt32?
    @State private var contentWidth: CGFloat = 0
    @State private var chart = CodeChartController()
    @StateObject private var search = CatalogSearch()
    @EnvironmentObject private var preferences: CatalogPreferences
    private var catalog: UnicodeCatalog { preferences.catalog }
    /// 8 and 16 per row form a code chart of every block, in code-point order.
    private var usesChart: Bool { query.isEmpty && density != .three }
    private var displayedCharacters: [UnicodeCharacter] {
        catalog.orderedCharacters(limit: pages * density.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The search field stays put, so typing never rebuilds it.
            VStack(alignment: .leading, spacing: 12) {
                SearchBar(text: $query, placeholder: "Names, blocks or U+ codes")
                HStack {
                    CatalogControls()
                    Spacer()
                    NavigationLink {
                        NewInEditionView(select: select, selectEmoji: selectEmoji)
                    } label: {
                        Label("What’s New", systemImage: "sparkles").font(.subheadline)
                    }
                    .accessibilityIdentifier("exploreWhatsNew")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 780)

            if usesChart {
                CodeChartView(catalog: catalog, density: density, controller: chart,
                              navigate: { showNavigator = true }, select: select)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if query.isEmpty {
                            CharacterGrid(characters: displayedCharacters, density: density, width: contentWidth,
                                          onReachEnd: loadNextPage, select: select)
                        } else {
                            HStack {
                                SectionLabel(title: "Results", trailing: search.searching ? nil : "\(search.results.count)\(search.results.count == 240 ? "+" : "") characters")
                                if search.searching { ProgressView().controlSize(.small) }
                            }
                            .padding(.bottom, 12)
                            if !search.searching && search.results.isEmpty {
                                EmptyCollection(symbol: "magnifyingglass", title: "No Results", message: "Try another name or description, a literal character, or a code point such as U+1F680.")
                            } else {
                                CharacterGrid(characters: search.results, density: density, width: contentWidth, select: select)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 780)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { contentWidth = $0 }
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("exploreResults")
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.groupedBackground)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedBlock) { BlockDetailView(block: $0, select: select) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNavigator = true } label: { Image(systemName: "list.bullet.indent") }
                    .accessibilityLabel("Jump to block")
                    .accessibilityIdentifier("exploreBlockNavigator")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Characters per Row", selection: $density) {
                        ForEach(GridDensity.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: { Image(systemName: density.symbol) }
                .accessibilityLabel("Characters per row")
                .accessibilityValue("\(density.rawValue)")
                .accessibilityIdentifier("exploreDensity")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScratchpad = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Open scratchpad")
                    .accessibilityIdentifier("openScratchpad")
            }
        }
        .sheet(isPresented: $showNavigator, onDismiss: {
            if let block = pendingJump { chart.jump(to: block) }
            pendingJump = nil
        }) {
            BlockNavigator(blocks: catalog.blocks, current: usesChart ? chart.topBlock : nil) { block in
                if usesChart { pendingJump = block.start } else { openedBlock = block }
            }
        }
        .onChange(of: density) { _, _ in pages = 1 }
        .onChange(of: query) { _, value in search.update(value, catalog: catalog) }
        .onChange(of: preferences.edition) { _, _ in
            pages = 1
            search.update(query, catalog: catalog)
        }
        .sheet(isPresented: $showScratchpad) { ScratchpadView(text: $scratchpad) }
    }

    private func loadNextPage() {
        if displayedCharacters.count >= pages * density.pageSize { pages += 1 }
    }
}
