# 1.4 downloaded-font network/storage facts for website disclosure

Source-verified 2026-10-25 in current unfinished working tree; not a packet capture or final release verification.

## Requests

- User-requested single-style font instances: HTTPS `fonts.gstatic.com/s/<family>/v<n>/<name>.ttf`, pinned bundled paths. No query strings, userinfo, custom port, fragments, redirects or runtime CSS/Google Fonts API calls are accepted.
- Original/shared font files: HTTPS `raw.githubusercontent.com/google/fonts/<40-hex-commit>/<repository-path>`, also bundled/pinned. Licenses and catalog metadata are bundled; receipt records source URL/commit/hash/license locally.
- Download transport is app-only, ephemeral URLSession, explicitly no cookie storage/set cookies, credential storage or URL cache. Non-server-trust authentication challenges are refused. No app-specific authentication, account or analytics is added. No custom request headers/User-Agent are set here; do not claim no platform User-Agent is sent.
- The remote host sees the selected font resource and ordinary network request information (including IP); no typed/inspected host text, favorites, custom key payloads or configuration document is put in the font URL/body by this transport. Catalog browsing/search uses bundled data, not a runtime remote search request.
- At most two concurrent transfers, 40MiB maximum per file, expected size+SHA256+font/PostScript validation before publication. Library cap16 entries counts imported/installed/downloaded entries. No automatic eviction.

## Storage, reading, removal

- Files/receipts/license notices and manifest are local in the App Group's `CustomFonts-v1` library; keyboard reads local files without making font-download requests and without requiring Full Access for that reading.
- No cloud account or sync server added. This does not imply OS backups cannot include app data; no backup-exclusion behavior was verified.
- Removing a download removes that download's active manifest membership. Other files remain; an identical explicitly imported entry is retained. Existing configuration font-reference IDs are not silently rewritten.
- Important: removal does NOT immediately erase/reclaim binary bytes. Retired immutable files are deliberately retained so old app/keyboard snapshots can safely finish reading. There is currently no garbage collector. Do not promise that Remove immediately frees disk space or permanently deletes font bytes. This is established preexisting storage behavior, not introduced by the1.4 static instances.

## Source evidence

- `App/GoogleFontDownloadCoordinator.swift`: GoogleFontURLPolicy, PinnedGoogleFontTransport.fetch, download(styleID:scope:), remove(fileID:).
- `App/GoogleFontCatalog.swift`: instanceHost, safeInstancePath, bundled instance records.
- `Shared/CustomFontStore.swift`: App Group library root, maximumFonts/maximumBytes, remove.
- `Shared/FontLibraryStorage.swift`: immutable publication/manifest commit, removeGoogleFont.
- `docs/font-library-api.md`: explicitly documents retained retired binaries/no garbage collector.

Privacy/Support must disclose the new host before1.4 ships. This file hands implementation facts to the website owner; it does not authorize publishing unrelated changes or claim publication succeeded.
