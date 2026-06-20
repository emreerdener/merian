CREATE EXTENSION IF NOT EXISTS ltree;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

DO $$
BEGIN
    CREATE TYPE public.taxonomy_version_status AS ENUM ('draft', 'active', 'retired');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE public.taxonomy_version_source AS ENUM ('merian_dictionary');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE public.explore_observation_projection_state AS ENUM (
        'normal',
        'community_needs_id',
        'community_resolved',
        'withdrawn'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE public.community_consensus_job_status AS ENUM (
        'pending',
        'processing',
        'completed',
        'failed'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.taxonomy_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status public.taxonomy_version_status NOT NULL DEFAULT 'draft',
    source public.taxonomy_version_source NOT NULL DEFAULT 'merian_dictionary',
    source_revision TEXT NOT NULL DEFAULT 'initial',
    activated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT taxonomy_versions_active_activation CHECK (
        (status = 'active' AND activated_at IS NOT NULL)
        OR (status <> 'active')
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxonomy_versions_one_active_per_source
    ON public.taxonomy_versions(source)
    WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_taxonomy_versions_status_source
    ON public.taxonomy_versions(status, source, activated_at DESC);

INSERT INTO public.taxonomy_versions (status, source, source_revision, activated_at)
SELECT 'active', 'merian_dictionary', 'initial-community-taxonomy', NOW()
WHERE NOT EXISTS (
    SELECT 1
    FROM public.taxonomy_versions
    WHERE source = 'merian_dictionary'
      AND status = 'active'
);

CREATE OR REPLACE FUNCTION public.active_taxonomy_version_id()
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_id UUID;
BEGIN
    SELECT id
    INTO active_id
    FROM public.taxonomy_versions
    WHERE source = 'merian_dictionary'
      AND status = 'active'
    ORDER BY activated_at DESC, created_at DESC
    LIMIT 1;

    IF active_id IS NULL THEN
        INSERT INTO public.taxonomy_versions (status, source, source_revision, activated_at)
        VALUES ('active', 'merian_dictionary', 'bootstrap-community-taxonomy', NOW())
        RETURNING id INTO active_id;
    END IF;

    RETURN active_id;
END;
$$;

ALTER TABLE public.taxon_nodes
    ADD COLUMN IF NOT EXISTS taxonomy_version_id UUID;

UPDATE public.taxon_nodes
SET taxonomy_version_id = public.active_taxonomy_version_id()
WHERE taxonomy_version_id IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.taxon_nodes'::REGCLASS
          AND conname = 'taxon_nodes_taxonomy_version_id_fkey'
    ) THEN
        ALTER TABLE public.taxon_nodes
            ADD CONSTRAINT taxon_nodes_taxonomy_version_id_fkey
            FOREIGN KEY (taxonomy_version_id)
            REFERENCES public.taxonomy_versions(id)
            ON DELETE RESTRICT;
    END IF;
END $$;

ALTER TABLE public.taxon_nodes
    ALTER COLUMN taxonomy_version_id SET NOT NULL;

ALTER TABLE public.taxon_nodes
    DROP CONSTRAINT IF EXISTS taxon_nodes_path_key;
ALTER TABLE public.taxon_nodes
    DROP CONSTRAINT IF EXISTS taxon_nodes_species_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxon_nodes_version_path_unique
    ON public.taxon_nodes(taxonomy_version_id, path);
CREATE UNIQUE INDEX IF NOT EXISTS idx_taxon_nodes_version_species_unique
    ON public.taxon_nodes(taxonomy_version_id, species_id)
    WHERE species_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_taxon_nodes_version_rank_name
    ON public.taxon_nodes(taxonomy_version_id, rank, LOWER(scientific_name));

CREATE TABLE IF NOT EXISTS public.taxon_names (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    taxonomy_version_id UUID NOT NULL REFERENCES public.taxonomy_versions(id) ON DELETE CASCADE,
    taxon_node_id UUID NOT NULL REFERENCES public.taxon_nodes(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('scientific', 'common', 'synonym')),
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    locale TEXT NOT NULL DEFAULT 'en',
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT taxon_names_non_empty CHECK (NULLIF(BTRIM(name), '') IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxon_names_unique
    ON public.taxon_names(taxonomy_version_id, taxon_node_id, kind, normalized_name, locale);
CREATE INDEX IF NOT EXISTS idx_taxon_names_version_normalized_trgm
    ON public.taxon_names USING GIN(normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_taxon_names_taxon_node_id
    ON public.taxon_names(taxon_node_id);

INSERT INTO public.taxon_names (
    taxonomy_version_id,
    taxon_node_id,
    kind,
    name,
    normalized_name,
    is_primary
)
SELECT
    tn.taxonomy_version_id,
    tn.id,
    'scientific',
    tn.scientific_name,
    LOWER(BTRIM(tn.scientific_name)),
    TRUE
FROM public.taxon_nodes tn
WHERE NULLIF(BTRIM(tn.scientific_name), '') IS NOT NULL
ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

INSERT INTO public.taxon_names (
    taxonomy_version_id,
    taxon_node_id,
    kind,
    name,
    normalized_name,
    is_primary
)
SELECT
    tn.taxonomy_version_id,
    tn.id,
    'common',
    tn.common_name,
    LOWER(BTRIM(tn.common_name)),
    TRUE
FROM public.taxon_nodes tn
WHERE NULLIF(BTRIM(tn.common_name), '') IS NOT NULL
ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.taxon_node_replacements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    old_taxon_node_id UUID NOT NULL REFERENCES public.taxon_nodes(id) ON DELETE CASCADE,
    new_taxon_node_id UUID NOT NULL REFERENCES public.taxon_nodes(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT taxon_node_replacements_not_self CHECK (old_taxon_node_id <> new_taxon_node_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_taxon_node_replacements_unique
    ON public.taxon_node_replacements(old_taxon_node_id, new_taxon_node_id);

CREATE OR REPLACE FUNCTION public.refresh_taxonomy_nodes_from_species_dictionary(
    target_source_revision TEXT DEFAULT NULL,
    activate_version BOOLEAN DEFAULT TRUE
)
RETURNS public.taxonomy_versions
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    draft_version public.taxonomy_versions;
    species_row RECORD;
    lineage RECORD;
    parent_node_id UUID;
    node_id UUID;
    node_path LTREE;
BEGIN
    INSERT INTO public.taxonomy_versions (
        status,
        source,
        source_revision,
        activated_at
    )
    VALUES (
        'draft',
        'merian_dictionary',
        COALESCE(NULLIF(BTRIM(target_source_revision), ''), 'species_dictionary-' || TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')),
        NULL
    )
    RETURNING * INTO draft_version;

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
            genus
        FROM public.species_dictionary
        WHERE NULLIF(BTRIM(scientific_name), '') IS NOT NULL
          AND NULLIF(BTRIM(kingdom), '') IS NOT NULL
    LOOP
        parent_node_id := NULL;

        FOR lineage IN
            SELECT * FROM (
                VALUES
                    ('kingdom'::TEXT, species_row.kingdom, public.community_taxon_path(species_row.kingdom, NULL, NULL, NULL, NULL, NULL, NULL), NULL::UUID),
                    ('phylum'::TEXT, species_row.phylum, public.community_taxon_path(species_row.kingdom, species_row.phylum, NULL, NULL, NULL, NULL, NULL), NULL::UUID),
                    ('class'::TEXT, species_row.class, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, NULL, NULL, NULL, NULL), NULL::UUID),
                    ('order'::TEXT, species_row."order", public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", NULL, NULL, NULL), NULL::UUID),
                    ('family'::TEXT, species_row.family, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", species_row.family, NULL, NULL), NULL::UUID),
                    ('genus'::TEXT, species_row.genus, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", species_row.family, species_row.genus, NULL), NULL::UUID),
                    ('species'::TEXT, species_row.scientific_name, public.community_taxon_path(species_row.kingdom, species_row.phylum, species_row.class, species_row."order", species_row.family, species_row.genus, species_row.scientific_name), species_row.id)
            ) AS v(rank_value, taxon_name, taxon_path, species_id)
            WHERE NULLIF(BTRIM(v.taxon_name), '') IS NOT NULL
              AND v.taxon_path IS NOT NULL
        LOOP
            node_path := lineage.taxon_path;

            INSERT INTO public.taxon_nodes (
                taxonomy_version_id,
                path,
                parent_id,
                rank,
                scientific_name,
                common_name,
                species_id,
                updated_at
            )
            VALUES (
                draft_version.id,
                node_path,
                parent_node_id,
                lineage.rank_value,
                lineage.taxon_name,
                CASE
                    WHEN lineage.rank_value = 'species' THEN public.public_species_common_name(species_row.common_names)
                    ELSE NULL
                END,
                lineage.species_id,
                NOW()
            )
            ON CONFLICT (taxonomy_version_id, path) DO UPDATE
            SET parent_id = COALESCE(EXCLUDED.parent_id, public.taxon_nodes.parent_id),
                rank = EXCLUDED.rank,
                scientific_name = EXCLUDED.scientific_name,
                common_name = COALESCE(EXCLUDED.common_name, public.taxon_nodes.common_name),
                species_id = COALESCE(EXCLUDED.species_id, public.taxon_nodes.species_id),
                updated_at = NOW()
            RETURNING id INTO node_id;

            parent_node_id := node_id;
        END LOOP;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1
        FROM public.taxon_nodes
        WHERE taxonomy_version_id = draft_version.id
    ) THEN
        RAISE EXCEPTION 'Cannot activate an empty taxonomy version.' USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.taxon_names
    WHERE taxonomy_version_id = draft_version.id;

    INSERT INTO public.taxon_names (
        taxonomy_version_id,
        taxon_node_id,
        kind,
        name,
        normalized_name,
        is_primary
    )
    SELECT
        tn.taxonomy_version_id,
        tn.id,
        'scientific',
        tn.scientific_name,
        LOWER(BTRIM(tn.scientific_name)),
        TRUE
    FROM public.taxon_nodes tn
    WHERE tn.taxonomy_version_id = draft_version.id
      AND NULLIF(BTRIM(tn.scientific_name), '') IS NOT NULL
    ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

    INSERT INTO public.taxon_names (
        taxonomy_version_id,
        taxon_node_id,
        kind,
        name,
        normalized_name,
        is_primary
    )
    SELECT
        tn.taxonomy_version_id,
        tn.id,
        'common',
        tn.common_name,
        LOWER(BTRIM(tn.common_name)),
        TRUE
    FROM public.taxon_nodes tn
    WHERE tn.taxonomy_version_id = draft_version.id
      AND NULLIF(BTRIM(tn.common_name), '') IS NOT NULL
    ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

    INSERT INTO public.taxon_names (
        taxonomy_version_id,
        taxon_node_id,
        kind,
        name,
        normalized_name,
        is_primary
    )
    SELECT DISTINCT
        tn.taxonomy_version_id,
        tn.id,
        'synonym',
        synonym_name.name,
        LOWER(BTRIM(synonym_name.name)),
        FALSE
    FROM public.taxon_nodes tn
    JOIN public.species_dictionary sd
        ON sd.id = tn.species_id
    CROSS JOIN LATERAL (
        SELECT value AS name
        FROM JSONB_EACH_TEXT(COALESCE(sd.common_names, '{}'::JSONB))
        UNION
        SELECT alt_name.value AS name
        FROM UNNEST(COALESCE(sd.alternative_common_names, ARRAY[]::TEXT[])) AS alt_name(value)
    ) synonym_name
    WHERE tn.taxonomy_version_id = draft_version.id
      AND NULLIF(BTRIM(synonym_name.name), '') IS NOT NULL
    ON CONFLICT (taxonomy_version_id, taxon_node_id, kind, normalized_name, locale) DO NOTHING;

    IF activate_version THEN
        UPDATE public.taxonomy_versions
        SET status = 'retired',
            updated_at = NOW()
        WHERE source = 'merian_dictionary'
          AND status = 'active'
          AND id <> draft_version.id;

        UPDATE public.taxonomy_versions
        SET status = 'active',
            activated_at = NOW(),
            updated_at = NOW()
        WHERE id = draft_version.id
        RETURNING * INTO draft_version;
    END IF;

    RETURN draft_version;
END;
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
BEGIN
    active_id := public.active_taxonomy_version_id();

    SELECT COUNT(*)::INTEGER
    INTO node_count
    FROM public.taxon_nodes
    WHERE taxonomy_version_id = active_id;

    IF node_count = 0 THEN
        PERFORM public.refresh_taxonomy_nodes_from_species_dictionary('bootstrap-sync', TRUE);
        active_id := public.active_taxonomy_version_id();

        SELECT COUNT(*)::INTEGER
        INTO node_count
        FROM public.taxon_nodes
        WHERE taxonomy_version_id = active_id;
    END IF;

    RETURN node_count;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_taxon_nodes_after_species_dictionary_change ON public.species_dictionary;

ALTER TABLE public.explore_community_requests
    ADD COLUMN IF NOT EXISTS taxonomy_version_id UUID,
    ADD COLUMN IF NOT EXISTS consensus_processing_state TEXT NOT NULL DEFAULT 'idle',
    ADD COLUMN IF NOT EXISTS last_consensus_job_id UUID;

UPDATE public.explore_community_requests ecr
SET taxonomy_version_id = COALESCE(initial_taxon.taxonomy_version_id, public.active_taxonomy_version_id())
FROM public.taxon_nodes initial_taxon
WHERE initial_taxon.id = ecr.initial_taxon_node_id
  AND ecr.taxonomy_version_id IS NULL;

UPDATE public.explore_community_requests
SET taxonomy_version_id = public.active_taxonomy_version_id()
WHERE taxonomy_version_id IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.explore_community_requests'::REGCLASS
          AND conname = 'explore_community_requests_taxonomy_version_id_fkey'
    ) THEN
        ALTER TABLE public.explore_community_requests
            ADD CONSTRAINT explore_community_requests_taxonomy_version_id_fkey
            FOREIGN KEY (taxonomy_version_id)
            REFERENCES public.taxonomy_versions(id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.explore_community_requests'::REGCLASS
          AND conname = 'explore_community_requests_consensus_processing_state_check'
    ) THEN
        ALTER TABLE public.explore_community_requests
            ADD CONSTRAINT explore_community_requests_consensus_processing_state_check
            CHECK (consensus_processing_state IN ('idle', 'queued', 'processing', 'failed'));
    END IF;
END $$;

ALTER TABLE public.explore_community_requests
    ALTER COLUMN taxonomy_version_id SET DEFAULT public.active_taxonomy_version_id(),
    ALTER COLUMN taxonomy_version_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_explore_community_requests_taxonomy_version
    ON public.explore_community_requests(taxonomy_version_id, status, requested_at DESC);

ALTER TABLE public.explore_identifications
    ADD COLUMN IF NOT EXISTS taxonomy_version_id UUID;

UPDATE public.explore_identifications ei
SET taxonomy_version_id = tn.taxonomy_version_id
FROM public.taxon_nodes tn
WHERE tn.id = ei.taxon_node_id
  AND ei.taxonomy_version_id IS NULL;

UPDATE public.explore_identifications
SET taxonomy_version_id = public.active_taxonomy_version_id()
WHERE taxonomy_version_id IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.explore_identifications'::REGCLASS
          AND conname = 'explore_identifications_taxonomy_version_id_fkey'
    ) THEN
        ALTER TABLE public.explore_identifications
            ADD CONSTRAINT explore_identifications_taxonomy_version_id_fkey
            FOREIGN KEY (taxonomy_version_id)
            REFERENCES public.taxonomy_versions(id)
            ON DELETE RESTRICT;
    END IF;
END $$;

ALTER TABLE public.explore_identifications
    ALTER COLUMN taxonomy_version_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_explore_identifications_request_taxonomy_active
    ON public.explore_identifications(request_id, taxonomy_version_id, created_at DESC)
    WHERE withdrawn_at IS NULL;

CREATE TABLE IF NOT EXISTS public.community_consensus_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL UNIQUE REFERENCES public.explore_community_requests(id) ON DELETE CASCADE,
    status public.community_consensus_job_status NOT NULL DEFAULT 'pending',
    reason TEXT NOT NULL DEFAULT 'identification_changed',
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error TEXT,
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_community_consensus_jobs_pending
    ON public.community_consensus_jobs(status, available_at, updated_at);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.explore_community_requests'::REGCLASS
          AND conname = 'explore_community_requests_last_consensus_job_id_fkey'
    ) THEN
        ALTER TABLE public.explore_community_requests
            ADD CONSTRAINT explore_community_requests_last_consensus_job_id_fkey
            FOREIGN KEY (last_consensus_job_id)
            REFERENCES public.community_consensus_jobs(id)
            ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.community_consensus_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES public.explore_community_requests(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    job_id UUID REFERENCES public.community_consensus_jobs(id) ON DELETE SET NULL,
    previous_status public.explore_community_request_status,
    new_status public.explore_community_request_status,
    previous_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    new_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    previous_score DOUBLE PRECISION,
    new_score DOUBLE PRECISION,
    previous_identification_count INTEGER,
    new_identification_count INTEGER,
    previous_rank TEXT,
    new_rank TEXT,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_community_consensus_events_request_created
    ON public.community_consensus_events(request_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.explore_observation_projection (
    post_id UUID PRIMARY KEY REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    projection_state public.explore_observation_projection_state NOT NULL DEFAULT 'normal',
    community_request_id UUID UNIQUE REFERENCES public.explore_community_requests(id) ON DELETE SET NULL,
    resolved_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    public_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_explore_observation_projection_state
    ON public.explore_observation_projection(projection_state, updated_at DESC);

ALTER TABLE public.taxonomy_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxon_names ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxon_node_replacements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_consensus_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_consensus_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_observation_projection ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'taxonomy_versions' AND policyname = 'Authenticated users can read taxonomy versions'
    ) THEN
        CREATE POLICY "Authenticated users can read taxonomy versions"
            ON public.taxonomy_versions
            FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'taxon_names' AND policyname = 'Authenticated users can read taxon names'
    ) THEN
        CREATE POLICY "Authenticated users can read taxon names"
            ON public.taxon_names
            FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sync_explore_observation_projection(target_request_id UUID)
RETURNS public.explore_observation_projection
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_row public.explore_community_requests;
    target_scan_id UUID;
    target_state public.explore_observation_projection_state;
    target_public_taxon_id UUID;
    updated_projection public.explore_observation_projection;
BEGIN
    SELECT *
    INTO request_row
    FROM public.explore_community_requests
    WHERE id = target_request_id;

    IF request_row.id IS NULL THEN
        RAISE EXCEPTION 'Community request not found.' USING ERRCODE = 'P0001';
    END IF;

    SELECT scan_id
    INTO target_scan_id
    FROM public.explore_posts
    WHERE id = request_row.post_id;

    target_state := CASE
        WHEN request_row.status = 'withdrawn' THEN 'withdrawn'::public.explore_observation_projection_state
        WHEN request_row.status = 'resolved' THEN 'community_resolved'::public.explore_observation_projection_state
        ELSE 'community_needs_id'::public.explore_observation_projection_state
    END;
    target_public_taxon_id := CASE
        WHEN request_row.status = 'resolved' THEN request_row.resolved_taxon_node_id
        ELSE NULL
    END;

    INSERT INTO public.explore_observation_projection (
        post_id,
        scan_id,
        projection_state,
        community_request_id,
        resolved_taxon_node_id,
        public_taxon_node_id,
        updated_at
    )
    VALUES (
        request_row.post_id,
        COALESCE(target_scan_id, request_row.scan_id),
        target_state,
        request_row.id,
        request_row.resolved_taxon_node_id,
        target_public_taxon_id,
        NOW()
    )
    ON CONFLICT (post_id) DO UPDATE
    SET scan_id = EXCLUDED.scan_id,
        projection_state = EXCLUDED.projection_state,
        community_request_id = EXCLUDED.community_request_id,
        resolved_taxon_node_id = EXCLUDED.resolved_taxon_node_id,
        public_taxon_node_id = EXCLUDED.public_taxon_node_id,
        updated_at = NOW()
    RETURNING * INTO updated_projection;

    RETURN updated_projection;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_explore_observation_projection_trigger()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.sync_explore_observation_projection(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_explore_observation_projection ON public.explore_community_requests;
CREATE TRIGGER trg_sync_explore_observation_projection
AFTER INSERT OR UPDATE OF status, resolved_taxon_node_id, withdrawn_at
ON public.explore_community_requests
FOR EACH ROW
EXECUTE FUNCTION public.sync_explore_observation_projection_trigger();

INSERT INTO public.explore_observation_projection (
    post_id,
    scan_id,
    projection_state,
    community_request_id,
    resolved_taxon_node_id,
    public_taxon_node_id
)
SELECT
    ep.id,
    ep.scan_id,
    COALESCE(
        CASE
            WHEN ecr.status = 'needs_id' THEN 'community_needs_id'::public.explore_observation_projection_state
            WHEN ecr.status = 'resolved' THEN 'community_resolved'::public.explore_observation_projection_state
            WHEN ecr.status = 'withdrawn' THEN 'withdrawn'::public.explore_observation_projection_state
            ELSE 'normal'::public.explore_observation_projection_state
        END,
        'normal'::public.explore_observation_projection_state
    ),
    ecr.id,
    ecr.resolved_taxon_node_id,
    CASE WHEN ecr.status = 'resolved' THEN ecr.resolved_taxon_node_id ELSE NULL END
FROM public.explore_posts ep
LEFT JOIN public.explore_community_requests ecr
    ON ecr.post_id = ep.id
   AND ecr.withdrawn_at IS NULL
ON CONFLICT (post_id) DO UPDATE
SET scan_id = EXCLUDED.scan_id,
    projection_state = EXCLUDED.projection_state,
    community_request_id = EXCLUDED.community_request_id,
    resolved_taxon_node_id = EXCLUDED.resolved_taxon_node_id,
    public_taxon_node_id = EXCLUDED.public_taxon_node_id,
    updated_at = NOW();

CREATE OR REPLACE FUNCTION public.enqueue_community_consensus_job(
    target_request_id UUID,
    job_reason TEXT DEFAULT 'identification_changed'
)
RETURNS public.community_consensus_jobs
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    queued_job public.community_consensus_jobs;
BEGIN
    INSERT INTO public.community_consensus_jobs (
        request_id,
        status,
        reason,
        last_error,
        available_at,
        locked_at,
        processed_at,
        updated_at
    )
    VALUES (
        target_request_id,
        'pending',
        COALESCE(NULLIF(BTRIM(job_reason), ''), 'identification_changed'),
        NULL,
        NOW(),
        NULL,
        NULL,
        NOW()
    )
    ON CONFLICT (request_id) DO UPDATE
    SET status = 'pending',
        reason = EXCLUDED.reason,
        last_error = NULL,
        available_at = NOW(),
        locked_at = NULL,
        processed_at = NULL,
        updated_at = NOW()
    RETURNING * INTO queued_job;

    UPDATE public.explore_community_requests
    SET consensus_processing_state = 'queued',
        last_consensus_job_id = queued_job.id,
        updated_at = NOW()
    WHERE id = target_request_id;

    RETURN queued_job;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_explore_community_consensus(
    target_request_id UUID,
    event_reason TEXT DEFAULT 'job_processed',
    target_job_id UUID DEFAULT NULL
)
RETURNS public.explore_community_requests
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    previous_request public.explore_community_requests;
    updated_request public.explore_community_requests;
    active_count INTEGER;
    selected_taxon_node_id UUID;
    selected_rank TEXT;
    selected_has_genus_best_possible BOOLEAN := FALSE;
    selected_score DOUBLE PRECISION;
    should_resolve BOOLEAN := FALSE;
BEGIN
    SELECT *
    INTO previous_request
    FROM public.explore_community_requests
    WHERE id = target_request_id
    FOR UPDATE;

    IF previous_request.id IS NULL THEN
        RAISE EXCEPTION 'Community request not found.' USING ERRCODE = 'P0001';
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO active_count
    FROM public.explore_identifications
    WHERE request_id = target_request_id
      AND withdrawn_at IS NULL;

    IF active_count >= 2 THEN
        WITH active_votes AS (
            SELECT
                ei.id,
                ei.disagreement_mode,
                ei.is_genus_best_possible,
                tn.path,
                tn.rank
            FROM public.explore_identifications ei
            JOIN public.taxon_nodes tn
                ON tn.id = ei.taxon_node_id
               AND tn.taxonomy_version_id = previous_request.taxonomy_version_id
            WHERE ei.request_id = target_request_id
              AND ei.withdrawn_at IS NULL
              AND ei.taxonomy_version_id = previous_request.taxonomy_version_id
        ),
        candidates AS (
            SELECT DISTINCT tn.id, tn.path, tn.rank
            FROM public.taxon_nodes tn
            JOIN active_votes av
                ON tn.path @> av.path
            WHERE tn.taxonomy_version_id = previous_request.taxonomy_version_id
        ),
        scored AS (
            SELECT
                c.id AS taxon_node_id,
                c.rank,
                COUNT(*) FILTER (WHERE c.path @> av.path)::INTEGER AS support_count,
                COUNT(*) FILTER (
                    WHERE (
                        NOT (c.path @> av.path)
                        AND NOT (av.path @> c.path)
                    )
                    OR (
                        av.path @> c.path
                        AND av.disagreement_mode = 'explicit_disagreement'
                    )
                )::INTEGER AS disagreement_count,
                EXISTS (
                    SELECT 1
                    FROM active_votes exact_genus
                    WHERE exact_genus.path = c.path
                      AND exact_genus.rank = 'genus'
                      AND exact_genus.is_genus_best_possible = TRUE
                ) AS has_genus_best_possible
            FROM candidates c
            CROSS JOIN active_votes av
            GROUP BY c.id, c.path, c.rank
        )
        SELECT
            taxon_node_id,
            rank,
            has_genus_best_possible,
            support_count::DOUBLE PRECISION / NULLIF(support_count + disagreement_count, 0)::DOUBLE PRECISION AS score
        INTO
            selected_taxon_node_id,
            selected_rank,
            selected_has_genus_best_possible,
            selected_score
        FROM scored
        WHERE support_count >= 2
          AND support_count::DOUBLE PRECISION / NULLIF(support_count + disagreement_count, 0)::DOUBLE PRECISION > (2.0 / 3.0)
        ORDER BY public.community_taxon_rank_sort(rank) DESC, support_count DESC, taxon_node_id
        LIMIT 1;
    END IF;

    IF selected_taxon_node_id IS NOT NULL THEN
        should_resolve := selected_rank = 'species'
            OR (selected_rank = 'genus' AND selected_has_genus_best_possible = TRUE);
    END IF;

    UPDATE public.explore_community_requests
    SET status = CASE
            WHEN status = 'withdrawn' THEN status
            WHEN should_resolve THEN 'resolved'::public.explore_community_request_status
            ELSE 'needs_id'::public.explore_community_request_status
        END,
        current_community_taxon_node_id = selected_taxon_node_id,
        resolved_taxon_node_id = CASE WHEN should_resolve THEN selected_taxon_node_id ELSE NULL END,
        resolved_observation_taxon_node_id = CASE WHEN should_resolve THEN selected_taxon_node_id ELSE NULL END,
        consensus_score = selected_score,
        consensus_identification_count = active_count,
        consensus_rank = selected_rank,
        resolved_at = CASE
            WHEN should_resolve THEN COALESCE(resolved_at, NOW())
            ELSE NULL
        END,
        updated_at = NOW()
    WHERE id = target_request_id
    RETURNING * INTO updated_request;

    IF previous_request.status IS DISTINCT FROM updated_request.status
       OR previous_request.current_community_taxon_node_id IS DISTINCT FROM updated_request.current_community_taxon_node_id
       OR previous_request.resolved_taxon_node_id IS DISTINCT FROM updated_request.resolved_taxon_node_id
       OR previous_request.consensus_score IS DISTINCT FROM updated_request.consensus_score
       OR previous_request.consensus_identification_count IS DISTINCT FROM updated_request.consensus_identification_count
       OR previous_request.consensus_rank IS DISTINCT FROM updated_request.consensus_rank THEN
        INSERT INTO public.community_consensus_events (
            request_id,
            post_id,
            job_id,
            previous_status,
            new_status,
            previous_taxon_node_id,
            new_taxon_node_id,
            previous_score,
            new_score,
            previous_identification_count,
            new_identification_count,
            previous_rank,
            new_rank,
            reason
        )
        VALUES (
            updated_request.id,
            updated_request.post_id,
            target_job_id,
            previous_request.status,
            updated_request.status,
            previous_request.current_community_taxon_node_id,
            updated_request.current_community_taxon_node_id,
            previous_request.consensus_score,
            updated_request.consensus_score,
            previous_request.consensus_identification_count,
            updated_request.consensus_identification_count,
            previous_request.consensus_rank,
            updated_request.consensus_rank,
            COALESCE(NULLIF(BTRIM(event_reason), ''), 'job_processed')
        );
    END IF;

    RETURN updated_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_community_consensus_job(target_job_id UUID)
RETURNS public.explore_community_requests
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    job_row public.community_consensus_jobs;
    updated_request public.explore_community_requests;
BEGIN
    SELECT *
    INTO job_row
    FROM public.community_consensus_jobs
    WHERE id = target_job_id
    FOR UPDATE;

    IF job_row.id IS NULL THEN
        RAISE EXCEPTION 'Consensus job not found.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.community_consensus_jobs
    SET status = 'processing',
        locked_at = NOW(),
        updated_at = NOW()
    WHERE id = job_row.id;

    UPDATE public.explore_community_requests
    SET consensus_processing_state = 'processing',
        updated_at = NOW()
    WHERE id = job_row.request_id;

    BEGIN
        updated_request := public.apply_explore_community_consensus(
            job_row.request_id,
            job_row.reason,
            job_row.id
        );

        UPDATE public.community_consensus_jobs
        SET status = 'completed',
            attempt_count = attempt_count + 1,
            last_error = NULL,
            locked_at = NULL,
            processed_at = NOW(),
            updated_at = NOW()
        WHERE id = job_row.id;

        UPDATE public.explore_community_requests
        SET consensus_processing_state = 'idle',
            updated_at = NOW()
        WHERE id = job_row.request_id;

        RETURN updated_request;
    EXCEPTION WHEN OTHERS THEN
        UPDATE public.community_consensus_jobs
        SET status = 'failed',
            attempt_count = attempt_count + 1,
            last_error = SQLERRM,
            locked_at = NULL,
            available_at = NOW() + INTERVAL '5 minutes',
            updated_at = NOW()
        WHERE id = job_row.id;

        UPDATE public.explore_community_requests
        SET consensus_processing_state = 'failed',
            updated_at = NOW()
        WHERE id = job_row.request_id;

        RAISE;
    END;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_community_consensus_jobs(max_jobs INTEGER DEFAULT 25)
RETURNS TABLE(
    job_id UUID,
    request_id UUID,
    status TEXT,
    error_message TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    job_row public.community_consensus_jobs;
    failure_message TEXT;
BEGIN
    FOR job_row IN
        SELECT *
        FROM public.community_consensus_jobs
        WHERE status IN ('pending', 'failed')
          AND available_at <= NOW()
          AND attempt_count < 5
        ORDER BY available_at ASC, updated_at ASC
        LIMIT LEAST(GREATEST(COALESCE(max_jobs, 25), 1), 100)
        FOR UPDATE SKIP LOCKED
    LOOP
        BEGIN
            PERFORM public.process_community_consensus_job(job_row.id);
            RETURN QUERY SELECT job_row.id, job_row.request_id, 'completed'::TEXT, NULL::TEXT;
        EXCEPTION WHEN OTHERS THEN
            failure_message := SQLERRM;
            RETURN QUERY SELECT job_row.id, job_row.request_id, 'failed'::TEXT, failure_message;
        END;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.community_identification_role_label(
    disagreement_mode public.explore_identification_disagreement,
    withdrawn_at TIMESTAMPTZ,
    taxon_path LTREE,
    current_path LTREE
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT CASE
        WHEN withdrawn_at IS NOT NULL THEN 'withdrawn'
        WHEN disagreement_mode = 'maverick' THEN 'maverick'
        WHEN disagreement_mode = 'explicit_disagreement' THEN 'disagreeing'
        WHEN current_path IS NULL THEN 'identifying'
        WHEN taxon_path = current_path THEN 'supporting'
        WHEN current_path @> taxon_path THEN 'leading'
        WHEN taxon_path @> current_path THEN 'broad_support'
        ELSE 'maverick'
    END;
$$;

DROP TRIGGER IF EXISTS trg_recalculate_explore_community_consensus ON public.explore_identifications;

CREATE OR REPLACE FUNCTION public.recalculate_explore_community_consensus(target_request_id UUID)
RETURNS public.explore_community_requests
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    queued_job public.community_consensus_jobs;
    fallback_request public.explore_community_requests;
BEGIN
    queued_job := public.enqueue_community_consensus_job(target_request_id, 'compat_recalculate');

    BEGIN
        RETURN public.process_community_consensus_job(queued_job.id);
    EXCEPTION WHEN OTHERS THEN
        SELECT *
        INTO fallback_request
        FROM public.explore_community_requests
        WHERE id = target_request_id;

        RETURN fallback_request;
    END;
END;
$$;

DROP FUNCTION IF EXISTS public.search_community_taxa(TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.search_community_taxa(TEXT, INTEGER, UUID);

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
    species_id UUID
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
        GROUP BY tn.id, tn.taxonomy_version_id, tn.common_name, tn.scientific_name, tn.rank, tn.path, tn.species_id
    )
    SELECT
        taxon_id,
        taxonomy_version_id,
        common_name,
        scientific_name,
        rank,
        path,
        species_id
    FROM matches
    ORDER BY
        match_rank,
        public.community_taxon_rank_sort(rank) DESC,
        COALESCE(common_name, scientific_name),
        scientific_name
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 20), 1), 50);
$$;

DROP FUNCTION IF EXISTS public.get_community_identification_feed(UUID, INTEGER, TIMESTAMPTZ, UUID, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION public.get_community_identification_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 30,
    before_requested_at TIMESTAMPTZ DEFAULT NULL,
    before_request_id UUID DEFAULT NULL,
    viewer_latitude DOUBLE PRECISION DEFAULT NULL,
    viewer_longitude DOUBLE PRECISION DEFAULT NULL
)
RETURNS TABLE(
    request_id UUID,
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    requested_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    taxonomy_version_id UUID,
    projection_state TEXT,
    consensus_processing_state TEXT,
    current_taxon_id UUID,
    current_common_name TEXT,
    current_scientific_name TEXT,
    current_rank TEXT,
    current_path TEXT,
    initial_taxon_id UUID,
    initial_common_name TEXT,
    initial_scientific_name TEXT,
    initial_rank TEXT,
    initial_path TEXT,
    consensus_score DOUBLE PRECISION,
    identification_count INTEGER,
    viewer_has_identified BOOLEAN,
    public_location_label TEXT,
    location_sharing TEXT
)
LANGUAGE SQL
STABLE
AS $$
    WITH visible_requests AS (
        SELECT
            ecr.id AS request_id,
            ep.id AS post_id,
            ep.scan_id,
            s.image_storage_urls[1] AS hero_image_url,
            ecr.requested_at,
            ep.user_id AS author_user_id,
            u.public_author_name AS author_name,
            u.public_avatar_url AS author_avatar_url,
            ecr.taxonomy_version_id,
            eop.projection_state::TEXT AS projection_state,
            ecr.consensus_processing_state,
            COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id) AS current_taxon_id,
            current_taxon.common_name AS current_common_name,
            current_taxon.scientific_name AS current_scientific_name,
            current_taxon.rank AS current_rank,
            current_taxon.path::TEXT AS current_path,
            ecr.initial_taxon_node_id AS initial_taxon_id,
            initial_taxon.common_name AS initial_common_name,
            initial_taxon.scientific_name AS initial_scientific_name,
            initial_taxon.rank AS initial_rank,
            initial_taxon.path::TEXT AS initial_path,
            ecr.consensus_score,
            ecr.consensus_identification_count AS identification_count,
            EXISTS (
                SELECT 1
                FROM public.explore_identifications ei
                WHERE ei.request_id = ecr.id
                  AND ei.user_id = self_id
                  AND ei.withdrawn_at IS NULL
            ) AS viewer_has_identified,
            ep.public_location_label,
            ep.location_sharing,
            CASE
                WHEN viewer_latitude IS NULL OR viewer_longitude IS NULL THEN NULL
                WHEN ep.public_latitude IS NULL OR ep.public_longitude IS NULL THEN NULL
                ELSE public.haversine_distance_meters(
                    ep.public_latitude,
                    ep.public_longitude,
                    viewer_latitude,
                    viewer_longitude
                )
            END AS distance_meters
        FROM public.explore_community_requests ecr
        JOIN public.explore_observation_projection eop
            ON eop.community_request_id = ecr.id
           AND eop.projection_state = 'community_needs_id'
        JOIN public.explore_posts ep
            ON ep.id = ecr.post_id
        JOIN public.scans s
            ON s.id = ep.scan_id
        JOIN public.users u
            ON u.id = ep.user_id
        LEFT JOIN public.taxon_nodes current_taxon
            ON current_taxon.id = COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id)
        LEFT JOIN public.taxon_nodes initial_taxon
            ON initial_taxon.id = ecr.initial_taxon_node_id
        WHERE ecr.status = 'needs_id'
          AND ecr.withdrawn_at IS NULL
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND u.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
                 OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
          )
          AND (
              before_requested_at IS NULL
              OR before_request_id IS NULL
              OR ecr.requested_at < before_requested_at
              OR (ecr.requested_at = before_requested_at AND ecr.id < before_request_id)
          )
    )
    SELECT
        request_id,
        post_id,
        scan_id,
        hero_image_url,
        requested_at,
        author_user_id,
        author_name,
        author_avatar_url,
        taxonomy_version_id,
        projection_state,
        consensus_processing_state,
        current_taxon_id,
        current_common_name,
        current_scientific_name,
        current_rank,
        current_path,
        initial_taxon_id,
        initial_common_name,
        initial_scientific_name,
        initial_rank,
        initial_path,
        consensus_score,
        identification_count,
        viewer_has_identified,
        public_location_label,
        location_sharing
    FROM visible_requests
    ORDER BY
        CASE WHEN distance_meters IS NULL THEN 1 ELSE 0 END,
        distance_meters ASC NULLS LAST,
        requested_at DESC,
        request_id DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 30), 0), 100);
$$;

DROP FUNCTION IF EXISTS public.get_community_identification_detail(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_community_identification_detail(
    self_id UUID,
    target_request_id UUID
)
RETURNS TABLE(
    request_id UUID,
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    requested_at TIMESTAMPTZ,
    status TEXT,
    note TEXT,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    taxonomy_version_id UUID,
    projection_state TEXT,
    consensus_processing_state TEXT,
    current_taxon_id UUID,
    current_common_name TEXT,
    current_scientific_name TEXT,
    current_rank TEXT,
    current_path TEXT,
    initial_taxon_id UUID,
    initial_common_name TEXT,
    initial_scientific_name TEXT,
    initial_rank TEXT,
    initial_path TEXT,
    resolved_taxon_id UUID,
    consensus_score DOUBLE PRECISION,
    identification_count INTEGER,
    viewer_identification_id UUID,
    public_location_label TEXT,
    location_sharing TEXT,
    identifications JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ecr.id AS request_id,
        ep.id AS post_id,
        ep.scan_id,
        s.image_storage_urls[1] AS hero_image_url,
        ecr.requested_at,
        ecr.status::TEXT,
        ecr.note,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        ecr.taxonomy_version_id,
        eop.projection_state::TEXT AS projection_state,
        ecr.consensus_processing_state,
        COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id) AS current_taxon_id,
        current_taxon.common_name AS current_common_name,
        current_taxon.scientific_name AS current_scientific_name,
        current_taxon.rank AS current_rank,
        current_taxon.path::TEXT AS current_path,
        ecr.initial_taxon_node_id AS initial_taxon_id,
        initial_taxon.common_name AS initial_common_name,
        initial_taxon.scientific_name AS initial_scientific_name,
        initial_taxon.rank AS initial_rank,
        initial_taxon.path::TEXT AS initial_path,
        ecr.resolved_taxon_node_id AS resolved_taxon_id,
        ecr.consensus_score,
        ecr.consensus_identification_count AS identification_count,
        viewer_identification.id AS viewer_identification_id,
        ep.public_location_label,
        ep.location_sharing,
        COALESCE(timeline.identifications, '[]'::JSONB) AS identifications
    FROM public.explore_community_requests ecr
    JOIN public.explore_observation_projection eop
        ON eop.community_request_id = ecr.id
    JOIN public.explore_posts ep
        ON ep.id = ecr.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.taxon_nodes current_taxon
        ON current_taxon.id = COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id)
    LEFT JOIN public.taxon_nodes initial_taxon
        ON initial_taxon.id = ecr.initial_taxon_node_id
    LEFT JOIN LATERAL (
        SELECT ei.id
        FROM public.explore_identifications ei
        WHERE ei.request_id = ecr.id
          AND ei.user_id = self_id
          AND ei.withdrawn_at IS NULL
        ORDER BY ei.created_at DESC
        LIMIT 1
    ) viewer_identification ON TRUE
    LEFT JOIN LATERAL (
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'id', ei.id,
                'user_id', ei.user_id,
                'author_name', iu.public_author_name,
                'author_avatar_url', iu.public_avatar_url,
                'taxon_id', tn.id,
                'common_name', tn.common_name,
                'scientific_name', tn.scientific_name,
                'rank', tn.rank,
                'taxonomy_version_id', tn.taxonomy_version_id,
                'disagreement_mode', ei.disagreement_mode,
                'role_label', public.community_identification_role_label(
                    ei.disagreement_mode,
                    ei.withdrawn_at,
                    tn.path,
                    current_taxon.path
                ),
                'is_genus_best_possible', ei.is_genus_best_possible,
                'reasoning', ei.reasoning,
                'created_at', ei.created_at,
                'withdrawn_at', ei.withdrawn_at,
                'is_viewer', ei.user_id = self_id
            )
            ORDER BY ei.created_at DESC, ei.id DESC
        ) AS identifications
        FROM public.explore_identifications ei
        JOIN public.taxon_nodes tn
            ON tn.id = ei.taxon_node_id
        JOIN public.users iu
            ON iu.id = ei.user_id
        WHERE ei.request_id = ecr.id
    ) timeline ON TRUE
    WHERE ecr.id = target_request_id
      AND ecr.withdrawn_at IS NULL
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.submit_explore_community_identification(
    self_id UUID,
    target_request_id UUID,
    target_taxon_node_id UUID,
    target_disagreement_mode public.explore_identification_disagreement DEFAULT 'implicit_support',
    target_reasoning TEXT DEFAULT NULL,
    target_is_genus_best_possible BOOLEAN DEFAULT FALSE
)
RETURNS public.explore_identifications
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_post_id UUID;
    request_status public.explore_community_request_status;
    request_owner_user_id UUID;
    request_unshared_at TIMESTAMPTZ;
    request_is_tombstoned BOOLEAN;
    request_is_shadowbanned BOOLEAN;
    request_taxonomy_version_id UUID;
    taxon_taxonomy_version_id UUID;
    inserted_identification public.explore_identifications;
    queued_job public.community_consensus_jobs;
BEGIN
    SELECT
        ecr.post_id,
        ecr.status,
        ecr.taxonomy_version_id,
        ep.user_id AS owner_user_id,
        ep.unshared_at,
        s.is_tombstoned,
        u.is_shadowbanned
    INTO
        request_post_id,
        request_status,
        request_taxonomy_version_id,
        request_owner_user_id,
        request_unshared_at,
        request_is_tombstoned,
        request_is_shadowbanned
    FROM public.explore_community_requests ecr
    JOIN public.explore_posts ep
        ON ep.id = ecr.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    WHERE ecr.id = target_request_id
      AND ecr.withdrawn_at IS NULL
    LIMIT 1;

    IF request_post_id IS NULL THEN
        RAISE EXCEPTION 'Community request not found.' USING ERRCODE = 'P0001';
    END IF;

    IF request_status <> 'needs_id' THEN
        RAISE EXCEPTION 'Community request is not accepting identifications.' USING ERRCODE = 'P0001';
    END IF;

    IF request_unshared_at IS NOT NULL OR request_is_tombstoned OR request_is_shadowbanned THEN
        RAISE EXCEPTION 'Community request is no longer available.' USING ERRCODE = 'P0001';
    END IF;

    SELECT taxonomy_version_id
    INTO taxon_taxonomy_version_id
    FROM public.taxon_nodes
    WHERE id = target_taxon_node_id;

    IF taxon_taxonomy_version_id IS NULL THEN
        RAISE EXCEPTION 'Taxon not found.' USING ERRCODE = 'P0001';
    END IF;

    IF taxon_taxonomy_version_id <> request_taxonomy_version_id THEN
        RAISE EXCEPTION 'Taxon belongs to a different taxonomy version.' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_blocks ub
        WHERE (ub.blocker_id = self_id AND ub.blocked_id = request_owner_user_id)
           OR (ub.blocker_id = request_owner_user_id AND ub.blocked_id = self_id)
    ) THEN
        RAISE EXCEPTION 'You cannot identify this request.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.explore_identifications
    SET withdrawn_at = NOW()
    WHERE request_id = target_request_id
      AND user_id = self_id
      AND withdrawn_at IS NULL;

    INSERT INTO public.explore_identifications (
        request_id,
        post_id,
        user_id,
        taxon_node_id,
        taxonomy_version_id,
        disagreement_mode,
        is_genus_best_possible,
        reasoning
    )
    VALUES (
        target_request_id,
        request_post_id,
        self_id,
        target_taxon_node_id,
        request_taxonomy_version_id,
        target_disagreement_mode,
        target_is_genus_best_possible,
        NULLIF(BTRIM(target_reasoning), '')
    )
    RETURNING * INTO inserted_identification;

    queued_job := public.enqueue_community_consensus_job(target_request_id, 'identification_submitted');

    BEGIN
        PERFORM public.process_community_consensus_job(queued_job.id);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN inserted_identification;
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_explore_community_identification(
    self_id UUID,
    target_identification_id UUID
)
RETURNS public.explore_identifications
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    updated_identification public.explore_identifications;
    queued_job public.community_consensus_jobs;
BEGIN
    UPDATE public.explore_identifications
    SET withdrawn_at = NOW()
    WHERE id = target_identification_id
      AND user_id = self_id
      AND withdrawn_at IS NULL
    RETURNING * INTO updated_identification;

    IF updated_identification.id IS NULL THEN
        RAISE EXCEPTION 'Active identification not found.' USING ERRCODE = 'P0001';
    END IF;

    queued_job := public.enqueue_community_consensus_job(updated_identification.request_id, 'identification_withdrawn');

    BEGIN
        PERFORM public.process_community_consensus_job(queued_job.id);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN updated_identification;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_explore_community_identification(
    self_id UUID,
    target_identification_id UUID
)
RETURNS public.explore_identifications
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_row public.explore_identifications;
    restored_identification public.explore_identifications;
    queued_job public.community_consensus_jobs;
BEGIN
    SELECT *
    INTO target_row
    FROM public.explore_identifications
    WHERE id = target_identification_id
      AND user_id = self_id
    LIMIT 1;

    IF target_row.id IS NULL THEN
        RAISE EXCEPTION 'Identification not found.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.explore_identifications
    SET withdrawn_at = NOW()
    WHERE request_id = target_row.request_id
      AND user_id = self_id
      AND withdrawn_at IS NULL
      AND id <> target_identification_id;

    UPDATE public.explore_identifications
    SET withdrawn_at = NULL,
        restored_at = NOW()
    WHERE id = target_identification_id
      AND user_id = self_id
    RETURNING * INTO restored_identification;

    queued_job := public.enqueue_community_consensus_job(restored_identification.request_id, 'identification_restored');

    BEGIN
        PERFORM public.process_community_consensus_job(queued_job.id);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN restored_identification;
END;
$$;

DO $$
DECLARE
    function_signature TEXT;
    target_function REGPROCEDURE;
    function_definition TEXT;
    patched_definition TEXT;
    has_projection_join BOOLEAN;
BEGIN
    FOREACH function_signature IN ARRAY ARRAY[
        'public.get_explore_post(uuid, uuid)',
        'public.get_explore_feed(uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_trending(uuid, integer, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_nearby(uuid, double precision, double precision, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_following(uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_author_posts(uuid, uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_hashtag_posts(uuid, text, integer, timestamp with time zone, uuid)',
        'public.get_explore_map_posts(uuid, double precision, double precision, double precision, double precision, integer)'
    ] LOOP
        target_function := TO_REGPROCEDURE(function_signature);
        IF target_function IS NULL THEN
            RAISE EXCEPTION 'Could not find Explore RPC % to patch community projection', function_signature;
        END IF;

        function_definition := PG_GET_FUNCTIONDEF(target_function);
        IF function_definition LIKE '%public.explore_observation_projection eop%' THEN
            CONTINUE;
        END IF;

        patched_definition := function_definition;

        -- Upgrade any environment that already received the earlier
        -- request-table join patch.
        patched_definition := REPLACE(
            patched_definition,
            'LEFT JOIN public.explore_community_requests ecr
        ON ecr.post_id = ep.id
       AND ecr.withdrawn_at IS NULL
       AND ecr.status IN (''needs_id'', ''resolved'')
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = ecr.resolved_taxon_node_id',
            'LEFT JOIN public.explore_observation_projection eop
        ON eop.post_id = ep.id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = eop.public_taxon_node_id'
        );

        -- Patch pristine Explore RPCs directly to the projection table.
        IF patched_definition NOT LIKE '%public.explore_observation_projection eop%' THEN
            patched_definition := REPLACE(
                patched_definition,
                'LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)',
                'LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    LEFT JOIN public.explore_observation_projection eop
        ON eop.post_id = ep.id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = eop.public_taxon_node_id'
            );
        END IF;

        -- Some Explore RPCs, notably nearby after post-level geoprivacy
        -- projection, have a different species join shape. The author join is
        -- stable across these public Explore reads and lets us add the
        -- projection without changing return columns.
        IF patched_definition NOT LIKE '%public.explore_observation_projection eop%' THEN
            patched_definition := REPLACE(
                patched_definition,
                'JOIN public.users u
        ON u.id = ep.user_id',
                'JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.explore_observation_projection eop
        ON eop.post_id = ep.id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = eop.public_taxon_node_id'
            );
        END IF;

        has_projection_join := patched_definition LIKE '%public.explore_observation_projection eop%';

        patched_definition := REPLACE(
            patched_definition,
            'public.explore_post_community_common_name(ecr.status::TEXT, community_taxon.common_name, community_taxon.scientific_name, ep.species_common_name, sd.common_names, sd.scientific_name) AS species_common_name',
            'public.explore_post_community_common_name(CASE WHEN eop.projection_state = ''community_resolved'' THEN ''resolved'' ELSE NULL END, community_taxon.common_name, community_taxon.scientific_name, ep.species_common_name, sd.common_names, sd.scientific_name) AS species_common_name'
        );

        IF has_projection_join THEN
            patched_definition := REPLACE(
                patched_definition,
                'public.explore_post_species_common_name(ep.species_common_name, sd.common_names, sd.scientific_name) AS species_common_name',
                'public.explore_post_community_common_name(CASE WHEN eop.projection_state = ''community_resolved'' THEN ''resolved'' ELSE NULL END, community_taxon.common_name, community_taxon.scientific_name, ep.species_common_name, sd.common_names, sd.scientific_name) AS species_common_name'
            );
        END IF;

        patched_definition := REPLACE(
            patched_definition,
            'public.explore_post_community_scientific_name(ecr.status::TEXT, community_taxon.scientific_name, sd.scientific_name) AS species_scientific_name',
            'public.explore_post_community_scientific_name(CASE WHEN eop.projection_state = ''community_resolved'' THEN ''resolved'' ELSE NULL END, community_taxon.scientific_name, sd.scientific_name) AS species_scientific_name'
        );

        IF has_projection_join THEN
            patched_definition := REPLACE(
                patched_definition,
                'COALESCE(sd.scientific_name, ''Unknown Subject'') AS species_scientific_name',
                'public.explore_post_community_scientific_name(CASE WHEN eop.projection_state = ''community_resolved'' THEN ''resolved'' ELSE NULL END, community_taxon.scientific_name, sd.scientific_name) AS species_scientific_name'
            );
        END IF;

        patched_definition := REPLACE(
            patched_definition,
            'AND COALESCE(ecr.status::TEXT, ''resolved'') <> ''needs_id''',
            'AND COALESCE(eop.projection_state::TEXT, ''normal'') <> ''community_needs_id'''
        );

        IF has_projection_join
           AND patched_definition NOT LIKE '%COALESCE(eop.projection_state::TEXT, ''normal'') <> ''community_needs_id''%' THEN
            patched_definition := REPLACE(
                patched_definition,
                'WHERE ep.unshared_at IS NULL',
                'WHERE ep.unshared_at IS NULL
      AND COALESCE(eop.projection_state::TEXT, ''normal'') <> ''community_needs_id'''
            );
        END IF;

        IF has_projection_join
           AND patched_definition NOT LIKE '%COALESCE(eop.projection_state::TEXT, ''normal'') <> ''community_needs_id''%' THEN
            RAISE EXCEPTION 'Explore RPC % could not be patched with community projection filter', function_signature;
        END IF;

        IF patched_definition = function_definition THEN
            RAISE EXCEPTION 'Explore RPC % did not contain expected projection patch points', function_signature;
        END IF;

        IF POSITION('ecr.' IN patched_definition) > 0 THEN
            RAISE EXCEPTION 'Explore RPC % still references legacy community request alias after projection patch', function_signature;
        END IF;

        IF POSITION('eop.' IN patched_definition) > 0
           AND patched_definition NOT LIKE '%public.explore_observation_projection eop%' THEN
            RAISE EXCEPTION 'Explore RPC % references projection alias without projection join', function_signature;
        END IF;

        EXECUTE patched_definition;
    END LOOP;
END $$;
