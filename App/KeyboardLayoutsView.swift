import SwiftUI

/// The keyboard's base layouts. The keyboard switches between them when the
/// space bar is held; the first is used until another is chosen.
struct KeyboardLayoutsView: View {
    @EnvironmentObject private var preferences: CatalogPreferences
    @State private var adding = false
    @State private var failed = false

    var body: some View {
        List {
            Section {
                ForEach(preferences.alphabets) { alphabet in
                    LayoutRow(alphabet: alphabet).accessibilityIdentifier("layouts.enabled.\(alphabet.id)")
                }
                .onMove { from, to in
                    var ids = preferences.layouts
                    ids.move(fromOffsets: from, toOffset: to)
                    failed = !preferences.selectLayouts(ids)
                }
                .onDelete { offsets in
                    var ids = preferences.layouts
                    ids.remove(atOffsets: offsets)
                    failed = !preferences.selectLayouts(ids)
                }
                .deleteDisabled(preferences.layouts.count == 1)
                Button { adding = true } label: { Label("Add Layout", systemImage: "plus") }
                    .disabled(preferences.layouts.count >= UnicodeEditionSettings.maximumLayouts)
                    .accessibilityIdentifier("layouts.add")
            }
            if failed {
                Text("This change could not be saved. Please try again.")
                    .foregroundStyle(.red).accessibilityIdentifier("layouts.error")
            }
        }
        .navigationTitle("Layouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) {
            AddLayoutView(enabled: Set(preferences.layouts)) { id in
                failed = !preferences.selectLayouts(preferences.layouts + [id])
            }
        }
    }
}

private struct LayoutRow: View {
    let alphabet: KeyboardAlphabet
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(alphabet.nativeName)
            if alphabet.nativeName != alphabet.englishName {
                Text(alphabet.englishName).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AddLayoutView: View {
    let enabled: Set<String>
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Layouts for the device's preferred languages come first.
    private var suggested: [KeyboardAlphabet] {
        let languages = Locale.preferredLanguages.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        return available.filter { alphabet in languages.contains(alphabet.languageCode) }
    }
    private var available: [KeyboardAlphabet] {
        KeyboardAlphabet.catalog.filter { !enabled.contains($0.id) && matches($0) }
    }
    private func matches(_ alphabet: KeyboardAlphabet) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || alphabet.nativeName.localizedCaseInsensitiveContains(text)
            || alphabet.englishName.localizedCaseInsensitiveContains(text)
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggested.isEmpty {
                    Section("Suggested") { rows(suggested) }
                }
                ForEach(KeyboardAlphabet.Script.allCases, id: \.self) { script in
                    let layouts = available.filter { $0.script == script && !suggested.contains($0) }
                    if !layouts.isEmpty {
                        Section(script.title) { rows(layouts) }
                    }
                }
                if available.isEmpty {
                    Text("No more layouts match.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Layout").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Language")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func rows(_ layouts: [KeyboardAlphabet]) -> some View {
        ForEach(layouts) { alphabet in
            Button { add(alphabet.id); dismiss() } label: { LayoutRow(alphabet: alphabet).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("layouts.catalog.\(alphabet.id)")
        }
    }
}

private extension KeyboardAlphabet.Script {
    var title: String {
        switch self { case .latin: return "Latin"; case .greek: return "Greek"; case .cyrillic: return "Cyrillic" }
    }
}
