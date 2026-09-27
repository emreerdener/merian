-- Preserve established Gemini metric meanings only for recorded compatible
-- executions. Historical SQL NULL keeps its prior interpretation; unknown
-- present metadata never inherits Gemini thresholds, ranking, or quality gates.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.identification_metrics_are_gemini_compatible(
    p_value JSONB,
    p_tier TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
IMMUTABLE
PARALLEL SAFE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    is_pro BOOLEAN := p_tier = 'pro';
    audio BOOLEAN;
    expected_generation JSONB;
    compatible BOOLEAN := FALSE;
BEGIN
    IF p_value IS NULL THEN RETURN TRUE; END IF;
    IF internal.identification_provenance_is_valid(p_value) IS NOT TRUE
       OR p_tier IS NULL OR p_tier NOT IN ('flash', 'pro')
       OR p_value ->> 'provider' <> 'gemini'
       OR p_value ->> 'binding' <> 'gemini_baseline_v1'
       OR p_value -> 'policy_version' <> '1'::JSONB
       OR p_value ->> 'model' <> (CASE WHEN is_pro THEN 'gemini-2.5-pro' ELSE 'gemini-2.5-flash' END)
       OR p_value -> 'timeout_ms' <> '90000'::JSONB THEN RETURN FALSE; END IF;

    CASE p_value ->> 'variant'
    WHEN 'audio_compat' THEN
        compatible := p_value ->> 'operation' = 'scan_audio_identification'
            AND p_value ->> 'prompt' = 'identify_audio_compat_v2'
            AND p_value ->> 'schema' = 'merian_audio_v2'
            AND p_value ->> 'confidence' = 'gemini_audio_compat_v2'
            AND p_value -> 'diagnostic_trigger' = 'null'::JSONB
            AND p_value -> 'prompt_diagnostic_trigger' = 'null'::JSONB
            AND p_value -> 'safety' = 'null'::JSONB;
        expected_generation := '{"temperature":0.1,"seed":42,"top_k":null,"max_output_tokens":2048,"thinking_budget":2048}'::JSONB;
    WHEN 'vision_compat' THEN
        compatible := p_value ->> 'operation' = 'scan_identification'
            AND p_value ->> 'prompt' = 'identify_vision_v1'
            AND p_value ->> 'schema' = 'merian_identify_v1'
            AND p_value ->> 'confidence' = 'gemini_vision_compat_v1'
            AND p_value -> 'diagnostic_trigger' = '0.99'::JSONB
            AND p_value -> 'prompt_diagnostic_trigger' = '0.99'::JSONB
            AND p_value ->> 'safety' = 'biological_vision_v1';
        expected_generation := CASE WHEN is_pro THEN
            '{"temperature":0.1,"seed":42,"top_k":40,"max_output_tokens":8192,"thinking_budget":5000}'::JSONB
            ELSE '{"temperature":0.1,"seed":42,"top_k":40,"max_output_tokens":4096,"thinking_budget":2048}'::JSONB END;
    WHEN 'description_compat' THEN
        compatible := p_value ->> 'operation' = 'scan_identification'
            AND p_value ->> 'prompt' = 'identify_describe_v1'
            AND p_value ->> 'schema' = 'merian_describe_v1'
            AND p_value ->> 'confidence' = 'gemini_describe_v1'
            AND p_value -> 'diagnostic_trigger' = 'null'::JSONB
            AND p_value -> 'prompt_diagnostic_trigger' = 'null'::JSONB
            AND p_value -> 'safety' = 'null'::JSONB;
        expected_generation := CASE WHEN is_pro THEN
            '{"temperature":0.15,"seed":42,"top_k":40,"max_output_tokens":4096,"thinking_budget":3000}'::JSONB
            ELSE '{"temperature":0.15,"seed":42,"top_k":40,"max_output_tokens":2048,"thinking_budget":1024}'::JSONB END;
    WHEN 'multimodal' THEN
        audio := p_value ->> 'prompt' = 'identify_audio_v2'
            OR (is_pro AND p_value ->> 'prompt' = 'identify_audio_uncertainty_experiment_v1');
        compatible := p_value ->> 'operation' = 'scan_identification'
            AND (audio OR p_value ->> 'prompt' IN ('identify_vision_v1', 'identify_blended_v1', 'identify_text_v1'))
            AND p_value ->> 'schema' = (CASE WHEN audio THEN 'merian_audio_v2' ELSE 'merian_identify_v1' END)
            AND p_value ->> 'confidence' = (CASE WHEN audio THEN 'gemini_audio_v2' ELSE 'gemini_identify_v1' END)
            AND p_value -> 'diagnostic_trigger' = '0.99'::JSONB
            AND p_value -> 'prompt_diagnostic_trigger' = 'null'::JSONB
            AND p_value -> 'safety' = 'null'::JSONB;
        expected_generation := CASE WHEN is_pro THEN
            '{"temperature":0.1,"seed":42,"top_k":null,"max_output_tokens":8192,"thinking_budget":5000}'::JSONB
            ELSE '{"temperature":0.1,"seed":42,"top_k":null,"max_output_tokens":8192,"thinking_budget":null}'::JSONB END;
    ELSE RETURN FALSE;
    END CASE;
    RETURN COALESCE(compatible AND p_value -> 'generation' = expected_generation, FALSE);
END;
$$;
REVOKE ALL ON FUNCTION internal.identification_metrics_are_gemini_compatible(JSONB, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.identification_metrics_are_gemini_compatible(JSONB, TEXT)
    TO service_role;
COMMENT ON FUNCTION internal.identification_metrics_are_gemini_compatible(JSONB, TEXT) IS
    'Compatibility with existing Gemini confidence and image-quality interpretation, not an empirical calibration or accuracy claim. SQL NULL is legacy; unrecognized present values fail closed.';

-- The SQL label helper is evaluated under the caller's explicit empty path.
-- Qualify the extension operators instead of relying on public in that path.
CREATE OR REPLACE FUNCTION public.community_identification_role_label(
    disagreement_mode public.explore_identification_disagreement,
    withdrawn_at TIMESTAMPTZ,
    taxon_path public.ltree,
    current_path public.ltree
)
RETURNS TEXT
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT CASE
        WHEN withdrawn_at IS NOT NULL THEN 'withdrawn'
        WHEN disagreement_mode = 'maverick' THEN 'maverick'
        WHEN disagreement_mode = 'explicit_disagreement' THEN 'disagreeing'
        WHEN current_path IS NULL THEN 'identifying'
        WHEN taxon_path OPERATOR(public.=) current_path THEN 'supporting'
        WHEN current_path OPERATOR(public.@>) taxon_path THEN 'leading'
        WHEN taxon_path OPERATOR(public.@>) current_path THEN 'broad_support'
        ELSE 'maverick'
    END;
$$;

-- The existing author-profile invoker calls get_user_follow_state. Give the
-- authenticated Edge service caller only the missing read privilege; browser
-- roles, write privileges and table RLS remain unchanged.
GRANT SELECT ON TABLE public.user_follows TO service_role;

DROP FUNCTION public.get_community_identification_detail(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_community_identification_detail(
    self_id UUID,
    target_request_id UUID
)
RETURNS TABLE(
    request_id UUID,
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    requested_at TIMESTAMPTZ,
    status TEXT,
    note TEXT,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    taxonomy_version_id UUID,
    projection_state TEXT,
    consensus_processing_state TEXT,
    current_taxon_id UUID,
    current_common_name TEXT,
    current_scientific_name TEXT,
    current_rank TEXT,
    current_path TEXT,
    initial_taxon_id UUID,
    initial_common_name TEXT,
    initial_scientific_name TEXT,
    initial_rank TEXT,
    initial_path TEXT,
    resolved_taxon_id UUID,
    consensus_score DOUBLE PRECISION,
    identification_count INTEGER,
    viewer_identification_id UUID,
    public_location_label TEXT,
    location_sharing TEXT,
    inference_tier TEXT,
    ai_confidence_qualified BOOLEAN,
    suggested_taxa JSONB,
    identifications JSONB
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT
        ecr.id AS request_id,
        ep.id AS post_id,
        ep.scan_id,
        s.image_storage_urls[1] AS hero_image_url,
        ecr.requested_at,
        ecr.status::TEXT,
        ecr.note,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        ecr.taxonomy_version_id,
        eop.projection_state::TEXT AS projection_state,
        ecr.consensus_processing_state,
        COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id) AS current_taxon_id,
        current_taxon.common_name AS current_common_name,
        current_taxon.scientific_name AS current_scientific_name,
        current_taxon.rank AS current_rank,
        current_taxon.path::TEXT AS current_path,
        ecr.initial_taxon_node_id AS initial_taxon_id,
        initial_taxon.common_name AS initial_common_name,
        initial_taxon.scientific_name AS initial_scientific_name,
        initial_taxon.rank AS initial_rank,
        initial_taxon.path::TEXT AS initial_path,
        ecr.resolved_taxon_node_id AS resolved_taxon_id,
        ecr.consensus_score,
        ecr.consensus_identification_count AS identification_count,
        viewer_identification.id AS viewer_identification_id,
        ep.public_location_label,
        ep.location_sharing,
        s.inference_tier,
        metrics.compatible AS ai_confidence_qualified,
        COALESCE(suggestions.suggested_taxa, '[]'::JSONB) AS suggested_taxa,
        COALESCE(timeline.identifications, '[]'::JSONB) AS identifications
    FROM public.explore_community_requests ecr
    JOIN public.explore_observation_projection eop
        ON eop.community_request_id = ecr.id
    JOIN public.explore_posts ep
        ON ep.id = ecr.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    CROSS JOIN LATERAL (
        SELECT internal.identification_metrics_are_gemini_compatible(
            s.identification_provenance, s.inference_tier
        ) AS compatible
    ) metrics
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.taxon_nodes current_taxon
        ON current_taxon.id = COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id)
    LEFT JOIN public.taxon_nodes initial_taxon
        ON initial_taxon.id = ecr.initial_taxon_node_id
    LEFT JOIN LATERAL (
        SELECT ei.id
        FROM public.explore_identifications ei
        WHERE ei.request_id = ecr.id
          AND ei.user_id = self_id
          AND ei.withdrawn_at IS NULL
        ORDER BY ei.created_at DESC
        LIMIT 1
    ) viewer_identification ON TRUE
    LEFT JOIN LATERAL (
        WITH candidate_suggestions AS (
            SELECT
                candidate_taxon.id AS taxon_id,
                candidate_taxon.taxonomy_version_id,
                candidate_taxon.common_name,
                candidate_taxon.scientific_name,
                candidate_taxon.rank,
                candidate_taxon.path::TEXT AS path,
                candidate_taxon.species_id,
                CASE
                    WHEN metrics.compatible AND (candidate_item.value->>'confidence_score') ~ '^[0-9]+([.][0-9]+)?$'
                        THEN (candidate_item.value->>'confidence_score')::DOUBLE PRECISION
                    ELSE NULL
                END AS confidence_score,
                NULLIF(BTRIM(candidate_item.value->>'distinguishing_feature'), '') AS distinguishing_feature,
                candidate_item.ordinality AS candidate_ordinality
            FROM JSONB_ARRAY_ELEMENTS(
                CASE
                    WHEN JSONB_TYPEOF(s.candidates) = 'array' THEN s.candidates
                    ELSE '[]'::JSONB
                END
            ) WITH ORDINALITY AS candidate_item(value, ordinality)
            JOIN public.taxon_nodes candidate_taxon
                ON candidate_taxon.taxonomy_version_id = ecr.taxonomy_version_id
               AND LOWER(candidate_taxon.scientific_name) = LOWER(BTRIM(candidate_item.value->>'scientific_name'))
            WHERE NULLIF(BTRIM(candidate_item.value->>'scientific_name'), '') IS NOT NULL
        ),
        raw_suggestions AS (
            SELECT
                initial_taxon.id AS taxon_id,
                initial_taxon.taxonomy_version_id,
                initial_taxon.common_name,
                initial_taxon.scientific_name,
                initial_taxon.rank,
                initial_taxon.path::TEXT AS path,
                initial_taxon.species_id,
                'ai_initial'::TEXT AS suggestion_source,
                CASE WHEN metrics.compatible THEN s.ai_confidence_score ELSE NULL END AS confidence_score,
                NULLIF(BTRIM(s.ai_reasoning), '') AS distinguishing_feature,
                0 AS source_rank,
                0::BIGINT AS candidate_ordinality
            WHERE initial_taxon.id IS NOT NULL

            UNION ALL

            SELECT
                taxon_id,
                taxonomy_version_id,
                common_name,
                scientific_name,
                rank,
                path,
                species_id,
                'ai_candidate'::TEXT AS suggestion_source,
                confidence_score,
                distinguishing_feature,
                1 AS source_rank,
                candidate_ordinality
            FROM candidate_suggestions
        ),
        deduped_suggestions AS (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY taxon_id
                    ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality
                ) AS duplicate_rank
            FROM raw_suggestions
        ),
        limited_suggestions AS (
            SELECT *
            FROM deduped_suggestions
            WHERE duplicate_rank = 1
            ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality
            LIMIT 6
        )
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'taxon_id', taxon_id,
                'taxonomy_version_id', taxonomy_version_id,
                'common_name', common_name,
                'scientific_name', scientific_name,
                'rank', rank,
                'path', path,
                'species_id', species_id,
                'suggestion_source', suggestion_source,
                'confidence_score', confidence_score,
                'distinguishing_feature', distinguishing_feature
            )
            ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality
        ) AS suggested_taxa
        FROM limited_suggestions
    ) suggestions ON TRUE
    LEFT JOIN LATERAL (
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'id', ei.id,
                'user_id', ei.user_id,
                'author_name', iu.public_author_name,
                'author_avatar_url', iu.public_avatar_url,
                'taxon_id', tn.id,
                'common_name', tn.common_name,
                'scientific_name', tn.scientific_name,
                'rank', tn.rank,
                'taxonomy_version_id', tn.taxonomy_version_id,
                'disagreement_mode', ei.disagreement_mode,
                'role_label', public.community_identification_role_label(
                    ei.disagreement_mode,
                    ei.withdrawn_at,
                    tn.path,
                    current_taxon.path
                ),
                'is_genus_best_possible', ei.is_genus_best_possible,
                'reasoning', ei.reasoning,
                'created_at', ei.created_at,
                'withdrawn_at', ei.withdrawn_at,
                'is_viewer', ei.user_id = self_id
            )
            ORDER BY ei.created_at DESC, ei.id DESC
        ) AS identifications
        FROM public.explore_identifications ei
        JOIN public.taxon_nodes tn
            ON tn.id = ei.taxon_node_id
        JOIN public.users iu
            ON iu.id = ei.user_id
        WHERE ei.request_id = ecr.id
    ) timeline ON TRUE
    WHERE ecr.id = target_request_id
      AND ecr.withdrawn_at IS NULL
      AND ep.unshared_at IS NULL AND ep.moderated_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_community_identification_detail(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_community_identification_detail(UUID, UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.field_trip_scan_evidence_is_eligible(candidate public.scans)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
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
        AND (
            candidate.confirmed_species_id IS NOT NULL
            OR candidate.user_confirmed_identification IS TRUE
            OR internal.identification_metrics_are_gemini_compatible(
                candidate.identification_provenance, candidate.inference_tier
            )
        )
        AND public.field_trip_scan_identification_is_eligible(
            candidate.ai_confidence_score,
            candidate.inference_tier,
            candidate.confirmed_species_id,
            candidate.user_confirmed_identification
        );
$function$;

REVOKE ALL ON FUNCTION public.field_trip_scan_evidence_is_eligible(public.scans)
    FROM PUBLIC, anon, authenticated, service_role;

-- Human species confirmation does not qualify an unfamiliar image-quality
-- metric. Exclude those scans from both dry-run and live reference promotion.
-- Existing later guards and exact grants on each routine remain intact.
DO $patch$
DECLARE
    change RECORD;
    definition TEXT;
    occurrences INTEGER;
BEGIN
    FOR change IN SELECT * FROM (VALUES
        ('public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)', '''inference_tier'', scan.inference_tier,', '''inference_tier'', scan.inference_tier,
        ''ai_confidence_qualified'', internal.identification_metrics_are_gemini_compatible(scan.identification_provenance, scan.inference_tier),', 1),
        ('public.refresh_merian_reference_images(integer,integer,boolean,double precision)', 'AND COALESCE(s.image_quality_score, -1) >= p_quality_threshold', 'AND internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier)
              AND COALESCE(s.image_quality_score, -1) >= p_quality_threshold', 2),
        ('public.get_explore_author_profile(uuid,uuid,integer)', '            s.ai_confidence_score,', '            s.ai_confidence_score,
            internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier) AS ai_confidence_qualified,', 1),
        ('public.get_explore_author_profile(uuid,uuid,integer)', 'WHERE ai_confidence_score >= 0.98', 'WHERE ai_confidence_qualified AND ai_confidence_score >= 0.98', 2)
    ) AS patches(signature, before_text, after_text, expected_count) LOOP
        definition := pg_catalog.PG_GET_FUNCTIONDEF(change.signature::REGPROCEDURE);
        occurrences := (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, change.before_text, '')))
            / pg_catalog.LENGTH(change.before_text);
        IF occurrences <> change.expected_count THEN
            RAISE EXCEPTION 'Unexpected routine shape for metric compatibility: %', change.signature;
        END IF;
        EXECUTE pg_catalog.REPLACE(definition, change.before_text, change.after_text);
    END LOOP;
END;
$patch$;

DROP TRIGGER IF EXISTS trg_apply_ingested_scan_field_trip_progress_update
    ON public.scans;
CREATE TRIGGER trg_apply_ingested_scan_field_trip_progress_update
AFTER UPDATE OF
    species_id,
    confirmed_species_id,
    ai_confidence_score,
    inference_tier,
    identification_provenance,
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
    OR OLD.identification_provenance IS DISTINCT FROM NEW.identification_provenance
    OR OLD.user_confirmed_identification IS DISTINCT FROM
        NEW.user_confirmed_identification
    OR OLD.user_identification_override IS DISTINCT FROM NEW.user_identification_override
    OR OLD.is_biological_subject IS DISTINCT FROM NEW.is_biological_subject
    OR OLD.is_tombstoned IS DISTINCT FROM NEW.is_tombstoned
    OR OLD.timestamp IS DISTINCT FROM NEW.timestamp
)
EXECUTE FUNCTION public.apply_ingested_scan_field_trip_progress();

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

-- Preserve valid cached responses after reconciling newly ineligible credit.
UPDATE public.field_trip_scan_progress_receipts AS receipt
SET scan_revision = receipt.scan_revision || pg_catalog.JSONB_BUILD_OBJECT(
        'ai_confidence_qualified', internal.identification_metrics_are_gemini_compatible(scan.identification_provenance, scan.inference_tier)
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
NOTIFY pgrst, 'reload schema';
