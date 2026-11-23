SET lock_timeout='5s';

SET statement_timeout='2min';

-- Reader16 is prepared only. Existing reader/storage/admission holds stay closed.

CREATE FUNCTION internal.resolve_initial_history_media(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; baseline internal.observation_analysis_results;
    object internal.ordinary_initial_evidence_objects; member JSONB;
BEGIN
    saved:=internal.assert_sealed_initial_evidence(p_owner,p_observation);
    SELECT * INTO baseline FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND analysis_id=p_analysis AND ordinal=1;
    IF NOT FOUND OR baseline.evidence_manifest IS DISTINCT FROM saved.evidence_manifest
        OR baseline.request_digest IS DISTINCT FROM saved.evidence_digest
        OR baseline.initial_evidence_proof IS DISTINCT FROM saved.completion_response->'initial_evidence'
        OR baseline.result_snapshot IS DISTINCT FROM saved.result_snapshot||jsonb_build_object('species_id',saved.accepted_species_id) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT value INTO member FROM jsonb_array_elements(internal.initial_evidence_contract(saved.evidence_manifest,
        p_observation::TEXT,saved.generation::TEXT)->'items') WHERE value->>'media_id'=p_media::TEXT;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO object FROM internal.ordinary_initial_evidence_objects WHERE scan_id=p_observation AND media_id=p_media;
    IF NOT FOUND OR object.ready_at IS NULL
        OR member IS DISTINCT FROM jsonb_build_object('media_id',object.media_id,'item_index',object.item_index,
            'role',object.role,'role_index',object.role_index,'content_type',object.content_type,'byte_count',object.byte_count,'sha256',object.sha256) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
    -- These objects are retained until observation/account erasure. A null
    -- allocation expiry is explicit; the signed delivery URL still expires in30s.
    RETURN jsonb_build_object('schema_version',2,'owner_id',p_owner,'observation_id',p_observation,'analysis_id',p_analysis,
        'media_id',object.media_id,'content_type',object.content_type,'byte_count',object.byte_count,'sha256',object.sha256,
        'object_id',object.object_id,'expires_at',NULL,'ready_at',object.ready_at);
END;
$$;
REVOKE ALL ON FUNCTION internal.resolve_initial_history_media(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('review_owned_observation_analysis(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: review_owned_observation_analysis(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('select_owned_observation_analysis(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: select_owned_observation_analysis(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(7,8,9,10,11,13,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(7,8,9,10,11,13,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(11,13,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(11,13,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(13,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(13,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$p_reader<>15$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$p_reader NOT IN (15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$p_reader=15$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$p_reader IN (15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$    IF p_reader NOT IN (15,16) AND$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$    IF p_reader<>16 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='7'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (15,16) AND$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,13,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_state(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,13,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(13,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_state(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(13,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_state(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$p_reader<>15$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_state(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$p_reader NOT IN (15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$    IF p_reader NOT IN (15,16) AND$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_state(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$    IF p_reader<>16 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='7'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (15,16) AND$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_rejection_undo(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_rejection_undo(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_confirmation_undo(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_confirmation_undo(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_enrollment_selection(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_enrollment_selection(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('internal.require_observation_action_reader(uuid,integer,uuid)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: internal.require_observation_action_reader(uuid,integer,uuid)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('internal.require_observation_action_reader(uuid,integer,uuid)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN RAISE EXCEPTION 'initial_reader16_source_drift: internal.require_observation_action_reader(uuid,integer,uuid)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('internal.require_observation_action_reader(uuid,integer,uuid)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: internal.require_observation_action_reader(uuid,integer,uuid)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$p_reader<>15$anchor$;
BEGIN
    definition:=pg_get_functiondef('internal.require_observation_action_reader(uuid,integer,uuid)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: internal.require_observation_action_reader(uuid,integer,uuid)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$p_reader NOT IN (15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$    IF p_reader NOT IN (15,16) AND$anchor$;
BEGIN
    definition:=pg_get_functiondef('internal.require_observation_action_reader(uuid,integer,uuid)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: internal.require_observation_action_reader(uuid,integer,uuid)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$    IF p_reader<>16 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='7'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (15,16) AND$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(9,10,11,14,15)$anchor$;
BEGIN
    definition:=pg_get_functiondef('internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(9,10,11,14,15,16)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(p_reader IN (15,16) AND result_row.evidence_manifest->'schema_version'='6'::JSONB))$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(p_reader IN (15,16) AND result_row.evidence_manifest->'schema_version'='6'::JSONB) OR (p_reader=16 AND result_row.evidence_manifest->'schema_version'='7'::JSONB))$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$internal.observation_analysis_snapshot(result_row.observation_id,result_row.analysis_id,
            result_row.source_analysis_id,result_row.request_digest,result_row.ordinal,result_row.completed_at,
            result_row.result_snapshot,result_row.evidence_manifest)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_page(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$internal.observation_result_snapshot(result_row)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$internal.observation_analysis_snapshot(observation,target,evidence.source_analysis_id,
        evidence.request_digest,evidence.ordinal,evidence.completed_at,evidence.result_snapshot,evidence.evidence_manifest)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_analysis_state(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$internal.observation_result_snapshot(evidence)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$p_reader IS DISTINCT FROM 9$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_enrollment_baseline(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_enrollment_baseline(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(p_reader IS NULL OR p_reader NOT IN (9,16))$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$AND evidence_manifest->'schema_version'='3'::JSONB;$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_enrollment_baseline(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_enrollment_baseline(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$AND evidence_manifest->'schema_version'=CASE WHEN p_reader=16 THEN '7'::JSONB ELSE '3'::JSONB END;$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$internal.observation_analysis_snapshot(observation,baseline.analysis_id,baseline.source_analysis_id,
        baseline.request_digest,baseline.ordinal,baseline.completed_at,baseline.result_snapshot,baseline.evidence_manifest)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_enrollment_baseline(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_enrollment_baseline(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$internal.observation_result_snapshot(baseline)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$    snapshot := internal.observation_result_snapshot(baseline);$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_enrollment_baseline(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_enrollment_baseline(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$    IF p_reader=16 THEN PERFORM internal.assert_sealed_initial_evidence(caller,observation); END IF;
    snapshot := internal.observation_result_snapshot(baseline);$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$public.get_owned_observation_enrollment_baseline(p_request,9)$anchor$;
BEGIN
    definition:=pg_get_functiondef('get_owned_observation_enrollment_selection(jsonb,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: get_owned_observation_enrollment_selection(jsonb,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$public.get_owned_observation_enrollment_baseline(p_request,CASE WHEN p_reader=16 THEN 16 ELSE 9 END)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$(p_protocol IS NULL OR p_protocol NOT IN (1,2))$anchor$;
BEGIN
    definition:=pg_get_functiondef('resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$(p_protocol IS NULL OR p_protocol NOT IN (1,2,3))$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$'5'::JSONB,'6'::JSONB)$anchor$;
BEGIN
    definition:=pg_get_functiondef('resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN RAISE EXCEPTION 'initial_reader16_source_drift: resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$'5'::JSONB,'6'::JSONB,'7'::JSONB)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$manifest->'schema_version'='6'::JSONB AND p_protocol<>2$anchor$;
BEGIN
    definition:=pg_get_functiondef('resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$manifest->'schema_version'='6'::JSONB AND p_protocol NOT IN (2,3)$replacement$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT:=$anchor$    IF manifest->'schema_version'='6'::JSONB$anchor$;
BEGIN
    definition:=pg_get_functiondef('resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'::regprocedure);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_reader16_source_drift: resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'; END IF;
    EXECUTE replace(definition,anchor,$replacement$    IF manifest->'schema_version'='7'::JSONB THEN
        IF p_protocol<>3 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
        RETURN internal.resolve_initial_history_media(p_owner,p_observation,p_analysis,p_media);
    END IF;
    IF manifest->'schema_version'='6'::JSONB$replacement$);
END;
$patch$;

RESET statement_timeout;

RESET lock_timeout;
