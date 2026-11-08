\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Unidentified plant','is_biological_subject',TRUE,
            'is_live_capture',TRUE,'confidence_score',0.8,'blur_score',0.2,'colors','[]'::JSONB,
            'estimated_size_cm',NULL,'inference_tier','flash','pet_identification',NULL,'candidates',NULL,
            'image_quality',NULL,'ai_reasoning','Synthetic fixture.','extracted_visual_traits','[]'::JSONB),
        'evidence_manifest','{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation."}}}]}'::JSONB);
$$;
CREATE FUNCTION pg_temp.seed_history_append(owner_id UUID, observation UUID, permit_initial BOOLEAN DEFAULT TRUE)
RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW()) ON CONFLICT(id) DO NOTHING;
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
    VALUES(observation,owner_id,'{}',0.8,FALSE,'flash','private',TRUE);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(observation,permit_initial);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;
END;
$$;
CREATE FUNCTION pg_temp.seed_funded_history(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    PERFORM pg_temp.seed_history_append(owner_id,observation);
    IF EXISTS(SELECT 1 FROM public.user_adult_eligibility_receipts WHERE user_id=owner_id) THEN RETURN; END IF;
    INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
    INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
    INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;
CREATE FUNCTION pg_temp.funded_input(observation UUID,analysis UUID,source UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT (pg_temp.history_append_request(observation,analysis,source)-'result_snapshot') || '{"entitlement_protocol":3,"identification_protocol":6,"history_protocol":7,"expected_processor_permission":"google_gemini"}'::JSONB;
$$;
CREATE FUNCTION pg_temp.funded_provenance(analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_object('version',1,'provider',q->>'provider','binding',q->>'binding','model',q->>'model','variant','multimodal','operation','scan_identification','policy_version',(q->>'policy_version')::BIGINT,
        'prompt','identify_vision_v1','schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,
        'generation','{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB)
    FROM (SELECT quota AS q FROM internal.observation_analysis_intents WHERE analysis_id=analysis) s;
$$;
CREATE FUNCTION pg_temp.funded_dispatch(owner_id UUID,observation UUID,analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT internal.dispatch_observation_analysis(owner_id,observation,analysis,(quota->>'lease_token')::UUID,pg_temp.funded_provenance(analysis)) FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
CREATE FUNCTION pg_temp.funded_draft(owner_id UUID,observation UUID,analysis UUID) RETURNS VOID LANGUAGE SQL AS $$
    SELECT internal.record_observation_analysis_draft(owner_id,observation,analysis,(quota->>'lease_token')::UUID,
        pg_temp.history_append_request(observation,analysis,(input_snapshot->>'source_analysis_id')::UUID) || jsonb_build_object('result_snapshot',pg_temp.history_append_request(observation,analysis)->'result_snapshot' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis))),'{"input_tokens":100,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}')
    FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
CREATE FUNCTION pg_temp.protected_input(observation UUID,analysis UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','google_gemini','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
$$;
CREATE FUNCTION pg_temp.protected_ready(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE receipt JSONB;
BEGIN
 receipt:=internal.reserve_observation_evidence(owner_id,observation,analysis,media,'image/jpeg',3,repeat('a',64));
 PERFORM internal.complete_observation_evidence(owner_id,observation,analysis,media,(receipt->>'object_id')::UUID);
 RETURN (receipt->>'object_id')::UUID;
END;
$$;
CREATE FUNCTION pg_temp.protected_draft(owner_id UUID,observation UUID,analysis UUID) RETURNS VOID LANGUAGE SQL AS $$
 SELECT internal.record_observation_analysis_draft(owner_id,observation,analysis,(quota->>'lease_token')::UUID,
 (input_snapshot-ARRAY['entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']) || jsonb_build_object('result_snapshot',pg_temp.history_append_request(observation,analysis)->'result_snapshot' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis))),'{"input_tokens":100,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}')
 FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;

CREATE FUNCTION pg_temp.seed_publication_intent(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM pg_temp.seed_funded_history(owner_id,observation);
 PERFORM pg_temp.protected_ready(owner_id,observation,analysis,media);
 PERFORM internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64));
 PERFORM pg_temp.funded_dispatch(owner_id,observation,analysis);
 PERFORM pg_temp.protected_draft(owner_id,observation,analysis);
 PERFORM internal.complete_observation_analysis(owner_id,observation,analysis);
END;
$$;
CREATE FUNCTION pg_temp.publication_request(observation UUID,analysis UUID,operation UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id',observation,'analysis_id',analysis,'operation_id',operation,
 'expected_observation_revision',1,'expected_review_revision',0,'taxonomy_version_id',public.active_taxonomy_version_id(),
 'initial_taxon_id',NULL,'note','Synthetic public note','media_ids',jsonb_build_array(media));
$$;


-- Reconstruct pre-guard admitted rows for compatibility/capacity tests only.
CREATE FUNCTION pg_temp.legacy_publication_intake(owner_id UUID, request JSONB, ip TEXT) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM internal.prepare_observation_publication_intent(owner_id,request);
 INSERT INTO internal.observation_publication_operations(operation_id,observation_id,owner_id,ip_hash,receipt)
 VALUES((request->>'operation_id')::UUID,(request->>'observation_id')::UUID,owner_id,ip,
 jsonb_build_object('schema_version',1,'operation_id',request->'operation_id','observation_id',request->'observation_id',
 'analysis_id',request->'analysis_id','status','accepted','admitted_at',clock_timestamp()));
END;
$$;

SELECT extensions.ok(NOT (SELECT publication_operation_enabled FROM internal.observation_history_rollout),'operation gate defaults closed');
SELECT extensions.ok(has_function_privilege('service_role','public.admit_owned_observation_publication(uuid,jsonb,text)','EXECUTE'),'service intake allowed');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.admit_owned_observation_publication(uuid,jsonb,text)','EXECUTE') AND NOT has_function_privilege('anon','public.admit_owned_observation_publication(uuid,jsonb,text)','EXECUTE'),'client roles cannot nominate an owner');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_publication_operations','SELECT'),'operation data is private');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,publication_intent_enabled=TRUE;
SELECT pg_temp.seed_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe31');
CREATE TEMP TABLE publication_fixture AS SELECT pg_temp.publication_request('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe41','00000000-0000-4000-8000-00000000fe31') AS request;
GRANT SELECT ON publication_fixture TO service_role,authenticated;
CREATE FUNCTION pg_temp.admit_fixture(delta JSONB DEFAULT '{}',ip TEXT DEFAULT repeat('a',64)) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000fe01',request||delta,ip) FROM publication_fixture;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.admit_fixture(JSONB,TEXT) TO service_role;
SELECT extensions.throws_ok('SELECT pg_temp.admit_fixture()','55000','analysis_history_unavailable','closed intake gate writes nothing');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_intents),0,'closed intake does not even prepare an intent');
UPDATE internal.observation_history_rollout SET publication_operation_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT pg_temp.admit_fixture('{}','raw-address')$$,'22023','invalid_analysis_history','only server HMAC hash may be stored');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_fixture('{"owner_id":"00000000-0000-4000-8000-00000000fe01"}')$$,'22023','invalid_analysis_history','request cannot nominate owner');
SELECT extensions.throws_ok($$SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000fe02',request,repeat('a',64)) FROM publication_fixture$$,'P0002','analysis_history_not_found','cross-owner cannot admit');
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
CREATE TEMP TABLE accepted AS SELECT pg_temp.admit_fixture() AS receipt;
SELECT extensions.is((SELECT receipt->>'status' FROM accepted),'accepted','actual service role gets durable acceptance only');
SELECT extensions.is(pg_temp.admit_fixture('{}',repeat('b',64)),(SELECT receipt FROM accepted),'changed network recovers exact receipt');
RESET ROLE;
SELECT extensions.is((SELECT ip_hash FROM internal.observation_publication_operations),repeat('a',64),'first hash remains bound to future quota');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_operations),1,'duplicate intake stores one operation');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_moderations),0,'intake never reserves moderation');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects),0,'intake never reserves public copies');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts),0,'intake creates no public post');
SELECT extensions.ok((SELECT receipt-ARRAY['schema_version','operation_id','observation_id','analysis_id','status','admitted_at']='{}'::JSONB FROM accepted),'response excludes notes, media, hash and source identities');
SELECT extensions.throws_ok($$UPDATE internal.observation_publication_operations SET ip_hash=repeat('b',64)$$,'22023','analysis_history_evidence_immutable','operation facts cannot mutate');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_fixture('{"note":"changed"}')$$,'22023','analysis_history_operation_conflict','changed consent is not an exact retry');
UPDATE internal.observation_history_rollout SET publication_operation_enabled=FALSE,publication_intent_enabled=FALSE;
SELECT extensions.is(pg_temp.admit_fixture(),(SELECT receipt FROM accepted),'gates closing preserve exact acknowledgement replay');
UPDATE internal.observation_history_rollout SET publication_operation_enabled=TRUE,publication_intent_enabled=TRUE;
-- Legacy rows still count toward owner capacity; new target admission cannot
-- manufacture them. Use a fresh second observation for the capacity denial.
SELECT pg_temp.seed_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe12','00000000-0000-4000-8000-00000000fe22','00000000-0000-4000-8000-00000000fe32');
DO $$ BEGIN FOR i IN 42..48 LOOP PERFORM pg_temp.legacy_publication_intake('00000000-0000-4000-8000-00000000fe01',
 (SELECT request||jsonb_build_object('operation_id',('00000000-0000-4000-8000-00000000fe'||i)::UUID) FROM publication_fixture),repeat('a',64)); END LOOP; END $$;
SELECT extensions.throws_ok($$SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000fe01',
 pg_temp.publication_request('00000000-0000-4000-8000-00000000fe12','00000000-0000-4000-8000-00000000fe22','00000000-0000-4000-8000-00000000fe49','00000000-0000-4000-8000-00000000fe32'),repeat('a',64))$$,
 '55000','analysis_history_unavailable','rolling intake bound refuses additional new work on a fresh observation');
SELECT extensions.is(pg_temp.admit_fixture(),(SELECT receipt FROM accepted),'capacity cannot strand lost-response recovery');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_intents),8,'capacity denial cannot leave an orphan intent');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000fe01',request,repeat('a',64)) FROM publication_fixture$$,'42501','permission denied for function admit_owned_observation_publication','actual user role denied');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe01');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_operations),0,'observation fence immediately removes every queued operation');
SELECT extensions.throws_ok('SELECT pg_temp.admit_fixture()','P0002','analysis_history_not_found','deletion wins over accepted receipt replay');
SELECT * FROM extensions.finish();
ROLLBACK;
