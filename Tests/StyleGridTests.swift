import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// design/styles-grid §1's fixtures, 1.4's width columns (§2–§3), file
/// coverage (§5), own and shared files (§6), derived names and the copy
/// (§11), then every style in the bundled catalog run through the same rules.
final class StyleGridTests: XCTestCase {
    private typealias Style = StyleGridStyle

    private let standard: [(Int, String)] = [(100, "Thin"), (200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
                                             (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold"), (900, "Black")]

    private func file(_ path: String, bytes: Int64 = 1000) -> StyleGridFile { StyleGridFile(id: path, path: path, bytes: bytes) }

    private func makeGrid(_ styles: [Style], downloaded: Set<String> = []) -> StyleGrid {
        let files = Dictionary(uniqueKeysWithValues: Set(styles.map(\.fileID)).map { ($0, file($0)) })
        return StyleGrid.make(styles: styles, files: files, downloadedFileIDs: downloaded)
    }

    private func s(_ name: String, _ ps: String, _ file: String, _ axes: [String: Double]? = nil, id: String? = nil,
                   instance: StyleGridInstance? = nil) -> Style {
        let coordinates = (axes ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return Style(id: id ?? "\(file)#\(name)#\(coordinates)",
              name: name, fileID: file, postScriptName: ps, variationInstance: axes, instance: instance)
    }

    /// (weight, name, a cell in any Normal column?, in any Italic column?) per row.
    private func shape(_ set: StyleGrid.StyleSet) -> [String] {
        set.rows.map { row in
            let normal = set.columns(italic: false).contains { row.cell(in: $0) != nil }
            let italic = set.columns(italic: true).contains { row.cell(in: $0) != nil }
            return "\(row.weight) \(row.name) \(normal ? "N" : "-")\(italic ? "I" : "-")"
        }
    }

    private func lato() -> [Style] {
        standard.flatMap { weight, name -> [Style] in
            let italicName = weight == 400 ? "Italic" : name + " Italic"
            let upright = weight == 400 ? "Regular" : name
            return [s(upright, "Lato-\(upright)", "ofl/lato/Lato-\(upright).ttf"),
                    s(italicName, "Lato-\(italicName.replacingOccurrences(of: " ", with: ""))",
                      "ofl/lato/Lato-\(italicName.replacingOccurrences(of: " ", with: "")).ttf")]
        }
    }

    private func roboto() -> [Style] {
        [(100.0, ""), (75.0, "Condensed ")].flatMap { width, prefix in
            standard.flatMap { weight, name -> [Style] in
                let upright = prefix + name
                let italic = weight == 400 ? prefix + "Italic" : prefix + name + " Italic"
                func instance(_ name: String) -> StyleGridInstance {
                    let ps = (width == 75 ? "RobotoCondensed-" : "Roboto-") + name.replacingOccurrences(of: "Condensed ", with: "").replacingOccurrences(of: " ", with: "")
                    return StyleGridInstance(id: "gstatic:s/roboto/v51/\(ps).ttf", postScriptName: ps, bytes: 124_000, sha256: String(repeating: "b", count: 64))
                }
                return [s(italic, "Roboto-" + italic.replacingOccurrences(of: " ", with: ""), "ofl/roboto/Roboto-Italic[wdth,wght].ttf",
                          ["wght": Double(weight), "wdth": width], instance: instance(italic)),
                        s(upright, "Roboto-" + upright.replacingOccurrences(of: " ", with: ""), "ofl/roboto/Roboto[wdth,wght].ttf",
                          ["wght": Double(weight), "wdth": width], instance: instance(upright))]
            }
        }
    }

    private func commissioner() -> [Style] {
        [0.0, -12].flatMap { slant in
            standard.map { weight, name in
                s(slant == 0 ? name : (weight == 400 ? "Italic" : name + " Italic"), "Commissioner-Thin",
                  "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf",
                  ["wght": Double(weight), "slnt": slant, "FLAR": 0, "VOLM": 0])
            }
        }
    }

    private func recursive() -> [Style] {
        let weights: [(Int, String, String)] = [(300, "Light", "Light"), (400, "", "Regular"), (500, "Medium", "Med"), (600, "SemiBold", "SemiBd"),
                                                (700, "Bold", "Bold"), (800, "ExtraBold", "ExtraBd"), (900, "Black", "Black"), (1000, "ExtraBlack", "XBlk")]
        var styles: [Style] = []
        for (mono, monoName, monoPS) in [(1.0, "Mono", "Mono"), (0, "Sans", "Sans")] {
            for (weight, name, ps) in weights {
                for (casual, casualName, casualPS) in [(0.0, "Linear", "Lnr"), (1, "Casual", "Csl")] {
                    let base = [monoName, casualName, name].filter { !$0.isEmpty }.joined(separator: " ")
                    let axes: [String: Double] = ["MONO": mono, "CASL": casual, "wght": Double(weight)]
                    styles.append(s(base, "Recursive\(monoPS)\(casualPS)-\(ps)", "ofl/recursive/Recursive.ttf",
                                    axes.merging(["slnt": 0, "CRSV": 0.5]) { $1 }))
                    styles.append(s(base + " Italic", "Recursive\(monoPS)\(casualPS)-\(ps)Italic", "ofl/recursive/Recursive.ttf",
                                    axes.merging(["slnt": -15, "CRSV": 1]) { $1 }))
                }
            }
        }
        return styles
    }

    func testPinnedGroupAndCrossGroupStripClampToTheirMeasuredContainer() {
        // A wide shared container stays pinned at the visible leading edge.
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: 0, width: 1088, contentWidth: 180), 0)
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: -120, width: 1088, contentWidth: 180), 120)
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: -600, width: 1088, contentWidth: 180), 600)
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: -1000, width: 1088, contentWidth: 180), 898)
        // A group not yet at the leading edge doesn't move, nor does an
        // over-wide label get a negative offset. Remeasuring updates the clamp.
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: 80, width: 540, contentWidth: 80), 0)
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: -500, width: 540, contentWidth: 100), 430)
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: -500, width: 540, contentWidth: 200), 330)
        XCTAssertEqual(StyleGrid.pinnedHeaderOffset(minX: -60, width: 120, contentWidth: 180), 0)
    }

    // MARK: §10 copy

    func testCopyIsExact() {
        XCTAssertEqual(StyleGridCopy.variant, "Variant")
        XCTAssertEqual(StyleGridCopy.normal, "Normal")
        XCTAssertEqual(StyleGridCopy.italic, "Italic")
        XCTAssertEqual(StyleGridCopy.standard, "Standard")
        XCTAssertEqual(StyleGridCopy.noItalics, "No italic styles in this family.")
        XCTAssertEqual(StyleGridCopy.noStyles, "No styles available.")
        XCTAssertEqual(StyleGridCopy.downloadStyle("Condensed Bold"), "Download Condensed Bold")
        XCTAssertEqual(StyleGridCopy.downloadFile(18), "Download File (18 Styles)")
        XCTAssertEqual(StyleGridCopy.removeFile(18), "Remove File (18 Styles)")
        XCTAssertEqual(StyleGridCopy.removeDownload, "Remove Download")
        XCTAssertEqual(StyleGridCopy.fileLine(18, size: "742 KB"), "1 file · 18 styles · 742 KB")
        XCTAssertEqual(StyleGridCopy.groupFileLine("Normal", count: 18, size: "489 KB"), "Normal styles: 1 file · 18 styles · 489 KB")
        XCTAssertEqual(StyleGridCopy.includes(72) + StyleGridCopy.existingKept, "Includes 72 styles in one file. Existing downloads are kept.")
        XCTAssertEqual(StyleGridCopy.coverage(groups: ["Normal"], widths: ["Standard", "Condensed"]),
                       "Normal styles in Standard and Condensed widths.")
        XCTAssertEqual(StyleGridCopy.sharedOnly(36),
                       "This style is available here in a file containing 36 styles. Downloading or removing the file affects them all.")
        XCTAssertEqual(StyleGridCopy.removeShared(18),
                       "This removes all 18 styles in this file from Uniboard. You can download it again later.")
        XCTAssertEqual(StyleGridCopy.removeKeepsOthers,
                       "Uniboard will stop using this download. Styles available from other files will stay available. The file may remain stored on this device.")
        XCTAssertEqual(StyleGridCopy.removeSingle, "This removes the downloaded font from Uniboard. You can download it again later.")
        XCTAssertEqual(StyleGridCopy.downloadingStyle("Condensed Bold", percent: 64), "Downloading Condensed Bold… 64%")
        XCTAssertEqual(StyleGridCopy.downloadingFile(72, percent: 64), "Downloading file (72 styles)… 64%")
        XCTAssertEqual(StyleGridCopy.capacity(free: 12, limit: 16),
                       "Room for 12 more font files. Each file counts once, whether it contains one style or several. 40 MiB maximum per file.")
        XCTAssertEqual(StyleGridCopy.capacity(free: 1, limit: 16),
                       "Room for 1 more font file. Each file counts once, whether it contains one style or several. 40 MiB maximum per file.")
        XCTAssertEqual(StyleGridCopy.capacity(free: 0, limit: 16),
                       "All 16 font-file spaces are in use. Remove a font file here or in Font Downloads to make room. 40 MiB maximum per file.")
        XCTAssertEqual(StyleGridCopy.fileContains(18), "File contains 18 styles")
        XCTAssertEqual(StyleGridCopy.separateFile("128 KB"), "Separate file, 128 KB")
        XCTAssertEqual(StyleGridCopy.fileElement("Normal", count: 18, size: "489 KB"), "Normal styles, 1 file, 18 styles, 489 KB")
        XCTAssertEqual(StyleGridCopy.normalStylesFile, "Normal styles file")
        XCTAssertEqual(StyleGridCopy.italicStylesFile, "Italic styles file")
        XCTAssertEqual(StyleGridCopy.sharedStylesFile, "Shared styles file")
        XCTAssertEqual(StyleGridCopy.list([]), "")
        XCTAssertEqual(StyleGridCopy.list(["A"]), "A")
        XCTAssertEqual(StyleGridCopy.list(["A", "B", "C"]), "A, B and C")
        // No replacement wording anywhere (Camo msg794).
        for text in [StyleGridCopy.removeKeepsOthers, StyleGridCopy.includes(2) + StyleGridCopy.existingKept, StyleGridCopy.capacity(free: 0, limit: 16)] {
            XCTAssertFalse(text.contains("Replace") || text.contains("frees") || text.contains("Download All"), text)
        }
    }

    // MARK: §1 word rules

    func testNameWordsJoinAndClassify() {
        XCTAssertEqual(StyleNameRules.nameWords("Extra Bold Italic"), [.weight(name: "ExtraBold", value: 800), .italic])
        XCTAssertEqual(StyleNameRules.nameWords("Semi Bold"), [.weight(name: "SemiBold", value: 600)])
        XCTAssertEqual(StyleNameRules.nameWords("Ultra Light"), [.weight(name: "UltraLight", value: 200)])
        XCTAssertEqual(StyleNameRules.nameWords("Demi Bold"), [.weight(name: "DemiBold", value: 600)])
        XCTAssertEqual(StyleNameRules.nameWords("Ultra Bold"), [.weight(name: "UltraBold", value: 800)])
        XCTAssertEqual(StyleNameRules.nameWords("Extra Black"), [.weight(name: "ExtraBlack", value: 1000)])
        XCTAssertEqual(StyleNameRules.nameWords("Extra Light"), [.weight(name: "ExtraLight", value: 200)])
        XCTAssertEqual(StyleNameRules.nameWords("BoldItalic"), [.weight(name: "Bold", value: 700), .italic])
        XCTAssertEqual(StyleNameRules.nameWords("semibold Oblique"), [.weight(name: "SemiBold", value: 600), .italic])
        XCTAssertEqual(StyleNameRules.nameWords("MagerKursiv"), [.italic])
        XCTAssertEqual(StyleNameRules.nameWords("Mono  Linear Hairline"), [.other("Mono"), .other("Linear"), .weight(name: "Hairline", value: 100)])
        XCTAssertEqual(StyleNameRules.classify("SemiCondensed"), .width(name: "SemiCondensed", value: 87.5))
        XCTAssertEqual(StyleNameRules.classify("Heavy"), .weight(name: "Heavy", value: 900))
    }

    func testPostScriptSuffixSplitsOnlyCompletely() {
        XCTAssertEqual(StyleNameRules.postScriptWords("Roboto-CondensedExtraLightItalic"),
                       [.width(name: "Condensed", value: 75), .weight(name: "ExtraLight", value: 200), .italic])
        XCTAssertEqual(StyleNameRules.postScriptWords("X-ExtraBoldOblique"), [.weight(name: "ExtraBold", value: 800), .italic])
        XCTAssertEqual(StyleNameRules.postScriptWords("X-UltraExpandedregular"), [.width(name: "UltraExpanded", value: 200), .weight(name: "Regular", value: 400)])
        XCTAssertNil(StyleNameRules.postScriptWords("RecursiveMonoLnr-SemiBd"), "Abbreviations don't split")
        XCTAssertNil(StyleNameRules.postScriptWords("NoSuffix"))
        XCTAssertNil(StyleNameRules.postScriptWords("Trailing-"))
        XCTAssertEqual(StyleNameRules.postScriptWords("A-B-Bold"), nil, "Only the text after the first dash, and it must split")
    }

    func testTraits() {
        let rules = StyleNameRules.self
        // wght wins, rounded; the name's word names it, else the nearest standard weight.
        XCTAssertEqual(rules.traits(s("SemiBold", "R-Regular", "f", ["wght": 525.6])),
                       StyleTraits(weight: 526, italic: false, width: 100, weightName: "SemiBold", otherWords: []))
        XCTAssertEqual(rules.traits(s("Mono Linear", "R-Regular", "f", ["wght": 650, "slnt": -15])),
                       StyleTraits(weight: 650, italic: true, width: 100, weightName: "SemiBold", otherWords: ["Mono", "Linear"]))
        XCTAssertEqual(rules.traits(s("Wide", "R-Regular", "f", ["wght": 450, "ital": 1, "wdth": 80])).italic, true)
        XCTAssertEqual(rules.traits(s("Wide", "R-Regular", "f", ["wght": 450, "wdth": 80])).width, 80)
        XCTAssertEqual(rules.traits(s("Italic", "R-Regular", "f", ["wght": 450])).italic, true, "An italic name word counts for a variable file")
        XCTAssertEqual(rules.traits(s("Regular", "R-Regular", "f", ["opsz": 14])).weight, 400)
        // Static: Regular/Book/Normal defer to the PostScript suffix.
        XCTAssertEqual(rules.traits(s("Regular", "AbhayaLibre-ExtraBold", "f")).weightName, "ExtraBold")
        XCTAssertEqual(rules.traits(s("Book", "X-Book", "f")).weightName, "Book")
        XCTAssertEqual(rules.traits(s("Book", "XBook", "f")), StyleTraits(weight: 400, italic: false, width: 100, weightName: "Book", otherWords: []))
        XCTAssertEqual(rules.traits(s("Display", "XDisplay", "f")), StyleTraits(weight: 400, italic: false, width: 100, weightName: "Regular", otherWords: ["Display"]))
        XCTAssertEqual(rules.traits(s("Heavy", "X-Black", "f")).weight, 900)
        // The suffix decides the slope of a static file when it splits; otherwise the name does.
        XCTAssertFalse(rules.traits(s("MagerKursiv", "Tuffy-Regular", "f")).italic)
        XCTAssertTrue(rules.traits(s("MagerKursiv", "Tuffy-Italic", "f")).italic)
        XCTAssertTrue(rules.traits(s("Italic", "Odd-Kursiv", "f")).italic)
        // Width: name word, then suffix word.
        XCTAssertEqual(rules.traits(s("Bold", "X-ExtraCondensedBold", "f")).width, 62.5)
        XCTAssertEqual(rules.traits(s("Expanded Bold", "X-Bold", "f")).width, 125)
        XCTAssertEqual(StyleNameRules.standardName(150), "Thin")
        XCTAssertEqual(StyleNameRules.standardName(267), "Light")
        XCTAssertEqual(StyleNameRules.standardName(1000), "ExtraBlack")
    }

    // MARK: §1 fixtures

    func testABeeZee() {
        let grid = makeGrid([s("Italic", "ABeeZee-Italic", "ofl/abeezee/ABeeZee-Italic.ttf"), s("Regular", "ABeeZee-Regular", "ofl/abeezee/ABeeZee-Regular.ttf")])
        XCTAssertEqual(grid.sets.count, 1)
        XCTAssertNil(grid.menuTitle)
        XCTAssertEqual(shape(grid.sets[0]), ["400 Regular NI"])
        XCTAssertEqual(grid.coverage(of: "ofl/abeezee/ABeeZee-Regular.ttf", in: grid.sets[0]), .single)
        XCTAssertEqual(grid.coverage(of: "ofl/abeezee/ABeeZee-Italic.ttf", in: grid.sets[0]), .single)
        XCTAssertEqual(grid.defaultCell?.cell.style.name, "Regular")
        XCTAssertTrue(grid.familyHasItalic)
    }

    func testLato() {
        let grid = makeGrid(lato())
        XCTAssertEqual(shape(grid.sets[0]), standard.map { "\($0.0) \($0.1) NI" })
        XCTAssertEqual(Set(grid.sets[0].cells.map(\.style.fileID)).count, 18)
        for cell in grid.sets[0].cells { XCTAssertEqual(grid.coverage(of: cell.style.fileID, in: grid.sets[0]), .single) }
        let boldItalic = grid.sets[0].cell(weight: 700, italic: true)!
        XCTAssertEqual(grid.displayName(of: boldItalic, in: grid.sets[0]), "Bold Italic")
        XCTAssertEqual(grid.displayName(of: grid.sets[0].cell(weight: 400, italic: true)!, in: grid.sets[0]), "Italic")
        XCTAssertEqual(grid.displayName(of: grid.sets[0].cell(weight: 400, italic: false)!, in: grid.sets[0]), "Regular")
        XCTAssertEqual(grid.styleCount(fileID: boldItalic.style.fileID), 1)
        XCTAssertEqual(grid.styleCount(fileID: "absent"), 0)
        // One width: no row C, no container; every style has its own static file (case A2).
        XCTAssertFalse(grid.sets[0].showsWidths)
        XCTAssertEqual(grid.ownFile(of: boldItalic), StyleGridDownload(id: boldItalic.style.fileID, filename: "Lato-BoldItalic.ttf",
                                                                        bytes: 1000, styleCount: 1, isInstance: false))
        XCTAssertNil(grid.sharedFile(of: boldItalic))
        XCTAssertNil(grid.containerFile(italic: false, in: grid.sets[0]))
    }

    func testRobotoWidthsAreColumns() {
        let grid = makeGrid(roboto())
        let upright = "ofl/roboto/Roboto[wdth,wght].ttf", italic = "ofl/roboto/Roboto-Italic[wdth,wght].ttf"
        XCTAssertNil(grid.menuTitle, "Width is no longer a menu")
        XCTAssertEqual(grid.sets.count, 1)
        let set = grid.sets[0]
        XCTAssertEqual(set.normalWidths, [100, 75])
        XCTAssertEqual(set.italicWidths, [100, 75])
        XCTAssertTrue(set.showsWidths)
        XCTAssertEqual(set.columns.map { StyleGrid.columnName($0.width) + ($0.italic ? " I" : "") }, ["Standard", "Condensed", "Standard I", "Condensed I"])
        XCTAssertEqual(shape(set), standard.map { "\($0.0) \($0.1) NI" })
        XCTAssertEqual(grid.coverage(of: upright, in: set), .group(italic: false))
        XCTAssertEqual(grid.coverage(of: italic, in: set), .group(italic: true))
        XCTAssertEqual(grid.containerFile(italic: false, in: set), upright)
        XCTAssertEqual(grid.containerFile(italic: true, in: set), italic)
        XCTAssertNil(grid.bothGroupsFile(in: set))
        XCTAssertEqual(grid.styleCount(fileID: upright), 18)
        XCTAssertEqual(grid.coverageLine(fileID: upright), "Normal styles in Standard and Condensed widths.")
        XCTAssertEqual(grid.coverageLine(fileID: italic), "Italic styles in Standard and Condensed widths.")
        // Names: width (not Standard), weight, Italic.
        let condensedBold = set.cell(width: 75, weight: 700, italic: false)!
        XCTAssertEqual(grid.displayName(of: condensedBold, in: set), "Condensed Bold")
        XCTAssertEqual(grid.displayName(of: set.cell(width: 75, weight: 500, italic: true)!, in: set), "Condensed Medium Italic")
        XCTAssertEqual(grid.displayName(of: set.cell(width: 75, weight: 400, italic: true)!, in: set), "Condensed Italic")
        XCTAssertEqual(grid.displayName(of: set.cell(weight: 500, italic: true)!, in: set), "Medium Italic")
        XCTAssertEqual(grid.displayName(of: set.cell(width: 75, weight: 400, italic: false)!, in: set), "Condensed Regular")
        // Option B: own file first, the shared file second (case A).
        XCTAssertEqual(grid.ownFile(of: condensedBold)?.filename, "RobotoCondensed-Bold.ttf")
        XCTAssertEqual(grid.ownFile(of: condensedBold)?.isInstance, true)
        XCTAssertEqual(grid.ownFile(of: condensedBold)?.styleCount, 1)
        XCTAssertEqual(grid.sharedFile(of: condensedBold), StyleGridDownload(id: upright, filename: "Roboto[wdth,wght].ttf", bytes: 1000,
                                                                              styleCount: 18, isInstance: false))
        XCTAssertEqual(grid.cells(coveredBy: upright).count, 18)
        XCTAssertEqual(grid.location(of: condensedBold.style.id)?.cell, condensedBold)
        XCTAssertNil(grid.location(of: "absent"))
        XCTAssertEqual(grid.defaultCell?.cell.style.name, "Regular")
        // A downloaded instance doesn't move the cell or change the container.
        let downloaded = makeGrid(roboto(), downloaded: [condensedBold.style.instance!.id])
        XCTAssertEqual(downloaded.containerFile(italic: false, in: downloaded.sets[0]), upright)
    }

    func testColumnTitlesBreakBeforeTheLastWord() {
        XCTAssertEqual(StyleGrid.columnName(100), "Standard")
        XCTAssertEqual(StyleGrid.columnTitle(100), "Standard")
        XCTAssertEqual(StyleGrid.columnTitle(75), "Condensed")
        XCTAssertEqual(StyleGrid.columnTitle(87.5), "Semi\nCondensed")
        XCTAssertEqual(StyleGrid.columnTitle(200), "Ultra\nExpanded")
        XCTAssertEqual(StyleGrid.columnTitle(80), "wdth\n80")
    }

    func testWeightOnlyInOneWidthStillGetsARow() {
        let grid = makeGrid([s("Regular", "X-Regular", "v.ttf", ["wght": 400, "wdth": 100]),
                             s("Condensed Black", "X-CondensedBlack", "v.ttf", ["wght": 900, "wdth": 75])])
        let set = grid.sets[0]
        XCTAssertEqual(set.rows.map(\.weight), [400, 900])
        XCTAssertNil(set.cell(weight: 900, italic: false), "Its Standard slot stays empty")
        XCTAssertEqual(set.rows[1].name, "Black")
        XCTAssertEqual(set.cells.map(\.style.name), ["Regular", "Condensed Black"])
    }

    func testCommissionerFileCoversBothColumns() {
        let grid = makeGrid(commissioner())
        XCTAssertEqual(shape(grid.sets[0]), standard.map { "\($0.0) \($0.1) NI" })
        XCTAssertEqual(grid.coverage(of: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf", in: grid.sets[0]), .both)
        XCTAssertEqual(grid.styleCount(fileID: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf"), 18)
        XCTAssertNil(grid.menuTitle, "Constant FLAR and VOLM make one set")
        XCTAssertEqual(grid.bothGroupsFile(in: grid.sets[0]), "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf")
        XCTAssertNil(grid.coverageLine(fileID: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf"), "One width")
        // No instance: shared file only (case B).
        XCTAssertNil(grid.ownFile(of: grid.sets[0].cells[0]))
        XCTAssertEqual(grid.sharedFile(of: grid.sets[0].cells[0])?.styleCount, 18)
    }

    func testOswaldIsOneColumnWithoutItalics() {
        let names = ["ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold"]
        let grid = makeGrid(names.enumerated().map { s($1, "Oswald-Regular", "ofl/oswald/Oswald[wght].ttf", ["wght": Double(200 + 100 * $0)]) })
        XCTAssertEqual(shape(grid.sets[0]), ["200 ExtraLight N-", "300 Light N-", "400 Regular N-", "500 Medium N-", "600 SemiBold N-", "700 Bold N-"])
        XCTAssertFalse(grid.familyHasItalic)
        XCTAssertFalse(grid.sets[0].hasItalic)
        XCTAssertEqual(grid.coverage(of: "ofl/oswald/Oswald[wght].ttf", in: grid.sets[0]), .group(italic: false))
    }

    func testAbhayaLibreNamesAreFixedByPostScriptNames() {
        let grid = makeGrid(["Bold", "ExtraBold", "Medium", "Regular", "SemiBold"].map { weight in
            s(weight == "Bold" ? "Bold" : "Regular", "AbhayaLibre-\(weight)", "ofl/abhayalibre/AbhayaLibre-\(weight).ttf")
        })
        XCTAssertEqual(shape(grid.sets[0]), ["400 Regular N-", "500 Medium N-", "600 SemiBold N-", "700 Bold N-", "800 ExtraBold N-"])
        XCTAssertEqual(grid.displayName(of: grid.sets[0].cell(weight: 800, italic: false)!, in: grid.sets[0]), "ExtraBold")
        XCTAssertEqual(grid.defaultCell?.cell.style.postScriptName, "AbhayaLibre-Regular")
    }

    func testTuffyKeepsRegularUpright() {
        let grid = makeGrid([s("Bold", "Tuffy-Bold", "Bold.ttf"), s("BoldItalic", "Tuffy-BoldItalic", "BoldItalic.ttf"),
                         s("MagerKursiv", "Tuffy-Italic", "Italic.ttf"), s("MagerKursiv", "Tuffy-Regular", "Regular.ttf")])
        XCTAssertEqual(shape(grid.sets[0]), ["400 Regular NI", "700 Bold NI"])
        XCTAssertEqual(grid.sets[0].cell(weight: 400, italic: false)?.style.postScriptName, "Tuffy-Regular")
    }

    func testOpenSansHebrewExtraBold() {
        let grid = makeGrid([s("Extra Bold", "OpenSansHebrew-ExtraBold", "eb.ttf"), s("Extra Bold Italic", "OpenSansHebrewExtraBold-Italic", "ebi.ttf"),
                         s("Regular", "OpenSansHebrew-Regular", "r.ttf")])
        XCTAssertEqual(shape(grid.sets[0]), ["400 Regular N-", "800 ExtraBold NI"])
    }

    func testInconsolataStaticCopiesHideBehindTheVariableFile() {
        let widths: [(Double, String)] = [(50, "UltraCondensed"), (62.5, "ExtraCondensed"), (75, "Condensed"), (87.5, "SemiCondensed"), (100, ""),
                                          (112.5, "SemiExpanded"), (125, "Expanded"), (150, "ExtraExpanded"), (200, "UltraExpanded")]
        let variable = "ofl/inconsolata/Inconsolata[wdth,wght].ttf"
        var styles: [Style] = []
        for (width, word) in widths {
            for (weight, name) in standard.dropFirst() {
                styles.append(s([word, name].filter { !$0.isEmpty }.joined(separator: " "), "Inconsolata-Regular", variable,
                                ["wght": Double(weight), "wdth": width]))
            }
        }
        // An exact duplicate instance, then static copies, one of them downloaded.
        styles.append(s("Regular", "Inconsolata-Regular", variable, ["wght": 400, "wdth": 100], id: "duplicate"))
        styles.append(s("Condensed Bold", "Inconsolata-CondensedBold", "ofl/inconsolata/static/Inconsolata-CondensedBold.ttf"))
        styles.append(s("Bold", "Inconsolata-Bold", "ofl/inconsolata/static/Inconsolata-Bold.ttf"))
        styles.append(s("Bold", "Ligconsolata-Bold", "ofl/inconsolata/static/Ligconsolata-Bold.ttf"))
        let grid = makeGrid(styles)
        XCTAssertNil(grid.menuTitle)
        XCTAssertEqual(grid.sets.count, 1)
        let set = grid.sets[0]
        XCTAssertEqual(set.normalWidths.map(StyleGrid.columnName), ["Standard", "Ultra Condensed", "Extra Condensed", "Condensed", "Semi Condensed",
                                                                    "Semi Expanded", "Expanded", "Extra Expanded", "Ultra Expanded"])
        XCTAssertTrue(set.italicWidths.isEmpty)
        XCTAssertFalse(grid.familyHasItalic)
        XCTAssertEqual(set.rows.count, 8)
        XCTAssertEqual(set.cells.count, 72)
        XCTAssertTrue(set.cells.allSatisfy { $0.style.fileID == variable })
        XCTAssertEqual(grid.coverage(of: variable, in: set), .group(italic: false))
        let bold = grid.sets[0].cell(weight: 700, italic: false)!
        XCTAssertEqual(bold.hidden.map(\.postScriptName), ["Inconsolata-Bold", "Ligconsolata-Bold"])
        XCTAssertEqual(grid.location(of: "duplicate")?.cell.style.name, "Regular")
        XCTAssertEqual(grid.location(of: bold.hidden[1].id)?.cell, bold)
        XCTAssertEqual(grid.styleCount(fileID: variable), 72, "Distinct cells: the repeated Regular counts once (1.4 §1)")
        XCTAssertEqual(grid.coverageLine(fileID: variable), "Normal styles in Standard, Ultra Condensed, Extra Condensed, Condensed, Semi Condensed, Semi Expanded, Expanded, Extra Expanded and Ultra Expanded widths.")
        // A downloaded static copy is the one shown, and then its file is a single tile.
        let downloaded = makeGrid(styles, downloaded: ["ofl/inconsolata/static/Inconsolata-Bold.ttf"])
        let shown = downloaded.sets[0].cell(weight: 700, italic: false)!
        XCTAssertEqual(shown.style.fileID, "ofl/inconsolata/static/Inconsolata-Bold.ttf")
        XCTAssertEqual(downloaded.coverage(of: variable, in: downloaded.sets[0]), .scattered)
        XCTAssertEqual(downloaded.coverage(of: shown.style.fileID, in: downloaded.sets[0]), .single)
    }

    func testStaticPathsLoseToOtherStaticPaths() {
        let grid = StyleGrid.make(styles: [s("Bold", "X-Bold", "ofl/x/static/X-Bold.ttf"), s("Bold", "X-Bold", "ofl/x/X-Bold.ttf"),
                                           s("Bold", "X-Bold", "unknown.ttf")],
                                  files: ["ofl/x/static/X-Bold.ttf": file("ofl/x/static/X-Bold.ttf"), "ofl/x/X-Bold.ttf": file("ofl/x/X-Bold.ttf")],
                                  downloadedFileIDs: [])
        XCTAssertEqual(grid.sets[0].cells[0].style.fileID, "ofl/x/X-Bold.ttf")
        XCTAssertEqual(grid.sets[0].cells[0].hidden.map(\.fileID), ["ofl/x/static/X-Bold.ttf", "unknown.ttf"])
    }

    func testRecursiveVariantsKeepItalicsInTheirSet() {
        let grid = makeGrid(recursive())
        XCTAssertEqual(grid.menuTitle, "Variant")
        XCTAssertEqual(grid.sets.map(\.option), ["Mono Linear", "Mono Casual", "Sans Linear", "Sans Casual"])
        for set in grid.sets {
            XCTAssertEqual(set.rows.map(\.weight), [300, 400, 500, 600, 700, 800, 900, 1000])
            XCTAssertTrue(set.rows.allSatisfy { set.cell(weight: $0.weight, italic: false) != nil && set.cell(weight: $0.weight, italic: true) != nil })
            XCTAssertEqual(grid.coverage(of: "ofl/recursive/Recursive.ttf", in: set), .both)
        }
        XCTAssertEqual(grid.sets[0].rows.map(\.name), ["Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black", "ExtraBlack"])
        let italic = grid.sets[1].cell(weight: 400, italic: true)!
        XCTAssertEqual(grid.displayName(of: italic, in: grid.sets[1]), "Mono Casual Italic")
        XCTAssertEqual(grid.displayName(of: grid.sets[1].cell(weight: 700, italic: false)!, in: grid.sets[1]), "Mono Casual Bold")
        XCTAssertEqual(grid.styleCount(fileID: "ofl/recursive/Recursive.ttf"), 64)
    }

    func testJaroOpticalSizes() {
        let grid = makeGrid([6.0, 14, 24, 48, 72].map { s("Regular", "Jaro-Regular", "ofl/jaro/Jaro[opsz].ttf", ["opsz": $0]) })
        XCTAssertEqual(grid.menuTitle, "Variant")
        XCTAssertEqual(grid.sets.map(\.option), ["Optical Size 6", "Optical Size 14", "Optical Size 24", "Optical Size 48", "Optical Size 72"])
        XCTAssertTrue(grid.sets.allSatisfy { $0.cells.count == 1 })
        XCTAssertEqual(grid.coverage(of: "ofl/jaro/Jaro[opsz].ttf", in: grid.sets[2]), .single)
        XCTAssertEqual(grid.displayName(of: grid.sets[1].cells[0], in: grid.sets[1]), "Optical Size 14 Regular")
    }

    func testRokkittKeepsRealWeights() {
        let weights: [(String, Double)] = [("Thin", 100), ("ExtraLight", 198), ("Light", 267), ("Regular", 400), ("Medium", 500),
                                           ("SemiBold", 526), ("Bold", 635), ("ExtraBold", 769), ("Black", 900)]
        let grid = makeGrid(weights.map { s($0.0, "Rokkitt-Regular", "ofl/rokkittvfbeta/RokkittVFBeta.ttf", ["wght": $0.1]) })
        XCTAssertEqual(grid.sets[0].rows.map(\.weight), [100, 198, 267, 400, 500, 526, 635, 769, 900])
        XCTAssertEqual(grid.sets[0].rows.map(\.name), weights.map(\.0))
    }

    // MARK: §2 menu edge cases

    func testFrauncesItalicOnlySetAndAxisLabels() {
        let italic = "Fraunces-Italic.ttf", upright = "Fraunces.ttf"
        let grid = makeGrid([s("Thin Italic", "Fraunces-ThinItalic", italic, ["opsz": 9, "wght": 100, "SOFT": 100, "WONK": 1]),
                         s("Italic", "Fraunces-Italic", italic, ["opsz": 9, "wght": 400, "SOFT": 0, "WONK": 1]),
                         s("Regular", "Fraunces-Regular", upright, ["opsz": 9, "wght": 400, "SOFT": 0, "WONK": 1]),
                         s("Bold", "Fraunces-Bold", upright, ["opsz": 9, "wght": 700, "SOFT": 0, "WONK": 1])])
        XCTAssertEqual(grid.sets.map(\.option), ["SOFT 100", "SOFT 0"])
        XCTAssertFalse(grid.sets[0].hasNormal)
        XCTAssertTrue(grid.sets[0].hasItalic)
        XCTAssertEqual(grid.defaultCell?.cell.style.name, "Regular", "The first set has no Regular, so the next one's opens")
        XCTAssertEqual(grid.coverage(of: italic, in: grid.sets[1]), .single)
        XCTAssertEqual(grid.coverage(of: upright, in: grid.sets[1]), .group(italic: false), "Every Normal cell, beside another file's italic")
        // Switching to a set without the cell falls back to Regular, then to the first cell.
        let bold = grid.sets[1].cell(weight: 700, italic: false)!
        XCTAssertEqual(grid.cell(switchingFrom: bold, to: grid.sets[0]).style.name, "Thin Italic")
        XCTAssertEqual(grid.cell(switchingFrom: grid.sets[0].cells[0], to: grid.sets[1]).style.name, "Regular")
        XCTAssertEqual(grid.displayName(of: grid.sets[0].cells[0], in: grid.sets[0]), "SOFT 100 Thin Italic")
    }

    func testVariantLabelsWithWidthsNegativeValuesAndFallbacks() {
        let nega = makeGrid([s("Regular", "S-Regular", "v.ttf", ["wght": 400, "NEGA": 0]), s("Regular", "S-Regular", "v.ttf", ["wght": 400, "NEGA": -1])])
        XCTAssertEqual(nega.sets.map(\.option), ["NEGA 0", "NEGA \u{2212}1"])
        // Widths are columns, never options: a width-80 variable style joins the plain set.
        let mixed = makeGrid([s("Regular", "X-Regular", "a.ttf"), s("Display Regular", "XDisplay-Regular", "b.ttf"),
                          s("Condensed Display", "XDisplay-Condensed", "c.ttf"), s("Ultra", "XUltra", "d.ttf", ["wdth": 80, "wght": 400])])
        XCTAssertEqual(mixed.menuTitle, "Variant")
        XCTAssertEqual(mixed.sets.map(\.option), ["Normal", "Display"])
        XCTAssertEqual(mixed.sets[0].normalWidths, [100, 80])
        XCTAssertEqual(mixed.sets[1].normalWidths, [100, 75])
        XCTAssertEqual(mixed.displayName(of: mixed.sets[1].cell(width: 75, weight: 400, italic: false)!, in: mixed.sets[1]), "Display Condensed Regular")
        // Distinct words win over axes, without width words.
        let words = makeGrid([s("Mono", "A", "v.ttf", ["wght": 400, "MONO": 1]), s("Sans Condensed", "B", "v.ttf", ["wght": 400, "MONO": 0, "wdth": 75])])
        XCTAssertEqual(words.sets.map(\.option), ["Mono", "Sans"])
        XCTAssertEqual(StyleGrid.widthName(87.5), "Semi Condensed")
        XCTAssertEqual(StyleGrid.number(62.5), "62.5")
    }

    func testCoverageColumnInsideALargerSetAndEmptyGrid() {
        let grid = makeGrid([s("Regular", "X-Regular", "u.ttf", ["wght": 400]), s("Bold", "X-Bold", "u.ttf", ["wght": 700]),
                         s("Italic", "X-Italic", "i.ttf"), s("Bold Italic", "X-BoldItalic", "bi.ttf")])
        XCTAssertEqual(grid.coverage(of: "u.ttf", in: grid.sets[0]), .group(italic: false))
        XCTAssertEqual(grid.coverage(of: "i.ttf", in: grid.sets[0]), .single)
        let partial = makeGrid([s("Regular", "X-Regular", "u.ttf", ["wght": 400]), s("Bold", "X-Bold", "u.ttf", ["wght": 700]),
                                 s("Black", "X-Black", "k.ttf")])
        XCTAssertEqual(partial.coverage(of: "u.ttf", in: partial.sets[0]), .scattered)
        let empty = makeGrid([])
        XCTAssertTrue(empty.sets.isEmpty)
        XCTAssertNil(empty.defaultCell)
        XCTAssertNil(empty.menuTitle)
        XCTAssertFalse(empty.familyHasItalic)
    }

    func testDefaultCellAndIdentities() {
        let grid = makeGrid([s("Light", "X-Light", "l.ttf"), s("Bold Italic", "X-BoldItalic", "bi.ttf")])
        // No Regular upright: the first set's first cell.
        XCTAssertEqual(grid.defaultCell?.cell.style.name, "Light")
        XCTAssertEqual(grid.sets[0].rows.map(\.id), [300, 700])
        XCTAssertEqual(grid.sets[0].cells.map(\.id), ["l.ttf#Light#", "bi.ttf#Bold Italic#"])
        let lato = makeGrid(lato())
        XCTAssertEqual(lato.defaultCell?.cell.style.name, "Regular")
    }

    // MARK: The bundled catalog

    private struct Catalog: Decodable {
        struct Family: Decodable { let id: String; let name: String; let styles: [CatalogStyle] }
        struct Instance: Decodable { let path: String; let bytes: Int64; let sha256: String; let postScriptName: String }
        struct CatalogStyle: Decodable {
            let id: String; let name: String; let fileID: String; let postScriptName: String; let variationInstance: [String: Double]?
            let instance: Instance?
        }
        struct File: Decodable { let id: String; let repositoryPath: String; let bytes: Int64 }
        let snapshotDate: String
        let families: [Family]
        let files: [File]
    }

    /// The designer's check (§1): every style in the snapshot lands in a cell,
    /// no two faces collide, and the counts match.
    func testEveryCatalogStyleGetsACellWithoutCollisions() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/GoogleFonts/catalog.json")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        let files = Dictionary(uniqueKeysWithValues: catalog.files.map { ($0.id, StyleGridFile(id: $0.id, path: $0.repositoryPath, bytes: $0.bytes)) })
        XCTAssertEqual(catalog.snapshotDate, "2026-10-23")
        XCTAssertEqual(catalog.families.count, 2065)
        XCTAssertEqual(catalog.families.reduce(0) { $0 + $1.styles.count }, 9293)

        var single = 0, multi: [String: Int] = [:], mostRows = (0, ""), columns = 0, both = 0, other = 0
        var grids: [String: StyleGrid] = [:]
        for family in catalog.families {
            let styles = family.styles.map { style in
                Style(id: style.id, name: style.name, fileID: style.fileID, postScriptName: style.postScriptName, variationInstance: style.variationInstance,
                      instance: style.instance.map { StyleGridInstance(id: "gstatic:" + $0.path, postScriptName: $0.postScriptName, bytes: $0.bytes, sha256: $0.sha256) })
            }
            let grid = StyleGrid.make(styles: styles, files: files, downloadedFileIDs: [])
            grids[family.id] = grid
            for style in styles {
                guard let location = grid.location(of: style.id) else { XCTFail("\(family.name) \(style.name) has no cell"); continue }
                let same = [location.cell.style] + location.cell.hidden
                XCTAssertTrue(same.contains { $0.fileID == style.fileID && $0.variationInstance == style.variationInstance },
                              "\(family.name) \(style.name)")
            }
            for set in grid.sets {
                for cell in set.cells {
                    // Collision: two faces of one file, or a variable instance hidden behind another.
                    let fileIDs = ([cell.style] + cell.hidden).map(\.fileID)
                    XCTAssertEqual(Set(fileIDs).count, fileIDs.count, "\(family.name) collides at \(cell.key)")
                    XCTAssertTrue(cell.hidden.allSatisfy { !$0.isVariable }, "\(family.name) hides a variable instance at \(cell.key)")
                }
                if set.rows.count > mostRows.0 { mostRows = (set.rows.count, family.name) }
                for fileID in Set(set.cells.map(\.style.fileID)) where set.cells.filter({ $0.style.fileID == fileID }).count > 1 {
                    switch grid.coverage(of: fileID, in: set) {
                    case .group: columns += 1
                    case .both: both += 1
                    default: other += 1
                    }
                }
            }
            if grid.sets.count == 1 { single += 1 } else { multi[family.name] = grid.sets.count }
            XCTAssertEqual(Set(grid.sets.map(\.option)).count, grid.sets.count, "\(family.name) repeats a menu option")
        }
        // 1.4 §2: widths are columns, not sets, so width-only families have one set.
        let widthOnly = ["Encode Sans", "Encode Sans SC", "Hubot Sans", "Inconsolata", "Noto Sans Display", "Noto Serif Display", "Open Sans", "Roboto", "Ubuntu Sans"]
            + ["Arabic", "Bengali", "Gurmukhi", "Kannada", "Khmer", "Lao", "Malayalam", "Sinhala", "Tamil", "Telugu", "Thai"].map { "Noto Sans \($0) UI" }
        XCTAssertEqual(widthOnly.filter { multi[$0] != nil }, [], "Width families that still have a Variant menu")
        XCTAssertEqual(single, 2051)
        XCTAssertEqual(multi.count, 14)
        XCTAssertEqual(multi.max { $0.value < $1.value }?.key, "Decovar Alpha")
        XCTAssertEqual(multi["Decovar Alpha"], 17)
        XCTAssertEqual(mostRows.0, 10)
        XCTAssertEqual(mostRows.1, "Hepta Slab")
        XCTAssertEqual(columns, 753)
        XCTAssertEqual(both, 23)
        XCTAssertEqual(other, 0)

        // §1's fixtures, on the real catalog entries.
        func rows(_ id: String) -> [[Int]] { grids[id]!.sets.map { $0.rows.map(\.weight) } }
        XCTAssertEqual(rows("ofl/abeezee"), [[400]])
        XCTAssertEqual(grids["ofl/lato"]!.sets[0].cells.count, 18)
        let roboto = grids["ofl/roboto"]!
        XCTAssertNil(roboto.menuTitle)
        XCTAssertEqual(roboto.sets[0].normalWidths, [100, 75])
        XCTAssertEqual(roboto.sets[0].italicWidths, [100, 75])
        XCTAssertEqual(roboto.coverage(of: "ofl/roboto/Roboto-Italic[wdth,wght].ttf", in: roboto.sets[0]), .group(italic: true))
        // §10 check 5: Roboto Condensed Bold has its own verified file; the static name differs from the variable instance's.
        let condensedBold = roboto.sets[0].cell(width: 75, weight: 700, italic: false)!
        XCTAssertEqual(roboto.displayName(of: condensedBold, in: roboto.sets[0]), "Condensed Bold")
        XCTAssertEqual(condensedBold.style.postScriptName, "Roboto-CondensedBold")
        XCTAssertEqual(roboto.ownFile(of: condensedBold)?.filename, "RobotoCondensed-Bold.ttf")
        XCTAssertEqual(roboto.sharedFile(of: condensedBold)?.styleCount, 18)
        XCTAssertEqual(roboto.ownFile(of: roboto.sets[0].cell(weight: 700, italic: false)!)?.bytes, 124_292)
        XCTAssertEqual(grids["ofl/commissioner"]!.coverage(of: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf", in: grids["ofl/commissioner"]!.sets[0]), .both)
        XCTAssertEqual(rows("ofl/oswald"), [[200, 300, 400, 500, 600, 700]])
        XCTAssertFalse(grids["ofl/oswald"]!.familyHasItalic)
        XCTAssertEqual(rows("ofl/abhayalibre"), [[400, 500, 600, 700, 800]])
        XCTAssertFalse(grids["ofl/abhayalibre"]!.familyHasItalic)
        XCTAssertEqual(grids["ofl/tuffy"]!.sets[0].cell(weight: 400, italic: false)?.style.postScriptName, "Tuffy-Regular")
        XCTAssertEqual(grids["apache/opensanshebrew"]!.sets[0].cell(weight: 800, italic: false)?.style.name, "Extra Bold")
        let inconsolata = grids["ofl/inconsolata"]!
        XCTAssertEqual(inconsolata.sets.count, 1)
        XCTAssertEqual(inconsolata.sets[0].normalWidths, [100, 50, 62.5, 75, 87.5, 112.5, 125, 150, 200])
        XCTAssertTrue(inconsolata.sets[0].cells.allSatisfy { $0.style.isVariable })
        XCTAssertEqual(inconsolata.styleCount(fileID: "ofl/inconsolata/Inconsolata[wdth,wght].ttf"), 72, "§10 check 6")
        XCTAssertTrue(inconsolata.sets[0].cells.allSatisfy { inconsolata.ownFile(of: $0)?.isInstance == true })
        let display = grids["ofl/notosansdisplay"]!
        XCTAssertEqual(display.sets[0].columns.count, 8)
        // A width family with no verified instances: every style is shared-only (case B).
        let telugu = grids.values.first { $0.sets.first?.cells.first?.style.fileID.contains("NotoSansTeluguUI") == true }!
        XCTAssertTrue(telugu.sets[0].showsWidths)
        XCTAssertTrue(telugu.sets[0].cells.allSatisfy { telugu.ownFile(of: $0) == nil && telugu.sharedFile(of: $0) != nil })
        XCTAssertEqual(grids["ofl/recursive"]!.sets.map(\.option), ["Mono Linear", "Mono Casual", "Sans Linear", "Sans Casual"])
        XCTAssertTrue(grids["ofl/recursive"]!.sets.allSatisfy { $0.cells.count == 16 })
        XCTAssertEqual(grids["ofl/jaro"]!.sets.map(\.option), ["Optical Size 6", "Optical Size 14", "Optical Size 24", "Optical Size 48", "Optical Size 72"])
        XCTAssertEqual(rows("ofl/rokkittvfbeta"), [[100, 198, 267, 400, 500, 526, 635, 769, 900]])
        XCTAssertEqual(grids["ofl/fraunces"]!.sets.map { $0.hasNormal }, [false, true])
    }
}
