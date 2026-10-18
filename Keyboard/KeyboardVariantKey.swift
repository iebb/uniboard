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
    let factory: KeyboardVariantInteraction.Factory

    func makeUIView(context: Context) -> KeyboardVariantButton { KeyboardVariantButton() }
    func updateUIView(_ view: KeyboardVariantButton, context: Context) {
        let font = UnicodeFontSupport.font(for: text, size: fontSize, enabled: useUnicodeFonts)
        view.configure(context: route, key: identifier, text: text, variants: variants,
            enabled: enabled, font: font, symbol: symbol, foreground: foreground,
            preservesPressAcrossTextChanges: preservesPressAcrossTextChanges,
            longPressOptions: longPressOptions, swipeUp: swipeUp, swipeDown: swipeDown, secondaryText: secondaryText, contentPosition: contentPosition,
            showsInspection: showsInspection, showsEditing: showsEditing, holdLabel: holdLabel,
            popupFont: { UnicodeFontSupport.font(for: symbolBoardPreview($0), size: fontSize, enabled: useUnicodeFonts) },
            displayText: symbolBoardPreview, factory: factory)
        view.tintColor = KeyboardPalette.accentUI
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = label ?? text
        view.accessibilityValue = value
        view.accessibilityHint = hint ?? "Tap to insert. Hold, slide to a choice, then lift your finger."
    }
}
