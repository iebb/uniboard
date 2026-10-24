import SwiftUI
import UIKit

/// Shown while Extra Unicode Fonts is off. Rules are paused, never deleted,
/// and stay fully editable; only this button turns the switch on.
struct FontRulesPausedNotice: View {
    /// "fontRules.notice" or "fontPicker.notice".
    let identifier: String
    @ObservedObject private var catalog = CatalogPreferences.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Rules apply only when Extra Unicode Fonts is on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier + ".text")
            Button("Turn On") { catalog.selectUnicodeFonts(true) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Turn on Extra Unicode Fonts")
                .accessibilityIdentifier(identifier + ".turnOn")
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A 44 × 44 glyph tile. Without a font it shows the system rendering at
/// 40 % opacity, so a missing face never looks applied.
struct FontRuleTile: View {
    let text: String
    let font: UIFont?
    var dimmed = false
    var side: CGFloat = 44
    var pointSize: CGFloat = 28

    var body: some View {
        Text(text)
            .font(font.map { Font($0) } ?? .system(size: pointSize))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .foregroundStyle(Color.primary)
            .opacity(dimmed ? 0.4 : 1)
            .padding(2)
            .frame(width: side, height: side)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A resolved sample and the text each of its characters shows.
struct FontRuleLoadedSample: Equatable {
    let sample: FontRuleSample
    let texts: [String]
}

/// What a range or block shows for `face`: the representative characters
/// the face itself draws (letters first), found off the main thread by `FontRangeCoverage`
/// (cached, and cancelled when the view goes away), or the dimmed system
/// fallback. `content` gets nil while the face is still being checked.
struct FontRuleFaceSamples<Content: View>: View {
    let selector: FontRuleSelector
    let face: FontFaceReference?
    let catalog: UnicodeCatalog
    var limit = 1
    @ViewBuilder let content: (FontRuleLoadedSample?) -> Content

    @State private var loaded: (key: String, value: FontRuleLoadedSample)?

    private var cacheKey: String {
        let (first, last) = selector.bounds
        return [face.map { $0.identityKey + "|" + $0.postScriptName } ?? "-", "\(first)-\(last)", "\(limit)",
                catalog.edition.rawValue, catalog.version].joined(separator: "|")
    }

    var body: some View {
        let key = cacheKey
        content(loaded?.key == key ? loaded?.value : nil)
            .task(id: key) {
                let (first, last) = selector.bounds
                let assigned = catalog.characters(in: UnicodeBlock(name: "", start: first, end: last), limit: limit).map(\.codePoint)
                var drawn: [UInt32]?
                if let face {
                    do {
                        drawn = try await FontRangeCoverage.shared.drawnSamples(of: face, first: first, last: last, limit: limit,
                                                                                catalog: catalog, loader: UnicodeFontSupport.ruleFaceLoader)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                let sample = FontRuleSample.resolve(hasFace: face != nil, drawn: drawn, assigned: assigned)
                let texts = sample.codePoints.map { catalog.character(at: $0)?.displayText ?? "" }
                loaded = (key, FontRuleLoadedSample(sample: sample, texts: texts))
            }
    }
}

/// A range or block rule's 44 × 44 tile in `face`, per `FontRuleFaceSamples`.
struct FontRuleFaceTile: View {
    let selector: FontRuleSelector
    let face: FontFaceReference?
    let catalog: UnicodeCatalog
    var side: CGFloat = 44
    var pointSize: CGFloat = 28
    @ObservedObject private var rules = FontRulePreferences.shared

    var body: some View {
        FontRuleFaceSamples(selector: selector, face: face, catalog: catalog) { loaded in
            tile(loaded)
        }
    }

    /// Blank while the face is checked; then its first representative
    /// character in the face, or the dimmed system fallback.
    private func tile(_ loaded: FontRuleLoadedSample?) -> FontRuleTile {
        guard let loaded else { return FontRuleTile(text: "", font: nil, side: side, pointSize: pointSize) }
        let font = loaded.sample.inFace ? face.flatMap { rules.font($0, size: pointSize) } : nil
        return FontRuleTile(text: loaded.texts.first ?? "", font: font, dimmed: loaded.sample.dimmed || (loaded.sample.inFace && font == nil),
                            side: side, pointSize: pointSize)
    }
}

/// Settings › Font Rules: Try Text, then the saved rules by kind in their
/// saved order (the priority tie-break), never sorted.
struct FontRulesView: View {
    @ObservedObject private var rules = FontRulePreferences.shared
    @EnvironmentObject private var catalog: CatalogPreferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editMode: EditMode = .inactive
    @State private var editor: EditorRequest?
    @State private var tryText = ""

    struct EditorRequest: Identifiable {
        let id = UUID()
        let draft: FontRuleDraft
    }

    private struct TryResult: Equatable {
        let text: String
        let font: UIFont
        let title: String
        let caption: String
        var outcome: [String] { [title, caption] }
    }

    private static let helper = "Choose how text looks in Uniboard. Other apps still choose how inserted text looks."
    private static let rangeHelper = "For overlapping ranges, the narrower range wins. If they are equally wide, the later rule wins."
    private static let priorityHelper = "Code point rules take priority over ranges, then blocks, then the default font."
    private static let fallbackHelper = "If a font is missing or can’t display the text, Uniboard tries the next matching rule, then its default fonts."
    private static let joinedNote = "Joined characters and emoji stay together. Their first main character determines the rule, and the font must support the whole sequence."

    private var kinds: [FontRuleKind] {
        [FontRuleKind.codePoint, .range, .block].filter { kind in rules.rules.contains { $0.selector.kind == kind } }
    }

    var body: some View {
        List {
            if !catalog.useUnicodeFonts {
                Section {
                    FontRulesPausedNotice(identifier: "fontRules.notice")
                } header: {
                    helperHeader
                }
            }
            tryTextSection
            if rules.rules.isEmpty {
                emptyState
            } else {
                ForEach(kinds, id: \.self) { kind in
                    ruleSection(kind, isLast: kind == kinds.last)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .navigationTitle("Font Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !rules.rules.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("fontRules.edit")
                }
                Menu {
                    addButtons
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .accessibilityIdentifier("fontRules.add")
            }
        }
        .sheet(item: $editor) { request in
            FontRuleEditorView(draft: request.draft)
                .environmentObject(catalog)
        }
        .onAppear { rules.reload() }
        .onChange(of: rules.rules.isEmpty) { _, empty in if empty { editMode = .inactive } }
    }

    /// Inherits the section header's own secondary color, like the footers:
    /// an explicit `.secondary` here fades a level further (1.85:1).
    private var helperHeader: some View {
        Text(Self.helper)
            .font(.footnote)
            .textCase(nil)
            .padding(.bottom, 8)
            .accessibilityIdentifier("fontRules.header")
    }

    @ViewBuilder private var addButtons: some View {
        Button("Code Point") { add(.codePoint) }.accessibilityIdentifier("fontRules.add.codePoint")
        Button("Range") { add(.range) }.accessibilityIdentifier("fontRules.add.range")
        Button("Unicode Block") { add(.block) }.accessibilityIdentifier("fontRules.add.block")
    }

    private func add(_ kind: FontRuleKind) {
        editor = EditorRequest(draft: FontRuleDraft(kind: kind))
    }

    // MARK: Try Text

    private var tryResults: [TryResult] {
        FontRuleTryText.characters(tryText).map { character in
            let resolution = UnicodeFontSupport.resolution(for: character, size: 28, enabled: catalog.useUnicodeFonts)
            return TryResult(text: character, font: resolution.font, title: Self.title(resolution), caption: Self.caption(resolution))
        }
    }

    /// "Using {font}" only for the rule face that really draws it; anything
    /// else is Uniboard's default fonts.
    static func title(_ resolution: FontResolution) -> String {
        guard case .rule = resolution.source else { return FontRuleCopy.usingDefaultFonts }
        return FontRuleCopy.using(resolution.faceName)
    }

    static func caption(_ resolution: FontResolution) -> String {
        guard case let .rule(match) = resolution.source, UnicodeFontSupport.ruleSet.rules.indices.contains(match.ruleIndex) else {
            return FontRuleCopy.defaultFonts
        }
        return FontRuleCopy.source(UnicodeFontSupport.ruleSet.rules[match.ruleIndex].selector)
    }

    private var tryTextSection: some View {
        let results = tryResults
        return Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Type or paste text", text: $tryText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Try Text")
                    .accessibilityIdentifier("fontRules.tryText.field")
            }
            .frame(minHeight: 44)
            .onChange(of: tryText) { _, value in
                let trimmed = FontRuleTryText.trimmed(value)
                if trimmed != value { tryText = trimmed }
            }
            if let first = results.first {
                if FontRuleTryText.allSame(results.map(\.outcome)) {
                    resultRow(TryResult(text: results.map(\.text).joined(), font: first.font, title: first.title, caption: first.caption), index: 0)
                } else {
                    Text(FontRuleCopy.multipleFonts)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fontRules.tryText.summary")
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        resultRow(result, index: index)
                    }
                }
            }
        } header: {
            if catalog.useUnicodeFonts {
                VStack(alignment: .leading, spacing: 0) {
                    helperHeader
                    Text("Try Text")
                }
            } else {
                Text("Try Text")
            }
        } footer: {
            if FontRuleTryText.hasJoinedCharacters(results.map(\.text)) {
                Text(Self.joinedNote)
                    .accessibilityIdentifier("fontRules.tryText.joinedNote")
            }
        }
    }

    private func resultRow(_ result: TryResult, index: Int) -> some View {
        HStack(spacing: 12) {
            FontRuleTile(text: result.text, font: result.font)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                Text(result.caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.text)
        .accessibilityValue("\(result.title), \(result.caption)")
        .accessibilityIdentifier("fontRules.tryText.result.\(index)")
    }

    // MARK: Rules

    private func header(_ kind: FontRuleKind) -> some View {
        let (title, identifier): (String, String) = {
            switch kind {
            case .codePoint: return ("Code Points", "codePoints")
            case .range: return ("Ranges", "ranges")
            case .block: return ("Unicode Blocks", "blocks")
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if kind == .range, editMode.isEditing {
                Text("Later rules win equal-width ties.")
                    .font(.caption)
                    .textCase(nil)
                    .accessibilityIdentifier("fontRules.rangeOrderCaption")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fontRules.section.\(identifier)")
    }

    @ViewBuilder private func footer(_ kind: FontRuleKind, isLast: Bool) -> some View {
        if kind == .range || isLast {
            VStack(alignment: .leading, spacing: 12) {
                if kind == .range { Text(Self.rangeHelper) }
                if isLast { Text(Self.priorityHelper + "\n" + Self.fallbackHelper).accessibilityIdentifier("fontRules.priority") }
            }
        }
    }

    private func ruleSection(_ kind: FontRuleKind, isLast: Bool) -> some View {
        Section {
            ForEach(rules.rules.filter { $0.selector.kind == kind }) { rule in
                row(rule)
            }
            .onMove { source, destination in rules.move(kind: kind, from: source, to: destination) }
        } header: {
            header(kind)
        } footer: {
            footer(kind, isLast: isLast)
        }
    }

    private func ruleTitle(_ rule: FontRule) -> String {
        switch rule.selector {
        case let .codePoint(value): return catalog.catalog.character(at: value)?.name ?? FontRuleScalar.label(value)
        case let .range(first, last): return FontRuleCopy.range(first, last)
        case let .block(block): return block.name
        }
    }

    private func ruleSubtitle(_ rule: FontRule) -> String {
        switch rule.selector {
        case let .codePoint(value): return FontRuleScalar.label(value)
        case .range: return FontRuleCopy.codePoints(rule.selector.validScalarCount)
        case let .block(block): return FontRuleCopy.range(block.first, block.last)
        }
    }

    private func row(_ rule: FontRule) -> some View {
        let status = rules.status(of: rule)
        let font = rules.font(rule.face, size: 28)
        let title = ruleTitle(rule)
        let subtitle = ruleSubtitle(rule)
        let stacked = typeSize.isAccessibilitySize
        let keyboard = KeyboardFontEvidenceCache.status(of: rule.face)
        return Button {
            editor = EditorRequest(draft: FontRuleDraft(editing: rule))
        } label: {
            HStack(spacing: 12) {
                if case .codePoint = rule.selector {
                    FontRuleTile(text: FontRulePreferences.firstCharacter(of: rule.selector, in: catalog.catalog)?.displayText ?? "",
                                 font: font, dimmed: font == nil)
                } else {
                    FontRuleFaceTile(selector: rule.selector, face: rule.face, catalog: catalog.catalog)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(rule.selector.kind == .range ? .body.monospaced() : .body)
                        .foregroundStyle(.primary)
                    if let text = status.text {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(text).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    } else {
                        Text(subtitle)
                            .font(rule.selector.kind == .block ? .caption.monospaced() : .caption)
                            .foregroundStyle(.secondary)
                    }
                    if stacked {
                        Text(rule.face.displayName).font(.subheadline).foregroundStyle(.secondary)
                        KeyboardFontTag(status: keyboard)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if !stacked {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(rule.face.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        KeyboardFontTag(status: keyboard)
                    }
                    .frame(maxWidth: 150, alignment: .trailing)
                }
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { remove(rule) } label: { Text("Remove Rule") }
        }
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(([rule.face.displayName] + [status.text, keyboard.accessibilityText].compactMap { $0 }).joined(separator: ", "))
        .accessibilityHint("Edit rule")
        .accessibilityIdentifier("fontRules.row.\(rule.id)")
    }

    private func remove(_ rule: FontRule) {
        guard rules.remove(id: rule.id) else { return }
        UIAccessibility.post(notification: .announcement, argument: "Rule removed")
    }

    // MARK: Empty

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "textformat.alt")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No font rules yet")
                    .font(.headline)
                Text("Choose a preferred font for a code point, range or Unicode block.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Menu {
                    addButtons
                } label: {
                    Text("Add Rule")
                }
                .accessibilityIdentifier("fontRules.empty.add")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fontRules.empty")
        }
    }
}
