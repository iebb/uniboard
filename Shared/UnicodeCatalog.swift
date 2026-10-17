import Foundation

enum UnicodeEdition: String, CaseIterable, Identifiable, Sendable {
    case latest, draft
    var id: String { rawValue }
    var title: String {
        let number = catalog.version.split(separator: ".").first.map(String.init) ?? catalog.version
        return "Unicode \(number) · \(self == .latest ? "latest" : "draft")"
    }
    var catalog: UnicodeCatalog { self == .latest ? .latest : .shared }
    var emojiCatalog: EmojiCatalog { self == .latest ? .latest : .shared }
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
    let components = version.split(separator: ".")
    guard let major = components.first.flatMap({ Int($0) }) else { return 0 }
    return major * 100 + (components.count > 1 ? Int(components[1]) ?? 0 : 0)
}

/// Formal kinds come from NameAliases.txt. Informative chart aliases never
/// acquire correction status merely because a character's name is misleading.
struct UnicodeNameAlias: Identifiable, Hashable, Sendable, Decodable {
    let name: String
    let kind: String
    var id: String { kind + ":" + name }
    var isFormal: Bool { kind != "informal" }
    var source: String { kind == "informal" || kind == "namesListFormal" ? "NamesList.txt" : "NameAliases.txt" }
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
    private let invisible: Bool

    var id: UInt32 { codePoint }
    var text: String { Unicode.Scalar(codePoint).map { String($0) } ?? "" }
    var codePointLabel: String { String(format: "U+%04X", codePoint) }
    var isInvisible: Bool { invisible }
    var categoryName: String { UnicodeCatalog.categoryDescriptions[category] ?? category }
    var displayText: String {
        switch codePoint {
        case 0x20: return "␣"
        case 0x09: return "⇥"
        case 0x0A, 0x0D, 0x2028, 0x2029: return "↵"
        default:
            if invisible { return "◌" }
            if category.hasPrefix("M") { return "◌" + text }
            if category == "Cn" { return "◇" }
            return text
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
         simpleUppercase: UInt32? = nil, simpleLowercase: UInt32? = nil, simpleTitlecase: UInt32? = nil) {
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
        if start >= 0xD800 && end <= 0xDFFF { return "UTF-16 surrogate code units" }
        return "\(Int(end - start + 1).formatted()) code points · \(start < 0x10000 ? "Basic plane" : "Plane \(start >> 16)")"
    }
    var symbol: String {
        let examples: [UInt32: UInt32] = [
            0x0000: 0x0041, 0x0080: 0x00C6, 0x0300: 0x0301, 0x0370: 0x03A9,
            0x0400: 0x0416, 0x0590: 0x05D0, 0x0600: 0x0639, 0x0900: 0x0905,
            0x2000: 0x2022, 0x20A0: 0x20AC, 0x2100: 0x2126, 0x2190: 0x2192,
            0x2200: 0x2211, 0x2300: 0x2318, 0x2500: 0x253C, 0x2580: 0x2588,
            0x2600: 0x2605, 0x2700: 0x2708, 0x2800: 0x283F, 0x3000: 0x3005,
            0x3040: 0x3042, 0x30A0: 0x30A2, 0x4E00: 0x4E2D, 0xAC00: 0xD55C,
            0x1F300: 0x1F308, 0x1F600: 0x1F603, 0x1F680: 0x1F680,
            0x1F900: 0x1F981, 0x1FA70: 0x1FA77
        ]
        if start >= 0xD800 && end <= 0xDFFF || name.contains("Private Use") { return "◇" }
        let scalar = Unicode.Scalar(examples[start] ?? start)
        guard let scalar else { return "◇" }
        return name.contains("Combining") ? "◌" + String(scalar) : String(scalar)
    }
}

/// Immutable, memory-mapped Unicode data shared by the containing app and keyboard.
/// Browsing materializes only a page, rather than hundreds of thousands of objects.
final class UnicodeCatalog: @unchecked Sendable {
    static let shared = UnicodeCatalog()
    static let latest = UnicodeCatalog(edition: .latest)

    let edition: UnicodeEdition
    let blocks: [UnicodeBlock]
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

    /// Pass a resource directory or UnicodeCatalog.ucd URL for tests/custom bundles.
    init(edition: UnicodeEdition = .draft, resourceURL: URL? = nil) {
        self.edition = edition
        let catalogURL: URL?
        let blocksURL: URL?
        let propertiesURL: URL?
        let suffix = edition == .latest ? "-latest" : ""
        if let resourceURL {
            let directory = resourceURL.pathExtension == "ucd" ? resourceURL.deletingLastPathComponent() : resourceURL
            catalogURL = resourceURL.pathExtension == "ucd" ? resourceURL : directory.appendingPathComponent("UnicodeCatalog\(suffix).ucd")
            blocksURL = directory.appendingPathComponent("Blocks\(suffix).json")
            propertiesURL = directory.appendingPathComponent("UnicodeProperties\(suffix).json")
        } else {
            #if SWIFT_PACKAGE
            let bundles = [Bundle.module, Bundle.main, Bundle(for: UnicodeCatalog.self)]
            #else
            let bundles = [Bundle.main, Bundle(for: UnicodeCatalog.self)]
            #endif
            catalogURL = bundles.lazy.compactMap { $0.url(forResource: "UnicodeCatalog\(suffix)", withExtension: "ucd") }.first
            blocksURL = bundles.lazy.compactMap { $0.url(forResource: "Blocks\(suffix)", withExtension: "json") }.first
            propertiesURL = bundles.lazy.compactMap { $0.url(forResource: "UnicodeProperties\(suffix)", withExtension: "json") }.first
        }
        blocks = blocksURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([UnicodeBlock].self, from: $0) } ?? []
        let loaded = catalogURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        let decodedProperties = propertiesURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(UnicodePropertyData.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
        properties = decodedProperties ?? .empty
        if let loaded, Self.valid(loaded) {
            data = loaded
            recordCount = Self.uint32(loaded, 8)
            recordOffset = Self.uint32(loaded, 12)
            rangeCount = Self.uint32(loaded, 16)
            rangeOffset = Self.uint32(loaded, 20)
            poolOffset = Self.uint32(loaded, 24)
            formatVersion = Self.uint32(loaded, 44)
            recordSize = formatVersion >= 3 ? 44 : 28
            let start = poolOffset + Self.uint32(loaded, 32)
            version = String(decoding: loaded[start..<(start + Self.uint32(loaded, 36))], as: UTF8.self)
            resourceError = blocks.isEmpty ? "Unicode block resources could not be loaded."
                : decodedProperties?.unicodeVersion != version ? "Unicode property resources could not be loaded for this edition." : nil
        } else {
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

    var featured: [UnicodeCharacter] {
        let points: [UInt32] = [0x2605, 0x2665, 0x2192, 0x2713, 0x221E, 0x03C0, 0x00B0, 0x00D7,
         0x00A9, 0x2122, 0x20AC, 0x00A5, 0x2014, 0x2022, 0x00BD, 0x2318,
         0x1F680, 0x1F308, 0x1F338, 0x1F43E, 0x1F30D, 0x1F4A1, 0x1F9ED]
        return points.reduce(into: [UnicodeCharacter]()) { result, cp in
                if !result.contains(where: { $0.codePoint == cp }), let character = character(at: cp) {
                    result.append(character)
                }
            }
    }

    /// Every valid scalar can be inspected, including reserved/noncharacters.
    /// Surrogates and values above U+10FFFF are rejected because they cannot be text.
    func character(at codePoint: UInt32) -> UnicodeCharacter? {
        guard Unicode.Scalar(codePoint) != nil else { return nil }
        let block = block(containing: codePoint)?.name ?? "No Block"
        return data.withUnsafeBytes { bytes in
            if let index = recordIndex(codePoint, bytes: bytes) {
                return character(record: index, blockName: block, bytes: bytes)
            }
            if let range = algorithmicRange(codePoint, bytes: bytes) {
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
                                    age: age(at: codePoint), script: script(at: codePoint))
        }
    }

    /// Pagination counts assigned Unicode scalars, not unused code-point slots.
    /// This keeps sparse blocks useful and excludes UTF-16 surrogates.
    func characters(in block: UnicodeBlock, offset: Int = 0, limit: Int = 256,
                    order: UnicodeSortOrder = .newestFirst) -> [UnicodeCharacter] {
        guard offset >= 0, limit > 0, block.start <= block.end, block.end <= 0x10FFFF else { return [] }
        let spans = properties.assignedSpans.compactMap { span -> UnicodeAssignedSpan? in
            guard span.start <= block.end && span.end >= block.start else { return nil }
            return UnicodeAssignedSpan(start: max(block.start, span.start), end: min(block.end, span.end),
                                       sortKey: span.sortKey, draftAddition: span.draftAddition)
        }
        return page(in: spans, offset: offset, limit: limit, order: order)
    }

    /// Applies global ordering before pagination and creates only the requested page.
    func orderedCharacters(offset: Int = 0, limit: Int = 256,
                           order: UnicodeSortOrder = .newestFirst) -> [UnicodeCharacter] {
        page(in: properties.assignedSpans, offset: offset, limit: limit, order: order)
    }

    func newestCharacters(offset: Int = 0, limit: Int = 256) -> [UnicodeCharacter] {
        orderedCharacters(offset: offset, limit: limit, order: .newestFirst)
    }

    private func page(in spans: [UnicodeAssignedSpan], offset: Int, limit: Int,
                      order: UnicodeSortOrder) -> [UnicodeCharacter] {
        guard offset >= 0, limit > 0 else { return [] }
        let ordered = spans.sorted { left, right in
            if order != .codePoint && left.sortKey != right.sortKey {
                return order == .newestFirst ? left.sortKey > right.sortKey : left.sortKey < right.sortKey
            }
            return left.start < right.start
        }
        var remainingOffset = offset
        var points: [UInt32] = []
        for span in ordered {
            let count = Int(span.end - span.start + 1)
            if remainingOffset >= count { remainingOffset -= count; continue }
            let start = span.start + UInt32(remainingOffset)
            remainingOffset = 0
            let take = min(Int(span.end - start + 1), limit - points.count)
            points.append(contentsOf: start..<(start + UInt32(take)))
            if points.count == limit { break }
        }
        return points.compactMap { character(at: $0) }
    }

    /// Supports names, informative descriptions, formal aliases, literal glyphs,
    /// U+1F680 / 0x1F680 / 1F680 and decimal:128640. Bare hexadecimal values
    /// need a numeric digit, so names such as "face" remain text searches.
    func search(_ query: String, limit: Int = 240,
                order: UnicodeSortOrder = .newestFirst) -> [UnicodeCharacter] {
        guard limit > 0 else { return [] }
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
        let tokens = normalized.split(separator: " ").map { Array($0.utf8) }
        guard !tokens.isEmpty else { return [] }
        let exactBlock = blocks.first { Self.normalized($0.name) == normalized }
        let stringTokens = tokens.map { String(decoding: $0, as: UTF8.self) }
        return data.withUnsafeBytes { bytes in
            var points: [UInt32] = []
            for index in 0..<recordCount {
                let record = recordOffset + index * recordSize
                let start = poolOffset + Int(Self.u32(bytes, record + 16))
                let length = Int(Self.u32(bytes, record + 20))
                let contextStart = formatVersion >= 3 ? poolOffset + Int(Self.u32(bytes, record + 36)) : start
                let contextLength = formatVersion >= 3 ? Int(Self.u32(bytes, record + 40)) : 0
                if tokens.allSatisfy({ Self.contains($0, bytes: bytes, start: start, length: length)
                    || Self.contains($0, bytes: bytes, start: contextStart, length: contextLength) }) {
                    let cp = Self.u32(bytes, record)
                    points.append(cp)
                }
            }
            // Algorithmic ranges are only expanded when their naming prefix or
            // a hexadecimal suffix could match. Ordinary searches stay compact.
            do {
                for index in 0..<rangeCount {
                    let range = rangeOffset + index * Self.rangeSize
                    let prefix = string(offset: Int(Self.u32(bytes, range + 8)),
                                        length: Self.u16(bytes, range + 12), bytes: bytes)
                        .lowercased().replacingOccurrences(of: "-", with: " ")
                    let kind = bytes[range + 15]
                    let start = Self.u32(bytes, range)
                    let end = Self.u32(bytes, range + 4)
                    for block in blocks where block.start <= end && block.end >= start {
                        let prefixAndBlock = prefix + " " + Self.normalized(block.name)
                        let possible = stringTokens.allSatisfy { word in
                            prefixAndBlock.contains(word) || (kind == 1
                                ? word.count <= 7 && word.allSatisfy { "abcdeghijklmnoprstuwy".contains($0) }
                                : word.allSatisfy { $0.isASCII && $0.isHexDigit })
                        }
                        guard possible else { continue }
                        let blockStart = max(block.start, start)
                        let blockEnd = min(block.end, end)
                        if stringTokens.allSatisfy({ prefixAndBlock.contains($0) }) {
                            for cp in blockStart...blockEnd {
                                points.append(cp)
                            }
                        } else {
                            let blockName = Self.normalized(block.name)
                            for cp in blockStart...blockEnd {
                                let text = algorithmicName(cp, range: range, bytes: bytes)
                                    .lowercased().replacingOccurrences(of: "-", with: " ") + " " + blockName
                                if stringTokens.allSatisfy({ text.contains($0) }) {
                                    points.append(cp)
                                }
                            }
                        }
                    }
                }
            }
            // Rank exact meanings naturally, then sort ALL matches before limiting.
            // Candidates are compact numbers, not hundreds of thousands of objects.
            let candidates = points.map { cp -> (point: UInt32, key: Int, rank: Int) in
                let block = block(containing: cp)
                let name: String
                if let index = recordIndex(cp, bytes: bytes) {
                    let record = recordOffset + index * recordSize
                    name = string(offset: Int(Self.u32(bytes, record + 4)), length: Self.u16(bytes, record + 8), bytes: bytes)
                } else if let range = algorithmicRange(cp, bytes: bytes) {
                    name = algorithmicName(cp, range: range, bytes: bytes)
                } else { name = "" }
                let rank = Self.normalized(name) == normalized ? 0 : block?.name == exactBlock?.name && exactBlock != nil ? 1 : 2
                return (cp, sortKey(at: cp), rank)
            }
            return candidates.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if order != .codePoint && $0.key != $1.key {
                    return order == .newestFirst ? $0.key > $1.key : $0.key < $1.key
                }
                return $0.point < $1.point
            }.prefix(limit).compactMap { character(at: $0.point) }
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
        let metadata = formatVersion >= 3 && !storedDetail.isEmpty
            ? try? JSONDecoder().decode(UnicodeDetailData.self, from: Data(storedDetail.utf8)) : nil
        let contextText = formatVersion >= 3 ? string(offset: Int(Self.u32(bytes, record + 28)), length: Int(Self.u32(bytes, record + 32)), bytes: bytes) : ""
        let context = !contextText.isEmpty ? try? JSONDecoder().decode(UnicodeDetailData.self, from: Data(contextText.utf8)) : nil
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
                                simpleTitlecase: metadata?.simpleTitlecase)
    }

    private func age(at cp: UInt32) -> String? { property(at: cp, in: properties.ages) }
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
            digits = lower[...]; radix = 16
        } else { return nil }
        return UInt32(digits.trimmingCharacters(in: .whitespaces), radix: radix)
    }

    private static func isNoncharacter(_ cp: UInt32) -> Bool {
        (0xFDD0...0xFDEF).contains(cp) || cp & 0xFFFF >= 0xFFFE
    }

    private static func contains(_ token: [UInt8], bytes: UnsafeRawBufferPointer, start: Int, length: Int) -> Bool {
        guard token.count <= length else { return false }
        for candidate in start...(start + length - token.count) where bytes[candidate] == token[0] {
            var matches = true
            for index in 1..<token.count where bytes[candidate + index] != token[index] { matches = false; break }
            if matches { return true }
        }
        return false
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
                  recordStart + records * recordSize == rangeStart,
                  rangeStart + ranges * rangeSize == pool,
                  pool + poolLength == bytes.count,
                  Int(u32(bytes, 32)) + Int(u32(bytes, 36)) <= poolLength else { return false }
            for index in 0..<records {
                let record = recordStart + index * recordSize
                guard Int(bytes[record + 24]) < categories.count,
                      Int(bytes[record + 27]) < bidiClasses.count,
                      Int(u32(bytes, record + 4)) + u16(bytes, record + 8) <= poolLength,
                      Int(u32(bytes, record + 12)) + u16(bytes, record + 10) <= poolLength,
                      Int(u32(bytes, record + 16)) + Int(u32(bytes, record + 20)) <= poolLength else { return false }
                if format >= 3 {
                    guard Int(u32(bytes, record + 28)) + Int(u32(bytes, record + 32)) <= poolLength,
                          Int(u32(bytes, record + 36)) + Int(u32(bytes, record + 40)) <= poolLength else { return false }
                }
            }
            for index in 0..<ranges {
                let range = rangeStart + index * rangeSize
                guard u32(bytes, range) <= u32(bytes, range + 4), u32(bytes, range + 4) <= 0x10FFFF,
                      Int(bytes[range + 14]) < categories.count, bytes[range + 15] <= 2,
                      Int(u32(bytes, range + 8)) + u16(bytes, range + 12) <= poolLength else { return false }
            }
            return true
        }
    }
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
private struct UnicodePropertyData: Decodable {
    let unicodeVersion: String
    let ages: [UnicodePropertyRange]
    let scripts: [UnicodePropertyRange]
    let assignedSpans: [UnicodeAssignedSpan]
    let decompositions: [UnicodeDecomposition]
    static let empty = UnicodePropertyData(unicodeVersion: "", ages: [], scripts: [], assignedSpans: [], decompositions: [])
    var isValid: Bool {
        func validRanges(_ ranges: [UnicodePropertyRange]) -> Bool {
            ranges.allSatisfy { $0.start <= $0.end && $0.end <= 0x10FFFF }
                && zip(ranges, ranges.dropFirst()).allSatisfy { $0.end < $1.start }
        }
        return !unicodeVersion.isEmpty && validRanges(ages) && validRanges(scripts)
            && assignedSpans.allSatisfy {
                $0.start <= $0.end && $0.end <= 0x10FFFF && $0.sortKey >= 0
                    && !($0.start <= 0xDFFF && $0.end >= 0xD800)
            }
            && zip(assignedSpans, assignedSpans.dropFirst()).allSatisfy { $0.end < $1.start }
            && decompositions.allSatisfy { Unicode.Scalar($0.codePoint) != nil }
            && zip(decompositions, decompositions.dropFirst()).allSatisfy { $0.codePoint < $1.codePoint }
    }
}
