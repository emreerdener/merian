-- merge_common_name_en(p_id, p_en_name)
-- Safely merges an English common name into species_dictionary.common_names
-- without overwriting existing locale keys.
--
-- Why an RPC instead of a direct PostgREST UPDATE:
--   PostgREST's .update() replaces the entire JSONB column. A species that already
--   has {"fr": "Renard roux"} would lose that entry if we wrote {"en": "Red Fox"}
--   directly. The || JSONB merge operator appends only the new key, preserving all
--   existing locale data.
--
-- Guard condition: only writes when the "en" key is absent. This means:
--   - common_names IS NULL          → writes {"en": p_en_name}
--   - common_names = '{}'           → writes {"en": p_en_name}
--   - common_names = '{"fr": "..."}' → writes {"fr": "...", "en": p_en_name}
--   - common_names = '{"en": "..."}' → no-op (authoritative data preserved)
--
-- SECURITY DEFINER is required so the Edge Function's anon/service role can
-- write to species_dictionary, which has no direct INSERT/UPDATE RLS policy
-- for non-admin roles.

CREATE OR REPLACE FUNCTION public.merge_common_name_en(p_id uuid, p_en_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.species_dictionary
    SET common_names = COALESCE(common_names, '{}'::jsonb) || jsonb_build_object('en', p_en_name)
    WHERE id = p_id
      AND (common_names IS NULL OR NOT (common_names ? 'en'));
END;
$$;
