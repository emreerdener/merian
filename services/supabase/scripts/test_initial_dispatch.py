"""Qualify private original dispatch on one fresh, owned local replay.

Uses real guarded admission and real service-role transactions. No invocation
injection, disabled guards, provider requests, hosted access or feature activation.
The qualification caller retains evidence and disposes the named database.
"""
import argparse
import json
from pathlib import Path
import hashlib
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_cpm_atomic_admission_committed import seed_committed_admission

FIXTURE = Path(__file__).with_name("fixtures") / "initial_dispatch.sql"
SCAN = "00000000-0000-4000-8000-00000000f101"
ROLE = "SELECT set_config('request.jwt.claim.role','service_role',TRUE); SET LOCAL ROLE service_role;"
CALL = "DO $$ BEGIN PERFORM public.test_initial_dispatch('" + SCAN + "',NULL); END $$;"
SNAPSHOT = """
SELECT encode(extensions.digest(convert_to(jsonb_build_object(
 'roots',internal.initial_dispatch_root_images('00000000-0000-4000-8000-00000000f101'),
 'quota',(SELECT jsonb_agg(internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q)) ORDER BY id) FROM internal.ai_quota_reservations q),
 'links',(SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::TEXT) FROM internal.ai_quota_reservation_counters c),
 'counters',(SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::TEXT) FROM internal.ai_quota_counters c),
 'attempts',(SELECT jsonb_agg(to_jsonb(a) ORDER BY reservation_id,attempt_count) FROM internal.identification_provider_attempts a),
 'invocations',(SELECT jsonb_agg(to_jsonb(i) ORDER BY id) FROM internal.identification_invocations i),
 'lifecycle',(SELECT jsonb_agg(to_jsonb(f) ORDER BY scan_id) FROM internal.initial_analysis_lifecycle_fences f),
 'holds',(SELECT jsonb_agg(to_jsonb(h) ORDER BY to_jsonb(h)::TEXT) FROM internal.complimentary_scan_usage h),
 'stages',(SELECT jsonb_agg(to_jsonb(s) ORDER BY transaction_id) FROM internal.initial_consuming_staging s)
)::TEXT,'UTF8'),'sha256'),'hex');
"""


def qualify(q, funding, media_vector=0, journey=False):
    for path in [Path(__file__), FIXTURE]:
        q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
    q.record["scope"] = (
        "Guarded original admission; actual-role private SQL dispatch, rollback "
        "faults and committed replay denial. No provider, installed execution, "
        "unexecuted media variants, concurrent order or device qualification."
    )
    q.save()
    if media_vector == 0:
        seed_committed_admission(q, funding)
        q.record['input_profile'] = 'vision_compat_v1'
    else:
        source = Path(__file__).with_name('fixtures') / 'initial_invocation_erasure.sql'
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
        prefix, owner, _ = q.fixture_prefix(held=funding == 'complimentary')
        cases = source.read_text()
        start = 'CREATE FUNCTION pg_temp.admit_erasure_scan('
        end = 'CREATE FUNCTION pg_temp.seed_admitted_invocation('
        if cases.count(start) != 1 or cases.count(end) != 1:
            raise ValueError('unique guarded admission boundaries required')
        # Reuse only guarded admission, never the injected invocation helper.
        admission = cases[cases.index(start):cases.index(end)].replace('00000000-0000-4000-8000-00000000f001', owner)
        fixture = prefix + admission + "SELECT pg_temp.admit_erasure_scan('" + SCAN + "'," + str(media_vector) + ");"
        fixture += "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE; COMMIT;"
        q.record['fixture_sha256'] = hashlib.sha256(fixture.encode()).hexdigest()
        vectors = json.loads((ROOT / 'services/supabase/tests/initial_atomic_admission_stage.sql').read_text().split('$vectors$')[1])
        q.record['input_profile'] = vectors[media_vector - 1]['profile']['spec']['input_profile']
        q.execute('commit_guarded_legacy_media_admission', fixture)
        expected_hold = 1 if funding == 'complimentary' else 0
        if q.execute('legacy_original_funding_mode', "SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='held';") != str(expected_hold):
            raise ValueError('requested original legacy funding required')
    q.record['media_vector'] = media_vector
    q.record['funding_mode'] = funding
    q.save()
    q.execute("install_disposable_dispatch_fixture", FIXTURE.read_text())
    before = q.execute("original_dispatch_snapshot", SNAPSHOT)

    def deny(label, sql, expected="55000"):
        q.execute(label, sql, expected)
        if q.execute(label + "_rollback_image", SNAPSHOT) != before:
            raise ValueError("denied dispatch changed original scope")

    for fault in ["configuration", "lease", "provenance"]:
        deny("deny_" + fault, "BEGIN;" + ROLE + CALL.replace("NULL", "'" + fault + "'") + "COMMIT;")
    for role in ["anon", "authenticated", "service_role"]:
        deny("no_private_dispatch_grant_" + role,
             "BEGIN; SET LOCAL ROLE " + role + "; SELECT internal.commit_initial_analysis_dispatch(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL); COMMIT;",
             "42501")

    # Every injected trigger is transaction-local and rolls back with the
    # rejected operation. Production guards and observers remain enabled.
    faults = [
        ("quota_suppressed", "internal.ai_quota_reservations", "BEFORE UPDATE", "RETURN NULL;"),
        ("invocation_suppressed", "internal.identification_invocations", "BEFORE INSERT", "RETURN NULL;"),
        ("lifecycle_suppressed", "internal.initial_analysis_lifecycle_fences", "BEFORE UPDATE", "RETURN NULL;"),
        ("invocation_rewritten", "internal.identification_invocations", "BEFORE INSERT", "NEW.model:='unassigned'; RETURN NEW;"),
        ("quota_rewritten", "internal.ai_quota_reservations", "BEFORE UPDATE", "NEW.committed_at:=NEW.committed_at+INTERVAL '1 second'; RETURN NEW;"),
        ("lifecycle_rewritten", "internal.initial_analysis_lifecycle_fences", "BEFORE UPDATE", "NEW.state:='pending_pre_dispatch'; RETURN NEW;"),
        ("extra_quota_statement", "internal.identification_invocations", "AFTER INSERT", "UPDATE internal.ai_quota_reservations SET updated_at=updated_at WHERE id=NEW.reservation_id; RETURN NEW;"),
        ("counter_mutation", "internal.ai_quota_reservations", "AFTER UPDATE", "UPDATE internal.ai_quota_counters SET request_count=request_count; RETURN NEW;"),
    ]
    links = int(q.execute("original_charge_link_count", "SELECT count(*) FROM internal.ai_quota_reservation_counters;"))
    q.record["original_charge_link_count"] = links
    q.record["link_suppression_applicable"] = links > 0
    if links:
        faults.append(("link_suppressed", "internal.ai_quota_reservation_counters", "BEFORE DELETE", "RETURN NULL;"))
    for label, relation, operation, body in faults:
        injection = (
            "CREATE FUNCTION public.test_dispatch_fault() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$ BEGIN "
            + body + " END $$; CREATE TRIGGER zzzz_test_dispatch_fault " + operation
            + " ON " + relation + " FOR EACH ROW EXECUTE FUNCTION public.test_dispatch_fault();"
        )
        deny(label, "BEGIN;" + injection + ROLE + CALL + "COMMIT;")

    deny("duplicate_dispatch_same_transaction", "BEGIN;" + ROLE + CALL + CALL + "COMMIT;")
    # Terminal checks must still reject a changed quota image after stage removal.
    deny("post_dispatch_quota_image_mutation", "BEGIN;" + ROLE + CALL + "RESET ROLE; UPDATE internal.ai_quota_reservations SET updated_at=updated_at+INTERVAL '1 second'; COMMIT;")
    q.execute("real_role_dispatch_and_deferred_commit", "BEGIN;" + ROLE + CALL + "COMMIT;")
    after = q.execute("committed_dispatch_snapshot", SNAPSHOT)
    q.execute("committed_replay_never_fresh", "BEGIN;" + ROLE + CALL + "COMMIT;", "55000")
    if q.execute("committed_replay_unchanged", SNAPSHOT) != after:
        raise ValueError("replay changed committed dispatch")
    q.execute("committed_original_dispatch_invariants", """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis)<>1
 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='committed' AND attempt_count=1 AND refund_count=0)<>1
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters)
 OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000f101') IS DISTINCT FROM 'dispatch_authorized'
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 THEN RAISE EXCEPTION USING ERRCODE='ZX802'; END IF;
END $$;
""")
    if journey:
        from initial_dispatch_journey import run
        for name in ['initial_dispatch_journey.py', 'initial_invocation_erasure_races.py']:
            path = Path(__file__).with_name(name)
            q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
        q.record['scope'] += ' Includes real dispatch then synthetic immutable result, original report and no-lease read; no actual inference or completion.'
        run(q)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--evidence-directory", required=True)
    parser.add_argument("--replay-manifest", required=True)
    parser.add_argument("--funding-mode", choices=["absent", "complimentary"], default="absent")
    parser.add_argument("--media-vector", type=int, choices=range(7), default=0,
                        help="0 uses guarded CPM; 1-6 reuse existing guarded legacy media vectors")
    parser.add_argument("--journey", action="store_true")
    args = parser.parse_args()
    started = time.monotonic()
    q = Qualification(args.container, args.evidence_directory, "initial-dispatch", args.replay_manifest)
    qualify(q, args.funding_mode, args.media_vector, args.journey)
    q.record["wall_seconds"] = time.monotonic() - started
    q.finish()
    print(json.dumps({"passed": True, "checks": len(q.record["checks"])}))


if __name__ == "__main__":
    main()
