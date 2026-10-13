"""Synthetic local qualification of the private transaction protocol.

Predecessor documents use privileged rollback fixtures. The selected operation
uses origin-mode stage/ledger/row/statement guards. No physical I/O, fixed
replay owner, API access, installed execution or concurrency is qualified here.
"""


def transaction_cases(q, owner, scan, fresh_admission=None):
    prefix = """BEGIN;
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
DO $$ DECLARE r internal.initial_preparation_admission_receipts; p JSONB; image JSONB;
    object_id UUID; token UUID; verification_digest TEXT; before_state JSONB;
    stage internal.initial_media_handoff_staging; entry_ordinal INTEGER;
BEGIN
SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='""" + scan + """';
"""
    suffix = 'END $$;ROLLBACK;'
    call = "p:=internal.plan_initial_media_handoff_mutation(r.owner_id,r.scan_id,"
    started = call + "'start_copy',r.receipt_digest);" + """
SET LOCAL session_replication_role='replica';
INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,p#>'{events,0,new}');
SET LOCAL session_replication_role='origin';
"""
    filled = started + """FOR object_id IN SELECT (value->>'object_id')::UUID FROM jsonb_array_elements(r.mapping::JSONB->'objects') LOOP
""" + call + "'record_object',r.receipt_digest,object_id);" + """
image:=p#>'{events,0,new}';
SET LOCAL session_replication_role='replica';
UPDATE internal.initial_media_copy_progress SET completed_objects=image->>'completed_objects',last_object_at_ms=(image->>'last_object_at_ms')::BIGINT WHERE scan_id=r.scan_id;
SET LOCAL session_replication_role='origin';
END LOOP;
"""
    completed = filled + call + "'complete_copy',r.receipt_digest);" + """
SET LOCAL session_replication_role='replica';
UPDATE internal.initial_media_copy_progress SET completed_at_ms=(p#>>'{events,0,new,completed_at_ms}')::BIGINT WHERE scan_id=r.scan_id;
SET LOCAL session_replication_role='origin';
"""
    claimed = completed + call + "'claim',r.receipt_digest);" + """
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
    defer = """SET CONSTRAINTS internal.initial_media_handoff_completion,
 internal.initial_source_intent_cohort,internal.initial_source_fence_cohort,
 internal.initial_source_mapping_cohort,internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
"""
    def stage(action, object_arg='NULL', claim_arg='NULL', verification_arg='NULL'):
        return defer + "INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest) VALUES(r.scan_id,r.owner_id,'" + action + "',r.receipt_digest," + object_arg + ',' + claim_arg + ',' + verification_arg + ');'
    execute = 'PERFORM internal.execute_initial_media_handoff_stage(r.scan_id);'
    success = """
IF EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=r.scan_id)
 OR NOT internal.initial_media_handoff_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX731'; END IF;
PERFORM internal.assert_initial_media_handoff_chain(r.owner_id,r.scan_id);
"""
    register = """SELECT * INTO STRICT stage FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id;
FOR entry_ordinal IN 0..jsonb_array_length(stage.events)-1 LOOP
 INSERT INTO internal.initial_media_handoff_writes(scan_id,ordinal) VALUES(r.scan_id,entry_ordinal);
END LOOP;
UPDATE internal.initial_media_handoff_staging SET registered=0 WHERE scan_id=r.scan_id;
"""
    mutate = "INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,stage.events#>'{0,new}');"
    def check(name, sql, expected=None):
        admission = fresh_admission() if fresh_admission is not None else None
        case_prefix = prefix.replace(scan, admission.scan_id) if admission is not None else prefix
        q.execute('transaction_' + name, case_prefix + sql + suffix, expected)
        if admission is not None:
            # Each selected operation rolls back. Release this untouched positive
            # unused synthetic admission through C1 before creating the next one.
            q.execute('transaction_' + name + '_fixture_c1_cleanup',
                "BEGIN;DO $$ DECLARE result JSONB;BEGIN SET LOCAL ROLE service_role;"
                + "result:=public.cancel_initial_analysis('" + owner + "','" + admission.scan_id
                + "');RESET ROLE;IF result IS DISTINCT FROM "
                + "'{\"version\":1,\"outcome\":\"cancelled\",\"dispatch\":\"dispatch_prevented\"}'::JSONB "
                + "THEN RAISE EXCEPTION USING ERRCODE='ZX735';END IF;END $$;COMMIT;")
    trace_setup = """
CREATE TEMP TABLE handoff_callback_audit(sequence BIGINT GENERATED ALWAYS AS IDENTITY,relation TEXT,phase TEXT);
CREATE FUNCTION pg_temp.handoff_callback_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $audit$
BEGIN INSERT INTO pg_temp.handoff_callback_audit(relation,phase) VALUES(TG_TABLE_NAME,TG_WHEN);RETURN NULL;END $audit$;
DO $install$ DECLARE relation TEXT;BEGIN
 FOREACH relation IN ARRAY ARRAY['initial_analysis_preparation_intents','initial_preparation_source_mapping',
  'initial_preparation_source_verifications','initial_preparation_execution_grants','initial_preparation_output_manifests',
  'initial_preparation_output_mapping','initial_preparation_outcomes'] LOOP
  EXECUTE format('CREATE TRIGGER a001_handoff_callback_audit BEFORE DELETE ON internal.%I FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.handoff_callback_audit()',relation);
  EXECUTE format('CREATE TRIGGER zzzz_handoff_callback_audit AFTER DELETE ON internal.%I FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.handoff_callback_audit()',relation);
 END LOOP;
END $install$;
"""
    trace_assert = """
IF (SELECT count(*) FROM pg_temp.handoff_callback_audit)<>14
 OR EXISTS(SELECT 1 FROM pg_temp.handoff_callback_audit GROUP BY relation,phase HAVING count(*)<>1)
 OR NOT ((SELECT sequence FROM pg_temp.handoff_callback_audit WHERE relation='initial_analysis_preparation_intents' AND phase='AFTER')
  <(SELECT sequence FROM pg_temp.handoff_callback_audit WHERE relation='initial_preparation_output_mapping' AND phase='BEFORE'))
 OR NOT ((SELECT sequence FROM pg_temp.handoff_callback_audit WHERE relation='initial_preparation_source_verifications' AND phase='BEFORE')
  <(SELECT sequence FROM pg_temp.handoff_callback_audit WHERE relation='initial_preparation_source_mapping' AND phase='AFTER'))
THEN RAISE EXCEPTION USING ERRCODE='ZX734'; END IF;
"""
    operations = [
        ('start_copy', '', stage('start_copy')),
        ('record_object', started, stage('record_object', "(r.mapping::JSONB#>>'{objects,0,object_id}')::UUID")),
        ('complete_copy', filled, stage('complete_copy')),
        ('claim', completed, stage('claim')),
        ('verify', claimed, stage('verify', claim_arg='token')),
        ('transfer', verified + trace_setup, stage('transfer', verification_arg='verification_digest')),
    ]
    check('unfinished_stage_rejected', stage('start_copy') + 'SET CONSTRAINTS ALL IMMEDIATE;', '55000')
    check('raw_stage_delete_rejected', stage('start_copy') + 'DELETE FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id;', '55000')
    # PostgreSQL refuses this before user triggers because deferred completion
    # events are pending. The empty-table case separately reaches our guard.
    check('stage_truncate_rejected', stage('start_copy') + 'TRUNCATE internal.initial_media_handoff_staging CASCADE;', '55006')
    check('empty_stage_truncate_guard_rejected', 'TRUNCATE internal.initial_media_handoff_staging CASCADE;', '55000')
    check('caller_derived_authority_rejected', """
INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,transaction_id)
 VALUES(r.scan_id,r.owner_id,'start_copy',r.receipt_digest,pg_current_xact_id());
""", '55000')
    check('ledger_truncate_rejected', stage('start_copy') + 'TRUNCATE internal.initial_media_handoff_writes;', '55000')
    check('missing_ledger_registration_rejected', stage('start_copy') + 'UPDATE internal.initial_media_handoff_staging SET registered=0 WHERE scan_id=r.scan_id;', '55000')
    check('fake_consumption_rejected', stage('start_copy') + register + "UPDATE internal.initial_media_handoff_writes SET consumed=TRUE,observed_new=new_image WHERE scan_id=r.scan_id;", '55000')
    check('before_without_open_frame_rejected', stage('start_copy') + register + "UPDATE internal.initial_media_handoff_writes SET before_seen=TRUE WHERE scan_id=r.scan_id;", '55000')
    check('early_after_rejected', stage('start_copy') + register + "UPDATE internal.initial_media_handoff_staging SET after_seen=ARRAY[0] WHERE scan_id=r.scan_id;", '55000')
    check('manufactured_closure_rejected', stage('start_copy') + register + "UPDATE internal.initial_media_handoff_staging SET closed=ARRAY[0],next_root=1 WHERE scan_id=r.scan_id;", '55000')
    check('duplicate_after_rejected', stage('start_copy') + register + mutate + "UPDATE internal.initial_media_handoff_staging SET after_seen=after_seen||0 WHERE scan_id=r.scan_id;", '55000')
    check('reset_before_after_consumption_rejected', stage('start_copy') + register + mutate + "UPDATE internal.initial_media_handoff_writes SET before_seen=FALSE WHERE scan_id=r.scan_id;", '55000')
    check('repeat_closed_frame_rejected', stage('start_copy') + register + mutate + "UPDATE internal.initial_media_handoff_staging SET active=ARRAY[0] WHERE scan_id=r.scan_id;", '55000')
    check('missing_events_cannot_complete', stage('start_copy') + register + "UPDATE internal.initial_media_handoff_staging SET phase='complete' WHERE scan_id=r.scan_id;", '55000')
    check('unregistered_statement_rejected', stage('start_copy') + 'DELETE FROM internal.initial_media_copy_progress WHERE FALSE;', '55000')
    check('wrong_registered_statement_rejected', stage('start_copy') + register + 'DELETE FROM internal.initial_media_copy_progress WHERE FALSE;', '55000')
    for role in ['authenticated', 'service_role']:
        for table, column in [('scans', 'custom_tags'), ('users', 'marketing_opt_in')]:
            # service_role has no preference-column UPDATE grant: PostgreSQL
            # rejects it before the trigger, including while a stage exists.
            parent_denied = role == 'service_role' and table == 'users'
            check(role + ('_parent_acl_denied_' if parent_denied else '_unplanned_public_') + table + '_rejected', stage('start_copy') + register
                  + 'SET LOCAL ROLE ' + role + ';UPDATE public.' + table + ' SET ' + column + '=' + column + ' WHERE FALSE;',
                  '42501' if parent_denied else '55000')
    check('zero_row_expected_insert_rejected', stage('start_copy') + register + "INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,stage.events#>'{0,new}') WHERE FALSE;", '55000')
    check('extra_zero_row_statement_after_root_rejected', stage('start_copy') + register + mutate + 'DELETE FROM internal.initial_media_copy_progress WHERE FALSE;', '55000')
    check('zero_row_failure_rolls_back_frame', stage('start_copy') + register + """
BEGIN
 INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,stage.events#>'{0,new}') WHERE FALSE;
 RAISE EXCEPTION USING ERRCODE='ZX732';
EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
END;
""" + mutate + """
IF NOT EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id AND next_root=1 AND registered IS NULL AND cardinality(active)=0)
 OR NOT EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=r.scan_id AND ordinal=0 AND consumed)
THEN RAISE EXCEPTION USING ERRCODE='ZX733';END IF;
""")
    for label, sql in [
        ('domain', 'UPDATE internal.initial_media_copy_progress SET completed_at_ms=completed_at_ms WHERE FALSE;'),
        ('funding', 'UPDATE internal.ai_quota_reservations SET state=state WHERE FALSE;'),
        ('eligibility', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE WHERE FALSE;'),
        ('raw_erasure', 'DELETE FROM internal.initial_analysis_preparation_intents WHERE FALSE;'),
    ]:
        check('sealed_zero_row_' + label + '_rejected', stage('start_copy') + execute + sql, '55000')
    check('foreign_admin_domain_insert_without_stage_rejected', call + "'start_copy',r.receipt_digest);"
          + "INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,p#>'{events,0,new}');", '55000')
    check('forged_seal_denies_stage', 'PERFORM pg_advisory_xact_lock(1229801542,hashtext(r.scan_id::TEXT));' + stage('start_copy'), '55000')
    # Rollback-only schema augmentation isolates the real pre-aggregation byte
    # guards without retaining large fixtures or relaxing production schemas.
    def padding(tables, size):
        sql = ''
        for table in tables:
            sql += 'ALTER TABLE internal.' + table + ' ADD COLUMN qualification_padding TEXT;'
        sql += "SET LOCAL session_replication_role='replica';"
        for table in tables:
            sql += 'UPDATE internal.' + table + " SET qualification_padding=repeat('x'," + str(size) + ') WHERE scan_id=r.scan_id;'
        return sql + "SET LOCAL session_replication_role='origin';"
    check('snapshot_row_bytes_bounded', padding(['initial_analysis_submissions'], 33554433)
          + 'PERFORM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);', '54000')
    check('snapshot_total_bytes_bounded', padding(['initial_analysis_submissions', 'initial_analysis_admissions',
          'initial_analysis_preparation_intents'], 23068672)
          + 'PERFORM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);', '54000')
    check('transfer_ledger_bytes_bounded', verified + padding(['initial_preparation_source_fences',
          'initial_preparation_source_registry'], 23068672) + call
          + "'transfer',r.receipt_digest,NULL,NULL,verification_digest);", '54000')
    for action, setup, enter in operations:
        for constraints in ['DEFERRED', 'IMMEDIATE']:
            check(action + '_' + constraints.lower(), setup + 'SET CONSTRAINTS ALL ' + constraints + ';' + enter + execute + success + (trace_assert if action == 'transfer' else ''))
