import SwiftUI

/// The main keyboard drawn as it types. Select a key to change what it types
/// and its swipe-up, hold and swipe-down choices; drag a letter onto another
/// to swap them. Each row keeps its length.
struct MainKeyboardEditorView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    @ObservedObject private var keys = KeyboardKeyPreferences.shared
    @State private var alphabetID = ""
    @State private var selected: String?
    @State private var width: CGFloat = 300
    private let spacing: CGFloat = 5
    private var alphabet: KeyboardAlphabet {
        preferences.alphabets.first { $0.id == alphabetID } ?? preferences.alphabets.first ?? .english
    }
    /// The layout's letters in the order the keyboard types them.
    private var arranged: KeyboardAlphabet { alphabet.arranged(keys.snapshot.arrangement(for: alphabet.id)) }
    private var rows: [[String]] { [Array("1234567890").map(String.init)] + arranged.rows }
    private var keyWidth: CGFloat {
        let columns = CGFloat(rows.map(\.count).max() ?? 10)
        return max(0, (width - spacing * (columns - 1)) / columns)
    }
    private var descriptor: KeyboardKeySettings.Descriptor? { selected.flatMap(KeyboardKeySettings.descriptor(for:)) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if preferences.alphabets.count > 1 {
                        Picker("Layout", selection: Binding(get: { alphabet.id }, set: { alphabetID = $0; selected = nil })) {
                            ForEach(preferences.alphabets) { Text($0.nativeName).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("mainKeyboard.layout")
                    }
                    VStack(spacing: 6) {
                        ForEach(rows.indices, id: \.self) { row in
                            HStack(spacing: spacing) {
                                ForEach(rows[row], id: \.self) { key in tile(key) }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("mainKeyboard.keys")
                    if let descriptor { layers(descriptor) }
                }
                .padding(16)
            }
            // Measured outside the keys, so they always fit the screen.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(0, $0 - 32 - 16) }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Standard Order") { keys.saveArrangement(nil, alphabetID: alphabet.id) }
                    .disabled(keys.snapshot.arrangement(for: alphabet.id) == nil)
                    .accessibilityIdentifier("mainKeyboard.reset")
            }
        }
        .onAppear { keys.refresh() }
    }

    /// The selected key's own output and its three candidate layers.
    private func layers(_ descriptor: KeyboardKeySettings.Descriptor) -> some View {
        KeyLayersPanel(layers: [.tap, .swipeUp, .longPress, .swipeDown], choices: { gesture in
            // No saved choices means the built-in defaults; the key itself types its own text.
            let values = keys.snapshot.candidates(for: descriptor.id, gesture: gesture)
            if gesture == .tap { return ([values?.first ?? descriptor.text ?? descriptor.title], values == nil) }
            return (values ?? KeyboardVariantPolicy.defaultCandidates(for: descriptor.id, gesture: gesture, alphabet: alphabet), values == nil)
        }, destination: { (gesture: KeyboardKeySettings.Gesture) -> AnyView in
                    let original = keys.snapshot.candidates(for: descriptor.id, gesture: gesture)
                    guard gesture == .tap else {
                        return AnyView(KeyboardGestureSettingsView(descriptor: descriptor, gesture: gesture, alphabet: alphabet,
                                                                   keys: keys, current: original))
                    }
                    // One value; none restores the key's own text.
                    return AnyView(KeyLayerEditor(title: "Key · \(descriptor.title)", choices: original ?? [], maximum: 1) { values in
                        keys.save(values.isEmpty ? nil : values, keyID: descriptor.id, gesture: .tap, replacing: original)
                    })
        })
    }

    /// Dropping one letter on another swaps their places.
    private func swap(_ dragged: String, with target: String) -> Bool {
        var order = arranged.keys
        guard dragged != target, let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else { return false }
        order.swapAt(from, to)
        return keys.saveArrangement(order == alphabet.keys ? nil : order, alphabetID: alphabet.id)
    }

    private func tile(_ key: String) -> some View {
        let id = KeyboardKeySettings.identifier(forCharacter: key)
        let isSelected = id != nil && id == selected
        // A changed key shows what it now types.
        let shown = id.flatMap { keys.snapshot.tapOutput(for: $0, defaultText: key, shifted: false) } ?? key
        return Button { selected = isSelected ? nil : id } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
                Text(symbolKeyPreview(shown)).font(.system(size: 22)).minimumScaleFactor(0.4).lineLimit(1).padding(2)
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
            .frame(width: keyWidth, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(id.flatMap(KeyboardKeySettings.descriptor(for:)) == nil)
        .modifier(LetterDrag(letter: key, enabled: alphabet.keys.contains(key), drop: swap))
        .accessibilityLabel("Key \(key)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("mainKeyboard.key.\(id ?? key)")
    }
}

/// Letters drag onto each other; the number row keeps its order.
private struct LetterDrag: ViewModifier {
    let letter: String
    let enabled: Bool
    let drop: (String, String) -> Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(letter) { Text(letter).font(.title2).padding(8) }
                .dropDestination(for: String.self) { items, _ in items.first.map { drop($0, letter) } ?? false }
        } else {
            content
        }
    }
}
