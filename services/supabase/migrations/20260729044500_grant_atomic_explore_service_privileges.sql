-- The final Explore and Ask the Community transactions are deliberately
-- SECURITY INVOKER. Supabase's hardened public-schema defaults therefore
-- require explicit table privileges for their only allowed caller.
--
-- Keep this allowlist operation-scoped. No browser-facing API role receives a
-- write privilege, and service_role receives no TRUNCATE, REFERENCES, TRIGGER,
-- or MAINTAIN capability from this migration.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

GRANT SELECT, UPDATE
    ON TABLE public.scans
    TO service_role;

-- Explore's existing location-projection trigger is also invoker-rights and
-- reads the species safety metadata while the post row is written.
GRANT SELECT
    ON TABLE
        public.taxon_nodes,
        public.species_dictionary
    TO service_role;

GRANT SELECT, INSERT, UPDATE
    ON TABLE
        public.explore_posts,
        public.explore_community_requests
    TO service_role;

GRANT SELECT, INSERT, DELETE
    ON TABLE
        public.explore_post_media,
        public.explore_post_hashtags
    TO service_role;

GRANT SELECT, UPDATE
    ON TABLE public.explore_identifications
    TO service_role;

GRANT SELECT, DELETE
    ON TABLE public.community_consensus_jobs
    TO service_role;

RESET statement_timeout;
RESET lock_timeout;
