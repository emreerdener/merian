"""No database: exercise actual overlap cleanup when a session close fails."""
import unittest
from initial_cpm_runtime_contract import close_overlap_sessions


class CloseOverlapTests(unittest.TestCase):
    def run_cleanup(self, observer_fails, admission_fails):
        calls = []
        class Session:
            def __init__(self, name, fails):
                self.name, self.fails = name, fails
            def close(self):
                calls.append(self.name)
                if self.fails: raise RuntimeError(self.name)
        observer = Session("observer", observer_fails)
        admission = Session("admission", admission_fails)
        if observer_fails or admission_fails:
            with self.assertRaises(RuntimeError):
                close_overlap_sessions(observer, admission)
        else:
            close_overlap_sessions(observer, admission)
        self.assertEqual(calls, ["observer", "admission"])

    def test_admission_closes_after_observer_failure(self):
        self.run_cleanup(True, False)

    def test_both_closes_attempted_when_both_fail(self):
        self.run_cleanup(True, True)

    def test_success_and_partial_initialization(self):
        self.run_cleanup(False, False)
        close_overlap_sessions(None, None)
        calls = []
        class Admission:
            def close(self): calls.append("admission")
        close_overlap_sessions(None, Admission())
        self.assertEqual(calls, ["admission"])


if __name__ == "__main__": unittest.main()
