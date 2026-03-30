-- Migration: add merge_common_name_en_batch RPC
--
-- Replaces N individual merge_common_name_en calls (one per lookalike species) with a single
-- round-trip that processes all back-fill candidates atomically. Reduces pgBouncer connection
-- demand from N per enrich-scan cold path to 1, at the cost of a slightly larger payload.
--
-- The WHERE guard (common_names IS NULL OR NOT (common_names ? 'en')) ensures this is a
-- safe no-op for any row that already has an authoritative "en" key — concurrent requests
-- cannot overwrite each other's writes.
--
-- SECURITY DEFINER is required so Edge Functions (which run as the anon role) can UPDATE
-- species_dictionary rows, which are otherwise restricted to service_role.

CREATE OR REPLACE FUNCTION public.merge_common_name_en_batch(
    p_updates jsonb  -- JSON array: [{id: uuid, en_name: text}, ...]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.species_dictionary sd
    SET common_names = COALESCE(common_names, '{}'::jsonb)
                    || jsonb_build_object('en', u->>'en_name')
    FROM jsonb_array_elements(p_updates) AS u
    WHERE sd.id = (u->>'id')::uuid
      AND (sd.common_names IS NULL OR NOT (sd.common_names ? 'en'));
END;
$$;
