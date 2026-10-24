import SwiftUI
import UIKit

/// Add Rule / Edit Rule. Fields hold what was typed; Save stays disabled
/// until the draft is a valid, non-duplicate rule with a font, and saving
/// goes through FontRuleStore. Nothing here turns Extra Unicode Fonts on.
struct FontRuleEditorView: View {
    @EnvironmentObject private var catalog: CatalogPreferences
    @ObservedObject private var rules = FontRulePreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FontRuleDraft
    @State private var original: FontRuleDraft
    @State private var confirmsDiscard = false
    @State private var coverage: Int?
    @State private var coverageChecked = false

    init(draft: FontRuleDraft) {
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
    }

    private var blocks: [UnicodeBlock] { UnicodeCatalog.shared.blocks }
    private var isEditing: Bool { draft.editingID != nil }
    private var hasChanges: Bool { draft != original }
    private var result: Result<FontRuleSelector, FontRuleDraft.Problem>? { draft.selector(blocks: blocks) }

    private var selector: FontRuleSelector? {
        guard case let .success(selector)? = result else { return nil }
        return selector
    }

    private var duplicate: FontRule? { selector.flatMap { draft.duplicate(of: $0, in: rules.rules) } }
    private var savable: FontRule? { draft.rule(in: rules.rules, blocks: blocks) }

    var body: some View {
        NavigationStack {
            Form {
                appliesTo
                fontSection
                if isEditing, let id = draft.editingID {
                    Section {
                        Button(role: .destructive) {
                            guard rules.remove(id: id) else { return }
                            UIAccessibility.post(notification: .announcement, argument: "Rule removed")
                            dismiss()
                        } label: {
                            Text("Remove Rule").frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("fontRuleEditor.remove")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Rule" : "Add Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmsDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("fontRuleEditor.cancel")
                    .confirmationDialog("Discard Changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                            .accessibilityIdentifier("fontRuleEditor.discard")
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(savable == nil)
                        .accessibilityIdentifier("fontRuleEditor.save")
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .task(id: coverageKey) { await checkCoverage() }
        }
    }

    private func save() {
        guard let rule = savable, rules.save(draft.applied(rule, to: rules.rules)) else { return }
        dismiss()
    }

    // MARK: Applies To

    private var appliesTo: some View {
        Section {
            if !isEditing {
                Picker("Applies To", selection: $draft.kind) {
                    Text("Code Point").tag(FontRuleKind.codePoint)
                    Text("Range").tag(FontRuleKind.range)
                    Text("Unicode Block").tag(FontRuleKind.block)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("fontRuleEditor.kind")
            }
            switch draft.kind {
            case .codePoint: codePointFields
            case .range: rangeFields
            case .block: blockFields
            }
        } header: {
            Text("Applies To")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if draft.kind == .range { Text("Includes both endpoints.") }
                if case let .failure(problem)? = result {
                    errorText(FontRuleCopy.message(problem), identifier: "fontRuleEditor.error")
                }
                if let duplicate {
                    HStack(alignment: .firstTextBaseline) {
                        errorText(FontRuleCopy.duplicate(draft.kind), identifier: "fontRuleEditor.duplicate")
                        Button("Edit Rule") { switchTo(duplicate) }
                            .buttonStyle(.borderless)
                            .font(.footnote)
                            .accessibilityIdentifier("fontRuleEditor.duplicate.edit")
                    }
                }
                if let overridden = overriddenCount, overridden > 0 {
                    Text(FontRuleCopy.overridden(overridden))
                        .accessibilityIdentifier("fontRuleEditor.overridden")
                }
            }
        }
    }

    private func errorText(_ text: String, identifier: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
            .font(.footnote)
            .accessibilityIdentifier(identifier)
    }

    private func switchTo(_ rule: FontRule) {
        let next = FontRuleDraft(editing: rule)
        draft = next
        original = next
    }

    /// Edit Rule: how many of this rule's code points a higher-priority rule takes.
    private var overriddenCount: Int? {
        guard isEditing, let selector, let face = draft.face, let id = draft.editingID else { return nil }
        let applied = draft.applied(FontRule(id: id, selector: selector, face: face), to: rules.rules)
        guard let index = applied.firstIndex(where: { $0.id == id }) else { return nil }
        return FontRuleSet(rules: applied).overriddenScalarCount(for: index)
    }

    @ViewBuilder private var codePointFields: some View {
        TextField("U+0041 or a character", text: $draft.codePoint)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityLabel("Code Point")
            .accessibilityIdentifier("fontRuleEditor.codePoint")
        if case let .codePoint(value)? = selector, let character = catalog.catalog.character(at: value) {
            HStack(spacing: 12) {
                FontRuleTile(text: character.displayText, font: draft.face.flatMap { rules.font($0, size: 28) })
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                    Text(character.codePointLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fontRuleEditor.summary")
        }
    }

    @ViewBuilder private var rangeFields: some View {
        endpoint("From", text: $draft.from, identifier: "fontRuleEditor.from")
        endpoint("To", text: $draft.to, identifier: "fontRuleEditor.to")
        if case let .range(first, last)? = selector {
            VStack(alignment: .leading, spacing: 2) {
                Text(FontRuleCopy.range(first, last)).font(.body.monospaced())
                Text(FontRuleCopy.codePoints(FontRuleScalar.validCount(first, last))).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fontRuleEditor.summary")
        }
    }

    private func endpoint(_ title: String, text: Binding<String>, identifier: String) -> some View {
        LabeledContent(title) {
            TextField("U+0000", text: text)
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private var blockFields: some View {
        NavigationLink {
            FontRuleBlockPicker(selection: $draft.block)
        } label: {
            LabeledContent("Unicode block") {
                if let block = draft.block {
                    Text(block.name)
                } else {
                    Text("Choose").foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityIdentifier("fontRuleEditor.block")
    }

    // MARK: Font

    private var fontSection: some View {
        Section {
            NavigationLink {
                if let selector {
                    FontRulePickerView(selector: selector, selection: draft.face) { draft.face = $0 }
                }
            } label: {
                LabeledContent("Preferred font") {
                    if let face = draft.face {
                        Text(face.displayName)
                    } else {
                        Text("Choose").foregroundStyle(selector == nil ? Color.secondary : Color.accentColor)
                    }
                }
            }
            .disabled(selector == nil)
            .accessibilityIdentifier("fontRuleEditor.font")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if selector != nil, draft.face == nil {
                    errorText(FontRuleCopy.chooseFont, identifier: "fontRuleEditor.chooseFont")
                }
                if let face = draft.face, !rules.isAvailable(face) {
                    Label(FontRuleCopy.unavailable, systemImage: "exclamationmark.triangle.fill")
                        .accessibilityIdentifier("fontRuleEditor.unavailable")
                }
                if let selector, selector.kind != .codePoint, draft.face != nil {
                    if let coverage {
                        Text(FontRuleCopy.supports(coverage, of: selector.validScalarCount))
                            .accessibilityIdentifier("fontRuleEditor.coverage")
                    } else if !coverageChecked {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    private var coverageKey: String {
        guard let selector, selector.kind != .codePoint, let face = draft.face else { return "" }
        let (first, last) = selector.bounds
        return "\(face.identityKey)|\(first)-\(last)"
    }

    private func checkCoverage() async {
        coverage = nil
        coverageChecked = false
        guard let selector, selector.kind != .codePoint, let face = draft.face else { return }
        let (first, last) = selector.bounds
        let count = try? await FontRangeCoverage.shared.supportedCount(of: face, first: first, last: last, loader: UnicodeFontSupport.ruleFaceLoader)
        guard !Task.isCancelled else { return }
        coverage = count
        coverageChecked = true
    }
}

/// The base Unicode block table (never ConScript), searchable.
struct FontRuleBlockPicker: View {
    @Binding var selection: FontRuleBlock?
    @EnvironmentObject private var catalog: CatalogPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var blocks: [UnicodeBlock] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return UnicodeCatalog.shared.blocks.filter {
            FontRuleScalar.validCount($0.start, $0.end) > 0
                && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.rangeLabel.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List(blocks) { block in
            let chosen = selection?.name == block.name
            Button {
                selection = FontRuleBlock(name: block.name, first: block.start, last: block.end, unicodeVersion: UnicodeCatalog.shared.version)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    FontRuleTile(text: block.symbol, font: nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.name).foregroundStyle(.primary)
                        Text(block.rangeLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if chosen {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .tint(.primary)
            .accessibilityLabel(block.name)
            .accessibilityValue(block.rangeLabel)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityIdentifier("fontRuleBlock.\(block.name)")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Unicode block")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search blocks")
    }
}
