import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardFooterLayoutPolicyTests: XCTestCase {
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
