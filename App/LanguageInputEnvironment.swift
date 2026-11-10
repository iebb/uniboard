import Foundation

/// App-owned models shared by Settings, Languages and My Words. Resource files
/// and explicit custom words live beside configuration generations, never in
/// them. No active keyboard mode or unfinished input is persisted here.
@MainActor
final class LanguageInputEnvironment {
    static let shared = LanguageInputEnvironment()
    /// Payload-free invalidation only; never attach custom words or typed text.
    nonisolated static let changedNotification = "ad.neko.uniboard.language-input.changed"

    let languages: LanguageManagementModel
    let myWords: MyWordsModel

    private init() {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)
        let packs = container?.appendingPathComponent("LanguagePacks", isDirectory: true)
        let words = container?.appendingPathComponent("MyWords", isDirectory: true)
        let indexWorker = LanguageInputIndexWorker(directory: words)
        languages = LanguageManagementModel(root: packs)
        myWords = MyWordsModel(directory: words, rules: Self.dictionaryRules) {
            try await indexWorker.rebuild()
            Self.notifyKeyboard()
        }
        languages.onChange = { Self.notifyKeyboard() }
    }

    /// Apply/Undo changes preferences only. It must not import, enable, select,
    /// download or delete any resource or custom-word collection.
    func reloadConfiguration() {
        languages.refresh()
        Self.notifyKeyboard()
    }

    nonisolated fileprivate static var dictionaryRules: CustomInputDictionaryRules {
        CustomInputDictionaryRules(isSupportedMode: { modeID in
            guard let mode = LanguageInputMode(rawValue: modeID) else { return false }
            return [LanguageInputMode.direct, .japaneseRomaji, .mandarinPinyin].contains(mode)
        }, normalizeReading: { modeID, reading in
            guard let mode = LanguageInputMode(rawValue: modeID) else { return nil }
            switch mode {
            case .direct:
                // English words/shortcuts only: no URLs, mail addresses,
                // whitespace or arbitrary punctuation silently accepted.
                guard !reading.isEmpty, reading.utf8.allSatisfy({ byte in
                    (65...90).contains(byte) || (97...122).contains(byte)
                        || (48...57).contains(byte) || byte == 39 || byte == 45 || byte == 95
                }), reading.utf8.contains(where: { (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
                return reading.lowercased()
            case .japaneseRomaji:
                return JapaneseInputReading.normalizedCustomReading(reading)
            case .mandarinPinyin:
                return MandarinPinyinReading.canonicalCustomReading(reading)
            default:
                return nil // No reading contract for romaja or mechanical two-set input.
            }
        })
    }

    nonisolated private static func notifyKeyboard() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(changedNotification as CFString), nil, nil, true)
    }
}

/// Full source JSON reading and SQLite compilation belong to this app-only
/// worker, not the main actor or the keyboard. Failed publication is surfaced by
/// MyWordsModel's existing index-retry state; committed words remain committed.
private actor LanguageInputIndexWorker {
    private let directory: URL?

    init(directory: URL?) { self.directory = directory }

    func rebuild() throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try CustomInputDictionaryStore(
            directory: directory, rules: LanguageInputEnvironment.dictionaryRules).rebuildIndex()
    }
}
