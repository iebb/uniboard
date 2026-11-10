# Bundled Google Fonts catalog

The containing app uses an offline catalog from the public [`google/fonts`](https://github.com/google/fonts) repository. No runtime catalog request, API key, HTML scrape, preview-triggered font fetch, or keyboard catalog resource is needed. Family-name search is entirely local. The catalog is not a character-coverage database and does not prove iOS registration or shaping support.

## Source and reproducibility

Pinned commit: `e7db6ca603fd4862010383ff17ffd6cc4ffac1c0`, resolved from `GET https://api.github.com/repos/google/fonts/commits/main`. Snapshot date is the commit's UTC committer date, **2026-10-23**, not a claim of device verification.

Generator sources:
- GitHub commit API and recursive Git tree API at that exact commit; truncation is a fatal error.
- Every `METADATA.pb` beneath `ofl`, `apache`, and `ufl` in that tree (2,040 families), plus all 25 additional family directories containing font binaries but no `METADATA.pb`. The latter use actual binary family/style names and are enumerated in `missingFamilyMetadata`. Protobuf text parsing uses a deliberately minimal descriptor for family/font fields and ignores unrelated metadata fields, not font entries.
- Every file referenced by those family records **and every additional TTF/OTF binary in each family directory**, fetched from `https://raw.githubusercontent.com/google/fonts/<commit>/<repositoryPath>`.
- Full adjacent `OFL.txt`, `LICENSE.txt`, `UFL.txt` or `LICENCE.txt` license records, retaining copyright notices. License SHA-256 covers the exact UTF-8 file bytes, including any BOM.

```sh
python3 -m venv /tmp/google-font-catalog-venv
/tmp/google-font-catalog-venv/bin/pip install fonttools==4.67.0 protobuf==7.36.2 requests==2.34.2
/tmp/google-font-catalog-venv/bin/python Scripts/generate-google-font-catalog.py \
  --commit e7db6ca603fd4862010383ff17ffd6cc4ffac1c0 \
  --cache /tmp/uniboard-google-fonts --workers 12
/tmp/google-font-catalog-venv/bin/python -m unittest discover -s Scripts -p test_google_font_catalog.py
```

Run from repository root. To refresh intentionally, use `--commit main`, inspect `coverage.json`, update `GoogleFontCatalog.trustedRepositoryCommit` and the pinned test count/source documentation, then test the resulting app. Do not silently accept arbitrary catalog pins. The script fails rather than writing a partial result when a declared font file is missing or downloading fails. Missing upstream license notices are reported explicitly and disable the affected file downloads without removing families. The script permits 1–24 concurrent retrievals; default 12. Git blob SHA-1 **and** tree byte size verify each cached/downloaded source against the pinned tree; the app's SHA-256 is independently calculated over the actual binary, never synthesized from Git blob SHA-1. All temporary upstream bytes remain under `/tmp`; no fonts are bundled by this feature. A refresh needs several GB of temporary disk/network traffic.

## Scope and metadata

`App/Resources/GoogleFonts/catalog.json` contains all 2,065 family directories (2,040 metadata-defined and 25 binary-derived), not a curated sample. A font file is represented once by its repository path; variable named instances share that file ID and include their actual `fvar` coordinates. Style names and PostScript identities come from the font's `name`/`fvar` tables. A named instance without a separate PostScript name uses the base face identity plus coordinates. Expected downloadable face identities use actual binary name ID 6. Static faces use typographic subfamily name ID 17, falling back to name ID 2.

`coverage.json` records exact family/style/file/license counts, total font bytes, unavailable files, missing face metadata, and repository font files not referenced by any family metadata. These additional files (for example alternate/static production artifacts) are also included, with styles derived from their own binary tables. `repositoryFontsNotIncluded` must be empty. Completeness means every font-containing family directory and every font binary at the pin, not all historical/deleted families or the live Google Fonts website inventory.

Files above 40 MiB remain in the catalog with an explicit unavailable reason. Ten families at this pin have no adjacent license notice: `apache/jsmathcmbx10`, `apache/jsmathcmex10`, `apache/jsmathcmmi10`, `apache/jsmathcmr10`, `apache/jsmathcmsy10`, `apache/jsmathcmti10`, `ofl/kumaroneoutline`, `ofl/mplusrounded1c`, `ofl/playwritenzbasicguides`, and `ofl/tinos`. Their license ID lists are empty and downloads are unavailable; no replacement notice is invented. See `missingLicenseFamilies` in the coverage report. Unsupported format or failed face-metadata inspection also remains explicit rather than dropping its family. Successful fontTools inspection is **not** a guarantee Core Text accepts a file: download/registration validation remains required. No script/subset metadata is interpreted as glyph coverage.

## Swift boundary

`App/GoogleFontCatalog.swift` provides public concrete `Codable`, `Sendable` value models and fixture initializers. `GoogleFontCatalog.load(bundle:)` loads only a bundled resource (`GoogleFonts/catalog.json`, with flattened bundle fallback). Validation rejects unknown schema/pin, duplicate or empty identifiers, unresolved style/license references, unsafe paths, invalid sizes/digests, tampered license notices, malformed variations, and oversized files without reasons. `downloadURL(for:)` accepts only a matching available record from the validated catalog and derives its HTTPS host/commit from app code, never from catalog-controlled URL text. Actual networking and downloaded-font storage are separate responsibilities.

Include this directory in the **app target only**, not Shared resources or the keyboard extension. Native tests in `Tests/GoogleFontCatalogTests.swift` need the app-hosted test target; they are conditional outside UIKit. Generator unit/coverage tests run locally without Apple SDKs. Device compatibility, real downloads, Core Text registration and keyboard availability must be tested separately; generation does not establish those guarantees.

## Generated coverage (2026-10-23 pin)

| Measure | Verified result |
|---|---:|
| Upstream METADATA.pb family records | 2,040 |
| Additional font-family directories without METADATA.pb | 25 |
| Bundled families | 2,065 |
| Binary-derived styles / named instances | 9,293 |
| Font files, each with actual SHA-256 and byte size | 3,912 |
| Total font bytes inspected (not bundled) | 2,469,954,256 |
| Full license file records | 2,058 |
| Repository font binaries omitted | **0** |
| Missing binary face metadata | **0** |
| Families with missing license notice | 10 |
| Files unavailable for missing license | 19 |
| Files unavailable above 40 MiB | 4 |
| Total unavailable files retained | 23 |
| Compact bundled catalog JSON bytes | 13,095,643 |

There are 131 binaries not explicitly referenced by METADATA.pb: 47 in the 25 directories without metadata and 84 additional binaries in metadata-defined directories. All are included. The four oversized files are Chiron GoRound TC, Chiron Sung HK upright and italic, and Noto Color Emoji Compat Test. Exact paths are in `coverage.json`.

Catalog SHA-256: `9df0c07fd65ce8408c7945d438cc8aa64b1d09c362ef9022b670eedefd1f6804`.

Local validation: `python -m unittest discover -s Scripts -p test_google_font_catalog.py` under the pinned temporary venv completed **6 tests, 0 failures, 0 skips**. Tests cover protobuf text escaping/unknown metadata, Git blob identity, safe paths, malformed font rejection, variable named-instance extraction from a real generated fixture font, and complete bundled coverage/license SHA-256s. Native app tests are supplied but not run by the catalog subtask; app build/registration evidence belongs to the parent integration work.

## Compact shared equivalence resource (1.4)

The preceding generated coverage table/hash describe the original schema-1 catalog.
The current schema-2 catalog, with accepted pinned single-style instances, is
**14,341,398 bytes**, SHA-256
`9cd08fbab58d01db6c4b390c31815b2d53ce9da5d266841487f132d6a0b52b12`.
The compact-resource change does not rewrite that catalog or `coverage.json`.

`App/Resources/GoogleFonts/equivalences.json` is an identity-only, schema-compatible
projection for `FontCatalogEquivalenceIndex`'s unchanged decoder. It contains
`schemaVersion: 2`, the source `repositoryCommit`, exact-source-byte
`catalogSHA256`, only referenced files (`id`, `sha256`), and only families with
accepted styles. Each style retains `fileID`, its **complete** `variationInstance`,
and `instance` (`path`, `sha256`). Display metadata, licenses, font bytes and
unaccepted styles are excluded. Source order and repeated styles are preserved;
5,439 styles reference 5,437 unique static paths, so deduplicating styles by path
would lose equivalences. There are **730 files, 552 families, 5,439 styles**, in
**1,565,640 bytes** (about 89% smaller than the full catalog), with an enforced
**2 MiB** generation/test budget.

Regenerate or verify entirely offline, from repository root, with **only the
Python standard library** (no requests, fontTools, protobuf, network or fonts):

```sh
python3 Scripts/google_font_equivalences.py --help
python3 Scripts/google_font_equivalences.py
python3 Scripts/google_font_equivalences.py --check
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
```

`--catalog PATH` and `--output PATH` select explicit files. `--check` writes
nothing and fails on a missing resource, stale source digest, changed projection
or nondeterministic bytes. The normal catalog generator and `--augment-instances`
both emit the companion via their shared `write_catalog`. Default schema-1
(no instances) generation remains supported and produces a schema-2 companion
with empty files/families. Generation preserves any syntactically valid source
commit, without granting runtime trust to new pins: the shared Swift decoder
still accepts only its existing hardcoded trusted commit. Invalid accepted
instance hashes, unavailable/missing references, unsafe paths and incomplete or
malformed axes fail generation rather than silently removing relationships.

The provenance digest is an **offline consistency check**, not runtime digest
verification or an extra source of trust. Runtime equivalence loading now reads
**only `GoogleFonts/equivalences.json`**: `Bundle.main`, then (for an `.appex`)
the containing app bundle, as before. Missing/invalid resources fail closed to an
empty index; there is **no full-catalog fallback**. The resource folder already
belongs to the companion app only and automatically includes the new JSON;
no target membership changes or keyboard copies are required. The keyboard
reads this immutable containing-app resource without Full Access and no longer
opens/decodes the full font catalog for equivalences. The app's full catalog
search/download loader, storage, receipts, rules and font resolution behavior
are unchanged.

`Scripts/tests/test_google_font_equivalences.py` verifies exact independent
projection, source-byte provenance, deterministic emission/check mode, malformed
inputs, repeated identities and budget using routine dependency-free discovery.
`Tests/GoogleFontCatalogTests.swift` fails if the compact app resource is absent
and compares **both directions of every alias set** to the full projection,
including shared static identities. Native execution is coordinated separately
by the integration owner; this resource change does not itself establish device
registration or runtime memory measurements.
