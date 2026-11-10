"""Fast source-contract checks; no builds, network requests or corpus compilation.

Run: python3 Tests/test_language_optional_download_contract.py
Swift catalog/transport behavior is covered by LanguagePackCatalogTests.swift.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class LanguageOptionalDownloadContractTests(unittest.TestCase):
    def test_all_five_original_pins_and_exact_total(self):
        compiler = source("Shared/MandarinDictionaryCompiler.swift")
        actual = re.findall(
            r'public static let (\w+) = resource\("([^"]+)", ([\d_]+),\s*"([a-f0-9]{64})"',
            compiler,
        )
        self.assertEqual(actual, [
            ("jichu", "jichu.dict.yaml", "48_469_368", "74abd0a8013d5bbc0f397280fa0949d83234f005690e1631786e9ba9b466a74e"),
            ("zi", "zi.dict.yaml", "616_550", "dbb68f8b4ef93e48bf3632b3c4bc00b810c6bbb2e101635d6e14752444abe7c9"),
            ("characters", "TSCharacters.txt", "104_516", "737c21c66f55a419dd6956cb3089476cdefc5a36877452631617696df1e5d925"),
            ("phrases", "TSPhrases.txt", "8_786", "362fa1b9a7d6edd04b462a32e12c9fef3adae822ab1dee9c83561cc37c06cb1f"),
            ("compatibility", "CJK_Compatibility_Ideographs.txt", "39_074", "663cc10b7de7c7cee3ff9df1ee963977d6c26c00b23f8fe670fab481283ed4f9"),
        ])
        self.assertEqual(sum(int(row[2].replace("_", "")) for row in actual), 49_238_294)
        self.assertIn('corpusCommit = "aa9947f3f513ff88a3f7ce4e342fcb519d517025"', compiler)
        self.assertIn('mappingCommit = "26753884f1984add422f3b0249ccee8613deaff6"', compiler)

    def test_catalog_downloads_every_input_and_checks_identity_and_order(self):
        catalog = source("App/LanguagePackCatalog.swift")
        resources = between(catalog, "static let mandarinResources = [", "]")
        self.assertEqual(re.findall(r"MandarinDictionaryCompiler\.(\w+)", resources),
                         ["jichu", "zi", "characters", "phrases", "compatibility"])
        construction = between(catalog, "let files = mandarinResources.map", "let wanxiang")
        self.assertIn("SourceFile(name: resource.filename", construction)
        self.assertNotIn("isBundled:", construction)
        self.assertIn("isBundled: Bool = false", catalog)
        self.assertNotIn("mandarinFiles.filter", catalog)
        self.assertIn("49,238,294 bytes for all five optional files", catalog)
        validation = catalog.split("func validatedMandarinSourceDescriptors()", 1)[1]
        for check in ["mandarinFiles.count == Self.mandarinResources.count",
                      "zip(mandarinFiles, Self.mandarinResources)", "!file.isBundled",
                      "file.name == resource.filename", "file.url == resource.downloadURL",
                      "file.bytes == Int64(resource.bytes)", "file.sha256 == resource.sha256",
                      "try source.validate()"]:
            self.assertIn(check, validation)

    def test_worker_downloads_then_compiles_downloaded_mapping_urls_only(self):
        worker = source("App/LanguageManagementModel.swift").split("private actor LanguageManagementWorker", 1)[1]
        download = between(worker, "func downloadMandarin(", "private static func payloadFile")
        self.assertNotIn("Bundle", download)
        self.assertNotIn("bundledMapping", download)
        ordered = ["try catalog.validatedMandarinSourceDescriptors()",
                   "LanguagePackDownloader(trustedSources: sources)", "for source in sources",
                   "try await downloader.download(source: source, scratchDirectory: scratch)",
                   "downloadedFiles.append(url)", "characters: downloadedFiles[2]",
                   "phrases: downloadedFiles[3]", "compatibility: downloadedFiles[4]",
                   "MandarinDictionaryCompiler.compile(jichuURL: downloadedFiles[0], ziURL: downloadedFiles[1]",
                   "let primary = sources[0]", "sourceURL: primary.sourceURL",
                   "archiveByteCount: primary.archiveByteCount, archiveSHA256: primary.archiveSHA256",
                   "store.install(manifestData:"]
        positions = [download.index(fragment) for fragment in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("Task.checkCancellation()", download)
        self.assertIn("expectedRevision: expectedRevision", download)
        self.assertIn("isCancelled: { Task.isCancelled }", download)
        self.assertIn("49,238,294 bytes for five optional files", download)

    def test_refresh_selection_and_enable_do_not_start_downloads(self):
        model = source("App/LanguageManagementModel.swift")
        ui = model.split("private actor LanguageManagementWorker", 1)[0]
        # Network entry points remain the explicit Japanese/Mandarin Download actions.
        self.assertEqual(ui.count("await worker.downloadMandarin("), 1)
        self.assertEqual(ui.count("await worker.downloadJapanese("), 1)
        for start, end in [("func refresh()", "func setEnabled("),
                           ("func setEnabled(", "func downloadJapanese()")]:
            self.assertNotIn("worker.download", between(ui, start, end))
        snapshot = between(model, "func snapshot()", "func save(_ change:")
        self.assertNotIn("download(", snapshot)
        self.assertNotIn("Downloader(", snapshot)
        self.assertIn("settings.load()", snapshot)
        self.assertNotIn("settings.save", snapshot)


if __name__ == "__main__":
    unittest.main()
