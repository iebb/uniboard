import SwiftUI

struct EmojisView: View {
    @Binding var scratchpad: String
    var select: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var query = ""
    @State private var pageLimit = 120
    @State private var showCategories = false
    @State private var loadedEntries: [UnicodeEmojiEntry] = []
    @State private var completedRequest: EmojiBrowseRequest?
    /// The grid's measured width, which bounds the size steps.
    @State private var gridWidth: CGFloat = 0
    /// Code point order, or by the version that introduced each emoji.
    @AppStorage("emojiSortOrder") private var order: UnicodeSortOrder = .codePoint
    /// Tiles per row; 0 is Automatic, the 1.3 layout. App only.
    @AppStorage("emojiColumns") private var emojiColumns = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hidden: Set<String> { preferences.hiddenEmojiGroups }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var request: EmojiBrowseRequest {
        EmojiBrowseRequest(edition: preferences.edition, query: query, order: order, hidden: hidden,
                           skinToneVariants: preferences.skinToneVariants, limit: pageLimit)
    }
    private var entries: [UnicodeEmojiEntry] {
        // Keep earlier pages while adding a page, but never render an old filter's
        // results (even in the frame before SwiftUI starts the replacement task).
        completedRequest?.hasSameProjection(as: request) == true ? loadedEntries : []
    }
    private var isLoading: Bool { completedRequest != request }
    private var fewerVariants: Bool { preferences.skinToneVariants == .fewer }
    private var zoom: EmojiZoom { EmojiZoom(stored: emojiColumns, width: gridWidth) }
    var body: some View {
        let catalog = preferences.emojis
        let total = catalog.groups.count
        let shown = catalog.shownGroupCount(hiding: hidden)
        let entries = self.entries
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchBar(text: $query, placeholder: "Name, group or code points", identifier: "emojiSearch")
                CatalogControls()
                if shown < total || fewerVariants {
                    EmojiFilterRow(shown: shown, total: total, fewerVariants: fewerVariants,
                                   open: { showCategories = true }, showAll: preferences.showAllEmojiGroups,
                                   showAllVariants: { preferences.selectSkinToneVariants(.all) })
                }
                if total > 0 && shown == 0 {
                    emptyState(symbol: "line.3.horizontal.decrease.circle", title: "No emoji categories shown",
                               message: "Choose at least one category to see emoji.")
                } else {
                    EmojiGrid(entries: entries, onReachEnd: {
                        if !isLoading && entries.count == pageLimit { pageLimit += 120 }
                    }, zoom: $emojiColumns, gridWidth: $gridWidth, select: select)
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if entries.isEmpty && !isLoading {
                        if shown < total && !trimmedQuery.isEmpty {
                            emptyState(symbol: "face.smiling", title: "No matching emoji in the categories shown",
                                       message: "Try another search or show more categories.")
                        } else {
                            EmptyCollection(symbol: "face.smiling", title: "No Matching Emoji", message: "Try a name such as rocket, a group such as flags, or paste an emoji sequence.")
                        }
                    }
                }
                Text("Pinch to change emoji size. Version order uses each emoji’s introduction; its individual Unicode scalars can be older. Your iOS fonts may show a box or several symbols for newer emoji, but Uniboard always inserts the original sequence.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .background { Color.groupedBackground.ignoresSafeArea() } // also behind the keyboard's corners
        .navigationTitle("Emoji")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCategories = true } label: {
                    Image(systemName: shown < total || fewerVariants ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Emoji Categories")
                .accessibilityValue((shown < total ? "\(shown.formatted()) of \(total.formatted()) categories shown" : "All categories shown")
                                    + (fewerVariants ? " · Fewer Variants" : ""))
                .accessibilityIdentifier("emojiCategories")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Emoji Size") {
                        ControlGroup {
                            Button { step(1) } label: { Label("Smaller", systemImage: "minus.magnifyingglass") }
                                .disabled(!zoom.canDecrease)
                                .accessibilityLabel("Decrease emoji size")
                                .accessibilityIdentifier("emojiSmaller")
                                .menuActionDismissBehavior(.disabled)
                            Button { step(-1) } label: { Label("Larger", systemImage: "plus.magnifyingglass") }
                                .disabled(!zoom.canIncrease)
                                .accessibilityLabel("Increase emoji size")
                                .accessibilityIdentifier("emojiLarger")
                                .menuActionDismissBehavior(.disabled)
                        } label: { Text("Emoji Size") }
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy) { emojiColumns = 0 }
                        } label: {
                            Label {
                                HStack {
                                    Text("Automatic")
                                    if emojiColumns == 0 { Image(systemName: "checkmark") }
                                }
                            } icon: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        }
                        .disabled(emojiColumns == 0)
                        .accessibilityLabel("Automatic emoji size")
                        .accessibilityHint("Fits emoji to the available width.")
                        .accessibilityIdentifier("emojiAutomatic")
                    }
                    Section {
                        Picker("Order", selection: $order) {
                            ForEach(UnicodeSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .accessibilityIdentifier("emojiOrder")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("View Options")
                .accessibilityValue(order.title)
                .accessibilityIdentifier("emojiViewOptions")
            }
        }
        .sheet(isPresented: $showCategories) { EmojiCategoriesView() }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, _ in pageLimit = 120 }
        .onChange(of: order) { _, _ in pageLimit = 120 }
        .onChange(of: hidden) { _, _ in pageLimit = 120 }
        .onChange(of: preferences.edition) { _, _ in pageLimit = 120 }
        .onChange(of: preferences.skinToneVariants) { _, _ in pageLimit = 120 }
        .task(id: request) {
            let captured = request
            let catalog = preferences.emojis
            let result = await CatalogWorker.run {
                catalog.search(captured.query, limit: captured.limit, order: captured.order,
                               hiding: captured.hidden, skinToneVariants: captured.skinToneVariants)
            }
            // .task cancels on every request change/disappearance; the explicit
            // identity check also rejects work completed before cancellation ran.
            guard !Task.isCancelled, captured == request else { return }
            loadedEntries = result
            completedRequest = captured
        }
    }

    private func step(_ change: Int) {
        guard let next = zoom.stepped(change) else { return }
        withAnimation(reduceMotion ? nil : .snappy) { emojiColumns = next }
    }

    private func emptyState(symbol: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button("Choose Categories") { showCategories = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("emojiChooseCategories")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Immutable generation of the app's background browse/search work. Size is not
/// part of this identity: zooming never changes the catalog projection.
private struct EmojiBrowseRequest: Equatable, Sendable {
    let edition: UnicodeEdition
    let query: String
    let order: UnicodeSortOrder
    let hidden: Set<String>
    let skinToneVariants: SkinToneVariants
    let limit: Int

    func hasSameProjection(as other: Self) -> Bool {
        edition == other.edition && query == other.query && order == other.order
            && hidden == other.hidden && skinToneVariants == other.skinToneVariants
    }
}

/// The Emoji tab's column count: the stored choice (0 = Automatic) within
/// what fits the measured width, and one step either way.
struct EmojiZoom: Equatable {
    let stored: Int
    let width: CGFloat
    var columns: Int {
        stored == 0 ? EmojiTileLayout.automaticColumns(in: Double(width)) : TileGridLayout.columns(stored: stored, in: width)
    }
    var maximumColumns: Int { TileGridLayout.maximumColumns(in: width) }
    var tileWidth: CGFloat { TileGridLayout.tileWidth(columns: columns, in: width) }
    /// Larger tiles: one column fewer.
    var canIncrease: Bool { width > 0 && columns > TileGridLayout.minimumColumns }
    /// Smaller tiles: one column more.
    var canDecrease: Bool { width > 0 && columns < maximumColumns }
    /// The value to store after `change` columns (+1 smaller, −1 larger),
    /// starting from the automatic count; nil at a limit.
    func stepped(_ change: Int) -> Int? {
        guard change < 0 ? canIncrease : canDecrease else { return nil }
        return TileGridLayout.columns(stored: columns + change, in: width)
    }
}

/// Visible active-filter state above the grid (design §1.3).
private struct EmojiFilterRow: View {
    let shown: Int
    let total: Int
    let fewerVariants: Bool
    let open: () -> Void
    let showAll: () -> Void
    let showAllVariants: () -> Void
    private var summary: String {
        "\(shown.formatted()) of \(total.formatted()) categories shown" + (fewerVariants ? " · Fewer Variants" : "")
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                openButton
                Spacer(minLength: 8)
                resetButtons
            }
            VStack(alignment: .leading, spacing: 0) {
                openButton
                resetButtons
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var openButton: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(.tint)
                Text(summary).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityHint("Opens Emoji Categories")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("emojiFilterSummary")
    }
    @ViewBuilder private var resetButtons: some View {
        if shown < total { showAllButton }
        if fewerVariants {
            Button("Show All Variants", action: showAllVariants)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("emojiFilterShowAllVariants")
        }
    }
    private var showAllButton: some View {
        Button("Show All", action: showAll)
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("emojiFilterShowAll")
    }
}

/// Which emoji categories appear in the app and keyboard (design §2).
/// Every switch saves at once; Done only closes.
struct EmojiCategoriesView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let catalog = preferences.emojis
        let hidden = preferences.hiddenEmojiGroups
        let shown = catalog.shownGroupCount(hiding: hidden)
        NavigationStack {
            List {
                Section {
                    Picker("Skin-Tone Variants", selection: Binding(
                        get: { preferences.skinToneVariants },
                        set: { preferences.selectSkinToneVariants($0) })) {
                        ForEach(SkinToneVariants.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityValue(preferences.skinToneVariants.title)
                    .accessibilityIdentifier("emojiCategories.skinToneVariants")
                } header: {
                    Text("Skin-Tone Variants")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show fewer repeated skin-tone variants while browsing. Saved emoji stay the same, and specific variants still appear when you search for them.")
                        if let error = preferences.emojiBrowsingSaveError {
                            Text(error).foregroundStyle(.red).accessibilityIdentifier("emojiCategories.variantsSaveError")
                        }
                    }
                }
                Section {
                    ForEach(catalog.groups, id: \.self) { group in
                        EmojiCategoryRow(group: group, sample: catalog.sample(forGroup: group) ?? "",
                                         count: catalog.count(inGroup: group),
                                         isShown: Binding(get: { !preferences.hiddenEmojiGroups.contains(group) },
                                                          set: { preferences.setEmojiGroup(group, shown: $0) }))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose which categories appear in the app and keyboard, including emoji search.\nHidden categories aren’t deleted from your saved pages or favorites.")
                        if let error = preferences.emojiCategoriesSaveError {
                            Text(error).foregroundStyle(.red).accessibilityIdentifier("emojiCategories.saveError")
                        }
                    }
                }
                Section {
                    Button("Show All") { preferences.showAllEmojiGroups() }
                        .disabled(shown == catalog.groups.count)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("emojiCategories.showAll")
                    Button("Hide All") { preferences.hideAllEmojiGroups() }
                        .disabled(shown == 0)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("emojiCategories.hideAll")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Emoji Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold).accessibilityIdentifier("emojiCategories.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct EmojiCategoryRow: View {
    let group: String
    let sample: String
    let count: Int
    @Binding var isShown: Bool
    private var countText: String { count == 1 ? "1 emoji" : "\(count.formatted()) emoji" }
    var body: some View {
        Toggle(isOn: $isShown) {
            HStack(spacing: 12) {
                Text(sample)
                    .font(.system(size: 22))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group)
                    Text(countText).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 52)
        .accessibilityLabel("\(group), \(countText)")
        .accessibilityHint("Show this category")
        .accessibilityIdentifier("emojiCategory.\(group)")
    }
}

struct EmojiGrid: View {
    let entries: [UnicodeEmojiEntry]
    /// Called when the last emoji scrolls into view, to load the next page.
    var onReachEnd: (() -> Void)? = nil
    /// The Emoji tab's remembered columns (0 = Automatic), which pinching
    /// and the tile actions change. Without it the grid keeps Automatic.
    var zoom: Binding<Int>? = nil
    /// Reports the measured width to the screen that owns the size menu.
    var gridWidth: Binding<CGFloat>? = nil
    var select: (UnicodeEmojiEntry) -> Void
    @EnvironmentObject private var store: CharacterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var pinch: CGFloat = 1
    var body: some View {
        let layout = EmojiZoom(stored: zoom?.wrappedValue ?? 0, width: width)
        let columns = layout.columns
        let tileWidth = layout.tileWidth
        let spacing = TileGridLayout.spacing
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(entries) { emoji in
                EmojiTile(emoji: emoji, favorite: store.isFavoriteEmoji(emoji.id), tileWidth: tileWidth,
                          increase: zoom != nil && layout.canIncrease ? { step(-1, layout) } : nil,
                          decrease: zoom != nil && layout.canDecrease ? { step(1, layout) } : nil) { select(emoji) }
                    .onAppear { if emoji.id == entries.last?.id { onReachEnd?() } }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            width = $0
            gridWidth?.wrappedValue = $0
        }
        .simultaneousGesture(MagnifyGesture()
            .onChanged { pinch = $0.magnification }
            .onEnded { _ in
                // As CharacterGrid: spreading gives fewer, larger tiles; one step per gesture.
                let change = pinch > 1.15 ? -1 : pinch < 0.87 ? 1 : 0
                if change != 0 { step(change, layout) }
                pinch = 1
            }, isEnabled: zoom != nil)
        .animation(reduceMotion ? nil : .snappy, value: columns)
    }

    private func step(_ change: Int, _ layout: EmojiZoom) {
        guard let zoom, let next = layout.stepped(change) else { return }
        zoom.wrappedValue = next
    }
}

private struct EmojiTile: View {
    let emoji: UnicodeEmojiEntry
    let favorite: Bool
    /// The measured tile width, or 0 before the grid is measured.
    var tileWidth: CGFloat = 0
    var increase: (() -> Void)? = nil
    var decrease: (() -> Void)? = nil
    let action: () -> Void
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var hoverTask: Task<Void, Never>?
    private var missing: Bool {
        UnicodeFontSupport.stockFontsMiss(emoji.text, emoji: true)
    }
    /// An unmeasured tile draws as the Automatic default (118 points on iPhone).
    private var width: Double { tileWidth > 0 ? Double(tileWidth) : 118 }
    private var glyphSize: CGFloat { CGFloat(EmojiTileLayout.glyphSize(tileWidth: width)) }
    private var showsName: Bool { EmojiTileLayout.showsName(tileWidth: width) }
    var body: some View {
        content
            .background(Color.previewSurface(missing: missing))
            .overlay(alignment: .topTrailing) {
                VersionRibbon(version: emoji.emojiVersion, prefix: "E",
                              labeled: TileGridLayout.showsLabeledRibbon(tileWidth: tileWidth, blockView: false),
                              triangleSide: VersionRibbon.triangleSide(cornerRadius: 12))
            }
            .overlay(alignment: .topLeading) {
                if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(width < 44 ? 4 : 7) }
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
            .modifier(EmojiSizeActions(increase: increase, decrease: decrease))
            .accessibilityIdentifier("emoji-\(emoji.id)")
    }

    private var glyph: some View {
        Text(emoji.text).font(Font(UnicodeFontSupport.font(for: emoji.text, size: glyphSize, enabled: preferences.useUnicodeFonts)))
            .lineLimit(1).minimumScaleFactor(0.55)
    }

    @ViewBuilder private var content: some View {
        if showsName {
            VStack(spacing: 3) {
                glyph.frame(height: glyphSize + 10)
                Text(emoji.name).font(EmojiTileLayout.usesLargeName(tileWidth: width) ? .footnote.weight(.medium) : .caption2.weight(.medium))
                    .lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        } else {
            glyph.padding(2).frame(maxWidth: .infinity).frame(height: tileWidth > 0 ? tileWidth : nil)
        }
    }
}

/// "Increase emoji size" and "Decrease emoji size", each left out at its limit.
private struct EmojiSizeActions: ViewModifier {
    let increase: (() -> Void)?
    let decrease: (() -> Void)?
    func body(content: Content) -> some View {
        content
            .accessibilityActions {
                if let increase { Button("Increase emoji size", action: increase) }
                if let decrease { Button("Decrease emoji size", action: decrease) }
            }
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
