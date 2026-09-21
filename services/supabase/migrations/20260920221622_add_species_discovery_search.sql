-- A searchable public reference document; no observation text or private data.
ALTER TABLE public.species_dictionary
ADD COLUMN discovery_search_document TSVECTOR GENERATED ALWAYS AS (
    pg_catalog.to_tsvector('english'::REGCONFIG,
        COALESCE(scientific_name, '') || ' ' ||
        COALESCE(common_names ->> 'en', '') || ' ' ||
        COALESCE(kingdom, '') || ' ' || COALESCE("class", '') || ' ' ||
        COALESCE("order", '') || ' ' || COALESCE(family, '') || ' ' ||
        COALESCE(genus, '') || ' ' || COALESCE(wikipedia_overview, '') || ' ' ||
        COALESCE(habitat_description, '')
    )
) STORED;

CREATE INDEX idx_species_discovery_search_public
ON public.species_dictionary USING GIN (discovery_search_document)
WHERE is_public_biological = TRUE;

-- Both result tabs use the same unpaginated eligibility predicate. Public posts
-- are joined before pagination, so rare sightings are not lost after page one.
CREATE FUNCTION internal.species_discovery_matches(
    search_text TEXT, group_filter TEXT, name_only BOOLEAN DEFAULT FALSE
) RETURNS TABLE(species_id UUID, match_rank REAL)
LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT species.id,
        CASE WHEN pg_catalog.lower(species.scientific_name) = pg_catalog.lower(search_text)
               OR pg_catalog.lower(species.common_names ->> 'en') = pg_catalog.lower(search_text)
             THEN 2::REAL
             ELSE LEAST(1::REAL, pg_catalog.ts_rank_cd(species.discovery_search_document,
                  pg_catalog.websearch_to_tsquery('english'::REGCONFIG, search_text))) END
    FROM public.species_dictionary species
    WHERE species.is_public_biological = TRUE
      AND CASE WHEN name_only THEN
          pg_catalog.strpos(pg_catalog.lower(species.scientific_name),pg_catalog.lower(search_text)) > 0
          OR pg_catalog.strpos(pg_catalog.lower(species.common_names ->> 'en'),pg_catalog.lower(search_text)) > 0
          OR EXISTS (SELECT 1 FROM pg_catalog.unnest(species.alternative_common_names) name
                     WHERE pg_catalog.strpos(pg_catalog.lower(name),pg_catalog.lower(search_text)) > 0)
        ELSE search_text = '' OR species.discovery_search_document @@
             pg_catalog.websearch_to_tsquery('english'::REGCONFIG, search_text) END
      AND (group_filter IS NULL OR CASE group_filter
        WHEN 'plants' THEN pg_catalog.lower(species.kingdom) = 'plantae' OR 'plant' = ANY(species.group_tags)
        WHEN 'birds' THEN pg_catalog.lower(species."class") = 'aves' OR 'bird' = ANY(species.group_tags)
        WHEN 'insects' THEN pg_catalog.lower(species."class") IN ('insecta','entognatha','arachnida') OR species.group_tags && ARRAY['insect','arachnid']
        WHEN 'fungi' THEN pg_catalog.lower(species.kingdom) = 'fungi' OR species.group_tags && ARRAY['fungus','fungi']
        WHEN 'mammals' THEN pg_catalog.lower(species."class") = 'mammalia' OR 'mammal' = ANY(species.group_tags)
        WHEN 'reptiles_amphibians' THEN pg_catalog.lower(species."class") IN ('reptilia','amphibia') OR pg_catalog.lower(species."order") = 'squamata' OR species.group_tags && ARRAY['reptile','amphibian']
        ELSE FALSE END);
$$;
REVOKE ALL ON FUNCTION internal.species_discovery_matches(TEXT,TEXT,BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION internal.species_discovery_matches(TEXT,TEXT,BOOLEAN) TO service_role;

CREATE FUNCTION public.search_species_discovery(
    self_id UUID, search_text TEXT, group_filter TEXT DEFAULT NULL,
    media_filter TEXT DEFAULT NULL, result_kind TEXT DEFAULT 'species',
    page_cursor JSONB DEFAULT NULL, name_only BOOLEAN DEFAULT FALSE
) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE
    result JSONB;
BEGIN
    IF CURRENT_USER <> 'service_role' THEN
        RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
    END IF;
    IF self_id IS NULL OR search_text IS NULL OR pg_catalog.length(search_text) > 240
       OR (search_text = '' AND group_filter IS NULL)
       OR result_kind NOT IN ('species','sightings')
       OR (group_filter IS NOT NULL AND group_filter NOT IN ('plants','birds','insects','fungi','mammals','reptiles_amphibians'))
       OR (media_filter IS NOT NULL AND media_filter NOT IN ('image','video','audio')) THEN
        RAISE EXCEPTION 'invalid_discovery_search' USING ERRCODE = '22023';
    END IF;

    IF result_kind = 'species' THEN
        WITH matched AS (
            SELECT species.*, matches.match_rank
            FROM internal.species_discovery_matches(search_text, group_filter, name_only) matches
            JOIN public.species_dictionary species ON species.id = matches.species_id
            WHERE page_cursor IS NULL
               OR (matches.match_rank, species.id) < ((page_cursor->>'rank')::REAL, (page_cursor->>'id')::UUID)
            ORDER BY matches.match_rank DESC, species.id DESC LIMIT 21
        ), page AS (
            SELECT * FROM matched ORDER BY match_rank DESC, id DESC LIMIT 20
        )
        SELECT pg_catalog.jsonb_build_object(
            'species', COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                'item', pg_catalog.jsonb_build_object(
                    'id', id, 'scientific_name', scientific_name,
                    'common_name', COALESCE(NULLIF(common_names->>'en',''),scientific_name),
                    'content_quality', NULL,
                    'taxonomy', pg_catalog.jsonb_build_object('kingdom',kingdom,'phylum',phylum,'class',"class",'order',"order",'family',family,'genus',genus),
                    'iucn_red_list_status',iucn_red_list_status,'hazard_type',hazard_type,
                    'group_tags',COALESCE(group_tags,ARRAY[]::TEXT[]),
                    'reference_image_url',public.public_species_first_reference_image_url(id,reference_image_url)),
                'excerpt', pg_catalog.left(CASE WHEN name_only OR search_text = '' THEN
                    COALESCE(NULLIF(wikipedia_overview,''),NULLIF(habitat_description,''),'')
                  ELSE pg_catalog.ts_headline('english'::REGCONFIG,
                    COALESCE(wikipedia_overview,'') || ' ' || COALESCE(habitat_description,''),
                    pg_catalog.websearch_to_tsquery('english'::REGCONFIG,search_text),
                    'StartSel="", StopSel="", MaxFragments=1, MinWords=10, MaxWords=40')
                  END,300)
            ) ORDER BY match_rank DESC,id DESC) FROM page),'[]'::JSONB),
            'sightings','[]'::JSONB,
            'next_cursor', CASE WHEN (SELECT pg_catalog.count(*) FROM matched) > 20 THEN
                (SELECT pg_catalog.jsonb_build_object('id',id,'rank',match_rank,'shared_at',NULL)
                 FROM page ORDER BY match_rank,id LIMIT 1) ELSE NULL END
        ) INTO result;
    ELSE
        WITH matched AS (
            SELECT cards.post_id,cards.scan_id,cards.hero_image_url,cards.shared_at,
                cards.author_user_id,cards.author_name,cards.author_avatar_url,
                cards.species_common_name,cards.species_scientific_name,cards.pet_identification,
                cards.public_location_label,cards.location_sharing,cards.time_of_day,
                cards.current_month,cards.weather_condition,cards.weather_temperature_f,
                cards.like_count,cards.comment_count,cards.viewer_has_liked,
                cards.is_owned_by_viewer,NULL::INTEGER AS ranking_value,cards.media_items,
                public.public_species_first_reference_image_url(species.id,species.reference_image_url) AS reference_thumbnail_url
            FROM public.explore_projected_post_cards(self_id) cards
            JOIN public.scans scan ON scan.id = cards.scan_id
            LEFT JOIN public.explore_observation_projection projection ON projection.post_id = cards.post_id
            LEFT JOIN public.taxon_nodes community_taxon ON community_taxon.id = projection.public_taxon_node_id
            JOIN internal.species_discovery_matches(search_text,group_filter,name_only) matches
              ON matches.species_id = CASE WHEN projection.projection_state::TEXT = 'community_resolved'
                   THEN community_taxon.species_id ELSE COALESCE(scan.confirmed_species_id,scan.species_id) END
            JOIN public.species_dictionary species ON species.id = matches.species_id
            WHERE (page_cursor IS NULL OR (cards.shared_at,cards.post_id) < ((page_cursor->>'shared_at')::TIMESTAMPTZ,(page_cursor->>'id')::UUID))
              AND (media_filter IS NULL OR EXISTS (
                  SELECT 1 FROM public.explore_post_media media
                  WHERE media.post_id = cards.post_id AND media.kind = media_filter
                    AND media.health_status <> 'missing'
              ))
            ORDER BY cards.shared_at DESC,cards.post_id DESC LIMIT 21
        ), page AS (
            SELECT * FROM matched ORDER BY shared_at DESC,post_id DESC LIMIT 20
        )
        SELECT pg_catalog.jsonb_build_object(
            'species','[]'::JSONB,
            'sightings',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(page) ORDER BY shared_at DESC,post_id DESC) FROM page),'[]'::JSONB),
            'next_cursor',CASE WHEN (SELECT pg_catalog.count(*) FROM matched) > 20 THEN
                (SELECT pg_catalog.jsonb_build_object('id',post_id,'rank',NULL,'shared_at',shared_at)
                 FROM page ORDER BY shared_at,post_id LIMIT 1) ELSE NULL END
        ) INTO result;
    END IF;
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.search_species_discovery(UUID,TEXT,TEXT,TEXT,TEXT,JSONB,BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_species_discovery(UUID,TEXT,TEXT,TEXT,TEXT,JSONB,BOOLEAN) TO service_role;
NOTIFY pgrst, 'reload schema';

-- Search has a separate content-free allowance; it never spends scan or chat
-- credits. Existing reserve_ai_quota enforces Gemini consent and account/IP gates.
INSERT INTO internal.ai_quota_policies (
    operation,effective_plan,model,allowed,daily_bucket,daily_limit,
    user_rate_bucket,user_window_seconds,user_window_limit,
    ip_rate_bucket,ip_window_seconds,ip_window_limit
)
SELECT 'species_discovery_search', plan, 'gemini-2.5-flash', TRUE,
       'species_search:' || plan, CASE WHEN plan = 'free' THEN 20 ELSE 120 END,
       'all_ai:' || plan,60,CASE WHEN plan = 'free' THEN 5 WHEN plan = 'pro_paid' THEN 20 ELSE 10 END,
       'all_ai:' || plan,60,CASE WHEN plan = 'free' THEN 30 WHEN plan = 'pro_paid' THEN 120 ELSE 60 END
FROM pg_catalog.unnest(ARRAY['free','pro_trial','pro_complimentary','pro_paid']) plan;
