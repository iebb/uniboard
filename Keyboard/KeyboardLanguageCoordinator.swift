import Foundation
import Combine

/// Session-only language input. This object never owns a textDocumentProxy and
/// never persists a selected mode, an anchor, raw input, or candidate output.
/// (The controller alone records the person's chosen mode in
/// `LanguageInputLastMode`; this object only selects.)
/// The controller resolves deliberate transitions BEFORE calling select(_:), and
/// applies returned effects synchronously, without yielding to another document.
@MainActor
final class KeyboardLanguageCoordinator: ObservableObject {
    @Published private(set) var state = LanguageCompositionState(documentID: UUID())
    // Refresh/revalidation re-derives these on every append and conversion
    // result. Each is published ONLY when its value actually changes, so an
    // unchanged re-derivation doesn't re-render the whole keyboard. (Nothing
    // observes them for side effects: no didSet, sink or onChange.)
    @Published private var publishedEnabledModes: [LanguageInputMode] = [.direct]
    @Published private var publishedPreferences = LanguageInputSettings.Value.defaults
    @Published private var publishedResourceStatus: LanguageConversionStatus = .ready
    @Published private var publishedIsLoading = false
    @Published private var publishedIsConverting = false
    @Published private var publishedUnavailableModes: [LanguageInputMode: LanguageModeUnavailability] = [:]

    private(set) var enabledModes: [LanguageInputMode] {
        get { publishedEnabledModes }
        set { if newValue != publishedEnabledModes { publishedEnabledModes = newValue } }
    }
    private(set) var preferences: LanguageInputSettings.Value {
        get { publishedPreferences }
        set { if newValue != publishedPreferences { publishedPreferences = newValue } }
    }
    private(set) var resourceStatus: LanguageConversionStatus {
        get { publishedResourceStatus }
        set { if newValue != publishedResourceStatus { publishedResourceStatus = newValue } }
    }
    private(set) var isLoading: Bool {
        get { publishedIsLoading }
        set { if newValue != publishedIsLoading { publishedIsLoading = newValue } }
    }
    private(set) var isConverting: Bool {
        get { publishedIsConverting }
        set { if newValue != publishedIsConverting { publishedIsConverting = newValue } }
    }
    /// Why each enabled-but-not-ready mode isn't ready, from the latest refresh
    /// or activation. `.unreadable` modes stay in `enabledModes` (the space-bar
    /// list) so choosing one can explain itself instead of silently vanishing.
    private(set) var unavailableModes: [LanguageInputMode: LanguageModeUnavailability] {
        get { publishedUnavailableModes }
        set { if newValue != publishedUnavailableModes { publishedUnavailableModes = newValue } }
    }

    /// Called AFTER publication; the controller can invalidate intrinsic height.
    var onChange: (() -> Void)?
    /// Called once a refresh has published its choices (appearance or the app's
    /// notification). The controller applies the remembered mode from here.
    var onRefreshed: (() -> Void)?
    /// Required for accepting results or returning any host-write effect. Capture
    /// the original field/cursor context before the FIRST append. This closure
    /// must validate that captured anchor, not merely report the current field.
    var validateAnchor: (() -> Bool)?

    var mode: LanguageInputMode { state.mode }
    var rawInput: String { state.rawInput }
    var preedit: String { state.visibleResult?.preedit ?? (mode == .koreanTwoSetHangul ? "" : rawInput) }
    var candidates: [LanguageConversionCandidate] { state.visibleResult?.candidates ?? [] }
    var token: LanguageCompositionToken { state.token }
    var choices: [LanguageInputMode] { enabledModes }
    var hasComposition: Bool { !rawInput.isEmpty }
    var status: LanguageConversionStatus {
        resourceStatus == .ready ? (state.visibleResult?.status ?? .ready) : resourceStatus
    }
    var name: String { Self.name(for: mode) }

    static func name(for mode: LanguageInputMode) -> String {
        switch mode {
        case .direct: return "Direct Typing"
        case .japaneseRomaji: return "Japanese — Romaji"
        case .mandarinPinyin: return "Mandarin Chinese — Pinyin"
        case .koreanRomaja: return "Korean — Romaja"
        case .koreanTwoSetHangul: return "Korean — Two-Set Hangul"
        }
    }

    /// Re-resolved on every refresh (a cheap path lookup), so a container that
    /// was unavailable at launch is picked up without restarting the keyboard.
    private let rootProvider: () -> URL?
    private var root: URL?
    private let settings: LanguageInputSettings
    private let indexDirectory: () -> URL?
    private let worker = KeyboardLanguageResourceWorker()
    private var owner: KeyboardLanguageEngineOwner?
    private var conversionTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private var indexRefreshTask: Task<UUID?, Never>?
    private var activationID = UUID()
    private var refreshID = UUID()
    private var dictionaryUUID: UUID?
    private var dictionaryDirectory: URL?
    private var dictionaryRevision: UInt64 = 0
    private var dictionaryRevisionExhausted = false

    /// root MUST be the same dedicated pack-store root used by the containing
    /// app. nil means inaccessible storage; it never guesses a different store.
    /// Custom words are read ONLY from the compiled SQLite index, never JSON.
    init(root: @escaping () -> URL? = {
             FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)?.appendingPathComponent("LanguagePacks", isDirectory: true)
         },
         settings: LanguageInputSettings = .shared,
         indexDirectory: @escaping () -> URL? = {
             FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)?.appendingPathComponent("MyWords", isDirectory: true)
         }) {
        self.rootProvider = root
        self.root = root()
        self.settings = settings
        self.indexDirectory = indexDirectory
    }

    deinit {
        conversionTask?.cancel()
        activationTask?.cancel()
        indexRefreshTask?.cancel()
    }

    /// Call on every appearance and on app-settings/resource notifications.
    /// Chooser metadata and active-only index opening run on the worker. A refresh
    /// never enables a mode, silently switches an unfinished buffer, or writes.
    func refresh() {
        // Claim the refresh now, so an older refresh that finishes before this
        // Task starts can't publish (or report `onRefreshed`) as the current one.
        let ticket = UUID()
        refreshID = ticket
        Task { [weak self] in
            guard let self, self.refreshID == ticket else { return }
            await self.refreshResources()
        }
    }

    func refreshResources() async {
        let id = UUID()
        refreshID = id
        root = rootProvider()
        preferences = settings.load()
        let requested = preferences.enabledModes.filter { $0 != .koreanRomaja }
        let availability = await worker.availableModes(root: root, requested: requested, references: preferences.packReferences)
        let ready = availability.ready
        guard refreshID == id, !Task.isCancelled else { return }
        // Only the selected conversion mode may open My Words. Readers are
        // operation-local; a switch cancels queued work and rejects late results.
        if mode.supportsConversionMyWords {
            let selected = mode
            let activation = activationID
            let directory = indexDirectory()?.standardizedFileURL
            let worker = worker
            indexRefreshTask?.cancel()
            let task = Task { await worker.refreshIndex(directory: directory) }
            indexRefreshTask = task
            let revision = await task.value
            guard refreshID == id, activationID == activation, mode == selected,
                  !task.isCancelled, !Task.isCancelled else { return }
            indexRefreshTask = nil
            updateDictionary(revision, directory: directory)
        }
        // Preferences could have changed during metadata/index inspection.
        preferences = settings.load()
        unavailableModes = availability.unavailable.filter { preferences.isEnabled($0.key) }
        // Ready modes AND enabled modes that can't be read; never disabled or Romaja.
        enabledModes = LanguageInputChoicePolicy.choices(enabled: preferences, ready: ready, unavailable: unavailableModes)
        _ = revalidateResources(checkDictionary: false)
        if mode != .direct {
            if !preferences.isEnabled(mode), !hasComposition {
                _ = select(.direct)
            } else if owner == nil, !isLoading, preferences.isEnabled(mode), ready.contains(mode) {
                beginActivation()
            } else if owner != nil, hasComposition, state.pendingRequest == nil,
                      state.visibleResult == nil, anchorIsValid() {
                scheduleConversion()
            }
        }
        changed()
        onRefreshed?()
    }

    /// false means unavailable OR unfinished text requires the controller's
    /// Keep Typed Text / Cancel Conversion / Keep Editing boundary panel first.
    /// Selecting the current mode is a no-op and never discards its composition.
    @discardableResult
    func select(_ selected: LanguageInputMode) -> Bool {
        if selected == mode { return true }
        guard !hasComposition else { return false }
        preferences = settings.load()
        guard selected == .direct || (selected != .koreanRomaja
            && preferences.isEnabled(selected) && enabledModes.contains(selected)) else { return false }
        stopWork()
        owner = nil
        state.changeMode(to: selected)
        state.changeResources(packRevision: "", dictionaryRevision: mode.supportsConversionMyWords ? dictionaryRevision : 0)
        resourceStatus = selected == .direct ? .ready : .missingResources
        if selected != .direct { beginActivation() }
        changed()
        return true
    }

    /// Only call for an unmodified normal key. Saved outputs, hold/swipe choices,
    /// Unicode actions and boundary punctuation belong to the controller. true
    /// consumes the tap even while loading, disabled, unsupported or at the cap:
    /// a broken converter must NOT leak Latin letters into the host document.
    @discardableResult
    func append(_ text: String) -> Bool {
        guard mode != .direct else { return false }
        guard revalidateResources(checkDictionary: false), owner != nil, !isLoading,
              preferences.isEnabled(mode), (!mode.supportsConversionMyWords || !dictionaryRevisionExhausted) else { return true }
        if hasComposition, !anchorIsValid() { documentChanged(); return true }
        // Preserve unsupported normal-key spelling locally as well. The real
        // engine reports unsupportedInput; literal/cancel recovery stays exact.
        let disposition = state.append(text, origin: .normalKeyTap) { mode, proposed in
            if mode == .koreanTwoSetHangul { return KoreanTwoSetKeyboard.accepts(proposed) ? proposed : nil }
            guard !proposed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return proposed
        }
        switch disposition {
        case .accepted: scheduleConversion()
        case .inputLimitReached, .unsupportedInput: changed()
        case .revisionExhausted: resourceStatus = .failed; changed()
        case .bypass: break
        }
        return true
    }

    /// false ONLY when the local buffer is empty: the controller then uses its
    /// existing host-delete path. Never returns a hostDelete effect itself.
    @discardableResult
    func backspace() -> Bool {
        guard hasComposition else { return false }
        guard anchorIsValid() else { documentChanged(); return true }
        conversionTask?.cancel()
        _ = state.backspace()
        if hasComposition, revalidateResources(checkDictionary: false), owner != nil {
            scheduleConversion()
        } else {
            isConverting = false
            finishUnavailableCompositionIfNeeded()
            changed()
        }
        return true
    }

    func choose(id: String, token expectedToken: LanguageCompositionToken) -> [LanguageCompositionEffect] {
        guard validateForCommit(expectedToken) else { return [] }
        let effects = state.choose(candidateID: id, expectedToken: expectedToken)
        afterCommit(effects)
        return effects
    }

    func commitLiteral(token expectedToken: LanguageCompositionToken) -> [LanguageCompositionEffect] {
        guard mode.offersLiteralConversion, validateForCommit(expectedToken) else { return [] }
        let effects = state.resolveBoundary(.commitLiteral, expectedToken: expectedToken)
        afterCommit(effects)
        return effects
    }

    /// A boundary is authorized only by a ready result for the current token.
    /// Korean's one Space suffix is part of the same effect, never a second write.
    func commitDefault(token expectedToken: LanguageCompositionToken, space: Bool = false) -> [LanguageCompositionEffect] {
        guard validateForCommit(expectedToken), let result = state.visibleResult,
              result.token == expectedToken, result.status == .ready else { return [] }
        let candidate = result.candidates.first { $0.source != .literal }
            ?? (mode.offersLiteralConversion ? result.candidates.first : nil)
        guard let candidate else { return [] }
        let effects = state.choose(candidateID: candidate.id, expectedToken: expectedToken,
                                   suffix: space ? mode.conversionSpaceSuffix : "")
        afterCommit(effects)
        return effects
    }

    /// Explicit cancellation clears only local unfinished input. It performs no
    /// host deletion, and does not select a pending controller-owned transition.
    func cancel() {
        conversionTask?.cancel()
        state.cancel()
        isConverting = false
        finishUnavailableCompositionIfNeeded()
        changed()
    }

    /// Call on focus, selection, cursor, external text/context change, or on hide
    /// when the original anchor cannot be validated. Clears live/parked input.
    func documentChanged() {
        conversionTask?.cancel()
        state.changeDocument(to: UUID())
        isConverting = false
        finishUnavailableCompositionIfNeeded()
        changed()
    }

    private func anchorIsValid() -> Bool { validateAnchor?() == true }

    private func validateForCommit(_ expected: LanguageCompositionToken) -> Bool {
        guard state.token == expected else { return false }
        guard anchorIsValid() else { documentChanged(); return false }
        // Even literal writes check publication/prefs. A mutation revokes the old
        // token, retaining raw text so a NEW explicit literal action can recover.
        _ = revalidateResources(checkDictionary: true)
        return state.token == expected && anchorIsValid() && (!mode.supportsConversionMyWords || !dictionaryRevisionExhausted)
    }

    private func afterCommit(_ effects: [LanguageCompositionEffect]) {
        guard !effects.isEmpty else { return }
        conversionTask?.cancel()
        isConverting = false
        // Never schedule before the controller synchronously inserts the effect:
        // a partial-consumption adapter would otherwise validate the old anchor.
        // Current Japanese and Mandarin adapters expose whole-buffer candidates.
        finishUnavailableCompositionIfNeeded()
        changed()
    }

    private func finishUnavailableCompositionIfNeeded() {
        if !hasComposition, mode != .direct, !settings.load().isEnabled(mode) {
            _ = select(.direct)
        }
    }

    private func stopWork() {
        conversionTask?.cancel()
        activationTask?.cancel()
        indexRefreshTask?.cancel()
        indexRefreshTask = nil
        activationID = UUID()
        isConverting = false
        isLoading = false
    }

    private func beginActivation() {
        guard mode.conversionEngineABI != nil else { return }
        activationTask?.cancel()
        conversionTask?.cancel()
        let id = UUID()
        activationID = id
        let selected = mode
        let root = root
        let worker = worker
        let directory = selected.supportsConversionMyWords ? indexDirectory()?.standardizedFileURL : nil
        isLoading = true
        isConverting = false
        activationTask = Task { [weak self] in
            // Direct refresh deliberately never initializes this identity. Every
            // activation observes current publication, including re-entry after
            // the app replaced My Words while Direct Typing was selected.
            let revision = selected.supportsConversionMyWords ? await worker.refreshIndex(directory: directory) : nil
            guard let self, self.activationID == id, self.mode == selected,
                  !Task.isCancelled else { return }
            if selected.supportsConversionMyWords { self.updateDictionary(revision, directory: directory) }
            let activation = await worker.activate(mode: selected, root: root)
            guard self.activationID == id, self.mode == selected,
                  !Task.isCancelled else { return }
            self.preferences = self.settings.load()
            // Every outcome below re-derives why this mode is unavailable, so a
            // stale "unreadable" never outlives a missing/damaged/ready result.
            guard self.preferences.isEnabled(selected) else {
                self.isLoading = false
                self.unavailableModes[selected] = nil
                self.revokeActiveResource(status: .missingResources)
                self.finishUnavailableCompositionIfNeeded()
                self.changed()
                return
            }
            do {
                guard let lease = activation.lease else {
                    self.isLoading = false
                    self.unavailableModes[selected] = activation.unreadable ? .unreadable
                        : activation.status == .failed ? .damaged : .missing
                    self.resourceStatus = activation.status
                    self.changed()
                    return
                }
                // Check the pointer AGAIN after background hashing. Never accept
                // a lease whose publication was removed/replaced while resolving.
                guard let root, try LanguagePackStore(root: root).activeRevision(modeID: selected.rawValue) == lease.pack.revision else {
                    self.isLoading = false
                    self.unavailableModes[selected] = .missing
                    self.resourceStatus = .missingResources
                    self.changed()
                    return
                }
                guard self.preferences.isEnabled(selected),
                      Self.matchesReference(lease.pack.descriptor, references: self.preferences.packReferences) else {
                    self.isLoading = false
                    self.unavailableModes[selected] = .mismatched
                    self.revokeActiveResource(status: .missingResources)
                    self.changed()
                    return
                }
                let engine: any LanguageConversionEngine
                let status: LanguageConversionStatus
                switch selected {
                case .japaneseRomaji:
                    guard let scratch = activation.scratch?.url else { throw KeyboardLanguageResourceError.unavailable }
                    let japanese = try JapaneseLanguageConverter(
                        installedDictionaryURL: lease.pack.path.appendingPathComponent("Dictionary", isDirectory: true),
                        lease: lease, scratchDirectoryURL: scratch)
                    engine = japanese
                    status = japanese.kanjiResourceStatus
                case .mandarinPinyin:
                    let mandarin = try MandarinLanguageConverter(
                        installedDictionaryURL: lease.pack.path.appendingPathComponent(MandarinLanguageConverter.databaseFilename), lease: lease)
                    engine = mandarin
                    status = mandarin.resourceStatus
                case .koreanTwoSetHangul:
                    guard let mapping = activation.mapping else { throw KeyboardLanguageResourceError.unavailable }
                    engine = try KoreanHangulLanguageConverter(mapping: mapping, lease: lease)
                    status = .ready
                case .direct, .koreanRomaja:
                    throw KeyboardLanguageResourceError.unavailable
                }
                self.owner = KeyboardLanguageEngineOwner(engine: engine, descriptor: lease.pack.descriptor, scratch: activation.scratch)
                self.unavailableModes[selected] = nil
                self.state.changeResources(packRevision: lease.pack.revision, dictionaryRevision: selected.supportsConversionMyWords ? self.dictionaryRevision : 0)
                self.resourceStatus = status
                self.isLoading = false
                if self.hasComposition, self.anchorIsValid() { self.scheduleConversion() }
                self.changed()
            } catch {
                self.isLoading = false
                self.unavailableModes[selected] = .damaged
                self.resourceStatus = .failed
                self.changed()
            }
        }
    }

    /// Only bounded preferences, pointer metadata and index schema/UUID metadata
    /// are read here; NEVER full-pack verification/hashing or source JSON. Opening
    /// a current index here is a bounded commit-time publication check. Actual
    /// operation-local lookups and appearance opening belong to the worker.
    @discardableResult
    private func revalidateResources(checkDictionary: Bool) -> Bool {
        preferences = settings.load()
        enabledModes = enabledModes.filter { $0 == .direct || preferences.isEnabled($0) }
        guard mode != .direct else { return true }
        if checkDictionary && mode.supportsConversionMyWords {
            let directory = indexDirectory()?.standardizedFileURL
            let revision = directory.flatMap { try? CustomInputDictionaryIndex(directory: $0).revision }
            updateDictionary(revision, directory: directory)
        }
        guard preferences.isEnabled(mode), mode != .koreanRomaja else {
            revokeActiveResource(status: .missingResources)
            if !hasComposition { _ = select(.direct) }
            return false
        }
        guard !state.packRevision.isEmpty else { return false }
        if let descriptor = owner?.descriptor,
           !Self.matchesReference(descriptor, references: preferences.packReferences) {
            revokeActiveResource(status: .missingResources)
            return false
        }
        do {
            guard let root,
                  try LanguagePackStore(root: root).activeRevision(modeID: mode.rawValue) == state.packRevision else {
                revokeActiveResource(status: .missingResources)
                return false
            }
        } catch {
            revokeActiveResource(status: .missingResources)
            return false
        }
        return true
    }

    private func revokeActiveResource(status: LanguageConversionStatus) {
        if owner != nil || !state.packRevision.isEmpty || isLoading {
            stopWork()
            owner = nil // In-flight work retains its own engine/lease until exit.
            state.changeResources(packRevision: "", dictionaryRevision: mode.supportsConversionMyWords ? dictionaryRevision : 0)
        }
        resourceStatus = status
        enabledModes.removeAll { $0 == mode && $0 != .direct }
        changed()
    }

    private func updateDictionary(_ revision: UUID?, directory: URL?) {
        guard revision != dictionaryUUID || directory != dictionaryDirectory else { return }
        guard dictionaryRevision < UInt64.max else {
            dictionaryRevisionExhausted = true
            conversionTask?.cancel()
            state.changeDocument(to: UUID())
            resourceStatus = .failed
            changed()
            return
        }
        dictionaryUUID = revision
        dictionaryDirectory = directory
        dictionaryRevision += 1 // UUIDs are identities, not truncatable integers.
        conversionTask?.cancel()
        isConverting = false
        state.changeResources(packRevision: state.packRevision, dictionaryRevision: mode.supportsConversionMyWords ? dictionaryRevision : 0)
        changed()
    }

    private func scheduleConversion() {
        conversionTask?.cancel()
        guard let owner, let engine = owner.engine, let request = state.requestConversion() else {
            isConverting = false
            changed()
            return
        }
        let customRevision = dictionaryUUID
        let directory = dictionaryDirectory
        let worker = worker
        let normalized: String?
        switch request.token.mode {
        case .japaneseRomaji: normalized = JapaneseInputReading.normalizedCustomReading(request.rawInput)
        case .mandarinPinyin: normalized = MandarinPinyinReading.canonicalCustomReading(request.rawInput)
        case .direct, .koreanRomaja, .koreanTwoSetHangul: normalized = nil
        }
        isConverting = true
        changed()
        conversionTask = Task { [weak self, owner] in
            // Retain the scratch owner as well as the converter through awaiting
            // work. Dropping the active mode must not remove its scratch/lease.
            defer { withExtendedLifetime(owner) {} }
            do {
                let result = try await engine.convert(request)
                try Task.checkCancellation()
                let custom = request.token.mode.supportsConversionMyWords
                    ? await worker.lookup(directory: directory, expectedRevision: customRevision,
                                          mode: request.token.mode, normalizedReading: normalized) : []
                try Task.checkCancellation()
                guard let self, self.state.token == request.token else { return }
                guard self.anchorIsValid() else { self.documentChanged(); return }
                _ = self.revalidateResources(checkDictionary: true)
                guard self.state.token == request.token, self.anchorIsValid() else { return }
                let merged = Self.merging(custom: custom, into: result, request: request)
                _ = self.state.receive(merged)
                self.isConverting = false
                self.changed()
            } catch is CancellationError {
                // Cancellation never changes a newer request's UI.
            } catch {
                guard let self, self.state.token == request.token else { return }
                guard self.anchorIsValid() else { self.documentChanged(); return }
                _ = self.revalidateResources(checkDictionary: true)
                guard self.state.token == request.token, self.anchorIsValid() else { return }
                _ = self.state.receive(.init(token: request.token, preedit: request.token.mode == .koreanTwoSetHangul ? "" : request.rawInput,
                                             candidates: [], status: .failed))
                self.isConverting = false
                self.changed()
            }
        }
    }

    /// Exact UTF-8 equality, NOT Swift String's canonically-equivalent equality.
    /// Custom choices precede engine outputs. Reserve the real adapter's local
    /// literal/kana escapes before taking a potentially full custom result set.
    nonisolated static func merging(custom: [CustomInputDictionaryIndexedCandidate],
                                    into result: LanguageConversionResult,
                                    request: LanguageConversionRequest) -> LanguageConversionResult {
        guard request.token.mode.supportsConversionMyWords, result.status == .ready else { return result }
        let limit = min(request.candidateLimit, LanguageCompositionLimits.candidates)
        let fallback = result.candidates.filter { [.literal, .hiragana, .katakana].contains($0.source) }
        var seen = Set<Data>()
        var output: [LanguageConversionCandidate] = []
        let reserve = Set(fallback.map { Data($0.output.utf8) }).count
        for (position, candidate) in custom.prefix(max(0, limit - reserve)).enumerated() {
            guard seen.insert(Data(candidate.output.utf8)).inserted else { continue }
            output.append(.init(id: "custom-\(position)", output: candidate.output, source: .custom,
                                consumedInputScalars: request.rawInput.unicodeScalars.count))
        }
        for candidate in result.candidates where ![.literal, .hiragana, .katakana].contains(candidate.source) {
            guard output.count < limit - reserve else { break }
            guard seen.insert(Data(candidate.output.utf8)).inserted else { continue }
            output.append(candidate)
        }
        for candidate in fallback {
            guard output.count < limit else { break }
            if seen.insert(Data(candidate.output.utf8)).inserted { output.append(candidate) }
        }
        return .init(token: result.token, preedit: result.preedit, candidates: output, status: result.status)
    }

    nonisolated static func matchesReference(_ descriptor: LanguagePackDescriptor,
                                             references: [LanguageInputSettings.PackReference]) -> Bool {
        let pins = references.filter { $0.mode.rawValue == descriptor.modeID }
        // An explicitly supplied pin cannot silently resolve to another version
        // after configuration import. No pin is not a download instruction.
        return pins.isEmpty || pins.contains {
            $0.packID == descriptor.packID && $0.version == descriptor.version
                && $0.archiveSHA256 == descriptor.archiveSHA256
        }
    }

    /// English correction is allowed only when the current bounded index proves
    /// this reading has no explicit custom output. Unknown/unreadable storage is
    /// protective, not evidence that the user's word is absent. No source JSON
    /// or full dictionary is read here; the immutable index performs one range.
    func protectsEnglishCustomReading(_ rawReading: String) -> Bool {
        guard let outputs = englishCustomOutputs(for: rawReading) else { return true }
        return !outputs.isEmpty
    }

    /// nil means unavailable/changed storage; [] is a verified absent reading.
    /// Called at a delimiter or deliberate suggestion action, not per layout.
    func englishCustomOutputs(for rawReading: String) -> [String]? {
        guard mode.supportsConversionMyWords else { return nil }
        guard !rawReading.isEmpty, rawReading.unicodeScalars.count <= 256,
              let directory = indexDirectory()?.standardizedFileURL else { return nil }
        let manager = FileManager.default
        do {
            // Listing a trusted parent distinguishes a genuinely absent fresh
            // index from an inaccessible shared container (Full Access limits).
            let parentChildren = try manager.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path)
            guard parentChildren.contains(directory.lastPathComponent) else { return [] }
            let children = try manager.contentsOfDirectory(atPath: directory.path)
            guard children.contains(CustomInputDictionaryIndex.filename) else { return [] }
            let index = try CustomInputDictionaryIndex(directory: directory)
            let revision = index.revision
            let rows = try index.lookup(modeID: LanguageInputMode.direct.rawValue,
                                        normalizedReading: rawReading.lowercased())
            // Atomic app publication may happen during this lookup. Never
            // authorize automatic editing using an obsolete no-match answer.
            guard try CustomInputDictionaryIndex(directory: directory).revision == revision else { return nil }
            return rows.map(\.output)
        } catch { return nil }
    }

    private func changed() { onChange?() }
}

private enum KeyboardLanguageResourceError: Error { case unavailable }

/// Scratch bytes are process-local and contain no learned dictionary/history.
/// Owned alongside the engine, never deleted just because the selected mode moved.
private final class KeyboardLanguageScratch {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("uniboard-input-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

private final class KeyboardLanguageEngineOwner {
    var engine: (any LanguageConversionEngine)?
    let descriptor: LanguagePackDescriptor
    let scratch: KeyboardLanguageScratch?
    init(engine: any LanguageConversionEngine, descriptor: LanguagePackDescriptor, scratch: KeyboardLanguageScratch?) {
        self.engine = engine
        self.descriptor = descriptor
        self.scratch = scratch
    }
    deinit { engine = nil } // Converter/cache dies before scratch and lease cleanup.
}

private actor KeyboardLanguageResourceWorker {
    struct Activation {
        let lease: LanguagePackReadLease?
        let scratch: KeyboardLanguageScratch?
        let status: LanguageConversionStatus
        var mapping: KoreanHangulComposer.KeyMapping? = nil
        /// The files (or the shared container) couldn't be read at all.
        var unreadable = false
    }
    struct Availability: Sendable {
        var ready: [LanguageInputMode] = [.direct]
        /// One reason per requested mode that isn't ready.
        var unavailable: [LanguageInputMode: LanguageModeUnavailability] = [:]
    }
    func availableModes(root: URL?, requested: [LanguageInputMode],
                        references: [LanguageInputSettings.PackReference]) -> Availability {
        var result = Availability()
        let modes = requested.filter { $0 != .direct && $0 != .koreanRomaja && $0.conversionEngineABI != nil }
        // No container: an enabled language can't be read, not "not downloaded".
        guard let root else {
            for mode in modes { result.unavailable[mode] = .unreadable }
            return result
        }
        let store = LanguagePackStore(root: root)
        for mode in modes {
            guard let abi = mode.conversionEngineABI else { continue }
            switch store.publishedMetadata(modeID: mode.rawValue, engineABI: abi) {
            case .available(let metadata):
                if KeyboardLanguageCoordinator.matchesReference(metadata.descriptor, references: references) {
                    result.ready.append(mode)
                } else { result.unavailable[mode] = .mismatched }
            case .unreadable: result.unavailable[mode] = .unreadable
            case .absent, .missing: result.unavailable[mode] = .missing
            case .corrupt, .incompatible: result.unavailable[mode] = .damaged
            }
        }
        return result
    }

    /// Fresh region transfer: this actor NEVER retains the lease or scratch.
    /// No unchecked Sendable escape is needed for a mutable converter's lease.
    func activate(mode: LanguageInputMode, root: URL?) -> sending Activation {
        guard !Task.isCancelled, let abi = mode.conversionEngineABI else {
            return .init(lease: nil, scratch: nil, status: .missingResources)
        }
        guard let root else {
            return .init(lease: nil, scratch: nil, status: .missingResources, unreadable: true)
        }
        switch LanguagePackStore(root: root).resolve(modeID: mode.rawValue, engineABI: abi) {
        case .available(let lease):
            do {
                let scratch = mode == .japaneseRomaji ? try KeyboardLanguageScratch() : nil
                let mapping: KoreanHangulComposer.KeyMapping?
                if mode == .koreanTwoSetHangul {
                    guard let bytes = try SharedConfigurationLocation.readRegularFile(
                        lease.pack.path.appendingPathComponent("mapping.json"),
                        limit: KoreanHangulComposer.KeyMapping.maximumJSONBytes + 1) else {
                        throw KeyboardLanguageResourceError.unavailable
                    }
                    mapping = try KoreanHangulLanguageConverter.prepare(mappingJSON: bytes)
                } else { mapping = nil }
                try Task.checkCancellation()
                return .init(lease: lease, scratch: scratch, status: .ready, mapping: mapping)
            } catch { return .init(lease: nil, scratch: nil, status: .failed) }
        case .unreadable:
            return .init(lease: nil, scratch: nil, status: .missingResources, unreadable: true)
        case .absent, .missing:
            return .init(lease: nil, scratch: nil, status: .missingResources)
        case .incompatible, .corrupt:
            return .init(lease: nil, scratch: nil, status: .failed)
        }
    }

    /// No cached reader survives a mode switch. Cancellation is checked before
    /// opening queued work; an already-running bounded read closes on return.
    func refreshIndex(directory: URL?) -> UUID? {
        guard !Task.isCancelled, let directory else { return nil }
        return (try? CustomInputDictionaryIndex(directory: directory))?.revision
    }

    func lookup(directory: URL?, expectedRevision: UUID?, mode: LanguageInputMode,
                normalizedReading: String?) -> [CustomInputDictionaryIndexedCandidate] {
        guard !Task.isCancelled, mode.supportsConversionMyWords,
              let directory, let expectedRevision, let normalizedReading,
              let index = try? CustomInputDictionaryIndex(directory: directory),
              index.revision == expectedRevision else { return [] }
        return (try? index.lookup(modeID: mode.rawValue, normalizedReading: normalizedReading)) ?? []
    }
}
