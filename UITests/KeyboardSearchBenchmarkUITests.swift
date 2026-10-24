import XCTest
import UIKit

/// Search benchmark inside the keyboard process: DEBUG builds of the keyboard
/// publish each search's duration, index use and footprint on
/// `keyboard.search.timing`. Opt-in: no shard or workflow selects this class;
/// run it with -only-testing:UniboardUITests/KeyboardSearchBenchmarkUITests
/// and UNIBOARD_KEYBOARD_INTEGRATION=1. Unit tests cover the index itself
/// (Tests/UnicodeSearchIndexTests.swift).
@MainActor
final class KeyboardSearchBenchmarkUITests: UniboardUITestCase {
    private static let benchmarkQueries = ["arrow", "heart", "greek small", "cjk", "ar", "letter", "u+00e9", "1f600", "qzxwvkjplm"]

    /// The probe's label once the newest search has published and settled.
    private func settledSearchTiming(after previous: String, timeout: TimeInterval = 30) -> String {
        let probe = app.descendants(matching: .any)["keyboard.search.timing"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var last = "", stableSince = Date()
        while Date() < deadline {
            let label = probe.exists ? probe.label : ""
            if label != last { last = label; stableSince = Date() }
            if label.hasPrefix("n="), label != previous, Date().timeIntervalSince(stableSince) >= 1.5 { return label }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return last
    }

    private func measureKeyboardSearches(_ phase: String, into lines: inout [String]) {
        var previous = ""
        for query in Self.benchmarkQueries {
            enterKeyboardQuery(query)
            let timing = settledSearchTiming(after: previous)
            previous = timing
            lines.append("KEYBOARD-BENCH \(phase) q=\(query) \(timing)")
        }
        closeKeyboardSearch()
    }

    func testSystemKeyboardSearchTimingWithAndWithoutIndex() throws {
        try requireKeyboardIntegration()
        var lines: [String] = []
        // Without the index: the app removes it and does not build it.
        app.launchArguments = ["--uitesting", "--search-index-off"]
        _ = openSystemKeyboardHost()
        measureKeyboardSearches("scan", into: &lines)
        restoreEnglishKeyboard()
        // With the index: the app builds it in the background after launch.
        app.launchArguments = ["--uitesting"]
        _ = openSystemKeyboardHost()
        Thread.sleep(forTimeInterval: 8)
        measureKeyboardSearches("index", into: &lines)
        restoreEnglishKeyboard()
        for line in lines { print(line) }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "keyboard-search-benchmark"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(lines.contains { $0.contains(" index ") && $0.contains("indexed=1") },
                      "The keyboard should map the index the app built: \(lines.joined(separator: "\n"))")
    }
}
