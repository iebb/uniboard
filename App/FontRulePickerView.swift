import SwiftUI
import UIKit
import CoreText

/// One listed face: the library record, its portable reference, and the
/// picker's precomputed view of it.
struct FontPickerEntry: Sendable {
    let record: FontFaceRecord
    let reference: FontFaceReference
    let face: FontPickerFace
}

/// Builds the picker's faces from the font inventory (design/font-picker §0, §2).
enum FontPickerInventory {
    struct ProcessTraits: Sendable {
        let weight: Double?
        let width: Double?
        let italic: Bool
    }

    /// CoreText's traits for every font this process lists, by PostScript
    /// name; read once. A face it lacks falls back to its style name.
    static let processTraits: [String: ProcessTraits] = {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        var result: [String: ProcessTraits] = [:]
        for descriptor in descriptors {
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                  let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any] else { continue }
            let symbolic = (traits[kCTFontSymbolicTrait as String] as? NSNumber)?.uint32Value ?? 0
            result[name] = ProcessTraits(weight: (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue,
                                         width: (traits[kCTFontWidthTrait as String] as? NSNumber)?.doubleValue,
                                         italic: symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0)
        }
        return result
    }()

    /// Listed faces only: never "."-prefixed private faces or LastResort.
    static func entries(_ records: [FontFaceRecord], evidence: KeyboardFontEvidence?,
                        systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) -> [FontPickerEntry] {
        records.compactMap { record in
            guard FontPickerSection.isListed(postScriptName: record.postScriptName, family: record.family),
                  let reference = FontFaceReference(record: record) else { return nil }
            let isPack: Bool
            let process: ProcessTraits?
            switch record.locator {
            case let .file(path, _, _, _): isPack = path.hasPrefix("pack:"); process = nil
            case .process: isPack = false; process = processTraits[record.postScriptName]
            }
            let variations: [String: Double]
            switch reference.identity {
            case let .file(_, _, axes), let .process(_, axes): variations = axes
            }
            let traits = FontStyleTraits.resolve(style: record.style, variations: variations, weightTrait: process?.weight,
                                                 widthTrait: process?.width, italicTrait: process?.italic ?? false)
            let face = FontPickerFace(id: record.id.rawValue, family: record.family, style: record.style, postScriptName: record.postScriptName,
                                      section: FontPickerSection(source: record.source, isPack: isPack), traits: traits,
                                      keyboard: KeyboardFontEvidence.status(source: record.source, postScriptName: record.postScriptName,
                                                                            evidence: evidence, systemVersion: systemVersion))
            return FontPickerEntry(record: record, reference: reference, face: face)
        }
    }
}

/// The keyboard's latest font report (design/font-picker §4), read again
/// only when the file changed.
@MainActor
enum KeyboardFontEvidenceCache {
    private static var loaded: (modified: Date?, evidence: KeyboardFontEvidence?)?

    static var evidence: KeyboardFontEvidence? {
        let store = KeyboardFontEvidenceStore.appGroup
        let url = store.root()?.appendingPathComponent(KeyboardFontEvidence.filename)
        let modified = url.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }
        if let loaded, loaded.modified == modified { return loaded.evidence }
        let evidence = store.load()
        loaded = (modified, evidence)
        return evidence
    }

    static func status(of face: FontFaceReference) -> KeyboardFontStatus {
        KeyboardFontEvidence.status(source: face.source, postScriptName: face.postScriptName, evidence: evidence,
                                    systemVersion: ProcessInfo.processInfo.operatingSystemVersionString)
    }
}

/// "App Only" or "Keyboard Unverified", on its own line under the subtitle.
struct KeyboardFontTag: View {
    let status: KeyboardFontStatus

    var body: some View {
        if let tag = status.tag {
            Text(tag)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .fixedSize()
                .accessibilityLabel(status.accessibilityText ?? tag)
        }
    }
}

/// Every face Uniboard can use for a rule (design/font-picker): Your Fonts,
/// Google, Preview, System and Other Device Fonts, as families. Support is
/// the NAMED face's own: `FontComparisonEngine` proofs for one code point,
/// `FontRangeCoverage` (off the main thread) for a range or block. Nothing
/// is downloaded.
@MainActor
final class FontRulePickerModel: ObservableObject {
    typealias Support = FontPickerSupport

    @Published private(set) var families: [FontPickerFamily] = []
    @Published private(set) var support: [String: Support] = [:]
    @Published private(set) var loading = true
    @Published private(set) var failed = false
    /// Every check finished: the list reorders once.
    @Published private(set) var ranked = false
    @Published private(set) var checked = 0
    private(set) var entries: [String: FontPickerEntry] = [:]
    private var byIdentity: [String: String] = [:]
    /// Read before each batch of checks: while searching, matches go first.
    var query = FontPickerQuery("")
    private let engine: FontComparisonEngine

    init(engine: FontComparisonEngine = .shared) { self.engine = engine }

    var total: Int { entries.count }

    func entry(for reference: FontFaceReference?) -> FontPickerEntry? {
        reference.flatMap { byIdentity[$0.identityKey] }.flatMap { entries[$0] }
    }

    /// Lists the faces, then checks support; cancelled with the view's task.
    func load(selector: FontRuleSelector, character: UnicodeCharacter?, selected: FontFaceReference?) async {
        loading = true
        failed = false
        ranked = false
        checked = 0
        do {
            let snapshot = try await engine.inventorySnapshot()
            try Task.checkCancellation()
            let evidence = KeyboardFontEvidenceCache.evidence
            let built = await Task.detached(priority: .userInitiated) { FontPickerInventory.entries(snapshot.faces, evidence: evidence) }.value
            try Task.checkCancellation()
            entries = Dictionary(built.map { ($0.face.id, $0) }, uniquingKeysWith: { first, _ in first })
            byIdentity = Dictionary(entries.values.map { ($0.reference.identityKey, $0.face.id) }, uniquingKeysWith: { min($0, $1) })
            support = entries.mapValues { _ in .checking }
            families = FontPickerFamily.grouping(entries.values.map(\.face))
            loading = false
            try await check(selector: selector, character: character, selected: selected)
            ranked = true
        } catch is CancellationError {
            return
        } catch {
            loading = false
            failed = true
            support = support.mapValues { $0 == .checking ? .unknown : $0 }
        }
    }

    /// The selected face first, then display order (matches first while
    /// searching), a small batch at a time so results show as they come.
    private func check(selector: FontRuleSelector, character: UnicodeCharacter?, selected: FontFaceReference?) async throws {
        let selectedID = selected.flatMap { byIdentity[$0.identityKey] }
        var pending = Set(entries.keys)
        let isCodePoint = selector.kind == .codePoint
        let inspection = FontInspection(originalText: character?.text ?? "", characterName: character?.name ?? "")
        let (first, last) = selector.bounds
        let loader = UnicodeFontSupport.ruleFaceLoader
        // Faces sharing one file and instance are counted once.
        var counts: [String: Int?] = [:]
        while !pending.isEmpty {
            let batch = Array(FontPickerContent.checkOrder(families, selected: selectedID, query: query, pending: pending).prefix(isCodePoint ? 16 : 4))
            guard !batch.isEmpty else { break }
            var next = support
            if isCodePoint {
                let proofs = try await engine.proofs(for: inspection, faces: batch.compactMap { entries[$0]?.record })
                for id in batch {
                    guard let entry = entries[id] else { continue }
                    switch proofs[entry.record.id] {
                    case .verified?: next[id] = .supported
                    case .unsupported?:
                        // A face whose file is gone is missing, not unsupported.
                        if case .file = entry.reference.identity, !FontRulePreferences.shared.isAvailable(entry.reference) {
                            next[id] = .missing
                        } else {
                            next[id] = .unsupported
                        }
                    case .unknown?, nil: next[id] = .unknown
                    }
                }
            } else {
                for id in batch {
                    guard let entry = entries[id] else { continue }
                    let key = entry.reference.identityKey + "|" + entry.reference.postScriptName
                    let count: Int?
                    if let known = counts[key] {
                        count = known
                    } else {
                        count = try await FontRangeCoverage.shared.supportedCount(of: entry.reference, first: first, last: last, loader: loader)
                        counts[key] = count
                    }
                    next[id] = count.map(Support.coverage) ?? .missing
                }
            }
            try Task.checkCancellation()
            pending.subtract(batch)
            support = next
            checked = entries.count - pending.count
        }
    }
}

/// Settings and character detail: choose the preferred font for a code
/// point, range or block (design/font-picker). `choose` saves (character
/// detail) or returns the choice to the editor; nothing is downloaded or
/// turned on.
struct FontRulePickerView: View {
    let selector: FontRuleSelector
    let selection: FontFaceReference?
    let choose: (FontFaceReference) -> Void
    /// Character detail only, when this code point has its own rule.
    var clear: (() -> Void)?

    @EnvironmentObject private var catalog: CatalogPreferences
    @ObservedObject private var rules = FontRulePreferences.shared
    @StateObject private var model = FontRulePickerModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var chosen: FontFaceReference?
    @State private var showsUnsupported = false
    /// Families opened by hand, remembered while the picker is open.
    @State private var expanded: Set<String> = []
    /// Families a search opened that were closed by hand; reset per query.
    @State private var searchCollapsed: Set<String> = []

    private var isSingle: Bool { selector.kind == .codePoint }
    private var current: FontFaceReference? { chosen ?? selection }
    private var total: Int { selector.validScalarCount }

    private var samples: [UnicodeCharacter] {
        FontRulePreferences.sampleCharacters(of: selector, in: catalog.catalog, limit: 1)
    }

    private var tileText: String { samples.first?.displayText ?? "" }

    private var content: FontPickerContent {
        FontPickerContent.build(model.families, query: FontPickerQuery(query), support: model.support, ranked: model.ranked)
    }

    var body: some View {
        let content = content
        List {
            Section {
                EmptyView()
            } header: {
                sampleHeader
            }
            if !catalog.useUnicodeFonts {
                Section { FontRulesPausedNotice(identifier: "fontPicker.notice") }
            }
            if let current {
                selectedSection(current)
            }
            statusSection
            if !model.loading, content.isEmpty {
                Section {
                    Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "No fonts" : FontPickerCopy.noMatches(query))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fontPicker.empty")
                }
            }
            ForEach(content.sections) { section in
                Section {
                    ForEach(section.rows) { familyRow($0) }
                } header: {
                    Text(section.section.title).accessibilityIdentifier("fontPicker.section.\(section.section.identifier)")
                } footer: {
                    let footers = section.keyboardFooters
                    if !footers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(footers, id: \.self) { Text($0) }
                        }
                        .accessibilityIdentifier("fontPicker.footer.\(section.section.identifier)")
                    }
                }
            }
            if !content.unsupported.isEmpty {
                unsupportedSection(content.unsupported)
            }
            Section {
                NavigationLink {
                    FontPackDownloadsView()
                } label: {
                    Label("Font Downloads", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("fontPicker.fontDownloads")
            } header: {
                Text("If a font is missing or can’t display the text, Uniboard tries the next matching rule, then its default fonts.")
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .animation(reduceMotion ? nil : .default, value: model.ranked)
        .navigationTitle("Preferred Font")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: FontPickerCopy.searchPrompt)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, text in
            searchCollapsed = []
            model.query = FontPickerQuery(text)
        }
        .task(id: query) {
            // VoiceOver hears the result count once typing stops.
            guard !query.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement, argument: FontPickerCopy.resultCount(self.content.familyCount))
        }
        .task(id: selector) { await model.load(selector: selector, character: samples.first, selected: current) }
    }

    // MARK: Sample

    @ViewBuilder private var sampleHeader: some View {
        let font = current.flatMap { rules.font($0, size: isSingle ? 64 : 28) }
        if isSingle {
            FontRuleTile(text: tileText, font: font, dimmed: current != nil && font == nil, side: 96, pointSize: 64)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityIdentifier("fontPicker.sample")
        } else {
            FontRuleFaceSamples(selector: selector, face: current, catalog: catalog.catalog, limit: FontRuleSample.previewLimit) { loaded in
                sampleStrip(loaded, font: font)
            }
            .frame(height: 64)
            .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .textCase(nil)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
            .accessibilityIdentifier("fontPicker.sample")
        }
    }

    /// The first 12 representative characters the highlighted face draws, in that face; or
    /// the system fallback, dimmed when that face draws none of them.
    private func sampleStrip(_ loaded: FontRuleLoadedSample?, font: UIFont?) -> some View {
        let drawnFont = loaded?.sample.inFace == true ? font : nil
        let dimmed = loaded.map { $0.sample.dimmed || ($0.sample.inFace && font == nil) } ?? false
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array((loaded?.texts ?? []).enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(drawnFont.map { Font($0) } ?? .system(size: 28))
                        .foregroundStyle(Color.primary)
                        .opacity(dimmed ? 0.4 : 1)
                        .frame(minWidth: 36, minHeight: 44)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: Selected and status

    /// The chosen face, whatever the search says, and Clear Preference.
    private func selectedSection(_ face: FontFaceReference) -> some View {
        let entry = model.entry(for: face)
        let section = entry?.face.section ?? FontPickerSection(source: face.source, isPack: face.googleFaceID == nil)
        let status = entry?.face.keyboard ?? KeyboardFontEvidenceCache.status(of: face)
        let style = face.style.isEmpty ? FontPickerCopy.regular : face.style
        let missing = rules.font(face, size: 28) == nil
        let support = entry.flatMap { model.support[$0.face.id] }
        return Section {
            Button {
                pick(face)
            } label: {
                HStack(spacing: 12) {
                    tile(face, side: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(face.family).foregroundStyle(.primary).lineLimit(2)
                        Text(style + " · " + section.title).font(.caption).foregroundStyle(.secondary)
                        if missing {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text(FontRuleCopy.unavailable).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        } else {
                            caption(support)
                        }
                        KeyboardFontTag(status: status)
                    }
                    Spacer(minLength: 8)
                    checkmark
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .tint(.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(face.family + " " + style)
            .accessibilityValue([missing ? FontRuleCopy.unavailable : captionText(support),
                                 status.accessibilityText].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits([.isButton, .isSelected])
            .accessibilityIdentifier("fontPicker.selected")
            if let clear, case .codePoint = selector {
                Button {
                    clear()
                    close()
                } label: {
                    Text("Clear Preference").frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("fontPicker.clear")
            }
        } header: {
            Text(FontPickerCopy.selected)
        } footer: {
            if clear != nil, case let .codePoint(value) = selector {
                Text(rules.captionAfterClearing(value))
                    .accessibilityIdentifier("fontPicker.clearCaption")
            }
        }
    }

    /// Listing, checking, or the check failure.
    @ViewBuilder private var statusSection: some View {
        if model.loading {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .accessibilityIdentifier("fontPicker.loading")
            }
        } else if model.failed {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn’t check font support").font(.headline)
                    Text("Try again in a moment. Results are incomplete.").font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fontPicker.failed")
            }
        } else if !model.ranked, model.total > 0 {
            Section {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(FontPickerCopy.checking(model.checked, of: model.total))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FontPickerCopy.checkingAccessibility(model.checked, of: model.total))
                .accessibilityIdentifier("fontPicker.checking")
            }
        }
    }

    private func unsupportedSection(_ rows: [FontPickerRow]) -> some View {
        Section {
            Button {
                showsUnsupported.toggle()
            } label: {
                HStack {
                    Text(FontRuleCopy.showUnsupportedFonts(rows.count))
                    Spacer()
                    Image(systemName: showsUnsupported ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("fontPicker.showUnsupported")
            .accessibilityValue(showsUnsupported ? "Expanded" : "Collapsed")
            if showsUnsupported {
                ForEach(rows) { familyRow($0) }
            }
        } footer: {
            if showsUnsupported {
                Text(isSingle ? FontPickerCopy.unsupportedCharacterFooter : FontPickerCopy.unsupportedRangeFooter)
            }
        }
    }

    // MARK: Families

    private func isChosen(_ face: FontPickerFace) -> Bool {
        current.map { model.entry(for: $0)?.face.id == face.id } ?? false
    }

    private func isUnable(_ face: FontPickerFace) -> Bool { model.support[face.id]?.isUnable == true }

    private func expansion(_ row: FontPickerRow) -> Binding<Bool> {
        Binding {
            row.isFiltered ? !searchCollapsed.contains(row.id) : expanded.contains(row.id)
        } set: { open in
            if row.isFiltered {
                if open { searchCollapsed.remove(row.id) } else { searchCollapsed.insert(row.id) }
            } else if open {
                expanded.insert(row.id)
            } else {
                expanded.remove(row.id)
            }
        }
    }

    /// One face: the row chooses it. Several: a disclosure that only opens.
    @ViewBuilder private func familyRow(_ row: FontPickerRow) -> some View {
        if row.family.faces.count == 1 {
            faceRow(row.family.faces[0], title: row.family.name, subtitle: row.subtitle, side: 44,
                    showsTag: true, showsPostScriptName: false)
        } else {
            DisclosureGroup(isExpanded: expansion(row)) {
                styleRows(row)
            } label: {
                familyLabel(row)
            }
            .disabled(row.family.faces.allSatisfy(isUnable))
            .accessibilityIdentifier("fontPicker.family.\(row.family.name)")
        }
    }

    private func familyLabel(_ row: FontPickerRow) -> some View {
        let representative = row.family.representative
        let chosen = row.family.faces.first(where: isChosen)
        let unable = row.family.faces.allSatisfy(isUnable)
        let support = model.support[representative.id]
        let reference = model.entries[representative.id]?.reference
        return HStack(spacing: 12) {
            if let reference { tile(reference, side: 44) }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.family.name).foregroundStyle(.primary).lineLimit(2)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                if !isSingle { caption(support) }
                KeyboardFontTag(status: row.family.keyboard)
            }
            Spacer(minLength: 8)
            if chosen != nil { checkmark }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .opacity(unable ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.family.name)
        .accessibilityValue([row.subtitle, chosen.map { FontPickerCopy.styleSelected($0.styleName) },
                             isSingle ? nil : captionText(support), row.family.keyboard.accessibilityText]
            .compactMap { $0 }.joined(separator: ", "))
    }

    /// The styles of an open family, as rows. Kept on its own so the styles
    /// grid (Normal / Italic × weight) can replace it.
    @ViewBuilder private func styleRows(_ row: FontPickerRow) -> some View {
        let repeated = row.family.repeatedStyleNames
        ForEach(row.faces) { face in
            faceRow(face, title: face.styleName, subtitle: nil, side: 36,
                    showsTag: row.family.keyboard == .available, showsPostScriptName: repeated.contains(face.styleName))
        }
    }

    /// A face that can be chosen: a one-face family row, or a style row.
    @ViewBuilder private func faceRow(_ face: FontPickerFace, title: String, subtitle: String?, side: CGFloat,
                                      showsTag: Bool, showsPostScriptName: Bool) -> some View {
        if let entry = model.entries[face.id] {
            let chosen = isChosen(face)
            let unable = isUnable(face)
            let support = model.support[face.id]
            Button {
                pick(entry.reference)
            } label: {
                HStack(spacing: 12) {
                    tile(entry.reference, side: side)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary).lineLimit(2)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                        if showsPostScriptName {
                            Text(face.postScriptName).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        caption(support)
                        if showsTag { KeyboardFontTag(status: face.keyboard) }
                    }
                    Spacer(minLength: 8)
                    if chosen { checkmark }
                }
                .frame(minHeight: side == 44 ? 56 : 48)
                .contentShape(Rectangle())
            }
            .tint(.primary)
            .disabled(unable)
            .opacity(unable ? 0.4 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(face.family + " " + face.styleName)
            .accessibilityValue([captionText(support), showsTag ? face.keyboard.accessibilityText : nil]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("fontPicker.face.\(face.postScriptName)")
        }
    }

    // MARK: Parts

    @ViewBuilder private func tile(_ reference: FontFaceReference, side: CGFloat) -> some View {
        let pointSize: CGFloat = side >= 44 ? 28 : 22
        if isSingle {
            let font = rules.font(reference, size: pointSize)
            FontRuleTile(text: tileText, font: font, dimmed: font == nil, side: side, pointSize: pointSize)
        } else {
            FontRuleFaceTile(selector: selector, face: reference, catalog: catalog.catalog, side: side, pointSize: pointSize)
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
            .fontWeight(.semibold)
            .accessibilityHidden(true)
    }

    /// Coverage ("Supports n of m code points") for a range or block, or
    /// "Can’t display this character" for a code point; "Font unavailable"
    /// when the file is gone.
    private func captionText(_ support: FontPickerSupport?) -> String? {
        switch support {
        case let .coverage(count)?: return FontRuleCopy.supports(count, of: total)
        case .unsupported?: return FontPickerCopy.cannotDisplayCharacter
        case .missing?: return FontRuleCopy.unavailable
        default: return nil
        }
    }

    @ViewBuilder private func caption(_ support: FontPickerSupport?) -> some View {
        if !isSingle, support == .checking {
            ProgressView().controlSize(.small)
        } else if let text = captionText(support) {
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pick(_ face: FontFaceReference) {
        chosen = face
        choose(face)
        close()
    }

    /// Pop after 0.25 s so the checkmark is seen; at once with Reduce Motion.
    private func close() {
        if reduceMotion {
            dismiss()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
        }
    }
}
