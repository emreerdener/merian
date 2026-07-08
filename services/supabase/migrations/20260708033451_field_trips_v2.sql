-- Field Trips v2: guided trip detail, explicit starts, profile pins, and a
-- Field Trips-native recent publication surface.

ALTER TABLE public.field_trip_templates
    ADD COLUMN IF NOT EXISTS cover_image_url TEXT,
    ADD COLUMN IF NOT EXISTS estimated_duration_minutes INTEGER,
    ADD COLUMN IF NOT EXISTS guide_where_to_look TEXT,
    ADD COLUMN IF NOT EXISTS guide_why_it_matters TEXT,
    ADD COLUMN IF NOT EXISTS guide_safety_ethics TEXT;

ALTER TABLE public.field_trip_templates
    DROP CONSTRAINT IF EXISTS field_trip_templates_estimated_duration_minutes_check;
ALTER TABLE public.field_trip_templates
    ADD CONSTRAINT field_trip_templates_estimated_duration_minutes_check
    CHECK (estimated_duration_minutes IS NULL OR estimated_duration_minutes > 0);

ALTER TABLE public.field_trip_checklist_items
    ADD COLUMN IF NOT EXISTS guide_tip TEXT;

ALTER TABLE public.field_trip_publications
    ADD COLUMN IF NOT EXISTS profile_pin_position INTEGER,
    ADD COLUMN IF NOT EXISTS profile_pinned_at TIMESTAMPTZ;

ALTER TABLE public.field_trip_publications
    DROP CONSTRAINT IF EXISTS field_trip_publications_profile_pin_position_check;
ALTER TABLE public.field_trip_publications
    ADD CONSTRAINT field_trip_publications_profile_pin_position_check
    CHECK (profile_pin_position IS NULL OR profile_pin_position BETWEEN 1 AND 3);

CREATE INDEX IF NOT EXISTS idx_field_trip_templates_region_tags_gin
    ON public.field_trip_templates USING GIN(region_tags);
CREATE INDEX IF NOT EXISTS idx_field_trip_templates_habitat_tags_gin
    ON public.field_trip_templates USING GIN(habitat_tags);
CREATE INDEX IF NOT EXISTS idx_field_trip_templates_season_tags_gin
    ON public.field_trip_templates USING GIN(season_tags);
CREATE INDEX IF NOT EXISTS idx_field_trip_publications_recent
    ON public.field_trip_publications(published_at DESC, id DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_publications_user_pinned
    ON public.field_trip_publications(user_id, profile_pin_position)
    WHERE deleted_at IS NULL AND profile_pin_position IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_field_trip_publications_user_pin_position_unique
    ON public.field_trip_publications(user_id, profile_pin_position)
    WHERE deleted_at IS NULL AND profile_pin_position IS NOT NULL;

COMMENT ON COLUMN public.field_trip_templates.cover_image_url IS
    'Optional curated cover image used by Field Trips catalog/detail cards.';
COMMENT ON COLUMN public.field_trip_templates.guide_where_to_look IS
    'Curated pre-trip guidance for where to look. V2 does not generate this with AI.';
COMMENT ON COLUMN public.field_trip_templates.guide_why_it_matters IS
    'Curated educational context for the trip.';
COMMENT ON COLUMN public.field_trip_templates.guide_safety_ethics IS
    'Curated safety and nature-ethics guidance for the trip.';
COMMENT ON COLUMN public.field_trip_checklist_items.guide_tip IS
    'Curated item-level tip shown on Field Trip checklist rows.';
COMMENT ON COLUMN public.field_trip_publications.profile_pin_position IS
    'Optional owner-controlled profile showcase position. Pinned Field Trips are capped at 3.';

UPDATE public.field_trip_templates
SET cover_image_url = seed.cover_image_url,
    estimated_duration_minutes = seed.estimated_duration_minutes,
    guide_where_to_look = seed.guide_where_to_look,
    guide_why_it_matters = seed.guide_why_it_matters,
    guide_safety_ethics = seed.guide_safety_ethics
FROM (
    VALUES
        (
            'backyard_safari',
            'https://images.unsplash.com/photo-1464226184884-fa280b87c399?auto=format&fit=crop&w=1200&q=80',
            30,
            'Walk slowly around yards, sidewalk edges, porch lights, planters, fences, and quiet corners where small animals rest or hunt.',
            'Neighborhood trips help people notice everyday biodiversity and build a habit of looking closely before traveling farther afield.',
            'Stay on public paths or places where you have permission, avoid handling animals, and give webs, nests, and resting insects space.'
        ),
        (
            'park_pollinators',
            'https://images.unsplash.com/photo-1490750967868-88aa4486c946?auto=format&fit=crop&w=1200&q=80',
            45,
            'Start near blooming plants, sunny meadow edges, community gardens, and sheltered patches where insects can land out of wind.',
            'Pollinator trips connect flowers with the insects and birds that move pollen, feed other wildlife, and signal habitat health.',
            'Keep off planted beds, watch for stinging insects without swatting, and avoid disturbing flowers that other visitors and pollinators share.'
        ),
        (
            'forest_edges',
            'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1200&q=80',
            75,
            'Move along trail edges, fallen logs, shaded leaf litter, sunny breaks, and the transition between open path and denser understory.',
            'Forest edges are layered habitats where plants, fungi, arthropods, birds, and mammals overlap in a small walking area.',
            'Stay on marked trails, leave fungi and plants in place, avoid reaching into hidden spaces, and follow park rules for sensitive habitat.'
        )
) AS seed(slug, cover_image_url, estimated_duration_minutes, guide_where_to_look, guide_why_it_matters, guide_safety_ethics)
WHERE field_trip_templates.slug = seed.slug;

WITH item_guidance AS (
    SELECT *
    FROM (VALUES
        ('backyard_safari', 1, 10, 'Look near flowers or sunny leaves where wings can warm in the light.'),
        ('backyard_safari', 1, 20, 'Pause and listen first; birds often reveal themselves by movement or sound.'),
        ('backyard_safari', 1, 30, 'Only scan cats you can observe respectfully from public space or with owner permission.'),
        ('backyard_safari', 1, 40, 'Check web corners, fence rails, shrubs, and shaded wall edges without touching the web.'),
        ('backyard_safari', 2, 10, 'Look for petals, seed heads, and leaf arrangements that make the plant identifiable.'),
        ('backyard_safari', 2, 20, 'Scan fungi from the side and top while leaving the fruiting body undisturbed.'),
        ('backyard_safari', 2, 30, 'Domesticated animals count when they are clearly visible and safely observed.'),
        ('backyard_safari', 2, 40, 'Many insects are easiest to scan when they pause on leaves, bark, or pavement.'),
        ('backyard_safari', 2, 50, 'Look for wildlife that has adapted to people, like squirrels, lizards, or city birds.'),
        ('backyard_safari', 2, 60, 'Moss and lichen often show up on shaded stone, bark, and damp edges.'),
        ('park_pollinators', 1, 10, 'Frame the flower and leaves together when possible; both can help identification.'),
        ('park_pollinators', 1, 20, 'Wait for the insect to settle with wings visible before scanning.'),
        ('park_pollinators', 1, 30, 'Observe calmly from a small distance and avoid blocking the insect flight path.'),
        ('park_pollinators', 1, 40, 'Small flies may hover before landing on open flower centers or leaves.'),
        ('park_pollinators', 2, 10, 'Check flower centers, stems, and leaf undersides for beetles.'),
        ('park_pollinators', 2, 20, 'Spiders often wait near flowers where pollinators visit.'),
        ('park_pollinators', 2, 30, 'Seed pods, berries, or fruiting structures help distinguish plants after bloom.'),
        ('park_pollinators', 2, 40, 'Birds near flowering shrubs may be feeding on insects, nectar, or fruit.'),
        ('park_pollinators', 2, 50, 'Wild plants usually appear in less formal patches and mixed meadow edges.'),
        ('park_pollinators', 2, 60, 'Scan the habitat context: flowers, grasses, and open sunny structure.'),
        ('forest_edges', 1, 10, 'Include bark, leaves, needles, or branching structure when scanning woody plants.'),
        ('forest_edges', 1, 20, 'Check fallen logs and damp shaded soil after rain.'),
        ('forest_edges', 1, 30, 'Look upward and along edge shrubs where birds perch before entering cover.'),
        ('forest_edges', 1, 40, 'Watch sunlit leaves and trunks where insects warm up.'),
        ('forest_edges', 1, 50, 'Scan from a distance and avoid putting fingers near hidden retreats.'),
        ('forest_edges', 1, 60, 'Look for mammals only when observation is safe and does not alter their behavior.'),
        ('forest_edges', 2, 10, 'Moss detail is clearest in even light; include nearby bark or rock context.'),
        ('forest_edges', 2, 20, 'Fern frond shape and underside details are useful if you can capture them safely.'),
        ('forest_edges', 2, 30, 'Caterpillars often sit under leaves or along plant stems.'),
        ('forest_edges', 2, 40, 'Look where small flowers break through leaf litter or trail-edge light.'),
        ('forest_edges', 2, 50, 'Observe amphibians and reptiles without handling, especially near water or damp cover.'),
        ('forest_edges', 2, 60, 'Tracks, scat, or feeding signs should be scanned without moving or collecting them.'),
        ('forest_edges', 2, 70, 'Use the surrounding canopy, understory, and ground layer as habitat clues.'),
        ('forest_edges', 2, 80, 'Native plant candidates are easier to assess with leaves, flowers, and habitat together.')
    ) AS seed(template_slug, level_number, sort_order, guide_tip)
)
UPDATE public.field_trip_checklist_items fci
SET guide_tip = item_guidance.guide_tip
FROM item_guidance
JOIN public.field_trip_templates t
    ON t.slug = item_guidance.template_slug
JOIN public.field_trip_levels fl
    ON fl.template_id = t.id
   AND fl.level_number = item_guidance.level_number
WHERE fci.level_id = fl.id
  AND fci.sort_order = item_guidance.sort_order;

CREATE OR REPLACE FUNCTION public.get_field_trip_catalog(
    self_id UUID,
    user_region TEXT DEFAULT NULL,
    max_limit INTEGER DEFAULT 40
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_is_pro BOOLEAN := FALSE;
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 40), 80));
    catalog_payload JSONB := '[]'::jsonb;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    WITH templates AS (
        SELECT
            t.*,
            (t.is_pro_only = FALSE OR user_is_pro OR t.is_rotating_free = TRUE) AS viewer_has_access,
            CASE
                WHEN user_region IS NOT NULL AND LOWER(user_region) = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 0
                WHEN COALESCE(ARRAY_LENGTH(t.region_tags, 1), 0) = 0
                  OR 'global' = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 1
                ELSE 2
            END AS region_rank,
            CASE
                WHEN t.is_pro_only AND NOT user_is_pro AND NOT t.is_rotating_free THEN 'pro'
                WHEN t.is_rotating_free THEN 'rotating_free'
                ELSE 'free'
            END AS access_kind
        FROM public.field_trip_templates t
        WHERE t.is_active = TRUE
        ORDER BY
            CASE
                WHEN user_region IS NOT NULL AND LOWER(user_region) = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 0
                WHEN COALESCE(ARRAY_LENGTH(t.region_tags, 1), 0) = 0
                  OR 'global' = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 1
                ELSE 2
            END,
            t.sort_order,
            t.title
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'template_id', t.id,
            'slug', t.slug,
            'title', t.title,
            'subtitle', t.subtitle,
            'description', t.description,
            'cover_image_url', t.cover_image_url,
            'estimated_duration_minutes', t.estimated_duration_minutes,
            'guide_where_to_look', t.guide_where_to_look,
            'guide_why_it_matters', t.guide_why_it_matters,
            'guide_safety_ethics', t.guide_safety_ethics,
            'region_tags', t.region_tags,
            'season_tags', t.season_tags,
            'habitat_tags', t.habitat_tags,
            'difficulty', t.difficulty,
            'is_pro_only', t.is_pro_only,
            'is_rotating_free', t.is_rotating_free,
            'viewer_has_access', t.viewer_has_access,
            'access_kind', t.access_kind,
            'active_progress', CASE WHEN uft.id IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
                'user_field_trip_id', uft.id,
                'started_at', uft.started_at,
                'current_level_number', uft.current_level_number,
                'completed_at', uft.completed_at,
                'is_profile_visible', uft.is_profile_visible,
                'completed_count', COALESCE(active_counts.completed_count, 0),
                'target_count', COALESCE(active_counts.target_count, 0)
            ) END,
            'levels', COALESCE(levels.levels, '[]'::jsonb)
        )
        ORDER BY t.region_rank, t.sort_order, t.title
    ), '[]'::jsonb)
    INTO catalog_payload
    FROM templates t
    LEFT JOIN public.user_field_trips uft
        ON uft.template_id = t.id
       AND uft.user_id = self_id
       AND uft.hidden_at IS NULL
    LEFT JOIN LATERAL (
        SELECT
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM public.field_trip_levels fl
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = fci.id
        WHERE fl.template_id = t.id
          AND fl.level_number = COALESCE(uft.current_level_number, 1)
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
                fl.id AS level_id,
                fl.level_number,
                fl.title,
                fl.description,
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'item_id', fci.id,
                        'prompt', fci.prompt,
                        'match_type', fci.match_type,
                        'guide_tip', fci.guide_tip,
                        'is_completed', ufc.id IS NOT NULL,
                        'completed_at', ufc.completed_at,
                        'completed_common_name', ufc.common_name,
                        'completed_scientific_name', ufc.scientific_name
                    )
                    ORDER BY fci.sort_order
                ) AS items
            FROM public.field_trip_levels fl
            JOIN public.field_trip_checklist_items fci
                ON fci.level_id = fl.id
            LEFT JOIN public.user_field_trip_item_completions ufc
                ON ufc.user_field_trip_id = uft.id
               AND ufc.item_id = fci.id
            WHERE fl.template_id = t.id
            GROUP BY fl.id, fl.level_number, fl.title, fl.description
        ) level_rows
    ) levels ON TRUE;

    RETURN catalog_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_template_detail(
    self_id UUID,
    target_template_id UUID DEFAULT NULL,
    target_slug TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_is_pro BOOLEAN := FALSE;
    detail_payload JSONB := NULL;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    SELECT JSONB_BUILD_OBJECT(
        'template_id', t.id,
        'slug', t.slug,
        'title', t.title,
        'subtitle', t.subtitle,
        'description', t.description,
        'cover_image_url', t.cover_image_url,
        'estimated_duration_minutes', t.estimated_duration_minutes,
        'guide_where_to_look', t.guide_where_to_look,
        'guide_why_it_matters', t.guide_why_it_matters,
        'guide_safety_ethics', t.guide_safety_ethics,
        'region_tags', t.region_tags,
        'season_tags', t.season_tags,
        'habitat_tags', t.habitat_tags,
        'difficulty', t.difficulty,
        'is_pro_only', t.is_pro_only,
        'is_rotating_free', t.is_rotating_free,
        'viewer_has_access', t.is_pro_only = FALSE OR user_is_pro OR t.is_rotating_free = TRUE,
        'access_kind', CASE
            WHEN t.is_pro_only AND NOT user_is_pro AND NOT t.is_rotating_free THEN 'pro'
            WHEN t.is_rotating_free THEN 'rotating_free'
            ELSE 'free'
        END,
        'active_progress', CASE WHEN uft.id IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
            'user_field_trip_id', uft.id,
            'started_at', uft.started_at,
            'current_level_number', uft.current_level_number,
            'completed_at', uft.completed_at,
            'is_profile_visible', uft.is_profile_visible,
            'completed_count', COALESCE(active_counts.completed_count, 0),
            'target_count', COALESCE(active_counts.target_count, 0)
        ) END,
        'levels', COALESCE(levels.levels, '[]'::jsonb)
    )
    INTO detail_payload
    FROM public.field_trip_templates t
    LEFT JOIN public.user_field_trips uft
        ON uft.template_id = t.id
       AND uft.user_id = self_id
       AND uft.hidden_at IS NULL
    LEFT JOIN LATERAL (
        SELECT
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM public.field_trip_levels fl
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = fci.id
        WHERE fl.template_id = t.id
          AND fl.level_number = COALESCE(uft.current_level_number, 1)
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
                fl.id AS level_id,
                fl.level_number,
                fl.title,
                fl.description,
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'item_id', fci.id,
                        'prompt', fci.prompt,
                        'match_type', fci.match_type,
                        'guide_tip', fci.guide_tip,
                        'is_completed', ufc.id IS NOT NULL,
                        'completed_at', ufc.completed_at,
                        'completed_common_name', ufc.common_name,
                        'completed_scientific_name', ufc.scientific_name
                    )
                    ORDER BY fci.sort_order
                ) AS items
            FROM public.field_trip_levels fl
            JOIN public.field_trip_checklist_items fci
                ON fci.level_id = fl.id
            LEFT JOIN public.user_field_trip_item_completions ufc
                ON ufc.user_field_trip_id = uft.id
               AND ufc.item_id = fci.id
            WHERE fl.template_id = t.id
            GROUP BY fl.id, fl.level_number, fl.title, fl.description
        ) level_rows
    ) levels ON TRUE
    WHERE t.is_active = TRUE
      AND (
          (target_template_id IS NOT NULL AND t.id = target_template_id)
          OR (target_slug IS NOT NULL AND t.slug = target_slug)
      )
    LIMIT 1;

    RETURN detail_payload;
END;
$$;

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
    user_is_pro BOOLEAN := FALSE;
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

    INSERT INTO public.user_field_trips(user_id, template_id, started_at, current_level_number, is_profile_visible, hidden_at)
    VALUES (self_id, target_template_id, NOW(), 1, TRUE, NULL)
    ON CONFLICT(user_id, template_id) DO UPDATE
    SET hidden_at = NULL,
        is_profile_visible = TRUE,
        updated_at = NOW();

    RETURN public.get_field_trip_template_detail(self_id, target_template_id, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_recent_field_trip_publications(
    self_id UUID,
    user_region TEXT DEFAULT NULL,
    viewer_habitat_tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    max_limit INTEGER DEFAULT 20,
    before_published_at TIMESTAMPTZ DEFAULT NULL,
    before_publication_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 20), 60));
    preferred_count INTEGER := 0;
    has_local_context BOOLEAN := FALSE;
    recent_payload JSONB := '[]'::jsonb;
BEGIN
    has_local_context := (
        user_region IS NOT NULL
        OR COALESCE(ARRAY_LENGTH(viewer_habitat_tags, 1), 0) > 0
    );

    WITH visible_publications AS (
        SELECT ftp.id
        FROM public.field_trip_publications ftp
        JOIN public.field_trip_templates t
            ON t.id = ftp.template_id
        WHERE ftp.deleted_at IS NULL
          AND public.can_view_field_trip_publication(self_id, ftp.id)
          AND (
              before_published_at IS NULL
              OR (ftp.published_at, ftp.id) < (before_published_at, before_publication_id)
          )
          AND (
              (user_region IS NOT NULL AND LOWER(BTRIM(user_region)) = ANY(public.field_trip_lower_text_array(t.region_tags)))
              OR EXISTS (
                  SELECT 1
                  FROM UNNEST(public.field_trip_lower_text_array(viewer_habitat_tags)) AS viewer_tag(tag)
                  WHERE viewer_tag.tag = ANY(public.field_trip_lower_text_array(t.habitat_tags))
              )
          )
    )
    SELECT COUNT(*)::INTEGER
    INTO preferred_count
    FROM visible_publications;

    WITH recent_publications AS (
        SELECT
            ftp.id AS publication_id,
            ftp.title,
            ftp.description,
            ftp.published_at,
            ftp.like_count,
            ftp.comment_count,
            ftp.profile_pin_position,
            t.id AS template_id,
            t.slug,
            t.title AS template_title,
            t.region_tags,
            t.season_tags,
            t.habitat_tags,
            ftp.user_id AS author_user_id,
            u.public_author_name AS author_name,
            u.public_username AS author_username,
            u.public_avatar_url AS author_avatar_url,
            (
                SELECT fpi.hero_image_url
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
                  AND fpi.hero_image_url IS NOT NULL
                ORDER BY fpi.sort_order
                LIMIT 1
            ) AS cover_image_url,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
            ) AS item_count,
            EXISTS (
                SELECT 1
                FROM public.field_trip_publication_likes ftpl
                WHERE ftpl.publication_id = ftp.id
                  AND ftpl.user_id = self_id
            ) AS viewer_has_liked
        FROM public.field_trip_publications ftp
        JOIN public.field_trip_templates t
            ON t.id = ftp.template_id
        JOIN public.users u
            ON u.id = ftp.user_id
        WHERE ftp.deleted_at IS NULL
          AND public.can_view_field_trip_publication(self_id, ftp.id)
          AND (
              before_published_at IS NULL
              OR (ftp.published_at, ftp.id) < (before_published_at, before_publication_id)
          )
          AND (
              has_local_context = FALSE
              OR (
                  (user_region IS NOT NULL AND LOWER(BTRIM(user_region)) = ANY(public.field_trip_lower_text_array(t.region_tags)))
                  OR EXISTS (
                      SELECT 1
                      FROM UNNEST(public.field_trip_lower_text_array(viewer_habitat_tags)) AS viewer_tag(tag)
                      WHERE viewer_tag.tag = ANY(public.field_trip_lower_text_array(t.habitat_tags))
                  )
              )
              OR (
                  preferred_count < resolved_limit
                  AND (
                      'global' = ANY(public.field_trip_lower_text_array(t.region_tags))
                      OR COALESCE(ARRAY_LENGTH(t.region_tags, 1), 0) = 0
                  )
              )
          )
        ORDER BY ftp.published_at DESC, ftp.id DESC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'publication_id', publication_id,
            'template_id', template_id,
            'title', title,
            'description', description,
            'published_at', published_at,
            'like_count', like_count,
            'comment_count', comment_count,
            'slug', slug,
            'template_title', template_title,
            'region_tags', region_tags,
            'season_tags', season_tags,
            'habitat_tags', habitat_tags,
            'cover_image_url', cover_image_url,
            'item_count', item_count,
            'viewer_has_liked', viewer_has_liked,
            'author_user_id', author_user_id,
            'author_name', author_name,
            'author_username', author_username,
            'author_avatar_url', author_avatar_url,
            'is_pinned', profile_pin_position IS NOT NULL,
            'pin_position', profile_pin_position
        )
        ORDER BY published_at DESC, publication_id DESC
    ), '[]'::jsonb)
    INTO recent_payload
    FROM recent_publications;

    RETURN recent_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_profile_summaries(
    self_id UUID,
    target_author_user_id UUID,
    max_limit INTEGER DEFAULT 6
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(0, LEAST(COALESCE(max_limit, 6), 12));
    active_payload JSONB := '[]'::jsonb;
    pinned_payload JSONB := '[]'::jsonb;
    published_payload JSONB := '[]'::jsonb;
BEGIN
    IF NOT public.user_has_visible_field_trip_profile(self_id, target_author_user_id) THEN
        RETURN JSONB_BUILD_OBJECT('active', '[]'::jsonb, 'pinned', '[]'::jsonb, 'published', '[]'::jsonb);
    END IF;

    WITH active_trips AS (
        SELECT
            uft.id AS user_field_trip_id,
            t.id AS template_id,
            t.slug,
            t.title,
            uft.started_at,
            uft.current_level_number,
            uft.completed_at,
            fl.id AS current_level_id,
            fl.title AS current_level_title,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM public.user_field_trips uft
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
        WHERE uft.user_id = target_author_user_id
          AND uft.is_profile_visible = TRUE
          AND uft.hidden_at IS NULL
        GROUP BY uft.id, t.id, t.slug, t.title, uft.started_at, uft.current_level_number, uft.completed_at, fl.id, fl.title
        ORDER BY uft.updated_at DESC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'user_field_trip_id', user_field_trip_id,
            'template_id', template_id,
            'slug', slug,
            'title', title,
            'started_at', started_at,
            'current_level_number', current_level_number,
            'current_level_title', current_level_title,
            'completed_count', completed_count,
            'target_count', target_count,
            'is_complete', completed_at IS NOT NULL
        )
    ), '[]'::jsonb)
    INTO active_payload
    FROM active_trips;

    WITH pinned_trips AS (
        SELECT
            ftp.id AS publication_id,
            ftp.title,
            ftp.description,
            ftp.published_at,
            ftp.like_count,
            ftp.comment_count,
            ftp.profile_pin_position,
            t.slug,
            t.title AS template_title,
            (
                SELECT fpi.hero_image_url
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
                  AND fpi.hero_image_url IS NOT NULL
                ORDER BY fpi.sort_order
                LIMIT 1
            ) AS cover_image_url,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
            ) AS item_count,
            EXISTS (
                SELECT 1
                FROM public.field_trip_publication_likes ftpl
                WHERE ftpl.publication_id = ftp.id
                  AND ftpl.user_id = self_id
            ) AS viewer_has_liked
        FROM public.field_trip_publications ftp
        JOIN public.field_trip_templates t
            ON t.id = ftp.template_id
        WHERE ftp.user_id = target_author_user_id
          AND ftp.deleted_at IS NULL
          AND ftp.profile_pin_position IS NOT NULL
          AND public.can_view_field_trip_publication(self_id, ftp.id)
        ORDER BY ftp.profile_pin_position ASC, ftp.profile_pinned_at DESC
        LIMIT 3
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'publication_id', publication_id,
            'title', title,
            'description', description,
            'published_at', published_at,
            'like_count', like_count,
            'comment_count', comment_count,
            'slug', slug,
            'template_title', template_title,
            'cover_image_url', cover_image_url,
            'item_count', item_count,
            'viewer_has_liked', viewer_has_liked,
            'is_pinned', TRUE,
            'pin_position', profile_pin_position
        )
        ORDER BY profile_pin_position ASC
    ), '[]'::jsonb)
    INTO pinned_payload
    FROM pinned_trips;

    WITH published_trips AS (
        SELECT
            ftp.id AS publication_id,
            ftp.title,
            ftp.description,
            ftp.published_at,
            ftp.like_count,
            ftp.comment_count,
            t.slug,
            t.title AS template_title,
            (
                SELECT fpi.hero_image_url
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
                  AND fpi.hero_image_url IS NOT NULL
                ORDER BY fpi.sort_order
                LIMIT 1
            ) AS cover_image_url,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
            ) AS item_count,
            EXISTS (
                SELECT 1
                FROM public.field_trip_publication_likes ftpl
                WHERE ftpl.publication_id = ftp.id
                  AND ftpl.user_id = self_id
            ) AS viewer_has_liked
        FROM public.field_trip_publications ftp
        JOIN public.field_trip_templates t
            ON t.id = ftp.template_id
        WHERE ftp.user_id = target_author_user_id
          AND ftp.deleted_at IS NULL
          AND ftp.profile_pin_position IS NULL
          AND public.can_view_field_trip_publication(self_id, ftp.id)
        ORDER BY ftp.published_at DESC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'publication_id', publication_id,
            'title', title,
            'description', description,
            'published_at', published_at,
            'like_count', like_count,
            'comment_count', comment_count,
            'slug', slug,
            'template_title', template_title,
            'cover_image_url', cover_image_url,
            'item_count', item_count,
            'viewer_has_liked', viewer_has_liked,
            'is_pinned', FALSE,
            'pin_position', NULL
        )
    ), '[]'::jsonb)
    INTO published_payload
    FROM published_trips;

    RETURN JSONB_BUILD_OBJECT('active', active_payload, 'pinned', pinned_payload, 'published', published_payload);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_field_trip_pinned_publications(
    self_id UUID,
    publication_ids UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    requested_count INTEGER := 0;
BEGIN
    DROP TABLE IF EXISTS pg_temp.field_trip_requested_pins;
    CREATE TEMP TABLE field_trip_requested_pins ON COMMIT DROP AS
    SELECT publication_id, ROW_NUMBER() OVER (ORDER BY first_position)::INTEGER AS pin_position
    FROM (
        SELECT publication_id, MIN(position) AS first_position
        FROM UNNEST(COALESCE(publication_ids, ARRAY[]::UUID[])) WITH ORDINALITY AS requested(publication_id, position)
        GROUP BY publication_id
    ) deduped
    ORDER BY first_position;

    SELECT COUNT(*)::INTEGER
    INTO requested_count
    FROM pg_temp.field_trip_requested_pins;

    IF requested_count > 3 THEN
        RAISE EXCEPTION 'At most 3 Field Trips can be pinned' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_temp.field_trip_requested_pins requested
        LEFT JOIN public.field_trip_publications ftp
            ON ftp.id = requested.publication_id
           AND ftp.user_id = self_id
           AND ftp.deleted_at IS NULL
        WHERE ftp.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Pinned Field Trip publication not found' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.field_trip_publications
    SET profile_pin_position = NULL,
        profile_pinned_at = NULL,
        updated_at = NOW()
    WHERE user_id = self_id
      AND profile_pin_position IS NOT NULL;

    UPDATE public.field_trip_publications ftp
    SET profile_pin_position = requested.pin_position,
        profile_pinned_at = NOW(),
        updated_at = NOW()
    FROM pg_temp.field_trip_requested_pins requested
    WHERE ftp.id = requested.publication_id
      AND ftp.user_id = self_id;

    RETURN public.get_field_trip_profile_summaries(self_id, self_id, 6);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_field_trip(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_recent_field_trip_publications(UUID, TEXT, TEXT[], INTEGER, TIMESTAMPTZ, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_field_trip_pinned_publications(UUID, UUID[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
