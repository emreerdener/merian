ALTER TABLE public.taxonomy_coverage_targets
    ADD COLUMN IF NOT EXISTS last_imported_offset INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS next_import_offset INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_successful_import_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_import_error TEXT,
    ADD COLUMN IF NOT EXISTS gbif_total_count INTEGER,
    ADD COLUMN IF NOT EXISTS import_cursor_metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.taxonomy_coverage_targets'::REGCLASS
          AND conname = 'taxonomy_coverage_targets_import_cursor_check'
    ) THEN
        ALTER TABLE public.taxonomy_coverage_targets
            ADD CONSTRAINT taxonomy_coverage_targets_import_cursor_check
            CHECK (
                last_imported_offset >= 0
                AND next_import_offset >= 0
                AND (gbif_total_count IS NULL OR gbif_total_count >= 0)
                AND jsonb_typeof(import_cursor_metadata) = 'object'
            );
    END IF;
END $$;

WITH latest_birds_import AS (
    SELECT
        NULLIF(metadata->>'offset', '')::INTEGER AS offset_value,
        NULLIF(metadata->>'limit', '')::INTEGER AS limit_value,
        CASE
            WHEN metadata->>'gbif_count' ~ '^[0-9]+$'
                THEN NULLIF(metadata->>'gbif_count', '')::INTEGER
            ELSE NULL
        END AS gbif_count_value,
        metadata,
        COALESCE(finished_at, updated_at, created_at) AS completed_at
    FROM public.taxonomy_import_runs
    WHERE source = 'gbif'
      AND scope = 'gbif_bounded_birds'
      AND status = 'completed'
      AND error_count = 0
      AND metadata->>'offset' ~ '^[0-9]+$'
      AND metadata->>'limit' ~ '^[0-9]+$'
    ORDER BY COALESCE(finished_at, updated_at, created_at) DESC
    LIMIT 1
)
UPDATE public.taxonomy_coverage_targets target
SET last_imported_offset = latest_birds_import.offset_value,
    next_import_offset = latest_birds_import.offset_value + latest_birds_import.limit_value,
    last_successful_import_at = latest_birds_import.completed_at,
    gbif_total_count = latest_birds_import.gbif_count_value,
    import_cursor_metadata = latest_birds_import.metadata || JSONB_BUILD_OBJECT(
        'target', 'birds',
        'last_offsets', JSONB_BUILD_ARRAY(latest_birds_import.offset_value),
        'next_import_offset', latest_birds_import.offset_value + latest_birds_import.limit_value,
        'updated_by', '20260623090000_optimize_community_taxonomy_imports'
    ),
    updated_at = NOW()
FROM latest_birds_import
WHERE target.slug = 'birds';

DROP FUNCTION IF EXISTS public.upsert_gbif_community_taxa(JSONB, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.upsert_gbif_community_taxa(
    taxa JSONB,
    query_text TEXT DEFAULT NULL,
    max_rows INTEGER DEFAULT 20,
    refresh_coverage BOOLEAN DEFAULT TRUE
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_id UUID;
    import_run_id UUID;
    imported_rows INTEGER := 0;
    taxon JSONB;
    rank_value TEXT;
    lineage RECORD;
    lineage_key INTEGER;
    parent_node_id UUID;
    node_id UUID;
    existing_species_id UUID;
    node_path LTREE;
BEGIN
    IF JSONB_TYPEOF(COALESCE(taxa, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'taxa must be a JSON array.' USING ERRCODE = 'P0001';
    END IF;

    active_id := public.active_taxonomy_version_id();

    INSERT INTO public.taxonomy_import_runs (
        source,
        scope,
        status,
        requested_query,
        target_taxonomy_version_id,
        metadata
    )
    VALUES (
        'gbif',
        'community_search_on_demand',
        'running',
        NULLIF(BTRIM(COALESCE(query_text, '')), ''),
        active_id,
        JSONB_BUILD_OBJECT(
            'requested_count',
            JSONB_ARRAY_LENGTH(taxa),
            'refresh_coverage',
            COALESCE(refresh_coverage, TRUE)
        )
    )
    RETURNING id INTO import_run_id;

    FOR taxon IN
        SELECT value
        FROM JSONB_ARRAY_ELEMENTS(taxa)
        LIMIT LEAST(GREATEST(COALESCE(max_rows, 20), 1), 200)
    LOOP
        rank_value := LOWER(BTRIM(COALESCE(taxon->>'rank', 'species')));

        IF rank_value NOT IN ('kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species') THEN
            CONTINUE;
        END IF;

        parent_node_id := NULL;

        FOR lineage IN
            SELECT *
            FROM (
                VALUES
                    ('kingdom'::TEXT, taxon->>'kingdom', public.community_taxon_path(taxon->>'kingdom', NULL, NULL, NULL, NULL, NULL, NULL), NULLIF(taxon->>'kingdom_gbif_taxon_key', '')::INTEGER),
                    ('phylum'::TEXT, taxon->>'phylum', public.community_taxon_path(taxon->>'kingdom', taxon->>'phylum', NULL, NULL, NULL, NULL, NULL), NULLIF(taxon->>'phylum_gbif_taxon_key', '')::INTEGER),
                    ('class'::TEXT, taxon->>'class', public.community_taxon_path(taxon->>'kingdom', taxon->>'phylum', taxon->>'class', NULL, NULL, NULL, NULL), NULLIF(taxon->>'class_gbif_taxon_key', '')::INTEGER),
                    ('order'::TEXT, taxon->>'order', public.community_taxon_path(taxon->>'kingdom', taxon->>'phylum', taxon->>'class', taxon->>'order', NULL, NULL, NULL), NULLIF(taxon->>'order_gbif_taxon_key', '')::INTEGER),
                    ('family'::TEXT, taxon->>'family', public.community_taxon_path(taxon->>'kingdom', taxon->>'phylum', taxon->>'class', taxon->>'order', taxon->>'family', NULL, NULL), NULLIF(taxon->>'family_gbif_taxon_key', '')::INTEGER),
                    ('genus'::TEXT, COALESCE(taxon->>'genus', CASE WHEN rank_value = 'genus' THEN taxon->>'scientific_name' ELSE NULL END), public.community_taxon_path(taxon->>'kingdom', taxon->>'phylum', taxon->>'class', taxon->>'order', taxon->>'family', COALESCE(taxon->>'genus', CASE WHEN rank_value = 'genus' THEN taxon->>'scientific_name' ELSE NULL END), NULL), NULLIF(taxon->>'genus_gbif_taxon_key', '')::INTEGER),
                    ('species'::TEXT, COALESCE(taxon->>'species', CASE WHEN rank_value = 'species' THEN taxon->>'scientific_name' ELSE NULL END), public.community_taxon_path(taxon->>'kingdom', taxon->>'phylum', taxon->>'class', taxon->>'order', taxon->>'family', taxon->>'genus', COALESCE(taxon->>'species', CASE WHEN rank_value = 'species' THEN taxon->>'scientific_name' ELSE NULL END)), NULLIF(taxon->>'gbif_taxon_key', '')::INTEGER)
            ) AS v(lineage_rank, taxon_name, taxon_path, taxon_key)
            WHERE NULLIF(BTRIM(v.taxon_name), '') IS NOT NULL
              AND v.taxon_path IS NOT NULL
              AND public.community_taxon_rank_sort(v.lineage_rank) <= public.community_taxon_rank_sort(rank_value)
            ORDER BY public.community_taxon_rank_sort(v.lineage_rank)
        LOOP
            node_path := lineage.taxon_path;
            lineage_key := lineage.taxon_key;

            SELECT tn.species_id
            INTO existing_species_id
            FROM public.taxon_nodes tn
            WHERE tn.taxonomy_version_id = active_id
              AND tn.path = node_path
            LIMIT 1;

            INSERT INTO public.taxon_nodes (
                taxonomy_version_id,
                path,
                parent_id,
                rank,
                scientific_name,
                common_name,
                gbif_taxon_key,
                accepted_gbif_taxon_key,
                taxonomic_status,
                source,
                last_synced_at,
                import_run_id,
                updated_at
            )
            VALUES (
                active_id,
                node_path,
                parent_node_id,
                lineage.lineage_rank,
                lineage.taxon_name,
                CASE
                    WHEN lineage.lineage_rank = rank_value THEN NULLIF(BTRIM(taxon->>'common_name'), '')
                    ELSE NULL
                END,
                lineage_key,
                NULLIF(taxon->>'accepted_gbif_taxon_key', '')::INTEGER,
                NULLIF(BTRIM(LOWER(COALESCE(taxon->>'taxonomic_status', ''))), ''),
                CASE WHEN existing_species_id IS NOT NULL THEN 'mixed' ELSE 'gbif' END,
                NOW(),
                import_run_id,
                NOW()
            )
            ON CONFLICT (taxonomy_version_id, path) DO UPDATE
            SET parent_id = COALESCE(EXCLUDED.parent_id, public.taxon_nodes.parent_id),
                common_name = COALESCE(EXCLUDED.common_name, public.taxon_nodes.common_name),
                gbif_taxon_key = COALESCE(public.taxon_nodes.gbif_taxon_key, EXCLUDED.gbif_taxon_key),
                accepted_gbif_taxon_key = COALESCE(public.taxon_nodes.accepted_gbif_taxon_key, EXCLUDED.accepted_gbif_taxon_key),
                taxonomic_status = COALESCE(EXCLUDED.taxonomic_status, public.taxon_nodes.taxonomic_status),
                source = CASE
                    WHEN public.taxon_nodes.species_id IS NOT NULL OR public.taxon_nodes.source = 'merian_dictionary'
                        THEN 'mixed'
                    ELSE EXCLUDED.source
                END,
                last_synced_at = NOW(),
                import_run_id = EXCLUDED.import_run_id,
                updated_at = NOW()
            RETURNING id INTO node_id;

            INSERT INTO public.taxon_names (
                taxonomy_version_id,
                taxon_node_id,
                kind,
                name,
                normalized_name,
                is_primary
            )
            VALUES (
                active_id,
                node_id,
                'scientific',
                lineage.taxon_name,
                LOWER(BTRIM(lineage.taxon_name)),
                TRUE
            )
            ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

            IF lineage.lineage_rank = rank_value
               AND NULLIF(BTRIM(taxon->>'common_name'), '') IS NOT NULL THEN
                INSERT INTO public.taxon_names (
                    taxonomy_version_id,
                    taxon_node_id,
                    kind,
                    name,
                    normalized_name,
                    is_primary
                )
                VALUES (
                    active_id,
                    node_id,
                    'common',
                    BTRIM(taxon->>'common_name'),
                    LOWER(BTRIM(taxon->>'common_name')),
                    TRUE
                )
                ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;
            END IF;

            parent_node_id := node_id;
        END LOOP;

        imported_rows := imported_rows + 1;
    END LOOP;

    UPDATE public.taxonomy_import_runs
    SET status = 'completed',
        imported_count = imported_rows,
        finished_at = NOW(),
        updated_at = NOW()
    WHERE id = import_run_id;

    IF COALESCE(refresh_coverage, TRUE) THEN
        PERFORM public.refresh_taxonomy_coverage_targets();
    END IF;

    RETURN imported_rows;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE public.taxonomy_import_runs
        SET status = 'failed',
            error_count = error_count + 1,
            error_message = SQLERRM,
            finished_at = NOW(),
            updated_at = NOW()
        WHERE id = import_run_id;
        RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_gbif_community_taxa(JSONB, TEXT, INTEGER, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_gbif_community_taxa(JSONB, TEXT, INTEGER, BOOLEAN) TO service_role;
