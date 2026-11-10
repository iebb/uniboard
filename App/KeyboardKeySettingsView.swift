import SwiftUI

extension KeyboardKeySettings.Gesture {
    var title: String {
        switch self { case .tap: return "Tap"; case .shiftedTap: return "Shifted tap"; case .longPress: return "Long press"; case .swipeUp: return "Swipe up"; case .swipeDown: return "Swipe down" }
    }
    var icon: String {
        switch self { case .tap: return "hand.point.up"; case .shiftedTap: return "shift"; case .longPress: return "hand.tap"; case .swipeUp: return "arrow.up"; case .swipeDown: return "arrow.down" }
    }
}

/// One layer of a letter, digit or symbol key, opened from Main Keyboard's
/// layers panel: its choices in selection order, defaults or a fixed list.
struct KeyboardGestureSettingsView: View {
    private struct Choice: Identifiable { let id = UUID(); var text: String }
    let descriptor: KeyboardKeySettings.Descriptor
    let gesture: KeyboardKeySettings.Gesture
    let alphabet: KeyboardAlphabet
    @ObservedObject var keys: KeyboardKeyPreferences
    @EnvironmentObject private var preferences: CatalogPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var original: [String]?
    @State private var choices: [Choice]
    /// True while the list shows the built-in candidates, which follow case
    /// and layout while typing. Any edit makes the list a fixed custom set.
    @State private var usesDefaults: Bool
    @State private var showsUnicodePicker = false
    @State private var saveAttempted = false
    @State private var saveAlert = false
    /// The row Add Choice just created, which takes focus as it appears.
    @State private var addedChoice: UUID?

    init(descriptor: KeyboardKeySettings.Descriptor, gesture: KeyboardKeySettings.Gesture, alphabet: KeyboardAlphabet,
         keys: KeyboardKeyPreferences, current: [String]?) {
        self.descriptor = descriptor; self.gesture = gesture; self.alphabet = alphabet; self.keys = keys
        _original = State(initialValue: current)
        _usesDefaults = State(initialValue: current == nil)
        _choices = State(initialValue: (current ?? []).map { Choice(text: $0) })
    }
    private var defaults: [String] {
        KeyboardVariantPolicy.defaultCandidates(for: descriptor.id, gesture: gesture, alphabet: alphabet)
    }
    private var candidates: [String]? {
        usesDefaults ? nil : choices.map(\.text).filter { !$0.isEmpty }
    }
    private var valid: Bool {
        KeyboardKeySettings.Snapshot.defaults.updating(candidates, for: descriptor.id, gesture: gesture) != nil
    }
    /// The script of the layout that has this letter, which decides its defaults.
    private var script: KeyboardAlphabet.Script {
        guard descriptor.kind == .letter, let key = descriptor.text else { return .latin }
        return (alphabet.keys.contains(key) ? alphabet : KeyboardAlphabet.catalog.first { $0.keys.contains(key) })?.script ?? .latin
    }
    private var explanation: String {
        switch gesture {
        case .swipeDown where descriptor.kind == .letter && script == .greek:
            return "By default: mathematical bold, italic, bold italic, sans-serif bold and sans-serif bold italic forms of the same letter in the current case, then double-struck and small capital forms where Unicode has them. Shift stays unchanged."
        case .swipeDown where descriptor.kind == .letter && script == .cyrillic:
            return "By default: related letters from other Cyrillic languages, in the current case. Shift stays unchanged."
        case .swipeDown where descriptor.kind == .letter:
            return "By default: styled forms of the same letter in the current case: mathematical bold, italic, script, fraktur, double-struck, sans-serif and monospace, then circled, parenthesized, fullwidth and small capital. Shift stays unchanged."
        case .swipeDown:
            return "By default: styled forms of the same character, such as mathematical, circled, parenthesized and fullwidth forms, where Unicode has them."
        case .longPress:
            return script == .latin ? "By default: this layout's accents, then familiar accents in the current case, and stock symbol variants."
                : "By default: this layout's accented letters in the current case."
        case .swipeUp:
            return "By default: the superscript, then the subscript form of the same character, where Unicode has them."
        default:
            return ""
        }
    }

    var body: some View {
        List {
            Section {
                ForEach($choices) { $choice in
                    VStack(alignment: .leading, spacing: 6) {
                        // A UIKit field reports every edit; SwiftUI's TextField can miss
                        // the last keystroke on iOS 27 when focus moves straight to Save.
                        AppSearchField(text: $choice.text, placeholder: "Character or sequence",
                                       identifier: "keySettings.choice.\(choices.firstIndex(where: { $0.id == choice.id }) ?? 0)",
                                       textStyle: .title2, focusOnAppear: choice.id == addedChoice)
                        Text(codePoints(choice.text)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
                .onDelete { choices.remove(atOffsets: $0) }
                .onMove { choices.move(fromOffsets: $0, toOffset: $1) }
                if choices.isEmpty {
                    Text("Off. This gesture does nothing; a tap still types the key.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("keySettings.off")
                }
                Button {
                    let choice = Choice(text: "")
                    addedChoice = choice.id
                    choices.append(choice)
                } label: { Label("Add Choice", systemImage: "plus") }
                    .disabled(choices.count >= gesture.maximumChoices)
                    .accessibilityIdentifier("keySettings.addChoice")
                Button { showsUnicodePicker = true } label: { Label("Choose from Unicode", systemImage: "character.book.closed") }
                    .disabled(choices.count >= gesture.maximumChoices)
                    .accessibilityIdentifier("keySettings.chooseUnicode")
            } header: {
                HStack {
                    Text("Choices in Selection Order")
                    Spacer()
                    if usesDefaults { Text("Default").accessibilityIdentifier("keySettings.isDefault") }
                }
            } footer: {
                Text([explanation, "Defaults are shown for lowercase iPhone typing and follow case and layout; once edited, this list is used as is. Swipe a choice to remove it, or remove every choice to turn the gesture off."]
                    .filter { !$0.isEmpty }.joined(separator: " "))
            }
            if !valid {
                Text("Choices must be different, at most 16, and each up to 64 Unicode scalars.")
                    .font(.caption).foregroundStyle(.red)
            }
            Section {
                Button("Reset to Default") {
                    choices = defaults.map { Choice(text: $0) }
                    usesDefaults = true
                }
                .disabled(usesDefaults)
                .accessibilityIdentifier("keySettings.resetGesture")
                Button("Remove All", role: .destructive) { choices = [] }
                    .disabled(choices.isEmpty)
                    .accessibilityIdentifier("keySettings.removeAll")
            }
            if saveAttempted, let error = keys.saveError {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("keySettings.saveError")
            }
        }
        .navigationTitle(gesture.title + " · " + descriptor.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    // A field still being edited publishes its last keystroke
                    // when editing ends, so end it before reading the choices.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    Task { @MainActor in
                        await Task.yield()
                        saveAttempted = true
                        if keys.save(candidates, keyID: descriptor.id, gesture: gesture, replacing: original) { dismiss() }
                        else { saveAlert = true }
                    }
                }.disabled(!valid).accessibilityIdentifier("keySettings.save")
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
        .onAppear { if usesDefaults && choices.isEmpty { choices = defaults.map { Choice(text: $0) } } }
        .onChange(of: choices.map(\.text)) { _, texts in
            if usesDefaults && texts != defaults { usesDefaults = false }
        }
        .alert("Couldn’t save key", isPresented: $saveAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(keys.saveError ?? "Please try again.") }
        .sheet(isPresented: $showsUnicodePicker) {
            KeyboardKeyUnicodePicker { text in
                guard choices.count < gesture.maximumChoices else { return }
                if let empty = choices.firstIndex(where: { $0.text.isEmpty }) { choices[empty].text = text }
                else { choices.append(Choice(text: text)) }
            }
        }
    }
    private func codePoints(_ text: String) -> String {
        if text.isEmpty { return "Empty choice" }
        let prefix = text.unicodeScalars.prefix(65).map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        return text.unicodeScalars.prefix(65).count > 64 ? prefix + " … · Too long" : prefix
    }
}

struct KeyboardKeyUnicodePicker: View {
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var query = ""
    @StateObject private var search = CatalogSearch()
    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search a name, description, block or code point. To use a whole sequence, type or paste it instead.")
                        .foregroundStyle(.secondary)
                } else if search.searching { ProgressView() }
                else if search.results.isEmpty { Text("No characters found").foregroundStyle(.secondary) }
                ForEach(search.results) { character in
                    if let forms = character.presentationForms {
                        // Each presentation is its own choice, so a page can hold both.
                        row(character, text: forms.text, glyph: forms.text, identifier: "picker.text.\(character.codePointLabel)")
                        row(character, text: forms.emoji, glyph: forms.emoji, identifier: "picker.emoji.\(character.codePointLabel)")
                    } else {
                        row(character, text: character.text, glyph: character.displayText, identifier: "picker.\(character.codePointLabel)")
                    }
                }
            }
            .navigationTitle("Choose a character").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Name, block or U+ code point")
            .onChange(of: query) { _, value in search.update(value, catalog: preferences.catalog, limit: 120) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private extension KeyboardKeyUnicodePicker {
    func row(_ character: UnicodeCharacter, text: String, glyph: String, identifier: String) -> some View {
        Button { select(text); dismiss() } label: {
            HStack(spacing: 14) {
                Text(glyph)
                    .font(Font(UnicodeFontSupport.font(for: glyph, size: 28, enabled: preferences.useUnicodeFonts, anchor: character.fontRuleAnchor)))
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name).foregroundStyle(.primary)
                    Text(text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
