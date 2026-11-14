#!/usr/bin/env python3
"""Release-control contracts for isolated complete-target execution."""

import copy
import json
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
    check(build["timeout-minutes"] == 95 and shards["timeout-minutes"] == 330, "Unreviewed job budget")
    check(build["needs"] == "scope" and build["if"] == "needs.scope.outputs.should_run == 'true'", "Build scope bypass")
    check(shards["needs"] == "ios-unit-build" and shards["if"] == "needs.ios-unit-build.result == 'success'", "Shard build bypass")
    check(shards["strategy"] == {"fail-fast": False, "max-parallel": 4,
          "matrix": "${{ fromJSON(needs.ios-unit-build.outputs.matrix) }}"}, "Incomplete/unbounded matrix")
    check(build["outputs"] == {"matrix": "${{ steps.plan.outputs.matrix }}",
          "plan_sha256": "${{ steps.plan.outputs.plan_sha256 }}",
          "products_id": "${{ steps.products.outputs.artifact-id }}",
          "plan_id": "${{ steps.plan-artifact.outputs.artifact-id }}"}, "Unbound build outputs")
    for job, name in ((build, "Prepare qualified unit-test simulator"), (shards, "Prepare qualified shard simulator")):
        check(step(job, name)["timeout-minutes"] == 25, "Qualification deadline changed")
        script(job, name, "python3 -B scripts/prepare-ios-unit-simulator.py", "--evidence")
        check(job["env"]["DEVELOPER_DIR"] == "/Applications/Xcode_27.0.app/Contents/Developer", "Wrong Xcode")
    script(shards, "Verify shard source and toolchain", 'test "$actual_sha" = "$GITHUB_SHA"',
           '"Xcode 27.0"', '"Build version 27A266a"', "git diff --quiet")
    compile_text = script(build, "Compile app, unit, and performance test targets", "xcodebuild build-for-testing",
                          "-testProductsPath", "-configuration Debug", "-only-testing:merianTests", "-only-testing:merianPerformanceTests")
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
    combined = script(aggregate, "Reconcile complete target and protected regressions", "scripts/ios-unit-shards.py aggregate",
                      "bash scripts/validate-ios-critical-test-results.sh")
    check(combined.index("scripts/ios-unit-shards.py aggregate") < combined.index("bash scripts/validate-ios-critical-test-results.sh"),
          "Protected-only result substituted for complete target")
    retained = step(aggregate, "Retain complete unit coverage evidence")
    check(retained["if"] == "always()" and retained["with"]["if-no-files-found"] == "warn",
          "Aggregate failure diagnostics hidden or absent output masks original failure")
    check("ios-unit-tests" in jobs["production-readiness"]["needs"], "Production readiness bypasses aggregate")
    for path in ("scripts/ios-unit-shards.py", "scripts/test-ios-unit-shards.py",
                 "scripts/test-ios-unit-shard-workflow.py", "scripts/config/ios-unit-shard-weights.json"):
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
            lambda j: j["ios-unit-tests"].update(needs=["scope", "ios-unit-build"]),
            lambda j: j["ios-unit-tests"].update(**{"if": "success()"}),
            lambda j: j["ios-unit-tests"]["steps"][0]["env"].update(SHARD_RESULT="success"),
            lambda j: j["production-readiness"]["needs"].remove("ios-unit-tests"),
        ]
        for mutation in mutations:
            value = copy.deepcopy(self.workflow)
            mutation(value["jobs"])
            with self.assertRaises(AssertionError):
                validate(value)


if __name__ == "__main__":
    unittest.main()
