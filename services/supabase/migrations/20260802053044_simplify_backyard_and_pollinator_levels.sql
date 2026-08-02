-- Split the two active starter outings into shorter 2/4/4 progressions while
-- preserving checklist-item identities and every completion still supported by
-- its source scan. The former broad Domesticated animal objective becomes an
-- exact domestic-dog objective, so derived completion artifacts are reconciled
-- in the same transaction as the curated-content change.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

DO $preflight$
BEGIN
    IF (
        SELECT COUNT(*)
        FROM public.field_trip_templates AS template
        WHERE template.slug IN ('backyard_safari', 'park_pollinators')
    ) <> 2 THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration requires both active curated templates';
    END IF;

    IF EXISTS (
        WITH expected(template_slug, prompt) AS (
            VALUES
                ('backyard_safari', 'Butterfly'),
                ('backyard_safari', 'Bird'),
                ('backyard_safari', 'Cat'),
                ('backyard_safari', 'Spider'),
                ('backyard_safari', 'Flowering plant'),
                ('backyard_safari', 'Fungus'),
                ('backyard_safari', 'Domesticated animal'),
                ('backyard_safari', 'Insect'),
                ('backyard_safari', 'Urban wild animal'),
                ('backyard_safari', 'Moss or lichen'),
                ('park_pollinators', 'Flowering plant'),
                ('park_pollinators', 'Butterfly or moth'),
                ('park_pollinators', 'Bee or wasp'),
                ('park_pollinators', 'Fly'),
                ('park_pollinators', 'Beetle'),
                ('park_pollinators', 'Spider'),
                ('park_pollinators', 'Seed or fruiting plant'),
                ('park_pollinators', 'Bird'),
                ('park_pollinators', 'Wild plant'),
                ('park_pollinators', 'Meadow plant')
        ),
        actual AS (
            SELECT template.slug, item.prompt
            FROM public.field_trip_checklist_items AS item
            JOIN public.field_trip_levels AS level
                ON level.id = item.level_id
            JOIN public.field_trip_templates AS template
                ON template.id = level.template_id
            WHERE template.slug IN ('backyard_safari', 'park_pollinators')
        )
        SELECT 1
        FROM (
            (SELECT * FROM expected EXCEPT SELECT * FROM actual)
            UNION ALL
            (SELECT * FROM actual EXCEPT SELECT * FROM expected)
        ) AS mismatch
    ) THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration found unexpected curated objectives';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.field_trip_templates AS template
        LEFT JOIN public.field_trip_levels AS level
            ON level.template_id = template.id
        WHERE template.slug IN ('backyard_safari', 'park_pollinators')
        GROUP BY template.id
        HAVING COUNT(level.id) <> 2
            OR MIN(level.level_number) <> 1
            OR MAX(level.level_number) <> 2
    ) THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration requires the reviewed two-level source state';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.field_trip_checklist_items AS item
        JOIN public.field_trip_levels AS level
            ON level.id = item.level_id
        JOIN public.field_trip_templates AS template
            ON template.id = level.template_id
        WHERE template.slug IN ('backyard_safari', 'park_pollinators')
          AND (item.sort_order < 0 OR item.sort_order >= 1000)
    ) THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration cannot safely stage current sort orders';
    END IF;
END;
$preflight$;

CREATE TEMP TABLE releveled_field_trip_templates
ON COMMIT DROP
AS
SELECT template.id, template.slug
FROM public.field_trip_templates AS template
WHERE template.slug IN ('backyard_safari', 'park_pollinators');

CREATE TEMP TABLE releveled_field_trip_items
ON COMMIT DROP
AS
SELECT
    item.id,
    template.slug AS template_slug,
    item.prompt AS original_prompt
FROM public.field_trip_checklist_items AS item
JOIN public.field_trip_levels AS level
    ON level.id = item.level_id
JOIN releveled_field_trip_templates AS template
    ON template.id = level.template_id;

CREATE TEMP TABLE releveled_user_field_trips
ON COMMIT DROP
AS
SELECT trip.id, trip.user_id
FROM public.user_field_trips AS trip
JOIN releveled_field_trip_templates AS template
    ON template.id = trip.template_id;

CREATE TEMP TABLE releveled_field_trip_challenges
ON COMMIT DROP
AS
SELECT challenge.id
FROM public.field_trip_challenges AS challenge
JOIN releveled_field_trip_templates AS template
    ON template.id = challenge.template_id;

CREATE TEMP TABLE releveled_challenge_participations
ON COMMIT DROP
AS
SELECT participation.id, participation.user_id
FROM public.field_trip_challenge_participants AS participation
JOIN releveled_field_trip_challenges AS challenge
    ON challenge.id = participation.challenge_id;

INSERT INTO public.field_trip_levels(
    template_id,
    level_number,
    title,
    description
)
SELECT
    template.id,
    seed.level_number,
    'Level ' || seed.level_number::TEXT,
    seed.description
FROM releveled_field_trip_templates AS template
JOIN (
    VALUES
        (
            'backyard_safari',
            1,
            'Start with two familiar animals close to home.'
        ),
        (
            'backyard_safari',
            2,
            'Add common neighborhood wildlife and a flowering plant.'
        ),
        (
            'backyard_safari',
            3,
            'Finish with subtler signs of life around the neighborhood.'
        ),
        (
            'park_pollinators',
            1,
            'Start with visible pollinator habitat.'
        ),
        (
            'park_pollinators',
            2,
            'Look for more small visitors around flowers and foliage.'
        ),
        (
            'park_pollinators',
            3,
            'Finish with plants and birds that support a wider pollinator habitat.'
        )
) AS seed(template_slug, level_number, description)
    ON seed.template_slug = template.slug
ON CONFLICT(template_id, level_number) DO UPDATE
SET title = EXCLUDED.title,
    description = EXCLUDED.description;

-- Vacate every final sort-order slot before objectives cross level boundaries.
UPDATE public.field_trip_checklist_items AS item
SET sort_order = item.sort_order + 1000
FROM public.field_trip_levels AS level,
     releveled_field_trip_templates AS template
WHERE item.level_id = level.id
  AND level.template_id = template.id;

WITH target_levels(template_slug, prompt, level_number, sort_order) AS (
    VALUES
        ('backyard_safari', 'Bird', 1, 10),
        ('backyard_safari', 'Domesticated animal', 1, 20),
        ('backyard_safari', 'Butterfly', 2, 10),
        ('backyard_safari', 'Cat', 2, 20),
        ('backyard_safari', 'Spider', 2, 30),
        ('backyard_safari', 'Flowering plant', 2, 40),
        ('backyard_safari', 'Fungus', 3, 10),
        ('backyard_safari', 'Insect', 3, 20),
        ('backyard_safari', 'Urban wild animal', 3, 30),
        ('backyard_safari', 'Moss or lichen', 3, 40),
        ('park_pollinators', 'Flowering plant', 1, 10),
        ('park_pollinators', 'Butterfly or moth', 1, 20),
        ('park_pollinators', 'Bee or wasp', 2, 10),
        ('park_pollinators', 'Fly', 2, 20),
        ('park_pollinators', 'Beetle', 2, 30),
        ('park_pollinators', 'Spider', 2, 40),
        ('park_pollinators', 'Seed or fruiting plant', 3, 10),
        ('park_pollinators', 'Bird', 3, 20),
        ('park_pollinators', 'Wild plant', 3, 30),
        ('park_pollinators', 'Meadow plant', 3, 40)
)
UPDATE public.field_trip_checklist_items AS item
SET level_id = level.id,
    sort_order = target.sort_order
FROM target_levels AS target
JOIN releveled_field_trip_templates AS template
    ON template.slug = target.template_slug
JOIN public.field_trip_levels AS level
    ON level.template_id = template.id
   AND level.level_number = target.level_number
WHERE item.id IN (
        SELECT original.id
        FROM releveled_field_trip_items AS original
        WHERE original.template_slug = target.template_slug
          AND original.original_prompt = target.prompt
    );

UPDATE public.field_trip_checklist_items AS item
SET prompt = 'Dog',
    match_type = 'scientific_name',
    species_id = NULL,
    scientific_name = 'Canis lupus familiaris',
    taxonomy_kingdom = NULL,
    taxonomy_phylum = NULL,
    taxonomy_class = NULL,
    taxonomy_order = NULL,
    taxonomy_family = NULL,
    taxonomy_genus = NULL,
    ecology_type = NULL,
    habitat_tag = NULL,
    semantic_tag = NULL,
    guide_tip = 'Dogs count when they are clearly visible and safely observed.',
    guide_where_to_look =
        'Look for safely visible dogs in permitted yards, paths, windows, and enclosures.',
    guide_best_conditions =
        'Daylight and a calm dog provide the clearest view without changing its behavior.',
    guide_what_to_notice =
        'Capture the whole dog when possible, including coat, body shape, ears, tail, or other distinguishing traits.',
    guide_scan_safely =
        'Observe from public space or with permission, respect barriers, and never lure, corner, feed, or reach toward a dog.'
WHERE item.id IN (
    SELECT original.id
    FROM releveled_field_trip_items AS original
    WHERE original.template_slug = 'backyard_safari'
      AND original.original_prompt = 'Domesticated animal'
);

CREATE TEMP TABLE invalid_dog_standard_completions
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
JOIN public.field_trip_checklist_items AS item
    ON item.id = completion.item_id
JOIN releveled_field_trip_items AS original
    ON original.id = item.id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
WHERE original.template_slug = 'backyard_safari'
  AND original.original_prompt = 'Domesticated animal'
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
    ) IS NOT TRUE;

CREATE TEMP TABLE invalid_dog_challenge_completions
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
JOIN public.field_trip_checklist_items AS item
    ON item.id = completion.item_id
JOIN releveled_field_trip_items AS original
    ON original.id = item.id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
WHERE original.template_slug = 'backyard_safari'
  AND original.original_prompt = 'Domesticated animal'
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
    ) IS NOT TRUE;

DELETE FROM public.user_field_trip_item_completions AS completion
USING invalid_dog_standard_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_challenge_item_completions AS completion
USING invalid_dog_challenge_completions AS invalid
WHERE completion.id = invalid.completion_id;

-- Recompute every affected outing because moving an objective across levels can
-- move progress backward even when every underlying completion remains valid.
WITH level_progress AS (
    SELECT
        trip.id AS user_field_trip_id,
        level.level_number,
        COUNT(item.id)::INTEGER AS target_count,
        COUNT(completion.id)::INTEGER AS completed_count,
        MAX(completion.completed_at) AS latest_completed_at
    FROM releveled_user_field_trips AS affected
    JOIN public.user_field_trips AS trip
        ON trip.id = affected.id
    JOIN public.field_trip_levels AS level
        ON level.template_id = trip.template_id
    JOIN public.field_trip_checklist_items AS item
        ON item.level_id = level.id
    LEFT JOIN public.user_field_trip_item_completions AS completion
        ON completion.user_field_trip_id = trip.id
       AND completion.item_id = item.id
    GROUP BY trip.id, level.level_number
), trip_state AS (
    SELECT
        progress.user_field_trip_id,
        COALESCE(
            MIN(progress.level_number) FILTER (
                WHERE progress.completed_count < progress.target_count
            ),
            MAX(progress.level_number)
        ) AS current_level_number,
        BOOL_AND(progress.completed_count >= progress.target_count) AS is_complete,
        MAX(progress.latest_completed_at) AS latest_completed_at
    FROM level_progress AS progress
    GROUP BY progress.user_field_trip_id
)
UPDATE public.user_field_trips AS trip
SET current_level_number = state.current_level_number,
    completed_at = CASE
        WHEN state.is_complete THEN
            COALESCE(trip.completed_at, state.latest_completed_at, NOW())
        ELSE NULL
    END,
    updated_at = NOW()
FROM trip_state AS state
WHERE trip.id = state.user_field_trip_id;

UPDATE public.field_trip_publications AS publication
SET deleted_at = COALESCE(publication.deleted_at, NOW()),
    updated_at = NOW()
FROM public.user_field_trips AS trip,
     releveled_user_field_trips AS affected
WHERE publication.user_field_trip_id = trip.id
  AND trip.id = affected.id
  AND trip.completed_at IS NULL
  AND publication.deleted_at IS NULL;

WITH level_progress AS (
    SELECT
        participation.id AS participation_id,
        level.level_number,
        COUNT(item.id)::INTEGER AS target_count,
        COUNT(completion.id)::INTEGER AS completed_count,
        MAX(completion.completed_at) AS latest_completed_at
    FROM releveled_challenge_participations AS affected
    JOIN public.field_trip_challenge_participants AS participation
        ON participation.id = affected.id
    JOIN public.field_trip_challenges AS challenge
        ON challenge.id = participation.challenge_id
    JOIN public.field_trip_levels AS level
        ON level.template_id = challenge.template_id
    JOIN public.field_trip_checklist_items AS item
        ON item.level_id = level.id
    LEFT JOIN public.field_trip_challenge_item_completions AS completion
        ON completion.participation_id = participation.id
       AND completion.item_id = item.id
    GROUP BY participation.id, level.level_number
), participation_state AS (
    SELECT
        progress.participation_id,
        COALESCE(
            MIN(progress.level_number) FILTER (
                WHERE progress.completed_count < progress.target_count
            ),
            MAX(progress.level_number)
        ) AS current_level_number,
        BOOL_AND(progress.completed_count >= progress.target_count) AS is_complete,
        MAX(progress.latest_completed_at) AS latest_completed_at
    FROM level_progress AS progress
    GROUP BY progress.participation_id
)
UPDATE public.field_trip_challenge_participants AS participation
SET current_level_number = state.current_level_number,
    completed_at = CASE
        WHEN state.is_complete THEN
            COALESCE(
                participation.completed_at,
                state.latest_completed_at,
                NOW()
            )
        ELSE NULL
    END,
    badge_awarded_at = CASE
        WHEN state.is_complete THEN
            COALESCE(
                participation.badge_awarded_at,
                participation.completed_at,
                state.latest_completed_at,
                NOW()
            )
        ELSE NULL
    END,
    updated_at = NOW()
FROM participation_state AS state
WHERE participation.id = state.participation_id;

DELETE FROM public.field_trip_challenge_badges AS badge
USING public.field_trip_challenge_participants AS participation,
      releveled_challenge_participations AS affected
WHERE badge.participation_id = participation.id
  AND participation.id = affected.id
  AND participation.completed_at IS NULL;

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
    COALESCE(participation.badge_awarded_at, participation.completed_at, NOW()),
    participation.is_profile_visible
FROM public.field_trip_challenge_participants AS participation
JOIN releveled_challenge_participations AS affected
    ON affected.id = participation.id
JOIN public.field_trip_challenges AS challenge
    ON challenge.id = participation.challenge_id
WHERE participation.completed_at IS NOT NULL
  AND participation.badge_awarded_at IS NOT NULL
ON CONFLICT(user_id, challenge_id) DO NOTHING;

UPDATE public.field_trip_challenge_entries AS entry
SET deleted_at = COALESCE(entry.deleted_at, NOW()),
    updated_at = NOW()
FROM public.field_trip_challenge_participants AS participation,
     releveled_challenge_participations AS affected
WHERE entry.participation_id = participation.id
  AND participation.id = affected.id
  AND participation.completed_at IS NULL
  AND entry.deleted_at IS NULL;

-- Stored result snapshots include credited-level counts and unlock state. Drop
-- only receipts tied to the two templates, their Events, their items, or scans
-- whose old broad Dog credit was removed. Persistent goal preferences remain.
DELETE FROM public.field_trip_scan_progress_receipts AS receipt
WHERE receipt.preferred_user_field_trip_id IN (
        SELECT affected.id FROM releveled_user_field_trips AS affected
    )
   OR receipt.preferred_item_id IN (
        SELECT item.id FROM releveled_field_trip_items AS item
    )
   OR EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(
            CASE
                WHEN JSONB_TYPEOF(receipt.result -> 'field_trip_updates') = 'array'
                    THEN receipt.result -> 'field_trip_updates'
                ELSE '[]'::JSONB
            END
        ) AS update_row(value)
        JOIN releveled_field_trip_templates AS template
            ON update_row.value ->> 'template_id' = template.id::TEXT
    )
   OR EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(
            CASE
                WHEN JSONB_TYPEOF(receipt.result -> 'challenge_updates') = 'array'
                    THEN receipt.result -> 'challenge_updates'
                ELSE '[]'::JSONB
            END
        ) AS update_row(value)
        JOIN releveled_field_trip_challenges AS challenge
            ON update_row.value ->> 'challenge_id' = challenge.id::TEXT
    )
   OR EXISTS (
        SELECT 1
        FROM public.user_field_trip_item_completions AS completion
        JOIN releveled_user_field_trips AS affected
            ON affected.id = completion.user_field_trip_id
        WHERE completion.scan_id = receipt.scan_id
          AND affected.user_id = receipt.user_id
    )
   OR EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_item_completions AS completion
        JOIN releveled_challenge_participations AS affected
            ON affected.id = completion.participation_id
        WHERE completion.scan_id = receipt.scan_id
          AND affected.user_id = receipt.user_id
    )
   OR EXISTS (
        SELECT 1
        FROM (
            SELECT invalid.scan_id, invalid.user_id
            FROM invalid_dog_standard_completions AS invalid
            UNION
            SELECT invalid.scan_id, invalid.user_id
            FROM invalid_dog_challenge_completions AS invalid
        ) AS invalid
        WHERE invalid.scan_id = receipt.scan_id
          AND invalid.user_id = receipt.user_id
    );

DO $verify$
BEGIN
    IF EXISTS (
        WITH expected(template_slug, level_number, prompt, sort_order) AS (
            VALUES
                ('backyard_safari', 1, 'Bird', 10),
                ('backyard_safari', 1, 'Dog', 20),
                ('backyard_safari', 2, 'Butterfly', 10),
                ('backyard_safari', 2, 'Cat', 20),
                ('backyard_safari', 2, 'Spider', 30),
                ('backyard_safari', 2, 'Flowering plant', 40),
                ('backyard_safari', 3, 'Fungus', 10),
                ('backyard_safari', 3, 'Insect', 20),
                ('backyard_safari', 3, 'Urban wild animal', 30),
                ('backyard_safari', 3, 'Moss or lichen', 40),
                ('park_pollinators', 1, 'Flowering plant', 10),
                ('park_pollinators', 1, 'Butterfly or moth', 20),
                ('park_pollinators', 2, 'Bee or wasp', 10),
                ('park_pollinators', 2, 'Fly', 20),
                ('park_pollinators', 2, 'Beetle', 30),
                ('park_pollinators', 2, 'Spider', 40),
                ('park_pollinators', 3, 'Seed or fruiting plant', 10),
                ('park_pollinators', 3, 'Bird', 20),
                ('park_pollinators', 3, 'Wild plant', 30),
                ('park_pollinators', 3, 'Meadow plant', 40)
        ), actual AS (
            SELECT
                template.slug,
                level.level_number,
                item.prompt,
                item.sort_order
            FROM public.field_trip_checklist_items AS item
            JOIN public.field_trip_levels AS level
                ON level.id = item.level_id
            JOIN releveled_field_trip_templates AS template
                ON template.id = level.template_id
        )
        SELECT 1
        FROM (
            (SELECT * FROM expected EXCEPT SELECT * FROM actual)
            UNION ALL
            (SELECT * FROM actual EXCEPT SELECT * FROM expected)
        ) AS mismatch
    ) THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration produced an unexpected objective map';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.field_trip_checklist_items AS item
        JOIN releveled_field_trip_items AS original
            ON original.id = item.id
    ) <> 20 THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration failed to preserve checklist identities';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.field_trip_checklist_items AS item
        JOIN public.field_trip_levels AS level
            ON level.id = item.level_id
        JOIN releveled_field_trip_templates AS template
            ON template.id = level.template_id
        WHERE template.slug = 'backyard_safari'
          AND item.prompt = 'Dog'
          AND item.match_type = 'scientific_name'
          AND item.scientific_name = 'Canis lupus familiaris'
          AND item.species_id IS NULL
          AND item.taxonomy_kingdom IS NULL
          AND item.taxonomy_phylum IS NULL
          AND item.taxonomy_class IS NULL
          AND item.taxonomy_order IS NULL
          AND item.taxonomy_family IS NULL
          AND item.taxonomy_genus IS NULL
          AND item.ecology_type IS NULL
          AND item.habitat_tag IS NULL
          AND item.semantic_tag IS NULL
    ) <> 1 THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration failed to install the exact Dog matcher';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_field_trip_item_completions AS completion
        JOIN public.field_trip_checklist_items AS item
            ON item.id = completion.item_id
        JOIN public.scans AS scan
            ON scan.id = completion.scan_id
        LEFT JOIN public.species_dictionary AS species
            ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
        WHERE item.id IN (
                SELECT original.id
                FROM releveled_field_trip_items AS original
                WHERE original.template_slug = 'backyard_safari'
                  AND original.original_prompt = 'Domesticated animal'
            )
          AND LOWER(BTRIM(COALESCE(species.scientific_name, ''))) <>
              'canis lupus familiaris'
    ) OR EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_item_completions AS completion
        JOIN public.field_trip_checklist_items AS item
            ON item.id = completion.item_id
        JOIN public.scans AS scan
            ON scan.id = completion.scan_id
        LEFT JOIN public.species_dictionary AS species
            ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
        WHERE item.id IN (
                SELECT original.id
                FROM releveled_field_trip_items AS original
                WHERE original.template_slug = 'backyard_safari'
                  AND original.original_prompt = 'Domesticated animal'
            )
          AND LOWER(BTRIM(COALESCE(species.scientific_name, ''))) <>
              'canis lupus familiaris'
    ) THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration retained non-Dog completion credit';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.field_trip_publications AS publication
        JOIN public.user_field_trips AS trip
            ON trip.id = publication.user_field_trip_id
        JOIN releveled_user_field_trips AS affected
            ON affected.id = trip.id
        WHERE trip.completed_at IS NULL
          AND publication.deleted_at IS NULL
    ) OR EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_badges AS badge
        JOIN public.field_trip_challenge_participants AS participation
            ON participation.id = badge.participation_id
        JOIN releveled_challenge_participations AS affected
            ON affected.id = participation.id
        WHERE participation.completed_at IS NULL
    ) OR EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_entries AS entry
        JOIN public.field_trip_challenge_participants AS participation
            ON participation.id = entry.participation_id
        JOIN releveled_challenge_participations AS affected
            ON affected.id = participation.id
        WHERE participation.completed_at IS NULL
          AND entry.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION
            'Field trip 2/4/4 migration retained reopened completion artifacts';
    END IF;
END;
$verify$;

RESET statement_timeout;
RESET lock_timeout;
