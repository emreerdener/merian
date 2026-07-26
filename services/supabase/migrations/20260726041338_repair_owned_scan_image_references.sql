-- Atomically replace a missing durable scan-image URL with a newly promoted
-- object. The Edge function verifies both objects in R2 before invoking this
-- service-only metadata repair.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

CREATE OR REPLACE FUNCTION internal.replace_jsonb_string_exact(
    p_value JSONB,
    p_source TEXT,
    p_replacement TEXT
)
RETURNS JSONB
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT CASE pg_catalog.JSONB_TYPEOF(p_value)
        WHEN 'string' THEN
            CASE
                WHEN p_value #>> '{}' = p_source
                    THEN pg_catalog.TO_JSONB(p_replacement)
                ELSE p_value
            END
        WHEN 'array' THEN (
            SELECT COALESCE(
                pg_catalog.JSONB_AGG(
                    internal.replace_jsonb_string_exact(
                        array_item.value,
                        p_source,
                        p_replacement
                    )
                    ORDER BY array_item.ordinality
                ),
                '[]'::JSONB
            )
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_value)
                WITH ORDINALITY AS array_item(value, ordinality)
        )
        WHEN 'object' THEN (
            SELECT COALESCE(
                pg_catalog.JSONB_OBJECT_AGG(
                    object_item.key,
                    internal.replace_jsonb_string_exact(
                        object_item.value,
                        p_source,
                        p_replacement
                    )
                ),
                '{}'::JSONB
            )
            FROM pg_catalog.JSONB_EACH(p_value)
                AS object_item(key, value)
        )
        ELSE p_value
    END;
$$;

COMMENT ON FUNCTION internal.replace_jsonb_string_exact(JSONB, TEXT, TEXT) IS
    'Private immutable helper for exact scan captured-media URL replacement.';

REVOKE ALL ON FUNCTION internal.replace_jsonb_string_exact(JSONB, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.repair_owned_scan_image_reference(
    p_user_id UUID,
    p_source_url TEXT,
    p_replacement_url TEXT
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    repaired_scan_ids UUID[];
    updated_scan_count INTEGER := 0;
    updated_post_media_count INTEGER := 0;
    replacement_storage_key TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_source_url IS NULL
       OR p_replacement_url IS NULL
       OR p_source_url = p_replacement_url
       OR p_source_url !~
            '^https://media[.]merian[.]app/public_uploads/(free|pro)/[^/?#]+/[^/?#]+$'
       OR (
            p_replacement_url NOT LIKE
                'https://media.merian.app/public_uploads/free/'
                || p_user_id::TEXT || '/%'
            AND p_replacement_url NOT LIKE
                'https://media.merian.app/public_uploads/pro/'
                || p_user_id::TEXT || '/%'
       )
       OR p_replacement_url LIKE '%?%'
       OR p_replacement_url LIKE '%#%' THEN
        RAISE EXCEPTION 'scan_image_repair_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.ARRAY_AGG(scans.id ORDER BY scans.id)
    INTO repaired_scan_ids
    FROM public.scans AS scans
    WHERE scans.user_id = p_user_id
      AND NOT scans.is_tombstoned
      AND p_source_url = ANY(scans.image_storage_urls);

    IF COALESCE(
        pg_catalog.CARDINALITY(repaired_scan_ids),
        0
    ) = 0 AND NOT EXISTS (
        SELECT 1
        FROM public.explore_post_media AS post_media
        INNER JOIN public.explore_posts AS explore_post
            ON explore_post.id = post_media.post_id
        WHERE explore_post.user_id = p_user_id
          AND (
              post_media.url = p_source_url
              OR post_media.thumbnail_url = p_source_url
          )
    ) THEN
        RAISE EXCEPTION 'scan_image_repair_source_not_owned'
            USING ERRCODE = 'P0002';
    END IF;

    IF COALESCE(
        pg_catalog.CARDINALITY(repaired_scan_ids),
        0
    ) > 0 THEN
        UPDATE public.scans AS scans
        SET image_storage_urls = ARRAY(
                SELECT CASE
                    WHEN image_url = p_source_url THEN p_replacement_url
                    ELSE image_url
                END
                FROM pg_catalog.UNNEST(scans.image_storage_urls)
                    WITH ORDINALITY AS image(image_url, ordinality)
                ORDER BY image.ordinality
            ),
            captured_media = CASE
                WHEN scans.captured_media IS NULL THEN NULL
                ELSE internal.replace_jsonb_string_exact(
                    scans.captured_media,
                    p_source_url,
                    p_replacement_url
                )
            END
        WHERE scans.id = ANY(repaired_scan_ids);

        GET DIAGNOSTICS updated_scan_count = ROW_COUNT;
    END IF;

    replacement_storage_key := pg_catalog.SUBSTRING(
        p_replacement_url,
        pg_catalog.CHAR_LENGTH('https://media.merian.app/') + 1
    );

    UPDATE public.scan_media_assets AS media_asset
    SET url = CASE
            WHEN media_asset.url = p_source_url
                THEN p_replacement_url
            ELSE media_asset.url
        END,
        thumbnail_url = CASE
            WHEN media_asset.thumbnail_url = p_source_url
                THEN p_replacement_url
            ELSE media_asset.thumbnail_url
        END,
        storage_key = CASE
            WHEN media_asset.url IN (p_source_url, p_replacement_url)
                THEN replacement_storage_key
            ELSE media_asset.storage_key
        END,
        failure_reason = NULL,
        updated_at = pg_catalog.NOW(),
        metadata = COALESCE(media_asset.metadata, '{}'::JSONB)
            || pg_catalog.JSONB_BUILD_OBJECT(
                'repair_source_url',
                p_source_url,
                'repaired_at',
                pg_catalog.NOW()
            )
    WHERE media_asset.user_id = p_user_id
      AND (
          media_asset.url IN (p_source_url, p_replacement_url)
          OR media_asset.thumbnail_url IN (p_source_url, p_replacement_url)
      );

    UPDATE public.explore_post_media AS post_media
    SET url = CASE
            WHEN post_media.url = p_source_url
                THEN p_replacement_url
            ELSE post_media.url
        END,
        thumbnail_url = CASE
            WHEN post_media.thumbnail_url = p_source_url
                THEN p_replacement_url
            ELSE post_media.thumbnail_url
        END,
        updated_at = pg_catalog.NOW()
    FROM public.explore_posts AS explore_post
    WHERE explore_post.id = post_media.post_id
      AND explore_post.user_id = p_user_id
      AND (
          post_media.url = p_source_url
          OR post_media.thumbnail_url = p_source_url
      );

    GET DIAGNOSTICS updated_post_media_count = ROW_COUNT;

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'updated_scan_count',
        updated_scan_count,
        'updated_post_media_count',
        updated_post_media_count
    );
END;
$$;

COMMENT ON FUNCTION public.repair_owned_scan_image_reference(
    UUID,
    TEXT,
    TEXT
) IS
    'Service-only exact replacement of a verified-missing owned scan image URL across scan, normalized-media, and Explore snapshot metadata.';

REVOKE ALL ON FUNCTION public.repair_owned_scan_image_reference(
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.repair_owned_scan_image_reference(
    UUID,
    TEXT,
    TEXT
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.repair_owned_scan_image_reference(uuid,text,text)',
    'Atomically replaces a verified-missing owned scan image across durable metadata.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;
