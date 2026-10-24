import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class FontPickerCatalogTests: XCTestCase {
    private func face(_ family: String, _ style: String, section: FontPickerSection = .google, weight: Int = 400,
                      width: Double = 100, italic: Bool = false, ps: String? = nil, id: String? = nil,
                      keyboard: KeyboardFontStatus = .available) -> FontPickerFace {
        let ps = ps ?? family.replacingOccurrences(of: " ", with: "") + "-" + style.replacingOccurrences(of: " ", with: "")
        return FontPickerFace(id: id ?? "\(section.rawValue):\(ps)", family: family, style: style, postScriptName: ps, section: section,
                              traits: FontStyleTraits(weight: weight, width: width, italic: italic), keyboard: keyboard)
    }

    /// Roboto's 18 upright and italic weights, shuffled.
    private func roboto(section: FontPickerSection = .google) -> [FontPickerFace] {
        let weights = [(100, "Thin"), (200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
                       (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold"), (900, "Black")]
        var faces: [FontPickerFace] = []
        for (weight, name) in weights {
            faces.append(face("Roboto", name, section: section, weight: weight))
            faces.append(face("Roboto", weight == 400 ? "Italic" : name + " Italic", section: section, weight: weight, italic: true))
        }
        return faces.reversed()
    }

    // MARK: Copy

    func testCopyIsExact() {
        XCTAssertEqual(FontPickerCopy.searchPrompt, "Search family or style")
        XCTAssertEqual(FontPickerCopy.selected, "Selected")
        XCTAssertEqual(FontPickerCopy.systemFonts, "System Fonts")
        XCTAssertEqual(FontPickerCopy.otherDeviceFonts, "Other Device Fonts")
        XCTAssertEqual(FontPickerCopy.appOnly, "App Only")
        XCTAssertEqual(FontPickerCopy.keyboardUnverified, "Keyboard Unverified")
        XCTAssertEqual(FontPickerCopy.appOnlyFooter, "These fonts are available in the app, but not the keyboard. The keyboard uses the next matching rule or its default fonts.")
        XCTAssertEqual(FontPickerCopy.keyboardUnverifiedFooter, "Available in the app. Keyboard availability hasn’t been confirmed.")
        XCTAssertEqual(FontPickerCopy.cannotDisplayCharacter, "Can’t display this character")
        XCTAssertEqual(FontPickerCopy.unsupportedCharacterFooter, "These fonts can’t display this character.")
        XCTAssertEqual(FontPickerCopy.unsupportedRangeFooter, "These fonts can’t display any of these characters.")
        XCTAssertEqual(FontPickerCopy.styles(36), "36 styles")
        XCTAssertEqual(FontPickerCopy.styles(12, of: 36), "12 of 36 styles")
        XCTAssertEqual(FontPickerCopy.styleSelected("Medium Italic"), "Medium Italic selected")
        XCTAssertEqual(FontPickerCopy.checking(412, of: 1186), "Checking Fonts… 412 of 1,186")
        XCTAssertEqual(FontPickerCopy.checkingAccessibility(412, of: 1186), "Checking fonts, 412 of 1,186")
        XCTAssertEqual(FontPickerCopy.noMatches("Garamond"), "No fonts match “Garamond”.")
        XCTAssertEqual(FontPickerCopy.resultCount(0), "No fonts")
        XCTAssertEqual(FontPickerCopy.resultCount(1), "1 font family")
        XCTAssertEqual(FontPickerCopy.resultCount(1200), "1,200 font families")
    }

    // MARK: Sections and listing

    func testSectionsComeFromTheSourceInOrder() {
        XCTAssertEqual(FontPickerSection(source: .imported, isPack: false), .yours)
        XCTAssertEqual(FontPickerSection(source: .installed, isPack: false), .yours)
        XCTAssertEqual(FontPickerSection(source: .downloaded, isPack: false), .google)
        XCTAssertEqual(FontPickerSection(source: .downloaded, isPack: true), .preview)
        XCTAssertEqual(FontPickerSection(source: .included, isPack: false), .preview)
        XCTAssertEqual(FontPickerSection(source: .system, isPack: false), .system)
        XCTAssertEqual(FontPickerSection(source: .available, isPack: false), .other)
        XCTAssertEqual(FontPickerSection.allCases.map(\.title), ["Your Fonts", "Google Fonts", "Preview Fonts", "System Fonts", "Other Device Fonts"])
        XCTAssertEqual(FontPickerSection.allCases.map(\.identifier), ["yourFonts", "googleFonts", "previewFonts", "systemFonts", "otherDeviceFonts"])
        XCTAssertTrue(FontPickerSection.yours < .other)
    }

    func testPrivateFacesAndLastResortAreNeverListed() {
        XCTAssertTrue(FontPickerSection.isListed(postScriptName: "Helvetica", family: "Helvetica"))
        XCTAssertFalse(FontPickerSection.isListed(postScriptName: ".SFUI-Regular", family: ".SF UI"))
        XCTAssertFalse(FontPickerSection.isListed(postScriptName: "SFUI", family: ".SF UI"))
        XCTAssertFalse(FontPickerSection.isListed(postScriptName: "LastResort", family: "LastResort"))
        XCTAssertTrue(FontPickerSection.isSystemFontFile("/System/Library/Fonts/Core/Arial.ttf"))
        XCTAssertTrue(FontPickerSection.isSystemFontFile("/Library/Developer/CoreSimulator/Volumes/iOS_23A/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/Fonts/Core/Arial.ttf"))
        XCTAssertFalse(FontPickerSection.isSystemFontFile("/System/Library/AssetsV2/com_apple_MobileAsset_Font8/Baskerville.ttc"))
        XCTAssertFalse(FontPickerSection.isSystemFontFile("/var/mobile/Library/Fonts/Custom.ttf"))
    }

    // MARK: Keyboard tags

    func testTagsFooterAndVoiceOverText() {
        XCTAssertNil(KeyboardFontStatus.available.tag)
        XCTAssertNil(KeyboardFontStatus.available.accessibilityText)
        XCTAssertNil(KeyboardFontStatus.available.footer)
        XCTAssertEqual(KeyboardFontStatus.unverified.tag, "Keyboard Unverified")
        XCTAssertEqual(KeyboardFontStatus.unverified.accessibilityText, "Keyboard unverified")
        XCTAssertEqual(KeyboardFontStatus.unverified.footer, FontPickerCopy.keyboardUnverifiedFooter)
        XCTAssertEqual(KeyboardFontStatus.appOnly.tag, "App Only")
        XCTAssertEqual(KeyboardFontStatus.appOnly.accessibilityText, "App only, not on the keyboard")
        XCTAssertEqual(KeyboardFontStatus.appOnly.footer, FontPickerCopy.appOnlyFooter)
    }

    func testFilesAndSystemFontsAreAlwaysAvailable() {
        let evidence = KeyboardFontEvidence(systemVersion: "26.0", postScriptNames: [])
        for source in [FontSource.imported, .downloaded, .included, .system] {
            XCTAssertEqual(KeyboardFontEvidence.status(source: source, postScriptName: "X", evidence: evidence, systemVersion: "26.0"), .available)
            XCTAssertEqual(KeyboardFontEvidence.status(source: source, postScriptName: "X", evidence: nil, systemVersion: "26.0"), .available)
        }
    }

    func testProcessFacesNeedEvidenceFromThisIOSBuild() {
        let evidence = KeyboardFontEvidence(systemVersion: "26.0", postScriptNames: ["KaitiSC-Regular"])
        for source in [FontSource.installed, .available] {
            XCTAssertEqual(KeyboardFontEvidence.status(source: source, postScriptName: "KaitiSC-Regular", evidence: nil, systemVersion: "26.0"), .unverified,
                           "No report: never App Only")
            XCTAssertEqual(KeyboardFontEvidence.status(source: source, postScriptName: "KaitiSC-Regular", evidence: evidence, systemVersion: "26.1"), .unverified,
                           "A report from another iOS build is no evidence")
            XCTAssertEqual(KeyboardFontEvidence.status(source: source, postScriptName: "KaitiSC-Regular", evidence: evidence, systemVersion: "26.0"), .available)
            XCTAssertEqual(KeyboardFontEvidence.status(source: source, postScriptName: "YuMin-Medium", evidence: evidence, systemVersion: "26.0"), .appOnly)
        }
    }

    func testEvidenceRoundTripsAndRejectsBadPayloads() throws {
        let evidence = KeyboardFontEvidence(systemVersion: "Version 26.0 (Build 23A)", postScriptNames: ["B", "A", ".SFUI-Regular", "A"])
        XCTAssertEqual(evidence.postScriptNames, ["A", "B"], "Private faces are never recorded")
        let data = try XCTUnwrap(evidence.encoded())
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"postScriptNames":["A","B"],"schemaVersion":1,"systemVersion":"Version 26.0 (Build 23A)"}"#)
        XCTAssertEqual(KeyboardFontEvidence.decode(data), evidence)
        XCTAssertNil(KeyboardFontEvidence.decode(Data()))
        XCTAssertNil(KeyboardFontEvidence.decode(Data("{".utf8)))
        XCTAssertNil(KeyboardFontEvidence.decode(Data(#"{"postScriptNames":[],"schemaVersion":2,"systemVersion":"26"}"#.utf8)))
        XCTAssertNil(KeyboardFontEvidence.decode(Data(#"{"postScriptNames":[],"schemaVersion":1,"systemVersion":""}"#.utf8)))
        XCTAssertNil(KeyboardFontEvidence.decode(Data(count: KeyboardFontEvidence.maximumPayloadBytes + 1)))
        let huge = KeyboardFontEvidence(systemVersion: "26", postScriptNames: (0..<200_000).map { "Font-\($0)-ABCDEFGHIJ" })
        XCTAssertNil(huge.encoded(), "Over the size cap")
    }

    func testCurrentEvidenceListsThisProcessFonts() {
        let current = KeyboardFontEvidence.current(systemVersion: "test")
        XCTAssertEqual(current.systemVersion, "test")
        XCTAssertFalse(current.postScriptNames.isEmpty)
        XCTAssertFalse(current.postScriptNames.contains { $0.hasPrefix(".") })
        XCTAssertFalse(KeyboardFontEvidence.current().systemVersion.isEmpty)
    }

    func testStoreWritesOnlyChangesAndToleratesFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardFontEvidenceStore(root: { directory })
        let evidence = KeyboardFontEvidence(systemVersion: "26.0", postScriptNames: ["A"])
        XCTAssertNil(store.load())
        XCTAssertTrue(store.record(evidence))
        XCTAssertEqual(store.load(), evidence)
        XCTAssertFalse(store.record(evidence), "Unchanged: no write")
        XCTAssertTrue(store.record(KeyboardFontEvidence(systemVersion: "26.1", postScriptNames: ["A"])))

        struct Refused: Error {}
        var failing = KeyboardFontEvidenceStore(root: { directory })
        failing.write = { _, _ in throw Refused() }
        XCTAssertFalse(failing.record(evidence))
        let huge = KeyboardFontEvidence(systemVersion: "26", postScriptNames: (0..<200_000).map { "Font-\($0)-ABCDEFGHIJ" })
        XCTAssertFalse(store.record(huge))
        XCTAssertNil(KeyboardFontEvidenceStore(root: { nil }).load())
        _ = KeyboardFontEvidenceStore.appGroup.root()
        XCTAssertFalse(KeyboardFontEvidenceStore(root: { URL(string: "https://example.com")! }).record(evidence))
    }

    // MARK: Traits and style order

    func testTraitsMapToCSSWeightsAndWidths() {
        XCTAssertEqual(FontStyleTraits.weight(trait: -0.8), 100)
        XCTAssertEqual(FontStyleTraits.weight(trait: 0), 400)
        XCTAssertEqual(FontStyleTraits.weight(trait: 0.4), 700)
        XCTAssertEqual(FontStyleTraits.weight(trait: 1), 900)
        XCTAssertEqual(FontStyleTraits.width(trait: 0.005), 100)
        XCTAssertEqual(FontStyleTraits.width(trait: -0.2), 80, accuracy: 0.001)
        XCTAssertEqual(FontStyleTraits.width(trait: 2), 200)
        XCTAssertEqual(FontStyleTraits.width(trait: -2), 50)
    }

    func testStyleNamesGiveTraitsWhenNothingElseDoes() {
        XCTAssertEqual(FontStyleTraits.named("Regular"), FontStyleTraits(weight: 400, width: 100, italic: false))
        XCTAssertEqual(FontStyleTraits.named("ExtraLight Italic"), FontStyleTraits(weight: 200, width: 100, italic: true))
        XCTAssertEqual(FontStyleTraits.named("Semi Bold"), FontStyleTraits(weight: 600, width: 100, italic: false))
        XCTAssertEqual(FontStyleTraits.named("Bold Condensed Oblique"), FontStyleTraits(weight: 700, width: 75, italic: true))
        XCTAssertEqual(FontStyleTraits.named("SemiCondensed Black"), FontStyleTraits(weight: 900, width: 87.5, italic: false))
        XCTAssertEqual(FontStyleTraits.named("Medium Expanded"), FontStyleTraits(weight: 500, width: 125, italic: false))
    }

    func testVariationsWinOverTraitsWhichWinOverNames() {
        XCTAssertEqual(FontStyleTraits.resolve(style: "Bold", variations: ["wght": 300, "wdth": 75, "ital": 1], weightTrait: 0.4, widthTrait: 0, italicTrait: false),
                       FontStyleTraits(weight: 300, width: 75, italic: true))
        XCTAssertEqual(FontStyleTraits.resolve(style: "Thin", variations: [:], weightTrait: 0.4, widthTrait: 0.25, italicTrait: true),
                       FontStyleTraits(weight: 700, width: 125, italic: true))
        XCTAssertEqual(FontStyleTraits.resolve(style: "Light Condensed Italic", variations: [:], weightTrait: nil, widthTrait: nil, italicTrait: false),
                       FontStyleTraits(weight: 300, width: 75, italic: true))
        XCTAssertEqual(FontStyleTraits.resolve(style: "Regular", variations: ["slnt": -10, "wght": 5000], weightTrait: nil, widthTrait: nil, italicTrait: false),
                       FontStyleTraits(weight: 1000, width: 100, italic: true))
        XCTAssertFalse(FontStyleTraits.resolve(style: "Regular", variations: ["ital": 0.2], weightTrait: nil, widthTrait: nil, italicTrait: false).italic)
    }

    func testStylesOrderByWidthThenWeightThenUprightFirst() {
        let family = FontPickerFamily(section: .google, name: "Roboto", faces: roboto() + [
            face("Roboto", "Condensed", weight: 400, width: 75),
            face("Roboto", "Expanded", weight: 400, width: 125),
            face("Roboto", "SemiCondensed", weight: 400, width: 87.5),
        ])
        XCTAssertEqual(family.faces.map(\.style), [
            "Thin", "Thin Italic", "ExtraLight", "ExtraLight Italic", "Light", "Light Italic", "Regular", "Italic",
            "Medium", "Medium Italic", "SemiBold", "SemiBold Italic", "Bold", "Bold Italic", "ExtraBold", "ExtraBold Italic",
            "Black", "Black Italic", "Condensed", "SemiCondensed", "Expanded",
        ])
        XCTAssertEqual(family.representative.style, "Regular")
    }

    func testEqualTraitsOrderByNameAndRepeatedStylesAreFlagged() {
        let family = FontPickerFamily(section: .other, name: "Times", faces: [
            face("Times", "", section: .other, ps: "Times-B"), face("Times", "Regular", section: .other, ps: "Times-A"),
            face("Times", "Bold", section: .other, weight: 700),
        ])
        XCTAssertEqual(family.faces.map(\.postScriptName), ["Times-A", "Times-B", "Times-Bold"])
        XCTAssertEqual(family.faces[1].styleName, "Regular")
        XCTAssertEqual(family.repeatedStyleNames, ["Regular"])
        XCTAssertEqual(family.id, "4|Times")
    }

    func testRepresentativePrefersNormalWidthThenUprightThenWeightNearest400() {
        let lighter = FontPickerFamily(section: .system, name: "A", faces: [face("A", "Light", weight: 300), face("A", "Medium", weight: 500)])
        XCTAssertEqual(lighter.representative.style, "Light", "Ties go to the lighter")
        let italics = FontPickerFamily(section: .google, name: "Roboto", faces: [
            face("Roboto", "Thin Italic", weight: 100, italic: true), face("Roboto", "Light Italic", weight: 300, italic: true),
            face("Roboto", "Italic", italic: true), face("Roboto", "Black Italic", weight: 900, italic: true),
            face("Roboto", "Condensed Italic", width: 75, italic: true),
        ])
        XCTAssertEqual(italics.faces.first?.style, "Thin Italic")
        XCTAssertEqual(italics.representative.style, "Italic", "Italics only: Regular Italic, never Thin Italic")
        let upright = FontPickerFamily(section: .system, name: "B", faces: [face("B", "Italic", italic: true), face("B", "Bold", weight: 700)])
        XCTAssertEqual(upright.representative.style, "Bold", "Upright beats italic before weight")
        let normal = FontPickerFamily(section: .system, name: "D", faces: [face("D", "Condensed", width: 75), face("D", "Black Italic", weight: 900, italic: true)])
        XCTAssertEqual(normal.representative.style, "Black Italic", "Normal width beats upright")
        let wide = FontPickerFamily(section: .system, name: "C", faces: [face("C", "Bold Wide", weight: 700, width: 125),
                                                                           face("C", "Wide", width: 125)])
        XCTAssertEqual(wide.representative.style, "Wide")
    }

    func testFamilyTagOnlyWhenEveryFaceShareIt() {
        let same = FontPickerFamily(section: .other, name: "Kaiti", faces: [face("Kaiti", "Regular", keyboard: .appOnly), face("Kaiti", "Bold", weight: 700, keyboard: .appOnly)])
        XCTAssertEqual(same.keyboard, .appOnly)
        let mixed = FontPickerFamily(section: .other, name: "Yu", faces: [face("Yu", "Regular", keyboard: .appOnly), face("Yu", "Bold", weight: 700, keyboard: .unverified)])
        XCTAssertEqual(mixed.keyboard, .available, "Mixed: each style row shows its own")
    }

    // MARK: Grouping

    func testFacesGroupBySectionAndExactFamily() {
        let families = FontPickerFamily.grouping(roboto() + roboto(section: .yours) + [
            face("helvetica Neue", "Regular", section: .system), face("Helvetica", "Regular", section: .system),
            face("Helvetica", "Bold", section: .system, weight: 700), face("arial", "Regular", section: .system),
            face("Arial", "Regular", section: .system),
        ])
        XCTAssertEqual(families.map(\.id), ["0|Roboto", "1|Roboto", "3|Arial", "3|arial", "3|Helvetica", "3|helvetica Neue"])
        XCTAssertEqual(families[0].faces.count, 18)
        XCTAssertEqual(families[4].faces.map(\.style), ["Regular", "Bold"])
    }

    // MARK: Search

    func testEveryWordMustMatchFamilyStyleOrPostScriptName() {
        let query = FontPickerQuery("  roboto\tBÓLD ")
        XCTAssertEqual(query.words, ["roboto", "bold"])
        XCTAssertFalse(query.isEmpty)
        XCTAssertTrue(FontPickerQuery("").isEmpty)
        XCTAssertTrue(query.matches(face("Roboto", "SemiBold Italic").searchKey))
        XCTAssertFalse(query.matches(face("Roboto", "Light").searchKey))
        XCTAssertTrue(FontPickerQuery("timesnewromanps").matches(face("Times New Roman", "Regular", ps: "TimesNewRomanPSMT").searchKey))
        XCTAssertTrue(FontPickerQuery("cafe").matches(FontPickerQuery.fold("Café")))
    }

    func testFamilyNameMatchesShowCollapsedAndStyleMatchesShowOnlyThoseStyles() throws {
        let families = FontPickerFamily.grouping(roboto() + [face("Helvetica", "Regular", section: .system), face("Helvetica", "Bold", section: .system, weight: 700),
                                                             face("Helvetica Neue", "Regular", section: .system)])
        let bold = FontPickerContent.build(families, query: FontPickerQuery("roboto bold"), support: [:], ranked: false)
        XCTAssertEqual(bold.sections.map(\.section), [.google])
        let row = try XCTUnwrap(bold.sections.first?.rows.first)
        XCTAssertTrue(row.isFiltered)
        XCTAssertEqual(row.faces.map(\.style), ["SemiBold", "SemiBold Italic", "Bold", "Bold Italic", "ExtraBold", "ExtraBold Italic"])
        XCTAssertEqual(row.subtitle, "6 of 18 styles")

        let helvetica = FontPickerContent.build(families, query: FontPickerQuery("helvetica"), support: [:], ranked: false)
        XCTAssertEqual(helvetica.sections.flatMap(\.rows).map(\.family.name), ["Helvetica", "Helvetica Neue"])
        XCTAssertEqual(helvetica.sections.flatMap(\.rows).map(\.isFiltered), [false, false])
        XCTAssertEqual(helvetica.sections.flatMap(\.rows).map(\.subtitle), ["2 styles", "Regular"])
        XCTAssertEqual(helvetica.familyCount, 2)

        let none = FontPickerContent.build(families, query: FontPickerQuery("Garamond"), support: [:], ranked: false)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.sections, [])
        XCTAssertNil(FontPickerContent.row(families[0], query: FontPickerQuery("Garamond")))
    }

    func testFilteringFifteenHundredFacesIsFast() {
        var faces: [FontPickerFace] = []
        for index in 0..<250 { faces += roboto().prefix(6).map { face("Family \(index)", $0.style, weight: $0.traits.weight, italic: $0.traits.italic) } }
        let families = FontPickerFamily.grouping(faces)
        let start = Date()
        for text in ["f", "fa", "fam", "fami", "famil"] {
            _ = FontPickerContent.build(families, query: FontPickerQuery(text + " bold"), support: [:], ranked: true)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 5, 0.1)
    }

    // MARK: Support and order

    func testSupportStates() {
        XCTAssertTrue(FontPickerSupport.unsupported.isUnable)
        XCTAssertTrue(FontPickerSupport.coverage(0).isUnable)
        XCTAssertFalse(FontPickerSupport.coverage(3).isUnable)
        XCTAssertFalse(FontPickerSupport.missing.isUnable)
        XCTAssertTrue(FontPickerSupport.supported.isUsable)
        XCTAssertTrue(FontPickerSupport.coverage(3).isUsable)
        XCTAssertFalse(FontPickerSupport.coverage(0).isUsable)
        for support in [FontPickerSupport.checking, .unknown, .unsupported, .missing] { XCTAssertFalse(support.isUsable) }
    }

    func testNothingMovesWhileCheckingThenOneReorder() {
        let faces = [face("Arial", "Regular", section: .system), face("Arial", "Bold", section: .system, weight: 700),
                     face("Baskerville", "Regular", section: .system), face("Courier", "Regular", section: .system),
                     face("Damascus", "Regular", section: .system), face("Lato", "Regular"), face("Lato", "Regular", section: .other)]
        let families = FontPickerFamily.grouping(faces)
        let ids = Dictionary(uniqueKeysWithValues: faces.map { ($0.family + $0.style + "\($0.section.rawValue)", $0.id) })
        let support: [String: FontPickerSupport] = [
            ids["ArialRegular3"]!: .unsupported, ids["ArialBold3"]!: .supported,
            ids["BaskervilleRegular3"]!: .unsupported, ids["CourierRegular3"]!: .missing, ids["DamascusRegular3"]!: .supported,
            ids["LatoRegular1"]!: .coverage(0), ids["LatoRegular4"]!: .unsupported,
        ]
        let checking = FontPickerContent.build(families, query: FontPickerQuery(""), support: support, ranked: false)
        XCTAssertEqual(checking.sections.flatMap(\.rows).map(\.id), ["1|Lato", "3|Arial", "3|Baskerville", "3|Courier", "3|Damascus", "4|Lato"])
        XCTAssertEqual(checking.unsupported, [])

        let done = FontPickerContent.build(families, query: FontPickerQuery(""), support: support, ranked: true)
        XCTAssertEqual(done.sections.map(\.section), [.system])
        XCTAssertEqual(done.sections[0].rows.map(\.family.name), ["Arial", "Damascus", "Courier"], "A family with one usable face stays; missing is never unsupported")
        XCTAssertEqual(done.unsupported.map(\.id), ["3|Baskerville", "1|Lato", "4|Lato"])
        XCTAssertEqual(done.familyCount, 6)
        XCTAssertEqual(done.sections[0].id, .system)

        var partial = support
        partial[ids["ArialBold3"]!] = .checking
        partial[ids["ArialRegular3"]!] = .unsupported
        let unfinished = FontPickerContent.build(families, query: FontPickerQuery("arial"), support: partial, ranked: true)
        XCTAssertEqual(unfinished.sections.flatMap(\.rows).map(\.id), ["3|Arial"], "Unsupported only once every style is checked")
    }

    func testFootersFollowTheTagsInEachSectionAppOnlyFirst() {
        let families = FontPickerFamily.grouping([
            face("Kaiti", "Regular", section: .other, keyboard: .unverified), face("Yu", "Regular", section: .other, keyboard: .appOnly),
            face("Fira", "Regular", section: .yours, keyboard: .unverified), face("Arial", "Regular", section: .system),
        ])
        let content = FontPickerContent.build(families, query: FontPickerQuery(""), support: [:], ranked: false)
        XCTAssertEqual(content.sections.map(\.keyboardFooters), [[FontPickerCopy.keyboardUnverifiedFooter], [],
                                                               [FontPickerCopy.appOnlyFooter, FontPickerCopy.keyboardUnverifiedFooter]])
        let searched = FontPickerContent.build(families, query: FontPickerQuery("kaiti"), support: [:], ranked: false)
        XCTAssertEqual(searched.sections.map(\.keyboardFooters), [[FontPickerCopy.keyboardUnverifiedFooter]])
    }

    func testCheckOrderIsSelectedThenMatchesThenTheRest() {
        let families = FontPickerFamily.grouping([face("Arial", "Regular", section: .system, id: "a"), face("Roboto", "Bold", weight: 700, id: "rb"),
                                                  face("Roboto", "Light", weight: 300, id: "rl"), face("Courier", "Bold", section: .system, weight: 700, id: "cb")])
        let all: Set = ["a", "rb", "rl", "cb"]
        XCTAssertEqual(FontPickerContent.checkOrder(families, selected: "cb", query: FontPickerQuery(""), pending: all), ["cb", "rl", "rb", "a"])
        XCTAssertEqual(FontPickerContent.checkOrder(families, selected: nil, query: FontPickerQuery("bold"), pending: all), ["rb", "cb", "rl", "a"])
        XCTAssertEqual(FontPickerContent.checkOrder(families, selected: "cb", query: FontPickerQuery("arial"), pending: ["a", "rl"]), ["a", "rl"])
    }
}
