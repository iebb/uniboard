import SwiftUI
import UIKit
import CoreText

// The Styles grid on a Google font family page (design/styles-grid). The
// sorting into cells, the menu and file coverage live in Shared/StyleGrid.swift;
// this file draws them and loads the "Ag" samples of downloaded files.

extension StyleGrid {
    /// §1 for one catalog family. A file the catalog doesn't list counts as
    /// not under `/static/`.
    static func make(family: GoogleFontFamily, catalog: GoogleFontCatalog?, downloadedFileIDs: Set<String>) -> StyleGrid {
        var files: [String: StyleGridFile] = [:]
        for style in family.styles {
            if let file = catalog?.file(id: style.fileID) { files[file.id] = StyleGridFile(id: file.id, path: file.repositoryPath, bytes: file.bytes) }
        }
        let styles = family.styles.map {
            StyleGridStyle(id: $0.id, name: $0.name, fileID: $0.fileID, postScriptName: $0.postScriptName, variationInstance: $0.variationInstance)
        }
        return make(styles: styles, files: files, downloadedFileIDs: downloadedFileIDs)
    }
}

/// One downloaded face's sample: drawn, or the face lacks the text.
enum StyleSample {
    case image(UIImage)
    /// The face covers neither the inspected text nor "Ag".
    case uncovered
    /// The face couldn't be loaded exactly; the placeholder stays.
    case failed
}

/// Samples are only drawn from downloaded files, off the main thread, in the
/// exact face (file, instance coordinates, face index 0) with no fallback
/// font, and cached per file and coordinates. One file's samples publish
/// together.
@MainActor
final class StyleSampleLoader: ObservableObject {
    struct Key: Hashable, Sendable {
        let fileID: String
        let coordinates: String
        let text: String
        let size: CGFloat
    }

    @Published private(set) var samples: [Key: StyleSample] = [:]
    private var loading: Set<Key> = []

    nonisolated static func key(fileID: String, axes: [String: Double]?, text: String?, size: CGFloat) -> Key {
        Key(fileID: fileID, coordinates: PublicFontInventory.axisKey(axes ?? [:]), text: text ?? "", size: size)
    }

    func sample(_ style: StyleGridStyle, text: String?, size: CGFloat) -> StyleSample? {
        samples[Self.key(fileID: style.fileID, axes: style.variationInstance, text: text, size: size)]
    }

    func load(file: GoogleFontFile, styles: [StyleGridStyle], text: String?, size: CGFloat, scale: CGFloat) async {
        let wanted = styles.filter {
            let key = Self.key(fileID: file.id, axes: $0.variationInstance, text: text, size: size)
            return samples[key] == nil && !loading.contains(key)
        }
        guard !wanted.isEmpty else { return }
        let keys = wanted.map { Self.key(fileID: file.id, axes: $0.variationInstance, text: text, size: size) }
        loading.formUnion(keys)
        let catalogStyles = wanted.map {
            GoogleFontStyle(id: $0.id, name: $0.name, fileID: $0.fileID, postScriptName: $0.postScriptName, variationInstance: $0.variationInstance)
        }
        let drawn = await Task.detached(priority: .userInitiated) {
            SendableSamples(value: Self.render(file: file, styles: catalogStyles, text: text, size: size, scale: scale))
        }.value.value
        loading.subtract(keys)
        samples.merge(drawn) { _, new in new }
    }

    private struct SendableSamples: @unchecked Sendable { let value: [Key: StyleSample] }

    nonisolated private static func render(file: GoogleFontFile, styles: [GoogleFontStyle], text: String?, size: CGFloat,
                                           scale: CGFloat) -> [Key: StyleSample] {
        var result: [Key: StyleSample] = [:]
        let state = try? CustomFontStore.shared.readLibraryState()
        let provider = PublicFontInventory()
        // The CGFont, its provider and its bytes stay alive while any instance draws.
        var opened: (url: URL, data: CFData, provider: CGDataProvider, font: CGFont)?
        for style in styles {
            let key = key(fileID: file.id, axes: style.variationInstance, text: text, size: size)
            guard let face = state?.snapshot.faces.first(where: { FontDetailIdentity.matches($0, file: file, style: style) }),
                  let url = provider.fileURL(for: face), PublicFontInventory.isSingleFaceSFNT(url) else { result[key] = .failed; continue }
            if opened?.url != url {
                guard let bytes = try? Data(contentsOf: url), let data = CGDataProvider(data: bytes as CFData),
                      let font = CGFont(data), let name = font.postScriptName as String?,
                      file.expectedPostScriptNames.contains(name) else { result[key] = .failed; continue }
                opened = (url, bytes as CFData, data, font)
            }
            result[key] = withExtendedLifetime(opened) {
                sample(opened!.font, axes: style.variationInstance ?? [:], text: text, size: size, scale: scale)
            }
        }
        return result
    }

    nonisolated private static func sample(_ graphics: CGFont, axes: [String: Double], text: String?, size: CGFloat,
                                           scale: CGFloat) -> StyleSample {
        guard let canonical = PublicFontInventory.canonicalAxes(axes) else { return .failed }
        let variation = Dictionary(uniqueKeysWithValues: canonical.map { (NSNumber(value: $0.key), NSNumber(value: $0.value)) })
        // An empty cascade list: CoreText never substitutes another font.
        let attributes: [CFString: Any] = [kCTFontVariationAttribute: variation, kCTFontCascadeListAttribute: [CTFontDescriptor]()]
        let font = CTFontCreateWithGraphicsFont(graphics, size, nil, CTFontDescriptorCreateWithAttributes(attributes as CFDictionary))
        let effective = FontLineVerifier.effectiveCoordinates(font)
        for (axis, requested) in variation {
            guard let actual = effective[axis]?.doubleValue, abs(actual - requested.doubleValue) <= 0.0001 else { return .failed }
        }
        for candidate in [text ?? "", "Ag"] where !candidate.isEmpty {
            let units = Array(candidate.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), let image = draw(candidate, font: font, scale: scale) {
                return .image(image)
            }
        }
        return .uncovered
    }

    /// Black glyphs on clear, as a template image the view tints with the label color.
    nonisolated private static func draw(_ text: String, font: CTFont, scale: CGFloat) -> UIImage? {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): UIColor.black.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        var bounds = CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        if !ink.isNull && !ink.isInfinite { bounds = bounds.union(ink) }
        bounds = bounds.integral
        guard bounds.width > 0, bounds.height > 0, bounds.width < 2048, bounds.height < 2048 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
            cg.textPosition = CGPoint(x: -bounds.minX, y: -bounds.minY)
            CTLineDraw(line, cg)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// Today's per-file status icons (§4 badge). Decorative: cells and container
/// headers carry the state for VoiceOver.
struct StyleStatusBadge: View {
    let status: StyleFileStatus
    let size: CGFloat

    var body: some View {
        Group {
            switch status {
            case .notDownloaded:
                Image(systemName: "arrow.down.circle").font(.system(size: size)).foregroundStyle(.tint)
            case .downloading:
                ProgressView().controlSize(.small).tint(.accentColor)
                    .scaleEffect(13 / 20).frame(width: size, height: size)
            case .downloaded:
                Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundStyle(.tint)
            case .unavailable:
                Image(systemName: "exclamationmark.circle").font(.system(size: size))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The grid row of the Styles section (§3–§5, §7).
struct StyleGridView: View {
    let grid: StyleGrid
    let set: StyleGrid.StyleSet
    let selectedStyleID: String?
    let files: [String: GoogleFontFile]
    let states: [String: GoogleFontDownloadState]
    /// The inspected character, drawn instead of "Ag" when the face covers it.
    let sampleText: String?
    let disabled: Bool
    @ObservedObject var samples: StyleSampleLoader
    let select: (StyleGrid.Cell) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title2) private var sampleSize: CGFloat = 22

    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if stacked { stackedGrid } else { columnGrid }
            }
            .accessibilityElement(children: .contain)
            if !grid.familyHasItalic {
                Text(StyleGridCopy.noItalics).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: loadKey) { await loadSamples() }
    }

    // MARK: Files

    private func status(_ fileID: String) -> StyleFileStatus {
        files[fileID].map { StyleFileStatus(file: $0, state: states[$0.id]) } ?? .unavailable(reason: "")
    }
    private func size(_ fileID: String) -> String {
        ByteCountFormatter.string(fromByteCount: files[fileID]?.bytes ?? 0, countStyle: .file)
    }
    /// The file filling every cell of one column, drawn as one container.
    private func columnFile(italic: Bool) -> String? {
        let ids = Set(set.cells.filter { $0.key.italic == italic }.map(\.style.fileID))
        guard ids.count == 1, let id = ids.first, grid.coverage(of: id, in: set) == .column(italic: italic) else { return nil }
        return id
    }
    /// The file filling every cell of both columns.
    private var sharedFile: String? {
        let ids = Set(set.cells.map(\.style.fileID))
        guard ids.count == 1, let id = ids.first, grid.coverage(of: id, in: set) == .both else { return nil }
        return id
    }
    private func ownsBadge(_ cell: StyleGrid.Cell) -> Bool {
        switch grid.coverage(of: cell.style.fileID, in: set) {
        case .single, .scattered: return true
        case .column, .both: return false
        }
    }
    private func fileLabel(_ fileID: String, title: String) -> String {
        [title, status(fileID).label, size(fileID)].joined(separator: ", ")
    }

    // MARK: Columns (§3)

    private var headerHeight: CGFloat {
        if sharedFile != nil { return 28 + 24 }
        return columnFile(italic: false) != nil || columnFile(italic: true) != nil ? 44 : 24
    }

    private var columnGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear.frame(height: headerHeight)
                ForEach(set.rows) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.name).font(.subheadline).foregroundStyle(Color(uiColor: .label))
                        Text(verbatim: String(row.weight)).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .frame(height: cellHeight)
                }
            }
            .frame(width: 84)
            .accessibilityHidden(true)
            if let shared = sharedFile {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        StyleStatusBadge(status: status(shared), size: badgeSize)
                        Text(StyleGridCopy.fileLine(grid.styleCount(fileID: shared), size: size(shared)))
                            .font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(height: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(fileLabel(shared, title: StyleGridCopy.sharedStylesFile))
                    .accessibilitySortPriority(2000)
                    HStack(spacing: 8) {
                        column(italic: false, container: nil, headerHeight: 24, inset: true)
                        column(italic: true, container: nil, headerHeight: 24, inset: true)
                    }
                }
                .padding(.bottom, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill)))
            } else {
                if set.hasNormal { column(italic: false, container: columnFile(italic: false), headerHeight: headerHeight, inset: false) }
                if set.hasItalic { column(italic: true, container: columnFile(italic: true), headerHeight: headerHeight, inset: false) }
            }
        }
    }

    private func column(italic: Bool, container: String?, headerHeight: CGFloat, inset: Bool) -> some View {
        VStack(spacing: 6) {
            header(italic: italic, file: container)
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)
            ForEach(Array(set.rows.enumerated()), id: \.element.id) { index, row in
                slot(row, italic: italic, index: index, inContainer: inset || container != nil)
                    .frame(height: cellHeight)
            }
        }
        .padding(.bottom, container != nil ? 6 : 0)
        .background {
            if container != nil {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Normal" / "Italic", with the badge and size when one file fills the column.
    @ViewBuilder private func header(italic: Bool, file: String?) -> some View {
        let title = italic ? StyleGridCopy.italic : StyleGridCopy.normal
        if let file {
            VStack(spacing: 2) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color(uiColor: .secondaryLabel))
                HStack(spacing: 4) {
                    StyleStatusBadge(status: status(file), size: badgeSize)
                    Text(size(file)).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fileLabel(file, title: italic ? StyleGridCopy.italicStylesFile : StyleGridCopy.normalStylesFile))
            .accessibilitySortPriority(italic ? 1999 : 2000)
        } else {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
    }

    // MARK: Accessibility sizes (§7)

    private var stackedGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let shared = sharedFile {
                HStack(spacing: 6) {
                    StyleStatusBadge(status: status(shared), size: badgeSize)
                    Text(StyleGridCopy.fileLine(grid.styleCount(fileID: shared), size: size(shared)))
                        .font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fileLabel(shared, title: StyleGridCopy.sharedStylesFile))
                .accessibilitySortPriority(2000)
            }
            HStack(alignment: .top, spacing: 8) {
                if set.hasNormal { stackedHeader(italic: false) }
                if set.hasItalic { stackedHeader(italic: true) }
            }
            ForEach(Array(set.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.name).font(.title3).foregroundStyle(Color(uiColor: .label))
                        Text(verbatim: String(row.weight)).font(.body).foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    HStack(spacing: 8) {
                        if set.hasNormal { slot(row, italic: false, index: index, inContainer: false).frame(height: cellHeight) }
                        if set.hasItalic { slot(row, italic: true, index: index, inContainer: false).frame(height: cellHeight) }
                    }
                }
            }
        }
    }

    private func stackedHeader(italic: Bool) -> some View {
        let file = sharedFile == nil ? columnFile(italic: italic) : nil
        return VStack(spacing: 2) {
            Text(italic ? StyleGridCopy.italic : StyleGridCopy.normal)
                .font(.footnote.weight(.semibold)).foregroundStyle(Color(uiColor: .secondaryLabel))
            if let file {
                HStack(spacing: 4) {
                    StyleStatusBadge(status: status(file), size: badgeSize)
                    Text(size(file)).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: file == nil ? .ignore : .ignore)
        .accessibilityLabel(file.map { fileLabel($0, title: italic ? StyleGridCopy.italicStylesFile : StyleGridCopy.normalStylesFile) } ?? "")
        .accessibilityHidden(file == nil)
        .accessibilitySortPriority(italic ? 1999 : 2000)
    }

    // MARK: Cells (§4, §5)

    /// A missing combination is an empty slot: no tile, text or VoiceOver element.
    @ViewBuilder private func slot(_ row: StyleGrid.Row, italic: Bool, index: Int, inContainer: Bool) -> some View {
        if let cell = italic ? row.italic : row.normal {
            cellButton(cell, inContainer: inContainer)
                .accessibilitySortPriority(Double(1000 - index * 2 - (italic ? 1 : 0)))
        } else {
            Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
        }
    }

    private func cellButton(_ cell: StyleGrid.Cell, inContainer: Bool) -> some View {
        let selected = cell.style.id == selectedStyleID
        let status = status(cell.style.fileID)
        let count = grid.styleCount(fileID: cell.style.fileID)
        let fill: Color = selected ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14)
            : inContainer ? .clear : Color(uiColor: .tertiarySystemFill)
        return Button { select(cell) } label: {
            content(cell, status: status)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tile.fill(fill))
                .overlay { if selected { tile.strokeBorder(Color.accentColor, lineWidth: 2) } }
                .overlay(alignment: .topTrailing) {
                    if ownsBadge(cell) { StyleStatusBadge(status: status, size: badgeSize).padding(4) }
                }
                .contentShape(tile)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, inContainer ? 4 : 0)
        .frame(minWidth: 48, minHeight: 48)
        .disabled(disabled)
        .accessibilityLabel(grid.displayName(of: cell, in: set))
        .accessibilityValue(count > 1 ? status.label + ", " + StyleGridCopy.fileContains(count) : status.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("fontDetail.style.\(cell.style.id)")
    }

    @ViewBuilder private func content(_ cell: StyleGrid.Cell, status: StyleFileStatus) -> some View {
        if status == .downloaded, let sample = samples.sample(cell.style, text: sampleText, size: sampleSize) {
            switch sample {
            case .image(let image):
                Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .foregroundStyle(Color(uiColor: .label))
                    .padding(4)
                    .accessibilityHidden(true)
            case .uncovered: placeholder(Color(uiColor: .secondaryLabel))
            case .failed: placeholder(Color(uiColor: .tertiaryLabel))
            }
        } else if case .unavailable = status {
            placeholder(Color(uiColor: .quaternaryLabel))
        } else {
            placeholder(Color(uiColor: .tertiaryLabel))
        }
    }

    private func placeholder(_ color: Color) -> some View {
        Image(systemName: "textformat").font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
            .accessibilityHidden(true)
    }

    // MARK: Samples

    private var downloadedCells: [StyleGrid.Cell] { self.set.cells.filter { status($0.style.fileID) == .downloaded } }
    private var loadKey: String {
        downloadedCells.map(\.style.id).joined(separator: "|") + "#\(sampleText ?? "")#\(sampleSize)#\(displayScale)"
    }
    private func loadSamples() async {
        let byFile = Dictionary(grouping: downloadedCells, by: \.style.fileID)
        for fileID in byFile.keys.sorted() {
            guard let file = files[fileID], !Task.isCancelled else { continue }
            await samples.load(file: file, styles: byFile[fileID]!.map(\.style), text: sampleText, size: sampleSize, scale: displayScale)
        }
    }
}
