-- Make the account boundary for preferred species names explicit and prevent
-- table-level capabilities (notably TRUNCATE) from bypassing row policies.

ALTER TABLE public.user_species_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage their own species preferences"
ON public.user_species_preferences;

DROP POLICY IF EXISTS user_species_preferences_manage_own
ON public.user_species_preferences;

CREATE POLICY user_species_preferences_manage_own
ON public.user_species_preferences
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

REVOKE ALL ON TABLE public.user_species_preferences FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.user_species_preferences FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.user_species_preferences
TO authenticated;

NOTIFY pgrst, 'reload schema';
