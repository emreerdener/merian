-- Migration: 20260513070000_add_species_content_refresh_worker_schedule.sql
-- Description: Adds the transactional reference-image sync helper used by the
-- scheduled species content refresh worker, then schedules the worker through
-- pg_cron/pg_net.

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
                source = EXCLUDED.source,
                license = COALESCE(public.species_reference_images.license, EXCLUDED.license),
                attribution = COALESCE(public.species_reference_images.attribution, EXCLUDED.attribution),
                width = COALESCE(public.species_reference_images.width, EXCLUDED.width),
                height = COALESCE(public.species_reference_images.height, EXCLUDED.height),
                sort_order = EXCLUDED.sort_order,
                last_verified_at = EXCLUDED.last_verified_at
        RETURNING url
    ),
    preserved_curated AS (
        SELECT
            ref.id,
            ROW_NUMBER() OVER (ORDER BY ref.sort_order, ref.created_at, ref.id) AS row_number
        FROM public.species_reference_images ref
        WHERE ref.species_id = p_species_id
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

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

DO $$
BEGIN
    PERFORM cron.unschedule('refresh_species_content_hourly');
EXCEPTION WHEN OTHERS THEN
    -- Ignore missing jobs so re-running the migration remains idempotent.
END;
$$;

SELECT cron.schedule(
    'refresh_species_content_hourly',
    '17 * * * *',
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

        edge_endpoint := project_url || '/functions/v1/refresh-species-content';

        PERFORM net.http_post(
            url := edge_endpoint,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := jsonb_build_object('limit', 25)
        );
    END;
    $job$;
    $$
);
