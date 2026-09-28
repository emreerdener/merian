-- A report is a durable viewer preference independent of moderation status.
SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE INDEX idx_explore_post_reports_reporter_post
    ON public.explore_post_reports(reporter_user_id, post_id);

CREATE FUNCTION internal.explore_post_is_reported(viewer_id UUID, target_post_id UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.explore_post_reports r
        WHERE r.reporter_user_id = viewer_id AND r.post_id = target_post_id
    );
$$;
REVOKE ALL ON FUNCTION internal.explore_post_is_reported(UUID,UUID) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.explore_post_is_reported(UUID,UUID) TO service_role;

-- Existing authenticated direct card readers must not gain report-table or
-- internal-schema access. This narrow boolean boundary validates their identity.
CREATE FUNCTION public.viewer_has_reported_explore_post(self_id UUID, target_post_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        PERFORM internal.require_service_role();
    ELSIF auth.uid() IS DISTINCT FROM self_id THEN
        RAISE EXCEPTION 'Authenticated caller does not match self_id' USING ERRCODE = '42501';
    END IF;
    RETURN internal.explore_post_is_reported(self_id, target_post_id);
END;
$$;
REVOKE ALL ON FUNCTION public.viewer_has_reported_explore_post(UUID,UUID) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.viewer_has_reported_explore_post(UUID,UUID) TO authenticated, service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('authenticated', 'public.viewer_has_reported_explore_post(uuid,uuid)', 'Caller-bound report visibility without exposing reports'),
    ('service_role', 'public.viewer_has_reported_explore_post(uuid,uuid)', 'Trusted viewer report visibility projection');

-- Include published snapshots, promotion provenance, and legacy scan media.
-- A promotion's current attribution is not authoritative: the same URL can be
-- promoted again from a different post. Never filter by moderation status.
CREATE FUNCTION internal.explore_media_is_reported(viewer_id UUID, candidate_url TEXT)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.explore_post_reports r
        JOIN public.explore_posts ep ON ep.id = r.post_id
        JOIN public.scans s ON s.id = ep.scan_id
        WHERE r.reporter_user_id = viewer_id AND (
            btrim(candidate_url) = ANY(s.image_storage_urls)
            OR EXISTS (SELECT 1 FROM public.explore_post_media m
                WHERE m.post_id = r.post_id AND btrim(candidate_url) IN (m.url, m.thumbnail_url))
            OR EXISTS (SELECT 1 FROM public.species_reference_image_merian_sources source
                WHERE source.explore_post_id = r.post_id AND source.image_url = btrim(candidate_url))
        )
    );
$$;
REVOKE ALL ON FUNCTION internal.explore_media_is_reported(UUID,TEXT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.explore_media_is_reported(UUID,TEXT) TO service_role;

CREATE FUNCTION public.filter_reported_explore_media(self_id UUID, candidate_urls TEXT[])
RETURNS TEXT[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF self_id IS NULL OR cardinality(candidate_urls) > 500 THEN
        RAISE EXCEPTION 'Invalid media visibility request' USING ERRCODE = '22023';
    END IF;
    RETURN ARRAY(SELECT candidate FROM unnest(candidate_urls) AS urls(candidate)
        WHERE NOT internal.explore_media_is_reported(self_id, candidate));
END;
$$;
REVOKE ALL ON FUNCTION public.filter_reported_explore_media(UUID,TEXT[]) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.filter_reported_explore_media(UUID,TEXT[]) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('service_role', 'public.filter_reported_explore_media(uuid,text[])',
    'Authenticated viewer-specific reference media visibility');

CREATE FUNCTION public.viewer_species_reference_image_urls(
    self_id UUID, target_species_id UUID, legacy_reference_image_url TEXT DEFAULT NULL
) RETURNS TEXT LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    WITH candidates AS (
        SELECT source.priority, image.raw_url, image.ordinality
        FROM (VALUES
            (0, public.public_species_reference_image_urls(target_species_id, NULL)),
            (1, public.public_species_reference_image_urls(NULL, legacy_reference_image_url))
        ) AS source(priority, urls)
        CROSS JOIN LATERAL pg_catalog.regexp_split_to_table(coalesce(source.urls, ''), '\s*,\s*')
            WITH ORDINALITY AS image(raw_url, ordinality)
        WHERE nullif(btrim(image.raw_url), '') IS NOT NULL
          AND NOT internal.explore_media_is_reported(self_id, image.raw_url)
    )
    SELECT string_agg(btrim(raw_url), ',' ORDER BY ordinality) FROM candidates
    WHERE priority = (SELECT min(priority) FROM candidates);
$$;
CREATE FUNCTION public.viewer_species_first_reference_image_url(
    self_id UUID, target_species_id UUID, legacy_reference_image_url TEXT DEFAULT NULL
) RETURNS TEXT LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT nullif(split_part(public.viewer_species_reference_image_urls(
        self_id, target_species_id, legacy_reference_image_url), ',', 1), '');
$$;
CREATE FUNCTION public.viewer_species_reference_image_urls_excluding_media(
    self_id UUID, target_species_id UUID, legacy_reference_image_url TEXT DEFAULT NULL,
    excluded_image_urls TEXT[] DEFAULT ARRAY[]::TEXT[]
) RETURNS TEXT LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT string_agg(btrim(raw_url), ',' ORDER BY ordinality)
    FROM pg_catalog.regexp_split_to_table(coalesce(public.viewer_species_reference_image_urls(
        self_id, target_species_id, legacy_reference_image_url), ''), '\s*,\s*')
        WITH ORDINALITY AS image(raw_url, ordinality)
    WHERE nullif(btrim(raw_url), '') IS NOT NULL
      AND NOT (btrim(raw_url) = ANY(coalesce(excluded_image_urls, ARRAY[]::TEXT[])));
$$;
REVOKE ALL ON FUNCTION public.viewer_species_reference_image_urls(UUID,UUID,TEXT),
    public.viewer_species_first_reference_image_url(UUID,UUID,TEXT),
    public.viewer_species_reference_image_urls_excluding_media(UUID,UUID,TEXT,TEXT[])
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.viewer_species_reference_image_urls(UUID,UUID,TEXT),
    public.viewer_species_first_reference_image_url(UUID,UUID,TEXT),
    public.viewer_species_reference_image_urls_excluding_media(UUID,UUID,TEXT,TEXT[])
    TO service_role;

-- Preserve the public lookalike metadata while selecting a viewer-eligible
-- alternative for each image, including Explore detail's nested projection.
CREATE FUNCTION public.viewer_species_similar_species(self_id UUID, target_species_id UUID)
RETURNS JSONB LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT coalesce(jsonb_agg(entry.value || jsonb_build_object(
        'reference_image_url', public.viewer_species_first_reference_image_url(
            self_id, species.id, species.reference_image_url)) ORDER BY entry.ordinality), '[]'::jsonb)
    FROM jsonb_array_elements(public.public_species_similar_species(target_species_id))
        WITH ORDINALITY AS entry(value, ordinality)
    LEFT JOIN public.species_dictionary species ON species.id = (entry.value->>'species_id')::uuid;
$$;
REVOKE ALL ON FUNCTION public.viewer_species_similar_species(UUID,UUID) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.viewer_species_similar_species(UUID,UUID) TO service_role;

-- These existing INVOKER discussion readers execute behind service-role Edge
-- handlers. Historical ACL hardening removed their source reads; restore only
-- the reads required by those handlers, never client access to report records.
GRANT SELECT ON public.explore_post_comments, public.explore_comment_mentions,
    public.species_lookalikes TO service_role;

-- Retain intervening projection and privilege fixes; reject unexpected source.
DO $migration$
DECLARE routine RECORD; original TEXT; patched TEXT; anchor TEXT; guard_sql TEXT;
BEGIN
    FOR routine IN SELECT * FROM (VALUES
        ('public.explore_projected_post_cards(uuid)', 'ep', 'viewer_id'),
        ('public.get_community_identification_feed(uuid,integer,timestamp with time zone,uuid,double precision,double precision,text,text)', 'explore_post', 'self_id'),
        ('public.get_community_identification_activity(uuid,integer,timestamp with time zone,uuid,text,text)', 'explore_post', 'self_id'),
        ('public.get_community_identification_detail(uuid,uuid)', 'ep', 'self_id'),
        ('public.get_explore_comments(uuid,uuid,integer,timestamp with time zone,uuid)', 'ep', 'self_id'),
        ('public.get_explore_comment_replies(uuid,uuid,integer,timestamp with time zone,uuid)', 'ep', 'self_id'),
        ('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)', 'ep', 'self_id'),
        ('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)', 'ep', 'self_id')
    ) AS targets(signature, post_alias, viewer_argument)
    LOOP
        original := pg_catalog.pg_get_functiondef(routine.signature::regprocedure);
        anchor := routine.post_alias || '.unshared_at IS NULL';
        IF strpos(original, anchor) = 0 THEN
            RAISE EXCEPTION 'Report visibility source drift: %', routine.signature;
        END IF;
        guard_sql := 'NOT public.viewer_has_reported_explore_post(' || routine.viewer_argument || ', ' || routine.post_alias || '.id)';
        patched := replace(original, anchor, anchor || ' AND ' || guard_sql);
        -- The reaction reader has an additional OR branch outside the normal
        -- post predicate. Filter at the Explore CTE's viewer boundary as well.
        IF routine.signature LIKE 'public.get_explore_notifications%' THEN
            anchor := 'WHERE n.user_id = self_id';
            IF strpos(patched, anchor) = 0 THEN RAISE EXCEPTION 'Notification source drift'; END IF;
            patched := overlay(patched placing (anchor || ' AND NOT public.viewer_has_reported_explore_post(self_id, n.post_id)')
                from strpos(patched, anchor) for length(anchor));
        END IF;
        EXECUTE patched;
    END LOOP;
END;
$migration$;

-- Replace only authenticated readers. Anonymous wrappers retain their existing
-- global projection and nullable-viewer behavior.
DO $migration$
DECLARE routine RECORD; original TEXT; patched TEXT;
BEGIN
    FOR routine IN
        SELECT p.oid, p.proname FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
            'get_explore_feed', 'get_explore_feed_liked', 'get_explore_author_posts',
            'get_explore_map_posts', 'get_explore_map_points', 'get_explore_species_posts',
            'get_explore_post_detail', 'search_species_discovery'])
          AND p.proargnames[1] = 'self_id'
    LOOP
        original := pg_catalog.pg_get_functiondef(routine.oid);
        patched := replace(original, 'public.public_species_first_reference_image_url(',
            'public.viewer_species_first_reference_image_url(self_id, ');
        patched := replace(patched, 'public.public_species_reference_image_urls_excluding_media(',
            'public.viewer_species_reference_image_urls_excluding_media(self_id, ');
        patched := replace(patched, 'public.public_species_reference_image_urls(',
            'public.viewer_species_reference_image_urls(self_id, ');
        patched := replace(patched, 'public.public_species_similar_species(',
            'public.viewer_species_similar_species(self_id, ');
        IF patched <> original THEN EXECUTE patched; END IF;
    END LOOP;
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;
