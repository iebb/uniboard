import SwiftUI

@main
struct UniboardApp: App {
    @StateObject private var store = CharacterStore.shared

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            CharacterStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "scratchpad")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Palette.accent)
        }
    }
}
