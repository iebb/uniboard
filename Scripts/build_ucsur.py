#!/usr/bin/env python3
"""Builds Shared/Resources/UCSUR.txt from the Under-ConScript Unicode Registry.

Download UnicodeData.txt, NamesList.txt and Blocks.txt from
https://www.kreativekorp.com/ucsur/UNIDATA/ in a browser into one folder, then:

    python3 Scripts/build_ucsur.py <folder>

Blocks follow the registry's current table below. A character from the
UNIDATA files is kept only while the block that held it still has the same
name, so code points the registry has since reassigned are left out.
"""
import re
import sys
import unicodedata
from pathlib import Path

# The registry's current allocated blocks (https://www.kreativekorp.com/ucsur/).
BLOCKS = [
    (0xE000, 0xE07F, "TENGWAR"),
    (0xE080, 0xE0FF, "CIRTH"),
    (0xE100, 0xE14F, "ENGSVANYÁLI"),
    (0xE150, 0xE1AF, "KINYA"),
    (0xE1B0, 0xE1CF, "ILIANORE"),
    (0xE1D0, 0xE1FF, "SYAI"),
    (0xE200, 0xE26F, "VERDURIAN"),
    (0xE270, 0xE28F, "AUI"),
    (0xE290, 0xE2BF, "AMMAN-IAR"),
    (0xE2C0, 0xE2CF, "STREICH"),
    (0xE2D0, 0xE2FF, "XAÎNI"),
    (0xE300, 0xE33F, "MIZARIAN"),
    (0xE340, 0xE35F, "ZÍRÍ:NKA"),
    (0xE360, 0xE37F, "SARKAI"),
    (0xE380, 0xE3AF, "THELWIK"),
    (0xE3B0, 0xE3FF, "OLAETYAN"),
    (0xE400, 0xE42F, "NÍSKLÔZ"),
    (0xE430, 0xE44F, "KAZAT ʔAKKOROU"),
    (0xE450, 0xE46F, "KAZVARAD"),
    (0xE470, 0xE48F, "ZARKHÁND"),
    (0xE490, 0xE4BF, "RØZHXH"),
    (0xE4C0, 0xE4EF, "SERIVELNA"),
    (0xE4F0, 0xE4FF, "KELWATHI"),
    (0xE500, 0xE51F, "SAKLOR"),
    (0xE520, 0xE54F, "RYNNAN"),
    (0xE550, 0xE57F, "ALZETJAN"),
    (0xE580, 0xE59F, "TELARASSO"),
    (0xE5A0, 0xE5BF, "SSÛRAKI"),
    (0xE5C0, 0xE5DF, "GARGOYLE"),
    (0xE5E0, 0xE5FF, "OPHIDIAN"),
    (0xE600, 0xE62F, "FERENGI"),
    (0xE630, 0xE64F, "SEUSSIAN LATIN EXTENSIONS"),
    (0xE650, 0xE67F, "SYLABICA"),
    (0xE680, 0xE6CF, "EWELLIC"),
    (0xE6D0, 0xE6EF, "AMLIN"),
    (0xE6F0, 0xE6FF, "UNIFON EXTENDED"),
    (0xE700, 0xE73F, "UNIFON EXTENDED"),
    (0xE740, 0xE76F, "UNIFON"),
    (0xE770, 0xE77F, "SOLRESOL"),
    (0xE780, 0xE7FF, "VISIBLE SPEECH"),
    (0xE800, 0xE82F, "MONOFON"),
    (0xE830, 0xE88F, "D'NI"),
    (0xE890, 0xE8DF, "AUREBESH"),
    (0xE8E0, 0xE8FF, "TONAL"),
    (0xE900, 0xE97F, "GLAITHA-A"),
    (0xE980, 0xE9FF, "GLAITHA-B"),
    (0xEA00, 0xEA9F, "LHENAZI"),
    (0xEAA0, 0xEAFF, "WANYA"),
    (0xEB00, 0xEB3F, "OROKIN"),
    (0xEB40, 0xEB5F, "STANDARD GALACTIC"),
    (0xEB60, 0xEB9F, "BRAILLE EXTENDED"),
    (0xEBA0, 0xEBDF, "CISTERCIAN NUMERALS"),
    (0xEBE0, 0xEBEF, "LAPOINTE HEXADECIMAL NUMERALS"),
    (0xEBF0, 0xEBFF, "MARTIN HEXADECIMAL NUMERALS"),
    (0xEC00, 0xEC2F, "CYLENIAN"),
    (0xEC30, 0xEC6F, "SYRRIN"),
    (0xEC70, 0xECEF, "GRAFLECT"),
    (0xECF0, 0xECFF, "WHITAKER HEXADECIMAL NUMERALS"),
    (0xED00, 0xED3F, "DEINI"),
    (0xED40, 0xED7F, "NIJI"),
    (0xED80, 0xEDAF, "IRANIC"),
    (0xEDB0, 0xEDDF, "TASSARUNESE"),
    (0xEDE0, 0xEDEF, "ZESE"),
    (0xEDF0, 0xEDFF, "GRAWLIXES"),
    (0xF4C0, 0xF4EF, "ATH"),
    (0xF8A0, 0xF8CF, "AIHA"),
    (0xF8D0, 0xF8FF, "KLINGON"),
    (0xF0000, 0xF0E69, "KINYA SYLLABLES"),
    (0xF0E70, 0xF16AF, "PIKTO"),
    (0xF16B0, 0xF16DF, "DERANI"),
    (0xF16E0, 0xF16FF, "BRAILLE SUPPLEMENT"),
    (0xF1700, 0xF18FF, "SEMTOG"),
    (0xF1900, 0xF19FF, "SITELEN PONA"),
    (0xF1B00, 0xF1C3F, "SHIDINN"),
    (0xF1C40, 0xF1C7F, "TITI PULA"),
    (0xF1C80, 0xF1C9F, "SITELEN PONA RADICALS"),
    (0xF1CA0, 0xF1CFF, "YAPIRI"),
    (0xF2000, 0xF267F, "SADALIAN"),
    (0xF28A0, 0xF28DF, "ZBALERMORNA"),]


def title(name):
    """TENGWAR -> Tengwar, D'NI -> D'ni, GLAITHA-A -> Glaitha-A."""
    return re.sub(r"[^\s-]+", lambda word: word[0][0].upper() + word[0][1:].lower(), name)


def key(name):
    """Compares names across sources: RØZHXH and KAZAT ʔAKKOROU match Rozhxh and Kazat Akkorou."""
    folded = unicodedata.normalize("NFKD", name.lower().replace("ø", "o"))
    return "".join(c for c in folded if c.isascii() and c.isalnum())


def private_use(point):
    return 0xE000 <= point <= 0xF8FF or 0xF0000 <= point <= 0xFFFFD or 0x100000 <= point <= 0x10FFFD


def main(folder):
    folder = Path(folder)
    old_blocks = []
    for line in (folder / "Blocks.txt").read_text(encoding="utf-8").splitlines():
        match = re.match(r"([0-9A-F]+)\.\.([0-9A-F]+); (.+)$", line)
        if match:
            old_blocks.append((int(match[1], 16), int(match[2], 16), match[3].strip()))
    for start, end, name in BLOCKS:
        assert start <= end and private_use(start) and private_use(end), name
    assert all(a[1] < b[0] for a, b in zip(BLOCKS, BLOCKS[1:])), "blocks must be sorted and disjoint"

    def current(point):
        return next((name for start, end, name in BLOCKS if start <= point <= end), None)

    def previous(point):
        return next((name for start, end, name in old_blocks if start <= point <= end), None)

    sections, aliases, section, last = {}, {}, None, None
    for line in (folder / "NamesList.txt").read_text(encoding="utf-8").splitlines():
        if line.startswith("@@"):
            section = None
        elif line.startswith("@"):
            section = line.lstrip("@").strip() or None
        elif line.startswith("\t= "):
            if last is not None:
                aliases.setdefault(last, []).append(line[3:].strip())
        elif re.match(r"[0-9A-F]{4,6}\t", line):
            last = int(line.split("\t")[0], 16)
            if section:
                sections[last] = section

    rows, dropped = [], 0
    for line in (folder / "UnicodeData.txt").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        f = line.split(";")
        assert len(f) == 15, line
        point = int(f[0], 16)
        block, old = current(point), previous(point)
        if not private_use(point) or block is None or old is None or key(block) != key(old):
            dropped += 1
            continue
        numeric_type = "Decimal" if f[6] else "Digit" if f[7] else "Numeric" if f[8] else ""
        fields = [f[0], f[1], f[2], f[3], f[4], f[5], numeric_type, f[8] or f[7] or f[6],
                  f[12], f[13], f[14], sections.get(point, ""), "|".join(aliases.get(point, []))]
        assert all("\t" not in field and "\n" not in field for field in fields), line
        rows.append("\t".join(fields))

    out = [
        "# Under-ConScript Unicode Registry, from https://www.kreativekorp.com/ucsur/",
        "# Copyright (c) Kreative Software. Built by Scripts/build_ucsur.py.",
        "# @start\\tend\\tblock, then code point, name, category, combining class, bidi class,",
        "# decomposition, numeric type and value, upper, lower, title, section, aliases.",
    ]
    out += ["@%04X\t%04X\t%s" % (start, end, title(name)) for start, end, name in BLOCKS]
    out += rows
    target = Path(__file__).resolve().parent.parent / "Shared" / "Resources" / "UCSUR.txt"
    target.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{len(BLOCKS)} blocks, {len(rows)} characters, {dropped} reassigned left out -> {target}")


if __name__ == "__main__":
    main(sys.argv[1])
