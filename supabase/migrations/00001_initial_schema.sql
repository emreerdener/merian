-- Enum Types
CREATE TYPE subscription_tier_enum AS ENUM ('free', 'pro');
CREATE TYPE geoprivacy_enum AS ENUM ('open', 'obscured', 'private');
CREATE TYPE ecology_type_enum AS ENUM ('wild', 'urban', 'domesticated', 'unknown');

-- 1. Create Species Dictionary Table
CREATE TABLE public.species_dictionary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scientific_name TEXT UNIQUE NOT NULL,
    common_names JSONB NOT NULL DEFAULT '{}'::jsonb,
    kingdom TEXT NOT NULL,
    phylum TEXT NOT NULL,
    class TEXT NOT NULL,
    "order" TEXT NOT NULL,
    family TEXT NOT NULL,
    genus TEXT NOT NULL,
    descriptions JSONB NOT NULL DEFAULT '{}'::jsonb,
    wikipedia_url TEXT,
    reference_image_url TEXT,
    gbif_taxon_key INTEGER,
    is_poisonous BOOLEAN NOT NULL DEFAULT false,
    native_region TEXT NOT NULL,
    iucn_red_list_status TEXT
);

-- 2. Create Users Table
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    subscription_tier subscription_tier_enum NOT NULL DEFAULT 'free',
    scans_remaining_today INTEGER NOT NULL DEFAULT 10,
    last_scan_date DATE NOT NULL DEFAULT CURRENT_DATE,
    current_streak_count INTEGER NOT NULL DEFAULT 0,
    rest_day_tokens INTEGER NOT NULL DEFAULT 0 CHECK (rest_day_tokens <= 3),
    total_species_discovered INTEGER NOT NULL DEFAULT 0,
    default_geoprivacy geoprivacy_enum NOT NULL DEFAULT 'open',
    marketing_opt_in BOOLEAN NOT NULL DEFAULT false,
    abuse_strikes INTEGER NOT NULL DEFAULT 0,
    is_shadowbanned BOOLEAN NOT NULL DEFAULT false
);

-- 3. Create Scans Table
CREATE TABLE public.scans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    image_storage_urls TEXT[] NOT NULL DEFAULT '{}',
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    gps_lat_exact DOUBLE PRECISION,
    gps_long_exact DOUBLE PRECISION,
    gps_lat_public DOUBLE PRECISION,
    gps_long_public DOUBLE PRECISION,
    geoprivacy geoprivacy_enum NOT NULL DEFAULT 'open',
    coordinate_uncertainty_in_meters INTEGER,
    gps_elevation DOUBLE PRECISION,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    ai_confidence_score DOUBLE PRECISION NOT NULL CHECK (ai_confidence_score >= 0.0 AND ai_confidence_score <= 1.0),
    ecology_type ecology_type_enum NOT NULL DEFAULT 'unknown',
    is_invasive BOOLEAN NOT NULL DEFAULT false,
    regional_status_rationale TEXT,
    is_offline_queued BOOLEAN NOT NULL DEFAULT false,
    is_live_capture BOOLEAN NOT NULL DEFAULT true,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    is_tombstoned BOOLEAN NOT NULL DEFAULT false,
    blur_score DOUBLE PRECISION,
    human_intervention_notes TEXT
);

-- 4. Create User Blocks Table
CREATE TABLE public.user_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(blocker_id, blocked_id)
);

-- 5. Create Pending Storage Deletions Table (from Phase 6 logic)
CREATE TABLE public.pending_storage_deletions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id UUID NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Row Level Security (RLS) Configuration

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.species_dictionary ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pending_storage_deletions ENABLE ROW LEVEL SECURITY;

-- users policies
CREATE POLICY "Users can only read their own row" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can only update their own row" ON public.users FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- scans policies
CREATE POLICY "Users can insert their own scans" ON public.scans FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can fully read their own private scans" ON public.scans FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Anyone can read open and live scans" ON public.scans FOR SELECT USING (geoprivacy = 'open' AND is_live_capture = true);
CREATE POLICY "Users can update their own scans" ON public.scans FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- species_dictionary policies
CREATE POLICY "Anyone can read the species dictionary" ON public.species_dictionary FOR SELECT USING (true);
-- Insert/Update on dictionary intentionally left restricted. Managed by Supabase Admin / Service Hooks exclusively.

-- user_blocks policies
CREATE POLICY "Users can insert their own blocks" ON public.user_blocks FOR INSERT WITH CHECK (auth.uid() = blocker_id);
CREATE POLICY "Users can view their own blocks" ON public.user_blocks FOR SELECT USING (auth.uid() = blocker_id);
CREATE POLICY "Users can remove their own blocks" ON public.user_blocks FOR DELETE USING (auth.uid() = blocker_id);

-- pending_storage_deletions policies
-- Fully managed by service roles
