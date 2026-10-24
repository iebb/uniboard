import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// Search timing harness. Opt-in (UNIBOARD_BENCHMARK=1, or
/// TEST_RUNNER_UNIBOARD_BENCHMARK=1 for xcodebuild) so ordinary test runs stay
/// fast. Prints `BENCH` lines that the search-index report quotes.
final class UnicodeSearchBenchmarkTests: XCTestCase {
    static let queries = ["a", "ar", "arrow", "greek small", "U+00E9", "1F600", "heart", "cjk",
                          "qzxwvkjplm frobnicate", "e", "letter", "latin small letter a",
                          "face", "hangul syllable ga", "ideograph 4e0"]

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// The process's physical footprint, the figure jetsam limits apply to.
    static func footprintMB() -> Double {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
        #else
        return -1
        #endif
    }

    private func report(_ line: String) {
        print("BENCH " + line)
        lines.append(line)
    }
    private var lines: [String] = []

    func testSearchTimings() throws {
        guard ProcessInfo.processInfo.environment["UNIBOARD_BENCHMARK"] != nil else {
            throw XCTSkip("Set UNIBOARD_BENCHMARK=1 to run the search benchmark")
        }
        #if DEBUG
        report("build=debug")
        #else
        report("build=release")
        #endif
        let memoryBefore = Self.footprintMB()
        var catalog: UnicodeCatalog!
        let load = milliseconds { catalog = UnicodeCatalog() }
        report(String(format: "catalog-load ms=%.1f footprintMB=%.1f->%.1f records=%@", load, memoryBefore,
                      Self.footprintMB(), catalog.version))
        // The first query in the process pays for page faults in the mapped catalog.
        var first: [UnicodeCharacter] = []
        let firstTime = milliseconds { first = catalog.search("arrow", limit: 240, indexStore: UnicodeSearchIndexStore(directory: nil)) }
        report(String(format: "first-query q=arrow ms=%.1f results=%d footprintMB=%.1f", firstTime, first.count, Self.footprintMB()))
        let scanOnly = UnicodeSearchIndexStore(directory: nil)
        for query in Self.queries {
            var count = 0
            let cold = milliseconds { count = catalog.search(query, limit: 240, indexStore: scanOnly).count }
            var warm: [Double] = [], scanOnlyTimes: [Double] = []
            for _ in 0..<3 {
                warm.append(milliseconds { _ = catalog.search(query, limit: 240, indexStore: scanOnly) })
                scanOnlyTimes.append(milliseconds { _ = catalog.search(query, limit: 1, indexStore: scanOnly) })
            }
            report(String(format: "scan q=%@ first=%.1f warm240=%.1f warm1=%.1f results=%d",
                          query, cold, median(warm), median(scanOnlyTimes), count))
        }
        // The index: digest of a freshly loaded catalog, build, atomic write, then
        // mapping by a second store as the keyboard does.
        let fresh = UnicodeCatalog()
        let digest = milliseconds { _ = fresh.searchIndexIdentity }
        var built: Data?
        let before = Self.footprintMB()
        let build = milliseconds { built = fresh.makeSearchIndex() }
        report(String(format: "index-digest ms=%.1f build ms=%.1f bytes=%d footprintMB=%.1f->%.1f",
                      digest, build, built?.count ?? -1, before, Self.footprintMB()))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = UnicodeSearchIndexStore(directory: directory)
        let prepare = milliseconds { _ = writer.prepare(for: catalog) }
        let reader = UnicodeSearchIndexStore(directory: directory)
        let mapBefore = Self.footprintMB()
        let map = milliseconds { _ = reader.installedIndex(for: catalog) }
        report(String(format: "index-prepare ms=%.1f map+validate ms=%.1f footprintMB=%.1f->%.1f",
                      prepare, map, mapBefore, Self.footprintMB()))
        for query in Self.queries {
            var count = 0
            let cold = milliseconds { count = catalog.search(query, limit: 240, indexStore: reader).count }
            var warm: [Double] = [], limitOne: [Double] = []
            for _ in 0..<3 {
                warm.append(milliseconds { _ = catalog.search(query, limit: 240, indexStore: reader) })
                limitOne.append(milliseconds { _ = catalog.search(query, limit: 1, indexStore: reader) })
            }
            report(String(format: "index q=%@ first=%.1f warm240=%.1f warm1=%.1f results=%d",
                          query, cold, median(warm), median(limitOne), count))
        }
        // Equivalence over a large query set; the full set only in release builds.
        #if DEBUG
        let equivalence = UnicodeSearchIndexTests.equivalenceQueries(blockStride: 3, extended: false)
        #else
        let equivalence = UnicodeSearchIndexTests.equivalenceQueries(blockStride: 1, extended: true)
        #endif
        var mismatches = 0
        var scanTotal = 0.0, indexTotal = 0.0
        for query in equivalence {
            var scanned: [UInt32] = [], indexed: [UInt32] = []
            scanTotal += milliseconds { scanned = catalog.search(query, indexStore: scanOnly).map(\.codePoint) }
            indexTotal += milliseconds { indexed = catalog.search(query, indexStore: reader).map(\.codePoint) }
            if scanned != indexed { mismatches += 1; report("MISMATCH q=\(query)") }
        }
        report(String(format: "equivalence queries=%d mismatches=%d scanTotalMs=%.0f indexTotalMs=%.0f",
                      equivalence.count, mismatches, scanTotal, indexTotal))
        XCTAssertEqual(mismatches, 0)
        let emoji = EmojiCatalog.shared
        for query in ["a", "heart", "face", "1F600", "qzxwvkjplm"] {
            var count = 0
            let cold = milliseconds { count = emoji.search(query, limit: 120).count }
            let warm = median((0..<3).map { _ in milliseconds { _ = emoji.search(query, limit: 120) } })
            report(String(format: "emoji q=%@ first=%.1f warm=%.1f results=%d", query, cold, warm, count))
        }
        report(String(format: "end footprintMB=%.1f", Self.footprintMB()))
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "search-benchmark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
