# Uniboard 1.4 font disclosure patch — not published

Prepared from Pluso's source-verified handoff of 25 October 2026 (message 846). Implementation is unfinished; this is not final release or network-capture verification. Apply only after final release confirmation. Existing hosting remains unchanged. GitHub write access still blocks Privacy publication.

## Support — replace font download/storage explanation

The font catalog and name search run on your device. When you choose a download, Uniboard requests the selected font file from GitHub or, for available individual styles, Google's fonts.gstatic.com host. Downloads need an internet connection. No account is needed, and your typing, inspected text, favorites and configuration are not sent with the font request.

Some downloads contain one style; others contain several styles in one file. Check the file description before downloading or removing it. Downloading a shared file keeps your existing separate downloads. Removing one file does not remove other files that provide the same style.

Remove stops Uniboard using that download. It does not immediately erase the stored font bytes or free their disk space: retired files are retained so the app and keyboard can finish reading them safely. Fonts are stored locally, not installed system-wide, and do not change text inserted into other apps. The keyboard reads local fonts without downloading them or requiring Full Access.

## Privacy — replace optional downloads paragraphs

The font catalog, metadata and license notices are bundled with Uniboard. Catalog browsing and name searches run locally. When you choose a font download in the app, Uniboard requests the selected file from raw.githubusercontent.com for original or shared Google Fonts files, or fonts.gstatic.com for available individual styles. Existing optional font-pack downloads may use GitHub's release-file delivery service; retain that disclosure if those downloads remain in the release.

Google, GitHub and their delivery providers receive the selected font resource and ordinary network request information, including your IP address, to deliver the file. Uniboard does not include your typing, inspected text, favorites, custom key text or configuration document in these font requests. The font downloader uses a temporary session without cookie storage, saved credentials or a URL cache. It does not add an app account, app-specific authentication or analytics. Platform-generated request information may still be sent.

Downloaded files are checked against their expected size and SHA-256 hash and validated as fonts before use. Font files, source records, license notices and the active library list are stored locally in storage shared by the app and keyboard. The keyboard reads local files without requesting font downloads and without needing Full Access. No app-operated cloud account or sync service is used.

Removing a download removes it from the active library. It does not immediately erase its font bytes or reclaim their disk space: retired files remain stored so existing app and keyboard views can finish reading them safely. Uniboard does not currently automatically clean up these retired files. Other downloads and explicitly imported copies remain. Deleting the app removes its local app data; copies outside the app and backups must be managed separately. Device backups may include app data according to your Apple settings.

Provider policies to link and verify before publishing: Google https://policies.google.com/privacy and GitHub https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement . Do not invent host retention periods.

## Reconcile throughout the whole Privacy page

- Remove blanket claims that all font downloads are excluded from backups: that has not been verified for the custom font library.
- Replace “downloads can be removed” / “fonts remain until removed” wherever those imply file-byte deletion. Distinguish removal from active use from retained file bytes.
- In Your choices: you can stop using a downloaded font by removing its active entry; this does not immediately free disk space. Manage backups separately.
- Keep the prior 1.3 explicit copy/export/editor privacy corrections, including the fact that exports can carry personal custom text and favorites.
- Set the effective date when actually published, not when this draft was prepared.

## Release checks still needed

Confirm final transport and hosts against the shipping code; distinguish source review from runtime verification. Confirm whether legacy font-pack downloads remain and whether they have different backup behavior. Verify that retained-file behavior also applies in shipped 1.3 before correcting that version's public claims; the handoff says it predates 1.4 but does not identify the exact released commit. Publish only to the existing sites and verify live contents and URLs afterward.

## Confirmed build 52 distinction — supersedes open verification above

Pluso verified submitted commit d3f76b0 on 25 October (message 850): legacy Unicode/emoji packs delete their files on successful Remove and explicitly request iOS backup exclusion for their folder. Google/custom library removal retains retired bytes, with no backup-exclusion setting. This is source verification, not device backup testing. The existing pack disclosure must remain alongside the Google/custom-library paragraphs above: never apply the retained-byte statement universally to all font downloads. Current 1.3 sources now distinguish these cases. The Google fonts.gstatic.com host remains a 1.4-only addition.
