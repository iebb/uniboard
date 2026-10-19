import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardFooterLayoutPolicyTests: XCTestCase {
    func testPadModifierTextUsesBottomCornersWithSafeInsetsAndNeverEscapesShortKeys() {
        let natural = CGRect(x: 20, y: 12, width: 35, height: 16)
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 52)
        XCTAssertEqual(KeyboardKeyContentPosition.center.alignedRect(natural, in: bounds), natural)
        XCTAssertEqual(KeyboardKeyContentPosition.bottomLeft.alignedRect(natural, in: bounds), CGRect(x: 8, y: 30, width: 35, height: 16))
        XCTAssertEqual(KeyboardKeyContentPosition.bottomRight.alignedRect(natural, in: bounds), CGRect(x: 57, y: 30, width: 35, height: 16))
        for width: CGFloat in [1, 10, 20, 44, 120] {
            for height: CGFloat in [1, 5, 36, 52] {
                let frame = CGRect(x: 7, y: 9, width: width, height: height)
                for position in [KeyboardKeyContentPosition.bottomLeft, .bottomRight] {
                    let value = position.alignedRect(natural, in: frame)
                    XCTAssertTrue(frame.contains(value))
                    XCTAssertTrue([value.minX, value.minY, value.width, value.height].allSatisfy(\.isFinite))
                }
            }
        }
        for bad in [CGRect.zero, CGRect(x: CGFloat.infinity, y: 0, width: 44, height: 52), CGRect(x: 0, y: 0, width: CGFloat.nan, height: 52)] {
            XCTAssertEqual(KeyboardKeyContentPosition.bottomRight.alignedRect(natural, in: bad), .zero)
        }
        XCTAssertEqual(KeyboardKeyContentPosition.bottomLeft.alignedRect(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 16), in: bounds), .zero)
    }
    func testWidePadReservesComfortableTrailingKeysAndASmallerSpaceInBothOrientations() throws {
        for width: CGFloat in [650, 752, 818, 980, 1008, 1180, 1350] {
            for globe in [false, true] {
                let plan = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: width, hasGlobe: globe,
                    showsCollapse: true, showsPage: true, isPad: true, showsReturn: false, padTyping: true))
                let count = CGFloat(4 + (globe ? 1 : 0))
                XCTAssertEqual(plan.returnWidth, 0)
                XCTAssertEqual(plan.keyWidth * count + plan.spaceWidth + plan.spacing * count, width, accuracy: 0.00001)
                XCTAssertGreaterThan(plan.keyWidth, 60)
                XCTAssertGreaterThan(plan.spaceWidth, 44)
                XCTAssertLessThan(plan.spaceWidth, width * 0.65)
            }
        }
        let fallback = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: 649, hasGlobe: true,
            showsCollapse: true, showsPage: true, isPad: true, showsReturn: false, padTyping: true))
        XCTAssertEqual(fallback.keyWidth, 36)
    }
    func testInlinePadReturnReleasesItsFooterWidthAndSpacingWithoutDuplicatingAnInvisibleKey() throws {
        for width: CGFloat in [230, 234, 304, 650, 752, 1008] {
            for globe in [false, true] { for collapse in [false, true] {
                let value = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: width, hasGlobe: globe,
                    showsCollapse: collapse, showsPage: true, isPad: true, showsReturn: false))
                let count = 3 + (globe ? 1 : 0) + (collapse ? 1 : 0)
                XCTAssertEqual(value.returnWidth, 0)
                XCTAssertGreaterThanOrEqual(value.spaceWidth, 44)
                XCTAssertEqual(CGFloat(count) * value.keyWidth + value.spaceWidth + CGFloat(count) * value.spacing, width, accuracy: 0.000001)
            } }
        }
        XCTAssertNil(KeyboardFooterLayoutPolicy.plan(availableWidth: 100, hasGlobe: true,
            showsCollapse: true, showsPage: true, isPad: true, showsReturn: false))
    }

    func testAllPhoneAndPadCombinationsKeepSpaceAtLeast44AndFitExactAvailableWidth() throws {
        for screen: CGFloat in [320, 375, 390, 768] {
            for globe in [false, true] { for collapse in [false, true] { for page in [false, true] {
                let available = screen - 16
                let plan = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: available,
                    hasGlobe: globe, showsCollapse: collapse, showsPage: page, isPad: screen == 768))
                let count = 2 + (globe ? 1 : 0) + (collapse ? 1 : 0) + (page ? 1 : 0)
                XCTAssertGreaterThanOrEqual(plan.spaceWidth, 44)
                XCTAssertEqual(CGFloat(count) * plan.keyWidth + plan.returnWidth + plan.spaceWidth + CGFloat(count + 1) * plan.spacing,
                    available, accuracy: 0.000001)
                XCTAssertEqual(plan.keyWidth, 36)
            } } }
        }
    }
    func testSmallPhoneOnlyUsesTighterFooterWhenOptionalKeyNeedsItsSpace() throws {
        let regular = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: 304,
            hasGlobe: true, showsCollapse: false, showsPage: true, isPad: false))
        XCTAssertEqual(regular.returnWidth, 68)
        XCTAssertEqual(regular.spacing, 4)
        let extra = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: 304,
            hasGlobe: true, showsCollapse: true, showsPage: true, isPad: false))
        XCTAssertEqual(extra.returnWidth, 56)
        XCTAssertEqual(extra.spacing, 2)
        XCTAssertEqual(extra.spaceWidth, 56)
    }
    func testPadUsesComfortableReturnWhenItFitsButNarrowFloatingWidthRemainsSafe() throws {
        XCTAssertEqual(KeyboardFooterLayoutPolicy.plan(availableWidth: 752, hasGlobe: true,
            showsCollapse: true, showsPage: true, isPad: true)?.returnWidth, 112)
        let floating = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: 304,
            hasGlobe: true, showsCollapse: true, showsPage: true, isPad: true))
        XCTAssertGreaterThanOrEqual(floating.spaceWidth, 44)
    }
    func testNarrowFallbackUsesFiniteBoundedControlsAndPreservesSpace() throws {
        let plan = try XCTUnwrap(KeyboardFooterLayoutPolicy.plan(availableWidth: 230,
            hasGlobe: true, showsCollapse: true, showsPage: true, isPad: false))
        XCTAssertGreaterThanOrEqual(plan.keyWidth, 24)
        XCTAssertLessThan(plan.keyWidth, 36)
        XCTAssertGreaterThanOrEqual(plan.spaceWidth, 44)
        XCTAssertNil(KeyboardFooterLayoutPolicy.plan(availableWidth: 100, hasGlobe: true,
            showsCollapse: true, showsPage: true, isPad: false))
    }
    func testInvalidWidthsFailClosedAndExtremeFiniteWidthNeverCreatesInfinity() {
        for width: CGFloat in [.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(KeyboardFooterLayoutPolicy.plan(availableWidth: width, hasGlobe: false,
                showsCollapse: false, showsPage: true, isPad: false))
        }
        let huge = KeyboardFooterLayoutPolicy.plan(availableWidth: .greatestFiniteMagnitude,
            hasGlobe: true, showsCollapse: true, showsPage: true, isPad: true)
        XCTAssertTrue(huge?.spaceWidth.isFinite == true)
    }
}
