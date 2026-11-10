import Foundation

/// Lookup constraints, not a greedy Roman-to-syllable parser. Actual dictionary
/// syllables resolve ambiguous streams such as xian / xi'an. Raw input is never
/// rewritten or committed by this value. Coordinates count normalized ASCII bytes.
public struct MandarinPinyinReading: Equatable, Sendable {
    public struct ToneConstraint: Equatable, Sendable {
        public let position: Int
        public let tone: Int
        public let endsSyllable: Bool
    }

    public let rawInput: String
    public let flat: String
    public let boundaries: Set<Int>
    public let apostropheBoundaries: Set<Int>
    public let toneConstraints: [ToneConstraint]
    public let hasTrailingBoundary: Bool

    /// Accepts ASCII case, ü/v/u:, tone marks or 1...5 (0 = neutral 5),
    /// and ASCII apostrophe as a hard boundary. No spaces/fuzzy substitutions.
    /// Incomplete prefixes remain valid lookup input and may yield no candidates.
    public init(_ rawInput: String) throws {
        guard !rawInput.isEmpty, rawInput.unicodeScalars.count <= 256 else {
            throw MandarinDictionaryError.invalidReading
        }
        let scalars = Array(rawInput.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars)
        var letters: [UInt8] = []
        var boundaries = Set<Int>()
        var apostropheBoundaries = Set<Int>()
        var tones: [ToneConstraint] = []
        var previousWasLetter = false
        var previousWasBoundary = false
        var previousWasToneDigit = false
        var previousWasModifier = false
        for scalar in scalars {
            switch scalar.value {
            case 97...122:
                letters.append(UInt8(scalar.value))
                previousWasLetter = true; previousWasBoundary = false
                previousWasToneDigit = false; previousWasModifier = false
            case 0x308: // Decomposed ü, including ǖ/ǘ/ǚ/ǜ. Never discard this mark.
                guard previousWasLetter, letters.last == 117 else { throw MandarinDictionaryError.invalidReading }
                letters[letters.count - 1] = 118
                previousWasModifier = true
            case 58: // u: keyboard alias; not a general punctuation escape.
                guard previousWasLetter, !previousWasModifier, letters.last == 117 else {
                    throw MandarinDictionaryError.invalidReading
                }
                letters[letters.count - 1] = 118; previousWasModifier = true
            case 0x304, 0x301, 0x30C, 0x300:
                guard previousWasLetter, let last = letters.last,
                      [97, 101, 105, 111, 117, 118, 109, 110].contains(Int(last)),
                      !tones.contains(where: { !$0.endsSyllable && $0.position == letters.count - 1 }) else {
                    throw MandarinDictionaryError.invalidReading
                }
                let tone = [UInt32(0x304): 1, 0x301: 2, 0x30C: 3, 0x300: 4][scalar.value]!
                tones.append(.init(position: letters.count - 1, tone: tone, endsSyllable: false))
                previousWasModifier = true
            case 48...53:
                guard previousWasLetter, !previousWasToneDigit else { throw MandarinDictionaryError.invalidReading }
                let tone = scalar.value == 48 ? 5 : Int(scalar.value - 48)
                tones.append(.init(position: letters.count, tone: tone, endsSyllable: true))
                boundaries.insert(letters.count)
                previousWasToneDigit = true; previousWasLetter = false; previousWasModifier = false
                previousWasBoundary = false
            case 39:
                guard !letters.isEmpty, !previousWasBoundary,
                      previousWasLetter || previousWasToneDigit else { throw MandarinDictionaryError.invalidReading }
                boundaries.insert(letters.count)
                apostropheBoundaries.insert(letters.count)
                previousWasBoundary = true; previousWasLetter = false; previousWasToneDigit = false
                previousWasModifier = false
            default:
                throw MandarinDictionaryError.invalidReading
            }
        }
        guard !letters.isEmpty else { throw MandarinDictionaryError.invalidReading }
        self.rawInput = rawInput
        self.flat = String(bytes: letters, encoding: .utf8)!
        self.boundaries = boundaries
        self.apostropheBoundaries = apostropheBoundaries
        self.toneConstraints = tones
        self.hasTrailingBoundary = previousWasBoundary
    }

    /// Tests constraints against a complete dictionary reading. Tone digits end
    /// syllables, whereas a tone mark applies to the syllable containing its vowel.
    public func matches(syllables: [String], tones: [Int], prefix: Bool = false) -> Bool {
        guard !syllables.isEmpty, syllables.count == tones.count else { return false }
        let candidate = syllables.joined()
        guard prefix ? candidate.hasPrefix(flat) : candidate == flat else { return false }
        var ends: [Int] = []
        var end = 0
        for syllable in syllables { end += syllable.utf8.count; ends.append(end) }
        guard boundaries.allSatisfy({ ends.contains($0) }) else { return false }
        for constraint in toneConstraints {
            let index: Int?
            if constraint.endsSyllable { index = ends.firstIndex(of: constraint.position) }
            else { index = ends.firstIndex(where: { $0 > constraint.position }) }
            guard let index, tones[index] == constraint.tone else { return false }
        }
        return true
    }

    /// Strict full-entry validator for My Words; unlike runtime constraints it
    /// requires a complete segmentation into supported syllables. Canonical form:
    /// lowercase, v for ü/u:, neutral 0 -> 5, ORIGINAL apostrophes.
    /// Tone-free ambiguity is preserved (xian stays distinct from xi'an).
    /// Diacritics become digits only when their syllable end is unambiguous;
    /// otherwise retain the tone mark at its original vowel, never guess.
    /// Output text is deliberately not an argument and is NEVER normalized.
    public static func canonicalCustomReading(_ rawInput: String) -> String? {
        guard let reading = try? Self(rawInput), !reading.hasTrailingBoundary else { return nil }
        let bytes = Array(reading.flat.utf8), count = bytes.count
        var edges = [[Int]](repeating: [], count: count + 1)
        for start in 0..<count {
            for end in (start + 1)...min(count, start + 6) {
                let word = String(bytes: bytes[start..<end], encoding: .utf8)!
                guard supportedCustomSyllables.contains(word),
                      !reading.boundaries.contains(where: { $0 > start && $0 < end }) else { continue }
                let constraints = reading.toneConstraints.filter {
                    $0.endsSyllable ? $0.position == end : ($0.position >= start && $0.position < end)
                }
                guard Set(constraints.map(\.tone)).count <= 1 else { continue }
                edges[start].append(end)
            }
        }
        var reachesEnd = [Bool](repeating: false, count: count + 1)
        reachesEnd[count] = true
        for start in stride(from: count - 1, through: 0, by: -1) {
            reachesEnd[start] = edges[start].contains(where: { reachesEnd[$0] })
        }
        guard reachesEnd[0] else { return nil }
        var reachable = [Bool](repeating: false, count: count + 1)
        reachable[0] = true
        var markEnds = [Set<Int>](repeating: [], count: reading.toneConstraints.count)
        for start in 0..<count where reachable[start] {
            for end in edges[start] where reachesEnd[end] {
                reachable[end] = true
                for (index, constraint) in reading.toneConstraints.enumerated()
                    where !constraint.endsSyllable && constraint.position >= start && constraint.position < end {
                    markEnds[index].insert(end)
                }
            }
        }
        var tonesByEnd: [Int: Int] = [:]
        var retainedMarks: [Int: Int] = [:]
        for (index, constraint) in reading.toneConstraints.enumerated() {
            let end: Int
            if constraint.endsSyllable { end = constraint.position }
            else {
                guard !markEnds[index].isEmpty else { return nil }
                if markEnds[index].count > 1 {
                    retainedMarks[constraint.position] = constraint.tone
                    continue
                }
                end = markEnds[index].first!
            }
            if let existing = tonesByEnd[end], existing != constraint.tone { return nil }
            tonesByEnd[end] = constraint.tone
        }
        var canonical = ""
        for index in bytes.indices {
            canonical.append(Character(UnicodeScalar(bytes[index])))
            if let mark = retainedMarks[index] {
                canonical += [1: "\u{304}", 2: "\u{301}", 3: "\u{30c}", 4: "\u{300}"][mark]!
            }
            if let tone = tonesByEnd[index + 1] { canonical += String(tone) }
            if reading.apostropheBoundaries.contains(index + 1) { canonical += "'" }
        }
        return canonical.precomposedStringWithCanonicalMapping
    }

    /// Phonetic grammar ONLY, not a demo vocabulary. The 418 tone-free spellings
    /// present across audited Wanxiang jichu+zi at aa9947f3f513ff88a3f7ce4e342fcb519d517025.
    /// Source data: amzxyz / 万象词库, CC BY 4.0, https://creativecommons.org/licenses/by/4.0/ .
    /// Modification: extract unique syllable spellings, remove tones, map ü -> v.
    /// No Rime schema/code copied. Includes source-supported rare syllabic m/n/ng.
    private static let supportedCustomSyllables: Set<String> = Set("""
    a ai an ang ao ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bu ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo e ei en eng er fa fan fang fei fen feng fiao fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve m ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu n na nai nan nang nao ne nei nen neng ng ni nian niang niao nie nin ning niu nong nou nu nuan nun nuo nv nve o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo wa wai wan wang wei wen weng wo wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
    """.split(separator: " ").map(String.init))

    /// Internal source adapter. Unmarked source syllables represent neutral tone.
    /// This never transforms output text or user dictionary outputs.
    static func sourceSyllables(_ reading: String) throws -> (syllables: [String], tones: [Int]) {
        let words = reading.split(separator: " ", omittingEmptySubsequences: false)
        guard !words.isEmpty, words.count <= 32 else { throw MandarinDictionaryError.invalidReading }
        var syllables: [String] = [], tones: [Int] = []
        for word in words {
            let parsed = try Self(String(word))
            guard parsed.boundaries.isEmpty, parsed.toneConstraints.count <= 1,
                  parsed.flat.utf8.count <= 6 else { throw MandarinDictionaryError.invalidReading }
            syllables.append(parsed.flat)
            tones.append(parsed.toneConstraints.first?.tone ?? 5)
        }
        return (syllables, tones)
    }
}
