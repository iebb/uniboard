import SwiftUI
import os

@main
struct UniboardApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = CharacterStore.shared
    @StateObject private var preferences = CatalogPreferences.shared

    init() {
        // Before any store reads: finish or discard an interrupted write, and
        // move the root files into the versioned configuration once.
        ConfigurationRecovery.run()
        // Once, in the current generation: the retired Number Row choice
        // becomes digits in the main keyboard's arrangements. Until then the
        // keyboard reads an earlier file the same way.
        if SharedConfigurationLocation.shared.currentGeneration() != nil {
            KeyboardKeySettings().migrateNumberRowIfNeeded()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            CharacterStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "scratchpad")
            for key in ["exploreGridDensity", "explorePlane", "exploreShowsPrivateUse"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            CatalogPreferences.shared.reset(preservingEdition: true)
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
            if ProcessInfo.processInfo.arguments.contains("--unit-testing") {
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
