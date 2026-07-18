-- Let first-party Field trip clients associate each completed checklist item
-- with the owner's persisted scan. The existing RPCs already scope completion
-- rows through the caller's user_field_trips row; no evidence is added to any
-- public outing publication payload.

CREATE OR REPLACE FUNCTION public.get_field_trip_catalog(
    self_id UUID,
    user_region TEXT DEFAULT NULL,
    max_limit INTEGER DEFAULT 40
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_is_pro BOOLEAN := FALSE;
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 40), 80));
    catalog_payload JSONB := '[]'::jsonb;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    WITH templates AS (
        SELECT
            t.*,
            (t.is_pro_only = FALSE OR user_is_pro OR t.is_rotating_free = TRUE) AS viewer_has_access,
            CASE
                WHEN user_region IS NOT NULL AND LOWER(user_region) = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 0
                WHEN COALESCE(ARRAY_LENGTH(t.region_tags, 1), 0) = 0
                  OR 'global' = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 1
                ELSE 2
            END AS region_rank,
            CASE
                WHEN t.is_pro_only AND NOT user_is_pro AND NOT t.is_rotating_free THEN 'pro'
                WHEN t.is_rotating_free THEN 'rotating_free'
                ELSE 'free'
            END AS access_kind
        FROM public.field_trip_templates t
        WHERE t.is_active = TRUE
        ORDER BY
            CASE
                WHEN user_region IS NOT NULL AND LOWER(user_region) = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 0
                WHEN COALESCE(ARRAY_LENGTH(t.region_tags, 1), 0) = 0
                  OR 'global' = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 1
                ELSE 2
            END,
            t.sort_order,
            t.title
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'template_id', t.id,
            'slug', t.slug,
            'title', t.title,
            'subtitle', t.subtitle,
            'description', t.description,
            'cover_image_url', t.cover_image_url,
            'estimated_duration_minutes', t.estimated_duration_minutes,
            'guide_where_to_look', t.guide_where_to_look,
            'guide_why_it_matters', t.guide_why_it_matters,
            'guide_safety_ethics', t.guide_safety_ethics,
            'region_tags', t.region_tags,
            'season_tags', t.season_tags,
            'habitat_tags', t.habitat_tags,
            'difficulty', t.difficulty,
            'is_pro_only', t.is_pro_only,
            'is_rotating_free', t.is_rotating_free,
            'viewer_has_access', t.viewer_has_access,
            'access_kind', t.access_kind,
            'active_progress', CASE WHEN uft.id IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
                'user_field_trip_id', uft.id,
                'started_at', uft.started_at,
                'current_level_number', uft.current_level_number,
                'completed_at', uft.completed_at,
                'is_profile_visible', uft.is_profile_visible,
                'completed_count', COALESCE(active_counts.completed_count, 0),
                'target_count', COALESCE(active_counts.target_count, 0)
            ) END,
            'levels', COALESCE(levels.levels, '[]'::jsonb)
        )
        ORDER BY t.region_rank, t.sort_order, t.title
    ), '[]'::jsonb)
    INTO catalog_payload
    FROM templates t
    LEFT JOIN public.user_field_trips uft
        ON uft.template_id = t.id
       AND uft.user_id = self_id
       AND uft.hidden_at IS NULL
    LEFT JOIN LATERAL (
        SELECT
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM public.field_trip_levels fl
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = fci.id
        WHERE fl.template_id = t.id
          AND fl.level_number = COALESCE(uft.current_level_number, 1)
    ) active_counts ON TRUE
    LEFT JOIN LATERAL (
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'level_id', level_rows.level_id,
                'level_number', level_rows.level_number,
                'title', level_rows.title,
                'description', level_rows.description,
                'items', level_rows.items
            )
            ORDER BY level_rows.level_number
        ) AS levels
        FROM (
            SELECT
                fl.id AS level_id,
                fl.level_number,
                fl.title,
                fl.description,
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'item_id', fci.id,
                        'prompt', fci.prompt,
                        'match_type', fci.match_type,
                        'guide_tip', fci.guide_tip,
                        'guide', CASE
                            WHEN fci.guide_where_to_look IS NULL
                             AND fci.guide_best_conditions IS NULL
                             AND fci.guide_what_to_notice IS NULL
                             AND fci.guide_scan_safely IS NULL THEN NULL
                            ELSE JSONB_BUILD_OBJECT(
                                'where_to_look', fci.guide_where_to_look,
                                'best_conditions', fci.guide_best_conditions,
                                'what_to_notice', fci.guide_what_to_notice,
                                'scan_safely', fci.guide_scan_safely
                            )
                        END,
                        'is_completed', ufc.id IS NOT NULL,
                        'completed_at', ufc.completed_at,
                        'completed_common_name', ufc.common_name,
                        'completed_scientific_name', ufc.scientific_name,
                        'completed_scan_id', ufc.scan_id
                    )
                    ORDER BY fci.sort_order
                ) AS items
            FROM public.field_trip_levels fl
            JOIN public.field_trip_checklist_items fci
                ON fci.level_id = fl.id
            LEFT JOIN public.user_field_trip_item_completions ufc
                ON ufc.user_field_trip_id = uft.id
               AND ufc.item_id = fci.id
            WHERE fl.template_id = t.id
            GROUP BY fl.id, fl.level_number, fl.title, fl.description
        ) level_rows
    ) levels ON TRUE;

    RETURN catalog_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_template_detail(
    self_id UUID,
    target_template_id UUID DEFAULT NULL,
    target_slug TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_is_pro BOOLEAN := FALSE;
    detail_payload JSONB := NULL;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    SELECT JSONB_BUILD_OBJECT(
        'template_id', t.id,
        'slug', t.slug,
        'title', t.title,
        'subtitle', t.subtitle,
        'description', t.description,
        'cover_image_url', t.cover_image_url,
        'estimated_duration_minutes', t.estimated_duration_minutes,
        'guide_where_to_look', t.guide_where_to_look,
        'guide_why_it_matters', t.guide_why_it_matters,
        'guide_safety_ethics', t.guide_safety_ethics,
        'region_tags', t.region_tags,
        'season_tags', t.season_tags,
        'habitat_tags', t.habitat_tags,
        'difficulty', t.difficulty,
        'is_pro_only', t.is_pro_only,
        'is_rotating_free', t.is_rotating_free,
        'viewer_has_access', t.is_pro_only = FALSE OR user_is_pro OR t.is_rotating_free = TRUE,
        'access_kind', CASE
            WHEN t.is_pro_only AND NOT user_is_pro AND NOT t.is_rotating_free THEN 'pro'
            WHEN t.is_rotating_free THEN 'rotating_free'
            ELSE 'free'
        END,
        'active_progress', CASE WHEN uft.id IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
            'user_field_trip_id', uft.id,
            'started_at', uft.started_at,
            'current_level_number', uft.current_level_number,
            'completed_at', uft.completed_at,
            'is_profile_visible', uft.is_profile_visible,
            'completed_count', COALESCE(active_counts.completed_count, 0),
            'target_count', COALESCE(active_counts.target_count, 0)
        ) END,
        'levels', COALESCE(levels.levels, '[]'::jsonb)
    )
    INTO detail_payload
    FROM public.field_trip_templates t
    LEFT JOIN public.user_field_trips uft
        ON uft.template_id = t.id
       AND uft.user_id = self_id
       AND uft.hidden_at IS NULL
    LEFT JOIN LATERAL (
        SELECT
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM public.field_trip_levels fl
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = fci.id
        WHERE fl.template_id = t.id
          AND fl.level_number = COALESCE(uft.current_level_number, 1)
    ) active_counts ON TRUE
    LEFT JOIN LATERAL (
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'level_id', level_rows.level_id,
                'level_number', level_rows.level_number,
                'title', level_rows.title,
                'description', level_rows.description,
                'items', level_rows.items
            )
            ORDER BY level_rows.level_number
        ) AS levels
        FROM (
            SELECT
                fl.id AS level_id,
                fl.level_number,
                fl.title,
                fl.description,
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'item_id', fci.id,
                        'prompt', fci.prompt,
                        'match_type', fci.match_type,
                        'guide_tip', fci.guide_tip,
                        'guide', CASE
                            WHEN fci.guide_where_to_look IS NULL
                             AND fci.guide_best_conditions IS NULL
                             AND fci.guide_what_to_notice IS NULL
                             AND fci.guide_scan_safely IS NULL THEN NULL
                            ELSE JSONB_BUILD_OBJECT(
                                'where_to_look', fci.guide_where_to_look,
                                'best_conditions', fci.guide_best_conditions,
                                'what_to_notice', fci.guide_what_to_notice,
                                'scan_safely', fci.guide_scan_safely
                            )
                        END,
                        'is_completed', ufc.id IS NOT NULL,
                        'completed_at', ufc.completed_at,
                        'completed_common_name', ufc.common_name,
                        'completed_scientific_name', ufc.scientific_name,
                        'completed_scan_id', ufc.scan_id
                    )
                    ORDER BY fci.sort_order
                ) AS items
            FROM public.field_trip_levels fl
            JOIN public.field_trip_checklist_items fci
                ON fci.level_id = fl.id
            LEFT JOIN public.user_field_trip_item_completions ufc
                ON ufc.user_field_trip_id = uft.id
               AND ufc.item_id = fci.id
            WHERE fl.template_id = t.id
            GROUP BY fl.id, fl.level_number, fl.title, fl.description
        ) level_rows
    ) levels ON TRUE
    WHERE t.is_active = TRUE
      AND (
          (target_template_id IS NOT NULL AND t.id = target_template_id)
          OR (target_slug IS NOT NULL AND t.slug = target_slug)
      )
    LIMIT 1;

    RETURN detail_payload;
END;
$$;

COMMENT ON FUNCTION public.get_field_trip_catalog(UUID, TEXT, INTEGER) IS
  'Returns the private Field trip catalog for one viewer, including the scan id that completed each of their checklist items.';

COMMENT ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT) IS
  'Returns one private Field trip template for a viewer, including the scan id that completed each of their checklist items.';

REVOKE ALL ON FUNCTION public.get_field_trip_catalog(UUID, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_catalog(UUID, TEXT, INTEGER)
  TO service_role;

REVOKE ALL ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
