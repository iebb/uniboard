import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardQueryHoldPolicyTests: XCTestCase {
    private typealias Policy = KeyboardQueryHoldPolicy

    func testHoldUsesTheKeyboardThresholdMovementAndOneWording() {
        XCTAssertEqual(Policy.holdThreshold, 0.4)
        XCTAssertEqual(Policy.allowedMovement, 10)
        XCTAssertEqual(Policy.accessibilityActionName, "Type in Text")
        XCTAssertEqual(Policy.typedAnnouncement("t"), "Typed t")
        XCTAssertEqual(Policy.typedAnnouncement("+") { _ in XCTFail("Visible text needs no name"); return nil }, "Typed +")
    }

    func testInvisibleCharactersAreAnnouncedByTheirTitleCasedName() {
        let names = [" ": "SPACE", "\u{200B}": "ZERO WIDTH SPACE", "\u{FEFF}": "ZERO WIDTH NO-BREAK SPACE", "\t": ""]
        let name: (String) -> String? = { names[$0] }
        XCTAssertEqual(Policy.typedAnnouncement(" ", name: name), "Typed Space")
        XCTAssertEqual(Policy.typedAnnouncement("\u{200B}", name: name), "Typed Zero Width Space")
        XCTAssertEqual(Policy.typedAnnouncement("\u{FEFF}", name: name), "Typed Zero Width No-break Space")
        XCTAssertEqual(Policy.typedAnnouncement("\t", name: name), "Typed U+0009", "An empty name falls back to the code point")
        XCTAssertEqual(Policy.typedAnnouncement("\u{2028}"), "Typed U+2028")
        XCTAssertEqual(Policy.typedAnnouncement("\u{00A0}\u{200D}"), "Typed U+00A0 U+200D")
        for visible in ["a", "1", "-", "\u{00E9}", "a\u{200B}"] { XCTAssertFalse(Policy.isInvisible(visible), visible) }
        XCTAssertFalse(Policy.isInvisible(""))
        XCTAssertTrue(Policy.isInvisible("\u{0000}"))
    }

    func testEveryQueryCharacterKeyTypesItsOwnLiteralTitle() {
        XCTAssertEqual(Policy.rows.map { $0.joined() }, ["1234567890", "qwertyuiop", "asdfghjkl", "+zxcvbnm-"])
        XCTAssertEqual(Policy.rows[3], KeyboardQueryPolicy.bottomRow)
        for key in Policy.rows.joined() {
            XCTAssertEqual(Policy.hostText(forKey: key), key, "Query keys have no Shift: they type what they show")
        }
        XCTAssertNil(Policy.hostText(forKey: "T"), "Query keys never show capitals")
        for function in ["delete", " ", "space", "return", "shift", "U", "globe", "123", "#+=", "", "ab", ":"] {
            XCTAssertNil(Policy.hostText(forKey: function), function)
        }
    }

    func testTapEditsTheQueryAndNeverTypesIntoTheHost() throws {
        var press = try XCTUnwrap(Policy.Press(key: "c"))
        XCTAssertEqual(press.phase, .pressing)
        XCTAssertEqual(press.hostText, "c")
        press.moved(distance: 3)
        XCTAssertEqual(press.released(inside: true), .editQuery)
        XCTAssertEqual(press.phase, .finished)
        XCTAssertEqual(press.thresholdReached(), .none, "A late timer after release does nothing")
        var outside = try XCTUnwrap(Policy.Press(key: "c"))
        XCTAssertEqual(outside.released(inside: false), .none)
    }

    func testHoldTypesOnceAndReleaseAddsNothing() throws {
        var press = try XCTUnwrap(Policy.Press(key: "t"))
        press.moved(distance: Policy.allowedMovement)
        XCTAssertEqual(press.thresholdReached(), .insertIntoHost("t"))
        XCTAssertEqual(press.phase, .held)
        XCTAssertEqual(press.thresholdReached(), .none, "No auto-repeat")
        press.moved(distance: 80)
        XCTAssertEqual(press.phase, .held, "Moving after the insert does not undo it")
        XCTAssertEqual(press.released(inside: true), .none, "No query character on release")
    }

    func testMovingBeyondTheAllowanceKeepsAnOrdinaryTap() throws {
        for distance: CGFloat in [10.5, .infinity, .nan] {
            var press = try XCTUnwrap(Policy.Press(key: "1"))
            press.moved(distance: distance)
            XCTAssertEqual(press.phase, .tapOnly)
            XCTAssertEqual(press.thresholdReached(), .none)
            press.moved(distance: 0)
            XCTAssertEqual(press.phase, .tapOnly, "Moving back does not restore the hold")
            XCTAssertEqual(press.released(inside: true), .editQuery)
        }
    }

    func testCancellationEndsThePress() throws {
        var press = try XCTUnwrap(Policy.Press(key: "-"))
        press.cancelled()
        XCTAssertEqual(press.thresholdReached(), .none)
        XCTAssertEqual(press.released(inside: true), .none)
        XCTAssertNil(Policy.Press(key: "delete"))
    }
}

#if canImport(UIKit) && !canImport(UniboardCore)
import UIKit

@MainActor
final class KeyboardQueryHoldButtonTests: XCTestCase {
    @MainActor private final class Harness {
        var queryTaps = 0
        var hostInserts = 0
        var accepts = true
        var announcements: [String] = []
        var fire: (() -> Void)?
        var scheduled: [TimeInterval] = []
        lazy var button: KeyboardQueryHoldButton = {
            let button = KeyboardQueryHoldButton { interval, action in
                self.scheduled.append(interval)
                self.fire = action
                return Timer(timeInterval: interval, repeats: false) { _ in }
            }
            button.configure(contextIdentifier: UUID()) { { self.queryTaps += 1; return true } }
            button.configureHold(key: "t") { { self.hostInserts += 1; return self.accepts } }
            button.announce = { self.announcements.append($0) }
            return button
        }()
    }

    func testTapEditsQueryOnly() {
        let harness = Harness()
        harness.button.sendActions(for: .touchDown)
        XCTAssertEqual(harness.scheduled, [0.4])
        harness.button.sendActions(for: .touchUpInside)
        XCTAssertEqual(harness.queryTaps, 1)
        harness.fire?()
        XCTAssertEqual(harness.hostInserts, 0, "A stale timer after release never types")
    }

    func testHoldTypesOnceShowsAccentAndReleaseAddsNothing() {
        let harness = Harness()
        let button = harness.button
        button.sendActions(for: .touchDown)
        XCTAssertTrue(button.pressFeedback.isPressed)
        XCTAssertFalse(button.pressFeedback.isHeld)
        harness.fire?()
        XCTAssertEqual(harness.hostInserts, 1)
        XCTAssertTrue(button.isHolding)
        XCTAssertTrue(button.pressFeedback.isHeld, "The accent overlay replaces the grey press")
        XCTAssertEqual(harness.announcements, ["Typed t"])
        harness.fire?()
        XCTAssertEqual(harness.hostInserts, 1, "No auto-repeat")
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(harness.queryTaps, 0, "No query character on release")
        XCTAssertFalse(button.pressFeedback.isPressed)
        XCTAssertFalse(button.pressFeedback.isHeld)
        XCTAssertFalse(button.isHolding)
    }

    func testRejectedHostInsertNeitherHighlightsNorEditsTheQuery() {
        let harness = Harness()
        harness.accepts = false
        harness.button.sendActions(for: .touchDown)
        harness.fire?()
        XCTAssertEqual(harness.hostInserts, 1)
        XCTAssertFalse(harness.button.pressFeedback.isHeld)
        XCTAssertTrue(harness.announcements.isEmpty)
        harness.button.sendActions(for: .touchUpInside)
        XCTAssertEqual(harness.queryTaps, 0)
    }

    func testMovementBeyondTenPointsKeepsTheTap() {
        let harness = Harness()
        harness.button.sendActions(for: .touchDown)
        harness.button.pressMoved(distance: 6)
        harness.button.pressMoved(distance: 11)
        harness.fire?()
        XCTAssertEqual(harness.hostInserts, 0)
        harness.button.sendActions(for: .touchUpInside)
        XCTAssertEqual(harness.queryTaps, 1)
    }

    func testCancelStopsTheHold() {
        let harness = Harness()
        harness.button.sendActions(for: .touchDown)
        harness.button.sendActions(for: .touchCancel)
        harness.fire?()
        XCTAssertEqual(harness.hostInserts + harness.queryTaps, 0)
    }

    func testVoiceOverCustomActionTypesInText() throws {
        let harness = Harness()
        let actions = try XCTUnwrap(harness.button.accessibilityCustomActions)
        XCTAssertEqual(actions.map(\.name), ["Type in Text"])
        XCTAssertTrue(harness.button.accessibilityTypeInText())
        XCTAssertEqual(harness.hostInserts, 1)
        XCTAssertEqual(harness.queryTaps, 0)
        XCTAssertEqual(harness.announcements, ["Typed t"])
        XCTAssertTrue(harness.button.accessibilityActivate(), "Activation still taps the query")
        XCTAssertEqual(harness.queryTaps, 1)
        XCTAssertEqual(harness.hostInserts, 1)
        harness.button.configureHold(key: "delete") { { true } }
        XCTAssertNil(harness.button.accessibilityCustomActions)
        XCTAssertFalse(harness.button.accessibilityTypeInText())
    }
}
#endif
