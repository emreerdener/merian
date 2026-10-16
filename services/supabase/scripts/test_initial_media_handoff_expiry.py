"""Effective legacy expiry paths over an actual private handoff lifecycle.

Synthetic original admission; rollback-only clock/legacy-branch seams; no hosted
scheduler, physical I/O, installed timing or concurrency qualification.
"""
import argparse
import json
from pathlib import Path

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification
from test_initial_media_handoff_owners import OPERATIONS


CLOCKS = """
DO $seams$ DECLARE definition TEXT; needle TEXT;BEGIN
 definition:=pg_get_functiondef('internal.recover_initial_admitted_media(uuid,uuid)'::regprocedure);
 needle:='floor(extract(epoch FROM clock_timestamp())*1000)';
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX750'; END IF;
 EXECUTE replace(definition,needle,'((receipt.media_binding::JSONB#>>''{phase_window,original_expires_at_ms}'')::NUMERIC+1)');
 definition:=pg_get_functiondef('internal.create_initial_media_preparation(uuid,uuid,text)'::regprocedure);
 needle:='IF clock_timestamp()>=saved.expires_at THEN';
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX750'; END IF;
 EXECUTE replace(definition,needle,'IF TRUE THEN');
 definition:=pg_get_functiondef('internal.initial_preparation_execution_action(text,uuid,uuid,text,text)'::regprocedure);
 needle:='IF now_ms>=expiry_ms THEN';
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX750'; END IF;
 EXECUTE replace(definition,needle,'IF TRUE THEN');
END $seams$;
"""
QUOTA_CLOCK = """
DO $seam$ DECLARE definition TEXT; needle TEXT:='quota_now TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();';BEGIN
 definition:=pg_get_functiondef('internal.refund_expired_ai_quota_reservations(integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX750'; END IF;
 EXECUTE replace(definition,needle,'quota_now TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP()+interval ''2 days'';');
END $seam$;
"""


def cases(q):
    signatures = ['internal.recover_initial_admitted_media(uuid,uuid)',
                  'internal.create_initial_media_preparation(uuid,uuid,text)',
                  'internal.initial_preparation_execution_action(text,uuid,uuid,text,text)',
                  'public.get_initial_preparation_status(uuid,uuid)',
                  'public.finalize_initial_preparation(uuid,uuid,text)',
                  'public.get_initial_preparation_execution_status(uuid,uuid,text)',
                  'internal.lock_initial_media_scope(uuid,uuid,text)',
                  'internal.reject_initial_preparation_provider_writer(uuid[])',
                  'public.retire_initial_analysis_media(uuid,uuid,text)',
                  'internal.refund_expired_ai_quota_reservations(integer)',
                  'internal.prune_ai_quota_state()']
    query = "SELECT jsonb_object_agg(signature,encode(extensions.digest(pg_get_functiondef(signature::regprocedure),'sha256'),'hex')) FROM unnest(ARRAY[" + ','.join("'" + s + "'" for s in signatures) + ']) x(signature);'
    q.record['effective_function_hashes'] = json.loads(q.execute('capture_effective_function_hashes', query))
    q.save()
    fixture = AdmissionFixture(q)
    try:
        admitted = fixture.admit_one()
        prefix = "DO $$ DECLARE r internal.initial_preparation_admission_receipts; before_state JSONB; result JSONB; input_digest TEXT; BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + admitted.scan_id + "';"
        capture = 'before_state:=internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);'
        unchanged = "IF before_state IS DISTINCT FROM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id) THEN RAISE EXCEPTION USING ERRCODE='ZX751'; END IF;"
        for stage in range(7):
            if stage:
                name, args, _, _ = OPERATIONS[stage - 1]
                q.execute('commit_' + name, 'BEGIN;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + prefix +
                          'PERFORM * FROM internal.' + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            expected = "result->>'outcome' IS DISTINCT FROM 'transferred'" if stage == 6 else "result->>'outcome' IS DISTINCT FROM 'admitted' OR result->>'phase' IS DISTINCT FROM 'expired'"
            check = "IF result->>'authority' IS DISTINCT FROM 'none' OR " + expected + " THEN RAISE EXCEPTION USING ERRCODE='ZX752'; END IF;"
            routes = [
                ('create', 'result:=internal.create_initial_media_preparation(r.owner_id,r.scan_id,r.candidate);'),
                ('status', 'SET LOCAL ROLE service_role;result:=public.get_initial_preparation_status(r.owner_id,r.scan_id);RESET ROLE;'),
                ('finalize', "SET LOCAL ROLE service_role;result:=public.finalize_initial_preparation(r.owner_id,r.scan_id,repeat('a',64));RESET ROLE;"),
            ]
            for label, call in routes:
                q.execute('stage_' + str(stage) + '_expired_' + label, 'BEGIN;' + CLOCKS + prefix + capture + call + check + unchanged + 'END $$;ROLLBACK;')
            execution = "result:=public.get_initial_preparation_execution_status(r.owner_id,r.scan_id,r.media_binding::JSONB->>'assignment_digest');"
            q.execute('stage_' + str(stage) + '_expired_execution_held', 'BEGIN;' + CLOCKS + prefix + capture + "SET LOCAL ROLE service_role;" + execution + "RESET ROLE;IF result IS DISTINCT FROM '{\"version\":2,\"outcome\":\"held\",\"reason\":\"incoherent\",\"authority\":\"none\"}'::JSONB THEN RAISE EXCEPTION USING ERRCODE='ZX753'; END IF;" + unchanged + 'END $$;ROLLBACK;')
            for label, call in [
                ('changed_candidate', "result:=internal.create_initial_media_preparation(r.owner_id,r.scan_id,r.candidate||' ');"),
                ('changed_assignment', "SET LOCAL ROLE service_role;result:=public.get_initial_preparation_execution_status(r.owner_id,r.scan_id,repeat('f',64));RESET ROLE;"),
            ]:
                q.execute('stage_' + str(stage) + '_' + label, 'BEGIN;' + CLOCKS + prefix + capture + "BEGIN " + call + "RAISE EXCEPTION USING ERRCODE='ZX756';EXCEPTION WHEN SQLSTATE '22023' THEN NULL;END;RESET ROLE;" + unchanged + 'END $$;ROLLBACK;')
            if stage in (0, 6):
                damages = [('absent_receipt', 'DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id;')]
                if stage == 6:
                    damages.append(('damaged_progress', "UPDATE internal.initial_media_copy_progress SET copy_adapter_digest=repeat('f',64) WHERE scan_id=r.scan_id;"))
                for damage_label, damage in damages:
                    for label, call in routes + [('execution', 'SET LOCAL ROLE service_role;' + execution + 'RESET ROLE;')]:
                        q.execute('stage_' + str(stage) + '_' + damage_label + '_' + label, 'BEGIN;' + CLOCKS + prefix + "SET LOCAL session_replication_role='replica';" + damage + "SET LOCAL session_replication_role='origin';" + capture + "BEGIN " + call + "RAISE EXCEPTION USING ERRCODE='ZX757';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;RESET ROLE;" + unchanged + 'END $$;ROLLBACK;')
            # The permanent preparation provider barrier denies before the v1 gate.
            q.execute('stage_' + str(stage) + '_legacy_m1_denied', 'BEGIN;' + prefix + capture + "SELECT submission_digest INTO STRICT input_digest FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;BEGIN SET LOCAL ROLE service_role;PERFORM public.retire_initial_analysis_media(r.owner_id,r.scan_id,input_digest);RAISE EXCEPTION USING ERRCODE='ZX754';EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_preparation_provider_blocked' THEN RAISE;END IF;END;RESET ROLE;" + unchanged + 'END $$;ROLLBACK;')
            q.execute('stage_' + str(stage) + '_quota_expiry_preserved', 'BEGIN;' + QUOTA_CLOCK + prefix + capture + "PERFORM internal.refund_expired_ai_quota_reservations(1000);PERFORM internal.prune_ai_quota_state();" + unchanged + 'END $$;ROLLBACK;')
        # Transfer remains protected by the permanent initial fence even with
        # missing private proof. This test never treats absence as refund proof.
        q.execute('quota_expiry_missing_private_proof', 'BEGIN;' + QUOTA_CLOCK + prefix + capture + "SET LOCAL session_replication_role='replica';DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id;SET LOCAL session_replication_role='origin';PERFORM internal.refund_expired_ai_quota_reservations(1000);PERFORM internal.prune_ai_quota_state();IF (before_state-'internal.initial_preparation_admission_receipts') IS DISTINCT FROM (internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id)-'internal.initial_preparation_admission_receipts') THEN RAISE EXCEPTION USING ERRCODE='ZX755';END IF;END $$;ROLLBACK;")
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-expiry', args.replay_manifest)
    source = Path(__file__).resolve()
    for p in [source, source.with_name('test_initial_media_handoff_owners.py')]:
        q.record['source_manifest'][str(p.relative_to(source.parents[3]))] = q.digest(p)
    q.record['scope'] = 'Effective callable expiry/recovery and generic quota cleanup over synthetic admission plus actual guarded handoff lifecycle. Rollback clock/legacy-branch seams; no installed scheduler, timing, I/O or concurrency qualification.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
