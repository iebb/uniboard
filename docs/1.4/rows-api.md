# Explicit rows data API (1.4)

Contract for renderer/editor integration. Data layer only; geometry/overflow remains a design decision. New explicit rows must never use ANSI/wide-iPad letter projections. Legacy values retain all existing projection behavior. Favorites remains dynamic and has no explicit rows/alignment controls.

## Shared types (in existing `Shared/SymbolPageLayout.swift`)

- `KeyboardRowAlignment: String, Codable, CaseIterable, Sendable`: `left`, `right`, `center`, `spaced` (physical edges). Spaced preserves cell/key widths, allocates remaining space between cells, singleton centered. No geometry implemented here.
- `KeyboardRowCell<Key: Codable & Equatable>`: `.key(Key)`, `.halfGap`, `.gap` (full gap). Codable object is either `{ "key": <payload> }` or `{ "gap": "half" | "full" }`, never both.
- `KeyboardRow<Key: Codable & Equatable>`: mutable `alignment`, `cells`; initializer `init(alignment: .left, cells: ...)`. Conditional Sendable. Ordered cells are authoritative.
- `SymbolBoard.Row = KeyboardRow<SymbolBoardKey>`; `MainKeyboardArrangement.Row = KeyboardRow<String>`.

## Model API

Both models expose `private(set) var explicitRows: [Row]?`, `isLegacy: Bool`, and `resolvedRows: [Row]`. `nil` means legacy; `[]` is an explicit empty static page. `resolvedRows` adapts legacy packing without mutating or converting the model. Main rows resolve with center alignment only as an adapter: legacy rendering is NOT equivalent to fixed-width explicit centered rows.

- `SymbolBoard(id:name:keys:layout:)` and `MainKeyboardArrangement(keys:layout:)` create legacy values as before.
- `SymbolBoard(id:name:rows:)` and `MainKeyboardArrangement(rows:)` create explicit values.
- `mutating setExplicitRows(_ rows: [Row]) -> Bool`: validates row structure before atomic adoption. Main semantic validation still requires `isValid(for:)` / snapshot validation; page payload validation remains in `SymbolPageRules` / store commit.
- `mutating convertToExplicitRows() -> Bool`: explicit user-edit boundary, resolves legacy packing and adopts nested rows. Never invoke on load/capture/Validate.
- `SymbolBoardStore.setExplicitRows(boardID:rows:) -> Bool`: validated persisted edit, refuses Favorites. Store methods continue to work with both representations.

`keys` and `layout` remain computed legacy projections for existing callers/renderers. In explicit mode there is NO second stored key list or slot string. Mutating projected keys refills the row key positions, removing deleted keys’ own positions (by stable ID/token) and appending excess keys to the last row while it has room (the existing ten-column add rule), otherwise to a new row inheriting the last row’s alignment; alignment of surviving rows is retained. Mutating projected layout rebuilds membership from the keys and applies existing alignments by row index (new rows default left for pages, center for main). Exact slot counts retain every typed gap, including gaps after the final key, rather than applying legacy last-key trimming. The internal `KeyboardRow.slots(keys:layout:alignment:)` helper performs that exact projection with one payload per key slot; explicit MainKeyboard digit restoration also uses it. These are compatibility adapters, not the entry point for new editors: use `setExplicitRows` for row insert/delete/split/join/reorder so alignment follows the intended row. No adapter changes explicit data back to legacy. Existing `rows`/`places` APIs remain projections.

## Serialization

Explicit models encode `rows` only, never redundant `keys`/`layout`. Legacy models encode original keys/layout without normalization. Decoders reject mixed forms and malformed explicit cells/rows; old forms remain accepted unchanged.

Envelopes: shared pages 1/2, local State 1/2/3, separate JSON PageFile 1/2, keyboard settings 1–5, TOML 1/2. New semantics require respectively 2/3/2/5/2; fully legacy values may retain earlier versions. Existing filenames and configuration-generation pointer schema do not change. JSON PageFile2 retains full nested key payload including stable IDs. Favorites never has rows in shared/local/exchange data.

TOML2 uses `row` arrays, each with `alignment` and `cell` arrays. Main key payload is `key = "{delete}"`; page key payload is a nested `key` table carrying id/text/variants/up/down. Example:

```toml
schema_version = 2
[[pages.page]]
id = "my-page"
name = "My Page"
[[pages.page.row]]
alignment = "right"
[[pages.page.row.cell]]
key = { id = "key-a", text = "a", variants = [], up = ["A"] }
[[pages.page.row.cell]]
gap = "half"
```

Main example cell: `key = "a"`; full gap: `gap = "full"`. All rows require explicit alignment and cells; no implicit wrapping. Legacy TOML uses existing keys/places or key/layout forms. Mixed representations and row semantics in schema1 fail validation.

## Integration and ownership

Types live in existing shared source files, already members of Package.swift, project.yml and imported Xcode project; no new source memberships required. Configuration capture preserves model representation; compile uses each version-aware store encoder, diff includes row alignment/membership, existing transaction/Undo machinery preserves payload bytes. UI/renderer/editor changes are intentionally not part of this work.

## Approved design limits / editor coordination (msg833)

`KeyboardRow<Key>.maximumRowUnits == 12`; `row.units` and `cell.units` count page keys/full gaps as 1, half gaps as 0.5, and semantic Main function tokens as 1.5. Explicit decoder, `setExplicitRows`, store commit and TOML Validate reject overlong explicit rows. TOML errors name the precise row path. `SymbolPageLayout.maximumRowUnits` remains **16** for all old formats and legacy intermediate edits. Never replace that parser limit globally.

Legacy repair: `resolvedRows` may contain >12 units; it is an adapter, not proof of explicit validity. An overlong legacy value cannot be converted until every row fits. While repairing it, use existing legacy keys/layout setters / `store.setLayout` and leave it legacy until the complete edit passes `setExplicitRows`. Moves/inserts must not lengthen an already overlong row; shortening/splitting is allowed (editor enforces operation intent). This avoids storing >12 under a new format or losing alignments. Alignment-only edits on an overlong legacy value must wait for repair rather than silently discarding alignment. Ordinary payload-only edits remain legacy.

New editor row operations use complete nested arrays: split copies source alignment to the new row; join keeps the upper row alignment; add-created overflow rows inherit the previous row alignment. Store add follows the existing last-row-until-ten-units rule; it does not wrap existing cells. The `spaced` API/raw value stays `spaced`; the UI label is **Spread**. Main editor/renderer must consult `isLegacy` before ANSI/wide-iPad projection; resolved Center is not permission to project explicit rows.

TOML width errors use the final Camo wording from `docs/symbols-row-alignment-copy.md`, followed by the exact parser row path. JSON row decode errors retain the indexed coding path.

Standalone JSON page import keeps the existing `importPages(_:) -> Int?` API and exposes `@Published private(set) var pageImportIssue: String?`. Overlong PageFile2 rows set the final named-page/row/path width error; failures adopt no pages. The UI may read this property instead of showing a generic import failure.
