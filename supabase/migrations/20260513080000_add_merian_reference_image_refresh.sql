-- Migration: 20260513080000_add_merian_reference_image_refresh.sql
-- Description: Promotes high-quality published Explore media into public
-- species reference imagery while keeping Merian provenance private.

ALTER TABLE public.species_reference_images
    DROP CONSTRAINT IF EXISTS species_reference_images_source_check;

ALTER TABLE public.species_reference_images
    ADD CONSTRAINT species_reference_images_source_check
    CHECK (source IN ('wikipedia', 'gbif', 'merian'));

CREATE OR REPLACE FUNCTION public.public_species_reference_image_source_rank(
    image_source TEXT
)
RETURNS INTEGER
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE image_source
        WHEN 'merian' THEN 0
        WHEN 'wikipedia' THEN 1
        WHEN 'gbif' THEN 2
        ELSE 3
    END;
$$;

CREATE TABLE IF NOT EXISTS public.species_reference_image_merian_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reference_image_id UUID REFERENCES public.species_reference_images(id) ON DELETE SET NULL,
    species_id UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    explore_post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    image_index INTEGER NOT NULL,
    image_quality_score SMALLINT NOT NULL,
    author_attribution TEXT NOT NULL,
    source_shared_at TIMESTAMPTZ NOT NULL,
    is_promoted BOOLEAN NOT NULL DEFAULT FALSE,
    first_qualified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_qualified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_promoted_at TIMESTAMPTZ,
    disqualified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT species_reference_image_merian_sources_url_nonempty_check
        CHECK (BTRIM(image_url) <> ''),
    CONSTRAINT species_reference_image_merian_sources_author_nonempty_check
        CHECK (BTRIM(author_attribution) <> ''),
    CONSTRAINT species_reference_image_merian_sources_index_check
        CHECK (image_index >= 0),
    CONSTRAINT species_reference_image_merian_sources_score_check
        CHECK (image_quality_score BETWEEN 0 AND 100),
    CONSTRAINT species_reference_image_merian_sources_species_url_key
        UNIQUE (species_id, image_url)
);

CREATE INDEX IF NOT EXISTS idx_species_reference_image_merian_sources_species
    ON public.species_reference_image_merian_sources(species_id, is_promoted, image_quality_score DESC);

CREATE INDEX IF NOT EXISTS idx_species_reference_image_merian_sources_post
    ON public.species_reference_image_merian_sources(explore_post_id, image_index);

ALTER TABLE public.species_reference_image_merian_sources ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.species_reference_image_merian_sources FROM PUBLIC;
REVOKE ALL ON TABLE public.species_reference_image_merian_sources FROM anon;
REVOKE ALL ON TABLE public.species_reference_image_merian_sources FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.species_reference_image_merian_sources TO service_role;

CREATE OR REPLACE FUNCTION public.public_species_reference_image_urls(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT STRING_AGG(ref.url, ',' ORDER BY public.public_species_reference_image_source_rank(ref.source), ref.sort_order, ref.created_at, ref.id)
            FROM public.species_reference_images ref
            WHERE ref.species_id = target_species_id
        ),
        NULLIF(BTRIM(COALESCE(legacy_reference_image_url, '')), '')
    );
$$;

CREATE OR REPLACE FUNCTION public.public_species_first_reference_image_url(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT ref.url
            FROM public.species_reference_images ref
            WHERE ref.species_id = target_species_id
            ORDER BY public.public_species_reference_image_source_rank(ref.source), ref.sort_order, ref.created_at, ref.id
            LIMIT 1
        ),
        (
            SELECT NULLIF(BTRIM(split.raw_url), '')
            FROM regexp_split_to_table(COALESCE(legacy_reference_image_url, ''), '\s*,\s*')
                WITH ORDINALITY AS split(raw_url, ordinality)
            WHERE NULLIF(BTRIM(split.raw_url), '') IS NOT NULL
            ORDER BY split.ordinality
            LIMIT 1
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.replace_species_reference_images(
    p_species_id UUID,
    p_images JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_species_id IS NULL THEN
        RAISE EXCEPTION 'p_species_id is required';
    END IF;

    IF p_images IS NULL OR jsonb_typeof(p_images) <> 'array' THEN
        RAISE EXCEPTION 'p_images must be a JSON array';
    END IF;

    WITH incoming AS (
        SELECT
            NULLIF(BTRIM(image.value ->> 'url'), '') AS url,
            CASE
                WHEN image.value ->> 'source' IN ('wikipedia', 'gbif')
                    THEN image.value ->> 'source'
                ELSE 'gbif'
            END AS source,
            CASE
                WHEN COALESCE(image.value ->> 'sort_order', '') ~ '^[0-9]+$'
                    THEN GREATEST((image.value ->> 'sort_order')::INTEGER, 0)
                ELSE (image.ordinality::INTEGER - 1)
            END AS sort_order,
            CASE
                WHEN COALESCE(image.value ->> 'last_verified_at', '') <> ''
                    THEN (image.value ->> 'last_verified_at')::TIMESTAMPTZ
                ELSE NOW()
            END AS last_verified_at,
            NULLIF(BTRIM(image.value ->> 'license'), '') AS license,
            NULLIF(BTRIM(image.value ->> 'attribution'), '') AS attribution,
            CASE
                WHEN COALESCE(image.value ->> 'width', '') ~ '^[0-9]+$'
                     AND (image.value ->> 'width')::INTEGER > 0
                    THEN (image.value ->> 'width')::INTEGER
                ELSE NULL
            END AS width,
            CASE
                WHEN COALESCE(image.value ->> 'height', '') ~ '^[0-9]+$'
                     AND (image.value ->> 'height')::INTEGER > 0
                    THEN (image.value ->> 'height')::INTEGER
                ELSE NULL
            END AS height
        FROM jsonb_array_elements(p_images) WITH ORDINALITY AS image(value, ordinality)
    ),
    deduped AS (
        SELECT DISTINCT ON (url)
            url,
            source,
            sort_order,
            last_verified_at,
            license,
            attribution,
            width,
            height
        FROM incoming
        WHERE url IS NOT NULL
        ORDER BY url, sort_order
    ),
    delete_stale_unlicensed AS (
        DELETE FROM public.species_reference_images ref
        WHERE ref.species_id = p_species_id
          AND ref.source <> 'merian'
          AND ref.license IS NULL
          AND ref.attribution IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM deduped incoming_image
              WHERE incoming_image.url = ref.url
          )
        RETURNING 1
    ),
    upserted AS (
        INSERT INTO public.species_reference_images (
            species_id,
            url,
            source,
            license,
            attribution,
            width,
            height,
            sort_order,
            last_verified_at
        )
        SELECT
            p_species_id,
            incoming_image.url,
            incoming_image.source,
            COALESCE(incoming_image.license, existing.license),
            COALESCE(incoming_image.attribution, existing.attribution),
            COALESCE(incoming_image.width, existing.width),
            COALESCE(incoming_image.height, existing.height),
            incoming_image.sort_order,
            incoming_image.last_verified_at
        FROM deduped incoming_image
        LEFT JOIN public.species_reference_images existing
            ON existing.species_id = p_species_id
           AND existing.url = incoming_image.url
        ON CONFLICT (species_id, url) DO UPDATE
            SET
                source = CASE
                    WHEN public.species_reference_images.source = 'merian'
                        THEN public.species_reference_images.source
                    ELSE EXCLUDED.source
                END,
                license = COALESCE(public.species_reference_images.license, EXCLUDED.license),
                attribution = COALESCE(public.species_reference_images.attribution, EXCLUDED.attribution),
                width = COALESCE(public.species_reference_images.width, EXCLUDED.width),
                height = COALESCE(public.species_reference_images.height, EXCLUDED.height),
                sort_order = CASE
                    WHEN public.species_reference_images.source = 'merian'
                        THEN public.species_reference_images.sort_order
                    ELSE EXCLUDED.sort_order
                END,
                last_verified_at = CASE
                    WHEN public.species_reference_images.source = 'merian'
                        THEN public.species_reference_images.last_verified_at
                    ELSE EXCLUDED.last_verified_at
                END
        RETURNING url
    ),
    preserved_curated AS (
        SELECT
            ref.id,
            ROW_NUMBER() OVER (ORDER BY ref.sort_order, ref.created_at, ref.id) AS row_number
        FROM public.species_reference_images ref
        WHERE ref.species_id = p_species_id
          AND ref.source <> 'merian'
          AND (ref.license IS NOT NULL OR ref.attribution IS NOT NULL)
          AND NOT EXISTS (
              SELECT 1
              FROM deduped incoming_image
              WHERE incoming_image.url = ref.url
          )
    )
    UPDATE public.species_reference_images ref
    SET sort_order = 1000 + preserved_curated.row_number
    FROM preserved_curated
    WHERE ref.id = preserved_curated.id;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_species_reference_images(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.replace_species_reference_images(UUID, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.refresh_merian_reference_images(
    p_quality_threshold INTEGER DEFAULT 90,
    p_per_species_limit INTEGER DEFAULT 8,
    p_dry_run BOOLEAN DEFAULT FALSE
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
              AND NULLIF(BTRIM(media.raw_url), '') IS NOT NULL
        ),
        deduped AS (
            SELECT *
            FROM (
                SELECT
                    raw_candidates.*,
                    ROW_NUMBER() OVER (
                        PARTITION BY species_id, image_url
                        ORDER BY image_quality_score DESC, source_shared_at DESC, image_index, explore_post_id
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
                    ORDER BY image_quality_score DESC, source_shared_at DESC, image_index, image_url
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
          AND NULLIF(BTRIM(media.raw_url), '') IS NOT NULL
    ),
    deduped AS (
        SELECT *
        FROM (
            SELECT
                raw_candidates.*,
                ROW_NUMBER() OVER (
                    PARTITION BY species_id, image_url
                    ORDER BY image_quality_score DESC, source_shared_at DESC, image_index, explore_post_id
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
                ORDER BY image_quality_score DESC, source_shared_at DESC, image_index, image_url
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

REVOKE ALL ON FUNCTION public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN) TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

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
                'per_species_limit', 8
            )
        );
    END;
    $job$;
    $$
);
