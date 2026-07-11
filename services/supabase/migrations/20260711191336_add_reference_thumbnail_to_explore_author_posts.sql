DROP FUNCTION IF EXISTS public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE FUNCTION public.get_explore_author_posts(
    self_id UUID,
    target_author_user_id UUID,
    max_limit INTEGER DEFAULT 30,
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
    ranking_value INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.public_species_first_reference_image_url(
            scan.species_id,
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
        NULL::INTEGER AS ranking_value
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species ON species.id = scan.species_id
    WHERE cards.author_user_id = target_author_user_id
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 30), 0);
$$;

REVOKE ALL ON FUNCTION public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) TO service_role;
