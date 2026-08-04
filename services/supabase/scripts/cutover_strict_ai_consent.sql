-- Run only after the replacement consent-capable TestFlight build is verified
-- and every older beta build has been expired in App Store Connect. This is a
-- one-way owner operation: afterward every Gemini-backed route requires the
-- current 18+ self-attestation, Terms receipt, and Gemini grant.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '30s';

UPDATE internal.ai_consent_rollout_config
SET enforcement_mode = 'strict_2026_08_04',
    changed_at = pg_catalog.NOW()
WHERE config_key = 'current'
  AND enforcement_mode IN (
      'legacy_compatible',
      'strict_2026_08_03'
  );

DO $cutover$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.ai_consent_rollout_config AS config
        WHERE config.config_key = 'current'
          AND config.enforcement_mode = 'strict_2026_08_04'
    ) THEN
        RAISE EXCEPTION 'strict_ai_consent_cutover_failed'
            USING ERRCODE = '55000';
    END IF;
END;
$cutover$;

COMMIT;
