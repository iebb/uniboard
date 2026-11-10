# Uniboard 1.5 — copy addendum, items 4–13

**Status: proposed implementation handoff, not verified features.** English UI copy only. This draft supplements `docs/language-input-copy-final.md` and `docs/copy-1.5/copy.md`; it does not change app code or settle other 1.5 items. No builds or Simulator checks were run.

Keep **Uniboard**, **Languages**, **My Words**, **Input Mode**, **Dictionary**, **Reading**, **Output**, **Weight**, **Direct Typing**, **Japanese — Romaji**, and **Mandarin Chinese — Pinyin**. Korean naming follows the separate 1.5 handoff. Downloading, enabling, selecting, saving words, and preparing keyboard choices are separate outcomes. Do not describe typing or language downloads as paid.

The current Full Access wording stays unchanged:

> **Full Access required**  
> Allow Full Access so the keyboard can read downloaded language files shared by the app. Your typing stays on this device. Direct Typing works without Full Access.

Do not use Full Access as a remedy for storage, network, damaged files, import validation, or inspection errors. Braced values below are runtime substitutions, not literal UI text. Localize numbers, byte units, and singular/plural forms. UI strings and behavior gates are deliberately separated.

## 4. Check storage before downloading

### User-facing copy

Retain the language-detail title and **Language Download** section, with **Download Size**, **Installed Size**, **Source**, and **License**. Add the storage information within that existing download flow:

| Element/state | Exact copy |
| --- | --- |
| Storage section | **Storage** |
| Estimated peak additional space | **Estimated Space Needed** / **{size}** |
| Estimate explanation | **Includes the download, installed files, and temporary space needed to prepare them.** |
| Measured capacity | **Available Storage** / **{size}** |
| Capacity unavailable | **Available Storage** / **Unavailable** |
| Requirement unavailable | **Estimated Space Needed** / **Size unavailable** |
| Check in progress | **Checking storage…** |
| Capacity unknown | **Couldn’t check available storage** / **Uniboard couldn’t check how much space is available. Preparing this download also needs temporary space.** |
| Requirement unknown | **Space needed is unavailable** / **Uniboard couldn’t determine how much space this download needs, including temporary space. Try again before downloading.** |
| Insufficient capacity | **Not enough storage** / **There isn’t enough storage to download and prepare these language files. Free some space and try again.** |
| Check passed | **Storage check passed** / **The last check found enough space for this estimate. Available storage can change before the download finishes.** |
| Storage failure after starting | **Not enough storage** / **The download couldn’t be prepared because storage ran out. Free some space and try again.** |

Controls: **Download**; **Try Again** to repeat a failed storage check; **Cancel** to leave a pre-download confirmation, if that confirmation exists. Once a download operation has started, retain **Cancel Download**. Do not add a storage-settings shortcut or a bypass action.

Accessible progress label: **Checking storage for {mode}**. Read each metadata label with its value; do not announce unavailable capacity as zero.

### Behavior gates — not UI text

- Check before the first network request of the explicit download. The estimate must account for peak simultaneous scratch files, downloaded sources/archive, extracted or compiled output, installation staging, and overhead. Retained old versions cannot be counted as space already freed. Avoid double-counting shared space or checking only the final payload size.
- Show a measured available-space value only for a successful, relevant-volume measurement. Unknown capacity is neither “enough” nor “not enough.” Never substitute a total disk size, cached guess, or zero for unavailable capacity.
- Block starting when capacity is known insufficient or the required-space estimate is unavailable. If implementation permits a download with unknown capacity, keep the unknown-state warning visible and make no sufficient-space claim. This draft does not introduce a “Download Anyway” override.
- A successful check is not a reservation or guarantee. Recheck when retrying after a storage failure. Retain existing catalog/installed-size verification gates.
- Append **Your current language download hasn’t changed.** to a failure only when an existing installation really was retained. Otherwise, if nothing was enabled, append **It hasn’t been enabled.**

## 5. Bounded retry during an explicit download

### User-facing copy

| State | Exact copy |
| --- | --- |
| Retry waiting | **Waiting to try again…** |
| Waiting explanation | **The download was interrupted. Uniboard will try again shortly.** |
| Retry starting | **Trying again…** |
| Retry count, when available | **Retry {current} of {maximum}** |
| All permitted attempts exhausted | **Download failed** / **The download couldn’t finish after several attempts. Check your connection and try again.** |
| Known offline failure | **Download failed** / **You’re offline. Connect to the internet and try again.** |
| Source still unavailable | **Download failed** / **The source couldn’t provide this download. Try again later.** |
| Cancellation requested | **Cancelling download…** |
| Cancellation complete | **Download cancelled** |
| Completed-cancellation helper | **Choose Download or Try Again when you want to start another download.** |

Controls: **Cancel Download** during the transfer and retry wait; **Try Again** after terminal failure. Keep **Downloading… {percent}%** only for measured transfer progress with a valid total; otherwise **Downloading…**.

Accessible retry value: **Retry {current} of {maximum}**. Announce a retry transition once, rather than repeatedly announcing unchanged status.

### Behavior gates — not UI text

- Automatic retries belong only to the download the person explicitly started. Use a finite implementation-owned retry count and bounded delay; the copy does not choose their values. “Several attempts” requires multiple attempts to have happened. Retry counts exclude the initial attempt.
- Retry only classified transient failures. Do not retry cancellation, invalid sources, disallowed redirects, verification/integrity failures, incompatible resources, or storage failures as if they were connection interruptions.
- Cancel must stop the current transfer and queued retry waits, and prevent further requests/publication from that operation. Show the completed cancellation message only after this is confirmed. Do not restart on screen reopening, app reopening, or a later connectivity change without a fresh explicit download action.
- Make no promise of resuming at a byte offset, preserving partial progress, or continuing in the background. A retry may start a file again. Progress must describe the actual attempt and not sum failed bytes into a misleading total.
- Preserve the conditional current-download/unenabled failure suffixes in item 4. Download completion still does not enable or select the mode.

## 6. Remove a damaged or incompatible download safely

### User-facing copy

| State | Title/status | Supporting copy |
| --- | --- | --- |
| Failed verification | **Download couldn’t be verified** | **These language files couldn’t be verified. Remove the download before downloading it again. Your words in My Words will be kept.** |
| Known incompatible resource | **Compatible download required** | **This download isn’t compatible with this version of Uniboard. Remove it before downloading compatible language files. Your words in My Words will be kept.** |
| Read access failed, cause not established | **Download can’t be read** | **Uniboard couldn’t read these language files. Try again. Your words in My Words haven’t been changed.** |

Removal confirmation:

- Title: **Remove this language download?**
- Body: **{mode} won’t be available until you download its resources again. Your words in My Words will be kept. Some files may remain until the keyboard stops using them.**
- Destructive action: **Remove Download**
- Secondary action: **Cancel**
- Working state: **Removing download…**
- Completed logical removal: **Download removed. Your words in My Words have been kept.**
- Deferred-cleanup detail, when known: **Some files are still in use. Storage will be freed after they can be removed.**
- Failure: **Couldn’t remove the language download. It may now be Off. Your words in My Words have been kept. Try again.**
- Changed-download conflict: **This language download changed. Review it in Languages and try again.**

After successful removal, retain **Not downloaded** and **Download**, subject to catalog availability. Accessible destructive-action label where the mode is otherwise ambiguous: **Remove download for {mode}**.

### Behavior gates — not UI text

- Offer removal for a safely identified damaged/incompatible installation, not only for an installation that resolves as ready. Do not equate temporary unreadability or missing permission with corruption.
- Removal must disable/deactivate the targeted download without deleting dictionaries, entries, or unrelated files. If resources serve multiple modes, list those mode names in the confirmation rather than implying only one is affected.
- Preserve concurrent-change checks and active reader leases. Physical cleanup can defer; “Download removed” means deactivated for future use, not proof that every byte is gone. Do not display a reclaimed-byte amount before actual reclamation.
- If safe identity/ownership cannot be established, show a removal error rather than forcing cleanup. Do not advise reinstalling Uniboard, which could risk custom words.
- A fresh download requires a separate user action. Offer it only when a compatible resource is actually available; do not imply that removing a download creates one.

## 7. Show real Mandarin preparation progress

### User-facing copy

Screen title remains **Mandarin Chinese — Pinyin**. Overall preparation status remains **Preparing language download…**. Use these phase labels when the worker actually reaches each phase:

| Actual work | Exact phase label |
| --- | --- |
| Verify downloaded inputs | **Checking downloaded files…** |
| Read and prepare the character-conversion mappings | **Preparing character conversions…** |
| Parse and prepare vocabulary records | **Preparing vocabulary…** |
| Finish writing and organizing the prepared vocabulary | **Finishing preparation…** |
| Validate the prepared language files | **Checking prepared language files…** |
| Install the validated result | **Installing language download…** |

Measured vocabulary counter: **Vocabulary rows processed: {count}**. If the worker also supplies an authoritative denominator for the same records: **Vocabulary rows processed: {count} of {total}**.

Preparation helper: **The files have downloaded. Uniboard is preparing them for use on this device.**

Failure: **Couldn’t prepare the language download** / **The language files couldn’t be prepared for use. Try again.** Apply the conditional preservation suffix from item 4.

Controls: **Cancel Download** while cancellation is supported; **Try Again** after failure. Final resource state: **Ready to use**. Existing completion helper: **Download ready. Enable Use in Keyboard when you want to use it.**

Accessible progress label: **Preparing Mandarin language files**; value: the actual phase and, when available, **{count} vocabulary rows processed**.

### Behavior gates — not UI text

- These labels map to actual work in `MandarinDictionaryCompiler` and the installation worker; expose real events before using the finer phases or counters. Without an event, keep the generic preparation status instead of advancing a timer-driven checklist.
- A row counter counts vocabulary records actually processed, not bytes, source line positions including headers, or final unique choices. Duplicate combination means processed rows and final entries can differ. Match any denominator to exactly the same population.
- No invented percentage, time remaining, or “almost done.” A completed transfer is not completed preparation. A completed row counter is not completed validation or installation.
- Cancellation must be honored by the worker, including checks around lengthy phases. Do not display a usable Cancel control after an irreversible completion boundary.
- Use **Ready to use** only after validated installation is published. Keep enabling, selection, and Full Access state separate.

## 8. Search readings and outputs from My Words

### User-facing copy

- Screen title: **My Words**
- Search field: **Search My Words**
- Search helper: **Search readings and outputs across your dictionaries.**
- Entry-results section: **Matching Entries**
- Result source: **Dictionary: {dictionary name}**
- Result mode: **Input Mode: {mode}**
- Bounded-results notice: **Showing the first {limit} matches. Narrow your search to find other entries.**
- No matches: **No matching entries** / **Try another reading or output.**
- No custom entries: **No custom words yet** / **Add an entry or import a dictionary.**
- Loading: **Loading My Words…**
- Read failure: **Couldn’t search My Words** / **Your dictionaries couldn’t be read. Try again.**

Controls: existing result navigation and **Edit Entry**; standard search cancellation; clear-field accessible label **Clear Search**. Use **Try Again** for a read failure. Preserve existing add/import actions rather than adding a separate search workflow.

Accessible result label: **Reading: {reading}. Output: {output}. Dictionary: {dictionary name}. Input Mode: {mode}.**

### Behavior gates — not UI text

- Search readings and outputs across the dictionaries in the top-level My Words scope, including dictionaries that are Off. Keep each result tied to its source dictionary and actual entry identity; equal text in separate dictionaries is not one result.
- If the existing dictionary-name/input-mode matches remain visible, keep them separate from **Matching Entries** under **Matching Dictionaries**. A name match must not masquerade as a reading/output match.
- Bound rendered results with deterministic ordering. Use the bounded-results notice only when more matches actually exist; do not claim an exhaustive total from a truncated search. Clearing search restores the ordinary dictionary view.
- The **My Words for This Mode** route remains mode-scoped. There, use **Search readings and outputs in dictionaries for this input mode.** instead of the all-dictionaries helper.
- Search does not enable dictionaries, change entries, or search downloadable vocabulary. Show a load/read error rather than a misleading “No matching entries” when the source could not be read. Do not echo custom content into diagnostics.

## 9. Sort the displayed entry list

### User-facing copy

- Menu/control: **Sort Entries**
- Options: **Original Order**, **Reading**, **Weight**
- Helper: **Changes only how entries are shown. Saved order and exports stay the same.**
- Original Order description: **Show entries in their saved order.**
- Reading description: **Sort by reading.**
- Weight description: **Show higher weights first.**
- Empty dictionary: **No entries yet** / **Add an entry to this dictionary.**
- No filtered matches: **No matching entries** / **Try another reading or output.**

Accessible label: **Sort Entries**; accessible value: the selected option. Expose the selected option as selected, not only as a visual checkmark.

### Behavior gates — not UI text

- This is a presentation choice within the existing entry list, not drag-reordering, a bulk edit, or a change to keyboard ranking.
- Original Order uses the saved sequence. Reading sorts consistently by reading; Weight sorts numerically from high to low. Use deterministic tie-breaks ending in the original position/stable identity. Document the comparator in implementation rather than promising an unsupported language-specific alphabetic order.
- Apply sorting to the full matching set before display bounds/pagination. Preserve original entry identities for edit, duplicate, and delete actions; a display position is not a storage position.
- No storage revision, entry mutation, export-order change, or Undo Import invalidation merely from choosing a sort option. Do not add saved sort preferences or additional sort directions in this copy handoff.

## 10. Duplicate Entry creates an unsaved draft

### User-facing copy

- Entry action: **Duplicate Entry**
- Editor title: **Duplicate Entry**
- Context: **Dictionary: {dictionary name}**
- Helper: **Start a new entry from this one. Nothing is saved until you tap Save.**
- Fields: **Reading**, **Output**, **Weight**; retain their existing helpers and validation copy.
- Primary: **Save**
- Secondary: **Cancel**
- Unchanged/duplicate validation: **This reading and output already exist in this dictionary. Edit the existing entry to change its weight.**
- Saving: **Saving entry…**
- Successful save announcement: **Saved**
- Save failure before any commit: **Couldn’t save this entry. Your words haven’t changed. Try again.**

For edited drafts, retain the existing discard confirmation: **Discard Changes?** / **Discard Changes** / **Keep Editing**. Accessible entry action: **Duplicate Entry**.

### Behavior gates — not UI text

- Open a new-entry draft in the same dictionary with the source reading, exact output, and weight prefilled. Opening it writes nothing, allocates no persistent entry, and leaves the original unchanged.
- Cancel/dismissal, including confirmed discard, writes nothing. Inspecting or validating the draft also writes nothing.
- Reject saving an unchanged duplicate. Changing only Weight is still a duplicate reading/output pair and uses the existing rejection. Use the existing reading-identity validation and exact-output comparison; do not normalize Output to test duplication.
- Apply normal entry limits and current-source conflict checks on Save. A failed save leaves the draft available for correction. If the words commit but preparing choices fails, use item 13 rather than claiming that nothing changed.

## 11. Inspect the draft Output without saving it

### User-facing copy

- Action beside Output: **Inspect Unicode Code Points**
- Panel title: **Inspect Text**
- Scope label: **Output**
- Helper: **This shows the output in your draft. Inspecting it doesn’t save or change your entry.**
- Section: **Code Points**
- Count: **1 code point** / **{count} code points**
- Code-point notation: **U+{hex}**, in the original sequence
- Empty: **No output to inspect** / **Enter output, then choose Inspect Unicode Code Points.**
- Failure: **Couldn’t inspect this text** / **Close and try again. Your draft hasn’t changed.**
- Close control: **Close**

Accessible action label: **Inspect output code points**. A code-point row can announce **Code point {position}: U+{hex}**, followed by its name only when that metadata is available. Missing metadata: **Not available**.

### Behavior gates — not UI text

- Inspect the current draft field, not the last saved entry, and do not require Save first. Freeze the original scalar sequence for the inspection. Closing returns to the unchanged draft.
- Show every scalar in logical order, including combining marks, variation selectors, joiners, and invisible characters. Do not use a rendered placeholder or normalized string as the inspected value. No silent trimming or replacement.
- Reuse the existing inspector's read-only behavior where appropriate; this item does not add normalization, repair, conversion, or saving actions. If existing normalization comparisons are shown, retain the neutral read-only wording in `docs/inspection-capitalization-copy.md` and never apply a form to the draft.
- Missing catalog metadata does not mean invalid output. Full Access is not an inspection prerequisite. Do not add clipboard/network access or inspect unrelated host text.

## 12. Full import review with search and pagination

### User-facing copy

- Screen title: **Review Dictionary Import**
- Intro: **This creates a separate dictionary. Your existing words won’t be replaced.**
- Existing fields: **Input Mode**, **Dictionary Name**, **Use in Keyboard**
- Full-file summary heading: **Entire File**
- Summary labels: **Valid Entries**, **Duplicate Entries**, **Combined Entries**, **Invalid Entries**
- Summary helper: **These counts cover the entire file, not just the entries shown below.**
- Entry section: **Preview**
- Search field: **Search entries**
- Search helper: **Search readings and outputs in this file.**
- Scope reminder: **Search and page changes only affect this review. They don’t select entries to import.**
- Unfiltered range: **Entries {first}–{last} of {total}**
- Filtered range: **Matches {first}–{last} of {totalMatches}**
- Paging controls: **Previous**, **Next**
- Page value: **Page {page} of {pages}**
- No search matches: **No matching entries** / **Try another reading or output. Searching doesn’t change what will be imported.**
- No importable content: **No entries to import** / **This file has no entries. Choose another UTF-8 .tsv or .txt file.**
- Problems section: **Problems**
- Problem range: **Problems {first}–{last} of {totalProblems}**
- Problem paging controls: **Previous Problems**, **Next Problems**
- Invalid-file helper: **Fix the invalid entries before importing. Your words haven’t changed.**
- Reviewing state: **Reviewing dictionary…**
- Importing state: **Importing dictionary…**

Primary remains **Import Dictionary**, never “Import Results,” “Import Page,” or “Import Selected.” Secondary remains **Cancel**. Retain **Choose File Again**, **Review Again**, **Dictionary File Format**, and **Inspect Unicode Code Points** where already offered.

Keep the existing count explanations:

> Valid Entries counts unique entries to add. Duplicate Entries counts repeated identical rows. Combined Entries counts additional distinct weights.
>
> Exact duplicates are kept once. Different outputs for the same reading remain separate choices.
>
> Combined Entries counts additional distinct weights for the same reading and exact output in this file. The highest weight is kept. These aren’t duplicates or invalid entries. Existing dictionaries aren’t changed.

Changed-source warning: **My Words changed. Review this file again before importing.**

Import failure title: **Couldn’t import dictionary**. Body, only before any commit: **Your words haven’t changed.** Success after the dictionary commits: **Dictionary imported**; if choices are not ready, accompany it with **Keyboard choices still need updating.** and item 13's recovery control.

Accessible search label: **Search import entries**. Paging labels: **Previous page of entries**, **Next page of entries**, **Previous page of problems**, **Next page of problems**. Announce the updated page/range after navigation. No “selected entries” announcement.

### Behavior gates — not UI text

- Replace the first-20 preview limitation with bounded pages over the full reviewed entry set. Search the full set before paging, not just the visible page. Keep all line problems reachable with original file line numbers; the current capped diagnostic sample is not a full review.
- File-level errors stay visible regardless of entry search or page. Summary counts always describe the full file under the existing duplicate/combination rules; result counts and page ranges describe the visible review subset. Do not turn repeated/combined rows back into extra imported entries.
- Keep counts consistent with the parser. Do not display a range such as “1–0”; use the relevant empty state. Reset or clamp the page after a query change. Disable Previous/Next at the real boundaries.
- Browsing pages, searching, inspecting, changing the draft name, or setting the review's Use in Keyboard toggle must not write words or settings. Cancel abandons the review without importing. Do not add checkboxes, row selection, selective import, or inline file editing.
- **Import Dictionary** applies the complete validated preview, not the filtered set. Any invalid row, blocking file issue, invalid name, unsupported mode, capacity limit, or stale review blocks import even when the affected row is hidden by search. Do not skip invalid rows or partially apply.
- Retain existing UTF-8/file-size/entry-count/scalar-count/forbidden-character/weight checks and their exact messages from `LanguageInputCopy.swift` and the finalized contract. Do not relax validation to make pagination work. Retain existing protected Undo Import behavior.
- Report source commit and keyboard-choice readiness separately. Do not emit an unqualified “everything ready” announcement when only the dictionary was saved.

## 13. Recover keyboard choices after reopening

### User-facing copy

Within **My Words**, use the section title **Keyboard Choices**.

| State | Exact copy |
| --- | --- |
| Checking saved choices | **Checking keyboard choices…** |
| Rebuild running | **Rebuilding keyboard choices…** |
| Rebuild helper | **Preparing choices from your saved words. Your dictionaries won’t change.** |
| Rebuild failed after reopening | **Couldn’t update keyboard choices** / **Your saved words couldn’t be prepared for the keyboard. Your dictionaries haven’t changed.** |
| A new edit/import committed, but preparation failed | **Your words were saved, but keyboard choices couldn’t be updated. Try updating them again.** |
| Prepared choices cannot be read | **Keyboard choices couldn’t be read. Your saved dictionaries haven’t been changed.** |
| Words changed during preparation | **My Words changed while choices were being prepared. Try updating them again.** |
| Verified completion | **Keyboard choices updated** |

Retry control: **Update Keyboard Choices**. Accessible progress label: **Rebuilding keyboard choices**. Announce completion only once, after verified success.

If the saved dictionaries themselves cannot be read, use their existing distinct messages instead of the rebuild helper:

- **Your saved dictionaries couldn’t be read. They haven’t been replaced.**
- **This version of Uniboard can’t read these saved dictionaries. They haven’t been replaced.**
- **Your saved dictionaries exceed the supported storage size. They haven’t been replaced.**

For those source-read errors, **Try Again** rereads the dictionaries; it is not permission to replace them with an empty collection.

### Behavior gates — not UI text

- On reopening/loading My Words, compare the current saved source with the prepared keyboard data. Missing or stale derived data triggers a visible rebuild from the authoritative saved words, even if a previous in-memory retry flag was lost.
- Checking/rebuilding never edits the source dictionaries, their enabled states, output sequences, or protected import history. A stale derived copy must not overwrite newer source words.
- Do heavy work off the UI thread. Publish only a fully validated result, guarded against newer changes. If the source changes during preparation, rebuild the current source or show the retry state; do not declare the older result current.
- A corrupt existing derived file is not equivalent to a missing file and does not authorize an unconditional overwrite. Only offer a rebuild that can complete through an implemented safe recovery path; otherwise retain the visible failure. Never replace unreadable source words with empty defaults to make rebuilding succeed.
- Keep failure and **Update Keyboard Choices** visible until a successful current rebuild. Disable repeated retry taps while work is running. Do not show a success checkmark merely because source loading, source saving, compilation, or a notification succeeded.
- **Keyboard choices updated** means validated current data is prepared and published, not that every keyboard session has already reloaded it or that a mode/dictionary is enabled. Full Access, downloaded-resource availability, and input-mode selection remain independent.

## Source review and integration boundaries

Reviewed `App/LanguageInputCopy.swift`, `App/LanguagesView.swift`, `App/LanguageManagementModel.swift`, `App/LanguagePackDownloader.swift`, `App/MyWordsView.swift`, `App/MyWordsModel.swift`, `App/LanguageInputEnvironment.swift`, `Shared/LanguagePackStore.swift`, `Shared/MandarinDictionaryCompiler.swift`, and `Shared/CustomInputDictionaryIndex.swift`, alongside the finalized copy and inspection handoffs.

Source observations, not runtime verification: the current top-level search matches dictionary names/modes; entry search is within a dictionary. Import preview currently shows at most 20 entries and a capped problem list. Mandarin preparation currently exposes a broad compiling state, not live row counters. Removal UI currently requires a ready installation. My Words retries preparation after mutation, but its load path does not itself compare saved and prepared revisions. These are implementation gates for the requested improvements, not claims that this draft has enabled them.

Only this draft file is changed by this handoff. Parent integration should keep user-visible strings separate from the behavior notes and verify every state before making release claims.
