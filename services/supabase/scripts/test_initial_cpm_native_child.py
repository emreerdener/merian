"""Real local child regressions for deadline, disconnect and pipe draining."""
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

from initial_cpm_native_child import AbandonedExchange, run_owned_child
from initial_cpm_native_bridge import write_ready, NativeBridge, IPC_ROOT


class NativeChildTests(unittest.TestCase):
    def test_success_drains_both_pipes_and_preserves_payload(self):
        command = [sys.executable, "-c", "import sys; data=sys.stdin.buffer.read();sys.stderr.write('x'*100000);sys.stdout.buffer.write(data)"]
        code, output, error = run_owned_child(command, b"exact synthetic bytes", lambda: False, timeout=5)
        self.assertEqual((code, output, len(error)), (0, b"exact synthetic bytes", 100000))

    def test_nonzero_exit_is_never_success(self):
        code, output, _ = run_owned_child([sys.executable, "-c", "raise SystemExit(7)"], b"", lambda: False)
        self.assertEqual((code, output), (7, b""))

    def exercise_abandonment(self, disconnect):
        with tempfile.TemporaryDirectory() as folder:
            pidfile = Path(folder) / "pid"
            command = [sys.executable, "-c", "import os,signal,time,pathlib,sys;signal.signal(signal.SIGTERM,signal.SIG_IGN);pathlib.Path(sys.argv[1]).write_text(str(os.getpid()));time.sleep(30)", str(pidfile)]
            started = time.monotonic()
            with self.assertRaises(AbandonedExchange) as raised:
                run_owned_child(command, b"", lambda: disconnect and pidfile.exists(), timeout=0.5, grace=0.1)
            self.assertTrue(raised.exception.child_exited)
            self.assertEqual(raised.exception.reason, "caller disconnected" if disconnect else "absolute deadline")
            self.assertLess(time.monotonic() - started, 3)
            self.assertTrue(pidfile.exists())
            with self.assertRaises(ProcessLookupError): os.kill(int(pidfile.read_text()), 0)

    def test_absolute_deadline_kills_and_reaps_sigterm_resistant_child(self):
        self.exercise_abandonment(False)

    def test_disconnect_kills_and_reaps_before_returning(self):
        self.exercise_abandonment(True)

    def test_registration_failure_still_reaps_owned_child(self):
        events = []
        def lifecycle(stage, pid):
            events.append((stage, pid))
            if stage == "started": raise RuntimeError("synthetic logging failure")
        with self.assertRaisesRegex(RuntimeError, "synthetic logging failure"):
            run_owned_child([sys.executable, "-c", "import time;time.sleep(30)"], b"", lambda: False,
                            timeout=2, grace=0.1, lifecycle=lifecycle)
        self.assertEqual([stage for stage, _ in events], ["spawning", "started", "exited"])
        self.assertEqual(events[1][1], events[2][1])
        with self.assertRaises(ProcessLookupError): os.kill(events[1][1], 0)

    def test_ready_publication_is_exclusive_and_rejects_symlink(self):
        with tempfile.TemporaryDirectory(prefix="merian-native-bridge-", dir=IPC_ROOT) as folder:
            parent = Path(folder); parent.chmod(0o700)
            ready = parent / "ready.json"
            write_ready(ready, {"synthetic": True})
            original = ready.read_bytes()
            with self.assertRaises(FileExistsError): write_ready(ready, {"replacement": True})
            self.assertEqual(ready.read_bytes(), original)
            ready.unlink(); ready.symlink_to(parent / "absent")
            with self.assertRaises(FileExistsError): write_ready(ready, {"replacement": True})
            self.assertFalse((parent / "absent").exists())
            self.assertEqual([p.name for p in parent.iterdir()], ["ready.json"])

    def test_ready_publication_rejects_nonprivate_parent(self):
        with tempfile.TemporaryDirectory(prefix="merian-native-bridge-", dir=IPC_ROOT) as folder:
            parent = Path(folder); parent.chmod(0o755)
            with self.assertRaises(ValueError): write_ready(parent / "ready.json", {})

    def test_incomplete_projection_bundle_does_not_finish(self):
        class Record:
            record = {"passed": False}
        bridge = NativeBridge({"sha256": "a" * 64}, "synthetic")
        with self.assertRaises(ValueError): bridge.finish(Record())
        self.assertIsNone(bridge.result)
        self.assertFalse(Record.record["passed"])


if __name__ == "__main__": unittest.main()
