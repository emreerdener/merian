#!/usr/bin/env python3
"""Portable adversarial tests for the disposable recovery cron lifecycle."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("recovery", Path(__file__).with_name("run_recovery_catalogs.py"))
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


class Cron:
    def __init__(self, active="true", idle="t"):
        self.active, self.idle = active, idle
        self.events = []
        self.original = "7:" + active

    def execute(self, sql):
        if sql.startswith("SELECT jobid::text"):
            self.events.append("read")
            return "7:" + self.active
        if "cron.alter_job" in sql:
            self.active = "true" if "active:=true" in sql else "false"
            self.events.append("set:" + self.active)
            return ""
        if "cron.job_run_details" in sql:
            self.events.append("idle")
            return self.idle
        raise AssertionError("Unexpected SQL")


class RecoveryTests(unittest.TestCase):
    def test_fixture_runs_only_after_disable_readback_and_idle(self):
        cron = Cron()
        recovery.with_accounting_cron_paused(cron.execute, lambda: cron.events.append("fixtures"))
        self.assertEqual(cron.events, ["read", "set:false", "read", "idle", "fixtures", "set:true", "read"])
        self.assertEqual(cron.active, "true")

    def test_inactive_job_stays_inactive(self):
        cron = Cron(active="false")
        recovery.with_accounting_cron_paused(cron.execute, lambda: None)
        self.assertEqual(cron.active, "false")
        self.assertNotIn("set:true", cron.events)

    def test_fixture_failure_restores_before_propagating(self):
        cron = Cron()
        def fail():
            raise subprocess.CalledProcessError(3, ["synthetic-catalog"])
        with self.assertRaises(subprocess.CalledProcessError):
            recovery.with_accounting_cron_paused(cron.execute, fail)
        self.assertEqual(cron.events[-2:], ["set:true", "read"])
        self.assertEqual(cron.active, "true")

    def test_inflight_or_unknown_idle_never_starts_fixture_and_restores(self):
        for idle in ("f", "", "t\nf"):
            with self.subTest(idle=idle):
                cron = Cron(idle=idle)
                with self.assertRaises(RuntimeError):
                    recovery.with_accounting_cron_paused(cron.execute, lambda: self.fail("fixture started"))
                self.assertEqual(cron.active, "true")

    def test_missing_ambiguous_or_malformed_job_never_mutates(self):
        for state in ("", "7:true\n8:true", "7:t", "0:true", "7:unknown"):
            calls = []
            def execute(sql):
                calls.append(sql)
                return state
            with self.subTest(state=state), self.assertRaises(RuntimeError):
                recovery.with_accounting_cron_paused(execute, lambda: self.fail("fixture started"))
            self.assertEqual(len(calls), 1)

    def test_disable_error_still_attempts_restore(self):
        cron = Cron()
        def execute(sql):
            value = cron.execute(sql)
            if "active:=false" in sql:
                raise RuntimeError("synthetic lost disable reply")
            return value
        with self.assertRaises(RuntimeError):
            recovery.with_accounting_cron_paused(execute, lambda: self.fail("fixture started"))
        self.assertEqual(cron.active, "true")
        self.assertEqual(cron.events[-2:], ["set:true", "read"])

    def test_failed_suspend_or_restore_readback_fails_closed(self):
        for mutate in ("disable", "restore"):
            cron = Cron()
            def execute(sql):
                value = cron.execute(sql)
                if mutate == "disable" and "active:=false" in sql:
                    cron.active = "true"
                if mutate == "restore" and "active:=true" in sql:
                    cron.active = "false"
                return value
            with self.subTest(mutate=mutate), self.assertRaises(RuntimeError):
                recovery.with_accounting_cron_paused(execute, lambda: None)

    def test_local_engine_only_and_pinned_environment(self):
        def run(*args, **kwargs):
            return subprocess.CompletedProcess(args, 0, json.dumps([{"Name": "local", "Endpoints": {"docker": {"Host": "unix:///tmp/test.sock"}}}]))
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(recovery.local_environment(run)["DOCKER_HOST"], "unix:///tmp/test.sock")
        with patch.dict(os.environ, {"DOCKER_HOST": "tcp://remote:2375"}, clear=True), self.assertRaises(RuntimeError):
            recovery.local_environment(run)
        def remote(*args, **kwargs):
            return subprocess.CompletedProcess(args, 0, json.dumps([{"Endpoints": {"docker": {"Host": "ssh://remote"}}}]))
        with self.assertRaises(RuntimeError):
            recovery.local_environment(remote)

    def test_container_name_running_port_and_immutable_id_are_required(self):
        project = "merian-migration-recovery-123-explore"
        with tempfile.TemporaryDirectory(prefix="merian-migration-recovery.") as directory:
            root = Path(directory)
            (root / "supabase").mkdir()
            (root / "supabase/config.toml").write_text('project_id="' + project + '"\n[db]\nport=55432\n')
            info = {"Name": "/supabase_db_" + project, "State": {"Running": True},
                    "HostConfig": {"PortBindings": {"5432/tcp": [{"HostPort": "55432"}]}}, "Id": "a" * 64}
            def run(*args, **kwargs):
                return subprocess.CompletedProcess(args, 0, json.dumps([info]))
            self.assertEqual(recovery.owned_container(root, project, {}, run), "a" * 64)
            for key, value in (("Name", "/supabase_db_merian"), ("State", {"Running": False}),
                               ("HostConfig", {"PortBindings": {"5432/tcp": [{"HostPort": "54322"}]}}),
                               ("Id", "mutable-name")):
                with self.subTest(key=key), patch.dict(info, {key: value}), self.assertRaises(RuntimeError):
                    recovery.owned_container(root, project, {}, run)
            with self.assertRaises(RuntimeError):
                recovery.owned_container(root, "merian-history", {}, run)

    def test_query_is_bounded_local_container_exec_without_remote_dsn(self):
        calls = []
        def run(args, **kwargs):
            calls.append((args, kwargs))
            return subprocess.CompletedProcess(args, 0, "t\n", "")
        self.assertEqual(recovery.query("a" * 64, {}, "SELECT true;", run), "t")
        args, options = calls[0]
        self.assertEqual(args[:4], ["docker", "exec", "-i", "a" * 64])
        self.assertEqual(options["timeout"], 10)
        self.assertIn("statement_timeout='5s'", options["input"])
        self.assertFalse(any("://" in value for value in args))

    def test_recovery_runner_keeps_complete_fixture_counts_and_cleanup(self):
        source = Path(__file__).with_name("test_migration_recovery_replay.sh").read_text()
        self.assertIn("trap cleanup EXIT", source)
        self.assertIn('if [ "$scenario" = explore ]; then', source)
        self.assertIn('python3 -B "$recovery_script_dir/run_recovery_catalogs.py"', source)
        self.assertIn('^Files=${#fixtures[@]}, Tests=[1-9][0-9]*,', source)
        self.assertIn("^Result: PASS", source)
        self.assertEqual(recovery.FIXTURES, ("reported_post_visibility", "identification_invocation_accounting", "privileged_routine_security"))


if __name__ == "__main__":
    unittest.main()
