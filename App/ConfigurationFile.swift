import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// A Uniboard configuration: TOML text, declared in Info.plist as an
    /// imported type with the `toml` extension.
    static let uniboardConfiguration = UTType(importedAs: "ad.neko.uniboard.toml", conformingTo: .plainText)
}

/// Every copy on the Configuration screens (docs/font-rules-copy.md).
enum ConfigurationCopy {
    static let title = "Configuration"
    static let export = "Export Configuration"
    static let importTitle = "Import Configuration"
    /// Undo covers imports and editor applies alike: one recovery history (msg702).
    static let undo = "Undo Last Configuration Change"
    static let header = "Save your settings, layouts, favorites, font rules and Copy Image options in a TOML file, or import a configuration from Files."
    static let privacy = "Favorites and custom key text are included and may be personal. Typing history, scratchpad text and font files aren’t included."
    static let portability = "Fonts aren’t included or downloaded automatically. Some font choices may need fonts added on the other device."
    /// The app can't know which colors or scale the keyboard kept without Full Access.
    static let keyboardColors = "Copy Image colors and scale chosen in the keyboard without Full Access aren’t included in this file."
    static let preparing = "Preparing configuration…"
    static let ready = "Configuration ready to share"
    static let exportFailed = "Couldn’t export configuration"
    static let exportFailedBody = "Try again. Your configuration hasn’t changed."
    static let tryAgain = "Try Again"

    static let review = "Review Import"
    static let intro = "This will replace your current configuration. Review the changes before continuing."
    static let noChanges = "No changes to import"
    static let changes = "Changes"
    static let missingSections = "Sections missing from this file will reset to defaults."
    static let overwrite = "Your current favorites and custom key layouts will be replaced."
    static func fontsBody(_ count: Int) -> String {
        count == 1
            ? "Rules using this font will be kept. Other fonts will be used until it’s available. Nothing will be downloaded."
            : "Their rules will be kept. Other fonts will be used until these fonts are available. Nothing will be downloaded."
    }
    static let backup = "Your previous configuration will be kept so you can undo this import."
    static let replace = "Replace Configuration"
    static let replacing = "Replacing configuration…"
    static let imported = "Configuration imported"
    static let importFailed = "Couldn’t import configuration"
    static let unchanged = "Your current configuration hasn’t changed."
    static let changedTitle = "Your configuration changed"
    static let changedBody = "Changes were made after this preview. Review the import again before replacing your configuration."
    static let reviewAgain = "Review Again"
    static let replaceFailed = "Couldn’t replace configuration"
    static let replaceFailedBody = "Your previous configuration is still in use."
    /// Replace or Undo failed and the state in effect couldn't be verified (Camo msg409).
    static let unconfirmedBody = "Some settings may have changed. Check your configuration before trying again."
    static let ignoredSettings = "Ignored settings"
    static let ignoredSettingsFooter = "These older settings won’t be applied. Your editable keyboard layout takes precedence."
    static func ignoredSetting(_ name: String) -> String { "Ignored setting, \(name)" }

    static let undoTitle = "Undo last configuration change?"
    static let undoBody = "Restore your previous configuration. Changes made since then will also be replaced."
    static let restore = "Restore Previous Configuration"
    static let restored = "Previous configuration restored"
    static let restoreFailed = "Couldn’t restore configuration"

    // The configuration editor (docs/config-editor-copy.md, design/config-editor/design.md).
    static let edit = "Edit Configuration"
    static let editTextLabel = "Configuration text"
    static let editHelper = "Edit your configuration in TOML. Validate checks your edits without changing your settings. Apply saves them."
    static let editUnchecked = "Edits haven’t been checked."
    static let editChecking = "Checking configuration…"
    static let editValid = "Configuration is valid. Your settings haven’t changed."
    static let editValidWarnings = "Configuration is valid. Review the warnings before applying."
    static let editInvalid = "Fix these errors before applying"
    static let editUnchanged = "Your settings haven’t changed."
    static let editEmpty = "Enter a configuration before validating or applying."
    static let editErrorHint = "Moves the cursor to this line."
    static let editValidate = "Validate"
    static let editApply = "Apply"
    static let discardTitle = "Discard edits?"
    static let discardBody = "Your edits haven’t been applied."
    static let discard = "Discard Edits"
    static let keepEditing = "Keep Editing"
    static let applied = "Configuration applied"
    static let editChangedBody = "Settings changed while you were editing. Review the changes again before applying."

    static func checking(_ name: String) -> String { "Checking \(name)…" }
    /// "Imported today at 18:40", "Imported yesterday at 9:05", "Imported 3 Oct 2026 at 18:40".
    static func importedAt(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        changedAt(date, source: .importFile, now: now, calendar: calendar)
    }
    /// The Undo row's caption: "Imported …" after an import, "Applied …"
    /// after an editor apply, "Changed …" when the pointer didn't record
    /// which (docs/config-editor-copy.md).
    static func changedAt(_ date: Date, source: ConfigurationChangeSource?, now: Date = Date(), calendar: Calendar = .current) -> String {
        let verb = switch source {
        case .importFile: "Imported"
        case .editor: "Applied"
        case nil: "Changed"
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "\(verb) today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(verb) yesterday at \(time)"
        }
        return "\(verb) \(date.formatted(date: .abbreviated, time: .omitted)) at \(time)"
    }
    static func fontsUnavailable(_ count: Int) -> String { count == 1 ? "1 font unavailable" : "\(count.formatted()) fonts unavailable" }
    static func moreProblems(_ count: Int) -> String { count == 1 ? "1 More Problem" : "\(count.formatted()) More Problems" }
    /// "14 KB · Format version 1": the file's own size and format version.
    static func fileCaption(bytes: Int, version: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + " · Format version \(version)"
    }
}

/// The review's wording in each mode: an import keeps its own strings
/// unchanged; the editor's come from docs/config-editor-copy.md.
struct ConfigurationReviewWording: Equatable {
    let title: String
    let intro: String
    let noChanges: String
    let missingSections: String
    let backup: String
    let primary: String
    let inProgress: String
    let success: String
    /// The error screen's title, when the text can't be read.
    let problemsTitle: String
    let failureTitle: String
    /// Only when the previous configuration is verified in use.
    let failureBody: String
    let changedBody: String

    static let importFile = ConfigurationReviewWording(
        title: ConfigurationCopy.review, intro: ConfigurationCopy.intro, noChanges: ConfigurationCopy.noChanges,
        missingSections: ConfigurationCopy.missingSections, backup: ConfigurationCopy.backup, primary: ConfigurationCopy.replace,
        inProgress: ConfigurationCopy.replacing, success: ConfigurationCopy.imported, problemsTitle: ConfigurationCopy.importFailed,
        failureTitle: ConfigurationCopy.replaceFailed, failureBody: ConfigurationCopy.replaceFailedBody, changedBody: ConfigurationCopy.changedBody)

    static let editor = ConfigurationReviewWording(
        title: "Review Changes", intro: "These edits will replace your current configuration.", noChanges: "No changes to apply",
        missingSections: "Sections missing from this configuration will reset to defaults.",
        backup: "Your previous configuration will be kept so you can undo these changes.", primary: ConfigurationCopy.editApply,
        inProgress: "Applying configuration…", success: ConfigurationCopy.applied, problemsTitle: ConfigurationCopy.editInvalid,
        failureTitle: "Couldn’t apply configuration",
        // True only because the editor keeps the draft whenever an apply fails.
        failureBody: "Your previous configuration is still in use. Your edits are still here.",
        changedBody: ConfigurationCopy.editChangedBody)
}

extension ConfigurationImportModel.Mode {
    var wording: ConfigurationReviewWording { self == .editor ? .editor : .importFile }
}

/// The app's side of the configuration: what is in effect now, export, and
/// replacing or restoring it under the shared writer lock. The keyboard
/// never sees TOML; it reads the JSON snapshots a replacement writes.
@MainActor
struct ConfigurationService {
    var location = SharedConfigurationLocation.shared
    var defaults = UserDefaults.standard

    /// The app presentation defaults as a generation stores them.
    var presentation: Data { AppPresentationSettings.encode(AppPresentationSettings.capture(defaults)) }

    /// The configuration in effect and the fingerprint a replacement must
    /// still match; the fingerprint is nil before the shared location exists.
    func current() -> (configuration: UniboardConfiguration, fingerprint: String?) {
        SymbolBoardStore.shared.refreshFavorites()
        let presentation = self.presentation
        let configuration = UniboardConfiguration.capture(directory: location.currentDirectory(),
                                                          presentation: AppPresentationSettings.capture(defaults),
                                                          favorites: SymbolBoardStore.shared.favoriteTexts)
        return (configuration, location.currentFingerprint(presentation: presentation))
    }

    /// The faces of `faces` this device can't load now.
    func unavailableFaces(_ faces: [FontFaceReference]) -> [FontFaceReference] {
        faces.filter { !FontRulePreferences.shared.isAvailable($0) }
    }

    func undoStatus() -> ConfigurationUndoStatus? { location.undoStatus(presentation: presentation) }

    /// After a replacement or restore: the app adopts the new generation's
    /// presentation defaults and every store reads its file again.
    func adoptCurrentConfiguration() {
        ConfigurationRecovery.adoptCurrentPresentation(location: location, defaults: defaults)
        CatalogPreferences.shared.refreshEdition()
        FontRulePreferences.shared.reload()
        KeyboardKeyPreferences.shared.refresh()
        SymbolBoardStore.shared.adoptReplacement()
    }

    /// The informational `in_library` flag: the face is one of the fonts
    /// added to the library (an imported file or an installed face).
    nonisolated static func inLibrary(_ face: FontFaceReference, fonts: [CustomFont]) -> Bool {
        switch face.identity {
        case let .file(sha256, _, _): return fonts.contains { $0.installed != true && $0.sha256 == sha256 }
        case let .process(postScriptName, _): return fonts.contains { $0.installed == true && $0.postScriptName == postScriptName }
        }
    }

    /// Writes the export to a fresh temporary folder under its suggested name.
    nonisolated static func writeExport(_ data: Data, date: Date = Date()) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigurationExport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ConfigurationCodec.exportFilename(date: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads at most one byte over the import limit from a file the user
    /// chose, inside its security scope; never reads past that limit.
    nonisolated static func readImport(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinated: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
            coordinated = Result {
                let handle = try FileHandle(forReadingFrom: readable)
                defer { try? handle.close() }
                return try handle.read(upToCount: ConfigurationCodec.maximumBytes + 1) ?? Data()
            }
        }
        if let coordinationError { throw coordinationError }
        return try coordinated.get()
    }
}

/// Presents the system share sheet for a file from the top view controller.
enum ConfigurationShareSheet {
    @MainActor
    static func present(_ url: URL, completion: @escaping () -> Void, dismissed: @escaping () -> Void) -> Bool {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController else { return false }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in dismissed() }
        // iPad needs an anchor; on iPhone the share sheet comes up from the bottom.
        if UIDevice.current.userInterfaceIdiom == .pad, let popover = controller.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true, completion: completion)
        return true
    }
}
