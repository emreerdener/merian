#!/usr/bin/env python3
"""Release-control contracts for isolated complete-target execution."""

import copy
import json
import re
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/ios-build-and-test.yml"


def validate(workflow):
    def check(value, message):
        if not value:
            raise AssertionError(message)
    jobs = workflow["jobs"]
    build, shards, aggregate = [jobs[name] for name in ("ios-unit-build", "ios-unit-shards", "ios-unit-tests")]
    def step(job, name):
        matches = [s for s in job["steps"] if s.get("name") == name]
        check(len(matches) == 1, "Missing/duplicate step: " + name)
        return matches[0]
    def script(job, name, *required):
        text = step(job, name).get("run", "")
        check(all(value in text for value in required), "Missing gate in " + name)
        check("|| true" not in text and "continue-on-error" not in text, "Gate failure ignored")
        return text
    for job in (build, shards, aggregate):
        check(not job.get("continue-on-error"), "Job failure ignored")
        check(all(not s.get("continue-on-error") for s in job["steps"]), "Step failure ignored")
        for s in job["steps"]:
            if s.get("uses", "").startswith("actions/download-artifact@"):
                check(s["with"].get("digest-mismatch") == "error", "Artifact digest failure ignored")
                check("github-token" not in s["with"] and "repository" not in s["with"]
                      and "run-id" not in s["with"], "Artifact download escaped current run")
    check(build["runs-on"] == shards["runs-on"] == "xcode-27", "Wrong native runner")
    check(build["timeout-minutes"] == 310 and shards["timeout-minutes"] == 350, "Unreviewed job budget")
    check(build["needs"] == "scope" and build["if"] == "needs.scope.outputs.should_run == 'true'", "Build scope bypass")
    check(shards["needs"] == "ios-unit-build" and shards["if"] == "needs.ios-unit-build.result == 'success'", "Shard build bypass")
    check(shards["strategy"] == {"fail-fast": False, "max-parallel": 4,
          "matrix": "${{ fromJSON(needs.ios-unit-build.outputs.matrix) }}"}, "Incomplete/unbounded matrix")
    check(build["outputs"] == {"matrix": "${{ steps.plan.outputs.matrix }}",
          "plan_sha256": "${{ steps.plan.outputs.plan_sha256 }}",
          "products_id": "${{ steps.products.outputs.artifact-id }}",
          "plan_id": "${{ steps.plan-artifact.outputs.artifact-id }}",
          "requalification_id": "${{ steps.requalification-artifact.outputs.artifact-id }}"}, "Unbound build outputs")
    for job, name in ((build, "Prepare candidate unit-test simulator"), (shards, "Prepare candidate shard simulator")):
        check(step(job, name)["timeout-minutes"] == 20, "Qualification deadline changed")
        script(job, name, "python3 -B scripts/discover-ios27-simulator.py", "--prepare-only", "--evidence")
        check(job["env"]["DEVELOPER_DIR"] == "/Applications/Xcode_27.0.app/Contents/Developer", "Wrong Xcode")
    for job in (build, shards):
        observe = step(job, "Observe exact guest identity inside XCTest")
        check(observe["timeout-minutes"] == 10, "Identity test deadline changed")
        script(job, observe["name"], "-testProductsPath", "-parallel-testing-enabled NO",
               "-only-testing:merianTests/SimulatorRuntimeIdentityTests/testRecordsBootedGuestIdentity")
        verify = step(job, "Verify exact guest identity evidence")
        check(verify["timeout-minutes"] == 5 and verify["if"] == "always() && steps.ios-identity-test.outcome != 'skipped'"
              and verify["env"] == {"IOS_IDENTITY_TEST_OUTCOME": "${{ steps.ios-identity-test.outcome }}"}, "Identity result gate bypass")
        script(job, verify["name"], "xcresulttool get test-results summary", "xcresulttool get test-results tests",
               "xcresulttool export attachments", "scripts/discover-ios27-simulator.py --verify-directory", "git diff --quiet")
        names = [s.get("name") for s in job["steps"]]
        inventory = "Enumerate complete compiled unit target" if job is build else "Reconcile selected compiled inventory"
        preparation = "Compile app, unit, and performance test targets" if job is build else "Verify and unpack compiled products"
        check(names.index(preparation) < names.index(observe["name"]) < names.index(verify["name"]) < names.index(inventory),
              "Identity observation does not bind actual compiled product before inventory")
        retained = step(job, "Retain simulator identity evidence")
        check(retained["if"] == "always()" and retained["timeout-minutes"] == 10, "Identity evidence retention changed")
    suites = ("PinnedPhotoUploadTaskTests", "CaptureNativePhotoRoleAllocationTests", "AppleFoundationVisualCueProviderTests")
    focused_enumeration = "Enumerate transport and Foundation requalification suites"
    selected = step(build, focused_enumeration)
    check(selected["timeout-minutes"] == 5 and selected["env"] ==
          {"IOS_UNIT_PLAN_SHA256": "${{ steps.plan.outputs.plan_sha256 }}"}, "Focused inventory preflight is unbound")
    selected_script = script(build, focused_enumeration, "scripts/ios-unit-shards.py check-focused-enumeration",
                             '--plan "$RUNNER_TEMP/ios-unit-plan.json"',
                             '--enumeration "$RUNNER_TEMP/ios-unit-requalification/enumeration.txt"')
    check(selected_script.index("-enumerate-tests") < selected_script.index("check-focused-enumeration"),
          "Focused inventory verified before generation")
    ordered = [s.get("name") for s in build["steps"]]
    check(ordered.index(focused_enumeration) < ordered.index("Requalify transport resources and iOS 27 parsing")
          < ordered.index("Verify complete focused runtime evidence"), "Focused preflight or postflight order changed")
    for name in ("Enumerate transport and Foundation requalification suites", "Requalify transport resources and iOS 27 parsing"):
        text = script(build, name, "-testProductsPath", "-parallel-testing-enabled NO",
                      *("-only-testing:merianTests/" + suite for suite in suites))
        check("-skip-testing" not in text and "-retry-tests-on-failure" not in text, "Focused requalification narrowed or retried")
        check(re.findall(r"-only-testing:merianTests/([^\s]+)", text) == list(suites), "Focused suite set changed")
    check(step(build, "Requalify transport resources and iOS 27 parsing")["timeout-minutes"] == 120, "Requalification budget changed")
    focus = step(build, "Verify complete focused runtime evidence")
    check(focus["if"] == "always() && steps.ios-transport-tests.outcome != 'skipped'"
          and focus["env"] == {"IOS_REQUALIFICATION_OUTCOME": "${{ steps.ios-transport-tests.outcome }}",
                               "IOS_UNIT_PLAN_SHA256": "${{ steps.plan.outputs.plan_sha256 }}"}, "Focused execution failure ignored")
    script(build, focus["name"], "scripts/ios-unit-shards.py requalification", "git diff --quiet")
    names = [s.get("name") for s in build["steps"]]
    check(names.index("Enumerate complete compiled unit target") < names.index("Package exact compiled products")
          < names.index("Plan complete suite partition") < names.index("Verify focused compiled products")
          < names.index("Enumerate transport and Foundation requalification suites")
          < names.index("Requalify transport resources and iOS 27 parsing") < names.index(focus["name"])
          < names.index("Retain compiled unit products"), "Focused results not bound before product publication")
    script(build, "Verify focused compiled products", "scripts/ios-unit-shards.py unpack", "--plan", "--products",
           '--directory "$RUNNER_TEMP/ios-unit-requalification-product"')
    for name in ("Enumerate transport and Foundation requalification suites", "Requalify transport resources and iOS 27 parsing"):
        script(build, name, '-testProductsPath "$RUNNER_TEMP/ios-unit-requalification-product/tests.xctestproducts"')
    allowed_selectors = {"Observe exact guest identity inside XCTest", "Enumerate transport and Foundation requalification suites",
                         "Requalify transport resources and iOS 27 parsing"}
    for job in (build, shards):
        for item in job["steps"]:
            selectors = re.findall(r"-only-testing:merianTests/([^\s]+)", item.get("run", ""))
            if selectors:
                check(item.get("name") in (allowed_selectors if job is build else {"Observe exact guest identity inside XCTest"}),
                      "Handwritten selector outside scoped prerequisites")
                if item["name"] == "Observe exact guest identity inside XCTest":
                    check(selectors == ["SimulatorRuntimeIdentityTests/testRecordsBootedGuestIdentity"], "Identity selector changed")
    script(shards, "Verify shard source and toolchain", 'test "$actual_sha" = "$GITHUB_SHA"',
           '"Xcode 27.0"', '"Build version 27A266a"', "git diff --quiet")
    compile_text = script(build, "Compile app, unit, and performance test targets", "xcodebuild build-for-testing",
                          "-testProductsPath", "-configuration Debug", "-only-testing:merianTests", "-only-testing:merianPerformanceTests")
    check(step(build, "Compile app, unit, and performance test targets")["timeout-minutes"] == 60, "Compile deadline changed")
    check("-project " not in compile_text, "Portable product build cannot combine explicit project")
    enum = script(build, "Enumerate complete compiled unit target", "-testProductsPath", "-only-testing:merianTests",
                  "-enumerate-tests", "-test-enumeration-style flat", "-test-enumeration-format text")
    check("-only-testing:merianTests/" not in enum and "-skip-testing" not in enum, "Inventory narrowed")
    script(build, "Plan complete suite partition", "git diff --quiet", "scripts/ios-unit-shards.py plan",
           "--enumeration", "--products", "--weights", "--output")
    for name, output in (("Download exact compiled products", "products_id"), ("Download exact unit plan", "plan_id")):
        check(step(shards, name)["with"]["artifact-ids"] == "${{ needs.ios-unit-build.outputs." + output + " }}",
              "Download not bound to build artifact ID")
    script(shards, "Verify and unpack compiled products", "scripts/ios-unit-shards.py unpack",
           "scripts/ios-unit-shards.py selectors", "--plan", '--index "$IOS_UNIT_SHARD"')
    for name in ("Reconcile selected compiled inventory", "Run complete assigned suites serially"):
        text = script(shards, name, "set -o pipefail", "-parallel-testing-enabled NO",
                      '-only-testing "@$RUNNER_TEMP/ios-unit-suites.txt"', "-testProductsPath")
        check("-skip-testing" not in text and "-retry-tests-on-failure" not in text, "Coverage retry/skip introduced")
    script(shards, "Reconcile selected compiled inventory", "scripts/ios-unit-shards.py check-enumeration")
    check(step(shards, "Run complete assigned suites serially")["timeout-minutes"] == 240, "Unreviewed execution budget")
    verify = step(shards, "Verify shard execution against compiled inventory")
    check(verify["if"] == "always()" and verify["env"]["IOS_UNIT_TEST_OUTCOME"] == "${{ steps.xcode-tests.outcome }}",
          "Receipt lacks actual command outcome")
    script(shards, verify["name"], "xcresulttool get test-results summary", "xcresulttool get test-results tests",
           "scripts/ios-unit-shards.py receipt")
    check(step(shards, "Retain shard coverage evidence")["with"]["name"] ==
          "ios-unit-shard-${{ github.run_id }}-attempt-${{ github.run_attempt }}-${{ matrix.index }}", "Evidence collision")
    check(aggregate["name"] == "Full iOS unit tests" and aggregate["needs"] == ["scope", "ios-unit-build", "ios-unit-shards"],
          "Aggregate bypasses a prerequisite")
    check(aggregate["if"] == "always() && needs.scope.outputs.should_run == 'true'", "Aggregate hidden on failures")
    check(aggregate["env"]["IOS_UNIT_PLAN_SHA256"] == shards["env"]["IOS_UNIT_PLAN_SHA256"] ==
          "${{ needs.ios-unit-build.outputs.plan_sha256 }}", "Unbound plan digest")
    require = step(aggregate, "Require successful build and every shard")
    check(aggregate["steps"][0] == require, "Aggregate proceeds before job-result gate")
    check(require["env"] == {"BUILD_RESULT": "${{ needs.ios-unit-build.result }}",
                            "SHARD_RESULT": "${{ needs.ios-unit-shards.result }}"}, "Missing matrix result")
    script(aggregate, require["name"], 'test "$BUILD_RESULT" = success', 'test "$SHARD_RESULT" = success')
    script(aggregate, "Verify aggregate source revision", 'test "$actual_sha" = "$GITHUB_SHA"', "git diff --quiet")
    check(aggregate["steps"][2]["name"] == "Verify aggregate source revision", "Aggregate source must be verified after checkout")
    download = step(aggregate, "Download all current-attempt shard evidence")["with"]
    check(download["pattern"] == "ios-unit-shard-${{ github.run_id }}-attempt-${{ github.run_attempt }}-*"
          and download["merge-multiple"] is False, "Evidence attempts mixed or directories flattened")
    check(step(aggregate, "Download exact runtime requalification evidence")["with"]["artifact-ids"] ==
          "${{ needs.ios-unit-build.outputs.requalification_id }}", "Focused artifact not bound to current build")
    combined = script(aggregate, "Reconcile complete target and protected regressions", "scripts/ios-unit-shards.py aggregate",
                      "bash scripts/validate-ios-critical-test-results.sh", "--requalification-directory")
    check(combined.index("scripts/ios-unit-shards.py aggregate") < combined.index("bash scripts/validate-ios-critical-test-results.sh"),
          "Protected-only result substituted for complete target")
    retained = step(aggregate, "Retain complete unit coverage evidence")
    check(retained["if"] == "always()" and retained["with"]["if-no-files-found"] == "warn",
          "Aggregate failure diagnostics hidden or absent output masks original failure")
    check("ios-unit-tests" in jobs["production-readiness"]["needs"], "Production readiness bypasses aggregate")
    for path in ("scripts/ios-unit-shards.py", "scripts/test-ios-unit-shards.py",
                 "scripts/test-ios-unit-shard-workflow.py", "scripts/config/ios-unit-shard-weights.json",
                 "scripts/discover-ios27-simulator.py", "scripts/test-discover-ios27-simulator.py"):
        check((ROOT / ".github/workflows/ios-project-guardrails.yml").read_text().count('"' + path + '"') == 2,
              "Project guardrails omit shard input: " + path)


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = json.loads(subprocess.check_output([
            "ruby", "-ryaml", "-rjson", "-e", "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(WORKFLOW)], text=True))

    def test_complete_release_contract(self):
        validate(self.workflow)

    def test_mutated_gates_fail_closed(self):
        mutations = [
            lambda j: j["ios-unit-shards"]["strategy"].update(**{"fail-fast": True}),
            lambda j: j["ios-unit-shards"]["strategy"].update(**{"max-parallel": 16}),
            lambda j: j["ios-unit-shards"].update(**{"continue-on-error": True}),
            lambda j: j["ios-unit-build"].update(**{"timeout-minutes": 360}),
            lambda j: j["ios-unit-build"]["outputs"].update(plan_sha256="arbitrary"),
            lambda j: next(s for s in j["ios-unit-build"]["steps"] if s.get("name") ==
                           "Enumerate transport and Foundation requalification suites").update(
                               env={"IOS_UNIT_PLAN_SHA256": "arbitrary"}),
            lambda j: next(s for s in j["ios-unit-build"]["steps"] if s.get("name") ==
                           "Enumerate transport and Foundation requalification suites").update(run="xcodebuild -enumerate-tests"),
            lambda j: j["ios-unit-build"]["steps"].append(j["ios-unit-build"]["steps"].pop(next(
                i for i, s in enumerate(j["ios-unit-build"]["steps"]) if s.get("name") ==
                "Enumerate transport and Foundation requalification suites"))),
            lambda j: j["ios-unit-tests"].update(needs=["scope", "ios-unit-build"]),
            lambda j: j["ios-unit-tests"].update(**{"if": "success()"}),
            lambda j: j["ios-unit-tests"]["steps"][0]["env"].update(SHARD_RESULT="success"),
            lambda j: j["production-readiness"]["needs"].remove("ios-unit-tests"),
            lambda j: j["ios-unit-shards"]["steps"].append({"name": "Requalify transport resources and iOS 27 parsing",
                                                         "run": "xcodebuild -only-testing:merianTests/Subset"}),
            lambda j: j["ios-unit-build"]["steps"].append({"name": "Extra selected tests",
                                                        "run": "xcodebuild -only-testing:merianTests/Subset"}),
        ]
        for mutation in mutations:
            value = copy.deepcopy(self.workflow)
            mutation(value["jobs"])
            with self.assertRaises(AssertionError):
                validate(value)


if __name__ == "__main__":
    unittest.main()
