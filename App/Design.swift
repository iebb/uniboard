import SwiftUI

/// Screens use iOS semantic colors and the system tint so they follow Light,
/// Dark and Increased Contrast exactly like built-in apps.
extension Color {
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Behind a preview whose glyph iOS and every installed fallback still
    /// draws as a placeholder.
    static let missingGlyph = Color.red.opacity(0.16)

    static func previewSurface(missing: Bool) -> Color { missing ? .missingGlyph : .groupedSurface }
}

/// A colored corner ribbon naming the Unicode or Emoji version that added a
/// character. Each version keeps its own hue everywhere it appears.
struct VersionRibbon: View {
    /// A version such as "18.0" or "15.1", or nil for draft additions.
    let version: String?
    var prefix = ""
    var labeled = true

    static func color(for version: String?) -> Color {
        guard let version, let major = Double(version.split(separator: ".").first ?? "") else { return .purple }
        // Golden-ratio steps keep neighbouring versions far apart in hue.
        let hue = (major * 0.618_034 + 0.08).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.62, brightness: 0.78)
    }
    private var label: String {
        guard let version else { return "draft" }
        return prefix + (version.hasSuffix(".0") ? String(version.dropLast(2)) : version)
    }

    var body: some View {
        if labeled {
            Text(label)
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 64, height: 15)
                .background(Self.color(for: version))
                // Centre the band 14pt in from the corner, along the diagonal.
                .rotationEffect(.degrees(45))
                .offset(x: 18, y: 6.5)
                .accessibilityHidden(true)
        } else {
            Path { path in
                path.move(to: .zero); path.addLine(to: CGPoint(x: 10, y: 0)); path.addLine(to: CGPoint(x: 10, y: 10))
            }
            .fill(Self.color(for: version))
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
        }
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
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
    private var missing: Bool {
        UnicodeFontSupport.stockFontsMiss(character.displayText)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(character.displayText)
                .font(Font(UnicodeFontSupport.font(for: character.displayText, size: 32, enabled: preferences.useUnicodeFonts)))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 44)
            Text(character.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 28)
            Text(character.codePointLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 106)
        .padding(.horizontal, 4)
            .background(Color.previewSurface(missing: missing))
            .overlay(alignment: .topTrailing) {
                if character.category != "Cn" { VersionRibbon(version: character.age) }
            }
            .overlay(alignment: .topLeading) {
                if saved { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(7) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    /// Called when the last character scrolls into view, to load the next page.
    var onReachEnd: (() -> Void)? = nil
    @EnvironmentObject private var store: CharacterStore
    var select: (UnicodeCharacter) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 8)], spacing: 8) {
            ForEach(characters) { character in
                CharacterTile(character: character, saved: store.isFavorite(character.codePoint)) { select(character) }
                    .onAppear { if character.id == characters.last?.id { onReachEnd?() } }
            }
        }
    }
}

/// Drawn like the system search field; the text itself stays a UIKit field
/// so the caret and literal input traits survive SwiftUI refreshes.
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    var identifier = "unicodeSearch"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            AppSearchField(text: $text, placeholder: placeholder, identifier: identifier)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Self.usesCapsule ? 14 : 8)
        .frame(height: Self.usesCapsule ? 44 : 36)
        .background(Color(uiColor: .tertiarySystemFill), in: Self.shape)
    }

    private static var usesCapsule: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
    private static var shape: AnyShape {
        usesCapsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyCollection: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

struct PropertyRow: Identifiable {
    let title: String
    let value: String
    /// Accessibility identifier of the value text.
    let identifier: String
    var monospaced = true
    /// Prose and multi-line values read better below their title.
    var stacked = false
    var id: String { identifier }
}

/// An inset grouped section that stays fully materialized inside a sheet's
/// scroll view, so every property remains reachable by VoiceOver and tests.
struct PropertyGroup: View {
    let title: String
    let rows: [PropertyRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Self.headerFont).foregroundStyle(.secondary)
                .textCase(Self.headerCase)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 16) }
                    cell(row)
                }
            }
            .background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // Match native Form section headers on each system generation.
    private static var headerFont: Font {
        if #available(iOS 26.0, *) { return .headline }
        return .footnote
    }
    private static var headerCase: Text.Case? {
        if #available(iOS 26.0, *) { return nil }
        return .uppercase
    }

    @ViewBuilder private func cell(_ row: PropertyRow) -> some View {
        let value = Text(row.value)
            .font(row.monospaced ? .body.monospaced() : .body)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier(row.identifier)
        Group {
            if row.stacked {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).font(.subheadline).foregroundStyle(.secondary)
                    value
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.title).fixedSize()
                    Spacer(minLength: 8)
                    value.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
