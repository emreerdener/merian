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
    suggested_taxa JSONB,
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
        COALESCE(suggestions.suggested_taxa, '[]'::JSONB) AS suggested_taxa,
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
        WITH raw_suggestions AS (
            SELECT
                initial_taxon.id AS taxon_id,
                initial_taxon.taxonomy_version_id,
                initial_taxon.common_name,
                initial_taxon.scientific_name,
                initial_taxon.rank,
                initial_taxon.path::TEXT AS path,
                initial_taxon.species_id,
                'ai_initial'::TEXT AS suggestion_source,
                NULL::DOUBLE PRECISION AS confidence_score,
                NULL::TEXT AS distinguishing_feature,
                0 AS source_rank,
                0::BIGINT AS candidate_ordinality
            WHERE initial_taxon.id IS NOT NULL

            UNION ALL

            SELECT
                candidate_taxon.id AS taxon_id,
                candidate_taxon.taxonomy_version_id,
                candidate_taxon.common_name,
                candidate_taxon.scientific_name,
                candidate_taxon.rank,
                candidate_taxon.path::TEXT AS path,
                candidate_taxon.species_id,
                'ai_candidate'::TEXT AS suggestion_source,
                CASE
                    WHEN (candidate_item.value->>'confidence_score') ~ '^[0-9]+([.][0-9]+)?$'
                        THEN (candidate_item.value->>'confidence_score')::DOUBLE PRECISION
                    ELSE NULL
                END AS confidence_score,
                NULLIF(BTRIM(candidate_item.value->>'distinguishing_feature'), '') AS distinguishing_feature,
                1 AS source_rank,
                candidate_item.ordinality AS candidate_ordinality
            FROM JSONB_ARRAY_ELEMENTS(
                CASE
                    WHEN JSONB_TYPEOF(s.candidates) = 'array' THEN s.candidates
                    ELSE '[]'::JSONB
                END
            ) WITH ORDINALITY AS candidate_item(value, ordinality)
            JOIN public.taxon_nodes candidate_taxon
                ON candidate_taxon.taxonomy_version_id = ecr.taxonomy_version_id
               AND LOWER(candidate_taxon.scientific_name) = LOWER(BTRIM(candidate_item.value->>'scientific_name'))
            WHERE NULLIF(BTRIM(candidate_item.value->>'scientific_name'), '') IS NOT NULL
        ),
        deduped_suggestions AS (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY taxon_id
                    ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality
                ) AS duplicate_rank
            FROM raw_suggestions
        ),
        limited_suggestions AS (
            SELECT *
            FROM deduped_suggestions
            WHERE duplicate_rank = 1
            ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality
            LIMIT 6
        )
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'taxon_id', taxon_id,
                'taxonomy_version_id', taxonomy_version_id,
                'common_name', common_name,
                'scientific_name', scientific_name,
                'rank', rank,
                'path', path,
                'species_id', species_id,
                'suggestion_source', suggestion_source,
                'confidence_score', confidence_score,
                'distinguishing_feature', distinguishing_feature
            )
            ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality
        ) AS suggested_taxa
        FROM limited_suggestions
    ) suggestions ON TRUE
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
