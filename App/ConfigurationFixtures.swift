#if DEBUG
import Foundation

/// DEBUG builds only: with the launch argument
/// `-UniboardConfigurationFixture <name>`, Import Configuration skips the
/// Files picker and reviews a generated file instead, so UI tests can run
/// the real review, replace and undo flow:
/// - `identical`: today's configuration, exported.
/// - `changed`: today's configuration with Extra Unicode Fonts flipped, two
///   favorites, a rule for U+2603 in a font no device has, and no
///   `[image_colors]` section.
/// - `legacy`: today's configuration, exported, plus the retired
///   `top_row` and `number_row` settings an older file may have.
/// - `invalid`: a file with three problems.
/// - `scale`: today's configuration, exported, with the Copy Image scale
///   changed (2×, or 1× when it is already 2×).
/// The URL `uniboard://debug/configuration-fixture/<name>` sets the same
/// for the rest of the session; `clear` goes back to the Files picker.
@MainActor
enum ConfigurationFixtures {
    static let launchArgument = "-UniboardConfigurationFixture"
    static let fileName = "Uniboard-Configuration-Fixture.toml"
    static let names: Set<String> = ["identical", "changed", "legacy", "invalid", "scale"]
    /// Set by the debug URL; wins over the launch argument.
    private static var selected: String?
    private static var cleared = false

    static func importData(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> (name: String, data: Data)? {
        var name = selected
        if name == nil, !cleared, let position = arguments.firstIndex(of: launchArgument), arguments.indices.contains(position + 1) {
            name = arguments[position + 1]
        }
        guard let name, let data = data(named: name, current: ConfigurationService().current().configuration) else { return nil }
        return (fileName, data)
    }

    /// Handles `uniboard://debug/configuration-fixture/<name>`; false for any other URL.
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "uniboard", url.host?.lowercased() == "debug", url.query == nil else { return false }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "configuration-fixture" else { return false }
        let name = String(parts[1])
        guard name == "clear" || names.contains(name) else { return true }
        selected = name == "clear" ? nil : name
        cleared = name == "clear"
        return true
    }

    static let missingFace = FontFaceReference(
        source: .imported, family: "Fixture Sans", style: "Regular", postScriptName: "FixtureSans-Regular",
        identity: .file(sha256: String(repeating: "0", count: 64), faceIndex: 0, variations: [:]))

    static func data(named name: String, current: UniboardConfiguration) -> Data? {
        switch name {
        case "identical":
            return ConfigurationCodec.encode(current)
        case "changed":
            var next = current
            next.settings.useUnicodeFonts.toggle()
            next.favorites = ["★", "Ω"]
            next.fontRules.removeAll { $0.selector == .codePoint(0x2603) }
            next.fontRules.append(FontRule(id: "fixture-snowman", selector: .codePoint(0x2603), face: missingFace))
            var document = ConfigurationCodec.document(next)
            document["image_colors"] = nil
            return Data(TOMLDocument.write(document).utf8)
        case "legacy":
            var document = ConfigurationCodec.document(current)
            var settings = document["settings"]?.tableValue ?? TOMLTable()
            settings["top_row"] = .string("search")
            settings["number_row"] = .boolean(!current.settings.showsNumberRow)
            document["settings"] = .table(settings)
            return Data(TOMLDocument.write(document).utf8)
        case "scale":
            var next = current
            next.imageColors.scale = next.imageColors.scale == 2 ? 1 : 2
            return ConfigurationCodec.encode(next)
        case "invalid":
            return Data("""
            schema_version = 1
            [settings]
            extra_unicode_fonts = "yes"
            unicode_edition = 3
            colour = true
            """.utf8)
        default:
            return nil
        }
    }
}
#endif
