import SwiftUI

/// The removal surface for both imported/downloaded files and saved references.
/// No destructive action is offered until membership and references were read.
struct FontFileDetailView: View {
    var filename: String? = nil
    var receiptID: String? = nil
    @StateObject private var model = FontFileManagementModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = UUID()
    @State private var confirmation: FontFileManagementModel.Confirmation?
    @State private var confirming = false
    @State private var editingRule: FontRule?

    private var entry: FontManagedEntry? {
        model.snapshot?.entries.first { value in
            filename.map { value.filename == $0 } ?? receiptID.map { value.receiptIDs.contains($0) } ?? false
        }
    }

    var body: some View {
        Form {
            if model.loading {
                ProgressView("Loading your fonts…")
            }
            if let error = model.error {
                Section {
                    Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                    Button("Try Again") { refresh = UUID() }
                }
            }
            if let entry {
                fileSection(entry)
                Section("Styles") {
                    ForEach(entry.faces) { face in FontManagedStyleRow(face: face) }
                }
                referencesSection(entry)
                Section {
                    Button(removeTitle(entry), role: .destructive) {
                        Task {
                            // Refresh before asking, not only after the person confirms.
                            await model.reload()
                            guard let current = self.entry, let value = model.confirmation(for: current) else { return }
                            confirmation = value
                            confirming = true
                        }
                    }
                    .disabled(model.loading || model.removing || model.rules == nil)
                    .accessibilityIdentifier("fontFile.remove")
                    if model.removing { ProgressView("Removing font…") }
                } footer: {
                    if !entry.installed { Text(FontFileManagementCopy.retained) }
                }
            } else if !model.loading && model.error == nil {
                Text("This font is no longer in Your Fonts.")
            }
        }
        .navigationTitle(entry?.displayName ?? "Font Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refresh) { await model.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh = UUID() } }
        .onReceive(NotificationCenter.default.publisher(for: .fontExplorationLibraryChanged)) { _ in
            if !model.removing { refresh = UUID() }
        }
        .sheet(item: $editingRule, onDismiss: { refresh = UUID() }) { rule in
            FontRuleEditorView(draft: FontRuleDraft(editing: rule))
        }
        .confirmationDialog(confirmation?.entry.installed == true ? "Stop using this font?" : "Stop using this font file?",
                            isPresented: $confirming, titleVisibility: .visible) {
            if let confirmation {
                Button(confirmation.entry.installed ? "Stop Using Font" : "Remove File", role: .destructive) {
                    Task { if await model.remove(confirmation) { dismiss() } }
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            if let confirmation { Text(removalMessage(confirmation)) }
        }
    }

    private func fileSection(_ entry: FontManagedEntry) -> some View {
        let keyboard = KeyboardFontEvidenceCache.status(of: entry)
        return Section {
            if entry.installed {
                Text("Installed on This Device")
            } else {
                LabeledContent("File Size", value: FontFileManagementCopy.size(entry.verifiedBytes))
                LabeledContent("Styles", value: "\(entry.styleCount)")
            }
            if let value = keyboard?.detailValue {
                LabeledContent("Keyboard") {
                    Text(value).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Keyboard")
                .accessibilityValue(keyboard?.detailAccessibilityValue ?? value)
            }
        } header: {
            Text(entry.installed ? "Installed Font" : "File")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let footer = keyboard?.detailFooter { Text(footer) }
                Text("Fonts change the preview here. Other apps choose how inserted text looks.")
                if !entry.installed && entry.styleCount > 1 { Text("Includes \(entry.styleCount) styles in one file.") }
            }
        }
    }

    @ViewBuilder private func referencesSection(_ entry: FontManagedEntry) -> some View {
        Section("Used by Font Rules") {
            if let error = model.rulesError {
                Text(error)
                Button("Try Again") { refresh = UUID() }
            } else if let rules = model.rules, let snapshot = model.snapshot {
                let uses = snapshot.references(to: entry, rules: rules)
                if uses.isEmpty { Text(entry.installed ? "No font rules use this font." : "No font rules use this file.") }
                ForEach(uses) { use in
                    Button {
                        FontRulePreferences.shared.reload()
                        if let current = FontRulePreferences.shared.rule(id: use.id) { editingRule = current }
                        else { refresh = UUID() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FontFileManagementCopy.ruleTitle(use.rule)).foregroundStyle(.primary)
                            Text(use.styles.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                            if !use.otherFilenames.isEmpty {
                                Text("Also included in another font file.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Opens this font rule for editing.")
                }
            } else { ProgressView("Checking font rules…") }
        }
    }

    private func removeTitle(_ entry: FontManagedEntry) -> String {
        entry.installed ? "Stop Using Font" : entry.styleCount > 1 ? "Remove File (\(entry.styleCount) Styles)" : "Remove File"
    }

    private func removalMessage(_ value: FontFileManagementModel.Confirmation) -> String {
        var text = value.entry.installed
            ? "This stops using the font in Uniboard. It doesn’t uninstall the font from this device."
            : "This file will no longer provide styles in Uniboard. Styles available from other files will stay available."
        if !value.uses.isEmpty {
            text += "\n\nUsed by Font Rules: " + value.uses.map { FontFileManagementCopy.ruleTitle($0.rule) }.joined(separator: ", ")
            text += "\n\n" + FontFileManagementCopy.rulesKept
        }
        if !value.entry.installed { text += "\n\n" + FontFileManagementCopy.retained }
        return text
    }
}

/// Exact face rendering when verified, otherwise honest system-text metadata.
private struct FontManagedStyleRow: View {
    let face: FontFaceRecord
    @State private var font: UIFont?
    var body: some View {
        Text(face.style)
            .font(font.map { Font($0) } ?? .body)
            .task(id: face) {
                font = nil
                guard let reference = FontFaceReference(record: face) else { return }
                let work = Task.detached(priority: .utility) { () -> LoadedRuleFont? in
                    guard !Task.isCancelled else { return nil }
                    return try? UnicodeFontSupport.ruleFaceLoader.load(reference).get()
                }
                let loaded = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled else { return }
                font = loaded?.font(size: UIFont.preferredFont(forTextStyle: .body).pointSize)
            }
    }
}

/// Native Form sections embedded in the existing Font Downloads screen.
struct YourFontManagementSections: View {
    @ObservedObject var model: FontFileManagementModel
    let importing: () -> Void
    let pickingInstalled: () -> Void

    var body: some View {
        Section {
            if let snapshot = model.snapshot {
                capacity(snapshot)
                Text("\(snapshot.files.count) \(snapshot.files.count == 1 ? "font file" : "font files") · \(snapshot.installed.count) \(snapshot.installed.count == 1 ? "installed font" : "installed fonts")")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(FontFileManagementCopy.remaining(CustomFontStore.maximumFonts - snapshot.used)).font(.footnote).foregroundStyle(.secondary)
                if !snapshot.files.isEmpty {
                    LabeledContent("Total File Size", value: FontFileManagementCopy.size(snapshot.verifiedTotalBytes))
                }
            } else if model.loading { ProgressView("Loading your fonts…") }
            if let error = model.error {
                Text(error)
                Button("Try Again") { Task { await model.reload() } }
            }
            Button(action: importing) { Label("Add Font File", systemImage: "doc.badge.plus") }
                .disabled(model.snapshot == nil || model.loading || (model.snapshot?.used ?? 16) >= CustomFontStore.maximumFonts)
                .accessibilityIdentifier("fontDownloads.addFont")
            Button(action: pickingInstalled) { Label("Use Installed Font", systemImage: "textformat") }
                .disabled(model.snapshot == nil || model.loading || (model.snapshot?.used ?? 16) >= CustomFontStore.maximumFonts)
                .accessibilityIdentifier("fontDownloads.useInstalled")
        } header: { Text("Your Fonts") } footer: {
            Text("Each added font file or installed font counts once. A file can contain several styles.")
        }
        if let snapshot = model.snapshot {
            if !snapshot.files.isEmpty {
                Section("Font Files") { ForEach(snapshot.files) { entry in fileRow(entry) } }
            }
            if !snapshot.installed.isEmpty {
                Section("Installed Fonts") { ForEach(snapshot.installed) { entry in fileRow(entry) } }
            }
            if snapshot.entries.isEmpty {
                Section { Text("No fonts added") } footer: { Text("Browse Google Fonts or add a font file.") }
            }
        }
    }

    private func fileRow(_ entry: FontManagedEntry) -> some View {
        NavigationLink { FontFileDetailView(filename: entry.filename) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                Text(entry.installed ? "Installed on This Device" : "1 file · \(FontFileManagementCopy.styles(entry.styleCount)) · \(FontFileManagementCopy.size(entry.verifiedBytes))")
                    .font(.footnote).foregroundStyle(.secondary)
                if let keyboard = KeyboardFontEvidenceCache.status(of: entry) {
                    KeyboardFontTag(status: keyboard)
                }
            }
        }
        .accessibilityIdentifier("fontDownloads.custom.\(entry.filename)")
    }

    private func capacity(_ snapshot: FontManagementSnapshot) -> some View {
        VStack(spacing: 8) {
            LabeledContent("Font Capacity") { Text("\(snapshot.used) of 16").monospacedDigit() }
            HStack(spacing: 2) {
                ForEach(0..<CustomFontStore.maximumFonts, id: \.self) { index in
                    Capsule()
                        .fill(index < snapshot.files.count ? Color.accentColor : index < snapshot.used ? Color.accentColor.opacity(0.45) : Color(uiColor: .quaternaryLabel))
                        .overlay { if index >= snapshot.files.count && index < snapshot.used { Capsule().stroke(Color.accentColor, lineWidth: 1) } }
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Font Capacity")
        .accessibilityValue(FontFileManagementCopy.capacity(files: snapshot.files.count, installed: snapshot.installed.count))
        .accessibilityIdentifier("fontDownloads.capacity")
    }

}
