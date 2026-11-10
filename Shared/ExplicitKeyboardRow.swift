import SwiftUI

/// Full-width physical row used by explicit editors and the keyboard. Gaps
/// are ordinary subviews, so Spread includes them without stretching cells.
struct ExplicitKeyboardRow: Layout {
    var alignment: KeyboardRowAlignment
    var spacing: CGFloat
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1)),
                      height: sizes.map(\.height).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = ExplicitRowGeometry.origins(widths: sizes.map(\.width), available: bounds.width,
                                                  spacing: spacing, alignment: alignment, scale: scale)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + origins[index], y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(sizes[index]))
        }
    }
}
