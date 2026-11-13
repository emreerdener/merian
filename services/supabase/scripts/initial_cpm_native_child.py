"""Absolute lifetime for one owned local test child and its process group."""
import os
import signal
import subprocess
import time


class AbandonedExchange(RuntimeError):
    def __init__(self, reason, child_exited):
        super().__init__("native exchange abandoned: " + reason)
        self.reason, self.child_exited = reason, child_exited


def run_owned_child(command, payload, disconnected, *, timeout=120, grace=3, lifecycle=lambda _stage, _pid: None):
    child, pending, previous = None, [], {}
    deadline, first, reason, result = time.monotonic() + timeout, True, None, None
    lifecycle("spawning", 0)
    try:
        # Defer parent termination while Popen establishes ownership. Custom
        # handlers reset on exec, so the child does not inherit blocked signals.
        for number in (signal.SIGINT, signal.SIGTERM):
            previous[number] = signal.getsignal(number)
            signal.signal(number, lambda number, _frame: pending.append(number))
        child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 start_new_session=True, env={"PATH": os.environ["PATH"], "PYTHONDONTWRITEBYTECODE": "1",
                                                              "SUPABASE_TELEMETRY_DISABLED": "1"})
        lifecycle("started", child.pid)
        for number, handler in previous.items(): signal.signal(number, handler)
        previous.clear()
        if pending: raise KeyboardInterrupt()
        while result is None:
            if disconnected():
                reason = "caller disconnected"; break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                reason = "absolute deadline"; break
            try:
                result = child.communicate(input=payload if first else None, timeout=min(0.05, remaining))
            except subprocess.TimeoutExpired:
                first = False
        if reason is None:
            # Publication is denied if cancellation wins concurrently with exit.
            if disconnected(): reason = "caller disconnected"
            elif time.monotonic() >= deadline: reason = "absolute deadline"
    except BaseException:
        reason = "parent interrupted"
        raise
    finally:
        for number, handler in previous.items(): signal.signal(number, handler)
        if child is None:
            lifecycle("spawn_failed", 0)
        elif reason is not None:
            try: os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: child.communicate(timeout=grace)
            except subprocess.TimeoutExpired: pass
            # Also stop a descendant that closed its pipes and ignored SIGTERM.
            try: os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            child.communicate(timeout=grace)
            if child.poll() is None:
                raise RuntimeError("owned native child termination unverified")
        if child is not None and child.poll() is not None: lifecycle("exited", child.pid)
    if reason is not None:
        # Already-issued local SQL may have committed. Caller must wait for this
        # confirmed child exit, then dispose its exact owned DB; never retry it.
        raise AbandonedExchange(reason, child.poll() is not None)
    return child.returncode, result[0], result[1]
