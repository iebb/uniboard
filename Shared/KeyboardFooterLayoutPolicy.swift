import Foundation

/// Footer sizing reserves a real Space target before optional controls. The
/// narrower fallback is for small phones with both Globe and Collapse shown.
enum KeyboardFooterLayoutPolicy {
    struct Plan {
        let keyWidth: CGFloat
        let returnWidth: CGFloat
        let spaceWidth: CGFloat
        let spacing: CGFloat
    }
    static func plan(availableWidth: CGFloat, hasGlobe: Bool, showsCollapse: Bool,
                     showsPage: Bool, isPad: Bool) -> Plan? {
        guard availableWidth.isFinite, availableWidth > 0 else { return nil }
        let count = 2 + (hasGlobe ? 1 : 0) + (showsCollapse ? 1 : 0) + (showsPage ? 1 : 0)
        let gaps = CGFloat(count + 1)
        func result(key: CGFloat, returnWidth: CGFloat, gap: CGFloat) -> Plan? {
            let space = availableWidth - CGFloat(count) * key - returnWidth - gaps * gap
            guard space.isFinite, space >= 44 else { return nil }
            return Plan(keyWidth: key, returnWidth: returnWidth, spaceWidth: space, spacing: gap)
        }
        if let preferred = result(key: 36, returnWidth: isPad ? 112 : 68, gap: 4) { return preferred }
        if let compact = result(key: 36, returnWidth: 56, gap: 2) { return compact }
        // Fail safely on an unusually narrow host rather than assigning a
        // negative or nonfinite SwiftUI frame. Normal phone widths use36pt.
        let key = min(36, (availableWidth - 44 - 44 - gaps * 2) / CGFloat(count))
        guard key.isFinite, key >= 24 else { return nil }
        return result(key: key, returnWidth: 44, gap: 2)
    }
}
