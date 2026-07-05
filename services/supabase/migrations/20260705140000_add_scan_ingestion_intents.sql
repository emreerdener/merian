-- Durable, service-role-only scan ingestion intent snapshots.
--
-- scan_ingestion_jobs is the state ledger. This table stores the sanitized
-- non-media request intent needed to resume staged-media ingestion later without
-- storing raw media bytes or local device file paths.

CREATE TABLE IF NOT EXISTS public.scan_ingestion_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id TEXT NOT NULL,
    user_id UUID NOT NULL,
    endpoint TEXT NOT NULL DEFAULT 'identify-multimodal',
    payload_schema_version INTEGER NOT NULL DEFAULT 1,
    request_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    media_counts JSONB NOT NULL DEFAULT '{}'::JSONB,
    media_object_keys JSONB NOT NULL DEFAULT '{}'::JSONB,
    upload_session_ids UUID[] NOT NULL DEFAULT '{}'::UUID[],
    manifest_checksum TEXT,
    payload_checksum TEXT,
    resumable BOOLEAN NOT NULL DEFAULT TRUE,
    inline_media_redacted BOOLEAN NOT NULL DEFAULT FALSE,
    redacted_media_counts JSONB NOT NULL DEFAULT '{}'::JSONB,
    claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_replayed_at TIMESTAMPTZ,
    replay_attempt_count INTEGER NOT NULL DEFAULT 0,
    last_replay_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, scan_id),
    CONSTRAINT scan_ingestion_intents_payload_object
        CHECK (jsonb_typeof(request_payload) = 'object'),
    CONSTRAINT scan_ingestion_intents_media_counts_object
        CHECK (jsonb_typeof(media_counts) = 'object'),
    CONSTRAINT scan_ingestion_intents_media_object_keys_object
        CHECK (jsonb_typeof(media_object_keys) = 'object'),
    CONSTRAINT scan_ingestion_intents_redacted_counts_object
        CHECK (jsonb_typeof(redacted_media_counts) = 'object'),
    CONSTRAINT scan_ingestion_intents_replay_attempt_nonnegative
        CHECK (replay_attempt_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_intents_scan_user
    ON public.scan_ingestion_intents(user_id, scan_id);

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_intents_manifest_checksum
    ON public.scan_ingestion_intents(user_id, manifest_checksum)
    WHERE manifest_checksum IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_intents_resumable_updated
    ON public.scan_ingestion_intents(updated_at)
    WHERE resumable = TRUE;

ALTER TABLE public.scan_ingestion_intents ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.scan_ingestion_intents IS
  'Service-role-only sanitized scan ingestion request snapshots. Stores replay intent and staged media references, never raw media bytes.';
COMMENT ON COLUMN public.scan_ingestion_intents.request_payload IS
  'Sanitized non-media request payload: telemetry, observation context, descriptors, and staged object keys. Inline media bytes and local file paths are excluded.';
COMMENT ON COLUMN public.scan_ingestion_intents.resumable IS
  'True when the persisted intent contains enough staged/cloud references for server-side replay without client media bytes.';
COMMENT ON COLUMN public.scan_ingestion_intents.inline_media_redacted IS
  'True when inline base64 media was present in the accepted request and intentionally omitted from request_payload.';
COMMENT ON COLUMN public.scan_ingestion_intents.payload_checksum IS
  'SHA-256 checksum of the sanitized request_payload used to detect replay intent drift.';

CREATE OR REPLACE FUNCTION public.record_scan_ingestion_intent(
    p_scan_id TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_request_payload JSONB,
    p_media_counts JSONB DEFAULT '{}'::JSONB,
    p_media_object_keys JSONB DEFAULT '{}'::JSONB,
    p_upload_session_ids UUID[] DEFAULT '{}'::UUID[],
    p_manifest_checksum TEXT DEFAULT NULL,
    p_payload_checksum TEXT DEFAULT NULL,
    p_resumable BOOLEAN DEFAULT TRUE,
    p_inline_media_redacted BOOLEAN DEFAULT FALSE,
    p_redacted_media_counts JSONB DEFAULT '{}'::JSONB,
    p_payload_schema_version INTEGER DEFAULT 1
)
RETURNS public.scan_ingestion_intents
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    recorded public.scan_ingestion_intents;
BEGIN
    IF NULLIF(BTRIM(COALESCE(p_scan_id, '')), '') IS NULL THEN
        RAISE EXCEPTION 'scan_id is required';
    END IF;

    INSERT INTO public.scan_ingestion_intents (
        scan_id,
        user_id,
        endpoint,
        payload_schema_version,
        request_payload,
        media_counts,
        media_object_keys,
        upload_session_ids,
        manifest_checksum,
        payload_checksum,
        resumable,
        inline_media_redacted,
        redacted_media_counts,
        claimed_at,
        updated_at
    )
    VALUES (
        p_scan_id,
        p_user_id,
        COALESCE(NULLIF(BTRIM(p_endpoint), ''), 'identify-multimodal'),
        GREATEST(COALESCE(p_payload_schema_version, 1), 1),
        COALESCE(p_request_payload, '{}'::JSONB),
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        COALESCE(p_upload_session_ids, '{}'::UUID[]),
        NULLIF(BTRIM(COALESCE(p_manifest_checksum, '')), ''),
        NULLIF(BTRIM(COALESCE(p_payload_checksum, '')), ''),
        COALESCE(p_resumable, TRUE),
        COALESCE(p_inline_media_redacted, FALSE),
        COALESCE(p_redacted_media_counts, '{}'::JSONB),
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET
        endpoint = EXCLUDED.endpoint,
        payload_schema_version = EXCLUDED.payload_schema_version,
        request_payload = EXCLUDED.request_payload,
        media_counts = EXCLUDED.media_counts,
        media_object_keys = EXCLUDED.media_object_keys,
        upload_session_ids = EXCLUDED.upload_session_ids,
        manifest_checksum = COALESCE(EXCLUDED.manifest_checksum, public.scan_ingestion_intents.manifest_checksum),
        payload_checksum = COALESCE(EXCLUDED.payload_checksum, public.scan_ingestion_intents.payload_checksum),
        resumable = EXCLUDED.resumable,
        inline_media_redacted = EXCLUDED.inline_media_redacted,
        redacted_media_counts = EXCLUDED.redacted_media_counts,
        claimed_at = NOW(),
        updated_at = NOW()
    RETURNING * INTO recorded;

    RETURN recorded;
END;
$$;

REVOKE ALL ON FUNCTION public.record_scan_ingestion_intent(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    JSONB,
    UUID[],
    TEXT,
    TEXT,
    BOOLEAN,
    BOOLEAN,
    JSONB,
    INTEGER
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_scan_ingestion_intent(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    JSONB,
    UUID[],
    TEXT,
    TEXT,
    BOOLEAN,
    BOOLEAN,
    JSONB,
    INTEGER
) TO service_role;

NOTIFY pgrst, 'reload schema';
