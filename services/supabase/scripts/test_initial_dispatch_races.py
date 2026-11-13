"""Both committed orders of real original dispatch and public C1, local only."""
import argparse
from pathlib import Path
import time
import sys

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session
from initial_invocation_erasure_races import wait_for_blocker

ROLE = "SELECT set_config('request.jwt.claim.role','service_role',TRUE); SET LOCAL ROLE service_role;"

FIXTURE = """
CREATE FUNCTION public.test_dispatch_race(slot INTEGER, expect_denied BOOLEAN) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD; reply JSONB; denied BOOLEAN:=FALSE;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM pg_temp.test_dispatch_args WHERE ordinal=slot;
 BEGIN
  reply:=internal.commit_initial_analysis_dispatch(a.owner_id,a.scan_id,a.submission_digest,a.configuration_digest,
   a.funding_digest,a.assets_digest,a.lease_token,a.provenance);
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM IS DISTINCT FROM 'initial_analysis_cancelled' THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF denied IS DISTINCT FROM expect_denied OR (NOT denied AND reply->>'outcome' IS DISTINCT FROM 'fresh')
 THEN RAISE EXCEPTION USING ERRCODE='ZX810'; END IF;
END $$;
CREATE FUNCTION public.test_cancel_dispatch_race(slot INTEGER, expected TEXT) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a RECORD; reply JSONB;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM pg_temp.test_dispatch_args WHERE ordinal=slot;
 reply:=public.cancel_initial_analysis(a.owner_id,a.scan_id);
 IF reply->>'dispatch' IS DISTINCT FROM expected THEN RAISE EXCEPTION USING ERRCODE='ZX811'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_dispatch_race(INTEGER,BOOLEAN),public.test_cancel_dispatch_race(INTEGER,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_dispatch_race(INTEGER,BOOLEAN),public.test_cancel_dispatch_race(INTEGER,TEXT) TO service_role;
"""

ARGS = """
CREATE TEMP TABLE test_dispatch_args AS
 SELECT row_number() OVER(ORDER BY a.scan_id) ordinal,a.owner_id,a.scan_id,a.submission_digest,a.configuration_digest,
 a.funding_digest,a.assets_digest,q.id reservation_id,q.lease_token,
 public.test_dispatch_provenance()||jsonb_build_object('provider',p.provider,'binding',p.binding,
 'model',COALESCE(p.provider_model,p.model),'policy_version',p.policy_version,
 'variant',CASE WHEN p.input_profile='vision_compat_v1' THEN 'vision_compat' ELSE 'multimodal' END) provenance
 FROM internal.initial_analysis_admissions a JOIN internal.ai_quota_reservations q ON q.id=a.funding_binding_id
 JOIN internal.identification_provider_attempts p ON p.reservation_id=q.id AND p.attempt_count=1;
"""


def run(q):
    fixture = Path(__file__).with_name('fixtures') / 'initial_dispatch.sql'
    for path in [Path(__file__), fixture, Path(__file__).with_name('initial_invocation_erasure_races.py')]:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.record['scope'] = 'Two real committed dispatch/C1 orders on guarded legacy vision fixtures, exact blockers and actual service roles. No provider, hosted, account deletion or full-media race acceptance.'
    q.seed(count=2, held=False)
    q.execute('install_disposable_dispatch_race_fixture', fixture.read_text() + FIXTURE)
    sessions = []
    try:
        for name in ['dispatch', 'cancellation', 'observer']:
            sessions.append(Session(q, 'dispatch_' + name))
        dispatch, cancellation, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('three distinct backends required')
        # Each session keeps original arguments privately in a temporary table;
        # raw leases never enter source, retained evidence or command output.
        dispatch.run('capture_original_dispatch_arguments', ARGS)
        cancellation.run('capture_original_cancel_arguments', ARGS)
        observer.run('capture_original_refund_charge_images', ARGS + """
CREATE TEMP TABLE dispatch_refund_counters AS SELECT to_jsonb(c) image
 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_counters c
 USING(scope_type,scope_key,bucket,window_start)
 WHERE l.reservation_id=(SELECT reservation_id FROM test_dispatch_args WHERE ordinal=2);
""")
        dispatch.run('dispatch_first_prepared', 'BEGIN;' + ROLE + 'SELECT public.test_dispatch_race(1,FALSE);')
        cancellation.start('c1_waits_for_original_dispatch', 'BEGIN;' + ROLE + "SELECT public.test_cancel_dispatch_race(1,'dispatch_already_authorized');")
        wait_for_blocker(observer, cancellation, dispatch)
        q.record['dispatch_first_exact_blocker'] = True
        dispatch.run('commit_original_dispatch_first', 'COMMIT;')
        cancellation.finish()
        cancellation.run('commit_c1_after_real_dispatch', 'COMMIT;')
        observer.run('first_order_terminal_facts', """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 OR (SELECT count(*) FROM public.ai_usage_events WHERE outcome='unknown')<>1
 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='committed' AND refund_count=0)<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX812'; END IF;
END $$;
""")
        cancellation.run('c1_first_prepared', 'BEGIN;' + ROLE + "SELECT public.test_cancel_dispatch_race(2,'dispatch_prevented');")
        dispatch.start('original_dispatch_waits_for_c1', 'BEGIN;' + ROLE + 'SELECT public.test_dispatch_race(2,TRUE);')
        wait_for_blocker(observer, dispatch, cancellation)
        q.record['c1_first_exact_blocker'] = True
        cancellation.run('commit_c1_before_dispatch', 'COMMIT;')
        dispatch.finish()
        dispatch.run('commit_denied_dispatch_no_fresh_grant', 'COMMIT;')
        observer.run('both_orders_retained_terminal_facts', """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations)<>1
 OR (SELECT count(*) FROM internal.initial_analysis_cancellations)<>2
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='committed' AND refund_count=0)<>1
 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=(SELECT reservation_id FROM test_dispatch_args WHERE ordinal=2)
   AND state='refunded' AND refund_count=1)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters)
 OR EXISTS(SELECT 1 FROM dispatch_refund_counters saved LEFT JOIN internal.ai_quota_counters c
   ON c.scope_type=saved.image->>'scope_type' AND c.scope_key=saved.image->>'scope_key'
   AND c.bucket=saved.image->>'bucket' AND c.window_start=(saved.image->>'window_start')::TIMESTAMPTZ
   WHERE c.scope_type IS NULL OR to_jsonb(c)-'updated_at' IS DISTINCT FROM
    (saved.image-'updated_at')||jsonb_build_object('request_count',GREATEST(0,(saved.image->>'request_count')::INTEGER-1)))
 THEN RAISE EXCEPTION USING ERRCODE='ZX813'; END IF;
END $$;
""")
    finally:
        original_failure = sys.exc_info()[0] is not None
        failures = []
        # Release held transactions before waiting on their blocked peers.
        # A failed close must not prevent every other owned session closing.
        for session in sorted(sessions, key=lambda item: item.pending is not None):
            try:
                session.close()
            except Exception as error:
                failures.append({'session': session.name, 'category': type(error).__name__})
        if failures:
            q.record['cleanup_failures'] = failures
            q.save()
            if not original_failure:
                raise RuntimeError('owned race session cleanup failed')
    q.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    started = time.monotonic()
    q = Qualification(args.container, args.evidence_directory, 'dispatch-c1-races', args.replay_manifest)
    run(q)
    q.record['wall_seconds'] = time.monotonic() - started
    q.finish()
    print('PASS original dispatch/C1 committed orders')


if __name__ == '__main__':
    main()
