#if canImport(UIKit)
import Foundation
import XCTest

final class PrivacyManifestTests: XCTestCase {
    func testApplicationPackagesItsNoCollectionAndElapsedTimingDeclarations() throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "ad.neko.uniboard")
        try verifyManifest(in: Bundle.main)
    }

    func testEmbeddedKeyboardPackagesTheSamePrivacyContract() throws {
        let directory = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let contents = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)
        let extensionURL = try XCTUnwrap(contents.first { url in
            Bundle(url: url)?.bundleIdentifier == "ad.neko.uniboard.keyboard"
        })
        try verifyManifest(in: XCTUnwrap(Bundle(url: extensionURL)))
    }

    private func verifyManifest(in bundle: Bundle, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try XCTUnwrap(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "The shipped bundle must contain its privacy manifest", file: file, line: line)
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, file: file, line: line)
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertTrue(collected.isEmpty, "Typing and searches stay on device", file: file, line: line)
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        for (category, reason) in [
            ("NSPrivacyAccessedAPICategoryUserDefaults", "CA92.1"),
            ("NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1"),
            ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1")
        ] {
            let matching = entries.filter { $0["NSPrivacyAccessedAPIType"] as? String == category }
            XCTAssertEqual(matching.count, 1, "Each required category must have one declaration", file: file, line: line)
            let reasons = matching.first?["NSPrivacyAccessedAPITypeReasons"] as? [String]
            XCTAssertTrue(reasons?.contains(reason) == true, file: file, line: line)
        }
    }
}
#endif
