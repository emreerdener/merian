-- Run only after the reservation-safe protocol-3 TestFlight build has been distributed and
-- verified. This owner-only transaction switches functional entitlement and
-- public protocol enforcement together. The table trigger advances the global
-- mode version, so every subsequent entitlement snapshot supersedes legacy
-- responses without rewriting public.users.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '30s';

UPDATE internal.entitlement_rollout_config
SET entitlement_mode = 'complimentary',
    required_client_protocol = 3
WHERE config_key = 'current'
  AND (
      (entitlement_mode = 'legacy_trial' AND required_client_protocol = 0)
      OR
      (entitlement_mode = 'complimentary' AND required_client_protocol = 2)
  );

DO $cutover$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.entitlement_rollout_config AS config
        WHERE config.config_key = 'current'
          AND config.entitlement_mode = 'complimentary'
          AND config.required_client_protocol = 3
    ) THEN
        RAISE EXCEPTION 'complimentary_entitlement_cutover_failed'
            USING ERRCODE = '55000';
    END IF;
END;
$cutover$;

-- Prevent the five-minute overview cache from carrying legacy trial/free plan
-- classifications across the atomic mode transition.
DELETE FROM internal.admin_aggregate_cache
WHERE cache_key LIKE 'overview:%';

COMMIT;
