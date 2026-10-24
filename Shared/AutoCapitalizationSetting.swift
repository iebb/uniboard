import Foundation

/// How the keyboard capitalizes upcoming letters. Follow App keeps today's
/// behavior: the host field's own autocapitalization trait.
enum AutoCapitalizationMode: String, CaseIterable, Codable, Sendable {
    case followApp = "follow_app"
    case off
    case sentences
    case words
    case allCharacters = "all_characters"
}

/// The shared auto-capitalization choice, in the current configuration
/// generation. The app writes; the keyboard only reads it on appear or
/// refresh. Missing or unusable data means Follow App.
struct AutoCapitalizationSetting {
    static let filename = "auto-capitalization-v1.json"
    static let maximumPayloadBytes = 256
    static let shared = AutoCapitalizationSetting()

    private struct File: Codable {
        let mode: String
        let schemaVersion: Int
    }

    let directory: () -> URL?

    init(directory: @escaping () -> URL? = { SharedConfigurationLocation.shared.currentDirectory() }) {
        self.directory = directory
    }

    func load() -> AutoCapitalizationMode {
        guard let directory = directory(),
              let data = try? SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(Self.filename),
                                                                          limit: Self.maximumPayloadBytes + 1) else { return .followApp }
        return Self.decode(data) ?? .followApp
    }

    /// Only the containing app calls this.
    @discardableResult func save(_ mode: AutoCapitalizationMode) -> Bool {
        guard let directory = directory(),
              (try? SharedConfigurationLocation.replaceFile(Self.encode(mode), at: directory.appendingPathComponent(Self.filename))) != nil else { return false }
        return true
    }

    static func encode(_ mode: AutoCapitalizationMode) -> Data {
        // A raw value and an integer: encoding can't fail.
        try! SharedConfigurationLocation.encoder.encode(File(mode: mode.rawValue, schemaVersion: 1))
    }

    static func decode(_ data: Data) -> AutoCapitalizationMode? {
        guard data.count <= maximumPayloadBytes, let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == 1 else { return nil }
        return AutoCapitalizationMode(rawValue: file.mode)
    }
}

extension AutoCapitalizationMode {
    /// The Settings title (docs/inspection-capitalization-copy.md).
    var title: String {
        switch self {
        case .followApp: return "Follow App"
        case .off: return "Off"
        case .sentences: return "Sentences"
        case .words: return "Words"
        case .allCharacters: return "All Characters"
        }
    }

    /// The Settings description beneath the title.
    var summary: String {
        switch self {
        case .followApp: return "Use the typing app’s capitalization preference."
        case .off: return "Use capitals only when you choose Shift or Caps Lock."
        case .sentences: return "Start detected sentences with a capital letter."
        case .words: return "Start detected words with a capital letter."
        case .allCharacters: return "Use capitals for letter keys that support them."
        }
    }
}

/// Settings copy for the Auto-Capitalization screen.
enum AutoCapitalizationCopy {
    static let title = "Auto-Capitalization"
    static let header = "Choose when letter keys use capitals automatically. This affects new typing, not existing text."
    static let footer = "Some fields turn off automatic capitals. Languages without capital letters are unchanged."
    static let footerDetail = "Custom key text, pasted text and symbols stay exactly as entered."

    /// The import preview's Settings change line.
    static func change(from old: AutoCapitalizationMode, to new: AutoCapitalizationMode) -> String {
        "Auto-Capitalization: \(old.title) → \(new.title)"
    }
}

/// Decides the automatic capitalization the keyboard applies to upcoming
/// letters. The host's restrictions always win: fields that don't permit
/// English assistance (URL, email, username, passwords, one-time codes,
/// secure entry, non-default keyboard types) get no automatic capitals in
/// any mode. Otherwise Follow App keeps the host's own request and every
/// other mode replaces it. Manual Shift and Caps Lock are a separate policy;
/// this never rewrites existing text.
enum KeyboardAutoCapitalizationPolicy {
    /// Maps `UITextAutocapitalizationType.rawValue` (0 none, 1 words,
    /// 2 sentences, 3 all characters). Unknown values read as sentences,
    /// the UIKit default.
    static func hostMode(rawValue: Int) -> KeyboardAutomaticCapitalization {
        switch rawValue {
        case 0: return .none
        case 1: return .words
        case 3: return .allCharacters
        default: return .sentences
        }
    }

    static func effectiveMode(setting: AutoCapitalizationMode, host: KeyboardAutomaticCapitalization,
                              permitsAssistance: Bool) -> KeyboardAutomaticCapitalization {
        guard permitsAssistance else { return .none }
        switch setting {
        case .followApp: return host
        case .off: return .none
        case .sentences: return .sentences
        case .words: return .words
        case .allCharacters: return .allCharacters
        }
    }

    /// Whether the next letter starts with an automatic capital.
    static func shouldCapitalize(setting: AutoCapitalizationMode, hostRawValue: Int,
                                 permitsAssistance: Bool, before: String?) -> Bool {
        let mode = effectiveMode(setting: setting, host: hostMode(rawValue: hostRawValue), permitsAssistance: permitsAssistance)
        return KeyboardEnglishInputPolicy.shouldCapitalize(mode: mode, before: before)
    }
}
