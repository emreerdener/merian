ALTER TABLE public.scans
ADD COLUMN IF NOT EXISTS pet_identification JSONB NULL;

COMMENT ON COLUMN public.scans.pet_identification IS
  'Optional dog/cat pet-specific label emitted by identify. Kept separate from species taxonomy.';

ALTER TABLE public.scans
DROP CONSTRAINT IF EXISTS scans_pet_identification_object_check;

ALTER TABLE public.scans
ADD CONSTRAINT scans_pet_identification_object_check
CHECK (
  pet_identification IS NULL
  OR JSONB_TYPEOF(pet_identification) = 'object'
);

DROP FUNCTION IF EXISTS public.get_explore_post(UUID, UUID);
DROP FUNCTION IF EXISTS public.get_explore_feed(UUID, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_feed_trending(UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_feed_nearby(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_feed_following(UUID, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_hashtag_posts(UUID, TEXT, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_map_posts(UUID, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER);
DROP FUNCTION IF EXISTS public.get_explore_post_detail(UUID, UUID);
DROP FUNCTION IF EXISTS public.explore_projected_post_cards(UUID);

CREATE OR REPLACE FUNCTION public.explore_projected_post_cards(viewer_id UUID)
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
    public_latitude DOUBLE PRECISION,
    public_longitude DOUBLE PRECISION,
    coordinate_visibility TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        s.image_storage_urls[1] AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        public.explore_post_community_common_name(
            CASE WHEN eop.projection_state = 'community_resolved' THEN 'resolved' ELSE NULL END,
            community_taxon.common_name,
            community_taxon.scientific_name,
            ep.species_common_name,
            sd.common_names,
            sd.scientific_name
        ) AS species_common_name,
        public.explore_post_community_scientific_name(
            CASE WHEN eop.projection_state = 'community_resolved' THEN 'resolved' ELSE NULL END,
            community_taxon.scientific_name,
            sd.scientific_name
        ) AS species_scientific_name,
        s.pet_identification,
        ep.public_location_label,
        ep.location_sharing,
        ep.public_latitude,
        ep.public_longitude,
        ep.public_coordinate_visibility AS coordinate_visibility,
        s.time_of_day,
        s.current_month,
        s.weather_condition,
        s.weather_temperature_f,
        ep.like_count,
        ep.comment_count,
        EXISTS (
            SELECT 1
            FROM public.explore_post_likes epl
            WHERE epl.post_id = ep.id
              AND epl.user_id = viewer_id
        ) AS viewer_has_liked,
        (ep.user_id = viewer_id) AS is_owned_by_viewer
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    LEFT JOIN public.explore_observation_projection eop
        ON eop.post_id = ep.id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = eop.public_taxon_node_id
    WHERE ep.unshared_at IS NULL
      AND COALESCE(eop.projection_state::TEXT, 'normal') <> 'community_needs_id'
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = viewer_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = viewer_id)
      );
$$;

CREATE OR REPLACE FUNCTION public.get_explore_post(
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
    is_owned_by_viewer BOOLEAN
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
        cards.is_owned_by_viewer
    FROM public.explore_projected_post_cards(self_id) cards
    WHERE cards.post_id = target_post_id
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
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
    ranking_value INTEGER
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
        NULL::INTEGER AS ranking_value
    FROM public.explore_projected_post_cards(self_id) cards
    WHERE (
        before_shared_at IS NULL
        OR before_post_id IS NULL
        OR cards.shared_at < before_shared_at
        OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
    )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed_trending(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_ranking_value INTEGER DEFAULT NULL,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
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
    ranking_value INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    WITH recent_likes AS (
        SELECT epl.post_id, COUNT(*)::INTEGER AS ranking_value
        FROM public.explore_post_likes epl
        WHERE epl.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY epl.post_id
    )
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
        COALESCE(recent_likes.ranking_value, 0) AS ranking_value
    FROM public.explore_projected_post_cards(self_id) cards
    LEFT JOIN recent_likes ON recent_likes.post_id = cards.post_id
    WHERE (
        before_ranking_value IS NULL
        OR before_shared_at IS NULL
        OR before_post_id IS NULL
        OR COALESCE(recent_likes.ranking_value, 0) < before_ranking_value
        OR (COALESCE(recent_likes.ranking_value, 0) = before_ranking_value AND cards.shared_at < before_shared_at)
        OR (COALESCE(recent_likes.ranking_value, 0) = before_ranking_value AND cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
    )
    ORDER BY COALESCE(recent_likes.ranking_value, 0) DESC, cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed_nearby(
    self_id UUID,
    viewer_latitude DOUBLE PRECISION,
    viewer_longitude DOUBLE PRECISION,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
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
    ranking_value INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    WITH search_window AS (
        SELECT
            80467.2::DOUBLE PRECISION AS radius_meters,
            80467.2 / 111320.0 AS latitude_delta,
            80467.2 / GREATEST(ABS(COS(RADIANS(viewer_latitude))) * 111320.0, 1000.0) AS longitude_delta
    ),
    bounded_posts AS (
        SELECT
            cards.*,
            search_window.radius_meters,
            public.haversine_distance_meters(cards.public_latitude, cards.public_longitude, viewer_latitude, viewer_longitude) AS distance_meters
        FROM public.explore_projected_post_cards(self_id) cards
        CROSS JOIN search_window
        WHERE cards.author_user_id = self_id
           OR (
               cards.location_sharing = 'open'
               AND cards.public_latitude IS NOT NULL
               AND cards.public_longitude IS NOT NULL
               AND cards.public_latitude BETWEEN viewer_latitude - search_window.latitude_delta AND viewer_latitude + search_window.latitude_delta
               AND (
                   (viewer_longitude - search_window.longitude_delta >= -180 AND viewer_longitude + search_window.longitude_delta <= 180 AND cards.public_longitude BETWEEN viewer_longitude - search_window.longitude_delta AND viewer_longitude + search_window.longitude_delta)
                   OR (viewer_longitude - search_window.longitude_delta < -180 AND (cards.public_longitude >= viewer_longitude - search_window.longitude_delta + 360 OR cards.public_longitude <= viewer_longitude + search_window.longitude_delta))
                   OR (viewer_longitude + search_window.longitude_delta > 180 AND (cards.public_longitude >= viewer_longitude - search_window.longitude_delta OR cards.public_longitude <= viewer_longitude + search_window.longitude_delta - 360))
               )
           )
    )
    SELECT
        bounded_posts.post_id,
        bounded_posts.scan_id,
        bounded_posts.hero_image_url,
        bounded_posts.shared_at,
        bounded_posts.author_user_id,
        bounded_posts.author_name,
        bounded_posts.author_avatar_url,
        bounded_posts.species_common_name,
        bounded_posts.species_scientific_name,
        bounded_posts.pet_identification,
        bounded_posts.public_location_label,
        bounded_posts.location_sharing,
        bounded_posts.time_of_day,
        bounded_posts.current_month,
        bounded_posts.weather_condition,
        bounded_posts.weather_temperature_f,
        bounded_posts.like_count,
        bounded_posts.comment_count,
        bounded_posts.viewer_has_liked,
        bounded_posts.is_owned_by_viewer,
        NULL::INTEGER AS ranking_value
    FROM bounded_posts
    WHERE (bounded_posts.distance_meters <= bounded_posts.radius_meters OR bounded_posts.author_user_id = self_id)
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR bounded_posts.shared_at < before_shared_at
          OR (bounded_posts.shared_at = before_shared_at AND bounded_posts.post_id < before_post_id)
      )
    ORDER BY bounded_posts.shared_at DESC, bounded_posts.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed_following(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
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
    ranking_value INTEGER
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
        NULL::INTEGER AS ranking_value
    FROM public.user_follows uf
    JOIN public.explore_projected_post_cards(self_id) cards
        ON cards.author_user_id = uf.followee_user_id
    WHERE uf.follower_user_id = self_id
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_author_posts(
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

CREATE OR REPLACE FUNCTION public.get_explore_hashtag_posts(
    self_id UUID,
    target_tag TEXT,
    max_limit INTEGER DEFAULT 30,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
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
    ranking_value INTEGER
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
        NULL::INTEGER AS ranking_value
    FROM public.explore_post_hashtags eph
    JOIN public.explore_projected_post_cards(self_id) cards
        ON cards.post_id = eph.post_id
    WHERE eph.tag = target_tag
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 30), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_map_posts(
    self_id UUID,
    north_latitude DOUBLE PRECISION,
    south_latitude DOUBLE PRECISION,
    east_longitude DOUBLE PRECISION,
    west_longitude DOUBLE PRECISION,
    max_limit INTEGER DEFAULT 500
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    coordinate_visibility TEXT,
    hero_image_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    taxonomy_kingdom TEXT,
    taxonomy_class TEXT,
    public_location_label TEXT,
    location_sharing TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.public_latitude AS latitude,
        cards.public_longitude AS longitude,
        cards.coordinate_visibility,
        cards.hero_image_url,
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        cards.author_avatar_url,
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        sd.kingdom AS taxonomy_kingdom,
        sd."class" AS taxonomy_class,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        cards.like_count,
        cards.comment_count,
        cards.viewer_has_liked,
        cards.is_owned_by_viewer
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans map_scan
        ON map_scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(map_scan.confirmed_species_id, map_scan.species_id)
    WHERE cards.location_sharing = 'open'
      AND cards.public_latitude IS NOT NULL
      AND cards.public_longitude IS NOT NULL
      AND cards.public_latitude BETWEEN LEAST(north_latitude, south_latitude) AND GREATEST(north_latitude, south_latitude)
      AND (
          (west_longitude <= east_longitude AND cards.public_longitude BETWEEN west_longitude AND east_longitude)
          OR
          (west_longitude > east_longitude AND (
              cards.public_longitude >= west_longitude
              OR cards.public_longitude <= east_longitude
          ))
      )
    ORDER BY cards.shared_at DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 500), 0), 500);
$$;

DROP FUNCTION IF EXISTS public.get_explore_post_detail(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_post_detail(
    self_id UUID,
    target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    field_notes TEXT,
    location_sharing TEXT,
    hashtags TEXT[],
    species_dictionary_id UUID,
    alternative_common_names TEXT[],
    pet_identification JSONB,
    taxonomy_kingdom TEXT,
    taxonomy_phylum TEXT,
    taxonomy_class TEXT,
    taxonomy_order TEXT,
    taxonomy_family TEXT,
    taxonomy_genus TEXT,
    ai_reasoning TEXT,
    habitat_description TEXT,
    gbif_taxon_key INTEGER,
    iucn_red_list_status TEXT,
    hazard_type TEXT,
    wikipedia_url TEXT,
    reference_image_url TEXT,
    wikipedia_overview TEXT,
    similar_species JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        NULLIF(BTRIM(COALESCE(ep.field_notes, '')), '') AS field_notes,
        ep.location_sharing,
        ARRAY(
            SELECT eph.tag
            FROM public.explore_post_hashtags eph
            WHERE eph.post_id = ep.id
            ORDER BY eph.tag
        ) AS hashtags,
        sd.id AS species_dictionary_id,
        ARRAY(
            SELECT NULLIF(BTRIM(names.raw_name), '')
            FROM UNNEST(COALESCE(sd.alternative_common_names, ARRAY[]::TEXT[]))
                WITH ORDINALITY AS names(raw_name, ordinality)
            WHERE NULLIF(BTRIM(names.raw_name), '') IS NOT NULL
            ORDER BY names.ordinality
        ) AS alternative_common_names,
        s.pet_identification,
        sd.kingdom AS taxonomy_kingdom,
        sd.phylum AS taxonomy_phylum,
        sd."class" AS taxonomy_class,
        sd."order" AS taxonomy_order,
        sd.family AS taxonomy_family,
        sd.genus AS taxonomy_genus,
        CASE
            WHEN s.is_flagged = FALSE
             AND COALESCE(s.user_review_state, 'unreviewed'::public.user_review_state) <> 'user_overridden'::public.user_review_state
             AND s.user_identification_override IS NULL
             AND NULLIF(BTRIM(COALESCE(s.ai_reasoning, '')), '') IS NOT NULL
                THEN s.ai_reasoning
            ELSE NULL
        END AS ai_reasoning,
        sd.habitat_description,
        sd.gbif_taxon_key,
        sd.iucn_red_list_status,
        COALESCE(NULLIF(BTRIM(sd.hazard_type), ''), 'none') AS hazard_type,
        sd.wikipedia_url,
        public.public_species_reference_image_urls(sd.id, sd.reference_image_url) AS reference_image_url,
        sd.wikipedia_overview,
        public.public_species_similar_species(sd.id) AS similar_species
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE ep.id = target_post_id
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND ep.location_sharing <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    LIMIT 1;
$$;
