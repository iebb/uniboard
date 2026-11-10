import Foundation

public enum KeyboardCompositionShelf: Equatable, Sendable {
    case regular
    case compact
    case none

    public var height: CGFloat {
        switch self {
        case .regular: return 74
        case .compact: return 44
        case .none: return 0
        }
    }

    public var chromeHeight: CGFloat { height == 0 ? 0 : height + 4 }
}

public struct KeyboardCompositionLayoutPlan: Equatable, Sendable {
    /// Scene-constrained natural request, independent of a previous host grant.
    /// Keeping this separate from the rendered shelf avoids a negotiation loop
    /// where an old baseline grant prevents ever requesting the larger height.
    public let requestedHeight: CGFloat
    public let shelf: KeyboardCompositionShelf
    public var shelfHeight: CGFloat { shelf.height }
    /// Additional chrome relative to the unchanged baseline, not the full band.
    /// English replaces the baseline's 4-point top and 4-point content insets.
    public let compositionChromeHeight: CGFloat
    /// Exactly the supplied baseline metric; conversion NEVER scales keys.
    public let typingKeyHeight: CGFloat
    public let availableKeyRegionHeight: CGFloat
    /// Pass this to KeyboardMergedSymbolsPolicy, not typingKeyHeight. Zero
    /// explicitly disables merge if four full normal rows do not actually fit.
    public let mergeNormalKeyHeight: CGFloat
    public let baselineFits: Bool
    public let usesHostGrantedHeight: Bool
    public let needsOverlayChoices: Bool
}

/// Pure geometry for design §5.2. Baseline height must ALREADY include the
/// user's preview, visible toolbar, footer, system band and existing gaps.
/// Do not add preview twice or disable it to make a shelf fit. The caller must
/// pass the original normal baseline key height, not a recomputed IME height.
public enum KeyboardCompositionLayoutPolicy {
    public static let sceneHeightFraction: CGFloat = 0.85

    /// A regular shelf reserves an intrinsic caption plus its gap, leaving at
    /// least half the available line for unfinished text. UIKit supplies the
    /// scaled caption measurement; this fit decision is deterministic geometry.
    public static func regularCaptionFits(captionWidth: CGFloat, availableLineWidth: CGFloat,
                                          gap: CGFloat = 8) -> Bool {
        guard captionWidth.isFinite, captionWidth >= 0,
              availableLineWidth.isFinite, availableLineWidth > 0,
              gap.isFinite, gap >= 0 else { return false }
        return captionWidth + gap <= availableLineWidth / 2
    }

    /// baselineKeyRows counts physical rows ABOVE the footer; supply the actual
    /// arrangement count (including an auxiliary row), and its row spacing.
    /// They let us recover fixed baseline chrome without guessing preview or
    /// footer metrics. Defaults describe a four-row phone arrangement.
    ///
    /// nil/zero/invalid grants are unmeasured. A positive grant below baseline is
    /// ignored during initial negotiation unless hostHeightIsSettled is true.
    /// Grants >= baseline are enforced immediately. Set the settled flag when a
    /// genuinely smaller final host bound is known, rather than treating it as
    /// initial zero layout. No state, timer or UIKit observation is hidden here.
    /// prefersCompactShelf keeps a caption that cannot fit at 44 points.
    /// englishSingleRow also forces 44-point content, but has NO exterior top,
    /// shelf or content gap: its full band is 44, not 4 + 44 + 4 + 4 = 56.
    /// Since baselineHeight already includes top4 + content4, English adds only
    /// 44 - 8 = 36 points. No baseline inset is removed when the shelf is absent.
    public static func plan(baselineHeight: CGFloat, baselineKeyHeight: CGFloat,
                            sceneHeight: CGFloat?, actualGrantedHeight: CGFloat? = nil,
                            conversionEnabled: Bool, surfaceAvailable: Bool,
                            baselineKeyRows: Int = 4, rowSpacing: CGFloat = 4,
                            hostHeightIsSettled: Bool = false,
                            prefersCompactShelf: Bool = false,
                            englishSingleRow: Bool = false) -> KeyboardCompositionLayoutPlan {
        guard baselineHeight.isFinite, baselineHeight > 0,
              baselineKeyHeight.isFinite, baselineKeyHeight > 0,
              rowSpacing.isFinite, rowSpacing >= 0, (1...256).contains(baselineKeyRows) else {
            return .init(requestedHeight: 0, shelf: .none, compositionChromeHeight: 0, typingKeyHeight: 0,
                         availableKeyRegionHeight: 0, mergeNormalKeyHeight: 0,
                         baselineFits: false, usesHostGrantedHeight: false,
                         needsOverlayChoices: conversionEnabled && surfaceAvailable)
        }
        let baselineKeys = CGFloat(baselineKeyRows) * baselineKeyHeight
            + CGFloat(baselineKeyRows - 1) * rowSpacing
        guard baselineKeys.isFinite, baselineKeys <= baselineHeight else {
            return .init(requestedHeight: baselineHeight, shelf: .none, compositionChromeHeight: 0, typingKeyHeight: baselineKeyHeight,
                         availableKeyRegionHeight: 0, mergeNormalKeyHeight: 0,
                         baselineFits: false, usesHostGrantedHeight: false,
                         needsOverlayChoices: conversionEnabled && surfaceAvailable)
        }
        let fixedChrome = baselineHeight - baselineKeys
        let cap = sceneHeight.flatMap { height -> CGFloat? in
            height.isFinite && height > 0 ? height * sceneHeightFraction : nil
        } ?? CGFloat.greatestFiniteMagnitude
        let active = conversionEnabled && surfaceAvailable
        func chromeHeight(_ shelf: KeyboardCompositionShelf) -> CGFloat {
            guard shelf != .none else { return 0 }
            return englishSingleRow ? shelf.height - 8 : shelf.chromeHeight
        }
        func shelfFitting(_ height: CGFloat) -> KeyboardCompositionShelf {
            guard active else { return .none }
            if !englishSingleRow && !prefersCompactShelf && height >= baselineHeight + chromeHeight(.regular) { return .regular }
            if height >= baselineHeight + chromeHeight(.compact) { return .compact }
            return .none
        }
        let preferred = shelfFitting(cap)
        let requested = min(cap, baselineHeight + chromeHeight(preferred))
        let grant = actualGrantedHeight.flatMap { height -> CGFloat? in
            guard height.isFinite, height > 0,
                  height >= baselineHeight || hostHeightIsSettled else { return nil }
            return height
        }
        let available = min(cap, grant ?? requested)
        let shelf = shelfFitting(available)
        let compositionChrome = chromeHeight(shelf)
        let keyRegion = max(0, available - fixedChrome - compositionChrome)
        let fourRows = 4 * baselineKeyHeight + 3 * rowSpacing
        let fourRowsTotal = fixedChrome + compositionChrome + fourRows
        return .init(requestedHeight: requested, shelf: shelf, compositionChromeHeight: compositionChrome,
                     typingKeyHeight: baselineKeyHeight,
                     availableKeyRegionHeight: keyRegion,
                     mergeNormalKeyHeight: fourRowsTotal.isFinite && available >= fourRowsTotal ? baselineKeyHeight : 0,
                     baselineFits: available >= baselineHeight, usesHostGrantedHeight: grant != nil,
                     needsOverlayChoices: active && shelf == .none)
    }
}
