import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class EmojiCatalogTests: XCTestCase {
    private func entry(_ points: [UInt32] = [0x1F680], name: String = "fixture rocket", version: String = "1.0") -> [String: Any] {
        ["id": points.map { String(format: "%04X", $0) }.joined(separator: "-"), "codePoints": points,
         "name": name, "emojiVersion": version, "unicodeVersion": "6.0", "group": "Fixture", "subgroup": "Symbols"]
    }
    private func fixture(_ entries: [[String: Any]], version: String = "18.0", unicode: String = "18.0.0") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("EmojiCatalog-latest.json")
        try JSONSerialization.data(withJSONObject: ["version": version, "unicodeVersion": unicode, "entries": entries])
            .write(to: url)
        return url
    }

    func testBareHexadecimalScalarAndSequenceQueriesPreserveExactQualifiedText() throws {
        let catalog = EmojiCatalog.latest
        let rocket = try XCTUnwrap(catalog.search("1F680").first)
        XCTAssertEqual(rocket.codePoints, [0x1F680])
        XCTAssertEqual(rocket.text, "🚀")
        XCTAssertEqual(catalog.search("1f680"), catalog.search("U+1F680"))
        let horizontal = try XCTUnwrap(catalog.search("1F642 200D 2194 FE0F").first)
        XCTAssertEqual(horizontal.codePoints, [0x1F642, 0x200D, 0x2194, 0xFE0F])
        XCTAssertEqual(horizontal.text, "🙂‍↔️")
        XCTAssertEqual(catalog.search("1F642-200D-2194-FE0F").first, horizontal)
        XCTAssertTrue(catalog.search("face").contains { $0.codePoints == [0x1F600] },
                      "A hex-looking ordinary word must still be searched as text")
    }

    func testAllOfficialEditionsAndUniqueFullyQualifiedEntries() {
        for edition in UnicodeEdition.allCases {
            let catalog = edition.emojiCatalog
            XCTAssertNil(catalog.resourceError)
            XCTAssertGreaterThan(catalog.entries.count, 3700)
            XCTAssertEqual(Set(catalog.entries.map(\.id)).count, catalog.entries.count)
            XCTAssertTrue(catalog.entries.allSatisfy { !$0.name.isEmpty && !$0.group.isEmpty && !$0.subgroup.isEmpty })
            let newest = catalog.orderedEntries(order: .newestFirst).first
            XCTAssertGreaterThanOrEqual(newest?.versionSortKey ?? 0, unicodeVersionKey("16.0"))
            XCTAssertLessThanOrEqual(newest?.versionSortKey ?? 0, unicodeVersionKey(catalog.unicodeVersion))
            XCTAssertEqual(catalog.unicodeVersion, edition.catalog.version)
        }
        XCTAssertFalse(UnicodeEdition.latest.emojiCatalog.version.contains("draft"))
        XCTAssertTrue(UnicodeEdition.draft.emojiCatalog.version.hasSuffix(" draft"))
    }

    func testEditionFilesDoNotMixTheirEntries() throws {
        // Distinct tiny fixture sets exercise all four slots independently of
        // today's upstream draft, whose assigned set can equal the final set.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures: [(UnicodeEdition, UInt32, String, String)] = [
            (.latest, 0x1F680, "rocket", "18.0"), (.previous, 0x1F600, "grinning face", "17.0"),
            (.older, 0x2603, "snowman", "16.0"), (.draft, 0x1F6F0, "satellite", "19.0")]
        for (edition, cp, name, number) in fixtures {
            let entry: [String: Any] = ["id": String(format: "%04X", cp), "codePoints": [cp],
                "name": name, "emojiVersion": "1.0", "unicodeVersion": "6.0",
                "group": "Fixture", "subgroup": "Fixture"]
            let suffix = edition == .draft ? " draft" : ""
            let document: [String: Any] = ["version": number + suffix, "edition": edition.rawValue,
                "unicodeVersion": number + ".0" + suffix, "entries": [entry]]
            try JSONSerialization.data(withJSONObject: document)
                .write(to: directory.appendingPathComponent("EmojiCatalog-\(edition.rawValue).json"))
        }
        for (edition, cp, name, _) in fixtures {
            let catalog = EmojiCatalog(edition: edition, resourceURL: directory)
            XCTAssertNil(catalog.resourceError)
            XCTAssertEqual(catalog.search(name).first?.codePoints, [cp])
            for (_, other, otherName, _) in fixtures where other != cp {
                XCTAssertTrue(catalog.search(otherName).isEmpty)
            }
        }
        // A complete but swapped historical document must fail closed, even
        // though both editions are final and all scalar sequences are valid.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("EmojiCatalog-previous.json"))
        try FileManager.default.copyItem(at: directory.appendingPathComponent("EmojiCatalog-older.json"),
                                        to: directory.appendingPathComponent("EmojiCatalog-previous.json"))
        XCTAssertNotNil(EmojiCatalog(edition: .previous, resourceURL: directory).resourceError)
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

    func testHistoricalEmojiSetsExcludeNewerIntroductionsWithoutChangingSequences() throws {
        for edition in [UnicodeEdition.older, .previous, .latest] {
            let catalog = edition.emojiCatalog
            let key = unicodeVersionKey(edition.versionLabel)
            for (point, version): (UInt32, String) in [(0x1FAE9, "16.0"), (0x1FAEA, "17.0"), (0x1FAEB, "18.0")] {
                let entry = catalog.entries.first { $0.codePoints == [point] }
                if key >= unicodeVersionKey(version) {
                    XCTAssertEqual(try XCTUnwrap(entry).emojiVersion, version)
                } else {
                    XCTAssertNil(entry)
                    XCTAssertTrue(catalog.search(String(format: "U+%04X", point)).isEmpty)
                }
            }
            let sequence = try XCTUnwrap(catalog.search("head shaking horizontally", limit: 1).first)
            XCTAssertEqual(sequence.codePoints, [0x1F642, 0x200D, 0x2194, 0xFE0F])
            XCTAssertEqual(sequence.text.unicodeScalars.map(\.value), sequence.codePoints)
        }
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

    func testMalformedDocumentsIDsAndScalarSequencesFailAsAWhole() throws {
        var invalid: [[[String: Any]]] = [[], [entry(), entry()]]
        for (field, value): (String, Any) in [
            ("id", "rocket-alias"), ("id", "1f680"), ("codePoints", [UInt32(0xD800)]),
            ("codePoints", [UInt32.max]), ("codePoints", [UInt32]()), ("name", " \n"),
            ("group", " "), ("subgroup", ""), ("emojiVersion", "99.0"),
            ("emojiVersion", "\(Int.max).0"), ("emojiVersion", "18.0 draft"), ("unicodeVersion", "999.0"),
            ("unicodeVersion", "Pending draft age")
        ] {
            var bad = entry()
            bad[field] = value
            invalid.append([bad])
        }
        var alias = entry()
        alias["id"] = "different-but-same-sequence"
        invalid.append([entry(), alias])
        for records in invalid {
            let url = try fixture(records)
            let broken = EmojiCatalog(edition: .latest, resourceURL: url)
            XCTAssertNotNil(broken.resourceError)
            XCTAssertEqual(broken.version, "Unavailable")
            XCTAssertTrue(broken.entries.isEmpty)
            XCTAssertTrue(broken.search("rocket").isEmpty)
        }
    }

    func testMissingTruncatedAndMixedEditionEmojiResourcesFailClosed() throws {
        let url = try fixture([entry()])
        let complete = try Data(contentsOf: url)
        for length in [0, 1, complete.count / 2, complete.count - 1] {
            try complete.prefix(length).write(to: url)
            XCTAssertNotNil(EmojiCatalog(edition: .latest, resourceURL: url).resourceError)
        }
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(EmojiCatalog(edition: .latest, resourceURL: url.deletingLastPathComponent()).entries.isEmpty)
        for (version, unicode) in [("19.0 draft", "19.0.0 draft"), ("18.0", "19.0.0"), ("", "18.0.0") ] {
            let mixed = try fixture([entry()], version: version, unicode: unicode)
            XCTAssertNotNil(EmojiCatalog(edition: .latest, resourceURL: mixed).resourceError)
        }
        let draftFile = try fixture([entry()], version: "19.0 draft", unicode: "19.0.0 draft")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: draftFile)) as? [String: Any])
        var pending = entry()
        pending["unicodeVersion"] = "Pending draft age"
        document["entries"] = [pending]
        try JSONSerialization.data(withJSONObject: document).write(to: draftFile)
        let draft = EmojiCatalog(edition: .draft, resourceURL: draftFile)
        XCTAssertNil(draft.resourceError)
        XCTAssertEqual(draft.entries.first?.unicodeVersionSortKey, 0)
    }

    func testInjectedNumericAgeOrderAndAllPageBoundaries() throws {
        let records = [entry([0x1F680], version: "9.0"), entry([0x1F600], name: "fixture face", version: "10.0"),
                       entry([0x1F642, 0x200D, 0x2194, 0xFE0F], name: "fixture horizontal", version: "15.1")]
        let url = try fixture(records), catalog = EmojiCatalog(edition: .latest, resourceURL: url.deletingLastPathComponent())
        XCTAssertNil(catalog.resourceError)
        let expected: [UnicodeSortOrder: [String]] = [
            .newestFirst: ["1F642-200D-2194-FE0F", "1F600", "1F680"],
            .oldestFirst: ["1F680", "1F600", "1F642-200D-2194-FE0F"],
            .codePoint: ["1F600", "1F642-200D-2194-FE0F", "1F680"]]
        for order in UnicodeSortOrder.allCases {
            let all = catalog.entries(limit: Int.max, order: order)
            XCTAssertEqual(all.map(\.id), expected[order])
            XCTAssertEqual(catalog.search("fixture", limit: Int.max, order: order), all)
            XCTAssertEqual(catalog.search("", limit: 2, order: order), Array(all.prefix(2)))
            for size in 1...4 {
                let pages = stride(from: 0, to: all.count, by: size).flatMap { catalog.entries(offset: $0, limit: size, order: order) }
                XCTAssertEqual(pages, all)
            }
            XCTAssertTrue(catalog.entries(offset: Int.max, limit: Int.max, order: order).isEmpty)
        }
        XCTAssertTrue(catalog.entries(limit: -1).isEmpty)
    }

    func testCodePointVariantsRemainExactAndMalformedSignedOrEmptyComponentsDoNotMatch() throws {
        let catalog = EmojiCatalog.latest
        for query in ["0x1F680", "decimal:128640", "u+1f680", "U+1F642, U+200D, U+2194, U+FE0F", "🙂‍↔"] {
            XCTAssertFalse(catalog.search(query).isEmpty, query)
        }
        XCTAssertEqual(catalog.search("U+1F642 200D 2194 FE0F").first?.text, "🙂‍↔️")
        XCTAssertTrue(catalog.search("1F469").contains { $0.codePoints.count > 1 })
        for query in ["-1F680", "1F680-", "1F680--200D", "U++1F680", "decimal:+128640", "decimal:١٢٨٦٤٠", "decimal:-1", "0x", ",1F680"] {
            XCTAssertTrue(catalog.search(query).isEmpty, query)
        }
        XCTAssertTrue(catalog.search("!!!").isEmpty)
    }

    func testInvalidDirectEntryCannotSilentlyInsertOnlyValidComponents() {
        let broken = UnicodeEmojiEntry(id: "invalid", codePoints: [0x1F469, 0xD800, 0x1F4BB], name: "invalid",
            emojiVersion: "1.0", unicodeVersion: "6.0", group: "Fixture", subgroup: "Fixture")
        XCTAssertEqual(broken.text, "")
    }

    func testCancelledEmojiQueriesAndPaginationReturnNoStaleResults() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let catalog = EmojiCatalog.shared
            return catalog.search("face", limit: Int.max).isEmpty && catalog.entries(limit: Int.max).isEmpty
                && catalog.orderedEntries(order: .oldestFirst).isEmpty
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }

    func testEmojiSearchUTF8BoundaryAndStableRepeatedTerms() throws {
        let url = try fixture([entry(name: "rocket", version: "1.0"), entry([0x1F600], name: "rocket rocket", version: "10.0")])
        let fixture = EmojiCatalog(edition: .latest, resourceURL: url)
        let boundary = "🚀" + String(repeating: " ", count: 4092)
        XCTAssertEqual(fixture.search(boundary).first?.codePoints, [0x1F680])
        XCTAssertTrue(fixture.search(boundary + " ").isEmpty)
        XCTAssertTrue(fixture.search(String(repeating: "🚀", count: 1025)).isEmpty)
        for order in UnicodeSortOrder.allCases {
            XCTAssertEqual(fixture.search("rocket rocket rocket", order: order), fixture.search("rocket", order: order))
            XCTAssertEqual(fixture.search(String(repeating: "rocket ", count: 585), order: order), fixture.search("rocket", order: order))
        }
    }

    func testEmojiWholeWordTierIncludesGroupAndSubgroupAndPrecedesSubstringTier() throws {
        var group = entry([0x1F604], name: "other", version: "6.0")
        group["group"] = "art"
        var subgroup = entry([0x1F605], name: "other", version: "18.0")
        subgroup["subgroup"] = "art word"
        let url = try fixture([entry([0x1F600], name: "cart", version: "18.0"),
            entry([0x1F601], name: "art", version: "1.0"), entry([0x1F602], name: "art word", version: "10.0"),
            entry([0x1F603], name: "earth word", version: "9.0"), group, subgroup])
        let fixture = EmojiCatalog(edition: .latest, resourceURL: url)
        XCTAssertNil(fixture.resourceError)
        let expected: [UnicodeSortOrder: [UInt32]] = [
            .codePoint: [0x1F601, 0x1F602, 0x1F604, 0x1F605, 0x1F600, 0x1F603],
            .newestFirst: [0x1F605, 0x1F602, 0x1F604, 0x1F601, 0x1F600, 0x1F603],
            .oldestFirst: [0x1F601, 0x1F604, 0x1F602, 0x1F605, 0x1F603, 0x1F600]]
        for order in UnicodeSortOrder.allCases {
            let points = try XCTUnwrap(expected[order])
            XCTAssertEqual(fixture.search("art", limit: Int.max, order: order).map { $0.codePoints[0] }, points)
            XCTAssertEqual(fixture.search("art", limit: 3, order: order).map { $0.codePoints[0] }, Array(points.prefix(3)))
            XCTAssertEqual(fixture.search("art art", order: order), fixture.search("art", order: order))
        }
        XCTAssertEqual(fixture.search("art word").map { $0.codePoints[0] }, [0x1F602, 0x1F605, 0x1F603])
        XCTAssertEqual(fixture.search("word-art").map { $0.codePoints[0] }, [0x1F602, 0x1F605, 0x1F603])
    }

    func testEmojiUnicodeBoundariesAndDefaultAscendingBrowsePreserveExactSequences() throws {
        let sequence: [UInt32] = [0x1F469, 0x200D, 0x1F4BB]
        let url = try fixture([entry([0x1F600], name: "mélange", version: "18.0"),
            entry([0x1F601], name: "élan", version: "1.0"),
            entry(sequence, name: "woman technologist", version: "4.0")])
        let fixture = EmojiCatalog(edition: .latest, resourceURL: url)
        XCTAssertNil(fixture.resourceError)
        for query in ["élan", "ÉLAN", "ｅｌａｎ", "(elan)"] {
            XCTAssertEqual(fixture.search(query).map { $0.codePoints[0] }, [0x1F601, 0x1F600], query)
        }
        XCTAssertEqual(fixture.entries.map(\.codePoints), [sequence, [0x1F600], [0x1F601]])
        XCTAssertEqual(fixture.orderedEntries(), fixture.entries)
        XCTAssertEqual(fixture.entries(offset: 1, limit: 2), Array(fixture.entries.dropFirst()))
        XCTAssertEqual(fixture.search(" \n"), fixture.entries)
        for query in ["👩‍💻", "1F469-200D-1F4BB", "U+1F469 U+200D U+1F4BB"] {
            XCTAssertEqual(fixture.search(query).map(\.codePoints), [sequence])
            XCTAssertEqual(fixture.search(query).first?.text.unicodeScalars.map(\.value), sequence)
        }
    }
}
