# Uniboard 1.4 website disclosures: change notes, claim sources, open questions

Prepared 29 October 2026 by Leto. **Nothing here has been published or pushed.** The live site under `website/` was not edited.

- **Privacy draft (current target): `docs/website/privacy-1.4-draft.html`.** This is a full page copied from the live `website/privacy/index.html` (Cloudflare Pages port of bf658eb), with the 1.4 text merged in. Template, markup, classes, relative links, canonical `https://uniboard.ieb.app/privacy/`, the Cloudflare hosting section and the contact address are unchanged. New links: Google's privacy policy (for fonts.gstatic.com) and `../support/#languages`, in the Japanese and Mandarin typing section. The date is `PUBLISH DATE`.
- **Support draft: `docs/website/support-1.4-draft.html`.** This is a full page copied from the live `website/support/index.html`. Four new sections are inserted after "Type a search key without changing your query", and the five replacements listed below are merged in. Links to the policy remain `../privacy/`, and the set of links is identical to the live page.
- The live `website/privacy/index.html` and `website/support/index.html` were not edited. Their md5 checksums match the copies taken before drafting.
- Superseded but kept as is: the privacy repo branch `uniboard-1.4` (commit `fcd487fa0f465f7d93b5f39151d0f9a2efb1955e` on unpushed master `bf658eb`, not pushed). It holds the same 1.4 text for the old docs.kitta.co template.
- Authoritative facts: `/tmp/release-preflight-2026-10-29.md`, cited below as **PF:line**. This is source review, not a packet capture (PF:32). The handoff also says it is not a shipping-build approval (PF:3).
- Engineering follow-up: `/run/airbuild/team/state/team/website/.engine/downloads/6f8988cc-52b7-4768-b450-f983d4c3d3a5/privacy-four-facts-1.4.md`, cited as **4F:line**. It is a source-only audit, not a signed-build, packet-capture or physical-backup inspection (4F:3).
- Font facts: `docs/website/font-disclosures-1.4-draft.md` (**FD**) and `docs/1.4/font-network-disclosure.md` (**FN**).
- UI labels not given in PF were taken from app source in the current uncommitted working tree (**src**). PF:12 says no clean 1.4 commit exists, so every label must be checked again on the final build.

## What changed

### Privacy policy (`privacy-1.4-draft.html`; the same text is on the old-repo branch)
- Layout, CSS link, canonical, nav, footer, contact address, the Cloudflare Pages hosting section and all existing links are unchanged. I added paragraphs and two `<h2>` sections using the page's existing elements. I added one link: Google's privacy policy, for fonts.gstatic.com, as FD specifies.
- The date is now `<time datetime="PUBLISH DATE">PUBLISH DATE</time>`. This placeholder must be replaced at publication.
- Meta description: now covers Japanese/Mandarin typing and language downloads. "Core typing" became "Direct Typing".
- Intro: adds optional Japanese and Mandarin conversion on device.
- Summary card: adds "no … AI service", on-device conversion and "keyboard itself makes no network requests". "Core typing" became "Direct Typing". Delivery providers now cover language and font downloads.
- **New "Japanese and Mandarin typing"**: local conversion, Simplified Mandarin vocabulary, no network or AI, no Japanese learning, no saved unfinished input / active mode / typing history. Full Access is needed only to read files shared by the app and is not used to send typing. With Full Access off, only Direct Typing is offered.
- **New "Optional language downloads"**: user-initiated and made by the app, not the keyboard. Hosts are codeload.github.com (Japanese) and raw.githubusercontent.com (Mandarin). The OpenCC mapping files are bundled, not downloaded. Covers what GitHub receives, what requests do not contain, the session with no cookies / credentials / URL cache, possible platform metadata, no retention promise, size + SHA-256 check, and local Mandarin compilation.
- Data on your device: My Words dictionaries and language settings are stored locally.
- Font downloads: integrates FD. Covers the fonts.gstatic.com host, GitHub release delivery for packs, raw.githubusercontent.com for original/shared files, bundled catalog/metadata/licenses, the wider list of excluded request contents, session details, Google privacy link, and "validated as a font". The keyboard reads fonts without Full Access. The existing two-behaviour removal/backup paragraph (packs delete files and request backup exclusion; the Google/custom library retains bytes with no exclusion) is kept as is and is never applied universally.
- Configuration files: new paragraph on My Words import/export, possible personal text, and copies elsewhere not erased by in-app removal.
- Clipboard and permissions: Full Access now covers reading downloaded language files and is not used to send typing. "Typing, search and inspection" became "Direct Typing, search and inspection".
- Retention: "Exported files" became "Exported configuration and dictionary files".
- Your choices: decline language downloads and use Direct Typing. Revoking Full Access keeps Direct Typing, search and inspection, but downloaded languages need it. Users can remove My Words dictionaries.
- Not mentioned anywhere, per instruction: Korean, English suggestions and autocorrection. `grep -ci 'korean|autocorr|english'` returns 0.

### Support draft (full page)
New sections, inserted before "A character looks like a box or dotted circle": "Type Japanese and Mandarin" (#languages), "Full Access for downloaded languages" (#languages-full-access), "Choose what to insert" (#choices) and "Add your own words" (#my-words).

Live lines that 1.4 makes wrong, now replaced in the draft:
1. Setup step 3. Was: "You can leave Allow Full Access off for typing, offline search and text inspection. Clipboard actions in the keyboard need Full Access; see below." Now: "… off for Direct Typing, offline search and text inspection. Downloaded Japanese and Mandarin, and clipboard actions in the keyboard, need Full Access; see below."
2. Preview fonts, sentence 2. Was: "The Google Fonts catalog is searched locally; downloading a selected font fetches its file from Google's font repository on GitHub. Downloads need an internet connection." Now uses FD Support text: "The font catalog and name search run on your device. When you choose a download, Uniboard requests the selected font file from GitHub or, for available individual styles, Google's fonts.gstatic.com. Downloads need an internet connection. No account is needed, and your typing, inspected text, favorites and configuration are not sent with the font request." The existing two-behaviour removal paragraph is kept.
3. Pages, favorites and Full Access, last paragraph. Was: "… It is not required for typing, offline search, preview fonts or read-only text inspection." Now: "Full Access also lets the keyboard read downloaded Japanese and Mandarin language files, and enables … It is not required for Direct Typing, offline search, preview fonts or read-only text inspection."
4. Meta description (optional). Now: "Set up the Uniboard keyboard, search Unicode and emoji, type Japanese and Mandarin, add your own words, inspect missing glyphs, and get help from Kitta Ltd." This drops "choose release or draft data". Restore it if preferred.
5. Save or replace your configuration, export list. Was: "Exports include settings, layouts, pages, favorites, custom key text, font references and rules, and Copy Image options. Favorites and custom text may be personal: check the file before sharing. Typing history, scratchpad text and font files are not included." Now: "… font references and rules, enabled language modes, language preferences, references identifying language downloads, and Copy Image options. Favorites and custom key text may be personal: check the file before sharing. My Words, language dictionary files, typing history, scratchpad text and font files are not included. To keep My Words, use Export Dictionary." (4F:39)

Checked and still correct: the lead ("interface … in English" refers to UI language), search, emoji/edition, inspection, Copy Image, configuration, unavailable fields and Contact.

## Claim → source map

### Privacy policy
| Claim | Source |
|---|---|
| Optional Japanese and Mandarin conversion on device | PF:22, PF:23, PF:33 "conversion is local" |
| No accounts, analytics SDK or AI service | PF:38 "No new app account, backend, analytics or AI service"; existing policy for pre-1.4 state |
| Uniboard's keyboard code does not send typing to a server or initiate language downloads; the containing app performs downloads (replaces the earlier absolute "makes no network requests") | 4F:19, 4F:23 (suggested wording); PF:33 |
| Mandarin = Simplified Chinese vocabulary | PF:23 |
| Japanese conversion does not learn from typing | PF:33 "Japanese learning … disabled" |
| Language settings don't save unfinished input, active mode or typing history | PF:38 |
| Full Access needed only to read files shared by the app; not used to send typing | PF:34 "observed local-file requirement, NOT evidence of typing upload"; src LanguagesView.swift:37, :65 |
| Full Access off → Direct Typing only, works normally | PF:34 "Fresh extension OFF offers Direct Typing only … Direct Typing was actually checked with access OFF" |
| Not downloaded unless the user chooses Download in the app's Languages settings | PF:33 "Containing app performs static, pinned downloads"; src SetupView.swift:28 "Languages", LanguagesView.swift:217 "Download" |
| App, not keyboard, makes the requests; files are fixed | PF:33; src LanguagesView.swift:37 |
| Japanese from codeload.github.com | PF:36; src LanguagesView.swift:193; japanese-pack-v1.json allowedHosts `["codeload.github.com"]` |
| Two Mandarin vocabulary files from raw.githubusercontent.com | PF:37 (jichu + zi); src LanguagePackCatalog.swift:76 allowedHosts |
| OpenCC mapping files now part of the optional Mandarin download (same raw.githubusercontent.com host); license notices stay bundled | Pluso msg1262 optional-download-move-facts.md (planned; confirm on build53) |
| GitHub/providers receive ordinary request metadata, IP and selected resource | PF:35 |
| Requests are for static resource files; Uniboard does not attach typing, My Words entries or configuration; downloads are not anonymous | 4F:27, 4F:31; PF:33 (typed text); PF:35 and 4F:27 (metadata and IP visible, no anonymity promise) |
| Removing a language download keeps My Words; files in use by a keyboard may be retained until readers release them; no promise of immediate space recovery | 4F:7, 4F:15 |
| Language downloads are not excluded from backups, so backups may include them; no claim about any specific backup | 4F:11, 4F:15 |
| Mandarin dictionary built locally and kept with the download | 4F:11 (Mandarin.sqlite is part of the persistent installed payload); PF:37 |
| Configuration export can include enabled language modes, language preferences and references identifying language downloads; not the My Words collection or language dictionary files; favorites and custom key text included and may be personal | 4F:35, 4F:39. The specific preference keys are deliberately not named |
| Separate session; no cookies, credentials or URL cache; no account or analytics | PF:35, PF:38 |
| Platform request information may still be sent; no retention promise | PF:35 "do not promise zero provider metadata or a fixed retention period" |
| Checked against size and SHA-256 | PF:35 "exact decoded-size/SHA verification"; PF:36 (SHA256) |
| Conversion uses only local data; app compiles Mandarin locally | PF:33, PF:37 "App compiles the data locally" |
| My Words and language settings stored locally | PF:38 (no backend); src LanguageInputCopy.swift:37 "stored on this device" |
| Font hosts (raw.githubusercontent.com, fonts.gstatic.com, GitHub release delivery for packs) | PF:39; FD Privacy para 1; FN Requests |
| Font catalog, metadata and licenses bundled; name search local | FD; FN "Catalog browsing/search uses bundled data" |
| Font request excludes typing, inspected text, favorites, custom key text, configuration | FD para 2; FN |
| Font session has no cookies, credentials or URL cache; no app authentication or analytics; platform info may be sent | FD; FN |
| Google + GitHub receive request info; Google privacy link | FD para 2 and "Provider policies to link" |
| Size + SHA-256 + font validation; keyboard reads fonts without Full Access | FD para 3; FN |
| Packs delete files and request backup exclusion; Google/custom library retains bytes, no exclusion, no auto cleanup | PF:39; FD "Confirmed build 52 distinction"; already in policy at bf658eb (unchanged) |
| My Words export/import; personal text; copies elsewhere not erased by in-app removal | PF:38; PF:24; src MyWordsView.swift:50/103 (import), :323 (export) |
| Full Access paragraph (language files part) | PF:34 |
| Revoking Full Access: Direct Typing, search and inspection still work; languages need it | PF:34; existing policy (search/inspection) |

### Support draft
| Claim / label | Source |
|---|---|
| Romaji → Japanese, pinyin → Simplified Chinese words, on device | PF:22, PF:23, PF:33 |
| **Settings → Languages** | src ContentView.swift:35 (Settings tab), SetupView.swift:28 |
| **Japanese — Romaji**, **Mandarin Chinese — Pinyin** | src LanguageInputCopy.swift:7–8 |
| Shows download size, source and license before download | src LanguagesView.swift:188, :193, :195, :244, :247 |
| **Download**; app downloads and checks; keyboard never downloads | src LanguagesView.swift:217; PF:33, PF:35 |
| **Use in Keyboard**; downloading alone doesn't enable | src LanguagesView.swift:128, :37 "Downloads don't enable or select an input mode" |
| iOS **Settings → General → Keyboard → Keyboards → Uniboard → Allow Full Access** | iOS path as already used on the live Support page (setup steps) |
| Hold **Space**, choose **日本語** / **拼音** | src KeyboardViewController.swift:1264–1265 ("holding Space lists them"), :1292, :1651–1653 |
| `nihongo` → にほんご, 日本語; `nihao` → 你好 | PF:22, PF:23 |
| Traditional Chinese not available | PF:23; src LanguagesView.swift:149 |
| Full Access only to read shared files; not used to send typing; off → Direct Typing only | PF:34 |
| Typed spelling comes first in the strip; tap to insert exactly | PF:22 "exact raw literal … insertion"; **order is src only**: KeyboardConversionViews.swift:400–402 (literal before candidates). See Q8 |
| Tap a choice to insert | PF:22, PF:25 |
| Down arrow = **More Choices** | src KeyboardConversionViews.swift:348–355 (chevron.down, AX label "More Choices") |
| ✕ closes the list and keeps unfinished input | PF:25 "Close preserves unfinished input"; src KeyboardConversionViews.swift:605–612 (xmark, AX "Close Conversion Choices", hint "Keeps unfinished text without inserting it") |
| **Cancel Conversion** clears unfinished input; inserts nothing; field text unchanged | PF:25 "Cancel inserts nothing"; src KeyboardConversionViews.swift:660–662 (hint "Clears unfinished text without deleting text in the app") |
| My Words offered as choices; exact output incl. 👩🏽‍💻é | PF:24; src LanguageInputCopy.swift:35, :37 |
| **Settings → My Words**, **Add Dictionary**, **+ → New Dictionary**, choose input mode | src SetupView.swift:31, MyWordsView.swift:49, :101–105, :162 |
| **Add Entry (+)**, **Reading**, **Output** | src MyWordsView.swift:288, :315, :458–466 |
| Dictionary **Use in Keyboard**; new dictionaries start off; Japanese/Mandarin dictionaries need language enabled | PF:24 "Explicitly enabled"; src MyWordsView.swift:196, :273, :277 |
| **+ → Import Dictionary**; UTF-8 .tsv/.txt; reading TAB output; optional weight 0–10000; review; separate dictionary | PF:24 (TSV import/review/apply); src MyWordsView.swift:103, :547; LanguageInputCopy.swift:39, :43 |
| **Undo Import** removes last-import dictionary only while available; later edits kept; not typing undo | PF:24 "dictionary-import Undo, NOT typing Undo"; src MyWordsView.swift:78, :116–121, :662 |
| **⋯ → Export Dictionary**; personal text; removal doesn't erase saved copies | PF:24 (export/Files), PF:38; src MyWordsView.swift:323, :330 |
| Replacement 1 (setup step 3) | PF:34 |
| Replacement 2 (fonts) | FD Support para 1; PF:39 |
| Replacement 3 (Full Access paragraph) | PF:34 |
| "The app, not the keyboard, downloads and checks the files" | 4F:19, 4F:23; PF:33, PF:35 |
| **Remove Download** in Settings → Languages; My Words stays; files in use may be kept; space may not free immediately; downloads can be included in backups | 4F:7, 4F:11, 4F:15; label src LanguagesView.swift:168–172 |
| Replacement 5 (configuration export list): adds language modes, preferences and download references; excludes My Words and dictionary files; points to Export Dictionary | 4F:35, 4F:39; src MyWordsView.swift:323 |

## Follow-up update (engineering's four facts, 4F)
Privacy draft:
- Summary card and the Japanese and Mandarin section: the absolute "keyboard itself makes no network requests" became "Uniboard's keyboard code does not send your typing to a server or initiate language downloads; language downloads are performed by the containing Uniboard app."
- Added the link "For setup steps, see Type Japanese and Mandarin" pointing to `../support/#languages`.
- Downloads: "fixed files" became "static resource files". "Requests do not include your typing, My Words or configuration" became "Downloads are not anonymous. Uniboard does not attach your typing, My Words entries or configuration to these requests."
- New paragraph in Optional language downloads: removal keeps My Words; files in use may be retained; no promise of immediate space recovery; language downloads are not excluded from backups, which may include them. The Mandarin dictionary is noted as kept with the download.
- Configuration files: language modes, preferences and download references added; the My Words collection and language dictionary files are listed as excluded; favorites and custom key text are included and may be personal.
- Retention and Your choices: language removal and backup sentences added.

Support draft:
- "The keyboard never downloads them" became "The app, not the keyboard, downloads and checks the files".
- New removal paragraph (Remove Download) in Type Japanese and Mandarin.
- The configuration export list was updated (replacement 5).

Still absent: Korean, English suggestions and autocorrection, UITextChecker, and specific preference keys. `PUBLISH DATE` is kept.

## Closed questions
- Former Q1 and Q6 (language removal, storage, backups): answered by 4F:7–15 and drafted.
- Former Q3 (keyboard networking): answered by 4F:19–23; the wording is softened.
- Former Q4 (My Words and configuration in requests): answered by 4F:27–31.
- Former Q5 (configuration export contents): answered by 4F:35–39.
- Former Q12 (link from Privacy to Support): done, `../support/#languages`.

## Open questions (resolve before publishing)
1. **Full Access mechanism wording** (former Q2, not covered by 4F). The drafts say Full Access is needed "so the keyboard can read the language files shared by the app" and give no iOS-level reason. Confirm this is acceptable.
2. **Provider policy links.** Verify the Google privacy URL (FD asks for this) and confirm that GitHub's statement covers codeload.github.com. The font paragraph's aggregate-download-count sentence mentions GitHub only.
3. **"Typed spelling first"** is source-only (KeyboardConversionViews.swift:400–402) and claimed for the strip only. Confirm on the final build.
4. **UI labels come from an uncommitted tree** (PF:12). Recheck them on the final signed build: Settings → Languages, Use in Keyboard, Download, Remove Download, More Choices, ✕, Cancel Conversion, the My Words actions, and holding Space for the mode list.
5. **Release status and scope.** Not a shipping approval (PF:3, 4F:3). Korean and English scope are undecided; if English suggestions ship, the keyboard-networking text may need an OS-services note (4F:19). The CC BY-SA tokenizer question is open (PF:45–46).
6. **Old docs.kitta.co policy and the unpushed privacy-repo branch `uniboard-1.4`.** That branch does not have the 4F updates. Decide whether to retire it, redirect it or update it.
7. **Cleanup timing** (4F:7). Reclamation after the app is killed depends on a later cleanup, with no explicit next-launch hook. The drafts avoid any timing promise, so this is informational only.
