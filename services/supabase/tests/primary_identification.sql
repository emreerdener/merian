\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(7);

CREATE TEMP TABLE primary_fixture (owner_id UUID, other_id UUID, scan_id UUID, provenance JSONB, snapshot JSONB);
INSERT INTO primary_fixture VALUES (
    '00000000-0000-0000-0000-00000000bd01', '00000000-0000-0000-0000-00000000bd02', '00000000-0000-0000-0000-00000000bd11',
    '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"synthetic_primary_fixture_v1","schema":"merian_identify_primary_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}',
    '{"version":1,"resolution":"genus","scientific_name":"Examplea","common_name":"Synthetic genus"}'
);
GRANT SELECT ON primary_fixture TO anon, authenticated, service_role;

DO $bounds$
DECLARE value JSONB; invalid JSONB; state TEXT;
BEGIN
    SELECT snapshot INTO value FROM primary_fixture;
    IF NOT internal.primary_identification_is_valid(NULL) THEN RAISE EXCEPTION 'legacy null rejected'; END IF;
    FOREACH state IN ARRAY ARRAY['species','genus','family','unresolved_biological','non_biological'] LOOP
        IF NOT internal.primary_identification_is_valid(value || JSONB_BUILD_OBJECT('resolution', state, 'scientific_name',
            CASE WHEN state = 'unresolved_biological' THEN NULL ELSE 'Examplea' END)) THEN
            RAISE EXCEPTION 'supported state rejected';
        END IF;
    END LOOP;
    FOR invalid IN SELECT bad FROM (VALUES
        ('null'::JSONB), ('[]'::JSONB), ('{}'::JSONB), (value || '{"extra":true}'),
        (value - 'common_name'), (value || '{"version":2}'), (value || '{"version":"1"}'),
        (value || '{"resolution":null}'), (value || '{"resolution":"subspecies"}'),
        (value || '{"scientific_name":null}'), (value || '{"common_name":""}'),
        (value || '{"common_name":" leading"}'), (value || JSONB_BUILD_OBJECT('common_name', 'trailing' || U&'\00A0')),
        (value || JSONB_BUILD_OBJECT('common_name', E'syn\nthetic')),
        (value || JSONB_BUILD_OBJECT('common_name', 'syn' || CHR(127) || 'thetic')),
        (value || JSONB_BUILD_OBJECT('common_name', REPEAT('x',256))),
        (value || JSONB_BUILD_OBJECT('common_name', REPEAT(U&'\+01F98B',128))),
        (value || '{"resolution":"unresolved_biological"}')
    ) AS invalids(bad) LOOP
        IF internal.primary_identification_is_valid(invalid) THEN RAISE EXCEPTION 'invalid snapshot accepted'; END IF;
    END LOOP;
    IF NOT internal.primary_identification_is_valid(value || JSONB_BUILD_OBJECT('common_name', REPEAT(U&'\+01F98B',127))) THEN
        RAISE EXCEPTION 'valid UTF-16 boundary rejected';
    END IF;
END;
$bounds$;
SELECT extensions.pass('strict snapshot states, required nulls, names and Unicode bounds');

DO $catalog$
DECLARE role_name TEXT; signature TEXT; routine pg_catalog.pg_proc%ROWTYPE;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
        IF HAS_COLUMN_PRIVILEGE(role_name,'public.scans','primary_identification','INSERT')
           OR HAS_COLUMN_PRIVILEGE(role_name,'public.scans','primary_identification','UPDATE')
           OR HAS_COLUMN_PRIVILEGE(role_name,'public.scan_ingestion_jobs','primary_identification','INSERT')
           OR HAS_COLUMN_PRIVILEGE(role_name,'public.scan_ingestion_jobs','primary_identification','UPDATE') THEN
            RAISE EXCEPTION 'client snapshot write exposed';
        END IF;
    END LOOP;
    FOREACH signature IN ARRAY ARRAY['internal.guard_scan_primary_identification()', 'internal.guard_job_primary_identification()', 'internal.copy_scan_identification_provenance()'] LOOP
        SELECT * INTO STRICT routine FROM pg_catalog.pg_proc WHERE oid = signature::REGPROCEDURE;
        IF NOT routine.prosecdef OR routine.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN RAISE EXCEPTION 'trigger authority drift'; END IF;
        FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            IF HAS_FUNCTION_PRIVILEGE(role_name, routine.oid, 'EXECUTE') THEN RAISE EXCEPTION 'direct trigger execution exposed'; END IF;
        END LOOP;
    END LOOP;
    SELECT * INTO STRICT routine FROM pg_catalog.pg_proc WHERE oid = 'internal.require_identification_result_reader(jsonb,jsonb)'::REGPROCEDURE;
    IF routine.prosecdef OR routine.provolatile <> 'v' OR routine.proconfig IS DISTINCT FROM ARRAY['search_path=""']
       OR HAS_FUNCTION_PRIVILEGE('service_role',routine.oid,'EXECUTE')
       OR NOT HAS_FUNCTION_PRIVILEGE('authenticated',routine.oid,'EXECUTE')
       OR NOT HAS_FUNCTION_PRIVILEGE('anon',routine.oid,'EXECUTE') THEN RAISE EXCEPTION 'reader authority drift'; END IF;
    IF EXISTS (SELECT 1 FROM internal.identification_provider_bindings WHERE minimum_identification_protocol NOT IN (0,4)) THEN
        RAISE EXCEPTION 'future producer activated';
    END IF;
END;
$catalog$;
SELECT extensions.pass('server-owned columns, fixed trigger authority and unchanged binding minima');

DO $setup$
DECLARE fixture primary_fixture%ROWTYPE;
BEGIN
    SELECT * INTO fixture FROM primary_fixture;
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES (fixture.owner_id,'authenticated','authenticated','primary-owner@example.invalid','{}','{}',NOW(),NOW()),
           (fixture.other_id,'authenticated','authenticated','primary-other@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,endpoint) VALUES (fixture.scan_id::TEXT,fixture.owner_id,'identify-multimodal');
    PERFORM SET_CONFIG('request.jwt.claims', JSONB_BUILD_OBJECT('role','service_role')::TEXT,TRUE);
    SET LOCAL ROLE service_role;
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,is_live_capture,inference_tier,geoprivacy,identification_provenance,primary_identification)
    VALUES (fixture.scan_id,fixture.owner_id,'{}',0.75,TRUE,TRUE,'flash','open',fixture.provenance,fixture.snapshot);
    RESET ROLE;
    IF NOT EXISTS (SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=fixture.scan_id::TEXT AND user_id=fixture.owner_id
        AND primary_identification=fixture.snapshot AND identification_provenance=fixture.provenance) THEN
        RAISE EXCEPTION 'primary and provenance not copied atomically';
    END IF;
END;
$setup$;
SELECT extensions.pass('first owner insertion copies one matching immutable generation atomically');

DO $integrity$
DECLARE fixture primary_fixture%ROWTYPE; denied BOOLEAN; changed JSONB; new_id UUID;
BEGIN
    SELECT * INTO fixture FROM primary_fixture;
    changed := fixture.snapshot || '{"common_name":"Changed label"}';
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,identification_provenance,primary_identification)
    VALUES (fixture.scan_id,fixture.owner_id,'{}',0.75,TRUE,fixture.provenance,changed) ON CONFLICT(id) DO NOTHING;
    IF (SELECT primary_identification FROM public.scans WHERE id=fixture.scan_id) IS DISTINCT FROM fixture.snapshot THEN RAISE EXCEPTION 'duplicate replaced primary'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET primary_identification=changed WHERE id=fixture.scan_id;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'scan mutation accepted'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scan_ingestion_jobs SET primary_identification=NULL WHERE scan_id=fixture.scan_id::TEXT;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'backup erased'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET is_biological_subject=FALSE WHERE id=fixture.scan_id;
    EXCEPTION WHEN check_violation THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'broader subject changed'; END IF;
    denied := FALSE;
    BEGIN UPDATE public.scans SET candidates='[]' WHERE id=fixture.scan_id;
    EXCEPTION WHEN check_violation THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'broader alternatives accepted'; END IF;
    new_id := '00000000-0000-0000-0000-00000000bd19';
    denied := FALSE;
    BEGIN INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,identification_provenance,primary_identification)
        VALUES (new_id,fixture.owner_id,'{}',0.75,TRUE,fixture.provenance,fixture.snapshot);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied OR EXISTS (SELECT 1 FROM public.scans WHERE id=new_id) THEN RAISE EXCEPTION 'missing job left partial scan'; END IF;
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,identification_provenance,primary_identification)
    VALUES (new_id::TEXT,fixture.owner_id,fixture.provenance,changed);
    denied := FALSE;
    BEGIN INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,identification_provenance,primary_identification)
        VALUES (new_id,fixture.owner_id,'{}',0.75,TRUE,fixture.provenance,fixture.snapshot);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied OR EXISTS (SELECT 1 FROM public.scans WHERE id=new_id) THEN RAISE EXCEPTION 'conflicting job left partial scan'; END IF;
    denied := FALSE;
    BEGIN INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,identification_provenance)
        VALUES ('00000000-0000-0000-0000-00000000bd20',fixture.owner_id,fixture.provenance);
    EXCEPTION WHEN check_violation THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'required snapshot loss became legacy'; END IF;
    denied := FALSE;
    BEGIN INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,primary_identification)
        VALUES ('00000000-0000-0000-0000-00000000bd20',fixture.owner_id,fixture.snapshot);
    EXCEPTION WHEN check_violation THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'snapshot without required provenance accepted'; END IF;
END;
$integrity$;
SELECT extensions.pass('duplicate, immutable, contradictory, missing and mismatched generations fail atomically');

DO $recovery$
DECLARE fixture primary_fixture%ROWTYPE; recovered_id UUID := '00000000-0000-0000-0000-00000000bd21'; payload JSONB; outcome TEXT; denied BOOLEAN;
BEGIN
    SELECT * INTO fixture FROM primary_fixture;
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code,identification_provenance,primary_identification)
    VALUES (recovered_id::TEXT,fixture.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted',fixture.provenance,fixture.snapshot);
    payload := JSONB_BUILD_OBJECT('id',recovered_id,'user_id',fixture.owner_id,'image_storage_urls','[]'::JSONB,
        'timestamp',NOW(),'geoprivacy','private','ecology_type','unknown','ai_confidence_score',0.75,
        'is_invasive',FALSE,'is_live_capture',FALSE,'is_biological_subject',FALSE,'user_confirmed_identification',FALSE,
        'user_review_state','unreviewed','inference_tier','flash',
        'primary_identification',fixture.snapshot || '{"resolution":"species"}');
    SET LOCAL ROLE service_role;
    denied:=FALSE;
    BEGIN PERFORM public.recover_missing_owned_scan(recovered_id,fixture.owner_id,payload);
    EXCEPTION WHEN check_violation THEN denied:=TRUE; END;
    IF NOT denied OR EXISTS (SELECT 1 FROM public.scans WHERE id=recovered_id) THEN RAISE EXCEPTION 'conflicting recovery partially restored'; END IF;
    payload := payload || '{"is_biological_subject":true}';
    SELECT public.recover_missing_owned_scan(recovered_id,fixture.owner_id,payload) INTO outcome;
    IF outcome <> 'recovered' OR NOT EXISTS (SELECT 1 FROM public.scans WHERE id=recovered_id
        AND primary_identification=fixture.snapshot AND identification_provenance=fixture.provenance AND species_id IS NULL) THEN
        RAISE EXCEPTION 'recovery trusted client rank or lost server answer';
    END IF;
    RESET ROLE;
END;
$recovery$;
SELECT extensions.pass('missing-row recovery ignores forged primary JSON and enforces the trusted subject');

DO $readers$
DECLARE fixture primary_fixture%ROWTYPE; caller TEXT; claim TEXT; denied BOOLEAN; received JSONB;
BEGIN
    SELECT * INTO fixture FROM primary_fixture;
    PERFORM SET_CONFIG('request.jwt.claims',JSONB_BUILD_OBJECT('role','authenticated','sub',fixture.owner_id)::TEXT,TRUE);
    FOREACH claim IN ARRAY ARRAY['{}','{"x-merian-identification-protocol":"4"}','{"x-merian-identification-protocol":"7"}',
        '{"x-merian-identification-protocol":5}','{"x-merian-identification-protocol":"05"}'] LOOP
        PERFORM SET_CONFIG('request.headers',claim,TRUE);
        FOREACH caller IN ARRAY ARRAY['anon','authenticated'] LOOP
            EXECUTE FORMAT('SET LOCAL ROLE %I',caller);
            denied:=FALSE;
            BEGIN PERFORM id FROM public.scans WHERE id=fixture.scan_id;
            EXCEPTION WHEN SQLSTATE 'PT426' THEN denied:=TRUE; END;
            IF NOT denied THEN RAISE EXCEPTION 'older/unknown reader consumed primary result'; END IF;
            RESET ROLE;
        END LOOP;
    END LOOP;
    PERFORM SET_CONFIG('request.headers','{"x-merian-identification-protocol":"5"}',TRUE);
    FOREACH caller IN ARRAY ARRAY['anon','authenticated'] LOOP
        EXECUTE FORMAT('SET LOCAL ROLE %I',caller);
        SELECT primary_identification INTO received FROM public.scans WHERE id=fixture.scan_id;
        IF received IS DISTINCT FROM fixture.snapshot THEN RAISE EXCEPTION 'capable reader lost labels'; END IF;
        RESET ROLE;
    END LOOP;
    SET LOCAL ROLE authenticated;
    UPDATE public.scans SET custom_tags=ARRAY['synthetic'] WHERE id=fixture.scan_id;
    denied:=FALSE;
    BEGIN UPDATE public.scans SET primary_identification=NULL WHERE id=fixture.scan_id;
    EXCEPTION WHEN insufficient_privilege THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'reader capability granted writes'; END IF;
    RESET ROLE;
    PERFORM SET_CONFIG('request.jwt.claims',JSONB_BUILD_OBJECT('role','authenticated','sub',fixture.other_id)::TEXT,TRUE);
    PERFORM SET_CONFIG('request.headers','{}',TRUE);
    SET LOCAL ROLE authenticated;
    IF EXISTS (SELECT 1 FROM public.scans WHERE id='00000000-0000-0000-0000-00000000bd21') THEN RAISE EXCEPTION 'private snapshot exposed'; END IF;
    RESET ROLE;
    PERFORM SET_CONFIG('request.headers','{"x-merian-identification-protocol":"4"}',TRUE);
    -- API roles cannot name the internal schema directly; policy invocation
    -- above exercises their real access. Test the compatibility wrapper as owner.
    denied:=FALSE;
    BEGIN PERFORM internal.require_identification_result_reader(fixture.provenance);
    EXCEPTION WHEN SQLSTATE 'PT426' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'legacy helper lost required-schema marker'; END IF;
    RESET ROLE;
END;
$readers$;
SELECT extensions.pass('exact reader 5, visibility-first errors, legacy wrapper and bounded owner writes');

DO $species$
DECLARE value JSONB; candidate JSONB;
BEGIN
    SELECT snapshot || '{"resolution":"species"}' INTO value FROM primary_fixture;
    candidate := '{"scientific_name":"Examplea altera","confidence_score":0.2,"distinguishing_feature":"Synthetic difference","taxon_rank":"species"}';
    IF NOT internal.primary_identification_scan_is_valid(value,TRUE,NULL,'[]',NULL)
       OR NOT internal.primary_identification_scan_is_valid(value,TRUE,NULL,JSONB_BUILD_ARRAY(candidate,candidate),NULL)
       OR internal.primary_identification_scan_is_valid(value,TRUE,NULL,JSONB_BUILD_ARRAY(candidate,candidate,candidate),NULL)
       OR internal.primary_identification_scan_is_valid(value,TRUE,NULL,JSONB_BUILD_ARRAY(candidate - 'taxon_rank'),NULL)
       OR internal.primary_identification_scan_is_valid(value,TRUE,NULL,JSONB_BUILD_ARRAY(candidate || '{"taxon_rank":"genus"}'),NULL)
       OR internal.primary_identification_scan_is_valid(value || '{"resolution":"genus"}',TRUE,'00000000-0000-0000-0000-00000000bd99',NULL,NULL) THEN
        RAISE EXCEPTION 'species-effect boundary failed';
    END IF;
END;
$species$;
SELECT extensions.pass('species alternatives need explicit rank; broader results cannot link a species');
SELECT * FROM extensions.finish();
ROLLBACK;
