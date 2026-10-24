# Uniboard 1.3.0 — Support and Privacy audit

Checked 24 October 2026 against the currently implemented source and live pages. This is an audit, not final-release certification. No pages or hosting were changed.

## Result
Both review URLs serve HTTP 200, but their content is not ready to describe 1.3.0 accurately.

- Support: https://uniboard-dxm.pages.dev/support/
- Privacy: https://docs.kitta.co/uniboard/

Main site source is `website/` in the imported project; it remains on Cloudflare Pages. The authoritative privacy page belongs to Kitta's separate docs site. Its repository/source has not been identified. `website/privacy/index.html` is not the public policy: `website/_redirects` redirects it to the external page. Do not edit that stale local page expecting the public policy to change.

## Required corrections

### Downloads
The current policy describes GitHub release-file downloads for existing packs only. Google Fonts downloads also fetch user-selected font files from the pinned `google/fonts` repository on `raw.githubusercontent.com`. The catalog is bundled and searched locally. The download is an explicit GET for a font file, not a transmission of typing or searches. The implementation uses an ephemeral session without cookies, credentials or cache and rejects redirects on this path. Existing pack paths use GitHub and its release CDN.

Explain that delivery hosts receive ordinary request information such as the requested file and network address. Do not invent third-party retention guarantees. Preserve the distinction between local font rendering and the receiving app's choice of font. Font files are not installed system-wide.

Evidence: `App/GoogleFontDownloadCoordinator.swift:10–43`, `App/GoogleFontCatalog.swift:140`, `Shared/UnicodeFontAssets.swift:75–119`.

### Local text inspection and image copying
Add local inspection of only the excerpt shown in the keyboard preview, not the whole document. The keyboard uses text context exposed by the host; do not claim it never reads surrounding text. Inspection freezes that excerpt, analyzes code points/grapheme clusters/UTF-16 counts and normalization locally, and clears the panel snapshot on closing. It does not send the excerpt to a server or automatically rewrite the host document.

Clipboard disclosure must cover explicit copying of preview text, code-point labels and rendered PNG images. Pictures preserve appearance but are not editable text and paste only where images are accepted. Clipboard writes are user-initiated; the audited implementation checks change counters rather than continuously reading clipboard contents.

Inspection and typing work without Full Access. Copy Text/Copy Code Points from the keyboard inspector and Copy Image are currently gated on Full Access. Add this to the permission explanation rather than claiming Full Access is only for favorite writes and haptics.

Evidence: `Keyboard/KeyboardViewController.swift:257–318,1031–1040`, `Shared/TextInspection.swift:81–88,217–247`, `Shared/KeyboardPreviewImageExport.swift:900–904`.

Important pending scope: the user has now requested copying each normalization result and UTF-8/UTF-16 representations (chat 489). This audit describes the current implementation; update the final clipboard/support wording once those changes are verified. Likewise, do not publish the movable cursor as complete before the final engineering handoff.

### Configuration import and export
Add that the user may save/share a TOML configuration file containing settings, editable layouts/pages/custom key text, favorites, font references/rules and Copy Image colors/scale. Favorites and custom text can be personal. Exports exclude typing history, scratchpad contents and font binaries. The chosen Files/share destination can store or cloud-sync the file under its own rules; this is not app-operated cloud sync.

Imports are validated and reviewed before confirmed replacement. Missing sections reset to defaults rather than merge. Imports do not download fonts automatically. Missing-font rules are kept with fallback. Prior configuration is stored locally for Undo; Undo also replaces changes made after the import. Keyboard-only colors and scale chosen without Full Access are not available to the app export and are excluded.

Evidence: `App/ConfigurationFile.swift:17–21,56–60,130–177`, `Shared/ConfigurationCodec.swift:50–160`, `App/ConfigurationImportModel.swift:94–163`, `Shared/SharedConfigurationLocation.swift:68–98,257+`, `Shared/KeyboardPreviewImageExport.swift:533–551`.

### On-device sharing and search
Replace Support's unqualified separate-favorites claim and Privacy's separate-custom-pages claim. App-authored pages and favorites reach the keyboard through local shared storage. Keyboard favorite changes write back with Full Access; without it they remain pending locally. Recents remain separate. This is not developer-operated cloud synchronization.

Support's draft-default and separately remembered edition wording is also outdated: current in-app help describes the latest release by default, two preceding releases plus a draft, with shared edition settings. Recheck exact catalog versions against the final build instead of hard-coding old dates.

The new search index is built from the bundled Unicode catalog and cached locally; it is not an index of typed text or query history. Avoid an absolute “no logging” promise: build timing/size metrics are logged locally, not search contents.

Evidence: `App/SetupView.swift:19,63–67`, `Keyboard/KeyboardViewController.swift:118–121`, `Shared/UnicodeSearchIndexStore.swift:1–65`, `App/UniboardApp.swift:74–76`.

### Keyboard instructions
Support still says the top-right backspace edits the query during search. This conflicts with the verified behavior reported in chat 119 (top backspace edits host text, lower backspace edits query). Update from the final verified key-routing implementation. Explain U-key search and hold-to-type without conflating search-key holds with long-press inspection of result tiles. Remove old Top Row / Number Row settings instructions wherever present; the number row is now editable within the keyboard layout.

## Release handoff
- Page availability: passed (both HTTP 200, rendered contents read).
- Content accuracy for 1.3.0: corrections required.
- Privacy source/deploy access: unresolved; source location required before editing the existing external page. Keep existing hosting, do not create a replacement policy elsewhere unasked.
- Support source available; deployment requires the existing Cloudflare Pages access, not AirHost.
- Final review must use the final 1.3.0 behavior, especially cursor handling, expanded inspection copy actions and font picker/download changes still being implemented.
- Apple’s privacy label is owned by @appstore; this audit does not change or certify it.
