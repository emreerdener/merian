-- Close the sole exposed-schema RLS gap and make future Data API exposure
-- explicit rather than dependent on project-level default privileges.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';

ALTER TABLE public.explore_comment_reactions
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES
    ON TABLE public.explore_comment_reactions
    FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, DELETE
    ON TABLE public.explore_comment_reactions
    TO service_role;

-- New public objects are deny-by-default. Every future migration must pair its
-- RLS policy with an explicit Data API grant for the roles that need it.
--
-- Supabase has used both global and schema-local default grants for API roles.
-- A schema-local REVOKE cannot cancel a global GRANT, so clear both layers.
-- ALL PRIVILEGES is intentional: Postgres 17 added MAINTAIN, and an enumerated
-- pre-17 list would silently leave that capability behind.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
    REVOKE ALL PRIVILEGES
    ON TABLES
    FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL PRIVILEGES
    ON TABLES
    FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres
    REVOKE ALL PRIVILEGES
    ON SEQUENCES
    FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL PRIVILEGES
    ON SEQUENCES
    FROM PUBLIC, anon, authenticated, service_role;
