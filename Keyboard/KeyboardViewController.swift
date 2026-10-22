import SwiftUI
import UIKit

/// Query keys edit only the extension's local search. Insertion always sends the
/// original scalar or complete emoji sequence to the host's document proxy.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var hostingController: UIHostingController<UnicodeKeyboardView>?
    private var deleteInteractionID = UUID()
    private var doubleSpaceState = KeyboardDoubleSpaceState()
    private var hostSignature: HostSignature?
    // These bounded suffixes exist only in this keyboard process. An expected
    // edit acknowledges proxy callbacks without mistaking our own Space for
    // an intervening external edit. No context is stored or logged.
    private var expectedHostEdit: ExpectedHostEdit?
    private var literalWriteTransaction = KeyboardLiteralWriteTransaction()
    private var literalWriteToken: UUID?
    private typealias HostSignature = KeyboardHostInputSignature
    private struct ExpectedHostEdit {
        let document: UUID
        let before: [Unicode.Scalar]
        let expires: TimeInterval
    }


    override func loadView() {
        // Use the keyboard's system blur and tint instead of stacking another
        // full-size material behind the control glass.
        view = KeyboardSelfSizingInputView(frame: .zero, inputViewStyle: .keyboard)
        view.accessibilityIdentifier = "keyboard.surface"
        view.accessibilityContainerType = .semanticGroup
        view.shouldGroupAccessibilityChildren = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
        NotificationCenter.default.addObserver(self, selector: #selector(updateBackdrop), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        updateBackdrop()
        let root = UnicodeKeyboardView(
            model: model, store: CharacterStore.shared, controller: self,
            delete: { [weak self] mode, isQuery in self?.makeDeleteAction(renderedMode: mode, isQuery: isQuery) ?? { false } },
            action: { [weak self] mode, command in self?.makeInputAction(renderedMode: mode, command: command) ?? { false } },
            shiftSlide: { [weak self] mode in self?.makeShiftSlideAction(renderedMode: mode) },
            keyActions: { [weak self] mode, item in self?.makeInspectableActions(renderedMode: mode, item: item) },
            queryAction: { [weak self] mode, query in self?.makeQueryAction(renderedMode: mode, renderedQuery: query) },
            typingVariantActions: { [weak self] mode, key, auxiliary, isAuxiliary, widePad, ansiPad in self?.makeTypingVariantActions(renderedMode: mode, key: key, hasAuxiliaryRow: auxiliary, isAuxiliaryKey: isAuxiliary, widePad: widePad, ansiPad: ansiPad) },
            favoritesActions: { [weak self] mode in self?.makeFavoritesActions(renderedMode: mode) },
            layoutActions: { [weak self] mode in self?.makeLayoutActions(renderedMode: mode) },
            boardKeyActions: { [weak self] mode, board, key in self?.makeSymbolBoardActions(renderedMode: mode, boardID: board, key: key) },
            boardConfigurationGuard: { [weak self] mode in self?.makeBoardConfigurationGuard(renderedMode: mode) },
            boardConfigurationSessionGuard: { [weak self] mode in self?.makeBoardConfigurationSessionGuard(renderedMode: mode) }
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
        let bottom = host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            bottom
        ])
        host.didMove(toParent: self)
        hostingController = host
        model.presentationChanged = { [weak self] in self?.updateKeyboardHeight() }
        model.queryEdited = { [weak self] in
            self?.doubleSpaceState.reset()
            self?.expectedHostEdit = nil
        }
        model.typingActivated = { [weak self] in self?.synchronizeHostTraits() }
        model.alphabetChanged = { [weak self] in
            self?.applyPrimaryLanguage()
            self?.synchronizeHostTraits()
        }
        applyPrimaryLanguage()
        model.inputModeChanged = { [weak self] in
            guard let self else { return }
            KeyboardVariantButton.cancelInteractions(in: self.view)
            self.doubleSpaceState.reset()
            self.expectedHostEdit = nil
        }
        // The remote document may not exist during viewDidLoad. Read its
        // optional identity only once UIKit begins presenting this input view.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshEditionFromAppSettings()
        SymbolBoardStore.shared.refreshPages()
        SymbolBoardStore.shared.refreshFavorites(canWrite: hasFullAccess)
        KeyboardTouchFeedback.hapticsAllowed = hasFullAccess
        synchronizeHostTraits()
        updateKeyboardHeight()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        UnicodeFontSupport.clearCache()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        synchronizeHostTraits()
    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        // A remote host may hide and reuse this same window without detaching
        // individual keys. Invalidate every captured input/hover action first.
        deleteInteractionID = UUID()
        model.symbolBoardManagerPresented = false
        KeyboardVariantButton.cancelInteractions(in: view)
        doubleSpaceState.reset()
        expectedHostEdit = nil
        super.viewWillDisappear(animated)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        acknowledgeHostChange()
        synchronizeHostTraits()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        // A selection move can leave the same preceding suffix. Never infer
        // permission for a destructive Space edit from that suffix alone.
        doubleSpaceState.reset()
        expectedHostEdit = nil
        model.symbolBoardManagerPresented = false
        model.hostDidEdit(invalidateMode: true)
        synchronizeHostTraits()
    }

    private var currentDocumentIdentifier: UUID? {
        KeyboardDocumentIdentity.read(from: textDocumentProxy)
    }

    private func synchronizeHostTraits() {
        // UIKit can ask again during a remote resize. Do not invalidate every
        // character key when neither input trait has changed.
        if model.needsInputModeSwitchKey != needsInputModeSwitchKey { model.needsInputModeSwitchKey = needsInputModeSwitchKey }
        guard let document = currentDocumentIdentifier else {
            doubleSpaceState.reset()
            expectedHostEdit = nil
            if hostSignature != nil {
                hostSignature = nil
                model.hostDidEdit(invalidateMode: true)
            }
            return
        }
        let title = Self.returnTitle(for: textDocumentProxy.returnKeyType)
        if model.returnTitle != title { model.returnTitle = title }
        let proxy = textDocumentProxy
        let signature = HostSignature(documentIdentifier: document, traits: KeyboardHostInputTraits(reading: proxy))
        if signature != hostSignature {
            hostSignature = signature
            doubleSpaceState.reset()
            expectedHostEdit = nil
            model.hostDidEdit(invalidateMode: true)
        }
        guard !model.isSearching else { return }
        let capitalization: KeyboardAutomaticCapitalization
        if !permitsEnglishAssistance { capitalization = .none }
        else {
            switch proxy.autocapitalizationType ?? .sentences {
            case .none: capitalization = .none
            case .words: capitalization = .words
            case .allCharacters: capitalization = .allCharacters
            default: capitalization = .sentences
            }
        }
        let literalScope = currentLiteralWriteScope()
        guard !literalWriteTransaction.matches(scope: literalScope) else { return }
        model.synchronizeCapitalization(KeyboardEnglishInputPolicy.shouldCapitalize(mode: capitalization, before: proxy.documentContextBeforeInput))
    }

    private var permitsEnglishAssistance: Bool {
        KeyboardHostInputTraits(reading: textDocumentProxy).permitsEnglishAssistance
    }

    private static func contextSuffix(_ text: String) -> [Unicode.Scalar] {
        Array(text.unicodeScalars.suffix(KeyboardEnglishInputPolicy.maximumContextScalars))
    }

    private func acknowledgeHostChange() {
        let expected = expectedHostEdit
        expectedHostEdit = nil
        let literalScope = currentLiteralWriteScope()
        if literalWriteTransaction.matches(scope: literalScope) {
            doubleSpaceState.reset()
            return
        }
        if let expected, expected.document == currentDocumentIdentifier,
           ProcessInfo.processInfo.systemUptime <= expected.expires,
           textDocumentProxy.selectedText?.isEmpty != false,
           let context = textDocumentProxy.documentContextBeforeInput,
           Self.contextSuffix(context) == expected.before { return }
        doubleSpaceState.reset()
        // Additional same-document text notifications can follow our own
        // edits. Reset punctuation/case hints, but do not invalidate another
        // finger's valid captured key. Document/traits are checked separately.
        model.hostDidEdit()
    }

    @discardableResult
    private func insertHostText(_ text: String, literalToken: UUID? = nil) -> Bool {
        guard literalWriteToken == nil || literalWriteToken == literalToken,
              let document = currentDocumentIdentifier else { return false }
        let proxy = textDocumentProxy
        if let before = proxy.documentContextBeforeInput {
            expectedHostEdit = ExpectedHostEdit(document: document,
                before: Self.contextSuffix(before + text), expires: ProcessInfo.processInfo.systemUptime + 1)
        } else { expectedHostEdit = nil }
        proxy.insertText(text)
        return true
    }

    private func currentLiteralWriteScope() -> KeyboardLiteralWriteScope? {
        guard !model.isSearching, !model.hasSymbolBoardOverlay,
              let document = currentDocumentIdentifier else { return nil }
        return KeyboardLiteralWriteScope(typingState: model.typingState, documentIdentifier: document,
            modeIdentifier: model.inputModeID, interactionIdentifier: deleteInteractionID)
    }

    private func insertLiteralGestureText(_ text: String) -> Bool {
        guard literalWriteToken == nil, let scope = currentLiteralWriteScope(),
              let token = literalWriteTransaction.begin(scope: scope) else { return false }
        literalWriteToken = token
        defer {
            literalWriteTransaction.invalidate(token: token)
            if literalWriteToken == token { literalWriteToken = nil }
        }
        let accepted = insertHostText(text, literalToken: token)
        let currentScope = currentLiteralWriteScope()
        if literalWriteTransaction.finish(token: token, accepted: accepted, scope: currentScope) {
            model.didInsertLiteralGesture(capturedState: scope.typingState)
        }
        return accepted
    }

    private func didEditHostText() {
        doubleSpaceState.reset()
        model.hostDidEdit()
        synchronizeHostTraits()
    }

    @objc private func updateBackdrop() {
        let opaque = UIAccessibility.isReduceTransparencyEnabled
        view.backgroundColor = opaque ? KeyboardPalette.backgroundUI : .clear
        view.isOpaque = opaque
    }

    private func updateKeyboardHeight() {
        let pad = traitCollection.userInterfaceIdiom == .pad
        let scene = view.window?.windowScene
        let sceneSize: CGSize?
        let landscape: Bool
        if #available(iOS 26.0, *) {
            let geometry = scene?.effectiveGeometry
            sceneSize = geometry?.coordinateSpace.bounds.size
            landscape = geometry?.interfaceOrientation.isLandscape == true
        } else {
            sceneSize = scene?.coordinateSpace.bounds.size
            landscape = scene?.interfaceOrientation.isLandscape == true
        }
        let landscapePad = pad && KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: view.bounds.width,
            sceneSize: sceneSize, displaySize: scene?.screen.bounds.size ?? view.window?.screen.bounds.size,
            orientationIsLandscape: landscape)
            && KeyboardTypingLayoutPolicy.usesANSI(availableWidth: view.bounds.width - 16, isPad: pad, isLandscape: true)
        if model.isLandscapePadLayout != landscapePad { model.isLandscapePadLayout = landscapePad }
        let metrics = KeyboardLayoutPolicy.metrics(
            viewWidth: view.bounds.width, displaySize: scene?.screen.bounds.size,
            sceneHeight: sceneSize?.height, isPad: pad,
            compactVertical: traitCollection.verticalSizeClass == .compact,
            showsSymbolBar: model.showsSymbolBar,
            showsNumberRow: model.showsNumberRow || (landscapePad && model.padLayout == .ansiNumbers),
            searching: model.isSearching)
        if model.isCompactLayout != metrics.isCompactLayout { model.isCompactLayout = metrics.isCompactLayout }
        if model.isPadLayout != pad { model.isPadLayout = pad }
        let typingHeight = metrics.typingKeyHeight
        if model.typingKeyHeight != typingHeight { model.typingKeyHeight = typingHeight }
        applyKeyboardHeight(metrics.height)
    }



    private func applyKeyboardHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        guard let input = view as? KeyboardSelfSizingInputView else { return }
        var changed = false
        UIView.performWithoutAnimation {
            changed = input.requestHeight(height)
            if changed {
                // Request remote negotiation; do not forge a local frame or
                // force layout to masquerade as remote acknowledgement.
                view.setNeedsLayout()
                view.superview?.setNeedsLayout()
            }
        }
        guard changed else { return }
    }

    private func makeBoardConfigurationGuard(renderedMode: UUID) -> (() -> Bool)? {
        guard renderedMode == model.inputModeID, let document = currentDocumentIdentifier else { return nil }
        let interaction = deleteInteractionID
        return { [weak self] in
            guard let self else { return false }
            return self.model.inputModeID == renderedMode
                && self.currentDocumentIdentifier == document && self.deleteInteractionID == interaction
        }
    }

    /// An editor may survive a height change; individual presses still use
    /// the stricter interaction generation captured at their own touch-down.
    private func makeBoardConfigurationSessionGuard(renderedMode: UUID) -> (() -> Bool)? {
        guard renderedMode == model.inputModeID, let document = currentDocumentIdentifier else { return nil }
        return { [weak self] in
            guard let self else { return false }
            return self.model.inputModeID == renderedMode
                && self.currentDocumentIdentifier == document
        }
    }

    private func makeTypingVariantActions(renderedMode: UUID, key: String, hasAuxiliaryRow: Bool,
                                          isAuxiliaryKey: Bool, widePad: Bool, ansiPad: Bool) -> KeyboardVariantActions? {
        guard !model.showsUnicode, !model.hasSymbolBoardOverlay, let current = makeBoardConfigurationGuard(renderedMode: renderedMode),
              model.typingAuxiliaryRowVisible.map({ $0 == hasAuxiliaryRow }) ?? true,
              model.typingWidePadVisible.map({ $0 == widePad }) ?? !widePad,
              model.typingANSIPadVisible.map({ $0 == ansiPad }) ?? !ansiPad,
              !ansiPad || model.isLandscapePadLayout,
              !ansiPad || widePad || model.typingState.layout != .letters,
              !widePad || model.isPadLayout,
              let keyID = KeyboardKeySettings.identifier(forCharacter: key) else { return nil }
        let captured = model.typingState
        let padLayout = model.padLayout
        let original = isAuxiliaryKey
            ? (hasAuxiliaryRow ? KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: key, layout: captured.layout, ansiPad: ansiPad) : nil)
            : KeyboardTypingLayoutPolicy.output(for: key, state: captured, hasAuxiliaryRow: hasAuxiliaryRow, widePad: widePad, ansiPad: ansiPad, padLayout: padLayout)
        guard let original else { return nil }
        let settings = model.keySettings
        let tapText = settings.tapOutput(for: keyID, defaultText: original,
            shifted: KeyboardTypingLayoutPolicy.usesShiftedTap(for: key, state: captured, ansiPad: ansiPad))
        let choices = KeyboardVariantPolicy.options(text: original,
            variants: KeyboardVariantPolicy.englishVariants(for: key, uppercase: captured.shift != .lowercase))
        let gestures = KeyboardVariantPolicy.gestureCandidates(for: key, original: original, state: captured, settings: settings)
        let accepts: () -> Bool = { [weak self] in
            current() && self?.model.showsUnicode == false && self?.model.hasSymbolBoardOverlay == false
                && self?.model.keySettings == settings && self?.model.padLayout == padLayout
                && (self?.model.typingAuxiliaryRowVisible.map({ $0 == hasAuxiliaryRow }) ?? true)
                && (self?.model.typingWidePadVisible.map({ $0 == widePad }) ?? !widePad)
                && (self?.model.typingANSIPadVisible.map({ $0 == ansiPad }) ?? !ansiPad)
        }
        let insertOrdinary: (String) -> Bool = { [weak self] text in
            guard let self, accepts() else { return false }
            self.doubleSpaceState.reset()
            guard self.insertHostText(text) else { return false }
            if captured.layout == .letters && !isAuxiliaryKey && (ansiPad || captured.output(for: key) != nil) { self.model.didInsertTypingKey(key, capturedState: captured, ansiPad: ansiPad, padLayout: padLayout) }
            else { self.model.didInsertNumberRowKey(capturedState: captured) }
            self.synchronizeHostTraits()
            return true
        }
        return .init(isCurrent: accepts, insert: { text in
            KeyboardVariantPolicy.contains(text, in: choices) && insertOrdinary(text)
        }, options: choices, longPressOptions: gestures.longPress, swipeUp: gestures.swipeUp, swipeDown: gestures.swipeDown,
           tap: { tapText.map(insertOrdinary) ?? false },
           insertGesture: { [weak self] text, gesture in
            guard let self, accepts(), gesture == .longPress || gesture == .swipeUp || gesture == .swipeDown else { return false }
            let allowed = gesture == .longPress ? gestures.longPress : gesture == .swipeUp ? gestures.swipeUp : gestures.swipeDown
            guard KeyboardVariantPolicy.contains(text, in: allowed) else { return false }
            self.doubleSpaceState.reset()
            if gesture == .longPress, captured.layout == .letters, !isAuxiliaryKey, captured.output(for: key) != nil {
                guard self.insertHostText(text) else { return false }
                self.model.didInsertTypingKey(key, capturedState: captured)
                self.synchronizeHostTraits()
            } else { return self.insertLiteralGestureText(text) }
            return true
        })
    }

    private func makeShiftSlideAction(renderedMode: UUID) -> ((String) -> Bool)? {
        guard !model.showsUnicode, model.typingState.layout == .letters,
              let current = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let captured = model.typingState
        let settings = model.keySettings
        let auxiliary = model.typingAuxiliaryRowVisible == true
        let wide = model.typingWidePadVisible == true
        let ansi = model.typingANSIPadVisible == true
        let preset = model.padLayout
        return { [weak self] key in
            guard let self, current(), !self.model.showsUnicode, self.model.typingState == captured,
                  self.model.keySettings == settings, self.model.padLayout == preset,
                  (self.model.typingAuxiliaryRowVisible == true) == auxiliary,
                  (self.model.typingWidePadVisible == true) == wide,
                  (self.model.typingANSIPadVisible == true) == ansi,
                  let keyID = KeyboardKeySettings.identifier(forCharacter: key),
                  let original = KeyboardTypingLayoutPolicy.output(for: key, state: captured.momentarilyShifted(),
                      hasAuxiliaryRow: auxiliary, widePad: wide, ansiPad: ansi, padLayout: preset),
                  let text = settings.tapOutput(for: keyID, defaultText: original, shifted: true) else { return false }
            self.doubleSpaceState.reset()
            guard self.insertHostText(text) else { return false }
            self.model.didInsertTypingKey(key, capturedState: captured, ansiPad: ansi, padLayout: preset)
            self.synchronizeHostTraits()
            return true
        }
    }

    /// Spell checking and dictation in the host follow the current layout.
    private func applyPrimaryLanguage() {
        let alphabet = model.typingState.alphabet
        primaryLanguage = alphabet == .english ? "en-US" : alphabet.id
    }

    /// With several layouts, holding Space lists them, current first; a tap
    /// still types a space.
    private func makeLayoutActions(renderedMode: UUID) -> KeyboardVariantActions? {
        guard model.layouts.count > 1, !model.isSearching, !model.hasSymbolBoardOverlay,
              let current = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let ids = model.layouts.map(\.id)
        let space = makeInputAction(renderedMode: renderedMode, command: .space)
        let accepts: () -> Bool = { [weak self] in
            guard let self else { return false }
            return current() && !self.model.isSearching && !self.model.hasSymbolBoardOverlay && self.model.layouts.map(\.id) == ids
        }
        return .init(isCurrent: accepts, insert: { [weak self] id in
            guard let self, accepts(), ids.contains(id) else { return false }
            self.doubleSpaceState.reset(); self.expectedHostEdit = nil
            return self.model.selectLayout(id)
        }, longPressOptions: KeyboardModel.layoutChoices(current: model.typingState.alphabet, layouts: model.layouts), tap: space)
    }

    private func makeFavoritesActions(renderedMode: UUID) -> KeyboardVariantActions? {
        guard !model.hasSymbolBoardOverlay, let guardCurrent = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let current: () -> Bool = { [weak self] in guardCurrent() && self?.model.hasSymbolBoardOverlay == false }
        return .init(isCurrent: current, insert: { [weak self] _ in
            guard let self, current() else { return false }
            self.doubleSpaceState.reset(); self.expectedHostEdit = nil
            return self.model.toggleFavorites()
        }, hold: { [weak self] in
            guard let self, current() else { return false }
            self.doubleSpaceState.reset(); self.expectedHostEdit = nil
            self.model.openSymbolBoardManager()
            return true
        })
    }

    private func makeSymbolBoardActions(renderedMode: UUID, boardID: String, key: SymbolBoardKey) -> KeyboardVariantActions? {
        guard let current = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let activeBoardID = SymbolBoardStore.shared.activeBoardID
        let choices = KeyboardVariantPolicy.options(text: key.text, variants: key.variants)
        let accepts: () -> Bool = { [weak self] in
            guard let self else { return false }
            return current() && !self.model.isSearching && !self.model.hasSymbolBoardOverlay
                && self.model.inspection == nil && self.model.symbolBoardInspectionText == nil
                && SymbolBoardStore.shared.activeBoardID == activeBoardID
                && (self.model.showsUnicode ? activeBoardID == boardID : SymbolBoardStore.shared.typingBoard.id == boardID)
                && SymbolBoardStore.shared.key(boardID: boardID, keyID: key.id) == key
        }
        guard accepts() else { return nil }
        return .init(isCurrent: accepts, insert: { [weak self] text in
            guard let self, accepts(), KeyboardVariantPolicy.contains(text, in: choices) else { return false }
            self.doubleSpaceState.reset()
            guard self.insertHostText(text) else { return false }
            if text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first {
                CharacterStore.shared.recordUse(scalar.value)
            } else if let emoji = self.model.emojiCatalog.entries.first(where: { $0.text.utf16.elementsEqual(text.utf16) }) {
                CharacterStore.shared.recordEmojiUse(emoji)
            }
            self.didEditHostText()
            return true
        }, inspect: { [weak self] text in
            guard let self, accepts(), KeyboardVariantPolicy.contains(text, in: choices) else { return false }
            self.model.inspectText(text)
            return true
        })
    }

    private func makeQueryAction(renderedMode: UUID, renderedQuery: String) -> KeyboardQueryActionSession? {
        guard renderedMode == model.inputModeID, !model.hasSymbolBoardOverlay,
              model.query.utf16.elementsEqual(renderedQuery.utf16),
              let document = currentDocumentIdentifier else { return nil }
        let originalQuery = Array(renderedQuery.utf16)
        let context = KeyboardInputActionContext(modeIdentifier: renderedMode,
            documentIdentifier: document, interactionIdentifier: deleteInteractionID)
        return KeyboardQueryActionSession(context: context, currentContext: { [weak self] in
            guard let self, !self.model.hasSymbolBoardOverlay, self.model.query.utf16.elementsEqual(originalQuery),
                  let document = self.currentDocumentIdentifier else { return nil }
            return KeyboardInputActionContext(modeIdentifier: self.model.inputModeID,
                documentIdentifier: document, interactionIdentifier: self.deleteInteractionID)
        }, activate: { [weak self] in
            guard let self else { return nil }
            self.model.beginSearch()
            // The action session may adopt exactly this owned activation's
            // final mode once, after rechecking document and interaction generation.
            return self.model.isSearching ? self.model.inputModeID : nil
        }, moveCaret: { [weak self] offset in self?.model.moveQueryCaret(toUTF16Offset: offset) })
    }

    private func makeInspectableActions(renderedMode: UUID, item: KeyboardItem) -> KeyboardInspectableInteraction.Actions? {
        let acceptsScope: () -> Bool = { [weak self] in
            guard let self else { return false }
            return !self.model.hasSymbolBoardOverlay && self.model.showsUnicode
        }
        guard renderedMode == model.inputModeID, acceptsScope(),
              let document = currentDocumentIdentifier else { return nil }
        let context = KeyboardInputActionContext(modeIdentifier: renderedMode,
            documentIdentifier: document, interactionIdentifier: deleteInteractionID)
        let current: () -> KeyboardInputActionContext? = { [weak self] in
            guard let self, acceptsScope(),
                  let document = self.currentDocumentIdentifier else { return nil }
            return KeyboardInputActionContext(modeIdentifier: self.model.inputModeID,
                documentIdentifier: document, interactionIdentifier: self.deleteInteractionID)
        }
        return .init(insert: context.guardedAction(currentContext: current, perform: { [weak self] in
            guard let self else { return false }
            switch item {
            case .character(let character):
                guard self.insertHostText(character.text) else { return false }
                CharacterStore.shared.recordUse(character.codePoint)
            case .emoji(let emoji):
                guard self.insertHostText(emoji.text) else { return false }
                CharacterStore.shared.recordEmojiUse(emoji)
            }
            self.didEditHostText()
            return true
        }), inspect: context.guardedAction(currentContext: current, perform: { [weak self] in
            guard let self else { return false }
            self.model.inspect(item)
            return true
        }))
    }

    private func makeDeleteAction(renderedMode: UUID, isQuery: Bool) -> RepeatingDeleteButton.DeleteAction {
        guard literalWriteToken == nil, renderedMode == model.inputModeID, !model.hasSymbolBoardOverlay,
              let document = currentDocumentIdentifier else { return { false } }
        let interactionID = deleteInteractionID
        let context = KeyboardDeleteContext(modeIdentifier: renderedMode, isQuery: isQuery, documentIdentifier: document)
        return context.guardedAction(currentContext: { [weak self] in
            guard let self, self.literalWriteToken == nil, !self.model.hasSymbolBoardOverlay, self.deleteInteractionID == interactionID,
                  let document = self.currentDocumentIdentifier else { return nil }
            return KeyboardDeleteContext(modeIdentifier: self.model.inputModeID, isQuery: self.model.isSearching, documentIdentifier: document)
        }, delete: { [weak self] in
            if isQuery { self?.model.deleteQueryCharacter() }
            else {
                self?.expectedHostEdit = nil
                self?.textDocumentProxy.deleteBackward()
                self?.didEditHostText()
            }
        })
    }

    /// Capture the rendered mode and document at touch-down. A scope change
    /// between rendering, pressing and releasing rejects the old action.
    private func makeInputAction(renderedMode: UUID, command: KeyboardInputCommand) -> () -> Bool {
        guard renderedMode == model.inputModeID, !model.hasSymbolBoardOverlay,
              let document = currentDocumentIdentifier else { return { false } }
        let bound = KeyboardInputActionContext(modeIdentifier: renderedMode,
            documentIdentifier: document, interactionIdentifier: deleteInteractionID)
        return bound.guardedAction(currentContext: { [weak self] in
            guard let self, !self.model.hasSymbolBoardOverlay, let document = self.currentDocumentIdentifier else { return nil }
            return KeyboardInputActionContext(modeIdentifier: self.model.inputModeID,
                documentIdentifier: document, interactionIdentifier: self.deleteInteractionID)
        }, perform: { [weak self] in
            guard let self else { return false }
            switch command {
            case .query(let key):
                guard self.model.isSearching else { return false }
                self.doubleSpaceState.reset()
                self.model.appendQuery(key)
            case .collapse:
                self.dismissKeyboard()
            case .toolbar:
                self.doubleSpaceState.reset()
                self.expectedHostEdit = nil
                self.model.toggleUnicodeToolbar()
            case .tab:
                guard !self.model.showsUnicode, self.model.isPadLayout, self.model.typingWidePadVisible == true,
                      self.model.typingState.layout == .letters else { return false }
                self.doubleSpaceState.reset()
                guard self.insertHostText("\t") else { return false }
                self.didEditHostText()
            case .capsLock:
                guard !self.model.showsUnicode, self.model.isPadLayout, self.model.typingWidePadVisible == true,
                      self.model.typingState.layout == .letters else { return false }
                self.doubleSpaceState.reset(); self.expectedHostEdit = nil
                self.model.toggleCapsLock()
            case .space: self.spaceKey()
            case .returnKey: self.returnKey()
            case .shift:
                guard !self.model.showsUnicode else { return false }
                self.doubleSpaceState.reset()
                self.expectedHostEdit = nil
                self.model.pressShift()
            case .layout(let layout):
                guard !self.model.showsUnicode else { return false }
                self.model.selectTypingLayout(layout)
                self.synchronizeHostTraits()
            }
            return true
        })
    }

    private func spaceKey() {
        if model.isSearching {
            doubleSpaceState.reset()
            model.appendQuery(" ")
            return
        }
        guard literalWriteToken == nil else { return }
        let proxy = textDocumentProxy
        guard let document = currentDocumentIdentifier else { doubleSpaceState.reset(); return }
        let mode = model.inputModeID
        let before = proxy.documentContextBeforeInput
        let selectionIsEmpty = proxy.selectedText?.isEmpty != false
        let decision = doubleSpaceState.spaceTap(before: before, at: ProcessInfo.processInfo.systemUptime,
            scope: KeyboardEnglishInputScope(documentIdentifier: document, modeIdentifier: mode),
            enabled: permitsEnglishAssistance && selectionIsEmpty && !model.showsUnicode)
        if decision == .replacePreviousSpaceWithPeriod,
           let before, before.unicodeScalars.last == " ",
           currentDocumentIdentifier == document, model.inputModeID == mode,
           proxy.selectedText?.isEmpty != false,
           let current = proxy.documentContextBeforeInput,
           Self.contextSuffix(current) == Self.contextSuffix(before) {
            // Delete only the ASCII space whose exact context was authorized.
            expectedHostEdit = nil
            proxy.deleteBackward()
            // A proxy mutation can synchronously change focus or input mode.
            // Never send the second write into a replacement document, and
            // never retry or undo an already-dispatched deletion there.
            guard currentDocumentIdentifier == document,
                  model.inputModeID == mode else {
                doubleSpaceState.reset()
                expectedHostEdit = nil
                return
            }
            insertHostText(". ")
            model.hostDidEdit()
        } else { insertHostText(" "); model.hostDidEdit() }
        synchronizeHostTraits()
    }

    private func returnKey() {
        if model.inspection != nil { model.closeInspection() }
        else if model.symbolBoardInspectionText != nil { model.closeSymbolBoardInspection() }
        else if model.isSearching { model.endSearch() }
        else { insertHostText("\n"); didEditHostText() }
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
        NotificationCenter.default.removeObserver(self)
    }
}


private enum KeyboardSection: String, CaseIterable {
    case symbols = "Symbols"
    case emojis = "Emojis"
    case blocks = "Blocks"
    case saved = "Saved"

    var title: String { self == .saved ? "Pages" : rawValue }
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
        case .character(let character): return character.name
        case .emoji(let emoji): return emoji.name
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

private enum KeyboardInputCommand {
    case query(String), space, returnKey, shift, capsLock, tab, layout(KeyboardTypingLayout), toolbar, collapse
}

private enum KeyboardPanel { case typing, unicode }

@MainActor
private final class KeyboardTypingModel: ObservableObject {
    @Published private(set) var state = KeyboardTypingState()
    func update(_ change: (inout KeyboardTypingState) -> Void) {
        var next = state
        change(&next)
        if next != state { state = next }
    }
}

@MainActor
private final class KeyboardModel: ObservableObject {
    @Published private(set) var panel: KeyboardPanel = .typing {
        didSet {
            if panel != oldValue { invalidateInputMode() }
        }
    }
    let typing = KeyboardTypingModel()
    @Published private(set) var keySettings: KeyboardKeySettings.Snapshot
    @Published private var selectedPadLayout: KeyboardPadLayout
    /// The ANSI presets are English keyboards; other layouts use the iPad arrangement.
    var padLayout: KeyboardPadLayout { typingState.alphabet == .english ? selectedPadLayout : .stock }
    /// The enabled base keyboards in the app's order; never empty.
    @Published private(set) var layouts: [KeyboardAlphabet] = [.english]
    var alphabetChanged: (() -> Void)?
    private static let layoutDefaultsKey = "keyboardLayout"
    var typingState: KeyboardTypingState { typing.state }
    // The view acknowledges its current row budget without publishing a
    // second typing state or changing Shift for a geometry-only update.
    var typingAuxiliaryRowVisible: Bool?
    var typingWidePadVisible: Bool?
    var typingANSIPadVisible: Bool?
    @Published var typingKeyHeight: CGFloat = KeyboardTypingLayoutPolicy.regularKeyHeight
    @Published private(set) var inputModeID = UUID()
    var inputModeChanged: (() -> Void)?
    var typingActivated: (() -> Void)?
    @Published var section: KeyboardSection = .symbols {
        didSet {
            if section != oldValue { invalidateInputMode() }
            if isSearching || hasSearchQuery { scheduleSearch() }
        }
    }
    @Published var isSearching = false {
        didSet { if isSearching != oldValue { invalidateInputMode() } }
    }
    @Published var query = "" {
        didSet {
            queryCursor = query.count
            if query != oldValue { queryEdited?() }
            scheduleSearch()
        }
    }
    var queryEdited: (() -> Void)?
    @Published private(set) var queryCursor = 0
    @Published private(set) var edition: UnicodeEdition {
        didSet {
            if edition != oldValue { invalidateInputMode() }
            refreshCatalog()
        }
    }
    /// Characters are always listed from the lowest code point.
    let order = UnicodeSortOrder.codePoint
    @Published private(set) var useUnicodeFonts: Bool {
        didSet {
            if oldValue && !useUnicodeFonts { UnicodeFontSupport.clearCache() }
        }
    }
    @Published private(set) var showsCollapseKey: Bool
    @Published private(set) var showsSymbolBar: Bool
    @Published private(set) var searchBarInsteadOfSymbols: Bool
    @Published private(set) var showsNumberRow: Bool
    @Published private(set) var symbolPagesToolbarVisible: Bool?
    var showsUnicodeToolbar: Bool { symbolPagesToolbarVisible ?? (showsUnicode || (showsSymbolBar && searchBarInsteadOfSymbols)) }
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
    @Published var inspection: KeyboardItem? {
        didSet {
            if inspection?.keyIdentifier != oldValue?.keyIdentifier { invalidateInputMode() }
            if !batchingPresentation { presentationChanged?() }
        }
    }
    @Published var symbolBoardManagerPresented = false {
        didSet { if symbolBoardManagerPresented != oldValue { invalidateInputMode() } }
    }
    @Published var symbolBoardActionError: String?
    @Published var symbolBoardInspectionText: String? {
        didSet {
            if symbolBoardInspectionText.map({ Array($0.utf16) }) != oldValue.map({ Array($0.utf16) }) { invalidateInputMode() }
            if !batchingPresentation { presentationChanged?() }
        }
    }
    @Published var showFavorites = true {
        didSet { if showFavorites != oldValue { invalidateInputMode() } }
    }
    @Published var needsInputModeSwitchKey = true
    @Published var returnTitle = "Return"
    @Published var isCompactLayout = false
    @Published var isPadLayout = false
    @Published var isLandscapePadLayout = false
    var presentationChanged: (() -> Void)?
    private var batchingPresentation = false
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
    private var catalogLoaded = false

    var showsUnicode: Bool { panel == .unicode || isSearching || inspection != nil || symbolBoardInspectionText != nil || symbolBoardManagerPresented }
    var hasSymbolBoardOverlay: Bool { symbolBoardManagerPresented }
    var isShowingSymbolPages: Bool { panel == .unicode && section == .saved && !isSearching }
    var modeValue: String { inspection != nil || symbolBoardInspectionText != nil ? "inspection" : isSearching ? "query" : panel == .typing ? "typing" : "unicode" }
    var typingLayoutValue: String {
        switch typingState.layout { case .letters: return "letters"; case .numbers: return "numbers"; case .symbols: return "symbols" }
    }
    private func invalidateInputMode() { inputModeID = UUID(); inputModeChanged?() }
    func pressShift() { typing.update { $0.pressShift(at: ProcessInfo.processInfo.systemUptime) } }
    func toggleCapsLock() { typing.update { $0.toggleCapsLock() } }
    static func layoutChoices(current: KeyboardAlphabet, layouts: [KeyboardAlphabet]) -> [String] {
        [current.id] + layouts.map(\.id).filter { $0 != current.id }
    }
    func selectTypingLayout(_ layout: KeyboardTypingLayout) {
        guard layout != typingState.layout else { return }
        typing.update { $0.selectLayout(layout) }
        invalidateInputMode()
        presentationChanged?()
    }
    func didInsertTypingKey(_ key: String, capturedState: KeyboardTypingState, ansiPad: Bool = false, padLayout: KeyboardPadLayout = .ansiNumbers) {
        // Another finger may have changed Shift since this key went down.
        // The captured character still inserts, without consuming that newer
        // explicit Shift choice or dropping a valid chorded key release.
        guard typingState == capturedState else { return }
        typing.update { $0.didInsertKey(key, ansiPad: ansiPad, padLayout: padLayout) }
    }
    func didInsertNumberRowKey(capturedState: KeyboardTypingState) {
        guard typingState == capturedState else { return }
        typing.update { $0.resetTapSequence() }
    }
    func didInsertLiteralGesture(capturedState: KeyboardTypingState) {
        guard typingState == capturedState else { return }
        typing.update { $0.didInsertLiteralGesture() }
    }
    func synchronizeCapitalization(_ uppercase: Bool) { typing.update { $0.synchronizeAutomaticCapitalization(uppercase) } }
    func hostDidEdit(invalidateMode: Bool = false) {
        typing.update { $0.didEditText() }
        if invalidateMode { invalidateInputMode() }
    }
    private func ensureCatalogLoaded() {
        guard !catalogLoaded else { return }
        catalogLoaded = true
        refreshCatalog()
    }
    func openUnicode() {
        ensureCatalogLoaded()
        symbolPagesToolbarVisible = nil
        panel = .unicode
        presentationChanged?()
    }
    @discardableResult
    func toggleFavorites() -> Bool {
        symbolBoardActionError = nil
        if isShowingSymbolPages { openTyping(); return true }
        let boards = SymbolBoardStore.shared
        guard boards.selectPreferredStarBoard() else {
            symbolBoardActionError = "Unable to open your preferred page. Hold the star to review pages."
            return false
        }
        openFavorites()
        return true
    }

    func toggleUnicodeToolbar() {
        if isShowingSymbolPages {
            symbolPagesToolbarVisible = !showsUnicodeToolbar
            invalidateInputMode()
            presentationChanged?()
            return
        }
        if showsUnicode { openTyping() } else { openUnicode() }
    }
    func openFavorites() {
        let toolbarWasVisible = showsUnicodeToolbar
        ensureCatalogLoaded()
        showFavorites = true
        selectSection(.saved)
        symbolPagesToolbarVisible = toolbarWasVisible
    }
    @discardableResult
    func selectSymbolPage(_ page: SymbolPageID) -> Bool {
        guard isShowingSymbolPages, !hasSymbolBoardOverlay else { return false }
        switch page {
        case .board(let id):
            let changed = !showFavorites || SymbolBoardStore.shared.activeBoardID != id
            guard SymbolBoardStore.shared.selectBoard(id) else {
                symbolBoardActionError = "This page could not be opened. Your saved pages have been kept."
                return false
            }
            showFavorites = true
            if changed { invalidateInputMode() }
        case .recent:
            showFavorites = false
        }
        symbolBoardActionError = nil
        return true
    }
    /// Pages are configured in the app; the keyboard lists them to open one.
    func openSymbolBoardManager() {
        symbolBoardActionError = nil
        openFavorites()
        symbolBoardManagerPresented = true
    }
    /// Save in the keyboard's details adds to Favorites, or removes from it.
    @discardableResult
    func toggleFavorite(_ text: String) -> Bool {
        let boards = SymbolBoardStore.shared
        guard KeyboardVariantPolicy.validText(text), boards.canEdit else { return false }
        if let key = boards.boards.first(where: { $0.id == SymbolBoardStore.favoritesID })?.keys
            .first(where: { SymbolBoardKey.exact($0.text, text) }) {
            return boards.removeKey(boardID: SymbolBoardStore.favoritesID, keyID: key.id)
        }
        return boards.add(text: text, to: SymbolBoardStore.favoritesID) != nil
    }
    func inspectText(_ text: String) {
        guard KeyboardVariantPolicy.validText(text) else { return }
        batchingPresentation = true
        inspection = nil
        panel = .unicode
        isSearching = false
        symbolBoardInspectionText = text
        batchingPresentation = false
        presentationChanged?()
    }
    func closeSymbolBoardInspection() { symbolBoardInspectionText = nil }
    func openTyping() {
        batchingPresentation = true
        inspection = nil
        symbolBoardInspectionText = nil
        symbolBoardManagerPresented = false
        symbolPagesToolbarVisible = nil
        isSearching = false
        selectTypingLayout(.letters)
        panel = .typing
        batchingPresentation = false
        // Query edits never change host Shift. On returning, recompute only
        // its automatic hint against the actual receiving document; manual
        // Shift/caps remain authoritative in the typing policy.
        typingActivated?()
        presentationChanged?()
    }
    func selectSection(_ section: KeyboardSection) {
        batchingPresentation = true
        inspection = nil
        symbolBoardInspectionText = nil
        panel = .unicode
        if section != .saved { symbolPagesToolbarVisible = nil }
        if section == .blocks || section == .saved { isSearching = false }
        self.section = section
        batchingPresentation = false
        presentationChanged?()
    }

    var catalog: UnicodeCatalog { edition.catalog }
    var emojiCatalog: EmojiCatalog { edition.emojiCatalog }
    var editionValue: String { edition.rawValue }
    var hasSearchQuery: Bool {
        (section == .symbols || section == .emojis) && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var queryCaretUTF16Offset: Int { KeyboardQueryPolicy.utf16Offset(forCharacterOffset: queryCursor, in: query) }

    init() {
        let appSettings = UnicodeEditionSettings.shared.loadSnapshot()
        keySettings = KeyboardKeySettings.shared.loadSnapshot()
        edition = appSettings.edition
        useUnicodeFonts = appSettings.useUnicodeFonts
        showsSymbolBar = appSettings.showsSymbolBar
        searchBarInsteadOfSymbols = appSettings.searchBarInsteadOfSymbols
        showsNumberRow = appSettings.showsNumberRow
        showsCollapseKey = appSettings.showsCollapseKey
        selectedPadLayout = appSettings.padLayout
        adoptLayouts(appSettings.layouts, keepingCurrent: false)
    }

    /// Keeps the current layout while it stays enabled, otherwise the one
    /// used last, otherwise the first.
    private func adoptLayouts(_ ids: [String], keepingCurrent: Bool) {
        let enabled = ids.compactMap(KeyboardAlphabet.alphabet(id:))
        let next = enabled.isEmpty ? [KeyboardAlphabet.english] : enabled
        if layouts != next { layouts = next }
        let remembered = defaults.string(forKey: Self.layoutDefaultsKey).flatMap { id in next.first { $0.id == id } }
        applyAlphabet(keepingCurrent && next.contains(typingState.alphabet) ? typingState.alphabet : remembered ?? next[0])
    }
    /// The keyboard remembers the chosen layout in its own defaults, which
    /// needs no Full Access.
    @discardableResult func selectLayout(_ id: String) -> Bool {
        guard let alphabet = layouts.first(where: { $0.id == id }) else { return false }
        defaults.set(alphabet.id, forKey: Self.layoutDefaultsKey)
        applyAlphabet(alphabet)
        return true
    }
    private func applyAlphabet(_ alphabet: KeyboardAlphabet) {
        guard alphabet != typingState.alphabet else { return }
        typing.update { $0.selectAlphabet(alphabet) }
        invalidateInputMode()
        presentationChanged?()
        alphabetChanged?()
    }

    func refreshEditionFromAppSettings() {
        if UnicodeFontSupport.refreshDownloadedFonts(force: true) { invalidateInputMode() }
        let selected = UnicodeEditionSettings.shared.loadSnapshot()
        if edition != selected.edition { edition = selected.edition }
        if useUnicodeFonts != selected.useUnicodeFonts { useUnicodeFonts = selected.useUnicodeFonts }
        if showsCollapseKey != selected.showsCollapseKey { showsCollapseKey = selected.showsCollapseKey }
        if selectedPadLayout != selected.padLayout { selectedPadLayout = selected.padLayout; invalidateInputMode(); presentationChanged?() }
        if layouts.map(\.id) != selected.layouts {
            adoptLayouts(selected.layouts, keepingCurrent: true)
            invalidateInputMode(); presentationChanged?()
        }
        if showsSymbolBar != selected.showsSymbolBar || searchBarInsteadOfSymbols != selected.searchBarInsteadOfSymbols {
            showsSymbolBar = selected.showsSymbolBar; searchBarInsteadOfSymbols = selected.searchBarInsteadOfSymbols
            invalidateInputMode(); presentationChanged?()
        }
        if showsNumberRow != selected.showsNumberRow {
            showsNumberRow = selected.showsNumberRow
            invalidateInputMode(); presentationChanged?()
        }
        let keys = KeyboardKeySettings.shared.loadSnapshot()
        if keySettings != keys { keySettings = keys; invalidateInputMode() }
    }

    deinit {
        searchTask?.cancel()
        discoveryTask?.cancel()
        blockTask?.cancel()
        symbolPageTask?.cancel()
        emojiPageTask?.cancel()
    }

    func beginSearch() {
        ensureCatalogLoaded()
        guard !isSearching || inspection != nil else { return }
        batchingPresentation = true
        panel = .unicode
        symbolPagesToolbarVisible = nil
        inspection = nil
        symbolBoardInspectionText = nil
        if section == .blocks || section == .saved { section = .symbols }
        isSearching = true
        batchingPresentation = false
        scheduleSearch()
        presentationChanged?()
    }
    func endSearch() { openTyping() }
    func inspect(_ item: KeyboardItem) {
        symbolBoardInspectionText = nil
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
        characters.sorted { $0.codePoint < $1.codePoint }
    }
    func sorted(_ emojis: [UnicodeEmojiEntry]) -> [UnicodeEmojiEntry] {
        emojis.sorted { $0.codePoints.lexicographicallyPrecedes($1.codePoints) }
    }

    private func refreshCatalog() {
        guard catalogLoaded else { return }
        revision += 1
        inspection = nil
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
    // Keycaps use iOS semantic surfaces; the system tint marks selection and
    // the action key, matching the stock keyboard.
    static let accentUI = UIColor.systemBlue
    static let backgroundUI = UIColor.systemGroupedBackground
    static let keyUI = UIColor.secondarySystemGroupedBackground
    static let modifierUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.29, blue: 0.33, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    }
    static let borderUI = UIColor { traits in
        UIColor.separator.resolvedColor(with: traits).withAlphaComponent(traits.accessibilityContrast == .high ? 0.65 : 0.16)
    }
    static let actionUI = UIColor.systemBlue
    /// A key whose glyph iOS and every installed fallback still cannot draw.
    /// Opaque, so the tint reads the same over the translucent keyboard tray.
    static let missingGlyphUI = UIColor { traits in
        let key = keyUI.resolvedColor(with: traits), red = UIColor.systemRed.resolvedColor(with: traits)
        var k: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), r = k
        key.getRed(&k.0, green: &k.1, blue: &k.2, alpha: &k.3)
        red.getRed(&r.0, green: &r.1, blue: &r.2, alpha: &r.3)
        let amount: CGFloat = 0.18
        return UIColor(red: k.0 + (r.0 - k.0) * amount, green: k.1 + (r.1 - k.1) * amount,
                       blue: k.2 + (r.2 - k.2) * amount, alpha: 1)
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
    func keyboardKeySurface(radius: CGFloat = 10, modifier: Bool = false) -> some View {
        self.modifier(KeyboardKeySurface(radius: radius, isModifier: modifier))
    }

    func keyboardControlSurface(radius: CGFloat = 12) -> some View {
        modifier(KeyboardControlSurface(radius: radius))
    }
}

private struct KeyboardKeySurface: ViewModifier {
    let radius: CGFloat
    var isModifier = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background(isModifier ? Color(uiColor: KeyboardPalette.modifierUI) : KeyboardPalette.key,
                           in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct KeyboardTypingAuxiliaryRowVisible: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct KeyboardTypingANSIPadVisible: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct KeyboardTypingWidePadVisible: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct UnicodeKeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject var store: CharacterStore
    @ObservedObject var symbolBoards = SymbolBoardStore.shared
    weak var controller: KeyboardViewController?
    let delete: (UUID, Bool) -> RepeatingDeleteButton.DeleteAction
    let action: (UUID, KeyboardInputCommand) -> () -> Bool
    let shiftSlide: (UUID) -> ((String) -> Bool)?
    let keyActions: (UUID, KeyboardItem) -> KeyboardInspectableInteraction.Actions?
    let queryAction: (UUID, String) -> KeyboardQueryActionSession?
    let typingVariantActions: (UUID, String, Bool, Bool, Bool, Bool) -> KeyboardVariantActions?
    let favoritesActions: (UUID) -> KeyboardVariantActions?
    let layoutActions: (UUID) -> KeyboardVariantActions?
    let boardKeyActions: (UUID, String, SymbolBoardKey) -> KeyboardVariantActions?
    let boardConfigurationGuard: (UUID) -> (() -> Bool)?
    let boardConfigurationSessionGuard: (UUID) -> (() -> Bool)?
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: model.isPadLayout ? 70 : 58, maximum: 92), spacing: 6)]
    }
    private var keyHeight: CGFloat { model.isCompactLayout ? 50 : model.isPadLayout ? 60 : 56 }
    private var headerHeight: CGFloat { model.typingKeyHeight }
    private var controlHeight: CGFloat { model.typingKeyHeight }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Hidden native controls must leave the remote AX hierarchy.
                // The model restores the exact query and caret when shown.
                if model.showsUnicodeToolbar {
                    toolbar.frame(height: headerHeight)
                } else if model.showsSymbolBar && !model.showsUnicode {
                    symbolBar.frame(height: headerHeight)
                }
                // Preserve the same row budget with the toolbar unmounted:
                // four points before the content and before the footer.
                Color.clear.frame(height: 4).accessibilityHidden(true)
                ZStack {
                    if model.showsUnicode {
                        unicodeContent
                    } else {
                        typingContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                Color.clear.frame(height: 4).accessibilityHidden(true)
                controls
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .allowsHitTesting(!model.hasSymbolBoardOverlay)
            .accessibilityHidden(model.hasSymbolBoardOverlay)
            .overlay {
                Group {
                    if model.symbolBoardManagerPresented {
                        SymbolPageListPanel(store: symbolBoards,
                            guardFactory: { [mode = model.inputModeID] in boardConfigurationGuard(mode) },
                            open: { id in
                                model.symbolBoardManagerPresented = false
                                _ = model.selectSymbolPage(.board(id))
                            },
                            close: { model.symbolBoardManagerPresented = false })
                            .padding(8).background(KeyboardPalette.background)
                            .id(model.inputModeID)
                    }
                }
            }

        }
        .accessibilityElement(children: .contain)
        .background(KeyboardTray().ignoresSafeArea())
        .overlay(alignment: .top) {
            if let message = model.symbolBoardActionError {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button { model.symbolBoardActionError = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss guidance")
                }
                .padding(8).keyboardKeySurface(radius: 7).padding(8)
                .accessibilityIdentifier("keyboard.boards.actionError")
            }
        }
        .tint(KeyboardPalette.accent)
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .onPreferenceChange(KeyboardTypingAuxiliaryRowVisible.self) {
            model.typingAuxiliaryRowVisible = $0
        }
        .onPreferenceChange(KeyboardTypingWidePadVisible.self) { model.typingWidePadVisible = $0 }
        .onPreferenceChange(KeyboardTypingANSIPadVisible.self) { model.typingANSIPadVisible = $0 }
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
                    contextIdentifier: model.inputModeID,
                    enabled: model.showsUnicodeToolbar && !model.hasSymbolBoardOverlay,
                    actionFactory: { [mode = model.inputModeID, query = model.query] in queryAction(mode, query) }
                )
                .frame(maxWidth: .infinity).frame(height: headerHeight)
                .accessibilityHidden(!model.showsUnicodeToolbar || model.hasSymbolBoardOverlay)
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

            panelButton
            if model.showsUnicode { sectionMenu }
            // A single fixed trailing key in search, browsing and inspection.
            RepeatingDeleteKey(action: delete, isQuery: model.isSearching, route: model.inputModeID,
                enabled: model.showsUnicodeToolbar && !model.hasSymbolBoardOverlay)
                .frame(width: 42, height: headerHeight)
                .keyboardControlSurface()
                .accessibilityHidden(!model.showsUnicodeToolbar || model.hasSymbolBoardOverlay)
        }
        .frame(height: headerHeight)
    }

    private var panelButton: some View {
        Button {
            if model.showsUnicode { model.openTyping() }
            else { model.openUnicode() }
        } label: {
            HStack(spacing: 4) {
                if model.showsUnicode { Text("ABC").font(.system(size: 12, weight: .semibold)) }
                else {
                    Image(systemName: "character.book.closed").font(.system(size: 14))
                    Text("Unicode").font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(KeyboardPalette.accent)
            .frame(width: model.showsUnicode ? 42 : 76, height: headerHeight)
            .keyboardControlSurface()
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel(model.showsUnicode ? "English keyboard" : "Browse Unicode")
        .accessibilityValue(model.modeValue)
        .accessibilityIdentifier(model.showsUnicode ? "keyboard.openTyping" : "keyboard.openUnicode")
    }

    @ViewBuilder private var unicodeContent: some View {
        VStack(spacing: 4) {
            if let text = model.symbolBoardInspectionText { boardTextInspection(text) }
            else if let inspected = model.inspection { inspectionPanel(inspected) }
            else if model.isSearching { searchContent }
            else { content }
        }
    }

    private var symbolBar: some View {
        GeometryReader { geometry in
            let board = symbolBoards.typingBoard
            KeyboardTypingFavoriteRow(board: board, route: model.inputModeID,
                keyHeight: model.typingKeyHeight,
                keyWidth: max(1, (geometry.size.width - 9 * (model.isPadLayout ? 7 : 5)) / 10),
                columnSpacing: model.isPadLayout ? 7 : 5, useUnicodeFonts: model.useUnicodeFonts,
                enabled: !model.showsUnicode, actionFactory: boardKeyActions)
        }
    }

    private var typingContent: some View {
        return KeyboardTypingView(typing: model.typing, mode: model.inputModeID,
            isPad: model.isPadLayout, isLandscape: model.isLandscapePadLayout, padLayout: model.padLayout, compact: model.isCompactLayout,
            showsNumberRow: model.showsNumberRow, enabled: !model.showsUnicode, useUnicodeFonts: model.useUnicodeFonts,
            delete: delete, variants: typingVariantActions,
            keySettings: model.keySettings, returnTitle: model.returnTitle, action: action, shiftSlide: shiftSlide)
    }

    private var sectionMenu: some View {
        Menu {
            ForEach(KeyboardSection.allCases, id: \.self) { section in
                Button {
                    model.selectSection(section)
                } label: {
                    Label(section.title, systemImage: model.section == section ? "checkmark" : section.icon)
                }
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
                .accessibilityIdentifier("keyboard.tab.\(section.rawValue.lowercased())")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.section.icon).font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(KeyboardPalette.accent)
            .frame(width: 36, height: headerHeight)
            .keyboardControlSurface()
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel("Keyboard section")
        .accessibilityValue(model.section.rawValue.lowercased())
        .accessibilityIdentifier("keyboard.section")
    }

    @ViewBuilder private var content: some View {
        if model.isSearching || model.hasSearchQuery { searchResults }
        else {
            switch model.section {
            case .symbols:
                if model.discoveryLoading { ProgressView("Loading Unicode…").font(.system(size: 12)) }
                else { characterGrid(model.discoveryCharacters, pagination: model.loadSymbolsPage).id("symbols-\(model.editionValue)") }
            case .emojis:
                if model.discoveryLoading { ProgressView("Loading emoji…").font(.system(size: 12)) }
                else { emojiGrid(model.discoveryEmojis, pagination: model.loadEmojisPage).id("emojis-\(model.editionValue)") }
            case .blocks: blockContent
            case .saved: savedContent
            }
        }
    }

    /// The local query keyboard uses the same key height as ordinary typing.
    /// Search gets its own row budget; results never squeeze the input keys.
    private var searchContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
            let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
            if KeyboardLayoutPolicy.searchUsesSideResults(availableWidth: width, isPad: model.isPadLayout, isCompact: model.isCompactLayout) {
                let available = max(2, width - 12)
                let resultsWidth = available * 0.35
                HStack(spacing: 12) {
                    searchResults
                        .frame(width: resultsWidth, height: height)
                    queryKeys(rowHeight: model.typingKeyHeight)
                        .frame(width: available - resultsWidth, height: height)
                }
                .frame(width: width, height: height)
            } else {
                let queryHeight = model.typingKeyHeight * 4 + 12
                VStack(spacing: 4) {
                    searchResultStrip
                        .frame(width: width, height: max(0, height - queryHeight - 4))
                    queryKeys(rowHeight: model.typingKeyHeight)
                        .frame(width: width, height: queryHeight)
                }
                .frame(width: width, height: height)
            }
        }
        .clipped()
    }

    @ViewBuilder private var searchResultStrip: some View {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(model.section == .emojis ? "Search emoji names or sequences" : "Search names, blocks or U+code points")
                .font(.system(size: 12)).foregroundStyle(KeyboardPalette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.searchInProgress {
            ProgressView("Searching…").font(.system(size: 12))
        } else if model.section == .emojis ? model.emojiResults.isEmpty : model.results.isEmpty {
            Text("No results. Try a shorter name or code point.")
                .font(.system(size: 12)).foregroundStyle(KeyboardPalette.secondary)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(model.section == .emojis ? model.emojiResults.map(KeyboardItem.emoji) : model.results.map(KeyboardItem.character), id: \.keyIdentifier) { item in
                        InspectableCharacterKey(item: item, favorite: isFavorite(item), compact: true,
                            useUnicodeFonts: model.useUnicodeFonts, route: model.inputModeID, enabled: model.isSearching,
                            actionFactory: { [mode = model.inputModeID] in keyActions(mode, item) })
                            .frame(width: 58, height: model.typingKeyHeight)
                    }
                }
            }
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
        }
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
                else { characterGrid(model.blockCharacters, pagination: model.loadBlockPage).id("block-\(block.id)-\(model.editionValue)") }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.catalog.blocks) { block in
                        Button { model.openBlock(block) } label: {
                            let symbol = model.catalog.representative(of: block)
                            HStack(spacing: 10) {
                                Text(symbol).font(Font(UnicodeFontSupport.font(for: symbol, size: 21, enabled: model.useUnicodeFonts))).foregroundStyle(KeyboardPalette.accent).frame(width: 31)
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

    private var selectedSymbolPage: SymbolPageID {
        model.showFavorites ? .board(symbolBoards.activeBoardID) : .recent
    }
    private var symbolPages: [KeyboardSymbolPage] {
        symbolBoards.boards.map { .init(id: .board($0.id), title: $0.name) } + [.init(id: .recent, title: "Recent")]
    }
    @ViewBuilder private func symbolPageContent(_ page: SymbolPageID) -> some View {
        switch page {
        case .board(let id):
            if let board = symbolBoards.boards.first(where: { $0.id == id }) { savedBoardPage(board) }
        case .recent: savedRecentKeys(legacy: false)
        }
    }
    private var savedContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(symbolBoards.boards) { board in
                                savedTab(board.name, icon: board.id == SymbolBoardStore.favoritesID ? "star" : "square.grid.2x2",
                                         selected: selectedSymbolPage == .board(board.id)) {
                                    _ = model.selectSymbolPage(.board(board.id))
                                }
                                .id(SymbolPageID.board(board.id))
                                .accessibilityIdentifier("keyboard.pages.tab.\(board.id)")
                            }
                            savedTab("Recent", icon: "clock", selected: selectedSymbolPage == .recent) {
                                _ = model.selectSymbolPage(.recent)
                            }
                            .id(SymbolPageID.recent)
                            .accessibilityIdentifier("keyboard.pages.tab.recent")
                        }
                    }
                    .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
                    .onChange(of: selectedSymbolPage) { _, page in proxy.scrollTo(page, anchor: .center) }
                    .onAppear { proxy.scrollTo(selectedSymbolPage, anchor: .center) }
                }
                Button { model.openSymbolBoardManager() } label: {
                    Image(systemName: "list.bullet").frame(width: 30, height: 28)
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityLabel("All pages").accessibilityIdentifier("keyboard.boards.open")
            }
            if let issue = symbolBoards.loadIssue {
                Text(issue.rawValue).font(.system(size: 11)).foregroundStyle(KeyboardPalette.secondary)
                    .accessibilityIdentifier("keyboard.boards.storageIssue")
            }
            KeyboardSymbolPagesPager(pages: symbolPages, selection: selectedSymbolPage,
                route: model.inputModeID, isActive: model.isShowingSymbolPages && !model.hasSymbolBoardOverlay,
                content: { AnyView(symbolPageContent($0).tint(KeyboardPalette.accent)
                    .environment(\.layoutDirection, .leftToRight).dynamicTypeSize(.xSmall ... .xxxLarge)) },
                actionFactory: { [mode = model.inputModeID] in
                    guard let current = boardConfigurationGuard(mode), current() else { return nil }
                    return { page in current() && model.selectSymbolPage(page) }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
    @ViewBuilder private func savedBoardPage(_ board: SymbolBoard) -> some View {
        if symbolBoards.hasLegacyFallback && board.id == SymbolBoardStore.favoritesID {
            savedRecentKeys(legacy: true)
        } else if board.keys.isEmpty {
            emptyState(icon: board.id == SymbolBoardStore.favoritesID ? "star" : "square.grid.2x2",
                       title: "This page is empty", detail: "Hold a Unicode key and choose Save to add it to a page.")
        } else {
            ScrollView {
                LazyVGrid(columns: savedBoardColumns, spacing: 4) {
                    ForEach(board.keys) { key in
                        KeyboardVariantKey(text: key.text, variants: key.variants,
                            identifier: "keyboard.board.\(board.id).key.\(key.id)",
                            label: symbolBoardKeyLabel(key.text), route: model.inputModeID,
                            enabled: model.isShowingSymbolPages && model.showFavorites && symbolBoards.activeBoardID == board.id,
                            fontSize: 23, useUnicodeFonts: model.useUnicodeFonts, showsInspection: true, showsEditing: true,
                            factory: { [mode = model.inputModeID, boardID = board.id] in boardKeyActions(mode, boardID, key) })
                            .frame(height: savedKeyHeight)
                            .keyboardKeySurface(radius: 7)
                            .accessibilityHidden(!model.isShowingSymbolPages || !model.showFavorites || symbolBoards.activeBoardID != board.id)
                    }
                }.padding(.bottom, 2)
            }
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
            .accessibilityIdentifier("keyboard.boards.keys")
        }
    }
    private var savedKeyHeight: CGFloat { model.typingKeyHeight }
    private var savedBoardColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: model.isPadLayout ? 7 : 5), count: 10)
    }
    private func savedRecentKeys(legacy: Bool) -> some View {
        let characters = model.sorted(legacy ? store.favoriteCharacters(in: model.catalog) : store.recentCharacters(in: model.catalog))
        let emojis = model.sorted(legacy ? store.favoriteEmojiEntries(in: model.emojiCatalog) : store.recentEmojiEntries(in: model.emojiCatalog))
        return ScrollView {
            LazyVGrid(columns: savedBoardColumns, spacing: 4) {
                ForEach(characters) { character in
                    InspectableCharacterKey(item: .character(character), favorite: false, compact: true,
                        useUnicodeFonts: model.useUnicodeFonts, route: model.inputModeID,
                        enabled: model.isShowingSymbolPages && (legacy ? model.showFavorites && symbolBoards.activeBoardID == SymbolBoardStore.favoritesID : !model.showFavorites), glyphOnly: true,
                        actionFactory: { [mode = model.inputModeID] in keyActions(mode, .character(character)) })
                        .frame(maxWidth: .infinity).frame(height: savedKeyHeight)
                        .keyboardKeySurface(radius: 7)
                        .accessibilityHidden(!model.isShowingSymbolPages || (legacy ? !model.showFavorites || symbolBoards.activeBoardID != SymbolBoardStore.favoritesID : model.showFavorites))
                }
                ForEach(emojis) { emoji in
                    InspectableCharacterKey(item: .emoji(emoji), favorite: false, compact: true,
                        useUnicodeFonts: model.useUnicodeFonts, route: model.inputModeID,
                        enabled: model.isShowingSymbolPages && (legacy ? model.showFavorites && symbolBoards.activeBoardID == SymbolBoardStore.favoritesID : !model.showFavorites), glyphOnly: true,
                        actionFactory: { [mode = model.inputModeID] in keyActions(mode, .emoji(emoji)) })
                        .frame(maxWidth: .infinity).frame(height: savedKeyHeight)
                        .keyboardKeySurface(radius: 7)
                        .accessibilityHidden(!model.isShowingSymbolPages || (legacy ? !model.showFavorites || symbolBoards.activeBoardID != SymbolBoardStore.favoritesID : model.showFavorites))
                }
            }
        }.scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
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
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
    }
    private func emojiGrid(_ emojis: [UnicodeEmojiEntry], pagination: (() -> Void)? = nil) -> some View {
        ScrollView { emojiTiles(emojis, pagination: pagination).padding(.bottom, 2) }
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
    }
    private func characterTiles(_ characters: [UnicodeCharacter], pagination: (() -> Void)? = nil) -> some View {
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(characters) { character in
                InspectableCharacterKey(item: .character(character), favorite: store.isFavorite(character.codePoint), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, route: model.inputModeID, enabled: model.showsUnicode,
                    actionFactory: { [mode = model.inputModeID] in keyActions(mode, .character(character)) })
                    .frame(height: keyHeight)
                    .onAppear { if character.id == characters.last?.id { pagination?() } }
            }
        }
    }
    private func emojiTiles(_ emojis: [UnicodeEmojiEntry], pagination: (() -> Void)? = nil) -> some View {
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(emojis) { emoji in
                InspectableCharacterKey(item: .emoji(emoji), favorite: store.isFavoriteEmoji(emoji.id), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, route: model.inputModeID, enabled: model.showsUnicode,
                    actionFactory: { [mode = model.inputModeID] in keyActions(mode, .emoji(emoji)) })
                    .frame(height: keyHeight)
                    .onAppear { if emoji.id == emojis.last?.id { pagination?() } }
            }
        }
    }

    private func isFavorite(_ item: KeyboardItem) -> Bool {
        symbolBoards.isFavorite(originalText(item))
    }
    private func originalText(_ item: KeyboardItem) -> String {
        switch item {
        case .character(let character): return character.text
        case .emoji(let emoji): return emoji.text
        }
    }
    @ViewBuilder private func boardTextInspection(_ text: String) -> some View {
        if text.unicodeScalars.count == 1, let point = text.unicodeScalars.first?.value,
           let character = model.catalog.character(at: point) { inspectionPanel(.character(character)) }
        else if let emoji = model.emojiCatalog.entries.first(where: { SymbolBoardKey.exact($0.text, text) }) { inspectionPanel(.emoji(emoji)) }
        else {
            VStack(spacing: 6) {
                inspectionHeader(title: "Unicode sequence", text: text, saved: symbolBoards.isFavorite(text))
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(symbolBoardPreview(text)).font(.system(size: 32)).frame(maxWidth: .infinity)
                        property("Code points", value: text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "), identifier: "codepoints", monospaced: true)
                        property("UTF-8", value: utf8(text), identifier: "utf8", monospaced: true)
                        ForEach(Array(text.unicodeScalars.enumerated()), id: \.offset) { index, scalar in
                            Text("\(index + 1). \(String(format: "U+%04X", scalar.value)) · \(model.catalog.character(at: scalar.value)?.name ?? "Unicode scalar")")
                                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(10)
                }
            }
        }
    }

    private func inspectionPanel(_ item: KeyboardItem) -> some View {
        VStack(spacing: 8) {
            inspectionHeader(title: "Unicode properties", text: originalText(item), saved: isFavorite(item))
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

    private func inspectionHeader(title: String, text: String, saved: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                if model.symbolBoardInspectionText != nil { model.closeSymbolBoardInspection() }
                else { model.closeInspection() }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 68, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(KeyboardPressStyle())
            .accessibilityLabel("Close Unicode properties")
            .accessibilityIdentifier("keyboard.properties.close")
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("keyboard.properties")
            KeyboardTouchKey(title: saved ? "Saved" : "Save", symbol: saved ? "star.fill" : "star",
                identifier: "keyboard.properties.favorite", label: saved ? "Remove from Favorites" : "Save to Favorites",
                value: saved ? "saved" : "not saved", fontSize: 13, tinted: true,
                route: model.inputModeID, factory: { [mode = model.inputModeID] in
                    guard let current = boardConfigurationGuard(mode) else { return { false } }
                    return {
                        guard current(), symbolBoards.canEdit, !model.hasSymbolBoardOverlay else { return false }
                        return model.toggleFavorite(text)
                    }
                })
                .frame(width: 76, height: 44).keyboardKeySurface(radius: 9)
                .disabled(!symbolBoards.canEdit)
        }
        .frame(height: 44)
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
                    Text(character?.name ?? "Unicode scalar").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
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
        case .emoji(let emoji):
            return Font(UnicodeFontSupport.font(for: emoji.text, size: size, enabled: model.useUnicodeFonts))
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
            searchKeyRow(["+", "z", "x", "c", "v", "b", "n", "m", ":", "-"], rowHeight: rowHeight, includeDelete: true)
        }
    }
    private func searchKeyRow(_ keys: [String], rowHeight: CGFloat, inset: CGFloat = 0, includeDelete: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                KeyboardTouchKey(title: key, identifier: "keyboard.query.\(key)",
                    label: key == "+" ? "Plus" : key == ":" ? "Colon" : key == "-" ? "Hyphen" : key,
                    fontSize: 22,
                    route: model.inputModeID,
                    factory: { [mode = model.inputModeID] in action(mode, .query(key)) })
                    .frame(maxWidth: .infinity).frame(height: rowHeight)
                    .keyboardKeySurface(radius: 7)
            }
            if includeDelete {
                RepeatingDeleteKey(action: delete, isQuery: true, route: model.inputModeID, identifier: "keyboard.query.delete")
                    .frame(maxWidth: .infinity).frame(height: rowHeight)
                    .keyboardKeySurface(radius: 7)
            }
        }
        .padding(.horizontal, inset)
    }

    private var usesPadFooter: Bool { usesPadKeyPositions }
    private var usesPadKeyPositions: Bool { model.isPadLayout && !model.showsUnicode && model.typingKeyHeight >= 44 }
    private var displaysCollapseKey: Bool { model.showsCollapseKey || usesPadFooter }

    private var controls: some View {
        GeometryReader { geometry in
            if let plan = KeyboardFooterLayoutPolicy.plan(availableWidth: geometry.size.width,
                hasGlobe: model.needsInputModeSwitchKey, showsCollapse: displaysCollapseKey,
                showsPage: !model.showsUnicode || model.isShowingSymbolPages, isPad: model.isPadLayout,
                showsReturn: !usesPadFooter && (model.showsUnicode || KeyboardTypingLayoutPolicy.padPlan(availableWidth: geometry.size.width,
                    isPad: model.isPadLayout, layout: model.typingState.layout, isLandscape: model.isLandscapePadLayout, padLayout: model.padLayout,
                    alphabet: model.typingState.alphabet) == nil),
                padTyping: usesPadFooter) {
                footerControls(plan)
            }
        }
        .frame(height: controlHeight)
    }

    private func footerControls(_ plan: KeyboardFooterLayoutPolicy.Plan) -> some View {
        HStack(spacing: plan.spacing) {
            KeyboardTouchKey(title: "U", identifier: "keyboard.toggleUnicodeToolbar",
                label: model.showsUnicodeToolbar ? "Hide Unicode toolbar" : "Show Unicode toolbar",
                value: model.showsUnicodeToolbar ? "on" : "off", fontSize: 18, tinted: true,
                contentPosition: usesPadKeyPositions ? .bottomLeft : .center,
                route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .toolbar) })
                .frame(width: plan.keyWidth, height: controlHeight)
                .background(KeyboardPalette.accent.opacity(model.showsUnicodeToolbar ? 0.08 : 0.03),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .keyboardKeySurface()
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(model.showsUnicodeToolbar ? KeyboardPalette.accent.opacity(0.65) : Color.clear, lineWidth: 1)
                    .allowsHitTesting(false))
            if model.needsInputModeSwitchKey {
                InputModeSwitchKey(controller: controller, isModifier: model.isPadLayout && !model.showsUnicode,
                    contentPosition: usesPadKeyPositions ? .bottomLeft : .center)
                    .frame(width: plan.keyWidth, height: controlHeight)
            }
            if displaysCollapseKey && !usesPadFooter { footerCollapseKey(plan) }
            if !model.showsUnicode && !usesPadFooter { footerPageKey(plan) }
            if model.isShowingSymbolPages {
                RepeatingDeleteKey(action: delete, isQuery: false, route: model.inputModeID, identifier: "keyboard.pages.delete")
                    .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface()
            }
            KeyboardVariantKey(text: "★", variants: [], identifier: "keyboard.openFavorites",
                label: model.isShowingSymbolPages ? "Back to English keyboard" : "Symbol keyboard",
                value: model.isShowingSymbolPages ? "favorites" : model.modeValue,
                symbol: model.isShowingSymbolPages ? "arrow.left" : "star", route: model.inputModeID,
                enabled: true, fontSize: 20,
                contentPosition: usesPadKeyPositions ? .bottomLeft : .center, holdLabel: "Manage pages",
                factory: { [mode = model.inputModeID] in favoritesActions(mode) })
                .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: model.isPadLayout && !model.showsUnicode)
            if model.layouts.count > 1 && !model.isSearching {
                let alphabet = model.typingState.alphabet
                KeyboardVariantKey(text: alphabet.id, variants: [], identifier: "keyboard.space", label: "Insert space",
                    value: alphabet.nativeName, route: model.inputModeID, fontSize: 14, foreground: .secondaryLabel,
                    hint: "Tap to insert a space. Hold, slide to a layout, then lift your finger to switch.",
                    longPressOptions: KeyboardModel.layoutChoices(current: alphabet, layouts: model.layouts),
                    displayText: { KeyboardAlphabet.alphabet(id: $0)?.nativeName ?? $0 },
                    actionName: { "Switch to \(KeyboardAlphabet.alphabet(id: $0)?.nativeName ?? $0)" },
                    factory: { [mode = model.inputModeID] in layoutActions(mode) })
                    .frame(width: plan.spaceWidth, height: controlHeight).keyboardKeySurface()
            } else {
                KeyboardTouchKey(title: model.isSearching ? "Search space" : "space", identifier: "keyboard.space",
                    label: model.isSearching ? "Add space to search" : "Insert space", fontSize: 14, secondary: true,
                    route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .space) })
                    .frame(width: plan.spaceWidth, height: controlHeight).keyboardKeySurface()
            }
            if usesPadFooter {
                footerPageKey(plan)
                footerCollapseKey(plan)
            }
            if plan.returnWidth > 0 {
                let inspecting = model.inspection != nil || model.symbolBoardInspectionText != nil
                KeyboardTouchKey(title: model.isSearching ? "Done" : inspecting ? "Back" : model.returnTitle,
                    identifier: "keyboard.return", label: model.isSearching ? "Close search keys" : inspecting ? "Close Unicode properties" : "\(model.returnTitle) key",
                    fontSize: 14, isAction: true, contentPosition: usesPadKeyPositions ? .bottomRight : .center, route: model.inputModeID,
                    factory: { [mode = model.inputModeID] in action(mode, .returnKey) })
                    .frame(width: plan.returnWidth, height: controlHeight)
                    .background(KeyboardPalette.action, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
    private func footerCollapseKey(_ plan: KeyboardFooterLayoutPolicy.Plan) -> some View {
        KeyboardTouchKey(title: nil, symbol: "keyboard.chevron.compact.down",
            identifier: "keyboard.collapse", label: "Dismiss keyboard", fontSize: 17,
            contentPosition: usesPadKeyPositions ? .bottomRight : .center,
            route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .collapse) })
            .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: model.isPadLayout && !model.showsUnicode)
    }
    private func footerPageKey(_ plan: KeyboardFooterLayoutPolicy.Plan) -> some View {
        let letters = model.typingState.layout != .letters
        // The number page swaps its digits for symbols only while the number row shows them.
        let symbols = model.showsNumberRow
        return KeyboardTouchKey(title: letters ? "ABC" : symbols ? "#+=" : "123",
            identifier: letters ? "keyboard.typing.letters" : "keyboard.typing.numbers",
            label: letters ? "Letters" : symbols ? "Symbols" : "Numbers", value: model.typingLayoutValue, fontSize: 13,
            contentPosition: usesPadKeyPositions ? .bottomRight : .center,
            route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .layout(letters ? .letters : .numbers)) })
            .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: model.isPadLayout && !model.showsUnicode)
    }

}

/// Only this small subtree observes transient Shift/capitalization changes.
/// The mounted Unicode browser is not rebuilt for each English character.
private struct KeyboardTypingView: View {
    @ObservedObject var typing: KeyboardTypingModel
    let mode: UUID
    let isPad: Bool
    let isLandscape: Bool
    let padLayout: KeyboardPadLayout
    let compact: Bool
    let showsNumberRow: Bool
    let enabled: Bool
    let useUnicodeFonts: Bool
    let delete: (UUID, Bool) -> RepeatingDeleteButton.DeleteAction
    let variants: (UUID, String, Bool, Bool, Bool, Bool) -> KeyboardVariantActions?
    let keySettings: KeyboardKeySettings.Snapshot
    let returnTitle: String
    let action: (UUID, KeyboardInputCommand) -> () -> Bool
    let shiftSlide: (UUID) -> ((String) -> Bool)?
    private var layoutValue: String {
        switch typing.state.layout { case .letters: return "letters"; case .numbers: return "numbers"; case .symbols: return "symbols" }
    }
    private var shiftValue: String {
        switch typing.state.shift { case .lowercase: return "lowercase"; case .uppercase: return "uppercase"; case .capsLock: return "capsLock" }
    }
    var body: some View {
        GeometryReader { geometry in
            if let plan = KeyboardTypingLayoutPolicy.plan(availableHeight: geometry.size.height,
                availableWidth: geometry.size.width, compact: compact, layout: typing.state.layout,
                isPad: isPad, isLandscape: isLandscape, padLayout: padLayout, showsNumberRow: showsNumberRow) {
                let ansiStyle = KeyboardTypingLayoutPolicy.usesANSI(availableWidth: geometry.size.width, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout)
                let pad = KeyboardTypingLayoutPolicy.padPlan(availableWidth: geometry.size.width, isPad: isPad, layout: typing.state.layout, isLandscape: isLandscape, padLayout: padLayout,
                    alphabet: typing.state.alphabet)
                VStack(spacing: plan.rowSpacing) {
                    if plan.numberRowCount > 0 { numberRow(height: plan.keyHeight, ansiPad: ansiStyle) }
                    if let pad {
                        if pad.isANSI { ansiRows(pad, height: plan.keyHeight, hasAuxiliaryRow: plan.numberRowCount > 0) }
                        else { padRows(pad, height: plan.keyHeight, hasAuxiliaryRow: plan.numberRowCount > 0) }
                    } else {
                        ForEach(Array(KeyboardTypingLayoutPolicy.rows(for: typing.state.layout, hasAuxiliaryRow: plan.numberRowCount > 0, ansiPad: ansiStyle, padLayout: padLayout,
                                alphabet: typing.state.alphabet).enumerated()), id: \.offset) { index, keys in
                            HStack(spacing: isPad ? 7 : 5) {
                                if index == 2 { typingLeadingKey(height: plan.keyHeight) }
                                ForEach(keys, id: \.self) { key in
                                    typingCharacterKey(key, hasAuxiliaryRow: plan.numberRowCount > 0,
                                        isAuxiliaryKey: false, ansiPad: ansiStyle, identifier: "keyboard.typing.key.\(key)", fontSize: compact ? 20 : 23)
                                        .frame(maxWidth: .infinity).frame(height: plan.keyHeight)
                                        .keyboardKeySurface(radius: 7)
                                }
                                if index == 2 {
                                    RepeatingDeleteKey(action: delete, isQuery: false, route: mode, identifier: "keyboard.typing.delete", padStyle: isPad)
                                        .frame(width: isPad ? 64 : 42, height: plan.keyHeight)
                                        .keyboardKeySurface(radius: 7, modifier: isPad)
                                    if isPad && geometry.size.width >= 650 { padReturn(width: 112, height: plan.keyHeight) }
                                }
                            }
                            .padding(.horizontal, index == 1 && typing.state.layout == .letters ? (isPad ? 24 : 12) : 0)
                        }
                    }
                }
                .frame(height: plan.contentHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .preference(key: KeyboardTypingAuxiliaryRowVisible.self, value: plan.numberRowCount > 0)
                .preference(key: KeyboardTypingWidePadVisible.self, value: pad != nil)
                .preference(key: KeyboardTypingANSIPadVisible.self, value: ansiStyle)
            }
        }
    }

    private func padRows(_ pad: KeyboardPadTypingLayoutPlan, height: CGFloat, hasAuxiliaryRow: Bool) -> some View {
        ForEach(Array(KeyboardTypingLayoutPolicy.rows(for: .letters, hasAuxiliaryRow: false, widePad: true,
                                                              alphabet: typing.state.alphabet).enumerated()), id: \.offset) { row, keys in
            HStack(spacing: pad.keySpacing) {
                if row == 0 {
                    KeyboardTouchKey(title: "tab", identifier: "keyboard.typing.tab", label: "Tab", fontSize: 13, contentPosition: .bottomLeft,
                        route: mode, factory: { [mode = mode] in action(mode, .tab) })
                        .frame(width: pad.characterWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                } else if row == 1 {
                    KeyboardTouchKey(title: "caps lock", identifier: "keyboard.typing.capsLock", label: "Caps Lock",
                        value: typing.state.shift == .capsLock ? "on" : "off", fontSize: 12, contentPosition: .bottomLeft,
                        route: mode, factory: { [mode = mode] in action(mode, .capsLock) })
                        .frame(width: pad.capsWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(typing.state.shift == .capsLock ? KeyboardPalette.accent : Color.clear, lineWidth: 1))
                } else {
                    padShift(width: pad.shiftWidth, height: height, right: false)
                }
                ForEach(keys, id: \.self) { key in
                    typingCharacterKey(key, hasAuxiliaryRow: hasAuxiliaryRow, isAuxiliaryKey: false, widePad: true,
                        identifier: "keyboard.typing.key.\(key)", fontSize: 23)
                        .frame(width: pad.characterWidth, height: height).keyboardKeySurface(radius: 7)
                }
                if row == 0 {
                    RepeatingDeleteKey(action: delete, isQuery: false, route: mode, identifier: "keyboard.typing.delete", padStyle: true)
                        .frame(width: pad.characterWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                } else if row == 1 {
                    padReturn(width: pad.returnWidth, height: height)
                } else {
                    padShift(width: pad.shiftWidth, height: height, right: true)
                }
            }
        }
    }

    private func ansiRows(_ pad: KeyboardPadTypingLayoutPlan, height: CGFloat, hasAuxiliaryRow: Bool) -> some View {
        let rows = pad.hasNumberRow ? KeyboardTypingLayoutPolicy.ansiRows : KeyboardTypingLayoutPolicy.compactANSIRows
        let offset = pad.hasNumberRow ? 1 : 0
        return ForEach(Array(rows.enumerated()), id: \.offset) { row, keys in
            HStack(spacing: pad.keySpacing) {
                if row == offset {
                    KeyboardTouchKey(title: "tab", identifier: "keyboard.typing.tab", label: "Tab", fontSize: 13, contentPosition: .bottomLeft,
                        route: mode, factory: { [mode = mode] in action(mode, .tab) })
                        .frame(width: pad.tabWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                } else if row == offset + 1 {
                    KeyboardTouchKey(title: "caps lock", identifier: "keyboard.typing.capsLock", label: "Caps Lock",
                        value: typing.state.shift == .capsLock ? "on" : "off", fontSize: 12, contentPosition: .bottomLeft,
                        route: mode, factory: { [mode = mode] in action(mode, .capsLock) })
                        .frame(width: pad.capsWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                } else if row == offset + 2 { padShift(width: pad.shiftWidth, height: height, right: false) }
                ForEach(keys, id: \.self) { key in
                    typingCharacterKey(key, hasAuxiliaryRow: hasAuxiliaryRow, isAuxiliaryKey: false, widePad: true, ansiPad: true,
                        identifier: "keyboard.typing.key.\(key)", fontSize: 23)
                        .frame(width: pad.hasNumberRow && row == 1 && key == "\\" ? pad.backslashWidth : pad.characterWidth, height: height)
                        .keyboardKeySurface(radius: 7)
                }
                if row == 0 {
                    RepeatingDeleteKey(action: delete, isQuery: false, route: mode, identifier: "keyboard.typing.delete", padStyle: true)
                        .frame(width: pad.deleteWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                } else if row == offset + 1 {
                    padReturn(width: pad.returnWidth, height: height)
                } else if row == offset + 2 { padShift(width: pad.rightShiftWidth, height: height, right: true) }
            }
        }
    }

    private func padReturn(width: CGFloat, height: CGFloat) -> some View {
        KeyboardTouchKey(title: returnTitle, identifier: "keyboard.return", label: "\(returnTitle) key", fontSize: 14,
            isAction: true, contentPosition: .bottomRight, route: mode, factory: { [mode = mode] in action(mode, .returnKey) })
            .frame(width: width, height: height)
            .background(KeyboardPalette.action, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func padShift(width: CGFloat, height: CGFloat, right: Bool) -> some View {
        KeyboardTouchKey(title: "shift",
            identifier: right ? "keyboard.typing.shift.right" : "keyboard.typing.shift", label: "Shift", value: shiftValue,
            fontSize: 13, contentPosition: right ? .bottomRight : .bottomLeft,
            route: mode, shiftSlideFactory: { [mode = mode] in shiftSlide(mode) },
            factory: { [mode = mode] in action(mode, .shift) })
            .frame(width: width, height: height).keyboardKeySurface(radius: 7, modifier: true)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(typing.state.shift == .lowercase ? Color.clear : KeyboardPalette.accent.opacity(0.65), lineWidth: 1))
    }

    private func numberRow(height: CGFloat, ansiPad: Bool) -> some View {
        HStack(spacing: isPad ? 7 : 5) {
            ForEach(KeyboardTypingLayoutPolicy.auxiliaryRow(for: typing.state.layout, ansiPad: ansiPad), id: \.self) { key in
                typingCharacterKey(key, hasAuxiliaryRow: true, isAuxiliaryKey: true, ansiPad: ansiPad,
                    identifier: KeyboardTypingLayoutPolicy.numberRowOutput(for: key) != nil ? "keyboard.typing.number.\(key)" : "keyboard.typing.auxiliary.\(key)",
                    fontSize: compact ? 18 : 20)
                    .frame(maxWidth: .infinity).frame(height: height)
                    .keyboardKeySurface(radius: 7)
            }
        }
    }

    private func typingCharacterKey(_ key: String, hasAuxiliaryRow: Bool, isAuxiliaryKey: Bool, widePad: Bool = false, ansiPad: Bool = false,
                                    identifier: String, fontSize: CGFloat) -> some View {
        let keyID = KeyboardKeySettings.identifier(forCharacter: key) ?? ""
        let original = isAuxiliaryKey ? key : KeyboardTypingLayoutPolicy.output(for: key, state: typing.state, hasAuxiliaryRow: hasAuxiliaryRow, widePad: widePad, ansiPad: ansiPad, padLayout: padLayout) ?? key
        let text = keySettings.tapOutput(for: keyID, defaultText: original,
            shifted: KeyboardTypingLayoutPolicy.usesShiftedTap(for: key, state: typing.state, ansiPad: ansiPad))
        let gestures = KeyboardVariantPolicy.gestureCandidates(for: key, original: original, state: typing.state, settings: keySettings)
        return KeyboardVariantKey(text: text ?? original,
            variants: KeyboardVariantPolicy.englishVariants(for: key, uppercase: typing.state.shift != .lowercase),
            identifier: identifier, value: layoutValue, route: mode, enabled: enabled, fontSize: fontSize,
            foreground: text == nil ? .secondaryLabel : .label,
            hint: text == nil ? "Tap is off. Hold or swipe for configured choices." : nil,
            useUnicodeFonts: useUnicodeFonts,
            preservesPressAcrossTextChanges: true,
            longPressOptions: gestures.longPress, swipeUp: gestures.swipeUp, swipeDown: gestures.swipeDown,
            factory: { [mode = mode] in variants(mode, key, hasAuxiliaryRow, isAuxiliaryKey, widePad, ansiPad) })
    }

    @ViewBuilder private func typingLeadingKey(height: CGFloat) -> some View {
        if typing.state.layout == .letters {
            KeyboardTouchKey(title: nil,
                symbol: typing.state.shift == .capsLock ? "capslock.fill" : typing.state.shift == .uppercase ? "shift.fill" : "shift",
                identifier: "keyboard.typing.shift", label: "Shift", value: shiftValue,
                route: mode, shiftSlideFactory: { [mode = mode] in shiftSlide(mode) },
            factory: { [mode = mode] in action(mode, .shift) })
                .frame(width: isPad ? 64 : 42, height: height)
                .keyboardKeySurface(radius: 7, modifier: isPad)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(typing.state.shift == .lowercase ? Color.clear : KeyboardPalette.accent.opacity(0.65), lineWidth: 1))
        } else {
            let symbols = typing.state.layout == .numbers
            KeyboardTouchKey(title: symbols ? "#+=" : isLandscape && padLayout == .ansiNumbers ? "=<>" : isPad ? ".?123" : "123",
                identifier: symbols ? "keyboard.typing.symbols" : "keyboard.typing.numbers",
                label: symbols ? "More symbols" : "Numbers", value: layoutValue, fontSize: 13,
                contentPosition: isPad && height >= 44 ? .bottomLeft : .center,
                route: mode, factory: { [mode = mode] in action(mode, .layout(symbols ? .symbols : .numbers)) })
                .frame(width: isPad ? 64 : 42, height: height)
                .keyboardKeySurface(radius: 7, modifier: isPad)
        }
    }

}

/// Shift only redraws letter labels. The saved previews keep their native
/// controls, scroll position and resolved preview fonts while their inputs match.
private struct KeyboardTypingFavoriteRow: View, Equatable {
    let board: SymbolBoard
    let route: UUID
    let keyHeight: CGFloat
    let keyWidth: CGFloat
    let columnSpacing: CGFloat
    let useUnicodeFonts: Bool
    let enabled: Bool
    let actionFactory: (UUID, String, SymbolBoardKey) -> KeyboardVariantActions?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.route == rhs.route && lhs.keyHeight == rhs.keyHeight
            && lhs.keyWidth == rhs.keyWidth && lhs.columnSpacing == rhs.columnSpacing
            && lhs.useUnicodeFonts == rhs.useUnicodeFonts && lhs.enabled == rhs.enabled
            && lhs.board == rhs.board
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: columnSpacing) {
                ForEach(board.keys) { key in
                    KeyboardVariantKey(text: key.text, variants: key.variants,
                        identifier: "keyboard.typing.favorite.\(board.id).\(key.id)",
                        label: symbolBoardKeyLabel(key.text), route: route, enabled: enabled,
                        fontSize: 23, useUnicodeFonts: useUnicodeFonts, showsInspection: true, showsEditing: true,
                        factory: { [route = route] in actionFactory(route, board.id, key) })
                        .frame(width: keyWidth, height: keyHeight)
                        .keyboardKeySurface(radius: 7)
                }
            }
        }
        .scrollIndicators(.hidden)
        .keyboardUnmaskedScrollEdges()
        .frame(height: keyHeight)
        .accessibilityIdentifier("keyboard.typing.favorites")
    }
}

/// Single host actions bind their route when the finger goes down. SwiftUI
/// can update labels while a finger is held; that must not retarget the press.
private struct KeyboardTouchKey: UIViewRepresentable {
    let title: String?
    var symbol: String? = nil
    let identifier: String
    var label: String? = nil
    var value: String? = nil
    var fontSize: CGFloat = 20
    var secondary = false
    var tinted = false
    var isAction = false
    var contentPosition: KeyboardKeyContentPosition = .center
    let route: UUID
    var shiftSlideFactory: (() -> ((String) -> Bool)?)? = nil
    let factory: () -> (() -> Bool)

    func makeUIView(context: Context) -> KeyboardTouchActionButton {
        shiftSlideFactory == nil ? KeyboardTouchActionButton() : KeyboardShiftTouchButton()
    }
    func updateUIView(_ view: KeyboardTouchActionButton, context: Context) {
        view.configure(contextIdentifier: route, actionFactory: factory)
        if let shift = view as? KeyboardShiftTouchButton, let shiftSlideFactory {
            shift.configureSlide(context: route, factory: shiftSlideFactory)
        }
        view.setTitle(title, for: .normal)
        view.setImage(symbol.flatMap { UIImage(systemName: $0) }, for: .normal)
        view.contentPosition = contentPosition
        view.titleLabel?.font = .systemFont(ofSize: fontSize, weight: isAction && contentPosition == .center ? .semibold : .regular)
        view.titleLabel?.adjustsFontSizeToFitWidth = true
        view.titleLabel?.minimumScaleFactor = 0.7
        let foreground = isAction ? KeyboardPalette.actionTextUI : tinted ? KeyboardPalette.accentUI : secondary ? UIColor.secondaryLabel : UIColor.label
        view.setTitleColor(foreground, for: .normal)
        view.tintColor = foreground
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = label ?? title
        view.accessibilityValue = value
    }
}



/// UIKit owns touch arbitration: a recognized long press cancels the button tap,
/// and sustained pointer hover only opens properties. No inspection inserts text.
private struct InspectableCharacterKey: UIViewRepresentable {
    let item: KeyboardItem
    let favorite: Bool
    let compact: Bool
    let useUnicodeFonts: Bool
    let route: UUID
    let enabled: Bool
    var glyphOnly = false
    var identifier: String? = nil
    let actionFactory: KeyboardInspectableInteraction.ActionFactory

    func makeUIView(context: Context) -> InspectableKeyButton { InspectableKeyButton() }
    func updateUIView(_ uiView: InspectableKeyButton, context: Context) {
        uiView.configure(item: item, favorite: favorite, compact: compact, useUnicodeFonts: useUnicodeFonts, glyphOnly: glyphOnly,
            route: route, enabled: enabled, actionFactory: actionFactory)
        uiView.accessibilityIdentifier = identifier ?? item.keyIdentifier
    }
}

private final class InspectableKeyButton: UIControl {
    private let glyph = UILabel()
    private let code = UILabel()
    private let star = UIImageView(image: UIImage(systemName: "star.fill"))
    private var glyphHeight: NSLayoutConstraint!
    private var codeHeight: NSLayoutConstraint!
    private var usesExternalKeySurface = false
    private let interaction = KeyboardInspectableInteraction()
    private lazy var pressFeedback = KeyboardTouchFeedback.attach(to: self)
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
        codeHeight = code.heightAnchor.constraint(equalToConstant: 11)
        addSubview(star)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor), glyphHeight,
            codeHeight,
            star.widthAnchor.constraint(equalToConstant: 9),
            star.heightAnchor.constraint(equalToConstant: 9),
            star.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            star.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        ])
        interaction.activityChanged = { [weak self] in self?.isHighlighted = $0 }
        hold.minimumPressDuration = 0.4
        hold.allowableMovement = 10
        hold.cancelsTouchesInView = true
        addGestureRecognizer(hold)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        addTarget(self, action: #selector(touchBegan), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(cancelledTouch), for: .touchCancel)
        addTarget(self, action: #selector(cancelledPress), for: [.touchUpOutside, .touchDragExit])
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (key: InspectableKeyButton, _: UITraitCollection) in
            key.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: key.traitCollection).cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        usesExternalKeySurface ? CGSize(width: UIView.noIntrinsicMetric, height: 36) : CGSize(width: 58, height: 56)
    }
    override var isHighlighted: Bool {
        didSet { pressFeedback.setPressed(isHighlighted) }
    }
    func configure(item: KeyboardItem, favorite: Bool, compact: Bool, useUnicodeFonts: Bool, glyphOnly: Bool,
                   route: UUID, enabled: Bool, actionFactory: @escaping KeyboardInspectableInteraction.ActionFactory) {
        if usesExternalKeySurface != glyphOnly {
            usesExternalKeySurface = glyphOnly
            invalidateIntrinsicContentSize()
        }
        layer.borderWidth = glyphOnly ? 0 : 0.4
        interaction.configure(contextIdentifier: route, itemIdentifier: item.keyIdentifier,
            enabled: enabled, actionFactory: actionFactory)
        isUserInteractionEnabled = enabled
        isAccessibilityElement = enabled
        accessibilityElementsHidden = !enabled
        glyph.text = item.displayText
        glyphHeight.constant = compact ? 26 : 34
        let missing: Bool
        if case .character(let character) = item {
            let size: CGFloat = character.isInvisible ? 17 : compact ? 24 : 32
            glyph.font = UnicodeFontSupport.font(for: character.displayText, size: size, enabled: useUnicodeFonts)
            accessibilityValue = UnicodeFontSupport.sourceName(for: character.displayText, size: size, enabled: useUnicodeFonts).map { "Preview font: \($0)" }
            missing = UnicodeFontSupport.stockFontsMiss(character.displayText)
        } else {
            let size: CGFloat = compact ? 24 : 32
            glyph.font = UnicodeFontSupport.font(for: item.displayText, size: size, enabled: useUnicodeFonts)
            accessibilityValue = UnicodeFontSupport.sourceName(for: item.displayText, size: size, enabled: useUnicodeFonts).map { "Preview font: \($0)" }
            missing = UnicodeFontSupport.stockFontsMiss(item.displayText, emoji: true)
        }
        backgroundColor = glyphOnly ? (missing ? UIColor.systemRed.withAlphaComponent(0.18) : .clear)
            : missing ? KeyboardPalette.missingGlyphUI : KeyboardPalette.keyUI
        code.text = item.footer
        codeHeight.isActive = !glyphOnly
        code.isHidden = glyphOnly
        star.isHidden = glyphOnly || !favorite
        layer.cornerRadius = glyphOnly ? 7 : 9
        accessibilityLabel = "\(item.name), \(item.codePointLabel), \(item.ageLabel)"
        accessibilityHint = "Tap to insert. Hold or keep the pointer here to inspect Unicode properties and description."
        accessibilityIdentifier = item.keyIdentifier
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Inspect Unicode properties") { [weak self] _ in
            self?.interaction.activateInspect() ?? false
        }]
    }
    override func accessibilityActivate() -> Bool { interaction.activateInsert() }
    @objc private func touchBegan() { interaction.beginPress() }
    @objc private func tapped() { isHighlighted = false; _ = interaction.endPress() }
    @objc private func cancelledPress() { interaction.cancelPress(); isHighlighted = false }
    @objc private func cancelledTouch() {
        isHighlighted = false
        interaction.cancelPress(preserveInspection: hold.state == .began || hold.state == .changed)
    }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began: isHighlighted = false; _ = interaction.inspectHeldPress()
        case .ended, .cancelled, .failed: interaction.cancelPress()
        default: break
        }
    }
    @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began: interaction.beginHover()
        case .ended, .cancelled, .failed: interaction.endHover()
        default: break
        }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { isHighlighted = false; interaction.cancelAll() }
        super.willMove(toWindow: newWindow)
    }
}

/// Preserve Apple's standard press-and-hold input-mode menu.
private struct InputModeSwitchKey: UIViewRepresentable {
    weak var controller: KeyboardViewController?
    var isModifier = false
    var contentPosition: KeyboardKeyContentPosition = .center
    func makeUIView(context: Context) -> KeyboardGlobeButton {
        let button = KeyboardGlobeButton(type: .system)
        button.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        button.tintColor = .label
        button.backgroundColor = isModifier ? KeyboardPalette.modifierUI : KeyboardPalette.keyUI
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
    func updateUIView(_ uiView: KeyboardGlobeButton, context: Context) {
        uiView.contentPosition = contentPosition
        uiView.backgroundColor = isModifier ? KeyboardPalette.modifierUI : KeyboardPalette.keyUI
        uiView.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: uiView.traitCollection).cgColor
    }
}

private final class KeyboardGlobeButton: UIButton {
    private lazy var pressFeedback = KeyboardTouchFeedback.attach(to: self)
    override var isHighlighted: Bool { didSet { pressFeedback.setPressed(isHighlighted) } }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { isHighlighted = false }
        super.willMove(toWindow: newWindow)
    }
    var contentPosition: KeyboardKeyContentPosition = .center { didSet { setNeedsLayout() } }
    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        contentPosition.alignedRect(super.imageRect(forContentRect: contentRect), in: contentRect)
    }
}

private struct RepeatingDeleteKey: UIViewRepresentable {
    let action: (UUID, Bool) -> RepeatingDeleteButton.DeleteAction
    let isQuery: Bool
    let route: UUID
    var identifier = "keyboard.delete"
    var enabled = true
    var padStyle = false
    func makeUIView(context: Context) -> RepeatingDeleteButton { RepeatingDeleteButton() }
    func updateUIView(_ uiView: RepeatingDeleteButton, context: Context) {
        // Capture the scope this key currently displays, even before a model
        // transition has reached updateUIView. Each press gets one action.
        uiView.configure(isQuery: isQuery, enabled: enabled, actionFactory: { [route, isQuery] in action(route, isQuery) })
        uiView.contentPosition = padStyle ? .bottomRight : .center
        uiView.setTitle(padStyle ? "delete" : nil, for: .normal)
        uiView.setTitleColor(.label, for: .normal)
        uiView.titleLabel?.font = .systemFont(ofSize: 13)
        uiView.setImage(padStyle ? nil : UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        uiView.accessibilityIdentifier = identifier
    }
}

// Keyboard keycaps must remain fully opaque at every scroll position. iOS 26's
// automatic scroll-edge treatment is useful for content, but masks half a key.
private extension View {
    @ViewBuilder func keyboardUnmaskedScrollEdges() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectHidden() }
        else { self }
    }
}
