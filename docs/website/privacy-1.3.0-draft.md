> Draft for the existing https://docs.kitta.co/uniboard/ policy. Not published. Effective date to be set on publication. Pending normalization-result / UTF-8 / UTF-16 copy additions and final cursor verification must be reconciled before release.

## Uniboard

Uniboard is an offline Unicode character and emoji explorer and keyboard for iPhone and iPad. It is published by Kitta Ltd, trading as Kitta Co.

**Uniboard does not collect data from the app.** The app has no accounts, advertisements, tracking or analytics SDK. The custom keyboard works without Full Access.

## Keyboard input and search

The Unicode release, development draft and emoji catalogs are bundled with the app. Character and emoji searches run on your device. Entering a search in the keyboard edits a query kept inside the keyboard extension; it does not write the query into the active text field.

When you select a character or emoji, the keyboard inserts its original Unicode scalar or complete sequence into the active field. Uniboard does not send your typing, queries or inserted text to Kitta Ltd or an app-operated server. The app that receives your inserted text handles that text under its own privacy policy.

## Data on your device

Favorites, recent entries, symbol pages, configured keys, preferences and scratchpad text are stored locally. App-authored preferences, configured keys and explicit Favorites are shared with the keyboard through on-device storage. With Full Access off, keyboard favorite edits remain pending locally; optional Full Access lets those edits return to Saved. Pages configured in the app also reach the keyboard through on-device shared storage. Recent entries remain local to their collection. Nothing is synced to a developer-operated service.

You can remove favorites and clear scratchpad text within the app. Recent entries are limited to the latest 60 distinct characters and 60 distinct emoji in each collection. Deleting Uniboard through iOS removes its local app data. Copies you paste into other apps and device backups remain under your control; backups may include app data under your Apple settings.

## Optional font downloads

Extra Unicode fonts are off by default. Core search, the bundled catalogs and typing work without a network connection. If you choose Download in the companion app, it requests static font files from GitHub’s release-file CDN for font packs, or from the Google Fonts repository on raw.githubusercontent.com for selected Google Fonts files. The font catalog and name search are local; the selected download request identifies the font file, not your search text. Requests do not contain your typing, searches, favorites, scratchpad text or an app account identifier. The downloader uses a separate cookie-free session.

GitHub and its delivery providers receive ordinary technical request information, such as an IP address and the requested file, to deliver and protect downloads under [GitHub’s privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). GitHub exposes aggregate asset-download counts; Uniboard has no download analytics SDK and Kitta Ltd does not receive individual download logs from the app.

Each font is checked against its expected size and SHA-256 before being saved on your device. The keyboard reads verified local files and never downloads them itself. Fonts are used only for previews while the option is on; they do not change text inserted into other apps or install system-wide fonts. Downloads can be removed in the app and are excluded from device backups. Turning previews off retains the downloaded files until you remove them.

## Text preview and inspection

The keyboard uses the surrounding text that iOS makes available to show its text preview. It does not have unrestricted access to your whole document. When you open Inspect Text or Copy Image, Uniboard uses the excerpt shown in the preview, not hidden text elsewhere in the document.

Inspection counts characters and code points and checks Unicode normalization on your device. It does not send that text to Kitta Ltd or an app-operated server, or automatically change the text in the app you are typing into. Closing the inspection panel clears its temporary snapshot. Copying or saving a result creates a separate copy under your control.

## Configuration files

You can export your configuration to a TOML file and choose where to save or share it. The file can contain settings, editable layouts and pages, custom key text, favorites, font references and rules, and Copy Image colors and scale. Favorites and custom text may be personal. Typing history, scratchpad contents and font files are not included. Copy Image colors and scale chosen in the keyboard without Full Access are not included in the app’s export.

Exporting does not send the file to a Kitta server. Files and destinations you choose, including cloud storage or another app, handle your exported copy under their own policies. Remove exported copies from those destinations when you no longer need them; deleting Uniboard does not remove copies you shared elsewhere.

An import is checked and reviewed before you confirm replacement. Missing sections reset to defaults. Import does not download font files. Uniboard keeps a previous configuration locally for Undo Last Import; restoring it also replaces later configuration changes. Local configuration and its recovery copies remain on your device until replaced or removed with the app.

## Clipboard and permissions

When you choose a copy action, Uniboard writes the selected character, complete emoji sequence, scratchpad text, inspected preview text or code-point labels to the system clipboard. Copy Image writes a rendered PNG of the shown excerpt using your chosen colors and scale. This is a picture, not editable text, and can be pasted only where images are accepted. Other apps may access clipboard content under iOS rules. Uniboard does not continuously read or monitor the clipboard.

Full Access is optional. It enables local favorite and Copy Image preference writes from the keyboard back to the app, keyboard clipboard copy actions, and light iPhone haptics; it does not enable typing or search collection. App settings and downloaded font previews reach the keyboard without Full Access. Uniboard does not request location, camera, microphone, contacts or advertising permissions. iOS controls which text fields and apps allow a third-party keyboard.

## Support messages

If you voluntarily contact Kitta Ltd, we receive the information you choose to send, such as your email address and message. We use it to answer your request and resolve the issue. Please do not include passwords, private documents or sensitive typing in support messages.

## This policy website and external services

This policy is hosted on GitHub Pages and delivered through Cloudflare. [GitHub logs visitor IP addresses for security purposes](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages#data-collection). Cloudflare may process IP addresses and ordinary network request information to deliver and protect the website, as described in [Cloudflare’s privacy policy](https://www.cloudflare.com/privacypolicy/). Website request processing is separate from the offline app.

If you open an external link, the destination receives the request information needed to serve its page and its own privacy policy applies. Apple manages App Store distribution, system services and device backups under its policies and your settings.

## Children

Uniboard does not collect personal information through the app from children or other users. It has no messaging, user accounts or social network.

## Your choices

Font downloads are optional. You can decline them, remove downloaded files in the app, or turn off Extra Unicode Fonts to pause their use while keeping the files. You can turn off Full Access in iOS keyboard settings; normal typing, search and inspection still work. Copy and export actions happen only when you choose them. You can remove favorites or custom text, clear the scratchpad, and delete the app to remove its local data. Copies in other apps, exported files and device backups must be managed separately.

## Changes and contact

We will update this policy and the app’s privacy disclosures if its data practices change. The date above identifies this revision.

Questions about this policy: [privacy@ieb.app](mailto:privacy@ieb.app?subject=Uniboard%20Privacy). For app help, visit the [Kitta support page](https://docs.kitta.co/support/).

[Back to Kitta apps](https://docs.kitta.co/) · [Uniboard website](https://uniboard-dxm.pages.dev/)
