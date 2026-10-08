\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN SOURCE STORAGE HELPERS
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
-- END SOURCE STORAGE HELPERS
SELECT extensions.ok(relrowsecurity,'private table RLS enabled') FROM pg_class
 WHERE oid IN ('internal.observation_analysis_source_bindings'::regclass,'internal.observation_analysis_source_occupancy'::regclass);
SELECT extensions.ok(NOT has_table_privilege(role_name,table_name,privilege),'API role denied ' || privilege)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.observation_analysis_source_bindings','internal.observation_analysis_source_occupancy']) table_name
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'API role cannot execute storage trigger')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.guard_observation_source_storage()','internal.validate_observation_source_binding()','internal.erase_observation_source_storage()']) signature;
SELECT extensions.has_index('internal','ai_quota_reservations','source_binding_quota_child','quota child collision index');
SELECT extensions.has_index('internal','complimentary_scan_usage','source_binding_usage_child','usage child collision index');
SELECT extensions.has_index('public','scan_ingestion_intents','source_binding_ingestion_child','ingestion child collision index');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000f102','00000000-0000-4000-8000-00000000f112');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000f101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121'));
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f131');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy),1::BIGINT,'one unresolved source occupancy');
SELECT extensions.throws_ok($$SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f132')$$,'23505',NULL,'distinct child cannot occupy same source');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_bindings),1::BIGINT,'losing storage transaction rolled back binding');
SELECT extensions.throws_ok($$SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000f102','00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f132')$$,'P0002','analysis_history_not_found','cross-owner rejected');
SELECT extensions.throws_ok($$UPDATE internal.observation_analysis_source_bindings SET fingerprint=repeat('b',64)$$,'22023','analysis_history_operation_conflict','binding cannot change');
SELECT extensions.throws_ok($$UPDATE internal.observation_analysis_source_occupancy SET analysis_id='00000000-0000-4000-8000-00000000f132'$$,'22023','analysis_history_operation_conflict','occupancy cannot retarget');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_bindings$$,'22023','analysis_history_operation_conflict','live parent binding retained');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_occupancy$$,'22023','analysis_history_operation_conflict','no unproven occupancy release');
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f102')$$,'55000','ghost_merge_source_history_requires_attention','merge holds immutable source ownership');
SELECT extensions.is((SELECT user_id FROM public.scans WHERE id='00000000-0000-4000-8000-00000000f111'),'00000000-0000-4000-8000-00000000f101'::UUID,'failed merge preserves parent owner');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE observation_id='00000000-0000-4000-8000-00000000f111'),0::BIGINT,'storage creates no funded intent');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f131'),0::BIGINT,'storage consumes no quota');
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_source_bindings
 SELECT '00000000-0000-4000-8000-00000000f132',owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint
 FROM internal.observation_analysis_source_bindings$$,'22023','analysis_history_operation_conflict','forged child/input association rejected');
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_source_bindings
 SELECT '00000000-0000-4000-8000-00000000f132',owner_id,observation_id,source_analysis_id,
 pg_temp.source_input(observation_id,source_analysis_id,'00000000-0000-4000-8000-00000000f132'),1,repeat('b',64)
 FROM internal.observation_analysis_source_bindings$$,'22023','analysis_history_operation_conflict','forged fingerprint rejected');
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_source_occupancy VALUES(
 '00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111',
 '00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f132')$$,'23505',NULL,'occupied scope never rebinds to missing child');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000f133','00000000-0000-4000-8000-00000000f101');
SELECT extensions.throws_ok($$SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f133')$$,'22023','analysis_history_operation_conflict','retired child cannot gain a fresh binding');
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f132',FALSE);
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_bindings),2::BIGINT,'bindings do not impose lifetime one-child uniqueness');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy),1::BIGINT,'unoccupied binding does not change or release occupancy');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT * FROM internal.observation_analysis_source_bindings$$,'42501',NULL,'anon actual read denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_occupancy$$,'42501',NULL,'authenticated actual write denied');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT * FROM internal.observation_analysis_source_bindings$$,'42501',NULL,'service actual read denied');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f101',clock_timestamp());
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_bindings),0::BIGINT,'parent tombstone erases private bindings');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy),0::BIGINT,'parent tombstone cascades occupancy');
SELECT extensions.throws_ok($$SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000f101','00000000-0000-4000-8000-00000000f111','00000000-0000-4000-8000-00000000f121','00000000-0000-4000-8000-00000000f133')$$,'P0002','analysis_history_not_found','tombstone cannot resurrect binding');
SELECT * FROM extensions.finish();
ROLLBACK;
