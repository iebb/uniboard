import SwiftUI
import UIKit

/// App search uses a native accessory bar. The system owns its keyboard
/// sizing, without SwiftUI's InputAccessoryBar introducing another layout.
struct AppSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let identifier: String

    func makeUIView(context: Context) -> AppSearchTextField {
        let field = AppSearchTextField()
        configure(field)
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

/// The delegate and accessory targets live with the actual field, rather than
/// an independently retained coordinator or a second text-input responder.
final class AppSearchTextField: UITextField, UITextFieldDelegate {
    private var textChanged: ((String) -> Void)?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        delegate = self
        borderStyle = .none
        backgroundColor = .clear
        textColor = .label
        font = .preferredFont(forTextStyle: .subheadline)
        adjustsFontForContentSizeCategory = true
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        keyboardType = .default
        returnKeyType = .search
        clearButtonMode = .never // SearchBar owns the visible clear action.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        // A valid initial height is important before UIKit attaches the bar.
        // Its width follows the actual input window, including after rotation.
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.autoresizingMask = [.flexibleWidth]
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePressed))
        ]
        inputAccessoryView = bar
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

    @objc private func donePressed() {
        resignFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
