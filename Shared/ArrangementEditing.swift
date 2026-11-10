import Foundation

/// One transient successful edit. A no-op or failed write never consumes the
/// previous step; consuming a restore never creates redo history.
struct ArrangementUndoStep<Value: Equatable> {
    let before: Value
    let expectedAfter: Value
}
struct ArrangementHistory<Value: Equatable> {
    private(set) var step: ArrangementUndoStep<Value>?
    mutating func record(before: Value, after: Value, succeeded: Bool) {
        guard succeeded, before != after else { return }
        step = .init(before: before, expectedAfter: after)
    }
    mutating func invalidate() { step = nil }
}

/// Row scope is independent from key selection. Invalid positional scopes
/// return to All Rows instead of unexpectedly modifying another row.
struct ArrangementRowScope: Equatable {
    var row: Int?
    init(row: Int? = nil) { self.row = row }
    func clamped(rowCount: Int) -> Self {
        Self(row: row.flatMap { (0..<max(0, rowCount)).contains($0) ? $0 : nil })
    }
}

enum ArrangementUndoResult: Equatable { case restored, invalidated, failed }
enum ArrangementCopy {
    static let invalidated = "Undo Arrangement is no longer available because the page changed. Your later changes have been kept."
    static let restoreFailed = "Couldn’t restore the arrangement. Try again."
}

/// Uses the same root lock as configuration replacement and Favorites sync.
/// Generation directories are resolved again *inside* this lock by callers.
enum ArrangementPublication {
    static func withLock<T>(directory: URL, _ body: () throws -> T) throws -> T {
        let parent = directory.deletingLastPathComponent()
        let root = parent.lastPathComponent == SharedConfigurationLocation.folderName
            && SharedConfigurationLocation.generationNumber(directory.lastPathComponent) != nil
            ? parent.deletingLastPathComponent() : directory
        return try SharedConfigurationLocation(root: { root }).withWriterLock(body)
    }

    /// Exact bytes, not canonical String equality. Other page/star edits are
    /// deliberately excluded: conditional page replacement merges those fresh.
    struct Context: Equatable {
        let directory: URL
        let files: [String: Data]
    }
    static func context(in directory: URL, excluding: Set<String>) -> Context? {
        var files: [String: Data] = [:]
        for name in SharedConfigurationLocation.snapshotFiles where !excluding.contains(name) {
            do {
                guard let limit = SharedConfigurationLocation.fileLimits[name] else { return nil }
                if let data = try SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(name), limit: limit + 1) {
                    guard data.count <= limit else { return nil }
                    files[name] = data
                }
            } catch { return nil }
        }
        return Context(directory: directory, files: files)
    }
}
