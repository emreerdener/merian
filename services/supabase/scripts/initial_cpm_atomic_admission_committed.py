"""Owned disposable CPM admission with existing public C1/account-erasure cases.

Uses the same locked-source replay and qualification owner as legacy admission.
No hosted DSN, provider/blob IO, rollout activation outside the synthetic fixture,
or native journey qualification. Generated identities and snapshots stay in memory.
"""
import argparse
import hashlib
import json
import re
import time
from pathlib import Path

from initial_atomic_admission_test_support import Qualification, ROOT

FIXTURE = ROOT / "services/supabase/tests/initial_cpm_photo_intents.sql"
MARKER = "-- END CPM COMMITTED ADMISSION FIXTURE\n"
RETAINED = """
SELECT jsonb_build_object(
 'capacity',(SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_cpm_photo_capacity_reservations c),
 'attempts',(SELECT jsonb_agg(to_jsonb(w) ORDER BY object_id) FROM internal.initial_cpm_photo_write_attempts w),
 'closures',(SELECT jsonb_agg(to_jsonb(c) ORDER BY attempt_id) FROM internal.initial_cpm_photo_write_closures c));
"""



def cancellation_cases(q):
    base = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',TRUE);"
    call = "public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101')"
    for role in ["anon", "authenticated"]:
        q.execute(role + "_public_cancellation_denied", base + "SET LOCAL ROLE " + role + ";SELECT " + call + ";ROLLBACK;", "42501")
    q.execute("wrong_owner_cancellation_denied", base + "SET LOCAL ROLE service_role;SELECT " + call.replace("00000000-0000-4000-8000-00000000f001", "00000000-0000-4000-8000-00000000f002") + ";ROLLBACK;", "P0002")
    positive = """
DO $$ DECLARE result JSONB; BEGIN
 SET LOCAL ROLE service_role;
 result:=""" + call + """;
 IF result IS DISTINCT FROM '{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}'::JSONB
 THEN RAISE EXCEPTION USING ERRCODE='ZX602'; END IF;
 RESET ROLE;
 IF NOT internal.initial_cancellation_sealed()
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='refunded' AND refund_count=1)<>1
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters)
 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE state<>'released' OR settlement_reason<>'cancelled_before_dispatch')
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 THEN RAISE EXCEPTION USING ERRCODE='ZX603'; END IF;
 PERFORM internal.assert_initial_cancellation_transients_absent('00000000-0000-4000-8000-00000000f101');
END $$;
"""
    q.execute("actual_service_cancellation_rollback_deferred", base + positive + "SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;")
    q.execute("actual_service_cancellation_commit_deferred", base + positive + "SET CONSTRAINTS ALL IMMEDIATE;COMMIT;")
    q.execute("fresh_session_exact_replay_no_second_refund", base + """
DO $$ DECLARE result JSONB; BEGIN
 SET LOCAL ROLE service_role;
 result:=""" + call + """;
 RESET ROLE;
 IF result IS DISTINCT FROM '{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}'::JSONB
 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='refunded' AND refund_count=1)<>1
 OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 THEN RAISE EXCEPTION USING ERRCODE='ZX604'; END IF;
END $$; COMMIT;
""")



def account_erasure_cases(q, before, *, classified_invocation=False, reported_invocation=False):
    """Actual service-role account deletion, with rollback and permanent liability checks."""
    if reported_invocation and not classified_invocation:
        raise ValueError('reported invocation requires classified account fixture')
    owner = "00000000-0000-4000-8000-00000000f001"
    base = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',TRUE);"
    call = "SET LOCAL ROLE service_role;SELECT public.apply_user_tombstone('" + owner + "');RESET ROLE;"
    funding_projection = "jsonb_build_array(" + ",".join(
        "(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + r + " t)"
        for r in ["internal.ai_quota_reservations", "internal.ai_quota_reservation_counters",
                  "internal.ai_quota_counters", "internal.complimentary_scan_usage",
                  "internal.identification_provider_attempts"]
    ) + ")"
    witness = "CREATE TEMP TABLE account_original_funding AS SELECT " + funding_projection + " AS value;" + """
CREATE TEMP TABLE account_settlement_witness(kind TEXT);
CREATE FUNCTION pg_temp.account_settlement_witness() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN
 IF OLD.id='00000000-0000-4000-8000-00000000f001' THEN
  IF (SELECT value FROM account_original_funding) IS DISTINCT FROM $FUNDING$
  OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging)
  THEN RAISE EXCEPTION USING ERRCODE='ZX631'; END IF;
  IF TG_NAME='a00_cpm_account_before_fence' AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND dispatch='dispatch_outcome_unknown')
  THEN RAISE EXCEPTION USING ERRCODE='ZX633'; END IF;
  IF TG_NAME='z99_cpm_account_after_fence' AND EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000f101')
  THEN RAISE EXCEPTION USING ERRCODE='ZX634'; END IF;
  INSERT INTO account_settlement_witness VALUES(TG_NAME);
 END IF;
 RETURN OLD;
END $$;
CREATE TRIGGER a00_cpm_account_before_fence BEFORE DELETE ON public.users
 FOR EACH ROW EXECUTE FUNCTION pg_temp.account_settlement_witness();
CREATE TRIGGER z99_cpm_account_after_fence BEFORE DELETE ON public.users
 FOR EACH ROW EXECUTE FUNCTION pg_temp.account_settlement_witness();
DO $$ BEGIN
 IF (SELECT array_agg(tgname::TEXT ORDER BY tgname) FROM pg_trigger WHERE tgrelid='public.users'::REGCLASS AND tgtype=11 AND tgenabled='O'
 AND tgname IN ('a00_cpm_account_before_fence','fence_initial_analysis_before_owner_delete','z99_cpm_account_after_fence'))
 IS DISTINCT FROM ARRAY['a00_cpm_account_before_fence','fence_initial_analysis_before_owner_delete','z99_cpm_account_after_fence']::TEXT[]
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.users'::REGCLASS AND tgname='fence_initial_analysis_before_owner_delete'
 AND tgfoid='internal.fence_initial_analysis_before_owner_delete()'::REGPROCEDURE)
 THEN RAISE EXCEPTION USING ERRCODE='ZX635'; END IF;
END $$;
"""
    witness = witness.replace("$FUNDING$", funding_projection)
    if classified_invocation:
        # Classified work uses permanent scan tombstone authority, never C1.
        old = "IF TG_NAME='a00_cpm_account_before_fence' AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND dispatch='dispatch_outcome_unknown')"
        new = """IF EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000f101')
  OR NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND user_id IS NULL AND completed_at IS NOT NULL)"""
        if witness.count(old) != 1:
            raise ValueError('unique unclassified account witness required')
        witness = witness.replace(old, new)
        witness = "CREATE TEMP TABLE account_original_event(value JSONB);" + witness
        witness = witness.replace('  INSERT INTO account_settlement_witness VALUES(TG_NAME);', """
  IF TG_NAME='a00_cpm_account_before_fence' THEN
   INSERT INTO account_original_event SELECT to_jsonb(e) FROM public.ai_usage_events e
    JOIN internal.identification_invocations i ON i.event_id=e.id;
  END IF;
  INSERT INTO account_settlement_witness VALUES(TG_NAME);""")
    checked = """
DO $$ BEGIN IF (SELECT array_agg(kind ORDER BY kind) FROM account_settlement_witness)
 IS DISTINCT FROM ARRAY['a00_cpm_account_before_fence','z99_cpm_account_after_fence']::TEXT[]
 THEN RAISE EXCEPTION USING ERRCODE='ZX632';END IF; END $$;
DROP TRIGGER a00_cpm_account_before_fence ON public.users;
DROP TRIGGER z99_cpm_account_after_fence ON public.users;
"""
    if classified_invocation:
        checked += """
DO $$ BEGIN
 IF (SELECT count(*) FROM account_original_event)<>1
 OR (SELECT to_jsonb(e) FROM public.ai_usage_events e) IS DISTINCT FROM
   (SELECT value || jsonb_build_object('user_id',NULL,'scan_id',NULL,'source_id',NULL,
     'conversation_id',NULL,'message_id',NULL,'metadata',(value->'metadata')-ARRAY['user_id','scan_id','conversation_id','message_id'])
    FROM account_original_event)
 THEN RAISE EXCEPTION USING ERRCODE='ZX637'; END IF;
END $$;
"""
    retained_invocation = """SELECT encode(extensions.digest(convert_to(
 COALESCE(jsonb_agg(to_jsonb(i)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id','event_id'] ORDER BY i.id),'[]'::JSONB)::TEXT,
 'UTF8'),'sha256'),'hex') FROM internal.identification_invocations i;"""
    if reported_invocation:
        if retained_invocation.count(",'event_id'") != 1:
            raise ValueError('unique pending event exclusion required')
        retained_invocation = retained_invocation.replace(",'event_id'", "")
    retained_event = """SELECT encode(extensions.digest(convert_to(COALESCE(jsonb_agg(
 (to_jsonb(e)-ARRAY['user_id','scan_id','source_id','conversation_id','message_id','metadata']) ||
 jsonb_build_object('metadata',(e.metadata)-ARRAY['user_id','scan_id','conversation_id','message_id']) ORDER BY e.id),
 '[]'::JSONB)::TEXT,'UTF8'),'sha256'),'hex') FROM public.ai_usage_events e;"""
    original_event = q.execute('account_original_completed_event', retained_event) if reported_invocation else None
    original_invocation = q.execute('account_original_invocation_identity', retained_invocation) if classified_invocation else None
    # Whole internal-table images prove rollback restores the original funding,
    # private roots and transients, not just the retained-media subset.
    image = """
DO $$ DECLARE t RECORD; BEGIN
 CREATE TEMP TABLE account_images(name TEXT PRIMARY KEY, value JSONB);
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='internal' ORDER BY tablename LOOP
  EXECUTE format('INSERT INTO account_images SELECT %L,COALESCE(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::TEXT),''[]''::JSONB) FROM internal.%I x',t.tablename,t.tablename);
 END LOOP;
 INSERT INTO account_images SELECT 'public.users',COALESCE(jsonb_agg(to_jsonb(u) ORDER BY id),'[]'::JSONB) FROM public.users u;
 INSERT INTO account_images SELECT 'public.ai_usage_events',COALESCE(jsonb_agg(to_jsonb(e) ORDER BY id),'[]'::JSONB) FROM public.ai_usage_events e;
END $$;
SELECT encode(extensions.digest(convert_to(jsonb_object_agg(name,value ORDER BY name)::TEXT,'UTF8'),'sha256'),'hex') FROM account_images;
"""
    original = q.execute("account_original_internal_image", "BEGIN;" + image + "ROLLBACK;")
    assertions = """
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001')
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE owner_id='00000000-0000-4000-8000-00000000f001')
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations)
 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND state='cancelled_unknown')
 OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND NOT retired)
 OR NOT internal.initial_admitted_settlement_blocked('00000000-0000-4000-8000-00000000f101')
 OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX630'; END IF;
 PERFORM internal.assert_initial_cancellation_transients_absent('00000000-0000-4000-8000-00000000f101');
END $$;
"""
    if classified_invocation:
        original_absence = ' OR EXISTS(SELECT 1 FROM internal.identification_invocations)'
        if assertions.count(original_absence) != 1:
            raise ValueError('unique invocation erasure assertion required')
        assertions = assertions.replace(original_absence, """
 OR (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 OR (SELECT count(*) FROM internal.identification_invocations)<>1
 OR (SELECT count(*) FROM public.ai_usage_events)<>1
 OR (SELECT count(*) FROM public.ai_usage_events e JOIN internal.identification_invocations i ON i.event_id=e.id
      WHERE i.is_initial_analysis AND e.outcome='unknown' AND e.user_id IS NULL AND e.scan_id IS NULL
       AND e.source_id IS NULL AND e.conversation_id IS NULL AND e.message_id IS NULL
       AND NOT e.metadata ?| ARRAY['user_id','scan_id','conversation_id','message_id'])<>1
""")
    if reported_invocation:
        assertions = assertions.replace("e.outcome='unknown'", "e.outcome='success' AND e.metadata->>'ai_outcome'='draft'")
    q.execute("account_erasure_rollback_deferred", base + witness + call + checked + assertions + ("SET LOCAL ROLE service_role;" if classified_invocation else "") + "SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;")
    restored = q.execute("account_rollback_exact_original_internal_image", "BEGIN;" + image + "ROLLBACK;")
    if original != restored:
        raise ValueError("account erasure rollback changed original internal data")
    q.execute("account_erasure_commit_deferred", base + witness + call + checked + assertions + ("SET LOCAL ROLE service_role;COMMIT;" if classified_invocation else "SET CONSTRAINTS ALL IMMEDIATE;COMMIT;"))
    after = json.loads(q.execute("account_ownerless_permanent_media", RETAINED))
    for capacity in before["capacity"]:
        if capacity["owner_id"] == owner:
            capacity["owner_id"] = None
            if capacity["state"] == "pending" and capacity["write_capability_state"] == "never_issued":
                capacity["state"] = "released"
    for attempt in before["attempts"]:
        attempt["retired"] = True
    if before != after:
        raise ValueError("account erasure changed permanent media beyond owner unlink and retirement")
    q.execute("account_fresh_session_erasure_and_liability", assertions)
    if classified_invocation and original_invocation != q.execute('account_exact_original_invocation_identity', retained_invocation):
        raise ValueError('account erasure changed retained original invocation fields')
    if reported_invocation and original_event != q.execute('account_exact_original_completed_event', retained_event):
        raise ValueError('account erasure changed original completed usage event')


def retained_receipt_cases(q):
    """Private retained proof only; no public recovery envelope or elapsed expiry."""
    projection = "jsonb_build_array(" + ",".join(
        "(SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT) FROM " + relation + " t)"
        for relation in ["internal.initial_analysis_preparation_intents",
                         "internal.initial_preparation_admission_receipts",
                         "internal.initial_analysis_submissions", "internal.initial_analysis_admissions",
                         "internal.ai_quota_reservations", "internal.ai_quota_reservation_counters",
                         "internal.ai_quota_counters", "internal.complimentary_scan_usage",
                         "internal.identification_provider_attempts", "internal.identification_invocations"]
    ) + ")"
    before = q.execute("retained_original_admission_and_funding", "SELECT " + projection + ";")
    base = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',TRUE);"
    q.execute("retained_exact_original_proof_after_policy_revocation", base + """
UPDATE internal.initial_cpm_photo_profile_eligibility SET state='revoked';
UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
DO $$ DECLARE original internal.initial_preparation_admission_receipts; recovered internal.initial_preparation_admission_receipts;
BEGIN
 SELECT * INTO STRICT original FROM internal.initial_preparation_admission_receipts;
 PERFORM internal.lock_initial_preparation_scope(original.owner_id,original.scan_id);
 recovered:=internal.initial_admission_retained_receipt(original.owner_id,original.scan_id,original.admission_receipt_id);
 IF to_jsonb(recovered) IS DISTINCT FROM to_jsonb(original)
 OR to_jsonb(internal.initial_admission_retained_receipt(original.owner_id,original.scan_id,original.admission_receipt_id))
    IS DISTINCT FROM to_jsonb(original)
 THEN RAISE EXCEPTION USING ERRCODE='ZX620'; END IF;
END $$;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;
""")
    for role in ["anon", "authenticated", "service_role"]:
        q.execute(role + "_cannot_call_private_retained_parser", base + """
DO $$ DECLARE r internal.initial_preparation_admission_receipts; BEGIN
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts;
 SET LOCAL ROLE """ + role + """;
 PERFORM internal.initial_admission_retained_receipt(r.owner_id,r.scan_id,r.admission_receipt_id);
END $$;ROLLBACK;
""", "42501")
    for wrong in ["owner_id", "scan_id", "admission_receipt_id"]:
        q.execute("retained_wrong_" + wrong + "_rejected", base + """
DO $$ DECLARE r internal.initial_preparation_admission_receipts; BEGIN
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts;
 r.""" + wrong + """:=gen_random_uuid();
 PERFORM internal.initial_admission_retained_receipt(r.owner_id,r.scan_id,r.admission_receipt_id);
END $$;ROLLBACK;
""", "55000")
    for call in ["public.get_initial_preparation_status(r.owner_id,r.scan_id)",
                 "public.finalize_initial_preparation(r.owner_id,r.scan_id,ad)"]:
        q.execute("unintegrated_legacy_recovery_refuses_cpm_" + call.split("(")[0], base + """
DO $$ DECLARE r internal.initial_preparation_admission_receipts; ad TEXT; BEGIN
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts;
 ad:=internal.initial_cpm_photo_digest('assignment',internal.initial_canonical(r.configuration::JSONB->'assignment'));
 SET LOCAL ROLE service_role;
 PERFORM """ + call + ";END $$;ROLLBACK;", "55000")
    after = q.execute("retained_recovery_does_not_reverify_or_fund", "SELECT " + projection + ";")
    if before != after:
        raise ValueError("retained reads changed original operation or accounting")


def seed_committed_admission(q, funding_mode, *, scan_id='00000000-0000-4000-8000-00000000f101'):
    """Reuse the guarded committed CPM fixture; snapshots remain in memory."""
    if funding_mode not in ('absent', 'complimentary'):
        raise ValueError('known local funding mode required')
    for path in [FIXTURE, Path(__file__).resolve()]:
        q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
    q.save()
    source = FIXTURE.read_text()
    if source.count(MARKER) != 1:
        raise ValueError("unique committed fixture boundary required")
    prefix = source.split(MARKER)[0]
    if not re.fullmatch('[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', scan_id):
        raise ValueError('canonical synthetic scan identity required')
    prefix = prefix.replace('00000000-0000-4000-8000-00000000f101', scan_id)
    if re.search(r"^COMMIT;", prefix, re.M):
        raise ValueError("fixture must retain its outer transaction")
    if funding_mode == "complimentary":
        anchor = "SELECT extensions.no_plan();"
        if prefix.count(anchor) != 1:
            raise ValueError("unique fixture start required")
        prefix = prefix.replace(anchor, anchor + "\nUPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';", 1)
    q.record["funding_mode"] = funding_mode
    fixture = prefix + "SELECT * FROM extensions.finish();\nCOMMIT;\n"
    q.record["fixture_sha256"] = hashlib.sha256(fixture.encode()).hexdigest()
    output = q.execute("commit_complete_cpm_admission", fixture)
    assertions = re.findall(r"^ok ([0-9]+) - .*$", output, re.M)
    if (assertions != [str(i) for i in range(1, 141)]
            or re.findall(r"^1\.\.([0-9]+)$", output, re.M) != ["140"]
            or re.search(r"^not ok|#\s*(?:SKIP|TODO)", output, re.M | re.I)):
        raise ValueError("all 140 fixture assertions and complete unskipped plan required")
    q.record["fixture_assertions"] = 140
    q.execute("disable_local_fixture_rollout", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
    funding = q.execute("original_funding_mode", """
SELECT jsonb_build_object('reservations',count(*),'linked',count(complimentary_client_scan_id),
 'held',(SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='held'))
FROM internal.ai_quota_reservations WHERE state='reserved' AND refund_count=0;
""")
    expected_credit = 1 if funding_mode == "complimentary" else 0
    if json.loads(funding) != {"reservations": 1, "linked": expected_credit, "held": expected_credit}:
        raise ValueError("original reservation and exact requested credit mode required")
    before = json.loads(q.execute("original_retained_media_snapshot", RETAINED))
    if (sum(c["state"] == "admitted" for c in before["capacity"]) != 1
            or len(before["attempts"]) != 3 or len(before["closures"]) != 3
            or any(a["retired"] for a in before["attempts"])):
        raise ValueError("exact original admitted media cohort required")
    return before


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--evidence-directory", required=True)
    parser.add_argument("--replay-manifest", required=True)
    parser.add_argument("--funding-mode", choices=["absent", "complimentary"], default="absent")
    parser.add_argument("--operation", choices=["cancellation", "account-erasure"], default="cancellation")
    args = parser.parse_args()
    q = None
    started = time.monotonic()
    try:
        q = Qualification(args.container, args.evidence_directory,
                          "cpm-committed-admission-c1", args.replay_manifest)
        q.record["operation"] = args.operation
        before = seed_committed_admission(q, args.funding_mode)
        if args.operation == "account-erasure":
            q.record["scope"] = "Committed CPM held/absent admission followed by actual service-role account erasure rollback/commit and ownerless retained liability; no multi-item or concurrent order qualification."
            account_erasure_cases(q, before)
            q.record["wall_seconds"] = time.monotonic() - started
            q.finish()
            print("PASS committed CPM account erasure; local synthetic scope only", flush=True)
            return 0
        # Exercise the existing public C1 owner with the actual service role.
        retained_receipt_cases(q)
        cancellation_cases(q)
        after = json.loads(q.execute("retained_media_after_committed_cancellation", RETAINED))
        for attempt in before["attempts"]:
            attempt["retired"] = True
        if before != after:
            raise ValueError("only original attempt retirement bits may change")
        q.execute("private_erasure_and_permanent_liability", """
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='00000000-0000-4000-8000-00000000f101')
 OR NOT internal.initial_admitted_settlement_blocked('00000000-0000-4000-8000-00000000f101')
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 THEN RAISE EXCEPTION USING ERRCODE='ZX601'; END IF;
END $$;
""")
        q.record["wall_seconds"] = time.monotonic() - started
        q.finish()
        print("PASS committed CPM admission and C1; local synthetic scope only", flush=True)
        return 0
    except Exception as error:
        if q is not None:
            q.record.update(error_category=type(error).__name__, wall_seconds=time.monotonic() - started)
            q.save()
            try:
                q.execute("restore_disabled_gate_after_failure", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            except Exception:
                q.record["gate_restore_failed"] = True
                q.save()
        print("FAIL committed CPM admission: " + type(error).__name__, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
