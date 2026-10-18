import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class LocalPreferencePolicyTests: XCTestCase {
    func testOnlyExplicitStoredBooleansEnableOptionalCapabilities() throws {
        let name = "Uniboard.Boolean.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(LocalPreferencePolicy.boolean(forKey: "enabled", in: defaults))
        for invalid: Any in ["true", "YES", "1", 1, 2, -1, 1.5, [true], ["enabled": true]] {
            defaults.set(invalid, forKey: "enabled")
            XCTAssertFalse(LocalPreferencePolicy.boolean(forKey: "enabled", in: defaults))
        }
        defaults.set(true, forKey: "enabled")
        XCTAssertTrue(LocalPreferencePolicy.boolean(forKey: "enabled", in: defaults))
        defaults.set(false, forKey: "enabled")
        XCTAssertFalse(LocalPreferencePolicy.boolean(forKey: "enabled", in: defaults))
    }
}
