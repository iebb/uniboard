import Foundation

// The Google font page's styles grid (design/styles-grid/design.md), kept
// apart from SwiftUI so it can be tested: the copy, sorting catalog styles
// into (set, weight, italic) cells (§1), the Width / Variant menu (§2), which
// cells each file covers (§4) and the derived style names (§6). The catalog
// has no weight or italic fields and some names are wrong, so everything here
// is derived from the style name, PostScript name and instance coordinates.
// Nothing here loads a font.

/// The grid's copy (§10, final): each string defined once here.
enum StyleGridCopy {
    static let width = "Width"
    static let variant = "Variant"
    static let normal = "Normal"
    static let italic = "Italic"
    static let noItalics = "No italic styles in this family."
    static let noStyles = "No styles available."
    static let downloadStyle = "Download Style"
    static let normalStylesFile = "Normal styles file"
    static let italicStylesFile = "Italic styles file"
    static let sharedStylesFile = "Shared styles file"

    static func downloadFile(_ count: Int) -> String { "Download File (\(count) Styles)" }

    /// The strip over a container covering both columns.
    static func fileLine(_ count: Int, size: String) -> String { "1 file · \(count) styles · \(size)" }

    /// Under the selected style, when its file holds more than one style.
    static func sharedFile(_ count: Int, across sets: [String]) -> String {
        let across = sets.count > 1 ? " across " + list(sets) : ""
        return "This file contains \(count) styles\(across). Downloading or removing it affects them all."
    }

    /// The Remove dialog's message for a file holding more than one style.
    static func removeShared(_ count: Int) -> String {
        "This removes all \(count) styles in this file from Uniboard. You can download it again later."
    }

    /// VoiceOver, after a cell's file state.
    static func fileContains(_ count: Int) -> String { "File contains \(count) styles" }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

/// One catalog style, as the grid needs it.
struct StyleGridStyle: Equatable, Sendable {
    let id: String
    let name: String
    let fileID: String
    let postScriptName: String
    let variationInstance: [String: Double]?

    init(id: String, name: String, fileID: String, postScriptName: String, variationInstance: [String: Double]? = nil) {
        self.id = id; self.name = name; self.fileID = fileID
        self.postScriptName = postScriptName; self.variationInstance = variationInstance
    }

    var isVariable: Bool { variationInstance != nil }
}

/// One catalog file, as the grid needs it.
struct StyleGridFile: Equatable, Sendable {
    let id: String
    let path: String
    let bytes: Int64
}

/// Weight, slope and width derived from one style's names and coordinates (§1).
struct StyleTraits: Equatable, Sendable {
    let weight: Int
    let italic: Bool
    let width: Double
    /// The style's own weight word, else the nearest standard weight's name.
    let weightName: String
    /// Name words that aren't weight, width or italic words ("Mono", "Linear").
    let otherWords: [String]
}

/// §1's word rules.
enum StyleNameRules {
    enum Word: Equatable {
        case weight(name: String, value: Int)
        case width(name: String, value: Double)
        case italic
        case other(String)
    }

    static let weightWords: [(String, Int)] = [
        ("Thin", 100), ("Hairline", 100), ("ExtraLight", 200), ("UltraLight", 200), ("Light", 300),
        ("Regular", 400), ("Book", 400), ("Normal", 400), ("Medium", 500), ("SemiBold", 600), ("DemiBold", 600),
        ("Bold", 700), ("ExtraBold", 800), ("UltraBold", 800), ("Black", 900), ("Heavy", 900), ("ExtraBlack", 1000),
    ]
    static let widthWords: [(String, Double)] = [
        ("UltraCondensed", 50), ("ExtraCondensed", 62.5), ("Condensed", 75), ("SemiCondensed", 87.5),
        ("SemiExpanded", 112.5), ("Expanded", 125), ("ExtraExpanded", 150), ("UltraExpanded", 200),
    ]
    static let standardWeights: [(Int, String)] = [
        (100, "Thin"), (200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
        (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold"), (900, "Black"), (1000, "ExtraBlack"),
    ]
    private static let joins = [("Extra Bold", "ExtraBold"), ("Semi Bold", "SemiBold"), ("Extra Light", "ExtraLight"),
                                ("Ultra Light", "UltraLight"), ("Demi Bold", "DemiBold"), ("Ultra Bold", "UltraBold"),
                                ("Extra Black", "ExtraBlack"), ("BoldItalic", "Bold Italic")]
    /// The PostScript suffix's vocabulary, longest first so "ExtraBold" wins over "Bold".
    private static let suffixWords: [(String, Word)] = (weightWords.map { ($0.0, Word.weight(name: $0.0, value: $0.1)) }
        + widthWords.map { ($0.0, Word.width(name: $0.0, value: $0.1)) }
        + [("Italic", Word.italic), ("Oblique", Word.italic)])
        .map { ($0.0.lowercased(), $0.1) }
        .sorted { $0.0.count > $1.0.count }

    static func classify(_ word: String) -> Word {
        let lower = word.lowercased()
        if let match = weightWords.first(where: { $0.0.lowercased() == lower }) { return .weight(name: match.0, value: match.1) }
        if let match = widthWords.first(where: { $0.0.lowercased() == lower }) { return .width(name: match.0, value: match.1) }
        if lower == "italic" || lower == "oblique" || lower.hasSuffix("kursiv") { return .italic }
        return .other(word)
    }

    static func nameWords(_ name: String) -> [Word] {
        let joined = joins.reduce(name) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        return joined.split(separator: " ").map { classify(String($0)) }
    }

    /// The text after the first "-", split greedily into weight, width and
    /// Italic/Oblique words; nil unless it splits completely.
    static func postScriptWords(_ postScriptName: String) -> [Word]? {
        guard let dash = postScriptName.firstIndex(of: "-") else { return nil }
        var rest = Substring(postScriptName[postScriptName.index(after: dash)...].lowercased())
        var words: [Word] = []
        while !rest.isEmpty {
            guard let match = suffixWords.first(where: { rest.hasPrefix($0.0) }) else { return nil }
            words.append(match.1)
            rest = rest.dropFirst(match.0.count)
        }
        return words.isEmpty ? nil : words
    }

    static func standardName(_ weight: Int) -> String {
        standardWeights.min { (abs($0.0 - weight), $0.0) < (abs($1.0 - weight), $1.0) }!.1
    }

    static func traits(_ style: StyleGridStyle) -> StyleTraits {
        let words = nameWords(style.name)
        let suffix = postScriptWords(style.postScriptName)
        func firstWeight(_ list: [Word]) -> (name: String, value: Int)? {
            for case let .weight(name, value) in list { return (name, value) }
            return nil
        }
        func firstWidth(_ list: [Word]) -> Double? {
            for case let .width(_, value) in list { return value }
            return nil
        }
        let nameWeight = firstWeight(words)
        let suffixWeight = firstWeight(suffix ?? [])
        let axes = style.variationInstance
        let weight: Int, weightName: String
        if let wght = axes?["wght"] {
            weight = Int(wght.rounded())
            weightName = nameWeight?.name ?? standardName(weight)
        } else if let nameWeight, !["Regular", "Book", "Normal"].contains(nameWeight.name) {
            weight = nameWeight.value; weightName = nameWeight.name
        } else if let suffixWeight {
            weight = suffixWeight.value; weightName = suffixWeight.name
        } else {
            weight = 400
            weightName = nameWeight?.name ?? standardName(400)
        }
        let italic: Bool
        if let axes {
            italic = (axes["ital"] ?? 0) >= 1 || (axes["slnt"] ?? 0) != 0 || words.contains(.italic)
        } else {
            italic = (suffix ?? words).contains(.italic)
        }
        let width = axes?["wdth"] ?? firstWidth(words) ?? firstWidth(suffix ?? []) ?? 100
        let others = words.compactMap { word -> String? in if case let .other(text) = word { return text }; return nil }
        return StyleTraits(weight: weight, italic: italic, width: width, weightName: weightName, otherWords: others)
    }
}

/// A family's styles sorted into sets (menu options), rows (weights) and
/// Normal / Italic cells.
struct StyleGrid: Equatable, Sendable {
    struct Axis: Hashable, Sendable {
        let tag: String
        let value: Double
    }

    /// Width, the axes that tell sets apart (variable files) and the leftover
    /// name words (static files).
    struct SetKey: Hashable, Sendable {
        let width: Double
        let axes: [Axis]
        let words: [String]
    }

    struct CellKey: Hashable, Sendable {
        let set: SetKey
        let weight: Int
        let italic: Bool
    }

    struct Cell: Equatable, Sendable, Identifiable {
        let key: CellKey
        /// The style drawn and selected in this cell.
        let style: StyleGridStyle
        let traits: StyleTraits
        /// The same face in other files; never shown.
        let hidden: [StyleGridStyle]
        var id: String { style.id }
    }

    struct Row: Equatable, Sendable, Identifiable {
        let weight: Int
        let name: String
        let normal: Cell?
        let italic: Cell?
        var id: Int { weight }
        var cells: [Cell] { [normal, italic].compactMap { $0 } }
    }

    struct StyleSet: Equatable, Sendable, Identifiable {
        let id: Int
        let key: SetKey
        /// The menu option ("Normal", "Condensed", "Mono Linear", "Optical Size 14").
        let option: String
        let rows: [Row]
        var cells: [Cell] { rows.flatMap(\.cells) }
        var hasNormal: Bool { rows.contains { $0.normal != nil } }
        var hasItalic: Bool { rows.contains { $0.italic != nil } }
        func cell(weight: Int, italic: Bool) -> Cell? {
            rows.first { $0.weight == weight }.flatMap { italic ? $0.italic : $0.normal }
        }
    }

    /// The cells one file covers in one set (§4).
    enum Coverage: Equatable, Sendable {
        /// One cell: its own tile with a corner badge.
        case single
        /// Every cell of one column: one column container.
        case column(italic: Bool)
        /// Every cell of both columns: one container across both.
        case both
        /// Anything else: every cell its own tile and badge.
        case scattered
    }

    let sets: [StyleSet]
    /// "Width" or "Variant"; nil when the family has one set and so no menu.
    let menuTitle: String?
    let familyHasItalic: Bool
    private let styleCounts: [String: Int]
    private let cellKeys: [String: CellKey]

    /// `files` gives each file's path, for the `/static/` preference; a missing
    /// file counts as not static.
    static func make(styles: [StyleGridStyle], files: [String: StyleGridFile], downloadedFileIDs: Set<String>) -> StyleGrid {
        var styleCounts: [String: Int] = [:]
        var kept: [StyleGridStyle] = []
        var keptByInstance: [String: String] = [:]
        var aliases: [String: String] = [:]
        for style in styles {
            styleCounts[style.fileID, default: 0] += 1
            let instance = style.fileID + "|" + (style.variationInstance ?? [:]).sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            if let first = keptByInstance[instance] { aliases[style.id] = first; continue }
            keptByInstance[instance] = style.id
            kept.append(style)
        }
        let traits = kept.map(StyleNameRules.traits)

        // Axes whose value only follows upright vs italic don't make sets.
        let reserved: Set<String> = ["wght", "wdth", "ital", "slnt"]
        let tags = Set(kept.flatMap { ($0.variationInstance ?? [:]).keys }).subtracting(reserved)
        let following = Set(tags.filter { tag in
            var values: [Bool: Set<Double?>] = [:]
            for (style, trait) in zip(kept, traits) where style.isVariable {
                values[trait.italic, default: []].insert(style.variationInstance?[tag])
            }
            return values[false]?.count == 1 && values[true]?.count == 1 && values[false] != values[true]
        })

        var order: [SetKey] = []
        var firstOthers: [SetKey: [String]] = [:]
        var candidates: [CellKey: [(StyleGridStyle, StyleTraits)]] = [:]
        var cellOrder: [CellKey] = []
        for (style, trait) in zip(kept, traits) {
            let axes = (style.variationInstance ?? [:]).filter { tags.contains($0.key) && !following.contains($0.key) }
                .map { Axis(tag: $0.key, value: $0.value) }.sorted { $0.tag < $1.tag }
            let set = SetKey(width: trait.width, axes: axes, words: style.isVariable ? [] : trait.otherWords)
            if firstOthers[set] == nil { firstOthers[set] = trait.otherWords; order.append(set) }
            let key = CellKey(set: set, weight: trait.weight, italic: trait.italic)
            if candidates[key] == nil { cellOrder.append(key) }
            candidates[key, default: []].append((style, trait))
        }

        // One style per cell: downloaded, then variable, then not under /static/.
        func rank(_ style: StyleGridStyle) -> Int {
            (downloadedFileIDs.contains(style.fileID) ? 0 : 4) + (style.isVariable ? 0 : 2)
                + ((files[style.fileID]?.path.contains("/static/") ?? false) ? 1 : 0)
        }
        var cells: [CellKey: Cell] = [:]
        var cellKeys: [String: CellKey] = [:]
        for key in cellOrder {
            let group = candidates[key]!
            let best = group.indices.min { (rank(group[$0].0), $0) < (rank(group[$1].0), $1) }!
            cells[key] = Cell(key: key, style: group[best].0, traits: group[best].1,
                              hidden: group.indices.filter { $0 != best }.map { group[$0].0 })
            for (style, _) in group { cellKeys[style.id] = key }
        }
        for (alias, original) in aliases { cellKeys[alias] = cellKeys[original] }

        // Normal width first, then narrower to wider, then catalog order.
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let sorted = order.sorted { ($0.width == 100 ? 0 : 1, $0.width, index[$0]!) < ($1.width == 100 ? 0 : 1, $1.width, index[$1]!) }
        let (title, options) = Self.options(for: sorted, otherWords: firstOthers)
        let sets = sorted.enumerated().map { offset, set -> StyleSet in
            let weights = Set(cells.keys.filter { $0.set == set }.map(\.weight)).sorted()
            let rows = weights.map { weight -> Row in
                let normal = cells[CellKey(set: set, weight: weight, italic: false)]
                let italic = cells[CellKey(set: set, weight: weight, italic: true)]
                return Row(weight: weight, name: (normal ?? italic)!.traits.weightName, normal: normal, italic: italic)
            }
            return StyleSet(id: offset, key: set, option: options[offset], rows: rows)
        }
        return StyleGrid(sets: sets, menuTitle: sets.count > 1 ? title : nil,
                         familyHasItalic: sets.contains { $0.hasItalic }, styleCounts: styleCounts, cellKeys: cellKeys)
    }

    /// §2: "Width" when the sets differ only in width, otherwise "Variant".
    private static func options(for sets: [SetKey], otherWords: [SetKey: [String]]) -> (String, [String]) {
        if Set(sets.map { [$0.axes.map { "\($0.tag)=\($0.value)" }, $0.words] }).count == 1 {
            return (StyleGridCopy.width, sets.map { $0.width == 100 ? StyleGridCopy.normal : widthName($0.width) })
        }
        let words = sets.map { otherWords[$0]!.joined(separator: " ") }
        let labels: [String]
        if !words.contains(""), Set(words).count == words.count {
            labels = words
        } else {
            let tags = Set(sets.flatMap { $0.axes.map(\.tag) }).sorted()
            let differing = tags.filter { tag in Set(sets.map { set in set.axes.first { $0.tag == tag }?.value }).count > 1 }
            labels = zip(sets, words).map { set, words in
                let axes = set.axes.filter { differing.contains($0.tag) }.map { axis in
                    (axis.tag == "opsz" ? "Optical Size" : axis.tag) + " " + number(axis.value)
                }
                return axes.isEmpty ? words : axes.joined(separator: " ")
            }
        }
        let widthsDiffer = Set(sets.map(\.width)).count > 1
        return (StyleGridCopy.variant, zip(sets, labels).map { set, label in
            let parts = [widthsDiffer && set.width != 100 ? widthName(set.width) : "", label].filter { !$0.isEmpty }
            return parts.isEmpty ? StyleGridCopy.normal : parts.joined(separator: " ")
        })
    }

    /// "Semi Condensed" for 87.5; an unnamed width reads "wdth 80".
    static func widthName(_ width: Double) -> String {
        guard let word = StyleNameRules.widthWords.first(where: { $0.1 == width })?.0 else { return "wdth " + number(width) }
        return word.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
    }

    /// Whole values without decimals; negative values with a real minus sign.
    static func number(_ value: Double) -> String {
        let text = value == value.rounded() ? String(Int(value)) : String(value)
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// The number of catalog styles in a file, across all sets.
    func styleCount(fileID: String) -> Int { styleCounts[fileID] ?? 0 }

    /// The set and cell showing a style, or the cell that hides it as a duplicate.
    func location(of styleID: String) -> (set: StyleSet, cell: Cell)? {
        guard let key = cellKeys[styleID], let set = sets.first(where: { $0.key == key.set }) else { return nil }
        return (set, set.cell(weight: key.weight, italic: key.italic)!)
    }

    /// The first set's Regular upright cell, else the first set with one, else
    /// the first cell.
    var defaultCell: (set: StyleSet, cell: Cell)? {
        for set in sets { if let cell = set.cell(weight: 400, italic: false) { return (set, cell) } }
        return sets.first.map { (set: $0, cell: $0.cells[0]) }
    }

    /// §2: switching sets keeps the weight and slope when the new set has
    /// them, else its 400 upright cell, else its first cell.
    func cell(switchingFrom cell: Cell, to set: StyleSet) -> Cell {
        set.cell(weight: cell.key.weight, italic: cell.key.italic) ?? set.cell(weight: 400, italic: false) ?? set.cells[0]
    }

    /// §4: the shape of the cells a file covers in one set.
    func coverage(of fileID: String, in set: StyleSet) -> Coverage {
        let covered = set.cells.filter { $0.style.fileID == fileID }
        guard covered.count > 1 else { return .single }
        if covered.count == set.cells.count { return set.hasNormal && set.hasItalic ? .both : .column(italic: set.hasItalic) }
        let italic = covered[0].key.italic
        let column = set.cells.filter { $0.key.italic == italic }
        return covered.allSatisfy({ $0.key.italic == italic }) && covered.count == column.count ? .column(italic: italic) : .scattered
    }

    /// The menu options of every set showing a cell from this file.
    func options(coveredBy fileID: String) -> [String] {
        sets.filter { $0.cells.contains { $0.style.fileID == fileID } }.map(\.option)
    }

    /// §6: the set option when the family has a menu and it isn't "Normal",
    /// the weight name, then " Italic"; "Regular Italic" reads "Italic".
    func displayName(of cell: Cell, in set: StyleSet) -> String {
        var parts = menuTitle != nil && set.option != StyleGridCopy.normal ? [set.option] : []
        if !(cell.key.italic && cell.traits.weightName == "Regular") { parts.append(cell.traits.weightName) }
        if cell.key.italic { parts.append(StyleGridCopy.italic) }
        return parts.joined(separator: " ")
    }
}
