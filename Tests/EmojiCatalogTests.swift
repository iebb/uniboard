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
    private func fixture(_ entries: [[String: Any]], version: String = "19.0 draft", unicode: String = "19.0.0 draft") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("EmojiCatalog-draft.json")
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

    func testFinalEditionsShowOnlyEmojiOfTheirVersion() throws {
        let records = [entry([0x2603], name: "snowman", version: "16.0"), entry([0x1F600], name: "grinning face", version: "17.0"),
                       entry([0x1F680], name: "rocket", version: "18.0"), entry([0x1F6F0], name: "satellite", version: "19.0")]
            .map { record -> [String: Any] in var copy = record; copy["unicodeVersion"] = record["emojiVersion"]; return copy }
        let draft = EmojiCatalog(resourceURL: try fixture(records))
        XCTAssertNil(draft.resourceError)
        XCTAssertTrue(draft.limited(to: .draft) === draft)
        let labels = [UnicodeEdition.latest, .previous, .older].map(\.versionLabel)
        XCTAssertEqual(labels, ["18.0.0", "17.0.0", "16.0.0"], "Labels come from the draft's manifest")
        for (edition, names) in [(UnicodeEdition.latest, ["snowman", "grinning face", "rocket"]),
                                 (.previous, ["snowman", "grinning face"]), (.older, ["snowman"])] {
            let limited = draft.limited(to: edition)
            XCTAssertNil(limited.resourceError)
            XCTAssertEqual(limited.unicodeVersion, edition.versionLabel)
            XCTAssertEqual(Set(limited.entries.map(\.name)), Set(names), edition.rawValue)
            XCTAssertTrue(limited.search("satellite").isEmpty, "A later emoji is not part of \(edition.rawValue)")
            XCTAssertEqual(limited.addedEntries.map(\.name), [names.last!], "What's New lists that version's emoji")
        }
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

    func testEntryLookupsByIDAndTextMatchLinearSearchInEveryEdition() {
        for edition in UnicodeEdition.allCases {
            let catalog = edition.emojiCatalog
            // Ids and exact texts are unique, so a linear first match finds each entry itself.
            XCTAssertEqual(Set(catalog.entries.map(\.id)).count, catalog.entries.count)
            XCTAssertEqual(Set(catalog.entries.map { Array($0.text.utf16) }).count, catalog.entries.count)
            for emoji in catalog.entries {
                XCTAssertEqual(catalog.entry(id: emoji.id), emoji, emoji.id)
                XCTAssertEqual(catalog.entry(text: emoji.text), emoji, emoji.id)
            }
            for emoji in catalog.entries.enumerated().filter({ $0.offset % 97 == 0 }).map(\.element) {
                XCTAssertEqual(catalog.entry(id: emoji.id), catalog.entries.first { $0.id == emoji.id }, emoji.id)
                XCTAssertEqual(catalog.entry(text: emoji.text), catalog.entries.first { SymbolBoardKey.exact($0.text, emoji.text) }, emoji.id)
            }
            for missing in ["", "A", "not-an-id", "1F680-FFFF", "\u{1F680}\u{1F680}"] {
                XCTAssertNil(catalog.entry(id: missing), missing)
                XCTAssertNil(catalog.entry(text: missing), missing)
            }
        }
    }

    func testEntryTextLookupIsExactUTF16AndIndexesAreThreadSafe() throws {
        // Canonically equivalent, so equal as Strings, but different sequences.
        let catalog = EmojiCatalog(resourceURL: try fixture([entry([0x00C5], name: "precomposed"),
                                                             entry([0x0041, 0x030A], name: "decomposed")]))
        XCTAssertNil(catalog.resourceError)
        XCTAssertEqual(catalog.entry(text: "\u{00C5}")?.name, "precomposed")
        XCTAssertEqual(catalog.entry(text: "A\u{030A}")?.name, "decomposed")
        XCTAssertNil(catalog.entry(text: "\u{212B}"), "Angstrom sign: equivalent, but not the same code units")
        XCTAssertNil(catalog.entry(text: "A"))
        XCTAssertEqual(catalog.entry(id: "0041-030A")?.name, "decomposed")

        let fresh = EmojiCatalog()
        var found = [String?](repeating: nil, count: fresh.entries.count)
        found.withUnsafeMutableBufferPointer { results in
            DispatchQueue.concurrentPerform(iterations: results.count) { index in
                let emoji = fresh.entries[index]
                if fresh.entry(text: emoji.text) == emoji, fresh.entry(id: emoji.id) == emoji { results[index] = emoji.id }
            }
        }
        XCTAssertEqual(found, fresh.entries.map { Optional($0.id) })
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
            ("emojiVersion", "\(Int.max).0"), ("emojiVersion", "18.0 draft"), ("unicodeVersion", "999.0")
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
            let broken = EmojiCatalog(resourceURL: url)
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
            XCTAssertNotNil(EmojiCatalog(resourceURL: url).resourceError)
        }
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(EmojiCatalog(resourceURL: url.deletingLastPathComponent()).entries.isEmpty)
        for (version, unicode) in [("18.0", "18.0.0"), ("19.0 draft", "18.0.0 draft"), ("", "19.0.0 draft")] {
            let mixed = try fixture([entry()], version: version, unicode: unicode)
            XCTAssertNotNil(EmojiCatalog(resourceURL: mixed).resourceError)
        }
        let draftFile = try fixture([entry()], version: "19.0 draft", unicode: "19.0.0 draft")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: draftFile)) as? [String: Any])
        var pending = entry()
        pending["unicodeVersion"] = "Pending draft age"
        document["entries"] = [pending]
        try JSONSerialization.data(withJSONObject: document).write(to: draftFile)
        let draft = EmojiCatalog(resourceURL: draftFile)
        XCTAssertNil(draft.resourceError)
        XCTAssertEqual(draft.entries.first?.unicodeVersionSortKey, 0)
    }

    func testInjectedNumericAgeOrderAndAllPageBoundaries() throws {
        let records = [entry([0x1F680], version: "9.0"), entry([0x1F600], name: "fixture face", version: "10.0"),
                       entry([0x1F642, 0x200D, 0x2194, 0xFE0F], name: "fixture horizontal", version: "15.1")]
        let url = try fixture(records), catalog = EmojiCatalog(resourceURL: url.deletingLastPathComponent())
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
        let fixture = EmojiCatalog(resourceURL: url)
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
        let fixture = EmojiCatalog(resourceURL: url)
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
        let fixture = EmojiCatalog(resourceURL: url)
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

    // MARK: 1.4 categories and size

    func testGroupsKeepFileOrderCountsAndSamples() throws {
        var flag = entry([0x1F3C1], name: "chequered flag", version: "1.0")
        flag["group"] = "Flags"
        var later = entry([0x1F600], name: "grinning face", version: "1.0")
        later["group"] = "Smileys & Emotion"
        var other = entry([0x1F601], name: "beaming face", version: "1.0")
        other["group"] = "Smileys & Emotion"
        // File order Fixture, Flags, Smileys: code-point sorting must not reorder groups.
        let fixture = EmojiCatalog(resourceURL: try fixture([entry(), flag, later, other]))
        XCTAssertEqual(fixture.groups, ["Fixture", "Flags", "Smileys & Emotion"])
        XCTAssertEqual(fixture.count(inGroup: "Smileys & Emotion"), 2)
        XCTAssertEqual(fixture.count(inGroup: "Fixture"), 1)
        XCTAssertEqual(fixture.count(inGroup: "Nope"), 0)
        XCTAssertEqual(fixture.sample(forGroup: "Flags"), "\u{1F3C1}")
        XCTAssertEqual(fixture.sample(forGroup: "Fixture"), "\u{1F680}", "A group without a fixed sample uses its first entry")
        XCTAssertNil(fixture.sample(forGroup: "Nope"))
        XCTAssertEqual(fixture.shownGroupCount(hiding: []), 3)
        XCTAssertEqual(fixture.shownGroupCount(hiding: ["Flags", "Elsewhere"]), 2)

        let latest = EmojiCatalog.latest
        XCTAssertEqual(latest.groups, ["Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink",
                                       "Travel & Places", "Activities", "Objects", "Symbols", "Flags"])
        XCTAssertEqual(latest.groups.reduce(0) { $0 + latest.count(inGroup: $1) }, latest.entries.count)
        for group in latest.groups { XCTAssertNotNil(latest.sample(forGroup: group), group) }
        for (group, sample) in EmojiCatalog.groupSamples {
            XCTAssertEqual(sample.unicodeScalars.count, 1)
            XCTAssertEqual(UnicodeEdition.allCases.compactMap { $0.emojiCatalog.entries.first { $0.text == sample }?.group }.count,
                           UnicodeEdition.allCases.count, "\(group) sample is in every edition")
        }
        // A final edition keeps every group, counted for that edition.
        let oldest = try XCTUnwrap(UnicodeEdition.allCases.filter { $0 != .draft }.first).emojiCatalog
        XCTAssertEqual(oldest.groups, latest.groups)
        XCTAssertLessThanOrEqual(oldest.count(inGroup: "Flags"), latest.count(inGroup: "Flags"))
        XCTAssertTrue(EmojiCatalog(resourceURL: URL(fileURLWithPath: "/nonexistent")).groups.isEmpty)
    }

    func testHiddenGroupsAreLeftOutBeforePagingAndInEverySearchPath() throws {
        let catalog = EmojiCatalog.latest
        let hidden: Set<String> = ["Flags"]
        for order in UnicodeSortOrder.allCases {
            let all = catalog.orderedEntries(order: order)
            let shown = catalog.orderedEntries(order: order, hiding: hidden)
            XCTAssertEqual(shown, all.filter { $0.group != "Flags" })
            XCTAssertFalse(shown.isEmpty)
            // Every page is full of shown emoji.
            let page = catalog.entries(offset: 120, limit: 120, order: order, hiding: hidden)
            XCTAssertEqual(page, Array(shown.dropFirst(120).prefix(120)))
            XCTAssertEqual(catalog.search("", limit: 50, order: order, hiding: hidden), Array(shown.prefix(50)))
        }
        XCTAssertFalse(catalog.search("flag").filter { $0.group == "Flags" }.isEmpty)
        XCTAssertTrue(catalog.search("flag", limit: Int.max, hiding: hidden).allSatisfy { $0.group != "Flags" })
        XCTAssertEqual(catalog.search("flag Japan").map(\.group), ["Flags"])
        XCTAssertEqual(catalog.search("flag Japan", hiding: hidden), [])
        XCTAssertEqual(catalog.search("\u{1F1EF}\u{1F1F5}").count, 1)
        XCTAssertEqual(catalog.search("\u{1F1EF}\u{1F1F5}", hiding: hidden), [], "An exact pasted flag is hidden too")
        XCTAssertEqual(catalog.search("1F1EF 1F1F5", hiding: hidden), [])
        XCTAssertFalse(catalog.search("1F1EF 1F1F5").isEmpty)
        XCTAssertEqual(catalog.search("1F600", hiding: hidden).first?.codePoints, [0x1F600], "Other groups still match")
        XCTAssertEqual(catalog.search("\u{1F600}", hiding: hidden).first?.codePoints, [0x1F600])
        let everything = Set(catalog.groups)
        XCTAssertTrue(catalog.entries(limit: Int.max, hiding: everything).isEmpty)
        XCTAssertTrue(catalog.search("face", hiding: everything).isEmpty)
        XCTAssertEqual(catalog.shownGroupCount(hiding: everything), 0)
        XCTAssertEqual(catalog.orderedEntries(hiding: ["Not a group"]), catalog.entries)
    }

    func testEmojiCategorySettingStoresOnlyValidHiddenNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EmojiCategories-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let setting = EmojiCategorySetting(directory: { root })
        XCTAssertEqual(setting.load(), [], "Missing means every category is shown")
        XCTAssertTrue(setting.save(["Flags", "Activities"]))
        XCTAssertEqual(setting.load(), ["Flags", "Activities"])
        XCTAssertEqual(String(decoding: try Data(contentsOf: root.appendingPathComponent(EmojiCategorySetting.filename)), as: UTF8.self),
                       #"{"hidden":["Activities","Flags"],"schemaVersion":1}"#)
        XCTAssertTrue(setting.save([]))
        XCTAssertEqual(setting.load(), [])
        XCTAssertFalse(setting.save([""]))
        XCTAssertEqual(setting.load(), [], "A refused save keeps the stored value")
        for invalid in [#"{"hidden":["Flags"],"schemaVersion":2}"#, #"{"hidden":["Flags","Flags"],"schemaVersion":1}"#,
                        #"{"hidden":[" Flags"],"schemaVersion":1}"#, #"{"hidden":"Flags","schemaVersion":1}"#, "{",
                        #"{"hidden":["a\u0007"],"schemaVersion":1}"#] {
            XCTAssertNil(EmojiCategorySetting.decode(Data(invalid.utf8)), invalid)
            try Data(invalid.utf8).write(to: root.appendingPathComponent(EmojiCategorySetting.filename))
            XCTAssertEqual(setting.load(), [], invalid)
        }
        let padded = Data((#"{"hidden":[],"schemaVersion":1}"# + String(repeating: " ", count: EmojiCategorySetting.maximumPayloadBytes)).utf8)
        XCTAssertNil(EmojiCategorySetting.decode(padded))
        XCTAssertEqual(EmojiCategorySetting.decode(EmojiCategorySetting.encode(["Ünïcode"])!), ["Ünïcode"])
        XCTAssertEqual(EmojiCategorySetting(directory: { nil }).load(), [])
        XCTAssertFalse(EmojiCategorySetting(directory: { nil }).save(["Flags"]))
        XCTAssertFalse(EmojiCategorySetting(directory: { root.appendingPathComponent("missing/deeper") }).save(["Flags"]))
        _ = EmojiCategorySetting.shared.directory()

        XCTAssertTrue(EmojiCategorySetting.isValidName("Smileys & Emotion"))
        XCTAssertTrue(EmojiCategorySetting.isValidName(String(repeating: "a", count: 64)))
        for name in ["", String(repeating: "a", count: 65), String(repeating: "é", count: 33), " Flags", "Flags\n", "Fl\u{0}ags"] {
            XCTAssertFalse(EmojiCategorySetting.isValidName(name), name.debugDescription)
        }
        XCTAssertTrue(EmojiCategorySetting.isValid(Set((1...32).map { "G\($0)" })))
        XCTAssertFalse(EmojiCategorySetting.isValid(Set((1...33).map { "G\($0)" })))
        XCTAssertNil(EmojiCategorySetting.encode(Set((1...33).map { "G\($0)" })))
        XCTAssertEqual(EmojiCategorySetting.ordered(["Zeta", "Flags", "Alpha", "Activities"], groups: ["Activities", "Objects", "Flags"]),
                       ["Activities", "Flags", "Alpha", "Zeta"])
        XCTAssertEqual(EmojiCategorySetting.ordered(["Flags", "Smileys & Emotion"]), ["Smileys & Emotion", "Flags"])
    }

    func testEmojiTileLayoutMatchesTheDesignTable() {
        XCTAssertEqual(EmojiTileLayout.automaticColumns(in: 0), 3)
        XCTAssertEqual(EmojiTileLayout.automaticColumns(in: 370), 3)
        XCTAssertEqual(EmojiTileLayout.automaticColumns(in: 748), 7)
        XCTAssertEqual(EmojiTileLayout.automaticColumns(in: 150), 2, "At least two")
        // design §3 table, iPhone grid width 370.
        let expected: [(width: Double, glyph: Double, named: Bool, large: Bool)] = [
            (181, 64, true, true), (118, 34, true, false), (86.5, 32, true, false), (67.2, 30, false, false),
            (55, 28, false, false), (46, 25, false, false), (39.3, 22, false, false), (34, 20, false, false)]
        for row in expected {
            XCTAssertEqual(EmojiTileLayout.glyphSize(tileWidth: row.width), row.glyph, "\(row.width)")
            XCTAssertEqual(EmojiTileLayout.showsName(tileWidth: row.width), row.named, "\(row.width)")
            XCTAssertEqual(EmojiTileLayout.usesLargeName(tileWidth: row.width), row.large, "\(row.width)")
        }
        XCTAssertEqual(EmojiTileLayout.glyphSize(tileWidth: 10), 20)
        XCTAssertEqual(EmojiTileLayout.glyphSize(tileWidth: 250), 96)
        XCTAssertEqual(EmojiTileLayout.glyphSize(tileWidth: 900), 96)
        XCTAssertEqual(EmojiTileLayout.glyphSize(tileWidth: 100), 33, "iPad Automatic")
        var previous = 0.0
        for width in stride(from: 20.0, through: 400, by: 0.5) {
            let glyph = EmojiTileLayout.glyphSize(tileWidth: width)
            XCTAssertGreaterThanOrEqual(glyph, previous, "Never shrinks as tiles grow")
            previous = glyph
        }
    }

    func testReleasedLookupIndexesRebuildWithIdenticalAnswers() throws {
        let catalog = EmojiCatalog(resourceURL: try fixture([
            entry([0x1F680], name: "fixture rocket"),
            entry([0x2764, 0xFE0F], name: "fixture heart"),
        ]))
        XCTAssertFalse(catalog.hasLookupIndexes, "built on first lookup only")
        let rocket = try XCTUnwrap(catalog.entry(id: "1F680"))
        XCTAssertTrue(catalog.hasLookupIndexes)
        catalog.releaseLookupIndexes()
        XCTAssertFalse(catalog.hasLookupIndexes)
        XCTAssertEqual(catalog.entries.count, 2, "entries are never released")
        XCTAssertEqual(catalog.entry(id: "1F680"), rocket)
        XCTAssertEqual(catalog.entry(text: "\u{2764}\u{FE0F}")?.id, "2764-FE0F")
        XCTAssertNil(catalog.entry(text: "\u{2764}"), "still exact UTF-16, not a looser match")
        XCTAssertTrue(catalog.hasLookupIndexes)

        EmojiCatalog.releaseAllLookupIndexes()
        XCTAssertFalse(catalog.hasLookupIndexes)
        XCTAssertEqual(catalog.entry(text: "\u{1F680}"), rocket)
        // A catalog that never looked anything up stays unindexed.
        let untouched = EmojiCatalog(resourceURL: try fixture([entry()]))
        EmojiCatalog.releaseAllLookupIndexes()
        XCTAssertFalse(untouched.hasLookupIndexes)
        XCTAssertFalse(catalog.hasLookupIndexes)
    }
}
