#if canImport(UIKit)
import UIKit
import SwiftUI
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardSymbolPagesPagerTests: XCTestCase {
    private let pages = [KeyboardSymbolPage(id: .board("a"), title: "Alpha"),
                         KeyboardSymbolPage(id: .board("b"), title: "Beta"),
                         KeyboardSymbolPage(id: .recent, title: "Recent")]
    private func fixture(selection: SymbolPageID = .board("a"),
                         factory: @escaping () -> ((SymbolPageID) -> Bool)?) -> KeyboardSymbolPagesController {
        let controller = KeyboardSymbolPagesController()
        controller.configure(pages: pages, selection: selection, route: UUID(), isActive: true,
                             content: { AnyView(Text(String(describing: $0))) }, actionFactory: factory)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 240)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        return controller
    }
    func testNativePagingCancelsControlTouchesCommitsOnceAndAnnouncesPageName() throws {
        XCTAssertEqual(KeyboardSymbolPagePolicy.maximumPages, SymbolBoardStore.maximumBoards + 1,
                       "Every allowed saved page plus Recent must fit in the pager")
        var selected: [SymbolPageID] = []
        let controller = fixture { { selected.append($0); return true } }
        let scroll = controller.scrollView
        XCTAssertTrue(scroll.isPagingEnabled)
        XCTAssertGreaterThan(scroll.backgroundColor?.cgColor.alpha ?? 0, 0, "Blank page space must remain in the remote keyboard's drawable hit map")
        XCTAssertTrue(scroll.touchesShouldCancel(in: UIControl()))
        XCTAssertEqual(scroll.contentSize, CGSize(width: 1200, height: 240))
        controller.scrollViewWillBeginDragging(scroll)
        var target = CGPoint(x: 800, y: 99)
        controller.scrollViewWillEndDragging(scroll, withVelocity: CGPoint(x: 1000, y: 0), targetContentOffset: &target)
        XCTAssertEqual(target, CGPoint(x: 400, y: 0), "One gesture advances one page")
        scroll.setContentOffset(target, animated: false)
        controller.scrollViewDidEndDragging(scroll, willDecelerate: true)
        XCTAssertTrue(selected.isEmpty)
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(selected, [.board("b")])
        XCTAssertEqual(scroll.accessibilityValue, "Beta")
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(selected.count, 1)
        XCTAssertLessThanOrEqual(controller.children.count, 3)
        controller.stop()
        XCTAssertTrue(controller.children.isEmpty)
        XCTAssertNil(scroll.delegate)
        XCTAssertNil(scroll.accessibilityPage)
    }
    func testRejectedOrExpiredContextCannotAdoptAnotherPageAndRotationCancels() {
        var current = true, calls = 0
        let controller = fixture { { _ in calls += 1; return current } }
        let scroll = controller.scrollView
        controller.scrollViewWillBeginDragging(scroll)
        current = false
        scroll.setContentOffset(CGPoint(x: 400, y: 0), animated: false)
        controller.scrollViewDidEndDragging(scroll, willDecelerate: false)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(scroll.contentOffset.x, 0)
        XCTAssertEqual(scroll.accessibilityValue, "Alpha")
        current = true
        controller.scrollViewWillBeginDragging(scroll)
        controller.view.frame.size = CGSize(width: 700, height: 240)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(scroll.contentOffset.x, 0)
    }
    func testAccessiblePagingRespectsBoundariesAndReentrantModelReplacement() {
        let controller = KeyboardSymbolPagesController()
        let configure: (SymbolPageID, @escaping () -> ((SymbolPageID) -> Bool)?) -> Void = { selection, factory in
            controller.configure(pages: self.pages, selection: selection, route: UUID(), isActive: true,
                                 content: { AnyView(Text(String(describing: $0))) }, actionFactory: factory)
        }
        configure(.board("a"), { { _ in true } })
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 240)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertFalse(controller.scrollView.accessibilityScroll(.right))
        XCTAssertTrue(controller.scrollView.accessibilityScroll(.left))
        XCTAssertEqual(controller.scrollView.accessibilityValue, "Beta")
        XCTAssertTrue(controller.scrollView.accessibilityScroll(.previous))
        XCTAssertEqual(controller.scrollView.accessibilityValue, "Alpha")
        XCTAssertTrue(controller.scrollView.accessibilityScroll(.next))
        XCTAssertEqual(controller.scrollView.accessibilityValue, "Beta")
        XCTAssertFalse(controller.scrollView.accessibilityScroll(.up))
        XCTAssertFalse(controller.scrollView.accessibilityScroll(.down))
        configure(.board("a"), { { _ in
            configure(.recent, { { _ in false } })
            return true
        } })
        XCTAssertTrue(controller.scrollView.accessibilityScroll(.left))
        XCTAssertEqual(controller.scrollView.accessibilityValue, "Recent", "A completed callback cannot overwrite its replacement model")
        XCTAssertFalse(controller.scrollView.accessibilityScroll(.left))
    }
    func testDeletedPageMissingFactoryAndInactiveConfigurationNeverCommit() {
        var calls = 0
        let controller = fixture { { _ in calls += 1; return true } }
        controller.scrollViewWillBeginDragging(controller.scrollView)
        controller.configure(pages: [pages[0], pages[2]], selection: .board("a"), route: UUID(), isActive: false,
                             content: { _ in AnyView(EmptyView()) }, actionFactory: { nil })
        controller.scrollViewDidEndDecelerating(controller.scrollView)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(controller.scrollView.isScrollEnabled)
        XCTAssertFalse(controller.scrollView.accessibilityScroll(.left))
        controller.configure(pages: pages, selection: .board("a"), route: UUID(), isActive: true,
                             content: { _ in AnyView(EmptyView()) }, actionFactory: { nil })
        controller.scrollViewWillBeginDragging(controller.scrollView)
        controller.scrollView.setContentOffset(CGPoint(x: 400, y: 0), animated: false)
        controller.scrollViewDidEndDragging(controller.scrollView, willDecelerate: false)
        XCTAssertEqual(controller.scrollView.accessibilityValue, "Alpha")
        XCTAssertEqual(calls, 0)
    }
}
#endif
