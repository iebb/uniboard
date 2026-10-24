#if canImport(UIKit)
import Foundation
import XCTest
import UIKit
@testable import Uniboard

/// Edit Configuration: Validate never writes, any edit clears the result,
/// Apply checks the current text again and goes through the import review,
/// and a configuration that changed since the editor opened is never
/// overwritten on a stale check.
@MainActor
final class ConfigurationEditorModelTests: XCTestCase {
    private final class Fake {
        var current = UniboardConfiguration.factoryDefaults
        var fingerprint: String? = "fp-1"
        var outcome: ConfigurationOutcome = .applied(ConfigurationPointer(generation: 2, directory: "g-000002"))
        var unavailable: [FontFaceReference] = []
        var applied: [(files: [String: Data], expected: String)] = []
        var adopted = 0
        var announced: [String] = []

        var environment: ConfigurationImportEnvironment {
            ConfigurationImportEnvironment(
                read: { _ in XCTFail("The editor never reads a file"); return Data() },
                current: { (self.current, self.fingerprint) },
                unavailableFonts: { faces in faces.filter(self.unavailable.contains) },
                presentation: { Data("presentation".utf8) },
                apply: { files, expected, _ in
                    self.applied.append((files, expected))
                    return self.outcome
                },
                currentFingerprint: { _ in self.fingerprint },
                adopt: { self.adopted += 1 })
        }

        @MainActor func editor() -> ConfigurationEditorModel {
            ConfigurationEditorModel(environment: environment, encode: { ConfigurationCodec.encode($0) },
                                     announce: { self.announced.append($0) })
        }
    }

    private func loaded(_ fake: Fake) async throws -> ConfigurationEditorModel {
        let model = fake.editor()
        XCTAssertNil(model.loaded, "Preparing until the text is encoded")
        XCTAssertFalse(model.canValidate)
        await model.load()
        XCTAssertNotNil(model.loaded)
        return model
    }

    /// Runs `work` until the editor shows Checking, and returns with the
    /// check still suspended (its result can only land on a later yield).
    private func startChecking(_ model: ConfigurationEditorModel, _ work: @escaping @MainActor () async -> Void) async -> Task<Void, Never> {
        let task = Task { @MainActor in await work() }
        for _ in 0..<1000 where model.status != .checking { await Task.yield() }
        return task
    }

    /// The loaded text with Extra Unicode Fonts turned on.
    private func validEdit(_ text: String) -> String {
        text.replacingOccurrences(of: "extra_unicode_fonts = false", with: "extra_unicode_fonts = true")
    }

    func testOpensWithTheExportedConfigurationAndItsFingerprint() async throws {
        let fake = Fake()
        fake.current.favorites = ["★"]
        let model = try await loaded(fake)
        XCTAssertEqual(model.text, String(decoding: try XCTUnwrap(ConfigurationCodec.encode(fake.current)), as: UTF8.self))
        XCTAssertEqual(model.fingerprint, "fp-1")
        XCTAssertEqual(model.status, .helper)
        XCTAssertEqual(model.statusTitle, "Edit your configuration in TOML. Validate checks your edits without changing your settings. Apply saves them.")
        XCTAssertFalse(model.isEdited)
        XCTAssertFalse(model.canApply, "Apply waits for an edit")
        XCTAssertTrue(model.canValidate, "Validate works on unedited text too")
        await model.load()
        XCTAssertEqual(model.status, .helper, "Loading twice changes nothing")
    }

    func testAnUnencodableConfigurationFailsToLoad() async {
        let fake = Fake()
        let model = ConfigurationEditorModel(environment: fake.environment, encode: { _ in nil }, announce: { _ in })
        await model.load()
        XCTAssertTrue(model.loadFailed)
        XCTAssertNil(model.loaded)
        XCTAssertFalse(model.canValidate)
    }

    func testValidateNeverAppliesOrWrites() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = validEdit(model.text)
        XCTAssertEqual(model.status, .unchecked)
        await model.validate()
        XCTAssertEqual(model.status, .valid(warnings: []))
        XCTAssertEqual(model.statusTitle, "Configuration is valid. Your settings haven’t changed.")
        XCTAssertEqual(fake.announced.last, "Configuration is valid. Your settings haven’t changed.")
        XCTAssertNil(model.review, "Validate never opens the review")

        model.text = "schema_version = 1\n[settings]\nextra_unicode_fonts = \"yes\"\ncolour = true\n"
        await model.validate()
        guard case let .invalid(problems) = model.status else { return XCTFail("\(model.status)") }
        XCTAssertGreaterThanOrEqual(problems.count, 2)
        XCTAssertEqual(model.statusTitle, "Fix these errors before applying")
        XCTAssertEqual(fake.announced.last, "Fix these errors before applying")
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.adopted, 0)
    }

    func testEveryProblemIsListedInTheCheckersOwnWords() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        let text = "schema_version = 1\n[settings]\nextra_unicode_fonts = \"yes\"\ncolour = true\n"
        model.text = text
        await model.validate()
        guard case let .invalid(problems) = model.status else { return XCTFail("\(model.status)") }
        guard case let .failure(expected) = ConfigurationCodec.decode(Data(text.utf8)) else { return XCTFail() }
        XCTAssertEqual(problems.map(\.text), expected.messages, "Every problem, unchanged")
        XCTAssertFalse(problems.contains(where: \.isLocated), "Field problems have no line and are never guessed")
        XCTAssertFalse(problems.contains { $0.text == "Invalid TOML" })

        model.text = "schema_version = 1\n[settings\n"
        await model.validate()
        guard case let .invalid(syntax) = model.status else { return XCTFail("\(model.status)") }
        XCTAssertEqual(syntax.count, 1)
        XCTAssertTrue(syntax[0].text.hasPrefix("Check line 2, column "), syntax[0].text)
        XCTAssertEqual(syntax[0].line, 2)
        XCTAssertNotNil(syntax[0].column)
    }

    func testEditingClearsTheResult() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = validEdit(model.text)
        await model.validate()
        XCTAssertEqual(model.status, .valid(warnings: []))
        model.text += "# note\n"
        XCTAssertEqual(model.status, .unchecked)
        XCTAssertEqual(model.statusTitle, "Edits haven’t been checked.")
        model.text = model.text
        XCTAssertEqual(model.status, .unchecked, "Setting the same text isn't an edit")
    }

    func testAnEditWhileCheckingDiscardsThatResult() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = validEdit(model.text)
        let checking = await startChecking(model) { await model.validate() }
        XCTAssertEqual(model.status, .checking)
        XCTAssertFalse(model.canValidate)
        XCTAssertFalse(model.canApply)
        model.text += "# later\n"
        await checking.value
        XCTAssertTrue(model.text.hasSuffix("# later\n"))
        XCTAssertEqual(model.status, .unchecked, "A result for older text never shows")
        XCTAssertNil(model.review)
    }

    func testANormalizationOnlyChangeIsAnEdit() async throws {
        let fake = Fake()
        fake.current.favorites = ["\u{E9}"]
        let model = try await loaded(fake)
        let loaded = try XCTUnwrap(model.loaded)
        XCTAssertTrue(loaded.unicodeScalars.contains("\u{E9}"), "The export writes é as is")
        await model.validate()
        XCTAssertEqual(model.status, .valid(warnings: []))
        var decomposed = String.UnicodeScalarView()
        for scalar in loaded.unicodeScalars {
            if scalar == "\u{E9}" { decomposed.append("e"); decomposed.append("\u{301}") } else { decomposed.append(scalar) }
        }
        let edited = String(decomposed)
        XCTAssertEqual(edited, loaded, "Canonically equivalent, so String == can't tell them apart")
        model.text = edited
        XCTAssertEqual(model.status, .unchecked, "é → e + U+0301 is an edit")
        XCTAssertTrue(model.isEdited)
        XCTAssertTrue(model.canApply)
        model.text = loaded
        XCTAssertFalse(model.isEdited, "Back to the exact loaded scalars")
    }

    func testEmptyTextIsNeverAReset() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = "  \n\t\n"
        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.statusTitle, "Enter a configuration before validating or applying.")
        XCTAssertFalse(model.canApply)
        await model.validate()
        XCTAssertEqual(model.status, .empty)
        await model.apply()
        XCTAssertEqual(model.status, .empty)
        XCTAssertNil(model.review)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    func testInvalidTextIsNeverApplied() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = model.text.replacingOccurrences(of: "extra_unicode_fonts = false", with: "extra_unicode_fonts = maybe")
        XCTAssertTrue(model.canApply)
        await model.apply()
        guard case .invalid = model.status else { return XCTFail("\(model.status)") }
        XCTAssertNil(model.review, "Nothing is pushed")
        XCTAssertNil(model.alert)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.announced.last, "Fix these errors before applying")
    }

    func testApplyChecksTheCurrentTextAgain() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        let original = model.text
        model.text = validEdit(original)
        await model.validate()
        XCTAssertEqual(model.status, .valid(warnings: []))
        // An earlier success never authorizes later edits.
        model.text = validEdit(original) + "[settings]\n"
        await model.apply()
        guard case .invalid = model.status else { return XCTFail("\(model.status)") }
        XCTAssertNil(model.review)

        model.text = validEdit(original)
        await model.apply()
        let review = try XCTUnwrap(model.review)
        XCTAssertEqual(review.mode, .editor)
        guard case let .review(shown) = review.phase else { return XCTFail("\(review.phase)") }
        XCTAssertEqual(shown.diff.change(.settings).lines.first, "Extra Unicode Fonts: Off → On")
        XCTAssertEqual(shown.fingerprint, "fp-1")
        XCTAssertTrue(fake.applied.isEmpty, "The review writes nothing until its Apply")
    }

    func testAChangedConfigurationAsksToReviewAgainAndNeverApplies() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = validEdit(model.text)
        fake.fingerprint = "fp-2"
        await model.apply()
        XCTAssertEqual(model.alert, .changed)
        XCTAssertNil(model.review)
        XCTAssertTrue(fake.applied.isEmpty)

        model.cancelChanged()
        XCTAssertNil(model.alert)
        XCTAssertNil(model.review)
        await model.reviewAgain()
        XCTAssertNil(model.review, "Cancel dropped the stale result")
        XCTAssertEqual(model.fingerprint, "fp-1")

        await model.apply()
        XCTAssertEqual(model.alert, .changed)
        fake.current.favorites = ["★"]
        fake.fingerprint = "fp-3"
        await model.reviewAgain()
        XCTAssertNil(model.alert)
        let review = try XCTUnwrap(model.review)
        guard case let .review(shown) = review.phase else { return XCTFail("\(review.phase)") }
        XCTAssertEqual(shown.fingerprint, "fp-3", "Compared with what's in effect now")
        XCTAssertEqual(model.fingerprint, "fp-3")
        XCTAssertTrue(fake.applied.isEmpty)
    }

    func testAnEditDuringReviewAgainPushesNoStaleReview() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = validEdit(model.text)
        fake.fingerprint = "fp-2"
        await model.apply()
        XCTAssertEqual(model.alert, .changed)

        let again = await startChecking(model) { await model.reviewAgain() }
        XCTAssertEqual(model.status, .checking, "Review Again checks like Apply")
        XCTAssertNil(model.alert)
        XCTAssertFalse(model.canValidate)
        XCTAssertFalse(model.canApply)
        model.text += "# later\n"
        await again.value
        XCTAssertNil(model.review, "A review of older text is never pushed")
        XCTAssertEqual(model.status, .unchecked)
        XCTAssertEqual(model.fingerprint, "fp-1", "Nothing was reviewed against the newer configuration")
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertFalse(model.didApply)

        // Review Again reviews the text on screen now.
        await model.apply()
        XCTAssertEqual(model.alert, .changed)
        await model.reviewAgain()
        let review = try XCTUnwrap(model.review)
        guard case let .review(shown) = review.phase else { return XCTFail("\(review.phase)") }
        XCTAssertEqual(shown.fingerprint, "fp-2")
        XCTAssertEqual(shown.diff.change(.settings).lines.first, "Extra Unicode Fonts: Off → On")
        await review.replace()
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.applied.first?.expected, "fp-2")
        XCTAssertTrue(model.didApply)
    }

    func testASuccessfulApplyGoesThroughTheImportPipelineOnce() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        model.text = validEdit(model.text)
        await model.apply()
        let review = try XCTUnwrap(model.review)
        XCTAssertFalse(model.didApply)
        let closes = await review.replace()
        XCTAssertFalse(closes)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.applied.first?.expected, "fp-1")
        XCTAssertEqual(Set(try XCTUnwrap(fake.applied.first).files.keys), Set(SharedConfigurationLocation.snapshotFiles))
        XCTAssertEqual(fake.adopted, 1)
        XCTAssertEqual(review.phase, .imported(unavailableFonts: []))
        XCTAssertTrue(model.didApply)
        model.review = nil
        XCTAssertTrue(model.didApply, "Stored, not derived from the review still being shown")
    }

    func testAFailedApplyKeepsTheDraft() async throws {
        let fake = Fake()
        fake.outcome = .failed(.publish)
        let model = try await loaded(fake)
        let draft = validEdit(model.text)
        model.text = draft
        await model.apply()
        let review = try XCTUnwrap(model.review)
        await review.replace()
        XCTAssertEqual(review.alert, .replaceFailed)
        XCTAssertFalse(model.didApply)
        model.review = nil
        XCTAssertEqual(model.text, draft)
        XCTAssertEqual(model.fingerprint, "fp-1")
    }

    func testWarningsForMissingSectionsFontsAndRetiredSettings() async throws {
        let fake = Fake()
        let missing = FontFaceReference(
            source: .imported, family: "Fixture Sans", style: "Regular", postScriptName: "FixtureSans-Regular",
            identity: .file(sha256: String(repeating: "0", count: 64), faceIndex: 0, variations: [:]))
        fake.unavailable = [missing]
        let model = try await loaded(fake)
        var next = fake.current
        next.fontRules = [FontRule(selector: .codePoint(0x2603), face: missing)]
        var document = ConfigurationCodec.document(next)
        document["image_colors"] = nil
        var settings = try XCTUnwrap(document["settings"]?.tableValue)
        settings["number_row"] = .boolean(true)
        document["settings"] = .table(settings)
        model.text = TOMLDocument.write(document)
        await model.validate()
        XCTAssertEqual(model.status, .valid(warnings: [
            "Sections missing from this configuration will reset to defaults.",
            "1 font unavailable: Fixture Sans Regular",
            "Ignored settings: settings.number_row",
        ]))
        XCTAssertEqual(model.statusTitle, "Configuration is valid. Review the warnings before applying.")
        XCTAssertTrue(fake.applied.isEmpty)
    }

    /// The checker counts columns in Unicode scalars; UITextView in UTF-16.
    func testErrorColumnsBecomeUTF16OffsetsForTheCursor() async throws {
        let fake = Fake()
        let model = try await loaded(fake)
        let text = "schema_version = 1\n[settings]\nconscript = \"あ😀\" !\n"
        model.text = text
        await model.validate()
        guard case let .invalid(problems) = model.status, let problem = problems.first else { return XCTFail("\(model.status)") }
        XCTAssertEqual(problem.text, "Check line 3, column 18: Expected a new line.")
        XCTAssertEqual(problem.line, 3)
        XCTAssertEqual(problem.column, 18, "あ and 😀 are one scalar each")
        model.focus(problem)
        let offset = try XCTUnwrap(model.cursor).offset
        XCTAssertEqual(offset, 19 + 11 + 18, "😀 is two UTF-16 units")
        XCTAssertEqual((text as NSString).substring(from: offset), "!\n")

        // CRLF is one break, a byte order mark isn't counted, and an overlong column stops at the line end.
        XCTAssertEqual(ConfigurationEditorProblem.utf16Offset(in: "ab\r\ncd", line: 2, column: 2), 5)
        XCTAssertEqual(ConfigurationEditorProblem.utf16Offset(in: "ab\r\ncd", line: 1, column: 9), 2)
        XCTAssertEqual(ConfigurationEditorProblem.utf16Offset(in: "\u{FEFF}x = 1", line: 1, column: 3), 3)
        XCTAssertEqual(ConfigurationEditorProblem.utf16Offset(in: "x", line: 4, column: 1), 1)

        let unlocated = ConfigurationEditorProblem(id: 0, message: ConfigurationCodec.missingVersion)
        XCTAssertFalse(unlocated.isLocated)
        let before = model.cursor
        model.focus(unlocated)
        XCTAssertEqual(model.cursor, before, "A problem without a line never moves the cursor")
        XCTAssertNil(ConfigurationEditorProblem.location(in: "Check line x, column 1: Expected =."))
        XCTAssertNil(ConfigurationEditorProblem.location(in: "Check font_rules.rule[2].font: …"))
    }

    func testImportWordingIsUnchangedAndTheEditorHasItsOwn() {
        XCTAssertEqual(ConfigurationImportModel(fileName: "x.toml", environment: Fake().environment).mode, .importFile)
        let wording = ConfigurationImportModel.Mode.importFile.wording
        XCTAssertEqual(wording.title, "Review Import")
        XCTAssertEqual(wording.intro, "This will replace your current configuration. Review the changes before continuing.")
        XCTAssertEqual(wording.noChanges, "No changes to import")
        XCTAssertEqual(wording.missingSections, "Sections missing from this file will reset to defaults.")
        XCTAssertEqual(wording.backup, "Your previous configuration will be kept so you can undo this import.")
        XCTAssertEqual(wording.primary, "Replace Configuration")
        XCTAssertEqual(wording.inProgress, "Replacing configuration…")
        XCTAssertEqual(wording.success, "Configuration imported")
        XCTAssertEqual(wording.problemsTitle, "Couldn’t import configuration")
        XCTAssertEqual(wording.failureTitle, "Couldn’t replace configuration")
        XCTAssertEqual(wording.failureBody, "Your previous configuration is still in use.")
        XCTAssertEqual(wording.changedBody, "Changes were made after this preview. Review the import again before replacing your configuration.")

        let editor = ConfigurationImportModel.Mode.editor.wording
        XCTAssertEqual(editor.title, "Review Changes")
        XCTAssertEqual(editor.intro, "These edits will replace your current configuration.")
        XCTAssertEqual(editor.noChanges, "No changes to apply")
        XCTAssertEqual(editor.missingSections, "Sections missing from this configuration will reset to defaults.")
        XCTAssertEqual(editor.backup, "Your previous configuration will be kept so you can undo these changes.")
        XCTAssertEqual(editor.primary, "Apply")
        XCTAssertEqual(editor.inProgress, "Applying configuration…")
        XCTAssertEqual(editor.success, "Configuration applied")
        XCTAssertEqual(editor.failureTitle, "Couldn’t apply configuration")
        XCTAssertEqual(editor.failureBody, "Your previous configuration is still in use. Your edits are still here.")
        XCTAssertEqual(editor.changedBody, "Settings changed while you were editing. Review the changes again before applying.")
        XCTAssertEqual(ConfigurationCopy.changedTitle, "Your configuration changed")
    }

    func testErrorTextBreaksAfterDotsForDisplayOnly() {
        let message = "Check settings.browse.explore_grid_density: 3, 8, 16 or 32."
        XCTAssertEqual(ProblemText.breakingAfterDots(message[...]),
                       "Check settings.\u{200B}browse.\u{200B}explore_grid_density: 3, 8, 16 or 32.")
        XCTAssertEqual(ProblemText.breakingAfterDots("Check line 3, column 7: Expected a value. Then more."),
                       "Check line 3, column 7: Expected a value. Then more.", "Never after a full stop")
        let shown = ProblemText.display(message, monospaced: nil, textStyle: .footnote, color: .label,
                                        traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        XCTAssertEqual(shown.string.replacingOccurrences(of: "\u{200B}", with: ""), message)
        XCTAssertFalse(shown.string.contains("-"))
        shown.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
            let style = value as? NSParagraphStyle
            XCTAssertEqual(style?.hyphenationFactor, 0)
            XCTAssertEqual(style?.usesDefaultHyphenation, false)
        }
        let problem = ConfigurationEditorProblem(id: 0, message: message)
        XCTAssertEqual(problem.text, message, "The checker's message is never changed")
    }

    func testUndoWordingAndCaptions() {
        XCTAssertEqual(ConfigurationCopy.undo, "Undo Last Configuration Change")
        XCTAssertEqual(ConfigurationCopy.undoTitle, "Undo last configuration change?")
        XCTAssertEqual(ConfigurationCopy.undoBody, "Restore your previous configuration. Changes made since then will also be replaced.")
        XCTAssertEqual(ConfigurationCopy.restore, "Restore Previous Configuration")
        XCTAssertEqual(ConfigurationCopy.restored, "Previous configuration restored")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let time = now.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(ConfigurationCopy.changedAt(now, source: .importFile, now: now), "Imported today at \(time)")
        XCTAssertEqual(ConfigurationCopy.changedAt(now, source: .editor, now: now), "Applied today at \(time)")
        XCTAssertEqual(ConfigurationCopy.changedAt(now, source: nil, now: now), "Changed today at \(time)")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(ConfigurationCopy.changedAt(yesterday, source: .editor, now: now),
                       "Applied yesterday at \(yesterday.formatted(date: .omitted, time: .shortened))")
    }
}
#endif
