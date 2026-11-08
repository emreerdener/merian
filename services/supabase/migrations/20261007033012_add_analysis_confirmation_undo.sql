SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN confirmation_undo_api_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Caller holds canonical owner/generation/history/authority locks. Shared by
-- advisory discovery and the mutation; the original parent revision is NOT a CAS.
CREATE FUNCTION internal.observation_confirmation_undo_eligibility(p_observation UUID,p_analysis UUID)
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
    RETURN pg_catalog.jsonb_build_object('status','available','confirmation_operation_id',prior.operation_id,'confirmation_action',action);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_confirmation_undo_eligibility(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.review_owned_observation_analysis(p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; target UUID; operation UUID;
    expected_revision INTEGER; expected_review INTEGER;
    history internal.observation_histories; evidence internal.observation_analysis_results;
    authority internal.observation_analysis_authorities; saved internal.observation_review_receipts;
    prior_rejection internal.observation_review_receipts;
    eligibility JSONB; response JSONB; review JSONB; next_authority JSONB; origin JSONB; ai_revision INTEGER; species_revision INTEGER;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9 OR pg_catalog.octet_length(p_request::TEXT) > 2048 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.JSONB_OBJECT_KEYS(p_request)) <> 8
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision','action','undo_operation_id']
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
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
    IF p_request->>'action' NOT IN ('reject','undo','undo_confirmation') OR p_request->>'action' IS NULL
        OR (p_request->>'action'='reject' AND p_request->'undo_operation_id' IS DISTINCT FROM 'null'::JSONB)
        OR (p_request->>'action' IN ('undo','undo_confirmation') AND COALESCE(p_request->>'undo_operation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    operation := (p_request ->> 'operation_id')::UUID;
    expected_revision := (p_request ->> 'expected_observation_revision')::INTEGER;
    expected_review := (p_request ->> 'expected_review_revision')::INTEGER;


    PERFORM users.id FROM public.users AS users WHERE users.id=caller FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=observation AND scans.user_id=caller AND NOT scans.is_tombstoned FOR UPDATE;
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
        RETURN saved.receipt;
    END IF;
    IF (SELECT (CASE WHEN p_request->>'action'='undo_confirmation' THEN confirmation_undo_api_enabled ELSE rejection_api_enabled END) AND reader_enabled AND state_reader_enabled
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
        -- Validate the exact stored authority before deriving any transition.
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
            OR (authority.review_snapshot->>'user_review_state'='user_overridden' AND p_request->>'action'<>'undo_confirmation')
            OR NULLIF(review->'community','null'::JSONB) IS NOT NULL THEN
            RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
        END IF;
        IF p_request->>'action'='reject' THEN
            IF COALESCE(review->>'state','clear')<>'clear' THEN
                RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
            END IF;
            origin := pg_catalog.jsonb_build_object('scientific_name',evidence.result_snapshot#>>'{primary_identification,scientific_name}',
                'common_name',evidence.result_snapshot#>>'{primary_identification,common_name}');
            IF NULLIF(evidence.result_snapshot->'primary_identification','null'::JSONB) IS NULL THEN
                SELECT pg_catalog.jsonb_build_object('scientific_name',scientific_name,'common_name',common_names->>'en') INTO origin
                FROM public.species_dictionary WHERE id=(evidence.result_snapshot->>'species_id')::UUID;
            END IF;
        ELSIF p_request->>'action'='undo_confirmation' THEN
            eligibility := internal.observation_confirmation_undo_eligibility(observation,target);
            IF eligibility->>'status' IS DISTINCT FROM 'available'
                OR eligibility->>'confirmation_operation_id' IS DISTINCT FROM p_request->>'undo_operation_id' THEN
                RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
            END IF;
            origin := review->'origin_identification';
        ELSE
            -- Undo names an acknowledged rejection, and both CAS revisions must
            -- still match. It clears rejection; it never recreates confirmation.
            SELECT * INTO prior_rejection FROM internal.observation_review_receipts
            WHERE observation_id=observation AND analysis_id=target AND operation_id=(p_request->>'undo_operation_id')::UUID;
            IF NOT FOUND OR prior_rejection.request_identity->>'action'<>'reject'
                OR prior_rejection.receipt->>'outcome'<>'applied'
                OR prior_rejection.receipt->>'review_revision'<>expected_review::TEXT
                OR review->>'state' IS DISTINCT FROM 'ai_rejected'
                OR review->>'operation_id' IS DISTINCT FROM p_request->>'undo_operation_id' THEN
                RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
            END IF;
            origin := review->'origin_identification';
        END IF;
        review := pg_catalog.jsonb_build_object('version',1,'revision',ai_revision+1,
            'state',CASE WHEN p_request->>'action'='reject' THEN 'ai_rejected' ELSE 'clear' END,
            'origin_scan_id',observation,'origin_identification',origin,'operation_id',operation,
            'operation_digest',pg_catalog.md5(p_request::TEXT),'community',NULL);
        next_authority := pg_catalog.jsonb_build_object('ai_identification_review',review,
            'confirmed_species_identity',NULL,'confirmed_species_identity_revision',species_revision+1,
            'confirmed_species_id',NULL,'user_identification_override',NULL,
            'user_confirmed_identification',FALSE,'user_review_state','unreviewed');
        UPDATE internal.observation_analysis_authorities SET review_revision=expected_review+1,review_snapshot=next_authority
            WHERE observation_id=observation AND analysis_id=target;
        -- The existing authority trigger atomically advances the parent, updates
        -- its projection only for the selected child, and enqueues reconciliation.
        response := p_request || pg_catalog.jsonb_build_object('outcome','applied',
            'observation_revision',history.state_revision+1,'review_revision',expected_review+1);
    END IF;
    INSERT INTO internal.observation_review_receipts(observation_id,analysis_id,operation_id,request_identity,receipt)
        VALUES(observation,target,operation,p_request,response);
    RETURN response;
END;
$$;

CREATE FUNCTION public.get_owned_observation_confirmation_undo(p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE caller UUID := auth.uid(); observation UUID; target UUID;
    history internal.observation_histories; authority internal.observation_analysis_authorities;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9 OR p_request IS NULL
        OR pg_catalog.octet_length(p_request::TEXT)>2048
        OR pg_catalog.jsonb_typeof(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.jsonb_object_keys(p_request))<>5
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','expected_observation_revision','expected_review_revision']
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR COALESCE(p_request->>'observation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request->>'analysis_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.jsonb_typeof(p_request->'expected_observation_revision') IS DISTINCT FROM 'number'
        OR pg_catalog.jsonb_typeof(p_request->'expected_review_revision') IS DISTINCT FROM 'number'
        OR COALESCE(p_request->>'expected_observation_revision','') !~ '^[0-9]{1,10}$'
        OR COALESCE(p_request->>'expected_review_revision','') !~ '^[0-9]{1,10}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF (p_request->>'expected_observation_revision')::BIGINT>2147483646
        OR (p_request->>'expected_review_revision')::BIGINT>2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request->>'observation_id')::UUID; target := (p_request->>'analysis_id')::UUID;
    PERFORM id FROM public.users WHERE id=caller FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=observation AND user_id=caller AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF (SELECT confirmation_undo_api_enabled AND reader_enabled AND state_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities
        WHERE observation_id=observation AND analysis_id=target FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF NOT history.selection_initialized OR history.state_revision::TEXT<>p_request->>'expected_observation_revision'
        OR authority.review_revision::TEXT<>p_request->>'expected_review_revision' THEN
        RETURN p_request || '{"status":"unavailable","reason":"revision_conflict"}'::JSONB;
    END IF;
    RETURN p_request || internal.observation_confirmation_undo_eligibility(observation,target);
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_confirmation_undo(JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_confirmation_undo(JSONB,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('authenticated','public.get_owned_observation_confirmation_undo(jsonb,integer)',
 'Default-off exact-owner/current-ticket confirmation reversal eligibility; no authority or ledger writes.');

COMMENT ON FUNCTION public.review_owned_observation_analysis(JSONB,INTEGER) IS
'Prepared exact-analysis Reject, rejection Undo and confirmation Undo. Owner/deletion checks precede receipt replay; new mutations use independent default-off gates and preserve selection.';

RESET statement_timeout;
RESET lock_timeout;
NOTIFY pgrst, 'reload schema';
