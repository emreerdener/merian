CREATE OR REPLACE FUNCTION public.decrement_user_species_count()
RETURNS trigger AS $$
BEGIN
  -- We only care about physical scan deletions, NOT ownership transfers to the 
  -- Anonymous Tombstone user (which is handled by a separate trigger).
  IF OLD.species_id IS NOT NULL AND OLD.user_id != '00000000-0000-0000-0000-000000000000'::uuid THEN
    -- Check if this was the absolute last instance of this specific species in their Scans
    IF NOT EXISTS (
      SELECT 1 
      FROM public.scans 
      WHERE user_id = OLD.user_id 
        AND species_id = OLD.species_id
    ) THEN
      -- Decrement their global profile species count, ensuring it never formally drops below 0 integers.
      UPDATE public.users 
      SET total_species_discovered = GREATEST(0, total_species_discovered - 1) 
      WHERE id = OLD.user_id;
    END IF;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach the execution boundary strictly listening precisely for physical `DELETE` constraints out of the Edges
CREATE TRIGGER decrement_species_count_on_delete
  AFTER DELETE ON public.scans
  FOR EACH ROW
  EXECUTE FUNCTION public.decrement_user_species_count();
