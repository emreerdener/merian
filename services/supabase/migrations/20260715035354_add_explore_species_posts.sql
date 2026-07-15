-- Viewer-aware Species Dictionary sightings stay separate from the cacheable
-- public species projection. This RPC reuses the canonical Explore card
-- projection while applying an exact effective-species filter and a stable
-- image-quality cursor.

CREATE INDEX IF NOT EXISTS idx_scans_effective_species_quality_active
    ON public.scans (
        (COALESCE(confirmed_species_id, species_id)),
        (COALESCE(image_quality_score, '-1'::SMALLINT)) DESC,
        id DESC
    )
    WHERE is_tombstoned = FALSE;

CREATE INDEX IF NOT EXISTS idx_taxon_nodes_species_id
    ON public.taxon_nodes(species_id)
    WHERE species_id IS NOT NULL;

DROP FUNCTION IF EXISTS public.get_explore_species_posts(
    UUID,
    UUID,
    INTEGER,
    SMALLINT,
    TIMESTAMPTZ,
    UUID
);

CREATE FUNCTION public.get_explore_species_posts(
    self_id UUID,
    target_species_id UUID,
    max_limit INTEGER DEFAULT 30,
    before_image_quality_score SMALLINT DEFAULT NULL,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    reference_thumbnail_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    ranking_value INTEGER,
    media_items JSONB,
    image_quality_score SMALLINT
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.public_species_first_reference_image_url(
            target_species.id,
            target_species.reference_image_url
        ) AS reference_thumbnail_url,
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        cards.author_avatar_url,
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        cards.like_count,
        cards.comment_count,
        cards.viewer_has_liked,
        cards.is_owned_by_viewer,
        NULL::INTEGER AS ranking_value,
        cards.media_items,
        scan.image_quality_score
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    JOIN public.species_dictionary target_species
        ON target_species.id = target_species_id
    LEFT JOIN public.explore_observation_projection projection
        ON projection.post_id = cards.post_id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = projection.public_taxon_node_id
    WHERE (
        CASE
            WHEN projection.projection_state::TEXT = 'community_resolved'
                THEN community_taxon.species_id
            ELSE COALESCE(scan.confirmed_species_id, scan.species_id)
        END
    ) = target_species_id
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR COALESCE(scan.image_quality_score, '-1'::SMALLINT)
              < COALESCE(before_image_quality_score, '-1'::SMALLINT)
          OR (
              COALESCE(scan.image_quality_score, '-1'::SMALLINT)
                  = COALESCE(before_image_quality_score, '-1'::SMALLINT)
              AND cards.shared_at < before_shared_at
          )
          OR (
              COALESCE(scan.image_quality_score, '-1'::SMALLINT)
                  = COALESCE(before_image_quality_score, '-1'::SMALLINT)
              AND cards.shared_at = before_shared_at
              AND cards.post_id < before_post_id
          )
      )
    ORDER BY
        COALESCE(scan.image_quality_score, '-1'::SMALLINT) DESC,
        cards.shared_at DESC,
        cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 30), 0);
$$;

COMMENT ON FUNCTION public.get_explore_species_posts(
    UUID,
    UUID,
    INTEGER,
    SMALLINT,
    TIMESTAMPTZ,
    UUID
) IS
  'Returns visibility-safe Explore cards for an exact effective species, ranked by image quality with stable cursor pagination.';

REVOKE ALL ON FUNCTION public.get_explore_species_posts(
    UUID,
    UUID,
    INTEGER,
    SMALLINT,
    TIMESTAMPTZ,
    UUID
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_species_posts(
    UUID,
    UUID,
    INTEGER,
    SMALLINT,
    TIMESTAMPTZ,
    UUID
) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_species_posts(
    UUID,
    UUID,
    INTEGER,
    SMALLINT,
    TIMESTAMPTZ,
    UUID
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_species_posts(
    UUID,
    UUID,
    INTEGER,
    SMALLINT,
    TIMESTAMPTZ,
    UUID
) TO service_role;

NOTIFY pgrst, 'reload schema';
