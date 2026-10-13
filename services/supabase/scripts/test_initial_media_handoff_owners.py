"""Local fixed-owner lifecycle and replay tests; no physical I/O or activation.

Original admission is synthetic; each selected handoff operation uses its fixed
private owner with origin-mode guards and commits in a separate transaction.
"""
import argparse
from pathlib import Path

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification


OPERATIONS = [
    ('begin_initial_media_copy_v2', '', 'progress', 'initial_media_copy_progress'),
    ('record_initial_media_copy_object_v2', ",(r.mapping::JSONB#>>'{objects,0,object_id}')::UUID", 'progress', 'initial_media_copy_progress'),
    ('complete_initial_media_copy_v2', '', 'progress', 'initial_media_copy_progress'),
    ('claim_initial_media_verification_v2', '', 'claim', 'initial_media_verification_claims_v2'),
    ('settle_initial_media_verification_v2', ",(SELECT (claim::JSONB->>'claim_token')::UUID FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id)", 'verification', 'initial_media_verification_receipts_v2'),
    ('transfer_initial_preparation_v2', ',(SELECT receipt_digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=r.scan_id)', 'transfer', 'initial_preparation_transfer_receipts'),
]


def cases(q):
    for role in ['anon', 'authenticated', 'service_role']:
        signatures = [name + '(uuid,uuid,text' + (',text' if column == 'transfer' else ',uuid' if args else '') + ')'
                      for name, args, column, _ in OPERATIONS]
        signatures += ['prepare_initial_media_handoff_operation(uuid,uuid,text,text,uuid,uuid,text)',
                       'initial_media_handoff_operation_response(uuid,uuid,boolean)']
        for signature in signatures:
            q.execute(role + '_no_' + signature.split('(')[0], "DO $$ BEGIN IF has_function_privilege('" + role +
                      "','internal." + signature + "','EXECUTE') THEN RAISE EXCEPTION USING ERRCODE='ZX740'; END IF;END $$;")
    fixture = AdmissionFixture(q)
    try:
        admitted = fixture.admit_one()
        prefix = "DO $$ DECLARE r internal.initial_preparation_admission_receipts; answer RECORD; saved JSONB; BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + admitted.scan_id + "';"
        stable = """
IF answer.response->>'authority' IS DISTINCT FROM 'none'
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX741'; END IF;
"""
        # Rollback-only clock seams exercise the real fixed owner branch without
        # changing any saved original or adding a production clock override.
        late_response = """
DO $clock$ DECLARE definition TEXT; needle TEXT:='floor(extract(epoch FROM clock_timestamp())*1000)';BEGIN
 definition:=pg_get_functiondef('internal.initial_media_handoff_operation_response(uuid,uuid,boolean)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX746'; END IF;
 EXECUTE replace(definition,needle,'((r.media_binding::JSONB#>>''{phase_window,original_expires_at_ms}'')::NUMERIC+1)');
END $clock$;
"""
        late_planner = """
DO $clock$ DECLARE definition TEXT; needle TEXT:='now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;';BEGIN
 definition:=pg_get_functiondef('internal.plan_initial_media_handoff_mutation(uuid,uuid,text,text,uuid,uuid,text)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX746'; END IF;
 EXECUTE replace(definition,needle,'now_ms:=(r.media_binding::JSONB#>>''{phase_window,original_expires_at_ms}'')::BIGINT+1;');
END $clock$;
"""
        planner_tripwire = """
DO $tripwire$ DECLARE definition TEXT; needle TEXT:='    -- Fresh mutations only.';BEGIN
 definition:=pg_get_functiondef('internal.plan_initial_media_handoff_mutation(uuid,uuid,text,text,uuid,uuid,text)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX746'; END IF;
 EXECUTE replace(definition,needle,'    RAISE EXCEPTION USING ERRCODE=''ZX747'';'||chr(10)||needle);
END $tripwire$;
"""
        for index, (name, args, column, table) in enumerate(OPERATIONS):
            call = 'SELECT * INTO STRICT answer FROM internal.' + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');'
            assertion = stable + 'IF to_jsonb(answer."' + column + '") IS DISTINCT FROM (SELECT to_jsonb(t) FROM internal.' + table + " t WHERE t.scan_id=r.scan_id) OR answer.response->>'outcome' IS DISTINCT FROM '" + ('transferred' if index == 5 else 'admitted') + "' THEN RAISE EXCEPTION USING ERRCODE='ZX742';END IF;"
            # A committed mutation seals its transaction. Restore the fixture's
            # gate in a distinct transaction, never by bypassing that seal.
            q.execute('commit_' + name, "BEGIN;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;" + prefix + call + assertion + "END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            replay = 'saved:=(SELECT to_jsonb(t) FROM internal.' + table + ' t WHERE t.scan_id=r.scan_id);' + call + assertion
            replay += 'IF saved IS DISTINCT FROM to_jsonb(answer."' + column + '") OR internal.initial_media_handoff_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX743\';END IF;'
            q.execute('disabled_gate_exact_replay_' + name, 'BEGIN;' + prefix + replay + 'END $$;ROLLBACK;')
            q.execute('changed_admission_' + name, 'BEGIN;' + prefix + call.replace('r.receipt_digest', "repeat('f',64)") + 'END $$;ROLLBACK;', '55000')
            q.execute('late_status_original_replay_' + name, 'BEGIN;' + late_response + planner_tripwire + prefix + replay +
                      ("IF answer.response->>'phase' IS DISTINCT FROM 'expired' THEN RAISE EXCEPTION USING ERRCODE='ZX748'; END IF;" if index < 5 else '') + 'END $$;ROLLBACK;')
            q.execute('foreign_owner_' + name, 'BEGIN;' + prefix + call.replace('r.owner_id', "'" + fixture.foreign + "'::UUID") + 'END $$;ROLLBACK;', '55000')
            if index in (0, 5):
                # Privileged rollback-only assertion fixture. Capture AFTER the
                # deliberate corruption so exact snapshot equality cannot mask
                # a missing chain proof in either poststate branch.
                for damaged in (False, True):
                    phase = 'transferred' if index == 5 else 'before_transfer'
                    body = 'DECLARE witness internal.initial_media_handoff_staging; BEGIN '
                    if damaged:
                        body += "SET LOCAL session_replication_role='replica';UPDATE internal.initial_media_copy_progress SET copy_adapter_digest=repeat('f',64) WHERE scan_id=r.scan_id;SET LOCAL session_replication_role='origin';"
                    body += "witness.transaction_id:=pg_catalog.pg_current_xact_id();witness.owner_id:=r.owner_id;witness.scan_id:=r.scan_id;"
                    body += "witness.snapshot:=internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);witness.events:='[]'::JSONB;"
                    body += "witness.authorized_at_ms:=(r.manifest::JSONB->>'authorized_at_ms')::BIGINT;"
                    body += "witness.cutoff_ms:=(r.media_binding::JSONB#>>'{phase_window,cutoffs," + ('transfer' if index == 5 else 'copy') + "}')::BIGINT;"
                    body += 'PERFORM internal.assert_initial_media_handoff_poststate(witness);END;'
                    q.execute('poststate_' + phase + ('_rejects_corrupt_chain' if damaged else '_valid_chain'),
                              'BEGIN;' + prefix + body + 'END $$;ROLLBACK;', '55000' if damaged else None)
                    if damaged:
                        check = q.record['checks'][-1]
                        check['passed'] = check['passed'] and 'internal.assert_initial_media_handoff_chain' in check['error_owners']
                        q.save()
                        if not check['passed']:
                            raise RuntimeError('poststate corruption must fail in the original chain assertion')
            if index < 5:
                next_name, next_args, _, _ = OPERATIONS[index + 1]
                q.execute('late_fresh_' + next_name, 'BEGIN;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + late_planner + prefix +
                          'PERFORM * FROM internal.' + next_name + '(r.owner_id,r.scan_id,r.receipt_digest' + next_args + ');END $$;ROLLBACK;', '55000')
            if index == 0:
                for label, damage in [
                    ('damaged_progress', "UPDATE internal.initial_media_copy_progress SET copy_adapter_digest=repeat('f',64) WHERE scan_id=r.scan_id;"),
                    ('retired_destination', 'UPDATE internal.initial_analysis_media_registry SET retired=TRUE WHERE scan_id=r.scan_id;'),
                    ('absent_original', 'DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id;'),
                ]:
                    q.execute('replay_rejects_' + label, 'BEGIN;' + prefix + "SET LOCAL session_replication_role='replica';" + damage +
                              "SET LOCAL session_replication_role='origin';" + call + 'END $$;ROLLBACK;', '55000')
                q.execute('incomplete_copy_cannot_claim', 'BEGIN;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + prefix +
                          'PERFORM * FROM internal.claim_initial_media_verification_v2(r.owner_id,r.scan_id,r.receipt_digest);END $$;ROLLBACK;', '55000')
        for name, args, column, _ in OPERATIONS[:-1]:
            call = 'SELECT * INTO STRICT answer FROM internal.' + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');'
            q.execute('held_' + name, 'BEGIN;' + prefix + call + stable + 'IF answer.response->>\'outcome\' IS DISTINCT FROM \'held\' OR answer.response->>\'reason\' IS DISTINCT FROM \'already_transferred\' OR to_jsonb(answer."' + column + '") IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE=\'ZX744\';END IF;END $$;ROLLBACK;')
            q.execute('held_still_checks_admission_' + name, 'BEGIN;' + prefix + call.replace('r.receipt_digest', "repeat('f',64)") + 'END $$;ROLLBACK;', '55000')
        for label, call in [
            ('object', 'record_initial_media_copy_object_v2(r.owner_id,r.scan_id,r.receipt_digest,extensions.gen_random_uuid())'),
            ('token', 'settle_initial_media_verification_v2(r.owner_id,r.scan_id,r.receipt_digest,extensions.gen_random_uuid())'),
            ('verification', "transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,repeat('f',64))"),
        ]:
            q.execute('post_transfer_changed_' + label, 'BEGIN;' + prefix + 'PERFORM * FROM internal.' + call + ';END $$;ROLLBACK;', '55000')
        for isolation in ['REPEATABLE READ', 'SERIALIZABLE']:
            q.execute('reject_' + isolation, 'BEGIN ISOLATION LEVEL ' + isolation + ';' + prefix +
                      'PERFORM * FROM internal.begin_initial_media_copy_v2(r.owner_id,r.scan_id,r.receipt_digest);END $$;ROLLBACK;', '25000')
        original_digest = q.execute('retain_synthetic_original_digest', "SELECT receipt_digest FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + admitted.scan_id + "';")
        q.execute('actual_transferred_c1_cleanup', 'BEGIN;DO $$ DECLARE answer JSONB;BEGIN SET LOCAL ROLE service_role;answer:=public.cancel_initial_analysis(\'' + admitted.owner_id + "','" + admitted.scan_id + "');RESET ROLE;IF answer IS DISTINCT FROM " +
                  "'{\"version\":1,\"outcome\":\"cancelled\",\"dispatch\":\"dispatch_prevented\"}'::JSONB OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + admitted.scan_id + "') THEN RAISE EXCEPTION USING ERRCODE='ZX745';END IF;END $$;COMMIT;")
        q.execute('erased_original_cannot_restart', "BEGIN;SELECT * FROM internal.begin_initial_media_copy_v2('" + admitted.owner_id + "','" + admitted.scan_id + "','" + original_digest + "');ROLLBACK;", '55000')
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-owners', args.replay_manifest)
    source = Path(__file__).resolve()
    q.record['source_manifest'][str(source.relative_to(source.parents[3]))] = q.digest(source)
    q.record['scope'] = 'Private fixed owners: committed six-operation lifecycle, exact replay with disabled gate, held/changed arguments and actual transferred C1. Rollback-only output/planner clock seams verify expired status recovery and late fresh denial; no installed deadline, physical I/O or concurrency qualification.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
