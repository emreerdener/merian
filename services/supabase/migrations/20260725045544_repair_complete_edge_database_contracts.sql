-- The complete Edge integration suite exposed three database contract
-- regressions that were previously hidden by the selected-test CI path:
--
-- 1. A later media-projection migration made community-resolved posts visible
--    before their explicit Explore publication timestamp. The repair must
--    retain the later reversible-moderation boundary and the original
--    withdrawn-request fallback.
-- 2. The service-role-only first Field Trip achievement function remained a
--    SECURITY INVOKER without the narrowly required source-table privileges.
-- 3. Reference-image refresh attempted to upsert, promote, demote, or
--    disqualify the same provenance row from sibling data-modifying CTEs.
--    PostgreSQL does not define which sibling mutation wins, so stale rows
--    could be demoted without being marked disqualified and active provenance
--    could retain stale metadata or links.

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
    is_owned_by_viewer BOOLEAN,
    media_items JSONB
)
LANGUAGE SQL
STABLE
SET search_path = ''
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        public.explore_post_hero_image_url(ep.id) AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        users.public_author_name AS author_name,
        users.public_avatar_url AS author_avatar_url,
        public.explore_post_community_common_name(
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
        ) AS species_common_name,
        public.explore_post_community_scientific_name(
            CASE
                WHEN projection.projection_state = 'community_resolved'
                    THEN 'resolved'
                ELSE NULL
            END,
            community_taxon.scientific_name,
            species.scientific_name
        ) AS species_scientific_name,
        scans.pet_identification,
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
        public.explore_post_media_items(ep.id) AS media_items
    FROM public.explore_posts AS ep
    JOIN public.scans AS scans
      ON scans.id = ep.scan_id
    JOIN public.users AS users
      ON users.id = ep.user_id
    LEFT JOIN public.species_dictionary AS species
      ON species.id = COALESCE(
          scans.confirmed_species_id,
          scans.species_id
      )
    LEFT JOIN public.explore_observation_projection AS projection
      ON projection.post_id = ep.id
    LEFT JOIN public.taxon_nodes AS community_taxon
      ON community_taxon.id = projection.public_taxon_node_id
    WHERE ep.unshared_at IS NULL
      AND ep.moderated_at IS NULL
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
      )
      AND COALESCE(
          scans.confirmed_species_id,
          scans.species_id
      ) IS NOT NULL
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
$$;

COMMENT ON FUNCTION public.explore_projected_post_cards(UUID) IS
    'Canonical visible Explore card projection. Moderated, needs-ID, and unpublished community-resolved observations remain excluded; withdrawn requests fall back to the original observation.';

-- This SECURITY INVOKER function is executable only by service_role. Grant
-- that role only the source tables needed to evaluate the private result.
GRANT SELECT ON TABLE
    public.user_field_trips,
    public.field_trip_templates,
    public.field_trip_challenge_participants
TO service_role;

-- Candidate upsert, promotion linking, demotion, and disqualification all
-- targeted the same provenance table from sibling data-modifying CTEs.
-- PostgreSQL does not define which update wins when one statement attempts to
-- modify the same row twice. Keep the CTE names as read-only placeholders so
-- the existing summary projection remains stable, then reconcile promotion
-- links sequentially after candidate/disqualification writes complete.
DO $migration$
DECLARE
    function_sql TEXT;
    cte_start INTEGER;
    cte_end_relative INTEGER;
    cte_end INTEGER;
    cte_end_marker TEXT := E'    )\n    SELECT\n';
    replacement_ctes TEXT :=
        E'    link_promoted AS (\n'
        || E'        SELECT NULL::UUID AS id\n'
        || E'        WHERE FALSE\n'
        || E'    ),\n'
        || E'    demote_unselected AS (\n'
        || E'        SELECT NULL::UUID AS id\n'
        || E'        WHERE FALSE\n';
    tail_marker TEXT := E'        FALSE;\nEND;\n';
    replacement_tail TEXT :=
        E'        FALSE;\n\n'
        || E'    UPDATE public.species_reference_image_merian_sources AS source\n'
        || E'    SET\n'
        || E'        reference_image_id = reference.id,\n'
        || E'        is_promoted = TRUE,\n'
        || E'        last_promoted_at = v_now,\n'
        || E'        updated_at = v_now\n'
        || E'    FROM public.species_reference_images AS reference\n'
        || E'    WHERE reference.source = ''merian''\n'
        || E'      AND source.disqualified_at IS NULL\n'
        || E'      AND source.species_id = reference.species_id\n'
        || E'      AND source.image_url = reference.url;\n\n'
        || E'    UPDATE public.species_reference_image_merian_sources AS source\n'
        || E'    SET\n'
        || E'        reference_image_id = NULL,\n'
        || E'        is_promoted = FALSE,\n'
        || E'        updated_at = v_now\n'
        || E'    WHERE source.disqualified_at IS NULL\n'
        || E'      AND NOT EXISTS (\n'
        || E'          SELECT 1\n'
        || E'          FROM public.species_reference_images AS reference\n'
        || E'          WHERE reference.source = ''merian''\n'
        || E'            AND reference.species_id = source.species_id\n'
        || E'            AND reference.url = source.image_url\n'
        || E'      );\n'
        || E'END;\n';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::REGPROCEDURE
    )
    INTO STRICT function_sql;

    cte_start := pg_catalog.STRPOS(
        function_sql,
        E'    link_promoted AS (\n'
    );
    cte_end_relative := pg_catalog.STRPOS(
        pg_catalog.SUBSTR(function_sql, cte_start),
        cte_end_marker
    );

    IF cte_start = 0 OR cte_end_relative = 0 THEN
        RAISE EXCEPTION
            'refresh_merian_reference_images does not contain the expected overlapping CTE block';
    END IF;

    cte_end := cte_start + cte_end_relative - 1;
    function_sql :=
        pg_catalog.SUBSTR(function_sql, 1, cte_start - 1)
        || replacement_ctes
        || pg_catalog.SUBSTR(function_sql, cte_end);

    IF pg_catalog.STRPOS(function_sql, tail_marker) = 0 THEN
        RAISE EXCEPTION
            'refresh_merian_reference_images does not contain the expected function tail';
    END IF;

    function_sql := pg_catalog.REPLACE(
        function_sql,
        tail_marker,
        replacement_tail
    );
    EXECUTE function_sql;
END;
$migration$;

ALTER FUNCTION public.refresh_merian_reference_images(
    INTEGER,
    INTEGER,
    BOOLEAN,
    DOUBLE PRECISION
) SET search_path = '';

REVOKE ALL ON FUNCTION public.refresh_merian_reference_images(
    INTEGER,
    INTEGER,
    BOOLEAN,
    DOUBLE PRECISION
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.refresh_merian_reference_images(
    INTEGER,
    INTEGER,
    BOOLEAN,
    DOUBLE PRECISION
) TO service_role;
