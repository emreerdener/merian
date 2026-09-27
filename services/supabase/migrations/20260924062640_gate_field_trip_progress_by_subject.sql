-- Audio presence confidence cannot establish a resolved non-human Field Trip subject.
-- Preserve the existing tier thresholds and explicit-confirmation score policy.
SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION public.field_trip_scan_evidence_is_eligible(
    candidate public.scans
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT candidate.is_biological_subject IS NOT FALSE
        AND candidate.is_tombstoned IS NOT TRUE
        AND pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(
            COALESCE(candidate.user_identification_override, ''), '\s+', ' ', 'g'
        ))) NOT IN ('human', 'humans', 'human being', 'person', 'human breathing', 'human speech', 'human vocalisation', 'human vocalization', 'homo sapiens', 'homo sapien')
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary AS species
            WHERE species.id = COALESCE(candidate.confirmed_species_id, candidate.species_id)
              AND pg_catalog.LOWER(pg_catalog.BTRIM(pg_catalog.REGEXP_REPLACE(
                  COALESCE(species.scientific_name, ''), '\s+', ' ', 'g'
              ))) NOT IN (
                  '', 'unknown', 'unknown subject', 'taxonomy unavailable',
                  'unidentified wildlife', 'no wildlife detected', 'not applicable',
                  'n/a', 'inanimate object', 'human', 'humans', 'human being',
                  'person', 'human breathing', 'human speech', 'human vocalisation',
                  'human vocalization', 'homo sapiens', 'homo sapien'
              )
        )
        AND public.field_trip_scan_identification_is_eligible(
            candidate.ai_confidence_score,
            candidate.inference_tier,
            candidate.confirmed_species_id,
            candidate.user_confirmed_identification
        );
$$;

REVOKE ALL ON FUNCTION public.field_trip_scan_evidence_is_eligible(public.scans)
    FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION public.field_trip_scan_evidence_is_eligible(public.scans) IS
    'Internal resolved non-human subject and confidence policy. Legacy nullable biological flags retain their prior meaning; confirmation never overrides an invalid subject.';

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
    SELECT public.field_trip_scan_evidence_is_eligible(scan)
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
    SELECT public.field_trip_scan_evidence_is_eligible(scan)
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

-- Override-only corrections must invalidate the atomic receipt and enter the trigger.
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
        'user_identification_override', scan.user_identification_override,
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
    user_identification_override,
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
    OR OLD.user_identification_override IS DISTINCT FROM NEW.user_identification_override
    OR OLD.is_biological_subject IS DISTINCT FROM NEW.is_biological_subject
    OR OLD.is_tombstoned IS DISTINCT FROM NEW.is_tombstoned
    OR OLD.timestamp IS DISTINCT FROM NEW.timestamp
)
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();

-- Reuse the normal atomic reconciliation for affected historical credit/receipts.
-- Its new revision key invalidates old cached responses, and its removal helpers
-- reopen progress, remove Event badges, and withdraw invalid publications while
-- retaining selected-goal preferences. Lock in stable scan order.
DO $repair$
DECLARE
    affected RECORD;
BEGIN
    FOR affected IN
        SELECT scan.id, scan.user_id,
            COALESCE(receipt.preferred_user_field_trip_id, preference.user_field_trip_id)
                AS preferred_user_field_trip_id,
            COALESCE(receipt.preferred_item_id, preference.item_id) AS preferred_item_id
        FROM public.scans AS scan
        LEFT JOIN public.field_trip_scan_progress_receipts AS receipt
            ON receipt.scan_id = scan.id AND receipt.user_id = scan.user_id
        LEFT JOIN public.field_trip_scan_goal_preferences AS preference
            ON preference.scan_id = scan.id AND preference.user_id = scan.user_id
        WHERE public.field_trip_scan_evidence_is_eligible(scan) IS NOT TRUE
          AND (
              EXISTS (SELECT 1 FROM public.user_field_trip_item_completions AS c WHERE c.scan_id = scan.id)
              OR EXISTS (SELECT 1 FROM public.field_trip_challenge_item_completions AS c WHERE c.scan_id = scan.id)
              OR EXISTS (SELECT 1 FROM public.field_trip_scan_progress_receipts AS r WHERE r.scan_id = scan.id)
          )
        ORDER BY scan.user_id, scan.id
        FOR UPDATE OF scan
    LOOP
        PERFORM public.apply_field_trip_scan_progress_atomic(
            affected.user_id, affected.id,
            affected.preferred_user_field_trip_id, affected.preferred_item_id
        );
    END LOOP;
END;
$repair$;

-- Preserve valid cached responses when extending their revision shape.
UPDATE public.field_trip_scan_progress_receipts AS receipt
SET scan_revision = receipt.scan_revision || pg_catalog.JSONB_BUILD_OBJECT(
        'user_identification_override', scan.user_identification_override
    ),
    updated_at = pg_catalog.NOW()
FROM public.scans AS scan
WHERE scan.id = receipt.scan_id
  AND scan.user_id = receipt.user_id;

DO $verify$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.scans AS scan
        WHERE public.field_trip_scan_evidence_is_eligible(scan) IS NOT TRUE
          AND (
              EXISTS (SELECT 1 FROM public.user_field_trip_item_completions AS c WHERE c.scan_id = scan.id)
              OR EXISTS (SELECT 1 FROM public.field_trip_challenge_item_completions AS c WHERE c.scan_id = scan.id)
          )
    ) THEN
        RAISE EXCEPTION 'Ineligible subject credit remains after Field Trip repair';
    END IF;
END;
$verify$;

RESET statement_timeout;
RESET lock_timeout;
