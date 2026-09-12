-- The liked-feed reference thumbnail helper is also SECURITY INVOKER. An
-- empty feed never evaluates that helper, so the earlier source-read repair
-- did not cover its normalized reference-image table. Preserve existing ACLs
-- and add only the read required when a liked card is actually returned.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

GRANT SELECT ON TABLE public.species_reference_images TO service_role;

RESET statement_timeout;
RESET lock_timeout;
