-- The service-only liked feed and its canonical post-card projection execute
-- with invoker rights. These three sources lack the service reads already
-- granted for the remaining projection dependencies. Preserve client RPC
-- denials, RLS, and the existing visibility predicates; add no write privileges.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

GRANT SELECT ON TABLE
    public.explore_post_likes,
    public.explore_observation_projection,
    public.user_blocks
TO service_role;

RESET statement_timeout;
RESET lock_timeout;
