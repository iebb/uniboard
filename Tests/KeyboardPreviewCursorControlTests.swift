#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardPreviewCursorControlTests: XCTestCase {
    /// A UIKit-like host: counts UTF-16 units (or grapheme clusters), exposes
    /// a bounded context and reports changes only when told to.
    @MainActor private final class Host: KeyboardPreviewCursorHost {
        var text: String
        var cursor: Int // UTF-16 offset
        var countsGraphemes = false
        var ignoresMoves = false
        var exposedAfter = Int.max
        var selection = false, secure = false, panel = false
        var document: UUID? = UUID()
        var moves: [Int] = []
        var announcements: [String] = []

        init(_ text: String, cursor: Int) { self.text = text; self.cursor = cursor }

        private var units: [UInt16] { Array(text.utf16) }
        var previewContextBefore: String? { String(decoding: units[..<cursor], as: UTF16.self) }
        var previewContextAfter: String? {
            let after = String(decoding: units[cursor...], as: UTF16.self)
            return String(after.prefix(exposedAfter))
        }
        var previewDocumentIdentifier: UUID? { document }
        var previewHasSelection: Bool { selection }
        var previewIsSecure: Bool { secure }
        var previewPanelOpen: Bool { panel }

        func previewAdjust(by offset: Int) {
            moves.append(offset)
            guard !ignoresMoves else { return }
            if countsGraphemes {
                let line = KeyboardPreviewCursorLine(before: String(decoding: units[..<cursor], as: UTF16.self),
                                                     after: String(decoding: units[cursor...], as: UTF16.self),
                                                     limit: .max)
                let start = cursor - line.caret
                if let landing = line.boundary(movingGraphemes: offset, from: line.caret) { cursor = start + landing }
            } else {
                cursor = min(max(0, cursor + offset), units.count)
            }
        }

        func previewAnnounce(_ message: String) { announcements.append(message) }
    }

    private var pending: [(TimeInterval, @MainActor () -> Void)] = []

    private func driver(for host: Host) -> KeyboardPreviewCursorDriver {
        let driver = KeyboardPreviewCursorDriver()
        driver.host = host
        driver.now = { 100 }
        driver.schedule = { [unowned self] delay, work in self.pending.append((delay, work)) }
        driver.refresh()
        return driver
    }

    private func runScheduled() {
        let work = pending
        pending = []
        for (_, job) in work { job() }
    }

    func testTapMovesTheHostCursorByTheLogicalDelta() {
        let host = Host("Hello world", cursor: 11)
        let driver = driver(for: host)
        XCTAssertTrue(driver.state.interactive)
        driver.request(5)
        XCTAssertEqual(host.moves, [-6])
        XCTAssertEqual(driver.state.caret, 5, "The preview caret moves at once")
        driver.refresh() // the host's text-change callback
        XCTAssertFalse(driver.session.isMoving)
        XCTAssertEqual(driver.state.line.caret, 5)
        XCTAssertEqual(host.cursor, 5)
    }

    func testOneMoveAtATimeCoalescesToTheLatestTarget() {
        let host = Host("abcdefghij", cursor: 10)
        let driver = driver(for: host)
        driver.request(8)
        driver.request(6)
        driver.request(3)
        XCTAssertEqual(host.moves, [-2], "Only one move is in flight")
        XCTAssertEqual(driver.state.caret, 3)
        driver.refresh()
        XCTAssertEqual(host.moves, [-2, -5], "The next move goes to the latest target from the confirmed context")
        driver.refresh()
        XCTAssertEqual(host.cursor, 3)
        XCTAssertFalse(driver.session.isMoving)
    }

    func testTimeoutConfirmsWhenNoCallbackArrives() {
        let host = Host("abcdef", cursor: 6)
        let driver = driver(for: host)
        driver.request(2)
        runScheduled() // 100 ms pass with no callback
        XCTAssertEqual(host.cursor, 2)
        XCTAssertFalse(driver.session.isMoving)
    }

    func testIgnoredMoveShowsTheRealPosition() {
        let host = Host("abcdef", cursor: 6)
        host.ignoresMoves = true
        let driver = driver(for: host)
        driver.request(2)
        runScheduled()
        XCTAssertFalse(driver.session.isMoving)
        XCTAssertEqual(driver.state.caret, 6, "Never a cursor the app doesn't have")
    }

    func testGraphemeHostIsLearnedFromTheUserMoveAndRemembered() {
        let emoji = "👩\u{200D}💻"
        let host = Host("ab" + emoji + "cd", cursor: ("ab" + emoji + "cd").utf16.count)
        host.countsGraphemes = true
        let driver = driver(for: host)
        driver.request(2) // before the emoji
        for _ in 0..<4 where driver.session.isMoving { driver.refresh() }
        XCTAssertEqual(host.cursor, 2)
        XCTAssertEqual(driver.session.unit, .grapheme)
        XCTAssertEqual(driver.memory.unit(for: host.document), .grapheme)
    }

    func testSelectionBlocksMovesAndTypingDropsTheMoveInFlight() {
        let host = Host("abcdef", cursor: 6)
        host.selection = true
        let driver = driver(for: host)
        XCTAssertFalse(driver.state.interactive)
        driver.request(1)
        XCTAssertEqual(host.moves, [])
        host.selection = false
        driver.refresh()
        driver.request(1)
        XCTAssertEqual(host.moves, [-5])
        driver.keyboardWillEdit()
        XCTAssertFalse(driver.session.isMoving)
        runScheduled()
        XCTAssertEqual(host.moves, [-5], "Nothing moves after the keyboard typed")
    }

    func testExternalChangesResetThePlacementButOwnMovesDoNot() {
        let host = Host("abcdef", cursor: 6)
        let driver = driver(for: host)
        let start = driver.state.placementGeneration
        driver.request(3)
        driver.refresh()
        XCTAssertEqual(driver.state.placementGeneration, start, "The preview's own move never resets")
        var clock: TimeInterval = 100
        driver.now = { clock }
        clock = 200
        host.cursor = 1 // the user tapped in the app
        driver.refresh()
        XCTAssertEqual(driver.state.placementGeneration, start + 1)
    }

    func testStepsAndLineEdgesAnnounce() {
        let host = Host("abc", cursor: 3)
        let driver = driver(for: host)
        XCTAssertTrue(driver.step(forward: false, announce: true))
        driver.refresh()
        XCTAssertEqual(host.cursor, 2)
        XCTAssertEqual(host.announcements.last, "Cursor after b")
        XCTAssertTrue(driver.lineEdge(.lineStart))
        driver.refresh()
        XCTAssertEqual(host.cursor, 0)
        XCTAssertEqual(host.announcements.last, "Beginning of line")
        XCTAssertFalse(driver.step(forward: false, announce: true), "Nothing before the line start")
    }

    func testControlHitTestsWholeCharactersAndFreezesTheVisibleExcerpt() {
        let control = KeyboardPreviewCursorControl(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let text = "Cafe\u{0301} 👩\u{200D}💻"
        let line = KeyboardPreviewCursorLine(before: text, after: "")
        control.configure(line: line, caret: line.caret, interactive: true, placementGeneration: 1)
        control.layoutIfNeeded()
        for x in stride(from: CGFloat(0), through: 300, by: 3) {
            XCTAssertTrue(line.isBoundary(control.boundary(atTextAreaX: x)), "Never inside a cluster at x \(x)")
        }
        XCTAssertEqual(control.boundary(atTextAreaX: 299), line.length, "Past the end: the visual end")
        let excerpt = control.visibleExcerpt()
        XCTAssertEqual(excerpt.before, text)
        XCTAssertEqual(excerpt.after, "")
        XCTAssertTrue(excerpt.isSingleLine)
    }

    func testInkIsMeasuredPerCharacterInTextAreaCoordinates() {
        let control = KeyboardPreviewCursorControl(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let line = KeyboardPreviewCursorLine(before: "ab \u{0301}c 👩\u{200D}💻", after: "")
        control.configure(line: line, caret: line.caret, interactive: true, placementGeneration: 1)
        control.layoutIfNeeded()
        let ink = control.characterInk()
        XCTAssertEqual(ink.count, line.boundaries.count - 1, "One entry per character")
        let boundaries = line.boundaries
        for (index, extent) in ink.enumerated() {
            let character = String(decoding: Array(line.text.utf16)[boundaries[index]..<boundaries[index + 1]], as: UTF16.self)
            if character == " " {
                XCTAssertNil(extent, "A space draws no ink")
            } else if let extent {
                let start = control.lineX(of: boundaries[index]), end = control.lineX(of: boundaries[index + 1])
                XCTAssertLessThan(extent.lowerBound, max(start, end) + 1, "Ink of \(character) sits at its advance")
                XCTAssertGreaterThan(extent.upperBound, min(start, end) - 1, "Ink of \(character) sits at its advance")
            } else {
                XCTFail("\(character) has no ink")
            }
        }
    }

    private func idle(_ seconds: TimeInterval = 0.7) {
        let done = expectation(description: "idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    func testCaretIsSolidAfterChangesAndBlinksWhenIdle() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let control = KeyboardPreviewCursorControl(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        window.addSubview(control)
        window.isHidden = false
        let line = KeyboardPreviewCursorLine(before: "abc", after: "")
        control.configure(line: line, caret: 3, interactive: true, placementGeneration: 1)
        XCTAssertFalse(control.isCaretBlinking, "Solid right after a change")
        idle()
        XCTAssertTrue(control.isCaretBlinking, "Blinking once idle")
        control.configure(line: line, caret: 2, interactive: true, placementGeneration: 1)
        XCTAssertFalse(control.isCaretBlinking, "A cursor move makes it solid again")
        idle()
        XCTAssertTrue(control.isCaretBlinking)
        control.configure(line: line, caret: 2, interactive: false, placementGeneration: 1)
        idle()
        XCTAssertFalse(control.isCaretBlinking, "Never while the preview isn't interactive")
        control.configure(line: line, caret: 2, interactive: true, placementGeneration: 1)
        idle()
        XCTAssertTrue(control.isCaretBlinking)
        control.isCaretLive = false
        XCTAssertFalse(control.isCaretBlinking, "Stops at once when a panel opens or the keyboard hides")
        idle()
        XCTAssertFalse(control.isCaretBlinking)
        control.isCaretLive = true
        XCTAssertFalse(control.isCaretBlinking, "Solid on return")
        idle()
        XCTAssertTrue(control.isCaretBlinking)
        control.noteCaretActivity()
        XCTAssertFalse(control.isCaretBlinking, "A key press makes it solid")
        control.removeFromSuperview()
        idle()
        XCTAssertFalse(control.isCaretBlinking, "Never while hidden")
    }

    func testCappedSidesKeepTheCaret24PointsInsideTheCap() {
        let control = KeyboardPreviewCursorControl(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let line = KeyboardPreviewCursorLine(before: "The quick brown fox jumps over the lazy dog while the preview keeps scrolling",
                                             after: " past the end of the row")
        control.configure(line: line, caret: line.caret, interactive: true, placementGeneration: 1)
        control.layoutIfNeeded()
        func caretX() -> CGFloat { control.lineX(of: control.caretOffset) - control.horizontalOffset }
        func walk(_ steps: Int, forward: Bool) {
            var caret = control.caretOffset
            for _ in 0..<steps {
                caret = (forward ? line.boundary(after: caret) : line.boundary(before: caret)) ?? caret
                control.configure(line: line, caret: caret, interactive: true, placementGeneration: 1)
                control.layoutIfNeeded()
            }
        }
        // Rev. 4 (checks 3 and 4): 24 pt inside the "…" cap, 42 pt from the edge.
        walk(45, forward: false)
        XCTAssertEqual(caretX(), 42, accuracy: 0.01, "Whole letters fill the 24 pt between the left cap and the caret")
        walk(45, forward: true)
        XCTAssertEqual(caretX(), 300 - 42, accuracy: 0.01, "Text follows: the caret stops 24 pt inside the right cap")
        control.configure(line: line, caret: 0, interactive: true, placementGeneration: 1)
        control.layoutIfNeeded()
        XCTAssertEqual(caretX(), 1, accuracy: 0.01, "No cap at the line's start: the caret reaches x 1")
    }

    func testRightToLeftLineIsRightAligned() {
        let control = KeyboardPreviewCursorControl(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let line = KeyboardPreviewCursorLine(before: "שלום abc", after: "")
        XCTAssertEqual(line.direction, .rightToLeft)
        control.configure(line: line, caret: 0, interactive: true, placementGeneration: 1)
        control.layoutIfNeeded()
        XCTAssertLessThan(control.horizontalOffset, 0, "The line sits at the right edge")
        XCTAssertEqual(control.boundary(atTextAreaX: 299), 0, "The logical start is on the right")
        XCTAssertEqual(control.boundary(atTextAreaX: 2), line.length, "Past the visual end: the end of the line")
    }
}
#endif
