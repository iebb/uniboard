import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class CatalogWorkerTests: XCTestCase {
    func testNormalResultIsReturned() async {
        let result = await CatalogWorker.run { ["U+0041", "U+1F680"] }
        XCTAssertEqual(result, ["U+0041", "U+1F680"])
    }

    func testCallerCancellationReachesTheDetachedScan() async {
        let started = expectation(description: "Detached scan started")
        let task = Task {
            await CatalogWorker.run {
                started.fulfill()
                let deadline = Date().addingTimeInterval(3)
                while !Task.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
                return Task.isCancelled
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled, "Cancelling the UI task must also stop the detached catalog scan")
    }

    func testAlreadyCancelledCallerPropagatesCancellationIntoNewWork() async {
        let task = Task {
            // Suspend before creating the worker so cancellation occurs first.
            do { try await Task.sleep(for: .seconds(30)) } catch {}
            return await CatalogWorker.run {
                let deadline = Date().addingTimeInterval(1)
                while !Task.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
                return Task.isCancelled
            }
        }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }
}
