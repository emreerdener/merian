-- Compatibility bridge for the failed production rollout in run 1461.
--
-- A public.users profile cannot be seeded without a matching auth.users
-- identity in installations that enforce the canonical profile FK. Creating a
-- synthetic Auth identity would turn deletion infrastructure into a login
-- principal, so this migration performs an explicit no-op. Keeping executable
-- SQL ensures the failed timestamp is recorded by the migration runner. The
-- immediately following ownerless_account_deletion_tombstones migration
-- removes the invalid sentinel dependency and also converges installations
-- where an earlier copy of this migration happened to apply.
DO $migration$
BEGIN
    NULL;
END;
$migration$;
