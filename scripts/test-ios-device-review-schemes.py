#!/usr/bin/env python3
"""Guard the generated, manual Debug fixture profiles and normal launch boundary."""
import json
import shlex
import subprocess
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parents[1]
SCHEMES = ROOT / "merian.xcodeproj/xcshareddata/xcschemes"
PROFILES = {
    "History": {"-seedPrivateScanMapFlow", "-seedIdentificationHistory"},
    "Community Photos": {"-seedPublicationConsentChooser"},
    "Species Name": {"-seedPublicationConsentChooser", "-seedSelectedNameConfirmation"},
    "Chat Pending": {"-seedProtectedInsightChat"},
    "Chat Refresh": {"-seedProtectedChatStale"},
    "Reanalysis Guard": {"-seedPrivateScanMapFlow", "-seedSavedReanalysisFailure"},
}
COMMON = {"-skipOnboarding", "-seedCurrentRequiredConsent",
          "-seedLocationPermissionPromptSuppressed", "-mockCameraFeed",
          "-hasCompletedOnboarding", "YES"}


class DeviceReviewSchemes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e",
             'puts JSON.generate(YAML.safe_load(File.read(ARGV.first), aliases: true).fetch("schemes"))',
             str(ROOT / "project.yml")],
            check=True, capture_output=True, text=True,
        )
        cls.manifest = json.loads(result.stdout)

    def test_every_profile_is_debug_with_isolated_test_environment(self):
        namespaces = set()
        for name in PROFILES:
            with self.subTest(profile=name):
                launch = ET.parse(SCHEMES / f"Merian Device - {name}.xcscheme").find("LaunchAction")
                self.assertIsNotNone(launch)
                self.assertEqual(launch.get("buildConfiguration"), "Debug")
                env = {e.get("key"): e.get("value") for e in launch.findall("EnvironmentVariables/EnvironmentVariable") if e.get("isEnabled") == "YES"}
                self.assertEqual(set(env), {"UITesting", "UITestKeychainNamespace"})
                self.assertEqual(env["UITesting"], "true")
                self.assertEqual(str(UUID(env["UITestKeychainNamespace"])), env["UITestKeychainNamespace"])
                namespaces.add(env["UITestKeychainNamespace"])
                source = self.manifest[f"Merian Device - {name}"]
                self.assertEqual(source["run"]["config"], "Debug")
                self.assertEqual(source["run"]["environmentVariables"], env)
                self.assertEqual(source["profile"]["config"], "Debug")
                profile = ET.parse(SCHEMES / f"Merian Device - {name}.xcscheme").find("ProfileAction")
                self.assertEqual(profile.get("buildConfiguration"), "Debug")
                self.assertEqual(profile.get("shouldUseLaunchSchemeArgsEnv"), "YES")
                target = launch.find("BuildableProductRunnable/BuildableReference")
                self.assertEqual(target.get("BlueprintName"), "Merian")
        self.assertEqual(len(namespaces), len(PROFILES))

    def test_each_profile_has_only_its_existing_guided_fixture_arguments(self):
        for name, scenario in PROFILES.items():
            with self.subTest(profile=name):
                launch = ET.parse(SCHEMES / f"Merian Device - {name}.xcscheme").find("LaunchAction")
                args = [part for e in launch.findall("CommandLineArguments/CommandLineArgument") if e.get("isEnabled") == "YES" for part in shlex.split(e.get("argument"))]
                source = self.manifest[f"Merian Device - {name}"]["run"]["commandLineArguments"]
                self.assertTrue(all(value is True for value in source.values()))
                source_args = [part for arg in source for part in shlex.split(arg)]
                self.assertEqual(sorted(source_args), sorted(args))
                self.assertEqual(set(args), COMMON | scenario)
                self.assertEqual(len(args), len(COMMON | scenario))
                self.assertEqual(args[args.index("-hasCompletedOnboarding") + 1], "YES")

    def test_normal_scheme_has_no_fixture_environment_or_arguments(self):
        launch = ET.parse(SCHEMES / "Merian.xcscheme").find("LaunchAction")
        self.assertNotIn("UITesting", [e.get("key") for e in launch.findall("EnvironmentVariables/EnvironmentVariable")])
        self.assertEqual(launch.findall("CommandLineArguments/CommandLineArgument"), [])
        composition = (ROOT / "apps/ios/Merian/App/Composition/PreparedHistoryReanalysisComposition.swift").read_text()
        self.assertIn("static let isAppInstallationQualified = false", composition)


if __name__ == "__main__":
    unittest.main()
