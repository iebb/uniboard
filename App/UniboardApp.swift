import SwiftUI

@main
struct UniboardApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = CharacterStore.shared
    @StateObject private var preferences = CatalogPreferences.shared

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            CharacterStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "scratchpad")
            for key in ["exploreGridDensity", "explorePlane", "exploreShowsPrivateUse"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            CatalogPreferences.shared.reset(preservingEdition: true)
        }
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
    }
}
