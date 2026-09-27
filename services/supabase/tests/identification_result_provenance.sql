\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    owner_id UUID := '00000000-0000-0000-0000-00000000ba01';
    v_scan_id UUID := '00000000-0000-0000-0000-00000000ba02';
    recovered_id UUID := '00000000-0000-0000-0000-00000000ba03';
    legacy_id UUID := '00000000-0000-0000-0000-00000000ba04';
    missing_job_id UUID := '00000000-0000-0000-0000-00000000ba05';
    conflicting_id UUID := '00000000-0000-0000-0000-00000000ba06';
    value JSONB := '{"version":1,"provider":"gemini","binding":"gemini_baseline_v1","model":"gemini-2.5-flash","variant":"description_compat","operation":"scan_identification","policy_version":1,"prompt":"identify_describe_v1","schema":"merian_describe_v1","confidence":"gemini_describe_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":null,"timeout_ms":90000,"generation":{"temperature":0.15,"seed":42,"top_k":40,"max_output_tokens":2048,"thinking_budget":1024}}'::JSONB;
    changed JSONB;
    invalid JSONB;
    payload JSONB;
    result TEXT;
    denied BOOLEAN;
    role_name TEXT;
BEGIN
    changed := pg_catalog.JSONB_SET(value, '{policy_version}', '2');
    IF NOT internal.identification_provenance_is_valid(value)
       OR NOT internal.identification_provenance_is_valid(NULL) THEN
        RAISE EXCEPTION 'valid or historical provenance rejected';
    END IF;
    FOR invalid IN SELECT invalids.bad FROM (VALUES
        ('{}'::JSONB), ('[]'::JSONB), ('null'::JSONB),
        (value || '{"observation":"synthetic private evidence"}'),
        (value - 'model'), (value || '{"model":null}'),
        (value || '{"provider":"unbounded free text"}'),
        (value || '{"version":2}'), (value || '{"policy_version":"1"}'),
        (value || '{"diagnostic_trigger":1.1}'), (value || '{"generation":[]}'),
        (pg_catalog.JSONB_SET(value, '{generation,temperature}', '-1')),
        (pg_catalog.JSONB_SET(value, '{generation,seed}', '"42"')),
        (pg_catalog.JSONB_SET(value, '{generation,max_output_tokens}', 'null')),
        (pg_catalog.JSONB_SET(value, '{generation,max_output_tokens}', '0')),
        (pg_catalog.JSONB_SET(value, '{generation,prompt}', '"synthetic prompt"'))
    ) AS invalids(bad) LOOP
        IF internal.identification_provenance_is_valid(invalid) THEN RAISE EXCEPTION 'invalid provenance accepted'; END IF;
    END LOOP;
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        IF pg_catalog.HAS_COLUMN_PRIVILEGE(role_name, 'public.scans', 'identification_provenance', 'INSERT')
           OR pg_catalog.HAS_COLUMN_PRIVILEGE(role_name, 'public.scans', 'identification_provenance', 'UPDATE')
           OR pg_catalog.HAS_COLUMN_PRIVILEGE(role_name, 'public.scan_ingestion_jobs', 'identification_provenance', 'INSERT')
           OR pg_catalog.HAS_COLUMN_PRIVILEGE(role_name, 'public.scan_ingestion_jobs', 'identification_provenance', 'UPDATE') THEN
            RAISE EXCEPTION 'client provenance write privilege exposed';
        END IF;
    END LOOP;
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (owner_id, 'authenticated', 'authenticated', 'provenance-fixture@example.invalid', '{}', '{}', pg_catalog.NOW(), pg_catalog.NOW());
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims', pg_catalog.JSONB_BUILD_OBJECT('role','service_role','sub',owner_id)::TEXT, TRUE);
    INSERT INTO public.scan_ingestion_jobs (scan_id, user_id, endpoint) VALUES (v_scan_id::TEXT, owner_id, 'identify-describe');
    SET LOCAL ROLE service_role;
    INSERT INTO public.scans (id, user_id, image_storage_urls, ai_confidence_score, is_biological_subject, is_live_capture, inference_tier, geoprivacy, identification_provenance)
    VALUES (v_scan_id, owner_id, '{}', 0.75, FALSE, TRUE, 'flash', 'open', value);
    RESET ROLE;
    IF (SELECT identification_provenance FROM public.scan_ingestion_jobs WHERE scan_id = v_scan_id::TEXT) IS DISTINCT FROM value THEN
        RAISE EXCEPTION 'scan insert did not atomically retain server backup';
    END IF;
    INSERT INTO public.scans (id, user_id, image_storage_urls, ai_confidence_score, is_biological_subject, identification_provenance)
    VALUES (v_scan_id, owner_id, '{}', 0.75, FALSE, changed) ON CONFLICT (id) DO NOTHING;
    IF (SELECT identification_provenance FROM public.scans WHERE id = v_scan_id) IS DISTINCT FROM value
       OR (SELECT identification_provenance FROM public.scan_ingestion_jobs WHERE scan_id = v_scan_id::TEXT) IS DISTINCT FROM value THEN
        RAISE EXCEPTION 'duplicate replaced original provenance';
    END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET identification_provenance = changed WHERE id = v_scan_id;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'scan provenance mutation accepted'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scan_ingestion_jobs SET identification_provenance = NULL WHERE scan_id = v_scan_id::TEXT;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'job provenance mutation accepted'; END IF;
    denied := FALSE;
    BEGIN INSERT INTO public.scans (id, user_id, image_storage_urls, ai_confidence_score, is_biological_subject, identification_provenance)
        VALUES (missing_job_id, owner_id, '{}', 0.75, FALSE, value);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied OR EXISTS (SELECT 1 FROM public.scans WHERE id = missing_job_id) THEN RAISE EXCEPTION 'missing backup job left partial scan'; END IF;
    INSERT INTO public.scan_ingestion_jobs (scan_id, user_id, identification_provenance) VALUES (conflicting_id::TEXT, owner_id, changed);
    denied := FALSE;
    BEGIN INSERT INTO public.scans (id, user_id, image_storage_urls, ai_confidence_score, is_biological_subject, identification_provenance)
        VALUES (conflicting_id, owner_id, '{}', 0.75, FALSE, value);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied OR EXISTS (SELECT 1 FROM public.scans WHERE id = conflicting_id) THEN RAISE EXCEPTION 'conflicting backup left partial scan'; END IF;
    -- Synthetic server-owned receipt models a missing historical row. Keep all
    -- production triggers and normal recovery authority/finalizer active.
    INSERT INTO public.scan_ingestion_jobs (scan_id, user_id, status, stage, terminal_reason_code, identification_provenance)
    VALUES (recovered_id::TEXT, owner_id, 'failed_terminal', 'server_replay_limit_reached', 'replay_exhausted', value),
           (legacy_id::TEXT, owner_id, 'failed_terminal', 'server_replay_limit_reached', 'replay_exhausted', NULL);
    payload := pg_catalog.JSONB_BUILD_OBJECT(
        'id', recovered_id, 'user_id', owner_id, 'image_storage_urls', '[]'::JSONB,
        'timestamp', pg_catalog.NOW(), 'geoprivacy', 'private', 'ecology_type', 'unknown',
        'ai_confidence_score', 0.75, 'is_invasive', FALSE, 'is_live_capture', FALSE,
        'is_biological_subject', FALSE, 'user_confirmed_identification', FALSE,
        'user_review_state', 'unreviewed', 'inference_tier', 'flash', 'identification_provenance', changed);
    SET LOCAL ROLE service_role;
    SELECT public.recover_missing_owned_scan(recovered_id, owner_id, payload) INTO result;
    IF result <> 'recovered' OR (SELECT identification_provenance FROM public.scans WHERE id = recovered_id) IS DISTINCT FROM value THEN
        RAISE EXCEPTION 'recovery did not restore only server provenance: %', result;
    END IF;
    SELECT public.recover_missing_owned_scan(legacy_id, owner_id, pg_catalog.JSONB_SET(payload,'{id}',pg_catalog.TO_JSONB(legacy_id))) INTO result;
    IF result <> 'recovered' OR (SELECT identification_provenance FROM public.scans WHERE id = legacy_id) IS NOT NULL THEN
        RAISE EXCEPTION 'legacy recovery fabricated provenance: %', result;
    END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET identification_provenance = value WHERE id = legacy_id;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'legacy backfill fabricated provenance'; END IF;
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims', pg_catalog.JSONB_BUILD_OBJECT('role','authenticated','sub',owner_id)::TEXT, TRUE);
    SET LOCAL ROLE authenticated;
    denied := FALSE;
    BEGIN UPDATE public.scans SET identification_provenance = changed WHERE id = v_scan_id;
    EXCEPTION WHEN insufficient_privilege THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'authenticated write accepted'; END IF;
    UPDATE public.scans SET custom_tags = ARRAY['synthetic'] WHERE id = v_scan_id;
    SET LOCAL ROLE anon;
    IF (SELECT identification_provenance FROM public.scans WHERE id = v_scan_id) IS DISTINCT FROM value THEN
        RAISE EXCEPTION 'fixed provenance visibility differs from scan visibility';
    END IF;
    RESET ROLE;
    UPDATE public.scans SET is_tombstoned = TRUE, user_id = NULL WHERE user_id = owner_id;
    DELETE FROM public.users WHERE id = owner_id;
    DELETE FROM auth.users WHERE id = owner_id;
    IF (SELECT identification_provenance FROM public.scans WHERE id = v_scan_id) IS DISTINCT FROM value
       OR EXISTS (SELECT 1 FROM public.scan_ingestion_jobs WHERE user_id = owner_id) THEN
        RAISE EXCEPTION 'owner deletion provenance lifecycle mismatch';
    END IF;
END;
$test$;
SELECT extensions.pass('durable provenance: bounds, atomicity, immutability, recovery, visibility and owner lifecycle');
SELECT * FROM extensions.finish();
ROLLBACK;
