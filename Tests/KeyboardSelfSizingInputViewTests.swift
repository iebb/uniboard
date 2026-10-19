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
