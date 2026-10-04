SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- This durable intent precedes moderation/public copy. It authorizes neither.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN publication_intent_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_publication_intents (
    operation_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    request JSONB NOT NULL CHECK(pg_catalog.octet_length(request::TEXT)<=4096),
    sources JSONB NOT NULL CHECK(pg_catalog.jsonb_typeof(sources)='array'
        AND pg_catalog.jsonb_array_length(sources) BETWEEN 1 AND 6
        AND pg_catalog.octet_length(sources::TEXT)<=8192),
    prepared_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.now(),
    FOREIGN KEY(observation_id,analysis_id) REFERENCES internal.observation_analysis_results(observation_id,analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_publication_intents_analysis_idx ON internal.observation_publication_intents(observation_id,analysis_id);
ALTER TABLE internal.observation_publication_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_intents FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_publication_intent BEFORE INSERT OR UPDATE ON internal.observation_publication_intents
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_publication_intent_update BEFORE UPDATE ON internal.observation_publication_intents
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- The caller passes only a request admitted by the exact-shape owner below.
-- Resolve source facts from immutable V2 evidence plus ready private receipts,
-- never from client URLs, scan media arrays or a saved/imported V3 presentation.
CREATE FUNCTION internal.resolve_publication_intent_sources(p_owner UUID,p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID:=(p_request->>'observation_id')::UUID; analysis UUID:=(p_request->>'analysis_id')::UUID;
    history internal.observation_histories; authority internal.observation_analysis_authorities;
    evidence internal.observation_analysis_results; identity JSONB; media JSONB; receipt JSONB;
    sources JSONB:='[]'::JSONB; total_bytes BIGINT:=0;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    IF (SELECT publication_intent_enabled AND reader_enabled AND media_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO STRICT history FROM internal.observation_histories WHERE observation_id=observation;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=observation AND analysis_id=analysis FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF NOT history.selection_initialized OR history.state_revision<>(p_request->>'expected_observation_revision')::INTEGER
        OR authority.review_revision<>(p_request->>'expected_review_revision')::INTEGER THEN
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
    IF (p_request->>'taxonomy_version_id')::UUID IS DISTINCT FROM public.active_taxonomy_version_id()
        OR (p_request->'initial_taxon_id'<>'null'::JSONB AND NOT EXISTS(SELECT 1 FROM public.taxon_nodes t
            WHERE t.id=(p_request->>'initial_taxon_id')::UUID AND t.taxonomy_version_id=(p_request->>'taxonomy_version_id')::UUID
                AND pg_catalog.lower(t.scientific_name) NOT IN ('homo sapiens','homo sapien','human')
                AND pg_catalog.lower(COALESCE(t.common_name,'')) NOT IN ('human','humans','human being','person'))) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM public.explore_posts WHERE scan_id=observation)
        OR EXISTS(SELECT 1 FROM public.explore_community_requests WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
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

CREATE FUNCTION internal.prepare_observation_publication_intent(p_owner UUID,p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID; analysis UUID; operation UUID; saved internal.observation_publication_intents;
    key TEXT; media JSONB; ids UUID[]:='{}'::UUID[]; sources JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR pg_catalog.jsonb_typeof(p_request) IS DISTINCT FROM 'object'
        OR pg_catalog.octet_length(p_request::TEXT)>4096 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision','taxonomy_version_id','initial_taxon_id','note','media_ids']
        OR p_request-ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision','taxonomy_version_id','initial_taxon_id','note','media_ids']<>'{}'::JSONB
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH key IN ARRAY ARRAY['observation_id','analysis_id','operation_id','taxonomy_version_id','initial_taxon_id'] LOOP
        IF key='initial_taxon_id' AND p_request->key='null'::JSONB THEN CONTINUE; END IF;
        IF pg_catalog.jsonb_typeof(p_request->key) IS DISTINCT FROM 'string'
            OR p_request->>key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    FOREACH key IN ARRAY ARRAY['expected_observation_revision','expected_review_revision'] LOOP
        IF pg_catalog.jsonb_typeof(p_request->key) IS DISTINCT FROM 'number' OR p_request->>key !~ '^[0-9]{1,10}$'
            OR (p_request->>key)::BIGINT NOT BETWEEN 0 AND 2147483646 THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF (p_request->'note'<>'null'::JSONB AND (pg_catalog.jsonb_typeof(p_request->'note') IS DISTINCT FROM 'string'
        OR pg_catalog.char_length(p_request->>'note')>1000)) OR pg_catalog.jsonb_typeof(p_request->'media_ids') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.jsonb_array_length(p_request->'media_ids') NOT BETWEEN 1 AND 6 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOR media IN SELECT value FROM pg_catalog.jsonb_array_elements(p_request->'media_ids') LOOP
        IF pg_catalog.jsonb_typeof(media) IS DISTINCT FROM 'string'
            OR media#>>'{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF (media#>>'{}')::UUID=ANY(ids) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        ids:=pg_catalog.array_append(ids,(media#>>'{}')::UUID);
    END LOOP;
    observation:=(p_request->>'observation_id')::UUID; analysis:=(p_request->>'analysis_id')::UUID; operation:=(p_request->>'operation_id')::UUID;
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    SELECT * INTO saved FROM internal.observation_publication_intents WHERE operation_id=operation;
    IF FOUND THEN
        IF ROW(saved.owner_id,saved.observation_id,saved.analysis_id,saved.request) IS DISTINCT FROM ROW(p_owner,observation,analysis,p_request) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- This is frozen preparation evidence only. It is never current authority
        -- to dispatch, copy, publish, or settle a provider reservation.
        RETURN pg_catalog.jsonb_build_object('schema_version',1,'request',saved.request,'sources',saved.sources);
    END IF;
    sources:=internal.resolve_publication_intent_sources(p_owner,p_request);
    BEGIN
        INSERT INTO internal.observation_publication_intents(operation_id,observation_id,analysis_id,owner_id,request,sources)
        VALUES(operation,observation,analysis,p_owner,p_request,sources);
    EXCEPTION WHEN unique_violation THEN
        -- Different owners/observations hold different generation locks. A global
        -- operation collision must reveal neither source facts nor constraint names.
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END;
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'request',p_request,'sources',sources);
END;
$$;
REVOKE ALL ON FUNCTION internal.prepare_observation_publication_intent(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.revalidate_observation_publication_intent(p_owner UUID,p_observation UUID,p_operation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_publication_intents; sources JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_publication_intents WHERE operation_id=p_operation AND observation_id=p_observation AND owner_id=p_owner;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    sources:=internal.resolve_publication_intent_sources(p_owner,saved.request);
    IF sources IS DISTINCT FROM saved.sources THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'request',saved.request,'sources',sources);
END;
$$;
REVOKE ALL ON FUNCTION internal.revalidate_observation_publication_intent(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;
