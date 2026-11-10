import SwiftUI
import UIKit
import CoreText

// The Styles grid on a Google font family page (design/styles-grid). The
// sorting into cells, the menu and file coverage live in Shared/StyleGrid.swift;
// this file draws them and loads the "Ag" samples of downloaded files.

extension StyleGrid {
    /// §1 for one catalog family. A file the catalog doesn't list counts as
    /// not under `/static/`. A style's instance is used only when the trusted
    /// catalog lists it (option B).
    static func make(family: GoogleFontFamily, catalog: GoogleFontCatalog?, downloadedFileIDs: Set<String>) -> StyleGrid {
        var files: [String: StyleGridFile] = [:]
        for style in family.styles {
            if let file = catalog?.file(id: style.fileID) { files[file.id] = StyleGridFile(id: file.id, path: file.repositoryPath, bytes: file.bytes) }
        }
        let styles = family.styles.map { style -> StyleGridStyle in
            let instance = style.instance.flatMap { instance -> StyleGridInstance? in
                guard catalog?.instance(id: instance.id) == instance else { return nil }
                return StyleGridInstance(id: instance.id, postScriptName: instance.postScriptName, bytes: instance.bytes, sha256: instance.sha256)
            }
            return StyleGridStyle(id: style.id, name: style.name, fileID: style.fileID, postScriptName: style.postScriptName,
                                  variationInstance: style.variationInstance, instance: instance)
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

/// Where a cell's sample is drawn from: its own downloaded file first
/// (smaller, design §8), else the downloaded shared file.
struct StyleSampleSource: Hashable, Sendable {
    /// Coordinator id of the file.
    let id: String
    let sha256: String
    let expectedPostScriptNames: [String]
    /// Instance coordinates inside that file; nil for a single-style file.
    let axes: [String: Double]?
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

    func sample(_ source: StyleSampleSource, text: String?, size: CGFloat) -> StyleSample? {
        samples[Self.key(fileID: source.id, axes: source.axes, text: text, size: size)]
    }

    /// `sources` all name the same file.
    func load(_ sources: [StyleSampleSource], text: String?, size: CGFloat, scale: CGFloat) async {
        let wanted = Array(Set(sources.filter {
            let key = Self.key(fileID: $0.id, axes: $0.axes, text: text, size: size)
            return samples[key] == nil && !loading.contains(key)
        }))
        guard let first = wanted.first, wanted.allSatisfy({ $0.id == first.id && $0.sha256 == first.sha256 }) else { return }
        let keys = wanted.map { Self.key(fileID: $0.id, axes: $0.axes, text: text, size: size) }
        loading.formUnion(keys)
        let drawn = await Task.detached(priority: .userInitiated) {
            SendableSamples(value: Self.render(wanted, text: text, size: size, scale: scale))
        }.value.value
        loading.subtract(keys)
        samples.merge(drawn) { _, new in new }
    }

    private struct SendableSamples: @unchecked Sendable { let value: [Key: StyleSample] }

    nonisolated private static func render(_ sources: [StyleSampleSource], text: String?, size: CGFloat,
                                           scale: CGFloat) -> [Key: StyleSample] {
        var result: [Key: StyleSample] = [:]
        let keys = sources.map { key(fileID: $0.id, axes: $0.axes, text: text, size: size) }
        guard let source = sources.first else { return result }
        let state = try? CustomFontStore.shared.readLibraryState()
        let provider = PublicFontInventory()
        // Any face record of this exact file (by content hash) gives its stored path.
        let face = state?.snapshot.faces.first { face in
            if case let .file(_, sha256, index, _) = face.locator { return sha256 == source.sha256 && index == 0 }
            return false
        }
        // The CGFont, its provider and its bytes stay alive while any instance draws.
        guard let face, let url = provider.fileURL(for: face), PublicFontInventory.isSingleFaceSFNT(url),
              let bytes = try? Data(contentsOf: url), CustomFontStore.digest(bytes) == source.sha256,
              let data = CGDataProvider(data: bytes as CFData), let font = CGFont(data), let name = font.postScriptName as String?,
              source.expectedPostScriptNames.contains(name) else {
            for key in keys { result[key] = .failed }
            return result
        }
        withExtendedLifetime((bytes, data)) {
            for (item, key) in zip(sources, keys) {
                result[key] = sample(font, axes: item.axes ?? [:], text: text, size: size, scale: scale)
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

/// Per-file status icons (§5). Decorative: cells and file lines carry the
/// state for VoiceOver. Tiles never show the not-downloaded arrow; only a
/// shared file's line does.
struct StyleStatusBadge: View {
    let status: StyleFileStatus
    let size: CGFloat
    var showsArrow = true

    var body: some View {
        Group {
            switch status {
            case .notDownloaded:
                if showsArrow { Image(systemName: "arrow.down.circle").font(.system(size: size)).foregroundStyle(.tint) }
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

/// The grid row of the Styles section (1.4 §2–§5, §9).
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
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title2) private var sampleSize: CGFloat = 22
    /// The row's content width (list insets excluded), measured.
    @State private var rowWidth: CGFloat = 0
    /// Scroll mode: the content's frame in the scroll view's space.
    @State private var contentFrame: CGRect = .zero
    private enum PinnedHeader: Hashable {
        case group(Bool)
        case sharedFile(String)
    }
    @State private var titleWidths: [PinnedHeader: CGFloat] = [:]
    @State private var didScrollToSelection = false

    private static let labelWidth: CGFloat = 84
    private static let minimumColumn: CGFloat = 60
    private static let groupGap: CGFloat = 8
    private static let space = "styleGridScroll"

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { rowWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in rowWidth = width }
        })
        .task(id: loadKey) { await loadSamples() }
    }

    // MARK: Files

    private func status(fileID: String) -> StyleFileStatus {
        files[fileID].map { StyleFileStatus(file: $0, state: states[$0.id]) } ?? .unavailable(reason: "")
    }
    private func status(_ download: StyleGridDownload) -> StyleFileStatus {
        download.isInstance ? StyleFileStatus(unavailableReason: nil, bytes: download.bytes, state: states[download.id])
            : status(fileID: download.id)
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func size(fileID: String) -> String { size(files[fileID]?.bytes ?? 0) }
    private func groupName(_ italic: Bool) -> String { italic ? StyleGridCopy.italic : StyleGridCopy.normal }

    /// The container file over a group, unless one file spans both.
    private func groupFile(italic: Bool) -> String? {
        grid.bothGroupsFile(in: set) == nil ? grid.containerFile(italic: italic, in: set) : nil
    }
    private var hasFileLine: Bool {
        grid.bothGroupsFile(in: set) != nil || groupFile(italic: false) != nil || groupFile(italic: true) != nil
    }
    private func fileElement(_ fileID: String, group: String) -> String {
        StyleGridCopy.fileElement(group, count: grid.styleCount(fileID: fileID), size: size(fileID: fileID)) + ", " + status(fileID: fileID).label
    }

    /// The cell's own file's state if it has one, else nothing: badges are per own file (§5).
    private func badgeStatus(_ cell: StyleGrid.Cell) -> StyleFileStatus? {
        grid.ownFile(of: cell).map(status)
    }

    /// Downloaded if either file is; then downloading; then the own file's state, else the shared file's.
    private func cellStatus(_ cell: StyleGrid.Cell) -> StyleFileStatus {
        let all = [grid.ownFile(of: cell), grid.sharedFile(of: cell)].compactMap { $0 }.map(status)
        if all.contains(.downloaded) { return .downloaded }
        if all.contains(.downloading) { return .downloading }
        return all.first ?? status(fileID: cell.style.fileID)
    }

    /// The own downloaded file first (smaller, §8), else the downloaded shared file.
    private func sampleSource(_ cell: StyleGrid.Cell) -> StyleSampleSource? {
        if let own = grid.ownFile(of: cell), status(own) == .downloaded {
            if let instance = cell.style.instance {
                return StyleSampleSource(id: instance.id, sha256: instance.sha256, expectedPostScriptNames: [instance.postScriptName], axes: nil)
            }
            if let file = files[own.id] {
                return StyleSampleSource(id: file.id, sha256: file.sha256, expectedPostScriptNames: file.expectedPostScriptNames,
                                         axes: cell.style.variationInstance)
            }
        }
        if let shared = grid.sharedFile(of: cell), status(shared) == .downloaded, let file = files[shared.id] {
            return StyleSampleSource(id: file.id, sha256: file.sha256, expectedPostScriptNames: file.expectedPostScriptNames,
                                     axes: cell.style.variationInstance)
        }
        return nil
    }

    // MARK: Fit or scroll (§4)

    private var groupCount: Int { (set.hasNormal ? 1 : 0) + (set.hasItalic ? 1 : 0) }
    private var available: CGFloat { max(0, rowWidth - Self.labelWidth - 8) }
    private var fits: Bool {
        CGFloat(set.columns.count) * Self.minimumColumn + CGFloat(max(0, groupCount - 1)) * Self.groupGap <= available
    }
    private var columnWidth: CGFloat {
        guard fits, !set.columns.isEmpty else { return Self.minimumColumn }
        return (available - CGFloat(max(0, groupCount - 1)) * Self.groupGap) / CGFloat(set.columns.count)
    }

    private static let titleHeight: CGFloat = 22
    private static let fileLineHeight: CGFloat = 18
    private static let widthHeight: CGFloat = 32
    private var headerHeight: CGFloat {
        Self.titleHeight + (hasFileLine ? Self.fileLineHeight : 0) + (set.showsWidths ? Self.widthHeight : 0)
    }

    private var columnGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            labels
            if rowWidth == 0 || fits {
                groups(scrolling: false)
            } else {
                scrollingGroups
            }
        }
    }

    /// Weight names, pinned outside any scroll view.
    private var labels: some View {
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
        .frame(width: Self.labelWidth)
        .accessibilityHidden(true)
    }

    private var scrollingGroups: some View {
        let viewport = available + 12
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                groups(scrolling: true)
                    .background(GeometryReader { geometry in
                        let frame = geometry.frame(in: .named(Self.space))
                        Color.clear.onAppear { contentFrame = frame }
                            .onChange(of: frame) { _, frame in contentFrame = frame }
                    })
            }
            .coordinateSpace(name: Self.space)
            .scrollIndicators(.visible, axes: .horizontal)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(width: viewport)
            .mask(fadeMask(viewport: viewport))
            .padding(.trailing, -12)
            .onAppear {
                // First appearance only: bring the selected column to the center if it isn't fully visible.
                guard !didScrollToSelection else { return }
                didScrollToSelection = true
                guard let selected = set.cells.first(where: { $0.style.id == selectedStyleID }) else { return }
                if columnMaxX(selected.column) > viewport { proxy.scrollTo(columnID(selected.column), anchor: .center) }
            }
        }
    }

    /// 22 pt fades where more content lies (§4).
    private func fadeMask(viewport: CGFloat) -> some View {
        let fade = min(0.5, 22 / max(viewport, 1))
        let leading = contentFrame.minX < -0.5
        let trailing = contentFrame.width == 0 || contentFrame.maxX > viewport + 0.5
        return LinearGradient(stops: [
            .init(color: leading ? .clear : .black, location: 0),
            .init(color: .black, location: fade),
            .init(color: .black, location: 1 - fade),
            .init(color: trailing ? .clear : .black, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    private func columnID(_ column: StyleGrid.Column) -> String { "column-\(column.italic)-\(column.width)" }
    private func columnMaxX(_ column: StyleGrid.Column) -> CGFloat {
        let before = set.columns.prefix { $0 != column }.count
        let gap = column.italic && set.hasNormal ? Self.groupGap : 0
        return CGFloat(before + 1) * columnWidth + gap
    }

    @ViewBuilder private func groups(scrolling: Bool) -> some View {
        if let shared = grid.bothGroupsFile(in: set) {
            VStack(alignment: .leading, spacing: 0) {
                fileLine(shared, scrolling: scrolling)
                HStack(alignment: .top, spacing: Self.groupGap) {
                    group(italic: false, container: true, scrolling: scrolling, titleOnly: true)
                    group(italic: true, container: true, scrolling: scrolling, titleOnly: true)
                }
            }
            .padding(.bottom, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill)))
        } else {
            HStack(alignment: .top, spacing: Self.groupGap) {
                if set.hasNormal { group(italic: false, container: groupFile(italic: false) != nil, scrolling: scrolling, titleOnly: false) }
                if set.hasItalic { group(italic: true, container: groupFile(italic: true) != nil, scrolling: scrolling, titleOnly: false) }
            }
        }
    }

    /// One group: title (A), its file line (B) when it is a container, width names (C), then cells.
    private func group(italic: Bool, container: Bool, scrolling: Bool, titleOnly: Bool) -> some View {
        let columns = set.columns(italic: italic)
        let file = titleOnly ? nil : groupFile(italic: italic)
        return VStack(alignment: .leading, spacing: 0) {
            pinned(header: .group(italic), scrolling: scrolling, height: Self.titleHeight + (hasFileLine && !titleOnly ? Self.fileLineHeight : 0)) {
                VStack(alignment: scrolling ? .leading : .center, spacing: 0) {
                    Text(groupName(italic)).font(.footnote.weight(.semibold)).foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1).frame(height: Self.titleHeight)
                        .accessibilityHidden(file == nil)
                    if let file {
                        HStack(spacing: 4) {
                            StyleStatusBadge(status: status(fileID: file), size: badgeSize)
                            Text(size(fileID: file)).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                        .lineLimit(1).frame(height: Self.fileLineHeight)
                    } else if hasFileLine && !titleOnly {
                        Color.clear.frame(height: Self.fileLineHeight)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(file.map { fileElement($0, group: groupName(italic)) } ?? "")
                .accessibilityHidden(file == nil)
                .accessibilitySortPriority(italic ? 1999 : 2000)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(columns, id: \.self) { column in
                    VStack(spacing: 6) {
                        if set.showsWidths {
                            Text(StyleGrid.columnTitle(column.width))
                                .font(.caption2.weight(.semibold)).foregroundStyle(Color(uiColor: .label))
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .frame(height: Self.widthHeight)
                                .accessibilityHidden(true)
                        }
                        ForEach(Array(set.rows.enumerated()), id: \.element.id) { index, row in
                            slot(row, column: column, index: index, inContainer: container).frame(height: cellHeight)
                        }
                    }
                    .frame(width: columnWidth)
                    .id(columnID(column))
                }
            }
            .padding(.top, set.showsWidths ? 0 : 6)
        }
        .padding(.bottom, container && !titleOnly ? 6 : 0)
        .background {
            if container && !titleOnly {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
            }
        }
    }

    /// Fit mode: centered. Scroll mode: leading with a 10 pt inset and pinned to
    /// the visible leading edge while any of the group is visible (§4).
    @ViewBuilder private func pinned<Content: View>(header: PinnedHeader, scrolling: Bool, height: CGFloat,
                                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        if scrolling {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(Self.space))
                let title = titleWidths[header] ?? 0
                let offset = StyleGrid.pinnedHeaderOffset(minX: frame.minX, width: frame.width, contentWidth: title)
                content()
                    .fixedSize()
                    .background(GeometryReader { inner in
                        Color.clear
                            .onAppear { titleWidths[header] = inner.size.width }
                            .onChange(of: inner.size.width) { _, width in titleWidths[header] = width }
                    })
                    .padding(.leading, 10)
                    .offset(x: layoutDirection == .rightToLeft ? -offset : offset)
            }
            .frame(height: height)
        } else {
            content().frame(maxWidth: .infinity)
        }
    }

    /// The 1.3 strip over a container spanning both groups.
    private func fileLine(_ fileID: String, scrolling: Bool) -> some View {
        // This reader spans the whole two-group container, not either group.
        // Use the same measured/clamped pinning as its headings (§4–5).
        pinned(header: .sharedFile(fileID), scrolling: scrolling, height: Self.fileLineHeight) {
            HStack(spacing: 4) {
                StyleStatusBadge(status: status(fileID: fileID), size: badgeSize)
                Text(StyleGridCopy.fileLine(grid.styleCount(fileID: fileID), size: size(fileID: fileID)))
                    .font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(height: Self.fileLineHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StyleGridCopy.fileElement("Shared", count: grid.styleCount(fileID: fileID), size: size(fileID: fileID))
                                + ", " + status(fileID: fileID).label)
            .accessibilitySortPriority(2000)
            .accessibilityIdentifier("fontDetail.sharedFileStrip")
        }
    }

    // MARK: Accessibility sizes (§9)

    private var stackedGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stackedFiles, id: \.id) { item in
                HStack(spacing: 6) {
                    StyleStatusBadge(status: status(fileID: item.id), size: badgeSize)
                    Text(StyleGridCopy.groupFileLine(item.group, count: grid.styleCount(fileID: item.id), size: size(fileID: item.id)))
                        .font(.body).foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fileElement(item.id, group: item.group))
                .accessibilitySortPriority(2000)
            }
            ForEach(Array(set.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.name).font(.title3).foregroundStyle(Color(uiColor: .label))
                        Text(verbatim: String(row.weight)).font(.body).foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    let present = set.columns.filter { row.cell(in: $0) != nil }
                    ForEach(Array(stride(from: 0, to: present.count, by: 2)), id: \.self) { start in
                        HStack(spacing: 8) {
                            ForEach(present[start..<min(start + 2, present.count)], id: \.self) { column in
                                slot(row, column: column, index: index, inContainer: false, stackedName: stackedName(column))
                                    .frame(height: cellHeight)
                            }
                            if present.count - start == 1 { Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true) }
                        }
                    }
                }
            }
        }
    }

    /// One AX file line per shared container file.
    private var stackedFiles: [(id: String, group: String)] {
        if let shared = grid.bothGroupsFile(in: set) { return [(shared, "Shared")] }
        return [false, true].compactMap { italic in groupFile(italic: italic).map { ($0, groupName(italic)) } }
    }

    /// The column name inside an AX tile: "Standard", "Condensed Italic"; "Normal"/"Italic" for one width.
    private func stackedName(_ column: StyleGrid.Column) -> String {
        guard set.showsWidths else { return groupName(column.italic) }
        return StyleGrid.columnName(column.width) + (column.italic ? " " + StyleGridCopy.italic : "")
    }

    // MARK: Cells (§5)

    /// A missing combination is an empty slot: no tile, text or VoiceOver element.
    @ViewBuilder private func slot(_ row: StyleGrid.Row, column: StyleGrid.Column, index: Int, inContainer: Bool,
                                   stackedName: String? = nil) -> some View {
        if let cell = row.cell(in: column) {
            let position = set.columns.firstIndex(of: column) ?? 0
            cellButton(cell, inContainer: inContainer, stackedName: stackedName)
                .accessibilitySortPriority(Double(1000 - index * 32 - position))
        } else {
            Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
        }
    }

    private func cellButton(_ cell: StyleGrid.Cell, inContainer: Bool, stackedName: String?) -> some View {
        let selected = cell.style.id == selectedStyleID
        let state = cellStatus(cell)
        let badge = badgeStatus(cell)
        let fill: Color = selected ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14)
            : inContainer ? .clear : Color(uiColor: .tertiarySystemFill)
        let detail: String
        if let own = grid.ownFile(of: cell) { detail = StyleGridCopy.separateFile(size(own.bytes)) }
        else { detail = StyleGridCopy.fileContains(grid.styleCount(fileID: cell.style.fileID)) }
        return Button { select(cell) } label: {
            ZStack(alignment: .topLeading) {
                content(cell, status: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let stackedName {
                    Text(stackedName).font(.subheadline.weight(.semibold)).foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 8).padding(.top, 6)
                        .accessibilityHidden(true)
                }
            }
            .background(tile.fill(fill))
            .overlay { if selected { tile.strokeBorder(Color.accentColor, lineWidth: 2) } }
            .overlay(alignment: .topTrailing) {
                if let badge { StyleStatusBadge(status: badge, size: badgeSize, showsArrow: false).padding(4) }
            }
            .contentShape(tile)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, inContainer ? 2 : 3)
        .frame(minWidth: 48, minHeight: 48)
        .disabled(disabled)
        .accessibilityLabel(grid.displayName(of: cell, in: set))
        .accessibilityValue(state.label + ", " + detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("fontDetail.style.\(cell.style.id)")
    }

    @ViewBuilder private func content(_ cell: StyleGrid.Cell, status: StyleFileStatus) -> some View {
        if let source = sampleSource(cell), let sample = samples.sample(source, text: sampleText, size: sampleSize) {
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

    private var sources: [StyleSampleSource] { self.set.cells.compactMap(sampleSource) }
    private var loadKey: String {
        sources.map { $0.id + PublicFontInventory.axisKey($0.axes ?? [:]) }.sorted().joined(separator: "|")
            + "#\(sampleText ?? "")#\(sampleSize)#\(displayScale)"
    }
    private func loadSamples() async {
        let byFile = Dictionary(grouping: sources, by: \.id)
        for id in byFile.keys.sorted() {
            guard !Task.isCancelled else { return }
            await samples.load(byFile[id]!, text: sampleText, size: sampleSize, scale: displayScale)
        }
    }
}
