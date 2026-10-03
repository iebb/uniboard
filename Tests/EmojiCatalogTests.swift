import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class EmojiCatalogTests: XCTestCase {
    func testBothOfficialEditionsAndUniqueFullyQualifiedEntries() {
        for edition in UnicodeEdition.allCases {
            let catalog = edition.emojiCatalog
            XCTAssertNil(catalog.resourceError)
            XCTAssertGreaterThan(catalog.entries.count, 3900)
            XCTAssertEqual(Set(catalog.entries.map(\.id)).count, catalog.entries.count)
            XCTAssertTrue(catalog.entries.allSatisfy { !$0.name.isEmpty && !$0.group.isEmpty && !$0.subgroup.isEmpty })
            XCTAssertGreaterThanOrEqual(catalog.entries.first?.versionSortKey ?? 0, unicodeVersionKey("18.0"))
            XCTAssertLessThanOrEqual(catalog.entries.first?.versionSortKey ?? 0, unicodeVersionKey(catalog.unicodeVersion))
            XCTAssertEqual(catalog.unicodeVersion, edition.catalog.version)
        }
        XCTAssertFalse(UnicodeEdition.latest.emojiCatalog.version.contains("draft"))
        XCTAssertTrue(UnicodeEdition.draft.emojiCatalog.version.hasSuffix(" draft"))
    }

    func testEditionFilesDoNotMixTheirEntries() throws {
        // Distinct tiny fixture sets exercise edition isolation independently of
        // today's upstream draft, whose assigned set still equals the final set.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for edition in UnicodeEdition.allCases {
            let cp: UInt32 = edition == .latest ? 0x1F680 : 0x1F600
            let name = edition == .latest ? "rocket" : "grinning face"
            let entry: [String: Any] = ["id": String(format: "%04X", cp), "codePoints": [cp],
                "name": name, "emojiVersion": "1.0", "unicodeVersion": "6.0",
                "group": "Fixture", "subgroup": "Fixture"]
            let document: [String: Any] = ["version": edition == .latest ? "18.0" : "19.0 draft",
                "unicodeVersion": edition == .latest ? "18.0.0" : "19.0.0 draft", "entries": [entry]]
            try JSONSerialization.data(withJSONObject: document)
                .write(to: directory.appendingPathComponent("EmojiCatalog-\(edition.rawValue).json"))
        }
        let latest = EmojiCatalog(edition: .latest, resourceURL: directory)
        let draft = EmojiCatalog(edition: .draft, resourceURL: directory)
        XCTAssertNil(latest.resourceError)
        XCTAssertNil(draft.resourceError)
        XCTAssertEqual(latest.search("rocket").first?.text, "🚀")
        XCTAssertTrue(latest.search("grinning face").isEmpty)
        XCTAssertEqual(draft.search("grinning face").first?.text, "😀")
        XCTAssertTrue(draft.search("rocket").isEmpty)
    }

    func testExactZWJAndVariationSelectorInsertion() throws {
        let emoji = try XCTUnwrap(EmojiCatalog.shared.search("head shaking horizontally", limit: 1).first)
        XCTAssertEqual(emoji.id, "1F642-200D-2194-FE0F")
        XCTAssertEqual(emoji.codePoints, [0x1F642, 0x200D, 0x2194, 0xFE0F])
        XCTAssertEqual(emoji.text, "🙂‍↔️")
        XCTAssertEqual(emoji.text.unicodeScalars.map(\.value), emoji.codePoints)
        XCTAssertEqual(emoji.codePointLabel, "U+1F642 U+200D U+2194 U+FE0F")
        XCTAssertEqual(emoji.emojiVersion, "15.1")
        XCTAssertEqual(emoji.unicodeVersion, "7.0")
        XCTAssertNotEqual(emoji.versionSortKey, emoji.unicodeVersionSortKey)
        XCTAssertEqual(EmojiCatalog.shared.search(emoji.text).first, emoji)
        XCTAssertEqual(EmojiCatalog.shared.search(emoji.codePointLabel).first, emoji)
        XCTAssertEqual(EmojiCatalog.shared.search(emoji.id).first, emoji)
    }

    func testCompleteKeycapsFlagsAndSkinToneSequences() throws {
        let catalog = EmojiCatalog.shared
        for points: [UInt32] in [[0x31, 0xFE0F, 0x20E3], [0x1F1EF, 0x1F1F5],
                                [0x1F469, 0x1F3FD, 0x200D, 0x1F4BB]] {
            let id = points.map { String(format: "%04X", $0) }.joined(separator: "-")
            let entry = try XCTUnwrap(catalog.entries.first { $0.id == id })
            XCTAssertEqual(entry.text.unicodeScalars.map(\.value), points)
            XCTAssertEqual(catalog.search(entry.text).first, entry)
        }
        let technologist = try XCTUnwrap(catalog.search("woman technologist", limit: 1, order: .codePoint).first)
        XCTAssertEqual(technologist.id, "1F469-200D-1F4BB")
        XCTAssertEqual(technologist.text, "👩‍💻")
    }

    func testEmojiSearchAndPaginationApplyGlobalOrderBeforeLimit() {
        let catalog = EmojiCatalog.shared
        for order in UnicodeSortOrder.allCases {
            let all = catalog.orderedEntries(order: order)
            XCTAssertEqual(catalog.entries(offset: 200, limit: 30, order: order), Array(all[200..<230]))
            let faces = catalog.search("face", limit: 5000, order: order)
            XCTAssertGreaterThan(faces.count, 50)
            XCTAssertEqual(catalog.search("face", limit: 5, order: order), Array(faces.prefix(5)))
            let people = catalog.search("People Body", limit: 5000, order: order)
            XCTAssertFalse(people.isEmpty)
            XCTAssertTrue(people.allSatisfy { $0.group == "People & Body" })
        }
        XCTAssertEqual(catalog.search("U+1FAEB").first?.name, "cracking face")
        XCTAssertTrue(catalog.search("not a real emoji name zzzz").isEmpty)
        XCTAssertTrue(catalog.search("U+D800").isEmpty)
        XCTAssertTrue(catalog.search("U+110000").isEmpty)
        XCTAssertTrue(catalog.search("0xZZZZ").isEmpty)
        XCTAssertTrue(catalog.search("face", limit: 0).isEmpty)
        XCTAssertTrue(catalog.entries(offset: -1).isEmpty)
    }
}
