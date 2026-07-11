-- Content-addressed publication moderation attestations. No transcript, URL,
-- filename, user identity, or media bytes are persisted here.
CREATE TABLE IF NOT EXISTS public.explore_audio_moderation_attestations (
    checksum_sha256 TEXT NOT NULL CHECK (checksum_sha256 ~ '^[a-f0-9]{64}$'),
    policy_version TEXT NOT NULL CHECK (length(policy_version) BETWEEN 1 AND 100),
    model TEXT NOT NULL CHECK (length(model) BETWEEN 1 AND 100),
    approved BOOLEAN NOT NULL,
    media_type TEXT NOT NULL CHECK (length(media_type) BETWEEN 1 AND 100),
    byte_size BIGINT NOT NULL CHECK (byte_size > 0 AND byte_size <= 12582912),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (checksum_sha256, policy_version, model)
);

ALTER TABLE public.explore_audio_moderation_attestations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.explore_audio_moderation_attestations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.explore_audio_moderation_attestations TO service_role;

COMMENT ON TABLE public.explore_audio_moderation_attestations IS
  'Service-only, content-addressed Gemini publication decisions. Stores no transcript, URL, user identity, or media bytes.';
