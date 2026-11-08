#!/usr/bin/env python3
"""Qualify inactive atomic admission/C1 in an explicitly disposable local database.

Use a fresh migration replay for EACH --suite invocation. Explicit includes the
reviewed rollback-only boundary cases before its committing cancellation. The
two terminal suites use three trusted complete admissions, and test synthetic
unknown/authorized projections without invoking a provider. No runtime S0 or
production qualification is implied. Receipts retain metadata only.
"""
import argparse
import json
from pathlib import Path
import uuid
from initial_atomic_admission_test_support import Qualification
from initial_atomic_admission_sessions import session_authority_cases
from initial_atomic_admission_explicit_edges import explicit_edge_cases
from initial_atomic_admission_cross_owner import cross_owner_cases
from initial_atomic_admission_recovery_order import recovery_order_cases
from initial_atomic_admission_counter_images import counter_image_cases
from initial_atomic_admission_counter_order import counter_order_cases
from initial_atomic_admission_ghost_order import ghost_order_cases
from initial_atomic_admission_resource import resource_cases
from initial_atomic_admission_historical_expiry import legacy_media_expiry_cases, historical_no_media_expiry_cases
from initial_atomic_admission_account_expiry import account_batch_cases, admitted_expiry_cases
from initial_atomic_admission_erasure_orders import scan_delete_order_cases, account_order_cases, registry_order_cases

def explicit_cases(qualification):
    execute = qualification.execute
    base = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
    ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts;'

    def invoke(body):
        return 'DO $$ DECLARE o UUID; a UUID; result JSONB; BEGIN ' + ids + body + ' END $$;'
    positive = invoke('\n SET LOCAL ROLE service_role;\n result:=public.cancel_initial_analysis(o,a);\n IF result IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX401\'; END IF;\n RESET ROLE;\n IF NOT internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)\n  OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents)\n  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>\'refunded\' OR refund_count<>1)\n  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters)\n  OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE state<>\'released\' OR settlement_reason<>\'cancelled_before_dispatch\')\n  OR EXISTS(SELECT 1 FROM internal.identification_invocations)\n  OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=a)<>\'cancelled_pre_dispatch\'\n THEN RAISE EXCEPTION USING ERRCODE=\'ZX402\'; END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(a);\n SET LOCAL ROLE service_role;\n')
    execute('actual_public_positive_rollback_deferred_service', base + positive + 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
    execute('public_positive_then_protected_zero_write_denied', base + positive + 'RESET ROLE;DELETE FROM public.users WHERE FALSE;ROLLBACK;', '55000')
    execute('generic_owner_stays_unknown_unfunded_and_seal_free', base + invoke("result:=internal.cancel_initial_analysis(o,a); IF result->>'dispatch'<>'dispatch_outcome_unknown' OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'reserved' OR refund_count<>0) THEN RAISE EXCEPTION USING ERRCODE='ZX403'; END IF; UPDATE public.users SET id=id WHERE FALSE;") + 'ROLLBACK;')
    execute('raw_original_quota_without_stage_denied', base + "DO $$ DECLARE q internal.ai_quota_reservations; BEGIN SELECT * INTO STRICT q FROM internal.ai_quota_reservations; PERFORM internal.finalize_ai_quota_reservation_core(q.id,q.user_id,q.lease_token,'refunded'); END $$;ROLLBACK;", '55000')
    execute('raw_original_credit_without_stage_denied', base + invoke("PERFORM internal.settle_complimentary_analysis(o,a,'cancelled_before_dispatch');") + 'ROLLBACK;', '55000')
    for role in ['anon', 'authenticated']:
        execute(role + '_public_endpoint_denied', base + invoke('SET LOCAL ROLE ' + role + ';PERFORM public.cancel_initial_analysis(o,a);') + 'ROLLBACK;', '42501')
    execute('service_cannot_call_private_compositor', base + invoke('SET LOCAL ROLE service_role;PERFORM internal.cancel_initial_analysis_explicit(o,a);') + 'ROLLBACK;', '42501')
    execute('wrong_owner_cannot_cancel', base + invoke('SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(gen_random_uuid(),a);') + 'ROLLBACK;', 'P0002')
    execute('missing_receipt_footprint_fails_closed', base + 'DO $$ DECLARE o UUID;a UUID;failed BOOLEAN:=FALSE;BEGIN ' + ids + "ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;DELETE FROM internal.initial_preparation_admission_receipts;ALTER TABLE internal.initial_preparation_admission_receipts ENABLE TRIGGER USER;BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,a);EXCEPTION WHEN SQLSTATE '55000' THEN failed:=TRUE; END;RESET ROLE;IF NOT failed OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'reserved' OR refund_count<>0) OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX404';END IF;END $$;ROLLBACK;")
    execute('actual_public_positive_commits_deferred_service', base + positive + 'COMMIT;')
    execute('fresh_session_exact_replay_no_second_refund', base + "DO $$ DECLARE c internal.initial_analysis_cancellations; result JSONB;BEGIN SELECT * INTO STRICT c FROM internal.initial_analysis_cancellations;SET LOCAL ROLE service_role;result:=public.cancel_initial_analysis(c.owner_id,c.scan_id);RESET ROLE;IF result IS DISTINCT FROM jsonb_build_object('version',1,'outcome','cancelled','dispatch',c.dispatch) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE refund_count<>1) OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.identification_invocations) THEN RAISE EXCEPTION USING ERRCODE='ZX405';END IF;END $$;COMMIT;")

def boundary_cases(qualification):
    execute = qualification.execute
    base = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
    ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts;'
    relations = ['public.users', 'public.scans', 'internal.initial_preparation_admission_receipts', 'internal.initial_analysis_submissions', 'internal.initial_analysis_preparation_intents', 'internal.initial_analysis_admissions', 'internal.initial_analysis_lifecycle_fences', 'internal.initial_analysis_cancellations', 'internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations', 'internal.initial_preparation_source_fences', 'internal.initial_analysis_media_allocation_fences', 'internal.initial_analysis_operation_fences', 'internal.initial_preparation_source_registry', 'internal.initial_analysis_media_registry', 'internal.initial_analysis_results', 'internal.initial_analysis_completions']
    projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations)) + ')'

    def saved(label, owner_expr, error, message):
        setup = 'INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture) VALUES(a,' + owner_expr + ",'{}',0.8,FALSE,'flash','private',TRUE);"
        execute(label, base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + 'a:=gen_random_uuid();' + setup + 'b:=' + projection + ";BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,a);EXCEPTION WHEN SQLSTATE '" + error + "' THEN IF SQLERRM<>'" + message + "' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed OR b IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX501';END IF;END $$;ROLLBACK;")
    execute('admitted_source_barrier_rejects_direct_saved_scan_insert', base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + 'b:=' + projection + ";BEGIN INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture) VALUES(a,o,'{}',0.8,FALSE,'flash','private',TRUE);EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_preparation_provider_blocked' THEN RAISE;END IF;failed:=TRUE;END;IF NOT failed OR b IS DISTINCT FROM " + projection + " THEN RAISE EXCEPTION USING ERRCODE='ZX505';END IF;END $$;ROLLBACK;")
    saved('matching_independent_saved_scan_denied', 'o', '55000', 'initial_analysis_already_complete')
    saved('foreign_independent_saved_scan_no_completion_disclosure', '(SELECT id FROM public.users WHERE id<>o LIMIT 1)', 'P0002', 'initial_analysis_owner_unavailable')
    for (name, path, value) in [('lease', '{quota,lease_token}', 'to_jsonb(gen_random_uuid()::TEXT)'), ('owner_epoch', '{owner_epoch,entitlement_version}', "to_jsonb((NEW.prestate#>>'{owner_epoch,entitlement_version}')::BIGINT+1)"), ('charges', '{charges}', "'[]'::JSONB")]:
        setup = "CREATE FUNCTION pg_temp.corrupt_captured() RETURNS TRIGGER LANGUAGE plpgsql AS $f$ BEGIN NEW.prestate:=jsonb_set(NEW.prestate,'" + path + "'," + value + ');RETURN NEW;END;$f$;CREATE TRIGGER zz_test_corrupt_captured BEFORE INSERT ON internal.initial_admitted_cancellation_staging FOR EACH ROW EXECUTE FUNCTION pg_temp.corrupt_captured();'
        body = 'DO $$ DECLARE o UUID;a UUID;q internal.ai_quota_reservations;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + 'SELECT * INTO STRICT q FROM internal.ai_quota_reservations WHERE original_analysis_id=a;INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id) VALUES(a,o);'
        body += "IF (SELECT prestate FROM internal.initial_admitted_cancellation_staging WHERE scan_id=a) IS NOT DISTINCT FROM internal.capture_initial_admitted_cancellation_prestate(o,a) THEN RAISE EXCEPTION USING ERRCODE='ZX502';END IF;"
        body += 'b:=' + projection + ";IF internal.initial_cancellation_quota_authorized(q.id,o,q.lease_token,'refunded') THEN RAISE EXCEPTION USING ERRCODE='ZX503';END IF;BEGIN PERFORM internal.finalize_ai_quota_reservation_core(q.id,o,q.lease_token,'refunded');EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_settlement_unavailable' THEN RAISE;END IF;failed:=TRUE;END;IF NOT failed OR b IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX504';END IF;END $$;ROLLBACK;"
        execute('trusted_corrupt_captured_' + name + '_cannot_authorize_refund', base + setup + body)

def terminal_cases(qualification):
    execute = qualification.execute
    base = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
    ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts;'
    relations = ['internal.initial_preparation_admission_receipts', 'internal.initial_analysis_submissions', 'internal.initial_analysis_preparation_intents', 'internal.initial_analysis_admissions', 'internal.initial_analysis_lifecycle_fences', 'internal.initial_analysis_cancellations', 'internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations', 'internal.initial_preparation_source_fences', 'internal.initial_analysis_media_allocation_fences', 'internal.initial_analysis_operation_fences', 'internal.initial_preparation_source_registry', 'internal.initial_analysis_media_registry', 'internal.initial_analysis_results', 'internal.initial_analysis_completions']
    projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations)) + ')'
    funding_projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations'])) + ')'

    def change(table, stmt):
        return 'ALTER TABLE ' + table + ' DISABLE TRIGGER USER;' + stmt + ';ALTER TABLE ' + table + ' ENABLE TRIGGER USER;'

    def replay(label, dispatch, setup='', error=None, message=None):
        ids = "SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_analysis_cancellations WHERE dispatch='" + dispatch + "';"
        call = 'SET LOCAL ROLE service_role;result:=public.cancel_initial_analysis(o,a);RESET ROLE;'
        if error:
            call = 'BEGIN ' + call + " EXCEPTION WHEN SQLSTATE '" + error + "' THEN failed:=TRUE;" + ("IF SQLERRM<>'" + message + "' THEN RAISE;END IF;" if message else '') + "END;RESET ROLE;IF NOT failed THEN RAISE EXCEPTION USING ERRCODE='ZX481';END IF;"
        else:
            call += "IF result IS DISTINCT FROM jsonb_build_object('version',1,'outcome','cancelled','dispatch','" + dispatch + "') THEN RAISE EXCEPTION USING ERRCODE='ZX482';END IF;"
        sql = base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;result JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + setup + ' b:=' + projection + ';' + call + ' IF b IS DISTINCT FROM ' + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX483';END IF;END $$;ROLLBACK;"
        execute(label, sql)
    for (dispatch, state) in [('dispatch_outcome_unknown', None), ('dispatch_already_authorized', 'dispatch_authorized'), ('dispatch_prevented', 'pending_pre_dispatch')]:
        ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts ORDER BY scan_id LIMIT 1;'
        setup = '' if state == 'pending_pre_dispatch' else change('internal.initial_analysis_lifecycle_fences', 'DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=a' if state is None else "UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized' WHERE scan_id=a")
        if state != 'pending_pre_dispatch':
            fault = "CREATE FUNCTION pg_temp.terminal_fault() RETURNS TRIGGER LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION USING ERRCODE='ZX490';END;$f$;CREATE TRIGGER test_terminal_fault AFTER INSERT ON internal.initial_analysis_cancellations FOR EACH ROW EXECUTE FUNCTION pg_temp.terminal_fault();"
            execute('late_fault_atomic_' + dispatch, base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + setup + fault + ' b:=' + projection + ";BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,a);EXCEPTION WHEN SQLSTATE 'ZX490' THEN failed:=TRUE;END;RESET ROLE;IF NOT failed OR b IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX491';END IF;END $$;ROLLBACK;")
        funding_check = '' if state == 'pending_pre_dispatch' else 'IF before_funding IS DISTINCT FROM ' + funding_projection + " THEN RAISE EXCEPTION USING ERRCODE='ZX492';END IF;"
        execute('commit_' + dispatch, base + 'DO $$ DECLARE o UUID;a UUID;result JSONB;before_funding JSONB;BEGIN ' + ids + setup + 'before_funding:=' + funding_projection + ';SET LOCAL ROLE service_role;result:=public.cancel_initial_analysis(o,a);RESET ROLE;' + funding_check + "IF result IS DISTINCT FROM jsonb_build_object('version',1,'outcome','cancelled','dispatch','" + dispatch + "') THEN RAISE EXCEPTION USING ERRCODE='ZX480';END IF;END $$;COMMIT;")
    execute('all_three_private_roots_erased_original_funding_classification_preserved', "DO $$ BEGIN IF (SELECT count(*) FROM internal.initial_analysis_cancellations)<>3 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='refunded' AND refund_count=1)<>1 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='reserved' AND refund_count=0)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX484';END IF;END $$;")
    for dispatch in ['dispatch_outcome_unknown', 'dispatch_already_authorized', 'dispatch_prevented']:
        replay('fresh_exact_' + dispatch, dispatch)
        replay('missing_lifecycle_' + dispatch, dispatch, 'ALTER TABLE internal.initial_analysis_cancellations DROP CONSTRAINT initial_analysis_cancellations_scan_id_fkey;' + change('internal.initial_analysis_lifecycle_fences', 'DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=a'), '55000', 'initial_analysis_unavailable')
        replay('mismatched_lifecycle_' + dispatch, dispatch, change('internal.initial_analysis_lifecycle_fences', "UPDATE internal.initial_analysis_lifecycle_fences SET state='pending_pre_dispatch' WHERE scan_id=a"), '55000', 'initial_analysis_unavailable')
        replay('missing_receipt_' + dispatch, dispatch, change('internal.initial_analysis_cancellations', 'DELETE FROM internal.initial_analysis_cancellations WHERE scan_id=a'), 'P0002', 'initial_analysis_owner_unavailable')
        replay('deleted_precedes_' + dispatch, dispatch, 'INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES(a,o);', '55000', 'initial_analysis_deleted')
        replay('wrong_owner_' + dispatch, dispatch, 'SELECT id INTO STRICT o FROM public.users WHERE id<>o LIMIT 1;', 'P0002', 'initial_analysis_owner_unavailable')

def held_terminal_cases(qualification):
    execute = qualification.execute
    base = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
    ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts;'
    relations = ['internal.initial_preparation_admission_receipts', 'internal.initial_analysis_submissions', 'internal.initial_analysis_preparation_intents', 'internal.initial_analysis_admissions', 'internal.initial_analysis_lifecycle_fences', 'internal.initial_analysis_cancellations', 'internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations', 'internal.initial_preparation_source_fences', 'internal.initial_analysis_media_allocation_fences', 'internal.initial_analysis_operation_fences', 'internal.initial_preparation_source_registry', 'internal.initial_analysis_media_registry', 'internal.initial_analysis_results', 'internal.initial_analysis_completions', 'public.users']
    projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations)) + ')'
    funding_projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations', 'public.users'])) + ')'

    def change(table, stmt):
        return 'ALTER TABLE ' + table + ' DISABLE TRIGGER USER;' + stmt + ';ALTER TABLE ' + table + ' ENABLE TRIGGER USER;'

    def replay(label, dispatch, setup='', error=None, message=None):
        ids = "SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_analysis_cancellations WHERE dispatch='" + dispatch + "';"
        call = 'SET LOCAL ROLE service_role;result:=public.cancel_initial_analysis(o,a);RESET ROLE;'
        if error:
            call = 'BEGIN ' + call + " EXCEPTION WHEN SQLSTATE '" + error + "' THEN failed:=TRUE;" + ("IF SQLERRM<>'" + message + "' THEN RAISE;END IF;" if message else '') + "END;RESET ROLE;IF NOT failed THEN RAISE EXCEPTION USING ERRCODE='ZX481';END IF;"
        else:
            call += "IF result IS DISTINCT FROM jsonb_build_object('version',1,'outcome','cancelled','dispatch','" + dispatch + "') THEN RAISE EXCEPTION USING ERRCODE='ZX482';END IF;"
        sql = base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;result JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + setup + ' b:=' + projection + ';' + call + ' IF b IS DISTINCT FROM ' + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX483';END IF;END $$;ROLLBACK;"
        execute(label, sql)
    execute('held_seed_has_three_original_allocations', "DO $$ BEGIN IF (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='held' AND settled_at IS NULL)<>3 THEN RAISE EXCEPTION USING ERRCODE='ZX493';END IF;END $$;")
    for (dispatch, state) in [('dispatch_outcome_unknown', None), ('dispatch_already_authorized', 'dispatch_authorized'), ('dispatch_prevented', 'pending_pre_dispatch')]:
        ids = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts ORDER BY scan_id LIMIT 1;'
        setup = '' if state == 'pending_pre_dispatch' else change('internal.initial_analysis_lifecycle_fences', 'DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=a' if state is None else "UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized' WHERE scan_id=a")
        if state != 'pending_pre_dispatch':
            fault = "CREATE FUNCTION pg_temp.terminal_fault() RETURNS TRIGGER LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION USING ERRCODE='ZX490';END;$f$;CREATE TRIGGER test_terminal_fault AFTER INSERT ON internal.initial_analysis_cancellations FOR EACH ROW EXECUTE FUNCTION pg_temp.terminal_fault();"
            execute('late_fault_atomic_' + dispatch, base + 'DO $$ DECLARE o UUID;a UUID;b JSONB;failed BOOLEAN:=FALSE;BEGIN ' + ids + setup + fault + ' b:=' + projection + ";BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(o,a);EXCEPTION WHEN SQLSTATE 'ZX490' THEN failed:=TRUE;END;RESET ROLE;IF NOT failed OR b IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX491';END IF;END $$;ROLLBACK;")
        funding_check = '' if state == 'pending_pre_dispatch' else 'IF before_funding IS DISTINCT FROM ' + funding_projection + " THEN RAISE EXCEPTION USING ERRCODE='ZX492';END IF;"
        owner_check = "IF (SELECT to_jsonb(u) FROM public.users u WHERE id=o) IS DISTINCT FROM (before_owner||jsonb_build_object('complimentary_entitlement_epoch',(before_owner->>'complimentary_entitlement_epoch')::BIGINT+1,'entitlement_version',(before_owner->>'entitlement_version')::BIGINT+1)) THEN RAISE EXCEPTION USING ERRCODE='ZX495';END IF;" if state == 'pending_pre_dispatch' else ''
        execute('commit_' + dispatch, base + 'DO $$ DECLARE o UUID;a UUID;result JSONB;before_funding JSONB;before_owner JSONB;BEGIN ' + ids + setup + 'SELECT to_jsonb(u) INTO STRICT before_owner FROM public.users u WHERE id=o;before_funding:=' + funding_projection + ';SET LOCAL ROLE service_role;result:=public.cancel_initial_analysis(o,a);RESET ROLE;' + funding_check + owner_check + "IF result IS DISTINCT FROM jsonb_build_object('version',1,'outcome','cancelled','dispatch','" + dispatch + "') THEN RAISE EXCEPTION USING ERRCODE='ZX480';END IF;END $$;COMMIT;")
    execute('all_three_private_roots_erased_original_funding_classification_preserved', "DO $$ BEGIN IF (SELECT count(*) FROM internal.initial_analysis_cancellations)<>3 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='refunded' AND refund_count=1)<>1 OR (SELECT count(*) FROM internal.ai_quota_reservations WHERE state='reserved' AND refund_count=0)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX484';END IF;END $$;")
    execute('held_terminal_retains_two_and_releases_prevented_once', "DO $$ BEGIN IF (SELECT count(*) FROM internal.complimentary_scan_usage)<>3 OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='held' AND settled_at IS NULL)<>2 OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='released' AND settlement_reason='cancelled_before_dispatch' AND settled_at IS NOT NULL)<>1 OR (SELECT count(*) FROM internal.initial_analysis_cancellations c JOIN internal.complimentary_scan_usage u ON u.client_scan_id=c.scan_id AND u.user_id=c.owner_id)<>3 OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations c JOIN internal.complimentary_scan_usage u ON u.client_scan_id=c.scan_id AND u.user_id=c.owner_id WHERE CASE WHEN c.dispatch='dispatch_prevented' THEN u.state IS DISTINCT FROM 'released' OR u.settlement_reason IS DISTINCT FROM 'cancelled_before_dispatch' OR u.settled_at IS NULL OR u.updated_at IS DISTINCT FROM u.settled_at ELSE u.state IS DISTINCT FROM 'held' OR u.settled_at IS NOT NULL OR u.settlement_reason IS NOT NULL END) THEN RAISE EXCEPTION USING ERRCODE='ZX494';END IF;END $$;")
    for dispatch in ['dispatch_outcome_unknown', 'dispatch_already_authorized', 'dispatch_prevented']:
        replay('fresh_exact_' + dispatch, dispatch)
        replay('missing_lifecycle_' + dispatch, dispatch, 'ALTER TABLE internal.initial_analysis_cancellations DROP CONSTRAINT initial_analysis_cancellations_scan_id_fkey;' + change('internal.initial_analysis_lifecycle_fences', 'DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=a'), '55000', 'initial_analysis_unavailable')
        replay('mismatched_lifecycle_' + dispatch, dispatch, change('internal.initial_analysis_lifecycle_fences', "UPDATE internal.initial_analysis_lifecycle_fences SET state='pending_pre_dispatch' WHERE scan_id=a"), '55000', 'initial_analysis_unavailable')
        replay('missing_receipt_' + dispatch, dispatch, change('internal.initial_analysis_cancellations', 'DELETE FROM internal.initial_analysis_cancellations WHERE scan_id=a'), 'P0002', 'initial_analysis_owner_unavailable')
        replay('deleted_precedes_' + dispatch, dispatch, 'INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES(a,o);', '55000', 'initial_analysis_deleted')
        replay('wrong_owner_' + dispatch, dispatch, 'SELECT id INTO STRICT o FROM public.users WHERE id<>o LIMIT 1;', 'P0002', 'initial_analysis_owner_unavailable')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disposable-container", required=True)
    parser.add_argument("--evidence-directory", required=True)
    parser.add_argument("--replay-manifest", required=True)
    parser.add_argument("--suite", choices=["explicit", "terminal", "terminal-held", "session-authority", "explicit-edges", "cross-owner", "recovery-order", "counter-images", "counter-order", "scan-delete-order", "account-order", "registry-order", "ghost-order", "account-batch", "admitted-expiry", "legacy-media-expiry", "historical-no-media-expiry", "resource"], required=True)
    args = parser.parse_args()
    qualification = None
    bootstrap_path = None
    bootstrap = {"suite": args.suite, "passed": False, "phase": "bootstrap"}
    try:
        directory = Path(args.evidence_directory).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        bootstrap_path = directory / (args.suite + "-bootstrap-" + uuid.uuid4().hex + ".json")
        bootstrap_path.write_text(json.dumps(bootstrap, indent=2) + "\n")
        qualification = Qualification(args.disposable_container, args.evidence_directory, args.suite, args.replay_manifest)
        if args.suite not in ("recovery-order", "counter-images", "counter-order", "scan-delete-order", "account-order", "registry-order", "ghost-order", "account-batch", "admitted-expiry", "legacy-media-expiry", "historical-no-media-expiry", "resource"):
            qualification.seed(count=1 if args.suite in ("explicit", "session-authority", "explicit-edges", "cross-owner") else 3, held=args.suite not in ("terminal", "explicit-edges"))
        if args.suite == "explicit":
            boundary_cases(qualification)
            explicit_cases(qualification)
        elif args.suite == "terminal":
            terminal_cases(qualification)
        elif args.suite == "terminal-held":
            held_terminal_cases(qualification)
        elif args.suite == "session-authority":
            session_authority_cases(qualification)
        elif args.suite == "explicit-edges":
            explicit_edge_cases(qualification)
        elif args.suite == "cross-owner":
            cross_owner_cases(qualification)
        elif args.suite == "recovery-order":
            recovery_order_cases(qualification)
        elif args.suite == "counter-images":
            counter_image_cases(qualification)
        elif args.suite == "counter-order":
            counter_order_cases(qualification)
        elif args.suite == "scan-delete-order":
            scan_delete_order_cases(qualification)
        elif args.suite == "account-order":
            account_order_cases(qualification)
        elif args.suite == "registry-order":
            registry_order_cases(qualification)
        elif args.suite == "ghost-order":
            ghost_order_cases(qualification)
        elif args.suite == "account-batch":
            account_batch_cases(qualification)
        elif args.suite == "admitted-expiry":
            admitted_expiry_cases(qualification)
        elif args.suite == "legacy-media-expiry":
            legacy_media_expiry_cases(qualification)
        elif args.suite == "historical-no-media-expiry":
            historical_no_media_expiry_cases(qualification)
        else:
            resource_cases(qualification)
        qualification.finish()
        bootstrap.update(passed=True, phase="complete", receipt=qualification.path.name)
        bootstrap_path.write_text(json.dumps(bootstrap, indent=2) + "\n")
        print("PASS " + args.suite, flush=True)
    except Exception as error:
        if bootstrap_path is not None:
            bootstrap["error_category"] = type(error).__name__
            bootstrap_path.write_text(json.dumps(bootstrap, indent=2) + "\n")
        if qualification is not None:
            qualification.record["error_category"] = type(error).__name__
            qualification.save()
        if qualification is not None:
            try:
                qualification.execute("restore_disabled_gate_after_failure", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            except Exception:
                qualification.record["gate_restore_failed"] = True
                qualification.save()
        print("FAIL " + args.suite + ": " + type(error).__name__, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
