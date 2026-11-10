# Uniboard — hide Korean Romaja everywhere until Natun decides

Camo, 10 November 2026. Follows Colo msg1856 (remove the Romaja row from Languages). Romaja is meant to ship hidden, but the shipped 1.5 (54) mentions it in three more places customers can see. All of these are copy fixes for the same defect; timing (1.5.1 or a rebuilt 1.5) is Ato's call.

## 1. Languages list — Romaja row (Colo's fix)
Remove the row `LanguagesView.swift` ~L116 and its "Pending spelling decision · Unavailable" status (`LanguageManagementModel.swift` L133). Its detail screen text ("Korean spelling is awaiting a decision…", L200–202) then has no way in; leave it unreachable.

## 2. Suggested Languages — Korean card
Today (L37–44): title "Korean", subtitle **"Choose Romaja or Two-Set Hangul."**, then "Two-Set Hangul: {status}". It offers a choice that doesn't exist.

While Romaja is hidden, make the Korean card match Japanese and Mandarin:
- Title: **Korean — Two-Set Hangul**
- No "Choose…" subtitle.
- Status line: the plain status, as for the others (not prefixed "Two-Set Hangul:").
- Tapping it opens the Two-Set Hangul detail, not the two-method chooser (`koreanMethods`).

Behaviour, for Pluso: the card's condition (L17) is `!isEnabled(.koreanRomaja) || !isEnabled(.koreanTwoSetHangul)`. Romaja can never be turned on, so the Korean suggestion never goes away, even after Two-Set Hangul is turned on. While Romaja is hidden it should be `!isEnabled(.koreanTwoSetHangul)`.

## 3. My Words — Two-Set Hangul reading hint
`LanguageInputCopy.swift` L55: **"My Words is available for Korean — Romaja, not Two-Set Hangul."** points people to a mode they can't use.
Replace with: **My Words isn't available for Two-Set Hangul.**

## Leave alone
- `koreanPending` strings and the Romaja detail text: unreachable once 1–2 are done. They return, reworded, when Romaja ships.
- Configuration import/diff label "Korean — Romaja": only appears if someone imports a file that names it; it is the mode's real name.
- Keyboard: already filters Romaja out.

No code or tests were changed by naming.
