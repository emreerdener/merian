SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN source_discovery_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Nonunique projections over durable rows, not reservations. Terminal siblings
-- remain valid history. No absence is authoritative before all-writer cutover.
CREATE INDEX observation_analysis_results_source
    ON internal.observation_analysis_results(observation_id,source_analysis_id,analysis_id);
CREATE INDEX observation_analysis_intents_source
    ON internal.observation_analysis_intents(observation_id,(input_snapshot->>'source_analysis_id'),analysis_id);

CREATE FUNCTION public.get_owned_observation_analysis_source(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path=''
SET statement_timeout='5s' AS $$
DECLARE
    observation UUID; source UUID; field TEXT; answer JSONB; saved internal.observation_analysis_intents;
    result_row internal.observation_analysis_results; retired internal.observation_analysis_retirement_receipts;
    input JSONB; blockers INTEGER:=0; terminals INTEGER:=0; candidate JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_reader IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023';
    END IF;
    IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object'
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','source_analysis_id'])
        OR p_request-ARRAY['schema_version','observation_id','source_analysis_id']<>'{}' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['observation_id','source_analysis_id'] LOOP
        IF jsonb_typeof(p_request->field) IS DISTINCT FROM 'string'
            OR p_request->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    observation:=(p_request->>'observation_id')::UUID;
    source:=(p_request->>'source_analysis_id')::UUID;
    IF source=observation THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    answer:=p_request || jsonb_build_object('owner_id',p_owner);
    -- Same owner -> parent generation -> scan -> history order as every writer.
    BEGIN
        PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    EXCEPTION WHEN SQLSTATE 'P0002' THEN
        RETURN answer || '{"state":"unavailable"}'::JSONB;
    END;
    IF (SELECT source_discovery_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
        OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results
            WHERE observation_id=observation AND analysis_id=source) THEN
        RETURN answer || '{"state":"unavailable"}'::JSONB;
    END IF;

    -- Bounded conservative coverage, not a partial page from which to infer vacancy.
    IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_intents
            WHERE observation_id=observation LIMIT 65) q)>64
        OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_results
            WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64 THEN
        RETURN answer || '{"state":"held","reason":"coverage_incomplete"}'::JSONB;
    END IF;
    -- Pre-admission media has no source field. Never assign an orphan to a guessed source.
    IF EXISTS(SELECT 1 FROM (
            SELECT owner_id,analysis_id FROM internal.observation_evidence_upload_cohorts WHERE observation_id=observation
            UNION ALL SELECT owner_id,analysis_id FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation
            UNION ALL SELECT owner_id,analysis_id FROM internal.observation_evidence_objects WHERE observation_id=observation
        ) media WHERE media.owner_id<>p_owner OR (
            NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents i
                WHERE i.analysis_id=media.analysis_id AND i.observation_id=observation AND i.owner_id=p_owner)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r
                WHERE r.analysis_id=media.analysis_id AND r.observation_id=observation))) THEN
        RETURN answer || '{"state":"held","reason":"coverage_incomplete"}'::JSONB;
    END IF;

    FOR saved IN SELECT * FROM internal.observation_analysis_intents
        WHERE observation_id=observation ORDER BY analysis_id LIMIT 64 LOOP
        input:=saved.input_snapshot;
        IF saved.owner_id<>p_owner OR jsonb_typeof(input) IS DISTINCT FROM 'object'
            OR NOT(input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
            OR input-ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
            OR input->'schema_version' NOT IN ('1'::JSONB,'2'::JSONB,'3'::JSONB)
            OR input->>'observation_id' IS DISTINCT FROM observation::TEXT
            OR input->>'analysis_id' IS DISTINCT FROM saved.analysis_id::TEXT
            OR jsonb_typeof(input->'request_digest') IS DISTINCT FROM 'string'
            OR input->>'request_digest' !~ '^[0-9a-f]{64}$'
            OR jsonb_typeof(input->'evidence_manifest') IS DISTINCT FROM 'object'
            OR input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
            OR input->'identification_protocol' IS DISTINCT FROM '6'::JSONB
            OR NOT COALESCE(((input->'schema_version'='1'::JSONB AND input->'history_protocol'='7'::JSONB
                    AND input->>'expected_processor_permission' IN ('google_gemini','openai'))
                OR (input->'schema_version'='2'::JSONB AND input->'history_protocol'='8'::JSONB
                    AND input->>'expected_processor_permission' IN ('google_gemini','openai'))
                OR (input->'schema_version'='3'::JSONB AND input->'history_protocol'='9'::JSONB
                    AND input->>'expected_processor_permission'='google_gemini')),FALSE)
            OR jsonb_typeof(saved.quota) IS DISTINCT FROM 'object'
            OR saved.quota->>'original_analysis_id' IS DISTINCT FROM saved.analysis_id::TEXT
            OR (input->'source_analysis_id'<>'null'::JSONB AND (
                jsonb_typeof(input->'source_analysis_id') IS DISTINCT FROM 'string'
                OR input->>'source_analysis_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                OR input->>'source_analysis_id' IN (observation::TEXT,saved.analysis_id::TEXT)
                OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r
                    WHERE r.observation_id=observation AND r.analysis_id::TEXT=input->>'source_analysis_id'))) THEN
            RETURN answer || '{"state":"held","reason":"malformed_linkage"}'::JSONB;
        END IF;
        CONTINUE WHEN input->>'source_analysis_id' IS DISTINCT FROM source::TEXT;
        SELECT * INTO result_row FROM internal.observation_analysis_results WHERE analysis_id=saved.analysis_id;
        IF saved.state IN ('admitted','dispatched','draft') THEN
            IF FOUND OR saved.receipt IS NOT NULL OR saved.terminal_reason IS NOT NULL
                OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=saved.analysis_id) THEN
                RETURN answer || '{"state":"held","reason":"malformed_linkage"}'::JSONB;
            END IF;
            blockers:=blockers+1;
            candidate:=jsonb_build_object('state','existing','analysis_id',saved.analysis_id,
                'request_digest',input->>'request_digest','phase',saved.state);
        ELSIF saved.state='complete' THEN
            IF NOT FOUND OR result_row.observation_id<>observation OR result_row.source_analysis_id IS DISTINCT FROM source
                OR result_row.request_digest IS DISTINCT FROM input->>'request_digest'
                OR result_row.evidence_manifest IS DISTINCT FROM input->'evidence_manifest'
                OR jsonb_typeof(saved.draft) IS DISTINCT FROM 'object'
                OR jsonb_typeof(saved.provider_usage) IS DISTINCT FROM 'object'
                OR saved.draft-'result_snapshot' IS DISTINCT FROM input-ARRAY['entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']
                OR saved.draft->'result_snapshot' IS DISTINCT FROM result_row.result_snapshot
                OR jsonb_typeof(saved.receipt) IS DISTINCT FROM 'object'
                OR NOT(saved.receipt ?& ARRAY['snapshot','plan_used','credit_consumed','entitlement_after'])
                OR saved.receipt-ARRAY['snapshot','plan_used','credit_consumed','entitlement_after']<>'{}'
                OR saved.receipt->>'snapshot' IS DISTINCT FROM internal.observation_analysis_snapshot(
                    result_row.observation_id,result_row.analysis_id,result_row.source_analysis_id,result_row.request_digest,
                    result_row.ordinal,result_row.completed_at,result_row.result_snapshot,result_row.evidence_manifest)
                OR jsonb_typeof(saved.receipt->'credit_consumed') IS DISTINCT FROM 'boolean'
                OR jsonb_typeof(saved.receipt->'entitlement_after') IS DISTINCT FROM 'object'
                OR saved.receipt->>'plan_used' IS DISTINCT FROM saved.quota->>'effective_plan'
                OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=saved.analysis_id)
                OR jsonb_typeof(saved.receipt->'plan_used') IS DISTINCT FROM 'string'
                OR saved.terminal_reason IS NOT NULL THEN
                RETURN answer || '{"state":"held","reason":"terminal_unproven"}'::JSONB;
            END IF;
            terminals:=terminals+1;
        ELSIF saved.state='failed_terminal' AND saved.terminal_reason='retired_before_dispatch' THEN
            IF FOUND OR saved.invocation_id IS NOT NULL OR saved.draft IS NOT NULL OR saved.receipt IS NOT NULL
                OR saved.provider_outcome IS NOT NULL OR saved.provider_usage IS DISTINCT FROM '{}'::JSONB
                OR saved.work_token IS NOT NULL OR saved.work_expires_at IS NOT NULL THEN
                RETURN answer || '{"state":"held","reason":"terminal_unproven"}'::JSONB;
            END IF;
            SELECT * INTO retired FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=saved.analysis_id;
            IF NOT FOUND OR retired.owner_id<>p_owner OR retired.observation_id<>observation
                OR retired.request_identity IS DISTINCT FROM jsonb_build_object('schema_version',1,
                    'operation_id',retired.operation_id,'observation_id',observation,'analysis_id',saved.analysis_id,
                    'source_analysis_id',source,'request_digest',input->>'request_digest')
                OR retired.receipt IS DISTINCT FROM retired.request_identity || '{"state":"retired_before_dispatch"}'::JSONB THEN
                RETURN answer || '{"state":"held","reason":"terminal_unproven"}'::JSONB;
            END IF;
            terminals:=terminals+1;
        ELSE
            RETURN answer || '{"state":"held","reason":"terminal_unproven"}'::JSONB;
        END IF;
    END LOOP;
    -- Results can be appended without an intent; they are not completion proof.
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results r
        WHERE r.observation_id=observation AND r.source_analysis_id=source
        AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.analysis_id=r.analysis_id
            AND i.observation_id=observation AND i.owner_id=p_owner AND i.state='complete'
            AND i.input_snapshot->>'source_analysis_id'=source::TEXT)) THEN
        RETURN answer || '{"state":"held","reason":"terminal_unproven"}'::JSONB;
    END IF;
    IF blockers>1 THEN RETURN answer || '{"state":"held","reason":"ambiguous_occupancy"}'::JSONB; END IF;
    IF blockers=1 THEN RETURN answer || candidate; END IF;
    IF terminals>0 THEN RETURN answer || '{"state":"history_only"}'::JSONB; END IF;
    -- No all-writer source reservation/coverage marker exists yet. Never absence.
    RETURN answer || '{"state":"held","reason":"coverage_incomplete"}'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_analysis_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_analysis_source(UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.get_owned_observation_analysis_source(uuid,jsonb,integer)',
     'Bounded owner/source discovery only; no vacancy, reservation, funding or execution authority.');
COMMENT ON FUNCTION public.get_owned_observation_analysis_source(UUID,JSONB,INTEGER) IS
    'Read-only private source classification under owner/parent locks. Reader 10, independent closed gate, at most 64 parent intents and source results; incomplete coverage holds.';
RESET statement_timeout;
RESET lock_timeout;
