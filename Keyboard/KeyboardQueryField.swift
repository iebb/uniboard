import SwiftUI
import UIKit

/// An editor for the keyboard's local query. It deliberately never becomes a
/// text-input responder, so the host app keeps its document proxy and focus.
struct KeyboardQueryField: UIViewRepresentable {
    let query: String
    let caretUTF16Offset: Int
    let isEditing: Bool
    let isEmojiScope: Bool
    let contextIdentifier: UUID
    let enabled: Bool
    let actionFactory: KeyboardQueryInteraction.ActionFactory

    func makeUIView(context: Context) -> KeyboardQueryControl {
        let view = KeyboardQueryControl()
        view.tintColor = KeyboardPalette.accentUI
        return view
    }

    func updateUIView(_ view: KeyboardQueryControl, context: Context) {
        view.configure(query: query, caretUTF16Offset: caretUTF16Offset,
                       isEditing: isEditing, isEmojiScope: isEmojiScope,
                       contextIdentifier: contextIdentifier, enabled: enabled, actionFactory: actionFactory)
    }
}
