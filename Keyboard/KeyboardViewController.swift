import SwiftUI
import UIKit
#if DEBUG
import os
#endif

/// Query keys edit only the extension's local search. Insertion always sends the
/// original scalar or complete emoji sequence to the host's document proxy.
fileprivate final class KeyboardResizePreviewModel: ObservableObject {
    @Published var height: CGFloat?
}

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var keyboardHeight: NSLayoutConstraint?
    private var hostingController: UIHostingController<UnicodeKeyboardView>?
    fileprivate let resizeHandle = ResizeHandleButton(backgroundColor: KeyboardPalette.backgroundUI.withAlphaComponent(0.02))
    fileprivate let resizePreview = KeyboardResizePreviewModel()
    private var resizeDisplayLink: CADisplayLink?
    private var resizeDisplayTarget: ResizeDisplayTarget?
    private var pendingResizeHeight: CGFloat?
    private var isResizing = false
#if DEBUG
    private var resizeDiagnostics: KeyboardResizeDiagnostics?
#endif

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
            delete: { [weak self] isQuery in self?.makeDeleteAction(isQuery: isQuery) ?? { false } },
            space: { [weak self] in self?.spaceKey() },
            returnKey: { [weak self] in self?.returnKey() }
        )
        let host = UIHostingController(rootView: root)
        // The input controller already owns its complete content bounds. The
        // remote keyboard's container safe area must not add another top inset.
        host.safeAreaRegions = []
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
        resizeHandle.coordinateView = view
        resizeHandle.toggle = { [weak self] in self?.model.togglePortraitHeight() }
        resizeHandle.begin = { [weak self] in self?.beginInteractiveResize() }
        resizeHandle.change = { [weak self] delta in
            guard let self, self.isResizing,
                  let height = self.model.resizeTarget(translationY: delta) else { return }
#if DEBUG
            self.resizeDiagnostics?.recordGesture()
#endif
            self.pendingResizeHeight = height
#if DEBUG
            self.resizeDiagnostics?.recordRequest()
#endif
        }
        resizeHandle.end = { [weak self] commit in self?.endInteractiveResize(flush: commit) }
        resizeHandle.step = { [weak self] delta in self?.model.stepPortraitHeight(delta) }
#if DEBUG
        resizeHandle.debugSample = { [weak self] sample in
            self?.resizeDiagnostics?.recordSample(sample)
        }
#endif
        let height = view.heightAnchor.constraint(equalToConstant: 300)
        height.priority = .init(999)
        height.isActive = true
        keyboardHeight = height
        model.presentationChanged = { [weak self] animated in self?.updateKeyboardHeight(animated: animated) }
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
#if DEBUG
        resizeDiagnostics?.recordLayout(view.bounds.height)
#endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        endInteractiveResize(flush: false)
        super.viewWillDisappear(animated)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        synchronizeHostTraits()
    }

    private func synchronizeHostTraits() {
        // UIKit can ask again during a remote resize. Do not invalidate every
        // character key when neither input trait has changed.
        if model.needsInputModeSwitchKey != needsInputModeSwitchKey { model.needsInputModeSwitchKey = needsInputModeSwitchKey }
        let title = Self.returnTitle(for: textDocumentProxy.returnKeyType)
        if model.returnTitle != title { model.returnTitle = title }
    }

    @objc private func updateBackdrop() {
        let opaque = UIAccessibility.isReduceTransparencyEnabled
        view.backgroundColor = opaque ? KeyboardPalette.backgroundUI : .clear
        view.isOpaque = opaque
    }

    private func updateKeyboardHeight(animated: Bool = false) {
        let pad = traitCollection.userInterfaceIdiom == .pad
        let scene = view.window?.windowScene
        let metrics = KeyboardLayoutPolicy.metrics(
            viewWidth: view.bounds.width, displaySize: scene?.screen.bounds.size,
            sceneHeight: scene?.coordinateSpace.bounds.height, isPad: pad,
            compactVertical: traitCollection.verticalSizeClass == .compact,
            isSearching: model.isSearching, isInspecting: model.inspection != nil,
            portraitBrowseHeight: model.portraitBrowseHeight,
            portraitExpandedHeight: model.portraitExpandedHeight
        )
        if model.isCompactLayout != metrics.isCompactLayout { model.isCompactLayout = metrics.isCompactLayout }
        if model.isPadLayout != pad { model.isPadLayout = pad }
        model.portraitResizeRange = metrics.portraitResizeRange
        let showsHandle = metrics.portraitResizeRange != nil
        resizeHandle.isHidden = !showsHandle
        resizeHandle.accessibilityHint = model.isSearching || model.inspection != nil
            ? "Drag to preview a height, then release to resize. Double tap to return to browsing."
            : "Drag to preview a height, then release to resize. Double tap to switch between compact and expanded."
        if isResizing && !showsHandle { endInteractiveResize(flush: false) }
        // The remote window stays fixed for the entire drag. Resizing it here
        // rebases incoming touches asynchronously and causes visible feedback.
        if isResizing { return }
        applyKeyboardHeight(metrics.height, animated: animated)
    }

    private func applyKeyboardHeight(_ height: CGFloat, animated: Bool) {
        guard height.isFinite, height > 0 else { return }
        model.presentationHeight = height
        resizeHandle.accessibilityValue = "\(Int(height.rounded())) points"
        guard keyboardHeight?.constant != height else { return }
        keyboardHeight?.constant = height
        // The system must negotiate the input view's new size with its host.
        // Forcing a local layout inside an animator can resize only our bounds
        // without updating the remote keyboard frame.
        view.setNeedsLayout()
        view.superview?.setNeedsLayout()
    }

    private func beginInteractiveResize() {
        guard !isResizing, model.portraitResizeRange != nil else { return }
        let visibleHeight = view.bounds.height
        isResizing = true
        pendingResizeHeight = nil
        guard let startHeight = model.beginResize(at: visibleHeight) else {
            isResizing = false
            return
        }
        pendingResizeHeight = nil
        resizePreview.height = startHeight
#if DEBUG
        resizeDiagnostics = KeyboardResizeDiagnostics(height: startHeight)
#endif
        let target = ResizeDisplayTarget(controller: self)
        let link = CADisplayLink(target: target, selector: #selector(ResizeDisplayTarget.tick(_:)))
        // Only the small preview observes these updates, never the key grid or
        // remote height constraint. Commit the final target after release.
        let fps = Float(min(60, view.window?.screen.maximumFramesPerSecond ?? 60))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: fps, preferred: fps)
        resizeDisplayTarget = target
        resizeDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    fileprivate func displayResizeFrame() {
        guard let height = pendingResizeHeight else { return }
        pendingResizeHeight = nil
#if DEBUG
        let began = CACurrentMediaTime()
#endif
        if resizePreview.height != height { resizePreview.height = height }
#if DEBUG
        resizeDiagnostics?.recordApply(height, began: began)
#endif
    }

    private func endInteractiveResize(flush: Bool = true) {
        guard isResizing else { return }
        if flush { displayResizeFrame() }
        let target = flush ? resizePreview.height : nil
        pendingResizeHeight = nil
        resizeDisplayLink?.invalidate()
        resizeDisplayLink = nil
        resizeDisplayTarget = nil
        isResizing = false
        resizePreview.height = nil
#if DEBUG
        let diagnostics = resizeDiagnostics
        resizeDiagnostics = nil
#endif
        model.endResize(commitHeight: target)
#if DEBUG
        diagnostics?.finish(height: model.presentationHeight, committed: target != nil)
#endif
    }

    private func makeDeleteAction(isQuery: Bool) -> RepeatingDeleteButton.DeleteAction {
        let context = KeyboardDeleteContext(isQuery: isQuery, documentIdentifier: textDocumentProxy.documentIdentifier)
        return context.guardedAction(currentContext: { [weak self] in
            guard let self else { return nil }
            return KeyboardDeleteContext(isQuery: self.model.isSearching, documentIdentifier: self.textDocumentProxy.documentIdentifier)
        }, delete: { [weak self] in
            if isQuery { self?.model.deleteQueryCharacter() }
            else { self?.textDocumentProxy.deleteBackward() }
        })
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

    deinit {
        resizeDisplayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

/// CADisplayLink retains its target, so keep the input controller weak.
private final class ResizeDisplayTarget: NSObject {
    weak var controller: KeyboardViewController?
    init(controller: KeyboardViewController) { self.controller = controller }
    @objc func tick(_ link: CADisplayLink) { controller?.displayResizeFrame() }
}

#if DEBUG
/// Local development-only timing evidence. No queries or host text are recorded,
/// and the entire recorder is absent from distributed Release binaries.
private final class KeyboardResizeDiagnostics {
    private static var bodyEvaluations = 0
    static func recordBodyEvaluation() { bodyEvaluations += 1 }
    private let started = CACurrentMediaTime()
    private let startedEpoch = Date().timeIntervalSince1970
    private let initialHeight: CGFloat
    private let initialBodyCount = bodyEvaluations
    private var gestureCount = 0
    private var requestCount = 0
    private var pendingSince: CFTimeInterval?
    private var applyTimes: [Double] = []
    private var applyCosts: [Double] = []
    private var latencies: [Double] = []
    private var targets: [[Double]] = []
    private var layouts: [[Double]] = []
    private var inputSamples: [[String: Double]] = []

    init(height: CGFloat) { initialHeight = height }
    func recordGesture() { gestureCount += 1 }
    func recordSample(_ sample: [String: Double]) {
        if inputSamples.count < 2_048 { inputSamples.append(sample) }
    }
    func recordRequest() {
        requestCount += 1
        if pendingSince == nil { pendingSince = CACurrentMediaTime() }
    }
    func recordApply(_ height: CGFloat, began: CFTimeInterval) {
        let now = CACurrentMediaTime()
        applyTimes.append(began)
        applyCosts.append((now - began) * 1_000)
        if let pendingSince { latencies.append((began - pendingSince) * 1_000) }
        pendingSince = nil
        if targets.count < 1_024 { targets.append([began - started, Double(height)]) }
    }
    func recordLayout(_ height: CGFloat) {
        guard height.isFinite, layouts.last?.last != Double(height), layouts.count < 1_024 else { return }
        layouts.append([CACurrentMediaTime() - started, Double(height)])
    }
    func finish(height: CGFloat, committed: Bool) {
        let gaps = zip(applyTimes.dropFirst(), applyTimes).map { ($0 - $1) * 1_000 }
        func percentile(_ values: [Double], fraction: Double) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
        }
        let value: [String: Any] = [
            "duration": CACurrentMediaTime() - started,
            "startedEpoch": startedEpoch,
            "commitEpoch": Date().timeIntervalSince1970,
            "initialHeight": Double(initialHeight), "finalHeight": Double(height),
            "gestureSamples": gestureCount, "queuedRequests": requestCount,
            "previewUpdates": applyTimes.count,
            "heightCommits": committed && height != initialHeight ? 1 : 0,
            "commitTimestamp": CACurrentMediaTime(),
            "maxApplyGapMs": gaps.max() ?? 0, "p95ApplyGapMs": percentile(gaps, fraction: 0.95),
            "maxRequestToApplyMs": latencies.max() ?? 0,
            "maxConstraintCostMs": applyCosts.max() ?? 0,
            "bodyEvaluations": Self.bodyEvaluations - initialBodyCount,
            "previewHeights": targets, "layoutHeightsDuringDrag": layouts,
            "inputSamples": inputSamples
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        // Write once, after sampling stops. Unified logging truncates long
        // vectors; this local DEBUG file preserves the complete timing proof.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UniboardResizeMetrics", isDirectory: true)
        if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil {
            let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
            try? data.write(to: file, options: .atomic)
        }
        Logger(subsystem: "ad.neko.uniboard.resize", category: "gesture")
            .notice("resizeMetrics \(json, privacy: .public)")
    }
}
#endif

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
        didSet { if isSearching || hasSearchQuery { scheduleSearch() } }
    }
    @Published var isSearching = false
    @Published var query = "" { didSet { queryCursor = query.count; scheduleSearch() } }
    @Published private(set) var queryCursor = 0
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
    @Published var inspection: KeyboardItem? { didSet { if !batchingPresentation { presentationChanged?(true) } } }
    @Published var showFavorites = true
    @Published var needsInputModeSwitchKey = true
    @Published var returnTitle = "Return"
    @Published var isCompactLayout = false
    @Published var isPadLayout = false
    // Native resize layout owns this value. Publishing it would rebuild the
    // entire SwiftUI character grid for every finger movement.
    var presentationHeight: CGFloat = 300
    private(set) var portraitBrowseHeight: CGFloat
    private(set) var portraitExpandedHeight: CGFloat = 340
    var portraitResizeRange: ClosedRange<CGFloat>?
    var presentationChanged: ((Bool) -> Void)?
    private var batchingPresentation = false
    private var resizeSession: KeyboardResizeSession?
    private let defaults = UserDefaults.standard
    private let pageSize = 160
    private var revision = 0
    private var searchTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var blockTask: Task<Void, Never>?
    private var symbolPageTask: Task<Void, Never>?
    private var emojiPageTask: Task<Void, Never>?
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
    var hasSearchQuery: Bool {
        (section == .symbols || section == .emojis) && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var queryCaretUTF16Offset: Int { KeyboardQueryPolicy.utf16Offset(forCharacterOffset: queryCursor, in: query) }

    init() {
        let storedHeight = defaults.double(forKey: "keyboard.portraitBrowseHeight")
        portraitBrowseHeight = storedHeight.isFinite && (220...420).contains(storedHeight) ? CGFloat(storedHeight) : 300
        edition = defaults.string(forKey: "keyboard.unicodeEdition") == "latest" ? .latest : .draft
        switch defaults.string(forKey: "keyboard.unicodeSortOrder") {
        case "oldestFirst": order = .oldestFirst
        case "codePoint": order = .codePoint
        default: order = .newestFirst
        }
        useUnicodeFonts = LocalPreferencePolicy.boolean(forKey: "keyboardUnicodeFonts", in: defaults)
        refreshCatalog()
    }

    deinit {
        searchTask?.cancel()
        discoveryTask?.cancel()
        blockTask?.cancel()
        symbolPageTask?.cancel()
        emojiPageTask?.cancel()
    }

    func beginSearch() {
        guard !isSearching || inspection != nil else { return }
        batchingPresentation = true
        inspection = nil
        if section == .blocks || section == .saved { section = .symbols }
        portraitExpandedHeight = max(340, portraitBrowseHeight)
        isSearching = true
        batchingPresentation = false
        scheduleSearch()
        presentationChanged?(true)
    }
    func endSearch() {
        isSearching = false
        presentationChanged?(true)
    }
    func inspect(_ item: KeyboardItem) {
        lastItem = item
        portraitExpandedHeight = max(340, presentationHeight)
        inspection = item
    }
    func closeInspection() { inspection = nil }
    func appendQuery(_ text: String) {
        applyQueryEdit(KeyboardQueryPolicy.inserting(text, into: query, caretUTF16Offset: queryCaretUTF16Offset))
    }
    func deleteQueryCharacter() {
        applyQueryEdit(KeyboardQueryPolicy.deletingBackward(from: query, caretUTF16Offset: queryCaretUTF16Offset))
    }
    func moveQueryCaret(toUTF16Offset offset: Int) {
        queryCursor = KeyboardQueryPolicy.characterOffset(forUTF16Offset: offset, in: query)
    }
    private func applyQueryEdit(_ edit: KeyboardQueryPolicy.Edit) {
        if query != edit.text { query = edit.text }
        queryCursor = edit.caretCharacterOffset
    }

    @discardableResult
    func beginResize(at height: CGFloat?) -> CGFloat? {
        guard let range = portraitResizeRange else { return nil }
        let preference = isSearching || inspection != nil ? portraitExpandedHeight : portraitBrowseHeight
        guard let session = KeyboardResizeSession(preferredHeight: preference, visibleHeight: height,
            fallbackHeight: presentationHeight, range: range) else { return nil }
        resizeSession = session
        presentationHeight = session.startHeight
        return session.startHeight
    }
    func resizeTarget(translationY: CGFloat) -> CGFloat? {
        guard let session = resizeSession, let range = portraitResizeRange else { return nil }
        return session.target(translationY: translationY, range: range)
    }
    func endResize(commitHeight: CGFloat?) {
        var session = resizeSession
        resizeSession = nil
        guard let range = portraitResizeRange, let height = session?.finish(commitHeight: commitHeight, range: range) else { return }
        setPortraitHeight(height, animated: true)
        persistBrowseHeight()
    }
    func togglePortraitHeight() {
        guard let range = portraitResizeRange else { return }
        if inspection != nil { closeInspection() }
        else if isSearching { endSearch() }
        else if let height = KeyboardResizePolicy.toggledHeight(current: presentationHeight, range: range) {
            setPortraitHeight(height, animated: true)
            persistBrowseHeight()
        }
    }
    func stepPortraitHeight(_ delta: CGFloat) {
        guard let range = portraitResizeRange,
              let height = KeyboardResizePolicy.target(startHeight: presentationHeight, translationY: -delta, in: range) else { return }
        setPortraitHeight(height, animated: true)
        persistBrowseHeight()
    }
    private func setPortraitHeight(_ value: CGFloat, animated: Bool) {
        guard let range = portraitResizeRange,
              let height = KeyboardResizePolicy.clampedHeight(value, in: range) else { return }
        let previous = isSearching || inspection != nil ? portraitExpandedHeight : portraitBrowseHeight
        guard height != previous else { return }
        if isSearching || inspection != nil { portraitExpandedHeight = height }
        else { portraitBrowseHeight = height }
        presentationChanged?(animated)
    }
    private func persistBrowseHeight() {
        defaults.set(Double(portraitBrowseHeight), forKey: "keyboard.portraitBrowseHeight")
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
            let more = await CatalogWorker.run {
                activeCatalog.characters(in: block, offset: offset, limit: limit, order: activeOrder)
            }
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
        symbolPageTask = Task { [weak self] in
            let more = await CatalogWorker.run {
                activeCatalog.orderedCharacters(offset: offset, limit: limit, order: activeOrder)
            }
            guard !Task.isCancelled, let self, self.revision == activeRevision else { return }
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
        emojiPageTask = Task { [weak self] in
            let more = await CatalogWorker.run {
                activeCatalog.entries(offset: offset, limit: limit, order: activeOrder)
            }
            guard !Task.isCancelled, let self, self.revision == activeRevision else { return }
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
        searchTask?.cancel()
        discoveryTask?.cancel()
        blockTask?.cancel()
        symbolPageTask?.cancel()
        emojiPageTask?.cancel()
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
            let pages = await CatalogWorker.run {
                (activeCatalog.orderedCharacters(offset: 0, limit: limit, order: activeOrder),
                 activeEmojis.entries(offset: 0, limit: limit, order: activeOrder))
            }
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
            let matches: ([UnicodeCharacter], [UnicodeEmojiEntry]) = await CatalogWorker.run {
                if searchEmojis { return ([], activeEmojis.search(searchQuery, limit: 120, order: activeOrder)) }
                return (activeCatalog.search(searchQuery, limit: 120, order: activeOrder), [])
            }
            guard !Task.isCancelled, let self, self.revision == activeRevision,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery,
                  (self.section == .emojis) == searchEmojis else { return }
            self.results = matches.0
            self.emojiResults = matches.1
            self.searchInProgress = false
        }
    }
}

enum KeyboardPalette {
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
    let delete: (Bool) -> RepeatingDeleteButton.DeleteAction
    let space: () -> Void
    let returnKey: () -> Void
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: model.isPadLayout ? 70 : 58, maximum: 92), spacing: 6)]
    }
    private var keyHeight: CGFloat { model.isCompactLayout ? 50 : model.isPadLayout ? 60 : 56 }
    private var headerHeight: CGFloat { model.isCompactLayout ? 36 : 40 }
    private var controlHeight: CGFloat { model.isCompactLayout ? 34 : 38 }

    var body: some View {
#if DEBUG
        let _ = KeyboardResizeDiagnostics.recordBodyEvaluation()
#endif
        VStack(spacing: 0) {
            if !model.isCompactLayout && !model.isPadLayout, let controller {
                // Keep the control in the hosted remote input hierarchy so
                // iOS forwards continuous touches as well as button actions.
                KeyboardResizeHandle(button: controller.resizeHandle)
                    .frame(height: 18)
                    .contentShape(Rectangle())
            }
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
            .padding(.top, model.isCompactLayout || model.isPadLayout ? 4 : 0)
            .padding(.bottom, 6)
        }
        .background(KeyboardTray().ignoresSafeArea())
        .overlay(alignment: .top) {
            if let controller {
                KeyboardResizePreview(model: controller.resizePreview)
                    .padding(.top, 72)
            }
        }
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
                KeyboardQueryField(
                    query: model.query,
                    caretUTF16Offset: model.queryCaretUTF16Offset,
                    isEditing: model.isSearching,
                    isEmojiScope: model.section == .emojis,
                    onActivate: model.beginSearch,
                    onMoveCaret: model.moveQueryCaret
                )
                .frame(maxWidth: .infinity).frame(height: headerHeight)
                if !model.query.isEmpty {
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
            // Native query text must stay outside the glass compositor. A
            // quiet key surface keeps the label and caret fully legible.
            .keyboardKeySurface(radius: 12)
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
        if model.isSearching || model.hasSearchQuery { searchResults }
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
            Text(!character.annotations.isEmpty || !character.sectionAnnotations.isEmpty
                 ? character.categoryName
                 : character.detail.isEmpty ? "No additional annotation is listed. The official Unicode name and properties are shown below." : character.detail)
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("keyboard.properties.description")
            if !character.nameAliases.isEmpty {
                property("Aliases", value: character.nameAliases.map { "\($0.kindLabel): \($0.name)" }.joined(separator: "\n"), identifier: "aliases")
            }
            if let section = character.namesListSection { property("Unicode section", value: section, identifier: "section") }
            let notes = character.sectionAnnotations + character.annotations
            if !notes.isEmpty {
                property("Unicode notes", value: (Array(NSOrderedSet(array: notes)) as? [String] ?? notes).joined(separator: "\n"), identifier: "notes")
            }
            if let oldName = character.unicode1Name { property("Unicode 1.0 name", value: oldName, identifier: "unicode1Name") }
            if !character.crossReferences.isEmpty {
                property("Related characters", value: character.crossReferences.map { "\($0.codePointLabel) · \($0.name)" }.joined(separator: "\n"), identifier: "references")
            }
            property("Unicode age", value: character.age.map { "Unicode \($0)" } ?? (character.category == "Cn" ? "Unassigned" : "Age pending"), identifier: "age")
            property("Block", value: character.blockName, identifier: "block")
            property("Category", value: "\(character.categoryName) (\(character.category))", identifier: "category")
            property("UTF-8", value: utf8(character.text), identifier: "utf8", monospaced: true)
            property("Decimal", value: String(character.codePoint), identifier: "decimal", monospaced: true)
            if let value = character.numericValue { property("Numeric value", value: value, identifier: "numericValue", monospaced: true) }
            if let type = character.numericType { property("Numeric type", value: type, identifier: "numericType") }
            if let point = character.simpleUppercase { property("Uppercase", value: codePointText(point), identifier: "uppercase") }
            if let point = character.simpleLowercase { property("Lowercase", value: codePointText(point), identifier: "lowercase") }
            if let point = character.simpleTitlecase { property("Titlecase", value: codePointText(point), identifier: "titlecase") }
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

    private func codePointText(_ value: UInt32) -> String {
        String(format: "U+%04X", value) + (UnicodeScalar(value).map { " · \(String($0))" } ?? "")
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

private struct KeyboardResizePreview: View {
    @ObservedObject var model: KeyboardResizePreviewModel

    var body: some View {
        if let height = model.height {
            HStack(spacing: 9) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KeyboardPalette.accent)
                VStack(spacing: 2) {
                    Text("\(Int(height)) pt")
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    Text("Release to resize")
                        .font(.system(size: 11))
                        .foregroundStyle(KeyboardPalette.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(KeyboardPalette.key, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("keyboard.resize.preview")
            .accessibilityLabel("Keyboard height preview")
            .accessibilityValue("\(Int(height)) points. Release to resize.")
        }
    }
}

private struct KeyboardResizeHandle: UIViewRepresentable {
    let button: ResizeHandleButton
    func makeUIView(context: Context) -> ResizeHandleButton { button }
    func updateUIView(_ view: ResizeHandleButton, context: Context) {}
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
    let action: (Bool) -> RepeatingDeleteButton.DeleteAction
    let isQuery: Bool
    func makeUIView(context: Context) -> RepeatingDeleteButton { RepeatingDeleteButton() }
    func updateUIView(_ uiView: RepeatingDeleteButton, context: Context) {
        // Capture the scope this key currently displays, even before a model
        // transition has reached updateUIView. Each press gets one action.
        uiView.configure(isQuery: isQuery, actionFactory: { [isQuery] in action(isQuery) })
    }
}
