-- Seasonal Challenge participation reuses the same user_field_trips row as the
-- standard outing. Keep that standard outing eligible for Capture while
-- continuing to ignore challenge-specific completion rows.

CREATE OR REPLACE FUNCTION public.get_field_trip_capture_context(
    self_id UUID
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH viewer AS (
        SELECT COALESCE(u.subscription_tier = 'pro'::public.subscription_tier_enum, FALSE) AS is_pro
        FROM public.users u
        WHERE u.id = self_id
    ),
    accessible_outings AS (
        SELECT
            uft.id AS user_field_trip_id,
            uft.template_id,
            t.slug AS template_slug,
            t.title AS outing_title,
            uft.current_level_number AS level_number,
            fl.id AS level_id,
            fl.title AS level_title,
            GREATEST(
                uft.started_at,
                COALESCE(MAX(completion.completed_at), uft.started_at)
            ) AS last_engaged_at
        FROM public.user_field_trips uft
        JOIN public.field_trip_templates t
          ON t.id = uft.template_id
         AND t.is_active = TRUE
        JOIN public.field_trip_levels fl
          ON fl.template_id = t.id
         AND fl.level_number = uft.current_level_number
        CROSS JOIN viewer
        LEFT JOIN public.user_field_trip_item_completions completion
          ON completion.user_field_trip_id = uft.id
        WHERE uft.user_id = self_id
          AND uft.completed_at IS NULL
          AND uft.hidden_at IS NULL
          AND (t.is_pro_only = FALSE OR viewer.is_pro OR t.is_rotating_free = TRUE)
        GROUP BY
            uft.id,
            uft.template_id,
            t.slug,
            t.title,
            uft.current_level_number,
            fl.id,
            fl.title,
            uft.started_at
    ),
    outing_rows AS (
        SELECT
            outing.*,
            COUNT(item.id)::INTEGER AS target_count,
            COUNT(completion.id)::INTEGER AS completed_count,
            COALESCE(
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'item_id', item.id,
                        'prompt', item.prompt,
                        'sort_order', item.sort_order,
                        'has_guide', (
                            item.guide_tip IS NOT NULL
                            OR item.guide_where_to_look IS NOT NULL
                            OR item.guide_best_conditions IS NOT NULL
                            OR item.guide_what_to_notice IS NOT NULL
                            OR item.guide_scan_safely IS NOT NULL
                        )
                    )
                    ORDER BY item.sort_order, item.id
                ) FILTER (WHERE completion.id IS NULL),
                '[]'::jsonb
            ) AS targets
        FROM accessible_outings outing
        JOIN public.field_trip_checklist_items item
          ON item.level_id = outing.level_id
        LEFT JOIN public.user_field_trip_item_completions completion
          ON completion.user_field_trip_id = outing.user_field_trip_id
         AND completion.item_id = item.id
        GROUP BY
            outing.user_field_trip_id,
            outing.template_id,
            outing.template_slug,
            outing.outing_title,
            outing.last_engaged_at,
            outing.level_number,
            outing.level_id,
            outing.level_title
        HAVING COUNT(item.id) FILTER (WHERE completion.id IS NULL) > 0
    )
    SELECT COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'user_field_trip_id', row.user_field_trip_id,
                'template_id', row.template_id,
                'template_slug', row.template_slug,
                'outing_title', row.outing_title,
                'last_engaged_at', row.last_engaged_at,
                'level_number', row.level_number,
                'level_title', row.level_title,
                'completed_count', row.completed_count,
                'target_count', row.target_count,
                'targets', row.targets
            )
            ORDER BY row.last_engaged_at DESC, row.user_field_trip_id
        ),
        '[]'::jsonb
    )
    FROM outing_rows row;
$$;

COMMENT ON FUNCTION public.get_field_trip_capture_context(UUID) IS
    'Private service-role capture context. Returns accessible active standard outing prompts and aggregate standard progress; challenge-specific progress and scan evidence remain excluded.';

REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM anon;
REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_capture_context(UUID) TO service_role;
