-- Dormant explicit-primary review authority. No model/profile or reader is enabled.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.confirmed_species_identity_is_valid(p_value JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $$
DECLARE name TEXT; utf16_length INTEGER;
    trim_characters CONSTANT TEXT := U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF p_value IS NULL THEN RETURN TRUE; END IF;
    IF pg_catalog.JSONB_TYPEOF(p_value) <> 'object'
       OR pg_catalog.OCTET_LENGTH(p_value::TEXT) > 4096
       OR NOT p_value ?& ARRAY['version','species_id','scientific_name','common_name','gbif_taxon_key']
       OR p_value - ARRAY['version','species_id','scientific_name','common_name','gbif_taxon_key'] <> '{}'::JSONB
       OR p_value -> 'version' <> '1'::JSONB
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'species_id') <> 'string'
       OR (p_value ->> 'species_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'scientific_name') <> 'string'
       OR p_value -> 'common_name' <> 'null'::JSONB
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'gbif_taxon_key') <> 'number'
       OR (p_value ->> 'gbif_taxon_key') !~ '^[1-9][0-9]{0,9}$'
       OR (p_value ->> 'gbif_taxon_key')::NUMERIC > 2147483647 THEN RETURN FALSE; END IF;
    name := p_value ->> 'scientific_name';
    SELECT pg_catalog.SUM(CASE WHEN pg_catalog.ASCII(character) > 65535 THEN 2 ELSE 1 END)
    INTO utf16_length FROM pg_catalog.REGEXP_SPLIT_TO_TABLE(name, '') AS character;
    RETURN name <> '' AND utf16_length <= 160
        AND name = pg_catalog.BTRIM(name,trim_characters) AND name !~ U&'[\0001-\001F\007F]';
END;
$$;
REVOKE ALL ON FUNCTION internal.confirmed_species_identity_is_valid(JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.confirmed_species_identity_is_valid(JSONB) TO anon, authenticated, service_role;

ALTER TABLE public.scans
    ADD COLUMN confirmed_species_identity JSONB,
    ADD COLUMN confirmed_species_identity_revision INTEGER NOT NULL DEFAULT 0;
-- One envelope also preserves pending legacy review text; a clear cannot be
-- resurrected from a stale device's recovery payload.
ALTER TABLE public.scan_ingestion_jobs ADD COLUMN confirmed_species_review JSONB;

CREATE FUNCTION internal.scan_species_review_snapshot(p_scan public.scans)
RETURNS JSONB LANGUAGE SQL STABLE PARALLEL SAFE SET search_path = ''
AS $$ SELECT pg_catalog.JSONB_BUILD_OBJECT(
    'version', 1, 'revision', p_scan.confirmed_species_identity_revision,
    'identity', p_scan.confirmed_species_identity,
    'user_identification_override', p_scan.user_identification_override,
    'user_confirmed_identification', p_scan.user_confirmed_identification,
    'confirmed_species_id', p_scan.confirmed_species_id,
    'user_review_state', p_scan.user_review_state
); $$;
REVOKE ALL ON FUNCTION internal.scan_species_review_snapshot(public.scans) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.confirmed_species_review_is_valid(p_value JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $$
DECLARE identity JSONB; review_state TEXT;
BEGIN
    IF p_value IS NULL THEN RETURN TRUE; END IF;
    IF pg_catalog.JSONB_TYPEOF(p_value) <> 'object'
       OR pg_catalog.OCTET_LENGTH(p_value::TEXT) > 8192
       OR NOT p_value ?& ARRAY['version','revision','identity','user_identification_override','user_confirmed_identification','confirmed_species_id','user_review_state']
       OR p_value - ARRAY['version','revision','identity','user_identification_override','user_confirmed_identification','confirmed_species_id','user_review_state'] <> '{}'::JSONB
       OR p_value -> 'version' <> '1'::JSONB
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'revision') <> 'number'
       OR (p_value ->> 'revision') !~ '^(0|[1-9][0-9]{0,9})$'
       OR (p_value ->> 'revision')::NUMERIC > 2147483647
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'user_confirmed_identification') <> 'boolean'
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'user_review_state') <> 'string' THEN RETURN FALSE; END IF;
    identity := NULLIF(p_value -> 'identity', 'null'::JSONB);
    review_state := p_value ->> 'user_review_state';
    IF NOT internal.confirmed_species_identity_is_valid(identity)
       OR review_state NOT IN ('unreviewed','ai_confirmed','user_overridden')
       OR (p_value -> 'user_confirmed_identification' = 'true'::JSONB) IS DISTINCT FROM (review_state = 'ai_confirmed')
       OR p_value -> 'confirmed_species_id' IS DISTINCT FROM COALESCE(identity -> 'species_id', 'null'::JSONB)
       OR (identity IS NOT NULL AND (review_state = 'unreviewed' OR p_value -> 'revision' = '0'::JSONB)) THEN RETURN FALSE; END IF;
    IF review_state = 'user_overridden' THEN
        RETURN pg_catalog.JSONB_TYPEOF(p_value -> 'user_identification_override') = 'string'
            AND pg_catalog.OCTET_LENGTH(p_value ->> 'user_identification_override') BETWEEN 1 AND 1024
            AND pg_catalog.BTRIM(p_value ->> 'user_identification_override') <> ''
            AND (p_value ->> 'user_identification_override') !~ '[[:cntrl:]]';
    END IF;
    RETURN p_value -> 'user_identification_override' = 'null'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION internal.confirmed_species_review_is_valid(JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.confirmed_species_review_is_valid(JSONB) TO anon, authenticated, service_role;

ALTER TABLE public.scans ADD CONSTRAINT scans_verified_species_review_check CHECK (
    confirmed_species_identity_revision >= 0
    AND internal.confirmed_species_identity_is_valid(confirmed_species_identity)
    AND CASE WHEN primary_identification IS NULL THEN
        confirmed_species_identity IS NULL AND confirmed_species_identity_revision = 0
    ELSE internal.confirmed_species_review_is_valid(pg_catalog.JSONB_BUILD_OBJECT(
        'version',1,'revision',confirmed_species_identity_revision,'identity',confirmed_species_identity,
        'user_identification_override',user_identification_override,'user_confirmed_identification',user_confirmed_identification,
        'confirmed_species_id',confirmed_species_id,'user_review_state',user_review_state)) END
);
ALTER TABLE public.scan_ingestion_jobs ADD CONSTRAINT jobs_verified_species_review_check CHECK (
    internal.confirmed_species_review_is_valid(confirmed_species_review)
    AND (confirmed_species_review IS NULL OR primary_identification IS NOT NULL)
);
REVOKE INSERT (confirmed_species_identity, confirmed_species_identity_revision), UPDATE (confirmed_species_identity, confirmed_species_identity_revision)
    ON public.scans FROM PUBLIC, anon, authenticated;
REVOKE INSERT (confirmed_species_review), UPDATE (confirmed_species_review)
    ON public.scan_ingestion_jobs FROM PUBLIC, anon, authenticated;
COMMENT ON COLUMN public.scans.confirmed_species_identity IS
    'Independent server-verified accepted species selection, never an AI confidence score. NULL is no verified selection. Original primary/provenance are unchanged; existing observation visibility applies.';
COMMENT ON COLUMN public.scans.confirmed_species_identity_revision IS
    'Monotonic owner review revision, including authoritative clear and invalidation. Omission by an older projection is not a clear. Initial/legacy revision is zero.';
COMMENT ON COLUMN public.scan_ingestion_jobs.confirmed_species_review IS
    'Exact owner-bound versioned review backup, including revision, nullable verified identity and pending legacy review fields. Never trusted from client recovery JSON; cleared on deletion.';

CREATE FUNCTION internal.guard_scan_verified_species_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
DECLARE backup public.scan_ingestion_jobs%ROWTYPE; saved JSONB; changed BOOLEAN;
BEGIN
    IF NEW.primary_identification IS NULL THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' THEN
        -- Preserve the existing first-write-wins INSERT ... ON CONFLICT path.
        -- A conflicting insert cannot replace the saved row; UPDATE guards
        -- still enforce immutable primary identity if a caller uses an upsert.
        IF EXISTS (SELECT 1 FROM public.scans WHERE id = NEW.id) THEN RETURN NEW; END IF;
        SELECT * INTO backup FROM public.scan_ingestion_jobs
        WHERE scan_id = NEW.id::TEXT AND user_id = NEW.user_id FOR UPDATE;
        IF NOT FOUND OR (backup.primary_identification IS NOT NULL AND (
            backup.primary_identification IS DISTINCT FROM NEW.primary_identification
            OR backup.identification_provenance IS DISTINCT FROM NEW.identification_provenance)) THEN
            RAISE EXCEPTION 'species_review_job_mismatch' USING ERRCODE = '22023';
        END IF;
        saved := backup.confirmed_species_review;
        -- A new generation or an older backup with no review always starts
        -- unconfirmed. Only the exact server backup can restore these fields.
        NEW.confirmed_species_identity := NULLIF(saved -> 'identity','null'::JSONB);
        NEW.confirmed_species_identity_revision := COALESCE((saved ->> 'revision')::INTEGER,0);
        NEW.user_identification_override := saved ->> 'user_identification_override';
        NEW.user_confirmed_identification := COALESCE((saved ->> 'user_confirmed_identification')::BOOLEAN,FALSE);
        NEW.confirmed_species_id := (saved ->> 'confirmed_species_id')::UUID;
        NEW.user_review_state := COALESCE(saved ->> 'user_review_state','unreviewed')::public.user_review_state;
        RETURN NEW;
    END IF;
    IF NEW.user_id IS NULL AND OLD.user_id IS NOT NULL THEN
        NEW.confirmed_species_identity := NULL;
        NEW.confirmed_species_id := NULL;
        NEW.user_identification_override := NULL;
        NEW.user_confirmed_identification := FALSE;
        NEW.user_review_state := 'unreviewed';
        NEW.confirmed_species_identity_revision := OLD.confirmed_species_identity_revision;
        RETURN NEW;
    END IF;
    IF pg_catalog.CURRENT_SETTING('merian.verified_species_review',TRUE) = 'on' THEN
        PERFORM internal.require_service_role();
        IF NEW.confirmed_species_identity_revision <> OLD.confirmed_species_identity_revision + 1 THEN
            RAISE EXCEPTION 'species_review_revision_conflict' USING ERRCODE = '40001';
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.confirmed_species_identity IS DISTINCT FROM OLD.confirmed_species_identity
       OR NEW.confirmed_species_identity_revision IS DISTINCT FROM OLD.confirmed_species_identity_revision THEN
        RAISE EXCEPTION 'species_review_server_owned' USING ERRCODE = '42501';
    END IF;
    changed := ROW(NEW.user_identification_override,NEW.user_confirmed_identification,NEW.confirmed_species_id,NEW.user_review_state)
        IS DISTINCT FROM ROW(OLD.user_identification_override,OLD.user_confirmed_identification,OLD.confirmed_species_id,OLD.user_review_state);
    IF changed THEN
        -- Old clients and community flows may record review intent, but their
        -- raw FK cannot mint or keep independent verified species authority.
        NEW.confirmed_species_identity := NULL;
        NEW.confirmed_species_id := NULL;
        NEW.confirmed_species_identity_revision := OLD.confirmed_species_identity_revision + 1;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_scan_verified_species_review() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_scan_verified_species_review
BEFORE INSERT OR UPDATE ON public.scans FOR EACH ROW EXECUTE FUNCTION internal.guard_scan_verified_species_review();

CREATE FUNCTION internal.guard_job_verified_species_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.confirmed_species_review IS NOT DISTINCT FROM OLD.confirmed_species_review THEN RETURN NEW; END IF;
    IF NEW.confirmed_species_review IS NULL THEN RETURN NEW; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.scans AS scans
        WHERE scans.id::TEXT = NEW.scan_id AND scans.user_id = NEW.user_id
        AND scans.primary_identification = NEW.primary_identification
        AND scans.identification_provenance = NEW.identification_provenance
        AND internal.scan_species_review_snapshot(scans) = NEW.confirmed_species_review) THEN
        RAISE EXCEPTION 'species_review_job_mismatch' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_job_verified_species_review() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_job_verified_species_review BEFORE INSERT OR UPDATE OF confirmed_species_review
ON public.scan_ingestion_jobs FOR EACH ROW EXECUTE FUNCTION internal.guard_job_verified_species_review();

CREATE FUNCTION internal.copy_scan_verified_species_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.scan_ingestion_jobs SET confirmed_species_review = NULL
        WHERE scan_id = OLD.id::TEXT AND user_id = OLD.user_id;
        RETURN NULL;
    END IF;
    IF NEW.user_id IS NULL THEN
        UPDATE public.scan_ingestion_jobs SET confirmed_species_review = NULL
        WHERE scan_id = OLD.id::TEXT AND user_id = OLD.user_id;
        RETURN NULL;
    END IF;
    IF NEW.primary_identification IS NULL THEN RETURN NULL; END IF;
    UPDATE public.scan_ingestion_jobs AS jobs
    SET identification_provenance = NEW.identification_provenance,
        primary_identification = NEW.primary_identification,
        confirmed_species_review = internal.scan_species_review_snapshot(NEW)
    WHERE jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id
      AND (jobs.primary_identification IS NULL OR jobs.primary_identification = NEW.primary_identification)
      AND (jobs.identification_provenance IS NULL OR jobs.identification_provenance = NEW.identification_provenance);
    IF NOT FOUND THEN
        -- The reviewed ghost merge can move the scan before its job. The job's
        -- owner-change trigger copies once both rows have the same new owner.
        IF TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id
           AND pg_catalog.CURRENT_SETTING('internal.ai_usage_reparenting',TRUE) = 'on'
           AND pg_catalog.CURRENT_SETTING('internal.ai_usage_reparent_source',TRUE) = OLD.user_id::TEXT
           AND pg_catalog.CURRENT_SETTING('internal.ai_usage_reparent_target',TRUE) = NEW.user_id::TEXT
           AND NOT EXISTS (SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=NEW.id::TEXT AND user_id=NEW.user_id)
           AND EXISTS (SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=NEW.id::TEXT AND user_id=OLD.user_id
             AND primary_identification=NEW.primary_identification AND identification_provenance=NEW.identification_provenance)
           THEN RETURN NULL; END IF;
        RAISE EXCEPTION 'species_review_job_mismatch' USING ERRCODE = '22023';
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.copy_scan_verified_species_review() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER copy_scan_verified_species_review AFTER INSERT OR DELETE OR UPDATE OF
    user_id,confirmed_species_identity,confirmed_species_identity_revision,user_identification_override,user_confirmed_identification,confirmed_species_id,user_review_state
ON public.scans FOR EACH ROW EXECUTE FUNCTION internal.copy_scan_verified_species_review();

CREATE FUNCTION internal.refresh_reparented_job_species_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET confirmed_species_review = internal.scan_species_review_snapshot(scans)
        FROM public.scans AS scans
        WHERE jobs.id = NEW.id AND scans.id::TEXT = NEW.scan_id AND scans.user_id = NEW.user_id
          AND scans.primary_identification = jobs.primary_identification
          AND scans.identification_provenance = jobs.identification_provenance;
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.refresh_reparented_job_species_review() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER refresh_reparented_job_species_review AFTER UPDATE OF user_id ON public.scan_ingestion_jobs
FOR EACH ROW EXECUTE FUNCTION internal.refresh_reparented_job_species_review();

CREATE FUNCTION internal.clear_deleted_job_species_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    UPDATE public.scan_ingestion_jobs SET confirmed_species_review = NULL
    WHERE scan_id = NEW.scan_id::TEXT AND user_id = NEW.user_id;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.clear_deleted_job_species_review() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER clear_deleted_job_species_review AFTER INSERT ON internal.scan_deletion_tombstones
FOR EACH ROW EXECUTE FUNCTION internal.clear_deleted_job_species_review();

CREATE FUNCTION public.apply_verified_scan_species_review(
    p_user_id UUID, p_scan_id UUID, p_expected_revision INTEGER,
    p_action TEXT, p_requested_name TEXT, p_taxon JSONB
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE scan public.scans%ROWTYPE; backup public.scan_ingestion_jobs%ROWTYPE;
    identity JSONB; species UUID; desired_state public.user_review_state; desired_override TEXT;
    previous_setting TEXT; receipt JSONB; saved_name TEXT;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR p_scan_id IS NULL OR p_expected_revision IS NULL
       OR p_expected_revision NOT BETWEEN 0 AND 2147483646
       OR p_action IS NULL OR p_action NOT IN ('confirm_primary','confirm_name','clear')
       OR (p_action = 'clear' AND (p_requested_name IS NOT NULL OR p_taxon IS NOT NULL))
       OR (p_action <> 'clear' AND (p_requested_name IS NULL OR pg_catalog.LENGTH(p_requested_name) NOT BETWEEN 1 AND 160)) THEN
        RAISE EXCEPTION 'invalid_species_review' USING ERRCODE = '22023';
    END IF;
    -- Same generation fence as finalization, recovery and deletion; no network
    -- activity or AI quota operations take place inside this transaction.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || p_scan_id::TEXT,0::BIGINT));
    SELECT * INTO scan FROM public.scans WHERE id = p_scan_id AND user_id = p_user_id AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = p_scan_id) THEN
        RAISE EXCEPTION 'species_review_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF scan.primary_identification IS NULL THEN
        RAISE EXCEPTION 'species_review_requires_primary' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO backup FROM public.scan_ingestion_jobs WHERE scan_id = p_scan_id::TEXT AND user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR backup.primary_identification IS DISTINCT FROM scan.primary_identification
       OR backup.identification_provenance IS DISTINCT FROM scan.identification_provenance
       OR backup.confirmed_species_review IS DISTINCT FROM internal.scan_species_review_snapshot(scan) THEN
        RAISE EXCEPTION 'species_review_job_mismatch' USING ERRCODE = '22023';
    END IF;
    IF scan.confirmed_species_identity_revision NOT IN (p_expected_revision,p_expected_revision + 1) THEN
        RAISE EXCEPTION 'species_review_revision_conflict' USING ERRCODE = '40001';
    END IF;
    IF p_action = 'confirm_primary' AND (scan.primary_identification ->> 'resolution' <> 'species'
        OR scan.primary_identification ->> 'scientific_name' IS DISTINCT FROM p_requested_name) THEN
        RAISE EXCEPTION 'species_review_primary_not_species' USING ERRCODE = '22023';
    END IF;
    IF p_action = 'clear' THEN
        desired_state := 'unreviewed';
    ELSE
        species := public.resolve_verified_dictionary_species(p_taxon);
        SELECT scientific_name INTO STRICT saved_name FROM public.species_dictionary
        WHERE id = species AND is_public_biological AND gbif_taxon_key = (p_taxon ->> 'gbif_taxon_key')::INTEGER FOR SHARE;
        identity := pg_catalog.JSONB_BUILD_OBJECT('version',1,'species_id',species,
            'scientific_name',saved_name,'common_name',NULL,'gbif_taxon_key',p_taxon -> 'gbif_taxon_key');
        IF NOT internal.confirmed_species_identity_is_valid(identity) THEN
            RAISE EXCEPTION 'invalid_verified_species' USING ERRCODE = '22023';
        END IF;
        desired_state := CASE WHEN p_action = 'confirm_primary' THEN 'ai_confirmed'::public.user_review_state ELSE 'user_overridden'::public.user_review_state END;
        desired_override := CASE WHEN p_action = 'confirm_name' THEN p_requested_name ELSE NULL END;
    END IF;
    IF scan.confirmed_species_identity_revision = p_expected_revision + 1 THEN
        IF scan.confirmed_species_identity IS DISTINCT FROM identity
           OR scan.user_review_state IS DISTINCT FROM desired_state
           OR scan.user_identification_override IS DISTINCT FROM desired_override THEN
            RAISE EXCEPTION 'species_review_revision_conflict' USING ERRCODE = '40001';
        END IF;
    ELSE
        previous_setting := pg_catalog.CURRENT_SETTING('merian.verified_species_review',TRUE);
        PERFORM pg_catalog.SET_CONFIG('merian.verified_species_review','on',TRUE);
        UPDATE public.scans SET confirmed_species_identity = identity,
            confirmed_species_identity_revision = p_expected_revision + 1,
            confirmed_species_id = species, user_identification_override = desired_override,
            user_confirmed_identification = desired_state = 'ai_confirmed', user_review_state = desired_state
        WHERE id = p_scan_id AND user_id = p_user_id RETURNING * INTO scan;
        PERFORM pg_catalog.SET_CONFIG('merian.verified_species_review',COALESCE(previous_setting,''),TRUE);
    END IF;
    receipt := internal.scan_species_review_snapshot(scan);
    RETURN pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'scan_id',scan.id,'review',receipt);
END;
$$;
REVOKE ALL ON FUNCTION public.apply_verified_scan_species_review(UUID, UUID, INTEGER, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_verified_scan_species_review(UUID, UUID, INTEGER, TEXT, TEXT, JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.apply_verified_scan_species_review(uuid,uuid,integer,text,text,jsonb)',
     'Atomically apply an owner review with fresh Edge-verified species proof, revision conflict checks and generation-bound recovery backup.');

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;
