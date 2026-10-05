SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Advisory recipient discovery for a new photo child. It never enrolls,
-- reserves funding/quota, uploads evidence, creates work or changes selection.
CREATE FUNCTION public.get_owned_observation_reanalysis_preflight(p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; analysis UUID; source UUID; field TEXT;
    saved internal.observation_analysis_intents;
    preview RECORD; decision TEXT; recipient TEXT; minimum_entitlement INTEGER; minimum_identification INTEGER;
BEGIN
    IF caller IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object'
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id',
            'entitlement_protocol','identification_protocol','history_protocol'])
        OR p_request - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id',
            'entitlement_protocol','identification_protocol','history_protocol'] <> '{}'::JSONB
        OR pg_catalog.OCTET_LENGTH(p_request::TEXT)>2048
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR p_request->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_request->'identification_protocol' IS DISTINCT FROM '6'::JSONB
        OR p_request->'history_protocol' IS DISTINCT FROM '8'::JSONB THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['observation_id','analysis_id','source_analysis_id'] LOOP
        IF pg_catalog.JSONB_TYPEOF(p_request->field) IS DISTINCT FROM 'string'
            OR p_request->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    observation:=(p_request->>'observation_id')::UUID;
    analysis:=(p_request->>'analysis_id')::UUID;
    source:=(p_request->>'source_analysis_id')::UUID;
    IF analysis=observation OR source IN (observation,analysis) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(caller,observation);
    IF NOT EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=observation
        AND selection_initialized AND selected_analysis_id IS NOT NULL AND state_revision>=1)
        OR (SELECT orchestration_enabled AND admission_enabled AND protected_analysis_enabled
            FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- Historical source need not be selected or confirmed. Its immutable
    -- membership, not the mutable selection, defines the requested reanalysis.
    IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=observation AND analysis_id=source) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || analysis::TEXT,0::BIGINT));
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-history-evidence:' || analysis::TEXT,0::BIGINT));
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
    IF FOUND THEN
        IF saved.owner_id IS DISTINCT FROM caller OR saved.observation_id IS DISTINCT FROM observation
            OR saved.input_snapshot->>'source_analysis_id' IS DISTINCT FROM source::TEXT THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- Includes admitted, terminal and uncertain dispatch: a preflight can
        -- never rebind a saved identity to today's provider or revive its work.
        decision:='recovery_only';
    ELSE
            IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=analysis)
                OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=analysis)
                OR EXISTS(SELECT 1 FROM public.scans WHERE id=analysis)
                OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=analysis::TEXT)
                OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=analysis)
                OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=analysis)
                OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=analysis
                    AND (owner_id<>caller OR observation_id<>observation)) THEN
                RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
            END IF;
            -- Reuse the current read-only recipient policy, not legacy request
            -- routing or admission. Flags/profile are fixed by this photo API.
            SELECT * INTO STRICT preview FROM public.get_my_identification_preflight(
                'scan_identification','multimodal_photo_v1',FALSE,analysis,3,6);
            decision:=preview.decision; recipient:=preview.processor_permission;
            minimum_entitlement:=preview.minimum_client_protocol;
            minimum_identification:=preview.minimum_identification_protocol;
    END IF;
    RETURN pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,
        'analysis_id',analysis,'source_analysis_id',source,'decision',decision,
        'processor_permission',recipient,'minimum_entitlement_protocol',minimum_entitlement,
        'minimum_identification_protocol',minimum_identification);
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_reanalysis_preflight(JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_reanalysis_preflight(JSONB) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.get_owned_observation_reanalysis_preflight(jsonb)',
     'Default-off owner/source/child-bound photo recipient preview without admission, funding or dispatch authority.');
COMMENT ON FUNCTION public.get_owned_observation_reanalysis_preflight(JSONB) IS
    'Advisory protocol 3/6/8 photo reanalysis preflight. Saved child identities are recovery-only; final admission revalidates recipient and consent. Never selects or allocates a provider attempt.';

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
