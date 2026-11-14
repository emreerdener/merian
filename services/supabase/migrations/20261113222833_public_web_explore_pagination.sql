CREATE OR REPLACE FUNCTION public.get_public_web_explore_posts_page(p_max_limit integer DEFAULT 48, p_before_shared_at timestamptz DEFAULT NULL, p_before_post_id uuid DEFAULT NULL)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, reference_thumbnail_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_username text, author_avatar_url text, author_is_pro boolean, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, media_items jsonb, identification jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();

    IF p_max_limit IS NULL OR p_max_limit NOT BETWEEN 1 AND 48 THEN
        RAISE EXCEPTION 'invalid_public_web_explore_limit'
            USING ERRCODE = '22023';
    END IF;

    IF (p_before_shared_at IS NULL) <> (p_before_post_id IS NULL)
       OR (p_before_shared_at IS NOT NULL AND NOT pg_catalog.isfinite(p_before_shared_at)) THEN
        RAISE EXCEPTION 'invalid_public_web_explore_cursor' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.public_species_first_reference_image_url(
            internal.explore_effective_species_id(scan, cards.post_id),
            species.reference_image_url
        ),
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        author.public_username,
        cards.author_avatar_url,
        author.subscription_tier = 'pro',
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        0::INTEGER,
        0::INTEGER,
        FALSE,
        FALSE,
        cards.media_items,
        cards.identification
    FROM public.explore_projected_post_cards(NULL::UUID) AS cards
    INNER JOIN public.scans AS scan
        ON scan.id = cards.scan_id
    INNER JOIN public.users AS author
        ON author.id = cards.author_user_id
    LEFT JOIN public.species_dictionary AS species
        ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
    WHERE (
        p_before_shared_at IS NULL
        OR (cards.shared_at, cards.post_id) < (p_before_shared_at, p_before_post_id)
    )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT p_max_limit + 1;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_public_web_explore_posts_page(integer,timestamptz,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_posts_page(integer,timestamptz,uuid) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.get_public_web_explore_posts_page(integer,timestamp with time zone,uuid)',
     'Bounded anonymous public web discovery pagination; canonical visibility and no viewer state.');
COMMENT ON FUNCTION public.get_public_web_explore_posts_page(integer,timestamptz,uuid) IS
    'Service-only keyset pagination. Returns at most limit+1 rows; consumer trims the lookahead and cursors from the last rendered row. Existing public web RPCs are unchanged.';
