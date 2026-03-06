-- Create the Universal Ghost User if it doesn't already exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000000'
    ) THEN
        -- Insert into Supabase Auth table first (if necessary for foreign keys). 
        -- Generally, auth.users contains the core identity, and public.users echoes it.
        INSERT INTO auth.users (id, email)
        VALUES ('00000000-0000-0000-0000-000000000000', 'tombstone@merian.app');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = '00000000-0000-0000-0000-000000000000'
    ) THEN
        INSERT INTO public.users (
            id, 
            email, 
            created_at, 
            subscription_tier, 
            scans_remaining_today, 
            last_scan_date, 
            current_streak_count, 
            rest_day_tokens, 
            total_species_discovered, 
            default_geoprivacy, 
            marketing_opt_in
        )
        VALUES (
            '00000000-0000-0000-0000-000000000000', 
            'tombstone@merian.app', 
            NOW(), 
            'free', 
            0, 
            CURRENT_DATE, 
            0, 
            0, 
            0, 
            'obscured', 
            false
        );
    END IF;
END $$;

-- Create the Stored Procedure for Tombstoning User Data
CREATE OR REPLACE FUNCTION apply_user_tombstone(target_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Ensures it runs with elevated privileges necessary for deleting records
AS $$
BEGIN
    -- --------------------------------------------------------
    -- STEP 1: Eradicate PII (Personal Identifiable Information)
    -- --------------------------------------------------------
    -- We process ALL scans owned by the target user. We round the 
    -- public coordinates substantially to construct a ~50km obfuscation.
    UPDATE public.scans
    SET 
        gps_lat_public = ROUND(gps_lat_public::numeric, 1),
        gps_long_public = ROUND(gps_long_public::numeric, 1),
        gps_lat_exact = NULL,
        gps_long_exact = NULL,
        image_storage_urls = ARRAY[]::text[]
    WHERE user_id = target_user_id;

    -- --------------------------------------------------------
    -- STEP 2: Reassign Verified AI Scans to the Ghost User
    -- --------------------------------------------------------
    -- Verified data stays in the ecosystem to preserve the 
    -- Machine Learning taxonomy graph. 
    UPDATE public.scans
    SET 
        user_id = '00000000-0000-0000-0000-000000000000',
        is_tombstoned = TRUE,
        geoprivacy = 'obscured' -- Force anonymized mappings
    WHERE user_id = target_user_id AND is_verified = TRUE;

    -- --------------------------------------------------------
    -- STEP 3: Purge remaining non-verified data
    -- --------------------------------------------------------
    -- Unverified scans hold no academic value and are deleted
    DELETE FROM public.scans
    WHERE user_id = target_user_id AND is_verified = FALSE;

END;
$$;
