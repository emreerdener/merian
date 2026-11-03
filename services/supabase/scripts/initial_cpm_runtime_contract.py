"""Owned local HTTP-to-SQL shim plus actual media verifier; not PostgREST or R2 qualification."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session
from initial_cpm_atomic_admission_committed import FIXTURE
from initial_cpm_admission_bridge_races import literal
from initial_cpm_admission_bridge_contract import FUNDING

PROBE = Path(__file__).with_name("initial_cpm_runtime_probe.ts")
DENO = ["deno", "run", "--frozen", "--config", str(ROOT / "services/supabase/functions/deno.json")]
RPCS = {
    "read_initial_cpm_photo_admission": ["p_owner", "p_scan", "p_candidate", "p_assignment", "p_assignment_digest"],
    "begin_initial_cpm_photo_admission": ["p_owner", "p_scan", "p_candidate", "p_assignment", "p_assignment_digest"],
    "admit_initial_cpm_photo": ["p_owner", "p_scan", "p_candidate", "p_assignment", "p_assignment_digest", "p_verification", "p_ip_hash"],
    "assert_initial_cpm_photo_verification_current": ["p_owner", "p_scan", "p_assignment_digest", "p_attempt", "p_snapshot_digest"],
    "read_initial_cpm_photo_observation": ["p_attempt", "p_outcome", "p_claim", "p_expected"],
}


def close_overlap_sessions(observer, admission):
    """Never let observer cleanup failure retain the admission transaction."""
    try:
        if observer: observer.close()
    finally:
        if admission: admission.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["container", "evidence-directory", "replay-manifest"]:
        parser.add_argument("--" + name, required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--lost-ack", action="store_true")
    modes.add_argument("--pending-commit", action="store_true")
    args = parser.parse_args()
    q = actor = server = None
    errors = []
    pending_admission = threading.Event()
    recovery_started = threading.Event()
    overlap = {}
    try:
        q = Qualification(args.container, args.evidence_directory, "cpm-runtime-contract", args.replay_manifest)
        # Concurrent admission/recovery sessions share evidence, never the SQL connection.
        evidence_lock = threading.RLock()
        original_save = q.save
        def save_locked():
            with evidence_lock: original_save()
        q.save = save_locked
        for path in [Path(__file__), PROBE, FIXTURE, Path(__file__).with_name("initial_cpm_admission_bridge_contract.py")]:
            q.record["source_manifest"][str(path.resolve().relative_to(ROOT))] = q.digest(path)
        for directory in ["initialAnalysis", "analysisHistory"]:
            for path in (ROOT / "services/supabase/functions/_shared" / directory).rglob("*"):
                if path.suffix in (".ts", ".json"):
                    q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
        q.record["scope"] = "Two-photo six-role tiny real JPEGs, local HTTP shim executing service SQL, fixed local storage response. Not PostgREST/JWT, real signer/R2, provider/native, maximum-byte or representative network latency qualification."
        q.record["lost_ack"] = args.lost_ack
        q.record["pending_commit"] = args.pending_commit
        generated = subprocess.run(DENO + [str(PROBE), "fixture"], capture_output=True, text=True, timeout=30)
        if generated.returncode: raise RuntimeError("fixture generator failed")
        media = bytes(json.loads(generated.stdout))
        source = FIXTURE.read_text()
        vector = re.search(r"\$fixture\$(.*?)\$fixture\$", source).group(1)
        candidate = json.loads(vector)
        content = json.loads(candidate["content_canonical"])
        content["photos"].append(json.loads(json.dumps(content["photos"][0])))
        for n, photo in enumerate(content["photos"]):
            photo["ordinal"] = n
            for i, role in enumerate(["source", "ai", "display"]):
                photo[role].update(byte_count=len(media), sha256=hashlib.sha256(media).hexdigest(), declared_content_type="image/jpeg", reference_id=f"00000000-0000-4000-8000-{700+n*3+i:012d}")
        candidate["content_canonical"] = json.dumps(content, separators=(",", ":"), sort_keys=True, ensure_ascii=False)
        prefix = source.split("-- Negotiated backend projection:")[0].replace(vector, json.dumps(candidate, separators=(",", ":"), sort_keys=True, ensure_ascii=False))
        policy = source[source.index("CREATE TEMP TABLE closure_policy"):source.index("-- END CPM CLOSURE POLICY FIXTURE")]
        writes = source[source.index("DO $$ DECLARE s internal.initial_analysis_preparation_intents; m RECORD;"):source.index("SAVEPOINT verification_revoked;")]
        actor = Session(q, "runtime_fixture", statement_seconds=45, marker_seconds=55)
        output = "\n".join(actor.run("physical_declarations_and_positive_closures", prefix + policy + writes + "SELECT * FROM extensions.finish();COMMIT;"))
        matches = re.findall(r"^ok ([0-9]+) -", output, re.M)
        plans = re.findall(r"^1\.\.([0-9]+)$", output, re.M)
        if not plans or matches != [str(n) for n in range(1, int(plans[0])+1)] or re.search(r"^not ok|#\s*(SKIP|TODO)", output, re.M|re.I):
            raise ValueError("complete fixture required")
        q.record["fixture_assertions"] = len(matches)
        actor.close(); actor = None
        facts = json.loads(q.execute("runtime_original_identity", "SELECT jsonb_build_object('owner_id',owner_id,'scan_id',scan_id,'candidate_canonical',canonical_candidate,'assignment_canonical',canonical_assignment,'assignment_digest',assignment_digest) FROM internal.initial_analysis_preparation_intents;"))
        assignment = json.loads(facts["assignment_canonical"])
        backend = json.loads(q.execute("runtime_original_backend", "SELECT to_jsonb(b) FROM internal.initial_preparation_source_backends b;"))
        backend = {k: backend[k] for k in ["generation", "configuration_digest", "provider", "direct_endpoint", "private_bucket", "namespace", "credential_profile", "storage_protocol"]}
        dims = {"maximumWidth":16384,"maximumHeight":16384,"maximumPixels":100_000_000}
        config = {"identity":facts,"policy":{"profile_digest":assignment["preparation"]["profile_digest"],"verifier_build_digest":assignment["preparation"]["verifier_build_digest"],"dimensions":{r:dims for r in ["source","ai","display"]},"backend":backend},"paths":[backend["direct_endpoint"]+"/"+backend["private_bucket"]+"/"+backend["namespace"]+"/"+facts["scan_id"]+"/"+m["object_id"] for m in assignment["preparation"]["role_mapping"]]}
        counts = {"rpc":0,"media":0,"admit":0}
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def reply(self, body, content_type):
                self.send_response(200); self.send_header("Content-Length",str(len(body))); self.send_header("Content-Type",content_type); self.send_header("Cache-Control","private, no-store"); self.end_headers()
                try: self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError): pass
            def do_GET(self):
                if self.path != "/media": self.send_error(404); return
                counts["media"] += 1; self.reply(media,"image/jpeg")
            def do_POST(self):
                try:
                    operation = self.path.removeprefix("/rest/v1/rpc/")
                    if operation not in RPCS or self.path != "/rest/v1/rpc/"+operation: raise ValueError("RPC denied")
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 0 < length <= 2_000_000: raise ValueError("body bound")
                    data = json.loads(self.rfile.read(length))
                    if set(data) != set(RPCS[operation]): raise ValueError("argument shape")
                    values = []
                    for name in RPCS[operation]:
                        value = data[name]
                        if value is None: values.append("NULL")
                        elif name == "p_expected": values.append(literal(json.dumps(value))+"::JSONB")
                        elif isinstance(value,str): values.append(literal(value))
                        else: raise ValueError("argument type")
                    counts["rpc"] += 1
                    if operation == "admit_initial_cpm_photo": counts["admit"] += 1
                    sql = "BEGIN; SET LOCAL statement_timeout='12s'; SET LOCAL lock_timeout='10s'; SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL ROLE service_role; SELECT public."+operation+"("+",".join(values)+");COMMIT;"
                    if args.pending_commit and operation == "admit_initial_cpm_photo":
                        admission = observer = None
                        try:
                            admission = Session(q, "http_pending_admission")
                            observer = Session(q, "http_overlap_observer")
                            received = time.monotonic()
                            result = admission.run("admission_uncommitted", sql.removesuffix("COMMIT;"))[0]
                            overlap["receipt"] = json.loads(result)
                            overlap["funding"] = admission.run("original_uncommitted_funding", "RESET ROLE;"+FUNDING+"SET LOCAL ROLE service_role;")[0]
                            pending_admission.set()
                            if not recovery_started.wait(8): raise TimeoutError("recovery did not overlap")
                            end = time.monotonic()+2
                            blocked = False
                            while time.monotonic() < end:
                                if observer.run("observe_http_recovery_blocker", f"SELECT {admission.pid}=ANY(pg_blocking_pids({overlap['recovery_pid']}));") == ["t"]:
                                    blocked = True; break
                                time.sleep(0.02)
                            if not blocked: raise ValueError("actual recovery lock wait required")
                            q.record["pending_commit_observation"] = {"distinct_backends":len({admission.pid,observer.pid,overlap["recovery_pid"]})==3,"recovery_blocked_by_admission":True,"request_to_observed_wait_seconds":time.monotonic()-received}
                            if not q.record["pending_commit_observation"]["distinct_backends"]: raise ValueError("distinct sessions required")
                            admission.run("commit_original_after_observed_recovery", "COMMIT;")
                        finally:
                            pending_admission.clear()
                            close_overlap_sessions(observer, admission)
                    elif args.pending_commit and operation == "read_initial_cpm_photo_admission" and pending_admission.is_set():
                        recovery = Session(q, "http_overlapping_recovery")
                        try:
                            overlap["recovery_pid"] = recovery.pid
                            recovery.start("recovery_waits_then_reads_committed_receipt", sql)
                            recovery_started.set()
                            result = recovery.finish()[0]
                            if json.loads(result) != overlap["receipt"]: raise ValueError("original receipt changed")
                            overlap["matched"] = True
                        finally:
                            recovery.close()
                    else:
                        result = q.execute("http_"+operation, sql)
                    if args.lost_ack and operation == "admit_initial_cpm_photo": time.sleep(6)
                    self.reply(result.encode(),"application/json")
                except Exception as error:
                    errors.append(type(error).__name__); self.send_error(500)
        server = ThreadingHTTPServer(("127.0.0.1",0), Handler)
        thread = threading.Thread(target=server.serve_forever); thread.start()
        config["base"] = "http://127.0.0.1:"+str(server.server_port)
        started = time.monotonic()
        run = subprocess.run(DENO+["--allow-env=SUPABASE_URL,SUPABASE_SERVER_API_KEY,MERIAN_SUPABASE_SERVER_API_KEY,SUPABASE_SECRET_KEYS,SUPABASE_SECRET_KEY,SUPABASE_SERVICE_ROLE_KEY","--allow-net=127.0.0.1",str(PROBE)],input=json.dumps(config),capture_output=True,text=True,timeout=45,env={k:v for k,v in os.environ.items() if k not in ["SUPABASE_URL","SUPABASE_SERVER_API_KEY","MERIAN_SUPABASE_SERVER_API_KEY","SUPABASE_SECRET_KEYS","SUPABASE_SECRET_KEY","SUPABASE_SERVICE_ROLE_KEY"]})
        server.shutdown(); server.server_close(); thread.join(); server = None
        q.record["runtime_wall_seconds"] = time.monotonic()-started
        q.record["child_exit"] = run.returncode
        q.record["child_known_error"] = next((message for message in ["physical admission failed", "recovery repeated reads", "unexpected storage target", "initial_analysis_media_unavailable", "NotCapable", "Requires env access"] if message in run.stderr), None)
        q.record["server_errors"] = errors
        q.record["transport_counts"] = counts
        q.save()
        if run.returncode or errors: raise RuntimeError("runtime child failed; metadata evidence retained")
        q.record["runtime"] = json.loads(run.stdout)
        if args.pending_commit:
            if not overlap.get("matched"): raise ValueError("overlapping exact recovery required")
            after = q.execute("funding_unchanged_after_overlapping_recovery", FUNDING)
            if after != overlap["funding"]: raise ValueError("original funding image changed")
            q.record["pending_commit_observation"].update(exact_receipt_match=True, original_funding_unchanged=True, funding_sha256=hashlib.sha256(after.encode()).hexdigest())
        if counts["admit"] != 1 or counts["media"] != 6: raise ValueError("duplicate or incomplete execution")
        if q.execute("single_original_funding", "SELECT (SELECT count(*)=1 FROM internal.ai_quota_reservations WHERE state='reserved') AND (SELECT count(*)=1 FROM internal.initial_preparation_admission_receipts) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations);") != "t": raise ValueError("funding mismatch")
        q.execute("disable_fixture_gate", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
        q.finish()
        print("PASS local HTTP/SQL physical CPM composition")
    except Exception as error:
        if q:
            q.record["failure_class"] = type(error).__name__; q.save()
        raise
    finally:
        if actor: actor.close()
        if server: server.shutdown(); server.server_close()

if __name__ == "__main__": main()
