DROP FUNCTION IF EXISTS public.get_community_identification_feed(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    TEXT
);

CREATE OR REPLACE FUNCTION public.get_community_identification_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 30,
    before_requested_at TIMESTAMPTZ DEFAULT NULL,
    before_request_id UUID DEFAULT NULL,
    viewer_latitude DOUBLE PRECISION DEFAULT NULL,
    viewer_longitude DOUBLE PRECISION DEFAULT NULL,
    request_scope TEXT DEFAULT 'all',
    request_group_filter TEXT DEFAULT 'all'
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
    request_group TEXT,
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
            CASE
                WHEN LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE 'plantae%' THEN 'plants'
                WHEN LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.aves.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.aves'
                    THEN 'birds'
                WHEN LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.insecta.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.insecta'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.entognatha.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.entognatha'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.arachnida.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.arachnida'
                    THEN 'insects'
                WHEN LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE 'fungi%' THEN 'fungi'
                WHEN LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.mammalia.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.mammalia'
                    THEN 'mammals'
                WHEN LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.reptilia.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.reptilia'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.amphibia.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.amphibia'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.squamata.%'
                    OR LOWER(COALESCE(current_taxon.path::TEXT, initial_taxon.path::TEXT, '')) LIKE '%.squamata'
                    THEN 'reptiles_amphibians'
                ELSE 'all'
            END AS request_group,
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
          AND (
              COALESCE(request_scope, 'all') = 'all'
              OR (request_scope = 'mine' AND ecr.requested_by = self_id)
          )
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
        request_group,
        consensus_score,
        identification_count,
        viewer_has_identified,
        public_location_label,
        location_sharing
    FROM visible_requests
    WHERE COALESCE(request_group_filter, 'all') = 'all'
       OR request_group = request_group_filter
    ORDER BY
        CASE WHEN distance_meters IS NULL THEN 1 ELSE 0 END,
        distance_meters ASC NULLS LAST,
        requested_at DESC,
        request_id DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 30), 0), 100);
$$;
