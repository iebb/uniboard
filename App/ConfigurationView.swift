import SwiftUI
import UniformTypeIdentifiers

/// Settings → Configuration (design.md §6): export, import, edit
/// (design/config-editor/design.md) and undo.
struct ConfigurationView: View {
    @State private var exporting = false
    @State private var exportCaption: String?
    @State private var exportFailed = false
    @State private var choosingFile = false
    @State private var importModel: ConfigurationImportModel?
    @State private var editorModel: ConfigurationEditorModel?
    /// The editor being shown, still readable in the sheet's onDismiss (which runs after the item is cleared).
    @State private var lastEditor: ConfigurationEditorModel?
    @State private var undoStatus: ConfigurationUndoStatus?
    @State private var confirmingUndo = false
    @State private var undoCaption: String?
    @State private var undoFailure: ConfigurationUndo.Result?
    @State private var captionTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Button(action: export) {
                    HStack {
                        rowLabel(ConfigurationCopy.export, symbol: "square.and.arrow.up",
                                 caption: exporting ? ConfigurationCopy.preparing : exportCaption)
                        Spacer()
                        if exporting { ProgressView() }
                    }
                }
                .disabled(exporting)
                .accessibilityIdentifier("configuration.export")
                Button { chooseFile() } label: {
                    rowLabel(ConfigurationCopy.importTitle, symbol: "square.and.arrow.down", caption: nil)
                }
                .disabled(exporting)
                .accessibilityIdentifier("configuration.import")
                Button(action: openEditor) {
                    rowLabel(ConfigurationCopy.edit, symbol: "square.and.pencil", caption: nil)
                }
                .disabled(exporting)
                .accessibilityIdentifier("configuration.edit")
                if let undoStatus {
                    Button { confirmingUndo = true } label: {
                        rowLabel(ConfigurationCopy.undo, symbol: "arrow.uturn.backward",
                                 caption: undoStatus.importedAt.map { ConfigurationCopy.changedAt($0, source: undoStatus.source) })
                    }
                    .accessibilityIdentifier("configuration.undo")
                    // Anchored to the row, not the top of the form.
                    .confirmationDialog(ConfigurationCopy.undoTitle, isPresented: $confirmingUndo, titleVisibility: .visible) {
                        Button(ConfigurationCopy.restore, role: .destructive, action: undo)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(ConfigurationCopy.undoBody)
                    }
                }
            } header: {
                Text(ConfigurationCopy.header)
                    .font(.footnote.weight(.regular))
                    .textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let undoCaption {
                        Text(undoCaption).foregroundStyle(.primary).accessibilityIdentifier("configuration.undoCaption")
                    }
                    Text(ConfigurationCopy.privacy)
                    Text(ConfigurationCopy.portability)
                    Text(ConfigurationCopy.keyboardColors).accessibilityIdentifier("configuration.keyboardColors")
                }
            }
        }
        .accessibilityIdentifier("configurationForm")
        .navigationTitle(ConfigurationCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshUndo)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.uniboardConfiguration, .plainText]) { result in
            guard case let .success(url) = result else { return }
            let model = ConfigurationImportModel(fileName: url.lastPathComponent, environment: .live)
            importModel = model
            Task { await model.load(url) }
        }
        .sheet(item: $importModel, onDismiss: refreshUndo) { model in
            ReviewImportView(model: model)
        }
        .sheet(item: $editorModel, onDismiss: editorClosed) { model in
            ConfigurationEditorView(model: model)
        }
        .alert(ConfigurationCopy.exportFailed, isPresented: $exportFailed) {
            Button(ConfigurationCopy.tryAgain, action: export)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ConfigurationCopy.exportFailedBody)
        }
        .alert(ConfigurationCopy.restoreFailed, isPresented: Binding(get: { undoFailure != nil }, set: { if !$0 { undoFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(undoFailure == .failed ? ConfigurationCopy.unchanged : ConfigurationCopy.unconfirmedBody)
        }
    }

    private func rowLabel(_ title: String, symbol: String, caption: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    // Gray, not the row's tint (design.md §6).
                    Text(caption).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
        .frame(minHeight: 44)
    }

    private func refreshUndo() {
        undoStatus = ConfigurationService().undoStatus()
    }

    private func openEditor() {
        let model = ConfigurationEditorModel.live()
        lastEditor = model
        editorModel = model
    }

    /// The editor closed: after an apply, say so and offer Undo.
    private func editorClosed() {
        refreshUndo()
        if let model = lastEditor, model.didApply { show(ConfigurationCopy.applied, in: .undo) }
        lastEditor = nil
    }

    private func chooseFile() {
#if DEBUG
        if let fixture = ConfigurationFixtures.importData() {
            let model = ConfigurationImportModel(fileName: fixture.name, environment: .live)
            importModel = model
            Task { await model.check(fixture.data) }
            return
        }
#endif
        choosingFile = true
    }

    private func export() {
        exporting = true
        exportCaption = nil
        let service = ConfigurationService()
        let configuration = service.current().configuration
        let fonts = CustomFontStore.shared.fonts
        Task {
            let url = await Task.detached { () -> URL? in
                guard let data = ConfigurationCodec.encode(configuration, inLibrary: { ConfigurationService.inLibrary($0, fonts: fonts) })
                else { return nil }
                return try? ConfigurationService.writeExport(data)
            }.value
            exporting = false
            guard let url, ConfigurationShareSheet.present(url, completion: { show(ConfigurationCopy.ready, in: .export) },
                                                            dismissed: { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
            else {
                exportFailed = true
                return
            }
        }
    }

    private func undo() {
        guard let status = undoStatus else { return }
        let service = ConfigurationService()
        let result = ConfigurationUndo.run(
            status: status, presentation: service.presentation,
            undo: { service.location.undoLastImport(expecting: $0, currentPresentation: $1) },
            currentFingerprint: { service.location.currentFingerprint(presentation: $0) },
            adopt: { service.adoptCurrentConfiguration() })
        refreshUndo()
        if result == .restored {
            show(ConfigurationCopy.restored, in: .undo)
            UIAccessibility.post(notification: .announcement, argument: ConfigurationCopy.restored)
        } else {
            undoFailure = result
        }
    }

    private enum Caption { case export, undo }

    /// A caption shown for 3 s.
    private func show(_ caption: String, in place: Caption) {
        captionTask?.cancel()
        exportCaption = place == .export ? caption : nil
        undoCaption = place == .undo ? caption : nil
        captionTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            exportCaption = nil
            undoCaption = nil
        }
    }
}
