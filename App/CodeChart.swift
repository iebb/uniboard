import SwiftUI
import UIKit

/// Which code points Explore shows: one plane, or all of them. The two
/// Supplementary Private Use planes hold no published characters, so they
/// are hidden unless Settings shows them; with ConScript on, plane 15 shows
/// for the registry's blocks there.
struct ExploreScope: Equatable {
    /// A plane number from 0 to 16, or nil for every plane.
    var plane: Int?
    var showsPrivateUse: Bool
    var showsConScript = false

    static let privateUsePlanes: Set<Int> = [15, 16]
    /// The Private Use planes left out.
    var hiddenPlanes: Set<Int> { showsPrivateUse ? [] : showsConScript ? [16] : Self.privateUsePlanes }
    /// Private Use left out as rows of placeholders unless Settings shows
    /// it; with ConScript on, only the registry's blocks stay.
    var hiddenRanges: [ClosedRange<UInt32>] {
        guard !showsPrivateUse else { return [] }
        guard showsConScript else { return [0xE000...0xF8FF] }
        var hidden: [ClosedRange<UInt32>] = []
        for area: ClosedRange<UInt32> in [0xE000...0xF8FF, 0xF0000...0xFFFFD] {
            var next = area.lowerBound
            for block in UCSUR.registry.blocks where block.start >= area.lowerBound && block.end <= area.upperBound {
                if block.start > next { hidden.append(next...(block.start - 1)) }
                next = block.end + 1
            }
            if next <= area.upperBound { hidden.append(next...area.upperBound) }
        }
        return hidden
    }
    func hides(_ points: ClosedRange<UInt32>) -> Bool {
        hiddenRanges.contains { $0.lowerBound <= points.lowerBound && $0.upperBound >= points.upperBound }
    }

    static func name(of plane: Int) -> String {
        switch plane {
        case 0: return "Basic Multilingual Plane"
        case 1: return "Supplementary Multilingual Plane"
        case 2: return "Supplementary Ideographic Plane"
        case 3: return "Tertiary Ideographic Plane"
        case 14: return "Supplementary Special-purpose Plane"
        case 15: return "Supplementary Private Use Area-A"
        case 16: return "Supplementary Private Use Area-B"
        default: return "Plane \(plane)"
        }
    }

    /// Planes with at least one block, offered in the plane menu.
    func planes(in catalog: UnicodeCatalog) -> [Int] {
        Array(Set(catalog.blocks.map { Int($0.start >> 16) })).filter { !hiddenPlanes.contains($0) }.sorted()
    }

    /// The code points in view, as one contiguous range.
    var range: ClosedRange<UInt32> {
        if let plane { return UInt32(plane) << 16...(UInt32(plane) << 16 | 0xFFFF) }
        return 0...(hiddenPlanes.contains(15) ? 0xEFFFF : hiddenPlanes.contains(16) ? 0xFFFFF : 0x10FFFF)
    }

    func includes(_ block: UnicodeBlock) -> Bool {
        range.contains(block.start) && !hides(block.start...block.end)
    }
}

/// The blocks of a chart, each as rows of `columns` code points. Built from
/// assigned spans; characters are created only as rows are shown.
struct CodeChartBlock: Identifiable {
    let block: UnicodeBlock
    let rows: [UnicodeChartRow]
    var id: UInt32 { block.start }

    /// With `addedOnly`, the chart holds only what this edition adds. When
    /// `descending`, blocks and their rows run from the highest code point.
    static func blocks(in catalog: UnicodeCatalog, columns: Int, addedOnly: Bool = false,
                       scope: ExploreScope = ExploreScope(plane: nil, showsPrivateUse: true),
                       descending: Bool = false, only: UInt32? = nil) -> [CodeChartBlock] {
        let blocks = catalog.blocks.filter { scope.includes($0) && (only == nil || $0.start == only) }.compactMap { block -> CodeChartBlock? in
            let rows = catalog.chartRows(in: block, columns: columns, addedOnly: addedOnly)
                .filter { !scope.hides($0.start...($0.start + UInt32(columns) - 1)) }
            return rows.isEmpty ? nil : CodeChartBlock(block: block, rows: descending ? rows.reversed() : rows)
        }
        return descending ? blocks.reversed() : blocks
    }
}

/// Lets SwiftUI jump a chart to a block and read which block is on top,
/// without re-rendering the chart while it scrolls.
@MainActor
final class CodeChartController {
    fileprivate weak var coordinator: CodeChartView.Coordinator?
    /// The block whose header is pinned at the top of the chart.
    fileprivate(set) var topBlock: UInt32?
    func jump(to block: UInt32) { coordinator?.jump(to: block) }
}

/// A code chart of every block, with each block's name and column digits
/// pinned while its rows scroll beneath them. A collection view lays out
/// tens of thousands of rows exactly, so jumps land on the chosen block and
/// the chart scrolls freely in both directions.
struct CodeChartView: UIViewRepresentable {
    let catalog: UnicodeCatalog
    let density: GridDensity
    var addedOnly = false
    var scope = ExploreScope(plane: nil, showsPrivateUse: true)
    let controller: CodeChartController
    /// Content shown above the chart, scrolling with it.
    var leading: AnyView? = nil
    /// Opens a block from its header; nil for a static header.
    var navigate: ((UnicodeBlock) -> Void)? = nil
    /// Runs from the highest code point down.
    var descending = false
    /// The start of the one block to chart, or nil for every block in scope.
    var only: UInt32? = nil
    let select: (UnicodeCharacter) -> Void
    @EnvironmentObject private var store: CharacterStore
    @EnvironmentObject private var preferences: CatalogPreferences

    static let headerHeight: CGFloat = 58
    /// Horizontal inset that keeps the chart within its density's widest width.
    static func inset(for width: CGFloat, density: GridDensity) -> CGFloat {
        max(0, (width - density.maximumWidth) / 2) + 16
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        coordinator.parent = self
        let layout = UICollectionViewCompositionalLayout { [weak coordinator] index, environment in
            coordinator?.section(at: index, environment: environment)
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemGroupedBackground
        view.allowsSelection = false
        view.keyboardDismissMode = .interactive
        view.delegate = coordinator
        view.accessibilityIdentifier = "codeChart"
        coordinator.attach(to: view)
        controller.coordinator = coordinator
        coordinator.reload(keepingTopBlock: false)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.parent
        coordinator.parent = self
        controller.coordinator = coordinator
        if previous.map({ $0.catalog !== catalog || $0.density != density || $0.addedOnly != addedOnly || $0.scope != scope
                || $0.descending != descending || $0.only != only }) ?? true {
            // A new density keeps the block being read; a new edition or plane starts over.
            coordinator.reload(keepingTopBlock: previous?.catalog === catalog && previous?.scope == scope)
        } else {
            coordinator.refreshLeading()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        enum Section: Hashable { case leading, block(UInt32) }
        enum Item: Hashable { case leading, row(UInt32) }

        var parent: CodeChartView?
        private(set) var blocks: [CodeChartBlock] = []
        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
        private var hasLeading: Bool { parent?.leading != nil }
        private var leadingOffset: Int { hasLeading ? 1 : 0 }

        func attach(to view: UICollectionView) {
            collectionView = view
            let rows = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, indexPath, _ in
                guard let self, let parent = self.parent, let block = self.block(atSection: indexPath.section),
                      block.rows.indices.contains(indexPath.item) else { return }
                let side = parent.density.cellSide(in: self.contentWidth)
                cell.contentConfiguration = UIHostingConfiguration {
                    CodeChartRow(row: block.rows[indexPath.item], catalog: parent.catalog, density: parent.density,
                                 side: side, select: parent.select)
                        .environmentObject(parent.store)
                        .environmentObject(parent.preferences)
                }
                .margins(.all, 0)
            }
            let leading = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, _ in
                guard let parent = self?.parent, let content = parent.leading else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    content.environmentObject(parent.store).environmentObject(parent.preferences)
                }
                .margins(.all, 0)
            }
            let headers = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
                elementKind: UICollectionView.elementKindSectionHeader) { [weak self] header, _, indexPath in
                guard let self, let parent = self.parent, let block = self.block(atSection: indexPath.section) else { return }
                let side = parent.density.cellSide(in: self.contentWidth)
                let inset = CodeChartView.inset(for: self.collectionView?.bounds.width ?? 0, density: parent.density)
                header.contentConfiguration = UIHostingConfiguration {
                    CodeChartHeader(block: block.block, density: parent.density, side: side, navigate: parent.navigate,
                                    catalog: parent.catalog, showsUCSUR: parent.preferences.showsUCSUR)
                        .padding(.horizontal, inset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .background(Color.groupedBackground)
                }
                .margins(.all, 0)
            }
            let source = UICollectionViewDiffableDataSource<Section, Item>(collectionView: view) { view, indexPath, item in
                switch item {
                case .leading: return view.dequeueConfiguredReusableCell(using: leading, for: indexPath, item: item)
                case .row: return view.dequeueConfiguredReusableCell(using: rows, for: indexPath, item: item)
                }
            }
            source.supplementaryViewProvider = { view, _, indexPath in
                view.dequeueConfiguredReusableSupplementary(using: headers, for: indexPath)
            }
            dataSource = source
        }

        private var contentWidth: CGFloat {
            let width = collectionView?.bounds.width ?? 0
            return width - 2 * CodeChartView.inset(for: width, density: parent?.density ?? .sixteen)
        }

        private func block(atSection section: Int) -> CodeChartBlock? {
            let index = section - leadingOffset
            return blocks.indices.contains(index) ? blocks[index] : nil
        }

        func section(at index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
            guard let parent else { return nil }
            let width = environment.container.effectiveContentSize.width
            let inset = CodeChartView.inset(for: width, density: parent.density)
            if hasLeading && index == 0 {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(240))
                let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: inset, bottom: 4, trailing: inset)
                return section
            }
            let side = parent.density.cellSide(in: width - 2 * inset)
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side))
            let section = NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [.init(layoutSize: size)]))
            section.interGroupSpacing = parent.density.spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: inset, bottom: 20, trailing: inset)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(CodeChartView.headerHeight)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            header.pinToVisibleBounds = true
            header.zIndex = 2
            section.supplementariesFollowContentInsets = false
            section.boundarySupplementaryItems = [header]
            return section
        }

        func reload(keepingTopBlock: Bool) {
            guard let parent, let dataSource else { return }
            let kept = keepingTopBlock ? parent.controller.topBlock : nil
            blocks = CodeChartBlock.blocks(in: parent.catalog, columns: parent.density.rawValue,
                                           addedOnly: parent.addedOnly, scope: parent.scope, descending: parent.descending,
                                           only: parent.only)
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            if hasLeading {
                snapshot.appendSections([.leading])
                snapshot.appendItems([.leading], toSection: .leading)
            }
            for block in blocks {
                snapshot.appendSections([.block(block.id)])
                snapshot.appendItems(block.rows.map { .row($0.start) }, toSection: .block(block.id))
            }
            dataSource.applySnapshotUsingReloadData(snapshot)
            collectionView?.collectionViewLayout.invalidateLayout()
            if let kept { jump(to: kept) } else {
                parent.controller.topBlock = blocks.first?.id
                collectionView?.setContentOffset(CGPoint(x: 0, y: -(collectionView?.adjustedContentInset.top ?? 0)), animated: false)
            }
        }

        func refreshLeading() {
            guard hasLeading, let dataSource else { return }
            var snapshot = dataSource.snapshot()
            guard snapshot.indexOfItem(.leading) != nil else { return }
            snapshot.reconfigureItems([.leading])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        /// Puts the header of `start`'s block, or the next block with
        /// characters, at the top of the chart.
        func jump(to start: UInt32) {
            guard let view = collectionView, !blocks.isEmpty else { return }
            let descending = parent?.descending == true
            let index = blocks.firstIndex { descending ? $0.block.start <= start : $0.block.start >= start } ?? blocks.count - 1
            let first = IndexPath(item: 0, section: index + leadingOffset)
            view.layoutIfNeeded()
            view.scrollToItem(at: first, at: .top, animated: false)
            view.layoutIfNeeded()
            // Rows above the target were estimated until now; with them laid
            // out, place the block's first row just below its pinned header.
            if let row = view.layoutAttributesForItem(at: first) {
                let top = view.adjustedContentInset.top
                let y = max(-top, row.frame.minY - top - CodeChartView.headerHeight - 2)
                view.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
            parent?.controller.topBlock = blocks[index].id
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let view = scrollView as? UICollectionView else { return }
            // The first row below the pinned header belongs to the block on top.
            let probe = CGPoint(x: view.bounds.midX,
                                y: view.contentOffset.y + view.adjustedContentInset.top + CodeChartView.headerHeight + 4)
            let indexPath = view.indexPathForItem(at: probe) ?? view.indexPathsForVisibleItems.filter { $0.section >= leadingOffset }.min()
            if let indexPath, let block = block(atSection: indexPath.section) { parent?.controller.topBlock = block.id }
        }
    }
}

/// The pinned header of a block: its name (opens the block navigator) and
/// the hex digit of each column.
struct CodeChartHeader: View {
    let block: UnicodeBlock
    let density: GridDensity
    let side: CGFloat
    let navigate: ((UnicodeBlock) -> Void)?
    let catalog: UnicodeCatalog
    let showsUCSUR: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let navigate {
                Button { navigate(block) } label: { title(chevron: true) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(block.name), \(block.rangeLabel)")
                    .accessibilityHint("Open this block")
                    .accessibilityIdentifier("chartBlockNavigator")
                    .blockInfo(block, catalog: catalog, showsUCSUR: showsUCSUR)
            } else {
                title(chevron: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .blockInfo(block, catalog: catalog, showsUCSUR: showsUCSUR)
            }
            HStack(spacing: density.spacing) {
                Color.clear.frame(width: density.rowLabelWidth, height: 1)
                ForEach(0..<density.rawValue, id: \.self) { column in
                    Text(density.columnLabel(column))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: side)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
    }

    private func title(chevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(block.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            Spacer(minLength: 8)
            Text(block.rangeLabel).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

struct CodeChartRow: View {
    let row: UnicodeChartRow
    let catalog: UnicodeCatalog
    let density: GridDensity
    let side: CGFloat
    @EnvironmentObject private var store: CharacterStore
    let select: (UnicodeCharacter) -> Void

    var body: some View {
        HStack(spacing: density.spacing) {
            Text(density.rowLabel(row.start))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: density.rowLabelWidth, alignment: .leading)
                .accessibilityHidden(true)
            ForEach(0..<density.rawValue, id: \.self) { column in
                if row.isAssigned(column: column), let cell = catalog.character(at: row.start + UInt32(column)) {
                    CharacterTile(character: cell, saved: store.isFavorite(cell.codePoint), density: density,
                                  showsCodePoint: false, side: side) { select(cell) }
                } else {
                    // An unassigned code point keeps the chart aligned.
                    RoundedRectangle(cornerRadius: density.isDense ? 4 : 8, style: .continuous)
                        .fill(Color(uiColor: .quaternarySystemFill))
                        .frame(width: side, height: side)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Jump straight to any block of the selected edition.
struct BlockNavigator: View {
    let blocks: [UnicodeBlock]
    let current: UInt32?
    let choose: (UnicodeBlock) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [UnicodeBlock] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if tokens.isEmpty { return blocks }
        return blocks.filter { block in
            tokens.allSatisfy { block.name.lowercased().contains($0) || block.rangeLabel.lowercased().contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(filtered) { block in
                    Button {
                        choose(block)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.name).foregroundStyle(Color.primary)
                                Text(block.rangeLabel).font(.footnote.monospaced()).foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if block.start == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .id(block.start)
                }
                .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Block name or range")
            .navigationTitle("Jump to Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
