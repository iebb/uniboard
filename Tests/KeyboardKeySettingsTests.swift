import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardKeySettingsTests: XCTestCase {
    func testTapShiftedTapAndThreeGesturesAreIndependentAndRoundTripForEveryCharacterKey() throws {
        for key in Settings.descriptors {
            var value = Settings.Snapshot.defaults
            for (gesture, text) in zip(Settings.Gesture.allCases, ["w", "Ω", "é", "↑", "↓"]) {
                value = try XCTUnwrap(value.updating([text], for: key.id, gesture: gesture))
                XCTAssertEqual(value.candidates(for: key.id, gesture: gesture), [text])
            }
            XCTAssertEqual(load(try data(value)), value)
            let encoded = try JSONEncoder().encode(try XCTUnwrap(value.overrides[key.id]))
            XCTAssertEqual(try JSONDecoder().decode(Settings.Overrides.self, from: encoded), value.overrides[key.id])
            for gesture in Settings.Gesture.allCases {
                value = try XCTUnwrap(value.updating(nil, for: key.id, gesture: gesture))
            }
            XCTAssertEqual(value, .defaults)
        }
    }

    func testDefaultCandidatesMatchTheKeyboardsOwnGroups() {
        let hold = KeyboardVariantPolicy.defaultCandidates(for: "letter.e", gesture: .longPress, mapping: .standard)
        XCTAssertEqual(hold.first, "e")
        XCTAssertTrue(hold.contains("é"))
        XCTAssertEqual(KeyboardVariantPolicy.defaultCandidates(for: "letter.e", gesture: .swipeDown, mapping: .standard).first, "ᵉ")
        XCTAssertFalse(KeyboardVariantPolicy.defaultCandidates(for: "letter.q", gesture: .swipeUp, mapping: .standard).isEmpty)
        XCTAssertTrue(KeyboardVariantPolicy.defaultCandidates(for: "letter.q", gesture: .swipeUp, mapping: .none).isEmpty)
        XCTAssertEqual(KeyboardVariantPolicy.defaultCandidates(for: "digit.1", gesture: .swipeDown, mapping: .standard).first, "¹")
        XCTAssertTrue(KeyboardVariantPolicy.defaultCandidates(for: "utility.space", gesture: .longPress, mapping: .standard).isEmpty)
        for key in Settings.descriptors {
            for gesture in Settings.Gesture.customizable {
                let values = KeyboardVariantPolicy.defaultCandidates(for: key.id, gesture: gesture, mapping: .standard)
                XCTAssertEqual(Set(values.map { Array($0.utf16) }).count, values.count, "\(key.id) \(gesture)")
            }
        }
    }

    func testTapsAlwaysTypeTheKeyItselfAndIgnoreSavedTapValues() throws {
        let defaults = Settings.Snapshot.defaults
        XCTAssertEqual(Settings.Gesture.customizable, [.swipeUp, .swipeDown, .longPress])
        XCTAssertEqual(defaults.tapOutput(for: "letter.q", defaultText: "Q", shifted: true), "Q")
        for saved in [Settings.Overrides(tap: ["w"]), .init(tap: []), .init(shiftedTap: ["Ω"]), .init(tap: ["a", "b"])] {
            let value = Settings.Snapshot(overrides: ["letter.q": saved])
            XCTAssertEqual(value.tapOutput(for: "letter.q", defaultText: "q", shifted: false), "q")
            XCTAssertEqual(value.tapOutput(for: "letter.q", defaultText: "Q", shifted: true), "Q")
        }
        XCTAssertEqual(Settings.Snapshot(overrides: ["digit.1": .init(tap: ["q"])]).tapOutput(for: "digit.1", defaultText: "!", shifted: true), "!")
        XCTAssertNil(defaults.tapOutput(for: "utility.space", defaultText: " ", shifted: false))
        XCTAssertNil(defaults.tapOutput(for: "letter.q", defaultText: "", shifted: false))
    }

    func testTapSlotsHaveOneOutputWhileGesturesKeepSixteenAndVersionOneCannotSmuggleNewFields() throws {
        for gesture in [Settings.Gesture.tap, .shiftedTap] {
            for choices in [[], ["👩‍💻"], [String(repeating: "😀", count: 64)]] {
                XCTAssertNotNil(Settings.Snapshot.defaults.updating(choices, for: "letter.a", gesture: gesture))
            }
            XCTAssertNil(Settings.Snapshot.defaults.updating(["a", "b"], for: "letter.a", gesture: gesture))
            XCTAssertNil(Settings.Snapshot.defaults.updating([""], for: "letter.a", gesture: gesture))
            XCTAssertNil(Settings.Snapshot.defaults.updating([String(repeating: "a", count: 65)], for: "letter.a", gesture: gesture))
            let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "overrides": [["keyID": "letter.a", gesture.rawValue: NSNull()]]])
            XCTAssertThrowsError(try JSONDecoder().decode(Settings.Snapshot.self, from: bytes))
        }
        let old = json(#"{"schemaVersion":1,"overrides":[{"keyID":"letter.q","longPress":["h"],"swipeUp":["u"],"swipeDown":["d"]}]}"#)
        let migrated = load(old)
        XCTAssertEqual(migrated.candidates(for: "letter.q", gesture: .longPress), ["h"])
        XCTAssertNil(migrated.candidates(for: "letter.q", gesture: .tap))
        XCTAssertEqual(load(try data(migrated)), migrated)
    }
    private typealias Settings = KeyboardKeySettings
    private let container = URL(fileURLWithPath: "/injected-key-settings", isDirectory: true)
    private enum Failure: Error { case unavailable }
    private var example: Settings.Snapshot {
        .init(overrides: ["letter.a": .init(longPress: ["à", "a\u{301}"], swipeUp: [], swipeDown: ["👩‍💻"])])
    }
    private func data(_ value: Settings.Snapshot) throws -> Data { try JSONEncoder().encode(value) }
    private func load(_ bytes: Data) -> Settings.Snapshot {
        Settings(containerURL: { self.container }, readPrefix: { _, _ in bytes },
                 writeAtomically: { _, _ in XCTFail("A keyboard read must not write") }).loadSnapshot()
    }
    private func json(_ text: String) -> Data { Data(text.utf8) }
    private func withContainer(_ action: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Uniboard.KeySettings.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }
        try action(url)
    }

    func testDescriptorCatalogCoversCharacterKeysWithStableASCIIIdentifiersAndExcludesFunctions() {
        XCTAssertEqual(Set(Settings.descriptors.map(\.id)).count, Settings.descriptors.count)
        XCTAssertTrue(Settings.descriptors.allSatisfy { !$0.title.isEmpty && $0.id.utf8.allSatisfy { $0 < 128 } })
        XCTAssertEqual(Settings.descriptors.filter { $0.kind == .letter }.count, 26)
        XCTAssertEqual(Settings.descriptors.filter { $0.kind == .digit }.count, 10)
        XCTAssertEqual(Settings.descriptor(for: "letter.a")?.text, "a")
        XCTAssertEqual(Settings.descriptor(for: "digit.0")?.text, "0")
        XCTAssertEqual(Settings.descriptor(for: "symbol.005B")?.text, "[")
        for key in ["space", "return", "delete", "shift", "layout", "unicode", "favorites", "collapse", "globe"] {
            XCTAssertNil(Settings.descriptor(for: "utility." + key))
        }
        XCTAssertTrue(Settings.descriptors.allSatisfy { $0.text != nil && !$0.id.hasPrefix("utility.") })
        for layout in KeyboardTypingLayout.allCases {
            let texts = layout.rows.flatMap { $0 } + KeyboardTypingLayoutPolicy.auxiliaryRow(for: layout)
                + KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: true).flatMap { $0 }
            for text in texts { XCTAssertNotNil(Settings.identifier(forCharacter: text), text) }
        }
        for letter in Array("abcdefghijklmnopqrstuvwxyz").map(String.init) {
            XCTAssertEqual(Settings.identifier(forCharacter: letter), "letter." + letter)
            XCTAssertEqual(Settings.identifier(forCharacter: letter.uppercased()), "letter." + letter)
        }
        for text in ["", "ab", "é", "e\u{301}", "👩‍💻", " ", "\n"] { XCTAssertNil(Settings.identifier(forCharacter: text)) }
    }

    func testEveryRetiredFunctionOverrideIsIgnoredWithoutLosingExactCharacterChoicesOrWriting() throws {
        let functions = ["space", "return", "delete", "shift", "layout", "unicode", "favorites", "collapse"]
        var entries: [[String: Any]] = functions.map {
            ["keyID": "utility." + $0, "longPress": ["old"], "swipeUp": ["_"], "swipeDown": []]
        }
        entries += [["keyID": "letter.e", "longPress": ["é", "e\u{301}"]],
                    ["keyID": "digit.1", "swipeUp": ["!"]], ["keyID": "symbol.002E", "swipeDown": ["…"]]]
        let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "overrides": entries])
        let result = load(bytes)
        XCTAssertEqual(result.overrides.count, 3)
        XCTAssertEqual(result.candidates(for: "letter.e", gesture: .longPress)?.map { Array($0.utf16) }, [Array("é".utf16), Array("e\u{301}".utf16)])
        XCTAssertEqual(result.candidates(for: "digit.1", gesture: .swipeUp), ["!"])
        XCTAssertEqual(result.candidates(for: "symbol.002E", gesture: .swipeDown), ["…"])
        for key in functions.map({ "utility." + $0 }) {
            XCTAssertNil(result.overrides[key])
            for gesture in Settings.Gesture.allCases {
                XCTAssertNil(result.candidates(for: key, gesture: gesture))
                XCTAssertNil(result.updating(["x"], for: key, gesture: gesture))
            }
            let invalid = Settings.Snapshot(overrides: [key: .init(swipeUp: ["_"])])
            XCTAssertNil(invalid.candidates(for: key, gesture: .swipeUp))
            XCTAssertThrowsError(try data(invalid), "New app writes must not recreate retired settings")
        }
        let saved = try data(result)
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("utility."))
        XCTAssertEqual(load(saved), result)
    }

    func testLegacyOnlyAndMaximumMixedPayloadDecodeButExcessAndDuplicateFunctionIDsFail() throws {
        let functions = ["space", "return", "delete", "shift", "layout", "unicode", "favorites", "collapse"]
            .map { ["keyID": "utility." + $0, "swipeUp": ["_"]] as [String: Any] }
        func decode(_ entries: [[String: Any]]) throws -> Settings.Snapshot {
            try JSONDecoder().decode(Settings.Snapshot.self,
                from: JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "overrides": entries]))
        }
        XCTAssertEqual(try decode(functions), .defaults)
        let characters = Settings.descriptors.map { ["keyID": $0.id, "swipeDown": ["x"]] as [String: Any] }
        XCTAssertEqual(try decode(characters + functions).overrides.count, Settings.descriptors.count)
        XCTAssertThrowsError(try decode(characters + functions + [functions[0]]))
        XCTAssertThrowsError(try decode([functions[0], functions[0]]))
        XCTAssertThrowsError(try decode([["keyID": "utility.space", "swipeUp": [""]], characters[0]]))
        XCTAssertThrowsError(try decode([["keyID": "utility.unknown", "swipeUp": ["_"]], characters[0]]))
        XCTAssertThrowsError(try decode([["keyID": "utility.space", "tap": ["_"]], characters[0]]))
    }

    func testDefaultDisabledAndExplicitCandidatesRemainDistinct() throws {
        let defaults = Settings.Snapshot.defaults
        XCTAssertTrue(defaults.overrides.isEmpty)
        for gesture in Settings.Gesture.allCases { XCTAssertNil(defaults.candidates(for: "letter.a", gesture: gesture)) }
        let disabled = try XCTUnwrap(defaults.updating([], for: "letter.a", gesture: .longPress))
        XCTAssertEqual(disabled.candidates(for: "letter.a", gesture: .longPress), [])
        XCTAssertNil(disabled.candidates(for: "letter.a", gesture: .swipeUp))
        XCTAssertNotEqual(disabled, defaults)
        let up = try XCTUnwrap(disabled.updating(["A", "Æ"], for: "letter.a", gesture: .swipeUp))
        let down = try XCTUnwrap(up.updating(["a"], for: "letter.a", gesture: .swipeDown))
        XCTAssertEqual(down.candidates(for: "letter.a", gesture: .longPress), [])
        XCTAssertEqual(down.candidates(for: "letter.a", gesture: .swipeUp), ["A", "Æ"])
        XCTAssertEqual(down.candidates(for: "letter.a", gesture: .swipeDown), ["a"])
        var restored = down
        for gesture in Settings.Gesture.allCases { restored = try XCTUnwrap(restored.updating(nil, for: "letter.a", gesture: gesture)) }
        XCTAssertEqual(restored, defaults)
        XCTAssertEqual(down.removingOverride(for: "letter.a"), defaults)
        XCTAssertEqual(down.removingOverride(for: "not-a-key"), down)
    }

    func testSnapshotEqualityUsesExactUTF16IncludingOrderAndMissingSlots() {
        let nfc = Settings.Overrides(longPress: ["é"])
        let nfd = Settings.Overrides(longPress: ["e\u{301}"])
        XCTAssertNotEqual(nfc, nfd)
        XCTAssertNotEqual(nfc, .init(swipeUp: ["é"]))
        XCTAssertNotEqual(Settings.Overrides(swipeDown: []), .init())
        XCTAssertNotEqual(Settings.Overrides(longPress: ["a", "b"]), .init(longPress: ["b", "a"]))
        XCTAssertNotEqual(Settings.Overrides(longPress: ["a"]), .init(longPress: ["a", "b"]))
        XCTAssertEqual(nfc, .init(longPress: ["é"]))
        XCTAssertNotEqual(Settings.Snapshot(overrides: ["letter.e": nfc]), .init(overrides: ["letter.e": nfd]))
    }

    func testExactNFCNFDZWJVariationSelectorsAndControlsRoundTripWithoutNormalization() throws {
        let values = ["é", "e\u{301}", "👩‍💻", "🙂‍↔️", "\0", "\n", " "]
        let expected = Settings.Snapshot(overrides: ["letter.e": .init(longPress: values, swipeUp: [], swipeDown: ["\u{10FFFF}"])])
        let actual = load(try data(expected))
        XCTAssertEqual(actual, expected)
        let actualValues = try XCTUnwrap(actual.candidates(for: "letter.e", gesture: .longPress))
        for (a, b) in zip(actualValues, values) { XCTAssertEqual(Array(a.utf16), Array(b.utf16)) }
        XCTAssertEqual(actualValues.count, values.count)
    }

    func testWriterUsesFixedChildSortedEntriesAndNoImplicitTypedState() throws {
        let expected = Settings.Snapshot(overrides: ["letter.z": .init(swipeDown: []), "letter.a": .init(longPress: ["à"])])
        var saved: Data?; var savedURL: URL?
        let settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in XCTFail("Saving does not inspect host/previous state"); return Data() },
                                writeAtomically: { saved = $0; savedURL = $1 })
        XCTAssertTrue(settings.save(expected))
        XCTAssertEqual(savedURL, container.appendingPathComponent(Settings.filename))
        let first = try XCTUnwrap(saved)
        XCTAssertTrue(settings.save(expected)); XCTAssertEqual(saved, first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "overrides"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        let entries = try XCTUnwrap(object["overrides"] as? [[String: Any]])
        XCTAssertEqual(entries.compactMap { $0["keyID"] as? String }, ["letter.a", "letter.z"])
        XCTAssertEqual(Set(entries[0].keys), ["keyID", "longPress"])
        XCTAssertEqual(Set(entries[1].keys), ["keyID", "swipeDown"])
        XCTAssertEqual(load(first), expected)
        XCTAssertEqual(Settings.groupIdentifier, UnicodeEditionSettings.groupIdentifier)
        XCTAssertEqual(Settings.filename, "keyboard-keys-v1.json")
    }

    func testReaderRequestsOnlyBoundedPrefixFromFixedGroupChildAndNeverWrites() throws {
        let bytes = try data(example); var reads = 0
        let settings = Settings(containerURL: { self.container }, readPrefix: { url, maximum in
            reads += 1; XCTAssertEqual(url, self.container.appendingPathComponent(Settings.filename))
            XCTAssertEqual(maximum, Settings.maximumPayloadBytes + 1); return bytes
        }, writeAtomically: { _, _ in XCTFail("Reading must not migrate or repair settings") })
        XCTAssertEqual(settings.loadSnapshot(), example); XCTAssertEqual(reads, 1)
    }

    func testDefaultProviderUsesOnlyDeclaredGroupWithInjectedReadAndNoActualFileAccess() throws {
        let expectedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.groupIdentifier)
        let bytes = try data(example); var reads = 0
        let settings = Settings(readPrefix: { url, maximum in
            reads += 1
            XCTAssertEqual(url, expectedContainer?.appendingPathComponent(Settings.filename))
            XCTAssertEqual(maximum, Settings.maximumPayloadBytes + 1)
            return bytes
        }, writeAtomically: { _, _ in XCTFail("Default keyboard load cannot write") })
        if let expectedContainer, expectedContainer.isFileURL {
            XCTAssertEqual(settings.loadSnapshot(), example); XCTAssertEqual(reads, 1)
        } else {
            XCTAssertEqual(settings.loadSnapshot(), .defaults); XCTAssertEqual(reads, 0)
        }
    }

    func testNilOrNonFileContainerNeverInvokesReaderOrWriter() {
        for url: URL? in [nil, URL(string: "https://example.invalid/keyboard-keys") ] {
            let settings = Settings(containerURL: { url }, readPrefix: { _, _ in XCTFail("No valid file container"); return Data() },
                                    writeAtomically: { _, _ in XCTFail("No valid file container") })
            XCTAssertEqual(settings.loadSnapshot(), .defaults)
            XCTAssertNil(settings.loadForEditing())
            XCTAssertFalse(settings.save(example)); XCTAssertFalse(settings.reset())
        }
    }

    func testMissingUnavailableAndMalformedDataFallBackWithoutRepair() {
        let missing = Settings(containerURL: { self.container }, readPrefix: { _, _ in throw Failure.unavailable },
                               writeAtomically: { _, _ in XCTFail("No repair writes") })
        XCTAssertEqual(missing.loadSnapshot(), .defaults)
        let malformed = [Data(), Data([0xFF]), json("[]"), json("null"), json("true"), json("{}"),
                         Data(json(#"{"schemaVersion":1,"overrides":[]}"#).dropLast()),
                         json(#"{"schemaVersion":1,"overrides":[]}!"#)]
        for bytes in malformed { XCTAssertEqual(load(bytes), .defaults) }
    }

    func testEditableReadDistinguishesVerifiedMissingFromUnreadableErrors() {
        for error: Error in [POSIXError(.ENOENT), CocoaError(.fileReadNoSuchFile)] {
            let settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in throw error },
                                    writeAtomically: { _, _ in XCTFail("A read cannot repair missing data") })
            XCTAssertEqual(settings.loadForEditing(), .defaults)
            XCTAssertEqual(settings.loadSnapshot(), .defaults)
        }
        let errors: [Error] = [Failure.unavailable, POSIXError(.EACCES), POSIXError(.ELOOP), POSIXError(.EIO),
                               CocoaError(.fileReadNoPermission), NSError(domain: "untrusted-domain", code: Int(ENOENT))]
        for error in errors {
            let settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in throw error },
                                    writeAtomically: { _, _ in XCTFail("An unreadable file cannot be repaired by a load") })
            XCTAssertNil(settings.loadForEditing())
            XCTAssertEqual(settings.loadSnapshot(), .defaults)
        }
    }

    func testEditableReadRequiresValidBoundedSnapshotWhileKeyboardRetainsSafeFallback() throws {
        let valid = try data(example)
        let malformed = [Data(), Data([0xFF]), Data(valid.dropLast()), json(#"{"schemaVersion":3,"overrides":[]}"#),
                         json(#"{"schemaVersion":1,"overrides":[{"keyID":"unknown"}]}"#),
                         valid + Data(repeating: 0x20, count: Settings.maximumPayloadBytes + 1 - valid.count)]
        for bytes in malformed {
            let settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in bytes },
                                    writeAtomically: { _, _ in XCTFail("Corrupt bytes must remain untouched") })
            XCTAssertNil(settings.loadForEditing())
            XCTAssertEqual(settings.loadSnapshot(), .defaults)
        }
        let settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in valid })
        XCTAssertEqual(settings.loadForEditing(), example)
    }

    func testStrictSchemaRejectsBooleansNumbersUnknownFieldsAndWrongSlotShapes() {
        let malformed = [
            #"{"schemaVersion":true,"overrides":[]}"#,
            #"{"schemaVersion":"1","overrides":[]}"#,
            #"{"schemaVersion":3,"overrides":[]}"#,
            #"{"schemaVersion":1.5,"overrides":[]}"#,
            #"{"schemaVersion":1}"#,
            #"{"schemaVersion":1,"overrides":[],"hostText":"not settings"}"#,
            #"{"schemaVersion":1,"overrides":[],"0":{"nested":[true,null]}}"#,
            #"{"schemaVersion":1,"overrides":{}}"#,
            #"{"schemaVersion":1,"overrides":[{"keyID":true,"longPress":[]}] }"#,
            #"{"schemaVersion":1,"overrides":[{"keyID":"letter.a","tap":["x"]}]}"#,
            #"{"schemaVersion":1,"overrides":[{"keyID":"letter.a","longPress":false}]}"#,
            #"{"schemaVersion":1,"overrides":[{"keyID":"letter.a","swipeUp":[1]}]}"#,
            #"{"schemaVersion":1,"overrides":[{"keyID":"letter.a","swipeDown":[true]}]}"#,
            #"{"schemaVersion":1,"overrides":[{"longPress":[]}]}"#
        ]
        for bytes in malformed { XCTAssertEqual(load(json(bytes)), .defaults, bytes) }
    }

    func testUnknownNoncanonicalAndDuplicateKeyIDsRejectWholeSnapshot() throws {
        for key in ["unknown", "letter.A", "letter.a ", "letter.á", "../letter.a", "utility.globe", "symbol.005b", "digit.10"] {
            let invalid = Settings.Snapshot(overrides: [key: .init(longPress: ["x"])])
            XCTAssertThrowsError(try data(invalid), key)
            XCTAssertNil(Settings.Snapshot.defaults.updating([], for: key, gesture: .swipeUp))
            let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "overrides": [["keyID": key, "longPress": ["x"]]]])
            XCTAssertEqual(load(bytes), .defaults)
        }
        let duplicate = json(#"{"schemaVersion":1,"overrides":[{"keyID":"letter.a","longPress":["x"]},{"keyID":"letter.a","swipeUp":["y"]}]}"#)
        XCTAssertEqual(load(duplicate), .defaults)
        XCTAssertThrowsError(try JSONDecoder().decode(Settings.Snapshot.self, from: duplicate))
        let tooMany = Array(repeating: ["keyID": "letter.a"], count: Settings.descriptors.count + 1)
        XCTAssertEqual(load(try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "overrides": tooMany])), .defaults)
    }

    func testCandidateAndScalarLimitsAreExactWithoutDeduplicatingUserChoices() throws {
        let sixteen = (0..<16).map { String(repeating: "a", count: 63) + String(Unicode.Scalar(65 + $0)!) }
        let valid = Settings.Snapshot(overrides: ["letter.a": .init(longPress: sixteen)])
        XCTAssertEqual(load(try data(valid)), valid)
        for values in [sixteen + ["seventeenth"], [""], [String(repeating: "a", count: 65)], ["x", "x"], ["👩‍💻", "👩‍💻"]] {
            XCTAssertThrowsError(try data(.init(overrides: ["letter.a": .init(longPress: values)])))
            XCTAssertNil(Settings.Snapshot.defaults.updating(values, for: "letter.a", gesture: .swipeDown))
        }
        XCTAssertNotNil(Settings.Snapshot.defaults.updating(["é", "e\u{301}"], for: "letter.e", gesture: .longPress))
        XCTAssertNotNil(Settings.Snapshot.defaults.updating([String(repeating: "😀", count: 64)], for: "letter.a", gesture: .swipeUp))
        let invalidExisting = Settings.Snapshot(overrides: ["unknown": .init(longPress: [])])
        XCTAssertNil(invalidExisting.updating(["a"], for: "letter.a", gesture: .longPress))
    }

    func testDirectOverridesCodableAlsoRejectsUnknownFieldsAndInvalidCandidates() throws {
        for text in [#"{"longPress":["x"],"unknown":true}"#, #"{"longPress":[""]}"#, #"{"swipeUp":[true]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(Settings.Overrides.self, from: json(text)))
        }
        XCTAssertThrowsError(try JSONEncoder().encode(Settings.Overrides(swipeDown: [""])))
        let expected = Settings.Overrides(longPress: ["é", "e\u{301}"], swipeUp: [], swipeDown: ["👩‍💻"])
        XCTAssertEqual(try JSONDecoder().decode(Settings.Overrides.self, from: JSONEncoder().encode(expected)), expected)
        XCTAssertEqual(try JSONDecoder().decode(Settings.Overrides.self, from: json(#"{"swipeUp":null}"#)), .init())
    }

    func testExactPayloadByteBoundaryAcceptsWhitespaceButOverflowFailsClosed() throws {
        let bytes = try data(example)
        let exact = bytes + Data(repeating: 0x20, count: Settings.maximumPayloadBytes - bytes.count)
        XCTAssertEqual(load(exact), example)
        XCTAssertEqual(load(exact + Data([0x20])), .defaults)
    }

    func testWholePayloadBudgetRejectsValidButExcessiveConfigurationBeforeWriting() {
        let choices = (0..<16).map { String(repeating: "\0", count: 63) + String(Unicode.Scalar(65 + $0)!) }
        let many = Settings.Snapshot(overrides: Dictionary(uniqueKeysWithValues: Settings.descriptors.map {
            ($0.id, Settings.Overrides(longPress: choices, swipeUp: choices, swipeDown: choices))
        }))
        let settings = Settings(containerURL: { self.container }, writeAtomically: { _, _ in XCTFail("Over budget must not write") })
        XCTAssertFalse(settings.save(many))
        XCTAssertFalse(settings.save(.init(overrides: ["unknown": .init()])))
        var excessiveKeys = many.overrides
        excessiveKeys["unknown"] = .init()
        XCTAssertFalse(settings.save(.init(overrides: excessiveKeys)))
    }

    func testAtomicRoundTripResetAndFailurePreservePreviouslyPublishedValue() throws {
        try withContainer { directory in
            let settings = Settings(containerURL: { directory })
            XCTAssertEqual(settings.loadSnapshot(), .defaults)
            XCTAssertEqual(settings.loadForEditing(), .defaults, "The actual ENOENT is an editable missing file")
            XCTAssertTrue(settings.save(example)); XCTAssertEqual(settings.loadSnapshot(), example)
            let before = try Data(contentsOf: directory.appendingPathComponent(Settings.filename))
            let failed = Settings(containerURL: { directory }, writeAtomically: { _, _ in throw Failure.unavailable })
            XCTAssertFalse(failed.reset()); XCTAssertFalse(failed.save(.defaults))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(Settings.filename)), before)
            XCTAssertEqual(settings.loadSnapshot(), example)
            XCTAssertTrue(settings.reset()); XCTAssertEqual(settings.loadSnapshot(), .defaults)
        }
    }

    func testNoFollowReadAndWriteProtectLinkedOutsideFileIncludingBrokenLinks() throws {
        try withContainer { directory in
            let outside = directory.appendingPathComponent("outside.json")
            let bytes = try data(example); try bytes.write(to: outside)
            let child = directory.appendingPathComponent(Settings.filename)
            try FileManager.default.createSymbolicLink(at: child, withDestinationURL: outside)
            let settings = Settings(containerURL: { directory })
            XCTAssertEqual(settings.loadSnapshot(), .defaults); XCTAssertNil(settings.loadForEditing()); XCTAssertFalse(settings.save(.defaults))
            XCTAssertEqual(try Data(contentsOf: outside), bytes)
            try FileManager.default.removeItem(at: child)
            try FileManager.default.createSymbolicLink(at: child, withDestinationURL: directory.appendingPathComponent("missing"))
            XCTAssertEqual(settings.loadSnapshot(), .defaults); XCTAssertNil(settings.loadForEditing()); XCTAssertFalse(settings.save(example))
        }
    }

    func testNonregularChildAndMissingParentFailWithoutBlockingOrDeleting() throws {
        try withContainer { directory in
            let child = directory.appendingPathComponent(Settings.filename)
            XCTAssertEqual(mkfifo(child.path, mode_t(0o600)), 0)
            let settings = Settings(containerURL: { directory })
            XCTAssertEqual(settings.loadSnapshot(), .defaults)
            XCTAssertNil(settings.loadForEditing())
            try FileManager.default.removeItem(at: child)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            XCTAssertEqual(settings.loadSnapshot(), .defaults); XCTAssertFalse(settings.save(example))
            XCTAssertTrue(try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
            let absent = Settings(containerURL: { directory.appendingPathComponent("absent", isDirectory: true) })
            XCTAssertFalse(absent.save(example)); XCTAssertEqual(absent.loadSnapshot(), .defaults)
        }
    }

    func testReentrantReaderDoesNotPublishCachedStateOrWriteDuringFallback() throws {
        let original = try data(example); var bytes = original; var reads = 0
        let replacement = Settings.Snapshot(overrides: ["letter.z": .init(swipeUp: ["Z"])])
        var settings: Settings!
        settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in
            reads += 1
            if reads == 1 { let captured = bytes; XCTAssertTrue(settings.save(replacement)); return captured }
            return bytes
        }, writeAtomically: { bytes = $0; XCTAssertEqual($1, self.container.appendingPathComponent(Settings.filename)) })
        defer { settings = nil }
        XCTAssertEqual(settings.loadSnapshot(), example)
        XCTAssertEqual(settings.loadSnapshot(), replacement)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(example.candidates(for: "letter.a", gesture: .swipeUp), [])
    }

    func testReentrantWriterCanReadPreviousSnapshotWithoutPartialVisiblePreferences() throws {
        var bytes = try data(example); var writes = 0
        var settings: Settings!
        settings = Settings(containerURL: { self.container }, readPrefix: { _, _ in bytes }, writeAtomically: { new, _ in
            writes += 1
            XCTAssertEqual(settings.loadSnapshot(), self.example)
            bytes = new
        })
        defer { settings = nil }
        XCTAssertTrue(settings.reset()); XCTAssertEqual(writes, 1)
        XCTAssertEqual(settings.loadSnapshot(), .defaults)
    }
}
