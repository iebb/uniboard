import SwiftUI

/// A selected key's three layers, swipe up, hold and swipe down, each
/// opening its list of choices.
struct KeyLayersPanel<Destination: View>: View {
    /// Each layer's choices as shown on the key, or nil for none.
    var layers: [KeyboardKeySettings.Gesture] = [.swipeUp, .longPress, .swipeDown]
    let summary: (KeyboardKeySettings.Gesture) -> String
    let destination: (KeyboardKeySettings.Gesture) -> Destination

    var body: some View {
        HStack(spacing: 8) {
            ForEach(layers, id: \.rawValue) { gesture in
                NavigationLink { destination(gesture) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: gesture == .tap ? "character.cursor.ibeam" : gesture.icon).font(.body)
                        Text(summary(gesture)).font(.caption).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(gesture == .tap ? "Key" : gesture.title)
                .accessibilityValue(summary(gesture))
                .accessibilityIdentifier("layers.\(gesture.rawValue)")
            }
        }
    }

    /// Choices joined as they show on a key.
    static func summary(_ choices: [String]?) -> String {
        guard let choices, !choices.isEmpty else { return "Off" }
        return choices.map(symbolKeyPreview).joined(separator: " ")
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
