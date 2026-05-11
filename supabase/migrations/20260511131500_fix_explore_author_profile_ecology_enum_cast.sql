-- Fix Explore author profile achievement projection for nullable enum values.
--
-- The original RPC selected scans.ecology_type as an enum and later used
-- COALESCE(ecology_type, ''). Postgres tries to cast the empty string back into
-- ecology_type_enum in that expression, which raises:
-- invalid input value for enum ecology_type_enum: "".
--
-- Recreate the existing function with ecology_type projected as TEXT so the
-- award comparisons can safely trim and compare it as a string.

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
        '            s.ecology_type,' || CHR(10),
        '            s.ecology_type::TEXT AS ecology_type,' || CHR(10)
    );

    EXECUTE function_sql;
END;
$$;

NOTIFY pgrst, 'reload schema';
