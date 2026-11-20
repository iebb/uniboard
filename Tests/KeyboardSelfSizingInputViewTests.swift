#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardSelfSizingInputViewTests: XCTestCase {
    private final class InputProbe: KeyboardSelfSizingInputView {
        var invalidations = 0
        override func invalidateIntrinsicContentSize() {
            invalidations += 1
            super.invalidateIntrinsicContentSize()
        }
    }
    private final class ParentProbe: UIView {
        var layoutRequests = 0
        override func setNeedsLayout() { layoutRequests += 1; super.setNeedsLayout() }
    }
    private func makeView() -> InputProbe {
        let view = InputProbe(frame: CGRect(x: 0, y: 0, width: 390, height: 300), inputViewStyle: .keyboard)
        _ = view.requestHeight(220)
        return view
    }

    func testStockGapsRouteToOriginalNativeControlsWithVisibleAccessibilityFrames() throws {
        let root = KeyboardSelfSizingInputView(frame: CGRect(x: 0, y: 0, width: 440, height: 272), inputViewStyle: .keyboard)
        let container = UIView(frame: root.bounds)
        root.addSubview(container)
        let q = KeyboardVariantButton(), w = KeyboardVariantButton(), a = KeyboardVariantButton()
        for (key, id, frame) in [(q, "q", CGRect(x: 8, y: 52, width: 35.2, height: 45)),
                                 (w, "w", CGRect(x: 51.2, y: 52, width: 35.2, height: 45)),
                                 (a, "a", CGRect(x: 29.6, y: 108, width: 35.2, height: 45))] {
            key.accessibilityIdentifier = "keyboard.typing.key.\(id)"
            key.frame = frame
            container.addSubview(key)
        }
        root.routesStockKeyGaps = true
        XCTAssertTrue(root.hitTest(CGPoint(x: 47.2, y: 74), with: nil) === w)
        XCTAssertTrue(root.hitTest(CGPoint(x: 4, y: 130), with: nil) === a)
        XCTAssertTrue(a.point(inside: CGPoint(x: -25.6, y: 22), with: nil))
        XCTAssertEqual(a.bounds, CGRect(x: 0, y: 0, width: 35.2, height: 45))
        let visible = a.convert(a.bounds, to: root)
        XCTAssertEqual(visible.minX, 29.6, accuracy: 0.00001)
        XCTAssertEqual(visible.minY, 108, accuracy: 0.00001)
        XCTAssertEqual(visible.width, 35.2, accuracy: 0.00001)
        XCTAssertEqual(visible.height, 45, accuracy: 0.00001)
        root.routesStockKeyGaps = false
        XCTAssertFalse(a.point(inside: CGPoint(x: -25.6, y: 22), with: nil))
        XCTAssertFalse(root.hitTest(CGPoint(x: 47.2, y: 74), with: nil) === w)
    }

    func testExpandedNativeFramesKeepVisibleAccessibilityAndNearestKeyGeometry() throws {
        let root = KeyboardSelfSizingInputView(frame: CGRect(x: 0, y: 0, width: 440, height: 272), inputViewStyle: .keyboard)
        let q = KeyboardVariantButton(), w = KeyboardVariantButton()
        q.accessibilityIdentifier = "keyboard.typing.key.q"
        w.accessibilityIdentifier = "keyboard.typing.key.w"
        q.frame = CGRect(x: 0, y: 46.5, width: 47.2, height: 56)
        q.keyboardVisualInsets = UIEdgeInsets(top: 5.5, left: 8, bottom: 5.5, right: 4)
        w.frame = CGRect(x: 47.2, y: 46.5, width: 43.2, height: 56)
        w.keyboardVisualInsets = UIEdgeInsets(top: 5.5, left: 4, bottom: 5.5, right: 4)
        root.addSubview(q); root.addSubview(w)
        root.routesStockKeyGaps = true
        root.layoutIfNeeded()
        XCTAssertEqual(q.keyboardVisibleBounds, CGRect(x: 8, y: 5.5, width: 35.2, height: 45))
        XCTAssertTrue(root.hitTest(CGPoint(x: 47.2, y: 74), with: nil) === w)
        XCTAssertTrue(root.hitTest(CGPoint(x: 4, y: 74), with: nil) === q)
        // VoiceOver reads a plain subview the size of the visible key, whose
        // outline iOS computes itself; the expanded control is only its container.
        q.accessibilityLabel = "q"
        XCTAssertFalse(q.isAccessibilityElement)
        let outline = try XCTUnwrap(q.accessibilityElements?.first as? KeyboardKeyAccessibilityOutline)
        XCTAssertEqual(q.accessibilityElements?.count, 1)
        XCTAssertTrue(outline.superview === q)
        XCTAssertEqual(outline.frame, q.keyboardVisibleBounds)
        XCTAssertTrue(outline.isAccessibilityElement)
        XCTAssertFalse(outline.isUserInteractionEnabled)
        XCTAssertEqual(outline.accessibilityIdentifier, "keyboard.typing.key.q")
        XCTAssertEqual(outline.accessibilityLabel, "q")
        XCTAssertEqual(outline.accessibilityTraits, q.accessibilityTraits)
        XCTAssertTrue(root.hitTest(outline.convert(CGPoint(x: outline.bounds.midX, y: outline.bounds.midY), to: root), with: nil) === q)
        // A disabled key hides the outline with the control, as before.
        q.isAccessibilityElement = false
        XCTAssertFalse(outline.isAccessibilityElement)
        q.isAccessibilityElement = true
        // Without expanded frames the control is its own element again.
        w.keyboardVisualInsets = .zero
        w.layoutIfNeeded()
        XCTAssertTrue(w.isAccessibilityElement)
        XCTAssertNil(w.accessibilityElements)
        XCTAssertFalse(w.subviews.contains { $0 is KeyboardKeyAccessibilityOutline })
        q.isHighlighted = true
        XCTAssertEqual(q.pressFeedback.frame, q.keyboardVisibleBounds)
    }

    func testNumberRowOnKeysSpeakThroughOutlinesTheSizeOfTheVisibleKeys() throws {
        // Number row on at 440: 328 tall, digits one 56-point pitch above Q.
        let root = KeyboardSelfSizingInputView(frame: CGRect(x: 0, y: 0, width: 440, height: 328), inputViewStyle: .keyboard)
        let one = KeyboardVariantButton(), q = KeyboardVariantButton(), a = KeyboardVariantButton()
        let inset = UIEdgeInsets(top: 5.5, left: 8, bottom: 5.5, right: 4)
        for (key, id, y) in [(one, "number.1", 46.5), (q, "key.q", 102.5)] {
            key.accessibilityIdentifier = "keyboard.typing.\(id)"
            key.frame = CGRect(x: 0, y: y, width: 47.2, height: 56)
            key.keyboardVisualInsets = inset
            root.addSubview(key)
        }
        a.accessibilityIdentifier = "keyboard.typing.key.a"
        a.frame = CGRect(x: 0, y: 158.5, width: 68.8, height: 56)
        a.keyboardVisualInsets = UIEdgeInsets(top: 5.5, left: 29.6, bottom: 5.5, right: 4)
        root.addSubview(a)
        root.routesStockKeyGaps = true
        root.layoutIfNeeded()
        for key in [one, q, a] {
            let outline = try XCTUnwrap(key.accessibilityElements?.first as? KeyboardKeyAccessibilityOutline)
            XCTAssertFalse(key.isAccessibilityElement)
            let spoken = outline.convert(outline.bounds, to: root), visible = key.convert(key.keyboardVisibleBounds, to: root)
            for (s, v) in [(spoken.minX, visible.minX), (spoken.minY, visible.minY), (spoken.width, visible.width), (spoken.height, visible.height)] {
                XCTAssertEqual(s, v, accuracy: 0.00001)
            }
            XCTAssertEqual(outline.accessibilityIdentifier, key.accessibilityIdentifier)
            // VoiceOver's fallback touch at the outline centre reaches the key.
            XCTAssertTrue(root.hitTest(outline.convert(CGPoint(x: outline.bounds.midX, y: outline.bounds.midY), to: root), with: nil) === key)
        }
        XCTAssertEqual(one.convert(one.keyboardVisibleBounds, to: root), CGRect(x: 8, y: 52, width: 35.2, height: 45))
        XCTAssertEqual(q.convert(q.keyboardVisibleBounds, to: root), CGRect(x: 8, y: 108, width: 35.2, height: 45))
    }

    func testDefaultUsesPublicSelfSizingAndDoesNotClaimAnIntrinsicWidth() {
        let view = InputProbe(frame: CGRect(x: 0, y: 0, width: 390, height: 300), inputViewStyle: .keyboard)
        XCTAssertTrue(view.allowsSelfSizing)
        XCTAssertEqual(view.inputViewStyle, .keyboard)
        XCTAssertEqual(view.requestedHeight, KeyboardLayoutPolicy.defaultHeight)
        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: UIView.noIntrinsicMetric, height: KeyboardLayoutPolicy.defaultHeight))
    }

    func testChangedFractionalHeightInvalidatesSizeAndRequestsParentLayout() {
        let view = makeView(), parent = ParentProbe()
        parent.addSubview(view)
        view.invalidations = 0
        parent.layoutRequests = 0
        XCTAssertTrue(view.requestHeight(312.4))
        XCTAssertEqual(view.requestedHeight, 312.4, accuracy: 0.0001)
        XCTAssertEqual(view.intrinsicContentSize.height, 312.4, accuracy: 0.0001)
        XCTAssertEqual(view.invalidations, 1)
        XCTAssertGreaterThan(parent.layoutRequests, 0)
        // The public request does not manually forge actual frame/bounds.
        XCTAssertEqual(view.bounds.height, 300)
    }

    func testUnchangedOrInvalidHeightCannotInvalidateOrMutateTheRequest() {
        let view = makeView()
        XCTAssertTrue(view.requestHeight(260))
        view.invalidations = 0
        for height: CGFloat in [260, 0, -1, -.leastNonzeroMagnitude, .nan, .infinity, -.infinity] {
            XCTAssertFalse(view.requestHeight(height))
            XCTAssertEqual(view.requestedHeight, 260)
        }
        XCTAssertEqual(view.invalidations, 0)
    }

    func testOneRootConstraintCarriesValidRequestsWithoutDuplicateConstraints() throws {
        let view = makeView()
        let constraint = try XCTUnwrap(view.constraints.first { $0.identifier == "keyboard.requestedHeight" })
        XCTAssertTrue(constraint.isActive)
        XCTAssertTrue(constraint.firstItem as? UIView === view)
        XCTAssertEqual(constraint.firstAttribute, .height)
        XCTAssertNil(constraint.secondItem)
        XCTAssertEqual(constraint.priority.rawValue, 999)
        XCTAssertEqual(constraint.constant, 220)
        for height: CGFloat in [348, 252, 348, 396, 340, 312.4] {
            XCTAssertTrue(view.requestHeight(height))
            XCTAssertEqual(constraint.constant, height)
            XCTAssertEqual(view.constraints.filter { $0.identifier == "keyboard.requestedHeight" }.count, 1)
            XCTAssertTrue(view.constraints.contains { $0 === constraint })
        }
        for height: CGFloat in [312.4, 0, -1, .nan, .infinity, -.infinity] {
            XCTAssertFalse(view.requestHeight(height))
            XCTAssertEqual(constraint.constant, 312.4)
        }
    }

    func testActualAutoLayoutHonorsRequiredHostHeightThenUsesUpdatedRequestWhenReleased() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let view = makeView()
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        let hostHeight = view.heightAnchor.constraint(equalToConstant: 220)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.widthAnchor.constraint(equalToConstant: 390), hostHeight
        ])
        XCTAssertTrue(view.requestHeight(420))
        parent.layoutIfNeeded()
        XCTAssertEqual(view.bounds.height, 220, accuracy: 0.001)
        XCTAssertEqual(view.requestedHeight, 420)
        hostHeight.isActive = false
        parent.setNeedsLayout()
        parent.layoutIfNeeded()
        XCTAssertEqual(view.bounds.height, 420, accuracy: 0.001)
        XCTAssertTrue(view.requestHeight(252))
        parent.layoutIfNeeded()
        XCTAssertEqual(view.bounds.height, 252, accuracy: 0.001)
    }

    func testDefaultAndExplicitLowPriorityFittingReturnTheSameRequestedHeightWithoutMutatingIt() {
        let view = makeView()
        XCTAssertTrue(view.requestHeight(340))
        view.invalidations = 0
        for size in [CGSize.zero, CGSize(width: 390, height: 100), UIView.layoutFittingCompressedSize, UIView.layoutFittingExpandedSize] {
            let automatic = view.systemLayoutSizeFitting(size)
            let explicit = view.systemLayoutSizeFitting(size,
                withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
            XCTAssertEqual(automatic, explicit)
            XCTAssertEqual(automatic.height, 340)
            XCTAssertTrue(automatic.width.isFinite)
            XCTAssertGreaterThanOrEqual(automatic.width, 0)
        }
        XCTAssertEqual(view.invalidations, 0, "Fitting is a pure read and cannot create a layout feedback loop")
        XCTAssertEqual(view.requestedHeight, 340)
    }

    func testRequiredHorizontalWidthIsHonoredInsteadOfUsingStaleBoundsOrScreenWidth() {
        let view = makeView()
        for width: CGFloat in [0, 320, 402, 874] {
            let fitted = view.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            XCTAssertEqual(fitted.width, width, accuracy: 0.001)
            XCTAssertEqual(fitted.height, 220)
        }
    }

    func testRequiredVerticalTargetRemainsARealExternalConstraint() {
        let view = makeView()
        XCTAssertTrue(view.requestHeight(420))
        for height: CGFloat in [0, 220, 600] {
            let fitted = view.systemLayoutSizeFitting(CGSize(width: 390, height: height),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .required)
            XCTAssertEqual(fitted.width, 390, accuracy: 0.001)
            XCTAssertEqual(fitted.height, height, accuracy: 0.001)
            XCTAssertEqual(view.requestedHeight, 420, "A fitting query must not persist the external target")
        }
    }

    func testMountedContentConstraintsDoNotReplaceTheControllerHeightRequest() {
        let view = makeView(), content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        // A descendant can overflow the keyboard's requested height without
        // taking ownership of its root height constraint.
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.heightAnchor.constraint(equalToConstant: 420),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        XCTAssertFalse(view.requestHeight(220), "The initial request is already 220 points")
        let fitted = view.systemLayoutSizeFitting(CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        XCTAssertEqual(fitted.width, 320, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 220)
        XCTAssertEqual(content.constraints.first(where: { $0.firstAttribute == .height })?.constant, 420)
    }

    func testInvalidFittingInputsAndPrioritiesCannotReachTheSolverAsNonfiniteValues() {
        let view = makeView()
        for size in [CGSize(width: CGFloat.nan, height: CGFloat.infinity), CGSize(width: -CGFloat.infinity, height: -CGFloat.nan), CGSize(width: -1, height: -2)] {
            let fitted = view.systemLayoutSizeFitting(size,
                withHorizontalFittingPriority: UILayoutPriority(rawValue: Float.nan),
                verticalFittingPriority: UILayoutPriority(rawValue: Float.infinity))
            XCTAssertTrue(fitted.width.isFinite)
            XCTAssertGreaterThanOrEqual(fitted.width, 0)
            XCTAssertEqual(fitted.height, 220)
        }
    }
    func testMalformedPriorityNormalizesIndependentlyForEachAxisIncludingZero() {
        let view = makeView()
        let target = CGSize(width: 320, height: 220)
        let fallback = view.systemLayoutSizeFitting(target,
            withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
        for raw in [Float.nan, Float.infinity, -Float.infinity, 0, -1, 1001] {
            let malformed = UILayoutPriority(rawValue: raw)
            let horizontal = view.systemLayoutSizeFitting(target,
                withHorizontalFittingPriority: malformed, verticalFittingPriority: .fittingSizeLevel)
            XCTAssertEqual(horizontal, fallback, "A malformed horizontal priority must behave like the documented fitting priority")
            let vertical = view.systemLayoutSizeFitting(target,
                withHorizontalFittingPriority: .required, verticalFittingPriority: malformed)
            XCTAssertEqual(vertical.width, 320, accuracy: 0.001)
            XCTAssertEqual(vertical.height, 220, "A malformed vertical priority must not become a required target")
        }
    }
#if DEBUG
    func testDebugCountersDescribeActualEntryPointsAndCanBeBaselinedWithoutChangingSizing() {
        let view = makeView()
        let before = view.debugSizingSnapshot
        _ = view.systemLayoutSizeFitting(CGSize(width: 320, height: 0))
        let afterDefault = view.debugSizingSnapshot
        XCTAssertEqual(afterDefault["defaultFittingCalls"], (before["defaultFittingCalls"] ?? 0) + 1)
        XCTAssertEqual(afterDefault["priorityFittingCalls"], (before["priorityFittingCalls"] ?? 0) + 1,
            "The default entry forwards to the priority entry; the counters are separate, not two independent system calls")
        _ = view.systemLayoutSizeFitting(CGSize(width: 402, height: 220),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .required)
        let afterPriority = view.debugSizingSnapshot
        XCTAssertEqual(afterPriority["defaultFittingCalls"], afterDefault["defaultFittingCalls"])
        XCTAssertEqual(afterPriority["priorityFittingCalls"], (afterDefault["priorityFittingCalls"] ?? 0) + 1)
        XCTAssertEqual(afterPriority["lastReturnedWidth"], 402)
        XCTAssertEqual(afterPriority["lastReturnedHeight"], 220)
        XCTAssertEqual(afterPriority["requestedHeight"], 220)
        XCTAssertEqual(afterPriority["lastVerticalPriority"], 1000)
    }
#endif
}
#endif
