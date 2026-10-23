import SwiftUI

/// A selected key's layers, one row each: its swipe-up, hold and swipe-down
/// choices as they show on the key. Tapping a row opens that layer's editor;
/// holding a choice drags it to another place, in its row or another one.
struct KeyLayersPanel<Destination: View>: View {
    typealias Gesture = KeyboardKeySettings.Gesture
    var layers: [Gesture] = [.swipeUp, .longPress, .swipeDown]
    /// A layer's choices, and whether they are the built-in defaults.
    let choices: (Gesture) -> (values: [String], isDefault: Bool)
    let destination: (Gesture) -> Destination
    /// Saves the layers a drag changed, as one change.
    var save: (([Gesture: [String]]) -> Bool)? = nil
    @State private var editing: Gesture?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(layers, id: \.rawValue) { gesture in row(gesture) }
        }
        .navigationDestination(item: $editing) { destination($0) }
    }

    private func row(_ gesture: Gesture) -> some View {
        let layer = choices(gesture)
        // The key's own output is one value, so it does not drag.
        let drags = save != nil && gesture != .tap
        return HStack(spacing: 10) {
            Image(systemName: gesture == .tap ? "character.cursor.ibeam" : gesture.icon)
                .font(.body.weight(.semibold)).foregroundStyle(.tint).frame(width: 24)
            if layer.values.isEmpty {
                Text("Off").foregroundStyle(.secondary)
            } else {
                // An overlay never widens the row, however many choices there are.
                Color.clear.frame(maxWidth: .infinity, minHeight: 34)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 6) {
                            ForEach(Array(layer.values.prefix(16).enumerated()), id: \.offset) { index, value in
                                chip(value, isDefault: layer.isDefault)
                                    .modifier(ChoiceDrag(payload: "\(gesture.rawValue)|\(index)", enabled: drags) { move($0, to: gesture, at: index) })
                            }
                        }
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
        .onTapGesture { editing = gesture }
        // Dropping on the row, past its choices, puts a choice at its end.
        .dropDestination(for: String.self) { items, _ in drags && items.first.map { move($0, to: gesture, at: nil) } == true }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(gesture == .tap ? "Key" : gesture.title)
        .accessibilityValue(Self.summary(layer.values))
        .accessibilityAction { editing = gesture }
        .accessibilityIdentifier("layers.\(gesture.rawValue)")
    }

    private func chip(_ value: String, isDefault: Bool) -> some View {
        Text(symbolKeyPreview(value)).font(.system(size: 20)).lineLimit(1)
            .foregroundStyle(isDefault ? .secondary : .primary)
            .frame(minWidth: 30, minHeight: 34).padding(.horizontal, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Moves the dragged choice before `index` in `target`, or to its end.
    private func move(_ payload: String, to target: Gesture, at index: Int?) -> Bool {
        let parts = payload.split(separator: "|")
        guard let save, parts.count == 2, let source = Gesture(rawValue: String(parts[0])), let from = Int(parts[1]),
              layers.contains(source), source != .tap, target != .tap else { return false }
        var lists = Dictionary(uniqueKeysWithValues: layers.filter { $0 != .tap }.map { ($0, choices($0).values) })
        guard var sourceList = lists[source], sourceList.indices.contains(from) else { return false }
        let value = sourceList.remove(at: from)
        lists[source] = sourceList
        var targetList = lists[target] ?? []
        // Within one row, removing the choice shifts the places after it.
        let place = index.map { source == target && $0 > from ? $0 - 1 : $0 } ?? targetList.count
        guard source == target || !targetList.contains(value) else { return false }
        targetList.insert(value, at: min(place, targetList.count))
        lists[target] = targetList
        return save(lists.filter { $0.key == source || $0.key == target })
    }

    /// Choices joined as they show on a key.
    static func summary(_ choices: [String]) -> String {
        choices.isEmpty ? "Off" : choices.map(symbolKeyPreview).joined(separator: " ")
    }
}

/// Holding a choice drags it; dropping one on another puts it before it.
private struct ChoiceDrag: ViewModifier {
    let payload: String
    let enabled: Bool
    let drop: (String) -> Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(payload) { content.padding(4) }
                .dropDestination(for: String.self) { items, _ in items.first.map(drop) ?? false }
        } else {
            content
        }
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

    /// One value, such as the key itself, is edited in place rather than listed.
    private var single: Bool { maximum == 1 }

    init(title: String, choices: [String], maximum: Int = SymbolBoardStore.maximumVariants, save: @escaping ([String]) -> Bool) {
        self.title = title
        self.maximum = maximum
        self.save = save
        _choices = State(initialValue: (maximum == 1 && choices.isEmpty ? [""] : choices).map { Choice(text: $0) })
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
                .onDelete { if !single { choices.remove(atOffsets: $0) } }
                .onMove { if !single { choices.move(fromOffsets: $0, toOffset: $1) } }
                if !single {
                    Button {
                        let choice = Choice(text: "")
                        addedChoice = choice.id
                        choices.append(choice)
                    } label: { Label("Add Choice", systemImage: "plus") }
                        .disabled(choices.count >= maximum)
                        .accessibilityIdentifier("layer.addChoice")
                }
                Button { showsUnicodePicker = true } label: { Label("Choose from Unicode", systemImage: "character.book.closed") }
                    .disabled(!single && choices.count >= maximum)
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
            if !single { ToolbarItem(placement: .bottomBar) { EditButton() } }
        }
        .sheet(isPresented: $showsUnicodePicker) {
            KeyboardKeyUnicodePicker { text in
                // One value is replaced; a list gains the choice.
                if single { choices = [Choice(text: text)]; return }
                guard choices.count < maximum else { return }
                if let empty = choices.firstIndex(where: { $0.text.isEmpty }) { choices[empty].text = text }
                else { choices.append(Choice(text: text)) }
            }
        }
    }
}
