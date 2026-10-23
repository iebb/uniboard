import SwiftUI

/// Screens use iOS semantic colors and the system tint so they follow Light,
/// Dark and Increased Contrast exactly like built-in apps.
extension Color {
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Behind a preview whose glyph iOS and every installed fallback still
    /// draws as a placeholder.
    static let missingGlyph = Color.red.opacity(0.16)
    /// Behind a Private Use character the ConScript Unicode Registry assigns.
    static let ucsur = Color.blue.opacity(0.16)

    static func previewSurface(missing: Bool, ucsur: Bool = false) -> Color {
        ucsur ? .ucsur : missing ? .missingGlyph : .groupedSurface
    }
}

/// A colored corner ribbon naming the Unicode or Emoji version that added a
/// character. Versions run through the rainbow from red, the oldest, to
/// blue, the newest; draft additions are purple.
struct VersionRibbon: View {
    /// A version such as "18.0" or "15.1", or nil for draft additions.
    let version: String?
    var prefix = ""
    var labeled = true
    /// Leg length of the unlabeled corner triangle.
    var triangleSide: CGFloat = 10
    /// A ConScript character reads CSUR, its registry, rather than its Unicode age.
    var conscript = false

    /// The unlabeled triangle grows with the tile's corner radius, so it stays
    /// visible past the rounded corner: 18pt on 12pt tiles, 14pt on 8pt, 10pt on 4pt.
    static func triangleSide(cornerRadius: CGFloat) -> CGFloat { max(10, cornerRadius + 6) }

    static let conscriptColor = Color.indigo
    static func color(for version: String?) -> Color {
        guard let version, let number = Double(version) else { return .purple }
        // Emoji 0.6 is the oldest and Unicode 18 the newest final version.
        let position = min(1, max(0, (number - 0.6) / (18 - 0.6)))
        return Color(hue: position * 0.66, saturation: 0.72, brightness: 0.74)
    }
    private var color: Color { conscript ? Self.conscriptColor : Self.color(for: version) }
    private var label: String {
        if conscript { return "CSUR" }
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
                .background(color)
                // Centre the band 14pt in from the corner, along the diagonal.
                .rotationEffect(.degrees(45))
                .offset(x: 18, y: 6.5)
                .accessibilityHidden(true)
        } else {
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: triangleSide, y: 0))
                path.addLine(to: CGPoint(x: triangleSide, y: triangleSide))
            }
            .fill(color)
            .frame(width: triangleSide, height: triangleSide)
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

/// How many character tiles Explore shows per row.
enum GridDensity: Int, CaseIterable, Identifiable {
    case three = 3, eight = 8, sixteen = 16, thirtyTwo = 32
    var id: Int { rawValue }
    var title: String { self == .three ? "Tiles" : "\(rawValue) per Row" }
    var symbol: String {
        switch self {
        case .three: return "square.grid.3x3"
        case .eight: return "square.grid.4x3.fill"
        case .sixteen: return "circle.grid.3x3.fill"
        case .thirtyTwo: return "square.grid.3x3.fill"
        }
    }
    var spacing: CGFloat {
        switch self {
        case .three: return 8
        case .eight: return 4
        case .sixteen, .thirtyTwo: return 2
        }
    }
    /// Characters per page, so each page fills a similar screen area.
    var pageSize: Int {
        switch self {
        case .three: return 160
        case .eight: return 320
        case .sixteen: return 640
        case .thirtyTwo: return 1280
        }
    }
}

extension GridDensity {
    /// 16 and 32 per row show only the glyph.
    var isDense: Bool { rawValue >= 16 }
    /// Widest a grid of this density grows, so wide screens and phones held
    /// sideways give charts room.
    var maximumWidth: CGFloat { self == .thirtyTwo ? 1600 : self == .sixteen ? 1100 : 780 }
    /// 32 per row needs a wide screen, such as an iPad.
    static func offered(width: CGFloat) -> [GridDensity] { allCases.filter { $0 != .thirtyTwo || width >= 960 } }
    /// This density, or 16 per row when 32 does not fit `width`.
    func fitting(_ width: CGFloat) -> GridDensity { self == .thirtyTwo && width > 0 && width < 960 ? .sixteen : self }

    /// Width of the frozen leading column of row code points.
    var rowLabelWidth: CGFloat { self == .sixteen ? 28 : 34 }

    /// The side of a square cell when a row of this density fills `width`.
    func cellSide(in width: CGFloat) -> CGFloat {
        let columns = CGFloat(rawValue)
        return max(8, ((width - rowLabelWidth - spacing * columns) / columns).rounded(.down))
    }

    /// 16 columns share a row prefix ("004" + column 0–F); 8 columns show
    /// the row's first code point and offsets +0…+7.
    func rowLabel(_ start: UInt32) -> String {
        self == .sixteen ? String(format: "%03X", start >> 4) : String(format: "%04X", start)
    }
    func columnLabel(_ column: Int) -> String {
        isDense ? String(format: "%X", column) : "+\(column)"
    }
}

/// How the tile grid sizes its columns and marks each tile's version.
enum TileGridLayout {
    static let spacing: CGFloat = 8
    static let minimumColumns = 2
    /// Columns shown before the grid's width is known.
    static let defaultMaximumColumns = 7
    /// Pinching never makes tiles narrower than this.
    static let minimumTileWidth: CGFloat = 32
    /// Narrower tiles show a corner triangle instead of the labeled ribbon.
    static let labeledRibbonMinimumWidth: CGFloat = 80
    /// Narrower tiles leave out the code point and show only the glyph.
    static let codePointMinimumWidth: CGFloat = 44

    /// The most columns whose tiles stay at least `minimumTileWidth` wide in
    /// `width`, and never fewer than `minimumColumns`.
    static func maximumColumns(in width: CGFloat, spacing: CGFloat = spacing) -> Int {
        guard width > 0 else { return defaultMaximumColumns }
        let fitting = Int(((width + spacing) / (minimumTileWidth + spacing)).rounded(.down))
        return max(minimumColumns, fitting)
    }

    /// The stored column preference, clamped to what fits `width`.
    static func columns(stored: Int, in width: CGFloat, spacing: CGFloat = spacing) -> Int {
        min(maximumColumns(in: width, spacing: spacing), max(minimumColumns, stored))
    }

    /// The width of one tile when `columns` tiles share `width`, or 0 when
    /// the width is not known yet.
    static func tileWidth(columns: Int, in width: CGFloat, spacing: CGFloat = spacing) -> CGFloat {
        guard width > 0, columns > 0 else { return 0 }
        return max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// Block view and tiles under 80 points show only a corner triangle; an
    /// unmeasured tile keeps the ribbon.
    static func showsLabeledRibbon(tileWidth: CGFloat, blockView: Bool) -> Bool {
        !blockView && (tileWidth <= 0 || tileWidth >= labeledRibbonMinimumWidth)
    }

    static func showsCodePoint(tileWidth: CGFloat) -> Bool {
        tileWidth <= 0 || tileWidth >= codePointMinimumWidth
    }
}

struct CharacterTile: View {
    let character: UnicodeCharacter
    @EnvironmentObject private var preferences: CatalogPreferences
    var saved = false
    var density: GridDensity = .three
    /// A code chart labels rows and columns, so its tiles omit the code point.
    var showsCodePoint = true
    /// Narrow tiles leave out the name.
    var showsName = true
    /// Square side for dense rows, measured from the available width.
    var side: CGFloat = 40
    /// Measured width of a full tile, or 0 when unknown.
    var tileWidth: CGFloat = 0
    /// Block view marks the version with a corner triangle only.
    var blockView = false
    var action: () -> Void
    @State private var hoverTask: Task<Void, Never>?
    private var ageText: String {
        if let age = character.age { return "Unicode " + age }
        return character.category == "Cn" ? "Unassigned" : "Age pending"
    }
    private var glyphSize: CGFloat {
        switch density {
        case .three:
            // Narrow tiles shrink the glyph to their width.
            return tileWidth > 0 ? min(32, max(14, (tileWidth - 8) * 0.8)) : 32
        case .eight: return showsCodePoint ? 22 : 26
        case .sixteen, .thirtyTwo: return 15
        }
    }
    private var cornerRadius: CGFloat {
        switch density {
        case .three: return 12
        case .eight: return 8
        case .sixteen, .thirtyTwo: return 4
        }
    }
    private var missing: Bool {
        UnicodeFontSupport.stockFontsMiss(character.displayText)
    }

    var body: some View {
        content
            .background(Color.previewSurface(missing: missing, ucsur: preferences.isUCSUR(character.codePoint)))
            .overlay(alignment: .topTrailing) {
                if !density.isDense, character.category != "Cn" {
                    VersionRibbon(version: character.age,
                                  labeled: density == .three && TileGridLayout.showsLabeledRibbon(tileWidth: tileWidth, blockView: blockView),
                                  triangleSide: VersionRibbon.triangleSide(cornerRadius: cornerRadius),
                                  conscript: preferences.isUCSUR(character.codePoint))
                }
            }
            .overlay(alignment: .topLeading) {
                if saved, !density.isDense {
                    Image(systemName: "star.fill").font(.system(size: density == .three ? 9 : 6)).foregroundStyle(.yellow)
                        .padding(density == .three ? 7 : 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name), \(character.codePointLabel)")
        .accessibilityValue(ageText)
        .accessibilityHint("Tap, hold, or hover to show Unicode properties and description")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityAction(named: Text("Inspect character"), action)
        .accessibilityIdentifier("character-\(character.codePointLabel)")
    }

    private var glyph: some View {
        Text(character.displayText)
            .font(Font(UnicodeFontSupport.font(for: character.displayText, size: glyphSize, enabled: preferences.useUnicodeFonts)))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder private var content: some View {
        switch density {
        case .three:
            let showsCode = TileGridLayout.showsCodePoint(tileWidth: tileWidth)
            VStack(spacing: 3) {
                glyph.frame(height: 44)
                if showsName {
                    Text(character.name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(height: 28)
                }
                if showsCode {
                    Text(character.codePointLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: showsName ? 106 : showsCode ? 72 : 52)
            .padding(.horizontal, 4)
        case .eight:
            VStack(spacing: 1) {
                glyph.frame(height: showsCodePoint ? 26 : 34)
                if showsCodePoint {
                    Text(character.codePointLabel)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 2)
            .frame(width: side, height: side)
        case .sixteen, .thirtyTwo:
            glyph
                .frame(width: side, height: side)
        }
    }
}

struct CharacterGrid: View {
    let characters: [UnicodeCharacter]
    /// Explore chooses a fixed density; other screens keep adaptive columns.
    var density: GridDensity? = nil
    /// The grid's measured width, which sizes dense cells.
    var width: CGFloat = 0
    /// Called when the last character scrolls into view, to load the next page.
    var onReachEnd: (() -> Void)? = nil
    @EnvironmentObject private var store: CharacterStore
    /// Tiles per row, shared by every tile grid; pinch to change it.
    @AppStorage("tileColumns") private var tileColumns = 3
    @State private var pinch: CGFloat = 1
    /// The tile grid's own measured width, which caps its columns.
    @State private var gridWidth: CGFloat = 0
    /// Block view marks versions with a corner triangle only.
    var blockView = false
    var select: (UnicodeCharacter) -> Void

    var body: some View {
        if let density, density != .three, width > 0 {
            let side = density.cellSide(in: width)
            // Dense rows keep a frozen leading column with each row's first code point.
            let rows = stride(from: 0, to: characters.count, by: density.rawValue).map {
                Array(characters[$0..<min($0 + density.rawValue, characters.count)])
            }
            LazyVStack(spacing: density.spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: density.spacing) {
                        Text(String(format: "%04X", row[0].codePoint))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: density.rowLabelWidth, alignment: .leading)
                            .accessibilityHidden(true)
                        ForEach(0..<density.rawValue, id: \.self) { column in
                            if column < row.count {
                                tile(row[column], density: density, side: side)
                            } else {
                                Color.clear.frame(width: side, height: side)
                            }
                        }
                    }
                    .onAppear { if index == rows.count - 1 { onReachEnd?() } }
                }
            }
        } else {
            // A preference wider than this screen allows is clamped here and kept for wider screens.
            let columns = TileGridLayout.columns(stored: tileColumns, in: gridWidth)
            let tileWidth = TileGridLayout.tileWidth(columns: columns, in: gridWidth)
            let spacing = TileGridLayout.spacing
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(characters) { character in
                    tile(character, density: .three, side: 0, showsName: columns <= 4, tileWidth: tileWidth)
                        .onAppear { if character.id == characters.last?.id { onReachEnd?() } }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .simultaneousGesture(MagnifyGesture()
                .onChanged { pinch = $0.magnification }
                .onEnded { _ in
                    // Spreading the fingers zooms in to fewer, larger tiles,
                    // down to the narrowest tiles this width allows.
                    let step = pinch > 1.15 ? -1 : pinch < 0.87 ? 1 : 0
                    if step != 0 { tileColumns = TileGridLayout.columns(stored: columns + step, in: gridWidth) }
                    pinch = 1
                })
            .animation(.snappy, value: columns)
        }
    }

    private func tile(_ character: UnicodeCharacter, density: GridDensity, side: CGFloat, showsName: Bool = true,
                      tileWidth: CGFloat = 0) -> some View {
        CharacterTile(character: character, saved: store.isFavorite(character.codePoint), density: density,
                      showsName: showsName, side: side, tileWidth: tileWidth, blockView: blockView) { select(character) }
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
