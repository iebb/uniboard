#if canImport(UIKit)
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Uniboard

/// The Review Import state machine: nothing is written before Replace, a
/// changed configuration is never overwritten, and failure copy claims the
/// previous configuration is in use only when its fingerprint proves it.
@MainActor
final class ConfigurationImportModelTests: XCTestCase {
    private final class Fake {
        var current = UniboardConfiguration.factoryDefaults
        var fingerprint: String? = "fp-1"
        var outcome: ConfigurationOutcome = .applied(ConfigurationPointer(generation: 2, directory: "g-000002"))
        /// Faces this device can't load.
        var unavailable: [FontFaceReference] = []
        var asked: [[FontFaceReference]] = []
        var applied: [(files: [String: Data], expected: String)] = []
        var adopted = 0
        var readError: Error?
        var fileData = Data()

        var environment: ConfigurationImportEnvironment {
            let data = fileData, error = readError
            return ConfigurationImportEnvironment(
                read: { _ in if let error { throw error }; return data },
                current: { (self.current, self.fingerprint) },
                unavailableFonts: { faces in
                    self.asked.append(faces)
                    return faces.filter(self.unavailable.contains)
                },
                presentation: { Data("presentation".utf8) },
                apply: { files, expected, presentation in
                    XCTAssertEqual(presentation, Data("presentation".utf8))
                    self.applied.append((files, expected))
                    return self.outcome
                },
                currentFingerprint: { _ in self.fingerprint },
                adopt: { self.adopted += 1 })
        }
    }

    private let url = URL(fileURLWithPath: "/tmp/Uniboard-Configuration-2026-10-23.toml")

    /// A face no device has.
    private let missing = FontFaceReference(
        source: .imported, family: "Fixture Sans", style: "Regular", postScriptName: "FixtureSans-Regular",
        identity: .file(sha256: String(repeating: "0", count: 64), faceIndex: 0, variations: [:]))

    private func encoded(_ configuration: UniboardConfiguration) throws -> Data {
        try XCTUnwrap(ConfigurationCodec.encode(configuration))
    }

    private func review(_ model: ConfigurationImportModel, file: StaticString = #filePath, line: UInt = #line) throws -> ConfigurationReview {
        guard case let .review(review) = model.phase else {
            XCTFail("Expected a review, got \(model.phase)", file: file, line: line)
            throw XCTSkip()
        }
        return review
    }

    func testCheckingNamesTheFileAndInvalidFilesListEveryProblemWithoutWriting() async {
        let fake = Fake()
        fake.fileData = Data("schema_version = 1\n[settings]\nextra_unicode_fonts = \"yes\"\ncolour = true\n".utf8)
        let model = ConfigurationImportModel(fileName: url.lastPathComponent, environment: fake.environment)
        XCTAssertEqual(model.phase, .checking("Uniboard-Configuration-2026-10-23.toml"))
        XCTAssertEqual(ConfigurationCopy.checking(model.fileName), "Checking Uniboard-Configuration-2026-10-23.toml…")
        await model.load(url)
        guard case let .failed(problems) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertGreaterThanOrEqual(problems.count, 2)
        XCTAssertFalse(problems.contains { $0.contains("yes") }, "Problems never echo file contents")
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.adopted, 0)
    }

    func testAFileThatCantBeReadSaysSo() async {
        let fake = Fake()
        fake.readError = CocoaError(.fileReadNoPermission)
        let model = ConfigurationImportModel(fileName: "x.toml", environment: fake.environment)
        await model.load(url)
        XCTAssertEqual(model.phase, .failed([ConfigurationCodec.unreadable]))
    }

    func testAnIdenticalFileOffersDoneAndNeverImports() async throws {
        let fake = Fake()
        fake.current.fontRules = [FontRule(selector: .codePoint(0x2603), face: missing)]
        fake.unavailable = [missing]
        let model = ConfigurationImportModel(fileName: "same.toml", environment: fake.environment)
        await model.check(try encoded(fake.current))
        let review = try review(model)
        XCTAssertTrue(review.diff.isIdentical)
        XCTAssertFalse(review.showsOverwrite)
        XCTAssertEqual(review.fontWarnings.count, 1)
        XCTAssertFalse(review.showsFonts, "No fonts card when nothing changes")
        XCTAssertTrue(review.ignoredSettings.isEmpty)
        let closes = await model.replace()
        XCTAssertTrue(closes)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.adopted, 0)
        XCTAssertEqual(model.phase, .review(review), "Never “Configuration imported” when nothing was applied")
    }

    func testReplaceAppliesTheReviewedFileAgainstTheReviewedFingerprint() async throws {
        let fake = Fake()
        var incoming = fake.current
        incoming.settings.useUnicodeFonts = true
        incoming.favorites = ["★"]
        let papyrus = FontFaceReference(source: .installed, family: "Papyrus", style: "Regular", postScriptName: "Papyrus",
                                        identity: .process(postScriptName: "Papyrus", variations: [:]))
        incoming.fontRules = [FontRule(selector: .codePoint(0x2603), face: missing),
                              FontRule(selector: .range(first: 0x2190, last: 0x21FF), face: papyrus),
                              FontRule(selector: .codePoint(0x2604), face: missing)]
        fake.unavailable = [missing]
        let model = ConfigurationImportModel(fileName: "next.toml", environment: fake.environment)
        await model.check(try encoded(incoming))
        let review = try review(model)
        XCTAssertEqual(review.diff.change(.settings).lines.first, "Extra Unicode Fonts: Off → On")
        XCTAssertTrue(review.diff.changesExtraUnicodeFonts)
        XCTAssertTrue(review.showsOverwrite)
        XCTAssertTrue(review.showsFonts)
        XCTAssertEqual(fake.asked.last, [missing, papyrus], "Every referenced face is checked, once each")
        // One warning per missing font, naming every rule that uses it.
        XCTAssertEqual(review.fontWarnings, [ConfigurationFontWarning(font: "Fixture Sans Regular",
                                                                      rules: ["Code point rule U+2603", "Code point rule U+2604"])])
        XCTAssertEqual(review.unavailableFonts, ["Fixture Sans Regular"])
        XCTAssertEqual(ConfigurationFontWarning.ruleStatus, "Font unavailable")
        XCTAssertTrue(review.caption.hasSuffix(" · Format version 1"), review.caption)
        XCTAssertTrue(fake.applied.isEmpty, "Reviewing writes nothing")

        let closes = await model.replace()
        XCTAssertFalse(closes)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.applied.first?.expected, "fp-1")
        XCTAssertEqual(Set(try XCTUnwrap(fake.applied.first).files.keys), Set(SharedConfigurationLocation.snapshotFiles))
        XCTAssertEqual(fake.adopted, 1)
        XCTAssertEqual(model.phase, .imported(unavailableFonts: ["Fixture Sans Regular"]))
        // Rules for a missing font are applied all the same; no font file is touched.
        let rules = try XCTUnwrap(FontRuleStore.decode(try XCTUnwrap(fake.applied.first?.files[FontRuleStore.filename])))
        XCTAssertEqual(rules.map(\.selector), [.codePoint(0x2603), .range(first: 0x2190, last: 0x21FF), .codePoint(0x2604)])
        XCTAssertEqual(rules.map(\.face), [missing, papyrus, missing])
    }

    func testRetiredSettingsAreListedButNeverApplied() async throws {
        let fake = Fake()
        fake.current.settings.showsNumberRow = false
        fake.current.settings.showsSymbolBar = false
        var document = ConfigurationCodec.document(fake.current)
        var settings = try XCTUnwrap(document["settings"]?.tableValue)
        settings["top_row"] = .string("search")
        settings["number_row"] = .boolean(true)
        settings["symbol_bar"] = .boolean(true)
        document["settings"] = .table(settings)
        let model = ConfigurationImportModel(fileName: "old.toml", environment: fake.environment)
        await model.check(Data(TOMLDocument.write(document).utf8))
        let legacy = try review(model)
        XCTAssertTrue(legacy.diff.isIdentical, "Ignored settings are never a change")
        XCTAssertEqual(legacy.ignoredSettings, [
            ConfigurationIgnoredSetting(name: "Top Row", key: "settings.top_row"),
            ConfigurationIgnoredSetting(name: "Number Row", key: "settings.number_row"),
            ConfigurationIgnoredSetting(name: "Top Row", key: "settings.symbol_bar"),
        ])
        // The stored values stay as they are, whatever the file says.
        XCTAssertFalse(legacy.incoming.settings.showsNumberRow)
        XCTAssertFalse(legacy.incoming.settings.showsSymbolBar)
        let closes = await model.replace()
        XCTAssertTrue(closes)
        XCTAssertTrue(fake.applied.isEmpty)

        // With a real change too, the write keeps the stored retired values.
        fake.current.favorites = []
        var changed = document
        changed["favorites"] = .table(TOMLTable(["texts": .array([.string("★")])]))
        let next = ConfigurationImportModel(fileName: "old.toml", environment: fake.environment)
        await next.check(Data(TOMLDocument.write(changed).utf8))
        XCTAssertEqual(try review(next).diff.change(.favorites).status, .changed)
        XCTAssertEqual(try review(next).diff.change(.settings).status, .unchanged)
        await next.replace()
        let edition = try XCTUnwrap(fake.applied.first?.files[UnicodeEditionSettings.filename])
        let stored = try XCTUnwrap(UnicodeEditionSettings.decode(edition))
        XCTAssertFalse(stored.showsNumberRow)
        XCTAssertFalse(stored.showsSymbolBar)
        XCTAssertEqual(ConfigurationCopy.ignoredSetting("Number Row"), "Ignored setting, Number Row")
    }

    func testRulesAloneNeverTurnOnExtraUnicodeFonts() async throws {
        let fake = Fake()
        var incoming = fake.current
        incoming.fontRules = [FontRule(selector: .codePoint(0x2603), face: FontFaceReference(
            source: .installed, family: "Papyrus", style: "Regular", postScriptName: "Papyrus",
            identity: .process(postScriptName: "Papyrus", variations: [:])))]
        let model = ConfigurationImportModel(fileName: "rules.toml", environment: fake.environment)
        await model.check(try encoded(incoming))
        let review = try review(model)
        XCTAssertEqual(review.diff.change(.settings).status, .unchanged)
        XCTAssertFalse(review.diff.changesExtraUnicodeFonts)
        await model.replace()
        let files = try XCTUnwrap(fake.applied.first?.files)
        let edition = try XCTUnwrap(files[UnicodeEditionSettings.filename])
        XCTAssertFalse(try XCTUnwrap(UnicodeEditionSettings.decode(edition)).useUnicodeFonts)
    }

    func testAChangedConfigurationIsReviewedAgainNeverOverwritten() async throws {
        let fake = Fake()
        var incoming = fake.current
        incoming.favorites = ["★"]
        fake.outcome = .conflict
        let model = ConfigurationImportModel(fileName: "next.toml", environment: fake.environment)
        await model.check(try encoded(incoming))
        let before = try review(model)
        await model.replace()
        XCTAssertEqual(model.alert, .changed)
        XCTAssertEqual(model.phase, .review(before))
        XCTAssertEqual(fake.adopted, 0)

        // Meanwhile the favorites became the file's: Review Again compares with them.
        fake.current.favorites = ["★"]
        fake.fingerprint = "fp-2"
        await model.reviewAgain()
        XCTAssertNil(model.alert)
        let after = try review(model)
        XCTAssertEqual(after.fingerprint, "fp-2")
        XCTAssertEqual(after.diff.change(.favorites).status, .unchanged)
        XCTAssertTrue(after.diff.isIdentical)
    }

    func testFailuresClaimThePreviousConfigurationOnlyWhenVerified() async throws {
        var incoming = UniboardConfiguration.factoryDefaults
        incoming.favorites = ["★"]
        for (outcome, fingerprintAfter, alert) in [
            (ConfigurationOutcome.failed(.publish), "fp-1", ConfigurationImportModel.Alert.replaceFailed),
            (.busy, "fp-1", .replaceFailed),
            (.unavailable, "fp-9", .replaceUnverified),
            (.invalidPayload, nil, .replaceUnverified),
        ] as [(ConfigurationOutcome, String?, ConfigurationImportModel.Alert)] {
            let fake = Fake()
            fake.outcome = outcome
            let model = ConfigurationImportModel(fileName: "next.toml", environment: fake.environment)
            await model.check(try encoded(incoming))
            let before = try review(model)
            fake.fingerprint = fingerprintAfter
            await model.replace()
            XCTAssertEqual(model.alert, alert, "\(outcome)")
            XCTAssertEqual(model.phase, .review(before), "Back to the review: \(outcome)")
            XCTAssertEqual(fake.adopted, 0)
        }

        // Before the shared configuration exists there is nothing to match: no write.
        let fake = Fake()
        fake.fingerprint = nil
        let model = ConfigurationImportModel(fileName: "next.toml", environment: fake.environment)
        await model.check(try encoded(incoming))
        await model.replace()
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(model.alert, .replaceUnverified)
    }

    func testReplaceOutsideTheReviewDoesNothing() async {
        let fake = Fake()
        let model = ConfigurationImportModel(fileName: "x.toml", environment: fake.environment)
        let closes = await model.replace()
        XCTAssertFalse(closes)
        await model.reviewAgain()
        XCTAssertEqual(model.phase, .checking("x.toml"))
        XCTAssertTrue(fake.applied.isEmpty)
    }

    func testUndoRestoresOrReportsOnlyVerifiedState() {
        let status = ConfigurationUndoStatus(fingerprint: "fp-1", hasNewerEdits: false)
        var adopted = 0
        func run(_ outcome: ConfigurationOutcome, after: String?) -> ConfigurationUndo.Result {
            ConfigurationUndo.run(status: status, presentation: Data(), undo: { expected, _ in
                XCTAssertEqual(expected, "fp-1")
                return outcome
            }, currentFingerprint: { _ in after }, adopt: { adopted += 1 })
        }
        XCTAssertEqual(run(.applied(ConfigurationPointer(generation: 3, directory: "g-000003")), after: "fp-3"), .restored)
        XCTAssertEqual(adopted, 1)
        XCTAssertEqual(run(.conflict, after: "fp-2"), .failed)
        XCTAssertEqual(run(.failed(.pointer), after: "fp-1"), .failed)
        XCTAssertEqual(run(.failed(.pointer), after: "fp-2"), .unverified)
        XCTAssertEqual(run(.unavailable, after: nil), .unverified)
        XCTAssertEqual(adopted, 1)
    }

    func testCopy() {
        XCTAssertEqual(ConfigurationCopy.fontsUnavailable(1), "1 font unavailable")
        XCTAssertEqual(ConfigurationCopy.fontsUnavailable(3), "3 fonts unavailable")
        XCTAssertEqual(ConfigurationCopy.moreProblems(1), "1 More Problem")
        XCTAssertEqual(ConfigurationCopy.moreProblems(4), "4 More Problems")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        XCTAssertEqual(ConfigurationCopy.importedAt(now.addingTimeInterval(-60), now: now), "Imported today at \(time(now.addingTimeInterval(-60)))")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(ConfigurationCopy.importedAt(yesterday, now: now), "Imported yesterday at \(time(yesterday))")
        let older = Calendar.current.date(byAdding: .day, value: -9, to: now)!
        XCTAssertEqual(ConfigurationCopy.importedAt(older, now: now),
                       "Imported \(older.formatted(date: .abbreviated, time: .omitted)) at \(time(older))")
        XCTAssertEqual(UTType.uniboardConfiguration.preferredFilenameExtension, "toml")
        XCTAssertTrue(UTType.uniboardConfiguration.conforms(to: .plainText))
    }

    func testInLibraryMatchesImportedFilesAndInstalledFaces() {
        let fonts = [CustomFont(filename: "a.ttf", displayName: "A", postScriptName: "A-Regular", sha256: "abc", ranges: []),
                     CustomFont(filename: "b", displayName: "Papyrus", postScriptName: "Papyrus", sha256: "def", ranges: [], installed: true)]
        func face(_ identity: FontFaceReference.Identity) -> FontFaceReference {
            FontFaceReference(source: .imported, family: "F", style: "Regular", postScriptName: "P", identity: identity)
        }
        XCTAssertTrue(ConfigurationService.inLibrary(face(.file(sha256: "abc", faceIndex: 0, variations: [:])), fonts: fonts))
        XCTAssertFalse(ConfigurationService.inLibrary(face(.file(sha256: "def", faceIndex: 0, variations: [:])), fonts: fonts))
        XCTAssertTrue(ConfigurationService.inLibrary(face(.process(postScriptName: "Papyrus", variations: [:])), fonts: fonts))
        XCTAssertFalse(ConfigurationService.inLibrary(face(.process(postScriptName: "A-Regular", variations: [:])), fonts: fonts))
    }

    #if DEBUG
    /// The `scale` UI test fixture changes only the Copy Image scale.
    func testScaleFixtureChangesOnlyTheCopyImageScale() throws {
        XCTAssertTrue(ConfigurationFixtures.names.contains("scale"))
        for (current, expected) in [(3, 2), (1, 2), (2, 1)] {
            var configuration = UniboardConfiguration.factoryDefaults
            configuration.imageColors.scale = current
            let data = try XCTUnwrap(ConfigurationFixtures.data(named: "scale", current: configuration))
            let decoded = try ConfigurationCodec.decode(data).get()
            XCTAssertEqual(decoded.configuration.imageColors.scale, expected)
            let diff = ConfigurationDiff(current: configuration, incoming: decoded.configuration)
            XCTAssertEqual(diff.change(.imageColors).lines, ["Image scale: \(current)× → \(expected)×"])
            XCTAssertEqual(diff.changes.filter { !$0.lines.isEmpty }.map(\.category), [.imageColors])
        }
    }
    #endif
}
#endif
