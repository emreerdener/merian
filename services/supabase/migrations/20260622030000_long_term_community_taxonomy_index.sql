CREATE TABLE IF NOT EXISTS public.taxonomy_import_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source TEXT NOT NULL DEFAULT 'gbif',
    scope TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'running',
    requested_query TEXT,
    target_taxonomy_version_id UUID REFERENCES public.taxonomy_versions(id) ON DELETE SET NULL,
    imported_count INTEGER NOT NULL DEFAULT 0,
    updated_count INTEGER NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT taxonomy_import_runs_source_check
        CHECK (source IN ('gbif', 'merian_dictionary', 'manual')),
    CONSTRAINT taxonomy_import_runs_status_check
        CHECK (status IN ('running', 'completed', 'failed')),
    CONSTRAINT taxonomy_import_runs_counts_check
        CHECK (imported_count >= 0 AND updated_count >= 0 AND error_count >= 0),
    CONSTRAINT taxonomy_import_runs_metadata_object_check
        CHECK (jsonb_typeof(metadata) = 'object')
);

ALTER TABLE public.taxonomy_import_runs ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_taxonomy_import_runs_source_status_started
    ON public.taxonomy_import_runs(source, status, started_at DESC);

ALTER TABLE public.taxon_nodes
    ADD COLUMN IF NOT EXISTS gbif_taxon_key INTEGER,
    ADD COLUMN IF NOT EXISTS accepted_gbif_taxon_key INTEGER,
    ADD COLUMN IF NOT EXISTS taxonomic_status TEXT,
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'merian_dictionary',
    ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS import_run_id UUID REFERENCES public.taxonomy_import_runs(id) ON DELETE SET NULL;

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

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.taxon_nodes'::REGCLASS
          AND conname = 'taxon_nodes_accepted_gbif_taxon_key_positive_check'
    ) THEN
        ALTER TABLE public.taxon_nodes
            ADD CONSTRAINT taxon_nodes_accepted_gbif_taxon_key_positive_check
            CHECK (accepted_gbif_taxon_key IS NULL OR accepted_gbif_taxon_key > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.taxon_nodes'::REGCLASS
          AND conname = 'taxon_nodes_source_check'
    ) THEN
        ALTER TABLE public.taxon_nodes
            ADD CONSTRAINT taxon_nodes_source_check
            CHECK (source IN ('merian_dictionary', 'gbif', 'mixed', 'manual'));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxon_nodes_version_gbif_key_unique
    ON public.taxon_nodes(taxonomy_version_id, gbif_taxon_key)
    WHERE gbif_taxon_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_taxon_nodes_source_rank
    ON public.taxon_nodes(source, rank);
CREATE INDEX IF NOT EXISTS idx_taxon_nodes_import_run_id
    ON public.taxon_nodes(import_run_id);

CREATE TABLE IF NOT EXISTS public.species_enrichment_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    species_id UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    content_group TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    priority INTEGER NOT NULL DEFAULT 100,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    source_trigger TEXT NOT NULL DEFAULT 'unknown',
    last_error TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    next_run_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT species_enrichment_jobs_content_group_check
        CHECK (content_group IN ('gbif_wikipedia_reference', 'habitat', 'lookalikes', 'group_tags')),
    CONSTRAINT species_enrichment_jobs_status_check
        CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
    CONSTRAINT species_enrichment_jobs_attempts_check
        CHECK (attempts >= 0 AND max_attempts > 0),
    CONSTRAINT species_enrichment_jobs_metadata_object_check
        CHECK (jsonb_typeof(metadata) = 'object')
);

ALTER TABLE public.species_enrichment_jobs ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX IF NOT EXISTS idx_species_enrichment_jobs_species_group
    ON public.species_enrichment_jobs(species_id, content_group);
CREATE INDEX IF NOT EXISTS idx_species_enrichment_jobs_queue
    ON public.species_enrichment_jobs(status, next_run_at, priority, created_at)
    WHERE status IN ('queued', 'failed');

CREATE TABLE IF NOT EXISTS public.taxonomy_coverage_targets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    taxonomy_version_id UUID REFERENCES public.taxonomy_versions(id) ON DELETE SET NULL,
    root_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    root_rank TEXT,
    root_scientific_name TEXT,
    indexed_species_count INTEGER NOT NULL DEFAULT 0,
    dictionary_species_count INTEGER NOT NULL DEFAULT 0,
    coverage_ratio NUMERIC(8,6) NOT NULL DEFAULT 0,
    last_computed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT taxonomy_coverage_targets_counts_check
        CHECK (indexed_species_count >= 0 AND dictionary_species_count >= 0),
    CONSTRAINT taxonomy_coverage_targets_ratio_check
        CHECK (coverage_ratio >= 0 AND coverage_ratio <= 1)
);

ALTER TABLE public.taxonomy_coverage_targets ENABLE ROW LEVEL SECURITY;

INSERT INTO public.taxonomy_coverage_targets (
    slug,
    display_name,
    root_rank,
    root_scientific_name
)
VALUES (
    'birds',
    'Birds',
    'class',
    'Aves'
)
ON CONFLICT (slug) DO NOTHING;

CREATE OR REPLACE FUNCTION public.enqueue_species_enrichment_jobs(
    target_species_id UUID,
    source_trigger TEXT DEFAULT 'unknown',
    priority_value INTEGER DEFAULT 100,
    content_groups TEXT[] DEFAULT ARRAY[
        'gbif_wikipedia_reference',
        'habitat',
        'lookalikes',
        'group_tags'
    ]::TEXT[]
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    inserted_count INTEGER := 0;
    content_group_value TEXT;
BEGIN
    IF target_species_id IS NULL THEN
        RETURN 0;
    END IF;

    FOREACH content_group_value IN ARRAY COALESCE(content_groups, ARRAY[]::TEXT[])
    LOOP
        IF content_group_value NOT IN ('gbif_wikipedia_reference', 'habitat', 'lookalikes', 'group_tags') THEN
            CONTINUE;
        END IF;

        INSERT INTO public.species_enrichment_jobs (
            species_id,
            content_group,
            status,
            priority,
            source_trigger,
            next_run_at,
            updated_at
        )
        VALUES (
            target_species_id,
            content_group_value,
            'queued',
            COALESCE(priority_value, 100),
            COALESCE(NULLIF(BTRIM(source_trigger), ''), 'unknown'),
            NOW(),
            NOW()
        )
        ON CONFLICT (species_id, content_group) DO UPDATE
        SET status = CASE
                WHEN public.species_enrichment_jobs.status IN ('succeeded', 'cancelled')
                    THEN 'queued'
                ELSE public.species_enrichment_jobs.status
            END,
            priority = LEAST(public.species_enrichment_jobs.priority, EXCLUDED.priority),
            source_trigger = EXCLUDED.source_trigger,
            next_run_at = LEAST(
                COALESCE(public.species_enrichment_jobs.next_run_at, EXCLUDED.next_run_at),
                EXCLUDED.next_run_at
            ),
            updated_at = NOW()
        WHERE public.species_enrichment_jobs.status <> 'running';

        IF FOUND THEN
            inserted_count := inserted_count + 1;
        END IF;
    END LOOP;

    RETURN inserted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_species_enrichment_jobs(
    max_rows INTEGER DEFAULT 25,
    as_of TIMESTAMPTZ DEFAULT NOW(),
    target_content_group TEXT DEFAULT NULL
)
RETURNS TABLE(
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
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
    WITH candidates AS (
        SELECT sej.id
        FROM public.species_enrichment_jobs sej
        WHERE sej.status IN ('queued', 'failed')
          AND sej.next_run_at <= COALESCE(as_of, NOW())
          AND sej.attempts < sej.max_attempts
          AND (
            target_content_group IS NULL
            OR sej.content_group = target_content_group
          )
        ORDER BY
            sej.priority ASC,
            sej.next_run_at ASC,
            sej.created_at ASC
        LIMIT LEAST(GREATEST(COALESCE(max_rows, 25), 1), 100)
        FOR UPDATE SKIP LOCKED
    ),
    claimed AS (
        UPDATE public.species_enrichment_jobs sej
        SET status = 'running',
            attempts = sej.attempts + 1,
            locked_at = NOW(),
            updated_at = NOW()
        FROM candidates
        WHERE sej.id = candidates.id
        RETURNING sej.*
    )
    SELECT
        claimed.id AS job_id,
        claimed.species_id,
        sd.scientific_name,
        claimed.content_group,
        claimed.priority,
        claimed.attempts,
        claimed.max_attempts,
        claimed.source_trigger,
        claimed.metadata
    FROM claimed
    JOIN public.species_dictionary sd
        ON sd.id = claimed.species_id;
$$;

CREATE OR REPLACE FUNCTION public.complete_species_enrichment_job(
    target_job_id UUID,
    succeeded BOOLEAN,
    error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    job_row public.species_enrichment_jobs;
BEGIN
    SELECT *
    INTO job_row
    FROM public.species_enrichment_jobs
    WHERE id = target_job_id
    FOR UPDATE;

    IF job_row.id IS NULL THEN
        RETURN;
    END IF;

    IF succeeded THEN
        UPDATE public.species_enrichment_jobs
        SET status = 'succeeded',
            last_error = NULL,
            locked_at = NULL,
            completed_at = NOW(),
            updated_at = NOW()
        WHERE id = target_job_id;
        RETURN;
    END IF;

    UPDATE public.species_enrichment_jobs
    SET status = 'failed',
        last_error = NULLIF(BTRIM(COALESCE(error_message, '')), ''),
        locked_at = NULL,
        next_run_at = CASE
            WHEN attempts >= max_attempts THEN NOW() + INTERVAL '30 days'
            ELSE NOW() + (POWER(2, GREATEST(attempts - 1, 0))::TEXT || ' minutes')::INTERVAL
        END,
        updated_at = NOW()
    WHERE id = target_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_gbif_community_taxa(
    taxa JSONB,
    query_text TEXT DEFAULT NULL,
    max_rows INTEGER DEFAULT 20
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
        JSONB_BUILD_OBJECT('requested_count', JSONB_ARRAY_LENGTH(taxa))
    )
    RETURNING id INTO import_run_id;

    FOR taxon IN
        SELECT value
        FROM JSONB_ARRAY_ELEMENTS(taxa)
        LIMIT LEAST(GREATEST(COALESCE(max_rows, 20), 1), 50)
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

    PERFORM public.refresh_taxonomy_coverage_targets();

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

CREATE OR REPLACE FUNCTION public.search_community_taxa(
    query_text TEXT,
    max_limit INTEGER DEFAULT 20,
    target_taxonomy_version_id UUID DEFAULT NULL
)
RETURNS TABLE(
    taxon_id UUID,
    taxonomy_version_id UUID,
    common_name TEXT,
    scientific_name TEXT,
    rank TEXT,
    path TEXT,
    species_id UUID,
    gbif_taxon_key INTEGER,
    source TEXT,
    is_in_dictionary BOOLEAN,
    accepted_gbif_taxon_key INTEGER,
    taxonomic_status TEXT
)
LANGUAGE SQL
AS $$
    WITH normalized AS (
        SELECT
            LOWER(BTRIM(query_text)) AS q,
            COALESCE(target_taxonomy_version_id, public.active_taxonomy_version_id()) AS version_id
    ),
    matches AS (
        SELECT
            tn.id AS taxon_id,
            tn.taxonomy_version_id,
            tn.common_name,
            tn.scientific_name,
            tn.rank,
            tn.path::TEXT AS path,
            tn.species_id,
            tn.gbif_taxon_key,
            tn.source,
            (tn.species_id IS NOT NULL) AS is_in_dictionary,
            tn.accepted_gbif_taxon_key,
            tn.taxonomic_status,
            MIN(CASE
                WHEN tname.normalized_name = normalized.q THEN 0
                WHEN tname.normalized_name LIKE normalized.q || '%' THEN 1
                ELSE 2
            END) AS match_rank
        FROM normalized
        JOIN public.taxon_nodes tn
            ON tn.taxonomy_version_id = normalized.version_id
        JOIN public.taxon_names tname
            ON tname.taxon_node_id = tn.id
           AND tname.taxonomy_version_id = tn.taxonomy_version_id
        WHERE normalized.q <> ''
          AND tname.normalized_name ILIKE '%' || normalized.q || '%'
        GROUP BY
            tn.id,
            tn.taxonomy_version_id,
            tn.common_name,
            tn.scientific_name,
            tn.rank,
            tn.path,
            tn.species_id,
            tn.gbif_taxon_key,
            tn.source,
            tn.accepted_gbif_taxon_key,
            tn.taxonomic_status
    )
    SELECT
        taxon_id,
        taxonomy_version_id,
        common_name,
        scientific_name,
        rank,
        path,
        species_id,
        gbif_taxon_key,
        source,
        is_in_dictionary,
        accepted_gbif_taxon_key,
        taxonomic_status
    FROM matches
    ORDER BY
        match_rank,
        is_in_dictionary DESC,
        CASE source WHEN 'merian_dictionary' THEN 0 WHEN 'mixed' THEN 1 WHEN 'gbif' THEN 2 ELSE 3 END,
        public.community_taxon_rank_sort(rank) DESC,
        COALESCE(common_name, scientific_name),
        scientific_name
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 20), 1), 50);
$$;

CREATE OR REPLACE FUNCTION public.sync_taxon_nodes_from_species_dictionary()
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_id UUID;
    node_count INTEGER;
    species_row RECORD;
    lineage RECORD;
    parent_node_id UUID;
    node_id UUID;
    node_path LTREE;
BEGIN
    active_id := public.active_taxonomy_version_id();

    SELECT COUNT(*)::INTEGER
    INTO node_count
    FROM public.taxon_nodes
    WHERE taxonomy_version_id = active_id;

    IF node_count = 0 THEN
        PERFORM public.refresh_taxonomy_nodes_from_species_dictionary('bootstrap-sync', TRUE);
        active_id := public.active_taxonomy_version_id();
    END IF;

    FOR species_row IN
        SELECT
            id,
            scientific_name,
            common_names,
            alternative_common_names,
            kingdom,
            phylum,
            class,
            "order",
            family,
            genus,
            gbif_taxon_key
        FROM public.species_dictionary
        WHERE NULLIF(BTRIM(scientific_name), '') IS NOT NULL
          AND NULLIF(BTRIM(kingdom), '') IS NOT NULL
    LOOP
        parent_node_id := NULL;

        FOR lineage IN
            SELECT * FROM (
                VALUES
                    ('kingdom'::TEXT, species_row.kingdom, public.community_taxon_path(species_row.kingdom, NULL, NULL, NULL, NULL, NULL, NULL), NULL::UUID, NULL::INTEGER),
                    ('phylum'::TEXT, species_row.phylum, public.community_taxon_path(species_row.kingdom, species_row.phylum, NULL, NULL, NULL, NULL, NULL), NULL::UUID, NULL::INTEGER),
                    ('class'::TEXT, species_row.class, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, NULL, NULL, NULL, NULL), NULL::UUID, NULL::INTEGER),
                    ('order'::TEXT, species_row."order", public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", NULL, NULL, NULL), NULL::UUID, NULL::INTEGER),
                    ('family'::TEXT, species_row.family, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", species_row.family, NULL, NULL), NULL::UUID, NULL::INTEGER),
                    ('genus'::TEXT, species_row.genus, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", species_row.family, species_row.genus, NULL), NULL::UUID, NULL::INTEGER),
                    ('species'::TEXT, species_row.scientific_name, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", species_row.family, species_row.genus, species_row.scientific_name), species_row.id, species_row.gbif_taxon_key)
            ) AS v(rank_value, taxon_name, taxon_path, species_id, gbif_taxon_key)
            WHERE NULLIF(BTRIM(v.taxon_name), '') IS NOT NULL
              AND v.taxon_path IS NOT NULL
        LOOP
            node_path := lineage.taxon_path;

            IF lineage.species_id IS NOT NULL THEN
                UPDATE public.taxon_nodes
                SET species_id = NULL,
                    updated_at = NOW()
                WHERE taxonomy_version_id = active_id
                  AND species_id = lineage.species_id
                  AND path <> node_path;
            END IF;

            INSERT INTO public.taxon_nodes (
                taxonomy_version_id,
                path,
                parent_id,
                rank,
                scientific_name,
                common_name,
                species_id,
                gbif_taxon_key,
                source,
                last_synced_at,
                updated_at
            )
            VALUES (
                active_id,
                node_path,
                parent_node_id,
                lineage.rank_value,
                lineage.taxon_name,
                CASE
                    WHEN lineage.rank_value = 'species' THEN public.public_species_common_name(species_row.common_names)
                    ELSE NULL
                END,
                lineage.species_id,
                lineage.gbif_taxon_key,
                CASE WHEN lineage.gbif_taxon_key IS NOT NULL THEN 'mixed' ELSE 'merian_dictionary' END,
                NOW(),
                NOW()
            )
            ON CONFLICT (taxonomy_version_id, path) DO UPDATE
            SET parent_id = COALESCE(EXCLUDED.parent_id, public.taxon_nodes.parent_id),
                rank = EXCLUDED.rank,
                scientific_name = EXCLUDED.scientific_name,
                common_name = COALESCE(EXCLUDED.common_name, public.taxon_nodes.common_name),
                species_id = COALESCE(EXCLUDED.species_id, public.taxon_nodes.species_id),
                gbif_taxon_key = COALESCE(public.taxon_nodes.gbif_taxon_key, EXCLUDED.gbif_taxon_key),
                source = CASE
                    WHEN public.taxon_nodes.source = 'gbif' OR EXCLUDED.gbif_taxon_key IS NOT NULL THEN 'mixed'
                    ELSE 'merian_dictionary'
                END,
                last_synced_at = NOW(),
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

            IF lineage.rank_value = 'species'
               AND public.public_species_common_name(species_row.common_names) IS NOT NULL THEN
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
                    public.public_species_common_name(species_row.common_names),
                    LOWER(BTRIM(public.public_species_common_name(species_row.common_names))),
                    TRUE
                )
                ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;
            END IF;

            parent_node_id := node_id;
        END LOOP;
    END LOOP;

    SELECT COUNT(*)::INTEGER
    INTO node_count
    FROM public.taxon_nodes
    WHERE taxonomy_version_id = active_id;

    RETURN node_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_taxonomy_coverage_targets()
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_row public.taxonomy_coverage_targets;
    active_id UUID := public.active_taxonomy_version_id();
    indexed_count INTEGER;
    dictionary_count INTEGER;
BEGIN
    FOR target_row IN
        SELECT *
        FROM public.taxonomy_coverage_targets
    LOOP
        SELECT id
        INTO target_row.root_taxon_node_id
        FROM public.taxon_nodes
        WHERE taxonomy_version_id = active_id
          AND rank = target_row.root_rank
          AND scientific_name = target_row.root_scientific_name
        ORDER BY updated_at DESC NULLS LAST
        LIMIT 1;

        IF target_row.root_taxon_node_id IS NULL THEN
            indexed_count := 0;
            dictionary_count := 0;
        ELSE
            SELECT
                COUNT(*) FILTER (WHERE rank = 'species')::INTEGER,
                COUNT(*) FILTER (WHERE rank = 'species' AND species_id IS NOT NULL)::INTEGER
            INTO indexed_count, dictionary_count
            FROM public.taxon_nodes child
            WHERE child.taxonomy_version_id = active_id
              AND child.path <@ (
                  SELECT root.path
                  FROM public.taxon_nodes root
                  WHERE root.id = target_row.root_taxon_node_id
              );
        END IF;

        UPDATE public.taxonomy_coverage_targets
        SET taxonomy_version_id = active_id,
            root_taxon_node_id = target_row.root_taxon_node_id,
            indexed_species_count = indexed_count,
            dictionary_species_count = dictionary_count,
            coverage_ratio = CASE
                WHEN indexed_count > 0 THEN dictionary_count::NUMERIC / indexed_count::NUMERIC
                ELSE 0
            END,
            last_computed_at = NOW(),
            updated_at = NOW()
        WHERE id = target_row.id;
    END LOOP;

    RETURN (SELECT COUNT(*)::INTEGER FROM public.taxonomy_coverage_targets);
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_gbif_community_taxa(JSONB, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_gbif_community_taxa(JSONB, TEXT, INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_species_enrichment_jobs(UUID, TEXT, INTEGER, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_species_enrichment_jobs(UUID, TEXT, INTEGER, TEXT[]) TO service_role;

REVOKE ALL ON FUNCTION public.claim_species_enrichment_jobs(INTEGER, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_species_enrichment_jobs(INTEGER, TIMESTAMPTZ, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.complete_species_enrichment_job(UUID, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_species_enrichment_job(UUID, BOOLEAN, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.refresh_taxonomy_coverage_targets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_taxonomy_coverage_targets() TO service_role;
