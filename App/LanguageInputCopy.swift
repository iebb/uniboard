import Foundation

// App-only presentation. Engines and the keyboard do not depend on localized copy.
extension LanguageInputMode {
    var title: String {
        switch self {
        case .direct: return "Direct Typing"
        case .japaneseRomaji: return "Japanese — Romaji"
        case .mandarinPinyin: return "Mandarin Chinese — Pinyin"
        case .koreanRomaja: return "Korean — Romaja"
        case .koreanTwoSetHangul: return "Korean — Two-Set Hangul"
        }
    }

    var summary: String {
        switch self {
        case .direct: return "Type characters without language conversion."
        case .japaneseRomaji: return "Type romaji, then choose Japanese text."
        case .mandarinPinyin: return "Type pinyin, then choose Chinese text."
        case .koreanRomaja: return "Type Korean with Roman letters using the spellings in the Typing Guide."
        case .koreanTwoSetHangul: return "Type Korean with consonant and vowel keys in the standard two-set layout."
        }
    }

    var nativeLabel: String {
        switch self {
        case .direct: return "English"
        case .japaneseRomaji: return "日本語"
        case .mandarinPinyin: return "拼音"
        case .koreanRomaja, .koreanTwoSetHangul: return "한국어"
        }
    }
}

enum LanguageInputCopy {
    static let koreanPending = "Korean spelling is awaiting a decision. Creating and importing Korean dictionaries isn’t available yet."
    static let exactOutput = "Output is preserved exactly, including accents, combining characters and Unicode sequences."
    static let collectionLimit = "My Words can contain up to 1,024 dictionaries, including empty dictionaries. Remove a dictionary before creating another."
    static let localWords = "Your custom words are stored on this device and offered as choices, not forced replacements. They aren’t sent to a server."
    static let backup = "Export each dictionary to keep a copy. Reinstalling the app may remove locally stored words."
    static let format = "Use a UTF-8 .tsv or .txt file. Each entry has a reading and output separated by a tab. You can add a third column for weight, from 0 to 10000. If omitted, the weight is 100."
    static let formatLines = "Don’t include a header row. Blank lines and lines starting with # are ignored. Choose the input mode before importing."
    static let formatLimits = "Each file can be up to 1 MiB and contain 10,000 entries. My Words can contain 50,000 entries in total. Each reading and output can contain up to 256 Unicode code points. Tabs, line breaks and the null character aren’t allowed inside a reading or output."
    static let separateDictionary = "This creates a separate dictionary. Your existing words won’t be replaced."
    static let duplicates = "Exact duplicates are kept once. Different outputs for the same reading remain separate choices."
    static let combined = "Combined Entries counts additional distinct weights for the same reading and exact output in this file. The highest weight is kept. These aren’t duplicates or invalid entries. Existing dictionaries aren’t changed."
    static let undoUnavailable = "Undo Import is no longer available because a later change could be lost. Your later changes have been kept."

    static func readingHelp(_ mode: LanguageInputMode) -> String {
        switch mode {
        case .direct: return "Enter a word or shortcut."
        case .japaneseRomaji: return "Enter kana or supported romaji."
        case .mandarinPinyin: return "Enter full pinyin using the spellings in the Typing Guide."
        case .koreanRomaja: return koreanPending
        case .koreanTwoSetHangul: return "My Words is available for Korean — Romaja, not Two-Set Hangul."
        }
    }

    static func message(_ issue: CustomInputDictionaryValidationIssue) -> String {
        switch issue {
        case .unsupportedMode: return "This input mode isn’t available for custom words."
        case .missingTab: return "Use a tab between the reading and output."
        case .columnCount: return "Use two columns, or three when including a weight."
        case .emptyReading: return "Enter a reading."
        case .emptyOutput: return "Enter an output."
        case .invalidWeight: return "Weight must be a whole number from 0 to 10000."
        case .unsupportedReading: return "This reading isn’t supported by the selected input mode."
        case .readingTooLong: return "The reading exceeds 256 Unicode code points."
        case .outputTooLong: return "The output exceeds 256 Unicode code points."
        case .forbiddenCharacter: return "The reading or output contains a character that isn’t allowed (tab, line break or null character)."
        }
    }

    static func message(_ issue: CustomInputDictionaryFileIssue) -> String {
        switch issue {
        case .invalidUTF8: return "Choose a UTF-8 text file."
        case .tooLarge: return "This file exceeds the 1 MiB limit."
        case .tooManyEntryLines: return "This file exceeds the 10,000-entry limit."
        case .tooManyTotalEntries: return "This import would exceed the 50,000-entry limit in My Words."
        case .tooManyCollections: return collectionLimit
        case .unsupportedMode: return "This input mode isn’t available for custom words."
        case .noEntries: return "No entries to import"
        }
    }

    // Never display localizedDescription: external file errors can contain private paths.
    static func message(_ error: Error) -> String {
        guard let error = error as? CustomInputDictionaryStoreError else {
            return "Couldn’t read or save your dictionary. Check file access and available storage, then try again."
        }
        switch error {
        case .revisionConflict: return "My Words changed since this review. Review the current words before trying again."
        case .undoConflict: return undoUnavailable
        case .noImportToUndo: return "No dictionary import is available to undo."
        case .invalidPreview: return "Review the dictionary again before importing."
        case .invalidName: return "Enter a dictionary name with up to 256 Unicode code points and no tabs, line breaks or null characters."
        case .validation(let issue): return message(issue)
        case .totalEntryLimit: return "This change would exceed the 50,000-entry limit in My Words."
        case .collectionLimit: return collectionLimit
        case .duplicateEntry: return "This reading and output already exist in this dictionary. Edit the existing entry to change its weight."
        case .collectionNotFound: return "This dictionary is no longer available. Return to My Words and try again."
        case .entryNotFound: return "This entry is no longer available. Review the dictionary and try again."
        case .corruptSnapshot: return "Your saved dictionaries couldn’t be read. They haven’t been replaced."
        case .unsupportedSchema: return "This version of Uniboard can’t read these saved dictionaries. They haven’t been replaced."
        case .snapshotTooLarge: return "Your saved dictionaries exceed the supported storage size. They haven’t been replaced."
        }
    }
}
