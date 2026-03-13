-- 1. Create a trigger function to increment total_species_discovered
CREATE OR REPLACE FUNCTION public.update_user_species_count()
RETURNS TRIGGER AS $$
BEGIN
    -- Only increment if this is the first time the user has ever safely uploaded this species_id
    IF NOT EXISTS (
        SELECT 1 FROM public.scans
        WHERE user_id = NEW.user_id
          AND species_id = NEW.species_id
          AND id != NEW.id
    ) THEN
        UPDATE public.users
        SET total_species_discovered = total_species_discovered + 1
        WHERE id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Attach the trigger to the scans table securely
DROP TRIGGER IF EXISTS on_scan_insert_update_species_count ON public.scans;
CREATE TRIGGER on_scan_insert_update_species_count
AFTER INSERT ON public.scans
FOR EACH ROW
WHEN (NEW.species_id IS NOT NULL)
EXECUTE FUNCTION public.update_user_species_count();

-- 3. Retroactively recalculate all historical totals for existing users who are stuck at 0
UPDATE public.users u
SET total_species_discovered = (
    SELECT COUNT(DISTINCT s.species_id)
    FROM public.scans s
    WHERE s.user_id = u.id
      AND s.species_id IS NOT NULL
);
