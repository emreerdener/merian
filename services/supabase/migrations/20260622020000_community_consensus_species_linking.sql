ALTER TABLE public.taxon_nodes
    ADD COLUMN IF NOT EXISTS gbif_taxon_key INTEGER;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.taxon_nodes'::REGCLASS
          AND conname = 'taxon_nodes_gbif_taxon_key_positive_check'
    ) THEN
        ALTER TABLE public.taxon_nodes
            ADD CONSTRAINT taxon_nodes_gbif_taxon_key_positive_check
            CHECK (gbif_taxon_key IS NULL OR gbif_taxon_key > 0);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxon_nodes_version_gbif_key_unique
    ON public.taxon_nodes(taxonomy_version_id, gbif_taxon_key)
    WHERE gbif_taxon_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.community_materialize_resolved_species(
    target_taxon_node_id UUID
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_taxon public.taxon_nodes;
    materialized_species_id UUID;
    lineage_kingdom TEXT;
    lineage_phylum TEXT;
    lineage_class TEXT;
    lineage_order TEXT;
    lineage_family TEXT;
    lineage_genus TEXT;
    now_value TIMESTAMPTZ := NOW();
BEGIN
    SELECT *
    INTO target_taxon
    FROM public.taxon_nodes
    WHERE id = target_taxon_node_id
    FOR UPDATE;

    IF target_taxon.id IS NULL THEN
        RAISE EXCEPTION 'Resolved community taxon not found.' USING ERRCODE = 'P0001';
    END IF;

    IF target_taxon.rank <> 'species' THEN
        RAISE EXCEPTION 'Only species-level community taxa can be materialized into species_dictionary.' USING ERRCODE = 'P0001';
    END IF;

    IF target_taxon.species_id IS NOT NULL THEN
        RETURN target_taxon.species_id;
    END IF;

    SELECT
        MAX(tn.scientific_name) FILTER (WHERE tn.rank = 'kingdom'),
        MAX(tn.scientific_name) FILTER (WHERE tn.rank = 'phylum'),
        MAX(tn.scientific_name) FILTER (WHERE tn.rank = 'class'),
        MAX(tn.scientific_name) FILTER (WHERE tn.rank = 'order'),
        MAX(tn.scientific_name) FILTER (WHERE tn.rank = 'family'),
        MAX(tn.scientific_name) FILTER (WHERE tn.rank = 'genus')
    INTO
        lineage_kingdom,
        lineage_phylum,
        lineage_class,
        lineage_order,
        lineage_family,
        lineage_genus
    FROM public.taxon_nodes tn
    WHERE tn.taxonomy_version_id = target_taxon.taxonomy_version_id
      AND tn.path @> target_taxon.path;

    INSERT INTO public.species_dictionary (
        scientific_name,
        common_names,
        kingdom,
        phylum,
        class,
        "order",
        family,
        genus,
        native_region,
        gbif_taxon_key,
        created_at
    )
    VALUES (
        target_taxon.scientific_name,
        CASE
            WHEN NULLIF(BTRIM(COALESCE(target_taxon.common_name, '')), '') IS NULL THEN '{}'::JSONB
            ELSE JSONB_BUILD_OBJECT('en', BTRIM(target_taxon.common_name))
        END,
        COALESCE(NULLIF(BTRIM(lineage_kingdom), ''), 'Unknown'),
        COALESCE(NULLIF(BTRIM(lineage_phylum), ''), 'Unknown'),
        COALESCE(NULLIF(BTRIM(lineage_class), ''), 'Unknown'),
        COALESCE(NULLIF(BTRIM(lineage_order), ''), 'Unknown'),
        COALESCE(NULLIF(BTRIM(lineage_family), ''), 'Unknown'),
        COALESCE(NULLIF(BTRIM(lineage_genus), ''), 'Unknown'),
        'Unknown',
        target_taxon.gbif_taxon_key,
        now_value
    )
    ON CONFLICT (scientific_name) DO UPDATE
    SET common_names = CASE
            WHEN public.species_dictionary.common_names = '{}'::JSONB
                 AND EXCLUDED.common_names <> '{}'::JSONB
                THEN EXCLUDED.common_names
            ELSE public.species_dictionary.common_names
        END,
        kingdom = CASE WHEN public.species_dictionary.kingdom = 'Unknown' THEN EXCLUDED.kingdom ELSE public.species_dictionary.kingdom END,
        phylum = CASE WHEN public.species_dictionary.phylum = 'Unknown' THEN EXCLUDED.phylum ELSE public.species_dictionary.phylum END,
        class = CASE WHEN public.species_dictionary.class = 'Unknown' THEN EXCLUDED.class ELSE public.species_dictionary.class END,
        "order" = CASE WHEN public.species_dictionary."order" = 'Unknown' THEN EXCLUDED."order" ELSE public.species_dictionary."order" END,
        family = CASE WHEN public.species_dictionary.family = 'Unknown' THEN EXCLUDED.family ELSE public.species_dictionary.family END,
        genus = CASE WHEN public.species_dictionary.genus = 'Unknown' THEN EXCLUDED.genus ELSE public.species_dictionary.genus END,
        gbif_taxon_key = COALESCE(public.species_dictionary.gbif_taxon_key, EXCLUDED.gbif_taxon_key)
    RETURNING id INTO materialized_species_id;

    UPDATE public.taxon_nodes
    SET species_id = NULL,
        updated_at = now_value
    WHERE taxonomy_version_id = target_taxon.taxonomy_version_id
      AND species_id = materialized_species_id
      AND id <> target_taxon.id;

    UPDATE public.taxon_nodes
    SET species_id = materialized_species_id,
        updated_at = now_value
    WHERE id = target_taxon.id;

    INSERT INTO public.taxon_names (
        taxonomy_version_id,
        taxon_node_id,
        kind,
        name,
        normalized_name,
        is_primary
    )
    VALUES (
        target_taxon.taxonomy_version_id,
        target_taxon.id,
        'scientific',
        target_taxon.scientific_name,
        LOWER(BTRIM(target_taxon.scientific_name)),
        TRUE
    )
    ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

    IF NULLIF(BTRIM(COALESCE(target_taxon.common_name, '')), '') IS NOT NULL THEN
        INSERT INTO public.taxon_names (
            taxonomy_version_id,
            taxon_node_id,
            kind,
            name,
            normalized_name,
            is_primary
        )
        VALUES (
            target_taxon.taxonomy_version_id,
            target_taxon.id,
            'common',
            BTRIM(target_taxon.common_name),
            LOWER(BTRIM(target_taxon.common_name)),
            TRUE
        )
        ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;
    END IF;

    INSERT INTO public.species_content_provenance (
        species_id,
        content_key,
        source,
        source_detail,
        confidence,
        metadata,
        last_refreshed_at,
        refresh_after
    )
    VALUES
        (
            materialized_species_id,
            'taxonomy',
            'gbif',
            'community_consensus_materialization',
            0.9000,
            JSONB_BUILD_OBJECT(
                'taxon_node_id', target_taxon.id,
                'taxonomy_version_id', target_taxon.taxonomy_version_id
            ),
            now_value,
            NULL
        ),
        (
            materialized_species_id,
            'common_names',
            'gbif',
            'community_consensus_materialization',
            CASE WHEN target_taxon.common_name IS NULL THEN 0.5000 ELSE 0.7500 END,
            JSONB_BUILD_OBJECT(
                'taxon_node_id', target_taxon.id,
                'taxonomy_version_id', target_taxon.taxonomy_version_id
            ),
            now_value,
            NULL
        )
    ON CONFLICT (species_id, content_key) DO UPDATE
    SET source = EXCLUDED.source,
        source_detail = EXCLUDED.source_detail,
        confidence = EXCLUDED.confidence,
        metadata = public.species_content_provenance.metadata || EXCLUDED.metadata,
        last_refreshed_at = EXCLUDED.last_refreshed_at,
        refresh_after = EXCLUDED.refresh_after;

    IF target_taxon.gbif_taxon_key IS NOT NULL THEN
        INSERT INTO public.species_content_provenance (
            species_id,
            content_key,
            source,
            source_detail,
            confidence,
            metadata,
            last_refreshed_at,
            refresh_after
        )
        VALUES (
            materialized_species_id,
            'gbif_taxon_key',
            'gbif',
            'community_consensus_materialization',
            0.9500,
            JSONB_BUILD_OBJECT(
                'taxon_node_id', target_taxon.id,
                'taxonomy_version_id', target_taxon.taxonomy_version_id,
                'gbif_taxon_key', target_taxon.gbif_taxon_key
            ),
            now_value,
            NULL
        )
        ON CONFLICT (species_id, content_key) DO UPDATE
        SET source = EXCLUDED.source,
            source_detail = EXCLUDED.source_detail,
            confidence = EXCLUDED.confidence,
            metadata = public.species_content_provenance.metadata || EXCLUDED.metadata,
            last_refreshed_at = EXCLUDED.last_refreshed_at,
            refresh_after = EXCLUDED.refresh_after;
    END IF;

    INSERT INTO public.species_content_provenance (
        species_id,
        content_key,
        source,
        source_detail,
        confidence,
        metadata,
        last_refreshed_at,
        refresh_after
    )
    SELECT
        materialized_species_id,
        queue_key.content_key,
        'unknown',
        'community_consensus_materialization',
        NULL,
        JSONB_BUILD_OBJECT(
            'taxon_node_id', target_taxon.id,
            'taxonomy_version_id', target_taxon.taxonomy_version_id,
            'reason', 'hydrate materialized community consensus species'
        ),
        now_value,
        now_value
    FROM (
        VALUES
            ('alternative_common_names'::TEXT),
            ('wikipedia_url'::TEXT),
            ('wikipedia_overview'::TEXT),
            ('habitat_description'::TEXT),
            ('reference_images'::TEXT),
            ('lookalikes'::TEXT),
            ('group_tags'::TEXT)
    ) AS queue_key(content_key)
    ON CONFLICT (species_id, content_key) DO UPDATE
    SET source_detail = EXCLUDED.source_detail,
        metadata = public.species_content_provenance.metadata || EXCLUDED.metadata,
        refresh_after = LEAST(
            COALESCE(public.species_content_provenance.refresh_after, EXCLUDED.refresh_after),
            EXCLUDED.refresh_after
        );

    PERFORM public.enqueue_species_enrichment_jobs(
        materialized_species_id,
        'community_consensus_materialization',
        50
    );
    PERFORM public.refresh_taxonomy_coverage_targets();

    RETURN materialized_species_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_resolved_community_request_to_explore(
    target_post_id UUID,
    self_id UUID
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_row public.explore_community_requests;
    materialized_species_id UUID;
BEGIN
    SELECT *
    INTO request_row
    FROM public.explore_community_requests
    WHERE post_id = target_post_id
      AND requested_by = self_id
      AND status = 'resolved'
      AND withdrawn_at IS NULL
    ORDER BY requested_at DESC
    LIMIT 1
    FOR UPDATE;

    IF request_row.id IS NULL THEN
        RETURN NULL;
    END IF;

    IF request_row.resolved_taxon_node_id IS NULL THEN
        RAISE EXCEPTION 'Resolved community request has no resolved taxon.' USING ERRCODE = 'P0001';
    END IF;

    materialized_species_id := public.community_materialize_resolved_species(
        request_row.resolved_taxon_node_id
    );

    UPDATE public.scans
    SET confirmed_species_id = materialized_species_id
    WHERE id = request_row.scan_id
      AND user_id = self_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Community request scan not found for owner.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.explore_community_requests
    SET explore_published_at = COALESCE(explore_published_at, NOW()),
        updated_at = NOW()
    WHERE id = request_row.id;

    RETURN materialized_species_id;
END;
$$;

REVOKE ALL ON FUNCTION public.community_materialize_resolved_species(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.community_materialize_resolved_species(UUID) TO service_role;

REVOKE ALL ON FUNCTION public.publish_resolved_community_request_to_explore(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_resolved_community_request_to_explore(UUID, UUID) TO service_role;
