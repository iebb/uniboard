"""Focused 1.5 emoji data/source contracts; no build, Swift execution or Simulator claim.

Run: python3 Scripts/test_emoji_browsing.py
The executable Swift behavior/migration tests live in Tests/EmojiBrowsingTests.swift.
"""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (text[cursor] == "{") - (text[cursor] == "}")
        cursor += 1
    return text[start:cursor]


def base(points):
    return tuple(p for p in points if not 0x1F3FB <= p <= 0x1F3FF)


def project(entries):
    sequences = {tuple(e["codePoints"]) for e in entries}
    return [e for e in entries if tuple(e["codePoints"]) == base(e["codePoints"])
            or base(e["codePoints"]) not in sequences]


class EmojiBrowsingContracts(unittest.TestCase):
    def test_bundled_whole_sequences_have_meaningful_filter_and_unmatched_coverage(self):
        entries = json.loads(source("Shared/Resources/EmojiCatalog-draft.json"))["entries"]
        projected = project(entries)
        kept = {e["id"] for e in projected}
        sequences = {tuple(e["codePoints"]) for e in entries}
        hidden, unmatched, mixed, mixed_hidden, mixed_kept = 0, 0, 0, 0, 0
        for entry in entries:
            points = entry["codePoints"]
            tones = [p for p in points if 0x1F3FB <= p <= 0x1F3FF]
            is_mixed = len(set(tones)) > 1
            mixed += is_mixed
            if entry["id"] not in kept:
                hidden += 1
                mixed_hidden += is_mixed
                self.assertTrue(tones)
                self.assertIn(base(points), sequences)
            elif tones:
                unmatched += 1
                mixed_kept += is_mixed
                self.assertNotIn(base(points), sequences)
        self.assertGreater(hidden, 500)
        self.assertGreater(unmatched, 0)
        self.assertGreater(mixed, 0)
        self.assertEqual(mixed_hidden + mixed_kept, mixed)
        print(f"catalog coverage: {len(entries)} full, {len(projected)} fewer, {hidden} hidden, "
              f"{unmatched} unmatched toned retained; mixed-tone {mixed_hidden} hidden/{mixed_kept} retained")
        # The reference projection selects original records, never synthesizes text.
        self.assertTrue(all(any(e is original for original in entries) for e in projected))

    def test_all_mixed_family_tones_require_exact_whole_base(self):
        family = [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]
        base_entry = {"codePoints": family}
        toned = [{"codePoints": [0x1F468, left, 0x200D, 0x1F469, right, 0x200D, 0x1F467]}
                 for left in range(0x1F3FB, 0x1F400) for right in range(0x1F3FB, 0x1F400)]
        self.assertEqual(len(toned), 25)
        self.assertEqual(project([base_entry] + toned), [base_entry])
        self.assertEqual(project(toned), toned)
        different_zwj = {"codePoints": family + [0xFE0F]}
        self.assertEqual(project([different_zwj] + toned), [different_zwj] + toned)

    def test_swift_policy_uses_scalar_arrays_not_text_or_component_substitution(self):
        policy = block(source("Shared/EmojiBrowsingPreferences.swift"), "enum EmojiBrowsingPolicy")
        for fragment in ("Set(entries.map(\\.codePoints))", "(0x1F3FB...0x1F3FF).contains($0)",
                         "!sequences.contains(base)", "result.append(entry)", "Task.isCancelled"):
            self.assertIn(fragment, policy)
        for forbidden in (".text", "0x200D", "0xFE0F", "normalized", "folding", "String("):
            self.assertNotIn(forbidden, policy)

    def test_projection_precedes_pagination_and_nonempty_search_bypasses_it(self):
        catalog = source("Shared/EmojiCatalog.swift")
        ordered = block(catalog, "    func orderedEntries(")
        self.assertIn("EmojiBrowsingPolicy.project(shown, skinToneVariants: skinToneVariants)", ordered)
        page = block(catalog, "    func entries(offset:")
        self.assertIn("skinToneVariants: skinToneVariants).dropFirst(offset).prefix(limit)", page)
        search = block(catalog, "    func search(")
        self.assertIn("guard !trimmed.isEmpty else", search)
        self.assertEqual(search.count("skinToneVariants: skinToneVariants"), 1)
        self.assertNotIn("EmojiBrowsingPolicy.project", search)
        self.assertIn("skinToneVariants: SkinToneVariants = .all", search)

    def test_settings_legacy_default_is_read_only_root_scoped_and_atomic(self):
        settings = source("Shared/EmojiBrowsingPreferences.swift")
        self.assertIn("SharedConfigurationLocation.shared.root()", settings)
        self.assertNotIn("currentDirectory()", settings)
        self.assertIn("let fewerVariants: Bool", settings)
        self.assertIn("file.schemaVersion == 1", settings)
        self.assertIn("data.count <= maximumPayloadBytes", settings)
        load = block(settings, "    func load()")
        self.assertIn("Self.decode(data) ?? .all", load)
        self.assertNotIn("save(", load)
        self.assertIn("SharedConfigurationLocation.replaceFile", block(settings, "    @discardableResult func save("))
        # The independent preference intentionally does not enter configuration migration/import schemas.
        self.assertNotIn("EmojiBrowsingSetting", source("Shared/SharedConfigurationLocation.swift"))
        tests = source("Tests/EmojiBrowsingTests.swift")
        self.assertIn("location.migrateIfNeeded(presentation: presentation)", tests)
        self.assertIn("testFailedAtomicSaveDoesNotFollowSymlinkOrReplaceTarget", tests)

    def test_app_publishes_and_notifies_only_after_successful_save(self):
        setter = block(source("App/CatalogPreferences.swift"), "    func selectSkinToneVariants(")
        self.assertLess(setter.index("guard emojiBrowsingSetting.save(value)"), setter.index("skinToneVariants = value"))
        self.assertLess(setter.index("skinToneVariants = value"), setter.index("CFNotificationCenterPostNotification"))
        self.assertIn("EmojiBrowsingSetting.changedNotification", setter)

    def test_background_request_captures_all_filter_inputs_and_checks_stale_completion(self):
        view = source("App/EmojisView.swift")
        request = block(view, "private struct EmojiBrowseRequest")
        for field in ("edition", "query", "order", "hidden", "skinToneVariants", "limit"):
            self.assertIn(f"let {field}:", request)
        task = block(view, "        .task(id: request)")
        self.assertIn("CatalogWorker.run", task)
        self.assertIn("skinToneVariants: captured.skinToneVariants", task)
        self.assertIn("guard !Task.isCancelled, captured == request", task)
        self.assertIn("completedRequest?.hasSameProjection(as: request) == true ? loadedEntries : []", view)
        self.assertIn(".onChange(of: preferences.skinToneVariants) { _, _ in pageLimit = 120 }", view)

    def test_automatic_and_filter_reset_are_separate_narrow_actions(self):
        view = source("App/EmojisView.swift")
        self.assertIn("withAnimation(reduceMotion ? nil : .snappy) { emojiColumns = 0 }", view)
        self.assertIn(".disabled(emojiColumns == 0)", view)
        self.assertIn('if emojiColumns == 0 { Image(systemName: "checkmark") }', view)
        self.assertIn('.accessibilityLabel("Automatic emoji size")', view)
        self.assertIn('.accessibilityHint("Fits emoji to the available width.")', view)
        self.assertIn('Button("Show All Variants", action: showAllVariants)', view)
        self.assertIn('showAllVariants: { preferences.selectSkinToneVariants(.all) }', view)
        self.assertIn(' · Fewer Variants', view)
        self.assertIn('.pickerStyle(.segmented)', view)


if __name__ == "__main__":
    unittest.main()
