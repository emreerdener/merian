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
SELECT extensions.ok(NOT (SELECT media_enabled OR media_reader_enabled FROM internal.observation_history_rollout WHERE singleton),'both media gates start closed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) role_name
    WHERE n.nspname='internal' AND p.proname LIKE '%observation_evidence%' AND HAS_FUNCTION_PRIVILEGE(role_name,p.oid,'EXECUTE')),'no API role can call evidence primitives');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM UNNEST(ARRAY['anon','authenticated','service_role']) role_name
    WHERE HAS_TABLE_PRIVILEGE(role_name,'internal.observation_evidence_objects','SELECT') OR HAS_TABLE_PRIVILEGE(role_name,'internal.observation_evidence_erasure','SELECT')),'receipt and erasure tables are inaccessible to API roles');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000f501','00000000-0000-4000-8000-00000000f511');
CREATE FUNCTION pg_temp.reserve_evidence(media TEXT DEFAULT '00000000-0000-4000-8000-00000000f531', digest TEXT DEFAULT REPEAT('a',64)) RETURNS JSONB LANGUAGE SQL AS $$
SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000f501','00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f521',media::UUID,'image/jpeg',3,digest);
$$;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_evidence()','55000','analysis_history_unavailable','reserve respects closed gate');
UPDATE internal.observation_history_rollout SET media_enabled=TRUE;
CREATE TEMP TABLE receipt AS SELECT pg_temp.reserve_evidence() AS value;
SELECT extensions.is(pg_temp.reserve_evidence(),(SELECT value FROM receipt),'reservation replay keeps key and deadline');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_evidence('00000000-0000-4000-8000-00000000f531',REPEAT('b',64))$$,'22023','analysis_history_operation_conflict','changed bytes cannot reuse receipt');
SELECT extensions.ok((SELECT value->>'object_id' NOT IN (value->>'owner_id',value->>'observation_id',value->>'analysis_id',value->>'media_id') FROM receipt),'object key is independent of owner and logical identities');
SELECT extensions.is((SELECT COUNT(*) FROM public.scan_media_assets WHERE scan_id='00000000-0000-4000-8000-00000000f511'),0::BIGINT,'private storage never enters public media inventory');
CREATE FUNCTION pg_temp.read_evidence(owner_id UUID DEFAULT '00000000-0000-4000-8000-00000000f501') RETURNS JSONB LANGUAGE SQL AS $$
SELECT internal.read_owned_observation_evidence(owner_id,'00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f521','00000000-0000-4000-8000-00000000f531');
$$;
CREATE FUNCTION pg_temp.complete_evidence() RETURNS JSONB LANGUAGE SQL AS $$
SELECT internal.complete_observation_evidence('00000000-0000-4000-8000-00000000f501','00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f521','00000000-0000-4000-8000-00000000f531',(SELECT (value->>'object_id')::UUID FROM receipt));
$$;
SELECT extensions.throws_ok('SELECT pg_temp.read_evidence()','55000','analysis_history_unavailable','owner reads have independent gate');
UPDATE internal.observation_history_rollout SET media_reader_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.read_evidence()','P0002','analysis_history_not_found','reserved upload is not readable');
SELECT extensions.throws_ok($$SELECT pg_temp.read_evidence('00000000-0000-4000-8000-00000000f599')$$,'P0002','analysis_history_not_found','foreign owner cannot read receipt');
CREATE TEMP TABLE ready AS SELECT pg_temp.complete_evidence() AS value;
SELECT extensions.is(pg_temp.complete_evidence(),(SELECT value FROM ready),'completion replay is immutable');
SELECT extensions.is(pg_temp.read_evidence(),(SELECT value FROM ready),'ready owner can resolve receipt');
SELECT extensions.throws_ok($$UPDATE internal.observation_evidence_objects SET sha256=REPEAT('b',64)$$,'22023','analysis_history_evidence_immutable','immutable digest cannot be edited');
SELECT extensions.throws_ok($$UPDATE internal.observation_evidence_objects SET ready_at=NULL$$,'22023','analysis_history_evidence_immutable','readiness cannot be undone');
SELECT extensions.ok(NOT internal.expire_observation_evidence('00000000-0000-4000-8000-00000000f531'),'expiry does not remove ready evidence');
INSERT INTO internal.observation_evidence_objects(media_id,observation_id,analysis_id,owner_id,content_type,byte_count,sha256,expires_at)
VALUES('00000000-0000-4000-8000-00000000f532','00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f521','00000000-0000-4000-8000-00000000f501','image/jpeg',3,REPEAT('a',64),NOW()-INTERVAL '1 minute');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_evidence('00000000-0000-4000-8000-00000000f532')$$,'55000','analysis_history_unavailable','retry cannot extend an expired upload capability');
SELECT extensions.throws_ok($$SELECT internal.complete_observation_evidence('00000000-0000-4000-8000-00000000f501','00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f521','00000000-0000-4000-8000-00000000f532',(SELECT object_id FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000f532'))$$,'55000','analysis_history_unavailable','expired upload cannot become ready');
CREATE TEMP TABLE expired_receipt AS SELECT object_id FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000f532';
SELECT extensions.ok(internal.expire_observation_evidence('00000000-0000-4000-8000-00000000f532'),'expiry queues erasure');
SELECT pg_temp.reserve_evidence('00000000-0000-4000-8000-00000000f532');
SELECT extensions.throws_ok($$SELECT internal.complete_observation_evidence('00000000-0000-4000-8000-00000000f501','00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f521','00000000-0000-4000-8000-00000000f532',(SELECT object_id FROM expired_receipt))$$,'P0002','analysis_history_not_found','late completion cannot authorize a replacement reservation');
SELECT extensions.ok((SELECT ready_at IS NULL FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000f532'),'replacement object remains unreadable after stale completion');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_evidence_erasure),1::BIGINT,'expired object has durable erasure obligation');
SELECT pg_temp.reserve_evidence('00000000-0000-4000-8000-00000000f533');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000f511','00000000-0000-4000-8000-00000000f501');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_evidence_objects),0::BIGINT,'deletion fence clears reserved and ready receipts immediately');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_evidence_erasure),4::BIGINT,'deletion queues both ready and in-flight writes');
SELECT extensions.throws_ok('SELECT pg_temp.complete_evidence()','P0002','analysis_history_not_found','deletion wins completed replay');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_evidence()','P0002','analysis_history_not_found','deletion wins reserve replay');
SELECT extensions.throws_ok('SELECT pg_temp.read_evidence()','P0002','analysis_history_not_found','deletion wins read');
CREATE TEMP TABLE claim AS SELECT internal.claim_observation_evidence_erasure() AS value;
SELECT extensions.ok(NOT internal.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM claim),'00000000-0000-4000-8000-00000000f599',TRUE),'foreign claim cannot acknowledge erasure');
SELECT extensions.ok(internal.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM claim),(SELECT (value->>'claim_token')::UUID FROM claim),FALSE),'failure schedules retry');
SELECT extensions.ok((SELECT erased_at IS NULL AND claim_token IS NULL AND available_at>NOW() FROM internal.observation_evidence_erasure WHERE object_id=(SELECT (value->>'object_id')::UUID FROM claim)),'failed write does not mark erased');
UPDATE internal.observation_evidence_erasure SET available_at=NOW()-INTERVAL '1 minute' WHERE object_id=(SELECT (value->>'object_id')::UUID FROM claim);
CREATE TEMP TABLE retry_claim AS SELECT internal.claim_observation_evidence_erasure() AS value;
SELECT extensions.ok((SELECT value->>'claim_token' FROM claim)<>(SELECT value->>'claim_token' FROM retry_claim),'retry changes claim identity');
SELECT extensions.ok(NOT internal.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM claim),(SELECT (value->>'claim_token')::UUID FROM claim),TRUE),'delayed old acknowledgment fails');
SELECT extensions.ok(internal.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM retry_claim),(SELECT (value->>'claim_token')::UUID FROM retry_claim),TRUE),'current marker write acknowledges erasure');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_evidence_erasure WHERE erased_at IS NOT NULL),1::BIGINT,'successful marker receipt retained');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000f502','00000000-0000-4000-8000-00000000f512');
SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000f502','00000000-0000-4000-8000-00000000f512','00000000-0000-4000-8000-00000000f522','00000000-0000-4000-8000-00000000f534','audio/mp4',3,REPEAT('a',64));
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000f502');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_evidence_objects),0::BIGINT,'account detachment clears private evidence');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_evidence_erasure),5::BIGINT,'account cascade preserves erasure obligation');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='internal' AND table_name='observation_evidence_erasure' AND column_name IN ('owner_id','observation_id','analysis_id','media_id','sha256','content_type')),'erasure ledger retains no owner or scientific payload');
SELECT * FROM extensions.finish();
ROLLBACK;
