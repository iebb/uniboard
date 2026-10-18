#if canImport(UIKit)
import XCTest
@testable import Uniboard

@MainActor
final class CatalogSearchTests: XCTestCase {
    private func waitUntilSettled(_ search: CatalogSearch,
                                  file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while search.searching && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(search.searching, "The latest query should finish", file: file, line: line)
    }

    func testExactSupplementaryQueryPublishesItsOriginalScalar() async throws {
        let search = CatalogSearch()
        search.update("U+1F680", catalog: .latest, order: .codePoint)
        try await waitUntilSettled(search)
        XCTAssertEqual(search.results.map(\.codePoint), [0x1F680])
        XCTAssertEqual(search.results.map(\.text), ["🚀"])
    }

    func testRapidReplacementPublishesOnlyTheNewestQuery() async throws {
        let search = CatalogSearch()
        search.update("U+0041", catalog: .shared, order: .newestFirst)
        search.update("U+1F680", catalog: .latest, order: .oldestFirst)
        try await waitUntilSettled(search)
        XCTAssertEqual(search.results.map(\.codePoint), [0x1F680])
    }

    func testClearingAQueuedQueryDoesNotRepopulateResults() async throws {
        let search = CatalogSearch()
        search.update("letter", catalog: .latest, order: .newestFirst)
        search.update(" \n\t ", catalog: .latest, order: .newestFirst)
        XCTAssertFalse(search.searching)
        XCTAssertTrue(search.results.isEmpty)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(search.searching)
        XCTAssertTrue(search.results.isEmpty)
    }

    func testNonpositiveLimitsDoNotProduceResults() async throws {
        let search = CatalogSearch()
        for limit in [0, -1, Int.min] {
            search.update("U+1F680", catalog: .latest, order: .codePoint, limit: limit)
            try await waitUntilSettled(search)
            XCTAssertTrue(search.results.isEmpty)
        }
    }

    func testPendingSearchDoesNotRetainItsViewModel() {
        var search: CatalogSearch? = CatalogSearch()
        weak var reference = search
        search?.update("letter", catalog: .latest, order: .newestFirst)
        search = nil
        XCTAssertNil(reference)
    }
}
#endif
