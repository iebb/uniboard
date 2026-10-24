import Foundation

// The Font Rules screens' logic, kept apart from SwiftUI so it can be
// tested: exact copy (docs/font-rules-copy.md), the rule editor's draft and
// its validation, Try Text's limit, and saved-order edits. Rules are always
// saved through FontRuleStore, which validates and never repairs.

/// Exact strings from docs/font-rules-copy.md. Counts are one sentence each,
/// never assembled from fragments.
enum FontRuleCopy {
    static let defaultFonts = "Default fonts"
    static let usingDefaultFonts = "Using default fonts"
    static let unavailable = "Font unavailable"
    static let cannotDisplay = "Font can’t display this text"
    static let usingNextMatchingFont = "Using the next matching font."
    static let multipleFonts = "Multiple fonts used"
    static let reversedRange = "The end of the range must come after or equal the start."
    static let unknownBlock = "This Unicode block isn’t recognized."
    static let chooseFont = "Choose a font."

    static func using(_ fontName: String?) -> String {
        fontName.map { "Using " + $0 } ?? usingDefaultFonts
    }

    /// Valid scalars only; surrogates are never counted.
    static func codePoints(_ count: Int) -> String {
        count == 1 ? "1 code point" : "\(count.formatted()) code points"
    }

    static func overridden(_ count: Int) -> String {
        count == 1 ? "Another rule takes priority for 1 code point."
            : "Another rule takes priority for \(count.formatted()) code points."
    }

    /// "U+2190–U+21FF"
    static func range(_ first: UInt32, _ last: UInt32) -> String {
        FontRuleScalar.label(first) + "–" + FontRuleScalar.label(last)
    }

    /// The caption naming the rule a result comes from.
    static func source(_ selector: FontRuleSelector) -> String {
        switch selector {
        case .codePoint: return "Code point rule"
        case let .range(first, last): return "Range rule " + range(first, last)
        case let .block(block): return "Unicode block rule " + block.name
        }
    }

    /// Coverage of the named face, never a fallback. `previewOnly` when only
    /// the sample characters were checked.
    static func supports(_ supported: Int, of total: Int, previewOnly: Bool = false) -> String {
        "Supports \(supported.formatted()) of \(total.formatted()) " + (previewOnly ? "preview characters" : "code points")
    }

    static func showUnsupportedFonts(_ count: Int) -> String {
        count == 1 ? "Show 1 Unsupported Font" : "Show \(count.formatted()) Unsupported Fonts"
    }

    static func duplicate(_ kind: FontRuleKind) -> String {
        switch kind {
        case .codePoint: return "A rule for this code point already exists."
        case .range: return "A rule for this range already exists."
        case .block: return "A rule for this block already exists."
        }
    }

    static func message(_ error: FontRuleInputError) -> String {
        switch error {
        case .invalid: return "Enter a valid Unicode code point, such as U+0041."
        case .surrogate: return "Surrogate code points can’t be used here."
        case .multipleScalars: return "Enter one code point. This text contains more than one."
        }
    }

    static func message(_ problem: FontRuleDraft.Problem) -> String {
        switch problem {
        case let .input(error): return message(error)
        case .reversed: return reversedRange
        case .unknownBlock: return unknownBlock
        }
    }

    /// The Settings row's trailing value.
    static func ruleCount(_ count: Int) -> String { count == 0 ? "None" : count.formatted() }
}

/// What the rule editor holds before Save: raw field text, so a typing
/// mistake is shown rather than silently corrected.
struct FontRuleDraft: Equatable {
    enum Problem: Error, Hashable {
        case input(FontRuleInputError)
        case reversed
        case unknownBlock
    }

    var kind: FontRuleKind
    var codePoint = ""
    var from = ""
    var to = ""
    var block: FontRuleBlock?
    var face: FontFaceReference?
    /// The saved rule being edited; nil while adding.
    var editingID: String?

    init(kind: FontRuleKind, face: FontFaceReference? = nil) {
        self.kind = kind
        self.face = face
    }

    init(editing rule: FontRule) {
        kind = rule.selector.kind
        face = rule.face
        editingID = rule.id
        switch rule.selector {
        case let .codePoint(value): codePoint = FontRuleScalar.label(value)
        case let .range(first, last):
            from = FontRuleScalar.label(first)
            to = FontRuleScalar.label(last)
        case let .block(value): block = value
        }
    }

    /// The selector the fields describe; nil while they are still empty.
    /// `blocks` is the full base block table, never a ConScript one.
    func selector(blocks: [UnicodeBlock]) -> Result<FontRuleSelector, Problem>? {
        switch kind {
        case .codePoint:
            guard !codePoint.isEmpty else { return nil }
            return FontRuleScalar.parse(codePoint).map(FontRuleSelector.codePoint).mapError(Problem.input)
        case .range:
            let first = from.isEmpty ? nil : FontRuleScalar.parse(from)
            let last = to.isEmpty ? nil : FontRuleScalar.parse(to)
            if case let .failure(error)? = first { return .failure(.input(error)) }
            if case let .failure(error)? = last { return .failure(.input(error)) }
            guard case let .success(start)? = first, case let .success(end)? = last else { return nil }
            return start <= end ? .success(.range(first: start, last: end)) : .failure(.reversed)
        case .block:
            guard let block else { return nil }
            return block.isRecognized(in: blocks) ? .success(.block(block)) : .failure(.unknownBlock)
        }
    }

    /// Another saved rule for exactly the same code point, range or block.
    func duplicate(of selector: FontRuleSelector, in rules: [FontRule]) -> FontRule? {
        rules.first { $0.id != editingID && FontRuleOrdering.sameTarget($0.selector, selector) }
    }

    /// The rule to save: a valid selector, a chosen font and no duplicate.
    func rule(in rules: [FontRule], blocks: [UnicodeBlock], newID: String = UUID().uuidString) -> FontRule? {
        guard case let .success(selector)? = selector(blocks: blocks), let face, duplicate(of: selector, in: rules) == nil else { return nil }
        return FontRule(id: editingID ?? newID, selector: selector, face: face)
    }

    /// The saved rules with this draft added or put in place of the rule it edits.
    func applied(_ rule: FontRule, to rules: [FontRule]) -> [FontRule] {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return rules + [rule] }
        var next = rules
        next[index] = rule
        return next
    }
}

/// Try Text: what was typed, limited to 32 characters (grapheme clusters).
/// Nothing typed here is stored or exported.
enum FontRuleTryText {
    static let limit = 32

    static func trimmed(_ text: String) -> String { String(text.prefix(limit)) }

    /// One entry per character, in typed order; a joined character or emoji is one.
    static func characters(_ text: String) -> [String] { trimmed(text).map(String.init) }

    /// True when a character is made of more than one code point.
    static func hasJoinedCharacters(_ characters: [String]) -> Bool {
        characters.contains { $0.unicodeScalars.count > 1 }
    }

    /// True when every result is the same, so one row describes the text.
    static func allSame<Result: Equatable>(_ results: [Result]) -> Bool {
        results.dropFirst().allSatisfy { $0 == results.first }
    }
}

/// Edits that keep the saved order, which is the priority tie-break: the
/// list never sorts rules, and a move stays within its own kind.
enum FontRuleOrdering {
    static func sameTarget(_ lhs: FontRuleSelector, _ rhs: FontRuleSelector) -> Bool {
        switch (lhs, rhs) {
        case let (.block(left), .block(right)): return left.name == right.name
        default: return lhs == rhs
        }
    }

    /// Indexes in `rules` of the rules of one kind, in saved order.
    static func indices(of kind: FontRuleKind, in rules: [FontRule]) -> [Int] {
        rules.indices.filter { rules[$0].selector.kind == kind }
    }

    /// Moves rules within one kind's section (List offsets), leaving every
    /// other rule where it was. Nil when an offset doesn't exist.
    static func moving(_ rules: [FontRule], kind: FontRuleKind, from source: IndexSet, to destination: Int) -> [FontRule]? {
        let slots = indices(of: kind, in: rules)
        guard !source.isEmpty, source.allSatisfy({ slots.indices.contains($0) }), (0...slots.count).contains(destination) else { return nil }
        let section = slots.map { rules[$0] }
        var remaining = section.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: source.map { section[$0] }, at: destination - source.count(in: 0..<destination))
        var next = rules
        for (slot, rule) in zip(slots, remaining) { next[slot] = rule }
        return next
    }

    static func codePointRule(_ codePoint: UInt32, in rules: [FontRule]) -> FontRule? {
        rules.first { $0.selector == .codePoint(codePoint) }
    }

    /// Character detail: sets this code point's own rule to `face`, keeping
    /// its place when it already exists.
    static func settingFace(_ face: FontFaceReference, forCodePoint codePoint: UInt32, in rules: [FontRule],
                            newID: String = UUID().uuidString) -> [FontRule] {
        guard let index = rules.firstIndex(where: { $0.selector == .codePoint(codePoint) }) else {
            return rules + [FontRule(id: newID, selector: .codePoint(codePoint), face: face)]
        }
        var next = rules
        next[index].face = face
        return next
    }

    /// "Clear Preference": removes the code point's own rule, never the font.
    static func clearing(codePoint: UInt32, in rules: [FontRule]) -> [FontRule] {
        rules.filter { $0.selector != .codePoint(codePoint) }
    }
}

/// Range and block tiles and the picker sample show the chosen face itself:
/// its representative characters (the assigned characters it can draw,
/// letters first; see `representative`), in that face. When it
/// draws none of them, or its file is missing, they show the first assigned
/// characters in system rendering at 40 % opacity, so a fallback never looks
/// applied. A single code point always shows its own character.
struct FontRuleSample: Equatable, Sendable {
    /// The picker's sample strip; a tile uses the first one.
    static let previewLimit = 12

    let codePoints: [UInt32]
    /// Drawn in the named face; otherwise system rendering.
    let inFace: Bool
    /// System rendering at 40 %: a face was named but can't draw any of it.
    let dimmed: Bool

    /// `drawn` is what the face draws (nil when its file is missing);
    /// `assigned` is the first assigned characters, for the fallback.
    static func resolve(hasFace: Bool, drawn: [UInt32]?, assigned: [UInt32]) -> FontRuleSample {
        guard hasFace else { return FontRuleSample(codePoints: assigned, inFace: false, dimmed: false) }
        if let drawn, !drawn.isEmpty { return FontRuleSample(codePoints: drawn, inFace: true, dimmed: false) }
        return FontRuleSample(codePoints: assigned, inFace: false, dimmed: true)
    }

    /// The cache identity: face, range, how many, the edition's assigned
    /// characters, and the font library revision.
    static func cacheKey(face: FontFaceReference, first: UInt32, last: UInt32, limit: Int, edition: String, revision: String) -> String {
        "\(face.identityKey)|\(face.postScriptName)|\(first)-\(last)|\(limit)|\(edition)|\(revision)"
    }

    /// Whether a character shows its own glyph: spaces, controls, format
    /// characters and invisible ones show a stand-in, so they never count as
    /// drawn by the face. Private-use characters do count.
    static func showsGlyph(_ character: UnicodeCharacter) -> Bool {
        !character.isInvisible && !["Cc", "Cf", "Cs", "Cn", "Zs", "Zl", "Zp"].contains(character.category)
    }

    /// Representative-character order (design §4), by General Category:
    /// letters, numbers, symbols, punctuation, anything else, then modifiers
    /// and marks last. Modifier letters (Lm) and modifier symbols (Sk) count
    /// as modifiers, so Greek in Roboto starts at Ά, not ʹ U+0374.
    enum Group: Int, CaseIterable {
        case letter, number, symbol, punctuation, other, modifier

        init(category: String) {
            switch category {
            case "Lm", "Sk": self = .modifier
            default:
                switch category.first {
                case "L": self = .letter
                case "N": self = .number
                case "S": self = .symbol
                case "P": self = .punctuation
                case "M": self = .modifier
                default: self = .other
                }
            }
        }
    }

    /// The representative characters of `rows` (chart rows of `columns`, in
    /// code point order): those `category` returns a General Category for
    /// (the face draws it and it shows its own glyph), ordered by `Group`,
    /// keeping code point order inside each group, at most `limit`. One
    /// pass, with a buffer of at most `limit` per group; it stops early once
    /// the first group is full. `checkpoint` runs every `stride` assigned
    /// code points so a caller can cancel or yield.
    static func representative(rows: [UnicodeChartRow], columns: Int, limit: Int, stride: Int = 1024,
                               category: (UInt32) -> String?, checkpoint: () async throws -> Void) async rethrows -> [UInt32] {
        guard limit > 0 else { return [] }
        var buffers = [[UInt32]](repeating: [], count: Group.allCases.count)
        var sinceCheck = 0
        scan: for row in rows {
            for column in 0..<columns where row.isAssigned(column: column) {
                let value = row.start + UInt32(column)
                if let category = category(value) {
                    let group = Group(category: category).rawValue
                    if buffers[group].count < limit {
                        buffers[group].append(value)
                        if group == 0 && buffers[group].count == limit { break scan }
                    }
                }
                sinceCheck += 1
                if sinceCheck == stride {
                    sinceCheck = 0
                    try await checkpoint()
                }
            }
        }
        return Array(buffers.joined().prefix(limit))
    }
}
