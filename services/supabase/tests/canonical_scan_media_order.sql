\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(7);

SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.align_scan_media_asset_order(uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.align_scan_media_asset_order(uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.align_scan_media_asset_order(uuid)',
        'EXECUTE'
    ),
    'canonical order helper is not API executable'
);

SELECT extensions.ok(
    (
        SELECT COALESCE(routine.proconfig, ARRAY[]::TEXT[])
        FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_namespace AS namespace
          ON namespace.oid = routine.pronamespace
        WHERE namespace.nspname = 'public'
          AND routine.proname = 'refresh_scan_media_assets'
          AND pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(routine.oid)
              = 'target_scan_id uuid'
    ) @> ARRAY['search_path=""']::TEXT[]
    AND pg_catalog.PG_GET_FUNCTIONDEF(
        'public.refresh_scan_media_assets(uuid)'::REGPROCEDURE
    ) LIKE '%internal.require_service_role()%'
    AND pg_catalog.PG_GET_FUNCTIONDEF(
        'public.refresh_scan_media_assets(uuid)'::REGPROCEDURE
    ) LIKE '%internal.align_scan_media_asset_order(target_scan_id)%',
    'service-only refresh keeps its guard and canonical order step'
);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-4000-8000-00000000c101'::UUID,
    'authenticated',
    'authenticated',
    'canonical-media-order@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-4000-8000-00000000c101',
    'canonical-media-order@naturebook.invalid',
    'canonical_media_order',
    'Canonical Media',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    image_storage_urls,
    video_storage_urls,
    audio_storage_urls,
    captured_media
)
VALUES (
    '00000000-0000-4000-8000-00000000c111',
    '00000000-0000-4000-8000-00000000c101',
    0.9,
    ARRAY['https://media.merian.app/canonical-image.webp'],
    ARRAY['https://media.merian.app/canonical-video.mp4'],
    ARRAY['https://media.merian.app/canonical-audio.wav'],
    '[
      {"description":{"_0":{"freeText":"Before audio"}}},
      {"audio":{"_0":{"storage":"remoteURL","path":"https://media.merian.app/canonical-audio.wav","sourceIndex":0}}},
      {"image":{"_0":{"storage":"remoteURL","path":"https://media.merian.app/canonical-image.webp"}}},
      {"description":{"_0":{"freeText":"Before video"}}},
      {"video":{"_0":{"video":{"storage":"remoteURL","path":"https://media.merian.app/canonical-video.mp4"}}}}
    ]'::JSONB
);

SELECT public.refresh_scan_media_assets(
    '00000000-0000-4000-8000-00000000c111'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.ARRAY_AGG(
            asset.kind::TEXT || ':' || asset.order_index::TEXT
            ORDER BY asset.order_index
        )
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = '00000000-0000-4000-8000-00000000c111'
          AND asset.status = 'ready'
          AND asset.source = 'scan_refresh'
    ),
    ARRAY['audio:1', 'image:2', 'video:4']::TEXT[],
    'normalized media rows retain captured_media ordinals and description gaps'
);

SELECT extensions.is(
    (
        SELECT COUNT(*)::INTEGER
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = '00000000-0000-4000-8000-00000000c111'
          AND asset.kind IN ('image', 'video', 'audio')
          AND asset.status = 'ready'
          AND asset.source = 'scan_refresh'
    ),
    3,
    'canonical alignment neither drops nor duplicates owner media'
);

-- Reproduce both collision classes that the original helper missed. The ready
-- display row is moved away from its canonical position, while legal non-ready
-- rows occupy the canonical destination and the old temporary destination.
UPDATE public.scan_media_assets AS asset
SET order_index = 0
WHERE asset.scan_id = '00000000-0000-4000-8000-00000000c111'
  AND asset.status = 'ready'
  AND asset.source = 'scan_refresh'
  AND asset.role = 'display';

INSERT INTO public.scan_media_assets (
    id,
    scan_id,
    client_scan_id,
    user_id,
    kind,
    role,
    status,
    source,
    url,
    storage_key,
    order_index,
    failure_reason
)
VALUES
    (
        '00000000-0000-4000-8000-00000000c121',
        '00000000-0000-4000-8000-00000000c111',
        '00000000-0000-4000-8000-00000000c111',
        '00000000-0000-4000-8000-00000000c101',
        'image',
        'display',
        'staged',
        'scan_refresh',
        NULL,
        'scan-media/canonical-staged.webp',
        2,
        NULL
    ),
    (
        '00000000-0000-4000-8000-00000000c122',
        '00000000-0000-4000-8000-00000000c111',
        '00000000-0000-4000-8000-00000000c111',
        '00000000-0000-4000-8000-00000000c101',
        'image',
        'display',
        'failed',
        'scan_refresh',
        NULL,
        'scan-media/canonical-failed.webp',
        7,
        'fixture_failure'
    );

SELECT internal.align_scan_media_asset_order(
    '00000000-0000-4000-8000-00000000c111'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.ARRAY_AGG(
            asset.kind::TEXT || ':' || asset.order_index::TEXT
            ORDER BY asset.order_index
        )
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = '00000000-0000-4000-8000-00000000c111'
          AND asset.status = 'ready'
          AND asset.source = 'scan_refresh'
    ),
    ARRAY['audio:1', 'image:2', 'video:4']::TEXT[],
    'ready media realigns when non-ready rows occupy canonical and temporary positions'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.ARRAY_AGG(
            asset.status::TEXT || ':' || asset.order_index::TEXT
            ORDER BY asset.order_index
        )
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = '00000000-0000-4000-8000-00000000c111'
          AND asset.status <> 'ready'
          AND asset.source = 'scan_refresh'
          AND asset.role = 'display'
    ),
    ARRAY['staged:5', 'failed:6']::TEXT[],
    'non-ready generated lifecycle rows remain ordered after ready media'
);

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    image_storage_urls,
    captured_media
)
VALUES (
    '00000000-0000-4000-8000-00000000c112',
    '00000000-0000-4000-8000-00000000c101',
    0.9,
    ARRAY['https://media.merian.app/legacy-image.webp'],
    NULL
);

SELECT extensions.is(
    (
        SELECT pg_catalog.ARRAY_AGG(
            asset.kind::TEXT || ':' || asset.order_index::TEXT
            ORDER BY asset.order_index
        )
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = '00000000-0000-4000-8000-00000000c112'
          AND asset.status = 'ready'
          AND asset.source = 'scan_refresh'
    ),
    ARRAY['image:0']::TEXT[],
    'legacy array refresh bypasses canonical alignment without nulling order'
);

SELECT * FROM extensions.finish();
ROLLBACK;
