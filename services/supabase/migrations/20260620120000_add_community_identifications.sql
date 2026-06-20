CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TYPE public.explore_community_request_status AS ENUM (
    'needs_id',
    'resolved',
    'withdrawn'
);

CREATE TYPE public.explore_identification_disagreement AS ENUM (
    'implicit_support',
    'explicit_disagreement',
    'maverick'
);

CREATE TABLE IF NOT EXISTS public.taxon_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    path LTREE NOT NULL UNIQUE,
    parent_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    rank TEXT NOT NULL CHECK (rank IN ('kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species')),
    scientific_name TEXT NOT NULL,
    common_name TEXT,
    species_id UUID UNIQUE REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_taxon_nodes_path_gist
    ON public.taxon_nodes USING GIST(path);
CREATE INDEX IF NOT EXISTS idx_taxon_nodes_parent_id
    ON public.taxon_nodes(parent_id);
CREATE INDEX IF NOT EXISTS idx_taxon_nodes_rank_name
    ON public.taxon_nodes(rank, LOWER(scientific_name));

CREATE TABLE IF NOT EXISTS public.explore_community_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL UNIQUE REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status public.explore_community_request_status NOT NULL DEFAULT 'needs_id',
    note TEXT,
    initial_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    current_community_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    resolved_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    resolved_observation_taxon_node_id UUID REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    consensus_score DOUBLE PRECISION CHECK (consensus_score IS NULL OR (consensus_score >= 0 AND consensus_score <= 1)),
    consensus_identification_count INTEGER NOT NULL DEFAULT 0 CHECK (consensus_identification_count >= 0),
    consensus_rank TEXT CHECK (consensus_rank IS NULL OR consensus_rank IN ('kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species')),
    resolved_at TIMESTAMPTZ,
    withdrawn_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT explore_community_requests_status_consistency CHECK (
        (status = 'needs_id' AND resolved_taxon_node_id IS NULL AND resolved_at IS NULL AND withdrawn_at IS NULL)
        OR (status = 'resolved' AND resolved_taxon_node_id IS NOT NULL AND resolved_at IS NOT NULL AND withdrawn_at IS NULL)
        OR (status = 'withdrawn' AND withdrawn_at IS NOT NULL)
    ),
    CONSTRAINT explore_community_requests_note_length CHECK (note IS NULL OR CHAR_LENGTH(note) <= 1000)
);

CREATE INDEX IF NOT EXISTS idx_explore_community_requests_status_requested
    ON public.explore_community_requests(status, requested_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_explore_community_requests_post_status
    ON public.explore_community_requests(post_id, status)
    WHERE withdrawn_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_explore_community_requests_scan_id
    ON public.explore_community_requests(scan_id);

CREATE TABLE IF NOT EXISTS public.explore_identifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES public.explore_community_requests(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    taxon_node_id UUID NOT NULL REFERENCES public.taxon_nodes(id) ON DELETE RESTRICT,
    disagreement_mode public.explore_identification_disagreement NOT NULL DEFAULT 'implicit_support',
    is_genus_best_possible BOOLEAN NOT NULL DEFAULT FALSE,
    reasoning TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    withdrawn_at TIMESTAMPTZ,
    restored_at TIMESTAMPTZ,
    CONSTRAINT explore_identifications_reasoning_length CHECK (reasoning IS NULL OR CHAR_LENGTH(reasoning) <= 1000)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_identifications_one_active_per_user
    ON public.explore_identifications(request_id, user_id)
    WHERE withdrawn_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_explore_identifications_request_active
    ON public.explore_identifications(request_id, created_at DESC)
    WHERE withdrawn_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_explore_identifications_post_id
    ON public.explore_identifications(post_id);

ALTER TABLE public.taxon_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_community_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_identifications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'taxon_nodes' AND policyname = 'Authenticated users can read taxon nodes'
    ) THEN
        CREATE POLICY "Authenticated users can read taxon nodes"
            ON public.taxon_nodes
            FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_community_requests' AND policyname = 'Request owners can read community requests'
    ) THEN
        CREATE POLICY "Request owners can read community requests"
            ON public.explore_community_requests
            FOR SELECT
            USING (auth.uid() = requested_by);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_identifications' AND policyname = 'Users can read their community identifications'
    ) THEN
        CREATE POLICY "Users can read their community identifications"
            ON public.explore_identifications
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.community_taxon_rank_sort(rank_value TEXT)
RETURNS INTEGER
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE rank_value
        WHEN 'kingdom' THEN 1
        WHEN 'phylum' THEN 2
        WHEN 'class' THEN 3
        WHEN 'order' THEN 4
        WHEN 'family' THEN 5
        WHEN 'genus' THEN 6
        WHEN 'species' THEN 7
        ELSE 0
    END;
$$;

CREATE OR REPLACE FUNCTION public.community_taxon_label(rank_value TEXT, taxon_name TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT LOWER(rank_value) || '_' || SUBSTRING(MD5(LOWER(BTRIM(COALESCE(taxon_name, 'unknown')))) FROM 1 FOR 24);
$$;

CREATE OR REPLACE FUNCTION public.community_taxon_path(
    kingdom_name TEXT,
    phylum_name TEXT,
    class_name TEXT,
    order_name TEXT,
    family_name TEXT,
    genus_name TEXT,
    species_name TEXT
)
RETURNS LTREE
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT ARRAY_TO_STRING(
        ARRAY_REMOVE(ARRAY[
            CASE WHEN NULLIF(BTRIM(kingdom_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('kingdom', kingdom_name) END,
            CASE WHEN NULLIF(BTRIM(phylum_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('phylum', phylum_name) END,
            CASE WHEN NULLIF(BTRIM(class_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('class', class_name) END,
            CASE WHEN NULLIF(BTRIM(order_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('order', order_name) END,
            CASE WHEN NULLIF(BTRIM(family_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('family', family_name) END,
            CASE WHEN NULLIF(BTRIM(genus_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('genus', genus_name) END,
            CASE WHEN NULLIF(BTRIM(species_name), '') IS NULL THEN NULL ELSE public.community_taxon_label('species', species_name) END
        ], NULL),
        '.'
    )::LTREE;
$$;

CREATE OR REPLACE FUNCTION public.sync_taxon_nodes_from_species_dictionary()
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    species_row RECORD;
    lineage RECORD;
    parent_node_id UUID;
    node_path LTREE;
    node_id UUID;
    upsert_count INTEGER := 0;
BEGIN
    FOR species_row IN
        SELECT
            id,
            scientific_name,
            common_names,
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

            IF lineage.species_id IS NOT NULL THEN
                UPDATE public.taxon_nodes
                SET species_id = NULL,
                    updated_at = NOW()
                WHERE species_id = lineage.species_id
                  AND path <> node_path;
            END IF;

            INSERT INTO public.taxon_nodes (
                path,
                parent_id,
                rank,
                scientific_name,
                common_name,
                species_id,
                updated_at
            )
            VALUES (
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
            ON CONFLICT (path) DO UPDATE
            SET parent_id = COALESCE(EXCLUDED.parent_id, public.taxon_nodes.parent_id),
                rank = EXCLUDED.rank,
                scientific_name = EXCLUDED.scientific_name,
                common_name = COALESCE(EXCLUDED.common_name, public.taxon_nodes.common_name),
                species_id = COALESCE(EXCLUDED.species_id, public.taxon_nodes.species_id),
                updated_at = NOW()
            RETURNING id INTO node_id;

            parent_node_id := node_id;
            upsert_count := upsert_count + 1;
        END LOOP;
    END LOOP;

    RETURN upsert_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_taxon_nodes_after_species_dictionary_change()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.sync_taxon_nodes_from_species_dictionary();
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_taxon_nodes_after_species_dictionary_change ON public.species_dictionary;
CREATE TRIGGER trg_sync_taxon_nodes_after_species_dictionary_change
AFTER INSERT OR UPDATE OF scientific_name, common_names, kingdom, phylum, class, "order", family, genus
ON public.species_dictionary
FOR EACH STATEMENT
EXECUTE FUNCTION public.sync_taxon_nodes_after_species_dictionary_change();

SELECT public.sync_taxon_nodes_from_species_dictionary();

CREATE OR REPLACE FUNCTION public.explore_post_community_common_name(
    request_status TEXT,
    community_common_name TEXT,
    community_scientific_name TEXT,
    snapshot_common_name TEXT,
    common_names JSONB,
    scientific_name TEXT
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT CASE
        WHEN request_status = 'resolved' THEN COALESCE(
            NULLIF(BTRIM(community_common_name), ''),
            NULLIF(BTRIM(community_scientific_name), ''),
            public.explore_post_species_common_name(snapshot_common_name, common_names, scientific_name)
        )
        ELSE public.explore_post_species_common_name(snapshot_common_name, common_names, scientific_name)
    END;
$$;

CREATE OR REPLACE FUNCTION public.explore_post_community_scientific_name(
    request_status TEXT,
    community_scientific_name TEXT,
    fallback_scientific_name TEXT
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT CASE
        WHEN request_status = 'resolved' THEN COALESCE(NULLIF(BTRIM(community_scientific_name), ''), fallback_scientific_name, 'Unknown Subject')
        ELSE COALESCE(fallback_scientific_name, 'Unknown Subject')
    END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_explore_community_consensus(target_request_id UUID)
RETURNS public.explore_community_requests
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_count INTEGER;
    selected_taxon_node_id UUID;
    selected_rank TEXT;
    selected_support_count INTEGER;
    selected_disagreement_count INTEGER;
    selected_has_genus_best_possible BOOLEAN := FALSE;
    selected_score DOUBLE PRECISION;
    updated_request public.explore_community_requests;
    should_resolve BOOLEAN := FALSE;
BEGIN
    SELECT COUNT(*)::INTEGER
    INTO active_count
    FROM public.explore_identifications
    WHERE request_id = target_request_id
      AND withdrawn_at IS NULL;

    IF active_count < 2 THEN
        UPDATE public.explore_community_requests
        SET status = CASE WHEN status = 'withdrawn' THEN status ELSE 'needs_id'::public.explore_community_request_status END,
            current_community_taxon_node_id = NULL,
            resolved_taxon_node_id = NULL,
            resolved_observation_taxon_node_id = NULL,
            consensus_score = NULL,
            consensus_identification_count = active_count,
            consensus_rank = NULL,
            resolved_at = NULL,
            updated_at = NOW()
        WHERE id = target_request_id
        RETURNING * INTO updated_request;

        RETURN updated_request;
    END IF;

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
        WHERE ei.request_id = target_request_id
          AND ei.withdrawn_at IS NULL
    ),
    candidates AS (
        SELECT DISTINCT tn.id, tn.path, tn.rank
        FROM public.taxon_nodes tn
        JOIN active_votes av
            ON tn.path @> av.path
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
        support_count,
        disagreement_count,
        has_genus_best_possible,
        support_count::DOUBLE PRECISION / NULLIF(support_count + disagreement_count, 0)::DOUBLE PRECISION AS score
    INTO
        selected_taxon_node_id,
        selected_rank,
        selected_support_count,
        selected_disagreement_count,
        selected_has_genus_best_possible,
        selected_score
    FROM scored
    WHERE support_count >= 2
      AND support_count::DOUBLE PRECISION / NULLIF(support_count + disagreement_count, 0)::DOUBLE PRECISION > (2.0 / 3.0)
    ORDER BY public.community_taxon_rank_sort(rank) DESC, support_count DESC, taxon_node_id
    LIMIT 1;

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

    RETURN updated_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_explore_community_consensus_trigger()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.recalculate_explore_community_consensus(COALESCE(NEW.request_id, OLD.request_id));
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_recalculate_explore_community_consensus ON public.explore_identifications;
CREATE TRIGGER trg_recalculate_explore_community_consensus
AFTER INSERT OR UPDATE OF taxon_node_id, disagreement_mode, is_genus_best_possible, withdrawn_at, restored_at
ON public.explore_identifications
FOR EACH ROW
EXECUTE FUNCTION public.recalculate_explore_community_consensus_trigger();

-- Explore feed graduation is patched in
-- 20260620143000_rebuild_community_identification_core.sql through
-- explore_observation_projection. Keeping the first migration focused on the
-- request/identification tables avoids brittle text rewrites of existing RPCs.

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
                'disagreement_mode', ei.disagreement_mode,
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

CREATE OR REPLACE FUNCTION public.search_community_taxa(
    query_text TEXT,
    max_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
    taxon_id UUID,
    common_name TEXT,
    scientific_name TEXT,
    rank TEXT,
    path TEXT,
    species_id UUID
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        tn.id AS taxon_id,
        tn.common_name,
        tn.scientific_name,
        tn.rank,
        tn.path::TEXT AS path,
        tn.species_id
    FROM public.taxon_nodes tn
    WHERE NULLIF(BTRIM(query_text), '') IS NOT NULL
      AND (
          tn.scientific_name ILIKE '%' || BTRIM(query_text) || '%'
          OR tn.common_name ILIKE '%' || BTRIM(query_text) || '%'
      )
    ORDER BY
        CASE
            WHEN tn.common_name ILIKE BTRIM(query_text) || '%' THEN 0
            WHEN tn.scientific_name ILIKE BTRIM(query_text) || '%' THEN 1
            ELSE 2
        END,
        public.community_taxon_rank_sort(tn.rank) DESC,
        COALESCE(tn.common_name, tn.scientific_name),
        tn.scientific_name
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 20), 1), 50);
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
    inserted_identification public.explore_identifications;
BEGIN
    SELECT
        ecr.post_id,
        ecr.status,
        ep.user_id AS owner_user_id,
        ep.unshared_at,
        s.is_tombstoned,
        u.is_shadowbanned
    INTO
        request_post_id,
        request_status,
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

    IF NOT EXISTS (SELECT 1 FROM public.taxon_nodes WHERE id = target_taxon_node_id) THEN
        RAISE EXCEPTION 'Taxon not found.' USING ERRCODE = 'P0001';
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
        disagreement_mode,
        is_genus_best_possible,
        reasoning
    )
    VALUES (
        target_request_id,
        request_post_id,
        self_id,
        target_taxon_node_id,
        target_disagreement_mode,
        target_is_genus_best_possible,
        NULLIF(BTRIM(target_reasoning), '')
    )
    RETURNING * INTO inserted_identification;

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

    RETURN restored_identification;
END;
$$;
