\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN SOURCE FUNDING HELPERS
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
CREATE FUNCTION pg_temp.seed_invocation(p_openai BOOLEAN DEFAULT FALSE)
RETURNS TABLE(reservation UUID, owner_id UUID, token UUID, scan UUID)
LANGUAGE plpgsql AS $function$
BEGIN
    reservation := gen_random_uuid(); owner_id := gen_random_uuid(); token := gen_random_uuid(); scan := gen_random_uuid();
    INSERT INTO auth.users(id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
        VALUES (owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}');
    INSERT INTO public.users(id,email,public_username,public_author_name,public_identity_source)
        VALUES(owner_id,owner_id::TEXT || '@example.invalid','account_' || left(replace(owner_id::TEXT,'-',''),16),'Synthetic accounting','alias')
        ON CONFLICT(id) DO NOTHING;
    INSERT INTO internal.ai_quota_reservations (id,user_id,operation,request_id,lease_token,
        model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id)
        VALUES(reservation,owner_id,'scan_identification',scan,token,'gemini-2.5-flash','free','free','free',FALSE,1,1,scan);
    INSERT INTO internal.identification_provider_attempts (reservation_id,attempt_count,operation,effective_plan,model,policy_version,
        provider,binding,processor_permission,input_profile,provider_model,minimum_identification_protocol,accepted_identification_protocol)
        VALUES(reservation,1,'scan_identification','free','gemini-2.5-flash',1,
            CASE WHEN p_openai THEN 'openai' ELSE 'gemini' END,
            CASE WHEN p_openai THEN 'openai_photo_v1' ELSE 'gemini_baseline_v1' END,
            CASE WHEN p_openai THEN 'openai' ELSE 'google_gemini' END,'multimodal_photo_v1',
            CASE WHEN p_openai THEN 'gpt-6-sol' ELSE NULL END,CASE WHEN p_openai THEN 4 ELSE 0 END,4);
    RETURN NEXT;
END;
$function$;

CREATE FUNCTION pg_temp.commit_invocation(p_reservation UUID, p_owner UUID, p_token UUID, p_attempt INTEGER)
RETURNS TABLE(invocation_id UUID, may_dispatch BOOLEAN) LANGUAGE sql AS $function$
    SELECT result.* FROM internal.identification_provider_attempts, LATERAL public.commit_identification_invocation(p_reservation,p_owner,p_token,p_attempt,
        jsonb_build_object('version',CASE provider WHEN 'openai' THEN 2 ELSE 1 END,
        'provider',provider,'binding',binding,'model',coalesce(provider_model,model),'variant','multimodal',
        'operation',operation,'policy_version',policy_version,'prompt','identify_vision_v1',
        'schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,
        'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,'generation',
        CASE provider WHEN 'openai' THEN '{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}'::JSONB
          ELSE '{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB END))
    AS result WHERE reservation_id=p_reservation AND attempt_count=p_attempt;
$function$;

-- END SOURCE FUNDING HELPERS
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111');
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000d102','00000000-0000-4000-8000-00000000d112');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000d101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d121'));
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d111','00000000-0000-4000-8000-00000000d121','00000000-0000-4000-8000-00000000d131',FALSE);
SELECT extensions.throws_ok(format('SELECT * FROM internal.reserve_ai_quota_core(%L,%L,%L,repeat(''a'',64),%L,FALSE,3,FALSE)',owner,'scan_identification',request,'00000000-0000-4000-8000-00000000d131'),
 '55000','analysis_history_admission_required','bound child funding denied with same or different request identity across owners')
 FROM unnest(ARRAY['00000000-0000-4000-8000-00000000d101','00000000-0000-4000-8000-00000000d102']) owner
 CROSS JOIN unnest(ARRAY['00000000-0000-4000-8000-00000000d131','00000000-0000-4000-8000-00000000d141']) request;
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d131'),0::BIGINT,'denial creates no quota reservation');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d131'),0::BIGINT,'denial creates no complimentary hold');
CREATE TEMP TABLE invocation_fixture AS SELECT * FROM pg_temp.seed_invocation();
-- Trusted fixture models a conflicting old writer; no production API can insert
-- these private rows. New guard must reject before quota is committed.
UPDATE internal.ai_quota_reservations SET original_analysis_id='00000000-0000-4000-8000-00000000d131' WHERE id=(SELECT reservation FROM invocation_fixture);
SELECT extensions.throws_ok(format('SELECT * FROM pg_temp.commit_invocation(%L,%L,%L,1)',reservation,owner_id,token),'55000','analysis_history_dispatch_required','bound child cannot acquire provider dispatch') FROM invocation_fixture;
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT reservation FROM invocation_fixture)),'reserved','denied dispatch leaves original quota unchanged');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE reservation_id=(SELECT reservation FROM invocation_fixture)),0::BIGINT,'denial records no invocation');
UPDATE internal.ai_quota_reservations SET original_analysis_id=(SELECT scan FROM invocation_fixture),request_id='00000000-0000-4000-8000-00000000d131' WHERE id=(SELECT reservation FROM invocation_fixture);
SELECT extensions.ok((SELECT may_dispatch FROM invocation_fixture,LATERAL pg_temp.commit_invocation(reservation,owner_id,token,1)),'unbound original remains eligible even when request UUID equals another bound child');
SELECT extensions.ok(NOT (SELECT may_dispatch FROM invocation_fixture,LATERAL pg_temp.commit_invocation(reservation,owner_id,token,1)),'exact prior invocation replay never dispatches twice');
SELECT * FROM extensions.finish();
ROLLBACK;
