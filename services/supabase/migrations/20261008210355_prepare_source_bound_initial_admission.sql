SET lock_timeout='5s';
SET statement_timeout='2min';

-- Initial funding proof only. Called after canonical source/child/intent locks;
-- it takes no new locks and cannot authorize provider dispatch or a successor.
CREATE FUNCTION internal.assert_source_initial_admission(
    p_owner UUID,p_analysis UUID,p_request UUID,p_operation TEXT,
    p_protocol INTEGER,p_fallback BOOLEAN,p_replay BOOLEAN
) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
    IF p_operation IS DISTINCT FROM 'scan_identification' OR p_request IS DISTINCT FROM p_analysis
        OR p_protocol IS DISTINCT FROM 3 OR p_fallback IS DISTINCT FROM FALSE OR p_replay IS DISTINCT FROM FALSE
        OR current_setting('merian.observation_analysis_admission',TRUE) IS DISTINCT FROM p_owner::TEXT || ':' || p_analysis::TEXT THEN
        RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis;
    IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.state IS DISTINCT FROM 'admitted'
        OR saved.quota IS NOT NULL OR saved.invocation_id IS NOT NULL OR saved.provider_outcome IS NOT NULL
        OR saved.provider_usage IS NOT NULL OR saved.draft IS NOT NULL OR saved.receipt IS NOT NULL
        OR saved.terminal_reason IS NOT NULL OR saved.work_token IS NOT NULL OR saved.work_expires_at IS NOT NULL
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_observation_source_input_chain(p_owner,saved.observation_id,p_analysis,saved.input_snapshot);
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_source_initial_admission(UUID,UUID,UUID,TEXT,INTEGER,BOOLEAN,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

DO $migration$
DECLARE definition TEXT; signature TEXT; anchor TEXT; denial TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'internal.admit_protected_observation_analysis(uuid,jsonb,text)',
        'internal.admit_audio_observation_analysis(uuid,jsonb,text)'
    ] LOOP
        SELECT pg_catalog.pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        anchor:='    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
            RAISE EXCEPTION 'Reviewed source admission entry changed: %',signature;
        END IF;
        definition:=replace(definition,anchor,$guard$    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
$guard$ || anchor || $body$
    -- Parent lock serializes recorded intent transitions. Recover the original
    -- bound receipt before live occupancy, evidence expiry or fresh gates. An
    -- admitted replay cannot enter generic quota admission a second time.
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=analysis) THEN
        SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
        IF FOUND THEN
            IF saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM observation
                OR saved.input_snapshot IS DISTINCT FROM p_input
                OR jsonb_typeof(saved.quota) IS DISTINCT FROM 'object'
                OR internal.source_child_uuid(saved.quota->>'reservation_id') IS NULL
                OR internal.source_child_uuid(saved.quota->>'lease_token') IS NULL
                OR saved.quota->>'request_id' IS DISTINCT FROM analysis::TEXT
                OR saved.quota->>'original_analysis_id' IS DISTINCT FROM analysis::TEXT
                OR saved.quota->>'reservation_state' IS DISTINCT FROM 'reserved'
                OR saved.quota->'attempt_count' IS DISTINCT FROM '1'::JSONB THEN
                RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
            END IF;
            RETURN to_jsonb(saved)-'draft';
        END IF;
    END IF;
    -- Also rereads apparent unbound absence after the child lock; no late
    -- source lock can follow a cross-owner binding committed during that wait.
    PERFORM internal.lock_observation_evidence_source(p_owner,observation,analysis);
$body$);
        EXECUTE definition;
    END LOOP;

    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='        IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_original_analysis_id) THEN
            RAISE EXCEPTION ''analysis_history_admission_required'' USING ERRCODE=''55000'';
        END IF;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'Reviewed bound funding exclusion changed';
    END IF;
    EXECUTE replace(definition,anchor,$body$
        IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_original_analysis_id) THEN
            PERFORM internal.assert_source_initial_admission(p_user_id,p_original_analysis_id,p_request_id,p_operation,
                p_client_protocol,p_flash_fallback_eligible,p_internal_replay);
        END IF;
$body$);

    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    ) AS quota;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'Reviewed profile admission boundary changed';
    END IF;
    -- The quota core has already taken the original child lock. A profile
    -- mismatch rolls back that reservation; no late source locks are added.
    EXECUTE replace(definition,anchor,anchor || $body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_original_analysis_id) AND NOT EXISTS(
        SELECT 1 FROM internal.observation_analysis_source_bindings b
        WHERE b.analysis_id=p_original_analysis_id AND b.owner_id=p_user_id
            AND p_input_profile=CASE b.input_snapshot->>'schema_version' WHEN '2' THEN 'multimodal_photo_v1' WHEN '3' THEN 'multimodal_audio_v1' END
            AND p_expected_processor_permission=b.input_snapshot->>'expected_processor_permission'
            AND to_jsonb(p_identification_protocol)=b.input_snapshot->'identification_protocol') THEN
        RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
    END IF;
$body$);

    denial:=$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_original_analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
    END IF;
$body$;
    FOREACH signature IN ARRAY ARRAY[
        'public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)'
    ] LOOP
        SELECT pg_catalog.pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        FOREACH anchor IN ARRAY ARRAY['PERFORM internal.require_service_role();','AS quota;'] LOOP
            IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
                RAISE EXCEPTION 'Reviewed legacy funding boundary changed: %',signature;
            END IF;
            definition:=replace(definition,anchor,anchor || denial);
        END LOOP;
        EXECUTE definition;
    END LOOP;
END;
$migration$;
COMMENT ON FUNCTION internal.assert_source_initial_admission(UUID,UUID,UUID,TEXT,INTEGER,BOOLEAN,BOOLEAN) IS
    'Private exact first-funding proof, not a GUC-only bypass. Saved bound intents replay original quota and cannot re-reserve after expiry or pruning. Dispatch remains independently denied.';
RESET statement_timeout;
RESET lock_timeout;
