-- Species lookalike relation metadata.
--
-- Turns species_lookalikes from a bare join table into an explicit relationship
-- model. The relation remains directional: one row means "when viewing species_id,
-- this lookalike_id may be confused with it." Reverse rows must still be written
-- deliberately.

ALTER TABLE public.species_lookalikes
    ADD COLUMN IF NOT EXISTS reason TEXT,
    ADD COLUMN IF NOT EXISTS visual_traits TEXT[] NOT NULL DEFAULT '{}'::text[],
    ADD COLUMN IF NOT EXISTS confidence NUMERIC(5,4),
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'system_backfill',
    ADD COLUMN IF NOT EXISTS review_status TEXT NOT NULL DEFAULT 'unreviewed',
    ADD COLUMN IF NOT EXISTS is_bidirectional BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'species_lookalikes_confidence_check'
          AND conrelid = 'public.species_lookalikes'::regclass
    ) THEN
        ALTER TABLE public.species_lookalikes
            ADD CONSTRAINT species_lookalikes_confidence_check
            CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'species_lookalikes_source_check'
          AND conrelid = 'public.species_lookalikes'::regclass
    ) THEN
        ALTER TABLE public.species_lookalikes
            ADD CONSTRAINT species_lookalikes_source_check
            CHECK (source IN (
                'model_enrichment',
                'taxonomy_trigger',
                'manual_curation',
                'user_review',
                'system_backfill',
                'unknown'
            ));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'species_lookalikes_review_status_check'
          AND conrelid = 'public.species_lookalikes'::regclass
    ) THEN
        ALTER TABLE public.species_lookalikes
            ADD CONSTRAINT species_lookalikes_review_status_check
            CHECK (review_status IN (
                'unreviewed',
                'needs_review',
                'approved',
                'rejected'
            ));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'species_lookalikes_sort_order_check'
          AND conrelid = 'public.species_lookalikes'::regclass
    ) THEN
        ALTER TABLE public.species_lookalikes
            ADD CONSTRAINT species_lookalikes_sort_order_check
            CHECK (sort_order >= 0);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_species_lookalikes_species_review_order
    ON public.species_lookalikes(species_id, review_status, sort_order, lookalike_id);

CREATE INDEX IF NOT EXISTS idx_species_lookalikes_source_review
    ON public.species_lookalikes(source, review_status);

CREATE OR REPLACE FUNCTION public.trg_species_lookalikes_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_species_lookalikes_set_updated_at
    ON public.species_lookalikes;

CREATE TRIGGER trg_species_lookalikes_set_updated_at
BEFORE UPDATE ON public.species_lookalikes
FOR EACH ROW
EXECUTE FUNCTION public.trg_species_lookalikes_set_updated_at();

-- Best-effort metadata for existing deterministic same-genus rows. We keep the
-- confidence deliberately modest because historical relation freshness is unknown.
UPDATE public.species_lookalikes sl
SET
    reason = COALESCE(
        NULLIF(BTRIM(sl.reason), ''),
        'Automatically linked because both species share a genus.'
    ),
    visual_traits = CASE
        WHEN COALESCE(ARRAY_LENGTH(sl.visual_traits, 1), 0) = 0
            THEN ARRAY['shared genus']::text[]
        ELSE sl.visual_traits
    END,
    confidence = COALESCE(sl.confidence, 0.6500),
    source = CASE
        WHEN sl.source IN ('system_backfill', 'unknown') THEN 'taxonomy_trigger'
        ELSE sl.source
    END,
    sort_order = CASE
        WHEN sl.sort_order = 0 THEN 100
        ELSE sl.sort_order
    END
FROM public.species_dictionary subject
JOIN public.species_dictionary lookalike
    ON TRUE
WHERE subject.id = sl.species_id
  AND lookalike.id = sl.lookalike_id
  AND subject.genus IS NOT NULL
  AND lookalike.genus IS NOT NULL
  AND BTRIM(subject.genus) <> ''
  AND BTRIM(lookalike.genus) <> ''
  AND LOWER(BTRIM(subject.genus)) = LOWER(BTRIM(lookalike.genus))
  AND subject.kingdom IS NOT NULL
  AND lookalike.kingdom IS NOT NULL
  AND LOWER(BTRIM(subject.kingdom)) = LOWER(BTRIM(lookalike.kingdom));

-- Refresh the same-genus trigger so future automatic relationships carry
-- explicit metadata. It still writes two directional rows when appropriate;
-- is_bidirectional remains false unless a curator explicitly marks the relation
-- as semantically bidirectional.
CREATE OR REPLACE FUNCTION public.trg_link_taxonomy_lookalikes_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    matched_id UUID;
    relation_reason TEXT;
BEGIN
    IF NEW.genus IS NULL OR BTRIM(NEW.genus) = '' OR LOWER(BTRIM(NEW.genus)) = 'unknown' THEN
        RETURN NEW;
    END IF;

    relation_reason := FORMAT(
        'Automatically linked because both species are in genus %s.',
        BTRIM(NEW.genus)
    );

    FOR matched_id IN
        SELECT id
        FROM public.species_dictionary
        WHERE genus = NEW.genus
          AND id != NEW.id
          AND kingdom IS NOT NULL
          AND NEW.kingdom IS NOT NULL
          AND LOWER(kingdom) = LOWER(NEW.kingdom)
    LOOP
        INSERT INTO public.species_lookalikes(
            species_id,
            lookalike_id,
            reason,
            visual_traits,
            confidence,
            source,
            review_status,
            is_bidirectional,
            sort_order
        )
        VALUES (
            NEW.id,
            matched_id,
            relation_reason,
            ARRAY['shared genus']::text[],
            0.7000,
            'taxonomy_trigger',
            'unreviewed',
            FALSE,
            100
        )
        ON CONFLICT (species_id, lookalike_id) DO UPDATE
        SET
            reason = COALESCE(public.species_lookalikes.reason, EXCLUDED.reason),
            visual_traits = CASE
                WHEN COALESCE(ARRAY_LENGTH(public.species_lookalikes.visual_traits, 1), 0) = 0
                    THEN EXCLUDED.visual_traits
                ELSE public.species_lookalikes.visual_traits
            END,
            confidence = COALESCE(public.species_lookalikes.confidence, EXCLUDED.confidence),
            source = CASE
                WHEN public.species_lookalikes.source IN ('system_backfill', 'unknown')
                    THEN EXCLUDED.source
                ELSE public.species_lookalikes.source
            END;

        INSERT INTO public.species_lookalikes(
            species_id,
            lookalike_id,
            reason,
            visual_traits,
            confidence,
            source,
            review_status,
            is_bidirectional,
            sort_order
        )
        VALUES (
            matched_id,
            NEW.id,
            relation_reason,
            ARRAY['shared genus']::text[],
            0.7000,
            'taxonomy_trigger',
            'unreviewed',
            FALSE,
            100
        )
        ON CONFLICT (species_id, lookalike_id) DO UPDATE
        SET
            reason = COALESCE(public.species_lookalikes.reason, EXCLUDED.reason),
            visual_traits = CASE
                WHEN COALESCE(ARRAY_LENGTH(public.species_lookalikes.visual_traits, 1), 0) = 0
                    THEN EXCLUDED.visual_traits
                ELSE public.species_lookalikes.visual_traits
            END,
            confidence = COALESCE(public.species_lookalikes.confidence, EXCLUDED.confidence),
            source = CASE
                WHEN public.species_lookalikes.source IN ('system_backfill', 'unknown')
                    THEN EXCLUDED.source
                ELSE public.species_lookalikes.source
            END;
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.public_species_similar_species(
    target_species_id UUID
)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'species_id', lookalike.id,
                'scientific_name', lookalike.scientific_name,
                'common_name', public.public_species_common_name(lookalike.common_names),
                'reference_image_url', public.public_species_first_reference_image_url(
                    lookalike.id,
                    lookalike.reference_image_url
                ),
                'iucn_red_list_status', NULLIF(BTRIM(COALESCE(lookalike.iucn_red_list_status, '')), ''),
                'reason', NULLIF(BTRIM(COALESCE(sl.reason, '')), ''),
                'visual_traits', COALESCE(TO_JSONB(sl.visual_traits), '[]'::jsonb),
                'confidence', sl.confidence,
                'source', sl.source,
                'review_status', sl.review_status,
                'is_bidirectional', sl.is_bidirectional,
                'sort_order', sl.sort_order
            )
            ORDER BY sl.sort_order, lookalike.scientific_name
        )
        FROM public.species_lookalikes sl
        JOIN public.species_dictionary lookalike
            ON lookalike.id = sl.lookalike_id
        WHERE sl.species_id = target_species_id
          AND sl.review_status <> 'rejected'
    ), '[]'::jsonb);
$$;
