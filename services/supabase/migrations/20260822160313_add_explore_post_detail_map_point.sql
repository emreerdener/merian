SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- PostgreSQL cannot change the row shape of an existing RETURNS TABLE
-- function in place. Recreate the canonical detail projection with one
-- additive, privacy-gated map point sourced only from the post-owned public
-- coordinate snapshot.
DROP FUNCTION public.get_explore_post_detail(UUID, UUID);

CREATE FUNCTION public.get_explore_post_detail(
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
    similar_species JSONB,
    map_point JSONB
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
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
        scan.pet_identification,
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
        public.public_species_reference_image_urls_excluding_media(
            species.id,
            species.reference_image_url,
            scan.image_storage_urls
        ) AS reference_image_url,
        species.wikipedia_overview,
        public.public_species_similar_species(species.id) AS similar_species,
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
        ON species.id = COALESCE(
            scan.confirmed_species_id,
            scan.species_id
        )
    WHERE post.id = target_post_id
      AND post.unshared_at IS NULL
      AND post.moderated_at IS NULL
      AND post.media_health_status <> 'quarantined'
      AND scan.is_tombstoned = FALSE
      AND COALESCE(scan.confirmed_species_id, scan.species_id) IS NOT NULL
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
$$;

COMMENT ON FUNCTION public.get_explore_post_detail(UUID, UUID) IS
    'Returns privacy-safe public Explore metadata, including a post-owned map point only for Open location sharing, and applies the canonical reversible media-quarantine visibility boundary.';

REVOKE ALL ON FUNCTION public.get_explore_post_detail(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_post_detail(UUID, UUID)
    TO service_role;

RESET statement_timeout;
RESET lock_timeout;
