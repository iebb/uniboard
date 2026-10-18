#if canImport(UIKit)
import UIKit

/// UITextDocumentProxy imports documentIdentifier as nonoptional UUID, but the
/// remote proxy can return Objective-C nil before connection or after detach.
/// Calling the public getter as an Objective-C object preserves that nil until
/// it has been validated; no identity is fabricated for an unavailable host.
@MainActor
enum KeyboardDocumentIdentity {
    private static let selector = #selector(getter: UITextDocumentProxy.documentIdentifier)

    static func read(from source: AnyObject?) -> UUID? {
        guard let source = source as? NSObjectProtocol,
              source.responds(to: selector),
              let object = source.perform(selector)?.takeUnretainedValue(),
              let identifier = object as? NSUUID else { return nil }
        return identifier as UUID
    }
}
#endif
