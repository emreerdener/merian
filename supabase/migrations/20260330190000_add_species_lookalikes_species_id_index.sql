-- Migration: add single-column index on species_lookalikes.species_id
--
-- The UNIQUE constraint on (species_id, lookalike_id) — required for the upsert in
-- resolveLookalikesToJoinTable — creates a composite index. PostgREST's
-- .eq("species_id", speciesId) query in fetchLookalikesFromJoinTable cannot efficiently
-- use the composite index when only the leading column is filtered, depending on the
-- Postgres planner's cost estimates at large table sizes.
--
-- A dedicated single-column index guarantees an O(log N) index scan on the fetch path
-- regardless of table cardinality, without impacting the upsert's conflict detection
-- (which continues to use the unique composite index).

CREATE INDEX IF NOT EXISTS idx_species_lookalikes_species_id
    ON public.species_lookalikes(species_id);
