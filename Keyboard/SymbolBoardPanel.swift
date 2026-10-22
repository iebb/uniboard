import SwiftUI
import UIKit

/// Opaque configuration owns the complete proposed overlay area. A clipped,
/// finite ScrollView keeps large boards and the local pad inside that area.
private extension View {
    func symbolBoardOpaquePanel() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KeyboardPalette.background)
            .contentShape(Rectangle())
            .clipped()
    }
}

/// The persistent editor has a document/mode lifetime, but every physical
/// press takes a fresh strict interaction-generation guard at touch-down.
private struct SymbolBoardConfigurationButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let guardFactory: () -> (() -> Bool)?
    var minimumHeight: CGFloat = 32
    var horizontalPadding: CGFloat = 8
    var fillsSurface = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minimumHeight)
            .contentShape(Rectangle())
            .background(fillsSurface ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.45)
            .overlay {
                SymbolBoardConfigurationTouchOverlay(enabled: isEnabled, guardFactory: guardFactory,
                    trigger: { configuration.trigger() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // Accessibility activation is atomic, rather than a held
                // physical press. It still requires the current strict scope.
                guard isEnabled, let current = guardFactory(), current() else { return }
                configuration.trigger()
            }
    }
}

private struct SymbolBoardConfigurationTouchOverlay: UIViewRepresentable {
    let enabled: Bool
    let guardFactory: () -> (() -> Bool)?
    let trigger: () -> Void

    func makeUIView(context: Context) -> KeyboardConfigurationTouchView {
        let view = KeyboardConfigurationTouchView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.02)
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ view: KeyboardConfigurationTouchView, context: Context) {
        view.isEnabled = enabled
        view.isUserInteractionEnabled = enabled
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        // Reconfiguration cancels an old label/action press. A later down
        // snapshots the fresh factory; an old up can never retarget to it.
        let capture = guardFactory
        let perform = trigger
        view.configure(contextIdentifier: UUID()) { [weak view] in
            guard view?.isEnabled == true, let current = capture(), current() else { return { false } }
            return { [weak view] in
                guard view?.isEnabled == true, current() else { return false }
                perform()
                return true
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyboardConfigurationTouchView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width >= 0, height >= 0 else { return nil }
        return CGSize(width: width, height: height)
    }
    static func dismantleUIView(_ view: KeyboardConfigurationTouchView, coordinator: ()) {
        view.isEnabled = false
        view.isUserInteractionEnabled = false
        view.configure(contextIdentifier: UUID()) { { false } }
    }
}

/// A visible substitute is presentation only; insertion always uses the
/// original string, including NUL, controls and standalone combining marks.
func symbolBoardPreview(_ text: String) -> String {
    if text == " " { return "␠" }
    if text == "\n" { return "↵" }
    if text == "\r" { return "␍" }
    if text == "\t" { return "⇥" }
    if text == "\0" { return "␀" }
    guard let first = text.unicodeScalars.first else { return "◌" }
    if text.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }) { return "◌" }
    if [.nonspacingMark, .spacingMark, .enclosingMark].contains(first.properties.generalCategory) { return "◌" + text }
    return text
}

func symbolBoardKeyLabel(_ text: String) -> String {
    let points = text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    return "\(symbolBoardPreview(text)), \(points)"
}
