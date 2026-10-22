import Foundation

enum UnicodeEdition: String, CaseIterable, Identifiable, Sendable {
    case latest, previous, older, draft
    var id: String { rawValue }
    /// Small provenance manifests are sufficient for settings/preferences; do
    /// not map any character catalog merely to label or resolve a selection.
    var versionLabel: String { Self.versionLabel(for: self, metadata: Self.bundledVersionLabels) }
    /// Resolve the same missing-provenance label for bundled or custom metadata.
    static func versionLabel(for edition: UnicodeEdition, metadata: [UnicodeEdition: String]) -> String {
        metadata[edition] ?? "Unavailable"
    }
    var title: String {
        // The bounded loader supplies a numeric label or "Unavailable". Both
        // have a first component; prefix also safely handles an empty label.
        let number = versionLabel.prefix { $0 != "." }
        return self == .draft ? "Unicode \(number) Draft" : "Unicode \(number)"
    }
    var catalog: UnicodeCatalog {
        switch self {
        case .latest: return .latest
        case .previous: return .previous
        case .older: return .older
        case .draft: return .shared
        }
    }
    var emojiCatalog: EmojiCatalog {
        switch self {
        case .latest: return .latest
        case .previous: return .previous
        case .older: return .older
        case .draft: return .shared
        }
    }
    /// Latest/draft follow a track. Historical selections retain their actual
    /// version rather than silently changing when the rolling bundle advances.
    var selectionIdentifier: String {
        self == .latest || self == .draft ? rawValue : versionLabel
    }
    static func resolve(selectionIdentifier: String?) -> UnicodeEdition {
        switch selectionIdentifier {
        case "latest": return .latest
        case "draft": return .draft
        case let value?:
            return [UnicodeEdition.previous, .older].first {
                unicodeVersionKey($0.versionLabel) > 0 && $0.versionLabel == value
            } ?? .latest
        case nil: return .latest
        }
    }
    /// Only the draft is bundled. Its manifest also names the final editions,
    /// which are the draft limited to characters of that version or earlier.
    private static let bundledVersionLabels: [UnicodeEdition: String] = {
        #if SWIFT_PACKAGE
        let bundles = [Bundle.module, Bundle.main, Bundle(for: UnicodeCatalog.self)]
        #else
        let bundles = [Bundle.main, Bundle(for: UnicodeCatalog.self)]
        #endif
        var labels: [UnicodeEdition: String] = [:]
        for bundle in bundles where labels.isEmpty {
            guard let url = bundle.url(forResource: "UnicodeSources", withExtension: "json"),
                  let stream = InputStream(url: url) else { continue }
            stream.open()
            // Each manifest is a few KiB. Bound the read even if a bundle's
            // metadata is malformed, without mapping its catalog at all.
            var buffer = [UInt8](repeating: 0, count: 65_537)
            var count = 0
            while count < buffer.count {
                let read = buffer.withUnsafeMutableBytes { bytes in
                    stream.read(bytes.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: count),
                                maxLength: bytes.count - count)
                }
                if read <= 0 { if read < 0 { count = buffer.count }; break }
                count += read
            }
            stream.close()
            guard count > 0, count <= 65_536,
                  let identity = try? JSONDecoder().decode(UnicodeSourceIdentity.self, from: Data(buffer.prefix(count))) else { continue }
            labels = editionLabels(identity)
        }
        return labels
    }()
    /// The draft's label and each final edition's, which must be an earlier final release.
    fileprivate static func editionLabels(_ identity: UnicodeSourceIdentity) -> [UnicodeEdition: String] {
        let draftKey = unicodeVersionKey(identity.versionLabel)
        guard draftKey > 0, identity.isDraft, identity.versionLabel.hasSuffix(" draft"),
              identity.edition == nil || identity.edition == UnicodeEdition.draft.rawValue else { return [:] }
        var labels: [UnicodeEdition: String] = [.draft: identity.versionLabel]
        for edition in [UnicodeEdition.latest, .previous, .older] {
            if let label = identity.editions?[edition.rawValue], !label.hasSuffix(" draft"),
               (1..<draftKey).contains(unicodeVersionKey(label)) { labels[edition] = label }
        }
        return labels
    }
}

enum UnicodeSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst, oldestFirst, codePoint
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        case .codePoint: return "Code point"
        }
    }
}

func unicodeVersionKey(_ version: String) -> Int {
    let number = version.hasSuffix(" draft") ? String(version.dropLast(6)) : version
    let components = number.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(components.count), components.allSatisfy({
        !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber }
    }), let major = Int(components[0]),
          let minor = components.count > 1 ? Int(components[1]) : 0,
          minor < 100, major <= (Int.max - minor) / 100 else { return 0 }
    return major * 100 + minor
}

enum CatalogSearchQueryPolicy {
    static let maximumUTF8Bytes = 4096
    static func accepts(_ query: String) -> Bool {
        // Consume at most 4097 bytes before folding, splitting or allocating
        // token buffers, including for pasted/foreign Unicode strings.
        query.utf8.prefix(maximumUTF8Bytes + 1).count <= maximumUTF8Bytes
    }
    static func terms(in normalized: String) -> [String] {
        var seen = Set<Substring>()
        return normalized.split(separator: " ").compactMap { seen.insert($0).inserted ? String($0) : nil }
    }
    static func containsWholeTerm(_ term: String, in normalized: String) -> Bool {
        // Normalization retains Unicode letters/numbers and uses ASCII spaces
        // for all boundaries. Do not use ASCII-only regular-expression words.
        guard !term.isEmpty else { return false }
        var start = normalized.startIndex
        while start < normalized.endIndex, !Task.isCancelled,
              let range = normalized.range(of: term, range: start..<normalized.endIndex) {
            if (range.lowerBound == normalized.startIndex || normalized[normalized.index(before: range.lowerBound)] == " ")
                && (range.upperBound == normalized.endIndex || normalized[range.upperBound] == " ") { return true }
            start = range.upperBound
        }
        return false
    }
}

/// Formal kinds come from NameAliases.txt. Informative chart aliases never
/// acquire correction status merely because a character's name is misleading.
struct UnicodeNameAlias: Identifiable, Hashable, Sendable, Decodable {
    let name: String
    let kind: String
    var id: String { kind + ":" + name }
    var isFormal: Bool { ["correction", "control", "alternate", "figment", "abbreviation", "namesListFormal"].contains(kind) }
    var source: String {
        if kind == "informal" || kind == "namesListFormal" { return "NamesList.txt" }
        return isFormal ? "NameAliases.txt" : "Unknown"
    }
    var kindLabel: String {
        switch kind {
        case "correction": return "Formal correction"
        case "control": return "Control name"
        case "alternate": return "Formal alternate"
        case "figment": return "Formal figment"
        case "abbreviation": return "Formal abbreviation"
        case "namesListFormal": return "Names list formal alias"
        default: return "Informative alias"
        }
    }
}

/// An informative related-character reference, not an equivalence mapping.
struct UnicodeCrossReference: Identifiable, Hashable, Sendable, Decodable {
    let codePoint: UInt32
    let name: String
    var id: UInt32 { codePoint }
    var codePointLabel: String { String(format: "U+%04X", codePoint) }
}

/// One Unicode scalar. A displayed placeholder never changes the inserted text.
struct UnicodeCharacter: Identifiable, Hashable, Sendable {
    let codePoint: UInt32
    let name: String
    let detail: String
    let blockName: String
    let category: String
    let age: String?
    let versionSortKey: Int
    let combiningClass: Int?
    let bidirectionalClass: String?
    let script: String?
    let decomposition: String?
    let nameAliases: [UnicodeNameAlias]
    let annotations: [String]
    let namesListSection: String?
    let sectionAnnotations: [String]
    let crossReferences: [UnicodeCrossReference]
    let unicode1Name: String?
    let numericValue: String?
    let numericType: String?
    let simpleUppercase: UInt32?
    let simpleLowercase: UInt32?
    let simpleTitlecase: UInt32?
    /// True when Unicode defines both a text and an emoji presentation sequence.
    let hasPresentationForms: Bool
    private let invisible: Bool

    var id: UInt32 { codePoint }
    var text: String { Unicode.Scalar(codePoint).map { String($0) } ?? "" }
    var codePointLabel: String { String(format: "U+%04X", codePoint) }
    var isInvisible: Bool { invisible }
    /// The text (VS15) and emoji (VS16) presentation sequences, when Unicode defines both.
    var presentationForms: (text: String, emoji: String)? {
        hasPresentationForms ? (text + "\u{FE0E}", text + "\u{FE0F}") : nil
    }
    var categoryName: String { Self.categoryName(category) }
    static func categoryName(_ category: String) -> String { UnicodeCatalog.categoryDescriptions[category] ?? category }
    var displayText: String {
        switch codePoint {
        case 0x20: return "␣"
        case 0x09: return "⇥"
        case 0x0A, 0x0D, 0x2028, 0x2029: return "↵"
        default:
            if invisible { return "◌" }
            if category.hasPrefix("M") { return "◌" + text }
            if category == "Cn" { return "◇" }
            // Charts show a character that also has an emoji form as text.
            return presentationForms?.text ?? text
        }
    }

    init(codePoint: UInt32, name: String, detail: String, blockName: String,
         category: String, isInvisible: Bool = false, age: String? = nil,
         versionSortKey: Int? = nil, combiningClass: Int? = nil,
         bidirectionalClass: String? = nil, script: String? = nil, decomposition: String? = nil,
         nameAliases: [UnicodeNameAlias] = [], annotations: [String] = [],
         namesListSection: String? = nil, sectionAnnotations: [String] = [],
         crossReferences: [UnicodeCrossReference] = [], unicode1Name: String? = nil,
         numericValue: String? = nil, numericType: String? = nil,
         simpleUppercase: UInt32? = nil, simpleLowercase: UInt32? = nil, simpleTitlecase: UInt32? = nil,
         hasPresentationForms: Bool = false) {
        self.hasPresentationForms = hasPresentationForms
        self.codePoint = codePoint
        self.name = name
        self.detail = detail
        self.blockName = blockName
        self.category = category
        self.age = age
        self.versionSortKey = versionSortKey ?? age.map(unicodeVersionKey) ?? 0
        self.combiningClass = combiningClass
        self.bidirectionalClass = bidirectionalClass
        self.script = script
        self.decomposition = decomposition
        self.nameAliases = nameAliases
        self.annotations = annotations
        self.namesListSection = namesListSection
        self.sectionAnnotations = sectionAnnotations
        self.crossReferences = crossReferences
        self.unicode1Name = unicode1Name
        self.numericValue = numericValue
        self.numericType = numericType
        self.simpleUppercase = simpleUppercase
        self.simpleLowercase = simpleLowercase
        self.simpleTitlecase = simpleTitlecase
        self.invisible = isInvisible
    }
}

struct UnicodeBlock: Identifiable, Hashable, Sendable, Decodable {
    let name: String
    let start: UInt32
    let end: UInt32

    var id: UInt32 { start }
    var rangeLabel: String { String(format: "U+%04X–U+%04X", start, end) }
    var subtitle: String {
        guard start <= end, end <= 0x10FFFF else { return "Invalid code-point range" }
        if start >= 0xD800 && end <= 0xDFFF { return "UTF-16 surrogate code units" }
        return "\(Int(end - start + 1).formatted()) code points · \(start < 0x10000 ? "Basic plane" : "Plane \(start >> 16)")"
    }
    private static let examples: [UInt32: UInt32] = [
        0x0000: 0x0041, 0x0080: 0x00C6, 0x0300: 0x0301, 0x0370: 0x03A9,
        0x0400: 0x0416, 0x0590: 0x05D0, 0x0600: 0x0639, 0x0900: 0x0905,
        0x2000: 0x2022, 0x20A0: 0x20AC, 0x2100: 0x2126, 0x2190: 0x2192,
        0x2200: 0x2211, 0x2300: 0x2318, 0x2500: 0x253C, 0x2580: 0x2588,
        0x2600: 0x2605, 0x2700: 0x2708, 0x2800: 0x283F, 0x3000: 0x3005,
        0x3040: 0x3042, 0x30A0: 0x30A2, 0x4E00: 0x4E2D, 0xAC00: 0xD55C,
        0x1F300: 0x1F308, 0x1F600: 0x1F603, 0x1F680: 0x1F680,
        0x1F900: 0x1F981, 0x1FA70: 0x1FA77
    ]
    /// A ConScript block split out of a Private Use area.
    private var isConScript: Bool { UCSUR.isPrivateUse(start) && !name.contains("Private Use") }
    /// The hand-picked example, or nil when the block has none.
    var curatedSymbol: String? {
        if start >= 0xD800 && end <= 0xDFFF || name.contains("Private Use") { return "◇" }
        return Self.examples[start] == nil && !isConScript ? nil : symbol
    }
    var symbol: String {
        if start >= 0xD800 && end <= 0xDFFF || name.contains("Private Use") { return "◇" }
        if isConScript { return String(Unicode.Scalar(start)!) }
        let scalar = Unicode.Scalar(Self.examples[start] ?? start)
        guard let scalar else { return "◇" }
        return name.contains("Combining") ? "◌" + String(scalar) : String(scalar)
    }
}

/// Immutable, memory-mapped Unicode data shared by the containing app and keyboard.
/// Browsing materializes only a page, rather than hundreds of thousands of objects.
final class UnicodeCatalog: @unchecked Sendable {
    static let shared = UnicodeCatalog()
    static let latest = shared.limited(to: .latest)
    static let previous = shared.limited(to: .previous)
    static let older = shared.limited(to: .older)

    let edition: UnicodeEdition
    /// A final edition shows only characters assigned by its version.
    private let isLimited: Bool
    /// Present when Private Use reads as the ConScript Unicode Registry assigns it.
    private let conscript: UCSUR.Registry?
    private let variantLock = NSLock()
    private var conscriptVariant: UnicodeCatalog?
    let blocks: [UnicodeBlock]
    private let representativeLock = NSLock()
    private var representatives: [UInt32: String] = [:]
    let version: String
    let resourceError: String?
    private let data: Data
    private let recordCount: Int
    private let recordOffset: Int
    private let rangeCount: Int
    private let rangeOffset: Int
    private let poolOffset: Int
    private let properties: UnicodePropertyData
    private let formatVersion: Int
    private let recordSize: Int
    private static let rangeSize = 16
    private static let categories = "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn".split(separator: " ").map(String.init)
    private static let bidiClasses = "L R AL EN ES ET AN CS NSM BN B S WS ON LRE LRO RLE RLO PDF LRI RLI FSI PDI".split(separator: " ").map(String.init)
    fileprivate static let categoryDescriptions = [
        "Lu": "Uppercase letter", "Ll": "Lowercase letter", "Lt": "Titlecase letter",
        "Lm": "Modifier letter", "Lo": "Letter", "Mn": "Nonspacing combining mark",
        "Mc": "Spacing combining mark", "Me": "Enclosing combining mark", "Nd": "Decimal digit",
        "Nl": "Letter number", "No": "Number", "Pc": "Connector punctuation",
        "Pd": "Dash punctuation", "Ps": "Opening punctuation", "Pe": "Closing punctuation",
        "Pi": "Initial quotation mark", "Pf": "Final quotation mark", "Po": "Punctuation",
        "Sm": "Mathematical symbol", "Sc": "Currency symbol", "Sk": "Modifier symbol",
        "So": "Symbol", "Zs": "Space separator", "Zl": "Line separator",
        "Zp": "Paragraph separator", "Cc": "Control character", "Cf": "Format character",
        "Co": "Private-use character", "Cn": "Unassigned code point"
    ]

    /// Loads the bundled draft. Pass a resource directory or UnicodeCatalog.ucd
    /// URL for tests/custom bundles.
    init(resourceURL: URL? = nil) {
        edition = .draft
        isLimited = false
        conscript = nil
        let catalogURL: URL?
        let blocksURL: URL?
        let propertiesURL: URL?
        let sourcesURL: URL?
        let suffix = ""
        if let resourceURL {
            let directory = resourceURL.pathExtension == "ucd" ? resourceURL.deletingLastPathComponent() : resourceURL
            catalogURL = resourceURL.pathExtension == "ucd" ? resourceURL : directory.appendingPathComponent("UnicodeCatalog\(suffix).ucd")
            blocksURL = directory.appendingPathComponent("Blocks\(suffix).json")
            propertiesURL = directory.appendingPathComponent("UnicodeProperties\(suffix).json")
            sourcesURL = directory.appendingPathComponent("UnicodeSources\(suffix).json")
        } else {
            #if SWIFT_PACKAGE
            let bundles = [Bundle.module, Bundle.main, Bundle(for: UnicodeCatalog.self)]
            #else
            let bundles = [Bundle.main, Bundle(for: UnicodeCatalog.self)]
            #endif
            catalogURL = bundles.lazy.compactMap { $0.url(forResource: "UnicodeCatalog\(suffix)", withExtension: "ucd") }.first
            blocksURL = bundles.lazy.compactMap { $0.url(forResource: "Blocks\(suffix)", withExtension: "json") }.first
            propertiesURL = bundles.lazy.compactMap { $0.url(forResource: "UnicodeProperties\(suffix)", withExtension: "json") }.first
            sourcesURL = bundles.lazy.compactMap { $0.url(forResource: "UnicodeSources\(suffix)", withExtension: "json") }.first
        }
        blocks = blocksURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([UnicodeBlock].self, from: $0) }
            .flatMap { Self.validBlocks($0) ? $0 : nil } ?? []
        let loaded = catalogURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        let decodedProperties = propertiesURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(UnicodePropertyData.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
        let sourceIdentity = sourcesURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(UnicodeSourceIdentity.self, from: $0) }
        // Bundled editions have a provenance manifest. A custom/legacy fixture
        // need not have one, but any manifest it supplies is authoritative.
        let sourceIdentityRequired = resourceURL == nil || sourcesURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let loadedVersion = loaded.flatMap { bytes -> String? in
            guard Self.valid(bytes) else { return nil }
            let start = Self.uint32(bytes, 24) + Self.uint32(bytes, 32)
            return String(decoding: bytes[start..<(start + Self.uint32(bytes, 36))], as: UTF8.self)
        }
        let sourceIdentityMatches = sourceIdentity.map {
            // The bundled base is always the draft; final editions are views of it.
            $0.versionLabel == loadedVersion && $0.isDraft && $0.versionLabel.hasSuffix(" draft")
                && ($0.edition == nil || $0.edition == UnicodeEdition.draft.rawValue)
        } ?? false
        if let loaded, let versionLabel = loadedVersion, !sourceIdentityRequired || sourceIdentityMatches {
            data = loaded
            recordCount = Self.uint32(loaded, 8)
            recordOffset = Self.uint32(loaded, 12)
            rangeCount = Self.uint32(loaded, 16)
            rangeOffset = Self.uint32(loaded, 20)
            poolOffset = Self.uint32(loaded, 24)
            formatVersion = Self.uint32(loaded, 44)
            recordSize = formatVersion >= 3 ? 44 : 28
            version = versionLabel
            let matchingProperties = decodedProperties.flatMap {
                $0.unicodeVersion == versionLabel && Self.validCoverage($0, data: loaded) ? $0 : nil
            }
            properties = matchingProperties ?? .empty
            resourceError = blocks.isEmpty ? "Unicode block resources could not be loaded."
                : matchingProperties == nil ? "Unicode property resources could not be loaded for this edition." : nil
        } else {
            properties = .empty
            data = Data()
            recordCount = 0
            recordOffset = 0
            rangeCount = 0
            rangeOffset = 0
            poolOffset = 0
            formatVersion = 0
            recordSize = 28
            version = "Unavailable"
            resourceError = "The offline Unicode catalog could not be loaded."
        }
    }

    /// A final edition: this catalog limited to characters of `edition`'s
    /// version or earlier. It shares the mapped data.
    func limited(to edition: UnicodeEdition) -> UnicodeCatalog {
        edition == .draft ? self : UnicodeCatalog(base: self, edition: edition)
    }

    private init(base: UnicodeCatalog, edition: UnicodeEdition) {
        self.edition = edition
        isLimited = true
        conscript = nil
        let key = unicodeVersionKey(edition.versionLabel)
        let spans = base.properties.assignedSpans.filter { !$0.draftAddition && $0.sortKey <= key }
        properties = UnicodePropertyData(unicodeVersion: base.properties.unicodeVersion, ages: base.properties.ages,
                                         scripts: base.properties.scripts, assignedSpans: spans,
                                         decompositions: base.properties.decompositions,
                                         presentationSequences: base.properties.presentationSequences)
        // Blocks with nothing assigned yet belong to a later version.
        blocks = base.blocks.filter { block in spans.contains { $0.start <= block.end && $0.end >= block.start } }
        version = key > 0 ? edition.versionLabel : "Unavailable"
        resourceError = key > 0 ? base.resourceError : "This Unicode edition is unavailable."
        data = base.data
        recordCount = base.recordCount
        recordOffset = base.recordOffset
        rangeCount = base.rangeCount
        rangeOffset = base.rangeOffset
        poolOffset = base.poolOffset
        formatVersion = base.formatVersion
        recordSize = base.recordSize
    }

    var usesConScript: Bool { conscript != nil }

    /// This edition with Private Use read as the ConScript Unicode Registry
    /// assigns it: its blocks, character names and properties. It shares the
    /// mapped data and is made once.
    func withConScript() -> UnicodeCatalog {
        guard conscript == nil else { return self }
        variantLock.lock()
        defer { variantLock.unlock() }
        if let conscriptVariant { return conscriptVariant }
        let variant = UnicodeCatalog(base: self, conscript: UCSUR.registry)
        conscriptVariant = variant
        return variant
    }

    private init(base: UnicodeCatalog, conscript: UCSUR.Registry) {
        edition = base.edition
        isLimited = base.isLimited
        self.conscript = conscript
        properties = base.properties
        blocks = UCSUR.splitting(base.blocks, with: conscript.blocks)
        version = base.version
        resourceError = base.resourceError
        data = base.data
        recordCount = base.recordCount
        recordOffset = base.recordOffset
        rangeCount = base.rangeCount
        rangeOffset = base.rangeOffset
        poolOffset = base.poolOffset
        formatVersion = base.formatVersion
        recordSize = base.recordSize
    }

    /// In a final edition, a character from a later version reads as unassigned.
    private func isAssigned(_ cp: UInt32) -> Bool {
        let spans = properties.assignedSpans
        var low = 0, high = spans.count
        while low < high {
            let mid = (low + high) / 2
            if spans[mid].end < cp { low = mid + 1 } else { high = mid }
        }
        return low < spans.count && spans[low].start <= cp
    }

    /// Every valid scalar can be inspected, including reserved/noncharacters.
    /// Surrogates and values above U+10FFFF are rejected because they cannot be text.
    func character(at codePoint: UInt32) -> UnicodeCharacter? {
        guard Unicode.Scalar(codePoint) != nil else { return nil }
        let block = block(containing: codePoint)?.name ?? "No Block"
        let later = isLimited && !isAssigned(codePoint)
        return data.withUnsafeBytes { bytes in
            if !later, let entry = conscript?.entry(at: codePoint) {
                return entry.character(blockName: block, age: age(at: codePoint), versionSortKey: sortKey(at: codePoint),
                                       script: script(at: codePoint))
            }
            if !later, let index = recordIndex(codePoint, bytes: bytes) {
                return character(record: index, blockName: block, bytes: bytes)
            }
            if !later, let range = algorithmicRange(codePoint, bytes: bytes) {
                let category = Self.categories[Int(bytes[range + 14])]
                let name = algorithmicName(codePoint, range: range, bytes: bytes)
                let description = bytes[range + 15] == 2
                    ? "Reserved for private agreements. Appearance depends on the font and application."
                    : Self.categoryDescriptions[category] ?? category
                return UnicodeCharacter(codePoint: codePoint, name: name, detail: description,
                                        blockName: block, category: category, age: age(at: codePoint),
                                        versionSortKey: sortKey(at: codePoint), combiningClass: 0,
                                        bidirectionalClass: "L", script: script(at: codePoint),
                                        decomposition: decomposition(at: codePoint))
            }
            let noncharacter = Self.isNoncharacter(codePoint)
            return UnicodeCharacter(codePoint: codePoint,
                                    name: noncharacter ? "NONCHARACTER" : "UNASSIGNED",
                                    detail: noncharacter ? "Permanently reserved for internal use. Not an assigned Unicode character."
                                        : "No character is assigned to this code point in Unicode \(version).",
                                    blockName: block, category: "Cn", isInvisible: true,
                                    age: later ? nil : age(at: codePoint),
                                    script: later ? (properties.unicodeVersion.isEmpty ? nil : "Unknown") : script(at: codePoint))
        }
    }

    /// Pagination counts assigned Unicode scalars, not unused code-point slots.
    /// This keeps sparse blocks useful and excludes UTF-16 surrogates.
    func characters(in block: UnicodeBlock, offset: Int = 0, limit: Int = 256,
                    order: UnicodeSortOrder = .codePoint) -> [UnicodeCharacter] {
        guard offset >= 0, limit > 0, block.start <= block.end, block.end <= 0x10FFFF else { return [] }
        let spans = properties.assignedSpans.compactMap { span -> UnicodeAssignedSpan? in
            guard span.start <= block.end && span.end >= block.start else { return nil }
            return UnicodeAssignedSpan(start: max(block.start, span.start), end: min(block.end, span.end),
                                       sortKey: span.sortKey, draftAddition: span.draftAddition)
        }
        return page(in: spans, offset: offset, limit: limit, order: order)
    }

    /// Code-chart rows of `columns` code points (at most 16) inside `block`
    /// that hold at least one assigned character, with a bit per assigned
    /// column. Built from assigned spans, without creating any characters.
    /// With `addedOnly`, only characters this edition adds are marked.
    func chartRows(in block: UnicodeBlock, columns: Int, addedOnly: Bool = false) -> [UnicodeChartRow] {
        guard (1...32).contains(columns), block.start <= block.end, block.end <= 0x10FFFF else { return [] }
        let spans = addedOnly ? addedSpans : properties.assignedSpans
        var low = 0, high = spans.count
        while low < high {
            let mid = (low + high) / 2
            if spans[mid].end < block.start { low = mid + 1 } else { high = mid }
        }
        let width = UInt32(columns)
        var rows: [UnicodeChartRow] = []
        var index = low
        while index < spans.count, spans[index].start <= block.end {
            let start = max(block.start, spans[index].start), end = min(block.end, spans[index].end)
            var point = start
            while point <= end {
                let rowStart = point - point % width
                let last = min(end, rowStart + width - 1)
                var bits: UInt32 = 0
                for column in (point - rowStart)...(last - rowStart) { bits |= 1 << column }
                if rows.last?.start == rowStart {
                    rows[rows.count - 1] = UnicodeChartRow(start: rowStart, assigned: rows[rows.count - 1].assigned | bits)
                } else {
                    rows.append(UnicodeChartRow(start: rowStart, assigned: bits))
                }
                if last == UInt32.max { break }
                point = last + 1
            }
            index += 1
        }
        return rows
    }

    /// Spans of characters this edition adds over the previous one: its own
    /// Unicode age, or draft additions not yet given an age.
    private var addedSpans: [UnicodeAssignedSpan] {
        let key = unicodeVersionKey(version)
        return properties.assignedSpans.filter { $0.draftAddition || $0.sortKey == key }
    }

    /// How many characters this edition adds over the previous one.
    var addedCount: Int { addedSpans.reduce(0) { $0 + Int($1.end - $1.start + 1) } }

    /// Characters this edition adds over the previous one, by code point.
    func addedCharacters(offset: Int = 0, limit: Int = 256) -> [UnicodeCharacter] {
        page(in: addedSpans, offset: offset, limit: limit, order: .codePoint)
    }

    /// A typical character for previewing `block`: its curated example, else
    /// its first visible assigned letter, then symbol, number, punctuation or mark.
    func representative(of block: UnicodeBlock) -> String {
        if let curated = block.curatedSymbol { return curated }
        representativeLock.lock()
        let cached = representatives[block.start]
        representativeLock.unlock()
        if let cached { return cached }
        let found = findRepresentative(of: block)
        representativeLock.lock()
        representatives[block.start] = found
        representativeLock.unlock()
        return found
    }

    private func findRepresentative(of block: UnicodeBlock) -> String {
        let ranks: [Character: Int] = ["L": 0, "S": 1, "N": 2, "P": 3, "M": 4]
        var best: (rank: Int, text: String)?
        var examined = 0
        for row in chartRows(in: block, columns: 16) {
            for column in 0..<16 where row.isAssigned(column: column) {
                guard let character = character(at: row.start + UInt32(column)), !character.isInvisible,
                      let rank = character.category.first.flatMap({ ranks[$0] }) else { continue }
                if rank == 0 { return character.displayText }
                if best.map({ rank < $0.rank }) ?? true { best = (rank, character.displayText) }
                examined += 1
                // Blocks without letters settle on their best early candidate.
                if examined >= 128, let best { return best.text }
            }
        }
        return best?.text ?? "◇"
    }

    /// Applies global ordering before pagination and creates only the requested page.
    func orderedCharacters(offset: Int = 0, limit: Int = 256,
                           order: UnicodeSortOrder = .codePoint) -> [UnicodeCharacter] {
        page(in: properties.assignedSpans, offset: offset, limit: limit, order: order)
    }

    /// Characters whose code points fall in `range` but none of `hidden`,
    /// lowest first, or highest first when `descending`.
    func orderedCharacters(in range: ClosedRange<UInt32>, excluding hidden: [ClosedRange<UInt32>] = [],
                           offset: Int = 0, limit: Int = 256, descending: Bool = false) -> [UnicodeCharacter] {
        let spans = properties.assignedSpans.flatMap { span -> [UnicodeAssignedSpan] in
            guard span.start <= range.upperBound && span.end >= range.lowerBound else { return [] }
            var pieces = [max(range.lowerBound, span.start)...min(range.upperBound, span.end)]
            for cut in hidden { pieces = pieces.flatMap { Self.subtracting(cut, from: $0) } }
            return pieces.map { UnicodeAssignedSpan(start: $0.lowerBound, end: $0.upperBound,
                                                    sortKey: span.sortKey, draftAddition: span.draftAddition) }
        }
        return page(in: spans, offset: offset, limit: limit, order: .codePoint, descending: descending)
    }

    /// What is left of `piece` around `cut`.
    private static func subtracting(_ cut: ClosedRange<UInt32>, from piece: ClosedRange<UInt32>) -> [ClosedRange<UInt32>] {
        guard cut.overlaps(piece) else { return [piece] }
        var left: [ClosedRange<UInt32>] = []
        if piece.lowerBound < cut.lowerBound { left.append(piece.lowerBound...(cut.lowerBound - 1)) }
        if piece.upperBound > cut.upperBound { left.append((cut.upperBound + 1)...piece.upperBound) }
        return left
    }

    private func page(in spans: [UnicodeAssignedSpan], offset: Int, limit: Int,
                      order: UnicodeSortOrder, descending: Bool = false) -> [UnicodeCharacter] {
        guard offset >= 0, limit > 0, !Task.isCancelled else { return [] }
        let ordered = spans.sorted { left, right in
            if order != .codePoint && left.sortKey != right.sortKey {
                return order == .newestFirst ? left.sortKey > right.sortKey : left.sortKey < right.sortKey
            }
            return left.start < right.start
        }
        var remainingOffset = offset
        var points: [UInt32] = []
        for span in descending ? ordered.reversed() : ordered {
            if Task.isCancelled { return [] }
            let count = Int(span.end - span.start + 1)
            if remainingOffset >= count { remainingOffset -= count; continue }
            let take = min(count - remainingOffset, limit - points.count)
            if descending {
                let top = span.end - UInt32(remainingOffset)
                points.append(contentsOf: (0..<UInt32(take)).map { top - $0 })
            } else {
                let start = span.start + UInt32(remainingOffset)
                points.append(contentsOf: start..<(start + UInt32(take)))
            }
            remainingOffset = 0
            if points.count == limit { break }
        }
        var result: [UnicodeCharacter] = []
        for (index, cp) in points.enumerated() {
            if index & 255 == 0 && Task.isCancelled { return [] }
            if let character = character(at: cp) { result.append(character) }
        }
        return Task.isCancelled ? [] : result
    }

    /// Supports names, informative descriptions, formal aliases, literal glyphs,
    /// U+1F680 / 0x1F680 / 1F680 and decimal:128640. Bare hexadecimal values
    /// need a numeric digit, so names such as "face" remain text searches.
    func search(_ query: String, limit: Int = 240,
                order: UnicodeSortOrder = .codePoint) -> [UnicodeCharacter] {
        guard limit > 0, !Task.isCancelled, CatalogSearchQueryPolicy.accepts(query) else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orderedCharacters(limit: limit, order: order) }
        if let cp = Self.parseCodePoint(trimmed) {
            return character(at: cp).map { [$0] } ?? []
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("u+") || lower.hasPrefix("0x") || lower.hasPrefix("decimal:") { return [] }
        if trimmed.count == 1 || trimmed.unicodeScalars.contains(where: { $0.value > 0x7F }) && !trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
            var seen = Set<UInt32>()
            return trimmed.unicodeScalars.compactMap { scalar in
                seen.insert(scalar.value).inserted ? character(at: scalar.value) : nil
            }.prefix(limit).map { $0 }
        }
        let normalized = Self.normalized(trimmed)
        let stringTokens = CatalogSearchQueryPolicy.terms(in: normalized)
        let tokens = stringTokens.map { Array($0.utf8) }
        guard !tokens.isEmpty else { return [] }
        return data.withUnsafeBytes { bytes in
            var candidates: [(point: UInt32, key: Int, rank: Int)] = []
            for index in 0..<recordCount {
                if index & 255 == 0 && Task.isCancelled { return [] }
                let record = recordOffset + index * recordSize
                let start = poolOffset + Int(Self.u32(bytes, record + 16))
                let length = Int(Self.u32(bytes, record + 20))
                let contextStart = formatVersion >= 3 ? poolOffset + Int(Self.u32(bytes, record + 36)) : start
                let contextLength = formatVersion >= 3 ? Int(Self.u32(bytes, record + 40)) : 0
                var allMatch = true, allWhole = true
                for token in tokens {
                    if Task.isCancelled { return [] }
                    let primary = Self.match(token, bytes: bytes, start: start, length: length)
                    let context = primary == 2 ? 0 : Self.match(token, bytes: bytes, start: contextStart, length: contextLength)
                    let kind = max(primary, context)
                    if kind == 0 { allMatch = false; break }
                    if kind != 2 { allWhole = false }
                }
                let cp = Self.u32(bytes, record)
                if allMatch, !isLimited || isAssigned(cp) {
                    candidates.append((cp, sortKey(at: cp), allWhole ? 0 : 1))
                }
            }
            // Algorithmic ranges are only expanded when their naming prefix or
            // a hexadecimal suffix could match. Ordinary searches stay compact.
            do {
                for index in 0..<rangeCount {
                    if Task.isCancelled { return [] }
                    let range = rangeOffset + index * Self.rangeSize
                    let prefix = string(offset: Int(Self.u32(bytes, range + 8)),
                                        length: Self.u16(bytes, range + 12), bytes: bytes)
                        .lowercased().replacingOccurrences(of: "-", with: " ")
                    let kind = bytes[range + 15]
                    let start = Self.u32(bytes, range)
                    let end = Self.u32(bytes, range + 4)
                    for block in blocks where block.start <= end && block.end >= start {
                        if Task.isCancelled { return [] }
                        let prefixAndBlock = prefix + " " + Self.normalized(block.name)
                        let possible = stringTokens.allSatisfy { word in
                            !Task.isCancelled && (prefixAndBlock.contains(word) || (kind == 1
                                ? word.count <= 7 && word.allSatisfy { "abcdeghijklmnoprstuwy".contains($0) }
                                : word.allSatisfy { $0.isASCII && $0.isHexDigit }))
                        }
                        guard possible else { continue }
                        let blockStart = max(block.start, start)
                        let blockEnd = min(block.end, end)
                        if stringTokens.allSatisfy({ !Task.isCancelled && prefixAndBlock.contains($0) }) {
                            let whole = stringTokens.allSatisfy {
                                !Task.isCancelled && CatalogSearchQueryPolicy.containsWholeTerm($0, in: prefixAndBlock)
                            }
                            for cp in blockStart...blockEnd where !isLimited || isAssigned(cp) {
                                if cp & 255 == 0 && Task.isCancelled { return [] }
                                candidates.append((cp, sortKey(at: cp), whole ? 0 : 1))
                            }
                        } else {
                            let blockName = Self.normalized(block.name)
                            for cp in blockStart...blockEnd where !isLimited || isAssigned(cp) {
                                if cp & 255 == 0 && Task.isCancelled { return [] }
                                let text = algorithmicName(cp, range: range, bytes: bytes)
                                    .lowercased().replacingOccurrences(of: "-", with: " ") + " " + blockName
                                if stringTokens.allSatisfy({ !Task.isCancelled && text.contains($0) }) {
                                    let whole = stringTokens.allSatisfy {
                                        !Task.isCancelled && CatalogSearchQueryPolicy.containsWholeTerm($0, in: text)
                                    }
                                    candidates.append((cp, sortKey(at: cp), whole ? 0 : 1))
                                }
                            }
                        }
                    }
                }
            }
            // ConScript names and aliases, when Private Use reads as the registry.
            for entry in conscript?.entries ?? [] {
                let text = Self.normalized(([entry.name] + entry.aliases).joined(separator: " "))
                if stringTokens.allSatisfy({ text.contains($0) }) {
                    let whole = stringTokens.allSatisfy { CatalogSearchQueryPolicy.containsWholeTerm($0, in: text) }
                    candidates.append((entry.codePoint, sortKey(at: entry.codePoint), whole ? 0 : 1))
                }
            }
            // Whole-word AND matches precede mid-word matches. Within each tier,
            // sort ALL matches before limiting, including algorithmic names.
            // Candidates are compact numbers, not hundreds of thousands of objects.
            let sorted = candidates.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if order != .codePoint && $0.key != $1.key {
                    return order == .newestFirst ? $0.key > $1.key : $0.key < $1.key
                }
                return $0.point < $1.point
            }
            guard !Task.isCancelled else { return [] }
            // A ConScript character can match both its block and its name.
            var seen = Set<UInt32>()
            return sorted.filter { seen.insert($0.point).inserted }.prefix(limit).compactMap { character(at: $0.point) }
        }
    }

    private func block(containing codePoint: UInt32) -> UnicodeBlock? {
        var low = 0
        var high = blocks.count
        while low < high {
            let mid = (low + high) / 2
            if blocks[mid].end < codePoint { low = mid + 1 } else { high = mid }
        }
        return low < blocks.count && blocks[low].start <= codePoint ? blocks[low] : nil
    }

    private func lowerBound(_ cp: UInt32, bytes: UnsafeRawBufferPointer) -> Int {
        var low = 0
        var high = recordCount
        while low < high {
            let mid = (low + high) / 2
            if Self.u32(bytes, recordOffset + mid * recordSize) < cp { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func recordIndex(_ cp: UInt32, bytes: UnsafeRawBufferPointer) -> Int? {
        let index = lowerBound(cp, bytes: bytes)
        return index < recordCount && Self.u32(bytes, recordOffset + index * recordSize) == cp ? index : nil
    }

    private func character(record index: Int, blockName: String, bytes: UnsafeRawBufferPointer) -> UnicodeCharacter {
        let record = recordOffset + index * recordSize
        let category = Self.categories[Int(bytes[record + 24])]
        let storedDetail = string(offset: Int(Self.u32(bytes, record + 12)), length: Self.u16(bytes, record + 10), bytes: bytes)
        // Version 3 keeps structured details in the existing mapped string pool.
        // Only the requested character/page is decoded; no global alias dictionary.
        let metadata = formatVersion >= 3 ? Self.detailData(storedDetail) : nil
        let contextText = formatVersion >= 3 ? string(offset: Int(Self.u32(bytes, record + 28)), length: Int(Self.u32(bytes, record + 32)), bytes: bytes) : ""
        let context = Self.detailData(contextText)
        let prose = ((metadata?.annotations ?? []) + (context?.sectionAnnotations ?? [])).joined(separator: "\n")
        let detail = formatVersion >= 3 ? prose : storedDetail
        return UnicodeCharacter(codePoint: Self.u32(bytes, record),
                                name: string(offset: Int(Self.u32(bytes, record + 4)), length: Self.u16(bytes, record + 8), bytes: bytes),
                                detail: detail.isEmpty ? Self.categoryDescriptions[category] ?? category : detail,
                                blockName: blockName, category: category, isInvisible: bytes[record + 25] & 1 != 0,
                                age: age(at: Self.u32(bytes, record)), versionSortKey: sortKey(at: Self.u32(bytes, record)),
                                combiningClass: Int(bytes[record + 26]),
                                bidirectionalClass: Self.bidiClasses[Int(bytes[record + 27])],
                                script: script(at: Self.u32(bytes, record)),
                                decomposition: decomposition(at: Self.u32(bytes, record)),
                                nameAliases: metadata?.aliases ?? [], annotations: metadata?.annotations ?? [],
                                namesListSection: context?.section, sectionAnnotations: context?.sectionAnnotations ?? [],
                                crossReferences: metadata?.references ?? [], unicode1Name: metadata?.unicode1Name,
                                numericValue: metadata?.numericValue, numericType: metadata?.numericType,
                                simpleUppercase: metadata?.simpleUppercase, simpleLowercase: metadata?.simpleLowercase,
                                simpleTitlecase: metadata?.simpleTitlecase,
                                hasPresentationForms: hasPresentationForms(Self.u32(bytes, record)))
    }

    private func age(at cp: UInt32) -> String? { property(at: cp, in: properties.ages) }
    private func hasPresentationForms(_ cp: UInt32) -> Bool {
        guard let bases = properties.presentationSequences else { return false }
        var low = 0, high = bases.count
        while low < high {
            let mid = (low + high) / 2
            if bases[mid] < cp { low = mid + 1 } else { high = mid }
        }
        return low < bases.count && bases[low] == cp
    }
    private func script(at cp: UInt32) -> String? {
        properties.unicodeVersion.isEmpty ? nil : property(at: cp, in: properties.scripts) ?? "Unknown"
    }
    private func property(at cp: UInt32, in ranges: [UnicodePropertyRange]) -> String? {
        var low = 0, high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if ranges[mid].end < cp { low = mid + 1 } else { high = mid }
        }
        return low < ranges.count && ranges[low].start <= cp ? ranges[low].value : nil
    }
    private func sortKey(at cp: UInt32) -> Int {
        var low = 0, high = properties.assignedSpans.count
        while low < high {
            let mid = (low + high) / 2
            if properties.assignedSpans[mid].end < cp { low = mid + 1 } else { high = mid }
        }
        return low < properties.assignedSpans.count && properties.assignedSpans[low].start <= cp
            ? properties.assignedSpans[low].sortKey : age(at: cp).map(unicodeVersionKey) ?? 0
    }
    private func decomposition(at cp: UInt32) -> String? {
        if (0xAC00...0xD7A3).contains(cp) {
            let index = cp - 0xAC00
            var points = [UInt32(0x1100) + index / 588, UInt32(0x1161) + index % 588 / 28]
            if index % 28 != 0 { points.append(0x11A7 + index % 28) }
            return points.map { String(format: "%04X", $0) }.joined(separator: " ")
        }
        var low = 0, high = properties.decompositions.count
        while low < high {
            let mid = (low + high) / 2
            if properties.decompositions[mid].codePoint < cp { low = mid + 1 } else { high = mid }
        }
        return low < properties.decompositions.count && properties.decompositions[low].codePoint == cp
            ? properties.decompositions[low].value : nil
    }

    private func algorithmicRange(_ cp: UInt32, bytes: UnsafeRawBufferPointer) -> Int? {
        var low = 0
        var high = rangeCount
        while low < high {
            let mid = (low + high) / 2
            if Self.u32(bytes, rangeOffset + mid * Self.rangeSize + 4) < cp { low = mid + 1 } else { high = mid }
        }
        let range = rangeOffset + low * Self.rangeSize
        return low < rangeCount && Self.u32(bytes, range) <= cp ? range : nil
    }

    private func algorithmicName(_ cp: UInt32, range: Int, bytes: UnsafeRawBufferPointer) -> String {
        let prefix = string(offset: Int(Self.u32(bytes, range + 8)), length: Self.u16(bytes, range + 12), bytes: bytes)
        if bytes[range + 15] == 1 {
            // Unicode 17 §3.12, Hangul syllable name generation.
            let leading = ["G", "GG", "N", "D", "DD", "R", "M", "B", "BB", "S", "SS", "", "J", "JJ", "C", "K", "T", "P", "H"]
            let vowel = ["A", "AE", "YA", "YAE", "EO", "E", "YEO", "YE", "O", "WA", "WAE", "OE", "YO", "U", "WEO", "WE", "WI", "YU", "EU", "YI", "I"]
            let trailing = ["", "G", "GG", "GS", "N", "NJ", "NH", "D", "L", "LG", "LM", "LB", "LS", "LT", "LP", "LH", "M", "B", "BS", "S", "SS", "NG", "J", "C", "K", "T", "P", "H"]
            let index = Int(cp - 0xAC00)
            return prefix + leading[index / 588] + vowel[(index % 588) / 28] + trailing[index % 28]
        }
        return prefix + String(format: "%04X", cp)
    }

    private func string(offset: Int, length: Int, bytes: UnsafeRawBufferPointer) -> String {
        String(decoding: bytes[(poolOffset + offset)..<(poolOffset + offset + length)], as: UTF8.self)
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func parseCodePoint(_ value: String) -> UInt32? {
        let lower = value.lowercased()
        let digits: Substring
        let radix: Int
        if lower.hasPrefix("u+") { digits = lower.dropFirst(2); radix = 16 }
        else if lower.hasPrefix("0x") { digits = lower.dropFirst(2); radix = 16 }
        else if lower.hasPrefix("decimal:") { digits = lower.dropFirst(8); radix = 10 }
        else if (4...6).contains(lower.count) && lower.allSatisfy({ $0.isASCII && $0.isHexDigit })
                    && lower.contains(where: { $0.isASCII && $0.isNumber }) {
            digits = lower[lower.startIndex..<lower.endIndex]; radix = 16
        } else { return nil }
        let text = digits.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && (radix == 16 ? $0.isHexDigit : $0.isNumber) }) else { return nil }
        return UInt32(text, radix: radix)
    }

    private static func isNoncharacter(_ cp: UInt32) -> Bool {
        (0xFDD0...0xFDEF).contains(cp) || cp & 0xFFFF >= 0xFFFE
    }

    /// 0 = absent, 1 = substring only, 2 = a complete normalized Unicode word.
    /// Scan the existing mapped index; no per-query character/index rebuild.
    private static func match(_ token: [UInt8], bytes: UnsafeRawBufferPointer, start: Int, length: Int) -> Int {
        guard !token.isEmpty, token.count <= length else { return 0 }
        var found = false
        for candidate in start...(start + length - token.count) where bytes[candidate] == token[0] {
            if Task.isCancelled { return 0 }
            var matches = true
            for index in 1..<token.count where bytes[candidate + index] != token[index] { matches = false; break }
            if matches {
                found = true
                if (candidate == start || bytes[candidate - 1] == 0x20)
                    && (candidate + token.count == start + length || bytes[candidate + token.count] == 0x20) { return 2 }
            }
        }
        return found ? 1 : 0
    }

    private static func uint32(_ data: Data, _ offset: Int) -> Int {
        data.withUnsafeBytes { Int(u32($0, offset)) }
    }
    private static func u32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    private static func u16(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    private static func valid(_ data: Data) -> Bool {
        guard data.count >= 48, String(decoding: data.prefix(8), as: UTF8.self) == "UBOARD17" else { return false }
        return data.withUnsafeBytes { bytes in
            let records = Int(u32(bytes, 8)), recordStart = Int(u32(bytes, 12))
            let ranges = Int(u32(bytes, 16)), rangeStart = Int(u32(bytes, 20))
            let pool = Int(u32(bytes, 24)), poolLength = Int(u32(bytes, 28))
            let format = u32(bytes, 44)
            let recordSize = format >= 3 ? 44 : 28
            guard (2...3).contains(u32(bytes, 44)), recordStart == 48,
                  records > 0 || ranges > 0,
                  recordStart + records * recordSize == rangeStart,
                  rangeStart + ranges * rangeSize == pool,
                  pool + poolLength == bytes.count,
                  Int(u32(bytes, 32)) + Int(u32(bytes, 36)) <= poolLength,
                  String(data: data[pool..<(pool + poolLength)], encoding: .utf8) != nil else { return false }
            let versionStart = pool + Int(u32(bytes, 32))
            let version = String(decoding: bytes[versionStart..<(versionStart + Int(u32(bytes, 36)))], as: UTF8.self)
            guard unicodeVersionKey(version) > 0 else { return false }
            var previousPoint: UInt32?
            for index in 0..<records {
                let record = recordStart + index * recordSize
                let cp = u32(bytes, record)
                guard Unicode.Scalar(cp) != nil, previousPoint.map({ $0 < cp }) ?? true,
                      Int(bytes[record + 24]) < categories.count,
                      Int(bytes[record + 27]) < bidiClasses.count,
                      bytes[record + 25] <= 1, u16(bytes, record + 8) > 0,
                      Int(u32(bytes, record + 4)) + u16(bytes, record + 8) <= poolLength,
                      Int(u32(bytes, record + 12)) + u16(bytes, record + 10) <= poolLength,
                      Int(u32(bytes, record + 16)) + Int(u32(bytes, record + 20)) <= poolLength else { return false }
                if format >= 3 {
                    guard Int(u32(bytes, record + 28)) + Int(u32(bytes, record + 32)) <= poolLength,
                          Int(u32(bytes, record + 36)) + Int(u32(bytes, record + 40)) <= poolLength else { return false }
                }
                previousPoint = cp
            }
            var previousEnd: UInt32?
            var recordIndex = 0
            for index in 0..<ranges {
                let range = rangeStart + index * rangeSize
                let start = u32(bytes, range), end = u32(bytes, range + 4)
                guard start <= end, end <= 0x10FFFF,
                      !(start <= 0xDFFF && end >= 0xD800), previousEnd.map({ $0 < start }) ?? true,
                      Int(bytes[range + 14]) < categories.count, bytes[range + 15] <= 2,
                      u16(bytes, range + 12) > 0,
                      Int(u32(bytes, range + 8)) + u16(bytes, range + 12) <= poolLength else { return false }
                if bytes[range + 15] == 1 && !(start >= 0xAC00 && end <= 0xD7A3) { return false }
                while recordIndex < records && u32(bytes, recordStart + recordIndex * recordSize) < start { recordIndex += 1 }
                if recordIndex < records && u32(bytes, recordStart + recordIndex * recordSize) <= end { return false }
                previousEnd = end
            }
            return true
        }
    }

    private static func validBlocks(_ blocks: [UnicodeBlock]) -> Bool {
        !blocks.isEmpty && blocks.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.start <= $0.end && $0.end <= 0x10FFFF }
            && zip(blocks, blocks.dropFirst()).allSatisfy { $0.end < $1.start }
    }

    private static func validCoverage(_ properties: UnicodePropertyData, data: Data) -> Bool {
        // Compare compact interval unions, not a materialized object per scalar.
        func append(_ start: UInt32, _ end: UInt32, to ranges: inout [ClosedRange<UInt32>]) {
            if let last = ranges.last, last.upperBound + 1 == start {
                ranges[ranges.count - 1] = last.lowerBound...end
            } else { ranges.append(start...end) }
        }
        let expected: [ClosedRange<UInt32>] = data.withUnsafeBytes { bytes in
            let records = Int(u32(bytes, 8)), recordStart = Int(u32(bytes, 12))
            let count = Int(u32(bytes, 16)), rangeStart = Int(u32(bytes, 20))
            let size = u32(bytes, 44) >= 3 ? 44 : 28
            var record = 0, range = 0, result: [ClosedRange<UInt32>] = []
            while record < records || range < count {
                let cp = record < records ? u32(bytes, recordStart + record * size) : UInt32.max
                let start = range < count ? u32(bytes, rangeStart + range * rangeSize) : UInt32.max
                if cp < start { append(cp, cp, to: &result); record += 1 }
                else { append(start, u32(bytes, rangeStart + range * rangeSize + 4), to: &result); range += 1 }
            }
            return result
        }
        var actual: [ClosedRange<UInt32>] = []
        for span in properties.assignedSpans { append(span.start, span.end, to: &actual) }
        return actual == expected
    }

    private static func detailData(_ text: String) -> UnicodeDetailData? {
        guard !text.isEmpty, let detail = try? JSONDecoder().decode(UnicodeDetailData.self, from: Data(text.utf8)), detail.isValid else { return nil }
        return detail
    }
}

struct UnicodeSourceIdentity: Decodable {
    let versionLabel: String
    let isDraft: Bool
    let edition: String?
    /// The final editions shown by limiting the draft, such as "latest": "18.0.0".
    var editions: [String: String]? = nil
}

private struct UnicodeDetailData: Decodable {
    let aliases: [UnicodeNameAlias]?
    let annotations: [String]?
    let section: String?
    let sectionAnnotations: [String]?
    let references: [UnicodeCrossReference]?
    let unicode1Name: String?
    let numericValue: String?
    let numericType: String?
    let simpleUppercase: UInt32?
    let simpleLowercase: UInt32?
    let simpleTitlecase: UInt32?
    var isValid: Bool {
        (aliases ?? []).allSatisfy { !$0.name.isEmpty && (["informal", "namesListFormal", "correction", "control", "alternate", "figment", "abbreviation"].contains($0.kind)) }
            && (references ?? []).allSatisfy { Unicode.Scalar($0.codePoint) != nil && !$0.name.isEmpty }
            && [simpleUppercase, simpleLowercase, simpleTitlecase].compactMap { $0 }.allSatisfy { Unicode.Scalar($0) != nil }
    }
}

private struct UnicodePropertyRange: Decodable {
    let start: UInt32
    let end: UInt32
    let value: String
}
private struct UnicodeAssignedSpan: Decodable {
    let start: UInt32
    let end: UInt32
    let sortKey: Int
    let draftAddition: Bool
}
private struct UnicodeDecomposition: Decodable {
    let codePoint: UInt32
    let value: String
}
/// One row of a code chart: its first code point and a bit per assigned column.
struct UnicodeChartRow: Hashable, Sendable {
    let start: UInt32
    /// One bit per column, up to 32 columns.
    let assigned: UInt32
    func isAssigned(column: Int) -> Bool { (0..<32).contains(column) && assigned & (1 << UInt32(column)) != 0 }
}

private struct UnicodePropertyData: Decodable {
    let unicodeVersion: String
    let ages: [UnicodePropertyRange]
    let scripts: [UnicodePropertyRange]
    let assignedSpans: [UnicodeAssignedSpan]
    let decompositions: [UnicodeDecomposition]
    /// Characters with both a text (VS15) and an emoji (VS16) presentation sequence.
    var presentationSequences: [UInt32]? = nil
    static let empty = UnicodePropertyData(unicodeVersion: "", ages: [], scripts: [], assignedSpans: [], decompositions: [])
    var isValid: Bool {
        func validRanges(_ ranges: [UnicodePropertyRange]) -> Bool {
            ranges.allSatisfy { $0.start <= $0.end && $0.end <= 0x10FFFF }
                && zip(ranges, ranges.dropFirst()).allSatisfy { $0.end < $1.start }
        }
        let editionKey = unicodeVersionKey(unicodeVersion)
        return editionKey > 0 && validRanges(ages) && validRanges(scripts)
            && ages.allSatisfy { unicodeVersionKey($0.value) > 0 && unicodeVersionKey($0.value) <= editionKey }
            && scripts.allSatisfy { !$0.value.isEmpty }
            && assignedSpans.allSatisfy {
                $0.start <= $0.end && $0.end <= 0x10FFFF && $0.sortKey > 0 && $0.sortKey <= editionKey
                    && (!$0.draftAddition || unicodeVersion.hasSuffix(" draft"))
                    && !($0.start <= 0xDFFF && $0.end >= 0xD800)
            }
            && zip(assignedSpans, assignedSpans.dropFirst()).allSatisfy { $0.end < $1.start }
            && decompositions.allSatisfy { Unicode.Scalar($0.codePoint) != nil }
            && zip(decompositions, decompositions.dropFirst()).allSatisfy { $0.codePoint < $1.codePoint }
            && (presentationSequences ?? []).allSatisfy { Unicode.Scalar($0) != nil }
            && zip(presentationSequences ?? [], (presentationSequences ?? []).dropFirst()).allSatisfy { $0 < $1 }
    }
}
