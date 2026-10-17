import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UnicodeCatalogTests: XCTestCase {
    private let catalog = UnicodeCatalog.shared

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

    func testNamesAliasesAndInformativeDescriptions() {
        XCTAssertEqual(catalog.search("rocket").first?.codePoint, 0x1F680)
        XCTAssertTrue(catalog.search("face").contains { $0.codePoint == 0x1F600 })
        XCTAssertTrue(catalog.search("BOM").contains { $0.codePoint == 0xFEFF })
        XCTAssertTrue(catalog.search("snowy weather").contains { $0.codePoint == 0x2603 })
        XCTAssertTrue(catalog.search("European packaging").contains { $0.codePoint == 0x212E })
        let greek = catalog.search("greek omega")
        XCTAssertTrue(greek.contains { $0.codePoint == 0x03A9 })
        XCTAssertTrue(greek.contains { $0.codePoint == 0x03C9 })
        XCTAssertTrue(catalog.search("no_break space").contains { $0.codePoint == 0x00A0 })
    }

    func testSuzhouNumeralsSearchUsesInformativeContextWithoutRenamingCharacters() throws {
        let digits = Set(UInt32(0x3021)...UInt32(0x3029))
        for edition in UnicodeEdition.allCases {
            let catalog = edition.catalog
            for query in ["suzhou numerals", "suzhou", "Suzhou numerals", "hangzhou numerals"] {
                let results = Set(catalog.search(query, order: .codePoint).map(\.codePoint))
                XCTAssertTrue(digits.isSubset(of: results), "\(edition): \(query)")
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
    }

    func testTypedAliasesPreserveFormalCorrectionsAndInformativeNames() throws {
        for edition in UnicodeEdition.allCases {
            let catalog = edition.catalog
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
            let alias = try XCTUnwrap(six.nameAliases.first { $0.name == "yangqin sign slow one half beat" })
            XCTAssertFalse(alias.isFormal)
            XCTAssertEqual(alias.source, "NamesList.txt")
            XCTAssertTrue(six.crossReferences.contains { $0.codePoint == 0x16FF4 && $0.codePointLabel == "U+16FF4" })
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
            let wave = try XCTUnwrap(catalog.character(at: 0x301C))
            XCTAssertTrue(wave.annotations.contains { $0.contains("JIS C 6226") })
            XCTAssertTrue(wave.crossReferences.contains { $0.codePoint == 0x3030 && $0.name == "WAVY DASH" })
            XCTAssertFalse(try XCTUnwrap(catalog.character(at: 0x301D)).annotations.contains { $0.contains("JIS C 6226") })
            XCTAssertNil(catalog.character(at: 0x0378)?.numericValue)
        }
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

    func testBlockNameSearchIncludesCharactersAndRanksExactBlock() {
        let arrows = catalog.search("Arrows", order: .codePoint)
        XCTAssertEqual(arrows.first?.codePoint, 0x2190)
        XCTAssertTrue(arrows.contains { $0.codePoint == 0x2192 })
        XCTAssertTrue(arrows.prefix(112).allSatisfy { $0.blockName == "Arrows" })
        let operators = catalog.search("Mathematical Operators", limit: 50)
        XCTAssertEqual(operators.count, 50)
        XCTAssertTrue(operators.allSatisfy { $0.blockName == "Mathematical Operators" })
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
        XCTAssertFalse(all.contains { $0.codePoint == 0x03A2 })
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
        XCTAssertEqual(catalog.character(at: 0x03A2)?.name, "UNASSIGNED")
        XCTAssertNil(catalog.character(at: 0xD800))
        XCTAssertNil(catalog.character(at: 0x110000))
        for query in ["U+D800", "U+110000", "0xZZZZ", "decimal:-1", "decimal:1114112", "110000"] {
            XCTAssertTrue(catalog.search(query).isEmpty, query)
        }
        XCTAssertTrue(catalog.search("rocket", limit: 0).isEmpty)
        XCTAssertEqual(catalog.search("", limit: 3), catalog.newestCharacters(limit: 3))
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
            XCTAssertEqual(edition.title, "Unicode \(major) · \(edition.rawValue)")
            XCTAssertEqual(edition.catalog.character(at: 0x1FAEB)?.name, "CRACKING FACE")
            XCTAssertEqual(edition.catalog.character(at: 0x1FAEB)?.age, "18.0")
            XCTAssertEqual(edition.catalog.character(at: 0x41)?.age, "1.1")
            XCTAssertNil(edition.catalog.character(at: 0x0378)?.age)
            XCTAssertEqual(edition.catalog.character(at: 0x0378)?.category, "Cn")
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
        XCTAssertNil(catalog.character(at: 0x0378)?.combiningClass)
    }

    func testNumericVersionOrderingAndGlobalPagination() {
        XCTAssertGreaterThan(unicodeVersionKey("10.0"), unicodeVersionKey("9.0"))
        XCTAssertGreaterThan(unicodeVersionKey("15.1"), unicodeVersionKey("15.0"))
        let newest = catalog.orderedCharacters(limit: 300)
        XCTAssertGreaterThanOrEqual(newest.first?.versionSortKey ?? 0, unicodeVersionKey("18.0"))
        XCTAssertTrue(newest.allSatisfy { $0.category != "Cn" })
        for pair in zip(newest, newest.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.versionSortKey, pair.1.versionSortKey)
        }
        XCTAssertEqual(catalog.newestCharacters(offset: 120, limit: 45), Array(newest[120..<165]))
        let oldest = catalog.orderedCharacters(limit: 300, order: .oldestFirst)
        XCTAssertEqual(oldest.first?.codePoint, 0)
        XCTAssertEqual(oldest.first?.age, "1.1")
        XCTAssertEqual(catalog.orderedCharacters(offset: 200, limit: 30, order: .oldestFirst), Array(oldest[200..<230]))
        let codePoints = catalog.orderedCharacters(limit: 300, order: .codePoint)
        XCTAssertEqual(codePoints.map(\.codePoint), codePoints.map(\.codePoint).sorted())
        XCTAssertTrue(catalog.orderedCharacters(offset: 500_000).isEmpty)
        XCTAssertTrue(catalog.orderedCharacters(offset: -1).isEmpty)
    }

    func testSearchSortsEntireMatchSetBeforeLimiting() {
        for order in UnicodeSortOrder.allCases {
            let complete = catalog.search("letter", limit: 100_000, order: order)
            XCTAssertGreaterThan(complete.count, 10_000)
            XCTAssertEqual(catalog.search("letter", limit: 7, order: order), Array(complete.prefix(7)))
            if order == .newestFirst { XCTAssertGreaterThanOrEqual(complete.first?.versionSortKey ?? 0, unicodeVersionKey("18.0")) }
        }
        XCTAssertEqual(catalog.search("rocket", limit: 1).first?.codePoint, 0x1F680)
    }

    func testBlockPaginationOrdersEntireBlockBeforeLimiting() throws {
        let arrows = try XCTUnwrap(catalog.blocks.first { $0.name == "Arrows" })
        let all = catalog.characters(in: arrows, limit: 1000)
        XCTAssertNotEqual(all.first?.codePoint, arrows.start)
        XCTAssertEqual(catalog.characters(in: arrows, limit: 5), Array(all.prefix(5)))
        XCTAssertEqual(catalog.characters(in: arrows, offset: 10, limit: 5), Array(all[10..<15]))
        let oldest = catalog.characters(in: arrows, limit: 1000, order: .oldestFirst)
        XCTAssertEqual(oldest.first?.age, "1.1")
        XCTAssertEqual(catalog.characters(in: arrows, offset: 10, limit: 5, order: .oldestFirst), Array(oldest[10..<15]))
    }
}
