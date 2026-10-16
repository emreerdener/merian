SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Pure resolver. Caller supplies the exact immutable row under canonical locks.
-- NULL is unsupported/malformed membership, never permission to use client text.
CREATE FUNCTION internal.observation_candidate_name(
    p_analysis UUID,p_result JSONB,p_manifest JSONB,p_reference JSONB)
RETURNS TEXT LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE candidates JSONB; candidate JSONB; name TEXT; position INTEGER;
BEGIN
    IF pg_catalog.jsonb_typeof(p_reference) IS DISTINCT FROM 'object' THEN RETURN NULL; END IF;
    IF (SELECT count(*) FROM pg_catalog.jsonb_object_keys(p_reference))<>4
        OR NOT p_reference ?& ARRAY['version','analysis_id','representation','ordinal']
        OR p_reference->'version' IS DISTINCT FROM '1'::JSONB
        OR p_reference->>'analysis_id' IS DISTINCT FROM p_analysis::TEXT
        OR p_reference->>'representation' IS DISTINCT FROM 'stored_species_candidates_v1'
        OR pg_catalog.jsonb_typeof(p_reference->'ordinal') IS DISTINCT FROM 'number'
        OR COALESCE(p_reference->>'ordinal','') !~ '^[0-1]$'
        OR p_manifest->'schema_version' IS NULL
        OR p_manifest->'schema_version' NOT IN ('1'::JSONB,'2'::JSONB)
        OR p_result->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
        OR p_result#>>'{primary_identification,resolution}' IS DISTINCT FROM 'species' THEN RETURN NULL; END IF;
    candidates:=p_result->'candidates';
    IF pg_catalog.jsonb_typeof(candidates) IS DISTINCT FROM 'array' THEN RETURN NULL; END IF;
    IF pg_catalog.jsonb_array_length(candidates) NOT BETWEEN 1 AND 2 THEN RETURN NULL; END IF;
    IF EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(candidates) AS entry(value)
        WHERE pg_catalog.jsonb_typeof(value) IS DISTINCT FROM 'object'
        OR value->>'taxon_rank' IS DISTINCT FROM 'species') THEN RETURN NULL; END IF;
    position:=(p_reference->>'ordinal')::INTEGER;
    candidate:=candidates->position;
    IF pg_catalog.jsonb_typeof(candidate) IS DISTINCT FROM 'object'
        OR candidate->>'taxon_rank' IS DISTINCT FROM 'species'
        OR pg_catalog.jsonb_typeof(candidate->'scientific_name') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(candidate->'confidence_score') IS DISTINCT FROM 'number' THEN RETURN NULL; END IF;
    IF (candidate->>'confidence_score')::NUMERIC NOT BETWEEN 0 AND 1 THEN RETURN NULL; END IF;
    name:=candidate->>'scientific_name';
    IF length(name) NOT BETWEEN 1 AND 160 OR btrim(name)<>name OR name ~ '[[:cntrl:]]' THEN RETURN NULL; END IF;
    RETURN name;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_candidate_name(UUID,JSONB,JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.confirm_observation_analysis(
    p_user_id UUID,p_request JSONB,p_reader INTEGER,p_complete BOOLEAN,
    p_verified_name TEXT,p_taxon JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE
    observation UUID; target UUID; operation UUID;
    expected_revision INTEGER; expected_review INTEGER;
    history internal.observation_histories; evidence internal.observation_analysis_results;
    authority internal.observation_analysis_authorities; saved internal.observation_review_receipts;
    intent internal.observation_confirmation_intents;
    response JSONB; review JSONB; next_authority JSONB; origin JSONB;
    ai_revision INTEGER; species_revision INTEGER; name TEXT;
    species UUID; saved_name TEXT; identity JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR p_reader IS DISTINCT FROM 9 OR pg_catalog.octet_length(p_request::TEXT) > 2048 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.JSONB_OBJECT_KEYS(p_request)) <>
            (CASE WHEN p_request->'schema_version'='2'::JSONB THEN 9 ELSE 8 END)
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision','action','scientific_name']
        OR p_request->'schema_version' IS NULL
        OR p_request->'schema_version' NOT IN ('1'::JSONB,'2'::JSONB)
        OR (p_request->'schema_version'='2'::JSONB AND (
            NOT p_request ? 'candidate_reference' OR p_request->>'action' IS DISTINCT FROM 'confirm_name'))
        OR COALESCE(p_request ->> 'observation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'analysis_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'operation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_observation_revision') IS DISTINCT FROM 'number'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_review_revision') IS DISTINCT FROM 'number'
        OR COALESCE(p_request ->> 'expected_observation_revision','') !~ '^[0-9]{1,10}$'
        OR COALESCE(p_request ->> 'expected_review_revision','') !~ '^[0-9]{1,10}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (p_request ->> 'expected_observation_revision')::BIGINT > 2147483646
        OR (p_request ->> 'expected_review_revision')::BIGINT > 2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF p_request->>'action' NOT IN ('confirm_primary','confirm_name') OR p_request->>'action' IS NULL
        OR (p_request->>'action'='confirm_primary' AND p_request->'scientific_name' IS DISTINCT FROM 'null'::JSONB)
        OR (p_request->>'action'='confirm_name' AND (
            pg_catalog.jsonb_typeof(p_request->'scientific_name') IS DISTINCT FROM 'string'
            OR length(p_request->>'scientific_name') NOT BETWEEN 1 AND 160
            OR btrim(p_request->>'scientific_name') IS DISTINCT FROM p_request->>'scientific_name'
            OR p_request->>'scientific_name' ~ '[[:cntrl:]]')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF p_request->'schema_version'='2'::JSONB THEN
        IF pg_catalog.jsonb_typeof(p_request->'candidate_reference') IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF (SELECT count(*) FROM pg_catalog.jsonb_object_keys(p_request->'candidate_reference'))<>4
            OR NOT (p_request->'candidate_reference') ?& ARRAY['version','analysis_id','representation','ordinal']
            OR p_request#>'{candidate_reference,version}' IS DISTINCT FROM '1'::JSONB
            OR p_request#>'{candidate_reference,analysis_id}' IS DISTINCT FROM p_request->'analysis_id'
            OR p_request#>>'{candidate_reference,representation}' IS DISTINCT FROM 'stored_species_candidates_v1'
            OR pg_catalog.jsonb_typeof(p_request#>'{candidate_reference,ordinal}') IS DISTINCT FROM 'number'
            OR COALESCE(p_request#>>'{candidate_reference,ordinal}','') !~ '^[0-1]$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    operation := (p_request ->> 'operation_id')::UUID;
    expected_revision := (p_request ->> 'expected_observation_revision')::INTEGER;
    expected_review := (p_request ->> 'expected_review_revision')::INTEGER;


    PERFORM users.id FROM public.users AS users WHERE users.id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=observation AND scans.user_id=p_user_id AND NOT scans.is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO saved FROM internal.observation_review_receipts WHERE observation_id=observation AND operation_id=operation;
    IF FOUND THEN
        IF saved.request_identity IS DISTINCT FROM p_request THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN pg_catalog.jsonb_build_object('schema_version',1,'status','complete','receipt',saved.receipt);
    END IF;
    SELECT * INTO intent FROM internal.observation_confirmation_intents WHERE observation_id=observation AND operation_id=operation;
    IF FOUND AND intent.request_identity IS DISTINCT FROM p_request THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF p_complete AND intent.operation_id IS NULL THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF (SELECT confirmation_api_enabled AND reader_enabled AND state_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO evidence FROM internal.observation_analysis_results WHERE observation_id=observation AND analysis_id=target;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=observation AND analysis_id=target FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    response := p_request || pg_catalog.jsonb_build_object('outcome','revision_conflict');
    IF history.selection_initialized AND history.state_revision=expected_revision AND authority.review_revision=expected_review THEN
        IF history.state_revision>=2147483646 OR authority.review_revision>=2147483646 THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF NOT authority.review_snapshot ?& ARRAY['ai_identification_review','confirmed_species_identity',
            'confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']
            OR authority.review_snapshot-ARRAY['ai_identification_review','confirmed_species_identity',
            'confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']<>'{}'::JSONB THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        PERFORM internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
        review := NULLIF(authority.review_snapshot->'ai_identification_review','null'::JSONB);
        ai_revision := COALESCE((review->>'revision')::INTEGER,0);
        species_revision := (authority.review_snapshot->>'confirmed_species_identity_revision')::INTEGER;
        IF ai_revision>=999999999 OR species_revision IS NULL OR species_revision>=2147483646 THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF evidence.result_snapshot->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
            OR NULLIF(review->'community','null'::JSONB) IS NOT NULL THEN
            RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
        END IF;
        IF NULLIF(evidence.result_snapshot->'primary_identification','null'::JSONB) IS NULL THEN
            RAISE EXCEPTION 'species_review_requires_primary' USING ERRCODE='22023';
        END IF;
        IF p_request->>'action'='confirm_primary' THEN
            IF evidence.result_snapshot#>>'{primary_identification,resolution}' IS DISTINCT FROM 'species' THEN
                RAISE EXCEPTION 'species_review_primary_not_species' USING ERRCODE='22023';
            END IF;
            name := evidence.result_snapshot#>>'{primary_identification,scientific_name}';
        ELSIF p_request->'schema_version'='2'::JSONB THEN
            name := internal.observation_candidate_name(target,evidence.result_snapshot,evidence.evidence_manifest,p_request->'candidate_reference');
            IF name IS NULL OR name IS DISTINCT FROM p_request->>'scientific_name' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
        ELSE
            name := p_request->>'scientific_name';
        END IF;
        IF name IS NULL OR length(name) NOT BETWEEN 1 AND 160 OR btrim(name)<>name OR name ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF intent.operation_id IS NOT NULL AND intent.scientific_name IS DISTINCT FROM name THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF NOT p_complete THEN
            INSERT INTO internal.observation_confirmation_intents(observation_id,analysis_id,operation_id,request_identity,scientific_name)
                VALUES(observation,target,operation,p_request,name) ON CONFLICT(observation_id,operation_id) DO NOTHING;
            RETURN pg_catalog.jsonb_build_object('schema_version',1,'status','verify','request',p_request,'scientific_name',name);
        END IF;
        IF p_verified_name IS DISTINCT FROM intent.scientific_name THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF p_taxon IS NULL THEN
            response := p_request || pg_catalog.jsonb_build_object('outcome','not_verified');
        ELSE
            -- Only the service endpoint supplies freshly verified proof. A synonym's
            -- accepted canonical name may legitimately differ from the frozen query.
            species := public.resolve_verified_dictionary_species(p_taxon);
            SELECT scientific_name INTO STRICT saved_name FROM public.species_dictionary
                WHERE id=species AND is_public_biological AND gbif_taxon_key=(p_taxon->>'gbif_taxon_key')::INTEGER FOR SHARE;
            identity := pg_catalog.jsonb_build_object('version',1,'species_id',species,
                'scientific_name',saved_name,'common_name',NULL,'gbif_taxon_key',p_taxon->'gbif_taxon_key');
            IF NOT internal.confirmed_species_identity_is_valid(identity) THEN
                RAISE EXCEPTION 'invalid_verified_species' USING ERRCODE='22023';
            END IF;
            origin := COALESCE(review->'origin_identification',pg_catalog.jsonb_build_object(
                'scientific_name',evidence.result_snapshot#>>'{primary_identification,scientific_name}',
                'common_name',evidence.result_snapshot#>>'{primary_identification,common_name}'));
            -- Explicit acceptance clears rejection of this child only. Selection
            -- never invokes this transition or transfers another child's review.
            review := pg_catalog.jsonb_build_object('version',1,'revision',ai_revision+1,'state','clear',
                'origin_scan_id',COALESCE(review->>'origin_scan_id',observation::TEXT),
                'origin_identification',origin,'operation_id',operation,
                'operation_digest',pg_catalog.md5(p_request::TEXT),'community',NULL);
            next_authority := pg_catalog.jsonb_build_object('ai_identification_review',review,
                'confirmed_species_identity',identity,'confirmed_species_identity_revision',species_revision+1,
                'confirmed_species_id',species,
                'user_identification_override',CASE WHEN p_request->>'action'='confirm_name' THEN name ELSE NULL END,
                'user_confirmed_identification',p_request->>'action'='confirm_primary',
                'user_review_state',CASE WHEN p_request->>'action'='confirm_primary' THEN 'ai_confirmed' ELSE 'user_overridden' END);
            PERFORM internal.observation_analysis_projection(evidence.result_snapshot,next_authority);
            UPDATE internal.observation_analysis_authorities SET review_revision=expected_review+1,review_snapshot=next_authority
                WHERE observation_id=observation AND analysis_id=target;
            response := p_request || pg_catalog.jsonb_build_object('outcome','applied',
                'observation_revision',history.state_revision+1,'review_revision',expected_review+1);
        END IF;
    END IF;
    INSERT INTO internal.observation_review_receipts(observation_id,analysis_id,operation_id,request_identity,receipt)
        VALUES(observation,target,operation,p_request,response);
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'status','complete','receipt',response);
END;
$$;
REVOKE ALL ON FUNCTION internal.confirm_observation_analysis(UUID,JSONB,INTEGER,BOOLEAN,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.observation_confirmation_undo_eligibility(p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE authority internal.observation_analysis_authorities; prior internal.observation_review_receipts;
    evidence internal.observation_analysis_results; review JSONB; action TEXT;
BEGIN
    SELECT * INTO STRICT authority FROM internal.observation_analysis_authorities
        WHERE observation_id=p_observation AND analysis_id=p_analysis;
    SELECT * INTO STRICT evidence FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND analysis_id=p_analysis;
    PERFORM internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    review := NULLIF(authority.review_snapshot->'ai_identification_review','null'::JSONB);
    IF NULLIF(review->'community','null'::JSONB) IS NOT NULL THEN
        RETURN '{"status":"unavailable","reason":"community_authority"}'::JSONB;
    END IF;
    IF authority.review_snapshot->>'user_review_state' NOT IN ('ai_confirmed','user_overridden')
        OR COALESCE(review->>'state','clear')<>'clear' THEN
        RETURN '{"status":"unavailable","reason":"not_confirmed"}'::JSONB;
    END IF;
    SELECT * INTO prior FROM internal.observation_review_receipts
        WHERE observation_id=p_observation AND analysis_id=p_analysis AND operation_id::TEXT=review->>'operation_id';
    IF NOT FOUND THEN
        RETURN '{"status":"unavailable","reason":"receipt_unavailable"}'::JSONB;
    END IF;
    action := prior.request_identity->>'action';
    IF action NOT IN ('confirm_primary','confirm_name') OR action IS NULL
        OR prior.receipt->>'outcome' IS DISTINCT FROM 'applied'
        OR prior.receipt->>'review_revision' IS DISTINCT FROM authority.review_revision::TEXT
        OR review->>'operation_digest' IS DISTINCT FROM pg_catalog.md5(prior.request_identity::TEXT)
        OR (action='confirm_primary' AND (authority.review_snapshot->>'user_review_state'<>'ai_confirmed'
            OR authority.review_snapshot->'user_confirmed_identification' IS DISTINCT FROM 'true'::JSONB))
        OR (action='confirm_name' AND (authority.review_snapshot->>'user_review_state'<>'user_overridden'
            OR authority.review_snapshot->'user_confirmed_identification' IS DISTINCT FROM 'false'::JSONB
            OR authority.review_snapshot->>'user_identification_override' IS DISTINCT FROM prior.request_identity->>'scientific_name')) THEN
        RETURN '{"status":"unavailable","reason":"confirmation_changed"}'::JSONB;
    END IF;
    IF prior.request_identity->'schema_version'='2'::JSONB AND (
        action IS DISTINCT FROM 'confirm_name'
        OR internal.observation_candidate_name(p_analysis,evidence.result_snapshot,evidence.evidence_manifest,prior.request_identity->'candidate_reference') IS DISTINCT FROM prior.request_identity->>'scientific_name'
        OR prior.request_identity->>'scientific_name' IS NULL) THEN
        RETURN '{"status":"unavailable","reason":"confirmation_changed"}'::JSONB;
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','available','confirmation_operation_id',prior.operation_id,'confirmation_action',action);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_confirmation_undo_eligibility(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;
NOTIFY pgrst, 'reload schema';
