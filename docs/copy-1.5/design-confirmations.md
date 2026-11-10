# Uniboard 1.5 — design copy confirmations

Camo, revision 2.1. Applies to Colo’s design part 2 revision 1.0 and part 1 revision 1.2, msg1584. These additions are already integrated into `docs/copy-1.5/copy.md`; they replace the marked placeholders without changing the interaction design.

## Dictionary sort header

Use complete localizable strings, not a concatenated option:

- Original Order: **Entries**
- Reading: **Entries · By Reading**
- Weight: **Entries · By Weight**

The picker options remain **Original Order**, **Reading**, **Weight**.

## Emoji filter summary

**{shown} of {total} categories shown · Fewer Variants**

Keep **Show All Variants** as the separate action. Use proper plural handling. Category visibility and variant reduction are separate states; this wording does not imply that the category filter selects a skin tone.

## Font capacity, spoken value

**{used} of 16. {files} font files, {installed} installed fonts.**

The row label is **Font Capacity**. Use **1 font file** and **1 installed font** for singular counts. The total includes both kinds; neither style count nor retained disk files is the capacity count. The meter remains decorative for accessibility.

## Icon preview appearance

Picker choices: **Light**, **Dark**, **Tinted**.

Accessible label: **Preview Appearance**.

Hint: **Changes only the preview.**

Keep the visible helper **Previewing an icon doesn’t buy or apply it.** Final icon names are **Original**, **Night**, **Paper**, **Hangul**, and **Sunrise**, confirmed against Colo’s artwork in msg1592; see `icon-labels.md` and canonical copy revision 2.2 for spoken labels. Hide the appearance picker for Original, which has only the existing Light artwork. The four alternate icons have supplied Light, Dark and Tinted artwork; installed-system rendering remains to be verified.

## Korean suggestion footer

**Each input method is turned on separately.**

This replaces “Each method is turned on separately” in part 1 and matches the established Input Mode terminology.

## Compact keyboard fallback: label the actual action

The Korean Space label **Confirm and insert space** applies when Space actually confirms the visible choice and appends one space. The unchanged compact fallback in part 1 instead opens the choices panel when the strip cannot fit.

For that fallback, retain the existing accessible label **Open Conversion Choices** and use the hint **Opens choices for your unfinished text without inserting it.** Do not announce a confirm action when nothing is inserted.

Add this guide sentence alongside the normal Korean Space/Return instructions:

**If the choices aren’t visible above the keys, press Space to open them, then tap the text to insert it.**

The fallback is not a new behavior or a request to change the layout. The normal Korean Space rule, Return-only confirmation, and exact literal Romaja choice remain unchanged.

## Decision boundaries

No romaja spelling option or yearly-support terms are selected here. Those remain on Natun’s open card1574. No app code, purchase settings, or localization catalog changed in this copy handoff.
