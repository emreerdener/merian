\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(5);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attribute
        WHERE attribute.attrelid = 'public.species_dictionary'::REGCLASS
          AND attribute.attname = 'is_public_biological'
          AND attribute.attgenerated = 's'
          AND NOT attribute.attisdropped
    ),
    'public biological eligibility is a stored generated database invariant'
);

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus,
    gbif_taxon_key
)
VALUES
    (
        '00000000-0000-4000-8000-00000000eb01',
        'Eligibilis taxonkey',
        '{}'::JSONB,
        'Unknown',
        'Unknown',
        'Unknown',
        'Unknown',
        'Unknown',
        'Unknown',
        920001
    ),
    (
        '00000000-0000-4000-8000-00000000eb02',
        'Eligibilis taxonomy',
        '{}'::JSONB,
        'Animalia',
        'Chordata',
        'Unknown',
        'Unknown',
        'Unknown',
        'Unknown',
        NULL
    ),
    (
        '00000000-0000-4000-8000-00000000eb03',
        'Ineligibilis placeholder',
        '{}'::JSONB,
        'Animalia',
        'Unavailable',
        'Not Available',
        'N/A',
        'None',
        'Undefined',
        0
    ),
    (
        '00000000-0000-4000-8000-00000000eb04',
        '   ',
        '{}'::JSONB,
        'Animalia',
        'Chordata',
        'Aves',
        'Passeriformes',
        'Testidae',
        'Testus',
        920004
    );

SELECT extensions.is(
    (
        SELECT species.is_public_biological
        FROM public.species_dictionary AS species
        WHERE species.id = '00000000-0000-4000-8000-00000000eb01'
    ),
    TRUE,
    'a positive GBIF taxon key is publicly biological'
);

SELECT extensions.is(
    (
        SELECT species.is_public_biological
        FROM public.species_dictionary AS species
        WHERE species.id = '00000000-0000-4000-8000-00000000eb02'
    ),
    TRUE,
    'a meaningful kingdom plus lower taxonomy is publicly biological'
);

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary AS species
        WHERE species.id IN (
            '00000000-0000-4000-8000-00000000eb03',
            '00000000-0000-4000-8000-00000000eb04'
        )
          AND species.is_public_biological
    ),
    'placeholder taxonomy and blank scientific names remain ineligible'
);

UPDATE public.species_dictionary
SET phylum = 'Chordata'
WHERE id = '00000000-0000-4000-8000-00000000eb03';

SELECT extensions.is(
    (
        SELECT species.is_public_biological
        FROM public.species_dictionary AS species
        WHERE species.id = '00000000-0000-4000-8000-00000000eb03'
    ),
    TRUE,
    'eligibility recomputes automatically when taxonomy becomes meaningful'
);

SELECT * FROM extensions.finish();
ROLLBACK;
