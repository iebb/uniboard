import SwiftUI
import UIKit

/// The extension never creates a text field: its own keys edit the search query,
/// while character selections go directly to the host app's document proxy.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var keyboardHeight: NSLayoutConstraint?
    private var hostingController: UIHostingController<UnicodeKeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KeyboardPalette.backgroundUI
        let root = UnicodeKeyboardView(
            model: model,
            store: CharacterStore.shared,
            controller: self,
            insert: { [weak self] character in
                self?.textDocumentProxy.insertText(character.text)
                CharacterStore.shared.recordUse(character.codePoint)
                self?.model.lastCharacter = character
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
        let height = view.heightAnchor.constraint(equalToConstant: 370)
        height.priority = .init(999)
        height.isActive = true
        keyboardHeight = height
        model.searchModeChanged = { [weak self] in self?.updateKeyboardHeight() }
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
        let isLandscape = view.window?.windowScene?.interfaceOrientation.isLandscape == true
        let isPad = traitCollection.userInterfaceIdiom == .pad
        let height: CGFloat
        if isPad {
            height = model.isSearching ? 470 : 390
        } else if isLandscape {
            height = model.isSearching ? 360 : 270
        } else {
            height = model.isSearching ? 460 : 370
        }
        if keyboardHeight?.constant != height {
            keyboardHeight?.constant = height
        }
    }

    private func deleteKey() {
        if model.isSearching {
            model.deleteQueryCharacter()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    private func spaceKey() {
        if model.isSearching {
            model.appendQuery(" ")
        } else {
            textDocumentProxy.insertText(" ")
        }
    }

    private func returnKey() {
        if model.isSearching {
            model.endSearch()
        } else {
            textDocumentProxy.insertText("\n")
        }
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
    case blocks = "Blocks"
    case saved = "Saved"

    var icon: String {
        switch self {
        case .symbols: return "sparkles"
        case .blocks: return "square.grid.2x2"
        case .saved: return "star"
        }
    }
}

@MainActor
private final class KeyboardModel: ObservableObject {
    @Published var section: KeyboardSection = .symbols
    @Published var isSearching = false
    @Published var query = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var results: [UnicodeCharacter] = []
    @Published private(set) var searchInProgress = false
    @Published var selectedBlock: UnicodeBlock?
    @Published private(set) var blockCharacters: [UnicodeCharacter] = []
    @Published private(set) var hasMoreCharacters = false
    @Published var lastCharacter: UnicodeCharacter?
    @Published var showFavorites = true
    @Published var needsInputModeSwitchKey = true
    @Published var returnTitle = "Return"
    var searchModeChanged: (() -> Void)?
    private var searchTask: Task<Void, Never>?
    private let pageSize = 160

    func beginSearch() {
        isSearching = true
        searchModeChanged?()
    }

    func endSearch() {
        isSearching = false
        searchModeChanged?()
    }

    func appendQuery(_ text: String) {
        guard query.count < 100 else { return }
        query += text
    }

    func deleteQueryCharacter() {
        guard !query.isEmpty else { return }
        query.removeLast()
    }

    func openBlock(_ block: UnicodeBlock) {
        selectedBlock = block
        blockCharacters = UnicodeCatalog.shared.characters(in: block, offset: 0, limit: pageSize)
        hasMoreCharacters = blockCharacters.count == pageSize
    }

    func loadNextPage() {
        guard let block = selectedBlock, hasMoreCharacters else { return }
        let more = UnicodeCatalog.shared.characters(in: block, offset: blockCharacters.count, limit: pageSize)
        blockCharacters.append(contentsOf: more)
        hasMoreCharacters = more.count == pageSize
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty else {
            results = []
            searchInProgress = false
            return
        }
        searchInProgress = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch { return }
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                UnicodeCatalog.shared.search(searchQuery, limit: 120)
            }.value
            guard !Task.isCancelled, let self, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery else { return }
            self.results = matches
            self.searchInProgress = false
        }
    }
}

private enum KeyboardPalette {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.60, blue: 0.45, alpha: 1)
            : UIColor(red: 0.73, green: 0.30, blue: 0.17, alpha: 1)
    })
    static let backgroundUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.105, blue: 0.11, alpha: 1)
            : UIColor(red: 0.955, green: 0.946, blue: 0.925, alpha: 1)
    }
    static let keyUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.205, blue: 0.21, alpha: 1)
            : UIColor(red: 1.0, green: 0.995, blue: 0.98, alpha: 1)
    }
    static let background = Color(uiColor: backgroundUI)
    static let key = Color(uiColor: keyUI)
    static let secondary = Color.primary.opacity(0.48)
}

private struct UnicodeKeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject var store: CharacterStore
    weak var controller: KeyboardViewController?
    let insert: (UnicodeCharacter) -> Void
    let delete: () -> Void
    let space: () -> Void
    let returnKey: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 54, maximum: 82), spacing: 6)]

    var body: some View {
        VStack(spacing: 7) {
            header
            if !model.isSearching { sectionTabs }
            statusBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            if model.isSearching { searchKeys }
            controls
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(KeyboardPalette.background.ignoresSafeArea())
        .tint(KeyboardPalette.accent)
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.isSearching {
                HStack(spacing: 3) {
                    Text("u")
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        .foregroundStyle(KeyboardPalette.accent)
                    Text("niboard")
                        .font(.system(size: 15, weight: .semibold))
                }
                .accessibilityElement(children: .combine)
            }
            Button { model.beginSearch() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.query.isEmpty ? "Name, description, U+…" : model.query)
                        .font(.system(size: 13))
                        .foregroundStyle(model.query.isEmpty ? KeyboardPalette.secondary : Color.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.isSearching {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(KeyboardPalette.accent)
                            .frame(width: 2, height: 17)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 35)
                .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.isSearching ? KeyboardPalette.accent.opacity(0.6) : Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search Unicode characters")
            .accessibilityValue(model.query.isEmpty ? "No query" : model.query)
            .accessibilityIdentifier("keyboard.search")
            if model.isSearching {
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(KeyboardPalette.secondary)
                    }
                    .accessibilityLabel("Clear search")
                    .frame(width: 25, height: 35)
                }
                Button("Done") { model.endSearch() }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 35)
                    .accessibilityLabel("Close search keys")
            }
        }
        .frame(height: 35)
    }

    private var sectionTabs: some View {
        HStack(spacing: 4) {
            ForEach(KeyboardSection.allCases, id: \.self) { section in
                Button {
                    model.section = section
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 11))
                        Text(section.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 29)
                    .foregroundStyle(model.section == section ? KeyboardPalette.accent : Color.primary.opacity(0.65))
                    .background(model.section == section ? KeyboardPalette.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
                .accessibilityIdentifier("keyboard.tab.\(section.rawValue.lowercased())")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            if let character = model.lastCharacter {
                Text(character.displayText)
                    .font(.system(size: 19))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(character.name.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(character.codePointLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(KeyboardPalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    store.toggleFavorite(character.codePoint)
                } label: {
                    Image(systemName: store.isFavorite(character.codePoint) ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .frame(width: 33, height: 27)
                }
                .accessibilityLabel("\(store.isFavorite(character.codePoint) ? "Remove" : "Save") \(character.name.capitalized) \(store.isFavorite(character.codePoint) ? "from" : "to") favorites")
            } else {
                Text(model.isSearching ? "Search by name, hex code, or meaning" : "Tap to insert · Hold to inspect and save")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardPalette.secondary)
                Spacer(minLength: 0)
                Text("U\(UnicodeCatalog.shared.version)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(KeyboardPalette.secondary)
            }
        }
        .frame(height: 27)
    }

    @ViewBuilder
    private var content: some View {
        if model.isSearching {
            searchResults
        } else {
            switch model.section {
            case .symbols:
                characterGrid(UnicodeCatalog.shared.featured)
            case .blocks:
                blockContent
            case .saved:
                savedContent
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 8) {
                Text("Find your character")
                    .font(.system(size: 16, weight: .semibold))
                Text("Try “arrow”, “heart”, “U+03C0”, or “decimal:960”")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardPalette.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    ForEach(["arrow", "heart", "U+03C0"], id: \.self) { example in
                        Button(example) { model.query = example }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(KeyboardPalette.accent.opacity(0.08), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.searchInProgress && model.results.isEmpty {
            ProgressView("Searching Unicode…")
                .font(.system(size: 12))
        } else if model.results.isEmpty {
            emptyState(icon: "magnifyingglass", title: "No characters found", detail: "Try a shorter name or a codepoint such as U+2192.")
        } else {
            characterGrid(model.results)
        }
    }

    @ViewBuilder
    private var blockContent: some View {
        if let block = model.selectedBlock {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Button {
                        model.selectedBlock = nil
                        model.lastCharacter = nil
                    } label: {
                        Label("All blocks", systemImage: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    Text(block.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(block.rangeLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(KeyboardPalette.secondary)
                        .lineLimit(1)
                }
                .frame(height: 23)
                if model.blockCharacters.isEmpty {
                    emptyState(icon: "square.dashed", title: "No assigned characters", detail: "This block is reserved in Unicode \(UnicodeCatalog.shared.version).")
                } else {
                    characterGrid(model.blockCharacters, paginated: true)
                        .id(block.id)
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(UnicodeCatalog.shared.blocks) { block in
                        Button { model.openBlock(block) } label: {
                            HStack(spacing: 10) {
                                Text(block.symbol)
                                    .font(.system(size: 21))
                                    .foregroundStyle(KeyboardPalette.accent)
                                    .frame(width: 31)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                    Text(block.rangeLabel)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(KeyboardPalette.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(KeyboardPalette.secondary)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 44)
                            .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Browse \(block.name), \(block.rangeLabel)")
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("keyboard.blocks")
        }
    }

    private var savedContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                savedTab("Favorites", icon: "star", selected: model.showFavorites) { model.showFavorites = true }
                savedTab("Recent", icon: "clock", selected: !model.showFavorites) { model.showFavorites = false }
                Spacer(minLength: 0)
                Text("On this keyboard")
                    .font(.system(size: 9))
                    .foregroundStyle(KeyboardPalette.secondary)
            }
            let characters = model.showFavorites ? store.favoriteCharacters : store.recentCharacters
            if characters.isEmpty {
                emptyState(
                    icon: model.showFavorites ? "star" : "clock",
                    title: model.showFavorites ? "Keep your go-to characters" : "Your recent characters appear here",
                    detail: model.showFavorites ? "Hold a character, then tap the star above." : "Insert a character to keep it close."
                )
            } else {
                characterGrid(characters)
            }
        }
    }

    private func savedTab(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .foregroundStyle(selected ? KeyboardPalette.accent : KeyboardPalette.secondary)
                .background(selected ? KeyboardPalette.accent.opacity(0.09) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func characterGrid(_ characters: [UnicodeCharacter], paginated: Bool = false) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(characters) { character in
                    CharacterKey(character: character, favorite: store.isFavorite(character.codePoint), insert: {
                        insert(character)
                    }, inspect: {
                        model.lastCharacter = character
                    })
                    .onAppear {
                        if paginated && character.id == characters.last?.id {
                            model.loadNextPage()
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(KeyboardPalette.accent)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(KeyboardPalette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchKeys: some View {
        VStack(spacing: 4) {
            searchKeyRow(Array("1234567890").map(String.init))
            searchKeyRow(Array("qwertyuiop").map(String.init))
            searchKeyRow(Array("asdfghjkl").map(String.init), inset: 10)
            searchKeyRow(["+", "z", "x", "c", "v", "b", "n", "m", ":", "-"], inset: 0)
        }
    }

    private func searchKeyRow(_ keys: [String], inset: CGFloat = 0) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Button { model.appendQuery(key) } label: {
                    Text(key)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "+" ? "Plus" : key == ":" ? "Colon" : key == "-" ? "Hyphen" : key)
                .accessibilityIdentifier("keyboard.query.\(key)")
            }
        }
        .padding(.horizontal, inset)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if model.needsInputModeSwitchKey {
                InputModeSwitchKey(controller: controller)
                    .frame(width: 42, height: 42)
            } else {
                Button { controller?.dismissKeyboard() } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 17))
                        .frame(width: 42, height: 42)
                        .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }
            RepeatingDeleteKey(action: delete, isQuery: model.isSearching)
                .frame(width: 49, height: 42)
            Button(action: space) {
                Text(model.isSearching ? "search space" : "space")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isSearching ? "Add space to search" : "Insert space")
            .accessibilityIdentifier("keyboard.space")
            Button(action: returnKey) {
                Text(model.isSearching ? "Done" : model.returnTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 78, height: 42)
                    .background(KeyboardPalette.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isSearching ? "Close search keys" : "\(model.returnTitle) key")
            .accessibilityIdentifier("keyboard.return")
        }
    }
}

private struct CharacterKey: View {
    let character: UnicodeCharacter
    let favorite: Bool
    let insert: () -> Void
    let inspect: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(character.displayText)
                .font(.system(size: character.isInvisible ? 17 : 27))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(height: 33)
            Text(character.codePointLabel.replacingOccurrences(of: "U+", with: ""))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(KeyboardPalette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(KeyboardPalette.accent)
                    .padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: insert)
        .onLongPressGesture(minimumDuration: 0.35, perform: inspect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name.capitalized), \(character.codePointLabel)")
        .accessibilityHint(character.isInvisible ? "Inserts an invisible character. Hold to inspect and save." : "Inserts this character. Hold to inspect and save.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { insert() }
        .accessibilityAction(named: Text("Inspect character"), inspect)
        .accessibilityIdentifier("keyboard.character.\(character.codePointLabel)")
    }
}

/// UIKit forwards all globe touch events to Apple's input-mode menu, preserving
/// the standard press-and-hold switcher instead of implementing only a tap.
private struct InputModeSwitchKey: UIViewRepresentable {
    weak var controller: KeyboardViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        button.tintColor = .label
        button.backgroundColor = KeyboardPalette.keyUI
        button.layer.cornerRadius = 7
        button.accessibilityLabel = "Next keyboard"
        button.accessibilityHint = "Hold to choose a keyboard"
        button.accessibilityIdentifier = "keyboard.globe"
        button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

private struct RepeatingDeleteKey: UIViewRepresentable {
    let action: () -> Void
    let isQuery: Bool

    func makeUIView(context: Context) -> RepeatingDeleteButton {
        RepeatingDeleteButton()
    }

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
        layer.cornerRadius = 7
        accessibilityIdentifier = "keyboard.delete"
        accessibilityHint = "Hold to delete repeatedly"
        addTarget(self, action: #selector(startDeleting), for: .touchDown)
        addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    override func accessibilityActivate() -> Bool {
        action?()
        return true
    }

    @objc private func startDeleting() {
        stopDeleting()
        action?()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.action?()
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                self?.action?()
            }
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

    deinit {
        delayTimer?.invalidate()
        repeatTimer?.invalidate()
    }
}
