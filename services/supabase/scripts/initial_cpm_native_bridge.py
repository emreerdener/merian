"""One-shot loopback synthetic-native/disposable-SQL test handoff.

Provision the owned database first. This process accepts one bounded, nonce-bound
packet and runs the existing request journey. It returns only literal public HTTP
bytes. No SQL configuration, assignment, credential or funding envelope is sent to
the simulator. The caller owns database disposal even when this process fails.
"""
import argparse
import contextlib
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import re
import stat
import socket
import select
import subprocess
import sys
import threading
import time

from initial_atomic_admission_test_support import ROOT
from initial_cpm_admission_bridge_races import literal
from initial_cpm_native_packet import MAX_PACKET, validate_packet
from initial_cpm_native_child import run_owned_child

# macOS resolves /tmp through /private/tmp; Linux runners use /tmp directly.
# Keep the same fixed, canonical parent restriction on each platform.
IPC_ROOT = Path("/private/tmp" if sys.platform == "darwin" else "/tmp")


class NativeBridge:
    def __init__(self, packet, nonce):
        self.packet, self.nonce = packet, nonce
        self.wires, self.metadata = {}, {}
        self.result = None

    def capture(self, label, encoded, metadata):
        if label not in ("allocation", "admission", "pending_status_after_original_dispatch",
                         "immutable_result_alone_is_pending", "original_completion_status_delivery") or label in self.wires:
            raise ValueError("fixture projection order")
        data = base64.b64decode(encoded, validate=True)
        if (not 0 < len(data) <= 131072 or metadata["byteCount"] != len(data)
                or metadata["sha256"] != hashlib.sha256(data).hexdigest()
                or metadata["reads"] != 1 or base64.b64encode(data).decode() != encoded):
            raise ValueError("literal public wire mismatch")
        # Do not decode/reencode the response on its way to the native consumer.
        self.wires[label] = encoded
        self.metadata[label] = metadata

    def project(self, label, value):
        probe = ROOT / "services/supabase/scripts/initial_cpm_native_wire_probe.ts"
        result = subprocess.run(["deno", "run", "--cached-only", "--frozen", "--deny-net", "--no-prompt",
                                 "--config", str(ROOT / "services/supabase/functions/deno.json"), str(probe), label],
                                input=json.dumps(value), capture_output=True, text=True, timeout=25,
                                env={"PATH": os.environ["PATH"]})
        if result.returncode:
            raise RuntimeError("native public projection refused")
        row = json.loads(result.stdout)
        self.capture(label, row.pop("body_base64"), row)

    def project_allocation(self, q, facts):
        for name in ("initial_cpm_native_bridge.py", "initial_cpm_native_packet.py", "initial_cpm_native_wire_probe.ts", "initial_cpm_native_child.py"):
            path = Path(__file__).with_name(name)
            q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
        reply = json.loads(q.execute("native_exact_v3_allocation", "BEGIN; SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL ROLE service_role; SELECT public.create_initial_cpm_photo_v3_allocation(" +
                                    literal(facts["owner_id"]) + "," + literal(facts["scan_id"]) + "," + literal(self.packet["canonical"]) + "); COMMIT;"))
        self.project("allocation", {"owner": facts["owner_id"], "candidate": self.packet["canonical"], "reply": reply})

    def project_admission(self, q, config, ack):
        facts = config["identity"]
        assignment = json.loads(facts["assignment_canonical"])
        backend = config["policy"]["backend"]
        original = {"owner_id": facts["owner_id"], "scan_id": facts["scan_id"],
                    "candidate_canonical": self.packet["canonical"], "candidate_digest": assignment["candidate_digest"],
                    "content_digest": assignment["content_digest"], "assignment_digest": facts["assignment_digest"],
                    "backend_generation": backend["generation"], "backend_configuration_digest": backend["configuration_digest"]}
        reply = json.loads(q.execute("native_saved_admission_public_read", "BEGIN; SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL ROLE service_role; SELECT public.test_cpm_saved_ack(NULL); COMMIT;"))
        self.project("admission", {"original": original, "reply": reply, "acknowledgement": ack})

    def finish(self, q):
        expected = {"allocation", "admission", "pending_status_after_original_dispatch", "immutable_result_alone_is_pending", "original_completion_status_delivery"}
        if (set(self.wires) != expected
                or self.wires["pending_status_after_original_dispatch"] != self.wires["immutable_result_alone_is_pending"]):
            raise ValueError("incomplete original native handoff")
        q.record["native_public_wires"] = self.metadata
        q.record["native_bridge_status"] = "public replies prepared; delivery and native qualification require runner reconciliation"
        q.record["scope"] = "Exact native acquisition/prepared bytes into disposable SQL lifecycle and literal public HTTP projections. Native consumers are independently reconciled by the caller; synthetic provider/retention/transfer configuration, no live Auth, R2 or device qualification."
        q.save()
        self.result = {"version": 1, "nonce": self.nonce, "candidate_sha256": self.packet["sha256"],
                       "allocation": self.wires["allocation"], "admission": self.wires["admission"],
                       "pending": self.wires["pending_status_after_original_dispatch"],
                       "found": self.wires["original_completion_status_delivery"],
                       "wire_metadata": self.metadata}


def write_ready(path, value):
    path = Path(path)
    parent = path.parent
    if (path.name != "ready.json" or parent.parent != IPC_ROOT
            or not parent.name.startswith("merian-native-bridge-")
            or parent.is_symlink() or parent.resolve() != parent):
        raise ValueError("owned private IPC directory required")
    info = parent.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("private IPC directory ownership")
    # Exclusive publication: the random parent is created by the runner before
    # launch. A previous ready record, symlink or conflicting run cannot win.
    temporary = parent / (".ready-" + secrets.token_hex(16))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(json.dumps(value)); stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, path, follow_symlinks=False)
    finally:
        temporary.unlink()



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge-ready")
    parser.add_argument("--native-worker", action="store_true")
    parser.add_argument("--native-nonce")
    for name in ("source", "app", "tests"):
        parser.add_argument("--native-" + name + "-sha256", required=True)
    args, runtime_args = parser.parse_known_args()
    execution = {name + "_sha256": getattr(args, "native_" + name + "_sha256") for name in ("source", "app", "tests")}
    if any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in execution.values()):
        raise ValueError("exact native execution required")
    if "--request-journey" not in runtime_args:
        raise ValueError("request journey required")
    if args.native_worker:
        if args.bridge_ready or not args.native_nonce or not re.fullmatch(r"[0-9a-f]{64}", args.native_nonce):
            raise ValueError("closed worker invocation")
        raw = sys.stdin.buffer.read(MAX_PACKET + 1)
        bridge = NativeBridge(validate_packet(raw, args.native_nonce, execution), args.native_nonce)
        from initial_cpm_runtime_contract import main as run_runtime
        sys.argv = [sys.argv[0]] + runtime_args
        with contextlib.redirect_stdout(sys.stderr): run_runtime(native_bridge=bridge)
        if bridge.result is None: raise ValueError("native runtime incomplete")
        response = json.dumps(bridge.result).encode()
        if len(response) > 524288: raise ValueError("public response bound")
        sys.stdout.buffer.write(response); sys.stdout.buffer.flush()
        return
    if not args.bridge_ready or args.native_nonce:
        raise ValueError("closed listener invocation")
    nonce = secrets.token_hex(32)
    state = {"spent": False, "passed": False}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_POST(self):
            self.connection.settimeout(150)
            if self.path != "/native/" + nonce or state["spent"] or self.headers.get("Transfer-Encoding"):
                self.send_error(404); return
            state["spent"] = True
            deadline = time.monotonic() + 120
            publication_lock, abandoned = threading.Lock(), threading.Event()
            def abandon_socket():
                with publication_lock:
                    if state["passed"]: return
                    abandoned.set()
                    try: self.connection.shutdown(socket.SHUT_RDWR)
                    except OSError: pass
            # Absolute ingress + child + publication bound; activity cannot
            # extend it. Closing the socket also wakes an incomplete body read.
            timer = threading.Timer(120, abandon_socket)
            timer.daemon = True; timer.start()
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= MAX_PACKET or self.headers.get("Content-Type") != "application/json":
                    raise ValueError("bounded native request required")
                raw = self.rfile.read(length)
                if len(raw) != length: raise ValueError("incomplete native request")
                validate_packet(raw, nonce, execution)
                def disconnected():
                    ready, _, _ = select.select([self.connection], [], [], 0)
                    if not ready: return False
                    try:
                        # Request bytes have been fully consumed; EOF or any
                        # unexpected pipelined bytes abandon the one-shot job.
                        self.connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT)
                        return True
                    except BlockingIOError: return False
                command = [sys.executable, str(Path(__file__).resolve()), "--native-worker", "--native-nonce", nonce]
                for name in ("source", "app", "tests"):
                    command += ["--native-" + name + "-sha256", execution[name + "_sha256"]]
                code, response, diagnostics = run_owned_child(command + runtime_args, raw, disconnected, timeout=max(0, deadline - time.monotonic() - 6),
                    lifecycle=lambda stage, pid: print("NATIVE_CHILD " + json.dumps({"stage": stage, "pid": pid}), flush=True))
                for line in diagnostics.decode("utf-8", errors="replace").splitlines():
                    if re.fullmatch(r"(?:PASS|FAIL) [A-Za-z0-9_ /.-]+", line): print(line, flush=True)
                if code or not response or len(response) > 524288:
                    raise ValueError("native child failed or response bound")
                if abandoned.is_set() or time.monotonic() >= deadline or disconnected():
                    raise ValueError("native publication abandoned")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers(); self.wfile.write(response); self.wfile.flush()
                with publication_lock:
                    if abandoned.is_set() or time.monotonic() >= deadline:
                        raise ValueError("native publication missed deadline")
                    state["passed"] = True
            except Exception as error:
                print("Native handoff failed:", type(error).__name__, flush=True)
                try: self.send_error(503, "Synthetic native handoff unavailable")
                except OSError: pass
            finally:
                timer.cancel()

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        server.timeout = 900  # Bounded build/start allowance, not a product timeout.
        write_ready(args.bridge_ready, {"version": 1, "port": server.server_port, "nonce": nonce, "execution": execution})
        server.handle_request()
    if not state["passed"]:
        raise RuntimeError("native handoff did not complete")


if __name__ == "__main__": main()
