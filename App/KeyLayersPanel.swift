import SwiftUI

/// A selected key's layers, one row each: its swipe-up, hold and swipe-down
/// choices as they show on the key. Tapping a row opens that layer's editor;
/// holding a choice drags it to another place, in its row or another one.
/// Hovering only marks where it would go; the drop saves once.
struct KeyLayersPanel<Destination: View>: View {
    typealias Gesture = KeyboardKeySettings.Gesture
    typealias Position = SymbolPageLayout.Position
    var layers: [Gesture] = [.swipeUp, .longPress, .swipeDown]
    /// A layer's choices, and whether they are the built-in defaults.
    let choices: (Gesture) -> (values: [String], isDefault: Bool)
    let destination: (Gesture) -> Destination
    /// Saves the layers a drag changed, as one change.
    var save: (([Gesture: [String]]) -> Bool)? = nil
    @State private var editing: Gesture?
    @StateObject private var drag = EditorDragSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// A parent's `.disabled`, such as while its own drag is under way. The
    /// chips are hosted by UIKit, so it is passed to them explicitly.
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var motion

    /// Each layer's choices, in the order of `layers`.
    private var rows: [[String]] { layers.map { choices($0).values } }
    /// The key's own output is one value, so it neither gives nor takes a choice.
    private var locked: Set<Int> { Set(layers.indices.filter { layers[$0] == .tap }) }
    /// What a drag lifted from; any other choices refuse its drop.
    private var fingerprint: String {
        zip(layers, rows).map { "\($0.rawValue):" + $1.joined(separator: "\u{1F}") }.joined(separator: "\u{1E}")
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(layers, id: \.rawValue) { gesture in row(gesture) }
        }
        .navigationDestination(item: $editing) { destination($0) }
        .onAppear { drag.fit(rowCounts: rows.map(\.count)) }
        .onDisappear { drag.reset() }
        .onChange(of: fingerprint) { _, _ in drag.reset(); drag.fit(rowCounts: rows.map(\.count)) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { drag.reset() } }
    }

    private func open(_ gesture: Gesture) {
        if isEnabled && !drag.isDragging { editing = gesture }
    }

    private func row(_ gesture: Gesture) -> some View {
        let layer = choices(gesture)
        let drags = save != nil && gesture != .tap
        let row = layers.firstIndex(of: gesture) ?? 0
        let end = Position(row: row, index: layer.values.count)
        return HStack(spacing: 10) {
            Image(systemName: gesture == .tap ? "character.cursor.ibeam" : gesture.icon)
                .font(.body.weight(.semibold)).foregroundStyle(.tint).frame(width: 24)
            if layer.values.isEmpty {
                // An empty layer takes a choice; Off stays until the drop.
                target(end, enabled: drags, gesture: gesture) { Text("Off").foregroundStyle(.secondary).frame(minHeight: 34) }
            } else {
                // An overlay never widens the row, however many choices there are.
                Color.clear.frame(maxWidth: .infinity, minHeight: 34)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 6) {
                            ForEach(layer.values.prefix(16).indices.map {
                                EditorTilePosition(id: drag.tileID(Position(row: row, index: $0)), position: Position(row: row, index: $0))
                            }) { entry in
                                choice(entry.position, value: layer.values[entry.position.index], isDefault: layer.isDefault,
                                       draggable: drags, gesture: gesture)
                                    .matchedGeometryEffect(id: entry.id, in: motion)
                            }
                            // Dropping past the last choice puts a choice at the end.
                            target(end, enabled: drags, gesture: gesture) {
                                Color.clear.frame(width: 12, height: 34).contentShape(Rectangle())
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
        .onTapGesture { open(gesture) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(gesture == .tap ? "Key" : gesture.title)
        .accessibilityValue(Self.summary(layer.values))
        .accessibilityAction { open(gesture) }
        .accessibilityIdentifier("layers.\(gesture.rawValue)")
    }

    private func choice(_ position: Position, value: String, isDefault: Bool, draggable: Bool, gesture: Gesture) -> some View {
        let active = drag.source == position
        let current = rows, fixed = locked
        // The row speaks for its choices, so the hosted chips stay out of VoiceOver.
        return EditorDragSurface(session: drag, position: position, fingerprint: fingerprint, currentFingerprint: { fingerprint },
                                 draggable: draggable, isEnabled: isEnabled, hidesAccessibility: true, cornerRadius: 6,
                                 accepts: { draggable && Self.move(current, locked: fixed, from: $0, to: position) != nil },
                                 commit: { drop($0, at: position) }) {
            chip(value, isDefault: isDefault).contentShape(Rectangle()).onTapGesture { open(gesture) }
        }
        .opacity(active ? 0.35 : 1)
        .animation(.editorFade(0.12, reduceMotion: reduceMotion), value: active)
        // Centred in the 6 pt gap before the choice; inside the row at its start.
        .overlay(alignment: .leading) { indicator(position, offset: position.index == 0 ? 0 : -5) }
    }

    private func target<Content: View>(_ position: Position, enabled: Bool, gesture: Gesture,
                                       @ViewBuilder content: @escaping () -> Content) -> some View {
        let current = rows, fixed = locked
        return EditorDragSurface(session: drag, position: position, fingerprint: fingerprint, currentFingerprint: { fingerprint },
                                 draggable: false, isEnabled: isEnabled, hidesAccessibility: true, cornerRadius: 6,
                                 accepts: { enabled && Self.move(current, locked: fixed, from: $0, to: position) != nil },
                                 commit: { drop($0, at: position) }) {
            content().onTapGesture { open(gesture) }
        }
        .overlay(alignment: .leading) { indicator(position, offset: position.index == 0 ? 0 : -5) }
    }

    private func indicator(_ position: Position, offset: CGFloat) -> some View {
        EditorInsertionMark(height: 30).offset(x: offset)
            .opacity(drag.target == position ? 1 : 0)
            .animation(.editorFade(0.08, reduceMotion: reduceMotion), value: drag.target == position)
    }

    private func chip(_ value: String, isDefault: Bool) -> some View {
        Text(symbolKeyPreview(value)).font(.system(size: 20)).lineLimit(1)
            .foregroundStyle(isDefault ? .secondary : .primary)
            .frame(minWidth: 30, minHeight: 34).padding(.horizontal, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private static func move(_ rows: [[String]], locked: Set<Int>, from source: Position, to destination: Position) -> EditorReorder.Move<[[String]]>? {
        EditorReorder.choices(rows, from: source, to: destination, locked: locked, maximum: SymbolBoardStore.maximumVariants)
    }

    /// A drop: computed once from the saved choices, saved once as one change
    /// of the layers it touched. A refused or unchanged drop saves nothing.
    private func drop(_ source: Position, at destination: Position) {
        guard let save, let move = Self.move(rows, locked: locked, from: source, to: destination), move.changesValue else { return }
        var changed: [Gesture: [String]] = [:]
        for row in Set([move.source.row, move.destination.row]) where layers.indices.contains(row) {
            changed[layers[row]] = move.value[row]
        }
        withAnimation(.editorReorder(reduceMotion: reduceMotion)) {
            // Layer rows never collapse, even when their last choice moves.
            if save(changed) { drag.moveIdentity(from: move.source, to: move.destination, removesEmptyRows: false) }
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
