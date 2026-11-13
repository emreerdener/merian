"""Local guarded CPM completion with synthetic fresh byte attestations.

Exercises the actual completion/settlement/transfer owners. No physical storage,
qualified retention build installation, API route or native acceptance.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_cpm_retention import run as prepare
from test_initial_completion_preparation import SNAPSHOT
from test_initial_dispatch import ROLE


def initialize(q):
    prepare(q)
    q.record.update(passed=False, scope=__doc__)
    q.record['source_manifest'][str(Path(__file__).relative_to(ROOT))] = q.digest(Path(__file__))
    q.save()
    q.execute('install_disposable_completion_adapter', """
CREATE TABLE public.test_cpm_completion_reply(reply JSONB);
REVOKE ALL ON public.test_cpm_completion_reply FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_cpm_complete(replaying BOOLEAN DEFAULT FALSE) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a internal.initial_analysis_admissions; r internal.initial_analysis_results;
 snapshot JSONB; proof JSONB; now_ms BIGINT; reply JSONB; original JSONB; result_hash TEXT;
BEGIN
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions;
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 result_hash:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex');
 IF NOT replaying THEN
  snapshot:=public.test_cpm_terminal();
  now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  proof:=snapshot->'binding'||jsonb_build_object('verification_started_at_ms',now_ms,'verified_at_ms',now_ms);
 END IF;
 reply:=internal.complete_initial_analysis_cpm_v1(a.owner_id,a.scan_id,a.submission_digest,r.result_evidence_id,result_hash,
  snapshot#>>'{binding,retention_policy_digest}',proof);
 IF NOT replaying THEN
  IF reply->>'outcome' IS DISTINCT FROM 'fresh' OR reply#>>'{projection,media,kind}' IS DISTINCT FROM 'cpm_adoption_v1'
   OR jsonb_array_length(reply#>'{projection,media,items}')<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX831'; END IF;
  INSERT INTO public.test_cpm_completion_reply VALUES(reply-'outcome');
 ELSE
  SELECT saved.reply INTO STRICT original FROM public.test_cpm_completion_reply saved;
  IF reply->>'outcome' IS DISTINCT FROM 'replay' OR (reply-'outcome') IS DISTINCT FROM original THEN RAISE EXCEPTION USING ERRCODE='ZX832'; END IF;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_complete(BOOLEAN) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_complete(BOOLEAN) TO service_role;
""")

    pre_denial = q.execute('original_before_pre_adoption_deletion_probe', SNAPSHOT)
    q.execute('pre_adoption_scan_deletion_not_found_and_live_marker_empty', """
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
DO $$ DECLARE a internal.initial_analysis_admissions; reply JSONB; BEGIN
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions;
 SET LOCAL ROLE service_role;
 IF public.request_scan_deletion(a.scan_id,a.owner_id) IS DISTINCT FROM 'not_found' THEN RAISE EXCEPTION USING ERRCODE='ZX853'; END IF;
 reply:=public.claim_initial_preparation_source_erasure();
 IF reply IS DISTINCT FROM '{"version":1,"outcome":"empty"}'::JSONB THEN RAISE EXCEPTION USING ERRCODE='ZX854'; END IF;
END $$;
COMMIT;
""")
    if q.execute('pre_adoption_denials_preserve_original', SNAPSHOT) != pre_denial:
        raise ValueError('pre-adoption denial changed original state')


def run(q):
    initialize(q)
    peer_snapshot = """
SELECT encode(extensions.digest(convert_to(jsonb_build_object(
 'registry',(SELECT jsonb_agg(to_jsonb(r) ORDER BY object_id) FROM internal.initial_preparation_source_registry r
   WHERE scan_id NOT IN (SELECT scan_id FROM internal.initial_analysis_admissions)),
 'intents',(SELECT jsonb_agg(to_jsonb(i) ORDER BY scan_id) FROM internal.initial_analysis_preparation_intents i
   WHERE scan_id NOT IN (SELECT scan_id FROM internal.initial_analysis_admissions))
)::TEXT,'UTF8'),'sha256'),'hex');
"""
    peer = q.execute('unrelated_preparation_before_completion', peer_snapshot)
    before = q.execute('original_before_cpm_completion', SNAPSHOT)
    q.execute('cpm_completion_rollback', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(); ROLLBACK;')
    if q.execute('cpm_completion_rollback_restores_original', SNAPSHOT) != before:
        raise ValueError('completion rollback changed original scope')
    for relation in ['internal.initial_preparation_transfer_receipts', 'public.scans', 'internal.initial_analysis_completions']:
        q.execute('install_fault_' + relation, """
CREATE OR REPLACE FUNCTION public.test_cpm_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN RAISE EXCEPTION USING ERRCODE='ZX833'; END $$;
CREATE TRIGGER zzzzzzz_test_cpm_fault AFTER INSERT ON """ + relation + ' FOR EACH STATEMENT EXECUTE FUNCTION public.test_cpm_fault();')
        q.execute('atomic_fault_' + relation, 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(); COMMIT;', 'ZX833')
        q.execute('remove_fault_' + relation, 'DROP TRIGGER zzzzzzz_test_cpm_fault ON ' + relation + ';')
        if q.execute('fault_restores_original_' + relation, SNAPSHOT) != before:
            raise ValueError('fault left partial completion')
    q.execute('install_adoption_event_expiry_delay', """
CREATE FUNCTION public.test_cpm_expire_before_adoption() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE state='consumed')
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts) THEN
  RAISE EXCEPTION USING ERRCODE='ZX839'; END IF;
 PERFORM pg_sleep(31); RETURN NULL;
END $$;
CREATE TRIGGER a000000_test_cpm_expiry BEFORE INSERT ON internal.initial_preparation_transfer_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION public.test_cpm_expire_before_adoption();
""")
    q.execute('freshness_expires_after_settlement_at_adoption',
              "BEGIN; SET LOCAL statement_timeout='45s';" + ROLE + 'SELECT public.test_cpm_complete(); COMMIT;', '22023')
    if 'internal.assert_initial_cpm_retention_interval_v1' not in q.record['checks'][-1]['error_owners']:
        raise ValueError('expiry did not reach the original retention clock owner')
    q.execute('remove_adoption_event_expiry_delay',
              'DROP TRIGGER a000000_test_cpm_expiry ON internal.initial_preparation_transfer_receipts;')
    if q.execute('adoption_expiry_rolls_back_settlement', SNAPSHOT) != before:
        raise ValueError('adoption expiry left partial settlement')
    q.execute('cpm_completion_commit', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(); COMMIT;')
    q.execute('cpm_terminal_invariants', """
DO $$ DECLARE r internal.initial_preparation_admission_receipts;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts;
 IF (SELECT count(*) FROM internal.initial_preparation_transfer_receipts)<>1
  OR (SELECT count(*) FROM internal.initial_analysis_completions)<>1
  OR (SELECT count(*) FROM public.scans)<>1
  OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id AND NOT retired)<>3
  OR (SELECT count(*) FROM internal.initial_cpm_photo_write_attempts WHERE NOT retired AND write_closed)<>3
  OR (SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)<>1
  OR (SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations WHERE state='admitted')<>1
  OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='consumed')<>1
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
  OR EXISTS(SELECT 1 FROM public.scan_media_assets)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs)
  OR (SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis)<>1 THEN
  RAISE EXCEPTION USING ERRCODE='ZX834'; END IF;
 PERFORM internal.assert_initial_cpm_completed_v1(r.owner_id,r.scan_id);
END $$;
""")
    if q.execute('unrelated_preparation_after_completion', peer_snapshot) != peer:
        raise ValueError('completion changed unrelated preparation')
    committed = q.execute('committed_cpm_snapshot', SNAPSHOT)
    q.execute('exact_cpm_replay_without_fresh_proof', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(TRUE); COMMIT;')
    if q.execute('exact_replay_preserves_original', SNAPSHOT) != committed:
        raise ValueError('replay changed immutable completion or funding')
    for table in ['initial_cpm_photo_retention_policies', 'initial_cpm_photo_write_policies', 'initial_preparation_backend_eligibility']:
        q.execute('replay_after_revocation_' + table, "BEGIN; UPDATE internal." + table + " SET state='revoked';" + ROLE + 'SELECT public.test_cpm_complete(TRUE); ROLLBACK;')
    q.execute('ordinary_retirement_denied', "BEGIN; SELECT internal.retire_initial_preparation_source_objects((SELECT scan_id FROM internal.initial_analysis_completions)); COMMIT;", '55000')
    q.execute('ordinary_intent_expiry_denied', 'BEGIN; DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=(SELECT scan_id FROM internal.initial_analysis_completions); COMMIT;', '55000')
    if q.execute('cleanup_denial_preserves_adoption', SNAPSHOT) != committed:
        raise ValueError('ordinary cleanup changed adopted media')
    q.record['passed'] = True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--evidence-directory', required=True)
    p.add_argument('--replay-manifest', required=True)
    a = p.parse_args()
    started = time.monotonic()
    q = Qualification(a.container, a.evidence_directory, 'initial-cpm-completion', a.replay_manifest)
    run(q)
    q.record['wall_seconds'] = time.monotonic() - started
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
