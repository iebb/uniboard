# Submitted 1.3 build52 — font removal and backup facts

Checked 2026-10-25 against submitted source commit `d3f76b0f297479a3915cededbec4572dcf3bd651` using git show/grep, not current dirty1.4 files. This is source verification, not physical-device backup/restore or filesystem observation of the installed binary.

## Two separate stores already exist in build52

| Store / feature | Remote source | Removal | Backup behavior in source |
| --- | --- | --- | --- |
| Optional Unicode/emoji font packs (`UnicodeFontDownloadStore`, `PreviewFonts-v1`) | Existing pinned GitHub release assets: iebb/uniboard releases fonts-1.1-20261022 and fonts-1.1-20261022-complete; iebb/emojifonts release2026.10.22. Validated redirects are allowed by pack policy. | `UnicodeFontDownloadStore.remove` deletes receipt and font file with FileManager.removeItem, then updates revision. Bundled fonts remain. Errors can mean some files not removed; UI already warns. | prepareDirectory sets URLResourceValues.isExcludedFromBackup=true and throws if it cannot apply; install/updateRevision use this preparation. Thus the app explicitly requests pack-directory exclusion. No device backup/restore verification performed. |
| Google Fonts browser downloads and added custom fonts (`CustomFontStore`/`FontLibraryStorage`, `CustomFonts-v1`) | Google font repository files pinned to raw.githubusercontent.com/google/fonts/<commit>/<path>; imported font files originate from user selection, installed fonts are references | Remove changes active manifest membership; retired immutable binary bytes remain for safe snapshots. Google removal preserves an independently imported identical file. No garbage collector. | No backup-exclusion setting found for this library. Do not assert these files are excluded from backups. Actual OS backup behavior not measured. |

## Exact submitted-source evidence

- Shared/UnicodeFontAssets.swift: downloadBase/completionDownloadBase/emojiDownloadBase lines76–81, shared store root145–147, remove196–203, prepareDirectory227–233. Exclusion flag at231.
- App/FontPackDownloadsView.swift: font-pack remove203–213 iterates store.remove; custom remove315 calls CustomFontStore separately.
- Shared/CustomFontStore.swift: root CustomFonts-v1, remove109–114 explicitly retains bytes; save116–122 removes membership/receipts.
- Shared/FontLibraryStorage.swift: removeGoogleFont300–308 commits manifest only; commitManifest atomic JSON write does not unlink retired binary files.
- App/GoogleFontDownloadCoordinator.swift: submitted transport permits only pinned raw.githubusercontent.com shapes, ephemeral session with cookies/credentials/cache disabled. No fonts.gstatic.com in this build’s transport.
- `git grep -i isExcludedFromBackup/excludedFromBackup/backupKey` over submitted App/Shared/Keyboard found only the pack-directory flag above.

## Publication boundary

The old GitHub font packs remain separate from the Google/custom library. Correct1.3 wording by distinguishing these categories, not replacing every removal/backup claim with a universal statement. Pack removal/exclusion has direct source support; universal immediate deletion and universal backup exclusion do not.

`fonts.gstatic.com` single-style downloads are unfinished1.4 behavior only and must not be described as live in1.3. This verification does not authorize a new app submission or alter the Waiting for Review build.
