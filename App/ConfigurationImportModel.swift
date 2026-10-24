import Foundation

/// What the import flow needs from the outside world, so its state machine
/// can be tested without the shared container.
struct ConfigurationImportEnvironment {
    /// The bounded, security-scoped read of the chosen file.
    var read: @Sendable (URL) throws -> Data
    /// The configuration in effect and the fingerprint a replacement must match.
    var current: @MainActor () -> (configuration: UniboardConfiguration, fingerprint: String?)
    /// The faces this device can't load now.
    var unavailableFonts: @MainActor ([FontFaceReference]) -> [FontFaceReference]
    /// Today's app presentation defaults, as a generation stores them.
    var presentation: @MainActor () -> Data
    /// Replaces the configuration under the writer lock.
    var apply: @MainActor ([String: Data], String, Data) -> ConfigurationOutcome
    /// The fingerprint in effect now (nil when it can't be read).
    var currentFingerprint: @MainActor (Data) -> String?
    /// Lets the app's stores read the replacement.
    var adopt: @MainActor () -> Void

    @MainActor static var live: ConfigurationImportEnvironment { live(source: .importFile) }

    /// `source` is recorded with the replacement for the Undo row's caption.
    @MainActor static func live(source: ConfigurationChangeSource) -> ConfigurationImportEnvironment {
        let service = ConfigurationService()
        return ConfigurationImportEnvironment(
            read: { try ConfigurationService.readImport($0) },
            current: { service.current() },
            unavailableFonts: { service.unavailableFaces($0) },
            presentation: { service.presentation },
            apply: { files, expected, presentation in
                service.location.apply(files, expecting: expected, currentPresentation: presentation, source: source)
            },
            currentFingerprint: { service.location.currentFingerprint(presentation: $0) },
            adopt: { service.adoptCurrentConfiguration() })
    }
}

/// A valid file, compared with the configuration in effect when it was checked.
struct ConfigurationReview: Equatable {
    let fileName: String
    let caption: String
    let diff: ConfigurationDiff
    /// Referenced fonts this device can't load, each with the rules that
    /// use it; those rules are still imported.
    let fontWarnings: [ConfigurationFontWarning]
    /// Retired settings in the file; never applied, never a change.
    let ignoredSettings: [ConfigurationIgnoredSetting]
    let incoming: UniboardConfiguration
    /// The fingerprint the preview was built from; nil before the shared
    /// configuration exists (Replace then fails without writing).
    let fingerprint: String?

    var showsOverwrite: Bool { !diff.isIdentical && diff.replacesFavoritesOrKeys }
    var showsFonts: Bool { !diff.isIdentical && !fontWarnings.isEmpty }
    /// Display names of referenced fonts this device can't load.
    var unavailableFonts: [String] { fontWarnings.map(\.font) }
}

/// The Review Import sheet's state machine (design.md §6a). Nothing is
/// written before Replace Configuration, and only when the configuration
/// in effect still matches the one the review compared against.
@MainActor
final class ConfigurationImportModel: ObservableObject, Identifiable {
    /// A file from Files, or the configuration editor's text (design/config-editor/design.md §5):
    /// the same check, review, Replace and recovery; only the wording and
    /// presentation differ.
    enum Mode: Equatable {
        case importFile
        case editor
    }

    enum Phase: Equatable {
        case checking(String)
        /// Every problem, the first shown as a card.
        case failed([String])
        case review(ConfigurationReview)
        case replacing(ConfigurationReview)
        /// Imported; the names of fonts still unavailable.
        case imported(unavailableFonts: [String])
    }

    enum Alert: Equatable {
        /// The configuration changed after the review: review again or cancel.
        case changed
        /// Nothing was replaced and the previous configuration is verified in use.
        case replaceFailed
        /// Replace failed and the state in effect couldn't be verified.
        case replaceUnverified
    }

    let id = UUID()
    let fileName: String
    let mode: Mode
    @Published private(set) var phase: Phase
    @Published var alert: Alert?
    /// Called once Replace succeeds (the editor records that it applied).
    var onImported: (() -> Void)?
    private let environment: ConfigurationImportEnvironment
    private var data: Data?

    init(fileName: String, mode: Mode = .importFile, environment: ConfigurationImportEnvironment) {
        self.fileName = fileName
        self.mode = mode
        self.environment = environment
        phase = .checking(fileName)
    }

    /// Reads and validates the file chosen in Files; no writes.
    func load(_ url: URL) async {
        let read = environment.read
        let result = await Task.detached { Result { try read(url) } }.value
        switch result {
        case let .success(data): await check(data)
        case .failure: phase = .failed([ConfigurationCodec.unreadable])
        }
    }

    /// Validates `data` and compares it with the configuration in effect now.
    func check(_ data: Data) async {
        self.data = data
        let name = fileName
        phase = .checking(name)
        let decoded = await Task.detached { ConfigurationCodec.decode(data) }.value
        switch decoded {
        case let .failure(problems):
            phase = .failed(problems.messages)
        case let .success(file):
            let current = environment.current()
            // Retired switches stay as stored: a file never changes them.
            var incoming = file.configuration
            incoming.settings = incoming.settings.keepingRetired(from: current.configuration.settings)
            let diff = ConfigurationDiff(current: current.configuration, incoming: incoming,
                                         missingSections: file.missingSections)
            phase = .review(ConfigurationReview(
                fileName: name,
                caption: ConfigurationCopy.fileCaption(bytes: file.byteCount, version: file.formatVersion),
                diff: diff,
                fontWarnings: ConfigurationFontWarning.warnings(rules: incoming.fontRules, unavailable: environment.unavailableFonts(file.faces)),
                ignoredSettings: file.ignoredSettings,
                incoming: incoming, fingerprint: current.fingerprint))
        }
    }

    /// "Review Again" after the configuration changed: the same file
    /// against what is in effect now.
    func reviewAgain() async {
        alert = nil
        guard let data else { return }
        await check(data)
    }

    /// Replace Configuration. Returns true when the sheet should close
    /// without importing (an identical file's Done).
    @discardableResult
    func replace() async -> Bool {
        guard case let .review(review) = phase else { return false }
        if review.diff.isIdentical { return true }
        phase = .replacing(review)
        // Lets "Replacing configuration…" draw before the locked write.
        await Task.yield()
        let presentation = environment.presentation()
        guard let expected = review.fingerprint, let files = review.incoming.compile() else {
            finishFailure(review, expected: review.fingerprint, presentation: presentation)
            return false
        }
        switch environment.apply(files, expected, presentation) {
        case .applied:
            environment.adopt()
            phase = .imported(unavailableFonts: review.unavailableFonts)
            onImported?()
        case .conflict:
            phase = .review(review)
            alert = .changed
        default:
            finishFailure(review, expected: expected, presentation: presentation)
        }
        return false
    }

    /// Back to the review; the alert claims the previous configuration is
    /// still in use only when its fingerprint proves it.
    private func finishFailure(_ review: ConfigurationReview, expected: String?, presentation: Data) {
        phase = .review(review)
        let now = environment.currentFingerprint(presentation)
        alert = now != nil && now == expected ? .replaceFailed : .replaceUnverified
    }
}

/// Undo Last Configuration Change (design.md §6b): imports and editor applies alike.
enum ConfigurationUndo {
    enum Result: Equatable {
        case restored
        /// Nothing was restored and the configuration in effect is verified unchanged.
        case failed
        /// Restore failed and the state in effect couldn't be verified.
        case unverified
    }

    @MainActor
    static func run(status: ConfigurationUndoStatus, presentation: Data,
                    undo: (String, Data) -> ConfigurationOutcome,
                    currentFingerprint: (Data) -> String?, adopt: () -> Void) -> Result {
        switch undo(status.fingerprint, presentation) {
        case .applied:
            adopt()
            return .restored
        case .conflict:
            // The lock's fingerprint check refused before writing anything.
            return .failed
        default:
            break
        }
        return currentFingerprint(presentation) == status.fingerprint ? .failed : .unverified
    }
}
