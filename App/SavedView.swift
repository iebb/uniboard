import SwiftUI

struct SavedView: View {
    var select: (UnicodeCharacter) -> Void
    @EnvironmentObject private var store: CharacterStore
    @State private var showRecents = false
    @EnvironmentObject private var preferences: CatalogPreferences
    @Binding var scratchpad: String
    @State private var selectedEmoji: UnicodeEmojiEntry?

    private var characters: [UnicodeCharacter] {
        showRecents ? store.recentCharacters(in: preferences.catalog) : store.favoriteCharacters(in: preferences.catalog)
    }
    private var emojis: [UnicodeEmojiEntry] {
        showRecents ? store.recentEmojiEntries(in: preferences.emojis) : store.favoriteEmojiEntries(in: preferences.emojis)
    }

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
                CatalogControls(showSort: false)
                if characters.isEmpty && emojis.isEmpty {
                    EmptyCollection(symbol: showRecents ? "clock" : "star", title: showRecents ? "Your next character awaits" : "Start your collection", message: showRecents ? "Characters you copy or add to your scratchpad will appear here." : "Tap any character, then Save. Your favorites will be waiting here.")
                } else if !characters.isEmpty {
                    SectionLabel(title: showRecents ? "Recently used" : "Favorites", trailing: "\(characters.count) CHARACTERS")
                    CharacterGrid(characters: characters, select: select)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(showRecents ? "savedRecents" : "savedFavorites")
                }
                if !emojis.isEmpty {
                    SectionLabel(title: showRecents ? "Recent emoji" : "Saved emoji", trailing: "\(emojis.count) EMOJI")
                    EmojiGrid(entries: emojis) { selectedEmoji = $0 }
                }
                Text("The app and keyboard keep their own collections on this device, so the keyboard works without Full Access.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Saved characters").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEmoji) { EmojiDetailView(emoji: $0, scratchpad: $scratchpad) }
    }
}
