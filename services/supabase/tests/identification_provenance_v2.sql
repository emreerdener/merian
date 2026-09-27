\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    owner_id UUID := '00000000-0000-0000-0000-00000000bb01';
    v_scan_id UUID := '00000000-0000-0000-0000-00000000bb02';
    recovered_id UUID := '00000000-0000-0000-0000-00000000bb03';
    value JSONB := '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"openai_identify_vision_v1","schema":"merian_openai_identify_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'::JSONB;
    invalid JSONB;
    payload JSONB;
    result TEXT;
    denied BOOLEAN;
    identifier TEXT;
BEGIN
    IF NOT internal.identification_provenance_is_valid(value) THEN
        RAISE EXCEPTION 'OpenAI v2 provenance rejected';
    END IF;
    IF internal.identification_metrics_are_gemini_compatible(value, 'pro')
       OR internal.identification_metrics_are_gemini_compatible(value, 'flash') THEN
        RAISE EXCEPTION 'OpenAI v2 inherited Gemini metrics';
    END IF;
    FOR invalid IN SELECT bad FROM (VALUES
        (value || '{"version":1}'), (value || '{"version":3}'),
        (value || '{"version":"2"}'), (value || '{"provider":"gemini"}'),
        (value || '{"variant":"future_variant"}'), (value || '{"operation":"future_operation"}'),
        (value || '{"observation":"synthetic evidence"}'),
        (value || '{"generation":{"temperature":0.1,"seed":42,"top_k":null,"max_output_tokens":8192,"thinking_budget":null}}'),
        (pg_catalog.JSONB_SET(value, '{generation,seed}', 'null')),
        (pg_catalog.JSONB_SET(value, '{generation,image_detail}', 'null')),
        (pg_catalog.JSONB_SET(value, '{generation,reasoning_effort}', '""')),
        (pg_catalog.JSONB_SET(value, '{generation,reasoning_effort}', '"unbounded free text"')),
        (pg_catalog.JSONB_SET(value, '{generation,image_detail}', pg_catalog.TO_JSONB(E'high\n'::TEXT))),
        (pg_catalog.JSONB_SET(value, '{generation,max_output_tokens}', '0')),
        (pg_catalog.JSONB_SET(value, '{generation,max_output_tokens}', '1.5')),
        (pg_catalog.JSONB_SET(value, '{generation,max_output_tokens}', '1000000000')),
        (value #- '{generation,image_detail}')
    ) AS invalids(bad) LOOP
        IF internal.identification_provenance_is_valid(invalid) THEN RAISE EXCEPTION 'malformed v2 accepted'; END IF;
    END LOOP;
    FOREACH identifier IN ARRAY ARRAY['binding', 'model', 'variant', 'operation', 'prompt', 'schema', 'confidence', 'safety'] LOOP
        IF internal.identification_provenance_is_valid(pg_catalog.JSONB_SET(value, ARRAY[identifier], '"free text"'))
           OR internal.identification_provenance_is_valid(pg_catalog.JSONB_SET(value, ARRAY[identifier], pg_catalog.TO_JSONB(E'token\n'::TEXT))) THEN
            RAISE EXCEPTION 'malformed v2 identifier accepted';
        END IF;
    END LOOP;
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (owner_id, 'authenticated', 'authenticated', 'provenance-v2@example.invalid', '{}', '{}', pg_catalog.NOW(), pg_catalog.NOW());
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims', pg_catalog.JSONB_BUILD_OBJECT('role','service_role','sub',owner_id)::TEXT, TRUE);
    INSERT INTO public.scan_ingestion_jobs (scan_id, user_id, endpoint) VALUES (v_scan_id::TEXT, owner_id, 'identify-multimodal');
    SET LOCAL ROLE service_role;
    INSERT INTO public.scans (id, user_id, image_storage_urls, ai_confidence_score, is_biological_subject, identification_provenance)
    VALUES (v_scan_id, owner_id, '{}', 0.99, FALSE, value);
    RESET ROLE;
    IF (SELECT jobs.identification_provenance FROM public.scan_ingestion_jobs AS jobs WHERE jobs.scan_id = v_scan_id::TEXT) IS DISTINCT FROM value THEN
        RAISE EXCEPTION 'v2 backup lost metadata';
    END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET identification_provenance = NULL WHERE id = v_scan_id;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'v2 scan metadata mutated'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scan_ingestion_jobs AS jobs SET identification_provenance = NULL WHERE jobs.scan_id = v_scan_id::TEXT;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'v2 backup metadata mutated'; END IF;
    RESET ROLE;
    INSERT INTO public.scan_ingestion_jobs (scan_id, user_id, status, stage, terminal_reason_code, identification_provenance)
    VALUES (recovered_id::TEXT, owner_id, 'failed_terminal', 'server_replay_limit_reached', 'replay_exhausted', value);
    payload := pg_catalog.JSONB_BUILD_OBJECT(
        'id', recovered_id, 'user_id', owner_id, 'image_storage_urls', '[]'::JSONB,
        'timestamp', pg_catalog.NOW(), 'geoprivacy', 'private', 'ecology_type', 'unknown',
        'ai_confidence_score', 0.99, 'is_invasive', FALSE, 'is_live_capture', FALSE,
        'is_biological_subject', FALSE, 'user_confirmed_identification', FALSE,
        'user_review_state', 'unreviewed', 'inference_tier', 'flash', 'identification_provenance', NULL);
    SET LOCAL ROLE service_role;
    SELECT public.recover_missing_owned_scan(recovered_id, owner_id, payload) INTO result;
    IF result <> 'recovered' OR (SELECT identification_provenance FROM public.scans WHERE id = recovered_id) IS DISTINCT FROM value THEN
        RAISE EXCEPTION 'v2 recovery lost server metadata';
    END IF;
    RESET ROLE;
END;
$test$;
SELECT extensions.pass('OpenAI v2 metadata is bounded, unqualified, immutable and recoverable');
SELECT * FROM extensions.finish();
ROLLBACK;
