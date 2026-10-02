-- Owner review is separate from AI evidence and from verified species identity.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.ai_identification_review_is_valid(value JSONB)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE PARALLEL SAFE SECURITY INVOKER SET search_path = ''
AS $$ SELECT value IS NULL OR COALESCE(
    pg_catalog.JSONB_TYPEOF(value) = 'object'
    AND pg_catalog.OCTET_LENGTH(value::TEXT) <= 8192
    AND value ?& ARRAY['version','revision','state','origin_scan_id','origin_identification','operation_id','operation_digest','community']
    AND value - ARRAY['version','revision','state','origin_scan_id','origin_identification','operation_id','operation_digest','community'] = '{}'::JSONB
    AND value -> 'version' = '1'::JSONB
    AND pg_catalog.JSONB_TYPEOF(value -> 'revision') = 'number'
    AND value ->> 'revision' ~ '^[0-9]{1,9}$'
    AND (value -> 'community' = 'null'::JSONB OR (
        pg_catalog.JSONB_TYPEOF(value -> 'community') = 'object'
        AND value ->> 'state' = 'clear'
        AND (value -> 'community') ?& ARRAY['request_id','rank','scientific_name','common_name','species_id']
        AND (value -> 'community') - ARRAY['request_id','rank','scientific_name','common_name','species_id'] = '{}'::JSONB
        AND value #>> '{community,request_id}' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND value #>> '{community,rank}' IN ('species','genus')
        AND pg_catalog.JSONB_TYPEOF(value #> '{community,scientific_name}') = 'string'
        AND pg_catalog.LENGTH(value #>> '{community,scientific_name}') BETWEEN 1 AND 160
        AND (value #> '{community,common_name}' = 'null'::JSONB OR (pg_catalog.JSONB_TYPEOF(value #> '{community,common_name}') = 'string' AND pg_catalog.LENGTH(value #>> '{community,common_name}') <= 160))
        AND ((value #>> '{community,rank}' = 'genus' AND value #> '{community,species_id}' = 'null'::JSONB)
            OR (value #>> '{community,rank}' = 'species' AND value #>> '{community,species_id}' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))))
    AND value ->> 'state' IN ('clear','ai_rejected','awaiting_acceptance')
    AND (value -> 'origin_scan_id' = 'null'::JSONB OR value ->> 'origin_scan_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    AND (value -> 'operation_id' = 'null'::JSONB OR value ->> 'operation_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    AND (value -> 'operation_digest' = 'null'::JSONB OR value ->> 'operation_digest' ~ '^[0-9a-f]{32}$')
    AND (value -> 'origin_identification' = 'null'::JSONB OR (
        pg_catalog.JSONB_TYPEOF(value -> 'origin_identification') = 'object'
        AND (value -> 'origin_identification') ?& ARRAY['scientific_name','common_name']
        AND (value -> 'origin_identification') - ARRAY['scientific_name','common_name'] = '{}'::JSONB
        AND (value #> '{origin_identification,scientific_name}' = 'null'::JSONB OR
            (pg_catalog.JSONB_TYPEOF(value #> '{origin_identification,scientific_name}') = 'string' AND pg_catalog.LENGTH(value #>> '{origin_identification,scientific_name}') <= 160))
        AND (value #> '{origin_identification,common_name}' = 'null'::JSONB OR
            (pg_catalog.JSONB_TYPEOF(value #> '{origin_identification,common_name}') = 'string' AND pg_catalog.LENGTH(value #>> '{origin_identification,common_name}') <= 160))))
    AND (value ->> 'state' = 'clear' OR value -> 'origin_scan_id' <> 'null'::JSONB), FALSE); $$;
REVOKE ALL ON FUNCTION internal.ai_identification_review_is_valid(JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION internal.ai_identification_review_is_valid(JSONB) TO authenticated,service_role;

ALTER TABLE public.scans ADD COLUMN ai_identification_review JSONB
    CHECK (internal.ai_identification_review_is_valid(ai_identification_review));
ALTER TABLE public.scan_ingestion_jobs ADD COLUMN ai_identification_review JSONB
    CHECK (internal.ai_identification_review_is_valid(ai_identification_review));
-- Raw review history is owner-only, even for publicly readable scans.
REVOKE SELECT ON public.scans FROM anon, authenticated;
DO $grants$
DECLARE columns TEXT;
BEGIN
    SELECT pg_catalog.STRING_AGG(pg_catalog.QUOTE_IDENT(attname), ', ' ORDER BY attnum) INTO columns
    FROM pg_catalog.pg_attribute WHERE attrelid = 'public.scans'::REGCLASS
        AND attnum > 0 AND NOT attisdropped AND attname <> 'ai_identification_review';
    EXECUTE pg_catalog.FORMAT('GRANT SELECT (%s) ON public.scans TO anon, authenticated', columns);
END;
$grants$;
CREATE FUNCTION public.get_owned_scan_ai_reviews(p_scan_ids UUID[])
RETURNS TABLE(scan_id UUID, review JSONB, review_fields JSONB)
LANGUAGE PLPGSQL STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF auth.uid() IS NULL OR p_scan_ids IS NULL OR pg_catalog.CARDINALITY(p_scan_ids) NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'invalid_review_lookup' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY SELECT scan.id, scan.ai_identification_review,
        pg_catalog.JSONB_BUILD_OBJECT('confirmed_species_id',scan.confirmed_species_id,
            'user_identification_override',scan.user_identification_override,
            'user_confirmed_identification',scan.user_confirmed_identification,
            'user_review_state',scan.user_review_state,
            'confirmed_species_identity',scan.confirmed_species_identity,
            'confirmed_species_identity_revision',scan.confirmed_species_identity_revision)
        FROM public.scans AS scan
    WHERE scan.id = ANY(p_scan_ids) AND scan.user_id = (SELECT auth.uid()) AND NOT scan.is_tombstoned;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_scan_ai_reviews(UUID[]) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_scan_ai_reviews(UUID[]) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('authenticated','public.get_owned_scan_ai_reviews(uuid[])','Bounded caller-owned identification review history.');

CREATE FUNCTION internal.scan_has_unresolved_review(candidate public.scans)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE PARALLEL SAFE SECURITY INVOKER SET search_path = ''
AS $$ SELECT COALESCE(candidate.ai_identification_review ->> 'state' IN ('ai_rejected','awaiting_acceptance'),FALSE); $$;
REVOKE ALL ON FUNCTION internal.scan_has_unresolved_review(public.scans) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION internal.scan_has_unresolved_review(public.scans) TO service_role;

CREATE FUNCTION internal.guard_scan_ai_identification_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
DECLARE saved JSONB; source_id UUID; source public.scans%ROWTYPE; review_changed BOOLEAN;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM public.scans WHERE id = NEW.id) THEN RETURN NEW; END IF;
        SELECT jobs.ai_identification_review INTO saved FROM public.scan_ingestion_jobs AS jobs
        WHERE jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id FOR UPDATE;
        -- Only trusted owner-job backup or server admission lineage may restore review authority.
        NEW.ai_identification_review := saved;
        RETURN NEW;
    END IF;
    IF NEW.user_id IS NULL OR NEW.is_tombstoned THEN NEW.ai_identification_review := NULL; RETURN NEW; END IF;
    IF pg_catalog.CURRENT_SETTING('merian.ai_identification_review',TRUE) = 'on' THEN
        PERFORM internal.require_service_role();
        RETURN NEW;
    END IF;
    IF NEW.ai_identification_review IS DISTINCT FROM OLD.ai_identification_review THEN
        RAISE EXCEPTION 'identification_review_server_owned' USING ERRCODE = '42501';
    END IF;
    review_changed := ROW(NEW.user_identification_override,NEW.user_confirmed_identification,NEW.confirmed_species_id,NEW.user_review_state)
        IS DISTINCT FROM ROW(OLD.user_identification_override,OLD.user_confirmed_identification,OLD.confirmed_species_id,OLD.user_review_state);
    IF review_changed THEN
        IF internal.scan_has_unresolved_review(OLD) THEN
            RAISE EXCEPTION 'identification_review_revision_conflict' USING ERRCODE = '40001';
        END IF;
        NEW.ai_identification_review := pg_catalog.JSONB_BUILD_OBJECT('version',1,
            'revision',COALESCE((OLD.ai_identification_review ->> 'revision')::INTEGER,0)+1,
            'state','clear','origin_scan_id',NULL,'origin_identification',NULL,'operation_id',NULL,'operation_digest',NULL,'community',NULL);
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_scan_ai_identification_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_scan_ai_identification_review BEFORE INSERT OR UPDATE ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.guard_scan_ai_identification_review();

CREATE FUNCTION internal.copy_scan_ai_identification_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.scan_ingestion_jobs SET ai_identification_review = NULL WHERE scan_id = OLD.id::TEXT AND user_id = OLD.user_id;
    ELSIF NEW.user_id IS NULL THEN
        UPDATE public.scan_ingestion_jobs SET ai_identification_review = NULL WHERE scan_id = OLD.id::TEXT AND user_id = OLD.user_id;
    ELSE
        UPDATE public.scan_ingestion_jobs SET ai_identification_review = NEW.ai_identification_review
        WHERE scan_id = NEW.id::TEXT AND user_id = NEW.user_id;
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.copy_scan_ai_identification_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER copy_scan_ai_identification_review AFTER INSERT OR UPDATE OR DELETE ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.copy_scan_ai_identification_review();

CREATE FUNCTION internal.guard_job_ai_identification_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        SELECT scan.ai_identification_review INTO NEW.ai_identification_review FROM public.scans AS scan
        WHERE scan.id::TEXT = NEW.scan_id AND scan.user_id = NEW.user_id;
    END IF;
    IF NEW.ai_identification_review IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.scans AS scan WHERE scan.id::TEXT = NEW.scan_id AND scan.user_id = NEW.user_id
          AND scan.ai_identification_review = NEW.ai_identification_review) THEN
        RAISE EXCEPTION 'identification_review_job_mismatch' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_job_ai_identification_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_job_ai_identification_review BEFORE INSERT OR UPDATE OF ai_identification_review,user_id ON public.scan_ingestion_jobs
FOR EACH ROW EXECUTE FUNCTION internal.guard_job_ai_identification_review();

CREATE FUNCTION internal.clear_deleted_job_ai_identification_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    UPDATE public.scan_ingestion_jobs SET ai_identification_review = NULL WHERE scan_id = NEW.scan_id::TEXT AND user_id = NEW.user_id;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.clear_deleted_job_ai_identification_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER clear_deleted_job_ai_identification_review AFTER INSERT ON internal.scan_deletion_tombstones
FOR EACH ROW EXECUTE FUNCTION internal.clear_deleted_job_ai_identification_review();

CREATE FUNCTION public.apply_scan_identification_review(
    p_user_id UUID,p_scan_id UUID,p_expected_revision INTEGER,p_operation_id UUID,
    p_action TEXT,p_requested_name TEXT,p_taxon JSONB,p_species_review_revision INTEGER,
    p_source_scan_id UUID,p_source_revision INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
DECLARE scan public.scans%ROWTYPE; source public.scans%ROWTYPE; saved JSONB; next_review JSONB; current_revision INTEGER;
    previous_setting TEXT; ingestion_setting TEXT; digest TEXT; species UUID; origin JSONB; species_receipt JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR p_scan_id IS NULL OR p_operation_id IS NULL OR p_expected_revision IS NULL
       OR p_expected_revision NOT BETWEEN 0 AND 999999998 OR p_action IS NULL
       OR p_action NOT IN ('carry','reject','undo','confirm_primary','confirm_name')
       OR (p_action = 'carry' AND (p_source_scan_id IS NULL OR p_source_revision IS NULL OR p_source_scan_id = p_scan_id))
       OR (p_action <> 'carry' AND (p_source_scan_id IS NOT NULL OR p_source_revision IS NOT NULL))
       OR (p_action IN ('carry','reject','undo') AND (p_requested_name IS NOT NULL OR p_taxon IS NOT NULL))
       OR (p_action = 'confirm_name' AND (p_requested_name IS NULL OR pg_catalog.LENGTH(p_requested_name) NOT BETWEEN 1 AND 160)) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE = '22023';
    END IF;
    IF p_action = 'carry' THEN
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || LEAST(p_scan_id,p_source_scan_id)::TEXT,0::BIGINT));
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || GREATEST(p_scan_id,p_source_scan_id)::TEXT,0::BIGINT));
    ELSE
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || p_scan_id::TEXT,0::BIGINT));
    END IF;
    SELECT * INTO scan FROM public.scans WHERE id = p_scan_id AND user_id = p_user_id AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = p_scan_id) THEN
        RAISE EXCEPTION 'identification_review_not_found' USING ERRCODE = 'P0002';
    END IF;
    -- Older saved observations may predate the ingestion ledger. Seed only from
    -- the locked authoritative row; never use a caller recovery payload.
    IF NOT EXISTS (SELECT 1 FROM public.scan_ingestion_jobs WHERE user_id=p_user_id AND scan_id=p_scan_id::TEXT) THEN
        ingestion_setting := pg_catalog.CURRENT_SETTING('merian.scan_ingestion_completion_fence',TRUE);
        PERFORM pg_catalog.SET_CONFIG('merian.scan_ingestion_completion_fence',p_user_id::TEXT || ':' || p_scan_id::TEXT,TRUE);
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,completed_at,identification_provenance,primary_identification,confirmed_species_review,ai_identification_review)
    VALUES(p_scan_id::TEXT,p_user_id,'complete','owner_review_snapshot',pg_catalog.NOW(),scan.identification_provenance,scan.primary_identification,
        CASE WHEN scan.primary_identification IS NOT NULL THEN internal.scan_species_review_snapshot(scan) ELSE NULL END,scan.ai_identification_review)
    ON CONFLICT (user_id,scan_id) DO NOTHING;
        PERFORM pg_catalog.SET_CONFIG('merian.scan_ingestion_completion_fence',COALESCE(ingestion_setting,''),TRUE);
    END IF;
    SELECT ai_identification_review INTO saved FROM public.scan_ingestion_jobs
    WHERE scan_id = p_scan_id::TEXT AND user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR saved IS DISTINCT FROM scan.ai_identification_review THEN
        RAISE EXCEPTION 'identification_review_job_mismatch' USING ERRCODE = '22023';
    END IF;
    digest := pg_catalog.MD5(pg_catalog.JSONB_BUILD_ARRAY(p_action,p_requested_name,p_species_review_revision,p_source_scan_id,p_source_revision)::TEXT);
    current_revision := COALESCE((saved ->> 'revision')::INTEGER,0);
    IF current_revision = p_expected_revision + 1 AND saved ->> 'operation_id' = p_operation_id::TEXT AND saved ->> 'operation_digest' = digest THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'scan_id',p_scan_id,'review',saved,
            'confirmed_species_id',scan.confirmed_species_id,'species_review',CASE WHEN scan.primary_identification IS NOT NULL THEN internal.scan_species_review_snapshot(scan) ELSE NULL END);
    END IF;
    IF current_revision <> p_expected_revision THEN
        RAISE EXCEPTION 'identification_review_revision_conflict' USING ERRCODE = '40001';
    END IF;
    IF p_action = 'reject' AND (scan.is_biological_subject IS FALSE OR scan.user_identification_override IS NOT NULL
        OR EXISTS (SELECT 1 FROM public.explore_community_requests WHERE scan_id = p_scan_id AND status = 'resolved' AND withdrawn_at IS NULL)) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE = '22023';
    END IF;
    IF p_action = 'undo' AND (saved ->> 'state' = 'awaiting_acceptance' OR COALESCE(saved -> 'community','null'::JSONB) <> 'null'::JSONB) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE = '22023';
    END IF;
    IF p_action = 'carry' THEN
        SELECT * INTO source FROM public.scans WHERE id = p_source_scan_id AND user_id = p_user_id AND NOT is_tombstoned FOR UPDATE;
        IF NOT FOUND OR NOT internal.scan_has_unresolved_review(source)
            OR (source.ai_identification_review ->> 'revision')::INTEGER <> p_source_revision OR current_revision <> 0 THEN
            RAISE EXCEPTION 'identification_review_revision_conflict' USING ERRCODE = '40001';
        END IF;
        next_review := source.ai_identification_review || pg_catalog.JSONB_BUILD_OBJECT('revision',1,'state','awaiting_acceptance',
            'operation_id',p_operation_id,'operation_digest',digest,'community',NULL);
    ELSIF p_action = 'reject' THEN
        SELECT pg_catalog.JSONB_BUILD_OBJECT('scientific_name',COALESCE(scan.primary_identification ->> 'scientific_name',scientific_name),'common_name',scan.primary_identification ->> 'common_name')
        INTO origin FROM public.species_dictionary WHERE id = scan.species_id;
        next_review := pg_catalog.JSONB_BUILD_OBJECT('version',1,'revision',current_revision+1,
            'state','ai_rejected','origin_scan_id',scan.id,'origin_identification',origin,
            'operation_id',p_operation_id,'operation_digest',digest,'community',NULL);
    ELSE
        next_review := pg_catalog.JSONB_BUILD_OBJECT('version',1,'revision',current_revision+1,
            'state','clear','origin_scan_id',saved -> 'origin_scan_id','origin_identification',saved -> 'origin_identification',
            'operation_id',p_operation_id,'operation_digest',digest,'community',NULL);
    END IF;
    previous_setting := pg_catalog.CURRENT_SETTING('merian.ai_identification_review',TRUE);
    PERFORM pg_catalog.SET_CONFIG('merian.ai_identification_review','on',TRUE);
    IF scan.primary_identification IS NOT NULL THEN
        species_receipt := public.apply_verified_scan_species_review(p_user_id,p_scan_id,p_species_review_revision,
            CASE WHEN p_action IN ('carry','reject','undo') THEN 'clear' ELSE p_action END,p_requested_name,p_taxon);
    ELSE
        IF p_action IN ('confirm_primary','confirm_name') THEN
            species := public.resolve_verified_dictionary_species(p_taxon);
            IF p_action = 'confirm_primary' AND NOT EXISTS (SELECT 1 FROM public.species_dictionary
                WHERE id = scan.species_id AND scientific_name = p_requested_name) THEN
                RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE = '22023';
            END IF;
        END IF;
        UPDATE public.scans SET user_identification_override = CASE WHEN p_action = 'confirm_name' THEN p_requested_name ELSE NULL END,
            user_confirmed_identification = p_action = 'confirm_primary',confirmed_species_id = species,
            user_review_state = CASE WHEN p_action = 'confirm_primary' THEN 'ai_confirmed'::public.user_review_state
                WHEN p_action = 'confirm_name' THEN 'user_overridden'::public.user_review_state ELSE 'unreviewed'::public.user_review_state END
        WHERE id = p_scan_id;
    END IF;
    UPDATE public.scans SET ai_identification_review = next_review WHERE id = p_scan_id;
    PERFORM pg_catalog.SET_CONFIG('merian.ai_identification_review',COALESCE(previous_setting,''),TRUE);
    RETURN pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'scan_id',p_scan_id,'review',next_review,'species_review',species_receipt -> 'review',
        'confirmed_species_id',(SELECT confirmed_species_id FROM public.scans WHERE id = p_scan_id));
END;
$$;
REVOKE ALL ON FUNCTION public.apply_scan_identification_review(UUID,UUID,INTEGER,UUID,TEXT,TEXT,JSONB,INTEGER,UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.apply_scan_identification_review(UUID,UUID,INTEGER,UUID,TEXT,TEXT,JSONB,INTEGER,UUID,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.apply_scan_identification_review(uuid,uuid,integer,uuid,text,text,jsonb,integer,uuid,integer)','Owner-bound revisioned identification review with durable rejection and atomic acceptance.');


CREATE OR REPLACE FUNCTION internal.scan_effective_identification(candidate public.scans)
RETURNS JSONB LANGUAGE PLPGSQL STABLE PARALLEL SAFE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE primary_answer JSONB := candidate.primary_identification; review JSONB;
    explicit_result BOOLEAN := primary_answer IS NOT NULL
        OR COALESCE(candidate.identification_provenance ->> 'schema' = 'merian_identify_primary_v1', FALSE);
BEGIN
    IF internal.scan_has_unresolved_review(candidate) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','ai_primary','rank','unresolved_biological',
            'scientific_name',NULL,'common_name','Identification unresolved','primary',primary_answer,
            'species_id',NULL,'verified',FALSE,'pending_review',TRUE);
    END IF;
    IF candidate.ai_identification_review -> 'community' IS NOT NULL AND candidate.ai_identification_review -> 'community' <> 'null'::JSONB THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','verified_selection','rank',candidate.ai_identification_review #>> '{community,rank}',
            'scientific_name',candidate.ai_identification_review #>> '{community,scientific_name}',
            'common_name',candidate.ai_identification_review #>> '{community,common_name}',
            'primary',primary_answer,'species_id',candidate.ai_identification_review #> '{community,species_id}',
            'verified',candidate.ai_identification_review #>> '{community,rank}' = 'species','pending_review',FALSE);
    END IF;
    IF NOT explicit_result THEN
        -- Legacy records keep their existing identity and review semantics.
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','legacy','rank',NULL,
            'scientific_name',NULL,'common_name',NULL,'primary',NULL,
            'species_id',COALESCE(candidate.confirmed_species_id,candidate.species_id),
            'verified',FALSE,'pending_review',FALSE);
    END IF;
    review := pg_catalog.JSONB_BUILD_OBJECT('version',1,
        'revision',candidate.confirmed_species_identity_revision,'identity',candidate.confirmed_species_identity,
        'user_identification_override',candidate.user_identification_override,
        'user_confirmed_identification',candidate.user_confirmed_identification,
        'confirmed_species_id',candidate.confirmed_species_id,'user_review_state',candidate.user_review_state);
    IF primary_answer IS NULL
       OR candidate.identification_provenance ->> 'schema' IS DISTINCT FROM 'merian_identify_primary_v1'
       OR NOT internal.identification_provenance_is_valid(candidate.identification_provenance)
       OR NOT internal.primary_identification_is_valid(primary_answer)
       OR NOT internal.primary_identification_scan_is_valid(primary_answer,candidate.is_biological_subject,
            candidate.species_id,candidate.candidates,candidate.pet_identification)
       OR NOT internal.confirmed_species_review_is_valid(review) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','invalid','rank',NULL,
            'scientific_name',NULL,'common_name',NULL,'primary',NULL,
            'species_id',NULL,'verified',FALSE,'pending_review',FALSE);
    END IF;
    IF candidate.confirmed_species_identity IS NOT NULL AND candidate.is_biological_subject IS TRUE THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','verified_selection','rank','species',
            'scientific_name',candidate.confirmed_species_identity -> 'scientific_name',
            'common_name',candidate.confirmed_species_identity -> 'common_name',
            'primary',primary_answer,'species_id',candidate.confirmed_species_identity -> 'species_id',
            'verified',TRUE,'pending_review',FALSE);
    END IF;
    RETURN pg_catalog.JSONB_BUILD_OBJECT('source','ai_primary','rank',primary_answer -> 'resolution',
        'scientific_name',primary_answer -> 'scientific_name','common_name',primary_answer -> 'common_name',
        'primary',primary_answer,'species_id',CASE WHEN primary_answer ->> 'resolution' = 'species'
            AND candidate.user_review_state <> 'user_overridden' THEN candidate.species_id ELSE NULL END,
        'verified',FALSE,'pending_review',candidate.user_review_state <> 'unreviewed');
END;
$$;

CREATE OR REPLACE FUNCTION public.field_trip_scan_evidence_is_eligible(candidate scans)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT NOT internal.scan_has_unresolved_review(candidate)
        AND candidate.is_biological_subject IS NOT FALSE
        AND candidate.is_tombstoned IS NOT TRUE
        AND pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(
            COALESCE(candidate.user_identification_override, ''), '\s+', ' ', 'g'
        ))) NOT IN ('human', 'humans', 'human being', 'person', 'human breathing', 'human speech', 'human vocalisation', 'human vocalization', 'homo sapiens', 'homo sapien')
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary AS species
            WHERE species.id = internal.scan_effective_species_id(candidate)
              AND pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(
                  COALESCE(species.scientific_name, ''), '\s+', ' ', 'g'
              ))) NOT IN (
                  '', 'unknown', 'unknown subject', 'taxonomy unavailable',
                  'unidentified wildlife', 'no wildlife detected', 'not applicable',
                  'n/a', 'inanimate object', 'human', 'humans', 'human being',
                  'person', 'human breathing', 'human speech', 'human vocalisation',
                  'human vocalization', 'homo sapiens', 'homo sapien'
              )
        )
        AND (
            (internal.scan_effective_identification(candidate) ->> 'verified')::BOOLEAN
            OR (candidate.primary_identification IS NULL AND (candidate.confirmed_species_id IS NOT NULL OR candidate.user_confirmed_identification IS TRUE))
            OR internal.identification_metrics_are_gemini_compatible(
                candidate.identification_provenance, candidate.inference_tier
            )
        )
        AND public.field_trip_scan_identification_is_eligible(
            candidate.ai_confidence_score,
            candidate.inference_tier,
            CASE WHEN (internal.scan_effective_identification(candidate) ->> 'verified')::BOOLEAN THEN internal.scan_effective_species_id(candidate)
                WHEN candidate.primary_identification IS NULL THEN candidate.confirmed_species_id ELSE NULL END,
            CASE WHEN candidate.primary_identification IS NULL THEN candidate.user_confirmed_identification ELSE FALSE END
        );
$function$;
DROP TRIGGER trg_apply_ingested_scan_field_trip_progress_update ON public.scans;
CREATE TRIGGER trg_apply_ingested_scan_field_trip_progress_update
AFTER UPDATE OF ai_identification_review,
    primary_identification,
    confirmed_species_identity,
    confirmed_species_identity_revision,
    species_id,
    confirmed_species_id,
    ai_confidence_score,
    inference_tier,
    identification_provenance,
    user_confirmed_identification,
    user_identification_override,
    is_biological_subject,
    is_tombstoned,
    timestamp
ON public.scans
FOR EACH ROW
WHEN (
    OLD.ai_identification_review IS DISTINCT FROM NEW.ai_identification_review
    OR OLD.primary_identification IS DISTINCT FROM NEW.primary_identification
    OR OLD.confirmed_species_identity IS DISTINCT FROM NEW.confirmed_species_identity
    OR OLD.confirmed_species_identity_revision IS DISTINCT FROM NEW.confirmed_species_identity_revision
    OR OLD.species_id IS DISTINCT FROM NEW.species_id
    OR OLD.confirmed_species_id IS DISTINCT FROM NEW.confirmed_species_id
    OR OLD.ai_confidence_score IS DISTINCT FROM NEW.ai_confidence_score
    OR OLD.inference_tier IS DISTINCT FROM NEW.inference_tier
    OR OLD.identification_provenance IS DISTINCT FROM NEW.identification_provenance
    OR OLD.user_confirmed_identification IS DISTINCT FROM
        NEW.user_confirmed_identification
    OR OLD.user_identification_override IS DISTINCT FROM NEW.user_identification_override
    OR OLD.is_biological_subject IS DISTINCT FROM NEW.is_biological_subject
    OR OLD.is_tombstoned IS DISTINCT FROM NEW.is_tombstoned
    OR OLD.timestamp IS DISTINCT FROM NEW.timestamp
)
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();
-- Existing receipt comparisons must observe review changes even when species IDs are unchanged.
DO $migration$
DECLARE definition TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)'::REGPROCEDURE) INTO definition;
    IF pg_catalog.STRPOS(definition, '''species_id'', scan.species_id') = 0 THEN RAISE EXCEPTION 'field_trip_review_source_drift'; END IF;
    definition := pg_catalog.REPLACE(definition, '''species_id'', scan.species_id', '''ai_identification_review'', scan.ai_identification_review, ''species_id'', scan.species_id');
    EXECUTE definition;
END;
$migration$;

-- A consensus decision is a distinct server-owned authority. It never rewrites
-- AI evidence or masquerades as a GBIF-verified owner selection. Reversal revokes it.
CREATE FUNCTION internal.sync_community_identification_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE scan public.scans%ROWTYPE; taxon public.taxon_nodes%ROWTYPE; community JSONB;
    materialized UUID; previous_setting TEXT;
BEGIN
    SELECT * INTO scan FROM public.scans WHERE id = NEW.scan_id AND user_id = NEW.requested_by AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR scan.ai_identification_review IS NULL OR scan.ai_identification_review -> 'origin_scan_id' = 'null'::JSONB THEN RETURN NULL; END IF;
    -- Do not resurrect a superseded owner acceptance or an unrelated request.
    IF NOT internal.scan_has_unresolved_review(scan) AND scan.ai_identification_review #>> '{community,request_id}' IS DISTINCT FROM NEW.id::TEXT THEN RETURN NULL; END IF;
    IF NEW.status = 'resolved' AND NEW.withdrawn_at IS NULL THEN
        SELECT * INTO taxon FROM public.taxon_nodes WHERE id = NEW.resolved_taxon_node_id AND taxonomy_version_id = NEW.taxonomy_version_id;
        IF NOT FOUND OR taxon.rank NOT IN ('species','genus') THEN RETURN NULL; END IF;
        IF taxon.rank = 'species' THEN materialized := public.community_materialize_resolved_species(taxon.id); END IF;
        community := pg_catalog.JSONB_BUILD_OBJECT('request_id',NEW.id,'rank',taxon.rank,
            'scientific_name',taxon.scientific_name,'common_name',taxon.common_name,'species_id',materialized);
    ELSE
        community := NULL;
    END IF;
    previous_setting := pg_catalog.CURRENT_SETTING('merian.ai_identification_review',TRUE);
    PERFORM pg_catalog.SET_CONFIG('merian.ai_identification_review','on',TRUE);
    UPDATE public.scans SET ai_identification_review = scan.ai_identification_review || pg_catalog.JSONB_BUILD_OBJECT(
        'revision',(scan.ai_identification_review ->> 'revision')::INTEGER+1,
        'state',CASE WHEN community IS NULL THEN 'awaiting_acceptance' ELSE 'clear' END,
        'community',community,'operation_id',NULL,'operation_digest',NULL)
    WHERE id=scan.id;
    PERFORM pg_catalog.SET_CONFIG('merian.ai_identification_review',COALESCE(previous_setting,''),TRUE);
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.sync_community_identification_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER sync_community_identification_review AFTER UPDATE OF status,resolved_taxon_node_id,withdrawn_at
ON public.explore_community_requests FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.resolved_taxon_node_id IS DISTINCT FROM NEW.resolved_taxon_node_id OR OLD.withdrawn_at IS DISTINCT FROM NEW.withdrawn_at)
EXECUTE FUNCTION internal.sync_community_identification_review();

-- Publishing an already resolved community decision must not overwrite its
-- independent authority with the legacy confirmed-species tuple.
DO $publication$
DECLARE definition TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('public.publish_resolved_community_request_to_explore(uuid,uuid)'::REGPROCEDURE) INTO definition;
    IF pg_catalog.STRPOS(definition,'SET confirmed_species_id = materialized_species_id') = 0 THEN RAISE EXCEPTION 'community_review_source_drift'; END IF;
    EXECUTE pg_catalog.REPLACE(definition,'SET confirmed_species_id = materialized_species_id',
        'SET confirmed_species_id = CASE WHEN COALESCE(ai_identification_review -> ''community'',''null''::JSONB) <> ''null''::JSONB THEN confirmed_species_id ELSE materialized_species_id END');
END;
$publication$;

CREATE FUNCTION internal.require_identification_review_reader(p_review JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE headers JSONB;
BEGIN
    IF COALESCE(p_review ->> 'state','clear') = 'clear' AND COALESCE(p_review -> 'community','null'::JSONB) = 'null'::JSONB THEN RETURN TRUE; END IF;
    BEGIN headers := NULLIF(pg_catalog.CURRENT_SETTING('request.headers',TRUE),'')::JSONB;
    EXCEPTION WHEN invalid_text_representation THEN headers := NULL; END;
    IF headers ->> 'x-merian-identification-protocol' = '6' THEN RETURN TRUE; END IF;
    RAISE SQLSTATE 'PT426' USING MESSAGE = 'client_update_required',HINT = 'Update Naturebook to read this identification.';
END;
$$;
REVOKE ALL ON FUNCTION internal.require_identification_review_reader(JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION internal.require_identification_review_reader(JSONB) TO anon,authenticated;
DO $migration$
DECLARE definition TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('internal.require_identification_result_reader(jsonb,jsonb)'::REGPROCEDURE) INTO definition;
    IF pg_catalog.STRPOS(definition, 'headers -> ''x-merian-identification-protocol'' = ''"5"''::JSONB') = 0 THEN RAISE EXCEPTION 'review_reader_source_drift'; END IF;
    EXECUTE pg_catalog.REPLACE(definition,'headers -> ''x-merian-identification-protocol'' = ''"5"''::JSONB',
        'headers -> ''x-merian-identification-protocol'' IN (''"5"''::JSONB,''"6"''::JSONB)');
END;
$migration$;
ALTER POLICY "Users can fully read their own private scans" ON public.scans USING (
    CASE WHEN (SELECT auth.uid()) = user_id THEN
        internal.require_identification_review_reader(ai_identification_review)
        AND internal.require_identification_result_reader(identification_provenance,primary_identification)
    ELSE FALSE END);
ALTER POLICY "Anyone can read open and live scans" ON public.scans USING (
    CASE WHEN geoprivacy = 'open' AND is_live_capture = TRUE AND is_tombstoned = FALSE THEN
        internal.require_identification_review_reader(ai_identification_review)
        AND internal.require_identification_result_reader(identification_provenance,primary_identification)
    ELSE FALSE END);


-- Capability 6 understands rejection; provider binding minimum remains unchanged.
ALTER TABLE internal.identification_provider_attempts
    DROP CONSTRAINT identification_attempt_accepted_protocol_check,
    ADD CONSTRAINT identification_attempt_accepted_protocol_check CHECK (accepted_identification_protocol IN (4,5,6));
DO $capability$
DECLARE definition TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_CONSTRAINTDEF(oid) INTO STRICT definition FROM pg_catalog.pg_constraint
    WHERE conrelid = 'internal.identification_provider_attempts'::REGCLASS AND conname = 'identification_provider_attempts_recipient_tuple';
    IF pg_catalog.STRPOS(definition, 'ARRAY[4, 5]') = 0 THEN RAISE EXCEPTION 'review_capability_constraint_drift'; END IF;
    ALTER TABLE internal.identification_provider_attempts DROP CONSTRAINT identification_provider_attempts_recipient_tuple;
    EXECUTE 'ALTER TABLE internal.identification_provider_attempts ADD CONSTRAINT identification_provider_attempts_recipient_tuple ' || pg_catalog.REPLACE(definition,'ARRAY[4, 5]','ARRAY[4, 5, 6]');
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('internal.require_identification_capability(uuid,text,uuid,text,integer,boolean,integer)'::REGPROCEDURE) INTO definition;
    IF pg_catalog.STRPOS(definition, 'IN (4, 5)') = 0 THEN RAISE EXCEPTION 'review_capability_source_drift'; END IF;
    EXECUTE pg_catalog.REPLACE(definition, 'IN (4, 5)', 'IN (4, 5, 6)');
END;
$capability$;

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;
