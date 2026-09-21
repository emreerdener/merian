\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(8);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.scan_media_assets'::REGCLASS
      AND conname = 'scan_media_assets_scan_id_order_index_key'
  ) THEN
    RAISE EXCEPTION 'legacy scan/order uniqueness constraint still exists';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'scan_media_assets'
      AND indexname = 'idx_scan_media_assets_generated_unique'
      AND indexdef LIKE '%UNIQUE INDEX%'
      AND indexdef LIKE '%(scan_id, source, role, order_index)%'
      AND indexdef LIKE '%source = ANY%scan_refresh%backfill%'
  ) THEN
    RAISE EXCEPTION 'source-aware generated-media unique index is missing or malformed';
  END IF;
END;
$$;
SELECT extensions.pass(
  'legacy global scan/order uniqueness is replaced by source-aware uniqueness'
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
  '00000000-0000-0000-0000-000000000501'::UUID,
  'authenticated',
  'authenticated',
  'scan-media-uniqueness@naturebook.invalid',
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
  '00000000-0000-0000-0000-000000000501',
  'scan-media-uniqueness@naturebook.invalid',
  'scan_media_501',
  'Scan Media',
  'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;

INSERT INTO public.scans (id, user_id, ai_confidence_score)
VALUES (
  '00000000-0000-0000-0000-000000000511',
  '00000000-0000-0000-0000-000000000501',
  0.91
);

INSERT INTO public.scan_media_assets (
  id,
  scan_id,
  user_id,
  kind,
  role,
  status,
  source,
  url,
  order_index
)
VALUES (
  '00000000-0000-0000-0000-000000000521',
  '00000000-0000-0000-0000-000000000511',
  '00000000-0000-0000-0000-000000000501',
  'image',
  'display',
  'ready',
  'scan_refresh',
  'https://media.naturebook.invalid/generated.webp',
  0
);

INSERT INTO public.scan_media_assets (
  id,
  scan_id,
  client_scan_id,
  upload_session_id,
  user_id,
  kind,
  role,
  status,
  source,
  url,
  storage_key,
  order_index
)
VALUES (
  '00000000-0000-0000-0000-000000000522',
  '00000000-0000-0000-0000-000000000511',
  '00000000-0000-0000-0000-000000000511',
  '00000000-0000-0000-0000-000000000531',
  '00000000-0000-0000-0000-000000000501',
  'image',
  'display',
  'promoted',
  'capture_upload',
  'https://media.naturebook.invalid/promoted.webp',
  'public_uploads/test/promoted.webp',
  0
);

DO $$
BEGIN
  IF (
    SELECT COUNT(*)
    FROM public.scan_media_assets
    WHERE scan_id = '00000000-0000-0000-0000-000000000511'
      AND order_index = 0
  ) <> 2 THEN
    RAISE EXCEPTION 'generated and promoted lifecycle rows did not coexist';
  END IF;
END;
$$;
SELECT extensions.pass(
  'promoted capture-upload and generated rows can share a scan position'
);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.scan_media_assets (
      id,
      scan_id,
      user_id,
      kind,
      role,
      status,
      source,
      url,
      order_index
    )
    VALUES (
      '00000000-0000-0000-0000-000000000523',
      '00000000-0000-0000-0000-000000000511',
      '00000000-0000-0000-0000-000000000501',
      'image',
      'display',
      'ready',
      'scan_refresh',
      'https://media.naturebook.invalid/duplicate-generated.webp',
      0
    );
    RAISE EXCEPTION 'duplicate generated media position unexpectedly passed validation';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
END;
$$;
SELECT extensions.pass(
  'duplicate generated rows remain rejected within the same source and role'
);


SELECT extensions.ok(
  NOT pg_catalog.has_function_privilege('anon', 'internal.enforce_staged_scan_media_budget()', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('authenticated', 'internal.enforce_staged_scan_media_budget()', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('service_role', 'internal.enforce_staged_scan_media_budget()', 'EXECUTE'),
  'staged budget trigger remains unavailable for direct API execution'
);

SELECT extensions.lives_ok($test$
  INSERT INTO public.scan_media_assets (
    upload_session_id, client_scan_id, user_id, kind, role, status, source, storage_key, order_index
  )
  SELECT
    '00000000-0000-0000-0000-000000000532'::UUID,
    '00000000-0000-0000-0000-000000000511'::UUID,
    '00000000-0000-0000-0000-000000000501'::UUID,
    CASE WHEN n <= 5 THEN 'image' WHEN n <= 7 THEN 'audio' ELSE 'video' END,
    CASE WHEN n <= 5 THEN 'inference_frame' WHEN n <= 7 THEN 'audio' ELSE 'playback' END,
    'staged', 'capture_upload', 'staging/synthetic-video-budget/' || n::TEXT, n
  FROM pg_catalog.generate_series(1, 8) AS n;
$test$, 'five frames, two audio clips, and playback video fit the staged source budget');

SELECT extensions.throws_ok($test$
  INSERT INTO public.scan_media_assets (
    upload_session_id, client_scan_id, user_id, kind, role, status, source, storage_key, order_index
  ) VALUES (
    pg_catalog.gen_random_uuid(),
    '00000000-0000-0000-0000-000000000511',
    '00000000-0000-0000-0000-000000000501',
    'image', 'display', 'staged', 'capture_upload', 'staging/synthetic-video-budget/9', 9
  );
$test$, '54000', 'staged_scan_media_budget_exceeded', 'a ninth staged source is rejected');

SELECT extensions.lives_ok($test$
  UPDATE public.scan_media_assets SET updated_at = pg_catalog.NOW()
  WHERE storage_key = 'staging/synthetic-video-budget/8';
$test$, 'updating an existing source at the cap does not count itself twice');

SELECT extensions.lives_ok($test$
  UPDATE public.scan_media_assets SET status = 'failed'
  WHERE storage_key = 'staging/synthetic-video-budget/8';
  INSERT INTO public.scan_media_assets (
    upload_session_id, client_scan_id, user_id, kind, role, status, source, storage_key, order_index
  ) VALUES (
    pg_catalog.gen_random_uuid(),
    '00000000-0000-0000-0000-000000000511',
    '00000000-0000-0000-0000-000000000501',
    'video', 'playback', 'staged', 'capture_upload', 'staging/synthetic-video-budget/replacement', 8
  );
$test$, 'historical failed and promoted rows do not consume active staging slots');

SELECT * FROM extensions.finish();
ROLLBACK;
