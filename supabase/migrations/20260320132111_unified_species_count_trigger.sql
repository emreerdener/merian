-- Drop the potential split legacy triggers to prevent conflicts natively
DROP TRIGGER IF EXISTS on_scan_insert_update_species_count ON public.scans;
DROP TRIGGER IF EXISTS decrement_species_count_on_delete ON public.scans;

DROP FUNCTION IF EXISTS public.update_user_species_count();
DROP FUNCTION IF EXISTS public.decrement_user_species_count();

CREATE OR REPLACE FUNCTION public.sync_global_species_count()
RETURNS TRIGGER AS $$
DECLARE
    target_user_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_user_id := OLD.user_id;
    ELSE
        target_user_id := NEW.user_id;
    END IF;

    IF target_user_id IS NOT NULL AND target_user_id != '00000000-0000-0000-0000-000000000000'::uuid THEN
        UPDATE public.users 
        SET total_species_discovered = (
            SELECT COUNT(DISTINCT species_id) 
            FROM public.scans 
            WHERE user_id = target_user_id 
              AND species_id IS NOT NULL
        ) 
        WHERE id = target_user_id;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER unified_species_count_sync
AFTER INSERT OR UPDATE OR DELETE ON public.scans
FOR EACH ROW
EXECUTE FUNCTION public.sync_global_species_count();
