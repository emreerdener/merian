-- `auth.role()` reflects JWT claims. Current `sb_secret_...` API keys are
-- intentionally opaque rather than JWTs, so PostgREST can impersonate the
-- `service_role` database role without populating that claim. Preserve the
-- JWT check for legacy keys and also inspect PostgREST's protected standard
-- `role` setting so both supported server-key formats reach privileged RPCs.
-- A direct owner session is accepted only while no role is impersonated;
-- otherwise the effective protected role must itself be privileged.
BEGIN;

CREATE OR REPLACE FUNCTION internal.require_service_role()
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role'
       AND pg_catalog.CURRENT_SETTING('role', TRUE)
            NOT IN ('service_role', 'postgres')
       AND NOT (
           pg_catalog.CURRENT_SETTING('role', TRUE) = 'none'
           AND SESSION_USER IN ('postgres', 'service_role')
       ) THEN
        RAISE EXCEPTION 'service_role authorization required'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

COMMENT ON FUNCTION internal.require_service_role() IS
    'Defense-in-depth caller check used by service-role public SECURITY DEFINER routines. Accepts legacy JWT role claims, protected privileged-role impersonation for opaque secret keys or CLI connections, and direct owner sessions that are not impersonating a lower-privilege role.';

REVOKE ALL ON FUNCTION internal.require_service_role()
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
