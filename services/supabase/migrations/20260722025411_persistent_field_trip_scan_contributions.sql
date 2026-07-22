-- Persistent, scan-addressable Field trip contributions.
--
-- A scan can advance several deliberately active experiences, but it may own at
-- most one checklist credit inside each standard outing or joined Event. Capture
-- may provide a preferred standard-outing goal; the preference is private and is
-- only honored when it is owned, current, active at the scan timestamp, and still
-- matches the scan's resolved identification.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.user_field_trips WHERE completed_at IS NOT NULL)
       OR EXISTS (SELECT 1 FROM public.field_trip_publications)
       OR EXISTS (
            SELECT 1
            FROM public.field_trip_challenge_participants
            WHERE completed_at IS NOT NULL OR badge_awarded_at IS NOT NULL
       )
       OR EXISTS (SELECT 1 FROM public.field_trip_challenge_badges)
       OR EXISTS (SELECT 1 FROM public.field_trip_challenge_entries) THEN
        RAISE EXCEPTION
            'Persistent Field trip contribution migration aborted: completed or published Field trip artifacts exist.';
    END IF;
END;
$$;

CREATE TABLE public.field_trip_scan_goal_preferences (
    scan_id UUID PRIMARY KEY REFERENCES public.scans(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_field_trip_id UUID NOT NULL REFERENCES public.user_field_trips(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.field_trip_checklist_items(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.field_trip_scan_goal_preferences IS
    'Private live-Capture goal preferences used to deterministically credit a saved scan.';

CREATE INDEX idx_field_trip_scan_goal_preferences_user
    ON public.field_trip_scan_goal_preferences(user_id);
CREATE INDEX idx_field_trip_scan_goal_preferences_trip
    ON public.field_trip_scan_goal_preferences(user_field_trip_id);
CREATE INDEX idx_field_trip_scan_goal_preferences_item
    ON public.field_trip_scan_goal_preferences(item_id);

ALTER TABLE public.field_trip_scan_goal_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.field_trip_scan_goal_preferences
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.field_trip_scan_goal_preferences
    TO service_role;

CREATE OR REPLACE FUNCTION public.field_trip_checklist_match_rank(
    match_type TEXT,
    taxonomy_kingdom TEXT,
    taxonomy_phylum TEXT,
    taxonomy_class TEXT,
    taxonomy_order TEXT,
    taxonomy_family TEXT,
    taxonomy_genus TEXT
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT CASE match_type
        WHEN 'species' THEN 10
        WHEN 'scientific_name' THEN 20
        WHEN 'taxonomy' THEN CASE
            WHEN NULLIF(BTRIM(taxonomy_genus), '') IS NOT NULL THEN 30
            WHEN NULLIF(BTRIM(taxonomy_family), '') IS NOT NULL THEN 31
            WHEN NULLIF(BTRIM(taxonomy_order), '') IS NOT NULL THEN 32
            WHEN NULLIF(BTRIM(taxonomy_class), '') IS NOT NULL THEN 33
            WHEN NULLIF(BTRIM(taxonomy_phylum), '') IS NOT NULL THEN 34
            WHEN NULLIF(BTRIM(taxonomy_kingdom), '') IS NOT NULL THEN 35
            ELSE 39
        END
        WHEN 'semantic_tag' THEN 40
        WHEN 'ecology' THEN 41
        WHEN 'habitat' THEN 42
        ELSE 99
    END;
$$;

REVOKE ALL ON FUNCTION public.field_trip_checklist_match_rank(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.field_trip_checklist_match_rank(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)
    TO service_role;

-- Existing progress is deliberately deduplicated in place. Only scans which
-- already own credit participate; this migration never replays an uncredited scan.
WITH ranked AS (
    SELECT
        completion.id,
        ROW_NUMBER() OVER (
            PARTITION BY completion.user_field_trip_id, completion.scan_id
            ORDER BY
                public.field_trip_checklist_match_rank(
                    item.match_type,
                    item.taxonomy_kingdom,
                    item.taxonomy_phylum,
                    item.taxonomy_class,
                    item.taxonomy_order,
                    item.taxonomy_family,
                    item.taxonomy_genus
                ),
                item.sort_order,
                item.id
        ) AS match_position
    FROM public.user_field_trip_item_completions completion
    JOIN public.scans scan ON scan.id = completion.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
    WHERE scan.is_tombstoned IS FALSE
      AND scan.is_biological_subject IS TRUE
      AND COALESCE(scan.confirmed_species_id, scan.species_id) IS NOT NULL
      AND public.field_trip_item_matches_scan(
          item.match_type,
          item.species_id,
          item.scientific_name,
          item.taxonomy_kingdom,
          item.taxonomy_phylum,
          item.taxonomy_class,
          item.taxonomy_order,
          item.taxonomy_family,
          item.taxonomy_genus,
          item.ecology_type,
          item.habitat_tag,
          item.semantic_tag,
          COALESCE(scan.confirmed_species_id, scan.species_id),
          species.scientific_name,
          species.common_names,
          species.kingdom,
          species.phylum,
          species."class",
          species."order",
          species.family,
          species.genus,
          scan.ecology_type::TEXT,
          species.habitat_description,
          species.group_tags
      )
), keepers AS (
    SELECT id FROM ranked WHERE match_position = 1
)
DELETE FROM public.user_field_trip_item_completions completion
WHERE NOT EXISTS (SELECT 1 FROM keepers WHERE keepers.id = completion.id);

WITH ranked AS (
    SELECT
        completion.id,
        ROW_NUMBER() OVER (
            PARTITION BY completion.participation_id, completion.scan_id
            ORDER BY
                public.field_trip_checklist_match_rank(
                    item.match_type,
                    item.taxonomy_kingdom,
                    item.taxonomy_phylum,
                    item.taxonomy_class,
                    item.taxonomy_order,
                    item.taxonomy_family,
                    item.taxonomy_genus
                ),
                item.sort_order,
                item.id
        ) AS match_position
    FROM public.field_trip_challenge_item_completions completion
    JOIN public.scans scan ON scan.id = completion.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
    WHERE scan.is_tombstoned IS FALSE
      AND scan.is_biological_subject IS TRUE
      AND COALESCE(scan.confirmed_species_id, scan.species_id) IS NOT NULL
      AND public.field_trip_item_matches_scan(
          item.match_type,
          item.species_id,
          item.scientific_name,
          item.taxonomy_kingdom,
          item.taxonomy_phylum,
          item.taxonomy_class,
          item.taxonomy_order,
          item.taxonomy_family,
          item.taxonomy_genus,
          item.ecology_type,
          item.habitat_tag,
          item.semantic_tag,
          COALESCE(scan.confirmed_species_id, scan.species_id),
          species.scientific_name,
          species.common_names,
          species.kingdom,
          species.phylum,
          species."class",
          species."order",
          species.family,
          species.genus,
          scan.ecology_type::TEXT,
          species.habitat_description,
          species.group_tags
      )
), keepers AS (
    SELECT id FROM ranked WHERE match_position = 1
)
DELETE FROM public.field_trip_challenge_item_completions completion
WHERE NOT EXISTS (SELECT 1 FROM keepers WHERE keepers.id = completion.id);

CREATE UNIQUE INDEX user_field_trip_item_completions_one_credit_per_scan
    ON public.user_field_trip_item_completions(user_field_trip_id, scan_id);
CREATE INDEX user_field_trip_item_completions_scan_lookup
    ON public.user_field_trip_item_completions(scan_id, user_field_trip_id);
CREATE UNIQUE INDEX field_trip_challenge_item_completions_one_credit_per_scan
    ON public.field_trip_challenge_item_completions(participation_id, scan_id);
CREATE INDEX field_trip_challenge_item_completions_scan_lookup
    ON public.field_trip_challenge_item_completions(scan_id, participation_id);

-- Dedupe can reopen an earlier level. Preserve all remaining later-level credits
-- and point each unfinished experience at its earliest incomplete level.
WITH incomplete AS (
    SELECT trip.id AS user_field_trip_id, MIN(level.level_number) AS level_number
    FROM public.user_field_trips trip
    JOIN public.field_trip_levels level ON level.template_id = trip.template_id
    WHERE trip.completed_at IS NULL
      AND (
          SELECT COUNT(*)
          FROM public.user_field_trip_item_completions completion
          JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
          WHERE completion.user_field_trip_id = trip.id
            AND item.level_id = level.id
      ) < (
          SELECT COUNT(*)
          FROM public.field_trip_checklist_items item
          WHERE item.level_id = level.id
      )
    GROUP BY trip.id
)
UPDATE public.user_field_trips trip
SET current_level_number = incomplete.level_number,
    updated_at = NOW()
FROM incomplete
WHERE trip.id = incomplete.user_field_trip_id;

WITH incomplete AS (
    SELECT participation.id AS participation_id, MIN(level.level_number) AS level_number
    FROM public.field_trip_challenge_participants participation
    JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
    JOIN public.field_trip_levels level ON level.template_id = challenge.template_id
    WHERE participation.completed_at IS NULL
      AND (
          SELECT COUNT(*)
          FROM public.field_trip_challenge_item_completions completion
          JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
          WHERE completion.participation_id = participation.id
            AND item.level_id = level.id
      ) < (
          SELECT COUNT(*)
          FROM public.field_trip_checklist_items item
          WHERE item.level_id = level.id
      )
    GROUP BY participation.id
)
UPDATE public.field_trip_challenge_participants participation
SET current_level_number = incomplete.level_number,
    updated_at = NOW()
FROM incomplete
WHERE participation.id = incomplete.participation_id;

CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_v2(
    self_id UUID,
    target_scan_id UUID,
    preferred_user_field_trip_id UUID,
    preferred_item_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    trip_row RECORD;
    existing_row RECORD;
    winner_row RECORD;
    state_row RECORD;
    stored_preferred_user_field_trip_id UUID;
    stored_preferred_item_id UUID;
    has_existing BOOLEAN;
    has_winner BOOLEAN;
    target_level_number INTEGER;
    credited_level_number INTEGER;
    old_item_id UUID;
    new_item_id UUID;
    response JSONB := '[]'::jsonb;
    user_is_pro BOOLEAN := FALSE;
BEGIN
    SELECT
        scan.id,
        scan.user_id,
        scan.timestamp,
        scan.ecology_type::TEXT AS ecology_type,
        scan.is_tombstoned,
        scan.is_biological_subject,
        COALESCE(scan.confirmed_species_id, scan.species_id) AS resolved_species_id,
        species.scientific_name,
        species.common_names,
        species.kingdom,
        species.phylum,
        species."class",
        species."order",
        species.family,
        species.genus,
        species.habitat_description,
        species.group_tags
    INTO scan_row
    FROM public.scans scan
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id;

    IF NOT FOUND
       OR scan_row.is_tombstoned
       OR scan_row.is_biological_subject IS FALSE
       OR scan_row.resolved_species_id IS NULL THEN
        RETURN response;
    END IF;

    SELECT COALESCE(users.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users users
    WHERE users.id = self_id;

    -- Validate and persist only a live, visible Capture selection. Invalid,
    -- unauthorized, stale, completed, and nonmatching hints are silently ignored.
    IF preferred_user_field_trip_id IS NOT NULL AND preferred_item_id IS NOT NULL THEN
        PERFORM 1
        FROM public.user_field_trips trip
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        JOIN public.field_trip_levels level
            ON level.template_id = trip.template_id
           AND level.level_number = trip.current_level_number
        JOIN public.field_trip_checklist_items item
            ON item.id = preferred_item_id
           AND item.level_id = level.id
        WHERE trip.id = preferred_user_field_trip_id
          AND trip.user_id = self_id
          AND trip.completed_at IS NULL
          AND trip.hidden_at IS NULL
          AND template.is_active = TRUE
          AND (template.is_pro_only = FALSE OR user_is_pro OR template.is_rotating_free = TRUE)
          AND EXISTS (
              SELECT 1
              FROM public.user_field_trip_active_periods period
              WHERE period.user_field_trip_id = trip.id
                AND scan_row.timestamp >= period.started_at
                AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
          )
          AND public.field_trip_item_matches_scan(
              item.match_type,
              item.species_id,
              item.scientific_name,
              item.taxonomy_kingdom,
              item.taxonomy_phylum,
              item.taxonomy_class,
              item.taxonomy_order,
              item.taxonomy_family,
              item.taxonomy_genus,
              item.ecology_type,
              item.habitat_tag,
              item.semantic_tag,
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

        IF FOUND THEN
            INSERT INTO public.field_trip_scan_goal_preferences(
                scan_id,
                user_id,
                user_field_trip_id,
                item_id,
                updated_at
            )
            VALUES (
                target_scan_id,
                self_id,
                preferred_user_field_trip_id,
                preferred_item_id,
                NOW()
            )
            ON CONFLICT(scan_id) DO UPDATE
            SET user_id = EXCLUDED.user_id,
                user_field_trip_id = EXCLUDED.user_field_trip_id,
                item_id = EXCLUDED.item_id,
                updated_at = NOW();
        END IF;
    END IF;

    SELECT preference.user_field_trip_id, preference.item_id
    INTO stored_preferred_user_field_trip_id, stored_preferred_item_id
    FROM public.field_trip_scan_goal_preferences preference
    WHERE preference.scan_id = target_scan_id
      AND preference.user_id = self_id;

    FOR trip_row IN
        SELECT trip.id, trip.template_id, trip.current_level_number, template.slug, template.title
        FROM public.user_field_trips trip
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        WHERE trip.user_id = self_id
          AND trip.completed_at IS NULL
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.user_field_trip_item_completions existing_completion
                  WHERE existing_completion.user_field_trip_id = trip.id
                    AND existing_completion.scan_id = target_scan_id
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.user_field_trip_active_periods period
                  WHERE period.user_field_trip_id = trip.id
                    AND scan_row.timestamp >= period.started_at
                    AND (period.stopped_at IS NULL OR scan_row.timestamp <= period.stopped_at)
              )
          )
        ORDER BY trip.id
        FOR UPDATE OF trip
    LOOP
        SELECT
            completion.id,
            completion.item_id,
            level.level_number,
            item.prompt
        INTO existing_row
        FROM public.user_field_trip_item_completions completion
        JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
        JOIN public.field_trip_levels level ON level.id = item.level_id
        WHERE completion.user_field_trip_id = trip_row.id
          AND completion.scan_id = target_scan_id;
        has_existing := FOUND;
        old_item_id := CASE WHEN has_existing THEN existing_row.item_id ELSE NULL END;
        target_level_number := CASE
            WHEN has_existing THEN existing_row.level_number
            ELSE trip_row.current_level_number
        END;

        SELECT
            item.id AS item_id,
            item.prompt,
            level.level_number,
            level.title AS level_title
        INTO winner_row
        FROM public.field_trip_levels level
        JOIN public.field_trip_checklist_items item ON item.level_id = level.id
        WHERE level.template_id = trip_row.template_id
          AND level.level_number = target_level_number
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_field_trip_item_completions occupied
              WHERE occupied.user_field_trip_id = trip_row.id
                AND occupied.item_id = item.id
                AND occupied.scan_id <> target_scan_id
          )
          AND public.field_trip_item_matches_scan(
              item.match_type,
              item.species_id,
              item.scientific_name,
              item.taxonomy_kingdom,
              item.taxonomy_phylum,
              item.taxonomy_class,
              item.taxonomy_order,
              item.taxonomy_family,
              item.taxonomy_genus,
              item.ecology_type,
              item.habitat_tag,
              item.semantic_tag,
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
          )
        ORDER BY
            CASE
                WHEN stored_preferred_user_field_trip_id = trip_row.id
                 AND stored_preferred_item_id = item.id THEN 0
                ELSE 1
            END,
            public.field_trip_checklist_match_rank(
                item.match_type,
                item.taxonomy_kingdom,
                item.taxonomy_phylum,
                item.taxonomy_class,
                item.taxonomy_order,
                item.taxonomy_family,
                item.taxonomy_genus
            ),
            item.sort_order,
            item.id
        LIMIT 1;
        has_winner := FOUND;
        new_item_id := CASE WHEN has_winner THEN winner_row.item_id ELSE NULL END;

        IF has_existing AND has_winner AND old_item_id = new_item_id THEN
            UPDATE public.user_field_trip_item_completions
            SET species_id = scan_row.resolved_species_id,
                common_name = public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scientific_name = scan_row.scientific_name,
                completed_at = scan_row.timestamp
            WHERE id = existing_row.id;
            CONTINUE;
        END IF;

        IF NOT has_existing AND NOT has_winner THEN
            CONTINUE;
        END IF;

        IF has_existing THEN
            DELETE FROM public.user_field_trip_item_completions
            WHERE id = existing_row.id;
        END IF;

        IF has_winner THEN
            INSERT INTO public.user_field_trip_item_completions(
                user_field_trip_id,
                item_id,
                scan_id,
                species_id,
                common_name,
                scientific_name,
                completed_at
            )
            VALUES (
                trip_row.id,
                winner_row.item_id,
                target_scan_id,
                scan_row.resolved_species_id,
                public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scan_row.scientific_name,
                scan_row.timestamp
            );
        END IF;

        credited_level_number := target_level_number;

        SELECT level.level_number
        INTO state_row
        FROM public.field_trip_levels level
        WHERE level.template_id = trip_row.template_id
          AND (
              SELECT COUNT(*)
              FROM public.user_field_trip_item_completions completion
              JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
              WHERE completion.user_field_trip_id = trip_row.id
                AND item.level_id = level.id
          ) < (
              SELECT COUNT(*)
              FROM public.field_trip_checklist_items item
              WHERE item.level_id = level.id
          )
        ORDER BY level.level_number
        LIMIT 1;

        IF FOUND THEN
            UPDATE public.user_field_trips
            SET current_level_number = state_row.level_number,
                updated_at = NOW()
            WHERE id = trip_row.id;
        ELSE
            UPDATE public.user_field_trips
            SET completed_at = COALESCE(completed_at, NOW()),
                hidden_at = NULL,
                updated_at = NOW()
            WHERE id = trip_row.id;

            UPDATE public.user_field_trip_active_periods
            SET stopped_at = COALESCE(stopped_at, NOW())
            WHERE user_field_trip_id = trip_row.id
              AND stopped_at IS NULL;
        END IF;

        SELECT
            trip.id AS user_field_trip_id,
            trip.template_id,
            template.slug,
            template.title,
            trip.current_level_number,
            current_level.title AS current_level_title,
            trip.completed_at,
            credited_level.title AS credited_level_title,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = current_level.id
            ) AS target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.user_field_trip_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.user_field_trip_id = trip.id
                  AND item.level_id = current_level.id
            ) AS completed_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = credited_level.id
            ) AS credited_target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.user_field_trip_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.user_field_trip_id = trip.id
                  AND item.level_id = credited_level.id
            ) AS credited_completed_count
        INTO state_row
        FROM public.user_field_trips trip
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        LEFT JOIN public.field_trip_levels current_level
            ON current_level.template_id = trip.template_id
           AND current_level.level_number = trip.current_level_number
        JOIN public.field_trip_levels credited_level
            ON credited_level.template_id = trip.template_id
           AND credited_level.level_number = credited_level_number
        WHERE trip.id = trip_row.id;

        response := response || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'user_field_trip_id', state_row.user_field_trip_id,
            'template_id', state_row.template_id,
            'slug', state_row.slug,
            'title', state_row.title,
            'current_level_number', state_row.current_level_number,
            'current_level_title', state_row.current_level_title,
            'completed_count', COALESCE(state_row.completed_count, 0),
            'target_count', COALESCE(state_row.target_count, 0),
            'is_complete', state_row.completed_at IS NOT NULL,
            'credited_level_number', credited_level_number,
            'credited_level_title', state_row.credited_level_title,
            'credited_completed_count', COALESCE(state_row.credited_completed_count, 0),
            'credited_target_count', COALESCE(state_row.credited_target_count, 0),
            'newly_completed_items', CASE WHEN has_winner THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
                'item_id', winner_row.item_id,
                'prompt', winner_row.prompt,
                'common_name', public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                'scientific_name', scan_row.scientific_name,
                'completed_at', scan_row.timestamp
            )) ELSE '[]'::jsonb END,
            'removed_item_ids', CASE WHEN has_existing THEN JSONB_BUILD_ARRAY(old_item_id) ELSE '[]'::jsonb END
        ));
    END LOOP;

    RETURN response;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress_v2(UUID, UUID, UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress_v2(UUID, UUID, UUID, UUID)
    TO service_role;

-- Compatibility wrapper used by older Edge deployments and app clients.
CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress(self_id UUID, target_scan_id UUID)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.apply_field_trip_scan_progress_v2(self_id, target_scan_id, NULL, NULL);
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress(UUID, UUID)
    TO service_role;

CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress(
    self_id UUID,
    target_scan_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    participation_row RECORD;
    existing_row RECORD;
    winner_row RECORD;
    state_row RECORD;
    has_existing BOOLEAN;
    has_winner BOOLEAN;
    target_level_number INTEGER;
    credited_level_number INTEGER;
    old_item_id UUID;
    response JSONB := '[]'::jsonb;
BEGIN
    SELECT
        scan.id,
        scan.user_id,
        scan.timestamp,
        scan.ecology_type::TEXT AS ecology_type,
        scan.is_tombstoned,
        scan.is_biological_subject,
        COALESCE(scan.confirmed_species_id, scan.species_id) AS resolved_species_id,
        species.scientific_name,
        species.common_names,
        species.kingdom,
        species.phylum,
        species."class",
        species."order",
        species.family,
        species.genus,
        species.habitat_description,
        species.group_tags
    INTO scan_row
    FROM public.scans scan
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id;

    IF NOT FOUND
       OR scan_row.is_tombstoned
       OR scan_row.is_biological_subject IS FALSE
       OR scan_row.resolved_species_id IS NULL THEN
        RETURN response;
    END IF;

    FOR participation_row IN
        SELECT
            participation.id,
            participation.challenge_id,
            participation.current_level_number,
            challenge.template_id,
            challenge.slug,
            challenge.title,
            challenge.suggested_hashtags
        FROM public.field_trip_challenge_participants participation
        JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
        WHERE participation.user_id = self_id
          AND participation.completed_at IS NULL
          AND scan_row.timestamp >= participation.joined_at
          AND scan_row.timestamp BETWEEN challenge.starts_at AND challenge.ends_at
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.field_trip_challenge_item_completions existing_completion
                  WHERE existing_completion.participation_id = participation.id
                    AND existing_completion.scan_id = target_scan_id
              )
              OR (
                  participation.hidden_at IS NULL
                  AND challenge.is_active = TRUE
              )
          )
        ORDER BY participation.id
        FOR UPDATE OF participation
    LOOP
        SELECT
            completion.id,
            completion.item_id,
            level.level_number,
            item.prompt
        INTO existing_row
        FROM public.field_trip_challenge_item_completions completion
        JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
        JOIN public.field_trip_levels level ON level.id = item.level_id
        WHERE completion.participation_id = participation_row.id
          AND completion.scan_id = target_scan_id;
        has_existing := FOUND;
        old_item_id := CASE WHEN has_existing THEN existing_row.item_id ELSE NULL END;
        target_level_number := CASE
            WHEN has_existing THEN existing_row.level_number
            ELSE participation_row.current_level_number
        END;

        SELECT
            item.id AS item_id,
            item.prompt,
            level.level_number,
            level.title AS level_title
        INTO winner_row
        FROM public.field_trip_levels level
        JOIN public.field_trip_checklist_items item ON item.level_id = level.id
        WHERE level.template_id = participation_row.template_id
          AND level.level_number = target_level_number
          AND NOT EXISTS (
              SELECT 1
              FROM public.field_trip_challenge_item_completions occupied
              WHERE occupied.participation_id = participation_row.id
                AND occupied.item_id = item.id
                AND occupied.scan_id <> target_scan_id
          )
          AND public.field_trip_item_matches_scan(
              item.match_type,
              item.species_id,
              item.scientific_name,
              item.taxonomy_kingdom,
              item.taxonomy_phylum,
              item.taxonomy_class,
              item.taxonomy_order,
              item.taxonomy_family,
              item.taxonomy_genus,
              item.ecology_type,
              item.habitat_tag,
              item.semantic_tag,
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
          )
        ORDER BY
            public.field_trip_checklist_match_rank(
                item.match_type,
                item.taxonomy_kingdom,
                item.taxonomy_phylum,
                item.taxonomy_class,
                item.taxonomy_order,
                item.taxonomy_family,
                item.taxonomy_genus
            ),
            item.sort_order,
            item.id
        LIMIT 1;
        has_winner := FOUND;

        IF has_existing AND has_winner AND old_item_id = winner_row.item_id THEN
            UPDATE public.field_trip_challenge_item_completions
            SET species_id = scan_row.resolved_species_id,
                common_name = public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scientific_name = scan_row.scientific_name,
                completed_at = scan_row.timestamp
            WHERE id = existing_row.id;
            CONTINUE;
        END IF;

        IF NOT has_existing AND NOT has_winner THEN
            CONTINUE;
        END IF;

        IF has_existing THEN
            DELETE FROM public.field_trip_challenge_item_completions
            WHERE id = existing_row.id;
        END IF;

        IF has_winner THEN
            INSERT INTO public.field_trip_challenge_item_completions(
                participation_id,
                item_id,
                scan_id,
                species_id,
                common_name,
                scientific_name,
                completed_at
            )
            VALUES (
                participation_row.id,
                winner_row.item_id,
                target_scan_id,
                scan_row.resolved_species_id,
                public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                scan_row.scientific_name,
                scan_row.timestamp
            );
        END IF;

        credited_level_number := target_level_number;

        SELECT level.level_number
        INTO state_row
        FROM public.field_trip_levels level
        WHERE level.template_id = participation_row.template_id
          AND (
              SELECT COUNT(*)
              FROM public.field_trip_challenge_item_completions completion
              JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
              WHERE completion.participation_id = participation_row.id
                AND item.level_id = level.id
          ) < (
              SELECT COUNT(*)
              FROM public.field_trip_checklist_items item
              WHERE item.level_id = level.id
          )
        ORDER BY level.level_number
        LIMIT 1;

        IF FOUND THEN
            UPDATE public.field_trip_challenge_participants
            SET current_level_number = state_row.level_number,
                updated_at = NOW()
            WHERE id = participation_row.id;
        ELSE
            UPDATE public.field_trip_challenge_participants
            SET completed_at = COALESCE(completed_at, NOW()),
                badge_awarded_at = COALESCE(badge_awarded_at, NOW()),
                updated_at = NOW()
            WHERE id = participation_row.id;

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
                participation.id,
                participation.challenge_id,
                participation.user_id,
                challenge.slug || '_completed',
                challenge.title || ' Completed',
                participation.badge_awarded_at,
                TRUE
            FROM public.field_trip_challenge_participants participation
            JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
            WHERE participation.id = participation_row.id
            ON CONFLICT(user_id, challenge_id) DO NOTHING;
        END IF;

        SELECT
            participation.id AS participation_id,
            participation.challenge_id,
            challenge.slug,
            challenge.title,
            challenge.suggested_hashtags,
            participation.current_level_number,
            current_level.title AS current_level_title,
            participation.completed_at,
            participation.badge_awarded_at,
            credited_level.title AS credited_level_title,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = current_level.id
            ) AS target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.participation_id = participation.id
                  AND item.level_id = current_level.id
            ) AS completed_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_checklist_items item
                WHERE item.level_id = credited_level.id
            ) AS credited_target_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_item_completions completion
                JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
                WHERE completion.participation_id = participation.id
                  AND item.level_id = credited_level.id
            ) AS credited_completed_count
        INTO state_row
        FROM public.field_trip_challenge_participants participation
        JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
        LEFT JOIN public.field_trip_levels current_level
            ON current_level.template_id = challenge.template_id
           AND current_level.level_number = participation.current_level_number
        JOIN public.field_trip_levels credited_level
            ON credited_level.template_id = challenge.template_id
           AND credited_level.level_number = credited_level_number
        WHERE participation.id = participation_row.id;

        response := response || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
            'participation_id', state_row.participation_id,
            'challenge_id', state_row.challenge_id,
            'slug', state_row.slug,
            'title', state_row.title,
            'current_level_number', state_row.current_level_number,
            'current_level_title', state_row.current_level_title,
            'completed_count', COALESCE(state_row.completed_count, 0),
            'target_count', COALESCE(state_row.target_count, 0),
            'is_complete', state_row.completed_at IS NOT NULL,
            'badge_awarded_at', state_row.badge_awarded_at,
            'suggested_hashtags', state_row.suggested_hashtags,
            'credited_level_number', credited_level_number,
            'credited_level_title', state_row.credited_level_title,
            'credited_completed_count', COALESCE(state_row.credited_completed_count, 0),
            'credited_target_count', COALESCE(state_row.credited_target_count, 0),
            'newly_completed_items', CASE WHEN has_winner THEN JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
                'item_id', winner_row.item_id,
                'prompt', winner_row.prompt,
                'common_name', public.field_trip_species_common_name(
                    scan_row.common_names,
                    scan_row.scientific_name,
                    winner_row.prompt
                ),
                'scientific_name', scan_row.scientific_name,
                'completed_at', scan_row.timestamp
            )) ELSE '[]'::jsonb END,
            'removed_item_ids', CASE WHEN has_existing THEN JSONB_BUILD_ARRAY(old_item_id) ELSE '[]'::jsonb END
        ));
    END LOOP;

    RETURN response;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_challenge_scan_progress(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_challenge_scan_progress(UUID, UUID)
    TO service_role;

CREATE OR REPLACE FUNCTION public.get_field_trip_scan_contributions(
    self_id UUID,
    target_scan_id UUID
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH owned_scan AS (
        SELECT scan.id
        FROM public.scans scan
        WHERE scan.id = target_scan_id
          AND scan.user_id = self_id
          AND scan.is_tombstoned IS FALSE
          AND scan.is_biological_subject IS TRUE
    ), standard_contributions AS (
        SELECT
            completion.completed_at,
            JSONB_BUILD_OBJECT(
                'source_kind', 'standard_outing',
                'source_id', trip.id,
                'user_field_trip_id', trip.id,
                'participation_id', NULL,
                'template_id', template.id,
                'challenge_id', NULL,
                'title', template.title,
                'slug', template.slug,
                'item_id', item.id,
                'prompt', item.prompt,
                'level_number', level.level_number,
                'level_title', level.title,
                'completed_count', (
                    SELECT COUNT(*)::INTEGER
                    FROM public.user_field_trip_item_completions level_completion
                    JOIN public.field_trip_checklist_items level_item
                        ON level_item.id = level_completion.item_id
                    WHERE level_completion.user_field_trip_id = trip.id
                      AND level_item.level_id = level.id
                ),
                'target_count', (
                    SELECT COUNT(*)::INTEGER
                    FROM public.field_trip_checklist_items level_item
                    WHERE level_item.level_id = level.id
                ),
                'is_complete', trip.completed_at IS NOT NULL,
                'artwork_prompt', item.prompt,
                'artwork_template_slug', template.slug,
                'destination_kind', 'field_trip',
                'destination_template_id', template.id,
                'destination_checklist_item_id', item.id,
                'destination_challenge_id', NULL
            ) AS contribution
        FROM owned_scan
        JOIN public.user_field_trip_item_completions completion
            ON completion.scan_id = owned_scan.id
        JOIN public.user_field_trips trip ON trip.id = completion.user_field_trip_id
        JOIN public.field_trip_templates template ON template.id = trip.template_id
        JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
        JOIN public.field_trip_levels level ON level.id = item.level_id
        WHERE trip.user_id = self_id
    ), event_contributions AS (
        SELECT
            completion.completed_at,
            JSONB_BUILD_OBJECT(
                'source_kind', 'event',
                'source_id', participation.id,
                'user_field_trip_id', participation.user_field_trip_id,
                'participation_id', participation.id,
                'template_id', challenge.template_id,
                'challenge_id', challenge.id,
                'title', challenge.title,
                'slug', challenge.slug,
                'item_id', item.id,
                'prompt', item.prompt,
                'level_number', level.level_number,
                'level_title', level.title,
                'completed_count', (
                    SELECT COUNT(*)::INTEGER
                    FROM public.field_trip_challenge_item_completions level_completion
                    JOIN public.field_trip_checklist_items level_item
                        ON level_item.id = level_completion.item_id
                    WHERE level_completion.participation_id = participation.id
                      AND level_item.level_id = level.id
                ),
                'target_count', (
                    SELECT COUNT(*)::INTEGER
                    FROM public.field_trip_checklist_items level_item
                    WHERE level_item.level_id = level.id
                ),
                'is_complete', participation.completed_at IS NOT NULL,
                'artwork_prompt', item.prompt,
                'artwork_template_slug', template.slug,
                'destination_kind', 'field_trip_challenge',
                'destination_template_id', NULL,
                'destination_checklist_item_id', NULL,
                'destination_challenge_id', challenge.id
            ) AS contribution
        FROM owned_scan
        JOIN public.field_trip_challenge_item_completions completion
            ON completion.scan_id = owned_scan.id
        JOIN public.field_trip_challenge_participants participation
            ON participation.id = completion.participation_id
        JOIN public.field_trip_challenges challenge ON challenge.id = participation.challenge_id
        JOIN public.field_trip_templates template ON template.id = challenge.template_id
        JOIN public.field_trip_checklist_items item ON item.id = completion.item_id
        JOIN public.field_trip_levels level ON level.id = item.level_id
        WHERE participation.user_id = self_id
    ), contributions AS (
        SELECT * FROM standard_contributions
        UNION ALL
        SELECT * FROM event_contributions
    )
    SELECT COALESCE(
        JSONB_AGG(contribution ORDER BY completed_at, contribution->>'title', contribution->>'source_id'),
        '[]'::jsonb
    )
    FROM contributions;
$$;

REVOKE ALL ON FUNCTION public.get_field_trip_scan_contributions(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_scan_contributions(UUID, UUID)
    TO service_role;

NOTIFY pgrst, 'reload schema';
