#if canImport(UIKit)
import XCTest
@testable import Uniboard

final class CustomFontStoreTests: XCTestCase {
    func testCoverageRangesComeFromTheCharacterMapWithoutSurrogates() {
        let set = CFCharacterSetCreateMutable(nil)!
        CFCharacterSetAddCharactersInRange(set, CFRange(location: 0x41, length: 3))
        CFCharacterSetAddCharactersInRange(set, CFRange(location: 0xE000, length: 1))
        CFCharacterSetAddCharactersInRange(set, CFRange(location: 0xF0000, length: 2))
        XCTAssertEqual(CustomFontStore.ranges(set), [[0x41, 0x43], [0xE000, 0xE000], [0xF0000, 0xF0001]])
    }

    func testOnlyRealFontsAreAddedAndAnEmptyStoreHasNone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = CustomFontStore(directory: directory)
        XCTAssertTrue(store.fonts.isEmpty)
        XCTAssertEqual(store.revision, "")
        XCTAssertThrowsError(try store.add(Data("not a font".utf8)))
        XCTAssertThrowsError(try store.add(Data([0, 1, 0, 0] + Array(repeating: 0, count: 16))), "A font header alone is not a font")
        XCTAssertNil(store.url(forFilename: "Custom-0123456789abcdef.ttf"), "Only added fonts resolve")
        XCTAssertNil(store.url(forFilename: "../escape.ttf"))
        XCTAssertThrowsError(try CustomFontStore(directory: nil).add(Data()))
    }
}
#endif
