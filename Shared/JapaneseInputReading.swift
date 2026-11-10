import Foundation

/// Bounded, deterministic reading rules. Only lookup/preedit text is normalized;
/// callers must retain the original input for literal output and scalar accounting.
public enum JapaneseInputReading {
    public struct Reading: Equatable, Sendable {
        public let kana: String
        /// False while a supported Roman syllable is still unfinished (e.g. `ky`).
        public let isComplete: Bool
    }

    /// Reducer recognizer for the ENTIRE proposed input, including unfinished syllables.
    public static func normalize(mode: LanguageInputMode, rawInput: String) -> String? {
        guard mode == .japaneseRomaji else { return nil }
        return parse(rawInput)?.kana
    }

    /// Stable custom-word key: kana or supported romaji -> NFC hiragana reading.
    /// A final n is explicitly resolved to ん here; other unfinished syllables fail.
    /// This never normalizes the custom word's OUTPUT.
    public static func normalizedCustomReading(_ input: String) -> String? {
        guard let reading = parse(input, finalizeTrailingN: true), reading.isComplete,
              !reading.kana.isEmpty else { return nil }
        return reading.kana
    }

    /// Supports common Hepburn/Kunrei aliases, small kana via x/l, doubled
    /// consonants, n' syllable boundaries and '-' as the prolonged sound mark.
    /// Unsupported spellings/symbols fail closed rather than disappearing.
    public static func parse(_ rawInput: String, finalizeTrailingN: Bool = false) -> Reading? {
        guard rawInput.unicodeScalars.count <= LanguageCompositionLimits.rawInputScalars else { return nil }
        let normalized = rawInput.precomposedStringWithCanonicalMapping
        var input: [Unicode.Scalar] = []
        for scalar in normalized.unicodeScalars {
            switch scalar.value {
            case 65...90: input.append(Unicode.Scalar(scalar.value + 32)!)
            case 0x30A1...0x30F6, 0x30FD...0x30FE:
                input.append(Unicode.Scalar(scalar.value - 0x60)!)
            case 97...122, 39, 45, 0x3041...0x3096, 0x309D...0x309E, 0x30FC:
                input.append(scalar)
            default: return nil
            }
        }
        var output = ""
        var index = 0
        while index < input.count {
            let current = input[index]
            if current.value >= 0x3041 {
                output.unicodeScalars.append(current)
                index += 1
                continue
            }
            if current == "-" {
                output += "ー"
                index += 1
                continue
            }
            if current == "n" {
                if index + 1 == input.count {
                    output += finalizeTrailingN ? "ん" : "n"
                    return Reading(kana: output, isComplete: finalizeTrailingN)
                }
                let next = input[index + 1]
                if next == "'" {
                    output += "ん"
                    index += 2
                    continue
                }
                if next == "n" {
                    let followingStartsSyllable = index + 2 < input.count
                        && "aiueoy".unicodeScalars.contains(input[index + 2])
                    output += "ん"
                    index += followingStartsSyllable ? 1 : 2
                    continue
                }
                if !"aiueoy".unicodeScalars.contains(next) {
                    output += "ん"
                    index += 1
                    continue
                }
            }
            if index + 1 < input.count, current == input[index + 1],
               "bcdfghjklmpqrstvwxyz".unicodeScalars.contains(current) {
                output += "っ"
                index += 1
                continue
            }
            var matched = false
            for length in stride(from: min(4, input.count - index), through: 1, by: -1) {
                let key = String(String.UnicodeScalarView(input[index..<(index + length)]))
                if let kana = syllables[key] {
                    output += kana
                    index += length
                    matched = true
                    break
                }
            }
            if matched { continue }
            let suffix = String(String.UnicodeScalarView(input[index...]))
            guard syllables.keys.contains(where: { $0.hasPrefix(suffix) }) else { return nil }
            output += suffix
            return Reading(kana: output, isComplete: false)
        }
        return Reading(kana: output.precomposedStringWithCanonicalMapping, isComplete: true)
    }

    private static let syllables: [String: String] = {
        var table: [String: String] = [:]
        func row(_ prefix: String, _ kana: String) {
            for (vowel, character) in zip("aiueo", kana) { table[prefix + String(vowel)] = String(character) }
        }
        row("", "あいうえお")
        for (prefix, kana) in [("k", "かきくけこ"), ("g", "がぎぐげご"),
                               ("s", "さしすせそ"), ("z", "ざじずぜぞ"),
                               ("t", "たちつてと"), ("d", "だぢづでど"),
                               ("n", "なにぬねの"), ("h", "はひふへほ"),
                               ("b", "ばびぶべぼ"), ("p", "ぱぴぷぺぽ"),
                               ("m", "まみむめも"), ("r", "らりるれろ")] { row(prefix, kana) }
        for (prefix, stem) in [("ky", "き"), ("gy", "ぎ"), ("sy", "し"),
                               ("sh", "し"), ("zy", "じ"), ("jy", "じ"),
                               ("j", "じ"), ("ty", "ち"), ("ch", "ち"),
                               ("cy", "ち"), ("dy", "ぢ"), ("ny", "に"),
                               ("hy", "ひ"), ("by", "び"), ("py", "ぴ"),
                               ("my", "み"), ("ry", "り")] {
            for (vowel, small) in [("a", "ゃ"), ("u", "ゅ"), ("e", "ぇ"), ("o", "ょ")] {
                table[prefix + vowel] = stem + small
            }
        }
        for prefix in ["x", "l"] {
            row(prefix, "ぁぃぅぇぉ")
            for (roman, kana) in [("ya", "ゃ"), ("yu", "ゅ"), ("yo", "ょ"),
                                  ("tu", "っ"), ("tsu", "っ"), ("wa", "ゎ"),
                                  ("ka", "ゕ"), ("ke", "ゖ")] { table[prefix + roman] = kana }
        }
        for (roman, kana) in [("shi", "し"), ("chi", "ち"), ("tsu", "つ"), ("fu", "ふ"),
                              ("ji", "じ"), ("ya", "や"), ("yu", "ゆ"), ("yo", "よ"),
                              ("wa", "わ"), ("wo", "を"), ("wi", "うぃ"), ("we", "うぇ"),
                              ("ye", "いぇ"), ("xn", "ん"), ("wu", "う"),
                              ("ca", "か"), ("ci", "し"), ("cu", "く"), ("ce", "せ"), ("co", "こ")] {
            table[roman] = kana
        }
        for (prefix, stem) in [("v", "ゔ"), ("f", "ふ"), ("kw", "く"), ("gw", "ぐ")] {
            for (vowel, small) in zip("aiueo", "ぁぃぅぇぉ") { table[prefix + String(vowel)] = stem + String(small) }
        }
        table["vu"] = "ゔ"
        table["fu"] = "ふ"
        return table
    }()
}
