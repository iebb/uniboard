# Language-input configuration

## Scope and defaults

`Shared/LanguageInputSettings.swift` stores semantic-input **preferences**, independently of the 512-byte Unicode edition snapshot. The app writes; the keyboard reads the same resolved configuration generation. `LanguageInputSettings(directory:)` accepts an injected directory provider, like `AutoCapitalizationSetting`, for coherent captures and isolated tests.

Schema 1 defaults are:

- `enabledModes = [.direct]`. Direct Typing is always enabled; Japanese Romaji, Mandarin Pinyin and Korean Romaja are opt-in.
- `englishSuggestions = false` and `englishAutocorrection = false`, **independent** switches (msg1032/1033). Neither implicitly changes the other or enables a mode.
- `packReferences = []`.

There is deliberately no persisted selected/active mode, unfinished composition, typed text, history, learned data, Traditional-output toggle, or custom-dictionary content. Custom collections use their separate store and dictionary export, not this configuration. Dataset-dependent output preferences can be added with an explicit later schema once supported data is verified.

Reading preferences or compiling/importing/exporting configuration never downloads, selects, installs, enables or deletes resources. A reference may name a disabled mode. A mode may be enabled without its resource being installed; consumers must report unavailable resources and preserve Direct Typing fallback. Pin validation does not assert that a real pack exists or that its license/data has been audited: the resource layer must match the complete identity against verified metadata before use.

## Shared snapshot

Filename: **`language-input-v1.json`**. Maximum complete UTF-8 payload: **8,192 bytes**, independently enforced during encoding and decoding. Example:

```json
{
  "schemaVersion": 1,
  "value": {
    "enabledModes": ["direct", "japaneseRomaji"],
    "englishSuggestions": false,
    "englishAutocorrection": false,
    "packReferences": [
      {
        "mode": "japaneseRomaji",
        "packID": "japanese.words",
        "version": "2026.10",
        "archiveSHA256": "abababababababababababababababababababababababababababababababab"
      }
    ]
  }
}
```

The example hash/ID are illustrative, **not** an audited downloadable pack.

All JSON fields shown are required; unknown fields, wrong types, unknown mode values and unsupported schema versions are refused. A missing, oversized, unreadable or invalid snapshot reads as the whole factory value, never a partially accepted preference set. No repair or write is performed by a read. `encode` returns nil for invalid values; `save` returns false for validation, unavailable storage or atomic-write failure and does not report false success. Saves do not create a missing generation directory. Regular-file reading and atomic replacement reuse `SharedConfigurationLocation`, including symlink refusal.

### Validation

- Mode strings are exactly `direct`, `japaneseRomaji`, `mandarinPinyin`, `koreanRomaja` from `LanguageInputMode` in `LanguageComposition.swift`.
- One to four enabled modes, in that canonical order, including Direct first. Duplicates, omissions of Direct, unknown modes and noncanonical order are invalid. `Value.setEnabled(_:for:)` maintains that order and refuses disabling Direct.
- At most eight pack references. The only fields are mode, pack ID, version and archive SHA-256. No URL, filesystem path, binary data or private/custom input field is allowed.
- Pack ID and version are canonical **1–128-byte ASCII** identifiers: letters/digits at both ends; letters/digits plus `.`, `_`, `-` internally. They are exact and case-sensitive (no case folding or trimming). Whitespace, separators for paths/URLs and non-ASCII text are rejected rather than normalized.
- Archive SHA-256 is exactly 64 lowercase hexadecimal digits.
- A pack ID occurs at most once in a snapshot, regardless of version/hash/mode. This rejects exact duplicates, contradictory pins and the same pack ID assigned to multiple modes. Multiple distinct pack IDs may serve one mode. A disabled-mode pin is not inconsistent with `enabledModes`.

## Portable TOML

The highest supported configuration schema is now **3**. Export still chooses the smallest necessary format:

1. Default language preferences and legacy layout content: schema **1**, exactly the existing field representation; no language section is emitted.
2. Default language preferences with explicit keyboard/page rows: schema **2**, preserving alignment, gaps and exact key/gesture payloads.
3. Any non-default language preference, including a pin alone or either English switch alone: schema **3**. Explicit rows retain their schema-2 semantics inside this file.

Schema 3 accepts the same existing keys as schema 2 and adds optional `[settings.language_input]`:

```toml
schema_version = 3

[settings.language_input]
enabled_modes = ["direct", "japaneseRomaji"]
english_suggestions = false
english_autocorrection = false

[[settings.language_input.pack_references]]
mode = "japaneseRomaji"
pack_id = "japanese.words"
version = "2026.10"
archive_sha256 = "abababababababababababababababababababababababababababababababab"
```

The optional section and optional preference keys default to factory values when absent. Each reference requires all four identity fields. An explicit empty `pack_references = []` is accepted; export omits an empty reference list. The same validation as the shared snapshot applies. No unknown keys or future versions are accepted. In schema **1 or 2**, `settings.language_input` is rejected, even when its content is the default: new keys cannot silently activate behavior in an older schema. Missing language sections in schemas 1–3 mean Direct-only factory preferences. Reading a schema-3 file with all-default content does not force subsequent export to schema 3.

All existing sections, missing-section reset semantics, retired/ignored setting handling, exact Unicode text and explicit empty-versus-unset gesture semantics remain unchanged. No broad fixture rewrites are needed to accept semantic changes to the old format.

## Configuration generations, review and Undo

`UniboardConfiguration.languageInput` belongs to **Settings**. Factory defaults, capture, compile and category matching include it. `compile()` emits a validated language snapshot along with the existing files. `SharedConfigurationLocation.fileLimits` and `ConfigurationSnapshotValidation.validators` include it, so staged apply verifies it and fingerprints notice edits.

Older generations legitimately have no language snapshot. Migration copies only files actually present; a generation's own manifest still governs completeness. Capture defaults the missing file. Undo copies the earlier file set, including absence of this snapshot, rather than enabling language behavior or fetching resources. Custom words/resources and transient app preferences remain outside these generations.

Review Import's existing Settings diff now lists readable enabled-mode changes, separate English Suggestions/English Autocorrection changes, and each added/removed/changed/reordered pinned identity. Changed pins include mode, ID, version and full hash; no typed or custom-dictionary content is shown. Existing review and one-step configuration Undo are reused, not replaced.

### Containing-app integration handoff

The parent integration must register the new source/test files in Package.swift/project manifests as appropriate. `App/ConfigurationFile.swift`'s existing post-apply/post-Undo refresh path must reload `LanguageInputSettings` from the newly resolved generation (and publish it to any preference owner); otherwise already-open consumers could retain pre-import preferences. The keyboard's generation-refresh path must likewise reload this snapshot, without adopting any active mode from disk. Configuration import must not call resource download/enable/select code. No UI work is included here; final UI integration remains pending.

The existing `ConfigurationCodecTests.testCaptureReadsCompiledFilesAndFallsBackToDefaults` hard-codes the old compiled filename set. Its narrow filename-set expectation needs the new `LanguageInputSettings.filename`; the old unsupported-version test at `ConfigurationCodecTests.swift:319` must use schema 4 rather than the now-supported schema 3. `SharedConfigurationLocationTests.payloads` explicitly builds a complete apply payload and needs a default language snapshot. These are bounded format/registration contract updates, not permission to weaken legacy assertions. Other shared-location tests should use `snapshotFiles`/`fileLimits` or include this new file in any explicit complete-generation fixtures.

## Focused verification

`Tests/LanguageInputSettingsTests.swift` covers defaults and independent English switches, canonical mode mutation, bounded snapshot round trips and strict rejection, atomic-save failures, pack identities/hashes and mode conflicts, compile/capture/Settings matching, schemas 1/2/3 and dynamic export, exact explicit rows/gesture preservation, readable review diffs, and import/Undo with an older generation missing the new file.

Swift/XCTest runtime execution is delegated to the parent's remote core-test run; this workspace has no Swift executable. No Simulator, native UI, physical-device, Full Access or dataset-quality claim follows from source inspection or these configuration tests.
