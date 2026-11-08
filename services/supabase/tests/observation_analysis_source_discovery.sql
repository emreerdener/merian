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

SELECT extensions.ok(NOT(SELECT source_discovery_enabled FROM internal.observation_history_rollout),'source discovery defaults closed');
SELECT extensions.ok(has_function_privilege('service_role','public.get_owned_observation_analysis_source(uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('authenticated','public.get_owned_observation_analysis_source(uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.get_owned_observation_analysis_source(uuid,jsonb,integer)','EXECUTE'),'only service owner boundary can read source discovery');
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000f901',pg_temp.history_append_request('00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f921'));
CREATE FUNCTION pg_temp.source_request() RETURNS JSONB LANGUAGE SQL AS $$ SELECT '{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000f911","source_analysis_id":"00000000-0000-4000-8000-00000000f921"}'::JSONB $$;
CREATE FUNCTION pg_temp.source_read() RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.get_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f901',pg_temp.source_request(),10) $$;
GRANT EXECUTE ON FUNCTION pg_temp.source_request(),pg_temp.source_read() TO anon,authenticated,service_role;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT pg_temp.source_read()$$,'42501','permission denied for function get_owned_observation_analysis_source','anon denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT pg_temp.source_read()$$,'42501','permission denied for function get_owned_observation_analysis_source','authenticated cannot choose service owner');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.source_read()->>'state','unavailable','closed discovery gate holds');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f901',pg_temp.source_request(),9)$$,'22023','analysis_history_reader_upgrade_required','reader10 required');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f901',pg_temp.source_request()||'{"extra":true}',10)$$,'22023','invalid_analysis_history','unknown keys rejected');
RESET ROLE;
UPDATE internal.observation_history_rollout SET source_discovery_enabled=TRUE;
SELECT extensions.is(pg_temp.source_read()->>'reason','coverage_incomplete','empty scope never claims absence before all-writer cutover');
SELECT extensions.is(public.get_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f902',pg_temp.source_request(),10)->>'state','unavailable','wrong owner unavailable');
SELECT extensions.is(public.get_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f901',pg_temp.source_request()||'{"source_analysis_id":"00000000-0000-4000-8000-00000000f929"}',10)->>'state','unavailable','missing source unavailable');
SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000f901',pg_temp.funded_input('00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f922','00000000-0000-4000-8000-00000000f921'),repeat('a',64));
CREATE TEMP TABLE before_read AS SELECT to_jsonb(i) value FROM internal.observation_analysis_intents i WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.source_read(),pg_temp.source_request()||jsonb_build_object('owner_id','00000000-0000-4000-8000-00000000f901','state','existing','analysis_id','00000000-0000-4000-8000-00000000f922','request_digest',repeat('a',64),'phase','admitted'),'one exact existing child, bounded private projection');
SELECT extensions.ok(octet_length(pg_temp.source_read()::TEXT)<2048,'response stays below wire ceiling');
RESET ROLE;
SELECT extensions.is((SELECT to_jsonb(i) FROM internal.observation_analysis_intents i WHERE analysis_id='00000000-0000-4000-8000-00000000f922'),(SELECT value FROM before_read),'discovery creates no claim and changes no durable work');
SAVEPOINT compatibility;
UPDATE internal.observation_analysis_intents SET input_snapshot=input_snapshot||'{"expected_processor_permission":"openai"}' WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'state' AS observed_1 \gset
UPDATE internal.observation_analysis_intents SET input_snapshot=input_snapshot||'{"history_protocol":10}' WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS observed_2 \gset
ROLLBACK TO compatibility;
SELECT extensions.is(:'observed_1'::TEXT,'existing','historical OpenAI photo identity remains readable');
SELECT extensions.is(:'observed_2'::TEXT,'malformed_linkage','unsupported persisted protocol does not borrow reader10');
SAVEPOINT damage;
UPDATE internal.observation_analysis_intents SET input_snapshot=input_snapshot||'{"source_analysis_id":"damaged"}' WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS observed_3 \gset
ROLLBACK TO damage;
SELECT extensions.is(:'observed_3'::TEXT,'malformed_linkage','malformed source is not filtered into absence');
SAVEPOINT duplicate;
INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot,quota)
SELECT '00000000-0000-4000-8000-00000000f923',observation_id,owner_id,input_snapshot||'{"analysis_id":"00000000-0000-4000-8000-00000000f923"}',quota||'{"original_analysis_id":"00000000-0000-4000-8000-00000000f923"}' FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS observed_4 \gset
ROLLBACK TO duplicate;
SELECT extensions.is(:'observed_4'::TEXT,'ambiguous_occupancy','multiple unresolved children held, never latest');
SAVEPOINT overflow;
INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot,quota)
SELECT ('00000000-0000-4000-8000-'||lpad(n::TEXT,12,'0'))::UUID,observation_id,owner_id,input_snapshot,quota FROM internal.observation_analysis_intents CROSS JOIN generate_series(1,64) n WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS observed_5 \gset
ROLLBACK TO overflow;
SELECT extensions.is(:'observed_5'::TEXT,'coverage_incomplete','65 parent intents are held before partial classification');
SAVEPOINT orphan_media;
INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items)
VALUES('00000000-0000-4000-8000-00000000f924','00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f901','[{}]');
SELECT pg_temp.source_read()->>'reason' AS observed_6 \gset
ROLLBACK TO orphan_media;
SELECT extensions.is(:'observed_6'::TEXT,'coverage_incomplete','unattributed parent cohort blocks all source discovery');
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f922');
SELECT extensions.is(pg_temp.source_read()->>'phase','dispatched','dispatched work grants only informational recovery');
SELECT pg_temp.funded_draft('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f922');
SELECT extensions.is(pg_temp.source_read()->>'phase','draft','draft remains unresolved');
SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f922');
SELECT extensions.is(pg_temp.source_read()->>'state','history_only','real canonical completion classifies terminal history');
SAVEPOINT damaged_receipt;
UPDATE internal.observation_analysis_intents SET receipt=jsonb_set(receipt,'{snapshot}','"damaged"') WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS observed_7 \gset
ROLLBACK TO damaged_receipt;
SELECT extensions.is(:'observed_7'::TEXT,'terminal_unproven','result alone cannot replace exact receipt');
SAVEPOINT no_intent;
-- Exercise backfill corruption without destructive intent-delete side effects.
UPDATE internal.observation_analysis_intents SET input_snapshot=jsonb_set(input_snapshot,'{source_analysis_id}','null') WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS observed_8 \gset
ROLLBACK TO no_intent;
SELECT extensions.is(:'observed_8'::TEXT,'terminal_unproven','source-linked result without tied intent holds');
SAVEPOINT deleted;
UPDATE public.scans SET is_tombstoned=TRUE WHERE id='00000000-0000-4000-8000-00000000f911';
SELECT pg_temp.source_read()->>'state' AS observed_9 \gset
ROLLBACK TO deleted;
SELECT extensions.is(:'observed_9'::TEXT,'unavailable','deletion wins over completed history');
SAVEPOINT contradictory_terminal;
INSERT INTO internal.observation_analysis_retirement_receipts(operation_id,analysis_id,observation_id,owner_id,request_identity,receipt)
SELECT '00000000-0000-4000-8000-00000000f931','00000000-0000-4000-8000-00000000f922','00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f901',r,r||'{"state":"retired_before_dispatch"}' FROM (SELECT jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f931','observation_id','00000000-0000-4000-8000-00000000f911','analysis_id','00000000-0000-4000-8000-00000000f922','source_analysis_id','00000000-0000-4000-8000-00000000f921','request_digest',repeat('a',64)) AS r) q;
SELECT pg_temp.source_read()->>'reason' AS contradictory_terminal_reason \gset
ROLLBACK TO contradictory_terminal;
SELECT extensions.is(:'contradictory_terminal_reason'::TEXT,'terminal_unproven','contradictory completion and retirement receipts hold');
SAVEPOINT missing_draft;
UPDATE internal.observation_analysis_intents SET draft=NULL WHERE analysis_id='00000000-0000-4000-8000-00000000f922';
SELECT pg_temp.source_read()->>'reason' AS missing_draft_reason \gset
ROLLBACK TO missing_draft;
SELECT extensions.is(:'missing_draft_reason'::TEXT,'terminal_unproven','complete needs retained exact draft and usage');
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11');
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000fa01',pg_temp.history_append_request('00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa21'));
SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000fa01',pg_temp.funded_input('00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa22','00000000-0000-4000-8000-00000000fa21'),repeat('a',64));
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=TRUE;
SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000fa01',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000fa31','observation_id','00000000-0000-4000-8000-00000000fa11','analysis_id','00000000-0000-4000-8000-00000000fa22','source_analysis_id','00000000-0000-4000-8000-00000000fa21','request_digest',repeat('a',64)),9);
CREATE FUNCTION pg_temp.retired_read() RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.get_owned_observation_analysis_source('00000000-0000-4000-8000-00000000fa01','{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000fa11","source_analysis_id":"00000000-0000-4000-8000-00000000fa21"}',10) $$;
SELECT extensions.is(pg_temp.retired_read()->>'state','history_only','exact pre-dispatch retirement classifies terminal history');
DELETE FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000fa22';
SELECT extensions.is(pg_temp.retired_read()->>'state','history_only','terminal classification survives quota pruning');
SAVEPOINT wrong_terminal;
UPDATE internal.observation_analysis_intents SET terminal_reason='cancelled_before_dispatch' WHERE analysis_id='00000000-0000-4000-8000-00000000fa22';
SELECT pg_temp.retired_read()->>'reason' AS wrong_terminal_reason \gset
ROLLBACK TO wrong_terminal;
SELECT extensions.is(:'wrong_terminal_reason'::TEXT,'terminal_unproven','other failure states do not reuse retirement proof');
-- Pin historical canonical snapshot framing. Future codec changes must preserve
-- old completion bytes, not silently invalidate saved terminal receipts.
SELECT extensions.is(internal.observation_analysis_snapshot(
 '00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa22',
 '00000000-0000-4000-8000-00000000fa21',repeat('a',64),2,'1970-01-01 00:00:00+00','{}',v.evidence),
 jsonb_build_object('schema_version',v.version,'observation_id','00000000-0000-4000-8000-00000000fa11',
 'analysis_id','00000000-0000-4000-8000-00000000fa22','source_analysis_id','00000000-0000-4000-8000-00000000fa21',
 'request_digest',repeat('a',64),'ordinal',2,'completed_at_ms',0,'result','{}'::JSONB,'evidence_manifest',v.evidence)::TEXT,
 'canonical receipt bytes retained for schema '||v.version::TEXT)
 FROM (VALUES (1,'{"schema_version":1,"captured_media":[]}'::JSONB),
 (2,'{"schema_version":2,"items":[]}'::JSONB),
 (3,'{"schema_version":3,"origin":"saved_identification","items":[]}'::JSONB),
 (4,'{"schema_version":3,"items":[]}'::JSONB)) v(version,evidence);
SELECT * FROM extensions.finish();
ROLLBACK;
