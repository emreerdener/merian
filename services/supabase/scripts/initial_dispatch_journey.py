"""Local synthetic result/accounting journey after real private dispatch.

Reuses existing result fixture content. No provider execution or completion.
"""
from initial_invocation_erasure_races import install_result_fixture


def run(q):
    install_result_fixture(q, injected_dispatch=False)
    role = "BEGIN; SELECT set_config('request.jwt.claim.role','service_role',TRUE); SET LOCAL ROLE service_role;"
    q.execute("real_dispatch_result_absent", role + "SELECT public.s0_result_fixture('absent'); COMMIT;")
    q.execute("real_dispatch_result_commit", role + "SELECT public.s0_result_fixture('valid'); COMMIT;")
    q.execute("install_disposable_journey_report", """
CREATE FUNCTION public.test_dispatched_report() RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE i internal.identification_invocations; a internal.initial_analysis_admissions; r internal.initial_preparation_admission_receipts; reply JSONB;
BEGIN
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE is_initial_analysis;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=i.scan_id;
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE admission_receipt_id=i.initial_admission_receipt_id;
 reply:=internal.report_initial_analysis_usage(i.user_id,i.scan_id,a.submission_digest,i.id,
  (r.accounting::JSONB#>>'{reservation,lease_token}')::UUID,'draft','{"candidate_tokens":37,"input_tokens":101}');
 IF reply->>'event_id' IS NULL THEN RAISE EXCEPTION USING ERRCODE='ZX803'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_dispatched_report() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_dispatched_report() TO service_role;
""")
    q.execute("real_dispatch_report_commit", role + "SELECT public.test_dispatched_report(); COMMIT;")
    snapshot = """
SELECT encode(extensions.digest(convert_to(jsonb_build_object(
 'result',(SELECT jsonb_agg(to_jsonb(r)) FROM internal.initial_analysis_results r),
 'invocation',(SELECT jsonb_agg(to_jsonb(i)) FROM internal.identification_invocations i),
 'event',(SELECT jsonb_agg(to_jsonb(e)) FROM public.ai_usage_events e),
 'quota',(SELECT jsonb_agg(internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q))) FROM internal.ai_quota_reservations q),
 'credit',(SELECT jsonb_agg(to_jsonb(c)) FROM internal.complimentary_scan_usage c)
)::TEXT,'UTF8'),'sha256'),'hex');
"""
    before = q.execute("committed_journey_snapshot", snapshot)
    # Result replay and no-lease read use retained original identities after
    # accounting has attached its original event. Neither repeats inference.
    q.execute("install_disposable_journey_reader", """
CREATE FUNCTION public.test_dispatched_read() RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r internal.initial_analysis_results; a internal.initial_analysis_admissions;
 i internal.identification_invocations; receipt internal.initial_preparation_admission_receipts; reply JSONB; digest TEXT;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE scan_id=r.scan_id;
 SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE admission_receipt_id=i.initial_admission_receipt_id;
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex');
 reply:=internal.record_initial_analysis_result(r.owner_id,r.scan_id,a.submission_digest,i.id,
  (receipt.accounting::JSONB#>>'{reservation,lease_token}')::UUID,r.result_evidence_id,
  internal.initial_canonical(r.result_snapshot),internal.initial_canonical(r.provenance_snapshot),digest);
 IF reply->>'outcome' IS DISTINCT FROM 'replay' THEN RAISE EXCEPTION USING ERRCODE='ZX806'; END IF;
 reply:=internal.read_initial_analysis_result(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,digest);
 IF reply->>'outcome' IS DISTINCT FROM 'found' OR reply#>>'{evidence,result_canonical}' IS DISTINCT FROM internal.initial_canonical(r.result_snapshot)
 THEN RAISE EXCEPTION USING ERRCODE='ZX804'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_dispatched_read() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_dispatched_read() TO service_role;
CREATE FUNCTION public.test_cancelled_dispatch_read() RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE request RECORD; denied BOOLEAN:=FALSE;
BEGIN
 SELECT * INTO STRICT request FROM pg_temp.late_dispatch_result;
 BEGIN
  PERFORM internal.read_initial_analysis_result(request.owner_id,request.scan_id,request.submission_digest,request.result_evidence_id,request.digest);
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM IS DISTINCT FROM 'initial_analysis_cancelled' THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF NOT denied THEN RAISE EXCEPTION USING ERRCODE='ZX809'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_cancelled_dispatch_read() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cancelled_dispatch_read() TO service_role;
""")
    q.execute("committed_result_original_read", role + "SELECT public.test_dispatched_read(); SELECT public.test_dispatched_report(); COMMIT;")
    if q.execute("recovery_and_report_replay_unchanged", snapshot) != before:
        raise ValueError("recovery/replay changed original journey")
    q.execute("real_dispatch_report_result_invariants", """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.initial_analysis_results)<>1
 OR (SELECT count(*) FROM internal.identification_invocations i JOIN public.ai_usage_events e ON i.event_id=e.id
   WHERE i.is_initial_analysis AND e.source_id=i.id AND e.outcome='success' AND e.prompt_tokens=101 AND e.candidate_tokens=37)<>1
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 THEN RAISE EXCEPTION USING ERRCODE='ZX805'; END IF;
END $$;
""")
    q.execute("real_dispatch_result_cancellation_and_late_recovery", """
BEGIN;
CREATE TEMP TABLE late_dispatch_result AS SELECT r.owner_id,r.scan_id,r.result_evidence_id,a.submission_digest,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') digest,
 (SELECT to_jsonb(e) FROM public.ai_usage_events e JOIN internal.identification_invocations i ON i.event_id=e.id WHERE i.scan_id=r.scan_id) original_event
 FROM internal.initial_analysis_results r JOIN internal.initial_analysis_admissions a USING(scan_id);
DO $$ DECLARE request RECORD; reply JSONB; BEGIN
 SELECT * INTO STRICT request FROM late_dispatch_result;
 PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
 SET LOCAL ROLE service_role;
 reply:=public.cancel_initial_analysis(request.owner_id,request.scan_id);
 IF reply->>'dispatch' IS DISTINCT FROM 'dispatch_already_authorized' THEN RAISE EXCEPTION USING ERRCODE='ZX807'; END IF;
END $$;
COMMIT;
DO $$ DECLARE request RECORD; BEGIN
 SELECT * INTO STRICT request FROM late_dispatch_result;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_results)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions)
 OR (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 OR (SELECT to_jsonb(e) FROM public.ai_usage_events e) IS DISTINCT FROM request.original_event
 THEN RAISE EXCEPTION USING ERRCODE='ZX808'; END IF;
END $$;
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SET LOCAL ROLE service_role;
SELECT public.test_cancelled_dispatch_read();
COMMIT;
""")
