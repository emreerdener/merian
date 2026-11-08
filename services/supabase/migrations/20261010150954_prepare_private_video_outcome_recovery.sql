SET lock_timeout='5s';
SET statement_timeout='2min';

-- Received evidence is independent of fresh dispatch eligibility. These private
-- helpers never claim work, settle credits, release occupancy or invoke a model.
CREATE FUNCTION internal.assert_video_analysis_dispatch_identity(p_saved internal.observation_analysis_intents)
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 IF p_saved.invocation_id IS NULL OR p_saved.state NOT IN ('dispatched','draft','complete','failed_terminal')
  OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses w
   JOIN internal.observation_analysis_source_bindings b USING(analysis_id)
   WHERE w.analysis_id=p_saved.analysis_id AND w.owner_id=p_saved.owner_id AND w.observation_id=p_saved.observation_id
    AND w.source_analysis_id=b.source_analysis_id AND w.fingerprint=b.fingerprint
    AND w.reservation_id=internal.source_child_uuid(p_saved.quota->>'reservation_id')
    AND w.attempt_count=1 AND w.lease_sha256=encode(extensions.digest(p_saved.quota->>'lease_token','sha256'),'hex')) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
END;
$$;

CREATE FUNCTION internal.record_video_observation_outcome(p_owner UUID,p_observation UUID,p_analysis UUID,p_quota_token UUID,p_value JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; kind TEXT;
BEGIN
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 PERFORM internal.assert_video_analysis_dispatch_identity(saved);
 IF p_quota_token IS NULL OR p_quota_token::TEXT IS DISTINCT FROM saved.quota->>'lease_token' THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 kind:=p_value#>>'{outcome,kind}';
 IF jsonb_typeof(p_value) IS DISTINCT FROM 'object' OR octet_length(p_value::TEXT)>1048576
  OR p_value-ARRAY['schema_version','provenance','outcome','usage']<>'{}'
  OR NOT(p_value ?& ARRAY['schema_version','provenance','outcome','usage'])
  OR p_value->'schema_version' IS DISTINCT FROM '1'::JSONB
  OR jsonb_typeof(p_value->'outcome') IS DISTINCT FROM 'object'
  OR kind IS NULL OR kind NOT IN ('draft','refusal','invalid_output')
  OR (kind='draft' AND ((p_value->'outcome')-ARRAY['kind','result']<>'{}' OR jsonb_typeof(p_value#>'{outcome,result}') IS DISTINCT FROM 'object'))
  OR (kind<>'draft' AND (p_value->'outcome')-'kind'<>'{}')
  OR jsonb_typeof(p_value->'usage') IS DISTINCT FROM 'object' OR octet_length((p_value->'usage')::TEXT)>2048
  OR (p_value->'usage')-ARRAY['input_tokens','cached_tokens','cache_write_tokens','output_tokens','candidate_tokens','thinking_tokens','tool_tokens','total_tokens','service_tier','modality_breakdown']<>'{}'
  OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=p_analysis AND provenance=p_value->'provenance') THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 -- Exact saved replay survives invocation retention. A first received answer
 -- must still prove its original invocation; absence never becomes permission.
 IF saved.provider_outcome IS NOT NULL THEN
  IF saved.provider_outcome IS DISTINCT FROM p_value THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN;
 END IF;
 IF saved.state<>'dispatched' THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 -- Retention takes FOR UPDATE SKIP LOCKED. Keep this exact invocation alive
 -- through the first outcome commit; deletion that wins first denies capture.
 PERFORM id FROM internal.identification_invocations
  WHERE id=saved.invocation_id AND scan_id=p_analysis AND user_id=p_owner AND provenance=p_value->'provenance'
  FOR KEY SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 UPDATE internal.observation_analysis_intents SET provider_outcome=p_value,recover_after=clock_timestamp() WHERE analysis_id=p_analysis;
END;
$$;

CREATE FUNCTION internal.read_video_observation_outcome(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 PERFORM internal.assert_video_analysis_dispatch_identity(saved);
 RETURN jsonb_build_object('state',saved.state,'input',saved.input_snapshot,'provider_outcome',saved.provider_outcome);
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_video_analysis_dispatch_identity(internal.observation_analysis_intents),
 internal.record_video_observation_outcome(UUID,UUID,UUID,UUID,JSONB),
 internal.read_video_observation_outcome(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Existing recovery workers cannot consume V4. Do not let private received
-- outcomes occupy their bounded candidate list before settlement is installed.
DO $patch$
DECLARE definition TEXT; anchor TEXT:='WHERE (state=''draft'' OR (state=''dispatched'' AND provider_outcome IS NOT NULL))';
BEGIN
 SELECT pg_get_functiondef('public.list_observation_analysis_recovery()'::regprocedure) INTO STRICT definition;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed recovery discovery changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||' AND input_snapshot->''schema_version''<>''4''::JSONB');
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;
