\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(4);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000601',
    'authenticated',
    'authenticated',
    'scan-image-repair@naturebook.invalid',
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
    '00000000-0000-0000-0000-000000000601',
    'scan-image-repair@naturebook.invalid',
    'scan_image_repair_601',
    'Scan Image Repair',
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
    image_storage_urls,
    captured_media,
    ai_confidence_score
)
VALUES (
    '00000000-0000-0000-0000-000000000611',
    '00000000-0000-0000-0000-000000000601',
    ARRAY[
        'https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/missing.webp',
        'https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/healthy.webp'
    ]::TEXT[],
    '[
      {
        "image": {
          "_0": {
            "path": "https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/missing.webp",
            "caption": "missing.webp must not be partially replaced"
          }
        }
      }
    ]'::JSONB,
    0.91
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    location_sharing,
    shared_at
)
VALUES (
    '00000000-0000-0000-0000-000000000621',
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000611',
    'obscured',
    pg_catalog.NOW()
);

INSERT INTO public.explore_post_media (
    id,
    post_id,
    kind,
    url,
    thumbnail_url,
    order_index
)
VALUES (
    '00000000-0000-0000-0000-000000000631',
    '00000000-0000-0000-0000-000000000621',
    'image',
    'https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/missing.webp',
    'https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/missing.webp',
    0
);

SET LOCAL ROLE service_role;
SELECT public.repair_owned_scan_image_reference(
    '00000000-0000-0000-0000-000000000601',
    'https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/missing.webp',
    'https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT image_storage_urls
        FROM public.scans
        WHERE id = '00000000-0000-0000-0000-000000000611'
    ),
    ARRAY[
        'https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp',
        'https://media.merian.app/public_uploads/free/00000000-0000-0000-0000-000000000601/healthy.webp'
    ]::TEXT[],
    'scan image URL order is preserved while the missing reference is replaced'
);

SELECT extensions.is(
    (
        SELECT captured_media #>> '{0,image,_0,path}'
        FROM public.scans
        WHERE id = '00000000-0000-0000-0000-000000000611'
    ),
    'https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp',
    'captured-media exact string references are replaced'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.scan_media_assets
        WHERE scan_id = '00000000-0000-0000-0000-000000000611'
          AND url = 'https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp'
          AND storage_key = 'public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp'
    ),
    'normalized scan media points at the repaired durable object'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.explore_post_media
        WHERE id = '00000000-0000-0000-0000-000000000631'
          AND url = 'https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp'
          AND thumbnail_url = 'https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000601/repaired.webp'
    ),
    'the owned Explore media snapshot is repaired atomically'
);

SELECT * FROM extensions.finish();
ROLLBACK;
