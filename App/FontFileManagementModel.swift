import SwiftUI

/// All bounded file/rule reads run off the UI actor. A cancelled or superseded
/// read never replaces the currently requested result.
@MainActor
final class FontFileManagementModel: ObservableObject {
    @Published private(set) var snapshot: FontManagementSnapshot?
    @Published private(set) var rules: [FontRule]?
    @Published private(set) var loading = false
    @Published private(set) var removing = false
    @Published private(set) var error: String?
    @Published private(set) var rulesError: String?
    private var request = UUID()
    private let store: CustomFontStore

    init(store: CustomFontStore = .shared) { self.store = store }

    func reload() async {
        let id = UUID()
        request = id
        loading = true
        snapshot = nil
        rules = nil
        error = nil
        rulesError = nil
        let store = store
        let work = Task.detached(priority: .userInitiated) { () throws -> (FontManagementSnapshot, [FontRule]?) in
            let snapshot = try store.readManagementSnapshot(checkCancellation: { try Task.checkCancellation() })
            let rules = FontRuleStore.shared.load()
            guard try store.readLibraryState().snapshot.generation == snapshot.generation else { throw FontManagementFailure.changed }
            try Task.checkCancellation()
            return (snapshot, rules)
        }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            guard request == id, !Task.isCancelled else { return }
            snapshot = value.0
            rules = value.1
            if value.1 == nil { rulesError = "Font rules couldn’t be read. Try again before removing a font." }
        } catch {
            guard request == id, !Task.isCancelled else { return }
            self.error = "Your fonts couldn’t be read. Nothing has been changed. Try again."
        }
        if request == id { loading = false }
    }

    struct Confirmation {
        let entry: FontManagedEntry
        let generation: String
        let rules: [FontRule]
        let uses: [FontManagedRuleUse]
    }

    func confirmation(for entry: FontManagedEntry) -> Confirmation? {
        guard !loading, !removing, let snapshot, let rules,
              snapshot.entries.contains(entry) else { return nil }
        return .init(entry: entry, generation: snapshot.generation, rules: rules,
                     uses: snapshot.references(to: entry, rules: rules))
    }

    func remove(_ confirmation: Confirmation) async -> Bool {
        guard !removing else { return false }
        removing = true
        defer { removing = false }
        request = UUID() // Invalidate an outstanding read before publishing membership.
        let store = store
        let work = Task.detached(priority: .userInitiated) {
            try store.removeManagedEntry(confirmation.entry, expectedGeneration: confirmation.generation,
                                         expectedRules: confirmation.rules, readRules: { FontRuleStore.shared.load() },
                                         checkCancellation: { try Task.checkCancellation() })
        }
        do {
            try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            CatalogPreferences.shared.fontFilesChanged()
            NotificationCenter.default.post(name: .fontExplorationLibraryChanged, object: nil)
            return true
        } catch {
            await reload()
            if error is FontManagementFailure {
                self.error = "Fonts or font rules changed. Review the current details before trying again. Nothing was removed."
            } else if !(error is CancellationError) {
                self.error = "Couldn’t stop using this font. Nothing was removed. Try again."
            }
            return false
        }
    }
}

enum FontFileManagementCopy {
    static let retained = "Some font files remain stored after you stop using them. Removing a file here may not free device storage immediately."
    static let rulesKept = "Your font rules will be kept. Other fonts will be used where a referenced style is no longer available."
    static func size(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Size unavailable"
    }
    static func styles(_ count: Int) -> String { count == 1 ? "1 style" : "\(count) styles" }
    static func capacity(files: Int, installed: Int) -> String {
        "\(files + installed) of 16. \(files) \(files == 1 ? "font file" : "font files"), \(installed) \(installed == 1 ? "installed font" : "installed fonts")"
    }
    static func remaining(_ free: Int) -> String {
        if free <= 0 { return "The limit of 16 has been reached. Remove an added font to make room." }
        return free == 1 ? "You can add 1 more font file or installed font." : "You can add \(free) more font files or installed fonts."
    }
    static func ruleTitle(_ rule: FontRule) -> String {
        switch rule.selector {
        case let .codePoint(value): return FontRuleScalar.label(value)
        case let .range(first, last): return FontRuleCopy.range(first, last)
        case let .block(block): return block.name
        }
    }
}
