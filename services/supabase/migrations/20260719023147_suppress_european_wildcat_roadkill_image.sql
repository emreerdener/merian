-- Migration: suppress European wildcat roadkill reference image
--
-- GBIF occurrence 5938154750 exposes iNaturalist photo 605615444. This is an
-- exact-media exception: every filename below that photo directory is denied,
-- while all other Felis silvestris and GBIF/iNaturalist imagery remains valid.

-- Remove normalized copies first. The species projection helpers below still
-- enforce the policy during rolling deployment and for any historical replica.
DELETE FROM public.species_reference_images
WHERE LOWER(BTRIM(url)) ~
    '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/';

-- Legacy rows store a source-ordered, comma-separated fallback list. Preserve
-- that ordering so the next permitted URL is promoted automatically.
UPDATE public.species_dictionary AS species
SET reference_image_url = (
    SELECT STRING_AGG(
        NULLIF(BTRIM(split.raw_url), ''),
        ','
        ORDER BY split.ordinality
    )
    FROM regexp_split_to_table(
        COALESCE(species.reference_image_url, ''),
        '\s*,\s*'
    ) WITH ORDINALITY AS split(raw_url, ordinality)
    WHERE NULLIF(BTRIM(split.raw_url), '') IS NOT NULL
      AND LOWER(BTRIM(split.raw_url)) !~
          '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/'
)
WHERE EXISTS (
    SELECT 1
    FROM regexp_split_to_table(
        COALESCE(species.reference_image_url, ''),
        '\s*,\s*'
    ) AS split(raw_url)
    WHERE LOWER(BTRIM(split.raw_url)) ~
        '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/'
);

CREATE OR REPLACE FUNCTION public.public_species_reference_image_urls(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT STRING_AGG(
                ref.url,
                ','
                ORDER BY
                    public.public_species_reference_image_source_rank(ref.source),
                    ref.sort_order,
                    ref.created_at,
                    ref.id
            )
            FROM public.species_reference_images AS ref
            WHERE ref.species_id = target_species_id
              AND LOWER(BTRIM(ref.url)) !~
                  '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/'
        ),
        (
            SELECT STRING_AGG(
                NULLIF(BTRIM(split.raw_url), ''),
                ','
                ORDER BY split.ordinality
            )
            FROM regexp_split_to_table(
                COALESCE(legacy_reference_image_url, ''),
                '\s*,\s*'
            ) WITH ORDINALITY AS split(raw_url, ordinality)
            WHERE NULLIF(BTRIM(split.raw_url), '') IS NOT NULL
              AND LOWER(BTRIM(split.raw_url)) !~
                  '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/'
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.public_species_first_reference_image_url(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT ref.url
            FROM public.species_reference_images AS ref
            WHERE ref.species_id = target_species_id
              AND LOWER(BTRIM(ref.url)) !~
                  '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/'
            ORDER BY
                public.public_species_reference_image_source_rank(ref.source),
                ref.sort_order,
                ref.created_at,
                ref.id
            LIMIT 1
        ),
        (
            SELECT NULLIF(BTRIM(split.raw_url), '')
            FROM regexp_split_to_table(
                COALESCE(legacy_reference_image_url, ''),
                '\s*,\s*'
            ) WITH ORDINALITY AS split(raw_url, ordinality)
            WHERE NULLIF(BTRIM(split.raw_url), '') IS NOT NULL
              AND LOWER(BTRIM(split.raw_url)) !~
                  '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/'
            ORDER BY split.ordinality
            LIMIT 1
        )
    );
$$;

-- A row trigger silently ignores only the blocked media. This lets bulk refresh
-- writes continue inserting later safe images rather than failing the batch.
CREATE OR REPLACE FUNCTION public.suppress_blocked_species_reference_image()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF LOWER(BTRIM(NEW.url)) ~
        '^https?://inaturalist-open-data[.]s3[.]amazonaws[.]com/photos/605615444/' THEN
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.suppress_blocked_species_reference_image() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.suppress_blocked_species_reference_image() FROM anon;
REVOKE ALL ON FUNCTION public.suppress_blocked_species_reference_image() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.suppress_blocked_species_reference_image() TO service_role;

DROP TRIGGER IF EXISTS suppress_blocked_species_reference_image
    ON public.species_reference_images;

CREATE TRIGGER suppress_blocked_species_reference_image
BEFORE INSERT OR UPDATE OF url ON public.species_reference_images
FOR EACH ROW
EXECUTE FUNCTION public.suppress_blocked_species_reference_image();
