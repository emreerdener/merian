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

SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'source validation unavailable to API roles')
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY['internal.lock_owned_observation_source(uuid,uuid,uuid)','internal.lock_owned_observation_source_binding(uuid,uuid,uuid,jsonb)']) signature;
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121'));
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e102',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122'));
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131',TRUE);
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e132',FALSE);
SELECT extensions.lives_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131'))$$,'exact immutable audio binding accepted');
SELECT extensions.is((internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131'))).input_snapshot,pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131'),'returns exact saved input');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131'))$$,'P0002','analysis_history_not_found','owner check precedes binding');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131','{}'::JSONB)$$,'P0002','analysis_history_not_found','owner check precedes malformed input');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131'))$$,'P0002','analysis_history_not_found','cross parent denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e133',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e133'))$$,'22023','analysis_history_operation_conflict','missing binding denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e132',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e132'))$$,'22023','analysis_history_operation_conflict','immutable binding without occupancy denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e122','00000000-0000-4000-8000-00000000e131'))$$,'22023','analysis_history_operation_conflict','cross observation source denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e132'))$$,'22023','analysis_history_operation_conflict','cross child payload denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131') || jsonb_build_object('request_digest',repeat('c',64)))$$,'22023','analysis_history_operation_conflict','changed digest denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131','{}'::JSONB)$$,'22023','invalid_analysis_history','invalid input denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131') || jsonb_build_object('source_analysis_id',NULL))$$,'22023','invalid_analysis_history','source-less request denied');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131') || jsonb_build_object('schema_version',1))$$,'22023','invalid_analysis_history','legacy request not fresh binding proof');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE observation_id='00000000-0000-4000-8000-00000000e111'),2::BIGINT,'validation does not mutate binding history');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE observation_id='00000000-0000-4000-8000-00000000e111'),1::BIGINT,'validation never acquires occupancy');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e131'),0::BIGINT,'validation does not fund work');
-- A newly appended, nonselected result is also a valid source.
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e124','00000000-0000-4000-8000-00000000e121'));
-- InputV2 uses its original photo profile and exact request; no upgrade/rewrite.
CREATE FUNCTION pg_temp.photo_source_input() RETURNS JSONB LANGUAGE SQL AS $$
SELECT jsonb_set(pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e124','00000000-0000-4000-8000-00000000e134')
 || '{"schema_version":2,"history_protocol":8}'::JSONB,'{evidence_manifest}',
 '{"schema_version":2,"items":[{"kind":"image","media_id":"00000000-0000-4000-8000-00000000e199","content_type":"image/jpeg","byte_count":100,"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'::JSONB);
$$;
INSERT INTO internal.observation_analysis_source_bindings VALUES(
'00000000-0000-4000-8000-00000000e134','00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e124',pg_temp.photo_source_input(),1,internal.observation_source_fingerprint(pg_temp.photo_source_input()));
INSERT INTO internal.observation_analysis_source_occupancy VALUES(
'00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e124','00000000-0000-4000-8000-00000000e134');
SELECT extensions.lives_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e134',pg_temp.photo_source_input())$$,'exact photo input with historical nonselected source accepted');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e101');
SELECT extensions.throws_ok($$SELECT internal.lock_owned_observation_source_binding('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131',pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131'))$$,'P0002','analysis_history_not_found','deletion wins over saved exact input');
SELECT * FROM extensions.finish();
ROLLBACK;
