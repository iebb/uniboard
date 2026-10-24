import Foundation

// Font rules: which preferred face to try for a code point, range or Unicode
// block (docs/font-rules-brief.md, docs/configuration-format.md §6). Pure and
// cheap: a rule list compiles once into a lookup structure the keyboard can
// query per grapheme without parsing anything.

/// Unicode scalar values a rule can name: U+0000…U+10FFFF without surrogates.
enum FontRuleScalar {
    static let surrogates: ClosedRange<UInt32> = 0xD800...0xDFFF
    static let maximum: UInt32 = 0x10FFFF

    static func isValid(_ value: UInt32) -> Bool { value <= maximum && !surrogates.contains(value) }

    static func label(_ value: UInt32) -> String { String(format: "U+%04X", value) }

    /// Valid scalars in `first...last`. Surrogates never count, so a range
    /// that crosses them applies only to the scalars on either side.
    static func validCount(_ first: UInt32, _ last: UInt32) -> Int {
        let upper = min(last, maximum)
        guard first <= upper else { return 0 }
        let low = max(first, surrogates.lowerBound)
        let high = min(upper, surrogates.upperBound)
        return Int(upper - first) + 1 - (low <= high ? Int(high - low) + 1 : 0)
    }

    /// Reads "U+0041", "u+41" or bare hex ("0041", 2–6 digits), or exactly one
    /// pasted scalar ("A", "ᚠ"). Counts scalars, not visible characters, and
    /// never quietly takes the first of several.
    static func parse(_ input: String) -> Result<UInt32, FontRuleInputError> {
        if input.unicodeScalars.count == 1 { return .success(input.unicodeScalars.first!.value) }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.unicodeScalars.count == 1 { return .success(trimmed.unicodeScalars.first!.value) }
        let prefixed = trimmed.hasPrefix("U+") || trimmed.hasPrefix("u+")
        let digits = prefixed ? trimmed.dropFirst(2) : Substring(trimmed)
        let allHex = digits.allSatisfy { $0.isASCII && $0.isHexDigit }
        guard allHex, (1...6).contains(digits.count), let value = UInt32(digits, radix: 16) else {
            return .failure(prefixed || allHex ? .invalid : .multipleScalars)
        }
        if surrogates.contains(value) { return .failure(.surrogate) }
        return value <= maximum ? .success(value) : .failure(.invalid)
    }
}

enum FontRuleInputError: Error, Hashable, Sendable {
    /// "Enter a valid Unicode code point, such as U+0041."
    case invalid
    /// "Surrogate code points can't be used here."
    case surrogate
    /// "Enter one code point. This text contains more than one."
    case multipleScalars
}

/// A named Unicode block: stable name, bounds, and the block table version
/// the bounds came from. Identity is name + bounds; the version is
/// informational because a named block's bounds never change.
struct FontRuleBlock: Hashable, Codable, Sendable {
    let name: String
    let first: UInt32
    let last: UInt32
    let unicodeVersion: String

    init(name: String, first: UInt32, last: UInt32, unicodeVersion: String) {
        self.name = name
        self.first = first
        self.last = last
        self.unicodeVersion = unicodeVersion
    }

    /// The base (never ConScript) block with exactly this name.
    init?(named name: String, in blocks: [UnicodeBlock] = UnicodeCatalog.shared.blocks, unicodeVersion: String = UnicodeCatalog.shared.version) {
        guard let block = blocks.first(where: { $0.name == name }) else { return nil }
        self.init(name: block.name, first: block.start, last: block.end, unicodeVersion: unicodeVersion)
    }

    /// Recognized only when the table has this exact name with these exact bounds.
    func isRecognized(in blocks: [UnicodeBlock]) -> Bool {
        blocks.contains { $0.name == name && $0.start == first && $0.end == last }
    }

    static func == (lhs: FontRuleBlock, rhs: FontRuleBlock) -> Bool {
        lhs.name == rhs.name && lhs.first == rhs.first && lhs.last == rhs.last
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(first)
        hasher.combine(last)
    }
}

enum FontRuleKind: Int, Hashable, Codable, Sendable { case codePoint, range, block }

enum FontRuleSelector: Hashable, Codable, Sendable {
    case codePoint(UInt32)
    /// Inclusive at both ends.
    case range(first: UInt32, last: UInt32)
    case block(FontRuleBlock)

    var kind: FontRuleKind {
        switch self {
        case .codePoint: return .codePoint
        case .range: return .range
        case .block: return .block
        }
    }

    var bounds: (first: UInt32, last: UInt32) {
        switch self {
        case let .codePoint(value): return (value, value)
        case let .range(first, last): return (first, last)
        case let .block(block): return (block.first, block.last)
        }
    }

    /// The span used for range priority and shown as "{n} code points".
    var validScalarCount: Int { FontRuleScalar.validCount(bounds.first, bounds.last) }

    /// Usable by the resolver without consulting a block table.
    var isWellFormed: Bool {
        switch self {
        case let .codePoint(value): return FontRuleScalar.isValid(value)
        case let .range(first, last): return FontRuleScalar.isValid(first) && FontRuleScalar.isValid(last) && first <= last
        case let .block(block): return !block.name.isEmpty && block.first <= block.last && block.last <= FontRuleScalar.maximum && validScalarCount > 0
        }
    }

    fileprivate var duplicateKey: String {
        switch self {
        case let .codePoint(value): return "c\(value)"
        case let .range(first, last): return "r\(first)-\(last)"
        case let .block(block): return "b" + block.name
        }
    }
}

/// A portable font face identity: the font library's identity
/// (`FontFaceRecord.locator`) without its device-local path. File faces are
/// identified by content hash, face index and variation instance; installed
/// faces by PostScript name. A filename is never part of the identity.
struct FontFaceReference: Hashable, Codable, Sendable {
    enum Identity: Hashable, Codable, Sendable {
        case file(sha256: String, faceIndex: Int, variations: [String: Double])
        case process(postScriptName: String, variations: [String: Double])
    }
    var source: FontSource
    /// Display only.
    var family: String
    /// Display only.
    var style: String
    var postScriptName: String
    var identity: Identity
    /// A Google Fonts library id ("google:<fileID>:<styleID>"): a hint, never trusted alone.
    var googleFaceID: String?

    init(source: FontSource, family: String, style: String, postScriptName: String, identity: Identity, googleFaceID: String? = nil) {
        self.source = source
        self.family = family
        self.style = style
        self.postScriptName = postScriptName
        self.identity = identity
        self.googleFaceID = googleFaceID
    }

    /// The portable reference for a library face, or nil when its identity
    /// can't be expressed portably (for example an axis that has no tag).
    init?(record: FontFaceRecord) {
        let identity: Identity
        switch record.locator {
        case let .file(_, sha256, faceIndex, axes):
            guard let tags = Self.tags(axes) else { return nil }
            identity = .file(sha256: sha256, faceIndex: faceIndex, variations: tags)
        case let .process(name, axes):
            guard let tags = Self.tags(axes) else { return nil }
            identity = .process(postScriptName: name, variations: tags)
        }
        self.init(source: record.source, family: record.family, style: record.style, postScriptName: record.postScriptName,
                  identity: identity, googleFaceID: record.id.rawValue.hasPrefix("google:") ? record.id.rawValue : nil)
        guard isValid else { return nil }
    }

    /// Canonical identity used to find the same face elsewhere; display names don't take part.
    var identityKey: String {
        switch identity {
        case let .file(sha256, faceIndex, axes): return "file:\(sha256):\(faceIndex):" + Self.axisKey(axes)
        case let .process(name, axes): return "ps:\(name):" + Self.axisKey(axes)
        }
    }

    func matches(_ record: FontFaceRecord) -> Bool { FontFaceReference(record: record)?.identityKey == identityKey }

    /// Well formed: 64 lowercase hex digits, a face index in 0…65535, 4-character
    /// axis tags with finite values, and short names without control characters.
    var isValid: Bool {
        guard Self.validText(family), Self.validText(style), Self.validText(postScriptName),
              googleFaceID.map(Self.validText) ?? true else { return false }
        switch identity {
        case let .file(sha256, faceIndex, axes):
            return sha256.utf8.count == 64 && sha256.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
                && (0...0xFFFF).contains(faceIndex) && Self.validAxes(axes)
        case let .process(name, axes):
            return Self.validText(name) && Self.validAxes(axes)
        }
    }

    private static func validText(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 255 && !text.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }
    }

    private static func validAxes(_ axes: [String: Double]) -> Bool {
        axes.count <= 64 && axes.allSatisfy { isTag($0.key) && $0.value.isFinite }
    }

    private static func isTag(_ key: String) -> Bool {
        key.utf8.count == 4 && key.utf8.allSatisfy { (0x20...0x7E).contains($0) }
    }

    /// OpenType axis tags from library variations, which may use CoreText's
    /// numeric axis identifiers. Nil when one has no tag or two disagree.
    static func tags(_ axes: [String: Double]) -> [String: Double]? {
        var result: [String: Double] = [:]
        for (key, value) in axes {
            guard let axisTag = Self.tag(key), value.isFinite, result[axisTag].map({ $0 == value }) ?? true else { return nil }
            result[axisTag] = value
        }
        return result
    }

    private static func tag(_ key: String) -> String? {
        guard let numeric = UInt32(key) else { return isTag(key) ? key : nil }
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: numeric >> UInt32($0)) }
        return bytes.allSatisfy({ (0x20...0x7E).contains($0) }) ? String(decoding: bytes, as: UTF8.self) : nil
    }

    private static func axisKey(_ axes: [String: Double]) -> String {
        axes.keys.sorted().map { "\($0)=\(axes[$0]!)" }.joined(separator: ",")
    }
}

struct FontRule: Hashable, Identifiable, Sendable {
    /// Local UI identity; not exported.
    var id: String
    var selector: FontRuleSelector
    var face: FontFaceReference

    init(id: String = UUID().uuidString, selector: FontRuleSelector, face: FontFaceReference) {
        self.id = id
        self.selector = selector
        self.face = face
    }
}

enum FontRuleLimits {
    static let maximumRules = 1024
    static let maximumRangeRules = 256
    static let maximumFaces = 256
}

/// Rule indexes refer to the validated array.
enum FontRuleIssue: Hashable, Sendable {
    case invalidCodePoint(rule: Int)
    case surrogate(rule: Int)
    case reversedRange(rule: Int)
    case unknownBlock(rule: Int, name: String)
    case duplicate(rule: Int, original: Int, kind: FontRuleKind)
    case invalidFace(rule: Int)
    case tooManyRules(limit: Int)
    case tooManyRanges(limit: Int)
    case tooManyFaces(limit: Int)
}

enum FontRuleValidator {
    /// Every problem, in rule order. `blocks` is the base Unicode block table;
    /// never pass a ConScript-split table.
    static func validate(_ rules: [FontRule], blocks: [UnicodeBlock] = UnicodeCatalog.shared.blocks) -> [FontRuleIssue] {
        var issues: [FontRuleIssue] = []
        if rules.count > FontRuleLimits.maximumRules { issues.append(.tooManyRules(limit: FontRuleLimits.maximumRules)) }
        if rules.filter({ $0.selector.kind == .range }).count > FontRuleLimits.maximumRangeRules {
            issues.append(.tooManyRanges(limit: FontRuleLimits.maximumRangeRules))
        }
        if Set(rules.map(\.face.identityKey)).count > FontRuleLimits.maximumFaces { issues.append(.tooManyFaces(limit: FontRuleLimits.maximumFaces)) }
        var seen: [String: Int] = [:]
        for (index, rule) in rules.enumerated() {
            if let issue = selectorIssue(rule.selector, rule: index, blocks: blocks) { issues.append(issue) }
            if !rule.face.isValid { issues.append(.invalidFace(rule: index)) }
            if let original = seen[rule.selector.duplicateKey] {
                issues.append(.duplicate(rule: index, original: original, kind: rule.selector.kind))
            } else {
                seen[rule.selector.duplicateKey] = index
            }
        }
        return issues
    }

    static func selectorIssue(_ selector: FontRuleSelector, rule index: Int, blocks: [UnicodeBlock]) -> FontRuleIssue? {
        switch selector {
        case let .codePoint(value):
            if value > FontRuleScalar.maximum { return .invalidCodePoint(rule: index) }
            return FontRuleScalar.surrogates.contains(value) ? .surrogate(rule: index) : nil
        case let .range(first, last):
            if max(first, last) > FontRuleScalar.maximum { return .invalidCodePoint(rule: index) }
            if FontRuleScalar.surrogates.contains(first) || FontRuleScalar.surrogates.contains(last) { return .surrogate(rule: index) }
            return first > last ? .reversedRange(rule: index) : nil
        case let .block(block):
            guard block.isRecognized(in: blocks) else { return .unknownBlock(rule: index, name: block.name) }
            return selector.validScalarCount > 0 ? nil : .surrogate(rule: index)
        }
    }
}

struct FontRuleMatch: Hashable, Sendable {
    let ruleIndex: Int
    let kind: FontRuleKind
}

/// Rules compiled once for lookups: exact code points in a dictionary, ranges
/// and blocks in sorted non-overlapping segments, each with its candidates
/// already in priority order. Malformed rules are skipped; validate first.
struct FontRuleSet: Sendable {
    let rules: [FontRule]
    private let exact: [UInt32: Int]
    /// Range then block rule indexes, highest priority first.
    private let priority: [Int]
    private let segmentStarts: [UInt32]
    private let segmentEnds: [UInt32]
    /// Candidates of segment k are `segmentRules[offsets[k]..<offsets[k + 1]]`.
    private let offsets: [Int]
    private let segmentRules: [Int]

    static let empty = FontRuleSet(rules: [])

    init(rules: [FontRule]) {
        self.rules = rules
        var exact: [UInt32: Int] = [:]
        var ranges: [(index: Int, count: Int)] = []
        var blocks: [Int] = []
        for (index, rule) in rules.enumerated() where rule.selector.isWellFormed {
            switch rule.selector {
            case let .codePoint(value): exact[value] = index
            case .range: ranges.append((index, rule.selector.validScalarCount))
            case .block: blocks.append(index)
            }
        }
        // Smallest span first; equal spans: the later rule first.
        ranges.sort { ($0.count, -$0.index) < ($1.count, -$1.index) }
        let priority = ranges.map { $0.index } + blocks.reversed()
        var boundaries = Set<UInt32>()
        for index in priority {
            let bounds = rules[index].selector.bounds
            boundaries.insert(bounds.first)
            if bounds.last < FontRuleScalar.maximum { boundaries.insert(bounds.last + 1) }
        }
        let sorted = boundaries.sorted()
        var starts: [UInt32] = []
        var ends: [UInt32] = []
        var offsets = [0]
        var segmentRules: [Int] = []
        for (position, start) in sorted.enumerated() {
            let matching = priority.filter { rules[$0].selector.bounds.first <= start && start <= rules[$0].selector.bounds.last }
            guard !matching.isEmpty else { continue }
            starts.append(start)
            ends.append(position + 1 < sorted.count ? sorted[position + 1] - 1 : FontRuleScalar.maximum)
            segmentRules += matching
            offsets.append(segmentRules.count)
        }
        self.exact = exact
        self.priority = priority
        segmentStarts = starts
        segmentEnds = ends
        self.offsets = offsets
        self.segmentRules = segmentRules
    }

    var isEmpty: Bool { rules.isEmpty }

    /// Rules to try for `scalar`, best first: its code point rule, every
    /// containing range from the smallest span (equal spans: later rule
    /// first), then its block rule. Empty means the default fonts. Callers
    /// fall through when a face is unavailable or can't draw the cluster.
    func candidates(for scalar: UInt32) -> [FontRuleMatch] {
        guard FontRuleScalar.isValid(scalar) else { return [] }
        var result: [FontRuleMatch] = []
        if let index = exact[scalar] { result.append(FontRuleMatch(ruleIndex: index, kind: .codePoint)) }
        var low = 0
        var high = segmentStarts.count
        while low < high {
            let middle = (low + high) / 2
            if segmentStarts[middle] <= scalar { low = middle + 1 } else { high = middle }
        }
        if low > 0 && scalar <= segmentEnds[low - 1] {
            for index in segmentRules[offsets[low - 1]..<offsets[low]] {
                result.append(FontRuleMatch(ruleIndex: index, kind: rules[index].selector.kind))
            }
        }
        return result
    }

    /// Candidates for one grapheme cluster, chosen by its anchor scalar.
    func candidates<S: StringProtocol>(forCluster cluster: S) -> [FontRuleMatch] {
        Self.anchor(of: cluster).map { candidates(for: $0) } ?? []
    }

    /// How many valid scalars of rule `index` a higher-priority rule takes:
    /// "Another rule takes priority for {n} code points."
    func overriddenScalarCount(for index: Int) -> Int {
        guard rules.indices.contains(index), rules[index].selector.isWellFormed, rules[index].selector.kind != .codePoint else { return 0 }
        let (first, last) = rules[index].selector.bounds
        var covered = exact.keys.filter { $0 >= first && $0 <= last }.map { (first: $0, last: $0) }
        for other in priority.prefix(while: { $0 != index }) {
            let bounds = rules[other].selector.bounds
            if bounds.first <= last && bounds.last >= first { covered.append((first: max(bounds.first, first), last: min(bounds.last, last))) }
        }
        var total = 0
        var next = first
        for interval in covered.sorted(by: { $0.first < $1.first }) where interval.last >= next {
            total += FontRuleScalar.validCount(max(interval.first, next), interval.last)
            next = interval.last + 1
        }
        return total
    }

    /// The scalar whose rules apply to a whole grapheme cluster: the first
    /// that isn't a combining mark (Mn, Mc, Me), ZWJ/ZWNJ or a variation
    /// selector; if there's none, the first scalar. Nil for empty text.
    static func anchor<S: StringProtocol>(of cluster: S) -> UInt32? {
        let scalars = cluster.unicodeScalars
        return (scalars.first { !isAnchorTransparent($0) } ?? scalars.first)?.value
    }

    private static let variationSelectors: [ClosedRange<UInt32>] = [0x180B...0x180D, 0x180F...0x180F, 0xFE00...0xFE0F, 0xE0100...0xE01EF]

    static func isAnchorTransparent(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return scalar.value == 0x200C || scalar.value == 0x200D || variationSelectors.contains { $0.contains(scalar.value) }
        }
    }
}
