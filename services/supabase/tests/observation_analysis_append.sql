\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(34);

-- BEGIN HISTORY APPEND SYNTHETIC HELPERS
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
-- END HISTORY APPEND SYNTHETIC HELPERS

SELECT extensions.ok(NOT (SELECT append_enabled FROM internal.observation_history_rollout WHERE singleton),'append starts closed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM UNNEST(ARRAY['anon','authenticated','service_role']) AS role_name
    WHERE HAS_FUNCTION_PRIVILEGE(role_name,'internal.append_observation_analysis(uuid,jsonb)','EXECUTE')),'no API role can invoke the storage primitive');
CREATE TEMP TABLE append_fixture AS SELECT '00000000-0000-4000-8000-00000000e501'::UUID owner_id,
    '00000000-0000-4000-8000-00000000e511'::UUID observation,
    '00000000-0000-4000-8000-00000000e521'::UUID analysis_a,
    '00000000-0000-4000-8000-00000000e522'::UUID analysis_b,
    '00000000-0000-4000-8000-00000000e523'::UUID analysis_c;
SELECT pg_temp.seed_history_append(owner_id,observation) FROM append_fixture;
CREATE TEMP TABLE original_scan AS SELECT TO_JSONB(s) AS value FROM public.scans s WHERE id=(SELECT observation FROM append_fixture);
CREATE FUNCTION pg_temp.append_fixture(analysis UUID, source UUID DEFAULT NULL, patch JSONB DEFAULT '{}') RETURNS TEXT LANGUAGE SQL AS $$
    SELECT internal.append_observation_analysis(owner_id,pg_temp.history_append_request(observation,analysis,source) || patch) FROM append_fixture;
$$;
SELECT extensions.throws_ok('SELECT pg_temp.append_fixture(analysis_a) FROM append_fixture','55000','analysis_history_unavailable','new appends respect independent gate');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
CREATE TEMP TABLE first_receipt AS SELECT pg_temp.append_fixture(analysis_a) AS value FROM append_fixture;
SELECT extensions.is(((SELECT value FROM first_receipt)::JSONB ->> 'ordinal')::INTEGER,1,'first append receives ordinal one');
SELECT extensions.ok((SELECT selection_initialized AND selected_analysis_id=analysis_a AND state_revision=1 FROM internal.observation_histories CROSS JOIN append_fixture WHERE observation_id=observation),'first result initializes selection exactly once');
SELECT extensions.is((SELECT active_projection ->> 'rank' FROM internal.observation_histories WHERE observation_id=(SELECT observation FROM append_fixture)),'non_biological','initial authority uses canonical non-biological projection');
SELECT extensions.ok((SELECT review_revision=0 AND review_snapshot ->> 'user_review_state'='unreviewed' AND review_snapshot -> 'user_confirmed_identification'='false' FROM internal.observation_analysis_authorities WHERE analysis_id=(SELECT analysis_a FROM append_fixture)),'new authority is unreviewed rather than inherited');
UPDATE internal.observation_history_rollout SET append_enabled=FALSE;
SELECT extensions.is((SELECT pg_temp.append_fixture(analysis_a) FROM append_fixture),(SELECT value FROM first_receipt),'lost response replays exact bytes even after new appends close');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_a,NULL,'{"request_digest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}') FROM append_fixture$$,'22023','analysis_history_operation_conflict','same analysis cannot change request binding');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_a,NULL,'{"result_snapshot":{}}') FROM append_fixture$$,'22023','analysis_history_operation_conflict','same analysis cannot change result');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_analysis_results WHERE observation_id=(SELECT observation FROM append_fixture)),1::BIGINT,'replays and conflicts add no result');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
UPDATE internal.observation_analysis_authorities SET review_revision=1,review_snapshot=review_snapshot || '{"user_confirmed_identification":true}' WHERE analysis_id=(SELECT analysis_a FROM append_fixture);
CREATE TEMP TABLE prior_state AS SELECT TO_JSONB(h) AS value FROM internal.observation_histories h WHERE observation_id=(SELECT observation FROM append_fixture);
CREATE TEMP TABLE prior_authority AS SELECT TO_JSONB(a) AS value FROM internal.observation_analysis_authorities a WHERE analysis_id=(SELECT analysis_a FROM append_fixture);
SELECT extensions.is(((SELECT pg_temp.append_fixture(analysis_b,analysis_a) FROM append_fixture)::JSONB ->> 'ordinal')::INTEGER,2,'reanalysis appends in serialized ordinal order');
SELECT extensions.is((SELECT TO_JSONB(h) FROM internal.observation_histories h WHERE observation_id=(SELECT observation FROM append_fixture)),(SELECT value FROM prior_state),'append preserves selected correction projection and revision');
SELECT extensions.is((SELECT TO_JSONB(a) FROM internal.observation_analysis_authorities a WHERE analysis_id=(SELECT analysis_a FROM append_fixture)),(SELECT value FROM prior_authority),'append never edits earlier review authority');
SELECT extensions.is((SELECT pg_temp.append_fixture(analysis_a) FROM append_fixture),(SELECT value FROM first_receipt),'old receipt cannot reinstall old authority');
SELECT extensions.is((SELECT TO_JSONB(s) FROM public.scans s WHERE id=(SELECT observation FROM append_fixture)),(SELECT value FROM original_scan),'immutable legacy scan projection remains untouched');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_history_reconciliation WHERE observation_id=(SELECT observation FROM append_fixture)),2::BIGINT,'only initial selection and explicit authority transition reconcile');
SELECT extensions.throws_ok('SELECT pg_temp.append_fixture(analysis_c,analysis_c) FROM append_fixture','22023','invalid_analysis_history','source cannot be the new analysis');
SELECT extensions.throws_ok('SELECT pg_temp.append_fixture(analysis_c,observation) FROM append_fixture','22023','invalid_analysis_history','source cannot be observation identity');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_c,'00000000-0000-4000-8000-00000000e599') FROM append_fixture$$,'P0002','analysis_history_not_found','missing source rejected before insertion');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_c,analysis_a,'{"evidence_manifest":{"schema_version":1,"captured_media":[{"image":{"_0":{"storage":"remoteURL","path":"https://media.merian.app/public_uploads/free/synthetic.jpg"}}}]}}') FROM append_fixture$$,'22023','invalid_analysis_history','public media cannot masquerade as protected evidence');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_c,analysis_a,'{"evidence_manifest":{"schema_version":1,"captured_media":[]}}') FROM append_fixture$$,'22023','invalid_analysis_history','empty evidence rejected');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_c,analysis_a,JSONB_BUILD_OBJECT('result_snapshot',(pg_temp.history_append_request(observation,analysis_c,analysis_a)->'result_snapshot') || '{"user_confirmed_identification":true}')) FROM append_fixture$$,'22023','invalid_analysis_history','result cannot supply review authority');
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_c,analysis_a,JSONB_BUILD_OBJECT('result_snapshot',(pg_temp.history_append_request(observation,analysis_c,analysis_a)->'result_snapshot') || '{"species_id":"00000000-0000-4000-8000-00000000e599"}')) FROM append_fixture$$,'22023','invalid_analysis_history','non-biological result cannot gain a species link');
SELECT extensions.throws_ok($$SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e599',pg_temp.history_append_request(observation,analysis_a)) FROM append_fixture$$,'P0002','analysis_history_not_found','foreign owner cannot replay a result');
INSERT INTO public.species_dictionary(id,scientific_name,common_names,kingdom,phylum,class,"order",family,genus,native_region)
VALUES('00000000-0000-4000-8000-00000000e590','Testus historyensis','{"en":"Synthetic history species"}','Animalia','Arthropoda','Insecta','Testales','Testidae','Testus','Synthetic region');
CREATE FUNCTION pg_temp.biological_append_patch(name TEXT) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('result_snapshot',(pg_temp.history_append_request(observation,analysis_c,analysis_a)->'result_snapshot') ||
        JSONB_BUILD_OBJECT('species_id','00000000-0000-4000-8000-00000000e590','is_biological_subject',TRUE,'scientific_name',name)) FROM append_fixture;
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture(analysis_c,analysis_a,pg_temp.biological_append_patch('Wrongus fixture')) FROM append_fixture$$,'22023','invalid_analysis_history','database independently rejects mismatched dictionary resolution');
SELECT extensions.is(((SELECT pg_temp.append_fixture('00000000-0000-4000-8000-00000000e526',analysis_a,pg_temp.biological_append_patch('Testus historyensis')) FROM append_fixture)::JSONB #>> '{result,species_id}'),'00000000-0000-4000-8000-00000000e590','validated biological result retains its dictionary species link');
SELECT extensions.is((SELECT TO_JSONB(h) FROM internal.observation_histories h WHERE observation_id=(SELECT observation FROM append_fixture)),(SELECT value FROM prior_state),'biological reanalysis cannot replace the selected non-biological result');
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT analysis_c,observation,2147483646,REPEAT('c',64),'{}','{"schema_version":1,"captured_media":[]}',NOW() FROM append_fixture;
SELECT extensions.throws_ok($$SELECT pg_temp.append_fixture('00000000-0000-4000-8000-00000000e524',analysis_a) FROM append_fixture$$,'55000','analysis_history_unavailable','ordinal exhaustion fails without overwriting history');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT observation,owner_id FROM append_fixture;
SELECT extensions.throws_ok('SELECT pg_temp.append_fixture(analysis_a) FROM append_fixture','P0002','analysis_history_deleted','deletion fence wins over completed replay');
SELECT extensions.throws_ok('SELECT pg_temp.append_fixture(analysis_b,analysis_a) FROM append_fixture','P0002','analysis_history_deleted','deletion fence wins over child replay');
SELECT extensions.ok(NOT (SELECT enrollment_enabled OR selection_enabled OR reader_enabled FROM internal.observation_history_rollout WHERE singleton),'append testing never activates readers, selection or persisted enrollment');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e502','00000000-0000-4000-8000-00000000e512',FALSE);
SELECT extensions.throws_ok($$SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e502',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e512','00000000-0000-4000-8000-00000000e525'))$$,'55000','analysis_history_unavailable','blank legacy history does not authorize initial selection');
SELECT extensions.throws_ok($$UPDATE internal.observation_histories SET initial_selection_permitted=TRUE WHERE observation_id='00000000-0000-4000-8000-00000000e512'$$,'22023','analysis_history_evidence_immutable','initial-selection eligibility cannot be enabled after enrollment');
SELECT * FROM extensions.finish();
ROLLBACK;
