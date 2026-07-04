-- Include domestic cat and dog achievements in public Explore author profiles.
--
-- The iOS achievement catalog gained domestic_cat and domestic_dog, but the
-- public author-profile RPC builds its awards JSON explicitly. Patch the current
-- deployed function in place so later return-shape changes are preserved.

DO $$
DECLARE
    function_sql TEXT;
BEGIN
    SELECT PG_GET_FUNCTIONDEF(
        'public.get_explore_author_profile(uuid, uuid, integer)'::REGPROCEDURE
    )
    INTO function_sql;

    function_sql := REPLACE(
        function_sql,
        '            s.ai_confidence_score' || CHR(10) ||
        '        FROM public.scans s',
        '            s.ai_confidence_score,' || CHR(10) ||
        '            sd.scientific_name' || CHR(10) ||
        '        FROM public.scans s'
    );

    function_sql := REPLACE(
        function_sql,
        '        JSONB_BUILD_OBJECT(' || CHR(10) ||
        '            ''type'', ''urban'',' || CHR(10) ||
        '            ''current_count'', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(ecology_type, ''''))) IN (''urban'', ''domesticated'')), 10),' || CHR(10) ||
        '            ''last_interaction_at'', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(ecology_type, ''''))) IN (''urban'', ''domesticated''))' || CHR(10) ||
        '        ),',
        '        JSONB_BUILD_OBJECT(' || CHR(10) ||
        '            ''type'', ''urban'',' || CHR(10) ||
        '            ''current_count'', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(ecology_type, ''''))) IN (''urban'', ''domesticated'')), 10),' || CHR(10) ||
        '            ''last_interaction_at'', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(ecology_type, ''''))) IN (''urban'', ''domesticated''))' || CHR(10) ||
        '        ),' || CHR(10) ||
        '        JSONB_BUILD_OBJECT(' || CHR(10) ||
        '            ''type'', ''domestic_cat'',' || CHR(10) ||
        '            ''current_count'', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(scientific_name, ''''))) IN (''felis catus'', ''felis silvestris catus'', ''felis domesticus'', ''felis catus domesticus'', ''felis silvestris domesticus'')), 1),' || CHR(10) ||
        '            ''last_interaction_at'', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(scientific_name, ''''))) IN (''felis catus'', ''felis silvestris catus'', ''felis domesticus'', ''felis catus domesticus'', ''felis silvestris domesticus''))' || CHR(10) ||
        '        ),' || CHR(10) ||
        '        JSONB_BUILD_OBJECT(' || CHR(10) ||
        '            ''type'', ''domestic_dog'',' || CHR(10) ||
        '            ''current_count'', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(scientific_name, ''''))) IN (''canis lupus familiaris'', ''canis familiaris'', ''canis familiaris domesticus'')), 1),' || CHR(10) ||
        '            ''last_interaction_at'', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(scientific_name, ''''))) IN (''canis lupus familiaris'', ''canis familiaris'', ''canis familiaris domesticus''))' || CHR(10) ||
        '        ),'
    );

    IF function_sql NOT LIKE '%''type'', ''domestic_cat''%' OR
       function_sql NOT LIKE '%''type'', ''domestic_dog''%' THEN
        RAISE EXCEPTION 'Failed to patch get_explore_author_profile with pet achievements';
    END IF;

    EXECUTE function_sql;
END;
$$;

NOTIFY pgrst, 'reload schema';
