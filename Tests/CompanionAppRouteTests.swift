import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class CompanionAppRouteTests: XCTestCase {
    func testSettingsDestinationAndCaseInsensitiveSchemeHost() throws {
        for text in ["uniboard://settings", "UNIBOARD://SETTINGS", "uniboard://settings/"] {
            XCTAssertTrue(CompanionAppRoute.isSettings(try XCTUnwrap(URL(string: text))))
        }
    }

    func testOtherDestinationsAndAnyEmbeddedDataCannotTriggerNavigation() throws {
        for text in ["https://settings", "uniboard://other", "uniboard:settings", "uniboard://settings/other",
                     "uniboard://user@settings", "uniboard://user:secret@settings", "uniboard://settings:123",
                     "uniboard://settings?query=private", "uniboard://settings#private", "uniboard://settings?",
                     "uniboard://settings#", "file:///settings"] {
            XCTAssertFalse(CompanionAppRoute.isSettings(try XCTUnwrap(URL(string: text))), text)
        }
    }
}
