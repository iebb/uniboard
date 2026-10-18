#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardQueryControlTests: XCTestCase {
    @MainActor private final class Route {
        let context = KeyboardInputActionContext(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        var moves: [Int] = []
        var activations = 0
        var onActivate: (() -> Void)?
        func action() -> KeyboardQueryActionSession {
            KeyboardQueryActionSession(context: context, currentContext: { self.context }, activate: {
                self.activations += 1
                self.onActivate?()
                return self.context.modeIdentifier
            }, moveCaret: { self.moves.append($0) })
        }
    }
    private func configure(_ control: KeyboardQueryControl, route: Route, query: String = "arrow cat", caret: Int = 6,
                           enabled: Bool, editing: Bool = false) {
        control.configure(query: query, caretUTF16Offset: caret, isEditing: editing, isEmojiScope: false,
            contextIdentifier: route.context.modeIdentifier, enabled: enabled, actionFactory: route.action)
    }
    private func assertVisibility(_ control: KeyboardQueryControl, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(control.isEnabled, enabled, file: file, line: line)
        XCTAssertEqual(control.isUserInteractionEnabled, enabled, file: file, line: line)
        XCTAssertEqual(control.isAccessibilityElement, enabled, file: file, line: line)
        XCTAssertEqual(control.accessibilityElementsHidden, !enabled, file: file, line: line)
        XCTAssertEqual(control.isHidden, !enabled, file: file, line: line)
        let recognizers = control.gestureRecognizers ?? []
        XCTAssertEqual(recognizers.count, 2, file: file, line: line)
        XCTAssertTrue(recognizers.allSatisfy { $0.isEnabled == enabled }, file: file, line: line)
    }

    func testUnconfiguredAndHiddenControlCannotExposeOrActivateSearch() {
        let control = KeyboardQueryControl(), route = Route()
        XCTAssertFalse(control.isAccessibilityElement)
        XCTAssertTrue(control.accessibilityElementsHidden)
        XCTAssertTrue(control.isHidden)
        configure(control, route: route, enabled: false)
        assertVisibility(control, enabled: false)
        XCTAssertFalse(control.accessibilityActivate())
        control.accessibilityIncrement()
        control.accessibilityDecrement()
        XCTAssertEqual(route.activations, 0)
        XCTAssertTrue(route.moves.isEmpty)
        XCTAssertFalse(control.canBecomeFirstResponder)
    }

    func testHiddenThenShownRetainsExactQueryAndMiddleCaretWithoutFirstResponder() {
        let control = KeyboardQueryControl(), route = Route()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.addSubview(control)
        control.frame = CGRect(x: 0, y: 300, width: 220, height: 36)
        configure(control, route: route, enabled: true, editing: true)
        control.layoutIfNeeded()
        assertVisibility(control, enabled: true)
        configure(control, route: route, enabled: false)
        assertVisibility(control, enabled: false)
        XCTAssertEqual(control.accessibilityValue, "arrow cat")
        XCTAssertFalse(control.accessibilityActivate())
        configure(control, route: route, enabled: true, editing: true)
        control.layoutIfNeeded()
        assertVisibility(control, enabled: true)
        XCTAssertEqual(control.accessibilityValue, "arrow cat")
        control.accessibilityIncrement()
        XCTAssertEqual(route.moves, [7], "The caret must continue after its saved middle position, not jump to the end")
        XCTAssertEqual(route.activations, 1)
        XCTAssertFalse(control.isFirstResponder)
    }

    func testRepeatedHiddenConfigurationDoesNotReactivateRecognizerAndFreshShowWorks() {
        let control = KeyboardQueryControl(), route = Route()
        for _ in 0..<3 {
            configure(control, route: route, enabled: false)
            assertVisibility(control, enabled: false)
        }
        configure(control, route: route, enabled: true)
        assertVisibility(control, enabled: true)
        XCTAssertTrue(control.accessibilityActivate())
        configure(control, route: route, enabled: false)
        assertVisibility(control, enabled: false)
        XCTAssertFalse(control.accessibilityActivate())
        XCTAssertEqual(route.activations, 1)
    }

    func testComposedUnicodeCaretAndLongQuerySurviveAHiddenCycleExactly() {
        let control = KeyboardQueryControl(), route = Route()
        let prefix = "e\u{301}🙂\u{200D}↔\u{FE0F}"
        let query = prefix + String(repeating: "x", count: 70)
        let caret = "e\u{301}".utf16.count
        configure(control, route: route, query: query, caret: caret, enabled: true)
        configure(control, route: route, query: query, caret: caret, enabled: false)
        configure(control, route: route, query: query, caret: caret, enabled: true)
        XCTAssertEqual((control.accessibilityValue ?? "").utf16.map { $0 }, query.utf16.map { $0 })
        control.accessibilityIncrement()
        XCTAssertEqual(route.moves, [prefix.utf16.count], "Cursor motion remains at whole-grapheme boundaries after showing the toolbar")
    }

    func testFactoryCannotActivateAnObsoleteQueryAfterHideAndReshow() {
        let control = KeyboardQueryControl(), oldRoute = Route(), newRoute = Route()
        control.configure(query: "arrow cat", caretUTF16Offset: 6, isEditing: true, isEmojiScope: false,
            contextIdentifier: oldRoute.context.modeIdentifier, enabled: true) { [weak control] in
                guard let control else { return nil }
                self.configure(control, route: newRoute, enabled: false)
                self.configure(control, route: newRoute, enabled: true, editing: true)
                return oldRoute.action()
            }
        XCTAssertFalse(control.accessibilityActivate())
        XCTAssertEqual(oldRoute.activations, 0)
        XCTAssertTrue(oldRoute.moves.isEmpty)
        XCTAssertEqual(newRoute.activations, 0)
        control.accessibilityIncrement()
        XCTAssertEqual(newRoute.activations, 1)
        XCTAssertEqual(newRoute.moves, [7])
        assertVisibility(control, enabled: true)
    }

    func testActivationCannotMoveTheOldCaretAfterHideAndReshow() {
        let control = KeyboardQueryControl(), oldRoute = Route(), newRoute = Route()
        oldRoute.onActivate = { [weak control] in
            guard let control else { return }
            self.configure(control, route: newRoute, enabled: false)
            self.configure(control, route: newRoute, caret: 2, enabled: true, editing: true)
        }
        configure(control, route: oldRoute, enabled: true, editing: true)
        control.accessibilityIncrement()
        XCTAssertEqual(oldRoute.activations, 1)
        XCTAssertTrue(oldRoute.moves.isEmpty)
        XCTAssertEqual(newRoute.activations, 0)
        control.accessibilityIncrement()
        XCTAssertEqual(newRoute.activations, 1)
        XCTAssertEqual(newRoute.moves, [3], "An obsolete accessibility callback must not overwrite the newly configured caret")
        assertVisibility(control, enabled: true)
    }
}
#endif
