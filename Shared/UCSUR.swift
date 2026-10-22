import Foundation

/// The ConScript Unicode Registry (https://www.kreativekorp.com/ucsur/)
/// assigns Private Use code points to constructed scripts. Only its block
/// ranges and names are kept here; they show when UCSUR is turned on.
enum UCSUR {
    struct Block: Equatable, Sendable {
        let start: UInt32
        let end: UInt32
        let name: String
    }

    /// Allocated blocks in code point order; withdrawn ones are left out.
    static let blocks: [Block] = [
        Block(start: 0xE000, end: 0xE07F, name: "TENGWAR"),
        Block(start: 0xE080, end: 0xE0FF, name: "CIRTH"),
        Block(start: 0xE100, end: 0xE14F, name: "ENGSVANYÁLI"),
        Block(start: 0xE150, end: 0xE1AF, name: "KINYA"),
        Block(start: 0xE1B0, end: 0xE1CF, name: "ILIANORE"),
        Block(start: 0xE1D0, end: 0xE1FF, name: "SYAI"),
        Block(start: 0xE200, end: 0xE26F, name: "VERDURIAN"),
        Block(start: 0xE270, end: 0xE28F, name: "AUI"),
        Block(start: 0xE290, end: 0xE2BF, name: "AMMAN-IAR"),
        Block(start: 0xE2C0, end: 0xE2CF, name: "STREICH"),
        Block(start: 0xE2D0, end: 0xE2FF, name: "XAÎNI"),
        Block(start: 0xE300, end: 0xE33F, name: "MIZARIAN"),
        Block(start: 0xE340, end: 0xE35F, name: "ZÍRÍ:NKA"),
        Block(start: 0xE360, end: 0xE37F, name: "SARKAI"),
        Block(start: 0xE380, end: 0xE3AF, name: "THELWIK"),
        Block(start: 0xE3B0, end: 0xE3FF, name: "OLAETYAN"),
        Block(start: 0xE400, end: 0xE42F, name: "NÍSKLÔZ"),
        Block(start: 0xE430, end: 0xE44F, name: "KAZAT ʔAKKOROU"),
        Block(start: 0xE450, end: 0xE46F, name: "KAZVARAD"),
        Block(start: 0xE470, end: 0xE48F, name: "ZARKHÁND"),
        Block(start: 0xE490, end: 0xE4BF, name: "RØZHXH"),
        Block(start: 0xE4C0, end: 0xE4EF, name: "SERIVELNA"),
        Block(start: 0xE4F0, end: 0xE4FF, name: "KELWATHI"),
        Block(start: 0xE500, end: 0xE51F, name: "SAKLOR"),
        Block(start: 0xE520, end: 0xE54F, name: "RYNNAN"),
        Block(start: 0xE550, end: 0xE57F, name: "ALZETJAN"),
        Block(start: 0xE580, end: 0xE59F, name: "TELARASSO"),
        Block(start: 0xE5A0, end: 0xE5BF, name: "SSÛRAKI"),
        Block(start: 0xE5C0, end: 0xE5DF, name: "GARGOYLE"),
        Block(start: 0xE5E0, end: 0xE5FF, name: "OPHIDIAN"),
        Block(start: 0xE600, end: 0xE62F, name: "FERENGI"),
        Block(start: 0xE630, end: 0xE64F, name: "SEUSSIAN LATIN EXTENSIONS"),
        Block(start: 0xE650, end: 0xE67F, name: "SYLABICA"),
        Block(start: 0xE680, end: 0xE6CF, name: "EWELLIC"),
        Block(start: 0xE6D0, end: 0xE6EF, name: "AMLIN"),
        Block(start: 0xE6F0, end: 0xE6FF, name: "UNIFON EXTENDED"),
        Block(start: 0xE700, end: 0xE73F, name: "UNIFON EXTENDED"),
        Block(start: 0xE740, end: 0xE76F, name: "UNIFON"),
        Block(start: 0xE770, end: 0xE77F, name: "SOLRESOL"),
        Block(start: 0xE780, end: 0xE7FF, name: "VISIBLE SPEECH"),
        Block(start: 0xE800, end: 0xE82F, name: "MONOFON"),
        Block(start: 0xE830, end: 0xE88F, name: "D'NI"),
        Block(start: 0xE890, end: 0xE8DF, name: "AUREBESH"),
        Block(start: 0xE8E0, end: 0xE8FF, name: "TONAL"),
        Block(start: 0xE900, end: 0xE97F, name: "GLAITHA-A"),
        Block(start: 0xE980, end: 0xE9FF, name: "GLAITHA-B"),
        Block(start: 0xEA00, end: 0xEA9F, name: "LHENAZI"),
        Block(start: 0xEAA0, end: 0xEAFF, name: "WANYA"),
        Block(start: 0xEB00, end: 0xEB3F, name: "OROKIN"),
        Block(start: 0xEB40, end: 0xEB5F, name: "STANDARD GALACTIC"),
        Block(start: 0xEB60, end: 0xEB9F, name: "BRAILLE EXTENDED"),
        Block(start: 0xEBA0, end: 0xEBDF, name: "CISTERCIAN NUMERALS"),
        Block(start: 0xEBE0, end: 0xEBEF, name: "LAPOINTE HEXADECIMAL NUMERALS"),
        Block(start: 0xEBF0, end: 0xEBFF, name: "MARTIN HEXADECIMAL NUMERALS"),
        Block(start: 0xEC00, end: 0xEC2F, name: "CYLENIAN"),
        Block(start: 0xEC30, end: 0xEC6F, name: "SYRRIN"),
        Block(start: 0xEC70, end: 0xECEF, name: "GRAFLECT"),
        Block(start: 0xECF0, end: 0xECFF, name: "WHITAKER HEXADECIMAL NUMERALS"),
        Block(start: 0xED00, end: 0xED3F, name: "DEINI"),
        Block(start: 0xED40, end: 0xED7F, name: "NIJI"),
        Block(start: 0xED80, end: 0xEDAF, name: "IRANIC"),
        Block(start: 0xEDB0, end: 0xEDDF, name: "TASSARUNESE"),
        Block(start: 0xEDE0, end: 0xEDEF, name: "ZESE"),
        Block(start: 0xEDF0, end: 0xEDFF, name: "GRAWLIXES"),
        Block(start: 0xF4C0, end: 0xF4EF, name: "ATH"),
        Block(start: 0xF8A0, end: 0xF8CF, name: "AIHA"),
        Block(start: 0xF8D0, end: 0xF8FF, name: "KLINGON"),
        Block(start: 0xF0000, end: 0xF0E69, name: "KINYA SYLLABLES"),
        Block(start: 0xF0E70, end: 0xF16AF, name: "PIKTO"),
        Block(start: 0xF16B0, end: 0xF16DF, name: "DERANI"),
        Block(start: 0xF16E0, end: 0xF16FF, name: "BRAILLE SUPPLEMENT"),
        Block(start: 0xF1700, end: 0xF18FF, name: "SEMTOG"),
        Block(start: 0xF1900, end: 0xF19FF, name: "SITELEN PONA"),
        Block(start: 0xF1B00, end: 0xF1C3F, name: "SHIDINN"),
        Block(start: 0xF1C40, end: 0xF1C7F, name: "TITI PULA"),
        Block(start: 0xF1C80, end: 0xF1C9F, name: "SITELEN PONA RADICALS"),
        Block(start: 0xF1CA0, end: 0xF1CFF, name: "YAPIRI"),
        Block(start: 0xF2000, end: 0xF267F, name: "SADALIAN"),
        Block(start: 0xF28A0, end: 0xF28DF, name: "ZBALERMORNA")
    ]

    static func block(containing codePoint: UInt32) -> Block? {
        var low = 0, high = blocks.count
        while low < high {
            let mid = (low + high) / 2
            if blocks[mid].end < codePoint { low = mid + 1 } else { high = mid }
        }
        return low < blocks.count && blocks[low].start <= codePoint ? blocks[low] : nil
    }
}
