#if canImport(UIKit) && !canImport(UniboardCore)
import Foundation
import XCTest
@testable import Uniboard

@MainActor
final class MainArrangementPreferencesTests: XCTestCase {
    private func fixture(writer: KeyboardKeySettings.AtomicWriter? = nil) throws -> (KeyboardKeyPreferences, KeyboardKeySettings, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MainArrangement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let settings: KeyboardKeySettings
        if let writer { settings = .init(containerURL: { directory }, writeAtomically: writer) }
        else { settings = .init(containerURL: { directory }) }
        XCTAssertTrue(settings.save(.defaults))
        return (KeyboardKeyPreferences(settings: settings, location: .init(root: { directory })), settings, directory)
    }
    private func arrangement(_ alignment: KeyboardRowAlignment) -> MainKeyboardArrangement {
        var rows = MainKeyboardArrangement.standard(for: .english).resolvedRows
        rows[0].alignment = alignment
        rows[0].cells.insert(.halfGap, at: 0)
        return MainKeyboardArrangement(rows: rows)
    }

    func testUndoRestoresNilArrangementWithoutTouchingLiteralKeyLayers() throws {
        let (preferences, settings, _) = try fixture()
        XCTAssertTrue(preferences.save(layers: [.tap: ["e\u{301}"], .longPress: ["👩🏽‍💻"], .swipeUp: []], keyID: "letter.a"))
        let before = preferences.snapshot
        XCTAssertTrue(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .restored)
        XCTAssertEqual(settings.loadForEditing(), before)
        XCTAssertNil(preferences.snapshot.arrangement(for: "en"))
        XCTAssertEqual(Array(preferences.snapshot.candidates(for: "letter.a", gesture: .tap)![0].utf8), Array("e\u{301}".utf8))
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .invalidated)
    }

    func testNewestSuccessfulEditAndNoopHaveOneStepOnly() throws {
        let (preferences, _, _) = try fixture()
        XCTAssertTrue(preferences.saveArrangement(arrangement(.center), alphabetID: "en"))
        let first = preferences.snapshot
        XCTAssertTrue(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
        let event = preferences.successfulEdit?.id
        XCTAssertTrue(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
        XCTAssertEqual(preferences.successfulEdit?.id, event)
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .restored)
        XCTAssertEqual(preferences.snapshot, first)
        XCTAssertNil(preferences.arrangementUndoAlphabetID)
    }

    func testFailedSaveAndRestoreRetainPreviousStepForRetry() throws {
        var fail = false
        let (preferences, _, _) = try fixture(writer: { data, url in
            if fail { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertTrue(preferences.saveArrangement(arrangement(.center), alphabetID: "en"))
        let event = preferences.successfulEdit?.id
        fail = true
        XCTAssertFalse(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
        XCTAssertEqual(preferences.successfulEdit?.id, event)
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .failed)
        XCTAssertEqual(preferences.arrangementUndoAlphabetID, "en")
        fail = false
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .restored)
        XCTAssertEqual(preferences.snapshot, .defaults)
    }

    func testTapRemapEmitsSuccessfulEditButRefreshDoesNotAndInvalidatesUndo() throws {
        let (preferences, _, _) = try fixture()
        XCTAssertTrue(preferences.saveArrangement(arrangement(.center), alphabetID: "en"))
        let event = preferences.successfulEdit?.id
        preferences.refresh()
        XCTAssertEqual(preferences.successfulEdit?.id, event)
        XCTAssertTrue(preferences.save(["one"], keyID: "digit.1", gesture: .tap, replacing: nil))
        XCTAssertNotEqual(preferences.successfulEdit?.id, event)
        XCTAssertNil(preferences.arrangementUndoAlphabetID)
        let edit = try XCTUnwrap(preferences.successfulEdit)
        let before = KeyboardMergedSymbolsPolicy.eligibility(settings: edit.before, alphabet: .english, availableWidth: 386, isPad: false)
        let after = KeyboardMergedSymbolsPolicy.eligibility(settings: edit.after, alphabet: .english, availableWidth: 386, isPad: false)
        XCTAssertEqual(before, .merged); XCTAssertEqual(after, .missingDigits)
        XCTAssertNotNil(KeyboardMergedSymbolsPolicy.transitionMessage(from: before, to: after))
    }

    func testExternalContentConflictNeverOverwritesLaterKeyActions() throws {
        let (preferences, settings, _) = try fixture()
        XCTAssertTrue(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
        let changed = try XCTUnwrap(preferences.snapshot.updating(["changed"], for: "letter.a", gesture: .tap))
        XCTAssertTrue(settings.save(changed))
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .invalidated)
        XCTAssertEqual(settings.loadForEditing(), changed)
    }

    func testMissingCorruptOrUnrelatedConfigurationStateInvalidatesRestore() throws {
        for scenario in 0..<3 {
            let (preferences, settings, directory) = try fixture()
            XCTAssertTrue(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
            let file = directory.appendingPathComponent(KeyboardKeySettings.filename)
            if scenario == 0 { try FileManager.default.removeItem(at: file) }
            else if scenario == 1 { try Data("corrupt".utf8).write(to: file) }
            else { try Data("changed config".utf8).write(to: directory.appendingPathComponent(ImageColorSettings.filename)) }
            XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .invalidated)
            if scenario == 0 { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
            if scenario == 1 { XCTAssertEqual(try Data(contentsOf: file), Data("corrupt".utf8)); XCTAssertNil(settings.loadForEditing()) }
        }
    }

    func testBusyConfigurationLockRefusesRestoreWithoutConsumingHistory() throws {
        let (preferences, _, directory) = try fixture()
        XCTAssertTrue(preferences.saveArrangement(arrangement(.right), alphabetID: "en"))
        try SharedConfigurationLocation(root: { directory }).withWriterLock {
            XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .failed)
        }
        XCTAssertEqual(preferences.undoArrangement(alphabetID: "en"), .restored)
    }
}
#endif
