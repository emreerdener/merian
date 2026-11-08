#!/usr/bin/env python3
"""Synthetic preparation execution contention on an explicitly disposable local DB.

No hosted DSN, runtime or storage adapter. Run on a freshly migrated catalog;
restores gate=false and removes private fixture rows, leaving revoked catalogs
and permanent content-free fences. Reset before subsequent catalog suites.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import uuid
from test_initial_saved_assignment_contention import Session, literal

ROOT = Path(__file__).resolve().parents[3]
OWNER = "00000000-0000-4000-8000-00000000f001"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disposable-container", required=True)
    container = parser.parse_args().disposable_container
    assert container.startswith("supabase_db_") and all(c.isalnum() or c in "_-" for c in container)
    context = json.loads(subprocess.check_output(["docker", "context", "inspect"], text=True))[0]
    assert (os.environ.get("DOCKER_HOST") or context["Endpoints"]["docker"]["Host"]).startswith("unix://")
    info = json.loads(subprocess.check_output(["docker", "inspect", container], text=True))[0]
    assert info["HostConfig"]["PortBindings"]["5432/tcp"]
    sessions = [Session(container) for _ in range(3)]
    admin, first, second = sessions
    initialized = False

    def wait_for(blocker, waiter):
        end = time.monotonic()+3
        while time.monotonic() < end:
            if admin.run(f"SELECT {blocker.pid}=ANY(pg_blocking_pids({waiter.pid}));") == ["t"]:
                return
            time.sleep(0.02)
        raise AssertionError("expected real lock wait was not observed")

    def advance(scan, phase):
        return f"SELECT pg_temp.execution_advance({literal(scan)},{phase})->>'outcome';"

    def prepared_transition(scan,phase):
        # Save the exact incoming RPC before the race. This reaches the named
        # boundary even when cancellation erases all private rows first.
        owner,digest=admin.run(f"SELECT owner_id||'|'||assignment_digest FROM internal.initial_analysis_preparation_intents WHERE scan_id={literal(scan)};")[0].split('|')
        if phase==1:
            value=admin.run(f"SELECT pg_temp.source_receipt({literal(scan)});")[0]
            name="settle_initial_preparation_sources"
        elif phase==2:
            value=admin.run(f"SELECT pg_temp.execution_advance({literal(scan)},1)->>'digest';")[0]
            name="issue_initial_preparation_execution"
        else:
            value=admin.run(f"SELECT internal.initial_canonical(pg_temp.execution_advance({literal(scan)},{phase+10}));")[0]
            name="register_initial_preparation_output" if phase==3 else "settle_initial_preparation_outcome"
        return f"SELECT public.{name}({literal(owner)},{literal(scan)},{literal(digest)},{literal(value)})->>'outcome';"

    def cancel(scan):
        return f"SELECT public.cancel_initial_analysis('{OWNER}',{literal(scan)})->>'dispatch';"

    fixture=json.loads((ROOT/"services/supabase/functions/_shared/initialAnalysis/fixtures/media-lifecycle-v2.json").read_text())
    candidate=literal(json.dumps(fixture["valid"][2]["candidate"],ensure_ascii=False,sort_keys=True,separators=(",",":")))

    def allocate(scan, owner=OWNER):
        return f"SELECT public.create_initial_preparation_intent({literal(owner)},{literal(scan)},{candidate})->>'outcome';"

    def create():
        scan = str(uuid.uuid4())
        admin.run(f"SELECT pg_temp.media_create({literal(scan)},3)->>'outcome';")
        return scan

    def no_private(scan):
        assert admin.run("SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id="+literal(scan)+";") == ["0"]
        assert admin.run("SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id="+literal(scan)+" AND NOT retired;") == ["0"]

    try:
        assert admin.run("SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout;") == ["f"]
        assert admin.run("SELECT count(*) FROM internal.initial_preparation_profiles;") == ["0"]
        tests = (ROOT/"services/supabase/tests/initial_preparation_execution.sql").read_text()
        setup = tests.split("CREATE TEMP TABLE execution_saved",1)[0]
        setup = setup.replace("\\set ON_ERROR_STOP on", "").replace("BEGIN;", "", 1).replace("SELECT extensions.no_plan();", "")
        admin.run("BEGIN;"+setup+"COMMIT;")
        initialized = True
        helpers = setup[setup.index("CREATE FUNCTION pg_temp.source_receipt"):]
        for s in sessions:
            s.run("SELECT set_config('request.jwt.claim.role','service_role',FALSE);")
        for s in [first, second]:
            s.run(helpers)
        # Each phase commits before cancellation or observes cancellation first.
        for phase in [1, 2, 3, 4]:
            for execution_first in [True, False]:
                scan = create()
                transition=prepared_transition(scan,phase)
                first.run("BEGIN;"+(transition if execution_first else cancel(scan)))
                second.run("BEGIN;")
                pending = second.start(cancel(scan) if execution_first else transition)
                wait_for(first,second)
                first.run("COMMIT;")
                result = second.finish(pending)
                if execution_first:
                    assert "dispatch_prevented" in result, result
                    assert not any("ERROR:" in line for line in result), result
                    second.run("COMMIT;")
                else:
                    assert any("ERROR:" in line for line in result), result
                    second.run("ROLLBACK;")
                no_private(scan)
                print("PASS phase/C1 opposed order",phase,execution_first,flush=True)
        # Saved handoff eligibility serializes both source registration and issue.
        # Each race gets a NEW immutable installation/selection; revocation is terminal.
        def new_handoff_selection():
            return admin.run("WITH old AS (SELECT s.* FROM internal.initial_preparation_current_selection c JOIN internal.initial_preparation_selections s USING(generation) WHERE c.input_profile='multimodal_audio_v1'), fresh AS (INSERT INTO internal.initial_preparation_selections(generation,profile_digest,backend_generation,handoff_installation_digest) SELECT gen_random_uuid(),profile_digest,backend_generation,pg_temp.install_handoff(profile_digest,backend_generation) FROM old RETURNING *) UPDATE internal.initial_preparation_current_selection c SET generation=f.generation FROM fresh f WHERE c.input_profile='multimodal_audio_v1' RETURNING f.handoff_installation_digest;")[0]

        for phase in [1, 2]:
            for execution_first in [True, False]:
                installation = new_handoff_selection()
                scan = create()
                transition = prepared_transition(scan, phase)
                revoke = f"UPDATE internal.initial_preparation_handoff_eligibility SET state='revoked' WHERE installation_digest={literal(installation)};"
                if execution_first:
                    first.run("BEGIN;" + transition)
                    second.run("BEGIN;")
                    pending = second.start(revoke)
                    wait_for(first, second)
                    first.run("COMMIT;")
                    result = second.finish(pending)
                    assert not any("ERROR:" in line for line in result), result
                    second.run("COMMIT;")
                    digest = admin.run(f"SELECT assignment_digest FROM internal.initial_analysis_preparation_intents WHERE scan_id={literal(scan)};")[0]
                    status = admin.run(f"SELECT public.get_initial_preparation_execution_status('{OWNER}',{literal(scan)},{literal(digest)})->>'phase';")
                    assert status == ["verified" if phase == 1 else "issued"], status
                    # Exact original proof and known output/outcome remain recoverable.
                    assert "verified" in admin.run(advance(scan, 1))
                    if phase == 2:
                        assert "outcome_ready" in admin.run(advance(scan, 4))
                    else:
                        admin.run(advance(scan, 2), error="initial_analysis_handoff_qualification_unavailable")
                else:
                    first.run("BEGIN;" + revoke)
                    second.run("BEGIN;")
                    second.run(transition, error="55P03")
                    second.run("ROLLBACK;")
                    first.run("COMMIT;")
                    second.run(transition, error="initial_analysis_handoff_qualification_unavailable")
                    assert admin.run(f"SELECT count(*) FROM internal.initial_preparation_execution_grants WHERE scan_id={literal(scan)};") == ["0"]
                admin.run(cancel(scan))
                print("PASS saved handoff revocation opposed order", phase, execution_first, flush=True)
        new_handoff_selection()
        # A competing fresh issue waits and can only observe the issued bit.
        scan = create()
        first.run("BEGIN;"+advance(scan,2))
        second.run("BEGIN;")
        pending = second.start(advance(scan,2))
        wait_for(first,second)
        first.run("COMMIT;")
        result = second.finish(pending)
        assert "held" in result and not any("ERROR:" in line for line in result), result
        second.run("COMMIT;")
        assert admin.run("SELECT count(*) FROM internal.initial_preparation_execution_grants WHERE scan_id="+literal(scan)+";") == ["1"]
        admin.run(cancel(scan))
        print("PASS two issuers produce one grant",flush=True)
        # Raw competing writer triggers fail fast under a fresh allocation and
        # reject after commit. These inserts intentionally omit other fields:
        # the barrier must fire before constraints can grant any authority.
        relations = [
            ("internal.ai_quota_reservations","request_id"),
            ("internal.identification_invocations","scan_id"),
            ("internal.complimentary_scan_usage","client_scan_id"),
            ("public.scans","id"),
            ("public.scan_ingestion_jobs","scan_id"),
            ("public.scan_ingestion_intents","scan_id"),
            ("internal.initial_analysis_submissions","scan_id"),
            ("internal.initial_analysis_admissions","scan_id"),
            ("internal.initial_analysis_results","scan_id"),
            ("internal.initial_analysis_completions","scan_id"),
            ("internal.initial_analysis_media_allocation_fences","scan_id"),
            ("internal.initial_analysis_media_registry","scan_id"),
            ("internal.initial_analysis_media_cohorts","scan_id"),
            ("internal.initial_analysis_media_preparations","scan_id"),
            ("internal.initial_analysis_media_verifications","scan_id"),
            ("internal.observation_histories","observation_id"),
            ("internal.observation_analysis_source_bindings","analysis_id"),
            ("internal.observation_analysis_intents","analysis_id"),
            ("internal.observation_analysis_results","analysis_id"),
        ]
        for relation, key in relations:
            scan=str(uuid.uuid4())
            first.run("BEGIN;"+allocate(scan))
            insert=f"INSERT INTO {relation}({key}) VALUES({literal(scan)});"
            second.run(insert,error="initial_analysis_scope_busy")
            first.run("COMMIT;")
            second.run(insert,error="initial_analysis_preparation_provider_blocked")
            admin.run(cancel(scan))
            second.run(insert,error="initial_analysis_preparation_provider_blocked")
            print("PASS raw competing writer allocation/committed/retired barrier",relation,flush=True)
        # Both stale-snapshot directions reject instead of trusting advisory
        # serialization to refresh a REPEATABLE READ or SERIALIZABLE snapshot.
        for isolation in ["REPEATABLE READ", "SERIALIZABLE"]:
            scan=str(uuid.uuid4())
            first.run(f"BEGIN ISOLATION LEVEL {isolation}; SELECT count(*) FROM internal.initial_preparation_source_fences WHERE scan_id={literal(scan)};")
            admin.run(allocate(scan))
            first.run(f"INSERT INTO internal.identification_invocations(scan_id) VALUES({literal(scan)});",error="initial_analysis_isolation_unavailable")
            first.run("ROLLBACK;")
            admin.run(cancel(scan))
            scan=str(uuid.uuid4())
            first.run(f"BEGIN ISOLATION LEVEL {isolation}; SELECT count(*) FROM internal.initial_preparation_source_fences WHERE scan_id={literal(scan)};")
            first.run(allocate(scan),error="initial_analysis_isolation_unavailable")
            first.run("ROLLBACK;")
            assert admin.run(f"SELECT count(*) FROM internal.initial_preparation_source_fences WHERE scan_id={literal(scan)};")==["0"]
            print("PASS stale-snapshot writer/allocation isolation rejected",isolation,flush=True)
        # Shared ordinary writer guards coexist, with no new exclusivity.
        scan=str(uuid.uuid4())
        guard=f"SELECT internal.reject_initial_preparation_provider_writer(ARRAY[{literal(scan)}::UUID]);"
        first.run("BEGIN;"+guard)
        second.run("BEGIN;"+guard)
        # A same-transaction shared-to-exclusive upgrade must fail boundedly
        # while the other writer is live, without any partial allocation.
        first.run(allocate(scan),error="initial_analysis_scope_busy")
        first.run("ROLLBACK;")
        second.run("ROLLBACK;")
        assert admin.run(f"SELECT count(*) FROM internal.initial_preparation_source_fences WHERE scan_id={literal(scan)};")==["0"]
        assert admin.run(f"SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id={literal(scan)};")==["0"]
        first.run("BEGIN;"+guard+allocate(scan))
        first.run("ROLLBACK;")
        second.run(allocate(scan))
        admin.run(cancel(scan))
        print("PASS shared compatibility, upgrade failure and rollback release",flush=True)
        # Valid durable roots exercise writer-first exclusion. Other durable
        # facts are checked directly or excluded through required parents;
        # see the evidence matrix for the explicit proof decomposition.
        roots=[
            ("complimentary",lambda scan:f"INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES('{OWNER}',{literal(scan)});"),
            ("ingestion_job",lambda scan:f"INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code) VALUES({literal(scan)},'{OWNER}','failed_terminal','server_replay_limit_reached','replay_exhausted');"),
            ("ingestion_intent",lambda scan:f"INSERT INTO public.scan_ingestion_intents(scan_id,user_id) VALUES({literal(scan)},'{OWNER}');"),
            ("scan",lambda scan:f"INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture) VALUES({literal(scan)},'{OWNER}','{{}}',0.8,FALSE,'flash','private',TRUE);"),
            ("quota",lambda scan:f"INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id) VALUES(gen_random_uuid(),'{OWNER}','scan_identification',{literal(scan)},gen_random_uuid(),'gemini-2.5-flash','free','free','free',FALSE,1,1,{literal(scan)});"),
        ]
        for name,insert in roots:
            scan=str(uuid.uuid4())
            first.run("BEGIN;"+insert(scan))
            second.run("BEGIN;")
            pending=second.start(allocate(scan))
            # Existing owner/ingestion waits are valid; the new admission lock
            # is TRY-only and may instead reject before those waits are needed.
            end=time.monotonic()+3
            waiting=False
            while time.monotonic()<end:
                waiting=admin.run(f"SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));")==["t"]
                if waiting or not second.lines.empty():break
                time.sleep(0.02)
            assert waiting or not second.lines.empty(),"neither canonical wait nor bounded denial"
            if waiting:first.run("COMMIT;")
            result=second.finish(pending)
            expected="initial_analysis_identity_conflict" if waiting else "initial_analysis_scope_busy"
            assert any(expected in line for line in result),result
            second.run("ROLLBACK;")
            if not waiting:first.run("COMMIT;")
            second.run(allocate(scan),error="initial_analysis_identity_conflict")
            for table in ["initial_preparation_source_fences","initial_analysis_operation_fences","initial_analysis_preparation_intents"]:
                assert admin.run(f"SELECT count(*) FROM internal.{table} WHERE scan_id={literal(scan)};")==["0"]
            print("PASS valid writer-first durable conflict and no partial allocation",name,flush=True)
        # Existing same-identity settlement remains legal at repeatable read;
        # its unconditional durable row still excludes fresh preparation.
        scan=str(uuid.uuid4())
        admin.run(roots[4][1](scan))
        first.run("BEGIN ISOLATION LEVEL REPEATABLE READ;"+f"UPDATE internal.ai_quota_reservations SET lease_token=gen_random_uuid() WHERE original_analysis_id={literal(scan)};")
        second.run(allocate(scan),error="initial_analysis_identity_conflict")
        first.run("COMMIT;")
        second.run(allocate(scan),error="initial_analysis_identity_conflict")
        for table in ["initial_preparation_source_fences","initial_analysis_operation_fences","initial_analysis_preparation_intents"]:
            assert admin.run(f"SELECT count(*) FROM internal.{table} WHERE scan_id={literal(scan)};")==["0"]
        print("PASS unchanged-identity settlement preserves durable allocation exclusion",flush=True)
        # A valid old row cannot be retargeted into a fresh or retired barrier.
        for relation,key,insert in [
            ("internal.complimentary_scan_usage","client_scan_id",roots[0][1]),
            ("public.scan_ingestion_jobs","scan_id",roots[1][1]),
            ("public.scan_ingestion_intents","scan_id",roots[2][1]),
        ]:
            old=str(uuid.uuid4());scan=create()
            first.run(insert(old))
            update=f"UPDATE {relation} SET {key}={literal(scan)} WHERE {key}={literal(old)};"
            first.run(update,error="initial_analysis_preparation_provider_blocked")
            admin.run(cancel(scan))
            first.run(update,error="initial_analysis_preparation_provider_blocked")
            assert admin.run(f"SELECT count(*) FROM {relation} WHERE {key}={literal(old)};")==["1"]
            print("PASS raw rekey NEW identity permanent barrier",relation,flush=True)
        # OLD-only rekey fixture: manufacture a contradictory barrier inside a
        # rollback-only owner transaction. No legal writer can create this pair.
        old=str(uuid.uuid4()); free=str(uuid.uuid4())
        first.run(roots[0][1](old))
        first.run("BEGIN; ALTER TABLE internal.initial_preparation_source_fences DISABLE TRIGGER initial_preparation_fresh_fence;"+f"INSERT INTO internal.initial_preparation_source_fences(scan_id,state,provider_barrier) VALUES({literal(old)},'allocated','blocked_pre_admission');")
        first.run(f"UPDATE internal.complimentary_scan_usage SET client_scan_id={literal(free)} WHERE client_scan_id={literal(old)};",error="initial_analysis_preparation_provider_blocked")
        first.run("ROLLBACK;")
        assert admin.run(f"SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id={literal(old)};")==["1"]
        assert admin.run(f"SELECT count(*) FROM internal.initial_preparation_source_fences WHERE scan_id={literal(old)};")==["0"]
        print("PASS raw rekey OLD identity barrier rollback probe",flush=True)
        for alias in ["request_id","original_analysis_id"]:
            old=str(uuid.uuid4());scan=create()
            first.run(roots[4][1](old))
            first.run(f"UPDATE internal.ai_quota_reservations SET {alias}={literal(scan)} WHERE request_id={literal(old)};",error="initial_analysis_preparation_provider_blocked")
            assert admin.run(f"SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id={literal(old)} AND original_analysis_id={literal(old)};")==["1"]
            admin.run(cancel(scan))
            print("PASS crossed quota identity denied",alias,flush=True)
        # Preserve non-UUID legacy helper behavior at unsupported isolation:
        # there is no possible preparation UUID barrier to miss in that case.
        first.run("BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT internal.reject_initial_preparation_provider_writer(ARRAY[NULL]::UUID[]); ROLLBACK;")
        for phase in [1,2,3,4]:
            scan=create()
            transition=prepared_transition(scan,phase)
            admin.run(f"SELECT pg_temp.age_execution({literal(scan)});")
            assert admin.run(f"SELECT internal.can_cancel_initial_preparation('{OWNER}',{literal(scan)});")==["t"]
            first.run(f"BEGIN; SELECT internal.lock_initial_preparation_scope('{OWNER}',{literal(scan)});")
            second.run("BEGIN;")
            pending=second.start(transition)
            wait_for(first,second)
            # Wait against the database clock, not a fixed assumption about
            # fixture setup speed, while the tested RPC holds a real wait.
            end=time.monotonic()+2
            while admin.run(f"SELECT expires_at<=clock_timestamp() FROM internal.initial_analysis_preparation_intents WHERE scan_id={literal(scan)};")!=["t"]:
                assert time.monotonic()<end
                time.sleep(0.02)
            first.run("COMMIT;")
            result=second.finish(pending)
            assert "held" in result and not any("ERROR:" in line for line in result),result
            second.run("COMMIT;")
            no_private(scan)
            assert admin.run(f"SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id={literal(scan)};")==["cancelled_pre_dispatch"]
            print("PASS original expiry checked after real lock wait",phase,flush=True)
        # A cleanup lease locks only a retired object; another owner can still
        # allocate and complete its unrelated original preparation.
        owner=str(uuid.uuid4());scan=str(uuid.uuid4())
        admin.run(f"SELECT pg_temp.admission_owner({literal(owner)});")
        claim=json.loads(first.run("BEGIN; SELECT public.claim_initial_preparation_source_erasure();")[0])
        assert claim["outcome"]=="claimed",claim
        second.run(allocate(scan,owner))
        second.run(advance(scan,4))
        first.run("COMMIT;")
        obj=claim["object"]
        first.run(f"SELECT public.finish_initial_preparation_source_erasure({literal(obj['object_id'])},{literal(obj['claim_token'])},TRUE);")
        admin.run(f"DELETE FROM public.users WHERE id={literal(owner)}; DELETE FROM auth.users WHERE id={literal(owner)};")
        no_private(scan)
        print("PASS registry cleanup lease permits another owner progress",flush=True)
        # Rollback each individual transition, including issued bit and fresh
        # output registry expansion, then compare the complete private chain.
        for phase in [1,2,3,4]:
            scan=create();transition=prepared_transition(scan,phase)
            snapshot=f"SELECT jsonb_build_object('fence',(SELECT to_jsonb(f) FROM internal.initial_preparation_source_fences f WHERE scan_id={literal(scan)}),'rows',(SELECT jsonb_object_agg(name,n) FROM ("
            tables=["initial_preparation_source_verifications","initial_preparation_execution_grants","initial_preparation_output_manifests","initial_preparation_output_mapping","initial_preparation_outcomes","initial_preparation_source_registry"]
            snapshot+=' UNION ALL '.join(f"SELECT '{table}' name,count(*) n FROM internal.{table} WHERE scan_id={literal(scan)}" for table in tables)+") v));"
            before=admin.run(snapshot)
            first.run("BEGIN;"+transition+"ROLLBACK;")
            assert admin.run(snapshot)==before
            assert admin.run(f"SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id={literal(scan)} OR request_id={literal(scan)};")==["0"]
            admin.run(cancel(scan))
            print("PASS transition rollback preserves exact phase and no funding",phase,flush=True)
        # Distinct owners cannot acquire the same no-row operation identity.
        other=str(uuid.uuid4());scan=str(uuid.uuid4())
        admin.run(f"SELECT pg_temp.admission_owner({literal(other)});")
        first.run("BEGIN;"+allocate(scan))
        second.run("BEGIN;")
        pending=second.start(allocate(scan,other))
        wait_for(first,second)
        first.run("COMMIT;")
        result=second.finish(pending)
        assert any("initial_analysis_identity_conflict" in line for line in result),result
        second.run("ROLLBACK;")
        assert admin.run(f"SELECT owner_id::TEXT FROM internal.initial_analysis_preparation_intents WHERE scan_id={literal(scan)};")==[OWNER]
        admin.run(cancel(scan))
        admin.run(f"DELETE FROM public.users WHERE id={literal(other)}; DELETE FROM auth.users WHERE id={literal(other)};")
        print("PASS cross-owner no-row allocation conflict",flush=True)
        # Strong erasure removes the full known-output chain in either order.
        for phase in [1, 2, 3, 4]:
            for execution_first in [True, False]:
                scan=create()
                transition=prepared_transition(scan,phase)
                erase=f"INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES({literal(scan)},'{OWNER}',clock_timestamp());"
                if execution_first:
                    first.run("BEGIN;"+transition)
                    second.run(erase,error="55P03")
                    first.run("COMMIT;")
                    second.run(erase)
                else:
                    first.run("BEGIN;"+erase)
                    second.run("BEGIN;")
                    pending=second.start(transition)
                    wait_for(first,second)
                    first.run("COMMIT;")
                    result=second.finish(pending)
                    assert any("ERROR:" in line for line in result), result
                    second.run("ROLLBACK;")
                no_private(scan)
                print("PASS known output/scan erasure order",phase,execution_first,flush=True)
        for phase in [1, 2, 3, 4]:
            for erasure in ["supported", "raw"]:
                for execution_first in [True,False]:
                    owner=str(uuid.uuid4()); scan=str(uuid.uuid4())
                    admin.run(f"SELECT pg_temp.admission_owner({literal(owner)}); SELECT public.create_initial_preparation_intent({literal(owner)},{literal(scan)},{candidate})->>'outcome';")
                    transition=prepared_transition(scan,phase)
                    erase=(f"SELECT public.apply_user_tombstone({literal(owner)});" if erasure=="supported" else f"DELETE FROM public.users WHERE id={literal(owner)};")
                    first.run("BEGIN;"+(transition if execution_first else erase))
                    second.run("BEGIN;")
                    pending=second.start(erase if execution_first else transition)
                    wait_for(first,second)
                    first.run("COMMIT;")
                    result=second.finish(pending)
                    if execution_first:
                        assert not any("ERROR:" in line for line in result),result
                        second.run("COMMIT;")
                    else:
                        assert any("ERROR:" in line for line in result),result
                        second.run("ROLLBACK;")
                    no_private(scan)
                    admin.run(f"DELETE FROM auth.users WHERE id={literal(owner)};")
                    print("PASS preparation/account erasure order",phase,erasure,execution_first,flush=True)
    finally:
        for s in sessions:
            if s.pending is not None:
                s.finish(s.pending)
            s.run("ROLLBACK;")
        if initialized:
            admin.run("UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            admin.run("DELETE FROM internal.initial_preparation_current_selection; UPDATE internal.initial_preparation_profile_eligibility SET state='revoked' WHERE state='eligible'; UPDATE internal.initial_preparation_backend_eligibility SET state='revoked' WHERE state='eligible'; UPDATE internal.initial_preparation_handoff_eligibility SET state='revoked' WHERE state='eligible';")
            admin.run(f"BEGIN; DELETE FROM public.users WHERE id='{OWNER}'; DELETE FROM auth.users WHERE id='{OWNER}'; COMMIT;")
            for table in ["internal.ai_quota_reservations", "internal.ai_quota_counters", "internal.complimentary_scan_usage", "internal.identification_provider_attempts", "public.users"]:
                admin.run(f"DROP TRIGGER test_funding_tripwire ON {table};")
        for s in sessions:
            s.close()


if __name__ == "__main__":
    main()
