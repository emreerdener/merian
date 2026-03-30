-- Enable RLS on species_lookalikes to match the species_dictionary access pattern.
--
-- All server-side writes and reads use the service role (supabaseAdmin), which bypasses
-- RLS entirely — this policy has no impact on edge function behaviour.
--
-- The public SELECT policy allows the anon / authenticated roles to read the join table
-- directly if needed (e.g. future client-side lookalike queries), consistent with
-- species_dictionary's "Anyone can read the species dictionary" policy.
--
-- INSERT / UPDATE / DELETE are intentionally left unpolicied: they are blocked for
-- non-service roles by default, ensuring the table is managed exclusively by
-- edge functions and admin tooling.

ALTER TABLE public.species_lookalikes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read species lookalikes"
    ON public.species_lookalikes
    FOR SELECT
    USING (true);
