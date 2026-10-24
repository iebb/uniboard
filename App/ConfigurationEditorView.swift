import SwiftUI
import UIKit

/// Edit Configuration (design/config-editor/design.md): a large sheet with
/// the configuration as plain TOML text, a status bar with Validate on top
/// of the keyboard, and Apply through the existing review, pushed inside
/// the sheet. Closing never applies anything.
struct ConfigurationEditorView: View {
    @ObservedObject var model: ConfigurationEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ConfigurationCopy.edit)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.review = nil } })) {
                    if let review = model.review {
                        ReviewImportView(model: review, close: { dismiss() })
                    }
                }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isEdited)
        .task { await model.load() }
        .alert(ConfigurationCopy.changedTitle, isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button(ConfigurationCopy.reviewAgain) { Task { await model.reviewAgain() } }
            Button("Cancel", role: .cancel) { model.cancelChanged() }
        } message: {
            Text(ConfigurationCopy.editChangedBody)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if model.isEdited { confirmingDiscard = true } else { dismiss() }
            }
            .accessibilityIdentifier("configurationEditor.cancel")
            .confirmationDialog(ConfigurationCopy.discardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button(ConfigurationCopy.discard, role: .destructive) { dismiss() }
                Button(ConfigurationCopy.keepEditing, role: .cancel) {}
            } message: {
                Text(ConfigurationCopy.discardBody)
            }
        }
        if model.loaded != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button(ConfigurationCopy.editApply) { Task { await model.apply() } }
                    .disabled(!model.canApply)
                    .accessibilityIdentifier("configurationEditor.apply")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.loaded != nil {
            GeometryReader { geometry in
                // The iPhone popover leaves the keyboard live; nothing may type behind it.
                ConfigurationTextView(text: $model.text, cursor: model.cursor, hidesKeyboard: confirmingDiscard)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // 40%; 50% at accessibility sizes, where a two-line
                        // title and a three-line first error need it (rev. 4
                        // guidance, after hiding the icon wasn't enough).
                        ConfigurationEditorStatusBar(model: model, maxStatusHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.4))
                    }
            }
        } else if model.loadFailed {
            VStack(spacing: 12) {
                Image(systemName: "xmark.octagon")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .accessibilityHidden(true)
                Text(ConfigurationCopy.exportFailed).font(.title3.weight(.semibold))
                Text(ConfigurationCopy.exportFailedBody).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(ConfigurationCopy.preparing).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The bottom bar: the status on the leading side, Validate on the
/// trailing side; Validate goes under the status at accessibility sizes.
private struct ConfigurationEditorStatusBar: View {
    @ObservedObject var model: ConfigurationEditorModel
    let maxStatusHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsAllProblems = false
    @State private var statusHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        cappedStatus
                        validate.frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        cappedStatus
                        Spacer(minLength: 8)
                        validate
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .onChange(of: model.status) { showsAllProblems = false }
    }

    private var validate: some View {
        Button {
            Task { await model.validate() }
        } label: {
            // The bordered style adds 7 pt above and below: 30 + 14 = a 44 pt target.
            Text(ConfigurationCopy.editValidate)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!model.canValidate)
        .accessibilityIdentifier("configurationEditor.validate")
    }

    /// At most 40% (50% at accessibility sizes) of the space above the
    /// keyboard; beyond that it scrolls.
    private var cappedStatus: some View {
        ScrollView {
            status.background(GeometryReader { geometry in
                Color.clear.preference(key: StatusHeight.self, value: geometry.size.height)
            })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(statusHeight, maxStatusHeight))
        .onPreferenceChange(StatusHeight.self) { statusHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("configurationEditor.result")
    }

    @ViewBuilder private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // At accessibility sizes the text gets the full width, so the
            // first error fits inside the cap (design rev. 4 guidance).
            if !dynamicTypeSize.isAccessibilitySize {
                icon.font(.system(size: 17)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) { lines }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
    }

    @ViewBuilder private var icon: some View {
        switch model.status {
        case .helper, .unchecked: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case let .valid(warnings):
            if warnings.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(uiColor: .systemGreen))
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(uiColor: .systemOrange))
            }
        case .invalid: Image(systemName: "xmark.octagon.fill").foregroundStyle(Color(uiColor: .systemRed))
        case .empty: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(uiColor: .systemOrange))
        }
    }

    @ViewBuilder private var lines: some View {
        switch model.status {
        case .helper, .unchecked, .checking:
            Text(model.statusTitle).foregroundStyle(.secondary)
        case let .valid(warnings):
            Text(model.statusTitle).foregroundStyle(.primary)
            ForEach(warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
        case .empty:
            Text(model.statusTitle).foregroundStyle(.primary)
        case let .invalid(problems):
            // Rev. 4 order, all sizes: the error comes right after the
            // title, so the 40% cap never pushes it out of sight.
            Text(model.statusTitle).fontWeight(.semibold).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let first = problems.first { problem(first) }
            if problems.count > 1 {
                if showsAllProblems {
                    ForEach(problems.dropFirst()) { problem($0) }
                } else {
                    Button(ConfigurationCopy.moreProblems(problems.count - 1)) { showsAllProblems = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("configurationEditor.moreProblems")
                }
            }
            Text(ConfigurationCopy.editUnchanged).foregroundStyle(.secondary)
        }
    }

    /// A located error is a button that moves the cursor there; any other is plain text.
    @ViewBuilder private func problem(_ problem: ConfigurationEditorProblem) -> some View {
        if problem.isLocated {
            Button { model.focus(problem) } label: {
                ProblemText(message: problem.text, textStyle: .footnote, color: .tintColor)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(problem.text))
            .accessibilityHint(ConfigurationCopy.editErrorHint)
            .accessibilityIdentifier("configurationEditor.problem.\(problem.id)")
        } else {
            ProblemText(message: problem.text, textStyle: .footnote, color: .label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(problem.text))
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("configurationEditor.problem.\(problem.id)")
        }
    }
}

/// A checker message without system-inserted hyphens (design rev. 4): a
/// hyphen inside "explore_grid_density" reads as a different name. SwiftUI
/// Text can't turn hyphenation off, so a UILabel draws it with
/// `hyphenationFactor` 0, and field paths may break after "." through a
/// U+200B added for display only. Callers give VoiceOver the unchanged
/// message; the message itself is never changed.
struct ProblemText: UIViewRepresentable {
    let message: String
    var textStyle: UIFont.TextStyle
    var color: UIColor
    /// A part of the message drawn monospaced (a field name).
    var monospaced: Range<String.Index>? = nil

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontForContentSizeCategory = false
        label.isUserInteractionEnabled = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(context.environment.dynamicTypeSize))
        label.attributedText = Self.display(message, monospaced: monospaced, textStyle: textStyle, color: color, traits: traits)
        label.accessibilityLabel = message
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 10_000
        label.preferredMaxLayoutWidth = width
        let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width == nil ? ceil(size.width) : width, height: ceil(size.height))
    }

    static func display(_ message: String, monospaced: Range<String.Index>?, textStyle: UIFont.TextStyle,
                        color: UIColor, traits: UITraitCollection) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.hyphenationFactor = 0
        paragraph.usesDefaultHyphenation = false
        paragraph.lineBreakMode = .byWordWrapping
        let font = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
        let mono = font.fontDescriptor.withDesign(.monospaced).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
        let output = NSMutableAttributedString()
        func add(_ part: Substring, _ font: UIFont) {
            output.append(NSAttributedString(string: breakingAfterDots(part), attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]))
        }
        if let monospaced {
            add(message[..<monospaced.lowerBound], font)
            add(message[monospaced], mono)
            add(message[monospaced.upperBound...], font)
        } else {
            add(message[...], font)
        }
        return output
    }

    /// U+200B after each "." inside a word ("settings.browse.x"), never
    /// after a sentence's full stop: a place to wrap, for display only.
    static func breakingAfterDots(_ text: Substring) -> String {
        var output = ""
        var scalars = text.unicodeScalars[...]
        while let scalar = scalars.popFirst() {
            output.unicodeScalars.append(scalar)
            if scalar == ".", let next = scalars.first, !next.properties.isWhitespace { output.unicodeScalars.append("\u{200B}") }
        }
        return output
    }
}

private extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}

private struct StatusHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// UITextView, because SwiftUI's TextEditor can't turn smart quotes off,
/// and `"` → `”` would break the file (design §2).
struct ConfigurationTextView: UIViewRepresentable {
    @Binding var text: String
    var cursor: ConfigurationEditorModel.CursorRequest?
    var hidesKeyboard = false

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.backgroundColor = .systemBackground
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        view.textContainer.lineFragmentPadding = 16
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.inlinePredictionType = .no
        view.dataDetectorTypes = []
        view.allowsEditingTextAttributes = false
        view.keyboardType = .default
        view.keyboardDismissMode = .interactive
        view.isFindInteractionEnabled = true
        view.alwaysBounceVertical = true
        view.accessibilityLabel = ConfigurationCopy.editTextLabel
        view.accessibilityIdentifier = "configurationEditor.text"
        view.delegate = context.coordinator
        view.text = text
        // The cursor at the start, no keyboard: the helper is read first.
        view.selectedRange = NSRange(location: 0, length: 0)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
        if hidesKeyboard, view.isFirstResponder { view.resignFirstResponder() }
        if let cursor, cursor != context.coordinator.lastCursor {
            context.coordinator.lastCursor = cursor
            let range = NSRange(location: min(cursor.offset, (view.text as NSString).length), length: 0)
            view.becomeFirstResponder()
            view.selectedRange = range
            // After the keyboard has resized the view.
            DispatchQueue.main.async { view.scrollRangeToVisible(range) }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var lastCursor: ConfigurationEditorModel.CursorRequest?

        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
