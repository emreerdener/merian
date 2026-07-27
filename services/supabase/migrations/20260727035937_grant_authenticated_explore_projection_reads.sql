-- Supabase's Data API now requires explicit table privileges independently
-- from RLS. The canonical Explore projection is SECURITY INVOKER, so grant the
-- authenticated role only the source-table reads needed to evaluate it. Each
-- table's existing RLS policies continue to decide which rows are visible.
BEGIN;

GRANT SELECT ON TABLE
    public.explore_posts,
    public.scans,
    public.users,
    public.species_dictionary,
    public.explore_observation_projection,
    public.taxon_nodes,
    public.explore_post_likes,
    public.explore_community_requests,
    public.explore_post_media,
    public.user_blocks
TO authenticated;

COMMIT;
