import Foundation
import CoreFoundation

enum LocalPreferencePolicy {
    /// Optional capabilities stay disabled when an old/corrupt value is a
    /// string or arbitrary number instead of an actual stored Boolean.
    static func boolean(forKey key: String, in defaults: UserDefaults) -> Bool {
        guard let value = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }
}
