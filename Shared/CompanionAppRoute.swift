import Foundation

/// Validate the app’s external Settings route without accepting embedded data.
enum CompanionAppRoute {
    static func isSettings(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "uniboard"
            && url.host?.lowercased() == "settings"
            && (url.path.isEmpty || url.path == "/")
            && url.user == nil && url.password == nil && url.port == nil
            && url.query == nil && url.fragment == nil
    }
}
