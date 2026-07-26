BEGIN;

-- This table was formerly used as a capability probe by Edge Functions.
-- An RLS-filtered SELECT is still a successful SELECT, so table reachability
-- cannot prove that the caller has service-role authority. Keep the operational
-- table inaccessible to low-privilege API roles even though authorization now
-- relies only on exact comparison with platform-managed server keys.
REVOKE ALL PRIVILEGES ON TABLE public.taxonomy_import_runs
    FROM PUBLIC, anon, authenticated, service_role;

-- Community-taxonomy workers read and annotate import runs directly. Grant
-- only the operations used by those workers; migrations and definer routines
-- continue to execute as their owners.
GRANT SELECT, INSERT, UPDATE ON TABLE public.taxonomy_import_runs
    TO service_role;

COMMENT ON TABLE public.taxonomy_import_runs IS
    'Private operational history for taxonomy imports. Low-privilege API roles have no table access; service-role workers receive only SELECT, INSERT, and UPDATE.';

NOTIFY pgrst, 'reload schema';

COMMIT;
