-- The new worker claims legacy empty outcomes itself. Merely applying this
-- migration must not reopen jobs for an older deployed worker.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

CREATE INDEX idx_species_enrichment_jobs_legacy_lookalikes
    ON public.species_enrichment_jobs (priority, next_run_at, created_at, id)
    WHERE content_group = 'lookalikes'
      AND status IN ('succeeded', 'failed')
      AND NOT (metadata ? 'lookalike_resolution_version');

CREATE FUNCTION public.claim_species_model_enrichment_jobs(
    max_rows INTEGER DEFAULT 12,
    as_of TIMESTAMPTZ DEFAULT NOW(),
    target_content_groups TEXT[] DEFAULT ARRAY['habitat', 'lookalikes', 'group_tags']::TEXT[],
    preview_only BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    job_id UUID,
    species_id UUID,
    scientific_name TEXT,
    content_group TEXT,
    priority INTEGER,
    attempts INTEGER,
    max_attempts INTEGER,
    source_trigger TEXT,
    metadata JSONB
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF max_rows IS NULL OR max_rows < 1 OR max_rows > 50
       OR preview_only IS NULL
       OR COALESCE(pg_catalog.ARRAY_LENGTH(target_content_groups, 1), 0) = 0
       OR pg_catalog.ARRAY_LENGTH(target_content_groups, 1) > 3
       OR pg_catalog.ARRAY_POSITION(target_content_groups, NULL) IS NOT NULL
       OR NOT target_content_groups <@ ARRAY['habitat', 'lookalikes', 'group_tags']::TEXT[] THEN
        RAISE EXCEPTION 'invalid_species_model_job_request' USING ERRCODE = '22023';
    END IF;

    -- Preview uses the same bounded eligibility rules without taking job locks
    -- or advancing the recovery marker.
    IF preview_only THEN
        RETURN QUERY
        SELECT job.id, job.species_id, species.scientific_name,
            job.content_group, job.priority, job.attempts, job.max_attempts,
            job.source_trigger, job.metadata
        FROM public.species_enrichment_jobs AS job
        JOIN public.species_dictionary AS species ON species.id = job.species_id
        WHERE job.content_group = ANY(target_content_groups)
          AND (
            (job.status IN ('queued', 'failed')
                AND job.attempts < job.max_attempts
                AND job.next_run_at <= COALESCE(as_of, pg_catalog.NOW()))
            OR (job.content_group = 'lookalikes'
                AND (job.status = 'succeeded'
                    OR (job.status = 'failed' AND job.attempts >= job.max_attempts))
                AND NOT (job.metadata ? 'lookalike_resolution_version')
                AND species.is_public_biological
                AND NOT EXISTS (
                    SELECT 1 FROM public.species_lookalikes AS relation
                    WHERE relation.species_id = job.species_id
                      AND relation.review_status <> 'rejected'
                ))
          )
        ORDER BY job.priority, job.next_run_at, job.created_at, job.id
        LIMIT max_rows;
        RETURN;
    END IF;

    RETURN QUERY
    WITH eligible AS MATERIALIZED (
        SELECT job.*,
            job.content_group = 'lookalikes'
                AND (job.status = 'succeeded'
                    OR (job.status = 'failed' AND job.attempts >= job.max_attempts))
                AS legacy_recovery
        FROM public.species_enrichment_jobs AS job
        JOIN public.species_dictionary AS species ON species.id = job.species_id
        WHERE job.content_group = ANY(target_content_groups)
          AND (
            (job.status IN ('queued', 'failed')
                AND job.attempts < job.max_attempts
                AND job.next_run_at <= COALESCE(as_of, pg_catalog.NOW()))
            OR (job.content_group = 'lookalikes'
                AND (job.status = 'succeeded'
                    OR (job.status = 'failed' AND job.attempts >= job.max_attempts))
                AND NOT (job.metadata ? 'lookalike_resolution_version')
                AND species.is_public_biological
                AND NOT EXISTS (
                    SELECT 1 FROM public.species_lookalikes AS relation
                    WHERE relation.species_id = job.species_id
                      AND relation.review_status <> 'rejected'
                ))
          )
        ORDER BY job.priority, job.next_run_at, job.created_at, job.id
        LIMIT max_rows
        FOR UPDATE OF job SKIP LOCKED
    ), claimed AS (
        UPDATE public.species_enrichment_jobs AS job
        SET status = 'running',
            attempts = CASE WHEN eligible.legacy_recovery THEN 1 ELSE job.attempts + 1 END,
            locked_at = pg_catalog.NOW(),
            completed_at = NULL,
            updated_at = pg_catalog.NOW(),
            metadata = job.metadata || CASE WHEN job.content_group = 'lookalikes'
                THEN pg_catalog.JSONB_BUILD_OBJECT('lookalike_resolution_version', 1)
                ELSE '{}'::JSONB END
        FROM eligible
        WHERE job.id = eligible.id
        RETURNING job.id, job.species_id, job.content_group, job.priority,
            job.attempts, job.max_attempts, job.source_trigger, job.metadata,
            job.next_run_at, job.created_at
    )
    SELECT claimed.id, claimed.species_id, species.scientific_name,
        claimed.content_group, claimed.priority, claimed.attempts,
        claimed.max_attempts, claimed.source_trigger, claimed.metadata
    FROM claimed
    JOIN public.species_dictionary AS species ON species.id = claimed.species_id
    ORDER BY claimed.priority, claimed.next_run_at, claimed.created_at, claimed.id;
END;
$$;

-- A model candidate still gets reference, habitat and tag hydration, but must
-- not recursively generate more candidates just because it was materialized.
-- The owner-only insert trigger also serves normal dictionary writers, whose
-- existing missing-group behavior remains intact.
CREATE OR REPLACE FUNCTION public.enqueue_species_dictionary_enrichment_jobs()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    missing_groups TEXT[];
BEGIN
    missing_groups := public.species_dictionary_missing_enrichment_groups(NEW);
    IF pg_catalog.CURRENT_SETTING('merian.lookalike_candidate_materialization', TRUE) = 'on' THEN
        missing_groups := pg_catalog.ARRAY_REMOVE(missing_groups, 'lookalikes');
    END IF;
    IF COALESCE(pg_catalog.ARRAY_LENGTH(missing_groups, 1), 0) > 0 THEN
        PERFORM public.enqueue_species_enrichment_jobs(
            NEW.id, 'species_dictionary_insert', 90, missing_groups
        );
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_species_dictionary_enrichment_jobs()
    FROM PUBLIC, anon, authenticated, service_role;

-- Model materialization writes only the validated subject-to-candidate edge.
-- Ordinary dictionary inserts retain the existing same-genus auto-linking.
CREATE OR REPLACE TRIGGER trg_link_taxonomy_lookalikes
    AFTER INSERT ON public.species_dictionary
    FOR EACH ROW
    WHEN (pg_catalog.CURRENT_SETTING('merian.lookalike_candidate_materialization', TRUE) IS DISTINCT FROM 'on')
    EXECUTE FUNCTION public.trg_link_taxonomy_lookalikes_fn();

-- Only the scheduled worker supplies GBIF-validated candidate identities. The
-- transaction checks the current taxonomy again and preserves review decisions.
CREATE FUNCTION public.persist_species_model_lookalikes(
    target_species_id UUID,
    candidates JSONB,
    resolution_complete BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (persisted_count INTEGER, unresolved_count INTEGER, rejected_count INTEGER)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    subject public.species_dictionary;
    candidate_species public.species_dictionary;
    candidate JSONB;
    gbif JSONB;
    candidate_name TEXT;
    candidate_key INTEGER;
    candidate_id UUID;
    relation_status TEXT;
    candidate_order INTEGER := 0;
    seen_ids UUID[] := ARRAY[]::UUID[];
    affected_rows INTEGER;
    model_write_count INTEGER := 0;
    previous_materialization_setting TEXT;
BEGIN
    PERFORM internal.require_service_role();
    IF target_species_id IS NULL OR resolution_complete IS NULL
       OR pg_catalog.JSONB_TYPEOF(candidates) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(candidates) > 3 THEN
        RAISE EXCEPTION 'invalid_species_lookalike_candidates' USING ERRCODE = '22023';
    END IF;

    -- At most three candidate dictionary/relationship writes, with no network
    -- work in this transaction. Serialize this low-volume writer so reciprocal
    -- candidate relations and concurrent materialization cannot take subject
    -- and candidate locks in reverse order.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED('merian:species-model-lookalikes', 0)
    );
    SELECT * INTO subject FROM public.species_dictionary
    WHERE id = target_species_id FOR NO KEY UPDATE;
    IF subject.id IS NULL THEN
        RAISE EXCEPTION 'species_lookalike_subject_missing' USING ERRCODE = '22023';
    END IF;

    persisted_count := 0;
    unresolved_count := 0;
    rejected_count := 0;
    IF NOT public.species_dictionary_taxonomy_value_is_usable(subject.kingdom)
       OR NOT (public.species_dictionary_taxonomy_value_is_usable(subject."order")
               OR public.species_dictionary_taxonomy_value_is_usable(subject.family)) THEN
        RAISE EXCEPTION 'species_lookalike_taxonomy_not_ready' USING ERRCODE = '55000';
    END IF;

    FOR candidate IN SELECT value FROM pg_catalog.JSONB_ARRAY_ELEMENTS(candidates) LOOP
        candidate_species := NULL;
        candidate_id := NULL;
        gbif := candidate -> 'gbif';
        candidate_name := NULLIF(pg_catalog.BTRIM(candidate ->> 'scientific_name'), '');
        IF pg_catalog.JSONB_TYPEOF(candidate) IS DISTINCT FROM 'object'
           OR candidate_name IS NULL OR pg_catalog.LENGTH(candidate_name) > 160 THEN
            RAISE EXCEPTION 'invalid_species_lookalike_candidate' USING ERRCODE = '22023';
        END IF;
        IF pg_catalog.LOWER(candidate_name) = pg_catalog.LOWER(subject.scientific_name) THEN
            rejected_count := rejected_count + 1;
            CONTINUE;
        END IF;

        IF pg_catalog.JSONB_TYPEOF(gbif) IS DISTINCT FROM 'object'
           OR gbif ->> 'rank' IS DISTINCT FROM 'SPECIES'
           OR gbif ->> 'status' IS DISTINCT FROM 'ACCEPTED'
           OR gbif ->> 'scientific_name' IS DISTINCT FROM candidate_name
           OR pg_catalog.JSONB_TYPEOF(gbif -> 'gbif_taxon_key') IS DISTINCT FROM 'number'
           OR (gbif ->> 'gbif_taxon_key') !~ '^[1-9][0-9]{0,9}$'
           OR (gbif ->> 'gbif_taxon_key')::NUMERIC > 2147483647 THEN
            RAISE EXCEPTION 'invalid_species_lookalike_gbif_identity' USING ERRCODE = '22023';
        END IF;
        candidate_key := (gbif ->> 'gbif_taxon_key')::INTEGER;
        IF candidate_key = subject.gbif_taxon_key THEN
            rejected_count := rejected_count + 1;
            CONTINUE;
        END IF;
        IF NOT public.species_dictionary_taxonomy_value_is_usable(gbif ->> 'kingdom')
           OR pg_catalog.LOWER(pg_catalog.BTRIM(gbif ->> 'kingdom')) <> pg_catalog.LOWER(pg_catalog.BTRIM(subject.kingdom))
           OR (public.species_dictionary_taxonomy_value_is_usable(subject."order")
               AND (NOT public.species_dictionary_taxonomy_value_is_usable(gbif ->> 'order')
                   OR pg_catalog.LOWER(pg_catalog.BTRIM(gbif ->> 'order')) <> pg_catalog.LOWER(pg_catalog.BTRIM(subject."order"))))
           OR (NOT public.species_dictionary_taxonomy_value_is_usable(subject."order")
               AND (NOT public.species_dictionary_taxonomy_value_is_usable(gbif ->> 'family')
                   OR pg_catalog.LOWER(pg_catalog.BTRIM(gbif ->> 'family')) <> pg_catalog.LOWER(pg_catalog.BTRIM(subject.family)))) THEN
            rejected_count := rejected_count + 1;
            CONTINUE;
        END IF;

        previous_materialization_setting := pg_catalog.CURRENT_SETTING(
            'merian.lookalike_candidate_materialization', TRUE
        );
        PERFORM pg_catalog.SET_CONFIG('merian.lookalike_candidate_materialization', 'on', TRUE);
        INSERT INTO public.species_dictionary (
            scientific_name, common_names, gbif_taxon_key,
            kingdom, phylum, class, "order", family, genus, native_region
        ) VALUES (
            candidate_name,
            CASE WHEN NULLIF(pg_catalog.BTRIM(candidate ->> 'common_name'), '') IS NOT NULL
                THEN pg_catalog.JSONB_BUILD_OBJECT('en', pg_catalog.LEFT(pg_catalog.BTRIM(candidate ->> 'common_name'), 160))
                ELSE '{}'::JSONB END,
            candidate_key, gbif ->> 'kingdom',
            COALESCE(gbif ->> 'phylum', 'Unknown'),
            COALESCE(gbif ->> 'class', 'Unknown'),
            COALESCE(gbif ->> 'order', 'Unknown'),
            COALESCE(gbif ->> 'family', 'Unknown'),
            COALESCE(gbif ->> 'genus', 'Unknown'), 'Unknown'
        ) ON CONFLICT (scientific_name) DO NOTHING;
        PERFORM pg_catalog.SET_CONFIG(
            'merian.lookalike_candidate_materialization',
            COALESCE(previous_materialization_setting, ''), TRUE
        );

        SELECT * INTO candidate_species FROM public.species_dictionary
        WHERE scientific_name = candidate_name FOR NO KEY UPDATE;
        IF candidate_species.gbif_taxon_key > 0 AND candidate_species.gbif_taxon_key <> candidate_key THEN
            unresolved_count := unresolved_count + 1;
            CONTINUE;
        END IF;
        IF candidate_species.id IS NOT NULL THEN
            UPDATE public.species_dictionary AS species
            SET gbif_taxon_key = CASE WHEN species.gbif_taxon_key > 0 THEN species.gbif_taxon_key ELSE candidate_key END,
                kingdom = CASE WHEN public.species_dictionary_taxonomy_value_is_usable(species.kingdom) THEN species.kingdom ELSE gbif ->> 'kingdom' END,
                phylum = CASE WHEN public.species_dictionary_taxonomy_value_is_usable(species.phylum) THEN species.phylum ELSE COALESCE(gbif ->> 'phylum', species.phylum) END,
                class = CASE WHEN public.species_dictionary_taxonomy_value_is_usable(species.class) THEN species.class ELSE COALESCE(gbif ->> 'class', species.class) END,
                "order" = CASE WHEN public.species_dictionary_taxonomy_value_is_usable(species."order") THEN species."order" ELSE COALESCE(gbif ->> 'order', species."order") END,
                family = CASE WHEN public.species_dictionary_taxonomy_value_is_usable(species.family) THEN species.family ELSE COALESCE(gbif ->> 'family', species.family) END,
                genus = CASE WHEN public.species_dictionary_taxonomy_value_is_usable(species.genus) THEN species.genus ELSE COALESCE(gbif ->> 'genus', species.genus) END
            WHERE species.id = candidate_species.id
            RETURNING * INTO candidate_species;
        END IF;
        IF candidate_species.id IS NULL THEN
            unresolved_count := unresolved_count + 1;
            CONTINUE;
        END IF;
        candidate_id := candidate_species.id;
        IF candidate_id = subject.id THEN
            rejected_count := rejected_count + 1;
            CONTINUE;
        END IF;
        IF candidate_id = ANY(seen_ids) THEN
            rejected_count := rejected_count + 1;
            CONTINUE;
        END IF;
        seen_ids := pg_catalog.ARRAY_APPEND(seen_ids, candidate_id);

        IF NOT public.species_dictionary_taxonomy_value_is_usable(candidate_species.kingdom)
           OR NOT (public.species_dictionary_taxonomy_value_is_usable(candidate_species."order")
                   OR public.species_dictionary_taxonomy_value_is_usable(candidate_species.family)) THEN
            unresolved_count := unresolved_count + 1;
            CONTINUE;
        END IF;
        IF pg_catalog.LOWER(pg_catalog.BTRIM(candidate_species.kingdom)) <> pg_catalog.LOWER(pg_catalog.BTRIM(subject.kingdom))
           OR (public.species_dictionary_taxonomy_value_is_usable(subject."order")
               AND (NOT public.species_dictionary_taxonomy_value_is_usable(candidate_species."order")
                   OR pg_catalog.LOWER(pg_catalog.BTRIM(candidate_species."order")) <> pg_catalog.LOWER(pg_catalog.BTRIM(subject."order"))))
           OR (NOT public.species_dictionary_taxonomy_value_is_usable(subject."order")
               AND pg_catalog.LOWER(pg_catalog.BTRIM(candidate_species.family)) IS DISTINCT FROM pg_catalog.LOWER(pg_catalog.BTRIM(subject.family))) THEN
            rejected_count := rejected_count + 1;
            CONTINUE;
        END IF;

        INSERT INTO public.species_lookalikes AS relation (
            species_id, lookalike_id, reason, visual_traits, confidence,
            source, review_status, is_bidirectional, sort_order
        ) VALUES (
            subject.id, candidate_id,
            NULLIF(pg_catalog.LEFT(pg_catalog.BTRIM(candidate ->> 'reason'), 500), ''),
            ARRAY(SELECT pg_catalog.LEFT(pg_catalog.BTRIM(value), 80)
                FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(COALESCE(candidate -> 'visual_traits', '[]'::JSONB))
                WHERE NULLIF(pg_catalog.BTRIM(value), '') IS NOT NULL LIMIT 5),
            COALESCE((candidate ->> 'confidence')::NUMERIC, 0.8),
            'model_enrichment', 'unreviewed', FALSE, candidate_order
        ) ON CONFLICT (species_id, lookalike_id) DO UPDATE
        SET reason = EXCLUDED.reason, visual_traits = EXCLUDED.visual_traits,
            confidence = EXCLUDED.confidence, source = EXCLUDED.source,
            is_bidirectional = FALSE, sort_order = EXCLUDED.sort_order
        WHERE relation.review_status = 'unreviewed'
          AND relation.source IN ('model_enrichment', 'taxonomy_trigger', 'system_backfill', 'unknown');
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
        model_write_count := model_write_count + affected_rows;
        SELECT review_status INTO relation_status FROM public.species_lookalikes
        WHERE species_id = subject.id AND lookalike_id = candidate_id;
        IF relation_status = 'rejected' THEN
            rejected_count := rejected_count + 1;
        ELSE
            persisted_count := persisted_count + 1;
        END IF;
        candidate_order := candidate_order + 1;
    END LOOP;

    IF persisted_count > 0 OR (resolution_complete AND unresolved_count = 0) THEN
        UPDATE public.species_dictionary
        SET lookalikes_flash_attempted = TRUE,
            similar_species = ARRAY(
                SELECT species.scientific_name
                FROM public.species_lookalikes AS relation
                JOIN public.species_dictionary AS species ON species.id = relation.lookalike_id
                WHERE relation.species_id = subject.id
                  AND relation.review_status <> 'rejected'
                ORDER BY relation.sort_order, species.scientific_name
            )
        WHERE id = subject.id;
    END IF;
    IF model_write_count > 0 THEN
        INSERT INTO public.species_content_provenance AS provenance (
            species_id, content_key, source, source_detail, confidence,
            metadata, last_refreshed_at, refresh_after
        ) VALUES (
            subject.id, 'lookalikes', 'model_enrichment',
            'validated similar-species generation', 0.8,
            pg_catalog.JSONB_BUILD_OBJECT('count', persisted_count),
            pg_catalog.NOW(), pg_catalog.NOW() + INTERVAL '30 days'
        ) ON CONFLICT (species_id, content_key) DO UPDATE
        SET source = EXCLUDED.source, source_detail = EXCLUDED.source_detail,
            confidence = EXCLUDED.confidence, metadata = EXCLUDED.metadata,
            last_refreshed_at = EXCLUDED.last_refreshed_at,
            refresh_after = EXCLUDED.refresh_after
        WHERE provenance.source NOT IN ('manual_curation', 'user_review');
    END IF;
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_species_model_enrichment_jobs(INTEGER, TIMESTAMPTZ, TEXT[], BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_species_model_enrichment_jobs(INTEGER, TIMESTAMPTZ, TEXT[], BOOLEAN) TO service_role;
GRANT EXECUTE ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants (role_name, routine_signature, purpose) VALUES
    ('service_role', 'public.claim_species_model_enrichment_jobs(integer,timestamp with time zone,text[],boolean)', 'Bounded model-worker claims and one-time legacy lookalike recovery.'),
    ('service_role', 'public.persist_species_model_lookalikes(uuid,jsonb,boolean)', 'Persist validated model lookalikes and settled empty results without overriding reviewed relationships.');

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
