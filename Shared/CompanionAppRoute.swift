import Foundation

/// A fixed navigation request. Keyboard text and preferences never enter a URL.
enum CompanionAppRoute {
    static let settingsURL = URL(string: "uniboard://settings")

    static func isSettings(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "uniboard"
            && url.host?.lowercased() == "settings"
            && (url.path.isEmpty || url.path == "/")
            && url.user == nil && url.password == nil && url.port == nil
            && url.query == nil && url.fragment == nil
    }
}
