import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KoreanHangulRuntimeTests: XCTestCase {
    private func state(_ raw: String = "gksrnr") -> LanguageCompositionState {
        var state = LanguageCompositionState(documentID: UUID(), mode: .koreanTwoSetHangul,
                                              packRevision: "verified-pack", dictionaryRevision: 0)
        XCTAssertEqual(state.append(raw, origin: .normalKeyTap) { _, raw in
            KoreanTwoSetKeyboard.accepts(raw) ? raw : nil
        }, .accepted)
        return state
    }
    private func ready(_ state: inout LanguageCompositionState, output: String = "한국") throws -> LanguageCompositionToken {
        let request = try XCTUnwrap(state.requestConversion())
        XCTAssertTrue(state.receive(.init(token: request.token, preedit: output, candidates: [
            .init(id: "hangul-word", output: output, source: .engine,
                  consumedInputScalars: request.rawInput.unicodeScalars.count)
        ])))
        return request.token
    }

    func testRawCaseIsSemanticAndNeverNormalized() {
        var value = state("Rk")
        XCTAssertEqual(value.rawInput, "Rk")
        XCTAssertEqual(value.backspace(), [])
        XCTAssertEqual(value.rawInput, "R")
        XCTAssertEqual(KoreanTwoSetKeyboard.label(for: "r"), "ㄱ")
        XCTAssertEqual(KoreanTwoSetKeyboard.label(for: "R"), "ㄲ")
    }
    func testAll52FacesAndSevenShiftForms() {
        let keys = KoreanTwoSetKeyboard.rows.flatMap { $0 }
        XCTAssertEqual(keys.count, 26)
        XCTAssertEqual(Set(keys).count, 26)
        var changes = 0
        for key in keys {
            XCTAssertNotNil(KoreanTwoSetKeyboard.label(for: key))
            XCTAssertNotNil(KoreanTwoSetKeyboard.label(for: key.uppercased()))
            if KoreanTwoSetKeyboard.label(for: key) != KoreanTwoSetKeyboard.label(for: key.uppercased()) { changes += 1 }
        }
        XCTAssertEqual(changes, 7)
        XCTAssertEqual(KoreanTwoSetKeyboard.accessibleName(for: "ㄲ"), "쌍기역")
        XCTAssertFalse(KoreanTwoSetKeyboard.accepts("한글"))
        XCTAssertFalse(KoreanTwoSetKeyboard.accepts("r k"))
        XCTAssertFalse(KoreanTwoSetKeyboard.accepts(""))
        XCTAssertTrue(KoreanTwoSetKeyboard.accepts(String(repeating: "R", count: 256)))
        XCTAssertFalse(KoreanTwoSetKeyboard.accepts(String(repeating: "R", count: 257)))
    }
    func testPendingNeverCommitsOrFallsBackToRawIDs() throws {
        var value = state()
        let pending = try XCTUnwrap(value.requestConversion())
        XCTAssertEqual(value.choose(candidateID: "hangul-word", expectedToken: pending.token, suffix: " "), [])
        XCTAssertEqual(value.resolveBoundary(.commitLiteral, expectedToken: pending.token), [])
        XCTAssertEqual(value.rawInput, "gksrnr")
    }
    func testSpaceOneGuardedEffectAndReplayDoesNotAppendAgain() throws {
        var value = state()
        let token = try ready(&value)
        XCTAssertEqual(value.choose(candidateID: "hangul-word", expectedToken: token,
                                    suffix: LanguageInputMode.koreanTwoSetHangul.conversionSpaceSuffix),
                       [.commit(text: "한국 ", remainingInput: "")])
        XCTAssertEqual(value.choose(candidateID: "hangul-word", expectedToken: token, suffix: " "), [])
        XCTAssertEqual(value.rawInput, "")
    }
    func testTapAndReturnAreSuffixFree() throws {
        for _ in 0..<2 {
            var value = state()
            let token = try ready(&value)
            XCTAssertEqual(value.choose(candidateID: "hangul-word", expectedToken: token),
                           [.commit(text: "한국", remainingInput: "")])
        }
        XCTAssertEqual(LanguageInputMode.japaneseRomaji.conversionSpaceSuffix, "")
        XCTAssertEqual(LanguageInputMode.mandarinPinyin.conversionSpaceSuffix, "")
    }
    func testEditDocumentAndResourceChangesRevokeReadyWord() throws {
        for mutation in 0..<3 {
            var value = state()
            let token = try ready(&value)
            switch mutation {
            case 0: _ = value.backspace()
            case 1: value.changeDocument(to: UUID())
            default: value.changeResources(packRevision: "replacement", dictionaryRevision: 0)
            }
            XCTAssertEqual(value.choose(candidateID: "hangul-word", expectedToken: token, suffix: " "), [])
        }
    }
    func testLateResultCannotReplaceNewKeystroke() throws {
        var value = state("rk")
        let request = try XCTUnwrap(value.requestConversion())
        XCTAssertEqual(value.append("s", origin: .normalKeyTap) { _, raw in raw }, .accepted)
        XCTAssertFalse(value.receive(.init(token: request.token, preedit: "가", candidates: [
            .init(id: "hangul-word", output: "가", source: .engine, consumedInputScalars: 2)
        ])))
        XCTAssertNil(value.visibleResult)
        XCTAssertEqual(value.rawInput, "rks")
    }
    func testMalformedLiteralCustomPartialOrLatinResultsFailClosed() throws {
        for (source, output, consumed) in [
            (LanguageConversionCandidateSource.literal, "가", 2), (.custom, "가", 2),
            (.engine, "rk", 2), (.engine, "가", 1)
        ] {
            var value = state("rk")
            let request = try XCTUnwrap(value.requestConversion())
            XCTAssertFalse(value.receive(.init(token: request.token, preedit: output, candidates: [
                .init(id: "word", output: output, source: source, consumedInputScalars: consumed)
            ])))
            XCTAssertNil(value.visibleResult)
        }
    }
    func testModeCapabilitiesSeparateABIFromMyWordsAndDeferredRomaja() {
        XCTAssertEqual(LanguageInputMode.koreanTwoSetHangul.conversionEngineABI, "uniboard-hangul-1")
        XCTAssertFalse(LanguageInputMode.koreanTwoSetHangul.supportsConversionMyWords)
        XCTAssertFalse(LanguageInputMode.koreanTwoSetHangul.offersLiteralConversion)
        XCTAssertNil(LanguageInputMode.koreanRomaja.conversionEngineABI)
        XCTAssertFalse(LanguageInputMode.koreanRomaja.supportsConversionMyWords)
        XCTAssertTrue(LanguageInputMode.japaneseRomaji.supportsConversionMyWords)
        XCTAssertTrue(LanguageInputMode.mandarinPinyin.supportsConversionMyWords)
        XCTAssertTrue(LanguageInputSettings.englishAssistanceAvailable)
    }
    func testIndependentThreeRowLayoutHasNoNumberRowAndDoesNotMutateSavedArrangement() {
        var saved = MainKeyboardArrangement.standard(for: .english)
        saved.keys.reverse()
        let before = saved
        let hangul = MainKeyboardArrangement.letters(for: .english)
        XCTAssertEqual(hangul.keyRows(widePad: false), 3)
        XCTAssertEqual(hangul.keyRows(widePad: true), 3)
        XCTAssertEqual(hangul.missingDigits, MainKeyboardArrangement.digits)
        XCTAssertEqual(hangul.letterRows, KoreanTwoSetKeyboard.rows)
        XCTAssertEqual(saved, before)
        let plan = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 44,
            sceneHeight: 800, conversionEnabled: true, surfaceAvailable: true,
            baselineKeyRows: 3, prefersCompactShelf: true)
        XCTAssertEqual(plan.shelfHeight, 44)
        XCTAssertEqual(plan.typingKeyHeight, 44)
        let constrained = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 44,
            sceneHeight: 800, actualGrantedHeight: 250, conversionEnabled: true, surfaceAvailable: true,
            baselineKeyRows: 3, hostHeightIsSettled: true, prefersCompactShelf: true)
        XCTAssertEqual(constrained.shelfHeight, 0)
        XCTAssertTrue(constrained.needsOverlayChoices)
    }
    func testSettingsAndConfigurationPreserveBothKoreanIdentities() throws {
        let pin = LanguageInputSettings.PackReference(mode: .koreanTwoSetHangul,
            packID: "korean-hangul-2set", version: "1", archiveSHA256: String(repeating: "a", count: 64))
        let deferred = LanguageInputSettings.PackReference(mode: .koreanRomaja,
            packID: "deferred-romaja", version: "1", archiveSHA256: String(repeating: "b", count: 64))
        let settings = LanguageInputSettings.Value(enabledModes: [.direct, .koreanRomaja, .koreanTwoSetHangul],
            englishSuggestions: true, englishAutocorrection: true, packReferences: [pin, deferred])
        let bytes = try XCTUnwrap(LanguageInputSettings.encode(settings))
        XCTAssertEqual(LanguageInputSettings.decode(bytes), settings)
        XCTAssertTrue(settings.effectiveEnglishAutocorrection, "Saved English opt-in remains independent of enabled Korean modes")
        XCTAssertFalse(LanguageInputSettings.visibleModeOrder.contains(.koreanRomaja))
        XCTAssertTrue(LanguageInputSettings.visibleModeOrder.contains(.koreanTwoSetHangul))
        var configuration = UniboardConfiguration.factoryDefaults
        configuration.languageInput = settings
        let exported = try XCTUnwrap(ConfigurationCodec.encode(configuration))
        XCTAssertEqual(try ConfigurationCodec.decode(exported).get().configuration, configuration)
        XCTAssertEqual(ConfigurationCodec.encode(try ConfigurationCodec.decode(exported).get().configuration), exported)
    }
    func testOverlappingShiftedJamoReleasesKeepBothCapturedRawIDs() throws {
        var live = KeyboardTypingState()
        live.pressShift(at: 1)
        let captured = live
        let q = KoreanTwoSetKeyboard.keyID("q", shifted: captured.shift != .lowercase)
        let k = KoreanTwoSetKeyboard.keyID("k", shifted: captured.shift != .lowercase)
        var raw = ""
        for (key, capturedID) in [("q", q), ("k", k)] {
            XCTAssertTrue(KoreanTwoSetKeyboard.acceptsHeldKey(contextIsCurrent: true,
                mode: .koreanTwoSetHangul, captured: captured, current: live))
            raw += capturedID
            // Match didInsertTypingKey: never consume a newer Shift choice.
            if live == captured { live.didInsertKey(key) }
        }
        XCTAssertEqual(raw, "QK")
        XCTAssertEqual(live.shift, .lowercase)
        // Test-only mapping fixture; production still requires downloaded JSON.
        let keys = KoreanTwoSetKeyboard.rows.flatMap { $0 }
        let entries = try (keys + keys.map { $0.uppercased() }).map { key in
            KoreanHangulComposer.KeyMapping.Entry(key: key,
                jamo: try XCTUnwrap(KoreanTwoSetKeyboard.label(for: key)))
        }
        let composer = KoreanHangulComposer(mapping: try .init(entries: entries))
        XCTAssertEqual(try composer.compose(raw), "빠")
    }

    func testHeldJamoSurvivesAnotherFingerShiftToggleWithoutConsumingIt() {
        var live = KeyboardTypingState()
        let captured = live
        let raw = KoreanTwoSetKeyboard.keyID("r", shifted: captured.shift != .lowercase)
        live.pressShift(at: 1)
        XCTAssertTrue(KoreanTwoSetKeyboard.acceptsHeldKey(contextIsCurrent: true,
            mode: .koreanTwoSetHangul, captured: captured, current: live))
        if live == captured { live.didInsertKey("r") }
        XCTAssertEqual(raw, "r")
        XCTAssertEqual(live.shift, .uppercase)
    }

    func testHeldJamoStillRejectsScopeModeLayoutAndAlphabetChanges() throws {
        let captured = KeyboardTypingState()
        // The untouched controller current() includes document, interaction and
        // rendered-mode identities. Any mismatch supplies false here.
        for _ in ["document", "interaction", "rendered-mode"] {
            XCTAssertFalse(KoreanTwoSetKeyboard.acceptsHeldKey(contextIsCurrent: false,
                mode: .koreanTwoSetHangul, captured: captured, current: captured))
        }
        XCTAssertFalse(KoreanTwoSetKeyboard.acceptsHeldKey(contextIsCurrent: true,
            mode: .direct, captured: captured, current: captured))
        var page = captured
        page.selectLayout(.numbers)
        XCTAssertFalse(KoreanTwoSetKeyboard.acceptsHeldKey(contextIsCurrent: true,
            mode: .koreanTwoSetHangul, captured: captured, current: page))
        var alphabet = captured
        alphabet.selectAlphabet(try XCTUnwrap(KeyboardAlphabet.alphabet(id: "el")))
        XCTAssertFalse(KoreanTwoSetKeyboard.acceptsHeldKey(contextIsCurrent: true,
            mode: .koreanTwoSetHangul, captured: captured, current: alphabet))
    }

}
