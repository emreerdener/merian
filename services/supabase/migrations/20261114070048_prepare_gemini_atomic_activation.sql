-- Activation is an explicit release operation, never a migration side effect.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.gemini_independent_holds()
RETURNS JSONB LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT pg_catalog.jsonb_build_object(
  'history',(SELECT pg_catalog.to_jsonb(r) FROM internal.observation_history_rollout r WHERE singleton),
  'initial',(SELECT pg_catalog.to_jsonb(r) FROM internal.initial_analysis_rollout r WHERE singleton),
  'consent',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) ORDER BY pg_catalog.to_jsonb(r)::TEXT) FROM internal.ai_consent_rollout_config r),
  'entitlement',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) ORDER BY pg_catalog.to_jsonb(r)::TEXT) FROM internal.entitlement_rollout_config r));
$$;
REVOKE ALL ON FUNCTION internal.gemini_independent_holds() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.activate_gemini_release(p_release UUID,p_target TEXT,p_sha TEXT,p_digest TEXT,p_identities JSONB,p_gates JSONB)
RETURNS BIGINT LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE release internal.gemini_activation_releases; current_revision BIGINT; next_revision BIGINT;
 policy internal.ai_quota_policies; next_model TEXT; holds JSONB;
BEGIN
 SELECT revision INTO current_revision FROM internal.gemini_routing_head WHERE singleton FOR UPDATE;
 SELECT * INTO release FROM internal.gemini_activation_releases WHERE id=p_release FOR UPDATE;
 IF NOT FOUND OR release.target IS DISTINCT FROM p_target OR release.backend_sha IS DISTINCT FROM p_sha
  OR release.configuration_digest IS DISTINCT FROM p_digest
  OR release.manifest::JSONB->'required_functions' IS DISTINCT FROM p_identities THEN RAISE EXCEPTION 'gemini_release_identity_mismatch' USING ERRCODE='55000'; END IF;
 IF release.activated_revision IS NOT NULL THEN
  IF current_revision=release.activated_revision AND release.status='activated'
   AND EXISTS(SELECT 1 FROM internal.gemini_routing_revisions WHERE revision=current_revision AND status='active') THEN RETURN current_revision; END IF;
  RAISE EXCEPTION 'gemini_release_superseded_or_suspended' USING ERRCODE='55000';
 END IF;
 IF release.status<>'verified' OR current_revision<>release.expected_previous_revision
  OR pg_catalog.clock_timestamp()<release.window_start OR pg_catalog.clock_timestamp()>=release.window_end
  OR release.manifest::JSONB->'required_functions' IS DISTINCT FROM p_identities
  OR release.verification->'required_functions' IS DISTINCT FROM p_identities
  OR release.verification->'technical_gates' IS DISTINCT FROM p_gates
  OR pg_catalog.jsonb_typeof(p_gates) IS DISTINCT FROM 'object' OR p_gates IS DISTINCT FROM release.manifest::JSONB->'required_gates'
  OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_each(p_gates) WHERE value<>'true'::JSONB)
  OR NOT EXISTS(SELECT 1 FROM internal.gemini_release_smokes WHERE release_id=p_release)
  OR EXISTS(SELECT 1 FROM internal.gemini_release_smokes WHERE release_id=p_release AND (state<>'passed' OR settlement<>'settled')) THEN
  RAISE EXCEPTION 'gemini_release_not_eligible' USING ERRCODE='55000'; END IF;
 holds:=internal.gemini_independent_holds();
 IF holds IS DISTINCT FROM release.verification->'independent_holds' THEN RAISE EXCEPTION 'gemini_independent_holds_changed' USING ERRCODE='55000'; END IF;
 next_revision:=current_revision+1;
 INSERT INTO internal.gemini_routing_revisions(revision,release_id,configuration_digest,status)
 VALUES(next_revision,p_release,p_digest,'active');
 -- Selection changes as one transaction; quota/entitlement limits and enabled
 -- flags are preserved, including independently held publication workflows.
 FOR policy IN SELECT * FROM internal.ai_quota_policies WHERE allowed AND model IN
  ('gemini-2.5-flash','gemini-2.5-pro','gemini-3.8-flash','gemini-3.5-flash-lite') ORDER BY operation,effective_plan FOR UPDATE LOOP
  IF policy.operation NOT IN ('scan_identification','scan_audio_identification','insight_chat_reply',
    'explore_post_chat_reply','species_dictionary_chat_reply','insight_chat_summary','insight_chat_prompt_suggestions',
    'scan_overview_enrichment','scan_lookalike_enrichment','scan_group_tag_enrichment','species_discovery_search',
    'observation_photo_publication_moderation','explore_audio_moderation') THEN RAISE EXCEPTION 'gemini_operation_unreviewed' USING ERRCODE='55000'; END IF;
  next_model:=CASE WHEN policy.operation IN ('scan_identification','scan_audio_identification') THEN 'gemini-3.8-flash' ELSE 'gemini-3.5-flash-lite' END;
  IF policy.operation IN ('scan_identification','scan_audio_identification') THEN
   INSERT INTO internal.identification_provider_bindings(operation,effective_plan,model,policy_version,provider,binding,
    processor_permission,input_profile,minimum_client_protocol,provider_model,minimum_identification_protocol)
   SELECT operation,effective_plan,next_model,policy.policy_version+1,'gemini','gemini_generation3_v1',
    'google_gemini',input_profile,minimum_client_protocol,next_model,7
   FROM internal.identification_provider_bindings WHERE operation=policy.operation AND effective_plan=policy.effective_plan
    AND model=policy.model AND policy_version=policy.policy_version;
   IF NOT FOUND THEN RAISE EXCEPTION 'gemini_assignment_set_incomplete' USING ERRCODE='55000'; END IF;
  END IF;
  UPDATE internal.ai_quota_policies SET model=next_model,policy_version=policy.policy_version+1,updated_at=pg_catalog.clock_timestamp()
    WHERE operation=policy.operation AND effective_plan=policy.effective_plan;
  INSERT INTO internal.gemini_assignment_revisions VALUES(policy.operation,policy.effective_plan,policy.policy_version+1,next_model,next_revision);
 END LOOP;
 UPDATE internal.gemini_routing_revisions SET status='superseded' WHERE revision=current_revision AND status='active';
 UPDATE internal.gemini_routing_head SET revision=next_revision WHERE singleton;
 UPDATE internal.gemini_activation_releases SET status='activated',activated_revision=next_revision WHERE id=p_release;
 INSERT INTO internal.gemini_release_events(release_id,revision,kind,evidence)
 VALUES(p_release,next_revision,'activated',pg_catalog.jsonb_build_object('backend_sha',p_sha,'configuration_digest',p_digest,'required_functions',p_identities,'technical_gates',p_gates));
 IF internal.gemini_independent_holds() IS DISTINCT FROM holds THEN RAISE EXCEPTION 'gemini_independent_hold_mutation' USING ERRCODE='55000'; END IF;
 RETURN next_revision;
END;
$$;
REVOKE ALL ON FUNCTION internal.activate_gemini_release(UUID,TEXT,TEXT,TEXT,JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.suspend_gemini_release(p_release UUID,p_revision BIGINT,p_digest TEXT,p_evidence JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE head BIGINT;
BEGIN
 SELECT revision INTO head FROM internal.gemini_routing_head WHERE singleton FOR UPDATE;
 IF head IS DISTINCT FROM p_revision OR NOT EXISTS(SELECT 1 FROM internal.gemini_routing_revisions
  WHERE revision=p_revision AND release_id=p_release AND configuration_digest=p_digest) THEN
  RAISE EXCEPTION 'gemini_suspension_revision_mismatch' USING ERRCODE='55000'; END IF;
 IF pg_catalog.jsonb_typeof(p_evidence) IS DISTINCT FROM 'object' OR pg_catalog.octet_length(p_evidence::TEXT)>65536 THEN RAISE EXCEPTION 'gemini_verification_invalid' USING ERRCODE='22023'; END IF;
 UPDATE internal.gemini_routing_revisions SET status='suspended',suspended_at=pg_catalog.clock_timestamp() WHERE revision=p_revision AND status='active';
 IF FOUND THEN
  UPDATE internal.gemini_activation_releases SET status='unhealthy' WHERE id=p_release;
  INSERT INTO internal.gemini_release_events(release_id,revision,kind,evidence) VALUES(p_release,p_revision,'suspended',p_evidence);
 END IF;
 -- No model rollback, refund, reinvocation, deletion or rewrite of old attempts.
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.suspend_gemini_release(UUID,BIGINT,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.claim_gemini_release_smoke(p_release UUID,p_case TEXT,p_configuration_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE release internal.gemini_activation_releases; smoke internal.gemini_release_smokes; token UUID;
BEGIN
    PERFORM internal.require_service_role();
 PERFORM 1 FROM internal.gemini_routing_head WHERE singleton FOR SHARE;
 SELECT * INTO release FROM internal.gemini_activation_releases WHERE id=p_release FOR UPDATE;
 IF NOT FOUND OR release.configuration_digest IS DISTINCT FROM p_configuration_digest OR release.status NOT IN ('prepared','verified')
  OR pg_catalog.clock_timestamp()<release.window_start OR pg_catalog.clock_timestamp()>=release.window_end
  OR release.expected_previous_revision IS DISTINCT FROM (SELECT revision FROM internal.gemini_routing_head WHERE singleton) THEN
  RAISE EXCEPTION 'gemini_smoke_not_eligible' USING ERRCODE='55000'; END IF;
 SELECT * INTO smoke FROM internal.gemini_release_smokes WHERE release_id=p_release AND case_id=p_case FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'gemini_smoke_case_unknown' USING ERRCODE='22023'; END IF;
 IF smoke.state<>'ready' THEN RETURN pg_catalog.jsonb_build_object('state',smoke.state,'receipt',smoke.receipt); END IF;
 IF EXISTS(SELECT 1 FROM internal.gemini_release_smokes WHERE release_id=p_release AND state IN ('claimed','dispatch_intent','failed','uncertain'))
  OR release.reserved_microusd+smoke.reservation_microusd>release.spending_cap_microusd THEN
  RAISE EXCEPTION 'gemini_smoke_stop_rule' USING ERRCODE='55000'; END IF;
 token:=extensions.gen_random_uuid();
 UPDATE internal.gemini_activation_releases SET reserved_microusd=reserved_microusd+smoke.reservation_microusd WHERE id=p_release;
 UPDATE internal.gemini_release_smokes SET state='claimed',owner_token=token,claimed_at=pg_catalog.clock_timestamp(),settlement='reserved' WHERE release_id=p_release AND case_id=p_case;
 RETURN pg_catalog.jsonb_build_object('state','claimed','owner_token',token,'case_digest',smoke.case_digest,'model',smoke.requested_model);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_gemini_release_smoke(UUID,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_gemini_release_smoke(UUID,TEXT,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.claim_gemini_release_smoke(uuid,text,text)','One non-reclaimable case owner within an explicitly authorized, bounded release; no caller provider settings.');

CREATE FUNCTION public.advance_gemini_release_smoke(p_release UUID,p_case TEXT,p_owner UUID,p_action TEXT,p_receipt JSONB DEFAULT NULL,p_valid_answer BOOLEAN DEFAULT FALSE)
RETURNS TEXT LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE release internal.gemini_activation_releases; smoke internal.gemini_release_smokes; price RECORD; next_state TEXT;
BEGIN
    PERFORM internal.require_service_role();
 PERFORM 1 FROM internal.gemini_routing_head WHERE singleton FOR SHARE;
 SELECT * INTO release FROM internal.gemini_activation_releases WHERE id=p_release FOR UPDATE;
 SELECT * INTO smoke FROM internal.gemini_release_smokes WHERE release_id=p_release AND case_id=p_case FOR UPDATE;
 IF NOT FOUND OR smoke.owner_token IS DISTINCT FROM p_owner OR p_owner IS NULL THEN RAISE EXCEPTION 'gemini_smoke_not_owned' USING ERRCODE='55000'; END IF;
 IF p_action='dispatch' THEN
  IF smoke.state<>'claimed' OR release.status NOT IN ('prepared','verified')
   OR pg_catalog.clock_timestamp()<release.window_start OR pg_catalog.clock_timestamp()>=release.window_end
   OR release.expected_previous_revision IS DISTINCT FROM (SELECT revision FROM internal.gemini_routing_head WHERE singleton) THEN
   RAISE EXCEPTION 'gemini_smoke_dispatch_closed' USING ERRCODE='55000'; END IF;
  UPDATE internal.gemini_release_smokes SET state='dispatch_intent',dispatch_intent_at=pg_catalog.clock_timestamp() WHERE release_id=p_release AND case_id=p_case;
  RETURN 'dispatch_intent';
 ELSIF p_action='receipt' THEN
  IF smoke.state NOT IN ('dispatch_intent','uncertain') OR NOT internal.gemini_response_receipt_valid(p_receipt) THEN RAISE EXCEPTION 'gemini_smoke_receipt_invalid' USING ERRCODE='22023'; END IF;
  IF smoke.receipt IS NOT NULL AND smoke.receipt IS DISTINCT FROM p_receipt THEN RAISE EXCEPTION 'gemini_smoke_receipt_conflict' USING ERRCODE='23505'; END IF;
  UPDATE internal.gemini_release_smokes SET receipt=p_receipt WHERE release_id=p_release AND case_id=p_case;
  RETURN smoke.state;
 ELSIF p_action='outcome' THEN
  IF NOT internal.gemini_response_receipt_valid(p_receipt) THEN RAISE EXCEPTION 'gemini_smoke_receipt_invalid' USING ERRCODE='22023'; END IF;
  IF smoke.state IN ('passed','failed') AND smoke.receipt=p_receipt THEN RETURN smoke.state; END IF;
  IF smoke.state<>'dispatch_intent' OR smoke.receipt IS DISTINCT FROM p_receipt THEN RAISE EXCEPTION 'gemini_smoke_outcome_conflict' USING ERRCODE='55000'; END IF;
  SELECT * INTO price FROM internal.price_gemini_receipt(p_receipt,smoke.dispatch_intent_at);
  next_state:=CASE WHEN p_valid_answer IS TRUE AND p_receipt->>'returnedModel'=smoke.requested_model
   AND p_receipt->'failure'='null'::JSONB AND price.cost IS NOT NULL AND price.cost<=smoke.reservation_microusd THEN 'passed' ELSE 'failed' END;
  UPDATE internal.gemini_release_smokes SET state=next_state,receipt=p_receipt,outcome_at=pg_catalog.clock_timestamp(),
   settlement=CASE WHEN price.cost IS NULL THEN 'unresolved' ELSE 'settled' END WHERE release_id=p_release AND case_id=p_case;
  RETURN next_state;
 ELSIF p_action='uncertain' AND smoke.state='dispatch_intent' THEN
  UPDATE internal.gemini_release_smokes SET state='uncertain',settlement='unresolved',outcome_at=pg_catalog.clock_timestamp() WHERE release_id=p_release AND case_id=p_case;
  RETURN 'uncertain';
 END IF;
 RAISE EXCEPTION 'gemini_smoke_transition_invalid' USING ERRCODE='55000';
END;
$$;
REVOKE ALL ON FUNCTION public.advance_gemini_release_smoke(UUID,TEXT,UUID,TEXT,JSONB,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.advance_gemini_release_smoke(UUID,TEXT,UUID,TEXT,JSONB,BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.advance_gemini_release_smoke(uuid,text,uuid,text,jsonb,boolean)','Exact owned smoke dispatch and response receipt; ambiguous dispatch cannot rerun or qualify activation.');
NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;
