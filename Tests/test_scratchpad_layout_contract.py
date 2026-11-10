"""Scratchpad source-contract guards; no build or simulator required.

Run: python3 Tests/test_scratchpad_layout_contract.py
These verify layout wiring, not rendered bounds or native cursor visibility.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = 'Text("Add characters from their detail pages, or type here with Uniboard.")'


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth and cursor < len(source):
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    if depth:
        raise AssertionError(f"Unclosed source block: {marker}")
    return source[start:cursor]


class ScratchpadLayoutContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "App/CharacterDetailView.swift").read_text(encoding="utf-8")
        cls.view = block(source, "struct ScratchpadView: View")
        cls.viewport = block(cls.view, "GeometryReader { viewport in")
        cls.scroll = block(cls.viewport, "ScrollView(.vertical)")

    def test_one_stable_editor_and_helper_share_top_anchored_vertical_scroll(self):
        stack = block(self.scroll, "VStack(alignment: .leading, spacing: 10)")
        self.assertEqual(self.view.count("ScrollView("), 1)
        self.assertEqual(self.view.count("TextEditor(text: $text)"), 1)
        self.assertEqual(self.view.count(HELPER), 1)
        self.assertLess(stack.index("TextEditor(text: $text)"), stack.index(HELPER))
        self.assertIn(".defaultScrollAnchor(.top)", self.viewport)
        self.assertIn('.accessibilityIdentifier("scratchpadInput")', stack)
        self.assertNotIn("ViewThatFits", self.view)

    def test_editor_fills_remaining_safe_viewport_with_minimum_inside_scroll(self):
        editor = self.scroll.split(HELPER, 1)[0]
        self.assertIn(".frame(height: max(120, viewport.size.height - helperHeight - 10))", editor)
        self.assertIn(".font(.title2).padding(8).scrollContentBackground(.hidden)", editor)
        self.assertIn(".frame(maxWidth: .infinity, alignment: .leading)", self.scroll)
        self.assertIn(".padding(16).background { Color.groupedBackground.ignoresSafeArea() }", self.view)
        # No minimum on the viewport: a very short landscape host must still clip/scroll.
        self.assertNotIn(".frame(minHeight:", self.view)
        for forbidden in ["UIScreen", "UIKeyboard", "UITextView", ".ignoresSafeArea(.keyboard",
                          ".safeAreaInset", ".scrollDisabled", ".minimumScaleFactor"]:
            self.assertNotIn(forbidden, self.view)

    def test_helper_keeps_exact_copy_and_uncompressed_intrinsic_height(self):
        helper = self.scroll.split(HELPER, 1)[1]
        for fragment in [".font(.footnote).foregroundStyle(.secondary)",
                         ".fixedSize(horizontal: false, vertical: true)",
                         ".padding(.horizontal, 4)",
                         "GeometryReader { helper in",
                         "Color.clear.preference(key: HelperHeightKey.self, value: helper.size.height)"]:
            self.assertIn(fragment, helper)
        self.assertIn("@State private var helperHeight: CGFloat = 0", self.view)
        self.assertIn(".onPreferenceChange(HelperHeightKey.self)", self.viewport)
        self.assertIn("if helperHeight != height { helperHeight = height }", self.viewport)
        for forbidden in [".lineLimit", ".truncationMode", ".hidden()", ".opacity(", ".frame(height:"]:
            self.assertNotIn(forbidden, helper)

    def test_existing_actions_and_bindings_remain(self):
        for fragment in ['@Binding var text: String',
                         'Button("Done") { dismiss() }',
                         'Button("Clear", systemImage: "trash", role: .destructive) { confirmClear = true }',
                         'UIPasteboard.general.string = text',
                         'copied = true',
                         '.confirmationDialog("Clear your scratchpad?", isPresented: $confirmClear, titleVisibility: .visible)',
                         'Button("Clear Scratchpad", role: .destructive) { text = "" }']:
            self.assertIn(fragment, self.view)
        self.assertEqual(self.view.count(".disabled(text.isEmpty)"), 2)


if __name__ == "__main__":
    unittest.main()
