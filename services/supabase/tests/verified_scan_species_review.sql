\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(12);
CREATE TEMP TABLE review_fixture AS SELECT
    '00000000-0000-0000-0000-00000000be01'::UUID owner_id,
    '00000000-0000-0000-0000-00000000be02'::UUID other_id,
    '00000000-0000-0000-0000-00000000be11'::UUID scan_id,
    '00000000-0000-0000-0000-00000000be12'::UUID species_scan_id,
    '00000000-0000-0000-0000-00000000be13'::UUID legacy_scan_id,
    '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"synthetic_primary_fixture_v1","schema":"merian_identify_primary_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'::JSONB provenance,
    '{"version":1,"resolution":"genus","scientific_name":"Reviewfixture","common_name":null}'::JSONB primary_answer,
    '{"scientific_name":"Reviewfixture accepted","gbif_taxon_key":987600001,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae"}'::JSONB proof;
GRANT SELECT ON review_fixture TO anon,authenticated,service_role;

DO $setup$
DECLARE f review_fixture%ROWTYPE;
BEGIN
    SELECT * INTO f FROM review_fixture;
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(f.owner_id,'authenticated','authenticated','review-owner@example.invalid','{}','{}',NOW(),NOW()),
          (f.other_id,'authenticated','authenticated','review-other@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(f.scan_id::TEXT,f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted'),
          (f.species_scan_id::TEXT,f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
    VALUES(f.scan_id,f.owner_id,'{}',0.75,TRUE,'flash','private',f.provenance,f.primary_answer),
          (f.species_scan_id,f.owner_id,'{}',0.75,TRUE,'flash','private',f.provenance,f.primary_answer || '{"resolution":"species","scientific_name":"Reviewfixture accepted"}'),
          (f.legacy_scan_id,f.owner_id,'{}',0.75,TRUE,'flash','private',NULL,NULL);
    IF NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=f.scan_id::TEXT
        AND confirmed_species_review -> 'revision'='0'::JSONB AND confirmed_species_review -> 'identity'='null'::JSONB) THEN RAISE EXCEPTION 'initial backup missing'; END IF;
END;
$setup$;
SELECT extensions.pass('initial explicit review has an owner-bound zero-revision backup; legacy stays untouched');

DO $permissions$
DECLARE role_name TEXT; column_name TEXT; denied BOOLEAN; f review_fixture%ROWTYPE;
BEGIN
    SELECT * INTO f FROM review_fixture;
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
        FOREACH column_name IN ARRAY ARRAY['confirmed_species_identity','confirmed_species_identity_revision'] LOOP
            IF HAS_COLUMN_PRIVILEGE(role_name,'public.scans',column_name,'INSERT') OR HAS_COLUMN_PRIVILEGE(role_name,'public.scans',column_name,'UPDATE') THEN RAISE EXCEPTION 'client authority grant'; END IF;
        END LOOP;
        IF HAS_COLUMN_PRIVILEGE(role_name,'public.scan_ingestion_jobs','confirmed_species_review','INSERT')
           OR HAS_COLUMN_PRIVILEGE(role_name,'public.scan_ingestion_jobs','confirmed_species_review','UPDATE')
           OR HAS_FUNCTION_PRIVILEGE(role_name,'public.apply_verified_scan_species_review(uuid,uuid,integer,text,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'client RPC/backup grant'; END IF;
        EXECUTE FORMAT('SET LOCAL ROLE %I',role_name);
        denied:=FALSE;
        BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.scan_id,0,'confirm_name','Reviewfixture accepted',f.proof);
        EXCEPTION WHEN insufficient_privilege THEN denied:=TRUE; END;
        IF NOT denied THEN RAISE EXCEPTION 'actual client called service routine'; END IF;
        RESET ROLE;
    END LOOP;
END;
$permissions$;
SELECT extensions.pass('actual API roles cannot write authority or invoke service confirmation');

DO $bounds$
DECLARE identity JSONB; invalid JSONB; valid JSONB;
BEGIN
    identity:='{"version":1,"species_id":"00000000-0000-0000-0000-00000000be99","scientific_name":"Reviewfixture accepted","common_name":null,"gbif_taxon_key":987600001}';
    IF NOT internal.confirmed_species_identity_is_valid(identity) THEN RAISE EXCEPTION 'identity rejected'; END IF;
    FOR invalid IN SELECT bad FROM (VALUES ('null'::JSONB),('{}'::JSONB),(identity - 'common_name'),(identity || '{"version":2}'),
      (identity || '{"gbif_taxon_key":0}'),(identity || '{"species_id":"fake"}'),(identity || '{"common_name":"invented"}'),
      (identity || '{"extra":true}'),(identity || JSONB_BUILD_OBJECT('scientific_name',REPEAT('a',161)))) AS cases(bad) LOOP
        IF internal.confirmed_species_identity_is_valid(invalid) THEN RAISE EXCEPTION 'invalid identity accepted'; END IF;
    END LOOP;
    SELECT confirmed_species_review INTO valid FROM public.scan_ingestion_jobs WHERE scan_id=(SELECT scan_id::TEXT FROM review_fixture);
    FOR invalid IN SELECT bad FROM (VALUES (valid || '{"revision":-1}'),(valid || '{"revision":2147483648}'),(valid || '{"revision":"1"}'),
      (valid - 'identity'),(valid || '{"extra":true}'),(valid || JSONB_BUILD_OBJECT('identity',identity)),(valid || '{"user_review_state":"unknown"}')) AS cases(bad) LOOP
        IF internal.confirmed_species_review_is_valid(invalid) THEN RAISE EXCEPTION 'invalid review accepted'; END IF;
    END LOOP;
END;
$bounds$;
SELECT extensions.pass('bounded version, revision, required nulls and coherent FK checks');

DO $apply$
DECLARE f review_fixture%ROWTYPE; receipt JSONB; repeated JSONB; denied BOOLEAN; species UUID;
BEGIN
    SELECT * INTO f FROM review_fixture;
    SET LOCAL ROLE service_role;
    receipt:=public.apply_verified_scan_species_review(f.owner_id,f.scan_id,0,'confirm_name','Reviewfixture synonym',f.proof);
    repeated:=public.apply_verified_scan_species_review(f.owner_id,f.scan_id,0,'confirm_name','Reviewfixture synonym',f.proof);
    IF receipt IS DISTINCT FROM repeated OR receipt #>> '{review,revision}' <> '1'
       OR receipt #> '{review,user_confirmed_identification}' <> 'false'::JSONB
       OR receipt #>> '{review,user_review_state}' <> 'user_overridden' THEN RAISE EXCEPTION 'idempotent legacy tuple mismatch'; END IF;
    species:=(receipt #>> '{review,identity,species_id}')::UUID;
    IF NOT EXISTS(SELECT 1 FROM public.scans WHERE id=f.scan_id AND primary_identification=f.primary_answer
      AND species_id IS NULL AND confirmed_species_id=species AND ai_confidence_score=0.75) THEN RAISE EXCEPTION 'original answer changed'; END IF;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.other_id,f.scan_id,1,'clear',NULL,NULL);
    EXCEPTION WHEN SQLSTATE 'P0002' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'foreign owner applied'; END IF;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.legacy_scan_id,0,'clear',NULL,NULL);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'legacy path changed'; END IF;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.scan_id,1,'confirm_primary','Reviewfixture',f.proof);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'genus confirmed as species'; END IF;
    receipt:=public.apply_verified_scan_species_review(f.owner_id,f.species_scan_id,0,'confirm_primary','Reviewfixture accepted',f.proof);
    IF receipt #> '{review,user_confirmed_identification}' <> 'true'::JSONB OR receipt #>> '{review,user_review_state}' <> 'ai_confirmed' THEN RAISE EXCEPTION 'primary review tuple mismatch'; END IF;
    RESET ROLE;
END;
$apply$;
SELECT extensions.pass('confirmation and exact retry preserve original answer; ownership, legacy and broader-primary guards hold');

DO $conflicts$
DECLARE f review_fixture%ROWTYPE; receipt JSONB; denied BOOLEAN;
BEGIN
    SELECT * INTO f FROM review_fixture;
    SET LOCAL ROLE service_role;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.scan_id,0,'confirm_name','Reviewfixture different',
      f.proof || '{"scientific_name":"Reviewfixture different","gbif_taxon_key":987600002}');
    EXCEPTION WHEN serialization_failure THEN denied:=TRUE; END;
    IF NOT denied OR EXISTS(SELECT 1 FROM public.species_dictionary WHERE gbif_taxon_key=987600002) THEN RAISE EXCEPTION 'conflict left materialization'; END IF;
    receipt:=public.apply_verified_scan_species_review(f.owner_id,f.scan_id,1,'clear',NULL,NULL);
    IF receipt #>> '{review,revision}' <> '2' OR receipt #> '{review,identity}' <> 'null'::JSONB THEN RAISE EXCEPTION 'clear lost revision'; END IF;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.scan_id,0,'confirm_name','Reviewfixture synonym',f.proof);
    EXCEPTION WHEN serialization_failure THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'stale confirmed response resurrected clear'; END IF;
    receipt:=public.apply_verified_scan_species_review(f.owner_id,f.scan_id,2,'confirm_name','Reviewfixture accepted',f.proof);
    RESET ROLE;
END;
$conflicts$;
SELECT extensions.pass('conflicting retries roll back materialization; clear/replacement advance revisions and reject stale replay');

DO $legacy$
DECLARE f review_fixture%ROWTYPE; species UUID; denied BOOLEAN; revision INTEGER;
BEGIN
    SELECT * INTO f FROM review_fixture;
    SELECT confirmed_species_id INTO species FROM public.scans WHERE id=f.scan_id;
    PERFORM SET_CONFIG('request.jwt.claims',JSONB_BUILD_OBJECT('role','authenticated','sub',f.owner_id)::TEXT,TRUE);
    PERFORM SET_CONFIG('request.headers','{"x-merian-identification-protocol":"5"}',TRUE);
    SET LOCAL ROLE authenticated;
    PERFORM public.update_owned_scan_identification_review(f.scan_id,'Pending typed selection',FALSE,species,'user_overridden');
    IF NOT EXISTS(SELECT 1 FROM public.scans WHERE id=f.scan_id AND confirmed_species_identity IS NULL AND confirmed_species_id IS NULL
      AND confirmed_species_identity_revision=4 AND user_identification_override='Pending typed selection' AND NOT user_confirmed_identification) THEN RAISE EXCEPTION 'old override invalidation failed'; END IF;
    -- The existing Explore refresh trigger additionally denies direct updates
    -- under authenticated. The authorized legacy RPC must still be safe.
    denied:=FALSE;
    BEGIN UPDATE public.scans SET confirmed_species_id=species WHERE id=f.scan_id;
    EXCEPTION WHEN insufficient_privilege THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected direct legacy grant path'; END IF;
    PERFORM public.update_owned_scan_identification_review(f.scan_id,NULL,TRUE,species,'ai_confirmed');
    IF NOT EXISTS(SELECT 1 FROM public.scans WHERE id=f.scan_id AND confirmed_species_id IS NULL AND confirmed_species_identity IS NULL
      AND user_confirmed_identification AND confirmed_species_identity_revision=5) THEN RAISE EXCEPTION 'raw FK gained authority'; END IF;
    denied:=FALSE;
    BEGIN UPDATE public.scans SET confirmed_species_identity_revision=99 WHERE id=f.scan_id;
    EXCEPTION WHEN insufficient_privilege THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'direct authority update accepted'; END IF;
    UPDATE public.scans SET custom_tags=ARRAY['fixture'] WHERE id=f.scan_id;
    SELECT confirmed_species_identity_revision INTO revision FROM public.scans WHERE id=f.scan_id;
    IF revision<>5 THEN RAISE EXCEPTION 'unrelated edit advanced revision'; END IF;
    RESET ROLE;
    IF (SELECT public.field_trip_scan_evidence_is_eligible(scans) FROM public.scans WHERE id=f.scan_id) THEN RAISE EXCEPTION 'boolean or raw FK granted species credit'; END IF;
    PERFORM SET_CONFIG('request.jwt.claims','{}',TRUE);
END;
$legacy$;
SELECT extensions.pass('old RPC/direct updates keep review intent but invalidate verified FK; boolean alone grants no species credit');

DO $canonical$
DECLARE f review_fixture%ROWTYPE; receipt JSONB;
BEGIN
    SELECT * INTO f FROM review_fixture;
    SET LOCAL ROLE service_role;
    receipt:=public.apply_verified_scan_species_review(f.owner_id,f.scan_id,5,'confirm_name','Reviewfixture renamed',f.proof || '{"scientific_name":"Reviewfixture renamed"}');
    IF receipt #>> '{review,identity,scientific_name}' <> 'Reviewfixture accepted' OR receipt #>> '{review,revision}' <> '6' THEN RAISE EXCEPTION 'receipt disagrees with dictionary identity'; END IF;
    RESET ROLE;
END;
$canonical$;
SELECT extensions.pass('accepted-name change reuses the verified key and stored canonical display identity');

DO $recovery$
DECLARE f review_fixture%ROWTYPE; saved JSONB; payload JSONB; outcome TEXT; receipt JSONB;
BEGIN
    SELECT * INTO f FROM review_fixture;
    SELECT confirmed_species_review INTO saved FROM public.scan_ingestion_jobs WHERE scan_id=f.scan_id::TEXT;
    payload:=JSONB_BUILD_OBJECT('id',f.scan_id,'user_id',f.owner_id,'image_storage_urls','[]'::JSONB,'timestamp',NOW(),
      'geoprivacy','private','ecology_type','unknown','ai_confidence_score',0.75,'is_invasive',FALSE,'is_live_capture',FALSE,
      'is_biological_subject',TRUE,'user_confirmed_identification',FALSE,'user_review_state','user_overridden','inference_tier','flash',
      'user_identification_override','Forged recovery selection','confirmed_species_id',f.species_scan_id,
      'confirmed_species_identity',JSONB_BUILD_OBJECT('version',99),'confirmed_species_identity_revision',999);
    -- Fault injection only: simulate a missing row while retaining the trusted
    -- completed-generation backup. Normal DELETE must create a tombstone.
    SET LOCAL session_replication_role=replica;
    DELETE FROM public.scans WHERE id=f.scan_id;
    SET LOCAL session_replication_role=origin;
    SET LOCAL ROLE service_role;
    outcome:=public.recover_missing_owned_scan(f.scan_id,f.owner_id,payload);
    IF outcome<>'recovered' THEN RAISE EXCEPTION 'recovery failed'; END IF;
    RESET ROLE;
    IF (SELECT internal.scan_species_review_snapshot(scans) FROM public.scans WHERE id=f.scan_id) IS DISTINCT FROM saved THEN RAISE EXCEPTION 'recovery trusted client review'; END IF;
    SET LOCAL ROLE service_role;
    receipt:=public.apply_verified_scan_species_review(f.owner_id,f.scan_id,6,'clear',NULL,NULL);
    RESET ROLE;
    SET LOCAL session_replication_role=replica;
    DELETE FROM public.scans WHERE id=f.scan_id;
    SET LOCAL session_replication_role=origin;
    SET LOCAL ROLE service_role;
    outcome:=public.recover_missing_owned_scan(f.scan_id,f.owner_id,payload);
    RESET ROLE;
    IF outcome<>'recovered' OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=f.scan_id AND confirmed_species_identity IS NULL
      AND confirmed_species_id IS NULL AND confirmed_species_identity_revision=7 AND user_review_state='unreviewed' AND user_identification_override IS NULL) THEN RAISE EXCEPTION 'stale recovery resurrected clear'; END IF;
END;
$recovery$;
SELECT extensions.pass('missing-row recovery restores server confirmation and clear, ignoring all client authority');

DO $backup$
DECLARE f review_fixture%ROWTYPE; denied BOOLEAN;
BEGIN
    SELECT * INTO f FROM review_fixture;
    denied:=FALSE;
    BEGIN UPDATE public.scan_ingestion_jobs SET confirmed_species_review=JSONB_SET(confirmed_species_review,'{revision}','99') WHERE scan_id=f.scan_id::TEXT;
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'job accepted forged backup'; END IF;
    -- Missing backup must fail atomically, not leave a scan-only review.
    UPDATE public.scan_ingestion_jobs SET confirmed_species_review=NULL WHERE scan_id=f.scan_id::TEXT;
    SET LOCAL ROLE service_role;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.scan_id,7,'confirm_name','Reviewfixture accepted',f.proof);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'missing backup accepted'; END IF;
    RESET ROLE;
END;
$backup$;
SELECT extensions.pass('forged or missing job backup cannot accept a review');

DO $privacy$
DECLARE f review_fixture%ROWTYPE; denied BOOLEAN;
BEGIN
    SELECT * INTO f FROM review_fixture;
    DELETE FROM public.scans WHERE id=f.species_scan_id;
    IF EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=f.species_scan_id::TEXT AND confirmed_species_review IS NOT NULL) THEN RAISE EXCEPTION 'deleted review retained'; END IF;
    SET LOCAL ROLE service_role;
    denied:=FALSE;
    BEGIN PERFORM public.apply_verified_scan_species_review(f.owner_id,f.species_scan_id,1,'clear',NULL,NULL);
    EXCEPTION WHEN SQLSTATE 'P0002' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'deleted scan review restored'; END IF;
    RESET ROLE;
END;
$privacy$;
SELECT extensions.pass('deletion clears backup and prevents a pending confirmation');
DO $merge$
DECLARE f review_fixture%ROWTYPE; saved JSONB; denied BOOLEAN;
BEGIN
    SELECT * INTO f FROM review_fixture;
    -- Restore the intentionally damaged fixture backup from its current row.
    UPDATE public.scan_ingestion_jobs AS jobs SET confirmed_species_review=internal.scan_species_review_snapshot(scans)
    FROM public.scans AS scans WHERE scans.id=f.scan_id AND jobs.scan_id=scans.id::TEXT AND jobs.user_id=scans.user_id;
    PERFORM public.apply_verified_scan_species_review(f.owner_id,f.scan_id,7,'confirm_name','Reviewfixture accepted',f.proof);
    SELECT confirmed_species_review INTO saved FROM public.scan_ingestion_jobs WHERE scan_id=f.scan_id::TEXT;
    -- Conflicting target backup must fail atomically instead of losing source authority.
    denied:=FALSE;
    BEGIN
      INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,primary_identification,identification_provenance)
      VALUES(f.scan_id::TEXT,f.other_id,f.primary_answer || '{"scientific_name":"Conflictinggenus"}',f.provenance);
      PERFORM internal.perform_ghost_profile_merge(f.owner_id,f.other_id);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied:=TRUE; END;
    IF NOT denied OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=f.scan_id AND user_id=f.owner_id) THEN RAISE EXCEPTION 'conflicting target backup lost source'; END IF;
    -- A target's pending job may replace the source ledger during merge; copy
    -- primary, provenance and review together into that still-empty job.
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES(f.scan_id::TEXT,f.other_id);
    PERFORM internal.perform_ghost_profile_merge(f.owner_id,f.other_id);
    IF NOT EXISTS(SELECT 1 FROM public.scans AS scans JOIN public.scan_ingestion_jobs AS jobs
      ON jobs.scan_id=scans.id::TEXT AND jobs.user_id=scans.user_id
      WHERE scans.id=f.scan_id AND scans.user_id=f.other_id AND internal.scan_species_review_snapshot(scans)=saved
        AND jobs.confirmed_species_review=saved) THEN RAISE EXCEPTION 'ghost merge lost owner-bound confirmation'; END IF;
END;
$merge$;
SELECT extensions.pass('account merge preserves confirmation and binds backup to the new owner');

DO $remove$
DECLARE f review_fixture%ROWTYPE;
BEGIN
    SELECT * INTO f FROM review_fixture;
    UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE WHERE id=f.scan_id;
    IF EXISTS(SELECT 1 FROM public.scans WHERE id=f.scan_id AND (confirmed_species_identity IS NOT NULL OR confirmed_species_id IS NOT NULL OR user_identification_override IS NOT NULL))
       OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=f.scan_id::TEXT AND confirmed_species_review IS NOT NULL) THEN RAISE EXCEPTION 'owner removal retained confirmation'; END IF;
END;
$remove$;
SELECT extensions.pass('owner removal clears confirmation and its recovery backup');
SELECT * FROM extensions.finish();
ROLLBACK;
