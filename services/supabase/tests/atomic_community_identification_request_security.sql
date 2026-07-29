\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(25);

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
    '00000000-0000-4000-8000-00000000e201'::UUID,
    'authenticated',
    'authenticated',
    'atomic-community@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000e201',
    'atomic-community@naturebook.invalid',
    'atomic_community_e201',
    'Atomic Community',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;

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
    '00000000-0000-4000-8000-00000000e202',
    'Testus communis e202',
    '{"en":"Atomic community species"}'::JSONB,
    'Animalia',
    'Arthropoda',
    'Insecta',
    'Lepidoptera',
    'Nymphalidae',
    'Testus',
    'Test fixture'
);

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    geoprivacy,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES
(
    '00000000-0000-4000-8000-00000000e210',
    '00000000-0000-4000-8000-00000000e201',
    '00000000-0000-4000-8000-00000000e202',
    ARRAY[
        'https://media.merian.app/public_uploads/free/'
        || '00000000-0000-4000-8000-00000000e201/'
        || '00000000-0000-4000-8000-00000000e230.webp'
    ],
    'obscured',
    0.95,
    pg_catalog.NOW(),
    TRUE
),
(
    '00000000-0000-4000-8000-00000000e220',
    '00000000-0000-4000-8000-00000000e201',
    '00000000-0000-4000-8000-00000000e202',
    ARRAY[
        'https://media.merian.app/public_uploads/free/'
        || '00000000-0000-4000-8000-00000000e201/'
        || '00000000-0000-4000-8000-00000000e231.webp'
    ],
    'private',
    0.94,
    pg_catalog.NOW(),
    TRUE
);

SELECT public.sync_taxon_nodes_from_species_dictionary();

CREATE TEMPORARY TABLE fixture_community_taxon AS
SELECT taxon_node.id, taxon_node.taxonomy_version_id
FROM public.taxon_nodes AS taxon_node
WHERE taxon_node.species_id =
    '00000000-0000-4000-8000-00000000e202'
ORDER BY taxon_node.created_at DESC, taxon_node.id DESC
LIMIT 1;
GRANT SELECT ON fixture_community_taxon TO service_role;

SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_community_identification_atomically(uuid,uuid,text,text,text,jsonb,uuid,uuid)',
        'EXECUTE'
    ),
    'anonymous callers cannot execute atomic Community creation'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_community_identification_atomically(uuid,uuid,text,text,text,jsonb,uuid,uuid)',
        'EXECUTE'
    ),
    'authenticated callers cannot execute atomic Community creation'
);
SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_community_identification_atomically(uuid,uuid,text,text,text,jsonb,uuid,uuid)',
        'EXECUTE'
    ),
    'service-role callers can execute atomic Community creation'
);
SELECT extensions.ok(
    NOT (
        SELECT routine.prosecdef
        FROM pg_catalog.PG_PROC AS routine
        WHERE routine.oid = pg_catalog.TO_REGPROCEDURE(
            'public.request_community_identification_atomically(uuid,uuid,text,text,text,jsonb,uuid,uuid)'
        )
    ),
    'atomic Community creation retains invoker privileges'
);
SELECT extensions.ok(
    pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_community_requests',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_community_requests',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_community_requests',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.taxon_nodes',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_identifications',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_identifications',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.community_consensus_jobs',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.community_consensus_jobs',
        'DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.explore_community_requests',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.explore_community_requests',
        'INSERT'
    ),
    'Community invoker has its exact relational privileges without browser writes'
);

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.request_community_identification_atomically(
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            '[]'::JSONB,
            NULL,
            NULL
        )
    $statement$,
    '22023',
    'Community request identifiers are required',
    'no-write validation rejects missing required identifiers'
);

SELECT extensions.is(
    public.request_community_identification_atomically(
        '00000000-0000-4000-8000-00000000e210',
        '00000000-0000-4000-8000-00000000e201',
        'Please check this observation.',
        NULL,
        'Atomic community species',
        '[
          {
            "kind":"image",
            "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e230.webp",
            "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e230.webp",
            "order_index":0,
            "duration_seconds":null,
            "has_audio":false
          }
        ]'::JSONB,
        (SELECT taxon.id FROM fixture_community_taxon AS taxon),
        (
            SELECT taxon.taxonomy_version_id
            FROM fixture_community_taxon AS taxon
        )
    ) ->> 'status',
    'needs_id',
    'atomic Community creation returns hidden needs-ID state'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT community_request.scan_id::TEXT
        FROM public.explore_community_requests AS community_request
        WHERE community_request.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    '00000000-0000-4000-8000-00000000e210',
    'atomic Community response persists the exact scan identity'
);
SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.explore_community_requests AS community_request
        INNER JOIN fixture_community_taxon AS taxon
            ON taxon.id = community_request.initial_taxon_node_id
           AND taxon.taxonomy_version_id =
               community_request.taxonomy_version_id
        WHERE community_request.scan_id =
                '00000000-0000-4000-8000-00000000e210'
          AND community_request.requested_by =
                '00000000-0000-4000-8000-00000000e201'
          AND community_request.status = 'needs_id'
          AND community_request.withdrawn_at IS NULL
    ),
    'request owner and pinned taxon match the locked scan'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_posts AS post
        WHERE post.scan_id =
                '00000000-0000-4000-8000-00000000e210'
          AND post.user_id =
                '00000000-0000-4000-8000-00000000e201'
          AND post.unshared_at IS NULL
    ),
    1,
    'atomic Community creation writes exactly one active owner post'
);
SELECT extensions.is(
    (
        SELECT media.url
        FROM public.explore_post_media AS media
        INNER JOIN public.explore_posts AS post
            ON post.id = media.post_id
        WHERE post.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    'https://media.merian.app/public_uploads/free/'
    || '00000000-0000-4000-8000-00000000e201/'
    || '00000000-0000-4000-8000-00000000e230.webp',
    'atomic Community creation writes the complete owner media snapshot'
);
SELECT extensions.is(
    (
        SELECT projection.projection_state::TEXT
        FROM public.explore_observation_projection AS projection
        INNER JOIN public.explore_posts AS post
            ON post.id = projection.post_id
        WHERE post.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    'community_needs_id',
    'new Community state is hidden from normal Explore projection'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.request_community_identification_atomically(
        '00000000-0000-4000-8000-00000000e210',
        '00000000-0000-4000-8000-00000000e201',
        'A duplicate request.',
        'open',
        'Replacement should not publish',
        '[
          {
            "kind":"image",
            "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e230.webp",
            "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e230.webp",
            "order_index":0,
            "duration_seconds":null,
            "has_audio":false
          }
        ]'::JSONB,
        (SELECT taxon.id FROM fixture_community_taxon AS taxon),
        (
            SELECT taxon.taxonomy_version_id
            FROM fixture_community_taxon AS taxon
        )
    ) ->> 'id',
    (
        SELECT community_request.id::TEXT
        FROM public.explore_community_requests AS community_request
        WHERE community_request.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    'duplicate Community creation returns the authoritative request'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_community_requests AS community_request
        WHERE community_request.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    1,
    'duplicate Community creation does not add request rows'
);

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        UPDATE public.explore_posts AS post
        SET shared_at = pg_catalog.CLOCK_TIMESTAMP(),
            unshared_at = NULL
        WHERE post.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    $statement$,
    'P0001',
    'Wait for the community to identify this request before sharing it to Explore.',
    'write-time guard rejects direct sharing during needs-ID state'
);
RESET ROLE;

UPDATE public.explore_community_requests AS community_request
SET status = 'withdrawn',
    current_community_taxon_node_id =
        community_request.initial_taxon_node_id,
    resolved_taxon_node_id = community_request.initial_taxon_node_id,
    resolved_observation_taxon_node_id =
        community_request.initial_taxon_node_id,
    consensus_score = 0.95,
    consensus_identification_count = 7,
    consensus_rank = 'species',
    resolved_at = pg_catalog.CLOCK_TIMESTAMP(),
    withdrawn_at = pg_catalog.CLOCK_TIMESTAMP(),
    explore_published_at = pg_catalog.CLOCK_TIMESTAMP(),
    consensus_processing_state = 'processing',
    updated_at = pg_catalog.CLOCK_TIMESTAMP()
WHERE community_request.scan_id =
    '00000000-0000-4000-8000-00000000e210';

INSERT INTO public.explore_identifications (
    request_id,
    post_id,
    user_id,
    taxon_node_id,
    taxonomy_version_id,
    reasoning
)
SELECT
    community_request.id,
    community_request.post_id,
    community_request.requested_by,
    community_request.initial_taxon_node_id,
    community_request.taxonomy_version_id,
    'Retained audit vote'
FROM public.explore_community_requests AS community_request
WHERE community_request.scan_id =
    '00000000-0000-4000-8000-00000000e210';

INSERT INTO public.community_consensus_jobs (
    id,
    request_id,
    status,
    reason,
    attempt_count,
    locked_at,
    updated_at
)
SELECT
    '00000000-0000-4000-8000-00000000e240',
    community_request.id,
    'processing',
    'fixture_stale_generation',
    2,
    pg_catalog.CLOCK_TIMESTAMP(),
    pg_catalog.CLOCK_TIMESTAMP()
FROM public.explore_community_requests AS community_request
WHERE community_request.scan_id =
    '00000000-0000-4000-8000-00000000e210';

UPDATE public.explore_community_requests AS community_request
SET last_consensus_job_id =
        '00000000-0000-4000-8000-00000000e240'
WHERE community_request.scan_id =
    '00000000-0000-4000-8000-00000000e210';

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.request_community_identification_atomically(
        '00000000-0000-4000-8000-00000000e210',
        '00000000-0000-4000-8000-00000000e201',
        'Reopened request.',
        NULL,
        'Atomic community species',
        '[
          {
            "kind":"image",
            "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e230.webp",
            "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e230.webp",
            "order_index":0,
            "duration_seconds":null,
            "has_audio":false
          }
        ]'::JSONB,
        (SELECT taxon.id FROM fixture_community_taxon AS taxon),
        (
            SELECT taxon.taxonomy_version_id
            FROM fixture_community_taxon AS taxon
        )
    ) ->> 'status',
    'needs_id',
    'withdrawn Community state reopens as a fresh needs-ID generation'
);
RESET ROLE;

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.explore_community_requests AS community_request
        WHERE community_request.scan_id =
                '00000000-0000-4000-8000-00000000e210'
          AND community_request.status = 'needs_id'
          AND community_request.withdrawn_at IS NULL
          AND community_request.explore_published_at IS NULL
          AND community_request.current_community_taxon_node_id IS NULL
          AND community_request.resolved_taxon_node_id IS NULL
          AND community_request.resolved_observation_taxon_node_id IS NULL
          AND community_request.consensus_score IS NULL
          AND community_request.consensus_identification_count = 0
          AND community_request.consensus_rank IS NULL
          AND community_request.resolved_at IS NULL
          AND community_request.consensus_processing_state = 'idle'
          AND community_request.last_consensus_job_id IS NULL
    ),
    'reopen clears stale publication, consensus, and worker state'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.community_consensus_jobs AS consensus_job
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = consensus_job.request_id
        WHERE community_request.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    0,
    'reopen deletes the stale consensus job'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_identifications AS identification
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = identification.request_id
        WHERE community_request.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    1,
    'reopen retains prior vote rows as audit history'
);
SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.explore_identifications AS identification
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = identification.request_id
        WHERE community_request.scan_id =
                '00000000-0000-4000-8000-00000000e210'
          AND identification.withdrawn_at IS NOT NULL
          AND identification.restored_at IS NULL
    ),
    'reopen withdraws the prior active vote generation'
);
SELECT extensions.is(
    (
        SELECT projection.projection_state::TEXT
        FROM public.explore_observation_projection AS projection
        INNER JOIN public.explore_posts AS post
            ON post.id = projection.post_id
        WHERE post.scan_id =
            '00000000-0000-4000-8000-00000000e210'
    ),
    'community_needs_id',
    'reopened Community state remains hidden from normal Explore'
);

CREATE FUNCTION pg_temp.force_community_request_failure()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $trigger$
BEGIN
    IF NEW.scan_id =
       '00000000-0000-4000-8000-00000000e220'::UUID THEN
        RAISE EXCEPTION 'fixture forced Community request failure'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$trigger$;

CREATE TRIGGER fixture_force_community_request_failure
BEFORE INSERT
ON public.explore_community_requests
FOR EACH ROW
EXECUTE FUNCTION pg_temp.force_community_request_failure();

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.request_community_identification_atomically(
            '00000000-0000-4000-8000-00000000e220',
            '00000000-0000-4000-8000-00000000e201',
            'Must roll back.',
            NULL,
            'Atomic community species',
            '[
              {
                "kind":"image",
                "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e231.webp",
                "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e201/00000000-0000-4000-8000-00000000e231.webp",
                "order_index":0,
                "duration_seconds":null,
                "has_audio":false
              }
            ]'::JSONB,
            (SELECT taxon.id FROM fixture_community_taxon AS taxon),
            (
                SELECT taxon.taxonomy_version_id
                FROM fixture_community_taxon AS taxon
            )
        )
    $statement$,
    'P0001',
    'fixture forced Community request failure',
    'late request failure aborts the complete Community transaction'
);
RESET ROLE;

DROP TRIGGER fixture_force_community_request_failure
    ON public.explore_community_requests;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_posts AS post
        WHERE post.scan_id =
            '00000000-0000-4000-8000-00000000e220'
    ),
    0,
    'late request failure leaves no normal Explore post'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_community_requests AS community_request
        WHERE community_request.scan_id =
            '00000000-0000-4000-8000-00000000e220'
    ),
    0,
    'late request failure leaves no Community request'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_post_media AS media
        INNER JOIN public.explore_posts AS post
            ON post.id = media.post_id
        WHERE post.scan_id =
            '00000000-0000-4000-8000-00000000e220'
    ),
    0,
    'late request failure leaves no partial media snapshot'
);

SELECT * FROM extensions.finish();
ROLLBACK;
