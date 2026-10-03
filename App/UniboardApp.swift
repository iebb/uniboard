import SwiftUI

@main
struct UniboardApp: App {
    @StateObject private var store = CharacterStore.shared
    @StateObject private var preferences = CatalogPreferences.shared

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            CharacterStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "scratchpad")
            CatalogPreferences.shared.reset()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(preferences)
                .tint(Palette.accent)
        }
    }
}
