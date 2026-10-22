import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UnicodeCatalogTests: XCTestCase {
    private let catalog = UnicodeCatalog.shared

    /// Tiny independent wire-format fixture: its coverage and malformed offsets
    /// do not depend on the production generator or bundled Unicode contents.
    private func fixture(records: [UInt32] = [0x41, 0x42],
                         ranges: [(UInt32, UInt32, UInt8)] = [],
                         details: [UInt32: String] = [:], names: [UInt32: String] = [:],
                         searches: [UInt32: String] = [:], contexts: [UInt32: String] = [:],
                         contextDetails: [UInt32: String] = [:],
                         versionLabel: String = "18.0.0") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var pool = Data()
        func string(_ value: String) -> (UInt32, UInt32) {
            let offset = UInt32(pool.count), data = Data(value.utf8)
            pool.append(data)
            return (offset, UInt32(data.count))
        }
        func append(_ value: UInt32, to data: inout Data) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func short(_ value: UInt32, to data: inout Data) {
            var little = UInt16(value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let version = string(versionLabel)
        var rows = Data(), rangeRows = Data()
        for cp in records {
            let label = names[cp] ?? String(format: "FIXTURE LETTER %04X", cp)
            let name = string(label)
            let detail = string(details[cp] ?? ""), search = string(searches[cp] ?? label.lowercased())
            let contextSearch = string(contexts[cp] ?? "")
            let context = string(contextDetails[cp] ?? "")
            append(cp, to: &rows); append(name.0, to: &rows)
            short(name.1, to: &rows); short(detail.1, to: &rows)
            append(detail.0, to: &rows); append(search.0, to: &rows); append(search.1, to: &rows)
            rows.append(contentsOf: [0, 0, 0, 0])
            for value: UInt32 in [context.0, context.1, contextSearch.0, contextSearch.1] { append(value, to: &rows) }
        }
        for (start, end, kind) in ranges {
            let prefix = string(kind == 1 ? "HANGUL SYLLABLE " : "FIXTURE IDEOGRAPH-")
            append(start, to: &rangeRows); append(end, to: &rangeRows); append(prefix.0, to: &rangeRows)
            short(prefix.1, to: &rangeRows); rangeRows.append(contentsOf: [4, kind])
        }
        var data = Data("UBOARD17".utf8)
        let rangeOffset = 48 + rows.count, poolOffset = rangeOffset + rangeRows.count
        for value: UInt32 in [UInt32(records.count), 48, UInt32(ranges.count), UInt32(rangeOffset), UInt32(poolOffset), UInt32(pool.count), version.0, version.1, 0, 3] {
            append(value, to: &data)
        }
        data.append(rows); data.append(rangeRows); data.append(pool)
        try data.write(to: directory.appendingPathComponent("UnicodeCatalog.ucd"))
        let blocks: [[String: Any]] = [["name": "Fixture", "start": 0, "end": 0x10FFFF]]
        try JSONSerialization.data(withJSONObject: blocks).write(to: directory.appendingPathComponent("Blocks.json"))
        let spans = (records.map { ($0, $0) } + ranges.map { ($0.0, $0.1) }).sorted { $0.0 < $1.0 }
        let properties: [String: Any] = ["unicodeVersion": versionLabel, "ages": [["start": 0, "end": 0x10FFFF, "value": "1.1"]],
            "scripts": [["start": 0, "end": 0x10FFFF, "value": "Latin"]], "decompositions": [],
            "assignedSpans": spans.map { ["start": $0.0, "end": $0.1, "sortKey": 101, "draftAddition": false] as [String: Any] }]
        try JSONSerialization.data(withJSONObject: properties).write(to: directory.appendingPathComponent("UnicodeProperties.json"))
        return directory
    }

    /// Fixed NamesList-style data exercises prose and alias semantics without
    /// requiring the rolling upstream draft to keep any informative wording.
    private func pinnedNamesListCatalog(includeYangqin: Bool = true) throws -> UnicodeCatalog {
        func json(_ object: [String: Any]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        var names: [UInt32: String] = [
            0x212E: "ESTIMATED SYMBOL", 0x2603: "SNOWMAN", 0x301C: "WAVE DASH",
            0x301D: "REVERSED DOUBLE PRIME QUOTATION MARK", 0x302A: "IDEOGRAPHIC LEVEL TONE MARK",
            0x3038: "HANGZHOU NUMERAL TEN", 0x3039: "HANGZHOU NUMERAL TWENTY", 0x303A: "HANGZHOU NUMERAL THIRTY",
            0xFE18: "PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRAKCET",
            0xFEFF: "ZERO WIDTH NO-BREAK SPACE"]
        var details: [UInt32: String] = [
            0x212E: try json(["annotations": ["European packaging"]]),
            0x2603: try json(["aliases": [["name": "snowy weather", "kind": "informal"]]]),
            0x301C: try json(["annotations": ["This character matches JIS C 6226."],
                             "references": [["codePoint": 0x3030, "name": "WAVY DASH"]]]),
            0xFE18: try json(["aliases": [["name": "PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRACKET", "kind": "correction"]],
                             "annotations": ["The name contains a misspelling."]]),
            0xFEFF: try json(["aliases": [["name": "BOM", "kind": "abbreviation"]]])]
        var searches: [UInt32: String] = [
            0x212E: "estimated symbol european packaging", 0x2603: "snowman snowy weather",
            0xFE18: "presentation form for vertical right white lenticular brakcet presentation form for vertical right white lenticular bracket",
            0xFEFF: "zero width no break space bom"]
        var contexts: [UInt32: String] = [:], contextDetails: [UInt32: String] = [:]
        let numeralNames = ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE"]
        for (index, name) in numeralNames.enumerated() {
            let cp = UInt32(0x3021 + index)
            names[cp] = "HANGZHOU NUMERAL " + name
            var metadata: [String: Any] = ["numericType": "Numeric", "numericValue": String(index + 1)]
            if cp == 0x3026 && includeYangqin {
                metadata["aliases"] = [["name": "yangqin sign slow one half beat", "kind": "informal"]]
                metadata["references"] = [["codePoint": 0x16FF4, "name": "YANGQIN SIGN SLOW ONE HALF BEAT"]]
                searches[cp] = "hangzhou numeral six yangqin sign slow one half beat"
            }
            details[cp] = try json(metadata)
            contexts[cp] = "suzhou numerals the use of hangzhou in the names is a misnomer"
            contextDetails[cp] = try json(["section": "Suzhou numerals",
                "sectionAnnotations": ["The use of HANGZHOU in the names is a misnomer."]])
        }
        for cp: UInt32 in [0x3038, 0x3039, 0x303A] {
            contexts[cp] = "additional suzhou numerals"
            contextDetails[cp] = try json(["section": "Additional Suzhou numerals"])
        }
        return UnicodeCatalog(resourceURL: try fixture(records: names.keys.sorted(), details: details, names: names,
            searches: searches, contexts: contexts, contextDetails: contextDetails,
            versionLabel: includeYangqin ? "17.0.0" : "16.0.0"))
    }

    private func changeProperties(at directory: URL, _ change: (inout [String: Any]) -> Void) throws {
        let url = directory.appendingPathComponent("UnicodeProperties.json")
        var properties = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        change(&properties)
        try JSONSerialization.data(withJSONObject: properties).write(to: url)
    }

    func testEditionAndOrderingLabelsRetainStableIdentifiers() {
        XCTAssertEqual(UnicodeEdition.versionLabel(for: .latest, metadata: [:]), "Unavailable")
        XCTAssertEqual(UnicodeEdition.versionLabel(for: .older, metadata: [.latest: "18.0.0"]), "Unavailable")
        XCTAssertEqual(UnicodeEdition.versionLabel(for: .previous, metadata: [.previous: "17.0.0"]), "17.0.0")
        for edition in UnicodeEdition.allCases {
            XCTAssertEqual(edition.id, edition.rawValue)
            XCTAssertTrue(edition.title.hasPrefix("Unicode "))
            XCTAssertTrue(edition.title.contains(edition.versionLabel.split(separator: ".").first.map(String.init) ?? ""))
            XCTAssertEqual(edition.title.hasSuffix(" Draft"), edition == .draft)
        }
        for (order, title): (UnicodeSortOrder, String) in [
            (.newestFirst, "Newest first"), (.oldestFirst, "Oldest first"), (.codePoint, "Code point")
        ] {
            XCTAssertEqual(order.id, order.rawValue)
            XCTAssertEqual(order.title, title)
        }
    }

    func testAliasAndRelatedCharacterLabelsKeepTheirSourceAndFormalStatus() {
        for (kind, label, source, formal): (String, String, String, Bool) in [
            ("correction", "Formal correction", "NameAliases.txt", true),
            ("control", "Control name", "NameAliases.txt", true),
            ("alternate", "Formal alternate", "NameAliases.txt", true),
            ("figment", "Formal figment", "NameAliases.txt", true),
            ("abbreviation", "Formal abbreviation", "NameAliases.txt", true),
            ("namesListFormal", "Names list formal alias", "NamesList.txt", true),
            ("informal", "Informative alias", "NamesList.txt", false),
            ("future-kind", "Informative alias", "Unknown", false)
        ] {
            let alias = UnicodeNameAlias(name: "Fixture alias", kind: kind)
            XCTAssertEqual(alias.id, kind + ":Fixture alias")
            XCTAssertEqual(alias.kindLabel, label)
            XCTAssertEqual(alias.source, source)
            XCTAssertEqual(alias.isFormal, formal)
        }
        let reference = UnicodeCrossReference(codePoint: 0x1F680, name: "ROCKET")
        XCTAssertEqual(reference.id, 0x1F680)
        XCTAssertEqual(reference.codePointLabel, "U+1F680")
    }

    func testPresentationPlaceholdersNeverReplaceTheUnderlyingScalar() {
        let cases: [(UInt32, String, Bool, String)] = [
            (0x20, "Zs", true, "␣"), (0x09, "Cc", true, "⇥"),
            (0x0A, "Cc", true, "↵"), (0x0D, "Cc", true, "↵"),
            (0x2028, "Zl", true, "↵"), (0x2029, "Zp", true, "↵"),
            (0, "Cc", true, "◌"), (0x0301, "Mn", false, "◌\u{301}"),
            (0x0378, "Cn", false, "◇"), (0x41, "Lu", false, "A")
        ]
        for (point, category, invisible, display) in cases {
            let character = UnicodeCharacter(codePoint: point, name: "Fixture", detail: "", blockName: "Fixture",
                                             category: category, isInvisible: invisible)
            XCTAssertEqual(character.id, point)
            XCTAssertEqual(character.displayText, display)
            XCTAssertEqual(character.text.unicodeScalars.map(\.value), [point])
            XCTAssertEqual(character.isInvisible, invisible)
        }
        let letter = UnicodeCharacter(codePoint: 0x41, name: "A", detail: "", blockName: "Fixture", category: "Lu")
        XCTAssertEqual(letter.categoryName, "Uppercase letter")
        let invalid = UnicodeCharacter(codePoint: 0xD800, name: "Invalid", detail: "", blockName: "Fixture", category: "Future")
        XCTAssertEqual(invalid.text, "")
        XCTAssertEqual(invalid.categoryName, "Future")
    }

    func testCharactersWithTextAndEmojiFormsChartAsTextAndOfferBoth() throws {
        let snowman = try XCTUnwrap(catalog.character(at: 0x2603))
        XCTAssertTrue(snowman.hasPresentationForms)
        XCTAssertEqual(snowman.presentationForms?.text.unicodeScalars.map(\.value), [0x2603, 0xFE0E])
        XCTAssertEqual(snowman.presentationForms?.emoji.unicodeScalars.map(\.value), [0x2603, 0xFE0F])
        XCTAssertEqual(snowman.displayText, "\u{2603}\u{FE0E}", "Charts show the text form")
        XCTAssertEqual(snowman.text, "\u{2603}", "Copy and insertion keep the original scalar")
        XCTAssertNotNil(catalog.character(at: 0x231A)?.presentationForms, "Emoji-default ⌚ also has a text form")
        for point: UInt32 in [0x41, 0x1F600, 0x221E, 0x10FFFF] {
            XCTAssertNil(catalog.character(at: point)?.presentationForms, String(format: "%04X", point))
        }
        // Each pair is listed once, sorted; anything else rejects the properties.
        for invalid: [Any] in [[0x2603, 0x23], [0x23, 0x23], [0xD800]] {
            let directory = try fixture()
            try changeProperties(at: directory) { $0["presentationSequences"] = invalid }
            XCTAssertNotNil(UnicodeCatalog(resourceURL: directory).resourceError, "\(invalid)")
        }
        let directory = try fixture()
        try changeProperties(at: directory) { $0["presentationSequences"] = [0x41] }
        let custom = UnicodeCatalog(resourceURL: directory)
        XCTAssertEqual(custom.character(at: 0x41)?.displayText, "A\u{FE0E}")
        XCTAssertNil(custom.character(at: 0x42)?.presentationForms)
        XCTAssertNil(try XCTUnwrap(UnicodeCatalog(resourceURL: try fixture()).character(at: 0x41)).presentationForms,
                     "Properties from before presentation forms have none")
    }

    func testConScriptViewNamesRegistryCharactersAndSplitsPrivateUse() throws {
        let plain = UnicodeCatalog.latest
        let conscript = plain.withConScript()
        XCTAssertTrue(conscript === plain.withConScript(), "The view is made once")
        XCTAssertTrue(conscript.withConScript() === conscript)
        XCTAssertFalse(plain.usesConScript); XCTAssertTrue(conscript.usesConScript)
        XCTAssertEqual(plain.character(at: 0xE000)?.name, "PRIVATE USE-E000")
        let tinco = try XCTUnwrap(conscript.character(at: 0xE000))
        XCTAssertEqual(tinco.name, "TENGWAR LETTER TINCO")
        XCTAssertEqual(tinco.blockName, "Tengwar")
        XCTAssertEqual(tinco.categoryName, "Letter")
        XCTAssertEqual(conscript.character(at: 0xEBE0)?.name, "PRIVATE USE-EBE0", "A reassigned code point keeps its Unicode name")
        let rest = try XCTUnwrap(conscript.blocks.first { $0.name == "Private Use Area" })
        XCTAssertNil(UCSUR.block(containing: rest.start))
        let klingonBlock = try XCTUnwrap(conscript.blocks.first { $0.name == "Klingon" })
        XCTAssertEqual(klingonBlock.curatedSymbol, "\u{F8D0}")
        XCTAssertFalse(plain.blocks.contains { $0.name == "Klingon" })
        XCTAssertEqual(conscript.search("tengwar letter tinco").first?.codePoint, 0xE000)
        XCTAssertTrue(plain.search("tengwar letter tinco").isEmpty)
        XCTAssertEqual(conscript.search("suule").first?.codePoint, 0xE008, "Aliases are searchable")
        let klingon = conscript.search("klingon", limit: 1000)
        XCTAssertEqual(Set(klingon.map(\.codePoint)).count, klingon.count, "Block and name matches list a character once")
        XCTAssertTrue(klingon.contains { $0.codePoint == 0xF8D0 })
    }

    func testBlockCardsHandleBasicSupplementarySurrogateAndInvalidRanges() {
        let basic = UnicodeBlock(name: "Basic Latin", start: 0, end: 0x7F)
        XCTAssertEqual(basic.id, 0)
        XCTAssertEqual(basic.rangeLabel, "U+0000–U+007F")
        XCTAssertEqual(basic.subtitle, "128 code points · Basic plane")
        XCTAssertEqual(basic.symbol, "A")
        let combining = UnicodeBlock(name: "Combining Diacritical Marks", start: 0x300, end: 0x36F)
        XCTAssertEqual(combining.symbol, "◌\u{301}")
        let supplementary = UnicodeBlock(name: "Fixture", start: 0x10000, end: 0x10001)
        XCTAssertEqual(supplementary.subtitle, "2 code points · Plane 1")
        XCTAssertEqual(supplementary.symbol.unicodeScalars.map(\.value), [0x10000])
        XCTAssertEqual(UnicodeBlock(name: "Transport", start: 0x1F680, end: 0x1F6FF).symbol, "🚀")
        let surrogate = UnicodeBlock(name: "High Surrogates", start: 0xD800, end: 0xDB7F)
        XCTAssertEqual(surrogate.subtitle, "UTF-16 surrogate code units")
        XCTAssertEqual(surrogate.symbol, "◇")
        XCTAssertEqual(UnicodeBlock(name: "Private Use Area", start: 0xE000, end: 0xF8FF).symbol, "◇")
        let invalid = UnicodeBlock(name: "Invalid", start: UInt32.max, end: UInt32.max)
        XCTAssertEqual(invalid.subtitle, "Invalid code-point range")
        XCTAssertEqual(invalid.symbol, "◇")
    }

    func testCustomCatalogFileURLRetainsLookup() throws {
        let directory = try fixture()
        let byFile = UnicodeCatalog(resourceURL: directory.appendingPathComponent("UnicodeCatalog.ucd"))
        XCTAssertNil(byFile.resourceError)
        XCTAssertEqual(byFile.character(at: 0x41)?.text, "A")
        XCTAssertEqual(byFile.search("0042").map(\.codePoint), [0x42])
    }

    func testRecognizedWireCategoryWithoutHumanDescriptionKeepsItsCodeAndExactText() throws {
        // Custom catalogs can contain the recognized Cs wire-category value
        // without a human-readable category description. Neither record nor
        // range lookup may lose its fallback detail or alter its scalar text.
        let directory = try fixture(ranges: [(0x80, 0x81, 0)])
        let url = directory.appendingPathComponent("UnicodeCatalog.ucd")
        var bytes = try Data(contentsOf: url)
        bytes[48 + 24] = 27 // First record's category: Cs.
        bytes[48 + 2 * 44 + 14] = 27 // First algorithmic range's category: Cs.
        try bytes.write(to: url)
        let custom = UnicodeCatalog(resourceURL: directory)
        XCTAssertNil(custom.resourceError)
        for point: UInt32 in [0x41, 0x80] {
            let character = try XCTUnwrap(custom.character(at: point))
            XCTAssertEqual(character.category, "Cs")
            XCTAssertEqual(character.categoryName, "Cs")
            XCTAssertEqual(character.detail, "Cs")
            XCTAssertEqual(character.text.unicodeScalars.map(\.value), [point])
        }
    }

    func testDraftAdditionCoverageMarkerRequiresDraftProvenance() throws {
        for version in ["18.0.0", "19.0.0 draft"] {
            let directory = try fixture(versionLabel: version)
            try changeProperties(at: directory) { properties in
                properties["assignedSpans"] = [
                    ["start": 0x41, "end": 0x42, "sortKey": 101, "draftAddition": true]
                ]
            }
            let custom = UnicodeCatalog(resourceURL: directory)
            if version.hasSuffix(" draft") {
                XCTAssertNil(custom.resourceError)
                XCTAssertEqual(custom.orderedCharacters().map(\.codePoint), [0x41, 0x42])
                XCTAssertEqual(custom.character(at: 0x41)?.age, "1.1")
            } else {
                XCTAssertNotNil(custom.resourceError)
                XCTAssertTrue(custom.orderedCharacters().isEmpty)
                XCTAssertNil(custom.character(at: 0x41)?.age)
            }
        }
    }

    func testBundledCatalogAndCompleteBlockRanges() {
        XCTAssertNil(catalog.resourceError)
        XCTAssertNotEqual(catalog.version, "Unavailable")
        XCTAssertGreaterThanOrEqual(catalog.blocks.count, 346)
        XCTAssertEqual(catalog.blocks.first?.name, "Basic Latin")
        XCTAssertEqual(catalog.blocks.last?.end, 0x10FFFF)
        for pair in zip(catalog.blocks, catalog.blocks.dropFirst()) {
            XCTAssertLessThan(pair.0.end, pair.1.start)
        }
    }

    func testSupplementaryScalarLookupAndExactInput() throws {
        let rocket = try XCTUnwrap(catalog.character(at: 0x1F680))
        XCTAssertEqual(rocket.name, "ROCKET")
        XCTAssertEqual(rocket.text, "🚀")
        XCTAssertEqual(rocket.codePointLabel, "U+1F680")
        XCTAssertEqual(rocket.blockName, "Transport and Map Symbols")
        XCTAssertEqual(rocket.category, "So")
    }

    func testHexadecimalDecimalAndLiteralSearches() {
        for query in ["U+1F680", "u+1f680", "0x1F680", "1F680", "decimal:128640", "🚀"] {
            XCTAssertEqual(catalog.search(query).map(\.codePoint), [0x1F680], query)
        }
        XCTAssertEqual(catalog.search("U+0041").first?.text, "A")
        XCTAssertEqual(catalog.search("Ω").first?.codePoint, 0x03A9)
        XCTAssertEqual(catalog.search("U+FACE").map(\.codePoint), [0xFACE])
        XCTAssertEqual(catalog.search("0xFACE").map(\.codePoint), [0xFACE])
    }

    func testNamesAliasesAndInformativeDescriptions() throws {
        XCTAssertTrue(catalog.search("rocket").contains { $0.codePoint == 0x1F680 })
        XCTAssertTrue(catalog.search("face").contains { $0.codePoint == 0x1F600 })
        XCTAssertTrue(catalog.search("BOM").contains { $0.codePoint == 0xFEFF })
        let pinned = try pinnedNamesListCatalog()
        XCTAssertTrue(pinned.search("snowy weather").contains { $0.codePoint == 0x2603 })
        XCTAssertTrue(pinned.search("European packaging").contains { $0.codePoint == 0x212E })
        let greek = catalog.search("greek omega")
        XCTAssertTrue(greek.contains { $0.codePoint == 0x03A9 })
        XCTAssertTrue(greek.contains { $0.codePoint == 0x03C9 })
        XCTAssertTrue(catalog.search("no_break space").contains { $0.codePoint == 0x00A0 })
    }

    func testSuzhouNumeralsSearchUsesInformativeContextWithoutRenamingCharacters() throws {
        let digits = Set(UInt32(0x3021)...UInt32(0x3029))
        let catalog = try pinnedNamesListCatalog()
        for query in ["suzhou numerals", "suzhou", "Suzhou numerals", "hangzhou numerals"] {
            let results = Set(catalog.search(query, order: .codePoint).map(\.codePoint))
            XCTAssertTrue(digits.isSubset(of: results), query)
            XCTAssertTrue(Set([UInt32(0x3038), 0x3039, 0x303A]).isSubset(of: results))
            XCTAssertFalse(results.contains(0x302A))
        }
        let one = try XCTUnwrap(catalog.character(at: 0x3021))
        XCTAssertEqual(one.name, "HANGZHOU NUMERAL ONE")
        XCTAssertEqual(one.text, "〡")
        XCTAssertEqual(one.namesListSection, "Suzhou numerals")
        XCTAssertTrue(one.sectionAnnotations.contains { $0.contains("misnomer") })
        XCTAssertFalse(one.nameAliases.contains { $0.kind == "correction" || $0.name.contains("SUZHOU") })
        XCTAssertEqual(one.numericType, "Numeric")
        XCTAssertEqual(one.numericValue, "1")
        XCTAssertEqual(catalog.search("U+3021").map(\.codePoint), [0x3021])
        XCTAssertEqual(catalog.search("additional suzhou numerals", order: .codePoint).map(\.codePoint), [0x3038, 0x3039, 0x303A])
    }

    func testBundledSuzhouCommonNameFindsEveryImmutableHangzhouNumeral() throws {
        let names = ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE"]
        let digits = Set(UInt32(0x3021)...UInt32(0x3029))
        for edition in UnicodeEdition.allCases {
            let catalog = edition.catalog
            // This is the user-facing naming contract, independent of mutable
            // wording or future additional matches in official informative data.
            for query in ["suzhou numerals", "suzhou", "Suzhou numerals", "hangzhou numerals"] {
                let results = Set(catalog.search(query, limit: Int.max, order: .codePoint).map(\.codePoint))
                XCTAssertTrue(digits.isSubset(of: results), "\(edition): \(query)")
            }
            for (index, name) in names.enumerated() {
                let cp = UInt32(0x3021 + index)
                let character = try XCTUnwrap(catalog.character(at: cp))
                XCTAssertEqual(character.name, "HANGZHOU NUMERAL " + name)
                XCTAssertEqual(character.text.unicodeScalars.map(\.value), [cp])
                XCTAssertEqual(character.numericType, "Numeric")
                XCTAssertEqual(character.numericValue, String(index + 1))
                XCTAssertEqual(catalog.search(character.codePointLabel).map(\.codePoint), [cp])
            }
        }
    }

    func testTypedAliasesPreserveFormalCorrectionsAndInformativeNames() throws {
        for includeYangqin in [false, true] {
            let catalog = try pinnedNamesListCatalog(includeYangqin: includeYangqin)
            let bracket = try XCTUnwrap(catalog.character(at: 0xFE18))
            XCTAssertTrue(bracket.name.hasSuffix("BRAKCET"))
            let correction = try XCTUnwrap(bracket.nameAliases.first { $0.kind == "correction" })
            XCTAssertTrue(correction.name.hasSuffix("BRACKET"))
            XCTAssertTrue(correction.isFormal)
            XCTAssertEqual(correction.source, "NameAliases.txt")
            XCTAssertTrue(bracket.annotations.contains { $0.contains("misspelling") })
            XCTAssertTrue(catalog.search(correction.name).contains { $0.codePoint == 0xFE18 })
            let bom = try XCTUnwrap(catalog.character(at: 0xFEFF))
            XCTAssertTrue(bom.nameAliases.contains { $0.name == "BOM" && $0.kind == "abbreviation" && $0.isFormal })
            let six = try XCTUnwrap(catalog.character(at: 0x3026))
            if includeYangqin {
                let alias = try XCTUnwrap(six.nameAliases.first { $0.name == "yangqin sign slow one half beat" })
                XCTAssertFalse(alias.isFormal)
                XCTAssertEqual(alias.source, "NamesList.txt")
                XCTAssertTrue(six.crossReferences.contains { $0.codePoint == 0x16FF4 && $0.codePointLabel == "U+16FF4" })
            } else {
                // The older fixture has no such annotation. Neither references
                // nor aliases may leak from the separately loaded newer fixture.
                XCTAssertFalse(six.nameAliases.contains { $0.name == "yangqin sign slow one half beat" })
                XCTAssertFalse(six.crossReferences.contains { $0.codePoint == 0x16FF4 })
            }
        }
    }

    func testAdditionalCharacterDetailsAreNormativeWhereAvailable() throws {
        for edition in UnicodeEdition.allCases {
            let catalog = edition.catalog
            let fraction = try XCTUnwrap(catalog.character(at: 0x00BD))
            XCTAssertEqual(fraction.numericValue, "1/2")
            XCTAssertEqual(fraction.numericType, "Numeric")
            XCTAssertEqual(catalog.character(at: 0x0031)?.numericType, "Decimal")
            XCTAssertEqual(catalog.character(at: 0x00B2)?.numericType, "Digit")
            XCTAssertEqual(catalog.character(at: 0x0041)?.simpleLowercase, 0x0061)
            XCTAssertEqual(catalog.character(at: 0x0061)?.simpleUppercase, 0x0041)
            XCTAssertEqual(catalog.character(at: 0x0061)?.simpleTitlecase, 0x0041)
            XCTAssertEqual(catalog.character(at: 0x00A0)?.unicode1Name, "NON-BREAKING SPACE")
            XCTAssertNil(catalog.character(at: 0x10FFFF)?.numericValue)
        }
        let pinned = try pinnedNamesListCatalog()
        let wave = try XCTUnwrap(pinned.character(at: 0x301C))
        XCTAssertTrue(wave.annotations.contains { $0.contains("JIS C 6226") })
        XCTAssertTrue(wave.crossReferences.contains { $0.codePoint == 0x3030 && $0.name == "WAVY DASH" })
        XCTAssertFalse(try XCTUnwrap(pinned.character(at: 0x301D)).annotations.contains { $0.contains("JIS C 6226") })
    }

    func testLegacyVersionTwoCatalogStillLoadsPlainDescriptions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var pool = Data()
        func add(_ text: String) -> (UInt32, UInt32) {
            let data = Data(text.utf8), offset = UInt32(pool.count)
            pool.append(data)
            return (offset, UInt32(data.count))
        }
        func append32(_ value: UInt32, to data: inout Data) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt32, to data: inout Data) {
            var little = UInt16(value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let version = add("18.0.0"), name = add("LATIN CAPITAL LETTER A")
        let detail = add("Legacy plain annotation"), search = add("latin capital letter a")
        var data = Data("UBOARD17".utf8)
        let header: [UInt32] = [1, 48, 0, 76, 76, UInt32(pool.count), version.0, version.1, 1, 2]
        for value in header {
            append32(value, to: &data)
        }
        append32(0x0041, to: &data)
        append32(name.0, to: &data)
        append16(name.1, to: &data)
        append16(detail.1, to: &data)
        append32(detail.0, to: &data)
        append32(search.0, to: &data)
        append32(search.1, to: &data)
        data.append(contentsOf: [0, 0, 0, 0]) // Lu, visible, combining class 0, bidi L
        data.append(pool)
        try data.write(to: directory.appendingPathComponent("UnicodeCatalog.ucd"))
        let legacy = UnicodeCatalog(resourceURL: directory)
        let character = try XCTUnwrap(legacy.character(at: 0x0041))
        XCTAssertEqual(character.name, "LATIN CAPITAL LETTER A")
        XCTAssertEqual(character.detail, "Legacy plain annotation")
        XCTAssertTrue(character.nameAliases.isEmpty)
        XCTAssertNil(character.namesListSection)
        XCTAssertEqual(legacy.search("capital letter").map(\.codePoint), [0x0041])
    }

    func testBlockNameSearchIncludesAllAssignedMembersAndUsesRankedPrefix() throws {
        let arrows = catalog.search("Arrows", order: .codePoint)
        XCTAssertEqual(arrows.first?.codePoint, 0x2190)
        XCTAssertTrue(arrows.contains { $0.codePoint == 0x2192 })
        XCTAssertTrue(arrows.prefix(112).allSatisfy { $0.blockName == "Arrows" })
        let operators = catalog.search("Mathematical Operators", limit: 50)
        XCTAssertEqual(operators.count, 50)
        let allOperators = catalog.search("Mathematical Operators", limit: Int.max)
        XCTAssertEqual(operators, Array(allOperators.prefix(50)))
        let block = try XCTUnwrap(catalog.blocks.first { $0.name == "Mathematical Operators" })
        let assigned = Set(catalog.characters(in: block, limit: 1000).map(\.codePoint))
        XCTAssertTrue(assigned.isSubset(of: Set(allOperators.map(\.codePoint))))
        XCTAssertEqual(allOperators.map(\.codePoint), allOperators.map(\.codePoint).sorted())
        XCTAssertEqual(catalog.search("CJK Unified Ideographs Extension B", limit: 3, order: .codePoint).map(\.codePoint),
                       [0x20000, 0x20001, 0x20002])
        XCTAssertTrue(catalog.search("Greek", order: .codePoint).contains { $0.codePoint == 0x03A9 })
        for name in ["Tangut Supplement", "CJK Unified Ideographs Extension D"] {
            let points = catalog.search(name).map(\.codePoint)
            XCTAssertEqual(Set(points).count, points.count, "Small algorithmic block must have unique results: \(name)")
        }
    }

    func testAlgorithmicCJKHangulAndTangutNames() {
        XCTAssertEqual(catalog.character(at: 0x20000)?.name, "CJK UNIFIED IDEOGRAPH-20000")
        XCTAssertEqual(catalog.character(at: 0xAC00)?.name, "HANGUL SYLLABLE GA")
        XCTAssertEqual(catalog.character(at: 0xD7A3)?.name, "HANGUL SYLLABLE HIH")
        XCTAssertEqual(catalog.character(at: 0x17000)?.name, "TANGUT IDEOGRAPH-17000")
        XCTAssertEqual(catalog.search("CJK UNIFIED IDEOGRAPH-20000").first?.codePoint, 0x20000)
        XCTAssertEqual(catalog.search("HANGUL SYLLABLE GA").first?.codePoint, 0xAC00)
    }

    func testInvisibleAndCombiningDisplayPreservesInsertion() throws {
        let space = try XCTUnwrap(catalog.character(at: 0x20))
        XCTAssertTrue(space.isInvisible)
        XCTAssertEqual(space.displayText, "␣")
        XCTAssertEqual(space.text, " ")
        let joiner = try XCTUnwrap(catalog.character(at: 0x200D))
        XCTAssertTrue(joiner.isInvisible)
        XCTAssertFalse(joiner.displayText.isEmpty)
        XCTAssertEqual(joiner.text.unicodeScalars.first?.value, 0x200D)
        let mark = try XCTUnwrap(catalog.character(at: 0x0301))
        XCTAssertEqual(mark.displayText, "◌\u{0301}")
        XCTAssertEqual(mark.text, "\u{0301}")
        XCTAssertTrue(catalog.character(at: 0xE0100)?.isInvisible == true)
    }

    func testAssignedPaginationSkipsReservedSlots() throws {
        let greek = try XCTUnwrap(catalog.blocks.first { $0.name == "Greek and Coptic" })
        let all = catalog.characters(in: greek, limit: 500)
        XCTAssertTrue(all.allSatisfy { $0.category != "Cn" })
        var pages: [UnicodeCharacter] = []
        while true {
            let next = catalog.characters(in: greek, offset: pages.count, limit: 17)
            if next.isEmpty { break }
            pages.append(contentsOf: next)
        }
        XCTAssertEqual(pages, all)
        XCTAssertEqual(Set(pages.map(\.codePoint)).count, pages.count)
        XCTAssertTrue(catalog.characters(in: greek, offset: -1).isEmpty)
        XCTAssertTrue(catalog.characters(in: greek, limit: 0).isEmpty)
    }

    func testLargeAlgorithmicRangePagination() throws {
        let cjk = try XCTUnwrap(catalog.blocks.first { $0.name == "CJK Unified Ideographs Extension B" })
        XCTAssertEqual(catalog.characters(in: cjk, offset: 256, limit: 3, order: .codePoint).map(\.codePoint),
                       [0x20100, 0x20101, 0x20102])
        XCTAssertTrue(catalog.characters(in: cjk, offset: 100_000).isEmpty)
        let surrogates = try XCTUnwrap(catalog.blocks.first { $0.name == "High Surrogates" })
        XCTAssertTrue(catalog.characters(in: surrogates).isEmpty)
    }

    func testScalarBoundariesReservedValuesAndInvalidQueries() {
        XCTAssertEqual(catalog.character(at: 0x10FFFF)?.name, "NONCHARACTER")
        XCTAssertEqual(catalog.character(at: 0x10FFFF)?.text.unicodeScalars.first?.value, 0x10FFFF)
        XCTAssertEqual(catalog.character(at: 0x10FFFF)?.category, "Cn")
        XCTAssertNil(catalog.character(at: 0xD800))
        XCTAssertNil(catalog.character(at: 0x110000))
        for query in ["U+D800", "U+110000", "0xZZZZ", "decimal:-1", "decimal:1114112", "110000"] {
            XCTAssertTrue(catalog.search(query).isEmpty, query)
        }
        XCTAssertTrue(catalog.search("rocket", limit: 0).isEmpty)
        XCTAssertEqual(catalog.search("", limit: 3), catalog.orderedCharacters(limit: 3, order: .codePoint))
    }

    func testFixedUnassignedFixtureHasNoInventedPropertiesOrAssignedBrowseEntries() throws {
        let directory = try fixture()
        try changeProperties(at: directory) { properties in
            properties["ages"] = [["start": 0x41, "end": 0x42, "value": "1.1"]]
            properties["scripts"] = [["start": 0x41, "end": 0x42, "value": "Latin"]]
        }
        let fixed = UnicodeCatalog(resourceURL: directory)
        XCTAssertNil(fixed.resourceError)
        for cp: UInt32 in [0x0378, 0x03A2] {
            let character = try XCTUnwrap(fixed.character(at: cp))
            XCTAssertEqual(character.name, "UNASSIGNED")
            XCTAssertEqual(character.category, "Cn")
            XCTAssertNil(character.age)
            XCTAssertNil(character.numericValue)
            XCTAssertNil(character.combiningClass)
            XCTAssertEqual(character.text.unicodeScalars.map(\.value), [cp])
            XCTAssertEqual(fixed.search(character.codePointLabel).map(\.codePoint), [cp])
            XCTAssertFalse(fixed.orderedCharacters().contains { $0.codePoint == cp })
        }
    }

    func testCorruptOrAbsentResourceDoesNotCrash() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("UnicodeCatalog.ucd"))
        let invalid = UnicodeCatalog(resourceURL: directory)
        XCTAssertNotNil(invalid.resourceError)
        XCTAssertEqual(invalid.version, "Unavailable")
        XCTAssertEqual(invalid.character(at: 0x41)?.name, "UNASSIGNED")
        XCTAssertTrue(invalid.search("rocket").isEmpty)
    }

    func testSeparateFinalAndDraftEditionsRetainOfficialAges() throws {
        let latest = UnicodeEdition.latest.catalog
        XCTAssertNil(latest.resourceError)
        XCTAssertFalse(latest.version.contains("draft"))
        XCTAssertTrue(UnicodeEdition.draft.catalog.version.hasSuffix(" draft"))
        XCTAssertGreaterThanOrEqual(unicodeVersionKey(UnicodeEdition.draft.catalog.version), unicodeVersionKey(latest.version))
        XCTAssertTrue(UnicodeEdition.draft.catalog === UnicodeCatalog.shared)
        XCTAssertEqual(UnicodeEdition.latest.rawValue, "latest")
        XCTAssertEqual(UnicodeEdition.draft.rawValue, "draft")
        for edition in UnicodeEdition.allCases {
            let major = edition.catalog.version.split(separator: ".").first.map(String.init) ?? ""
            XCTAssertEqual(edition.title, edition == .draft ? "Unicode \(major) Draft" : "Unicode \(major)")
            XCTAssertEqual(edition.versionLabel, edition.catalog.version)
            if unicodeVersionKey(edition.catalog.version) >= unicodeVersionKey("18.0") {
                XCTAssertEqual(edition.catalog.character(at: 0x1FAEB)?.name, "CRACKING FACE")
                XCTAssertEqual(edition.catalog.character(at: 0x1FAEB)?.age, "18.0")
            } else {
                XCTAssertEqual(edition.catalog.character(at: 0x1FAEB)?.category, "Cn")
                XCTAssertNil(edition.catalog.character(at: 0x1FAEB)?.age)
            }
            XCTAssertEqual(edition.catalog.character(at: 0x41)?.age, "1.1")
            XCTAssertEqual(edition.catalog.character(at: 0x10FFFF)?.name, "NONCHARACTER")
            XCTAssertEqual(edition.catalog.character(at: 0x10FFFF)?.category, "Cn")
        }
    }

    func testHistoricalReleaseSelectionAndAssignmentBoundaries() {
        XCTAssertEqual(UnicodeEdition.allCases, [.latest, .previous, .older, .draft])
        let latestMajor = unicodeVersionKey(UnicodeEdition.latest.versionLabel) / 100
        XCTAssertEqual(UnicodeEdition.previous.versionLabel, "\(latestMajor - 1).0.0")
        XCTAssertEqual(UnicodeEdition.older.versionLabel, "\(latestMajor - 2).0.0")
        XCTAssertEqual(UnicodeEdition.latest.selectionIdentifier, "latest")
        XCTAssertEqual(UnicodeEdition.draft.selectionIdentifier, "draft")
        XCTAssertEqual(UnicodeEdition.previous.selectionIdentifier, UnicodeEdition.previous.versionLabel)
        XCTAssertEqual(UnicodeEdition.older.selectionIdentifier, UnicodeEdition.older.versionLabel)
        for edition in UnicodeEdition.allCases {
            XCTAssertEqual(UnicodeEdition.resolve(selectionIdentifier: edition.selectionIdentifier), edition)
        }
        for missing in [nil, "", "13.0.0", "999999.0.0", "previous", "older", "Unavailable"] {
            XCTAssertEqual(UnicodeEdition.resolve(selectionIdentifier: missing), .latest)
        }
        for edition in [UnicodeEdition.older, .previous, .latest] {
            XCTAssertNil(edition.catalog.resourceError)
            for (point, age): (UInt32, String) in [(0x10940, "17.0"), (0x0558, "18.0")] {
                if unicodeVersionKey(edition.versionLabel) < unicodeVersionKey(age) {
                    XCTAssertEqual(edition.catalog.character(at: point)?.category, "Cn")
                    XCTAssertNil(edition.catalog.character(at: point)?.age)
                } else {
                    XCTAssertEqual(edition.catalog.character(at: point)?.age, age)
                }
            }
            XCTAssertEqual(edition.catalog.character(at: 0x0041)?.age, "1.1")
            XCTAssertEqual(edition.catalog.character(at: 0x10FFFF)?.category, "Cn")
        }
    }

    func testNormativeCharacterProperties() throws {
        let mark = try XCTUnwrap(catalog.character(at: 0x0301))
        XCTAssertEqual(mark.categoryName, "Nonspacing combining mark")
        XCTAssertEqual(mark.combiningClass, 230)
        XCTAssertEqual(mark.bidirectionalClass, "NSM")
        XCTAssertEqual(mark.script, "Inherited")
        let accent = try XCTUnwrap(catalog.character(at: 0x00C5))
        XCTAssertEqual(accent.script, "Latin")
        XCTAssertEqual(accent.decomposition, "0041 030A")
        XCTAssertEqual(catalog.character(at: 0x05D0)?.bidirectionalClass, "R")
        XCTAssertEqual(catalog.character(at: 0xAC00)?.decomposition, "1100 1161")
        XCTAssertEqual(catalog.character(at: 0xAC01)?.decomposition, "1100 1161 11A8")
        for edition in UnicodeEdition.allCases {
            XCTAssertEqual(edition.catalog.character(at: 0xF900)?.decomposition, "8C48")
            XCTAssertEqual(edition.catalog.character(at: 0x2F800)?.decomposition, "4E3D")
        }
        XCTAssertNil(catalog.character(at: 0x10FFFF)?.combiningClass)
    }

    func testNumericVersionOrderingAndGlobalPagination() {
        XCTAssertGreaterThan(unicodeVersionKey("10.0"), unicodeVersionKey("9.0"))
        XCTAssertGreaterThan(unicodeVersionKey("15.1"), unicodeVersionKey("15.0"))
        let newest = catalog.orderedCharacters(limit: 300, order: .newestFirst)
        XCTAssertGreaterThanOrEqual(newest.first?.versionSortKey ?? 0, unicodeVersionKey("18.0"))
        XCTAssertTrue(newest.allSatisfy { $0.category != "Cn" })
        for pair in zip(newest, newest.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.versionSortKey, pair.1.versionSortKey)
        }
        XCTAssertEqual(catalog.orderedCharacters(offset: 120, limit: 45, order: .newestFirst), Array(newest[120..<165]))
        let oldest = catalog.orderedCharacters(limit: 300, order: .oldestFirst)
        XCTAssertEqual(oldest.first?.codePoint, 0)
        XCTAssertEqual(oldest.first?.age, "1.1")
        XCTAssertEqual(catalog.orderedCharacters(offset: 200, limit: 30, order: .oldestFirst), Array(oldest[200..<230]))
        let codePoints = catalog.orderedCharacters(limit: 300, order: .codePoint)
        XCTAssertEqual(codePoints.map(\.codePoint), codePoints.map(\.codePoint).sorted())
        XCTAssertTrue(catalog.orderedCharacters(offset: 500_000).isEmpty)
        XCTAssertTrue(catalog.orderedCharacters(offset: -1).isEmpty)
    }

    func testSearchSortsEntireMatchSetBeforeLimiting() async {
        let catalog = self.catalog
        for order in UnicodeSortOrder.allCases {
            let (complete, limited) = await CatalogWorker.run {
                let complete = catalog.search("letter", limit: 100_000, order: order)
                let limited = catalog.search("letter", limit: 7, order: order)
                return (complete, limited)
            }
            XCTAssertGreaterThan(complete.count, 10_000)
            XCTAssertEqual(limited, Array(complete.prefix(7)))
            if order == .newestFirst { XCTAssertGreaterThanOrEqual(complete.first?.versionSortKey ?? 0, unicodeVersionKey("18.0")) }
        }
        let (rockets, firstRocket, exactRocket) = await CatalogWorker.run {
            (catalog.search("rocket", limit: Int.max), catalog.search("rocket", limit: 1), catalog.search("U+1F680", limit: 1))
        }
        XCTAssertTrue(rockets.contains { $0.codePoint == 0x1F680 })
        XCTAssertEqual(firstRocket, Array(rockets.prefix(1)))
        XCTAssertEqual(firstRocket.first?.codePoint, 0x1CC56, "A smaller complete-word ROCKET SHIP precedes ROCKET")
        XCTAssertEqual(exactRocket.first?.codePoint, 0x1F680)
    }

    func testBlockPaginationOrdersEntireBlockBeforeLimiting() throws {
        let arrows = try XCTUnwrap(catalog.blocks.first { $0.name == "Arrows" })
        let all = catalog.characters(in: arrows, limit: 1000, order: .newestFirst)
        XCTAssertNotEqual(all.first?.codePoint, arrows.start)
        XCTAssertEqual(catalog.characters(in: arrows, limit: 5, order: .newestFirst), Array(all.prefix(5)))
        XCTAssertEqual(catalog.characters(in: arrows, offset: 10, limit: 5, order: .newestFirst), Array(all[10..<15]))
        let oldest = catalog.characters(in: arrows, limit: 1000, order: .oldestFirst)
        XCTAssertEqual(oldest.first?.age, "1.1")
        XCTAssertEqual(catalog.characters(in: arrows, offset: 10, limit: 5, order: .oldestFirst), Array(oldest[10..<15]))
    }

    func testEveryTruncationAndImpossibleHeaderFailsWithoutUsingDetachedProperties() throws {
        let directory = try fixture(), url = directory.appendingPathComponent("UnicodeCatalog.ucd")
        let complete = try Data(contentsOf: url)
        for length in 0..<complete.count {
            try complete.prefix(length).write(to: url)
            let broken = UnicodeCatalog(resourceURL: directory)
            XCTAssertEqual(broken.version, "Unavailable", "Truncated at \(length)")
            XCTAssertTrue(broken.orderedCharacters().isEmpty)
            XCTAssertNil(broken.character(at: 0x41)?.age)
        }
        for field in [8, 12, 16, 20, 24, 28, 32, 36, 44] {
            var bytes = complete
            bytes.replaceSubrange(field..<(field + 4), with: [255, 255, 255, 255])
            try bytes.write(to: url)
            XCTAssertEqual(UnicodeCatalog(resourceURL: directory).version, "Unavailable")
        }
        var invalidUTF8 = complete
        invalidUTF8[invalidUTF8.count - 1] = 0xFF
        try invalidUTF8.write(to: url)
        XCTAssertEqual(UnicodeCatalog(resourceURL: directory).version, "Unavailable")
    }

    func testMalformedScalarOrderAndAlgorithmicDomainsCannotReachLookup() throws {
        for points: [UInt32] in [[0x42, 0x41], [0x41, 0x41], [0xD800], [0x110000], [UInt32.max]] {
            let directory = try fixture(records: points)
            let broken = UnicodeCatalog(resourceURL: directory)
            XCTAssertEqual(broken.version, "Unavailable")
            XCTAssertEqual(broken.character(at: 0x41)?.name, "UNASSIGNED")
        }
        let malformed: [[(UInt32, UInt32, UInt8)]] = [
            [(0, 1, 1)], [(0xD7A3, 0xD7A4, 1)], [(0xD700, 0xE000, 0)],
            [(0x80, 0x82, 0), (0x82, 0x84, 0)], [(0x90, 0x91, 0), (0x80, 0x81, 0)],
            [(0x42, 0x44, 0)], [(0x90, 0x80, 0)]]
        for ranges in malformed {
            let directory = try fixture(ranges: ranges)
            let broken = UnicodeCatalog(resourceURL: directory)
            XCTAssertEqual(broken.version, "Unavailable")
            XCTAssertTrue(broken.search("hangul").isEmpty)
        }
    }

    func testInvalidBlocksNeverReachBinarySearchOrUnsignedSubtitleArithmetic() throws {
        let directory = try fixture(), url = directory.appendingPathComponent("Blocks.json")
        for blocks: [[String: Any]] in [
            [["name": "Bad", "start": 42, "end": 1]],
            [["name": "Bad", "start": 0, "end": 0x110000]],
            [["name": "", "start": 0, "end": 127]],
            [["name": "First", "start": 0, "end": 64], ["name": "Overlap", "start": 64, "end": 128]]
        ] {
            try JSONSerialization.data(withJSONObject: blocks).write(to: url)
            let broken = UnicodeCatalog(resourceURL: directory)
            XCTAssertNotNil(broken.resourceError)
            XCTAssertTrue(broken.blocks.isEmpty)
            XCTAssertEqual(broken.character(at: 0x41)?.blockName, "No Block")
        }
        XCTAssertEqual(UnicodeBlock(name: "Bad", start: UInt32.max, end: 0).subtitle, "Invalid code-point range")
    }

    func testForeignEditionAndInventedCoveragePropertiesAreNotUsed() throws {
        for mutate in 0..<4 {
            let directory = try fixture()
            try changeProperties(at: directory) { properties in
                switch mutate {
                case 0: properties["unicodeVersion"] = "19.0.0 draft"
                case 1: properties["assignedSpans"] = [["start": 0x43, "end": 0x44, "sortKey": 101, "draftAddition": false]]
                case 2: properties["assignedSpans"] = [["start": 0x41, "end": 0x42, "sortKey": Int.max, "draftAddition": false]]
                default: properties["ages"] = [["start": 0, "end": 0x10FFFF, "value": "999999999999999999999.0"]]
                }
            }
            let broken = UnicodeCatalog(resourceURL: directory)
            XCTAssertNotNil(broken.resourceError)
            XCTAssertEqual(broken.character(at: 0x41)?.name, "FIXTURE LETTER 0041")
            XCTAssertNil(broken.character(at: 0x41)?.age)
            XCTAssertTrue(broken.orderedCharacters().isEmpty)
        }
    }

    func testInvalidStructuredDetailsCannotExposeInvalidMappingsOrInventFormalAliases() throws {
        let detail = #"{"aliases":[{"name":"Invented","kind":"unknown"}],"references":[{"codePoint":1114112,"name":"Invalid"}],"simpleUppercase":55296}"#
        let directory = try fixture(details: [0x41: detail])
        let character = try XCTUnwrap(UnicodeCatalog(resourceURL: directory).character(at: 0x41))
        XCTAssertEqual(character.text, "A")
        XCTAssertTrue(character.nameAliases.isEmpty)
        XCTAssertTrue(character.crossReferences.isEmpty)
        XCTAssertNil(character.simpleUppercase)
        XCTAssertFalse(UnicodeNameAlias(name: "Unknown", kind: "unknown").isFormal)
    }

    func testBlockPreviewUsesATypicalVisibleCharacter() throws {
        let catalog = UnicodeEdition.latest.catalog
        func block(_ name: String) throws -> UnicodeBlock { try XCTUnwrap(catalog.blocks.first { $0.name == name }) }
        XCTAssertEqual(catalog.representative(of: try block("Basic Latin")), "A", "Curated examples win")
        XCTAssertEqual(catalog.representative(of: try block("Cyrillic Supplement")), "\u{0500}", "First letter, not the block start")
        XCTAssertEqual(catalog.representative(of: try block("Mathematical Alphanumeric Symbols")), "\u{1D400}")
        XCTAssertEqual(catalog.representative(of: try block("Combining Diacritical Marks for Symbols")), "\u{25CC}\u{20D0}")
        XCTAssertEqual(catalog.representative(of: try block("Variation Selectors")), "◇", "Invisible-only blocks use a placeholder")
        XCTAssertEqual(catalog.representative(of: try block("Private Use Area")), "◇")
    }

    func testEachFinalEditionListsExactlyItsOwnAdditions() throws {
        for edition in [UnicodeEdition.latest, .previous, .older] {
            let catalog = edition.catalog
            let major = catalog.version.split(separator: ".").first.map(String.init) ?? ""
            let added = catalog.addedCharacters(limit: Int.max)
            XCTAssertEqual(added.count, catalog.addedCount)
            XCTAssertGreaterThan(added.count, 0)
            XCTAssertTrue(added.allSatisfy { $0.age == major + ".0" }, edition.rawValue)
            XCTAssertEqual(added.map(\.codePoint), added.map(\.codePoint).sorted())
            let emoji = edition.emojiCatalog.addedEntries
            XCTAssertTrue(emoji.allSatisfy { $0.emojiVersion == edition.emojiCatalog.version })
        }
        XCTAssertEqual(UnicodeEdition.latest.catalog.addedCharacters(limit: 3).map(\.codePoint), [0x0558, 0x058B, 0x058C])
        XCTAssertEqual(UnicodeEdition.latest.emojiCatalog.addedEntries.count, 19)
        let seal = try XCTUnwrap(UnicodeEdition.latest.catalog.blocks.first { $0.name == "Seal" })
        let rows = UnicodeEdition.latest.catalog.chartRows(in: seal, columns: 16, addedOnly: true)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.assigned.nonzeroBitCount }, 11_328)
    }

    func testRangePagesStayWithinTheirPlane() throws {
        let catalog = UnicodeEdition.latest.catalog
        let smp = catalog.orderedCharacters(in: 0x10000...0x1FFFF, limit: 300)
        XCTAssertEqual(smp.first?.codePoint, 0x10000)
        XCTAssertTrue(smp.allSatisfy { (0x10000...0x1FFFF).contains($0.codePoint) })
        XCTAssertEqual(smp.map(\.codePoint), smp.map(\.codePoint).sorted())
        let next = catalog.orderedCharacters(in: 0x10000...0x1FFFF, offset: 300, limit: 1)
        XCTAssertGreaterThan(try XCTUnwrap(next.first).codePoint, try XCTUnwrap(smp.last).codePoint)
        XCTAssertEqual(catalog.orderedCharacters(in: 0xF0000...0xF0001, limit: 10).map(\.codePoint), [0xF0000, 0xF0001])
        // High to low pages the same characters from the top of the range.
        let ascending = catalog.orderedCharacters(in: 0x2600...0x27BF, limit: 2000).map(\.codePoint)
        let descending = catalog.orderedCharacters(in: 0x2600...0x27BF, limit: 2000, descending: true).map(\.codePoint)
        XCTAssertEqual(descending, ascending.reversed())
        let pages = stride(from: 0, to: descending.count, by: 7).flatMap {
            catalog.orderedCharacters(in: 0x2600...0x27BF, offset: $0, limit: 7, descending: true).map(\.codePoint)
        }
        XCTAssertEqual(pages, descending)
        XCTAssertEqual(catalog.orderedCharacters(in: 0xF0000...0xF0001, limit: 10, descending: true).map(\.codePoint), [0xF0001, 0xF0000])
    }

    func testChartRowsMarkAssignedColumnsWithoutCreatingCharacters() throws {
        let directory = try fixture(records: [0, 0x41, 0x1F680], ranges: [(0xAC00, 0xAC05, 1)])
        let fixture = UnicodeCatalog(resourceURL: directory)
        XCTAssertNil(fixture.resourceError)
        let latin = UnicodeBlock(name: "Basic Latin", start: 0, end: 0x7F)
        XCTAssertEqual(fixture.chartRows(in: latin, columns: 16), [
            UnicodeChartRow(start: 0, assigned: 1), UnicodeChartRow(start: 0x40, assigned: 1 << 1)])
        XCTAssertEqual(fixture.chartRows(in: latin, columns: 8).map(\.start), [0, 0x40])
        let hangul = UnicodeBlock(name: "Hangul Syllables", start: 0xAC00, end: 0xD7AF)
        XCTAssertEqual(fixture.chartRows(in: hangul, columns: 16), [UnicodeChartRow(start: 0xAC00, assigned: 0b11_1111)])
        XCTAssertEqual(fixture.chartRows(in: hangul, columns: 4), [
            UnicodeChartRow(start: 0xAC00, assigned: 0b1111), UnicodeChartRow(start: 0xAC04, assigned: 0b11)])
        let row = fixture.chartRows(in: hangul, columns: 16)[0]
        XCTAssertEqual((0..<16).filter(row.isAssigned), [0, 1, 2, 3, 4, 5])
        XCTAssertTrue(fixture.chartRows(in: latin, columns: 0).isEmpty)
        XCTAssertTrue(fixture.chartRows(in: latin, columns: 17).isEmpty)
        XCTAssertTrue(fixture.chartRows(in: UnicodeBlock(name: "Empty", start: 0x100, end: 0x17F), columns: 16).isEmpty)
    }

    func testFixturePagesReconstructExactAssignedScalarSetWithExtremeOffsetsAndLimits() throws {
        let directory = try fixture(records: [0, 0x41, 0x1F680], ranges: [(0xAC00, 0xAC05, 1)])
        let fixture = UnicodeCatalog(resourceURL: directory)
        XCTAssertNil(fixture.resourceError)
        let expected: [UInt32] = [0, 0x41, 0xAC00, 0xAC01, 0xAC02, 0xAC03, 0xAC04, 0xAC05, 0x1F680]
        for order in UnicodeSortOrder.allCases {
            for size in 1...5 {
                var pages: [UnicodeCharacter] = []
                while true {
                    let page = fixture.orderedCharacters(offset: pages.count, limit: size, order: order)
                    if page.isEmpty { break }
                    pages += page
                    XCTAssertLessThanOrEqual(pages.count, expected.count)
                }
                XCTAssertEqual(pages.map(\.codePoint), expected)
                XCTAssertEqual(Set(pages.map(\.codePoint)).count, expected.count)
            }
            XCTAssertTrue(fixture.orderedCharacters(offset: Int.max, limit: Int.max, order: order).isEmpty)
            XCTAssertEqual(fixture.orderedCharacters(limit: Int.max, order: order).map(\.codePoint), expected)
        }
    }

    func testVersionOverflowAndSignedCodePointSyntaxAreRejected() {
        XCTAssertEqual(unicodeVersionKey("15.1 draft"), 1501)
        for value in ["\(Int.max).0", "18.100", "-1.0", "18..0", "18.zero", ""] {
            XCTAssertEqual(unicodeVersionKey(value), 0, value)
        }
        for query in ["U++0041", "0x+0041", "decimal:+65", "decimal:٦٥"] {
            XCTAssertTrue(catalog.search(query).isEmpty, query)
        }
    }

    func testCancelledSearchAndBrowsingDoNotProduceStalePages() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let catalog = UnicodeCatalog.shared
            return catalog.search("cjk ideograph", limit: Int.max).isEmpty
                && catalog.orderedCharacters(limit: Int.max).isEmpty
                && catalog.search("U+1F680").isEmpty
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }

    func testSearchUTF8LimitPrecedesFoldingAndKeepsTheExactBoundary() throws {
        let directory = try fixture(records: [0x1F680]), fixture = UnicodeCatalog(resourceURL: directory)
        let boundary = "🚀" + String(repeating: " ", count: 4092)
        XCTAssertEqual(boundary.utf8.count, 4096)
        XCTAssertTrue(CatalogSearchQueryPolicy.accepts(boundary))
        XCTAssertEqual(fixture.search(boundary).map(\.codePoint), [0x1F680])
        XCTAssertFalse(CatalogSearchQueryPolicy.accepts(boundary + " "))
        XCTAssertTrue(fixture.search(boundary + " ").isEmpty)
        XCTAssertTrue(fixture.search(String(repeating: "a\u{301}", count: 20_000)).isEmpty)
    }

    func testDuplicateANDTermsKeepFirstOrderAndIdenticalExactNameRanking() throws {
        let directory = try fixture(names: [0x41: "ROCKET", 0x42: "ROCKET ROCKET"])
        let fixture = UnicodeCatalog(resourceURL: directory)
        XCTAssertEqual(CatalogSearchQueryPolicy.terms(in: "rocket arrow rocket letter arrow"), ["rocket", "arrow", "letter"])
        XCTAssertTrue(CatalogSearchQueryPolicy.containsWholeTerm("rocket", in: "rocket rocket arrow"))
        XCTAssertTrue(CatalogSearchQueryPolicy.containsWholeTerm("arrow", in: "arrow rocket"))
        for order in UnicodeSortOrder.allCases {
            XCTAssertEqual(fixture.search("rocket rocket rocket", order: order), fixture.search("rocket", order: order))
            XCTAssertEqual(fixture.search(String(repeating: "rocket ", count: 585), order: order), fixture.search("rocket", order: order))
        }
        XCTAssertEqual(fixture.search("U+0041").map(\.codePoint), [0x41])
    }

    func testEmptyRecordAndRangeCatalogCannotReportHealthyResources() throws {
        let directory = try fixture(records: [])
        let empty = UnicodeCatalog(resourceURL: directory)
        XCTAssertNotNil(empty.resourceError)
        XCTAssertEqual(empty.version, "Unavailable")
        XCTAssertTrue(empty.orderedCharacters().isEmpty)
    }

    func testAuthoritativeManifestRejectsSwappedFinalPairWithoutInferringEditionFromFilename() throws {
        let directory = try fixture() // Final binary + final properties under custom/draft filenames.
        XCTAssertNil(UnicodeCatalog(resourceURL: directory).resourceError, "A manifest-free custom fixture remains supported")
        let manifest = directory.appendingPathComponent("UnicodeSources.json")
        for identity: [String: Any] in [
            ["versionLabel": "19.0.0 draft", "isDraft": true], // binary/property swap alone
            ["versionLabel": "18.0.0", "isDraft": false], // entire final manifest swapped too
            ["versionLabel": "18.0.0", "isDraft": true] // inconsistent authoritative flag
        ] {
            try JSONSerialization.data(withJSONObject: identity).write(to: manifest)
            let swapped = UnicodeCatalog(resourceURL: directory)
            XCTAssertEqual(swapped.version, "Unavailable")
            XCTAssertNotNil(swapped.resourceError)
            XCTAssertTrue(swapped.orderedCharacters().isEmpty)
        }
        try Data("invalid provenance".utf8).write(to: manifest)
        XCTAssertEqual(UnicodeCatalog(resourceURL: directory).version, "Unavailable")
        let validDraft = try fixture(versionLabel: "19.0.0 draft")
        try JSONSerialization.data(withJSONObject: ["versionLabel": "19.0.0 draft", "isDraft": true])
            .write(to: validDraft.appendingPathComponent("UnicodeSources.json"))
        XCTAssertNil(UnicodeCatalog(resourceURL: validDraft).resourceError)
        XCTAssertEqual(UnicodeCatalog(resourceURL: validDraft).version, "19.0.0 draft")
    }

    func testWholeWordTierUsesSelectedOrderBeforeSubstringMatchesAndLimit() throws {
        let directory = try fixture(records: Array(0x41...0x47), names: [
            0x41: "ART WORD", 0x42: "ART", 0x43: "CART WORD", 0x44: "HEART WORD",
            0x45: "ARTWORK", 0x46: "LETTER", 0x47: "LETTER"],
            searches: [0x46: "letter informative art"], contexts: [0x47: "art word"])
        try changeProperties(at: directory) { properties in
            properties["assignedSpans"] = [101, 1000, 1800, 101, 1800, 600, 1800].enumerated().map {
                ["start": 0x41 + $0.offset, "end": 0x41 + $0.offset, "sortKey": $0.element, "draftAddition": false] as [String: Any]
            }
        }
        let fixture = UnicodeCatalog(resourceURL: directory)
        XCTAssertNil(fixture.resourceError)
        let expected: [UnicodeSortOrder: [UInt32]] = [
            .codePoint: [0x41, 0x42, 0x46, 0x47, 0x43, 0x44, 0x45],
            .newestFirst: [0x47, 0x42, 0x46, 0x41, 0x43, 0x45, 0x44],
            .oldestFirst: [0x41, 0x46, 0x42, 0x47, 0x44, 0x43, 0x45]]
        for order in UnicodeSortOrder.allCases {
            let points = try XCTUnwrap(expected[order])
            XCTAssertEqual(fixture.search("art", limit: Int.max, order: order).map(\.codePoint), points)
            XCTAssertEqual(fixture.search("art", limit: 3, order: order).map(\.codePoint), Array(points.prefix(3)))
            XCTAssertEqual(fixture.search("art art", order: order), fixture.search("art", order: order))
        }
        XCTAssertEqual(fixture.search("art word").map(\.codePoint), [0x41, 0x47, 0x43, 0x44])
        XCTAssertEqual(fixture.search("WORD_art").map(\.codePoint), [0x41, 0x47, 0x43, 0x44])
        XCTAssertEqual(fixture.search("U+0043").map(\.codePoint), [0x43])
        XCTAssertEqual(fixture.search("A").map(\.codePoint), [0x41])
        let algorithmicDirectory = try self.fixture(records: [0x41], ranges: [(0x20000, 0x20002, 0)],
                                                    names: [0x41: "PREFIXTURE"])
        let algorithmic = UnicodeCatalog(resourceURL: algorithmicDirectory)
        XCTAssertNil(algorithmic.resourceError)
        XCTAssertEqual(algorithmic.search("fixture").map(\.codePoint), [0x20000, 0x20001, 0x20002, 0x41])
        XCTAssertEqual(algorithmic.search("fix").map(\.codePoint), [0x41, 0x20000, 0x20001, 0x20002])
    }

    func testNormalizedUnicodeWordsHaveRealBoundariesAndStableTies() throws {
        let directory = try fixture(records: Array(0x41...0x46), names: [
            0x41: "MÉLANGE", 0x42: "ÉLAN", 0x43: "中漢字", 0x44: "漢字", 0x45: "PREΩΜΕΓΑ", 0x46: "ΩΜΕΓΑ"],
            searches: [0x41: "melange", 0x42: "elan", 0x43: "中漢字", 0x44: "漢字", 0x45: "preωμεγα", 0x46: "ωμεγα"])
        let fixture = UnicodeCatalog(resourceURL: directory)
        XCTAssertNil(fixture.resourceError)
        for query in ["élan", "ÉLAN", "ｅｌａｎ", "(elan)"] {
            XCTAssertEqual(fixture.search(query).map(\.codePoint), [0x42, 0x41], query)
        }
        XCTAssertEqual(fixture.search("漢字").map(\.codePoint), [0x44, 0x43])
        XCTAssertEqual(fixture.search("ωμεγα").map(\.codePoint), [0x46, 0x45])
        XCTAssertFalse(CatalogSearchQueryPolicy.containsWholeTerm("", in: "elan"))
        XCTAssertTrue(CatalogSearchQueryPolicy.containsWholeTerm("art", in: "cart art"))
        XCTAssertFalse(CatalogSearchQueryPolicy.containsWholeTerm("art", in: "cart artist"))
    }

    func testDefaultScalarBrowsingAndEmptySearchUseAscendingCodePoints() throws {
        let directory = try fixture(records: [0x41, 0x1F680], ranges: [(0xAC00, 0xAC02, 1)])
        try changeProperties(at: directory) { properties in
            properties["assignedSpans"] = [
                ["start": 0x41, "end": 0x41, "sortKey": 1800, "draftAddition": false],
                ["start": 0xAC00, "end": 0xAC02, "sortKey": 101, "draftAddition": false],
                ["start": 0x1F680, "end": 0x1F680, "sortKey": 1000, "draftAddition": false]]
        }
        let fixture = UnicodeCatalog(resourceURL: directory)
        let expected: [UInt32] = [0x41, 0xAC00, 0xAC01, 0xAC02, 0x1F680]
        XCTAssertNil(fixture.resourceError)
        XCTAssertEqual(fixture.orderedCharacters(limit: 99).map(\.codePoint), expected)
        XCTAssertEqual(fixture.search(" \n", limit: 99).map(\.codePoint), expected)
        let block = try XCTUnwrap(fixture.blocks.first)
        XCTAssertEqual(fixture.characters(in: block, offset: 1, limit: 2).map(\.codePoint), [0xAC00, 0xAC01])
        XCTAssertEqual(fixture.search("hangul syllable ga").first?.codePoint, 0xAC00)
        XCTAssertEqual(fixture.orderedCharacters(limit: 2, order: .newestFirst).map(\.codePoint), [0x41, 0x1F680])
    }

    func testFinalEditionsAreTheDraftLimitedToTheirVersion() throws {
        XCTAssertTrue(UnicodeCatalog.shared.limited(to: .draft) === UnicodeCatalog.shared)
        let latest = UnicodeCatalog.latest, previous = UnicodeCatalog.previous
        XCTAssertEqual(latest.version, "18.0.0")
        XCTAssertNil(previous.resourceError)
        let added = try XCTUnwrap(latest.addedCharacters(limit: 1).first, "Unicode 18 adds characters")
        XCTAssertEqual(added.age, "18.0")
        XCTAssertEqual(latest.character(at: added.codePoint)?.name, added.name)
        let later = try XCTUnwrap(previous.character(at: added.codePoint))
        XCTAssertEqual(later.name, "UNASSIGNED", "A character from a later version reads as unassigned")
        XCTAssertNil(later.age)
        XCTAssertEqual(later.script, "Unknown")
        XCTAssertFalse(previous.search(added.name).contains { $0.codePoint == added.codePoint })
        XCTAssertTrue(latest.search(added.name).contains { $0.codePoint == added.codePoint })
        XCTAssertFalse(previous.addedCharacters(limit: 4096).contains { $0.codePoint == added.codePoint })
        XCTAssertGreaterThan(latest.addedCount, 0)
        XCTAssertLessThan(previous.blocks.count, latest.blocks.count, "Blocks begin in the version that fills them")
        XCTAssertTrue(latest.blocks.allSatisfy(UnicodeCatalog.shared.blocks.contains))
        // An algorithmic range that grew later keeps only its earlier part.
        let ideographs = try XCTUnwrap(UnicodeCatalog.older.search("cjk unified ideograph", limit: 400_000))
        XCTAssertTrue(ideographs.allSatisfy { ($0.age.map(unicodeVersionKey) ?? 0) <= unicodeVersionKey("16.0") })
        XCTAssertEqual(UnicodeCatalog.older.character(at: 0x4E00)?.name, "CJK UNIFIED IDEOGRAPH-4E00")
        XCTAssertEqual(UnicodeCatalog.older.search("cjk unified ideograph 4e00").first?.codePoint, 0x4E00)
        let unavailable = UnicodeCatalog(resourceURL: try fixture()).limited(to: .latest)
        XCTAssertEqual(unavailable.version, "18.0.0", "A custom catalog still uses the bundled labels")
    }
}
