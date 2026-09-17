-- Preserve lookalike accounting and refresh provenance while avoiding new
-- dictionary/relationship tuple versions for identical model results.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.persist_species_model_lookalikes(
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
    proposed_candidate public.species_dictionary;
    proposed_names TEXT[];
    candidate JSONB;
    gbif JSONB;
    candidate_name TEXT;
    candidate_key INTEGER;
    candidate_id UUID;
    relation_status TEXT;
    relation_source TEXT;
    candidate_order INTEGER := 0;
    seen_ids UUID[] := ARRAY[]::UUID[];
    model_refresh_count INTEGER := 0;
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
            proposed_candidate := candidate_species;
            proposed_candidate.gbif_taxon_key := CASE WHEN candidate_species.gbif_taxon_key > 0 THEN candidate_species.gbif_taxon_key ELSE candidate_key END;
            proposed_candidate.kingdom := CASE WHEN public.species_dictionary_taxonomy_value_is_usable(candidate_species.kingdom) THEN candidate_species.kingdom ELSE gbif ->> 'kingdom' END;
            proposed_candidate.phylum := CASE WHEN public.species_dictionary_taxonomy_value_is_usable(candidate_species.phylum) THEN candidate_species.phylum ELSE COALESCE(gbif ->> 'phylum', candidate_species.phylum) END;
            proposed_candidate.class := CASE WHEN public.species_dictionary_taxonomy_value_is_usable(candidate_species.class) THEN candidate_species.class ELSE COALESCE(gbif ->> 'class', candidate_species.class) END;
            proposed_candidate."order" := CASE WHEN public.species_dictionary_taxonomy_value_is_usable(candidate_species."order") THEN candidate_species."order" ELSE COALESCE(gbif ->> 'order', candidate_species."order") END;
            proposed_candidate.family := CASE WHEN public.species_dictionary_taxonomy_value_is_usable(candidate_species.family) THEN candidate_species.family ELSE COALESCE(gbif ->> 'family', candidate_species.family) END;
            proposed_candidate.genus := CASE WHEN public.species_dictionary_taxonomy_value_is_usable(candidate_species.genus) THEN candidate_species.genus ELSE COALESCE(gbif ->> 'genus', candidate_species.genus) END;

            -- Do not clear the locked candidate via UPDATE ... RETURNING when
            -- a conditional update affects no rows. Unchanged is still valid.
            IF ROW(candidate_species.gbif_taxon_key, candidate_species.kingdom,
                   candidate_species.phylum, candidate_species.class,
                   candidate_species."order", candidate_species.family, candidate_species.genus)
               IS DISTINCT FROM
               ROW(proposed_candidate.gbif_taxon_key, proposed_candidate.kingdom,
                   proposed_candidate.phylum, proposed_candidate.class,
                   proposed_candidate."order", proposed_candidate.family, proposed_candidate.genus) THEN
                UPDATE public.species_dictionary AS species
                SET gbif_taxon_key = proposed_candidate.gbif_taxon_key,
                    kingdom = proposed_candidate.kingdom,
                    phylum = proposed_candidate.phylum,
                    class = proposed_candidate.class,
                    "order" = proposed_candidate."order",
                    family = proposed_candidate.family,
                    genus = proposed_candidate.genus
                WHERE species.id = candidate_species.id
                RETURNING * INTO candidate_species;
            END IF;
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
          AND relation.source IN ('model_enrichment', 'taxonomy_trigger', 'system_backfill', 'unknown')
          AND ROW(relation.reason, relation.visual_traits, relation.confidence,
                  relation.source, relation.is_bidirectional, relation.sort_order)
              IS DISTINCT FROM
              ROW(EXCLUDED.reason, EXCLUDED.visual_traits, EXCLUDED.confidence,
                  EXCLUDED.source, FALSE, EXCLUDED.sort_order);
        -- ON CONFLICT locks even an unchanged eligible row. Freshness records
        -- a successful model refresh, independently of physical tuple updates.
        SELECT review_status, source INTO relation_status, relation_source
        FROM public.species_lookalikes
        WHERE species_id = subject.id AND lookalike_id = candidate_id;
        IF relation_status = 'unreviewed' AND relation_source = 'model_enrichment' THEN
            model_refresh_count := model_refresh_count + 1;
        END IF;
        IF relation_status = 'rejected' THEN
            rejected_count := rejected_count + 1;
        ELSE
            persisted_count := persisted_count + 1;
        END IF;
        candidate_order := candidate_order + 1;
    END LOOP;

    IF persisted_count > 0 OR (resolution_complete AND unresolved_count = 0) THEN
        proposed_names := ARRAY(
            SELECT species.scientific_name
            FROM public.species_lookalikes AS relation
            JOIN public.species_dictionary AS species ON species.id = relation.lookalike_id
            WHERE relation.species_id = subject.id
              AND relation.review_status <> 'rejected'
            ORDER BY relation.sort_order, species.scientific_name
        );
        UPDATE public.species_dictionary
        SET lookalikes_flash_attempted = TRUE, similar_species = proposed_names
        WHERE id = subject.id
          AND (lookalikes_flash_attempted IS DISTINCT FROM TRUE
               OR similar_species IS DISTINCT FROM proposed_names);
    END IF;
    IF model_refresh_count > 0 THEN
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

REVOKE ALL ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN) TO service_role;

RESET statement_timeout;
RESET lock_timeout;
