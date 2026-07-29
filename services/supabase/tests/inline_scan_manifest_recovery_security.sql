\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(23);

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
    '00000000-0000-4000-8000-00000000f101'::UUID,
    'authenticated',
    'authenticated',
    'inline-recovery@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000f101',
    'inline-recovery@naturebook.invalid',
    'inline_recovery_f101',
    'Inline Recovery',
    'alias'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.recover_inline_scan_ingestion_completion(uuid,uuid)',
        'EXECUTE'
    ),
    'anonymous callers cannot execute inline completion recovery'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.recover_inline_scan_ingestion_completion(uuid,uuid)',
        'EXECUTE'
    ),
    'authenticated callers cannot execute inline completion recovery'
);
SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.recover_inline_scan_ingestion_completion(uuid,uuid)',
        'EXECUTE'
    ),
    'service-role callers can execute inline completion recovery'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.inline_scan_recovery_ledger_matches(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,text[],text[])',
        'EXECUTE'
    ),
    'anonymous callers cannot execute the private ledger validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.inline_scan_recovery_ledger_matches(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,text[],text[])',
        'EXECUTE'
    ),
    'authenticated callers cannot execute the private ledger validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.inline_scan_recovery_ledger_matches(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,text[],text[])',
        'EXECUTE'
    ),
    'service-role callers cannot bypass the recovery wrapper through the ledger validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.inline_scan_recovery_scan_media_match(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,uuid,text[],text[],text[],boolean,integer)',
        'EXECUTE'
    ),
    'anonymous callers cannot execute the private canonical-media validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.inline_scan_recovery_scan_media_match(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,uuid,text[],text[],text[],boolean,integer)',
        'EXECUTE'
    ),
    'authenticated callers cannot execute the private canonical-media validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.inline_scan_recovery_scan_media_match(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,uuid,text[],text[],text[],boolean,integer)',
        'EXECUTE'
    ),
    'service-role callers cannot bypass the recovery wrapper through the canonical-media validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.inline_scan_recovery_staged_assets_match(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,uuid,text[],text[],boolean,integer,integer,integer)',
        'EXECUTE'
    ),
    'anonymous callers cannot execute the private staged-asset validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.inline_scan_recovery_staged_assets_match(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,uuid,text[],text[],boolean,integer,integer,integer)',
        'EXECUTE'
    ),
    'authenticated callers cannot execute the private staged-asset validator'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.inline_scan_recovery_staged_assets_match(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,uuid,text[],text[],boolean,integer,integer,integer)',
        'EXECUTE'
    ),
    'service-role callers cannot bypass the recovery wrapper through the staged-asset validator'
);

INSERT INTO public.scans (
    id,
    user_id,
    image_storage_urls,
    video_storage_urls,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES
    (
        '00000000-0000-4000-8000-00000000f110',
        '00000000-0000-4000-8000-00000000f101',
        ARRAY[
            'https://media.merian.app/public_uploads/free/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f120.webp',
            'https://media.merian.app/public_uploads/free/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f122.webp'
        ],
        '{}'::TEXT[],
        0.91,
        pg_catalog.NOW(),
        TRUE
    ),
    (
        '00000000-0000-4000-8000-00000000f111',
        '00000000-0000-4000-8000-00000000f101',
        ARRAY[
            'https://media.merian.app/public_uploads/free/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f121.webp'
        ],
        '{}'::TEXT[],
        0.92,
        pg_catalog.NOW(),
        TRUE
    ),
    (
        '00000000-0000-4000-8000-00000000f112',
        '00000000-0000-4000-8000-00000000f101',
        ARRAY[
            'https://media.merian.app/public_uploads/pro/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f123.webp',
            'https://media.merian.app/public_uploads/pro/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f124.webp'
        ],
        ARRAY[
            'https://media.merian.app/public_uploads/pro/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f140.mp4'
        ],
        0.93,
        pg_catalog.NOW(),
        TRUE
    ),
    (
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f101',
        ARRAY[
            'https://media.merian.app/public_uploads/free/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f125.webp',
            'https://media.merian.app/public_uploads/free/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f126.webp'
        ],
        '{}'::TEXT[],
        0.94,
        pg_catalog.NOW(),
        TRUE
    );

INSERT INTO public.scan_ingestion_jobs (
    scan_id,
    user_id,
    endpoint,
    status,
    stage,
    attempt_count,
    media_counts,
    media_object_keys,
    upload_session_ids,
    last_error
)
VALUES
    (
        '00000000-0000-4000-8000-00000000f110',
        '00000000-0000-4000-8000-00000000f101',
        'identify-multimodal',
        'failed_retryable',
        'background_ingestion_failed',
        1,
        '{
          "image_count":2,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_inference_frame_count":0
        }'::JSONB,
        '{
          "image":[
            "staging/device-installation/00000000-0000-4000-8000-00000000f120.webp"
          ],
          "audio":[],
          "video":[]
        }'::JSONB,
        '{}'::UUID[],
        'completeScanIngestionFinalization: scan_media_promotion_incomplete'
    ),
    (
        '00000000-0000-4000-8000-00000000f111',
        '00000000-0000-4000-8000-00000000f101',
        'identify',
        'failed_retryable',
        'media_finalization_failed',
        1,
        '{
          "image_count":2,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_inference_frame_count":0
        }'::JSONB,
        '{
          "image":[
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f121.webp"
          ],
          "audio":[],
          "video":[]
        }'::JSONB,
        '{}'::UUID[],
        'completeScanIngestionFinalization: scan_media_promotion_incomplete'
    ),
    (
        '00000000-0000-4000-8000-00000000f112',
        '00000000-0000-4000-8000-00000000f101',
        'identify-multimodal',
        'failed_retryable',
        'media_finalization_failed',
        1,
        '{
          "image_count":0,
          "audio_count":0,
          "video_count":1,
          "required_video_count":1,
          "video_inference_frame_count":2
        }'::JSONB,
        '{
          "image":[
            "staging/device-installation/00000000-0000-4000-8000-00000000f123.webp"
          ],
          "audio":[],
          "video":[
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f140.mp4"
          ]
        }'::JSONB,
        ARRAY[
            '00000000-0000-4000-8000-00000000f131'::UUID
        ],
        'completeScanIngestionFinalization: scan_media_promotion_incomplete'
    ),
    (
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f101',
        'identify-multimodal',
        'failed_retryable',
        'media_finalization_failed',
        1,
        '{
          "image_count":2,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_inference_frame_count":0
        }'::JSONB,
        '{
          "image":[
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f125.webp",
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f126.webp"
          ],
          "audio":[],
          "video":[]
        }'::JSONB,
        ARRAY[
            '00000000-0000-4000-8000-00000000f132'::UUID,
            '00000000-0000-4000-8000-00000000f133'::UUID
        ],
        'completeScanIngestionFinalization: scan_media_promotion_incomplete'
    );

INSERT INTO public.scan_ingestion_intents (
    scan_id,
    user_id,
    endpoint,
    request_payload,
    media_counts,
    media_object_keys,
    upload_session_ids,
    resumable,
    inline_media_redacted,
    redacted_media_counts
)
VALUES
    (
        '00000000-0000-4000-8000-00000000f110',
        '00000000-0000-4000-8000-00000000f101',
        'identify-multimodal',
        '{
          "clientScanId":"00000000-0000-4000-8000-00000000f110",
          "media":{
            "r2ObjectKeys":[
              "staging/device-installation/00000000-0000-4000-8000-00000000f120.webp"
            ],
            "audioR2ObjectKeys":[],
            "videoR2ObjectKeys":[],
            "audioMediaItems":[]
          },
          "mediaCounts":{
            "image_count":2,
            "audio_count":0,
            "video_count":0,
            "required_video_count":0,
            "video_inference_frame_count":0
          },
          "uploadSessionIds":[],
          "redactedMediaCounts":{
            "image_base64_count":2,
            "audio_base64_count":0
          }
        }'::JSONB,
        '{
          "image_count":2,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_inference_frame_count":0
        }'::JSONB,
        '{
          "image":[
            "staging/device-installation/00000000-0000-4000-8000-00000000f120.webp"
          ],
          "audio":[],
          "video":[]
        }'::JSONB,
        '{}'::UUID[],
        FALSE,
        TRUE,
        '{"image_base64_count":2,"audio_base64_count":0}'::JSONB
    ),
    (
        '00000000-0000-4000-8000-00000000f111',
        '00000000-0000-4000-8000-00000000f101',
        'identify',
        '{
          "clientScanId":"00000000-0000-4000-8000-00000000f111",
          "media":{
            "r2ObjectKeys":[
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f121.webp"
            ],
            "audioR2ObjectKeys":[],
            "videoR2ObjectKeys":[],
            "audioMediaItems":[]
          },
          "mediaCounts":{
            "image_count":2,
            "audio_count":0,
            "video_count":0,
            "required_video_count":0,
            "video_inference_frame_count":0
          },
          "uploadSessionIds":[],
          "redactedMediaCounts":{
            "image_base64_count":1,
            "audio_base64_count":0
          }
        }'::JSONB,
        '{
          "image_count":2,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_inference_frame_count":0
        }'::JSONB,
        '{
          "image":[
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f121.webp"
          ],
          "audio":[],
          "video":[]
        }'::JSONB,
        '{}'::UUID[],
        FALSE,
        TRUE,
        '{"image_base64_count":1,"audio_base64_count":0}'::JSONB
    ),
    (
        '00000000-0000-4000-8000-00000000f112',
        '00000000-0000-4000-8000-00000000f101',
        'identify-multimodal',
        '{
          "clientScanId":"00000000-0000-4000-8000-00000000f112",
          "media":{
            "r2ObjectKeys":[
              "staging/device-installation/00000000-0000-4000-8000-00000000f123.webp"
            ],
            "audioR2ObjectKeys":[],
            "videoR2ObjectKeys":[
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f140.mp4"
            ],
            "audioMediaItems":[]
          },
          "mediaCounts":{
            "image_count":0,
            "audio_count":0,
            "video_count":1,
            "required_video_count":1,
            "video_inference_frame_count":2
          },
          "uploadSessionIds":[
            "00000000-0000-4000-8000-00000000f131"
          ],
          "redactedMediaCounts":{
            "image_base64_count":2,
            "audio_base64_count":0
          }
        }'::JSONB,
        '{
          "image_count":0,
          "audio_count":0,
          "video_count":1,
          "required_video_count":1,
          "video_inference_frame_count":2
        }'::JSONB,
        '{
          "image":[
            "staging/device-installation/00000000-0000-4000-8000-00000000f123.webp"
          ],
          "audio":[],
          "video":[
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f140.mp4"
          ]
        }'::JSONB,
        ARRAY[
            '00000000-0000-4000-8000-00000000f131'::UUID
        ],
        FALSE,
        TRUE,
        '{"image_base64_count":2,"audio_base64_count":0}'::JSONB
    ),
    (
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f101',
        'identify-multimodal',
        '{
          "clientScanId":"00000000-0000-4000-8000-00000000f113",
          "media":{
            "r2ObjectKeys":[
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f125.webp",
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f126.webp"
            ],
            "audioR2ObjectKeys":[],
            "videoR2ObjectKeys":[],
            "audioMediaItems":[]
          },
          "mediaCounts":{
            "image_count":2,
            "audio_count":0,
            "video_count":0,
            "required_video_count":0,
            "video_inference_frame_count":0
          },
          "uploadSessionIds":[
            "00000000-0000-4000-8000-00000000f132",
            "00000000-0000-4000-8000-00000000f133"
          ],
          "redactedMediaCounts":{
            "image_base64_count":0,
            "audio_base64_count":0
          }
        }'::JSONB,
        '{
          "image_count":2,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_inference_frame_count":0
        }'::JSONB,
        '{
          "image":[
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f125.webp",
            "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f126.webp"
          ],
          "audio":[],
          "video":[]
        }'::JSONB,
        ARRAY[
            '00000000-0000-4000-8000-00000000f132'::UUID,
            '00000000-0000-4000-8000-00000000f133'::UUID
        ],
        TRUE,
        FALSE,
        '{"image_base64_count":0,"audio_base64_count":0}'::JSONB
    );

INSERT INTO public.scan_media_assets (
    client_scan_id,
    upload_session_id,
    user_id,
    kind,
    role,
    status,
    source,
    storage_key,
    order_index
)
VALUES (
    '00000000-0000-4000-8000-00000000f112',
    '00000000-0000-4000-8000-00000000f131',
    '00000000-0000-4000-8000-00000000f101',
    'video',
    'playback',
    'staged',
    'capture_upload',
    'staging/00000000-0000-4000-8000-00000000f101/'
        || '00000000-0000-4000-8000-00000000f140.mp4',
    0
);

INSERT INTO public.scan_media_assets (
    client_scan_id,
    upload_session_id,
    user_id,
    kind,
    role,
    status,
    source,
    storage_key,
    order_index,
    failure_reason
)
VALUES
    (
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f132',
        '00000000-0000-4000-8000-00000000f101',
        'image',
        'display',
        'staged',
        'capture_upload',
        'staging/00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f125.webp',
        0,
        NULL
    ),
    (
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f132',
        '00000000-0000-4000-8000-00000000f101',
        'image',
        'display',
        'staged',
        'capture_upload',
        'staging/00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f126.webp',
        1,
        NULL
    ),
    (
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f133',
        '00000000-0000-4000-8000-00000000f101',
        'image',
        'display',
        'failed',
        'capture_upload',
        'staging/00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f125.webp',
        0,
        'superseded_staging_registration'
    );

SELECT extensions.is(
    public.recover_inline_scan_ingestion_completion(
        '00000000-0000-4000-8000-00000000f110',
        '00000000-0000-4000-8000-00000000f101'
    ),
    'completed',
    'the exact phantom inline-image manifest is completed atomically'
);
SELECT extensions.ok(
    (
        SELECT jobs.status = 'complete'
            AND jobs.media_object_keys = '{
              "image":[],
              "audio":[],
              "video":[]
            }'::JSONB
            AND jobs.manifest_checksum = intents.manifest_checksum
            AND intents.request_payload #> '{media,r2ObjectKeys}'
                = '[]'::JSONB
        FROM public.scan_ingestion_jobs AS jobs
        JOIN public.scan_ingestion_intents AS intents
          ON intents.user_id = jobs.user_id
         AND intents.scan_id = jobs.scan_id
        WHERE jobs.scan_id =
            '00000000-0000-4000-8000-00000000f110'
    ),
    'repair normalizes both ledgers and preserves checksum agreement'
);
SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS assets
        WHERE assets.scan_id =
            '00000000-0000-4000-8000-00000000f110'
          AND assets.user_id =
            '00000000-0000-4000-8000-00000000f101'
          AND assets.kind = 'image'
          AND assets.status = 'ready'
          AND assets.url LIKE
            'https://media.merian.app/public_uploads/%'
    ),
    'canonical finalization leaves the durable image asset ready'
);

SELECT extensions.is(
    public.recover_inline_scan_ingestion_completion(
        '00000000-0000-4000-8000-00000000f112',
        '00000000-0000-4000-8000-00000000f101'
    ),
    'completed',
    'mixed video recovery removes only the phantom image hint'
);
SELECT extensions.ok(
    (
        SELECT jobs.status = 'complete'
            AND jobs.media_object_keys -> 'image' = '[]'::JSONB
            AND jobs.media_object_keys -> 'video' = '[
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f140.mp4"
            ]'::JSONB
            AND jobs.upload_session_ids = ARRAY[
              '00000000-0000-4000-8000-00000000f131'::UUID
            ]
            AND jobs.manifest_checksum = intents.manifest_checksum
        FROM public.scan_ingestion_jobs AS jobs
        JOIN public.scan_ingestion_intents AS intents
          ON intents.user_id = jobs.user_id
         AND intents.scan_id = jobs.scan_id
        WHERE jobs.scan_id =
            '00000000-0000-4000-8000-00000000f112'
    ),
    'mixed recovery preserves the real video manifest and upload identity'
);
SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS assets
        WHERE assets.client_scan_id =
            '00000000-0000-4000-8000-00000000f112'
          AND assets.storage_key =
            'staging/00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f140.mp4'
          AND assets.scan_id =
            '00000000-0000-4000-8000-00000000f112'
          AND assets.kind = 'video'
          AND assets.status = 'promoted'
          AND assets.url =
            'https://media.merian.app/public_uploads/pro/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f140.mp4'
    )
    AND EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS assets
        WHERE assets.scan_id =
            '00000000-0000-4000-8000-00000000f112'
          AND assets.kind = 'video'
          AND assets.status = 'ready'
          AND assets.url =
            'https://media.merian.app/public_uploads/pro/'
            || '00000000-0000-4000-8000-00000000f101/'
            || '00000000-0000-4000-8000-00000000f140.mp4'
    ),
    'mixed recovery promotes the capture row and refreshes canonical video'
);

SELECT extensions.is(
    public.recover_inline_scan_ingestion_completion(
        '00000000-0000-4000-8000-00000000f113',
        '00000000-0000-4000-8000-00000000f101'
    ),
    'completed',
    'offline queued images remain real staged sources and complete atomically'
);
SELECT extensions.ok(
    (
        SELECT jobs.status = 'complete'
            AND jobs.media_object_keys -> 'image' = '[
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f125.webp",
              "staging/00000000-0000-4000-8000-00000000f101/00000000-0000-4000-8000-00000000f126.webp"
            ]'::JSONB
            AND jobs.upload_session_ids = ARRAY[
              '00000000-0000-4000-8000-00000000f132'::UUID,
              '00000000-0000-4000-8000-00000000f133'::UUID
            ]
            AND jobs.manifest_checksum = intents.manifest_checksum
            AND intents.resumable = TRUE
            AND intents.inline_media_redacted = FALSE
        FROM public.scan_ingestion_jobs AS jobs
        JOIN public.scan_ingestion_intents AS intents
          ON intents.user_id = jobs.user_id
         AND intents.scan_id = jobs.scan_id
        WHERE jobs.scan_id =
            '00000000-0000-4000-8000-00000000f113'
    ),
    'offline recovery preserves real image keys, sessions, and resumability'
);
SELECT extensions.ok(
    (
        SELECT pg_catalog.COUNT(*) = 2
        FROM public.scan_media_assets AS assets
        WHERE assets.client_scan_id =
            '00000000-0000-4000-8000-00000000f113'
          AND assets.kind = 'image'
          AND assets.status = 'promoted'
          AND assets.scan_id =
            '00000000-0000-4000-8000-00000000f113'
    )
    AND (
        SELECT pg_catalog.COUNT(*) = 2
        FROM public.scan_media_assets AS assets
        WHERE assets.scan_id =
            '00000000-0000-4000-8000-00000000f113'
          AND assets.kind = 'image'
          AND assets.status = 'ready'
    )
    AND EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS assets
        WHERE assets.client_scan_id =
            '00000000-0000-4000-8000-00000000f113'
          AND assets.status = 'failed'
          AND assets.failure_reason =
            'superseded_staging_registration'
    ),
    'offline recovery promotes each canonical source and ignores only the marked duplicate'
);

INSERT INTO public.scan_media_assets (
    client_scan_id,
    upload_session_id,
    user_id,
    kind,
    role,
    status,
    source,
    storage_key,
    order_index
)
VALUES (
    '00000000-0000-4000-8000-00000000f111',
    '00000000-0000-4000-8000-00000000f130',
    '00000000-0000-4000-8000-00000000f101',
    'image',
    'display',
    'staged',
    'capture_upload',
    'staging/00000000-0000-4000-8000-00000000f101/'
        || '00000000-0000-4000-8000-00000000f121.webp',
    0
);

SELECT extensions.is(
    public.recover_inline_scan_ingestion_completion(
        '00000000-0000-4000-8000-00000000f111',
        '00000000-0000-4000-8000-00000000f101'
    ),
    'not_applicable',
    'recovery refuses to discard a real capture-upload source'
);
SELECT extensions.ok(
    (
        SELECT jobs.status = 'failed_retryable'
            AND pg_catalog.JSONB_ARRAY_LENGTH(
                jobs.media_object_keys -> 'image'
            ) = 1
        FROM public.scan_ingestion_jobs AS jobs
        WHERE jobs.scan_id =
            '00000000-0000-4000-8000-00000000f111'
    ),
    'a refused repair leaves the real staged manifest untouched'
);

SELECT * FROM extensions.finish();
ROLLBACK;
