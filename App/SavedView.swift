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
            VStack(alignment: .leading, spacing: 16) {
                Picker("Collection", selection: $showRecents) {
                    Text("Favorites").tag(false)
                    Text("Recently Used").tag(true)
                }.pickerStyle(.segmented)
                CatalogControls()
                if characters.isEmpty && emojis.isEmpty && otherTexts.isEmpty {
                    EmptyCollection(symbol: showRecents ? "clock" : "star", title: showRecents ? "No Recent Characters" : "No Favorites", message: showRecents ? "Characters you copy or add to your scratchpad appear here." : "Open any character and tap Save to keep it here and on the keyboard’s Favorites page.")
                } else if !characters.isEmpty {
                    SectionLabel(title: "Characters", trailing: "\(characters.count)")
                    CharacterGrid(characters: characters, select: select)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(showRecents ? "savedRecents" : "savedFavorites")
                }
                if !emojis.isEmpty {
                    SectionLabel(title: "Emoji", trailing: "\(emojis.count)")
                    EmojiGrid(entries: emojis) { selectedEmoji = $0 }
                }
                if !otherTexts.isEmpty {
                    SectionLabel(title: "Text", trailing: "\(otherTexts.count)")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                        ForEach(Array(otherTexts.enumerated()), id: \.offset) { _, text in
                            Button(text) { UIPasteboard.general.string = text }
                                .font(.title2).foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityHint("Copy saved text")
                                .contextMenu { Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) { store.removeFavoriteText(text) } }
                        }
                    }
                }
                if let issue = boards.loadIssue {
                    Text(issue.rawValue).font(.footnote).foregroundStyle(.red)
                }
                if boards.syncStatus == .unavailable {
                    Text("Favorites could not sync right now. Your local collection is kept; reopen the app or keyboard to retry.")
                        .font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("favorites.syncError")
                }
                Text("Favorites are the keyboard's Favorites page. To sync favorites saved in the keyboard back to this app, enable Allow Full Access in iOS keyboard settings. Recently Used stays separate. Nothing is sent to a server.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .onAppear { store.refreshFavorites() }
        .background(Color.groupedBackground)
        .navigationTitle("Favorites")
        .sheet(item: $selectedEmoji) { EmojiDetailView(emoji: $0, scratchpad: $scratchpad) }
    }
}
