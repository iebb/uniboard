import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class FontRulesTests: XCTestCase {
    private static let hash = String(repeating: "ab", count: 32)

    private func face(_ name: String = "Junicode", hash: String = FontRulesTests.hash, index: Int = 0) -> FontFaceReference {
        FontFaceReference(source: .imported, family: name, style: "Regular", postScriptName: name + "-Regular",
                          identity: .file(sha256: hash, faceIndex: index, variations: [:]))
    }

    private func rule(_ selector: FontRuleSelector, _ id: String, face: FontFaceReference? = nil) -> FontRule {
        FontRule(id: id, selector: selector, face: face ?? self.face(id))
    }

    private func block(_ name: String) throws -> FontRuleBlock {
        try XCTUnwrap(FontRuleBlock(named: name))
    }

    private func ids(_ set: FontRuleSet, _ scalar: UInt32) -> [String] {
        set.candidates(for: scalar).map { set.rules[$0.ruleIndex].id }
    }

    // MARK: Scalars

    func testScalarValidityLabelsAndCounts() {
        XCTAssertTrue(FontRuleScalar.isValid(0))
        XCTAssertTrue(FontRuleScalar.isValid(0xD7FF))
        XCTAssertFalse(FontRuleScalar.isValid(0xD800))
        XCTAssertFalse(FontRuleScalar.isValid(0xDFFF))
        XCTAssertTrue(FontRuleScalar.isValid(0xE000))
        XCTAssertTrue(FontRuleScalar.isValid(0x10FFFF))
        XCTAssertFalse(FontRuleScalar.isValid(0x110000))
        XCTAssertEqual(FontRuleScalar.label(0x41), "U+0041")
        XCTAssertEqual(FontRuleScalar.label(0x1F600), "U+1F600")
        XCTAssertEqual(FontRuleScalar.label(0x10FFFF), "U+10FFFF")

        XCTAssertEqual(FontRuleScalar.validCount(0x41, 0x41), 1)
        XCTAssertEqual(FontRuleScalar.validCount(0x16A0, 0x16FF), 96)
        XCTAssertEqual(FontRuleScalar.validCount(0xD000, 0xE0FF), 0x1100 - 0x800)
        XCTAssertEqual(FontRuleScalar.validCount(0xD7FF, 0xE000), 2)
        XCTAssertEqual(FontRuleScalar.validCount(0xD800, 0xDFFF), 0)
        XCTAssertEqual(FontRuleScalar.validCount(0xDB00, 0xDBFF), 0)
        XCTAssertEqual(FontRuleScalar.validCount(0, 0x10FFFF), 0x110000 - 0x800)
        XCTAssertEqual(FontRuleScalar.validCount(0x10FFFE, 0x200000), 2)
        XCTAssertEqual(FontRuleScalar.validCount(0x110000, 0x120000), 0)
        XCTAssertEqual(FontRuleScalar.validCount(5, 4), 0)
    }

    func testScalarInputParsing() {
        XCTAssertEqual(FontRuleScalar.parse("U+0041"), .success(0x41))
        XCTAssertEqual(FontRuleScalar.parse("u+41"), .success(0x41))
        XCTAssertEqual(FontRuleScalar.parse("U+1"), .success(1))
        XCTAssertEqual(FontRuleScalar.parse("0041"), .success(0x41))
        XCTAssertEqual(FontRuleScalar.parse("  1F600\n"), .success(0x1F600))
        XCTAssertEqual(FontRuleScalar.parse("10FFFF"), .success(0x10FFFF))
        XCTAssertEqual(FontRuleScalar.parse("A"), .success(0x41))
        XCTAssertEqual(FontRuleScalar.parse("ᚠ"), .success(0x16A0))
        XCTAssertEqual(FontRuleScalar.parse(" "), .success(0x20), "a lone space is a pasted scalar")
        XCTAssertEqual(FontRuleScalar.parse(" ᚠ "), .success(0x16A0))
        XCTAssertEqual(FontRuleScalar.parse("\u{301}"), .success(0x301))

        XCTAssertEqual(FontRuleScalar.parse("U+D800"), .failure(.surrogate))
        XCTAssertEqual(FontRuleScalar.parse("DFFF"), .failure(.surrogate))
        XCTAssertEqual(FontRuleScalar.parse("110000"), .failure(.invalid))
        XCTAssertEqual(FontRuleScalar.parse("1234567"), .failure(.invalid))
        XCTAssertEqual(FontRuleScalar.parse("U+"), .failure(.invalid))
        XCTAssertEqual(FontRuleScalar.parse("U+12G"), .failure(.invalid))
        XCTAssertEqual(FontRuleScalar.parse(""), .failure(.invalid))
        XCTAssertEqual(FontRuleScalar.parse("ＡＢ"), .failure(.multipleScalars), "full-width letters aren't hex digits")
        XCTAssertEqual(FontRuleScalar.parse("Hello"), .failure(.multipleScalars))
        XCTAssertEqual(FontRuleScalar.parse("e\u{301}"), .failure(.multipleScalars), "one visible character, two scalars")
        XCTAssertEqual(FontRuleScalar.parse("👍🏽"), .failure(.multipleScalars))
    }

    // MARK: Blocks and selectors

    func testBlocksComeFromTheBaseTable() throws {
        let runic = try block("Runic")
        XCTAssertEqual(runic.first, 0x16A0)
        XCTAssertEqual(runic.last, 0x16FF)
        XCTAssertEqual(runic.unicodeVersion, UnicodeCatalog.shared.version)
        XCTAssertTrue(runic.isRecognized(in: UnicodeCatalog.shared.blocks))
        XCTAssertNil(FontRuleBlock(named: "Klingon"), "ConScript blocks are never rule targets")
        XCTAssertNil(FontRuleBlock(named: "runic"), "names match exactly")
        XCTAssertNotNil(FontRuleBlock(named: "Private Use Area"))

        let fixture = [UnicodeBlock(name: "Fixture", start: 0x10, end: 0x1F)]
        let custom = try XCTUnwrap(FontRuleBlock(named: "Fixture", in: fixture, unicodeVersion: "1.0"))
        XCTAssertEqual(custom, FontRuleBlock(name: "Fixture", first: 0x10, last: 0x1F, unicodeVersion: "1.0"))
        XCTAssertFalse(custom.isRecognized(in: UnicodeCatalog.shared.blocks))
        XCTAssertFalse(FontRuleBlock(name: "Runic", first: 0x16A0, last: 0x16FE, unicodeVersion: "17.0").isRecognized(in: UnicodeCatalog.shared.blocks))
        XCTAssertFalse(FontRuleBlock(name: "Runix", first: 0x16A0, last: 0x16FF, unicodeVersion: "17.0").isRecognized(in: UnicodeCatalog.shared.blocks))

        // The version is informational: it takes no part in identity.
        let older = FontRuleBlock(name: "Runic", first: 0x16A0, last: 0x16FF, unicodeVersion: "3.0")
        XCTAssertEqual(older, runic)
        XCTAssertEqual(Set([older, runic]).count, 1)
        XCTAssertNotEqual(older, FontRuleBlock(name: "Runic", first: 0x16A0, last: 0x16FE, unicodeVersion: "3.0"))
        XCTAssertNotEqual(older, FontRuleBlock(name: "Runic", first: 0x16A1, last: 0x16FF, unicodeVersion: "3.0"))
        XCTAssertTrue(older.isRecognized(in: UnicodeCatalog.shared.blocks))

        let data = try JSONEncoder().encode(older)
        XCTAssertEqual(try JSONDecoder().decode(FontRuleBlock.self, from: data).unicodeVersion, "3.0")
    }

    func testSelectorKindsBoundsAndShape() throws {
        let runic = try block("Runic")
        XCTAssertEqual(FontRuleSelector.codePoint(0x41).kind, .codePoint)
        XCTAssertEqual(FontRuleSelector.range(first: 1, last: 2).kind, .range)
        XCTAssertEqual(FontRuleSelector.block(runic).kind, .block)
        XCTAssertTrue(FontRuleSelector.codePoint(0x41).bounds == (0x41, 0x41))
        XCTAssertTrue(FontRuleSelector.range(first: 1, last: 2).bounds == (1, 2))
        XCTAssertTrue(FontRuleSelector.block(runic).bounds == (0x16A0, 0x16FF))
        XCTAssertEqual(FontRuleSelector.codePoint(0x41).validScalarCount, 1)
        XCTAssertEqual(FontRuleSelector.range(first: 0xD7F0, last: 0xE00F).validScalarCount, 32)
        XCTAssertEqual(FontRuleSelector.block(runic).validScalarCount, 96)

        XCTAssertTrue(FontRuleSelector.codePoint(0x10FFFF).isWellFormed)
        XCTAssertFalse(FontRuleSelector.codePoint(0xD800).isWellFormed)
        XCTAssertFalse(FontRuleSelector.codePoint(0x110000).isWellFormed)
        XCTAssertTrue(FontRuleSelector.range(first: 0xD7FF, last: 0xE000).isWellFormed)
        XCTAssertTrue(FontRuleSelector.range(first: 5, last: 5).isWellFormed)
        XCTAssertFalse(FontRuleSelector.range(first: 6, last: 5).isWellFormed)
        XCTAssertFalse(FontRuleSelector.range(first: 0xD800, last: 0xE000).isWellFormed)
        XCTAssertFalse(FontRuleSelector.range(first: 0, last: 0xDFFF).isWellFormed)
        XCTAssertFalse(FontRuleSelector.range(first: 0, last: 0x110000).isWellFormed)
        XCTAssertTrue(FontRuleSelector.block(runic).isWellFormed)
        XCTAssertFalse(FontRuleSelector.block(FontRuleBlock(name: "", first: 0, last: 1, unicodeVersion: "")).isWellFormed)
        XCTAssertFalse(FontRuleSelector.block(FontRuleBlock(name: "X", first: 2, last: 1, unicodeVersion: "")).isWellFormed)
        XCTAssertFalse(FontRuleSelector.block(FontRuleBlock(name: "X", first: 0, last: 0x110000, unicodeVersion: "")).isWellFormed)
        XCTAssertFalse(FontRuleSelector.block(try block("High Surrogates")).isWellFormed)

        let selectors: [FontRuleSelector] = [.codePoint(0x41), .range(first: 1, last: 9), .block(runic)]
        let data = try JSONEncoder().encode(selectors)
        XCTAssertEqual(try JSONDecoder().decode([FontRuleSelector].self, from: data), selectors)
    }

    // MARK: Face references

    func testFaceReferencesFromLibraryRecordsDropPaths() throws {
        let fileRecord = FontFaceRecord(id: FontFaceID(rawValue: "google:file-1:style-2"), family: "Noto Sans Runic", style: "Regular",
                                        postScriptName: "NotoSansRunic-Regular", source: .downloaded,
                                        locator: .file(relativePath: "Downloads/abc/NotoSansRunic.ttf", sha256: Self.hash, faceIndex: 2,
                                                       variations: ["2003265652": 700, "wdth": 87.5]),
                                        assetID: "abc")
        let reference = try XCTUnwrap(FontFaceReference(record: fileRecord))
        XCTAssertEqual(reference.identity, .file(sha256: Self.hash, faceIndex: 2, variations: ["wght": 700, "wdth": 87.5]))
        XCTAssertEqual(reference.source, .downloaded)
        XCTAssertEqual(reference.family, "Noto Sans Runic")
        XCTAssertEqual(reference.style, "Regular")
        XCTAssertEqual(reference.postScriptName, "NotoSansRunic-Regular")
        XCTAssertEqual(reference.googleFaceID, "google:file-1:style-2")
        XCTAssertEqual(reference.identityKey, "file:\(Self.hash):2:wdth=87.5,wght=700.0")
        XCTAssertFalse(String(describing: reference).contains("Downloads"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(reference), as: UTF8.self).contains("Downloads"))
        XCTAssertTrue(reference.matches(fileRecord))

        // A moved or renamed file is the same face; different bytes are not.
        let moved = FontFaceRecord(id: FontFaceID(rawValue: "imported:1"), family: "Renamed", style: "Book", postScriptName: "Other",
                                   source: .imported,
                                   locator: .file(relativePath: "Imported/x.ttf", sha256: Self.hash, faceIndex: 2, variations: ["wght": 700, "wdth": 87.5]),
                                   assetID: nil)
        XCTAssertTrue(reference.matches(moved))
        XCTAssertNil(try XCTUnwrap(FontFaceReference(record: moved)).googleFaceID)
        let otherBytes = FontFaceRecord(id: moved.id, family: moved.family, style: moved.style, postScriptName: moved.postScriptName, source: .imported,
                                        locator: .file(relativePath: "Imported/x.ttf", sha256: String(repeating: "cd", count: 32), faceIndex: 2,
                                                       variations: ["wght": 700, "wdth": 87.5]),
                                        assetID: nil)
        XCTAssertFalse(reference.matches(otherBytes))

        let processRecord = FontFaceRecord(id: FontFaceID(rawValue: "system:Menlo"), family: "Menlo", style: "Bold", postScriptName: "Menlo-Bold",
                                           source: .system, locator: .process(postScriptName: "Menlo-Bold", variations: [:]), assetID: nil)
        let process = try XCTUnwrap(FontFaceReference(record: processRecord))
        XCTAssertEqual(process.identity, .process(postScriptName: "Menlo-Bold", variations: [:]))
        XCTAssertEqual(process.identityKey, "ps:Menlo-Bold:")
        XCTAssertTrue(process.matches(processRecord))
        XCTAssertFalse(process.matches(fileRecord))
        XCTAssertFalse(reference.matches(processRecord))

        let decoded = try JSONDecoder().decode(FontFaceReference.self, from: JSONEncoder().encode(reference))
        XCTAssertEqual(decoded, reference)
    }

    func testFaceReferencesRejectUnportableRecords() {
        func record(_ locator: FontLocator, family: String = "Family") -> FontFaceRecord {
            FontFaceRecord(id: FontFaceID(rawValue: "x"), family: family, style: "Regular", postScriptName: "PS", source: .imported, locator: locator, assetID: nil)
        }
        // Axis identifier 1 has no printable tag.
        XCTAssertNil(FontFaceReference(record: record(.file(relativePath: "a", sha256: Self.hash, faceIndex: 0, variations: ["1": 1]))))
        XCTAssertNil(FontFaceReference(record: record(.process(postScriptName: "PS", variations: ["1": 1]))))
        XCTAssertNil(FontFaceReference(record: record(.process(postScriptName: "PS", variations: ["weight": 1]))))
        // Numeric and tagged forms of one axis must agree.
        XCTAssertNil(FontFaceReference(record: record(.process(postScriptName: "PS", variations: ["2003265652": 400, "wght": 700]))))
        XCTAssertNotNil(FontFaceReference(record: record(.process(postScriptName: "PS", variations: ["2003265652": 400, "wght": 400]))))
        XCTAssertNil(FontFaceReference(record: record(.process(postScriptName: "PS", variations: ["wght": .infinity]))))
        XCTAssertNil(FontFaceReference(record: record(.file(relativePath: "a", sha256: "ABCDEF", faceIndex: 0, variations: [:]))))
        XCTAssertNil(FontFaceReference(record: record(.process(postScriptName: "PS", variations: [:]), family: "")))

        XCTAssertEqual(FontFaceReference.tags(["2003265652": 1, "opsz": 12]), ["wght": 1, "opsz": 12])
        XCTAssertEqual(FontFaceReference.tags([:]), [:])
        XCTAssertNil(FontFaceReference.tags(["4294967295": 1]))
        XCTAssertNil(FontFaceReference.tags(["wght": .nan]))
    }

    func testFaceReferenceValidation() {
        XCTAssertTrue(face().isValid)
        XCTAssertTrue(face(index: 0xFFFF).isValid)
        XCTAssertFalse(face(index: 0x10000).isValid)
        XCTAssertFalse(face(index: -1).isValid)
        XCTAssertFalse(face(hash: String(repeating: "AB", count: 32)).isValid, "hashes are lowercase")
        XCTAssertFalse(face(hash: String(repeating: "a", count: 63)).isValid)
        XCTAssertFalse(face(hash: String(repeating: "g", count: 64)).isValid)
        XCTAssertTrue(face(hash: "0123456789abcdef" + String(repeating: "0", count: 48)).isValid)

        var reference = face()
        reference.family = ""
        XCTAssertFalse(reference.isValid)
        reference = face()
        reference.style = String(repeating: "x", count: 256)
        XCTAssertFalse(reference.isValid)
        reference.style = String(repeating: "x", count: 255)
        XCTAssertTrue(reference.isValid)
        reference.postScriptName = "Bad\u{0}Name"
        XCTAssertFalse(reference.isValid)
        reference.postScriptName = "Bad\u{85}Name"
        XCTAssertFalse(reference.isValid)
        reference.postScriptName = "Bad\u{7F}Name"
        XCTAssertFalse(reference.isValid)
        reference = face()
        reference.googleFaceID = "google:\n"
        XCTAssertFalse(reference.isValid)
        reference.googleFaceID = "google:a:b"
        XCTAssertTrue(reference.isValid)

        reference = face()
        reference.identity = .process(postScriptName: "", variations: [:])
        XCTAssertFalse(reference.isValid)
        reference.identity = .process(postScriptName: "Menlo-Regular", variations: ["wght": 400, "ital": 1])
        XCTAssertTrue(reference.isValid)
        reference.identity = .process(postScriptName: "Menlo-Regular", variations: ["wgh": 400])
        XCTAssertFalse(reference.isValid)
        reference.identity = .process(postScriptName: "Menlo-Regular", variations: ["wgh\u{1}": 400])
        XCTAssertFalse(reference.isValid)
        reference.identity = .process(postScriptName: "Menlo-Regular", variations: ["wght": .nan])
        XCTAssertFalse(reference.isValid)
        let many = Dictionary(uniqueKeysWithValues: (0..<65).map { (String(format: "a%03d", $0), Double($0)) })
        reference.identity = .process(postScriptName: "Menlo-Regular", variations: many)
        XCTAssertFalse(reference.isValid)
        reference.identity = .file(sha256: Self.hash, faceIndex: 0, variations: many.filter { $0.value < 64 })
        XCTAssertTrue(reference.isValid)
    }

    // MARK: Validation

    func testValidationReportsEveryProblemInRuleOrder() throws {
        let runic = try block("Runic")
        var badFace = face()
        badFace.family = ""
        let rules = [
            rule(.codePoint(0x41), "a"),
            rule(.codePoint(0x110000), "too big"),
            rule(.codePoint(0xDC00), "surrogate"),
            rule(.range(first: 0x30, last: 0x20), "reversed"),
            rule(.range(first: 0x20, last: 0x110000), "range too big"),
            rule(.range(first: 0xD800, last: 0xE000), "range from surrogate"),
            rule(.range(first: 0x20, last: 0xDFFF), "range to surrogate"),
            rule(.block(FontRuleBlock(name: "Klingon", first: 0xF8D0, last: 0xF8FF, unicodeVersion: "17.0")), "conscript"),
            rule(.block(try block("Low Surrogates")), "surrogate block"),
            rule(.codePoint(0x41), "duplicate"),
            rule(.range(first: 0x16A0, last: 0x16FF), "range like runic"),
            rule(.block(runic), "runic"),
            rule(.block(FontRuleBlock(name: "Runic", first: 0x16A0, last: 0x16FF, unicodeVersion: "5.0")), "runic again"),
            rule(.range(first: 0x16A0, last: 0x16FF), "range again"),
            rule(.range(first: 0xD7FF, last: 0xE000), "crossing", face: badFace),
        ]
        XCTAssertEqual(FontRuleValidator.validate(rules), [
            .invalidCodePoint(rule: 1),
            .surrogate(rule: 2),
            .reversedRange(rule: 3),
            .invalidCodePoint(rule: 4),
            .surrogate(rule: 5),
            .surrogate(rule: 6),
            .unknownBlock(rule: 7, name: "Klingon"),
            .surrogate(rule: 8),
            .duplicate(rule: 9, original: 0, kind: .codePoint),
            .duplicate(rule: 12, original: 11, kind: .block),
            .duplicate(rule: 13, original: 10, kind: .range),
            .invalidFace(rule: 14),
        ])
        XCTAssertEqual(FontRuleValidator.validate([]), [])
        XCTAssertEqual(FontRuleValidator.validate([rule(.block(runic), "r")]), [])
        XCTAssertEqual(FontRuleValidator.validate([rule(.block(runic), "r")], blocks: []), [.unknownBlock(rule: 0, name: "Runic")])
    }

    func testValidationEnforcesListLimits() {
        let shared = face()
        let codePoints = (0..<UInt32(FontRuleLimits.maximumRules)).map { rule(.codePoint(0x100 + $0), "c\($0)", face: shared) }
        XCTAssertEqual(FontRuleValidator.validate(codePoints), [])
        XCTAssertEqual(FontRuleValidator.validate(codePoints + [rule(.codePoint(0x41), "extra", face: shared)]),
                       [.tooManyRules(limit: 1024)])

        let ranges = (0..<UInt32(FontRuleLimits.maximumRangeRules)).map { rule(.range(first: $0 * 2, last: $0 * 2 + 1), "r\($0)", face: shared) }
        XCTAssertEqual(FontRuleValidator.validate(ranges), [])
        XCTAssertEqual(FontRuleValidator.validate(ranges + [rule(.range(first: 0x1000, last: 0x1001), "extra", face: shared)]),
                       [.tooManyRanges(limit: 256)])

        let faces = (0..<FontRuleLimits.maximumFaces).map { rule(.codePoint(0x100 + UInt32($0)), "f\($0)", face: face("F", index: $0)) }
        XCTAssertEqual(FontRuleValidator.validate(faces), [])
        // Display names don't make a face distinct; identity does.
        var renamed = face("Renamed", index: 0)
        renamed.style = "Other"
        XCTAssertEqual(FontRuleValidator.validate(faces + [rule(.codePoint(0x41), "same", face: renamed)]), [])
        XCTAssertEqual(FontRuleValidator.validate(faces + [rule(.codePoint(0x41), "new", face: face("F", index: 999))]),
                       [.tooManyFaces(limit: 256)])
    }

    // MARK: Resolution

    func testResolutionOrderIsExactThenSmallestRangeThenBlock() throws {
        let rules = [
            rule(.block(try block("Runic")), "block"),
            rule(.range(first: 0x16A0, last: 0x16AF), "wide"),
            rule(.range(first: 0x16A0, last: 0x16A3), "narrow"),
            rule(.codePoint(0x16A0), "exact"),
            rule(.range(first: 0x1600, last: 0x16FF), "widest"),
        ]
        let set = FontRuleSet(rules: rules)
        XCTAssertFalse(set.isEmpty)
        XCTAssertEqual(ids(set, 0x16A0), ["exact", "narrow", "wide", "widest", "block"])
        XCTAssertEqual(ids(set, 0x16A1), ["narrow", "wide", "widest", "block"])
        XCTAssertEqual(ids(set, 0x16A4), ["wide", "widest", "block"])
        XCTAssertEqual(ids(set, 0x16B0), ["widest", "block"])
        XCTAssertEqual(ids(set, 0x16FF), ["widest", "block"])
        XCTAssertEqual(ids(set, 0x1650), ["widest"])
        XCTAssertEqual(ids(set, 0x15FF), [])
        XCTAssertEqual(ids(set, 0x1700), [])
        XCTAssertEqual(ids(set, 0), [])
        XCTAssertEqual(ids(set, 0x10FFFF), [])
        XCTAssertEqual(set.candidates(for: 0x16A0).map(\.kind), [.codePoint, .range, .range, .range, .block])
        XCTAssertEqual(set.candidates(for: 0x16A0).first, FontRuleMatch(ruleIndex: 3, kind: .codePoint))
        XCTAssertEqual(set.candidates(for: 0xD800), [])
        XCTAssertEqual(set.candidates(for: 0x110000), [])
    }

    /// Ato msg408: a range always beats a block, however narrow the block;
    /// narrowest-wins (in valid scalars) applies only among ranges.
    func testARangeBeatsANarrowerBlock() throws {
        let runic = try block("Runic")                                    // 96 scalars
        let rules = [
            rule(.block(runic), "block"),
            rule(.range(first: 0x1600, last: 0x17FF), "wider range"),      // 512 scalars, saved after the block
            rule(.range(first: 0xD000, last: 0xE0FF), "surrogate span"),   // 2,304 scalars
            rule(.block(try block("Hangul Jamo Extended-B")), "jamo"),    // D7B0–D7FF: 80 scalars
        ]
        XCTAssertLessThan(rules[0].selector.validScalarCount, rules[1].selector.validScalarCount)
        XCTAssertLessThan(rules[3].selector.validScalarCount, rules[2].selector.validScalarCount)
        for order in [rules, rules.reversed()] {
            let set = FontRuleSet(rules: order)
            XCTAssertEqual(ids(set, 0x16A0), ["wider range", "block"])
            XCTAssertEqual(ids(set, 0x16FF), ["wider range", "block"])
            XCTAssertEqual(ids(set, 0x1650), ["wider range"])
            XCTAssertEqual(ids(set, 0xD7B0), ["surrogate span", "jamo"])
            let block = order.firstIndex { $0.id == "block" }!, range = order.firstIndex { $0.id == "wider range" }!
            XCTAssertEqual(set.overriddenScalarCount(for: block), 96, "the whole block is taken by the range")
            XCTAssertEqual(set.overriddenScalarCount(for: range), 0, "a block never takes priority over a range")
            let jamo = order.firstIndex { $0.id == "jamo" }!, span = order.firstIndex { $0.id == "surrogate span" }!
            XCTAssertEqual(set.overriddenScalarCount(for: jamo), 80)
            XCTAssertEqual(set.overriddenScalarCount(for: span), 0)
        }
    }

    func testEqualSpansPreferTheLaterRuleAndSpansSkipSurrogates() {
        let rules = [
            rule(.range(first: 0x10, last: 0x1F), "first"),
            rule(.range(first: 0x18, last: 0x27), "second"),
            // 0xD7F8…0xE007 holds 16 valid scalars, like the two ranges above,
            // even though it spans 2,064 code points.
            rule(.range(first: 0xD7F8, last: 0xE007), "crossing"),
            rule(.range(first: 0xD700, last: 0xE0FF), "crossing wide"),
            rule(.range(first: 0x20, last: 0x2F), "third"),
        ]
        let set = FontRuleSet(rules: rules)
        XCTAssertEqual(ids(set, 0x17), ["first"])
        XCTAssertEqual(ids(set, 0x18), ["second", "first"])
        XCTAssertEqual(ids(set, 0x20), ["third", "second"])
        XCTAssertEqual(ids(set, 0x2F), ["third"])
        XCTAssertEqual(ids(set, 0xD7FF), ["crossing", "crossing wide"])
        XCTAssertEqual(ids(set, 0xE000), ["crossing", "crossing wide"])
        XCTAssertEqual(ids(set, 0xD800), [])
        XCTAssertEqual(ids(set, 0xD700), ["crossing wide"])

        let reversed = FontRuleSet(rules: [rules[1], rules[0]])
        XCTAssertEqual(ids(reversed, 0x18), ["first", "second"], "saved order breaks the tie")
    }

    func testMalformedRulesAreSkippedAndEdgesResolve() throws {
        let rules = [
            rule(.codePoint(0xD800), "surrogate"),
            rule(.codePoint(0x110000), "too big"),
            rule(.range(first: 9, last: 2), "reversed"),
            rule(.block(try block("High Surrogates")), "surrogate block"),
            rule(.range(first: 0x10FFF0, last: 0x10FFFF), "top"),
            rule(.range(first: 0, last: 0), "bottom"),
            rule(.codePoint(0x10FFFF), "last"),
            rule(.block(try block("Supplementary Private Use Area-B")), "pua-b"),
        ]
        let set = FontRuleSet(rules: rules)
        XCTAssertEqual(ids(set, 0), ["bottom"])
        XCTAssertEqual(ids(set, 1), [])
        XCTAssertEqual(ids(set, 5), [])
        XCTAssertEqual(ids(set, 0x10FFFF), ["last", "top", "pua-b"])
        XCTAssertEqual(ids(set, 0x10FFEF), ["pua-b"])
        XCTAssertEqual(ids(set, 0x100000), ["pua-b"])
        XCTAssertEqual(ids(set, 0xFFFFF), [])

        XCTAssertTrue(FontRuleSet.empty.isEmpty)
        XCTAssertEqual(FontRuleSet.empty.candidates(for: 0x41), [])
        XCTAssertEqual(FontRuleSet.empty.candidates(forCluster: "A"), [])
        XCTAssertFalse(FontRuleSet(rules: [rules[0]]).isEmpty, "isEmpty reflects the saved list, not usable rules")
    }

    func testLargeRuleSetsResolveLikeALinearScan() {
        var rules: [FontRule] = []
        var seed: UInt32 = 12345
        func next(_ bound: UInt32) -> UInt32 {
            seed = seed &* 1_103_515_245 &+ 12345
            return (seed >> 8) % bound
        }
        for index in 0..<200 {
            let first = next(0x3000)
            let last = first + next(0x400)
            rules.append(rule(.range(first: first, last: last), "r\(index)"))
        }
        for index in 0..<300 { rules.append(rule(.codePoint(next(0x3400)), "c\(index)")) }
        let set = FontRuleSet(rules: rules)
        for scalar in stride(from: UInt32(0), to: 0x3500, by: 7) {
            var expected: [Int] = []
            if let exact = rules.lastIndex(where: { $0.selector == .codePoint(scalar) }) { expected.append(exact) }
            let containing = rules.indices.filter {
                guard case let .range(first, last) = rules[$0].selector else { return false }
                return first <= scalar && scalar <= last
            }
            expected += containing.sorted {
                let a = rules[$0].selector.validScalarCount
                let b = rules[$1].selector.validScalarCount
                return a != b ? a < b : $0 > $1
            }
            XCTAssertEqual(set.candidates(for: scalar).map(\.ruleIndex), expected, "U+\(String(scalar, radix: 16))")
        }
    }

    func testOverriddenScalarCounts() throws {
        let rules = [
            rule(.block(try block("Runic")), "block"),                     // 0: 96 scalars
            rule(.range(first: 0x16A0, last: 0x16AF), "wide"),              // 1: 16
            rule(.range(first: 0x16A8, last: 0x16B3), "narrow"),            // 2: 12
            rule(.codePoint(0x16A0), "exact"),                              // 3
            rule(.codePoint(0x16A9), "exact in narrow"),                    // 4
            rule(.range(first: 0xD7F0, last: 0xE00F), "crossing"),          // 5: 32
            rule(.range(first: 0xD7FE, last: 0xE001), "inside crossing"),   // 6: 4
            rule(.codePoint(0xD800), "malformed"),                          // 7
        ]
        let set = FontRuleSet(rules: rules)
        // Block: exact 0x16A0 and 0x16A9, plus wide 16A0–16AF and narrow 16A8–16B3 → 16A0–16B3 = 20.
        XCTAssertEqual(set.overriddenScalarCount(for: 0), 20)
        // Wide: exact 16A0, 16A9 and narrow 16A8–16AF → 1 + 8 = 9.
        XCTAssertEqual(set.overriddenScalarCount(for: 1), 9)
        // Narrow: only exact 16A9.
        XCTAssertEqual(set.overriddenScalarCount(for: 2), 1)
        XCTAssertEqual(set.overriddenScalarCount(for: 3), 0)
        XCTAssertEqual(set.overriddenScalarCount(for: 5), 4, "surrogates never count")
        XCTAssertEqual(set.overriddenScalarCount(for: 6), 0)
        XCTAssertEqual(set.overriddenScalarCount(for: 7), 0)
        XCTAssertEqual(set.overriddenScalarCount(for: -1), 0)
        XCTAssertEqual(set.overriddenScalarCount(for: 8), 0)

        let tie = FontRuleSet(rules: [rule(.range(first: 0, last: 9), "a"), rule(.range(first: 5, last: 14), "b")])
        XCTAssertEqual(tie.overriddenScalarCount(for: 0), 5)
        XCTAssertEqual(tie.overriddenScalarCount(for: 1), 0)
    }

    // MARK: Grapheme anchors

    func testClusterAnchors() {
        XCTAssertEqual(FontRuleSet.anchor(of: "e\u{301}"), 0x65)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{301}"), 0x301, "a mark with no base anchors itself")
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{301}\u{302}"), 0x301)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{301}a"), 0x61)
        XCTAssertEqual(FontRuleSet.anchor(of: "👩\u{200D}💻"), 0x1F469)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{200D}💻"), 0x1F4BB)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{200C}"), 0x200C)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{FE0F}❤"), 0x2764)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{E0100}字"), 0x5B57)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{180B}ᠠ"), 0x1820)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{180F}ᠠ"), 0x1820)
        XCTAssertEqual(FontRuleSet.anchor(of: "👍🏽"), 0x1F44D)
        XCTAssertEqual(FontRuleSet.anchor(of: "🏽"), 0x1F3FD, "skin tone modifiers aren't marks")
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{20DD}"), 0x20DD)
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{93F}क"), 0x915, "Mc is transparent")
        XCTAssertEqual(FontRuleSet.anchor(of: "\u{20E3}1"), 0x31, "Me is transparent")
        XCTAssertNil(FontRuleSet.anchor(of: ""))
        XCTAssertEqual(FontRuleSet.anchor(of: "ab"[...]), 0x61)

        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{301}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{93F}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{20DD}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{200D}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{200C}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{FE00}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{FE0F}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{E01EF}"))
        XCTAssertTrue(FontRuleSet.isAnchorTransparent("\u{180D}"))
        XCTAssertFalse(FontRuleSet.isAnchorTransparent("\u{180E}"))
        XCTAssertFalse(FontRuleSet.isAnchorTransparent("\u{200B}"))
        XCTAssertFalse(FontRuleSet.isAnchorTransparent("\u{E01F0}"))
        XCTAssertFalse(FontRuleSet.isAnchorTransparent("a"))
    }

    func testClusterCandidatesFollowTheAnchor() {
        let set = FontRuleSet(rules: [
            rule(.codePoint(0x65), "e"),
            rule(.codePoint(0x301), "acute"),
            rule(.codePoint(0x1F469), "woman"),
            rule(.codePoint(0x1F4BB), "laptop"),
        ])
        func clusterIDs(_ cluster: String) -> [String] { set.candidates(forCluster: cluster).map { set.rules[$0.ruleIndex].id } }
        XCTAssertEqual(clusterIDs("e\u{301}"), ["e"])
        XCTAssertEqual(clusterIDs("\u{301}"), ["acute"])
        XCTAssertEqual(clusterIDs("👩\u{200D}💻"), ["woman"])
        XCTAssertEqual(clusterIDs("x"), [])
        XCTAssertEqual(clusterIDs(""), [])
    }

    func testRuleDefaults() {
        let first = FontRule(selector: .codePoint(0x41), face: face())
        let second = FontRule(selector: .codePoint(0x41), face: face())
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(first.id.isEmpty)
        XCTAssertEqual(FontRuleLimits.maximumRules, 1024)
        XCTAssertEqual(FontRuleLimits.maximumRangeRules, 256)
        XCTAssertEqual(FontRuleLimits.maximumFaces, 256)
    }
}
