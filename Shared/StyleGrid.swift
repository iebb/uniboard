import Foundation

// The Google font page's styles grid (design/styles-grid-1.4/design.md), kept
// apart from SwiftUI so it can be tested: the copy, sorting catalog styles
// into (set, width column, weight, italic) cells (§1–§3), the Variant menu,
// which cells each file covers (§5), own vs shared files (§6) and the derived
// style names. The catalog has no weight or italic fields and some names are
// wrong, so everything here is derived from the style name, PostScript name
// and instance coordinates. Nothing here loads a font.

/// The grid's copy (1.4 §11, Camo msg674 + msg794): each string defined once here.
enum StyleGridCopy {
    static let variant = "Variant"
    static let normal = "Normal"
    static let italic = "Italic"
    /// wdth 100's column name.
    static let standard = "Standard"
    static let noItalics = "No italic styles in this family."
    static let noStyles = "No styles available."
    static let normalStylesFile = "Normal styles file"
    static let italicStylesFile = "Italic styles file"
    static let sharedStylesFile = "Shared styles file"
    static let removeDownload = "Remove Download"
    static let existingKept = " Existing downloads are kept."

    /// A verified single-style file (or a static family's own file).
    static func downloadStyle(_ name: String) -> String { "Download \(name)" }
    static func downloadFile(_ count: Int) -> String { "Download File (\(count) Styles)" }
    /// Case G: removing the shared file while the style's own file stays (Camo approved).
    static func removeFile(_ count: Int) -> String { "Remove File (\(count) Styles)" }

    /// The strip over a container covering both groups.
    static func fileLine(_ count: Int, size: String) -> String { "1 file · \(count) styles · \(size)" }
    /// The AX file line.
    static func groupFileLine(_ group: String, count: Int, size: String) -> String { "\(group) styles: 1 file · \(count) styles · \(size)" }

    /// Under "Download File": what one file includes.
    static func includes(_ count: Int) -> String { "Includes \(count) styles in one file." }
    /// "Normal styles in Standard and Condensed widths."
    static func coverage(groups: [String], widths: [String]) -> String {
        "\(list(groups)) styles in \(list(widths)) widths."
    }

    /// Selected style with no own file.
    static func sharedOnly(_ count: Int) -> String {
        "This style is available here in a file containing \(count) styles. Downloading or removing the file affects them all."
    }

    /// The Remove dialog's message for a file holding more than one style.
    static func removeShared(_ count: Int) -> String {
        "This removes all \(count) styles in this file from Uniboard. You can download it again later."
    }
    /// A single-style file nothing else supplies.
    static let removeSingle = "This removes the downloaded font from Uniboard. You can download it again later."
    /// Another kept file still supplies some of the styles (Camo).
    static let removeKeepsOthers = "Uniboard will stop using this download. Styles available from other files will stay available. The file may remain stored on this device."

    static func downloadingStyle(_ name: String, percent: Int) -> String { "Downloading \(name)… \(percent)%" }
    static func downloadingFile(_ count: Int, percent: Int) -> String { "Downloading file (\(count) styles)… \(percent)%" }

    /// §7 footer: the existing 16-file check, then the 1.3 per-file limit.
    static func capacity(free: Int, limit: Int) -> String {
        let room: String
        switch free {
        case ...0: room = "All \(limit) font-file spaces are in use. Remove a font file here or in Font Downloads to make room."
        case 1: room = "Room for 1 more font file. Each file counts once, whether it contains one style or several."
        default: room = "Room for \(free) more font files. Each file counts once, whether it contains one style or several."
        }
        return room + " 40 MiB maximum per file."
    }

    /// VoiceOver, after a cell's state.
    static func fileContains(_ count: Int) -> String { "File contains \(count) styles" }
    static func separateFile(_ size: String) -> String { "Separate file, \(size)" }
    /// "{group} styles, 1 file, {n} styles, {size}".
    static func fileElement(_ group: String, count: Int, size: String) -> String { "\(group) styles, 1 file, \(count) styles, \(size)" }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

/// A style's own single-style file (option B): a pinned gstatic instance.
struct StyleGridInstance: Equatable, Hashable, Sendable {
    /// The download id ("gstatic:s/…").
    let id: String
    let postScriptName: String
    let bytes: Int64
    let sha256: String
}

/// One catalog style, as the grid needs it.
struct StyleGridStyle: Equatable, Sendable {
    let id: String
    let name: String
    let fileID: String
    let postScriptName: String
    let variationInstance: [String: Double]?
    let instance: StyleGridInstance?

    init(id: String, name: String, fileID: String, postScriptName: String, variationInstance: [String: Double]? = nil,
         instance: StyleGridInstance? = nil) {
        self.id = id; self.name = name; self.fileID = fileID
        self.postScriptName = postScriptName; self.variationInstance = variationInstance; self.instance = instance
    }

    var isVariable: Bool { variationInstance != nil }
}

/// One catalog file, as the grid needs it.
struct StyleGridFile: Equatable, Sendable {
    let id: String
    let path: String
    let bytes: Int64
}

/// A downloadable file as the selected-style block shows it.
struct StyleGridDownload: Equatable, Sendable {
    /// Coordinator id: a repository file id or a gstatic instance id.
    let id: String
    /// "{file name}" in §6 line 2.
    let filename: String
    let bytes: Int64
    /// Distinct cells it fills; 1 for an own file.
    let styleCount: Int
    let isInstance: Bool
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

/// A family's styles sorted into sets (Variant options), width columns
/// inside the Normal and Italic groups, and weight rows.
struct StyleGrid: Equatable, Sendable {
    struct Axis: Hashable, Sendable {
        let tag: String
        let value: Double
    }

    /// The axes that tell sets apart (variable files) and the leftover name
    /// words (static files). Width is a column, never a set (1.4 §2).
    struct SetKey: Hashable, Sendable {
        let axes: [Axis]
        let words: [String]
    }

    /// One width inside one group.
    struct Column: Hashable, Sendable {
        let width: Double
        let italic: Bool
    }

    struct CellKey: Hashable, Sendable {
        let set: SetKey
        let column: Column
        let weight: Int
        var italic: Bool { column.italic }
    }

    struct Cell: Equatable, Sendable, Identifiable {
        let key: CellKey
        /// The style drawn and selected in this cell.
        let style: StyleGridStyle
        let traits: StyleTraits
        /// The same face in other files; never shown.
        let hidden: [StyleGridStyle]
        var id: String { style.id }
        var column: Column { key.column }
    }

    struct Row: Equatable, Sendable, Identifiable {
        let weight: Int
        let name: String
        let byColumn: [Column: Cell]
        var id: Int { weight }
        func cell(in column: Column) -> Cell? { byColumn[column] }
    }

    struct StyleSet: Equatable, Sendable, Identifiable {
        let id: Int
        let key: SetKey
        /// The Variant option ("Mono Linear", "Optical Size 14"); "Normal" without a menu.
        let option: String
        let rows: [Row]
        /// Each group's widths: Standard (100) first, then narrowest to widest.
        let normalWidths: [Double]
        let italicWidths: [Double]
        var hasNormal: Bool { !normalWidths.isEmpty }
        var hasItalic: Bool { !italicWidths.isEmpty }
        /// Normal columns, then Italic columns.
        var columns: [Column] {
            normalWidths.map { Column(width: $0, italic: false) } + italicWidths.map { Column(width: $0, italic: true) }
        }
        func columns(italic: Bool) -> [Column] { (italic ? italicWidths : normalWidths).map { Column(width: $0, italic: italic) } }
        /// Row C (width names) only when more than one width is visible.
        var showsWidths: Bool { Set(normalWidths + italicWidths).count > 1 }
        /// Row by row, columns in order (VoiceOver order).
        var cells: [Cell] { rows.flatMap { row in columns.compactMap { row.cell(in: $0) } } }
        func cell(width: Double = 100, weight: Int, italic: Bool) -> Cell? {
            rows.first { $0.weight == weight }?.cell(in: Column(width: width, italic: italic))
        }
    }

    /// The cells one file covers in one set (§5).
    enum Coverage: Equatable, Sendable {
        /// One cell.
        case single
        /// Every cell of one group, across all its width columns: one container.
        case group(italic: Bool)
        /// Every cell of both groups: one container across both.
        case both
        /// Anything else (legacy VF files): no container.
        case scattered
    }

    let sets: [StyleSet]
    /// "Variant" when sets differ by something other than width; else nil (no menu).
    let menuTitle: String?
    let familyHasItalic: Bool
    private let styleCounts: [String: Int]
    private let cellKeys: [String: CellKey]
    private let files: [String: StyleGridFile]

    /// `files` gives each file's path, for the `/static/` preference and
    /// sizes; a missing file counts as not static.
    static func make(styles: [StyleGridStyle], files: [String: StyleGridFile], downloadedFileIDs: Set<String>) -> StyleGrid {
        var kept: [StyleGridStyle] = []
        var keptByInstance: [String: String] = [:]
        var aliases: [String: String] = [:]
        for style in styles {
            let instance = style.fileID + "|" + (style.variationInstance ?? [:]).sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            if let first = keptByInstance[instance] { aliases[style.id] = first; continue }
            keptByInstance[instance] = style.id
            kept.append(style)
        }
        // {n} = distinct cells a file fills (same file + same coordinates = one), 1.4 §1.
        let styleCounts = Dictionary(grouping: kept, by: \.fileID).mapValues(\.count)
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
            let set = SetKey(axes: axes, words: style.isVariable ? [] : trait.otherWords)
            if firstOthers[set] == nil { firstOthers[set] = trait.otherWords; order.append(set) }
            let key = CellKey(set: set, column: Column(width: trait.width, italic: trait.italic), weight: trait.weight)
            if candidates[key] == nil { cellOrder.append(key) }
            candidates[key, default: []].append((style, trait))
        }

        // One style per cell: downloaded, then variable, then not under /static/.
        func rank(_ style: StyleGridStyle) -> Int {
            let downloaded = downloadedFileIDs.contains(style.fileID) || style.instance.map { downloadedFileIDs.contains($0.id) } == true
            return (downloaded ? 0 : 4) + (style.isVariable ? 0 : 2) + ((files[style.fileID]?.path.contains("/static/") ?? false) ? 1 : 0)
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

        let options = Self.options(for: order, otherWords: firstOthers)
        let sets = order.enumerated().map { offset, set -> StyleSet in
            let mine = cells.filter { $0.key.set == set }
            func widths(_ italic: Bool) -> [Double] {
                Set(mine.keys.filter { $0.italic == italic }.map(\.column.width)).sorted { (($0 == 100 ? 0 : 1), $0) < (($1 == 100 ? 0 : 1), $1) }
            }
            let weights = Set(mine.keys.map(\.weight)).sorted()
            let rows = weights.map { weight -> Row in
                let byColumn = Dictionary(uniqueKeysWithValues: mine.filter { $0.key.weight == weight }.map { ($0.key.column, $0.value) })
                // The weight word of the Standard upright cell, else of the first cell in column order.
                let name = byColumn.sorted { ($0.key.italic ? 1 : 0, $0.key.width == 100 ? 0 : 1, $0.key.width)
                    < ($1.key.italic ? 1 : 0, $1.key.width == 100 ? 0 : 1, $1.key.width) }[0].value.traits.weightName
                return Row(weight: weight, name: name, byColumn: byColumn)
            }
            return StyleSet(id: offset, key: set, option: options[offset], rows: rows, normalWidths: widths(false), italicWidths: widths(true))
        }
        return StyleGrid(sets: sets, menuTitle: sets.count > 1 ? StyleGridCopy.variant : nil,
                         familyHasItalic: sets.contains { $0.hasItalic }, styleCounts: styleCounts, cellKeys: cellKeys, files: files)
    }

    /// Variant options: never width words (1.4 §2).
    private static func options(for sets: [SetKey], otherWords: [SetKey: [String]]) -> [String] {
        guard sets.count > 1 else { return sets.map { _ in StyleGridCopy.normal } }
        let words = sets.map { otherWords[$0]!.joined(separator: " ") }
        if !words.contains(""), Set(words).count == words.count { return words }
        let tags = Set(sets.flatMap { $0.axes.map(\.tag) }).sorted()
        let differing = tags.filter { tag in Set(sets.map { set in set.axes.first { $0.tag == tag }?.value }).count > 1 }
        return zip(sets, words).map { set, words in
            let axes = set.axes.filter { differing.contains($0.tag) }.map { axis in
                (axis.tag == "opsz" ? "Optical Size" : axis.tag) + " " + number(axis.value)
            }
            let label = axes.isEmpty ? words : axes.joined(separator: " ")
            return label.isEmpty ? StyleGridCopy.normal : label
        }
    }

    /// "Semi Condensed" for 87.5; an unnamed width reads "wdth 80".
    static func widthName(_ width: Double) -> String {
        guard let word = StyleNameRules.widthWords.first(where: { $0.1 == width })?.0 else { return "wdth " + number(width) }
        return word.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
    }

    /// Row C's column name: "Standard" for wdth 100.
    static func columnName(_ width: Double) -> String { width == 100 ? StyleGridCopy.standard : widthName(width) }

    /// Row C's two-line form: the break before the last word ("Semi\nCondensed").
    static func columnTitle(_ width: Double) -> String {
        let name = columnName(width)
        guard let space = name.lastIndex(of: " ") else { return name }
        return name[..<space] + "\n" + name[name.index(after: space)...]
    }

    /// Whole values without decimals; negative values with a real minus sign.
    static func number(_ value: Double) -> String {
        let text = value == value.rounded() ? String(Int(value)) : String(value)
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// The number of distinct cells a file fills, across all sets (1.4 §1).
    func styleCount(fileID: String) -> Int { styleCounts[fileID] ?? 0 }

    /// The set and cell showing a style, or the cell that hides it as a duplicate.
    func location(of styleID: String) -> (set: StyleSet, cell: Cell)? {
        guard let key = cellKeys[styleID], let set = sets.first(where: { $0.key == key.set }),
              let cell = set.rows.first(where: { $0.weight == key.weight })?.cell(in: key.column) else { return nil }
        return (set, cell)
    }

    /// The first set's Standard Regular upright cell, else any width's
    /// Regular upright, else the first set with one, else the first cell.
    var defaultCell: (set: StyleSet, cell: Cell)? {
        for set in sets { if let cell = set.cell(weight: 400, italic: false) { return (set, cell) } }
        for set in sets {
            for width in set.normalWidths { if let cell = set.cell(width: width, weight: 400, italic: false) { return (set, cell) } }
        }
        return sets.first.map { (set: $0, cell: $0.cells[0]) }
    }

    /// Switching Variant keeps the width, weight and slope when the new set
    /// has them, else its Standard 400 upright cell, else its first cell.
    func cell(switchingFrom cell: Cell, to set: StyleSet) -> Cell {
        set.cell(width: cell.column.width, weight: cell.key.weight, italic: cell.key.italic)
            ?? set.cell(weight: 400, italic: false) ?? set.cells[0]
    }

    /// §5: the shape of the cells a file covers in one set.
    func coverage(of fileID: String, in set: StyleSet) -> Coverage {
        let all = set.cells
        let covered = all.filter { $0.style.fileID == fileID }
        guard covered.count > 1 else { return .single }
        if covered.count == all.count { return set.hasNormal && set.hasItalic ? .both : .group(italic: set.hasItalic) }
        let italic = covered[0].key.italic
        let group = all.filter { $0.key.italic == italic }
        return covered.allSatisfy({ $0.key.italic == italic }) && covered.count == group.count ? .group(italic: italic) : .scattered
    }

    /// The shared file drawn as a container over a group, if any.
    func containerFile(italic: Bool, in set: StyleSet) -> String? {
        let ids = Set(set.cells.filter { $0.key.italic == italic }.map(\.style.fileID))
        guard ids.count == 1, let id = ids.first, styleCount(fileID: id) > 1 else { return nil }
        switch coverage(of: id, in: set) {
        case .group(let covered) where covered == italic: return id
        case .both: return id
        default: return nil
        }
    }

    /// The shared file drawn as one container over both groups, if any.
    func bothGroupsFile(in set: StyleSet) -> String? {
        let ids = Set(set.cells.map(\.style.fileID))
        guard set.hasNormal, set.hasItalic, ids.count == 1, let id = ids.first, coverage(of: id, in: set) == .both else { return nil }
        return id
    }

    /// The style's own single-style file: its verified gstatic instance, else
    /// its catalog file when that file holds only this style (static families).
    func ownFile(of cell: Cell) -> StyleGridDownload? {
        if let instance = cell.style.instance {
            return StyleGridDownload(id: instance.id, filename: instance.postScriptName + ".ttf", bytes: instance.bytes,
                                     styleCount: 1, isInstance: true)
        }
        guard styleCount(fileID: cell.style.fileID) == 1, let file = files[cell.style.fileID] else { return nil }
        return StyleGridDownload(id: file.id, filename: (file.path as NSString).lastPathComponent, bytes: file.bytes,
                                 styleCount: 1, isInstance: false)
    }

    /// The file holding this style and others, if any.
    func sharedFile(of cell: Cell) -> StyleGridDownload? {
        let count = styleCount(fileID: cell.style.fileID)
        guard count > 1, let file = files[cell.style.fileID] else { return nil }
        return StyleGridDownload(id: file.id, filename: (file.path as NSString).lastPathComponent, bytes: file.bytes,
                                 styleCount: count, isInstance: false)
    }

    /// Every shown cell, in every set, filled by a file.
    func cells(coveredBy fileID: String) -> [Cell] {
        sets.flatMap { $0.cells.filter { $0.style.fileID == fileID } }
    }

    /// The caption's second line, when the file spans more than one width:
    /// "Normal styles in Standard and Condensed widths."
    func coverageLine(fileID: String) -> String? {
        let covered = cells(coveredBy: fileID)
        let widths = Set(covered.map(\.column.width)).sorted { (($0 == 100 ? 0 : 1), $0) < (($1 == 100 ? 0 : 1), $1) }
        guard widths.count > 1 else { return nil }
        let groups = [false, true].filter { italic in covered.contains { $0.key.italic == italic } }
            .map { $0 ? StyleGridCopy.italic : StyleGridCopy.normal }
        return StyleGridCopy.coverage(groups: groups, widths: widths.map(Self.columnName))
    }

    /// The selected style's name (1.4 §6): Variant option when there is a
    /// menu, width (not Standard), weight, " Italic"; "Regular Italic" reads "Italic".
    func displayName(of cell: Cell, in set: StyleSet) -> String {
        var parts = menuTitle != nil && set.option != StyleGridCopy.normal ? [set.option] : []
        if cell.column.width != 100 { parts.append(Self.widthName(cell.column.width)) }
        if !(cell.key.italic && cell.traits.weightName == "Regular") { parts.append(cell.traits.weightName) }
        if cell.key.italic { parts.append(StyleGridCopy.italic) }
        return parts.joined(separator: " ")
    }
}


extension StyleGrid {
    /// §4–5: group headings and the cross-group file strip share this clamp.
    /// The 10 pt inset remains visible; stop at the container's trailing edge.
    static func pinnedHeaderOffset(minX: CGFloat, width: CGFloat, contentWidth: CGFloat, inset: CGFloat = 10) -> CGFloat {
        min(max(-minX, 0), max(0, width - contentWidth - inset))
    }
}
