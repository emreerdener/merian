-- Preserve the level credited by a scan in progress responses even when the
-- completion immediately advances the participant to the next level.

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
            COALESCE(uft.id, NULL) AS user_field_trip_id,
            COALESCE(uft.current_level_number, 1) AS level_number,
            COALESCE(uft.started_at, scan_row.timestamp) AS started_at
        FROM eligible_templates t
        LEFT JOIN public.user_field_trips uft
            ON uft.template_id = t.id
           AND uft.user_id = self_id
           AND uft.completed_at IS NULL
           AND uft.hidden_at IS NULL
    )
    SELECT
        cl.template_id,
        cl.user_field_trip_id,
        cl.level_number,
        cl.started_at,
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

    INSERT INTO public.user_field_trips(user_id, template_id, started_at, current_level_number, is_profile_visible)
    SELECT DISTINCT self_id, m.template_id, scan_row.timestamp, 1, TRUE
    FROM pg_temp.field_trip_scan_matches m
    WHERE m.user_field_trip_id IS NULL
    ON CONFLICT(user_id, template_id) DO NOTHING;

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
          AND uft.hidden_at IS NULL
          AND scan_row.timestamp >= uft.started_at
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
            scan_row.timestamp
        FROM resolved_matches rm
        ON CONFLICT(user_field_trip_id, item_id) DO NOTHING
        RETURNING user_field_trip_id, item_id
    )
    SELECT COUNT(*)::INTEGER
    INTO inserted_count
    FROM inserted;

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
        completed_at = CASE WHEN nl.next_level_number IS NULL THEN COALESCE(uft.completed_at, NOW()) ELSE uft.completed_at END
    FROM next_levels nl
    WHERE uft.id = nl.user_field_trip_id;

    WITH touched_trips AS (
        SELECT DISTINCT uft.id
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_scan_matches m
            ON m.template_id = uft.template_id
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
        JOIN public.user_field_trip_item_completions credited_completion
            ON credited_completion.user_field_trip_id = uft.id
           AND credited_completion.scan_id = target_scan_id
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
        JOIN pg_temp.field_trip_scan_matches m
            ON m.template_id = uft.template_id
        JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = m.item_id
           AND ufc.scan_id = target_scan_id
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

CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress(self_id UUID, target_scan_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
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

    DROP TABLE IF EXISTS pg_temp.field_trip_challenge_scan_matches;
    CREATE TEMP TABLE field_trip_challenge_scan_matches ON COMMIT DROP AS
    SELECT
        p.id AS participation_id,
        p.challenge_id,
        c.template_id,
        p.current_level_number,
        fl.id AS level_id,
        fci.id AS item_id,
        fci.prompt,
        scan_row.resolved_species_id::UUID AS species_id,
        public.field_trip_species_common_name(scan_row.common_names, scan_row.scientific_name, fci.prompt) AS common_name,
        scan_row.scientific_name::TEXT AS scientific_name
    FROM public.field_trip_challenge_participants p
    JOIN public.field_trip_challenges c
        ON c.id = p.challenge_id
    JOIN public.field_trip_levels fl
        ON fl.template_id = c.template_id
       AND fl.level_number = p.current_level_number
    JOIN public.field_trip_checklist_items fci
        ON fci.level_id = fl.id
    WHERE p.user_id = self_id
      AND p.hidden_at IS NULL
      AND p.completed_at IS NULL
      AND c.is_active = TRUE
      AND scan_row.timestamp >= p.joined_at
      AND scan_row.timestamp <= c.ends_at
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

    WITH inserted AS (
        INSERT INTO public.field_trip_challenge_item_completions(
            participation_id,
            item_id,
            scan_id,
            species_id,
            common_name,
            scientific_name,
            completed_at
        )
        SELECT
            m.participation_id,
            m.item_id,
            target_scan_id,
            m.species_id,
            m.common_name,
            m.scientific_name,
            scan_row.timestamp
        FROM pg_temp.field_trip_challenge_scan_matches m
        ON CONFLICT(participation_id, item_id) DO NOTHING
        RETURNING participation_id, item_id
    )
    SELECT COUNT(*)::INTEGER
    INTO inserted_count
    FROM inserted;

    IF inserted_count = 0 THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH touched_participations AS (
        SELECT DISTINCT p.id, p.challenge_id, c.template_id, p.current_level_number
        FROM public.field_trip_challenge_participants p
        JOIN pg_temp.field_trip_challenge_scan_matches m
            ON m.participation_id = p.id
        JOIN public.field_trip_challenges c
            ON c.id = p.challenge_id
        WHERE p.user_id = self_id
    ),
    level_counts AS (
        SELECT
            tp.id AS participation_id,
            tp.challenge_id,
            tp.template_id,
            tp.current_level_number,
            fl.id AS current_level_id,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(comp.id)::INTEGER AS completed_count
        FROM touched_participations tp
        JOIN public.field_trip_levels fl
            ON fl.template_id = tp.template_id
           AND fl.level_number = tp.current_level_number
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = tp.id
           AND comp.item_id = fci.id
        GROUP BY tp.id, tp.challenge_id, tp.template_id, tp.current_level_number, fl.id
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
    UPDATE public.field_trip_challenge_participants p
    SET current_level_number = COALESCE(nl.next_level_number, p.current_level_number),
        completed_at = CASE WHEN nl.next_level_number IS NULL THEN COALESCE(p.completed_at, NOW()) ELSE p.completed_at END,
        badge_awarded_at = CASE WHEN nl.next_level_number IS NULL THEN COALESCE(p.badge_awarded_at, NOW()) ELSE p.badge_awarded_at END
    FROM next_levels nl
    WHERE p.id = nl.participation_id;

    INSERT INTO public.field_trip_challenge_badges(
        participation_id,
        challenge_id,
        user_id,
        badge_key,
        title,
        awarded_at,
        is_profile_visible
    )
    SELECT
        p.id,
        p.challenge_id,
        p.user_id,
        c.slug || '_completed',
        c.title || ' Completed',
        COALESCE(p.badge_awarded_at, NOW()),
        TRUE
    FROM public.field_trip_challenge_participants p
    JOIN public.field_trip_challenges c
        ON c.id = p.challenge_id
    JOIN pg_temp.field_trip_challenge_scan_matches m
        ON m.participation_id = p.id
    WHERE p.user_id = self_id
      AND p.completed_at IS NOT NULL
      AND p.badge_awarded_at IS NOT NULL
    ON CONFLICT(user_id, challenge_id) DO NOTHING;

    WITH touched_participations AS (
        SELECT DISTINCT p.id
        FROM public.field_trip_challenge_participants p
        JOIN pg_temp.field_trip_challenge_scan_matches m
            ON m.participation_id = p.id
        WHERE p.user_id = self_id
    ),
    participation_counts AS (
        SELECT
            p.id AS participation_id,
            p.challenge_id,
            c.slug,
            c.title,
            c.suggested_hashtags,
            p.current_level_number,
            p.completed_at,
            p.badge_awarded_at,
            fl.title AS current_level_title,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(comp.id)::INTEGER AS completed_count
        FROM touched_participations tp
        JOIN public.field_trip_challenge_participants p
            ON p.id = tp.id
        JOIN public.field_trip_challenges c
            ON c.id = p.challenge_id
        LEFT JOIN public.field_trip_levels fl
            ON fl.template_id = c.template_id
           AND fl.level_number = p.current_level_number
        LEFT JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = p.id
           AND comp.item_id = fci.id
        GROUP BY p.id, p.challenge_id, c.slug, c.title, c.suggested_hashtags, p.current_level_number, p.completed_at, p.badge_awarded_at, fl.title
    ),
    credited_progress AS (
        SELECT
            p.id AS participation_id,
            fl.level_number,
            fl.title AS level_title,
            COUNT(DISTINCT all_items.id)::INTEGER AS target_count,
            COUNT(DISTINCT all_completions.item_id)::INTEGER AS completed_count
        FROM public.field_trip_challenge_participants p
        JOIN public.field_trip_challenge_item_completions credited_completion
            ON credited_completion.participation_id = p.id
           AND credited_completion.scan_id = target_scan_id
        JOIN public.field_trip_checklist_items credited_item
            ON credited_item.id = credited_completion.item_id
        JOIN public.field_trip_levels fl
            ON fl.id = credited_item.level_id
        JOIN public.field_trip_checklist_items all_items
            ON all_items.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions all_completions
            ON all_completions.participation_id = p.id
           AND all_completions.item_id = all_items.id
        WHERE p.user_id = self_id
        GROUP BY p.id, fl.id, fl.level_number, fl.title
    ),
    newly_completed AS (
        SELECT
            p.id AS participation_id,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'item_id', fci.id,
                    'prompt', fci.prompt,
                    'common_name', comp.common_name,
                    'scientific_name', comp.scientific_name,
                    'completed_at', comp.completed_at
                )
                ORDER BY fci.sort_order
            ) AS items
        FROM public.field_trip_challenge_participants p
        JOIN pg_temp.field_trip_challenge_scan_matches m
            ON m.participation_id = p.id
        JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = p.id
           AND comp.item_id = m.item_id
           AND comp.scan_id = target_scan_id
        JOIN public.field_trip_checklist_items fci
            ON fci.id = comp.item_id
        WHERE p.user_id = self_id
        GROUP BY p.id
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'participation_id', pc.participation_id,
            'challenge_id', pc.challenge_id,
            'slug', pc.slug,
            'title', pc.title,
            'current_level_number', pc.current_level_number,
            'current_level_title', pc.current_level_title,
            'completed_count', pc.completed_count,
            'target_count', pc.target_count,
            'is_complete', pc.completed_at IS NOT NULL,
            'badge_awarded_at', pc.badge_awarded_at,
            'suggested_hashtags', pc.suggested_hashtags,
            'credited_level_number', cp.level_number,
            'credited_level_title', cp.level_title,
            'credited_completed_count', cp.completed_count,
            'credited_target_count', cp.target_count,
            'newly_completed_items', COALESCE(nc.items, '[]'::jsonb)
        )
        ORDER BY pc.title
    ), '[]'::jsonb)
    INTO response
    FROM participation_counts pc
    JOIN credited_progress cp
        ON cp.participation_id = pc.participation_id
    LEFT JOIN newly_completed nc
        ON nc.participation_id = pc.participation_id;

    RETURN response;
END;
$$;
