-- Several curated Field Trip objectives were narrower than their matching
-- rules. Taxonomy columns stored beside ecology and semantic rules were
-- ignored, broad Arachnida rules accepted non-spiders, and two contextual
-- prompts described "near flowers" evidence that is not present in the saved
-- scan contract. Add an explicit conjunctive matcher, align active objective
-- copy with verifiable scan data, and remove any progress credited by the old
-- broad rules.

ALTER TABLE public.field_trip_checklist_items
    DROP CONSTRAINT IF EXISTS field_trip_checklist_items_match_type_check;

ALTER TABLE public.field_trip_checklist_items
    ADD CONSTRAINT field_trip_checklist_items_match_type_check
    CHECK (
        match_type IN (
            'species',
            'scientific_name',
            'taxonomy',
            'taxonomy_excluding_family',
            'taxonomy_and_signal',
            'ecology',
            'habitat',
            'semantic_tag'
        )
    );

CREATE OR REPLACE FUNCTION public.field_trip_item_matches_scan(
    match_type TEXT,
    item_species_id UUID,
    item_scientific_name TEXT,
    item_taxonomy_kingdom TEXT,
    item_taxonomy_phylum TEXT,
    item_taxonomy_class TEXT,
    item_taxonomy_order TEXT,
    item_taxonomy_family TEXT,
    item_taxonomy_genus TEXT,
    item_ecology_type TEXT,
    item_habitat_tag TEXT,
    item_semantic_tag TEXT,
    scan_species_id UUID,
    scan_scientific_name TEXT,
    scan_common_names JSONB,
    scan_kingdom TEXT,
    scan_phylum TEXT,
    scan_class TEXT,
    scan_order TEXT,
    scan_family TEXT,
    scan_genus TEXT,
    scan_ecology_type TEXT,
    scan_habitat_description TEXT,
    scan_group_tags TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN match_type = 'species' THEN
            item_species_id IS NOT NULL AND item_species_id = scan_species_id
        WHEN match_type = 'scientific_name' THEN
            NULLIF(BTRIM(item_scientific_name), '') IS NOT NULL
            AND LOWER(BTRIM(item_scientific_name)) = LOWER(BTRIM(COALESCE(scan_scientific_name, '')))
        WHEN match_type IN (
            'taxonomy',
            'taxonomy_excluding_family',
            'taxonomy_and_signal'
        ) THEN
            (NULLIF(BTRIM(item_taxonomy_kingdom), '') IS NULL OR LOWER(BTRIM(item_taxonomy_kingdom)) = LOWER(BTRIM(COALESCE(scan_kingdom, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_phylum), '') IS NULL OR LOWER(BTRIM(item_taxonomy_phylum)) = LOWER(BTRIM(COALESCE(scan_phylum, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_class), '') IS NULL OR LOWER(BTRIM(item_taxonomy_class)) = LOWER(BTRIM(COALESCE(scan_class, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_order), '') IS NULL OR LOWER(BTRIM(item_taxonomy_order)) = LOWER(BTRIM(COALESCE(scan_order, ''))))
            AND (
                (
                    match_type IN ('taxonomy', 'taxonomy_and_signal')
                    AND (
                        NULLIF(BTRIM(item_taxonomy_family), '') IS NULL
                        OR LOWER(BTRIM(item_taxonomy_family)) = LOWER(BTRIM(COALESCE(scan_family, '')))
                    )
                )
                OR (
                    match_type = 'taxonomy_excluding_family'
                    AND NULLIF(BTRIM(item_taxonomy_family), '') IS NOT NULL
                    AND NULLIF(BTRIM(scan_family), '') IS NOT NULL
                    AND LOWER(BTRIM(item_taxonomy_family)) <> LOWER(BTRIM(scan_family))
                )
            )
            AND (NULLIF(BTRIM(item_taxonomy_genus), '') IS NULL OR LOWER(BTRIM(item_taxonomy_genus)) = LOWER(BTRIM(COALESCE(scan_genus, ''))))
            AND (
                (
                    match_type IN ('taxonomy', 'taxonomy_and_signal')
                    AND (
                        NULLIF(BTRIM(item_taxonomy_kingdom), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_phylum), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_class), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_order), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_family), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_genus), '') IS NOT NULL
                    )
                )
                OR (
                    match_type = 'taxonomy_excluding_family'
                    AND NULLIF(BTRIM(item_taxonomy_family), '') IS NOT NULL
                    AND (
                        NULLIF(BTRIM(item_taxonomy_kingdom), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_phylum), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_class), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_order), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_taxonomy_genus), '') IS NOT NULL
                    )
                )
            )
            AND (
                match_type <> 'taxonomy_and_signal'
                OR (
                    (
                        NULLIF(BTRIM(item_ecology_type), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_habitat_tag), '') IS NOT NULL
                        OR NULLIF(BTRIM(item_semantic_tag), '') IS NOT NULL
                    )
                    AND (
                        NULLIF(BTRIM(item_ecology_type), '') IS NULL
                        OR LOWER(BTRIM(item_ecology_type)) = LOWER(BTRIM(COALESCE(scan_ecology_type, '')))
                    )
                    AND (
                        NULLIF(BTRIM(item_habitat_tag), '') IS NULL
                        OR LOWER(BTRIM(item_habitat_tag)) = ANY(public.field_trip_lower_text_array(scan_group_tags))
                        OR (
                            ' ' || REGEXP_REPLACE(
                                LOWER(COALESCE(scan_habitat_description, '')),
                                '[^[:alnum:]]+',
                                ' ',
                                'g'
                            ) || ' '
                        ) LIKE '% ' || LOWER(BTRIM(item_habitat_tag)) || ' %'
                    )
                    AND (
                        NULLIF(BTRIM(item_semantic_tag), '') IS NULL
                        OR EXISTS (
                            SELECT 1
                            FROM UNNEST(
                                STRING_TO_ARRAY(LOWER(item_semantic_tag), '|')
                            ) AS required_semantic(value)
                            WHERE NULLIF(BTRIM(required_semantic.value), '') IS NOT NULL
                              AND (
                                  BTRIM(required_semantic.value) = ANY(public.field_trip_lower_text_array(scan_group_tags))
                                  OR BTRIM(required_semantic.value) = LOWER(BTRIM(COALESCE(scan_scientific_name, '')))
                                  OR BTRIM(required_semantic.value) = LOWER(BTRIM(COALESCE(scan_common_names->>'en', '')))
                              )
                        )
                    )
                )
            )
        WHEN match_type = 'ecology' THEN
            NULLIF(BTRIM(item_ecology_type), '') IS NOT NULL
            AND LOWER(BTRIM(item_ecology_type)) = LOWER(BTRIM(COALESCE(scan_ecology_type, '')))
        WHEN match_type = 'habitat' THEN
            NULLIF(BTRIM(item_habitat_tag), '') IS NOT NULL
            AND (
                LOWER(COALESCE(scan_habitat_description, '')) LIKE '%' || LOWER(BTRIM(item_habitat_tag)) || '%'
                OR LOWER(BTRIM(item_habitat_tag)) = ANY(public.field_trip_lower_text_array(scan_group_tags))
            )
        WHEN match_type = 'semantic_tag' THEN
            NULLIF(BTRIM(item_semantic_tag), '') IS NOT NULL
            AND (
                LOWER(BTRIM(item_semantic_tag)) = ANY(public.field_trip_lower_text_array(scan_group_tags))
                OR LOWER(BTRIM(item_semantic_tag)) = LOWER(BTRIM(COALESCE(scan_scientific_name, '')))
                OR LOWER(BTRIM(item_semantic_tag)) = LOWER(BTRIM(COALESCE(scan_common_names->>'en', '')))
            )
        ELSE FALSE
    END;
$$;

REVOKE ALL ON FUNCTION public.field_trip_item_matches_scan(
    TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    UUID, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[]
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.field_trip_item_matches_scan(
    TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    UUID, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[]
) TO service_role;

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
        WHEN 'taxonomy_excluding_family' THEN CASE
            WHEN NULLIF(BTRIM(taxonomy_genus), '') IS NOT NULL THEN 30
            WHEN NULLIF(BTRIM(taxonomy_order), '') IS NOT NULL THEN 32
            WHEN NULLIF(BTRIM(taxonomy_class), '') IS NOT NULL THEN 33
            WHEN NULLIF(BTRIM(taxonomy_phylum), '') IS NOT NULL THEN 34
            WHEN NULLIF(BTRIM(taxonomy_kingdom), '') IS NOT NULL THEN 35
            ELSE 39
        END
        WHEN 'taxonomy_and_signal' THEN CASE
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

REVOKE ALL ON FUNCTION public.field_trip_checklist_match_rank(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.field_trip_checklist_match_rank(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) TO service_role;

-- Preserve the exact item set so the repair below only evaluates objectives
-- whose criteria or user-facing meaning changed in this migration.
CREATE TEMP TABLE tightened_field_trip_items
AS
SELECT item.id
FROM public.field_trip_checklist_items AS item
JOIN public.field_trip_levels AS level
    ON level.id = item.level_id
JOIN public.field_trip_templates AS template
    ON template.id = level.template_id
WHERE (
    template.slug = 'backyard_safari'
    AND item.prompt IN (
        'Butterfly',
        'Spider',
        'Flowering plant',
        'Domesticated animal',
        'Urban wild animal'
    )
) OR (
    template.slug = 'park_pollinators'
    AND item.prompt IN (
        'Flowering plant',
        'Bee or wasp',
        'Spider near flowers',
        'Seed or fruiting plant',
        'Bird near flowers',
        'Wild plant',
        'Pollinator habitat'
    )
);

UPDATE public.field_trip_checklist_items AS item
SET match_type = CASE item.prompt
        WHEN 'Spider' THEN 'taxonomy'
        ELSE 'taxonomy_and_signal'
    END,
    taxonomy_order = CASE item.prompt
        WHEN 'Spider' THEN 'Araneae'
        ELSE item.taxonomy_order
    END,
    taxonomy_kingdom = CASE item.prompt
        WHEN 'Flowering plant' THEN 'Plantae'
        WHEN 'Domesticated animal' THEN 'Animalia'
        WHEN 'Urban wild animal' THEN 'Animalia'
        ELSE item.taxonomy_kingdom
    END,
    semantic_tag = CASE item.prompt
        WHEN 'Butterfly' THEN 'butterfly'
        WHEN 'Flowering plant' THEN 'flower'
        ELSE item.semantic_tag
    END
FROM public.field_trip_levels AS level,
     public.field_trip_templates AS template
WHERE item.level_id = level.id
  AND level.template_id = template.id
  AND template.slug = 'backyard_safari'
  AND item.prompt IN (
      'Butterfly',
      'Spider',
      'Flowering plant',
      'Domesticated animal',
      'Urban wild animal'
  );

UPDATE public.field_trip_checklist_items AS item
SET prompt = CASE item.prompt
        WHEN 'Spider near flowers' THEN 'Spider'
        WHEN 'Bird near flowers' THEN 'Bird'
        WHEN 'Pollinator habitat' THEN 'Meadow plant'
        ELSE item.prompt
    END,
    match_type = CASE item.prompt
        WHEN 'Spider near flowers' THEN 'taxonomy'
        WHEN 'Bird near flowers' THEN 'taxonomy'
        ELSE 'taxonomy_and_signal'
    END,
    taxonomy_kingdom = CASE item.prompt
        WHEN 'Flowering plant' THEN 'Plantae'
        WHEN 'Seed or fruiting plant' THEN 'Plantae'
        WHEN 'Wild plant' THEN 'Plantae'
        WHEN 'Pollinator habitat' THEN 'Plantae'
        ELSE item.taxonomy_kingdom
    END,
    taxonomy_order = CASE item.prompt
        WHEN 'Spider near flowers' THEN 'Araneae'
        ELSE item.taxonomy_order
    END,
    taxonomy_family = CASE item.prompt
        WHEN 'Bee or wasp' THEN NULL
        ELSE item.taxonomy_family
    END,
    ecology_type = CASE item.prompt
        WHEN 'Wild plant' THEN 'wild'
        ELSE item.ecology_type
    END,
    habitat_tag = CASE item.prompt
        WHEN 'Pollinator habitat' THEN 'meadow'
        ELSE item.habitat_tag
    END,
    semantic_tag = CASE item.prompt
        WHEN 'Flowering plant' THEN 'flower'
        WHEN 'Bee or wasp' THEN 'bee|wasp'
        WHEN 'Seed or fruiting plant' THEN 'fruit'
        WHEN 'Wild plant' THEN NULL
        WHEN 'Pollinator habitat' THEN NULL
        ELSE item.semantic_tag
    END,
    guide_where_to_look = CASE item.prompt
        WHEN 'Pollinator habitat' THEN
            'Look along meadow edges, unmown patches, and sunny open areas for plants growing naturally among grasses and flowers.'
        ELSE item.guide_where_to_look
    END,
    guide_best_conditions = CASE item.prompt
        WHEN 'Pollinator habitat' THEN
            'Even daylight and low wind make leaves, stems, flowers, and seed heads easier to photograph.'
        ELSE item.guide_best_conditions
    END,
    guide_what_to_notice = CASE item.prompt
        WHEN 'Pollinator habitat' THEN
            'Include the plant''s growth form, leaves, stem, and any flowers or seed structures, plus a little meadow context.'
        ELSE item.guide_what_to_notice
    END,
    guide_scan_safely = CASE item.prompt
        WHEN 'Pollinator habitat' THEN
            'Keep the plant rooted, stay on paths or durable ground, and avoid trampling the surrounding patch.'
        ELSE item.guide_scan_safely
    END
FROM public.field_trip_levels AS level,
     public.field_trip_templates AS template
WHERE item.level_id = level.id
  AND level.template_id = template.id
  AND template.slug = 'park_pollinators'
  AND item.prompt IN (
      'Flowering plant',
      'Bee or wasp',
      'Spider near flowers',
      'Seed or fruiting plant',
      'Bird near flowers',
      'Wild plant',
      'Pollinator habitat'
  );

CREATE TEMP TABLE invalid_tightened_standard_completions
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
JOIN tightened_field_trip_items AS tightened
    ON tightened.id = item.id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
WHERE public.field_trip_item_matches_scan(
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

CREATE TEMP TABLE invalid_tightened_challenge_completions
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
JOIN tightened_field_trip_items AS tightened
    ON tightened.id = item.id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
WHERE public.field_trip_item_matches_scan(
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
USING invalid_tightened_standard_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_challenge_item_completions AS completion
USING invalid_tightened_challenge_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_scan_goal_preferences AS preference
USING public.field_trip_checklist_items AS item,
      tightened_field_trip_items AS tightened,
      public.scans AS scan,
      public.species_dictionary AS species
WHERE preference.item_id = item.id
  AND tightened.id = item.id
  AND preference.scan_id = scan.id
  AND species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
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
      species.id,
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

DELETE FROM public.field_trip_scan_progress_receipts AS receipt
USING (
    SELECT scan_id, user_id FROM invalid_tightened_standard_completions
    UNION
    SELECT scan_id, user_id FROM invalid_tightened_challenge_completions
) AS invalid
WHERE receipt.scan_id = invalid.scan_id
  AND receipt.user_id = invalid.user_id;

WITH affected_trips AS (
    SELECT DISTINCT user_field_trip_id
    FROM invalid_tightened_standard_completions
), earliest_incomplete AS (
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
    FROM invalid_tightened_standard_completions
)
  AND publication.deleted_at IS NULL;

WITH affected_participations AS (
    SELECT DISTINCT participation_id
    FROM invalid_tightened_challenge_completions
), earliest_incomplete AS (
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
    FROM invalid_tightened_challenge_completions
);

UPDATE public.field_trip_challenge_entries AS entry
SET deleted_at = COALESCE(entry.deleted_at, NOW()),
    updated_at = NOW()
WHERE entry.participation_id IN (
    SELECT DISTINCT participation_id
    FROM invalid_tightened_challenge_completions
)
  AND entry.deleted_at IS NULL;
