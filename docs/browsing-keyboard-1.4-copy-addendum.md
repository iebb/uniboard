
## Script scope correction — msg812

Supersedes all earlier three-script wording: **Hebrew and Arabic** only for 1.4. Armenian is deferred; no Add Layout row, availability claim or release-note mention for Armenian in this release.

Arabic's additional key: accessible label **Arabic Diacritics**. Chooser title **Arabic Diacritics**. Helper, if needed: **Choose a mark to add to the text.** Do not call it Shift or imply it capitalizes letters. Individual accessible choices must use the verified mark names (such as Fatha, Damma, Kasra, Shadda or Sukun where actually present), not read only an isolated combining glyph. A dotted-circle display aid must not be inserted or copied with the actual mark. Exact inventory follows implementation; no unsupported marks are promised here.

If a hold-only key needs instruction: **Touch and hold for Arabic diacritics.** Also provide the same choices through a non-hold accessibility action, labeled **Choose Arabic Diacritic**; the wording does not replace implementing that access.

Shared 123 pages remain. Planned layout-specific hold choices are Arabic comma/question mark/semicolon and Hebrew shekel sign. Existing custom choices take priority. Do not advertise them as universally present across layouts or as overwriting saved choices. New choices and combining-mark insertion/deletion require verification before availability claims.

Shared-file removal wording approved msg809: **Remove File ({n} Styles)**. Confirmation: **This removes the downloaded file. Styles available from other files will stay available.** Count describes the file's contents, not how many styles disappear.
