-- Prepared consumers only: protocol 4 and current producers remain unchanged.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

-- Pure policy over an already-authorized row. This grants no source-row access.
CREATE OR REPLACE FUNCTION internal.scan_effective_identification(candidate public.scans)
RETURNS JSONB LANGUAGE PLPGSQL STABLE PARALLEL SAFE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE primary_answer JSONB := candidate.primary_identification; review JSONB;
    explicit_result BOOLEAN := primary_answer IS NOT NULL
        OR COALESCE(candidate.identification_provenance ->> 'schema' = 'merian_identify_primary_v1', FALSE);
BEGIN
    IF NOT explicit_result THEN
        -- Legacy records keep their existing identity and review semantics.
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','legacy','rank',NULL,
            'scientific_name',NULL,'common_name',NULL,'primary',NULL,
            'species_id',COALESCE(candidate.confirmed_species_id,candidate.species_id),
            'verified',FALSE,'pending_review',FALSE);
    END IF;
    review := pg_catalog.JSONB_BUILD_OBJECT('version',1,
        'revision',candidate.confirmed_species_identity_revision,'identity',candidate.confirmed_species_identity,
        'user_identification_override',candidate.user_identification_override,
        'user_confirmed_identification',candidate.user_confirmed_identification,
        'confirmed_species_id',candidate.confirmed_species_id,'user_review_state',candidate.user_review_state);
    IF primary_answer IS NULL
       OR candidate.identification_provenance ->> 'schema' IS DISTINCT FROM 'merian_identify_primary_v1'
       OR NOT internal.identification_provenance_is_valid(candidate.identification_provenance)
       OR NOT internal.primary_identification_is_valid(primary_answer)
       OR NOT internal.primary_identification_scan_is_valid(primary_answer,candidate.is_biological_subject,
            candidate.species_id,candidate.candidates,candidate.pet_identification)
       OR NOT internal.confirmed_species_review_is_valid(review) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','invalid','rank',NULL,
            'scientific_name',NULL,'common_name',NULL,'primary',NULL,
            'species_id',NULL,'verified',FALSE,'pending_review',FALSE);
    END IF;
    IF candidate.confirmed_species_identity IS NOT NULL AND candidate.is_biological_subject IS TRUE THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('source','verified_selection','rank','species',
            'scientific_name',candidate.confirmed_species_identity -> 'scientific_name',
            'common_name',candidate.confirmed_species_identity -> 'common_name',
            'primary',primary_answer,'species_id',candidate.confirmed_species_identity -> 'species_id',
            'verified',TRUE,'pending_review',FALSE);
    END IF;
    RETURN pg_catalog.JSONB_BUILD_OBJECT('source','ai_primary','rank',primary_answer -> 'resolution',
        'scientific_name',primary_answer -> 'scientific_name','common_name',primary_answer -> 'common_name',
        'primary',primary_answer,'species_id',CASE WHEN primary_answer ->> 'resolution' = 'species'
            AND candidate.user_review_state <> 'user_overridden' THEN candidate.species_id ELSE NULL END,
        'verified',FALSE,'pending_review',candidate.user_review_state <> 'unreviewed');
END;
$$;
REVOKE ALL ON FUNCTION internal.scan_effective_identification(public.scans) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.scan_effective_identification(public.scans) TO service_role;

CREATE OR REPLACE FUNCTION internal.scan_effective_species_id(candidate public.scans)
RETURNS UUID LANGUAGE SQL STABLE PARALLEL SAFE SECURITY INVOKER SET search_path = ''
AS $$ SELECT (internal.scan_effective_identification(candidate) ->> 'species_id')::UUID; $$;
REVOKE ALL ON FUNCTION internal.scan_effective_species_id(public.scans) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.scan_effective_species_id(public.scans) TO service_role;


-- Sharing admits a biological observation, not necessarily a resolved species.
CREATE OR REPLACE FUNCTION internal.scan_identification_is_shareable(candidate public.scans)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE identity JSONB := internal.scan_effective_identification(candidate); scientific_name TEXT;
BEGIN
    IF candidate.is_biological_subject IS FALSE OR identity ->> 'source' = 'invalid'
        OR identity ->> 'rank' = 'non_biological' THEN RETURN FALSE; END IF;
    IF identity ->> 'source' = 'legacy' THEN
        SELECT species.scientific_name INTO scientific_name FROM public.species_dictionary AS species
        WHERE species.id = (identity ->> 'species_id')::UUID;
        IF pg_catalog.LOWER(pg_catalog.BTRIM(COALESCE(scientific_name,''))) IN
            ('','unknown','unknown subject','taxonomy unavailable','unidentified wildlife','no wildlife detected','not applicable','n/a','inanimate object') THEN RETURN FALSE; END IF;
    ELSE scientific_name := identity ->> 'scientific_name'; END IF;
    RETURN NOT EXISTS (SELECT 1 FROM pg_catalog.UNNEST(ARRAY[scientific_name,identity ->> 'common_name',candidate.user_identification_override]) AS name
        WHERE pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(COALESCE(name,''),'\s+',' ','g')))
          IN ('human','humans','human being','person','homo sapiens','homo sapien'));
END;
$$;
REVOKE ALL ON FUNCTION internal.scan_identification_is_shareable(public.scans) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION internal.scan_identification_is_shareable(public.scans) TO service_role;

-- A community display outcome cannot assert independent verified species identity.
CREATE OR REPLACE FUNCTION internal.explore_effective_species_id(candidate public.scans, target_post_id UUID)
RETURNS UUID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE effective_id UUID := internal.scan_effective_species_id(candidate); community RECORD;
BEGIN
    SELECT projection.projection_state, taxon.rank, taxon.species_id INTO community
    FROM public.explore_observation_projection AS projection
    LEFT JOIN public.taxon_nodes AS taxon ON taxon.id = projection.public_taxon_node_id
    WHERE projection.post_id = target_post_id;
    IF FOUND AND community.projection_state = 'community_resolved' THEN
        IF candidate.primary_identification IS NULL
            AND candidate.identification_provenance ->> 'schema' IS DISTINCT FROM 'merian_identify_primary_v1' THEN
            RETURN CASE WHEN pg_catalog.LOWER(community.rank::TEXT) = 'species' THEN community.species_id ELSE NULL END;
        END IF;
        IF pg_catalog.LOWER(community.rank::TEXT) IS DISTINCT FROM 'species'
            OR community.species_id IS DISTINCT FROM effective_id THEN RETURN NULL; END IF;
    END IF;
    RETURN effective_id;
END;
$$;
REVOKE ALL ON FUNCTION internal.explore_effective_species_id(public.scans,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION internal.explore_effective_species_id(public.scans,UUID) TO service_role;

-- Allowlisted public labels/ranks only. No score, review revision, raw review,
-- provider settings, private scan context or community taxon authority is exposed.
CREATE OR REPLACE FUNCTION internal.explore_identification_labels(candidate public.scans, target_post_id UUID)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE identity JSONB := internal.scan_effective_identification(candidate); community RECORD;
    label_source TEXT := identity ->> 'source'; rank TEXT := identity ->> 'rank';
BEGIN
    IF label_source = 'invalid' THEN RETURN NULL; END IF;
    SELECT projection.projection_state, taxon.rank INTO community
    FROM public.explore_observation_projection AS projection
    LEFT JOIN public.taxon_nodes AS taxon ON taxon.id = projection.public_taxon_node_id
    WHERE projection.post_id = target_post_id;
    IF FOUND AND community.projection_state = 'community_resolved' THEN
        label_source := 'community'; rank := pg_catalog.LOWER(community.rank::TEXT);
        IF rank NOT IN ('species','genus','family') OR rank IS NULL THEN rank := 'unresolved_biological'; END IF;
    ELSIF label_source = 'legacy' THEN RETURN NULL; END IF;
    RETURN pg_catalog.JSONB_BUILD_OBJECT('version',1,'rank',rank,'label_source',label_source,
        'original_rank',identity #> '{primary,resolution}',
        'original_scientific_name',identity #> '{primary,scientific_name}',
        'original_common_name',identity #> '{primary,common_name}');
END;
$$;
REVOKE ALL ON FUNCTION internal.explore_identification_labels(public.scans,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION internal.explore_identification_labels(public.scans,UUID) TO service_role;
DROP FUNCTION public.explore_projected_post_cards(uuid);
CREATE OR REPLACE FUNCTION public.explore_projected_post_cards(viewer_id uuid)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, public_latitude double precision, public_longitude double precision, coordinate_visibility text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, media_items jsonb, identification jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        public.explore_post_hero_image_url(ep.id) AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        users.public_author_name AS author_name,
        users.public_avatar_url AS author_avatar_url,
        CASE WHEN identity.value ->> 'source' = 'legacy' OR projection.projection_state = 'community_resolved' THEN public.explore_post_community_common_name(
            CASE
                WHEN projection.projection_state = 'community_resolved'
                    THEN 'resolved'
                ELSE NULL
            END,
            community_taxon.common_name,
            community_taxon.scientific_name,
            ep.species_common_name,
            species.common_names,
            species.scientific_name
        )
            ELSE COALESCE(identity.value ->> 'common_name',species.common_names ->> 'en',identity.value ->> 'scientific_name','Unidentified organism') END AS species_common_name,
        CASE WHEN identity.value ->> 'source' = 'legacy' OR projection.projection_state = 'community_resolved' THEN public.explore_post_community_scientific_name(CASE
                WHEN projection.projection_state = 'community_resolved'
                    THEN 'resolved'
                ELSE NULL
            END,
            community_taxon.scientific_name,
            species.scientific_name
        )
            ELSE COALESCE(identity.value ->> 'scientific_name','') END AS species_scientific_name,
        CASE WHEN identity.value ->> 'source' = 'verified_selection' THEN NULL ELSE scans.pet_identification END AS pet_identification,
        ep.public_location_label,
        ep.location_sharing,
        ep.public_latitude,
        ep.public_longitude,
        ep.public_coordinate_visibility AS coordinate_visibility,
        scans.time_of_day,
        scans.current_month,
        scans.weather_condition,
        scans.weather_temperature_f,
        ep.like_count,
        ep.comment_count,
        EXISTS (
            SELECT 1
            FROM public.explore_post_likes AS likes
            WHERE likes.post_id = ep.id
              AND likes.user_id = viewer_id
        ) AS viewer_has_liked,
        (ep.user_id = viewer_id) AS is_owned_by_viewer,
        public.explore_post_media_items(ep.id) AS media_items,
        CASE WHEN identity.value ->> 'source' = 'invalid' THEN NULL
            WHEN projection.projection_state = 'community_resolved' THEN
                pg_catalog.JSONB_BUILD_OBJECT('version',1,
                    'rank',CASE WHEN pg_catalog.LOWER(community_taxon.rank::TEXT) IN ('species','genus','family')
                        THEN pg_catalog.LOWER(community_taxon.rank::TEXT) ELSE 'unresolved_biological' END,
                    'label_source','community',
                    'original_rank',identity.value #> '{primary,resolution}',
                    'original_scientific_name',identity.value #> '{primary,scientific_name}',
                    'original_common_name',identity.value #> '{primary,common_name}')
            WHEN identity.value ->> 'source' = 'legacy' THEN NULL
            ELSE pg_catalog.JSONB_BUILD_OBJECT('version',1,
                'rank',identity.value -> 'rank','label_source',identity.value -> 'source',
                'original_rank',identity.value #> '{primary,resolution}',
                'original_scientific_name',identity.value #> '{primary,scientific_name}',
                'original_common_name',identity.value #> '{primary,common_name}')
        END AS identification
    FROM public.explore_posts AS ep
    JOIN public.scans AS scans
      ON scans.id = ep.scan_id
    -- This invoker reads persisted rows under the caller's existing RLS. Their
    -- validated primary/provenance/subject/review CHECKs own shape validation;
    -- no caller-supplied row or private-schema execution privilege is accepted.
    CROSS JOIN LATERAL (
        SELECT CASE
            WHEN scans.primary_identification IS NULL
                AND scans.identification_provenance ->> 'schema' IS DISTINCT FROM 'merian_identify_primary_v1'
                THEN 'legacy'
            WHEN scans.primary_identification IS NULL
                OR scans.identification_provenance ->> 'schema' IS DISTINCT FROM 'merian_identify_primary_v1'
                OR scans.primary_identification ->> 'resolution' IS NULL THEN 'invalid'
            WHEN scans.confirmed_species_identity IS NOT NULL AND scans.is_biological_subject IS TRUE THEN
                CASE WHEN scans.confirmed_species_identity_revision > 0
                    AND scans.confirmed_species_id::TEXT = scans.confirmed_species_identity ->> 'species_id'
                    THEN 'verified_selection' ELSE 'invalid' END
            ELSE 'ai_primary'
        END AS source
    ) AS identity_source
    CROSS JOIN LATERAL (
        SELECT CASE identity_source.source
            WHEN 'legacy' THEN pg_catalog.JSONB_BUILD_OBJECT('source','legacy','primary',NULL,
                'rank',NULL,'scientific_name',NULL,'common_name',NULL,
                'species_id',COALESCE(scans.confirmed_species_id,scans.species_id))
            WHEN 'invalid' THEN pg_catalog.JSONB_BUILD_OBJECT('source','invalid')
            WHEN 'verified_selection' THEN pg_catalog.JSONB_BUILD_OBJECT('source','verified_selection',
                'primary',scans.primary_identification,'rank','species',
                'scientific_name',scans.confirmed_species_identity -> 'scientific_name',
                'common_name',scans.confirmed_species_identity -> 'common_name',
                'species_id',scans.confirmed_species_identity -> 'species_id')
            ELSE pg_catalog.JSONB_BUILD_OBJECT('source','ai_primary','primary',scans.primary_identification,
                'rank',scans.primary_identification -> 'resolution',
                'scientific_name',scans.primary_identification -> 'scientific_name',
                'common_name',scans.primary_identification -> 'common_name',
                'species_id',CASE WHEN scans.primary_identification ->> 'resolution' = 'species'
                    AND scans.user_review_state <> 'user_overridden' THEN scans.species_id ELSE NULL END)
        END AS value
    ) AS identity
    JOIN public.users AS users
      ON users.id = ep.user_id
    LEFT JOIN public.explore_observation_projection AS projection
      ON projection.post_id = ep.id
    LEFT JOIN public.taxon_nodes AS community_taxon
      ON community_taxon.id = projection.public_taxon_node_id
    LEFT JOIN public.species_dictionary AS species
      ON species.id = CASE WHEN projection.projection_state = 'community_resolved' THEN
            CASE WHEN pg_catalog.LOWER(community_taxon.rank::TEXT) = 'species'
                AND (identity.value ->> 'source' = 'legacy'
                    OR community_taxon.species_id = (identity.value ->> 'species_id')::UUID)
                THEN community_taxon.species_id ELSE NULL END
            ELSE (identity.value ->> 'species_id')::UUID END
    LEFT JOIN public.species_dictionary AS legacy_species
      ON identity.value ->> 'source' = 'legacy'
        AND legacy_species.id = (identity.value ->> 'species_id')::UUID
    WHERE ep.unshared_at IS NULL AND NOT public.viewer_has_reported_explore_post(viewer_id, ep.id)
      AND ep.moderated_at IS NULL
      AND ep.media_health_status <> 'quarantined'
      AND (
          COALESCE(
              projection.projection_state::TEXT,
              'normal'
          ) IN ('normal', 'withdrawn')
          OR (
              projection.projection_state = 'community_resolved'
              AND EXISTS (
                  SELECT 1
                  FROM public.explore_community_requests AS requests
                  WHERE requests.id = projection.community_request_id
                    AND requests.status = 'resolved'
                    AND requests.explore_published_at IS NOT NULL
              )
          )
      )
      AND scans.is_tombstoned = FALSE
      AND EXISTS (
          SELECT 1
          FROM public.explore_post_media AS media
          WHERE media.post_id = ep.id
            AND media.health_status <> 'missing'
      )
      AND scans.is_biological_subject IS DISTINCT FROM FALSE
      AND identity.value ->> 'source' <> 'invalid'
      AND identity.value ->> 'rank' IS DISTINCT FROM 'non_biological'
      AND (identity.value ->> 'source' <> 'legacy'
          OR pg_catalog.LOWER(pg_catalog.BTRIM(COALESCE(legacy_species.scientific_name,''))) NOT IN
            ('','unknown','unknown subject','taxonomy unavailable','unidentified wildlife','no wildlife detected','not applicable','n/a','inanimate object'))
      AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.UNNEST(ARRAY[
              CASE WHEN identity.value ->> 'source' = 'legacy' THEN legacy_species.scientific_name
                  ELSE identity.value ->> 'scientific_name' END,
              identity.value ->> 'common_name',scans.user_identification_override]) AS name
          WHERE pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(COALESCE(name,''),'\s+',' ','g')))
              IN ('human','humans','human being','person','homo sapiens','homo sapien')
      )
      AND users.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks AS blocks
          WHERE (
              blocks.blocker_id = viewer_id
              AND blocks.blocked_id = ep.user_id
          ) OR (
              blocks.blocker_id = ep.user_id
              AND blocks.blocked_id = viewer_id
          )
      );
$function$;
GRANT EXECUTE ON FUNCTION public.explore_projected_post_cards(uuid) TO PUBLIC;


DROP FUNCTION public.get_explore_feed(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_explore_feed(self_id uuid, max_limit integer DEFAULT 20, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid, requested_species_categories text[] DEFAULT '{}'::text[], requested_media_types text[] DEFAULT '{}'::text[], shared_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, reference_thumbnail_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, media_items jsonb, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.viewer_species_first_reference_image_url(self_id,
            internal.explore_effective_species_id(scan, cards.post_id),
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
        cards.media_items,
        cards.identification
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
    WHERE (shared_since IS NULL OR cards.shared_at >= shared_since)
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
                AND filtered_media.health_status <> 'missing'
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
$function$;
REVOKE ALL ON FUNCTION public.get_explore_feed(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_feed(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) TO service_role;
COMMENT ON FUNCTION public.get_explore_feed(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) IS 'Returns the recent Explore feed with server-side species, media, and shared-date filters.';


DROP FUNCTION public.get_explore_feed_following(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_explore_feed_following(self_id uuid, max_limit integer DEFAULT 20, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid, requested_species_categories text[] DEFAULT '{}'::text[], requested_media_types text[] DEFAULT '{}'::text[], shared_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
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
        NULL::INTEGER AS ranking_value,
        cards.identification
    FROM public.user_follows follows
    JOIN public.explore_projected_post_cards(self_id) cards
        ON cards.author_user_id = follows.followee_user_id
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
    WHERE follows.follower_user_id = self_id
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
                AND filtered_media.health_status <> 'missing'
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
$function$;
REVOKE ALL ON FUNCTION public.get_explore_feed_following(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_following(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) TO service_role;
COMMENT ON FUNCTION public.get_explore_feed_following(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) IS 'Returns followed-author Explore posts with server-side advanced filters.';


DROP FUNCTION public.get_explore_feed_liked(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_explore_feed_liked(self_id uuid, max_limit integer DEFAULT 20, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid, requested_species_categories text[] DEFAULT '{}'::text[], requested_media_types text[] DEFAULT '{}'::text[], shared_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, reference_thumbnail_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, media_items jsonb, identification jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.viewer_species_first_reference_image_url(self_id,
            internal.explore_effective_species_id(scan, cards.post_id),
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
        cards.media_items,
        cards.identification
    FROM public.explore_post_likes likes
    JOIN public.explore_projected_post_cards(self_id) cards
        ON cards.post_id = likes.post_id
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
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
$function$;
REVOKE ALL ON FUNCTION public.get_explore_feed_liked(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_liked(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) TO service_role;
COMMENT ON FUNCTION public.get_explore_feed_liked(uuid,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) IS 'Service-only viewer liked observations, ordered by date shared with advanced filters before pagination.';


DROP FUNCTION public.get_explore_feed_nearby(uuid,double precision,double precision,integer,timestamp with time zone,uuid,double precision,text[],text[],timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_explore_feed_nearby(self_id uuid, viewer_latitude double precision, viewer_longitude double precision, max_limit integer DEFAULT 20, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid, nearby_radius_miles double precision DEFAULT 50, requested_species_categories text[] DEFAULT '{}'::text[], requested_media_types text[] DEFAULT '{}'::text[], shared_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    WITH search_window AS (
        SELECT
            LEAST(GREATEST(COALESCE(nearby_radius_miles, 50), 1), 100)
                * 1609.344 AS radius_meters
    ),
    search_bounds AS (
        SELECT
            search_window.radius_meters,
            search_window.radius_meters / 111320.0 AS latitude_delta,
            search_window.radius_meters
                / GREATEST(
                    ABS(COS(RADIANS(viewer_latitude))) * 111320.0,
                    1000.0
                ) AS longitude_delta
        FROM search_window
    ),
    bounded_posts AS (
        SELECT
            cards.*,
            search_bounds.radius_meters,
            public.haversine_distance_meters(
                cards.public_latitude,
                cards.public_longitude,
                viewer_latitude,
                viewer_longitude
            ) AS distance_meters
        FROM public.explore_projected_post_cards(self_id) cards
        JOIN public.scans scan
            ON scan.id = cards.scan_id
        LEFT JOIN public.species_dictionary species
            ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
        CROSS JOIN search_bounds
        WHERE (shared_since IS NULL OR cards.shared_at >= shared_since)
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
                    AND filtered_media.health_status <> 'missing'
AND filtered_media.kind = ANY(requested_media_types)
              )
          )
          AND (
              cards.author_user_id = self_id
              OR (
                  cards.location_sharing = 'open'
                  AND cards.public_latitude IS NOT NULL
                  AND cards.public_longitude IS NOT NULL
                  AND cards.public_latitude BETWEEN
                      viewer_latitude - search_bounds.latitude_delta
                      AND viewer_latitude + search_bounds.latitude_delta
                  AND (
                      (
                          viewer_longitude - search_bounds.longitude_delta >= -180
                          AND viewer_longitude + search_bounds.longitude_delta <= 180
                          AND cards.public_longitude BETWEEN
                              viewer_longitude - search_bounds.longitude_delta
                              AND viewer_longitude + search_bounds.longitude_delta
                      )
                      OR (
                          viewer_longitude - search_bounds.longitude_delta < -180
                          AND (
                              cards.public_longitude >=
                                  viewer_longitude - search_bounds.longitude_delta + 360
                              OR cards.public_longitude <=
                                  viewer_longitude + search_bounds.longitude_delta
                          )
                      )
                      OR (
                          viewer_longitude + search_bounds.longitude_delta > 180
                          AND (
                              cards.public_longitude >=
                                  viewer_longitude - search_bounds.longitude_delta
                              OR cards.public_longitude <=
                                  viewer_longitude + search_bounds.longitude_delta - 360
                          )
                      )
                  )
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
        NULL::INTEGER AS ranking_value,
        bounded_posts.identification
    FROM bounded_posts
    WHERE (
        bounded_posts.distance_meters <= bounded_posts.radius_meters
        OR bounded_posts.author_user_id = self_id
    )
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR bounded_posts.shared_at < before_shared_at
          OR (
              bounded_posts.shared_at = before_shared_at
              AND bounded_posts.post_id < before_post_id
          )
      )
    ORDER BY bounded_posts.shared_at DESC, bounded_posts.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$function$;
REVOKE ALL ON FUNCTION public.get_explore_feed_nearby(uuid,double precision,double precision,integer,timestamp with time zone,uuid,double precision,text[],text[],timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_nearby(uuid,double precision,double precision,integer,timestamp with time zone,uuid,double precision,text[],text[],timestamp with time zone) TO service_role;
COMMENT ON FUNCTION public.get_explore_feed_nearby(uuid,double precision,double precision,integer,timestamp with time zone,uuid,double precision,text[],text[],timestamp with time zone) IS 'Returns radius-bounded Explore posts with server-side advanced filters and cursor pagination.';


DROP FUNCTION public.get_explore_feed_trending(uuid,integer,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_explore_feed_trending(self_id uuid, max_limit integer DEFAULT 20, before_ranking_value integer DEFAULT NULL::integer, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid, requested_species_categories text[] DEFAULT '{}'::text[], requested_media_types text[] DEFAULT '{}'::text[], shared_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    WITH recent_likes AS (
        SELECT likes.post_id, COUNT(*)::INTEGER AS ranking_value
        FROM public.explore_post_likes likes
        WHERE likes.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY likes.post_id
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
        COALESCE(recent_likes.ranking_value, 0) AS ranking_value,
        cards.identification
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
    LEFT JOIN recent_likes
        ON recent_likes.post_id = cards.post_id
    WHERE (shared_since IS NULL OR cards.shared_at >= shared_since)
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
                AND filtered_media.health_status <> 'missing'
AND filtered_media.kind = ANY(requested_media_types)
          )
      )
      AND (
          before_ranking_value IS NULL
          OR before_shared_at IS NULL
          OR before_post_id IS NULL
          OR COALESCE(recent_likes.ranking_value, 0) < before_ranking_value
          OR (
              COALESCE(recent_likes.ranking_value, 0) = before_ranking_value
              AND cards.shared_at < before_shared_at
          )
          OR (
              COALESCE(recent_likes.ranking_value, 0) = before_ranking_value
              AND cards.shared_at = before_shared_at
              AND cards.post_id < before_post_id
          )
      )
    ORDER BY
        COALESCE(recent_likes.ranking_value, 0) DESC,
        cards.shared_at DESC,
        cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$function$;
REVOKE ALL ON FUNCTION public.get_explore_feed_trending(uuid,integer,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_trending(uuid,integer,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) TO service_role;
COMMENT ON FUNCTION public.get_explore_feed_trending(uuid,integer,integer,timestamp with time zone,uuid,text[],text[],timestamp with time zone) IS 'Returns ranked Explore posts with filters applied before ranking pagination.';


DROP FUNCTION public.get_explore_author_posts(uuid,uuid,integer,timestamp with time zone,uuid);
CREATE OR REPLACE FUNCTION public.get_explore_author_posts(self_id uuid, target_author_user_id uuid, max_limit integer DEFAULT 30, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, reference_thumbnail_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, media_items jsonb, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.viewer_species_first_reference_image_url(self_id,
            internal.explore_effective_species_id(scan, cards.post_id),
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
        cards.media_items,
        cards.identification
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.explore_effective_species_id(scan, cards.post_id)
    WHERE cards.author_user_id = target_author_user_id
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 30), 0);
$function$;
REVOKE ALL ON FUNCTION public.get_explore_author_posts(uuid,uuid,integer,timestamp with time zone,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_author_posts(uuid,uuid,integer,timestamp with time zone,uuid) TO service_role;


DROP FUNCTION public.get_explore_post(uuid,uuid);
CREATE OR REPLACE FUNCTION public.get_explore_post(self_id uuid, target_post_id uuid)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, media_items jsonb, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
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
        cards.media_items,
        cards.identification
    FROM public.explore_projected_post_cards(self_id) cards
    WHERE cards.post_id = target_post_id
    LIMIT 1;
$function$;
GRANT EXECUTE ON FUNCTION public.get_explore_post(uuid,uuid) TO PUBLIC;
COMMENT ON FUNCTION public.get_explore_post(uuid,uuid) IS 'Returns one privacy-safe public Explore post, including its canonical ordered media snapshot for web and app detail playback.';


DROP FUNCTION public.get_explore_hashtag_posts(uuid,text,integer,timestamp with time zone,uuid);
CREATE OR REPLACE FUNCTION public.get_explore_hashtag_posts(self_id uuid, target_tag text, max_limit integer DEFAULT 30, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
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
        NULL::INTEGER AS ranking_value,
        cards.identification
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
$function$;
GRANT EXECUTE ON FUNCTION public.get_explore_hashtag_posts(uuid,text,integer,timestamp with time zone,uuid) TO PUBLIC;


DROP FUNCTION public.get_explore_map_posts(uuid,double precision,double precision,double precision,double precision,integer);
CREATE OR REPLACE FUNCTION public.get_explore_map_posts(self_id uuid, north_latitude double precision, south_latitude double precision, east_longitude double precision, west_longitude double precision, max_limit integer DEFAULT 500)
 RETURNS TABLE(post_id uuid, scan_id uuid, latitude double precision, longitude double precision, coordinate_visibility text, hero_image_url text, reference_thumbnail_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, taxonomy_kingdom text, taxonomy_class text, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, identification jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.public_latitude AS latitude,
        cards.public_longitude AS longitude,
        cards.coordinate_visibility,
        COALESCE(
            NULLIF(BTRIM(cards.hero_image_url), ''),
            public.viewer_species_first_reference_image_url(self_id,
                internal.explore_effective_species_id(map_scan, cards.post_id),
                sd.reference_image_url
            ),
            ''
        ) AS hero_image_url,
        public.viewer_species_first_reference_image_url(self_id,
            internal.explore_effective_species_id(map_scan, cards.post_id),
            sd.reference_image_url
        ) AS reference_thumbnail_url,
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
        cards.is_owned_by_viewer,
        cards.identification
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans map_scan
        ON map_scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = internal.explore_effective_species_id(map_scan, cards.post_id)
    WHERE cards.location_sharing = 'open'
      AND cards.public_latitude IS NOT NULL
      AND cards.public_longitude IS NOT NULL
      AND cards.public_latitude BETWEEN LEAST(north_latitude, south_latitude)
          AND GREATEST(north_latitude, south_latitude)
      AND (
          (
              west_longitude <= east_longitude
              AND cards.public_longitude BETWEEN west_longitude AND east_longitude
          )
          OR (
              west_longitude > east_longitude
              AND (
                  cards.public_longitude >= west_longitude
                  OR cards.public_longitude <= east_longitude
              )
          )
      )
    ORDER BY cards.shared_at DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 500), 0), 500);
$function$;
REVOKE ALL ON FUNCTION public.get_explore_map_posts(uuid,double precision,double precision,double precision,double precision,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_map_posts(uuid,double precision,double precision,double precision,double precision,integer) TO service_role;


DROP FUNCTION public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamp with time zone,uuid);
CREATE OR REPLACE FUNCTION public.get_explore_species_posts(self_id uuid, target_species_id uuid, max_limit integer DEFAULT 30, before_image_quality_score smallint DEFAULT NULL::smallint, before_shared_at timestamp with time zone DEFAULT NULL::timestamp with time zone, before_post_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(post_id uuid, scan_id uuid, hero_image_url text, reference_thumbnail_url text, shared_at timestamp with time zone, author_user_id uuid, author_name text, author_avatar_url text, species_common_name text, species_scientific_name text, pet_identification jsonb, public_location_label text, location_sharing text, time_of_day text, current_month integer, weather_condition text, weather_temperature_f double precision, like_count integer, comment_count integer, viewer_has_liked boolean, is_owned_by_viewer boolean, ranking_value integer, media_items jsonb, image_quality_score smallint, identification jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.viewer_species_first_reference_image_url(self_id,
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
        scan.image_quality_score,
        cards.identification
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
        internal.explore_effective_species_id(scan,cards.post_id)
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
$function$;
REVOKE ALL ON FUNCTION public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamp with time zone,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamp with time zone,uuid) TO service_role;
COMMENT ON FUNCTION public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamp with time zone,uuid) IS 'Returns visibility-safe Explore cards for an exact effective species, ranked by image quality with stable cursor pagination.';


DROP FUNCTION public.get_public_web_explore_posts(uuid,integer);
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
    WHERE (
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
REVOKE ALL ON FUNCTION public.get_public_web_explore_posts(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_posts(uuid,integer) TO service_role;
COMMENT ON FUNCTION public.get_public_web_explore_posts(uuid,integer) IS 'Service-only public-web projection with a fixed anonymous viewer. Returns privacy-filtered post cards without engagement or ownership state.';


CREATE OR REPLACE FUNCTION public.get_explore_post_detail(self_id uuid, target_post_id uuid)
 RETURNS TABLE(post_id uuid, field_notes text, location_sharing text, hashtags text[], species_dictionary_id uuid, alternative_common_names text[], pet_identification jsonb, taxonomy_kingdom text, taxonomy_phylum text, taxonomy_class text, taxonomy_order text, taxonomy_family text, taxonomy_genus text, ai_reasoning text, habitat_description text, gbif_taxon_key integer, iucn_red_list_status text, hazard_type text, wikipedia_url text, reference_image_url text, wikipedia_overview text, similar_species jsonb, map_point jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT
        post.id AS post_id,
        NULLIF(BTRIM(COALESCE(post.field_notes, '')), '') AS field_notes,
        post.location_sharing,
        ARRAY(
            SELECT hashtag.tag
            FROM public.explore_post_hashtags AS hashtag
            WHERE hashtag.post_id = post.id
            ORDER BY hashtag.tag
        ) AS hashtags,
        species.id AS species_dictionary_id,
        ARRAY(
            SELECT NULLIF(BTRIM(names.raw_name), '')
            FROM UNNEST(
                COALESCE(
                    species.alternative_common_names,
                    ARRAY[]::TEXT[]
                )
            ) WITH ORDINALITY AS names(raw_name, ordinality)
            WHERE NULLIF(BTRIM(names.raw_name), '') IS NOT NULL
            ORDER BY names.ordinality
        ) AS alternative_common_names,
        CASE WHEN internal.scan_effective_identification(scan) ->> 'source' = 'verified_selection' THEN NULL ELSE scan.pet_identification END AS pet_identification,
        species.kingdom AS taxonomy_kingdom,
        species.phylum AS taxonomy_phylum,
        species."class" AS taxonomy_class,
        species."order" AS taxonomy_order,
        species.family AS taxonomy_family,
        species.genus AS taxonomy_genus,
        CASE
            WHEN COALESCE(
                scan.user_review_state,
                'unreviewed'::public.user_review_state
            ) <> 'user_overridden'::public.user_review_state
             AND scan.user_identification_override IS NULL
             AND NULLIF(BTRIM(COALESCE(scan.ai_reasoning, '')), '') IS NOT NULL
                THEN scan.ai_reasoning
            ELSE NULL
        END AS ai_reasoning,
        species.habitat_description,
        species.gbif_taxon_key,
        species.iucn_red_list_status,
        COALESCE(NULLIF(BTRIM(species.hazard_type), ''), 'none')
            AS hazard_type,
        species.wikipedia_url,
        public.viewer_species_reference_image_urls_excluding_media(self_id,
            species.id,
            species.reference_image_url,
            scan.image_storage_urls
        ) AS reference_image_url,
        species.wikipedia_overview,
        public.viewer_species_similar_species(self_id, species.id) AS similar_species,
        CASE
            WHEN post.location_sharing = 'open'
             AND post.public_latitude BETWEEN -90 AND 90
             AND post.public_longitude BETWEEN -180 AND 180
             AND post.public_coordinate_visibility IN ('exact', 'obscured')
                THEN pg_catalog.JSONB_BUILD_OBJECT(
                    'latitude', post.public_latitude,
                    'longitude', post.public_longitude,
                    'coordinate_visibility',
                    post.public_coordinate_visibility
                )
            ELSE NULL
        END AS map_point
    FROM public.explore_posts AS post
    INNER JOIN public.scans AS scan
        ON scan.id = post.scan_id
    INNER JOIN public.users AS author
        ON author.id = post.user_id
    LEFT JOIN public.species_dictionary AS species
        ON species.id = internal.explore_effective_species_id(scan, post.id)
    WHERE post.id = target_post_id
      AND post.unshared_at IS NULL
      AND post.moderated_at IS NULL
      AND post.media_health_status <> 'quarantined'
      AND scan.is_tombstoned = FALSE
      AND internal.scan_identification_is_shareable(scan)
      AND author.is_shadowbanned = FALSE
      AND EXISTS (
          SELECT 1
          FROM public.explore_projected_post_cards(self_id) AS visible_post
          WHERE visible_post.post_id = post.id
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks AS blocks
          WHERE (
              blocks.blocker_id = self_id
              AND blocks.blocked_id = post.user_id
          ) OR (
              blocks.blocker_id = post.user_id
              AND blocks.blocked_id = self_id
          )
      )
    LIMIT 1;
$function$;


CREATE OR REPLACE FUNCTION public.publish_scan_to_explore_atomically(p_scan_id uuid, p_user_id uuid, p_species_common_name text, p_field_notes text, p_location_sharing text, p_media_rows jsonb, p_hashtags text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_audio_urls TEXT[];
    v_community_request_status public.explore_community_request_status;
    v_distinct_hashtag_count INTEGER;
    v_distinct_order_count INTEGER;
    v_hashtags TEXT[] := COALESCE(p_hashtags, ARRAY[]::TEXT[]);
    v_image_urls TEXT[];
    v_location_sharing TEXT;
    v_media_count INTEGER;
    v_media_item JSONB;
    v_media_kind TEXT;
    v_media_order NUMERIC;
    v_media_thumbnail_url TEXT;
    v_media_url TEXT;
    v_post_id UUID;
    v_shared_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    v_scan_geoprivacy TEXT;
    v_video_urls TEXT[];
BEGIN
    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Scan and owner are required'
            USING ERRCODE = '22023';
    END IF;

    IF p_species_common_name IS NOT NULL
       AND (
           pg_catalog.BTRIM(p_species_common_name) = ''
           OR pg_catalog.CHAR_LENGTH(p_species_common_name) > 200
       ) THEN
        RAISE EXCEPTION 'Invalid Explore species common name'
            USING ERRCODE = '22023';
    END IF;

    IF p_field_notes IS NOT NULL
       AND (
           pg_catalog.BTRIM(p_field_notes) = ''
           OR pg_catalog.CHAR_LENGTH(p_field_notes) > 1000
       ) THEN
        RAISE EXCEPTION 'Invalid Explore field notes'
            USING ERRCODE = '22023';
    END IF;

    IF p_location_sharing IS NOT NULL
       AND p_location_sharing NOT IN ('open', 'obscured', 'private') THEN
        RAISE EXCEPTION 'Invalid Explore location sharing'
            USING ERRCODE = '22023';
    END IF;

    IF p_media_rows IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_media_rows) <> 'array' THEN
        RAISE EXCEPTION 'Explore media must be an array'
            USING ERRCODE = '22023';
    END IF;

    v_media_count := pg_catalog.JSONB_ARRAY_LENGTH(p_media_rows);
    IF v_media_count < 1 OR v_media_count > 6 THEN
        RAISE EXCEPTION 'Explore media count is outside the supported range'
            USING ERRCODE = '22023';
    END IF;

    IF pg_catalog.CARDINALITY(v_hashtags) > 5 THEN
        RAISE EXCEPTION 'Explore hashtag count is outside the supported range'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.UNNEST(v_hashtags) AS hashtag(tag)
        WHERE hashtag.tag IS NULL
           OR hashtag.tag !~ '^[a-z0-9][a-z0-9_]{1,39}$'
    ) THEN
        RAISE EXCEPTION 'Invalid Explore hashtag'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.COUNT(DISTINCT hashtag.tag)::INTEGER
    INTO v_distinct_hashtag_count
    FROM pg_catalog.UNNEST(v_hashtags) AS hashtag(tag);

    IF v_distinct_hashtag_count <> pg_catalog.CARDINALITY(v_hashtags) THEN
        RAISE EXCEPTION 'Duplicate Explore hashtags are not permitted'
            USING ERRCODE = '22023';
    END IF;

    -- The resolved-community publisher locks this row before updating scans.
    -- Preserve that request -> scan order here so concurrent consensus and
    -- publication work cannot form a scan -> request deadlock cycle. A scan
    -- can have at most one request because explore_posts.scan_id and
    -- explore_community_requests.post_id are both unique.
    SELECT community_request.status
    INTO v_community_request_status
    FROM public.explore_community_requests AS community_request
    WHERE community_request.scan_id = p_scan_id
      AND community_request.requested_by = p_user_id
    FOR UPDATE OF community_request;

    IF v_community_request_status = 'needs_id' THEN
        RAISE EXCEPTION 'Wait for the community to identify this request before sharing it to Explore.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT
        COALESCE(scan.image_storage_urls, ARRAY[]::TEXT[]),
        COALESCE(scan.video_storage_urls, ARRAY[]::TEXT[]),
        COALESCE(scan.audio_storage_urls, ARRAY[]::TEXT[]),
        scan.geoprivacy::TEXT
    INTO
        v_image_urls,
        v_video_urls,
        v_audio_urls,
        v_scan_geoprivacy
    FROM public.scans AS scan
    WHERE scan.id = p_scan_id
      AND scan.user_id = p_user_id
      AND NOT scan.is_tombstoned
      AND internal.scan_identification_is_shareable(scan)
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Owned share-eligible scan not found'
            USING ERRCODE = 'P0001';
    END IF;

    -- Backward-compatible clients may omit a post-owned privacy choice. Resolve
    -- that default from the scan only after taking the owner-row lock so a
    -- concurrent privacy change cannot publish with a stale geoprivacy value.
    v_location_sharing :=
        COALESCE(p_location_sharing, v_scan_geoprivacy);
    IF v_location_sharing NOT IN ('open', 'obscured', 'private') THEN
        RAISE EXCEPTION 'Invalid locked scan geoprivacy'
            USING ERRCODE = '22023';
    END IF;

    FOR v_media_item IN
        SELECT media.item
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_media_rows) AS media(item)
    LOOP
        IF pg_catalog.JSONB_TYPEOF(v_media_item) <> 'object'
           OR NOT (
               v_media_item ?& ARRAY[
                   'kind',
                   'url',
                   'thumbnail_url',
                   'order_index',
                   'duration_seconds',
                   'has_audio'
               ]
           )
           OR (
               v_media_item - ARRAY[
                   'kind',
                   'url',
                   'thumbnail_url',
                   'order_index',
                   'duration_seconds',
                   'has_audio'
               ]
           ) <> '{}'::JSONB THEN
            RAISE EXCEPTION 'Invalid Explore media object shape'
                USING ERRCODE = '22023';
        END IF;

        IF pg_catalog.JSONB_TYPEOF(v_media_item -> 'kind') <> 'string'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'url') <> 'string'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'thumbnail_url') <> 'string'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'order_index') <> 'number'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'duration_seconds')
                NOT IN ('number', 'null')
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'has_audio') <> 'boolean' THEN
            RAISE EXCEPTION 'Invalid Explore media value types'
                USING ERRCODE = '22023';
        END IF;

        v_media_kind := v_media_item ->> 'kind';
        v_media_url := pg_catalog.BTRIM(v_media_item ->> 'url');
        v_media_thumbnail_url :=
            pg_catalog.BTRIM(v_media_item ->> 'thumbnail_url');
        v_media_order := (v_media_item ->> 'order_index')::NUMERIC;

        IF v_media_kind NOT IN ('image', 'video', 'audio')
           OR v_media_url = ''
           OR pg_catalog.CHAR_LENGTH(v_media_url) > 4096
           OR pg_catalog.CHAR_LENGTH(v_media_thumbnail_url) > 4096
           OR v_media_order <> pg_catalog.TRUNC(v_media_order)
           OR v_media_order < 0
           OR v_media_order >= v_media_count
           OR (
               pg_catalog.JSONB_TYPEOF(
                   v_media_item -> 'duration_seconds'
               ) = 'number'
               AND (v_media_item ->> 'duration_seconds')::NUMERIC < 0
           ) THEN
            RAISE EXCEPTION 'Invalid Explore media values'
                USING ERRCODE = '22023';
        END IF;

        IF v_media_kind = 'image'
           AND (
               v_media_thumbnail_url <> v_media_url
               OR NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_image_urls)
                       AS source_image(url)
                   WHERE pg_catalog.BTRIM(source_image.url) = v_media_url
               )
               OR (v_media_item ->> 'has_audio')::BOOLEAN
           ) THEN
            RAISE EXCEPTION 'Explore image does not belong to the scan'
                USING ERRCODE = '22023';
        ELSIF v_media_kind = 'video'
           AND (
               v_media_thumbnail_url = ''
               OR v_media_thumbnail_url = v_media_url
               OR NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_video_urls)
                       AS source_video(url)
                   WHERE pg_catalog.BTRIM(source_video.url) = v_media_url
               )
               OR NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_image_urls)
                       AS source_thumbnail(url)
                   WHERE pg_catalog.BTRIM(source_thumbnail.url) =
                       v_media_thumbnail_url
               )
           ) THEN
            RAISE EXCEPTION 'Explore video does not belong to the scan'
                USING ERRCODE = '22023';
        ELSIF v_media_kind = 'audio'
           AND (
               NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_audio_urls)
                       AS source_audio(url)
                   WHERE pg_catalog.BTRIM(source_audio.url) = v_media_url
               )
               OR NOT (v_media_item ->> 'has_audio')::BOOLEAN
           ) THEN
            RAISE EXCEPTION 'Explore audio does not belong to the scan'
                USING ERRCODE = '22023';
        END IF;
    END LOOP;

    SELECT pg_catalog.COUNT(
        DISTINCT (media.item ->> 'order_index')::INTEGER
    )::INTEGER
    INTO v_distinct_order_count
    FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_media_rows) AS media(item);

    IF v_distinct_order_count <> v_media_count THEN
        RAISE EXCEPTION 'Explore media order must be unique and contiguous'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.explore_posts AS existing (
        scan_id,
        user_id,
        species_common_name,
        field_notes,
        location_sharing,
        shared_at,
        unshared_at
    )
    VALUES (
        p_scan_id,
        p_user_id,
        p_species_common_name,
        p_field_notes,
        v_location_sharing,
        v_shared_at,
        NULL
    )
    ON CONFLICT (scan_id) DO UPDATE
    SET species_common_name = EXCLUDED.species_common_name,
        field_notes = EXCLUDED.field_notes,
        location_sharing = EXCLUDED.location_sharing,
        shared_at = EXCLUDED.shared_at,
        unshared_at = NULL
    WHERE existing.user_id = EXCLUDED.user_id
    RETURNING existing.id, existing.shared_at
    INTO v_post_id, v_shared_at;

    IF v_post_id IS NULL THEN
        RAISE EXCEPTION 'Explore post ownership does not match the scan'
            USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.explore_post_media AS media
    WHERE media.post_id = v_post_id;

    INSERT INTO public.explore_post_media (
        post_id,
        kind,
        url,
        thumbnail_url,
        order_index,
        duration_seconds,
        has_audio
    )
    SELECT
        v_post_id,
        media.kind,
        pg_catalog.BTRIM(media.url),
        pg_catalog.BTRIM(media.thumbnail_url),
        media.order_index,
        media.duration_seconds,
        media.has_audio
    FROM pg_catalog.JSONB_TO_RECORDSET(p_media_rows) AS media(
        kind TEXT,
        url TEXT,
        thumbnail_url TEXT,
        order_index INTEGER,
        duration_seconds DOUBLE PRECISION,
        has_audio BOOLEAN
    );

    DELETE FROM public.explore_post_hashtags AS hashtag
    WHERE hashtag.post_id = v_post_id;

    INSERT INTO public.explore_post_hashtags (
        post_id,
        tag
    )
    SELECT
        v_post_id,
        hashtag.tag
    FROM pg_catalog.UNNEST(v_hashtags) AS hashtag(tag);

    PERFORM public.publish_resolved_community_request_to_explore(
        v_post_id,
        p_user_id
    );

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'post_id', v_post_id,
        'shared_at', v_shared_at,
        'location_sharing', v_location_sharing,
        'publication_status', 'published'
    );
END;
$function$;


CREATE OR REPLACE FUNCTION public.field_trip_scan_evidence_is_eligible(candidate scans)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT candidate.is_biological_subject IS NOT FALSE
        AND candidate.is_tombstoned IS NOT TRUE
        AND pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(
            COALESCE(candidate.user_identification_override, ''), '\s+', ' ', 'g'
        ))) NOT IN ('human', 'humans', 'human being', 'person', 'human breathing', 'human speech', 'human vocalisation', 'human vocalization', 'homo sapiens', 'homo sapien')
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary AS species
            WHERE species.id = COALESCE(candidate.confirmed_species_id, candidate.species_id)
              AND pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(
                  COALESCE(species.scientific_name, ''), '\s+', ' ', 'g'
              ))) NOT IN (
                  '', 'unknown', 'unknown subject', 'taxonomy unavailable',
                  'unidentified wildlife', 'no wildlife detected', 'not applicable',
                  'n/a', 'inanimate object', 'human', 'humans', 'human being',
                  'person', 'human breathing', 'human speech', 'human vocalisation',
                  'human vocalization', 'homo sapiens', 'homo sapien'
              )
        )
        AND (
            (internal.scan_effective_identification(candidate) ->> 'verified')::BOOLEAN
            OR (candidate.primary_identification IS NULL AND (candidate.confirmed_species_id IS NOT NULL OR candidate.user_confirmed_identification IS TRUE))
            OR internal.identification_metrics_are_gemini_compatible(
                candidate.identification_provenance, candidate.inference_tier
            )
        )
        AND public.field_trip_scan_identification_is_eligible(
            candidate.ai_confidence_score,
            candidate.inference_tier,
            CASE WHEN candidate.primary_identification IS NULL THEN candidate.confirmed_species_id
                WHEN (internal.scan_effective_identification(candidate) ->> 'verified')::BOOLEAN THEN internal.scan_effective_species_id(candidate) ELSE NULL END,
            CASE WHEN candidate.primary_identification IS NULL THEN candidate.user_confirmed_identification ELSE FALSE END
        );
$function$;


CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_atomic(self_id uuid, target_scan_id uuid, preferred_user_field_trip_id uuid DEFAULT NULL::uuid, preferred_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    current_scan_revision JSONB;
    existing_receipt public.field_trip_scan_progress_receipts%ROWTYPE;
    has_existing_receipt BOOLEAN := FALSE;
    effective_preferred_user_field_trip_id UUID;
    effective_preferred_item_id UUID;
    previous_achievement JSONB;
    current_achievement JSONB;
    field_trip_updates JSONB;
    challenge_updates JSONB;
    mutation_completed_trip BOOLEAN;
    achievement_newly_unlocked BOOLEAN;
    response JSONB;
BEGIN
    PERFORM internal.require_service_role();

    IF (preferred_user_field_trip_id IS NULL) <> (preferred_item_id IS NULL) THEN
        RAISE EXCEPTION 'preferred Field Trip goal must include both identifiers'
            USING ERRCODE = '22023';
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'species_id', scan.species_id,
        'primary_identification',scan.primary_identification,
        'identification_provenance',scan.identification_provenance,
        'confirmed_species_identity',scan.confirmed_species_identity,
        'confirmed_species_identity_revision',scan.confirmed_species_identity_revision,
        'effective_species_id',internal.scan_effective_species_id(scan),
        'confirmed_species_id', scan.confirmed_species_id,
        'ai_confidence_score', scan.ai_confidence_score,
        'inference_tier', scan.inference_tier,
        'ai_confidence_qualified', internal.identification_metrics_are_gemini_compatible(scan.identification_provenance, scan.inference_tier),
        'user_confirmed_identification', scan.user_confirmed_identification,
        'user_identification_override', scan.user_identification_override,
        'is_biological_subject', scan.is_biological_subject,
        'is_tombstoned', scan.is_tombstoned,
        'timestamp', scan.timestamp
    )
    INTO current_scan_revision
    FROM public.scans AS scan
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN JSONB_BUILD_OBJECT(
            'field_trip_updates', '[]'::JSONB,
            'challenge_updates', '[]'::JSONB,
            'first_field_trip_achievement', NULL,
            'first_field_trip_achievement_newly_unlocked', FALSE
        );
    END IF;

    SELECT receipt.*
    INTO existing_receipt
    FROM public.field_trip_scan_progress_receipts AS receipt
    WHERE receipt.scan_id = target_scan_id
      AND receipt.user_id = self_id
    FOR UPDATE;
    has_existing_receipt := FOUND;

    IF has_existing_receipt
       AND existing_receipt.scan_revision = current_scan_revision
       AND (
           preferred_user_field_trip_id IS NULL
           OR (
               existing_receipt.preferred_user_field_trip_id =
                   preferred_user_field_trip_id
               AND existing_receipt.preferred_item_id = preferred_item_id
           )
       ) THEN
        RETURN existing_receipt.result;
    END IF;

    effective_preferred_user_field_trip_id :=
        preferred_user_field_trip_id;
    effective_preferred_item_id := preferred_item_id;
    IF effective_preferred_user_field_trip_id IS NULL
       AND effective_preferred_item_id IS NULL
       AND has_existing_receipt
       AND existing_receipt.preferred_user_field_trip_id IS NOT NULL
       AND existing_receipt.preferred_item_id IS NOT NULL THEN
        effective_preferred_user_field_trip_id :=
            existing_receipt.preferred_user_field_trip_id;
        effective_preferred_item_id := existing_receipt.preferred_item_id;
    END IF;

    previous_achievement :=
        public.get_first_field_trip_achievement_progress(self_id);

    -- Completed trips are skipped by normal progress allocation. Reopen stale
    -- contributions before applying a different verified species, preserving
    -- the saved goal preference and the pre-mutation achievement snapshot.
    IF current_scan_revision -> 'primary_identification' <> 'null'::JSONB
       AND (
           EXISTS (
               SELECT 1 FROM public.user_field_trip_item_completions completion
               JOIN public.user_field_trips trip ON trip.id = completion.user_field_trip_id
               WHERE completion.scan_id = target_scan_id AND trip.user_id = self_id
                 AND completion.species_id::TEXT IS DISTINCT FROM
                     (current_scan_revision ->> 'effective_species_id')
           ) OR EXISTS (
               SELECT 1 FROM public.field_trip_challenge_item_completions completion
               JOIN public.field_trip_challenge_participants participation
                 ON participation.id = completion.participation_id
               WHERE completion.scan_id = target_scan_id AND participation.user_id = self_id
                 AND completion.species_id::TEXT IS DISTINCT FROM
                     (current_scan_revision ->> 'effective_species_id')
           )
       ) THEN
        PERFORM public.remove_ineligible_field_trip_scan_progress(self_id, target_scan_id);
        PERFORM public.remove_ineligible_field_trip_challenge_scan_progress(self_id, target_scan_id);
    END IF;

    field_trip_updates := public.apply_field_trip_scan_progress_v2(
        self_id,
        target_scan_id,
        effective_preferred_user_field_trip_id,
        effective_preferred_item_id
    );
    challenge_updates := public.apply_field_trip_challenge_scan_progress(
        self_id,
        target_scan_id
    );

    current_achievement :=
        public.get_first_field_trip_achievement_progress(self_id);
    mutation_completed_trip := EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(
            COALESCE(field_trip_updates, '[]'::JSONB)
            || COALESCE(challenge_updates, '[]'::JSONB)
        ) AS update_row(value)
        WHERE COALESCE(
            (update_row.value ->> 'is_complete')::BOOLEAN,
            FALSE
        )
    );
    achievement_newly_unlocked := previous_achievement IS NULL
        AND current_achievement IS NOT NULL
        AND mutation_completed_trip;

    response := JSONB_BUILD_OBJECT(
        'field_trip_updates', COALESCE(field_trip_updates, '[]'::JSONB),
        'challenge_updates', COALESCE(challenge_updates, '[]'::JSONB),
        'first_field_trip_achievement', current_achievement,
        'first_field_trip_achievement_newly_unlocked',
            achievement_newly_unlocked
    );

    INSERT INTO public.field_trip_scan_progress_receipts(
        scan_id,
        user_id,
        scan_revision,
        preferred_user_field_trip_id,
        preferred_item_id,
        result,
        processed_at,
        updated_at
    )
    VALUES (
        target_scan_id,
        self_id,
        current_scan_revision,
        effective_preferred_user_field_trip_id,
        effective_preferred_item_id,
        response,
        NOW(),
        NOW()
    )
    ON CONFLICT(scan_id) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        scan_revision = EXCLUDED.scan_revision,
        preferred_user_field_trip_id =
            EXCLUDED.preferred_user_field_trip_id,
        preferred_item_id = EXCLUDED.preferred_item_id,
        result = EXCLUDED.result,
        processed_at = NOW(),
        updated_at = NOW();

    RETURN response;
END;
$function$;


CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress_unchecked(self_id uuid, target_scan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    scan_row RECORD;
    participation_row RECORD;
    existing_row RECORD;
    winner_row RECORD;
    state_row RECORD;
    has_existing BOOLEAN;
    has_winner BOOLEAN;
    target_level_number INTEGER;
    credited_level_number INTEGER;
    old_item_id UUID;
    response JSONB := '[]'::jsonb;
BEGIN
    SELECT
        scan.id,
        scan.user_id,
        scan.timestamp,
        scan.ecology_type::TEXT AS ecology_type,
        scan.is_tombstoned,
        scan.is_biological_subject,
        internal.scan_effective_species_id(scan) AS resolved_species_id,
        species.scientific_name,
        species.common_names,
        species.kingdom,
        species.phylum,
        species."class",
        species."order",
        species.family,
        species.genus,
        species.habitat_description,
        species.group_tags
    INTO scan_row
    FROM public.scans scan
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.scan_effective_species_id(scan)
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id;

    IF NOT FOUND
       OR scan_row.is_tombstoned
       OR scan_row.is_biological_subject IS FALSE
       OR scan_row.resolved_species_id IS NULL THEN
        RETURN response;
    END IF;

    FOR participation_row IN
        SELECT
            participation.id,
            participation.challenge_id,
            participation.current_level_number,
            challenge.template_id,
            challenge.slug,
            challenge.title,
            challenge.suggested_hashtags
        FROM public.field_trip_challenge_participants participation
        JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
        WHERE participation.user_id = self_id
          AND participation.completed_at IS NULL
          AND scan_row.timestamp >= participation.joined_at
          AND scan_row.timestamp BETWEEN challenge.starts_at AND challenge.ends_at
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.field_trip_challenge_item_completions existing_completion
                  WHERE existing_completion.participation_id = participation.id
                    AND existing_completion.scan_id = target_scan_id
              )
              OR (
                  participation.hidden_at IS NULL
                  AND challenge.is_active = TRUE
              )
          )
        ORDER BY participation.id
        FOR UPDATE OF participation
    LOOP
        SELECT
            completion.id,
            completion.item_id,
            level.level_number,
            item.prompt
        INTO existing_row
        FROM public.field_trip_challenge_item_completions completion
        JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
        JOIN public.field_trip_levels level ON level.id = item.level_id
        WHERE completion.participation_id = participation_row.id
          AND completion.scan_id = target_scan_id;
        has_existing := FOUND;
        old_item_id := CASE WHEN has_existing THEN existing_row.item_id ELSE NULL END;
        target_level_number := CASE
            WHEN has_existing THEN existing_row.level_number
            ELSE participation_row.current_level_number
        END;

        SELECT
            item.id AS item_id,
            item.prompt,
            level.level_number,
            level.title AS level_title
        INTO winner_row
        FROM public.field_trip_levels level
        JOIN public.field_trip_checklist_items item ON item.level_id = level.id
        WHERE level.template_id = participation_row.template_id
          AND level.level_number = target_level_number
          AND NOT EXISTS (
              SELECT 1
              FROM public.field_trip_challenge_item_completions occupied
              WHERE occupied.participation_id = participation_row.id
                AND occupied.item_id = item.id
                AND occupied.scan_id <> target_scan_id
          )
          AND public.field_trip_item_matches_scan(
              item.match_type,
              item.species_id,
              item.scientific_name,
              item.taxonomy_kingdom,
              item.taxonomy_phylum,
              item.taxonomy_class,
              item.taxonomy_order,
              item.taxonomy_family,
              item.taxonomy_genus,
              item.ecology_type,
              item.habitat_tag,
              item.semantic_tag,
              scan_row.resolved_species_id,
              scan_row.scientific_name,
              scan_row.common_names,
              scan_row.kingdom,
              scan_row.phylum,
              scan_row."class",
              scan_row."order",
              scan_row.family,
              scan_row.genus,
              scan_row.ecology_type,
              scan_row.habitat_description,
              scan_row.group_tags
          )
        ORDER BY
            public.field_trip_checklist_match_rank(
                item.match_type,
                item.taxonomy_kingdom,
                item.taxonomy_phylum,
                item.taxonomy_class,
                item.taxonomy_order,
                item.taxonomy_family,
                item.taxonomy_genus
            ),
            item.sort_order,
            item.id
        LIMIT 1;
        has_winner := FOUND;

        IF has_existing AND has_winner AND old_item_id = winner_row.item_id THEN
            UPDATE public.field_trip_challenge_item_completions
            SET species_id = scan_row.resolved_species_id,
                common_name = public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scientific_name = scan_row.scientific_name,
                completed_at = scan_row.timestamp
            WHERE id = existing_row.id;
            CONTINUE;
        END IF;

        IF NOT has_existing AND NOT has_winner THEN
            CONTINUE;
        END IF;

        IF has_existing THEN
            DELETE FROM public.field_trip_challenge_item_completions
            WHERE id = existing_row.id;
        END IF;

        IF has_winner THEN
            INSERT INTO public.field_trip_challenge_item_completions(
                participation_id,
                item_id,
                scan_id,
                species_id,
                common_name,
                scientific_name,
                completed_at
            )
            VALUES (
                participation_row.id,
                winner_row.item_id,
                target_scan_id,
                scan_row.resolved_species_id,
                public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scan_row.scientific_name,
                scan_row.timestamp
            );
        END IF;

        credited_level_number := target_level_number;

        SELECT level.level_number
        INTO state_row
        FROM public.field_trip_levels level
        WHERE level.template_id = participation_row.template_id
          AND (
              SELECT COUNT(*)
              FROM public.field_trip_challenge_item_completions completion
              JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
              WHERE completion.participation_id = participation_row.id
                AND item.level_id = level.id
          ) < (
              SELECT COUNT(*)
              FROM public.field_trip_checklist_items item
              WHERE item.level_id = level.id
          )
        ORDER BY level.level_number
        LIMIT 1;

        IF FOUND THEN
            UPDATE public.field_trip_challenge_participants
            SET current_level_number = state_row.level_number,
                updated_at = NOW()
            WHERE id = participation_row.id;
        ELSE
            UPDATE public.field_trip_challenge_participants
            SET completed_at = COALESCE(completed_at, NOW()),
                badge_awarded_at = COALESCE(badge_awarded_at, NOW()),
                updated_at = NOW()
            WHERE id = participation_row.id;

            INSERT INTO public.field_trip_challenge_badges(
                participation_id,
                challenge_id,
                user_id,
                badge_key,
                title,
                awarded_at,
                is_profile_visible
            )
            SELECT
                participation.id,
                participation.challenge_id,
                participation.user_id,
                challenge.slug || '_completed',
                challenge.title || ' Completed',
                participation.badge_awarded_at,
                TRUE
            FROM public.field_trip_challenge_participants participation
            JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
            WHERE participation.id = participation_row.id
            ON CONFLICT(user_id, challenge_id) DO NOTHING;
        END IF;

        SELECT
            participation.id AS participation_id,
            participation.challenge_id,
            challenge.slug,
            challenge.title,
            challenge.suggested_hashtags,
            participation.current_level_number,
            current_level.title AS current_level_title,
            participation.completed_at,
            participation.badge_awarded_at,
            credited_level.title AS credited_level_title,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = current_level.id
            ) AS target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.participation_id = participation.id
                  AND item.level_id = current_level.id
            ) AS completed_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = credited_level.id
            ) AS credited_target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.participation_id = participation.id
                  AND item.level_id = credited_level.id
            ) AS credited_completed_count
        INTO state_row
        FROM public.field_trip_challenge_participants participation
        JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
        LEFT JOIN public.field_trip_levels current_level
            ON current_level.template_id = challenge.template_id
           AND current_level.level_number = participation.current_level_number
        JOIN public.field_trip_levels credited_level
            ON credited_level.template_id = challenge.template_id
           AND credited_level.level_number = credited_level_number
        WHERE participation.id = participation_row.id;

        response := response || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'participation_id', state_row.participation_id,
            'challenge_id', state_row.challenge_id,
            'slug', state_row.slug,
            'title', state_row.title,
            'current_level_number', state_row.current_level_number,
            'current_level_title', state_row.current_level_title,
            'completed_count', COALESCE(state_row.completed_count, 0),
            'target_count', COALESCE(state_row.target_count, 0),
            'is_complete', state_row.completed_at IS NOT NULL,
            'badge_awarded_at', state_row.badge_awarded_at,
            'suggested_hashtags', state_row.suggested_hashtags,
            'credited_level_number', credited_level_number,
            'credited_level_title', state_row.credited_level_title,
            'credited_completed_count', COALESCE(state_row.credited_completed_count, 0),
            'credited_target_count', COALESCE(state_row.credited_target_count, 0),
            'newly_completed_items', CASE WHEN has_winner THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
                'item_id', winner_row.item_id,
                'prompt', winner_row.prompt,
                'common_name', public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                'scientific_name', scan_row.scientific_name,
                'completed_at', scan_row.timestamp
            )) ELSE '[]'::jsonb END,
            'removed_item_ids', CASE WHEN has_existing THEN JSONB_BUILD_ARRAY(old_item_id) ELSE '[]'::jsonb END
        ));
    END LOOP;

    RETURN response;
END;
$function$;


CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_v2_unchecked(self_id uuid, target_scan_id uuid, preferred_user_field_trip_id uuid, preferred_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    scan_row RECORD;
    trip_row RECORD;
    existing_row RECORD;
    winner_row RECORD;
    state_row RECORD;
    stored_preferred_user_field_trip_id UUID;
    stored_preferred_item_id UUID;
    has_existing BOOLEAN;
    has_winner BOOLEAN;
    target_level_number INTEGER;
    credited_level_number INTEGER;
    old_item_id UUID;
    new_item_id UUID;
    response JSONB := '[]'::jsonb;
    user_is_pro BOOLEAN := FALSE;
BEGIN
    SELECT
        scan.id,
        scan.user_id,
        scan.timestamp,
        scan.ecology_type::TEXT AS ecology_type,
        scan.is_tombstoned,
        scan.is_biological_subject,
        internal.scan_effective_species_id(scan) AS resolved_species_id,
        species.scientific_name,
        species.common_names,
        species.kingdom,
        species.phylum,
        species."class",
        species."order",
        species.family,
        species.genus,
        species.habitat_description,
        species.group_tags
    INTO scan_row
    FROM public.scans scan
    LEFT JOIN public.species_dictionary species
        ON species.id = internal.scan_effective_species_id(scan)
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id;

    IF NOT FOUND
       OR scan_row.is_tombstoned
       OR scan_row.is_biological_subject IS FALSE
       OR scan_row.resolved_species_id IS NULL THEN
        RETURN response;
    END IF;

    SELECT internal.user_has_effective_pro(users.id)
    INTO user_is_pro
    FROM public.users users
    WHERE users.id = self_id;

    -- Validate and persist only a live, visible Capture selection. Invalid,
    -- unauthorized, stale, completed, and nonmatching hints are silently ignored.
    IF preferred_user_field_trip_id IS NOT NULL AND preferred_item_id IS NOT NULL THEN
        PERFORM 1
        FROM public.user_field_trips trip
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        JOIN public.field_trip_levels level
            ON level.template_id = trip.template_id
           AND level.level_number = trip.current_level_number
        JOIN public.field_trip_checklist_items item
            ON item.id = preferred_item_id
           AND item.level_id = level.id
        WHERE trip.id = preferred_user_field_trip_id
          AND trip.user_id = self_id
          AND trip.completed_at IS NULL
          AND trip.hidden_at IS NULL
          AND template.is_active = TRUE
          AND (template.is_pro_only = FALSE OR user_is_pro OR template.is_rotating_free = TRUE)
          AND EXISTS (
              SELECT 1
              FROM public.user_field_trip_active_periods period
              WHERE period.user_field_trip_id = trip.id
                AND scan_row.timestamp >= period.started_at
                AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
          )
          AND public.field_trip_item_matches_scan(
              item.match_type,
              item.species_id,
              item.scientific_name,
              item.taxonomy_kingdom,
              item.taxonomy_phylum,
              item.taxonomy_class,
              item.taxonomy_order,
              item.taxonomy_family,
              item.taxonomy_genus,
              item.ecology_type,
              item.habitat_tag,
              item.semantic_tag,
              scan_row.resolved_species_id,
              scan_row.scientific_name,
              scan_row.common_names,
              scan_row.kingdom,
              scan_row.phylum,
              scan_row."class",
              scan_row."order",
              scan_row.family,
              scan_row.genus,
              scan_row.ecology_type,
              scan_row.habitat_description,
              scan_row.group_tags
          );

        IF FOUND THEN
            INSERT INTO public.field_trip_scan_goal_preferences(
                scan_id,
                user_id,
                user_field_trip_id,
                item_id,
                updated_at
            )
            VALUES (
                target_scan_id,
                self_id,
                preferred_user_field_trip_id,
                preferred_item_id,
                NOW()
            )
            ON CONFLICT(scan_id) DO UPDATE
            SET user_id = EXCLUDED.user_id,
                user_field_trip_id = EXCLUDED.user_field_trip_id,
                item_id = EXCLUDED.item_id,
                updated_at = NOW();
        END IF;
    END IF;

    SELECT preference.user_field_trip_id, preference.item_id
    INTO stored_preferred_user_field_trip_id, stored_preferred_item_id
    FROM public.field_trip_scan_goal_preferences preference
    WHERE preference.scan_id = target_scan_id
      AND preference.user_id = self_id;

    FOR trip_row IN
        SELECT trip.id, trip.template_id, trip.current_level_number, template.slug, template.title
        FROM public.user_field_trips trip
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        WHERE trip.user_id = self_id
          AND trip.completed_at IS NULL
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.user_field_trip_item_completions existing_completion
                  WHERE existing_completion.user_field_trip_id = trip.id
                    AND existing_completion.scan_id = target_scan_id
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.user_field_trip_active_periods period
                  WHERE period.user_field_trip_id = trip.id
                    AND scan_row.timestamp >= period.started_at
                    AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
              )
          )
        ORDER BY trip.id
        FOR UPDATE OF trip
    LOOP
        SELECT
            completion.id,
            completion.item_id,
            level.level_number,
            item.prompt
        INTO existing_row
        FROM public.user_field_trip_item_completions completion
        JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
        JOIN public.field_trip_levels level ON level.id = item.level_id
        WHERE completion.user_field_trip_id = trip_row.id
          AND completion.scan_id = target_scan_id;
        has_existing := FOUND;
        old_item_id := CASE WHEN has_existing THEN existing_row.item_id ELSE NULL END;
        target_level_number := CASE
            WHEN has_existing THEN existing_row.level_number
            ELSE trip_row.current_level_number
        END;

        SELECT
            item.id AS item_id,
            item.prompt,
            level.level_number,
            level.title AS level_title
        INTO winner_row
        FROM public.field_trip_levels level
        JOIN public.field_trip_checklist_items item ON item.level_id = level.id
        WHERE level.template_id = trip_row.template_id
          AND level.level_number = target_level_number
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_field_trip_item_completions occupied
              WHERE occupied.user_field_trip_id = trip_row.id
                AND occupied.item_id = item.id
                AND occupied.scan_id <> target_scan_id
          )
          AND public.field_trip_item_matches_scan(
              item.match_type,
              item.species_id,
              item.scientific_name,
              item.taxonomy_kingdom,
              item.taxonomy_phylum,
              item.taxonomy_class,
              item.taxonomy_order,
              item.taxonomy_family,
              item.taxonomy_genus,
              item.ecology_type,
              item.habitat_tag,
              item.semantic_tag,
              scan_row.resolved_species_id,
              scan_row.scientific_name,
              scan_row.common_names,
              scan_row.kingdom,
              scan_row.phylum,
              scan_row."class",
              scan_row."order",
              scan_row.family,
              scan_row.genus,
              scan_row.ecology_type,
              scan_row.habitat_description,
              scan_row.group_tags
          )
        ORDER BY
            CASE
                WHEN stored_preferred_user_field_trip_id = trip_row.id
                 AND stored_preferred_item_id = item.id THEN 0
                ELSE 1
            END,
            public.field_trip_checklist_match_rank(
                item.match_type,
                item.taxonomy_kingdom,
                item.taxonomy_phylum,
                item.taxonomy_class,
                item.taxonomy_order,
                item.taxonomy_family,
                item.taxonomy_genus
            ),
            item.sort_order,
            item.id
        LIMIT 1;
        has_winner := FOUND;
        new_item_id := CASE WHEN has_winner THEN winner_row.item_id ELSE NULL END;

        IF has_existing AND has_winner AND old_item_id = new_item_id THEN
            UPDATE public.user_field_trip_item_completions
            SET species_id = scan_row.resolved_species_id,
                common_name = public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scientific_name = scan_row.scientific_name,
                completed_at = scan_row.timestamp
            WHERE id = existing_row.id;
            CONTINUE;
        END IF;

        IF NOT has_existing AND NOT has_winner THEN
            CONTINUE;
        END IF;

        IF has_existing THEN
            DELETE FROM public.user_field_trip_item_completions
            WHERE id = existing_row.id;
        END IF;

        IF has_winner THEN
            INSERT INTO public.user_field_trip_item_completions(
                user_field_trip_id,
                item_id,
                scan_id,
                species_id,
                common_name,
                scientific_name,
                completed_at
            )
            VALUES (
                trip_row.id,
                winner_row.item_id,
                target_scan_id,
                scan_row.resolved_species_id,
                public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scan_row.scientific_name,
                scan_row.timestamp
            );
        END IF;

        credited_level_number := target_level_number;

        SELECT level.level_number
        INTO state_row
        FROM public.field_trip_levels level
        WHERE level.template_id = trip_row.template_id
          AND (
              SELECT COUNT(*)
              FROM public.user_field_trip_item_completions completion
              JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
              WHERE completion.user_field_trip_id = trip_row.id
                AND item.level_id = level.id
          ) < (
              SELECT COUNT(*)
              FROM public.field_trip_checklist_items item
              WHERE item.level_id = level.id
          )
        ORDER BY level.level_number
        LIMIT 1;

        IF FOUND THEN
            UPDATE public.user_field_trips
            SET current_level_number = state_row.level_number,
                updated_at = NOW()
            WHERE id = trip_row.id;
        ELSE
            UPDATE public.user_field_trips
            SET completed_at = COALESCE(completed_at, NOW()),
                hidden_at = NULL,
                updated_at = NOW()
            WHERE id = trip_row.id;

            UPDATE public.user_field_trip_active_periods
            SET stopped_at = COALESCE(stopped_at, NOW())
            WHERE user_field_trip_id = trip_row.id
              AND stopped_at IS NULL;
        END IF;

        SELECT
            trip.id AS user_field_trip_id,
            trip.template_id,
            template.slug,
            template.title,
            trip.current_level_number,
            current_level.title AS current_level_title,
            trip.completed_at,
            credited_level.title AS credited_level_title,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = current_level.id
            ) AS target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.user_field_trip_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.user_field_trip_id = trip.id
                  AND item.level_id = current_level.id
            ) AS completed_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = credited_level.id
            ) AS credited_target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.user_field_trip_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.user_field_trip_id = trip.id
                  AND item.level_id = credited_level.id
            ) AS credited_completed_count
        INTO state_row
        FROM public.user_field_trips trip
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        LEFT JOIN public.field_trip_levels current_level
            ON current_level.template_id = trip.template_id
           AND current_level.level_number = trip.current_level_number
        JOIN public.field_trip_levels credited_level
            ON credited_level.template_id = trip.template_id
           AND credited_level.level_number = credited_level_number
        WHERE trip.id = trip_row.id;

        response := response || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'user_field_trip_id', state_row.user_field_trip_id,
            'template_id', state_row.template_id,
            'slug', state_row.slug,
            'title', state_row.title,
            'current_level_number', state_row.current_level_number,
            'current_level_title', state_row.current_level_title,
            'completed_count', COALESCE(state_row.completed_count, 0),
            'target_count', COALESCE(state_row.target_count, 0),
            'is_complete', state_row.completed_at IS NOT NULL,
            'credited_level_number', credited_level_number,
            'credited_level_title', state_row.credited_level_title,
            'credited_completed_count', COALESCE(state_row.credited_completed_count, 0),
            'credited_target_count', COALESCE(state_row.credited_target_count, 0),
            'newly_completed_items', CASE WHEN has_winner THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
                'item_id', winner_row.item_id,
                'prompt', winner_row.prompt,
                'common_name', public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                'scientific_name', scan_row.scientific_name,
                'completed_at', scan_row.timestamp
            )) ELSE '[]'::jsonb END,
            'removed_item_ids', CASE WHEN has_existing THEN JSONB_BUILD_ARRAY(old_item_id) ELSE '[]'::jsonb END
        ));
    END LOOP;

    RETURN response;
END;
$function$;


CREATE OR REPLACE FUNCTION public.refresh_merian_reference_images(p_quality_threshold integer DEFAULT 80, p_per_species_limit integer DEFAULT 8, p_dry_run boolean DEFAULT false, p_species_confidence_threshold double precision DEFAULT 0.95)
 RETURNS TABLE(candidate_count integer, promoted_count integer, removed_count integer, species_count integer, dry_run boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_now TIMESTAMPTZ := NOW();
BEGIN
    PERFORM internal.require_service_role();

    IF p_quality_threshold IS NULL OR p_quality_threshold < 0 OR p_quality_threshold > 100 THEN
        RAISE EXCEPTION 'p_quality_threshold must be an integer from 0 to 100';
    END IF;

    IF p_per_species_limit IS NULL OR p_per_species_limit < 1 OR p_per_species_limit > 50 THEN
        RAISE EXCEPTION 'p_per_species_limit must be an integer from 1 to 50';
    END IF;

    IF p_species_confidence_threshold IS NULL
       OR p_species_confidence_threshold < 0
       OR p_species_confidence_threshold > 1 THEN
        RAISE EXCEPTION 'p_species_confidence_threshold must be a number from 0 to 1';
    END IF;

    IF p_dry_run THEN
        RETURN QUERY
        WITH raw_candidates AS (
            SELECT
                internal.explore_effective_species_id(s, ep.id) AS species_id,
                ep.id AS explore_post_id,
                s.id AS scan_id,
                ep.user_id,
                NULLIF(BTRIM(media.raw_url), '') AS image_url,
                (media.ordinality::INTEGER - 1) AS image_index,
                s.image_quality_score,
                LEAST(GREATEST(COALESCE(s.ai_confidence_score, 0), 0), 1) AS species_confidence_score,
                CASE
                    WHEN (s.primary_identification IS NULL AND s.confirmed_species_id IS NOT NULL) THEN 'confirmed_species'
                    ELSE 'ai'
                END AS species_confidence_source,
                COALESCE(NULLIF(BTRIM(u.public_author_name), ''), 'Naturebook community') AS author_attribution,
                ep.shared_at AS source_shared_at
            FROM public.explore_posts ep
            JOIN public.scans s
                ON s.id = ep.scan_id
            JOIN public.users u
                ON u.id = ep.user_id
            CROSS JOIN LATERAL UNNEST(s.image_storage_urls) WITH ORDINALITY AS media(raw_url, ordinality)
            WHERE ep.unshared_at IS NULL
              AND s.is_tombstoned = FALSE
              AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
              AND internal.explore_effective_species_id(s, ep.id) IS NOT NULL
              AND s.geoprivacy <> 'private'
              AND u.is_shadowbanned = FALSE
              AND (
                  s.primary_identification IS NULL OR (
                      s.primary_identification ->> 'resolution' = 'species'
                      AND s.species_id = internal.explore_effective_species_id(s, ep.id)
                  )
              )
              AND internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier)
              AND COALESCE(s.image_quality_score, -1) >= p_quality_threshold
              AND (
                  (s.primary_identification IS NULL AND s.confirmed_species_id IS NOT NULL)
                  OR COALESCE(s.ai_confidence_score, -1) >= p_species_confidence_threshold
              )
              AND NULLIF(BTRIM(media.raw_url), '') IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.explore_post_media AS media_health
                  WHERE media_health.post_id = ep.id
                    AND media_health.url = NULLIF(BTRIM(media.raw_url), '')
                    AND media_health.health_status = 'missing'
              )
        ),
        deduped AS (
            SELECT *
            FROM (
                SELECT
                    raw_candidates.*,
                    ROW_NUMBER() OVER (
                        PARTITION BY species_id, image_url
                        ORDER BY
                            CASE WHEN species_confidence_source = 'confirmed_species' THEN 0 ELSE 1 END,
                            species_confidence_score DESC,
                            image_quality_score DESC,
                            source_shared_at DESC,
                            image_index,
                            explore_post_id
                    ) AS duplicate_rank
                FROM raw_candidates
            ) ranked_duplicates
            WHERE duplicate_rank = 1
        ),
        ranked AS (
            SELECT
                deduped.*,
                ROW_NUMBER() OVER (
                    PARTITION BY species_id
                    ORDER BY
                        CASE WHEN species_confidence_source = 'confirmed_species' THEN 0 ELSE 1 END,
                        species_confidence_score DESC,
                        image_quality_score DESC,
                        source_shared_at DESC,
                        image_index,
                        image_url
                ) AS species_rank
            FROM deduped
        ),
        selected AS (
            SELECT *
            FROM ranked
            WHERE species_rank <= p_per_species_limit
        ),
        stale_merian_refs AS (
            SELECT ref.id
            FROM public.species_reference_images ref
            WHERE ref.source = 'merian'
              AND NOT EXISTS (
                  SELECT 1
                  FROM selected
                  WHERE selected.species_id = ref.species_id
                    AND selected.image_url = ref.url
              )
        )
        SELECT
            (SELECT COUNT(*)::INTEGER FROM deduped),
            (SELECT COUNT(*)::INTEGER FROM selected),
            (SELECT COUNT(*)::INTEGER FROM stale_merian_refs),
            (SELECT COUNT(DISTINCT species_id)::INTEGER FROM selected),
            TRUE;
        RETURN;
    END IF;

    RETURN QUERY
    WITH raw_candidates AS (
        SELECT
            internal.explore_effective_species_id(s, ep.id) AS species_id,
            ep.id AS explore_post_id,
            s.id AS scan_id,
            ep.user_id,
            NULLIF(BTRIM(media.raw_url), '') AS image_url,
            (media.ordinality::INTEGER - 1) AS image_index,
            s.image_quality_score,
            LEAST(GREATEST(COALESCE(s.ai_confidence_score, 0), 0), 1) AS species_confidence_score,
            CASE
                WHEN (s.primary_identification IS NULL AND s.confirmed_species_id IS NOT NULL) THEN 'confirmed_species'
                ELSE 'ai'
            END AS species_confidence_source,
            COALESCE(NULLIF(BTRIM(u.public_author_name), ''), 'Naturebook community') AS author_attribution,
            ep.shared_at AS source_shared_at
        FROM public.explore_posts ep
        JOIN public.scans s
            ON s.id = ep.scan_id
        JOIN public.users u
            ON u.id = ep.user_id
        CROSS JOIN LATERAL UNNEST(s.image_storage_urls) WITH ORDINALITY AS media(raw_url, ordinality)
        WHERE ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND internal.explore_effective_species_id(s, ep.id) IS NOT NULL
          AND s.geoprivacy <> 'private'
          AND u.is_shadowbanned = FALSE
          AND (
                  s.primary_identification IS NULL OR (
                      s.primary_identification ->> 'resolution' = 'species'
                      AND s.species_id = internal.explore_effective_species_id(s, ep.id)
                  )
              )
              AND internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier)
              AND COALESCE(s.image_quality_score, -1) >= p_quality_threshold
          AND (
              (s.primary_identification IS NULL AND s.confirmed_species_id IS NOT NULL)
              OR COALESCE(s.ai_confidence_score, -1) >= p_species_confidence_threshold
          )
          AND NULLIF(BTRIM(media.raw_url), '') IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.explore_post_media AS media_health
                  WHERE media_health.post_id = ep.id
                    AND media_health.url = NULLIF(BTRIM(media.raw_url), '')
                    AND media_health.health_status = 'missing'
              )
    ),
    deduped AS (
        SELECT *
        FROM (
            SELECT
                raw_candidates.*,
                ROW_NUMBER() OVER (
                    PARTITION BY species_id, image_url
                    ORDER BY
                        CASE WHEN species_confidence_source = 'confirmed_species' THEN 0 ELSE 1 END,
                        species_confidence_score DESC,
                        image_quality_score DESC,
                        source_shared_at DESC,
                        image_index,
                        explore_post_id
                ) AS duplicate_rank
            FROM raw_candidates
        ) ranked_duplicates
        WHERE duplicate_rank = 1
    ),
    ranked AS (
        SELECT
            deduped.*,
            ROW_NUMBER() OVER (
                PARTITION BY species_id
                ORDER BY
                    CASE WHEN species_confidence_source = 'confirmed_species' THEN 0 ELSE 1 END,
                    species_confidence_score DESC,
                    image_quality_score DESC,
                    source_shared_at DESC,
                    image_index,
                    image_url
            ) AS species_rank
        FROM deduped
    ),
    selected AS (
        SELECT *
        FROM ranked
        WHERE species_rank <= p_per_species_limit
    ),
    mark_disqualified AS (
        UPDATE public.species_reference_image_merian_sources source
        SET
            reference_image_id = NULL,
            is_promoted = FALSE,
            disqualified_at = COALESCE(source.disqualified_at, v_now),
            updated_at = v_now
        WHERE source.disqualified_at IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM deduped
              WHERE deduped.species_id = source.species_id
                AND deduped.image_url = source.image_url
          )
        RETURNING source.id
    ),
    candidate_upsert AS (
        INSERT INTO public.species_reference_image_merian_sources (
            species_id,
            explore_post_id,
            scan_id,
            user_id,
            image_url,
            image_index,
            image_quality_score,
            species_confidence_score,
            species_confidence_source,
            author_attribution,
            source_shared_at,
            is_promoted,
            first_qualified_at,
            last_qualified_at,
            disqualified_at,
            updated_at
        )
        SELECT
            ranked.species_id,
            ranked.explore_post_id,
            ranked.scan_id,
            ranked.user_id,
            ranked.image_url,
            ranked.image_index,
            ranked.image_quality_score,
            ranked.species_confidence_score,
            ranked.species_confidence_source,
            ranked.author_attribution,
            ranked.source_shared_at,
            ranked.species_rank <= p_per_species_limit,
            v_now,
            v_now,
            NULL,
            v_now
        FROM ranked
        ON CONFLICT (species_id, image_url) DO UPDATE
            SET
                explore_post_id = EXCLUDED.explore_post_id,
                scan_id = EXCLUDED.scan_id,
                user_id = EXCLUDED.user_id,
                image_index = EXCLUDED.image_index,
                image_quality_score = EXCLUDED.image_quality_score,
                species_confidence_score = EXCLUDED.species_confidence_score,
                species_confidence_source = EXCLUDED.species_confidence_source,
                author_attribution = EXCLUDED.author_attribution,
                source_shared_at = EXCLUDED.source_shared_at,
                is_promoted = EXCLUDED.is_promoted,
                last_qualified_at = EXCLUDED.last_qualified_at,
                disqualified_at = NULL,
                updated_at = EXCLUDED.updated_at
        RETURNING id, species_id, image_url
    ),
    deleted_refs AS (
        DELETE FROM public.species_reference_images ref
        WHERE ref.source = 'merian'
          AND NOT EXISTS (
              SELECT 1
              FROM selected
              WHERE selected.species_id = ref.species_id
                AND selected.image_url = ref.url
          )
        RETURNING ref.id
    ),
    upserted_refs AS (
        INSERT INTO public.species_reference_images (
            species_id,
            url,
            source,
            license,
            attribution,
            sort_order,
            last_verified_at
        )
        SELECT
            selected.species_id,
            selected.image_url,
            'merian',
            'Used with permission via Naturebook',
            selected.author_attribution,
            (selected.species_rank::INTEGER - 1),
            v_now
        FROM selected
        ON CONFLICT (species_id, url) DO UPDATE
            SET
                source = 'merian',
                license = 'Used with permission via Naturebook',
                attribution = EXCLUDED.attribution,
                sort_order = EXCLUDED.sort_order,
                last_verified_at = EXCLUDED.last_verified_at
        RETURNING id, species_id, url
    ),
    link_promoted AS (
        SELECT NULL::UUID AS id
        WHERE FALSE
    ),
    demote_unselected AS (
        SELECT NULL::UUID AS id
        WHERE FALSE
    )
    SELECT
        (SELECT COUNT(*)::INTEGER FROM candidate_upsert),
        (SELECT COUNT(*)::INTEGER FROM upserted_refs),
        (SELECT COUNT(*)::INTEGER FROM deleted_refs),
        (SELECT COUNT(DISTINCT species_id)::INTEGER FROM selected),
        FALSE;

    UPDATE public.species_reference_image_merian_sources AS source
    SET
        reference_image_id = reference.id,
        is_promoted = TRUE,
        last_promoted_at = v_now,
        updated_at = v_now
    FROM public.species_reference_images AS reference
    WHERE reference.source = 'merian'
      AND source.disqualified_at IS NULL
      AND source.species_id = reference.species_id
      AND source.image_url = reference.url;

    UPDATE public.species_reference_image_merian_sources AS source
    SET
        reference_image_id = NULL,
        is_promoted = FALSE,
        updated_at = v_now
    WHERE source.disqualified_at IS NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.species_reference_images AS reference
          WHERE reference.source = 'merian'
            AND reference.species_id = source.species_id
            AND reference.url = source.image_url
      );
END;
$function$;


CREATE OR REPLACE VIEW internal.dwca_export_snapshot_source
WITH (security_invoker = TRUE)
AS
SELECT
    scans.id AS scan_id,
    scans.user_id,
    scans.is_live_capture,
    scans.is_tombstoned,
    scans.ecology_type,
    scans.geoprivacy,
    internal.scan_effective_species_id(scans)
        AS effective_species_id,
    species.iucn_red_list_status,
    COALESCE(
        species.iucn_red_list_status IN (
            'vulnerable',
            'endangered',
            'critically_endangered',
            'near_threatened'
        ),
        FALSE
    ) AS coordinate_protection_required,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', NULL,
        'coordinate_protection_required',
            COALESCE(
                species.iucn_red_list_status IN (
                    'vulnerable',
                    'endangered',
                    'critically_endangered',
                    'near_threatened'
                ),
                FALSE
            )
    ) AS personal_eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', scans.geoprivacy,
        'coordinate_protection_required',
            COALESCE(
                species.iucn_red_list_status IN (
                    'vulnerable',
                    'endangered',
                    'critically_endangered',
                    'near_threatened'
                ),
                FALSE
            )
    ) AS global_eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'effective_species_id',
            internal.scan_effective_species_id(scans),
        'identification',CASE WHEN internal.scan_effective_identification(scans) ->> 'source' IN ('legacy', 'invalid') THEN NULL ELSE
            pg_catalog.JSONB_BUILD_OBJECT('rank',internal.scan_effective_identification(scans) -> 'rank',
                'scientific_name',internal.scan_effective_identification(scans) -> 'scientific_name',
                'verified_selection',(internal.scan_effective_identification(scans) ->> 'verified')::BOOLEAN) END,
        'timestamp', scans.timestamp,
        'gps_lat_exact', scans.gps_lat_exact,
        'gps_long_exact', scans.gps_long_exact,
        'gps_lat_public', scans.gps_lat_public,
        'gps_long_public', scans.gps_long_public,
        'coordinate_uncertainty_in_meters',
            scans.coordinate_uncertainty_in_meters,
        'life_stage', scans.life_stage,
        'reproductive_condition', scans.reproductive_condition,
        'sex', scans.sex,
        'individual_count', scans.individual_count,
        'ecological_interactions',
            COALESCE(scans.ecological_interactions, ARRAY[]::TEXT[]),
        'ai_confidence_score', scans.ai_confidence_score,
        'ai_confidence_qualified', internal.identification_metrics_are_gemini_compatible(
            scans.identification_provenance, scans.inference_tier),
        'species_dictionary', CASE
            WHEN species.id IS NULL THEN NULL
            ELSE pg_catalog.JSONB_BUILD_OBJECT(
                'scientific_name', species.scientific_name,
                'kingdom', species.kingdom,
                'phylum', species.phylum,
                'class', species.class,
                'order', species."order",
                'family', species.family,
                'genus', species.genus,
                'iucn_red_list_status', species.iucn_red_list_status
            )
        END
    ) AS occurrence_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'image_storage_urls', scans.image_storage_urls
    ) AS multimedia_payload
FROM public.scans AS scans
LEFT JOIN public.species_dictionary AS species
    ON species.id = internal.scan_effective_species_id(scans);

REVOKE ALL ON TABLE internal.dwca_export_snapshot_source
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON VIEW internal.dwca_export_snapshot_source IS
    'Private one-statement source projection used to materialize immutable authoritative DwC-A DTO rows and scope-aware privacy eligibility hashes.';




DROP TRIGGER IF EXISTS trg_apply_ingested_scan_field_trip_progress_update
    ON public.scans;
CREATE TRIGGER trg_apply_ingested_scan_field_trip_progress_update
AFTER UPDATE OF
    primary_identification,
    confirmed_species_identity,
    confirmed_species_identity_revision,
    species_id,
    confirmed_species_id,
    ai_confidence_score,
    inference_tier,
    identification_provenance,
    user_confirmed_identification,
    user_identification_override,
    is_biological_subject,
    is_tombstoned,
    timestamp
ON public.scans
FOR EACH ROW
WHEN (
    OLD.primary_identification IS DISTINCT FROM NEW.primary_identification
    OR OLD.confirmed_species_identity IS DISTINCT FROM NEW.confirmed_species_identity
    OR OLD.confirmed_species_identity_revision IS DISTINCT FROM NEW.confirmed_species_identity_revision
    OR OLD.species_id IS DISTINCT FROM NEW.species_id
    OR OLD.confirmed_species_id IS DISTINCT FROM NEW.confirmed_species_id
    OR OLD.ai_confidence_score IS DISTINCT FROM NEW.ai_confidence_score
    OR OLD.inference_tier IS DISTINCT FROM NEW.inference_tier
    OR OLD.identification_provenance IS DISTINCT FROM NEW.identification_provenance
    OR OLD.user_confirmed_identification IS DISTINCT FROM
        NEW.user_confirmed_identification
    OR OLD.user_identification_override IS DISTINCT FROM NEW.user_identification_override
    OR OLD.is_biological_subject IS DISTINCT FROM NEW.is_biological_subject
    OR OLD.is_tombstoned IS DISTINCT FROM NEW.is_tombstoned
    OR OLD.timestamp IS DISTINCT FROM NEW.timestamp
)
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;
