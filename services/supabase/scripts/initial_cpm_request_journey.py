"""Join the existing disposable physical admission fixture to original dispatch and result.
No lease leaves SQL. The child consumes the prepared input with an offline synthetic receiver.
"""
import base64
import json
import hashlib
import os
import re
from pathlib import Path
import subprocess

from initial_atomic_admission_test_support import ROOT
from initial_cpm_admission_bridge_races import literal
from test_initial_cpm_completion_admission import ADAPTER
from test_initial_completion_acquisition import ADAPTER as ACQUISITION_ADAPTER

PROBE = Path(__file__).with_name("initial_cpm_request_probe.ts")
SQL = Path(__file__).with_name("fixtures") / "initial_cpm_request_journey.sql"


def run(q, config, roster, native_bridge=None):
    for path in [Path(__file__), PROBE, SQL, Path(__file__).with_name("test_initial_cpm_completion_admission.py"),
                 Path(__file__).with_name("test_initial_completion_acquisition.py")]:
        q.record["source_manifest"][str(path.resolve().relative_to(ROOT))] = q.digest(path)
    q.execute("install_disposable_original_request_adapters", ADAPTER + ACQUISITION_ADAPTER + SQL.read_text())

    def service(label, statement, expected=None):
        return q.execute(label, "BEGIN; SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL ROLE service_role; " +
                         statement + "; COMMIT;", expected)

    def argument(value):
        return literal(json.dumps(value, ensure_ascii=False)) + "::jsonb"

    def probe(mode, value):
        command = ["deno", "run", "--cached-only", "--frozen", "--deny-net", "--no-prompt",
                   "--allow-env=GOOGLE_SDK_NODE_LOGGING,GOOGLE_GENAI_DEBUG,WS_NO_BUFFER_UTIL,WS_NO_UTF_8_VALIDATE,GOOGLE_GENAI_USE_ENTERPRISE,GOOGLE_GENAI_USE_VERTEXAI,GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_LOCATION,GOOGLE_VERTEX_BASE_URL,GOOGLE_GEMINI_BASE_URL,GOOGLE_API_KEY,GEMINI_API_KEY",
                   "--config", str(ROOT / "services/supabase/functions/deno.json"), str(PROBE), mode] + (["--public-wire"] if native_bridge and mode == "deliver" else [])
        child = subprocess.run(command, input=json.dumps(value), text=True, capture_output=True, timeout=25, env={"PATH": os.environ["PATH"]})
        if child.returncode:
            # Child input and output may contain synthetic submitted content.
            owners = [name for name in ("initial_media_unavailable", "NotCapable", "original grant or parameters mismatch",
                                       "serialized evidence mismatch","unexpected fixture request","initial_result_invalid") if name in child.stderr]
            q.record["request_probe_failure"] = {"mode": mode, "exit": child.returncode, "categories": owners,
                "locations": re.findall(r"/(cpm[A-Za-z]+|mediaHandoffStorage|initial_cpm_request_probe)\.ts:(\d+):\d+",child.stderr)[:6]}
            q.save()
            raise RuntimeError("local request probe failed")
        return json.loads(child.stdout)

    ack = json.loads(service("original_admission_for_preparation", "SELECT public.test_cpm_ack(NULL)"))
    if native_bridge: native_bridge.project_admission(q, config, ack)
    def status(label, outcome, evidence=None):
        reply = json.loads(service(label, "SELECT public.test_acquisition()"))
        result = probe("deliver", {"admission": ack["admission_canonical"], "reply": reply,
                                   "outcome": outcome, "result": evidence})
        if native_bridge: native_bridge.capture(label, result.pop("body_base64"), result)
        return result

    service("completion_lookup_requires_original_dispatch", "SELECT public.test_acquisition()", "55000")
    if "internal.lock_initial_dispatched_original" not in q.record["checks"][-1]["error_owners"]:
        raise RuntimeError("unexpected pre-dispatch completion denial")
    backend = config["policy"]["backend"]
    original = dict(config["identity"], backend_generation=backend["generation"],
                    backend_configuration_digest=backend["configuration_digest"])
    cfg = json.loads(original["assignment_canonical"])["configuration"]
    q.record["synthetic_request_profile"] = {k:cfg[k] for k in ("provider","binding","input_profile","route","effective_model",
        "policy_version","effective_tier","operation","processor_permission","output_language")}
    q.save()
    packet = probe("prepare", {"original": original, "policy": config["policy"], "ack": ack,
                               "syntheticAI": [base64.b64encode(member).decode("ascii") for member in roster[1::3]]})
    binding, provenance = packet["binding"], argument(packet["provenance"])
    service("substituted_funding_refused", "SELECT public.test_cpm_request_dispatch(" +
            argument(dict(binding, funding_binding_digest="0"*64)) + "," + provenance + ")", "ZX881")
    grant = json.loads(service("commit_original_photo_dispatch", "SELECT public.test_cpm_request_dispatch(" +
                               argument(binding) + "," + provenance + ")"))
    if grant.get("outcome") != "fresh":
        raise RuntimeError("fresh original required")
    before = status("pending_status_after_original_dispatch", "pending")
    content = json.loads(json.loads(original["candidate_canonical"])["content_canonical"])
    contexts = [base64.b64decode(entry["text_utf8_base64"], validate=True).decode("utf-8")
                for entry in content["contexts"]]
    result = probe("synthetic-result", {"grant": grant, "packet": packet, "contexts": contexts,
                   "expectedAI": [hashlib.sha256(member).hexdigest() for member in roster[1::3]]})
    evidence = result["evidence"]
    reference = evidence["reference"]
    if reference["invocation_id"] != grant["invocation_id"] or result["syntheticCalls"] != 1:
        raise RuntimeError("fixture did not use the original grant")
    service("report_original_photo_usage", "SELECT public.test_cpm_request_report(" + argument(reference) +
            "," + literal(json.dumps(result["usage"], separators=(",",":"),sort_keys=True)) + ")")
    service("commit_original_photo_result_reply_discarded", "SELECT public.test_cpm_request_store(" + argument(evidence) + ")")
    recovered = json.loads(service("recover_exact_committed_photo_result", "SELECT public.test_cpm_request_recover(" +
                                   argument(reference) + "," + literal(evidence["result_digest"]) + ")"))
    if recovered.get("evidence") != evidence:
        raise RuntimeError("recovered result differs from prepared invocation evidence")
    check = q.execute("single_committed_charge_invocation_report_result", """
SELECT (SELECT count(*)=1 AND bool_and(state='committed') FROM internal.ai_quota_reservations)
 AND (SELECT count(*)=1 AND bool_and(event_id IS NOT NULL) FROM internal.identification_invocations WHERE is_initial_analysis)
 AND (SELECT count(*)=1 FROM internal.initial_analysis_results);
""")
    if check != "t":
        raise RuntimeError("unexpected original accounting or result count")
    q.record["prepared_photo_journey"] = {"offline_synthetic_replies":1, "original_committed_dispatches":1,
        "original_results":1, "usage_event_linked":True, "exact_recovered":True,
        "parameters_sha256":packet["parametersDigest"],"installed_artifact":False}
    q.save()
    unpublished = status("immutable_result_alone_is_pending", "pending")
    if unpublished["sha256"] != before["sha256"]:
        raise RuntimeError("unsettled result changed pending response")
    finish_with_original_media(q, config, roster, reference, evidence["result_digest"], service, argument)
    delivered = status("original_completion_status_delivery", "found", evidence)
    q.record["prepared_photo_journey"]["status"] = {
        "before_dispatch": "original-dispatched reader refused", "pending_after_dispatch": before, "pending_before_completion": unpublished,
        "completed": delivered}
    q.save()


def finish_with_original_media(q, config, roster, reference, digest, service, argument):
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from threading import Thread
    from test_initial_cpm_retention import install_disposable_retention

    retention_probe = Path(__file__).with_name("initial_cpm_request_retention_probe.ts")
    for path in (retention_probe, Path(__file__).with_name("test_initial_cpm_retention.py")):
        q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
    install_disposable_retention(q)
    sql_read = "SELECT public.test_cpm_terminal()"
    terminal = json.loads(service("original_terminal_roster", sql_read))
    reads = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            if self.path == "/current":
                content = service("recheck_exact_terminal_roster",sql_read).encode()
                mime = "application/json"
            elif self.path == "/objects/" + str(len(reads)) and len(reads) < len(config["paths"]):
                content = roster[len(reads)]
                mime = config.get("media_types", ["image/jpeg"] * 6)[len(reads)]
                reads.append(self.path)
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Cache-Control", "private, no-store")
            self.send_header("Content-Type",mime)
            self.send_header("Content-Length",str(len(content)))
            self.end_headers()
            self.wfile.write(content)
    with HTTPServer(("127.0.0.1",0),Handler) as server:
        thread = Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            port = server.server_port
            command = ["deno","run","--cached-only","--frozen","--no-prompt","--deny-env",
                       "--allow-net=127.0.0.1:"+str(port),"--config",str(ROOT/"services/supabase/functions/deno.json"),str(retention_probe)]
            child = subprocess.run(command,input=json.dumps(dict(config,terminal=terminal,base=f"http://127.0.0.1:{port}")),
                                   text=True,capture_output=True,timeout=50,env={"PATH":os.environ["PATH"]})
            if child.returncode:
                raise RuntimeError("disposable terminal verifier failed")
            verified=json.loads(child.stdout)
        finally:
            server.shutdown()
            thread.join()
    if len(reads)!=6 or verified["reads"]!=6:
        raise RuntimeError("incomplete terminal byte verification")
    def complete(proof):
        return "SELECT public.test_cpm_request_complete("+argument(reference)+","+literal(digest)+","+proof+")"
    fresh=json.loads(service("original_two_photo_completion",complete(argument(verified["proof"]))))
    replay=json.loads(service("exact_completion_replay_without_verification",complete("NULL")))
    if fresh.pop("outcome")!="fresh" or replay.pop("outcome")!="replay" or fresh!=replay:
        raise RuntimeError("uncertain completion did not recover the original")
    if len(fresh["projection"]["media"]["items"])!=2:
        raise RuntimeError("original two-photo projection missing")
    q.record["prepared_photo_journey"].update(terminal_reads=6,distinct_role_fixtures=len(set(roster)),current_checks=verified["currentChecks"],two_photo_completion=True,
        exact_completion_replay=True)
    q.save()
