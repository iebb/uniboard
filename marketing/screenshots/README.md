# Uniboard App Store screenshots

Upload-ready files:

- `iphone/01-keyboard.png` — real code-point search and supplementary-character insertion through the installed Uniboard keyboard. Recommended first iPhone screenshot.
- `iphone/00-explore.png` — actual Explore screen, with the bundled catalog version visible.
- `ipad/00-explore.png` — actual iPad Explore layout, including the block-browsing entry point.

The iPhone artwork is 1320 × 2868; the iPad artwork is 2064 × 2752. Every export is an opaque RGB PNG. These are accepted portrait sizes for Apple's 6.9-inch iPhone and 13-inch iPad screenshot classes. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

`source/iphone/00-explore.png` and `source/ipad/00-explore.png` are unmodified simulator framebuffer captures from dedicated iPhone 17 Pro Max and iPad Pro 13-inch M5 devices running iOS/iPadOS 27. They were captured from the installed real app using `simctl io … screenshot`.

`source/iphone/01-keyboard.png` is the unmodified 1206 × 2622 screenshot attachment from `build/QA/FinalValidation.xcresult`, captured during the passing `testSystemKeyboardSearchAndInsertion` integration test on iPhone 16 Pro / iOS 18.5. The test searched `u+1f680` with the extension's own keys and verified that tapping the rocket inserted `🚀` into the host text editor. Its original attachment and export manifest are retained under `source/validation-attachments/`.

The decorative App Store layouts use the approved app icon at `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Screenshots are resized uniformly and placed inside a decorative frame. Only the physical screen's outer corners are rounded. App text, controls, glyphs and results are never relabeled, generated or replaced.

Run `python3 marketing/screenshots/render.py` from the repository root to regenerate exports, source-hash manifest and `qa/contact-sheet.jpg`. The renderer uses Pillow and the macOS Avenir Next, Georgia and SF Mono fonts. It exports only source captures that exist; planned feature slots are not populated with fabricated UI.

Visual QA: checked the complete composition, readable headlines, preserved query/result/insertion pixels, correct device layouts, accepted dimensions, and absence of alpha channels. `qa/` contains a contact sheet and early layout previews and is not an upload folder.

The larger planned set (active app search, block detail, character detail, Saved, privacy) requires additional actual UI captures. Current Xcode Device Hub acquisition through CUA times out before returning a controllable accessibility window. No shared Device Hub restart, existing simulator reset, or generated UI was used to work around that limitation.
