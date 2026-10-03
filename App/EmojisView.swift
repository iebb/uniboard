import SwiftUI

struct EmojisView: View {
    @Binding var scratchpad: String
    var select: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var query = ""
    @State private var pageLimit = 120
    private var entries: [UnicodeEmojiEntry] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferences.emojis.entries(limit: pageLimit, order: preferences.order)
            : preferences.emojis.search(query, limit: pageLimit, order: preferences.order)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Every expression.\nEvery little detail.")
                    .font(.system(size: 35, design: .serif)).foregroundStyle(Palette.ink)
                Text("Find emoji by name, group or code points. A tap opens the full sequence; hold or hover for its properties.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                SearchBar(text: $query, placeholder: "Search emoji, like woman technologist", identifier: "emojiSearch")
                CatalogControls()
                Text("Version order uses each emoji’s introduction. The ages of its individual Unicode scalars can differ.")
                    .font(.caption).foregroundStyle(Palette.muted)
                EmojiGrid(entries: entries, select: select)
                if entries.isEmpty {
                    EmptyCollection(symbol: "face.smiling", title: "No matching emoji", message: "Try a name such as rocket, a group such as flags, or paste an emoji sequence.")
                } else if entries.count == pageLimit {
                    Button("Load more emoji") { pageLimit += 120 }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(16)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("loadMoreEmoji")
                }
                Text("Your iOS fonts may show a box or several symbols for newer emoji. The name, sequence and properties remain readable; Uniboard inserts the original sequence.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Emoji").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, _ in pageLimit = 120 }
        .onChange(of: preferences.edition) { _, _ in pageLimit = 120 }
        .onChange(of: preferences.order) { _, _ in pageLimit = 120 }
    }
}

struct EmojiGrid: View {
    let entries: [UnicodeEmojiEntry]
    var select: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var store: CharacterStore
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 9)], spacing: 9) {
            ForEach(entries) { emoji in
                EmojiTile(emoji: emoji, favorite: store.isFavoriteEmoji(emoji.id)) { select(emoji) }
            }
        }
    }
}

private struct EmojiTile: View {
    let emoji: UnicodeEmojiEntry
    let favorite: Bool
    let action: () -> Void
    @State private var hoverTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 7) {
            Text(emoji.text).font(.system(size: 32)).lineLimit(1).minimumScaleFactor(0.55).frame(height: 40)
            Text(emoji.name.capitalized).font(.system(size: 11, weight: .medium))
                .lineLimit(2).multilineTextAlignment(.center).foregroundStyle(Palette.ink).frame(height: 28)
            Text("Emoji \(emoji.emojiVersion)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 122)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .topTrailing) {
                if favorite { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Palette.accent).padding(8) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .gesture(LongPressGesture(minimumDuration: 0.4).exclusively(before: TapGesture()).onEnded { _ in action() })
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                        guard !Task.isCancelled else { return }
                        action()
                    }
                }
            }
            .onDisappear { hoverTask?.cancel() }
            .accessibilityLabel("\(emoji.name), \(emoji.codePointLabel)")
            .accessibilityValue("Emoji \(emoji.emojiVersion)")
            .accessibilityHint("Tap, hold, or hover for the complete emoji sequence and properties")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityIdentifier("emoji-\(emoji.id)")
    }
}

struct EmojiDetailView: View {
    let emoji: UnicodeEmojiEntry
    @Binding var scratchpad: String
    @EnvironmentObject private var store: CharacterStore
    @EnvironmentObject private var preferences: CatalogPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var added = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(emoji.text).font(.system(size: 92)).lineLimit(1).minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity).frame(height: 190)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 24))
                    Text(emoji.name.capitalized).font(.system(size: 27, design: .serif))
                        .foregroundStyle(Palette.ink).accessibilityIdentifier("emojiProperties.name")
                    Text("\(emoji.group) · \(emoji.subgroup). This fully qualified emoji contains \(emoji.codePoints.count) Unicode scalar\(emoji.codePoints.count == 1 ? "" : "s"). Copying or inserting it preserves the complete sequence.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("emojiProperties.description")
                    Text(emoji.codePointLabel).font(.caption.monospaced()).foregroundStyle(Palette.accent)
                        .textSelection(.enabled).accessibilityIdentifier("emojiProperties.codepoints")
                    Text("A missing glyph does not remove its name or properties. Older iOS fonts may display this sequence as a box or separate components.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button {
                        UIPasteboard.general.string = emoji.text
                        store.recordEmojiUse(emoji)
                        copied = true
                    } label: {
                        Label(copied ? "Copied emoji" : "Copy emoji", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.headline).frame(maxWidth: .infinity).padding(17)
                            .foregroundStyle(Palette.surface).background(Palette.ink, in: RoundedRectangle(cornerRadius: 15))
                    }.accessibilityIdentifier("copyEmoji")
                    HStack {
                        Button {
                            store.toggleFavoriteEmoji(emoji)
                        } label: {
                            Label(store.isFavoriteEmoji(emoji.id) ? "Saved" : "Save", systemImage: store.isFavoriteEmoji(emoji.id) ? "star.fill" : "star")
                                .frame(maxWidth: .infinity).padding(15).background(Palette.soft, in: RoundedRectangle(cornerRadius: 15))
                        }.accessibilityIdentifier("toggleEmojiFavorite")
                        Button {
                            scratchpad += emoji.text
                            store.recordEmojiUse(emoji)
                            added = true
                        } label: {
                            Label(added ? "Added" : "Scratchpad", systemImage: added ? "checkmark" : "plus")
                                .frame(maxWidth: .infinity).padding(15).background(Palette.soft, in: RoundedRectangle(cornerRadius: 15))
                        }.accessibilityIdentifier("addEmojiToScratchpad")
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                    property("EMOJI INTRODUCTION", value: "Emoji \(emoji.emojiVersion)", id: "version")
                    property("NEWEST SCALAR AGE", value: "Unicode \(emoji.unicodeVersion)", id: "age")
                    property("UTF-8", value: emoji.text.utf8.map { String(format: "%02X", $0) }.joined(separator: " "), id: "utf8")
                    property("UTF-16", value: emoji.text.utf16.map { String(format: "%04X", $0) }.joined(separator: " "), id: "utf16")
                    Text("Unicode components").font(.headline).foregroundStyle(Palette.ink)
                    ForEach(Array(emoji.codePoints.enumerated()), id: \.offset) { _, cp in
                        if let character = preferences.catalog.character(at: cp) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\(character.codePointLabel) · \(character.name.capitalized)")
                                    .font(.caption.monospaced().weight(.semibold)).foregroundStyle(Palette.ink)
                                Text(character.detail).font(.caption).foregroundStyle(Palette.muted)
                                Text("\(character.categoryName) · \(character.age.map { "Unicode \($0)" } ?? "Age pending")")
                                    .font(.caption).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity).buttonStyle(.plain)
            }.background(Palette.background)
                .navigationTitle("Emoji properties").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
    private func property(_ title: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.monospaced()).foregroundStyle(Palette.muted)
            Text(value).font(.caption.monospaced()).foregroundStyle(Palette.ink).textSelection(.enabled)
                .accessibilityIdentifier("emojiProperties.\(id)")
        }
    }
}
