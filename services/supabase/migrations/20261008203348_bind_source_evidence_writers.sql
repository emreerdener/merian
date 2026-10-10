SET lock_timeout='5s';
SET statement_timeout='2min';

-- Entry boundary for evidence writers, before any child or receipt lock.
CREATE FUNCTION internal.lock_observation_evidence_source(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS internal.observation_analysis_source_bindings
LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
    IF FOUND THEN
        RETURN internal.lock_owned_observation_source_binding(p_owner,p_observation,p_analysis,binding.input_snapshot);
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_analysis::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    -- A different owner's binding may commit while this writer waits. Never
    -- acquire its source lock late or interpret the stale absence as legacy.
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_observation_evidence_source(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the reviewed existing expiry, object identity, receipt replay and
-- service-role checks. Only source entry/linkage changes at exact anchors.
DO $migration$
DECLARE definition TEXT; signature TEXT; anchor TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.reserve_owned_observation_evidence_cohort(uuid,uuid,uuid,jsonb)',
        'public.reserve_owned_observation_audio_evidence_cohort(uuid,uuid,uuid,uuid,integer,text)',
        'internal.reserve_observation_evidence(uuid,uuid,uuid,uuid,text,integer,text)',
        'internal.complete_observation_evidence(uuid,uuid,uuid,uuid,uuid)',
        'public.complete_owned_observation_audio_evidence_upload(uuid,uuid,uuid,uuid,uuid)'
    ] LOOP
        SELECT pg_catalog.pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        anchor:='    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
            RAISE EXCEPTION 'Reviewed evidence entry boundary changed: %',signature;
        END IF;
        IF signature LIKE 'public.reserve_owned_observation%cohort%' THEN
            IF (length(definition)-length(replace(definition,'DECLARE ','')))/length('DECLARE ')<>1 THEN
                RAISE EXCEPTION 'Reviewed evidence declaration changed: %',signature;
            END IF;
            definition:=replace(definition,'DECLARE ','DECLARE binding internal.observation_analysis_source_bindings; ');
            definition:=replace(definition,anchor,
                '    binding:=internal.lock_observation_evidence_source(p_owner,p_observation,p_analysis);');
            IF signature='public.reserve_owned_observation_evidence_cohort(uuid,uuid,uuid,jsonb)' THEN
                anchor:='    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN';
                IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Reviewed photo branch changed'; END IF;
                definition:=replace(definition,anchor,$body$
    IF binding.analysis_id IS NOT NULL AND internal.observation_source_cohort_items(binding.input_snapshot,2) IS DISTINCT FROM p_items THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$body$ || anchor);
                anchor:='IF saved.owner_id<>p_owner OR saved.observation_id<>p_observation OR saved.items<>p_items THEN';
                IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Reviewed photo replay changed'; END IF;
                definition:=replace(definition,anchor,replace(anchor,' THEN',' OR saved.binding_analysis_id IS DISTINCT FROM binding.analysis_id THEN'));
                anchor:='INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items)
        VALUES(p_analysis,p_observation,p_owner,p_items)';
                IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Reviewed photo insert changed'; END IF;
                definition:=replace(definition,anchor,'INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items,binding_analysis_id)
        VALUES(p_analysis,p_observation,p_owner,p_items,binding.analysis_id)');
            ELSE
                anchor:='    IF EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)';
                IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Reviewed audio branch changed'; END IF;
                definition:=replace(definition,anchor,$body$
    IF binding.analysis_id IS NOT NULL AND internal.observation_source_cohort_items(binding.input_snapshot,3) IS DISTINCT FROM
        jsonb_build_array(jsonb_build_object('media_id',p_media,'content_type','audio/wav','byte_count',p_bytes,'sha256',p_sha256)) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$body$ || anchor);
                anchor:='OR saved.byte_count<>p_bytes OR saved.sha256<>p_sha256 THEN';
                IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Reviewed audio replay changed'; END IF;
                definition:=replace(definition,anchor,replace(anchor,' THEN',' OR saved.binding_analysis_id IS DISTINCT FROM binding.analysis_id THEN'));
                anchor:='INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,observation_id,owner_id,media_id,content_type,byte_count,sha256)
        VALUES(p_analysis,p_observation,p_owner,p_media,''audio/wav'',p_bytes,p_sha256)';
                IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Reviewed audio insert changed'; END IF;
                definition:=replace(definition,anchor,'INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,observation_id,owner_id,media_id,content_type,byte_count,sha256,binding_analysis_id)
        VALUES(p_analysis,p_observation,p_owner,p_media,''audio/wav'',p_bytes,p_sha256,binding.analysis_id)');
            END IF;
        ELSE
            definition:=replace(definition,anchor,$body$
    PERFORM internal.lock_observation_evidence_source(p_owner,p_observation,p_analysis);
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis) THEN
        PERFORM internal.assert_observation_source_input_chain(p_owner,p_observation,p_analysis,
            (SELECT input_snapshot FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis));
    END IF;
$body$);
        END IF;
        EXECUTE definition;
    END LOOP;
END;
$migration$;
COMMENT ON FUNCTION internal.lock_observation_evidence_source(UUID,UUID,UUID) IS
    'Private source-first evidence writer entry. Bound children need exact live occupancy; unbound children are reread after locks. No reservation, funding or dispatch authority.';
RESET statement_timeout;
RESET lock_timeout;
