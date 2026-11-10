import Foundation
import Combine
import CryptoKit

@MainActor
final class LanguageManagementModel: ObservableObject {
    enum Operation: Equatable, Sendable {
        case idle, waiting, checkingStorage(requiredBytes: Int64), downloading(Double), retrying(attempt: Int)
        case verifying, compiling(MandarinCompilationProgress), activating, removing
        var isBusy: Bool { self != .idle }
        var canCancel: Bool {
            switch self { case .waiting, .checkingStorage, .downloading, .retrying, .verifying, .compiling: return true; default: return false }
        }
    }

    enum StorageState: Equatable, Sendable {
        case checking, requirementUnknown
        case assessed(LanguagePackSpacePlan.Assessment)
        var permitsDownload: Bool {
            if case .assessed(.sufficient) = self { return true }
            return false
        }
        var requiredBytes: Int64? {
            switch self {
            case .assessed(.sufficient(let required, _)), .assessed(.insufficient(let required, _)),
                 .assessed(.unknown(let required)): return required
            default: return nil
            }
        }
        var availableBytes: Int64? {
            switch self {
            case .assessed(.sufficient(_, let available)), .assessed(.insufficient(_, let available)): return available
            default: return nil
            }
        }
    }
    @Published private(set) var storage: [LanguageInputMode: StorageState] = [:]
    @Published private(set) var isCancelling = false
    @Published private(set) var retryAttempt = 0
    @Published private(set) var cancelledMode: LanguageInputMode?
    private var storageGenerations: [LanguageInputMode: UUID] = [:]
    private var compilationTask: Task<Void, Never>?
    private var pendingCompilation: Operation?
    private var lastCompilationEmission: TimeInterval = -.infinity
    private(set) var lastCompilationProgress: MandarinCompilationProgress?

    @Published private(set) var catalog: LanguagePackCatalog?
    @Published private(set) var mandarinDatabaseBytes: Int64?
    @Published private(set) var preferences = LanguageInputSettings.Value.defaults
    /// The shared last-chosen mode (`LanguageInputLastMode`): the keyboard opens
    /// in it, and a space-bar choice in the keyboard shows up here. Never exported.
    @Published private(set) var selectedMode: LanguageInputMode = .direct
    @Published private(set) var installed: [LanguageInputMode: ValidatedInstalledLanguagePack] = [:]
    /// Valid pointer authority for removal, deliberately independent of readiness.
    @Published private(set) var removable: [LanguageInputMode: LanguagePackStore.RemovablePublication] = [:]
    @Published private(set) var resourceProblems: [LanguageInputMode: String] = [:]
    @Published private(set) var failures: [LanguageInputMode: String] = [:]
    @Published private(set) var operation: Operation = .idle
    @Published private(set) var operatingMode: LanguageInputMode?
    @Published private(set) var isChecking = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var notice: String?

    /// Parent may post its cross-process settings notification here. No typed data.
    var onChange: (() -> Void)?
    private let worker: LanguageManagementWorker
    private let lastMode: LanguageInputLastMode
    /// Bumped by every write of the shared mode, so a refresh that read the
    /// stored value before a newer select() can't restore the older value.
    private var selectionGeneration = 0
    private var transfer: Task<Void, Never>?
    private var generation = UUID()
    private var progressGate = LanguageManagementProgressGate()

    // Default is the measured full-corpus output for the exact pinned compiler,
    // not a guessed generic SQLite size. Installation checks its actual size.
    init(root: URL?, settings: LanguageInputSettings = .shared,
         lastMode: LanguageInputLastMode = .shared,
         mandarinDatabaseBytes: Int64? = LanguagePackCatalog.measuredMandarinDatabaseBytes,
         capacity: @escaping LanguagePackSpacePlan.CapacityProvider = { LanguagePackSpacePlan.availableCapacity(at: $0) }) {
        worker = LanguageManagementWorker(root: root, settings: settings, lastMode: lastMode, capacity: capacity)
        self.lastMode = lastMode
        self.mandarinDatabaseBytes = mandarinDatabaseBytes
        // selectedMode starts at Direct; the first refresh() adopts the stored
        // mode once it knows that mode is downloaded and enabled (canSelect).
    }

    /// Only supply the measured full-corpus SQLite size from the audited compiler
    /// run, never a fixture estimate. Until supplied, Mandarin Download stays gated.
    func configureMandarinDatabaseBytes(_ bytes: Int64) {
        guard !hasOperation, bytes > 0, bytes < LanguagePackDescriptor.maximumInstalledBytes else { return }
        mandarinDatabaseBytes = bytes
    }

    var hasOperation: Bool { operation.isBusy || isSaving || isChecking }
    func isReady(_ mode: LanguageInputMode) -> Bool { mode == .direct || installed[mode] != nil }
    func isEnabled(_ mode: LanguageInputMode) -> Bool { preferences.isEnabled(mode) }
    func canSelect(_ mode: LanguageInputMode) -> Bool { isReady(mode) && isEnabled(mode) && mode != .koreanRomaja }
    /// A choice here is the shared last-chosen mode; the keyboard follows it.
    func select(_ mode: LanguageInputMode) {
        guard canSelect(mode) else { return }
        selectedMode = mode
        remember(mode)
    }

    /// Records the shared value and posts the existing payload-free notice.
    /// A failed write leaves the keyboard's own choice; nothing else changes.
    private func remember(_ mode: LanguageInputMode) {
        selectionGeneration += 1
        lastMode.save(mode)
        onChange?()
    }

    /// Every place that drops a mode (no longer selectable, turned off or
    /// removed) also stores Direct Typing, but only when the dropped mode is
    /// what's stored: a newer keyboard choice of another mode is kept.
    private func resetSelectionIfUnselectable(dropping extra: LanguageInputMode? = nil) {
        var dropped = extra.map { [$0] } ?? []
        if !canSelect(selectedMode) {
            if selectedMode != .direct { dropped.append(selectedMode) }
            selectedMode = .direct
        }
        guard !dropped.isEmpty else { return }
        let stored = lastMode.load()
        if dropped.contains(where: { LanguageInputChoicePolicy.appShouldStoreDirect(stored: stored, dropped: $0) }) {
            remember(.direct)
        }
    }

    func status(_ mode: LanguageInputMode) -> String {
        if mode == .direct { return "Always available" }
        if mode == .koreanRomaja { return "Pending spelling decision · Unavailable" }
        if operatingMode == mode {
            if isCancelling { return "Cancelling download…" }
            switch operation {
            case .waiting: return "Waiting"
            case .checkingStorage: return "Checking available storage…"
            case .retrying: return "Waiting to try again…"
            case .downloading(let fraction): return "Downloading… \(Int(fraction * 100))%"
            case .verifying: return "Checking downloaded files…"
            case .compiling(let progress):
                switch progress {
                case .verifyingSources: return "Checking downloaded files…"
                case .preparingMappings: return "Preparing character conversions…"
                case .rows: return "Preparing vocabulary…"
                case .indexing: return "Finishing preparation…"
                case .finalCheck: return "Checking prepared language files…"
                }
            case .activating: return "Installing language download…"
            case .removing: return "Removing download…"
            case .idle: break
            }
        }
        if isReady(mode) { return isEnabled(mode) ? "Ready to use · Enabled" : "Ready to use · Off" }
        if let problem = resourceProblems[mode] { return problem }
        if mode == .mandarinPinyin && mandarinDatabaseBytes == nil { return "Installation size verification pending" }
        return isChecking ? "Checking download…" : "Language download required"
    }

    func refresh() {
        guard !hasOperation else { return }
        isChecking = true
        let generation = selectionGeneration
        Task {
            let result = await worker.snapshot()
            preferences = result.preferences
            installed = result.installed
            removable = result.removable
            resourceProblems = result.problems
            if let value = result.catalog { catalog = value }
            if let problem = result.catalogProblem { errorMessage = problem }
            // Follow a choice made in the keyboard; a stored mode that isn't
            // selectable here is left stored (the keyboard also ignores it).
            // Skipped when select() wrote a newer value while this was reading.
            if selectionGeneration == generation, let stored = result.lastMode, canSelect(stored) { selectedMode = stored }
            resetSelectionIfUnselectable()
            isChecking = false
        }
    }

    func setEnabled(_ enabled: Bool, for mode: LanguageInputMode) {
        guard !hasOperation, mode != .direct, mode != .koreanRomaja,
              !enabled || isReady(mode) else { return }
        save(.enabled(mode, enabled))
    }

    /// System English word suggestions are local. Both preferences start OFF.
    func setEnglishSuggestions(_ enabled: Bool) { save(.suggestions(enabled)) }
    func setEnglishAutocorrection(_ enabled: Bool) { save(.autocorrection(enabled)) }

    private func save(_ change: LanguageManagementWorker.PreferenceChange) {
        guard !hasOperation else { return }
        isSaving = true
        Task {
            do {
                preferences = try await worker.save(change)
                if case .enabled(let mode, false) = change { resetSelectionIfUnselectable(dropping: mode) }
                else { resetSelectionIfUnselectable() }
                onChange?()
            } catch { errorMessage = "Couldn’t save language settings. Your change hasn’t been saved. Try again." }
            isSaving = false
        }
    }

    func checkStorage(for mode: LanguageInputMode) {
        guard !hasOperation else { return }
        let token = UUID()
        storageGenerations[mode] = token
        storage[mode] = .checking
        let catalog = catalog, databaseBytes = mandarinDatabaseBytes
        Task {
            let result = await worker.assessStorage(mode: mode, catalog: catalog, databaseBytes: databaseBytes)
            guard storageGenerations[mode] == token else { return }
            storage[mode] = result
        }
    }

    func downloadJapanese() { download(.japaneseRomaji) }
    func downloadMandarin() { download(.mandarinPinyin) }
    func downloadKoreanTwoSet() { download(.koreanTwoSetHangul) }

    private func download(_ mode: LanguageInputMode) {
        guard !hasOperation, let catalog,
              (mode != .koreanTwoSetHangul || catalog.koreanTwoSet != nil),
              (mode != .mandarinPinyin || mandarinDatabaseBytes != nil) else { return }
        let token = beginDownloadOperation(mode)
        storage[mode] = .checking
        let databaseBytes = mandarinDatabaseBytes
        transfer = Task { [self] in
            do {
                // A fresh off-main check at the explicit action, not a cached permission.
                let result = await worker.assessStorage(mode: mode, catalog: catalog, databaseBytes: databaseBytes)
                try Task.checkCancellation()
                guard generation == token else { return }
                storage[mode] = result
                guard result.permitsDownload else {
                    operation = .idle; operatingMode = nil; transfer = nil
                    return
                }
                let progress = progressHandler(token: token, mode: mode)
                let pack: ValidatedInstalledLanguagePack
                switch mode {
                case .japaneseRomaji:
                    pack = try await worker.downloadJapanese(catalog.japanese, progress: progress)
                case .koreanTwoSetHangul:
                    guard let descriptor = catalog.koreanTwoSet else { throw LanguageManagementWorker.WorkerError.unavailable }
                    pack = try await worker.downloadArchive(descriptor, archiveRoot: "hangul-2set-1", progress: progress)
                case .mandarinPinyin:
                    guard let databaseBytes else { throw LanguageManagementWorker.WorkerError.unavailable }
                    pack = try await worker.downloadMandarin(catalog, expectedDatabaseBytes: databaseBytes, progress: progress)
                case .direct, .koreanRomaja: throw LanguageManagementWorker.WorkerError.unavailable
                }
                guard generation == token else { return }
                installed[mode] = pack
                removable[mode] = .init(modeID: pack.descriptor.modeID, revision: pack.revision)
                resourceProblems[mode] = nil
                // Publication won a cancellation race: report real readiness, never false cancellation.
                notice = "Download ready. Enable Use in Keyboard when you want to use it."
                onChange?()
            } catch {
                guard generation == token else { return }
                if Self.isCancellation(error) {
                    cancelledMode = mode
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        guard let self, self.generation == token else { return }
                        self.cancelledMode = nil
                    }
                } else {
                    failures[mode] = Self.downloadMessage(error, hasCurrent: removable[mode] != nil)
                    if let space = error as? LanguagePackSpacePlan.SpaceError {
                        switch space {
                        case .capacityUnknown(let required): storage[mode] = .assessed(.unknown(required: required))
                        case .insufficient(let required, let available): storage[mode] = .assessed(.insufficient(required: required, available: available))
                        case .invalidEstimate: storage[mode] = .requirementUnknown
                        }
                    }
                }
            }
            finishDownloadOperation(token)
        }
    }

    /// The real lifecycle seam, also exercised by callback-order tests.
    @discardableResult
    func beginDownloadOperation(_ mode: LanguageInputMode) -> UUID {
        let token = UUID(); generation = token; progressGate.begin(token)
        storageGenerations[mode] = token
        failures[mode] = nil; notice = nil; cancelledMode = nil; isCancelling = false; retryAttempt = 0
        pendingCompilation = nil; compilationTask?.cancel(); compilationTask = nil
        lastCompilationEmission = -.infinity; lastCompilationProgress = nil
        operatingMode = mode; operation = .waiting
        return token
    }

    func finishDownloadOperation(_ token: UUID) {
        guard generation == token else { return }
        compilationTask?.cancel(); compilationTask = nil; pendingCompilation = nil
        isCancelling = false; operation = .idle; operatingMode = nil; transfer = nil
    }

    func acceptProgress(_ update: Operation, token: UUID, mode: LanguageInputMode, sequence: Int) {
        guard generation == token, operatingMode == mode,
              progressGate.accept(generation: token, sequence: sequence,
                  isActive: operation.isBusy, isCancelled: isCancelling || transfer?.isCancelled == true) else { return }
        receiveProgress(update, token: token)
    }

    /// Sequence stamped synchronously at emission, before the MainActor hop.
    /// Late callbacks cannot regress phases, revive a finished/cancelled operation,
    /// or overwrite a later user operation (even for the same language).
    private func progressHandler(token: UUID, mode: LanguageInputMode) -> @Sendable (Operation) -> Void {
        let sequence = LanguageManagementProgressSequence()
        return { [weak self] update in
            let number = sequence.next()
            Task { @MainActor in
                self?.acceptProgress(update, token: token, mode: mode, sequence: number)
            }
        }
    }

    /// Coalesce all compiler events to at most four UI updates per second.
    /// Retain the newest real event; generation/cancellation guards also apply to
    /// the trailing delivery. Non-compilation boundaries never wait for a timer.
    private func receiveProgress(_ update: Operation, token: UUID) {
        if case .retrying(let attempt) = update { retryAttempt = attempt }
        guard case .compiling(let progress) = update else {
            compilationTask?.cancel(); compilationTask = nil; pendingCompilation = nil
            operation = update
            return
        }
        lastCompilationProgress = progress
        pendingCompilation = update
        let elapsed = ProcessInfo.processInfo.systemUptime - lastCompilationEmission
        if elapsed >= 0.25 {
            compilationTask?.cancel(); compilationTask = nil
            operation = update; pendingCompilation = nil
            lastCompilationEmission = ProcessInfo.processInfo.systemUptime
        } else if compilationTask == nil {
            compilationTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64((0.25 - elapsed) * 1_000_000_000)) }
                catch { return }
                guard let self, self.generation == token, !self.isCancelling,
                      self.operation.isBusy, let pending = self.pendingCompilation else { return }
                self.operation = pending; self.pendingCompilation = nil; self.compilationTask = nil
                self.lastCompilationEmission = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    func canRemove(_ mode: LanguageInputMode) -> Bool {
        guard removable[mode] != nil else { return false }
        return installed[mode] != nil || ["Download couldn’t be verified", "Compatible download required"].contains(resourceProblems[mode] ?? "")
    }

    /// Capture this when presenting confirmation, not when the user confirms.
    func removalRequest(for mode: LanguageInputMode) -> LanguagePackStore.RemovablePublication? {
        guard !hasOperation, canRemove(mode) else { return nil }
        return removable[mode]
    }

    func cancelDownload() {
        if operation.canCancel {
            isCancelling = true
            compilationTask?.cancel(); compilationTask = nil; pendingCompilation = nil
            transfer?.cancel()
        }
    }

    func remove(_ publication: LanguagePackStore.RemovablePublication) {
        guard !hasOperation, let mode = LanguageInputMode(rawValue: publication.modeID) else { return }
        guard removable[mode] == publication else {
            errorMessage = "This language download has changed. Check it and confirm removal again."
            return
        }
        operatingMode = mode; operation = .removing; notice = nil
        Task {
            do {
                // Preferences are saved before deactivation. Live keyboard readers
                // retain their immutable read lease; no files are deleted beneath them.
                preferences = try await worker.save(.enabled(mode, false))
                resetSelectionIfUnselectable(dropping: mode) // Not selectable once turned off.
                onChange?()
                try await worker.remove(publication)
                installed[mode] = nil; removable[mode] = nil; failures[mode] = nil
                resourceProblems[mode] = nil
                notice = "Download removed. Your words in My Words have been kept."
                onChange?()
            } catch {
                if case LanguagePackError.revisionConflict = error {
                    errorMessage = "This language download changed. Review it in Languages and try again."
                } else {
                    errorMessage = "Couldn’t remove the language download. It may now be Off. Your words in My Words have been kept. Try again."
                }
                let current = await worker.snapshot()
                preferences = current.preferences; installed = current.installed
                removable = current.removable; resourceProblems = current.problems
                resetSelectionIfUnselectable()
            }
            operation = .idle; operatingMode = nil
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? LanguagePackDownloadError, error == .cancelled { return true }
        if let error = error as? LanguagePackArchiveError, error == .cancelled { return true }
        if let error = error as? MandarinDictionaryError, error == .cancelled { return true }
        return false
    }

    private static func downloadMessage(_ error: Error, hasCurrent: Bool) -> String {
        let unchanged = hasCurrent ? " Your current language download hasn’t changed." : " It hasn’t been enabled."
        if let space = error as? LanguagePackSpacePlan.SpaceError {
            switch space {
            case .capacityUnknown:
                return "Available storage couldn’t be checked. No download was started. Try again." + unchanged
            case .insufficient:
                return "There isn’t enough storage to prepare this download. Free some space and try again." + unchanged
            case .invalidEstimate: return "This download’s storage requirement couldn’t be verified." + unchanged
            }
        }
        if let error = error as? LanguagePackDownloadError {
            switch error {
            case .network(let code):
                return (code == NSURLErrorNotConnectedToInternet ? "You’re offline. Connect to the internet and try again." : "The download couldn’t finish. Check your connection and try again.") + unchanged
            case .verification, .invalidSource, .rejectedRedirect:
                return "This download couldn’t be verified." + unchanged
            case .storage(_, let code) where code == NSFileWriteOutOfSpaceError || code == 28:
                return "There isn’t enough storage for this download. Free some space and try again." + unchanged
            case .httpStatus: return "The source couldn’t provide this download. Try again later." + unchanged
            default: break
            }
        }
        let ns = error as NSError
        if ns.code == NSFileWriteOutOfSpaceError || ns.code == 28 {
            return "There isn’t enough storage for this download. Free some space and try again." + unchanged
        }
        return "This download couldn’t be installed or verified. Try again." + unchanged
    }
}

/// All catalog decoding, preference I/O, full-pack hashing, extraction and store
/// operations are confined to this worker, never the main/UI executor.
actor LanguageManagementWorker {
    enum PreferenceChange: Sendable {
        case enabled(LanguageInputMode, Bool), suggestions(Bool), autocorrection(Bool)
    }
    struct Snapshot: Sendable {
        let preferences: LanguageInputSettings.Value
        let installed: [LanguageInputMode: ValidatedInstalledLanguagePack]
        let removable: [LanguageInputMode: LanguagePackStore.RemovablePublication]
        let problems: [LanguageInputMode: String]
        let catalog: LanguagePackCatalog?
        let catalogProblem: String?
        /// The shared last-chosen mode; nil when it couldn't be read.
        var lastMode: LanguageInputMode? = nil
    }
    private let root: URL?
    private let settings: LanguageInputSettings
    private let lastMode: LanguageInputLastMode
    private let capacity: LanguagePackSpacePlan.CapacityProvider
    init(root: URL?, settings: LanguageInputSettings, lastMode: LanguageInputLastMode = .shared,
         capacity: @escaping LanguagePackSpacePlan.CapacityProvider = { LanguagePackSpacePlan.availableCapacity(at: $0) }) {
        self.root = root; self.settings = settings; self.lastMode = lastMode; self.capacity = capacity
    }

    func snapshot() -> Snapshot {
        let catalog = try? LanguagePackCatalog.load()
        var installed: [LanguageInputMode: ValidatedInstalledLanguagePack] = [:]
        var removable: [LanguageInputMode: LanguagePackStore.RemovablePublication] = [:]
        var problems: [LanguageInputMode: String] = [:]
        if let root {
            let store = LanguagePackStore(root: root)
            for (mode, abi) in [(LanguageInputMode.japaneseRomaji, LanguagePackCatalog.japaneseABI),
                                (.mandarinPinyin, LanguagePackCatalog.mandarinABI),
                                (.koreanTwoSetHangul, LanguagePackCatalog.koreanABI)] {
                // Malformed/insecure pointers throw: never turn them into removal
                // authority. A valid pointer remains removable with damaged bytes.
                removable[mode] = try? store.removablePublication(modeID: mode.rawValue)
                switch store.resolve(modeID: mode.rawValue, engineABI: abi) {
                case .available(let lease):
                    defer { lease.release() }
                    do {
                        if mode == .koreanTwoSetHangul {
                            try LanguagePackCatalog.validateKoreanPayload(at: lease.pack.path, descriptor: lease.pack.descriptor)
                        }
                        installed[mode] = lease.pack
                    } catch is LanguagePackCatalog.CatalogError {
                        problems[mode] = "Download couldn’t be verified"
                    } catch is KoreanHangulComposer.KeyMapping.ValidationError {
                        problems[mode] = "Download couldn’t be verified"
                    } catch {
                        problems[mode] = "Download can’t be read"
                    }
                case .unreadable: problems[mode] = "Download can’t be read"
                case .incompatible: problems[mode] = "Compatible download required"
                case .corrupt: problems[mode] = "Download couldn’t be verified"
                // .missing means this mode has no active pointer in an existing
                // store (for example, only a sibling language was downloaded).
                // Damaged active publications resolve as .corrupt/.unreadable.
                case .missing, .absent: break
                }
            }
        } else {
            problems[.japaneseRomaji] = "Shared language storage unavailable"
            problems[.mandarinPinyin] = "Shared language storage unavailable"
            problems[.koreanTwoSetHangul] = "Shared language storage unavailable"
        }
        return Snapshot(preferences: settings.load(), installed: installed, removable: removable, problems: problems,
                        catalog: catalog, catalogProblem: catalog == nil ? "Language-download information couldn’t be loaded. Existing downloads are kept. Try again." : nil,
                        lastMode: lastMode.load())
    }

    func save(_ change: PreferenceChange) throws -> LanguageInputSettings.Value {
        var fresh = settings.load() // Never overwrite another screen with a stale snapshot.
        switch change {
        case .enabled(let mode, let enabled):
            _ = fresh.setEnabled(enabled, for: mode)
            if enabled, let root {
                let store = LanguagePackStore(root: root)
                guard let abi = LanguagePackCatalog.engineABI(for: mode) else { throw WorkerError.unavailable }
                guard case .available(let lease) = store.resolve(modeID: mode.rawValue, engineABI: abi) else {
                    throw WorkerError.unavailable
                }
                defer { lease.release() }
                let d = lease.pack.descriptor
                if mode == .koreanTwoSetHangul {
                    try LanguagePackCatalog.validateKoreanPayload(at: lease.pack.path, descriptor: d)
                }
                fresh.packReferences.removeAll { $0.mode == mode }
                fresh.packReferences.append(.init(mode: mode, packID: d.packID, version: d.version, archiveSHA256: d.archiveSHA256))
            } else if enabled { throw WorkerError.unavailable }
        case .suggestions(let enabled): fresh.englishSuggestions = enabled
        case .autocorrection(let enabled): fresh.englishAutocorrection = enabled
        }
        guard settings.save(fresh) else { throw WorkerError.saveFailed }
        return fresh
    }

    func downloadJapanese(_ descriptor: LanguagePackDescriptor,
                          progress: @escaping @Sendable (LanguageManagementModel.Operation) -> Void) async throws -> ValidatedInstalledLanguagePack {
        try await downloadArchive(descriptor, archiveRoot: LanguagePackArchive.japaneseArchiveRoot, progress: progress)
    }

    /// Same verified bounded tar.gz path; Korean is data validation, not another transport.
    func downloadArchive(_ descriptor: LanguagePackDescriptor, archiveRoot: String,
                         progress: @escaping @Sendable (LanguageManagementModel.Operation) -> Void) async throws -> ValidatedInstalledLanguagePack {
        guard let root else { throw WorkerError.unavailable }
        let store = LanguagePackStore(root: root)
        let expected = try store.activeRevision(modeID: descriptor.modeID)
        try descriptor.validate()
        let plan = try LanguagePackSpacePlan(sourceBytes: [descriptor.archiveByteCount], installedBytes: descriptor.installedBytes)
        try preflight(plan, root: root, progress: progress)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("uniboard-language-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let downloader = LanguagePackDownloader(trustedSources: [descriptor])
        let archive = try await downloader.download(source: descriptor, scratchDirectory: scratch,
            retrying: { progress(.retrying(attempt: $0)) }) { fraction in
            progress(.downloading(fraction))
        }
        try Task.checkCancellation()
        progress(.verifying)
        let data = try JSONEncoder().encode(descriptor)
        let pack = try store.install(manifestData: data, expectedRevision: expected, populate: { stage in
            try LanguagePackArchive.extract(archive: archive, descriptor: descriptor, into: stage, archiveRoot: archiveRoot)
            if descriptor.modeID == LanguageInputMode.koreanTwoSetHangul.rawValue {
                try LanguagePackCatalog.validateKoreanPayload(at: stage, descriptor: descriptor)
            }
        }, checkpoint: { checkpoint in
            try Task.checkCancellation()
            if checkpoint == .beforePointerPublication { progress(.activating) }
        })
        // Reclaim only inactive versions; a converter's lease protects lazy reads.
        try? store.reclaimUnusedVersions()
        return pack
    }

    func downloadMandarin(_ catalog: LanguagePackCatalog, expectedDatabaseBytes: Int64,
                          progress: @escaping @Sendable (LanguageManagementModel.Operation) -> Void) async throws -> ValidatedInstalledLanguagePack {
        guard let root, expectedDatabaseBytes > 0,
              expectedDatabaseBytes <= LanguagePackDescriptor.maximumInstalledBytes,
              catalog.mandarinInstalledBytes(databaseBytes: expectedDatabaseBytes) <= LanguagePackDescriptor.maximumInstalledBytes else {
            throw WorkerError.unavailable
        }
        let store = LanguagePackStore(root: root)
        let expectedRevision = try store.activeRevision(modeID: LanguageInputMode.mandarinPinyin.rawValue)
        // Validate every identity/order before capacity checks or any network work.
        let sources = try catalog.validatedMandarinSourceDescriptors()
        let plan = try LanguagePackSpacePlan(sourceBytes: sources.map(\.archiveByteCount),
            installedBytes: catalog.mandarinInstalledBytes(databaseBytes: expectedDatabaseBytes), compiledBytes: expectedDatabaseBytes)
        try preflight(plan, root: root, progress: progress)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("uniboard-mandarin-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let downloader = LanguagePackDownloader(trustedSources: sources)
        let retryBudget = LanguagePackRetryBudget() // At most two retries for ALL five files.
        var downloadedFiles: [URL] = []
        var completedBytes: Int64 = 0
        for source in sources {
            let before = completedBytes
            let total = catalog.mandarinDownloadBytes
            let url = try await downloader.download(source: source, scratchDirectory: scratch,
                retryBudget: retryBudget, retrying: { progress(.retrying(attempt: $0)) }) { fraction in
                progress(.downloading((Double(before) + Double(source.archiveByteCount) * fraction) / Double(total)))
            }
            downloadedFiles.append(url)
            completedBytes += source.archiveByteCount
        }
        try Task.checkCancellation()
        progress(.verifying)
        // Each result belongs to the validated source at the same index above.
        let mappingURLs = MandarinSimplifiedMappingURLs(characters: downloadedFiles[2],
            phrases: downloadedFiles[3], compatibility: downloadedFiles[4])
        progress(.compiling(.verifyingSources))
        let databaseURL = scratch.appendingPathComponent("Mandarin.sqlite")
        // The fixed compiler independently re-verifies ALL five input byte counts
        // and hashes, including the downloaded OpenCC mappings, before producing SQL.
        let stats = try MandarinDictionaryCompiler.compile(jichuURL: downloadedFiles[0], ziURL: downloadedFiles[1],
            mappingURLs: mappingURLs, destinationURL: databaseURL, isCancelled: { Task.isCancelled },
            progress: { progress(.compiling($0)) })
        try Task.checkCancellation()
        let index = try MandarinDictionaryIndex(url: databaseURL)
        guard try index.lookup("nihao").candidates.contains(where: { $0.text == "你好" }) else {
            throw MandarinDictionaryError.incompatibleDatabase
        }
        progress(.compiling(.finalCheck))
        let databaseFile = try Self.payloadFile(databaseURL, path: "Mandarin.sqlite")
        guard databaseFile.byteCount == expectedDatabaseBytes else { throw WorkerError.unexpectedCompiledSize }
        let licenseURL = scratch.appendingPathComponent("LICENSE.txt")
        try Data(catalog.mandarinLicense.utf8).write(to: licenseURL, options: .withoutOverwriting)
        let licenseFile = try Self.payloadFile(licenseURL, path: "LICENSE.txt")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let statistics = String(decoding: try encoder.encode(stats), as: UTF8.self)
        let allInputs = catalog.mandarinFiles.map {
            "\($0.name): \($0.bytes) bytes; SHA-256 \($0.sha256); \($0.url.absoluteString); optional downloaded source"
        }.joined(separator: "\n")
        let provenance = catalog.mandarinSource + "\n\nAll independently pinned compiler inputs:\n" + allInputs
            + "\n\nCompiler: " + MandarinDictionaryIndex.compilerVersion
            + "\nCompilation statistics: " + statistics
            + "\nThe descriptor’s singular source URL/archive size/archive hash identify ONLY the original jichu source, not an aggregate download or the compiled database. The total network transfer is 49,238,294 bytes for five optional files (jichu, zi and three OpenCC mappings). All five are downloaded only on request, not bundled, and independently verified. SQLite bytes and SHA-256 in files are derived locally after compilation by this app."
        let primary = sources[0]
        let descriptor = LanguagePackDescriptor(packID: "wanxiang-mandarin-simplified",
            version: MandarinDictionaryCompiler.corpusCommit + "-" + MandarinDictionaryIndex.compilerVersion,
            modeID: LanguageInputMode.mandarinPinyin.rawValue, engineABI: LanguagePackCatalog.mandarinABI,
            sourceURL: primary.sourceURL, allowedHosts: primary.allowedHosts,
            archiveByteCount: primary.archiveByteCount, archiveSHA256: primary.archiveSHA256,
            installedBytes: databaseFile.byteCount + licenseFile.byteCount, fileCount: 2,
            files: [databaseFile, licenseFile], licenseNotice: catalog.mandarinLicense, sourceNotice: provenance)
        try descriptor.validate()
        let pack = try store.install(manifestData: encoder.encode(descriptor), expectedRevision: expectedRevision,
            populate: { stage in
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: databaseURL, to: stage.appendingPathComponent("Mandarin.sqlite"))
                try FileManager.default.copyItem(at: licenseURL, to: stage.appendingPathComponent("LICENSE.txt"))
            }, checkpoint: { checkpoint in
                try Task.checkCancellation()
                if checkpoint == .beforePointerPublication { progress(.activating) }
            })
        try? store.reclaimUnusedVersions()
        return pack
    }

    private static func payloadFile(_ url: URL, path: String) throws -> LanguagePackDescriptor.File {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            bytes += Int64(chunk.count)
            guard bytes <= LanguagePackDescriptor.maximumInstalledBytes else { throw WorkerError.unexpectedCompiledSize }
            hash.update(data: chunk)
        }
        return .init(path: path, byteCount: bytes, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    func assessStorage(mode: LanguageInputMode, catalog: LanguagePackCatalog?, databaseBytes: Int64?) -> LanguageManagementModel.StorageState {
        guard let catalog else { return .requirementUnknown }
        do {
            let plan: LanguagePackSpacePlan
            switch mode {
            case .japaneseRomaji:
                plan = try LanguagePackSpacePlan(sourceBytes: [catalog.japanese.archiveByteCount], installedBytes: catalog.japanese.installedBytes)
            case .koreanTwoSetHangul:
                guard let descriptor = catalog.koreanTwoSet else { return .requirementUnknown }
                try LanguagePackCatalog.validateKoreanDescriptor(descriptor)
                plan = try LanguagePackSpacePlan(sourceBytes: [descriptor.archiveByteCount], installedBytes: descriptor.installedBytes)
            case .mandarinPinyin:
                guard let databaseBytes else { return .requirementUnknown }
                let sources = try catalog.validatedMandarinSourceDescriptors()
                plan = try LanguagePackSpacePlan(sourceBytes: sources.map(\.archiveByteCount),
                    installedBytes: catalog.mandarinInstalledBytes(databaseBytes: databaseBytes), compiledBytes: databaseBytes)
            case .direct, .koreanRomaja: return .requirementUnknown
            }
            guard let root else { return .assessed(.unknown(required: plan.requiredBytes)) }
            return .assessed(plan.assess(at: [root, FileManager.default.temporaryDirectory], capacity: capacity))
        } catch { return .requirementUnknown }
    }

    private func preflight(_ plan: LanguagePackSpacePlan, root: URL,
                           progress: @Sendable (LanguageManagementModel.Operation) -> Void) throws {
        try Task.checkCancellation()
        progress(.checkingStorage(requiredBytes: plan.requiredBytes))
        try plan.requireCapacity(at: [root, FileManager.default.temporaryDirectory], capacity: capacity)
        try Task.checkCancellation()
    }

    func remove(_ publication: LanguagePackStore.RemovablePublication) throws {
        guard let root else { throw WorkerError.unavailable }
        try LanguagePackStore(root: root).remove(publication)
    }
    enum WorkerError: Error { case unavailable, saveFailed, unexpectedCompiledSize }
}

/// Only the counter is shared across delegate/worker callbacks; lock protects it.
private final class LanguageManagementProgressSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

/// Value seam for deliberately reordered/late callback tests. Used on MainActor.
struct LanguageManagementProgressGate {
    private var generation = UUID()
    private var lastSequence = 0
    mutating func begin(_ generation: UUID) { self.generation = generation; lastSequence = 0 }
    mutating func accept(generation: UUID, sequence: Int, isActive: Bool, isCancelled: Bool) -> Bool {
        guard generation == self.generation, isActive, !isCancelled, sequence > lastSequence else { return false }
        lastSequence = sequence
        return true
    }
}

// Only the main app probes disk capacity; the keyboard does not download packs.
extension LanguagePackSpacePlan {
    /// Capacity is a best-effort point-in-time estimate; writes can still fail.
    /// Missing store directories are queried through their nearest existing parent.
    public static func availableCapacity(at location: URL) -> Int64? {
        guard location.isFileURL else { return nil }
        var url = location
        while !FileManager.default.fileExists(atPath: url.path) {
            guard url.path != "/" else { return nil }
            url.deleteLastPathComponent()
        }
        #if os(iOS) || os(macOS)
        return try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        #else
        return (try? FileManager.default.attributesOfFileSystem(forPath: url.path)[.systemFreeSize] as? NSNumber)?.int64Value
        #endif
    }
}
