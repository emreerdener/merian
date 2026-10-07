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
CREATE FUNCTION pg_temp.funded_provenance(analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_object('version',1,'provider',q->>'provider','binding',q->>'binding','model',q->>'model','variant','multimodal','operation','scan_identification','policy_version',(q->>'policy_version')::BIGINT,
        'prompt','identify_vision_v1','schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,
        'generation','{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB)
    FROM (SELECT quota AS q FROM internal.observation_analysis_intents WHERE analysis_id=analysis) s;
$$;

SELECT extensions.ok(NOT audio_analysis_enabled,'audio execution disabled by default') FROM internal.observation_history_rollout;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911');
UPDATE internal.observation_history_rollout SET orchestration_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,reader_enabled=TRUE,state_reader_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000a901',pg_temp.history_append_request('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a920'));
CREATE TEMP TABLE original_history AS SELECT selected_analysis_id,state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000a911';
-- Preserve exact old-client receipts before audio arrives; reader10 later
-- recovers them even with fresh-action gates closed.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000a901',TRUE);
UPDATE internal.observation_history_rollout SET selection_enabled=TRUE,selection_api_enabled=TRUE,rejection_api_enabled=TRUE,confirmation_api_enabled=TRUE,confirmation_undo_api_enabled=TRUE;
CREATE FUNCTION pg_temp.action_request() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000a911','analysis_id','00000000-0000-4000-8000-00000000a920','operation_id','00000000-0000-4000-8000-00000000a941','expected_observation_revision',0,'expected_review_revision',0);
$$;
CREATE FUNCTION pg_temp.select_action(reader INTEGER) RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.select_owned_observation_analysis(pg_temp.action_request(),reader); $$;
CREATE FUNCTION pg_temp.review_action(reader INTEGER) RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.review_owned_observation_analysis(pg_temp.action_request() || '{"action":"reject","undo_operation_id":null}',reader); $$;
CREATE FUNCTION pg_temp.confirm_action(reader INTEGER,complete BOOLEAN DEFAULT FALSE) RETURNS JSONB LANGUAGE SQL AS $$ SELECT internal.confirm_observation_analysis('00000000-0000-4000-8000-00000000a901',pg_temp.action_request() || '{"operation_id":"00000000-0000-4000-8000-00000000a942","action":"confirm_primary","scientific_name":null}',reader,complete,NULL,NULL); $$;
CREATE TEMP TABLE old_actions AS SELECT pg_temp.select_action(9) selection,pg_temp.review_action(9) review,pg_temp.confirm_action(9) confirmation;
SELECT extensions.is(pg_temp.select_action(10),(SELECT selection FROM old_actions),'reader10 preserves original selection receipt');
SELECT extensions.is(pg_temp.review_action(10),(SELECT review FROM old_actions),'reader10 preserves original review receipt');
SELECT extensions.is(pg_temp.confirm_action(10),(SELECT confirmation FROM old_actions),'reader10 preserves original confirmation receipt');
CREATE TEMP TABLE audio_receipt AS SELECT public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921','00000000-0000-4000-8000-00000000a931',46,repeat('b',64)) value;
CREATE FUNCTION pg_temp.audio_manifest() RETURNS JSONB LANGUAGE SQL AS $$ SELECT jsonb_build_object('schema_version',3,'items',jsonb_build_array(jsonb_build_object('kind','description','text','Before'),jsonb_build_object('kind','audio','media_id','00000000-0000-4000-8000-00000000a931','content_type','audio/wav','byte_count',46,'sha256',repeat('b',64)),jsonb_build_object('kind','description','text','After'))); $$;
CREATE FUNCTION pg_temp.funded_input(observation UUID,analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$ SELECT (pg_temp.history_append_request(observation,analysis,'00000000-0000-4000-8000-00000000a920')-'result_snapshot') || jsonb_build_object('schema_version',3,'evidence_manifest',pg_temp.audio_manifest(),'entitlement_protocol',3,'identification_protocol',6,'history_protocol',9,'expected_processor_permission','google_gemini'); $$;
CREATE FUNCTION pg_temp.audio_draft() RETURNS JSONB LANGUAGE SQL AS $$ SELECT pg_temp.history_append_request('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921','00000000-0000-4000-8000-00000000a920') || jsonb_build_object('schema_version',3,'evidence_manifest',pg_temp.audio_manifest()); $$;
CREATE FUNCTION pg_temp.begin_work() RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.begin_owned_observation_analysis('00000000-0000-4000-8000-00000000a901',pg_temp.funded_input('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921'),repeat('a',64)); $$;
SELECT extensions.throws_ok('SELECT pg_temp.begin_work()','55000','analysis_history_unavailable','audio gate refuses funding');
UPDATE internal.observation_history_rollout SET audio_analysis_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.begin_work()','55000','analysis_history_evidence_unavailable','unready audio cannot fund');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a921'),0::BIGINT,'denied admission consumed no slot');
SELECT public.complete_owned_observation_audio_evidence_upload('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921','00000000-0000-4000-8000-00000000a931',(SELECT (value->>'object_id')::UUID FROM audio_receipt));

ALTER TABLE internal.observation_audio_evidence_upload_cohorts DISABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_audio_evidence_upload_cohorts SET expires_at=transaction_timestamp()-interval '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-interval '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
ALTER TABLE internal.observation_audio_evidence_upload_cohorts ENABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SELECT extensions.throws_ok('SELECT pg_temp.begin_work()','55000','analysis_history_evidence_unavailable','expired unbound cohort cannot admit');

ALTER TABLE internal.observation_audio_evidence_upload_cohorts DISABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_audio_evidence_upload_cohorts SET expires_at=(SELECT (value->>'expires_at')::TIMESTAMPTZ FROM audio_receipt) WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
UPDATE internal.observation_evidence_objects SET expires_at=(SELECT (value->>'expires_at')::TIMESTAMPTZ FROM audio_receipt) WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
ALTER TABLE internal.observation_audio_evidence_upload_cohorts ENABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
CREATE TEMP TABLE claim AS SELECT pg_temp.begin_work() AS value;
SELECT extensions.is((SELECT value->>'state' FROM claim),'admitted','first request claims admitted intent');
UPDATE internal.observation_history_rollout SET execution_status_api_enabled=TRUE,execution_retirement_api_enabled=TRUE;
CREATE FUNCTION pg_temp.execution_request() RETURNS JSONB LANGUAGE SQL AS $$ SELECT jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000a911','analysis_id','00000000-0000-4000-8000-00000000a921','source_analysis_id','00000000-0000-4000-8000-00000000a920','request_digest',repeat('a',64)); $$;
CREATE FUNCTION pg_temp.execution_status(reader INTEGER) RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.get_owned_observation_analysis_execution(pg_temp.execution_request(),reader); $$;
CREATE FUNCTION pg_temp.retire_action(reader INTEGER) RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000a901',pg_temp.execution_request() || '{"operation_id":"00000000-0000-4000-8000-00000000a943"}',reader); $$;
SELECT extensions.throws_ok('SELECT pg_temp.execution_status(9)','55000','analysis_history_reader_upgrade_required','pending input3 is incompatible before any audio result exists');
SELECT extensions.is(pg_temp.execution_status(10)->>'state','admitted','reader10 observes exact pending audio without dispatch');
SELECT extensions.throws_ok('SELECT pg_temp.retire_action(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot retire pending audio');
SAVEPOINT audio_retirement;
CREATE TEMP TABLE audio_retired AS SELECT pg_temp.retire_action(10) value;
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=FALSE;
SELECT extensions.is(pg_temp.retire_action(10),(SELECT value FROM audio_retired),'reader10 retirement receipt replay precedes closed gate');
SELECT extensions.throws_ok('SELECT pg_temp.retire_action(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot replay retired audio receipt');
ROLLBACK TO SAVEPOINT audio_retirement;

SELECT extensions.is(pg_temp.begin_work()->'claimed','false'::JSONB,'simultaneous retry cannot take active claim');
CREATE FUNCTION pg_temp.advance(operation TEXT,payload JSONB DEFAULT '{}') RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.advance_owned_observation_analysis('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921',(SELECT (value->>'work_token')::UUID FROM claim),operation,payload); $$;

ALTER TABLE internal.observation_audio_evidence_upload_cohorts DISABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_audio_evidence_upload_cohorts SET expires_at=transaction_timestamp()-interval '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-interval '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
ALTER TABLE internal.observation_audio_evidence_upload_cohorts ENABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SELECT extensions.is(jsonb_array_length(pg_temp.advance('materialize')),1,'audio materializes exact receipt');
SELECT extensions.is((SELECT quota->>'input_profile' FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000a921'),'multimodal_audio_v1','funding binds audio profile');
SELECT extensions.is(pg_temp.advance('dispatch',jsonb_build_object('provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000a921')))->'may_dispatch','true'::JSONB,'claimed dispatch admits one execution');
SELECT extensions.is(pg_temp.begin_work()->'claimed','false'::JSONB,'dispatched outcome is not permission for new inference');
SELECT extensions.is(public.list_observation_analysis_recovery(),'[]'::JSONB,'uncertain execution never enters automatic recovery');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('fail','{"reason":"timeout"}')$$,'22023','invalid_analysis_history','timeout cannot release hold');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('fail','{"reason":"provider_refusal"}')$$,'22023','invalid_analysis_history','terminal claim needs durable provider evidence');
CREATE TEMP TABLE outcome AS SELECT jsonb_build_object('quota_token',quota->'lease_token','value',jsonb_build_object('schema_version',1,'provenance',pg_temp.funded_provenance(analysis_id),'outcome',jsonb_build_object('kind','draft','result',(pg_temp.history_append_request(observation_id,analysis_id)->'result_snapshot')-'species_id' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis_id))),'usage','{}'::JSONB)) AS value FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
SELECT pg_temp.advance('outcome',(SELECT value FROM outcome));
SELECT extensions.is(jsonb_array_length(public.list_observation_analysis_recovery()),1,'received outcome becomes recoverable even after claim expiry');
SELECT extensions.lives_ok($$SELECT pg_temp.advance('outcome',(SELECT value FROM outcome))$$,'lost outcome response supports exact retry');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('outcome',(SELECT jsonb_set(value,'{value,outcome,kind}','"refusal"') FROM outcome))$$,'22023','analysis_history_operation_conflict','received outcome cannot be replaced');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('release')$$,'22023','analysis_history_operation_conflict','stale worker cannot change recovery scheduling');
UPDATE claim SET value=public.claim_observation_analysis_recovery('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921');
SELECT extensions.is((SELECT value->'claimed' FROM claim),'true'::JSONB,'recovery takes expired claim without provider dispatch');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a921'),'held','received outcome alone does not consume credit');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('draft',jsonb_build_object('draft',pg_temp.audio_draft() || jsonb_build_object('result_snapshot',(SELECT value#>'{value,outcome,result}' FROM outcome) || '{"confidence_score":0.01}'::JSONB || jsonb_build_object('species_id',NULL,'identification_provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000a921')))))$$,'22023','invalid_analysis_history','same provenance cannot authorize a different result');
SELECT pg_temp.advance('draft',jsonb_build_object('draft',pg_temp.audio_draft() || jsonb_build_object('result_snapshot',(SELECT value#>'{value,outcome,result}' FROM outcome) || jsonb_build_object('species_id',NULL,'identification_provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000a921')))));
SELECT extensions.is(pg_temp.advance('complete')->>'state','complete','draft completion is atomic');
SELECT extensions.is(pg_temp.begin_work(),' {"state":"complete","claimed":false}'::JSONB,'lost completion replay returns only terminal state');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE scan_id='00000000-0000-4000-8000-00000000a921'),1::BIGINT,'all retries retain one provider execution');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a921'),'consumed','only durable completion consumes credit');

SELECT extensions.is((SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000a911'),(SELECT selected_analysis_id FROM original_history),'audio completion preserves original selection');
SELECT extensions.is((SELECT review_snapshot->>'user_review_state' FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000a921'),'unreviewed','new audio starts unreviewed');
SELECT extensions.is((SELECT (internal.observation_analysis_snapshot(r.observation_id,r.analysis_id,r.source_analysis_id,r.request_digest,r.ordinal,r.completed_at,r.result_snapshot,r.evidence_manifest)::JSONB)->>'schema_version' FROM internal.observation_analysis_results r WHERE analysis_id='00000000-0000-4000-8000-00000000a921'),'4','audio uses outer result4');
SELECT extensions.is((SELECT evidence_manifest FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000a921'),pg_temp.audio_manifest(),'stored evidence order unchanged');

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000a901',TRUE);
SELECT set_config('request.jwt.claim.role','authenticated',TRUE);
CREATE FUNCTION pg_temp.page(reader INTEGER,cursor_ordinal INTEGER DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.get_owned_observation_analysis_page(jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000a911','before_ordinal',cursor_ordinal,'limit',10),reader); $$;
CREATE FUNCTION pg_temp.target_state(reader INTEGER,child UUID DEFAULT '00000000-0000-4000-8000-00000000a921') RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.get_owned_observation_analysis_state(jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000a911','analysis_id',child),reader); $$;
SELECT extensions.throws_ok('SELECT pg_temp.page(9)','55000','analysis_history_reader_upgrade_required','old page reader refuses audio history');
SELECT extensions.throws_ok('SELECT pg_temp.page(9,2)','55000','analysis_history_reader_upgrade_required','old cursor cannot hide audio row');
SELECT extensions.throws_ok($$SELECT pg_temp.target_state(9,'00000000-0000-4000-8000-00000000a920')$$,'55000','analysis_history_reader_upgrade_required','old target reader refuses whole audio history');
SELECT extensions.is(jsonb_array_length(pg_temp.page(10)->'items'),2,'reader10 returns mixed original and audio history');
SELECT extensions.is(((pg_temp.target_state(10)#>>'{analysis,snapshot}')::JSONB)->>'schema_version','4','reader10 returns exact audio state');
SELECT extensions.is(pg_temp.target_state(10)->>'selected_analysis_id','00000000-0000-4000-8000-00000000a920','reader10 target state does not select audio');
-- Whole-observation action refusal includes old targets and existing receipts.
SELECT extensions.throws_ok('SELECT pg_temp.select_action(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot replay selection after audio append');
SELECT extensions.throws_ok('SELECT pg_temp.review_action(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot replay review after audio append');
SELECT extensions.throws_ok('SELECT pg_temp.confirm_action(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot replay confirmation after audio append');
SELECT extensions.throws_ok('SELECT pg_temp.execution_status(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot observe completed audio execution');
SELECT extensions.throws_ok('SELECT pg_temp.retire_action(9)','55000','analysis_history_reader_upgrade_required','reader9 cannot retire completed audio history');
SELECT extensions.is(pg_temp.execution_status(10)->>'state','complete','reader10 recovers completed status without execution');
SELECT extensions.throws_ok('SELECT pg_temp.retire_action(10)','22023','analysis_history_operation_conflict','completed execution remains nonretirable for reader10');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_confirmation_undo(pg_temp.action_request()-'operation_id',9)$$,'55000','analysis_history_reader_upgrade_required','confirmation Undo lookup refuses whole audio history');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_rejection_undo(pg_temp.action_request()-'operation_id',9)$$,'55000','analysis_history_reader_upgrade_required','rejection Undo lookup refuses whole audio history');
SELECT extensions.is(public.get_owned_observation_confirmation_undo(pg_temp.action_request()-'operation_id',10)->>'reason','revision_conflict','reader10 confirmation lookup preserves exact revisions');
SELECT extensions.is(public.get_owned_observation_rejection_undo(pg_temp.action_request()-'operation_id',10)->>'reason','revision_conflict','reader10 rejection lookup preserves exact revisions');
UPDATE internal.observation_history_rollout SET selection_api_enabled=FALSE,rejection_api_enabled=FALSE,confirmation_api_enabled=FALSE;
SELECT extensions.is(pg_temp.select_action(10),(SELECT selection FROM old_actions),'reader10 selection replay precedes fresh gate on mixed history');
SELECT extensions.is(pg_temp.review_action(10),(SELECT review FROM old_actions),'reader10 review replay precedes fresh gate on mixed history');
SELECT extensions.is(pg_temp.confirm_action(10),(SELECT confirmation FROM old_actions),'reader10 confirmation prepare replay precedes fresh gate on mixed history');
SELECT extensions.is(pg_temp.confirm_action(10,TRUE),(SELECT confirmation FROM old_actions),'reader10 confirmation complete replay precedes fresh gate on mixed history');
SELECT extensions.throws_ok('SELECT pg_temp.select_action(NULL)','22023','invalid_analysis_history','null reader is not compatible');
SELECT extensions.throws_ok('SELECT pg_temp.review_action(11)','22023','invalid_analysis_history','unknown reader is not compatible');
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000a909',TRUE);
SELECT extensions.throws_ok('SELECT pg_temp.target_state(10)','P0002','analysis_history_not_found','foreign owner cannot read audio');
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000a901',TRUE);
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a901');
SELECT extensions.throws_ok('SELECT pg_temp.target_state(10)','P0002','analysis_history_not_found','deletion wins over saved audio result');
SELECT extensions.throws_ok('SELECT pg_temp.begin_work()','P0002','analysis_history_not_found','deletion wins over exact completed replay');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=(SELECT (value->>'object_id')::UUID FROM audio_receipt)),'deletion retains exact audio erasure obligation');
SELECT * FROM extensions.finish();
ROLLBACK;
