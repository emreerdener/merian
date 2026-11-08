"""Local synthetic tests of private handoff storage and transaction guards.

Injected predecessors exercise validators; selected transaction cases execute
origin-mode guards. Fixed replay owners, physical I/O and concurrency remain open.
Requires a fresh owned disposable database and its exact migration-byte manifest.
"""
import argparse
from pathlib import Path

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification
from initial_media_handoff_transaction_cases import transaction_cases


def cases(q):
    q.execute('statement_trigger_private_owner_boundary', """DO $$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='internal.guard_initial_media_handoff_statement()'::regprocedure
 AND prosecdef AND proowner='postgres'::regrole AND prorettype='trigger'::regtype
 AND proconfig=ARRAY['search_path=""']::text[])
 OR (SELECT prosecdef FROM pg_proc WHERE oid='internal.guard_initial_media_handoff_domain_row()'::regprocedure)
 THEN RAISE EXCEPTION USING ERRCODE='ZX703'; END IF;
END $$;""")
    q.execute('service_user_preference_parent_acl_preserved', """DO $$ BEGIN
IF has_column_privilege('service_role','public.users','marketing_opt_in','UPDATE')
 OR NOT has_column_privilege('authenticated','public.users','marketing_opt_in','UPDATE')
 THEN RAISE EXCEPTION USING ERRCODE='ZX703'; END IF;
END $$;""")
    for role in ['authenticated', 'service_role']:
        for table, column in [('scans', 'custom_tags'), ('users', 'marketing_opt_in')]:
            parent_denied = role == 'service_role' and table == 'users'
            q.execute(role + ('_parent_acl_denied_' if parent_denied else '_ordinary_unsealed_') + table,
                'BEGIN;SET LOCAL ROLE ' + role + ';UPDATE public.' + table + ' SET ' + column + '=' + column + ' WHERE FALSE;ROLLBACK;',
                '42501' if parent_denied else None)
    tables = ['initial_media_copy_progress', 'initial_media_verification_claims_v2',
              'initial_media_verification_receipts_v2', 'initial_preparation_transfer_receipts']
    for table in tables:
        q.execute('private_catalog_' + table, "DO $$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='internal." + table +
            "'::regclass) OR (SELECT count(*) FROM pg_constraint WHERE conrelid='internal." + table +
            "'::regclass AND contype='f' AND confrelid='internal.initial_preparation_admission_receipts'::regclass AND confdeltype='c')<>1 "
            "OR (SELECT count(*) FROM pg_constraint WHERE conrelid='internal." + table +
            "'::regclass AND contype='f')<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX701'; END IF; END $$;")
        for role in ['anon', 'authenticated', 'service_role']:
            q.execute(role + '_no_table_' + table,
                "DO $$ BEGIN IF has_table_privilege('" + role + "','internal." + table +
                "','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN RAISE EXCEPTION USING ERRCODE='ZX702';END IF;END $$;")
    for role in ['anon', 'authenticated', 'service_role']:
        for table in ['initial_media_handoff_staging', 'initial_media_handoff_writes']:
            q.execute(role + '_no_table_' + table,
                "DO $$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='internal." + table +
                "'::regclass) OR has_table_privilege('" + role + "','internal." + table +
                "','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN RAISE EXCEPTION USING ERRCODE='ZX702';END IF;END $$;")
        for signature in ['initial_media_copy_progress_shape(text,bigint,bigint,bigint)',
                          'initial_media_handoff_sealed()',
                          'initial_media_handoff_row_image(text,jsonb)',
                          'assert_initial_media_handoff_poststate(internal.initial_media_handoff_staging)',
                          'assert_initial_media_handoff_ledger(internal.initial_media_handoff_staging,boolean)',
                          'guard_initial_media_handoff_stage()',
                          'require_initial_media_handoff_completion()',
                          'guard_initial_media_handoff_write()',
                          'guard_initial_media_handoff_statement()',
                          'guard_initial_media_handoff_domain_row()',
                          'initial_media_handoff_transfer_event(text,jsonb,jsonb)',
                          'execute_initial_media_handoff_stage(uuid)',
                          'initial_media_handoff_document_shape(text,uuid,uuid,text,text)',
                          'lock_initial_media_handoff_members(uuid)',
                          'lock_initial_media_handoff_erasure_rows(uuid)',
                          'initial_media_handoff_erasure_identities(uuid)',
                          'lock_initial_media_handoff_scope(uuid,uuid,boolean)',
                          'initial_media_handoff_snapshot_catalog()',
                          'capture_initial_media_handoff_snapshot(uuid,uuid)',
                          'assert_initial_media_handoff_cascade_catalog()',
                          'plan_initial_media_handoff_mutation(uuid,uuid,text,text,uuid,uuid,text)',
                          'assert_initial_media_handoff_chain(uuid,uuid)',
                          'assert_initial_transferred_preparation(uuid,uuid)',
                          'assert_initial_cancellation_retirement_images(uuid,text,jsonb,boolean,jsonb)',
                          'initial_media_handoff_recovery_response(internal.initial_preparation_admission_receipts,numeric)']:
            q.execute(role + '_no_function_' + signature.split('(')[0],
                "DO $$ BEGIN IF has_function_privilege('" + role + "','internal." + signature +
                "','EXECUTE') THEN RAISE EXCEPTION USING ERRCODE='ZX703';END IF;END $$;")
    fixture = AdmissionFixture(q)
    try:
        admitted = fixture.admit_one()
        owner, scan = admitted.owner_id, admitted.scan_id
        plan_cases(q, owner, scan)
        transaction_cases(q, owner, scan, fixture.admit_one)
        for isolation in ['REPEATABLE READ', 'SERIALIZABLE']:
            q.execute('deny_scope_' + isolation.lower().replace(' ', '_'),
                'BEGIN ISOLATION LEVEL ' + isolation + ";SELECT internal.lock_initial_media_handoff_scope('" + owner + "','" + scan + "',FALSE);ROLLBACK;", '25000')
        q.execute('original_scope_and_absent_chain', "BEGIN;SELECT internal.lock_initial_media_handoff_scope('" + owner + "','" + scan +
            "',FALSE);SELECT internal.assert_initial_media_handoff_chain('" + owner + "','" + scan + "');ROLLBACK;")
        # This fixed privileged test composer injects synthetic state under
        # replica mode only for fixture DML. Every validation runs in origin
        # mode. All injected rows disappear with transaction rollback.
        prefix = """BEGIN;DO $$
DECLARE r internal.initial_preparation_admission_receipts; objects JSONB; start_ms BIGINT;
    claim TEXT; verified TEXT; transferred TEXT; result JSONB; private_member RECORD;
BEGIN
SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='""" + scan + """';
SELECT jsonb_agg(jsonb_build_object('object_id',o->'object_id','backend_generation',r.mapping::JSONB->'destination_backend_generation')||(o->'bytes') ORDER BY ordinal)
INTO objects FROM jsonb_array_elements(r.mapping::JSONB->'objects') WITH ORDINALITY x(o,ordinal);
start_ms:=(r.manifest::JSONB->>'authorized_at_ms')::BIGINT;
SET LOCAL session_replication_role='replica';
INSERT INTO internal.initial_media_copy_progress VALUES(r.scan_id,r.owner_id,r.receipt_digest,
    r.configuration::JSONB#>>'{assignment,handoff,profile,copy_adapter_digest}',start_ms,'[]',NULL,NULL);
SET LOCAL session_replication_role='origin';
"""
        suffix = 'END $$;ROLLBACK;'
        chain = 'PERFORM internal.assert_initial_media_handoff_chain(r.owner_id,r.scan_id);'
        def inject(sql):
            return "SET LOCAL session_replication_role='replica';" + sql + "SET LOCAL session_replication_role='origin';"
        full = inject("UPDATE internal.initial_media_copy_progress SET completed_objects=internal.initial_canonical(objects),last_object_at_ms=start_ms WHERE scan_id=r.scan_id;")
        complete = full + inject("UPDATE internal.initial_media_copy_progress SET completed_at_ms=start_ms WHERE scan_id=r.scan_id;")
        claim_sql = "claim:=internal.initial_canonical(jsonb_build_object('version',2,'binding',r.media_binding::JSONB,'admission_receipt_digest',r.receipt_digest,'verification_adapter_digest',r.configuration::JSONB#>'{assignment,handoff,profile,verification_adapter_digest}','claim_token',extensions.gen_random_uuid(),'issued_at_ms',start_ms));"
        claim_sql += inject("INSERT INTO internal.initial_media_verification_claims_v2 VALUES(r.scan_id,r.owner_id,claim,internal.initial_media_handoff_proof_digest('claim',claim));")
        verify_sql = "verified:=internal.initial_canonical(jsonb_build_object('version',2,'claim',claim::JSONB,'claim_digest',internal.initial_media_handoff_proof_digest('claim',claim),'objects',objects,'authorized_at_ms',start_ms));"
        verify_sql += inject("INSERT INTO internal.initial_media_verification_receipts_v2 VALUES(r.scan_id,r.owner_id,verified,internal.initial_media_handoff_proof_digest('verification_receipt',verified));")
        transfer_sql = "transferred:=internal.initial_canonical(jsonb_build_object('version',1,'admission_receipt_digest',r.receipt_digest,'protocol_artifact_digest',r.media_binding::JSONB#>'{phase_window,protocol_artifact_digest}','verification_receipt',verified::JSONB,'verification_receipt_digest',internal.initial_media_handoff_proof_digest('verification_receipt',verified),'authorized_at_ms',start_ms));"
        transfer_sql += inject("INSERT INTO internal.initial_preparation_transfer_receipts VALUES(r.scan_id,r.owner_id,transferred,internal.initial_media_handoff_proof_digest('transfer_receipt',transferred));")
        def check(name, sql, expected=None):
            q.execute(name, prefix + sql + suffix, expected)
        check('synthetic_empty_copy_chain', chain)
        check('synthetic_full_but_incomplete_chain', full + chain)
        check('synthetic_complete_copy_chain', complete + chain)
        check('synthetic_complete_claim_chain', complete + claim_sql + chain)
        check('synthetic_complete_verification_chain', complete + claim_sql + verify_sql + chain)
        check('synthetic_complete_transfer_chain', complete + claim_sql + verify_sql + transfer_sql + chain)
        check('claim_requires_explicit_copy_completion', full + claim_sql + chain, '55000')
        check('progress_requires_original_admission', inject("UPDATE internal.initial_media_copy_progress SET admission_receipt_digest=repeat('f',64) WHERE scan_id=r.scan_id;") + chain, '55000')
        check('progress_requires_original_adapter', inject("UPDATE internal.initial_media_copy_progress SET copy_adapter_digest=repeat('f',64) WHERE scan_id=r.scan_id;") + chain, '55000')
        check('progress_rejects_foreign_tuple', inject("UPDATE internal.initial_media_copy_progress SET completed_objects=internal.initial_canonical(jsonb_build_array(jsonb_set(objects->0,'{object_id}',to_jsonb(extensions.gen_random_uuid()::TEXT)))),last_object_at_ms=start_ms WHERE scan_id=r.scan_id;") + chain, '55000')
        check('progress_copy_cutoff_equality_rejected', inject("UPDATE internal.initial_media_copy_progress SET started_at_ms=(r.media_binding::JSONB#>>'{phase_window,cutoffs,copy}')::BIGINT WHERE scan_id=r.scan_id;") + chain, '55000')
        check('claim_cannot_precede_copy_completion', complete + inject("UPDATE internal.initial_media_copy_progress SET completed_at_ms=start_ms+1 WHERE scan_id=r.scan_id;") + claim_sql + chain, '55000')
        cancel = """SET LOCAL ROLE service_role;
result:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;
IF result->>'dispatch' IS DISTINCT FROM 'dispatch_prevented'
 OR EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id)
 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID AND state='refunded' AND refund_count=1)
THEN RAISE EXCEPTION USING ERRCODE='ZX705';END IF;
"""
        check('real_c1_erases_synthetic_empty_copy', chain + cancel)
        check('real_c1_erases_synthetic_full_incomplete_copy', full + chain + cancel)
        check('real_c1_erases_synthetic_claimed_copy', complete + claim_sql + chain + cancel)
        check('real_c1_erases_synthetic_verified_copy', complete + claim_sql + verify_sql + chain + cancel)
        transferred_state = complete + claim_sql + verify_sql + transfer_sql
        transferred_state += inject("UPDATE internal.initial_preparation_source_fences SET state='retired' WHERE scan_id=r.scan_id;"
                                    "UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE scan_id=r.scan_id;" +
                                    ''.join('DELETE FROM internal.' + table + ' WHERE scan_id=r.scan_id;' for table in [
                                        'initial_preparation_source_mapping', 'initial_preparation_source_verifications',
                                        'initial_preparation_execution_grants', 'initial_preparation_output_mapping',
                                        'initial_preparation_output_manifests', 'initial_preparation_outcomes',
                                        'initial_analysis_preparation_intents']))
        live = 'PERFORM internal.assert_initial_admission_live_receipt(r.owner_id,r.scan_id,r.admission_receipt_id);'
        check('synthetic_transferred_retained_live_proof', transferred_state + live)
        check('real_c1_erases_synthetic_transferred_state', transferred_state + live + cancel)
        check('transferred_source_must_remain_retired', transferred_state + inject(
            "UPDATE internal.initial_preparation_source_registry SET retired=FALSE WHERE scan_id=r.scan_id;") + live, '55000')
        check('transferred_source_union_must_remain_complete', transferred_state + inject(
            "DELETE FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id;") + live, '55000')
        check('transfer_document_does_not_replace_retirement', complete + claim_sql + verify_sql + transfer_sql + live, '55000')
        check('empty_retirement_requires_captured_prestate',
              "PERFORM internal.assert_initial_cancellation_retirement_images(r.scan_id,'source','[]',TRUE,NULL);", '55000')
        def recovered(phase, time='start_ms', outcome='admitted'):
            return ('result:=internal.initial_media_handoff_recovery_response(r,' + time + ");"
                    "IF result->>'authority' IS DISTINCT FROM 'none' OR result->>'outcome' IS DISTINCT FROM '" + outcome +
                    "' OR result->>'phase' IS DISTINCT FROM " + ("'" + phase + "'" if phase else 'NULL') +
                    " THEN RAISE EXCEPTION USING ERRCODE='ZX706';END IF;")
        check('recovery_empty_copy', recovered('copy'))
        check('recovery_full_incomplete_stays_copy', full + recovered('copy'))
        check('recovery_completed_copy_verification', complete + recovered('verification'))
        check('recovery_claimed_after_read_cutoff_has_no_authority', complete + claim_sql +
              recovered('verification', "(r.media_binding::JSONB#>>'{phase_window,cutoffs,verification}')::NUMERIC"))
        check('recovery_verified_transfer_phase', complete + claim_sql + verify_sql + recovered('transfer'))
        for prefix_sql, cutoff in [('', 'copy'), (complete, 'verification_claim'),
                                   (complete + claim_sql, 'verification_settlement'),
                                   (complete + claim_sql + verify_sql, 'transfer')]:
            check('recovery_cutoff_equality_' + cutoff, prefix_sql +
                  recovered('expired', "(r.media_binding::JSONB#>>'{phase_window,cutoffs," + cutoff + "}')::NUMERIC"))
        check('recovery_transfer_precedes_original_expiry', transferred_state +
              recovered(None, "(r.media_binding::JSONB#>>'{phase_window,original_expires_at_ms}')::NUMERIC+1", 'transferred'))
        check('recovery_owner_after_transfer_without_intent', transferred_state +
              "result:=internal.recover_initial_admitted_media(r.owner_id,r.scan_id);IF result->>'outcome' IS DISTINCT FROM 'transferred' OR result->>'authority' IS DISTINCT FROM 'none' THEN RAISE EXCEPTION USING ERRCODE='ZX707';END IF;")
        # Test-only rollback tripwires observe real source-first retirement.
        # They never grant authority or replace a production guard.
        probe = """BEGIN;
CREATE FUNCTION pg_temp.handoff_source_first_probe() RETURNS TRIGGER LANGUAGE plpgsql AS $probe$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND state<>'retired')
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=NEW.scan_id AND NOT retired)
 THEN RAISE EXCEPTION USING ERRCODE='ZX708';END IF;
 RETURN NEW;
END; $probe$;
CREATE TRIGGER handoff_source_first_probe BEFORE UPDATE ON internal.initial_analysis_media_allocation_fences
 FOR EACH ROW EXECUTE FUNCTION pg_temp.handoff_source_first_probe();
CREATE TRIGGER handoff_source_first_probe BEFORE UPDATE ON internal.initial_analysis_media_registry
 FOR EACH ROW EXECUTE FUNCTION pg_temp.handoff_source_first_probe();
DO $$"""
        raw_prefix = prefix.replace('BEGIN;DO $$', probe)
        raw_assert = """
IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id AND NOT retired)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=r.scan_id AND NOT retired)
 OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=r.scan_id AND state='retired')
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=r.scan_id AND state='retired')
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND (refund_count<>0 OR state='refunded'))
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
THEN RAISE EXCEPTION USING ERRCODE='ZX709';END IF;
"""
        tombstone = "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES(r.scan_id,NULL,clock_timestamp());"
        damaged = inject("UPDATE internal.initial_media_copy_progress SET admission_receipt_digest=repeat('f',64) WHERE scan_id=r.scan_id;")
        roots = {
            'tombstone': tombstone,
            'generic_unknown_cancel': "PERFORM set_config('request.jwt.claim.role','service_role',TRUE);result:=internal.cancel_initial_analysis(r.owner_id,r.scan_id);IF result->>'dispatch' IS DISTINCT FROM 'dispatch_outcome_unknown' THEN RAISE EXCEPTION USING ERRCODE='ZX710';END IF;",
            'raw_owner_delete': "DELETE FROM public.users WHERE id=r.owner_id;",
            'scan_detach': inject("INSERT INTO public.scans(id,user_id,ai_confidence_score) VALUES(r.scan_id,r.owner_id,0);") + "UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE WHERE id=r.scan_id;",
            'existing_tombstone_scan_detach': inject("INSERT INTO public.scans(id,user_id,ai_confidence_score) VALUES(r.scan_id,r.owner_id,0);" + tombstone) + "UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE WHERE id=r.scan_id;",
            'existing_tombstone_owner_delete': inject(tombstone) + "DELETE FROM public.users WHERE id=r.owner_id;",
        }
        for name, root in roots.items():
            q.execute('raw_source_first_' + name + '_damaged_private_proof', raw_prefix + damaged + root + raw_assert + suffix)
        missing_roots = inject("FOR private_member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP EXECUTE format('DELETE FROM %s WHERE scan_id=$1',private_member.relation_name) USING r.scan_id;END LOOP;")
        for name in ['tombstone', 'raw_owner_delete', 'scan_detach',
                     'existing_tombstone_scan_detach', 'existing_tombstone_owner_delete']:
            q.execute('raw_source_first_' + name + '_absent_private_roots', raw_prefix + missing_roots + roots[name] + raw_assert + suffix)
        q.execute('raw_source_first_transferred_tombstone', raw_prefix + transferred_state + tombstone + raw_assert + suffix)
        q.execute('raw_source_first_transferred_generic_cancel', raw_prefix + transferred_state + roots['generic_unknown_cancel'] + raw_assert + suffix)
        check('shape_rejects_duplicates_and_extra_fields', """
IF internal.initial_media_copy_progress_shape(internal.initial_canonical(jsonb_build_array(objects->0,objects->0)),start_ms,start_ms,NULL)
 OR internal.initial_media_copy_progress_shape(internal.initial_canonical(jsonb_build_array((objects->0)||'{"extra":true}'::JSONB)),start_ms,start_ms,NULL)
 OR internal.initial_media_copy_progress_shape('[]',start_ms,start_ms,NULL)
 OR internal.initial_media_copy_progress_shape(internal.initial_canonical(objects),start_ms,start_ms-1,NULL)
 OR internal.initial_media_copy_progress_shape(internal.initial_canonical(objects),start_ms,start_ms,start_ms-1)
 OR internal.initial_media_copy_progress_shape(repeat(' ',8193),start_ms,NULL,NULL)
 OR internal.initial_media_copy_progress_shape('{}',start_ms,NULL,NULL)
 OR internal.initial_media_copy_progress_shape(NULL,start_ms,NULL,NULL)
THEN RAISE EXCEPTION USING ERRCODE='ZX704'; END IF;
""")
    finally:
        fixture.close()


def plan_cases(q, owner, scan):
    """Planner tests only: applying expected images uses privileged rollback DML.

    No guarded writer, trigger provenance, blob I/O or concurrency is exercised.
    """
    prefix = """BEGIN;
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
DO $$ DECLARE r internal.initial_preparation_admission_receipts; p JSONB; before_state JSONB;
    source JSONB; object_id UUID; token UUID; verification_digest TEXT; item JSONB;
    copy_start BIGINT; frame JSONB; image JSONB; event_count INTEGER;
BEGIN
SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='""" + scan + """';
"""
    suffix = 'END $$;ROLLBACK;'
    call = "p:=internal.plan_initial_media_handoff_mutation(r.owner_id,r.scan_id,"
    start = call + "'start_copy',r.receipt_digest);"
    apply_copy = """SET LOCAL session_replication_role='replica';
INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,p#>'{events,0,new}');
SET LOCAL session_replication_role='origin';
"""
    fill = """FOR object_id IN SELECT (value->>'object_id')::UUID FROM jsonb_array_elements(r.mapping::JSONB->'objects') ORDER BY (value->>'object_id')::UUID DESC LOOP
""" + call + "'record_object',r.receipt_digest,object_id);" + """
image:=p#>'{events,0,new}';
IF image->>'started_at_ms' IS DISTINCT FROM copy_start::TEXT OR p#>>'{events,0,operation}'<>'UPDATE'
 OR image->>'completed_at_ms' IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='ZX720';END IF;
SET LOCAL session_replication_role='replica';
UPDATE internal.initial_media_copy_progress SET completed_objects=image->>'completed_objects',last_object_at_ms=(image->>'last_object_at_ms')::BIGINT WHERE scan_id=r.scan_id;
SET LOCAL session_replication_role='origin';
END LOOP;
"""
    started = start + "copy_start:=(p#>>'{events,0,new,started_at_ms}')::BIGINT;" + apply_copy
    filled = started + fill
    complete = filled + call + "'complete_copy',r.receipt_digest);" + """
SET LOCAL session_replication_role='replica';
UPDATE internal.initial_media_copy_progress SET completed_at_ms=(p#>>'{events,0,new,completed_at_ms}')::BIGINT WHERE scan_id=r.scan_id;
SET LOCAL session_replication_role='origin';
"""
    claimed = complete + call + "'claim',r.receipt_digest);" + """
token:=((p#>>'{events,0,new,claim}')::JSONB->>'claim_token')::UUID;
SET LOCAL session_replication_role='replica';
INSERT INTO internal.initial_media_verification_claims_v2 SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_verification_claims_v2,p#>'{events,0,new}');
SET LOCAL session_replication_role='origin';
"""
    verified = claimed + call + "'verify',r.receipt_digest,NULL,token);" + """
verification_digest:=p#>>'{events,0,new,receipt_digest}';
SET LOCAL session_replication_role='replica';
INSERT INTO internal.initial_media_verification_receipts_v2 SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_verification_receipts_v2,p#>'{events,0,new}');
SET LOCAL session_replication_role='origin';
"""
    transfer = call + "'transfer',r.receipt_digest,NULL,NULL,verification_digest);"
    def check(name, sql, expected=None):
        q.execute('plan_' + name, prefix + sql + suffix, expected)
    check('start_is_private_read_only_plan', start + """
IF p->>'authority'<>'none' OR jsonb_array_length(p->'events')<>1 OR jsonb_array_length(p->'frames')<>1
 OR p#>>'{events,0,operation}'<>'INSERT' OR p#>>'{events,0,new,completed_objects}'<>'[]'
 OR (p#>>'{events,0,new,started_at_ms}')::BIGINT<>(p->>'authorized_at_ms')::BIGINT
 OR EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=r.scan_id)
 OR (SELECT count(*) FROM jsonb_object_keys(p->'snapshot'))<>31
THEN RAISE EXCEPTION USING ERRCODE='ZX721';END IF;
""")
    check('all_six_actions_retained_chain_and_transfer_graph', verified + """
before_state:=internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);
""" + transfer + """
IF before_state IS DISTINCT FROM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id)
 OR p#>>'{events,0,relation}'<>'internal.initial_preparation_transfer_receipts'
 OR p#>>'{events,1,new,state}'<>'retired'
 OR jsonb_array_length(p->'events')>39 OR jsonb_array_length(p->'frames')>32
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p->'events') e WHERE e->>'relation' IN
  ('internal.ai_quota_reservations','internal.complimentary_scan_usage','internal.initial_analysis_media_registry'))
THEN RAISE EXCEPTION USING ERRCODE='ZX722';END IF;
FOR frame IN SELECT value FROM jsonb_array_elements(p->'frames') LOOP
 SELECT count(*) INTO event_count FROM jsonb_array_elements(p->'events') e WHERE e->'frame'=frame->'id';
 IF event_count<>jsonb_array_length(frame->'events') THEN RAISE EXCEPTION USING ERRCODE='ZX723';END IF;
 IF frame->>'parent' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'frames') f
  WHERE f->'id'=frame->'parent' AND f->>'operation'='DELETE') THEN RAISE EXCEPTION USING ERRCODE='ZX724';END IF;
END LOOP;
IF (SELECT count(*) FROM jsonb_array_elements(p->'frames') f WHERE f->>'parent' IS NOT NULL)<>6 THEN
 RAISE EXCEPTION USING ERRCODE='ZX725';END IF;
PERFORM internal.assert_initial_media_handoff_chain(r.owner_id,r.scan_id);
""")
    check('repeat_start_rejected_before_new_authority', started + start, '55000')
    check('record_requires_existing_copy', call + "'record_object',r.receipt_digest,extensions.gen_random_uuid());", '55000')
    check('record_rejects_foreign_object', started + call + "'record_object',r.receipt_digest,extensions.gen_random_uuid());", '55000')
    check('record_rejects_duplicate', filled + "object_id:=(r.mapping::JSONB#>>'{objects,0,object_id}')::UUID;" + call + "'record_object',r.receipt_digest,object_id);", '55000')
    check('complete_requires_full_union', started + call + "'complete_copy',r.receipt_digest);", '55000')
    check('claim_requires_explicit_completion', filled + call + "'claim',r.receipt_digest);", '55000')
    check('claim_cannot_renew', claimed + call + "'claim',r.receipt_digest);", '55000')
    check('verify_requires_original_token', claimed + call + "'verify',r.receipt_digest,NULL,extensions.gen_random_uuid());", '55000')
    check('transfer_requires_original_verification', verified + call + "'transfer',r.receipt_digest,NULL,NULL,repeat('f',64));", '55000')
    check('requires_original_admission', call + "'start_copy',repeat('f',64));", '55000')
    for action, slots in [('bad', 'NULL,NULL,NULL'), ('start_copy', 'extensions.gen_random_uuid(),NULL,NULL'),
                          ('record_object', 'NULL,NULL,NULL'), ('verify', 'NULL,NULL,NULL'),
                          ('transfer', "NULL,NULL,'bad'")]:
        check('closed_arguments_' + action, call + "'" + action + "',r.receipt_digest," + slots + ');', '22023')
    check('live_gate_required', "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;" + start, '55000')
    check('fk_catalog_extra_child_rejected', """
CREATE TABLE internal.handoff_test_extra_child(scan_id UUID REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE);
PERFORM internal.assert_initial_media_handoff_cascade_catalog();
""", '55000')
    check('snapshot_preflight_rejects_extra_attempt', """
SET LOCAL session_replication_role='replica';
INSERT INTO internal.identification_provider_attempts SELECT (jsonb_populate_record(NULL::internal.identification_provider_attempts,to_jsonb(t)||'{"attempt_count":2}'::JSONB)).*
 FROM internal.identification_provider_attempts t WHERE reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID;
SET LOCAL session_replication_role='origin';
PERFORM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);
""", '55000')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-state', args.replay_manifest)
    source = Path(__file__).resolve()
    q.record['source_manifest'][str(source.relative_to(source.parents[3]))] = q.digest(source)
    helper = source.with_name('initial_media_handoff_transaction_cases.py')
    q.record['source_manifest'][str(helper.relative_to(source.parents[3]))] = q.digest(helper)
    q.record['scope'] = ('Private storage/chain, ordered locks, fresh planning, selected origin-mode transaction guards and bounded raw erasure. '
                         'Predecessors are privileged rollback fixtures. Fixed replay owners, physical I/O, concurrency and full runtime acceptance remain open.')
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
