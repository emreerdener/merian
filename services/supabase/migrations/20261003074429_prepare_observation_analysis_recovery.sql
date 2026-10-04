SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN orchestration_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE internal.observation_analysis_intents
    ADD COLUMN provider_outcome JSONB CHECK(jsonb_typeof(provider_outcome)='object' AND octet_length(provider_outcome::TEXT)<=1048576),
    ADD COLUMN work_token UUID,
    ADD COLUMN work_expires_at TIMESTAMPTZ,
    ADD COLUMN recover_after TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    ADD CONSTRAINT observation_analysis_work_pair CHECK((work_token IS NULL)=(work_expires_at IS NULL));
CREATE INDEX observation_analysis_recoverable ON internal.observation_analysis_intents(recover_after,analysis_id)
    WHERE state='draft' OR (state='dispatched' AND provider_outcome IS NOT NULL);

-- All worker operations retain the owner -> parent generation -> scan -> history
-- lock order. A worker claim never authorizes another provider execution.
CREATE FUNCTION internal.claim_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_analysis_intents
        WHERE owner_id=p_owner AND observation_id=p_observation AND analysis_id=p_analysis FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF saved.state IN ('complete','failed_terminal')
        OR (saved.state='dispatched' AND saved.provider_outcome IS NULL)
        OR saved.work_expires_at>clock_timestamp() THEN
        RETURN jsonb_build_object('state',saved.state,'claimed',FALSE);
    END IF;
    UPDATE internal.observation_analysis_intents SET work_token=gen_random_uuid(),
        work_expires_at=clock_timestamp()+INTERVAL '120 seconds'
        WHERE analysis_id=p_analysis RETURNING * INTO saved;
    -- Edge-private; never serialize this response to a user.
    RETURN jsonb_build_object('state',saved.state,'claimed',TRUE,'work_token',saved.work_token,
        'input',saved.input_snapshot,'quota',saved.quota,'provider_outcome',saved.provider_outcome);
END;
$$;
REVOKE ALL ON FUNCTION internal.claim_observation_analysis(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.begin_owned_observation_analysis(p_owner UUID,p_input JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=(p_input->>'analysis_id')::UUID AND state<>'admitted')
        AND (SELECT admission_enabled AND dispatch_enabled AND append_enabled
            AND (p_input->'schema_version'<>'2'::JSONB OR (protected_analysis_enabled AND media_enabled))
            FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF p_input->'schema_version'='2'::JSONB THEN
        PERFORM internal.admit_protected_observation_analysis(p_owner,p_input,p_ip_hash);
    ELSE
        PERFORM internal.admit_observation_analysis(p_owner,p_input,p_ip_hash);
    END IF;
    RETURN internal.claim_observation_analysis(p_owner,(p_input->>'observation_id')::UUID,(p_input->>'analysis_id')::UUID);
END;
$$;

-- Recovery is restricted to already received outcomes/drafts. It never renews
-- client claims, consent, quota admission, or an uncertain provider dispatch.
CREATE FUNCTION public.claim_observation_analysis_recovery(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis
        AND observation_id=p_observation AND owner_id=p_owner
        AND (state='draft' OR (state='dispatched' AND provider_outcome IS NOT NULL))) THEN
        RETURN jsonb_build_object('claimed',FALSE);
    END IF;
    RETURN internal.claim_observation_analysis(p_owner,p_observation,p_analysis);
END;
$$;

CREATE FUNCTION public.list_observation_analysis_recovery()
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- Discovery is a hint, not a lock or authority. Claim rechecks deletion and
    -- ownership in the same order as foreground work; never lock children first.
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(candidate)) FROM (
        SELECT owner_id,observation_id,analysis_id FROM internal.observation_analysis_intents
        WHERE (state='draft' OR (state='dispatched' AND provider_outcome IS NOT NULL))
          AND recover_after<=clock_timestamp() AND (work_expires_at IS NULL OR work_expires_at<=clock_timestamp())
        ORDER BY recover_after,analysis_id LIMIT 10
    ) candidate),'[]'::JSONB);
END;
$$;

CREATE FUNCTION public.advance_owned_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID,p_work UUID,p_operation TEXT,p_payload JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; quota_token UUID; answer JSONB; evidence JSONB; species UUID; species_name TEXT; result JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF p_operation IS NULL OR p_operation NOT IN ('materialize','dispatch','outcome','draft','complete','fail','release','cancel_uninvoked','resolve_species')
        OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::TEXT)>2097152 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_analysis_intents
        WHERE owner_id=p_owner AND observation_id=p_observation AND analysis_id=p_analysis FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    quota_token:=(saved.quota->>'lease_token')::UUID;
    -- A late response is still evidence for the one admitted execution. Accept
    -- it after work-lease expiry only with the unchanged dispatch quota token.
    IF p_operation='outcome' THEN
        IF p_payload-ARRAY['quota_token','value']<>'{}' OR NOT(p_payload ?& ARRAY['quota_token','value'])
            OR p_payload->>'quota_token' IS DISTINCT FROM quota_token::TEXT
            OR jsonb_typeof(p_payload->'value') IS DISTINCT FROM 'object'
            OR (p_payload->'value')-ARRAY['schema_version','provenance','outcome','usage']<>'{}'
            OR NOT((p_payload->'value') ?& ARRAY['schema_version','provenance','outcome','usage'])
            OR p_payload#>'{value,schema_version}' IS DISTINCT FROM '1'::JSONB
            OR octet_length((p_payload->'value')::TEXT)>1048576
            OR p_payload#>>'{value,outcome,kind}' IS NULL
            OR p_payload#>>'{value,outcome,kind}' NOT IN ('draft','refusal','invalid_output')
            OR jsonb_typeof(p_payload#>'{value,usage}') IS DISTINCT FROM 'object'
            OR octet_length((p_payload#>'{value,usage}')::TEXT)>2048
            OR (p_payload#>'{value,usage}')-ARRAY['input_tokens','cached_tokens','cache_write_tokens','output_tokens','candidate_tokens','thinking_tokens','tool_tokens','total_tokens','service_tier','modality_breakdown']<>'{}'
            OR NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE id=saved.invocation_id AND provenance=p_payload#>'{value,provenance}') THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF saved.provider_outcome IS NOT NULL THEN
            IF saved.provider_outcome IS DISTINCT FROM p_payload->'value' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
            RETURN '{}'::JSONB;
        END IF;
        IF saved.state<>'dispatched' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        UPDATE internal.observation_analysis_intents SET provider_outcome=p_payload->'value',recover_after=clock_timestamp()
            WHERE analysis_id=p_analysis;
        RETURN '{}'::JSONB;
    END IF;
    IF p_work IS NULL OR saved.work_token IS DISTINCT FROM p_work OR saved.work_expires_at<=clock_timestamp() THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF p_operation IN ('materialize','complete','release','cancel_uninvoked','resolve_species') AND p_payload<>'{}' THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF p_operation='release' THEN
        UPDATE internal.observation_analysis_intents SET work_token=NULL,work_expires_at=NULL,
            recover_after=clock_timestamp()+INTERVAL '60 seconds' WHERE analysis_id=p_analysis;
        RETURN '{}'::JSONB;
    ELSIF p_operation='materialize' THEN
        IF saved.state<>'admitted' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        evidence:=saved.input_snapshot->'evidence_manifest';
        IF evidence->'schema_version'='2'::JSONB THEN
            PERFORM internal.assert_protected_analysis_evidence(p_owner,p_observation,p_analysis,evidence,FALSE);
            RETURN COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM internal.observation_evidence_objects e
                WHERE analysis_id=p_analysis AND owner_id=p_owner AND observation_id=p_observation),'[]'::JSONB);
        END IF;
        RETURN '[]'::JSONB;
    ELSIF p_operation='dispatch' THEN
        IF (SELECT admission_enabled AND dispatch_enabled AND append_enabled
            AND (saved.input_snapshot->'schema_version'<>'2'::JSONB OR (protected_analysis_enabled AND media_enabled))
            FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF p_payload-'provenance'<>'{}' OR NOT(p_payload ? 'provenance') THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        IF saved.input_snapshot->'schema_version'='2'::JSONB THEN
            PERFORM internal.assert_protected_analysis_evidence(p_owner,p_observation,p_analysis,saved.input_snapshot->'evidence_manifest',FALSE);
        END IF;
        RETURN internal.dispatch_observation_analysis(p_owner,p_observation,p_analysis,quota_token,p_payload->'provenance');
    ELSIF p_operation='resolve_species' THEN
        IF saved.state<>'dispatched' OR saved.provider_outcome#>>'{outcome,kind}' IS DISTINCT FROM 'draft' THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        result:=saved.provider_outcome#>'{outcome,result}';
        IF result->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
            OR COALESCE(result#>>'{primary_identification,resolution}','species')<>'species' THEN RETURN 'null'::JSONB; END IF;
        species_name:=btrim(result->>'scientific_name');
        IF species_name IS NULL OR species_name='' THEN RETURN 'null'::JSONB; END IF;
        IF char_length(species_name)>255 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        -- Taxonomy identity only. Never overwrite curated facts or publish
        -- private result prose, common names, evidence or review authority.
        INSERT INTO public.species_dictionary(scientific_name,common_names) VALUES(species_name,'{}')
            ON CONFLICT(scientific_name) DO NOTHING RETURNING id INTO species;
        IF species IS NULL THEN SELECT id INTO STRICT species FROM public.species_dictionary WHERE scientific_name=species_name; END IF;
        RETURN jsonb_build_object('id',species,'scientific_name',species_name);
    ELSIF p_operation='draft' THEN
        IF p_payload-'draft'<>'{}' OR NOT(p_payload ? 'draft') OR saved.provider_outcome#>>'{outcome,kind}' IS DISTINCT FROM 'draft'
            OR (p_payload#>'{draft,result_snapshot}')-'species_id' IS DISTINCT FROM saved.provider_outcome#>'{outcome,result}' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        PERFORM internal.record_observation_analysis_draft(p_owner,p_observation,p_analysis,quota_token,p_payload->'draft',saved.provider_outcome->'usage');
    ELSIF p_operation='complete' THEN
        PERFORM internal.complete_observation_analysis(p_owner,p_observation,p_analysis);
        UPDATE internal.observation_analysis_intents SET work_token=NULL,work_expires_at=NULL WHERE analysis_id=p_analysis;
    ELSIF p_operation='cancel_uninvoked' THEN
        -- Live-worker proof only: this branch is called exclusively before
        -- invoke() is entered. Recovery never manufactures this proof.
        IF saved.state NOT IN ('admitted','dispatched') OR saved.provider_outcome IS NOT NULL THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        PERFORM internal.fail_observation_analysis(p_owner,p_observation,p_analysis,quota_token,
            CASE saved.state WHEN 'admitted' THEN 'cancelled_before_dispatch' ELSE 'proven_provider_failure' END,'{}');
        UPDATE internal.observation_analysis_intents SET work_token=NULL,work_expires_at=NULL WHERE analysis_id=p_analysis;
    ELSIF p_operation='fail' THEN
        IF p_payload-'reason'<>'{}' OR NOT(p_payload ? 'reason')
            OR ((p_payload->>'reason'='provider_refusal' AND saved.provider_outcome#>>'{outcome,kind}'='refusal')
                OR (p_payload->>'reason'='invalid_result' AND saved.provider_outcome#>>'{outcome,kind}'='invalid_output')
                OR (p_payload->>'reason'='cancelled_before_dispatch' AND saved.state='admitted')) IS NOT TRUE THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        PERFORM internal.fail_observation_analysis(p_owner,p_observation,p_analysis,quota_token,p_payload->>'reason',COALESCE(saved.provider_outcome->'usage','{}'));
        UPDATE internal.observation_analysis_intents SET work_token=NULL,work_expires_at=NULL WHERE analysis_id=p_analysis;
    END IF;
    SELECT jsonb_build_object('state',state) INTO answer FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis;
    RETURN answer;
END;
$$;

REVOKE ALL ON FUNCTION public.begin_owned_observation_analysis(UUID,JSONB,TEXT),
    public.claim_observation_analysis_recovery(UUID,UUID,UUID),public.list_observation_analysis_recovery(),
    public.advance_owned_observation_analysis(UUID,UUID,UUID,UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_owned_observation_analysis(UUID,JSONB,TEXT),
    public.claim_observation_analysis_recovery(UUID,UUID,UUID),public.list_observation_analysis_recovery(),
    public.advance_owned_observation_analysis(UUID,UUID,UUID,UUID,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.begin_owned_observation_analysis(uuid,jsonb,text)','Default-off verified-owner analysis admission and exclusive work claim.'),
    ('service_role','public.claim_observation_analysis_recovery(uuid,uuid,uuid)','Default-off recovery of received private outcomes and drafts only; no provider redispatch.'),
    ('service_role','public.list_observation_analysis_recovery()','Bounded server-only discovery of durable outcome recovery candidates.'),
    ('service_role','public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)','Default-off claim-fenced worker operations; deletion fencing and immutable provider outcome capture.');

RESET statement_timeout;
RESET lock_timeout;
