-- The public web detail route reads get_explore_post, while the canonical
-- Explore media snapshot lives behind explore_projected_post_cards. The detail
-- RPC predated that media column and silently discarded it, leaving browsers
-- with only the hero poster and no playable video URL.

DROP FUNCTION IF EXISTS public.get_explore_post(UUID, UUID);

CREATE FUNCTION public.get_explore_post(
    self_id UUID,
    target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
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
    media_items JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
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
        cards.media_items
    FROM public.explore_projected_post_cards(self_id) cards
    WHERE cards.post_id = target_post_id
    LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_explore_post(UUID, UUID) IS
  'Returns one privacy-safe public Explore post, including its canonical ordered media snapshot for web and app detail playback.';

NOTIFY pgrst, 'reload schema';
