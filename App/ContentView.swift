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
                ExploreView(scratchpad: $scratchpad, select: select)
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
    @State private var query = ""
    @State private var pages = 1
    @State private var showScratchpad = false
    @StateObject private var search = CatalogSearch()
    @EnvironmentObject private var preferences: CatalogPreferences
    private static let pageSize = 160
    private var catalog: UnicodeCatalog { preferences.catalog }
    private var displayedCharacters: [UnicodeCharacter] {
        catalog.orderedCharacters(limit: pages * Self.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The search field stays put, so typing never rebuilds it.
            VStack(alignment: .leading, spacing: 12) {
                SearchBar(text: $query, placeholder: "Names, blocks or U+ codes")
                CatalogControls()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 780)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        CharacterGrid(characters: displayedCharacters, onReachEnd: loadNextPage, select: select)
                    } else {
                        HStack {
                            SectionLabel(title: "Results", trailing: search.searching ? nil : "\(search.results.count)\(search.results.count == 240 ? "+" : "") characters")
                            if search.searching { ProgressView().controlSize(.small) }
                        }
                        .padding(.bottom, 12)
                        if !search.searching && search.results.isEmpty {
                            EmptyCollection(symbol: "magnifyingglass", title: "No Results", message: "Try another name or description, a literal character, or a code point such as U+1F680.")
                        } else {
                            CharacterGrid(characters: search.results, select: select)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("exploreResults")
        }
        .frame(maxWidth: .infinity)
        .background(Color.groupedBackground)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScratchpad = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Open scratchpad")
                    .accessibilityIdentifier("openScratchpad")
            }
        }
        .onChange(of: query) { _, value in search.update(value, catalog: catalog) }
        .onChange(of: preferences.edition) { _, _ in
            pages = 1
            search.update(query, catalog: catalog)
        }
        .sheet(isPresented: $showScratchpad) { ScratchpadView(text: $scratchpad) }
    }

    private func loadNextPage() {
        if displayedCharacters.count >= pages * Self.pageSize { pages += 1 }
    }
}
