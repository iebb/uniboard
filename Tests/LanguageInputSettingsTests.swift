import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class LanguageInputSettingsTests: XCTestCase {
    private let fixtureArchiveHash = String(repeating: "ab", count: 32)

    private func pin(_ mode: LanguageInputMode = .japaneseRomaji, id: String = "japanese.words", version: String = "2026.10") -> LanguageInputSettings.PackReference {
        .init(mode: mode, packID: id, version: version, archiveSHA256: fixtureArchiveHash)
    }

    private func preferences() -> LanguageInputSettings.Value {
        .init(enabledModes: [.direct, .japaneseRomaji, .koreanRomaja], englishSuggestions: true,
              englishAutocorrection: false, packReferences: [pin(), pin(.mandarinPinyin, id: "mandarin.words")])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LanguageInputTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func snapshot(_ value: LanguageInputSettings.Value) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(LanguageInputSettings.encode(value))) as? [String: Any])
    }

    private func decode(_ root: [String: Any]) throws -> LanguageInputSettings.Value? {
        LanguageInputSettings.decode(try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
    }

    private func decodedConfiguration(_ text: String) throws -> DecodedConfiguration {
        try ConfigurationCodec.decode(Data(text.utf8)).get()
    }

    private func assertConfigurationRejected(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        switch ConfigurationCodec.decode(Data(text.utf8)) {
        case .success: XCTFail("Malformed language configuration was accepted", file: file, line: line)
        case .failure: break
        }
    }

    func testFactoryDefaultsAndIndependentEnglishSwitches() throws {
        XCTAssertEqual(LanguageInputSettings.defaultValue, .defaults)
        XCTAssertEqual(LanguageInputSettings.defaultValue.enabledModes, [.direct])
        XCTAssertFalse(LanguageInputSettings.defaultValue.englishSuggestions)
        XCTAssertFalse(LanguageInputSettings.defaultValue.englishAutocorrection)
        XCTAssertTrue(LanguageInputSettings.defaultValue.packReferences.isEmpty)
        XCTAssertEqual(LanguageInputSettings(directory: { nil }).load(), .defaults)
        XCTAssertFalse(LanguageInputSettings(directory: { nil }).save(.defaults))
        for suggestions in [false, true] {
            for correction in [false, true] {
                let value = LanguageInputSettings.Value(englishSuggestions: suggestions, englishAutocorrection: correction)
                XCTAssertEqual(LanguageInputSettings.decode(try XCTUnwrap(LanguageInputSettings.encode(value))), value)
            }
        }
        var value = LanguageInputSettings.Value()
        XCTAssertFalse(value.setEnabled(false, for: .direct))
        XCTAssertTrue(value.isEnabled(.direct))
        XCTAssertFalse(value.isEnabled(.japaneseRomaji))
        XCTAssertTrue(value.setEnabled(true, for: .koreanRomaja))
        XCTAssertTrue(value.setEnabled(true, for: .japaneseRomaji))
        XCTAssertEqual(value.enabledModes, [.direct, .japaneseRomaji, .koreanRomaja])
        XCTAssertTrue(value.setEnabled(false, for: .japaneseRomaji))
        XCTAssertEqual(value.enabledModes, [.direct, .koreanRomaja])
        XCTAssertTrue(value.isValid)
    }

    func testReleaseAvailabilityDoesNotChangeStorageOrderOrSavedEnglishFlags() throws {
        XCTAssertEqual(LanguageInputSettings.modeOrder, [.direct, .japaneseRomaji, .mandarinPinyin, .koreanRomaja, .koreanTwoSetHangul])
        XCTAssertEqual(LanguageInputSettings.visibleModeOrder, [.direct, .japaneseRomaji, .mandarinPinyin, .koreanTwoSetHangul])
        XCTAssertFalse(LanguageInputSettings.englishAssistanceAvailable)
        for suggestions in [false, true] {
            for correction in [false, true] {
                let value = LanguageInputSettings.Value(enabledModes: LanguageInputSettings.modeOrder,
                    englishSuggestions: suggestions, englishAutocorrection: correction,
                    packReferences: [pin(.direct, id: "english.words"), pin(.koreanRomaja, id: "korean.words")])
                let bytes = try XCTUnwrap(LanguageInputSettings.encode(value))
                XCTAssertFalse(value.effectiveEnglishSuggestions)
                XCTAssertFalse(value.effectiveEnglishAutocorrection)
                XCTAssertTrue(value.isEnabled(.koreanRomaja), "Availability must not masquerade as a storage edit")
                XCTAssertEqual(LanguageInputSettings.decode(bytes), value)
                XCTAssertEqual(LanguageInputSettings.encode(value), bytes, "Reading runtime policy must not mutate the snapshot")
            }
        }
    }

    func testDeferredSettingsSurviveAppSaveLoadAndConfigurationExportImport() throws {
        let directory = try temporaryDirectory()
        let store = LanguageInputSettings(directory: { directory })
        let value = LanguageInputSettings.Value(enabledModes: LanguageInputSettings.modeOrder,
            englishSuggestions: true, englishAutocorrection: true,
            packReferences: [pin(.direct, id: "english.words"), pin(.koreanRomaja, id: "korean.words")])
        XCTAssertTrue(store.save(value))
        let url = directory.appendingPathComponent(LanguageInputSettings.filename)
        let savedBytes = try Data(contentsOf: url)
        let loaded = store.load()
        XCTAssertFalse(loaded.effectiveEnglishSuggestions)
        XCTAssertFalse(loaded.effectiveEnglishAutocorrection)
        XCTAssertEqual(loaded, value)
        XCTAssertEqual(try Data(contentsOf: url), savedBytes)
        var configuration = UniboardConfiguration.factoryDefaults
        configuration.languageInput = loaded
        let exported = try XCTUnwrap(ConfigurationCodec.encode(configuration))
        let imported = try ConfigurationCodec.decode(exported).get().configuration
        XCTAssertEqual(imported, configuration)
        XCTAssertEqual(imported.languageInput.packReferences, value.packReferences)
        XCTAssertTrue(imported.languageInput.englishSuggestions)
        XCTAssertTrue(imported.languageInput.englishAutocorrection)
        XCTAssertTrue(imported.languageInput.enabledModes.contains(.koreanRomaja))
        XCTAssertEqual(ConfigurationCodec.encode(imported), exported)
        XCTAssertEqual(LanguageInputSettings.encode(imported.languageInput), savedBytes)
    }

    func testSnapshotRoundTripAndAppWriteKeyboardRead() throws {
        let directory = try temporaryDirectory()
        let app = LanguageInputSettings(directory: { directory })
        let keyboard = LanguageInputSettings(directory: { directory })
        XCTAssertEqual(keyboard.load(), .defaults)
        let value = preferences()
        let bytes = try XCTUnwrap(LanguageInputSettings.encode(value))
        XCTAssertLessThanOrEqual(bytes.count, 8192)
        XCTAssertEqual(bytes, LanguageInputSettings.encode(value))
        XCTAssertTrue(app.save(value))
        XCTAssertEqual(keyboard.load(), value)
        XCTAssertFalse(keyboard.load().isEnabled(.mandarinPinyin), "A reference for a disabled mode must not enable it")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(LanguageInputSettings.filename)), bytes)
        XCTAssertEqual(LanguageInputSettings.decode(bytes), value)
        let root = try snapshot(value)
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "value"])
        let contents = try XCTUnwrap(root["value"] as? [String: Any])
        XCTAssertEqual(Set(contents.keys), ["enabledModes", "englishSuggestions", "englishAutocorrection", "packReferences"])
        let refs = try XCTUnwrap(contents["packReferences"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(refs.first).keys), ["mode", "packID", "version", "archiveSHA256"])
    }

    func testOmittedMemberwiseLanguagePreferencesRemainSafeDefaults() {
        let baseline = UniboardConfiguration.factoryDefaults
        let configuration = UniboardConfiguration(
            settings: baseline.settings, autoCapitalization: baseline.autoCapitalization,
            browse: baseline.browse, keys: baseline.keys, pages: baseline.pages,
            starPageID: baseline.starPageID, favorites: baseline.favorites,
            fontRules: baseline.fontRules, imageColors: baseline.imageColors)
        XCTAssertEqual(configuration.languageInput, .defaults)
        XCTAssertFalse(configuration.languageInput.englishSuggestions)
        XCTAssertFalse(configuration.languageInput.englishAutocorrection)
        XCTAssertEqual(configuration.languageInput.enabledModes, [.direct])
    }

    func testInvalidFilesAndSaveFailuresDoNotPretendSuccess() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent(LanguageInputSettings.filename)
        let store = LanguageInputSettings(directory: { directory })
        XCTAssertTrue(store.save(preferences()))
        let original = try Data(contentsOf: url)
        var invalid = preferences()
        invalid.enabledModes = [.japaneseRomaji]
        XCTAssertFalse(store.save(invalid))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNil(LanguageInputSettings.encode(invalid))
        var configuration = UniboardConfiguration.factoryDefaults
        configuration.languageInput = invalid
        XCTAssertNil(configuration.compile())
        XCTAssertNil(ConfigurationCodec.encode(configuration))

        for data in [Data(), Data("not JSON".utf8), Data(repeating: 32, count: 8193)] {
            try data.write(to: url)
            XCTAssertEqual(store.load(), .defaults)
            XCTAssertNil(LanguageInputSettings.decode(data))
        }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertEqual(store.load(), .defaults)
        XCTAssertFalse(store.save(.defaults))
        let missingDirectory = directory.appendingPathComponent("absent")
        XCTAssertFalse(LanguageInputSettings(directory: { missingDirectory }).save(.defaults))
        try FileManager.default.removeItem(at: url)
        let target = directory.appendingPathComponent("private-target.json")
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        XCTAssertEqual(store.load(), .defaults)
        XCTAssertFalse(store.save(.defaults))
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testStrictSchemaShapeTypesAndUnknownKeys() throws {
        let good = try snapshot(preferences())
        for version in [0, 2, 99, -1] {
            var root = good
            root["schemaVersion"] = version
            XCTAssertNil(try decode(root))
        }
        for key in ["schemaVersion", "value"] {
            var root = good
            root.removeValue(forKey: key)
            XCTAssertNil(try decode(root))
        }
        var unknown = good
        unknown["activeMode"] = "japaneseRomaji"
        XCTAssertNil(try decode(unknown))
        let contents = try XCTUnwrap(good["value"] as? [String: Any])
        for key in ["enabledModes", "englishSuggestions", "englishAutocorrection", "packReferences"] {
            var value = contents
            value.removeValue(forKey: key)
            var root = good
            root["value"] = value
            XCTAssertNil(try decode(root))
        }
        for (key, bad) in [("englishSuggestions", 1 as Any), ("englishAutocorrection", "false" as Any),
                           ("packReferences", "[]" as Any), ("enabledModes", NSNull() as Any),
                           ("activeMode", "japaneseRomaji" as Any), ("typedBuffer", "private" as Any),
                           ("traditional", true as Any)] {
            var value = contents
            value[key] = bad
            var root = good
            root["value"] = value
            XCTAssertNil(try decode(root))
        }
        let refs = try XCTUnwrap(contents["packReferences"] as? [[String: Any]])
        for key in ["url", "path", "customEntries", "archiveBytes"] {
            var ref = refs[0]
            ref[key] = "not-portable"
            var value = contents
            value["packReferences"] = [ref]
            var root = good
            root["value"] = value
            XCTAssertNil(try decode(root))
        }
        for key in ["mode", "packID", "version", "archiveSHA256"] {
            var ref = refs[0]
            ref.removeValue(forKey: key)
            var value = contents
            value["packReferences"] = [ref]
            var root = good
            root["value"] = value
            XCTAssertNil(try decode(root))
        }
    }

    func testModeValidationRejectsUnknownDuplicatesAndNoncanonicalOrder() throws {
        let good = try snapshot(.defaults)
        for names in [[], ["japaneseRomaji"], ["direct", "direct"], ["direct", "futureMode"],
                      ["direct", "koreanRomaja", "japaneseRomaji"], ["Direct"],
                      ["direct", "japaneseRomaji", "mandarinPinyin", "koreanRomaja", "direct"]] {
            var root = good
            var value = try XCTUnwrap(root["value"] as? [String: Any])
            value["enabledModes"] = names
            root["value"] = value
            XCTAssertNil(try decode(root))
        }
        let all = LanguageInputSettings.Value(enabledModes: LanguageInputSettings.modeOrder)
        XCTAssertEqual(LanguageInputSettings.decode(try XCTUnwrap(LanguageInputSettings.encode(all))), all)
    }

    func testReferenceIdentityBoundsHashesAndModeConsistency() throws {
        for identifier in ["a", "1", "UPPER", "1-RC2", "japanese.words", "words_1-test", String(repeating: "a", count: 128)] {
            XCTAssertTrue(LanguageInputSettings.isCanonicalIdentifier(identifier))
        }
        for identifier in ["", " words", "words ", "a/b", "../private", "https://host", "é", "a\n", "_a", "a-", String(repeating: "a", count: 129)] {
            XCTAssertFalse(LanguageInputSettings.isCanonicalIdentifier(identifier))
            var value = LanguageInputSettings.Value(packReferences: [pin(id: identifier)])
            XCTAssertNil(LanguageInputSettings.encode(value))
            value.packReferences = [pin(version: identifier)]
            XCTAssertNil(LanguageInputSettings.encode(value))
        }
        for badHash in ["", String(repeating: "a", count: 63), String(repeating: "a", count: 65), fixtureArchiveHash.uppercased(), String(repeating: "g", count: 64)] {
            var ref = pin()
            ref.archiveSHA256 = badHash
            XCTAssertNil(LanguageInputSettings.encode(.init(packReferences: [ref])))
            // Decoder must reject corrupt bytes too, not just prevent app writes.
            var root = try snapshot(.init(packReferences: [pin()]))
            var value = try XCTUnwrap(root["value"] as? [String: Any])
            var refs = try XCTUnwrap(value["packReferences"] as? [[String: Any]])
            refs[0]["archiveSHA256"] = badHash
            value["packReferences"] = refs
            root["value"] = value
            XCTAssertNil(try decode(root))
        }
        for refs in [[pin(), pin()], [pin(), pin(version: "2026.11")], [pin(), pin(.mandarinPinyin)]] {
            XCTAssertNil(LanguageInputSettings.encode(.init(packReferences: refs)))
        }
        let eight = (0..<8).map { pin(id: "words.\($0)") }
        XCTAssertNotNil(LanguageInputSettings.encode(.init(packReferences: eight)))
        XCTAssertNil(LanguageInputSettings.encode(.init(packReferences: eight + [pin(id: "words.8")])))
        var root = try snapshot(.init(packReferences: [pin()]))
        var contents = try XCTUnwrap(root["value"] as? [String: Any])
        let original = try XCTUnwrap((contents["packReferences"] as? [[String: Any]])?.first)
        var futureMode = original
        futureMode["mode"] = "futureMode"
        var conflicting = original
        conflicting["mode"] = "mandarinPinyin"
        for malformed in [[futureMode], [original, original], [original, conflicting], Array(repeating: original, count: 9)] {
            contents["packReferences"] = malformed
            root["value"] = contents
            XCTAssertNil(try decode(root))
        }
        // English assistance resources may be pinned to Direct Typing, with
        // both assistance switches still Off and no automatic activation.
        let direct = LanguageInputSettings.Value(packReferences: [pin(.direct, id: "english.words")])
        XCTAssertEqual(LanguageInputSettings.decode(try XCTUnwrap(LanguageInputSettings.encode(direct))), direct)
    }

    func testSnapshotByteBoundaryIncludesTrailingWhitespace() throws {
        let data = try XCTUnwrap(LanguageInputSettings.encode(.defaults))
        var boundary = data
        boundary.append(Data(repeating: 32, count: 8192 - data.count))
        XCTAssertEqual(LanguageInputSettings.decode(boundary), .defaults)
        boundary.append(32)
        XCTAssertNil(LanguageInputSettings.decode(boundary))
    }

    func testMaximumReferencesFitIndependentSnapshotBudget() throws {
        let refs = (0..<8).map { index in
            pin(LanguageInputSettings.modeOrder[index % 4], id: String(repeating: "a", count: 127) + "\(index)", version: String(repeating: "1", count: 128))
        }
        let value = LanguageInputSettings.Value(enabledModes: LanguageInputSettings.modeOrder, englishSuggestions: true,
                                               englishAutocorrection: true, packReferences: refs)
        let data = try XCTUnwrap(LanguageInputSettings.encode(value))
        XCTAssertGreaterThan(data.count, UnicodeEditionSettings.maximumPayloadBytes)
        XCTAssertLessThanOrEqual(data.count, LanguageInputSettings.maximumPayloadBytes)
        XCTAssertEqual(LanguageInputSettings.decode(data), value)
        XCTAssertEqual(SharedConfigurationLocation.fileLimits[LanguageInputSettings.filename], 8192)
        XCTAssertTrue(ConfigurationSnapshotValidation.validators[LanguageInputSettings.filename]?(data) == true)
        XCTAssertFalse(ConfigurationSnapshotValidation.validators[LanguageInputSettings.filename]?(Data()) == true)
    }

    func testCompileCaptureAndSettingsOnlyMatch() throws {
        var c = UniboardConfiguration.factoryDefaults
        c.languageInput = preferences()
        XCTAssertFalse(c.matches(.factoryDefaults, in: .settings))
        for category in ConfigurationCategory.allCases where category != .settings {
            XCTAssertTrue(c.matches(.factoryDefaults, in: category))
        }
        let directory = try temporaryDirectory()
        let files = try XCTUnwrap(c.compile())
        XCTAssertEqual(Set(files.keys), Set(SharedConfigurationLocation.snapshotFiles))
        XCTAssertEqual(LanguageInputSettings.decode(try XCTUnwrap(files[LanguageInputSettings.filename])), c.languageInput)
        for (name, data) in files { try data.write(to: directory.appendingPathComponent(name)) }
        XCTAssertEqual(UniboardConfiguration.capture(directory: directory, presentation: c.browse.values, favorites: []), c)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(LanguageInputSettings.filename))
        XCTAssertEqual(UniboardConfiguration.capture(directory: directory, presentation: c.browse.values, favorites: []), .factoryDefaults)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent(LanguageInputSettings.filename))
        XCTAssertEqual(UniboardConfiguration.capture(directory: directory, presentation: c.browse.values, favorites: []), .factoryDefaults)
    }

    func testLegacySchemasAndExplicitDefaultSectionRetainDynamicExport() throws {
        let baseline = try XCTUnwrap(ConfigurationCodec.encode(.factoryDefaults))
        XCTAssertTrue(String(decoding: baseline, as: UTF8.self).hasPrefix("schema_version = 1"))
        XCTAssertFalse(String(decoding: baseline, as: UTF8.self).contains("language_input"))
        for version in [1, 2, 3] {
            let parsed = try decodedConfiguration("schema_version = \(version)\n")
            XCTAssertEqual(parsed.configuration, .factoryDefaults)
            XCTAssertEqual(parsed.configuration.languageInput, .defaults)
            XCTAssertEqual(ConfigurationCodec.encode(parsed.configuration), baseline)
        }
        let explicitDefault = try decodedConfiguration("""
        schema_version = 3
        [settings.language_input]
        enabled_modes = ["direct"]
        english_suggestions = false
        english_autocorrection = false
        pack_references = []
        """)
        XCTAssertEqual(ConfigurationCodec.encode(explicitDefault.configuration), baseline)
        XCTAssertEqual(try decodedConfiguration("schema_version=3\n[settings.language_input]\n").configuration, .factoryDefaults)
        for version in [1, 2] {
            assertConfigurationRejected("schema_version=\(version)\n[settings.language_input]\nenglish_suggestions=true\n")
        }
        assertConfigurationRejected("schema_version=4\n")
    }

    func testLegacyFieldsRetainIgnoredAndExplicitEmptySemantics() throws {
        let body = """
        [settings]
        unicode_edition = "\(UnicodeEdition.latest.selectionIdentifier)"
        auto_capitalization = "words"
        number_row = {retired = "ignored"}
        [settings.browse]
        emoji_columns = 9
        blocks_descending = true
        [[keyboard.key]]
        id = "letter.a"
        long_press = []
        swipe_down = ["e\\u0301", "é"]
        [favorites]
        texts = ["e\\u0301", "é"]
        """
        let first = try decodedConfiguration("schema_version=1\n" + body)
        let second = try decodedConfiguration("schema_version=2\n" + body)
        XCTAssertEqual(first.configuration, second.configuration)
        XCTAssertEqual(first.configuration.languageInput, .defaults)
        XCTAssertEqual(first.ignoredSettings, [.init(name: "Number Row", key: "settings.number_row")])
        XCTAssertEqual(first.configuration.keys.overrides["letter.a"]?.longPress, [])
        XCTAssertNil(first.configuration.keys.overrides["letter.a"]?.swipeUp)
        XCTAssertEqual(first.configuration.favorites.map { Array($0.unicodeScalars) }, [Array("e\u{301}".unicodeScalars), Array("é".unicodeScalars)])
        let data = try XCTUnwrap(ConfigurationCodec.encode(first.configuration))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("schema_version = 1"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("number_row"))
        let again = try ConfigurationCodec.decode(data).get().configuration
        XCTAssertEqual(again, first.configuration)
        XCTAssertEqual(ConfigurationCodec.encode(again), data)
    }

    func testSchema3RoundTripPreservesAllExistingFieldsAndExactRows() throws {
        var c = UniboardConfiguration.factoryDefaults
        c.autoCapitalization = .words
        c.browse.emojiColumns = 7
        c.browse.blocksDescending = true
        c.settings.layouts = ["en", "el"]
        c.settings.edition = .previous
        c.settings.useUnicodeFonts = true
        c.settings.showsTextPreview = true
        c.imageColors = .init(preset: "custom", customText: "#123456", customBackground: "transparent", scale: 2)
        let face = FontFaceReference(source: .installed, family: "Chalkduster", style: "Regular", postScriptName: "Chalkduster",
                                     identity: .process(postScriptName: "Chalkduster", variations: [:]))
        c.fontRules = [FontRule(selector: .codePoint(0x16A0), face: face)]
        c.hiddenEmojiCategories = ["Flags"]
        c.favorites = ["e\u{301}", "é", "👩‍💻"]
        c.keys = .init(overrides: ["letter.a": .init(longPress: [], swipeUp: nil, swipeDown: ["é"])])
        c.pages.append(SymbolBoard(id: "explicit", name: "Explicit", rows: [
            .init(alignment: .right, cells: [.halfGap, .key(.init(id: "decomposed", text: "e\u{301}", variants: ["é"])), .gap]),
        ]))
        c.starPageID = "explicit"
        let legacyData = try XCTUnwrap(ConfigurationCodec.encode(c))
        XCTAssertTrue(String(decoding: legacyData, as: UTF8.self).hasPrefix("schema_version = 2"))
        XCTAssertEqual(ConfigurationCodec.encode(try ConfigurationCodec.decode(legacyData).get().configuration), legacyData)
        c.languageInput = preferences()
        let data = try XCTUnwrap(ConfigurationCodec.encode(c))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("schema_version = 3"))
        XCTAssertTrue(text.contains("[settings.language_input]"))
        XCTAssertTrue(text.contains("[[settings.language_input.pack_references]]"))
        let result = try ConfigurationCodec.decode(data).get()
        XCTAssertEqual(result.formatVersion, 3)
        XCTAssertEqual(result.configuration, c)
        XCTAssertEqual(ConfigurationCodec.encode(result.configuration), data)
        XCTAssertEqual(result.configuration.pages.last?.explicitRows, c.pages.last?.explicitRows)
        XCTAssertEqual(result.configuration.keys.overrides["letter.a"]?.longPress, [])
        XCTAssertNil(result.configuration.keys.overrides["letter.a"]?.swipeUp)
        XCTAssertTrue(result.missingSections.isEmpty)
        // Import/export has no downloader, location or custom-data field.
        for forbidden in ["url =", "path =", "typed_buffer", "active_mode", "custom_entries"] {
            XCTAssertFalse(text.contains(forbidden))
        }
    }

    func testSchema3RejectsMalformedOrFutureLanguageData() {
        let header = "schema_version=3\n[settings.language_input]\n"
        for tail in [
            "enabled_modes=[]", "enabled_modes=['japaneseRomaji']", "enabled_modes=['direct','direct']",
            "enabled_modes=['direct','unknown']", "enabled_modes=['direct','koreanRomaja','japaneseRomaji']",
            "enabled_modes=['direct',3]", "enabled_modes='direct'", "english_suggestions=1", "english_autocorrection='false'",
            "traditional=true", "active_mode='japaneseRomaji'", "schema_version=2", "pack_references=['words']",
            "pack_references=[{mode='future',pack_id='words',version='1',archive_sha256='\(fixtureArchiveHash)'}]",
            "pack_references=[{mode='direct',pack_id='words',version='1',archive_sha256='bad'}]",
            "pack_references=[{mode='direct',pack_id='Words/invalid',version='1',archive_sha256='\(fixtureArchiveHash)'}]",
            "pack_references=[{mode='direct',pack_id='words',version='../1',archive_sha256='\(fixtureArchiveHash)'}]",
            "pack_references=[{mode='direct',pack_id='words',version='1',archive_sha256='\(fixtureArchiveHash)',url='https://host'}]",
            "pack_references=[{mode='direct',pack_id='words',version='1'}]",
        ] { assertConfigurationRejected(header + tail + "\n") }
        let ref = "{mode='direct',pack_id='words',version='1',archive_sha256='\(fixtureArchiveHash)'}"
        let differentMode = "{mode='japaneseRomaji',pack_id='words',version='2',archive_sha256='\(fixtureArchiveHash)'}"
        assertConfigurationRejected(header + "pack_references=[\(ref),\(ref)]")
        assertConfigurationRejected(header + "pack_references=[\(ref),\(differentMode)]")
        assertConfigurationRejected(header + "pack_references=[" + Array(repeating: ref, count: 9).joined(separator: ",") + "]")
        assertConfigurationRejected("schema_version=3\n[settings]\nlanguage_input=true\n")
    }

    func testSeparateEnglishFlagsChooseSchema3WithoutEnablingModes() throws {
        for value in [LanguageInputSettings.Value(englishSuggestions: true), .init(englishAutocorrection: true),
                      .init(packReferences: [pin()])] {
            var c = UniboardConfiguration.factoryDefaults
            c.languageInput = value
            let data = try XCTUnwrap(ConfigurationCodec.encode(c))
            XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("schema_version = 3"))
            XCTAssertEqual(try ConfigurationCodec.decode(data).get().configuration, c)
            XCTAssertEqual(c.languageInput.enabledModes, [.direct])
        }
    }

    func testSettingsReviewShowsExactReadableChangesAndNoCustomData() {
        let old = UniboardConfiguration.factoryDefaults
        var new = old
        new.languageInput = preferences()
        let diff = ConfigurationDiff(current: old, incoming: new)
        let lines = diff.change(.settings).lines
        XCTAssertTrue(lines.contains("Enabled Language Modes: Direct Typing → Direct Typing, Japanese — Romaji, Korean — Romaja"))
        XCTAssertTrue(lines.contains("English Suggestions: Off → On"))
        XCTAssertFalse(lines.contains(where: { $0.contains("English Autocorrection") }))
        XCTAssertTrue(lines.contains("Adds Language Pack Reference: Japanese — Romaji, japanese.words @ 2026.10, SHA-256 \(fixtureArchiveHash)"))
        XCTAssertEqual(diff.changes.filter { $0.status != .unchanged }.map(\.category), [.settings])
        var changed = new
        changed.languageInput.englishAutocorrection = true
        changed.languageInput.packReferences[0].version = "2026.11"
        changed.languageInput.packReferences[0].archiveSHA256 = String(repeating: "cd", count: 32)
        changed.languageInput.packReferences.removeLast()
        let edit = ConfigurationDiff(current: new, incoming: changed).change(.settings).lines
        XCTAssertTrue(edit.contains("English Autocorrection: Off → On"))
        XCTAssertTrue(edit.contains(where: { $0.hasPrefix("Language Pack Reference: Japanese") && $0.contains("2026.10") && $0.contains("2026.11") && $0.contains(fixtureArchiveHash) && $0.contains(String(repeating: "cd", count: 32)) }))
        XCTAssertTrue(edit.contains(where: { $0.hasPrefix("Removes Language Pack Reference: Mandarin") }))
        let reset = ConfigurationDiff(current: new, incoming: old, missingSections: [.settings])
        XCTAssertEqual(reset.change(.settings).status, .reset)
        XCTAssertTrue(reset.change(.settings).lines.contains("English Suggestions: On → Off"))
    }

    func testSchema3CaptureFromCompiledSnapshotsPreservesExactUnicodeGestures() throws {
        var incoming = UniboardConfiguration.factoryDefaults
        incoming.languageInput = preferences()
        let expected = KeyboardKeySettings.Overrides(tap: ["e\u{301}"], shiftedTap: ["𝔄"], longPress: [], swipeUp: nil,
                                                     swipeDown: ["é", "e\u{301}", "👩\u{200D}💻", "\u{E0041}"])
        incoming.keys = .init(overrides: ["letter.a": expected])
        incoming.favorites = ["é", "e\u{301}"]
        let portable = try XCTUnwrap(ConfigurationCodec.encode(incoming))
        XCTAssertEqual(try ConfigurationCodec.decode(portable).get().formatVersion, 3)
        let decoded = try ConfigurationCodec.decode(portable).get().configuration
        let directory = try temporaryDirectory()
        for (filename, bytes) in try XCTUnwrap(decoded.compile()) {
            try bytes.write(to: directory.appendingPathComponent(filename))
        }
        let captured = UniboardConfiguration.capture(directory: directory, presentation: decoded.browse.values, favorites: decoded.favorites)
        XCTAssertEqual(captured.languageInput, incoming.languageInput)
        let actual = try XCTUnwrap(captured.keys.overrides["letter.a"])
        for gesture in KeyboardKeySettings.Gesture.allCases {
            // Compare scalars rather than canonically equivalent String values.
            XCTAssertEqual(actual.candidates(for: gesture)?.map { $0.unicodeScalars.map(\.value) },
                           expected.candidates(for: gesture)?.map { $0.unicodeScalars.map(\.value) })
        }
        XCTAssertEqual(actual.longPress, [])
        XCTAssertNil(actual.swipeUp)
        XCTAssertEqual(captured.favorites.map { $0.unicodeScalars.map(\.value) }, incoming.favorites.map { $0.unicodeScalars.map(\.value) })
        XCTAssertEqual(ConfigurationCodec.encode(captured), portable)
    }

    func testSchema3ImportUndoAndRecaptureRestoreExactUnicodeGestureSnapshots() throws {
        let root = try temporaryDirectory()
        var original = UniboardConfiguration.factoryDefaults
        original.keys = .init(overrides: ["letter.a": .init(tap: ["e\u{301}"], shiftedTap: ["é"], longPress: [], swipeUp: nil,
                                                            swipeDown: ["é", "e\u{301}", "👩\u{200D}💻"])])
        original.favorites = ["e\u{301}", "é"]
        let originalFiles = try XCTUnwrap(original.compile())
        for (filename, bytes) in originalFiles { try bytes.write(to: root.appendingPathComponent(filename)) }
        let location = SharedConfigurationLocation(root: { root })
        let presentation = AppPresentationSettings.encode(original.browse.values)
        guard case .applied = location.migrateIfNeeded(presentation: presentation) else { return XCTFail("Migration failed") }

        var incoming = original
        incoming.languageInput = preferences()
        incoming.keys = .init(overrides: ["letter.a": .init(tap: ["é"], shiftedTap: ["e\u{301}"], longPress: nil, swipeUp: [],
                                                            swipeDown: ["e\u{301}", "é", "𝔄"])])
        incoming.favorites.reverse()
        let portable = try XCTUnwrap(ConfigurationCodec.encode(incoming))
        let imported = try ConfigurationCodec.decode(portable).get()
        XCTAssertEqual(imported.formatVersion, 3)
        let before = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case .applied = location.apply(try XCTUnwrap(imported.configuration.compile()), expecting: before, currentPresentation: presentation) else {
            return XCTFail("Import failed")
        }
        let appliedDirectory = try XCTUnwrap(location.currentDirectory())
        let appliedFavorites = try XCTUnwrap(FavoriteSync.decode(Data(contentsOf: appliedDirectory.appendingPathComponent(FavoriteSync.filename)))).texts
        let applied = UniboardConfiguration.capture(directory: appliedDirectory, presentation: incoming.browse.values, favorites: appliedFavorites)
        XCTAssertEqual(applied, incoming)
        XCTAssertEqual(applied.keys.overrides["letter.a"]?.tap?.first?.unicodeScalars.map(\.value), [0xE9])
        XCTAssertNil(applied.keys.overrides["letter.a"]?.longPress)
        XCTAssertEqual(applied.keys.overrides["letter.a"]?.swipeUp, [])
        XCTAssertFalse(try XCTUnwrap(location.undoStatus(presentation: presentation)).hasNewerEdits)

        let after = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case .applied = location.undoLastImport(expecting: after, currentPresentation: presentation) else { return XCTFail("Undo failed") }
        let restoredDirectory = try XCTUnwrap(location.currentDirectory())
        let restoredFavorites = try XCTUnwrap(FavoriteSync.decode(Data(contentsOf: restoredDirectory.appendingPathComponent(FavoriteSync.filename)))).texts
        let restored = UniboardConfiguration.capture(directory: restoredDirectory, presentation: original.browse.values, favorites: restoredFavorites)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.languageInput, .defaults)
        XCTAssertEqual(restored.keys.overrides["letter.a"]?.tap?.first?.unicodeScalars.map(\.value), [0x65, 0x301])
        XCTAssertEqual(restored.keys.overrides["letter.a"]?.longPress, [])
        XCTAssertNil(restored.keys.overrides["letter.a"]?.swipeUp)
        XCTAssertEqual(restored.favorites.map { $0.unicodeScalars.map(\.value) }, original.favorites.map { $0.unicodeScalars.map(\.value) })
        XCTAssertEqual(try Data(contentsOf: restoredDirectory.appendingPathComponent(KeyboardKeySettings.filename)), originalFiles[KeyboardKeySettings.filename])
    }

    func testOldGenerationMissingNewSnapshotRemainsReadableAndImportUndoRestoresIt() throws {
        let root = try temporaryDirectory()
        let location = SharedConfigurationLocation(root: { root })
        let presentation = AppPresentationSettings.encode(.init())
        // Migration preserves the older store set as-is, including absence of
        // the new file. Recovery uses the generation's own manifest file list.
        guard case .applied = location.migrateIfNeeded(presentation: presentation) else { return XCTFail("Migration failed") }
        let original = try XCTUnwrap(location.currentDirectory())
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.appendingPathComponent(LanguageInputSettings.filename).path))
        XCTAssertEqual(location.lastGoodGeneration(), "g-000001")
        XCTAssertEqual(UniboardConfiguration.capture(directory: original, presentation: .init(), favorites: []), .factoryDefaults)
        var incoming = UniboardConfiguration.factoryDefaults
        incoming.languageInput = preferences()
        let expected = try XCTUnwrap(location.currentFingerprint(presentation: presentation))
        guard case .applied = location.apply(try XCTUnwrap(incoming.compile()), expecting: expected, currentPresentation: presentation) else {
            return XCTFail("Import failed")
        }
        XCTAssertEqual(LanguageInputSettings(directory: { location.currentDirectory() }).load(), incoming.languageInput)
        // Applying a portable configuration explicitly sets its browse defaults.
        // Model the app's presentation adoption before checking Undo: the older
        // unset snapshot is semantically equivalent but has different bytes and
        // must still count as a newer edit if supplied after the import.
        let importedPresentation = AppPresentationSettings.encode(incoming.browse.values)
        XCTAssertNotEqual(importedPresentation, presentation)
        XCTAssertTrue(try XCTUnwrap(location.undoStatus(presentation: presentation)).hasNewerEdits)
        XCTAssertFalse(try XCTUnwrap(location.undoStatus(presentation: importedPresentation)).hasNewerEdits)
        let current = try XCTUnwrap(location.currentFingerprint(presentation: importedPresentation))
        guard case .applied = location.undoLastImport(expecting: current, currentPresentation: importedPresentation) else { return XCTFail("Undo failed") }
        let restored = try XCTUnwrap(location.currentDirectory())
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.appendingPathComponent(LanguageInputSettings.filename).path))
        XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent(AppPresentationSettings.filename)), presentation)
        XCTAssertEqual(LanguageInputSettings(directory: { restored }).load(), .defaults)
        XCTAssertEqual(location.lastGoodGeneration(), "g-000003")
        XCTAssertNil(location.undoStatus(presentation: presentation))
    }
}
