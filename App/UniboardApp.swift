import SwiftUI
import os

@main
struct UniboardApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: CharacterStore
    @StateObject private var preferences: CatalogPreferences
#if DEBUG
    private let pageCacheWarningFixture: PageCacheWarningFixture?
#endif

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--page-cache-warning-fixture") {
            // Explicit isolated capture only: bypass recovery, migrations and all
            // normal launch fixtures before any shared/App Group store is read.
            let fixture = try! PageCacheWarningFixture()
            pageCacheWarningFixture = fixture
            _store = StateObject(wrappedValue: CharacterStore(defaults: fixture.defaults))
            _preferences = StateObject(wrappedValue: CatalogPreferences(
                editionSettings: UnicodeEditionSettings(containerURL: { fixture.directory }), fontRules: nil,
                autoCapitalization: AutoCapitalizationSetting(directory: { fixture.directory }),
                emojiCategories: EmojiCategorySetting(directory: { fixture.directory })))
            return
        }
        pageCacheWarningFixture = nil
#endif
        // Fresh installs type without the number row; anyone who opened an
        // earlier Uniboard keeps it. Decided before this launch writes anything.
        let group = SharedConfigurationLocation.shared.root()
        // UI tests type digits from the number row on their fresh devices.
        let earlierUse = group.map { ProcessInfo.processInfo.arguments.contains("--uitesting")
            || KeyboardNumberRowDefault.hasEarlierUse(in: $0, defaults: .standard) }
        // Before any store reads: finish or discard an interrupted write, and
        // move the root files into the versioned configuration once.
        ConfigurationRecovery.run()
        if let group, let earlierUse { KeyboardNumberRowDefault.recordIfNeeded(in: group, earlierUse: earlierUse) }
        // Once, in the current generation: the retired Number Row choice
        // becomes digits in the main keyboard's arrangements. Until then the
        // keyboard reads an earlier file the same way.
        if SharedConfigurationLocation.shared.currentGeneration() != nil {
            KeyboardKeySettings().migrateNumberRowIfNeeded()
        }
        _store = StateObject(wrappedValue: CharacterStore.shared)
        _preferences = StateObject(wrappedValue: CatalogPreferences.shared)
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            CharacterStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "scratchpad")
            for key in ["exploreGridDensity", "explorePlane", "exploreShowsPrivateUse", "emojiColumns", "blocksDescending"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            CatalogPreferences.shared.reset(preservingEdition: true)
            CatalogPreferences.shared.showAllEmojiGroups()
            // "Flags|Objects": start a test with these categories hidden.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--hidden-emoji-categories"), arguments.indices.contains(index + 1) {
                for group in arguments[index + 1].split(separator: "|") { CatalogPreferences.shared.setEmojiGroup(String(group), shown: false) }
            }
        }
#if DEBUG
        FontRuleFixtures.applyLaunchArguments()
        // UI tests: `--text-preview on|off` sets the keyboard's text preview
        // at launch instead of through two trips to Settings.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting"), let index = arguments.firstIndex(of: "--text-preview"),
           arguments.indices.contains(index + 1) {
            CatalogPreferences.shared.selectTextPreview(arguments[index + 1] == "on")
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let fixture = pageCacheWarningFixture {
                NavigationStack {
                    PageArrangeView(boardID: fixture.boardID, boards: fixture.boards)
                }
            } else if ProcessInfo.processInfo.arguments.contains("--unit-testing") {
                // Unit tests render their own UIKit fixtures. Keep unrelated
                // app navigation and keyboard restoration out of that host.
                Color.clear
            } else {
                content
            }
#else
            content
#endif
        }
    }

    private var content: some View {
        ContentView()
            .environmentObject(store)
            .environmentObject(preferences)
            .onAppear { store.refreshFavorites() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshFavorites() } }
            .task(priority: .background) { await Self.prepareSearchIndex() }
    }

    /// Builds the shared Unicode search index once per catalog (again after an
    /// update brings new Unicode data), after launch has settled and at
    /// background priority. Until it is ready, searches scan the catalog.
    private static func prepareSearchIndex() async {
#if DEBUG
        // UI tests measure the keyboard's search without the index.
        if ProcessInfo.processInfo.arguments.contains("--search-index-off") {
            if let url = UnicodeSearchIndexStore.shared.fileURL { try? FileManager.default.removeItem(at: url) }
            return
        }
#endif
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        let started = DispatchTime.now().uptimeNanoseconds
        let bytes = await Task.detached(priority: .background) {
            UnicodeSearchIndexStore.shared.prepare(for: .shared)?.byteCount
        }.value
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        Logger(subsystem: "ad.neko.uniboard", category: "SearchIndex")
            .info("Search index ready: \(bytes ?? 0, privacy: .public) bytes in \(milliseconds, privacy: .public) ms")
    }
}

#if DEBUG
/// Capture fixture uses the real publication/local-rejection path. It has no
/// reference to the user's defaults, App Group, configuration or shared stores.
@MainActor
private final class PageCacheWarningFixture {
    let defaults: UserDefaults
    let directory: URL
    let boards: SymbolBoardStore
    let boardID: String
    private let suiteName: String

    init() throws {
        let suiteName = "Uniboard.PageCacheWarningFixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rejectLocal = false
        let pages = SymbolPageSettings(containerURL: { directory })
        let boards = SymbolBoardStore(defaults: defaults, persist: { data in
            guard !rejectLocal else { return false }
            defaults.set(data, forKey: SymbolBoardStore.storageKey)
            return defaults.data(forKey: SymbolBoardStore.storageKey) == data
        }, pages: pages)
        guard let id = boards.createBoard(named: "Symbols") else { throw CocoaError(.fileWriteUnknown) }
        for text in ["!", "?", "@", "#", "$", "%", "&", "*"] {
            guard boards.add(text: text, to: id) != nil else { throw CocoaError(.fileWriteUnknown) }
        }
        var rows = boards.activeBoard.resolvedRows
        rows[0].alignment = .right
        rejectLocal = true
        guard boards.setExplicitRows(boardID: id, rows: rows), boards.localCopyWarning,
              pages.load()?.pages.first(where: { $0.id == id })?.explicitRows == rows else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.suiteName = suiteName
        self.defaults = defaults
        self.directory = directory
        self.boards = boards
        boardID = id
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
