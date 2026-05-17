-- species_lookalikes: self-referential join table linking confusable or visually similar species.
-- Replaces the flat similar_species TEXT[] column on species_dictionary as the authoritative
-- source for rich lookalike data (scientific name + common name + reference image + IUCN status).

-- 1. Create the join table
CREATE TABLE IF NOT EXISTS public.species_lookalikes (
    species_id  UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    lookalike_id UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    PRIMARY KEY (species_id, lookalike_id),
    CONSTRAINT no_self_link CHECK (species_id != lookalike_id)
);

-- Index for reverse-direction lookups ("who considers species X a lookalike?")
CREATE INDEX IF NOT EXISTS idx_species_lookalikes_lookalike_id
    ON public.species_lookalikes(lookalike_id);

-- 2. Trigger function: auto-link same-genus species bidirectionally on every new INSERT
--    into species_dictionary. Zero token cost — pure taxonomy.
CREATE OR REPLACE FUNCTION public.trg_link_taxonomy_lookalikes_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    matched_id UUID;
BEGIN
    -- Skip if genus is unknown
    IF NEW.genus IS NULL OR NEW.genus = '' THEN
        RETURN NEW;
    END IF;

    FOR matched_id IN
        SELECT id
        FROM public.species_dictionary
        WHERE genus = NEW.genus
          AND id != NEW.id
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

-- Attach trigger
DROP TRIGGER IF EXISTS trg_link_taxonomy_lookalikes ON public.species_dictionary;
CREATE TRIGGER trg_link_taxonomy_lookalikes
    AFTER INSERT ON public.species_dictionary
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_link_taxonomy_lookalikes_fn();

-- 3. Backfill: link all existing same-genus pairs in the dictionary
INSERT INTO public.species_lookalikes(species_id, lookalike_id)
SELECT a.id, b.id
FROM public.species_dictionary a
JOIN public.species_dictionary b
    ON a.genus = b.genus
   AND a.id != b.id
   AND a.genus IS NOT NULL
   AND a.genus != ''
ON CONFLICT DO NOTHING;
