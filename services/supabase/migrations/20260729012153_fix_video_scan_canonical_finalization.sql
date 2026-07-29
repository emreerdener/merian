-- Restore canonical finalization for video scans.
--
-- image_storage_urls is a compatibility surface. For a legacy video capture it
-- contains sampled inference frames as well as any standalone images, while
-- refresh_scan_visual_media_assets deliberately creates one ready playback row
-- for the clip and does not render those inference frames as image rows. The
-- finalizer added on 2026-07-28 compared every compatibility image URL with a
-- ready standalone image and therefore rejected otherwise-complete video scans.
--
-- Keep finalization fail-closed by projecting the same app-facing timeline as
-- refresh_scan_media_assets, then require every projected image, playback
-- video, and standalone audio item to have an owner-matched ready asset. The
-- later captured-to-canonical proof excludes only owner/job-declared inference
-- frames that are present in the compatibility array and outside that display
-- projection.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION internal.scan_canonical_media_projection_complete(
    p_scan_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH scan_row AS (
        SELECT
            scans.id,
            scans.user_id,
            scans.captured_media,
            COALESCE(
                scans.image_storage_urls,
                '{}'::TEXT[]
            ) AS image_storage_urls,
            COALESCE(
                scans.video_storage_urls,
                '{}'::TEXT[]
            ) AS video_storage_urls,
            COALESCE(
                scans.audio_storage_urls,
                '{}'::TEXT[]
            ) AS audio_storage_urls,
            jobs.endpoint,
            jobs.media_counts
        FROM public.scans AS scans
        JOIN public.scan_ingestion_jobs AS jobs
          ON jobs.scan_id = scans.id::TEXT
         AND jobs.user_id = scans.user_id
        WHERE scans.id = p_scan_id
    ),
    captured_items AS (
        SELECT
            media_items.item,
            media_items.ordinality
        FROM scan_row
        CROSS JOIN LATERAL pg_catalog.JSONB_ARRAY_ELEMENTS(
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_row.captured_media
                ) = 'array'
                    THEN scan_row.captured_media
                ELSE '[]'::JSONB
            END
        ) WITH ORDINALITY AS media_items(item, ordinality)
    ),
    captured_visuals AS (
        SELECT
            CASE
                WHEN projected_references.image_url IS NOT NULL
                    THEN 'image'::TEXT
                ELSE 'video'::TEXT
            END AS kind,
            COALESCE(
                projected_references.image_url,
                projected_references.video_url
            ) AS url,
            captured_items.ordinality
        FROM captured_items
        CROSS JOIN LATERAL (
            SELECT
                public.scan_media_reference_path(
                    captured_items.item #> '{image,_0}'
                ) AS image_url,
                public.scan_media_reference_path(
                    captured_items.item #> '{video,_0,video}'
                ) AS video_url
        ) AS projected_references
        WHERE projected_references.image_url IS NOT NULL
           OR projected_references.video_url IS NOT NULL
    ),
    legacy_images AS (
        SELECT
            cleaned.url,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY source_urls.ordinality
            ) AS sequence
        FROM scan_row
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            scan_row.image_storage_urls
        ) WITH ORDINALITY AS source_urls(url, ordinality)
        CROSS JOIN LATERAL (
            SELECT NULLIF(
                pg_catalog.BTRIM(source_urls.url),
                ''
            ) AS url
        ) AS cleaned
        WHERE cleaned.url IS NOT NULL
    ),
    legacy_videos AS (
        SELECT
            cleaned.url,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY source_urls.ordinality
            ) AS sequence
        FROM scan_row
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            scan_row.video_storage_urls
        ) WITH ORDINALITY AS source_urls(url, ordinality)
        CROSS JOIN LATERAL (
            SELECT NULLIF(
                pg_catalog.BTRIM(source_urls.url),
                ''
            ) AS url
        ) AS cleaned
        WHERE cleaned.url IS NOT NULL
    ),
    legacy_counts AS (
        SELECT
            (SELECT pg_catalog.COUNT(*) FROM legacy_images)
                AS image_count,
            (SELECT pg_catalog.COUNT(*) FROM legacy_videos)
                AS video_count
    ),
    legacy_visuals AS (
        SELECT
            'image'::TEXT AS kind,
            legacy_images.url,
            legacy_images.sequence
        FROM legacy_images
        CROSS JOIN legacy_counts
        WHERE legacy_images.sequence <= CASE
            WHEN legacy_counts.video_count > 0
                THEN GREATEST(
                    legacy_counts.image_count
                        - (legacy_counts.video_count * 5),
                    0
                )
            ELSE legacy_counts.image_count
        END

        UNION ALL

        SELECT
            'video'::TEXT,
            legacy_videos.url,
            legacy_videos.sequence
        FROM legacy_videos
    ),
    expected_visuals AS (
        SELECT
            captured_visuals.kind,
            captured_visuals.url
        FROM captured_visuals

        UNION ALL

        SELECT
            legacy_visuals.kind,
            legacy_visuals.url
        FROM legacy_visuals
        WHERE NOT EXISTS (
            SELECT 1
            FROM captured_visuals
        )

        UNION ALL

        -- A structured timeline must not silently omit a durable playback URL.
        -- Refresh will create the row only when captured_media contains it, so
        -- this strict expectation turns manifest drift into finalization
        -- failure rather than losing a promoted clip.
        SELECT
            'video'::TEXT,
            legacy_videos.url
        FROM legacy_videos
        WHERE EXISTS (
            SELECT 1
            FROM captured_visuals
        )
          AND NOT EXISTS (
              SELECT 1
              FROM captured_visuals
              WHERE captured_visuals.kind = 'video'
                AND captured_visuals.url = legacy_videos.url
          )
    ),
    captured_audio AS (
        SELECT
            public.scan_media_reference_path(
                captured_items.item #> '{audio,_0}'
            ) AS url
        FROM captured_items
        WHERE public.scan_media_reference_path(
            captured_items.item #> '{audio,_0}'
        ) IS NOT NULL
    ),
    legacy_audio AS (
        SELECT cleaned.url
        FROM scan_row
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            scan_row.audio_storage_urls
        ) AS source_urls(url)
        CROSS JOIN LATERAL (
            SELECT NULLIF(
                pg_catalog.BTRIM(source_urls.url),
                ''
            ) AS url
        ) AS cleaned
        WHERE cleaned.url IS NOT NULL
    ),
    expected_media AS (
        SELECT expected_visuals.kind, expected_visuals.url
        FROM expected_visuals

        UNION ALL

        SELECT 'audio'::TEXT, captured_audio.url
        FROM captured_audio

        UNION ALL

        SELECT 'audio'::TEXT, legacy_audio.url
        FROM legacy_audio
    ),
    parsed_visual_counts AS (
        SELECT
            scan_row.endpoint,
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_row.media_counts -> 'image_count'
                ) = 'number'
                 AND scan_row.media_counts ->> 'image_count'
                        ~ '^(0|[1-9]|1[0-6])$'
                    THEN (
                        scan_row.media_counts ->> 'image_count'
                    )::INTEGER
                ELSE -1
            END AS image_count,
            CASE
                WHEN NOT (
                    COALESCE(scan_row.media_counts, '{}'::JSONB)
                        ? 'video_inference_frame_count'
                ) THEN 0
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_row.media_counts
                        -> 'video_inference_frame_count'
                ) = 'number'
                 AND scan_row.media_counts
                        ->> 'video_inference_frame_count'
                        ~ '^(0|[1-9]|1[0-6])$'
                    THEN (
                        scan_row.media_counts
                            ->> 'video_inference_frame_count'
                    )::INTEGER
                ELSE -1
            END AS frame_count,
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_row.media_counts -> 'video_count'
                ) = 'number'
                 AND scan_row.media_counts ->> 'video_count'
                        ~ '^(0|[1-9]|1[0-6])$'
                    THEN (
                        scan_row.media_counts ->> 'video_count'
                    )::INTEGER
                ELSE -1
            END AS video_count
        FROM scan_row
    ),
    declared_visual_counts AS (
        SELECT
            CASE
                -- The native endpoint records standalone images. Compatibility
                -- endpoints historically record every inference image, so
                -- remove their separately declared video-frame subset.
                WHEN parsed_visual_counts.endpoint = 'identify-multimodal'
                    THEN parsed_visual_counts.image_count
                WHEN parsed_visual_counts.endpoint IN (
                    'identify',
                    'identify-describe',
                    'audio-spec'
                )
                 AND parsed_visual_counts.frame_count >= 0
                 AND parsed_visual_counts.image_count
                        >= parsed_visual_counts.frame_count
                    THEN parsed_visual_counts.image_count
                        - parsed_visual_counts.frame_count
                ELSE -1
            END AS image_count,
            parsed_visual_counts.video_count
        FROM parsed_visual_counts
    )
    SELECT
        EXISTS (SELECT 1 FROM scan_row)
        AND (
            SELECT declared_visual_counts.image_count
            FROM declared_visual_counts
        ) = (
            SELECT pg_catalog.COUNT(*)
            FROM expected_visuals
            WHERE expected_visuals.kind = 'image'
        )
        AND (
            SELECT declared_visual_counts.video_count
            FROM declared_visual_counts
        ) = (
            SELECT pg_catalog.COUNT(*)
            FROM expected_visuals
            WHERE expected_visuals.kind = 'video'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM expected_media
            CROSS JOIN scan_row
            WHERE NOT EXISTS (
                SELECT 1
                FROM public.scan_media_assets AS assets
                WHERE assets.scan_id = scan_row.id
                  AND assets.user_id = scan_row.user_id
                  AND assets.kind = expected_media.kind
                  AND assets.status = 'ready'
                  AND assets.url = expected_media.url
            )
        );
$$;

COMMENT ON FUNCTION internal.scan_canonical_media_projection_complete(UUID) IS
  'Returns true only when endpoint-normalized visual job counts and ready owner-matched media rows cover the canonical captured-media timeline. Legacy video inference frames are thumbnail inputs, not standalone images.';

REVOKE ALL ON FUNCTION
    internal.scan_canonical_media_projection_complete(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION
    internal.scan_media_reference_is_video_inference_frame(
        p_scan_id UUID,
        p_user_id UUID,
        p_url TEXT
    )
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH scan_job AS (
        SELECT
            scans.id,
            scans.user_id,
            scans.captured_media,
            COALESCE(
                scans.image_storage_urls,
                '{}'::TEXT[]
            ) AS image_storage_urls,
            COALESCE(
                scans.video_storage_urls,
                '{}'::TEXT[]
            ) AS video_storage_urls,
            jobs.endpoint,
            jobs.media_counts
        FROM public.scans AS scans
        JOIN public.scan_ingestion_jobs AS jobs
          ON jobs.scan_id = scans.id::TEXT
         AND jobs.user_id = scans.user_id
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
          AND p_url IS NOT NULL
    ),
    parsed_declared_media AS (
        SELECT
            scan_job.endpoint,
            CASE
                WHEN NOT (
                    COALESCE(scan_job.media_counts, '{}'::JSONB)
                        ? 'video_inference_frame_count'
                ) THEN 0
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_job.media_counts
                        -> 'video_inference_frame_count'
                ) = 'number'
                 AND scan_job.media_counts
                        ->> 'video_inference_frame_count'
                        ~ '^(0|[1-9]|1[0-6])$'
                    THEN (
                        scan_job.media_counts
                            ->> 'video_inference_frame_count'
                    )::INTEGER
                ELSE -1
            END AS frame_count,
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_job.media_counts -> 'image_count'
                ) = 'number'
                 AND scan_job.media_counts ->> 'image_count'
                        ~ '^(0|[1-9]|1[0-6])$'
                    THEN (
                        scan_job.media_counts ->> 'image_count'
                    )::INTEGER
                ELSE -1
            END AS image_count
        FROM scan_job
    ),
    declared_media AS (
        SELECT
            parsed_declared_media.frame_count,
            CASE
                WHEN parsed_declared_media.endpoint = 'identify-multimodal'
                    THEN parsed_declared_media.image_count
                WHEN parsed_declared_media.endpoint IN (
                    'identify',
                    'identify-describe',
                    'audio-spec'
                )
                 AND parsed_declared_media.frame_count >= 0
                 AND parsed_declared_media.image_count
                        >= parsed_declared_media.frame_count
                    THEN parsed_declared_media.image_count
                        - parsed_declared_media.frame_count
                ELSE -1
            END AS image_count
        FROM parsed_declared_media
    ),
    captured_items AS (
        SELECT
            media_items.item,
            media_items.ordinality
        FROM scan_job
        CROSS JOIN LATERAL pg_catalog.JSONB_ARRAY_ELEMENTS(
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    scan_job.captured_media
                ) = 'array'
                    THEN scan_job.captured_media
                ELSE '[]'::JSONB
            END
        ) WITH ORDINALITY AS media_items(item, ordinality)
    ),
    captured_visuals AS (
        SELECT
            CASE
                WHEN projected_references.image_url IS NOT NULL
                    THEN 'image'::TEXT
                ELSE 'video'::TEXT
            END AS kind,
            COALESCE(
                projected_references.image_url,
                projected_references.video_url
            ) AS url
        FROM captured_items
        CROSS JOIN LATERAL (
            SELECT
                public.scan_media_reference_path(
                    captured_items.item #> '{image,_0}'
                ) AS image_url,
                public.scan_media_reference_path(
                    captured_items.item #> '{video,_0,video}'
                ) AS video_url
        ) AS projected_references
        WHERE projected_references.image_url IS NOT NULL
           OR projected_references.video_url IS NOT NULL
    ),
    legacy_images AS (
        SELECT
            cleaned.url,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY source_urls.ordinality
            ) AS sequence
        FROM scan_job
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            scan_job.image_storage_urls
        ) WITH ORDINALITY AS source_urls(url, ordinality)
        CROSS JOIN LATERAL (
            SELECT NULLIF(
                pg_catalog.BTRIM(source_urls.url),
                ''
            ) AS url
        ) AS cleaned
        WHERE cleaned.url IS NOT NULL
    ),
    legacy_counts AS (
        SELECT
            (SELECT pg_catalog.COUNT(*) FROM legacy_images)
                AS image_count,
            (
                SELECT pg_catalog.COUNT(*)
                FROM scan_job
                CROSS JOIN LATERAL pg_catalog.UNNEST(
                    scan_job.video_storage_urls
                ) AS videos(url)
                WHERE NULLIF(
                    pg_catalog.BTRIM(videos.url),
                    ''
                ) IS NOT NULL
            ) AS video_count
    ),
    projection_state AS (
        SELECT
            EXISTS (
                SELECT 1
                FROM captured_visuals
            ) AS uses_captured_visuals,
            EXISTS (
                SELECT 1
                FROM captured_visuals
                WHERE captured_visuals.kind = 'video'
            ) AS captured_has_video,
            (
                SELECT pg_catalog.COUNT(*)
                FROM captured_visuals
                WHERE captured_visuals.kind = 'image'
            ) AS captured_image_count,
            legacy_counts.image_count,
            legacy_counts.video_count
        FROM legacy_counts
    ),
    inference_frames AS (
        SELECT legacy_images.url
        FROM legacy_images
        CROSS JOIN projection_state
        WHERE (
            (
                projection_state.uses_captured_visuals
                AND projection_state.captured_has_video
                AND NOT EXISTS (
                    SELECT 1
                    FROM captured_visuals
                    WHERE captured_visuals.kind = 'image'
                      AND captured_visuals.url = legacy_images.url
                )
            )
            OR (
                NOT projection_state.uses_captured_visuals
                AND projection_state.video_count > 0
                AND legacy_images.sequence > GREATEST(
                    projection_state.image_count
                        - (projection_state.video_count * 5),
                    0
                )
            )
        )
    )
    SELECT
        EXISTS (SELECT 1 FROM scan_job)
        AND (SELECT frame_count FROM declared_media) > 0
        AND (SELECT image_count FROM declared_media) = (
            SELECT CASE
                WHEN projection_state.uses_captured_visuals
                    THEN projection_state.captured_image_count
                WHEN projection_state.video_count > 0
                    THEN GREATEST(
                        projection_state.image_count
                            - (projection_state.video_count * 5),
                        0
                    )
                ELSE projection_state.image_count
            END
            FROM projection_state
        )
        AND (SELECT frame_count FROM declared_media) = (
            SELECT pg_catalog.COUNT(*)
            FROM inference_frames
        )
        AND EXISTS (
            SELECT 1
            FROM inference_frames
            WHERE inference_frames.url = p_url
        );
$$;

COMMENT ON FUNCTION
    internal.scan_media_reference_is_video_inference_frame(
        UUID,
        UUID,
        TEXT
    ) IS
  'Classifies only owner video inference-frame URLs outside the canonical display-image projection when endpoint-normalized image counts and the complete classified set equal the job declaration.';

REVOKE ALL ON FUNCTION
    internal.scan_media_reference_is_video_inference_frame(
        UUID,
        UUID,
        TEXT
    ) FROM PUBLIC, anon, authenticated, service_role;

-- Patch only the exact validation block introduced by the finalization
-- hardening migration. Resolving the catalog definition preserves later
-- function changes, while the guarded one-for-one replacement fails the
-- migration instead of silently weakening an unexpected production routine.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT := $guard$
    PERFORM public.refresh_scan_media_assets(p_scan_id);

    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.image_storage_urls, '{}'::TEXT[])
        ) AS expected(url)
        WHERE scans.id = p_scan_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS assets
              WHERE assets.scan_id = p_scan_id
                AND assets.kind = 'image'
                AND assets.status = 'ready'
                AND assets.url = expected.url
          )
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.video_storage_urls, '{}'::TEXT[])
        ) AS expected(url)
        WHERE scans.id = p_scan_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS assets
              WHERE assets.scan_id = p_scan_id
                AND assets.kind = 'video'
                AND assets.status = 'ready'
                AND assets.url = expected.url
          )
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.audio_storage_urls, '{}'::TEXT[])
        ) AS expected(url)
        WHERE scans.id = p_scan_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS assets
              WHERE assets.scan_id = p_scan_id
                AND assets.kind = 'audio'
                AND assets.status = 'ready'
                AND assets.url = expected.url
          )
    ) THEN
        RAISE EXCEPTION 'canonical_scan_media_incomplete'
            USING ERRCODE = '55000';
    END IF;
$guard$;
    replacement_fragment TEXT := $replacement$
    PERFORM public.refresh_scan_media_assets(p_scan_id);

    IF NOT internal.scan_canonical_media_projection_complete(p_scan_id) THEN
        RAISE EXCEPTION 'canonical_scan_media_incomplete'
            USING ERRCODE = '55000';
    END IF;
$replacement$;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    IF (
        pg_catalog.LENGTH(function_definition)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(
                function_definition,
                guarded_fragment,
                ''
            )
        )
    ) / pg_catalog.LENGTH(guarded_fragment) <> 1 THEN
        RAISE EXCEPTION
            'Could not locate the exact canonical-media validation block';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );

    IF rewritten_definition IS NOT DISTINCT FROM function_definition
       OR (
            pg_catalog.LENGTH(rewritten_definition)
            - pg_catalog.LENGTH(
                pg_catalog.REPLACE(
                    rewritten_definition,
                    'internal.scan_canonical_media_projection_complete(p_scan_id)',
                    ''
                )
            )
       ) / pg_catalog.LENGTH(
            'internal.scan_canonical_media_projection_complete(p_scan_id)'
       ) <> 1 THEN
        RAISE EXCEPTION
            'Could not install the exact canonical-media projection check';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

-- Promoted sampled frames are genuine claimed capture rows, but they map to
-- compatibility image URLs rather than standalone canonical image rows. Keep
-- the captured-to-canonical proof for every other promoted item and exclude
-- only references proven by the private owner/declaration/timeline classifier.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT := $guard$
    IF EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS captured
        WHERE captured.user_id = p_user_id
          AND captured.client_scan_id = p_scan_id
          AND captured.source = 'capture_upload'
          AND captured.status = 'promoted'
          AND (
              COALESCE(
                  job_media_object_keys -> 'image',
                  '[]'::JSONB
              ) ? captured.storage_key
              OR COALESCE(
                  job_media_object_keys -> 'video',
                  '[]'::JSONB
              ) ? captured.storage_key
              OR COALESCE(
                  job_media_object_keys -> 'audio',
                  '[]'::JSONB
              ) ? captured.storage_key
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS canonical
              WHERE canonical.scan_id = p_scan_id
                AND canonical.kind = captured.kind
                AND canonical.status = 'ready'
                AND canonical.url = captured.url
          )
    ) THEN
        RAISE EXCEPTION 'canonical_scan_media_manifest_incomplete'
            USING ERRCODE = '55000';
    END IF;
$guard$;
    replacement_fragment TEXT := $replacement$
    IF EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS captured
        WHERE captured.user_id = p_user_id
          AND captured.client_scan_id = p_scan_id
          AND captured.source = 'capture_upload'
          AND captured.status = 'promoted'
          AND (
              COALESCE(
                  job_media_object_keys -> 'image',
                  '[]'::JSONB
              ) ? captured.storage_key
              OR COALESCE(
                  job_media_object_keys -> 'video',
                  '[]'::JSONB
              ) ? captured.storage_key
              OR COALESCE(
                  job_media_object_keys -> 'audio',
                  '[]'::JSONB
              ) ? captured.storage_key
          )
          AND NOT (
              captured.kind = 'image'
              AND internal.scan_media_reference_is_video_inference_frame(
                  p_scan_id,
                  p_user_id,
                  captured.url
              )
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS canonical
              WHERE canonical.scan_id = p_scan_id
                AND canonical.kind = captured.kind
                AND canonical.status = 'ready'
                AND canonical.url = captured.url
          )
    ) THEN
        RAISE EXCEPTION 'canonical_scan_media_manifest_incomplete'
            USING ERRCODE = '55000';
    END IF;
$replacement$;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    IF (
        pg_catalog.LENGTH(function_definition)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(
                function_definition,
                guarded_fragment,
                ''
            )
        )
    ) / pg_catalog.LENGTH(guarded_fragment) <> 1 THEN
        RAISE EXCEPTION
            'Could not locate the exact captured-media validation block';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );

    IF rewritten_definition IS NOT DISTINCT FROM function_definition
       OR (
            pg_catalog.LENGTH(rewritten_definition)
            - pg_catalog.LENGTH(
                pg_catalog.REPLACE(
                    rewritten_definition,
                    'internal.scan_media_reference_is_video_inference_frame(',
                    ''
                )
            )
       ) / pg_catalog.LENGTH(
            'internal.scan_media_reference_is_video_inference_frame('
       ) <> 1 THEN
        RAISE EXCEPTION
            'Could not install the exact video-frame manifest exclusion';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

REVOKE ALL ON FUNCTION public.complete_scan_ingestion_finalization(
    UUID,
    UUID,
    JSONB,
    TEXT[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_scan_ingestion_finalization(
    UUID,
    UUID,
    JSONB,
    TEXT[]
) TO service_role;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
