import SwiftUI
import UIKit

/// Query keys edit only the extension's local search. Insertion always sends the
/// original scalar or complete emoji sequence to the host's document proxy.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var keyboardHeight: NSLayoutConstraint?
    private var hostingController: UIHostingController<UnicodeKeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KeyboardPalette.backgroundUI
        let root = UnicodeKeyboardView(
            model: model, store: CharacterStore.shared, controller: self,
            insert: { [weak self] character in
                self?.textDocumentProxy.insertText(character.text)
                CharacterStore.shared.recordUse(character.codePoint)
                self?.model.lastItem = .character(character)
            },
            insertEmoji: { [weak self] emoji in
                self?.textDocumentProxy.insertText(emoji.text)
                CharacterStore.shared.recordEmojiUse(emoji)
                self?.model.lastItem = .emoji(emoji)
            },
            delete: { [weak self] in self?.deleteKey() },
            space: { [weak self] in self?.spaceKey() },
            returnKey: { [weak self] in self?.returnKey() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
        let height = view.heightAnchor.constraint(equalToConstant: 420)
        height.priority = .init(999)
        height.isActive = true
        keyboardHeight = height
        model.presentationChanged = { [weak self] in self?.updateKeyboardHeight() }
        synchronizeHostTraits()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        synchronizeHostTraits()
        updateKeyboardHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        synchronizeHostTraits()
    }

    private func synchronizeHostTraits() {
        model.needsInputModeSwitchKey = needsInputModeSwitchKey
        model.returnTitle = Self.returnTitle(for: textDocumentProxy.returnKeyType)
    }

    private func updateKeyboardHeight() {
        let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape == true
        let pad = traitCollection.userInterfaceIdiom == .pad
        if model.isCompactLayout != (landscape && !pad) { model.isCompactLayout = landscape && !pad }
        if model.isPadLayout != pad { model.isPadLayout = pad }
        let height: CGFloat
        if pad {
            height = model.inspection != nil ? 480 : model.isSearching ? 480 : 420
        } else if landscape {
            height = model.inspection != nil ? 320 : model.isSearching ? 270 : 290
        } else {
            height = model.inspection != nil ? 440 : model.isSearching ? 480 : 420
        }
        if keyboardHeight?.constant != height { keyboardHeight?.constant = height }
    }

    private func deleteKey() {
        if model.isSearching { model.deleteQueryCharacter() }
        else { textDocumentProxy.deleteBackward() }
    }

    private func spaceKey() {
        if model.isSearching { model.appendQuery(" ") }
        else { textDocumentProxy.insertText(" ") }
    }

    private func returnKey() {
        if model.inspection != nil { model.closeInspection() }
        else if model.isSearching { model.endSearch() }
        else { textDocumentProxy.insertText("\n") }
    }

    static func returnTitle(for type: UIReturnKeyType?) -> String {
        switch type {
        case .go: return "Go"
        case .google, .yahoo, .search: return "Search"
        case .join: return "Join"
        case .next: return "Next"
        case .route: return "Route"
        case .send: return "Send"
        case .done: return "Done"
        case .emergencyCall: return "Call"
        case .continue: return "Continue"
        default: return "Return"
        }
    }
}

private enum KeyboardSection: String, CaseIterable {
    case symbols = "Symbols"
    case emojis = "Emojis"
    case blocks = "Blocks"
    case saved = "Saved"

    var icon: String {
        switch self {
        case .symbols: return "sparkles"
        case .emojis: return "face.smiling"
        case .blocks: return "square.grid.2x2"
        case .saved: return "star"
        }
    }
}

private enum KeyboardItem {
    case character(UnicodeCharacter)
    case emoji(UnicodeEmojiEntry)

    var name: String {
        switch self {
        case .character(let character): return character.name.capitalized
        case .emoji(let emoji): return emoji.name.capitalized
        }
    }
    var displayText: String {
        switch self {
        case .character(let character): return character.displayText
        case .emoji(let emoji): return emoji.text
        }
    }
    var codePointLabel: String {
        switch self {
        case .character(let character): return character.codePointLabel
        case .emoji(let emoji): return emoji.codePointLabel
        }
    }
    var ageLabel: String {
        switch self {
        case .character(let character):
            return character.age.map { "U\($0)" } ?? (character.category == "Cn" ? "Unassigned" : "Age pending")
        case .emoji(let emoji): return "E\(emoji.emojiVersion)"
        }
    }
    var keyIdentifier: String {
        switch self {
        case .character(let character): return "keyboard.character.\(character.codePointLabel)"
        case .emoji(let emoji): return "keyboard.emoji.\(emoji.id)"
        }
    }
    var footer: String {
        switch self {
        case .character(let character): return character.codePointLabel
        case .emoji(let emoji): return emoji.codePoints.count == 1 ? emoji.codePointLabel : "\(emoji.codePoints.count) code points"
        }
    }
}

@MainActor
private final class KeyboardModel: ObservableObject {
    @Published var section: KeyboardSection = .symbols {
        didSet { if isSearching { scheduleSearch() } }
    }
    @Published var isSearching = false
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var edition: UnicodeEdition {
        didSet {
            defaults.set(edition == .latest ? "latest" : "draft", forKey: "keyboard.unicodeEdition")
            refreshCatalog()
        }
    }
    @Published var order: UnicodeSortOrder {
        didSet {
            defaults.set(orderValue, forKey: "keyboard.unicodeSortOrder")
            refreshCatalog()
        }
    }
    @Published var useUnicodeFonts: Bool {
        didSet {
            defaults.set(useUnicodeFonts, forKey: "keyboardUnicodeFonts")
            if !useUnicodeFonts { UnicodeFontSupport.clearCache() }
        }
    }
    @Published private(set) var results: [UnicodeCharacter] = []
    @Published private(set) var emojiResults: [UnicodeEmojiEntry] = []
    @Published private(set) var searchInProgress = false
    @Published private(set) var discoveryCharacters: [UnicodeCharacter] = []
    @Published private(set) var discoveryEmojis: [UnicodeEmojiEntry] = []
    @Published private(set) var discoveryLoading = false
    @Published private(set) var moreSymbols = false
    @Published private(set) var moreEmojis = false
    @Published var selectedBlock: UnicodeBlock?
    @Published private(set) var blockCharacters: [UnicodeCharacter] = []
    @Published private(set) var hasMoreBlockCharacters = false
    @Published private(set) var blockLoading = false
    @Published var lastItem: KeyboardItem?
    @Published var inspection: KeyboardItem? { didSet { presentationChanged?() } }
    @Published var showFavorites = true
    @Published var needsInputModeSwitchKey = true
    @Published var returnTitle = "Return"
    @Published var isCompactLayout = false
    @Published var isPadLayout = false
    var presentationChanged: (() -> Void)?
    private let defaults = UserDefaults.standard
    private let pageSize = 160
    private var revision = 0
    private var searchTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var blockTask: Task<Void, Never>?
    private var loadingSymbolPage = false
    private var loadingEmojiPage = false

    var catalog: UnicodeCatalog { edition.catalog }
    var emojiCatalog: EmojiCatalog { edition.emojiCatalog }
    var editionValue: String { edition == .latest ? "latest" : "draft" }
    var orderValue: String {
        switch order {
        case .newestFirst: return "newestFirst"
        case .oldestFirst: return "oldestFirst"
        case .codePoint: return "codePoint"
        }
    }

    init() {
        edition = defaults.string(forKey: "keyboard.unicodeEdition") == "latest" ? .latest : .draft
        switch defaults.string(forKey: "keyboard.unicodeSortOrder") {
        case "oldestFirst": order = .oldestFirst
        case "codePoint": order = .codePoint
        default: order = .newestFirst
        }
        useUnicodeFonts = defaults.bool(forKey: "keyboardUnicodeFonts")
        refreshCatalog()
    }

    func beginSearch() {
        inspection = nil
        isSearching = true
        scheduleSearch()
        presentationChanged?()
    }
    func endSearch() {
        isSearching = false
        presentationChanged?()
    }
    func inspect(_ item: KeyboardItem) {
        lastItem = item
        inspection = item
    }
    func closeInspection() { inspection = nil }
    func appendQuery(_ text: String) {
        guard query.count < 100 else { return }
        query += text
    }
    func deleteQueryCharacter() {
        guard !query.isEmpty else { return }
        query.removeLast()
    }

    func openBlock(_ block: UnicodeBlock) {
        blockTask?.cancel()
        selectedBlock = block
        blockCharacters = []
        hasMoreBlockCharacters = true
        blockLoading = false
        loadBlockPage()
    }
    func closeBlock() {
        blockTask?.cancel()
        selectedBlock = nil
        blockLoading = false
    }
    func loadBlockPage() {
        guard let block = selectedBlock, hasMoreBlockCharacters, !blockLoading else { return }
        blockLoading = true
        let activeCatalog = catalog, activeOrder = order, activeRevision = revision
        let offset = blockCharacters.count, limit = pageSize
        blockTask = Task { [weak self] in
            let more = await Task.detached(priority: .userInitiated) {
                activeCatalog.characters(in: block, offset: offset, limit: limit, order: activeOrder)
            }.value
            guard !Task.isCancelled, let self, self.revision == activeRevision,
                  self.selectedBlock?.id == block.id else { return }
            self.blockCharacters.append(contentsOf: more)
            self.hasMoreBlockCharacters = more.count == limit
            self.blockLoading = false
        }
    }

    func loadSymbolsPage() {
        guard moreSymbols, !loadingSymbolPage else { return }
        loadingSymbolPage = true
        let activeCatalog = catalog, activeOrder = order, activeRevision = revision
        let offset = discoveryCharacters.count, limit = pageSize
        Task { [weak self] in
            let more = await Task.detached(priority: .userInitiated) {
                activeCatalog.orderedCharacters(offset: offset, limit: limit, order: activeOrder)
            }.value
            guard let self, self.revision == activeRevision else { return }
            self.discoveryCharacters.append(contentsOf: more)
            self.moreSymbols = more.count == limit
            self.loadingSymbolPage = false
        }
    }

    func loadEmojisPage() {
        guard moreEmojis, !loadingEmojiPage else { return }
        loadingEmojiPage = true
        let activeCatalog = emojiCatalog, activeOrder = order, activeRevision = revision
        let offset = discoveryEmojis.count, limit = pageSize
        Task { [weak self] in
            let more = await Task.detached(priority: .userInitiated) {
                activeCatalog.entries(offset: offset, limit: limit, order: activeOrder)
            }.value
            guard let self, self.revision == activeRevision else { return }
            self.discoveryEmojis.append(contentsOf: more)
            self.moreEmojis = more.count == limit
            self.loadingEmojiPage = false
        }
    }

    func sorted(_ characters: [UnicodeCharacter]) -> [UnicodeCharacter] {
        characters.sorted { lhs, rhs in
            switch order {
            case .newestFirst:
                if lhs.versionSortKey != rhs.versionSortKey { return lhs.versionSortKey > rhs.versionSortKey }
            case .oldestFirst:
                if lhs.versionSortKey != rhs.versionSortKey { return lhs.versionSortKey < rhs.versionSortKey }
            case .codePoint: break
            }
            return lhs.codePoint < rhs.codePoint
        }
    }
    func sorted(_ emojis: [UnicodeEmojiEntry]) -> [UnicodeEmojiEntry] {
        emojis.sorted { lhs, rhs in
            switch order {
            case .newestFirst:
                if lhs.versionSortKey != rhs.versionSortKey { return lhs.versionSortKey > rhs.versionSortKey }
            case .oldestFirst:
                if lhs.versionSortKey != rhs.versionSortKey { return lhs.versionSortKey < rhs.versionSortKey }
            case .codePoint: break
            }
            return lhs.codePoints.lexicographicallyPrecedes(rhs.codePoints)
        }
    }

    private func refreshCatalog() {
        revision += 1
        inspection = nil
        lastItem = nil
        discoveryTask?.cancel()
        blockTask?.cancel()
        discoveryCharacters = []
        discoveryEmojis = []
        moreSymbols = false
        moreEmojis = false
        loadingSymbolPage = false
        loadingEmojiPage = false
        discoveryLoading = true
        let activeCatalog = catalog, activeEmojis = emojiCatalog, activeOrder = order
        let activeRevision = revision, limit = pageSize
        discoveryTask = Task { [weak self] in
            let pages = await Task.detached(priority: .userInitiated) {
                (activeCatalog.orderedCharacters(offset: 0, limit: limit, order: activeOrder),
                 activeEmojis.entries(offset: 0, limit: limit, order: activeOrder))
            }.value
            guard !Task.isCancelled, let self, self.revision == activeRevision else { return }
            self.discoveryCharacters = pages.0
            self.discoveryEmojis = pages.1
            self.moreSymbols = pages.0.count == limit
            self.moreEmojis = pages.1.count == limit
            self.discoveryLoading = false
        }
        if let oldBlock = selectedBlock {
            if let newBlock = catalog.blocks.first(where: { $0.id == oldBlock.id }) { openBlock(newBlock) }
            else { closeBlock() }
        }
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        emojiResults = []
        guard !searchQuery.isEmpty else { searchInProgress = false; return }
        searchInProgress = true
        let activeCatalog = catalog, activeEmojis = emojiCatalog, activeOrder = order
        let activeRevision = revision, searchEmojis = section == .emojis
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled else { return }
            let matches: ([UnicodeCharacter], [UnicodeEmojiEntry]) = await Task.detached(priority: .userInitiated) {
                if searchEmojis { return ([], activeEmojis.search(searchQuery, limit: 120, order: activeOrder)) }
                return (activeCatalog.search(searchQuery, limit: 120, order: activeOrder), [])
            }.value
            guard !Task.isCancelled, let self, self.revision == activeRevision,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery,
                  (self.section == .emojis) == searchEmojis else { return }
            self.results = matches.0
            self.emojiResults = matches.1
            self.searchInProgress = false
        }
    }
}

private enum KeyboardPalette {
    // Keycaps use iOS semantic surfaces; brand color is reserved for selection.
    static let accentUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.65, blue: 0.48, alpha: 1)
            : UIColor(red: 0.73, green: 0.30, blue: 0.17, alpha: 1)
    }
    static let backgroundUI = UIColor.systemGroupedBackground
    static let keyUI = UIColor.secondarySystemGroupedBackground
    static let pressedUI = UIColor.systemGray5
    static let borderUI = UIColor.separator.withAlphaComponent(0.18)
    static let actionUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGray3
            : UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
    }
    static let actionTextUI = UIColor.white
    static let accent = Color(uiColor: accentUI)
    static let background = Color(uiColor: backgroundUI)
    static let key = Color(uiColor: keyUI)
    static let separator = Color(uiColor: borderUI)
    static let secondary = Color.secondary
    static let action = Color(uiColor: actionUI)
    static let actionText = Color(uiColor: actionTextUI)
}

private extension View {
    func keyboardKeySurface(radius: CGFloat = 10) -> some View {
        background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(KeyboardPalette.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 0, x: 0, y: 1)
    }
}

private struct KeyboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct UnicodeKeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject var store: CharacterStore
    weak var controller: KeyboardViewController?
    let insert: (UnicodeCharacter) -> Void
    let insertEmoji: (UnicodeEmojiEntry) -> Void
    let delete: () -> Void
    let space: () -> Void
    let returnKey: () -> Void
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: model.isPadLayout ? 76 : 64, maximum: 100), spacing: 7)]
    }
    private var keyHeight: CGFloat { model.isCompactLayout ? 60 : model.isPadLayout ? 80 : 72 }
    private var headerHeight: CGFloat { model.isCompactLayout ? 38 : 42 }
    private var controlHeight: CGFloat { model.isCompactLayout ? 38 : 44 }

    var body: some View {
        VStack(spacing: 6) {
            header
            if let inspected = model.inspection {
                inspectionPanel(inspected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            } else {
                if !model.isSearching { sectionTabs }
                optionsBar
                if model.isCompactLayout && model.isSearching {
                    compactSearchContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                } else {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    if model.isSearching { searchKeys }
                }
            }
            controls
        }
        .padding(.horizontal, 10)
        .padding(.top, model.isCompactLayout ? 6 : 10)
        .padding(.bottom, 6)
        .background(KeyboardPalette.background.ignoresSafeArea())
        .tint(KeyboardPalette.accent)
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.beginSearch() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(model.isSearching ? KeyboardPalette.accent : KeyboardPalette.secondary)
                    Text(model.query.isEmpty ? (model.section == .emojis ? "Search emoji names" : "Search names, descriptions or U+…") : model.query)
                        .font(.system(size: 14, weight: model.query.isEmpty ? .regular : .medium))
                        .foregroundStyle(model.query.isEmpty ? KeyboardPalette.secondary : Color.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.isSearching {
                        RoundedRectangle(cornerRadius: 1).fill(KeyboardPalette.accent).frame(width: 2, height: 18)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: headerHeight)
                .keyboardKeySurface(radius: 12)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(model.isSearching ? KeyboardPalette.accent.opacity(0.65) : Color.clear, lineWidth: 1.5))
            }
            .buttonStyle(KeyboardPressStyle())
            .accessibilityLabel(model.section == .emojis ? "Search emoji sequences" : "Search Unicode characters")
            .accessibilityValue(model.query.isEmpty ? "No query" : model.query)
            .accessibilityIdentifier("keyboard.search")
            if model.isSearching {
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 19))
                            .foregroundStyle(KeyboardPalette.secondary)
                            .frame(width: 28, height: headerHeight)
                    }
                    .buttonStyle(KeyboardPressStyle())
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("keyboard.search.clear")
                }
                Button("Done") { model.endSearch() }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: headerHeight)
                    .buttonStyle(KeyboardPressStyle())
                    .accessibilityLabel("Close search keys")
            }
            // A single fixed trailing key in search, browsing and inspection.
            RepeatingDeleteKey(action: delete, isQuery: model.isSearching)
                .frame(width: 46, height: headerHeight)
        }
        .frame(height: headerHeight)
    }

    private var sectionTabs: some View {
        HStack(spacing: 2) {
            ForEach(KeyboardSection.allCases, id: \.self) { section in
                Button { model.section = section } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon).font(.system(size: 12, weight: .medium))
                        Text(section.rawValue).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: model.isCompactLayout ? 28 : 32)
                    .foregroundStyle(model.section == section ? KeyboardPalette.accent : KeyboardPalette.secondary)
                    .background(model.section == section ? KeyboardPalette.key : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if model.section == section {
                            Capsule().fill(KeyboardPalette.accent).frame(width: 18, height: 2).padding(.bottom, 3)
                        }
                    }
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
                .accessibilityIdentifier("keyboard.tab.\(section.rawValue.lowercased())")
            }
        }
        .padding(2)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var optionsBar: some View {
        HStack(spacing: 6) {
            Menu {
                Button { model.edition = .latest } label: { Label("Unicode \(UnicodeEdition.latest.catalog.version) · latest", systemImage: model.edition == .latest ? "checkmark" : "circle") }
                    .accessibilityIdentifier("keyboard.edition.latest")
                Button { model.edition = .draft } label: { Label("Unicode \(UnicodeEdition.draft.catalog.version)", systemImage: model.edition == .draft ? "checkmark" : "circle") }
                    .accessibilityIdentifier("keyboard.edition.draft")
            } label: {
                HStack(spacing: 4) {
                    Text("Unicode \(model.catalog.version)")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 7)
                .frame(height: 28)
            }
            .accessibilityLabel("Unicode edition")
            .accessibilityValue(model.editionValue)
            .accessibilityIdentifier("keyboard.edition")
            Rectangle().fill(KeyboardPalette.separator).frame(width: 1, height: 14)
            Menu {
                sortOption(.newestFirst, identifier: "newest")
                sortOption(.oldestFirst, identifier: "oldest")
                sortOption(.codePoint, identifier: "codepoint")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .medium))
                    Text(model.order.title)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 7)
                .frame(height: 28)
            }
            .accessibilityLabel("Character order")
            .accessibilityValue(model.orderValue)
            .accessibilityIdentifier("keyboard.order")
            Spacer(minLength: 0)
            Menu {
                Button { model.useUnicodeFonts = false } label: {
                    Label("Extra Unicode fonts: Off", systemImage: model.useUnicodeFonts ? "circle" : "checkmark")
                }
                .accessibilityIdentifier("keyboard.unicodeFonts.off")
                Button { model.useUnicodeFonts = true } label: {
                    Label("Extra Unicode fonts: On", systemImage: model.useUnicodeFonts ? "checkmark" : "circle")
                }
                .accessibilityIdentifier("keyboard.unicodeFonts.on")
                Text("Character previews only. Emoji and host-app fonts stay unchanged. Draft coverage is limited.")
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.useUnicodeFonts ? KeyboardPalette.accent : KeyboardPalette.secondary)
                    .frame(width: 28, height: 28)
                    .background(model.useUnicodeFonts ? KeyboardPalette.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            }
            .accessibilityLabel("Fonts: Extra Unicode fonts")
            .accessibilityValue(model.useUnicodeFonts ? "On" : "Off")
            .accessibilityIdentifier("keyboard.unicodeFonts")
            if let item = model.lastItem {
                Button { model.inspect(item) } label: {
                    Image(systemName: "info.circle").font(.system(size: 16)).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Inspect \(item.name)")
                .accessibilityIdentifier("keyboard.inspectLast")
                Button { toggleFavorite(item) } label: {
                    Image(systemName: isFavorite(item) ? "star.fill" : "star").font(.system(size: 15)).frame(width: 28, height: 28)
                }
                .accessibilityLabel(isFavorite(item) ? "Remove from favorites" : "Save to favorites")
                .disabled(!canToggleFavorite(item))
            }
        }
        .foregroundStyle(KeyboardPalette.secondary)
        .buttonStyle(KeyboardPressStyle())
        .frame(height: model.isCompactLayout ? 26 : 30)
    }

    private func sortOption(_ order: UnicodeSortOrder, identifier: String) -> some View {
        Button { model.order = order } label: {
            Label(order.title, systemImage: model.order == order ? "checkmark" : "circle")
        }
        .accessibilityIdentifier("keyboard.order.\(identifier)")
    }

    @ViewBuilder private var content: some View {
        if model.isSearching { searchResults }
        else {
            switch model.section {
            case .symbols:
                if model.discoveryLoading { ProgressView("Loading Unicode…").font(.system(size: 12)) }
                else { characterGrid(model.discoveryCharacters, pagination: model.loadSymbolsPage).id("symbols-\(model.editionValue)-\(model.orderValue)") }
            case .emojis:
                if model.discoveryLoading { ProgressView("Loading emoji…").font(.system(size: 12)) }
                else { emojiGrid(model.discoveryEmojis, pagination: model.loadEmojisPage).id("emojis-\(model.editionValue)-\(model.orderValue)") }
            case .blocks: blockContent
            case .saved: savedContent
            }
        }
    }

    /// Landscape leaves room for the host editor: two result rows beside the
    /// local query keys, sharing the same search header and document controls.
    private var compactSearchContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
            let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
            let available = max(2, width - 12)
            let resultsWidth = available * 0.35
            HStack(spacing: 12) {
                searchResults
                    .frame(width: resultsWidth, height: height)
                searchKeys
                    .frame(width: available - resultsWidth, height: height)
            }
            .frame(width: width, height: height)
        }
    }

    @ViewBuilder private var searchResults: some View {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 8) {
                Text(model.section == .emojis ? "Find an emoji sequence" : "Find your character").font(.system(size: 16, weight: .semibold))
                Text(model.section == .emojis ? "Try “woman technologist”, “flag Japan”, or a complete emoji" : "Try “arrow”, “heart”, “U+03C0”, or “decimal:960”")
                    .font(.system(size: 11)).foregroundStyle(KeyboardPalette.secondary).multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    ForEach(model.section == .emojis ? ["woman technologist", "flag Japan"] : ["arrow", "heart", "U+03C0"], id: \.self) { example in
                        Button(example) { model.query = example }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(KeyboardPalette.accent.opacity(0.08), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.searchInProgress {
            ProgressView("Searching…").font(.system(size: 12))
        } else if model.section == .emojis {
            if model.emojiResults.isEmpty { emptyState(icon: "face.smiling", title: "No emoji sequences found", detail: "Try a shorter name, a group, or a complete emoji.") }
            else { emojiGrid(model.emojiResults) }
        } else if model.results.isEmpty {
            emptyState(icon: "magnifyingglass", title: "No characters found", detail: "Try a shorter name or a code point such as U+2192.")
        } else { characterGrid(model.results) }
    }

    @ViewBuilder private var blockContent: some View {
        if let block = model.selectedBlock {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Button { model.closeBlock() } label: { Label("All blocks", systemImage: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(KeyboardPressStyle())
                    Spacer(minLength: 4)
                    Text(block.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(block.rangeLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(KeyboardPalette.secondary).lineLimit(1)
                }
                .frame(height: 23)
                if model.blockLoading && model.blockCharacters.isEmpty { ProgressView("Loading block…").font(.system(size: 12)) }
                else if model.blockCharacters.isEmpty { emptyState(icon: "square.dashed", title: "No assigned characters", detail: "This block is reserved in Unicode \(model.catalog.version).") }
                else { characterGrid(model.blockCharacters, pagination: model.loadBlockPage).id("block-\(block.id)-\(model.editionValue)-\(model.orderValue)") }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.catalog.blocks) { block in
                        Button { model.openBlock(block) } label: {
                            HStack(spacing: 10) {
                                Text(block.symbol).font(Font(UnicodeFontSupport.font(for: block.symbol, size: 21, enabled: model.useUnicodeFonts))).foregroundStyle(KeyboardPalette.accent).frame(width: 31)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                                    Text(block.rangeLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(KeyboardPalette.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(KeyboardPalette.secondary)
                            }
                            .padding(.horizontal, 12).frame(height: model.isCompactLayout ? 44 : 50)
                            .keyboardKeySurface(radius: 11)
                        }
                        .buttonStyle(KeyboardPressStyle())
                        .accessibilityLabel("Browse \(block.name), \(block.rangeLabel)")
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var savedContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                savedTab("Favorites", icon: "star", selected: model.showFavorites) { model.showFavorites = true }
                savedTab("Recent", icon: "clock", selected: !model.showFavorites) { model.showFavorites = false }
                Spacer(minLength: 0)
                Text("On this keyboard").font(.system(size: 9)).foregroundStyle(KeyboardPalette.secondary)
            }
            let characters = model.sorted(model.showFavorites ? store.favoriteCharacters(in: model.catalog) : store.recentCharacters(in: model.catalog))
            let emojis = model.sorted(model.showFavorites ? store.favoriteEmojiEntries(in: model.emojiCatalog) : store.recentEmojiEntries(in: model.emojiCatalog))
            if characters.isEmpty && emojis.isEmpty {
                emptyState(icon: model.showFavorites ? "star" : "clock", title: model.showFavorites ? "Keep your go-to characters" : "Your recent entries appear here", detail: model.showFavorites ? "Hold a character or emoji, then tap Save." : "Insert a character or complete emoji to keep it close.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if !characters.isEmpty {
                            Text("Characters").font(.system(size: 11, weight: .semibold)).foregroundStyle(KeyboardPalette.secondary)
                            characterTiles(characters)
                        }
                        if !emojis.isEmpty {
                            Text("Emoji sequences").font(.system(size: 11, weight: .semibold)).foregroundStyle(KeyboardPalette.secondary)
                            emojiTiles(emojis)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func savedTab(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).frame(height: 26)
                .foregroundStyle(selected ? KeyboardPalette.accent : KeyboardPalette.secondary)
                .background(selected ? KeyboardPalette.accent.opacity(0.09) : Color.clear, in: Capsule())
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func characterGrid(_ characters: [UnicodeCharacter], pagination: (() -> Void)? = nil) -> some View {
        ScrollView { characterTiles(characters, pagination: pagination).padding(.bottom, 2) }
            .scrollIndicators(.hidden)
    }
    private func emojiGrid(_ emojis: [UnicodeEmojiEntry], pagination: (() -> Void)? = nil) -> some View {
        ScrollView { emojiTiles(emojis, pagination: pagination).padding(.bottom, 2) }
            .scrollIndicators(.hidden)
    }
    private func characterTiles(_ characters: [UnicodeCharacter], pagination: (() -> Void)? = nil) -> some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(characters) { character in
                InspectableCharacterKey(item: .character(character), favorite: store.isFavorite(character.codePoint), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, insert: { insert(character) }, inspect: { model.inspect(.character(character)) })
                    .frame(height: keyHeight)
                    .onAppear { if character.id == characters.last?.id { pagination?() } }
            }
        }
    }
    private func emojiTiles(_ emojis: [UnicodeEmojiEntry], pagination: (() -> Void)? = nil) -> some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(emojis) { emoji in
                InspectableCharacterKey(item: .emoji(emoji), favorite: store.isFavoriteEmoji(emoji.id), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, insert: { insertEmoji(emoji) }, inspect: { model.inspect(.emoji(emoji)) })
                    .frame(height: keyHeight)
                    .onAppear { if emoji.id == emojis.last?.id { pagination?() } }
            }
        }
    }

    private func isFavorite(_ item: KeyboardItem) -> Bool {
        switch item {
        case .character(let character): return store.isFavorite(character.codePoint)
        case .emoji(let emoji): return store.isFavoriteEmoji(emoji.id)
        }
    }
    private func toggleFavorite(_ item: KeyboardItem) {
        switch item {
        case .character(let character): store.toggleFavorite(character.codePoint)
        case .emoji(let emoji): store.toggleFavoriteEmoji(emoji)
        }
    }
    private func canToggleFavorite(_ item: KeyboardItem) -> Bool {
        if case .character(let character) = item {
            return character.category != "Cn" || isFavorite(item)
        }
        return true
    }

    private func inspectionPanel(_ item: KeyboardItem) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.closeInspection() } label: { Label("Back", systemImage: "chevron.left").font(.system(size: 12, weight: .semibold)) }
                    .accessibilityLabel("Close Unicode properties")
                    .accessibilityIdentifier("keyboard.properties.close")
                Spacer(minLength: 0)
                Text("Unicode properties").font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("keyboard.properties")
                Spacer(minLength: 0)
                Button { toggleFavorite(item) } label: {
                    Label(isFavorite(item) ? "Saved" : "Save", systemImage: isFavorite(item) ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .medium))
                }
                .accessibilityLabel(isFavorite(item) ? "Remove from favorites" : "Save to favorites")
                .accessibilityIdentifier("keyboard.properties.favorite")
                .disabled(!canToggleFavorite(item))
            }
            .frame(height: 36)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.displayText).font(previewFont(item, size: 36)).lineLimit(2).minimumScaleFactor(0.5)
                            .frame(width: 64).frame(minHeight: 64)
                            .background(KeyboardPalette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                        Text(item.name).font(.system(size: 17, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("keyboard.properties.name")
                    }
                    inspectionProperties(item)
                    Text("Names and properties stay available even when your iOS font cannot display a glyph. Tap a key to insert its original text; inspecting never inserts it.")
                        .font(.system(size: 11)).foregroundStyle(KeyboardPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .keyboardKeySurface(radius: 14)
        }
    }

    @ViewBuilder private func inspectionProperties(_ item: KeyboardItem) -> some View {
        switch item {
        case .character(let character):
            if let source = UnicodeFontSupport.sourceName(for: character.displayText, size: 36, enabled: model.useUnicodeFonts) {
                property("Preview font", value: source, identifier: "fontSource")
            }
            property("Code point", value: character.codePointLabel, identifier: "codepoints", monospaced: true)
            Text(character.detail.isEmpty ? "No additional annotation is listed. The official Unicode name and properties are shown below." : character.detail)
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("keyboard.properties.description")
            property("Unicode age", value: character.age.map { "Unicode \($0)" } ?? (character.category == "Cn" ? "Unassigned" : "Age pending"), identifier: "age")
            property("Block", value: character.blockName, identifier: "block")
            property("Category", value: "\(character.categoryName) (\(character.category))", identifier: "category")
            property("UTF-8", value: utf8(character.text), identifier: "utf8", monospaced: true)
            property("Decimal", value: String(character.codePoint), identifier: "decimal", monospaced: true)
            property("Script", value: character.script ?? "Not listed", identifier: "script")
            property("Bidirectional class", value: character.bidirectionalClass ?? "Not listed", identifier: "bidi", monospaced: true)
            property("Combining class", value: character.combiningClass.map(String.init) ?? "Not listed", identifier: "combiningClass", monospaced: true)
            property("Decomposition", value: character.decomposition.flatMap { $0.isEmpty ? nil : $0 } ?? "None listed", identifier: "decomposition", monospaced: true)
        case .emoji(let emoji):
            property("Code points", value: emoji.codePointLabel, identifier: "codepoints", monospaced: true)
            Text("Fully-qualified emoji sequence: \(emoji.name). All \(emoji.codePoints.count) Unicode scalars, including any joiners, variation selectors and modifiers, are inserted together.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("keyboard.properties.description")
            property("Emoji introduction", value: "Emoji \(emoji.emojiVersion)", identifier: "emojiVersion")
            property("Newest component age", value: "Unicode \(emoji.unicodeVersion)", identifier: "age")
            property("Category", value: "Fully-qualified emoji sequence", identifier: "category")
            property("Group", value: emoji.group, identifier: "group")
            property("Subgroup", value: emoji.subgroup, identifier: "subgroup")
            property("UTF-8", value: utf8(emoji.text), identifier: "utf8", monospaced: true)
            Text("Sequence components").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            ForEach(Array(emoji.codePoints.enumerated()), id: \.offset) { index, point in
                let character = model.catalog.character(at: point)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(index + 1). \(String(format: "U+%04X", point))").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(character?.name.capitalized ?? "Unicode scalar").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keyboard.properties.component.\(index).name")
                    if let character {
                        Text("\(character.categoryName) · \(character.age.map { "Unicode \($0)" } ?? "Age not listed")")
                            .font(.system(size: 10)).foregroundStyle(KeyboardPalette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(KeyboardPalette.background, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func previewFont(_ item: KeyboardItem, size: CGFloat) -> Font {
        switch item {
        case .character(let character):
            return Font(UnicodeFontSupport.font(for: character.displayText, size: size, enabled: model.useUnicodeFonts))
        case .emoji:
            return .system(size: size)
        }
    }

    private func property(_ title: String, value: String, identifier: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(KeyboardPalette.secondary)
            Text(value).font(.system(size: 13, design: monospaced ? .monospaced : .default))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("keyboard.properties.\(identifier)")
        }
    }
    private func utf8(_ text: String) -> String {
        text.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(KeyboardPalette.accent)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(KeyboardPalette.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchKeys: some View {
        VStack(spacing: 5) {
            searchKeyRow(Array("1234567890").map(String.init))
            searchKeyRow(Array("qwertyuiop").map(String.init))
            searchKeyRow(Array("asdfghjkl").map(String.init), inset: 10)
            searchKeyRow(["+", "z", "x", "c", "v", "b", "n", "m", ":", "-"], inset: 0)
        }
    }
    private func searchKeyRow(_ keys: [String], inset: CGFloat = 0) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key in
                Button { model.appendQuery(key) } label: {
                    Text(key).font(.system(size: model.isCompactLayout ? 16 : 18)).foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity).frame(height: model.isCompactLayout ? 28 : 34)
                        .keyboardKeySurface(radius: 7)
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityLabel(key == "+" ? "Plus" : key == ":" ? "Colon" : key == "-" ? "Hyphen" : key)
                .accessibilityIdentifier("keyboard.query.\(key)")
            }
        }
        .padding(.horizontal, inset)
    }

    private var controls: some View {
        HStack(spacing: 7) {
            if model.needsInputModeSwitchKey {
                InputModeSwitchKey(controller: controller).frame(width: 46, height: controlHeight)
            } else {
                Button { controller?.dismissKeyboard() } label: {
                    Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 17))
                        .frame(width: 46, height: controlHeight)
                        .keyboardKeySurface()
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityLabel("Dismiss keyboard")
            }
            Button(action: space) {
                Text(model.isSearching ? "Search space" : "space").font(.system(size: 14, weight: .medium)).foregroundStyle(KeyboardPalette.secondary)
                    .frame(maxWidth: .infinity).frame(height: controlHeight)
                    .keyboardKeySurface()
            }
            .buttonStyle(KeyboardPressStyle())
            .accessibilityLabel(model.isSearching ? "Add space to search" : "Insert space")
            .accessibilityIdentifier("keyboard.space")
            Button(action: returnKey) {
                Text(model.inspection != nil ? "Back" : model.isSearching ? "Done" : model.returnTitle)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(KeyboardPalette.actionText)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: model.isPadLayout ? 112 : 84, height: controlHeight)
                    .background(KeyboardPalette.action, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(KeyboardPressStyle())
            .accessibilityLabel(model.inspection != nil ? "Close Unicode properties" : model.isSearching ? "Close search keys" : "\(model.returnTitle) key")
            .accessibilityIdentifier("keyboard.return")
        }
    }
}

/// UIKit owns touch arbitration: a recognized long press cancels the button tap,
/// and sustained pointer hover only opens properties. No inspection inserts text.
private struct InspectableCharacterKey: UIViewRepresentable {
    let item: KeyboardItem
    let favorite: Bool
    let compact: Bool
    let useUnicodeFonts: Bool
    let insert: () -> Void
    let inspect: () -> Void

    func makeUIView(context: Context) -> InspectableKeyButton { InspectableKeyButton() }
    func updateUIView(_ uiView: InspectableKeyButton, context: Context) {
        uiView.configure(item: item, favorite: favorite, compact: compact, useUnicodeFonts: useUnicodeFonts, insert: insert, inspect: inspect)
    }
}

private final class InspectableKeyButton: UIControl {
    private let glyph = UILabel()
    private let code = UILabel()
    private let age = UILabel()
    private let star = UIImageView(image: UIImage(systemName: "star.fill"))
    private var glyphHeight: NSLayoutConstraint!
    private var stackTop: NSLayoutConstraint!
    private var stackBottom: NSLayoutConstraint!
    private var insertAction: (() -> Void)?
    private var inspectAction: (() -> Void)?
    private var hoverTimer: Timer?
    private var suppressTap = false
    private lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))

    init() {
        super.init(frame: .zero)
        backgroundColor = KeyboardPalette.keyUI
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.08
        isAccessibilityElement = true
        accessibilityTraits = .button
        glyph.textAlignment = .center
        glyph.adjustsFontSizeToFitWidth = true
        glyph.minimumScaleFactor = 0.45
        glyph.lineBreakMode = .byClipping
        code.textAlignment = .center
        code.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        code.adjustsFontSizeToFitWidth = true
        code.minimumScaleFactor = 0.7
        code.textColor = .secondaryLabel
        code.lineBreakMode = .byTruncatingTail
        age.textAlignment = .center
        age.font = .systemFont(ofSize: 9, weight: .regular)
        age.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [glyph, code, age])
        // Touches must reach this control rather than the decorative label stack.
        stack.isUserInteractionEnabled = false
        glyph.isUserInteractionEnabled = false
        code.isUserInteractionEnabled = false
        age.isUserInteractionEnabled = false
        star.isUserInteractionEnabled = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        star.translatesAutoresizingMaskIntoConstraints = false
        star.tintColor = KeyboardPalette.accentUI
        glyphHeight = glyph.heightAnchor.constraint(equalToConstant: 34)
        stackTop = stack.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        stackBottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        addSubview(star)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackTop, stackBottom, glyphHeight,
            code.heightAnchor.constraint(equalToConstant: 11),
            star.widthAnchor.constraint(equalToConstant: 9),
            star.heightAnchor.constraint(equalToConstant: 9),
            star.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            star.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        ])
        hold.minimumPressDuration = 0.4
        hold.allowableMovement = 10
        hold.cancelsTouchesInView = true
        addGestureRecognizer(hold)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        addTarget(self, action: #selector(touchBegan), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (key: InspectableKeyButton, _: UITraitCollection) in
            key.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: key.traitCollection).cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 64, height: 72) }
    override var isHighlighted: Bool { didSet { backgroundColor = isHighlighted ? KeyboardPalette.pressedUI : KeyboardPalette.keyUI } }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath
    }

    func configure(item: KeyboardItem, favorite: Bool, compact: Bool, useUnicodeFonts: Bool, insert: @escaping () -> Void, inspect: @escaping () -> Void) {
        glyph.text = item.displayText
        glyphHeight.constant = compact ? 24 : 34
        stackTop.constant = compact ? 5 : 6
        stackBottom.constant = compact ? -5 : -6
        if case .character(let character) = item {
            let size: CGFloat = character.isInvisible ? 17 : compact ? 24 : 32
            glyph.font = UnicodeFontSupport.font(for: character.displayText, size: size, enabled: useUnicodeFonts)
            accessibilityValue = UnicodeFontSupport.sourceName(for: character.displayText, size: size, enabled: useUnicodeFonts).map { "Preview font: \($0)" }
        } else {
            glyph.font = .systemFont(ofSize: compact ? 24 : 32)
            accessibilityValue = nil
        }
        code.text = item.footer
        age.text = item.ageLabel
        star.isHidden = !favorite
        insertAction = insert
        inspectAction = inspect
        accessibilityLabel = "\(item.name), \(item.codePointLabel), \(item.ageLabel)"
        accessibilityHint = "Tap to insert. Hold or keep the pointer here to inspect Unicode properties and description."
        accessibilityIdentifier = item.keyIdentifier
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Inspect Unicode properties") { [weak self] _ in
            self?.inspectAction?()
            return self != nil
        }]
    }
    override func accessibilityActivate() -> Bool {
        insertAction?()
        return true
    }
    @objc private func touchBegan() {
        suppressTap = false
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
    @objc private func tapped() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard !suppressTap, hold.state != .began, hold.state != .changed else { return }
        insertAction?()
    }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            suppressTap = true
            hoverTimer?.invalidate()
            hoverTimer = nil
            inspectAction?()
        }
    }
    @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began:
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
                guard let self, self.window != nil else { return }
                self.suppressTap = true
                self.inspectAction?()
            }
        case .ended, .cancelled, .failed:
            hoverTimer?.invalidate()
            hoverTimer = nil
        default: break
        }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { hoverTimer?.invalidate(); hoverTimer = nil }
        super.willMove(toWindow: newWindow)
    }
    deinit { hoverTimer?.invalidate() }
}

/// Preserve Apple's standard press-and-hold input-mode menu.
private struct InputModeSwitchKey: UIViewRepresentable {
    weak var controller: KeyboardViewController?
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        button.tintColor = .label
        button.backgroundColor = KeyboardPalette.keyUI
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.5
        button.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: button.traitCollection).cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0
        button.layer.shadowOpacity = 0.06
        button.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (key: UIButton, _: UITraitCollection) in
            key.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: key.traitCollection).cgColor
        }
        button.accessibilityLabel = "Next keyboard"
        button.accessibilityHint = "Hold to choose a keyboard"
        button.accessibilityIdentifier = "keyboard.globe"
        button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }
    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: uiView.traitCollection).cgColor
    }
}

private struct RepeatingDeleteKey: UIViewRepresentable {
    let action: () -> Void
    let isQuery: Bool
    func makeUIView(context: Context) -> RepeatingDeleteButton { RepeatingDeleteButton() }
    func updateUIView(_ uiView: RepeatingDeleteButton, context: Context) {
        uiView.action = action
        uiView.accessibilityLabel = isQuery ? "Delete search character" : "Delete backward"
    }
}

private final class RepeatingDeleteButton: UIButton {
    var action: (() -> Void)?
    private var delayTimer: Timer?
    private var repeatTimer: Timer?
    init() {
        super.init(frame: .zero)
        setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        tintColor = .label
        backgroundColor = KeyboardPalette.keyUI
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.06
        accessibilityIdentifier = "keyboard.delete"
        accessibilityHint = "Hold to delete repeatedly"
        addTarget(self, action: #selector(startDeleting), for: .touchDown)
        addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (key: RepeatingDeleteButton, _: UITraitCollection) in
            key.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: key.traitCollection).cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHighlighted: Bool { didSet { backgroundColor = isHighlighted ? KeyboardPalette.pressedUI : KeyboardPalette.keyUI } }
    override func accessibilityActivate() -> Bool { action?(); return true }
    @objc private func startDeleting() {
        stopDeleting()
        action?()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.action?()
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in self?.action?() }
        }
    }
    @objc private func stopDeleting() {
        delayTimer?.invalidate()
        repeatTimer?.invalidate()
        delayTimer = nil
        repeatTimer = nil
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { stopDeleting() }
        super.willMove(toWindow: newWindow)
    }
    deinit { delayTimer?.invalidate(); repeatTimer?.invalidate() }
}
