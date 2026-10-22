import SwiftUI

struct EmojisView: View {
    @Binding var scratchpad: String
    var select: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var query = ""
    @State private var pageLimit = 120
    /// Code point order, or by the version that introduced each emoji.
    @AppStorage("emojiSortOrder") private var order: UnicodeSortOrder = .codePoint
    private var entries: [UnicodeEmojiEntry] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferences.emojis.entries(limit: pageLimit, order: order)
            : preferences.emojis.search(query, limit: pageLimit, order: order)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchBar(text: $query, placeholder: "Name, group or code points", identifier: "emojiSearch")
                CatalogControls()
                EmojiGrid(entries: entries, onReachEnd: { if entries.count == pageLimit { pageLimit += 120 } }, select: select)
                if entries.isEmpty {
                    EmptyCollection(symbol: "face.smiling", title: "No Matching Emoji", message: "Try a name such as rocket, a group such as flags, or paste an emoji sequence.")
                }
                Text("Version order uses each emoji’s introduction; its individual Unicode scalars can be older. Your iOS fonts may show a box or several symbols for newer emoji, but Uniboard always inserts the original sequence.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Emoji")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Order", selection: $order) {
                        ForEach(UnicodeSortOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel("Order")
                .accessibilityValue(order.title)
                .accessibilityIdentifier("emojiOrder")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, _ in pageLimit = 120 }
        .onChange(of: order) { _, _ in pageLimit = 120 }
        .onChange(of: preferences.edition) { _, _ in pageLimit = 120 }
    }
}

struct EmojiGrid: View {
    let entries: [UnicodeEmojiEntry]
    /// Called when the last emoji scrolls into view, to load the next page.
    var onReachEnd: (() -> Void)? = nil
    var select: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var store: CharacterStore
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 8)], spacing: 8) {
            ForEach(entries) { emoji in
                EmojiTile(emoji: emoji, favorite: store.isFavoriteEmoji(emoji.id)) { select(emoji) }
                    .onAppear { if emoji.id == entries.last?.id { onReachEnd?() } }
            }
        }
    }
}

private struct EmojiTile: View {
    let emoji: UnicodeEmojiEntry
    let favorite: Bool
    let action: () -> Void
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var hoverTask: Task<Void, Never>?
    private var missing: Bool {
        UnicodeFontSupport.stockFontsMiss(emoji.text, emoji: true)
    }
    var body: some View {
        VStack(spacing: 3) {
            Text(emoji.text).font(Font(UnicodeFontSupport.font(for: emoji.text, size: 34, enabled: preferences.useUnicodeFonts))).lineLimit(1).minimumScaleFactor(0.55).frame(height: 44)
            Text(emoji.name).font(.caption2.weight(.medium))
                .lineLimit(2).multilineTextAlignment(.center).frame(height: 28)
        }.padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 92)
            .background(Color.previewSurface(missing: missing))
            .overlay(alignment: .topTrailing) { VersionRibbon(version: emoji.emojiVersion, prefix: "E") }
            .overlay(alignment: .topLeading) {
                if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(7) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .accessibilityElement(children: .ignore)
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
                VStack(spacing: 20) {
                    Text(emoji.text).font(Font(UnicodeFontSupport.font(for: emoji.text, size: 92, enabled: preferences.useUnicodeFonts))).lineLimit(1).minimumScaleFactor(0.4)
                        .padding(24)
                        .frame(maxWidth: .infinity).frame(height: 196)
                        .background(Color.previewSurface(missing: UnicodeFontSupport.stockFontsMiss(emoji.text, emoji: true)),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(spacing: 4) {
                        Text(emoji.name).font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("emojiProperties.name")
                        Text(emoji.codePointLabel).font(.body.monospaced()).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled).accessibilityIdentifier("emojiProperties.codepoints")
                    }
                    VStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = emoji.text
                            store.recordEmojiUse(emoji)
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy Emoji", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("copyEmoji")
                        HStack(spacing: 10) {
                            Button {
                                store.toggleFavoriteEmoji(emoji)
                            } label: {
                                Label(store.isFavoriteEmoji(emoji.id) ? "Saved" : "Save", systemImage: store.isFavoriteEmoji(emoji.id) ? "star.fill" : "star")
                                    .frame(maxWidth: .infinity)
                            }.accessibilityIdentifier("toggleEmojiFavorite")
                            Button {
                                scratchpad += emoji.text
                                store.recordEmojiUse(emoji)
                                added = true
                            } label: {
                                Label(added ? "Added" : "Scratchpad", systemImage: added ? "checkmark" : "plus")
                                    .frame(maxWidth: .infinity)
                            }.accessibilityIdentifier("addEmojiToScratchpad")
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(emoji.group) · \(emoji.subgroup). This fully qualified emoji contains \(emoji.codePoints.count) Unicode scalar\(emoji.codePoints.count == 1 ? "" : "s"). Copying or inserting it preserves the complete sequence.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("emojiProperties.description")
                        Text("A missing glyph does not remove its name or properties. Older iOS fonts may display this sequence as a box or separate components.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    PropertyGroup(title: "Properties", rows: [
                        .init(title: "Introduced", value: "Emoji \(emoji.emojiVersion)", identifier: "emojiProperties.version", monospaced: false),
                        .init(title: "Newest scalar age", value: "Unicode \(emoji.unicodeVersion)", identifier: "emojiProperties.age", monospaced: false),
                        .init(title: "UTF-8", value: emoji.text.utf8.map { String(format: "%02X", $0) }.joined(separator: " "), identifier: "emojiProperties.utf8", stacked: true),
                        .init(title: "UTF-16", value: emoji.text.utf16.map { String(format: "%04X", $0) }.joined(separator: " "), identifier: "emojiProperties.utf16", stacked: true),
                    ])
                    let components = emoji.codePoints.compactMap { preferences.catalog.character(at: $0) }
                    if !components.isEmpty {
                        PropertyGroup(title: "Unicode Components", rows: components.enumerated().map { index, character in
                            PropertyRow(title: "\(character.codePointLabel) · \(character.name)",
                                  value: [character.detail, "\(character.categoryName) · \(character.age.map { "Unicode \($0)" } ?? "Age pending")"]
                                    .filter { !$0.isEmpty }.joined(separator: "\n"),
                                  identifier: "emojiProperties.component.\(index)", monospaced: false, stacked: true)
                        })
                    }
                }.padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(Color.groupedBackground)
                .navigationTitle("Emoji").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
}
