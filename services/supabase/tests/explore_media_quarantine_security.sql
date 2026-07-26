\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(16);

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
    '00000000-0000-4000-8000-00000000e701',
    'authenticated',
    'authenticated',
    'explore-media-health@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000e701',
    'explore-media-health@naturebook.invalid',
    'explore_media_health_e701',
    'Explore Media Health',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email;

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus,
    native_region
)
VALUES (
    '00000000-0000-4000-8000-00000000e711',
    'Contractus mediaperditus',
    '{"en":"Media health contract species"}'::JSONB,
    'Animalia',
    'Chordata',
    'Aves',
    'Passeriformes',
    'Contractidae',
    'Contractus',
    'Test region'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    ai_confidence_score,
    geoprivacy
)
VALUES (
    '00000000-0000-4000-8000-00000000e721',
    '00000000-0000-4000-8000-00000000e701',
    '00000000-0000-4000-8000-00000000e711',
    ARRAY[
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/one.webp',
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/two.webp'
    ]::TEXT[],
    0.94,
    'obscured'
);

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    audio_storage_urls,
    ai_confidence_score,
    geoprivacy
)
VALUES (
    '00000000-0000-4000-8000-00000000e722',
    '00000000-0000-4000-8000-00000000e701',
    '00000000-0000-4000-8000-00000000e711',
    ARRAY[]::TEXT[],
    ARRAY[
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/audio.wav'
    ]::TEXT[],
    0.91,
    'private'
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    species_common_name,
    location_sharing,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000e731',
    '00000000-0000-4000-8000-00000000e701',
    '00000000-0000-4000-8000-00000000e721',
    'Media health contract species',
    'obscured',
    pg_catalog.NOW()
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    species_common_name,
    location_sharing,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000e732',
    '00000000-0000-4000-8000-00000000e701',
    '00000000-0000-4000-8000-00000000e722',
    'Audio media health contract species',
    'private',
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
VALUES
    (
        '00000000-0000-4000-8000-00000000e741',
        '00000000-0000-4000-8000-00000000e731',
        'image',
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/one.webp',
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/one.webp',
        0
    ),
    (
        '00000000-0000-4000-8000-00000000e742',
        '00000000-0000-4000-8000-00000000e731',
        'image',
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/two.webp',
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/two.webp',
        1
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
    '00000000-0000-4000-8000-00000000e743',
    '00000000-0000-4000-8000-00000000e732',
    'audio',
    'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e701/audio.wav',
    NULL,
    0
);

UPDATE public.explore_post_media
SET health_status = 'missing',
    missing_confirmed_at = pg_catalog.NOW(),
    consecutive_missing_checks = 2
WHERE id = '00000000-0000-4000-8000-00000000e743';

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)
        FROM public.get_explore_notifications(
            '00000000-0000-4000-8000-00000000e701',
            100
        ) AS notification
        WHERE notification.post_id =
                '00000000-0000-4000-8000-00000000e732'
          AND notification.type = 'media_missing'
    ),
    1::BIGINT,
    'owner media incidents remain visible for audio-only/private scan metadata'
);

SELECT extensions.is(
    (
        SELECT media_health_status || ':' || total_media_count || ':'
            || missing_media_count
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
    ),
    'healthy:2:0',
    'new media snapshots initialize a healthy aggregate'
);

UPDATE public.explore_post_media
SET health_status = 'missing',
    missing_confirmed_at = pg_catalog.NOW(),
    consecutive_missing_checks = 2
WHERE id = '00000000-0000-4000-8000-00000000e741';

SELECT extensions.is(
    (
        SELECT media_health_status
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
    ),
    'degraded',
    'one confirmed-missing item degrades rather than hides the post'
);

SELECT extensions.is(
    pg_catalog.JSONB_ARRAY_LENGTH(
        public.explore_post_media_items(
            '00000000-0000-4000-8000-00000000e731'
        )
    ),
    1,
    'confirmed-missing media is omitted from the public media list'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)
        FROM public.explore_projected_post_cards(
            '00000000-0000-4000-8000-00000000e701'
        )
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
    ),
    1::BIGINT,
    'a degraded post remains in the canonical public projection'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.explore_post_notifications
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
          AND type = 'media_missing'
    ),
    'the owner receives one durable incident notification'
);

UPDATE public.explore_post_media
SET health_status = 'missing',
    missing_confirmed_at = pg_catalog.NOW(),
    consecutive_missing_checks = 2
WHERE id = '00000000-0000-4000-8000-00000000e742';

SELECT extensions.is(
    (
        SELECT media_health_status
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
    ),
    'quarantined',
    'all confirmed-missing items reversibly quarantine the post'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)
        FROM public.explore_projected_post_cards(
            '00000000-0000-4000-8000-00000000e701'
        )
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
    ),
    0::BIGINT,
    'a quarantined post is absent from the public projection'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)
        FROM public.get_explore_post_detail(
            '00000000-0000-4000-8000-00000000e701',
            '00000000-0000-4000-8000-00000000e731'
        )
    ),
    0::BIGINT,
    'a quarantined post is also absent from the independently fetched detail projection'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
          AND unshared_at IS NULL
    ),
    'system quarantine preserves the post row and author publication intent'
);

SELECT public.refresh_explore_post_media(
    '00000000-0000-4000-8000-00000000e731'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)
        FROM public.explore_post_media
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
          AND health_status = 'missing'
    ),
    2::BIGINT,
    'a snapshot rebuild preserves health by stable post, kind, and URL'
);

SELECT extensions.is(
    (
        SELECT media_health_status
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
    ),
    'quarantined',
    'a snapshot rebuild cannot accidentally clear quarantine'
);

UPDATE public.explore_post_media
SET health_status = 'healthy',
    missing_first_observed_at = NULL,
    missing_confirmed_at = NULL,
    consecutive_missing_checks = 0
WHERE post_id = '00000000-0000-4000-8000-00000000e731'
  AND url LIKE '%/one.webp';

SELECT extensions.ok(
    (
        SELECT media_health_status = 'degraded'
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
    )
    AND EXISTS (
        SELECT 1
        FROM public.explore_projected_post_cards(
            '00000000-0000-4000-8000-00000000e701'
        )
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
    ),
    'repairing one item automatically republishes the usable remainder'
);

UPDATE public.explore_post_media
SET health_status = 'healthy',
    missing_first_observed_at = NULL,
    missing_confirmed_at = NULL,
    consecutive_missing_checks = 0
WHERE post_id = '00000000-0000-4000-8000-00000000e731'
  AND url LIKE '%/two.webp';

SELECT extensions.is(
    (
        SELECT media_health_status
        FROM public.explore_posts
        WHERE id = '00000000-0000-4000-8000-00000000e731'
    ),
    'healthy',
    'repairing all items automatically clears system quarantine'
);

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.explore_post_notifications
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
          AND type = 'media_missing'
    )
    AND EXISTS (
        SELECT 1
        FROM public.explore_post_notifications
        WHERE post_id = '00000000-0000-4000-8000-00000000e731'
          AND type = 'media_restored'
    ),
    'automatic recovery replaces the active incident with an in-app restore event'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.explore_media_health_check_claims',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.explore_media_health_history',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_explore_media_health_checks(integer,integer)',
        'EXECUTE'
    )
    AND pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.record_explore_media_health_check(uuid,uuid,text,integer,integer)',
        'EXECUTE'
    )
    AND pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_owned_explore_media_incidents(uuid)',
        'EXECUTE'
    ),
    'worker internals stay private while owner and service boundaries remain explicit'
);

SELECT * FROM extensions.finish();
ROLLBACK;
