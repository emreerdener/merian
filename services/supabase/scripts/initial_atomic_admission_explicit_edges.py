"""Previously accepted absent-credit C1 edges, each preserving its rollback boundary.

Trusted corrupt/partial fixtures deliberately roll back invalid setup rather than
claim it passes deferred integrity. Authentic completion/replay probes retain
original constraint flushes; partial-stage commit has its own expected denial.
Independent before/after projections additionally require full case restoration.
"""
from initial_atomic_admission_sessions import PROJECTION


def explicit_edge_cases(qualification):
    base = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
    ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts;'

    def invoke(body):
        return 'DO $$ DECLARE o UUID; a UUID; result JSONB; BEGIN ' + ids + body + ' END $$;'

    def execute(label, sql, expected=None):
        snapshot = "SELECT " + PROJECTION + ";"
        before = qualification.execute(label + '_before', snapshot)
        result = qualification.execute(label, sql, expected)
        after = qualification.execute(label + '_after', snapshot)
        if before != after:
            qualification.record['case_restoration_failed'] = label
            qualification.save()
            raise RuntimeError('rollback case changed original projection')
        qualification.record.setdefault('restored_cases', []).append(label)
        qualification.save()
        return result

    qualification.execute('single_absent_admission', """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>1
 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage)
 THEN RAISE EXCEPTION USING ERRCODE='ZX512'; END IF;
END $$;
""")
    relations = ['internal.initial_preparation_admission_receipts', 'internal.initial_analysis_submissions', 'internal.initial_analysis_preparation_intents', 'internal.initial_analysis_admissions', 'internal.initial_analysis_lifecycle_fences', 'internal.initial_analysis_cancellations', 'internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts']
    projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations)) + ')'

    def denied(label, setup='', code='55000'):
        sql = base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + setup + ' b:=' + projection + ";BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,a);EXCEPTION WHEN SQLSTATE '" + code + "' THEN failed:=TRUE;END;RESET ROLE;IF NOT failed OR b IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX411';END IF;END $$;ROLLBACK;"
        execute(label, sql)

    def change(table, statement):
        return 'ALTER TABLE ' + table + ' DISABLE TRIGGER USER;' + statement + ';ALTER TABLE ' + table + ' ENABLE TRIGGER USER;'

    def precedence(label, setup, message):
        sql = base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + setup + ' b:=' + projection + ";BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,a);EXCEPTION WHEN SQLSTATE '55000' THEN failed:=(SQLERRM='" + message + "');END;RESET ROLE;IF NOT failed OR b IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX441';END IF;END $$;ROLLBACK;"
        execute(label, sql)
    execute('fixture_absent_credit_verified', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.complimentary_scan_usage) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE complimentary_client_scan_id IS NOT NULL) THEN RAISE EXCEPTION USING ERRCODE='ZX412';END IF;END $$;")
    for (table, column, value) in [('internal.initial_preparation_admission_receipts', 'admission_receipt_id', 'gen_random_uuid()'), ('internal.initial_analysis_admissions', 'funding_digest', "repeat('0',64)"), ('internal.initial_analysis_submissions', 'funding_snapshot', "'{}'::JSONB")]:
        denied('drift_' + table.rsplit('.', 1)[-1], change(table, 'UPDATE ' + table + ' SET ' + column + '=' + value + ' WHERE scan_id=a'))
    denied('paired_fences_without_receipt_or_admission', change('internal.initial_preparation_admission_receipts', 'DELETE FROM internal.initial_preparation_admission_receipts') + change('internal.initial_analysis_admissions', 'DELETE FROM internal.initial_analysis_admissions'))
    for (table, event) in [('internal.ai_quota_reservations', 'UPDATE'), ('internal.initial_analysis_lifecycle_fences', 'UPDATE'), ('internal.initial_analysis_submissions', 'DELETE'), ('internal.initial_analysis_preparation_intents', 'DELETE'), ('internal.initial_analysis_cancellations', 'INSERT'), ('internal.initial_cancellation_terminal_snapshot', 'DELETE')]:
        setup = "CREATE FUNCTION pg_temp.fail_c1() RETURNS TRIGGER LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION USING ERRCODE='ZX410'; END;$f$;CREATE TRIGGER zz_fail_c1 AFTER " + event + ' ON ' + table + ' FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.fail_c1();'
        denied('injected_' + table.rsplit('.', 1)[-1], setup, 'ZX410')
    for (lifecycle, dispatch) in [('dispatch_authorized', 'dispatch_already_authorized'), (None, 'dispatch_outcome_unknown')]:
        setup = change('internal.initial_analysis_lifecycle_fences', 'DELETE FROM internal.initial_analysis_lifecycle_fences' if lifecycle is None else "UPDATE internal.initial_analysis_lifecycle_fences SET state='" + lifecycle + "'")
        execute('conservative_' + str(lifecycle) + '_and_exact_replay', base + invoke(setup + "SET LOCAL ROLE service_role;result:=public.cancel_initial_analysis(o,a);IF result->>'dispatch' IS DISTINCT FROM '" + dispatch + "' OR result IS DISTINCT FROM public.cancel_initial_analysis(o,a) THEN RAISE EXCEPTION USING ERRCODE='ZX413';END IF;RESET ROLE;IF internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'reserved' OR refund_count<>0) THEN RAISE EXCEPTION USING ERRCODE='ZX414';END IF;UPDATE public.users SET id=id WHERE FALSE;") + 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
    execute('new_no_footprint_disabled_gate_denied', base + invoke('SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,gen_random_uuid());') + 'ROLLBACK;', '55000')
    execute('raw_lifecycle_original_guard_denies', base + invoke("UPDATE internal.initial_analysis_lifecycle_fences SET state='cancelled_pre_dispatch' WHERE scan_id=a;") + 'ROLLBACK;', '22023')
    execute('helpers_denied_without_stage', base + invoke("IF internal.initial_cancellation_quota_authorized(gen_random_uuid(),o,gen_random_uuid(),'refunded') OR internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch','sample') OR internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch','settle') OR internal.initial_cancellation_lifecycle_authorized('{}','{}') THEN RAISE EXCEPTION USING ERRCODE='ZX415';END IF;") + 'ROLLBACK;')
    denied('missing_admission_only_retained_receipt_paired_fences', change('internal.initial_analysis_admissions', 'DELETE FROM internal.initial_analysis_admissions'))
    live = 'DO $$ DECLARE o UUID;a UUID;q internal.ai_quota_reservations;s internal.initial_admitted_cancellation_staging;v JSONB;old_image JSONB;new_image JSONB;BEGIN ' + ids + 'INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id) VALUES(a,o);SELECT * INTO STRICT q FROM internal.ai_quota_reservations;'
    checks = "\n IF NOT internal.initial_cancellation_quota_authorized(q.id,o,q.lease_token,'refunded')\n OR internal.initial_cancellation_quota_authorized(gen_random_uuid(),o,q.lease_token,'refunded')\n OR internal.initial_cancellation_quota_authorized(q.id,gen_random_uuid(),q.lease_token,'refunded')\n OR internal.initial_cancellation_quota_authorized(q.id,o,gen_random_uuid(),'refunded')\n OR internal.initial_cancellation_quota_authorized(q.id,o,q.lease_token,'committed')\n OR internal.initial_cancellation_quota_authorized(q.id,o,q.lease_token,NULL)\n THEN RAISE EXCEPTION USING ERRCODE='ZX431';END IF;\n PERFORM internal.finalize_ai_quota_reservation_core(q.id,o,q.lease_token,'refunded');\n IF NOT internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch','sample')\n OR internal.initial_cancellation_credit_authorized(gen_random_uuid(),a,'cancelled_before_dispatch','sample')\n OR internal.initial_cancellation_credit_authorized(o,gen_random_uuid(),'cancelled_before_dispatch','sample')\n OR internal.initial_cancellation_credit_authorized(o,a,'other_failure','sample')\n OR internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch','settle')\n OR internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch',NULL)\n THEN RAISE EXCEPTION USING ERRCODE='ZX432';END IF;\n v:=internal.settle_complimentary_analysis(o,a,'cancelled_before_dispatch');\n PERFORM internal.advance_initial_cancellation_lifecycle(o,a,'cancelled_pre_dispatch','begin');\n SELECT to_jsonb(t) INTO STRICT old_image FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=a;\n new_image:=old_image||jsonb_build_object('state','cancelled_pre_dispatch');\n IF NOT internal.initial_cancellation_lifecycle_authorized(old_image,new_image)\n OR internal.initial_cancellation_lifecycle_authorized(old_image||jsonb_build_object('scan_id',gen_random_uuid()),new_image)\n OR internal.initial_cancellation_lifecycle_authorized(old_image,new_image||jsonb_build_object('state','cancelled_unknown'))\n THEN RAISE EXCEPTION USING ERRCODE='ZX433';END IF;\n "
    execute('live_original_owner_seams_accept_exact_and_reject_wrong_identity_phase_action', base + live + checks + 'END $$;ROLLBACK;')
    execute('live_partial_stage_cannot_commit', base + live + checks + 'END $$;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;', '55000')
    execute('live_stage_prestate_is_immutable', base + live + "UPDATE internal.initial_admitted_cancellation_staging SET prestate=jsonb_set(prestate,'{quota,lease_token}',to_jsonb(gen_random_uuid()::TEXT));END $$;ROLLBACK;", '55000')
    precedence('scan_deletion_precedes_positive_cancellation', 'INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES(a,o);', 'initial_analysis_deleted')
    setup = change('internal.initial_analysis_results', "INSERT INTO internal.initial_analysis_results(scan_id,owner_id,result_evidence_id,result_schema_version,result_snapshot,provenance_snapshot) VALUES(a,o,gen_random_uuid(),1,'{}','{}')") + change('internal.initial_analysis_completions', "INSERT INTO internal.initial_analysis_completions(scan_id,owner_id,result_evidence_id,receipt_version,receipt_snapshot) SELECT scan_id,owner_id,result_evidence_id,1,'{}'::JSONB FROM internal.initial_analysis_results WHERE scan_id=a")
    precedence('completed_receipt_precedes_positive_cancellation', setup, 'initial_analysis_already_complete')
    execute('absent_original_credit_is_noop_without_stage', base + invoke('result:=internal.settle_complimentary_analysis(o,a,\'cancelled_before_dispatch\');IF result IS DISTINCT FROM \'{"credit_released":false,"credit_consumed":false}\'::JSONB OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage) OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX416\';END IF;') + 'ROLLBACK;')
