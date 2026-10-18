import SwiftUI

enum Palette {
    static let accent = Color(light: 0xB94D2C, dark: 0xF39A73)
    static let background = Color(light: 0xF7F5F0, dark: 0x171917)
    static let surface = Color(light: 0xFFFFFF, dark: 0x252824)
    static let soft = Color(light: 0xEEECE5, dark: 0x30352F)
    static let ink = Color(light: 0x29332C, dark: 0xE8EAE2)
    static let muted = Color(light: 0x6C736A, dark: 0xA3ADA0)
    static let line = Color(light: 0xDEDFD5, dark: 0x3E453C)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink)
            Spacer()
            if let trailing { Text(trailing).font(.caption.monospaced()).foregroundStyle(Palette.muted) }
        }
    }
}

struct CharacterTile: View {
    let character: UnicodeCharacter
    @EnvironmentObject private var preferences: CatalogPreferences
    var saved = false
    var action: () -> Void
    @State private var hoverTask: Task<Void, Never>?
    private var ageText: String {
        if let age = character.age { return "Unicode " + age }
        return character.category == "Cn" ? "Unassigned" : "Age pending"
    }

    var body: some View {
            VStack(spacing: 5) {
                Text(character.displayText)
                    .font(Font(UnicodeFontSupport.font(for: character.displayText, size: 31, enabled: preferences.useUnicodeFonts)))
                    .foregroundStyle(Palette.ink)
                    .frame(height: 39)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(character.codePointLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                Text(character.name.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 26)
                Text(ageText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("age-\(character.codePointLabel)")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 126)
            .padding(.horizontal, 3)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .topTrailing) {
                if saved { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Palette.accent).padding(8) }
            }
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .gesture(LongPressGesture(minimumDuration: 0.4).exclusively(before: TapGesture()).onEnded { _ in action() })
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                    guard !Task.isCancelled else { return }
                    action()
                }
            }
        }
        .onDisappear { hoverTask?.cancel() }
        .accessibilityLabel("\(character.name), \(character.codePointLabel)")
        .accessibilityValue(ageText)
        .accessibilityHint("Tap, hold, or hover to show Unicode properties and description")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityAction(named: Text("Inspect character"), action)
        .accessibilityIdentifier("character-\(character.codePointLabel)")
    }
}

struct CharacterGrid: View {
    let characters: [UnicodeCharacter]
    @EnvironmentObject private var store: CharacterStore
    var select: (UnicodeCharacter) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 9)], spacing: 9) {
            ForEach(characters) { character in
                CharacterTile(character: character, saved: store.isFavorite(character.codePoint)) { select(character) }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    var identifier = "unicodeSearch"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.accent)
            AppSearchField(text: $text, placeholder: placeholder, identifier: identifier)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }
}

struct EmptyCollection: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(Palette.accent)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(message).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }
}
