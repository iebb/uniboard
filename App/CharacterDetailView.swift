import SwiftUI

struct CharacterDetailView: View {
    let character: UnicodeCharacter
    @Binding var scratchpad: String
    @EnvironmentObject private var store: CharacterStore
    @EnvironmentObject private var preferences: CatalogPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var added = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 26).fill(Palette.soft)
                        VStack(spacing: 18) {
                            Text(character.displayText)
                                .font(Font(UnicodeFontSupport.font(for: character.displayText, size: 104, enabled: preferences.useUnicodeFonts)))
                                .foregroundStyle(Palette.ink)
                                .accessibilityIdentifier("characterGlyph")
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text(character.codePointLabel)
                                .font(.subheadline.monospaced().weight(.medium))
                                .foregroundStyle(Palette.accent)
                                .accessibilityIdentifier("characterProperties.codepoints")
                        }.padding(27)
                    }.frame(height: 223)

                    VStack(spacing: 9) {
                        Text(character.name.capitalized)
                            .font(.system(size: 27, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center).foregroundStyle(Palette.ink)
                            .accessibilityIdentifier("characterProperties.name")
                        Text(character.blockName).font(.subheadline).foregroundStyle(Palette.muted)
                        Text(character.category == "Cn" ? "Unassigned" : "Assigned")
                            .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                            .accessibilityIdentifier("characterProperties.status")
                    }

                        Text(characterDescription)
                            .font(.subheadline).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                            .accessibilityIdentifier("characterProperties.description")
                    Text("The name and properties remain available even if your iOS font cannot display this glyph.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    namingInformation
                    if character.category == "Cn" {
                        Label("This code point is not assigned in the selected Unicode edition.", systemImage: "square.dashed")
                            .font(.caption).foregroundStyle(Palette.muted)
                    } else if character.isInvisible {
                        Label("This character is invisible. Its preview is a placeholder; copying inserts the actual character.", systemImage: "eye.slash")
                            .font(.caption).foregroundStyle(Palette.muted)
                    } else if character.category.hasPrefix("M") {
                        Label("The dotted circle is only a preview. This mark combines with the character before it.", systemImage: "circle.dotted")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }

                    VStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = character.text
                            store.recordUse(character.codePoint)
                            copied = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(copied ? "Copied character" : "Copy character", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.headline).frame(maxWidth: .infinity).padding(17)
                                .foregroundStyle(Palette.surface)
                                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 15))
                        }.accessibilityIdentifier("copyCharacter")

                        HStack(spacing: 10) {
                            Button {
                                store.toggleFavorite(character.codePoint)
                            } label: {
                                Label(store.isFavorite(character.codePoint) ? "Saved" : "Save", systemImage: store.isFavorite(character.codePoint) ? "star.fill" : "star")
                                    .frame(maxWidth: .infinity).padding(15)
                                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: 15))
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
                                    .frame(maxWidth: .infinity).padding(15)
                                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: 15))
                            }.accessibilityIdentifier("addToScratchpad")
                        }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                    }.buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 20) {
                        if let source = UnicodeFontSupport.sourceName(for: character.displayText, size: 104, enabled: preferences.useUnicodeFonts) {
                            metadata("PREVIEW FONT", value: source, identifier: "fontSource")
                        }
                        metadata("UNICODE AGE", value: character.age ?? (character.category == "Cn" ? "Not assigned" : "Pending in the draft data"), identifier: "age")
                        metadata("GENERAL CATEGORY", value: "\(character.category) · \(character.categoryName)", identifier: "category")
                        metadata("BLOCK", value: character.blockName, identifier: "block")
                        metadata("SCRIPT", value: character.script ?? "Not listed in this source", identifier: "script")
                        metadata("DECIMAL", value: String(character.codePoint), identifier: "decimal")
                        metadata("UTF-8", value: character.text.utf8.map { String(format: "%02X", $0) }.joined(separator: " "), identifier: "utf8")
                        metadata("UTF-16", value: character.text.utf16.map { String(format: "%04X", $0) }.joined(separator: " "), identifier: "utf16")
                        metadata("BIDIRECTIONAL CLASS", value: character.bidirectionalClass ?? "Not listed in this source", identifier: "bidi")
                        metadata("COMBINING CLASS", value: character.combiningClass.map(String.init) ?? "Not listed in this source", identifier: "combining")
                        metadata("DECOMPOSITION", value: character.decomposition.flatMap { $0.isEmpty ? nil : $0 } ?? "None listed", identifier: "decomposition")
                        if let value = character.numericValue {
                            metadata("NUMERIC VALUE", value: value, identifier: "numericValue")
                        }
                        if let type = character.numericType {
                            metadata("NUMERIC TYPE", value: type, identifier: "numericType")
                        }
                        if let point = character.simpleUppercase { metadata("UPPERCASE", value: codePointText(point), identifier: "uppercase") }
                        if let point = character.simpleLowercase { metadata("LOWERCASE", value: codePointText(point), identifier: "lowercase") }
                        if let point = character.simpleTitlecase { metadata("TITLECASE", value: codePointText(point), identifier: "titlecase") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
                .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .navigationTitle("Character detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }

    private var namingInformation: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !character.nameAliases.isEmpty {
                metadata("ALIASES", value: character.nameAliases.map { "\($0.kindLabel): \($0.name)" }.joined(separator: "\n"), identifier: "aliases", monospaced: false)
            }
            if let section = character.namesListSection {
                metadata("UNICODE SECTION", value: section, identifier: "section", monospaced: false)
            }
            let notes = character.sectionAnnotations + character.annotations
            if !notes.isEmpty { metadata("UNICODE NOTES", value: (Array(NSOrderedSet(array: notes)) as? [String] ?? notes).joined(separator: "\n"), identifier: "notes", monospaced: false) }
            if let oldName = character.unicode1Name {
                metadata("UNICODE 1.0 NAME", value: oldName, identifier: "unicode1Name")
            }
            if !character.crossReferences.isEmpty {
                metadata("RELATED CHARACTERS", value: character.crossReferences.map { "\($0.codePointLabel) · \($0.name)" }.joined(separator: "\n"), identifier: "references", monospaced: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var characterDescription: String {
        // Structured notes are shown once below, with their source context.
        if !character.annotations.isEmpty || !character.sectionAnnotations.isEmpty { return character.categoryName }
        return character.detail.isEmpty ? character.categoryName : character.detail
    }

    private func codePointText(_ value: UInt32) -> String {
        String(format: "U+%04X", value) + (UnicodeScalar(value).map { " · \(String($0))" } ?? "")
    }

    private func metadata(_ title: String, value: String, identifier: String, monospaced: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
            Text(value).font(monospaced ? .caption.monospaced() : .subheadline).foregroundStyle(Palette.ink).textSelection(.enabled)
                .accessibilityIdentifier("characterProperties.\(identifier)")
        }
    }
}

struct ScratchpadView: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Make something\nwith your characters.")
                    .font(.system(size: 32, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                Text("Add characters from their detail cards, or try Uniboard using the keyboard globe.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                TextEditor(text: $text)
                    .font(.title2).padding(12).scrollContentBackground(.hidden)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("scratchpadInput")
                HStack {
                    Button { confirmClear = true } label: { Label("Clear", systemImage: "trash") }
                        .disabled(text.isEmpty)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.borderedProminent).disabled(text.isEmpty)
                }
            }
            .padding(24).background(Palette.background)
            .navigationTitle("Scratchpad").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear your scratchpad?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear scratchpad", role: .destructive) { text = "" }
            }
        }
    }
}
