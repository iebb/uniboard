import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardTypingPolicyTests: XCTestCase {
    func testAutomaticCapitalizationAndLiteralCaseFlickNeverShiftANSINumbers() {
        var state = KeyboardTypingState()
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
        XCTAssertFalse(state.shiftsANSISymbols)
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "1", state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), "1")
        state.didInsertLiteralGesture()
        XCTAssertFalse(state.shiftsANSISymbols)
        state.pressShift(at: 1)
        state.pressShift(at: 2)
        XCTAssertTrue(state.shiftsANSISymbols)
        state.didInsertLiteralGesture()
        XCTAssertTrue(state.shiftsANSISymbols)
        state.didEditText()
        XCTAssertFalse(state.shiftsANSISymbols)
        state.synchronizeAutomaticCapitalization(false)
        state.pressShift(at: 3)
        XCTAssertTrue(state.shiftsANSISymbols)
        state.selectLayout(.numbers)
        XCTAssertFalse(state.shiftsANSISymbols)
    }
    func testANSIOrdinaryDigitsAndPunctuationConsumeOneShotShiftButKeepCapsLock() {
        for key in ["1", "`", "[", "\\", ";", "'", ",", ".", "/"] {
            var state = KeyboardTypingState()
            state.pressShift(at: 1)
            state.didInsertKey(key)
            XCTAssertEqual(state.shift, .uppercase)
            state.didInsertKey(key, ansiPad: true)
            XCTAssertEqual(state.shift, .lowercase)
            state.toggleCapsLock()
            state.didInsertKey(key, ansiPad: true)
            XCTAssertEqual(state.shift, .capsLock)
        }
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        for invalid in ["", "11", "A", "é", "\t", "\n"] {
            state.didInsertKey(invalid, ansiPad: true)
            XCTAssertEqual(state.shift, .uppercase)
        }
    }
    func testDedicatedCapsLockTogglesEveryCaseAndRemainsLockedThroughTypingAndAutomaticCapitalization() {
        var state = KeyboardTypingState()
        state.toggleCapsLock()
        XCTAssertEqual(state.shift, .capsLock)
        state.didInsertKey("a"); state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.output(for: "q"), "Q")
        XCTAssertEqual(state.shift, .capsLock)
        state.toggleCapsLock()
        XCTAssertEqual(state.shift, .lowercase)
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .lowercase, "Explicitly unlocking is a manual case choice")
        state.pressShift(at: 1)
        XCTAssertEqual(state.shift, .uppercase)
        state.toggleCapsLock()
        XCTAssertEqual(state.shift, .capsLock)
        state.pressShift(at: 1.1)
        XCTAssertEqual(state.shift, .lowercase)
        state.pressShift(at: 1.2)
        XCTAssertEqual(state.shift, .uppercase, "Caps actions clear the previous double-tap sequence")
    }

    func testDedicatedCapsLockCannotChangeNumberOrSymbolPageState() {
        for page in [KeyboardTypingLayout.numbers, .symbols] {
            var state = KeyboardTypingState()
            state.pressShift(at: 1)
            state.selectLayout(page)
            let before = state
            state.toggleCapsLock()
            XCTAssertEqual(state, before)
            XCTAssertEqual(state.layout, page)
            XCTAssertEqual(state.shift, .uppercase)
        }
    }

    func testLiteralGesturePreservesAutomaticUppercaseUntilAnOrdinaryLetterConsumesIt() {
        var state = KeyboardTypingState()
        state.synchronizeAutomaticCapitalization(true)
        state.didInsertLiteralGesture()
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .uppercase)
        XCTAssertEqual(state.output(for: "a"), "A")
        state.didInsertKey("a")
        XCTAssertEqual(state.shift, .lowercase)
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testLiteralGesturePreservesLowercaseAndManualShiftWithoutJoiningDoubleTapSequence() {
        var state = KeyboardTypingState()
        state.didInsertLiteralGesture()
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .lowercase)
        state.pressShift(at: 1)
        state.didInsertLiteralGesture()
        state.pressShift(at: 1.1)
        XCTAssertEqual(state.shift, .lowercase, "The flick breaks the previous Shift double-tap sequence")
        state.didInsertKey("a")
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testLiteralGestureNeverUnlocksCapsOrChangesTheSelectedPage() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1); state.pressShift(at: 1.1)
        state.didInsertLiteralGesture()
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .capsLock)
        state.didInsertKey("q")
        XCTAssertEqual(state.shift, .capsLock)
        for page in [KeyboardTypingLayout.numbers, .symbols, .letters] {
            state.selectLayout(page)
            state.didInsertLiteralGesture()
            XCTAssertEqual(state.layout, page)
            XCTAssertEqual(state.shift, .capsLock)
        }
        state.pressShift(at: .infinity)
        XCTAssertEqual(state.shift, .lowercase)
    }

    func testOrdinaryHostEditReleasesTheLiteralGestureCaseHint() {
        var state = KeyboardTypingState()
        state.didInsertLiteralGesture()
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .lowercase)
        state.didEditText()
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testDefaultIsLowercaseQWERTYWithAllLettersExactlyOnce() {
        let state = KeyboardTypingState()
        XCTAssertEqual(state.layout, .letters)
        XCTAssertEqual(state.shift, .lowercase)
        XCTAssertEqual(state.layout.rows.map { $0.joined() }, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        let keys = state.layout.rows.flatMap { $0 }
        XCTAssertEqual(keys.count, 26)
        XCTAssertEqual(Set(keys), Set(Array("abcdefghijklmnopqrstuvwxyz").map(String.init)))
        for key in keys { XCTAssertEqual(state.output(for: key), key) }
    }

    func testEveryPageContainsUniqueCompleteKeysAndCommonPunctuation() {
        for page in KeyboardTypingLayout.allCases {
            var state = KeyboardTypingState()
            state.selectLayout(page)
            let keys = page.rows.flatMap { $0 }
            XCTAssertEqual(page.rows.count, 3)
            XCTAssertEqual(keys.count, Set(keys).count)
            for key in keys {
                XCTAssertEqual(key.count, 1)
                XCTAssertEqual(state.output(for: key), key)
            }
        }
        XCTAssertEqual(KeyboardTypingLayout.numbers.rows[0].joined(), "1234567890")
        for page in [KeyboardTypingLayout.numbers, .symbols] {
            XCTAssertEqual(page.rows[2], [".", ",", "?", "!", "'"])
        }
        XCTAssertTrue(KeyboardTypingLayout.symbols.rows.flatMap { $0 }.contains("\\"))
        XCTAssertTrue(KeyboardTypingLayout.numbers.rows.flatMap { $0 }.contains("\""))
    }

    func testOneShotShiftIsConsumedOnlyBySuccessfulLetterInsertion() {
        var state = KeyboardTypingState()
        state.pressShift(at: 10)
        XCTAssertEqual(state.output(for: "q"), "Q")
        XCTAssertEqual(state.output(for: "q"), "Q", "Rendering/output lookup must not consume Shift")
        state.didInsertKey("not a key")
        XCTAssertEqual(state.shift, .uppercase)
        state.didInsertKey("q")
        XCTAssertEqual(state.shift, .lowercase)
        XCTAssertEqual(state.output(for: "w"), "w")
    }

    func testAllShiftedLetterOutputsPreserveTheOriginalASCIIKey() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        for key in KeyboardTypingLayout.letters.rows.flatMap({ $0 }) {
            XCTAssertEqual(state.output(for: key), key.uppercased())
            XCTAssertEqual(state.label(for: key), key.uppercased())
        }
    }

    func testDoubleTapLocksAndSingleTapUnlocksCaps() {
        var state = KeyboardTypingState()
        state.pressShift(at: 10)
        state.pressShift(at: 10.2)
        XCTAssertEqual(state.shift, .capsLock)
        state.didInsertKey("a")
        state.didInsertKey("b")
        XCTAssertEqual(state.output(for: "c"), "C")
        state.pressShift(at: 10.3)
        XCTAssertEqual(state.shift, .lowercase)
        XCTAssertEqual(state.output(for: "c"), "c")
    }

    func testSeparateShiftTapsToggleWithoutLocking() {
        var state = KeyboardTypingState()
        state.pressShift(at: 10)
        state.pressShift(at: 11)
        XCTAssertEqual(state.shift, .lowercase)
        state.pressShift(at: 12)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testDoubleTapThresholdIncludesBoundaryButNotLaterTap() {
        var atBoundary = KeyboardTypingState()
        atBoundary.pressShift(at: 0)
        atBoundary.pressShift(at: KeyboardTypingState.capsLockTapInterval)
        XCTAssertEqual(atBoundary.shift, .capsLock)
        var afterBoundary = KeyboardTypingState()
        afterBoundary.pressShift(at: 0)
        afterBoundary.pressShift(at: KeyboardTypingState.capsLockTapInterval.nextUp)
        XCTAssertEqual(afterBoundary.shift, .lowercase)
    }

    func testClockRegressionInvalidValuesAndOverflowCannotLockCaps() {
        for timestamp in [Double.nan, .infinity, -.infinity, -1, 9, .greatestFiniteMagnitude] {
            var state = KeyboardTypingState()
            state.pressShift(at: 10)
            state.pressShift(at: timestamp)
            XCTAssertEqual(state.shift, .lowercase)
        }
        for timestamp in [Double.nan, .infinity, -.infinity, -1] {
            var state = KeyboardTypingState()
            state.pressShift(at: timestamp)
            state.pressShift(at: 10)
            XCTAssertEqual(state.shift, .lowercase)
            XCTAssertEqual(state, state, "Invalid timestamps must not enter stored state")
        }
    }

    func testPageChangesKeepCapsButBreakTheShiftDoubleTapSequence() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        state.selectLayout(.numbers)
        state.didInsertKey("1")
        XCTAssertEqual(state.shift, .uppercase)
        XCTAssertEqual(state.output(for: "1"), "1")
        state.selectLayout(.symbols)
        XCTAssertEqual(state.output(for: "€"), "€")
        state.selectLayout(.letters)
        state.pressShift(at: 1.1)
        XCTAssertEqual(state.shift, .lowercase)
        state.pressShift(at: 1.2)
        XCTAssertEqual(state.shift, .capsLock)
        state.selectLayout(.numbers)
        state.didInsertKey("9")
        state.selectLayout(.letters)
        XCTAssertEqual(state.output(for: "z"), "Z")
    }

    func testShiftOnOtherPagesDoesNotAlterLettersOrRememberTap() {
        var state = KeyboardTypingState()
        for page in [KeyboardTypingLayout.numbers, .symbols] {
            state.selectLayout(page)
            state.pressShift(at: 1)
            XCTAssertEqual(state.shift, .lowercase)
        }
        state.selectLayout(.letters)
        state.pressShift(at: 1.1)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testInvalidOrStalePageKeysCannotBeInserted() {
        var state = KeyboardTypingState()
        for key in ["", "Q", "ab", " ", "\n", "🙂", "a\u{301}", "1", "+"] {
            XCTAssertNil(state.output(for: key))
        }
        state.selectLayout(.numbers)
        XCTAssertNil(state.output(for: "q"))
        XCTAssertNil(state.output(for: "+"))
        state.selectLayout(.symbols)
        XCTAssertNil(state.output(for: "1"))
        XCTAssertNil(state.output(for: "@"))
    }

    func testEditingActionBreaksTapSequenceWithoutConsumingShift() {
        var state = KeyboardTypingState()
        state.pressShift(at: 10)
        state.resetTapSequence()
        state.pressShift(at: 10.1)
        XCTAssertEqual(state.shift, .lowercase)
    }

    func testAutomaticCapitalizationFollowsContextUntilUserOverridesIt() {
        var state = KeyboardTypingState()
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
        state.pressShift(at: 1)
        XCTAssertEqual(state.shift, .lowercase)
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .lowercase, "Repeated host callbacks must not undo an explicit lowercase choice")
        state.didInsertKey("a")
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .lowercase)
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testAutomaticCapitalizationNeverDisablesCapsLockOrChangesOtherPages() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        state.pressShift(at: 1.1)
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .capsLock)
        state.didEditText()
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .capsLock)
        state.pressShift(at: 2)
        state.didEditText()
        state.selectLayout(.numbers)
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .lowercase)
        state.selectLayout(.letters)
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(state.shift, .uppercase)
    }

    func testInvalidInsertionCannotReleaseManualShiftOverride() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        state.didInsertKey("invalid")
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .uppercase)
        state.selectLayout(.numbers)
        state.didInsertKey("1")
        state.selectLayout(.letters)
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .uppercase)
        state.didEditText()
        state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(state.shift, .lowercase)
    }

    func testLiteralWriteOwnCallbacksPreserveCaseEvenWhenHostContextIsNil() {
        for beforeContext in [String?.none, "", "q"] {
            let host = LiteralWriteHost()
            host.state.synchronizeAutomaticCapitalization(true)
            XCTAssertTrue(host.write("q") {
                host.hostCallback(beforeContext: beforeContext, automaticUppercase: false)
                host.hostCallback(beforeContext: nil, automaticUppercase: false)
            })
            XCTAssertEqual(host.inserted, ["q"])
            XCTAssertEqual(host.state.output(for: "q"), "Q")
            host.state.synchronizeAutomaticCapitalization(false)
            XCTAssertEqual(host.state.shift, .uppercase, "Finishing a matching write preserves the case choice")
            host.hostCallback(beforeContext: "q ", automaticUppercase: false)
            XCTAssertEqual(host.state.shift, .lowercase, "The transaction never suppresses later ordinary host edits")
        }
    }

    func testLiteralWriteCapturesNewerShiftAtWriteCommencementRatherThanKeyDown() {
        let host = LiteralWriteHost()
        let keyDownState = host.state
        host.state.pressShift(at: 10)
        XCTAssertNotEqual(host.state, keyDownState)
        XCTAssertTrue(host.write("q") {
            host.hostCallback(beforeContext: nil, automaticUppercase: false)
        })
        XCTAssertEqual(host.state.shift, .uppercase)
        host.state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(host.state.shift, .uppercase)
    }

    func testLiteralWriteDoesNotOverwriteShiftChangedSynchronouslyByTheHost() {
        let host = LiteralWriteHost()
        host.state.synchronizeAutomaticCapitalization(true)
        XCTAssertFalse(host.write("q") {
            host.state.pressShift(at: 2)
            host.hostCallback(beforeContext: nil, automaticUppercase: false)
        })
        XCTAssertEqual(host.inserted, ["q"], "The already accepted host write is never retried or undone")
        XCTAssertEqual(host.state.shift, .lowercase)
        host.state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(host.state.shift, .uppercase, "A superseded write cannot install a manual case hint")
    }

    func testLiteralWriteCannotMarkAReplacementDocumentModeOrResizeInteraction() {
        let replacements: [(LiteralWriteHost) -> Void] = [
            { $0.documentIdentifier = UUID() },
            { $0.modeIdentifier = UUID() },
            { $0.interactionIdentifier = UUID() }
        ]
        for replace in replacements {
            let host = LiteralWriteHost()
            host.state.synchronizeAutomaticCapitalization(true)
            XCTAssertFalse(host.write("q") {
                replace(host)
                host.hostCallback(beforeContext: nil, automaticUppercase: false)
            })
            XCTAssertEqual(host.inserted, ["q"])
            XCTAssertEqual(host.state.shift, .lowercase)
            host.state.synchronizeAutomaticCapitalization(true)
            XCTAssertEqual(host.state.shift, .uppercase, "The old write cannot lock case in its replacement scope")
        }
    }

    func testLiteralWriteScopeChangesAreTerminalEvenIfTheOriginalScopeReturns() throws {
        let original = LiteralWriteHost().scope
        var alteredState = original.typingState
        alteredState.didInsertLiteralGesture()
        XCTAssertEqual(alteredState.shift, original.typingState.shift)
        let changedScopes: [KeyboardLiteralWriteScope?] = [
            nil,
            KeyboardLiteralWriteScope(typingState: alteredState,
                documentIdentifier: original.documentIdentifier,
                modeIdentifier: original.modeIdentifier, interactionIdentifier: original.interactionIdentifier),
            KeyboardLiteralWriteScope(typingState: original.typingState,
                documentIdentifier: UUID(), modeIdentifier: original.modeIdentifier,
                interactionIdentifier: original.interactionIdentifier),
            KeyboardLiteralWriteScope(typingState: original.typingState,
                documentIdentifier: original.documentIdentifier, modeIdentifier: UUID(),
                interactionIdentifier: original.interactionIdentifier),
            KeyboardLiteralWriteScope(typingState: original.typingState,
                documentIdentifier: original.documentIdentifier, modeIdentifier: original.modeIdentifier,
                interactionIdentifier: UUID())
        ]
        for changed in changedScopes {
            var transaction = KeyboardLiteralWriteTransaction()
            let token = try XCTUnwrap(transaction.begin(scope: original))
            XCTAssertFalse(transaction.matches(scope: changed))
            XCTAssertFalse(transaction.matches(scope: original))
            XCTAssertFalse(transaction.finish(token: token, accepted: true, scope: original))
        }
    }

    func testLiteralWriteFinishRejectsUnobservedScopeChangesAndFailure() throws {
        let original = LiteralWriteHost().scope
        var different = original.typingState
        different.selectLayout(.symbols)
        let changed = KeyboardLiteralWriteScope(typingState: different,
            documentIdentifier: original.documentIdentifier, modeIdentifier: original.modeIdentifier,
            interactionIdentifier: original.interactionIdentifier)
        for scope in [KeyboardLiteralWriteScope?.none, changed, original] {
            var transaction = KeyboardLiteralWriteTransaction()
            let token = try XCTUnwrap(transaction.begin(scope: original))
            XCTAssertFalse(transaction.finish(token: token, accepted: scope != original, scope: scope))
            XCTAssertFalse(transaction.matches(scope: original))
        }
        let host = LiteralWriteHost()
        host.state.synchronizeAutomaticCapitalization(true)
        XCTAssertFalse(host.write("q", accepted: false) { XCTFail("A rejected write must not call the proxy") })
        XCTAssertTrue(host.inserted.isEmpty)
        host.state.synchronizeAutomaticCapitalization(false)
        XCTAssertEqual(host.state.shift, .lowercase)
        XCTAssertTrue(host.write("q") {})
    }

    func testLiteralWriteRejectsNestedWritesWithoutDisruptingTheOwner() {
        let host = LiteralWriteHost()
        XCTAssertTrue(host.write("q") {
            XCTAssertFalse(host.write("x") { XCTFail("A nested write must not reach the host") })
            host.hostCallback(beforeContext: nil, automaticUppercase: true)
        })
        XCTAssertEqual(host.inserted, ["q"])
        XCTAssertEqual(host.state.shift, .lowercase)
        host.state.synchronizeAutomaticCapitalization(true)
        XCTAssertEqual(host.state.shift, .lowercase)
    }

    func testStaleLiteralWriteCleanupCannotClearAReplacementOwner() throws {
        let scope = LiteralWriteHost().scope
        var transaction = KeyboardLiteralWriteTransaction()
        XCTAssertFalse(transaction.matches(scope: scope))
        transaction.invalidate(token: UUID())
        let oldToken = try XCTUnwrap(transaction.begin(scope: scope))
        XCTAssertFalse(transaction.matches(scope: nil))
        let replacement = try XCTUnwrap(transaction.begin(scope: scope))
        XCTAssertNotEqual(oldToken, replacement)
        XCTAssertFalse(transaction.finish(token: oldToken, accepted: true, scope: scope))
        transaction.invalidate(token: oldToken)
        XCTAssertTrue(transaction.matches(scope: scope))
        XCTAssertTrue(transaction.finish(token: replacement, accepted: true, scope: scope))
        XCTAssertFalse(transaction.finish(token: replacement, accepted: true, scope: scope))
        let cancelled = try XCTUnwrap(transaction.begin(scope: scope))
        transaction.invalidate(token: cancelled)
        XCTAssertFalse(transaction.matches(scope: scope))
        XCTAssertFalse(transaction.finish(token: cancelled, accepted: true, scope: scope))
    }

    func testLiteralWritePreservesCapsAndNonletterPagesWithoutChangingTheirOutputs() {
        let host = LiteralWriteHost()
        host.state.pressShift(at: 1)
        host.state.pressShift(at: 1.1)
        for layout in KeyboardTypingLayout.allCases {
            host.state.selectLayout(layout)
            let before = host.state
            XCTAssertTrue(host.write("👩‍💻") {
                host.hostCallback(beforeContext: nil, automaticUppercase: false)
            })
            XCTAssertEqual(host.state.layout, before.layout)
            XCTAssertEqual(host.state.shift, .capsLock)
        }
        XCTAssertEqual(host.inserted, Array(repeating: "👩‍💻", count: 3))
    }
}

/// Models the two synchronous callbacks around the real policy, including the
/// otherwise destructive nil-context path. No document API or app state is used.
private final class LiteralWriteHost {
    var state = KeyboardTypingState()
    var documentIdentifier = UUID()
    var modeIdentifier = UUID()
    var interactionIdentifier = UUID()
    var inserted: [String] = []
    private var transaction = KeyboardLiteralWriteTransaction()

    var scope: KeyboardLiteralWriteScope {
        KeyboardLiteralWriteScope(typingState: state, documentIdentifier: documentIdentifier,
            modeIdentifier: modeIdentifier, interactionIdentifier: interactionIdentifier)
    }

    func hostCallback(beforeContext: String?, automaticUppercase: Bool) {
        // Matching own callbacks preserve case regardless of context visibility.
        if !transaction.matches(scope: scope), beforeContext == nil { state.didEditText() }
        if !transaction.matches(scope: scope) {
            state.didEditText()
            state.synchronizeAutomaticCapitalization(automaticUppercase)
        }
    }

    func write(_ text: String, accepted: Bool = true, callback: () -> Void) -> Bool {
        guard let token = transaction.begin(scope: scope) else { return false }
        if accepted {
            inserted.append(text)
            callback()
        }
        let preserveCase = transaction.finish(token: token, accepted: accepted, scope: scope)
        if preserveCase { state.didInsertLiteralGesture() }
        return preserveCase
    }
}
