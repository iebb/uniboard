import SwiftUI
import UIKit

enum SymbolPageID: Hashable { case board(String), recent }

struct KeyboardSymbolPage: Identifiable, Equatable {
    let id: SymbolPageID
    let title: String
}

/// Native paging owns its position. Saving a page preference happens only
/// after a completed gesture, outside SwiftUI's layout/target discovery.
struct KeyboardSymbolPagesPager: UIViewControllerRepresentable {
    let pages: [KeyboardSymbolPage]
    let selection: SymbolPageID
    let route: UUID
    let isActive: Bool
    let content: (SymbolPageID) -> AnyView
    let actionFactory: () -> ((SymbolPageID) -> Bool)?

    func makeUIViewController(context: Context) -> KeyboardSymbolPagesController { KeyboardSymbolPagesController() }
    func updateUIViewController(_ controller: KeyboardSymbolPagesController, context: Context) {
        controller.configure(pages: pages, selection: selection, route: route, isActive: isActive,
                             content: content, actionFactory: actionFactory)
    }
    static func dismantleUIViewController(_ controller: KeyboardSymbolPagesController, coordinator: ()) { controller.stop() }
}

final class KeyboardSymbolPagesScrollView: UIScrollView {
    var accessibilityPage: ((UIAccessibilityScrollDirection) -> Bool)?
    // Symbol keys are UIControls. UIKit's default can otherwise keep their
    // touches instead of letting an ancestor scroll view begin a page swipe.
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        // VoiceOver's semantic next/previous actions must use the same
        // guarded selection path as physical left/right paging.
        switch direction {
        case .left, .next: return accessibilityPage?(.left) ?? false
        case .right, .previous: return accessibilityPage?(.right) ?? false
        default: return false
        }
    }
}

@MainActor
final class KeyboardSymbolPagesController: UIViewController, UIScrollViewDelegate {
    let scrollView = KeyboardSymbolPagesScrollView()
    private var pages: [KeyboardSymbolPage] = []
    private var selection: SymbolPageID?
    private var route: UUID?
    private var active = false
    private var content: ((SymbolPageID) -> AnyView)?
    private var factory: (() -> ((SymbolPageID) -> Bool)?)?
    private var hosts: [SymbolPageID: UIHostingController<AnyView>] = [:]
    private var size = CGSize.zero
    private var startIndex: Int?
    private var commit: ((SymbolPageID) -> Bool)?
    private var arranging = false
    private var generation = UUID()

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        // Like the native key controls, keep a drawable surface in the
        // remote keyboard's hit map, including empty pages and key gaps.
        scrollView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.02)
        scrollView.isPagingEnabled = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.canCancelContentTouches = true
        scrollView.delaysContentTouches = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.accessibilityIdentifier = "keyboard.pages.pager"
        scrollView.accessibilityLabel = "Symbol pages"
        scrollView.delegate = self
        scrollView.accessibilityPage = { [weak self] direction in self?.accessibilityPage(direction) ?? false }
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
            scrollView.leftEdgeEffect.isHidden = true
            scrollView.rightEdgeEffect.isHidden = true
        }
        view.addSubview(scrollView)
    }

    func configure(pages: [KeyboardSymbolPage], selection: SymbolPageID, route: UUID, isActive: Bool,
                   content: @escaping (SymbolPageID) -> AnyView,
                   actionFactory: @escaping () -> ((SymbolPageID) -> Bool)?) {
        guard (1...KeyboardSymbolPagePolicy.maximumPages).contains(pages.count),
              Set(pages.map(\.id)).count == pages.count, pages.contains(where: { $0.id == selection }) else {
            cancelGesture(); active = false; scrollView.isScrollEnabled = false
            for host in hosts.values { host.view.isUserInteractionEnabled = false; host.view.accessibilityElementsHidden = true }
            return
        }
        loadViewIfNeeded()
        let changed = self.pages != pages || self.selection != selection || self.route != route || active != isActive
        if changed { cancelGesture(); generation = UUID() }
        self.pages = pages; self.selection = selection; self.route = route
        active = isActive; self.content = content; factory = actionFactory
        scrollView.isScrollEnabled = isActive && pages.count > 1
        for (id, host) in Array(hosts) { host.rootView = content(id) }
        arrange(align: changed || startIndex == nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let changed = size != view.bounds.size
        if changed { cancelGesture() }
        arrange(align: changed || startIndex == nil)
    }

    private var selectedIndex: Int { pages.firstIndex { $0.id == selection } ?? 0 }
    private func arrange(align: Bool) {
        let bounds = view.bounds
        guard !arranging, !pages.isEmpty, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0, (bounds.width * CGFloat(pages.count)).isFinite else { return }
        arranging = true
        defer { arranging = false }
        size = bounds.size
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: bounds.width * CGFloat(pages.count), height: bounds.height)
        if align { scrollView.setContentOffset(CGPoint(x: CGFloat(selectedIndex) * bounds.width, y: 0), animated: false) }
        render(near: KeyboardSymbolPagePolicy.index(offset: scrollView.contentOffset.x, width: size.width, count: pages.count) ?? selectedIndex)
        scrollView.accessibilityValue = pages[selectedIndex].title
    }

    private func render(near index: Int) {
        guard let content else { return }
        let indices = max(0, index - 1)...min(pages.count - 1, index + 1)
        let needed = Set(indices.map { pages[$0].id })
        for id in Array(hosts.keys) where !needed.contains(id) {
            guard let host = hosts.removeValue(forKey: id) else { continue }
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
        for index in indices {
            let page = pages[index]
            let host: UIHostingController<AnyView>
            if let existing = hosts[page.id] { host = existing }
            else {
                host = UIHostingController(rootView: content(page.id))
                host.safeAreaRegions = []
                host.view.backgroundColor = .clear
                addChild(host); scrollView.addSubview(host.view); host.didMove(toParent: self)
                hosts[page.id] = host
            }
            host.view.frame = CGRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height)
            host.view.accessibilityElementsHidden = !active || page.id != selection
            host.view.isUserInteractionEnabled = active && page.id == selection
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelGesture()
        guard active else { return }
        startIndex = selectedIndex
        commit = factory?()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !arranging, !pages.isEmpty, size.width > 0,
              let index = KeyboardSymbolPagePolicy.index(offset: scrollView.contentOffset.x, width: size.width, count: pages.count) else { return }
        render(near: index)
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                  targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let startIndex, let index = KeyboardSymbolPagePolicy.index(offset: targetContentOffset.pointee.x,
                width: size.width, count: pages.count, startingAt: startIndex) else { return }
        targetContentOffset.pointee = CGPoint(x: CGFloat(index) * size.width, y: 0)
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { finish() } }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finish() }

    private func finish() {
        let action = commit, start = startIndex
        cancelGesture() // A reentrant callback or duplicate end cannot commit twice.
        guard active, let start, let index = KeyboardSymbolPagePolicy.index(offset: scrollView.contentOffset.x,
                width: size.width, count: pages.count, startingAt: start) else { arrange(align: true); return }
        let id = pages[index].id
        let captured = generation
        let accepted = id == selection || action?(id) == true
        if accepted, generation == captured, pages.contains(where: { $0.id == id }) { selection = id }
        arrange(align: true)
    }

    private func accessibilityPage(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard active, direction == .left || direction == .right else { return false }
        let index = selectedIndex + (direction == .left ? 1 : -1)
        guard pages.indices.contains(index), let action = factory?() else { return false }
        let page = pages[index], captured = generation
        guard action(page.id) else { return false }
        if generation == captured, pages.contains(where: { $0.id == page.id }) { selection = page.id }
        arrange(align: true)
        UIAccessibility.post(notification: .pageScrolled, argument: scrollView.accessibilityValue)
        return true
    }
    private func cancelGesture() { startIndex = nil; commit = nil }
    func stop() {
        cancelGesture(); active = false; factory = nil; content = nil
        scrollView.delegate = nil; scrollView.accessibilityPage = nil
        for host in hosts.values { host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent() }
        hosts.removeAll()
    }
}
