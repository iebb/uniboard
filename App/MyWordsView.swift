import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Embed in the parent's NavigationStack. The parent owns storage/rules/index
/// wiring; there is deliberately no fallback to Documents or guessed App Group.
@MainActor
struct MyWordsView: View {
    @ObservedObject private var model: MyWordsModel
    private let initialMode: LanguageInputMode?
    @State private var search = ""
    @State private var sheet: WordsSheet?
    @State private var confirmUndo = false
    @State private var matches = MyWordsSearchResult.empty
    @State private var searching = false
    @State private var searchGeneration = UUID()
    @State private var draft: WordsEntryDraft?
    @State private var deleteTarget: WordsEntryDraft?

    init(model: MyWordsModel, initialMode: LanguageInputMode? = nil) {
        self.model = model
        self.initialMode = initialMode
    }

    private enum WordsSheet: String, Identifiable {
        case create, importFile
        var id: String { rawValue }
    }

    private var collections: [CustomInputDictionaryCollection] {
        model.snapshot.collections.filter {
            (initialMode == nil || $0.modeID == initialMode?.rawValue) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) ||
             modeTitle($0.modeID).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    Text(LanguageInputCopy.localWords).font(.subheadline)
                }
            }
            WordsStatus(model: model)
            if !model.hasLoaded {
                Section {
                    if model.isBusy { ProgressView("Loading My Words…") }
                    else { Button("Try Again") { Task { await model.load() } } }
                }
            } else if !model.sourceReadable {
                Section { Text("Your dictionaries couldn’t be read. Try again.") }
            } else {
                if search.isEmpty && collections.isEmpty {
                    Section {
                        Text("No custom words yet").font(.headline)
                        Text("Add an entry or import a dictionary.").foregroundStyle(.secondary)
                        Button("Add Dictionary", systemImage: "plus") { sheet = .create }
                        Button("Import Dictionary", systemImage: "square.and.arrow.down") { sheet = .importFile }
                    }
                }
                if !collections.isEmpty {
                    Section {
                        ForEach(collections) { collection in
                            NavigationLink {
                                WordsCollectionView(model: model, collectionID: collection.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(collection.name).foregroundStyle(.primary)
                                    Text("\(modeTitle(collection.modeID)) · \(collection.entries.count == 1 ? "1 entry" : "\(collection.entries.count) entries")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Label(collection.enabled ? "Enabled" : "Off", systemImage: collection.enabled ? "checkmark.circle" : "minus.circle")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    if let mode = LanguageInputMode(rawValue: collection.modeID), let notice = model.modeNotices[mode] {
                                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }.frame(minHeight: 52, alignment: .leading)
                            }
                        }
                    } header: { Text(search.isEmpty ? "Dictionaries" : "Matching Dictionaries") }
                    footer: {
                        if search.isEmpty {
                            Text(initialMode == nil ? "Search readings and outputs across your dictionaries." : "Search readings and outputs in dictionaries for this input mode.")
                        }
                    }
                }
                if !search.isEmpty {
                    if searching {
                        Section { ProgressView("Loading My Words…") }
                    } else if matches.entries.isEmpty && collections.isEmpty {
                        ContentUnavailableView("No matching entries", systemImage: "magnifyingglass", description: Text("Try another reading or output."))
                    } else if !matches.entries.isEmpty {
                        Section {
                            ForEach(matches.entries) { reference in
                                searchRow(reference)
                            }
                        } header: { Text("Matching Entries") } footer: {
                            if matches.hasMore { Text("Showing the first 100 matches. Narrow your search to find other entries.") }
                        }
                    }
                }
            }
            if search.isEmpty {
                if model.canUndoImport {
                    Section("Recent Import") {
                        if let name = model.recentImportName { Text(name) }
                        if let date = model.recentImportDate { Text(date, style: .date).font(.footnote).foregroundStyle(.secondary) }
                        Button("Undo Import", systemImage: "arrow.uturn.backward") { confirmUndo = true }
                    }
                } else if let reason = model.undoInvalidationReason {
                    Section { Text(reason).font(.footnote).foregroundStyle(.secondary) }
                } else if model.hasLoaded && !model.snapshot.collections.isEmpty {
                    // The core persists a protected Undo marker but doesn't expose it
                    // in snapshots. This recovery action asks the core to verify it.
                    Section {
                        Button("Undo Last Import…", systemImage: "arrow.uturn.backward") { confirmUndo = true }
                        Text("If the last import is still eligible, only its dictionary will be removed. Later edits are never rolled back.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("\(model.snapshot.totalEntryCount) / 50,000 entries").monospacedDigit()
                    Text(LanguageInputCopy.backup).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Words")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            WordsSearchHeader(text: $search, placeholder: "Search My Words", identifier: "myWords.search")
        }
        .scrollDismissesKeyboard(.interactively)
                .modifier(WordsScrollEdge())
        .onDisappear { WordsSearchHeader.endEditing() }
        .onChange(of: sheet) { _, value in if value != nil { WordsSearchHeader.endEditing() } }
        .onChange(of: draft?.id) { _, value in if value != nil { WordsSearchHeader.endEditing() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Dictionary", systemImage: "plus") { sheet = .create }
                    Button("Import Dictionary", systemImage: "square.and.arrow.down") { sheet = .importFile }
                } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Add Words")
                .disabled(!model.hasLoaded || model.isBusy)
            }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .create: WordsNewDictionary(model: model, initialMode: initialMode)
            case .importFile: WordsImportView(model: model, initialMode: initialMode)
            }
        }
        .confirmationDialog("Undo this dictionary import?", isPresented: $confirmUndo, titleVisibility: .visible) {
            Button("Undo Import", role: .destructive) { Task { _ = await model.recoverLastImportUndo() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let name = model.recentImportName {
                Text("This removes “\(name)”, the dictionary created by the last import.")
            } else { Text("This removes the dictionary created by the last import. It won’t remove later edits.") }
        }
        .sheet(item: $draft) { WordsEntryEditor(model: model, draft: $0) }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            if let target = deleteTarget, let index = target.index {
                Button("Delete Entry", role: .destructive) {
                    Task { _ = await model.deleteEntry(collectionID: target.collectionID, index: index, revision: target.revision, expectedIdentity: target.entry?.identity) }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The entry will no longer appear as a choice from this dictionary.") }
        .task { await model.load() }
        .task(id: WordsSearchRequest(query: search, revision: model.snapshot.revision, readable: model.sourceReadable, modeID: initialMode?.rawValue)) {
            let generation = UUID()
            searchGeneration = generation
            matches = .empty
            guard !search.isEmpty, model.sourceReadable else { searching = false; return }
            searching = true
            let result = await MyWordsModel.search(snapshot: model.snapshot, query: search, modeID: initialMode?.rawValue)
            guard !Task.isCancelled, searchGeneration == generation else { return }
            matches = result
            searching = false
        }
    }

    private func searchRow(_ reference: MyWordsEntryReference) -> some View {
        let target = WordsEntryDraft(collectionID: reference.id.collectionID,
            mode: LanguageInputMode(rawValue: reference.modeID) ?? .koreanRomaja,
            index: reference.id.index, entry: reference.entry, revision: reference.id.revision,
            dictionaryName: reference.dictionaryName)
        return Button { draft = target } label: {
            HStack(alignment: .top, spacing: 12) {
                WordsModeTile(modeID: reference.modeID)
                VStack(alignment: .leading, spacing: 5) {
                    WordsEntryRow(entry: reference.entry)
                    Text("Dictionary: \(reference.dictionaryName)")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel("Reading: \(reference.entry.reading). Output: \(reference.entry.output). Dictionary: \(reference.dictionaryName). Input Mode: \(modeTitle(reference.modeID)).")
        .swipeActions(edge: .leading) {
            Button("Duplicate Entry", systemImage: "plus.square.on.square") { draft = target.duplicate() }.tint(.blue)
                .disabled(!model.supportedModes.contains(target.mode))
        }
        .swipeActions {
            Button("Delete Entry", role: .destructive) { deleteTarget = target }
            Button("Edit Entry") { draft = target }
        }
        .contextMenu {
            Button("Edit Entry") { draft = target }
            Button("Duplicate Entry", systemImage: "plus.square.on.square") { draft = target.duplicate() }
                .disabled(!model.supportedModes.contains(target.mode))
            Button("Delete Entry", role: .destructive) { deleteTarget = target }
        }
    }
}

/// A real content-owned field, like Explore/Emoji search, rather than a
/// navigation-controller search item. The Settings push hierarchy can suppress
/// `.searchable` even with an always-visible drawer on iOS 27.
@MainActor
private struct WordsSearchHeader: View {
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 44
    @Binding var text: String
    let placeholder: String
    let identifier: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).accessibilityHidden(true)
            // Existing app control preserves exact UTF-16, native caret and
            // every editingChanged event; no autocorrection/smart punctuation.
            // Its keyboard Done key resigns first responder without clearing.
            AppSearchField(text: $text, placeholder: placeholder, identifier: identifier)
                .frame(height: max(44, fieldHeight))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier(identifier + ".clear")
            }
        }
        .padding(.horizontal, 12)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 8)
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) {
            // Draw across the actual list boundary, rather than relying on the
            // navigation scroll-edge effect to discover this custom inset.
            // The first 8 points occlude clipped glyph fragments; the remaining
            // 16 fade into the scrolling rows without adding another layout gap.
            LinearGradient(stops: [
                .init(color: Color(uiColor: .systemGroupedBackground), location: 0),
                .init(color: Color(uiColor: .systemGroupedBackground), location: 1.0 / 3.0),
                .init(color: Color(uiColor: .systemGroupedBackground).opacity(0), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 24)
            .offset(y: 24)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .zIndex(1)
    }

    static func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct WordsScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct WordsSearchRequest: Equatable {
    let query: String
    let revision: UUID
    let readable: Bool
    let modeID: String?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query.utf8.elementsEqual(rhs.query.utf8) && lhs.revision == rhs.revision && lhs.readable == rhs.readable && lhs.modeID == rhs.modeID
    }
}

private struct WordsModeTile: View {
    let modeID: String
    var body: some View {
        Group {
            switch LanguageInputMode(rawValue: modeID) {
            case .direct: Image(systemName: "keyboard")
            case .japaneseRomaji, .mandarinPinyin: Image(systemName: "character.bubble")
            case .koreanRomaja: VStack(spacing: 0) { Text("가"); Text("Aa").font(.caption2) }
            case .koreanTwoSetHangul: Text("가")
            default: Image(systemName: "questionmark")
            }
        }
        .font(.body).frame(width: 28, height: 28)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

@MainActor
private struct WordsStatus: View {
    @ObservedObject var model: MyWordsModel
    var body: some View {
        if model.choicesPhase != .idle {
            Section {
                switch model.choicesPhase {
                case .checking:
                    ProgressView("Checking keyboard choices…").foregroundStyle(.secondary)
                case .rebuilding:
                    ProgressView("Rebuilding keyboard choices…")
                case .updated:
                    Label { Text("Keyboard choices updated") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                case .stale, .failed, .unreadable:
                    Label {
                        Text(model.choicesPhase == .unreadable ? "Keyboard choices couldn’t be read. Your saved dictionaries haven’t been changed." : model.choicesPhase == .failed ? "Your saved words couldn’t be prepared for the keyboard. Your dictionaries haven’t changed." : "Keyboard choices still need updating.")
                    } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Button("Update Keyboard Choices") { Task { await model.retryIndex() } }
                        .buttonStyle(.bordered).disabled(model.isBusy)
                case .sourceUnreadable:
                    Label { Text(model.errorMessage ?? "Your saved dictionaries couldn’t be read. They haven’t been replaced.") }
                    icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Button("Try Again") { Task { await model.load() } }.disabled(model.isBusy)
                case .idle: EmptyView()
                }
            } header: { Text("Keyboard Choices") } footer: {
                if model.choicesPhase == .rebuilding {
                    Text("Preparing choices from your saved words. Your dictionaries won’t change.")
                }
            }
            .onChange(of: model.choicesPhase) { _, phase in
                if phase == .updated { UIAccessibility.post(notification: .announcement, argument: "Keyboard choices updated") }
            }
        }
        if let error = model.errorMessage, model.choicesPhase != .failed && model.choicesPhase != .unreadable && model.choicesPhase != .sourceUnreadable {
            Section {
                Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button("Try Again") { Task { await model.load() } }.disabled(model.isBusy)
            }
        }
        if let status = model.statusMessage {
            Section { Label(status, systemImage: "checkmark.circle").accessibilityAddTraits(.updatesFrequently) }
        }
    }
}

private func modeTitle(_ modeID: String) -> String {
    LanguageInputMode(rawValue: modeID)?.title ?? "Unavailable Input Mode"
}

@MainActor
private struct WordsModePicker: View {
    @ObservedObject var model: MyWordsModel
    @Binding var mode: LanguageInputMode?
    var body: some View {
        Picker("Input Mode", selection: $mode) {
            Text("Choose Input Mode").tag(Optional<LanguageInputMode>.none)
            ForEach(MyWordsModel.editableModes, id: \.self) { item in
                Text(item == .direct ? "Direct Typing — English" : item.title)
                    .tag(Optional(item))
                    .disabled(!model.supportedModes.contains(item))
            }
        }
        Text("Creating words doesn’t install language data or enable an input mode. Manage language availability in Languages.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

@MainActor
private struct WordsNewDictionary: View {
    @ObservedObject var model: MyWordsModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mode: LanguageInputMode?
    @State private var discard = false

    init(model: MyWordsModel, initialMode: LanguageInputMode?) {
        self.model = model
        _mode = State(initialValue: initialMode.flatMap { MyWordsModel.editableModes.contains($0) ? $0 : nil })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).autocorrectionDisabled()
                    WordsModePicker(model: model, mode: $mode)
                }
                Section {
                    Text("New dictionaries start Off. Turn on Use in Keyboard after reviewing your entries.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                WordsStatus(model: model)
            }
            .disabled(model.isBusy)
            .navigationTitle("New Dictionary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if name.isEmpty { dismiss() } else { discard = true } }.disabled(model.isBusy)
                        .confirmationDialog("Discard Changes?", isPresented: $discard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let mode else { return }
                        Task { if await model.create(name: name, mode: mode) { dismiss() } }
                    }.disabled(model.isBusy || !validDictionaryName(name) || mode == nil || !model.supportedModes.contains(mode ?? .koreanRomaja))
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isBusy || !name.isEmpty)
        .onAppear { model.clearError() }
    }
}

private func validDictionaryName(_ name: String) -> Bool {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !value.isEmpty && value.unicodeScalars.count <= 256 && !value.unicodeScalars.contains {
        $0.value == 0 || $0.value == 9 || CharacterSet.newlines.contains($0)
    }
}

private struct WordsRenameDraft: Identifiable {
    let id = UUID()
    let collection: CustomInputDictionaryCollection
    let revision: UUID
}

private struct WordsEntryDraft: Identifiable {
    let id = UUID()
    let collectionID: UUID
    let mode: LanguageInputMode
    let index: Int?
    let entry: CustomInputDictionaryEntry?
    let revision: UUID
    var dictionaryName: String = ""
    var isDuplicate: Bool { index == nil && entry != nil }
    func duplicate() -> WordsEntryDraft {
        .init(collectionID: collectionID, mode: mode, index: nil, entry: entry, revision: revision, dictionaryName: dictionaryName)
    }
}

@MainActor
private struct WordsCollectionView: View {
    @ObservedObject var model: MyWordsModel
    let collectionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var draft: WordsEntryDraft?
    @State private var renameTarget: WordsRenameDraft?
    @State private var sort: MyWordsEntrySort = .original
    @State private var remove = false
    @State private var removeRevision: UUID?
    @State private var share: MyWordsShare?
    @State private var deleteTarget: WordsEntryDraft?

    private var collection: CustomInputDictionaryCollection? { model.snapshot.collections.first { $0.id == collectionID } }

    var body: some View {
        Group {
            if let collection {
                let sourceRevision = model.snapshot.revision
                let indices = visibleIndices(in: collection)
                List {
                    Section {
                        Text(collection.name)
                            .font(.headline)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        LabeledContent("Input Mode", value: modeTitle(collection.modeID))
                        if let mode = LanguageInputMode(rawValue: collection.modeID), let notice = model.modeNotices[mode] {
                            Text(notice).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Use in Keyboard", isOn: Binding(get: { self.collection?.enabled ?? false }, set: { value in
                            Task { await model.setEnabled(id: collection.id, enabled: value) }
                        })).disabled(model.isBusy)
                        Text(collection.entries.count == 1 ? "1 entry" : "\(collection.entries.count) entries").monospacedDigit()
                        Text("Language data, if needed, must also be installed and its mode enabled in Languages.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if collection.entries.isEmpty {
                            Text("Input mode was chosen when this dictionary was created. To use another mode, create a new dictionary.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    WordsStatus(model: model)
                    Section {
                        if collection.entries.isEmpty {
                            Text("No entries yet").foregroundStyle(.secondary)
                            Text("No entries to export").font(.footnote).foregroundStyle(.secondary)
                            Button("Add Entry", systemImage: "plus") { add(in: collection, revision: sourceRevision) }
                                .disabled(model.isBusy || !model.supportedModes.contains(LanguageInputMode(rawValue: collection.modeID) ?? .koreanRomaja))
                        }
                        if !collection.entries.isEmpty && indices.isEmpty {
                            Text("No matching entries").font(.headline)
                            Text("Try another reading or output.").foregroundStyle(.secondary)
                        }
                        ForEach(indices, id: \.self) { index in
                            let entry = collection.entries[index]
                            Button {
                                draft = makeDraft(in: collection, index: index, entry: entry, revision: sourceRevision)
                            } label: {
                                HStack {
                                    WordsEntryRow(entry: entry)
                                    if sort == .weight { Text(entry.weight, format: .number).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(model.isBusy)
                            .swipeActions(edge: .leading) {
                                Button("Duplicate Entry", systemImage: "plus.square.on.square") {
                                    draft = makeDraft(in: collection, index: nil, entry: entry, revision: sourceRevision)
                                }.tint(.blue).disabled(!canEdit(collection))
                            }
                            .swipeActions {
                                Button("Delete Entry", role: .destructive) { deleteTarget = makeDraft(in: collection, index: index, entry: entry, revision: sourceRevision) }
                            }
                            .contextMenu {
                                Button("Edit Entry") { draft = makeDraft(in: collection, index: index, entry: entry, revision: sourceRevision) }
                                Button("Duplicate Entry", systemImage: "plus.square.on.square") { draft = makeDraft(in: collection, index: nil, entry: entry, revision: sourceRevision) }
                                    .disabled(!canEdit(collection))
                                Button("Delete Entry", role: .destructive) { deleteTarget = makeDraft(in: collection, index: index, entry: entry, revision: sourceRevision) }
                            }
                            .accessibilityAction(named: "Edit Entry") { draft = makeDraft(in: collection, index: index, entry: entry, revision: sourceRevision) }
                            .accessibilityAction(named: "Duplicate Entry") {
                                if canEdit(collection) { draft = makeDraft(in: collection, index: nil, entry: entry, revision: sourceRevision) }
                            }
                            .accessibilityAction(named: "Delete Entry") { deleteTarget = makeDraft(in: collection, index: index, entry: entry, revision: sourceRevision) }
                        }
                    } header: { Text(sort.heading) } footer: {
                        if sort != .original { Text("Changes only how entries are shown. Saved order and exports stay the same.") }
                    }
                }
                .navigationTitle(collection.name).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top, spacing: 0) {
                    WordsSearchHeader(text: $search, placeholder: "Search entries", identifier: "myWords.dictionary.search")
                }
                .scrollDismissesKeyboard(.interactively)
                .modifier(WordsScrollEdge())
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Entry", systemImage: "plus") { add(in: collection, revision: sourceRevision) }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Add Entry")
                            .disabled(model.isBusy || !model.supportedModes.contains(LanguageInputMode(rawValue: collection.modeID) ?? .koreanRomaja))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker(selection: $sort) {
                                ForEach(MyWordsEntrySort.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
                            } label: { Label("Sort Entries", systemImage: "arrow.up.arrow.down") }
                            .pickerStyle(.inline)
                            Divider()
                            Button("Rename") { renameTarget = .init(collection: collection, revision: sourceRevision) }
                            Button("Export Dictionary", systemImage: "square.and.arrow.up") { Task { share = await model.export(id: collection.id) } }
                                .disabled(collection.entries.isEmpty)
                            Button("Remove Dictionary", systemImage: "trash", role: .destructive) {
                                removeRevision = sourceRevision
                                remove = true
                            }
                        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Dictionary Actions").disabled(model.isBusy)
                        .confirmationDialog("Remove this dictionary?", isPresented: $remove, titleVisibility: .visible) {
                            Button("Remove Dictionary", role: .destructive) {
                                guard let revision = removeRevision else { return }
                                Task { if await model.remove(id: collection.id, revision: revision) { dismiss() } }
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("“\(collection.name)” has \(collection.entries.count == 1 ? "1 entry" : "\(collection.entries.count) entries"). Its entries will no longer appear as choices. Export it first if you want to keep a copy. Language downloads won’t be removed.")
                        }
                    }
                }
                .sheet(item: $renameTarget) { target in
                    WordsRenameView(model: model, collection: target.collection, revision: target.revision)
                }
            } else {
                ContentUnavailableView("Dictionary unavailable", systemImage: "text.book.closed", description: Text("Return to My Words to review your dictionaries."))
            }
        }
        .onAppear { model.dismissUpdatedChoices() }
        .onDisappear { WordsSearchHeader.endEditing() }
        .onChange(of: draft?.id) { _, value in if value != nil { WordsSearchHeader.endEditing() } }
        .onChange(of: renameTarget?.id) { _, value in if value != nil { WordsSearchHeader.endEditing() } }
        .sheet(item: $draft) { WordsEntryEditor(model: model, draft: $0) }
        .sheet(item: $share, onDismiss: { /* Activity controller performs cleanup. */ }) { value in
            WordsShareView(share: value, model: model)
                .onDisappear { Task { await model.cleanShare(value) } }
        }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            if let target = deleteTarget, let index = target.index {
                Button("Delete Entry", role: .destructive) {
                    Task { _ = await model.deleteEntry(collectionID: target.collectionID, index: index, revision: target.revision, expectedIdentity: target.entry?.identity) }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The entry will no longer appear as a choice from this dictionary.") }
    }

    private func makeDraft(in collection: CustomInputDictionaryCollection, index: Int?, entry: CustomInputDictionaryEntry?, revision: UUID) -> WordsEntryDraft {
        .init(collectionID: collection.id, mode: LanguageInputMode(rawValue: collection.modeID) ?? .koreanRomaja,
              index: index, entry: entry, revision: revision, dictionaryName: collection.name)
    }
    private func visibleIndices(in collection: CustomInputDictionaryCollection) -> [Int] {
        MyWordsPresentation.sortedIndices(collection.entries, query: search, sort: sort)
    }
    private func canEdit(_ collection: CustomInputDictionaryCollection) -> Bool {
        model.supportedModes.contains(LanguageInputMode(rawValue: collection.modeID) ?? .koreanRomaja)
    }
    private func add(in collection: CustomInputDictionaryCollection, revision: UUID) { draft = makeDraft(in: collection, index: nil, entry: nil, revision: revision) }
}

private struct WordsEntryRow: View {
    let entry: CustomInputDictionaryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.reading).font(.subheadline).foregroundStyle(.secondary)
            Text(entry.output).font(.body).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading: \(entry.reading). Output: \(entry.output)")
    }
}

@MainActor
private struct WordsRenameView: View {
    @ObservedObject var model: MyWordsModel
    let collection: CustomInputDictionaryCollection
    let revision: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var discard = false

    init(model: MyWordsModel, collection: CustomInputDictionaryCollection, revision: UUID) {
        self.model = model
        self.collection = collection
        self.revision = revision
        _name = State(initialValue: collection.name)
    }
    private var dirty: Bool { !name.utf8.elementsEqual(collection.name.utf8) }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name).autocorrectionDisabled() }
                WordsStatus(model: model)
            }
            .disabled(model.isBusy)
            .navigationTitle("Rename Dictionary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { discard = true } else { dismiss() } }.disabled(model.isBusy)
                        .confirmationDialog("Discard Changes?", isPresented: $discard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await model.rename(id: collection.id, name: name, revision: revision) { dismiss() } } }
                        .disabled(model.isBusy || !validDictionaryName(name) || !dirty)
                }
            }
        }
        .presentationDetents([.large]).interactiveDismissDisabled(model.isBusy || dirty)
        .onAppear { model.clearError() }
    }
}

@MainActor
private struct WordsEntryEditor: View {
    @ObservedObject var model: MyWordsModel
    let draft: WordsEntryDraft
    @Environment(\.dismiss) private var dismiss
    @State private var reading: String
    @State private var output: String
    @State private var weight: String
    @State private var validation: String?
    @State private var checking = true
    @State private var weightExpanded: Bool
    @State private var inspection: MyWordsOutputInspection?
    @AccessibilityFocusState private var inspectFocused: Bool
    @State private var discard = false

    init(model: MyWordsModel, draft: WordsEntryDraft) {
        self.model = model
        self.draft = draft
        _reading = State(initialValue: draft.entry?.reading ?? "")
        _output = State(initialValue: draft.entry?.output ?? "")
        _weight = State(initialValue: String(draft.entry?.weight ?? 100))
        _weightExpanded = State(initialValue: draft.isDuplicate)
    }
    private var dirty: Bool {
        !reading.utf8.elementsEqual((draft.entry?.reading ?? "").utf8) ||
        !output.utf8.elementsEqual((draft.entry?.output ?? "").utf8) || weight != String(draft.entry?.weight ?? 100)
    }
    private var unchangedDuplicate: Bool {
        guard draft.isDuplicate, let source = draft.entry else { return false }
        return MyWordsPresentation.isUnchangedPair(reading: reading, output: output, source: source)
    }
    private var validationID: [Data] { [Data(reading.utf8), Data(output.utf8), Data(weight.utf8)] }

    var body: some View {
        NavigationStack {
            Form {
                if draft.isDuplicate {
                    Section { Text("Dictionary: \(draft.dictionaryName)") } footer: {
                        Text("Start a new entry from this one. Nothing is saved until you tap Save.")
                    }
                }
                Section { LabeledContent("Input Mode", value: draft.mode.title) }
                Section {
                    WordsExactTextEditor(text: $reading, label: "Reading")
                    scalarCount(reading)
                } header: { Text("Reading") } footer: {
                    Text("The spelling you type to find this entry. \(LanguageInputCopy.readingHelp(draft.mode))")
                }
                Section {
                    WordsExactTextEditor(text: $output, label: "Output")
                    scalarCount(output)
                    Button("Inspect Unicode Code Points", systemImage: "magnifyingglass.circle") {
                        inspection = MyWordsOutputInspection(output)
                    }
                    .disabled(output.isEmpty).accessibilityLabel("Inspect output code points")
                    .accessibilityFocused($inspectFocused)
                } header: { Text("Output") } footer: {
                    if unchangedDuplicate {
                        Text("This reading and output already exist in this dictionary. Edit the existing entry to change its weight.")
                    } else if output.isEmpty {
                        Text("Enter output, then choose Inspect Unicode Code Points.")
                    } else { Text("The text offered as a choice. \(LanguageInputCopy.exactOutput)") }
                }
                Section {
                    DisclosureGroup("Weight", isExpanded: $weightExpanded) {
                        TextField("Weight", text: $weight).keyboardType(.numberPad)
                            .accessibilityLabel("Weight, a whole number from 0 to 10000")
                        Text("A ranking preference from 0 to 10000.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if model.isMutating { Section { ProgressView("Saving entry…") } }
                else if checking { Section { ProgressView("Checking entry…") } }
                if let validation {
                    Section { Label(validation, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
                WordsStatus(model: model)
            }
            .disabled(model.isBusy)
            .navigationTitle(draft.isDuplicate ? "Duplicate Entry" : draft.index == nil ? "Add Entry" : "Edit Entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { discard = true } else { dismiss() } }.disabled(model.isBusy)
                        .confirmationDialog("Discard Changes?", isPresented: $discard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let number = Int(weight) else { return }
                        Task {
                            if await model.saveEntry(collectionID: draft.collectionID, index: draft.index, reading: reading,
                                                     output: output, weight: number, revision: draft.revision, expectedIdentity: draft.index == nil ? nil : draft.entry?.identity) {
                                UIAccessibility.post(notification: .announcement, argument: "Saved")
                                dismiss()
                            }
                        }
                    }.disabled(model.isBusy || checking || validation != nil || !dirty || unchangedDuplicate)
                }
            }
            .task(id: validationID) {
                checking = true
                let result = await model.validate(reading: reading, output: output, weight: weight, mode: draft.mode)
                guard !Task.isCancelled else { return }
                validation = result
                checking = false
            }
        }
        .presentationDetents([.large]).interactiveDismissDisabled(model.isBusy || dirty)
        .sheet(item: $inspection, onDismiss: { inspectFocused = true }) { WordsOutputInspector(snapshot: $0) }
        .onAppear { model.clearError() }
    }

    @ViewBuilder private func scalarCount(_ text: String) -> some View {
        let count = text.unicodeScalars.count
        if count >= 224 {
            Text("\(count) / 256 Unicode code points").font(.footnote).monospacedDigit()
                .foregroundStyle(count > 256 ? Color.red : Color.secondary)
        }
    }
}

private struct WordsOutputInspector: View {
    let snapshot: MyWordsOutputInspection
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(snapshot.text).font(.title2).textSelection(.enabled)
                } header: { Text("Output") } footer: {
                    Text("This shows the output in your draft. Inspecting it doesn’t save or change your entry.")
                }
                Section {
                    ForEach(snapshot.scalars) { scalar in
                        HStack(alignment: .top, spacing: 12) {
                            Text(scalar.glyph).frame(width: 32).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scalar.codePoint).font(.system(.subheadline, design: .monospaced))
                                HStack {
                                    Text(scalar.name).font(.footnote)
                                    if scalar.usesStandIn { Image(systemName: "eye.slash").font(.footnote).accessibilityHidden(true) }
                                }.foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Code point \(scalar.id + 1): \(scalar.codePoint). \(scalar.name)")
                    }
                } header: {
                    Text("Code Points · \(snapshot.scalars.count == 1 ? "1 code point" : "\(snapshot.scalars.count) code points")")
                }
            }
            .navigationTitle("Inspect Text").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

@MainActor
private struct WordsImportView: View {
    @ObservedObject var model: MyWordsModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: LanguageInputMode?
    @State private var name = ""
    @State private var chooseFile = false
    @State private var review: MyWordsImportReview?
    @State private var enableImported = false
    @State private var showAllProblems = false
    @State private var reviewSearch = ""
    @State private var previewPage = 0
    @State private var problemsPage = 0
    @State private var share: MyWordsShare?

    init(model: MyWordsModel, initialMode: LanguageInputMode?) {
        self.model = model
        _mode = State(initialValue: initialMode.flatMap { MyWordsModel.editableModes.contains($0) ? $0 : nil })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let review { reviewForm(review) }
                else { setupForm }
            }
            .navigationTitle(review == nil ? "Import Dictionary" : "Review Dictionary Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if review != nil { review = nil; model.clearError() }
                        else { dismiss() }
                    }.disabled(model.isMutating)
                }
            }
            .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.tabSeparatedText, .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first, let mode else { return }
                    Task {
                        if let result = await model.review(fileURL: url, mode: mode, name: name) {
                            name = result.name
                            review = result
                            enableImported = false
                            showAllProblems = false
                            reviewSearch = ""
                            previewPage = 0
                            problemsPage = 0
                        }
                    }
                case .failure: model.reportFileError()
                }
            }
        }
        .presentationDetents([.large]).interactiveDismissDisabled(model.isMutating)
        .sheet(item: $share) { value in
            WordsShareView(share: value, model: model)
                .onDisappear { Task { await model.cleanShare(value) } }
        }
        .onAppear { model.clearError() }
    }

    private var setupForm: some View {
        Form {
            Section {
                WordsModePicker(model: model, mode: $mode)
                TextField("Dictionary Name", text: $name).autocorrectionDisabled()
                Button("Choose File", systemImage: "doc") { chooseFile = true }
                    .disabled(mode == nil || model.isBusy || !model.supportedModes.contains(mode ?? .koreanRomaja))
            }
            Section {
                NavigationLink("Dictionary File Format") { WordsFormatHelp() }
                Button("Download Example", systemImage: "square.and.arrow.down") {
                    guard let mode else { return }
                    Task { share = await model.example(mode: mode) }
                }.disabled(mode == nil || model.isBusy || !model.supportedModes.contains(mode ?? .koreanRomaja))
                Text("Save or share a local example for the selected mode. No network download is used.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            WordsStatus(model: model)
        }
        .disabled(model.isBusy)
    }

    private func reviewForm(_ review: MyWordsImportReview) -> some View {
        ScrollViewReader { proxy in
            reviewContents(review)
                .safeAreaInset(edge: .top, spacing: 0) {
                    WordsSearchHeader(text: $reviewSearch, placeholder: "Search entries", identifier: "myWords.import.search")
                }
                .scrollDismissesKeyboard(.interactively)
                .modifier(WordsScrollEdge())
                .onDisappear { WordsSearchHeader.endEditing() }
                .onChange(of: reviewSearch) { _, _ in previewPage = 0 }
                .onChange(of: review.id) { _, _ in
                    previewPage = 0; problemsPage = 0; showAllProblems = false
                }
                .onChange(of: previewPage) { _, _ in
                    proxy.scrollTo("import-preview", anchor: .top)
                    let total = previewIndices(review).count
                    UIAccessibility.post(notification: .announcement, argument: MyWordsPage(total: total, page: previewPage, size: 50).label(noun: reviewSearch.isEmpty ? "Entries" : "Matches", total: total))
                }
                .onChange(of: showAllProblems) { _, expanded in
                    if expanded {
                        proxy.scrollTo("import-problems", anchor: .top)
                        let total = review.preview.rowErrors.count
                        UIAccessibility.post(notification: .announcement, argument: MyWordsPage(total: total, page: 0, size: 20).label(noun: "Problems", total: total))
                    }
                }
                .onChange(of: problemsPage) { _, _ in
                    proxy.scrollTo("import-problems", anchor: .top)
                    let total = review.preview.rowErrors.count
                    UIAccessibility.post(notification: .announcement, argument: MyWordsPage(total: total, page: problemsPage, size: 20).label(noun: "Problems", total: total))
                }
        }
    }

    private func reviewContents(_ review: MyWordsImportReview) -> some View {
        Form {
            Section { Text(LanguageInputCopy.separateDictionary).font(.subheadline) }
            Section {
                Text(review.filename).textSelection(.enabled)
                Text("\(review.byteCount) bytes").monospacedDigit().font(.footnote)
                LabeledContent("Input Mode", value: review.mode.title)
                TextField("Dictionary Name", text: $name).autocorrectionDisabled()
                Toggle("Use in Keyboard", isOn: $enableImported).disabled(model.isBusy)
                Text("Importing doesn’t enable this language mode or install language data. The dictionary starts Off unless you turn on Use in Keyboard here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                count("Valid Entries", review.preview.uniqueEntryCount)
                count("Duplicate Entries", review.preview.duplicateRowCount)
                count("Combined Entries", review.preview.combinedCount)
                count("Invalid Entries", review.preview.invalidRowCount)
                DisclosureGroup("About These Counts") {
                    Text("Valid Entries counts unique entries to add. Duplicate Entries counts repeated identical rows. Combined Entries counts additional distinct weights.")
                    Text(LanguageInputCopy.duplicates)
                    Text(LanguageInputCopy.combined)
                }.font(.footnote)
            } header: { Text("Entire File") } footer: {
                Text("These counts cover the entire file, not just the entries shown below.")
            }
            if !review.preview.fileIssues.isEmpty || review.preview.invalidRowCount > 0 {
                Section("Problems") {
                    ForEach(Array(review.preview.fileIssues.enumerated()), id: \.offset) { _, issue in
                        Label(LanguageInputCopy.message(issue), systemImage: "xmark.octagon")
                            .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    let page = MyWordsPage(total: review.preview.rowErrors.count, page: problemsPage, size: 20)
                    let range = showAllProblems ? page.range : 0..<min(3, review.preview.rowErrors.count)
                    ForEach(Array(range), id: \.self) { index in
                        let error = review.preview.rowErrors[index]
                        Label("Line \(error.line): \(LanguageInputCopy.message(error.issue))", systemImage: "xmark.octagon")
                            .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    if review.preview.rowErrors.count > 3 && !showAllProblems {
                        Button("Show More Problems") { problemsPage = 0; showAllProblems = true }
                    }
                    if showAllProblems {
                        Text(page.label(noun: "Problems", total: review.preview.rowErrors.count)).font(.footnote).monospacedDigit()
                        WordsPager(page: page, previous: "Previous Problems", next: "Next Problems", value: $problemsPage)
                    }
                    Text("Fix the invalid entries before importing. Your words haven’t changed.").font(.footnote)
                    Button("Choose File Again") { chooseFile = true }.disabled(model.isBusy)
                }.id("import-problems")
            } else if review.preview.duplicateRowCount > 0 || review.preview.combinedCount > 0 {
                Section {
                    Label("Repeated entries will be kept once.", systemImage: "exclamationmark.triangle")
                }
            }
            previewSection(review)
            Section {
                Text(LanguageInputCopy.duplicates).font(.footnote)
                Text(LanguageInputCopy.combined).font(.footnote)
                Text("One-step Undo Import remains available until a later change makes it unsafe. Each imported dictionary can also be removed independently.").font(.footnote)
                Text(LanguageInputCopy.readingHelp(review.mode)).font(.footnote)
                NavigationLink("Dictionary File Format") { WordsFormatHelp() }
            }
            WordsStatus(model: model)
            if review.preview.baseRevision != model.snapshot.revision {
                Section {
                    Label("My Words changed. Review this file again before importing.", systemImage: "exclamationmark.triangle")
                    Button("Review Again") {
                        Task { self.review = await model.review(fileURL: review.fileURL, mode: review.mode, name: name) }
                    }.disabled(model.isBusy)
                }
            }
        }
        .disabled(model.isBusy)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text(review.preview.invalidRowCount > 0 ? "Fix the invalid entries before importing. Your words haven’t changed." : "Your existing words won’t be replaced.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if review.preview.fileIssues.contains(.noEntries) {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).frame(minHeight: 50)
                } else {
                    Button {
                        Task {
                            if await model.apply(review, name: name, enabled: enableImported) {
                                UIAccessibility.post(notification: .announcement, argument: "Dictionary imported")
                                dismiss()
                            }
                        }
                    } label: { Text(model.isMutating ? "Importing dictionary…" : "Import Dictionary").frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || !review.preview.canApply || !validDictionaryName(name) || review.preview.baseRevision != model.snapshot.revision)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(.bar)
        }
    }

    private func previewIndices(_ review: MyWordsImportReview) -> [Int] {
        MyWordsPresentation.sortedIndices(review.preview.entries, query: reviewSearch, sort: .original)
    }

    private func previewSection(_ review: MyWordsImportReview) -> some View {
        let indices = previewIndices(review)
        let page = MyWordsPage(total: indices.count, page: previewPage, size: 50)
        return Section {
            if indices.isEmpty {
                Text(review.preview.entries.isEmpty ? "No entries to import" : "No matching entries").font(.headline)
                Text(review.preview.entries.isEmpty ? "This file has no entries. Choose another UTF-8 .tsv or .txt file." : "Try another reading or output. Searching doesn’t change what will be imported.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(indices[page.range]), id: \.self) { index in
                let entry = review.preview.entries[index]
                WordsEntryRow(entry: entry).textSelection(.enabled)
                DisclosureGroup("Inspect Unicode Code Points") {
                    Text(codePoints(entry.output)).font(.footnote).textSelection(.enabled)
                }
            }
            WordsPager(page: page, previous: "Previous", next: "Next", value: $previewPage)
        } header: { Text("Preview") } footer: {
            VStack(alignment: .leading, spacing: 5) {
                if !indices.isEmpty {
                    Text(page.label(noun: reviewSearch.isEmpty ? "Entries" : "Matches", total: indices.count)).monospacedDigit()
                }
                Text("Search readings and outputs in this file.")
                Text("Search and page changes only affect this review. They don’t select entries to import.")
            }
        }.id("import-preview")
    }

    private func count(_ title: String, _ value: Int) -> some View {
        LabeledContent(title) { Text(value, format: .number).monospacedDigit() }
    }
    private func codePoints(_ text: String) -> String {
        text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }
}

private struct WordsPager: View {
    let page: MyWordsPage
    let previous: String
    let next: String
    @Binding var value: Int
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if page.pages > 1 {
            ViewThatFits(in: .horizontal) {
                HStack {
                    previousButton(expanded: false)
                    Spacer(minLength: 4)
                    pageLabel.fixedSize(horizontal: true, vertical: true)
                    Spacer(minLength: 4)
                    nextButton(expanded: false)
                }
                VStack(spacing: 8) {
                    pageLabel.frame(maxWidth: .infinity)
                    EqualWidthButtons(layoutDirection: layoutDirection) {
                        previousButton(expanded: true)
                        nextButton(expanded: true)
                    }
                }
                VStack(spacing: 8) {
                    pageLabel.frame(maxWidth: .infinity)
                    previousButton(expanded: true, allowsWrapping: true)
                    nextButton(expanded: true, allowsWrapping: true)
                }
            }
        }
    }

    // Report two full button widths even under a narrower proposal, so
    // ViewThatFits can reject this candidate rather than compress its labels.
    private struct EqualWidthButtons: Layout {
        let layoutDirection: LayoutDirection
        private let spacing: CGFloat = 8

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let buttonWidth = idealSizes.map(\.width).max() ?? 0
            let gaps = spacing * CGFloat(max(0, subviews.count - 1))
            let minimumWidth = buttonWidth * CGFloat(subviews.count) + gaps
            return CGSize(width: max(minimumWidth, proposal.width ?? minimumWidth),
                          height: idealSizes.map(\.height).max() ?? 0)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard !subviews.isEmpty else { return }
            let gaps = spacing * CGFloat(subviews.count - 1)
            let buttonWidth = (bounds.width - gaps) / CGFloat(subviews.count)
            for (index, subview) in subviews.enumerated() {
                let position = layoutDirection == .rightToLeft ? subviews.count - 1 - index : index
                subview.place(at: CGPoint(x: bounds.minX + CGFloat(position) * (buttonWidth + spacing) + buttonWidth / 2,
                                          y: bounds.midY),
                              anchor: .center,
                              proposal: ProposedViewSize(width: buttonWidth, height: bounds.height))
            }
        }
    }

    private var pageLabel: some View {
        Text("Page \(page.index + 1) of \(page.pages)")
            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func previousButton(expanded: Bool, allowsWrapping: Bool = false) -> some View {
        Button { value = page.index - 1 } label: {
            buttonLabel(previous, systemImage: "chevron.left", expanded: expanded, allowsWrapping: allowsWrapping)
        }
        .buttonStyle(.bordered)
        .disabled(page.index == 0)
        .accessibilityLabel(previous == "Previous Problems" ? "Previous page of problems" : "Previous page of entries")
    }

    private func nextButton(expanded: Bool, allowsWrapping: Bool = false) -> some View {
        Button { value = page.index + 1 } label: {
            buttonLabel(next, systemImage: "chevron.right", expanded: expanded, allowsWrapping: allowsWrapping)
        }
        .buttonStyle(.bordered)
        .disabled(page.index + 1 >= page.pages)
        .accessibilityLabel(next == "Next Problems" ? "Next page of problems" : "Next page of entries")
    }

    private func buttonLabel(_ title: String, systemImage: String, expanded: Bool, allowsWrapping: Bool) -> some View {
        // Keep both parts under the button's styling, not List's automatic Label icon tint.
        HStack {
            Image(systemName: systemImage)
            Text(title)
        }
        .lineLimit(allowsWrapping ? 2 : 1)
        .multilineTextAlignment(.center)
        .allowsTightening(false)
        // Horizontal candidates must report their full single-line width.
        // Only the final stacked fallback may wrap and grow vertically.
        .fixedSize(horizontal: !allowsWrapping, vertical: true)
        .frame(maxWidth: expanded ? .infinity : nil, minHeight: 44)
    }
}

private struct WordsFormatHelp: View {
    var body: some View {
        Form {
            Section {
                Text(LanguageInputCopy.format)
                Text(LanguageInputCopy.formatLines)
                Text("An optional UTF-8 byte order mark and LF or CRLF line endings are accepted.")
            }
            Section {
                Text(LanguageInputCopy.formatLimits)
                Text("Unicode code points are counted as Unicode scalars, not visible characters. A visible character can contain several code points.")
                Text(LanguageInputCopy.exactOutput)
            }
            Section {
                Text("This is Uniboard’s format. Rime files, binary dictionaries and archives aren’t supported.")
                Text("MSIME files and YAML aren’t supported. Links in an entry are only text; importing never opens or downloads them.")
            }
            Section {
                Text(LanguageInputCopy.duplicates)
                Text(LanguageInputCopy.combined)
                Text("Large exports may contain several files. Import each part separately; each part creates its own dictionary.")
            }
        }
        .textSelection(.enabled)
        .navigationTitle("Dictionary File Format").navigationBarTitleDisplayMode(.inline)
    }
}

/// UITextView exposes the smart punctuation and spellcheck switches that
/// SwiftUI TextField doesn't. Only entry fields use this exact-text editor.
@MainActor
private struct WordsExactTextEditor: UIViewRepresentable {
    @Binding var text: String
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .default
        view.accessibilityLabel = label
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if !view.text.utf8.elementsEqual(text.utf8) { view.text = text }
        view.accessibilityLabel = label
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, fit.height))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}

@MainActor
private struct WordsShareView: UIViewControllerRepresentable {
    let share: MyWordsShare
    let model: MyWordsModel
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: share.urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in Task { await model.cleanShare(share) } }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: ()) {
        // Completion handles ordinary dismissal. Files are temporary and never
        // become part of the persistent dictionary snapshot.
    }
}
