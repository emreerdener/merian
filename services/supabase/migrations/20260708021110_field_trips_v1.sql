-- Field Trips v1: Explore-adjacent quest templates, private active progress,
-- and explicit publication snapshots. This feature is intentionally distinct
-- from the existing low-power Expedition mode.

CREATE TABLE IF NOT EXISTS public.field_trip_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9_\\-]{2,80}$'),
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    subtitle TEXT,
    description TEXT,
    region_tags TEXT[] NOT NULL DEFAULT '{}',
    season_tags TEXT[] NOT NULL DEFAULT '{}',
    habitat_tags TEXT[] NOT NULL DEFAULT '{}',
    difficulty TEXT NOT NULL DEFAULT 'starter' CHECK (difficulty IN ('starter', 'easy', 'moderate', 'hard')),
    is_pro_only BOOLEAN NOT NULL DEFAULT FALSE,
    is_rotating_free BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.field_trip_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES public.field_trip_templates(id) ON DELETE CASCADE,
    level_number INTEGER NOT NULL CHECK (level_number > 0),
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(template_id, level_number)
);

CREATE TABLE IF NOT EXISTS public.field_trip_checklist_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    level_id UUID NOT NULL REFERENCES public.field_trip_levels(id) ON DELETE CASCADE,
    prompt TEXT NOT NULL CHECK (BTRIM(prompt) <> ''),
    match_type TEXT NOT NULL CHECK (match_type IN ('species', 'scientific_name', 'taxonomy', 'ecology', 'habitat', 'semantic_tag')),
    species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    scientific_name TEXT,
    taxonomy_kingdom TEXT,
    taxonomy_phylum TEXT,
    taxonomy_class TEXT,
    taxonomy_order TEXT,
    taxonomy_family TEXT,
    taxonomy_genus TEXT,
    ecology_type TEXT,
    habitat_tag TEXT,
    semantic_tag TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(level_id, sort_order)
);

CREATE TABLE IF NOT EXISTS public.user_field_trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES public.field_trip_templates(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_level_number INTEGER NOT NULL DEFAULT 1 CHECK (current_level_number > 0),
    completed_at TIMESTAMPTZ,
    is_profile_visible BOOLEAN NOT NULL DEFAULT TRUE,
    hidden_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, template_id)
);

CREATE TABLE IF NOT EXISTS public.user_field_trip_item_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_field_trip_id UUID NOT NULL REFERENCES public.user_field_trips(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.field_trip_checklist_items(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    common_name TEXT,
    scientific_name TEXT,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_field_trip_id, item_id),
    UNIQUE(user_field_trip_id, scan_id, item_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_publications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_field_trip_id UUID NOT NULL UNIQUE REFERENCES public.user_field_trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES public.field_trip_templates(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    description TEXT,
    ai_summary TEXT,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    like_count INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.field_trip_publication_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    publication_id UUID NOT NULL REFERENCES public.field_trip_publications(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.field_trip_checklist_items(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    common_name TEXT,
    scientific_name TEXT,
    hero_image_url TEXT,
    reference_image_url TEXT,
    taxonomy JSONB NOT NULL DEFAULT '{}'::jsonb,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(publication_id, item_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_publication_likes (
    publication_id UUID NOT NULL REFERENCES public.field_trip_publications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(publication_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_publication_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    publication_id UUID NOT NULL REFERENCES public.field_trip_publications(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES public.field_trip_publication_comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (LENGTH(BTRIM(body)) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    moderated_at TIMESTAMPTZ
);

COMMENT ON TABLE public.user_field_trips IS
    'Private Field Trip progress. Active visible progress may appear on public profiles, but no scan evidence or exact location is exposed here.';
COMMENT ON TABLE public.field_trip_publications IS
    'Field Trip-scoped published pages. Publishing here does not create Explore posts, map points, or Explore notifications.';
COMMENT ON TABLE public.field_trip_publication_items IS
    'Public snapshot items for a Field Trip page. This is the only v1 Field Trip surface that intentionally carries media URLs.';

CREATE INDEX IF NOT EXISTS idx_field_trip_templates_active_sort
    ON public.field_trip_templates(is_active, sort_order, title);
CREATE INDEX IF NOT EXISTS idx_field_trip_levels_template_number
    ON public.field_trip_levels(template_id, level_number);
CREATE INDEX IF NOT EXISTS idx_field_trip_items_level_sort
    ON public.field_trip_checklist_items(level_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_user_field_trips_user_visible
    ON public.user_field_trips(user_id, is_profile_visible, updated_at DESC)
    WHERE hidden_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_field_trips_template
    ON public.user_field_trips(template_id, current_level_number);
CREATE INDEX IF NOT EXISTS idx_user_field_trip_item_completions_trip
    ON public.user_field_trip_item_completions(user_field_trip_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_field_trip_publications_user_published
    ON public.field_trip_publications(user_id, published_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_publication_items_publication_sort
    ON public.field_trip_publication_items(publication_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_field_trip_publication_comments_publication
    ON public.field_trip_publication_comments(publication_id, created_at, id)
    WHERE deleted_at IS NULL AND moderated_at IS NULL;

CREATE OR REPLACE FUNCTION public.field_trip_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_templates_touch_updated_at ON public.field_trip_templates;
CREATE TRIGGER trg_field_trip_templates_touch_updated_at
BEFORE UPDATE ON public.field_trip_templates
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_touch_updated_at();

DROP TRIGGER IF EXISTS trg_user_field_trips_touch_updated_at ON public.user_field_trips;
CREATE TRIGGER trg_user_field_trips_touch_updated_at
BEFORE UPDATE ON public.user_field_trips
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_touch_updated_at();

DROP TRIGGER IF EXISTS trg_field_trip_publications_touch_updated_at ON public.field_trip_publications;
CREATE TRIGGER trg_field_trip_publications_touch_updated_at
BEFORE UPDATE ON public.field_trip_publications
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_touch_updated_at();

CREATE OR REPLACE FUNCTION public.field_trip_set_comment_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_comments_touch_updated_at ON public.field_trip_publication_comments;
CREATE TRIGGER trg_field_trip_comments_touch_updated_at
BEFORE UPDATE ON public.field_trip_publication_comments
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_set_comment_updated_at();

CREATE OR REPLACE FUNCTION public.field_trip_validate_comment_parent()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    parent_row RECORD;
BEGIN
    IF NEW.parent_comment_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id, publication_id, parent_comment_id, deleted_at, moderated_at
    INTO parent_row
    FROM public.field_trip_publication_comments
    WHERE id = NEW.parent_comment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip parent comment not found';
    END IF;
    IF parent_row.publication_id <> NEW.publication_id THEN
        RAISE EXCEPTION 'Field Trip parent comment must belong to the same publication';
    END IF;
    IF parent_row.parent_comment_id IS NOT NULL THEN
        RAISE EXCEPTION 'Field Trip replies can only target top-level comments';
    END IF;
    IF parent_row.deleted_at IS NOT NULL OR parent_row.moderated_at IS NOT NULL THEN
        RAISE EXCEPTION 'Field Trip parent comment is no longer available';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_comments_validate_parent ON public.field_trip_publication_comments;
CREATE TRIGGER trg_field_trip_comments_validate_parent
BEFORE INSERT OR UPDATE OF parent_comment_id, publication_id ON public.field_trip_publication_comments
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_validate_comment_parent();

CREATE OR REPLACE FUNCTION public.field_trip_publication_like_count_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.field_trip_publications
    SET like_count = like_count + 1
    WHERE id = NEW.publication_id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.field_trip_publication_like_count_after_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.field_trip_publications
    SET like_count = GREATEST(0, like_count - 1)
    WHERE id = OLD.publication_id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_publication_like_count_after_insert ON public.field_trip_publication_likes;
CREATE TRIGGER trg_field_trip_publication_like_count_after_insert
AFTER INSERT ON public.field_trip_publication_likes
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_publication_like_count_after_insert();

DROP TRIGGER IF EXISTS trg_field_trip_publication_like_count_after_delete ON public.field_trip_publication_likes;
CREATE TRIGGER trg_field_trip_publication_like_count_after_delete
AFTER DELETE ON public.field_trip_publication_likes
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_publication_like_count_after_delete();

CREATE OR REPLACE FUNCTION public.recompute_field_trip_publication_comment_count(target_publication_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    computed_count INTEGER := 0;
BEGIN
    SELECT COUNT(*)::INTEGER
    INTO computed_count
    FROM public.field_trip_publication_comments c
    WHERE c.publication_id = target_publication_id
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL;

    UPDATE public.field_trip_publications
    SET comment_count = computed_count
    WHERE id = target_publication_id;

    RETURN computed_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.field_trip_publication_comment_count_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recompute_field_trip_publication_comment_count(OLD.publication_id);
        RETURN OLD;
    END IF;

    PERFORM public.recompute_field_trip_publication_comment_count(NEW.publication_id);
    IF TG_OP = 'UPDATE' AND OLD.publication_id <> NEW.publication_id THEN
        PERFORM public.recompute_field_trip_publication_comment_count(OLD.publication_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_publication_comment_count ON public.field_trip_publication_comments;
CREATE TRIGGER trg_field_trip_publication_comment_count
AFTER INSERT OR UPDATE OF deleted_at, moderated_at, publication_id OR DELETE ON public.field_trip_publication_comments
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_publication_comment_count_trigger();

CREATE OR REPLACE FUNCTION public.field_trip_species_common_name(common_names JSONB, scientific_name TEXT, fallback TEXT DEFAULT 'Unknown subject')
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(common_names->>'en'), ''),
        NULLIF(BTRIM(scientific_name), ''),
        fallback
    );
$$;

CREATE OR REPLACE FUNCTION public.field_trip_lower_text_array(values TEXT[])
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(ARRAY_AGG(LOWER(BTRIM(value))) FILTER (WHERE BTRIM(value) <> ''), ARRAY[]::TEXT[])
    FROM UNNEST(COALESCE(values, ARRAY[]::TEXT[])) AS value;
$$;

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
AS $$
    SELECT CASE
        WHEN match_type = 'species' THEN
            item_species_id IS NOT NULL AND item_species_id = scan_species_id
        WHEN match_type = 'scientific_name' THEN
            NULLIF(BTRIM(item_scientific_name), '') IS NOT NULL
            AND LOWER(BTRIM(item_scientific_name)) = LOWER(BTRIM(COALESCE(scan_scientific_name, '')))
        WHEN match_type = 'taxonomy' THEN
            (NULLIF(BTRIM(item_taxonomy_kingdom), '') IS NULL OR LOWER(BTRIM(item_taxonomy_kingdom)) = LOWER(BTRIM(COALESCE(scan_kingdom, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_phylum), '') IS NULL OR LOWER(BTRIM(item_taxonomy_phylum)) = LOWER(BTRIM(COALESCE(scan_phylum, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_class), '') IS NULL OR LOWER(BTRIM(item_taxonomy_class)) = LOWER(BTRIM(COALESCE(scan_class, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_order), '') IS NULL OR LOWER(BTRIM(item_taxonomy_order)) = LOWER(BTRIM(COALESCE(scan_order, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_family), '') IS NULL OR LOWER(BTRIM(item_taxonomy_family)) = LOWER(BTRIM(COALESCE(scan_family, ''))))
            AND (NULLIF(BTRIM(item_taxonomy_genus), '') IS NULL OR LOWER(BTRIM(item_taxonomy_genus)) = LOWER(BTRIM(COALESCE(scan_genus, ''))))
            AND (
                NULLIF(BTRIM(item_taxonomy_kingdom), '') IS NOT NULL
                OR NULLIF(BTRIM(item_taxonomy_phylum), '') IS NOT NULL
                OR NULLIF(BTRIM(item_taxonomy_class), '') IS NOT NULL
                OR NULLIF(BTRIM(item_taxonomy_order), '') IS NOT NULL
                OR NULLIF(BTRIM(item_taxonomy_family), '') IS NOT NULL
                OR NULLIF(BTRIM(item_taxonomy_genus), '') IS NOT NULL
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

CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress(self_id UUID, target_scan_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    user_is_pro BOOLEAN := FALSE;
    inserted_count INTEGER := 0;
    response JSONB := '[]'::jsonb;
BEGIN
    SELECT
        s.id,
        s.user_id,
        s.timestamp,
        s.ecology_type::TEXT AS ecology_type,
        s.is_tombstoned,
        s.is_biological_subject,
        COALESCE(s.confirmed_species_id, s.species_id) AS resolved_species_id,
        sd.scientific_name,
        sd.common_names,
        sd.kingdom,
        sd.phylum,
        sd."class",
        sd."order",
        sd.family,
        sd.genus,
        sd.habitat_description,
        sd.group_tags
    INTO scan_row
    FROM public.scans s
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE s.id = target_scan_id
      AND s.user_id = self_id;

    IF NOT FOUND OR scan_row.is_tombstoned OR scan_row.is_biological_subject IS FALSE OR scan_row.resolved_species_id IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    DROP TABLE IF EXISTS pg_temp.field_trip_scan_matches;
    CREATE TEMP TABLE field_trip_scan_matches ON COMMIT DROP AS
    WITH eligible_templates AS (
        SELECT t.*
        FROM public.field_trip_templates t
        WHERE t.is_active = TRUE
          AND (t.is_pro_only = FALSE OR user_is_pro OR t.is_rotating_free = TRUE)
    ),
    candidate_levels AS (
        SELECT
            t.id AS template_id,
            COALESCE(uft.id, NULL) AS user_field_trip_id,
            COALESCE(uft.current_level_number, 1) AS level_number,
            COALESCE(uft.started_at, scan_row.timestamp) AS started_at
        FROM eligible_templates t
        LEFT JOIN public.user_field_trips uft
            ON uft.template_id = t.id
           AND uft.user_id = self_id
           AND uft.completed_at IS NULL
           AND uft.hidden_at IS NULL
    )
    SELECT
        cl.template_id,
        cl.user_field_trip_id,
        cl.level_number,
        cl.started_at,
        fl.id AS level_id,
        fci.id AS item_id,
        fci.prompt,
        scan_row.resolved_species_id::UUID AS species_id,
        public.field_trip_species_common_name(scan_row.common_names, scan_row.scientific_name, fci.prompt) AS common_name,
        scan_row.scientific_name::TEXT AS scientific_name
    FROM candidate_levels cl
    JOIN public.field_trip_levels fl
        ON fl.template_id = cl.template_id
       AND fl.level_number = cl.level_number
    JOIN public.field_trip_checklist_items fci
        ON fci.level_id = fl.id
    WHERE scan_row.timestamp >= cl.started_at
      AND public.field_trip_item_matches_scan(
          fci.match_type,
          fci.species_id,
          fci.scientific_name,
          fci.taxonomy_kingdom,
          fci.taxonomy_phylum,
          fci.taxonomy_class,
          fci.taxonomy_order,
          fci.taxonomy_family,
          fci.taxonomy_genus,
          fci.ecology_type,
          fci.habitat_tag,
          fci.semantic_tag,
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

    INSERT INTO public.user_field_trips(user_id, template_id, started_at, current_level_number, is_profile_visible)
    SELECT DISTINCT self_id, m.template_id, scan_row.timestamp, 1, TRUE
    FROM pg_temp.field_trip_scan_matches m
    WHERE m.user_field_trip_id IS NULL
    ON CONFLICT(user_id, template_id) DO NOTHING;

    WITH resolved_matches AS (
        SELECT
            uft.id AS user_field_trip_id,
            m.item_id,
            m.species_id,
            m.common_name,
            m.scientific_name
        FROM pg_temp.field_trip_scan_matches m
        JOIN public.user_field_trips uft
            ON uft.user_id = self_id
           AND uft.template_id = m.template_id
        WHERE uft.completed_at IS NULL
          AND uft.hidden_at IS NULL
          AND scan_row.timestamp >= uft.started_at
    ),
    inserted AS (
        INSERT INTO public.user_field_trip_item_completions(
            user_field_trip_id,
            item_id,
            scan_id,
            species_id,
            common_name,
            scientific_name,
            completed_at
        )
        SELECT
            rm.user_field_trip_id,
            rm.item_id,
            target_scan_id,
            rm.species_id,
            rm.common_name,
            rm.scientific_name,
            scan_row.timestamp
        FROM resolved_matches rm
        ON CONFLICT(user_field_trip_id, item_id) DO NOTHING
        RETURNING user_field_trip_id, item_id
    )
    SELECT COUNT(*)::INTEGER
    INTO inserted_count
    FROM inserted;

    IF inserted_count = 0 THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH touched_trips AS (
        SELECT DISTINCT uft.id, uft.template_id, uft.current_level_number
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_scan_matches m
            ON m.template_id = uft.template_id
        WHERE uft.user_id = self_id
    ),
    level_counts AS (
        SELECT
            tt.id AS user_field_trip_id,
            tt.template_id,
            tt.current_level_number,
            fl.id AS current_level_id,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM touched_trips tt
        JOIN public.field_trip_levels fl
            ON fl.template_id = tt.template_id
           AND fl.level_number = tt.current_level_number
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = tt.id
           AND ufc.item_id = fci.id
        GROUP BY tt.id, tt.template_id, tt.current_level_number, fl.id
    ),
    next_levels AS (
        SELECT
            lc.*,
            (
                SELECT MIN(next_fl.level_number)
                FROM public.field_trip_levels next_fl
                WHERE next_fl.template_id = lc.template_id
                  AND next_fl.level_number > lc.current_level_number
            ) AS next_level_number
        FROM level_counts lc
        WHERE lc.completed_count >= lc.target_count
    )
    UPDATE public.user_field_trips uft
    SET current_level_number = COALESCE(nl.next_level_number, uft.current_level_number),
        completed_at = CASE WHEN nl.next_level_number IS NULL THEN COALESCE(uft.completed_at, NOW()) ELSE uft.completed_at END
    FROM next_levels nl
    WHERE uft.id = nl.user_field_trip_id;

    WITH touched_trips AS (
        SELECT DISTINCT uft.id
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_scan_matches m
            ON m.template_id = uft.template_id
        WHERE uft.user_id = self_id
    ),
    trip_counts AS (
        SELECT
            uft.id AS user_field_trip_id,
            uft.current_level_number,
            uft.completed_at,
            t.id AS template_id,
            t.slug,
            t.title,
            fl.id AS current_level_id,
            fl.title AS current_level_title,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(ufc.id)::INTEGER AS completed_count
        FROM touched_trips tt
        JOIN public.user_field_trips uft
            ON uft.id = tt.id
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
        GROUP BY uft.id, uft.current_level_number, uft.completed_at, t.id, t.slug, t.title, fl.id, fl.title
    ),
    newly_completed AS (
        SELECT
            uft.id AS user_field_trip_id,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'item_id', fci.id,
                    'prompt', fci.prompt,
                    'common_name', ufc.common_name,
                    'scientific_name', ufc.scientific_name,
                    'completed_at', ufc.completed_at
                )
                ORDER BY fci.sort_order
            ) AS items
        FROM public.user_field_trips uft
        JOIN pg_temp.field_trip_scan_matches m
            ON m.template_id = uft.template_id
        JOIN public.user_field_trip_item_completions ufc
            ON ufc.user_field_trip_id = uft.id
           AND ufc.item_id = m.item_id
           AND ufc.scan_id = target_scan_id
        JOIN public.field_trip_checklist_items fci
            ON fci.id = ufc.item_id
        WHERE uft.user_id = self_id
        GROUP BY uft.id
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'user_field_trip_id', tc.user_field_trip_id,
            'template_id', tc.template_id,
            'slug', tc.slug,
            'title', tc.title,
            'current_level_number', tc.current_level_number,
            'current_level_title', tc.current_level_title,
            'completed_count', tc.completed_count,
            'target_count', tc.target_count,
            'is_complete', tc.completed_at IS NOT NULL,
            'newly_completed_items', COALESCE(nc.items, '[]'::jsonb)
        )
        ORDER BY tc.title
    ), '[]'::jsonb)
    INTO response
    FROM trip_counts tc
    LEFT JOIN newly_completed nc
        ON nc.user_field_trip_id = tc.user_field_trip_id;

    RETURN response;
END;
$$;

CREATE OR REPLACE FUNCTION public.user_has_visible_field_trip_profile(self_id UUID, target_author_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = target_author_user_id
          AND u.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = target_author_user_id)
                 OR (ub.blocker_id = target_author_user_id AND ub.blocked_id = self_id)
          )
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.user_field_trips uft
                  WHERE uft.user_id = target_author_user_id
                    AND uft.is_profile_visible = TRUE
                    AND uft.hidden_at IS NULL
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.field_trip_publications ftp
                  WHERE ftp.user_id = target_author_user_id
                    AND ftp.deleted_at IS NULL
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_field_trip_publication(self_id UUID, target_publication_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.field_trip_publications ftp
        JOIN public.users u
            ON u.id = ftp.user_id
        WHERE ftp.id = target_publication_id
          AND ftp.deleted_at IS NULL
          AND u.is_shadowbanned = FALSE
          AND (
              ftp.user_id = self_id
              OR NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks ub
                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = ftp.user_id)
                     OR (ub.blocker_id = ftp.user_id AND ub.blocked_id = self_id)
              )
          )
    );
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
    published_payload JSONB := '[]'::jsonb;
BEGIN
    IF NOT public.user_has_visible_field_trip_profile(self_id, target_author_user_id) THEN
        RETURN JSONB_BUILD_OBJECT('active', '[]'::jsonb, 'published', '[]'::jsonb);
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
            'viewer_has_liked', viewer_has_liked
        )
    ), '[]'::jsonb)
    INTO published_payload
    FROM published_trips;

    RETURN JSONB_BUILD_OBJECT('active', active_payload, 'published', published_payload);
END;
$$;

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
                WHEN t.is_pro_only AND NOT user_is_pro AND NOT t.is_rotating_free THEN 'pro'
                WHEN t.is_rotating_free THEN 'rotating_free'
                ELSE 'free'
            END AS access_kind
        FROM public.field_trip_templates t
        WHERE t.is_active = TRUE
        ORDER BY
            CASE
                WHEN user_region IS NOT NULL AND LOWER(user_region) = ANY(public.field_trip_lower_text_array(t.region_tags)) THEN 0
                WHEN COALESCE(ARRAY_LENGTH(t.region_tags, 1), 0) = 0 THEN 1
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
        ORDER BY t.sort_order, t.title
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
SET search_path = public
AS $$
DECLARE
    trip_row RECORD;
    created_publication_id UUID;
    resolved_title TEXT;
BEGIN
    SELECT uft.*, t.title AS template_title
    INTO trip_row
    FROM public.user_field_trips uft
    JOIN public.field_trip_templates t
        ON t.id = uft.template_id
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
        user_field_trip_id,
        user_id,
        template_id,
        title,
        description,
        ai_summary,
        published_at,
        deleted_at
    )
    VALUES (
        trip_row.id,
        self_id,
        trip_row.template_id,
        resolved_title,
        NULLIF(BTRIM(publication_description), ''),
        NULLIF(BTRIM(publication_ai_summary), ''),
        NOW(),
        NULL
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
        created_publication_id,
        item_id,
        scan_id,
        species_id,
        common_name,
        scientific_name,
        hero_image_url,
        reference_image_url,
        taxonomy,
        sort_order
    )
    SELECT
        publication_id,
        fci.id,
        ufc.scan_id,
        COALESCE(ufc.species_id, COALESCE(s.confirmed_species_id, s.species_id)),
        COALESCE(ufc.common_name, public.field_trip_species_common_name(sd.common_names, sd.scientific_name, fci.prompt)),
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
    JOIN public.field_trip_checklist_items fci
        ON fci.id = ufc.item_id
    JOIN public.field_trip_levels fl
        ON fl.id = fci.level_id
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

CREATE OR REPLACE FUNCTION public.get_field_trip_publication_detail(self_id UUID, target_publication_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    detail_payload JSONB;
BEGIN
    IF NOT public.can_view_field_trip_publication(self_id, target_publication_id) THEN
        RETURN NULL;
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'publication_id', ftp.id,
        'user_field_trip_id', ftp.user_field_trip_id,
        'template_id', ftp.template_id,
        'template_slug', t.slug,
        'template_title', t.title,
        'title', ftp.title,
        'description', ftp.description,
        'ai_summary', ftp.ai_summary,
        'published_at', ftp.published_at,
        'author_user_id', ftp.user_id,
        'author_name', u.public_author_name,
        'author_username', u.public_username,
        'author_avatar_url', u.public_avatar_url,
        'like_count', ftp.like_count,
        'comment_count', ftp.comment_count,
        'viewer_has_liked', EXISTS (
            SELECT 1
            FROM public.field_trip_publication_likes ftpl
            WHERE ftpl.publication_id = ftp.id
              AND ftpl.user_id = self_id
        ),
        'items', COALESCE((
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'publication_item_id', fpi.id,
                    'item_id', fpi.item_id,
                    'prompt', fci.prompt,
                    'common_name', fpi.common_name,
                    'scientific_name', fpi.scientific_name,
                    'hero_image_url', fpi.hero_image_url,
                    'reference_image_url', fpi.reference_image_url,
                    'taxonomy', fpi.taxonomy
                )
                ORDER BY fpi.sort_order
            )
            FROM public.field_trip_publication_items fpi
            JOIN public.field_trip_checklist_items fci
                ON fci.id = fpi.item_id
            WHERE fpi.publication_id = ftp.id
        ), '[]'::jsonb)
    )
    INTO detail_payload
    FROM public.field_trip_publications ftp
    JOIN public.field_trip_templates t
        ON t.id = ftp.template_id
    JOIN public.users u
        ON u.id = ftp.user_id
    WHERE ftp.id = target_publication_id
      AND ftp.deleted_at IS NULL;

    RETURN detail_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_comments(
    self_id UUID,
    target_publication_id UUID,
    max_limit INTEGER DEFAULT 50,
    after_created_at TIMESTAMPTZ DEFAULT NULL,
    after_comment_id UUID DEFAULT NULL
)
RETURNS TABLE(
    comment_id UUID,
    post_id UUID,
    parent_comment_id UUID,
    author_user_id UUID,
    author_name TEXT,
    author_username TEXT,
    author_avatar_url TEXT,
    body TEXT,
    created_at TIMESTAMPTZ,
    viewer_can_delete BOOLEAN,
    viewer_can_moderate BOOLEAN,
    viewer_can_report BOOLEAN,
    reply_count INTEGER,
    reactions JSONB,
    mentions JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 50), 100));
BEGIN
    IF NOT public.can_view_field_trip_publication(self_id, target_publication_id) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        c.id AS comment_id,
        c.publication_id AS post_id,
        c.parent_comment_id,
        c.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_username AS author_username,
        u.public_avatar_url AS author_avatar_url,
        c.body,
        c.created_at,
        c.user_id = self_id AS viewer_can_delete,
        FALSE AS viewer_can_moderate,
        c.user_id <> self_id AS viewer_can_report,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.field_trip_publication_comments reply
            JOIN public.users reply_author
                ON reply_author.id = reply.user_id
            WHERE reply.parent_comment_id = c.id
              AND reply.deleted_at IS NULL
              AND reply.moderated_at IS NULL
              AND reply_author.is_shadowbanned = FALSE
        ) AS reply_count,
        '[]'::jsonb AS reactions,
        '[]'::jsonb AS mentions
    FROM public.field_trip_publication_comments c
    JOIN public.users u
        ON u.id = c.user_id
    WHERE c.publication_id = target_publication_id
      AND c.parent_comment_id IS NULL
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = c.user_id)
             OR (ub.blocker_id = c.user_id AND ub.blocked_id = self_id)
      )
      AND (
          after_created_at IS NULL
          OR (c.created_at, c.id) > (after_created_at, after_comment_id)
      )
    ORDER BY c.created_at ASC, c.id ASC
    LIMIT resolved_limit;
END;
$$;

-- Explicit RLS and grants. Edge Functions use service-role access, but these
-- keep direct API exposure bounded under Supabase's newer explicit-exposure behavior.
ALTER TABLE public.field_trip_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_field_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_field_trip_item_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_publications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_publication_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_publication_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_publication_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active field trip templates" ON public.field_trip_templates;
CREATE POLICY "Anyone can read active field trip templates"
    ON public.field_trip_templates FOR SELECT
    USING (is_active = TRUE);

DROP POLICY IF EXISTS "Anyone can read field trip levels" ON public.field_trip_levels;
CREATE POLICY "Anyone can read field trip levels"
    ON public.field_trip_levels FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.field_trip_templates t
        WHERE t.id = template_id AND t.is_active = TRUE
    ));

DROP POLICY IF EXISTS "Anyone can read field trip checklist items" ON public.field_trip_checklist_items;
CREATE POLICY "Anyone can read field trip checklist items"
    ON public.field_trip_checklist_items FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.field_trip_levels fl
        JOIN public.field_trip_templates t ON t.id = fl.template_id
        WHERE fl.id = level_id AND t.is_active = TRUE
    ));

DROP POLICY IF EXISTS "Users can manage their own field trip progress" ON public.user_field_trips;
CREATE POLICY "Users can manage their own field trip progress"
    ON public.user_field_trips FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can read their own field trip item completions" ON public.user_field_trip_item_completions;
CREATE POLICY "Users can read their own field trip item completions"
    ON public.user_field_trip_item_completions FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.user_field_trips uft
        WHERE uft.id = user_field_trip_id AND uft.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "Users can view visible field trip publications" ON public.field_trip_publications;
CREATE POLICY "Users can view visible field trip publications"
    ON public.field_trip_publications FOR SELECT
    USING (public.can_view_field_trip_publication(auth.uid(), id));

DROP POLICY IF EXISTS "Users can manage their own field trip publications" ON public.field_trip_publications;
CREATE POLICY "Users can manage their own field trip publications"
    ON public.field_trip_publications FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view visible field trip publication items" ON public.field_trip_publication_items;
CREATE POLICY "Users can view visible field trip publication items"
    ON public.field_trip_publication_items FOR SELECT
    USING (public.can_view_field_trip_publication(auth.uid(), publication_id));

DROP POLICY IF EXISTS "Users can manage their own field trip publication items" ON public.field_trip_publication_items;
CREATE POLICY "Users can manage their own field trip publication items"
    ON public.field_trip_publication_items FOR ALL
    USING (EXISTS (
        SELECT 1 FROM public.field_trip_publications ftp
        WHERE ftp.id = publication_id AND ftp.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.field_trip_publications ftp
        WHERE ftp.id = publication_id AND ftp.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "Users can read field trip likes on visible publications" ON public.field_trip_publication_likes;
CREATE POLICY "Users can read field trip likes on visible publications"
    ON public.field_trip_publication_likes FOR SELECT
    USING (public.can_view_field_trip_publication(auth.uid(), publication_id));

DROP POLICY IF EXISTS "Users can insert their own field trip likes" ON public.field_trip_publication_likes;
CREATE POLICY "Users can insert their own field trip likes"
    ON public.field_trip_publication_likes FOR INSERT
    WITH CHECK (auth.uid() = user_id AND public.can_view_field_trip_publication(auth.uid(), publication_id));

DROP POLICY IF EXISTS "Users can delete their own field trip likes" ON public.field_trip_publication_likes;
CREATE POLICY "Users can delete their own field trip likes"
    ON public.field_trip_publication_likes FOR DELETE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can read field trip comments on visible publications" ON public.field_trip_publication_comments;
CREATE POLICY "Users can read field trip comments on visible publications"
    ON public.field_trip_publication_comments FOR SELECT
    USING (public.can_view_field_trip_publication(auth.uid(), publication_id));

DROP POLICY IF EXISTS "Users can insert their own field trip comments" ON public.field_trip_publication_comments;
CREATE POLICY "Users can insert their own field trip comments"
    ON public.field_trip_publication_comments FOR INSERT
    WITH CHECK (auth.uid() = user_id AND public.can_view_field_trip_publication(auth.uid(), publication_id));

DROP POLICY IF EXISTS "Users can soft-delete their own field trip comments" ON public.field_trip_publication_comments;
CREATE POLICY "Users can soft-delete their own field trip comments"
    ON public.field_trip_publication_comments FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

GRANT SELECT ON public.field_trip_templates, public.field_trip_levels, public.field_trip_checklist_items TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_field_trips TO authenticated;
GRANT SELECT ON public.user_field_trip_item_completions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.field_trip_publications, public.field_trip_publication_items TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.field_trip_publication_likes TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.field_trip_publication_comments TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_catalog(UUID, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_profile_summaries(UUID, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_publication_detail(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_comments(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_field_trip(UUID, UUID, TEXT, TEXT, TEXT) TO authenticated;

INSERT INTO public.field_trip_templates(
    slug,
    title,
    subtitle,
    description,
    region_tags,
    season_tags,
    habitat_tags,
    difficulty,
    is_pro_only,
    is_rotating_free,
    sort_order
)
VALUES
    (
        'backyard_safari',
        'Backyard Safari',
        'A starter trip for everyday neighborhood life.',
        'Find familiar animals and small wild neighbors without leaving your usual walking radius.',
        ARRAY['global', 'neighborhood'],
        ARRAY['spring', 'summer', 'fall'],
        ARRAY['urban', 'yard', 'garden'],
        'starter',
        FALSE,
        TRUE,
        10
    ),
    (
        'park_pollinators',
        'Park Pollinators',
        'Flowers, wings, and the tiny work of moving pollen.',
        'A gentle park trip focused on insects and flowering plants.',
        ARRAY['global', 'park'],
        ARRAY['spring', 'summer'],
        ARRAY['park', 'meadow', 'garden'],
        'easy',
        FALSE,
        TRUE,
        20
    ),
    (
        'forest_edges',
        'Forest Edges',
        'A Pro trip for layered habitats where trail meets shade.',
        'Look for fungi, plants, arthropods, birds, and mammals along woodland edges.',
        ARRAY['global', 'forest'],
        ARRAY['spring', 'summer', 'fall'],
        ARRAY['forest', 'woodland', 'trail'],
        'moderate',
        TRUE,
        FALSE,
        30
    )
ON CONFLICT(slug) DO UPDATE
SET title = EXCLUDED.title,
    subtitle = EXCLUDED.subtitle,
    description = EXCLUDED.description,
    region_tags = EXCLUDED.region_tags,
    season_tags = EXCLUDED.season_tags,
    habitat_tags = EXCLUDED.habitat_tags,
    difficulty = EXCLUDED.difficulty,
    is_pro_only = EXCLUDED.is_pro_only,
    is_rotating_free = EXCLUDED.is_rotating_free,
    sort_order = EXCLUDED.sort_order;

WITH template AS (
    SELECT id FROM public.field_trip_templates WHERE slug = 'backyard_safari'
),
levels AS (
    INSERT INTO public.field_trip_levels(template_id, level_number, title, description)
    SELECT template.id, level_number, title, description
    FROM template
    CROSS JOIN (VALUES
        (1, 'Level 1', 'A compact neighborhood checklist.'),
        (2, 'Level 2', 'A wider look at common urban biodiversity.')
    ) AS seed(level_number, title, description)
    ON CONFLICT(template_id, level_number) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description
    RETURNING id, level_number
)
INSERT INTO public.field_trip_checklist_items(
    level_id,
    prompt,
    match_type,
    scientific_name,
    taxonomy_kingdom,
    taxonomy_class,
    taxonomy_order,
    taxonomy_genus,
    ecology_type,
    semantic_tag,
    sort_order
)
SELECT l.id, seed.prompt, seed.match_type, seed.scientific_name, seed.taxonomy_kingdom,
       seed.taxonomy_class, seed.taxonomy_order, seed.taxonomy_genus, seed.ecology_type,
       seed.semantic_tag, seed.sort_order
FROM levels l
JOIN (VALUES
    (1, 'Butterfly', 'taxonomy', NULL::TEXT, NULL::TEXT, 'Insecta', 'Lepidoptera', NULL::TEXT, NULL::TEXT, NULL::TEXT, 10),
    (1, 'Bird', 'taxonomy', NULL::TEXT, NULL::TEXT, 'Aves', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 20),
    (1, 'Cat', 'scientific_name', 'Felis catus', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 30),
    (1, 'Spider', 'taxonomy', NULL::TEXT, NULL::TEXT, 'Arachnida', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 40),
    (2, 'Flowering plant', 'taxonomy', NULL::TEXT, 'Plantae', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 'flower', 10),
    (2, 'Fungus', 'taxonomy', NULL::TEXT, 'Fungi', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 20),
    (2, 'Domesticated animal', 'ecology', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 'domesticated', NULL::TEXT, 30),
    (2, 'Insect', 'taxonomy', NULL::TEXT, NULL::TEXT, 'Insecta', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 40),
    (2, 'Urban wild animal', 'ecology', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 'urban', NULL::TEXT, 50),
    (2, 'Moss or lichen', 'semantic_tag', NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, 'moss', 60)
) AS seed(level_number, prompt, match_type, scientific_name, taxonomy_kingdom, taxonomy_class, taxonomy_order, taxonomy_genus, ecology_type, semantic_tag, sort_order)
    ON seed.level_number = l.level_number
ON CONFLICT(level_id, sort_order) DO UPDATE
SET prompt = EXCLUDED.prompt,
    match_type = EXCLUDED.match_type,
    scientific_name = EXCLUDED.scientific_name,
    taxonomy_kingdom = EXCLUDED.taxonomy_kingdom,
    taxonomy_class = EXCLUDED.taxonomy_class,
    taxonomy_order = EXCLUDED.taxonomy_order,
    taxonomy_genus = EXCLUDED.taxonomy_genus,
    ecology_type = EXCLUDED.ecology_type,
    semantic_tag = EXCLUDED.semantic_tag;

WITH template AS (
    SELECT id FROM public.field_trip_templates WHERE slug = 'park_pollinators'
),
levels AS (
    INSERT INTO public.field_trip_levels(template_id, level_number, title, description)
    SELECT template.id, level_number, title, description
    FROM template
    CROSS JOIN (VALUES
        (1, 'Level 1', 'Start with visible pollinator habitat.'),
        (2, 'Level 2', 'Add more pollinator neighbors and supporting plants.')
    ) AS seed(level_number, title, description)
    ON CONFLICT(template_id, level_number) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description
    RETURNING id, level_number
)
INSERT INTO public.field_trip_checklist_items(
    level_id,
    prompt,
    match_type,
    taxonomy_kingdom,
    taxonomy_class,
    taxonomy_order,
    semantic_tag,
    sort_order
)
SELECT l.id, seed.prompt, seed.match_type, seed.taxonomy_kingdom, seed.taxonomy_class,
       seed.taxonomy_order, seed.semantic_tag, seed.sort_order
FROM levels l
JOIN (VALUES
    (1, 'Flowering plant', 'taxonomy', 'Plantae', NULL::TEXT, NULL::TEXT, NULL::TEXT, 10),
    (1, 'Butterfly or moth', 'taxonomy', NULL::TEXT, 'Insecta', 'Lepidoptera', NULL::TEXT, 20),
    (1, 'Bee or wasp', 'taxonomy', NULL::TEXT, 'Insecta', 'Hymenoptera', NULL::TEXT, 30),
    (1, 'Fly', 'taxonomy', NULL::TEXT, 'Insecta', 'Diptera', NULL::TEXT, 40),
    (2, 'Beetle', 'taxonomy', NULL::TEXT, 'Insecta', 'Coleoptera', NULL::TEXT, 10),
    (2, 'Spider near flowers', 'taxonomy', NULL::TEXT, 'Arachnida', NULL::TEXT, NULL::TEXT, 20),
    (2, 'Seed or fruiting plant', 'semantic_tag', 'Plantae', NULL::TEXT, NULL::TEXT, 'fruit', 30),
    (2, 'Bird near flowers', 'taxonomy', NULL::TEXT, 'Aves', NULL::TEXT, NULL::TEXT, 40),
    (2, 'Wild plant', 'ecology', NULL::TEXT, NULL::TEXT, NULL::TEXT, 'wild', 50),
    (2, 'Pollinator habitat', 'habitat', NULL::TEXT, NULL::TEXT, NULL::TEXT, 'meadow', 60)
) AS seed(level_number, prompt, match_type, taxonomy_kingdom, taxonomy_class, taxonomy_order, semantic_tag, sort_order)
    ON seed.level_number = l.level_number
ON CONFLICT(level_id, sort_order) DO UPDATE
SET prompt = EXCLUDED.prompt,
    match_type = EXCLUDED.match_type,
    taxonomy_kingdom = EXCLUDED.taxonomy_kingdom,
    taxonomy_class = EXCLUDED.taxonomy_class,
    taxonomy_order = EXCLUDED.taxonomy_order,
    semantic_tag = EXCLUDED.semantic_tag;

WITH template AS (
    SELECT id FROM public.field_trip_templates WHERE slug = 'forest_edges'
),
levels AS (
    INSERT INTO public.field_trip_levels(template_id, level_number, title, description)
    SELECT template.id, level_number, title, description
    FROM template
    CROSS JOIN (VALUES
        (1, 'Level 1', 'A broad woodland-edge sampler.'),
        (2, 'Level 2', 'Look for quieter forest-edge signals.')
    ) AS seed(level_number, title, description)
    ON CONFLICT(template_id, level_number) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description
    RETURNING id, level_number
)
INSERT INTO public.field_trip_checklist_items(
    level_id,
    prompt,
    match_type,
    taxonomy_kingdom,
    taxonomy_class,
    taxonomy_order,
    semantic_tag,
    sort_order
)
SELECT l.id, seed.prompt, seed.match_type, seed.taxonomy_kingdom, seed.taxonomy_class,
       seed.taxonomy_order, seed.semantic_tag, seed.sort_order
FROM levels l
JOIN (VALUES
    (1, 'Tree or shrub', 'taxonomy', 'Plantae', NULL::TEXT, NULL::TEXT, 'tree', 10),
    (1, 'Fungus', 'taxonomy', 'Fungi', NULL::TEXT, NULL::TEXT, NULL::TEXT, 20),
    (1, 'Bird', 'taxonomy', NULL::TEXT, 'Aves', NULL::TEXT, NULL::TEXT, 30),
    (1, 'Insect', 'taxonomy', NULL::TEXT, 'Insecta', NULL::TEXT, NULL::TEXT, 40),
    (1, 'Spider', 'taxonomy', NULL::TEXT, 'Arachnida', NULL::TEXT, NULL::TEXT, 50),
    (1, 'Wild mammal', 'taxonomy', NULL::TEXT, 'Mammalia', NULL::TEXT, NULL::TEXT, 60),
    (2, 'Moss', 'semantic_tag', 'Plantae', NULL::TEXT, NULL::TEXT, 'moss', 10),
    (2, 'Fern', 'semantic_tag', 'Plantae', NULL::TEXT, NULL::TEXT, 'fern', 20),
    (2, 'Larva or caterpillar', 'semantic_tag', NULL::TEXT, 'Insecta', NULL::TEXT, 'larva', 30),
    (2, 'Woodland wildflower', 'semantic_tag', 'Plantae', NULL::TEXT, NULL::TEXT, 'flower', 40),
    (2, 'Reptile or amphibian', 'semantic_tag', NULL::TEXT, NULL::TEXT, NULL::TEXT, 'amphibian', 50),
    (2, 'Animal track or sign', 'semantic_tag', NULL::TEXT, NULL::TEXT, NULL::TEXT, 'track', 60),
    (2, 'Forest habitat species', 'habitat', NULL::TEXT, NULL::TEXT, NULL::TEXT, 'forest', 70),
    (2, 'Native plant', 'semantic_tag', 'Plantae', NULL::TEXT, NULL::TEXT, 'native', 80)
) AS seed(level_number, prompt, match_type, taxonomy_kingdom, taxonomy_class, taxonomy_order, semantic_tag, sort_order)
    ON seed.level_number = l.level_number
ON CONFLICT(level_id, sort_order) DO UPDATE
SET prompt = EXCLUDED.prompt,
    match_type = EXCLUDED.match_type,
    taxonomy_kingdom = EXCLUDED.taxonomy_kingdom,
    taxonomy_class = EXCLUDED.taxonomy_class,
    taxonomy_order = EXCLUDED.taxonomy_order,
    semantic_tag = EXCLUDED.semantic_tag;

DO $$
DECLARE
    function_sql TEXT;
BEGIN
    SELECT PG_GET_FUNCTIONDEF(
        'public.get_explore_author_profile(uuid, uuid, integer)'::REGPROCEDURE
    )
    INTO function_sql;

    function_sql := REPLACE(
        function_sql,
        '    IF visible_post_count = 0 THEN' || CHR(10) ||
        '        RETURN;' || CHR(10) ||
        '    END IF;',
        '    IF visible_post_count = 0 AND NOT public.user_has_visible_field_trip_profile(self_id, target_author_user_id) THEN' || CHR(10) ||
        '        RETURN;' || CHR(10) ||
        '    END IF;'
    );

    IF function_sql NOT LIKE '%user_has_visible_field_trip_profile%' THEN
        RAISE EXCEPTION 'Failed to patch get_explore_author_profile for Field Trip profile visibility';
    END IF;

    EXECUTE function_sql;
END;
$$;

NOTIFY pgrst, 'reload schema';
