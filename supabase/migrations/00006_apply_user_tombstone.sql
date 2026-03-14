-- Migration to safely quarantine and delete a user's data while preserving biological context

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- 1. Ensure the tombstone user account exists to avoid entirely deleting historical biological insights
    INSERT INTO public.users (id, current_streak_count, total_species_discovered, subscription_tier)
    VALUES ('00000000-0000-0000-0000-000000000000', 0, 0, 'free')
    ON CONFLICT (id) DO NOTHING;

    -- 2. Re-assign all of the user's documented encounters to the anonymous tombstone, preserving public discovery feeds
    UPDATE public.scans
    SET 
        user_id = '00000000-0000-0000-0000-000000000000',
        is_tombstoned = true
    WHERE user_id = target_user_id;

    -- 3. Obliterate the user's account and telemetry
    DELETE FROM public.users
    WHERE id = target_user_id;
END;
$$;
