-- Recover successful identifications stranded after their owned scan row was
-- committed but strict media finalization rejected the ingestion manifest.
--
-- The provider response and owned scan row are already durable in this state.
-- Re-running inference would be wasteful and the committed quota reservation
-- correctly prevents it. Distinguish historical inline-image filename hints
-- from real offline-queue image sources, normalize only provable phantom
-- hints, preserve every independently verified staged source, and pass the
-- existing scan through the canonical transactional finalizer.

-- Keep each validated stage in a bounded private routine. Besides making the
-- recovery contract reviewable, this removes the unusually large (43 KiB)
-- single-statement and complex-predicate parser surface that blocked fresh
-- migration replay. These helpers are invoker-security routines, have no
-- grants, and can therefore be reached only by their owner while the public
-- service-only wrapper runs.
CREATE OR REPLACE FUNCTION internal.inline_scan_recovery_ledger_matches(
    job_row public.scan_ingestion_jobs,
    intent_row public.scan_ingestion_intents,
    p_scan_id UUID,
    scan_image_storage_urls TEXT[],
    scan_video_storage_urls TEXT[]
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    inline_image_count INTEGER;
    inline_audio_count INTEGER;
    image_key_count INTEGER;
    audio_key_count INTEGER;
    video_key_count INTEGER;
    expected_job_image_count INTEGER;
    expected_scan_image_count INTEGER;
    has_inline_media BOOLEAN;
    uses_inline_images BOOLEAN;
BEGIN
    -- Keep type checks separate from array and numeric operations: PostgreSQL
    -- does not promise boolean-expression short-circuit order.
    IF job_row.status <> 'failed_retryable'
       OR job_row.stage NOT IN (
            'background_ingestion_failed',
            'media_finalization_failed'
       )
       OR job_row.endpoint NOT IN ('identify', 'identify-multimodal')
       OR intent_row.endpoint IS DISTINCT FROM job_row.endpoint
       OR pg_catalog.JSONB_TYPEOF(job_row.media_object_keys)
            IS DISTINCT FROM 'object'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_object_keys -> 'image'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_object_keys -> 'audio'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_object_keys -> 'video'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(job_row.media_counts)
            IS DISTINCT FROM 'object'
       OR pg_catalog.JSONB_TYPEOF(intent_row.media_object_keys)
            IS DISTINCT FROM 'object'
       OR intent_row.media_object_keys IS DISTINCT FROM
            job_row.media_object_keys
       OR intent_row.media_counts IS DISTINCT FROM job_row.media_counts
       OR intent_row.upload_session_ids IS DISTINCT FROM
            job_row.upload_session_ids
       OR intent_row.manifest_checksum IS DISTINCT FROM
            job_row.manifest_checksum
       OR pg_catalog.JSONB_TYPEOF(intent_row.request_payload)
            IS DISTINCT FROM 'object'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload -> 'media'
       ) IS DISTINCT FROM 'object'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload #> '{media,r2ObjectKeys}'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload #> '{media,audioR2ObjectKeys}'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload #> '{media,videoR2ObjectKeys}'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload #> '{media,audioMediaItems}'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload -> 'mediaCounts'
       ) IS DISTINCT FROM 'object'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload -> 'uploadSessionIds'
       ) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.request_payload -> 'redactedMediaCounts'
       ) IS DISTINCT FROM 'object'
       OR intent_row.request_payload #> '{media,r2ObjectKeys}'
            IS DISTINCT FROM job_row.media_object_keys -> 'image'
       OR intent_row.request_payload #> '{media,audioR2ObjectKeys}'
            IS DISTINCT FROM job_row.media_object_keys -> 'audio'
       OR intent_row.request_payload #> '{media,videoR2ObjectKeys}'
            IS DISTINCT FROM job_row.media_object_keys -> 'video'
       OR intent_row.request_payload -> 'mediaCounts'
            IS DISTINCT FROM job_row.media_counts
       OR intent_row.request_payload -> 'uploadSessionIds'
            IS DISTINCT FROM pg_catalog.TO_JSONB(
                job_row.upload_session_ids
            )
       OR intent_row.request_payload -> 'redactedMediaCounts'
            IS DISTINCT FROM intent_row.redacted_media_counts
       OR intent_row.request_payload ->> 'clientScanId'
            IS DISTINCT FROM p_scan_id::TEXT
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.redacted_media_counts
                -> 'image_base64_count'
       ) IS DISTINCT FROM 'number'
       OR pg_catalog.JSONB_TYPEOF(
            intent_row.redacted_media_counts
                -> 'audio_base64_count'
       ) IS DISTINCT FROM 'number'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_counts -> 'image_count'
       ) IS DISTINCT FROM 'number'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_counts -> 'audio_count'
       ) IS DISTINCT FROM 'number'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_counts -> 'video_count'
       ) IS DISTINCT FROM 'number'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_counts -> 'required_video_count'
       ) IS DISTINCT FROM 'number'
       OR pg_catalog.JSONB_TYPEOF(
            job_row.media_counts -> 'video_inference_frame_count'
       ) IS DISTINCT FROM 'number' THEN
        RETURN FALSE;
    END IF;

    image_key_count := pg_catalog.JSONB_ARRAY_LENGTH(
        job_row.media_object_keys -> 'image'
    );
    audio_key_count := pg_catalog.JSONB_ARRAY_LENGTH(
        job_row.media_object_keys -> 'audio'
    );
    video_key_count := pg_catalog.JSONB_ARRAY_LENGTH(
        job_row.media_object_keys -> 'video'
    );

    -- Bounds and lexical numeric checks make every cast below safe.
    IF image_key_count NOT BETWEEN 0 AND 16
       OR audio_key_count NOT BETWEEN 0 AND 16
       OR video_key_count NOT BETWEEN 0 AND 16
       OR COALESCE(
            intent_row.redacted_media_counts
                ->> 'image_base64_count',
            ''
       ) !~ '^(0|[1-9]|1[0-6])$'
       OR COALESCE(
            intent_row.redacted_media_counts
                ->> 'audio_base64_count',
            ''
       ) !~ '^(0|[1-9]|1[0-6])$'
       OR COALESCE(
            job_row.media_counts ->> 'image_count',
            ''
       ) !~ '^(0|[1-9]|[12][0-9]|3[0-2])$'
       OR COALESCE(
            job_row.media_counts ->> 'audio_count',
            ''
       ) !~ '^(0|[1-9]|[12][0-9]|3[0-2])$'
       OR COALESCE(
            job_row.media_counts ->> 'video_count',
            ''
       ) !~ '^(0|[1-9]|1[0-6])$'
       OR COALESCE(
            job_row.media_counts ->> 'required_video_count',
            ''
       ) !~ '^(0|[1-9]|1[0-6])$'
       OR COALESCE(
            job_row.media_counts
                ->> 'video_inference_frame_count',
            ''
       ) !~ '^(0|[1-9]|1[0-6])$' THEN
        RETURN FALSE;
    END IF;

    inline_image_count := (
        intent_row.redacted_media_counts
            ->> 'image_base64_count'
    )::INTEGER;
    inline_audio_count := (
        intent_row.redacted_media_counts
            ->> 'audio_base64_count'
    )::INTEGER;
    uses_inline_images := inline_image_count > 0;
    has_inline_media := uses_inline_images OR inline_audio_count > 0;

    IF uses_inline_images THEN
        expected_scan_image_count := inline_image_count;
    ELSE
        expected_scan_image_count := image_key_count;
    END IF;

    IF uses_inline_images
       AND image_key_count > inline_image_count THEN
        RETURN FALSE;
    END IF;

    IF intent_row.inline_media_redacted
            IS DISTINCT FROM has_inline_media
       OR intent_row.resumable
            IS DISTINCT FROM (NOT has_inline_media) THEN
        RETURN FALSE;
    END IF;

    -- identify used a compatibility ledger that counted the ignored image hint
    -- in addition to inline images. identify-multimodal counted sampled video
    -- frames separately. Mirror both historical shapes exactly, but keep the
    -- endpoint predicates independent so the migration never depends on one
    -- giant nested CASE expression.
    IF job_row.endpoint = 'identify' THEN
        expected_job_image_count := image_key_count;
        IF uses_inline_images THEN
            expected_job_image_count :=
                expected_job_image_count + inline_image_count;
        END IF;

        IF audio_key_count <> 0
           OR video_key_count <> 0
           OR inline_audio_count <> 0
           OR (
                job_row.media_counts ->> 'image_count'
           )::INTEGER <> expected_job_image_count
           OR (
                job_row.media_counts
                    ->> 'video_inference_frame_count'
           )::INTEGER <> 0 THEN
            RETURN FALSE;
        END IF;
    ELSIF job_row.endpoint = 'identify-multimodal' THEN
        IF (
                job_row.media_counts ->> 'image_count'
           )::INTEGER
                + (
                    job_row.media_counts
                        ->> 'video_inference_frame_count'
                )::INTEGER <> expected_scan_image_count
           OR (
                inline_audio_count > 0
                AND audio_key_count > 0
           ) THEN
            RETURN FALSE;
        END IF;
    ELSE
        RETURN FALSE;
    END IF;

    IF job_row.media_counts -> 'audio_count'
            IS DISTINCT FROM pg_catalog.TO_JSONB(
                inline_audio_count + audio_key_count
            )
       OR job_row.media_counts -> 'video_count'
            IS DISTINCT FROM pg_catalog.TO_JSONB(video_key_count)
       OR job_row.media_counts -> 'required_video_count'
            IS DISTINCT FROM pg_catalog.TO_JSONB(video_key_count)
       OR pg_catalog.CARDINALITY(
            COALESCE(scan_image_storage_urls, '{}'::TEXT[])
       ) <> expected_scan_image_count
       OR pg_catalog.CARDINALITY(
            COALESCE(scan_video_storage_urls, '{}'::TEXT[])
       ) <> video_key_count
       OR pg_catalog.JSONB_ARRAY_LENGTH(
            intent_row.request_payload #> '{media,audioMediaItems}'
       ) <> inline_audio_count + audio_key_count THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION internal.inline_scan_recovery_ledger_matches(
    public.scan_ingestion_jobs,
    public.scan_ingestion_intents,
    UUID,
    TEXT[],
    TEXT[]
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.inline_scan_recovery_scan_media_match(
    job_row public.scan_ingestion_jobs,
    intent_row public.scan_ingestion_intents,
    p_scan_id UUID,
    p_user_id UUID,
    scan_image_storage_urls TEXT[],
    scan_video_storage_urls TEXT[],
    scan_audio_storage_urls TEXT[],
    uses_inline_images BOOLEAN,
    image_key_count INTEGER
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    standalone_audio_count INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(
            intent_row.request_payload #> '{media,audioMediaItems}'
        ) AS audio_items(item)
        WHERE pg_catalog.JSONB_TYPEOF(audio_items.item)
                IS DISTINCT FROM 'object'
           OR audio_items.item ->> 'kind' IS NULL
           OR audio_items.item ->> 'kind'
                NOT IN ('audio', 'video_audio')
    ) THEN
        RETURN FALSE;
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO STRICT standalone_audio_count
    FROM pg_catalog.JSONB_ARRAY_ELEMENTS(
        intent_row.request_payload #> '{media,audioMediaItems}'
    ) AS audio_items(item)
    WHERE audio_items.item ->> 'kind' = 'audio';

    -- Every persisted media URL must be unique, canonical, and owner-scoped.
    IF pg_catalog.CARDINALITY(
            COALESCE(scan_audio_storage_urls, '{}'::TEXT[])
       ) <> standalone_audio_count
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(
                COALESCE(scan_image_storage_urls, '{}'::TEXT[])
            ) AS media_urls(url)
            WHERE media_urls.url
                !~ (
                    '^https://media[.]merian[.]app/public_uploads/'
                    || '(free|pro)/'
                    || p_user_id::TEXT
                    || '/[A-Za-z0-9._-]+$'
                )
       )
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(
                COALESCE(scan_video_storage_urls, '{}'::TEXT[])
            ) AS media_urls(url)
            WHERE media_urls.url
                !~ (
                    '^https://media[.]merian[.]app/public_uploads/'
                    || '(free|pro)/'
                    || p_user_id::TEXT
                    || '/[A-Za-z0-9._-]+$'
                )
       )
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(
                COALESCE(scan_audio_storage_urls, '{}'::TEXT[])
            ) AS media_urls(url)
            WHERE media_urls.url
                !~ (
                    '^https://media[.]merian[.]app/public_uploads/'
                    || '(free|pro)/'
                    || p_user_id::TEXT
                    || '/[A-Za-z0-9._-]+$'
                )
       )
       OR (
            SELECT pg_catalog.COUNT(DISTINCT media_urls.url)
            FROM pg_catalog.UNNEST(
                COALESCE(scan_image_storage_urls, '{}'::TEXT[])
            ) AS media_urls(url)
       ) <> pg_catalog.CARDINALITY(
            COALESCE(scan_image_storage_urls, '{}'::TEXT[])
       )
       OR (
            SELECT pg_catalog.COUNT(DISTINCT media_urls.url)
            FROM pg_catalog.UNNEST(
                COALESCE(scan_video_storage_urls, '{}'::TEXT[])
            ) AS media_urls(url)
       ) <> pg_catalog.CARDINALITY(
            COALESCE(scan_video_storage_urls, '{}'::TEXT[])
       )
       OR (
            SELECT pg_catalog.COUNT(DISTINCT media_urls.url)
            FROM pg_catalog.UNNEST(
                COALESCE(scan_audio_storage_urls, '{}'::TEXT[])
            ) AS media_urls(url)
       ) <> pg_catalog.CARDINALITY(
            COALESCE(scan_audio_storage_urls, '{}'::TEXT[])
       ) THEN
        RETURN FALSE;
    END IF;

    -- Image keys are overloaded by historical clients. With inline bytes they
    -- were destination filename hints and must have no upload row. Without
    -- inline bytes they are real offline-queue sources and require one exact
    -- active capture row (plus only migration-marked superseded duplicates).
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'image'
        ) AS image_keys(storage_key)
        WHERE pg_catalog.CHAR_LENGTH(image_keys.storage_key)
                NOT BETWEEN 1 AND 512
           OR image_keys.storage_key
                !~ '^staging/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
       )
       OR (
            SELECT pg_catalog.COUNT(DISTINCT image_keys.storage_key)
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'image'
            ) AS image_keys(storage_key)
       ) <> image_key_count THEN
        RETURN FALSE;
    END IF;

    IF uses_inline_images THEN
        IF EXISTS (
            SELECT 1
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'image'
            ) AS image_keys(storage_key)
            WHERE (
                SELECT pg_catalog.COUNT(*)
                FROM pg_catalog.UNNEST(
                    COALESCE(scan_image_storage_urls, '{}'::TEXT[])
                ) AS image_urls(url)
                WHERE pg_catalog.RIGHT(
                    image_urls.url,
                    pg_catalog.CHAR_LENGTH(
                        '/'
                        || pg_catalog.REGEXP_REPLACE(
                            image_keys.storage_key,
                            '^.*/',
                            ''
                        )
                    )
                ) = '/'
                    || pg_catalog.REGEXP_REPLACE(
                        image_keys.storage_key,
                        '^.*/',
                        ''
                    )
            ) <> 1
        )
        OR EXISTS (
            SELECT 1
            FROM public.scan_media_assets AS assets
            WHERE assets.user_id = p_user_id
              AND assets.client_scan_id = p_scan_id
              AND assets.source = 'capture_upload'
              AND assets.storage_key IN (
                  SELECT image_keys.storage_key
                  FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                      job_row.media_object_keys -> 'image'
                  ) AS image_keys(storage_key)
              )
        ) THEN
            RETURN FALSE;
        END IF;
    ELSE
        IF EXISTS (
            SELECT 1
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'image'
            ) AS image_keys(storage_key)
            WHERE image_keys.storage_key
                !~ (
                    '^staging/'
                    || p_user_id::TEXT
                    || '/[A-Za-z0-9._-]+$'
                )
               OR (
                    SELECT pg_catalog.COUNT(*)
                    FROM pg_catalog.UNNEST(
                        COALESCE(scan_image_storage_urls, '{}'::TEXT[])
                    ) AS image_urls(url)
                    WHERE pg_catalog.RIGHT(
                        image_urls.url,
                        pg_catalog.CHAR_LENGTH(
                            '/'
                            || pg_catalog.REGEXP_REPLACE(
                                image_keys.storage_key,
                                '^.*/',
                                ''
                            )
                        )
                    ) = '/'
                        || pg_catalog.REGEXP_REPLACE(
                            image_keys.storage_key,
                            '^.*/',
                            ''
                        )
               ) <> 1
               OR (
                    SELECT pg_catalog.COUNT(*)
                    FROM public.scan_media_assets AS assets
                    WHERE assets.user_id = p_user_id
                      AND assets.client_scan_id = p_scan_id
                      AND assets.source = 'capture_upload'
                      AND assets.storage_key = image_keys.storage_key
                      AND assets.kind = 'image'
                      AND assets.upload_session_id IS NOT NULL
                      AND assets.status IN ('staged', 'promoted')
               ) <> 1
               OR EXISTS (
                    SELECT 1
                    FROM public.scan_media_assets AS assets
                    WHERE assets.user_id = p_user_id
                      AND assets.client_scan_id = p_scan_id
                      AND assets.source = 'capture_upload'
                      AND assets.storage_key = image_keys.storage_key
                      AND NOT (
                          (
                              assets.kind = 'image'
                              AND assets.upload_session_id IS NOT NULL
                              AND assets.status IN ('staged', 'promoted')
                          )
                          OR (
                              assets.status = 'failed'
                              AND assets.failure_reason =
                                  'superseded_staging_registration'
                          )
                      )
               )
               OR EXISTS (
                    SELECT 1
                    FROM public.scan_media_assets AS assets
                    WHERE assets.user_id = p_user_id
                      AND assets.client_scan_id = p_scan_id
                      AND assets.source = 'capture_upload'
                      AND assets.storage_key = image_keys.storage_key
                      AND assets.status = 'promoted'
                      AND assets.url IS DISTINCT FROM (
                          SELECT pg_catalog.MAX(image_urls.url)
                          FROM pg_catalog.UNNEST(
                              COALESCE(
                                  scan_image_storage_urls,
                                  '{}'::TEXT[]
                              )
                          ) AS image_urls(url)
                          WHERE pg_catalog.RIGHT(
                              image_urls.url,
                              pg_catalog.CHAR_LENGTH(
                                  '/'
                                  || pg_catalog.REGEXP_REPLACE(
                                      image_keys.storage_key,
                                      '^.*/',
                                      ''
                                  )
                              )
                          ) = '/'
                              || pg_catalog.REGEXP_REPLACE(
                                  image_keys.storage_key,
                                  '^.*/',
                                  ''
                              )
                      )
               )
        ) THEN
            RETURN FALSE;
        END IF;
    END IF;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION internal.inline_scan_recovery_scan_media_match(
    public.scan_ingestion_jobs,
    public.scan_ingestion_intents,
    UUID,
    UUID,
    TEXT[],
    TEXT[],
    TEXT[],
    BOOLEAN,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.inline_scan_recovery_staged_assets_match(
    job_row public.scan_ingestion_jobs,
    intent_row public.scan_ingestion_intents,
    p_scan_id UUID,
    p_user_id UUID,
    scan_video_storage_urls TEXT[],
    scan_audio_storage_urls TEXT[],
    uses_inline_images BOOLEAN,
    image_key_count INTEGER,
    audio_key_count INTEGER,
    video_key_count INTEGER
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    expected_staged_key_count INTEGER;
BEGIN
    expected_staged_key_count := audio_key_count + video_key_count;
    IF NOT uses_inline_images THEN
        expected_staged_key_count :=
            expected_staged_key_count + image_key_count;
    END IF;

    -- Every non-inline manifest key remains a real staged source. Reject
    -- malformed keys, cross-kind collisions, missing active upload rows, or
    -- unrecognized duplicates.
    IF EXISTS (
        WITH expected(kind, storage_key) AS (
            SELECT 'image'::TEXT, image_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'image'
            ) AS image_keys(storage_key)
            WHERE NOT uses_inline_images
            UNION ALL
            SELECT 'audio'::TEXT, audio_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'audio'
            ) AS audio_keys(storage_key)
            UNION ALL
            SELECT 'video'::TEXT, video_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'video'
            ) AS video_keys(storage_key)
        )
        SELECT 1
        FROM expected
        WHERE pg_catalog.CHAR_LENGTH(expected.storage_key)
                NOT BETWEEN 1 AND 512
           OR expected.storage_key
                !~ (
                    '^staging/'
                    || p_user_id::TEXT
                    || '/[A-Za-z0-9._-]+$'
                )
    ) THEN
        RETURN FALSE;
    END IF;

    IF (
        WITH expected(storage_key) AS (
            SELECT image_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'image'
            ) AS image_keys(storage_key)
            WHERE NOT uses_inline_images
            UNION ALL
            SELECT audio_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'audio'
            ) AS audio_keys(storage_key)
            UNION ALL
            SELECT video_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'video'
            ) AS video_keys(storage_key)
        )
        SELECT pg_catalog.COUNT(DISTINCT expected.storage_key)
        FROM expected
    ) <> expected_staged_key_count THEN
        RETURN FALSE;
    END IF;

    IF EXISTS (
        WITH expected(kind, storage_key) AS (
            SELECT 'image'::TEXT, image_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'image'
            ) AS image_keys(storage_key)
            WHERE NOT uses_inline_images
            UNION ALL
            SELECT 'audio'::TEXT, audio_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'audio'
            ) AS audio_keys(storage_key)
            UNION ALL
            SELECT 'video'::TEXT, video_keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                job_row.media_object_keys -> 'video'
            ) AS video_keys(storage_key)
        )
        SELECT 1
        FROM expected
        WHERE (
            SELECT pg_catalog.COUNT(*)
            FROM public.scan_media_assets AS assets
            WHERE assets.user_id = p_user_id
              AND assets.client_scan_id = p_scan_id
              AND assets.source = 'capture_upload'
              AND assets.storage_key = expected.storage_key
              AND assets.kind = expected.kind
              AND assets.upload_session_id IS NOT NULL
              AND (
                  (
                      expected.kind IN ('image', 'video')
                      AND assets.status IN ('staged', 'promoted')
                  )
                  OR (
                      expected.kind = 'audio'
                      AND assets.status IN (
                          'staged',
                          'promoted',
                          'deleted'
                      )
                  )
              )
        ) <> 1
           OR EXISTS (
                SELECT 1
                FROM public.scan_media_assets AS assets
                WHERE assets.user_id = p_user_id
                  AND assets.client_scan_id = p_scan_id
                  AND assets.source = 'capture_upload'
                  AND assets.storage_key = expected.storage_key
                  AND NOT (
                      (
                          assets.kind = expected.kind
                          AND assets.upload_session_id IS NOT NULL
                          AND (
                              (
                                  expected.kind IN ('image', 'video')
                                  AND assets.status IN (
                                      'staged',
                                      'promoted'
                                  )
                              )
                              OR (
                                  expected.kind = 'audio'
                                  AND assets.status IN (
                                      'staged',
                                      'promoted',
                                      'deleted'
                                  )
                              )
                          )
                      )
                      OR (
                          assets.status = 'failed'
                          AND assets.failure_reason =
                              'superseded_staging_registration'
                      )
                  )
           )
    ) THEN
        RETURN FALSE;
    END IF;

    -- A real video key always maps one-to-one to its canonical scan URL.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'video'
        ) AS video_keys(storage_key)
        WHERE (
            SELECT pg_catalog.COUNT(*)
            FROM pg_catalog.UNNEST(
                COALESCE(scan_video_storage_urls, '{}'::TEXT[])
            ) AS video_urls(url)
            WHERE pg_catalog.RIGHT(
                video_urls.url,
                pg_catalog.CHAR_LENGTH(
                    '/'
                    || pg_catalog.REGEXP_REPLACE(
                        video_keys.storage_key,
                        '^.*/',
                        ''
                    )
                )
            ) = '/'
                || pg_catalog.REGEXP_REPLACE(
                    video_keys.storage_key,
                    '^.*/',
                    ''
                )
        ) <> 1
           OR EXISTS (
                SELECT 1
                FROM public.scan_media_assets AS assets
                WHERE assets.user_id = p_user_id
                  AND assets.client_scan_id = p_scan_id
                  AND assets.source = 'capture_upload'
                  AND assets.storage_key = video_keys.storage_key
                  AND assets.status = 'promoted'
                  AND assets.url IS DISTINCT FROM (
                      SELECT pg_catalog.MAX(video_urls.url)
                      FROM pg_catalog.UNNEST(
                          COALESCE(
                              scan_video_storage_urls,
                              '{}'::TEXT[]
                          )
                      ) AS video_urls(url)
                      WHERE pg_catalog.RIGHT(
                          video_urls.url,
                          pg_catalog.CHAR_LENGTH(
                              '/'
                              || pg_catalog.REGEXP_REPLACE(
                                  video_keys.storage_key,
                                  '^.*/',
                                  ''
                              )
                          )
                      ) = '/'
                          || pg_catalog.REGEXP_REPLACE(
                              video_keys.storage_key,
                              '^.*/',
                              ''
                          )
                  )
           )
    ) THEN
        RETURN FALSE;
    END IF;

    -- Audio descriptors are the durable classification used by the original
    -- route: standalone audio is promoted; video companion audio is deleted.
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'audio'
        ) WITH ORDINALITY AS audio_keys(storage_key, ordinal)
        JOIN pg_catalog.JSONB_ARRAY_ELEMENTS(
            intent_row.request_payload #> '{media,audioMediaItems}'
        ) WITH ORDINALITY AS audio_items(item, ordinal)
        USING (ordinal)
        WHERE (
            audio_items.item ->> 'kind' = 'audio'
            AND (
                (
                    SELECT pg_catalog.COUNT(*)
                    FROM pg_catalog.UNNEST(
                        COALESCE(
                            scan_audio_storage_urls,
                            '{}'::TEXT[]
                        )
                    ) AS audio_urls(url)
                    WHERE pg_catalog.RIGHT(
                        audio_urls.url,
                        pg_catalog.CHAR_LENGTH(
                            '/'
                            || pg_catalog.REGEXP_REPLACE(
                                audio_keys.storage_key,
                                '^.*/',
                                ''
                            )
                        )
                    ) = '/'
                        || pg_catalog.REGEXP_REPLACE(
                            audio_keys.storage_key,
                            '^.*/',
                            ''
                        )
                ) <> 1
                OR EXISTS (
                    SELECT 1
                    FROM public.scan_media_assets AS assets
                    WHERE assets.user_id = p_user_id
                      AND assets.client_scan_id = p_scan_id
                      AND assets.source = 'capture_upload'
                      AND assets.storage_key = audio_keys.storage_key
                      AND NOT (
                          assets.status = 'failed'
                          AND assets.failure_reason =
                              'superseded_staging_registration'
                      )
                      AND (
                          assets.status NOT IN ('staged', 'promoted')
                          OR (
                              assets.status = 'promoted'
                              AND assets.url IS DISTINCT FROM (
                                  SELECT pg_catalog.MAX(audio_urls.url)
                                  FROM pg_catalog.UNNEST(
                                      COALESCE(
                                          scan_audio_storage_urls,
                                          '{}'::TEXT[]
                                      )
                                  ) AS audio_urls(url)
                                  WHERE pg_catalog.RIGHT(
                                      audio_urls.url,
                                      pg_catalog.CHAR_LENGTH(
                                          '/'
                                          || pg_catalog.REGEXP_REPLACE(
                                              audio_keys.storage_key,
                                              '^.*/',
                                              ''
                                          )
                                      )
                                  ) = '/'
                                      || pg_catalog.REGEXP_REPLACE(
                                          audio_keys.storage_key,
                                          '^.*/',
                                          ''
                                      )
                              )
                          )
                      )
                )
            )
        )
           OR (
                audio_items.item ->> 'kind' = 'video_audio'
                AND (
                    EXISTS (
                        SELECT 1
                        FROM pg_catalog.UNNEST(
                            COALESCE(
                                scan_audio_storage_urls,
                                '{}'::TEXT[]
                            )
                        ) AS audio_urls(url)
                        WHERE pg_catalog.RIGHT(
                            audio_urls.url,
                            pg_catalog.CHAR_LENGTH(
                                '/'
                                || pg_catalog.REGEXP_REPLACE(
                                    audio_keys.storage_key,
                                    '^.*/',
                                    ''
                                )
                            )
                        ) = '/'
                            || pg_catalog.REGEXP_REPLACE(
                                audio_keys.storage_key,
                                '^.*/',
                                ''
                            )
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM public.scan_media_assets AS assets
                        WHERE assets.user_id = p_user_id
                          AND assets.client_scan_id = p_scan_id
                          AND assets.source = 'capture_upload'
                          AND assets.storage_key =
                              audio_keys.storage_key
                          AND NOT (
                              assets.status = 'failed'
                              AND assets.failure_reason =
                                  'superseded_staging_registration'
                          )
                          AND assets.status NOT IN ('staged', 'deleted')
                    )
                )
           )
    ) THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION internal.inline_scan_recovery_staged_assets_match(
    public.scan_ingestion_jobs,
    public.scan_ingestion_intents,
    UUID,
    UUID,
    TEXT[],
    TEXT[],
    BOOLEAN,
    INTEGER,
    INTEGER,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.recover_inline_scan_ingestion_completion(
    p_scan_id UUID,
    p_user_id UUID
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    job_row public.scan_ingestion_jobs%ROWTYPE;
    intent_row public.scan_ingestion_intents%ROWTYPE;
    scan_owner UUID;
    scan_image_storage_urls TEXT[];
    scan_video_storage_urls TEXT[];
    scan_audio_storage_urls TEXT[];
    inline_image_count INTEGER;
    image_key_count INTEGER;
    audio_key_count INTEGER;
    video_key_count INTEGER;
    preserved_storage_keys TEXT[];
    resolved_upload_session_ids UUID[];
    normalized_media_object_keys JSONB;
    normalized_request_payload JSONB;
    recovered_promotions JSONB;
    recovered_deletions TEXT[];
    finalization_result TEXT;
    uses_inline_images BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_inline_scan_recovery_identity'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = p_scan_id
    ) THEN
        RETURN 'deleted';
    END IF;

    SELECT jobs.*
    INTO job_row
    FROM public.scan_ingestion_jobs AS jobs
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'job_not_found';
    END IF;
    IF job_row.status = 'complete' THEN
        RETURN 'already_complete';
    END IF;

    SELECT intents.*
    INTO intent_row
    FROM public.scan_ingestion_intents AS intents
    WHERE intents.scan_id = p_scan_id::TEXT
      AND intents.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'not_applicable';
    END IF;

    SELECT
        scans.user_id,
        scans.image_storage_urls,
        scans.video_storage_urls,
        scans.audio_storage_urls
    INTO
        scan_owner,
        scan_image_storage_urls,
        scan_video_storage_urls,
        scan_audio_storage_urls
    FROM public.scans AS scans
    WHERE scans.id = p_scan_id
    FOR UPDATE;

    IF NOT FOUND OR scan_owner IS DISTINCT FROM p_user_id THEN
        RETURN 'not_applicable';
    END IF;

    IF NOT internal.inline_scan_recovery_ledger_matches(
        job_row,
        intent_row,
        p_scan_id,
        scan_image_storage_urls,
        scan_video_storage_urls
    ) THEN
        RETURN 'not_applicable';
    END IF;

    -- The helper above proves these operations safe while this transaction
    -- retains both ledger row locks.
    image_key_count := pg_catalog.JSONB_ARRAY_LENGTH(
        job_row.media_object_keys -> 'image'
    );
    audio_key_count := pg_catalog.JSONB_ARRAY_LENGTH(
        job_row.media_object_keys -> 'audio'
    );
    video_key_count := pg_catalog.JSONB_ARRAY_LENGTH(
        job_row.media_object_keys -> 'video'
    );
    inline_image_count := (
        intent_row.redacted_media_counts
            ->> 'image_base64_count'
    )::INTEGER;
    uses_inline_images := inline_image_count > 0;

    IF NOT internal.inline_scan_recovery_scan_media_match(
        job_row,
        intent_row,
        p_scan_id,
        p_user_id,
        scan_image_storage_urls,
        scan_video_storage_urls,
        scan_audio_storage_urls,
        uses_inline_images,
        image_key_count
    ) THEN
        RETURN 'not_applicable';
    END IF;

    IF NOT internal.inline_scan_recovery_staged_assets_match(
        job_row,
        intent_row,
        p_scan_id,
        p_user_id,
        scan_video_storage_urls,
        scan_audio_storage_urls,
        uses_inline_images,
        image_key_count,
        audio_key_count,
        video_key_count
    ) THEN
        RETURN 'not_applicable';
    END IF;

    SELECT ARRAY(
        SELECT image_keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'image'
        ) AS image_keys(storage_key)
        WHERE NOT uses_inline_images
        UNION ALL
        SELECT audio_keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'audio'
        ) AS audio_keys(storage_key)
        UNION ALL
        SELECT video_keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'video'
        ) AS video_keys(storage_key)
    )
    INTO STRICT preserved_storage_keys;

    SELECT COALESCE(
        pg_catalog.ARRAY_AGG(
            DISTINCT assets.upload_session_id
            ORDER BY assets.upload_session_id
        ),
        '{}'::UUID[]
    )
    INTO STRICT resolved_upload_session_ids
    FROM public.scan_media_assets AS assets
    WHERE assets.user_id = p_user_id
      AND assets.client_scan_id = p_scan_id
      AND assets.source = 'capture_upload'
      AND assets.storage_key = ANY(preserved_storage_keys);

    IF resolved_upload_session_ids IS DISTINCT FROM
            job_row.upload_session_ids THEN
        RETURN 'not_applicable';
    END IF;

    SELECT COALESCE(
        pg_catalog.JSONB_OBJECT_AGG(
            promoted.storage_key,
            promoted.public_url
        ),
        '{}'::JSONB
    )
    INTO STRICT recovered_promotions
    FROM (
        SELECT image_keys.storage_key, image_urls.url AS public_url
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'image'
        ) AS image_keys(storage_key)
        JOIN pg_catalog.UNNEST(
            COALESCE(scan_image_storage_urls, '{}'::TEXT[])
        ) AS image_urls(url)
          ON NOT uses_inline_images
         AND pg_catalog.RIGHT(
                image_urls.url,
                pg_catalog.CHAR_LENGTH(
                    '/'
                    || pg_catalog.REGEXP_REPLACE(
                        image_keys.storage_key,
                        '^.*/',
                        ''
                    )
                )
             ) = '/'
                || pg_catalog.REGEXP_REPLACE(
                    image_keys.storage_key,
                    '^.*/',
                    ''
                )
        UNION ALL
        SELECT video_keys.storage_key, video_urls.url AS public_url
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'video'
        ) AS video_keys(storage_key)
        JOIN pg_catalog.UNNEST(
            COALESCE(scan_video_storage_urls, '{}'::TEXT[])
        ) AS video_urls(url)
          ON pg_catalog.RIGHT(
                video_urls.url,
                pg_catalog.CHAR_LENGTH(
                    '/'
                    || pg_catalog.REGEXP_REPLACE(
                        video_keys.storage_key,
                        '^.*/',
                        ''
                    )
                )
             ) = '/'
                || pg_catalog.REGEXP_REPLACE(
                    video_keys.storage_key,
                    '^.*/',
                    ''
                )
        UNION ALL
        SELECT audio_keys.storage_key, audio_urls.url AS public_url
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            job_row.media_object_keys -> 'audio'
        ) WITH ORDINALITY AS audio_keys(storage_key, ordinal)
        JOIN pg_catalog.JSONB_ARRAY_ELEMENTS(
            intent_row.request_payload #> '{media,audioMediaItems}'
        ) WITH ORDINALITY AS audio_items(item, ordinal)
        USING (ordinal)
        JOIN pg_catalog.UNNEST(
            COALESCE(scan_audio_storage_urls, '{}'::TEXT[])
        ) AS audio_urls(url)
          ON pg_catalog.RIGHT(
                audio_urls.url,
                pg_catalog.CHAR_LENGTH(
                    '/'
                    || pg_catalog.REGEXP_REPLACE(
                        audio_keys.storage_key,
                        '^.*/',
                        ''
                    )
                )
             ) = '/'
                || pg_catalog.REGEXP_REPLACE(
                    audio_keys.storage_key,
                    '^.*/',
                    ''
                )
        WHERE audio_items.item ->> 'kind' = 'audio'
    ) AS promoted;

    SELECT COALESCE(
        pg_catalog.ARRAY_AGG(
            audio_keys.storage_key
            ORDER BY audio_keys.ordinal
        ),
        '{}'::TEXT[]
    )
    INTO STRICT recovered_deletions
    FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
        job_row.media_object_keys -> 'audio'
    ) WITH ORDINALITY AS audio_keys(storage_key, ordinal)
    JOIN pg_catalog.JSONB_ARRAY_ELEMENTS(
        intent_row.request_payload #> '{media,audioMediaItems}'
    ) WITH ORDINALITY AS audio_items(item, ordinal)
    USING (ordinal)
    WHERE audio_items.item ->> 'kind' = 'video_audio';

    normalized_media_object_keys := pg_catalog.JSONB_BUILD_OBJECT(
        'image',
        CASE
            WHEN uses_inline_images THEN '[]'::JSONB
            ELSE job_row.media_object_keys -> 'image'
        END,
        'audio',
        job_row.media_object_keys -> 'audio',
        'video',
        job_row.media_object_keys -> 'video'
    );
    normalized_request_payload := CASE
        WHEN uses_inline_images THEN pg_catalog.JSONB_SET(
            intent_row.request_payload,
            '{media,r2ObjectKeys}',
            '[]'::JSONB,
            FALSE
        )
        ELSE intent_row.request_payload
    END;

    -- begin_scan_ingestion recomputes the manifest and payload checksums and
    -- updates both ledgers together. The advisory lock is transaction-scoped
    -- and re-entrant for the canonical finalizer invoked immediately after it.
    PERFORM public.begin_scan_ingestion(
        p_scan_id::TEXT,
        p_user_id,
        job_row.endpoint,
        normalized_request_payload,
        job_row.media_counts,
        normalized_media_object_keys,
        preserved_storage_keys,
        NULL,
        NULL,
        intent_row.resumable,
        intent_row.inline_media_redacted,
        intent_row.redacted_media_counts,
        intent_row.payload_schema_version,
        300
    );

    finalization_result := public.complete_scan_ingestion_finalization(
        p_scan_id,
        p_user_id,
        recovered_promotions,
        recovered_deletions
    );

    IF finalization_result NOT IN ('completed', 'already_complete') THEN
        RAISE EXCEPTION 'inline_scan_recovery_finalization_failed: %',
            finalization_result
            USING ERRCODE = '55000';
    END IF;

    RETURN finalization_result;
END;
$$;

REVOKE ALL ON FUNCTION public.recover_inline_scan_ingestion_completion(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_inline_scan_ingestion_completion(
    UUID,
    UUID
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.recover_inline_scan_ingestion_completion(uuid,uuid)',
    'Atomically removes only proven phantom inline-image hints, preserves exactly verified staged image/audio/video sources, and completes an already-owned durable scan through the canonical finalizer.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

COMMENT ON FUNCTION public.recover_inline_scan_ingestion_completion(
    UUID,
    UUID
) IS
    'Service-only, fail-closed repair for already-durable owned scans stranded at strict media finalization; distinguishes historical inline hints from genuine staged sources.';

NOTIFY pgrst, 'reload schema';
