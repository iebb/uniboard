"""Download regression tests; no live requests or retry delays are required."""
import contextlib
import http.client
import importlib.util
import io
import json
import os
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


class SourceValidationTests(unittest.TestCase):
    @staticmethod
    def row(code="0041", name="LATIN CAPITAL LETTER A", category="Lu", **changes):
        fields = [code, name, category, "0", "L", "", "", "", "", "N", "", "", "", "", ""]
        for index, value in changes.items():
            fields[int(index.removeprefix("f"))] = value
        return ";".join(fields)

    def test_span_rejects_descending_out_of_range_and_extra_endpoints(self):
        for value in ["0042..0041", "110000", "0041..0042..0043", "-1", "+0041", "0041..", ""]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                generator.span(value)
        self.assertEqual(generator.span("10FFFE..10FFFF"), (0x10FFFE, 0x10FFFF))
        self.assertEqual(generator.span("D800..DFFF"), (0xD800, 0xDFFF))  # Blocks/Age contain code units too.

    def test_unicode_data_duplicate_unsorted_and_invalid_scalars_fail_closed(self):
        rows = [self.row(), self.row("0061", "LATIN SMALL LETTER A", "Ll")]
        self.assertEqual(len(list(generator.unicode_data_rows(rows))), 2)
        for invalid in [rows + [rows[0]], rows[::-1], [self.row("110000")], [self.row("D800")], []]:
            with self.subTest(rows=invalid), self.assertRaises(ValueError):
                list(generator.unicode_data_rows(invalid))

    def test_unicode_data_first_last_pair_identity_and_completion_are_required(self):
        first = self.row("AC00", "<Hangul Syllable, First>", "Lo")
        last = self.row("D7A3", "<Hangul Syllable, Last>", "Lo")
        self.assertEqual(len(list(generator.unicode_data_rows([first, last]))), 2)
        for rows in [[first], [last], [first, self.row("D7A3", "<CJK Ideograph, Last>", "Lo")],
                     [first, self.row("AC01", "<Other, First>", "Lo"), last],
                     [first, self.row("AC01", "HANGUL SYLLABLE GAG", "Lo"), last]]:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                list(generator.unicode_data_rows(rows))

    def test_truncated_and_invalid_normative_property_rows_are_rejected(self):
        rows = [self.row().rsplit(";", 1)[0], self.row(f3="256"), self.row(f4="Bogus"),
                self.row(category="Bogus"), self.row(f12="D800"), self.row(f5="<font> 110000")]
        for row in rows:
            with self.subTest(row=row), self.assertRaises(ValueError):
                list(generator.unicode_data_rows([row]))

    def test_version_keys_reject_ambiguous_or_unrepresentable_numbers(self):
        self.assertEqual(generator.version_key("15.1 draft"), 1501)
        self.assertEqual(generator.version_key("18.0.0"), 1800)
        for version in ["-1.0", "18.100", "18..0", "18.zero", str(2**63 - 1) + ".0"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                generator.version_key(version)

    def test_empty_or_invalid_aliases_never_become_metadata(self):
        records = {0x41: {"name": "A", "aliases": [], "notes": []}}
        for line in ["0041;;alternate", "110000;Bad;alternate", "D800;Bad;alternate", "+0041;Bad;alternate"]:
            with self.subTest(line=line), self.assertRaises(ValueError):
                generator.add_name_aliases(records, [line])

    def test_real_cached_editions_still_satisfy_unicode_data_validation(self):
        # No network: independently verify that stricter range validation accepts
        # every cached official snapshot, including surrogate code units.
        root = Path(__file__).resolve().parents[2]
        checked = 0
        for source in ("latest", "previous", "older", "draft"):
            path = root / ".unicode-cache" / source / "UnicodeData.txt"
            if path.exists():
                self.assertGreater(len(list(generator.unicode_data_rows(path.read_text("utf-8").splitlines()))), 40000)
                checked += 1
        if checked == 0:
            self.skipTest("Official local source cache is absent; injected normative-source tests still run")


class ArtifactTransactionTests(unittest.TestCase):
    def test_stage_failure_never_changes_any_original(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Resources"
            output.mkdir()
            (output / "A").write_bytes(b"old A")
            original = generator.atomic_write
            def write(path, content):
                if path.name == "B":
                    raise OSError("fixture disk full")
                return original(path, content)
            with mock.patch.object(generator, "atomic_write", side_effect=write):
                with self.assertRaises(OSError):
                    generator.replace_artifacts(output, {"A": b"new A", "B": b"new B"})
            self.assertEqual((output / "A").read_bytes(), b"old A")
            self.assertFalse((output / "B").exists())

    def test_commit_failure_or_cancellation_restores_replaced_files_and_removes_new_ones(self):
        for error in [OSError("fixture replace failed"), KeyboardInterrupt()]:
            with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "Resources"
                output.mkdir()
                (output / "A").write_bytes(b"old A")
                original = os.replace
                def replace(source, target):
                    if Path(target) == output / "B":
                        raise error
                    return original(source, target)
                with mock.patch.object(generator.os, "replace", side_effect=replace):
                    with self.assertRaises(type(error)):
                        generator.replace_artifacts(output, {"new": b"new file", "A": b"new A", "B": b"new B"})
                self.assertEqual((output / "A").read_bytes(), b"old A")
                self.assertEqual(sorted(path.name for path in output.iterdir()), ["A"])

    def test_success_replaces_exact_artifacts_without_touching_unrelated_files(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Resources"
            output.mkdir()
            (output / "unrelated").write_bytes(b"preserved")
            generator.replace_artifacts(output, {"A": b"new A", "B": b"new B"})
            self.assertEqual((output / "A").read_bytes(), b"new A")
            self.assertEqual((output / "B").read_bytes(), b"new B")
            self.assertEqual((output / "unrelated").read_bytes(), b"preserved")

    def test_rollback_failure_attempts_remaining_restores_and_preserves_recovery_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Resources"
            output.mkdir()
            (output / "A").write_bytes(b"old A")
            (output / "C").write_bytes(b"old C")
            original_replace, original_unlink = os.replace, Path.unlink
            restored = []
            def replace(source, target):
                source, target = Path(source), Path(target)
                if target == output / "B":
                    raise OSError("fixture commit failure")
                if source.parent.name == "old":
                    restored.append(target.name)
                    if target == output / "C":
                        raise OSError("fixture restore failure")
                return original_replace(source, target)
            def unlink(path, *args, **kwargs):
                if path == output / "new":
                    raise OSError("fixture new-file removal failure")
                return original_unlink(path, *args, **kwargs)
            with mock.patch.object(generator.os, "replace", side_effect=replace), \
                    mock.patch.object(Path, "unlink", autospec=True, side_effect=unlink):
                with self.assertRaisesRegex(RuntimeError, "recovery files retained at"):
                    generator.replace_artifacts(output, {"A": b"new A", "C": b"new C", "new": b"new file", "B": b"not committed"})
            # Failure removing a new file and restoring C must not skip A.
            self.assertEqual(restored, ["C", "A"])
            self.assertEqual((output / "A").read_bytes(), b"old A")
            self.assertEqual((output / "C").read_bytes(), b"new C")
            stages = list(Path(directory).glob(".unicode-artifacts-*"))
            self.assertEqual(len(stages), 1)
            self.assertEqual((stages[0] / "old" / "C").read_bytes(), b"old C")
            recovery = json.loads((stages[0] / "RECOVERY.json").read_text())
            self.assertEqual(recovery, {"unrecoveredTargets": ["new", "C"], "originallyAbsent": ["new"]})


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
                    mock.patch.object(generator, "edition_labels", return_value={"latest": "18.0.0", "previous": "17.0.0", "older": "16.0.0"}), \
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

    def test_only_the_draft_is_generated_and_labelled_with_three_final_editions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            labels = {"latest": "18.0.0", "previous": "17.0.0", "older": "16.0.0"}
            with mock.patch.object(generator, "ROOT", root), \
                    mock.patch.object(generator.sys, "argv", ["generate_unicode.py", "--source", "all", "--refresh"]), \
                    mock.patch.object(generator, "edition_labels", return_value=labels), \
                    mock.patch.object(generator, "generate_catalog", return_value={"UnicodeCatalog.ucd": b"draft"}) as generate, \
                    mock.patch.object(generator, "replace_artifacts") as replace:
                generator.main()
            generate.assert_called_once()
            self.assertEqual(generate.call_args.args[0], "draft")
            self.assertEqual(generate.call_args.kwargs["slot"], "draft")
            self.assertEqual(generate.call_args.kwargs["editions"], labels)
            self.assertIn("UnicodeCatalog.ucd", replace.call_args.args[1])

    def test_edition_labels_follow_the_latest_final_release(self):
        for latest, expected in [("18.0.0", ("17.0.0", "16.0.0")), ("19.0.0", ("18.0.0", "17.0.0"))]:
            resolved = (f"https://www.unicode.org/Public/{latest}/ucd/", {"sourceKind": "unicode-release"})
            with self.subTest(latest=latest), mock.patch.object(generator, "resolve_source", return_value=resolved) as resolve:
                self.assertEqual(generator.edition_labels(),
                                 {"latest": latest, "previous": expected[0], "older": expected[1]})
                resolve.assert_called_once_with("latest")
        for base in ["https://example.invalid/18.0.0/", "https://www.unicode.org/Public/2.0.0/ucd/"]:
            with mock.patch.object(generator, "resolve_source", return_value=(base, {})), self.assertRaises(ValueError):
                generator.edition_labels()

    def test_historical_emoji_archive_is_versioned_independently_before_unicode_17(self):
        provenance = {"sourceKind": "unicode-release"}
        self.assertEqual(generator.emoji_source_base("https://www.unicode.org/Public/16.0.0/ucd/", provenance),
                         "https://www.unicode.org/Public/emoji/16.0/")
        self.assertEqual(generator.emoji_source_base("https://www.unicode.org/Public/17.0.0/ucd/", provenance),
                         "https://www.unicode.org/Public/17.0.0/emoji/")
        self.assertEqual(generator.emoji_source_base("https://raw.githubusercontent.com/commit/ucd/dev/", {"sourceKind": "unicode-development-draft"}),
                         "https://raw.githubusercontent.com/commit/emoji/dev/")
        with self.assertRaises(ValueError):
            generator.emoji_source_base("https://example.invalid/ucd/", provenance)

    def test_latest_release_resolves_final_version_to_immutable_directory(self):
        with mock.patch.object(generator, "fetch", return_value=b"This directory contains final data files for version 18.0.0 of the Unicode Character Database."):
            base, provenance = generator.resolve_source("latest")
        self.assertEqual(base, "https://www.unicode.org/Public/18.0.0/ucd/")
        self.assertEqual(provenance["sourceKind"], "unicode-release")
        with mock.patch.object(generator, "fetch", return_value=b"This directory contains draft data files for version 19.0.0"):
            with self.assertRaisesRegex(ValueError, "not an official final release"):
                generator.resolve_source("latest")

    def test_presentation_sequences_need_both_styles_and_fail_closed(self):
        lines = ["# emoji-variation-sequences.txt", "",
                 "0023 FE0E  ; text style;  # (1.1) NUMBER SIGN",
                 "0023 FE0F  ; emoji style; # (1.1) NUMBER SIGN",
                 "2603 FE0F  ; emoji style; # (1.1) SNOWMAN",
                 "2603 FE0E  ; text style;  # (1.1) SNOWMAN",
                 "1F004 FE0E ; text style;  # (5.1) MAHJONG TILE RED DRAGON"]
        assigned = lambda cp: True
        self.assertEqual(generator.presentation_sequences(lines, assigned), [0x23, 0x2603])
        for bad in ["0023 FE0F  ; text style;", "0023 FE0E ; emoji style;", "0023 FE00 ; text style;",
                    "0023 ; text style;", "zz FE0E ; text style;"]:
            with self.assertRaises(ValueError, msg=bad):
                generator.presentation_sequences(lines + [bad], assigned)
        with self.assertRaises(ValueError):
            generator.presentation_sequences(lines + ["0023 FE0E ; text style;"], assigned)
        with self.assertRaises(ValueError):
            generator.presentation_sequences(lines, lambda cp: cp != 0x2603)
        with self.assertRaises(ValueError):
            generator.presentation_sequences(["1F004 FE0E ; text style;"], assigned)

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
