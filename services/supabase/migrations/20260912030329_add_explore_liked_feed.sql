-- Personal liked observations reuse the canonical public visibility projection.
CREATE INDEX idx_explore_post_likes_user_id_post_id
    ON public.explore_post_likes (user_id, post_id);

CREATE FUNCTION public.get_explore_feed_liked(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL,
    requested_species_categories TEXT[] DEFAULT '{}'::TEXT[],
    requested_media_types TEXT[] DEFAULT '{}'::TEXT[],
    shared_since TIMESTAMPTZ DEFAULT NULL
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
    media_items JSONB
)
LANGUAGE SQL
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.public_species_first_reference_image_url(
            COALESCE(scan.confirmed_species_id, scan.species_id),
            species.reference_image_url
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
        cards.media_items
    FROM public.explore_post_likes likes
    JOIN public.explore_projected_post_cards(self_id) cards
        ON cards.post_id = likes.post_id
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    WHERE likes.user_id = self_id
      AND (shared_since IS NULL OR cards.shared_at >= shared_since)
      AND (
          COALESCE(CARDINALITY(requested_species_categories), 0) = 0
          OR public.explore_feed_species_category(species.kingdom, species."class")
              = ANY(requested_species_categories)
      )
      AND (
          COALESCE(CARDINALITY(requested_media_types), 0) = 0
          OR EXISTS (
              SELECT 1
              FROM public.explore_post_media filtered_media
              WHERE filtered_media.post_id = cards.post_id
                AND filtered_media.kind = ANY(requested_media_types)
          )
      )
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

REVOKE ALL ON FUNCTION public.get_explore_feed_liked(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_liked(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) TO service_role;

COMMENT ON FUNCTION public.get_explore_feed_liked(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) IS 'Service-only viewer liked observations, ordered by date shared with advanced filters before pagination.';

NOTIFY pgrst, 'reload schema';
