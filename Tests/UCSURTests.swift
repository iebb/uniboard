import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UCSURTests: XCTestCase {
    func testBundledRegistryHasSortedBlocksAndCharacters() throws {
        let registry = UCSUR.registry
        XCTAssertEqual(registry.blocks.count, 79)
        XCTAssertGreaterThan(registry.entries.count, 9000)
        XCTAssertTrue(zip(registry.blocks, registry.blocks.dropFirst()).allSatisfy { $0.end < $1.start })
        XCTAssertEqual(UCSUR.block(containing: 0xF8D0)?.name, "Klingon")
        XCTAssertEqual(UCSUR.block(containing: 0xF28DF)?.name, "Zbalermorna")
        XCTAssertNil(UCSUR.block(containing: 0x41))
        XCTAssertNil(UCSUR.block(containing: 0xF28E0))
        let tinco = try XCTUnwrap(UCSUR.entry(at: 0xE000))
        XCTAssertEqual(tinco.name, "TENGWAR LETTER TINCO")
        XCTAssertEqual(UCSUR.entry(at: 0xE008)?.aliases, ["suule"])
        XCTAssertEqual(UCSUR.entry(at: 0xF8D0)?.section, "Letters")
        XCTAssertNil(UCSUR.entry(at: 0xEBE0), "Kaktovik numerals left the registry for Unicode")
        XCTAssertNil(UCSUR.entry(at: 0x10FFFD))
    }

    func testParsingKeepsOnlyOrderedPrivateUseLines() {
        let fields = ["E001", "X LETTER B", "Lu", "0", "L", "", "Decimal", "1", "", "E002", "", "Letters", "bee|be"]
        let text = [
            "# comment",
            "@E000\tE00F\tX", "@E000\tE00F\tDuplicate", "@0041\t0042\tLatin", "@E020\tE010\tBackwards", "@E030\tE03F",
            "E000\tX LETTER A\tLo\t0\t\t\t\t\t\t\t\t\t",
            fields.joined(separator: "\t"),
            "E001\tX LETTER B AGAIN\tLo\t0\t\t\t\t\t\t\t\t\t",
            "0041\tLATIN\tLu\t0\t\t\t\t\t\t\t\t\t", "E003\t\tLo\t0\t\t\t\t\t\t\t\t\t",
            "E004\tX\tLetter\t0\t\t\t\t\t\t\t\t\t", "E005\tX\tLo\tzero\t\t\t\t\t\t\t\t\t", "E006\tshort",
        ].joined(separator: "\n")
        let registry = UCSUR.parse(text)
        XCTAssertEqual(registry.blocks, [UCSUR.Block(start: 0xE000, end: 0xE00F, name: "X")])
        XCTAssertEqual(registry.entries.map(\.name), ["X LETTER A", "X LETTER B"])
        let b = registry.entries[1]
        XCTAssertEqual(b.numericType, "Decimal"); XCTAssertEqual(b.numericValue, "1")
        XCTAssertEqual(b.lowercase, 0xE002); XCTAssertNil(b.uppercase); XCTAssertNil(b.decomposition)
        XCTAssertEqual(b.aliases, ["bee", "be"])
        XCTAssertNil(registry.entries[0].bidirectionalClass)
        XCTAssertNil(registry.entry(at: 0xE003)); XCTAssertNil(registry.block(containing: 0xE010))
        XCTAssertTrue(UCSUR.parse("").entries.isEmpty)

        let character = b.character(blockName: "X", age: "1.1", versionSortKey: 7, script: nil)
        XCTAssertEqual(character.name, "X LETTER B")
        XCTAssertEqual(character.nameAliases.map(\.kindLabel), ["Informative alias", "Informative alias"])
        XCTAssertEqual(character.namesListSection, "Letters")
        XCTAssertFalse(character.isInvisible)
        let space = UCSUR.parse("E000\tX SPACE\tZs\t0\tWS\t\t\t\t\t\t\t\t").entries[0]
        XCTAssertTrue(space.character(blockName: "X", age: nil, versionSortKey: 0, script: nil).isInvisible)
    }

    func testPrivateUseAreasSplitAroundRegistryBlocks() {
        XCTAssertTrue(UCSUR.isPrivateUse(0xE000) && UCSUR.isPrivateUse(0xF0000) && UCSUR.isPrivateUse(0x10FFFD))
        XCTAssertFalse(UCSUR.isPrivateUse(0xF900) || UCSUR.isPrivateUse(0xFFFFE) || UCSUR.isPrivateUse(0x10FFFF))
        let blocks = [UnicodeBlock(name: "Latin", start: 0, end: 0x7F),
                      UnicodeBlock(name: "Private Use Area", start: 0xE000, end: 0xF8FF),
                      UnicodeBlock(name: "Supplementary Private Use Area-B", start: 0x100000, end: 0x10FFFF)]
        let registry = [UCSUR.Block(start: 0xE000, end: 0xE07F, name: "Tengwar"),
                        UCSUR.Block(start: 0xF8D0, end: 0xF8FF, name: "Klingon")]
        XCTAssertEqual(UCSUR.splitting(blocks, with: registry).map(\.name),
                       ["Latin", "Tengwar", "Private Use Area", "Klingon", "Supplementary Private Use Area-B"])
        XCTAssertEqual(UCSUR.splitting(blocks, with: registry)[2].end, 0xF8CF)
        XCTAssertEqual(UCSUR.splitting([UnicodeBlock(name: "Private Use Area", start: 0xE000, end: 0xF8FF)],
                                       with: [UCSUR.Block(start: 0xE080, end: 0xE0FF, name: "Cirth")]).map(\.start),
                       [0xE000, 0xE080, 0xE100])
    }
}
