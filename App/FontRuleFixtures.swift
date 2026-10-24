#if DEBUG
import Foundation

/// DEBUG builds only: saved font rules for UI tests and visual checks. Set
/// with the launch argument `-UniboardFontRuleFixture <name>` or the URL
/// `uniboard://debug/font-rule-fixture/<name>`; `clear` removes every rule.
/// A `--uitesting` launch without a fixture starts with no rules. Fixtures
/// never touch the Extra Unicode Fonts switch.
///
/// `-UniboardFontLibraryFixture installed` (or
/// `uniboard://debug/font-library-fixture/installed`) adds Papyrus and
/// Chalkduster to the font library as installed faces, so the preferred-font
/// picker has fonts to offer; `clear`, or a `--uitesting` launch without it,
/// removes just those two entries.
@MainActor
enum FontRuleFixtures {
    static let launchArgument = "-UniboardFontRuleFixture"

    /// Faces every iOS device has, referenced as installed faces.
    private static func installed(_ family: String, _ postScriptName: String) -> FontFaceReference {
        FontFaceReference(source: .installed, family: family, style: "Regular", postScriptName: postScriptName,
                          identity: .process(postScriptName: postScriptName, variations: [:]))
    }

    static func rules(named name: String) -> [FontRule]? {
        switch name {
        case "clear":
            return []
        case "sample":
            // A code point rule takes priority over its block's rule.
            guard let latin = FontRuleBlock(named: "Basic Latin") else { return nil }
            return [
                FontRule(id: "fixture-a", selector: .codePoint(0x41), face: installed("Papyrus", "Papyrus")),
                FontRule(id: "fixture-latin", selector: .block(latin), face: installed("Chalkduster", "Chalkduster")),
            ]
        default:
            return nil
        }
    }

    @discardableResult static func apply(named name: String, preferences: CatalogPreferences = .shared) -> Bool {
        guard let rules = rules(named: name) else { return false }
        if (FontRuleStore.shared.load() ?? []) != rules, !FontRuleStore.shared.save(rules) { return false }
        FontRulePreferences.shared.reload()
        preferences.reloadFontRules()
        return true
    }

    static let libraryLaunchArgument = "-UniboardFontLibraryFixture"
    static let libraryFaces = ["Papyrus", "Chalkduster"]

    @discardableResult static func applyLibrary(named name: String, store: CustomFontStore = .shared) -> Bool {
        switch name {
        case "installed":
            for face in libraryFaces { guard (try? store.addInstalled(postScriptName: face)) != nil else { return false } }
        case "clear":
            for font in store.fonts where font.installed == true && libraryFaces.contains(font.postScriptName) { try? store.remove(font) }
        default:
            return false
        }
        NotificationCenter.default.post(name: .fontExplorationLibraryChanged, object: nil)
        return true
    }

    static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if let position = arguments.firstIndex(of: launchArgument), arguments.indices.contains(position + 1) {
            apply(named: arguments[position + 1])
        } else if arguments.contains("--uitesting") {
            apply(named: "clear")
        }
        if let position = arguments.firstIndex(of: libraryLaunchArgument), arguments.indices.contains(position + 1) {
            applyLibrary(named: arguments[position + 1])
        } else if arguments.contains("--uitesting") {
            applyLibrary(named: "clear")
        }
    }

    /// The fixture a `uniboard://debug/font-rule-fixture/<name>` URL names.
    static func fixtureName(_ url: URL) -> String? { name(url, route: "font-rule-fixture") }

    /// The fixture a `uniboard://debug/font-library-fixture/<name>` URL names.
    static func libraryFixtureName(_ url: URL) -> String? { name(url, route: "font-library-fixture") }

    private static func name(_ url: URL, route: String) -> String? {
        guard url.scheme?.lowercased() == "uniboard", url.host?.lowercased() == "debug", url.query == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == route else { return nil }
        return String(parts[1])
    }
}
#endif
