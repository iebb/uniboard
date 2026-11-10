import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardCompositionLayoutTests: XCTestCase {
    private func plan(scene: CGFloat? = 1000, grant: CGFloat? = nil,
                      enabled: Bool = true, available: Bool = true,
                      settled: Bool = false, compact: Bool = false,
                      english: Bool = false) -> KeyboardCompositionLayoutPlan {
        KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 41.4,
            sceneHeight: scene, actualGrantedHeight: grant, conversionEnabled: enabled,
            surfaceAvailable: available, hostHeightIsSettled: settled, prefersCompactShelf: compact,
            englishSingleRow: english)
    }

    func testRegularShelfRequestsOnlyIts74PointsAnd4PointGap() {
        let value = plan()
        XCTAssertEqual(value.requestedHeight, 328)
        XCTAssertEqual(value.shelf, .regular)
        XCTAssertEqual(value.shelfHeight, 74)
        XCTAssertEqual(value.compositionChromeHeight, 78)
        XCTAssertEqual(value.typingKeyHeight, 41.4)
        XCTAssertEqual(value.mergeNormalKeyHeight, 41.4)
        XCTAssertTrue(value.baselineFits)
        XCTAssertFalse(value.needsOverlayChoices)
        XCTAssertFalse(value.usesHostGrantedHeight)
    }

    func testPreferredCompactShelfRequestsOnly44AndGapEvenWithTallGrant() {
        for grant: CGFloat? in [nil, 0, 298, 328, 400] {
            let value = plan(grant: grant, compact: true)
            XCTAssertEqual(value.requestedHeight, 298)
            XCTAssertEqual(value.shelf, .compact)
            XCTAssertEqual(value.shelfHeight, 44)
            XCTAssertEqual(value.compositionChromeHeight, 48)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
            XCTAssertEqual(value.mergeNormalKeyHeight, 41.4)
            XCTAssertTrue(value.baselineFits)
            XCTAssertFalse(value.needsOverlayChoices)
        }
        XCTAssertEqual(plan(compact: true).availableKeyRegionHeight,
                       plan().availableKeyRegionHeight, accuracy: 0.0001,
                       "A shorter shelf reduces the request, not the baseline rows")
    }

    func testPreferredCompactStillHonorsGrantAndSceneWithoutGrowingOrShrinkingKeys() {
        for grant: CGFloat in [CGFloat(298).nextDown, 250, 220] {
            let value = plan(grant: grant, settled: true, compact: true)
            XCTAssertEqual(value.requestedHeight, 298)
            XCTAssertEqual(value.shelf, .none)
            XCTAssertTrue(value.needsOverlayChoices)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
            XCTAssertEqual(value.baselineFits, grant >= 250)
        }
        XCTAssertEqual(plan(scene: 360, compact: true).requestedHeight, 298)
        XCTAssertEqual(plan(scene: 340, compact: true).shelf, .none)
        XCTAssertEqual(plan(enabled: false, compact: true).requestedHeight, 250)
        XCTAssertEqual(plan(available: false, compact: true).shelf, .none)
    }

    func testCompactMergeUsesActual48PointChromeAndUnchangedThreeRowBaseline() {
        // Fixed chrome122 + compact chrome48 + four normal rows172 =342.
        let grants: [(CGFloat?, Bool)] = [(nil, false), (342, true), (CGFloat(342).nextDown, false)]
        for (grant, merged) in grants {
            let value = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 40,
                sceneHeight: 1000, actualGrantedHeight: grant, conversionEnabled: true,
                surfaceAvailable: true, baselineKeyRows: 3, prefersCompactShelf: true)
            XCTAssertEqual(value.requestedHeight, 298)
            XCTAssertEqual(value.shelf, .compact)
            XCTAssertEqual(value.typingKeyHeight, 40)
            XCTAssertEqual(value.mergeNormalKeyHeight, merged ? 40 : 0)
            if grant == nil { XCTAssertEqual(value.availableKeyRegionHeight, 128) }
        }
    }

    func testEnglishFull44PointBandReducesRequestByExactly12WithoutChangingKeyRegion() {
        let oldCompact = plan(compact: true)
        let baseline = plan(enabled: false)
        for grant: CGFloat? in [nil, 0, 286, 298, 400] {
            let value = plan(grant: grant, english: true)
            XCTAssertEqual(value.shelf, .compact, "English must never grow a 30-point preedit line")
            XCTAssertEqual(value.shelfHeight, 44, "Status, suggestions and Undo share the same geometry")
            XCTAssertEqual(value.compositionChromeHeight, 36,
                           "Full band44 replaces baseline top4 + content4; no new shelf gap")
            XCTAssertEqual(4 + value.compositionChromeHeight + 4, 44)
            XCTAssertEqual(value.requestedHeight, oldCompact.requestedHeight - 12)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
            XCTAssertEqual(value.mergeNormalKeyHeight, 41.4)
            XCTAssertFalse(value.needsOverlayChoices)
        }
        XCTAssertEqual(plan(english: true).availableKeyRegionHeight, baseline.availableKeyRegionHeight, accuracy: 0.0001)
        XCTAssertEqual(plan(english: true).availableKeyRegionHeight, oldCompact.availableKeyRegionHeight, accuracy: 0.0001)
    }

    func testEnglish44PointBandHonorsExactHostBoundaryWithoutStealingKeyHeight() {
        XCTAssertEqual(plan(grant: 286, english: true).shelf, .compact)
        for grant: CGFloat in [CGFloat(286).nextDown, 250, 220] {
            let value = plan(grant: grant, settled: true, english: true)
            XCTAssertEqual(value.requestedHeight, 286, "Do not lock request to an earlier host grant")
            XCTAssertEqual(value.shelf, .none)
            XCTAssertEqual(value.compositionChromeHeight, 0, "Absent shelf restores all baseline insets")
            XCTAssertTrue(value.needsOverlayChoices)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
            XCTAssertEqual(value.baselineFits, grant >= 250)
        }
        XCTAssertEqual(plan(scene: 340, english: true).requestedHeight, 286)
        XCTAssertEqual(plan(scene: 340, english: true).shelf, .compact)
        XCTAssertEqual(plan(scene: 330, english: true).shelf, .none)
        for (enabled, available) in [(false, false), (false, true), (true, false)] {
            let value = plan(enabled: enabled, available: available, english: true)
            XCTAssertEqual(value.requestedHeight, 250)
            XCTAssertEqual(value.shelf, .none)
            XCTAssertEqual(value.compositionChromeHeight, 0)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
        }
    }

    func testEnglishMergeRequiresFourNormalRowsAfterActual36PointAdditionalChrome() {
        // Fixed baseline chrome122 + English additional36 + four rows172 =330.
        let cases: [(CGFloat?, Bool)] = [(nil, false), (330, true), (CGFloat(330).nextDown, false)]
        for (grant, merged) in cases {
            let value = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 40,
                sceneHeight: 1000, actualGrantedHeight: grant, conversionEnabled: true,
                surfaceAvailable: true, baselineKeyRows: 3, englishSingleRow: true)
            XCTAssertEqual(value.requestedHeight, 286)
            XCTAssertEqual(value.shelfHeight, 44)
            XCTAssertEqual(value.typingKeyHeight, 40)
            XCTAssertEqual(value.mergeNormalKeyHeight, merged ? 40 : 0)
            if grant == nil { XCTAssertEqual(value.availableKeyRegionHeight, 128) }
        }
    }

    func testEnglishPreviewToolbarAndWidePadKeepTheirBaselineSpaceAndNormalMetrics() {
        let baseline: CGFloat = 250
        // Optional preview includes its unchanged 4-point spacer; toolbar retains full height.
        for extraChrome: CGFloat in [0, 45.4, 41.4, 45.4 + 41.4] {
            let value = KeyboardCompositionLayoutPolicy.plan(baselineHeight: baseline + extraChrome,
                baselineKeyHeight: 41.4, sceneHeight: 1000, conversionEnabled: true,
                surfaceAvailable: true, englishSingleRow: true)
            XCTAssertEqual(value.requestedHeight, baseline + extraChrome + 36, accuracy: 0.0001)
            XCTAssertEqual(value.availableKeyRegionHeight, plan(english: true).availableKeyRegionHeight, accuracy: 0.0001)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
        }
        let pad = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 360, baselineKeyHeight: 59.8,
            sceneHeight: 1000, conversionEnabled: true, surfaceAvailable: true,
            baselineKeyRows: 4, rowSpacing: 6, englishSingleRow: true)
        XCTAssertEqual(pad.requestedHeight, 396)
        XCTAssertEqual(pad.typingKeyHeight, 59.8)
        XCTAssertEqual(pad.availableKeyRegionHeight, 4 * 59.8 + 18, accuracy: 0.0001)
        XCTAssertEqual(pad.mergeNormalKeyHeight, 59.8)
    }

    func testIntrinsicCaptionPlusGapMustLeaveAtLeastHalfAvailableLine() {
        XCTAssertTrue(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: 70, availableLineWidth: 156))
        XCTAssertFalse(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: CGFloat(70).nextUp, availableLineWidth: 156))
        XCTAssertTrue(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: 100, availableLineWidth: 216))
        XCTAssertFalse(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: 101, availableLineWidth: 216))
        for invalid: CGFloat in [-1, .nan, .infinity, -.infinity] {
            XCTAssertFalse(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: invalid, availableLineWidth: 300))
            XCTAssertFalse(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: 60, availableLineWidth: invalid))
            XCTAssertFalse(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: 60, availableLineWidth: 300, gap: invalid))
        }
        XCTAssertFalse(KeyboardCompositionLayoutPolicy.regularCaptionFits(captionWidth: 0, availableLineWidth: 0))
    }

    func testSceneCapChoosesCompactThenShelfFreeWithoutShrinkingKeys() {
        let compact = plan(scene: 360) // cap306: full328 cannot fit, compact298 can.
        XCTAssertEqual(compact.requestedHeight, 298)
        XCTAssertEqual(compact.shelf, .compact)
        XCTAssertEqual(compact.compositionChromeHeight, 48)
        XCTAssertEqual(compact.typingKeyHeight, 41.4)
        XCTAssertEqual(compact.mergeNormalKeyHeight, 41.4)
        let none = plan(scene: 340) // cap289: even compact298 cannot fit.
        XCTAssertEqual(none.requestedHeight, 250)
        XCTAssertEqual(none.shelf, .none)
        XCTAssertEqual(none.compositionChromeHeight, 0)
        XCTAssertTrue(none.needsOverlayChoices)
        XCTAssertEqual(none.typingKeyHeight, 41.4)
        XCTAssertTrue(none.baselineFits)
    }

    func testCapBelowBaselineReportsUnmetGeometryAndOverlayNotSmallerKeys() {
        let value = plan(scene: 200)
        XCTAssertEqual(value.requestedHeight, 170)
        XCTAssertEqual(value.shelf, .none)
        XCTAssertTrue(value.needsOverlayChoices)
        XCTAssertFalse(value.baselineFits)
        XCTAssertEqual(value.typingKeyHeight, 41.4)
        XCTAssertEqual(value.mergeNormalKeyHeight, 0)
    }

    func testHostGrantControlsRenderedShelfButNotNaturalHeightNegotiation() {
        let cases: [(CGFloat, KeyboardCompositionShelf)] = [
            (328, .regular), (CGFloat(328).nextDown, .compact),
            (298, .compact), (CGFloat(298).nextDown, .none), (250, .none)
        ]
        for (grant, shelf) in cases {
            let value = plan(grant: grant)
            XCTAssertEqual(value.requestedHeight, 328, "Do not lock request to the previous smaller grant")
            XCTAssertEqual(value.shelf, shelf)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
            XCTAssertTrue(value.usesHostGrantedHeight)
            XCTAssertEqual(value.needsOverlayChoices, shelf == .none)
            XCTAssertTrue(value.baselineFits)
        }
    }

    func testInitialZeroAndSubBaselineMeasurementsDoNotDisableNaturalShelf() {
        for grant: CGFloat? in [nil, 0, -1, .nan, .infinity, -.infinity, 1, 249] {
            let value = plan(grant: grant)
            XCTAssertEqual(value.requestedHeight, 328)
            XCTAssertEqual(value.shelf, .regular)
            XCTAssertFalse(value.usesHostGrantedHeight)
        }
    }

    func testExplicitSettledSubBaselineGrantFailsClosedWithoutShrinkingKeys() {
        let value = plan(grant: 220, settled: true)
        XCTAssertTrue(value.usesHostGrantedHeight)
        XCTAssertEqual(value.requestedHeight, 328)
        XCTAssertEqual(value.shelf, .none)
        XCTAssertFalse(value.baselineFits)
        XCTAssertTrue(value.needsOverlayChoices)
        XCTAssertEqual(value.typingKeyHeight, 41.4)
        XCTAssertEqual(value.mergeNormalKeyHeight, 0)
        XCTAssertFalse(plan(grant: 0, settled: true).usesHostGrantedHeight,
                       "Even a settled zero is not useful host geometry")
    }

    func testConversionDisabledOrSurfaceUnavailableAddsNoShelfOrOverlay() {
        for (enabled, available) in [(false, false), (false, true), (true, false)] {
            let value = plan(enabled: enabled, available: available)
            XCTAssertEqual(value.requestedHeight, 250)
            XCTAssertEqual(value.shelf, .none)
            XCTAssertEqual(value.typingKeyHeight, 41.4)
            XCTAssertFalse(value.needsOverlayChoices)
        }
    }

    func testPreviewAndToolbarAreAlreadyInBaselineAndNeverCountedTwiceOrRemoved() {
        let noPreview = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 41.4,
            sceneHeight: 1000, conversionEnabled: true, surfaceAvailable: true)
        let withPreview = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 295.4, baselineKeyHeight: 41.4,
            sceneHeight: 1000, conversionEnabled: true, surfaceAvailable: true)
        XCTAssertEqual(withPreview.requestedHeight - noPreview.requestedHeight, 45.4, accuracy: 0.0001)
        XCTAssertEqual(withPreview.availableKeyRegionHeight, noPreview.availableKeyRegionHeight, accuracy: 0.0001)
        let constrained = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 295.4, baselineKeyHeight: 41.4,
            sceneHeight: 390, conversionEnabled: true, surfaceAvailable: true)
        XCTAssertEqual(constrained.shelf, .none)
        XCTAssertEqual(constrained.requestedHeight, 295.4)
        XCTAssertTrue(constrained.needsOverlayChoices)
    }

    func testMergeRequiresFourRowsAfterEveryPieceOfChromeNotJustNormalKeyMetric() {
        // Three normal rows never authorize four merged rows at natural height.
        let natural = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 40,
            sceneHeight: 1000, conversionEnabled: true, surfaceAvailable: true, baselineKeyRows: 3)
        XCTAssertEqual(natural.typingKeyHeight, 40)
        XCTAssertEqual(natural.mergeNormalKeyHeight, 0)
        XCTAssertEqual(natural.availableKeyRegionHeight, 128)
        // Fixed chrome122 + shelf78 + four rows172 =372, not merely baseline250.
        let fits = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 40,
            sceneHeight: 1000, actualGrantedHeight: 372, conversionEnabled: true,
            surfaceAvailable: true, baselineKeyRows: 3)
        XCTAssertEqual(fits.mergeNormalKeyHeight, 40)
        let short = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 250, baselineKeyHeight: 40,
            sceneHeight: 1000, actualGrantedHeight: CGFloat(372).nextDown, conversionEnabled: true,
            surfaceAvailable: true, baselineKeyRows: 3)
        XCTAssertEqual(short.mergeNormalKeyHeight, 0)
    }

    func testWidePadNormalHeightAndSixPointRowSpacingArePreserved() {
        for grant: CGFloat? in [nil, 438, 408, 360] {
            let value = KeyboardCompositionLayoutPolicy.plan(baselineHeight: 360, baselineKeyHeight: 59.8,
                sceneHeight: 1000, actualGrantedHeight: grant, conversionEnabled: true,
                surfaceAvailable: true, baselineKeyRows: 4, rowSpacing: 6)
            XCTAssertEqual(value.typingKeyHeight, 59.8)
            XCTAssertEqual(value.requestedHeight, 438)
            XCTAssertTrue(value.baselineFits)
            XCTAssertGreaterThanOrEqual(value.availableKeyRegionHeight, 4 * 59.8 + 18 - 0.0001)
        }
    }

    func testInvalidSceneOrHostGeometryCannotInjectNaNOrInfinityIntoPlan() {
        for scene: CGFloat? in [nil, 0, -1, .nan, .infinity, -.infinity] {
            let value = plan(scene: scene)
            XCTAssertEqual(value.requestedHeight, 328)
            XCTAssertEqual(value.shelf, .regular)
        }
        for invalid: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            let value = KeyboardCompositionLayoutPolicy.plan(baselineHeight: invalid, baselineKeyHeight: 41.4,
                sceneHeight: 1000, conversionEnabled: true, surfaceAvailable: true)
            XCTAssertEqual(value.shelf, .none)
            XCTAssertEqual(value.mergeNormalKeyHeight, 0)
            XCTAssertTrue(value.requestedHeight.isFinite)
            XCTAssertFalse(value.baselineFits)
        }
    }
}
