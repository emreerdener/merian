-- Field Trip progress should not treat a weak, unreviewed model identification
-- as verified evidence. Automatically accept the same tier-specific boundary
-- used by the "Possible match" UI, while allowing explicit confirmation,
-- correction, or community resolution to qualify regardless of the original
-- model score.
--
-- The canonical UI constants are FLASH_POSSIBLE = 0.75 and
-- PRO_POSSIBLE = 0.65 in functions/_shared/identify/thresholds.ts.

CREATE OR REPLACE FUNCTION public.field_trip_scan_identification_is_eligible(
    ai_confidence_score DOUBLE PRECISION,
    inference_tier TEXT,
    confirmed_species_id UUID,
    user_confirmed_identification BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT
        confirmed_species_id IS NOT NULL
        OR COALESCE(user_confirmed_identification, FALSE)
        OR (
            COALESCE(ai_confidence_score BETWEEN 0.0 AND 1.0, FALSE)
            AND ai_confidence_score >= CASE
                WHEN LOWER(BTRIM(COALESCE(inference_tier, ''))) = 'pro'
                    THEN 0.65
                ELSE 0.75
            END
        );
$$;

COMMENT ON FUNCTION public.field_trip_scan_identification_is_eligible(
    DOUBLE PRECISION,
    TEXT,
    UUID,
    BOOLEAN
) IS
    'Internal Field Trip evidence policy: Possible match or better for the inference tier, or an explicitly confirmed/resolved identification.';

REVOKE ALL ON FUNCTION public.field_trip_scan_identification_is_eligible(
    DOUBLE PRECISION,
    TEXT,
    UUID,
    BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;

-- Confidence can be revised after a scan was credited. Ineligible scans must
-- therefore reconcile any existing contribution instead of only blocking new
-- credit. These private helpers reopen completed experiences and withdraw
-- completion-derived artifacts when the removed contribution creates a gap.
CREATE OR REPLACE FUNCTION public.remove_ineligible_field_trip_scan_progress(
    self_id UUID,
    target_scan_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    affected RECORD;
    next_level_number INTEGER;
BEGIN
    FOR affected IN
        SELECT
            completion.id AS completion_id,
            trip.id AS user_field_trip_id,
            trip.template_id
        FROM public.user_field_trip_item_completions AS completion
        JOIN public.user_field_trips AS trip
            ON trip.id = completion.user_field_trip_id
        WHERE completion.scan_id = target_scan_id
          AND trip.user_id = self_id
        ORDER BY trip.id, completion.id
        FOR UPDATE OF trip
    LOOP
        DELETE FROM public.user_field_trip_item_completions AS completion
        WHERE completion.id = affected.completion_id;

        SELECT MIN(level.level_number)
        INTO next_level_number
        FROM public.field_trip_levels AS level
        WHERE level.template_id = affected.template_id
          AND (
              SELECT COUNT(*)
              FROM public.user_field_trip_item_completions AS completion
              JOIN public.field_trip_checklist_items AS item
                  ON item.id = completion.item_id
              WHERE completion.user_field_trip_id =
                      affected.user_field_trip_id
                AND item.level_id = level.id
          ) < (
              SELECT COUNT(*)
              FROM public.field_trip_checklist_items AS item
              WHERE item.level_id = level.id
          );

        IF next_level_number IS NOT NULL THEN
            UPDATE public.user_field_trips AS trip
            SET current_level_number = next_level_number,
                completed_at = NULL,
                updated_at = NOW()
            WHERE trip.id = affected.user_field_trip_id;

            UPDATE public.field_trip_publications AS publication
            SET deleted_at = COALESCE(publication.deleted_at, NOW()),
                updated_at = NOW()
            WHERE publication.user_field_trip_id =
                    affected.user_field_trip_id
              AND publication.deleted_at IS NULL;
        END IF;
    END LOOP;

    RETURN '[]'::JSONB;
END;
$$;

COMMENT ON FUNCTION public.remove_ineligible_field_trip_scan_progress(
    UUID,
    UUID
) IS
    'Internal reconciliation that removes standard Field Trip credit for a scan that no longer satisfies the evidence policy.';

REVOKE ALL ON FUNCTION public.remove_ineligible_field_trip_scan_progress(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.remove_ineligible_field_trip_challenge_scan_progress(
    self_id UUID,
    target_scan_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    affected RECORD;
    next_level_number INTEGER;
BEGIN
    FOR affected IN
        SELECT
            completion.id AS completion_id,
            participation.id AS participation_id,
            challenge.template_id
        FROM public.field_trip_challenge_item_completions AS completion
        JOIN public.field_trip_challenge_participants AS participation
            ON participation.id = completion.participation_id
        JOIN public.field_trip_challenges AS challenge
            ON challenge.id = participation.challenge_id
        WHERE completion.scan_id = target_scan_id
          AND participation.user_id = self_id
        ORDER BY participation.id, completion.id
        FOR UPDATE OF participation
    LOOP
        DELETE FROM public.field_trip_challenge_item_completions AS completion
        WHERE completion.id = affected.completion_id;

        SELECT MIN(level.level_number)
        INTO next_level_number
        FROM public.field_trip_levels AS level
        WHERE level.template_id = affected.template_id
          AND (
              SELECT COUNT(*)
              FROM public.field_trip_challenge_item_completions AS completion
              JOIN public.field_trip_checklist_items AS item
                  ON item.id = completion.item_id
              WHERE completion.participation_id = affected.participation_id
                AND item.level_id = level.id
          ) < (
              SELECT COUNT(*)
              FROM public.field_trip_checklist_items AS item
              WHERE item.level_id = level.id
          );

        IF next_level_number IS NOT NULL THEN
            UPDATE public.field_trip_challenge_participants AS participation
            SET current_level_number = next_level_number,
                completed_at = NULL,
                badge_awarded_at = NULL,
                updated_at = NOW()
            WHERE participation.id = affected.participation_id;

            DELETE FROM public.field_trip_challenge_badges AS badge
            WHERE badge.participation_id = affected.participation_id;

            UPDATE public.field_trip_challenge_entries AS entry
            SET deleted_at = COALESCE(entry.deleted_at, NOW()),
                updated_at = NOW()
            WHERE entry.participation_id = affected.participation_id
              AND entry.deleted_at IS NULL;
        END IF;
    END LOOP;

    RETURN '[]'::JSONB;
END;
$$;

COMMENT ON FUNCTION public.remove_ineligible_field_trip_challenge_scan_progress(
    UUID,
    UUID
) IS
    'Internal reconciliation that removes Event credit for a scan that no longer satisfies the evidence policy.';

REVOKE ALL ON FUNCTION public.remove_ineligible_field_trip_challenge_scan_progress(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

-- Preserve the existing matching and correction implementations behind
-- private unchecked names. The public progress entry points below own the
-- confidence policy, and only the PostgreSQL owner can reach these functions.
ALTER FUNCTION public.apply_field_trip_scan_progress_v2(
    UUID,
    UUID,
    UUID,
    UUID
) RENAME TO apply_field_trip_scan_progress_v2_unchecked;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress_v2_unchecked(
    UUID,
    UUID,
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.apply_field_trip_scan_progress_v2_unchecked(
    UUID,
    UUID,
    UUID,
    UUID
) IS
    'Internal contribution mutation. Call apply_field_trip_scan_progress_v2 so confidence eligibility is enforced.';

ALTER FUNCTION public.apply_field_trip_challenge_scan_progress(
    UUID,
    UUID
) RENAME TO apply_field_trip_challenge_scan_progress_unchecked;

REVOKE ALL ON FUNCTION public.apply_field_trip_challenge_scan_progress_unchecked(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.apply_field_trip_challenge_scan_progress_unchecked(
    UUID,
    UUID
) IS
    'Internal Event contribution mutation. Call apply_field_trip_challenge_scan_progress so confidence eligibility is enforced.';

CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_v2(
    self_id UUID,
    target_scan_id UUID,
    preferred_user_field_trip_id UUID,
    preferred_item_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    identification_is_eligible BOOLEAN := FALSE;
BEGIN
    SELECT public.field_trip_scan_identification_is_eligible(
        scan.ai_confidence_score,
        scan.inference_tier,
        scan.confirmed_species_id,
        scan.user_confirmed_identification
    )
    INTO identification_is_eligible
    FROM public.scans AS scan
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id;

    IF identification_is_eligible IS NOT TRUE THEN
        RETURN public.remove_ineligible_field_trip_scan_progress(
            self_id,
            target_scan_id
        );
    END IF;

    RETURN public.apply_field_trip_scan_progress_v2_unchecked(
        self_id,
        target_scan_id,
        preferred_user_field_trip_id,
        preferred_item_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress_v2(
    UUID,
    UUID,
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress(
    self_id UUID,
    target_scan_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    RETURN public.apply_field_trip_scan_progress_v2(
        self_id,
        target_scan_id,
        NULL,
        NULL
    );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress(
    self_id UUID,
    target_scan_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    identification_is_eligible BOOLEAN := FALSE;
BEGIN
    SELECT public.field_trip_scan_identification_is_eligible(
        scan.ai_confidence_score,
        scan.inference_tier,
        scan.confirmed_species_id,
        scan.user_confirmed_identification
    )
    INTO identification_is_eligible
    FROM public.scans AS scan
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id;

    IF identification_is_eligible IS NOT TRUE THEN
        RETURN public.remove_ineligible_field_trip_challenge_scan_progress(
            self_id,
            target_scan_id
        );
    END IF;

    RETURN public.apply_field_trip_challenge_scan_progress_unchecked(
        self_id,
        target_scan_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_challenge_scan_progress(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

-- Confidence and explicit-confirmation fields are part of the idempotency
-- revision. This lets a finalization repair or a confirmation-only update
-- replace a prior no-credit receipt.
CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_atomic(
    self_id UUID,
    target_scan_id UUID,
    preferred_user_field_trip_id UUID DEFAULT NULL,
    preferred_item_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    current_scan_revision JSONB;
    existing_receipt public.field_trip_scan_progress_receipts%ROWTYPE;
    has_existing_receipt BOOLEAN := FALSE;
    effective_preferred_user_field_trip_id UUID;
    effective_preferred_item_id UUID;
    previous_achievement JSONB;
    current_achievement JSONB;
    field_trip_updates JSONB;
    challenge_updates JSONB;
    mutation_completed_trip BOOLEAN;
    achievement_newly_unlocked BOOLEAN;
    response JSONB;
BEGIN
    PERFORM internal.require_service_role();

    IF (preferred_user_field_trip_id IS NULL) <> (preferred_item_id IS NULL) THEN
        RAISE EXCEPTION 'preferred Field Trip goal must include both identifiers'
            USING ERRCODE = '22023';
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'species_id', scan.species_id,
        'confirmed_species_id', scan.confirmed_species_id,
        'ai_confidence_score', scan.ai_confidence_score,
        'inference_tier', scan.inference_tier,
        'user_confirmed_identification', scan.user_confirmed_identification,
        'is_biological_subject', scan.is_biological_subject,
        'is_tombstoned', scan.is_tombstoned,
        'timestamp', scan.timestamp
    )
    INTO current_scan_revision
    FROM public.scans AS scan
    WHERE scan.id = target_scan_id
      AND scan.user_id = self_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN JSONB_BUILD_OBJECT(
            'field_trip_updates', '[]'::JSONB,
            'challenge_updates', '[]'::JSONB,
            'first_field_trip_achievement', NULL,
            'first_field_trip_achievement_newly_unlocked', FALSE
        );
    END IF;

    SELECT receipt.*
    INTO existing_receipt
    FROM public.field_trip_scan_progress_receipts AS receipt
    WHERE receipt.scan_id = target_scan_id
      AND receipt.user_id = self_id
    FOR UPDATE;
    has_existing_receipt := FOUND;

    IF has_existing_receipt
       AND existing_receipt.scan_revision = current_scan_revision
       AND (
           preferred_user_field_trip_id IS NULL
           OR (
               existing_receipt.preferred_user_field_trip_id =
                   preferred_user_field_trip_id
               AND existing_receipt.preferred_item_id = preferred_item_id
           )
       ) THEN
        RETURN existing_receipt.result;
    END IF;

    effective_preferred_user_field_trip_id :=
        preferred_user_field_trip_id;
    effective_preferred_item_id := preferred_item_id;
    IF effective_preferred_user_field_trip_id IS NULL
       AND effective_preferred_item_id IS NULL
       AND has_existing_receipt
       AND existing_receipt.preferred_user_field_trip_id IS NOT NULL
       AND existing_receipt.preferred_item_id IS NOT NULL THEN
        effective_preferred_user_field_trip_id :=
            existing_receipt.preferred_user_field_trip_id;
        effective_preferred_item_id := existing_receipt.preferred_item_id;
    END IF;

    previous_achievement :=
        public.get_first_field_trip_achievement_progress(self_id);

    field_trip_updates := public.apply_field_trip_scan_progress_v2(
        self_id,
        target_scan_id,
        effective_preferred_user_field_trip_id,
        effective_preferred_item_id
    );
    challenge_updates := public.apply_field_trip_challenge_scan_progress(
        self_id,
        target_scan_id
    );

    current_achievement :=
        public.get_first_field_trip_achievement_progress(self_id);
    mutation_completed_trip := EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(
            COALESCE(field_trip_updates, '[]'::JSONB)
            || COALESCE(challenge_updates, '[]'::JSONB)
        ) AS update_row(value)
        WHERE COALESCE(
            (update_row.value ->> 'is_complete')::BOOLEAN,
            FALSE
        )
    );
    achievement_newly_unlocked := previous_achievement IS NULL
        AND current_achievement IS NOT NULL
        AND mutation_completed_trip;

    response := JSONB_BUILD_OBJECT(
        'field_trip_updates', COALESCE(field_trip_updates, '[]'::JSONB),
        'challenge_updates', COALESCE(challenge_updates, '[]'::JSONB),
        'first_field_trip_achievement', current_achievement,
        'first_field_trip_achievement_newly_unlocked',
            achievement_newly_unlocked
    );

    INSERT INTO public.field_trip_scan_progress_receipts(
        scan_id,
        user_id,
        scan_revision,
        preferred_user_field_trip_id,
        preferred_item_id,
        result,
        processed_at,
        updated_at
    )
    VALUES (
        target_scan_id,
        self_id,
        current_scan_revision,
        effective_preferred_user_field_trip_id,
        effective_preferred_item_id,
        response,
        NOW(),
        NOW()
    )
    ON CONFLICT(scan_id) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        scan_revision = EXCLUDED.scan_revision,
        preferred_user_field_trip_id =
            EXCLUDED.preferred_user_field_trip_id,
        preferred_item_id = EXCLUDED.preferred_item_id,
        result = EXCLUDED.result,
        processed_at = NOW(),
        updated_at = NOW();

    RETURN response;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress_atomic(
    UUID,
    UUID,
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress_atomic(
    UUID,
    UUID,
    UUID,
    UUID
) TO service_role;

-- Insert already sees the completed scan row. Updates must also re-enter the
-- transaction boundary when any field that controls evidence eligibility
-- changes.
DROP TRIGGER IF EXISTS trg_apply_ingested_scan_field_trip_progress_update
    ON public.scans;
CREATE TRIGGER trg_apply_ingested_scan_field_trip_progress_update
AFTER UPDATE OF
    species_id,
    confirmed_species_id,
    ai_confidence_score,
    inference_tier,
    user_confirmed_identification,
    is_biological_subject,
    is_tombstoned,
    timestamp
ON public.scans
FOR EACH ROW
WHEN (
    OLD.species_id IS DISTINCT FROM NEW.species_id
    OR OLD.confirmed_species_id IS DISTINCT FROM NEW.confirmed_species_id
    OR OLD.ai_confidence_score IS DISTINCT FROM NEW.ai_confidence_score
    OR OLD.inference_tier IS DISTINCT FROM NEW.inference_tier
    OR OLD.user_confirmed_identification IS DISTINCT FROM
        NEW.user_confirmed_identification
    OR OLD.is_biological_subject IS DISTINCT FROM NEW.is_biological_subject
    OR OLD.is_tombstoned IS DISTINCT FROM NEW.is_tombstoned
    OR OLD.timestamp IS DISTINCT FROM NEW.timestamp
)
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();

-- Repair credit issued before the confidence policy existed. Retain the
-- private selected-goal preference so later confirmation can still honor the
-- user's Capture intent.
CREATE TEMP TABLE invalid_confidence_standard_completions
ON COMMIT DROP
AS
SELECT
    completion.id AS completion_id,
    completion.scan_id,
    trip.id AS user_field_trip_id,
    trip.user_id
FROM public.user_field_trip_item_completions AS completion
JOIN public.user_field_trips AS trip
    ON trip.id = completion.user_field_trip_id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
WHERE public.field_trip_scan_identification_is_eligible(
    scan.ai_confidence_score,
    scan.inference_tier,
    scan.confirmed_species_id,
    scan.user_confirmed_identification
) IS NOT TRUE;

CREATE TEMP TABLE invalid_confidence_challenge_completions
ON COMMIT DROP
AS
SELECT
    completion.id AS completion_id,
    completion.scan_id,
    participation.id AS participation_id,
    participation.user_id
FROM public.field_trip_challenge_item_completions AS completion
JOIN public.field_trip_challenge_participants AS participation
    ON participation.id = completion.participation_id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
WHERE public.field_trip_scan_identification_is_eligible(
    scan.ai_confidence_score,
    scan.inference_tier,
    scan.confirmed_species_id,
    scan.user_confirmed_identification
) IS NOT TRUE;

CREATE TEMP TABLE affected_confidence_scans
ON COMMIT DROP
AS
WITH affected AS (
    SELECT scan_id, user_id
    FROM invalid_confidence_standard_completions
    UNION
    SELECT scan_id, user_id
    FROM invalid_confidence_challenge_completions
)
SELECT
    affected.scan_id,
    affected.user_id,
    COALESCE(
        receipt.preferred_user_field_trip_id,
        preference.user_field_trip_id
    ) AS preferred_user_field_trip_id,
    COALESCE(
        receipt.preferred_item_id,
        preference.item_id
    ) AS preferred_item_id
FROM affected
LEFT JOIN public.field_trip_scan_progress_receipts AS receipt
    ON receipt.scan_id = affected.scan_id
   AND receipt.user_id = affected.user_id
LEFT JOIN public.field_trip_scan_goal_preferences AS preference
    ON preference.scan_id = affected.scan_id
   AND preference.user_id = affected.user_id;

DELETE FROM public.user_field_trip_item_completions AS completion
USING invalid_confidence_standard_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_challenge_item_completions AS completion
USING invalid_confidence_challenge_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_scan_progress_receipts AS receipt
USING affected_confidence_scans AS affected
WHERE receipt.scan_id = affected.scan_id
  AND receipt.user_id = affected.user_id;

WITH affected_trips AS (
    SELECT DISTINCT user_field_trip_id
    FROM invalid_confidence_standard_completions
),
earliest_incomplete AS (
    SELECT
        trip.id AS user_field_trip_id,
        MIN(level.level_number) AS level_number
    FROM affected_trips AS affected
    JOIN public.user_field_trips AS trip
        ON trip.id = affected.user_field_trip_id
    JOIN public.field_trip_levels AS level
        ON level.template_id = trip.template_id
    WHERE (
        SELECT COUNT(*)
        FROM public.user_field_trip_item_completions AS completion
        JOIN public.field_trip_checklist_items AS item
            ON item.id = completion.item_id
        WHERE completion.user_field_trip_id = trip.id
          AND item.level_id = level.id
    ) < (
        SELECT COUNT(*)
        FROM public.field_trip_checklist_items AS item
        WHERE item.level_id = level.id
    )
    GROUP BY trip.id
)
UPDATE public.user_field_trips AS trip
SET current_level_number = incomplete.level_number,
    completed_at = NULL,
    updated_at = NOW()
FROM earliest_incomplete AS incomplete
WHERE trip.id = incomplete.user_field_trip_id;

UPDATE public.field_trip_publications AS publication
SET deleted_at = COALESCE(publication.deleted_at, NOW()),
    updated_at = NOW()
WHERE publication.user_field_trip_id IN (
    SELECT DISTINCT user_field_trip_id
    FROM invalid_confidence_standard_completions
)
  AND publication.deleted_at IS NULL;

WITH affected_participations AS (
    SELECT DISTINCT participation_id
    FROM invalid_confidence_challenge_completions
),
earliest_incomplete AS (
    SELECT
        participation.id AS participation_id,
        MIN(level.level_number) AS level_number
    FROM affected_participations AS affected
    JOIN public.field_trip_challenge_participants AS participation
        ON participation.id = affected.participation_id
    JOIN public.field_trip_challenges AS challenge
        ON challenge.id = participation.challenge_id
    JOIN public.field_trip_levels AS level
        ON level.template_id = challenge.template_id
    WHERE (
        SELECT COUNT(*)
        FROM public.field_trip_challenge_item_completions AS completion
        JOIN public.field_trip_checklist_items AS item
            ON item.id = completion.item_id
        WHERE completion.participation_id = participation.id
          AND item.level_id = level.id
    ) < (
        SELECT COUNT(*)
        FROM public.field_trip_checklist_items AS item
        WHERE item.level_id = level.id
    )
    GROUP BY participation.id
)
UPDATE public.field_trip_challenge_participants AS participation
SET current_level_number = incomplete.level_number,
    completed_at = NULL,
    badge_awarded_at = NULL,
    updated_at = NOW()
FROM earliest_incomplete AS incomplete
WHERE participation.id = incomplete.participation_id;

DELETE FROM public.field_trip_challenge_badges AS badge
WHERE badge.participation_id IN (
    SELECT DISTINCT participation_id
    FROM invalid_confidence_challenge_completions
);

UPDATE public.field_trip_challenge_entries AS entry
SET deleted_at = COALESCE(entry.deleted_at, NOW()),
    updated_at = NOW()
WHERE entry.participation_id IN (
    SELECT DISTINCT participation_id
    FROM invalid_confidence_challenge_completions
)
  AND entry.deleted_at IS NULL;

-- Preserve qualifying receipts while extending their revision shape.
UPDATE public.field_trip_scan_progress_receipts AS receipt
SET scan_revision = receipt.scan_revision || JSONB_BUILD_OBJECT(
        'ai_confidence_score', scan.ai_confidence_score,
        'inference_tier', scan.inference_tier,
        'user_confirmed_identification',
            scan.user_confirmed_identification
    ),
    updated_at = NOW()
FROM public.scans AS scan
WHERE scan.id = receipt.scan_id
  AND scan.user_id = receipt.user_id;

-- Recreate an empty receipt for repaired weak scans. Besides preventing a
-- stale progress toast, this remains a durable marker that lets a later
-- confirmation-only update re-enter the ingestion trigger.
DO $repair$
DECLARE
    affected RECORD;
BEGIN
    FOR affected IN
        SELECT repair.*
        FROM affected_confidence_scans AS repair
        ORDER BY repair.user_id, repair.scan_id
    LOOP
        PERFORM public.apply_field_trip_scan_progress_atomic(
            affected.user_id,
            affected.scan_id,
            affected.preferred_user_field_trip_id,
            affected.preferred_item_id
        );
    END LOOP;
END;
$repair$;

-- Migration-time verification: no remaining completion may rely on a weak,
-- unreviewed identification.
DO $verify$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.user_field_trip_item_completions AS completion
        JOIN public.scans AS scan
            ON scan.id = completion.scan_id
        WHERE public.field_trip_scan_identification_is_eligible(
            scan.ai_confidence_score,
            scan.inference_tier,
            scan.confirmed_species_id,
            scan.user_confirmed_identification
        ) IS NOT TRUE
    ) OR EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_item_completions AS completion
        JOIN public.scans AS scan
            ON scan.id = completion.scan_id
        WHERE public.field_trip_scan_identification_is_eligible(
            scan.ai_confidence_score,
            scan.inference_tier,
            scan.confirmed_species_id,
            scan.user_confirmed_identification
        ) IS NOT TRUE
    ) THEN
        RAISE EXCEPTION
            'Weak, unreviewed Field Trip progress remains after confidence repair';
    END IF;
END;
$verify$;
