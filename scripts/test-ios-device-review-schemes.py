#!/usr/bin/env python3
"""Guard the generated, manual Debug fixture profiles and normal launch boundary."""
import json
import os
import importlib.util
import sys
import tempfile
import plistlib
import shlex
import subprocess
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from uuid import UUID

RUN_COMPILED = "--swift-qualification" in sys.argv
if RUN_COMPILED:
    sys.argv.remove("--swift-qualification")
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
             'puts JSON.generate(YAML.safe_load(File.read(ARGV.first), aliases: true))',
             str(ROOT / "project.yml")],
            check=True, capture_output=True, text=True,
        )
        cls.project = json.loads(result.stdout)
        cls.manifest = cls.project["schemes"]

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

    def test_qualification_scheme_has_no_debug_fixture_or_runtime_override(self):
        scheme = ET.parse(SCHEMES / "HistoryQualification.xcscheme")
        for action in ["LaunchAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"]:
            node = scheme.find(action)
            self.assertEqual(node.get("buildConfiguration"), "HistoryQualification")
            self.assertEqual(node.findall("CommandLineArguments/CommandLineArgument"), [])
            self.assertEqual(node.findall("EnvironmentVariables/EnvironmentVariable"), [])
        self.assertEqual(self.project["configs"]["HistoryQualification"], "release")
        flags = self.project["settings"]["configs"]["HistoryQualification"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
        self.assertIn("MERIAN_HISTORY_QUALIFICATION", flags)
        self.assertNotIn("DEBUG", flags)
        for config in ["Debug", "Release"]:
            self.assertNotIn("MERIAN_HISTORY_QUALIFICATION", str(self.project["settings"].get("configs", {}).get(config, {})))

    def test_history_testing_uses_primary_oauth_without_qualification_or_fixtures(self):
        self.assertEqual(self.project["configs"]["HistoryTesting"], "release")
        settings = self.project["settings"]["configs"]["HistoryTesting"]
        self.assertEqual(settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"], "$(inherited) MERIAN_HISTORY_NORMAL_OAUTH MERIAN_HISTORY_LOCAL_DIAGNOSTICS")
        self.assertEqual(str(settings["MERIAN_HISTORY_NORMAL_OAUTH"]), "1")
        for name in ["Merian", "MerianExploreWidget", "MerianMessagesExtension"]:
            self.assertEqual(self.project["targets"][name]["configFiles"]["HistoryTesting"], "Config.xcconfig")
        scheme = ET.parse(SCHEMES / "HistoryTesting.xcscheme")
        for action in ["LaunchAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"]:
            node = scheme.find(action)
            self.assertEqual(node.get("buildConfiguration"), "HistoryTesting")
            self.assertEqual(node.findall("CommandLineArguments/CommandLineArgument"), [])
            self.assertEqual(node.findall("EnvironmentVariables/EnvironmentVariable"), [])
        for trigger in [{"ACTION": "install"}, {"DEPLOYMENT_LOCATION": "YES"}, {"ARCHIVE_PRODUCTS_PATH": "/synthetic/archive"}]:
            result = subprocess.run(["bash", str(ROOT / "scripts/check-ios-release-prep.sh")],
                env={"PATH": os.environ["PATH"], "CONFIGURATION": "HistoryTesting", **trigger}, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"HistoryTesting archive and distribution are disabled", result.stderr)

    def test_release_enables_only_main_app_and_excludes_local_diagnostics(self):
        release = self.project["targets"]["Merian"]["settings"]["configs"]["Release"]
        self.assertEqual(release["SWIFT_ACTIVE_COMPILATION_CONDITIONS"], "$(inherited) MERIAN_HISTORY_NORMAL_OAUTH")
        self.assertEqual(str(release["MERIAN_HISTORY_NORMAL_OAUTH"]), "1")
        self.assertEqual(str(release["MERIAN_HISTORY_QUALIFICATION"]), "0")
        self.assertEqual(release["MERIAN_AUTH_NAMESPACE"], "")
        self.assertNotIn("MERIAN_HISTORY_NORMAL_OAUTH", str(self.project["settings"]["configs"].get("Release", {})))
        for name, target in self.project["targets"].items():
            for config, settings in target.get("settings", {}).get("configs", {}).items():
                if name != "Merian" or config != "Release":
                    self.assertNotIn("MERIAN_HISTORY_NORMAL_OAUTH", str(settings))
                self.assertNotIn("MERIAN_HISTORY_LOCAL_DIAGNOSTICS", str(settings))
        for config, settings in self.project["settings"]["configs"].items():
            if config != "HistoryTesting":
                self.assertNotIn("MERIAN_HISTORY_LOCAL_DIAGNOSTICS", str(settings))
        scheme = ET.parse(SCHEMES / "Merian.xcscheme")
        self.assertEqual(scheme.find("ArchiveAction").get("buildConfiguration"), "Release")
        for relative in [
            "Core/Data/AnalysisHistory/ObservationHistorySelectionService.swift",
            "Features/Insights/History/ViewModels/IdentificationHistoryReviewModel.swift",
            "Features/Insights/History/ViewModels/IdentificationHistoryViewModel.swift",
        ]:
            source = (ROOT / "apps/ios/Merian" / relative).read_text()
            self.assertIn("#if MERIAN_HISTORY_LOCAL_DIAGNOSTICS", source)
            self.assertNotIn("#if MERIAN_HISTORY_NORMAL_OAUTH", source)

    def test_generated_qualification_preserves_primary_identity_and_entitlements(self):
        self.assertIn("merian.xcodeproj", {path.name for path in ROOT.iterdir()})
        result = subprocess.run(["ruby", "-rxcodeproj", "-rjson", "-e",
            'p=Xcodeproj::Project.open(ARGV.first); puts JSON.generate(p.targets.to_h {|t| [t.name,t.build_configurations.to_h {|c| [c.name,c.build_settings]}]})',
            str(ROOT / "merian.xcodeproj")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        targets = json.loads(result.stdout)
        for name, configs in targets.items():
            for config, settings in configs.items():
                flags = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")
                if config == "Release" and name == "Merian":
                    self.assertIn("MERIAN_HISTORY_NORMAL_OAUTH", flags)
                    self.assertEqual(str(settings["MERIAN_HISTORY_NORMAL_OAUTH"]), "1")
                    self.assertEqual(str(settings["MERIAN_HISTORY_QUALIFICATION"]), "0")
                    self.assertEqual(settings["MERIAN_AUTH_NAMESPACE"], "")
                elif config != "HistoryTesting":
                    self.assertNotIn("MERIAN_HISTORY_NORMAL_OAUTH", flags)
                if config != "HistoryTesting":
                    self.assertNotIn("MERIAN_HISTORY_LOCAL_DIAGNOSTICS", flags)
        suffixes = {"Merian": "", "MerianWatch": ".watchkitapp", "MerianExploreWidget": ".ExploreWidget", "MerianMessagesExtension": ".MessagesExtension"}
        for name, suffix in suffixes.items():
            self.assertEqual(targets[name]["HistoryQualification"]["PRODUCT_BUNDLE_IDENTIFIER"], "app.merian.Merian" + suffix)
            for ordinary in ["Debug", "Release"]:
                self.assertNotIn("historyqualification", targets[name][ordinary]["PRODUCT_BUNDLE_IDENTIFIER"])
        self.assertEqual(targets["MerianWatch"]["HistoryQualification"]["INFOPLIST_KEY_WKCompanionAppBundleIdentifier"], "app.merian.Merian")
        path = targets["Merian"]["HistoryQualification"]["CODE_SIGN_ENTITLEMENTS"]
        self.assertEqual(path, "apps/ios/Merian/Configuration/Merian.entitlements")
        entitlements = plistlib.loads((ROOT / path).read_bytes())
        self.assertEqual(entitlements["com.apple.developer.associated-domains"], ["applinks:naturebook.earth", "applinks:merian.earth"])
        self.assertEqual(entitlements["com.apple.security.application-groups"], ["$(MERIAN_APP_GROUP_IDENTIFIER)"])
        for ordinary in ["Debug", "Release"]:
            self.assertEqual(targets["Merian"][ordinary]["CODE_SIGN_ENTITLEMENTS"], "apps/ios/Merian/Configuration/Merian.entitlements")
        values = self.project["settings"]["base"]
        overrides = self.project["settings"]["configs"]["HistoryQualification"]
        expected = {"MERIAN_APP_GROUP_IDENTIFIER": "group.app.merian.shared",
                    "MERIAN_KEYCHAIN_NAMESPACE": "app.merian.shared",
                    "MERIAN_DEEP_LINK_SCHEME": "naturebook",
                    "MERIAN_LEGACY_DEEP_LINK_SCHEME": "merian"}
        for key, value in expected.items():
            self.assertEqual(values[key], value)
            self.assertNotIn(key, overrides)
        for name in suffixes:
            for ordinary in ["Debug", "Release"]:
                self.assertEqual(targets[name]["HistoryQualification"]["PRODUCT_BUNDLE_IDENTIFIER"],
                                 targets[name][ordinary]["PRODUCT_BUNDLE_IDENTIFIER"])

    def test_public_qualification_inputs_are_unapproved_and_do_not_override_installation(self):
        source = (ROOT / "HistoryQualification.xcconfig").read_text()
        for key in ["MERIAN_HISTORY_APPROVAL_ID", "MERIAN_HISTORY_APPROVED_PROJECT", "MERIAN_HISTORY_APPROVED_HOST", "MERIAN_HISTORY_ACCOUNT_FINGERPRINTS", "REVENUECAT_API_KEY", "POSTHOG_API_KEY",
                    *["MERIAN_HISTORY_IDENTITY_" + field for field in ["APPROVAL_ID", "HOST", "PROVIDER", "ACCOUNT_FINGERPRINT", "SUBJECT_FINGERPRINT", "MAPPING_EVIDENCE_DIGEST", "REFUSAL_EVIDENCE_DIGEST", "MAPPING_OBSERVED_AT", "MAPPING_EXPIRES_AT", "REFUSAL_OBSERVED_AT", "REFUSAL_EXPIRES_AT"]]]:
            self.assertIn(key + " =\n", source)
        self.assertIn('#include? "HistoryQualificationApproval.xcconfig"', source)
        self.assertIn('#include "Config.xcconfig"', source)
        self.assertNotIn("\nGIDClientID =", source)
        self.assertNotIn("\nREVERSED_CLIENT_ID =", source)
        self.assertTrue(all(script.get("showEnvVars") is False for kind in ["preBuildScripts", "postBuildScripts"] for script in self.project["targets"]["Merian"][kind]))
        ignored = subprocess.run(["git", "check-ignore", "HistoryQualificationApproval.xcconfig"], cwd=ROOT, capture_output=True)
        self.assertEqual(ignored.returncode, 0)
        info = plistlib.loads((ROOT / "apps/ios/Merian/Configuration/Info.plist").read_bytes())
        self.assertEqual(info["MERIAN_HISTORY_QUALIFICATION"], "$(MERIAN_HISTORY_QUALIFICATION)")
        self.assertEqual(info["CFBundleURLTypes"][1]["CFBundleURLSchemes"], ["$(MERIAN_DEEP_LINK_SCHEME)", "$(MERIAN_LEGACY_DEEP_LINK_SCHEME)"])

    def test_qualification_archive_is_refused_before_release_credentials(self):
        for trigger in [{"ACTION": "install"}, {"DEPLOYMENT_LOCATION": "YES"}, {"ARCHIVE_PRODUCTS_PATH": "/synthetic/archive"}]:
            environment = {"PATH": os.environ["PATH"], "CONFIGURATION": "HistoryQualification", **trigger}
            result = subprocess.run(["bash", str(ROOT / "scripts/check-ios-release-prep.sh")], env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("HistoryQualification archive and distribution are disabled", result.stderr)

    if RUN_COMPILED:
        def test_compiled_qualification_refuses_inherited_services_and_destructive_actions(self):
            spec = importlib.util.spec_from_file_location("local_ios_build", ROOT / "scripts/local-ios-build.py")
            build = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(build)
            with build.Workspace(ROOT).lock(), tempfile.TemporaryDirectory() as temporary:
                build.ensure_no_xcodebuild()
                folder = Path(temporary)
                main = folder / "main.swift"
                main.write_text("""import Foundation
let config = MerianEnvironment.load(infoDictionary: [
    "SUPABASE_URL": "https://abcdefghijklmnopqrst.supabase.co",
    "SUPABASE_ANON_KEY": "synthetic-anon",
    "REVENUECAT_API_KEY": "synthetic-inherited-purchases",
    "POSTHOG_API_KEY": "synthetic-inherited-analytics"
], environment: [:], runtime: .init(isDebug: false, isSimulator: false))
let accountID = UUID(uuidString: "00000000-0000-4000-8000-000000000265")!
let account = MerianEnvironment.HistoryQualificationScope.fingerprint(accountID)
let scope = MerianEnvironment.HistoryQualificationScope(
    approvalID: UUID(uuidString: "00000000-0000-4000-8000-000000000262")!,
    host: "abcdefghijklmnopqrst.supabase.co", accountFingerprints: [account])
let fields = [
    "APPROVAL_ID": scope.approvalID.uuidString.lowercased(), "HOST": scope.host,
    "PROVIDER": "google", "ACCOUNT_FINGERPRINT": account,
    "SUBJECT_FINGERPRINT": "eacb6d601990bfb45b26b2f19843b40b4c5a1d57b86546065a27f70ea86e3cf7",
    "MAPPING_EVIDENCE_DIGEST": String(repeating: "c", count: 64),
    "REFUSAL_EVIDENCE_DIGEST": String(repeating: "d", count: 64),
    "MAPPING_OBSERVED_AT": "1800000000", "MAPPING_EXPIRES_AT": "1800000300",
    "REFUSAL_OBSERVED_AT": "1800000010", "REFUSAL_EXPIRES_AT": "1800000200"
]
let info: [String: Any] = Dictionary(uniqueKeysWithValues: fields.map { ("MERIAN_HISTORY_IDENTITY_" + $0.key, $0.value) })
let now = Date(timeIntervalSince1970: 1800000100)
func validate(_ input: [String: Any], marker: Bool = true, at: Date = now) throws -> MerianEnvironment.HistoryQualificationIdentityEvidence {
    try MerianEnvironment.validateHistoryQualificationIdentityEvidence(info: input, scope: scope, compiledMarker: marker, now: at)
}
func reject(_ input: [String: Any], marker: Bool = true, at: Date = now) {
    do { _ = try validate(input, marker: marker, at: at); fatalError("Invalid identity evidence admitted") }
    catch is MerianEnvironment.QualificationIdentityEvidenceFailure {}
    catch { fatalError("Unexpected identity evidence error") }
}
let evidence = try validate(info)
precondition(evidence.approvalID == scope.approvalID && evidence.host == scope.host)
precondition(evidence.provider == "google" && evidence.accountFingerprint == account)
precondition(evidence.mappingEvidenceDigest == fields["MAPPING_EVIDENCE_DIGEST"])
precondition(evidence.refusalEvidenceDigest == fields["REFUSAL_EVIDENCE_DIGEST"])
precondition(evidence.subjectFingerprint == fields["SUBJECT_FINGERPRINT"])
precondition(evidence.isCurrent(at: now))
precondition(evidence.permitsGoogleExchange(isGoogle: true, subject: "qualification-google-subject", at: now))
precondition(!evidence.permitsGoogleExchange(isGoogle: false, subject: "qualification-google-subject", at: now))
precondition(!evidence.permitsGoogleExchange(isGoogle: true, subject: "other-subject", at: now))
precondition(!evidence.permitsGoogleExchange(isGoogle: true, subject: "qualification-google-subject", at: evidence.refusalExpiresAt))
precondition(evidence.permitsInstalledAccount(accountID, isAnonymous: false, at: now))
precondition(!evidence.permitsInstalledAccount(accountID, isAnonymous: true, at: now))
precondition(!evidence.permitsInstalledAccount(UUID(), isAnonymous: false, at: now))
precondition(!evidence.permitsInstalledAccount(accountID, isAnonymous: false, at: evidence.mappingExpiresAt))
let broadScope = MerianEnvironment.HistoryQualificationScope(approvalID: scope.approvalID, host: scope.host,
    accountFingerprints: [account, String(repeating: "f", count: 64)])
do {
    _ = try MerianEnvironment.validateHistoryQualificationIdentityEvidence(info: info, scope: broadScope, compiledMarker: true, now: now)
    fatalError("Multiple-account Google activation admitted")
} catch MerianEnvironment.QualificationIdentityEvidenceFailure.binding {}
// Fixed vector from the SQL inspector's UTF-8 domain-separated SHA-256 contract.
precondition(evidence.matchesGoogleSubject("qualification-google-subject", at: now))
for subject in ["", "different-subject", "Qualification-google-subject", " qualification-google-subject", "qualification-google-subject ", "qualification-google-subject\\n", String(repeating: "x", count: 256)] {
    precondition(!evidence.matchesGoogleSubject(subject, at: now))
}
for seconds in [1799999999.0, 1800000009.0, 1800000200.0, 1800000300.0, .nan, .infinity] {
    precondition(!evidence.matchesGoogleSubject("qualification-google-subject", at: Date(timeIntervalSince1970: seconds)))
}
// Matching digests ensure length/control rejection is not merely a hash mismatch.
for (subject, fingerprint, allowed) in [
    ("", "44d9eaa3801026a86c18710557e83caec162e2044900ac699346a5b457a67a9a", false),
    ("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "afd9767811a67b5e14ee338c448084c47076d2966c210736b404465eba24a989", false),
    ("qualification-google-subject\\n", "c6ac7d76cca632ad93a3ee4fd87eae09ba674ed8cf570cd29a13a600c35984f5", false),
    ("éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé", "5ca8053991f00c37c14282e1cd56b3fc0914ea0031595b2131cdff116fcad552", false),
    ("ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééée", "4a8c65277e173db3e4a829add38e55127f0f62f57f2ced0de87cebed6a990b83", true)
] {
    var input = info; input["MERIAN_HISTORY_IDENTITY_SUBJECT_FINGERPRINT"] = fingerprint
    let matchingEvidence = try validate(input)
    precondition(matchingEvidence.matchesGoogleSubject(subject, at: now) == allowed)
}
var wrongDomain = info
wrongDomain["MERIAN_HISTORY_IDENTITY_SUBJECT_FINGERPRINT"] = "e927226f3cb921ca8f15de86ef31fef0ccc680cb56c64c5ad198d9e17cc8137d"
let wrongDomainEvidence = try validate(wrongDomain)
precondition(!wrongDomainEvidence.matchesGoogleSubject("qualification-google-subject", at: now))
for key in info.keys {
    var input = info; input.removeValue(forKey: key); reject(input)
    input = info; input[key] = ""; reject(input)
    input[key] = true; reject(input)
}
for (field, badValues) in [
    "APPROVAL_ID": ["00000000-0000-4000-8000-000000000263"],
    "HOST": ["different.supabase.co", scope.host + ".invalid"],
    "PROVIDER": ["apple", "Google"],
    "ACCOUNT_FINGERPRINT": [String(repeating: "f", count: 64)],
    "SUBJECT_FINGERPRINT": ["invalid", String(repeating: "B", count: 64)],
    "MAPPING_EVIDENCE_DIGEST": ["invalid"], "REFUSAL_EVIDENCE_DIGEST": ["invalid"],
    "MAPPING_OBSERVED_AT": ["1800000101", "1800000300"],
    "REFUSAL_OBSERVED_AT": ["1800000101", "1800000200"],
    "MAPPING_EXPIRES_AT": ["1800000100", "1799999999"],
    "REFUSAL_EXPIRES_AT": ["1800000100", "1799999999"]
] {
    for bad in badValues { var input = info; input["MERIAN_HISTORY_IDENTITY_" + field] = bad; reject(input) }
}
for field in ["SUBJECT_FINGERPRINT", "MAPPING_EVIDENCE_DIGEST", "REFUSAL_EVIDENCE_DIGEST"] {
    for suffix in ["\\n", "\\r\\n"] {
        var input = info
        input["MERIAN_HISTORY_IDENTITY_" + field] = fields[field]! + suffix
        reject(input)
    }
}
for field in ["MAPPING_OBSERVED_AT", "MAPPING_EXPIRES_AT", "REFUSAL_OBSERVED_AT", "REFUSAL_EXPIRES_AT"] {
    for bad in ["0", "-1", "1800000100.5", "NaN", "inf", "01800000100", " 1800000100", "253402300800"] {
        var input = info; input["MERIAN_HISTORY_IDENTITY_" + field] = bad; reject(input)
    }
}
reject(info, marker: false)
reject(info, at: Date(timeIntervalSince1970: .nan))
reject(info, at: Date(timeIntervalSince1970: 1800000009))
reject(info, at: Date(timeIntervalSince1970: 1800000200))
precondition(!evidence.isCurrent(at: Date(timeIntervalSince1970: 1800000200)))
let normalInfo: [String: Any] = [
    "MERIAN_HISTORY_NORMAL_OAUTH": "1", "SUPABASE_URL": "https://qlarqavoqhkuwzmevrmf.supabase.co",
    "MERIAN_APP_GROUP_IDENTIFIER": "group.app.merian.shared", "MERIAN_KEYCHAIN_NAMESPACE": "app.merian.shared"
]
func normalValid(_ values: [String: Any], marker: Bool = true, bundle: String = "app.merian.Merian") -> Bool {
    MerianEnvironment.validatesHistoryNormalOAuthConfiguration(info: values, bundleID: bundle, compiledMarker: marker)
}
precondition(normalValid(normalInfo))
precondition(!normalValid(normalInfo, marker: false))
precondition(!normalValid(normalInfo, bundle: "app.other"))
for key in normalInfo.keys { var invalid = normalInfo; invalid.removeValue(forKey: key); precondition(!normalValid(invalid)) }
for (key, value) in [
    ("MERIAN_HISTORY_QUALIFICATION", "1"), ("MERIAN_AUTH_NAMESPACE", "Merian.HistoryQualification.Auth"),
    ("MERIAN_APP_GROUP_IDENTIFIER", "group.other"), ("MERIAN_KEYCHAIN_NAMESPACE", "other"),
    ("SUPABASE_URL", "https://other.supabase.co"), ("SUPABASE_URL", "http://qlarqavoqhkuwzmevrmf.supabase.co"),
    ("SUPABASE_URL", "https://qlarqavoqhkuwzmevrmf.supabase.co/path"),
    ("SUPABASE_URL", "https://qlarqavoqhkuwzmevrmf.supabase.co:443"),
    ("SUPABASE_URL", "https://qlarqavoqhkuwzmevrmf.supabase.co?x=1"),
    ("SUPABASE_URL", "https://qlarqavoqhkuwzmevrmf.supabase.co#fragment"),
    ("SUPABASE_URL", "https://user:password@qlarqavoqhkuwzmevrmf.supabase.co")
] { var invalid = normalInfo; invalid[key] = value; precondition(!normalValid(invalid)) }
#if MERIAN_HISTORY_NORMAL_OAUTH
precondition(MerianEnvironment.isHistoryNormalOAuthBuild && MerianEnvironment.preservesExistingLibrary)
precondition(!MerianEnvironment.isHistoryQualificationBuild)
precondition(MerianEnvironment.permitsHistoryQualificationAccount(UUID()))
#else
precondition(!MerianEnvironment.isHistoryNormalOAuthBuild)
precondition(MerianEnvironment.preservesExistingLibrary == MerianEnvironment.isHistoryQualificationBuild)
#endif
// Parsing a synthetically complete record never opens the real exchange gate.
#if MERIAN_HISTORY_QUALIFICATION
precondition(MerianEnvironment.isHistoryQualificationBuild)
precondition(!MerianEnvironment.allowsAncillaryHostedIntegrations)
precondition(!MerianEnvironment.permitsQualificationGooglePresentation)
var parsedSubject = false
do {
    try MerianEnvironment.requireQualificationGoogleExchange(isGoogle: true, subject: { parsedSubject = true; return "qualification-google-subject" }())
    fatalError("Missing runtime packet admitted exchange")
} catch MerianEnvironment.HistoryQualificationFailure.accounts {}
precondition(!parsedSubject)
do {
    try MerianEnvironment.requireQualificationGoogleAccount(accountID, isAnonymous: false)
    fatalError("Missing runtime packet admitted installed account")
} catch MerianEnvironment.HistoryQualificationFailure.accounts {}
precondition(config.revenueCatApiKey.isEmpty && config.postHogApiKey.isEmpty)
do {
    try MerianEnvironment.requireQualificationIdentityExchangePermission()
    fatalError("Identity exchange escaped qualification refusal")
} catch MerianEnvironment.HistoryQualificationFailure.accounts {}
do {
    try MerianEnvironment.requireQualificationDeletionPermission()
    fatalError("Deletion escaped qualification refusal")
} catch MerianEnvironment.HistoryQualificationFailure.operationScope {}
#else
precondition(!MerianEnvironment.isHistoryQualificationBuild)
precondition(MerianEnvironment.allowsAncillaryHostedIntegrations)
precondition(MerianEnvironment.permitsQualificationGooglePresentation)
var parsedSubject = false
try MerianEnvironment.requireQualificationGoogleExchange(isGoogle: false, subject: { parsedSubject = true; return "ordinary-token-not-parsed" }())
precondition(!parsedSubject)
try MerianEnvironment.requireQualificationGoogleAccount(accountID, isAnonymous: true)
precondition(config.revenueCatApiKey == "synthetic-inherited-purchases")
precondition(config.postHogApiKey == "synthetic-inherited-analytics")
try MerianEnvironment.requireQualificationIdentityExchangePermission()
try MerianEnvironment.requireQualificationDeletionPermission()
#endif
""")
                command = ["xcrun", "swiftc", "-module-cache-path", str(folder / "modules"),
                    str(ROOT / "apps/ios/Merian/Configuration/MerianEnvironment.swift"),
                    str(ROOT / "apps/ios/Merian/Configuration/HistoryQualificationIdentityEvidence.swift"),
                    str(ROOT / "apps/ios/Merian/Configuration/HistoryNormalOAuthConfiguration.swift"),
                    str(ROOT / "apps/ios/Merian/Core/Security/SecureTransportPolicy.swift"), str(main), "-o", str(folder / "check")]
                for flags in [[], ["-D", "MERIAN_HISTORY_QUALIFICATION"], ["-D", "MERIAN_HISTORY_NORMAL_OAUTH"]]:
                    subprocess.run(command + flags, check=True, capture_output=True, text=True)
                    subprocess.run([str(folder / "check")], check=True, capture_output=True, text=True)
                invalid = subprocess.run(command + ["-D", "DEBUG", "-D", "MERIAN_HISTORY_QUALIFICATION"], capture_output=True, text=True)
                self.assertNotEqual(invalid.returncode, 0)
                self.assertIn("HistoryQualification must exclude Debug fixtures", invalid.stderr)
                for conflict in ["DEBUG", "MERIAN_HISTORY_QUALIFICATION"]:
                    invalid = subprocess.run(command + ["-D", "MERIAN_HISTORY_NORMAL_OAUTH", "-D", conflict], capture_output=True, text=True)
                    self.assertNotEqual(invalid.returncode, 0)
                    self.assertIn("History-enabled builds must use normal OAuth", invalid.stderr)

        def test_enabled_history_gate_constructs_once_with_real_processed_bundle(self):
            # Compile the production gate/factory prefix, not a parallel policy.
            source = (ROOT / "apps/ios/Merian/App/Composition/PreparedHistoryReanalysisComposition.swift").read_text()
            prefix = source[:source.index("    let history:")] + "}\n"
            spec = importlib.util.spec_from_file_location("local_ios_build", ROOT / "scripts/local-ios-build.py")
            build = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(build)
            with build.Workspace(ROOT).lock(), tempfile.TemporaryDirectory() as temporary:
                build.ensure_no_xcodebuild()
                folder = Path(temporary)
                contents = folder / "Gate.app/Contents"
                executable = contents / "MacOS/Gate"
                executable.parent.mkdir(parents=True)
                info = {"CFBundleIdentifier": "app.merian.Merian", "CFBundleExecutable": "Gate",
                    "MERIAN_HISTORY_NORMAL_OAUTH": "1", "MERIAN_HISTORY_QUALIFICATION": "0",
                    "MERIAN_AUTH_NAMESPACE": "", "MERIAN_APP_GROUP_IDENTIFIER": "group.app.merian.shared",
                    "MERIAN_KEYCHAIN_NAMESPACE": "app.merian.shared", "SUPABASE_URL": "https://qlarqavoqhkuwzmevrmf.supabase.co"}
                (contents / "Info.plist").write_bytes(plistlib.dumps(info))
                gate = folder / "Gate.swift"
                gate.write_text(prefix)
                main = folder / "main.swift"
                main.write_text('''import Foundation
MainActor.assumeIsolated {
    MerianEnvironment.requireHistoryQualificationConfiguration()
    precondition(MerianEnvironment.historyNormalOAuthConfigurationIsValid)
    precondition(!MerianEnvironment.isHistoryQualificationBuild)
    precondition(MerianEnvironment.permitsQualificationGooglePresentation)
    precondition(MerianEnvironment.preservesExistingLibrary)
    var builds = 0
    let installed = PreparedHistoryReanalysisComposition.appInstallation {
        builds += 1
        return PreparedHistoryReanalysisComposition()
    }
    precondition(installed != nil && builds == 1)
}
''')
                subprocess.run(["xcrun", "swiftc", "-D", "MERIAN_HISTORY_NORMAL_OAUTH",
                    "-module-cache-path", str(folder / "modules"),
                    str(ROOT / "apps/ios/Merian/Configuration/MerianEnvironment.swift"),
                    str(ROOT / "apps/ios/Merian/Configuration/HistoryNormalOAuthConfiguration.swift"),
                    str(ROOT / "apps/ios/Merian/Configuration/HistoryQualificationIdentityEvidence.swift"),
                    str(ROOT / "apps/ios/Merian/Core/Security/SecureTransportPolicy.swift"),
                    str(gate), str(main), "-o", str(executable)], check=True, capture_output=True, text=True)
                subprocess.run([str(executable)], check=True, capture_output=True, text=True)

    def test_normal_scheme_has_no_fixture_environment_or_arguments(self):
        launch = ET.parse(SCHEMES / "Merian.xcscheme").find("LaunchAction")
        self.assertNotIn("UITesting", [e.get("key") for e in launch.findall("EnvironmentVariables/EnvironmentVariable")])
        self.assertEqual(launch.findall("CommandLineArguments/CommandLineArgument"), [])
        composition = (ROOT / "apps/ios/Merian/App/Composition/PreparedHistoryReanalysisComposition.swift").read_text()
        self.assertIn("static let isAppInstallationQualified = false", composition)


if __name__ == "__main__":
    unittest.main()
