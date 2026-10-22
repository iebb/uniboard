import SwiftUI

struct CharacterDetailView: View {
    let character: UnicodeCharacter
    @Binding var scratchpad: String
    @EnvironmentObject private var store: CharacterStore
    @EnvironmentObject private var preferences: CatalogPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var added = false
    @State private var copiedForm: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let forms = character.presentationForms {
                        // Unicode defines both presentations; show them side by side.
                        HStack(spacing: 12) {
                            presentationTile(forms.text, title: "Text", identifier: "characterGlyph")
                            presentationTile(forms.emoji, title: "Emoji", identifier: "characterGlyph.emoji")
                        }
                    } else {
                        Text(character.displayText)
                            .font(Font(UnicodeFontSupport.font(for: character.displayText, size: 104, enabled: preferences.useUnicodeFonts)))
                            .accessibilityIdentifier("characterGlyph")
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .padding(24)
                            .frame(maxWidth: .infinity).frame(height: 196)
                            .background(Color.previewSurface(missing: glyphMissing, ucsur: preferences.isUCSUR(character.codePoint)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 4) {
                        Text(character.name)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("characterProperties.name")
                        Text(character.codePointLabel)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("characterProperties.codepoints")
                    }

                    actions

                    VStack(alignment: .leading, spacing: 8) {
                        Text(characterDescription)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("characterProperties.description")
                        Group {
                            if character.category == "Cn" {
                                Label("This code point is not assigned in the selected Unicode edition.", systemImage: "square.dashed")
                            } else if character.isInvisible {
                                Label("This character is invisible. Its preview is a placeholder; copying inserts the actual character.", systemImage: "eye.slash")
                            } else if character.category.hasPrefix("M") {
                                Label("The dotted circle is only a preview. This mark combines with the character before it.", systemImage: "circle.dotted")
                            } else if glyphMissing {
                                Label(previewFont == nil
                                      ? "iOS can’t display this character, so its preview is a placeholder. The name and properties are still accurate."
                                      : "iOS can’t display this character. The preview uses \(previewFont!); other apps may show a placeholder.",
                                      systemImage: "exclamationmark.triangle")
                            }
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    }

                    if !namingRows.isEmpty { PropertyGroup(title: "Names & Notes", rows: namingRows) }
                    PropertyGroup(title: "Properties", rows: propertyRows)
                }
                .padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(Color.groupedBackground)
            .navigationTitle("Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }

    private func presentationTile(_ form: String, title: String, identifier: String) -> some View {
        Text(form)
            .font(Font(UnicodeFontSupport.font(for: form, size: 84, enabled: preferences.useUnicodeFonts)))
            .minimumScaleFactor(0.5).lineLimit(1)
            .accessibilityIdentifier(identifier)
            .padding(12)
        .frame(maxWidth: .infinity).frame(height: 196)
        .background(Color.previewSurface(missing: glyphMissing, ucsur: preferences.isUCSUR(character.codePoint)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) presentation")
    }

    /// Copies one presentation sequence exactly, selector included.
    private func copyFormButton(_ form: String, title: String, identifier: String) -> some View {
        Button {
            UIPasteboard.general.string = form
            store.recordUse(character.codePoint)
            copiedForm = form
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(copiedForm == form ? "Copied" : title, systemImage: copiedForm == form ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(identifier)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = character.text
                store.recordUse(character.codePoint)
                copied = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(copied ? "Copied" : "Copy Character", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("copyCharacter")

            if let forms = character.presentationForms {
                HStack(spacing: 10) {
                    copyFormButton(forms.text, title: "Copy Text", identifier: "copyTextPresentation")
                    copyFormButton(forms.emoji, title: "Copy Emoji", identifier: "copyEmojiPresentation")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    store.toggleFavorite(character.codePoint)
                } label: {
                    Label(store.isFavorite(character.codePoint) ? "Saved" : "Save", systemImage: store.isFavorite(character.codePoint) ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(store.isFavorite(character.codePoint) ? "Remove from favorites" : "Add to favorites")
                .accessibilityIdentifier("toggleFavorite")
                .disabled(character.category == "Cn" && !store.isFavorite(character.codePoint))
                Button {
                    scratchpad += character.text
                    store.recordUse(character.codePoint)
                    added = true
                } label: {
                    Label(added ? "Added" : "Scratchpad", systemImage: added ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                }.accessibilityIdentifier("addToScratchpad")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var previewFont: String? {
        UnicodeFontSupport.sourceName(for: character.displayText, size: 104, enabled: preferences.useUnicodeFonts)
    }
    private var glyphMissing: Bool {
        UnicodeFontSupport.stockFontsMiss(character.displayText)
    }

    private var namingRows: [PropertyRow] {
        var rows: [PropertyRow] = []
        if !character.nameAliases.isEmpty {
            rows.append(.init(title: "Aliases", value: character.nameAliases.map { "\($0.kindLabel): \($0.name)" }.joined(separator: "\n"), identifier: "characterProperties.aliases", monospaced: false, stacked: true))
        }
        if let section = character.namesListSection {
            rows.append(.init(title: "Unicode section", value: section, identifier: "characterProperties.section", monospaced: false, stacked: true))
        }
        let notes = character.sectionAnnotations + character.annotations
        if !notes.isEmpty {
            rows.append(.init(title: "Unicode notes", value: (Array(NSOrderedSet(array: notes)) as? [String] ?? notes).joined(separator: "\n"), identifier: "characterProperties.notes", monospaced: false, stacked: true))
        }
        if let oldName = character.unicode1Name {
            rows.append(.init(title: "Unicode 1.0 name", value: oldName, identifier: "characterProperties.unicode1Name", monospaced: false, stacked: true))
        }
        if !character.crossReferences.isEmpty {
            rows.append(.init(title: "Related characters", value: character.crossReferences.map { "\($0.codePointLabel) · \($0.name)" }.joined(separator: "\n"), identifier: "characterProperties.references", monospaced: false, stacked: true))
        }
        return rows
    }

    private var propertyRows: [PropertyRow] {
        let decomposition = character.decomposition.flatMap { $0.isEmpty ? nil : $0 }
        var rows: [PropertyRow] = [
            .init(title: "Status", value: character.category == "Cn" ? "Unassigned" : "Assigned", identifier: "characterProperties.status", monospaced: false),
        ]
        if let source = UnicodeFontSupport.sourceName(for: character.displayText, size: 104, enabled: preferences.useUnicodeFonts) {
            rows.append(.init(title: "Preview font", value: source, identifier: "characterProperties.fontSource", monospaced: false))
        }
        rows += [
            .init(title: "Unicode age", value: character.age ?? (character.category == "Cn" ? "Not assigned" : "Pending in the draft data"), identifier: "characterProperties.age", monospaced: false),
            .init(title: "Category", value: "\(character.category) · \(character.categoryName)", identifier: "characterProperties.category", monospaced: false),
            .init(title: "Block", value: character.blockName, identifier: "characterProperties.block", monospaced: false),
        ]
        if preferences.showsUCSUR, let block = UCSUR.block(containing: character.codePoint) {
            rows.append(.init(title: "ConScript block", value: block.name, identifier: "characterProperties.ucsur", monospaced: false))
        }
        rows += [
            .init(title: "Script", value: character.script ?? "Not listed in this source", identifier: "characterProperties.script", monospaced: false),
            .init(title: "Decimal", value: String(character.codePoint), identifier: "characterProperties.decimal", monospaced: false),
            .init(title: "UTF-8", value: character.text.utf8.map { String(format: "%02X", $0) }.joined(separator: " "), identifier: "characterProperties.utf8"),
            .init(title: "UTF-16", value: character.text.utf16.map { String(format: "%04X", $0) }.joined(separator: " "), identifier: "characterProperties.utf16"),
            .init(title: "Bidi class", value: character.bidirectionalClass ?? "Not listed in this source", identifier: "characterProperties.bidi", monospaced: character.bidirectionalClass != nil),
            .init(title: "Combining class", value: character.combiningClass.map(String.init) ?? "Not listed in this source", identifier: "characterProperties.combining", monospaced: false),
            .init(title: "Decomposition", value: decomposition ?? "None listed", identifier: "characterProperties.decomposition", monospaced: decomposition != nil),
        ]
        if let value = character.numericValue {
            rows.append(.init(title: "Numeric value", value: value, identifier: "characterProperties.numericValue"))
        }
        if let type = character.numericType {
            rows.append(.init(title: "Numeric type", value: type, identifier: "characterProperties.numericType", monospaced: false))
        }
        if let point = character.simpleUppercase { rows.append(.init(title: "Uppercase", value: codePointText(point), identifier: "characterProperties.uppercase")) }
        if let point = character.simpleLowercase { rows.append(.init(title: "Lowercase", value: codePointText(point), identifier: "characterProperties.lowercase")) }
        if let point = character.simpleTitlecase { rows.append(.init(title: "Titlecase", value: codePointText(point), identifier: "characterProperties.titlecase")) }
        return rows
    }

    private var characterDescription: String {
        // Structured notes are shown once below, with their source context.
        if !character.annotations.isEmpty || !character.sectionAnnotations.isEmpty { return character.categoryName }
        return character.detail.isEmpty ? character.categoryName : character.detail
    }

    private func codePointText(_ value: UInt32) -> String {
        String(format: "U+%04X", value) + (UnicodeScalar(value).map { " · \(String($0))" } ?? "")
    }
}

struct ScratchpadView: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .font(.title2).padding(8).scrollContentBackground(.hidden)
                    .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("scratchpadInput")
                Text("Add characters from their detail pages, or type here with Uniboard.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(16).background(Color.groupedBackground)
            .navigationTitle("Scratchpad").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Clear", systemImage: "trash", role: .destructive) { confirmClear = true }
                        .disabled(text.isEmpty)
                    Spacer()
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = text
                        copied = true
                    }
                    .disabled(text.isEmpty)
                }
            }
            .confirmationDialog("Clear your scratchpad?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Scratchpad", role: .destructive) { text = "" }
            }
        }
    }
}
