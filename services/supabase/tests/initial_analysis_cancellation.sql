\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.admission_owner(owner_id UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',NOW(),NOW());
 INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
 INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
 INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;
CREATE FUNCTION pg_temp.admission_input() RETURNS JSONB LANGUAGE SQL AS $input$
 SELECT '{"schema_version":1,"route":"identify-describe","ordered_descriptions":["  Synthetic α / é / é\n\ttext  "],"media":[],"owner_timeline":[{"kind":"description","index":0}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null}'::JSONB;
$input$;
CREATE FUNCTION pg_temp.admit_initial(owner_id UUID,scan UUID,value JSONB DEFAULT pg_temp.admission_input()) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.admit_initial_analysis(owner_id,scan,internal.initial_canonical(value),internal.initial_digest('input',internal.initial_canonical(value)),
 (SELECT configuration_assets_digest FROM internal.initial_analysis_rollout WHERE singleton),repeat('a',64));
$$;

SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000d001');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000d002');
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'no activation');
SELECT extensions.ok(NOT has_table_privilege(r,t,p),'private lifecycle and cancellation data denied')
 FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['internal.initial_analysis_lifecycle_fences','internal.initial_analysis_cancellations']) t
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p;
SELECT extensions.ok(NOT has_function_privilege(r,'internal.cancel_initial_analysis(uuid,uuid)','EXECUTE'),'private settlement owner denied') FROM unnest(ARRAY['anon','authenticated','service_role']) r;
SELECT extensions.ok(NOT has_function_privilege(r,'public.cancel_initial_analysis(uuid,uuid)','EXECUTE'),'clients cannot call service cancellation') FROM unnest(ARRAY['anon','authenticated']) r;
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d100')$$,'55000','initial_analysis_unavailable','closed gate cannot claim empty UUID');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d101');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000d101'),'pending_pre_dispatch','fresh admission creates positive pending witness');
UPDATE internal.ai_quota_reservations SET lease_expires_at=now()-INTERVAL '1 hour' WHERE request_id='00000000-0000-4000-8000-00000000d101';
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
CREATE TEMP TABLE cancelled AS SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d101') value;
SELECT extensions.is((SELECT value FROM cancelled),'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}'::JSONB,'expired original lease can release only under exact non-dispatch proof');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d101'),'refunded','original quota refunded');
SELECT extensions.is((SELECT refund_count FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d101'),1,'only one refund');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d101'),'released','original complimentary usage released');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id='00000000-0000-4000-8000-00000000d101'),'private submission and derived binding erased');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id='00000000-0000-4000-8000-00000000d101'),'cancellation is not ordinary scan deletion');
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d101'),(SELECT value FROM cancelled),'lost acknowledgement exact replay while gate closed');
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d002','00000000-0000-4000-8000-00000000d101')$$,'P0002','initial_analysis_owner_unavailable','foreign receipt never disclosed');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_lifecycle_fences SET state='pending_pre_dispatch' WHERE scan_id='00000000-0000-4000-8000-00000000d101'$$,'22023','initial_analysis_lifecycle_immutable','terminal state cannot reset');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000d101'$$,'22023','initial_analysis_lifecycle_immutable','permanent state cannot prune');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000d101'$$,'22023','initial_analysis_storage_immutable','recovery receipt cannot disappear without stronger erasure');
SELECT extensions.is((SELECT strategy FROM internal.ghost_profile_merge_reference_policies WHERE source_schema='internal' AND source_table='initial_analysis_cancellations'),'preserve','merge holds cancellation receipts');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000d101',NULL,clock_timestamp());
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000d101'),'strong deletion erases private recovery association');
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d101')$$,'55000','initial_analysis_deleted','stronger deletion supersedes replay');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d102')->>'dispatch','dispatch_outcome_unknown','empty pre-admission cancellation does not infer legacy non-execution');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d102'),'empty cancellation allocates nothing');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d102')$$,'22023','initial_analysis_identity_conflict','cancelled UUID never admits');
-- Corrupt original binding: positive pending alone cannot refund.
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d103');
UPDATE internal.ai_quota_reservations SET policy_version=policy_version+1 WHERE request_id='00000000-0000-4000-8000-00000000d103';
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d103')->>'dispatch','dispatch_outcome_unknown','mismatched original funding holds unknown');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d103'),'reserved','unknown quota stays held');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d103'),'held','unknown complimentary stays held');
-- Old prepared admission without new positive witness (fixture only).
ALTER TABLE internal.initial_analysis_admissions DISABLE TRIGGER record_initial_pending_state;
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d104');
ALTER TABLE internal.initial_analysis_admissions ENABLE TRIGGER record_initial_pending_state;
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d104')->>'dispatch','dispatch_outcome_unknown','no witness never inferred/backfilled');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d104'),'reserved','old prepared funding remains held');
-- Raw pre-row erasure is privacy-safe, conservative and does not settle.
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d002','00000000-0000-4000-8000-00000000d105');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000d105',NULL,clock_timestamp());
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000d105'),'cancelled_unknown','raw stronger erasure records conservative terminal state');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d105'),'reserved','raw erasure does not refund');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id='00000000-0000-4000-8000-00000000d105'),'raw erasure has no receipt');
-- Force receipt failure after accounting: all prior work must roll back.
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d002','00000000-0000-4000-8000-00000000d106');
CREATE FUNCTION pg_temp.reject_cancellation() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION 'synthetic_cancellation_failure' USING ERRCODE='22023'; END; $$;
CREATE TRIGGER zz_reject_cancellation BEFORE INSERT ON internal.initial_analysis_cancellations FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_cancellation();
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d002','00000000-0000-4000-8000-00000000d106')$$,'22023','synthetic_cancellation_failure','failure propagates after attempted settlement');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d106'),'reserved','failed cancellation rolls back refund');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d106'),'held','failed cancellation rolls back credit release');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000d106'),'pending_pre_dispatch','failed cancellation rolls back state');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id='00000000-0000-4000-8000-00000000d106'),'failed cancellation retains original private proof');
DROP TRIGGER zz_reject_cancellation ON internal.initial_analysis_cancellations;
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000d002');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000d106'),'cancelled_pre_dispatch','supported account owner settles before user tuple deletion');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE owner_id='00000000-0000-4000-8000-00000000d002'),'account erase removes recovery receipts');
-- Saved scan precedence is no-mutation; cancellation cannot become deletion.
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000d003');
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d003','00000000-0000-4000-8000-00000000d107');
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES('00000000-0000-4000-8000-00000000d107','00000000-0000-4000-8000-00000000d003','failed_terminal','server_replay_limit_reached','replay_exhausted');
INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
 VALUES('00000000-0000-4000-8000-00000000d107','00000000-0000-4000-8000-00000000d003','{}',0.8,FALSE,'flash','private',TRUE);
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d003','00000000-0000-4000-8000-00000000d107')$$,'55000','initial_analysis_already_complete','saved scan cancels too late');
SELECT extensions.ok(EXISTS(SELECT 1 FROM public.scans WHERE id='00000000-0000-4000-8000-00000000d107' AND user_id='00000000-0000-4000-8000-00000000d003' AND NOT is_tombstoned),'saved scan untouched');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id='00000000-0000-4000-8000-00000000d107'),'too-late denial preserves evidence');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d107'),'reserved','too-late denial leaves funding untouched');
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d107')$$,'P0002','initial_analysis_owner_unavailable','foreign saved scan returns no completion detail');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized' WHERE scan_id='00000000-0000-4000-8000-00000000d107'$$,'22023','initial_analysis_lifecycle_immutable','no usable dispatch transition installed');
-- Cancelled-only receipt holds merge and terminal state fences late evidence.
SELECT extensions.throws_ok($$SELECT internal.assert_ghost_profile_merge_reference_preconditions('00000000-0000-4000-8000-00000000d001')$$,'55000','ghost_merge_preserved_reference_present: internal.initial_analysis_cancellations.owner_id','merge cannot erase or reparent cancellation receipt');
SELECT extensions.throws_ok($$INSERT INTO internal.initial_analysis_submissions VALUES('00000000-0000-4000-8000-00000000d102','00000000-0000-4000-8000-00000000d001','identify-describe',1,'{}','[]','{}','{}')$$,'55000','initial_analysis_cancelled','terminal fence rejects delayed private evidence');
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d106')$$,'P0002','initial_analysis_owner_unavailable','ownerless terminal state after account erasure gives generic denial');
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d105')$$,'55000','initial_analysis_deleted','raw erasure gives only generic deleted state');
-- Terminal namespace survives without a scan tombstone, including UUID aliases,
-- raw ownerless writers and identity-changing UPDATEs.
SELECT extensions.throws_ok(format('INSERT INTO public.%I(scan_id,user_id) VALUES(%L,%L)',table_name,scan,owner),
 '55000','initial_analysis_cancelled','terminal operation rejects generic job/intent identity')
 FROM unnest(ARRAY['scan_ingestion_jobs','scan_ingestion_intents']) table_name
 CROSS JOIN unnest(ARRAY['00000000-0000-4000-8000-00000000d102','{0000000000004000800000000000D102}']) scan
 CROSS JOIN unnest(ARRAY['00000000-0000-4000-8000-00000000d001',NULL]) owner;
SELECT extensions.throws_ok(format('INSERT INTO public.scans(id,user_id,image_storage_urls) VALUES(%L,%L,''{}'')','00000000-0000-4000-8000-00000000d102',owner),
 '55000','initial_analysis_cancelled','terminal operation rejects delayed saved scan')
 FROM unnest(ARRAY['00000000-0000-4000-8000-00000000d001',NULL]) owner;
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES('c1-legacy-job','00000000-0000-4000-8000-00000000d001');
INSERT INTO public.scan_ingestion_intents(scan_id,user_id) VALUES('c1-legacy-intent','00000000-0000-4000-8000-00000000d001');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_jobs SET scan_id='{0000000000004000800000000000D102}' WHERE scan_id='c1-legacy-job'$$,'55000','initial_analysis_cancelled','job rekey cannot bypass terminal guard');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_intents SET scan_id='{0000000000004000800000000000D102}' WHERE scan_id='c1-legacy-intent'$$,'55000','initial_analysis_cancelled','intent rekey cannot bypass terminal guard');
SELECT extensions.throws_ok($$UPDATE public.scans SET id='00000000-0000-4000-8000-00000000d102' WHERE id='00000000-0000-4000-8000-00000000d107'$$,'55000','initial_analysis_cancelled','scan rekey cannot bypass terminal guard');
-- Existing legacy aliases block first-writer admission and cancellation.
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES('{0000000000004000800000000000D108}','00000000-0000-4000-8000-00000000d001');
SELECT extensions.throws_ok($$SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d108')$$,'P0002','initial_analysis_owner_unavailable','aliased occupied identity cannot cancel');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d108')$$,'22023','initial_analysis_identity_conflict','aliased occupied identity cannot admit');
-- Contradictory generic work defeats a pending refund witness.
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d109');
INSERT INTO public.scan_ingestion_intents(scan_id,user_id) VALUES('{0000000000004000800000000000D109}','00000000-0000-4000-8000-00000000d001');
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,endpoint,retry_after) VALUES('{0000000000004000800000000000D109}','00000000-0000-4000-8000-00000000d001','failed_retryable','identify-multimodal',now());
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000d001','00000000-0000-4000-8000-00000000d109')->>'dispatch','dispatch_outcome_unknown','existing generic intent defeats non-dispatch proof');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d109'),'reserved','contradictory generic work holds quota');
UPDATE public.scan_ingestion_intents SET resumable=TRUE,inline_media_redacted=FALSE,request_payload='{}',endpoint='identify-multimodal'
 WHERE internal.source_child_uuid(scan_id)='00000000-0000-4000-8000-00000000d109';
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_replayable_scan_ingestion_jobs() WHERE internal.source_child_uuid(scan_id)='00000000-0000-4000-8000-00000000d109'),0,'batch replay excludes cancelled prepared jobs');
UPDATE public.scan_ingestion_intents SET replay_attempt_count=10 WHERE internal.source_child_uuid(scan_id)='00000000-0000-4000-8000-00000000d109';
SELECT extensions.lives_ok($$SELECT * FROM public.claim_replayable_scan_ingestion_jobs()$$,'over-budget prepared job skipped without legacy settlement');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d109'),'held','batch exhaustion cannot release unknown funding');
-- Legacy execution/recovery/settlement owners cannot operate on prepared IDs.
SELECT extensions.throws_ok(format(statement,scan,owner),'55000','initial_analysis_execution_required','legacy API cannot execute or settle prepared identity')
 FROM unnest(ARRAY[
 'SELECT public.begin_scan_ingestion(%L,%L,''identify-describe'',''{}'')',
 'SELECT public.claim_scan_ingestion_job(%L,%L,''identify-describe'')',
 'SELECT public.record_scan_ingestion_intent(%L,%L,''identify-describe'',''{}'')',
 'SELECT public.complete_scan_ingestion_finalization(%L,%L)',
 'SELECT public.complete_scan_ingestion_with_entitlement(%L,%L,''{}'',''{}'',''{}'')',
 'SELECT public.fail_scan_ingestion_terminal(%L,%L,''server_replay_limit_reached'',''synthetic'',''replay_exhausted'')',
 'SELECT public.recover_inline_scan_ingestion_completion(%L,%L)',
 'SELECT public.recover_stranded_scan_ingestion_attempt(%L,%L)'
 ]) statement
 CROSS JOIN (VALUES('00000000-0000-4000-8000-00000000d103','00000000-0000-4000-8000-00000000d001'),
 ('00000000-0000-4000-8000-00000000d107','00000000-0000-4000-8000-00000000d003')) identities(scan,owner);
SELECT extensions.throws_ok($$SELECT public.complete_scan_ingestion_finalization_with_response('00000000-0000-4000-8000-00000000d103','00000000-0000-4000-8000-00000000d001','{"success":true,"data":{"scan_id":"00000000-0000-4000-8000-00000000d103"}}','{}','{}')$$,
 '55000','initial_analysis_execution_required','response wrapper cannot bypass canonical finalization');
SELECT extensions.throws_ok($$SELECT public.recover_missing_owned_scan('00000000-0000-4000-8000-00000000d103','00000000-0000-4000-8000-00000000d001','{"id":"00000000-0000-4000-8000-00000000d103","user_id":"00000000-0000-4000-8000-00000000d001","image_storage_urls":[],"timestamp":"2026-10-11T00:00:00Z","geoprivacy":"private","ecology_type":"unknown","user_review_state":"unreviewed","ai_confidence_score":0.8,"is_invasive":false,"is_live_capture":true,"is_biological_subject":false,"user_confirmed_identification":false,"inference_tier":"flash"}')$$,
 '55000','initial_analysis_execution_required','owned client recovery cannot resurrect cancelled operation');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000d103'),'reserved','legacy rejection preserves unknown quota hold');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d103'),'held','legacy failure cannot release unknown complimentary allocation');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT * FROM internal.initial_analysis_cancellations$$,'42501',NULL,'actual service cannot read private receipt');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
