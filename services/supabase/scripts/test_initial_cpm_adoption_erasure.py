"""Actual CPM scan/account erasure after completion on owned disposable fixtures.

SQL lifecycle only; no physical media removal, hosted or native qualification.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_cpm_completion import run as complete
from test_initial_completion_preparation import SNAPSHOT
from test_initial_dispatch import ROLE
from initial_completion_account_erasure import run as erase_account


def run(q, mode):
    complete(q)
    q.record.update(passed=False, scope=__doc__, erasure_mode=mode)
    q.record['source_manifest'][str(Path(__file__).relative_to(ROOT))] = q.digest(Path(__file__))
    q.save()
    install_report(q)
    q.execute('install_cpm_scan_erasure_adapter', """
CREATE TABLE public.test_cpm_erasure_args AS
 SELECT a.owner_id,a.scan_id,a.submission_digest,r.result_evidence_id,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') result_digest,
 (SELECT jsonb_agg(to_jsonb(s)||'{"retired":true}'::JSONB ORDER BY object_id) FROM internal.initial_preparation_source_registry s WHERE s.scan_id=a.scan_id) retired_registry,
 (SELECT jsonb_agg(to_jsonb(w)||'{"retired":true}'::JSONB ORDER BY object_id) FROM internal.initial_cpm_photo_write_attempts w WHERE w.scan_id=a.scan_id) retired_attempts,
 (SELECT to_jsonb(c)-'owner_id' FROM internal.initial_cpm_photo_capacity_reservations c WHERE c.scan_id=a.scan_id) retained_capacity,
 (SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE h.client_scan_id=a.scan_id) funding
 FROM internal.initial_analysis_admissions a JOIN internal.initial_analysis_results r USING(scan_id,owner_id);
REVOKE ALL ON public.test_cpm_erasure_args FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_cpm_retired_liability(account_erased BOOLEAN DEFAULT FALSE) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD;
BEGIN
 SELECT * INTO STRICT a FROM public.test_cpm_erasure_args;
 IF (SELECT jsonb_agg(to_jsonb(s) ORDER BY object_id) FROM internal.initial_preparation_source_registry s WHERE s.scan_id=a.scan_id) IS DISTINCT FROM a.retired_registry
  OR (SELECT jsonb_agg(to_jsonb(w) ORDER BY object_id) FROM internal.initial_cpm_photo_write_attempts w WHERE w.scan_id=a.scan_id) IS DISTINCT FROM a.retired_attempts
  OR (SELECT owner_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=a.scan_id)
   IS DISTINCT FROM (CASE WHEN account_erased THEN NULL::UUID ELSE a.owner_id END)
  OR (SELECT to_jsonb(c)-'owner_id' FROM internal.initial_cpm_photo_capacity_reservations c WHERE c.scan_id=a.scan_id) IS DISTINCT FROM a.retained_capacity
  OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=a.scan_id AND state='retired') THEN
  RAISE EXCEPTION USING ERRCODE='ZX838'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_retired_liability(BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_cpm_erase_scan(phase TEXT) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD; denied BOOLEAN:=FALSE; outcome TEXT;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM public.test_cpm_erasure_args;
 IF phase NOT IN ('request','finish','all') THEN RAISE EXCEPTION USING ERRCODE='ZX835'; END IF;
 IF phase IN ('request','all') THEN
  outcome:=public.request_scan_deletion(a.scan_id,a.owner_id);
  IF outcome IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION USING ERRCODE='ZX835'; END IF;
 END IF;
 IF phase IN ('finish','all') AND public.complete_scan_deletion(a.scan_id,a.owner_id) IS DISTINCT FROM TRUE THEN
  RAISE EXCEPTION USING ERRCODE='ZX835'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=a.scan_id AND NOT retired)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=a.scan_id AND NOT retired)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
  OR (SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE h.client_scan_id=a.scan_id) IS DISTINCT FROM a.funding THEN
  RAISE EXCEPTION USING ERRCODE='ZX836'; END IF;
 BEGIN
  PERFORM internal.complete_initial_analysis_cpm_v1(a.owner_id,a.scan_id,a.submission_digest,a.result_evidence_id,a.result_digest,NULL,NULL);
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM IS DISTINCT FROM 'initial_analysis_deleted' THEN RAISE; END IF; denied:=TRUE;
 END;
 IF NOT denied THEN RAISE EXCEPTION USING ERRCODE='ZX837'; END IF;
 PERFORM public.test_cpm_retired_liability();
 IF phase IN ('finish','all') AND (EXISTS(SELECT 1 FROM public.scans WHERE id=a.scan_id)
  OR NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=a.scan_id AND completed_at IS NOT NULL)) THEN
  RAISE EXCEPTION USING ERRCODE='ZX839'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_erase_scan(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_erase_scan(TEXT) TO service_role;
""")
    before = q.execute('adopted_before_erasure', SNAPSHOT)
    q.execute('cpm_scan_erasure_rollback', 'BEGIN;' + ROLE + "SELECT public.test_cpm_erase_scan('all'); SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;")
    if q.execute('cpm_erasure_rollback_preserves_original', SNAPSHOT) != before:
        raise ValueError('erasure rollback changed original completion')
    for table in ['initial_cpm_photo_retention_policies', 'initial_cpm_photo_write_policies', 'initial_preparation_backend_eligibility']:
        q.execute('cpm_scan_erasure_after_revoked_' + table, 'BEGIN; UPDATE internal.' + table + " SET state='revoked';" + ROLE + "SELECT public.test_cpm_erase_scan('all'); SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;")
    if mode == 'account':
        erase_account(q, SNAPSHOT, ROLE)
        q.execute('account_erasure_leaves_no_live_adopted_sources', """
DO $$ DECLARE a RECORD; BEGIN
 SELECT * INTO STRICT a FROM public.test_cpm_erasure_args;
 PERFORM public.test_cpm_retired_liability(TRUE);
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=a.scan_id AND NOT retired)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=a.scan_id AND NOT retired)
 THEN RAISE EXCEPTION USING ERRCODE='ZX838'; END IF;
END $$;
""")
    else:
        q.execute('cpm_scan_deletion_request_commit', 'BEGIN;' + ROLE + "SELECT public.test_cpm_erase_scan('request'); COMMIT;")
        requested = q.execute('cpm_requested_snapshot', SNAPSHOT)
        q.execute('cpm_scan_deletion_request_retry', 'BEGIN;' + ROLE + "SELECT public.test_cpm_erase_scan('request'); COMMIT;")
        if q.execute('cpm_request_retry_preserves_original', SNAPSHOT) != requested:
            raise ValueError('repeated erasure request changed original state')
        q.execute('cpm_scan_deletion_finish_commit', 'BEGIN;' + ROLE + "SELECT public.test_cpm_erase_scan('finish'); COMMIT;")
    q.record['passed'] = True


def install_report(q):
    q.execute('install_disposable_original_report_adapter', """
CREATE FUNCTION public.test_completion_original_report() RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE i internal.identification_invocations; a internal.initial_analysis_admissions;
 r internal.initial_preparation_admission_receipts; reply JSONB;
BEGIN
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE is_initial_analysis;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=i.scan_id;
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=i.scan_id;
 reply:=internal.report_initial_analysis_usage(i.user_id,i.scan_id,a.submission_digest,i.id,
  (r.accounting::JSONB#>>'{reservation,lease_token}')::UUID,'draft','{"candidate_tokens":37,"input_tokens":101}');
 IF reply->>'event_id' IS NULL THEN RAISE EXCEPTION USING ERRCODE='ZX814'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_completion_original_report() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completion_original_report() TO service_role;
""")
    q.execute('original_report_before_cpm_erasure', 'BEGIN;' + ROLE + 'SELECT public.test_completion_original_report(); COMMIT;')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    parser.add_argument('--mode', choices=['scan', 'account'], required=True)
    args = parser.parse_args()
    start = time.monotonic()
    q = Qualification(args.container, args.evidence_directory, 'initial-cpm-adoption-erasure', args.replay_manifest)
    run(q, args.mode)
    q.record['wall_seconds'] = time.monotonic() - start
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
