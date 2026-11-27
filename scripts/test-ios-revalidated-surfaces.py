#!/usr/bin/env python3
"""Fail-closed source and hosted checks for the dependency successor."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("surfaces", Path(__file__).with_name("ios-revalidated-surfaces.py"))
surfaces = importlib.util.module_from_spec(spec)
spec.loader.exec_module(surfaces)


class RevalidatedSurfacesTests(unittest.TestCase):
    def setUp(self):
        self.before, self.after = {}, {}
        self.policy = {"origin": {"source_sha": "a" * 40}, "product_paths": ["apps/ios", "project.yml"],
                       "reused_surface_paths": {}, "reused_workflows": {},
                       "reused_workflow_paths": {}, "revalidated_surfaces": {}}
        self.paths = {}
        for name, contract in surfaces.CONTRACTS.items():
            path = contract["paths"][0] + ("/file.ts" if name != "agent_quality" else "")
            self.paths[name] = path
            self.before[path] = {"mode": "100644", "type": "blob", "object": "a" * 40}
            self.after[path] = {"mode": "100644", "type": "blob", "object": "b" * 40}
            self.policy["revalidated_surfaces"][name] = {"owned_paths": contract["paths"].copy(), "reviewed_delta": [
                {"path": path, "before": copy.deepcopy(self.before[path]), "after": copy.deepcopy(self.after[path]), "review": "Exact dependency update"}]}
        self.candidate = {"source_sha": "b" * 40}
        self.run_ids = {"backend": 10, "admin": 20, "agent_quality": 30, "web": 40}
        self.runs, self.jobs = {}, {}
        for name, run_id in self.run_ids.items():
            contract = surfaces.CONTRACTS[name]
            self.runs[run_id] = {"id": run_id, "head_sha": self.candidate["source_sha"], "path": contract["workflow"],
                                 "event": "workflow_dispatch", "status": "completed", "conclusion": "success", "run_attempt": 2}
            self.jobs[run_id] = [{"id": run_id * 100 + i, "name": job, "run_id": run_id, "run_attempt": 2,
                                  "head_sha": self.candidate["source_sha"], "status": "completed", "conclusion": "success",
                                  "steps": [{"name": step, "status": "completed", "conclusion": "success"}
                                            for step in contract["steps"].get(job, [])]} for i, job in enumerate(contract["jobs"])]
        self.client = Mock()
        self.client.json.side_effect = lambda path: self.runs[int(path.split('/')[3])]
        self.client.listing.side_effect = lambda path, key: {key: self.jobs[int(path.split('/')[3])], "total_count": len(self.jobs[int(path.split('/')[3])])}
        self.backend = Mock(side_effect=lambda client, run_id, candidate: {**self.runs[run_id], "complete_scope_executed": True})

    def git(self, *args):
        return (self.paths[next(name for name, contract in surfaces.CONTRACTS.items() if tuple(contract["paths"]) == args[5:])] + '\n').encode()

    def validate(self):
        return surfaces.validate(self.policy, "b" * 40, self.git, lambda sha: self.before if sha == "a" * 40 else self.after)

    def verify_runs(self):
        return surfaces.verify_runs(self.policy, self.candidate, self.client, self.run_ids, self.backend)

    def test_exact_objects_and_four_fresh_surfaces_pass(self):
        self.assertEqual(set(self.validate()), set(surfaces.CONTRACTS))
        self.assertTrue(self.verify_runs()["backend"]["backend_evidence"]["complete_scope_executed"])
        self.backend.assert_called_once()

    def test_legacy_policy_remains_supported_without_new_runs(self):
        self.assertEqual(surfaces.validate({}, "b" * 40, None, None), {})
        self.assertEqual(surfaces.verify_runs({}, {}, None, {}, None), {})
        with self.assertRaises(ValueError):
            surfaces.verify_runs({}, {}, None, self.run_ids, None)

    def test_unknown_missing_or_reused_changed_surface_rejected(self):
        original = copy.deepcopy(self.policy)
        for change in (lambda p: p["revalidated_surfaces"].pop("backend"),
                       lambda p: p["revalidated_surfaces"].update(extra={}),
                       lambda p: p["reused_surface_paths"].update(backend=["services/supabase"]),
                       lambda p: p.update(reviewed_surface_control_delta={"backend": ["old exception"]}),
                       lambda p: p["reused_workflow_paths"].update(web="wrong.yml"),
                       lambda p: p["product_paths"].append("services")):
            self.policy = copy.deepcopy(original)
            change(self.policy)
            with self.assertRaises(ValueError): self.validate()

    def test_missing_extra_unreviewed_or_altered_object_rejected(self):
        original = copy.deepcopy(self.policy)
        for change in (lambda r: r.update(owned_paths=["services"]),
                       lambda r: r["reviewed_delta"].clear(),
                       lambda r: r["reviewed_delta"].append(copy.deepcopy(r["reviewed_delta"][0])),
                       lambda r: r["reviewed_delta"][0].update(review=""),
                       lambda r: r["reviewed_delta"][0].update(path="apps/ios/injected.swift"),
                       lambda r: r["reviewed_delta"][0]["after"].update(object="c" * 40)):
            self.policy = copy.deepcopy(original)
            change(self.policy["revalidated_surfaces"]["backend"])
            with self.assertRaises(ValueError): self.validate()

    def test_mode_change_is_rejected_even_when_manifest_matches(self):
        path = self.paths["backend"]
        self.after[path]["mode"] = "100755"
        self.policy["revalidated_surfaces"]["backend"]["reviewed_delta"][0]["after"]["mode"] = "100755"
        with self.assertRaises(ValueError): self.validate()

    def test_missing_duplicate_invalid_run_identity_rejected(self):
        original = self.run_ids.copy()
        for bad in ({"backend": 10}, {**original, "extra": 40}, {**original, "admin": 10},
                    {**original, "admin": None}, {**original, "admin": True}):
            self.run_ids = bad
            with self.assertRaises(ValueError): self.verify_runs()

    def test_run_source_workflow_event_attempt_and_completion_are_bound(self):
        for key, value in (("id", 999), ("head_sha", "a" * 40), ("path", "wrong.yml"),
                           ("event", "pull_request_target"), ("status", "in_progress"),
                           ("conclusion", "failure"), ("run_attempt", 0), ("run_attempt", True)):
            old = self.runs[20][key]; self.runs[20][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify_runs()
            self.runs[20][key] = old

    def test_backend_push_and_noninteger_job_ids_fail(self):
        self.runs[10]["event"] = "push"
        with self.assertRaises(ValueError): self.verify_runs()
        self.runs[10]["event"] = "workflow_dispatch"
        for bad in (True, "2000", 0):
            self.jobs[20][0]["id"] = bad
            with self.assertRaises(ValueError): self.verify_runs()

    def test_job_source_attempt_and_required_execution_are_bound(self):
        for key, value in (("run_id", 1), ("run_attempt", 1), ("head_sha", "a" * 40),
                           ("status", "in_progress"), ("conclusion", "skipped"), ("name", "Unexpected job")):
            old = self.jobs[20][0][key]; self.jobs[20][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify_runs()
            self.jobs[20][0][key] = old
        self.jobs[10][1]["conclusion"] = "skipped"
        with self.assertRaises(ValueError): self.verify_runs()

    def test_missing_duplicate_and_truncated_job_inventories_fail(self):
        original = copy.deepcopy(self.jobs[20])
        for jobs in ([], original * 2, original + [{**original[0], "id": 999}]):
            self.jobs[20] = jobs
            with self.assertRaises(ValueError): self.verify_runs()
        self.jobs[20] = original
        self.client.listing.side_effect = lambda path, key: {key: self.jobs[int(path.split('/')[3])], "total_count": 100}
        with self.assertRaises(ValueError): self.verify_runs()

    def test_every_required_admin_and_agent_step_must_execute(self):
        for run_id in (20, 30, 40):
            for step in self.jobs[run_id][0]["steps"]:
                step["conclusion"] = "skipped"
                with self.subTest(step=step["name"]), self.assertRaises(ValueError): self.verify_runs()
                step["conclusion"] = "success"
            steps = self.jobs[run_id][0]["steps"]
            steps.append(copy.deepcopy(steps[0]))
            with self.assertRaises(ValueError): self.verify_runs()
            steps.pop()

    def test_nonblocking_live_evaluation_failure_does_not_weaken_deterministic_gate(self):
        self.jobs[30].append({**self.jobs[30][0], "id": 3999, "name": "Live evaluation (ios)", "conclusion": "failure"})
        self.assertIn("agent_quality", self.verify_runs())
        self.jobs[30][0]["conclusion"] = "failure"
        with self.assertRaises(ValueError): self.verify_runs()

    def test_existing_backend_verifier_failure_and_attempt_race_propagate(self):
        self.backend.side_effect = ValueError("Missing C1 evidence")
        with self.assertRaisesRegex(ValueError, "C1"): self.verify_runs()
        self.backend.side_effect = lambda *args: {**self.runs[10], "run_attempt": 3}
        with self.assertRaisesRegex(ValueError, "attempt changed"): self.verify_runs()


if __name__ == "__main__":
    unittest.main()
