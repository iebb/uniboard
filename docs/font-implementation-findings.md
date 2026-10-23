# Font implementation findings

23 Oct 2026, imported Uniboard baseline.

- Existing `App/FontPackDownloadsView.swift::InstalledFontPicker` uses UIFontPickerViewController with includeFaces; `CustomFontStore.addInstalled(postScriptName:)` persists selected installed faces. It does not enumerate every face for a per-character grid.
- `App/CharacterDetailView.swift` has one selected preview (or text/emoji pair), not a font comparison grid.
- `Shared/CustomFontStore.swift` validates imported TTF/OTF, deduplicates by hash, extracts scalar coverage, saves in App Group. Current limits: 16 custom entries, 40 MiB per file. Preserve these unless scope explicitly changes them.
- Existing pack downloading has cancellation, progress, partial retry, bounded concurrency and pinned release metadata. `UnicodeFontDownloadStore` verifies exact size/hash, approved HTTPS redirects, file signature and atomic receipt-backed installation. Do NOT loosen this validator for arbitrary Google URLs. Add a separate reviewed family/variant resolver and bounded downloader, retaining license metadata.
- `UnicodeFontSupport.missingCodePoints` allows system fallback runs. It alone cannot prove the requested face supports a character: the grid must check actual face attribution, including sequence shaping. Scalar coverage is only a prefilter. Outline-only checks wrongly reject spaces and color glyphs. `font(for:)` picks the first fallback, not all supporting faces.
- Current font test defect: unconditional U+0558 assertion assumed an on-demand preview font was bundled. Production behavior correctly can keep system font without a downloaded fallback. Parent moved stock-warning invariant to existing fixture-guarded fallback test; rerun pending. No production font selection change.

Google service endpoint/licensing/update strategy still needs official-source verification before implementation; no new backend is needed merely to download public font files. Preview-only wording and other apps' own rendering remain essential.
