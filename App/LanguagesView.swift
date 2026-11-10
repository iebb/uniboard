import SwiftUI
import UIKit

@MainActor
struct LanguagesView: View {
    @ObservedObject var model: LanguageManagementModel
    @ObservedObject var wordsModel: MyWordsModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var languageHints = LanguageSuggestionPolicy.Snapshot.empty
    @State private var isVisible = false

    private var suggestions: [LanguageSuggestionPolicy.Suggestion] {
        languageHints.suggestions.filter { suggestion in
            switch suggestion.language {
            case .japanese: return !model.isEnabled(.japaneseRomaji)
            case .mandarin: return !model.isEnabled(.mandarinPinyin)
            case .korean: return !model.isEnabled(.koreanRomaja) || !model.isEnabled(.koreanTwoSetHangul)
            }
        }
    }

    var body: some View {
        List {
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.language) { suggestion in
                        NavigationLink {
                            switch suggestion.language {
                            case .japanese: detail(.japaneseRomaji)
                            case .mandarin: detail(.mandarinPinyin)
                            case .korean: koreanMethods
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                switch suggestion.language {
                                case .japanese: Text(LanguageInputMode.japaneseRomaji.title)
                                case .mandarin: Text(LanguageInputMode.mandarinPinyin.title)
                                case .korean:
                                    Text("Korean")
                                    Text("Choose Romaja or Two-Set Hangul.").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text(suggestion.provenance == .activeKeyboard ? "Matches an active keyboard language." : "Matches a preferred language on this device.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                if suggestion.language == .japanese { Text(model.status(.japaneseRomaji)).font(.footnote).foregroundStyle(.secondary) }
                                if suggestion.language == .mandarin { Text(model.status(.mandarinPinyin)).font(.footnote).foregroundStyle(.secondary) }
                                if suggestion.language == .korean { Text("Two-Set Hangul: \(model.status(.koreanTwoSetHangul))").font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } header: { Text("Suggested Languages") } footer: {
                    Text("Suggested from language information on this device. Nothing downloads or switches automatically. The language hints used for these suggestions stay on this device.")
                }
            }
            Section("Input Mode") {
                ForEach(LanguageInputSettings.modeOrder, id: \.self) { mode in
                    if model.canSelect(mode) {
                        Button { model.select(mode) } label: { modeRow(mode) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink { detail(mode) } label: { modeRow(mode) }
                    }
                }
            }
            infoSection
            Section {
                if model.catalog == nil {
                    if model.isChecking { ProgressView("Checking download…") }
                    else {
                        Label("Language-download information couldn’t be loaded.", systemImage: "exclamationmark.triangle")
                        Button("Try Again") { model.refresh() }.disabled(model.hasOperation)
                    }
                }
                NavigationLink { detail(.japaneseRomaji) } label: {
                    downloadRow(.japaneseRomaji, name: "Japanese Dictionary", bytes: model.catalog?.japanese.archiveByteCount)
                }
                NavigationLink { detail(.mandarinPinyin) } label: {
                    downloadRow(.mandarinPinyin, name: "Mandarin Vocabulary Sources", bytes: model.catalog?.mandarinDownloadBytes)
                }
                NavigationLink { detail(.koreanTwoSetHangul) } label: {
                    downloadRow(.koreanTwoSetHangul, name: "Korean Two-Set Hangul Resources", bytes: model.catalog?.koreanTwoSet?.archiveByteCount)
                }
            } header: { Text("Language Downloads") } footer: {
                Text("Language downloads are optional. Downloading doesn’t enable or select an input mode. Downloaded language files require Full Access in the keyboard. Conversion uses local data; the containing app contacts the named source hosts only to download resources. The keyboard doesn’t download resources.")
            }
            if LanguageInputSettings.englishAssistanceAvailable {
                Section("English") {
                    NavigationLink { EnglishLanguageSettingsView(model: model) } label: {
                        LabeledContent("English Autocorrection", value: model.preferences.englishAutocorrection ? "On" : "Off")
                    }
                }
            }
            Section("Your Words") {
                NavigationLink { MyWordsView(model: wordsModel) } label: {
                    Label("My Words", systemImage: "text.book.closed")
                }
            }
            if let notice = model.notice {
                Section { Label(notice, systemImage: "info.circle").font(.footnote) }
            }
        }
        .navigationTitle("Languages")
        .onAppear { isVisible = true; languageHints = LanguageSuggestionReader().refresh(); model.refresh() }
        .onDisappear { isVisible = false; languageHints = .empty }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isVisible { languageHints = LanguageSuggestionReader().refresh(); model.refresh() }
        }
        .refreshable { model.refresh() }
        .alert("Language Settings", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var koreanMethods: some View {
        List {
            Section {
                NavigationLink { detail(.koreanRomaja) } label: { modeRow(.koreanRomaja) }
                NavigationLink { detail(.koreanTwoSetHangul) } label: { modeRow(.koreanTwoSetHangul) }
            } footer: { Text("Each input method is turned on separately.") }
            Section("Language Download") {
                NavigationLink { detail(.koreanTwoSetHangul) } label: {
                    downloadRow(.koreanTwoSetHangul, name: "Korean Two-Set Hangul Resources", bytes: model.catalog?.koreanTwoSet?.archiveByteCount)
                }
            }
        }.navigationTitle("Korean").navigationBarTitleDisplayMode(.inline)
    }

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Full Access required").font(.headline)
                Text("Allow Full Access so the keyboard can read downloaded language files shared by the app. Your typing stays on this device. Direct Typing works without Full Access.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detail(_ mode: LanguageInputMode) -> some View {
        LanguageModeDetailView(model: model, wordsModel: wordsModel, mode: mode)
    }

    private func modeRow(_ mode: LanguageInputMode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if mode == .koreanTwoSetHangul || mode == .koreanRomaja {
                VStack(spacing: 0) {
                    Text("가").font(.body)
                    if mode == .koreanRomaja { Text("Aa").font(.caption2) }
                }.frame(width: 28).accessibilityHidden(true)
            } else {
                Image(systemName: mode == .direct ? "keyboard" : "character.bubble")
                    .frame(width: 28).padding(.top, 3).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title).foregroundStyle(.primary)
                if mode != .koreanRomaja { Text(mode.summary).font(.subheadline).foregroundStyle(.secondary) }
                Text(mode.nativeLabel).font(.subheadline).foregroundStyle(.secondary)
                Text(model.status(mode)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if model.selectedMode == mode {
                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected")
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(model.selectedMode == mode ? .isSelected : [])
    }

    private func downloadRow(_ mode: LanguageInputMode, name: String, bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
            Text(bytes.map { "Download Size: \(languageExactBytes($0))" } ?? "Download Size: Size unavailable")
                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            if let pack = model.installed[mode] {
                Text("Installed Size: \(languageExactBytes(pack.descriptor.installedBytes))")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            if model.resourceProblems[mode] != nil {
                Label { Text(model.status(mode)).font(.footnote) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            } else { Text(model.status(mode)).font(.footnote).foregroundStyle(.secondary) }
        }.frame(minHeight: 52)
    }
}

@MainActor
private struct LanguageModeDetailView: View {
    @ObservedObject var model: LanguageManagementModel
    @ObservedObject var wordsModel: MyWordsModel
    let mode: LanguageInputMode
    @State private var confirmsRemoval = false
    @State private var removalPublication: LanguagePackStore.RemovablePublication?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            problemCard
            Section {
                if mode == .koreanRomaja {
                    Label("Korean spelling is awaiting a decision. This input mode isn’t available yet.", systemImage: "exclamationmark.triangle")
                    Text("The Romaja Typing Guide and availability will be updated after that decision. Two-Set Hangul is a separate input method with its own download.")
                } else {
                    Text(mode.summary)
                    Text(model.status(mode)).font(.subheadline)
                    if model.selectedMode == mode { Label("Selected in this session", systemImage: "checkmark") }
                    if mode != .direct {
                        Toggle("Use in Keyboard", isOn: Binding(get: { model.isEnabled(mode) }, set: { model.setEnabled($0, for: mode) }))
                            .disabled(!model.isReady(mode) || model.hasOperation)
                    }
                    if model.canSelect(mode) {
                        Button("Select Input Mode") { model.select(mode) }
                    }
                }
            } footer: {
                if mode != .direct && mode != .koreanRomaja {
                    Text("Downloading and enabling are separate choices. Selecting here is session-only; the keyboard’s own mode selection is independent.")
                }
            }
            if mode == .japaneseRomaji { japaneseDownload }
            if mode == .mandarinPinyin { mandarinDownload }
            if mode == .koreanTwoSetHangul { koreanDownload }
            if mode != .koreanRomaja {
                Section("Typing") {
                    NavigationLink { LanguageTypingGuideView(mode: mode) } label: {
                        Label("Typing Guide", systemImage: "questionmark.circle")
                    }
                    if mode == .mandarinPinyin {
                        LabeledContent("Output", value: "Simplified")
                        Text("Traditional output isn’t available. The current Simplified mapping is a conservative subset, not full OpenCC t2s.").font(.footnote)
                    }
                    if mode != .direct && LanguageInputSettings.englishAssistanceAvailable {
                        Text("Language conversion choices are separate from English autocorrection.").font(.footnote)
                    }
                }
                if mode != .koreanTwoSetHangul {
                Section {
                    NavigationLink { MyWordsView(model: wordsModel, initialMode: mode) } label: {
                        Label("My Words for This Mode", systemImage: "text.book.closed")
                    }
                }
                }
            }
            if mode == .direct && LanguageInputSettings.englishAssistanceAvailable {
                Section {
                    NavigationLink("English Autocorrection") { EnglishLanguageSettingsView(model: model) }
                }
            }
            if model.canRemove(mode) && model.resourceProblems[mode] == nil {
                Section { removeButton }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.checkStorage(for: mode) }
        .onChange(of: model.isChecking) { _, checking in if !checking { model.checkStorage(for: mode) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.checkStorage(for: mode) } }
        .onChange(of: model.operation) { old, new in
            guard model.operatingMode == mode else { return }
            if case .retrying(let attempt) = new {
                UIAccessibility.post(notification: .announcement, argument: "Waiting to try again. Retry \(attempt) of 2")
            } else if case .compiling(let progress) = new {
                let oldPhase: String? = { if case .compiling(let previous) = old { return compilationPhase(previous) }; return nil }()
                let phase = compilationPhase(progress)
                if oldPhase != phase { UIAccessibility.post(notification: .announcement, argument: phase) }
            }
        }
        .confirmationDialog("Remove this language download?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                if let publication = removalPublication { model.remove(publication) }
                removalPublication = nil
            }
            Button("Cancel", role: .cancel) { removalPublication = nil }
        } message: {
            Text("\(mode.title) won’t be available until you download its resources again. Your words in My Words will be kept. Some files may remain until the keyboard stops using them.")
        }
    }

    private var removeButton: some View {
        Button("Remove Download", role: .destructive) {
            removalPublication = model.removalRequest(for: mode)
            confirmsRemoval = removalPublication != nil
        }.disabled(model.hasOperation)
    }

    @ViewBuilder private var problemCard: some View {
        if let problem = model.resourceProblems[mode] {
            Section {
                if model.operatingMode == mode && model.operation == .removing {
                    ProgressView("Removing download…")
                } else {
                    Label { Text(problem).font(.headline) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text(problem == "Download couldn’t be verified"
                         ? "These language files couldn’t be verified. Remove the download before downloading it again. Your words in My Words will be kept."
                         : problem == "Compatible download required"
                         ? "This download isn’t compatible with this version of Uniboard. Remove it before downloading compatible language files. Your words in My Words will be kept."
                         : "Uniboard couldn’t read these language files. Try again. Your words in My Words haven’t been changed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.canRemove(mode) { removeButton }
                    else { Button("Try Again") { model.refresh() }.disabled(model.hasOperation) }
                }
            }
        }
    }

    private var canDownload: Bool {
        model.storage[mode]?.permitsDownload == true && model.resourceProblems[mode] == nil
    }

    @ViewBuilder private var storageRows: some View {
        let state = model.storage[mode] ?? .checking
        LabeledContent("Estimated Space Needed", value: state.requiredBytes.map(languageStorageBytes) ?? "Size unavailable")
        LabeledContent("Available Storage", value: state.availableBytes.map(languageStorageBytes) ?? "Unavailable")
        switch state {
        case .checking: ProgressView("Checking storage…").accessibilityLabel("Checking storage for \(mode.title)")
        case .requirementUnknown:
            storageWarning("Space needed is unavailable", body: "Uniboard couldn’t determine how much space this download needs, including temporary space. Try again before downloading.")
        case .assessed(.unknown):
            storageWarning("Couldn’t check available storage", body: "Uniboard couldn’t check how much space is available. Preparing this download also needs temporary space.")
        case .assessed(.insufficient):
            storageWarning("Not enough storage", body: "There isn’t enough storage to download and prepare these language files. Free some space and try again.")
        case .assessed(.sufficient):
            Label("Storage check passed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            Text("The last check found enough space for this estimate. Available storage can change before the download finishes.").font(.footnote).foregroundStyle(.secondary)
        }
        Text("Includes the download, installed files, and temporary space needed to prepare them.").font(.footnote).foregroundStyle(.secondary)
    }

    private func storageWarning(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(title).font(.subheadline).bold() } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            Text(body).font(.footnote).foregroundStyle(.secondary)
            Button("Try Again", systemImage: "arrow.clockwise") { model.checkStorage(for: mode) }.disabled(model.hasOperation)
        }
    }

    @ViewBuilder private var koreanDownload: some View {
        Section("Language Download") {
            Text("Korean Two-Set Hangul Resources").font(.headline)
            if let descriptor = model.catalog?.koreanTwoSet {
                metadata("Version", descriptor.version)
                metadata("Download Size", languageExactBytes(descriptor.archiveByteCount))
                metadata("Installed Size", languageExactBytes(descriptor.installedBytes))
                storageRows
                NavigationLink {
                    LanguageSourceView(title: "Source", notice: descriptor.sourceNotice, files: [
                        .init(name: "Two-Set Hangul data", url: descriptor.sourceURL, bytes: descriptor.archiveByteCount, sha256: descriptor.archiveSHA256)
                    ])
                } label: { Label("Source · uniboard.ieb.app", systemImage: "link") }
                NavigationLink { LanguageNoticeView(title: "License", text: descriptor.licenseNotice) } label: {
                    Label("License · MIT", systemImage: "doc.text")
                }
                Text("Small key-mapping data only. No dictionary, predictions, Hanja, or downloaded executable code. My Words doesn’t apply to Two-Set Hangul.").font(.footnote).foregroundStyle(.secondary)
                operationRows
                if !model.hasOperation && model.cancelledMode != mode && model.installed[mode]?.descriptor != descriptor {
                    Button(model.failures[mode] == nil ? "Download" : "Try Again") { model.downloadKoreanTwoSet() }.disabled(!canDownload)
                }
            } else {
                Text("Download is unavailable until size, source and license information can be read.").font(.footnote)
                Button("Try Again") { model.refresh() }.disabled(model.hasOperation)
            }
        }
    }

    @ViewBuilder private var japaneseDownload: some View {
        Section("Language Download") {
            if let descriptor = model.catalog?.japanese {
                Text("azooKey Japanese Dictionary").font(.headline)
                metadata("Version", descriptor.version)
                metadata("Download Size", languageExactBytes(descriptor.archiveByteCount))
                metadata("Installed Size", languageExactBytes(descriptor.installedBytes))
                storageRows
                Text("Installed size includes 25,593,074 dictionary bytes and 11,342 license bytes. Staging and filesystem overhead need additional space.").font(.footnote).foregroundStyle(.secondary)
                NavigationLink { LanguageSourceView(title: "Source", notice: descriptor.sourceNotice, files: [
                    .init(name: "Pinned Japanese archive", url: descriptor.sourceURL, bytes: descriptor.archiveByteCount, sha256: descriptor.archiveSHA256)
                ]) } label: { Label("Source · codeload.github.com", systemImage: "link") }
                NavigationLink { LanguageNoticeView(title: "License", text: descriptor.licenseNotice) } label: {
                    Label("License · Apache-2.0", systemImage: "doc.text")
                }
                NavigationLink {
                    LanguageNoticeView(title: "Japanese Engine Licenses", text: model.catalog?.japaneseEngineNotices
                        ?? "Japanese engine license notices couldn’t be read from the app. Return to Languages and try again.")
                } label: {
                    Label("Japanese Engine Licenses", systemImage: "doc.text")
                }
                operationRows
                if let current = model.installed[mode] {
                    Label("Current version · Ready to use", systemImage: "checkmark.circle.fill")
                    metadata("Current Installed Size", languageExactBytes(current.descriptor.installedBytes))
                }
                if !model.hasOperation && model.cancelledMode != mode {
                    if let current = model.installed[mode] {
                        if current.descriptor != descriptor {
                            Button("Download Update") { model.downloadJapanese() }.disabled(!canDownload)
                        } else if model.failures[mode] != nil {
                            Button("Try Again") { model.downloadJapanese() }.disabled(!canDownload)
                        }
                    } else {
                        Button { model.downloadJapanese() } label: {
                            Label(model.failures[mode] == nil ? "Download" : "Try Again", systemImage: model.failures[mode] == nil ? "arrow.down.circle" : "arrow.clockwise")
                        }
                        .disabled(!canDownload)
                    }
                }
            } else {
                ProgressView("Checking download…")
                Text("Download is unavailable until size, source and license information can be read.").font(.footnote)
                Button("Try Again") { model.refresh() }.disabled(model.hasOperation)
            }
        }
    }

    @ViewBuilder private var mandarinDownload: some View {
        Section("Language Download") {
            Text("Wanxiang Mandarin Vocabulary").font(.headline)
            if let catalog = model.catalog {
                metadata("Version", MandarinDictionaryCompiler.corpusCommit)
                metadata("Download Size", languageExactBytes(catalog.mandarinDownloadBytes))
                Text("Mandarin is an optional download containing two vocabulary files and three character-conversion files. All five are downloaded together and checked before use. Nothing downloads automatically.").font(.footnote).foregroundStyle(.secondary)
                if let databaseBytes = model.mandarinDatabaseBytes {
                    metadata("Installed Size", languageExactBytes(catalog.mandarinInstalledBytes(databaseBytes: databaseBytes)))
                    Text("Dictionary and license payload bytes. Source staging, compilation and filesystem overhead require additional temporary space.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    metadata("Installed Size", "Size verification pending")
                }
                storageRows
                NavigationLink { LanguageSourceView(title: "Source", notice: catalog.mandarinSource, files: catalog.mandarinFiles) } label: {
                    Label("Source · raw.githubusercontent.com", systemImage: "link")
                }
                NavigationLink { LanguageNoticeView(title: "License", text: catalog.mandarinLicense) } label: {
                    Label("License · CC BY 4.0 and Apache-2.0", systemImage: "doc.text")
                }
                if let current = model.installed[mode] {
                    Label("Current version · Ready to use", systemImage: "checkmark.circle.fill")
                    metadata("Current Installed Size", languageExactBytes(current.descriptor.installedBytes))
                }
                operationRows
                if model.mandarinDatabaseBytes == nil {
                    Label("Installation size verification pending", systemImage: "exclamationmark.triangle")
                    Text("Download is unavailable until the full-corpus compilation’s installed size has been verified. Existing verified installations are kept.").font(.footnote)
                } else if !model.hasOperation && model.cancelledMode != mode {
                    Button { model.downloadMandarin() } label: {
                        Label(model.failures[mode] != nil ? "Try Again" : (model.installed[mode] == nil ? "Download" : "Download Again"),
                              systemImage: model.failures[mode] != nil ? "arrow.clockwise" : "arrow.down.circle")
                    }
                    .disabled(!canDownload)
                }
            } else {
                Text("Size unavailable")
                Button("Try Again") { model.refresh() }.disabled(model.hasOperation)
            }
        }
    }

    private var downloadTotal: Int64? {
        switch mode {
        case .mandarinPinyin: return model.catalog?.mandarinDownloadBytes
        case .japaneseRomaji: return model.catalog?.japanese.archiveByteCount
        case .koreanTwoSetHangul: return model.catalog?.koreanTwoSet?.archiveByteCount
        case .direct, .koreanRomaja: return nil
        }
    }

    @ViewBuilder private var operationRows: some View {
        if model.operatingMode == mode {
            if model.isCancelling { ProgressView("Cancelling download…") } else {
            switch model.operation {
            case .downloading(let fraction):
                if fraction == 0 && model.retryAttempt > 0 {
                    ProgressView("Trying again…")
                    Text("Retry \(model.retryAttempt) of 2").font(.subheadline).foregroundStyle(.secondary)
                } else {
                ProgressView(value: fraction) { Text("Downloading… \(Int(fraction * 100))%") }
                    .monospacedDigit()
                    .accessibilityValue("\(Int(fraction * 100)) percent of \(languageExactBytes(downloadTotal ?? 0))")
                if let total = downloadTotal {
                    Text("Approximately \(languageExactBytes(Int64(Double(total) * fraction))) of \(languageExactBytes(total)) received")
                        .font(.footnote).monospacedDigit()
                }
                }
            case .waiting: ProgressView("Waiting")
            case .checkingStorage: ProgressView("Checking storage…")
            case .retrying(let attempt):
                HStack {
                    ProgressView("Waiting to try again…")
                    Spacer()
                    Text("Retry \(attempt) of 2").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }.accessibilityElement(children: .combine)
                Text("The download was interrupted. Uniboard will try again shortly.").font(.footnote).foregroundStyle(.secondary)
            case .verifying: ProgressView("Checking download…")
            case .compiling(let progress): compilationRows(progress)
            case .activating: ProgressView("Installing language download…")
            case .removing: ProgressView("Removing download…")
            case .idle: EmptyView()
            }
            }
            if model.operation.canCancel {
                Button("Cancel Download", role: .cancel) { model.cancelDownload() }
                    .disabled(model.isCancelling)
                    .frame(minHeight: 44).padding(.top, 12)
            }
        }
        if model.cancelledMode == mode {
            Text("Download cancelled")
            Text("Choose Download or Try Again when you want to start another download.").font(.footnote).foregroundStyle(.secondary)
        }
        if let failure = model.failures[mode] {
            Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private func compilationPhase(_ progress: MandarinCompilationProgress) -> String {
        switch progress {
        case .verifyingSources: return "Checking downloaded files…"
        case .preparingMappings: return "Preparing character conversions…"
        case .rows: return "Preparing vocabulary…"
        case .indexing: return "Finishing preparation…"
        case .finalCheck: return "Checking prepared language files…"
        }
    }

    @ViewBuilder private func compilationRows(_ progress: MandarinCompilationProgress) -> some View {
        Text("Preparing language download…").font(.headline)
        switch progress {
        case .verifyingSources: ProgressView("Checking downloaded files…")
        case .preparingMappings: ProgressView("Preparing character conversions…")
        case .indexing: ProgressView("Finishing preparation…")
        case .finalCheck: ProgressView("Checking prepared language files…")
        case .rows(let processed, let total):
            Text("Preparing vocabulary…")
            if total > 0 {
                Text("Vocabulary rows processed: \(processed.formatted()) of \(total.formatted())")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                ProgressView(value: Double(processed), total: Double(total))
            } else {
                Text("Vocabulary rows processed: \(processed.formatted())").font(.subheadline).monospacedDigit()
                ProgressView()
            }
        }
        Text("The files have downloaded. Uniboard is preparing them for use on this device.").font(.footnote).foregroundStyle(.secondary)
    }

    private func metadata(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled)
        }
    }
}

@MainActor
struct EnglishLanguageSettingsView: View {
    @ObservedObject var model: LanguageManagementModel
    private var available: Bool { UITextChecker.availableLanguages.contains("en_US") }

    var body: some View {
        Form {
            Section {
                Toggle("English Suggestions", isOn: Binding(get: { model.preferences.englishSuggestions }, set: { model.setEnglishSuggestions($0) }))
                    .disabled((!available && !model.preferences.englishSuggestions) || model.hasOperation)
            } footer: { Text("Show English word suggestions you can tap to insert. Suggestions don’t replace text automatically.") }
            Section {
                Toggle("English Autocorrection", isOn: Binding(get: { model.preferences.englishAutocorrection }, set: { model.setEnglishAutocorrection($0) }))
                    .disabled((!available && !model.preferences.englishAutocorrection) || model.hasOperation)
            } footer: {
                Text("Correct English words automatically when you finish a word. Press Backspace immediately after a correction to restore your spelling.")
            }
            Section {
                Text("Language conversion choices are separate from English autocorrection.")
                Text("Both options start Off and are independent. They use the device’s English (US) spelling dictionary, not a downloaded language pack. Results can vary by device and system version.")
                if !available {
                    Label("The English (US) spelling dictionary isn’t available on this device. These options can’t be enabled here.", systemImage: "exclamationmark.triangle")
                }
                NavigationLink { LanguageTypingGuideView(mode: .direct) } label: { Label("Typing Guide", systemImage: "questionmark.circle") }
            }
        }
        .navigationTitle("English Autocorrection")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.refresh() }
        .alert("Language Settings", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct LanguageNoticeView: View {
    let title: String
    let text: String
    var body: some View {
        ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled) }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct LanguageSourceView: View {
    let title: String
    let notice: String
    let files: [LanguagePackCatalog.SourceFile]
    var body: some View {
        List {
            Section { Text(notice).textSelection(.enabled) }
            ForEach(files) { file in
                Section(file.name) {
                    Link(destination: file.url) { Text(file.url.absoluteString).textSelection(.enabled) }
                    Text("\(file.isBundled ? "Bundled Mapping Size" : "Download Size"): \(languageExactBytes(file.bytes))").monospacedDigit()
                    if file.isBundled { Text("Already bundled. This URL identifies the upstream source; no mapping download is needed.").font(.footnote) }
                    Text("SHA-256\n\(file.sha256)").font(.footnote).textSelection(.enabled)
                }
            }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct LanguageTypingGuideView: View {
    let mode: LanguageInputMode
    var body: some View {
        List {
            if mode != .koreanTwoSetHangul {
            Section("Keys stay in their English positions") {
                Text("Language conversion uses your saved English (US) key arrangement. It changes how supported letters are interpreted, not the physical layout.")
            }
            }
            if mode == .koreanTwoSetHangul {
                Section("Two-Set Hangul") {
                    Text("Use consonant and vowel keys to build Hangul syllables.")
                    Text("The standard two-set layout is separate from your saved English arrangement. Leaving this mode restores your other layout. Auto-capitalization doesn’t apply.")
                    Text("ㅂ ㅈ ㄷ ㄱ ㅅ ㅛ ㅕ ㅑ ㅐ ㅔ")
                    Text("ㅁ ㄴ ㅇ ㄹ ㅎ ㅗ ㅓ ㅏ ㅣ")
                    Text("ㅋ ㅌ ㅊ ㅍ ㅠ ㅜ ㅡ")
                    Text("Shift changes seven keys: ㅂ→ㅃ, ㅈ→ㅉ, ㄷ→ㄸ, ㄱ→ㄲ, ㅅ→ㅆ, ㅐ→ㅒ, ㅔ→ㅖ.")
                }
                Section("Build syllables") {
                    example("ㄱ ㅏ (r k)", "가")
                    example("ㄲ ㅏ (Shift-R k)", "까")
                    example("ㄱ ㅗ ㅏ (r h k)", "과")
                    example("ㄱ ㅏ ㅂ ㅅ (r k q t)", "값")
                    example("ㄱ ㅏ ㅂ ㅅ ㅏ (r k q t k)", "갑사")
                    Text("Backspace removes one keystroke: 값 → 갑 → 가 → ㄱ → empty. It doesn’t delete a whole syllable at once.")
                }
                Section("How to choose") {
                    Text("Your Korean text appears in the choices before it is inserted. Press Space to insert it and add a space. Tap a choice to insert it without a space. Return confirms the text without adding a line break or sending it.")
                    Text("If the choices aren’t visible above the keys, press Space to open them, then tap the text to insert it.")
                    Text("Cancel Conversion clears unfinished text only. Changing input modes asks you to finish, keep editing, or cancel. Changing fields or cursor context clears unfinished text without inserting it elsewhere.")
                    Text("This mode composes modern Hangul. It doesn’t offer Hanja, archaic Hangul, three-set input, predictions, or My Words choices.")
                }
            }
            if mode == .japaneseRomaji {
                Section("What to type") {
                    Text("Type romaji, then choose Japanese text. The full dictionary’s engineering smoke check found these choices; ranking and natural-language quality still need native-speaker review.")
                    example("nihongo", "日本語 · にほんご · ニホンゴ")
                    example("toukyou", "東京")
                    example("watashi", "私")
                    example("arigatou", "ありがとう")
                    Text("Hiragana and Katakana are explicit choices. Phrase ranking can be imperfect; inspect the choice before inserting it.")
                }
            } else if mode == .mandarinPinyin {
                Section("What to type") {
                    example("nihao", "你好")
                    Text("The audited vocabulary includes this reading and output. The installer verifies the full sources, compiles the local dictionary and checks that this choice is present before activating it. Ranking and natural-language quality still need native-speaker review.")
                    Text("Use full pinyin, not initials or Cantonese. ASCII case is accepted. Incomplete spellings remain unfinished and may have no matching choice.")
                }
                Section("Boundaries and tones") {
                    Text("An ASCII apostrophe forces a syllable boundary: xi'an keeps xi and an separate, while xian can be ambiguous. Spaces aren’t accepted within a reading. A trailing apostrophe can remain unfinished.")
                    Text("Use v, ü or u: for ü. These aren’t treated as plain u. Tone marks and digits 1–4 are accepted as tone constraints; 5 and 0 mean neutral tone. A tone digit ends the preceding syllable. Unmarked input does not constrain the tone. Digits such as 6–9 and unsupported characters aren’t valid pinyin spellings here.")
                    Text("Simplified output is the default. Traditional output and general typo-tolerant conversion aren’t available.")
                }
            } else if mode == .direct {
                Section("Direct Typing") {
                    Text("Type characters without language conversion.")
                    if LanguageInputSettings.englishAssistanceAvailable {
                        Text("English Suggestions offers tap-only choices. English Autocorrection is separate and starts Off.")
                        Text("When an eligible correction happens, use Undo Correction or press Backspace immediately to restore the original pre-delimiter word. For a space-triggered correction, restoration removes that space and leaves your word editable. Cursor, selection or field changes end that rollback.")
                        Text("Custom outputs and exact Unicode actions aren’t automatic replacements. URL, email and code-like text are excluded from English autocorrection; insufficient host context must leave text unchanged rather than perform a blind replacement.")
                    }
                }
            }
            if mode == .japaneseRomaji || mode == .mandarinPinyin {
                Section("How to choose") {
                    Text("Tap a visible choice to insert it once. While composing, Space confirms once without adding a space; Return confirms once without a newline or submission. Press Space or Return again when idle for its ordinary action. Ordinary punctuation confirms the choice, then inserts that punctuation.")
                    Text("If choices can’t fit above the keys, Space opens Conversion Choices instead of committing an unseen default. More Choices opens the full list; closing it keeps unfinished text.")
                }
                Section("Literal input and cancel") {
                    Text("To insert exactly what you typed without conversion, tap that spelling in the choices.")
                    if mode == .japaneseRomaji {
                        Text("For example, tap nihongo to insert nihongo.")
                    }
                    Text("Cancel Conversion clears only unfinished text, not text already in the field.")
                    Text("A deliberate mode change or exact custom-key insertion asks you to finish unfinished text first. Changing fields or cursor context clears local unfinished text without inserting it in another location.")
                }
            }
        }
        .navigationTitle("Typing Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func example(_ reading: String, _ output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reading).font(.subheadline).foregroundStyle(.secondary)
            Text(output)
        }.textSelection(.enabled).accessibilityElement(children: .combine)
    }
}

private func languageExactBytes(_ count: Int64) -> String {
    count.formatted(.number.grouping(.automatic)) + " bytes"
}

private func languageStorageBytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}
