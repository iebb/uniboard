# Verified font discovery and comparison — handoff

23 Oct 2026. Shared dirty master; no commit or release. Simulator build f1b226d5-7875-48ae-b09e-d82e9c82fd64 installed and running on iPhone 18 Pro.

## Completed
Google Fonts discovery/search, exact-face comparison and downloaded previews are implemented. Source identity, effective variation coordinates, missing-glyph and no-fallback checks remain enforced; keyboard makes no network requests.

The real downloaded Roboto exposed EXC_BAD_ACCESS at CGFontNameTableCreate → CTFontCopyVariationAxes after font loading returned. LoadedFont now retains the physical CGFont, provider and owned CFData; the verified CTLine retains that backing owner through attributed runs. No global font-registration shortcut was introduced.

Mandatory pinned Roboto fixture SHA256 d7598e12c5dbef095ff8272cfc55da0250bd07fbdecbac8a530b9b277872a134 now exercises actual UIKit drawing after autoreleasepool drain. Native engine result 35722f1b-14c4-4b0e-8f2a-35425c153e15: 17 tests, 2 unrelated runtime-dependent fixtures skipped, zero failures; mandatory Roboto passes.

Back navigation issue was active search hiding sheet controls, not a stack pop. Always-visible search drawers and availability-gated avoidance of content hiding plus item-owned inspection route fixed it. Targeted result 7f3a5a42-c0d7-4774-915e-4f24453bdd82: two UI tests passed, including Back to original Copy Character → Copied and immediately visible catalog search → Roboto.

## Full regression context
Earlier source snapshot f51ab751-0257-4e00-8e94-8928cbb3f89d: 620 unit tests, 8 skipped, no failures. 64 UI tests, 41 skipped, one failure: the Back case subsequently fixed and rerun above. Therefore this is NOT a clean all-suite run on final source. Existing opt-in skipped coverage is not claimed. The background follower hit local 30-minute timeout and was reattached; remote run finished in 39m41s.

## Live evidence
Built and installed final source. Opened Settings → Font Downloads → Browse Google Fonts, searched Roboto, selected downloaded Regular and scrolled to verified Aa preview. App remained running and showed the actual rendered preview, codepoints, Downloaded state and license. Screenshot /tmp/uniboard-roboto-fixed.png. Existing download survived rebuild; no fallback claim substituted.

## Limits / separate next work
VoiceOver spoken interaction, physical devices and every Google catalog face not independently tested. Drag customization and Copy Image are separate new requests in progress, not included in this font completion statement.

App Intents report reused: it was updated for these font capabilities earlier today. No existing App Intents. Proposed first priorities remain opening character details and exploring fonts, pending integration verification; none implemented.
