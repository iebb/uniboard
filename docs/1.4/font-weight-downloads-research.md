# Uniboard 1.4: downloading single weights (research, 2026-10-24)

Project: /projects/ccadf99c-a2ff-4476-93be-fbe43192a9e7 (read-only). Network checks were run with curl and fontTools 4.67 in /tmp/wt.

## 1. How 1.3 gets Google Fonts today
- **Source:** the public GitHub repo google/fonts, pinned to commit `e7db6ca603fd…c1c0` (App/GoogleFontCatalog.swift:88). The app makes no Google Fonts API call and uses no key (docs/google-font-catalog.md:3).
- **Catalog:** a bundled offline file, `App/Resources/GoogleFonts/catalog.json` (13.1 MB): 2,065 families, 9,293 styles, 3,912 files. It is built by `Scripts/generate-google-font-catalog.py`. That script reads every METADATA.pb plus every TTF/OTF in each family directory (lines 99-117). It then builds styles from each binary:
  - variable files: one style per `fvar` named instance, with its coordinates (lines 59-63, 152-155);
  - static files: one style per file.
- **Download:** `https://raw.githubusercontent.com/google/fonts/<pin>/<repositoryPath>` (GoogleFontCatalog.swift:135-142; GoogleFontDownloadCoordinator.swift:10-17). The transport accepts only that host, rejects redirects and checks the pinned size (coordinator :28-34, :133). Storage checks the pinned SHA-256 and the PostScript name (name ID 6) (Shared/FontLibraryStorage.swift:258-262).
- **Tile → file:** each `GoogleFontStyle` has a `fileID` (GoogleFontCatalog.swift:34-48). `download(styleID:)` resolves the style to its file and downloads the **whole file** (coordinator :94-98, :117). It then records a `FontFaceRecord` for every style in that file, with `variations` set to the instance coordinates (coordinator :141-145).
- **Rendering:** the app and keyboard memory-map the file, build a CGFont, and select the instance with `kCTFontVariationAttribute` (Shared/FontRuleFaceLoader.swift:112-117). Nothing is registered through CTFontManager.
- **Grid:** `StyleGrid.make` builds sets (width/variant), rows (weights) and Normal/Italic cells (Shared/StyleGrid.swift:261-330).
  - The Width/Variant picker is FontFaceDetailView.swift:200-210.
  - Shared-file copy: `downloadFile(n)` "Download File (n Styles)", `sharedFile`, `removeShared` (StyleGrid.swift:24-37), used at FontFaceDetailView.swift:246-249, :282-285 and :165-166.
  - Rows already exist only for weights that have a cell in the set (StyleGrid.swift:322-327).
- **Limits:** 16 font files in the library (Shared/CustomFontStore.swift:23, checked at FontLibraryStorage.swift:269); 40 MiB per file.

## 2. Can a single weight be downloaded?
**GitHub google/fonts:** variable families usually ship only the `[axes].ttf` files. In the catalog, just 3 of 593 variable families also have static files:
- Inconsolata, under `static/`;
- Intel One Mono and Wix Madefor Text, at the top level.

There is **no** static Roboto. GitHub is therefore not a source of single weights for variable families.

**Google Fonts CSS2 API** (https://developers.google.com/fonts/docs/css2), checked live. The response format depends on the User-Agent:
- **No UA, wget, or any non-browser UA** (including a CFNetwork-style one): one `@font-face` per requested style. Each is a full-charset **static TTF** at fonts.gstatic.com, served `content-type: font/ttf`, `cache-control: max-age=31536000`, with no redirect.
- **iPhone Safari UA:** WOFF2 split into `unicode-range` script slices, so several files per weight. Not usable for this.
- **Old MSIE UA:** a `/l/font?kit=` URL (EOT-style).

Measured examples (static TTF vs the pinned variable file):

| Request | Static TTF | Variable file | Notes |
|---|---:|---:|---|
| `Roboto:wght@700` | 124,292 B | 488,584 B | PS `Roboto-Bold`; same 927-codepoint cmap; no fvar; same version 3.015 |
| `Roboto:ital,wdth,wght@1,75,700` | 128,708 B | 530,944 B | PS `RobotoCondensed-BoldItalic`, usWidthClass 3 |
| `Open+Sans:wdth,wght@75,700` | 121,704 B | 532,636 B | PS `OpenSansCondensed-Bold` |
| Inter 700 | 326,468 B | 876,576 B | |
| Oswald 700 | 86,416 B | 172,088 B | |
| Source Sans 3 700 | 234,640 B | 646,340 B | |
| Noto Sans JP 700 | 5,698,616 B | 9,589,900 B | full 16,732-codepoint cmap |

Other behaviour:
- A range such as `wght@100..900` with a TTF UA returns 9 static instances, not a variable file.
- The same URL returns the same bytes on repeat fetches.
- Old versioned URLs still resolve (`/s/roboto/v30/…ttf` returned 200).
- A weight outside the axis returns HTTP 400 with an HTML error page (e.g. Oswald 100).

Sample of 43 variable families, requesting every named weight: 40 fully OK. The rest:
- **Roboto Flex:** `wght@700` returns an empty stylesheet; a range returns only 400.
- **Recursive:** 1000 is missing.
- **Big Shoulders Stencil Text SC:** 400 "family not found". The family is in the repo but not served by the API.

**Version skew between the API and the repo:** `Lato:wght@700` from the API is Lato 1.104 "Western+Polish", 70 KB with 263 codepoints. The repo's Lato-Bold.ttf is 2.015, 657 KB with 2,164 codepoints. The API also rejects Lato 500 (400 error), although the repo has Medium. For static families, keep using the repo files.

**Developer API** (https://developers.google.com/fonts/docs/developer_api):
- `webfonts/v1` needs an API key (403 without one). A key shipped in the app can be extracted.
- The `files` map gives one gstatic TTF per variant ("static fonts files … instantiated at standard positions"; `capability=VF` returns variable files instead).
- Variants are only weight × italic, so there are no Condensed instances. CSS2 can return them through `wdth`.

**WOFF2 on iOS:** not tested on a device; no simulator was used.
- WebKit sets `HAVE_WOFF_SUPPORT 1` for all Cocoa platforms (Source/WTF/wtf/PlatformHave.h:887-889). WOFFFileFormat.cpp compiles its own WOFF/WOFF2 decoder only `#if !HAVE(WOFF_SUPPORT)`. So on Apple platforms WebKit leaves WOFF2 decoding to the system font parser (FPFontCreateFontsFromData). That suggests CoreText accepts WOFF2 data, but it is undocumented and unverified for `CGFont(provider)`.
- Either way, the app rejects anything that isn't sfnt (`00010000`/`OTTO`/`true`): FontLibraryStorage.swift:260 and FontRuleFaceLoader.swift:114 (`isSingleFaceSFNT`).
- TTF is available by sending a non-browser UA, so don't use WOFF2.

**Terms and licence:**
- The API is covered by the Google APIs ToS (https://developers.google.com/fonts/terms → https://developers.google.com/terms).
- The fonts stay under their OFL/Apache/UFL licences. The gstatic instances are Google's own builds of the same family, so the licence text from the catalog still applies.
- Do **not** make our own instances with fontTools for families with an OFL Reserved Font Name: a renamed "Modified Version" problem.
- gstatic responses carry no licence or receipt, so the app must keep supplying the licence from the catalog.
- Privacy: requests now go to Google (fonts.gstatic.com) as well as GitHub. The App Privacy and "Downloaded fonts" copy should say so (FAQ: https://fonts.google.com/faq#privacy).

## 3. Shared files vs one file per weight (from catalog.json at the pin)
- **Variable-only families: 590.** Their 784 `[axes].ttf` files cover 777 multi-style files. Variable file sizes: median 242 KB, p90 949 KB, max 51.9 MB.
- **Static-only families: 1,472.**
  - 1,078 have a single file with a single style.
  - 394 have one file per weight/style, e.g. Lato with 18 files. A single-weight download is honest by construction.
- **Both kinds: 3** (Inconsolata, Intel One Mono, Wix Madefor Text). The grid already prefers the variable file and files not under `/static/` (StyleGrid.swift:301-305).
- **Static files with several styles: 6** legacy `*VF*` beta files (DecovarAlpha-VF, LemonadaVFBeta…). Treat them as shared.
- **Condensed/Expanded columns** only appear for the 20 variable families with `fvar` named instances at `wdth≠100`: Roboto, Open Sans, Inconsolata, Encode Sans, Noto Sans Display, the Noto *UI families, and others. No static-only family has Condensed/Expanded names.
- About 131 files have a `wdth` axis. Archivo and Noto Sans, for example, have a `wdth` axis but no named condensed instances, so they show only a Normal column unless instances are synthesised.

**How to tell, honestly:**
- **Shared** = the number of styles with that `fileID` is greater than 1. `StyleGrid.styleCount(fileID:)` already gives this; the 1.3 copy uses it.
- **Metadata cues:** the file name contains `[`; the catalog style has `variationInstance`; METADATA.pb has `axes {}`. In METADATA.pb a variable family lists one `fonts{}` per file, e.g. Roboto lists weight 400 for both `Roboto[wdth,wght].ttf` and `Roboto-Italic[wdth,wght].ttf`. Do not read `fonts{}` entries as separate weight files.
- **Rule:** call a download "this weight" only when the bytes fetched contain only that face, i.e. a static file whose style count is 1, or a pinned gstatic instance. Otherwise label the whole file, e.g. "Downloads all 18 Roboto Normal styles (Condensed included) · 489 KB".

## 4. Recommendation for 1.4
**A. Ship now (UI only, no new source).**
- Columns = sets by width (Normal | Condensed) × slope; rows = the union of weights that exist.
- Static families get a per-cell "Download Bold · 657 KB" (Lato).
- Variable families get "Download File · 18 styles · 489 KB" plus a container or badge across the cells it covers. Never "Download Bold".
- Pros: no new host, no change to the pinned-hash trust model, offline catalog unchanged.
- Con: "download an individual weight" works only for static families.

**B. Recommended, as a generator change (1.4 or 1.4.x).** The generator also resolves single instances through CSS2 at catalog-build time:
- For each variable named instance at standard wght, wdth ∈ {75, 100} and ital ∈ {0, 1}, fetch the TTF with a fixed non-browser UA.
- Record the gstatic URL, bytes, SHA-256 and the actual name ID 6, in a new `instances` field on the style (schemaVersion 2).
- Accept an instance only if its cmap equals the repo variable file's cmap and its version matches (this catches Lato-style skew). Otherwise no single-weight option: fall back to the whole file (Roboto Flex, Recursive 1000, families the API doesn't serve).
- The URL is versioned and pinned like today; no runtime CSS or API call and no key.

Tradeoffs:
- **Size:** files are 25-60% the size of the variable file (Roboto Bold 124 KB vs 489 KB).
- **16-file cap:** every weight is one library slot. All of Roboto as statics would be 36 files, more than 16; the variable files need 2. Show the cost, e.g. "Download all weights (1 file, 489 KB)" next to "Download Bold (124 KB)".
- **Duplicates:** if a user later downloads the variable file, the statics duplicate it.
- **Keyboard memory:** files are mmapped (FontRuleFaceLoader.swift:112), so bytes count as clean, evictable address space, not dirty memory. Static files are smaller and skip gvar/avar work. Not measured; the 16-file cap matters more than the variable-vs-static difference.
- **Identity:** a static instance's PostScript name differs from the instance name inside the variable file (`RobotoCondensed-BoldItalic` vs the catalog's `Roboto-CondensedBoldItalic`; `OpenSansCondensed-Bold` vs `OpenSansRoman-CondensedBold`). It has no variations and a different SHA. This matters for duplicate hiding, the preview match and config references.
- **Cost:** catalog JSON grows by roughly 1-2 MB. A refresh downloads every instance once (GBs, as today).

Rejected:
- the Developer API (needs a key, no widths);
- a runtime CSS2 call (unpinned bytes, depends on UA sniffing);
- WOFF2 (sfnt checks, slices);
- instancing ourselves (RFN; no fontTools on iOS).

**Code that would change:**
- **Generator:** Scripts/generate-google-font-catalog.py (instance fetch and validation) and its tests.
- **Models:** App/GoogleFontCatalog.swift (schema 2; `GoogleFontFile` gains source `github|gstatic` or a style→instance file ID; `validate` and `safePath` for the gstatic path).
- **Download:** App/GoogleFontDownloadCoordinator.swift.
  - `GoogleFontURLPolicy` and `PinnedGoogleFontTransport` need to allow host `fonts.gstatic.com` with the pinned path.
  - `download(styleID:)` needs a choice of instance vs whole file.
  - The faces built at :141-145 must cover only the instance face, with no variations.
- **Storage:** Shared/FontLibraryStorage.swift:252-299. The receipt needs a source URL or kind.
- **Grid:** Shared/StyleGrid.swift.
  - Replace the width picker (`menuTitle`/`options`, :254, :320, :335) with width columns: `Row` gets cells per (width, italic) instead of normal/italic (:217-224).
  - New copy: e.g. `downloadWeight(name, size)`, `downloadAllInFile(n, size)`. Keep `sharedFile`/`removeShared`.
- **Views:** App/StyleGridView.swift (`columnGrid` :249, file strips :269/:338, layout for 4 columns and the stacked accessibility layout) and App/FontFaceDetailView.swift (drop the Picker :200-210; two download actions :258-289; remove/state keyed by the file actually downloaded).
- **Tests:** GoogleFontCatalogTests, GoogleFontDownloadCoordinatorTests, StyleGrid tests.
