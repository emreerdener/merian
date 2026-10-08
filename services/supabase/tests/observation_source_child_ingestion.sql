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

SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121'));
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131',FALSE);
SELECT extensions.is(internal.source_child_uuid('{00000000-0000-4000-8000-00000000E131}'),'00000000-0000-4000-8000-00000000e131'::UUID,'UUID aliases normalize without rewriting legacy rows');
SELECT extensions.is(internal.source_child_uuid('legacy-not-uuid'),NULL::UUID,'legacy non UUID remains outside child namespace');
SELECT extensions.throws_ok(format('INSERT INTO public.%I(scan_id,user_id) VALUES(%L,%L)',table_name,child,owner),
 '22023','analysis_history_operation_conflict','bound child rejects legacy ingestion across owner and spelling')
 FROM unnest(ARRAY['scan_ingestion_jobs','scan_ingestion_intents']) table_name
 CROSS JOIN unnest(ARRAY['00000000-0000-4000-8000-00000000e131','{0000000000004000800000000000E131}']) child
 CROSS JOIN unnest(ARRAY['00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102']) owner;
SELECT extensions.throws_ok($$INSERT INTO public.scans(id,user_id,image_storage_urls) VALUES('00000000-0000-4000-8000-00000000e131','00000000-0000-4000-8000-00000000e102','{}')$$,
 '22023','analysis_history_operation_conflict','bound child cannot become another owner scan');
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES('legacy-not-uuid','00000000-0000-4000-8000-00000000e101');
INSERT INTO public.scan_ingestion_intents(scan_id,user_id) VALUES('{0000000000004000800000000000E132}','00000000-0000-4000-8000-00000000e102');
SELECT extensions.throws_ok($$SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e132',FALSE)$$,
 '22023','analysis_history_operation_conflict','existing aliased cross owner intent prevents binding');
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000E133','00000000-0000-4000-8000-00000000e102');
SELECT extensions.throws_ok($$SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e133',FALSE)$$,
 '22023','analysis_history_operation_conflict','existing uppercase job prevents binding');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_jobs SET scan_id='00000000-0000-4000-8000-00000000e131' WHERE scan_id='legacy-not-uuid'$$,
 '22023','analysis_history_operation_conflict','identity changing update cannot reuse bound child');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$INSERT INTO public.scan_ingestion_intents(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000E134','00000000-0000-4000-8000-00000000e102')$$,'42501',NULL,'service still cannot bypass approved ingestion routines');
SELECT extensions.throws_ok($$INSERT INTO public.scan_ingestion_intents(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e131','00000000-0000-4000-8000-00000000e102')$$,
 '42501',NULL,'service direct bound-child write remains denied');
RESET ROLE;
SELECT extensions.has_index('public','scan_ingestion_jobs','source_binding_ingestion_job_uuid','normalized job identity indexed');
SELECT extensions.has_index('public','scan_ingestion_intents','source_binding_ingestion_intent_uuid','normalized intent identity indexed');
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'helper not callable by API roles')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.source_child_uuid(text)','internal.guard_source_child_ingestion()']) signature;
SELECT extensions.ok(pg_get_functiondef('internal.guard_source_child_ingestion()'::regprocedure) LIKE '%analysis_history_current_snapshot_required%','ingestion fails closed with frozen transaction snapshots');
SELECT * FROM extensions.finish();
ROLLBACK;
