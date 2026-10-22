import SwiftUI

struct ContentView: View {
    private enum AppTab: Hashable { case explore, emojis, blocks, pages, settings }
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

            NavigationStack { PagesView(select: select, scratchpad: $scratchpad) }
                .tabItem { Label("Pages", systemImage: "star") }
                .tag(AppTab.pages)

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
    /// A plane number, or -1 for every plane.
    @AppStorage("explorePlane") private var plane = -1
    @AppStorage("exploreShowsPrivateUse") private var showsPrivateUse = false
    /// Highest code point first.
    @AppStorage("exploreDescending") private var descending = false
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
    private var scope: ExploreScope {
        let selected = plane >= 0 && (showsPrivateUse || !ExploreScope.privateUsePlanes.contains(plane)) ? plane : nil
        return ExploreScope(plane: selected, showsPrivateUse: showsPrivateUse)
    }
    private var displayedCharacters: [UnicodeCharacter] {
        catalog.orderedCharacters(in: scope.range, limit: pages * density.pageSize, descending: descending)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The search field stays put, so typing never rebuilds it.
            VStack(alignment: .leading, spacing: 12) {
                // Search from the edit itself rather than a later view update:
                // SwiftUI coalesces fast keystrokes and can skip the last one.
                SearchBar(text: Binding(get: { query }, set: { value in
                    query = value
                    search.update(value, catalog: catalog)
                }), placeholder: "Names, blocks or U+ codes")
                HStack {
                    if let plane = scope.plane {
                        Text(ExploreScope.name(of: plane)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        CatalogControls()
                    }
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
                CodeChartView(catalog: catalog, density: density, scope: scope, controller: chart,
                              navigate: { openedBlock = $0 }, descending: descending, select: select)
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
                    Picker("Order", selection: $descending) {
                        Label("Low to High", systemImage: "arrow.down").tag(false)
                        Label("High to Low", systemImage: "arrow.up").tag(true)
                    }
                    Picker("Plane", selection: $plane) {
                        Text("All Planes").tag(-1)
                        ForEach(ExploreScope.planes(in: catalog, showsPrivateUse: showsPrivateUse), id: \.self) { number in
                            Text("\(number) · \(ExploreScope.name(of: number))").tag(number)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Show Supplementary Private Use", isOn: $showsPrivateUse)
                } label: { Image(systemName: density.symbol) }
                .accessibilityLabel("View options")
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
            BlockNavigator(blocks: catalog.blocks.filter(scope.includes), current: usesChart ? chart.topBlock : nil) { block in
                if usesChart { pendingJump = block.start } else { openedBlock = block }
            }
        }
        .onChange(of: density) { _, _ in pages = 1 }
        .onChange(of: descending) { _, _ in pages = 1 }
        .onChange(of: scope) { _, _ in pages = 1 }
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
