import SwiftUI

struct CharacterDetailView: View {
    let character: UnicodeCharacter
    @Binding var scratchpad: String
    @EnvironmentObject private var store: CharacterStore
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
                                .font(.system(size: 104, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text(character.codePointLabel)
                                .font(.subheadline.monospaced().weight(.medium))
                                .foregroundStyle(Palette.accent)
                        }.padding(27)
                    }.frame(height: 223)

                    VStack(spacing: 9) {
                        Text(character.name.capitalized)
                            .font(.system(size: 27, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center).foregroundStyle(Palette.ink)
                        Text(character.blockName).font(.subheadline).foregroundStyle(Palette.muted)
                    }

                    if !character.detail.isEmpty {
                        Text(character.detail)
                            .font(.subheadline).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                    }
                    if character.isInvisible {
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

                    HStack(spacing: 0) {
                        metadata("DECIMAL", value: String(character.codePoint))
                        Spacer()
                        metadata("UTF-8", value: character.text.utf8.map { String(format: "%02X", $0) }.joined(separator: " "))
                        Spacer()
                        metadata("CATEGORY", value: character.category)
                    }
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

    private func metadata(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
            Text(value).font(.caption.monospaced()).foregroundStyle(Palette.ink).textSelection(.enabled)
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
