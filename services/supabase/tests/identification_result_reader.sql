\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(8);

CREATE TEMP TABLE reader_fixture (owner_id UUID, other_id UUID, provenance JSONB);
INSERT INTO reader_fixture VALUES (
    '00000000-0000-0000-0000-00000000bc01',
    '00000000-0000-0000-0000-00000000bc02',
    '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"openai_identify_vision_v1","schema":"merian_openai_identify_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'
);
GRANT SELECT ON reader_fixture TO anon, authenticated, service_role;

DO $setup$
DECLARE
    fixture reader_fixture%ROWTYPE;
    v1 JSONB := '{"version":1,"provider":"gemini","binding":"gemini_baseline_v1","model":"gemini-2.5-flash","variant":"description_compat","operation":"scan_identification","policy_version":1,"prompt":"identify_describe_v1","schema":"merian_describe_v1","confidence":"gemini_describe_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":null,"timeout_ms":90000,"generation":{"temperature":0.15,"seed":42,"top_k":40,"max_output_tokens":2048,"thinking_budget":1024}}';
BEGIN
    SELECT * INTO fixture FROM reader_fixture;
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (fixture.owner_id, 'authenticated', 'authenticated', 'reader-owner@example.invalid', '{}', '{}', NOW(), NOW()),
           (fixture.other_id, 'authenticated', 'authenticated', 'reader-other@example.invalid', '{}', '{}', NOW(), NOW());
    INSERT INTO public.scan_ingestion_jobs (scan_id, user_id, endpoint)
    SELECT id, fixture.owner_id, 'identify-multimodal' FROM UNNEST(ARRAY[
        '00000000-0000-0000-0000-00000000bc11',
        '00000000-0000-0000-0000-00000000bc12',
        '00000000-0000-0000-0000-00000000bc13',
        '00000000-0000-0000-0000-00000000bc14',
        '00000000-0000-0000-0000-00000000bc15'
    ]) AS ids(id);
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role', 'service_role')::TEXT, TRUE);
    SET LOCAL ROLE service_role;
    INSERT INTO public.scans (id, user_id, image_storage_urls, ai_confidence_score, is_biological_subject, is_live_capture, inference_tier, geoprivacy, identification_provenance)
    VALUES
        ('00000000-0000-0000-0000-00000000bc11', fixture.owner_id, '{}', 0.99, FALSE, TRUE, 'flash', 'open', NULL),
        ('00000000-0000-0000-0000-00000000bc12', fixture.owner_id, '{}', 0.99, FALSE, TRUE, 'flash', 'open', v1),
        ('00000000-0000-0000-0000-00000000bc13', fixture.owner_id, '{}', 0.99, FALSE, TRUE, 'pro', 'private', fixture.provenance),
        ('00000000-0000-0000-0000-00000000bc14', fixture.owner_id, ARRAY['https://example.invalid/reader.jpg'], 0.99, FALSE, TRUE, 'pro', 'open', fixture.provenance),
        ('00000000-0000-0000-0000-00000000bc15', fixture.owner_id, '{}', 0.99, FALSE, FALSE, 'pro', 'open', fixture.provenance);
    RESET ROLE;
END;
$setup$;

DO $catalog$
DECLARE helper pg_catalog.pg_proc%ROWTYPE;
BEGIN
    SELECT * INTO STRICT helper FROM pg_catalog.pg_proc
    WHERE oid = 'internal.require_identification_result_reader(jsonb)'::REGPROCEDURE;
    IF helper.prosecdef OR helper.provolatile <> 'v' OR helper.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN
        RAISE EXCEPTION 'reader helper must be invoker, volatile and fixed-search-path';
    END IF;
    IF (SELECT COUNT(*) FROM pg_catalog.pg_policy WHERE polrelid = 'public.scans'::REGCLASS AND polcmd IN ('r', '*')) <> 2
       OR (SELECT COUNT(*) FROM pg_catalog.pg_policy WHERE polrelid = 'public.scans'::REGCLASS AND polcmd = 'r'
           AND pg_catalog.PG_GET_EXPR(polqual, polrelid) LIKE '%CASE%require_identification_result_reader%ELSE false%') <> 2 THEN
        RAISE EXCEPTION 'scan read policy bypass';
    END IF;
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', helper.oid, 'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_catalog.ACLEXPLODE(helper.proacl) WHERE grantee = 0 AND privilege_type = 'EXECUTE')
       OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('anon', helper.oid, 'EXECUTE')
       OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('authenticated', helper.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'reader helper ACL drift';
    END IF;
END;
$catalog$;
SELECT extensions.pass('reader policy and invoker ACL are bounded');

DO $legacy$
DECLARE caller TEXT; total BIGINT;
BEGIN
    PERFORM SET_CONFIG('request.headers', '', TRUE);
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role', 'authenticated', 'sub', (SELECT owner_id FROM reader_fixture))::TEXT, TRUE);
    FOREACH caller IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        EXECUTE FORMAT('SET LOCAL ROLE %I', caller);
        SELECT COUNT(*) INTO total FROM public.scans WHERE id IN ('00000000-0000-0000-0000-00000000bc11', '00000000-0000-0000-0000-00000000bc12');
        IF total <> 2 THEN RAISE EXCEPTION 'legacy rows unavailable'; END IF;
        RESET ROLE;
    END LOOP;
END;
$legacy$;
SELECT extensions.pass('null and V1 results remain readable without capability');

DO $legacy_denial$
DECLARE header_value TEXT; caller TEXT; denied BOOLEAN;
BEGIN
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role', 'authenticated', 'sub', (SELECT owner_id FROM reader_fixture))::TEXT, TRUE);
    FOREACH header_value IN ARRAY ARRAY['', '{}', 'broken', '[]', 'null',
        '{"x-merian-entitlement-protocol":"3"}', '{"x-merian-identification-protocol":"3"}',
        '{"x-merian-identification-protocol":"5"}', '{"x-merian-identification-protocol":"04"}',
        '{"x-merian-identification-protocol":"4 "}', '{"x-merian-identification-protocol":4}',
        '{"x-merian-identification-protocol":["4"]}', '{"x-merian-identification-protocol":null}',
        '{"X-Merian-Identification-Protocol":"4"}', REPEAT(' ', 32769)] LOOP
        PERFORM SET_CONFIG('request.headers', header_value, TRUE);
        FOREACH caller IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            EXECUTE FORMAT('SET LOCAL ROLE %I', caller);
            denied := FALSE;
            BEGIN
                -- An old main build omits provenance altogether; projection
                -- omission must not permit Gemini interpretation of V2 scores.
                PERFORM id, ai_confidence_score, inference_tier FROM public.scans
                WHERE id = '00000000-0000-0000-0000-00000000bc14';
            EXCEPTION WHEN SQLSTATE 'PT426' THEN
                IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
                denied := TRUE;
            END;
            IF NOT denied THEN RAISE EXCEPTION 'legacy V2 query did not require update'; END IF;
            RESET ROLE;
        END LOOP;
    END LOOP;
    PERFORM SET_CONFIG('request.headers', '{}', TRUE);
    SET LOCAL ROLE authenticated;
    denied := FALSE;
    BEGIN
        -- A V1-provenance reader selects a mixed history page. The request must
        -- fail, rather than returning a successful page with V2 silently absent.
        PERFORM id, identification_provenance FROM public.scans
        WHERE user_id = (SELECT owner_id FROM reader_fixture)
        ORDER BY timestamp DESC LIMIT 200;
    EXCEPTION WHEN SQLSTATE 'PT426' THEN denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'mixed page returned partial success'; END IF;
    RESET ROLE;
END;
$legacy_denial$;
SELECT extensions.pass('old projections, mixed pages and malformed capabilities fail with upgrade required');

DO $capable$
DECLARE expected JSONB; caller TEXT; received JSONB;
BEGIN
    SELECT provenance INTO expected FROM reader_fixture;
    PERFORM SET_CONFIG('request.headers', '{"x-merian-identification-protocol":"4"}', TRUE);
    FOREACH caller IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        EXECUTE FORMAT('SET LOCAL ROLE %I', caller);
        SELECT identification_provenance INTO received FROM public.scans WHERE id = '00000000-0000-0000-0000-00000000bc14';
        IF received IS DISTINCT FROM expected THEN RAISE EXCEPTION 'capable reader changed provenance'; END IF;
        RESET ROLE;
    END LOOP;
    SET LOCAL ROLE authenticated;
    IF (SELECT COUNT(*) FROM public.scans WHERE user_id = (SELECT owner_id FROM reader_fixture)) <> 5 THEN
        RAISE EXCEPTION 'capable owner lost history';
    END IF;
    RESET ROLE;
END;
$capable$;
SELECT extensions.pass('capability 4 reads all owner history and truthful public provenance');

DO $visibility$
DECLARE caller TEXT; header_value TEXT;
BEGIN
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role', 'authenticated', 'sub', (SELECT other_id FROM reader_fixture))::TEXT, TRUE);
    FOREACH header_value IN ARRAY ARRAY['{}', '{"x-merian-identification-protocol":"4"}'] LOOP
        PERFORM SET_CONFIG('request.headers', header_value, TRUE);
        FOREACH caller IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            EXECUTE FORMAT('SET LOCAL ROLE %I', caller);
            IF EXISTS (SELECT 1 FROM public.scans WHERE id IN ('00000000-0000-0000-0000-00000000bc13', '00000000-0000-0000-0000-00000000bc15')) THEN
                RAISE EXCEPTION 'capability widened private or non-live visibility';
            END IF;
            RESET ROLE;
        END LOOP;
    END LOOP;
    -- The original tombstone exclusion must remain true for capable readers.
    UPDATE public.scans SET is_tombstoned = TRUE WHERE id = '00000000-0000-0000-0000-00000000bc14';
    SET LOCAL ROLE anon;
    IF EXISTS (SELECT 1 FROM public.scans WHERE id = '00000000-0000-0000-0000-00000000bc14') THEN
        RAISE EXCEPTION 'reader exposed tombstoned row';
    END IF;
    RESET ROLE;
    UPDATE public.scans SET is_tombstoned = FALSE WHERE id = '00000000-0000-0000-0000-00000000bc14';
END;
$visibility$;
SELECT extensions.pass('capability never exposes private, non-live or tombstoned rows or their upgrade errors');

DO $writes$
DECLARE denied BOOLEAN; affected BIGINT;
BEGIN
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role', 'authenticated', 'sub', (SELECT owner_id FROM reader_fixture))::TEXT, TRUE);
    PERFORM SET_CONFIG('request.headers', '{}', TRUE);
    SET LOCAL ROLE authenticated;
    UPDATE public.scans SET custom_tags = ARRAY['legacy'] WHERE id = '00000000-0000-0000-0000-00000000bc11';
    denied := FALSE;
    BEGIN UPDATE public.scans SET custom_tags = ARRAY['blocked'] WHERE id = '00000000-0000-0000-0000-00000000bc13';
    EXCEPTION WHEN SQLSTATE 'PT426' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'legacy V2 update accepted'; END IF;
    PERFORM SET_CONFIG('request.headers', '{"x-merian-identification-protocol":"4"}', TRUE);
    UPDATE public.scans SET custom_tags = ARRAY['reviewed'] WHERE id = '00000000-0000-0000-0000-00000000bc13';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'capable owner metadata update failed'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET identification_provenance = NULL WHERE id = '00000000-0000-0000-0000-00000000bc13';
    EXCEPTION WHEN insufficient_privilege THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'reader capability granted provenance writes'; END IF;
    RESET ROLE;
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role', 'authenticated', 'sub', (SELECT other_id FROM reader_fixture))::TEXT, TRUE);
    SET LOCAL ROLE authenticated;
    UPDATE public.scans SET custom_tags = ARRAY['cross-owner'] WHERE id = '00000000-0000-0000-0000-00000000bc14';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN RAISE EXCEPTION 'capable reader changed another owner'; END IF;
    RESET ROLE;
END;
$writes$;
SELECT extensions.pass('legacy writes stay bounded and V2 writes require a capable owner');

DO $service$
BEGIN
    PERFORM SET_CONFIG('request.jwt.claims', '{"role":"service_role"}', TRUE);
    PERFORM SET_CONFIG('request.headers', '{}', TRUE);
    SET LOCAL ROLE service_role;
    IF (SELECT COUNT(*) FROM public.scans WHERE user_id = (SELECT owner_id FROM reader_fixture)) <> 5 THEN
        RAISE EXCEPTION 'service reader was restricted';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.get_filtered_discovery_feed((SELECT other_id FROM reader_fixture), 200)
                   WHERE id = '00000000-0000-0000-0000-00000000bc14') THEN
        RAISE EXCEPTION 'service feed lost V2';
    END IF;
    RESET ROLE;
END;
$service$;
SELECT extensions.pass('service reads and public product feed keep their reviewed authority');

DO $immutability$
BEGIN
    IF (SELECT COUNT(*) FROM public.scans WHERE user_id = (SELECT owner_id FROM reader_fixture)) <> 5
       OR EXISTS (SELECT 1 FROM public.scans WHERE id IN ('00000000-0000-0000-0000-00000000bc13', '00000000-0000-0000-0000-00000000bc14', '00000000-0000-0000-0000-00000000bc15')
           AND (identification_provenance IS DISTINCT FROM (SELECT provenance FROM reader_fixture) OR ai_confidence_score <> 0.99 OR inference_tier <> 'pro')) THEN
        RAISE EXCEPTION 'reader checks changed saved evidence';
    END IF;
    IF internal.identification_metrics_are_gemini_compatible((SELECT provenance FROM reader_fixture), 'pro') THEN
        RAISE EXCEPTION 'reader capability qualified an OpenAI score';
    END IF;
END;
$immutability$;
SELECT extensions.pass('reader checks preserve observations, scores and unqualified provenance');
SELECT * FROM extensions.finish();
ROLLBACK;
