-- RevenueCat App User IDs are case-sensitive. Swift's UUID representation is
-- uppercase while PostgreSQL's UUID::TEXT output is lowercase; using both
-- causes GET /subscribers to create two provider customers for one Merian user.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION internal.canonical_revenuecat_app_user_id(
    p_user_id UUID
)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
STRICT
PARALLEL SAFE
SET search_path = ''
AS $function$
    SELECT pg_catalog.UPPER(p_user_id::TEXT)
$function$;

COMMENT ON FUNCTION internal.canonical_revenuecat_app_user_id(UUID) IS
    'Returns Merian canonical RevenueCat App User ID: uppercase Supabase UUID.';

REVOKE ALL ON FUNCTION internal.canonical_revenuecat_app_user_id(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

-- Future public.users rows enter the reconciliation queue with the same exact
-- ID used by iOS at RevenueCat configuration time.
CREATE OR REPLACE FUNCTION internal.enqueue_revenuecat_reconciliation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = NEW.id
          AND auth_user.is_anonymous IS NOT TRUE
    ) THEN
        INSERT INTO internal.revenuecat_reconciliation_queue (
            merian_user_id,
            lookup_app_user_id,
            next_reconcile_at
        )
        VALUES (
            NEW.id,
            internal.canonical_revenuecat_app_user_id(NEW.id),
            pg_catalog.NOW() + INTERVAL '15 minutes'
        )
        ON CONFLICT (merian_user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.enqueue_revenuecat_reconciliation()
    FROM PUBLIC, anon, authenticated, service_role;

-- Patch the active ghost-merge helper in place so all previously reviewed
-- merge, collision, and lock-order behavior remains byte-for-byte unchanged.
DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    target_occurrences INTEGER;
    old_lookup CONSTANT TEXT := 'p_target_user_id::TEXT';
    new_lookup CONSTANT TEXT :=
        'internal.canonical_revenuecat_app_user_id(p_target_user_id)';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'internal.merge_ghost_revenuecat_state(uuid,uuid)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'merge_ghost_revenuecat_state is missing during identity repair';
    END IF;

    target_occurrences := (
        pg_catalog.LENGTH(function_sql)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(function_sql, old_lookup, '')
        )
    ) / pg_catalog.LENGTH(old_lookup);

    IF target_occurrences <> 1 THEN
        RAISE EXCEPTION 'revenuecat_ghost_merge_identity_source_drift'
            USING ERRCODE = '55000';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        old_lookup,
        new_lookup
    );

    IF pg_catalog.STRPOS(patched_sql, old_lookup) > 0
       OR pg_catalog.STRPOS(patched_sql, new_lookup) = 0 THEN
        RAISE EXCEPTION 'revenuecat_ghost_merge_identity_patch_failed'
            USING ERRCODE = '55000';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

-- Normalize only queue lookups that are already the same UUID as their
-- Merian row. Preserve RevenueCat emails, aliases, $RCAnonymousID values, and
-- other event-provided IDs exactly as received. Clearing leases claim-fences
-- any worker that fetched the old lowercase customer before this migration.
UPDATE internal.revenuecat_reconciliation_queue AS queue
SET lookup_app_user_id =
        internal.canonical_revenuecat_app_user_id(queue.merian_user_id),
    next_reconcile_at = LEAST(queue.next_reconcile_at, pg_catalog.NOW()),
    attempt_count = 0,
    claim_token = NULL,
    claimed_at = NULL,
    claim_expires_at = NULL,
    last_error_code = NULL,
    updated_at = pg_catalog.NOW()
WHERE queue.lookup_app_user_id IS DISTINCT FROM
        internal.canonical_revenuecat_app_user_id(queue.merian_user_id)
  AND CASE
      WHEN queue.lookup_app_user_id ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN queue.lookup_app_user_id::UUID = queue.merian_user_id
      ELSE FALSE
  END;

RESET statement_timeout;
RESET lock_timeout;
