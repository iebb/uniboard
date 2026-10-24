import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// design/styles-grid §1's fixtures, the menu (§2), file coverage (§4),
/// derived names (§6) and the copy (§10), then every style in the bundled
/// catalog run through the same rules.
final class StyleGridTests: XCTestCase {
    private typealias Style = StyleGridStyle

    private let standard: [(Int, String)] = [(100, "Thin"), (200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
                                             (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold"), (900, "Black")]

    private func file(_ path: String, bytes: Int64 = 1000) -> StyleGridFile { StyleGridFile(id: path, path: path, bytes: bytes) }

    private func makeGrid(_ styles: [Style], downloaded: Set<String> = []) -> StyleGrid {
        let files = Dictionary(uniqueKeysWithValues: Set(styles.map(\.fileID)).map { ($0, file($0)) })
        return StyleGrid.make(styles: styles, files: files, downloadedFileIDs: downloaded)
    }

    private func s(_ name: String, _ ps: String, _ file: String, _ axes: [String: Double]? = nil, id: String? = nil) -> Style {
        let instance = (axes ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return Style(id: id ?? "\(file)#\(name)#\(instance)",
              name: name, fileID: file, postScriptName: ps, variationInstance: axes)
    }

    /// (weight, normal style name?, italic style name?) per row.
    private func shape(_ set: StyleGrid.StyleSet) -> [String] {
        set.rows.map { row in "\(row.weight) \(row.name) \(row.normal != nil ? "N" : "-")\(row.italic != nil ? "I" : "-")" }
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
                return [s(italic, "Roboto-" + italic.replacingOccurrences(of: " ", with: ""), "ofl/roboto/Roboto-Italic[wdth,wght].ttf",
                          ["wght": Double(weight), "wdth": width]),
                        s(upright, "Roboto-" + upright.replacingOccurrences(of: " ", with: ""), "ofl/roboto/Roboto[wdth,wght].ttf",
                          ["wght": Double(weight), "wdth": width])]
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

    // MARK: §10 copy

    func testCopyIsExact() {
        XCTAssertEqual(StyleGridCopy.width, "Width")
        XCTAssertEqual(StyleGridCopy.variant, "Variant")
        XCTAssertEqual(StyleGridCopy.normal, "Normal")
        XCTAssertEqual(StyleGridCopy.italic, "Italic")
        XCTAssertEqual(StyleGridCopy.noItalics, "No italic styles in this family.")
        XCTAssertEqual(StyleGridCopy.noStyles, "No styles available.")
        XCTAssertEqual(StyleGridCopy.downloadStyle, "Download Style")
        XCTAssertEqual(StyleGridCopy.downloadFile(18), "Download File (18 Styles)")
        XCTAssertEqual(StyleGridCopy.fileLine(18, size: "742 KB"), "1 file · 18 styles · 742 KB")
        XCTAssertEqual(StyleGridCopy.sharedFile(6, across: ["Normal"]),
                       "This file contains 6 styles. Downloading or removing it affects them all.")
        XCTAssertEqual(StyleGridCopy.sharedFile(18, across: ["Normal", "Condensed"]),
                       "This file contains 18 styles across Normal and Condensed. Downloading or removing it affects them all.")
        XCTAssertEqual(StyleGridCopy.removeShared(18),
                       "This removes all 18 styles in this file from Uniboard. You can download it again later.")
        XCTAssertEqual(StyleGridCopy.fileContains(18), "File contains 18 styles")
        XCTAssertEqual(StyleGridCopy.normalStylesFile, "Normal styles file")
        XCTAssertEqual(StyleGridCopy.italicStylesFile, "Italic styles file")
        XCTAssertEqual(StyleGridCopy.sharedStylesFile, "Shared styles file")
        XCTAssertEqual(StyleGridCopy.list([]), "")
        XCTAssertEqual(StyleGridCopy.list(["A"]), "A")
        XCTAssertEqual(StyleGridCopy.list(["A", "B", "C"]), "A, B and C")
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
    }

    func testRoboto() {
        let grid = makeGrid(roboto())
        let upright = "ofl/roboto/Roboto[wdth,wght].ttf", italic = "ofl/roboto/Roboto-Italic[wdth,wght].ttf"
        XCTAssertEqual(grid.menuTitle, "Width")
        XCTAssertEqual(grid.sets.map(\.option), ["Normal", "Condensed"])
        XCTAssertEqual(grid.sets.map(\.key.width), [100, 75])
        for set in grid.sets {
            XCTAssertEqual(shape(set), standard.map { "\($0.0) \($0.1) NI" })
            XCTAssertEqual(grid.coverage(of: upright, in: set), .column(italic: false))
            XCTAssertEqual(grid.coverage(of: italic, in: set), .column(italic: true))
        }
        XCTAssertEqual(grid.styleCount(fileID: upright), 18)
        XCTAssertEqual(grid.options(coveredBy: italic), ["Normal", "Condensed"])
        // Switching sets keeps the cell; names lead with a non-Normal option.
        let medium = grid.sets[0].cell(weight: 500, italic: true)!
        let condensed = grid.cell(switchingFrom: medium, to: grid.sets[1])
        XCTAssertEqual(condensed.style.name, "Condensed Medium Italic")
        XCTAssertEqual(grid.displayName(of: condensed, in: grid.sets[1]), "Condensed Medium Italic")
        XCTAssertEqual(grid.displayName(of: medium, in: grid.sets[0]), "Medium Italic")
        XCTAssertEqual(grid.displayName(of: grid.sets[1].cell(weight: 400, italic: false)!, in: grid.sets[1]), "Condensed Regular")
        XCTAssertEqual(grid.location(of: condensed.style.id)?.set.option, "Condensed")
        XCTAssertNil(grid.location(of: "absent"))
        XCTAssertEqual(grid.defaultCell?.cell.style.name, "Regular")
    }

    func testCommissionerFileCoversBothColumns() {
        let grid = makeGrid(commissioner())
        XCTAssertEqual(shape(grid.sets[0]), standard.map { "\($0.0) \($0.1) NI" })
        XCTAssertEqual(grid.coverage(of: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf", in: grid.sets[0]), .both)
        XCTAssertEqual(grid.styleCount(fileID: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf"), 18)
        XCTAssertNil(grid.menuTitle, "Constant FLAR and VOLM make one set")
    }

    func testOswaldIsOneColumnWithoutItalics() {
        let names = ["ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold"]
        let grid = makeGrid(names.enumerated().map { s($1, "Oswald-Regular", "ofl/oswald/Oswald[wght].ttf", ["wght": Double(200 + 100 * $0)]) })
        XCTAssertEqual(shape(grid.sets[0]), ["200 ExtraLight N-", "300 Light N-", "400 Regular N-", "500 Medium N-", "600 SemiBold N-", "700 Bold N-"])
        XCTAssertFalse(grid.familyHasItalic)
        XCTAssertFalse(grid.sets[0].hasItalic)
        XCTAssertEqual(grid.coverage(of: "ofl/oswald/Oswald[wght].ttf", in: grid.sets[0]), .column(italic: false))
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
        XCTAssertEqual(grid.menuTitle, "Width")
        XCTAssertEqual(grid.sets.map(\.option), ["Normal", "Ultra Condensed", "Extra Condensed", "Condensed", "Semi Condensed",
                                                 "Semi Expanded", "Expanded", "Extra Expanded", "Ultra Expanded"])
        for set in grid.sets {
            XCTAssertEqual(set.rows.count, 8)
            XCTAssertTrue(set.cells.allSatisfy { $0.style.fileID == variable })
            XCTAssertEqual(grid.coverage(of: variable, in: set), .column(italic: false))
        }
        let bold = grid.sets[0].cell(weight: 700, italic: false)!
        XCTAssertEqual(bold.hidden.map(\.postScriptName), ["Inconsolata-Bold", "Ligconsolata-Bold"])
        XCTAssertEqual(grid.location(of: "duplicate")?.cell.style.name, "Regular")
        XCTAssertEqual(grid.location(of: bold.hidden[1].id)?.cell, bold)
        XCTAssertEqual(grid.styleCount(fileID: variable), 73)
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
            XCTAssertTrue(set.rows.allSatisfy { $0.normal != nil && $0.italic != nil })
            XCTAssertEqual(grid.coverage(of: "ofl/recursive/Recursive.ttf", in: set), .both)
        }
        XCTAssertEqual(grid.sets[0].rows.map(\.name), ["Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black", "ExtraBlack"])
        let italic = grid.sets[1].cell(weight: 400, italic: true)!
        XCTAssertEqual(grid.displayName(of: italic, in: grid.sets[1]), "Mono Casual Italic")
        XCTAssertEqual(grid.displayName(of: grid.sets[1].cell(weight: 700, italic: false)!, in: grid.sets[1]), "Mono Casual Bold")
        XCTAssertEqual(grid.options(coveredBy: "ofl/recursive/Recursive.ttf").count, 4)
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
        XCTAssertEqual(grid.coverage(of: upright, in: grid.sets[1]), .column(italic: false), "Every Normal cell, beside another file's italic")
        // Switching to a set without the cell falls back to Regular, then to the first cell.
        let bold = grid.sets[1].cell(weight: 700, italic: false)!
        XCTAssertEqual(grid.cell(switchingFrom: bold, to: grid.sets[0]).style.name, "Thin Italic")
        XCTAssertEqual(grid.cell(switchingFrom: grid.sets[0].cells[0], to: grid.sets[1]).style.name, "Regular")
        XCTAssertEqual(grid.displayName(of: grid.sets[0].cells[0], in: grid.sets[0]), "SOFT 100 Thin Italic")
    }

    func testVariantLabelsWithWidthsNegativeValuesAndFallbacks() {
        let nega = makeGrid([s("Regular", "S-Regular", "v.ttf", ["wght": 400, "NEGA": 0]), s("Regular", "S-Regular", "v.ttf", ["wght": 400, "NEGA": -1])])
        XCTAssertEqual(nega.sets.map(\.option), ["NEGA 0", "NEGA \u{2212}1"])
        // Static sets: duplicate words fall back to words when there are no axes;
        // widths lead, and an empty label reads Normal.
        let mixed = makeGrid([s("Regular", "X-Regular", "a.ttf"), s("Display Regular", "XDisplay-Regular", "b.ttf"),
                          s("Condensed Display", "XDisplay-Condensed", "c.ttf"), s("Ultra", "XUltra", "d.ttf", ["wdth": 80, "wght": 400])])
        XCTAssertEqual(mixed.menuTitle, "Variant")
        XCTAssertEqual(mixed.sets.map(\.option), ["Normal", "Display", "Condensed Display", "wdth 80 Ultra"])
        // Distinct words win over axes, with the width in front.
        let words = makeGrid([s("Mono", "A", "v.ttf", ["wght": 400, "MONO": 1]), s("Sans Condensed", "B", "v.ttf", ["wght": 400, "MONO": 0, "wdth": 75])])
        XCTAssertEqual(words.sets.map(\.option), ["Mono", "Condensed Sans"])
        XCTAssertEqual(StyleGrid.widthName(87.5), "Semi Condensed")
        XCTAssertEqual(StyleGrid.number(62.5), "62.5")
    }

    func testCoverageColumnInsideALargerSetAndEmptyGrid() {
        let grid = makeGrid([s("Regular", "X-Regular", "u.ttf", ["wght": 400]), s("Bold", "X-Bold", "u.ttf", ["wght": 700]),
                         s("Italic", "X-Italic", "i.ttf"), s("Bold Italic", "X-BoldItalic", "bi.ttf")])
        XCTAssertEqual(grid.coverage(of: "u.ttf", in: grid.sets[0]), .column(italic: false))
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
        struct CatalogStyle: Decodable { let id: String; let name: String; let fileID: String; let postScriptName: String; let variationInstance: [String: Double]? }
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
            let styles = family.styles.map { Style(id: $0.id, name: $0.name, fileID: $0.fileID, postScriptName: $0.postScriptName, variationInstance: $0.variationInstance) }
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
                    case .column: columns += 1
                    case .both: both += 1
                    default: other += 1
                    }
                }
            }
            if grid.sets.count == 1 { single += 1 } else { multi[family.name] = grid.sets.count }
            XCTAssertEqual(Set(grid.sets.map(\.option)).count, grid.sets.count, "\(family.name) repeats a menu option")
        }
        XCTAssertEqual(single, 2032)
        XCTAssertEqual(multi.count, 33)
        XCTAssertEqual(multi.max { $0.value < $1.value }?.key, "Decovar Alpha")
        XCTAssertEqual(multi["Decovar Alpha"], 17)
        XCTAssertEqual(mostRows.0, 10)
        XCTAssertEqual(mostRows.1, "Hepta Slab")
        XCTAssertEqual(columns, 817)
        XCTAssertEqual(both, 23)
        XCTAssertEqual(other, 0)

        // §1's fixtures, on the real catalog entries.
        func rows(_ id: String) -> [[Int]] { grids[id]!.sets.map { $0.rows.map(\.weight) } }
        XCTAssertEqual(rows("ofl/abeezee"), [[400]])
        XCTAssertEqual(grids["ofl/lato"]!.sets[0].cells.count, 18)
        XCTAssertEqual(grids["ofl/roboto"]!.sets.map(\.option), ["Normal", "Condensed"])
        XCTAssertEqual(grids["ofl/roboto"]!.coverage(of: "ofl/roboto/Roboto-Italic[wdth,wght].ttf", in: grids["ofl/roboto"]!.sets[1]), .column(italic: true))
        XCTAssertEqual(grids["ofl/commissioner"]!.coverage(of: "ofl/commissioner/Commissioner[FLAR,VOLM,slnt,wght].ttf", in: grids["ofl/commissioner"]!.sets[0]), .both)
        XCTAssertEqual(rows("ofl/oswald"), [[200, 300, 400, 500, 600, 700]])
        XCTAssertFalse(grids["ofl/oswald"]!.familyHasItalic)
        XCTAssertEqual(rows("ofl/abhayalibre"), [[400, 500, 600, 700, 800]])
        XCTAssertFalse(grids["ofl/abhayalibre"]!.familyHasItalic)
        XCTAssertEqual(grids["ofl/tuffy"]!.sets[0].cell(weight: 400, italic: false)?.style.postScriptName, "Tuffy-Regular")
        XCTAssertEqual(grids["apache/opensanshebrew"]!.sets[0].cell(weight: 800, italic: false)?.style.name, "Extra Bold")
        XCTAssertEqual(grids["ofl/inconsolata"]!.sets.count, 9)
        XCTAssertTrue(grids["ofl/inconsolata"]!.sets.allSatisfy { $0.cells.allSatisfy { $0.style.isVariable } })
        XCTAssertEqual(grids["ofl/recursive"]!.sets.map(\.option), ["Mono Linear", "Mono Casual", "Sans Linear", "Sans Casual"])
        XCTAssertTrue(grids["ofl/recursive"]!.sets.allSatisfy { $0.cells.count == 16 })
        XCTAssertEqual(grids["ofl/jaro"]!.sets.map(\.option), ["Optical Size 6", "Optical Size 14", "Optical Size 24", "Optical Size 48", "Optical Size 72"])
        XCTAssertEqual(rows("ofl/rokkittvfbeta"), [[100, 198, 267, 400, 500, 526, 635, 769, 900]])
        XCTAssertEqual(grids["ofl/fraunces"]!.sets.map { $0.hasNormal }, [false, true])
    }
}
