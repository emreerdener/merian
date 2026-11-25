#!/usr/bin/env python3
"""Recovery has narrower authority than the normal full-suite verifier."""
import copy
import importlib.util
import os
import io
import stat
import tempfile
import zipfile
from pathlib import Path
import shutil
import unittest
from unittest.mock import patch


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


recovery = module("recovery", "ios-evidence-recovery.py")
fixtures = module("fixtures", "test-ios-unit-shards.py")
shards = recovery.shards


class RecoveryTests(fixtures.ShardTests):
    """Reuse existing adversarial fixtures; inherited tests still test strict mode."""
    def recovery_fixture(self):
        self.methods = [m for m in self.methods if not m.startswith("merianTests/Extra")] + [f"merianTests/Extra{i}/testOne" for i in range(20)]
        self.ordinary = [m for m in self.methods if m not in fixtures.EXPECTED_INTEGRATIONS]
        self.enumeration.write_text(fixtures.enumeration_text(self.methods, full_target=True))
        self.plan = shards.make_plan(self.enumeration, self.products, {"Alpha": 50})
        self.save_plan()
        shutil.rmtree(self.focused)
        self.focused = self.requalification_evidence()
        evidence = self.evidence()
        self.policy = {"schema_version": 1, "origin": {"source_sha": "a" * 40, "run_id": 1234, "build_attempt": 1,
                       "recovery_attempt": 2, "lost_shard": 1, "lost_job_id": 1001, "retry_shards": [1, 6, 11]}}
        for index in (1, 6, 11):
            original = evidence / shards.shard_artifact(self.plan, index, "1")
            retry = evidence / shards.shard_artifact(self.plan, index, "2")
            shutil.copytree(original, retry)
            with patch.dict(os.environ, {"GITHUB_RUN_ATTEMPT": "2", "IOS_UNIT_BUILD_ATTEMPT": "1"}):
                shards.write_json(retry / "qualification.json", fixtures.qualification())
                shards.write_json(retry / "receipt.json", shards.receipt(self.plan, index, retry))
                shards.write_json(retry / "execution.json", shards.execution(self.plan, index, retry,
                                  {key: "success" for key in shards.OUTCOME_KEYS}))
            if index == 1:
                shutil.rmtree(original)
            else:
                (original / "receipt.json").unlink()
                outcomes = {key: "success" for key in shards.OUTCOME_KEYS}
                outcomes.update(native="failure", receipt="failure")
                shards.write_json(original / "execution.json", shards.execution(self.plan, index, original, outcomes))
        context = {"source_sha": "a" * 40, "run_id": "1234", "run_attempt": "2", "build_attempt": "1",
                   "plan_sha256": shards.digest(self.plan_file), "artifact_ids": {"products": "101", "plan": "102", "requalification": "103"}}
        return evidence, context

    def metadata(self):
        jobs = []
        for index in range(16):
            steps = [{"name": name, "status": "completed", "conclusion": "success"}
                     for name in sorted(recovery.SUCCESS_STEPS)]
            steps += [{"name": name, "status": "completed", "conclusion": "failure" if index == 1 else "success"}
                      for name in sorted(recovery.UPLOAD_STEPS)]
            jobs.append({"id": 1000 + index, "run_id": 1234, "run_attempt": 1, "head_sha": "a" * 40,
                         "name": f"iOS unit shard {index}", "status": "completed",
                         "conclusion": "failure" if index in (1, 6, 11) else "success",
                         "started_at": "2026-11-24T00:00:00Z", "completed_at": "2026-11-24T00:10:00Z", "steps": steps})
        retries = copy.deepcopy(jobs)
        for index, job in enumerate(retries):
            job.update(id=2000 + index, run_attempt=2)
            if index in (1, 6, 11):
                job.update(started_at="2026-11-25T00:00:00Z", completed_at="2026-11-25T00:10:00Z", conclusion="success")
                for step in job["steps"]:
                    step["conclusion"] = "success"
        return {"total_count": 16, "jobs": jobs}, {"total_count": 16, "jobs": retries}

    def test_recovery_preserves_thirteen_passes_and_two_failed_envelopes(self):
        evidence, context = self.recovery_fixture()
        with patch.dict(os.environ, {"GITHUB_SHA": "b" * 40, "GITHUB_RUN_ID": "9876"}):
            plan = shards.load_plan(self.plan_file, require_workspace=False, context=context)
            selected, failed = recovery.select_recovery(self.policy, plan, evidence, context)
            self.assertEqual(len(selected), 16)
            self.assertEqual([entry[1]["shard"] for entry in selected if entry[1]["execution_attempt"] == "2"], [1, 6, 11])
            self.assertEqual([entry["shard"] for entry in failed], [6, 11])
            self.assertEqual(os.environ["GITHUB_SHA"], "b" * 40)
            with self.assertRaises(ValueError):
                shards.load_plan(self.plan_file)
            with self.assertRaisesRegex(ValueError, "Missing original"):
                shards.aggregate(plan, evidence, self.root / "strict", self.focused, context=context)
            shards.write_aggregate(plan, selected, failed, self.root / "recovered", self.focused, context=context)
            result = shards.read_json(self.root / "recovered/coverage.json")
            self.assertEqual(result["methods"], len(self.ordinary))
            self.assertFalse(result["release_eligible"])

    def test_omitted_or_extra_original_and_retry_artifacts_fail(self):
        for index, attempt in ((0, "1"), (6, "1"), (11, "1"), (1, "2"), (6, "2"), (11, "2")):
            with self.subTest(index=index, attempt=attempt):
                evidence, context = self.recovery_fixture()
                shutil.rmtree(evidence / shards.shard_artifact(self.plan, index, attempt))
                with self.assertRaises(ValueError):
                    recovery.select_recovery(self.policy, self.plan, evidence, context)
                shutil.rmtree(evidence)
                # Re-create a fresh fixture rather than mutate previous passes.
                self.methods = self.methods[:-20]

    def test_second_retry_and_context_drift_fail(self):
        evidence, context = self.recovery_fixture()
        for key, value in (("run_attempt", "3"), ("source_sha", "c" * 40), ("run_id", "999"), ("build_attempt", "2")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                recovery.select_recovery(self.policy, self.plan, evidence, {**context, key: value})

    def test_unreviewed_loss_index_or_retry_set_fails(self):
        evidence, context = self.recovery_fixture()
        for change in ({"lost_shard": 0}, {"retry_shards": [1, 6]}, {"retry_shards": [1, 6, 11, 12]}):
            policy = copy.deepcopy(self.policy)
            policy["origin"].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                recovery.select_recovery(policy, self.plan, evidence, context)

    def test_missing_retry_raw_evidence_or_skipped_result_fails(self):
        evidence, context = self.recovery_fixture()
        retry = evidence / shards.shard_artifact(self.plan, 1, "2")
        original = (retry / "summary.json").read_bytes()
        summary = shards.read_json(retry / "summary.json")
        summary["skippedTests"] = 1
        shards.write_json(retry / "summary.json", summary)
        with self.assertRaises(ValueError):
            recovery.select_recovery(self.policy, self.plan, evidence, context)
        (retry / "summary.json").write_bytes(original)
        (retry / "receipt.json").unlink()
        with self.assertRaises(ValueError):
            recovery.select_recovery(self.policy, self.plan, evidence, context)

    def test_metadata_carry_forward_is_not_counted_as_a_rerun(self):
        self.recovery_fixture()
        original, second = self.metadata()
        before, after = recovery.validate_jobs(self.policy, original, second)
        self.assertEqual(len(before), len(after))
        self.assertEqual(after[0]["started_at"], before[0]["started_at"])
        self.assertNotEqual(after[0]["id"], before[0]["id"])

    def test_changed_passed_job_timestamps_or_steps_fail(self):
        self.recovery_fixture()
        for key, value in (("started_at", "2026-11-25T00:00:00Z"), ("steps", []), ("conclusion", "failure")):
            original, second = self.metadata()
            second["jobs"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                recovery.validate_jobs(self.policy, original, second)

    def test_loss_record_requires_exact_job_absence_and_upload_only_failure(self):
        self.recovery_fixture()
        original, second = self.metadata()
        before, _ = recovery.validate_jobs(self.policy, original, second)
        absent = {"total_count": 0, "artifacts": []}
        excerpt = ["Failed to CreateArtifact: ETIMEDOUT", "Failed to FinalizeArtifact: ETIMEDOUT"]
        record = recovery.loss_record(self.policy, before, absent, excerpt, {"source": "d" * 64}, absent)
        self.assertFalse(record["passing_coverage"])
        self.assertFalse(record["original_receipt_reconstructed"])
        for name in recovery.SUCCESS_STEPS:
            changed = copy.deepcopy(before)
            next(s for s in changed[1]["steps"] if s["name"] == name)["conclusion"] = "failure"
            with self.subTest(step=name), self.assertRaises(ValueError):
                recovery.loss_record(self.policy, changed, absent, excerpt, {}, absent)
        for bad in ({"total_count": 1, "artifacts": [{}]}, {"total_count": 0, "artifacts": [{}]}):
            with self.assertRaises(ValueError):
                recovery.loss_record(self.policy, before, bad, excerpt, {}, absent)
        for bad in ([], ["CreateArtifact ETIMEDOUT"], ["CreateArtifact 403", "FinalizeArtifact 403"]):
            with self.assertRaises(ValueError):
                recovery.loss_record(self.policy, before, absent, bad, {}, absent)



    def collection_fixture(self):
        evidence, context = self.recovery_fixture()
        original, second = self.metadata()
        blobs, artifacts = {}, []
        def artifact(identifier, name, directory=None, files=None):
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, "w") as bundle:
                if directory:
                    for path in sorted(directory.rglob("*")):
                        bundle.write(path, path.relative_to(directory).as_posix())
                else:
                    for key, raw in files.items():
                        bundle.writestr(key, raw)
            raw = stream.getvalue()
            blobs[identifier] = raw
            result = {"id": identifier, "name": name, "size_in_bytes": len(raw), "expired": False,
                      "digest": "sha256:" + recovery.sha256(raw)}
            artifacts.append(result)
            return {"id": identifier, "archive_digest": result["digest"]}
        pins = {"plan": artifact(102, "ios-unit-plan-1234-attempt-1", files={"ios-unit-plan.json": self.plan_file.read_bytes()}),
                "requalification": artifact(103, "ios-unit-requalification-1234-attempt-1", self.focused),
                "products": artifact(101, "ios-unit-products-1234-attempt-1", files={"products.tar.gz": self.products.read_bytes()})}
        for identifier, directory in enumerate(sorted(evidence.iterdir()), 200):
            artifact(identifier, directory.name, directory)
        self.policy["origin"].update(artifacts=pins, plan_sha256=shards.digest(self.plan_file), products_sha256=shards.digest(self.products))
        class Client:
            def json(inner, path):
                return {"head_sha": "a" * 40, "run_attempt": 2, "status": "completed", "conclusion": "failure",
                        "path": ".github/workflows/ios-build-and-test.yml"}
            def listing(inner, path, key):
                if "/attempts/1/jobs" in path: return original
                if "/attempts/2/jobs" in path: return second
                if "?name=" in path: return {"total_count": 0, "artifacts": []}
                return {"total_count": len(artifacts), "artifacts": artifacts}
            def bytes(inner, path):
                if path.endswith("/logs"):
                    return b"Failed to CreateArtifact: ETIMEDOUT\nFailed to FinalizeArtifact: ETIMEDOUT\n"
                return blobs[int(path.split("/")[-2])]
        return Client(), artifacts, blobs

    def test_collect_and_verify_end_to_end_preserves_failure_and_exact_origins(self):
        client, _, _ = self.collection_fixture()
        directory, output = self.root / "collection", self.root / "verified"
        recovery.collect(self.policy, directory, client)
        verifier = {"source_sha": "b" * 40, "workflow_run_id": "9876"}
        # This compact fixture lacks the real critical suites; the production
        # subprocess is separately exercised by test-validate-ios-critical-test-results.
        with patch.object(recovery.subprocess, "run") as critical:
            result = recovery.verify(self.policy, directory, output, verifier)
        critical.assert_called_once()
        self.assertEqual(result["compiled_source"], "a" * 40)
        self.assertEqual(result["verifier"], verifier)
        self.assertEqual(result["original_workflow_conclusion"], "failure")
        self.assertFalse(result["old_workflow_relabelled"])
        self.assertFalse(result["evidence_losses"][0]["passing_coverage"])
        self.assertEqual(result["methods"], len(self.ordinary))
        collection = shards.read_json(directory / "collection.json")
        collection["forged_extra"] = True
        shards.write_json(directory / "collection.json", collection)
        with self.assertRaises(ValueError):
            recovery.verify(self.policy, directory, self.root / "forged", verifier)

    def test_collect_rejects_wrong_download_digest_and_present_fallback(self):
        client, artifacts, blobs = self.collection_fixture()
        blobs[102] = b"wrong bytes"
        with self.assertRaises(ValueError):
            recovery.collect(self.policy, self.root / "bad-digest", client)
        listing = client.listing
        def fallback_present(path, key):
            return {"total_count": 1, "artifacts": [{}]} if "?name=ios-unit-failure-" in path else listing(path, key)
        client.listing = fallback_present
        with self.assertRaises(ValueError):
            recovery.collect(self.policy, self.root / "bad-fallback", client)



class RecoveryArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def zip(self, names=("receipt.json",), mode=None):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for name in names:
                entry = zipfile.ZipInfo(name)
                if mode:
                    entry.external_attr = mode << 16
                archive.writestr(entry, b"retained evidence")
        return stream.getvalue()

    def test_safe_zip_preserves_original_bytes(self):
        recovery.safe_unzip(self.zip(("nested/receipt.json",)), self.root / "out")
        self.assertEqual((self.root / "out/nested/receipt.json").read_bytes(), b"retained evidence")
        with self.assertRaises(ValueError):
            recovery.safe_unzip(self.zip(), self.root / "out")

    def test_unsafe_special_duplicate_and_oversized_zip_fail(self):
        for index, (names, mode) in enumerate((
            (("../escape",), None), (("/absolute",), None), (("a/../escape",), None),
            (("a\\escape",), None), (("same", "same"), None), (("./same",), None),
            (("linked",), stat.S_IFLNK | 0o777), (("device",), stat.S_IFCHR | 0o600))):
            with self.subTest(names=names, mode=mode), self.assertRaises(ValueError):
                recovery.safe_unzip(self.zip(names, mode), self.root / str(index))

    def archive_fixture(self):
        origin = {"run_id": 1234, "lost_shard": 1, "retry_shards": [1, 6, 11], "artifacts": {}}
        artifacts = []
        (self.root / "archives").mkdir()
        names = [(f"ios-unit-shard-1234-build-1-attempt-1-{i}", self.root / "shards") for i in range(16) if i != 1]
        names += [(f"ios-unit-shard-1234-build-1-attempt-2-{i}", self.root / "shards") for i in (1, 6, 11)]
        names += [(f"ios-unit-{role}-1234-attempt-1", self.root) for role in ("plan", "requalification")]
        for index, (name, parent) in enumerate(names, 1):
            raw = self.zip()
            digest = "sha256:" + recovery.sha256(raw)
            (self.root / "archives" / f"{index}.zip").write_bytes(raw)
            role = "plan" if name.startswith("ios-unit-plan-") else "requalification" if name.startswith("ios-unit-requalification-") else None
            recovery.safe_unzip(raw, parent / (role or name))
            if role:
                origin["artifacts"][role] = {"id": index, "archive_digest": digest}
            artifacts.append({"id": index, "name": name, "digest": digest})
        return {"origin": origin}, {"artifacts": artifacts}

    def test_retained_archives_are_recomputed_and_extracted_bytes_bound(self):
        policy, collection = self.archive_fixture()
        recovery.verify_archives(policy, self.root, collection)
        first = self.root / "shards" / collection["artifacts"][0]["name"] / "receipt.json"
        first.write_bytes(b"fabricated")
        with self.assertRaises(ValueError):
            recovery.verify_archives(policy, self.root, collection)
        first.write_bytes(b"retained evidence")
        first.with_name("extra.json").write_text("extra")
        with self.assertRaises(ValueError):
            recovery.verify_archives(policy, self.root, collection)

    def test_manifest_pin_wrong_digest_missing_archive_and_symlink_fail(self):
        policy, collection = self.archive_fixture()
        for edit in (lambda c: c["artifacts"].pop(),
                     lambda c: c["artifacts"][-1].update(id=999),
                     lambda c: c["artifacts"][0].update(digest="sha256:" + "0" * 64),
                     lambda c: c["artifacts"][0].update(id="../escape")):
            changed = copy.deepcopy(collection)
            edit(changed)
            with self.assertRaises(ValueError):
                recovery.verify_archives(policy, self.root, changed)
        (self.root / "archives/1.zip").unlink()
        with self.assertRaises(ValueError):
            recovery.verify_archives(policy, self.root, collection)
        (self.root / "archives/1.zip").symlink_to(self.root / "archives/2.zip")
        with self.assertRaises(ValueError):
            recovery.verify_archives(policy, self.root, collection)

    def test_qualifying_entry_point_rejects_local_pat_and_untrusted_events(self):
        valid = {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": "emreerdener/merian", "GITHUB_TOKEN": "synthetic",
                 "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}
        with patch.dict(os.environ, valid, clear=True), patch.object(recovery, "verifier_identity", return_value={"verified": True}):
            self.assertEqual(recovery.trusted_workflow_identity(), {"verified": True})
        for edit in ({"GITHUB_ACTIONS": "false"}, {"GITHUB_REPOSITORY": "other/repo"}, {"GITHUB_TOKEN": ""},
                     {"GH_TOKEN": "synthetic-pat"}, {"GITHUB_EVENT_NAME": "pull_request_target"},
                     {"GITHUB_SHA": ""}, {"GITHUB_RUN_ID": ""}, {"GITHUB_RUN_ATTEMPT": "0"}):
            with self.subTest(edit=edit), patch.dict(os.environ, {**valid, **edit}, clear=True), self.assertRaises(ValueError):
                recovery.trusted_workflow_identity()

    def test_credentials_are_not_forwarded_on_artifact_redirect(self):
        import urllib.error
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, limit): return b"artifact"
        redirect = urllib.error.HTTPError("https://api.github.com", 302, "Found", {"Location": "https://example.blob.core.windows.net/artifact?token=synthetic"}, None)
        with patch.dict(os.environ, {"GH_TOKEN": "synthetic"}), patch.object(recovery.urllib.request, "build_opener") as opener, patch.object(recovery.urllib.request, "urlopen", return_value=Response()) as download:
            opener.return_value.open.side_effect = redirect
            client = recovery.GitHub("emreerdener/merian")
            self.assertEqual(client.bytes("/actions/artifacts/1/zip"), b"artifact")
            self.assertEqual(download.call_args.args, ("https://example.blob.core.windows.net/artifact?token=synthetic",))
            self.assertEqual(download.call_args.kwargs, {"timeout": 60})
            redirect.headers["Location"] = "https://untrusted.example/artifact"
            with self.assertRaises(ValueError):
                client.bytes("/actions/artifacts/1/zip")


if __name__ == "__main__":
    unittest.main()
