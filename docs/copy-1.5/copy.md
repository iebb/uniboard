# Uniboard 1.5 — copy for the twenty improvements

Status: revision 2.4 (landscape number-row note, msg1721; polish wording for the unconfirmed keyboard font status, msg1669), implementation handoff against Ato’s numbered brief (msg1572, Korean Space override msg1576, font-capacity correction msg1578) and Colo’s design parts 1–2 (msg1584, icon artwork msg1592), not a release claim. Uniboard keeps its name. The spelling guide and yearly-support terms depend on Natun’s open card (msg1574); neither choice is settled here. The Korean mode names and local hint copy below cover items 1–3; numbered sections 4–20 follow. Exact guide examples and engine/resource claims remain subject to focused verification.

Keep the existing `docs/language-input-copy-final.md` contract except where this file explicitly replaces a string. No code or localization catalog changed in this handoff.

## Items 1–3: Korean modes and local suggestions

## Consistent terms

| Concept | Exact term |
| --- | --- |
| Screen for modes and downloads | Languages |
| Conversion method | Input Mode |
| Optional downloaded resources | Language Download; Language Downloads for the section |
| Latin-letter Korean input | Korean — Romaja |
| Standard two-set Korean input | Korean — Two-Set Hangul |
| User-authored dictionaries | My Words |
| Instructions and supported spellings | Typing Guide |
| Recommendations from local language information | Suggested Languages |

Use **Romaja** consistently rather than alternating with Romanized. Explain it with **Roman letters** in prose. Use **Hangul** for the Korean writing system, **Two-Set Hangul** for this input method, and **한국어** as the native language label. Do not call a mechanical Hangul composition table a dictionary or describe either mode as Hanja conversion.

Existing Direct Typing, Japanese — Romaji, and Mandarin Chinese — Pinyin names remain unchanged. Storage identifiers are engineering-owned and need not change with the displayed Korean label.

## Korean mode rows and details

- Title: **Korean — Romaja**
- Native label: **한국어**
- Summary: **Type Korean with Roman letters using the spellings in the Typing Guide.**
- Title: **Korean — Two-Set Hangul**
- Native label: **한국어**
- Summary: **Type Korean with consonant and vowel keys in the standard two-set layout.**

Use the same names in Languages, the keyboard's mode picker, My Words when supported, configuration review, and the Typing Guide. Do not abbreviate both methods to an indistinguishable “Korean.” Compact labels, if required by design, are **Romaja** and **Two-Set Hangul**; accessible labels retain the full mode name.

Reuse existing actions **Download**, **Cancel Download**, **Try Again**, **Use in Keyboard**, **Select Input Mode**, **Remove Download**, and **Typing Guide**. Downloading, enabling, and selecting remain separate operations. Preserve the current session-only selection explanation; do not imply that selecting in the containing app changes the keyboard's active mode.

Common download footer:

**Language downloads are optional. Downloading doesn’t enable or select an input mode. Only the language you’re using is loaded by the keyboard.**

Only use the final sentence when the new Korean path has the same active-only loading guarantee as the existing modes.

Resource names depend on packaging, not a naming decision:

- Separate resources: **Korean Romaja Resources** and **Korean Two-Set Hangul Resources**.
- Shared resource: **Korean Input Resources**, with **Used by Korean — Romaja and Korean — Two-Set Hangul.**

Show actual download size, installed size, source, and license before Download. No estimated sizes or invented upstream license/source names. Do not promise “full Korean vocabulary,” predictions, or correction unless those features are implemented and verified.

## Download and access states

Reuse existing states **Not downloaded**, **Downloading… {percent}%**, **Checking download…**, **Ready to use**, and **Download failed**. Readiness is not enabled state, selected state, or Full Access permission.

Missing resource:

- Title: **Language download required**
- Body: **Download this language in Languages in the Uniboard app. You can still use Direct Typing.**

Retain the existing access wording for Korean only after its shared-file behavior is verified:

- Title: **Full Access required**
- Body: **Allow Full Access so the keyboard can read downloaded language files shared by the app. Your typing stays on this device. Direct Typing works without Full Access.**
- Compact recovery: **Allow Full Access to use downloaded languages. Direct Typing is still available.**

Do not request Full Access merely to display language suggestions. Do not place language loading, download, or hint controls inside Direct Typing.

Removal confirmation, for a resource used by one mode:

- Title: **Remove this language download?**
- Body: **{mode} won’t be available until you download its resources again. Your words in My Words will be kept.**
- Destructive action: **Remove Download**
- Cancel: **Cancel**

If one resource serves both Korean methods, replace the body with:

**Korean — Romaja and Korean — Two-Set Hangul won’t be available until you download their resources again. Your words in My Words will be kept.**

Do not promise immediate removal of files still in use. Remove the obsolete “Korean spelling is awaiting a decision” messages only as the corresponding mode and My Words support actually become available.

## Suggested Languages

Containing app only. These are recommendations, not a report of everything installed. The full language list remains visible. A Korean language hint must not select Romaja or Two-Set Hangul on the person's behalf. A Mandarin hint must not assert Simplified/Traditional preference unless the available identifier supports it.

- Section title: **Suggested Languages**
- Common explanation: **Suggested from language information on this device. Nothing downloads or switches automatically.**
- Active-keyboard source caption, only for a matching active input language: **Matches an active keyboard language.**
- Preferred-language-only source caption: **Matches a preferred language on this device.**
- Privacy helper: **The language hints used for these suggestions stay on this device.**
- Row action: **View Language** if a separate action is needed; the row otherwise opens the existing language detail. It must not immediately download or enable.

When Korean has one suggestion row leading to both methods:

- Title: **Korean**
- Detail: **Choose Romaja or Two-Set Hangul.**

If the suggestion is already downloaded, use its real download state; do not keep a Download call to action. A missing/disabled mode can still be enabled only by its existing user action.

For the Korean suggestion screen, title **Korean** and footer **Each input method is turned on separately.** This replaces the placeholder in Colo’s part 1. The suggestion section is hidden when there are no matches in that design; the following empty state is a fallback only if a visible suggestion view is added.

If design hides the section when there are no suggestions, no empty message is necessary. If a visible empty state is needed:

- Title: **No language suggestions**
- Body: **You can still choose a language from the full list.**

Use that for unavailable, empty, or nonmatching hints; it does not mean the person has no keyboards installed. Never say “Installed keyboards detected,” “Your keyboard packs,” “We know your language,” or “Recommended for your typing.” Do not infer from typed text or claim access to Apple’s dictionaries.

Technical/privacy constraint from Pluso’s audit: active input languages and preferred languages are different signals. Do not export either the values or derived suggestions, put them in diagnostic logs, or include them in remote requests. Source metadata downloads remain a separate, user-controlled action with their own host disclosures.

## Typing Guide and keyboard choices

- Screen title: **Typing Guide**
- Korean method headings: **Romaja** and **Two-Set Hangul**
- Romaja introduction: **Use the spellings below to enter Korean with Roman letters.**
- Two-set introduction: **Use consonant and vowel keys to build Hangul syllables.**

The examples, supported spellings, boundaries, shifted keys, syllable splitting, and Backspace behavior must come from the implemented engine and focused tests. No romanization or two-set examples are supplied as verified in this handoff. Do not name Revised Romanization or promise interchangeable spellings without proof.

Retain the flat candidate strip. For Romaja, where a literal choice is offered:

**To insert exactly what you typed without conversion, tap that spelling in the choices.**

The choice itself is the exact typed text, without a “Keep Roman Letters” label, extra quotes, or normalization. Accessible label remains **Insert exactly as typed: {text}**. Do not force this prose onto a two-set flow that does not offer a literal choice.

The selected Korean behavior is Uniboard’s explicit composition flow, not inline insertion into the host field. Ato’s msg1576 supersedes the original brief’s Space-only-confirm rule for both Korean modes. Guide copy after verification:

**Your Korean text appears in the choices before it is inserted. Press Space to insert it and add a space. Tap a choice to insert it without a space. Return confirms the text without adding a line break or sending it.**

While composing with choices visible:

- Space accessible label: **Confirm and insert space**. Hint: **Inserts the composed text followed by one space.**
- Return accessible label: **Confirm**. Hint: **Inserts the composed text without adding a line break or sending it.**
- Choice accessible label: **Insert {text}**. Literal Romaja choice retains **Insert exactly as typed: {text}**.

When the keyboard cannot show the choice strip and Space opens the choices panel instead, retain **Open Conversion Choices** as its accessible label, with **Opens choices for your unfinished text without inserting it.** Do not announce Confirm on a control that only opens the panel. Add the guide sentence **If the choices aren’t visible above the keys, press Space to open them, then tap the text to insert it.** This describes the unchanged compact fallback in Colo’s part 1, not a new confirmation rule.

Once idle, restore each key’s real action label/hint. Keep existing Finish Conversion / Keep Editing / Cancel Conversion transition names. Backspace-by-step examples still require the engine tests; do not claim stock iOS inline Hangul editing. Japanese and Mandarin keep their existing Space behavior. Romaja guide grammar remains pending Natun’s answer.

English autocorrection remains deferred and should not appear as a new 1.5 feature.

## My Words: engine-dependent gate

Korean Romaja My Words is required by item 2, with the final Reading format dependent on Natun’s spelling choice. Its helper after implementation is:

**Enter a supported romaja spelling from the Typing Guide.**

Do not reuse the Romaja helper for Two-Set Hangul. Colo’s part 1 uses a single composed-text choice and no My Words for two-set in 1.5: omit its My Words link and editor/import actions. Do not invent a physical-key Reading format. If explanatory text is needed, use **My Words is available for Korean — Romaja, not Two-Set Hangul.** Hiding unsupported Romaja actions during development does not complete item 2. Exact Output preservation remains unchanged.

## Handoff checks

Before treating this copy as shipped, Pluso/Colo should confirm:

1. Separate versus shared Korean resource packaging and each method's name across app/keyboard/configuration.
2. Actual Korean spelling/layout guide examples, candidate and commit behavior, and My Words support.
3. Korean Full Access behavior, active-only loading, and no implicit download/enable/switch.
4. Provenance-specific suggestion captions; empty hints leave the full catalog usable.
5. No hint or derived data leaves the device; required API declaration follows Pluso’s audit.

The remaining numbered improvements follow. Annual purchase terms and romaja grammar stay open; none of these strings claims that 1.5 has shipped.

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
- Section header while sorting by Reading: **Entries · By Reading**
- Section header while sorting by Weight: **Entries · By Weight**
- Section header in Original Order: **Entries**
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

## 14. Reset emoji size

Keep **Emoji Size**, **Smaller**, and **Larger**. Add **Automatic** beside those choices, selected when size follows the available width.

- Accessible label: **Automatic emoji size**
- Hint: **Fits emoji to the available width.**
- Optional helper: **Only the emoji size changes. Your categories, sorting and saved emoji stay the same.**

Use Automatic rather than a broad Reset action. This is app-only; it does not resize keyboard keys.

## 15. Hide repeated skin-tone variants while browsing

- Control/section: **Skin-Tone Variants**
- Choices: **All Variants** / **Fewer Variants**
- Default: **All Variants**
- Helper: **Show fewer repeated skin-tone variants while browsing. Saved emoji stay the same, and specific variants still appear when you search for them.**
- If a visible reset action is offered: **Show All Variants**
- Filter summary while reduced: **{shown} of {total} categories shown · Fewer Variants**. Keep category and variant state distinct; use proper plural handling.
- Accessible value: the selected choice, not “On” for an unspecified filter.

Do not call a skin tone “normal,” replace a chosen emoji with a different tone, or imply that this changes the person's preferred tone. Whole sequences remain exact, including multi-person emoji. The helper requires the explicit-variant search exception in item 15; do not ship it before that behavior works. This preference applies to browsing in the app and keyboard, not saved entries.

## 16. Undo the last row arrangement change

- Visible action: **Undo Arrangement**
- Accessible hint: **Restores the arrangement before your last change on this page.**
- Success, if feedback is needed: **Arrangement restored**
- Safely invalidated undo: **Undo Arrangement is no longer available because the page changed. Your later changes have been kept.**
- Save failure: **Couldn’t restore the arrangement. Try again.** Only add **Your arrangement hasn’t changed.** if the write is known to be atomic.

The action is one step, not an edit history. Do not imply that page changes, later conflicting edits, text entry or configuration imports can be undone here. Keep **Undo Last Configuration Change** separate and unchanged. Hide/disable a nonexistent undo rather than showing an error on every page.

Keep the existing partial local-copy notice exactly when the shared save succeeds:

**Your change is saved and available to the keyboard, but the app couldn’t update its local copy.**

A successful shared restore with a secondary local-copy failure is not “Couldn’t restore.”

## 17. Select rows directly

- Scope control: **Rows**
- Scope choices: **All Rows** / **Row {n}**
- Scope helper replacing “Select a key to align only its row”: **Choose a row to change its alignment without editing a key.**
- Direct row selector accessible label: **Select row {n}**
- Selected value/trait: **Selected**
- Alignment accessible label remains **Alignment for all rows** / **Alignment for row {n}**.

Retain **Left**, **Center**, **Right**, **Spread**, and the read-only **Mixed** state. Retain width-limit warnings, physical left/right meanings, and **Rows of Ten, Align Left**. Row numbers are one-based. Favorites has no row-alignment scope.

Existing key instruction remains **Tap a key to change its choices. Drag a key to move it.** The new row instruction should sit with the row control, not imply that a key tap is now required for alignment.

## 18. Explain symbol-page changes

Show one nonblocking message after the relevant edit, only when the merged/split state changes. Use the actual reason supplied by layout calculation, not a guess from key count. Do not replay on launch.

- Merged: **Symbols now fit on one page because ABC types all ten digits. Your key actions are unchanged.**
- Split because digits are missing/remapped: **123 and #+= are separate again because ABC no longer types all ten digits. Your key actions are unchanged.**
- Split because of space: **123 and #+= are separate again because the symbols no longer fit on one page. Your key actions are unchanged.**

These messages do not rename the saved Symbols page or imply that any layout was reset. Show the digit reason first if both conditions fail; do not claim only one underlying condition failed. If the merge algorithm uses labels beyond ABC/123/#+=, substitute the visible labels consistently. Announce the message once for accessibility without taking focus from the edit.

## 19. Font files, styles and capacity

Keep screen **Font Downloads**. Within the file-management portion:

- Section: **Your Fonts**. Separate groups **Font Files** and **Installed Fonts**; installed-font references carry **Installed on This Device**. File Size is shown only for real downloaded/imported files.
- Capacity label: **Font Capacity**
- Capacity value: **{used} of 16**
- Accessible capacity value: **{used} of 16. {files} font files, {installed} installed fonts.** Use singular **1 font file** / **1 installed font** as needed; the visible Font Capacity label supplies the context.
- Capacity helper: **Each added font file or installed font counts once. A file can contain several styles.**
- Remaining: **You can add {free} more font files or installed fonts.** / **You can add 1 more font file or installed font.**
- Full: **The limit of 16 has been reached. Remove an added font to make room.**
- Empty: **No fonts added**
- Empty helper: **Browse Google Fonts or add a font file.**
- Existing actions: **Browse Google Fonts**, **Add Font File**, **Use Installed Font** where currently available.

Source audit: `CustomFontStore.maximumFonts` is 16 and both `add` and `addInstalled` use `fonts.count`. The counter must include added installed-font references, not mislabel them as downloaded files. Bundled/system fonts not explicitly added here and separate Unicode packs are outside this counter. Each actual shared downloaded file still counts once, not once per style. An installed-font reference has no copied file-size value: show **Installed on This Device**, not “0 bytes.” No storage-policy change is requested by this copy.

Per file:

- **File Size** — verified local size; unknown **Size unavailable**.
- **Styles** — actual names, including Normal/Italic/width/weight where applicable.
- Shared-file helper: **Includes {n} styles in one file.**
- Compact line: **1 file · {n} styles · {size}**; correct singular **1 style**.
- **Used by Font Rules** — show actual rules referencing styles in this file.
- Empty references: **No font rules use this file.** Only after the reference check completes.

Revision 2.3 replaces “Keyboard Unverified” (Colo design-polish-1 rev 1.0): list rows and the font rule picker show nothing for the unconfirmed state. The font detail screen shows a **Keyboard** row with value **Not Checked Yet** (VoiceOver **Keyboard, Not checked yet**) and footer **Uniboard checks this font when its keyboard opens with Full Access. It already works here in the app.** (Pluso msg1675 confirmed the keyboard records the check only with Full Access on; no Full Access button here). The row follows the computed status: hidden when available, **App Only** when confirmed unavailable. Downloaded and added font files are always available to the keyboard per the status logic. Keep **App Only** only for verified unavailability. Details in `polish-keyboard-status.md`. Downloading does not install a font for use in other apps. Use **Fonts change the preview here. Other apps choose how inserted text looks.** when that distinction needs explanation.

Removal:

- Shared file action: **Remove File ({n} Styles)**; single style **Remove File**.
- Confirmation: **Stop using this font file?**
- Body: **This file will no longer provide styles in Uniboard. Styles available from other files will stay available.**
- If rules refer to it: **Your font rules will be kept. Other fonts will be used where a referenced style is no longer available.** Show the affected rules before confirming.
- Destructive action: **Remove File**
- Cancel: **Cancel**
- Retained-file explanation when applicable: **Some font files remain stored after you stop using them. Removing a file here may not free device storage immediately.**
- For an installed-font reference, use **Stop Using Font** instead of Remove File, with **This stops using the font in Uniboard. It doesn’t uninstall the font from this device.** Retain affected-rule warnings.

Do not promise freed bytes immediately, delete rules automatically, remove other files without consent, or confuse style count with file capacity. The 40 MiB per-file limit remains as implemented; no cap increase is implied.

## 20. Support Us and app icons

### Commercial decision boundary

The user's one-time icon unlock request is known. Whether yearly remains and what it provides are still open. The strings below cover the one-time option and common purchase/icon states only; they do not decide the yearly option or its benefits. Do not create a subscription promise, cadence, expiry policy, annual price label, or future-icon entitlement from this document. Ato/Natun must settle those, with Ampo's review, before final yearly copy.

Purchases and promotion belong only in the containing app. Nothing here goes in the keyboard. Use StoreKit's actual localized price, never hard-code $3.99 in UI. No new account or purchase-reporting consent is implied.

### Support screen

- Screen/Settings row: **Support Us**
- Heading: **Support Uniboard**
- Body: **Help support Uniboard and unlock extra app icons. Typing, language conversion and language downloads stay free.**
- One-time offer title: **One-Time Support**
- One-time offer detail: **A one-time purchase that permanently unlocks the icons shown here.**
- Price line: **{localized price} once**
- Purchase action: **Unlock Icons — {localized price}**
- Restore: **Restore Purchases**
- Legal links: **Privacy Policy** / **Terms of Use**, pointing to real approved destinations.

“Permanently” describes the non-consumable entitlement, not immunity from refunds/revocation or a promise to include every future icon. Clearly identify the icons included in this purchase. Do not say “donation,” “all future icons,” or “lifetime updates.”

### Purchase states

| State | Exact copy / action |
| --- | --- |
| Loading product details | **Loading purchase options…** |
| Price/product unavailable | **Purchase options aren’t available right now. Try again later.** / **Try Again** |
| No connection detected | **Connect to the internet to load purchase options or restore purchases.** |
| Purchase in progress | **Completing purchase…** |
| Pending approval | **Purchase pending** / **Your purchase is waiting for approval. The icons will unlock after it’s approved and verified.** |
| Explicit user cancellation | Return quietly to the offer; no alarming failure message. |
| Verified success | **Thank you for supporting Uniboard. Your extra icons are unlocked.** / **Choose an Icon** |
| Unverified transaction | **We couldn’t verify this purchase. Try Restore Purchases before buying again.** / **Restore Purchases** |
| Generic purchase failure | **The purchase couldn’t be completed. Try again later.** |
| Restore in progress | **Restoring purchases…** |
| Verified restore | **Your extra icons have been restored.** |
| Successful check, no entitlement | **No icon purchase was found for this App Store account.** |
| Restore/network failure | **Purchases couldn’t be restored. Check your connection and try again.** |
| Already entitled | **Icons Unlocked** / **Choose an Icon**; no duplicate purchase prompt. |

Do not call a failed restore “No purchases found.” Do not assert that Apple charged nothing after a verification/network failure. Existing verified entitlement should not be represented as lost solely because the device is offline; implementation owns that state. Keep errors free of raw server details, identifiers, receipt text or file paths.

### App Icons

- Screen/Settings row: **App Icons**
- Original icon: **Original**
- Current icon badge/value: **Current Icon**
- Preview heading: **Icon Preview**
- Preview-appearance picker: **Light** / **Dark** / **Tinted**. Accessible label: **Preview Appearance**. Hint: **Changes only the preview.**
- Preview helper, where needed: **Previewing an icon doesn’t buy or apply it.**
- Explicit apply action: **Use This Icon**
- Return to original: **Use Original Icon**
- Locked icon action: **View Support Options**; it navigates, not purchases.
- Applying: **Changing icon…**
- Success: **App icon changed**
- Failure: **The app icon couldn’t be changed. Try again.**
- Accessible preview label: **Preview {icon name} icon**
- Accessible apply label: **Use {icon name} icon**

### Final icon names and spoken labels

Colo’s artwork supplied in msg1592 confirms the four short names below. These are icon-choice labels, not new product names or a change to Uniboard’s identity. Keep the displayed order **Original**, **Night**, **Paper**, **Hangul**, **Sunrise**.

| Visible name | Preview control label | Apply control label | Artwork basis — not UI text |
| --- | --- | --- | --- |
| Original | **Preview Original icon** | **Use Original Icon** | Existing white-background icon; unchanged. |
| Night | **Preview Night icon** | **Use Night icon** | Dark keyboard with an orange accent key. |
| Paper | **Preview Paper icon** | **Use Paper icon** | Cream background with a red accent key in Light. |
| Hangul | **Preview Hangul icon** | **Use Hangul icon** | The Korean syllable 가 on the accent key. |
| Sunrise | **Preview Sunrise icon** | **Use Sunrise icon** | Warm orange background and yellow accent key in Light. |

Use **Hangul**, not “Korean Pack” or “Korean Keyboard,” for this icon. Choosing it does not download, enable or select a Korean input mode. If an explanation is shown, use **Changing the app icon doesn’t change your keyboard or input mode.**

The four alternate sets have supplied Light, Dark and Tinted artwork. **Original** has only its existing Light artwork: hide the appearance picker for Original rather than presenting disabled or invented appearances. This supersedes the archive README’s earlier “shows Light only” instruction, matching Colo’s message1592. Do not alter Original or infer how iOS itself renders it in other system appearances.

Names remain the same across appearances. A static preview image uses **{icon name} icon, light appearance**, **{icon name} icon, dark appearance**, or **{icon name} icon, tinted appearance**, according to the actual preview. Those are complete localizable templates. A preview control uses the control label above; combine its thumbnail and text into one accessible element rather than announcing the same icon twice. Keep the **Current Icon** value distinct from a merely selected preview.

Night, Paper and Sunrise share identical supplied Tinted artwork. Describe the offer as four alternate icons, not twelve different designs, and do not promise that every icon looks different in every appearance. Naming has reviewed the artwork files, not installed-system rendering or icon switching; engineering verification is still required.

Keep Original available without a purchase. Never announce a changed icon until the platform confirms it. The existing **Use This Icon**, **View Support Options**, purchase states and open commercial decision remain unchanged.


## Copy-wide implementation checks

- Full templates must be localizable units. Use real plural handling and localized sizes/prices/numbers; never stitch grammar around a translated count.
- User dictionary/page names and exact Unicode outputs are content, not localization keys. Display safely without silently trimming or normalizing them.
- Announcements must describe completed state, never speculative success. Avoid repetitive progress announcements.
- This is a design/implementation copy handoff, not proof that twenty features have shipped. Release copy follows the verified implementation.

## Follow-up: landscape number-row note (revision 2.4)

Ato msg1721, Colo design-landscape-compact.md rev 1.0. In iPhone landscape, Mandarin, Japanese and (once built) Korean Romaja hide the number row. Show this footnote in Main Keyboard → Letters, iPhone only, only when the arrangement has a number row:

**In landscape on iPhone, Mandarin and Japanese hide the number row so you can see what you're typing. Use the 123 key for digits there. Your arrangement doesn't change.**

Per Ato msg1724, the row hides only when it holds just the digits 1 to 0; a customized row stays. If that case exists, show instead: **In landscape on iPhone, Mandarin and Japanese hide the number row only when it holds nothing but digits. Your number row has other keys, so it stays, and there's less room to see your text.** When Romaja follows the same rule, the list becomes **Mandarin, Japanese and Korean Romaja**. Keep the merged-symbols footnote unchanged; rotating must not trigger the item 18 split/merge message. Details in `landscape-number-row-note.md`.
