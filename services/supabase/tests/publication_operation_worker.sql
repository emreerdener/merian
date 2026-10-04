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

SELECT extensions.ok(NOT (SELECT publication_execution_enabled FROM internal.observation_history_rollout),'execution gate defaults closed');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_publication_work','SELECT'),'worker state is not directly readable');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.claim_observation_publication_work(uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.read_owned_observation_publication_status(uuid,uuid,uuid)','EXECUTE'),'client roles cannot nominate owners');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.assert_publication_operation_work(uuid,uuid,uuid,uuid)','EXECUTE'),'claim assertion remains private');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,publication_intent_enabled=TRUE,publication_operation_enabled=TRUE;
SELECT pg_temp.seed_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe31');
CREATE TEMP TABLE fixture AS SELECT pg_temp.publication_request('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe41','00000000-0000-4000-8000-00000000fe31') AS request;
SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000fe01',request,repeat('a',64)) FROM fixture;
CREATE FUNCTION pg_temp.claim_work() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.claim_observation_publication_work('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41');
$$;
CREATE FUNCTION pg_temp.read_status() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.read_owned_observation_publication_status('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41');
$$;
CREATE FUNCTION pg_temp.release_work(token UUID) RETURNS VOID LANGUAGE SQL AS $$
 SELECT public.release_observation_publication_work('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41',token);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.claim_work(),pg_temp.read_status(),pg_temp.release_work(UUID) TO service_role,authenticated;
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_work),1,'intake atomically seeds one work row even with execution closed');
SELECT extensions.throws_ok('SELECT public.list_observation_publication_work()','55000','analysis_history_unavailable','closed gate prevents discovery');
SELECT extensions.throws_ok('SELECT pg_temp.claim_work()','55000','analysis_history_unavailable','closed gate prevents claim');
SELECT extensions.is(pg_temp.read_status()->>'status','accepted','status recovery works with execution closed');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.list_observation_publication_work()),1,'actual service role discovers accepted work');
SELECT extensions.ok((public.list_observation_publication_work()->0)-ARRAY['owner_id','observation_id','operation_id']='{}','discovery contains only scope hints');
CREATE TEMP TABLE original_claim AS SELECT pg_temp.claim_work() AS receipt;
SELECT extensions.is((SELECT receipt->>'claimed' FROM original_claim),'true','actual service role obtains claim');
SELECT extensions.throws_ok($$SELECT public.claim_observation_publication_work('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000ffff')$$,'P0002','analysis_history_not_found','claim requires the exact admitted operation');
SELECT extensions.throws_ok($$SELECT public.release_observation_publication_work('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000ffff',(SELECT (receipt->>'work_token')::UUID FROM original_claim))$$,'P0002','analysis_history_not_found','token cannot authorize another operation');
SELECT extensions.is(pg_temp.claim_work(),'{"claimed":false}'::JSONB,'duplicate claim cannot obtain or expose the first token');
SELECT extensions.is(public.list_observation_publication_work(),'[]'::JSONB,'active lease is not rediscovered');
SELECT extensions.is(pg_temp.read_status()->>'status','processing','active orchestration claim is processing only');
SELECT extensions.ok(pg_temp.read_status()-ARRAY['schema_version','operation_id','observation_id','analysis_id','status']='{}','owner status excludes sources, hash, note, token and internal outcome');
SELECT extensions.throws_ok($$SELECT public.read_owned_observation_publication_status('00000000-0000-4000-8000-00000000fe02','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'P0002','analysis_history_not_found','cross-owner status is denied');
SELECT extensions.throws_ok($$SELECT pg_temp.release_work('00000000-0000-4000-8000-00000000ffff')$$,'22023','analysis_history_operation_conflict','unrelated work token cannot release');
RESET ROLE;
SELECT extensions.is((SELECT receipt->>'ip_hash' FROM original_claim),repeat('a',64),'worker retains original quota address hash');
SELECT extensions.is((SELECT receipt->'request' FROM original_claim),(SELECT request FROM fixture),'worker receives exact immutable approved request');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_moderations),0,'claim reserves no provider attempt');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects),0,'claim reserves no public object');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=FALSE,publication_operation_enabled=FALSE;
SELECT extensions.lives_ok($$SELECT pg_temp.release_work((SELECT (receipt->>'work_token')::UUID FROM original_claim))$$,'gate closure allows current token release');
SELECT extensions.is(pg_temp.read_status()->>'status','accepted','release does not mark publication complete');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=TRUE;
SELECT extensions.is(public.list_observation_publication_work(),'[]'::JSONB,'release enforces discovery backoff');
SELECT extensions.is(pg_temp.claim_work(),'{"claimed":false}'::JSONB,'direct claim cannot bypass backoff');
UPDATE internal.observation_publication_work SET recover_after=clock_timestamp()-INTERVAL '1 second';
CREATE TEMP TABLE second_claim AS SELECT pg_temp.claim_work() AS receipt;
SELECT extensions.ok((SELECT receipt->'work_token' FROM second_claim)<>(SELECT receipt->'work_token' FROM original_claim),'reclaim uses a distinct orchestration identity');
SELECT extensions.throws_ok($$SELECT pg_temp.release_work((SELECT (receipt->>'work_token')::UUID FROM original_claim))$$,'22023','analysis_history_operation_conflict','stale worker cannot release a successor');
UPDATE internal.observation_publication_work SET work_expires_at=clock_timestamp()-INTERVAL '1 second';
SELECT extensions.throws_ok($$SELECT pg_temp.release_work((SELECT (receipt->>'work_token')::UUID FROM second_claim))$$,'22023','analysis_history_operation_conflict','expired token has no write authority');
SELECT extensions.is(pg_temp.read_status()->>'status','accepted','expiry reports awaiting recovery without inferring provider outcome');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.list_observation_publication_work()),1,'expired work becomes discoverable');
SELECT extensions.is(pg_temp.claim_work()->>'claimed','true','expired orchestration can be reclaimed without provider retry');
-- Model the binder's durable receipt insertion only; actual ordered cohort
-- authorization and revocation are covered by publication_photo_binding.sql.
INSERT INTO internal.observation_photo_publications(operation_id,object_ids,receipt)
VALUES('00000000-0000-4000-8000-00000000fe41',ARRAY['00000000-0000-4000-8000-00000000ff01'::UUID],'{"status":"admitted"}');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_work),0,'binding receipt atomically retires orchestration');
SELECT extensions.is(pg_temp.read_status()->>'status','admitted','only durable binding receipt establishes historical admission');
SELECT extensions.is(pg_temp.claim_work(),'{"claimed":false}'::JSONB,'completed operation cannot be reclaimed');
SELECT extensions.is((SELECT receipt->>'status' FROM internal.observation_publication_operations),'accepted','original accepted receipt stays immutable');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.read_status()','42501','permission denied for function read_owned_observation_publication_status','actual authenticated role cannot call owner-nominating RPC');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe01');
SELECT extensions.throws_ok('SELECT pg_temp.read_status()','P0002','analysis_history_not_found','deletion defeats historical admission status');
SELECT extensions.throws_ok('SELECT pg_temp.claim_work()','P0002','analysis_history_not_found','deletion defeats work recovery');
SELECT * FROM extensions.finish();
ROLLBACK;
