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
