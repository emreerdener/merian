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

CREATE FUNCTION pg_temp.cohort_input(child UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
SELECT CASE WHEN version=3 THEN pg_temp.source_input('00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d122',child)
ELSE jsonb_set(pg_temp.source_input('00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d121',child)
 || '{"schema_version":2,"history_protocol":8}'::JSONB,'{evidence_manifest}',jsonb_build_object('schema_version',2,'items',jsonb_build_array(
 jsonb_build_object('kind','image','media_id','00000000-0000-4000-8000-00000000d191','content_type','image/jpeg','byte_count',100,'sha256',repeat('a',64)),
 jsonb_build_object('kind','description','text','Synthetic saved description.'),
 jsonb_build_object('kind','image','media_id','00000000-0000-4000-8000-00000000d192','content_type','image/png','byte_count',200,'sha256',repeat('b',64))))) END;
$$;
CREATE FUNCTION pg_temp.bind_cohort(child UUID,version INTEGER) RETURNS VOID LANGUAGE SQL AS $$
INSERT INTO internal.observation_analysis_source_bindings VALUES(child,'00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111',(pg_temp.cohort_input(child,version)->>'source_analysis_id')::UUID,pg_temp.cohort_input(child,version),1,internal.observation_source_fingerprint(pg_temp.cohort_input(child,version)));
$$;
CREATE FUNCTION pg_temp.insert_photo(child UUID,link UUID,items JSONB,owner_id UUID DEFAULT '00000000-0000-4000-8000-00000000d101',parent UUID DEFAULT '00000000-0000-4000-8000-00000000d111') RETURNS VOID LANGUAGE SQL AS $$
INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items,binding_analysis_id)
VALUES(child,parent,owner_id,items,link);
$$;
CREATE FUNCTION pg_temp.insert_audio(child UUID,link UUID,bytes INTEGER DEFAULT 46) RETURNS VOID LANGUAGE SQL AS $$
INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,observation_id,owner_id,media_id,content_type,byte_count,sha256,binding_analysis_id)
VALUES(child,'00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000f999','audio/wav',bytes,repeat('b',64),link);
$$;
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000d102','00000000-0000-4000-8000-00000000d112');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000d101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d121'));
SELECT pg_temp.bind_cohort('00000000-0000-4000-8000-00000000d131',2);
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000d101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d122','00000000-0000-4000-8000-00000000d121'));
SELECT pg_temp.bind_cohort('00000000-0000-4000-8000-00000000d132',3);

SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'source intent guard is private')
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)','internal.guard_source_bound_analysis_intent()']) signature;
CREATE FUNCTION pg_temp.chain(child UUID,version INTEGER) RETURNS VOID LANGUAGE SQL AS $$
SELECT internal.assert_observation_source_input_chain('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111',child,pg_temp.cohort_input(child,version));
$$;
CREATE FUNCTION pg_temp.insert_source_intent(child UUID,version INTEGER) RETURNS VOID LANGUAGE SQL AS $$
INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot)
VALUES(child,'00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d101',pg_temp.cohort_input(child,version));
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.insert_source_intent('00000000-0000-4000-8000-00000000d131',2)$$,'22023','analysis_history_operation_conflict','raw bound intent without occupancy/cohort rejected');
INSERT INTO internal.observation_analysis_source_occupancy VALUES('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d121','00000000-0000-4000-8000-00000000d131');
SELECT extensions.throws_ok($$SELECT pg_temp.chain('00000000-0000-4000-8000-00000000d131',2)$$,'22023','analysis_history_operation_conflict','occupancy without cohort rejected');
SAVEPOINT legacy_link;
SELECT pg_temp.insert_photo('00000000-0000-4000-8000-00000000d131',NULL,internal.observation_source_cohort_items(pg_temp.cohort_input('00000000-0000-4000-8000-00000000d131',2),2));
SELECT extensions.throws_ok($$SELECT pg_temp.chain('00000000-0000-4000-8000-00000000d131',2)$$,'22023','analysis_history_operation_conflict','NULL legacy cohort never becomes binding proof');
ROLLBACK TO SAVEPOINT legacy_link;
SELECT pg_temp.insert_photo('00000000-0000-4000-8000-00000000d131','00000000-0000-4000-8000-00000000d131',internal.observation_source_cohort_items(pg_temp.cohort_input('00000000-0000-4000-8000-00000000d131',2),2));
SELECT extensions.lives_ok($$SELECT pg_temp.chain('00000000-0000-4000-8000-00000000d131',2)$$,'exact ordered photo chain validates');
SELECT extensions.throws_ok($$SELECT internal.assert_observation_source_input_chain('00000000-0000-4000-8000-00000000d102','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d131',pg_temp.cohort_input('00000000-0000-4000-8000-00000000d131',2))$$,'22023','analysis_history_operation_conflict','cross owner chain denied');
SELECT extensions.throws_ok($$SELECT internal.assert_observation_source_input_chain('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d112','00000000-0000-4000-8000-00000000d131',pg_temp.cohort_input('00000000-0000-4000-8000-00000000d131',2))$$,'22023','analysis_history_operation_conflict','cross parent chain denied');
SELECT extensions.throws_ok($$SELECT internal.assert_observation_source_input_chain('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d131',pg_temp.cohort_input('00000000-0000-4000-8000-00000000d131',2) || jsonb_build_object('request_digest',repeat('c',64)))$$,'22023','analysis_history_operation_conflict','changed immutable input rejected');
SAVEPOINT opposite_cohort;
SELECT pg_temp.insert_audio('00000000-0000-4000-8000-00000000d131',NULL);
SELECT extensions.throws_ok($$SELECT pg_temp.chain('00000000-0000-4000-8000-00000000d131',2)$$,'22023','analysis_history_operation_conflict','ambiguous mixed cohort types rejected');
ROLLBACK TO SAVEPOINT opposite_cohort;
-- Source-chain validation does not replace the existing ready-evidence gate.
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE;
DO $$ DECLARE item JSONB; receipt JSONB;
BEGIN
FOR item IN SELECT value FROM jsonb_array_elements(internal.observation_source_cohort_items(pg_temp.cohort_input('00000000-0000-4000-8000-00000000d131',2),2)) LOOP
receipt:=internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d131',(item->>'media_id')::UUID,item->>'content_type',(item->>'byte_count')::INTEGER,item->>'sha256');
PERFORM internal.complete_observation_evidence('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d131',(item->>'media_id')::UUID,(receipt->>'object_id')::UUID);
END LOOP;
END; $$;
SELECT extensions.lives_ok($$SELECT pg_temp.insert_source_intent('00000000-0000-4000-8000-00000000d131',2)$$,'exact chain and ready evidence permit private intent insertion');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d131'),0::BIGINT,'intent guard does not reserve quota');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE scan_id='00000000-0000-4000-8000-00000000d131'),0::BIGINT,'intent guard does not grant dispatch');
-- An unoccupied audio binding cannot become intent authority.
SELECT pg_temp.insert_audio('00000000-0000-4000-8000-00000000d132','00000000-0000-4000-8000-00000000d132');
SELECT extensions.throws_ok($$SELECT pg_temp.chain('00000000-0000-4000-8000-00000000d132',3)$$,'22023','analysis_history_operation_conflict','audio binding and cohort without occupancy stay held');
INSERT INTO internal.observation_analysis_source_occupancy VALUES('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d122','00000000-0000-4000-8000-00000000d132');
SELECT extensions.lives_ok($$SELECT pg_temp.chain('00000000-0000-4000-8000-00000000d132',3)$$,'exact audio chain validates');
DO $$ DECLARE receipt JSONB;
BEGIN
receipt:=internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d132','00000000-0000-4000-8000-00000000f999','audio/wav',46,repeat('b',64));
PERFORM internal.complete_observation_evidence('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d132','00000000-0000-4000-8000-00000000f999',(receipt->>'object_id')::UUID);
END; $$;
SELECT extensions.lives_ok($$SELECT pg_temp.insert_source_intent('00000000-0000-4000-8000-00000000d132',3)$$,'exact audio chain and ready evidence permit private intent insertion');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d101');
SELECT extensions.throws_ok($$SELECT pg_temp.insert_source_intent('00000000-0000-4000-8000-00000000d131',2)$$,'P0002','analysis_history_not_found','deletion wins over exact input');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE observation_id='00000000-0000-4000-8000-00000000d111'),0::BIGINT,'deletion removes bound intent');
SELECT * FROM extensions.finish();
ROLLBACK;
