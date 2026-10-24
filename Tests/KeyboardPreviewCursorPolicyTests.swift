import CoreGraphics
import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// A host text field for the session tests: it moves its cursor the way a
/// UIKit field (UTF-16 units) or WebKit (whole characters) does and exposes
/// a bounded context, like `textDocumentProxy`.
private struct FakeHost {
    var units: [UInt16]
    var caret: Int
    let unit: KeyboardPreviewCursorUnit
    var window = 96
    /// Distorts each offset before the host applies it.
    var distort: (Int) -> Int = { $0 }

    init(_ text: String, caret: Int? = nil, unit: KeyboardPreviewCursorUnit) {
        units = Array(text.utf16)
        self.caret = caret ?? units.count
        self.unit = unit
    }

    private static func decode(_ units: ArraySlice<UInt16>) -> String { String(decoding: units, as: UTF16.self) }

    var line: KeyboardPreviewCursorLine {
        let before = Self.decode(units[..<caret]), after = Self.decode(units[caret...])
        return KeyboardPreviewCursorLine(before: String(before.suffix(window)), after: String(after.prefix(window)))
    }

    mutating func adjust(_ requested: Int) {
        let offset = distort(requested)
        switch unit {
        case .utf16:
            if (0...units.count).contains(caret + offset) { caret += offset }
        case .grapheme:
            let boundaries = KeyboardPreviewCursorLine.graphemeBoundaries(in: Self.decode(units[...]))
            let index = boundaries.firstIndex(of: caret)!
            if boundaries.indices.contains(index + offset) { caret = boundaries[index + offset] }
        }
    }
}

final class KeyboardPreviewCursorPolicyTests: XCTestCase {
    private typealias Line = KeyboardPreviewCursorLine
    private typealias Move = KeyboardPreviewCursorMove
    private typealias Outcome = KeyboardPreviewCursorOutcome
    private typealias Session = KeyboardPreviewCursorSession
    private typealias Policy = KeyboardPreviewCursorPolicy

    private let acute = "e\u{301}"
    private let coder = "👩\u{200D}💻"

    private func line(_ text: String, at caret: Int) -> Line {
        let units = Array(text.utf16)
        return Line(before: String(decoding: units[..<caret], as: UTF16.self),
                    after: String(decoding: units[caret...], as: UTF16.self))
    }

    /// Runs one user request against `host` until it settles; returns the
    /// offsets sent and how it settled.
    private func run(_ session: inout Session, _ host: inout FakeHost,
                     _ start: (inout Session) -> Session.Step) -> ([Int], Session.Step) {
        let first = start(&session)
        return run(&session, &host, first: first)
    }

    private func run(_ session: inout Session, _ host: inout FakeHost, first: Session.Step) -> ([Int], Session.Step) {
        var sent: [Int] = []
        var step = first
        while case let .send(offset) = step {
            sent.append(offset)
            XCTAssertLessThan(sent.count, 200, "A request always settles")
            host.adjust(offset)
            step = session.confirm(host.line)
        }
        return (sent, step)
    }

    // MARK: The cursor's line

    func testLineIsTheCursorsLineFromTheBoundedContext() {
        let both = Line(before: "one\ntwo ", after: "three\nfour")
        XCTAssertEqual(both.text, "two three")
        XCTAssertEqual(both.caret, 4)
        XCTAssertEqual(both.length, 9)
        XCTAssertFalse(both.isEmpty)
        XCTAssertTrue(both.hiddenBefore && both.hiddenAfter && both.startsLine && both.endsLine)
        XCTAssertEqual(both.direction, .leftToRight)

        let none = Line(before: nil, after: nil)
        XCTAssertEqual(none.text, "")
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.boundaries, [0])
        XCTAssertTrue(none.startsLine && none.endsLine)
        XCTAssertFalse(none.hiddenBefore || none.hiddenAfter)

        let clipped = Line(before: "abcdef", after: "ghijkl", limit: 2)
        XCTAssertEqual(clipped.text, "efgh")
        XCTAssertEqual(clipped.caret, 2)
        XCTAssertTrue(clipped.hiddenBefore && clipped.hiddenAfter, "Context beyond the limit is hidden text")
        XCTAssertFalse(clipped.startsLine || clipped.endsLine)

        let negative = Line(before: "ab", after: "cd", limit: -1)
        XCTAssertEqual(negative.text, "")
        XCTAssertTrue(negative.hiddenBefore && negative.hiddenAfter)
        XCTAssertEqual(Line.contextLimit, 96)
    }

    func testBoundariesAreWholeCharactersInUTF16Units() {
        XCTAssertEqual(Line.graphemeBoundaries(in: acute + coder + "a"), [0, 2, 7, 8])
        let sample = line(acute + "ab", at: 0)
        XCTAssertEqual(sample.boundaries, [0, 2, 3, 4])
        XCTAssertTrue(sample.isBoundary(2))
        XCTAssertFalse(sample.isBoundary(1))
        XCTAssertEqual(sample.nearestBoundary(to: 1), 0, "A tie goes to the earlier boundary")
        XCTAssertEqual(sample.nearestBoundary(to: 5), 4)
        XCTAssertEqual(sample.boundary(after: 0), 2)
        XCTAssertNil(sample.boundary(after: 4))
        XCTAssertEqual(sample.boundary(before: 2), 0)
        XCTAssertNil(sample.boundary(before: 0))
        XCTAssertEqual(sample.graphemeDistance(from: 0, to: 4), 3)
        XCTAssertEqual(sample.graphemeDistance(from: 4, to: 0), -3)
        XCTAssertEqual(sample.graphemeDistance(from: 2, to: 2), 0)
        XCTAssertEqual(sample.boundary(movingGraphemes: 0, from: 2), 2)
        XCTAssertEqual(sample.boundary(movingGraphemes: 2, from: 0), 3)
        XCTAssertNil(sample.boundary(movingGraphemes: 4, from: 0))
        XCTAssertEqual(sample.boundary(movingGraphemes: -1, from: 3), 2)
        XCTAssertEqual(sample.boundary(movingGraphemes: -2, from: 3), 0)
        XCTAssertNil(sample.boundary(movingGraphemes: -3, from: 3))
        XCTAssertEqual(sample.character(endingAt: 2), acute)
        XCTAssertNil(sample.character(endingAt: 0))
        XCTAssertNil(sample.character(endingAt: 1))
    }

    func testBaseDirectionIsTheFirstStrongCharacter() {
        XCTAssertEqual(Line.baseDirection(of: "123 שלום abc"), .rightToLeft)
        XCTAssertEqual(Line.baseDirection(of: "123 abc שלום"), .leftToRight)
        XCTAssertEqual(Line.baseDirection(of: "123 !"), .leftToRight, "No strong character is left to right")
        XCTAssertEqual(Line.baseDirection(of: "\u{200F}abc"), .rightToLeft)
        XCTAssertEqual(Line.baseDirection(of: "\u{200E}שלום"), .leftToRight)
        XCTAssertEqual(Line(before: "שלום", after: " abc").direction, .rightToLeft)
        for scalar: Unicode.Scalar in ["\u{0645}", "\u{FB50}", "\u{FE8D}", "\u{10800}", "\u{1E900}"] {
            XCTAssertEqual(Line.strongDirection(of: scalar), .rightToLeft, "U+\(String(scalar.value, radix: 16))")
        }
        for scalar: Unicode.Scalar in ["a", "\u{01C5}", "\u{02B0}", "中"] {
            XCTAssertEqual(Line.strongDirection(of: scalar), .leftToRight)
        }
        for scalar: Unicode.Scalar in ["1", " ", "\u{301}", "😀"] { XCTAssertNil(Line.strongDirection(of: scalar)) }
    }

    // MARK: Planning a move

    func testMoveLandingsAndTheUnitTheyPredict() {
        let split = Move(offset: 2, utf16Landing: 2, graphemeLanding: 3, target: 2)
        XCTAssertEqual(split.expectedLanding(unit: .utf16), 2)
        XCTAssertEqual(split.expectedLanding(unit: .grapheme), 3)
        XCTAssertNil(split.expectedLanding(unit: nil))
        XCTAssertEqual(Move(offset: 1, utf16Landing: 1, graphemeLanding: 1, target: 1).expectedLanding(unit: nil), 1)
    }

    func testPlannedMovesAreExactWithAKnownUnitAndTellUnitsApartOtherwise() {
        let sample = line(acute + "ab", at: 0)
        XCTAssertNil(Move.planned(in: sample, from: 0, to: 0, unit: nil))
        XCTAssertEqual(Move.planned(in: sample, from: 2, to: 4, unit: nil),
                       Move(offset: 2, utf16Landing: 4, graphemeLanding: 4, target: 4), "Plain text needs no calibration")
        XCTAssertEqual(Move.planned(in: sample, from: 0, to: 2, unit: .utf16),
                       Move(offset: 2, utf16Landing: 2, graphemeLanding: 3, target: 2))
        XCTAssertEqual(Move.planned(in: sample, from: 0, to: 2, unit: .grapheme),
                       Move(offset: 1, utf16Landing: 1, graphemeLanding: 2, target: 2))
        XCTAssertEqual(Move.planned(in: sample, from: 0, to: 2, unit: nil),
                       Move(offset: 2, utf16Landing: 2, graphemeLanding: 3, target: 2),
                       "Unknown: the UTF-16 count lands on whole characters both ways, on different spots")
        XCTAssertEqual(Move.planned(in: sample, from: 4, to: 0, unit: nil),
                       Move(offset: -3, utf16Landing: 1, graphemeLanding: 0, target: 0),
                       "No offset tells them apart: the whole-character count, before one correction")
        let emoji = line(coder + "b", at: 0)
        XCTAssertEqual(Move.planned(in: emoji, from: 0, to: 5, unit: nil),
                       Move(offset: 1, utf16Landing: 1, graphemeLanding: 5, target: 5))
    }

    // MARK: Reading the host's answer

    func testCandidatesMatchTheContextAroundTheNewCursor() {
        let old = Line(before: "", after: "babab")
        XCTAssertEqual(Outcome.candidates(of: Line(before: "b", after: "a"), in: old), [1, 3, 5],
                       "A line cut by the context may continue after its end")
        XCTAssertEqual(Outcome.candidates(of: Line(before: "bab", after: ""), in: old), [5])
        XCTAssertEqual(Outcome.candidates(of: Line(before: "", after: "babab"), in: old), [0])
        XCTAssertEqual(Outcome.candidates(of: Line(before: "x", after: "y"), in: old), [])
        let ended = Line(before: "ab", after: "")
        XCTAssertEqual(Outcome.candidates(of: Line(before: "a", after: "bc"), in: ended), [],
                       "A line that ends can't gain text after the cursor")
        XCTAssertTrue(Outcome.sameUnit(0xFFFD, 0xD83D))
        XCTAssertTrue(Outcome.sameUnit(0xDC69, 0xFFFD))
        XCTAssertFalse(Outcome.sameUnit(0xFFFD, 0x200D), "A replacement character stands only for a surrogate")
        XCTAssertTrue(Outcome.sameUnit(0x61, 0x61))
    }

    func testReadingTellsLandingsIgnoredAndUnconfirmedMoves() {
        let old = Line(before: "", after: "babab")
        let plain = Move(offset: 4, utf16Landing: 4, graphemeLanding: 4, target: 4)
        XCTAssertEqual(Outcome.reading(plain, from: old, to: Line(before: "b", after: "a")), .unconfirmed,
                       "Several spots fit and none is the expected one")
        XCTAssertEqual(Outcome.reading(plain, from: old, to: Line(before: "bab", after: "")), .landed(5, unit: nil))
        XCTAssertEqual(Outcome.reading(plain, from: old, to: old), .ignored)
        XCTAssertEqual(Outcome.reading(plain, from: old, to: Line(before: "baba", after: "b")), .landed(4, unit: nil))

        let text = acute + acute + acute + "\n"
        let accents = line(text, at: 0)
        XCTAssertTrue(accents.endsLine)
        let split = Move(offset: 2, utf16Landing: 2, graphemeLanding: 4, target: 2)
        XCTAssertEqual(Outcome.reading(split, from: accents, to: Line(before: acute, after: acute)), .unconfirmed,
                       "Both ways of counting fit")
        XCTAssertEqual(Outcome.reading(split, from: accents, to: line(text, at: 2)), .landed(2, unit: .utf16))
        XCTAssertEqual(Outcome.reading(split, from: accents, to: line(text, at: 4)), .landed(4, unit: .grapheme))
        let beyond = Move(offset: 9, utf16Landing: nil, graphemeLanding: nil, target: 6)
        XCTAssertEqual(Outcome.reading(beyond, from: accents, to: accents), .ignored)

        let emoji = line(coder + "b", at: 0)
        let inside = Move(offset: 1, utf16Landing: 1, graphemeLanding: 5, target: 5)
        XCTAssertEqual(Outcome.reading(inside, from: emoji, to: line(coder + "b", at: 1)), .landed(1, unit: .utf16),
                       "Stopping inside a cluster proves UTF-16 units")
        let unknown = Move(offset: 1, utf16Landing: 1, graphemeLanding: 1, target: 1)
        XCTAssertEqual(Outcome.reading(unknown, from: emoji, to: line(coder + "b", at: 2)), .landed(2, unit: .utf16),
                       "Any spot inside a cluster proves UTF-16 units")
    }

    // MARK: Sessions against hosts

    func testUTF16HostInsideAnEmojiGetsOneCorrection() {
        var host = FakeHost(coder + "b", caret: 0, unit: .utf16)
        var session = Session(line: host.line)
        let first = session.request(5)
        XCTAssertEqual(first, .send(1))
        XCTAssertEqual(session.displayedCaret, 5, "The preview caret stays on the target")
        XCTAssertEqual(session.target, 5)
        XCTAssertTrue(session.isMoving)
        let (sent, end) = run(&session, &host, first: first)
        XCTAssertEqual(sent, [1, 4])
        XCTAssertEqual(end, .settled(.reached))
        XCTAssertEqual(host.caret, 5)
        XCTAssertEqual(session.unit, .utf16)
        XCTAssertNil(session.target)
        XCTAssertEqual(session.displayedCaret, 5)
        XCTAssertFalse(session.isMoving)
    }

    func testGraphemeHostLearnsItsUnitFromTheFirstMove() {
        var host = FakeHost(coder + "b", caret: 0, unit: .grapheme)
        var session = Session(line: host.line)
        let (sent, end) = run(&session, &host) { $0.request(5) }
        XCTAssertEqual(sent, [1])
        XCTAssertEqual(end, .settled(.reached))
        XCTAssertEqual(session.unit, .grapheme)
        // Now exact: one more whole character.
        XCTAssertEqual(session.request(6), .send(1))
    }

    func testAccentCalibrationCorrectsAGraphemeHostOnce() {
        var host = FakeHost(acute + "ab", caret: 0, unit: .grapheme)
        var session = Session(line: host.line)
        let (sent, end) = run(&session, &host) { $0.request(2) }
        XCTAssertEqual(sent, [2, -1])
        XCTAssertEqual(end, .settled(.reached))
        XCTAssertEqual(host.caret, 2)
        XCTAssertEqual(session.unit, .grapheme)

        var uikit = FakeHost(acute + "ab", caret: 0, unit: .utf16)
        var learning = Session(line: uikit.line)
        let (direct, done) = run(&learning, &uikit) { $0.request(2) }
        XCTAssertEqual(direct, [2])
        XCTAssertEqual(done, .settled(.reached))
        XCTAssertEqual(learning.unit, .utf16)
    }

    func testAMissedCorrectionStopsAndShowsTheRealPosition() {
        var host = FakeHost("abcdefgh", caret: 0, unit: .utf16)
        host.distort = { $0 / 2 == 0 ? $0 : $0 / 2 }
        var session = Session(line: host.line)
        let (sent, end) = run(&session, &host) { $0.request(6) }
        XCTAssertEqual(sent, [6, 3])
        XCTAssertEqual(end, .settled(.unconfirmed))
        XCTAssertEqual(session.displayedCaret, host.caret, "The preview shows where the host really is")
        XCTAssertEqual(host.caret, 4)
    }

    func testIgnoredAndUnplaceableMovesSettle() {
        var host = FakeHost(acute + "ab", caret: 0, unit: .utf16)
        host.distort = { _ in 99 }
        var session = Session(line: host.line)
        XCTAssertEqual(run(&session, &host) { $0.request(2) }.1, .settled(.ignored))
        XCTAssertNil(session.unit, "An ignored move proves nothing")

        var lost = Session(line: Line(before: "", after: "abcdef"))
        XCTAssertEqual(lost.request(6), .send(6))
        XCTAssertEqual(lost.confirm(Line(before: "ab", after: "c")), .settled(.unconfirmed),
                       "The target lies beyond the text now exposed")
        XCTAssertEqual(lost.request(lost.line.caret), .settled(.reached), "Already there: nothing to send")
        XCTAssertEqual(lost.request(1), .send(-1))
        XCTAssertEqual(lost.confirm(Line(before: "zz", after: "zz")), .settled(.unconfirmed))
    }

    func testANewTargetInFlightIsSentAfterConfirmation() {
        var host = FakeHost("abcdefgh", caret: 0, unit: .utf16)
        var session = Session(line: host.line)
        XCTAssertEqual(session.request(2), .send(2))
        XCTAssertEqual(session.request(5), .none, "One move at a time")
        XCTAssertEqual(session.displayedCaret, 5)
        XCTAssertFalse(session.hasChanged(host.line), "The host hasn't answered yet")
        host.adjust(2)
        XCTAssertTrue(session.hasChanged(host.line))
        var refreshed = session
        refreshed.refresh(Line(before: "x", after: "y"))
        XCTAssertEqual(refreshed, session, "A plain read never replaces the line a move started in")
        let next = session.confirm(host.line)
        XCTAssertEqual(next, .send(3))
        let (sent, end) = run(&session, &host, first: next)
        XCTAssertEqual(sent, [3])
        XCTAssertEqual(end, .settled(.reached))
        XCTAssertEqual(host.caret, 5)
        XCTAssertTrue(session.hasChanged(host.line), "Nothing in flight: every read counts")
        XCTAssertEqual(session.confirm(Line(before: "abc", after: "")), .none)
        XCTAssertEqual(session.line, Line(before: "abc", after: ""))
        session.refresh(host.line)
        XCTAssertEqual(session.line, host.line)
        XCTAssertEqual(session.request(0), .send(-5))
        session.cancel(Line(before: "q", after: ""))
        XCTAssertFalse(session.isMoving)
        XCTAssertNil(session.goal)
        XCTAssertEqual(session.displayedCaret, 1)
    }

    func testLineEdgesMoveByTheExposedTextUntilTheEdge() {
        var host = FakeHost("x\nabc", unit: .utf16)
        var session = Session(line: host.line)
        let start = session.requestLineEdge(.lineStart)
        XCTAssertEqual(session.goal, .lineStart)
        XCTAssertEqual(run(&session, &host, first: start).1, .settled(.reached))
        XCTAssertEqual(host.caret, 2, "Never crosses the newline")

        var long = FakeHost(String(repeating: "a", count: 300), caret: 0, unit: .utf16)
        long.window = 20
        var walk = Session(line: long.line)
        let (sent, end) = run(&walk, &long) { $0.requestLineEdge(.lineEnd) }
        XCTAssertEqual(end, .settled(.reached))
        XCTAssertEqual(long.caret, 300)
        XCTAssertEqual(sent, Array(repeating: 20, count: 15))

        var endless = FakeHost(String(repeating: "a", count: 2000), caret: 0, unit: .utf16)
        endless.window = 20
        var bounded = Session(line: endless.line)
        let (chunks, stop) = run(&bounded, &endless) { $0.requestLineEdge(.lineEnd) }
        XCTAssertEqual(stop, .settled(.reached))
        XCTAssertEqual(chunks.count, Session.maximumEdgeChunks + 1)
        XCTAssertEqual(endless.caret, 1300)

        var ignoring = FakeHost("abc", caret: 0, unit: .utf16)
        ignoring.distort = { _ in 99 }
        var gaveUp = Session(line: ignoring.line)
        XCTAssertEqual(run(&gaveUp, &ignoring) { $0.requestLineEdge(.lineEnd) }.1, .settled(.ignored))
        XCTAssertNil(gaveUp.goal, "A failed move ends the walk")
        XCTAssertEqual(Session.confirmationTimeout, 0.1)
        XCTAssertEqual(Session.settleRereadDelay, 0.3)
    }

    // MARK: Fixed rules

    func testTypingProtectionAndInteractivity() {
        XCTAssertFalse(Policy.acceptsTouch(at: 10, lastKeyRelease: nil, keysDown: 1), "A key is held")
        XCTAssertTrue(Policy.acceptsTouch(at: 10, lastKeyRelease: nil, keysDown: 0))
        XCTAssertFalse(Policy.acceptsTouch(at: 10, lastKeyRelease: 9.8, keysDown: 0))
        XCTAssertTrue(Policy.acceptsTouch(at: 10, lastKeyRelease: 9.7, keysDown: 0))
        let text = Line(before: "ab", after: "")
        XCTAssertTrue(Policy.isInteractive(line: text, contextShared: true, hasSelection: false, isSecure: false, panelOpen: false))
        XCTAssertFalse(Policy.isInteractive(line: text, contextShared: false, hasSelection: false, isSecure: false, panelOpen: false))
        XCTAssertFalse(Policy.isInteractive(line: Line(before: "", after: ""), contextShared: true, hasSelection: false,
                                            isSecure: false, panelOpen: false))
        XCTAssertFalse(Policy.isInteractive(line: text, contextShared: true, hasSelection: true, isSecure: false, panelOpen: false))
        XCTAssertFalse(Policy.isInteractive(line: text, contextShared: true, hasSelection: false, isSecure: true, panelOpen: false))
        XCTAssertFalse(Policy.isInteractive(line: text, contextShared: true, hasSelection: false, isSecure: false, panelOpen: true))
        XCTAssertEqual(Policy.keyQuietPeriod, 0.3)
        XCTAssertEqual(Policy.tapSlop, 10)
    }

    func testEdgeSteppingZonesPaceAndDirection() {
        XCTAssertEqual(Policy.stepInterval(afterStepping: 0.5), 0.08)
        XCTAssertEqual(Policy.stepInterval(afterStepping: 1.0), 0.04)
        XCTAssertEqual(Policy.edge(at: 10, width: 200), .left)
        XCTAssertEqual(Policy.edge(at: 190, width: 200), .right)
        XCTAssertNil(Policy.edge(at: 100, width: 200))
        // Rev. 4: on a capped side the zone reaches the margin line, 42 pt.
        XCTAssertNil(Policy.edge(at: 30, width: 200), "Uncapped: 24 pt")
        XCTAssertEqual(Policy.edge(at: 30, width: 200, caps: (true, false)), .left)
        XCTAssertEqual(Policy.edge(at: 41.9, width: 200, caps: (true, true)), .left)
        XCTAssertNil(Policy.edge(at: 42, width: 200, caps: (true, true)))
        XCTAssertNil(Policy.edge(at: 170, width: 200, caps: (true, false)))
        XCTAssertEqual(Policy.edge(at: 170, width: 200, caps: (false, true)), .right)
        XCTAssertNil(Policy.edge(at: 158, width: 200, caps: (true, true)))
        XCTAssertTrue(Policy.stepsForward(toward: .right, in: .leftToRight))
        XCTAssertFalse(Policy.stepsForward(toward: .left, in: .leftToRight))
        XCTAssertFalse(Policy.stepsForward(toward: .right, in: .rightToLeft))
        XCTAssertTrue(Policy.stepsForward(toward: .left, in: .rightToLeft))
        let sample = line(acute + "ab", at: 2)
        XCTAssertEqual(Policy.steppedTarget(in: sample, from: 2, forward: true), 3)
        XCTAssertEqual(Policy.steppedTarget(in: sample, from: 2, forward: false), 0)
        XCTAssertNil(Policy.steppedTarget(in: sample, from: 4, forward: true))
        XCTAssertEqual(Policy.edgeMargin, 24)
        XCTAssertEqual(Policy.ellipsisCapWidth, 18)
        XCTAssertEqual(Policy.cappedMargin, 42, "24 pt inside the 18 pt cap")
    }

    func testHitTestingPicksTheNearestCaret() {
        XCTAssertEqual(Policy.nearestBoundary(to: 10, among: [(0, 0), (1, .nan), (2, 12), (3, 9)]), 3)
        XCTAssertNil(Policy.nearestBoundary(to: 10, among: []))
    }

    func testEllipsisEdgesFollowClippingAndHiddenText() {
        let earlier = Line(before: "x\nab", after: "cd")
        XCTAssertTrue(Policy.ellipsisEdges(offset: 0, lineWidth: 100, width: 200, line: earlier) == (true, false))
        XCTAssertTrue(Policy.ellipsisEdges(offset: 10, lineWidth: 300, width: 200, line: earlier) == (true, true))
        let hebrew = Line(before: "שלום", after: "\nx")
        XCTAssertTrue(Policy.ellipsisEdges(offset: 0, lineWidth: 100, width: 200, line: hebrew) == (true, false),
                      "In a right-to-left line, later text is on the left")
    }

    func testScrollingKeepsTheCaretInsideTheMargins() {
        XCTAssertEqual(Policy.scrollOffset(caretX: 50, previous: 30, lineWidth: 100, width: 200, direction: .leftToRight), 0)
        XCTAssertEqual(Policy.scrollOffset(caretX: 50, previous: 30, lineWidth: 100, width: 200, direction: .rightToLeft), -100)
        XCTAssertEqual(Policy.scrollOffset(caretX: 100, previous: 0, lineWidth: 500, width: 200, direction: .leftToRight), 0)
        func offset(_ caretX: CGFloat, from previous: CGFloat, hidden: (left: Bool, right: Bool) = (false, false)) -> CGFloat {
            Policy.scrollOffset(caretX: caretX, previous: previous, lineWidth: 500, width: 200, direction: .leftToRight,
                                hidden: hidden)
        }
        // Rev. 4: a capped side's limit is 24 pt inside the cap, 42 pt from the edge.
        XCTAssertEqual(offset(190, from: 0), 32, "Text follows: the caret stops at W - 42")
        XCTAssertEqual(offset(300, from: 0), 142)
        XCTAssertEqual(offset(100, from: 80), 58, "Text before: the caret stops at 42")
        // A side that shows the line's end without a cap: the edge itself.
        XCTAssertEqual(offset(10, from: 50), 0, "The line's start comes into view, aligned at x 0")
        XCTAssertEqual(offset(30, from: 0), 0, "Uncapped: nothing slides while the caret is at x 1 or more")
        XCTAssertEqual(offset(0, from: 0), -1, "The caret may reach x 1")
        XCTAssertEqual(offset(30, from: 10, hidden: (true, false)), -1, "Exposed text beyond keeps the cap and the margin")
        XCTAssertEqual(offset(499, from: 0), 300, "The line's end comes into view; the caret at W - 1")
        XCTAssertEqual(offset(480, from: 300), 300, "End already in view: nothing slides")
        XCTAssertEqual(offset(480, from: 290), 300)
        XCTAssertEqual(offset(500, from: 300), 301, "The caret may reach W - 1")
        XCTAssertEqual(offset(480, from: 290, hidden: (false, true)), 301, "Exposed text after keeps the cap")
    }

    func testResetShowsAsMuchTextBeforeTheCursorAsFits() {
        XCTAssertEqual(Policy.resetOffset(caretX: 50, lineWidth: 100, width: 200, direction: .leftToRight, ellipsisWidth: 18), 0)
        XCTAssertEqual(Policy.resetOffset(caretX: 50, lineWidth: 100, width: 200, direction: .rightToLeft, ellipsisWidth: 18), -100)
        XCTAssertEqual(Policy.resetOffset(caretX: 300, lineWidth: 500, width: 200, direction: .leftToRight, ellipsisWidth: 18), 118)
        XCTAssertEqual(Policy.resetOffset(caretX: 500, lineWidth: 500, width: 200, direction: .leftToRight, ellipsisWidth: 18), 300)
        XCTAssertEqual(Policy.resetOffset(caretX: 400, lineWidth: 500, width: 200, direction: .rightToLeft, ellipsisWidth: 18), 300)
    }

    func testAlignmentKeepsSharedTextInPlace() {
        XCTAssertTrue(Policy.alignment(from: "abcdef", to: "cdefg", probeLength: 3)! == (2, 0))
        XCTAssertTrue(Policy.alignment(from: "cdef", to: "abcdef", probeLength: 3)! == (0, 2))
        XCTAssertNil(Policy.alignment(from: "abc", to: "xyz"))
        XCTAssertNil(Policy.alignment(from: "abc", to: ""))
    }

    func testVisibleExcerptHoldsOnlyWholeVisibleCharacters() {
        let sample = Line(before: "ab", after: "cd")
        let characters: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)] = [(0..<1, 0, 10), (1..<2, 10, 20), (2..<3, 20, 30), (3..<4, 30, 40)]
        let clipped = Policy.visibleExcerpt(line: sample, caret: 2, characters: characters, visible: 5...35)
        XCTAssertEqual(clipped.before, "…b")
        XCTAssertEqual(clipped.after, "c…")
        XCTAssertTrue(clipped.beforeTruncated && clipped.afterTruncated)
        let whole = Policy.visibleExcerpt(line: Line(before: "x\nab", after: "cd"), caret: 2, characters: characters,
                                          visible: 0...40)
        XCTAssertEqual(whole.before, "…ab", "Hidden earlier lines are marked too")
        XCTAssertEqual(whole.after, "cd")
        XCTAssertTrue(whole.beforeTruncated)
        XCTAssertFalse(whole.afterTruncated)
    }

    func testDrawnSpanShowsNoSliverBesideACap() {
        let characters: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)] = [(0..<1, 0, 10), (1..<2, 10, 20), (2..<3, 20, 30), (3..<4, 30, 40)]
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...35, caps: (false, false)), 5...35,
                       "No cap: the whole area")
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...35, caps: (true, true)), 10...30,
                       "Cut glyphs beside both caps are hidden")
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...35, caps: (true, false)), 10...35)
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...35, caps: (false, true)), 5...30)
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 12...18, caps: (true, true)), 12...12,
                       "Nothing whole: nothing drawn")
        let zeroWidth: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)] = [(0..<1, 4.8, 4.8)]
        XCTAssertEqual(Policy.drawnSpan(characters: zeroWidth, visible: 5...35, caps: (true, true)), 5...5)
    }

    func testDrawnSpanAlsoHidesInkSpillingFromHiddenGlyphs() {
        // Italic: a hidden glyph's ink leans into the space beside it.
        let characters: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)] = [
            (0..<1, 0, 10), (1..<2, 10, 14), (2..<3, 14, 24), (3..<4, 24, 34), (4..<5, 34, 44)]
        let ink: [ClosedRange<CGFloat>?] = [1...12.5, nil, 15...25.5, 23.5...33, 32.5...46]
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...40, caps: (true, true), ink: ink),
                       13.5...33, "The left spill and the cut glyph's lean are hidden; shown ink stays whole")
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...40, caps: (true, false), ink: ink), 13.5...40)
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...40, caps: (false, true), ink: ink), 5...33)
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...40, caps: (false, false), ink: ink), 5...40)
        // Spill reaching into shown ink: the shown glyph wins.
        let overlapping: [ClosedRange<CGFloat>?] = [1...16, nil, 15...25.5, 23.5...33, 32.5...46]
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...40, caps: (true, false),
                                        ink: overlapping).lowerBound, 15)
        // Shown ink overhanging its advance is kept, up to the cap.
        let leaning: [ClosedRange<CGFloat>?] = [1...8, 9.5...13, 15...25.5, 23.5...33, 32.5...46]
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 5...40, caps: (true, false),
                                        ink: leaning).lowerBound, 9.5, "The spill ends before the shown glyph's lean")
        XCTAssertEqual(Policy.drawnSpan(characters: characters, visible: 12...40, caps: (true, false),
                                        ink: [nil, nil, 13...25, nil, nil]).lowerBound, 13,
                       "Shown ink left of its advance stays visible")
        // Only a blank character whole: spills from both sides are hidden.
        let blank: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)] = [(0..<1, 0, 10), (1..<2, 10, 20), (2..<3, 20, 30)]
        XCTAssertEqual(Policy.drawnSpan(characters: blank, visible: 5...25, caps: (true, true),
                                        ink: [1...12, nil, 18...29]), 13...17)
    }

    func testAnnouncementsAfterAMove() {
        let sample = Line(before: "a b\tc", after: "")
        XCTAssertEqual(Policy.announcement(line: sample, caret: 0), "Beginning of line")
        XCTAssertEqual(Policy.announcement(line: sample, caret: 5), "End of line")
        XCTAssertEqual(Policy.announcement(line: sample, caret: 2), "Cursor after space")
        XCTAssertEqual(Policy.announcement(line: sample, caret: 4), "Cursor after tab")
        XCTAssertEqual(Policy.announcement(line: sample, caret: 1), "Cursor after a")
        XCTAssertEqual(Policy.announcement(line: Line(before: acute + "x", after: ""), caret: 1), "Cursor after ")
        XCTAssertEqual(Policy.accessibilityLabel, "Text preview")
        XCTAssertEqual(Policy.accessibilityHint,
                       "Tap or drag in the text to move the cursor. Swipe up or down to move by one character.")
        XCTAssertEqual(Policy.moveToLineStartName, "Move to beginning of line")
        XCTAssertEqual(Policy.moveToLineEndName, "Move to end of line")
    }

    func testACursorInsideAClusterIsRepairedToTheNearerBoundary() {
        XCTAssertFalse(Policy.isInsideCluster(before: nil, after: "a"))
        XCTAssertFalse(Policy.isInsideCluster(before: "a", after: nil))
        XCTAssertFalse(Policy.isInsideCluster(before: "a", after: "b"))
        XCTAssertTrue(Policy.isInsideCluster(before: "x\u{FFFD}", after: "\u{FFFD}y"))
        XCTAssertTrue(Policy.isInsideCluster(before: "e", after: "\u{301}"))
        XCTAssertNil(Policy.repairOffset(before: "", after: "b"))
        XCTAssertEqual(Policy.repairOffset(before: "x\u{FFFD}", after: "\u{FFFD}y"), -1)
        XCTAssertEqual(Policy.repairOffset(before: "e", after: "\u{301}"), -1, "A tie goes back")
        XCTAssertEqual(Policy.repairOffset(before: "a👩", after: "\u{200D}💻b"), -2)
        XCTAssertEqual(Policy.repairOffset(before: "a👩\u{200D}", after: "💻b"), 2)
    }

    // MARK: Remembering the unit

    func testCaretIsSolidOnActivityAndBlinksWhenIdle() {
        typealias Blink = KeyboardPreviewCaretBlinkPolicy
        func blinks(live: Bool = true, nonBlinking: Bool = false, busy: Bool = false, at now: TimeInterval) -> Bool {
            Blink.blinks(live: live, prefersNonBlinking: nonBlinking, busy: busy, now: now, lastActivity: 10)
        }
        XCTAssertFalse(blinks(at: 10.2), "Solid for 0.5 s after a tap, key, move or app change")
        XCTAssertTrue(blinks(at: 10.5), "Blinking once idle")
        XCTAssertTrue(blinks(at: 10.49), "A timer firing a little early still starts blinking")
        XCTAssertFalse(blinks(busy: true, at: 20), "Solid while a finger is down, dragging or stepping")
        XCTAssertFalse(blinks(live: false, at: 20), "Not while hidden, not interactive or under a panel")
        XCTAssertFalse(blinks(nonBlinking: true, at: 20), "Prefer Non-Blinking Cursor keeps it solid")
        XCTAssertEqual(Blink.delayUntilBlinking(now: 10.2, lastActivity: 10), 0.3, accuracy: 1e-9)
        XCTAssertEqual(Blink.delayUntilBlinking(now: 12, lastActivity: 10), 0)

        // 1.0 s: visible 0.5 s, fade out 0.1 s, hidden 0.3 s, fade in 0.1 s.
        XCTAssertEqual(Blink.period, 1)
        XCTAssertEqual(Blink.opacity(blinkingFor: 0), 1, "Restarts from fully visible")
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.45), 1)
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.55), 0.5, accuracy: 1e-9, "Halfway through the fade out")
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.52), 0.896, accuracy: 1e-3, "Eased, not linear")
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.75), 0, "Hidden")
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.95), 0.5, accuracy: 1e-9, "Halfway through the fade in")
        XCTAssertEqual(Blink.opacity(blinkingFor: 1.3), 1, "The cycle repeats")
        XCTAssertEqual(Blink.opacity(blinkingFor: -1), 1, "Never before it starts")
        // Reduce Motion: the same timing, hard on and off.
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.3, reduceMotion: true), 1)
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.55, reduceMotion: true), 0, "No fade")
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.89, reduceMotion: true), 0)
        XCTAssertEqual(Blink.opacity(blinkingFor: 0.95, reduceMotion: true), 1)
    }

    func testUnitMemoryIsPerDocumentAndBounded() {
        var memory = KeyboardPreviewCursorUnitMemory()
        let first = UUID(), second = UUID()
        XCTAssertNil(memory.unit(for: first))
        XCTAssertNil(memory.unit(for: nil))
        memory.remember(.grapheme, for: nil)
        XCTAssertEqual(memory, KeyboardPreviewCursorUnitMemory(), "No document, nothing remembered")
        memory.remember(.grapheme, for: first)
        memory.remember(.utf16, for: second)
        memory.remember(.utf16, for: first)
        XCTAssertEqual(memory.unit(for: first), .utf16)
        XCTAssertEqual(memory.entries.map(\.key), [second, first])
        var other = KeyboardPreviewCursorUnitMemory()
        other.remember(.utf16, for: second)
        other.remember(.grapheme, for: first)
        XCTAssertNotEqual(memory, other)
        for _ in 0..<KeyboardPreviewCursorUnitMemory.capacity { memory.remember(.grapheme, for: UUID()) }
        XCTAssertEqual(memory.entries.count, KeyboardPreviewCursorUnitMemory.capacity)
        XCTAssertNil(memory.unit(for: first), "The oldest documents are forgotten")
    }
}
