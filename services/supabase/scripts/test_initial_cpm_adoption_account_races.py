"""CPM adoption versus real account erasure in both committed orders.

A saved synthetic proof crosses the transaction boundary before either race.
No direct retirement writes, physical IO, hosted or native qualification.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session
from initial_invocation_erasure_races import wait_for_blocker
from test_initial_cpm_completion import initialize
from test_initial_cpm_adoption_erasure import install_report
from test_initial_dispatch import ROLE


def run(q, order):
    initialize(q)
    install_report(q)
    q.record.update(passed=False, scope=__doc__, account_order=order)
    for path in [Path(__file__), Path(__file__).with_name('test_initial_cpm_adoption_erasure.py')]:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.save()
    q.execute('install_cpm_account_race_adapter', """
CREATE TABLE public.test_cpm_account_race_args AS
 SELECT a.owner_id,a.scan_id,a.submission_digest,r.result_evidence_id,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') result_digest,
 NULL::JSONB proof,
 (SELECT jsonb_agg(to_jsonb(s)||'{"retired":true}'::JSONB ORDER BY object_id) FROM internal.initial_preparation_source_registry s WHERE s.scan_id=a.scan_id) retired_registry,
 (SELECT jsonb_agg(to_jsonb(w)||'{"retired":true}'::JSONB ORDER BY object_id) FROM internal.initial_cpm_photo_write_attempts w WHERE w.scan_id=a.scan_id) retired_attempts,
 (SELECT to_jsonb(c)||'{"owner_id":null}'::JSONB FROM internal.initial_cpm_photo_capacity_reservations c WHERE c.scan_id=a.scan_id) retired_capacity,
 (SELECT to_jsonb(i)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id'] FROM internal.identification_invocations i) invocation_image,
 (SELECT (to_jsonb(e)-ARRAY['user_id','scan_id','source_id','conversation_id','message_id','metadata']) || jsonb_build_object('metadata',e.metadata-ARRAY['user_id','scan_id','conversation_id','message_id']) FROM public.ai_usage_events e) event_image
 FROM internal.initial_analysis_admissions a JOIN internal.initial_analysis_results r USING(scan_id,owner_id);
REVOKE ALL ON public.test_cpm_account_race_args FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_cpm_account_capture_proof() RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE s JSONB; now_ms BIGINT;
BEGIN
 s:=public.test_cpm_terminal();now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
 UPDATE public.test_cpm_account_race_args SET proof=s->'binding'||jsonb_build_object('verification_started_at_ms',now_ms,'verified_at_ms',now_ms);
END $$;
CREATE FUNCTION public.test_cpm_account_complete(expect_erased BOOLEAN) RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD; reply JSONB; denied BOOLEAN:=FALSE;
BEGIN
 SELECT * INTO STRICT a FROM public.test_cpm_account_race_args;
 BEGIN
  reply:=internal.complete_initial_analysis_cpm_v1(a.owner_id,a.scan_id,a.submission_digest,a.result_evidence_id,a.result_digest,a.proof->>'retention_policy_digest',a.proof);
 EXCEPTION WHEN SQLSTATE 'P0002' OR SQLSTATE '55000' THEN
  IF NOT ((SQLSTATE='P0002' AND SQLERRM='initial_analysis_owner_unavailable') OR (SQLSTATE='55000' AND SQLERRM='initial_analysis_deleted')) THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF denied IS DISTINCT FROM expect_erased OR (NOT denied AND reply->>'outcome' IS DISTINCT FROM 'fresh') THEN RAISE EXCEPTION USING ERRCODE='ZX851'; END IF;
END $$;
CREATE FUNCTION public.test_cpm_account_erase() RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD;
BEGIN
 SELECT * INTO STRICT a FROM public.test_cpm_account_race_args;
 PERFORM public.apply_user_tombstone(a.owner_id);
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_account_capture_proof(),public.test_cpm_account_complete(BOOLEAN),public.test_cpm_account_erase() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_account_capture_proof(),public.test_cpm_account_complete(BOOLEAN),public.test_cpm_account_erase() TO service_role;
""")
    q.execute('capture_proof_then_release_locks', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_account_capture_proof(); COMMIT;')
    sessions = []
    try:
        for name in ['completion', 'erasure', 'observer']:
            sessions.append(Session(q, 'cpm_account_' + name))
        completion, erasure, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('three distinct backends required')
        if order == 'completion':
            completion.run('adopt_before_account_erasure', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_account_complete(FALSE);')
            erasure.start('account_erasure_waits_for_adoption', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_account_erase();')
            wait_for_blocker(observer, erasure, completion)
            completion.run('commit_adoption_first', 'COMMIT;')
            erasure.finish()
            erasure.run('commit_following_account_erasure', 'COMMIT;')
        else:
            erasure.run('account_erasure_before_adoption', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_account_erase();')
            completion.start('stale_proof_waits_for_account_erasure', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_account_complete(TRUE);')
            wait_for_blocker(observer, completion, erasure)
            erasure.run('commit_account_erasure_first', 'COMMIT;')
            completion.finish()
            completion.run('commit_stale_proof_denial', 'COMMIT;')
        q.execute('account_race_exact_terminal_retention', """
DO $$ DECLARE a RECORD; BEGIN
 SELECT * INTO STRICT a FROM public.test_cpm_account_race_args;
 IF EXISTS(SELECT 1 FROM public.users WHERE id=a.owner_id)
  OR (CASE WHEN __COMPLETION_FIRST__ THEN
    NOT EXISTS(SELECT 1 FROM public.scans WHERE id=a.scan_id AND user_id IS NULL AND is_tombstoned)
   ELSE EXISTS(SELECT 1 FROM public.scans WHERE id=a.scan_id) END)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=a.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
  OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=a.owner_id)
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=a.owner_id)
  OR (SELECT jsonb_agg(to_jsonb(s) ORDER BY object_id) FROM internal.initial_preparation_source_registry s WHERE s.scan_id=a.scan_id) IS DISTINCT FROM a.retired_registry
  OR (SELECT jsonb_agg(to_jsonb(w) ORDER BY object_id) FROM internal.initial_cpm_photo_write_attempts w WHERE w.scan_id=a.scan_id) IS DISTINCT FROM a.retired_attempts
  OR (SELECT to_jsonb(c) FROM internal.initial_cpm_photo_capacity_reservations c WHERE c.scan_id=a.scan_id) IS DISTINCT FROM a.retired_capacity
  OR (SELECT count(*) FROM internal.identification_invocations)<>1
  OR NOT EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i)
    AND to_jsonb(i)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id']=a.invocation_image)
  OR (SELECT count(*) FROM public.ai_usage_events)<>1
  OR NOT EXISTS(SELECT 1 FROM public.ai_usage_events e WHERE e.user_id IS NULL AND e.scan_id IS NULL AND e.source_id IS NULL
    AND e.conversation_id IS NULL AND e.message_id IS NULL AND NOT e.metadata ?| ARRAY['user_id','scan_id','conversation_id','message_id']
    AND (to_jsonb(e)-ARRAY['user_id','scan_id','source_id','conversation_id','message_id','metadata']) || jsonb_build_object('metadata',e.metadata-ARRAY['user_id','scan_id','conversation_id','message_id'])=a.event_image)
 THEN RAISE EXCEPTION USING ERRCODE='ZX852'; END IF;
END $$;
""".replace('__COMPLETION_FIRST__', 'TRUE' if order == 'completion' else 'FALSE'))
        q.execute('saved_proof_denied_after_erasure', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_account_complete(TRUE); COMMIT;')
        q.record['passed'] = True
        q.record['exact_blocker_observed'] = True
    finally:
        for session in sessions:
            session.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--evidence-directory', required=True)
    p.add_argument('--replay-manifest', required=True)
    p.add_argument('--order', choices=['completion', 'account'], required=True)
    a = p.parse_args()
    start = time.monotonic()
    q = Qualification(a.container, a.evidence_directory, 'initial-cpm-account-race', a.replay_manifest)
    run(q, a.order)
    q.record['wall_seconds'] = time.monotonic() - start
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks']), 'session_commands': len(q.record.get('session_commands', []))}))


if __name__ == '__main__':
    main()
