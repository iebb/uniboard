# Uniboard 1.4 — widths and downloads copy

For Colo/Pluso/Ato, responding to msg670. 1.4 only; no effect on the 1.3 submission. Copy does not decide download source or automatic replacement; both remain product/engineering decisions.

## Names

Keep **Normal** / **Italic** group headers from 1.3. Use **Standard** for wdth 100, with **Condensed**, **Semi Condensed**, etc. for other widths. This distinguishes slope from width without renaming all existing groups. Accessible column label: **Standard width, Normal** / **Condensed width, Italic**. Keep the catalog's actual style names in face details; do not rename a face itself to Standard.

Keep **Variant** for non-width variants. No Width selector. Keep **No italic styles in this family.**

## Actions and scope

- True single-style file: **Download {name}**. A style name includes width, weight and italic where applicable.
- Shared-file action: **Download File ({n} Styles)**. Use this for the secondary whole-file action too; avoid “Download All” unless it truly includes every style of the stated family/group.
- Secondary shared-file caption: **Includes {n} styles in one file.** Add actual group/width coverage on a separate line when useful, e.g. **Normal styles in Standard and Condensed widths.**
- No single-style download available: **This style is available here in a file containing {n} styles. Downloading or removing the file affects them all.** “Here” avoids claiming no other source can offer the style separately.
- Progress, single: **Downloading {name}… {p}%**.
- Progress, shared: **Downloading file ({n} styles)… {p}%**.
- Removal action: **Remove Download**, with selected style/file scope explained in confirmation. Prefer the existing action over “Remove {name}”, which can imply removing the font entirely even when another retained file supplies it.
- Shared removal confirmation body: **This removes all {n} styles in this file from Uniboard. You can download it again later.** Use only if removal really removes their availability; if other retained files supply some, say **This removes the downloaded file. Styles available from other files will stay available.**
- Keep **1 file · {n} styles · {size}**. Count distinct usable styles consistently, not duplicate metadata entries.

## Capacity

Use the concrete file limit rather than introducing “font slots”:

**Room for {free} more font files. Each file counts once, whether it contains one style or several.**
Singular: **Room for 1 more font file. Each file counts once, whether it contains one style or several.**
Full: **All 16 font-file spaces are in use. Remove a font file here or in Font Downloads to make room.**
Keep the verified per-file size limit alongside this. If the capacity policy changes, update 16 to the actual limit. Do not imply 16 individual styles, 16 families, or storage bytes are the limit. Counts must include every source the storage policy counts.

## Replacement — only if approved and implemented safely

Do not ship replacement text or promise to free capacity until Ato settles that behavior.

- One old file: **Replaces the separate download for {name}.**
- Multiple named files: **Replaces the separate downloads for {names}.**
- Longer list: **Replaces {k} separate downloads.**
- If a confirmation is required: **Replace separate downloads?** / **The shared file will replace these separate downloads after it has been checked.** Show the exact affected list and accurate before/after file count.

Count replaced download files, not styles, when explaining capacity. Never silently remove user-imported copies or erase preferences just because file contents overlap; any such ownership change is outside copy approval.

## Accessibility

- Single-style file value: **Separate file, {size}**.
- Shared-file value: **File contains {n} styles**.
- File line: **{group} styles, 1 file, {n} styles, {size}**. Use **Shared styles file** if it crosses groups.
- Include selected trait; keep download state independent of selection.
- Do not call a font “Available in the app only” merely because keyboard support has not been checked. Retain **Keyboard Unverified** vs confirmed **App Only** from 1.3.

## Guardrails

No synthesized styles or nonexistent weight rows. Never label a whole-file download as an individual weight. Do not describe downloading as installing system-wide fonts. Source options A/B and cleanup policy remain outside this copy handoff.
