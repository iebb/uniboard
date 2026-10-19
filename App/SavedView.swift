import SwiftUI
import UIKit

struct SavedView: View {
    var select: (UnicodeCharacter) -> Void
    @EnvironmentObject private var store: CharacterStore
    @ObservedObject private var boards = SymbolBoardStore.shared
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

    private var otherTexts: [String] { showRecents ? [] : store.otherFavoriteTexts(in: preferences.emojis) }

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
                if characters.isEmpty && emojis.isEmpty && otherTexts.isEmpty {
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
                if !otherTexts.isEmpty {
                    SectionLabel(title: "Saved text", trailing: "\(otherTexts.count) KEYS")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
                        ForEach(Array(otherTexts.enumerated()), id: \.offset) { _, text in
                            Button(text) { UIPasteboard.general.string = text }
                                .font(.title2).frame(maxWidth: .infinity, minHeight: 48)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                                .accessibilityHint("Copy saved text")
                                .contextMenu { Button("Remove from favorites", role: .destructive) { store.removeFavoriteText(text) } }
                        }
                    }
                }
                if let issue = boards.loadIssue {
                    Text(issue.rawValue).font(.caption).foregroundStyle(Palette.accent)
                }
                if boards.syncStatus == .unavailable {
                    Text("Favorites could not sync right now. Your local collection is kept; reopen the app or keyboard to retry.")
                        .font(.caption).foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("favorites.syncError")
                }
                Text("Favorites are shared with the keyboard on this device. To sync favorites saved in the keyboard back to this app, enable Allow Full Access in iOS keyboard settings. With it off, keyboard changes stay local until access is enabled. Recently used stays separate. Nothing is sent to a server.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .onAppear { store.refreshFavorites() }
        .background(Palette.background)
        .navigationTitle("Saved characters").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEmoji) { EmojiDetailView(emoji: $0, scratchpad: $scratchpad) }
    }
}
