-- Website quarantine is separate from native viewer preferences and manual hiding.
SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.public_web_explore_review_clear(p_post_id UUID, p_scan_id UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM internal.review_cases review
        WHERE (review.case_type = 'post' AND review.subject_id = p_post_id
            OR review.case_type = 'identification' AND review.subject_id = p_scan_id)
          AND review.status IN ('open', 'in_review')
    ) AND NOT EXISTS (
        SELECT 1 FROM public.scans scan WHERE scan.id = p_scan_id AND scan.is_flagged
    );
$$;
REVOKE ALL ON FUNCTION internal.public_web_explore_review_clear(UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_public_web_explore_posts(p_target_post_id uuid DEFAULT NULL::uuid, p_max_limit integer DEFAULT 24)
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
    WHERE internal.public_web_explore_review_clear(cards.post_id, cards.scan_id) AND (
        p_target_post_id IS NULL
        OR cards.post_id = p_target_post_id
    )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT CASE
        WHEN p_target_post_id IS NULL THEN p_max_limit
        ELSE 1
    END;
END;
$function$;

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
    WHERE internal.public_web_explore_review_clear(cards.post_id, cards.scan_id) AND (
        p_before_shared_at IS NULL
        OR (cards.shared_at, cards.post_id) < (p_before_shared_at, p_before_post_id)
    )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT p_max_limit + 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_detail(
    p_target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    field_notes TEXT,
    location_sharing TEXT,
    hashtags TEXT[],
    species_dictionary_id UUID,
    alternative_common_names TEXT[],
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
    wikipedia_overview TEXT
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_target_post_id IS NULL THEN
        RAISE EXCEPTION 'invalid_public_web_explore_post'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        detail.post_id,
        detail.field_notes,
        detail.location_sharing,
        detail.hashtags,
        detail.species_dictionary_id,
        detail.alternative_common_names,
        detail.taxonomy_kingdom,
        detail.taxonomy_phylum,
        detail.taxonomy_class,
        detail.taxonomy_order,
        detail.taxonomy_family,
        detail.taxonomy_genus,
        detail.ai_reasoning,
        detail.habitat_description,
        detail.gbif_taxon_key,
        detail.iucn_red_list_status,
        detail.hazard_type,
        detail.wikipedia_url,
        detail.reference_image_url,
        detail.wikipedia_overview
    FROM public.get_explore_post_detail(
        NULL::UUID,
        p_target_post_id
    ) AS detail
    INNER JOIN public.explore_projected_post_cards(
        NULL::UUID
    ) AS canonical_post
        ON canonical_post.post_id = detail.post_id
    WHERE canonical_post.post_id = p_target_post_id
      AND internal.public_web_explore_review_clear(canonical_post.post_id, canonical_post.scan_id)
    LIMIT 1;
END;
$$;

-- No report IDs, reporters, reasons, or moderation state leave the server boundary.
CREATE FUNCTION public.get_public_web_explore_visibility(p_post_ids UUID[])
RETURNS TABLE(post_id UUID) LANGUAGE PLPGSQL STABLE SECURITY DEFINER
SET search_path = '' SET statement_timeout = '5s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_post_ids IS NULL OR cardinality(p_post_ids) NOT BETWEEN 1 AND 128
       OR array_position(p_post_ids, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'invalid_public_web_visibility_ids' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY SELECT cards.post_id
    FROM public.explore_projected_post_cards(NULL::UUID) cards
    WHERE cards.post_id = ANY(p_post_ids)
      AND internal.public_web_explore_review_clear(cards.post_id, cards.scan_id);
END;
$$;
REVOKE ALL ON FUNCTION public.get_public_web_explore_visibility(UUID[])
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_visibility(UUID[]) TO service_role;

INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.get_public_web_explore_visibility(uuid[])','Bounded anonymous website eligibility; no review details');
RESET statement_timeout;
RESET lock_timeout;
