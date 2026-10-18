#if canImport(UIKit)
import UIKit

/// Only semantic traits are retained. The optional protocol getter and its
/// null-unspecified content type are flattened before any value is inspected.
struct KeyboardHostInputTraits: Equatable {
    let keyboardType: UIKeyboardType
    let capitalization: UITextAutocapitalizationType
    let returnKey: UIReturnKeyType
    let textContentType: UITextContentType?

    @MainActor
    init(reading source: any UITextInputTraits) {
        keyboardType = source.keyboardType ?? .default
        capitalization = source.autocapitalizationType ?? .sentences
        returnKey = source.returnKeyType ?? .default
        let contentType: UITextContentType? = source.textContentType ?? nil
        textContentType = contentType
    }

    /// These identifier/address/code fields must remain literal even when a
    /// host leaves keyboardType at default. Unknown future content types keep
    /// ordinary English behavior; manual Shift and Caps are a separate policy.
    var permitsEnglishAssistance: Bool {
        if let textContentType,
           [.URL, .emailAddress, .username, .password, .newPassword, .oneTimeCode].contains(textContentType) {
            return false
        }
        switch keyboardType {
        case .default, .asciiCapable, .twitter: return true
        default: return false
        }
    }
}

/// Same-document semantic changes are real input boundaries, including when
/// the keyboard page and visible text suffix happen to remain unchanged.
struct KeyboardHostInputSignature: Equatable {
    let documentIdentifier: UUID
    let traits: KeyboardHostInputTraits
}
#endif
