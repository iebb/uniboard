import SwiftUI

/// A selected key's layers, one row each: its swipe-up, hold and swipe-down
/// choices as they show on the key. A row opens that layer's editor.
struct KeyLayersPanel<Destination: View>: View {
    var layers: [KeyboardKeySettings.Gesture] = [.swipeUp, .longPress, .swipeDown]
    /// A layer's choices, and whether they are the built-in defaults.
    let choices: (KeyboardKeySettings.Gesture) -> (values: [String], isDefault: Bool)
    let destination: (KeyboardKeySettings.Gesture) -> Destination

    var body: some View {
        VStack(spacing: 8) {
            ForEach(layers, id: \.rawValue) { gesture in
                let layer = choices(gesture)
                NavigationLink { destination(gesture) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: gesture == .tap ? "character.cursor.ibeam" : gesture.icon)
                            .font(.body.weight(.semibold)).foregroundStyle(.tint).frame(width: 24)
                        if layer.values.isEmpty {
                            Text("Off").foregroundStyle(.secondary)
                        } else {
                            // An overlay never widens the row, however many choices there are.
                            Color.clear.frame(maxWidth: .infinity, minHeight: 34)
                                .overlay(alignment: .leading) {
                                    HStack(spacing: 6) {
                                        ForEach(Array(layer.values.prefix(16).enumerated()), id: \.offset) { _, value in
                                            Text(symbolKeyPreview(value)).font(.system(size: 20)).lineLimit(1)
                                                .frame(minWidth: 30, minHeight: 34).padding(.horizontal, 2)
                                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        }
                                    }
                                    .foregroundStyle(layer.isDefault ? .secondary : .primary)
                                    .fixedSize()
                                }
                                .clipped()
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 52)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(gesture == .tap ? "Key" : gesture.title)
                .accessibilityValue(Self.summary(layer.values))
                .accessibilityIdentifier("layers.\(gesture.rawValue)")
            }
        }
    }

    /// Choices joined as they show on a key.
    static func summary(_ choices: [String]) -> String {
        choices.isEmpty ? "Off" : choices.map(symbolKeyPreview).joined(separator: " ")
    }
}

/// One layer's choices in order: type them, pick them from Unicode, swipe to
/// remove, or drag to reorder. No choices turn the layer off.
struct KeyLayerEditor: View {
    private struct Choice: Identifiable { let id = UUID(); var text: String }
    let title: String
    var maximum = SymbolBoardStore.maximumVariants
    let save: ([String]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [Choice]
    @State private var showsUnicodePicker = false
    @State private var addedChoice: UUID?
    @State private var failed = false

    init(title: String, choices: [String], maximum: Int = SymbolBoardStore.maximumVariants, save: @escaping ([String]) -> Bool) {
        self.title = title
        self.maximum = maximum
        self.save = save
        _choices = State(initialValue: choices.map { Choice(text: $0) })
    }

    var body: some View {
        List {
            Section {
                ForEach($choices) { $choice in
                    AppSearchField(text: $choice.text, placeholder: "Character or sequence",
                                   identifier: "layer.choice.\(choices.firstIndex(where: { $0.id == choice.id }) ?? 0)",
                                   textStyle: .title2, focusOnAppear: choice.id == addedChoice)
                        .padding(.vertical, 4)
                }
                .onDelete { choices.remove(atOffsets: $0) }
                .onMove { choices.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    let choice = Choice(text: "")
                    addedChoice = choice.id
                    choices.append(choice)
                } label: { Label("Add Choice", systemImage: "plus") }
                    .disabled(choices.count >= maximum)
                    .accessibilityIdentifier("layer.addChoice")
                Button { showsUnicodePicker = true } label: { Label("Choose from Unicode", systemImage: "character.book.closed") }
                    .disabled(choices.count >= maximum)
                    .accessibilityIdentifier("layer.chooseUnicode")
            }
            if failed {
                Text("These choices could not be saved.").foregroundStyle(.red).accessibilityIdentifier("layer.error")
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    // End editing first so the field publishes its last keystroke.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    Task { @MainActor in
                        await Task.yield()
                        if save(choices.map(\.text).filter { !$0.isEmpty }) { dismiss() } else { failed = true }
                    }
                }
                .accessibilityIdentifier("layer.save")
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
        .sheet(isPresented: $showsUnicodePicker) {
            KeyboardKeyUnicodePicker { text in
                guard choices.count < maximum else { return }
                if let empty = choices.firstIndex(where: { $0.text.isEmpty }) { choices[empty].text = text }
                else { choices.append(Choice(text: text)) }
            }
        }
    }
}
