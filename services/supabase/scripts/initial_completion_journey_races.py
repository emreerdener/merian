"""Both committed completion/C1 orders on separate owned local fixtures."""
from pathlib import Path

from initial_atomic_admission_sessions import Session
from initial_atomic_admission_test_support import ROOT
from initial_invocation_erasure_races import wait_for_blocker

ROLE = "SELECT set_config('request.jwt.claim.role','service_role',TRUE); SET LOCAL ROLE service_role;"
ARGS = """
CREATE TEMP TABLE completion_original_args AS
 SELECT r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') result_digest
 FROM internal.initial_analysis_results r JOIN internal.initial_analysis_admissions a USING(scan_id,owner_id);
"""
FIXTURE = """
CREATE FUNCTION public.test_completion_race(expect_cancelled BOOLEAN) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD; reply JSONB; denied BOOLEAN:=FALSE;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM pg_temp.completion_original_args;
 BEGIN
  reply:=internal.complete_initial_analysis_legacy_v1(a.owner_id,a.scan_id,a.submission_digest,a.result_evidence_id,a.result_digest);
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM IS DISTINCT FROM 'initial_analysis_cancelled' THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF denied IS DISTINCT FROM expect_cancelled OR (NOT denied AND reply->>'outcome' IS DISTINCT FROM 'fresh') THEN
  RAISE EXCEPTION USING ERRCODE='ZX827'; END IF;
END $$;
CREATE FUNCTION public.test_cancel_completion_race(expect_complete BOOLEAN) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD; reply JSONB; denied BOOLEAN:=FALSE;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM pg_temp.completion_original_args;
 BEGIN
  reply:=public.cancel_initial_analysis(a.owner_id,a.scan_id);
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM IS DISTINCT FROM 'initial_analysis_already_complete' THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF denied IS DISTINCT FROM expect_complete OR (NOT denied AND reply->>'dispatch' IS DISTINCT FROM 'dispatch_already_authorized') THEN
  RAISE EXCEPTION USING ERRCODE='ZX828'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_completion_race(BOOLEAN),public.test_cancel_completion_race(BOOLEAN) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completion_race(BOOLEAN),public.test_cancel_completion_race(BOOLEAN) TO service_role;
"""


def run(q, order, snapshot):
    if order not in ('completion', 'cancellation'):
        raise ValueError('explicit committed order required')
    q.record['source_manifest'][str(Path(__file__).relative_to(ROOT))] = q.digest(Path(__file__))
    q.record['scope'] = ('One committed ' + order + '-first completion/C1 schedule after original guarded legacy '
                         'admission/transfer/dispatch, synthetic result and usage. Three distinct bounded local sessions; '
                         'exact blocker observed. No provider, physical media, native or hosted qualification.')
    q.execute('install_completion_race_adapter', FIXTURE)
    sessions = []
    try:
        for name in ['completion', 'cancellation', 'observer']:
            sessions.append(Session(q, 'completion_race_' + name))
        completion, cancellation, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('three distinct backends required')
        for s in sessions:
            s.run('capture_original_completion_arguments', ARGS)
        if order == 'completion':
            completion.run('completion_prepared_before_c1', 'BEGIN;' + ROLE + 'SELECT public.test_completion_race(FALSE);')
            cancellation.start('c1_waits_for_completion', 'BEGIN;' + ROLE + 'SELECT public.test_cancel_completion_race(TRUE);')
            wait_for_blocker(observer, cancellation, completion)
            completion.run('commit_completion_first', 'COMMIT;')
            cancellation.finish()
            expected = q.execute('completed_before_c1_denial', snapshot)
            cancellation.run('commit_c1_denial', 'COMMIT;')
            if q.execute('c1_denial_preserves_completed_scope', snapshot) != expected:
                raise ValueError('late C1 changed completion')
        else:
            cancellation.run('c1_prepared_before_completion', 'BEGIN;' + ROLE + 'SELECT public.test_cancel_completion_race(FALSE);')
            completion.start('completion_waits_for_c1', 'BEGIN;' + ROLE + 'SELECT public.test_completion_race(TRUE);')
            wait_for_blocker(observer, completion, cancellation)
            cancellation.run('commit_c1_first', 'COMMIT;')
            completion.finish()
            expected = q.execute('cancelled_before_completion_denial', snapshot)
            completion.run('commit_completion_denial', 'COMMIT;')
            if q.execute('completion_denial_preserves_cancelled_scope', snapshot) != expected:
                raise ValueError('cancelled completion changed original scope')
        q.record['completion_c1_order'] = order
        q.record['completion_c1_exact_blocker'] = True
        terminal = q.execute('completion_c1_terminal_facts', """
SELECT (SELECT count(*) FROM public.scans),
 (SELECT count(*) FROM internal.initial_analysis_completions),
 (SELECT count(*) FROM internal.initial_analysis_cancellations),
 (SELECT count(*) FROM internal.initial_consuming_staging),
 (SELECT count(*) FROM internal.identification_invocations),
 (SELECT count(*) FROM public.ai_usage_events),
 (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='committed' AND refund_count=0);
""")
        if terminal != ('1|1|0|0|1|1|1' if order == 'completion' else '0|0|1|0|1|1|1'):
            raise ValueError('completion/C1 terminal facts mismatch')
    finally:
        for s in sessions:
            s.close()
