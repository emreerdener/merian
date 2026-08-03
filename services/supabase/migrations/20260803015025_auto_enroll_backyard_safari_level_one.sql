-- Make the starter Backyard Safari available from a user's first scan without
-- weakening the scan-progress contract: enrollment still creates an explicit
-- trip and activity window, and scan matching never creates either one.
-- Existing trip rows are intentionally left alone so completed, stopped, or
-- reset outings are not silently resumed.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

DO $preflight$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.field_trip_templates AS template
        JOIN public.field_trip_levels AS level
          ON level.template_id = template.id
         AND level.level_number = 1
        JOIN public.field_trip_checklist_items AS item
          ON item.level_id = level.id
        WHERE template.slug = 'backyard_safari'
          AND template.is_active = TRUE
          AND (
              template.is_pro_only = FALSE
              OR template.is_rotating_free = TRUE
          )
    ) THEN
        RAISE EXCEPTION
            'Backyard Safari auto-enrollment requires an active, accessible Level 1';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION internal.auto_enroll_backyard_safari_level_one()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    backyard_template_id UUID;
    enrolled_trip_id UUID;
    enrollment_time TIMESTAMPTZ := pg_catalog.NOW();
BEGIN
    SELECT template.id
    INTO backyard_template_id
    FROM public.field_trip_templates AS template
    WHERE template.slug = 'backyard_safari'
      AND template.is_active = TRUE
      AND (
          template.is_pro_only = FALSE
          OR template.is_rotating_free = TRUE
      )
      AND EXISTS (
          SELECT 1
          FROM public.field_trip_levels AS level
          JOIN public.field_trip_checklist_items AS item
            ON item.level_id = level.id
          WHERE level.template_id = template.id
            AND level.level_number = 1
      );

    -- Allow account creation to continue if the curated starter is retired in
    -- the future. The deployment preflight above protects today's invariant.
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.user_field_trips (
        user_id,
        template_id,
        started_at,
        current_level_number,
        is_profile_visible,
        hidden_at
    )
    VALUES (
        NEW.id,
        backyard_template_id,
        enrollment_time,
        1,
        TRUE,
        NULL
    )
    ON CONFLICT (user_id, template_id) DO NOTHING
    RETURNING id INTO enrolled_trip_id;

    IF enrolled_trip_id IS NOT NULL THEN
        INSERT INTO public.user_field_trip_active_periods (
            user_field_trip_id,
            started_at,
            stopped_at
        )
        VALUES (enrolled_trip_id, enrollment_time, NULL)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION internal.auto_enroll_backyard_safari_level_one() IS
    'Database-only public.users insert trigger that starts accessible Backyard Safari Level 1 for a new account without resuming existing trip state.';

REVOKE ALL ON FUNCTION internal.auto_enroll_backyard_safari_level_one()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS auto_enroll_backyard_safari_level_one_on_user_insert
    ON public.users;
CREATE TRIGGER auto_enroll_backyard_safari_level_one_on_user_insert
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.auto_enroll_backyard_safari_level_one();

COMMENT ON TRIGGER auto_enroll_backyard_safari_level_one_on_user_insert
    ON public.users IS
    'Starts accessible Backyard Safari Level 1 and its first activity period after a new signed-in or ghost profile is inserted.';

WITH backyard_template AS (
    SELECT template.id
    FROM public.field_trip_templates AS template
    WHERE template.slug = 'backyard_safari'
      AND template.is_active = TRUE
      AND (
          template.is_pro_only = FALSE
          OR template.is_rotating_free = TRUE
      )
      AND EXISTS (
          SELECT 1
          FROM public.field_trip_levels AS level
          JOIN public.field_trip_checklist_items AS item
            ON item.level_id = level.id
          WHERE level.template_id = template.id
            AND level.level_number = 1
      )
),
enrolled_trips AS (
    INSERT INTO public.user_field_trips (
        user_id,
        template_id,
        started_at,
        current_level_number,
        is_profile_visible,
        hidden_at
    )
    SELECT
        users.id,
        backyard_template.id,
        pg_catalog.NOW(),
        1,
        TRUE,
        NULL::TIMESTAMPTZ
    FROM public.users AS users
    CROSS JOIN backyard_template
    ON CONFLICT (user_id, template_id) DO NOTHING
    RETURNING id, started_at
)
INSERT INTO public.user_field_trip_active_periods (
    user_field_trip_id,
    started_at,
    stopped_at
)
SELECT enrolled_trips.id, enrolled_trips.started_at, NULL::TIMESTAMPTZ
FROM enrolled_trips
ON CONFLICT DO NOTHING;

RESET statement_timeout;
RESET lock_timeout;
