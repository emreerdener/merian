"""Account-batch and expiry qualification for synthetic admitted records."""
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE


def account_batch_cases(qualification):
    base = BASE
    execute = qualification.execute
    qualification.record['scope'] = ('Two same-owner synthetic committed held v3 admissions; actual service-role account tombstone with pre-delete accounting/cascade observers, rollback faults and commit. Local SQL only, no Auth API or external cleanup qualification.')
    fixture = AdmissionFixture(qualification, held=True)
    try:
        fixture.admit_one()
        fixture.admit_one()
    finally:
        fixture.close()
    setup = "\nCREATE TEMP TABLE batch_audit(kind TEXT);\nCREATE FUNCTION pg_temp.quota_delete_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN\n IF OLD.state<>'reserved' OR OLD.refund_count<>0 THEN RAISE EXCEPTION USING ERRCODE='ZX451';END IF;\n INSERT INTO batch_audit VALUES('quota_original');RETURN OLD;END $$;\nCREATE TRIGGER test_account_quota BEFORE DELETE ON internal.ai_quota_reservations FOR EACH ROW EXECUTE FUNCTION pg_temp.quota_delete_audit();\nCREATE FUNCTION pg_temp.user_delete_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN\n IF internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging)\n OR (SELECT count(*) FROM internal.initial_analysis_cancellations WHERE owner_id=OLD.id AND dispatch='dispatch_outcome_unknown')<>2\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=OLD.id AND (state<>'reserved' OR refund_count<>0))\n THEN RAISE EXCEPTION USING ERRCODE='ZX452';END IF;\n INSERT INTO batch_audit VALUES('user_delete_after_both');RETURN OLD;END $$;\nCREATE TRIGGER test_account_user BEFORE DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION pg_temp.user_delete_audit();\n"
    call = "DO $$ DECLARE o UUID;BEGIN SELECT owner_id INTO STRICT o FROM internal.initial_preparation_admission_receipts GROUP BY owner_id;\n IF (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>2 OR (SELECT count(*) FROM internal.ai_quota_reservations)<>2 THEN RAISE EXCEPTION USING ERRCODE='ZX453';END IF;\n SET LOCAL ROLE service_role;PERFORM public.apply_user_tombstone(o);RESET ROLE;\n IF EXISTS(SELECT 1 FROM public.users WHERE id=o) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations) OR EXISTS(SELECT 1 FROM internal.identification_invocations)\n OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging)\n OR (SELECT count(*) FROM batch_audit WHERE kind='quota_original')<>2 OR (SELECT count(*) FROM batch_audit WHERE kind='user_delete_after_both')<>1\n THEN RAISE EXCEPTION USING ERRCODE='ZX454';END IF;\n SET LOCAL ROLE service_role;END $$;"
    setup += "\nCREATE FUNCTION pg_temp.no_account_settlement_update() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION USING ERRCODE='ZX459';END $$;\nCREATE TRIGGER no_account_quota_update BEFORE UPDATE ON internal.ai_quota_reservations FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.no_account_settlement_update();\nCREATE TRIGGER no_account_counter_update BEFORE UPDATE ON internal.ai_quota_counters FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.no_account_settlement_update();\nCREATE TRIGGER no_account_credit_update BEFORE UPDATE ON internal.complimentary_scan_usage FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.no_account_settlement_update();\nCREATE TRIGGER no_account_epoch_update BEFORE UPDATE ON public.users FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.no_account_settlement_update();\nCREATE FUNCTION pg_temp.credit_delete_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN\n IF OLD.state<>'held' OR OLD.settled_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='ZX460';END IF;\n INSERT INTO batch_audit VALUES('credit_original');RETURN OLD;END $$;\nCREATE TRIGGER test_account_credit BEFORE DELETE ON internal.complimentary_scan_usage FOR EACH ROW EXECUTE FUNCTION pg_temp.credit_delete_audit();\n"
    call = call.replace('(SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>2', '(SELECT count(*) FROM internal.initial_analysis_submissions)<>2')
    call = call.replace("OR (SELECT count(*) FROM batch_audit WHERE kind='quota_original')<>2", "OR (SELECT count(*) FROM batch_audit WHERE kind='credit_original')<>2 OR (SELECT count(*) FROM batch_audit WHERE kind='quota_original')<>2")
    projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'public.users'])) + ')'
    setup = 'CREATE TEMP TABLE batch_before AS SELECT ' + projection + ' AS value;' + setup
    setup = setup.replace('IF internal.initial_cancellation_sealed()', 'IF (SELECT value FROM batch_before) IS DISTINCT FROM ' + projection + ' OR internal.initial_cancellation_sealed()')
    setup += "\nCREATE TRIGGER no_account_link_update BEFORE UPDATE ON internal.ai_quota_reservation_counters FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.no_account_settlement_update();\nCREATE FUNCTION pg_temp.link_delete_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN\n IF (SELECT count(*) FROM batch_audit WHERE kind='user_delete_after_both')<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX461';END IF;\n INSERT INTO batch_audit VALUES('link_after_user');RETURN OLD;END $$;\nCREATE TRIGGER test_account_links BEFORE DELETE ON internal.ai_quota_reservation_counters FOR EACH ROW EXECUTE FUNCTION pg_temp.link_delete_audit();\n"
    execute('actual_two_item_account_tombstone_rollback', base + setup + call + 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
    execute('second_cancellation_failure_rolls_back_first_and_preserves_original_funding', base + "CREATE FUNCTION pg_temp.fail_second() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN IF (SELECT count(*) FROM internal.initial_analysis_cancellations)=2 THEN RAISE EXCEPTION USING ERRCODE='ZX455';END IF;RETURN NULL;END $$;CREATE TRIGGER test_fail_second AFTER INSERT ON internal.initial_analysis_cancellations FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second();DO $$ DECLARE o UUID;failed BOOLEAN:=FALSE;BEGIN SELECT owner_id INTO STRICT o FROM internal.initial_preparation_admission_receipts GROUP BY owner_id;BEGIN SET LOCAL ROLE service_role;PERFORM public.apply_user_tombstone(o);EXCEPTION WHEN SQLSTATE 'ZX455' THEN failed:=TRUE;END;RESET ROLE;IF NOT failed OR (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>2 OR (SELECT count(*) FROM internal.initial_analysis_submissions)<>2 OR (SELECT count(*) FROM internal.initial_analysis_preparation_intents)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'reserved' OR refund_count<>0) OR internal.initial_cancellation_sealed() OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=o) THEN RAISE EXCEPTION USING ERRCODE='ZX456';END IF;END $$;ROLLBACK;")
    for table in ['internal.initial_preparation_admission_receipts', 'internal.initial_analysis_admissions']:
        damage = 'ALTER TABLE ' + table + ' DISABLE TRIGGER USER;DELETE FROM ' + table + ' WHERE scan_id=(SELECT scan_id FROM internal.initial_analysis_submissions ORDER BY scan_id DESC LIMIT 1);ALTER TABLE ' + table + ' ENABLE TRIGGER USER;'
        execute('damaged_' + table.rsplit('.', 1)[-1] + '_does_not_contaminate_account_batch', base + setup + damage + call + 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
    execute('actual_two_item_account_tombstone_commits', base + setup + call + 'COMMIT;')
    execute('fresh_session_account_erasure_removes_owner_receipts_retains_global_fences', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR (SELECT count(*) FROM internal.initial_analysis_lifecycle_fences WHERE state='cancelled_unknown')<>2 OR (SELECT count(*) FROM internal.initial_analysis_operation_fences)<>2 OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE retired)<>2 OR (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE retired)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX458';END IF;END $$;")


def admitted_expiry_cases(qualification):
    import json
    import time
    from initial_atomic_admission_sessions import Session

    base = BASE
    execute = qualification.execute
    qualification.record['scope'] = ('Actual elapsed expiry of two committed held v3 admissions; original deadlines are never changed. Actual service public recovery/execution wrappers; no provider or hosted IO.')
    fixture = AdmissionFixture(qualification, held=True)
    try:
        fixture.admit_one()
        fixture.admit_one()
    finally:
        fixture.close()
    started = time.monotonic()
    clock_reader = Session(qualification, 'original_deadline_observer')
    try:
        while True:
            value = json.loads(clock_reader.run('remaining_original_deadline', "SELECT jsonb_build_object('count',count(*),'remaining',GREATEST(0,extract(epoch FROM max(expires_at)-clock_timestamp()))) FROM internal.initial_analysis_preparation_intents;")[-1])
            remaining = float(value['remaining'])
            if value['count'] != 2 or not 0 <= remaining <= 360:
                raise ValueError('unexpected original deadline fixture')
            if remaining == 0:
                break
            if time.monotonic() - started + remaining > 360:
                raise TimeoutError('bounded original expiry wait')
            time.sleep(min(20, remaining + 0.05))
        qualification.record['actual_expiry_wait_seconds'] = round(time.monotonic() - started, 3)
        qualification.save()
    finally:
        clock_reader.close()
    projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in ['internal.initial_analysis_preparation_intents', 'internal.initial_preparation_admission_receipts', 'internal.initial_analysis_submissions', 'internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts'])) + ')'
    execute('both_original_deadlines_elapsed_gate_closed', "DO $$ BEGIN IF (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE expires_at>=clock_timestamp()) OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX481';END IF;END $$;")
    for kind in ['create', 'status', 'finalize', 'sources', 'issue', 'output', 'outcome', 'execution_status']:
        body = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;a JSONB;b JSONB;ad TEXT;BEGIN b:=' + projection + ";FOR r IN SELECT * FROM internal.initial_preparation_admission_receipts ORDER BY scan_id LOOP ad:=r.media_binding::JSONB->>'assignment_digest';SET LOCAL ROLE service_role;"
        if kind == 'create':
            call = 'a:=public.create_initial_preparation_intent(r.owner_id,r.scan_id,r.candidate);'
        elif kind == 'status':
            call = 'a:=public.get_initial_preparation_status(r.owner_id,r.scan_id);'
        elif kind == 'finalize':
            call = 'a:=public.finalize_initial_preparation(r.owner_id,r.scan_id,ad);'
        else:
            names = {'sources': 'settle_initial_preparation_sources', 'issue': 'issue_initial_preparation_execution', 'output': 'register_initial_preparation_output', 'outcome': 'settle_initial_preparation_outcome', 'execution_status': 'get_initial_preparation_execution_status'}
            call = 'a:=public.' + names[kind] + '(r.owner_id,r.scan_id,ad' + ('' if kind == 'execution_status' else ',NULL') + ');'
        expected = "a->>'outcome' IS DISTINCT FROM 'admitted' OR a->'binding' IS DISTINCT FROM r.media_binding::JSONB OR a->>'authority' IS DISTINCT FROM 'none'" if kind in ['create', 'status', 'finalize'] else "a IS DISTINCT FROM internal.initial_preparation_held_reply(2,'incoherent')"
        body += call + 'RESET ROLE;IF ' + expected + " THEN RAISE EXCEPTION USING ERRCODE='ZX482';END IF;END LOOP;IF b IS DISTINCT FROM " + projection + " OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX483';END IF;UPDATE public.users SET id=id WHERE FALSE;END $$;"
        execute('elapsed_v3_' + kind + '_no_generic_expiry_no_new_authority', base + body + 'COMMIT;')
