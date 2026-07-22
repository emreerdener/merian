-- Park Pollinators originally modeled "Bee or wasp" as all Hymenoptera.
-- Ants are also Hymenoptera, so use an explicit family exclusion and repair
-- any ant-backed progress already credited under the broad rule.

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
        WHEN match_type IN ('taxonomy', 'taxonomy_excluding_family') THEN
            (NULLIF(BTRIM(item_taxonomy_kingdom), '') IS NULL OR LOWER(BTRIM(item_taxonomy_kingdom)) = LOWER(BTRIM(COALESCE(scan_kingdom, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_phylum), '') IS NULL OR LOWER(BTRIM(item_taxonomy_phylum)) = LOWER(BTRIM(COALESCE(scan_phylum, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_class), '') IS NULL OR LOWER(BTRIM(item_taxonomy_class)) = LOWER(BTRIM(COALESCE(scan_class, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_order), '') IS NULL OR LOWER(BTRIM(item_taxonomy_order)) = LOWER(BTRIM(COALESCE(scan_order, ''))))
            AND (
                (
                    match_type = 'taxonomy'
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
                    match_type = 'taxonomy'
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

UPDATE public.field_trip_checklist_items AS item
SET match_type = 'taxonomy_excluding_family',
    taxonomy_family = 'Formicidae'
FROM public.field_trip_levels AS level,
     public.field_trip_templates AS template
WHERE item.level_id = level.id
  AND level.template_id = template.id
  AND template.slug = 'park_pollinators'
  AND level.level_number = 1
  AND item.prompt = 'Bee or wasp';

-- Capture the affected derived rows before deleting them so receipts and
-- completion state can be repaired without replaying unrelated scans.
CREATE TEMP TABLE invalid_bee_wasp_standard_completions
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
JOIN public.field_trip_levels AS level
    ON level.id = item.level_id
JOIN public.field_trip_templates AS template
    ON template.id = level.template_id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
WHERE template.slug = 'park_pollinators'
  AND level.level_number = 1
  AND item.prompt = 'Bee or wasp'
  AND LOWER(BTRIM(COALESCE(species.family, ''))) = 'formicidae';

CREATE TEMP TABLE invalid_bee_wasp_challenge_completions
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
JOIN public.field_trip_levels AS level
    ON level.id = item.level_id
JOIN public.field_trip_templates AS template
    ON template.id = level.template_id
JOIN public.scans AS scan
    ON scan.id = completion.scan_id
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
WHERE template.slug = 'park_pollinators'
  AND level.level_number = 1
  AND item.prompt = 'Bee or wasp'
  AND LOWER(BTRIM(COALESCE(species.family, ''))) = 'formicidae';

DELETE FROM public.user_field_trip_item_completions AS completion
USING invalid_bee_wasp_standard_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_challenge_item_completions AS completion
USING invalid_bee_wasp_challenge_completions AS invalid
WHERE completion.id = invalid.completion_id;

DELETE FROM public.field_trip_scan_goal_preferences AS preference
USING public.field_trip_checklist_items AS item,
      public.field_trip_levels AS level,
      public.field_trip_templates AS template,
      public.scans AS scan,
      public.species_dictionary AS species
WHERE preference.item_id = item.id
  AND item.level_id = level.id
  AND level.template_id = template.id
  AND preference.scan_id = scan.id
  AND species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
  AND template.slug = 'park_pollinators'
  AND level.level_number = 1
  AND item.prompt = 'Bee or wasp'
  AND LOWER(BTRIM(COALESCE(species.family, ''))) = 'formicidae';

DELETE FROM public.field_trip_scan_progress_receipts AS receipt
USING (
    SELECT scan_id, user_id FROM invalid_bee_wasp_standard_completions
    UNION
    SELECT scan_id, user_id FROM invalid_bee_wasp_challenge_completions
) AS invalid
WHERE receipt.scan_id = invalid.scan_id
  AND receipt.user_id = invalid.user_id;

WITH affected_trips AS (
    SELECT DISTINCT user_field_trip_id
    FROM invalid_bee_wasp_standard_completions
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
    FROM invalid_bee_wasp_standard_completions
)
  AND publication.deleted_at IS NULL;

WITH affected_participations AS (
    SELECT DISTINCT participation_id
    FROM invalid_bee_wasp_challenge_completions
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
    FROM invalid_bee_wasp_challenge_completions
);

UPDATE public.field_trip_challenge_entries AS entry
SET deleted_at = COALESCE(entry.deleted_at, NOW()),
    updated_at = NOW()
WHERE entry.participation_id IN (
    SELECT DISTINCT participation_id
    FROM invalid_bee_wasp_challenge_completions
)
  AND entry.deleted_at IS NULL;
