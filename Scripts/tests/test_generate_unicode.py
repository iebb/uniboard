"""Download regression tests; no live requests or retry delays are required."""
import contextlib
import http.client
import importlib.util
import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    "generate_unicode", Path(__file__).resolve().parents[1] / "generate_unicode.py")
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class NamesListTests(unittest.TestCase):
    @staticmethod
    def record(name):
        return {"name": name, "aliases": [], "notes": []}

    def test_informative_group_heading_and_notice_apply_to_all_members_not_neighbors(self):
        records = {cp: self.record(f"HANGZHOU NUMERAL {cp - 0x3020}") for cp in range(0x3021, 0x302A)}
        records[0x302A] = self.record("IDEOGRAPHIC LEVEL TONE MARK")
        lines = ["@@\t3000\tCJK Symbols and Punctuation\t303F", "@\t\tSuzhou numerals",
                 '@+\t\tThe use of "HANGZHOU" in the names is a misnomer.']
        lines += [f"{cp:04X}\t{record['name']}" for cp, record in records.items() if cp < 0x302A]
        lines += ["@\t\tCombining tone marks", "302A\tIDEOGRAPHIC LEVEL TONE MARK"]
        generator.add_names_list(records, lines)
        for cp in range(0x3021, 0x302A):
            payload = generator.detail_payload(records[cp])
            self.assertEqual(payload["section"], "Suzhou numerals")
            self.assertIn("misnomer", payload["sectionAnnotations"][0])
            self.assertNotIn("aliases", payload)
            self.assertTrue(records[cp]["name"].startswith("HANGZHOU"))
        self.assertEqual(records[0x302A]["section"], "Combining tone marks")
        self.assertEqual(records[0x302A]["sectionNotes"], [])

    def test_character_notice_does_not_erase_references_or_leak_to_next_character(self):
        records = {cp: self.record(name) for cp, name in [(0x301C, "WAVE DASH"), (0x301D, "REVERSED DOUBLE PRIME QUOTATION MARK"), (0x3030, "WAVY DASH")]}
        generator.add_names_list(records, ["@@\t3000\tCJK Symbols and Punctuation\t303F", "@\t\tPunctuation",
            "301C\tWAVE DASH", "@+\t\tThis character matches JIS C 6226.", "\tx (wavy dash - 3030)",
            "301D\tREVERSED DOUBLE PRIME QUOTATION MARK"])
        self.assertEqual(records[0x301C]["notes"], ["This character matches JIS C 6226."])
        self.assertEqual(records[0x301C]["references"], [{"codePoint": 0x3030, "name": "WAVY DASH"}])
        self.assertEqual(records[0x301D]["notes"], [])
        self.assertEqual(records[0x301D]["sectionNotes"], [])

    def test_formal_alias_kinds_are_authoritative_and_informal_aliases_stay_distinct(self):
        records = {0xFE18: self.record("PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRAKCET"),
                   0xFEFF: self.record("ZERO WIDTH NO-BREAK SPACE"), 0x2603: self.record("SNOWMAN")}
        generator.add_name_aliases(records, ["FE18;PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRACKET;correction",
                                             "FEFF;BOM;abbreviation", "FEFF;ZWNBSP;abbreviation"])
        generator.add_names_list(records, ["@@\tFE00\tVariation Selectors\tFEFF", "FE18\tIGNORED CHART NAME",
            "\t% PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRACKET", "FEFF\tZERO WIDTH NO-BREAK SPACE",
            "\t= BOM, ZWNBSP", "2603\tSNOWMAN", "\t= snowy weather"])
        self.assertEqual(records[0xFE18]["aliases"][0]["kind"], "correction")
        self.assertEqual(len(records[0xFE18]["aliases"]), 1)
        self.assertTrue(records[0xFE18]["name"].endswith("BRAKCET"))
        self.assertEqual(len(records[0xFEFF]["aliases"]), 2)
        self.assertEqual(records[0x2603]["aliases"], [{"name": "snowy weather", "kind": "informal"}])

    def test_reserved_character_notice_and_new_block_do_not_pollute_neighbor_details(self):
        records = {0x0370: self.record("GREEK CAPITAL LETTER HETA"), 0x0400: self.record("CYRILLIC CAPITAL LETTER IE WITH GRAVE")}
        generator.add_names_list(records, ["@@\t0370\tGreek\t03FF", "@\t\tGreek letters",
            "0378\t<reserved>", "@+\t\tReserved-only warning.", "0370\tGREEK CAPITAL LETTER HETA",
            "@@\t0400\tCyrillic\t04FF", "0400\tCYRILLIC CAPITAL LETTER IE WITH GRAVE"])
        self.assertEqual(records[0x0370]["sectionNotes"], [])
        self.assertIsNone(records[0x0400]["section"])
        self.assertEqual(records[0x0400]["sectionNotes"], [])

    def test_unknown_formal_alias_kind_fails_instead_of_inventing_a_correction(self):
        with self.assertRaisesRegex(ValueError, "Unsupported formal name alias kind"):
            generator.add_name_aliases({0x3021: self.record("HANGZHOU NUMERAL ONE")}, ["3021;SUZHOU NUMERAL ONE;informal-correction"])


class DownloadTests(unittest.TestCase):
    URL = "https://raw.githubusercontent.com/unicode-org/unicodetools/pinned/UnicodeData.txt"

    @staticmethod
    def response(*, content=b"complete source", error=None):
        response = mock.MagicMock()
        response.__enter__.return_value = response
        if error is None:
            response.read.return_value = content
        else:
            response.read.side_effect = error
        return response

    def test_truncated_response_retries_and_returns_only_complete_source(self):
        partial = self.response(error=http.client.IncompleteRead(b"partial", 20))
        complete = self.response(content=b"complete source")
        with mock.patch.object(generator.urllib.request, "urlopen", side_effect=[partial, complete]) as open_url, \
                mock.patch.object(generator.time, "sleep") as sleep, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(generator.fetch(self.URL), b"complete source")
        self.assertEqual(open_url.call_count, 2)
        partial.__exit__.assert_called_once()
        complete.__exit__.assert_called_once()
        sleep.assert_called_once_with(1)
        for call in open_url.call_args_list:
            self.assertEqual(call.args[0].full_url, self.URL)
            self.assertEqual(call.kwargs["timeout"], 60)

    def test_transport_failures_retry_with_bounded_backoff(self):
        errors = [urllib.error.URLError("temporary network failure"),
                  ConnectionResetError("connection reset"),
                  TimeoutError("read timeout"), http.client.RemoteDisconnected("closed")]
        for error in errors:
            with self.subTest(error=type(error).__name__), \
                    mock.patch.object(generator.urllib.request, "urlopen",
                                      side_effect=[error, error, self.response()]) as open_url, \
                    mock.patch.object(generator.time, "sleep") as sleep, \
                    contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(generator.fetch(self.URL), b"complete source")
                self.assertEqual(open_url.call_count, 3)
                self.assertEqual(sleep.call_args_list, [mock.call(1), mock.call(2)])

    def test_transient_http_statuses_retry_and_cap_retry_after(self):
        for status in (429, 500, 502, 503, 504):
            with self.subTest(status=status):
                stream = io.BytesIO(b"unavailable")
                error = urllib.error.HTTPError(self.URL, status, "temporary", {"Retry-After": "120"}, stream)
                with mock.patch.object(generator.urllib.request, "urlopen",
                                       side_effect=[error, self.response()]) as open_url, \
                        mock.patch.object(generator.time, "sleep") as sleep, \
                        contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(generator.fetch(self.URL), b"complete source")
                self.assertEqual(open_url.call_count, 2)
                self.assertTrue(stream.closed)
                sleep.assert_called_once_with(generator.MAX_RETRY_DELAY)

    def test_permanent_http_failure_is_not_retried(self):
        stream = io.BytesIO(b"missing")
        error = urllib.error.HTTPError(self.URL, 404, "missing", {}, stream)
        with mock.patch.object(generator.urllib.request, "urlopen", side_effect=error) as open_url, \
                mock.patch.object(generator.time, "sleep") as sleep:
            with self.assertRaises(urllib.error.HTTPError) as raised:
                generator.fetch(self.URL)
        self.assertIs(raised.exception, error)
        self.assertTrue(stream.closed)
        open_url.assert_called_once()
        sleep.assert_not_called()

    def test_exhausted_refresh_preserves_existing_catalog_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / "Shared" / "Resources"
            resources.mkdir(parents=True)
            filenames = ["UnicodeCatalog.ucd", "Blocks.json", "UnicodeSources.json", "Unicode-LICENSE.txt"]
            originals = {name: ("previous " + name).encode() for name in filenames}
            for name, content in originals.items():
                (resources / name).write_bytes(content)
            partial = self.response(error=http.client.IncompleteRead(b"partial source", 30))
            with mock.patch.object(generator, "ROOT", root), \
                    mock.patch.object(generator, "resolve_source", return_value=(
                        "https://raw.githubusercontent.com/unicode-org/unicodetools/pinned/",
                        {"sourceKind": "unicode-development-draft"})), \
                    mock.patch.object(generator.sys, "argv", ["generate_unicode.py", "--source", "draft", "--refresh"]), \
                    mock.patch.object(generator.urllib.request, "urlopen", return_value=partial) as open_url, \
                    mock.patch.object(generator.time, "sleep") as sleep, \
                    contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(http.client.IncompleteRead):
                    generator.main()
            self.assertEqual(open_url.call_count, generator.FETCH_ATTEMPTS)
            self.assertEqual(sleep.call_args_list, [mock.call(1), mock.call(2)])
            self.assertFalse((root / ".unicode-cache" / "draft" / "ReadMe.txt").exists())
            for name, content in originals.items():
                self.assertEqual((resources / name).read_bytes(), content)

    def test_both_editions_validate_before_any_resource_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / "Shared" / "Resources"
            resources.mkdir(parents=True)
            originals = {name: ("old " + name).encode() for name in (
                "UnicodeCatalog.ucd", "UnicodeCatalog-latest.ucd", "UnicodeProperties.json",
                "UnicodeProperties-latest.json", "EmojiCatalog-draft.json", "EmojiCatalog-latest.json")}
            for name, content in originals.items():
                (resources / name).write_bytes(content)
            with mock.patch.object(generator, "ROOT", root), \
                    mock.patch.object(generator.sys, "argv", ["generate_unicode.py", "--source", "all", "--refresh"]), \
                    mock.patch.object(generator, "generate_catalog", side_effect=[
                        {"UnicodeCatalog-latest.ucd": b"new final edition"}, ValueError("invalid draft")]) as generate:
                with self.assertRaisesRegex(ValueError, "invalid draft"):
                    generator.main()
            self.assertEqual([call.args[0] for call in generate.call_args_list], ["latest", "draft"])
            for name, content in originals.items():
                self.assertEqual((resources / name).read_bytes(), content)

    def test_latest_release_resolves_final_version_to_immutable_directory(self):
        with mock.patch.object(generator, "fetch", return_value=b"This directory contains final data files for version 18.0.0 of the Unicode Character Database."):
            base, provenance = generator.resolve_source("latest")
        self.assertEqual(base, "https://www.unicode.org/Public/18.0.0/ucd/")
        self.assertEqual(provenance["sourceKind"], "unicode-release")
        with mock.patch.object(generator, "fetch", return_value=b"This directory contains draft data files for version 19.0.0"):
            with self.assertRaisesRegex(ValueError, "not an official final release"):
                generator.resolve_source("latest")

    def test_numeric_versions_do_not_use_lexicographic_sorting(self):
        self.assertGreater(generator.version_key("10.0"), generator.version_key("9.0"))
        self.assertGreater(generator.version_key("15.1"), generator.version_key("15.0"))

    def test_draft_pins_repository_head_so_emoji_only_changes_are_included(self):
        sha = "a" * 40
        commit = [{"sha": sha, "commit": {"committer": {"date": "2026-10-03T00:00:00Z"}}}]
        with mock.patch.object(generator, "fetch", return_value=json.dumps(commit).encode()) as fetch:
            base, provenance = generator.resolve_source("draft")
        fetch.assert_called_once_with("https://api.github.com/repos/unicode-org/unicodetools/commits?per_page=1")
        self.assertIn(sha + "/unicodetools/data/ucd/dev/", base)
        self.assertEqual(provenance["sourceCommit"], sha)
        self.assertIn(sha + "/unicodetools/data/emoji/dev/", base.replace("/ucd/dev/", "/emoji/dev/"))


if __name__ == "__main__":
    unittest.main()
