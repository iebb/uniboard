"""Focused source wiring checks for active-only keyboard resources (no build/network).

Run: python3 Tests/test_keyboard_active_resources.py
Filesystem/hash behavior is exercised by LanguagePackStoreTests.swift on macOS.
These checks do not claim to exercise actor scheduling or converter lifetimes.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (text[cursor] == "{") - (text[cursor] == "}")
        cursor += 1
    return text[start:cursor]


class KeyboardActiveResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.coordinator = source("Keyboard/KeyboardLanguageCoordinator.swift")
        cls.store = source("Shared/LanguagePackStore.swift")

    def test_chooser_only_inspects_bounded_metadata(self):
        choices = block(self.coordinator, "    func availableModes(")
        self.assertIn("store.publishedMetadata(", choices)
        self.assertIn("matchesReference(metadata.descriptor", choices)
        for forbidden in ("store.resolve(", "LanguageConverter(", "refreshIndex("):
            self.assertNotIn(forbidden, choices)
        metadata = block(self.store, "    public func publishedMetadata(")
        for required in ("pointer(modeID:", "LanguagePackDescriptor.validated(",
                         "descriptor.engineABI == engineABI", "for file in descriptor.files",
                         "Self.info(url)", "attributes.st_nlink == 1"):
            self.assertIn(required, metadata)
        for forbidden in ("verifyPayload(", "verifyFile(", "contentsOfDirectory(",
                          "LanguagePackReadLease(", "Data(contentsOf:"):
            self.assertNotIn(forbidden, metadata)

    def test_direct_is_guarded_before_every_refresh_or_validation_index_open(self):
        refresh = block(self.coordinator, "    func refreshResources() async")
        active = block(refresh, "        if mode != .direct {")
        self.assertIn("indexDirectory()", active)
        self.assertIn("worker.refreshIndex(", active)
        self.assertEqual(refresh.count("indexDirectory()"), 1)
        self.assertNotIn("checkDictionary: true", refresh)
        revalidate = block(self.coordinator, "    private func revalidateResources(")
        self.assertLess(revalidate.index("guard mode != .direct"),
                        revalidate.index("indexDirectory()"))
        legacy = block(self.coordinator, "    func englishCustomOutputs(")
        self.assertLess(legacy.index("guard mode != .direct"), legacy.index("indexDirectory()"))

    def test_index_is_operation_local_and_cancelled_work_cannot_publish(self):
        worker = self.coordinator.split("private actor KeyboardLanguageResourceWorker", 1)[1]
        self.assertNotIn("private var index:", worker)
        self.assertNotIn("private var directory:", worker)
        for name in ("    func refreshIndex(", "    func lookup("):
            operation = block(worker, name)
            self.assertLess(operation.index("!Task.isCancelled"),
                            operation.index("CustomInputDictionaryIndex(directory:"))
        lookup = block(worker, "    func lookup(")
        self.assertIn("index.revision == expectedRevision", lookup)
        refresh = block(self.coordinator, "    func refreshResources() async")
        self.assertIn("refreshID == id, activationID == activation, mode == selected", refresh)
        self.assertIn("!task.isCancelled", refresh)
        stop = block(self.coordinator, "    private func stopWork()")
        self.assertIn("indexRefreshTask?.cancel()", stop)
        self.assertIn("activationID = UUID()", stop)

    def test_activation_initializes_current_dictionary_and_still_fully_verifies(self):
        activation = block(self.coordinator, "    private func beginActivation()")
        ordered = ("guard mode == .japaneseRomaji || mode == .mandarinPinyin",
                   "worker.refreshIndex(directory:", "self.activationID == id, self.mode == selected",
                   "self.updateDictionary(revision, directory:", "worker.activate(mode:",
                   "guard self.activationID == id, self.mode == selected",
                   "activeRevision(modeID: selected.rawValue) == lease.pack.revision",
                   "Self.matchesReference(lease.pack.descriptor", "self.owner =")
        positions = [activation.index(fragment) for fragment in ordered]
        self.assertEqual(positions, sorted(positions))
        worker_activation = block(self.coordinator, "    func activate(mode:")
        self.assertIn(".resolve(modeID:", worker_activation)
        resolve = block(self.store, "    public func resolve(")
        self.assertIn("Self.verifyPayload(payload, descriptor: descriptor)", resolve)
        self.assertIn("verifyFile(url, byteCount: file.byteCount, sha256: file.sha256)",
                      block(self.store, "    private static func verifyPayload("))

    def test_refresh_preserves_composition_and_commit_rechecks_publication(self):
        refresh = block(self.coordinator, "    func refreshResources() async")
        self.assertNotIn("state.cancel()", refresh)
        self.assertNotIn("state.changeDocument(", refresh)
        self.assertIn("!hasComposition", refresh)
        commit = block(self.coordinator, "    private func validateForCommit(")
        self.assertIn("state.token == expected", commit)
        self.assertIn("anchorIsValid()", commit)
        self.assertIn("revalidateResources(checkDictionary: true)", commit)
        revalidate = block(self.coordinator, "    private func revalidateResources(")
        self.assertIn("activeRevision(modeID: mode.rawValue) == state.packRevision", revalidate)
        self.assertIn("revokeActiveResource(status:", revalidate)
        conversion = block(self.coordinator, "    private func scheduleConversion()")
        self.assertIn("defer { withExtendedLifetime(owner) {} }", conversion)
        self.assertIn("self.state.token == request.token", conversion)
        select = block(self.coordinator, "    func select(")
        self.assertLess(select.index("stopWork()"), select.index("owner = nil"))
        self.assertLess(select.index("owner = nil"), select.index("state.changeMode(to: selected)"))


if __name__ == "__main__":
    unittest.main()
