-- Migration: 00003_performance_indexes.sql
-- Description: Implement concurrent indexing to eliminate sequential scans on highly queried keys and telemetry discovery feeds.

-- 1. Accelerate Science Taxonomy Lookups (identify engine enrichment matches)
CREATE INDEX IF NOT EXISTS idx_species_dict_scientific_name ON public.species_dictionary (scientific_name);

-- 2. Accelerate Individual User Profile queries for streaks & usage limits
CREATE INDEX IF NOT EXISTS idx_scans_user_id ON public.scans (user_id);

-- 3. Accelerate Global Discovery Feed paginations bounding constraints natively
CREATE INDEX IF NOT EXISTS idx_scans_discovery_feed ON public.scans (geoprivacy, is_live_capture, timestamp DESC);

-- 4. Accelerate Distinct Species Counters for Leaderboards and Profiles triggering updates natively
CREATE INDEX IF NOT EXISTS idx_scans_user_species ON public.scans (user_id, species_id);
