import SwiftUI

struct SavedView: View {
    var select: (UnicodeCharacter) -> Void
    @EnvironmentObject private var store: CharacterStore
    @State private var showRecents = false

    private var characters: [UnicodeCharacter] { showRecents ? store.recentCharacters : store.favoriteCharacters }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your own\nlittle collection.")
                        .font(.system(size: 37, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Keep your favorites close at hand.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                Picker("Collection", selection: $showRecents) {
                    Text("Favorites").tag(false)
                    Text("Recently used").tag(true)
                }.pickerStyle(.segmented)
                if characters.isEmpty {
                    EmptyCollection(symbol: showRecents ? "clock" : "star", title: showRecents ? "Your next character awaits" : "Start your collection", message: showRecents ? "Characters you copy or add to your scratchpad will appear here." : "Tap any character, then Save. Your favorites will be waiting here.")
                } else {
                    SectionLabel(title: showRecents ? "Recently used" : "Favorites", trailing: "\(characters.count) CHARACTERS")
                    CharacterGrid(characters: characters, select: select)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(showRecents ? "savedRecents" : "savedFavorites")
                }
                Text("The app and keyboard keep their own collections on this device, so the keyboard works without Full Access.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Saved characters").navigationBarTitleDisplayMode(.inline)
    }
}
