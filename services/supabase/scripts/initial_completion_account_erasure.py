"""Selected completed legacy account-erasure checks on the caller's owned database.

The existing completion runner supplies committed original completion/report
and later review. This does not qualify physical storage cleanup or account races.
"""
from pathlib import Path


def run(q, snapshot, role):
    q.record['source_manifest'][str(Path(__file__).relative_to(Path(__file__).resolve().parents[3]))] = q.digest(Path(__file__))
    q.record['completed_account_erasure'] = True
    q.save()
    q.execute('install_completed_account_erasure_adapter', """
CREATE TABLE public.test_completed_account_args AS
SELECT r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') digest,
 i.id invocation_id,
 to_jsonb(i)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id'] invocation_image,
 (to_jsonb(e)-ARRAY['user_id','scan_id','source_id','conversation_id','message_id','metadata']) ||
 jsonb_build_object('metadata',e.metadata-ARRAY['user_id','scan_id','conversation_id','message_id']) event_image
FROM internal.initial_analysis_results r JOIN internal.initial_analysis_admissions a USING(scan_id,owner_id)
JOIN internal.identification_invocations i ON i.id=(r.result_snapshot->>'invocation_id')::UUID
JOIN public.ai_usage_events e ON e.id=i.event_id;
REVOKE ALL ON public.test_completed_account_args FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_completed_account_check() RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE original RECORD; denied BOOLEAN:=FALSE;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT original FROM public.test_completed_account_args;
 IF EXISTS(SELECT 1 FROM public.users WHERE id=original.owner_id)
 OR EXISTS(SELECT 1 FROM public.scans WHERE id=original.scan_id AND (user_id IS NOT NULL OR NOT is_tombstoned))
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=original.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=original.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=original.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=original.owner_id)
 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=original.owner_id)
 OR (SELECT count(*) FROM internal.identification_invocations)<>1
 OR NOT EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE i.id=original.invocation_id
   AND internal.initial_invocation_retired(i)
   AND to_jsonb(i)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id']=original.invocation_image)
 OR (SELECT count(*) FROM public.ai_usage_events)<>1
 OR NOT EXISTS(SELECT 1 FROM public.ai_usage_events e WHERE e.user_id IS NULL AND e.scan_id IS NULL
   AND e.source_id IS NULL AND e.conversation_id IS NULL AND e.message_id IS NULL
   AND NOT e.metadata ?| ARRAY['user_id','scan_id','conversation_id','message_id']
   AND (to_jsonb(e)-ARRAY['user_id','scan_id','source_id','conversation_id','message_id','metadata']) ||
     jsonb_build_object('metadata',e.metadata-ARRAY['user_id','scan_id','conversation_id','message_id'])=original.event_image)
 THEN RAISE EXCEPTION USING ERRCODE='ZX840'; END IF;
 BEGIN
  PERFORM internal.complete_initial_analysis_legacy_v1(original.owner_id,original.scan_id,
   original.submission_digest,original.result_evidence_id,original.digest);
 EXCEPTION WHEN SQLSTATE '55000' OR SQLSTATE 'P0002' THEN
  IF NOT ((SQLSTATE='55000' AND SQLERRM='initial_analysis_deleted')
   OR (SQLSTATE='P0002' AND SQLERRM='initial_analysis_owner_unavailable')) THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF NOT denied THEN RAISE EXCEPTION USING ERRCODE='ZX841'; END IF;
END $$;
CREATE FUNCTION public.test_erase_completed_account() RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE original RECORD;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT original FROM public.test_completed_account_args;
 PERFORM public.apply_user_tombstone(original.owner_id);
 PERFORM public.test_completed_account_check();
END $$;
REVOKE ALL ON FUNCTION public.test_completed_account_check(),public.test_erase_completed_account() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completed_account_check(),public.test_erase_completed_account() TO service_role;
""")
    before = q.execute('completed_account_original_scope', snapshot)
    q.execute('completed_account_erasure_rollback', 'BEGIN;' + role + 'SELECT public.test_erase_completed_account(); SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;')
    if q.execute('completed_account_exact_rollback', snapshot) != before:
        raise ValueError('account erasure changed original completion scope after rollback')
    q.execute('completed_account_erasure_commit', 'BEGIN;' + role + 'SELECT public.test_erase_completed_account(); COMMIT;')
    q.execute('completed_account_fresh_session_retention', 'BEGIN;' + role + 'SELECT public.test_completed_account_check(); COMMIT;')
