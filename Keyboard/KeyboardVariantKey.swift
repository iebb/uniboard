import SwiftUI
import UIKit

/// Native press/hold/slide selection keeps the original host first responder.
struct KeyboardVariantKey: UIViewRepresentable {
    let text: String
    let variants: [String]
    let identifier: String
    var label: String? = nil
    var value: String? = nil
    var symbol: String? = nil
    let route: UUID
    var enabled = true
    var fontSize: CGFloat = 23
    var foreground: UIColor = .label
    var hint: String? = nil
    var useUnicodeFonts = false
    var preservesPressAcrossTextChanges = false
    var longPressOptions: [String]? = nil
    var swipeUp: [String]? = nil
    var swipeDown: [String]? = nil
    var secondaryText: String? = nil
    var contentPosition: KeyboardKeyContentPosition = .center
    var showsInspection = false
    var showsEditing = false
    var holdLabel: String? = nil
    /// Shown for the key and its choices instead of their literal text.
    var displayText: ((String) -> String)? = nil
    /// Names a hold choice for VoiceOver instead of its text and code points.
    var actionName: ((String) -> String)? = nil
    /// A named accessibility action that does what activating the key does.
    var primaryActionName: String? = nil
    /// Asked on each update; true once moves VoiceOver focus to this key.
    var focusRequest: (@MainActor () -> Bool)? = nil
    let factory: KeyboardVariantInteraction.Factory

    func makeUIView(context: Context) -> KeyboardVariantButton { KeyboardVariantButton() }
    func updateUIView(_ view: KeyboardVariantButton, context: Context) {
        let font = UnicodeFontSupport.font(for: symbolBoardPreview(text), size: fontSize, enabled: useUnicodeFonts, anchor: symbolBoardFontAnchor(text))
        view.configure(context: route, key: identifier, text: text, variants: variants,
            enabled: enabled, font: font, symbol: symbol, foreground: foreground,
            preservesPressAcrossTextChanges: preservesPressAcrossTextChanges,
            longPressOptions: longPressOptions, swipeUp: swipeUp, swipeDown: swipeDown, secondaryText: secondaryText, contentPosition: contentPosition,
            showsInspection: showsInspection, showsEditing: showsEditing, holdLabel: holdLabel,
            popupFont: { UnicodeFontSupport.font(for: symbolBoardPreview($0), size: fontSize, enabled: useUnicodeFonts, anchor: symbolBoardFontAnchor($0)) },
            displayText: displayText ?? symbolBoardPreview, actionName: actionName,
            primaryActionName: primaryActionName, factory: factory)
        view.tintColor = KeyboardPalette.accentUI
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = label ?? text
        view.accessibilityValue = value
        view.accessibilityHint = hint ?? "Tap to insert. Hold, slide to a choice, then lift your finger."
        if focusRequest?() == true, UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak view] in
                UIAccessibility.post(notification: .layoutChanged, argument: view)
            }
        }
    }
}
