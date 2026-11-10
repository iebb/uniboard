import Foundation
import UIKit

/// Containing-app only. Create at the presentation boundary and call refresh on
/// screen entry / foreground. Keep the returned value only for that screen's
/// lifetime. No observers, global tracking, persistence, logging, or networking.
/// This API reads language hints, not keyboard-app identities or dictionaries;
/// it does not need the keyboard extension's Full Access permission.
@available(iOSApplicationExtension, unavailable)
@MainActor
struct LanguageSuggestionReader {
    /// Replaces rather than accumulates hints. The reader itself retains nothing.
    /// The containing app must declare ActiveKeyboards reason 3EC4.1 in its
    /// privacy manifest. Do not add this reader to the keyboard target.
    func refresh() -> LanguageSuggestionPolicy.Snapshot {
        let active = UITextInputMode.activeInputModes
            .prefix(LanguageSuggestionPolicy.maximumHintsPerSource)
            .map(\.primaryLanguage)
        let preferred = Array(Locale.preferredLanguages.prefix(LanguageSuggestionPolicy.maximumHintsPerSource))
        return LanguageSuggestionPolicy.snapshot(activeKeyboardLanguages: active,
                                                 preferredLanguages: preferred)
    }
}
