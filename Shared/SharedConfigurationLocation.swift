import Foundation
import CoreFoundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Which generation directory holds the current configuration. Written
/// atomically by the containing app only; the keyboard only reads it.
struct ConfigurationPointer: Codable, Equatable, Sendable {
    static let currentSchema = 1
    var schemaVersion = ConfigurationPointer.currentSchema
    var generation: Int
    /// `g-NNNNNN`, always the name of `generation`.
    var directory: String
    /// The pre-import backup kept for Undo Last Import.
    var previous: String? = nil
    /// The configuration right after that import, to notice later edits.
    var importFingerprint: String? = nil
    /// When that import was applied on this device (seconds since 1970),
    /// for "Imported {date, time}". Not the file's own date.
    var importedAt: Double? = nil
    /// What made that change (`ConfigurationChangeSource`), for the Undo
    /// row's caption. Optional and free text: older pointers have none, and
    /// a value this build doesn't know never makes the pointer invalid.
    var changeSource: String? = nil

    var isValid: Bool {
        SharedConfigurationLocation.generationNumber(directory) == generation
            && (previous.map { SharedConfigurationLocation.generationNumber($0).map { $0 < generation } ?? false } ?? true)
            && (importFingerprint.map(SharedConfigurationLocation.isDigest) ?? true)
            && (importedAt?.isFinite ?? true)
    }
}

enum ConfigurationPointerState: Equatable, Sendable {
    /// Not migrated yet: every store still reads the group root.
    case missing
    case valid(ConfigurationPointer)
    /// Written by a newer Uniboard; refused rather than guessed at.
    case unsupported
    case invalid
}

/// The steps of a staged write, in order. Tests inject a failure at each.
enum ConfigurationStep: String, Sendable { case stage, verify, publish, pointer }

enum ConfigurationOutcome: Equatable, Sendable {
    case applied(ConfigurationPointer)
    case alreadyMigrated
    /// Another writer holds the configuration lock; nothing changed.
    case busy
    /// The configuration changed since it was previewed; nothing changed.
    case conflict
    case invalidPayload
    case unavailable
    /// Stopped before the pointer moved: the last good generation stays current.
    case failed(ConfigurationStep)
}

/// What replaced the configuration: an imported file or the in-app editor.
enum ConfigurationChangeSource: String, Equatable, Sendable {
    case importFile = "import"
    case editor
}

struct ConfigurationUndoStatus: Equatable, Sendable {
    let fingerprint: String
    /// Changes were made after the import; undoing replaces them too.
    let hasNewerEdits: Bool
    /// When the import was applied; nil for a pointer written before this was recorded.
    var importedAt: Date? = nil
    /// nil when the pointer didn't record it (older pointers) or names an unknown source.
    var source: ConfigurationChangeSource? = nil
}

/// The shared configuration location in the App Group:
///
///     <group>/Configuration-v1/current.json      pointer (atomic rename)
///     <group>/Configuration-v1/g-000001/…        one complete snapshot per generation
///     <group>/Configuration-v1/staging-<uuid>/   an apply in progress
///     <group>/favorites-v1.lock                  the one writer lock
///
/// Readers resolve the current directory through the pointer, or the group
/// root before migration. A replacement is written to a staging directory,
/// read back, renamed to the next generation, and becomes visible to the
/// keyboard only when the pointer is replaced. The root files are never
/// changed by migration, so an older build still finds them.
struct SharedConfigurationLocation {
    enum Failure: Error { case unavailable, busy, invalid }
    static let folderName = "Configuration-v1"
    static let pointerFilename = "current.json"
    static let manifestFilename = "generation.json"
    static let lockFilename = FavoriteSync.lockFilename
    static let maximumPointerBytes = 4096
    /// Every file a generation can hold, with the most bytes its store reads.
    static let fileLimits: [String: Int] = [
        UnicodeEditionSettings.filename: UnicodeEditionSettings.maximumPayloadBytes,
        KeyboardKeySettings.filename: KeyboardKeySettings.maximumPayloadBytes,
        SymbolPageSettings.filename: SymbolPageSettings.maximumPayloadBytes,
        FavoriteSync.filename: FavoriteSync.maximumBytes,
        FontRuleStore.filename: FontRuleStore.maximumPayloadBytes,
        ImageColorSettings.filename: ImageColorSettings.maximumPayloadBytes,
        AutoCapitalizationSetting.filename: AutoCapitalizationSetting.maximumPayloadBytes,
        AppPresentationSettings.filename: AppPresentationSettings.maximumPayloadBytes,
    ]
    static let snapshotFiles = fileLimits.keys.sorted()
    static let shared = SharedConfigurationLocation(root: {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)
    })

    let root: () -> URL?
    /// Called before each step of a staged write; tests throw to simulate an interruption.
    var fault: (ConfigurationStep) throws -> Void = { _ in }
    /// The clock an import's time comes from.
    var now: () -> Date = Date.init

    init(root: @escaping () -> URL?) { self.root = root }

    private struct Manifest: Codable {
        var schemaVersion = 1
        let generation: Int
        let files: [String]
    }

    var folder: URL? {
        guard let root = root(), root.isFileURL else { return nil }
        return root.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func directoryName(_ generation: Int) -> String { String(format: "g-%06d", generation) }

    static func generationNumber(_ name: String) -> Int? {
        guard name.utf8.count == 8, name.hasPrefix("g-"), name.utf8.dropFirst(2).allSatisfy({ (48...57).contains($0) }),
              let number = Int(name.dropFirst(2)), number > 0 else { return nil }
        return number
    }

    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// A replacement id or color revision: 1–64 ASCII letters, digits and hyphens.
    static func isRevision(_ text: String) -> Bool {
        (1...64).contains(text.utf8.count) && text.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
    }

    // MARK: Reading

    func readPointer() -> ConfigurationPointerState {
        guard let folder else { return .missing }
        do {
            guard let data = try Self.readRegularFile(folder.appendingPathComponent(Self.pointerFilename), limit: Self.maximumPointerBytes + 1) else { return .missing }
            return Self.pointerState(data)
        } catch { return .invalid }
    }

    static func pointerState(_ data: Data) -> ConfigurationPointerState {
        struct Version: Decodable { let schemaVersion: Int }
        guard data.count <= maximumPointerBytes, let version = try? JSONDecoder().decode(Version.self, from: data) else { return .invalid }
        guard version.schemaVersion == ConfigurationPointer.currentSchema else { return .unsupported }
        guard let pointer = try? JSONDecoder().decode(ConfigurationPointer.self, from: data), pointer.isValid else { return .invalid }
        return .valid(pointer)
    }

    /// Where every store reads and writes now. Resolve once and pass it to
    /// each reader when several files must come from the same generation.
    func currentDirectory() -> URL? {
        switch readPointer() {
        case let .valid(pointer): return folder?.appendingPathComponent(pointer.directory, isDirectory: true)
        case .invalid: return lastGoodGeneration().flatMap { folder?.appendingPathComponent($0, isDirectory: true) } ?? root()
        case .missing, .unsupported: return root()
        }
    }

    /// nil before migration. Cheap enough for the keyboard's refresh.
    func currentGeneration() -> Int? {
        guard case let .valid(pointer) = readPointer() else { return nil }
        return pointer.generation
    }

    /// The newest generation whose manifest and files are all present.
    func lastGoodGeneration() -> String? {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        return names.compactMap { name in Self.generationNumber(name).map { ($0, name) } }.sorted { $0.0 > $1.0 }
            .first { isComplete(folder.appendingPathComponent($0.1, isDirectory: true), generation: $0.0) }?.1
    }

    private func isComplete(_ directory: URL, generation: Int) -> Bool {
        guard let data = try? Self.readRegularFile(directory.appendingPathComponent(Self.manifestFilename), limit: Self.maximumPointerBytes),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.generation == generation else { return false }
        return manifest.files.allSatisfy { (try? Self.readRegularFile(directory.appendingPathComponent($0), limit: 0)) != nil }
    }

    /// SHA-256 over the generation number, every snapshot file's bytes (the
    /// app presentation file excepted) and the app's live presentation
    /// defaults. Any edit by the app or keyboard, or a generation switch,
    /// changes it.
    func fingerprint(of directory: URL, generation: Int, presentation: Data) -> String {
        var digest = SHA256()
        digest.update(data: Data("uniboard-configuration:\(generation)\n".utf8))
        for file in Self.snapshotFiles where file != AppPresentationSettings.filename {
            let bytes = try? Self.readRegularFile(directory.appendingPathComponent(file), limit: Self.fileLimits[file]! + 1)
            digest.update(data: Data("\(file):\(bytes.map { String($0.count) } ?? "-")\n".utf8))
            digest.update(data: bytes ?? Data())
        }
        digest.update(data: Data("presentation:\(presentation.count)\n".utf8))
        digest.update(data: presentation)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// nil before migration.
    func currentFingerprint(presentation: Data) -> String? {
        guard case let .valid(pointer) = readPointer(), let folder else { return nil }
        return fingerprint(of: folder.appendingPathComponent(pointer.directory, isDirectory: true), generation: pointer.generation, presentation: presentation)
    }

    // MARK: Lock

    /// The one nonblocking writer lock, shared with favorites sync. Busy
    /// means another process is writing: try again later, never wait.
    func withWriterLock<T>(_ body: () throws -> T) throws -> T {
        guard let root = root(), root.isFileURL else { throw Failure.unavailable }
        let descriptor = root.appendingPathComponent(Self.lockFilename).withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw Failure.unavailable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw Failure.unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func locked(_ body: () -> ConfigurationOutcome) -> ConfigurationOutcome {
        do { return try withWriterLock(body) } catch Failure.busy { return .busy } catch { return .unavailable }
    }

    // MARK: Migration, apply, undo, recovery (containing app only)

    /// Copies the root files into generation 1 byte for byte (bounded by
    /// each store's own read limit) and leaves them untouched. A root entry
    /// that exists but isn't a readable regular file becomes an empty
    /// directory, so every reader keeps treating it as unreadable rather than
    /// missing. Nothing is reset, repaired or reformatted.
    func migrateIfNeeded(presentation: Data) -> ConfigurationOutcome {
        locked {
            guard let root = root(), readPointer() == .missing else { return .alreadyMigrated }
            var files = [AppPresentationSettings.filename: presentation]
            var placeholders: [String] = []
            for file in Self.snapshotFiles where file != AppPresentationSettings.filename {
                do { files[file] = try Self.readRegularFile(root.appendingPathComponent(file), limit: Self.fileLimits[file]! + 1) } catch { placeholders.append(file) }
            }
            return publish(files, placeholders: placeholders, after: nil)
        }
    }

    /// Replaces the whole configuration with already validated payloads,
    /// one per snapshot file. `expected` is the fingerprint the preview was
    /// built from; any change since then is a conflict. The current
    /// generation stays as the Undo backup, completed with today's app
    /// presentation defaults.
    func apply(_ files: [String: Data], expecting expected: String, currentPresentation: Data, source: ConfigurationChangeSource = .importFile,
               validators: [String: (Data) -> Bool] = ConfigurationSnapshotValidation.validators) -> ConfigurationOutcome {
        guard Set(files.keys) == Set(Self.snapshotFiles), files.allSatisfy({ validators[$0.key]?($0.value) == true }) else { return .invalidPayload }
        return locked {
            guard case let .valid(pointer) = readPointer(), let folder else { return .unavailable }
            let current = folder.appendingPathComponent(pointer.directory, isDirectory: true)
            guard fingerprint(of: current, generation: pointer.generation, presentation: currentPresentation) == expected else { return .conflict }
            guard (try? Self.replaceFile(currentPresentation, at: current.appendingPathComponent(AppPresentationSettings.filename))) != nil else { return .failed(.stage) }
            return publish(files, after: pointer, importedPresentation: files[AppPresentationSettings.filename]!, source: source)
        }
    }

    /// nil when there is no import to undo.
    func undoStatus(presentation: Data) -> ConfigurationUndoStatus? {
        guard case let .valid(pointer) = readPointer(), let folder, let previous = pointer.previous, let imported = pointer.importFingerprint,
              isComplete(folder.appendingPathComponent(previous, isDirectory: true), generation: Self.generationNumber(previous)!) else { return nil }
        let current = fingerprint(of: folder.appendingPathComponent(pointer.directory, isDirectory: true), generation: pointer.generation, presentation: presentation)
        return ConfigurationUndoStatus(fingerprint: current, hasNewerEdits: current != imported,
                                       importedAt: pointer.importedAt.map(Date.init(timeIntervalSince1970:)),
                                       source: pointer.changeSource.flatMap(ConfigurationChangeSource.init(rawValue:)))
    }

    /// Restores the pre-import backup as a new generation, so both processes
    /// notice it: favorites get a fresh replacement id and image colors a
    /// fresh revision. Every other file is copied byte for byte.
    func undoLastImport(expecting expected: String, currentPresentation: Data) -> ConfigurationOutcome {
        locked {
            guard case let .valid(pointer) = readPointer(), let folder, let previous = pointer.previous,
                  isComplete(folder.appendingPathComponent(previous, isDirectory: true), generation: Self.generationNumber(previous)!) else { return .unavailable }
            guard fingerprint(of: folder.appendingPathComponent(pointer.directory, isDirectory: true), generation: pointer.generation, presentation: currentPresentation) == expected else { return .conflict }
            let source = folder.appendingPathComponent(previous, isDirectory: true)
            let current = folder.appendingPathComponent(pointer.directory, isDirectory: true)
            var files: [String: Data] = [:]
            var placeholders: [String] = []
            for file in Self.snapshotFiles {
                // A file migration kept unreadable stays unreadable.
                do { files[file] = try Self.readRegularFile(source.appendingPathComponent(file), limit: Self.fileLimits[file]! + 1) } catch { placeholders.append(file) }
            }
            if !placeholders.contains(FavoriteSync.filename) {
                // A backup without a favorites file never shared them: they lived only in each
                // process. Restoring that as an empty list would erase them, so the current
                // file carries over byte for byte (same replacement id: nothing is re-adopted).
                files[FavoriteSync.filename] = files[FavoriteSync.filename].map(FavoriteSync.renewedReplacement)
                    ?? (try? Self.readRegularFile(current.appendingPathComponent(FavoriteSync.filename), limit: FavoriteSync.maximumBytes + 1)) ?? nil
            }
            files[ImageColorSettings.filename] = files[ImageColorSettings.filename].map(ImageColorSettings.renewedRevision)
            return publish(files, placeholders: placeholders, after: pointer)
        }
    }

    struct RecoveryReport: Equatable, Sendable {
        var repairedPointer = false
        var removed: [String] = []
    }

    /// Removes leftovers of an interrupted write (staging directories,
    /// temporary pointers, generations the pointer doesn't name) and keeps
    /// the current and backup generations. A damaged pointer is rebuilt from
    /// the newest complete generation, or removed so migration starts again
    /// from the untouched root files. A newer pointer schema is left alone.
    /// nil when another writer holds the lock.
    @discardableResult func recover() -> RecoveryReport? {
        try? withWriterLock { () -> RecoveryReport in
            var report = RecoveryReport()
            guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return report }
            let pointerURL = folder.appendingPathComponent(Self.pointerFilename)
            var state = readPointer()
            if state == .invalid {
                let good = lastGoodGeneration().map { ConfigurationPointer(generation: Self.generationNumber($0)!, directory: $0) }
                if let good, (try? Self.replaceFile(Self.encoder.encode(good), at: pointerURL)) != nil {
                    state = .valid(good); report.repairedPointer = true
                } else { try? FileManager.default.removeItem(at: pointerURL); state = .missing }
            }
            var keep: Set<String> = []
            if case let .valid(pointer) = state { keep = Set([pointer.directory] + (pointer.previous.map { [$0] } ?? [])) }
            let collects = state != .unsupported
            for name in names.sorted() where name.hasPrefix("staging-") || (name.hasPrefix(".") && name.hasSuffix(".tmp"))
                || (collects && Self.generationNumber(name) != nil && !keep.contains(name)) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
                report.removed.append(name)
            }
            return report
        }
    }

    /// With `importedPresentation` (an import), the replaced generation stays
    /// as the Undo backup and the new one's fingerprint is recorded.
    private func publish(_ files: [String: Data], placeholders: [String] = [], after current: ConfigurationPointer?,
                         importedPresentation: Data? = nil, source: ConfigurationChangeSource? = nil) -> ConfigurationOutcome {
        let folder = self.folder!
        let generation = (current?.generation ?? 0) + 1
        let name = Self.directoryName(generation)
        let staging = folder.appendingPathComponent("staging-" + UUID().uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(name, isDirectory: true)
        var step = ConfigurationStep.stage
        do {
            try fault(step)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for (file, data) in files { try Self.writeNewFile(data, to: staging.appendingPathComponent(file)) }
            for file in placeholders { try FileManager.default.createDirectory(at: staging.appendingPathComponent(file), withIntermediateDirectories: false) }
            try Self.writeNewFile(try Self.encoder.encode(Manifest(generation: generation, files: files.keys.sorted())), to: staging.appendingPathComponent(Self.manifestFilename))
            step = .verify
            try fault(step)
            for (file, data) in files { guard try Self.readRegularFile(staging.appendingPathComponent(file), limit: data.count + 1) == data else { throw Failure.invalid } }
            step = .publish
            try fault(step)
            // A generation directory the pointer never named is a leftover.
            try? FileManager.default.removeItem(at: target)
            guard rename(staging.path, target.path) == 0 else { throw Failure.unavailable }
            step = .pointer
            try fault(step)
            let pointer = ConfigurationPointer(generation: generation, directory: name, previous: importedPresentation.flatMap { _ in current?.directory },
                importFingerprint: importedPresentation.map { fingerprint(of: target, generation: generation, presentation: $0) },
                importedAt: importedPresentation.map { _ in now().timeIntervalSince1970 },
                changeSource: importedPresentation.flatMap { _ in source?.rawValue })
            try Self.replaceFile(try Self.encoder.encode(pointer), at: folder.appendingPathComponent(Self.pointerFilename))
            return .applied(pointer)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            if step == .pointer { try? FileManager.default.removeItem(at: target) }
            return .failed(step)
        }
    }

    // MARK: Files

    /// nil when the file doesn't exist. Never follows a link or blocks on a
    /// FIFO; anything but a regular file is an error. Reads at most `limit` bytes.
    static func readRegularFile(_ url: URL, limit: Int) throws -> Data? {
        guard url.isFileURL else { throw Failure.unavailable }
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        guard descriptor >= 0 else { if errno == ENOENT { return nil } else { throw Failure.unavailable } }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw Failure.invalid }
        var data = Data()
        while data.count < limit, let chunk = try handle.read(upToCount: limit - data.count), !chunk.isEmpty { data.append(chunk) }
        return data
    }

    /// Creates a new file (never through a link) and flushes it to disk.
    static func writeNewFile(_ data: Data, to url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw Failure.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    /// Atomically replaces one file: a flushed sibling, then rename(2).
    /// Refuses to write through a link.
    static func replaceFile(_ data: Data, at url: URL) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw Failure.invalid }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try writeNewFile(data, to: temporary)
        guard rename(temporary.path, url.path) == 0 else { try? FileManager.default.removeItem(at: temporary); throw Failure.unavailable }
    }
}

/// Each store's own strict decoder, run on every payload before an apply
/// writes anything.
enum ConfigurationSnapshotValidation {
    static let validators: [String: (Data) -> Bool] = [
        UnicodeEditionSettings.filename: { UnicodeEditionSettings.decode($0) != nil },
        KeyboardKeySettings.filename: { KeyboardKeySettings.decode($0) != nil },
        SymbolPageSettings.filename: { SymbolPageSettings.decode($0) != nil },
        // A replacement always carries an id, so both processes adopt it wholesale.
        FavoriteSync.filename: { FavoriteSync.decode($0)?.replacementID != nil },
        FontRuleStore.filename: { FontRuleStore.decode($0, blocks: UnicodeCatalog.shared.blocks) != nil },
        ImageColorSettings.filename: { ImageColorSettings.decode($0) != nil },
        AutoCapitalizationSetting.filename: { AutoCapitalizationSetting.decode($0) != nil },
        AppPresentationSettings.filename: { AppPresentationSettings.decode($0) != nil },
    ]
}

/// The app's own browse preferences (`@AppStorage` in standard defaults).
/// The keyboard never reads them; a generation keeps a copy so Undo and an
/// interrupted apply can restore them. Scratchpad and recents never enter.
enum AppPresentationSettings {
    static let filename = "app-presentation-v1.json"
    static let maximumPayloadBytes = 4096
    struct Values: Codable, Equatable, Sendable {
        var integers: [String: Int] = [:]
        var booleans: [String: Bool] = [:]
        var strings: [String: String] = [:]
    }
    static let integerValues: [String: Set<Int>] = [
        "exploreGridDensity": [3, 8, 16, 32], "blockGridDensity": [3, 8, 16, 32],
        "tileColumns": Set(2...256), "explorePlane": Set(-1...16),
    ]
    static let booleanKeys: Set<String> = ["exploreShowsPrivateUse", "exploreDescending"]
    static let stringValues: [String: Set<String>] = ["emojiSortOrder": Set(UnicodeSortOrder.allCases.map(\.rawValue))]

    /// Only set, well-typed values; an unset key stays unset.
    static func capture(_ defaults: UserDefaults) -> Values {
        var values = Values()
        for (key, allowed) in integerValues {
            if let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
               number.doubleValue == Double(number.intValue), allowed.contains(number.intValue) { values.integers[key] = number.intValue }
        }
        for key in booleanKeys {
            if let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { values.booleans[key] = number.boolValue }
        }
        for (key, allowed) in stringValues {
            if let text = defaults.object(forKey: key) as? String, allowed.contains(text) { values.strings[key] = text }
        }
        return values
    }

    /// Only strings, integers and booleans: encoding can't fail.
    static func encode(_ values: Values) -> Data { try! SharedConfigurationLocation.encoder.encode(values) }

    static func decode(_ data: Data) -> Values? {
        guard data.count <= maximumPayloadBytes, let values = try? JSONDecoder().decode(Values.self, from: data),
              values.integers.allSatisfy({ integerValues[$0.key]?.contains($0.value) == true }),
              values.booleans.keys.allSatisfy(booleanKeys.contains),
              values.strings.allSatisfy({ stringValues[$0.key]?.contains($0.value) == true }) else { return nil }
        return values
    }

    /// Sets every stored value and removes keys the snapshot leaves unset.
    static func apply(_ values: Values, to defaults: UserDefaults) {
        for key in integerValues.keys { if let value = values.integers[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        for key in booleanKeys { if let value = values.booleans[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        for key in stringValues.keys { if let value = values.strings[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
    }
}

/// Run by the containing app at launch, before any store is used. The
/// keyboard never migrates or repairs; it only reads.
enum ConfigurationRecovery {
    static let appliedGenerationKey = "configuration.appliedGeneration"

    @discardableResult
    static func run(location: SharedConfigurationLocation = .shared, defaults: UserDefaults = .standard) -> ConfigurationOutcome {
        location.recover()
        let outcome = location.migrateIfNeeded(presentation: AppPresentationSettings.encode(AppPresentationSettings.capture(defaults)))
        if case let .applied(pointer) = outcome { defaults.set(pointer.generation, forKey: appliedGenerationKey) }
        adoptCurrentPresentation(location: location, defaults: defaults)
        return outcome
    }

    /// After an apply or undo, or at the next launch when the app stopped
    /// before adopting the generation's app presentation defaults.
    @discardableResult
    static func adoptCurrentPresentation(location: SharedConfigurationLocation = .shared, defaults: UserDefaults = .standard) -> Bool {
        guard let generation = location.currentGeneration(), defaults.object(forKey: appliedGenerationKey) as? Int != generation,
              let directory = location.currentDirectory() else { return false }
        if let data = try? SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(AppPresentationSettings.filename),
                                                                        limit: AppPresentationSettings.maximumPayloadBytes + 1),
           let values = AppPresentationSettings.decode(data) { AppPresentationSettings.apply(values, to: defaults) }
        defaults.set(generation, forKey: appliedGenerationKey)
        return true
    }
}
