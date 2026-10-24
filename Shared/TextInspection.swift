import Foundation

/// The keyboard's read-only Inspect Text analysis of exactly the excerpt the
/// text preview showed: grapheme clusters, scalar metadata, the three counts
/// and normalization status. Nothing is normalized, stored or logged; the
/// inspected text never changes. Wording: docs/inspection-capitalization-copy.md.
enum TextInspectionWording {
    static let title = "Inspect Text"
    static let codePointsSection = "Code Points"
    static let normalizationSection = "Normalization"
    static let normalizationHelper = "Normalization can change how text is represented. These checks don’t change your text."
    static let totalsHelp = "A grapheme cluster groups code points that form one text unit, such as a letter with an accent or a joined emoji. UTF-16 code units measure how the text is encoded."
    static let scopeNote = "Only the text shown in the preview is inspected. Your text won’t be changed."
    static let markerNote = "Markers for invisible characters and combining marks are shown only in the preview."
    static let snapshotNote = "This is a snapshot of the preview. Reopen Inspect to check updated text."
    static let notAvailable = "Not available"
    static let noBlock = "No Unicode block"
    static let copyText = "Copy Text"
    static let copyCodePoints = "Copy Code Points"
    static let copyCodePointsHint = "Copies the code point sequence, not the original text."
    static let textCopied = "Text copied"
    static let codePointsCopied = "Code points copied"
    static let tryAgain = "Try again. Your text hasn’t changed."
    static let fullAccessRequired = "To copy from the inspector, allow Full Access for Uniboard in your keyboard settings. You can still inspect text and type without it."
    static let copyBlocked = "iOS isn’t allowing this keyboard to copy. You can still inspect text and type normally."
    // Copy each form and encoding (design/inspect/copy-forms/design.md §4;
    // final wording Camo msg504).
    static let encodingsSection = "Encodings"
    static let showAll = "Show All"
    static let showLess = "Show Less"
    static let copyHexHint = "Copies the full hexadecimal value"
    static let changeArrow = " → "

    static func bytes(_ count: Int) -> String {
        count == 1 ? "1 byte · hex" : "\(count.formatted()) bytes · hex"
    }

    static func codeUnits(_ count: Int) -> String {
        count == 1 ? "1 code unit · hex" : "\(count.formatted()) code units · hex"
    }

    /// The line after the shown changes: "+3 more".
    static func moreChanges(_ count: Int) -> String { "+\(count.formatted()) more" }

    static func moreChangesSpoken(_ count: Int) -> String {
        count == 1 ? "1 more change" : "\(count.formatted()) more changes"
    }

    /// A change that happens more than once: "×3".
    static func occurrences(_ count: Int) -> String { "×\(count.formatted())" }

    static func occurrencesSpoken(_ count: Int) -> String { "\(count.formatted()) occurrences" }

    static func showAll(_ encoding: TextEncodingForm) -> String { "Show all " + encoding.unitsName }

    static func showFewer(_ encoding: TextEncodingForm) -> String { "Show fewer " + encoding.unitsName }

    static func codePoints(_ count: Int) -> String {
        count == 1 ? "1 code point" : "\(count.formatted()) code points"
    }

    static func graphemeClusters(_ count: Int) -> String {
        count == 1 ? "1 grapheme cluster" : "\(count.formatted()) grapheme clusters"
    }

    static func utf16CodeUnits(_ count: Int) -> String {
        count == 1 ? "1 UTF-16 code unit" : "\(count.formatted()) UTF-16 code units"
    }

    static func unassigned(in version: String) -> String { "Unassigned in Unicode \(version)" }

    static func versionNote(_ version: String) -> String {
        "Character details use Unicode \(version). Grouping and normalization use this version of iOS."
    }

    static func cluster(_ index: Int, count: Int) -> String {
        "Grapheme cluster \(index), \(codePoints(count))"
    }

    /// What a copy puts on the pasteboard, in the notice's and the
    /// announcement's words: "NFC text", "UTF-8 hex".
    private static func copyObject(_ target: TextInspectionCopyTarget) -> String {
        switch target {
        case .text: return "text"
        case .codePoints: return "code points"
        case .form(let form): return form.rawValue + " text"
        case .encoding(let encoding): return encoding.rawValue + " hex"
        }
    }

    static func copyFailed(_ target: TextInspectionCopyTarget) -> String {
        "Couldn’t copy " + copyObject(target)
    }

    static func copied(_ target: TextInspectionCopyTarget) -> String {
        switch target {
        case .text: return textCopied
        case .codePoints: return codePointsCopied
        case .form, .encoding: return copyObject(target) + " copied"
        }
    }

    /// The VoiceOver label of a row's copy button: "Copy NFD text", "Copy UTF-8 hex".
    static func copyLabel(_ target: TextInspectionCopyTarget) -> String {
        switch target {
        case .text: return copyText
        case .codePoints: return copyCodePoints
        case .form, .encoding: return "Copy " + copyObject(target)
        }
    }

    /// "18.0.0" reads as "18.0"; "19.0.0 draft" as "19.0 draft".
    static func versionLabel(_ version: String) -> String {
        let draft = version.hasSuffix(" draft")
        let number = draft ? String(version.dropLast(6)) : version
        var parts = number.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3, parts[2] == "0" { parts.removeLast() }
        return parts.joined(separator: ".") + (draft ? " draft" : "")
    }

    static func codePointLabel(_ value: UInt32) -> String { String(format: "U+%04X", value) }
}

enum TextNormalizationForm: String, CaseIterable, Sendable {
    case nfc = "NFC", nfd = "NFD", nfkc = "NFKC", nfkd = "NFKD"

    var summary: String {
        switch self {
        case .nfc: return "Canonical composition"
        case .nfd: return "Canonical decomposition"
        case .nfkc: return "Compatibility composition"
        case .nfkd: return "Compatibility decomposition"
        }
    }

    /// The system's normalization of `text`; never applied to the host.
    func normalize(_ text: String) -> String {
        switch self {
        case .nfc: return text.precomposedStringWithCanonicalMapping
        case .nfd: return text.decomposedStringWithCanonicalMapping
        case .nfkc: return text.precomposedStringWithCompatibilityMapping
        case .nfkd: return text.decomposedStringWithCompatibilityMapping
        }
    }
}

/// Facts, not errors: shown in neutral colors with a symbol and words.
enum TextNormalizationStatus: Equatable, Sendable {
    case already, differs, unavailable

    var title: String {
        switch self {
        case .already: return "Already in this form"
        case .differs: return "Differs from this form"
        case .unavailable: return "Not available"
        }
    }

    /// The SF Symbol beside the status.
    var symbol: String {
        switch self {
        case .already: return "equal"
        case .differs: return "notequal"
        case .unavailable: return "minus"
        }
    }
}

struct TextNormalizationResult: Equatable, Sendable, Identifiable {
    let form: TextNormalizationForm
    let status: TextNormalizationStatus
    /// Every distinct per-cluster change, in order of first appearance.
    /// Empty unless the status is Differs and the per-cluster results add
    /// up exactly to normalizing the whole excerpt.
    let changes: [TextNormalizationChange]
    var id: String { form.rawValue }
    /// "NFC, already in this form"
    var accessibilityLabel: String { form.rawValue + ", " + status.title.lowercased() }

    /// At most this many change lines; the rest are counted, not listed.
    static let maximumChangeLines = 4

    var shownChanges: [TextNormalizationChange] { Array(changes.prefix(Self.maximumChangeLines)) }
    var hiddenChangeCount: Int { max(0, changes.count - Self.maximumChangeLines) }
    /// "+3 more", only when some changes aren't listed.
    var moreChanges: String? { hiddenChangeCount > 0 ? TextInspectionWording.moreChanges(hiddenChangeCount) : nil }

    /// The row's spoken summary: the description, then its status and each
    /// change line as written, without the panel's symbols.
    var accessibilityRowLabel: String { form.rawValue + ", " + form.summary.lowercased() }
    var accessibilityRowValue: String {
        var parts = [status.title.lowercased()]
        parts += shownChanges.map(\.accessibilityText)
        if hiddenChangeCount > 0 { parts.append(TextInspectionWording.moreChangesSpoken(hiddenChangeCount)) }
        return parts.joined(separator: ", ")
    }

    /// Copy is offered for Already and Differs; Not available may be wrong.
    var canCopy: Bool { status != .unavailable }

    /// Normalizes each cluster on its own and keeps the distinct changes,
    /// counting repeats. Returns none when joining the per-cluster results
    /// doesn't give exactly `whole` (reordering across cluster boundaries):
    /// a change line is never shown unless it is exact.
    static func changes(in clusters: [TextInspectionCluster], whole: String,
                        normalize: (String) -> String) -> [TextNormalizationChange] {
        var joined: [Unicode.Scalar] = []
        var changes: [TextNormalizationChange] = []
        var index: [[UInt32]: Int] = [:]
        for cluster in clusters {
            let after = Array(normalize(cluster.text).unicodeScalars)
            joined += after
            let before = cluster.scalars.map(\.value)
            let afterValues = after.map(\.value)
            guard afterValues != before else { continue }
            if let existing = index[before] {
                changes[existing].count += 1
            } else {
                index[before] = changes.count
                changes.append(TextNormalizationChange(display: cluster.tileText, before: before, after: afterValues))
            }
        }
        return joined == Array(whole.unicodeScalars) ? changes : []
    }
}

/// One changed grapheme cluster in a normalization row:
/// "é  U+0065 U+0301 → U+00E9", with " ×3" when it repeats.
struct TextNormalizationChange: Equatable, Sendable, Identifiable {
    /// The original cluster as the tiles draw it (marker display for marks
    /// and invisible characters). Never copied.
    let display: String
    let before: [UInt32]
    let after: [UInt32]
    var count = 1
    var id: [UInt32] { before }

    /// "U+0065 U+0301 → U+00E9"
    var codePoints: String {
        before.map(TextInspectionWording.codePointLabel).joined(separator: " ") + TextInspectionWording.changeArrow
            + after.map(TextInspectionWording.codePointLabel).joined(separator: " ")
    }

    /// "×3", only when the change happens more than once.
    var occurrences: String? { count > 1 ? TextInspectionWording.occurrences(count) : nil }

    /// The whole line as written: "é  U+0065 U+0301 → U+00E9 ×3".
    var line: String { display + "  " + codePoints + (occurrences.map { " " + $0 } ?? "") }

    /// As written, with "×3" read as "3 occurrences".
    var accessibilityText: String {
        display + "  " + codePoints + (count > 1 ? ", " + TextInspectionWording.occurrencesSpoken(count) : "")
    }
}

enum TextEncodingForm: String, CaseIterable, Sendable {
    case utf8 = "UTF-8", utf16 = "UTF-16"

    /// What its values are called: "UTF-8 bytes", "UTF-16 code units".
    var unitsName: String { self == .utf8 ? "UTF-8 bytes" : "UTF-16 code units" }
}

/// The excerpt's UTF-8 bytes or UTF-16 code units as uppercase hex, one
/// space between values: "43 61 CC 81" or "0043 D83D DE04". No prefix,
/// no byte-order mark; surrogates are their own units.
struct TextEncodingResult: Equatable, Sendable, Identifiable {
    let form: TextEncodingForm
    let count: Int
    let hex: String
    var id: String { form.rawValue }

    init(form: TextEncodingForm, text: String) {
        self.form = form
        switch form {
        case .utf8:
            count = text.utf8.count
            hex = text.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .utf16:
            count = text.utf16.count
            hex = text.utf16.map { String(format: "%04X", $0) }.joined(separator: " ")
        }
    }

    /// "26 bytes · hex", "16 code units · hex"
    var countLabel: String { form == .utf8 ? TextInspectionWording.bytes(count) : TextInspectionWording.codeUnits(count) }

    /// "UTF-8, 26 bytes, hex"
    var accessibilityLabel: String { form.rawValue + ", " + countLabel.replacingOccurrences(of: " · ", with: ", ") }

    var target: TextInspectionCopyTarget { .encoding(form) }

    /// Hex digits per value: 2 for a byte, 4 for a code unit.
    var valueWidth: Int { form == .utf8 ? 2 : 4 }

    /// The collapsed value: only the whole values that fit `maxLines` lines
    /// of `columns` monospaced characters, then " …" when any are left out.
    /// Never part of a value. Copy and Show All use the full `hex`.
    func collapsed(columns: Int, maxLines: Int, trailerColumns: Int = 2) -> (hex: String, truncated: Bool) {
        let fit = HexValueFit(count: count, valueWidth: valueWidth, columns: columns, maxLines: maxLines,
                              trailerColumns: trailerColumns)
        guard fit.truncated else { return (hex, false) }
        guard fit.shown > 0 else { return ("…", true) }
        return (String(hex.prefix(fit.shown * (valueWidth + 1) - 1)) + " …", true)
    }
}

/// How many whole hex values show when a value is collapsed to a few lines
/// (copy-forms §2): values are one space apart and wrap only between
/// values, so a line of `columns` monospaced characters holds
/// (columns + 1) / (valueWidth + 1) of them, and never less than one.
struct HexValueFit: Equatable, Sendable {
    let shown: Int
    let truncated: Bool

    /// When some values are left out, the last line keeps room for the
    /// trailer " …" (`trailerColumns`: the space plus the ellipsis).
    init(count: Int, valueWidth: Int, columns: Int, maxLines: Int, trailerColumns: Int = 2) {
        let perLine = max(1, (columns + 1) / (valueWidth + 1))
        let lines = max(1, maxLines)
        guard count > perLine * lines else {
            shown = count
            truncated = false
            return
        }
        let lastLine = min(perLine, max(0, (columns + 1 - trailerColumns) / (valueWidth + 1)))
        shown = perLine * (lines - 1) + lastLine
        truncated = true
    }
}

/// One label/value pair in an expanded code point row.
struct TextInspectionProperty: Equatable, Sendable {
    let title: String
    let value: String
    let identifier: String
    var monospaced = false
}

/// One scalar, in its original logical position.
struct TextInspectionScalar: Equatable, Sendable, Identifiable {
    /// The scalar's offset in the inspected text.
    let id: Int
    let value: UInt32
    /// The catalog's name, the unassigned wording or "Not available".
    let name: String
    /// True when `name` is the unassigned or missing wording, not a name.
    let nameIsNote: Bool
    /// "{categoryName} ({cat}) · {blockName}"; empty when nothing is known.
    let detail: String
    let properties: [TextInspectionProperty]
    let accessibilityCategoryBlock: String

    var label: String { TextInspectionWording.codePointLabel(value) }
    var accessibilityLabel: String { label + ", " + name }
}

/// One extended grapheme cluster and its scalars, in order.
struct TextInspectionCluster: Equatable, Sendable, Identifiable {
    /// Zero-based position among the clusters.
    let id: Int
    let text: String
    /// What the tile draws: the cluster itself, or the catalog's marker
    /// display for marks and invisible characters. Never copied.
    let tileText: String
    let usesMarker: Bool
    let scalars: [TextInspectionScalar]

    var accessibilityLabel: String { TextInspectionWording.cluster(id + 1, count: scalars.count) }
}

struct TextInspection: Equatable, Sendable {
    /// The frozen excerpt either side of the caret, without truncation marks.
    let before: String
    let after: String
    let clusters: [TextInspectionCluster]
    let normalization: [TextNormalizationResult]
    /// UTF-8 then UTF-16, from the same excerpt.
    let encodings: [TextEncodingResult]
    let codePointCount: Int
    let clusterCount: Int
    let utf16Count: Int
    let usesMarkers: Bool
    /// Only when the catalog knows a character this system doesn't.
    let versionNote: String?

    /// Inspection beyond this many scalars reports a processing failure
    /// rather than building an unbounded panel.
    static let maximumScalars = 1024

    var text: String { before + after }

    var totals: String {
        [TextInspectionWording.codePoints(codePointCount), TextInspectionWording.graphemeClusters(clusterCount),
         TextInspectionWording.utf16CodeUnits(utf16Count)].joined(separator: " · ")
    }

    /// "U+05D1 U+05BC …", the original scalars, never normalized.
    var codePointSequence: String {
        text.unicodeScalars.map { TextInspectionWording.codePointLabel($0.value) }.joined(separator: " ")
    }

    /// Exactly what a copy puts on the pasteboard; nil when that copy isn't
    /// offered (a form this system can't normalize reliably).
    func copyValue(for target: TextInspectionCopyTarget) -> String? {
        switch target {
        case .text: return text
        case .codePoints: return codePointSequence
        case .form(let form):
            guard normalization.first(where: { $0.form == form })?.canCopy == true else { return nil }
            return form.normalize(text)
        case .encoding(let encoding): return encodings.first { $0.form == encoding }?.hex
        }
    }

    /// The footnotes that apply, in order.
    var footnotes: [String] {
        var notes = [TextInspectionWording.scopeNote]
        if usesMarkers { notes.append(TextInspectionWording.markerNote) }
        notes.append(TextInspectionWording.snapshotNote)
        if let versionNote { notes.append(versionNote) }
        return notes
    }

    /// Removes the preview's own truncation marks, which are not text.
    static func frozenText(before: String, after: String, beforeTruncated: Bool, afterTruncated: Bool,
                           ellipsis: Unicode.Scalar = "…") -> (before: String, after: String) {
        // By scalar: a mark after the ellipsis would join it into one Character.
        var head = Substring(before)
        if beforeTruncated, head.unicodeScalars.first == ellipsis { head.unicodeScalars.removeFirst() }
        var tail = Substring(after)
        if afterTruncated, tail.unicodeScalars.last == ellipsis { tail.unicodeScalars.removeLast() }
        return (String(head), String(tail))
    }

    /// - Parameters:
    ///   - catalogVersion: the catalog's Unicode version, or nil when its
    ///     data is unavailable (then nothing is called unassigned).
    ///   - lookup: the catalog's character for a scalar; nil when unknown.
    ///   - systemAssigns: whether this system's Unicode data assigns a
    ///     scalar; grouping and normalization come from the system.
    static func analyze(before: String, after: String, catalogVersion: String?,
                        lookup: (UInt32) -> UnicodeCharacter?,
                        systemAssigns: (Unicode.Scalar) -> Bool = { $0.properties.age != nil }) -> TextInspection {
        let text = before + after
        var clusters: [TextInspectionCluster] = []
        var offset = 0
        var usesMarkers = false
        var systemLags = false
        let version = catalogVersion.map(TextInspectionWording.versionLabel)
        for character in text {
            let scalars = Array(character.unicodeScalars)
            let entries = scalars.map { lookup($0.value) }
            var rows: [TextInspectionScalar] = []
            for (scalar, entry) in zip(scalars, entries) {
                if let entry, entry.category != "Cn", !systemAssigns(scalar) { systemLags = true }
                rows.append(row(scalar.value, offset: offset, entry: entry, version: version))
                offset += 1
            }
            let tile = tile(String(character), entries: entries)
            usesMarkers = usesMarkers || tile.marker
            clusters.append(TextInspectionCluster(id: clusters.count, text: String(character), tileText: tile.text,
                                                  usesMarker: tile.marker, scalars: rows))
        }
        let original = Array(text.unicodeScalars)
        let normalization = TextNormalizationForm.allCases.map { form -> TextNormalizationResult in
            // Scalar equality: String == would treat canonical equivalents as equal.
            let normalized = form.normalize(text)
            let status: TextNormalizationStatus = systemLags ? .unavailable
                : Array(normalized.unicodeScalars) == original ? .already : .differs
            let changes = status == .differs
                ? TextNormalizationResult.changes(in: clusters, whole: normalized, normalize: form.normalize) : []
            return TextNormalizationResult(form: form, status: status, changes: changes)
        }
        return TextInspection(before: before, after: after, clusters: clusters, normalization: normalization,
                              encodings: TextEncodingForm.allCases.map { TextEncodingResult(form: $0, text: text) },
                              codePointCount: original.count, clusterCount: clusters.count, utf16Count: text.utf16.count,
                              usesMarkers: usesMarkers,
                              versionNote: systemLags ? version.map(TextInspectionWording.versionNote) : nil)
    }

    private static func row(_ value: UInt32, offset: Int, entry: UnicodeCharacter?, version: String?) -> TextInspectionScalar {
        let label = TextInspectionWording.codePointLabel(value)
        let missing = TextInspectionWording.notAvailable
        guard let entry else {
            return TextInspectionScalar(id: offset, value: value, name: missing, nameIsNote: true, detail: missing,
                properties: [TextInspectionProperty(title: "Code point", value: label, identifier: "codePoint", monospaced: true),
                             TextInspectionProperty(title: "Name", value: missing, identifier: "name"),
                             TextInspectionProperty(title: "Category", value: missing, identifier: "category"),
                             TextInspectionProperty(title: "Unicode block", value: missing, identifier: "block")],
                accessibilityCategoryBlock: missing + ", " + missing)
        }
        let unassigned = version != nil && entry.category == "Cn" && entry.name == "UNASSIGNED"
        let name: String
        if unassigned, let version { name = TextInspectionWording.unassigned(in: version) }
        else { name = entry.name.isEmpty ? missing : entry.name }
        let block: String
        switch entry.blockName {
        case "": block = missing
        case "No Block": block = TextInspectionWording.noBlock
        default: block = entry.blockName
        }
        let category = entry.category.isEmpty ? missing : "\(entry.categoryName) (\(entry.category))"
        let detail: String
        if unassigned { detail = entry.blockName == "No Block" || entry.blockName.isEmpty ? "" : block }
        else { detail = category + " · " + block }
        var properties = [TextInspectionProperty(title: "Code point", value: label, identifier: "codePoint", monospaced: true),
                          TextInspectionProperty(title: "Name", value: name, identifier: "name"),
                          TextInspectionProperty(title: "Category", value: category, identifier: "category"),
                          TextInspectionProperty(title: "Unicode block", value: block, identifier: "block")]
        if let script = entry.script, !script.isEmpty {
            properties.append(TextInspectionProperty(title: "Script", value: script, identifier: "script"))
        }
        let categoryWords = entry.category.isEmpty ? missing : entry.categoryName
        return TextInspectionScalar(id: offset, value: value, name: name, nameIsNote: unassigned || name == missing,
                                    detail: detail, properties: properties,
                                    accessibilityCategoryBlock: categoryWords + ", " + block)
    }

    /// Spaces, line breaks, tabs, invisible characters, unassigned code
    /// points and marks use the catalog's own display in the tile.
    private static func needsMarker(_ entry: UnicodeCharacter) -> Bool {
        entry.isInvisible || entry.category.hasPrefix("M") || entry.category == "Cn"
            || [0x09, 0x0A, 0x0D, 0x20, 0x2028, 0x2029].contains(entry.codePoint)
    }

    private static func tile(_ text: String, entries: [UnicodeCharacter?]) -> (text: String, marker: Bool) {
        // A cluster that begins with a mark has no base to sit on.
        if let first = entries[0], first.category.hasPrefix("M") { return ("◌" + text, true) }
        // Only invisible parts, such as a space or CR LF: the first part's marker.
        if let first = entries[0], entries.allSatisfy({ $0.map(needsMarker) ?? false }) {
            return (first.displayText, true)
        }
        return (text, false)
    }
}

/// Which panel the Inspect button opens.
enum TextInspectionState: Equatable, Sendable {
    case ready(TextInspection)
    /// The preview showed nothing.
    case empty
    /// The host gave the keyboard no text context.
    case unavailable
    /// A field known not to share its text, such as secure entry.
    case restricted
    case failed

    /// Freezes the excerpt as drawn. Inspection never needs Full Access
    /// and never reads beyond the excerpt.
    static func inspect(before: String, after: String, beforeTruncated: Bool, afterTruncated: Bool,
                        contextAvailable: Bool, restricted: Bool, catalogVersion: String?,
                        lookup: (UInt32) -> UnicodeCharacter?,
                        systemAssigns: (Unicode.Scalar) -> Bool = { $0.properties.age != nil }) -> TextInspectionState {
        if restricted { return .restricted }
        let frozen = TextInspection.frozenText(before: before, after: after,
                                               beforeTruncated: beforeTruncated, afterTruncated: afterTruncated)
        let count = frozen.before.unicodeScalars.count + frozen.after.unicodeScalars.count
        if count == 0 { return contextAvailable ? .empty : .unavailable }
        if count > TextInspection.maximumScalars { return .failed }
        return .ready(TextInspection.analyze(before: frozen.before, after: frozen.after, catalogVersion: catalogVersion,
                                             lookup: lookup, systemAssigns: systemAssigns))
    }

    var inspection: TextInspection? {
        if case .ready(let inspection) = self { return inspection }
        return nil
    }

    /// The centered state's SF Symbol, title and text; nil when ready.
    var message: (symbol: String, title: String, text: String)? {
        switch self {
        case .ready: return nil
        case .empty: return ("text.magnifyingglass", "No text to inspect", "Show some text in the preview, then choose Inspect.")
        case .unavailable: return ("text.badge.xmark", "Preview text unavailable", "This app hasn’t made text available to the keyboard.")
        case .restricted: return ("lock", "Inspection unavailable here", "This field doesn’t share text with the keyboard.")
        case .failed: return ("exclamationmark.triangle", "Couldn’t inspect this text", "Close and try again. Your text hasn’t changed.")
        }
    }
}

/// What one copy button copies. Each has its own confirmation and failure
/// wording; all share the panel's one Full Access state.
enum TextInspectionCopyTarget: Hashable, Sendable {
    case text, codePoints
    case form(TextNormalizationForm)
    case encoding(TextEncodingForm)
}

/// The result of one pasteboard write.
enum TextInspectionCopyOutcome: Equatable, Sendable {
    case copied
    /// Full Access is off: the documented requirement for a keyboard to
    /// use the general pasteboard.
    case fullAccessRequired
    /// The write didn't take, for a reason iOS doesn't report.
    case failed
}

/// Where every copy in the panel is: Copy Text, Copy Code Points and each
/// form and encoding row. Never blocks inspection.
struct TextInspectionCopyState: Equatable, Sendable {
    enum Notice: Equatable, Sendable {
        case failed(TextInspectionCopyTarget)
        case fullAccessRequired
        /// Copying keeps failing with Full Access on: cause not verified.
        case blocked
    }

    private(set) var notice: Notice?
    /// The button showing its checkmark confirmation; one at a time, so
    /// any other copy ends the previous one.
    private(set) var confirmed: TextInspectionCopyTarget?
    private var consecutiveFailures = 0

    /// Without Full Access the panel already knows copying is blocked.
    init(hasFullAccess: Bool) {
        notice = hasFullAccess ? nil : .fullAccessRequired
    }

    /// Every copy button stays visible; all are disabled while copying is blocked.
    var canCopy: Bool { notice != .fullAccessRequired && notice != .blocked }

    /// A first failure offers Try Again; a second in a row means iOS isn't
    /// allowing the copy, with the cause unverified.
    mutating func record(_ outcome: TextInspectionCopyOutcome, for target: TextInspectionCopyTarget) {
        switch outcome {
        case .copied:
            consecutiveFailures = 0
            notice = nil
            confirmed = target
        case .fullAccessRequired:
            confirmed = nil
            notice = .fullAccessRequired
        case .failed:
            confirmed = nil
            consecutiveFailures += 1
            notice = consecutiveFailures >= 2 ? .blocked : .failed(target)
        }
    }

    /// Ends a confirmation after its 1.5 seconds.
    mutating func endConfirmation(_ target: TextInspectionCopyTarget) {
        if confirmed == target { confirmed = nil }
    }

    /// The notice's bold line (failures only) and its text.
    var noticeText: (title: String?, body: String)? {
        switch notice {
        case .failed(let target): return (TextInspectionWording.copyFailed(target), TextInspectionWording.tryAgain)
        case .fullAccessRequired: return (nil, TextInspectionWording.fullAccessRequired)
        case .blocked: return (nil, TextInspectionWording.copyBlocked)
        case nil: return nil
        }
    }
}
