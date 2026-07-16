-- Public product rebrand: Naturebook replaces Merian in user-visible database output.
-- Stable function names, source values, signatures, grants, and technical identifiers remain unchanged.

UPDATE public.species_reference_images
SET
    license = 'Used with permission via Naturebook',
    attribution = CASE
        WHEN attribution = 'Merian community' THEN 'Naturebook community'
        ELSE attribution
    END
WHERE source = 'merian'
  AND (
      license = 'Used with permission via Merian'
      OR attribution = 'Merian community'
  );

DO $migration$
DECLARE
    function_definition TEXT;
BEGIN
    SELECT pg_get_functiondef(
        'public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::REGPROCEDURE
    )
    INTO function_definition;

    IF POSITION('Used with permission via Merian' IN function_definition) = 0 THEN
        RAISE EXCEPTION 'refresh_merian_reference_images does not contain the expected legacy license text';
    END IF;

    function_definition := REPLACE(
        function_definition,
        'Used with permission via Merian',
        'Used with permission via Naturebook'
    );
    function_definition := REPLACE(
        function_definition,
        '''Merian community''',
        '''Naturebook community'''
    );

    EXECUTE function_definition;
END;
$migration$;

REVOKE ALL ON FUNCTION public.refresh_merian_reference_images(
    INTEGER,
    INTEGER,
    BOOLEAN,
    DOUBLE PRECISION
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_merian_reference_images(
    INTEGER,
    INTEGER,
    BOOLEAN,
    DOUBLE PRECISION
) TO service_role;

CREATE OR REPLACE FUNCTION public.is_reserved_public_username(candidate_username TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT LOWER(BTRIM(COALESCE(candidate_username, ''))) = ANY (ARRAY[
        'admin',
        'administrator',
        'api',
        'explore',
        'help',
        'merian',
        'naturebook',
        'naturebookearth',
        'moderator',
        'null',
        'official',
        'root',
        'staff',
        'support',
        'system',
        'undefined'
    ]);
$$;

NOTIFY pgrst, 'reload schema';
