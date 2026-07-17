-- Add reviewed, structured objective guidance for curated Outings. The legacy
-- guide_tip remains available so older clients and unexpanded content continue
-- to render without a coordinated rollout.

ALTER TABLE public.field_trip_checklist_items
    ADD COLUMN IF NOT EXISTS guide_where_to_look TEXT,
    ADD COLUMN IF NOT EXISTS guide_best_conditions TEXT,
    ADD COLUMN IF NOT EXISTS guide_what_to_notice TEXT,
    ADD COLUMN IF NOT EXISTS guide_scan_safely TEXT;

COMMENT ON COLUMN public.field_trip_checklist_items.guide_where_to_look IS
    'Reviewed microhabitat guidance for finding this Outing objective.';
COMMENT ON COLUMN public.field_trip_checklist_items.guide_best_conditions IS
    'Reviewed timing, weather, light, or seasonal guidance for this objective.';
COMMENT ON COLUMN public.field_trip_checklist_items.guide_what_to_notice IS
    'Reviewed visual or behavioral cues that help a user recognize this objective.';
COMMENT ON COLUMN public.field_trip_checklist_items.guide_scan_safely IS
    'Reviewed scan-framing, safety, and low-disturbance guidance for this objective.';

WITH objective_guidance AS (
    SELECT *
    FROM (VALUES
        (
            'backyard_safari', 1, 10,
            'Check sunny flowers, broad leaves, garden edges, and warm path borders where butterflies can land.',
            'Warm, bright, calm periods are usually easiest, especially from late morning through afternoon.',
            'Watch for slow wing opening, basking, or repeated visits to the same cluster of flowers.',
            'Wait for a landing, keep the wings and nearby plant in frame, and avoid touching or blocking the insect.'
        ),
        (
            'backyard_safari', 1, 20,
            'Scan shrubs, fences, feeders, utility lines, and the open edges of tree canopies.',
            'Early morning and late afternoon are often active; pause quietly before deciding no birds are present.',
            'Listen for calls and look for movement, silhouette, beak shape, tail length, and strong color patches.',
            'Use zoom from a respectful distance, steady the phone, and never approach nests or flush a resting bird.'
        ),
        (
            'backyard_safari', 1, 30,
            'Look on porches, paths, windowsills, or yards only where you have permission to observe.',
            'Quiet daylight makes coat pattern and body shape easier to capture without startling the animal.',
            'Notice coat color, striping, face shape, ears, tail, and other features visible from your position.',
            'Photograph from public space or with owner permission, and do not call, feed, corner, or follow the cat.'
        ),
        (
            'backyard_safari', 1, 40,
            'Check web corners, fence rails, shrubs, porch lights, and shaded wall edges.',
            'Still mornings can reveal dew on webs; evenings often bring spiders near lights and active insects.',
            'Look for body proportions, leg arrangement, markings, and the shape or placement of any web.',
            'Keep hands away, photograph without touching the web, and use an angled view if glare hides detail.'
        ),
        (
            'backyard_safari', 2, 10,
            'Look in gardens, planters, lawn edges, sidewalk cracks, and other places with visible blooms or seed heads.',
            'Even daylight with little wind helps flowers and leaves stay sharp; blooming seasons vary by plant.',
            'Include flower shape, petal count, leaf arrangement, stem, and any buds, fruit, or seed structures.',
            'Leave the plant rooted, frame several identifying parts when possible, and stay out of planted beds.'
        ),
        (
            'backyard_safari', 2, 20,
            'Search damp soil, mulch, shaded lawns, decaying wood, and the bases of trees after moisture.',
            'Fungi are often easier to find after rain or during humid weather before exposed caps dry out.',
            'Notice cap shape, color, gills or pores, stem, clustering, and the surface the fungus grows from.',
            'Do not taste or handle it; photograph the side, top, and habitat without moving the fruiting body.'
        ),
        (
            'backyard_safari', 2, 30,
            'Look for safely visible pets or managed animals in permitted yards, paths, windows, and enclosures.',
            'Daylight and a calm animal provide the clearest view without changing its behavior.',
            'Capture the whole animal when possible, including coat, body shape, ears, tail, or other distinguishing traits.',
            'Observe from public space or with permission, respect barriers, and never lure or reach toward an animal.'
        ),
        (
            'backyard_safari', 2, 40,
            'Inspect flowers, leaves, bark, pavement, porch lights, and sheltered corners where insects pause.',
            'Warm calm weather is often active, while cool mornings may keep insects still long enough to photograph.',
            'Look for the number and shape of wings, antennae, legs, body segments, color, and surface markings.',
            'Wait for the insect to settle, avoid swatting or handling it, and keep enough habitat in frame for context.'
        ),
        (
            'backyard_safari', 2, 50,
            'Watch trees, roofs, fences, lawns, drainage edges, and quiet spaces where wildlife moves between cover.',
            'Dawn, dusk, and calm periods after human activity often reveal neighborhood wildlife.',
            'Notice movement, tracks, feeding behavior, body shape, tail, and how the animal uses nearby structures.',
            'Use distance and zoom, never chase or feed wildlife, and leave young animals and shelters undisturbed.'
        ),
        (
            'backyard_safari', 2, 60,
            'Check shaded bark, stones, walls, soil, and damp edges where low growth forms patches or crusts.',
            'Soft overcast light or recent moisture can reveal texture and color without harsh glare.',
            'Look for tiny leaves, branching cushions, flat crusts, lobes, and the surface the patch is attached to.',
            'Photograph close and wide views without scraping the surface or removing material.'
        ),
        (
            'park_pollinators', 1, 10,
            'Start in sunny beds, meadow edges, path borders, and open patches with fresh blooms.',
            'Bright calm periods make flowers easier to photograph; bloom timing changes through the season.',
            'Notice flower shape, color, petal arrangement, leaves, stems, and whether several species grow together.',
            'Stay on paths, leave blooms attached, and include both flowers and leaves in a steady frame.'
        ),
        (
            'park_pollinators', 1, 20,
            'Watch flowering patches, sunny leaves, puddling areas, and sheltered edges out of strong wind.',
            'Warm sunny periods are usually most active, while cool mornings may reveal resting individuals.',
            'Look for wing posture, antennae, body shape, markings, and repeated visits to flowers or host plants.',
            'Wait for a landing, use zoom, keep wings visible when possible, and never touch or net the insect.'
        ),
        (
            'park_pollinators', 1, 30,
            'Focus on flowering plants, bare soil, hollow stems, and sunny edges where bees or wasps feed and nest.',
            'Warm calm weather brings more flight activity; cooler periods can make individuals easier to observe.',
            'Notice body hair, waist shape, antennae, wing position, pollen loads, and the flower being visited.',
            'Keep a comfortable distance, do not block flight paths or disturb nests, and wait for the insect to settle.'
        ),
        (
            'park_pollinators', 1, 40,
            'Check open flower centers, leaves, damp ground, and sunny airspace where small flies hover and land.',
            'Bright calm conditions make hovering and flower visits easier to follow.',
            'Look for very large eyes, short antennae, one visible pair of wings, hovering, and fly-like body shape.',
            'Photograph a settled fly when possible, avoid chasing it through vegetation, and include its landing surface.'
        ),
        (
            'park_pollinators', 2, 10,
            'Inspect flower centers, stems, leaf surfaces, bark, and fallen plant material.',
            'Warm daylight is often productive; some beetles remain tucked into flowers during cooler periods.',
            'Notice hardened wing covers, antennae, body shape, color, and the plant or surface being used.',
            'Use a close view without picking up the beetle or shaking the flower, and keep habitat context in frame.'
        ),
        (
            'park_pollinators', 2, 20,
            'Look among flower clusters, under petals and leaves, and along stems where spiders wait for visiting insects.',
            'Calm daylight makes silk, posture, and camouflage easier to see before wind moves the plant.',
            'Notice leg posture, body shape, color matching, web strands, and the spider position relative to flowers.',
            'Do not touch the spider or web; steady the phone nearby and avoid bending the supporting plant.'
        ),
        (
            'park_pollinators', 2, 30,
            'Search meadow edges and garden beds for pods, berries, cones, dry flower heads, or other fruiting structures.',
            'Late bloom and post-bloom periods are productive, but some plants hold fruit or pods for many months.',
            'Include the fruit or pod, leaf arrangement, stem, and any remaining flowers that connect it to the plant.',
            'Leave seeds and fruit in place, avoid tasting unknown plants, and photograph from the path when required.'
        ),
        (
            'park_pollinators', 2, 40,
            'Watch flowering shrubs, canopy gaps, meadow edges, and perches near nectar- or insect-rich plants.',
            'Early morning is often active; pause quietly when flowers are busy or birds are calling nearby.',
            'Look for feeding or hovering behavior, beak shape, wing posture, markings, and the flowers being visited.',
            'Use zoom, avoid crowding the bird or blocking its approach, and never disturb nests near flowering plants.'
        ),
        (
            'park_pollinators', 2, 50,
            'Look along unmown edges, meadow patches, drainage margins, and mixed plant communities outside formal beds.',
            'Growth and bloom vary by season; even light and low wind help capture leaves and stems clearly.',
            'Notice how the plant grows, its leaves, flowers or seed heads, stem texture, and neighboring vegetation.',
            'Keep the plant rooted, avoid trampling the patch, and include several structures rather than one detached part.'
        ),
        (
            'park_pollinators', 2, 60,
            'Find a sunny patch that combines flowers, varied plant heights, shelter, bare ground, water, or nesting material.',
            'Choose a period when insects are visibly using the site so the habitat function is clear.',
            'Look for connected resources: blooms, host plants, resting places, nesting features, and reduced mowing or disturbance.',
            'Use a wide frame that shows the whole patch, stay on paths, and do not rearrange natural or installed habitat.'
        ),
        (
            'forest_edges', 1, 10,
            'Look along trail borders, canopy openings, hedgerows, and understory transitions for trees and shrubs.',
            'Even daylight reduces glare on leaves and bark; flowers, fruit, and buds appear in different seasons.',
            'Notice leaf arrangement, bark, branching, buds, flowers, fruit, and the overall growth form.',
            'Stay on the trail, photograph reachable details without breaking branches, and include the whole plant context.'
        ),
        (
            'forest_edges', 1, 20,
            'Search fallen logs, damp leaf litter, shaded soil, and tree bases where decaying material holds moisture.',
            'After rain or during humid periods is often most productive before exposed fungi dry out.',
            'Look for cap, gills or pores, stem, clustering, texture, and the wood or soil supporting the fungus.',
            'Do not taste, collect, or overturn it; photograph multiple angles while leaving the substrate undisturbed.'
        ),
        (
            'forest_edges', 1, 30,
            'Watch canopy gaps, edge shrubs, snags, and low branches where birds pause before moving into cover.',
            'Early morning is often active, but a quiet pause at any time can reveal calls or movement.',
            'Notice silhouette, beak, tail, wing bars, color patches, calls, and the height of the perch.',
            'Use zoom from the trail, avoid playback or pursuit, and give nests and feeding birds extra space.'
        ),
        (
            'forest_edges', 1, 40,
            'Inspect sunlit leaves, flowers, bark, trail surfaces, and decaying wood along the habitat edge.',
            'Warm calm periods are often active; cooler mornings may keep insects still for a clearer view.',
            'Look for wings, antennae, body segments, markings, and the surface or plant being used.',
            'Wait for a pause, do not handle the insect, and keep enough surrounding habitat in the frame.'
        ),
        (
            'forest_edges', 1, 50,
            'Check webbed gaps, bark crevices, leaf undersides, log surfaces, and sheltered trail-edge vegetation.',
            'Still mornings can reveal silk and web structure; evening light may reveal active hunters.',
            'Notice body proportions, leg arrangement, markings, web form, and the retreat or surface nearby.',
            'Keep fingers out of crevices, do not touch webs, and use zoom or an angled view instead of moving cover.'
        ),
        (
            'forest_edges', 1, 60,
            'Scan quiet openings, edge thickets, fallen logs, tracks, and routes between dense cover and open ground.',
            'Dawn and dusk are often productive; stop moving and listen before searching farther.',
            'Look for body shape, movement, tracks, feeding signs, tail, ears, and how the animal uses cover.',
            'Stay distant, never follow or feed the animal, and leave dens, young animals, and resting sites alone.'
        ),
        (
            'forest_edges', 2, 10,
            'Look on damp bark, rocks, soil banks, logs, and shaded trail edges where green cushions form.',
            'Recent moisture and soft overcast light make fine texture and color easier to see.',
            'Notice tiny leaves, branching form, cushion shape, reproductive stalks, and the surface underneath.',
            'Photograph close and wide views without scraping, collecting, or stepping on the patch.'
        ),
        (
            'forest_edges', 2, 20,
            'Search moist shaded slopes, drainage edges, stream approaches, and cool understory pockets.',
            'Spring and moist periods often bring fresh fronds, while mature fronds provide more identifying detail.',
            'Notice frond outline, leaflet arrangement, stem color, growth cluster, and underside structures when safely visible.',
            'Leave fronds attached, avoid climbing banks, and photograph the underside only when it can be seen without damage.'
        ),
        (
            'forest_edges', 2, 30,
            'Inspect leaf undersides, young stems, host plants, and chewed foliage along sunny or sheltered edges.',
            'Warm growing seasons are often productive; early or late daylight can reduce harsh shadows on small larvae.',
            'Look for body segmentation, hairs or spines, color pattern, posture, feeding marks, and the host plant.',
            'Do not handle unfamiliar larvae, keep them on the plant, and avoid breaking leaves to improve the view.'
        ),
        (
            'forest_edges', 2, 40,
            'Look where filtered light reaches leaf litter, path banks, clearings, and the base of woodland shrubs.',
            'Bloom timing varies, so revisit edge habitats through the growing season after rain or warm spells.',
            'Include flowers, leaves, stems, growth habit, and the surrounding forest-floor context.',
            'Stay on durable surfaces, do not pick blooms, and avoid compressing nearby seedlings or leaf litter.'
        ),
        (
            'forest_edges', 2, 50,
            'Check sunny rocks, damp margins, pond or stream approaches, logs, and warm trail edges from a distance.',
            'Mild warm periods can bring reptiles into sun; cool damp periods may favor amphibian activity.',
            'Notice skin or scale texture, body shape, limbs, tail, color pattern, and proximity to water or cover.',
            'Never handle or corner the animal, keep out of the water edge, and do not lift rocks or logs to find one.'
        ),
        (
            'forest_edges', 2, 60,
            'Look on mud, sand, snow, bark, feeding sites, and trail edges for tracks, scat, rubs, or chewed material.',
            'Fresh soft ground after rain or snow often preserves signs before traffic and weather erase them.',
            'Notice track shape, number of toes, stride, scale, feeding marks, hair, and the direction of travel.',
            'Photograph in place with a familiar object nearby for scale, and never touch scat or collect signs.'
        ),
        (
            'forest_edges', 2, 70,
            'Frame a living species together with the forest edge layers it uses: canopy, understory, logs, litter, or openings.',
            'Choose even light and a moment when the organism and surrounding habitat are both readable.',
            'Look for a clear relationship between the species and cover, food, moisture, perches, or decomposing material.',
            'Use a wider contextual frame, remain on the trail, and avoid moving plants, logs, or animals into position.'
        ),
        (
            'forest_edges', 2, 80,
            'Search established woodland plant communities, restoration areas, and trail edges away from recent landscaping.',
            'Flowers and fruit are seasonal, but leaves, stems, bark, and growth pattern can still provide useful evidence.',
            'Capture multiple traits and habitat context; native status cannot be confirmed from one decorative feature alone.',
            'Leave the plant rooted, follow restoration-area rules, and treat the scan as an identification candidate rather than proof of origin.'
        )
    ) AS seed(
        template_slug,
        level_number,
        sort_order,
        guide_where_to_look,
        guide_best_conditions,
        guide_what_to_notice,
        guide_scan_safely
    )
)
UPDATE public.field_trip_checklist_items AS item
SET guide_where_to_look = objective_guidance.guide_where_to_look,
    guide_best_conditions = objective_guidance.guide_best_conditions,
    guide_what_to_notice = objective_guidance.guide_what_to_notice,
    guide_scan_safely = objective_guidance.guide_scan_safely
FROM objective_guidance
JOIN public.field_trip_templates AS template
    ON template.slug = objective_guidance.template_slug
JOIN public.field_trip_levels AS level
    ON level.template_id = template.id
   AND level.level_number = objective_guidance.level_number
WHERE item.level_id = level.id
  AND item.sort_order = objective_guidance.sort_order;

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
                        'guide', CASE
                            WHEN fci.guide_where_to_look IS NULL
                             AND fci.guide_best_conditions IS NULL
                             AND fci.guide_what_to_notice IS NULL
                             AND fci.guide_scan_safely IS NULL THEN NULL
                            ELSE JSONB_BUILD_OBJECT(
                                'where_to_look', fci.guide_where_to_look,
                                'best_conditions', fci.guide_best_conditions,
                                'what_to_notice', fci.guide_what_to_notice,
                                'scan_safely', fci.guide_scan_safely
                            )
                        END,
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
                        'guide', CASE
                            WHEN fci.guide_where_to_look IS NULL
                             AND fci.guide_best_conditions IS NULL
                             AND fci.guide_what_to_notice IS NULL
                             AND fci.guide_scan_safely IS NULL THEN NULL
                            ELSE JSONB_BUILD_OBJECT(
                                'where_to_look', fci.guide_where_to_look,
                                'best_conditions', fci.guide_best_conditions,
                                'what_to_notice', fci.guide_what_to_notice,
                                'scan_safely', fci.guide_scan_safely
                            )
                        END,
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
