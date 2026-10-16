SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Shared eligibility preserves the admission denial order and generation lock.
-- Preflight is descriptive: no intent, quota, receipt readiness or I/O authority.
CREATE FUNCTION internal.lock_publication_consent_eligibility(
    p_owner UUID, observation UUID, analysis UUID,
    p_expected_observation_revision INTEGER, p_expected_review_revision INTEGER,
    p_taxonomy_version_id UUID, p_initial_taxon_id UUID, p_preflight BOOLEAN)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE history internal.observation_histories; authority internal.observation_analysis_authorities;
    evidence internal.observation_analysis_results; identity JSONB; taxonomy UUID;
BEGIN
    IF p_preflight IS NULL THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    IF (SELECT publication_intent_enabled AND reader_enabled AND media_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO STRICT history FROM internal.observation_histories WHERE observation_id=observation;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=observation AND analysis_id=analysis FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF NOT history.selection_initialized OR (NOT p_preflight AND (p_expected_observation_revision IS NULL OR p_expected_review_revision IS NULL
            OR history.state_revision<>p_expected_observation_revision OR authority.review_revision<>p_expected_review_revision)) THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
    END IF;
    SELECT * INTO STRICT evidence FROM internal.observation_analysis_results WHERE observation_id=observation AND analysis_id=analysis;
    IF evidence.evidence_manifest->'schema_version' IS DISTINCT FROM '2'::JSONB THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    identity:=internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    IF evidence.result_snapshot->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
        OR authority.review_snapshot->>'user_review_state' IS DISTINCT FROM 'unreviewed'
        OR NULLIF(authority.review_snapshot#>'{ai_identification_review,community}','null'::JSONB) IS NOT NULL
        OR EXISTS(SELECT 1 FROM pg_catalog.unnest(ARRAY[identity->>'scientific_name',identity->>'common_name']) name
            WHERE pg_catalog.lower(pg_catalog.btrim(COALESCE(name,''))) IN ('human','humans','human being','person','homo sapiens','homo sapien')) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
    END IF;
    taxonomy:=public.active_taxonomy_version_id();
    IF (NOT p_preflight AND p_taxonomy_version_id IS DISTINCT FROM taxonomy)
        OR (p_initial_taxon_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.taxon_nodes t
            WHERE t.id=p_initial_taxon_id AND t.taxonomy_version_id=p_taxonomy_version_id
                AND pg_catalog.lower(t.scientific_name) NOT IN ('homo sapiens','homo sapien','human')
                AND pg_catalog.lower(COALESCE(t.common_name,'')) NOT IN ('human','humans','human being','person'))) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM public.explore_posts WHERE scan_id=observation)
        OR EXISTS(SELECT 1 FROM public.explore_community_requests WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF p_preflight AND taxonomy IS NULL THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN pg_catalog.jsonb_build_object('expected_observation_revision',history.state_revision,
        'expected_review_revision',authority.review_revision,'taxonomy_version_id',taxonomy,
        'evidence_manifest',evidence.evidence_manifest);
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_publication_consent_eligibility(UUID,UUID,UUID,INTEGER,INTEGER,UUID,UUID,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.resolve_publication_intent_sources(p_owner UUID,p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID:=(p_request->>'observation_id')::UUID; analysis UUID:=(p_request->>'analysis_id')::UUID;
    media JSONB; receipt JSONB; sources JSONB:='[]'::JSONB; total_bytes BIGINT:=0;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_publication_consent_eligibility(p_owner,observation,analysis,
        (p_request->>'expected_observation_revision')::INTEGER,(p_request->>'expected_review_revision')::INTEGER,
        (p_request->>'taxonomy_version_id')::UUID,(p_request->>'initial_taxon_id')::UUID,FALSE);
    FOR media IN SELECT value FROM pg_catalog.jsonb_array_elements(p_request->'media_ids') LOOP
        receipt:=public.resolve_owned_observation_photo(p_owner,observation,analysis,(media#>>'{}')::UUID,8);
        total_bytes:=total_bytes+(receipt->>'byte_count')::BIGINT;
        sources:=sources||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'media_id',receipt->'media_id','object_id',receipt->'object_id','content_type',receipt->'content_type',
            'byte_count',receipt->'byte_count','sha256',receipt->'sha256'));
    END LOOP;
    IF total_bytes>33554432 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    RETURN sources;
END;
$$;
REVOKE ALL ON FUNCTION internal.resolve_publication_intent_sources(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

-- Service-only projection; the HTTP facade supplies its verified owner.
CREATE FUNCTION public.prepare_owned_observation_publication_consent(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE eligible JSONB; candidates JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_observation IS NULL OR p_analysis IS NULL THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    eligible:=internal.lock_publication_consent_eligibility(p_owner,p_observation,p_analysis,NULL,NULL,NULL,NULL,TRUE);
    -- V2 was validated and frozen at analysis admission. Preserve manifest order;
    -- candidate references never expose descriptions, private keys or object IDs.
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('media_id',item->'media_id',
        'content_type',item->'content_type','byte_count',item->'byte_count','sha256',item->'sha256') ORDER BY ordinal)
    INTO candidates FROM pg_catalog.jsonb_array_elements(eligible#>'{evidence_manifest,items}') WITH ORDINALITY AS items(item,ordinal)
    WHERE item->>'kind'='image';
    IF candidates IS NULL OR pg_catalog.jsonb_array_length(candidates) NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN (eligible-'evidence_manifest')||pg_catalog.jsonb_build_object('schema_version',1,
        'observation_id',p_observation,'analysis_id',p_analysis,'initial_taxon_id',NULL,'media',candidates);
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_owned_observation_publication_consent(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_owned_observation_publication_consent(UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.prepare_owned_observation_publication_consent(uuid,uuid,uuid)','Read owner-scoped locked consent candidates, never publication or ready-media authority.');

RESET statement_timeout;
RESET lock_timeout;
