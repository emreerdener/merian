-- species_dictionary.lookalikes_flash_attempted
-- Tracks whether the Flash model has ever been asked to generate lookalike species
-- for this entry. Set to true after resolveLookalikesToJoinTable completes a Flash-
-- sourced call, regardless of how many common names were resolved.
--
-- Purpose: prevents infinite Flash re-calls for species whose lookalikes are
-- genuinely obscure (legitimately null common names). Without this flag the
-- hasLookalikes gate — lookalikes.some(l => l.common_name !== null) — can never
-- become true for such species, causing Flash to run on every enrich-scan call.
--
-- The flag is NOT set by the legacy TEXT[] migration path (which passes
-- common_name: null for all entries) so those species still trigger Flash once.

ALTER TABLE public.species_dictionary
    ADD COLUMN IF NOT EXISTS lookalikes_flash_attempted BOOLEAN NOT NULL DEFAULT false;
