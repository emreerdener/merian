"""Rollback-only terminal/aged quota fixtures proving permanent prune fences.

These deliberately inconsistent terminal images are test seams, not a funding
transition, positive refund proof, or installed scheduler qualification.
"""
import argparse
import json
from pathlib import Path

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification


def cases(q):
    q.record['effective_function_hashes'] = json.loads(q.execute(
        'capture_prune_function_hash',
        "SELECT jsonb_build_object('internal.prune_ai_quota_state()',encode(extensions.digest(pg_get_functiondef('internal.prune_ai_quota_state()'::regprocedure),'sha256'),'hex'));"))
    q.save()
    fixture = AdmissionFixture(q)
    try:
        admitted = fixture.admit_one()
        for terminal in ('committed', 'failed', 'refunded'):
            for identity in ('original_analysis_id', 'request_id'):
                other = 'request_id' if identity == 'original_analysis_id' else 'original_analysis_id'
                for absent in (False, True):
                    # Privileged corruption is rolled back, and origin guards
                    # are restored before invoking the real pruning owner.
                    sql = """
BEGIN;
DO $$
DECLARE r internal.initial_preparation_admission_receipts;
 saved internal.ai_quota_reservations; control internal.ai_quota_reservations;
 before_state JSONB;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='SCAN';
 SELECT * INTO STRICT saved FROM internal.ai_quota_reservations WHERE id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID;
 SET LOCAL session_replication_role='replica';
 UPDATE internal.ai_quota_reservations SET state='TERMINAL',updated_at=now()-interval '31 days',
  lease_expires_at=now()-interval '31 days',complimentary_client_scan_id=NULL,OTHER=extensions.gen_random_uuid() WHERE id=saved.id;
 SELECT * INTO STRICT control FROM internal.ai_quota_reservations WHERE id=saved.id;
 control.id:=extensions.gen_random_uuid();control.request_id:=extensions.gen_random_uuid();
 control.original_analysis_id:=extensions.gen_random_uuid();control.lease_token:=extensions.gen_random_uuid();
 INSERT INTO internal.ai_quota_reservations SELECT control.*;
 ABSENT
 SET LOCAL session_replication_role='origin';
 IF NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations a JOIN internal.initial_analysis_operation_fences f
  ON f.scan_id=a.IDENTITY WHERE a.id=saved.id AND a.state='TERMINAL' AND a.updated_at<now()-interval '30 days')
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id IN(control.original_analysis_id,control.request_id))
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id IN(saved.original_analysis_id,control.original_analysis_id))
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE user_id=r.owner_id
   AND status='failed_terminal' AND terminal_reason_code='media_reconciliation_abandoned')
  THEN RAISE EXCEPTION USING ERRCODE='ZX760';END IF;
 before_state:=internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);
 PERFORM internal.prune_ai_quota_state();
 IF before_state IS DISTINCT FROM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id)
  THEN RAISE EXCEPTION USING ERRCODE='ZX761';END IF;
 IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=control.id)
  THEN RAISE EXCEPTION USING ERRCODE='ZX762';END IF;
END $$;
ROLLBACK;
"""
                    sql = sql.replace('SCAN', admitted.scan_id).replace('TERMINAL', terminal).replace('OTHER', other).replace('IDENTITY', identity).replace('ABSENT', 'DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id;' if absent else '')
                    q.execute('prune_' + terminal + '_' + identity + ('_missing_proof' if absent else '_retained_proof'), sql)
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-pruning', args.replay_manifest)
    source = Path(__file__).resolve()
    q.record['source_manifest'][str(source.relative_to(source.parents[3]))] = q.digest(source)
    q.record['scope'] = 'Real pruning owner over rollback-only terminal/aged reservation images, each logical fence arm, retained/absent private proof, and matching unfenced control. Not a valid funding transition, refund authorization, installed scheduler, or runtime lifecycle acceptance.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
