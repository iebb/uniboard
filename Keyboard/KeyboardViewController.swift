import SwiftUI
import UIKit

/// Remote keyboard scenes can retain a stale interfaceOrientation after the
/// host rotates. Phone layout follows the actual view width, never its height.
enum KeyboardLayoutPolicy {
    struct Metrics {
        let isCompactLayout: Bool
        let height: CGFloat
    }

    static func metrics(viewWidth: CGFloat, displaySize: CGSize?, sceneHeight: CGFloat?, isPad: Bool,
                        compactVertical: Bool, isSearching: Bool, isInspecting: Bool) -> Metrics {
        let edges: (short: CGFloat, long: CGFloat)? = displaySize.flatMap { size in
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
            return (min(size.width, size.height), max(size.width, size.height))
        }
        let compact: Bool
        if isPad { compact = false }
        else if let edges, viewWidth.isFinite, viewWidth > 0 {
            compact = viewWidth > edges.short + max(24, edges.short * 0.10)
        } else {
            compact = compactVertical
        }
        let expanded = isSearching || isInspecting
        let target: CGFloat = isPad ? (expanded ? 380 : 340) : compact ? 220 : (expanded ? 340 : 300)
        let effectiveHeight: CGFloat?
        if !isPad, let edges {
            effectiveHeight = compact ? edges.short : edges.long
        } else {
            effectiveHeight = sceneHeight
        }
        let fraction: CGFloat = isPad ? 0.50 : compact ? 0.60 : isInspecting ? 0.50 : isSearching ? 0.55 : 0.47
        let height = effectiveHeight.flatMap { $0.isFinite && $0 > 0 ? min(target, $0 * fraction) : nil } ?? target
        return Metrics(isCompactLayout: compact, height: height)
    }
}

/// Query keys edit only the extension's local search. Insertion always sends the
/// original scalar or complete emoji sequence to the host's document proxy.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var keyboardHeight: NSLayoutConstraint?
    private var hostingController: UIHostingController<UnicodeKeyboardView>?

    override func loadView() {
        // Use the keyboard's system blur and tint instead of stacking another
        // full-size material behind the control glass.
        view = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
        NotificationCenter.default.addObserver(self, selector: #selector(updateBackdrop), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        updateBackdrop()
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
        host.view.isOpaque = false
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
        let height = view.heightAnchor.constraint(equalToConstant: 300)
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

    @objc private func updateBackdrop() {
        let opaque = UIAccessibility.isReduceTransparencyEnabled
        view.backgroundColor = opaque ? KeyboardPalette.backgroundUI : .clear
        view.isOpaque = opaque
    }

    private func updateKeyboardHeight() {
        let pad = traitCollection.userInterfaceIdiom == .pad
        let scene = view.window?.windowScene
        let metrics = KeyboardLayoutPolicy.metrics(
            viewWidth: view.bounds.width, displaySize: scene?.screen.bounds.size,
            sceneHeight: scene?.coordinateSpace.bounds.height, isPad: pad,
            compactVertical: traitCollection.verticalSizeClass == .compact,
            isSearching: model.isSearching, isInspecting: model.inspection != nil
        )
        if model.isCompactLayout != metrics.isCompactLayout { model.isCompactLayout = metrics.isCompactLayout }
        if model.isPadLayout != pad { model.isPadLayout = pad }
        if keyboardHeight?.constant != metrics.height { keyboardHeight?.constant = metrics.height }
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

    deinit { NotificationCenter.default.removeObserver(self) }
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
    static let borderUI = UIColor { traits in
        UIColor.separator.resolvedColor(with: traits).withAlphaComponent(traits.accessibilityContrast == .high ? 0.65 : 0.16)
    }
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
        modifier(KeyboardKeySurface(radius: radius))
    }

    func keyboardControlSurface(radius: CGFloat = 12) -> some View {
        modifier(KeyboardControlSurface(radius: radius))
    }
}

private struct KeyboardKeySurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(KeyboardPalette.separator, lineWidth: contrast == .increased ? 1 : 0.4))
    }
}

/// Glass belongs to navigation controls, while the character grid stays quiet.
private struct KeyboardControlSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.keyboardKeySurface(radius: radius)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(contrast == .increased ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 1))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(KeyboardPalette.separator, lineWidth: contrast == .increased ? 1 : 0.5))
        }
    }
}

private struct KeyboardTray: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            KeyboardPalette.background
        } else {
            Color.clear
        }
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
        [GridItem(.adaptive(minimum: model.isPadLayout ? 70 : 58, maximum: 92), spacing: 6)]
    }
    private var keyHeight: CGFloat { model.isCompactLayout ? 50 : model.isPadLayout ? 60 : 56 }
    private var headerHeight: CGFloat { model.isCompactLayout ? 36 : 40 }
    private var controlHeight: CGFloat { model.isCompactLayout ? 34 : 38 }

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            if let inspected = model.inspection {
                inspectionPanel(inspected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            } else {
                if model.isSearching {
                    searchContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                } else {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            }
            controls
        }
        .padding(.horizontal, 8)
        .padding(.top, model.isCompactLayout ? 4 : 6)
        .padding(.bottom, 6)
        .background(KeyboardTray().ignoresSafeArea())
        .tint(KeyboardPalette.accent)
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    @ViewBuilder private var toolbar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 4) { header }
        } else {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { model.beginSearch() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(model.isSearching ? KeyboardPalette.accent : KeyboardPalette.secondary)
                        Text(model.query.isEmpty ? (model.section == .emojis ? "Search emoji" : "Search Unicode") : model.query)
                            .font(.system(size: 14, weight: model.query.isEmpty ? .regular : .medium))
                            .foregroundStyle(model.query.isEmpty ? KeyboardPalette.secondary : Color.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if model.isSearching {
                            RoundedRectangle(cornerRadius: 1).fill(KeyboardPalette.accent).frame(width: 2, height: 16)
                        }
                    }
                    .padding(.leading, 11).padding(.trailing, 8)
                    .frame(maxWidth: .infinity).frame(height: headerHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityLabel(model.section == .emojis ? "Search emoji sequences" : "Search Unicode characters")
                .accessibilityValue(model.query.isEmpty ? "No query" : model.query)
                .accessibilityIdentifier("keyboard.search")
                if model.isSearching && !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            .foregroundStyle(KeyboardPalette.secondary)
                            .frame(width: 30, height: headerHeight)
                    }
                    .buttonStyle(KeyboardPressStyle())
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("keyboard.search.clear")
                }
            }
            .frame(height: headerHeight)
            .keyboardControlSurface()
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(model.isSearching ? KeyboardPalette.accent.opacity(0.55) : Color.clear, lineWidth: 1))

            sectionMenu
            optionsMenu
            // A single fixed trailing key in search, browsing and inspection.
            RepeatingDeleteKey(action: delete, isQuery: model.isSearching)
                .frame(width: 42, height: headerHeight)
                .keyboardControlSurface()
        }
        .frame(height: headerHeight)
    }

    private var sectionMenu: some View {
        Menu {
            ForEach(KeyboardSection.allCases, id: \.self) { section in
                Button {
                    model.closeInspection()
                    if section == .blocks || section == .saved { model.endSearch() }
                    model.section = section
                } label: {
                    Label(section.rawValue, systemImage: model.section == section ? "checkmark" : section.icon)
                }
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
                .accessibilityIdentifier("keyboard.tab.\(section.rawValue.lowercased())")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.section.icon).font(.system(size: 14, weight: .medium))
                if !model.isSearching && !model.isCompactLayout {
                    Text(model.section.rawValue).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(KeyboardPalette.accent)
            .frame(width: model.isSearching || model.isCompactLayout ? 40 : 86, height: headerHeight)
            .keyboardControlSurface()
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel("Keyboard section")
        .accessibilityValue(model.section.rawValue.lowercased())
        .accessibilityIdentifier("keyboard.section")
    }

    private var optionsMenu: some View {
        Menu {
            Menu {
                Button { model.edition = .latest } label: { Label("Unicode \(UnicodeEdition.latest.catalog.version) · latest", systemImage: model.edition == .latest ? "checkmark" : "circle") }
                    .accessibilityIdentifier("keyboard.edition.latest")
                Button { model.edition = .draft } label: { Label("Unicode \(UnicodeEdition.draft.catalog.version)", systemImage: model.edition == .draft ? "checkmark" : "circle") }
                    .accessibilityIdentifier("keyboard.edition.draft")
            } label: {
                Label("Unicode \(model.catalog.version)", systemImage: "books.vertical")
            }
            .accessibilityLabel("Unicode edition")
            .accessibilityValue(model.editionValue)
            .accessibilityIdentifier("keyboard.edition")
            Menu {
                sortOption(.newestFirst, identifier: "newest")
                sortOption(.oldestFirst, identifier: "oldest")
                sortOption(.codePoint, identifier: "codepoint")
            } label: {
                Label("Order: \(model.order.title)", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Character order")
            .accessibilityValue(model.orderValue)
            .accessibilityIdentifier("keyboard.order")
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
                Label("Extra Unicode fonts: \(model.useUnicodeFonts ? "On" : "Off")", systemImage: "textformat")
            }
            .accessibilityLabel("Fonts: Extra Unicode fonts")
            .accessibilityValue(model.useUnicodeFonts ? "On" : "Off")
            .accessibilityIdentifier("keyboard.unicodeFonts")
            if let item = model.lastItem {
                Section("Last inserted or inspected") {
                    Button { model.inspect(item) } label: {
                        Label("Inspect \(item.name)", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("keyboard.inspectLast")
                    Button { toggleFavorite(item) } label: {
                        Label(isFavorite(item) ? "Remove from favorites" : "Save to favorites", systemImage: isFavorite(item) ? "star.fill" : "star")
                    }
                    .disabled(!canToggleFavorite(item))
                }
            }
            Text("Hold a key for Unicode properties.")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: headerHeight)
                .keyboardControlSurface()
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel("Keyboard options")
        .accessibilityValue("\(model.editionValue), \(model.orderValue), extra fonts \(model.useUnicodeFonts ? "on" : "off")")
        .accessibilityIdentifier("keyboard.options")
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

    /// Short, wide scenes put results beside the query keys. Narrow scenes keep
    /// a complete result key visible by fitting only the query row heights.
    private var searchContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
            let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
            if model.isCompactLayout || (model.isPadLayout && width >= 520 && height < keyHeight + 154) {
                let available = max(2, width - 12)
                let resultsWidth = available * 0.35
                HStack(spacing: 12) {
                    searchResults
                        .frame(width: resultsWidth, height: height)
                    queryKeys(rowHeight: max(16, min(model.isCompactLayout ? 28 : 34, (height - 12) / 4)))
                        .frame(width: available - resultsWidth, height: height)
                }
                .frame(width: width, height: height)
            } else {
                let rowHeight = max(16, min(34, (height - keyHeight - 18) / 4))
                let queryHeight = rowHeight * 4 + 12
                VStack(spacing: 6) {
                    searchResults
                        .frame(width: width, height: max(0, height - queryHeight - 6))
                    queryKeys(rowHeight: rowHeight)
                        .frame(width: width, height: queryHeight)
                }
                .frame(width: width, height: height)
            }
        }
        .clipped()
    }

    private var emptySearchSuggestions: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                Text(model.section == .emojis ? "Find an emoji sequence" : "Find your character").font(.system(size: 13, weight: .semibold))
                if geometry.size.height >= 48 {
                    Text(model.section == .emojis ? "Try “woman technologist”, “flag Japan”, or a complete emoji" : "Try “arrow”, “heart”, “U+03C0”, or “decimal:960”")
                        .font(.system(size: 11)).foregroundStyle(KeyboardPalette.secondary).multilineTextAlignment(.center).lineLimit(2)
                }
                if geometry.size.height >= 78 && !model.isCompactLayout {
                    HStack(spacing: 6) {
                        ForEach(model.section == .emojis ? ["woman technologist", "flag Japan"] : ["arrow", "heart", "U+03C0"], id: \.self) { example in
                            Button(example) { model.query = example }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(KeyboardPalette.accent.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(width: max(0, geometry.size.width), height: max(0, geometry.size.height))
        }
    }

    @ViewBuilder private var searchResults: some View {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptySearchSuggestions
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
                LazyVStack(spacing: 6) {
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
                            .padding(.horizontal, 10).frame(height: 44)
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
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(characters) { character in
                InspectableCharacterKey(item: .character(character), favorite: store.isFavorite(character.codePoint), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, insert: { insert(character) }, inspect: { model.inspect(.character(character)) })
                    .frame(height: keyHeight)
                    .onAppear { if character.id == characters.last?.id { pagination?() } }
            }
        }
    }
    private func emojiTiles(_ emojis: [UnicodeEmojiEntry], pagination: (() -> Void)? = nil) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
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

    private func queryKeys(rowHeight: CGFloat) -> some View {
        VStack(spacing: 4) {
            searchKeyRow(Array("1234567890").map(String.init), rowHeight: rowHeight)
            searchKeyRow(Array("qwertyuiop").map(String.init), rowHeight: rowHeight)
            searchKeyRow(Array("asdfghjkl").map(String.init), rowHeight: rowHeight, inset: 10)
            searchKeyRow(["+", "z", "x", "c", "v", "b", "n", "m", ":", "-"], rowHeight: rowHeight)
        }
    }
    private func searchKeyRow(_ keys: [String], rowHeight: CGFloat, inset: CGFloat = 0) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Button { model.appendQuery(key) } label: {
                    Text(key).font(.system(size: model.isCompactLayout ? 16 : 18)).foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity).frame(height: rowHeight)
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
    private let star = UIImageView(image: UIImage(systemName: "star.fill"))
    private var glyphHeight: NSLayoutConstraint!
    private var insertAction: (() -> Void)?
    private var inspectAction: (() -> Void)?
    private var hoverTimer: Timer?
    private var suppressTap = false
    private lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))

    init() {
        super.init(frame: .zero)
        backgroundColor = KeyboardPalette.keyUI
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.4
        layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: traitCollection).cgColor
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
        let stack = UIStackView(arrangedSubviews: [glyph, code])
        // Touches must reach this control rather than the decorative label stack.
        stack.isUserInteractionEnabled = false
        glyph.isUserInteractionEnabled = false
        code.isUserInteractionEnabled = false
        star.isUserInteractionEnabled = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        star.translatesAutoresizingMaskIntoConstraints = false
        star.tintColor = KeyboardPalette.accentUI
        glyphHeight = glyph.heightAnchor.constraint(equalToConstant: 34)
        addSubview(star)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor), glyphHeight,
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
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (key: InspectableKeyButton, _: UITraitCollection) in
            key.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: key.traitCollection).cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 58, height: 56) }
    override var isHighlighted: Bool { didSet { backgroundColor = isHighlighted ? KeyboardPalette.pressedUI : KeyboardPalette.keyUI } }
    func configure(item: KeyboardItem, favorite: Bool, compact: Bool, useUnicodeFonts: Bool, insert: @escaping () -> Void, inspect: @escaping () -> Void) {
        glyph.text = item.displayText
        glyphHeight.constant = compact ? 26 : 34
        if case .character(let character) = item {
            let size: CGFloat = character.isInvisible ? 17 : compact ? 24 : 32
            glyph.font = UnicodeFontSupport.font(for: character.displayText, size: size, enabled: useUnicodeFonts)
            accessibilityValue = UnicodeFontSupport.sourceName(for: character.displayText, size: size, enabled: useUnicodeFonts).map { "Preview font: \($0)" }
        } else {
            glyph.font = .systemFont(ofSize: compact ? 24 : 32)
            accessibilityValue = nil
        }
        code.text = item.footer
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
        button.registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (key: UIButton, _: UITraitCollection) in
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
        backgroundColor = .clear
        isOpaque = false
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        accessibilityIdentifier = "keyboard.delete"
        accessibilityHint = "Hold to delete repeatedly"
        addTarget(self, action: #selector(startDeleting), for: .touchDown)
        addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHighlighted: Bool { didSet { backgroundColor = isHighlighted ? UIColor.tertiarySystemFill : .clear } }
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
