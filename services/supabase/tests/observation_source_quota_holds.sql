\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Synthetic object','is_biological_subject',FALSE,
            'is_live_capture',TRUE,'confidence_score',0.8,'blur_score',0.2,'colors','[]'::JSONB,
            'estimated_size_cm',NULL,'inference_tier','flash','pet_identification',NULL,'candidates',NULL,
            'image_quality',NULL,'ai_reasoning','Synthetic fixture.','extracted_visual_traits','[]'::JSONB),
        'evidence_manifest','{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation."}}}]}'::JSONB);
$$;
CREATE FUNCTION pg_temp.seed_history_append(owner_id UUID, observation UUID, permit_initial BOOLEAN DEFAULT TRUE)
RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
    VALUES(observation,owner_id,'{}',0.8,FALSE,'flash','private',TRUE);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(observation,permit_initial);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;
END;
$$;

CREATE FUNCTION pg_temp.source_input(observation UUID,source UUID,child UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',3,'observation_id',observation,'analysis_id',child,'source_analysis_id',source,
 'request_digest',repeat('a',64),'entitlement_protocol',3,'identification_protocol',6,'history_protocol',9,'expected_processor_permission','google_gemini',
 'evidence_manifest',jsonb_build_object('schema_version',3,'items',jsonb_build_array(jsonb_build_object('kind','audio',
 'media_id','00000000-0000-4000-8000-00000000f999','content_type','audio/wav','byte_count',46,'sha256',repeat('b',64)))));
$$;
CREATE FUNCTION pg_temp.store_source(owner_id UUID,observation UUID,source UUID,child UUID,occupy BOOLEAN DEFAULT TRUE) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE input JSONB:=pg_temp.source_input(observation,source,child);
BEGIN
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,owner_id,observation,source,input,1,internal.observation_source_fingerprint(input));
 IF occupy THEN
 INSERT INTO internal.observation_analysis_source_occupancy(owner_id,observation_id,source_analysis_id,analysis_id) VALUES(owner_id,observation,source,child);
 END IF;
END;
$$;
CREATE FUNCTION pg_temp.seed_funded_history(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    PERFORM pg_temp.seed_history_append(owner_id,observation);
    INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
    INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
    INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;

CREATE FUNCTION pg_temp.admission_input(parent UUID,source UUID,child UUID,media UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.source_input(parent,source,child) || jsonb_build_object('schema_version',version,'history_protocol',CASE version WHEN 2 THEN 8 ELSE 9 END,
 'evidence_manifest',jsonb_build_object('schema_version',version,'items',jsonb_build_array(jsonb_build_object('kind',CASE version WHEN 2 THEN 'image' ELSE 'audio' END,'media_id',media,'content_type',CASE version WHEN 2 THEN 'image/jpeg' ELSE 'audio/wav' END,'byte_count',46,'sha256',repeat('b',64)))));
$$;
CREATE FUNCTION pg_temp.seed_bound_admission(owner_id UUID,parent UUID,source UUID,child UUID,media UUID,version INTEGER) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE input JSONB:=pg_temp.admission_input(parent,source,child,media,version); receipt JSONB;
BEGIN
 PERFORM pg_temp.seed_funded_history(owner_id,parent);
 PERFORM internal.append_observation_analysis(owner_id,pg_temp.history_append_request(parent,source));
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,owner_id,parent,source,input,1,internal.observation_source_fingerprint(input));
 INSERT INTO internal.observation_analysis_source_occupancy VALUES(owner_id,parent,source,child);
 IF version=2 THEN
  receipt:=(public.reserve_owned_observation_evidence_cohort(owner_id,parent,child,internal.observation_source_cohort_items(input,2)))->0;
 ELSE receipt:=public.reserve_owned_observation_audio_evidence_cohort(owner_id,parent,child,media,46,repeat('b',64)); END IF;
 PERFORM internal.complete_observation_evidence(owner_id,parent,child,media,(receipt->>'object_id')::UUID);
 RETURN input;
END;
$$;
CREATE FUNCTION pg_temp.admit_bound(owner_id UUID,input JSONB) RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
 IF input->'schema_version'='2'::JSONB THEN RETURN internal.admit_protected_observation_analysis(owner_id,input,repeat('a',64)); END IF;
 RETURN internal.admit_audio_observation_analysis(owner_id,input,repeat('a',64));
END;
$$;

UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE,audio_analysis_enabled=TRUE,execution_retirement_api_enabled=TRUE;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);

CREATE TEMP TABLE input_2 AS SELECT pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000d102','00000000-0000-4000-8000-00000000d112','00000000-0000-4000-8000-00000000d122','00000000-0000-4000-8000-00000000d132','00000000-0000-4000-8000-00000000d142',2) value;
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000d102',(SELECT value FROM input_2));
CREATE TEMP TABLE quota_2 AS SELECT id,lease_token FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d132';
SELECT set_config('merian.observation_analysis_provider','00000000-0000-4000-8000-00000000d102:00000000-0000-4000-8000-00000000d132',TRUE);
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((SELECT id FROM quota_2),'00000000-0000-4000-8000-00000000d102',(SELECT lease_token FROM quota_2),'committed')$$,'55000','analysis_history_retirement_required','V2 forged provider context cannot finalize committed');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((SELECT id FROM quota_2),'00000000-0000-4000-8000-00000000d102',(SELECT lease_token FROM quota_2),'failed')$$,'55000','analysis_history_retirement_required','V2 forged provider context cannot finalize failed');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((SELECT id FROM quota_2),'00000000-0000-4000-8000-00000000d102',(SELECT lease_token FROM quota_2),'refunded')$$,'55000','analysis_history_retirement_required','V2 forged provider context cannot finalize refunded');

SELECT extensions.throws_ok($$SELECT internal.fail_observation_analysis('00000000-0000-4000-8000-00000000d102','00000000-0000-4000-8000-00000000d112','00000000-0000-4000-8000-00000000d132',(SELECT lease_token FROM quota_2),'cancelled_before_dispatch','{}')$$,'55000','analysis_history_retirement_required','V2 generic cancellation holds');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000d102',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000d162','observation_id','00000000-0000-4000-8000-00000000d112','analysis_id','00000000-0000-4000-8000-00000000d132','source_analysis_id','00000000-0000-4000-8000-00000000d122','request_digest',repeat('a',64)),9)$$,'55000','analysis_history_retirement_required','V2 source retirement remains held');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d132'$$,'55000','analysis_history_retirement_required','V2 live-parent intent deletion is not erasure proof');
INSERT INTO internal.ai_quota_reservations SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,to_jsonb(q)||jsonb_build_object('id','00000000-0000-4000-8000-00000000d152','request_id','00000000-0000-4000-8000-00000000d152','original_analysis_id',NULL))).* FROM internal.ai_quota_reservations q WHERE q.id=(SELECT id FROM quota_2);
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE id IN ('00000000-0000-4000-8000-00000000d152',(SELECT id FROM quota_2));
SELECT internal.refund_expired_ai_quota_reservations(1000);
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT id FROM quota_2)),'reserved','V2 generic expiry holds bound quota');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id='00000000-0000-4000-8000-00000000d152'),'refunded','V2 unrelated expiry cleanup continues');
-- Superuser-only old terminal rows exercise the pruning exclusion.
UPDATE internal.ai_quota_reservations SET state='failed',updated_at=clock_timestamp()-INTERVAL '40 days' WHERE id=(SELECT id FROM quota_2);
UPDATE internal.ai_quota_reservations SET updated_at=clock_timestamp()-INTERVAL '40 days' WHERE id='00000000-0000-4000-8000-00000000d152';
SELECT internal.prune_ai_quota_state();
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE id=(SELECT id FROM quota_2)),1::BIGINT,'V2 generic pruning retains bound proof');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE id='00000000-0000-4000-8000-00000000d152'),0::BIGINT,'V2 unrelated pruning continues');
UPDATE internal.ai_quota_reservations SET state='reserved',updated_at=clock_timestamp() WHERE id=(SELECT id FROM quota_2);
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000d132'),1::BIGINT,'V2 accounting hold never releases occupancy');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d112','00000000-0000-4000-8000-00000000d102');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT id FROM quota_2)), 'refunded','V2 deletion refunds proven unused work');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d132'),0::BIGINT,'V2 deletion still erases intent');

CREATE TEMP TABLE input_3 AS SELECT pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000d103','00000000-0000-4000-8000-00000000d113','00000000-0000-4000-8000-00000000d123','00000000-0000-4000-8000-00000000d133','00000000-0000-4000-8000-00000000d143',3) value;
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000d103',(SELECT value FROM input_3));
CREATE TEMP TABLE quota_3 AS SELECT id,lease_token FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d133';
SELECT set_config('merian.observation_analysis_provider','00000000-0000-4000-8000-00000000d103:00000000-0000-4000-8000-00000000d133',TRUE);
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((SELECT id FROM quota_3),'00000000-0000-4000-8000-00000000d103',(SELECT lease_token FROM quota_3),'committed')$$,'55000','analysis_history_retirement_required','V3 forged provider context cannot finalize committed');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((SELECT id FROM quota_3),'00000000-0000-4000-8000-00000000d103',(SELECT lease_token FROM quota_3),'failed')$$,'55000','analysis_history_retirement_required','V3 forged provider context cannot finalize failed');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((SELECT id FROM quota_3),'00000000-0000-4000-8000-00000000d103',(SELECT lease_token FROM quota_3),'refunded')$$,'55000','analysis_history_retirement_required','V3 forged provider context cannot finalize refunded');

SELECT extensions.throws_ok($$SELECT internal.fail_observation_analysis('00000000-0000-4000-8000-00000000d103','00000000-0000-4000-8000-00000000d113','00000000-0000-4000-8000-00000000d133',(SELECT lease_token FROM quota_3),'cancelled_before_dispatch','{}')$$,'55000','analysis_history_retirement_required','V3 generic cancellation holds');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000d103',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000d163','observation_id','00000000-0000-4000-8000-00000000d113','analysis_id','00000000-0000-4000-8000-00000000d133','source_analysis_id','00000000-0000-4000-8000-00000000d123','request_digest',repeat('a',64)),10)$$,'55000','analysis_history_retirement_required','V3 source retirement remains held');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d133'$$,'55000','analysis_history_retirement_required','V3 live-parent intent deletion is not erasure proof');
INSERT INTO internal.ai_quota_reservations SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,to_jsonb(q)||jsonb_build_object('id','00000000-0000-4000-8000-00000000d153','request_id','00000000-0000-4000-8000-00000000d153','original_analysis_id',NULL))).* FROM internal.ai_quota_reservations q WHERE q.id=(SELECT id FROM quota_3);
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE id IN ('00000000-0000-4000-8000-00000000d153',(SELECT id FROM quota_3));
SELECT internal.refund_expired_ai_quota_reservations(1000);
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT id FROM quota_3)),'reserved','V3 generic expiry holds bound quota');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id='00000000-0000-4000-8000-00000000d153'),'refunded','V3 unrelated expiry cleanup continues');
-- Superuser-only old terminal rows exercise the pruning exclusion.
UPDATE internal.ai_quota_reservations SET state='failed',updated_at=clock_timestamp()-INTERVAL '40 days' WHERE id=(SELECT id FROM quota_3);
UPDATE internal.ai_quota_reservations SET updated_at=clock_timestamp()-INTERVAL '40 days' WHERE id='00000000-0000-4000-8000-00000000d153';
SELECT internal.prune_ai_quota_state();
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE id=(SELECT id FROM quota_3)),1::BIGINT,'V3 generic pruning retains bound proof');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE id='00000000-0000-4000-8000-00000000d153'),0::BIGINT,'V3 unrelated pruning continues');
UPDATE internal.ai_quota_reservations SET state='reserved',updated_at=clock_timestamp() WHERE id=(SELECT id FROM quota_3);
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000d133'),1::BIGINT,'V3 accounting hold never releases occupancy');
UPDATE internal.observation_analysis_intents SET invocation_id='00000000-0000-4000-8000-00000000d199' WHERE analysis_id='00000000-0000-4000-8000-00000000d133';
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d113','00000000-0000-4000-8000-00000000d103');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT id FROM quota_3)), 'reserved','V3 deletion does not refund uncertain work');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d133'),0::BIGINT,'V3 deletion still erases intent');
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000d104',pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000d104','00000000-0000-4000-8000-00000000d114','00000000-0000-4000-8000-00000000d124','00000000-0000-4000-8000-00000000d134','00000000-0000-4000-8000-00000000d144',2));
UPDATE internal.observation_analysis_intents SET terminal_reason='synthetic_terminal' WHERE analysis_id='00000000-0000-4000-8000-00000000d134';
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d114','00000000-0000-4000-8000-00000000d104');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d134'),'reserved','tampered terminal evidence prevents deletion refund 4');
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000d105',pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000d105','00000000-0000-4000-8000-00000000d115','00000000-0000-4000-8000-00000000d125','00000000-0000-4000-8000-00000000d135','00000000-0000-4000-8000-00000000d145',2));
UPDATE internal.observation_analysis_intents SET provider_usage='{}'::JSONB WHERE analysis_id='00000000-0000-4000-8000-00000000d135';
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d115','00000000-0000-4000-8000-00000000d105');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d135'),'reserved','tampered terminal evidence prevents deletion refund 5');
SELECT * FROM extensions.finish();
ROLLBACK;
