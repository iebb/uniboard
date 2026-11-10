import Foundation

/// Immutable app/compiler state. Decode only on an app worker queue: the full
/// 50,000-entry document is NOT the extension's lookup format. The keyboard needs
/// a separately compiled, bounded per-reading index; that integration is separate.
public struct CustomInputDictionarySnapshot: Codable, Equatable, Sendable {
    public let revision: UUID
    public let collections: [CustomInputDictionaryCollection]
    public var totalEntryCount: Int { collections.reduce(0) { $0 + $1.entries.count } }
    public var enabledCollections: [CustomInputDictionaryCollection] { collections.filter(\.enabled) }

    public static let empty = CustomInputDictionarySnapshot(
        revision: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, collections: [])
}

/// Typed failures contain no readings/outputs and are not localized UI copy.
public enum CustomInputDictionaryStoreError: Error, Equatable {
    case revisionConflict(expected: UUID, actual: UUID)
    case undoConflict(actual: UUID)
    case noImportToUndo
    case invalidPreview
    case invalidName
    case validation(CustomInputDictionaryValidationIssue)
    case totalEntryLimit
    case collectionLimit
    case duplicateEntry
    case collectionNotFound
    case entryNotFound
    case corruptSnapshot
    case unsupportedSchema
    case snapshotTooLarge
}

/// App-side writer. Supply a dedicated directory in the actual app-group storage;
/// there is intentionally no default path, configuration integration or networking.
/// All writes coordinate the same snapshot URL with NSFileCoordinator, re-read
/// under the exclusive coordination, check revision, then atomically replace the
/// complete JSON. Never write this filename outside this API. Call on a worker
/// queue (I/O and up to 50,000 entries are deliberately not main-actor work).
public final class CustomInputDictionaryStore {
    public static let filename = "custom-input-dictionaries-v1.json"
    /// Not the 1 MiB import bound. JSONEncoder emits non-BMP scalars as UTF-8
    /// (4 bytes); its largest scalar representation is an escaped BMP scalar
    /// (6 bytes). A conservative bound is 50k * (2*256*6 + 128 entry metadata)
    /// + 1024 * (2*256*6 + 256 collection metadata) + 64 KiB envelope, <157 MiB.
    /// 192 MiB leaves headroom without lowering the 50k/256-scalar data limits.
    /// Collections, names and mode IDs are independently bounded. Noncanonical
    /// externally authored JSON with excessive escapes/whitespace may be refused.
    public static let maximumSnapshotBytes = 192 * 1_024 * 1_024

    private let directory: URL
    private let rules: CustomInputDictionaryRules

    public init(directory: URL, rules: CustomInputDictionaryRules) {
        self.directory = directory.standardizedFileURL
        self.rules = rules
    }

    /// Loading and previewing never create files or repair an unreadable snapshot.
    public func snapshot() throws -> CustomInputDictionarySnapshot {
        try CustomInputDictionaryDisk.read(directory: directory).snapshot
    }

    /// App-worker-only comparison against validated index metadata. Missing is
    /// retryable even for an empty source; unreadable is an error, never "current".
    public func indexNeedsRebuild(for revision: UUID) throws -> Bool {
        try CustomInputDictionaryIndex.publishedRevision(directory: directory) != revision
    }

    /// Re-read authoritative source for every attempt, not a retained UI snapshot.
    /// Compilation guards BOTH the source and prior publication at atomic rename.
    @discardableResult
    public func rebuildIndex(isCancelled: () -> Bool = { false }) throws -> CustomInputDictionaryIndexCompilation {
        let current = try snapshot()
        let expected = try CustomInputDictionaryIndex.publishedRevision(directory: directory)
        return try CustomInputDictionaryIndexCompiler.compile(snapshot: current, directory: directory,
            expectedPublishedRevision: expected, requireCurrentSource: true, isCancelled: isCancelled)
    }

    public func preview(data: Data, modeID: String) throws -> CustomInputDictionaryPreview {
        let current = try snapshot()
        return CustomInputDictionaryParser.preview(data: data, modeID: modeID, baseRevision: current.revision,
                                                   existingEntryCount: current.totalEntryCount, existingCollectionCount: current.collections.count, rules: rules)
    }

    /// Optional bounded file loader; checks size before allocation and after read.
    /// No security-scoped URL access is assumed; the app owns that access lifetime.
    public func preview(fileURL: URL, modeID: String) throws -> CustomInputDictionaryPreview {
        let current = try snapshot()
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CustomInputDictionaryStoreError.invalidPreview }
        if (values.fileSize ?? 0) > CustomInputDictionaryLimits.importBytes {
            return CustomInputDictionaryParser.preview(data: Data(count: CustomInputDictionaryLimits.importBytes + 1),
                modeID: modeID, baseRevision: current.revision, existingEntryCount: current.totalEntryCount, existingCollectionCount: current.collections.count, rules: rules)
        }
        // FileHandle caps allocation even if an external document grows after stat.
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= CustomInputDictionaryLimits.importBytes {
            let remaining = CustomInputDictionaryLimits.importBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return CustomInputDictionaryParser.preview(data: data, modeID: modeID, baseRevision: current.revision,
                                                   existingEntryCount: current.totalEntryCount, existingCollectionCount: current.collections.count, rules: rules)
    }

    /// Creates a separate collection. Preview counts/entries cannot be edited by
    /// clients, and every field is validated again before committing. Returns the
    /// new snapshot (the imported collection is last). Failure preserves old bytes.
    @discardableResult
    public func apply(_ preview: CustomInputDictionaryPreview, name: String, enabled: Bool = true) throws -> CustomInputDictionarySnapshot {
        guard preview.canApply else { throw CustomInputDictionaryStoreError.invalidPreview }
        return try mutate(expectedRevision: preview.baseRevision) { document in
            try self.validateName(name)
            guard preview.entryLineCount <= CustomInputDictionaryLimits.entryLinesPerImport,
                  preview.entries.count <= CustomInputDictionaryLimits.entryLinesPerImport,
                  self.rules.supports(modeID: preview.modeID) else { throw CustomInputDictionaryStoreError.invalidPreview }
            for entry in preview.entries { try self.validateCanonical(entry, modeID: preview.modeID) }
            let collection = CustomInputDictionaryCollection(name: name, modeID: preview.modeID, enabled: enabled,
                                                            entries: preview.entries)
            let revision = UUID()
            let next = CustomInputDictionarySnapshot(revision: revision, collections: document.snapshot.collections + [collection])
            return CustomInputDictionaryDocument(snapshot: next,
                undo: .init(importRevision: revision, collectionID: collection.id))
        }
    }

    /// One-step undo removes ONLY the last imported collection. Its marker
    /// survives app restart. Any newer manual edit/import/enable/remove revision
    /// invalidates the old undo: it never overwrites intervening changes.
    @discardableResult
    public func undoLastImport(expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try mutate(expectedRevision: expectedRevision) { document in
            guard let undo = document.undo else { throw CustomInputDictionaryStoreError.noImportToUndo }
            guard undo.importRevision == document.snapshot.revision else {
                throw CustomInputDictionaryStoreError.undoConflict(actual: document.snapshot.revision)
            }
            guard document.snapshot.collections.contains(where: { $0.id == undo.collectionID }) else {
                throw CustomInputDictionaryStoreError.corruptSnapshot
            }
            return .init(snapshot: .init(revision: UUID(), collections: document.snapshot.collections.filter { $0.id != undo.collectionID }), undo: nil)
        }
    }

    /// Empty manual collections are allowed; imported collections must be nonempty.
    @discardableResult
    public func createCollection(name: String, modeID: String, enabled: Bool = true,
                                 expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try mutate(expectedRevision: expectedRevision) { document in
            try self.validateName(name)
            guard self.rules.supports(modeID: modeID) else { throw CustomInputDictionaryStoreError.validation(.unsupportedMode) }
            let collection = CustomInputDictionaryCollection(name: name, modeID: modeID, enabled: enabled, entries: [])
            return document.edited(collections: document.snapshot.collections + [collection])
        }
    }

    @discardableResult
    public func renameCollection(id: UUID, name: String, expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try updateCollection(id: id, expectedRevision: expectedRevision) { collection in
            try self.validateName(name)
            return .init(id: collection.id, name: name, modeID: collection.modeID, enabled: collection.enabled, entries: collection.entries)
        }
    }

    @discardableResult
    public func setEnabled(id: UUID, enabled: Bool, expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try updateCollection(id: id, expectedRevision: expectedRevision) { collection in
            .init(id: collection.id, name: collection.name, modeID: collection.modeID, enabled: enabled, entries: collection.entries)
        }
    }

    @discardableResult
    public func removeCollection(id: UUID, expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try mutate(expectedRevision: expectedRevision) { document in
            guard document.snapshot.collections.contains(where: { $0.id == id }) else { throw CustomInputDictionaryStoreError.collectionNotFound }
            return document.edited(collections: document.snapshot.collections.filter { $0.id != id })
        }
    }

    @discardableResult
    public func addEntry(collectionID: UUID, reading: String, output: String,
                         weight: Int = CustomInputDictionaryLimits.defaultWeight, expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try updateCollection(id: collectionID, expectedRevision: expectedRevision) { collection in
            let entry = try self.validatedEntry(reading: reading, output: output, weight: weight, modeID: collection.modeID)
            guard !collection.entries.contains(where: { $0.identity == entry.identity }) else { throw CustomInputDictionaryStoreError.duplicateEntry }
            return self.replacingEntries(in: collection, with: collection.entries + [entry])
        }
    }

    /// Indices are safe only with the supplied snapshot revision. No index from
    /// a stale preview/snapshot is ever applied against newer collection contents.
    @discardableResult
    public func editEntry(collectionID: UUID, index: Int, reading: String, output: String,
                          weight: Int = CustomInputDictionaryLimits.defaultWeight, expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try updateCollection(id: collectionID, expectedRevision: expectedRevision) { collection in
            guard collection.entries.indices.contains(index) else { throw CustomInputDictionaryStoreError.entryNotFound }
            let entry = try self.validatedEntry(reading: reading, output: output, weight: weight, modeID: collection.modeID)
            guard !collection.entries.enumerated().contains(where: { $0.offset != index && $0.element.identity == entry.identity }) else {
                throw CustomInputDictionaryStoreError.duplicateEntry
            }
            var entries = collection.entries
            entries[index] = entry
            return self.replacingEntries(in: collection, with: entries)
        }
    }

    @discardableResult
    public func deleteEntry(collectionID: UUID, index: Int, expectedRevision: UUID) throws -> CustomInputDictionarySnapshot {
        try updateCollection(id: collectionID, expectedRevision: expectedRevision) { collection in
            guard collection.entries.indices.contains(index) else { throw CustomInputDictionaryStoreError.entryNotFound }
            var entries = collection.entries
            entries.remove(at: index)
            return self.replacingEntries(in: collection, with: entries)
        }
    }

    public func exportCollection(id: UUID, weights: CustomInputDictionaryExport.Weights = .omitDefault) throws -> Data {
        guard let collection = try snapshot().collections.first(where: { $0.id == id }) else {
            throw CustomInputDictionaryStoreError.collectionNotFound
        }
        return try CustomInputDictionaryExport.tsv(collection, weights: weights)
    }

    /// Bounded backup parts for collections larger than one import file.
    public func exportCollectionParts(id: UUID, weights: CustomInputDictionaryExport.Weights = .omitDefault) throws -> [Data] {
        guard let collection = try snapshot().collections.first(where: { $0.id == id }) else {
            throw CustomInputDictionaryStoreError.collectionNotFound
        }
        return try CustomInputDictionaryExport.tsvParts(collection, weights: weights)
    }

    private func replacingEntries(in collection: CustomInputDictionaryCollection,
                                  with entries: [CustomInputDictionaryEntry]) -> CustomInputDictionaryCollection {
        .init(id: collection.id, name: collection.name, modeID: collection.modeID, enabled: collection.enabled, entries: entries)
    }

    private func updateCollection(id: UUID, expectedRevision: UUID,
                                  transform: (CustomInputDictionaryCollection) throws -> CustomInputDictionaryCollection) throws -> CustomInputDictionarySnapshot {
        try mutate(expectedRevision: expectedRevision) { document in
            guard let index = document.snapshot.collections.firstIndex(where: { $0.id == id }) else {
                throw CustomInputDictionaryStoreError.collectionNotFound
            }
            var collections = document.snapshot.collections
            collections[index] = try transform(collections[index])
            return document.edited(collections: collections)
        }
    }

    private func validateName(_ name: String) throws {
        guard CustomInputDictionaryValidation.fieldIssue(name, reading: false) == nil else { throw CustomInputDictionaryStoreError.invalidName }
    }

    private func validatedEntry(reading: String, output: String, weight: Int, modeID: String) throws -> CustomInputDictionaryEntry {
        switch rules.validate(reading: reading, output: output, weight: weight, modeID: modeID) {
        case let .success(entry): return entry
        case let .failure(issue): throw CustomInputDictionaryStoreError.validation(issue)
        }
    }

    private func validateCanonical(_ entry: CustomInputDictionaryEntry, modeID: String) throws {
        let normalized = try validatedEntry(reading: entry.reading, output: entry.output, weight: entry.weight, modeID: modeID)
        guard normalized == entry else { throw CustomInputDictionaryStoreError.invalidPreview }
    }

    private func mutate(expectedRevision: UUID,
                        transform: (CustomInputDictionaryDocument) throws -> CustomInputDictionaryDocument) throws -> CustomInputDictionarySnapshot {
        try CustomInputDictionaryDisk.write(directory: directory) { current in
            guard current.snapshot.revision == expectedRevision else {
                throw CustomInputDictionaryStoreError.revisionConflict(expected: expectedRevision, actual: current.snapshot.revision)
            }
            let next = try transform(current)
            guard next.snapshot.collections.count <= CustomInputDictionaryLimits.totalCollections else { throw CustomInputDictionaryStoreError.collectionLimit }
            guard next.snapshot.totalEntryCount <= CustomInputDictionaryLimits.totalEntries else { throw CustomInputDictionaryStoreError.totalEntryLimit }
            return next
        }.snapshot
    }
}

/// Read-only app/compiler API: decodes the FULL document on a worker queue.
/// Do not instantiate this in the keyboard; it needs a bounded per-reading index.
/// A failed read throws; the app can retain its last good immutable snapshot.
/// This never creates the directory, logs contents or repairs corrupt files.
public struct CustomInputDictionarySnapshotReader {
    private let directory: URL
    public init(directory: URL) { self.directory = directory.standardizedFileURL }
    public func read() throws -> CustomInputDictionarySnapshot {
        try CustomInputDictionaryDisk.read(directory: directory).snapshot
    }

    /// Internal compiler guard. Never call back into the source store from body.
    func withCurrentRevision<T>(_ expected: UUID, body: () throws -> T) throws -> T {
        try CustomInputDictionaryDisk.withCurrentRevision(directory: directory, expected: expected, body: body)
    }
}

private struct CustomInputDictionaryDocument: Codable {
    struct Undo: Codable {
        let importRevision: UUID
        let collectionID: UUID
    }
    let schemaVersion: Int
    let snapshot: CustomInputDictionarySnapshot
    let undo: Undo?

    init(snapshot: CustomInputDictionarySnapshot, undo: Undo?) {
        schemaVersion = 1
        self.snapshot = snapshot
        self.undo = undo
    }

    func edited(collections: [CustomInputDictionaryCollection]) -> Self {
        // Preserve a stale marker so Undo reports an explicit conflict, not a
        // misleading successful restoration or an unexplained missing action.
        .init(snapshot: .init(revision: UUID(), collections: collections), undo: undo)
    }
}

private enum CustomInputDictionaryDisk {
    /// NSFileCoordinator supplies cross-process exclusion. This lock also makes
    /// simultaneous stores in this process deterministic, including first save.
    static let processLock = NSLock()

    static func read(directory: URL) throws -> CustomInputDictionaryDocument {
        processLock.lock()
        defer { processLock.unlock() }
        let url = directory.appendingPathComponent(CustomInputDictionaryStore.filename)
        // Distinguish an absent first snapshot from permission/I/O failure; a
        // boolean fileExists check would incorrectly turn some failures into [].
        do { _ = try url.resourceValues(forKeys: [.isRegularFileKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .init(snapshot: .empty, undo: nil)
        }
        return try coordinate(url: url, writing: false) { try load(url: $0) }
    }

    static func withCurrentRevision<T>(directory: URL, expected: UUID, body: () throws -> T) throws -> T {
        processLock.lock()
        defer { processLock.unlock() }
        let url = directory.appendingPathComponent(CustomInputDictionaryStore.filename)
        // Same coordination/lock order as source writers, held until publication.
        // No source bytes (including persisted Undo) are rewritten by recovery.
        return try coordinate(url: url, writing: false) { location in
            let actual = try load(url: location).snapshot.revision
            guard actual == expected else {
                throw CustomInputDictionaryStoreError.revisionConflict(expected: expected, actual: actual)
            }
            return try body()
        }
    }

    static func write(directory: URL, transform: (CustomInputDictionaryDocument) throws -> CustomInputDictionaryDocument) throws -> CustomInputDictionaryDocument {
        processLock.lock()
        defer { processLock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(CustomInputDictionaryStore.filename)
        return try coordinate(url: url, writing: true) { coordinatedURL in
            let current = try load(url: coordinatedURL)
            let next = try transform(current)
            try validate(next)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(next)
            guard bytes.count <= CustomInputDictionaryStore.maximumSnapshotBytes else { throw CustomInputDictionaryStoreError.snapshotTooLarge }
            // Foundation stages a sibling temp file and atomically renames it.
            // Failure before replacement leaves the previous snapshot untouched.
            try bytes.write(to: coordinatedURL, options: .atomic)
            return next
        }
    }

    private static func coordinate<T>(url: URL, writing: Bool, body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<T, Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { location in
                outcome = Result { try body(location) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { location in
                outcome = Result { try body(location) }
            }
        }
        if let outcome = outcome { return try outcome.get() }
        if let coordinationError = coordinationError { throw coordinationError }
        throw CustomInputDictionaryStoreError.corruptSnapshot
    }

    private static func load(url: URL) throws -> CustomInputDictionaryDocument {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .init(snapshot: .empty, undo: nil)
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CustomInputDictionaryStoreError.corruptSnapshot }
        guard let size = values.fileSize, size <= CustomInputDictionaryStore.maximumSnapshotBytes else { throw CustomInputDictionaryStoreError.snapshotTooLarge }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count <= CustomInputDictionaryStore.maximumSnapshotBytes else { throw CustomInputDictionaryStoreError.snapshotTooLarge }
        let document: CustomInputDictionaryDocument
        do { document = try JSONDecoder().decode(CustomInputDictionaryDocument.self, from: bytes) }
        catch { throw CustomInputDictionaryStoreError.corruptSnapshot }
        try validate(document)
        return document
    }

    private static func validate(_ document: CustomInputDictionaryDocument) throws {
        guard document.schemaVersion == 1 else { throw CustomInputDictionaryStoreError.unsupportedSchema }
        guard document.snapshot.collections.count <= CustomInputDictionaryLimits.totalCollections else { throw CustomInputDictionaryStoreError.corruptSnapshot }
        var ids = Set<UUID>()
        var total = 0
        for collection in document.snapshot.collections {
            total += collection.entries.count
            guard total <= CustomInputDictionaryLimits.totalEntries,
                  ids.insert(collection.id).inserted,
                  CustomInputDictionaryValidation.fieldIssue(collection.name, reading: false) == nil,
                  CustomInputDictionaryValidation.fieldIssue(collection.modeID, reading: true) == nil else {
                throw CustomInputDictionaryStoreError.corruptSnapshot
            }
            var keys = Set<CustomInputDictionaryEntryIdentity>()
            for entry in collection.entries {
                guard CustomInputDictionaryValidation.structurallyValid(entry), keys.insert(entry.identity).inserted else {
                    throw CustomInputDictionaryStoreError.corruptSnapshot
                }
            }
        }
        if let undo = document.undo, undo.importRevision == document.snapshot.revision {
            guard ids.contains(undo.collectionID) else { throw CustomInputDictionaryStoreError.corruptSnapshot }
        }
    }
}
