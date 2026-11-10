import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class EmojiBrowsingTests: XCTestCase {
    private func entry(_ points: [UInt32], name: String = "fixture", group: String = "People") -> UnicodeEmojiEntry {
        UnicodeEmojiEntry(id: points.map { String(format: "%04X", $0) }.joined(separator: "-"),
                          codePoints: points, name: name, emojiVersion: "1.0", unicodeVersion: "6.0",
                          group: group, subgroup: "Fixture")
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testWholeSequenceProjectionNeverRewritesOrDropsUnmatchedFamilies() {
        let family: [UInt32] = [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]
        let mixedFamily: [UInt32] = [0x1F468, 0x1F3FB, 0x200D, 0x1F469, 0x1F3FF, 0x200D, 0x1F467, 0x1F3FD]
        let orphan: [UInt32] = [0x1F468, 0x1F3FB, 0x200D, 0x1F469, 0x1F3FF, 0x200D, 0x1F466]
        let base = entry(family), toned = entry(mixedFamily), unmatched = entry(orphan)
        XCTAssertEqual(EmojiBrowsingPolicy.project([base, toned, unmatched], skinToneVariants: .fewer), [base, unmatched])
        XCTAssertEqual(EmojiBrowsingPolicy.project([toned, unmatched], skinToneVariants: .fewer), [toned, unmatched])
        XCTAssertEqual(EmojiBrowsingPolicy.project([base, toned, unmatched], skinToneVariants: .all), [base, toned, unmatched])
        XCTAssertEqual(toned.text.unicodeScalars.map(\.value), mixedFamily)
        XCTAssertEqual(unmatched.text.unicodeScalars.map(\.value), orphan)
    }

    func testProjectionDoesNotNormalizeVariationSelectorsZWJGenderOrCanonicalText() {
        let fixtures = [
            entry([0x261D, 0xFE0F]), entry([0x261D, 0x1F3FB]), // exact no-tone base is absent
            entry([0x1F469, 0x200D, 0x1F4BB]), entry([0x1F469, 0x1F3FD, 0x200D, 0x1F4BB]),
            entry([0x1F468, 0x1F3FD, 0x200D, 0x1F4BB]), // different gender, no base
            entry([0x1F469, 0x1F3FD, 0x200D, 0x1F4BB, 0xFE0F]), // extra VS, no base
            entry([0x00E9]), entry([0x65, 0x301, 0x1F3FD]), // canonical String equality must not hide it
            entry([0x1F3FB]) // standalone modifier
        ]
        let result = EmojiBrowsingPolicy.project(fixtures, skinToneVariants: .fewer)
        XCTAssertEqual(result, fixtures.enumerated().filter { $0.offset != 3 }.map(\.element))
        for result in result { XCTAssertEqual(result.text.unicodeScalars.map(\.value), result.codePoints) }
    }

    func testEveryBundledEditionFiltersBeforePagingAndPreservesOriginalEntries() {
        for edition in UnicodeEdition.allCases {
            let catalog = edition.emojiCatalog
            let sequences = Set(catalog.entries.map(\.codePoints))
            let original = catalog.entries
            for order in UnicodeSortOrder.allCases {
                let all = catalog.orderedEntries(order: order)
                let fewer = catalog.orderedEntries(order: order, skinToneVariants: .fewer)
                XCTAssertLessThan(fewer.count, all.count)
                let expected = all.filter { value in
                    let base = value.codePoints.filter { !(0x1F3FB...0x1F3FF).contains($0) }
                    return base == value.codePoints || !sequences.contains(base)
                }
                XCTAssertEqual(fewer, expected)
                let pages = stride(from: 0, to: fewer.count, by: 37).flatMap {
                    catalog.entries(offset: $0, limit: 37, order: order, skinToneVariants: .fewer)
                }
                XCTAssertEqual(pages, fewer)
                XCTAssertEqual(catalog.search("  \n", limit: 37, order: order, skinToneVariants: .fewer), Array(fewer.prefix(37)))
                let hidden: Set<String> = ["People & Body"]
                let shown = catalog.orderedEntries(order: order, hiding: hidden, skinToneVariants: .fewer)
                XCTAssertTrue(shown.allSatisfy { !hidden.contains($0.group) })
                XCTAssertEqual(catalog.entries(offset: 37, limit: 37, order: order, hiding: hidden,
                                               skinToneVariants: .fewer), Array(shown.dropFirst(37).prefix(37)))
            }
            XCTAssertEqual(catalog.entries, original)
        }
    }

    func testAllNonemptySearchesBypassToneFilterIncludingMixedToneAndCodePoints() throws {
        let catalog = EmojiCatalog.shared
        let mixed = try XCTUnwrap(catalog.entries.first {
            Set($0.codePoints.filter { (0x1F3FB...0x1F3FF).contains($0) }).count > 1
        })
        for query in ["light skin tone", "medium-dark skin tone", "U+1F3FF", "1F3FB", "👩🏽‍💻", mixed.text, mixed.id, "person", "family"] {
            XCTAssertEqual(catalog.search(query, limit: 5000, skinToneVariants: .fewer), catalog.search(query, limit: 5000), query)
        }
        XCTAssertEqual(catalog.search(mixed.text, skinToneVariants: .fewer).first, mixed)
        XCTAssertEqual(catalog.search(mixed.text, skinToneVariants: .fewer).first?.text.utf8.map { $0 }, Array(mixed.text.utf8))
        XCTAssertTrue(catalog.search(mixed.text, hiding: [mixed.group], skinToneVariants: .fewer).isEmpty)
    }

    func testAllTwentyFiveMixedTonePairsWithAndWithoutExactWholeBase() {
        let base = entry([0x1FAF1, 0x200D, 0x1FAF2])
        let pairs = (UInt32(0x1F3FB)...UInt32(0x1F3FF)).flatMap { left in
            (UInt32(0x1F3FB)...UInt32(0x1F3FF)).map { right in
                entry([0x1FAF1, left, 0x200D, 0x1FAF2, right])
            }
        }
        XCTAssertEqual(pairs.count, 25)
        XCTAssertEqual(EmojiBrowsingPolicy.project([base] + pairs, skinToneVariants: .fewer), [base])
        // A legacy handshake is not that sequence's exact base: never substitute it.
        let legacyHandshake = entry([0x1F91D])
        XCTAssertEqual(EmojiBrowsingPolicy.project([legacyHandshake] + pairs, skinToneVariants: .fewer), [legacyHandshake] + pairs)
        XCTAssertEqual(EmojiBrowsingPolicy.project([base] + pairs, skinToneVariants: .fewer, query: "skin tone"), [base] + pairs)
    }

    func testSettingsLegacyDefaultsStrictBooleanAndRoundTrip() throws {
        let root = try temporaryDirectory(), setting = EmojiBrowsingSetting(directory: { root })
        XCTAssertEqual(setting.load(), .all)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(EmojiBrowsingSetting.filename).path))
        for value in SkinToneVariants.allCases {
            XCTAssertTrue(setting.save(value))
            XCTAssertEqual(EmojiBrowsingSetting(directory: { root }).load(), value)
            XCTAssertEqual(EmojiBrowsingSetting.decode(EmojiBrowsingSetting.encode(value)), value)
        }
        for bad in ["{}", "{\"schemaVersion\":2,\"fewerVariants\":true}",
                    "{\"schemaVersion\":1,\"fewerVariants\":1}", "{\"schemaVersion\":1,\"fewerVariants\":\"true\"}",
                    "{\"schemaVersion\":1,\"fewerVariants\":null}", "{", String(repeating: " ", count: 257)] {
            let bytes = Data(bad.utf8)
            XCTAssertNil(EmojiBrowsingSetting.decode(bytes))
            try bytes.write(to: root.appendingPathComponent(EmojiBrowsingSetting.filename))
            XCTAssertEqual(setting.load(), .all)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(EmojiBrowsingSetting.filename)), bytes,
                           "An unreadable preference must not be rewritten on load")
        }
        XCTAssertFalse(EmojiBrowsingSetting(directory: { nil }).save(.fewer))
    }

    func testRootPreferenceSurvivesLegacyConfigurationMigrationAndDoesNotMutateOtherFiles() throws {
        let root = try temporaryDirectory(), setting = EmojiBrowsingSetting(directory: { root })
        let location = SharedConfigurationLocation(root: { root })
        let categories = EmojiCategorySetting(directory: { root })
        XCTAssertTrue(categories.save(["Flags"]))
        let originalCategories = try Data(contentsOf: root.appendingPathComponent(EmojiCategorySetting.filename))
        let favorites = Data("saved 👩🏽‍💻 and recent 👨🏻‍🤝‍👨🏿".utf8)
        let savedURL = root.appendingPathComponent("saved-fixture.txt")
        try favorites.write(to: savedURL)
        XCTAssertEqual(setting.load(), .all)
        XCTAssertTrue(setting.save(.fewer))
        let originalPreference = try Data(contentsOf: root.appendingPathComponent(EmojiBrowsingSetting.filename))
        let presentation = AppPresentationSettings.encode(.init(integers: ["emojiColumns": 7]))
        guard case .applied = location.migrateIfNeeded(presentation: presentation) else {
            return XCTFail("Expected legacy migration to publish a generation")
        }
        XCTAssertNotEqual(location.currentDirectory(), root)
        XCTAssertEqual(setting.load(), .fewer)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(EmojiBrowsingSetting.filename)), originalPreference)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(EmojiCategorySetting.filename)), originalCategories)
        XCTAssertEqual(try Data(contentsOf: savedURL), favorites)
        XCTAssertFalse(SharedConfigurationLocation.snapshotFiles.contains(EmojiBrowsingSetting.filename))
        XCTAssertTrue(setting.save(.all))
        XCTAssertEqual(try Data(contentsOf: savedURL), favorites)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(EmojiCategorySetting.filename)), originalCategories)
    }

    func testFailedAtomicSaveDoesNotFollowSymlinkOrReplaceTarget() throws {
        let root = try temporaryDirectory(), setting = EmojiBrowsingSetting(directory: { root })
        let target = root.appendingPathComponent("unrelated.json")
        let original = Data("keep exact bytes".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(EmojiBrowsingSetting.filename), withDestinationURL: target)
        XCTAssertFalse(setting.save(.fewer))
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(setting.load(), .all)
    }
}
