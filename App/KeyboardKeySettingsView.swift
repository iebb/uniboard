import SwiftUI

private extension KeyboardKeySettings.Gesture {
    var title: String {
        switch self { case .longPress: return "Long press"; case .swipeUp: return "Swipe up"; case .swipeDown: return "Swipe down" }
    }
    var icon: String {
        switch self { case .longPress: return "hand.tap"; case .swipeUp: return "arrow.up"; case .swipeDown: return "arrow.down" }
    }
}

struct KeyboardKeySettingsView: View {
    @StateObject private var keys = KeyboardKeyPreferences.shared
    @State private var query = ""
    @State private var resetConfirmation = false
    @State private var selectedKeyID: String?
    private var groups: [(String, KeyboardKeySettings.Kind)] {
        [("Letters", .letter), ("Numbers", .digit), ("Symbols", .character)]
    }
    private func matches(_ descriptor: KeyboardKeySettings.Descriptor) -> Bool {
        query.isEmpty || descriptor.title.localizedCaseInsensitiveContains(query)
            || descriptor.id.localizedCaseInsensitiveContains(query)
    }
    var body: some View {
        List {
            if let error = keys.saveError {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("keySettings.saveError") }
            }
            Section {
                Text("Choose a letter, number or symbol key to change its long press, swipe up and swipe down choices. After swiping, slide left or right to select a choice, then lift to insert.")
                Text("Ordinary taps keep their usual behavior. Custom choices are inserted exactly as saved, regardless of Shift.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.0) { title, kind in
                let descriptors = KeyboardKeySettings.descriptors.filter { $0.kind == kind && matches($0) }
                if !descriptors.isEmpty {
                    Section(title) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 8)], spacing: 8) {
                            ForEach(descriptors) { descriptor in
                                Button { selectedKeyID = descriptor.id } label: {
                                    VStack(spacing: 4) {
                                        Text(descriptor.title).font(.title3)
                                        Circle().fill(keys.snapshot.overrides[descriptor.id] == nil ? Color.clear : Palette.accent)
                                            .frame(width: 4, height: 4)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 0.5))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Configure \(descriptor.title) key")
                                .accessibilityValue(keys.snapshot.overrides[descriptor.id] == nil ? "Default" : "Customized")
                                .accessibilityIdentifier("keySettings.key.\(descriptor.id)")
                            }
                        }.listRowBackground(Palette.soft)
                    }
                }
            }
            Section {
                Button("Restore all key defaults", role: .destructive) { resetConfirmation = true }
                    .disabled(keys.snapshot.overrides.isEmpty && keys.saveError == nil)
                    .accessibilityIdentifier("keySettings.resetAll")
            } footer: {
                Text("Only letters, numbers and symbols are configurable. Space, Shift, Backspace, Return and other function keys retain their standard behavior, as do search typing and the iOS globe key. Saved choices stay on this device; Full Access is not required.")
            }
        }
        .navigationTitle("Keyboard keys").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedKeyID) { keyID in
            if let descriptor = KeyboardKeySettings.descriptor(for: keyID) {
                KeyboardSingleKeySettingsView(descriptor: descriptor, keys: keys)
            }
        }
        .searchable(text: $query, prompt: "Find a key")
        .onAppear { keys.refresh() }
        .confirmationDialog("Restore every key’s default gestures?", isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button("Restore all defaults", role: .destructive) { keys.resetAll() }
        } message: { Text("Your symbol boards and favorites are kept.") }
    }
}

private struct KeyboardSingleKeySettingsView: View {
    let descriptor: KeyboardKeySettings.Descriptor
    @ObservedObject var keys: KeyboardKeyPreferences
    @State private var resetConfirmation = false
    var body: some View {
        List {
            Section {
                ForEach(KeyboardKeySettings.Gesture.allCases, id: \.rawValue) { gesture in
                    NavigationLink {
                        KeyboardGestureSettingsView(descriptor: descriptor, gesture: gesture, keys: keys,
                            current: keys.snapshot.candidates(for: descriptor.id, gesture: gesture))
                    } label: {
                        HStack {
                            Label(gesture.title, systemImage: gesture.icon)
                            Spacer()
                            Text(summary(keys.snapshot.candidates(for: descriptor.id, gesture: gesture)))
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.accessibilityIdentifier("keySettings.gesture.\(gesture.rawValue)")
                        .accessibilityValue(summary(keys.snapshot.candidates(for: descriptor.id, gesture: gesture)))
                }
            } footer: {
                Text("The first choice is selected when a gesture opens. Slide left or right before lifting to choose another.")
            }
            Section {
                Button("Restore this key’s defaults", role: .destructive) { resetConfirmation = true }
                    .disabled(keys.snapshot.overrides[descriptor.id] == nil)
                    .accessibilityIdentifier("keySettings.resetKey")
                if let error = keys.saveError { Text(error).foregroundStyle(.red).accessibilityIdentifier("keySettings.saveError") }
            }
        }
        .navigationTitle(descriptor.title + " key").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("keySettings.detail.\(descriptor.id)")
        .onAppear { keys.refresh() }
        .confirmationDialog("Restore this key’s default gestures?", isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button("Restore defaults", role: .destructive) { keys.reset(keyID: descriptor.id) }
        }
    }
    private func summary(_ values: [String]?) -> String {
        guard let values else { return "Default" }
        return values.isEmpty ? "Off" : values.map(keyChoicePreview).joined(separator: "  ")
    }
}

private struct KeyboardGestureSettingsView: View {
    private enum Mode: String, CaseIterable { case system = "Default", disabled = "Off", custom = "Custom" }
    private struct Choice: Identifiable { let id = UUID(); var text: String }
    let descriptor: KeyboardKeySettings.Descriptor
    let gesture: KeyboardKeySettings.Gesture
    @ObservedObject var keys: KeyboardKeyPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var original: [String]?
    @State private var mode: Mode
    @State private var choices: [Choice]
    @State private var showsUnicodePicker = false
    @State private var saveAttempted = false
    @State private var saveAlert = false

    init(descriptor: KeyboardKeySettings.Descriptor, gesture: KeyboardKeySettings.Gesture,
         keys: KeyboardKeyPreferences, current: [String]?) {
        self.descriptor = descriptor; self.gesture = gesture; self.keys = keys
        _original = State(initialValue: current)
        _mode = State(initialValue: current.map { $0.isEmpty ? .disabled : .custom } ?? .system)
        _choices = State(initialValue: (current ?? []).map { Choice(text: $0) })
    }
    private var candidates: [String]? {
        switch mode { case .system: return nil; case .disabled: return []; case .custom: return choices.map(\.text) }
    }
    private var valid: Bool {
        if mode == .custom && choices.isEmpty { return false }
        return KeyboardKeySettings.Snapshot.defaults.updating(candidates, for: descriptor.id, gesture: gesture) != nil
    }
    var body: some View {
        List {
            Section {
                Picker("Behavior", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("keySettings.behavior")
                if mode == .system {
                    Text("Use Uniboard’s built-in behavior for this gesture.").foregroundStyle(.secondary)
                    if gesture == .swipeUp && descriptor.kind == .letter {
                        Text("Selects the opposite case first, followed by its accented choices. The keyboard’s Shift state stays unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if mode == .disabled {
                    Text("This gesture is disabled. An ordinary tap still works.").foregroundStyle(.secondary)
                }
            }
            if mode == .custom {
                Section {
                    ForEach($choices) { $choice in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Character or sequence", text: $choice.text, axis: .vertical)
                                .font(.title2).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .lineLimit(1...3)
                                .accessibilityIdentifier("keySettings.choice.\(choices.firstIndex(where: { $0.id == choice.id }) ?? 0)")
                            Text(codePoints(choice.text)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                    .onDelete { choices.remove(atOffsets: $0) }
                    .onMove { choices.move(fromOffsets: $0, toOffset: $1) }
                    Button { choices.append(Choice(text: "")) } label: { Label("Add choice", systemImage: "plus") }
                        .disabled(choices.count >= KeyboardVariantPolicy.maximumVariants)
                        .accessibilityIdentifier("keySettings.addChoice")
                    Button { showsUnicodePicker = true } label: { Label("Choose from Unicode", systemImage: "character.book.closed") }
                        .disabled(choices.count >= KeyboardVariantPolicy.maximumVariants)
                        .accessibilityIdentifier("keySettings.chooseUnicode")
                } header: { Text("Choices in selection order") } footer: {
                    Text("Up to 16 different choices, each up to 64 Unicode scalars. Paste a whole emoji or combining sequence into one choice. Swipe a row to remove it; use Edit to reorder.")
                }
                if !valid { Text("Choices must be nonempty and cannot repeat exactly. Check the 16-choice and 64-scalar limits.").font(.caption).foregroundStyle(.red) }
            }
            if saveAttempted, let error = keys.saveError {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("keySettings.saveError")
            }
        }
        .navigationTitle(gesture.title + " · " + descriptor.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveAttempted = true
                    if keys.save(candidates, keyID: descriptor.id, gesture: gesture, replacing: original) { dismiss() }
                    else { saveAlert = true }
                }.disabled(!valid).accessibilityIdentifier("keySettings.save")
            }
            ToolbarItem(placement: .bottomBar) { if mode == .custom { EditButton() } }
        }
        .onChange(of: mode) { _, value in if value == .custom && choices.isEmpty { choices.append(Choice(text: "")) } }
        .alert("Couldn’t save key", isPresented: $saveAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(keys.saveError ?? "Please try again.") }
        .sheet(isPresented: $showsUnicodePicker) {
            KeyboardKeyUnicodePicker { text in
                guard choices.count < KeyboardVariantPolicy.maximumVariants else { return }
                if choices.count == 1 && choices[0].text.isEmpty { choices[0].text = text }
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

private struct KeyboardKeyUnicodePicker: View {
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var query = ""
    @StateObject private var search = CatalogSearch()
    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search a name, description, block or code point. You can also paste a complete sequence in the choice editor.")
                        .foregroundStyle(.secondary)
                } else if search.searching { ProgressView() }
                else if search.results.isEmpty { Text("No characters found").foregroundStyle(.secondary) }
                ForEach(search.results) { character in
                    Button { select(character.text); dismiss() } label: {
                        HStack(spacing: 14) {
                            Text(character.displayText)
                                .font(Font(UnicodeFontSupport.font(for: character.displayText, size: 28, enabled: preferences.useUnicodeFonts)))
                                .frame(width: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.name.capitalized).foregroundStyle(Palette.ink)
                                Text(character.codePointLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose a character").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Name, block or U+ code point")
            .onChange(of: query) { _, value in search.update(value, catalog: preferences.catalog, order: .codePoint, limit: 120) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private func keyChoicePreview(_ text: String) -> String {
    if text == " " { return "␣" }
    if text == "\n" { return "↵" }
    if text == "\t" { return "⇥" }
    return String(text.prefix(4))
}
