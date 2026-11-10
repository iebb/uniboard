# Uniboard 1.4 — final remaining strings for design §9

Responds to design rev. 1 / msg796. Supplements browsing-keyboard-1.4-copy.md.

1. Filter row: **{shown} of {total} categories shown**. Accessibility hint: **Opens Emoji Categories**. Use locale-aware counts; total comes from the catalog, not hard-coded 9.
2. Toolbar value: **All categories shown** / **{shown} of {total} categories shown**. Menu accessibility label: **View Options**. Full category wording is clearer when spoken independently.
3. Category count: **{n} emoji**, including **1 emoji** and **0 emoji**. Count actual emoji entries/sequences for the selected Unicode version, not code points or glyph components.
4. Keyboard, all hidden: **Choose categories in the Uniboard app.** Keyboard, filtered search empty: **Try another search, or show more categories in the Uniboard app.** Both approved; no dead-end Choose Categories button unless it can actually open the app.
5. Main Keyboard subtitle: **Letters, numbers and symbol keys**.
6. Canvas switch accessible labels: **Switch to More Symbols** / **Switch to Numbers and Symbols**.
7. Read error: **Couldn’t read your saved keyboard keys. Try again. To reset all key actions and arrangements, open Main Keyboard in Keyboard, then choose Restore All Key Defaults from the More menu. This replaces your saved key settings.** Preserve the distinction between key settings and the complete portable configuration. This is an optional destructive recovery, not an instruction to reset automatically. The ellipsis toolbar control must have accessibility label **More** if the error names that menu.
8. Size menu section heading: **Emoji Size**, not a full sentence. Keep **Pinch to change emoji size.** as a hint/helper where there is room, not the section heading. The Smaller/Larger controls already make the menu usable without a gesture.

Interaction confirmations from design: categories apply immediately, so **Done** is final; Find a key searches all three sections, so **No matching keys** / **Try another search.** is final. Emoji zoom affects the app grid only, not the keyboard grid. No copy implies otherwise.

The four §11 proposals remain proposals; no strings or claims here add them to scope.
