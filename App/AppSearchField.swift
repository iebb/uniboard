import SwiftUI
import UIKit

/// Live search finishes with the keyboard's own Done key. No accessory bar
/// adds a floating confirmation button or another keyboard layout band.
struct AppSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let identifier: String
    var textStyle: UIFont.TextStyle = .body
    /// Takes focus once, when the field is first created.
    var focusOnAppear = false

    func makeUIView(context: Context) -> AppSearchTextField {
        let field = AppSearchTextField()
        field.font = .preferredFont(forTextStyle: textStyle)
        configure(field)
        if focusOnAppear { DispatchQueue.main.async { field.becomeFirstResponder() } }
        return field
    }

    func updateUIView(_ field: AppSearchTextField, context: Context) {
        configure(field)
    }

    private func configure(_ field: AppSearchTextField) {
        let binding = $text
        field.configure(text: text, placeholder: placeholder, identifier: identifier) {
            binding.wrappedValue = $0
        }
    }
}

/// The delegate lives with the actual field, preserving its native caret
/// through ordinary SwiftUI binding updates.
final class AppSearchTextField: UITextField, UITextFieldDelegate {
    private var textChanged: ((String) -> Void)?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        delegate = self
        borderStyle = .none
        backgroundColor = .clear
        textColor = .label
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        keyboardType = .default
        returnKeyType = .done
        clearButtonMode = .never // SearchBar owns the visible clear action.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addTarget(self, action: #selector(editingChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, placeholder: String, identifier: String,
                   onTextChanged: @escaping (String) -> Void) {
        textChanged = onTextChanged
        self.placeholder = placeholder
        accessibilityIdentifier = identifier
        accessibilityLabel = placeholder
        // Ordinary SwiftUI binding refreshes must not move the native caret,
        // discard a selected range or replace an active composition.
        if !(self.text ?? "").utf16.elementsEqual(text.utf16) { self.text = text }
    }

    @objc private func editingChanged() {
        textChanged?(text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
