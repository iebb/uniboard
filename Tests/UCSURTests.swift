import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UCSURTests: XCTestCase {
    func testBlocksAreSortedPrivateUseRanges() {
        for (block, next) in zip(UCSUR.blocks, UCSUR.blocks.dropFirst()) {
            XCTAssertLessThanOrEqual(block.start, block.end)
            XCTAssertLessThan(block.end, next.start)
        }
        XCTAssertTrue(UCSUR.blocks.allSatisfy { (0xE000...0xF8FF).contains($0.start) || $0.start >= 0xF0000 })
    }

    func testLookup() {
        XCTAssertEqual(UCSUR.block(containing: 0xF8D0)?.name, "KLINGON")
        XCTAssertEqual(UCSUR.block(containing: 0xE000)?.name, UCSUR.blocks.first?.name)
        XCTAssertEqual(UCSUR.block(containing: 0xF28DF)?.name, "ZBALERMORNA")
        XCTAssertNil(UCSUR.block(containing: 0x41))
        XCTAssertNil(UCSUR.block(containing: 0xF28E0))
    }
}
