-- Migration: 20260514110000_add_species_confidence_gate_to_merian_reference_images.sql
-- Description: Requires high species-identification confidence, in addition to
-- image quality, before Merian-published media can become public reference
-- imagery.

ALTER TABLE public.species_reference_image_merian_sources
    ADD COLUMN IF NOT EXISTS species_confidence_score DOUBLE PRECISION;

ALTER TABLE public.species_reference_image_merian_sources
    ADD COLUMN IF NOT EXISTS species_confidence_source TEXT;

UPDATE public.species_reference_image_merian_sources source
SET
    species_confidence_score = LEAST(GREATEST(COALESCE(s.ai_confidence_score, 0), 0), 1),
    species_confidence_source = CASE
        WHEN s.confirmed_species_id IS NOT NULL THEN 'confirmed_species'
        ELSE 'ai'
    END
FROM public.scans s
WHERE s.id = source.scan_id
  AND (
      source.species_confidence_score IS NULL
      OR source.species_confidence_source IS NULL
  );

UPDATE public.species_reference_image_merian_sources
SET
    species_confidence_score = COALESCE(species_confidence_score, 0),
    species_confidence_source = COALESCE(species_confidence_source, 'ai')
WHERE species_confidence_score IS NULL
   OR species_confidence_source IS NULL;

ALTER TABLE public.species_reference_image_merian_sources
    ALTER COLUMN species_confidence_score SET DEFAULT 0,
    ALTER COLUMN species_confidence_score SET NOT NULL,
    ALTER COLUMN species_confidence_source SET DEFAULT 'ai',
    ALTER COLUMN species_confidence_source SET NOT NULL;

ALTER TABLE public.species_reference_image_merian_sources
    DROP CONSTRAINT IF EXISTS species_reference_image_merian_sources_confidence_score_check;

ALTER TABLE public.species_reference_image_merian_sources
    ADD CONSTRAINT species_reference_image_merian_sources_confidence_score_check
    CHECK (species_confidence_score >= 0 AND species_confidence_score <= 1);

ALTER TABLE public.species_reference_image_merian_sources
    DROP CONSTRAINT IF EXISTS species_reference_image_merian_sources_confidence_source_check;

ALTER TABLE public.species_reference_image_merian_sources
    ADD CONSTRAINT species_reference_image_merian_sources_confidence_source_check
    CHECK (species_confidence_source IN ('ai', 'confirmed_species'));

CREATE INDEX IF NOT EXISTS idx_species_reference_image_merian_sources_confidence
    ON public.species_reference_image_merian_sources(
        species_id,
        is_promoted,
        species_confidence_source,
        species_confidence_score DESC,
        image_quality_score DESC
    );

DROP FUNCTION IF EXISTS public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN);

CREATE OR REPLACE FUNCTION public.refresh_merian_reference_images(
    p_quality_threshold INTEGER DEFAULT 90,
    p_per_species_limit INTEGER DEFAULT 8,
    p_dry_run BOOLEAN DEFAULT FALSE,
    p_species_confidence_threshold DOUBLE PRECISION DEFAULT 0.95
)
RETURNS TABLE(
    candidate_count INTEGER,
    promoted_count INTEGER,
    removed_count INTEGER,
    species_count INTEGER,
    dry_run BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
BEGIN
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
                COALESCE(s.confirmed_species_id, s.species_id) AS species_id,
                ep.id AS explore_post_id,
                s.id AS scan_id,
                ep.user_id,
                NULLIF(BTRIM(media.raw_url), '') AS image_url,
                (media.ordinality::INTEGER - 1) AS image_index,
                s.image_quality_score,
                LEAST(GREATEST(COALESCE(s.ai_confidence_score, 0), 0), 1) AS species_confidence_score,
                CASE
                    WHEN s.confirmed_species_id IS NOT NULL THEN 'confirmed_species'
                    ELSE 'ai'
                END AS species_confidence_source,
                COALESCE(NULLIF(BTRIM(u.public_author_name), ''), 'Merian community') AS author_attribution,
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
              AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
              AND s.geoprivacy <> 'private'
              AND u.is_shadowbanned = FALSE
              AND COALESCE(s.image_quality_score, -1) >= p_quality_threshold
              AND (
                  s.confirmed_species_id IS NOT NULL
                  OR COALESCE(s.ai_confidence_score, -1) >= p_species_confidence_threshold
              )
              AND NULLIF(BTRIM(media.raw_url), '') IS NOT NULL
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
            COALESCE(s.confirmed_species_id, s.species_id) AS species_id,
            ep.id AS explore_post_id,
            s.id AS scan_id,
            ep.user_id,
            NULLIF(BTRIM(media.raw_url), '') AS image_url,
            (media.ordinality::INTEGER - 1) AS image_index,
            s.image_quality_score,
            LEAST(GREATEST(COALESCE(s.ai_confidence_score, 0), 0), 1) AS species_confidence_score,
            CASE
                WHEN s.confirmed_species_id IS NOT NULL THEN 'confirmed_species'
                ELSE 'ai'
            END AS species_confidence_source,
            COALESCE(NULLIF(BTRIM(u.public_author_name), ''), 'Merian community') AS author_attribution,
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
          AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
          AND s.geoprivacy <> 'private'
          AND u.is_shadowbanned = FALSE
          AND COALESCE(s.image_quality_score, -1) >= p_quality_threshold
          AND (
              s.confirmed_species_id IS NOT NULL
              OR COALESCE(s.ai_confidence_score, -1) >= p_species_confidence_threshold
          )
          AND NULLIF(BTRIM(media.raw_url), '') IS NOT NULL
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
            'Used with permission via Merian',
            selected.author_attribution,
            (selected.species_rank::INTEGER - 1),
            v_now
        FROM selected
        ON CONFLICT (species_id, url) DO UPDATE
            SET
                source = 'merian',
                license = 'Used with permission via Merian',
                attribution = EXCLUDED.attribution,
                sort_order = EXCLUDED.sort_order,
                last_verified_at = EXCLUDED.last_verified_at
        RETURNING id, species_id, url
    ),
    link_promoted AS (
        UPDATE public.species_reference_image_merian_sources source
        SET
            reference_image_id = upserted_refs.id,
            is_promoted = TRUE,
            last_promoted_at = v_now,
            updated_at = v_now
        FROM upserted_refs
        WHERE source.species_id = upserted_refs.species_id
          AND source.image_url = upserted_refs.url
        RETURNING source.id
    ),
    demote_unselected AS (
        UPDATE public.species_reference_image_merian_sources source
        SET
            reference_image_id = NULL,
            is_promoted = FALSE,
            updated_at = v_now
        WHERE source.disqualified_at IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM upserted_refs
              WHERE upserted_refs.species_id = source.species_id
                AND upserted_refs.url = source.image_url
          )
        RETURNING source.id
    )
    SELECT
        (SELECT COUNT(*)::INTEGER FROM candidate_upsert),
        (SELECT COUNT(*)::INTEGER FROM upserted_refs),
        (SELECT COUNT(*)::INTEGER FROM deleted_refs),
        (SELECT COUNT(DISTINCT species_id)::INTEGER FROM selected),
        FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN, DOUBLE PRECISION) TO service_role;

DO $$
BEGIN
    PERFORM cron.unschedule('refresh_merian_reference_images_hourly');
EXCEPTION WHEN OTHERS THEN
    -- Ignore missing jobs so re-running the migration remains idempotent.
END;
$$;

SELECT cron.schedule(
    'refresh_merian_reference_images_hourly',
    '37 * * * *',
    $$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
        edge_endpoint TEXT;
    BEGIN
        SELECT decrypted_secret INTO project_url
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT decrypted_secret INTO service_role_key
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', true);
        END IF;

        IF service_role_key IS NULL THEN
            service_role_key := current_setting('app.settings.service_role_key', true);
        END IF;

        edge_endpoint := project_url || '/functions/v1/refresh-merian-reference-images';

        PERFORM net.http_post(
            url := edge_endpoint,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := jsonb_build_object(
                'quality_threshold', 90,
                'species_confidence_threshold', 0.95,
                'per_species_limit', 8
            )
        );
    END;
    $job$;
    $$
);

NOTIFY pgrst, 'reload schema';
