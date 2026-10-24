import Foundation
import UIKit

/// One problem the check found. Syntax errors carry the checker's line and
/// column; every other problem has no location and is never guessed at.
struct ConfigurationEditorProblem: Equatable, Identifiable {
    let id: Int
    /// The checker's own message, shown unchanged (Camo msg707).
    let message: String
    let line: Int?
    let column: Int?

    init(id: Int, message: String) {
        self.id = id
        self.message = message
        let location = Self.location(in: message)
        line = location?.line
        column = location?.column
    }

    var isLocated: Bool { line != nil }

    /// The text shown for a problem. One place, so a wording change is one line.
    var text: String { message }

    /// "Check line 3, column 7: …" (`TOMLError.description`) → (3, 7).
    static func location(in message: String) -> (line: Int, column: Int)? {
        let prefix = "Check line "
        guard message.hasPrefix(prefix) else { return nil }
        let rest = message.dropFirst(prefix.count)
        guard let comma = rest.range(of: ", column "), let line = Int(rest[..<comma.lowerBound]), line > 0 else { return nil }
        let after = rest[comma.upperBound...]
        guard let colon = after.range(of: ": "), let column = Int(after[..<colon.lowerBound]), column > 0 else { return nil }
        return (line, column)
    }

    /// The UTF-16 offset (what UITextView's selectedRange counts) of a
    /// checker location: lines split at LF (a CRLF is one break), columns
    /// count Unicode scalars from 1, and a leading byte order mark isn't
    /// counted, as in `TOMLDocument`. Past the end of a line or the text,
    /// the end of that line or text.
    static func utf16Offset(in text: String, line: Int, column: Int) -> Int {
        var scalars = text.unicodeScalars[...]
        var offset = 0
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst(); offset = 1 }
        var currentLine = 1
        while currentLine < line, let scalar = scalars.first {
            scalars = scalars.dropFirst()
            offset += scalar.utf16.count
            if scalar == "\n" { currentLine += 1 }
        }
        var remaining = column - 1
        while remaining > 0, let scalar = scalars.first, scalar != "\n" {
            // Stop before the CR of a CRLF: it ends the line.
            if scalar == "\r", scalars.dropFirst().first == "\n" { break }
            scalars = scalars.dropFirst()
            offset += scalar.utf16.count
            remaining -= 1
        }
        return offset
    }
}

/// Edit Configuration (design/config-editor/design.md): the current
/// configuration as TOML text in front of the Import flow. Validate runs
/// the import check and writes nothing; Apply checks the current text again
/// and hands a valid result to the existing review, Replace and recovery.
@MainActor
final class ConfigurationEditorModel: ObservableObject, Identifiable {
    enum Status: Equatable {
        /// Opened, not edited: the helper text.
        case helper
        /// Edited since the last check.
        case unchecked
        case checking
        /// Valid; the lines are warnings (none: plainly valid).
        case valid(warnings: [String])
        case invalid([ConfigurationEditorProblem])
        /// Whitespace only: never a reset.
        case empty
    }

    enum Alert: Equatable {
        /// The configuration in effect changed since the editor opened.
        case changed
    }

    /// Where the text view should put the cursor (a UTF-16 offset), once.
    struct CursorRequest: Equatable {
        let id = UUID()
        let offset: Int
    }

    let id = UUID()
    /// nil while the configuration is being prepared.
    @Published private(set) var loaded: String?
    @Published private(set) var loadFailed = false
    @Published var text = "" {
        didSet {
            // Scalar by scalar: String == treats a normalization-only
            // change (é → e + U+0301) as no change, but it is an edit.
            guard !Self.same(text, oldValue), loaded != nil else { return }
            revision += 1
            status = isBlank ? .empty : .unchecked
        }
    }
    @Published private(set) var status = Status.helper
    @Published var alert: Alert?
    /// The review pushed after a valid Apply.
    @Published var review: ConfigurationImportModel? {
        didSet {
            // Back from a review that compared with a newer configuration
            // (Review Again in the review): that is what the user has seen.
            if review == nil, let oldValue, case let .review(shown) = oldValue.phase { fingerprint = shown.fingerprint }
        }
    }
    @Published private(set) var cursor: CursorRequest?

    /// The fingerprint of the configuration the text was loaded from, or last reviewed against.
    private(set) var fingerprint: String?
    private let environment: ConfigurationImportEnvironment
    private let encode: @Sendable (UniboardConfiguration) -> Data?
    private let announce: (String) -> Void
    /// Bumped by every edit: a check of older text never reports on newer text.
    private var revision = 0
    /// True while the "Your configuration changed" alert waits on a valid Apply.
    private var pending = false
    /// Set once a review pushed from this editor applied the text; kept
    /// after the review is popped or the sheet closes.
    private(set) var didApply = false

    init(environment: ConfigurationImportEnvironment,
         encode: @escaping @Sendable (UniboardConfiguration) -> Data?,
         announce: @escaping (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.environment = environment
        self.encode = encode
        self.announce = announce
    }

    /// The live editor: exports exactly as Export does and records an
    /// apply as an editor change for the Undo row.
    static func live() -> ConfigurationEditorModel {
        let fonts = CustomFontStore.shared.fonts
        return ConfigurationEditorModel(environment: .live(source: .editor), encode: { configuration in
            ConfigurationCodec.encode(configuration, inLibrary: { ConfigurationService.inLibrary($0, fonts: fonts) })
        })
    }

    var isEdited: Bool { loaded.map { !Self.same(text, $0) } ?? false }
    var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
    var isChecking: Bool { status == .checking }
    var canValidate: Bool { loaded != nil && !isChecking }
    var canApply: Bool { isEdited && !isBlank && !isChecking }
    /// Exact equality: same Unicode scalars, not canonical equivalence.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf8.count == b.utf8.count && a.utf8.elementsEqual(b.utf8)
    }

    /// The current configuration as Export writes it, encoded off the main thread.
    func load() async {
        guard loaded == nil else { return }
        let current = environment.current()
        fingerprint = current.fingerprint
        let encode = self.encode
        let configuration = current.configuration
        let data = await Task.detached { encode(configuration) }.value
        guard let data, let string = String(data: data, encoding: .utf8) else {
            loadFailed = true
            return
        }
        text = string
        loaded = string
    }

    /// Runs the import check on the current text. Never writes anything.
    func validate() async {
        _ = await check()
        announceStatus()
    }

    /// Checks the current text again; a valid result goes to the review,
    /// unless the configuration changed since the editor opened.
    func apply() async {
        guard canApply else { return }
        let checked = await check()
        announceStatus()
        guard let checked, case let .review(shown) = checked.phase else { return }
        if shown.fingerprint != fingerprint {
            pending = true
            alert = .changed
            return
        }
        push(checked)
    }

    /// "Review Again": the current text, checked again like Apply (status
    /// Checking, so Validate and Apply wait), against what is in effect now.
    /// An edit during that check drops the result: nothing older than the
    /// text on screen is ever reviewed.
    func reviewAgain() async {
        alert = nil
        guard pending else { return }
        pending = false
        let checked = await check()
        announceStatus()
        guard let checked, case let .review(shown) = checked.phase else { return }
        fingerprint = shown.fingerprint
        push(checked)
    }

    /// Cancel on the changed alert: nothing is applied.
    func cancelChanged() {
        alert = nil
        pending = false
    }

    private func push(_ checked: ConfigurationImportModel) {
        checked.onImported = { [weak self] in self?.didApply = true }
        review = checked
    }

    /// An error with a location: the cursor goes there.
    func focus(_ problem: ConfigurationEditorProblem) {
        guard let line = problem.line else { return }
        cursor = CursorRequest(offset: ConfigurationEditorProblem.utf16Offset(in: text, line: line, column: problem.column ?? 1))
    }

    /// The status's first line, for VoiceOver.
    var statusTitle: String {
        switch status {
        case .helper: ConfigurationCopy.editHelper
        case .unchecked: ConfigurationCopy.editUnchecked
        case .checking: ConfigurationCopy.editChecking
        case let .valid(warnings): warnings.isEmpty ? ConfigurationCopy.editValid : ConfigurationCopy.editValidWarnings
        case .invalid: ConfigurationCopy.editInvalid
        case .empty: ConfigurationCopy.editEmpty
        }
    }

    private func announceStatus() {
        guard status != .checking else { return }
        announce(statusTitle)
    }

    /// The import check (`ConfigurationImportModel.check`) on the current
    /// text: the checked model when valid, nil otherwise.
    private func check() async -> ConfigurationImportModel? {
        guard loaded != nil, !isChecking else { return nil }
        guard !isBlank else {
            status = .empty
            return nil
        }
        let revision = self.revision
        status = .checking
        let model = ConfigurationImportModel(fileName: ConfigurationCopy.edit, mode: .editor, environment: environment)
        await model.check(Data(text.utf8))
        // Edited while checking: the result is for older text.
        guard revision == self.revision else { return nil }
        switch model.phase {
        case let .failed(problems):
            status = .invalid(problems.enumerated().map { ConfigurationEditorProblem(id: $0.offset, message: $0.element) })
            return nil
        case let .review(review):
            status = .valid(warnings: Self.warnings(review))
            return model
        default:
            status = .unchecked
            return nil
        }
    }

    /// One line per warning: sections that reset, fonts this device can't
    /// load, retired settings that won't be applied.
    static func warnings(_ review: ConfigurationReview) -> [String] {
        var lines: [String] = []
        if !review.diff.missingSections.isEmpty { lines.append(ConfigurationReviewWording.editor.missingSections) }
        if !review.fontWarnings.isEmpty {
            lines.append(ConfigurationCopy.fontsUnavailable(review.fontWarnings.count) + ": " + review.unavailableFonts.joined(separator: ", "))
        }
        if !review.ignoredSettings.isEmpty {
            lines.append(ConfigurationCopy.ignoredSettings + ": " + review.ignoredSettings.map(\.key).joined(separator: ", "))
        }
        return lines
    }
}
