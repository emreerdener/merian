-- Data recovery: clear incorrectly set lookalikes_flash_attempted flags.
--
-- Prior to the lookalikes_flash_attempted gating fix, the flag was written even when
-- resolveLookalikesToJoinTable returned without writing any rows (e.g., null-kingdom
-- early-exit, replication lag on first scan). This permanently blocked Flash retries
-- for those species, causing similar_species to never appear in the UI.
--
-- This migration resets the flag for every species_dictionary row where the flag is
-- true but no corresponding rows exist in the species_lookalikes join table, allowing
-- the next enrich-scan call to re-attempt the Flash fetch.
UPDATE public.species_dictionary
SET lookalikes_flash_attempted = false
WHERE lookalikes_flash_attempted = true
  AND id NOT IN (
    SELECT DISTINCT species_id FROM public.species_lookalikes
  );
