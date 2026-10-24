import SwiftUI

/// The Review Import sheet (design.md §6a). Nothing is written until
/// Replace Configuration, and the Extra Unicode Fonts switch changes only then.
struct ReviewImportView: View {
    @ObservedObject var model: ConfigurationImportModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ConfigurationCopy.review)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isReplacing)
        .alert(alertTitle, isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            if model.alert == .changed {
                Button(ConfigurationCopy.reviewAgain) { Task { await model.reviewAgain() } }
                Button("Cancel", role: .cancel) { dismiss() }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            switch model.alert {
            case .changed: Text(ConfigurationCopy.changedBody)
            case .replaceFailed: Text(ConfigurationCopy.replaceFailedBody)
            case .replaceUnverified: Text(ConfigurationCopy.unconfirmedBody)
            case nil: EmptyView()
            }
        }
    }

    private var isReplacing: Bool {
        if case .replacing = model.phase { return true }
        return false
    }

    private var alertTitle: String {
        model.alert == .changed ? ConfigurationCopy.changedTitle : ConfigurationCopy.replaceFailed
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        switch model.phase {
        case .checking, .review, .replacing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isReplacing)
                    .accessibilityIdentifier("reviewImport.cancel")
            }
        case .failed, .imported:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("reviewImport.done")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case let .checking(name):
            VStack(spacing: 12) {
                ProgressView()
                Text(ConfigurationCopy.checking(name)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reviewImport.checking")
        case let .failed(problems):
            ImportProblemsView(problems: problems)
        case let .review(review):
            ReviewList(review: review, replacing: false) { Task { if await model.replace() { dismiss() } } }
        case let .replacing(review):
            ReviewList(review: review, replacing: true) {}
        case let .imported(fonts):
            ImportedView(unavailableFonts: fonts)
        }
    }
}

/// The error state: the first problem as a card, the rest behind a disclosure.
private struct ImportProblemsView: View {
    let problems: [String]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "xmark.octagon")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(ConfigurationCopy.importFailed).font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("reviewImport.errorTitle")
                    Text(ConfigurationCopy.unchanged).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                if let first = problems.first {
                    problemCard(first).accessibilityIdentifier("reviewImport.firstProblem")
                }
                if problems.count > 1 {
                    DisclosureGroup(ConfigurationCopy.moreProblems(problems.count - 1)) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(problems.dropFirst().enumerated()), id: \.offset) { _, problem in
                                Text(Self.styled(problem)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .tint(.primary)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("reviewImport.moreProblems")
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func problemCard(_ problem: String) -> some View {
        Text(Self.styled(problem))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Field names ("Check font_rules.rule[2].font: …", "Unrecognized
    /// setting: keyboard.tapp.") in a monospaced font; the messages never
    /// contain file contents or custom key text.
    static func styled(_ problem: String) -> AttributedString {
        var text = AttributedString(problem)
        let field: Substring?
        if problem.hasPrefix("Check "), !problem.hasPrefix("Check line "), let colon = problem.range(of: ": ") {
            field = problem[problem.index(problem.startIndex, offsetBy: 6)..<colon.lowerBound]
        } else if problem.hasPrefix(unrecognized), problem.hasSuffix(".") {
            field = problem.dropFirst(unrecognized.count).dropLast()
        } else {
            field = nil
        }
        if let field, !field.isEmpty, let range = text.range(of: String(field)) { text[range].font = .body.monospaced() }
        return text
    }

    private static let unrecognized = "Unrecognized setting: "
}

/// A valid file's review: what changes in each category, then the cards.
private struct ReviewList: View {
    let review: ConfigurationReview
    let replacing: Bool
    let replace: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if review.diff.isIdentical {
                        Text(ConfigurationCopy.noChanges).font(.headline).accessibilityIdentifier("reviewImport.noChanges")
                    } else {
                        Text(ConfigurationCopy.intro).accessibilityIdentifier("reviewImport.intro")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.fileName).font(.footnote)
                        Text(review.caption).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("reviewImport.fileCaption")
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                ForEach(review.diff.changes, id: \.category) { change in
                    ChangeRow(change: change, expanded: change.category == .settings && review.diff.changesExtraUnicodeFonts)
                }
            } header: {
                Text(ConfigurationCopy.changes)
            } footer: {
                if review.diff.showsMissingSections {
                    Label {
                        Text(ConfigurationCopy.missingSections)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .accessibilityIdentifier("reviewImport.missingSections")
                }
            }
            if !review.ignoredSettings.isEmpty {
                Section {
                    ForEach(Array(review.ignoredSettings.enumerated()), id: \.offset) { _, setting in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(setting.name)
                            Text(setting.key).font(.footnote.monospaced()).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ConfigurationCopy.ignoredSetting(setting.name))
                        .accessibilityValue(setting.key)
                        .accessibilityIdentifier("reviewImport.ignored.\(setting.key)")
                    }
                } header: {
                    Text(ConfigurationCopy.ignoredSettings)
                } footer: {
                    Text(ConfigurationCopy.ignoredSettingsFooter).accessibilityIdentifier("reviewImport.ignoredFooter")
                }
            }
            if review.showsOverwrite {
                Section {
                    Text(ConfigurationCopy.overwrite).accessibilityIdentifier("reviewImport.overwrite")
                }
            }
            if review.showsFonts {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(ConfigurationCopy.fontsUnavailable(review.unavailableFonts.count)).font(.headline)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        Text(ConfigurationCopy.fontsBody(review.unavailableFonts.count)).font(.subheadline)
                        // Each font, then every imported rule that uses it.
                        ForEach(review.fontWarnings, id: \.font) { warning in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.font).font(.subheadline.weight(.semibold))
                                ForEach(warning.rules, id: \.self) { rule in
                                    Text("\(rule) · \(ConfigurationFontWarning.ruleStatus)").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reviewImport.fonts")
                }
            }
            if !review.diff.isIdentical {
                Section {
                } footer: {
                    Text(ConfigurationCopy.backup).accessibilityIdentifier("reviewImport.backup")
                }
            }
        }
        .disabled(replacing)
        .safeAreaInset(edge: .bottom) {
            Button(action: replace) {
                Group {
                    if replacing {
                        HStack(spacing: 8) { ProgressView(); Text(ConfigurationCopy.replacing) }
                    } else {
                        Text(review.diff.isIdentical ? "Done" : ConfigurationCopy.replace)
                    }
                }
                // The prominent style adds 7 pt above and below the label:
                // 36 + 14 = the 50 pt the design asks for (msg411).
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(replacing)
            .accessibilityIdentifier("reviewImport.primary")
            .padding(16)
            .background(.bar)
        }
    }
}

/// One category: its status as a second line; a changed category lists
/// every change.
private struct ChangeRow: View {
    let change: ConfigurationCategoryChange
    @State private var expanded: Bool

    init(change: ConfigurationCategoryChange, expanded: Bool) {
        self.change = change
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        if change.lines.isEmpty {
            label.accessibilityIdentifier("reviewImport.change.\(change.category.rawValue)")
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(Array(change.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.subheadline)
                }
            } label: {
                label
            }
            .accessibilityIdentifier("reviewImport.change.\(change.category.rawValue)")
        }
    }

    private var label: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.category.title)
                HStack(spacing: 4) {
                    if change.status == .reset {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    }
                    Text(change.status.title)
                        .foregroundStyle(change.status == .changed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .font(.footnote)
            }
        } icon: {
            Image(systemName: change.category.symbol).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.category.title), \(change.status.title)")
    }
}

private struct ImportedView: View {
    let unavailableFonts: [String]

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color(uiColor: .systemGreen))
                        .accessibilityHidden(true)
                    Text(ConfigurationCopy.imported).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("reviewImport.imported")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            if !unavailableFonts.isEmpty {
                Section {
                    NavigationLink("Font Downloads") {
                        FontPackDownloadsView().environmentObject(CatalogPreferences.shared)
                    }
                    .accessibilityIdentifier("reviewImport.fontDownloads")
                }
            }
        }
        .onAppear { UIAccessibility.post(notification: .announcement, argument: ConfigurationCopy.imported) }
    }
}
