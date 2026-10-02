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

    func testBlockNameSearchIncludesCharactersAndRanksExactBlock() {
        let arrows = catalog.search("Arrows")
        XCTAssertEqual(arrows.first?.codePoint, 0x2190)
        XCTAssertTrue(arrows.contains { $0.codePoint == 0x2192 })
        XCTAssertTrue(arrows.prefix(112).allSatisfy { $0.blockName == "Arrows" })
        let operators = catalog.search("Mathematical Operators", limit: 50)
        XCTAssertEqual(operators.count, 50)
        XCTAssertTrue(operators.allSatisfy { $0.blockName == "Mathematical Operators" })
        XCTAssertEqual(catalog.search("CJK Unified Ideographs Extension B", limit: 3).map(\.codePoint),
                       [0x20000, 0x20001, 0x20002])
        XCTAssertTrue(catalog.search("Greek").contains { $0.codePoint == 0x03A9 })
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
        XCTAssertEqual(catalog.characters(in: cjk, offset: 256, limit: 3).map(\.codePoint),
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
        XCTAssertEqual(catalog.search("", limit: 3), Array(catalog.featured.prefix(3)))
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
}
