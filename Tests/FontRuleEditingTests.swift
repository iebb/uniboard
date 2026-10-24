import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class FontRuleEditingTests: XCTestCase {
    private func face(_ name: String) -> FontFaceReference {
        FontFaceReference(source: .installed, family: name, style: "Regular", postScriptName: name,
                          identity: .process(postScriptName: name, variations: [:]))
    }

    private func block(_ name: String) throws -> FontRuleBlock {
        try XCTUnwrap(FontRuleBlock(named: name))
    }

    // MARK: Copy

    func testCopyUsesExactWordingAndOneSentencePerCount() throws {
        XCTAssertEqual(FontRuleCopy.using("Noto Serif"), "Using Noto Serif")
        XCTAssertEqual(FontRuleCopy.using(nil), "Using default fonts")
        XCTAssertEqual(FontRuleCopy.defaultFonts, "Default fonts")
        XCTAssertEqual(FontRuleCopy.codePoints(1), "1 code point")
        XCTAssertEqual(FontRuleCopy.codePoints(112), "112 code points")
        XCTAssertEqual(FontRuleCopy.overridden(1), "Another rule takes priority for 1 code point.")
        XCTAssertEqual(FontRuleCopy.overridden(3), "Another rule takes priority for 3 code points.")
        XCTAssertEqual(FontRuleCopy.range(0x2190, 0x21FF), "U+2190–U+21FF")
        XCTAssertEqual(FontRuleCopy.source(.codePoint(0x41)), "Code point rule")
        XCTAssertEqual(FontRuleCopy.source(.range(first: 0x2190, last: 0x21FF)), "Range rule U+2190–U+21FF")
        XCTAssertEqual(FontRuleCopy.source(.block(try block("Runic"))), "Unicode block rule Runic")
        XCTAssertEqual(FontRuleCopy.supports(112, of: 112), "Supports 112 of 112 code points")
        XCTAssertEqual(FontRuleCopy.supports(3, of: 12, previewOnly: true), "Supports 3 of 12 preview characters")
        XCTAssertEqual(FontRuleCopy.showUnsupportedFonts(1), "Show 1 Unsupported Font")
        XCTAssertEqual(FontRuleCopy.showUnsupportedFonts(3), "Show 3 Unsupported Fonts")
        XCTAssertEqual(FontRuleCopy.duplicate(.codePoint), "A rule for this code point already exists.")
        XCTAssertEqual(FontRuleCopy.duplicate(.range), "A rule for this range already exists.")
        XCTAssertEqual(FontRuleCopy.duplicate(.block), "A rule for this block already exists.")
        XCTAssertEqual(FontRuleCopy.message(FontRuleInputError.invalid), "Enter a valid Unicode code point, such as U+0041.")
        XCTAssertEqual(FontRuleCopy.message(FontRuleInputError.surrogate), "Surrogate code points can’t be used here.")
        XCTAssertEqual(FontRuleCopy.message(FontRuleInputError.multipleScalars), "Enter one code point. This text contains more than one.")
        XCTAssertEqual(FontRuleCopy.message(FontRuleDraft.Problem.input(.surrogate)), "Surrogate code points can’t be used here.")
        XCTAssertEqual(FontRuleCopy.message(FontRuleDraft.Problem.reversed), "The end of the range must come after or equal the start.")
        XCTAssertEqual(FontRuleCopy.message(FontRuleDraft.Problem.unknownBlock), "This Unicode block isn’t recognized.")
        XCTAssertEqual(FontRuleCopy.ruleCount(0), "None")
        XCTAssertEqual(FontRuleCopy.ruleCount(2), "2")
        XCTAssertEqual(FontRuleCopy.unavailable, "Font unavailable")
        XCTAssertEqual(FontRuleCopy.cannotDisplay, "Font can’t display this text")
        XCTAssertEqual(FontRuleCopy.usingNextMatchingFont, "Using the next matching font.")
        XCTAssertEqual(FontRuleCopy.multipleFonts, "Multiple fonts used")
        XCTAssertEqual(FontRuleCopy.chooseFont, "Choose a font.")
    }

    // MARK: Draft

    func testCodePointDraftCountsScalarsAndNeverTakesTheFirst() {
        let blocks = UnicodeCatalog.shared.blocks
        var draft = FontRuleDraft(kind: .codePoint)
        XCTAssertNil(draft.selector(blocks: blocks), "Nothing typed yet is not an error")
        draft.codePoint = "U+16A0"
        XCTAssertEqual(draft.selector(blocks: blocks), .success(.codePoint(0x16A0)))
        draft.codePoint = "ᚠ"
        XCTAssertEqual(draft.selector(blocks: blocks), .success(.codePoint(0x16A0)))
        draft.codePoint = "e\u{301}"
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.input(.multipleScalars)), "One accented letter can be two code points")
        draft.codePoint = "U+D800"
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.input(.surrogate)))
        draft.codePoint = "U+110000"
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.input(.invalid)))
    }

    func testRangeDraftReportsEachEndpointAndReversal() {
        let blocks = UnicodeCatalog.shared.blocks
        var draft = FontRuleDraft(kind: .range)
        XCTAssertNil(draft.selector(blocks: blocks))
        draft.from = "U+2190"
        XCTAssertNil(draft.selector(blocks: blocks), "Only one endpoint so far")
        draft.to = "U+DFFF"
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.input(.surrogate)))
        draft.from = "zz"
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.input(.multipleScalars)))
        draft.from = "U+21FF"
        draft.to = "U+2190"
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.reversed))
        draft.from = "U+2190"
        draft.to = "U+21FF"
        XCTAssertEqual(draft.selector(blocks: blocks), .success(.range(first: 0x2190, last: 0x21FF)))
        draft.from = "U+D7FF"
        draft.to = "U+E000"
        XCTAssertEqual(draft.selector(blocks: blocks), .success(.range(first: 0xD7FF, last: 0xE000)),
                       "A range may cross the surrogates; only its endpoints are checked")
    }

    func testBlockDraftUsesOnlyTheBaseTable() throws {
        let blocks = UnicodeCatalog.shared.blocks
        var draft = FontRuleDraft(kind: .block)
        XCTAssertNil(draft.selector(blocks: blocks))
        let runic = try block("Runic")
        draft.block = runic
        XCTAssertEqual(draft.selector(blocks: blocks), .success(.block(runic)))
        draft.block = FontRuleBlock(name: "Runic", first: 0x16A0, last: 0x16AF, unicodeVersion: "1")
        XCTAssertEqual(draft.selector(blocks: blocks), .failure(.unknownBlock), "Bounds must match too")
    }

    func testEditingDraftRoundTripsEveryKindAndFindsDuplicates() throws {
        let blocks = UnicodeCatalog.shared.blocks
        let runic = try block("Runic")
        let rules = [
            FontRule(id: "a", selector: .codePoint(0x41), face: face("Papyrus")),
            FontRule(id: "r", selector: .range(first: 0x2190, last: 0x21FF), face: face("Papyrus")),
            FontRule(id: "b", selector: .block(runic), face: face("Chalkduster")),
        ]
        for rule in rules {
            let draft = FontRuleDraft(editing: rule)
            XCTAssertEqual(draft.kind, rule.selector.kind)
            XCTAssertEqual(draft.editingID, rule.id)
            XCTAssertEqual(draft.selector(blocks: blocks), .success(rule.selector))
            XCTAssertNil(draft.duplicate(of: rule.selector, in: rules), "A rule never duplicates itself")
            XCTAssertEqual(draft.rule(in: rules, blocks: blocks), rule)
        }
        XCTAssertEqual(FontRuleDraft(editing: rules[0]).codePoint, "U+0041")
        XCTAssertEqual(FontRuleDraft(editing: rules[1]).from, "U+2190")
        XCTAssertEqual(FontRuleDraft(editing: rules[1]).to, "U+21FF")
        XCTAssertEqual(FontRuleDraft(editing: rules[2]).block, runic)

        var adding = FontRuleDraft(kind: .range, face: face("Symbol"))
        adding.from = "U+2190"
        adding.to = "U+21FF"
        XCTAssertEqual(adding.duplicate(of: .range(first: 0x2190, last: 0x21FF), in: rules)?.id, "r")
        XCTAssertNil(adding.rule(in: rules, blocks: blocks), "A duplicate can't be saved")
        adding.to = "U+21FE"
        let added = try XCTUnwrap(adding.rule(in: rules, blocks: blocks, newID: "new"))
        XCTAssertEqual(added, FontRule(id: "new", selector: .range(first: 0x2190, last: 0x21FE), face: face("Symbol")))
        XCTAssertEqual(adding.applied(added, to: rules).map(\.id), ["a", "r", "b", "new"])
        adding.face = nil
        XCTAssertNil(adding.rule(in: rules, blocks: blocks), "A font must be chosen")

        var editing = FontRuleDraft(editing: rules[1])
        editing.face = face("Symbol")
        let edited = try XCTUnwrap(editing.rule(in: rules, blocks: blocks))
        XCTAssertEqual(editing.applied(edited, to: rules), [rules[0], edited, rules[2]], "Editing keeps the saved place")
    }

    // MARK: Try Text

    func testTryTextLimitsGraphemesNotScalars() {
        let family = "👩‍👩‍👧"
        XCTAssertEqual(FontRuleTryText.characters("→Ω" + family), ["→", "Ω", family])
        XCTAssertEqual(FontRuleTryText.trimmed(String(repeating: "a", count: 40)).count, 32)
        XCTAssertEqual(FontRuleTryText.characters(String(repeating: family, count: 33)).count, 32)
        XCTAssertTrue(FontRuleTryText.hasJoinedCharacters(["a", family]))
        XCTAssertFalse(FontRuleTryText.hasJoinedCharacters(["a", "b"]))
        XCTAssertTrue(FontRuleTryText.allSame([1, 1, 1]))
        XCTAssertTrue(FontRuleTryText.allSame([Int]()))
        XCTAssertFalse(FontRuleTryText.allSame([1, 2]))
    }

    // MARK: Ordering

    func testMovesStayWithinOneKindAndKeepOtherRulesInPlace() throws {
        let runic = try block("Runic")
        let rules = [
            FontRule(id: "r1", selector: .range(first: 0x2190, last: 0x21FF), face: face("A")),
            FontRule(id: "c1", selector: .codePoint(0x41), face: face("A")),
            FontRule(id: "r2", selector: .range(first: 0x2100, last: 0x214F), face: face("A")),
            FontRule(id: "b1", selector: .block(runic), face: face("A")),
            FontRule(id: "r3", selector: .range(first: 0x2200, last: 0x22FF), face: face("A")),
        ]
        XCTAssertEqual(FontRuleOrdering.indices(of: .range, in: rules), [0, 2, 4])
        XCTAssertEqual(FontRuleOrdering.moving(rules, kind: .range, from: [2], to: 0)?.map(\.id), ["r3", "c1", "r1", "b1", "r2"])
        XCTAssertEqual(FontRuleOrdering.moving(rules, kind: .range, from: [0], to: 3)?.map(\.id), ["r2", "c1", "r3", "b1", "r1"])
        XCTAssertEqual(FontRuleOrdering.moving(rules, kind: .range, from: [0, 1], to: 3)?.map(\.id), ["r3", "c1", "r1", "b1", "r2"])
        XCTAssertEqual(FontRuleOrdering.moving(rules, kind: .codePoint, from: [0], to: 1)?.map(\.id), rules.map(\.id))
        XCTAssertNil(FontRuleOrdering.moving(rules, kind: .range, from: [3], to: 0))
        XCTAssertNil(FontRuleOrdering.moving(rules, kind: .range, from: [0], to: 4))
        XCTAssertNil(FontRuleOrdering.moving(rules, kind: .range, from: [], to: 0))
    }

    func testCharacterPreferenceSetsAndClearsOnlyTheCodePointRule() throws {
        let runic = try block("Runic")
        let rules = [
            FontRule(id: "b", selector: .block(runic), face: face("Block")),
            FontRule(id: "a", selector: .codePoint(0x16A0), face: face("Old")),
        ]
        XCTAssertEqual(FontRuleOrdering.codePointRule(0x16A0, in: rules)?.id, "a")
        XCTAssertNil(FontRuleOrdering.codePointRule(0x16A1, in: rules))
        let changed = FontRuleOrdering.settingFace(face("New"), forCodePoint: 0x16A0, in: rules)
        XCTAssertEqual(changed.map(\.id), ["b", "a"])
        XCTAssertEqual(changed[1].face, face("New"))
        let added = FontRuleOrdering.settingFace(face("New"), forCodePoint: 0x16A1, in: rules, newID: "n")
        XCTAssertEqual(added.last, FontRule(id: "n", selector: .codePoint(0x16A1), face: face("New")))
        XCTAssertEqual(FontRuleOrdering.clearing(codePoint: 0x16A0, in: rules).map(\.id), ["b"], "The block rule and its font stay")
        XCTAssertTrue(FontRuleOrdering.sameTarget(.block(runic), .block(FontRuleBlock(name: "Runic", first: 0, last: 1, unicodeVersion: ""))))
        XCTAssertFalse(FontRuleOrdering.sameTarget(.codePoint(1), .codePoint(2)))
    }

    // MARK: Samples

    func testSampleShowsTheFaceOrDimmedSystemFallback() {
        let assigned: [UInt32] = [0x370, 0x371]
        XCTAssertEqual(FontRuleSample.resolve(hasFace: false, drawn: nil, assigned: assigned),
                       FontRuleSample(codePoints: assigned, inFace: false, dimmed: false), "No face yet: system rendering, not dimmed")
        XCTAssertEqual(FontRuleSample.resolve(hasFace: true, drawn: [0x374], assigned: assigned),
                       FontRuleSample(codePoints: [0x374], inFace: true, dimmed: false))
        XCTAssertEqual(FontRuleSample.resolve(hasFace: true, drawn: [], assigned: assigned),
                       FontRuleSample(codePoints: assigned, inFace: false, dimmed: true), "Draws none: dimmed fallback")
        XCTAssertEqual(FontRuleSample.resolve(hasFace: true, drawn: nil, assigned: assigned),
                       FontRuleSample(codePoints: assigned, inFace: false, dimmed: true), "Missing file: dimmed fallback")
        XCTAssertEqual(FontRuleSample.previewLimit, 12)
    }

    func testSampleCacheKeySeparatesFaceRangeLimitEditionAndRevision() {
        let base = FontRuleSample.cacheKey(face: face("A"), first: 0x370, last: 0x3FF, limit: 12, edition: "latest", revision: "1")
        XCTAssertEqual(base, FontRuleSample.cacheKey(face: face("A"), first: 0x370, last: 0x3FF, limit: 12, edition: "latest", revision: "1"))
        let others = [
            FontRuleSample.cacheKey(face: face("B"), first: 0x370, last: 0x3FF, limit: 12, edition: "latest", revision: "1"),
            FontRuleSample.cacheKey(face: face("A"), first: 0x371, last: 0x3FF, limit: 12, edition: "latest", revision: "1"),
            FontRuleSample.cacheKey(face: face("A"), first: 0x370, last: 0x3FE, limit: 12, edition: "latest", revision: "1"),
            FontRuleSample.cacheKey(face: face("A"), first: 0x370, last: 0x3FF, limit: 1, edition: "latest", revision: "1"),
            FontRuleSample.cacheKey(face: face("A"), first: 0x370, last: 0x3FF, limit: 12, edition: "draft", revision: "1"),
            FontRuleSample.cacheKey(face: face("A"), first: 0x370, last: 0x3FF, limit: 12, edition: "latest", revision: "2"),
        ]
        XCTAssertFalse(others.contains(base))
        XCTAssertEqual(Set(others).count, others.count)
    }

    func testGroupsOrderLettersNumbersSymbolsPunctuationOtherThenModifiers() {
        typealias Group = FontRuleSample.Group
        XCTAssertEqual(["Lu", "Ll", "Lt", "Lo"].map(Group.init(category:)), [.letter, .letter, .letter, .letter])
        XCTAssertEqual(Group(category: "Lm"), .modifier, "ʹ U+0374 is a modifier letter")
        XCTAssertEqual(["Nd", "Nl", "No"].map(Group.init(category:)), [.number, .number, .number])
        XCTAssertEqual(["Sm", "Sc", "So"].map(Group.init(category:)), [.symbol, .symbol, .symbol])
        XCTAssertEqual(Group(category: "Sk"), .modifier)
        XCTAssertEqual(["Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po"].map(Group.init(category:)), Array(repeating: .punctuation, count: 7))
        XCTAssertEqual(["Co", "Zs", "Cf", ""].map(Group.init(category:)), [.other, .other, .other, .other])
        XCTAssertEqual(["Mn", "Mc", "Me"].map(Group.init(category:)), [.modifier, .modifier, .modifier])
        XCTAssertEqual(Group.allCases, [.letter, .number, .symbol, .punctuation, .other, .modifier])
    }

    func testRepresentativeOrdersByGroupKeepingCodePointOrder() async {
        let rows = [UnicodeChartRow(start: 0x100, assigned: 0xFFFF)]
        let categories: [UInt32: String] = [
            0x100: "Mn", 0x101: "Lm", 0x102: "Po", 0x103: "Sm", 0x104: "Nd", 0x105: "Co",
            0x106: "Lu", 0x107: "Sk", 0x108: "Nd", 0x109: "Ll", 0x10A: "So", 0x10B: "Pd",
        ]
        let noCheck: () async -> Void = {}
        let all = await FontRuleSample.representative(rows: rows, columns: 32, limit: 12, category: { categories[$0] }, checkpoint: noCheck)
        XCTAssertEqual(all, [0x106, 0x109, 0x104, 0x108, 0x103, 0x10A, 0x102, 0x10B, 0x105, 0x100, 0x101, 0x107])
        let tile = await FontRuleSample.representative(rows: rows, columns: 32, limit: 1, category: { categories[$0] }, checkpoint: noCheck)
        XCTAssertEqual(tile, [0x106], "The tile is the first of the strip")
        let three = await FontRuleSample.representative(rows: rows, columns: 32, limit: 3, category: { categories[$0] }, checkpoint: noCheck)
        XCTAssertEqual(three, [0x106, 0x109, 0x104])
        let none = await FontRuleSample.representative(rows: rows, columns: 32, limit: 12, category: { _ in nil }, checkpoint: noCheck)
        XCTAssertEqual(none, [])
        let zero = await FontRuleSample.representative(rows: rows, columns: 32, limit: 0, category: { categories[$0] }, checkpoint: noCheck)
        XCTAssertEqual(zero, [])
        let narrow = await FontRuleSample.representative(rows: rows, columns: 2, limit: 12, category: { categories[$0] }, checkpoint: noCheck)
        XCTAssertEqual(narrow, [0x100, 0x101], "Only the given columns")
    }

    func testRepresentativeSkipsUnassignedColumnsCapsGroupsAndStopsOnceLettersAreFull() async {
        let rows = [UnicodeChartRow(start: 0x360, assigned: 0b1011), UnicodeChartRow(start: 0x380, assigned: UInt32.max)]
        let noCheck: () async -> Void = {}
        var asked: [UInt32] = []
        let symbolsThenLetters = await FontRuleSample.representative(rows: rows, columns: 32, limit: 2, category: { value in
            asked.append(value)
            return value < 0x390 ? "So" : "Lu"
        }, checkpoint: noCheck)
        XCTAssertEqual(symbolsThenLetters, [0x390, 0x391], "Later letters win over earlier symbols")
        XCTAssertEqual(asked.prefix(3), [0x360, 0x361, 0x363], "Unassigned columns are skipped")
        XCTAssertEqual(asked.last, 0x391, "Stops once the letters fill the limit")
        let symbols = await FontRuleSample.representative(rows: rows, columns: 32, limit: 2, category: { _ in "Sm" }, checkpoint: noCheck)
        XCTAssertEqual(symbols, [0x360, 0x361], "Symbols only: still samples, in code point order")
        var checkpoints = 0
        let counted = await FontRuleSample.representative(rows: rows, columns: 32, limit: 12, stride: 7, category: { _ in nil }) {
            checkpoints += 1
        }
        XCTAssertEqual(counted, [])
        XCTAssertEqual(checkpoints, 5, "35 assigned code points, a checkpoint every 7")
    }

    func testRepresentativeStopsWhenTheCheckpointThrows() async {
        let rows = [UnicodeChartRow(start: 0, assigned: UInt32.max)]
        do {
            _ = try await FontRuleSample.representative(rows: rows, columns: 32, limit: 12, stride: 4, category: { _ in nil }) {
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    /// The catalog's category for a code point a face draws, as `FontRangeCoverage` asks.
    private func category(_ catalog: UnicodeCatalog, draws: @escaping (UInt32) -> Bool) -> (UInt32) -> String? {
        { value in
            guard draws(value), let character = catalog.character(at: value), FontRuleSample.showsGlyph(character) else { return nil }
            return character.category
        }
    }

    func testGreekInRobotoStartsAtTonosLettersNotModifiers() async throws {
        let catalog = UnicodeCatalog.shared
        let greek = try XCTUnwrap(catalog.blocks.first { $0.name == "Greek and Coptic" })
        let rows = catalog.chartRows(in: greek, columns: 32)
        // Roboto's Greek: the modifiers ʹ ͵ ͺ, the question mark, tonos, then WGL4's letters.
        let roboto: Set<UInt32> = Set([0x374, 0x375, 0x37A, 0x37E, 0x384, 0x385, 0x386, 0x387, 0x388, 0x389, 0x38A, 0x38C])
            .union(0x38E...0x3A1).union(0x3A3...0x3CE)
        let noCheck: () async -> Void = {}
        let strip = await FontRuleSample.representative(rows: rows, columns: 32, limit: FontRuleSample.previewLimit,
                                                        category: category(catalog) { roboto.contains($0) }, checkpoint: noCheck)
        XCTAssertEqual(String(String.UnicodeScalarView(strip.compactMap(Unicode.Scalar.init))), "ΆΈΉΊΌΎΏΐΑΒΓΔ")
        let tile = await FontRuleSample.representative(rows: rows, columns: 32, limit: 1,
                                                       category: category(catalog) { roboto.contains($0) }, checkpoint: noCheck)
        XCTAssertEqual(tile, [0x386], "Ά")
        let everything = await FontRuleSample.representative(rows: rows, columns: 32, limit: 3,
                                                             category: category(catalog) { _ in true }, checkpoint: noCheck)
        XCTAssertEqual(everything, [0x370, 0x371, 0x372])
    }

    func testArrowsBlockStillHasSamples() async throws {
        let catalog = UnicodeCatalog.shared
        let arrows = try XCTUnwrap(catalog.blocks.first { $0.name == "Arrows" })
        let noCheck: () async -> Void = {}
        let strip = await FontRuleSample.representative(rows: catalog.chartRows(in: arrows, columns: 32), columns: 32,
                                                        limit: FontRuleSample.previewLimit, category: category(catalog) { _ in true },
                                                        checkpoint: noCheck)
        XCTAssertEqual(strip, Array(0x2190...0x219B), "Symbols come first when there are no letters")
    }

    func testOnlyCharactersWithTheirOwnGlyphCountAsDrawn() throws {
        let catalog = UnicodeCatalog.shared
        func shows(_ value: UInt32) throws -> Bool { FontRuleSample.showsGlyph(try XCTUnwrap(catalog.character(at: value))) }
        XCTAssertTrue(try shows(0x41))
        XCTAssertTrue(try shows(0x301), "A combining mark shows its glyph")
        XCTAssertTrue(try shows(0xE000), "Private use counts")
        XCTAssertFalse(try shows(0x20))
        XCTAssertFalse(try shows(0x0A))
        XCTAssertFalse(try shows(0x200D))
        XCTAssertFalse(try shows(0x378), "Unassigned")
        XCTAssertFalse(try shows(0x2028))
        XCTAssertFalse(try shows(0x2029))
        XCTAssertFalse(FontRuleSample.showsGlyph(UnicodeCharacter(codePoint: 0x41, name: "", detail: "", blockName: "", category: "Lu", isInvisible: true)))
        XCTAssertFalse(FontRuleSample.showsGlyph(UnicodeCharacter(codePoint: 0xD800, name: "", detail: "", blockName: "", category: "Cs")))
    }
}
