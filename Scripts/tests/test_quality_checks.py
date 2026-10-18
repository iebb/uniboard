import copy
import importlib.util
import pathlib
import tempfile
import unittest


def load_script(name):
    path = pathlib.Path(__file__).resolve().parent.parent / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


coverage = load_script("check_swift_coverage")
destination = load_script("select_ios_test_destination")


class CoverageCheckTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.files = [{"filename": str(self.root / "Shared" / name),
                       "summary": {"lines": {"covered": 100, "count": 100}}}
                      for name in coverage.MINIMUMS]

    def evaluate(self, files):
        return coverage.evaluate({"data": [{"files": files}]}, root=self.root)

    def testShippedFilesMeetTheirOwnThresholds(self):
        output, failures = self.evaluate(self.files)
        self.assertEqual(len(output), len(coverage.MINIMUMS))
        self.assertEqual(failures, [])

    def testLowCoverageCannotHideBehindFullyCoveredTests(self):
        catalog = next(item for item in self.files
                       if pathlib.Path(item["filename"]).name == "UnicodeCatalog.swift")
        catalog["summary"]["lines"]["covered"] = 89
        self.files.append({"filename": str(self.root / "Tests" / "ManyTests.swift"),
                           "summary": {"lines": {"covered": 100000, "count": 100000}}})
        self.assertEqual(self.evaluate(self.files)[1], ["UnicodeCatalog.swift"])

    def testMissingDuplicateOrImposterPathsFailClosed(self):
        for files in [self.files[:-1], self.files + [self.files[0]],
                      [dict(item, filename=item["filename"].replace("/Shared/", "/Tests/"))
                       for item in self.files]]:
            with self.subTest(files=files), self.assertRaises(ValueError):
                self.evaluate(files)

    def testZeroInvalidAndNonIntegerCountsAreRejected(self):
        for count, covered in [(0, 0), (100, 101), (100, -1), (True, 1), (100, 99.0), (None, None)]:
            files = copy.deepcopy(self.files)
            files[0]["summary"]["lines"] = {"covered": covered, "count": count}
            with self.subTest(count=count, covered=covered), self.assertRaises(ValueError):
                self.evaluate(files)

    def testMalformedReportsDoNotBypassCoverage(self):
        for value in [None, [], {}, {"data": {}}, {"data": [None]}, {"data": [{"files": [None]}]}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                coverage.evaluate(value, root=self.root)


class SimulatorDestinationTests(unittest.TestCase):
    first = "11111111-1111-4111-8111-111111111111"
    second = "22222222-2222-4222-8222-222222222222"

    def inventory(self):
        return {"runtimes": [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5", "version": "18.5", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2", "version": "26.2", "isAvailable": True}],
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [{"name": "iPhone 16 Pro", "udid": self.first, "isAvailable": True}],
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [{"name": "iPhone 17 Pro", "udid": self.second, "isAvailable": True}]}}

    def testLatestAvailablePhoneIsSelectedNumerically(self):
        self.assertEqual(destination.select_destination(self.inventory()),
                         "platform=iOS Simulator,id=" + self.second.upper())

    def testUnavailableLatestRuntimeAndInvalidDevicesFallBack(self):
        inventory = self.inventory()
        inventory["runtimes"][1]["isAvailable"] = False
        self.assertTrue(destination.select_destination(inventory).endswith(self.first.upper()))
        inventory = self.inventory()
        inventory["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-26-2"] = [
            {"name": "iPhone broken", "udid": "bad;echo unsafe", "isAvailable": True},
            {"name": "iPhone null", "udid": None, "isAvailable": True},
            {"name": "iPad Pro", "udid": self.second, "isAvailable": True}, None]
        self.assertTrue(destination.select_destination(inventory).endswith(self.first.upper()))

    def testMissingPhonesAndMalformedInventoriesFailClearly(self):
        for inventory in [None, {}, {"runtimes": [], "devices": {}},
                          {"runtimes": [None, {"identifier": 1, "version": None, "isAvailable": True}], "devices": {}}]:
            with self.subTest(inventory=inventory), self.assertRaises(ValueError):
                destination.select_destination(inventory)


if __name__ == "__main__":
    unittest.main()
