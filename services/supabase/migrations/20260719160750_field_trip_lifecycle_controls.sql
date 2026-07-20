-- Preserve standard Field trip progress while allowing an outing to be stopped,
-- resumed, and reset without confusing scans captured during stopped gaps with
-- scans captured during an active outing window.

CREATE TABLE IF NOT EXISTS public.user_field_trip_active_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_field_trip_id UUID NOT NULL REFERENCES public.user_field_trips(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL,
    stopped_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (stopped_at IS NULL OR stopped_at >= started_at)
);

COMMENT ON TABLE public.user_field_trip_active_periods IS
    'Private standard-outing activity windows used to exclude scans captured while an outing was stopped.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_field_trip_active_periods_open
    ON public.user_field_trip_active_periods(user_field_trip_id)
    WHERE stopped_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_field_trip_active_periods_lookup
    ON public.user_field_trip_active_periods(user_field_trip_id, started_at, stopped_at);

ALTER TABLE public.user_field_trip_active_periods ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.user_field_trip_active_periods
    FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.user_field_trip_active_periods TO service_role;

INSERT INTO public.user_field_trip_active_periods(
    user_field_trip_id,
    started_at,
    stopped_at
)
SELECT
    uft.id,
    uft.started_at,
    CASE
        WHEN uft.hidden_at IS NOT NULL AND uft.completed_at IS NOT NULL
            THEN LEAST(uft.hidden_at, uft.completed_at)
        ELSE COALESCE(uft.hidden_at, uft.completed_at)
    END
FROM public.user_field_trips uft
WHERE NOT EXISTS (
    SELECT 1
    FROM public.user_field_trip_active_periods period
    WHERE period.user_field_trip_id = uft.id
);

CREATE OR REPLACE FUNCTION public.start_field_trip(
    self_id UUID,
    target_template_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    template_row RECORD;
    trip_row RECORD;
    user_is_pro BOOLEAN := FALSE;
    mutation_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    SELECT *
    INTO template_row
    FROM public.field_trip_templates t
    WHERE t.id = target_template_id
      AND t.is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip template not found' USING ERRCODE = 'P0002';
    END IF;

    IF template_row.is_pro_only AND NOT user_is_pro AND NOT template_row.is_rotating_free THEN
        RAISE EXCEPTION 'Field Trip requires Pro access' USING ERRCODE = 'P0001';
    END IF;

    SELECT uft.*
    INTO trip_row
    FROM public.user_field_trips uft
    WHERE uft.user_id = self_id
      AND uft.template_id = target_template_id
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.user_field_trips(
            user_id,
            template_id,
            started_at,
            current_level_number,
            is_profile_visible,
            hidden_at
        )
        VALUES (self_id, target_template_id, mutation_time, 1, TRUE, NULL)
        RETURNING * INTO trip_row;
    ELSIF trip_row.completed_at IS NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.user_field_trip_active_periods period
            WHERE period.user_field_trip_id = trip_row.id
        ) THEN
            UPDATE public.user_field_trips
            SET started_at = mutation_time,
                current_level_number = 1,
                completed_at = NULL,
                is_profile_visible = TRUE,
                hidden_at = NULL,
                updated_at = mutation_time
            WHERE id = trip_row.id
            RETURNING * INTO trip_row;
        ELSE
            UPDATE public.user_field_trips
            SET is_profile_visible = TRUE,
                hidden_at = NULL,
                updated_at = mutation_time
            WHERE id = trip_row.id
            RETURNING * INTO trip_row;
        END IF;
    END IF;

    IF trip_row.completed_at IS NULL THEN
        INSERT INTO public.user_field_trip_active_periods(
            user_field_trip_id,
            started_at,
            stopped_at
        )
        SELECT trip_row.id, mutation_time, NULL
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.user_field_trip_active_periods period
            WHERE period.user_field_trip_id = trip_row.id
              AND period.stopped_at IS NULL
        )
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN public.get_field_trip_template_detail(self_id, target_template_id, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.stop_field_trip(
    self_id UUID,
    target_user_field_trip_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    trip_row RECORD;
    mutation_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT uft.id, uft.template_id, uft.completed_at
    INTO trip_row
    FROM public.user_field_trips uft
    WHERE uft.id = target_user_field_trip_id
      AND uft.user_id = self_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip not found' USING ERRCODE = 'P0002';
    END IF;

    IF trip_row.completed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Completed Field Trips cannot be stopped' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.user_field_trip_active_periods period
    SET stopped_at = mutation_time
    WHERE period.user_field_trip_id = trip_row.id
      AND period.stopped_at IS NULL;

    IF FOUND THEN
        UPDATE public.user_field_trips
        SET hidden_at = mutation_time,
            updated_at = mutation_time
        WHERE id = trip_row.id;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM public.user_field_trip_active_periods period
        WHERE period.user_field_trip_id = trip_row.id
    ) THEN
        RAISE EXCEPTION 'Field Trip has not started' USING ERRCODE = 'P0001';
    END IF;

    RETURN trip_row.template_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_field_trip(
    self_id UUID,
    target_user_field_trip_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    trip_row RECORD;
    mutation_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT uft.id, uft.template_id, uft.completed_at, uft.hidden_at
    INTO trip_row
    FROM public.user_field_trips uft
    WHERE uft.id = target_user_field_trip_id
      AND uft.user_id = self_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip not found' USING ERRCODE = 'P0002';
    END IF;

    IF trip_row.completed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Completed Field Trips cannot be reset' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.field_trip_publications publication
        WHERE publication.user_field_trip_id = trip_row.id
          AND publication.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Published Field Trips cannot be reset' USING ERRCODE = 'P0001';
    END IF;

    IF trip_row.hidden_at IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.user_field_trip_item_completions completion
           WHERE completion.user_field_trip_id = trip_row.id
       )
       AND NOT EXISTS (
           SELECT 1
           FROM public.user_field_trip_active_periods period
           WHERE period.user_field_trip_id = trip_row.id
       ) THEN
        RETURN trip_row.template_id;
    END IF;

    DELETE FROM public.user_field_trip_item_completions completion
    WHERE completion.user_field_trip_id = trip_row.id;

    DELETE FROM public.user_field_trip_active_periods period
    WHERE period.user_field_trip_id = trip_row.id;

    UPDATE public.user_field_trips
    SET started_at = mutation_time,
        current_level_number = 1,
        completed_at = NULL,
        hidden_at = mutation_time,
        updated_at = mutation_time
    WHERE id = trip_row.id;

    RETURN trip_row.template_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_stopped_field_trip_progress(
    self_id UUID,
    target_template_id UUID DEFAULT NULL,
    target_slug TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH stopped_trips AS (
        SELECT
            uft.id AS user_field_trip_id,
            uft.template_id,
            uft.started_at,
            uft.current_level_number,
            uft.completed_at,
            uft.is_profile_visible,
            uft.hidden_at,
            template.slug
        FROM public.user_field_trips uft
        JOIN public.field_trip_templates template
          ON template.id = uft.template_id
         AND template.is_active = TRUE
        WHERE uft.user_id = self_id
          AND uft.completed_at IS NULL
          AND uft.hidden_at IS NOT NULL
          AND (target_template_id IS NULL OR uft.template_id = target_template_id)
          AND (target_slug IS NULL OR template.slug = target_slug)
          AND EXISTS (
              SELECT 1
              FROM public.user_field_trip_active_periods period
              WHERE period.user_field_trip_id = uft.id
          )
    ),
    stopped_rows AS (
        SELECT
            trip.template_id,
            JSONB_BUILD_OBJECT(
                'user_field_trip_id', trip.user_field_trip_id,
                'started_at', trip.started_at,
                'current_level_number', trip.current_level_number,
                'completed_at', trip.completed_at,
                'is_profile_visible', trip.is_profile_visible,
                'completed_count', COALESCE(active_counts.completed_count, 0),
                'target_count', COALESCE(active_counts.target_count, 0),
                'publication_id', NULL,
                'published_at', NULL,
                'stopped_at', trip.hidden_at
            ) AS stopped_progress,
            COALESCE(levels.levels, '[]'::JSONB) AS levels
        FROM stopped_trips trip
        LEFT JOIN LATERAL (
            SELECT
                COUNT(item.id)::INTEGER AS target_count,
                COUNT(completion.id)::INTEGER AS completed_count
            FROM public.field_trip_levels level
            JOIN public.field_trip_checklist_items item
              ON item.level_id = level.id
            LEFT JOIN public.user_field_trip_item_completions completion
              ON completion.user_field_trip_id = trip.user_field_trip_id
             AND completion.item_id = item.id
            WHERE level.template_id = trip.template_id
              AND level.level_number = trip.current_level_number
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
                    level.id AS level_id,
                    level.level_number,
                    level.title,
                    level.description,
                    JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'item_id', item.id,
                            'prompt', item.prompt,
                            'match_type', item.match_type,
                            'guide_tip', item.guide_tip,
                            'guide', CASE
                                WHEN item.guide_where_to_look IS NULL
                                 AND item.guide_best_conditions IS NULL
                                 AND item.guide_what_to_notice IS NULL
                                 AND item.guide_scan_safely IS NULL THEN NULL
                                ELSE JSONB_BUILD_OBJECT(
                                    'where_to_look', item.guide_where_to_look,
                                    'best_conditions', item.guide_best_conditions,
                                    'what_to_notice', item.guide_what_to_notice,
                                    'scan_safely', item.guide_scan_safely
                                )
                            END,
                            'is_completed', completion.id IS NOT NULL,
                            'completed_at', completion.completed_at,
                            'completed_common_name', completion.common_name,
                            'completed_scientific_name', completion.scientific_name,
                            'completed_scan_id', completion.scan_id
                        )
                        ORDER BY item.sort_order
                    ) AS items
                FROM public.field_trip_levels level
                JOIN public.field_trip_checklist_items item
                  ON item.level_id = level.id
                LEFT JOIN public.user_field_trip_item_completions completion
                  ON completion.user_field_trip_id = trip.user_field_trip_id
                 AND completion.item_id = item.id
                WHERE level.template_id = trip.template_id
                GROUP BY level.id, level.level_number, level.title, level.description
            ) level_rows
        ) levels ON TRUE
    )
    SELECT COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'template_id', row.template_id,
                'stopped_progress', row.stopped_progress,
                'levels', row.levels
            )
            ORDER BY row.template_id
        ),
        '[]'::JSONB
    )
    FROM stopped_rows row;
$$;

REVOKE ALL ON FUNCTION public.stop_field_trip(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reset_field_trip(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_stopped_field_trip_progress(UUID, UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stop_field_trip(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.reset_field_trip(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_stopped_field_trip_progress(UUID, UUID, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.start_field_trip(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_field_trip(UUID, UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.join_field_trip_challenge(
    self_id UUID,
    target_challenge_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    challenge_row RECORD;
    linked_trip_row RECORD;
    user_is_pro BOOLEAN := FALSE;
    mutation_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    SELECT *
    INTO challenge_row
    FROM public.field_trip_challenges c
    WHERE c.id = target_challenge_id
      AND c.is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip challenge not found' USING ERRCODE = 'P0002';
    END IF;

    IF mutation_time < challenge_row.starts_at OR mutation_time > challenge_row.ends_at THEN
        RAISE EXCEPTION 'Field Trip challenge is not open for joining' USING ERRCODE = 'P0001';
    END IF;

    IF challenge_row.is_pro_only AND NOT user_is_pro AND NOT challenge_row.is_temporarily_free THEN
        RAISE EXCEPTION 'Field Trip challenge requires Pro access' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.user_field_trips(
        user_id,
        template_id,
        started_at,
        current_level_number,
        is_profile_visible,
        hidden_at
    )
    VALUES (self_id, challenge_row.template_id, mutation_time, 1, TRUE, NULL)
    ON CONFLICT(user_id, template_id) DO UPDATE
    SET hidden_at = NULL,
        is_profile_visible = TRUE,
        updated_at = mutation_time
    RETURNING * INTO linked_trip_row;

    IF linked_trip_row.completed_at IS NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.user_field_trip_active_periods period
            WHERE period.user_field_trip_id = linked_trip_row.id
        ) THEN
            UPDATE public.user_field_trips
            SET started_at = mutation_time,
                current_level_number = 1,
                completed_at = NULL,
                hidden_at = NULL,
                updated_at = mutation_time
            WHERE id = linked_trip_row.id
            RETURNING * INTO linked_trip_row;
        END IF;

        INSERT INTO public.user_field_trip_active_periods(
            user_field_trip_id,
            started_at,
            stopped_at
        )
        SELECT linked_trip_row.id, mutation_time, NULL
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.user_field_trip_active_periods period
            WHERE period.user_field_trip_id = linked_trip_row.id
              AND period.stopped_at IS NULL
        )
        ON CONFLICT DO NOTHING;
    END IF;

    INSERT INTO public.field_trip_challenge_participants(
        challenge_id,
        user_id,
        user_field_trip_id,
        joined_at,
        current_level_number,
        hidden_at
    )
    VALUES (
        target_challenge_id,
        self_id,
        linked_trip_row.id,
        mutation_time,
        1,
        NULL
    )
    ON CONFLICT(user_id, challenge_id) DO UPDATE
    SET hidden_at = NULL,
        user_field_trip_id = EXCLUDED.user_field_trip_id,
        updated_at = mutation_time;

    RETURN public.get_field_trip_challenge_detail(self_id, target_challenge_id, NULL, 12);
END;
$$;

REVOKE ALL ON FUNCTION public.join_field_trip_challenge(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_field_trip_challenge(UUID, UUID) TO service_role;
 
CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress(self_id UUID, target_scan_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    user_is_pro BOOLEAN := FALSE;
    inserted_count INTEGER := 0;
    response JSONB := '[]'::jsonb;
BEGIN
    SELECT
        s.id,
        s.user_id,
        s.timestamp,
        s.ecology_type::TEXT AS ecology_type,
        s.is_tombstoned,
        s.is_biological_subject,
        COALESCE(s.confirmed_species_id, s.species_id) AS resolved_species_id,
        sd.scientific_name,
        sd.common_names,
        sd.kingdom,
        sd.phylum,
        sd."class",
        sd."order",
        sd.family,
        sd.genus,
        sd.habitat_description,
        sd.group_tags
    INTO scan_row
    FROM public.scans s
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE s.id = target_scan_id
      AND s.user_id = self_id;

    IF NOT FOUND OR scan_row.is_tombstoned OR scan_row.is_biological_subject IS FALSE OR scan_row.resolved_species_id IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    DROP TABLE IF EXISTS pg_temp.field_trip_scan_matches;
    CREATE TEMP TABLE field_trip_scan_matches ON COMMIT DROP AS
    WITH eligible_templates AS (
        SELECT t.*
        FROM public.field_trip_templates t
        WHERE t.is_active = TRUE
          AND (t.is_pro_only = FALSE OR user_is_pro OR t.is_rotating_free = TRUE)
    ),
    candidate_levels AS (
        SELECT
            t.id AS template_id,
            CASE
                WHEN uft.id IS NOT NULL
                 AND EXISTS (
                    SELECT 1
                    FROM public.user_field_trip_active_periods period
                    WHERE period.user_field_trip_id = uft.id
                      AND scan_row.timestamp >= period.started_at
                      AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
                 ) THEN uft.id
                ELSE NULL
            END AS user_field_trip_id,
            CASE
                WHEN uft.id IS NOT NULL
                 AND EXISTS (
                    SELECT 1
                    FROM public.user_field_trip_active_periods period
                    WHERE period.user_field_trip_id = uft.id
                      AND scan_row.timestamp >= period.started_at
                      AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
                 ) THEN uft.current_level_number
                ELSE 1
            END AS level_number,
            CASE
                WHEN uft.id IS NOT NULL
                 AND EXISTS (
                    SELECT 1
                    FROM public.user_field_trip_active_periods period
                    WHERE period.user_field_trip_id = uft.id
                      AND scan_row.timestamp >= period.started_at
                      AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
                 ) THEN uft.started_at
                ELSE scan_row.timestamp
            END AS started_at,
            (
                uft.id IS NULL
                OR (
                    NOT EXISTS (
                        SELECT 1
                        FROM public.user_field_trip_active_periods period
                        WHERE period.user_field_trip_id = uft.id
                    )
                    AND scan_row.timestamp >= uft.started_at
                )
            ) AS should_auto_start
        FROM eligible_templates t
        LEFT JOIN public.user_field_trips uft
            ON uft.template_id = t.id
           AND uft.user_id = self_id
           AND uft.completed_at IS NULL
        WHERE uft.id IS NULL
           OR EXISTS (
                SELECT 1
                FROM public.user_field_trip_active_periods period
                WHERE period.user_field_trip_id = uft.id
                  AND scan_row.timestamp >= period.started_at
                  AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
           )
           OR (
                NOT EXISTS (
                    SELECT 1
                    FROM public.user_field_trip_active_periods period
                    WHERE period.user_field_trip_id = uft.id
                )
                AND scan_row.timestamp >= uft.started_at
           )
    )
    SELECT
        cl.template_id,
        cl.user_field_trip_id,
        cl.level_number,
        cl.started_at,
        cl.should_auto_start,
        fl.id AS level_id,
        fci.id AS item_id,
        fci.prompt,
        scan_row.resolved_species_id::UUID AS species_id,
        public.field_trip_species_common_name(scan_row.common_names, scan_row.scientific_name, fci.prompt) AS common_name,
        scan_row.scientific_name::TEXT AS scientific_name
    FROM candidate_levels cl
    JOIN public.field_trip_levels fl
        ON fl.template_id = cl.template_id
       AND fl.level_number = cl.level_number
    JOIN public.field_trip_checklist_items fci
        ON fci.level_id = fl.id
    WHERE scan_row.timestamp >= cl.started_at
      AND public.field_trip_item_matches_scan(
          fci.match_type,
          fci.species_id,
          fci.scientific_name,
          fci.taxonomy_kingdom,
          fci.taxonomy_phylum,
          fci.taxonomy_class,
          fci.taxonomy_order,
          fci.taxonomy_family,
          fci.taxonomy_genus,
          fci.ecology_type,
          fci.habitat_tag,
          fci.semantic_tag,
          scan_row.resolved_species_id,
          scan_row.scientific_name,
          scan_row.common_names,
          scan_row.kingdom,
          scan_row.phylum,
          scan_row."class",
          scan_row."order",
          scan_row.family,
          scan_row.genus,
          scan_row.ecology_type,
          scan_row.habitat_description,
          scan_row.group_tags
      );

    INSERT INTO public.user_field_trips(
        user_id,
        template_id,
        started_at,
        current_level_number,
        completed_at,
        is_profile_visible,
        hidden_at
    )
    SELECT DISTINCT
        self_id,
        m.template_id,
        scan_row.timestamp,
        1,
        NULL::TIMESTAMPTZ,
        TRUE,
        NULL::TIMESTAMPTZ
    FROM pg_temp.field_trip_scan_matches m
    WHERE m.should_auto_start
    ON CONFLICT(user_id, template_id) DO UPDATE
    SET started_at = EXCLUDED.started_at,
        current_level_number = 1,
        completed_at = NULL,
        is_profile_visible = TRUE,
        hidden_at = NULL,
        updated_at = NOW();

    INSERT INTO public.user_field_trip_active_periods(
        user_field_trip_id,
        started_at,
        stopped_at
    )
    SELECT DISTINCT uft.id, scan_row.timestamp, NULL::TIMESTAMPTZ
    FROM pg_temp.field_trip_scan_matches m
    JOIN public.user_field_trips uft
      ON uft.user_id = self_id
     AND uft.template_id = m.template_id
    WHERE m.should_auto_start
    ON CONFLICT DO NOTHING;

    DROP TABLE IF EXISTS pg_temp.field_trip_new_completions;
    CREATE TEMP TABLE field_trip_new_completions (
        user_field_trip_id UUID NOT NULL,
        item_id UUID NOT NULL
    ) ON COMMIT DROP;

    WITH resolved_matches AS (
        SELECT
            uft.id AS user_field_trip_id,
            m.item_id,
            m.species_id,
            m.common_name,
            m.scientific_name
        FROM pg_temp.field_trip_scan_matches m
        JOIN public.user_field_trips uft
            ON uft.user_id = self_id
           AND uft.template_id = m.template_id
        WHERE uft.completed_at IS NULL
          AND EXISTS (
              SELECT 1
              FROM public.user_field_trip_active_periods period
              WHERE period.user_field_trip_id = uft.id
                AND scan_row.timestamp >= period.started_at
                AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
          )
    ),
    inserted AS (
        INSERT INTO public.user_field_trip_item_completions(
            user_field_trip_id,
            item_id,
            scan_id,
            species_id,
            common_name,
            scientific_name,
            completed_at
        )
        SELECT
            rm.user_field_trip_id,
            rm.item_id,
            target_scan_id,
            rm.species_id,
            rm.common_name,
            rm.scientific_name,
            scan_row.timestamp::TIMESTAMPTZ
        FROM resolved_matches rm
        ON CONFLICT(user_field_trip_id, item_id) DO NOTHING
        RETURNING user_field_trip_id, item_id
    )
    INSERT INTO pg_temp.field_trip_new_completions(user_field_trip_id, item_id)
    SELECT user_field_trip_id, item_id
    FROM inserted;

    GET DIAGNOSTICS inserted_count = ROW_COUNT;

    IF inserted_count = 0 THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH touched_trips AS (
        SELECT DISTINCT uft.id, uft.template_id, uft.current_level_number
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_scan_matches m
            ON m.template_id = uft.template_id
        WHERE uft.user_id = self_id
    ),
    level_counts AS (
        SELECT
            tt.id AS user_field_trip_id,
            tt.template_id,
            tt.current_level_number,
            fl.id AS current_level_id,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM touched_trips tt
        JOIN public.field_trip_levels fl
            ON fl.template_id = tt.template_id
           AND fl.level_number = tt.current_level_number
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = tt.id
           AND ufc.item_id = fci.id
        GROUP BY tt.id, tt.template_id, tt.current_level_number, fl.id
    ),
    next_levels AS (
        SELECT
            lc.*,
            (
                SELECT MIN(next_fl.level_number)
                FROM public.field_trip_levels next_fl
                WHERE next_fl.template_id = lc.template_id
                  AND next_fl.level_number > lc.current_level_number
            ) AS next_level_number
        FROM level_counts lc
        WHERE lc.completed_count >= lc.target_count
    )
    UPDATE public.user_field_trips uft
    SET current_level_number = COALESCE(nl.next_level_number, uft.current_level_number),
        completed_at = CASE
            WHEN nl.next_level_number IS NULL THEN COALESCE(uft.completed_at, NOW())
            ELSE uft.completed_at
        END,
        hidden_at = CASE
            WHEN nl.next_level_number IS NULL THEN NULL
            ELSE uft.hidden_at
        END
    FROM next_levels nl
    WHERE uft.id = nl.user_field_trip_id;

    UPDATE public.user_field_trip_active_periods period
    SET stopped_at = uft.completed_at
    FROM public.user_field_trips uft
    WHERE period.user_field_trip_id = uft.id
      AND period.stopped_at IS NULL
      AND uft.completed_at IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM pg_temp.field_trip_new_completions completion
          WHERE completion.user_field_trip_id = uft.id
      );

    WITH touched_trips AS (
        SELECT DISTINCT uft.id
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_new_completions new_completion
            ON new_completion.user_field_trip_id = uft.id
        WHERE uft.user_id = self_id
    ),
    trip_counts AS (
        SELECT
            uft.id AS user_field_trip_id,
            uft.current_level_number,
            uft.completed_at,
            t.id AS template_id,
            t.slug,
            t.title,
            fl.id AS current_level_id,
            fl.title AS current_level_title,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM touched_trips tt
        JOIN public.user_field_trips uft
            ON uft.id = tt.id
        JOIN public.field_trip_templates t
            ON t.id = uft.template_id
        LEFT JOIN public.field_trip_levels fl
            ON fl.template_id = t.id
           AND fl.level_number = uft.current_level_number
        LEFT JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = fci.id
        GROUP BY uft.id, uft.current_level_number, uft.completed_at, t.id, t.slug, t.title, fl.id, fl.title
    ),
    credited_progress AS (
        SELECT
            uft.id AS user_field_trip_id,
            fl.level_number,
            fl.title AS level_title,
            COUNT(DISTINCT all_items.id)::INTEGER AS target_count,
            COUNT(DISTINCT all_completions.item_id)::INTEGER AS completed_count
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_new_completions credited_completion
            ON credited_completion.user_field_trip_id = uft.id
        JOIN public.field_trip_checklist_items credited_item
            ON credited_item.id = credited_completion.item_id
        JOIN public.field_trip_levels fl
            ON fl.id = credited_item.level_id
        JOIN public.field_trip_checklist_items all_items
            ON all_items.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions all_completions
            ON all_completions.user_field_trip_id = uft.id
           AND all_completions.item_id = all_items.id
        WHERE uft.user_id = self_id
        GROUP BY uft.id, fl.id, fl.level_number, fl.title
    ),
    newly_completed AS (
        SELECT
            uft.id AS user_field_trip_id,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'item_id', fci.id,
                    'prompt', fci.prompt,
                    'common_name', ufc.common_name,
                    'scientific_name', ufc.scientific_name,
                    'completed_at', ufc.completed_at
                )
                ORDER BY fci.sort_order
            ) AS items
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_new_completions new_completion
            ON new_completion.user_field_trip_id = uft.id
        JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = new_completion.item_id
        JOIN public.field_trip_checklist_items fci
            ON fci.id = ufc.item_id
        WHERE uft.user_id = self_id
        GROUP BY uft.id
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'user_field_trip_id', tc.user_field_trip_id,
            'template_id', tc.template_id,
            'slug', tc.slug,
            'title', tc.title,
            'current_level_number', tc.current_level_number,
            'current_level_title', tc.current_level_title,
            'completed_count', tc.completed_count,
            'target_count', tc.target_count,
            'is_complete', tc.completed_at IS NOT NULL,
            'credited_level_number', cp.level_number,
            'credited_level_title', cp.level_title,
            'credited_completed_count', cp.completed_count,
            'credited_target_count', cp.target_count,
            'newly_completed_items', COALESCE(nc.items, '[]'::jsonb)
        )
        ORDER BY tc.title
    ), '[]'::jsonb)
    INTO response
    FROM trip_counts tc
    JOIN credited_progress cp
        ON cp.user_field_trip_id = tc.user_field_trip_id
    LEFT JOIN newly_completed nc
        ON nc.user_field_trip_id = tc.user_field_trip_id;

    RETURN response;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress(UUID, UUID) TO service_role;

NOTIFY pgrst, 'reload schema';
