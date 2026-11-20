import SwiftUI
import UIKit

/// Query keys edit only the extension's local search. Insertion always sends the
/// original scalar or complete emoji sequence to the host's document proxy.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var language: KeyboardLanguageCoordinator { model.language }
    private var lastAppliedPrimaryLanguage: String?
    private let english = KeyboardEnglishCorrectionCoordinator()
    /// Explicit events revoke capabilities even when exposed host strings match.
    private var englishInteraction = UUID()
    private var englishWriteInProgress = false
    private var manualEnglishExpected: KeyboardCorrectionContext?
    private var manualEnglishResult: KeyboardCorrectionContext?

    /// In-memory, exact host anchor. Neither this nor pending actions is persisted.
    private struct CompositionAnchor: Equatable {
        let document: UUID
        let interaction: UUID
        let before: [UInt8]?
        let after: [UInt8]?
        let selection: [UInt8]?
    }
    private var compositionAnchor: CompositionAnchor?
    /// The stored chosen mode (`LanguageInputLastMode`) this keyboard last
    /// applied, wrote, or found stored when its own write failed. A choice it
    /// couldn't save isn't undone by an older value.
    private var lastSeenRememberedMode: LanguageInputMode?
    /// Writes run off the main thread, in order; no restore while one is pending.
    private let rememberedModeQueue = DispatchQueue(label: "ad.neko.uniboard.keyboard.last-mode", qos: .utility)
    private var pendingRememberedWrites = 0
    /// Any key touch, host edit or delete since viewWillAppear: the person has
    /// started typing, so the remembered mode no longer switches by itself.
    private var typedSinceAppear = false
    /// One VoiceOver announcement of the unreadable-language panel per opening.
    private var announcesUnreadablePanel = false
    private var languageRefreshedSinceAppear = false
    /// Only these audited, non-host-writing transitions may continue without a
    /// verified post-write text anchor. Never put an arbitrary closure here.
    private enum InputModeTransition {
        case target(String)
        case directTyping
    }
    private enum PendingConversionAction {
        case guardedAction(() -> Void)
        case inputMode(InputModeTransition, LanguageCompositionModeTransitionScope)
    }
    private var pendingConversionAction: PendingConversionAction?
    private var pendingConversionAnchor: CompositionAnchor?
    private var queuedPunctuation: String?
    private var completingConversion = false
    private var conversionPostWriteAnchor: CompositionAnchor?

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
    /// The movable cursor in the text preview (design/preview-cursor).
    private let previewCursorDriver = KeyboardPreviewCursorDriver()
    private let keyTouchObserver = KeyboardKeyTouchObserver.make()
    /// Between viewWillAppear and viewWillDisappear: the preview caret may blink.
    private var isKeyboardShown = false
    private var heightShortfallCheck: DispatchWorkItem?
    private weak var previewCursorControl: KeyboardPreviewCursorControl?
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
        // The app posts this after changing Emoji Categories; Darwin
        // notifications arrive on the main thread. Removed in deinit.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let controller = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            MainActor.assumeIsolated { controller.model.refreshEmojiCategories() }
        }, EmojiCategorySetting.changedNotification as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let controller = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor [weak controller] in controller?.model.refreshEmojiCategories() }
        }, EmojiBrowsingSetting.changedNotification as CFString, nil, .deliverImmediately)
        // Payload-free publication notice; reload only our fixed App Group stores.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let controller = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor [weak controller] in
                controller?.model.refreshEditionFromAppSettings()
                controller?.invalidateEnglish()
                controller?.language.refresh()
            }
        }, "ad.neko.uniboard.language-input.changed" as CFString, nil, .deliverImmediately)
        updateBackdrop()
        refreshFullAccess()
        let root = UnicodeKeyboardView(
            model: model, language: language, store: CharacterStore.shared, controller: self,
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
        previewCursorDriver.host = self
        previewCursorDriver.publish = { [weak self] state in
            guard let self, self.model.previewCursor != state else { return }
            self.model.previewCursor = state
        }
        // Key touches, seen without taking part, guard the preview (§5).
        keyTouchObserver.ignores = { view in
            var current = view
            while let candidate = current {
                if candidate is KeyboardPreviewCursorControl { return true }
                current = candidate.superview
            }
            return false
        }
        // Any key press keeps the preview caret solid for a moment (§1a).
        keyTouchObserver.onKeyActivity = { [weak self] in
            self?.typedSinceAppear = true
            self?.previewCursorControl?.noteCaretActivity()
        }
        view.addGestureRecognizer(keyTouchObserver)
        model.presentationChanged = { [weak self] in self?.updateKeyboardHeight() }
        model.queryEdited = { [weak self] in
            self?.invalidateEnglish()
            self?.doubleSpaceState.reset()
            self?.expectedHostEdit = nil
        }
        model.typingActivated = { [weak self] in self?.synchronizeHostTraits() }
        model.alphabetChanged = { [weak self] in
            self?.applyPrimaryLanguage()
            self?.synchronizeHostTraits()
        }
        language.onChange = { [weak self] in
            guard let self else { return }
            // A disabled idle converter must not keep consuming ordinary taps.
            if self.language.mode != .direct, self.language.rawInput.isEmpty,
               !self.language.preferences.isEnabled(self.language.mode) {
                self.language.select(.direct)
            }
            self.invalidateEnglish()
            self.synchronizeEnglishOptions()
            self.model.synchronizeLanguageKeyboard()
            if self.language.mode != .direct { self.model.synchronizeCapitalization(false) }
            self.applyPrimaryLanguage()
            self.updateKeyboardHeight()
            self.announceUnreadablePanelIfNeeded()
        }
        language.validateAnchor = { [weak self] in
            guard let self else { return false }
            return self.compositionAnchor == nil || self.compositionAnchor == self.readCompositionAnchor()
        }
        language.onRefreshed = { [weak self] in self?.languageDidRefresh() }
        applyPrimaryLanguage()
        model.inputModeChanged = { [weak self] in
            guard let self else { return }
            self.invalidateEnglish()
            KeyboardVariantButton.cancelInteractions(in: self.view)
            self.doubleSpaceState.reset()
            self.expectedHostEdit = nil
        }
        // The remote document may not exist during viewDidLoad. Read its
        // optional identity only once UIKit begins presenting this input view.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFullAccess()
        model.refreshEditionFromAppSettings()
        invalidateEnglish()
        announcesUnreadablePanel = true
        languageRefreshedSinceAppear = false
        typedSinceAppear = false
        language.refresh()
        synchronizeEnglishOptions()
        SymbolBoardStore.shared.refreshPages()
        SymbolBoardStore.shared.refreshFavorites(canWrite: hasFullAccess)
        KeyboardTouchFeedback.hapticsAllowed = hasFullAccess
        if hasFullAccess {
            // The app's font picker tags fonts the keyboard can't open (design/font-picker §4).
            // At most once a minute after a successful run; a failed run is retried.
            let throttle = KeyboardFontEvidenceThrottle.shared
            if throttle.begin() {
                DispatchQueue.global(qos: .utility).async {
                    throttle.finish(succeeded: KeyboardFontEvidenceStore.appGroup.recordAndConfirm(.current()))
                }
            }
        }
        synchronizeHostTraits()
        updateKeyboardHeight()
        isKeyboardShown = true
        updatePreviewCaretLiveness()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        UnicodeFontSupport.clearCache()
        // Only lazily rebuilt lookup state; never the active language engine,
        // its lease, a composition, or any catalog the keyboard is showing.
        KeyboardMemoryRelief.releaseRebuildableCaches()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        synchronizeHostTraits()
        #if DEBUG
        cursorProbeHostEvent(.appear) // DEBUG-only cursor probe
        #endif
    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
        updateHeightShortfall()
    }

    /// iOS steps through shorter heights while opening the keyboard, so a
    /// height below the request only counts as the host's limit once it lasts.
    private func updateHeightShortfall() {
        guard let input = view as? KeyboardSelfSizingInputView else { return }
        guard view.bounds.height + 0.5 < input.requestedHeight else {
            heightShortfallCheck?.cancel(); heightShortfallCheck = nil
            if model.hostLimitsHeight { model.hostLimitsHeight = false }
            return
        }
        guard !model.hostLimitsHeight, heightShortfallCheck == nil else { return }
        let check = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.heightShortfallCheck = nil
            guard let input = self.view as? KeyboardSelfSizingInputView,
                  self.view.bounds.height + 0.5 < input.requestedHeight else { return }
            self.model.hostLimitsHeight = true
        }
        heightShortfallCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
    }

    override func viewWillDisappear(_ animated: Bool) {
        // A remote host may hide and reuse this same window without detaching
        // individual keys. Invalidate every captured input/hover action first.
        invalidateComposition()
        deleteInteractionID = UUID()
        model.symbolBoardManagerPresented = false
        // The Arabic Diacritics panel never stays open across launches.
        model.closeDiacritics()
        closePreviewImagePanel()
        closeTextInspection()
        KeyboardVariantButton.cancelInteractions(in: view)
        previewCursorControl?.cancelGestures()
        isKeyboardShown = false
        heightShortfallCheck?.cancel(); heightShortfallCheck = nil
        model.hostLimitsHeight = false
        updatePreviewCaretLiveness()
        previewCursorDriver.reset()
        doubleSpaceState.reset()
        expectedHostEdit = nil
        super.viewWillDisappear(animated)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        #if DEBUG
        cursorProbeHostEvent(.text) // DEBUG-only cursor probe
        #endif
        acknowledgeHostChange()
        synchronizeHostTraits()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        #if DEBUG
        cursorProbeHostEvent(.selection) // DEBUG-only cursor probe
        #endif
        // A selection move can leave the same preceding suffix. Never infer
        // permission for a destructive Space edit from that suffix alone.
        invalidateComposition()
        doubleSpaceState.reset()
        expectedHostEdit = nil
        model.symbolBoardManagerPresented = false
        refreshTextPreview()
        model.hostDidEdit(invalidateMode: true)
        synchronizeHostTraits()
    }

    private var currentDocumentIdentifier: UUID? {
        KeyboardDocumentIdentity.read(from: textDocumentProxy)
    }

    // MARK: Copy Image

    /// Freezes exactly the excerpt the preview row is showing and renders it
    /// once; later host edits never change what this panel copies.
    /// The picture uses the remembered fixed sRGB colors, never the
    /// keyboard's appearance, so light and dark keyboards copy the same PNG.
    fileprivate func openPreviewImagePanel(excerpt: KeyboardPreviewExcerpt, availableWidth: CGFloat, visibleHeight: CGFloat) {
        invalidateEnglish()
        // Adopts an imported or restored choice; reads the shared file only here.
        let choice = KeyboardImageColorStore.load(shared: .shared, hasFullAccess: hasFullAccess)
        if model.previewImageColors != choice { model.previewImageColors = choice }
        let export = KeyboardPreviewImageExport.prepare(excerpt: excerpt, availableWidth: availableWidth,
            visibleHeight: visibleHeight, colors: choice.colors, scale: choice.scale, hasFullAccess: hasFullAccess)
        model.previewImageThumbnail = export.thumbnail()
        model.previewImageExport = export
        updatePreviewCaretLiveness()
        // An iPhone in portrait grows to fit the panel.
        updateKeyboardHeight(animated: true)
    }

    /// Re-renders the frozen excerpt in new colors or at a new scale and
    /// remembers the choice (preset id, the two Custom colors and the scale
    /// only). Ignored while copying.
    fileprivate func selectPreviewImageColors(_ choice: KeyboardImageColorChoice) {
        guard let export = model.previewImageExport, export.phase != .copying else { return }
        guard choice != model.previewImageColors else { return }
        model.previewImageColors = choice
        KeyboardImageColorStore.save(choice, shared: .shared, hasFullAccess: hasFullAccess)
        guard choice.colors != export.colors || choice.scale != export.scale,
              let recolored = export.recolored(choice.colors, scale: choice.scale, hasFullAccess: hasFullAccess) else { return }
        // A scale-only change keeps the thumbnail: same canvas, text and layout.
        if recolored.colors != export.colors || model.previewImageThumbnail == nil || recolored.image == nil {
            model.previewImageThumbnail = recolored.thumbnail()
        }
        model.previewImageExport = recolored
    }

    /// Writes the frozen PNG only on this explicit request. A closed or
    /// replaced panel never reaches the pasteboard afterwards.
    fileprivate func copyPreviewImage() {
        guard let export = model.previewImageExport, export.canCopy, let image = export.image else { return }
        let id = export.id
        model.previewImageExport?.phase = .copying
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.previewImageExport?.id == id,
                  self.model.previewImageExport?.phase == .copying else { return }
            switch KeyboardPreviewClipboard.write(image, to: .general, hasFullAccess: self.hasFullAccess) {
            case .copied:
                self.model.previewImageExport?.phase = .copied
                UIAccessibility.post(notification: .announcement, argument: String(localized: "Image copied"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.model.previewImageExport?.id == id,
                          self.model.previewImageExport?.phase == .copied else { return }
                    self.model.previewImageExport?.phase = .ready
                }
            case .fullAccessRequired:
                self.model.previewImageExport?.phase = .fullAccessRequired
            case .unavailable:
                self.model.previewImageExport?.phase = .copyFailed
            }
        }
    }

    fileprivate func closePreviewImagePanel() {
        let open = model.previewImageExport != nil
        if open { model.previewImageExport = nil }
        updatePreviewCaretLiveness()
        if model.previewImageThumbnail != nil { model.previewImageThumbnail = nil }
        if open { updateKeyboardHeight(animated: view.window != nil) }
    }

    // MARK: Inspect Text

    /// Freezes exactly the excerpt the preview row is drawing (without its
    /// "…" marks) and inspects it. Nothing beyond the visible excerpt is
    /// read, kept or logged; Full Access is never needed to inspect.
    fileprivate func openTextInspection(excerpt: KeyboardPreviewExcerpt) {
        guard model.previewImageExport == nil else { return }
        invalidateEnglish()
        let proxy = textDocumentProxy
        // No context at all while the field reports text: the host isn't sharing it.
        let contextAvailable = proxy.documentContextBeforeInput != nil || proxy.documentContextAfterInput != nil || !proxy.hasText
        let catalog = model.catalog
        let state = TextInspectionState.inspect(before: excerpt.before, after: excerpt.after,
            beforeTruncated: excerpt.beforeTruncated, afterTruncated: excerpt.afterTruncated,
            contextAvailable: contextAvailable, restricted: KeyboardHostInputTraits(reading: proxy).isSecureTextEntry,
            catalogVersion: catalog.resourceError == nil ? catalog.version : nil,
            lookup: { catalog.character(at: $0) })
        model.textInspection = KeyboardTextInspection(excerpt: excerpt, state: state,
                                                      copy: TextInspectionCopyState(hasFullAccess: hasFullAccess))
        updatePreviewCaretLiveness()
        // An iPhone in portrait grows to fit the panel, as for Copy Image.
        updateKeyboardHeight(animated: true)
    }

    /// Copies the frozen excerpt, its original scalars as U+ labels, one
    /// normalized form of it, or its UTF-8/UTF-16 hex, only on this explicit
    /// tap. The host's text and the panel never change; the pasteboard is
    /// never read.
    fileprivate func copyTextInspection(_ target: TextInspectionCopyTarget) {
        guard let panel = model.textInspection, let inspection = panel.state.inspection, panel.copy.canCopy,
              let value = inspection.copyValue(for: target) else { return }
        let outcome: TextInspectionCopyOutcome
        if !hasFullAccess {
            outcome = .fullAccessRequired
        } else {
            let pasteboard = UIPasteboard.general
            let before = pasteboard.changeCount
            pasteboard.string = value
            outcome = pasteboard.changeCount != before ? .copied : .failed
        }
        model.textInspection?.copy.record(outcome, for: target)
        guard outcome == .copied else { return }
        UIAccessibility.post(notification: .announcement, argument: TextInspectionWording.copied(target))
        let id = panel.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.model.textInspection?.id == id else { return }
            self.model.textInspection?.copy.endConfirmation(target)
        }
    }

    /// Close, the backdrop, or switching away: typing, caret and Shift are untouched.
    fileprivate func closeTextInspection() {
        guard model.textInspection != nil else { return }
        model.textInspection = nil
        updatePreviewCaretLiveness()
        updateKeyboardHeight(animated: view.window != nil)
    }

    /// The cursor's line, read from up to 96 characters either side, when
    /// the preview row shows it; confirms a preview move in flight.
    private func refreshTextPreview() {
        guard model.showsTextPreview else { return }
        previewCursorDriver.refresh()
    }

    /// The excerpt the preview row is drawing right now, frozen by Inspect
    /// and Copy Image.
    fileprivate func currentPreviewExcerpt() -> KeyboardPreviewExcerpt {
        previewCursorControl?.visibleExcerpt() ?? .empty
    }

    fileprivate func attachPreviewCursor(_ control: KeyboardPreviewCursorControl) {
        guard previewCursorControl !== control else { return }
        previewCursorControl = control
        control.delegate = self
        updatePreviewCaretLiveness()
    }

    /// The preview caret blinks only while the keyboard is shown and no Copy
    /// Image or Inspect panel covers the row (§1a).
    private func updatePreviewCaretLiveness() {
        previewCursorControl?.isCaretLive = isKeyboardShown && !model.hasKeyboardPanel
    }

    /// Publishes Full Access for rendering, only when it actually changed.
    private func refreshFullAccess() {
        if model.hasFullAccess != hasFullAccess { model.hasFullAccess = hasFullAccess }
    }

    private func synchronizeHostTraits() {
        refreshFullAccess()
        refreshTextPreview()
        // UIKit can ask again during a remote resize. Do not invalidate every
        // character key when neither input trait has changed.
        if model.needsInputModeSwitchKey != needsInputModeSwitchKey { model.needsInputModeSwitchKey = needsInputModeSwitchKey }
        guard let document = currentDocumentIdentifier else {
            invalidateEnglish()
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
            invalidateComposition()
            hostSignature = signature
            doubleSpaceState.reset()
            expectedHostEdit = nil
            model.hostDidEdit(invalidateMode: true)
        }
        guard !model.isSearching else { return }
        if language.mode != .direct { model.synchronizeCapitalization(false); return }
        // Follow App keeps the host's own request; the other modes replace
        // it. Restricted fields (URL, email, credentials, secure entry,
        // non-default keyboards) never get automatic capitals.
        let capitalization = KeyboardAutoCapitalizationPolicy.effectiveMode(
            setting: model.autoCapitalization,
            host: KeyboardAutoCapitalizationPolicy.hostMode(rawValue: (proxy.autocapitalizationType ?? .sentences).rawValue),
            permitsAssistance: permitsEnglishAssistance)
        let literalScope = currentLiteralWriteScope()
        guard !literalWriteTransaction.matches(scope: literalScope) else { return }
        model.synchronizeCapitalization(KeyboardEnglishInputPolicy.shouldCapitalize(mode: capitalization, before: proxy.documentContextBeforeInput))
    }

    private var permitsEnglishAssistance: Bool {
        language.mode == .direct && KeyboardHostInputTraits(reading: textDocumentProxy).permitsEnglishAssistance
    }

    private static func contextSuffix(_ text: String) -> [Unicode.Scalar] {
        Array(text.unicodeScalars.suffix(KeyboardEnglishInputPolicy.maximumContextScalars))
    }

    private func acknowledgeHostChange() {
        let snapshot = englishContext()
        let manualAcknowledged = manualEnglishExpected.map { Self.sameEnglishObservation($0, snapshot) } == true
            || manualEnglishResult.map { Self.sameEnglishObservation($0, snapshot) } == true
        let englishAcknowledged = english.observeHostSnapshot(snapshot)
        if englishSurfaceAvailable && (manualAcknowledged || englishAcknowledged) {
            // Own expected writes acknowledge callbacks; never invent context.
            expectedHostEdit = nil
            return
        }
        publishEnglishState()
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
        invalidateComposition()
        doubleSpaceState.reset()
        // Additional same-document text notifications can follow our own
        // edits. Reset punctuation/case hints, but do not invalidate another
        // finger's valid captured key. Document/traits are checked separately.
        model.hostDidEdit()
    }

    // MARK: English assistance (local, opt-in, synchronous proxy transactions)

    private var englishSurfaceAvailable: Bool {
        LanguageInputSettings.englishAssistanceAvailable && language.mode == .direct && model.typingState.alphabet.id == KeyboardAlphabet.english.id
            && !model.showsUnicode && !model.isSearching && !model.hasSymbolBoardOverlay
            && !model.hasKeyboardPanel && !model.finishingConversion && !model.expandedConversion
    }

    private var englishPermission: KeyboardCorrectionHostPermission {
        guard englishSurfaceAvailable else { return .literalField }
        return KeyboardHostInputTraits(reading: textDocumentProxy).englishCorrectionPermission
    }

    private func englishContext() -> KeyboardCorrectionContext {
        let proxy = textDocumentProxy
        return KeyboardCorrectionContext(before: proxy.documentContextBeforeInput,
            after: proxy.documentContextAfterInput, selectedText: proxy.selectedText,
            scope: currentDocumentIdentifier.map {
                KeyboardEnglishInputScope(documentIdentifier: $0, modeIdentifier: model.inputModeID)
            }, completeness: .unknownOrTruncated)
    }

    private static func sameEnglishObservation(_ lhs: KeyboardCorrectionContext,
                                               _ rhs: KeyboardCorrectionContext) -> Bool {
        func same(_ a: String?, _ b: String?) -> Bool {
            switch (a, b) {
            case let (.some(a), .some(b)): return a.unicodeScalars.elementsEqual(b.unicodeScalars)
            case (.none, .none): return true
            default: return false
            }
        }
        return lhs.scope != nil && lhs.scope == rhs.scope
            && same(lhs.before, rhs.before) && same(lhs.after, rhs.after)
            && same(lhs.selectedText, rhs.selectedText)
    }

    private func synchronizeEnglishOptions() {
        english.setOptions(KeyboardEnglishCorrectionOptions(
            suggestionsEnabled: language.preferences.effectiveEnglishSuggestions,
            autocorrectionEnabled: language.preferences.effectiveEnglishAutocorrection))
        publishEnglishState()
    }

    private func invalidateEnglish() {
        englishInteraction = UUID()
        // Called on every key, Shift, layout, language and query change: only
        // republish the model when a revision can matter (see the policy).
        if KeyboardEnglishRevisionPolicy.invalidationIssuesRevision(
            assistanceAvailable: LanguageInputSettings.englishAssistanceAvailable,
            showsSuggestions: !model.englishSuggestions.isEmpty, showsOriginal: model.englishOriginal != nil,
            canReplace: model.englishCanReplace, hasUndo: model.englishHasUndo) {
            model.englishRevision = UUID()
        }
        manualEnglishExpected = nil
        manualEnglishResult = nil
        english.invalidate()
        publishEnglishState()
    }

    private func englishVisibleSuggestions() -> [String] {
        guard englishSurfaceAvailable, language.preferences.effectiveEnglishSuggestions,
              let word = english.trackedWord,
              KeyboardHostInputTraits(reading: textDocumentProxy).permitsEnglishAssistance else { return [] }
        let custom = language.englishCustomOutputs(for: word) ?? []
        var seen = Set<[UInt32]>()
        // Scalar identities preserve canonically equivalent but distinct outputs.
        return Array((custom + english.suggestions).filter {
            seen.insert($0.unicodeScalars.map(\.value)).inserted
        }.prefix(12))
    }

    private func publishEnglishState() {
        let values = englishVisibleSuggestions()
        let original = english.hasImmediateUndo ? english.correctedOriginalWord : nil
        let canReplace = englishSurfaceAvailable && english.hasVerifiedReplacementScope
            && english.trackedWord != nil && englishPermission == .permits
        let hasUndo = englishSurfaceAvailable && english.hasImmediateUndo
        let undoAvailabilityChanged = model.englishHasUndo != hasUndo
        let status: String
        if !values.isEmpty && !canReplace { status = "Suggestions unavailable here." }
        else if english.dictionaryAvailability == .dictionaryUnavailable { status = "English suggestions unavailable" }
        else { status = "English" }
        if model.englishSuggestions.map({ Array($0.utf8) }) != values.map({ Array($0.utf8) })
            || model.englishOriginal.map({ Array($0.utf8) }) != original.map({ Array($0.utf8) })
            || model.englishCanReplace != canReplace || model.englishHasUndo != hasUndo
            || model.englishStatus != status {
            model.englishSuggestions = values
            model.englishOriginal = original
            model.englishCanReplace = canReplace
            model.englishHasUndo = hasUndo
            model.englishStatus = status
            model.englishRevision = UUID()
        }
        if undoAvailabilityChanged { updateKeyboardHeight() }
    }

    private struct EnglishExecutionGuard: Equatable {
        let document: UUID
        let mode: UUID
        let interaction: UUID
        let englishInteraction: UUID
        let traits: KeyboardHostInputTraits
    }

    private func englishExecutionGuard() -> EnglishExecutionGuard? {
        guard englishSurfaceAvailable, let document = currentDocumentIdentifier else { return nil }
        return EnglishExecutionGuard(document: document, mode: model.inputModeID,
            interaction: deleteInteractionID, englishInteraction: englishInteraction,
            traits: KeyboardHostInputTraits(reading: textDocumentProxy))
    }

    /// Returns true once a plan is dispatched, INCLUDING a partial failure. A
    /// failed transaction must never replay the delimiter into another field.
    private func insertEnglishDelimiter(_ delimiter: String,
                                        onCorrection: ((KeyboardCorrectionContext) -> Void)? = nil) -> Bool {
        guard englishSurfaceAvailable, KeyboardAutocorrectionPolicy.isAutomaticDelimiter(delimiter),
              let reading = english.trackedWord else { return false }
        let customProtected = language.protectsEnglishCustomReading(reading)
        guard let plan = english.planForDelimiter(delimiter, context: englishContext(),
            hostPermission: englishPermission, isKnownCustomReading: customProtected) else {
            publishEnglishState(); return false
        }
        if executeEnglishPlan(plan, protectedReading: reading) {
            let actual = englishContext()
            if english.hasImmediateUndo, Self.sameEnglishObservation(plan.resultingContext, actual) {
                onCorrection?(actual)
            }
        }
        return true
    }

    private func insertOrdinaryEnglish(_ text: String) -> Bool {
        guard literalWriteToken == nil, englishSurfaceAvailable,
              let bound = englishExecutionGuard() else { return false }
        if insertEnglishDelimiter(text) { return true }
        // Bind rendered suggestion actions to this exact input revision even
        // when two successive words happen to receive identical suggestions.
        model.englishRevision = UUID()
        // Ordinary provenance never applies to saved keys, variants or Unicode.
        english.willInsert(text, origin: .ordinaryKey, context: englishContext(), hostPermission: englishPermission)
        englishWriteInProgress = true
        defer { englishWriteInProgress = false; publishEnglishState() }
        expectedHostEdit = nil
        previewCursorDriver.keyboardWillEdit()
        guard englishExecutionGuard() == bound else { invalidateEnglish(); return false }
        textDocumentProxy.insertText(text)
        guard englishExecutionGuard() == bound else { invalidateEnglish(); return true }
        english.didInsert(context: englishContext(), hostPermission: englishPermission)
        return true
    }

    @discardableResult
    private func executeEnglishPlan(_ plan: KeyboardGuardedReplacementPlan,
                                    protectedReading: String? = nil) -> Bool {
        guard !englishWriteInProgress, let bound = englishExecutionGuard() else { invalidateEnglish(); return false }
        englishWriteInProgress = true
        defer { englishWriteInProgress = false; publishEnglishState() }
        expectedHostEdit = nil
        previewCursorDriver.keyboardWillEdit()
        for (index, step) in plan.steps.enumerated() {
            guard englishExecutionGuard() == bound,
                  protectedReading.map({ !language.protectsEnglishCustomReading($0) }) ?? true,
                  english.authorizesStep(index, of: plan, context: englishContext(), hostPermission: englishPermission)
            else { invalidateEnglish(); return false }
            switch step.operation {
            case .deleteBackward: textDocumentProxy.deleteBackward()
            case .insertText(let text): textDocumentProxy.insertText(text)
            }
            guard englishExecutionGuard() == bound,
                  english.validateStepResult(index, of: plan, context: englishContext(), hostPermission: englishPermission)
            else { invalidateEnglish(); return false }
        }
        return english.didExecute(plan, context: englishContext(), hostPermission: englishPermission)
    }

    fileprivate func undoEnglish(revision: UUID) {
        guard revision == model.englishRevision, englishSurfaceAvailable,
              let plan = english.planUndo(context: englishContext(), hostPermission: englishPermission) else {
            publishEnglishState(); return
        }
        _ = executeEnglishPlan(plan)
        didEditHostText()
    }

    /// Explicit manual selection permits arbitrary saved Unicode output, never
    /// automatic substitution. The deleted span is ONLY our verified ASCII word.
    fileprivate func chooseEnglish(_ text: String, revision: UUID) {
        guard revision == model.englishRevision, !englishWriteInProgress,
              english.hasVerifiedReplacementScope, englishPermission == .permits,
              let word = english.trackedWord, !word.isEmpty, word.utf8.count <= 32,
              word.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              englishVisibleSuggestions().contains(where: { $0.unicodeScalars.elementsEqual(text.unicodeScalars) }),
              let bound = englishExecutionGuard() else { return }
        let start = englishContext()
        guard english.observeHostSnapshot(start), english.hasVerifiedReplacementScope,
              english.trackedWord?.unicodeScalars.elementsEqual(word.unicodeScalars) == true,
              let before = start.before, let after = start.after, start.selectedText == "",
              before.utf8.suffix(word.utf8.count).elementsEqual(word.utf8),
              before.unicodeScalars.count <= 4096, after.unicodeScalars.count <= 4096,
              !text.isEmpty, text.unicodeScalars.count <= 256 else { invalidateEnglish(); return }
        var expected = before
        let requiresCustom = !english.suggestions.contains(where: { $0.unicodeScalars.elementsEqual(text.unicodeScalars) })
        guard !requiresCustom || language.englishCustomOutputs(for: word)?.contains(where: {
            $0.unicodeScalars.elementsEqual(text.unicodeScalars)
        }) == true else { invalidateEnglish(); return }
        // Capture the live verified target BEFORE revoking the automatic plan.
        english.invalidate()
        englishWriteInProgress = true
        defer {
            manualEnglishExpected = nil; manualEnglishResult = nil
            englishWriteInProgress = false; publishEnglishState()
        }
        previewCursorDriver.keyboardWillEdit()
        expectedHostEdit = nil
        func context(_ before: String) -> KeyboardCorrectionContext {
            KeyboardCorrectionContext(before: before, after: after, selectedText: "",
                scope: start.scope, completeness: .unknownOrTruncated)
        }
        for index in 0...word.count {
            let input = context(expected)
            let output: String
            if index < word.count { output = String(expected.dropLast()) }
            else { output = expected + text }
            let result = context(output)
            manualEnglishExpected = input; manualEnglishResult = result
            guard englishExecutionGuard() == bound, englishPermission == .permits,
                  Self.sameEnglishObservation(input, englishContext()),
                  !requiresCustom || language.englishCustomOutputs(for: word)?.contains(where: {
                      $0.unicodeScalars.elementsEqual(text.unicodeScalars)
                  }) == true else { invalidateEnglish(); return }
            if index < word.count { textDocumentProxy.deleteBackward() }
            else { textDocumentProxy.insertText(text) }
            guard englishExecutionGuard() == bound, englishPermission == .permits,
                  Self.sameEnglishObservation(result, englishContext()) else { invalidateEnglish(); return }
            expected = output
        }
        // The completed selection is literal and cannot be immediately recorrected.
        didEditHostText()
    }

    private func readCompositionAnchor() -> CompositionAnchor? {
        guard let document = currentDocumentIdentifier else { return nil }
        let proxy = textDocumentProxy
        return CompositionAnchor(document: document, interaction: deleteInteractionID,
            before: proxy.documentContextBeforeInput.map { Array($0.utf8) },
            after: proxy.documentContextAfterInput.map { Array($0.utf8) },
            selection: proxy.selectedText.map { Array($0.utf8) })
    }

    private func invalidateComposition() {
        invalidateEnglish()
        guard !completingConversion else { return }
        language.documentChanged()
        compositionAnchor = nil
        conversionPostWriteAnchor = nil
        pendingConversionAction = nil
        pendingConversionAnchor = nil
        queuedPunctuation = nil
        model.queuedConversionPunctuation = nil
        model.finishingConversion = false
        model.expandedConversion = false
    }

    @discardableResult
    private func finishConversionBefore(_ action: @escaping () -> Void) -> Bool {
        finishConversionBefore(.guardedAction(action))
    }

    @discardableResult
    private func finishConversionBeforeInputMode(_ transition: InputModeTransition) -> Bool {
        guard !model.finishingConversion else { return false }
        guard !language.rawInput.isEmpty else { performInputModeTransition(transition); return true }
        guard let scope = readConversionModeScope() else { return false }
        return finishConversionBefore(.inputMode(transition, scope))
    }

    private func performConversionAction(_ action: PendingConversionAction) {
        switch action {
        case .guardedAction(let action): action()
        case .inputMode(let transition, _): performInputModeTransition(transition)
        }
    }

    /// Keep this dispatcher local-only: no host insert/delete/cursor operations.
    private func performInputModeTransition(_ transition: InputModeTransition) {
        switch transition {
        case .target(let id): switchInputTarget(id)
        case .directTyping:
            let previous = language.mode
            if language.select(.direct) { rememberChosenMode(.direct, previous: previous) }
            model.synchronizeLanguageKeyboard()
        }
    }

    private func readConversionModeScope() -> LanguageCompositionModeTransitionScope? {
        guard isKeyboardShown, let document = currentDocumentIdentifier else { return nil }
        // inputModeID also revokes on selection/focus/trait callbacks, even if
        // their exposed strings and document ID happen to return unchanged.
        return .init(document: document, inputMode: model.inputModeID,
            interaction: deleteInteractionID,
            selection: textDocumentProxy.selectedText.map { Array($0.utf8) })
    }

    @discardableResult
    private func finishConversionBefore(_ action: PendingConversionAction) -> Bool {
        guard !model.finishingConversion else { return false }
        guard !language.rawInput.isEmpty else { performConversionAction(action); return true }
        guard let anchor = compositionAnchor, anchor == readCompositionAnchor() else {
            invalidateComposition(); return false
        }
        pendingConversionAction = action
        pendingConversionAnchor = anchor
        model.finishingConversion = true
        return true
    }

    fileprivate func resolveConversionTransition(keepTypedText: Bool?, token: LanguageCompositionToken) {
        // An old view activation must never clear newer input/resources.
        guard token == language.state.token, model.finishingConversion,
              let anchor = pendingConversionAnchor else { return }
        guard anchor == readCompositionAnchor() else {
            invalidateComposition(); return
        }
        guard let keepTypedText else {
            pendingConversionAction = nil; pendingConversionAnchor = nil
            model.finishingConversion = false
            return
        }
        guard let action = pendingConversionAction else { return }
        if case .inputMode(_, let scope) = action, readConversionModeScope() != scope {
            invalidateComposition(); return
        }
        // Keep the request visible if commit-time resource validation revokes
        // this token. A fresh panel action can still recover the exact raw text.
        var expected = anchor
        if keepTypedText {
            let effects = language.mode == .koreanTwoSetHangul
                ? language.commitDefault(token: token) : language.commitLiteral(token: token)
            guard !effects.isEmpty else { return }
            switch action {
            case .inputMode(_, let scope):
                guard commitConversionForInputMode(effects, scope: scope) else {
                    invalidateComposition(); return
                }
            case .guardedAction:
                guard applyConversionEffects(effects), let postWrite = conversionPostWriteAnchor else {
                    invalidateComposition(); return
                }
                expected = postWrite
            }
        } else { language.cancel(); compositionAnchor = nil }
        pendingConversionAction = nil; pendingConversionAnchor = nil
        model.finishingConversion = false
        switch action {
        case .inputMode(_, let scope):
            guard readConversionModeScope() == scope,
                  keepTypedText || readCompositionAnchor() == expected else { invalidateComposition(); return }
        case .guardedAction:
            // Arbitrary actions (including second host writes) still require
            // ALL exposed context before replay.
            guard readCompositionAnchor() == expected else { invalidateComposition(); return }
        }
        performConversionAction(action)
    }

    /// A single accepted commit can finish a LOCAL mode change even when the
    /// proxy withholds or delays its text context. This never mints an anchor
    /// for punctuation, a saved key, cursor movement, or another host write.
    private func commitConversionForInputMode(_ effects: [LanguageCompositionEffect],
                                             scope: LanguageCompositionModeTransitionScope) -> Bool {
        conversionPostWriteAnchor = nil
        guard let text = LanguageCompositionModeTransitionScope.completeCommitText(in: effects),
              language.rawInput.isEmpty, scope.selection?.isEmpty != false,
              readConversionModeScope() == scope,
              let anchor = compositionAnchor, anchor == readCompositionAnchor() else { return false }
        completingConversion = true
        defer { completingConversion = false }
        let accepted = insertHostText(text, resolvingComposition: false)
        guard scope.permitsContinuation(after: effects, commitAccepted: accepted,
                                        current: readConversionModeScope()) else { return false }
        compositionAnchor = nil
        model.expandedConversion = false
        doubleSpaceState.reset()
        synchronizeHostTraits()
        return readConversionModeScope() == scope
    }

    private func expectedAnchor(afterInserting text: String, into anchor: CompositionAnchor) -> CompositionAnchor? {
        // Without preceding context we cannot authorize a second chained write.
        guard let before = anchor.before, anchor.selection?.isEmpty != false else { return nil }
        return CompositionAnchor(document: anchor.document, interaction: anchor.interaction,
            before: before + Array(text.utf8), after: anchor.after, selection: anchor.selection)
    }

    @discardableResult
    private func applyConversionEffects(_ effects: [LanguageCompositionEffect]) -> Bool {
        conversionPostWriteAnchor = nil
        guard let anchor = compositionAnchor, anchor == readCompositionAnchor(), !effects.isEmpty else { return false }
        completingConversion = true
        defer { completingConversion = false }
        var expected = anchor
        for effect in effects {
            guard readCompositionAnchor() == expected else { return false }
            switch effect {
            case .commit(let text, _):
                let postWrite = expectedAnchor(afterInserting: text, into: expected)
                guard insertHostText(text, resolvingComposition: false) else { return false }
                // A focus/cursor change or a host transformation can happen
                // synchronously inside insertText, even in the same document.
                guard let postWrite, readCompositionAnchor() == postWrite else {
                    compositionAnchor = nil
                    model.expandedConversion = false
                    return false
                }
                expected = postWrite
            case .hostDelete: return false
            }
        }
        conversionPostWriteAnchor = expected
        compositionAnchor = language.rawInput.isEmpty ? nil : expected
        model.expandedConversion = false
        doubleSpaceState.reset()
        synchronizeHostTraits()
        return true
    }

    private func insertQueuedPunctuation(_ punctuation: String?) {
        guard let punctuation else { return }
        guard let expected = conversionPostWriteAnchor, readCompositionAnchor() == expected else {
            invalidateComposition(); return
        }
        if insertHostText(punctuation, resolvingComposition: false) { didEditHostText() }
    }

    fileprivate func chooseConversion(_ id: String, token: LanguageCompositionToken) {
        guard token == language.state.token else { return }
        guard let anchor = compositionAnchor, anchor == readCompositionAnchor() else { invalidateComposition(); return }
        let punctuation = queuedPunctuation
        let effects = language.choose(id: id, token: token)
        guard !effects.isEmpty else { return }
        queuedPunctuation = nil; model.queuedConversionPunctuation = nil
        guard applyConversionEffects(effects) else { invalidateComposition(); return }
        insertQueuedPunctuation(punctuation)
    }

    fileprivate func keepRomanLetters(token: LanguageCompositionToken) {
        guard token == language.state.token else { return }
        guard let anchor = compositionAnchor, anchor == readCompositionAnchor() else { invalidateComposition(); return }
        let punctuation = queuedPunctuation
        let effects = language.commitLiteral(token: token)
        guard !effects.isEmpty else { return }
        queuedPunctuation = nil; model.queuedConversionPunctuation = nil
        guard applyConversionEffects(effects) else { invalidateComposition(); return }
        insertQueuedPunctuation(punctuation)
    }

    fileprivate func cancelConversion(token: LanguageCompositionToken) {
        guard token == language.state.token else { return }
        language.cancel(); compositionAnchor = nil; queuedPunctuation = nil
        model.queuedConversionPunctuation = nil
        model.expandedConversion = false
    }

    fileprivate func expandConversion() { model.expandedConversion = true }
    fileprivate func closeConversionChoices() { model.expandedConversion = false; queuedPunctuation = nil; model.queuedConversionPunctuation = nil }

    /// Returns true when this tap belongs to local composition. Explicit saved
    /// outputs and gesture variants are never routed through this function.
    private func insertTypingText(_ text: String, normalTap: Bool) -> Bool {
        if language.mode == .direct {
            return normalTap && englishSurfaceAvailable
                ? insertOrdinaryEnglish(text) : insertHostText(text)
        }
        guard normalTap else { return insertHostText(text) }
        guard !model.showsUnicode else { return false }
        if language.rawInput.isEmpty { compositionAnchor = readCompositionAnchor() }
        guard compositionAnchor != nil, compositionAnchor == readCompositionAnchor() else { invalidateComposition(); return false }
        // The mode-specific parser owns eligibility. Punctuation is a boundary,
        // not permission to reinterpret arbitrary explicit Unicode output.
        let recognized: Bool
        switch language.mode {
        case .japaneseRomaji: recognized = JapaneseInputReading.normalize(mode: .japaneseRomaji, rawInput: language.rawInput + text) != nil
        case .koreanTwoSetHangul: recognized = KoreanTwoSetKeyboard.accepts(language.rawInput + text)
        case .mandarinPinyin: recognized = (try? MandarinPinyinReading(language.rawInput + text)) != nil
        default: recognized = false
        }
        if recognized { return language.append(text) }
        if text.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) || CharacterSet.decimalDigits.contains($0) }) {
            if !language.rawInput.isEmpty { return confirmConversion(then: text) }
            compositionAnchor = nil
            return insertHostText(text)
        }
        // Unsupported phonetics never leak into the host under a conversion label.
        return language.append(text)
    }

    @discardableResult
    private func confirmConversion(then punctuation: String? = nil, space: Bool = false) -> Bool {
        guard !language.rawInput.isEmpty else { return false }
        guard compositionAnchor == readCompositionAnchor() else { invalidateComposition(); return true }
        if model.showsUnicode || model.compositionShelfHeight == 0 {
            queuedPunctuation = punctuation; model.queuedConversionPunctuation = punctuation
            model.expandedConversion = true
            return true
        }
        let token = language.state.token
        let effects = language.commitDefault(token: token, space: space)
        guard !effects.isEmpty else { return true }
        guard applyConversionEffects(effects) else { invalidateComposition(); return true }
        insertQueuedPunctuation(punctuation)
        return true
    }

    @discardableResult
    private func insertHostText(_ text: String, literalToken: UUID? = nil, resolvingComposition: Bool = true, onInserted: @escaping () -> Void = {}) -> Bool {
        typedSinceAppear = true
        if resolvingComposition && !completingConversion && !language.rawInput.isEmpty {
            return finishConversionBefore { [weak self] in
                guard let self, self.insertHostText(text, resolvingComposition: false, onInserted: onInserted) else { return }
                self.didEditHostText()
            }
        }
        guard literalWriteToken == nil || literalWriteToken == literalToken,
              let document = currentDocumentIdentifier else { return false }
        let proxy = textDocumentProxy
        if let before = proxy.documentContextBeforeInput {
            expectedHostEdit = ExpectedHostEdit(document: document,
                before: Self.contextSuffix(before + text), expires: ProcessInfo.processInfo.systemUptime + 1)
        } else { expectedHostEdit = nil }
        invalidateEnglish()
        previewCursorDriver.keyboardWillEdit()
        proxy.insertText(text)
        onInserted()
        return true
    }

    private func currentLiteralWriteScope() -> KeyboardLiteralWriteScope? {
        guard !model.isSearching, !model.hasSymbolBoardOverlay,
              let document = currentDocumentIdentifier else { return nil }
        return KeyboardLiteralWriteScope(typingState: model.typingState, documentIdentifier: document,
            modeIdentifier: model.inputModeID, interactionIdentifier: deleteInteractionID)
    }

    private func insertLiteralGestureText(_ text: String) -> Bool {
        if !language.rawInput.isEmpty {
            guard literalWriteToken == nil, let scope = currentLiteralWriteScope() else { return false }
            return finishConversionBefore { [weak self] in
                guard let self, self.currentLiteralWriteScope() == scope else { return }
                _ = self.insertLiteralGestureText(text)
            }
        }
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
        typedSinceAppear = true
        doubleSpaceState.reset()
        model.hostDidEdit()
        synchronizeHostTraits()
    }

    @objc private func updateBackdrop() {
        // iOS 26 draws its own opaque, rounded backdrop with Reduce Transparency;
        // a rectangular fill here would square off its corners.
        let opaque = UIAccessibility.isReduceTransparencyEnabled && Self.needsOwnOpaqueBackdrop
        view.backgroundColor = opaque ? KeyboardPalette.backgroundUI : .clear
        view.isOpaque = opaque
    }

    nonisolated static var needsOwnOpaqueBackdrop: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    /// `animated` eases a panel's height change in 0.2 seconds, never with
    /// Reduce Motion.
    private func updateKeyboardHeight(animated: Bool = false) {
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
        // Preserve the preexisting normal-key baseline even when autocorrection
        // has no suggestions/Undo to show. Shelf visibility is a separate choice.
        let usesCompositionLayout = !model.showsUnicode && (language.mode != .direct
            || (englishSurfaceAvailable && (language.preferences.effectiveEnglishSuggestions
                || language.preferences.effectiveEnglishAutocorrection || model.englishHasUndo)))
        let conversionVisible = usesCompositionLayout && (language.mode != .direct
            || language.preferences.effectiveEnglishSuggestions || model.englishHasUndo)
        // Resolve compact geometry BEFORE counting projected rows. The compact
        // predicate is independent of row count; never use last frame's mode.
        let geometryMetrics = KeyboardLayoutPolicy.metrics(
            viewWidth: view.bounds.width, displaySize: scene?.screen.bounds.size,
            sceneHeight: usesCompositionLayout ? nil : sceneSize?.height, isPad: pad,
            compactVertical: traitCollection.verticalSizeClass == .compact)
        model.updateTypingLayoutContext(isPhone: traitCollection.userInterfaceIdiom == .phone,
            isPad: pad, compact: geometryMetrics.isCompactLayout)
        // The same presentation drives height, rendering and action routing.
        let rows = model.typingArrangement.keyRows(widePad: pad && view.bounds.width - 16 >= 650)
        let keyRows = language.mode != .koreanTwoSetHangul && landscapePad && model.typingArrangement.isLegacy && model.padLayout == .ansiNumbers ? max(MainKeyboardArrangement.maximumRows, rows) : rows
        let prefersCompactShelf = language.mode == .direct || language.mode == .koreanTwoSetHangul
            || model.typingPresentation.isCompactConversion || !KeyboardConversionShelfMetrics.regularCaptionFits(
            mode: language.mode, containerWidth: max(0, view.bounds.width - 16), traits: traitCollection)
        let metrics = KeyboardLayoutPolicy.metrics(
            viewWidth: view.bounds.width, displaySize: scene?.screen.bounds.size,
            sceneHeight: usesCompositionLayout ? nil : sceneSize?.height, isPad: pad,
            compactVertical: traitCollection.verticalSizeClass == .compact,
            keyRows: keyRows,
            searching: model.isSearching, browsing: model.showsUnicode && !model.isSearching,
            showsTextPreview: model.showsTextPreview,
            previewImagePanel: model.hasKeyboardPanel, stockRows: model.usesPhonePortraitGeometry)
        // The existing metrics include preview/footer/gaps; the optional typing
        // toolbar is actual additional chrome, not borrowed key-row space.
        let portrait = metrics.usesPhonePortraitGeometry
        (view as? KeyboardSelfSizingInputView)?.routesStockKeyGaps = portrait
        let toolbarChrome = usesCompositionLayout && model.showsUnicodeToolbar && !portrait ? metrics.typingKeyHeight : 0
        let compositionPlan = KeyboardCompositionLayoutPolicy.plan(
            baselineHeight: metrics.height + toolbarChrome, baselineKeyHeight: metrics.typingKeyHeight,
            sceneHeight: sceneSize?.height, actualGrantedHeight: view.bounds.height,
            conversionEnabled: conversionVisible, surfaceAvailable: !model.hasKeyboardPanel,
            baselineKeyRows: keyRows, rowSpacing: portrait ? 11 : pad && view.bounds.width >= 666 ? 6 : 4,
            hostHeightIsSettled: isKeyboardShown && view.window != nil,
            prefersCompactShelf: prefersCompactShelf, englishSingleRow: language.mode == .direct,
            reservedShelfHeight: portrait ? 42 : 0)
        let shelf = conversionVisible ? compositionPlan.shelfHeight : 0
        if model.compositionShelfHeight != shelf { model.compositionShelfHeight = shelf }
        model.updateTypingGeometry(availableWidth: max(0, view.bounds.width - 16),
            normalKeyHeight: usesCompositionLayout ? compositionPlan.mergeNormalKeyHeight : metrics.typingKeyHeight)
        let typingHeight = metrics.typingKeyHeight
        if model.typingKeyHeight != typingHeight { model.typingKeyHeight = typingHeight }
        let portraitRows = KeyboardPhonePortraitGeometry.Rows(width: view.bounds.width)
        if model.phonePortraitRows != portraitRows { model.phonePortraitRows = portraitRows }
        applyKeyboardHeight(usesCompositionLayout ? compositionPlan.requestedHeight : metrics.height,
            animated: animated && !UIAccessibility.isReduceMotionEnabled)
    }



    private func applyKeyboardHeight(_ height: CGFloat, animated: Bool = false) {
        guard height.isFinite, height > 0 else { return }
        guard let input = view as? KeyboardSelfSizingInputView else { return }
        var changed = false
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                changed = input.requestHeight(height)
                if changed { self.view.superview?.layoutIfNeeded() }
            }
            return
        }
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
                && !self.model.finishingConversion && !self.model.expandedConversion
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
        if language.mode == .koreanTwoSetHangul, model.typingState.layout == .letters {
            return makeHangulKeyActions(renderedMode: renderedMode, key: key)
        }
        // Shift's place on a caseless layout holds the Arabic Diacritics key.
        if key == MainKeyboardArrangement.shift { return makeDiacriticsActions(renderedMode: renderedMode) }
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
        let original = KeyboardTypingLayoutPolicy.routedOutput(for: key, state: captured,
            hasAuxiliaryRow: hasAuxiliaryRow, isAuxiliaryKey: isAuxiliaryKey,
            widePad: widePad, ansiPad: ansiPad, padLayout: padLayout, arrangement: model.typingArrangement, mergedSymbols: model.mergesSymbols)
        guard let original else { return nil }
        let mergedSymbols = model.mergesSymbols
        let settings = model.keySettings
        let tapText = settings.tapOutput(for: keyID, defaultText: original,
            shifted: KeyboardTypingLayoutPolicy.usesShiftedTap(for: key, state: captured, ansiPad: ansiPad))
        let choices = KeyboardVariantPolicy.options(text: original,
            variants: KeyboardVariantPolicy.holdVariants(for: key, state: captured))
        let gestures = KeyboardVariantPolicy.gestureCandidates(for: key, original: original, state: captured, settings: settings)
        let accepts: () -> Bool = { [weak self] in
            current() && self?.model.showsUnicode == false && self?.model.hasSymbolBoardOverlay == false
                && self?.model.keySettings == settings && self?.model.padLayout == padLayout
                && self?.model.mergesSymbols == mergedSymbols
                && self?.model.typingState.layout == captured.layout
                && (self?.model.typingAuxiliaryRowVisible.map({ $0 == hasAuxiliaryRow }) ?? true)
                && (self?.model.typingWidePadVisible.map({ $0 == widePad }) ?? !widePad)
                && (self?.model.typingANSIPadVisible.map({ $0 == ansiPad }) ?? !ansiPad)
        }
        let insertOrdinary: (String, Bool) -> Bool = { [weak self] text, normalTap in
            guard let self, accepts() else { return false }
            self.doubleSpaceState.reset()
            let didInsert: () -> Void = { [weak self] in
                guard let self else { return }
                if captured.layout == .letters && !isAuxiliaryKey && (ansiPad || captured.output(for: key) != nil) { self.model.didInsertTypingKey(key, capturedState: captured, ansiPad: ansiPad, padLayout: padLayout) }
                else { self.model.didInsertNumberRowKey(capturedState: captured) }
                self.synchronizeHostTraits()
            }
            if !normalTap {
                // A saved exact tap/variant can be deferred. Do not consume
                // one-shot Shift or mark the key used until the write occurs.
                return self.insertHostText(text, onInserted: didInsert)
            }
            guard self.insertTypingText(text, normalTap: true) else { return false }
            didInsert()
            return true
        }
        return .init(isCurrent: accepts, insert: { text in
            KeyboardVariantPolicy.contains(text, in: choices) && insertOrdinary(text, false)
        }, options: choices, longPressOptions: gestures.longPress, swipeUp: gestures.swipeUp, swipeDown: gestures.swipeDown,
           tap: {
            guard let tapText else { return false }
            let normal = tapText.utf8.elementsEqual(original.utf8)
                && settings.candidates(for: keyID, gesture: .tap) == nil
                && settings.candidates(for: keyID, gesture: .shiftedTap) == nil
            return insertOrdinary(tapText, normal)
        },
           insertGesture: { [weak self] text, gesture in
            guard let self, accepts(), gesture == .longPress || gesture == .swipeUp || gesture == .swipeDown else { return false }
            let allowed = gesture == .longPress ? gestures.longPress : gesture == .swipeUp ? gestures.swipeUp : gestures.swipeDown
            guard KeyboardVariantPolicy.contains(text, in: allowed) else { return false }
            self.doubleSpaceState.reset()
            if gesture == .longPress, captured.layout == .letters, !isAuxiliaryKey, captured.output(for: key) != nil {
                return self.insertHostText(text, onInserted: { [weak self] in
                    self?.model.didInsertTypingKey(key, capturedState: captured)
                    self?.synchronizeHostTraits()
                })
            } else { return self.insertLiteralGestureText(text) }
        })
    }

    /// Jamo taps and the seven shifted hold choices are semantic physical IDs,
    /// never saved English tap/gesture outputs or literal host text.
    private func makeHangulKeyActions(renderedMode: UUID, key: String) -> KeyboardVariantActions? {
        guard let current = makeBoardConfigurationGuard(renderedMode: renderedMode),
              !model.showsUnicode, KoreanTwoSetKeyboard.rows.flatMap({ $0 }).contains(key) else { return nil }
        let captured = model.typingState
        let raw = KoreanTwoSetKeyboard.keyID(key, shifted: captured.shift != .lowercase)
        let shiftedFace = KoreanTwoSetKeyboard.shiftedVariant(for: key)
        let choices = shiftedFace.map { [$0] } ?? []
        let accepts: () -> Bool = { [weak self] in
            guard let self else { return false }
            return !self.model.showsUnicode && KoreanTwoSetKeyboard.acceptsHeldKey(
                contextIsCurrent: current(), mode: self.language.mode,
                captured: captured, current: self.model.typingState)
        }
        let insert: (String) -> Bool = { [weak self] rawID in
            guard let self, accepts() else { return false }
            self.doubleSpaceState.reset()
            guard self.insertTypingText(rawID, normalTap: true) else { return false }
            self.model.didInsertTypingKey(key, capturedState: captured)
            self.synchronizeHostTraits()
            return true
        }
        return .init(isCurrent: accepts, insert: { face in
            guard face == shiftedFace else { return false }
            return insert(key.uppercased())
        }, options: choices, longPressOptions: choices, tap: { insert(raw) },
        insertGesture: { face, gesture in
            guard gesture == .longPress, face == shiftedFace else { return false }
            return insert(key.uppercased())
        })
    }

    private func makeShiftSlideAction(renderedMode: UUID) -> ((String) -> Bool)? {
        guard language.mode != .koreanTwoSetHangul, !model.showsUnicode, model.typingState.layout == .letters,
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
            return self.insertHostText(text, onInserted: { [weak self] in
                self?.model.didInsertTypingKey(key, capturedState: captured, ansiPad: ansi, padLayout: preset)
                self?.synchronizeHostTraits()
            })
        }
    }

    /// The Arabic Diacritics key: hold and slide inserts one mark; a tap,
    /// or VoiceOver activation, opens the panel and types nothing.
    private func makeDiacriticsActions(renderedMode: UUID) -> KeyboardVariantActions? {
        let marks = model.typingState.alphabet.diacritics.map(\.mark)
        guard !marks.isEmpty, !model.showsUnicode, !model.hasSymbolBoardOverlay, model.typingState.layout == .letters,
              let current = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let alphabetID = model.typingState.alphabet.id
        let accepts: () -> Bool = { [weak self] in
            guard let self else { return false }
            return current() && !self.model.showsUnicode && !self.model.hasSymbolBoardOverlay
                && self.model.typingState.layout == .letters && self.model.typingState.alphabet.id == alphabetID
        }
        let insert: (String) -> Bool = { [weak self] mark in
            guard let self, accepts(), KeyboardVariantPolicy.contains(mark, in: marks) else { return false }
            return self.insertDiacritic(mark)
        }
        return .init(isCurrent: accepts, insert: insert, longPressOptions: marks,
            tap: { [weak self] in
                guard let self, accepts() else { return false }
                self.doubleSpaceState.reset(); self.expectedHostEdit = nil
                return self.model.openDiacritics()
            },
            insertGesture: { mark, gesture in gesture == .longPress && insert(mark) })
    }

    /// Exactly the mark's one scalar, never its dotted-circle picture, with
    /// no normalization; it joins whatever precedes it. Closes the panel.
    private func insertDiacritic(_ mark: String) -> Bool {
        guard mark.unicodeScalars.count == 1, model.typingState.alphabet.diacritics.contains(where: { $0.mark == mark }) else { return false }
        doubleSpaceState.reset()
        return insertHostText(mark, onInserted: { [weak self] in
            self?.model.closeDiacritics(returningFocus: true)
            self?.didEditHostText()
        })
    }

    /// Spell checking and dictation in the host follow the current layout.
    private func applyPrimaryLanguage() {
        let alphabet = model.typingState.alphabet
        let desired: String
        switch language.mode {
        case .japaneseRomaji: desired = "ja-JP"
        case .mandarinPinyin: desired = "zh-Hans"
        case .koreanRomaja, .koreanTwoSetHangul: desired = "ko-KR"
        case .direct: desired = alphabet == .english ? "en-US" : alphabet.id
        }
        guard lastAppliedPrimaryLanguage != desired else { return }
        // UIKit can synchronously publish another selection/text callback from
        // this setter. Cache BEFORE crossing that boundary to break reentry.
        lastAppliedPrimaryLanguage = desired
        primaryLanguage = desired
    }

    /// With several layouts, holding Space lists them, current first; a tap
    /// still types a space.
    private func makeLayoutActions(renderedMode: UUID) -> KeyboardVariantActions? {
        let choices = inputModeChoices
        guard choices.count > 1, !model.isSearching, !model.hasSymbolBoardOverlay,
              let current = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let space = makeInputAction(renderedMode: renderedMode, command: .space)
        let englishRevision = model.englishRevision
        let accepts: () -> Bool = { [weak self] in
            current() && self?.model.isSearching == false && self?.inputModeChoices == choices
        }
        return .init(isCurrent: accepts, insert: { [weak self] id in
            guard let self, accepts(), choices.contains(id) else { return false }
            if id == "conversion-choices" { self.expandConversion(); return true }
            if id == "english-undo" { self.undoEnglish(revision: englishRevision); return true }
            if id.hasPrefix("english-suggestion:") {
                let components = id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                guard components.count == 3 else { return false }
                self.chooseEnglish(String(components[2]), revision: englishRevision)
                return true
            }
            return self.finishConversionBeforeInputMode(.target(id))
        }, longPressOptions: choices, tap: space)
    }

    fileprivate var inputModeChoices: [String] {
        var ids = model.layouts.map(\.id)
        if !ids.contains(model.typingState.alphabet.id) { ids.insert(model.typingState.alphabet.id, at: 0) }
        ids += language.enabledModes.filter { $0 != .direct && $0 != .koreanRomaja }.map { "mode:" + $0.rawValue }
        let selected = language.mode == .direct ? model.typingState.alphabet.id : "mode:" + language.mode.rawValue
        ids.removeAll { $0 == selected }; ids.insert(selected, at: 0)
        if language.mode != .direct && model.compositionShelfHeight == 0 { ids.insert("conversion-choices", at: 0) }
        if englishSurfaceAvailable && model.compositionShelfHeight == 0 {
            if model.englishHasUndo { ids.insert("english-undo", at: 0) }
            if model.englishCanReplace {
                ids += model.englishSuggestions.enumerated().map { "english-suggestion:\($0.offset):\($0.element)" }
            }
        }
        return ids
    }

    fileprivate func switchToDirectTyping() {
        _ = finishConversionBeforeInputMode(.directTyping)
    }

    private func switchInputTarget(_ id: String) {
        invalidateEnglish()
        doubleSpaceState.reset(); expectedHostEdit = nil
        let previous = language.mode
        if id.hasPrefix("mode:"), let mode = LanguageInputMode(rawValue: String(id.dropFirst(5))),
           mode != .direct, mode != .koreanRomaja {
            guard language.select(mode) else { return }
            rememberChosenMode(mode, previous: previous)
            model.useConversionKeyboard()
        } else {
            // Another alphabet within Direct Typing stores nothing (see policy).
            if language.select(.direct) { rememberChosenMode(.direct, previous: previous) }
            _ = model.selectLayout(id)
        }
        compositionAnchor = nil
        applyPrimaryLanguage(); synchronizeHostTraits(); updateKeyboardHeight()
    }

    // MARK: Remembered language (shared with the app's Languages screen)

    /// A person's choice in the keyboard becomes the shared last-chosen mode.
    /// Only a real mode change is stored (an alphabet switch within Direct
    /// Typing never overwrites an app choice that's still pending). The read,
    /// compare and write run on a utility queue; an unchanged value isn't
    /// rewritten. Writing needs Full Access; without it, or on any failure, the
    /// choice isn't remembered, but this keyboard keeps it for the session.
    private func rememberChosenMode(_ mode: LanguageInputMode, previous: LanguageInputMode) {
        guard LanguageInputChoicePolicy.choiceShouldBeStored(mode, previous: previous) else { return }
        let canWrite = hasFullAccess
        pendingRememberedWrites += 1
        rememberedModeQueue.async {
            let store = LanguageInputLastMode.shared
            let storedBefore = store.load()
            let saved = storedBefore == mode || (canWrite && store.save(mode))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingRememberedWrites -= 1
                self.lastSeenRememberedMode = LanguageInputChoicePolicy.lastSeenAfterChoice(
                    mode, saved: saved, storedBefore: storedBefore, previous: self.lastSeenRememberedMode)
            }
        }
    }

    /// After every refresh (appearance or the app's notification): open in the
    /// last-chosen mode when it's offered, never over unfinished text or a
    /// conversion in progress. An unavailable mode leaves the stored value alone.
    private func languageDidRefresh() {
        languageRefreshedSinceAppear = true
        let decision = LanguageInputChoicePolicy.rememberedDecision(
            stored: LanguageInputLastMode.shared.load(), lastSeen: lastSeenRememberedMode,
            current: language.mode, choices: language.enabledModes,
            hasComposition: language.hasComposition,
            isBusy: language.isConverting || completingConversion || pendingConversionAction != nil
                || model.finishingConversion || model.expandedConversion || model.isSearching
                || pendingRememberedWrites > 0,
            hasTypedSinceAppear: typedSinceAppear, hasFullAccess: hasFullAccess)
        switch decision {
        case .adopt: lastSeenRememberedMode = language.mode
        case .switchTo(let mode): if restoreRememberedMode(mode) { lastSeenRememberedMode = mode }
        case .none, .wait: break
        }
        announceUnreadablePanelIfNeeded()
    }

    /// The space-bar path's local steps, without writing the value back.
    private func restoreRememberedMode(_ mode: LanguageInputMode) -> Bool {
        guard language.rawInput.isEmpty, !model.finishingConversion else { return false }
        invalidateEnglish()
        doubleSpaceState.reset(); expectedHostEdit = nil
        guard language.select(mode) else { return false }
        model.synchronizeLanguageKeyboard()
        compositionAnchor = nil
        applyPrimaryLanguage(); synchronizeHostTraits(); updateKeyboardHeight()
        return true
    }

    /// Why an offered language can't be read, by what this keyboard knows.
    /// Read while rendering, so it uses the published copy of Full Access:
    /// keys no longer re-render the whole keyboard, so a flip must publish.
    fileprivate func unreadableNotice(for mode: LanguageInputMode) -> LanguageUnreadableNotice? {
        let hasFullAccess = model.hasFullAccess
        return LanguageUnreadableNotice.state(for: mode, unavailable: language.unavailableModes[mode], hasFullAccess: hasFullAccess)
    }

    /// Non-nil while the recovery panel explains an unreadable selected language.
    fileprivate var unreadablePanelNotice: LanguageUnreadableNotice? {
        guard language.mode != .direct, !language.isLoading, language.status == .missingResources else { return nil }
        return unreadableNotice(for: language.mode)
    }

    /// The recovery panel is the visible content (same branch order as the view):
    /// not under Unicode/search/symbol pages, a finish/expanded panel, or a cover.
    private var unreadablePanelIsOnScreen: Bool {
        unreadablePanelNotice != nil && !model.showsUnicode && !model.isSearching
            && !model.finishingConversion && !model.expandedConversion
            && !model.hasKeyboardPanel && !model.hasSymbolBoardOverlay
    }

    /// Announce the panel's title once per keyboard opening, after the first
    /// refresh since appearing settles, and only while the panel is on screen.
    /// Later refreshes never repeat it. Focus is not moved.
    private func announceUnreadablePanelIfNeeded() {
        guard announcesUnreadablePanel, languageRefreshedSinceAppear, !language.isLoading else { return }
        guard let notice = unreadablePanelNotice else { announcesUnreadablePanel = false; return }
        guard unreadablePanelIsOnScreen else { return } // Still once, when it's first visible.
        announcesUnreadablePanel = false
        guard UIAccessibility.isVoiceOverRunning else { return }
        let mode = language.mode
        let title = notice.title(language: keyboardModeLabel(mode))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, self.language.mode == mode, self.unreadablePanelNotice == notice,
                  self.unreadablePanelIsOnScreen else { return }
            UIAccessibility.post(notification: .announcement, argument: title)
        }
    }

    private func makeFavoritesActions(renderedMode: UUID) -> KeyboardVariantActions? {
        guard !model.hasSymbolBoardOverlay, let guardCurrent = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let current: () -> Bool = { [weak self] in guardCurrent() && self?.model.hasSymbolBoardOverlay == false }
        return .init(isCurrent: current, insert: { [weak self] _ in
            guard let self, current() else { return false }
            self.doubleSpaceState.reset(); self.expectedHostEdit = nil
            self.model.closeDiacritics()
            return self.model.toggleFavorites()
        })
    }

    private func makeSymbolBoardActions(renderedMode: UUID, boardID: String, key: SymbolBoardKey) -> KeyboardVariantActions? {
        guard let current = makeBoardConfigurationGuard(renderedMode: renderedMode) else { return nil }
        let activeBoardID = SymbolBoardStore.shared.activeBoardID
        // Hold choices, then the key's own swipe-up and swipe-down choices.
        let choices = KeyboardVariantPolicy.options(text: key.text, variants: model.pageKeyVariants(key)) + (key.up ?? []) + (key.down ?? [])
        let accepts: () -> Bool = { [weak self] in
            guard let self else { return false }
            return current() && !self.model.isSearching && !self.model.hasSymbolBoardOverlay
                && self.model.inspection == nil && self.model.symbolBoardInspectionText == nil
                && SymbolBoardStore.shared.activeBoardID == activeBoardID
                && self.model.showsUnicode && activeBoardID == boardID
                && SymbolBoardStore.shared.key(boardID: boardID, keyID: key.id) == key
        }
        guard accepts() else { return nil }
        return .init(isCurrent: accepts, insert: { [weak self] text in
            guard let self, accepts(), KeyboardVariantPolicy.contains(text, in: choices) else { return false }
            self.doubleSpaceState.reset()
            return self.insertHostText(text, onInserted: { [weak self] in
                guard let self else { return }
                if text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first {
                    CharacterStore.shared.recordUse(scalar.value)
                } else if let emoji = self.model.emojiCatalog.entry(text: text) {
                    CharacterStore.shared.recordEmojiUse(emoji)
                }
                self.didEditHostText()
            })
        }, inspect: { [weak self] text in
            guard let self, accepts(), KeyboardVariantPolicy.contains(text, in: choices) else { return false }
            self.model.inspectText(text)
            return true
        }, swipeUp: key.up, swipeDown: key.down)
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
                return self.insertHostText(character.text, onInserted: { [weak self] in
                    CharacterStore.shared.recordUse(character.codePoint)
                    self?.didEditHostText()
                })
            case .emoji(let emoji):
                return self.insertHostText(emoji.text, onInserted: { [weak self] in
                    CharacterStore.shared.recordEmojiUse(emoji)
                    self?.didEditHostText()
                })
            }
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
        // Search focus scopes the lifetime of the press, not its destination.
        // The toolbar always targets the host; only the lower query key edits search.
        guard !isQuery || model.isSearching else { return { false } }
        let context = KeyboardDeleteContext(modeIdentifier: renderedMode, isQuery: model.isSearching, documentIdentifier: document)
        return context.guardedAction(currentContext: { [weak self] in
            guard let self, self.literalWriteToken == nil, !self.model.hasSymbolBoardOverlay,
                  !self.model.finishingConversion, !self.model.expandedConversion, self.deleteInteractionID == interactionID,
                  let document = self.currentDocumentIdentifier else { return nil }
            return KeyboardDeleteContext(modeIdentifier: self.model.inputModeID, isQuery: self.model.isSearching, documentIdentifier: document)
        }, delete: { [weak self] in
            self?.typedSinceAppear = true
            if isQuery { self?.invalidateEnglish(); self?.model.deleteQueryCharacter() }
            else {
                if let self, self.language.backspace() {
                    if self.language.rawInput.isEmpty { self.compositionAnchor = nil }
                    return
                }
                if let self, self.englishSurfaceAvailable, self.english.hasImmediateUndo {
                    // A dispatched rollback owns this Backspace even on partial
                    // failure: never follow it with an unrelated extra delete.
                    if let plan = self.english.planUndo(context: self.englishContext(), hostPermission: self.englishPermission) {
                        _ = self.executeEnglishPlan(plan)
                        self.didEditHostText()
                        return
                    }
                }
                self?.invalidateEnglish()
                self?.expectedHostEdit = nil
                self?.previewCursorDriver.keyboardWillEdit()
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
            guard let self, !self.model.finishingConversion, !self.model.expandedConversion else { return false }
            // Any other key, such as space or 123, also closes the Arabic Diacritics panel.
            switch command {
            case .diacritic, .diacritics: break
            default: self.model.closeDiacritics()
            }
            switch command {
            case .diacritic(let mark):
                guard !self.model.showsUnicode, self.model.typingState.layout == .letters else { return false }
                return self.insertDiacritic(mark)
            case .diacritics(let open):
                self.invalidateEnglish()
                guard open else { self.model.closeDiacritics(returningFocus: true); return true }
                guard !self.model.showsUnicode else { return false }
                return self.model.openDiacritics()
            case .query(let key):
                guard self.model.isSearching else { return false }
                self.doubleSpaceState.reset()
                self.model.appendQuery(key)
            case .queryHold(let key):
                // A held search key types its literal title into the host,
                // like a search result: a plain insert, no case or spacing
                // assistance, and the query stays as it is.
                guard self.model.isSearching, let text = KeyboardQueryHoldPolicy.hostText(forKey: key) else { return false }
                self.doubleSpaceState.reset()
                guard self.insertHostText(text) else { return false }
                self.didEditHostText()
            case .collapse:
                self.invalidateEnglish()
                self.dismissKeyboard()
            case .toolbar:
                self.invalidateEnglish()
                self.doubleSpaceState.reset()
                self.expectedHostEdit = nil
                self.model.toggleUnicodeToolbar()
            case .tab:
                guard !self.model.showsUnicode, self.model.typingState.layout == .letters,
                      (self.model.isPadLayout && self.model.typingWidePadVisible == true)
                        || self.model.arrangementHas(MainKeyboardArrangement.tab) else { return false }
                self.doubleSpaceState.reset()
                guard self.englishSurfaceAvailable ? self.insertOrdinaryEnglish("\t") : self.insertHostText("\t") else { return false }
                self.didEditHostText()
            case .capsLock:
                guard !self.model.showsUnicode, self.model.typingState.layout == .letters,
                      (self.model.isPadLayout && self.model.typingWidePadVisible == true)
                        || self.model.arrangementHas(MainKeyboardArrangement.caps) else { return false }
                self.doubleSpaceState.reset(); self.expectedHostEdit = nil
                self.invalidateEnglish()
                self.model.toggleCapsLock()
            case .space: self.spaceKey()
            case .returnKey: self.returnKey()
            case .shift:
                guard !self.model.showsUnicode else { return false }
                self.doubleSpaceState.reset()
                self.expectedHostEdit = nil
                self.invalidateEnglish()
                self.model.pressShift()
            case .layout(let layout):
                guard !self.model.showsUnicode else { return false }
                self.invalidateEnglish()
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
        if model.showsUnicode && !language.rawInput.isEmpty {
            // Search Space remains local above; browser Space reveals choices.
            expandConversion(); return
        }
        if confirmConversion(space: true) { return }
        var correctedSpace: (context: KeyboardCorrectionContext, guardValue: EnglishExecutionGuard)?
        if englishSurfaceAvailable && insertEnglishDelimiter(" ", onCorrection: { actual in
            if let bound = self.englishExecutionGuard() { correctedSpace = (actual, bound) }
        }) {
            didEditHostText()
            // didEditHostText resets punctuation state. Re-arm ONLY after a
            // fully confirmed correction, with the exact actual first Space;
            // a handled but partial/failed replacement never reaches this path.
            if let correctedSpace, english.hasImmediateUndo,
               englishExecutionGuard() == correctedSpace.guardValue,
               englishPermission == .permits,
               Self.sameEnglishObservation(correctedSpace.context, englishContext()),
               correctedSpace.context.selectedText == "",
               let before = correctedSpace.context.before, before.unicodeScalars.last == " ",
               let scope = correctedSpace.context.scope {
                _ = doubleSpaceState.spaceTap(before: String(before.dropLast()),
                    at: ProcessInfo.processInfo.systemUptime, scope: scope, enabled: true)
            }
            return
        }
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
            previewCursorDriver.keyboardWillEdit()
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
        if model.showsUnicode && !language.rawInput.isEmpty {
            if model.isSearching { model.endSearch() }
            else { expandConversion() }
            return
        }
        if !model.showsUnicode && confirmConversion() { return }
        if model.inspection != nil { model.closeInspection() }
        else if model.symbolBoardInspectionText != nil { model.closeSymbolBoardInspection() }
        else if model.isSearching { model.endSearch() }
        else {
            if !englishSurfaceAvailable || !insertEnglishDelimiter("\n") { insertHostText("\n") }
            didEditHostText()
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}


private func keyboardModeLabel(_ mode: LanguageInputMode) -> String {
    switch mode {
    case .direct: return "Direct Typing"
    case .japaneseRomaji: return "日本語"
    case .mandarinPinyin: return "拼音"
    case .koreanRomaja: return "Romaja"
    case .koreanTwoSetHangul: return "Two-Set Hangul"
    }
}

private func keyboardInputTargetLabel(_ id: String) -> String {
    if id == "english-undo" { return "Undo Correction" }
    if id.hasPrefix("english-suggestion:") {
        return id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).last.map(String.init) ?? "English Suggestion"
    }
    if id == "conversion-choices" { return "Conversion Choices" }
    if id.hasPrefix("mode:"), let mode = LanguageInputMode(rawValue: String(id.dropFirst(5))) { return keyboardModeLabel(mode) }
    return KeyboardAlphabet.alphabet(id: id)?.nativeName ?? id
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
    case query(String), queryHold(String), space, returnKey, shift, capsLock, tab, layout(KeyboardTypingLayout), toolbar, collapse
    /// Arabic Diacritics: insert one mark, or open (true) or close the panel.
    case diacritic(String), diacritics(Bool)
}

private enum KeyboardPanel { case typing, unicode }

@MainActor
private final class KeyboardTypingModel: ObservableObject {
    @Published private(set) var state = KeyboardTypingState()
    /// The Arabic Diacritics panel shows in place of the letter rows.
    @Published private(set) var showsDiacritics = false
    /// VoiceOver focus goes back to the Arabic Diacritics key after the panel
    /// closes from its own close key or a mark.
    private(set) var returnsFocusToDiacriticsKey = false
    func setDiacritics(_ shown: Bool, returningFocus: Bool = false) {
        guard shown != showsDiacritics else { return }
        returnsFocusToDiacriticsKey = !shown && returningFocus
        showsDiacritics = shown
    }
    /// Once: whether the redrawn Arabic Diacritics key should take VoiceOver focus.
    func takeFocusReturn() -> Bool {
        defer { returnsFocusToDiacriticsKey = false }
        return returnsFocusToDiacriticsKey && !showsDiacritics
    }
    func update(_ change: (inout KeyboardTypingState) -> Void) {
        var next = state
        change(&next)
        if next != state { state = next }
    }
}

@MainActor
private final class KeyboardModel: ObservableObject {
    let language = KeyboardLanguageCoordinator()
    @Published var englishSuggestions: [String] = []
    @Published var englishOriginal: String?
    @Published var englishCanReplace = false
    @Published var englishHasUndo = false
    @Published var englishStatus = ""
    @Published var englishRevision = UUID()
    @Published var compositionShelfHeight: CGFloat = 0
    @Published var expandedConversion = false
    @Published var finishingConversion = false
    @Published var queuedConversionPunctuation: String?

    @Published private(set) var panel: KeyboardPanel = .typing {
        didSet {
            if panel != oldValue { closeDiacritics(); invalidateInputMode() }
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
    @Published private(set) var mergesSymbols = false
    private var typingAvailableWidth: CGFloat = 0
    private var typingNormalKeyHeight = KeyboardTypingLayoutPolicy.regularKeyHeight

    private var isPhoneLayout = false
    var usesPhonePortraitGeometry: Bool {
        guard isPhoneLayout, !isCompactLayout, !showsUnicode else { return false }
        let alphabet = KeyboardAlphabet.alphabet(id: typingState.alphabet.id) ?? typingState.alphabet
        return typingPresentation.widthBasis.stockEquivalent(for: alphabet) != nil
    }

    func updateTypingLayoutContext(isPhone: Bool, isPad: Bool, compact: Bool) {
        let previous = typingPresentation
        let compactChanged = isCompactLayout != compact
        isPhoneLayout = isPhone
        if isPadLayout != isPad { isPadLayout = isPad }
        if compactChanged { isCompactLayout = compact }
        refreshMergedSymbols()
        // Revoke outgoing key gestures, not the language composition/candidates.
        if compactChanged || previous != typingPresentation { invalidateInputMode() }
    }

    func updateTypingGeometry(availableWidth: CGFloat, normalKeyHeight: CGFloat) {
        let changed = typingAvailableWidth != availableWidth || typingNormalKeyHeight != normalKeyHeight
        typingAvailableWidth = availableWidth
        typingNormalKeyHeight = normalKeyHeight
        refreshMergedSymbols()
        if changed { invalidateInputMode() }
    }

    private func refreshMergedSymbols() {
        let alphabet = KeyboardAlphabet.alphabet(id: typingState.alphabet.id) ?? typingState.alphabet
        let merged = language.mode != .koreanTwoSetHangul && typingPresentation.allowsMergedSymbols
            && KeyboardMergedSymbolsPolicy.isEligible(settings: keySettings, alphabet: alphabet,
            availableWidth: typingAvailableWidth, isPad: isPadLayout,
            isLandscape: isLandscapePadLayout, padLayout: padLayout, normalKeyHeight: typingNormalKeyHeight)
        guard merged != mergesSymbols else { return }
        mergesSymbols = merged
        let page = KeyboardMergedSymbolsPolicy.page(typingState.layout, merged: merged)
        if page != typingState.layout { typing.update { $0.selectLayout(page) } }
        // Retiring a page/geometry cancels presses, even if #+= keeps its identity.
        invalidateInputMode()
    }

    @Published var typingKeyHeight: CGFloat = KeyboardTypingLayoutPolicy.regularKeyHeight
    /// The portrait rows for this keyboard's width; used while `usesPhonePortraitGeometry`.
    @Published var phonePortraitRows = KeyboardPhonePortraitGeometry.Rows.large
    /// The host has kept the keyboard below its requested height, not just
    /// stepped through a shorter height while opening.
    @Published var hostLimitsHeight = false
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
            // The master switch: off pauses font rules without deleting them.
            UnicodeFontSupport.rulesEnabled = useUnicodeFonts
        }
    }
    /// The app's saved font rules, as compiled JSON. Re-read on appear and
    /// refresh only (never per keystroke), and decoded only when the file
    /// changed. The keyboard never parses TOML.
    private let fontRules = FontRuleSnapshotReader()
    @Published private(set) var showsCollapseKey: Bool
    @Published private(set) var showsTextPreview: Bool
    @Published private(set) var showsUCSUR: Bool
    @Published private(set) var prefersUCSUR: Bool
    /// The cursor's line, the drawn caret and whether the preview may move
    /// it, for the text preview row.
    @Published var previewCursor = KeyboardPreviewCursorDriver.State(
        line: KeyboardPreviewCursorLine(before: nil, after: nil), caret: 0, interactive: false, placementGeneration: 0)
    /// The open Copy Image panel: a frozen excerpt of the visible preview and
    /// its rendered picture. Nil when closed; never persisted or logged.
    @Published var previewImageExport: KeyboardPreviewImageExport?
    @Published var previewImageThumbnail: UIImage?
    /// The Copy Image colors; loaded from and saved to the keyboard's own
    /// defaults as a preset id and two colors.
    @Published var previewImageColors = KeyboardImageColorChoice.default
    /// The open Inspect Text panel: a frozen excerpt and its analysis.
    /// Nil when closed; never persisted or logged.
    @Published var textInspection: KeyboardTextInspection?
    /// Either full-keyboard panel is open.
    var hasKeyboardPanel: Bool { previewImageExport != nil || textInspection != nil }
    /// The app's Auto-Capitalization choice, read on appear and refresh only.
    private(set) var autoCapitalization: AutoCapitalizationMode = .followApp
    /// Emoji categories the app hides from the Emojis grid and emoji search;
    /// read on appear and when the app posts its change notification.
    @Published private(set) var hiddenEmojiGroups: Set<String> = []
    @Published private(set) var skinToneVariants: SkinToneVariants = .all
    /// Every category of this edition is hidden.
    var hidesAllEmoji: Bool { !emojiCatalog.groups.isEmpty && emojiCatalog.shownGroupCount(hiding: hiddenEmojiGroups) == 0 }
    /// At least one category of this edition is hidden.
    var filtersEmoji: Bool { emojiCatalog.shownGroupCount(hiding: hiddenEmojiGroups) < emojiCatalog.groups.count }
    @Published private(set) var symbolPagesToolbarVisible: Bool?
    var showsUnicodeToolbar: Bool { symbolPagesToolbarVisible ?? showsUnicode }
    @Published private(set) var results: [UnicodeCharacter] = []
    @Published private(set) var emojiResults: [UnicodeEmojiEntry] = []
    @Published private(set) var searchInProgress = false
#if DEBUG
    /// The last search's timing, for the search benchmark UI test only.
    @Published private(set) var searchTiming = ""
    private var searchSerial = 0
#endif
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
    /// The controller's Full Access, copied for rendering (unreadable notices).
    @Published var hasFullAccess = false
    @Published var isCompactLayout = false
    /// iPhone landscape search: compact rows, with the results in the search row.
    var usesCompactSearchLayout: Bool { isCompactLayout && !isPadLayout && isSearching }
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
    /// Only on the letters of a layout with diacritics, such as Arabic.
    func openDiacritics() -> Bool {
        guard !showsUnicode, typingState.layout == .letters, !typingState.alphabet.diacritics.isEmpty else { return false }
        typing.setDiacritics(true)
        return true
    }
    func closeDiacritics(returningFocus: Bool = false) { typing.setDiacritics(false, returningFocus: returningFocus) }
    static func layoutChoices(current: KeyboardAlphabet, layouts: [KeyboardAlphabet]) -> [String] {
        [current.id] + layouts.map(\.id).filter { $0 != current.id }
    }
    func selectTypingLayout(_ requested: KeyboardTypingLayout) {
        let layout = KeyboardMergedSymbolsPolicy.page(requested, merged: mergesSymbols)
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
        if showsUnicode { openTyping() } else { beginSearch() }
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

    /// Whether the app placed `key`, such as Tab, on this layout's keyboard.
    /// The current layout's main keyboard as it types: the saved
    /// arrangement, or the number row and the layout's own rows.
    var typingPresentation: KeyboardTypingPresentation {
        let alphabet = KeyboardAlphabet.alphabet(id: typingState.alphabet.id) ?? typingState.alphabet
        var saved = language.mode == .koreanTwoSetHangul ? MainKeyboardArrangement.letters(for: .english)
            : keySettings.effectiveArrangement(for: alphabet)
        // Saved rows equal to the stock ones type as the stock default in
        // phone portrait, so its rows render with Apple's geometry.
        if isPhoneLayout, !isCompactLayout, !showsUnicode, let stock = saved.stockEquivalent(for: alphabet) { saved = stock }
        return KeyboardTypingPresentation(arrangement: saved, mode: language.mode,
            isPhone: isPhoneLayout, isCompactLayout: isCompactLayout, isTyping: !showsUnicode)
    }
    var typingArrangement: MainKeyboardArrangement { typingPresentation.arrangement }
    func arrangementHas(_ key: String) -> Bool {
        keySettings.arrangement(for: typingState.alphabet.id)?.keys.contains(key) == true
    }
    /// With ConScript preferred, Private Use reads as the registry assigns it.
    var catalog: UnicodeCatalog {
        !showsUCSUR ? edition.catalog : prefersUCSUR ? edition.catalog.withConScript() : edition.catalog.withConScriptSearch()
    }
    /// A page key's hold choices: its own variants, then, for a character
    /// with both a text and an emoji form, the form the key does not type.
    func pageKeyVariants(_ key: SymbolBoardKey) -> [String] {
        let scalars = Array(key.text.unicodeScalars)
        guard let base = scalars.first, scalars.count == 1 || (scalars.count == 2 && [0xFE0E, 0xFE0F].contains(scalars[1].value)),
              let forms = catalog.character(at: base.value)?.presentationForms else { return key.variants }
        return key.variants + [forms.text, forms.emoji].filter { !$0.utf16.elementsEqual(key.text.utf16) }
    }
    var emojiCatalog: EmojiCatalog { edition.emojiCatalog }
    var editionValue: String { edition.rawValue + (catalog.usesConScript ? "+conscript" : showsUCSUR ? "+search" : "") }
    var hasSearchQuery: Bool {
        (section == .symbols || section == .emojis) && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var queryCaretUTF16Offset: Int { KeyboardQueryPolicy.utf16Offset(forCharacterOffset: queryCursor, in: query) }

    init() {
        let appSettings = UnicodeEditionSettings.shared.loadSnapshot()
        keySettings = KeyboardKeySettings.shared.loadSnapshot()
        edition = appSettings.edition
        useUnicodeFonts = appSettings.useUnicodeFonts
        showsTextPreview = appSettings.showsTextPreview
        showsUCSUR = appSettings.showsUCSUR
        prefersUCSUR = appSettings.prefersUCSUR
        UnicodeFontSupport.prefersConScript = appSettings.showsUCSUR && appSettings.prefersUCSUR
        showsCollapseKey = appSettings.showsCollapseKey
        selectedPadLayout = appSettings.padLayout
        adoptLayouts(appSettings.layouts, keepingCurrent: false)
        UnicodeFontSupport.rulesEnabled = appSettings.useUnicodeFonts
        fontRules.refresh()
        UnicodeFontSupport.ruleSet = FontRuleSet(rules: fontRules.rules)
        autoCapitalization = AutoCapitalizationSetting.shared.load()
        hiddenEmojiGroups = EmojiCategorySetting.shared.load()
        skinToneVariants = EmojiBrowsingSetting.shared.load()
    }

    /// Reloads the Emojis grid and emoji search when the app changed which
    /// categories they show.
    func refreshEmojiCategories() {
        let hidden = EmojiCategorySetting.shared.load()
        let variants = EmojiBrowsingSetting.shared.load()
        guard hidden != hiddenEmojiGroups || variants != skinToneVariants else { return }
        hiddenEmojiGroups = hidden
        skinToneVariants = variants
        refreshCatalog()
    }

    /// Keeps the current layout while it stays enabled, otherwise the one
    /// used last, otherwise the first.
    private func adoptLayouts(_ ids: [String], keepingCurrent: Bool) {
        // Each layout in the letter order the app arranged.
        let enabled = ids.compactMap(KeyboardAlphabet.alphabet(id:)).map { $0.arranged(keySettings.arrangement(for: $0.id)?.letterRows) }
        let next = enabled.isEmpty ? [KeyboardAlphabet.english] : enabled
        // Alphabets compare by id, so compare their rows too.
        if layouts != next || layouts.map(\.rows) != next.map(\.rows) { layouts = next }
        let remembered = defaults.string(forKey: Self.layoutDefaultsKey).flatMap { id in next.first { $0.id == id } }
        let current = keepingCurrent ? next.first { $0.id == typingState.alphabet.id } : nil
        if language.mode != .direct { useConversionKeyboard() }
        else { applyAlphabet(current ?? remembered ?? next[0]) }
    }
    /// The keyboard remembers the chosen layout in its own defaults, which
    /// needs no Full Access.
    @discardableResult func selectLayout(_ id: String) -> Bool {
        guard let alphabet = layouts.first(where: { $0.id == id }) else { return false }
        defaults.set(alphabet.id, forKey: Self.layoutDefaultsKey)
        applyAlphabet(alphabet)
        return true
    }
    private var usesConversionAlphabet = false
    private var renderedLanguageMode: LanguageInputMode = .direct
    func useConversionKeyboard() {
        usesConversionAlphabet = true
        applyAlphabet(language.mode == .koreanTwoSetHangul ? .english
            : KeyboardAlphabet.english.arranged(keySettings.arrangement(for: KeyboardAlphabet.english.id)?.letterRows))
        refreshMergedSymbols()
    }
    func synchronizeLanguageKeyboard() {
        if renderedLanguageMode != language.mode {
            renderedLanguageMode = language.mode
            invalidateInputMode() // Revoke presses even when both modes use English geometry.
            if language.mode == .koreanTwoSetHangul { typing.update { $0.selectLayout(.letters) } }
        }
        if language.mode != .direct { useConversionKeyboard() }
        else if usesConversionAlphabet {
            usesConversionAlphabet = false
            adoptLayouts(layouts.map(\.id), keepingCurrent: false)
        }
    }
    private func applyAlphabet(_ alphabet: KeyboardAlphabet) {
        // The same layout can come back rearranged.
        guard alphabet != typingState.alphabet || alphabet.rows != typingState.alphabet.rows else { return }
        closeDiacritics()
        typing.update { $0.selectAlphabet(alphabet) }
        refreshMergedSymbols()
        invalidateInputMode()
        presentationChanged?()
        alphabetChanged?()
    }

    func refreshEditionFromAppSettings() {
        if UnicodeFontSupport.refreshDownloadedFonts(force: true) { invalidateInputMode() }
        let selected = UnicodeEditionSettings.shared.loadSnapshot()
        if edition != selected.edition { edition = selected.edition }
        if useUnicodeFonts != selected.useUnicodeFonts { useUnicodeFonts = selected.useUnicodeFonts }
        refreshFontRules()
        // Applies to upcoming letters only; the caller re-synchronizes Shift.
        autoCapitalization = AutoCapitalizationSetting.shared.load()
        refreshEmojiCategories()
        if showsCollapseKey != selected.showsCollapseKey { showsCollapseKey = selected.showsCollapseKey }
        if selectedPadLayout != selected.padLayout { selectedPadLayout = selected.padLayout; invalidateInputMode(); presentationChanged?() }
        if layouts.map(\.id) != selected.layouts {
            adoptLayouts(selected.layouts, keepingCurrent: true)
            invalidateInputMode(); presentationChanged?()
        }
        if showsTextPreview != selected.showsTextPreview {
            showsTextPreview = selected.showsTextPreview
            invalidateInputMode(); presentationChanged?()
        }
        if showsUCSUR != selected.showsUCSUR || prefersUCSUR != selected.prefersUCSUR {
            showsUCSUR = selected.showsUCSUR; prefersUCSUR = selected.prefersUCSUR
            UnicodeFontSupport.prefersConScript = showsUCSUR && prefersUCSUR
            // Names, blocks and search follow both choices.
            invalidateInputMode(); refreshCatalog()
        }
        let keys = KeyboardKeySettings.shared.loadSnapshot()
        if keySettings != keys {
            let arranged = keySettings.arrangements != keys.arrangements
            keySettings = keys
            if arranged { adoptLayouts(layouts.map(\.id), keepingCurrent: true) }
            invalidateInputMode()
        }
        synchronizeLanguageKeyboard()
        refreshMergedSymbols()
    }

    /// Adopts rules the app saved since the last appear; decodes only when
    /// the rules file changed, and redraws only when the rules did.
    func refreshFontRules() {
        guard fontRules.refresh() else { return }
        UnicodeFontSupport.ruleSet = FontRuleSet(rules: fontRules.rules)
        invalidateInputMode()
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
        let activeCatalog = emojiCatalog, activeOrder = order, activeRevision = revision, hidden = hiddenEmojiGroups, variants = skinToneVariants
        let offset = discoveryEmojis.count, limit = pageSize
        emojiPageTask = Task { [weak self] in
            let more = await CatalogWorker.run {
                activeCatalog.entries(offset: offset, limit: limit, order: activeOrder, hiding: hidden, skinToneVariants: variants)
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
        let activeCatalog = catalog, activeEmojis = emojiCatalog, activeOrder = order, hidden = hiddenEmojiGroups, variants = skinToneVariants
        let activeRevision = revision, limit = pageSize
        discoveryTask = Task { [weak self] in
            let pages = await CatalogWorker.run {
                (activeCatalog.orderedCharacters(offset: 0, limit: limit, order: activeOrder),
                 activeEmojis.entries(offset: 0, limit: limit, order: activeOrder, hiding: hidden, skinToneVariants: variants))
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
        let activeCatalog = catalog, activeEmojis = emojiCatalog, activeOrder = order, hidden = hiddenEmojiGroups, variants = skinToneVariants
        let activeRevision = revision, searchEmojis = section == .emojis
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled else { return }
#if DEBUG
            let started = DispatchTime.now().uptimeNanoseconds
#endif
            let matches: ([UnicodeCharacter], [UnicodeEmojiEntry]) = await CatalogWorker.run {
                if searchEmojis { return ([], activeEmojis.search(searchQuery, limit: 120, order: activeOrder, hiding: hidden, skinToneVariants: variants)) }
                return (activeCatalog.search(searchQuery, limit: 120, order: activeOrder), [])
            }
#if DEBUG
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            let indexed = await CatalogWorker.run {
                !searchEmojis && UnicodeSearchIndexStore.shared.installedIndex(for: activeCatalog) != nil
            }
#endif
            guard !Task.isCancelled, let self, self.revision == activeRevision,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery,
                  (self.section == .emojis) == searchEmojis else { return }
            self.results = matches.0
            self.emojiResults = matches.1
            self.searchInProgress = false
#if DEBUG
            self.searchSerial += 1
            self.searchTiming = KeyboardSearchTiming.describe(serial: self.searchSerial, milliseconds: elapsed, indexed: indexed,
                                                              results: matches.0.count + matches.1.count)
#endif
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
    static let missingGlyphUI = tintedKey(.systemRed)
    /// A Private Use key the ConScript Unicode Registry assigns.
    static let ucsurUI = tintedKey(.systemBlue)
    private static func tintedKey(_ tint: UIColor) -> UIColor {
        UIColor { traits in
            let key = keyUI.resolvedColor(with: traits), tint = tint.resolvedColor(with: traits)
            var k: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), r = k
            key.getRed(&k.0, green: &k.1, blue: &k.2, alpha: &k.3)
            tint.getRed(&r.0, green: &r.1, blue: &r.2, alpha: &r.3)
            let amount: CGFloat = 0.18
            return UIColor(red: k.0 + (r.0 - k.0) * amount, green: k.1 + (r.1 - k.1) * amount,
                           blue: k.2 + (r.2 - k.2) * amount, alpha: 1)
        }
    }
    static let actionTextUI = UIColor.white
    static let accent = Color(uiColor: accentUI)
    static let background = Color(uiColor: backgroundUI)
    static let key = Color(uiColor: keyUI)
    static let ucsur = Color(uiColor: ucsurUI)
    /// The blue key for one ConScript character while ConScript is on.
    static func conscriptFill(_ text: String, shows: Bool) -> Color? {
        guard shows, text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first,
              UCSUR.block(containing: scalar.value) != nil else { return nil }
        return ucsur
    }
    static let separator = Color(uiColor: borderUI)
    static let secondary = Color.secondary
    static let action = Color(uiColor: actionUI)
    static let actionText = Color(uiColor: actionTextUI)
}

private extension View {
    func keyboardKeySurface(radius: CGFloat = 10, modifier: Bool = false, fill: Color? = nil) -> some View {
        self.modifier(KeyboardKeySurface(radius: radius, isModifier: modifier, fill: fill))
    }

    func keyboardControlSurface(radius: CGFloat = 12) -> some View {
        modifier(KeyboardControlSurface(radius: radius))
    }
}

private struct KeyboardKeySurface: ViewModifier {
    let radius: CGFloat
    var isModifier = false
    var fill: Color? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background(fill ?? (isModifier ? Color(uiColor: KeyboardPalette.modifierUI) : KeyboardPalette.key),
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
        if reduceTransparency && KeyboardViewController.needsOwnOpaqueBackdrop {
            KeyboardPalette.background
        } else {
            Color.clear
        }
    }
}

/// The preview-only checkerboard behind transparent areas. Never exported.
private struct KeyboardCheckerboard: View {
    let tones: (KeyboardImageRGB, KeyboardImageRGB)
    var square: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(cgColor: tones.0.cgColor)))
            var path = Path()
            let columns = Int((size.width / square).rounded(.up)), rows = Int((size.height / square).rounded(.up))
            for row in 0..<max(0, rows) {
                for column in 0..<max(0, columns) where (row + column) % 2 == 1 {
                    path.addRect(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square))
                }
            }
            context.fill(path, with: .color(Color(cgColor: tones.1.cgColor)))
        }
        .accessibilityHidden(true)
    }
}

/// The rendered picture in its chosen colors, over a checkerboard where it
/// is transparent. Changing colors cross-fades unless Reduce Motion is on.
private struct PreviewImageThumbnailPicture: View {
    let image: UIImage
    let colors: KeyboardImageColors
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ZStack {
                if colors.isTransparent { KeyboardCheckerboard(tones: colors.checkerboardTones) }
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            }
            .frame(width: size.width, height: size.height)
            .id(colors)
            .transition(reduceMotion ? .identity : .opacity)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: colors)
    }
}

/// Copy Image colors: the caption (or, in its place, any readability
/// caution), five preset chips and, for Custom, the Text and Background
/// swatch lines.
private struct PreviewImageColorsSection: View {
    let choice: KeyboardImageColorChoice
    let enabled: Bool
    let select: (KeyboardImageColorChoice) -> Void
    @Environment(\.displayScale) private var displayScale

    private var hairline: CGFloat { 1 / max(1, displayScale) }
    private var separator: Color { Color(uiColor: .separator) }
    static let customLinesID = "customLines"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                // A readability note takes the caption's place, so the footer
                // separator never clips it.
                if let note = KeyboardImageColorCopy.readabilityNote(choice.colors.readability) {
                    Label {
                        Text(verbatim: note)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("keyboard.previewImage.readability")
                } else {
                    Text(verbatim: KeyboardImageColorCopy.caption(choice))
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                // Five chips need 268 points, so this scrolls only for very large text.
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(KeyboardImageColorPreset.allCases) { chip($0) }
                    }
                    // 4pt clearance on every side inside the scroll content, so the
                    // selection ring outside each chip is never clipped by the row.
                    .padding(4)
                }
                .scrollIndicators(.hidden)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: KeyboardImageColorCopy.groupLabel))
            .accessibilityIdentifier("keyboard.previewImage.colors")
            if choice.preset == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    swatchLine(KeyboardImageColorCopy.textLine,
                               items: KeyboardImagePalette.colors.map { KeyboardImageBackground.color($0.rgb) },
                               selected: .color(choice.customText), identifier: "text") { background in
                        guard case .color(let rgb) = background else { return }
                        var next = choice
                        next.customText = rgb
                        select(next)
                    }
                    swatchLine(KeyboardImageColorCopy.backgroundLine, items: KeyboardImagePalette.backgrounds,
                               selected: choice.customBackground, identifier: "background") { background in
                        var next = choice
                        next.customBackground = background
                        select(next)
                    }
                }
                // Picking Custom scrolls the panel so both lines show.
                .id(Self.customLinesID)
            }
        }
        .disabled(!enabled)
    }

    private func chip(_ preset: KeyboardImageColorPreset) -> some View {
        let selected = choice.preset == preset
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            var next = choice
            next.preset = preset
            select(next)
        } label: {
            ZStack {
                if let colors = preset.fixedColors {
                    switch colors.background {
                    case .transparent: KeyboardCheckerboard(tones: colors.checkerboardTones)
                    case .color(let rgb): Color(cgColor: rgb.cgColor)
                    }
                    // Fixed size: the caption above carries the name.
                    Text(verbatim: "Aa").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(cgColor: colors.text.cgColor))
                } else {
                    Color(uiColor: .tertiarySystemFill)
                    Image(systemName: "paintpalette").font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(uiColor: .label))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(shape)
            .overlay(shape.strokeBorder(separator, lineWidth: hairline))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(KeyboardPalette.accent, lineWidth: 2)
                        .padding(-4)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel(Text(verbatim: preset.accessibilityLabel))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("keyboard.previewImage.colors.\(preset.rawValue)")
    }

    private func swatchLine(_ title: String, items: [KeyboardImageBackground], selected: KeyboardImageBackground,
                            identifier: String, pick: @escaping (KeyboardImageBackground) -> Void) -> some View {
        HStack(spacing: 0) {
            // A fixed leading column, so both lines' swatches start together.
            Text(verbatim: title).font(.footnote).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 84, alignment: .leading)
                .accessibilityHidden(true)
            PreviewImageSwatchScroller {
                HStack(spacing: 0) {
                    ForEach(items, id: \.storedValue) { item in
                        swatch(item, isSelected: item == selected, line: title, identifier: identifier) { pick(item) }
                    }
                }
                // Same 4pt ring clearance as the chip row: 52 points a line.
                .padding(4)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func swatch(_ item: KeyboardImageBackground, isSelected: Bool, line: String, identifier: String,
                        action: @escaping () -> Void) -> some View {
        let name = KeyboardImagePalette.name(of: item)
        return Button(action: action) {
            ZStack {
                switch item {
                case .transparent: KeyboardCheckerboard(tones: KeyboardImageColors.checkerboardTones(forText: .black), square: 7)
                case .color(let rgb): Color(cgColor: rgb.cgColor)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(separator, lineWidth: hairline))
            .overlay {
                if isSelected {
                    Circle().strokeBorder(KeyboardPalette.accent, lineWidth: 2).frame(width: 38, height: 38)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel(Text(verbatim: String(localized: "\(line), \(name)")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("keyboard.previewImage.\(identifier).\(item.storedValue)")
    }
}

/// Copy Image size: the size actually copied as a caption, then 1×, 2× and
/// 3× chips. The scale changes only the picture's pixels, never its layout.
private struct PreviewImageSizeSection: View {
    let choice: KeyboardImageColorChoice
    /// Nil when there is nothing to size; the caption then reads "Size".
    let size: KeyboardImagePixelSize?
    let enabled: Bool
    let select: (KeyboardImageColorChoice) -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hairline: CGFloat { 1 / max(1, displayScale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // One line at default sizes; wraps at large text sizes.
            Text(verbatim: KeyboardImageColorCopy.sizeCaption(size))
                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize > .large ? nil : 1).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize > .large)
                .accessibilityLabel(Text(verbatim: KeyboardImageColorCopy.sizeCaptionAccessibilityLabel(size)))
                .accessibilityIdentifier("keyboard.previewImage.size.caption")
            HStack(spacing: 12) {
                ForEach(KeyboardImageScale.allCases, id: \.self) { chip($0) }
            }
            // The same 4pt ring clearance as the color chips: a 52-point row.
            .padding(4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: KeyboardImageColorCopy.sizeGroupLabel))
            .accessibilityIdentifier("keyboard.previewImage.size")
        }
        .disabled(!enabled)
    }

    private func chip(_ scale: KeyboardImageScale) -> some View {
        let selected = choice.scale == scale
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            var next = choice
            next.scale = scale
            select(next)
        } label: {
            // Fixed size, like the color chips' "Aa".
            Text(verbatim: scale.label)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(uiColor: .label))
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .tertiarySystemFill), in: shape)
                .overlay(shape.strokeBorder(Color(uiColor: .separator), lineWidth: hairline))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(KeyboardPalette.accent, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(KeyboardPressStyle())
        .accessibilityLabel(Text(verbatim: KeyboardImageColorCopy.scaleLabel(scale)))
        .accessibilityValue(Text(verbatim: selected ? size.map { KeyboardImageColorCopy.pixelsValue($0) } ?? "" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("keyboard.previewImage.size.\(scale.rawValue)")
    }
}

/// A panel that covers the whole keyboard while it is open: a card inset
/// 4 points from every edge (on iPad at most 640 points wide, centred), a
/// pinned 44-point header with its title and Close, a body that always
/// scrolls, and a pinned footer for its action. Copy Image uses it, and an
/// Inspect panel can too. VoiceOver's escape gesture closes it.
private struct KeyboardPanelContainer<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    let closeIdentifier: String
    let isPad: Bool
    let close: () -> Void
    /// False hides the footer and its separator, for a panel's centered states.
    var showsFooter = true
    /// The body, given its scroll view so it can bring a part into view.
    @ViewBuilder let content: (ScrollViewProxy) -> Content
    /// The footer, given the keyboard's height to cap any notice.
    @ViewBuilder let footer: (CGFloat) -> Footer

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, isPad ? min(geometry.size.width - 8, 640) : geometry.size.width - 8)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyboardPressStyle())
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier(closeIdentifier)
                }
                .padding(.leading, 16).padding(.trailing, 4)
                .frame(height: 44)
                .layoutPriority(2)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        content(proxy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.automatic)
                    .scrollIndicatorsFlash(onAppear: true)
                    // No iOS 26 edge blur over the top of the body.
                    .keyboardUnmaskedScrollEdges()
                }
                .frame(maxHeight: .infinity)
                // The action is laid out before the body, so it never falls off.
                if showsFooter {
                    VStack(spacing: 0) {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5).accessibilityHidden(true)
                        footer(geometry.size.height)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                    }
                    .layoutPriority(1)
                }
            }
            .frame(width: width, height: max(0, geometry.size.height - 8))
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
            .accessibilityAction(.escape, close)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// A panel's one action: full width, exactly 44 points tall, radius 12.
private struct KeyboardPanelActionStyle: ButtonStyle {
    let prominent: Bool
    var radius: CGFloat = 12
    var font: Font = .system(size: 17, weight: .semibold)
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let fill: Color = !isEnabled ? Color(uiColor: .tertiarySystemFill)
            : prominent ? KeyboardPalette.action : KeyboardPalette.accent.opacity(0.15)
        let text: Color = !isEnabled ? .secondary : prominent ? KeyboardPalette.actionText : KeyboardPalette.accent
        return configuration.label
            .font(font)
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(fill, in: shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}

/// The preview row's trailing glyphs: plain light grey outlines with no
/// fill, border or accent. Pressed reads lighter, disabled lighter still;
/// Increase Contrast uses the label color at 75 %.
private struct PreviewRowIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let color: Color
        if !isEnabled { color = Color(uiColor: .quaternaryLabel) }
        else if configuration.isPressed { color = Color(uiColor: .tertiaryLabel) }
        else if contrast == .increased { color = Color(uiColor: .label).opacity(0.75) }
        else { color = Color(uiColor: .secondaryLabel) }
        return configuration.label.foregroundStyle(color)
    }
}

/// One open Inspect Text panel: the excerpt frozen as drawn, its analysis
/// and where copying is. Lives only while the panel is open.
struct KeyboardTextInspection: Equatable {
    let id = UUID()
    let excerpt: KeyboardPreviewExcerpt
    let state: TextInspectionState
    var copy: TextInspectionCopyState
}

/// Inspect Text (design/inspect/design.md §2–5) in the same full-keyboard
/// container as Copy Image: the frozen sample, the three counts, neutral
/// normalization chips, one card per grapheme cluster with its code points
/// in original order, then the normalization rows, the UTF-8/UTF-16 hex
/// and footnotes (copy-forms addendum: each form and encoding copies on its
/// own). Copy Text
/// and Copy Code Points are pinned below. Read-only: nothing here edits,
/// normalizes or keeps the inspected text.
private struct TextInspectionPanel: View {
    let panel: KeyboardTextInspection
    let isPad: Bool
    let close: () -> Void
    let copy: (TextInspectionCopyTarget) -> Void
    /// The one expanded code point row, by scalar offset.
    @State private var expanded: Int?
    @State private var showsTotalsHelp = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let normalizationID = "keyboard.inspect.normalization"

    var body: some View {
        KeyboardPanelContainer(title: "Inspect Text", identifier: "keyboard.inspect.panel",
                               closeIdentifier: "keyboard.inspect.close", isPad: isPad, close: close,
                               showsFooter: panel.state.inspection != nil) { proxy in
            if let inspection = panel.state.inspection {
                content(inspection, proxy: proxy)
            } else if let message = panel.state.message {
                stateMessage(message)
            }
        } footer: { height in
            footer(availableHeight: height)
        }
    }

    // MARK: States

    private func stateMessage(_ message: (symbol: String, title: String, text: String)) -> some View {
        VStack(spacing: 12) {
            Image(systemName: message.symbol).font(.system(size: 34)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message.title).font(.headline).multilineTextAlignment(.center)
                .accessibilityIdentifier("keyboard.inspect.stateTitle")
            Text(message.text).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close", action: close)
                .buttonStyle(KeyboardPanelActionStyle(prominent: false, radius: 10, font: .body.weight(.semibold)))
                .frame(width: 120)
                .accessibilityIdentifier("keyboard.inspect.stateClose")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: Body

    private func content(_ inspection: TextInspection, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sample(inspection)
            totals(inspection)
            chips(inspection, proxy: proxy)
            Text("Code Points").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(inspection.clusters) { cluster in clusterCard(cluster) }
            }
            normalizationSection(inspection).id(Self.normalizationID)
            encodingsSection(inspection)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(inspection.footnotes, id: \.self) { note in
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("keyboard.inspect.footnotes")
        }
    }

    /// Drawn like the preview row: per-character preview fonts, before,
    /// a 2-point accent caret, then after, in that order from the left.
    /// The preview's "…" marks show in secondary color; they aren't text.
    private func sample(_ inspection: TextInspection) -> some View {
        let excerpt = panel.excerpt
        // Isolates keep before|caret|after in that order while RTL runs
        // inside each part shape naturally.
        let text = Text("\(Text(verbatim: "\u{2066}"))\(sampleRun(excerpt.before, leadingMark: excerpt.beforeTruncated))\(Text(verbatim: "\u{2069}"))\(Text(verbatim: "\u{258F}").font(.system(size: 22, weight: .regular)).foregroundStyle(KeyboardPalette.accent))\(Text(verbatim: "\u{2066}"))\(sampleRun(excerpt.after, trailingMark: excerpt.afterTruncated))\(Text(verbatim: "\u{2069}"))")
        return text
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(10)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Text preview")
            .accessibilityValue(Text(verbatim: inspection.text))
            .accessibilityIdentifier("keyboard.inspect.sample")
    }

    private func sampleRun(_ text: String, leadingMark: Bool = false, trailingMark: Bool = false) -> Text {
        var result = AttributedString()
        var characters = Array(text)
        var lead = false, trail = false
        if leadingMark, characters.first == "…" { characters.removeFirst(); lead = true }
        if trailingMark, characters.last == "…" { characters.removeLast(); trail = true }
        func mark() -> AttributedString {
            var run = AttributedString(KeyboardTextPreviewLayout.ellipsis)
            run.font = .system(size: KeyboardTextPreviewLayout.fontSize)
            run.foregroundColor = Color(uiColor: .secondaryLabel)
            return run
        }
        if lead { result += mark() }
        for character in characters {
            var run = AttributedString(String(character))
            run.font = Font(KeyboardTextPreviewLayout.font(for: String(character)))
            result += run
        }
        if trail { result += mark() }
        return Text(result)
    }

    private func totals(_ inspection: TextInspection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Text(inspection.totals).font(.footnote.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("keyboard.inspect.totals")
                Button {
                    showsTotalsHelp.toggle()
                } label: {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(KeyboardPressStyle())
                .accessibilityLabel("About these counts")
                .accessibilityValue(showsTotalsHelp ? "expanded" : "collapsed")
                .accessibilityIdentifier("keyboard.inspect.totalsInfo")
            }
            .padding(.vertical, -8)
            if showsTotalsHelp {
                Text(TextInspectionWording.totalsHelp).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("keyboard.inspect.totalsHelp")
            }
        }
    }

    @ViewBuilder private func chips(_ inspection: TextInspection, proxy: ScrollViewProxy) -> some View {
        let chips = ForEach(inspection.normalization) { result in
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(Self.normalizationID, anchor: .top)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: result.form.rawValue).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                    Image(systemName: result.status.symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                // A 44-point target around the 32-point chip.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyboardPressStyle())
            .accessibilityLabel(Text(verbatim: result.accessibilityLabel))
            .accessibilityIdentifier("keyboard.inspect.chip.\(result.form.rawValue)")
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 0) { chips }
            } else {
                HStack(spacing: 8) { chips }
            }
        }
        .padding(.vertical, -6)
    }

    private func clusterCard(_ cluster: TextInspectionCluster) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            Text(verbatim: cluster.tileText)
                .font(Font(UnicodeFontSupport.font(for: cluster.tileText, size: 26, enabled: true)))
                .lineLimit(1).minimumScaleFactor(0.4)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Array(cluster.scalars.enumerated()), id: \.element.id) { index, scalar in
                    if index > 0 {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5).accessibilityHidden(true)
                    }
                    scalarRow(scalar)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: cluster.accessibilityLabel))
        .accessibilityIdentifier("keyboard.inspect.cluster.\(cluster.id)")
    }

    private func scalarRow(_ scalar: TextInspectionScalar) -> some View {
        let isOpen = expanded == scalar.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    expanded = isOpen ? nil : scalar.id
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Text(verbatim: scalar.label).font(.system(.footnote, design: .monospaced).weight(.semibold)).foregroundStyle(.primary)) \(Text(verbatim: scalar.name).font(.footnote).foregroundStyle(scalar.nameIsNote ? Color.secondary : Color.primary))")
                            .fixedSize(horizontal: false, vertical: true)
                        if !scalar.detail.isEmpty {
                            Text(verbatim: scalar.detail).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(.top, 3)
                }
                .padding(.vertical, 5)
                .frame(minHeight: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyboardPressStyle())
            .accessibilityLabel(Text(verbatim: scalar.accessibilityLabel))
            .accessibilityValue(Text(verbatim: scalar.accessibilityCategoryBlock + ", " + (isOpen ? "expanded" : "collapsed")))
            .accessibilityIdentifier("keyboard.inspect.codePoint.\(scalar.id)")
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(scalar.properties, id: \.identifier) { property in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(property.title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(verbatim: property.value)
                                .font(property.monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("keyboard.inspect.property.\(property.identifier)")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6).padding(.bottom, 8)
                .accessibilityIdentifier("keyboard.inspect.details.\(scalar.id)")
            }
        }
    }

    /// Each form: name and status, its description, then only the clusters
    /// it changes (design/inspect/copy-forms/design.md §1), with its own
    /// copy button on the trailing edge.
    private func normalizationSection(_ inspection: TextInspection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Normalization").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Text(TextInspectionWording.normalizationHelper).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(inspection.normalization.enumerated()), id: \.element.id) { index, result in
                    if index > 0 {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5).accessibilityHidden(true)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            titleLine(Text(verbatim: result.form.rawValue),
                                      detail: Text("\(Image(systemName: result.status.symbol)) \(result.status.title)"))
                            Text(result.form.summary).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !result.changes.isEmpty {
                                changeLines(result).padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: result.accessibilityRowLabel))
                        .accessibilityValue(Text(verbatim: result.accessibilityRowValue))
                        .accessibilityIdentifier("keyboard.inspect.normalization.\(result.form.rawValue)")
                        rowCopyButton(.form(result.form), enabled: result.canCopy,
                                      identifier: "keyboard.inspect.copy.\(result.form.rawValue)")
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    /// "NFD  = Already in this form" on one line; the status wraps under
    /// the name when they don't fit, and always at accessibility sizes.
    @ViewBuilder private func titleLine(_ name: Text, detail: Text) -> some View {
        let title = name.font(.body.weight(.semibold)).foregroundStyle(.primary)
        let secondary = detail.font(.footnote).foregroundStyle(.secondary)
        let stacked = VStack(alignment: .leading, spacing: 2) {
            title.fixedSize(horizontal: false, vertical: true)
            secondary.fixedSize(horizontal: false, vertical: true)
        }
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { title.fixedSize(); secondary.fixedSize() }
                stacked
            }
        }
    }

    /// "é  U+0065 U+0301 → U+00E9 ×3", at most four, then "+n more".
    private func changeLines(_ result: TextNormalizationResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(result.shownChanges) { change in
                Text("\(Text(verbatim: change.display).font(.caption2).foregroundStyle(.primary))  \(Text(verbatim: change.codePoints).font(.caption2.monospaced()))\(Text(verbatim: change.occurrences.map { " " + $0 } ?? ""))")
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let more = result.moreChanges {
                Text(more).font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("keyboard.inspect.changes.\(result.form.rawValue)")
    }

    /// UTF-8 bytes and UTF-16 code units of the same excerpt as hex
    /// (copy-forms §2), each collapsed to three lines with its own copy.
    private func encodingsSection(_ inspection: TextInspection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TextInspectionWording.encodingsSection).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(inspection.encodings.enumerated()), id: \.element.id) { index, encoding in
                    if index > 0 {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5).accessibilityHidden(true)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        TextInspectionEncodingValue(encoding: encoding) {
                            titleLine(Text(verbatim: encoding.form.rawValue), detail: Text(encoding.countLabel))
                        }
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        rowCopyButton(encoding.target, enabled: true,
                                      identifier: "keyboard.inspect.copy.\(encoding.form.rawValue)")
                            .accessibilityHint(Text(TextInspectionWording.copyHexHint))
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard.inspect.encodings")
    }

    /// A row's 44-point `doc.on.doc`, a checkmark for 1.5 s after a copy.
    private func rowCopyButton(_ target: TextInspectionCopyTarget, enabled: Bool, identifier: String) -> some View {
        let confirmed = panel.copy.confirmed == target
        return Button { copy(target) } label: {
            Image(systemName: confirmed ? "checkmark" : "doc.on.doc").font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(TextInspectionRowCopyStyle())
        .disabled(!enabled || !panel.copy.canCopy)
        .accessibilityLabel(confirmed ? TextInspectionWording.copied(target) : TextInspectionWording.copyLabel(target))
        .accessibilityIdentifier(identifier)
    }

    // MARK: Footer

    @ViewBuilder private func footer(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = panel.copy.noticeText {
                // A long notice at large sizes scrolls on its own, as in Copy Image.
                ViewThatFits(in: .vertical) {
                    noticeLabel(notice)
                    ScrollView(.vertical) { noticeLabel(notice) }
                }
                .modifier(PreviewImageHeightCap(cap: max(44, availableHeight * 0.3)))
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) { copyButton(.text); copyButton(.codePoints) }
                } else {
                    HStack(spacing: 8) { copyButton(.text); copyButton(.codePoints) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    private func noticeLabel(_ notice: (title: String?, body: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color(uiColor: .systemOrange))
            VStack(alignment: .leading, spacing: 2) {
                if let title = notice.title { Text(title).font(.footnote.weight(.semibold)) }
                Text(notice.body).font(.footnote)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboard.inspect.copyNotice")
    }

    private func copyButton(_ target: TextInspectionCopyTarget) -> some View {
        let confirmed = panel.copy.confirmed == target
        let title = confirmed ? TextInspectionWording.copied(target)
            : target == .text ? TextInspectionWording.copyText : TextInspectionWording.copyCodePoints
        let symbol = confirmed ? "checkmark" : target == .text ? "doc.on.doc" : "number"
        return Button { copy(target) } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(KeyboardPanelActionStyle(prominent: false, radius: 10, font: .subheadline.weight(.semibold)))
        .disabled(!panel.copy.canCopy)
        .accessibilityHint(target == .codePoints ? Text(TextInspectionWording.copyCodePointsHint) : Text(""))
        .accessibilityIdentifier(target == .text ? "keyboard.inspect.copyText" : "keyboard.inspect.copyCodePoints")
    }
}

/// One encoding's name, count and hex value (copy-forms §2): collapsed to
/// three lines of whole values ending " …", with Show All only when values
/// are left out. Each row expands on its own; nothing is remembered.
/// VoiceOver always reads the full value.
private struct TextInspectionEncodingValue<Title: View>: View {
    let encoding: TextEncodingResult
    @ViewBuilder let title: Title
    @State private var expanded = false
    /// The value's width and, in its font at the current text size, one
    /// monospaced column and the ellipsis, measured live.
    @State private var width: CGFloat = 0
    @State private var columnWidth: CGFloat = 0
    @State private var ellipsisWidth: CGFloat = 0

    private static var collapsedLines: Int { 3 }
    private static var probe: String { "0000000000" }

    /// Whole values that fit three lines at this width and text size; nil
    /// until measured. The cut is computed, never left to text truncation.
    private var collapsed: (hex: String, truncated: Bool)? {
        guard width > 0, columnWidth > 0 else { return nil }
        let columns = Int((width / columnWidth + 0.001).rounded(.down))
        let ellipsisColumns = max(1, Int((ellipsisWidth / columnWidth - 0.001).rounded(.up)))
        return encoding.collapsed(columns: columns, maxLines: Self.collapsedLines, trailerColumns: 1 + ellipsisColumns)
    }

    private var truncated: Bool { collapsed?.truncated ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                title
                value
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: encoding.accessibilityLabel))
            .accessibilityValue(Text(verbatim: encoding.hex))
            .accessibilityIdentifier("keyboard.inspect.encoding.\(encoding.form.rawValue)")
            if expanded || truncated {
                Button { expanded.toggle() } label: {
                    Text(expanded ? TextInspectionWording.showLess : TextInspectionWording.showAll)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KeyboardPalette.accent)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KeyboardPressStyle())
                // 32 points tall visually inside a 44-point target.
                .padding(.vertical, -6)
                .accessibilityLabel(expanded ? TextInspectionWording.showFewer(encoding.form) : TextInspectionWording.showAll(encoding.form))
                .accessibilityIdentifier("keyboard.inspect.showAll.\(encoding.form.rawValue)")
            }
        }
    }

    /// Uppercase hex, single spaces, wrapping only between values. Collapsed,
    /// it shows only whole values (`collapsed`); the line limit just holds
    /// the first layout before anything is measured.
    private var value: some View {
        let font = Font.system(.footnote, design: .monospaced)
        let shown = expanded ? encoding.hex : (collapsed?.hex ?? encoding.hex)
        return Text(verbatim: shown).font(font).foregroundStyle(.primary)
            .lineLimit(expanded ? nil : Self.collapsedLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // One column and the ellipsis in the same font and text size.
            .background(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Text(verbatim: Self.probe).font(font).fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                            columnWidth = $0 / CGFloat(Self.probe.count)
                        }
                    Text(verbatim: "…").font(font).fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ellipsisWidth = $0 }
                }
                .hidden()
                .accessibilityHidden(true)
            }
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// A form or encoding row's copy glyph: accent, `.tertiaryLabel` when disabled.
private struct TextInspectionRowCopyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? KeyboardPalette.accent : Color(uiColor: .tertiaryLabel))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// A line of swatches that scrolls sideways. While it overflows, its trailing
/// 20 points fade to clear so the cut-off swatch reads as more this way.
private struct PreviewImageSwatchScroller<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var contentWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
        .mask {
            if contentWidth > visibleWidth + 0.5 {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 20)
                }
            } else {
                Color.black
            }
        }
    }
}

/// Caps the height offered to its content without growing to the cap the way
/// `.frame(maxHeight:)` does: short content keeps its own height, taller content
/// is offered at most `cap` (so a `ViewThatFits` inside picks its scrolling form).
private struct PreviewImageHeightCap: ViewModifier {
    let cap: CGFloat

    func body(content: Content) -> some View {
        CapLayout(cap: cap) { content }
    }

    private struct CapLayout: Layout {
        let cap: CGFloat

        private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
            ProposedViewSize(width: proposal.width, height: min(proposal.height ?? cap, cap))
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let subview = subviews.first else { return .zero }
            let size = subview.sizeThatFits(capped(proposal))
            return CGSize(width: size.width, height: min(size.height, cap))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
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
    @Environment(\.displayScale) private var rowDisplayScale
    @ObservedObject var model: KeyboardModel
    @ObservedObject var language: KeyboardLanguageCoordinator
    @ObservedObject var store: CharacterStore
    @ObservedObject var symbolBoards = SymbolBoardStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Named keys fit the glyph, the code point and three lines of name.
    private var keyHeight: CGFloat { model.isCompactLayout ? 72 : model.isPadLayout ? 84 : 80 }
    private var headerHeight: CGFloat { model.usesPhonePortraitGeometry ? 42 : model.usesCompactSearchLayout ? KeyboardLayoutPolicy.compactSearchBarHeight : model.typingKeyHeight }
    /// The gap above the content and above the footer.
    private var contentGap: CGFloat { model.usesPhonePortraitGeometry ? 11 : model.usesCompactSearchLayout ? KeyboardLayoutPolicy.compactSearchRowSpacing : 4 }
    private var controlHeight: CGFloat { model.typingKeyHeight }
    private var showsCompositionShelf: Bool {
        !model.showsUnicode && !model.expandedConversion && !model.finishingConversion
            && (language.mode != .direct || LanguageInputSettings.englishAssistanceAvailable)
            && ((language.mode == .koreanTwoSetHangul && unreadableNotice == nil) || (!isConversionLoading && !needsConversionRecovery)) && model.compositionShelfHeight > 0
    }
    private var showsEnglishShelf: Bool { showsCompositionShelf && language.mode == .direct }
    // English owns the complete 44-point band. Keep baseline insets when absent,
    // and keep conversion/preview/footer/key metrics independent of this row.
    private var typingTopInset: CGFloat { model.usesPhonePortraitGeometry ? 4 : showsEnglishShelf ? 0 : 4 }
    private var typingContentTopGap: CGFloat { model.usesPhonePortraitGeometry ? model.phonePortraitRows.toolbarGap : showsEnglishShelf ? 0 : contentGap }
    private static let englishStatusInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 177.0 / 255, green: 177.0 / 255, blue: 186.0 / 255, alpha: 1) // #B1B1BA
            : UIColor(red: 84.0 / 255, green: 84.0 / 255, blue: 93.0 / 255, alpha: 1) // #54545D
    })

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.showsTextPreview && (!model.showsUnicode || model.isSearching) {
                    textPreviewRow.frame(height: headerHeight)
                    Color.clear.frame(height: 4).accessibilityHidden(true)
                }
                // Hidden native controls must leave the remote AX hierarchy.
                // The model restores the exact query and caret when shown.
                if model.usesPhonePortraitGeometry && !showsCompositionShelf && !model.showsUnicodeToolbar {
                    Color.clear.frame(height: 42).accessibilityHidden(true)
                }
                if model.showsUnicodeToolbar {
                    toolbar.frame(height: headerHeight)
                        .allowsHitTesting(!model.finishingConversion && !model.expandedConversion)
                        .accessibilityHidden(model.finishingConversion || model.expandedConversion)
                }
                if showsCompositionShelf {
                    if showsEnglishShelf { englishShelf }
                    else {
                        conversionShelf
                        Color.clear.frame(height: model.usesPhonePortraitGeometry ? 0 : 4).accessibilityHidden(true)
                    }
                }
                // English has no exterior gap; conversion and shelf-free typing
                // retain their existing content gap. The footer gap stays intact.
                Color.clear.frame(height: typingContentTopGap).accessibilityHidden(true)
                ZStack {
                    if model.finishingConversion {
                        finishConversionPanel
                    } else if model.expandedConversion {
                        expandedConversionPanel
                    } else if model.showsUnicode {
                        unicodeContent
                    } else if isConversionLoading && language.mode != .koreanTwoSetHangul {
                        // Unmount normal keys (including AX) until activation can retain input.
                        conversionLoadingPanel
                    } else if needsConversionRecovery && (language.mode != .koreanTwoSetHangul || unreadableNotice != nil) {
                        conversionRecoveryPanel
                    } else {
                        typingContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                Color.clear.frame(height: contentGap).accessibilityHidden(true)
                controls
                    .allowsHitTesting(!model.finishingConversion && !model.expandedConversion)
                    .accessibilityHidden(model.finishingConversion || model.expandedConversion)
            }
            .padding(.horizontal, 8)
            .padding(.top, typingTopInset)
            .padding(.bottom, model.usesPhonePortraitGeometry ? model.phonePortraitRows.bottomPadding : 6)
            // Hidden, not dimmed, under a panel that covers them.
            .opacity(model.hasKeyboardPanel ? 0 : 1)
            .allowsHitTesting(!model.hasSymbolBoardOverlay && !model.hasKeyboardPanel)
            .accessibilityHidden(model.hasSymbolBoardOverlay || model.hasKeyboardPanel)

        }
        .accessibilityElement(children: .contain)
        .background(KeyboardTray().ignoresSafeArea())
        .overlay {
            // Copy Image covers the keyboard's own bounds, inset 4 points.
            if let export = model.previewImageExport {
                previewImagePanel(export).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.previewImageExport?.id)
        .overlay {
            // Inspect Text shares the Copy Image container, height and scrolling.
            if let inspection = model.textInspection {
                TextInspectionPanel(panel: inspection, isPad: model.isPadLayout,
                                    close: { controller?.closeTextInspection() },
                                    copy: { controller?.copyTextInspection($0) })
                    .id(inspection.id)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.textInspection?.id)
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
            // In iPhone landscape search the field shrinks for the results.
            .frame(width: model.usesCompactSearchLayout ? 200 : nil)
            // Native query text must stay outside the glass compositor. A
            // quiet key surface keeps the label and caret fully legible.
            .keyboardKeySurface(radius: 12)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(model.isSearching ? KeyboardPalette.accent.opacity(0.55) : Color.clear, lineWidth: 1))

            if model.usesCompactSearchLayout {
                compactResultChips
                    .frame(maxWidth: .infinity).frame(height: headerHeight)
#if DEBUG
                    .overlay(alignment: .topLeading) { KeyboardSearchTimingProbe(timing: model.searchTiming) }
#endif
            }
            panelButton
            if model.showsUnicode { sectionMenu }
            // A single fixed trailing key in search, browsing and inspection.
            RepeatingDeleteKey(action: delete, isQuery: false, route: model.inputModeID,
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
            else { model.beginSearch() }
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

    private var conversionStatusText: String? {
        if language.isLoading { return "Loading language…" }
        switch language.status {
        case .ready: return nil
        case .missingResources: return "Download required. Open Uniboard to manage languages."
        case .unsupportedMode: return "This input mode isn’t available."
        case .unsupportedInput: return "No matching conversion. Keep typed text or cancel."
        case .failed: return "Conversion unavailable. Switch to Direct Typing or keep typed text."
        }
    }

    private var isConversionLoading: Bool {
        language.mode != .direct && language.isLoading
    }

    private var needsConversionRecovery: Bool {
        guard language.mode != .direct, !language.isLoading else { return false }
        switch language.status {
        case .missingResources, .unsupportedMode, .failed: return true
        case .ready, .unsupportedInput: return false
        }
    }

    private var conversionLoadingPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Loading language…")
                    .font(.headline)
                    .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Switch to Direct Typing") { controller?.switchToDirectTyping() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("keyboard.conversion.switchToDirect")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .keyboardUnmaskedScrollEdges()
        .accessibilityIdentifier("keyboard.conversion.loading")
    }

    /// An enabled language the keyboard can't read (LanguageUnreadableNotice).
    private var unreadableNotice: LanguageUnreadableNotice? {
        needsConversionRecovery ? controller?.unreadablePanelNotice : nil
    }

    private var conversionRecoveryPanel: some View {
        let token = language.state.token
        let unreadable = unreadableNotice
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let unreadable {
                    // Title, body, Switch, then unfinished-text controls (VoiceOver order).
                    Label(unreadable.title(language: keyboardModeLabel(language.mode)), systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("keyboard.conversion.unreadable.title")
                    Text(unreadable.body(language: keyboardModeLabel(language.mode)))
                        .font(.body)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keyboard.conversion.unreadable.body")
                } else {
                    Label(language.name, systemImage: "exclamationmark.triangle").font(.headline)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                    Text(conversionStatusText ?? "Conversion unavailable.")
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The unreadable panel replaces this general Full Access help.
                if language.status == .missingResources,
                   language.mode.conversionEngineABI != nil, unreadable == nil {
                    Text("Full Access required").font(.subheadline.weight(.semibold))
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                    Text("Allow Full Access to use downloaded languages. Direct Typing is still available.")
                        .font(.footnote)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The keyboard needs Full Access to read language files shared locally by Uniboard.")
                        .font(.footnote)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Switch to Direct Typing") { controller?.switchToDirectTyping() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("keyboard.conversion.switchToDirect")
                if !language.rawInput.isEmpty {
                    Text(language.preedit).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                    if language.mode.offersLiteralConversion {
                        Button("Keep Typed Text") { controller?.keepRomanLetters(token: token) }.frame(minHeight: 44)
                    }
                    Button("Cancel Conversion") { controller?.cancelConversion(token: token) }.frame(minHeight: 44)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var englishShelf: some View {
        let revision = model.englishRevision
        let suggestionsUnavailable = !model.englishSuggestions.isEmpty && !model.englishCanReplace
        let status = suggestionsUnavailable ? "Suggestions unavailable here." : model.englishStatus
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.englishHasUndo, let original = model.englishOriginal {
                    Button { controller?.undoEnglish(revision: revision) } label: {
                        Label("Undo “\(original)”", systemImage: "arrow.uturn.backward")
                            .lineLimit(1).padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 44, maxHeight: 44)
                            .foregroundStyle(Color(uiColor: .label))
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Undo correction, restore \(original)")
                    .accessibilityHint("Restores your spelling and removes the triggering delimiter.")
                    .accessibilityIdentifier("keyboard.english.undo")
                }
                if model.englishCanReplace {
                    HStack(spacing: 0) {
                        ForEach(model.englishSuggestions.indices, id: \.self) { index in
                            let suggestion = model.englishSuggestions[index]
                            if index > 0 { KeyboardCandidateDivider() }
                            Button { controller?.chooseEnglish(suggestion, revision: revision) } label: {
                                KeyboardCandidateText(output: suggestion)
                            }
                            .buttonStyle(KeyboardCandidateButtonStyle())
                            .disabled(!model.englishCanReplace)
                            .accessibilityLabel("English suggestion, \(suggestion)")
                            .accessibilityHint("Replace the word you just typed.")
                            .accessibilityIdentifier("keyboard.english.suggestion.\(index)")
                        }
                    }
                }
                if suggestionsUnavailable || (model.englishSuggestions.isEmpty && !model.englishHasUndo) {
                    Text(status).font(.footnote)
                        .foregroundStyle(Self.englishStatusInk)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .frame(height: 44)
                        .accessibilityIdentifier("keyboard.english.status")
                }
            }
        }
        .keyboardUnmaskedScrollEdges()
        .frame(height: 44)
        .accessibilityIdentifier("keyboard.english.shelf")
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("English Suggestions")
    }

    private var conversionShelf: some View {
        let token = language.state.token
        return KeyboardConversionShelf(mode: language.mode, rawInput: language.rawInput,
            preedit: language.preedit,
            candidates: language.state.visibleResult?.candidates ?? [], token: token,
            statusText: conversionStatusText, height: model.compositionShelfHeight,
            onChoose: { controller?.chooseConversion($0, token: $1) },
            onLiteral: { controller?.keepRomanLetters(token: token) },
            onExpand: { controller?.expandConversion() })
    }

    private var expandedConversionPanel: some View {
        let token = language.state.token
        return GeometryReader { geometry in
            KeyboardExpandedConversionView(mode: language.mode, rawInput: language.rawInput,
            preedit: language.preedit,
            candidates: language.state.visibleResult?.candidates ?? [], token: token,
            statusText: conversionStatusText, height: geometry.size.height,
            onChoose: { controller?.chooseConversion($0, token: $1) },
            onLiteral: { controller?.keepRomanLetters(token: token) },
            onClose: { controller?.closeConversionChoices() },
            onCancel: { controller?.cancelConversion(token: token) },
            queuedPunctuation: model.queuedConversionPunctuation)
        }
    }

    private var finishConversionPanel: some View {
        let token = language.state.token
        return KeyboardFinishConversionView(rawInput: language.mode == .koreanTwoSetHangul ? language.preedit : language.rawInput,
            confirmsComposedText: language.mode == .koreanTwoSetHangul,
            onKeepTypedText: { controller?.resolveConversionTransition(keepTypedText: true, token: token) },
            onCancelConversion: { controller?.resolveConversionTransition(keepTypedText: false, token: token) },
            onKeepEditing: { controller?.resolveConversionTransition(keepTypedText: nil, token: token) })
    }

    private var typingContent: some View {
        return KeyboardTypingView(typing: model.typing, mode: model.inputModeID, koreanTwoSet: language.mode == .koreanTwoSetHangul,
            presentation: model.typingPresentation,
            isPad: model.isPadLayout, isLandscape: model.isLandscapePadLayout, padLayout: model.padLayout, mergedSymbols: model.mergesSymbols, compact: model.isCompactLayout,
            enabled: !model.showsUnicode, useUnicodeFonts: model.useUnicodeFonts,
            preservesNormalKeySize: language.mode != .direct || (model.typingState.alphabet.id == KeyboardAlphabet.english.id
                && (language.preferences.effectiveEnglishSuggestions || language.preferences.effectiveEnglishAutocorrection)),
            hostLimitsHeight: model.hostLimitsHeight,
            delete: delete, variants: typingVariantActions,
            keySettings: model.keySettings, returnTitle: language.rawInput.isEmpty ? model.returnTitle : "Confirm", action: action, shiftSlide: shiftSlide)
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
                else if model.hidesAllEmoji { allEmojiHiddenState }
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
            let queryHeight = model.typingKeyHeight * 4 + 12
            VStack(spacing: 4) {
                if model.usesCompactSearchLayout {
                    // The results sit in the search row; the keys get the space.
                    queryKeys(rowHeight: model.typingKeyHeight, spacing: KeyboardLayoutPolicy.compactSearchRowSpacing)
                        .frame(width: width, height: height)
                } else {
                searchResultStrip
                    .frame(width: width, height: max(0, height - queryHeight - 4))
#if DEBUG
                    .overlay(alignment: .topLeading) { KeyboardSearchTimingProbe(timing: model.searchTiming) }
#endif
                queryKeys(rowHeight: model.typingKeyHeight)
                    .frame(width: width, height: queryHeight)
                }
            }
            .frame(width: width, height: height)
        }
        .clipped()
    }

    /// The host's text around the caret, each character in the font Uniboard
    /// would preview it with, so Private Use and unsupported characters show
    /// as this keyboard draws them. The row draws exactly the measured
    /// excerpt, so Copy Image can freeze what is visible and nothing more.
    private var textPreviewRow: some View {
        GeometryReader { geometry in
            let textWidth = max(0, geometry.size.width - KeyboardTextPreviewLayout.actionsButtonWidth)
            HStack(spacing: 0) {
                // One shaped line with an overlaid caret; taps and drags move
                // the app's cursor (design/preview-cursor).
                KeyboardPreviewCursorField(state: model.previewCursor, controller: controller)
                    .frame(width: textWidth, height: geometry.size.height)
                // Two plain grey outline glyphs inside the field (design §1a):
                // centres 30 points apart, each in its own full 44-point target.
                Button {
                    if let controller { controller.openTextInspection(excerpt: controller.currentPreviewExcerpt()) }
                } label: {
                    previewRowIcon("text.magnifyingglass", alignment: .trailing, height: geometry.size.height)
                }
                .buttonStyle(PreviewRowIconStyle())
                .disabled(model.previewImageExport != nil)
                .accessibilityLabel("Inspect preview text")
                .accessibilityIdentifier("keyboard.textPreview.inspect")
                Button {
                    if let controller {
                        controller.openPreviewImagePanel(excerpt: controller.currentPreviewExcerpt(), availableWidth: textWidth,
                                                         visibleHeight: geometry.size.height)
                    }
                } label: {
                    previewRowIcon("ellipsis.circle", alignment: .leading, height: geometry.size.height)
                }
                .buttonStyle(PreviewRowIconStyle())
                .disabled(model.textInspection != nil)
                .accessibilityLabel("Preview actions")
                .accessibilityIdentifier("keyboard.textPreview.actions")
            }
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KeyboardPalette.key.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Always before, caret, after from the left, the order Copy Image renders.
        .environment(\.layoutDirection, .leftToRight)
    }
    /// A 22-point glyph in a 44 × row-height target; the left glyph sits at
    /// the trailing edge of its target, the right one 8 points in from its
    /// leading edge.
    private func previewRowIcon(_ symbol: String, alignment: Alignment, height: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: 22, height: 22)
            .padding(.leading, alignment == .leading ? 8 : 0)
            .frame(width: KeyboardTextPreviewLayout.actionButtonWidth, height: max(44, height), alignment: alignment)
            .contentShape(Rectangle())
            .frame(height: height)
    }

    /// The Copy Image panel over the whole keyboard: the frozen picture, its
    /// colors and one explicit Copy Image action. Close is the way out.
    private func previewImagePanel(_ export: KeyboardPreviewImageExport) -> some View {
        KeyboardPanelContainer(title: "Text preview", identifier: "keyboard.previewImage.panel",
                               closeIdentifier: "keyboard.previewImage.close", isPad: model.isPadLayout,
                               close: { controller?.closePreviewImagePanel() }) { proxy in
            previewImagePanelBody(export)
                .onChange(of: model.previewImageColors.preset) { old, new in
                    // Only the change to Custom scrolls; later swatch taps never do.
                    guard new == .custom, old != .custom else { return }
                    DispatchQueue.main.async {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            proxy.scrollTo(PreviewImageColorsSection.customLinesID, anchor: .bottom)
                        }
                    }
                }
        } footer: { height in
            previewImagePanelFooter(export, availableHeight: height)
        }
    }

    private func previewImagePanelBody(_ export: KeyboardPreviewImageExport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            previewImageThumbnail(export)
                .accessibilitySortPriority(6)
            if export.image != nil {
                PreviewImageColorsSection(choice: model.previewImageColors, enabled: export.phase != .copying) {
                    controller?.selectPreviewImageColors($0)
                }
                .accessibilitySortPriority(5)
                // After Colors (and Custom's lines), before the explanation.
                PreviewImageSizeSection(choice: model.previewImageColors,
                                        size: export.pixelSize(for: model.previewImageColors.scale),
                                        enabled: export.phase != .copying) {
                    controller?.selectPreviewImageColors($0)
                }
                .accessibilitySortPriority(4)
            }
            Text(verbatim: previewImageExplanation(export))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(3)
        }
        .accessibilityElement(children: .contain)
    }

    /// The pinned bottom of the panel: any notice that belongs with the action,
    /// then the action itself (Copy Image, or OK when copying isn't possible).
    private func previewImagePanelFooter(_ export: KeyboardPreviewImageExport, availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = previewImageNotice(export.phase) {
                // A long notice at large text sizes scrolls on its own rather than
                // pushing the action off the keyboard or crowding out the picture.
                ViewThatFits(in: .vertical) {
                    previewImageNoticeLabel(notice)
                    ScrollView(.vertical) { previewImageNoticeLabel(notice) }
                }
                .modifier(PreviewImageHeightCap(cap: max(44, availableHeight * 0.35)))
                .accessibilitySortPriority(2)
            }
            previewImagePrimaryAction(export)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    private func previewImageNoticeLabel(_ notice: PreviewImageNotice) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.footnote.weight(.semibold))
                Text(notice.body).font(.footnote)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(notice.isError ? Color(uiColor: .systemRed) : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboard.previewImage.message")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The base explanation, then the color sentences that apply to this picture.
    private func previewImageExplanation(_ export: KeyboardPreviewImageExport) -> String {
        let base = String(localized: "Copies only the text shown here as a picture. Paste into apps that accept images. The text in the picture isn’t editable.")
        guard let image = export.image else { return base }
        return base + KeyboardImageColorCopy.explanationSuffix(colors: image.colors,
                                                               containsColorGlyphs: image.containsColorGlyphs)
    }

    @ViewBuilder private func previewImageThumbnail(_ export: KeyboardPreviewImageExport) -> some View {
        let neutral = Color(uiColor: .tertiarySystemFill)
        if let image = model.previewImageThumbnail, let rendered = export.image {
            // The thumbnail's own size (always the canvas drawn at 3×), not
            // the copy's pixels ÷ scale, which rounds differently at each
            // scale and would resample the same picture (size-choice §3).
            let size = image.size
            ScrollView(size.height > 96 ? [.horizontal, .vertical] : .horizontal) {
                PreviewImageThumbnailPicture(image: image, colors: rendered.colors, size: size)
                    .frame(minHeight: 48)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity)
            .frame(height: min(96, max(48, size.height)))
            .background(neutral, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Image preview of visible text")
            .accessibilityValue(rendered.accessibilityValue)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("keyboard.previewImage.thumbnail")
        } else if export.phase == .empty {
            Text("Show some text in the preview to copy an image.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(neutral, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("keyboard.previewImage.empty")
        }
    }

    private struct PreviewImageNotice { let title: LocalizedStringKey; let body: LocalizedStringKey; let isError: Bool }

    private func previewImageNotice(_ phase: KeyboardPreviewImageExport.Phase) -> PreviewImageNotice? {
        switch phase {
        case .renderFailed, .copyFailed:
            return PreviewImageNotice(title: "Couldn’t copy image", body: "Try again. Your text hasn’t changed.", isError: true)
        case .fullAccessRequired:
            return PreviewImageNotice(title: "Image copying unavailable",
                body: "To copy images, allow Full Access for Uniboard in your keyboard settings. You can still type without it.",
                isError: false)
        case .ready, .empty, .copying, .copied:
            return nil
        }
    }

    @ViewBuilder private func previewImagePrimaryAction(_ export: KeyboardPreviewImageExport) -> some View {
        switch export.phase {
        case .fullAccessRequired, .renderFailed:
            Button { controller?.closePreviewImagePanel() } label: {
                Text("OK")
            }
            .buttonStyle(KeyboardPanelActionStyle(prominent: false))
            .accessibilityIdentifier("keyboard.previewImage.ok")
        default:
            Button { controller?.copyPreviewImage() } label: {
                Group {
                    switch export.phase {
                    case .copying:
                        Label { Text("Creating image…") } icon: { ProgressView() }
                    case .copied:
                        Label("Image copied", systemImage: "checkmark")
                    case .copyFailed:
                        Label("Try Again", systemImage: "arrow.clockwise")
                    default:
                        Label("Copy Image", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .buttonStyle(KeyboardPanelActionStyle(prominent: true))
            .disabled(!export.canCopy)
            .accessibilityLabel(export.phase == .ready || export.phase == .empty
                ? Text("Copy preview as image") : Text(previewImageActionTitle(export.phase)))
            .accessibilityHint(export.phase == .ready ? Text("Copies only the text shown in this preview, not the whole document.") : Text(""))
            .accessibilityIdentifier("keyboard.previewImage.copy")
        }
    }

    private func previewImageActionTitle(_ phase: KeyboardPreviewImageExport.Phase) -> LocalizedStringKey {
        switch phase {
        case .copying: return "Creating image…"
        case .copied: return "Image copied"
        case .copyFailed: return "Try Again"
        default: return "Copy Image"
        }
    }

    @ViewBuilder private var searchResultStrip: some View {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(model.section == .emojis ? "Search emoji names or sequences" : "Search names, blocks or U+code points")
                .font(.system(size: 12)).foregroundStyle(KeyboardPalette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.searchInProgress {
            ProgressView("Searching…").font(.system(size: 12))
        } else if model.section == .emojis ? model.emojiResults.isEmpty : model.results.isEmpty {
            VStack(spacing: 2) {
                Text(model.section != .emojis ? "No results. Try a shorter name or code point."
                     : model.hidesAllEmoji ? "No emoji categories shown. Choose categories in the Uniboard app."
                     : model.filtersEmoji ? "No matching emoji in the categories shown" : "No results. Try a shorter name or code point.")
                if model.section == .emojis && !model.hidesAllEmoji && model.filtersEmoji {
                    Text("Try another search, or show more categories in the Uniboard app.")
                }
            }
            .font(.system(size: 12)).foregroundStyle(KeyboardPalette.secondary)
            .multilineTextAlignment(.center).padding(.horizontal, 12)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(model.section == .emojis ? model.emojiResults.map(KeyboardItem.emoji) : searchItems(model.results), id: \.keyIdentifier) { item in
                        InspectableCharacterKey(item: item, favorite: isFavorite(item), compact: true,
                            useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID, enabled: model.isSearching, showsName: true,
                            actionFactory: { [mode = model.inputModeID] in keyActions(mode, item) })
                            // The row is taller than a typing key, for the code point and name.
                            .frame(width: 64).frame(maxHeight: .infinity)
                            .keyboardKeySurface(radius: 7)
                    }
                }
            }
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
        }
    }

    /// iPhone landscape search: the results beside the field as 34-point
    /// chips, a 20-point glyph with its 11-point code point, scrolling sideways.
    @ViewBuilder private var compactResultChips: some View {
        let emoji = model.section == .emojis
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            compactSearchNote(emoji ? "Search emoji names or sequences" : "Search names, blocks or U+code points")
        } else if model.searchInProgress {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if emoji ? model.emojiResults.isEmpty : model.results.isEmpty {
            compactSearchNote(emoji && model.hidesAllEmoji ? "No emoji categories shown"
                              : emoji && model.filtersEmoji ? "No matching emoji in the categories shown" : "No results")
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(emoji ? model.emojiResults.map(KeyboardItem.emoji) : searchItems(model.results), id: \.keyIdentifier) { item in
                        InspectableCharacterKey(item: item, favorite: isFavorite(item), compact: true,
                            useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID, enabled: model.isSearching,
                            chip: true, actionFactory: { [mode = model.inputModeID] in keyActions(mode, item) })
                            .frame(width: min(124, 40 + 6.7 * CGFloat(item.footer.count)), height: headerHeight)
                            .keyboardKeySurface(radius: 7)
                    }
                }
            }
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
        }
    }
    private func compactSearchNote(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(KeyboardPalette.secondary)
            .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, alignment: .leading)
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
            if model.hidesAllEmoji { allEmojiHiddenState }
            else if model.emojiResults.isEmpty && model.filtersEmoji {
                emptyState(icon: "face.smiling", title: "No matching emoji in the categories shown",
                           detail: "Try another search, or show more categories in the Uniboard app.")
            }
            else if model.emojiResults.isEmpty { emptyState(icon: "face.smiling", title: "No emoji sequences found", detail: "Try a shorter name, a group, or a complete emoji.") }
            else { emojiGrid(model.emojiResults) }
        } else if model.results.isEmpty {
            emptyState(icon: "magnifyingglass", title: "No characters found", detail: "Try a shorter name or a code point such as U+2192.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(searchItems(model.results), id: \.keyIdentifier) { item in
                        InspectableCharacterKey(item: item, favorite: isFavorite(item), compact: model.isCompactLayout,
                            useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID, enabled: model.showsUnicode, showsName: true,
                            actionFactory: { [mode = model.inputModeID] in keyActions(mode, item) })
                            .frame(height: keyHeight)
                            .keyboardKeySurface(radius: 7)
                    }
                }.padding(.bottom, 2)
            }
            .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
        }
    }

    /// A searched character with both a text and an emoji form appears twice,
    /// as its exact text (VS15) and emoji (VS16) sequences, so either can be picked.
    private func searchItems(_ characters: [UnicodeCharacter]) -> [KeyboardItem] {
        characters.flatMap { character -> [KeyboardItem] in
            guard character.hasPresentationForms else { return [.character(character)] }
            return [0xFE0E, 0xFE0F].map { selector in
                .emoji(UnicodeEmojiEntry(id: String(format: "%04X-%04X", character.codePoint, selector),
                    codePoints: [character.codePoint, UInt32(selector)], name: character.name,
                    emojiVersion: character.age ?? "", unicodeVersion: character.age ?? "",
                    group: character.blockName, subgroup: character.blockName))
            }
        }
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
                // Pages are set up in the app; the keyboard only opens them.
                Menu {
                    ForEach(symbolBoards.boards) { board in
                        Button { _ = model.selectSymbolPage(.board(board.id)) } label: {
                            if selectedSymbolPage == .board(board.id) { Label(board.name, systemImage: "checkmark") } else { Text(board.name) }
                        }
                        .accessibilityIdentifier("keyboard.boards.page.\(board.id)")
                    }
                    Button { _ = model.selectSymbolPage(.recent) } label: {
                        if selectedSymbolPage == .recent { Label("Recent", systemImage: "checkmark") } else { Text("Recent") }
                    }
                    .accessibilityIdentifier("keyboard.boards.page.recent")
                } label: {
                    Image(systemName: "list.bullet").frame(width: 30, height: 28)
                }
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
            // The page's own rows and gaps, or rows of ten, with one key width throughout.
            let cells = savedPageCells(board)
            let spacing: CGFloat = model.isPadLayout ? 7 : 5
            GeometryReader { geometry in
                let width = SymbolPageLayout.keyWidth(for: cells, available: geometry.size.width, spacing: spacing)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(cells.indices, id: \.self) { row in
                            if let rows = board.explicitRows {
                                ExplicitKeyboardRow(alignment: rows[row].alignment, spacing: spacing, scale: rowDisplayScale) {
                                    ForEach(cells[row].indices, id: \.self) { column in
                                        savedBoardCell(cells[row][column], board: board, keyWidth: width, spacing: spacing)
                                    }
                                }.environment(\.layoutDirection, .leftToRight)
                            } else {
                                HStack(spacing: spacing) {
                                    ForEach(cells[row].indices, id: \.self) { column in
                                        savedBoardCell(cells[row][column], board: board, keyWidth: width, spacing: spacing)
                                    }
                                }
                            }
                        }
                    }.padding(.bottom, 2)
                }
                .scrollIndicators(.hidden).keyboardUnmaskedScrollEdges()
                .accessibilityIdentifier("keyboard.boards.keys")
            }
        }
    }
    private func savedPageCells(_ board: SymbolBoard) -> [[SymbolPageLayout.Cell]] {
        guard let rows = board.explicitRows else { return SymbolPageLayout.resolved(board.layout, keyCount: board.keys.count).cells(keyCount: board.keys.count) }
        var index = 0
        return rows.map { row in row.cells.map { cell in
            if cell.key != nil { defer { index += 1 }; return .key(index) }
            return cell == .halfGap ? .halfGap : .gap
        } }
    }
    @ViewBuilder private func savedBoardCell(_ cell: SymbolPageLayout.Cell, board: SymbolBoard, keyWidth: CGFloat, spacing: CGFloat) -> some View {
        if case .key(let index) = cell, board.keys.indices.contains(index) {
            let key = board.keys[index]
            KeyboardVariantKey(text: key.text, variants: model.pageKeyVariants(key),
                identifier: "keyboard.board.\(board.id).key.\(key.id)",
                label: symbolBoardKeyLabel(key.text), route: model.inputModeID,
                enabled: model.isShowingSymbolPages && model.showFavorites && symbolBoards.activeBoardID == board.id,
                fontSize: 23, useUnicodeFonts: model.useUnicodeFonts, swipeUp: key.up, swipeDown: key.down,
                showsInspection: true, showsEditing: true,
                factory: { [mode = model.inputModeID, boardID = board.id] in boardKeyActions(mode, boardID, key) })
                .frame(width: keyWidth, height: savedKeyHeight)
                .keyboardKeySurface(radius: 7, fill: KeyboardPalette.conscriptFill(key.text, shows: model.showsUCSUR))
                .accessibilityHidden(!model.isShowingSymbolPages || !model.showFavorites || symbolBoards.activeBoardID != board.id)
        } else {
            Color.clear.frame(width: SymbolPageLayout.gapWidth(cell, keyWidth: keyWidth, spacing: spacing), height: savedKeyHeight)
                .accessibilityHidden(true)
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
                        useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID,
                        enabled: model.isShowingSymbolPages && (legacy ? model.showFavorites && symbolBoards.activeBoardID == SymbolBoardStore.favoritesID : !model.showFavorites), glyphOnly: true,
                        actionFactory: { [mode = model.inputModeID] in keyActions(mode, .character(character)) })
                        .frame(maxWidth: .infinity).frame(height: savedKeyHeight)
                        .keyboardKeySurface(radius: 7)
                        .accessibilityHidden(!model.isShowingSymbolPages || (legacy ? !model.showFavorites || symbolBoards.activeBoardID != SymbolBoardStore.favoritesID : model.showFavorites))
                }
                ForEach(emojis) { emoji in
                    InspectableCharacterKey(item: .emoji(emoji), favorite: false, compact: true,
                        useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID,
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
                InspectableCharacterKey(item: .character(character), favorite: store.isFavorite(character.codePoint), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID, enabled: model.showsUnicode,
                    showsName: true, actionFactory: { [mode = model.inputModeID] in keyActions(mode, .character(character)) })
                    .frame(height: keyHeight)
                    .keyboardKeySurface(radius: 7)
                    .onAppear { if character.id == characters.last?.id { pagination?() } }
            }
        }
    }
    private func emojiTiles(_ emojis: [UnicodeEmojiEntry], pagination: (() -> Void)? = nil) -> some View {
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(emojis) { emoji in
                InspectableCharacterKey(item: .emoji(emoji), favorite: store.isFavoriteEmoji(emoji.id), compact: model.isCompactLayout, useUnicodeFonts: model.useUnicodeFonts, showsUCSUR: model.showsUCSUR, route: model.inputModeID, enabled: model.showsUnicode,
                    showsName: true, actionFactory: { [mode = model.inputModeID] in keyActions(mode, .emoji(emoji)) })
                    .frame(height: keyHeight)
                    .keyboardKeySurface(radius: 7)
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
        else if let emoji = model.emojiCatalog.entry(text: text) { inspectionPanel(.emoji(emoji)) }
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
            if let source = UnicodeFontSupport.sourceName(for: character.displayText, size: 36, enabled: model.useUnicodeFonts, anchor: character.fontRuleAnchor) {
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
            // ConScript on but not preferred: the registry's own data, beside Unicode's.
            if model.showsUCSUR, !model.prefersUCSUR, let block = UCSUR.block(containing: character.codePoint) {
                property("ConScript block", value: block.name, identifier: "ucsur")
                if let entry = UCSUR.entry(at: character.codePoint) {
                    property("ConScript name", value: entry.name, identifier: "ucsurName")
                    if let section = entry.section { property("ConScript section", value: section, identifier: "ucsurSection") }
                    if !entry.aliases.isEmpty { property("ConScript aliases", value: entry.aliases.joined(separator: "\n"), identifier: "ucsurAliases") }
                    property("ConScript category", value: "\(UnicodeCharacter.categoryName(entry.category)) (\(entry.category))",
                             identifier: "ucsurCategory")
                }
            }
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
            return Font(UnicodeFontSupport.font(for: character.displayText, size: size, enabled: model.useUnicodeFonts, anchor: character.fontRuleAnchor))
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

    /// Every emoji category is hidden in the app (no button: the keyboard can't open it).
    private var allEmojiHiddenState: some View {
        emptyState(icon: "line.3.horizontal.decrease.circle", title: "No emoji categories shown", detail: "Choose categories in the Uniboard app.")
            .accessibilityIdentifier("keyboard.emojisAllHidden")
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

    private func queryKeys(rowHeight: CGFloat, spacing: CGFloat = 4) -> some View {
        VStack(spacing: spacing) {
            let rows = KeyboardQueryHoldPolicy.rows
            searchKeyRow(rows[0], rowHeight: rowHeight)
            searchKeyRow(rows[1], rowHeight: rowHeight)
            searchKeyRow(rows[2], rowHeight: rowHeight, inset: 10)
            searchKeyRow(rows[3], rowHeight: rowHeight, includeDelete: true)
        }
    }
    private func searchKeyRow(_ keys: [String], rowHeight: CGFloat, inset: CGFloat = 0, includeDelete: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                KeyboardTouchKey(title: key, identifier: "keyboard.query.\(key)",
                    label: key == "+" ? "Plus" : key == ":" ? "Colon" : key == "-" ? "Hyphen" : key,
                    fontSize: 22,
                    route: model.inputModeID,
                    holdKey: key,
                    holdFactory: { [mode = model.inputModeID] in action(mode, .queryHold(key)) },
                    holdSpokenName: { [model] text in
                        text.unicodeScalars.count == 1 ? text.unicodeScalars.first.flatMap { model.catalog.character(at: $0.value)?.name } : nil
                    },
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

    private var usesPadFooter: Bool { usesPadKeyPositions && language.mode != .koreanTwoSetHangul }
    private var usesPadKeyPositions: Bool { model.isPadLayout && !model.showsUnicode && model.typingKeyHeight >= 44 }
    private var displaysCollapseKey: Bool { model.showsCollapseKey || usesPadFooter }
    /// Browsing Unicode (any section) shows its own Delete in the footer, so the
    /// footer plan must reserve that slot too, or Return is pushed off screen.
    private var showsPagesDelete: Bool {
        model.showsUnicode && !model.isSearching && model.inspection == nil && model.symbolBoardInspectionText == nil
    }

    private var controls: some View {
        GeometryReader { geometry in
            if let plan = KeyboardFooterLayoutPolicy.plan(availableWidth: geometry.size.width,
                hasGlobe: model.needsInputModeSwitchKey, showsCollapse: displaysCollapseKey,
                showsPage: !model.showsUnicode || showsPagesDelete, isPad: model.isPadLayout,
                showsReturn: language.mode == .koreanTwoSetHangul || !usesPadFooter && (model.showsUnicode || KeyboardTypingLayoutPolicy.padPlan(availableWidth: geometry.size.width,
                    isPad: model.isPadLayout, layout: model.typingState.layout, isLandscape: model.isLandscapePadLayout, padLayout: model.padLayout,
                    alphabet: model.typingState.alphabet) == nil),
                padTyping: usesPadFooter, phonePortrait: model.usesPhonePortraitGeometry,
                alphabet: model.typingState.alphabet) {
                footerControls(plan)
            }
        }
        .frame(height: controlHeight)
    }

    private func footerControls(_ plan: KeyboardFooterLayoutPolicy.Plan) -> some View {
        HStack(spacing: plan.spacing) {
            KeyboardTouchKey(title: "U", identifier: "keyboard.toggleUnicodeToolbar",
                label: model.showsUnicodeToolbar ? "Hide Unicode toolbar" : "Show Unicode toolbar",
                value: model.showsUnicodeToolbar ? "on" : "off", fontSize: 18,
                contentPosition: usesPadKeyPositions ? .bottomLeft : .center,
                route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .toolbar) })
                .frame(width: plan.keyWidth, height: controlHeight)
                // Like Shift: the darker modifier grey while the toolbar is
                // hidden, and an ordinary key while it shows. Never tinted.
                .keyboardKeySurface(modifier: !model.showsUnicodeToolbar)
                .environment(\.keyboardStockKeyInsets, model.usesPhonePortraitGeometry ? EdgeInsets(top: 5.5, leading: 8, bottom: model.phonePortraitRows.bottomPadding, trailing: 4) : EdgeInsets())
            if model.needsInputModeSwitchKey {
                InputModeSwitchKey(controller: controller, isModifier: model.isPadLayout && !model.showsUnicode,
                    contentPosition: usesPadKeyPositions ? .bottomLeft : .center)
                    .frame(width: plan.keyWidth, height: controlHeight)
            }
            if displaysCollapseKey && !usesPadFooter { footerCollapseKey(plan) }
            if !model.showsUnicode && !usesPadFooter { footerPageKey(plan) }
            if showsPagesDelete {
                RepeatingDeleteKey(action: delete, isQuery: false, route: model.inputModeID, identifier: "keyboard.pages.delete")
                    .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: true)
            }
            KeyboardVariantKey(text: "★", variants: [], identifier: "keyboard.openFavorites",
                label: model.isShowingSymbolPages ? "Back to English keyboard" : "Symbol keyboard",
                value: model.isShowingSymbolPages ? "favorites" : model.modeValue,
                symbol: model.isShowingSymbolPages ? "arrow.left" : "star", route: model.inputModeID,
                enabled: true, fontSize: 20,
                contentPosition: usesPadKeyPositions ? .bottomLeft : .center,
                factory: { [mode = model.inputModeID] in favoritesActions(mode) })
                .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: true)
            if (controller?.inputModeChoices.count ?? 0) > 1 && !model.isSearching {
                let alphabet = model.typingState.alphabet
                KeyboardVariantKey(text: language.mode == .direct ? alphabet.id : keyboardModeLabel(language.mode), variants: [], identifier: "keyboard.space", label: language.rawInput.isEmpty ? "Insert space" : model.compositionShelfHeight == 0 ? "Open Conversion Choices" : language.mode == .koreanTwoSetHangul ? "Confirm and insert space" : "Confirm Conversion",
                    value: language.mode == .direct ? alphabet.nativeName : language.name, route: model.inputModeID, fontSize: 14, foreground: .secondaryLabel,
                    hint: !language.rawInput.isEmpty
                        ? (model.compositionShelfHeight == 0 ? "Opens choices for your unfinished text without inserting it."
                            : language.mode == .koreanTwoSetHangul ? "Inserts the composed text followed by one space." : "Confirms the composed text.")
                        : LanguageInputSettings.englishAssistanceAvailable && model.englishHasUndo && model.compositionShelfHeight == 0
                        ? "Tap to insert a space. Hold for Undo Correction or keyboard choices."
                        : LanguageInputSettings.englishAssistanceAvailable
                            ? "Tap to insert a space. Hold for keyboard choices and available English suggestions."
                            : "Tap to insert a space. Hold for keyboard choices.",
                    longPressOptions: controller?.inputModeChoices ?? [],
                    secondaryText: language.mode == .koreanTwoSetHangul && model.compositionShelfHeight == 0 && language.hasComposition ? language.preedit : nil,
                    displayText: { keyboardInputTargetLabel($0) },
                    actionName: { id in
                        if id.hasPrefix("mode:"), let mode = LanguageInputMode(rawValue: String(id.dropFirst(5))) {
                            // A custom action has no value/hint: an unreadable
                            // language appends both ("Needs Full Access. Allow…").
                            if let notice = controller?.unreadableNotice(for: mode) {
                                return "Switch to \(KeyboardLanguageCoordinator.name(for: mode)), \(notice.accessibilityValue). \(notice.compact(language: keyboardModeLabel(mode)))"
                            }
                            return "Switch to \(KeyboardLanguageCoordinator.name(for: mode))"
                        }
                        return id == "english-undo" ? "Undo Correction" : id.hasPrefix("english-suggestion:")
                            ? "Use \(keyboardInputTargetLabel(id))" : "Switch to \(keyboardInputTargetLabel(id))"
                    },
                    optionInk: { id in
                        // Same label, quieter informative ink; still selectable.
                        guard id.hasPrefix("mode:"), let mode = LanguageInputMode(rawValue: String(id.dropFirst(5))),
                              controller?.unreadableNotice(for: mode) != nil else { return nil }
                        return KeyboardLanguageInformativeInk.secondaryUI
                    },
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
                KeyboardTouchKey(title: model.isSearching ? "Done" : inspecting ? "Back" : !language.rawInput.isEmpty ? "Confirm" : model.returnTitle,
                    identifier: "keyboard.return", label: model.isSearching ? "Close search keys" : inspecting ? "Close Unicode properties" : !language.rawInput.isEmpty ? "Confirm" : "\(model.returnTitle) key",
                    fontSize: 14, isAction: true, contentPosition: usesPadKeyPositions ? .bottomRight : .center, route: model.inputModeID,
                    accessibilityHint: !language.rawInput.isEmpty ? "Inserts the composed text without adding a line break or sending it." : nil,
                    factory: { [mode = model.inputModeID] in action(mode, .returnKey) })
                    .frame(width: plan.returnWidth, height: controlHeight)
                    .background(KeyboardPalette.action, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .environment(\.keyboardStockKeyInsets, model.usesPhonePortraitGeometry ? EdgeInsets(top: 5.5, leading: 4, bottom: model.phonePortraitRows.bottomPadding, trailing: 8) : EdgeInsets())
            }
        }
        .environment(\.keyboardStockKeyInsets, model.usesPhonePortraitGeometry ? EdgeInsets(top: 5.5, leading: 4, bottom: model.phonePortraitRows.bottomPadding, trailing: 4) : EdgeInsets())
    }
    private func footerCollapseKey(_ plan: KeyboardFooterLayoutPolicy.Plan) -> some View {
        KeyboardTouchKey(title: nil, symbol: "keyboard.chevron.compact.down",
            identifier: "keyboard.collapse", label: "Dismiss keyboard", fontSize: 17,
            contentPosition: usesPadKeyPositions ? .bottomRight : .center,
            route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .collapse) })
            .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: true)
    }
    private func footerPageKey(_ plan: KeyboardFooterLayoutPolicy.Plan) -> some View {
        let letters = model.typingState.layout != .letters
        return KeyboardTouchKey(title: letters ? model.typingState.alphabet.lettersKeyTitle : model.mergesSymbols ? "#+=" : "123",
            identifier: letters ? "keyboard.typing.letters" : "keyboard.typing.numbers",
            label: letters ? "Letters" : model.mergesSymbols ? "Symbols" : "Numbers", value: model.typingLayoutValue, fontSize: model.usesPhonePortraitGeometry && model.mergesSymbols && !letters ? 15 : 13,
            contentPosition: usesPadKeyPositions ? .bottomRight : .center,
            route: model.inputModeID, factory: { [mode = model.inputModeID] in action(mode, .layout(letters ? .letters : .numbers)) })
            .frame(width: plan.keyWidth, height: controlHeight).keyboardKeySurface(modifier: true)
    }

}

/// Only this small subtree observes transient Shift/capitalization changes.
/// The mounted Unicode browser is not rebuilt for each English character.
private struct KeyboardTypingRowsViewport<Content: View>: View {
    let scrolls: Bool
    var clipsTop = false
    @ViewBuilder var content: Content

    var body: some View {
        if scrolls {
            VStack(spacing: 2) {
                Text("App height limited — scroll for all keys")
                    .font(.caption2).foregroundStyle(KeyboardPalette.secondary)
                    .frame(maxWidth: .infinity)
                ScrollView(.vertical) { content }
                    .defaultScrollAnchor(.bottom)
                    .accessibilityHint("Scroll to reach all normal-size key rows.")
            }
        } else if clipsTop {
            // Full-size rows taller than the space: bottom-anchored, clipped.
            Color.clear.overlay(alignment: .bottom) { content }.clipped()
        } else {
            // Preserve the existing direct/fully-fitting keyboard hierarchy.
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct KeyboardTypingView: View {
    @ObservedObject var typing: KeyboardTypingModel
    let mode: UUID
    let koreanTwoSet: Bool
    let presentation: KeyboardTypingPresentation
    let isPad: Bool
    let isLandscape: Bool
    let padLayout: KeyboardPadLayout
    let mergedSymbols: Bool
    let compact: Bool
    let enabled: Bool
    let useUnicodeFonts: Bool
    let preservesNormalKeySize: Bool
    let hostLimitsHeight: Bool
    let delete: (UUID, Bool) -> RepeatingDeleteButton.DeleteAction
    let variants: (UUID, String, Bool, Bool, Bool, Bool) -> KeyboardVariantActions?
    let keySettings: KeyboardKeySettings.Snapshot
    let returnTitle: String
    let action: (UUID, KeyboardInputCommand) -> () -> Bool
    let shiftSlide: (UUID) -> ((String) -> Bool)?
    @Environment(\.displayScale) private var rowDisplayScale
    private var layoutValue: String {
        switch typing.state.layout { case .letters: return "letters"; case .numbers: return "numbers"; case .symbols: return "symbols" }
    }
    private var shiftValue: String {
        switch typing.state.shift { case .lowercase: return "lowercase"; case .uppercase: return "uppercase"; case .capsLock: return "capsLock" }
    }
    var body: some View {
        GeometryReader { geometry in
            let arrangement = arrangement
            let stockABC = KeyboardABCRendering(alphabet: catalogAlphabet, arrangement: presentation.widthBasis,
                availableWidth: geometry.size.width, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout)
            let phonePortrait = !isPad && !compact && !stockABC.arranged
            let portraitGeometry = phonePortrait ? KeyboardPhonePortraitGeometry(width: geometry.size.width + 16, alphabet: catalogAlphabet) : nil
            let explicitLetters = (koreanTwoSet || !arrangement.isLegacy) && typing.state.layout == .letters
            let arrangedKeyRows = arrangement.keyRows(widePad: isPad && geometry.size.width >= 650)
            let fullANSI = !explicitLetters && KeyboardTypingLayoutPolicy.usesANSI(availableWidth: geometry.size.width,
                isPad: isPad, isLandscape: isLandscape, padLayout: padLayout) && padLayout == .ansiNumbers
            let keyRows = fullANSI ? max(4, arrangedKeyRows) : arrangedKeyRows
            let spacing: CGFloat = phonePortrait ? 11 : isPad && geometry.size.width >= 650 ? 6 : 4
            let normalHeight = phonePortrait ? KeyboardPhonePortraitGeometry.Rows(width: geometry.size.width + 16).keyHeight : KeyboardTypingLayoutPolicy.typingKeyHeight(availableWidth: geometry.size.width, isPad: isPad)
            let minimumHeight = CGFloat(keyRows) * normalHeight + CGFloat(max(0, keyRows - 1)) * spacing
            // Phone portrait rows keep their size through a transient short
            // height: pinned to the bottom, the top rows cut off, no caption.
            let holdsRows = phonePortrait && !hostLimitsHeight && geometry.size.height < minimumHeight
            let scrolls = preservesNormalKeySize && geometry.size.height < minimumHeight && !holdsRows
            if let plan = KeyboardTypingLayoutPolicy.plan(availableHeight: preservesNormalKeySize || holdsRows ? max(geometry.size.height, minimumHeight) : geometry.size.height,
                availableWidth: geometry.size.width, compact: compact, layout: typing.state.layout,
                isPad: isPad, isLandscape: explicitLetters ? false : isLandscape, padLayout: explicitLetters ? .stock : padLayout,
                keyRows: arrangement.keyRows(widePad: isPad && geometry.size.width >= 650), mergedSymbols: mergedSymbols, phonePortrait: phonePortrait) {
                let ansiStyle = !explicitLetters && KeyboardTypingLayoutPolicy.usesANSI(availableWidth: geometry.size.width, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout)
                let pad = explicitLetters ? nil : KeyboardTypingLayoutPolicy.padPlan(availableWidth: geometry.size.width, isPad: isPad, layout: typing.state.layout, isLandscape: isLandscape, padLayout: padLayout,
                    alphabet: typing.state.alphabet)
                // Keep the original renderer as well as its width basis: a
                // custom number row can project to stock-looking letters, but
                // must not silently switch their key widths to stock rendering.
                let abc = KeyboardABCRendering(alphabet: catalogAlphabet, arrangement: presentation.widthBasis,
                    availableWidth: geometry.size.width, isPad: isPad, isLandscape: isLandscape, padLayout: padLayout)
                let arranged = typing.state.layout == .letters && abc.arranged
                // A caseless layout has no Shift: letters one width, rows centred.
                let caseless = typing.state.layout == .letters
                    ? KeyboardTypingLayoutPolicy.caselessKeyWidths(for: typing.state.alphabet, available: geometry.size.width, spacing: isPad ? 7 : 5) : nil
                KeyboardTypingRowsViewport(scrolls: scrolls, clipsTop: holdsRows) {
                VStack(spacing: plan.rowSpacing) {
                    if showsDiacriticsPanel {
                        // The panel takes the number row's and letter rows' place.
                        KeyboardDiacriticsPanel(marks: typing.state.alphabet.diacritics, isPad: isPad, route: mode, action: action)
                            .frame(height: plan.contentHeight)
                    } else {
                    if plan.auxiliaryRowCount > 0 && !arranged { auxiliaryRow(height: plan.keyHeight, ansiPad: ansiStyle, portrait: portraitGeometry) }
                    if let pad {
                        if pad.isANSI { ansiRows(pad, height: plan.keyHeight, hasAuxiliaryRow: plan.auxiliaryRowCount > 0) }
                        else { padRows(pad, height: plan.keyHeight, hasAuxiliaryRow: plan.auxiliaryRowCount > 0) }
                    } else if let portraitGeometry {
                        portraitRows(portraitGeometry, plan: plan)
                    } else if arranged {
                        arrangedRows(arrangement, width: geometry.size.width, height: plan.keyHeight, hasAuxiliaryRow: plan.auxiliaryRowCount > 0)
                    } else {
                        ForEach(Array(KeyboardTypingLayoutPolicy.rows(for: typing.state.layout, hasAuxiliaryRow: plan.auxiliaryRowCount > 0, ansiPad: ansiStyle, padLayout: padLayout,
                                alphabet: typing.state.alphabet, mergedSymbols: mergedSymbols).enumerated()), id: \.offset) { index, keys in
                            let punctuationWidth: CGFloat? = mergedSymbols && typing.state.layout == .symbols && index == 3
                                ? KeyboardMergedSymbolsPolicy.punctuationWidth(available: geometry.size.width,
                                    spacing: isPad ? 7 : 5, deleteWidth: isPad ? 64 : 42) : nil
                            HStack(spacing: isPad ? 7 : 5) {
                                if index == 2 && (typing.state.layout == .letters || !mergedSymbols) { typingLeadingKey(height: plan.keyHeight, width: caseless?.function, ansiPad: ansiStyle) }
                                ForEach(keys, id: \.self) { key in
                                    typingCharacterKey(key, hasAuxiliaryRow: plan.auxiliaryRowCount > 0,
                                        isAuxiliaryKey: false, ansiPad: ansiStyle, identifier: "keyboard.typing.key.\(key)", fontSize: compact ? 20 : 23)
                                        .frame(width: punctuationWidth ?? caseless?.letter).frame(maxWidth: caseless == nil && punctuationWidth == nil ? .infinity : nil).frame(height: plan.keyHeight)
                                        .keyboardKeySurface(radius: 7)
                                }
                                if index == (mergedSymbols && typing.state.layout == .symbols ? 3 : 2) {
                                    RepeatingDeleteKey(action: delete, isQuery: false, route: mode, identifier: "keyboard.typing.delete", padStyle: isPad)
                                        .frame(width: caseless?.function ?? (isPad ? 64 : 42), height: plan.keyHeight)
                                        .keyboardKeySurface(radius: 7, modifier: true)
                                    if !koreanTwoSet && KeyboardTypingLayoutPolicy.showsSymbolReturn(availableWidth: geometry.size.width, isPad: isPad) { padReturn(width: 112, height: plan.keyHeight) }
                                }
                            }
                            .padding(.horizontal, index == 1 && typing.state.layout == .letters && caseless == nil ? (isPad ? 24 : 12) : 0)
                        }
                    }
                    }
                }
                .frame(height: plan.contentHeight)
                .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .preference(key: KeyboardTypingAuxiliaryRowVisible.self, value: plan.auxiliaryRowCount > 0)
                .preference(key: KeyboardTypingWidePadVisible.self, value: pad != nil)
                .preference(key: KeyboardTypingANSIPadVisible.self, value: ansiStyle)
            }
        }
    }

    /// Positions are in keyboard coordinates; this subtree is inset 8 points.
    private func portraitRows(_ geometry: KeyboardPhonePortraitGeometry, plan: KeyboardTypingLayoutPlan) -> some View {
        let rows = KeyboardTypingLayoutPolicy.rows(for: typing.state.layout, hasAuxiliaryRow: plan.auxiliaryRowCount > 0,
            alphabet: typing.state.alphabet, mergedSymbols: mergedSymbols)
        return ForEach(Array(rows.enumerated()), id: \.offset) { index, keys in
            let last = index == rows.count - 1
            let letters = typing.state.layout == .letters
            let letterRow = geometry.lastLetterRow(letters: keys.count, alphabet: typing.state.alphabet)
            let punctuation = geometry.punctuationRow(count: keys.count, leadingKey: !mergedSymbols)
            let spans = last ? (letters ? letterRow.letters : punctuation.keys) : geometry.characterRow(count: keys.count)
            let leading = last ? (letters ? letterRow.leading : punctuation.leading) : nil
            let trailing = last ? (letters ? letterRow.trailing : punctuation.trailing) : nil
            let allSpans = ([leading].compactMap { $0 } + spans + [trailing].compactMap { $0 })
            ZStack(alignment: .topLeading) {
                if let leading {
                    typingLeadingKey(height: plan.keyHeight, width: leading.width)
                        .environment(\.keyboardStockKeyInsets, portraitInsets(leading, in: allSpans, width: geometry.width))
                        .offset(x: leading.x - 8)
                }
                ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                    typingCharacterKey(key, hasAuxiliaryRow: plan.auxiliaryRowCount > 0, isAuxiliaryKey: false,
                        identifier: "keyboard.typing.key.\(key)", fontSize: compact ? 20 : 23)
                        .frame(width: spans[i].width, height: plan.keyHeight).keyboardKeySurface(radius: 7)
                        .environment(\.keyboardStockKeyInsets, portraitInsets(spans[i], in: allSpans, width: geometry.width))
                        .offset(x: spans[i].x - 8)
                }
                if let trailing {
                    RepeatingDeleteKey(action: delete, isQuery: false, route: mode, identifier: "keyboard.typing.delete")
                        .frame(width: trailing.width, height: plan.keyHeight).keyboardKeySurface(radius: 7, modifier: true)
                        .environment(\.keyboardStockKeyInsets, portraitInsets(trailing, in: allSpans, width: geometry.width))
                        .offset(x: trailing.x - 8)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: plan.keyHeight)
        }
    }

    private func portraitInsets(_ span: KeyboardPhonePortraitGeometry.Span,
                                in spans: [KeyboardPhonePortraitGeometry.Span], width: CGFloat) -> EdgeInsets {
        let i = spans.firstIndex(of: span) ?? 0
        let left = i == 0 ? span.x : (span.x - spans[i - 1].maxX) / 2
        let right = i == spans.count - 1 ? width - span.maxX : (spans[i + 1].x - span.maxX) / 2
        return EdgeInsets(top: 5.5, leading: left, bottom: 5.5, trailing: right)
    }

    private var showsDiacriticsPanel: Bool {
        typing.showsDiacritics && typing.state.layout == .letters && !typing.state.alphabet.diacritics.isEmpty
    }

    private var catalogAlphabet: KeyboardAlphabet { KeyboardAlphabet.alphabet(id: typing.state.alphabet.id) ?? typing.state.alphabet }
    /// The layout's main keyboard as the app arranged it, or the standard one.
    private var arrangement: MainKeyboardArrangement { presentation.arrangement }

    /// Rows as the app arranged them: digits, letters, Shift, Delete and
    /// optional Tab and Caps Lock, with gaps, every key one width and each
    /// row centred.
    private func arrangedRows(_ arrangement: MainKeyboardArrangement, width: CGFloat, height: CGFloat, hasAuxiliaryRow: Bool) -> some View {
        let spacing: CGFloat = isPad ? 7 : 5
        let rows = arrangement.rows
        let keyWidth = MainKeyboardArrangement.keyWidth(for: presentation.widthBasis.rows, available: width, spacing: spacing)
        return ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            if let explicit = arrangement.explicitRows {
                ExplicitKeyboardRow(alignment: explicit[index].alignment, spacing: spacing, scale: rowDisplayScale) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        arrangedCell(cell, width: MainKeyboardArrangement.width(of: cell, keyWidth: keyWidth, spacing: spacing),
                                     height: height, hasAuxiliaryRow: hasAuxiliaryRow)
                    }
                }.environment(\.layoutDirection, .leftToRight)
            } else {
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        arrangedCell(cell, width: MainKeyboardArrangement.width(of: cell, keyWidth: keyWidth, spacing: spacing),
                                     height: height, hasAuxiliaryRow: hasAuxiliaryRow)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func arrangedCell(_ cell: MainKeyboardArrangement.Cell, width: CGFloat, height: CGFloat, hasAuxiliaryRow: Bool) -> some View {
        switch cell {
        case .halfGap, .gap:
            Color.clear.frame(width: width, height: height).accessibilityHidden(true)
        case .key(let key) where key == MainKeyboardArrangement.shift:
            typingLeadingKey(height: height, width: width)
        case .key(let key) where key == MainKeyboardArrangement.delete:
            RepeatingDeleteKey(action: delete, isQuery: false, route: mode, identifier: "keyboard.typing.delete", padStyle: isPad)
                .frame(width: width, height: height).keyboardKeySurface(radius: 7, modifier: true)
        case .key(let key) where key == MainKeyboardArrangement.tab:
            KeyboardTouchKey(title: nil, symbol: "arrow.right.to.line", identifier: "keyboard.typing.tab", label: "Tab", fontSize: 16,
                route: mode, factory: { [mode = mode] in action(mode, .tab) })
                .frame(width: width, height: height).keyboardKeySurface(radius: 7, modifier: true)
        case .key(let key) where key == MainKeyboardArrangement.caps:
            KeyboardTouchKey(title: nil, symbol: typing.state.shift == .capsLock ? "capslock.fill" : "capslock",
                identifier: "keyboard.typing.capsLock", label: "Caps Lock", value: typing.state.shift == .capsLock ? "on" : "off", fontSize: 16,
                route: mode, factory: { [mode = mode] in action(mode, .capsLock) })
                .frame(width: width, height: height).keyboardKeySurface(radius: 7, modifier: true)
        case .key(let key) where MainKeyboardArrangement.isDigit(key):
            // Digits type themselves, whatever Shift says, like the number row.
            typingCharacterKey(key, hasAuxiliaryRow: hasAuxiliaryRow, isAuxiliaryKey: true, ansiPad: false,
                identifier: "keyboard.typing.number.\(key)", fontSize: compact ? 18 : 20)
                .frame(width: width, height: height).keyboardKeySurface(radius: 7)
        case .key(let key):
            typingCharacterKey(key, hasAuxiliaryRow: hasAuxiliaryRow, isAuxiliaryKey: false, ansiPad: false,
                identifier: "keyboard.typing.key.\(key)", fontSize: compact ? 20 : 23)
                .frame(width: width, height: height).keyboardKeySurface(radius: 7)
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
                    if typing.state.alphabet.isCaseless { padGap(width: pad.capsWidth, height: height) } else {
                    KeyboardTouchKey(title: "caps lock", identifier: "keyboard.typing.capsLock", label: "Caps Lock",
                        value: typing.state.shift == .capsLock ? "on" : "off", fontSize: 12, contentPosition: .bottomLeft,
                        route: mode, factory: { [mode = mode] in action(mode, .capsLock) })
                        .frame(width: pad.capsWidth, height: height).keyboardKeySurface(radius: 7, modifier: true)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(typing.state.shift == .capsLock ? KeyboardPalette.accent : Color.clear, lineWidth: 1))
                    }
                } else if typing.state.alphabet.isCaseless {
                    if typing.state.alphabet.diacritics.isEmpty { padGap(width: pad.shiftWidth, height: height) }
                    else { diacriticsKey(width: pad.shiftWidth, height: height) }
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
                } else if typing.state.alphabet.isCaseless {
                    padGap(width: pad.shiftWidth, height: height)
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
            isAction: true, contentPosition: .bottomRight, route: mode, accessibilityHint: returnTitle == "Confirm" ? "Inserts the composed text without adding a line break or sending it." : nil, factory: { [mode = mode] in action(mode, .returnKey) })
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

    private func auxiliaryRow(height: CGFloat, ansiPad: Bool, portrait: KeyboardPhonePortraitGeometry? = nil) -> some View {
        HStack(spacing: portrait == nil ? (isPad ? 7 : 5) : 8) {
            ForEach(KeyboardTypingLayoutPolicy.auxiliaryRow(for: typing.state.layout, ansiPad: ansiPad), id: \.self) { key in
                typingCharacterKey(key, hasAuxiliaryRow: true, isAuxiliaryKey: true, ansiPad: ansiPad,
                    identifier: KeyboardTypingLayoutPolicy.numberRowOutput(for: key) != nil ? "keyboard.typing.number.\(key)" : "keyboard.typing.auxiliary.\(key)",
                    fontSize: compact ? 18 : 20)
                    .frame(width: portrait?.keyWidth).frame(maxWidth: portrait == nil ? .infinity : nil).frame(height: height)
                    .keyboardKeySurface(radius: 7)
                    .environment(\.keyboardStockKeyInsets, portrait == nil ? EdgeInsets() : EdgeInsets(top: 5.5, leading: key == "1" ? 8 : 4, bottom: 5.5, trailing: key == "0" ? 8 : 4))
            }
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private func typingCharacterKey(_ key: String, hasAuxiliaryRow: Bool, isAuxiliaryKey: Bool, widePad: Bool = false, ansiPad: Bool = false,
                                    identifier: String, fontSize: CGFloat) -> some View {
        if koreanTwoSet, typing.state.layout == .letters,
           let face = KoreanTwoSetKeyboard.label(for: KoreanTwoSetKeyboard.keyID(key, shifted: typing.state.shift != .lowercase)) {
            let shifted = KoreanTwoSetKeyboard.shiftedVariant(for: key).map { [$0] } ?? []
            KeyboardVariantKey(text: face, variants: shifted, identifier: identifier,
                label: KoreanTwoSetKeyboard.accessibleName(for: face), value: layoutValue,
                route: mode, enabled: enabled, fontSize: fontSize, useUnicodeFonts: false,
                preservesPressAcrossTextChanges: true, longPressOptions: shifted,
                actionName: { KoreanTwoSetKeyboard.accessibleName(for: $0) },
                factory: { [mode = mode] in variants(mode, key, false, false, false, false) })
        } else {
        let keyID = KeyboardKeySettings.identifier(forCharacter: key) ?? ""
        let original = isAuxiliaryKey ? key : KeyboardTypingLayoutPolicy.output(for: key, state: typing.state, hasAuxiliaryRow: hasAuxiliaryRow, widePad: widePad, ansiPad: ansiPad, padLayout: padLayout, mergedSymbols: mergedSymbols) ?? key
        let text = keySettings.tapOutput(for: keyID, defaultText: original,
            shifted: KeyboardTypingLayoutPolicy.usesShiftedTap(for: key, state: typing.state, ansiPad: ansiPad))
        let gestures = KeyboardVariantPolicy.gestureCandidates(for: key, original: original, state: typing.state, settings: keySettings)
        KeyboardVariantKey(text: text ?? original,
            variants: KeyboardVariantPolicy.holdVariants(for: key, state: typing.state),
            identifier: identifier, value: layoutValue, route: mode, enabled: enabled, fontSize: fontSize,
            foreground: text == nil ? .secondaryLabel : .label,
            hint: text == nil ? "Tap is off. Hold or swipe for configured choices." : nil,
            useUnicodeFonts: useUnicodeFonts,
            preservesPressAcrossTextChanges: true,
            longPressOptions: gestures.longPress, swipeUp: gestures.swipeUp, swipeDown: gestures.swipeDown,
            factory: { [mode = mode] in variants(mode, key, hasAuxiliaryRow, isAuxiliaryKey, widePad, ansiPad) })
        }
    }

    @ViewBuilder private func typingLeadingKey(height: CGFloat, width: CGFloat? = nil, ansiPad: Bool = false) -> some View {
        if typing.state.layout == .letters && typing.state.alphabet.isCaseless {
            // No Shift at all: Arabic holds its Diacritics key there, Hebrew nothing.
            if !typing.state.alphabet.diacritics.isEmpty { diacriticsKey(width: width ?? (isPad ? 64 : 42), height: height) }
        } else if typing.state.layout == .letters {
            KeyboardTouchKey(title: nil,
                symbol: typing.state.shift == .capsLock ? "capslock.fill" : typing.state.shift == .uppercase ? "shift.fill" : "shift",
                identifier: "keyboard.typing.shift", label: "Shift", value: shiftValue,
                route: mode, shiftSlideFactory: { [mode = mode] in shiftSlide(mode) },
            factory: { [mode = mode] in action(mode, .shift) })
                .frame(width: width ?? (isPad ? 64 : 42), height: height)
                .keyboardKeySurface(radius: 7, modifier: true)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(typing.state.shift == .lowercase ? Color.clear : KeyboardPalette.accent.opacity(0.65), lineWidth: 1))
        } else {
            let symbols = typing.state.layout == .numbers
            KeyboardTouchKey(title: KeyboardTypingLayoutPolicy.symbolSwitchTitle(to: symbols ? .symbols : .numbers,
                isPad: isPad, ansiPad: ansiPad, padLayout: padLayout),
                identifier: symbols ? "keyboard.typing.symbols" : "keyboard.typing.numbers",
                label: symbols ? "More symbols" : "Numbers", value: layoutValue, fontSize: !isPad && !compact && symbols ? 15 : 13,
                contentPosition: isPad && height >= 44 ? .bottomLeft : .center,
                route: mode, factory: { [mode = mode] in action(mode, .layout(symbols ? .symbols : .numbers)) })
                .frame(width: width ?? (isPad ? 64 : 42), height: height)
                .keyboardKeySurface(radius: 7, modifier: true)
        }
    }

    /// The Arabic Diacritics key in Shift's place: hold and slide for a mark;
    /// a tap or VoiceOver activation opens the panel.
    private func diacriticsKey(width: CGFloat, height: CGFloat) -> some View {
        let marks = typing.state.alphabet.diacritics
        return KeyboardVariantKey(text: "\u{064E}", variants: [], identifier: "keyboard.typing.diacritics",
            label: "Arabic Diacritics", route: mode, enabled: enabled, fontSize: compact ? 20 : 23,
            hint: "Choose a mark to add to the text.", longPressOptions: marks.map(\.mark),
            actionName: { mark in marks.first { $0.mark == mark }?.name ?? mark },
            primaryActionName: "Choose Arabic Diacritic",
            focusRequest: { [typing] in typing.takeFocusReturn() },
            factory: { [mode = mode] in variants(mode, MainKeyboardArrangement.shift, false, false, false, false) })
            .frame(width: width, height: height)
            .keyboardKeySurface(radius: 7, modifier: true)
    }

    /// An empty place where a caseless layout has no Caps Lock or Shift.
    private func padGap(width: CGFloat, height: CGFloat) -> some View {
        Color.clear.frame(width: width, height: height).accessibilityHidden(true)
    }

}

/// The Arabic Diacritics panel (design §7.4), in place of the number row
/// and letter rows: a titled header with a close key, then one tile per mark.
private struct KeyboardDiacriticsPanel: View {
    let marks: [KeyboardDiacritic]
    let isPad: Bool
    let route: UUID
    let action: (UUID, KeyboardInputCommand) -> () -> Bool
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let columns = isPad ? 8 : 4, gap: CGFloat = 6
            let rows = (marks.count + columns - 1) / columns
            let tileHeight = max(48, (geometry.size.height - 36 - gap * CGFloat(rows)) / CGFloat(max(rows, 1)))
            VStack(spacing: gap) {
                HStack {
                    Text("Arabic Diacritics")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    Spacer(minLength: 8)
                    KeyboardTouchKey(title: nil, symbol: "xmark", identifier: "keyboard.diacritics.close", label: "Close", fontSize: 15,
                        route: route, factory: { [route] in action(route, .diacritics(false)) })
                        .frame(width: 44, height: 32).keyboardKeySurface(radius: 7, modifier: true)
                }
                .frame(height: 36)
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(marks[(row * columns)..<min(marks.count, (row + 1) * columns)], id: \.mark) { mark in
                            tile(mark).frame(maxWidth: .infinity).frame(height: tileHeight)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            // VoiceOver starts on the title, after the panel is in place.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { titleFocused = true }
        }
    }

    private func tile(_ mark: KeyboardDiacritic) -> some View {
        // The dotted circle only pictures the mark; the key types the mark alone.
        KeyboardTouchKey(title: nil, identifier: "keyboard.diacritics.\(mark.name)", label: mark.name,
            route: route, largeContentTitle: "\u{25CC}\(mark.mark) \(mark.name)",
            factory: { [route] in action(route, .diacritic(mark.mark)) })
            .overlay {
                VStack(spacing: 2) {
                    Text("\u{25CC}" + mark.mark).font(.system(size: 28))
                    Text(mark.name).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 4)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .keyboardKeySurface(radius: 7)
    }
}

/// Single host actions bind their route when the finger goes down. SwiftUI
/// can update labels while a finger is held; that must not retarget the press.
/// The preview row's text area as the movable-cursor control.
private struct KeyboardPreviewCursorField: UIViewRepresentable {
    let state: KeyboardPreviewCursorDriver.State
    weak var controller: KeyboardViewController?

    func makeUIView(context: Context) -> KeyboardPreviewCursorControl {
        let control = KeyboardPreviewCursorControl()
        control.caretColor = KeyboardPalette.accentUI
        return control
    }

    func updateUIView(_ control: KeyboardPreviewCursorControl, context: Context) {
        controller?.attachPreviewCursor(control)
        control.configure(line: state.line, caret: state.caret, interactive: state.interactive,
                          placementGeneration: state.placementGeneration)
    }
}

extension KeyboardViewController: KeyboardPreviewCursorHost, KeyboardPreviewCursorControlDelegate {
    var previewContextBefore: String? { textDocumentProxy.documentContextBeforeInput }
    var previewContextAfter: String? { textDocumentProxy.documentContextAfterInput }
    var previewDocumentIdentifier: UUID? { currentDocumentIdentifier }
    var previewHasSelection: Bool { textDocumentProxy.selectedText?.isEmpty == false }
    var previewIsSecure: Bool { KeyboardHostInputTraits(reading: textDocumentProxy).isSecureTextEntry }
    var previewPanelOpen: Bool { model.hasKeyboardPanel }

    func previewAdjust(by offset: Int) {
        invalidateEnglish()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func previewAnnounce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func previewCursorShouldBeginTouch(_ control: KeyboardPreviewCursorControl, at time: TimeInterval) -> Bool {
        invalidateEnglish()
        return KeyboardPreviewCursorPolicy.acceptsTouch(at: time, lastKeyRelease: keyTouchObserver.lastRelease,
                                                 keysDown: keyTouchObserver.keysDown)
    }

    func previewCursor(_ control: KeyboardPreviewCursorControl, request offset: Int) {
        _ = finishConversionBefore { [weak self] in self?.previewCursorDriver.request(offset) }
    }

    func previewCursor(_ control: KeyboardPreviewCursorControl, step forward: Bool, announce: Bool) -> Bool {
        if !language.rawInput.isEmpty {
            return finishConversionBefore { [weak self] in _ = self?.previewCursorDriver.step(forward: forward, announce: announce) }
        }
        return previewCursorDriver.step(forward: forward, announce: announce)
    }

    func previewCursor(_ control: KeyboardPreviewCursorControl, lineEdge: KeyboardPreviewCursorSession.Goal) -> Bool {
        if !language.rawInput.isEmpty {
            return finishConversionBefore { [weak self] in _ = self?.previewCursorDriver.lineEdge(lineEdge) }
        }
        return previewCursorDriver.lineEdge(lineEdge)
    }

    func previewCursorDidEndTouch(_ control: KeyboardPreviewCursorControl) {
        previewCursorDriver.endTouch()
    }
}

private struct KeyboardTouchKey: View {
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
    /// A Unicode search character key: holding it types `holdKey` into the host.
    var holdKey: String? = nil
    var holdFactory: (() -> (() -> Bool))? = nil
    /// Names an invisible held character for its VoiceOver announcement.
    var holdSpokenName: ((String) -> String?)? = nil
    /// Shown by the Large Content Viewer at accessibility text sizes.
    var largeContentTitle: String? = nil
    var accessibilityHint: String? = nil
    let factory: () -> (() -> Bool)

    typealias Context = UIViewRepresentableContext<Native>
    var body: some View { Native(key: self).modifier(KeyboardNativeTouchExpansion()) }
    struct Native: UIViewRepresentable {
        let key: KeyboardTouchKey
        func makeUIView(context: Context) -> KeyboardTouchActionButton { key.makeUIView(context: context) }
        func updateUIView(_ view: KeyboardTouchActionButton, context: Context) {
            let inset = context.environment.keyboardStockKeyInsets
            view.keyboardVisualInsets = UIEdgeInsets(top: inset.top, left: inset.leading, bottom: inset.bottom, right: inset.trailing)
            key.updateUIView(view, context: context)
        }
    }

    func makeUIView(context: Context) -> KeyboardTouchActionButton {
        if holdFactory != nil { return KeyboardQueryHoldButton() }
        return shiftSlideFactory == nil ? KeyboardTouchActionButton() : KeyboardShiftTouchButton()
    }
    func updateUIView(_ view: KeyboardTouchActionButton, context: Context) {
        view.configure(contextIdentifier: route, actionFactory: factory)
        if let shift = view as? KeyboardShiftTouchButton, let shiftSlideFactory {
            shift.configureSlide(context: route, factory: shiftSlideFactory)
        }
        if let held = view as? KeyboardQueryHoldButton, let holdKey, let holdFactory {
            held.heldAccent = KeyboardPalette.accentUI
            held.spokenName = holdSpokenName ?? { _ in nil }
            held.configureHold(key: holdKey, factory: holdFactory)
        }
        view.setTitle(title, for: .normal)
        view.setImage(symbol.flatMap { UIImage(systemName: $0) }, for: .normal)
        view.contentPosition = contentPosition
        view.titleLabel?.font = .systemFont(ofSize: fontSize, weight: (isAction && contentPosition == .center) || (title == "#+=" && fontSize == 15) ? .semibold : .regular)
        view.titleLabel?.adjustsFontSizeToFitWidth = true
        view.titleLabel?.minimumScaleFactor = 0.7
        let foreground = isAction ? KeyboardPalette.actionTextUI : tinted ? KeyboardPalette.accentUI : secondary ? UIColor.secondaryLabel : UIColor.label
        view.setTitleColor(foreground, for: .normal)
        view.tintColor = foreground
        view.accessibilityHint = accessibilityHint
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = label ?? title
        view.accessibilityValue = value
        if let largeContentTitle {
            view.showsLargeContentViewer = true
            view.largeContentTitle = largeContentTitle
            if !view.interactions.contains(where: { $0 is UILargeContentViewerInteraction }) {
                view.addInteraction(UILargeContentViewerInteraction())
            }
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
    let showsUCSUR: Bool
    let route: UUID
    let enabled: Bool
    var glyphOnly = false
    /// A result key: the page keys' rounded surface, with the name in small text below the glyph.
    var showsName = false
    /// A landscape search chip: a small glyph with its code point beside it.
    var chip = false
    var identifier: String? = nil
    let actionFactory: KeyboardInspectableInteraction.ActionFactory

    func makeUIView(context: Context) -> InspectableKeyButton { InspectableKeyButton() }
    func updateUIView(_ uiView: InspectableKeyButton, context: Context) {
        uiView.configure(item: item, favorite: favorite, compact: compact, useUnicodeFonts: useUnicodeFonts, showsUCSUR: showsUCSUR, glyphOnly: glyphOnly || showsName || chip,
            showsName: showsName, chip: chip, route: route, enabled: enabled, actionFactory: actionFactory)
        uiView.accessibilityIdentifier = identifier ?? item.keyIdentifier
    }
}

private final class InspectableKeyButton: UIControl {
    private let glyph = UILabel()
    private let code = UILabel()
    private let name = UILabel()
    private var stackCenter: NSLayoutConstraint!
    private var labelStack: UIStackView!
    private var chipGlyphWidth: NSLayoutConstraint!
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
        // The name wraps anywhere, up to three lines, below the glyph and code point.
        name.font = .systemFont(ofSize: 7, weight: .medium)
        name.textColor = .secondaryLabel
        name.textAlignment = .center
        name.numberOfLines = 3
        name.lineBreakMode = .byCharWrapping
        name.isUserInteractionEnabled = false
        let stack = UIStackView(arrangedSubviews: [glyph, code, name])
        labelStack = stack
        chipGlyphWidth = glyph.widthAnchor.constraint(equalToConstant: 24)
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
        stackCenter = stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        codeHeight = code.heightAnchor.constraint(equalToConstant: 11)
        addSubview(star)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackCenter, glyphHeight,
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
    func configure(item: KeyboardItem, favorite: Bool, compact: Bool, useUnicodeFonts: Bool, showsUCSUR: Bool, glyphOnly: Bool, showsName: Bool = false,
                   chip: Bool = false, route: UUID, enabled: Bool, actionFactory: @escaping KeyboardInspectableInteraction.ActionFactory) {
        // A chip lays the glyph and its code point side by side.
        labelStack.axis = chip ? .horizontal : .vertical
        labelStack.alignment = chip ? .center : .fill
        labelStack.spacing = chip ? 4 : 2
        chipGlyphWidth.isActive = chip
        code.font = .monospacedSystemFont(ofSize: chip ? 11 : 9, weight: .medium)
        code.textAlignment = chip ? .left : .center
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
        glyphHeight.constant = chip ? 24 : compact ? 26 : 34
        let missing: Bool
        var ucsur = false
        if case .character(let character) = item {
            ucsur = showsUCSUR && UCSUR.block(containing: character.codePoint) != nil
            let size: CGFloat = chip ? 20 : character.isInvisible ? 17 : compact ? 24 : 32
            let resolution = UnicodeFontSupport.resolution(for: character.displayText, size: size, enabled: useUnicodeFonts, anchor: character.fontRuleAnchor)
            glyph.font = resolution.font
            accessibilityValue = resolution.faceName.map { "Preview font: \($0)" }
            missing = UnicodeFontSupport.stockFontsMiss(character.displayText)
        } else {
            let size: CGFloat = chip ? 20 : compact ? 24 : 32
            let resolution = UnicodeFontSupport.resolution(for: item.displayText, size: size, enabled: useUnicodeFonts)
            glyph.font = resolution.font
            accessibilityValue = resolution.faceName.map { "Preview font: \($0)" }
            missing = UnicodeFontSupport.stockFontsMiss(item.displayText, emoji: true)
        }
        backgroundColor = glyphOnly
            ? (ucsur ? UIColor.systemBlue.withAlphaComponent(0.18) : missing ? UIColor.systemRed.withAlphaComponent(0.18) : .clear)
            : ucsur ? KeyboardPalette.ucsurUI : missing ? KeyboardPalette.missingGlyphUI : KeyboardPalette.keyUI
        code.text = item.footer
        name.text = showsName ? item.name : nil
        name.isHidden = !showsName
        // A named key shows its code point too.
        let showsCode = !glyphOnly || showsName || chip
        codeHeight.isActive = showsCode
        code.isHidden = !showsCode
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
private struct InputModeSwitchKey: View {
    weak var controller: KeyboardViewController?
    var isModifier = false
    var contentPosition: KeyboardKeyContentPosition = .center
    @Environment(\.keyboardStockKeyInsets) private var touchInsets
    typealias Context = UIViewRepresentableContext<Native>
    @ViewBuilder var body: some View {
        if touchInsets.top > 0 {
            Native(key: self).modifier(KeyboardNativeTouchExpansion()).keyboardKeySurface(modifier: isModifier)
        } else {
            Native(key: self)
        }
    }
    struct Native: UIViewRepresentable {
        let key: InputModeSwitchKey
        func makeUIView(context: Context) -> KeyboardGlobeButton { key.makeUIView(context: context) }
        func updateUIView(_ view: KeyboardGlobeButton, context: Context) {
            let inset = context.environment.keyboardStockKeyInsets
            view.keyboardVisualInsets = UIEdgeInsets(top: inset.top, left: inset.leading, bottom: inset.bottom, right: inset.trailing)
            key.updateUIView(view, context: context)
        }
    }

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
        uiView.backgroundColor = uiView.keyboardVisualInsets == .zero ? (isModifier ? KeyboardPalette.modifierUI : KeyboardPalette.keyUI) : .clear
        uiView.layer.borderWidth = uiView.keyboardVisualInsets == .zero ? 0.5 : 0
        uiView.layer.borderColor = KeyboardPalette.borderUI.resolvedColor(with: uiView.traitCollection).cgColor
    }
}

private final class KeyboardGlobeButton: KeyboardStockButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        keyboardStockTouchRect.contains(point)
    }
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

private struct RepeatingDeleteKey: View {
    let action: (UUID, Bool) -> RepeatingDeleteButton.DeleteAction
    let isQuery: Bool
    let route: UUID
    var identifier = "keyboard.delete"
    var enabled = true
    var padStyle = false
    typealias Context = UIViewRepresentableContext<Native>
    var body: some View { Native(key: self).modifier(KeyboardNativeTouchExpansion()) }
    struct Native: UIViewRepresentable {
        let key: RepeatingDeleteKey
        func makeUIView(context: Context) -> RepeatingDeleteButton { key.makeUIView(context: context) }
        func updateUIView(_ view: RepeatingDeleteButton, context: Context) {
            let inset = context.environment.keyboardStockKeyInsets
            view.keyboardVisualInsets = UIEdgeInsets(top: inset.top, left: inset.leading, bottom: inset.bottom, right: inset.trailing)
            key.updateUIView(view, context: context)
        }
    }

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

#if DEBUG
import CoreText

// MARK: - DEBUG-only cursor probe (docs/preview-cursor-findings.md)
//
// Measurement scaffolding, never compiled into Release. It answers how
// textDocumentProxy.adjustTextPosition(byCharacterOffset:) maps onto host
// text before the text preview becomes interactive. It stays inert unless
// the host document contains the sentinel "cursorprobe" ("cursorprobeline"
// for single-line hosts); then a small yellow button appears at the top of
// the keyboard. Each tap runs one scripted step (seed, move, insert a "|"
// marker, delete it, …) and publishes a report in the button's
// accessibility value. UniboardUITests.testCursorProbeMapsAdjustTextPositionInHosts
// pairs every report with the host's own value, the ground truth.
extension KeyboardViewController {
    func cursorProbeHostEvent(_ event: KeyboardCursorProbe.Event) {
        KeyboardCursorProbe.hostEvent(event, controller: self)
    }
}

@MainActor
final class KeyboardCursorProbe: NSObject {
    enum Event { case appear, text, selection }

    enum Op {
        case seed(String)
        case move(Int)
        case moveRapid(count: Int, by: Int)
        case movePaced(count: Int, by: Int)
        case moveBeyondContext(extra: Int)
        case moveBurst([Int])
        case moveBurstThenInsert([Int], String)
        case mark
        case unmark
        case insert(String)
        case deleteBackward
        case report
        case bidi(String)
    }

    struct Step {
        let name: String
        let ops: [Op]
        var awaitSelection = false
    }

    private static var current: KeyboardCursorProbe?

    static func hostEvent(_ event: Event, controller: UIInputViewController) {
        if let probe = current, probe.controller === controller {
            probe.record(event)
            if probe.finished, probe.sentinelPresent() { probe.restart() }
            return
        }
        let candidate = KeyboardCursorProbe(controller: controller)
        guard candidate.sentinelPresent() else { return }
        current?.button.removeFromSuperview()
        current = candidate
        candidate.restart()
    }

    private weak var controller: UIInputViewController?
    private let button = UIButton(type: .system)
    private var steps: [Step] = []
    private var index = 0
    private var running = false
    private var selectionEvents = 0
    private var textEvents = 0
    private var lastCall: TimeInterval = 0
    private var firstSelectionDelay: Double?
    private var firstTextDelay: Double?

    private init(controller: UIInputViewController) {
        self.controller = controller
        super.init()
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    private var finished: Bool { index >= steps.count && !running }

    private func sentinelPresent() -> Bool {
        guard let proxy else { return false }
        let text = ((proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? "")).lowercased()
        return text.contains("cursorprobe") || Self.previewFixture(in: text) != nil
    }

    /// "previewfixtureN" seeds one text for the preview cursor UI tests
    /// (UniboardUITests "PreviewCursor"), text a test can't type itself.
    static let previewFixtures = [
        "previewfixture1": "Cafe\u{301} \u{5D1}\u{5BC}\u{5E8}\u{5D0} \u{1F469}\u{200D}\u{1F4BB}",
        "previewfixture2": "\u{5E9}\u{5DC}\u{5D5}\u{5DD} abc"
    ]

    private static func previewFixture(in text: String) -> String? {
        previewFixtures.first { text.contains($0.key) }?.value
    }

    private func restart() {
        guard let proxy, let view = controller?.view else { return }
        let text = ((proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? "")).lowercased()
        // "cursorprobe2…" selects the follow-up script (forward walks from
        // the exact start, overshoot and coalescing checks); "cursorprobe3"
        // runs the follow-up and then the first script.
        if let fixture = Self.previewFixture(in: text) {
            steps = [Step(name: "fixture", ops: [.seed(fixture)])]
        } else if text.contains("cursorprobe3") {
            steps = Self.followUpScript() + Self.script(singleLine: false)
        } else if text.contains("cursorprobe2") || text.contains("cursorprobeline2") {
            steps = Self.followUpScript()
        } else {
            steps = Self.script(singleLine: text.contains("cursorprobeline"))
        }
        index = 0
        if button.superview !== view {
            button.removeFromSuperview()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("probe", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
            button.backgroundColor = .systemYellow
            button.setTitleColor(.black, for: .normal)
            button.accessibilityIdentifier = "keyboard.debug.cursorProbe"
            button.accessibilityLabel = "Cursor probe"
            button.removeTarget(nil, action: nil, for: .allEvents)
            button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.topAnchor.constraint(equalTo: view.topAnchor),
                button.widthAnchor.constraint(equalToConstant: 64),
                button.heightAnchor.constraint(equalToConstant: 26)
            ])
        }
        view.bringSubviewToFront(button)
        button.accessibilityValue = "#0/\(steps.count) READY"
    }

    private func record(_ event: Event) {
        let delay = (ProcessInfo.processInfo.systemUptime - lastCall) * 1000
        switch event {
        case .selection:
            selectionEvents += 1
            if firstSelectionDelay == nil { firstSelectionDelay = delay }
        case .text:
            textEvents += 1
            if firstTextDelay == nil { firstTextDelay = delay }
        case .appear:
            break
        }
    }

    @objc private func tapped() {
        guard !running, index < steps.count else { return }
        running = true
        let step = steps[index]
        index += 1
        let number = index
        let total = steps.count
        Task { @MainActor in
            var log: [String] = []
            for op in step.ops { log.append(await self.perform(op)) }
            try? await Task.sleep(nanoseconds: 350_000_000)
            log.append("end=" + self.snapshot())
            self.button.accessibilityValue = "#\(number)/\(total) \(step.name) :: " + log.joined(separator: " ; ")
                + (step.awaitSelection ? " AWAIT:select" : "")
            self.running = false
            // A seeded fixture leaves the keyboard as it ships.
            if step.name == "fixture" { self.button.removeFromSuperview() }
        }
    }

    // MARK: Script

    private static func followUpScript() -> [Step] {
        var steps: [Step] = []
        let cases: [(String, String)] = [
            ("astral", "x\u{1F600}y"),
            ("zwj", "x\u{1F469}\u{200D}\u{1F4BB}y"),
            ("flag", "x\u{1F1EF}\u{1F1F5}y"),
            ("skin", "x\u{1F44D}\u{1F3FD}y"),
            ("combining", "xe\u{301}y"),
            ("niqqud", "x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y"),
            ("mixed", "abc \u{5D0}\u{5D1}\u{5D2} def")
        ]
        for (id, text) in cases {
            let units = text.utf16.count
            // Exactly to the start, then +1 at a time past the end.
            steps.append(Step(name: "\(id) toStart", ops: (steps.isEmpty ? [] : [.unmark]) + [.seed(text), .move(-units), .mark]))
            for i in 1...(units + 1) {
                steps.append(Step(name: "\(id) fwd\(i)", ops: [.unmark, .move(1), .mark]))
            }
            // A move one unit past either edge, in one call.
            steps.append(Step(name: "\(id) overshootEnd", ops: [.unmark, .seed(text), .move(-1), .move(2), .mark]))
            steps.append(Step(name: "\(id) overshootStart", ops: [.unmark, .seed(text), .move(-(units + 1)), .mark]))
        }
        // Coalescing: rapid calls whose sum overshoots, versus paced ones.
        let ascii = "0123456789abcdefghij"
        steps.append(Step(name: "coalesce seed at 15", ops: [.unmark, .seed(ascii), .move(-5), .mark]))
        steps.append(Step(name: "coalesce rapid 8x-1 in range", ops: [.unmark, .moveRapid(count: 8, by: -1), .mark]))
        steps.append(Step(name: "coalesce rapid 12x-1 sum overshoots by 5", ops: [.unmark, .moveRapid(count: 12, by: -1), .mark]))
        steps.append(Step(name: "coalesce paced 12x-1 overshoots by 5", ops: [.unmark, .movePaced(count: 12, by: -1), .mark]))
        steps.append(Step(name: "coalesce burst +3,-1,+3", ops: [.unmark, .moveBurst([3, -1, 3]), .mark]))
        steps.append(Step(name: "coalesce burst +3 then insert at once", ops: [.unmark, .moveBurstThenInsert([1, 1, 1], "Q"), .report]))
        return steps
    }

    private static func script(singleLine: Bool) -> [Step] {
        var steps: [Step] = []
        let cases: [(String, String)] = [
            ("astral", "x\u{1F600}y"),
            ("zwj", "x\u{1F469}\u{200D}\u{1F4BB}y"),
            ("flag", "x\u{1F1EF}\u{1F1F5}y"),
            ("skin", "x\u{1F44D}\u{1F3FD}y"),
            ("combining", "xe\u{301}y"),
            ("niqqud", "x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y"),
            ("mixed", "abc \u{5D0}\u{5D1}\u{5D2} def")
        ]
        for (id, text) in cases {
            let units = text.utf16.count
            steps.append(Step(name: "\(id) seed", ops: [.seed(text)]))
            for i in 1...(units + 1) {
                steps.append(Step(name: "\(id) back\(i)", ops: (i > 1 ? [.unmark] : []) + [.move(-1), .mark]))
            }
            steps.append(Step(name: "\(id) jump-50", ops: [.unmark, .seed(text), .move(-50), .mark]))
            for i in 1...(units + 1) {
                steps.append(Step(name: "\(id) fwd\(i)", ops: [.unmark, .move(1), .mark]))
            }
            steps.append(Step(name: "\(id) end-2 insertZ", ops: [.unmark, .seed(text), .move(-2), .insert("Z")]))
            steps.append(Step(name: "\(id) end-2 delete", ops: [.seed(text), .move(-2), .deleteBackward]))
            steps.append(Step(name: "\(id) end-\(units - 1) mark", ops: [.seed(text), .move(-(units - 1)), .mark]))
            steps.append(Step(name: "\(id) end-\(units - 1) delete", ops: [.unmark, .deleteBackward]))
        }
        steps.append(Step(name: "bidi layout", ops: [
            .bidi("abc \u{5D0}\u{5D1}\u{5D2} def"),
            .bidi("\u{5E9}\u{5DC}\u{5D5}\u{5DD} abc")
        ]))
        // Selection: the UI test double-taps the first word after each AWAIT.
        let selection = "wwwwwwww world"
        steps.append(Step(name: "sel seed", ops: [.seed(selection)], awaitSelection: true))
        steps.append(Step(name: "sel report", ops: [.report]))
        steps.append(Step(name: "sel +3", ops: [.move(3), .mark]))
        steps.append(Step(name: "sel unmark", ops: [.unmark], awaitSelection: true))
        steps.append(Step(name: "sel -3", ops: [.move(-3), .mark]))
        steps.append(Step(name: "sel unmark", ops: [.unmark], awaitSelection: true))
        steps.append(Step(name: "sel 0", ops: [.move(0), .mark]))
        steps.append(Step(name: "sel reseed", ops: [.seed(selection)], awaitSelection: true))
        steps.append(Step(name: "sel insert", ops: [.insert("|")]))
        steps.append(Step(name: "sel reseed", ops: [.seed(selection)], awaitSelection: true))
        steps.append(Step(name: "sel delete", ops: [.deleteBackward]))
        // Long document: exposed context, large jumps, edges and chunking.
        let lines = (1...(singleLine ? 40 : 80)).map { String(format: "L%02ld the quick brown fox jumps over.", $0) }
        let long = lines.joined(separator: singleLine ? " " : "\n")
        steps.append(Step(name: "long seed", ops: [.seed(long), .report]))
        steps.append(Step(name: "long -300", ops: [.move(-300), .mark]))
        steps.append(Step(name: "long +300", ops: [.unmark, .move(300), .mark]))
        steps.append(Step(name: "long -1200", ops: [.unmark, .move(-1200), .mark]))
        steps.append(Step(name: "long mid report", ops: [.unmark, .report]))
        steps.append(Step(name: "long +1200", ops: [.move(1200), .mark]))
        steps.append(Step(name: "long beyond-context", ops: [.unmark, .moveBeyondContext(extra: 40), .mark]))
        steps.append(Step(name: "long -100000", ops: [.unmark, .move(-100000), .mark]))
        steps.append(Step(name: "long start report", ops: [.unmark, .report]))
        steps.append(Step(name: "long +100000", ops: [.move(100000), .mark]))
        steps.append(Step(name: "long rapid 12x-100", ops: [.unmark, .moveRapid(count: 12, by: -100), .mark]))
        steps.append(Step(name: "long to end", ops: [.unmark, .move(100000), .mark]))
        steps.append(Step(name: "long paced 12x-100", ops: [.unmark, .movePaced(count: 12, by: -100), .mark]))
        steps.append(Step(name: "long rapid 40x-1", ops: [.unmark, .moveRapid(count: 40, by: -1), .mark]))
        return steps
    }

    // MARK: Operations

    private func perform(_ op: Op) async -> String {
        guard let proxy else { return "no-proxy" }
        switch op {
        case .seed(let text):
            let rounds = await clear()
            call { proxy.insertText(text) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            return "seed(\(Self.escape(String(text.prefix(24))))…u16=\(text.utf16.count)) clearRounds=\(rounds) -> " + snapshot()
        case .move(let offset):
            return await measured("move(\(offset))") { proxy.adjustTextPosition(byCharacterOffset: offset) }
        case .moveRapid(let count, let offset):
            return await measured("rapid(\(count)x\(offset))") {
                for _ in 0..<count { proxy.adjustTextPosition(byCharacterOffset: offset) }
            }
        case .movePaced(let count, let offset):
            var trail: [String] = []
            for _ in 0..<count {
                call { proxy.adjustTextPosition(byCharacterOffset: offset) }
                try? await Task.sleep(nanoseconds: 80_000_000)
                trail.append("b\(proxy.documentContextBeforeInput?.utf16.count ?? -1)")
            }
            return "paced(\(count)x\(offset)) " + trail.joined(separator: ",") + " -> " + snapshot()
        case .moveBurst(let offsets):
            return await measured("burst(\(offsets))") {
                for offset in offsets { proxy.adjustTextPosition(byCharacterOffset: offset) }
            }
        case .moveBurstThenInsert(let offsets, let text):
            return await measured("burst(\(offsets))+insert(\(Self.escape(text)))") {
                for offset in offsets { proxy.adjustTextPosition(byCharacterOffset: offset) }
                proxy.insertText(text)
            }
        case .moveBeyondContext(let extra):
            let exposed = proxy.documentContextBeforeInput?.utf16.count ?? 0
            let offset = -(exposed + extra)
            return await measured("beyond(exposed=\(exposed) move \(offset))") { proxy.adjustTextPosition(byCharacterOffset: offset) }
        case .mark:
            return await measured("mark") { proxy.insertText("|") }
        case .unmark:
            return await measured("unmark") { proxy.deleteBackward() }
        case .insert(let text):
            return await measured("insert(\(Self.escape(text)))") { proxy.insertText(text) }
        case .deleteBackward:
            return await measured("deleteBackward") { proxy.deleteBackward() }
        case .report:
            let before = proxy.documentContextBeforeInput
            let after = proxy.documentContextAfterInput
            return "report hasText=\(proxy.hasText) selected=\(proxy.selectedText.map { "\"\(Self.escape($0))\"" } ?? "nil")"
                + " beforeLen=\(before.map { "\($0.utf16.count)u16/\($0.count)ch" } ?? "nil")"
                + " afterLen=\(after.map { "\($0.utf16.count)u16/\($0.count)ch" } ?? "nil")"
                + " beforeHead=\"\(Self.escape(String((before ?? "").prefix(20))))\""
                + " afterTail=\"\(Self.escape(String((after ?? "").suffix(20))))\" " + snapshot()
        case .bidi(let text):
            return Self.bidiLayout(text)
        }
    }

    private func call(_ body: () -> Void) {
        lastCall = ProcessInfo.processInfo.systemUptime
        firstSelectionDelay = nil
        firstTextDelay = nil
        body()
    }

    /// Runs one proxy call and samples the context synchronously, after one
    /// main-queue turn, after 60 ms and after 300 ms, with callback counts.
    private func measured(_ name: String, _ body: () -> Void) async -> String {
        let pre = snapshot()
        let selection0 = selectionEvents
        let text0 = textEvents
        call(body)
        let sync = snapshot()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        let turn = snapshot()
        try? await Task.sleep(nanoseconds: 60_000_000)
        let ms60 = snapshot()
        try? await Task.sleep(nanoseconds: 240_000_000)
        let ms300 = snapshot()
        func delta(_ value: String, _ previous: String) -> String { value == previous ? "=" : value }
        let selectionDelay = firstSelectionDelay.map { String(format: "%.0fms", $0) } ?? "-"
        let textDelay = firstTextDelay.map { String(format: "%.0fms", $0) } ?? "-"
        return "\(name) pre=\(pre) sync=\(delta(sync, pre)) turn=\(delta(turn, sync)) 60ms=\(delta(ms60, turn))"
            + " 300ms=\(delta(ms300, ms60)) cb[sel+\(selectionEvents - selection0)@\(selectionDelay)"
            + " txt+\(textEvents - text0)@\(textDelay)]"
    }

    /// Moves to the end of the exposed text and deletes until the host has none.
    private func clear() async -> Int {
        guard let proxy else { return -1 }
        for round in 0..<60 {
            if let after = proxy.documentContextAfterInput, !after.isEmpty {
                call { proxy.adjustTextPosition(byCharacterOffset: after.utf16.count) }
                try? await Task.sleep(nanoseconds: 120_000_000)
                continue
            }
            let before = proxy.documentContextBeforeInput ?? ""
            if before.isEmpty && !proxy.hasText { return round }
            let count = before.isEmpty ? 50 : before.utf16.count
            call { for _ in 0..<count { proxy.deleteBackward() } }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return 60
    }

    private func snapshot() -> String {
        guard let proxy else { return "[no-proxy]" }
        let before = proxy.documentContextBeforeInput
        let after = proxy.documentContextAfterInput
        let b = before.map { "\"\(Self.escape(String($0.suffix(12))))\"(\($0.utf16.count)u16,\($0.count)ch)" } ?? "nil"
        let a = after.map { "\"\(Self.escape(String($0.prefix(12))))\"(\($0.utf16.count)u16,\($0.count)ch)" } ?? "nil"
        var result = "[\(b)^\(a)"
        if let selected = proxy.selectedText, !selected.isEmpty { result += " sel=\"\(Self.escape(selected))\"" }
        return result + "]"
    }

    static func escape(_ text: String) -> String {
        text.unicodeScalars.map { scalar -> String in
            if scalar.value >= 0x20 && scalar.value < 0x7F && scalar != "\\" { return String(scalar) }
            if scalar == "\n" { return "\\n" }
            return "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
        }.joined()
    }

    /// How Core Text lays out a bidi string in a left-to-right line, the
    /// geometry a tap-to-offset mapping in the preview row would rely on.
    private static func bidiLayout(_ text: String) -> String {
        let attributed = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17)])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        var offsets: [String] = []
        let units = Array(text.utf16)
        for i in 0...units.count {
            var secondary: CGFloat = 0
            let primary = CTLineGetOffsetForStringIndex(line, i, &secondary)
            offsets.append("\(i):" + String(format: "%.1f/%.1f", primary, secondary))
        }
        var carets: [String] = []
        CTLineEnumerateCaretOffsets(line) { offset, index, leading, _ in
            carets.append(String(format: "%.1f", offset) + "→\(index)" + (leading ? "L" : "T"))
        }
        var hits: [String] = []
        var x: CGFloat = 0
        while x <= CGFloat(width) + 4 {
            hits.append(String(format: "x%.0f", x) + "→\(CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0)))")
            x += 6
        }
        return "bidi(\(escape(text)) width=\(String(format: "%.1f", width))) offsets{\(offsets.joined(separator: " "))}"
            + " carets{\(carets.joined(separator: " "))} hits{\(hits.joined(separator: " "))}"
    }
}
#endif
