SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN video_orchestration_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- A separate service boundary keeps legacy workers and client readers closed.
CREATE FUNCTION public.begin_owned_observation_video_analysis(p_owner UUID,p_input JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 IF (SELECT orchestration_enabled AND video_orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM internal.admit_video_observation_analysis(p_owner,p_input,p_ip_hash);
 RETURN internal.claim_video_observation_analysis(p_owner,internal.source_child_uuid(p_input->>'observation_id'),internal.source_child_uuid(p_input->>'analysis_id'));
END;
$$;

CREATE FUNCTION public.claim_observation_video_analysis_recovery(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
 PERFORM internal.require_service_role();
 IF (SELECT orchestration_enabled AND video_orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 IF (saved.state='draft' OR (saved.state='dispatched' AND saved.provider_outcome IS NOT NULL)) IS NOT TRUE
  OR saved.work_expires_at>clock_timestamp() OR saved.recover_after>clock_timestamp() THEN
  RETURN jsonb_build_object('state',saved.state,'claimed',FALSE); END IF;
 PERFORM internal.assert_video_analysis_dispatch_identity(saved);
 UPDATE internal.observation_analysis_intents SET work_token=gen_random_uuid(),work_expires_at=clock_timestamp()+INTERVAL '120 seconds'
  WHERE analysis_id=p_analysis RETURNING * INTO saved;
 RETURN jsonb_build_object('state',saved.state,'claimed',TRUE,'work_token',saved.work_token,
  'input',saved.input_snapshot,'quota',saved.quota,'provider_outcome',saved.provider_outcome,'draft',saved.draft);
END;
$$;

CREATE FUNCTION public.list_observation_video_analysis_recovery()
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 IF (SELECT orchestration_enabled AND video_orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 -- Discovery conveys no execution authority; claim rechecks owner/deletion and
 -- source identity under the canonical locks. Unknown execution is never listed.
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(candidate)) FROM (
  SELECT owner_id,observation_id,analysis_id FROM internal.observation_analysis_intents
  WHERE input_snapshot->'schema_version'='4'::JSONB
   AND (state='draft' OR (state='dispatched' AND provider_outcome IS NOT NULL))
   AND (work_expires_at IS NULL OR work_expires_at<=clock_timestamp())
   AND (recover_after IS NULL OR recover_after<=clock_timestamp())
  ORDER BY recover_after NULLS FIRST,analysis_id LIMIT 32
 ) candidate),'[]'::JSONB);
END;
$$;

CREATE FUNCTION public.advance_owned_observation_video_analysis(p_owner UUID,p_observation UUID,p_analysis UUID,p_work UUID,p_operation TEXT,p_payload JSONB)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; binding internal.observation_analysis_source_bindings;
 quota_token UUID; result JSONB; species UUID; species_name TEXT; matching UUID[];
BEGIN
 PERFORM internal.require_service_role();
 IF (SELECT orchestration_enabled AND video_orchestration_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 IF p_operation IS NULL OR p_operation NOT IN ('materialize','dispatch','outcome','resolve_species','draft','account','complete','fail','release')
  OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::TEXT)>2097152 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 quota_token:=internal.source_child_uuid(saved.quota->>'lease_token');
 -- Late received evidence uses the original quota token, not an expired or
 -- replaced worker claim. Private capture proves the immutable dispatch witness.
 IF p_operation='outcome' THEN
  IF p_payload-ARRAY['quota_token','value']<>'{}' OR NOT(p_payload ?& ARRAY['quota_token','value'])
   OR p_payload->>'quota_token' IS DISTINCT FROM quota_token::TEXT THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  PERFORM internal.record_video_observation_outcome(p_owner,p_observation,p_analysis,quota_token,p_payload->'value');
  RETURN '{}'::JSONB;
 END IF;
 IF p_work IS NULL OR saved.work_token IS DISTINCT FROM p_work OR saved.work_expires_at IS NULL
  OR saved.work_expires_at<=clock_timestamp() THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF p_operation NOT IN ('dispatch','draft') AND p_payload<>'{}' THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF p_operation='release' THEN
  UPDATE internal.observation_analysis_intents SET work_token=NULL,work_expires_at=NULL,
   recover_after=clock_timestamp()+INTERVAL '60 seconds' WHERE analysis_id=p_analysis;
  RETURN '{}'::JSONB;
 ELSIF p_operation='materialize' THEN
  PERFORM internal.assert_video_observation_dispatchable(saved);
  SELECT * INTO STRICT binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
  RETURN internal.video_evidence_receipt(binding);
 ELSIF p_operation='dispatch' THEN
  IF p_payload-'provenance'<>'{}' OR NOT(p_payload ? 'provenance') OR saved.provider_outcome IS NOT NULL THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  RETURN internal.dispatch_video_observation_analysis(p_owner,p_observation,p_analysis,p_work,p_payload->'provenance');
 END IF;
 -- Known-result progression never evaluates fresh media/consent/dispatch gates
 -- or asks for a provider attempt. Each settlement owner proves its own receipt.
 PERFORM internal.assert_video_analysis_dispatch_identity(saved);
 IF saved.provider_outcome IS NULL THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF p_operation='resolve_species' THEN
  IF saved.state<>'dispatched' OR saved.provider_outcome#>>'{outcome,kind}' IS DISTINCT FROM 'draft' THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  result:=saved.provider_outcome#>'{outcome,result}';
  IF result->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
   OR COALESCE(result#>>'{primary_identification,resolution}','species')<>'species' THEN RETURN 'null'::JSONB; END IF;
  species_name:=btrim(result->>'scientific_name');
  IF species_name IS NULL OR species_name='' THEN RETURN 'null'::JSONB; END IF;
  IF char_length(species_name)>255 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  -- Model text cannot create taxonomy. The verified resolver owns any missing
  -- dictionary identity; this work operation only reads an unambiguous match.
  SELECT array_agg(candidate.id) INTO matching FROM (
   SELECT d.id FROM public.species_dictionary d WHERE lower(btrim(d.scientific_name))=lower(species_name)
   ORDER BY d.id LIMIT 2 FOR SHARE
  ) candidate;
  IF COALESCE(array_length(matching,1),0)<>1 THEN
   RAISE EXCEPTION 'analysis_history_species_unavailable' USING ERRCODE='55000'; END IF;
  SELECT d.id,d.scientific_name INTO species,species_name FROM public.species_dictionary d
   WHERE d.id=matching[1] AND d.is_public_biological AND d.gbif_taxon_key IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_species_unavailable' USING ERRCODE='55000'; END IF;
  RETURN jsonb_build_object('id',species,'scientific_name',species_name);
 ELSIF p_operation='draft' THEN
  IF p_payload-'draft'<>'{}' OR NOT(p_payload ? 'draft') THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  PERFORM internal.record_video_observation_draft(p_owner,p_observation,p_analysis,quota_token,p_payload->'draft');
 ELSIF p_operation='account' THEN
  RETURN internal.account_video_observation_draft(p_owner,p_observation,p_analysis,quota_token);
 ELSIF p_operation='complete' THEN
  RETURN internal.complete_video_observation_analysis(p_owner,p_observation,p_analysis,quota_token);
 ELSIF p_operation='fail' THEN
  RETURN internal.settle_video_observation_terminal(p_owner,p_observation,p_analysis,quota_token);
 END IF;
 RETURN jsonb_build_object('state',saved.state);
END;
$$;

REVOKE ALL ON FUNCTION public.begin_owned_observation_video_analysis(UUID,JSONB,TEXT),
 public.claim_observation_video_analysis_recovery(UUID,UUID,UUID),public.list_observation_video_analysis_recovery(),
 public.advance_owned_observation_video_analysis(UUID,UUID,UUID,UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_owned_observation_video_analysis(UUID,JSONB,TEXT),
 public.claim_observation_video_analysis_recovery(UUID,UUID,UUID),public.list_observation_video_analysis_recovery(),
 public.advance_owned_observation_video_analysis(UUID,UUID,UUID,UUID,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.begin_owned_observation_video_analysis(uuid,jsonb,text)','Default-off exact V4 admission and exclusive initial work claim.'),
 ('service_role','public.claim_observation_video_analysis_recovery(uuid,uuid,uuid)','Default-off known V4 outcome/draft recovery; no provider redispatch.'),
 ('service_role','public.list_observation_video_analysis_recovery()','Bounded service-only known V4 recovery discovery; no execution authority.'),
 ('service_role','public.advance_owned_observation_video_analysis(uuid,uuid,uuid,uuid,text,jsonb)','Default-off V4 worker composition with canonical source locks and separate dispatch/known-result fences.');
COMMENT ON COLUMN internal.observation_history_rollout.video_orchestration_enabled IS
 'Default-off service-only V4 orchestration. No Edge/native execution consumer or hosted scheduling is installed by this migration.';
COMMENT ON COLUMN internal.observation_history_rollout.video_analysis_enabled IS
 'Default-off V4 initial admission, composed only by separately gated service-only video orchestration; no Edge/native execution consumer.';
COMMENT ON COLUMN internal.observation_history_rollout.video_dispatch_enabled IS
 'Default-off V4 one-shot dispatch, composed only by separately gated service-only video orchestration; known-result recovery grants no dispatch authority.';
RESET statement_timeout;
RESET lock_timeout;
