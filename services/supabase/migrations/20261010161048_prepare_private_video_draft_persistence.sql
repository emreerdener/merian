SET lock_timeout='5s';
SET statement_timeout='2min';

-- Store canonical received-result evidence without implying usage accounting,
-- credit settlement, completion, source release or permission to invoke again.
CREATE FUNCTION internal.record_video_observation_draft(p_owner UUID,p_observation UUID,p_analysis UUID,p_quota_token UUID,p_draft JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; result JSONB; resolved_species UUID; scientific_name TEXT; needs_species BOOLEAN;
BEGIN
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 PERFORM internal.assert_video_analysis_dispatch_identity(saved);
 IF p_quota_token IS NULL OR p_quota_token::TEXT IS DISTINCT FROM saved.quota->>'lease_token'
  OR saved.provider_outcome#>>'{outcome,kind}' IS DISTINCT FROM 'draft' THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 result:=p_draft->'result_snapshot';
 IF jsonb_typeof(p_draft) IS DISTINCT FROM 'object' OR octet_length(p_draft::TEXT)>1048576
  OR p_draft-'result_snapshot' IS DISTINCT FROM saved.input_snapshot-ARRAY['entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']
  OR jsonb_typeof(result) IS DISTINCT FROM 'object'
  OR result-'species_id' IS DISTINCT FROM saved.provider_outcome#>'{outcome,result}'
  OR result->'identification_provenance' IS DISTINCT FROM saved.provider_outcome->'provenance'
  OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=p_analysis AND provenance=result->'identification_provenance') THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 -- Stored equality is independent of dictionary updates and invocation retention.
 -- Identity/deletion fencing above still applies to every replay.
 IF saved.draft IS NOT NULL THEN
  IF saved.draft IS DISTINCT FROM p_draft THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN;
 END IF;
 IF saved.state<>'dispatched' OR saved.provider_usage IS NOT NULL OR saved.receipt IS NOT NULL OR saved.terminal_reason IS NOT NULL THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 -- Full Identify semantics remain owned by the canonical Edge builder. Recheck
 -- database identity/taxonomy and projection boundaries before private storage.
 IF result->>'scan_id' IS DISTINCT FROM p_observation::TEXT
  OR jsonb_typeof(result->'is_biological_subject') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(result->'is_live_capture') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(result->'confidence_score') IS DISTINCT FROM 'number'
  OR NOT(result ? 'species_id')
  OR result ?| ARRAY['ai_identification_review','confirmed_species_identity','confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state','entitlement'] THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF (result->>'confidence_score')::NUMERIC NOT BETWEEN 0 AND 1 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF result->'species_id'<>'null'::JSONB THEN
  IF jsonb_typeof(result->'species_id') IS DISTINCT FROM 'string' OR result->>'species_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  resolved_species:=(result->>'species_id')::UUID;
 END IF;
 needs_species:=(result->>'is_biological_subject')::BOOLEAN AND (
  result#>>'{primary_identification,resolution}'='species'
  OR (NOT(result ? 'primary_identification') AND NULLIF(btrim(result->>'scientific_name'),'') IS NOT NULL));
 IF COALESCE(needs_species,FALSE)<>(resolved_species IS NOT NULL) THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF resolved_species IS NOT NULL THEN
  SELECT dictionary.scientific_name INTO scientific_name FROM public.species_dictionary dictionary WHERE dictionary.id=resolved_species FOR SHARE;
  IF NOT FOUND OR lower(btrim(scientific_name)) IS DISTINCT FROM lower(btrim(result->>'scientific_name')) THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 END IF;
 PERFORM internal.observation_analysis_projection(result,'{"confirmed_species_identity":null,"confirmed_species_identity_revision":0,"confirmed_species_id":null,"user_identification_override":null,"user_confirmed_identification":false,"user_review_state":"unreviewed","ai_identification_review":null}'::JSONB);
 -- Deliberately remain dispatched: the existing draft state implies accounting.
 UPDATE internal.observation_analysis_intents SET draft=p_draft WHERE analysis_id=p_analysis;
END;
$$;
REVOKE ALL ON FUNCTION internal.record_video_observation_draft(UUID,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
RESET statement_timeout;
RESET lock_timeout;
