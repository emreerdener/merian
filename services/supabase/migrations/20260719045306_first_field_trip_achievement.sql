-- First Field trip achievement progress is resolved from completed standard
-- outings and Seasonal Challenges. The function is intentionally callable only
-- by service_role so trip evidence never becomes part of the public RPC surface.

CREATE INDEX IF NOT EXISTS idx_user_field_trips_user_completed_at
    ON public.user_field_trips(user_id, completed_at)
    WHERE completed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_participants_user_completed_at
    ON public.field_trip_challenge_participants(user_id, completed_at)
    WHERE completed_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_first_field_trip_achievement_progress(
    target_user_id UUID
)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH completion_candidates AS (
        SELECT
            'standard_outing'::TEXT AS kind,
            uft.completed_at,
            ft.slug AS template_slug,
            NULL::UUID AS challenge_id,
            1 AS destination_priority,
            uft.id AS source_id
        FROM public.user_field_trips uft
        JOIN public.field_trip_templates ft
            ON ft.id = uft.template_id
        WHERE uft.user_id = target_user_id
          AND uft.completed_at IS NOT NULL

        UNION ALL

        SELECT
            'seasonal_challenge'::TEXT AS kind,
            ftcp.completed_at,
            NULL::TEXT AS template_slug,
            ftcp.challenge_id,
            0 AS destination_priority,
            ftcp.id AS source_id
        FROM public.field_trip_challenge_participants ftcp
        WHERE ftcp.user_id = target_user_id
          AND ftcp.completed_at IS NOT NULL
    )
    SELECT JSONB_BUILD_OBJECT(
        'kind', candidate.kind,
        'completed_at', candidate.completed_at,
        'template_slug', candidate.template_slug,
        'challenge_id', candidate.challenge_id
    )
    FROM completion_candidates candidate
    ORDER BY
        candidate.completed_at ASC,
        candidate.destination_priority ASC,
        candidate.source_id ASC
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_first_field_trip_achievement_progress(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_first_field_trip_achievement_progress(UUID)
    TO service_role;

-- Explore author profiles expose only the achievement count and completion date.
-- Destination evidence stays private to the service-role-only function above.
DO $migration$
DECLARE
    function_sql TEXT;
    needle TEXT;
    replacement TEXT;
BEGIN
    SELECT PG_GET_FUNCTIONDEF(
        'public.get_explore_author_profile(uuid, uuid, integer)'::REGPROCEDURE
    )
    INTO function_sql;

    needle :=
        '        JSONB_BUILD_OBJECT(' || CHR(10) ||
        '            ''type'', ''frost_walker'',';

    replacement :=
        '        JSONB_BUILD_OBJECT(' || CHR(10) ||
        '            ''type'', ''first_field_trip'',' || CHR(10) ||
        '            ''current_count'', CASE WHEN EXISTS (' || CHR(10) ||
        '                SELECT 1 FROM public.user_field_trips uft' || CHR(10) ||
        '                WHERE uft.user_id = target_author_user_id AND uft.completed_at IS NOT NULL' || CHR(10) ||
        '                UNION ALL' || CHR(10) ||
        '                SELECT 1 FROM public.field_trip_challenge_participants ftcp' || CHR(10) ||
        '                WHERE ftcp.user_id = target_author_user_id AND ftcp.completed_at IS NOT NULL' || CHR(10) ||
        '            ) THEN 1 ELSE 0 END,' || CHR(10) ||
        '            ''last_interaction_at'', (' || CHR(10) ||
        '                SELECT MIN(completed_at)' || CHR(10) ||
        '                FROM (' || CHR(10) ||
        '                    SELECT uft.completed_at' || CHR(10) ||
        '                    FROM public.user_field_trips uft' || CHR(10) ||
        '                    WHERE uft.user_id = target_author_user_id AND uft.completed_at IS NOT NULL' || CHR(10) ||
        '                    UNION ALL' || CHR(10) ||
        '                    SELECT ftcp.completed_at' || CHR(10) ||
        '                    FROM public.field_trip_challenge_participants ftcp' || CHR(10) ||
        '                    WHERE ftcp.user_id = target_author_user_id AND ftcp.completed_at IS NOT NULL' || CHR(10) ||
        '                ) first_field_trip_completions' || CHR(10) ||
        '            )' || CHR(10) ||
        '        ),' || CHR(10) ||
        needle;

    function_sql := REPLACE(function_sql, needle, replacement);

    IF function_sql NOT LIKE '%''type'', ''first_field_trip''%' THEN
        RAISE EXCEPTION 'Failed to patch get_explore_author_profile with first Field trip achievement';
    END IF;

    EXECUTE function_sql;
END;
$migration$;

NOTIFY pgrst, 'reload schema';
