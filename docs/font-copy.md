# Uniboard — character fonts and Google Fonts copy

For product, design and development. Existing name retained. Proposed English copy for the requested features; not evidence that downloading or coverage checks are implemented. Scope and interaction design remain with product/design.

## Core distinction

Use this persistent note beside font previews: **Fonts change the preview here. Other apps choose how inserted text looks.**

On the download screen: **Downloaded fonts are for use in Uniboard. They aren’t installed for other apps.**

Do not promise “all languages”, “every font on your iPhone”, or that a character can be displayed correctly by every destination app. Prefer **Fonts available to Uniboard** to “All installed fonts”. Do not call downloads system installations.

## Consistent terms

- **Character**: the Unicode character being inspected. Preserve its existing name and code point labels.
- **Font**: a named font used to render a preview. Show its actual name unchanged.
- **Style**: a face/variant such as Regular or Bold; show separately from the family name when needed.
- **Preview**: display in Uniboard, not a formatted-text insertion promise.
- **Available**: successfully registered and usable in the current Uniboard process, not merely downloaded or listed online.
- **Downloaded**: verified files saved locally. This alone does not prove character support or keyboard availability.
- **Included**: a font shipped with Uniboard.
- **System**: a font made available to this process by iOS.
- **Google Fonts**: keep the service name; don't translate or imply an endorsement.
- Keep existing **Copy Character**, **Copy Text**, **Copy Emoji**, **Scratchpad**, **Save**, **Saved**, **Done** labels in character details. None of these actions copies a selected preview font.

## Character detail and font grid

Existing screen title: **Character**.
Section / pushed screen title: **Fonts for This Character**.
Optional concise entry point: **View Fonts**.
Grid count: **1 font available** / **{count} fonts available**. Count distinct faces or families consistently with the actual grid unit; never mix the two.
Search, if included: **Search available fonts**.
Grid tiles: rendered sample, actual font name, style where needed, and optional source label **System**, **Included**, or **Downloaded**.
Accessible tile label: **{font name}, {style}, preview of {character name}**. Do not rely on the glyph itself being speakable.

| State | Title or status | Body | Action |
|---|---|---|---|
| Checking local font support | Checking available fonts… | None | None |
| No verified local match | No matching fonts | None of the fonts available here can preview this character. | Browse Google Fonts |
| Filter returns no matches | No matching fonts | Try a different font name. | Clear Search, if supported |
| Preview failed after selection | Preview unavailable | This font couldn’t display the character. | None |
| Font support cannot be checked | Couldn’t check font support | Try again in a moment. | Try Again |

“Browse Google Fonts” is navigation, not a promise Google Fonts contains a match. Never label a fallback-rendered tile as supported by the named font. If font checks only establish code-point coverage, use the narrower title **Fonts With This Character**, and do not claim correct shaping of a whole sequence or language.

Retain special-character explanations:
- Invisible characters: **This character is invisible. Its preview is a placeholder; copying inserts the actual character.**
- Combining marks: **The dotted circle is only a preview. This mark combines with the character before it.**
- Keep **Text** and **Emoji** presentation distinctions. A font matching one presentation is not proof it supports the other.
- Font coverage does not establish an input method, composing behavior, or language support.

## Google Fonts browsing

Screen title: **Google Fonts**.
Search placeholder: **Search fonts by name**.
Intro: **Find a font and download it when you need it.**
Persistent scope note: **Downloaded fonts are for use in Uniboard. They aren’t installed for other apps.**
Before download, show the font family/name, selected style or exact download scope, and file size when known. Do not invent an estimated size or imply a whole family is downloaded if the action gets one face.

| State | Exact label/body | Action |
|---|---|---|
| Catalog loading | Loading fonts… | None |
| Ready to download | Actual name and style | Download |
| Queued | Waiting to download… | Cancel, only if queue cancellation exists |
| Download in progress | Downloading… {percent}% | Cancel |
| Total size unknown | Downloading… | Cancel |
| Verification/registration pending | Preparing font… | None |
| Saved and usable | Downloaded | Preview, only if preview exists |
| Search returns nothing | No fonts found / Try a different font name. | Clear Search, if supported |
| Catalog fetch fails | Couldn’t load Google Fonts / Try again in a moment. | Try Again |
| Known offline | No internet connection / Connect to the internet to browse and download fonts. | Try Again |
| Font download fails | Couldn’t download this font / Try again in a moment. | Try Again |
| Download invalid or unusable | Couldn’t use this font / The downloaded file couldn’t be loaded. | Try Again |
| Cancellation completes | Download cancelled | Download |

Do not clear already usable fonts when the catalog is unavailable. If the previous catalog is shown, say **Showing saved results.** No automatic bulk downloads implied by search or preview.

## Font details / management (only where in agreed scope)

Title: actual font name.
Sections: **Styles**, **Preview**, **License**.
For downloadable face selection: **Download Style**. For a true family-wide action: **Download Family**. Use only the one matching the implementation.
For removal, use **Remove Download**, not Delete Font or Uninstall.
Confirmation: **Remove {font name}?**
Body: **This removes the downloaded font from Uniboard. You can download it again later.**
Actions: **Remove Download**, **Cancel**.
Never offer removal for system or included fonts.

If downloads are initiated in the main app rather than the keyboard, keyboard entry point: **Open Uniboard to Download Fonts**. Do not claim keyboard availability until the shared-storage/registration path is verified. If not available there, state **Available in the app only**.

## Copy acceptance checks

1. No “supported languages” count derived from character-font coverage.
2. No font change implied by Copy Character or keyboard insertion.
3. No fallback font presented as a match for another font.
4. Downloaded, available, and supported are distinct states.
5. Download failure, unknown coverage and no matches are not conflated.
6. Invisible characters, combining marks, text/emoji variants and sequences remain explicit.
7. Only actual user actions receive buttons; optional wording does not add feature scope.
