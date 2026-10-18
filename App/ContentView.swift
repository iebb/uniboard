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
            .tabItem { Label("Emojis", systemImage: "face.smiling") }
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

    func update(_ query: String, catalog: UnicodeCatalog, order: UnicodeSortOrder, limit: Int = 240) {
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
                catalog.search(query, limit: limit, order: order)
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
    @State private var collection: DiscoveryCollection = .all
    @State private var pageLimit = 160
    @State private var showScratchpad = false
    @StateObject private var search = CatalogSearch()
    @EnvironmentObject private var preferences: CatalogPreferences
    private var catalog: UnicodeCatalog { preferences.catalog }
    private var displayedCharacters: [UnicodeCharacter] {
        if collection == .all {
            return catalog.orderedCharacters(limit: pageLimit, order: preferences.order)
        }
        return collection.characters(in: catalog).sorted {
            switch preferences.order {
            case .newestFirst: return $0.versionSortKey == $1.versionSortKey ? $0.codePoint < $1.codePoint : $0.versionSortKey > $1.versionSortKey
            case .oldestFirst: return $0.versionSortKey == $1.versionSortKey ? $0.codePoint < $1.codePoint : $0.versionSortKey < $1.versionSortKey
            case .codePoint: return $0.codePoint < $1.codePoint
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "character.cursor.ibeam").font(.title3)
                        Text("uniboard").font(.system(size: 21, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Palette.ink)
                    Spacer()
                    Button { showScratchpad = true } label: {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(Palette.soft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Open scratchpad")
                    .accessibilityIdentifier("openScratchpad")
                    Text("UNICODE \(catalog.version)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Palette.soft, in: Capsule())
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("A world of\ncharacters.")
                        .font(.system(size: 43, weight: .regular, design: .serif))
                        .tracking(-1.5)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Find the perfect symbol, letter, or little detail.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }

                VStack(alignment: .leading, spacing: 9) {
                    SearchBar(text: $query, placeholder: "Search names, blocks, or U+ codes")
                    if query.isEmpty {
                        Text("Try “arrow”, “Hiragana”, or “U+2665”")
                            .font(.caption).foregroundStyle(Palette.muted).padding(.leading, 3)
                    }
                }
                CatalogControls()

                if query.isEmpty {
                    collections
                    SectionLabel(title: collection.title, trailing: "HOLD FOR DETAILS")
                    CharacterGrid(characters: displayedCharacters, select: select)
                    if collection == .all {
                        Button("Load more characters") { pageLimit += 160 }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(16)
                            .background(Palette.soft, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("loadMoreExplore")
                    }
                    scratchpadCard
                    browseCard
                } else {
                    HStack {
                        SectionLabel(title: "Search results", trailing: search.searching ? "SEARCHING" : "\(search.results.count)\(search.results.count == 240 ? "+" : "") CHARACTERS")
                        if search.searching { ProgressView().controlSize(.small) }
                    }
                    if !search.searching && search.results.isEmpty {
                        EmptyCollection(symbol: "magnifyingglass", title: "No characters found", message: "Try another name or description, a literal character, or a code point such as U+1F680.")
                    } else {
                        CharacterGrid(characters: search.results, select: select)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, value in search.update(value, catalog: catalog, order: preferences.order) }
        .onChange(of: preferences.edition) { _, _ in
            pageLimit = 160
            search.update(query, catalog: catalog, order: preferences.order)
        }
        .onChange(of: preferences.order) { _, _ in
            pageLimit = 160
            search.update(query, catalog: catalog, order: preferences.order)
        }
        .sheet(isPresented: $showScratchpad) { ScratchpadView(text: $scratchpad) }
    }

    private var collections: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoveryCollection.allCases) { item in
                    Button { collection = item } label: {
                        Text(item.rawValue).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 17).padding(.vertical, 10)
                            .foregroundStyle(collection == item ? Palette.surface : Palette.muted)
                            .background(collection == item ? Palette.ink : Palette.soft, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var scratchpadCard: some View {
        Button { showScratchpad = true } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Your scratchpad", systemImage: "pencil.line").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.subheadline)
                }
                Text(scratchpad.isEmpty ? "A place to put things together.  ☺" : scratchpad)
                    .font(scratchpad.isEmpty ? .subheadline : .title2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            .foregroundStyle(Palette.ink)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.soft, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scratchpadCard")
    }

    private var browseCard: some View {
        NavigationLink {
            BlocksView(select: select)
        } label: {
            HStack(spacing: 16) {
                Text("あ").font(Font(UnicodeFontSupport.font(for: "あ", size: 31, enabled: preferences.useUnicodeFonts))).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Take the scenic route").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("Wander through \(catalog.blocks.count) Unicode blocks.").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(.vertical, 8)
        }
    }
}

enum DiscoveryCollection: String, CaseIterable, Identifiable {
    case all = "All characters", essentials = "Essentials", arrows = "Arrows", math = "Math", letters = "Letters", playful = "Playful"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "A world of characters"
        case .essentials: return "Small symbols, big possibilities"
        case .arrows: return "A sense of direction"
        case .math: return "Beautiful equations"
        case .letters: return "Letters with character"
        case .playful: return "A little more expressive"
        }
    }
    func characters(in catalog: UnicodeCatalog) -> [UnicodeCharacter] {
        let points: [UInt32]
        switch self {
        case .all: return catalog.orderedCharacters(limit: 160)
        case .essentials: points = [0x2661, 0x2606, 0x2726, 0x2192, 0x221E, 0x00B0, 0x00D7, 0x2713, 0x00A9, 0x00AE, 0x2122, 0x2022, 0x2014, 0x2026, 0x00B7, 0x266A, 0x00B1, 0x2260, 0x00A7, 0x00B6]
        case .arrows: points = Array(0x2190...0x21A3) + [0x21AA, 0x21BA, 0x21C4, 0x21D2, 0x21D4, 0x27F6, 0x27F5, 0x27F7]
        case .math: points = [0x221E, 0x2211, 0x220F, 0x221A, 0x222B, 0x222C, 0x2202, 0x2206, 0x2207, 0x2260, 0x2248, 0x2264, 0x2265, 0x00B1, 0x00D7, 0x00F7, 0x2208, 0x2209, 0x222A, 0x2229, 0x2205, 0x2200, 0x2203, 0x03C0]
        case .letters: points = [0x00E6, 0x0153, 0x00DF, 0x00F8, 0x0142, 0x00F0, 0x00FE, 0x0259, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03BB, 0x03BC, 0x03C0, 0x03C9, 0x0416, 0x042F, 0x3042, 0x30A2, 0x5B57, 0xD55C, 0x2113, 0x212F]
        case .playful: points = [0x2603, 0x263A, 0x263B, 0x2665, 0x2660, 0x2663, 0x2666, 0x2600, 0x263E, 0x2602, 0x2615, 0x2693, 0x2699, 0x2708, 0x2709, 0x2702, 0x1F680, 0x1F30D, 0x1F331, 0x1F984, 0x1F308, 0x1F41A, 0x1F407, 0x1F3B2]
        }
        return points.compactMap { catalog.character(at: $0) }
    }
}
