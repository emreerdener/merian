-- Make species_dictionary taxonomy nullable so "unknown" can be represented as NULL.
-- The previous TEXT NOT NULL + "Unknown" sentinel polluted both Flash validation and the
-- same-genus lookalike trigger, allowing unrelated species to link through placeholder data.

ALTER TABLE public.species_dictionary
  ALTER COLUMN kingdom DROP NOT NULL,
  ALTER COLUMN phylum DROP NOT NULL,
  ALTER COLUMN class DROP NOT NULL,
  ALTER COLUMN "order" DROP NOT NULL,
  ALTER COLUMN family DROP NOT NULL,
  ALTER COLUMN genus DROP NOT NULL;

-- Normalize legacy placeholder strings to real NULLs.
UPDATE public.species_dictionary
SET
  kingdom = CASE
    WHEN kingdom IS NULL OR btrim(kingdom) = '' OR lower(btrim(kingdom)) = 'unknown' THEN NULL
    ELSE btrim(kingdom)
  END,
  phylum = CASE
    WHEN phylum IS NULL OR btrim(phylum) = '' OR lower(btrim(phylum)) = 'unknown' THEN NULL
    ELSE btrim(phylum)
  END,
  class = CASE
    WHEN class IS NULL OR btrim(class) = '' OR lower(btrim(class)) = 'unknown' THEN NULL
    ELSE btrim(class)
  END,
  "order" = CASE
    WHEN "order" IS NULL OR btrim("order") = '' OR lower(btrim("order")) = 'unknown' THEN NULL
    ELSE btrim("order")
  END,
  family = CASE
    WHEN family IS NULL OR btrim(family) = '' OR lower(btrim(family)) = 'unknown' THEN NULL
    ELSE btrim(family)
  END,
  genus = CASE
    WHEN genus IS NULL OR btrim(genus) = '' OR lower(btrim(genus)) = 'unknown' THEN NULL
    ELSE btrim(genus)
  END;

-- Harden the same-genus trigger so placeholder genus values can never auto-link species again.
CREATE OR REPLACE FUNCTION public.trg_link_taxonomy_lookalikes_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    matched_id UUID;
BEGIN
    IF NEW.genus IS NULL OR btrim(NEW.genus) = '' OR lower(btrim(NEW.genus)) = 'unknown' THEN
        RETURN NEW;
    END IF;

    FOR matched_id IN
        SELECT id
        FROM public.species_dictionary
        WHERE genus = NEW.genus
          AND id != NEW.id
          AND kingdom IS NOT NULL
          AND NEW.kingdom IS NOT NULL
          AND lower(kingdom) = lower(NEW.kingdom)
    LOOP
        INSERT INTO public.species_lookalikes(species_id, lookalike_id)
        VALUES (NEW.id, matched_id)
        ON CONFLICT DO NOTHING;

        INSERT INTO public.species_lookalikes(species_id, lookalike_id)
        VALUES (matched_id, NEW.id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    RETURN NEW;
END;
$$;

-- Reset all cached lookalike relationships and rebuild only the deterministic same-genus layer.
DELETE FROM public.species_lookalikes;

INSERT INTO public.species_lookalikes(species_id, lookalike_id)
SELECT a.id, b.id
FROM public.species_dictionary a
JOIN public.species_dictionary b
  ON a.genus = b.genus
 AND a.id != b.id
WHERE a.genus IS NOT NULL
  AND b.genus IS NOT NULL
  AND btrim(a.genus) <> ''
  AND btrim(b.genus) <> ''
  AND lower(btrim(a.genus)) <> 'unknown'
  AND lower(btrim(b.genus)) <> 'unknown'
  AND a.kingdom IS NOT NULL
  AND b.kingdom IS NOT NULL
  AND lower(a.kingdom) = lower(b.kingdom)
ON CONFLICT DO NOTHING;

-- Clear the legacy flat cache and retry flags so future lookalikes regenerate under the
-- new validation rules instead of reusing names created with placeholder taxonomy.
UPDATE public.species_dictionary
SET similar_species = NULL,
    lookalikes_flash_attempted = FALSE;
