import Foundation
import Combine

struct MyWordsImportReview: Identifiable {
    let id = UUID()
    let fileURL: URL
    let filename: String
    let byteCount: Int
    let name: String
    let mode: LanguageInputMode
    let preview: CustomInputDictionaryPreview
}

struct MyWordsShare: Identifiable {
    let id = UUID()
    let urls: [URL]
    let directory: URL
}

/// App-only serial executor. Store construction, full JSON decoding, validation,
/// file access and export all run here, never on the main actor or in the keyboard.
/// The injected rules must be immutable and safe to call on this executor.
private final class MyWordsExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ad.neko.uniboard.my-words", qos: .userInitiated)
    private let directory: URL?
    private let rules: CustomInputDictionaryRules

    init(directory: URL?, rules: CustomInputDictionaryRules) {
        self.directory = directory
        self.rules = rules
    }

    func run<T>(_ work: @escaping (CustomInputDictionaryStore, CustomInputDictionaryRules) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let directory = self.directory else {
                    continuation.resume(throwing: MyWordsError.storageUnavailable)
                    return
                }
                do {
                    let store = CustomInputDictionaryStore(directory: directory, rules: self.rules)
                    continuation.resume(returning: try work(store, self.rules))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private enum MyWordsError: Error { case storageUnavailable, exampleUnavailable, wrongFileType }

@MainActor
final class MyWordsModel: ObservableObject {
    @Published private(set) var snapshot = CustomInputDictionarySnapshot.empty
    @Published private(set) var isBusy = false
    @Published private(set) var isMutating = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var supportedModes: Set<LanguageInputMode> = []
    /// Optional app-manager status (for example "Language download required").
    /// The parent updates these from its actual resource/access state; the words
    /// store cannot infer download readiness from reading-parser support.
    @Published var modeNotices: [LanguageInputMode: String] = [:]
    @Published private(set) var recentImportName: String?
    @Published private(set) var recentImportDate: Date?
    @Published private(set) var undoInvalidationReason: String?
    enum ChoicesPhase: Equatable {
        case idle, checking, rebuilding, stale, failed, unreadable, updated, sourceUnreadable
    }
    /// Explicit phases: isBusy also covers exports/import review and cannot
    /// truthfully describe keyboard preparation.
    @Published private(set) var choicesPhase: ChoicesPhase = .idle
    @Published private(set) var sourceReadable = false
    @Published private(set) var needsIndexRetry = false
    private var phaseTask: Task<Void, Never>?
    static let editableModes: [LanguageInputMode] = [.direct, .japaneseRomaji, .mandarinPinyin]

    nonisolated static func search(snapshot: CustomInputDictionarySnapshot, query: String, modeID: String?) async -> MyWordsSearchResult {
        await Task.detached(priority: .userInitiated) {
            MyWordsPresentation.search(snapshot, query: query, modeID: modeID)
        }.value
    }

    private func setChoicesPhase(_ phase: ChoicesPhase) {
        phaseTask?.cancel()
        choicesPhase = phase
        if phase == .updated {
            phaseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                self?.choicesPhase = .idle
            }
        }
    }

    private func beginChecking() {
        setChoicesPhase(.idle)
        phaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.choicesPhase = .checking
        }
    }

    func dismissUpdatedChoices() {
        if choicesPhase == .updated { setChoicesPhase(.idle) }
    }
    private var undoRevision: UUID?
    private let executor: MyWordsExecutor
    private let didMutate: () async throws -> Void

    /// The parent supplies the actual app-group directory and audited parsers.
    /// didMutate rebuilds/publishes the parent's bounded keyboard index. It must
    /// perform its own heavy work off-main; no full JSON reader belongs in a keyboard.
    init(directory: URL?, rules: CustomInputDictionaryRules,
         didMutate: @escaping () async throws -> Void) {
        executor = MyWordsExecutor(directory: directory, rules: rules)
        self.didMutate = didMutate
    }

    var canUndoImport: Bool { undoRevision == snapshot.revision }
    var enabledEntryCount: Int { snapshot.enabledCollections.reduce(0) { $0 + $1.entries.count } }

    func clearError() {
        if choicesPhase != .sourceUnreadable && choicesPhase != .failed && choicesPhase != .unreadable { errorMessage = nil }
    }
    func reportFileError() { errorMessage = "Couldn’t open the selected file. Choose a UTF-8 .tsv or .txt file and try again." }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        beginChecking()
        defer { isBusy = false }
        do {
            let result = try await executor.run { store, rules in
                let source = try store.snapshot()
                // Index failure must not hide a successfully validated source.
                let indexState = Result { try store.indexNeedsRebuild(for: source.revision) }
                return (source, Set([LanguageInputMode.direct, .japaneseRomaji, .mandarinPinyin].filter { rules.supports(modeID: $0.rawValue) }), indexState)
            }
            if let undoRevision, undoRevision != result.0.revision { invalidateUndo() }
            snapshot = result.0
            supportedModes = result.1
            hasLoaded = true
            sourceReadable = true
            errorMessage = nil
            switch result.2 {
            case .success(let needsRetry):
                needsIndexRetry = needsRetry
                setChoicesPhase(needsRetry ? .stale : .idle)
            case .failure:
                needsIndexRetry = true
                setChoicesPhase(.unreadable)
                errorMessage = "Keyboard choices couldn’t be read. Your saved dictionaries haven’t been changed."
            }
        } catch {
            sourceReadable = false
            needsIndexRetry = false
            setChoicesPhase(.sourceUnreadable)
            present(error)
        }
    }

    func validate(reading: String, output: String, weight: String, mode: LanguageInputMode) async -> String? {
        guard !weight.isEmpty, weight.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(weight) else {
            return LanguageInputCopy.message(CustomInputDictionaryValidationIssue.invalidWeight)
        }
        guard Self.editableModes.contains(mode) else { return "This input mode isn’t available for custom words." }
        do {
            return try await executor.run { _, rules in
                switch rules.validate(reading: reading, output: output, weight: number, modeID: mode.rawValue) {
                case .success: return nil
                case .failure(let issue): return LanguageInputCopy.message(issue)
                }
            }
        } catch { return "Dictionary storage isn’t available. Try again from My Words." }
    }

    func create(name: String, mode: LanguageInputMode) async -> Bool {
        guard supportedModes.contains(mode), Self.editableModes.contains(mode) else {
            errorMessage = mode == .koreanRomaja ? LanguageInputCopy.koreanPending : "This input mode isn’t available for custom words."
            return false
        }
        let revision = snapshot.revision
        return await mutate { store in
            try store.createCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines), modeID: mode.rawValue,
                                       enabled: false, expectedRevision: revision)
        }
    }

    func rename(id: UUID, name: String, revision: UUID) async -> Bool {
        await mutate { try $0.renameCollection(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), expectedRevision: revision) }
    }

    func setEnabled(id: UUID, enabled: Bool) async {
        if enabled, let collection = snapshot.collections.first(where: { $0.id == id }),
           !Self.editableModes.contains(where: { $0.rawValue == collection.modeID }) {
            errorMessage = "This input mode isn’t available for custom words."
            return
        }
        let revision = snapshot.revision
        _ = await mutate { try $0.setEnabled(id: id, enabled: enabled, expectedRevision: revision) }
    }

    func remove(id: UUID, revision: UUID) async -> Bool {
        await mutate { try $0.removeCollection(id: id, expectedRevision: revision) }
    }

    func saveEntry(collectionID: UUID, index: Int?, reading: String, output: String, weight: Int, revision: UUID, expectedIdentity: CustomInputDictionaryEntryIdentity? = nil) async -> Bool {
        await mutate { store in
            if let index {
                try Self.verifyIdentity(store: store, collectionID: collectionID, index: index, revision: revision, expected: expectedIdentity)
                return try store.editEntry(collectionID: collectionID, index: index, reading: reading, output: output,
                                           weight: weight, expectedRevision: revision)
            }
            return try store.addEntry(collectionID: collectionID, reading: reading, output: output,
                                      weight: weight, expectedRevision: revision)
        }
    }

    func deleteEntry(collectionID: UUID, index: Int, revision: UUID, expectedIdentity: CustomInputDictionaryEntryIdentity? = nil) async -> Bool {
        await mutate { store in
            try Self.verifyIdentity(store: store, collectionID: collectionID, index: index, revision: revision, expected: expectedIdentity)
            return try store.deleteEntry(collectionID: collectionID, index: index, expectedRevision: revision)
        }
    }

    nonisolated private static func verifyIdentity(store: CustomInputDictionaryStore, collectionID: UUID, index: Int,
                                                    revision: UUID, expected: CustomInputDictionaryEntryIdentity?) throws {
        guard let expected else { return }
        let source = try store.snapshot()
        guard source.revision == revision,
              let collection = source.collections.first(where: { $0.id == collectionID }),
              collection.entries.indices.contains(index), collection.entries[index].identity == expected else {
            throw CustomInputDictionaryStoreError.revisionConflict(expected: revision, actual: source.revision)
        }
        // Mutation itself still uses the store's locked expected-revision CAS.
    }

    func review(fileURL: URL, mode: LanguageInputMode, name: String) async -> MyWordsImportReview? {
        guard !isBusy else { return nil }
        guard supportedModes.contains(mode), Self.editableModes.contains(mode) else {
            errorMessage = mode == .koreanRomaja ? LanguageInputCopy.koreanPending : "This input mode isn’t available for custom words."
            return nil
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let review = try await executor.run { store, _ in
                guard ["tsv", "txt"].contains(fileURL.pathExtension.lowercased()) else { throw MyWordsError.wrongFileType }
                let access = fileURL.startAccessingSecurityScopedResource()
                defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
                let preview = try store.preview(fileURL: fileURL, modeID: mode.rawValue)
                let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let suggested = fileURL.deletingPathExtension().lastPathComponent
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return MyWordsImportReview(fileURL: fileURL, filename: fileURL.lastPathComponent, byteCount: size,
                                           name: trimmedName.isEmpty ? suggested : trimmedName, mode: mode, preview: preview)
            }
            return review
        } catch { present(error); return nil }
    }

    func apply(_ review: MyWordsImportReview, name: String, enabled: Bool) async -> Bool {
        guard Self.editableModes.contains(review.mode), review.preview.canApply else { return false }
        let succeeded = await mutate(isImport: true) { try $0.apply(review.preview, name: name.trimmingCharacters(in: .whitespacesAndNewlines), enabled: enabled) }
        if succeeded {
            undoRevision = snapshot.revision
            recentImportName = snapshot.collections.last?.name
            recentImportDate = Date()
            undoInvalidationReason = nil
            statusMessage = "Dictionary imported"
        }
        return succeeded
    }

    func undoImport() async -> Bool {
        let revision = snapshot.revision
        let succeeded = await mutate(isImport: true) { try $0.undoLastImport(expectedRevision: revision) }
        if succeeded {
            undoRevision = nil
            recentImportName = nil
            recentImportDate = nil
            statusMessage = "Dictionary import undone"
        }
        return succeeded
    }

    /// Also allows recovery of the store's persisted one-step Undo after relaunch.
    /// The store checks its marker and revision; no newer edit can be rolled back.
    func recoverLastImportUndo() async -> Bool { await undoImport() }

    func export(id: UUID) async -> MyWordsShare? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            return try await executor.run { store, _ in
                let snapshot = try store.snapshot()
                guard let collection = snapshot.collections.first(where: { $0.id == id }) else { throw CustomInputDictionaryStoreError.collectionNotFound }
                guard !collection.entries.isEmpty else { throw CustomInputDictionaryStoreError.invalidPreview }
                let parts = try CustomInputDictionaryExport.tsvParts(collection)
                let safeName = String(collection.name.unicodeScalars.map {
                    CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "_"
                }.joined().prefix(70))
                return try Self.writeShare(parts: parts, basename: safeName.isEmpty ? "dictionary" : safeName)
            }
        } catch { present(error); return nil }
    }

    func example(mode: LanguageInputMode) async -> MyWordsShare? {
        guard !isBusy, Self.editableModes.contains(mode) else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            return try await executor.run { _, rules in
                let basename: String
                switch mode {
                case .direct: basename = "english"
                case .japaneseRomaji: basename = "japanese"
                case .mandarinPinyin: basename = "mandarin"
                default: throw MyWordsError.exampleUnavailable
                }
                guard let url = Bundle.main.url(forResource: basename, withExtension: "tsv", subdirectory: "LanguageExamples")
                    ?? Bundle.main.url(forResource: basename, withExtension: "tsv") else { throw MyWordsError.exampleUnavailable }
                let data = try Data(contentsOf: url)
                let preview = CustomInputDictionaryParser.preview(data: data, modeID: mode.rawValue, baseRevision: .init(),
                                                                  existingEntryCount: 0, rules: rules)
                guard preview.canApply else { throw MyWordsError.exampleUnavailable }
                return try Self.writeShare(parts: [data], basename: "uniboard-\(basename)-example")
            }
        } catch { present(error); return nil }
    }

    func cleanShare(_ share: MyWordsShare) async {
        _ = try? await executor.run { _, _ in try FileManager.default.removeItem(at: share.directory) }
    }

    func retryIndex() async {
        guard !isBusy, sourceReadable else { return }
        isBusy = true
        defer { isBusy = false }
        await rebuildIndex()
    }

    private func mutate(isImport: Bool = false, _ action: @escaping (CustomInputDictionaryStore) throws -> CustomInputDictionarySnapshot) async -> Bool {
        guard !isBusy, hasLoaded, sourceReadable else { return false }
        isBusy = true
        isMutating = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false; isMutating = false }
        do {
            snapshot = try await executor.run { store, _ in try action(store) }
            if !isImport { invalidateUndo() }
            // The snapshot is already committed. A compiler failure must NOT be
            // reported as a failed save or as "Your words haven’t changed."
            await rebuildIndex()
            return true
        } catch {
            present(error)
            if case CustomInputDictionaryStoreError.undoConflict = error { invalidateUndo() }
            if case CustomInputDictionaryStoreError.noImportToUndo = error { invalidateUndo() }
            if case CustomInputDictionaryStoreError.revisionConflict = error {
                if let latest = try? await executor.run({ store, _ in try store.snapshot() }) { snapshot = latest }
                invalidateUndo()
            }
            return false
        }
    }

    private func rebuildIndex() async {
        // A save is already durable; neither failure nor retry rolls it back.
        // Keep the warning until actual publication has been verified off-main.
        needsIndexRetry = true
        errorMessage = nil
        setChoicesPhase(.rebuilding)
        do {
            try await didMutate()
            let result = try await executor.run { store, _ in
                let source = try store.snapshot()
                return (source, try store.indexNeedsRebuild(for: source.revision))
            }
            if let undoRevision, undoRevision != result.0.revision { invalidateUndo() }
            snapshot = result.0
            needsIndexRetry = result.1
            if !needsIndexRetry { errorMessage = nil }
            setChoicesPhase(needsIndexRetry ? .stale : .updated)
        } catch {
            switch error {
            case CustomInputDictionaryStoreError.corruptSnapshot,
                 CustomInputDictionaryStoreError.unsupportedSchema,
                 CustomInputDictionaryStoreError.snapshotTooLarge:
                sourceReadable = false
                needsIndexRetry = false
                setChoicesPhase(.sourceUnreadable)
                present(error)
            default: presentIndexError()
            }
        }
    }

    private func presentIndexError() {
        setChoicesPhase(.failed)
        errorMessage = "Your saved words couldn’t be prepared for the keyboard. Your dictionaries haven’t changed."
    }

    private func invalidateUndo() {
        if undoRevision != nil { undoInvalidationReason = LanguageInputCopy.undoUnavailable }
        undoRevision = nil
        recentImportName = nil
        recentImportDate = nil
    }

    private func present(_ error: Error) {
        switch error {
        case MyWordsError.storageUnavailable: errorMessage = "Shared dictionary storage isn’t available. Your words haven’t been changed. Try again after reopening Uniboard."
        case MyWordsError.exampleUnavailable: errorMessage = "This example isn’t available for the current spelling rules. No words have been imported."
        case MyWordsError.wrongFileType: errorMessage = "Choose a UTF-8 .tsv or .txt file."
        default: errorMessage = LanguageInputCopy.message(error)
        }
    }

    nonisolated private static func writeShare(parts: [Data], basename: String) throws -> MyWordsShare {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uniboard-words-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let urls = try parts.enumerated().map { index, data in
                let suffix = parts.count > 1 ? "-part-\(index + 1)-of-\(parts.count)" : ""
                let url = directory.appendingPathComponent("\(basename)\(suffix).tsv")
                try data.write(to: url, options: .atomic)
                return url
            }
            return MyWordsShare(urls: urls, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
