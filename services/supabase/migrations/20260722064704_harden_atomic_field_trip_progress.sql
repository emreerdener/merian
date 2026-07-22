-- Field Trip authorization, atomic progress, and ingestion durability hardening.
--
-- All Field Trip RPCs are Edge-owned. No caller may impersonate another user by
-- supplying a self_id directly to PostgREST. Scan progress is applied in one
-- database transaction and its result is retained so a later client retry sees
-- the same unlock payload that the ingestion transaction produced.

CREATE TABLE IF NOT EXISTS public.field_trip_scan_progress_receipts (
    scan_id UUID PRIMARY KEY REFERENCES public.scans(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    scan_revision JSONB NOT NULL,
    preferred_user_field_trip_id UUID,
    preferred_item_id UUID,
    result JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT field_trip_scan_progress_receipts_revision_object
        CHECK (JSONB_TYPEOF(scan_revision) = 'object'),
    CONSTRAINT field_trip_scan_progress_receipts_result_object
        CHECK (JSONB_TYPEOF(result) = 'object'),
    CONSTRAINT field_trip_scan_progress_receipts_preference_pair
        CHECK (
            (preferred_user_field_trip_id IS NULL AND preferred_item_id IS NULL)
            OR
            (preferred_user_field_trip_id IS NOT NULL AND preferred_item_id IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_field_trip_scan_progress_receipts_user_scan
    ON public.field_trip_scan_progress_receipts(user_id, scan_id);

ALTER TABLE public.field_trip_scan_progress_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.field_trip_scan_progress_receipts
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.field_trip_scan_progress_receipts
    TO service_role;

COMMENT ON TABLE public.field_trip_scan_progress_receipts IS
    'Private idempotency receipts for the transactional Field Trip progress mutation. Contains no scan media, coordinates, or notes.';

CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_atomic(
    self_id UUID,
    target_scan_id UUID,
    preferred_user_field_trip_id UUID DEFAULT NULL,
    preferred_item_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    current_scan_revision JSONB;
    existing_receipt public.field_trip_scan_progress_receipts%ROWTYPE;
    previous_achievement JSONB;
    current_achievement JSONB;
    field_trip_updates JSONB;
    challenge_updates JSONB;
    mutation_completed_trip BOOLEAN;
    achievement_newly_unlocked BOOLEAN;
    response JSONB;
BEGIN
    IF (preferred_user_field_trip_id IS NULL) <> (preferred_item_id IS NULL) THEN
        RAISE EXCEPTION 'preferred Field Trip goal must include both identifiers'
            USING ERRCODE = '22023';
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'species_id', scan.species_id,
        'confirmed_species_id', scan.confirmed_species_id,
        'is_biological_subject', scan.is_biological_subject,
        'is_tombstoned', scan.is_tombstoned,
        'timestamp', scan.timestamp
    )
    INTO current_scan_revision
    FROM public.scans scan
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
    FROM public.field_trip_scan_progress_receipts receipt
    WHERE receipt.scan_id = target_scan_id
      AND receipt.user_id = self_id
    FOR UPDATE;

    IF FOUND
       AND existing_receipt.scan_revision = current_scan_revision
       AND (
           preferred_user_field_trip_id IS NULL
           OR (
               existing_receipt.preferred_user_field_trip_id = preferred_user_field_trip_id
               AND existing_receipt.preferred_item_id = preferred_item_id
           )
       ) THEN
        RETURN existing_receipt.result;
    END IF;

    previous_achievement := public.get_first_field_trip_achievement_progress(self_id);

    field_trip_updates := public.apply_field_trip_scan_progress_v2(
        self_id,
        target_scan_id,
        preferred_user_field_trip_id,
        preferred_item_id
    );
    challenge_updates := public.apply_field_trip_challenge_scan_progress(
        self_id,
        target_scan_id
    );

    current_achievement := public.get_first_field_trip_achievement_progress(self_id);
    mutation_completed_trip := EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(
            COALESCE(field_trip_updates, '[]'::JSONB)
            || COALESCE(challenge_updates, '[]'::JSONB)
        ) AS update_row(value)
        WHERE COALESCE((update_row.value ->> 'is_complete')::BOOLEAN, FALSE)
    );
    achievement_newly_unlocked := previous_achievement IS NULL
        AND current_achievement IS NOT NULL
        AND mutation_completed_trip;

    response := JSONB_BUILD_OBJECT(
        'field_trip_updates', COALESCE(field_trip_updates, '[]'::JSONB),
        'challenge_updates', COALESCE(challenge_updates, '[]'::JSONB),
        'first_field_trip_achievement', current_achievement,
        'first_field_trip_achievement_newly_unlocked', achievement_newly_unlocked
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
        preferred_user_field_trip_id,
        preferred_item_id,
        response,
        NOW(),
        NOW()
    )
    ON CONFLICT(scan_id) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        scan_revision = EXCLUDED.scan_revision,
        preferred_user_field_trip_id = EXCLUDED.preferred_user_field_trip_id,
        preferred_item_id = EXCLUDED.preferred_item_id,
        result = EXCLUDED.result,
        processed_at = NOW(),
        updated_at = NOW();

    RETURN response;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_field_trip_scan_progress_atomic(UUID, UUID, UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress_atomic(UUID, UUID, UUID, UUID)
    TO service_role;

-- Apply progress inside the scan insert/correction transaction. The ingestion
-- intent is written before the scan, so a live Capture selection is available
-- to this trigger even if the app terminates before it receives the response.
-- Existing scans without an ingestion receipt are deliberately not replayed.
CREATE OR REPLACE FUNCTION public.apply_ingested_scan_field_trip_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    intent_payload JSONB;
    preferred_payload JSONB;
    preferred_trip_text TEXT;
    preferred_item_text TEXT;
    preferred_trip_id UUID;
    preferred_goal_item_id UUID;
    has_ingestion_intent BOOLEAN := FALSE;
    has_existing_progress BOOLEAN := FALSE;
BEGIN
    SELECT intent.request_payload, TRUE
    INTO intent_payload, has_ingestion_intent
    FROM public.scan_ingestion_intents intent
    WHERE intent.user_id = NEW.user_id
      AND intent.scan_id = NEW.id::TEXT
    ORDER BY intent.updated_at DESC
    LIMIT 1;

    SELECT
        EXISTS (
            SELECT 1
            FROM public.field_trip_scan_progress_receipts receipt
            WHERE receipt.scan_id = NEW.id
              AND receipt.user_id = NEW.user_id
        )
        OR EXISTS (
            SELECT 1
            FROM public.user_field_trip_item_completions completion
            JOIN public.user_field_trips trip
                ON trip.id = completion.user_field_trip_id
               AND trip.user_id = NEW.user_id
            WHERE completion.scan_id = NEW.id
        )
        OR EXISTS (
            SELECT 1
            FROM public.field_trip_challenge_item_completions completion
            JOIN public.field_trip_challenge_participants participation
                ON participation.id = completion.participation_id
               AND participation.user_id = NEW.user_id
            WHERE completion.scan_id = NEW.id
        )
    INTO has_existing_progress;

    has_ingestion_intent := COALESCE(has_ingestion_intent, FALSE);
    IF NOT has_ingestion_intent AND NOT has_existing_progress THEN
        RETURN NEW;
    END IF;

    preferred_payload := COALESCE(
        intent_payload -> 'preferredGoal',
        intent_payload -> 'preferred_goal'
    );
    preferred_trip_text := COALESCE(
        preferred_payload ->> 'userFieldTripId',
        preferred_payload ->> 'user_field_trip_id'
    );
    preferred_item_text := COALESCE(
        preferred_payload ->> 'itemId',
        preferred_payload ->> 'item_id'
    );

    IF preferred_trip_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       AND preferred_item_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
        preferred_trip_id := preferred_trip_text::UUID;
        preferred_goal_item_id := preferred_item_text::UUID;
    END IF;

    PERFORM public.apply_field_trip_scan_progress_atomic(
        NEW.user_id,
        NEW.id,
        preferred_trip_id,
        preferred_goal_item_id
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_ingested_scan_field_trip_progress_insert
    ON public.scans;
CREATE TRIGGER trg_apply_ingested_scan_field_trip_progress_insert
AFTER INSERT ON public.scans
FOR EACH ROW
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();

DROP TRIGGER IF EXISTS trg_apply_ingested_scan_field_trip_progress_update
    ON public.scans;
CREATE TRIGGER trg_apply_ingested_scan_field_trip_progress_update
AFTER UPDATE OF
    species_id,
    confirmed_species_id,
    is_biological_subject,
    is_tombstoned,
    timestamp
ON public.scans
FOR EACH ROW
WHEN (
    OLD.species_id IS DISTINCT FROM NEW.species_id
    OR OLD.confirmed_species_id IS DISTINCT FROM NEW.confirmed_species_id
    OR OLD.is_biological_subject IS DISTINCT FROM NEW.is_biological_subject
    OR OLD.is_tombstoned IS DISTINCT FROM NEW.is_tombstoned
    OR OLD.timestamp IS DISTINCT FROM NEW.timestamp
)
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();

-- Keep profile pin replacement lintable and transactional without depending on
-- a session-local temporary table inside a SECURITY DEFINER routine.
CREATE OR REPLACE FUNCTION public.set_field_trip_pinned_publications(
    self_id UUID,
    publication_ids UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    normalized_publication_ids UUID[] := ARRAY[]::UUID[];
    requested_count INTEGER := 0;
BEGIN
    SELECT COALESCE(
        ARRAY_AGG(deduped.publication_id ORDER BY deduped.first_position),
        ARRAY[]::UUID[]
    )
    INTO normalized_publication_ids
    FROM (
        SELECT requested.publication_id, MIN(requested.position) AS first_position
        FROM UNNEST(
            COALESCE(publication_ids, ARRAY[]::UUID[])
        ) WITH ORDINALITY AS requested(publication_id, position)
        GROUP BY requested.publication_id
    ) deduped;

    requested_count := CARDINALITY(normalized_publication_ids);
    IF requested_count > 3 THEN
        RAISE EXCEPTION 'At most 3 Field Trips can be pinned'
            USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM UNNEST(normalized_publication_ids) AS requested(publication_id)
        LEFT JOIN public.field_trip_publications publication
            ON publication.id = requested.publication_id
           AND publication.user_id = self_id
           AND publication.deleted_at IS NULL
        WHERE publication.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Pinned Field Trip publication not found'
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.field_trip_publications
    SET profile_pin_position = NULL,
        profile_pinned_at = NULL,
        updated_at = NOW()
    WHERE user_id = self_id
      AND profile_pin_position IS NOT NULL;

    UPDATE public.field_trip_publications publication
    SET profile_pin_position = requested.pin_position::INTEGER,
        profile_pinned_at = NOW(),
        updated_at = NOW()
    FROM UNNEST(normalized_publication_ids)
        WITH ORDINALITY AS requested(publication_id, pin_position)
    WHERE publication.id = requested.publication_id
      AND publication.user_id = self_id;

    RETURN public.get_field_trip_profile_summaries(self_id, self_id, 6);
END;
$$;

-- Repair completed-outing publication materialization. The original SELECT
-- accidentally resolved publication_id as a nonexistent source column.
CREATE OR REPLACE FUNCTION public.publish_field_trip(
    self_id UUID,
    target_user_field_trip_id UUID,
    publication_title TEXT DEFAULT NULL,
    publication_description TEXT DEFAULT NULL,
    publication_ai_summary TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    trip_row RECORD;
    created_publication_id UUID;
    resolved_title TEXT;
BEGIN
    SELECT uft.*, t.title AS template_title
    INTO trip_row
    FROM public.user_field_trips uft
    JOIN public.field_trip_templates t ON t.id = uft.template_id
    WHERE uft.id = target_user_field_trip_id
      AND uft.user_id = self_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip not found' USING ERRCODE = 'P0002';
    END IF;
    IF trip_row.completed_at IS NULL THEN
        RAISE EXCEPTION 'Field Trip must be complete before publishing' USING ERRCODE = 'P0001';
    END IF;

    resolved_title := COALESCE(NULLIF(BTRIM(publication_title), ''), trip_row.template_title);

    INSERT INTO public.field_trip_publications(
        user_field_trip_id, user_id, template_id, title, description,
        ai_summary, published_at, deleted_at
    )
    VALUES (
        trip_row.id, self_id, trip_row.template_id, resolved_title,
        NULLIF(BTRIM(publication_description), ''),
        NULLIF(BTRIM(publication_ai_summary), ''), NOW(), NULL
    )
    ON CONFLICT(user_field_trip_id) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description,
        ai_summary = EXCLUDED.ai_summary,
        deleted_at = NULL,
        updated_at = NOW()
    RETURNING id INTO created_publication_id;

    DELETE FROM public.field_trip_publication_items
    WHERE publication_id = created_publication_id;

    INSERT INTO public.field_trip_publication_items(
        publication_id, item_id, scan_id, species_id, common_name,
        scientific_name, hero_image_url, reference_image_url, taxonomy,
        sort_order
    )
    SELECT
        created_publication_id,
        fci.id,
        ufc.scan_id,
        COALESCE(ufc.species_id, COALESCE(s.confirmed_species_id, s.species_id)),
        COALESCE(
            ufc.common_name,
            public.field_trip_species_common_name(sd.common_names, sd.scientific_name, fci.prompt)
        ),
        COALESCE(ufc.scientific_name, sd.scientific_name),
        s.image_storage_urls[1],
        public.public_species_first_reference_image_url(sd.id, sd.reference_image_url),
        JSONB_BUILD_OBJECT(
            'kingdom', sd.kingdom,
            'phylum', sd.phylum,
            'class', sd."class",
            'order', sd."order",
            'family', sd.family,
            'genus', sd.genus
        ),
        (fl.level_number * 1000) + fci.sort_order
    FROM public.user_field_trip_item_completions ufc
    JOIN public.field_trip_checklist_items fci ON fci.id = ufc.item_id
    JOIN public.field_trip_levels fl ON fl.id = fci.level_id
    JOIN public.scans s
        ON s.id = ufc.scan_id
       AND s.user_id = self_id
       AND s.is_tombstoned = FALSE
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(ufc.species_id, COALESCE(s.confirmed_species_id, s.species_id))
    WHERE ufc.user_field_trip_id = trip_row.id
    ORDER BY fl.level_number, fci.sort_order
    ON CONFLICT(publication_id, item_id) DO UPDATE
    SET scan_id = EXCLUDED.scan_id,
        species_id = EXCLUDED.species_id,
        common_name = EXCLUDED.common_name,
        scientific_name = EXCLUDED.scientific_name,
        hero_image_url = EXCLUDED.hero_image_url,
        reference_image_url = EXCLUDED.reference_image_url,
        taxonomy = EXCLUDED.taxonomy,
        sort_order = EXCLUDED.sort_order;

    RETURN JSONB_BUILD_OBJECT('publication_id', created_publication_id);
END;
$$;

-- Every existing Field Trip SECURITY DEFINER routine is Edge-owned. Remove the
-- PostgreSQL default PUBLIC execute grant as well as API-role execute grants.
DO $acl_hardening$
DECLARE
    function_signature REGPROCEDURE;
BEGIN
    FOR function_signature IN
        SELECT procedure.oid::REGPROCEDURE
        FROM pg_proc procedure
        JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
        WHERE namespace.nspname = 'public'
          AND procedure.prokind = 'f'
          AND procedure.prosecdef
          AND (
              procedure.proname ILIKE '%field_trip%'
              OR procedure.proname ILIKE '%challenge%'
          )
    LOOP
        EXECUTE FORMAT(
            'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
            function_signature
        );
        EXECUTE FORMAT(
            'GRANT EXECUTE ON FUNCTION %s TO service_role',
            function_signature
        );
    END LOOP;
END;
$acl_hardening$;

NOTIFY pgrst, 'reload schema';
