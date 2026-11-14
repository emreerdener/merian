-- Bind background work at claim time. Never infer an old assignment from current routing.
SET lock_timeout='5s';
SET statement_timeout='5min';
CREATE TABLE internal.gemini_species_executions (
 job_id UUID NOT NULL REFERENCES public.species_enrichment_jobs(id) ON DELETE CASCADE,
 attempt_count INTEGER NOT NULL CHECK(attempt_count>0),
 owner_token UUID NOT NULL DEFAULT extensions.gen_random_uuid(),
 requested_model TEXT NOT NULL CHECK(requested_model IN ('gemini-2.5-flash','gemini-3.5-flash-lite')),
 assignment_revision BIGINT NOT NULL REFERENCES internal.gemini_routing_revisions(revision),
 state TEXT NOT NULL DEFAULT 'ready' CHECK(state IN ('ready','dispatch_intent','received','not_invoked')),
 dispatch_intent_at TIMESTAMPTZ, receipt JSONB CHECK(pg_catalog.octet_length(receipt::TEXT)<=4096),
 estimated_cost_microusd BIGINT, settlement TEXT NOT NULL DEFAULT 'unresolved' CHECK(settlement IN ('unresolved','settled','not_invoked')),
 PRIMARY KEY(job_id,attempt_count)
);
ALTER TABLE internal.gemini_species_executions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.gemini_species_executions FROM PUBLIC,anon,authenticated,service_role;
-- Older workers may already have invoked. A running row is not proof of an
-- unused transport; retain uncertainty without inventing a dispatch timestamp.
INSERT INTO internal.gemini_species_executions(job_id,attempt_count,requested_model,assignment_revision,state)
 SELECT id,attempts,'gemini-2.5-flash',0,'dispatch_intent' FROM public.species_enrichment_jobs
 WHERE status='running' AND attempts>0 AND content_group IN ('habitat','lookalikes','group_tags');

CREATE FUNCTION internal.bind_gemini_species_execution() RETURNS TRIGGER
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE assigned BIGINT; model TEXT; operation_name TEXT; policy internal.ai_quota_policies;
BEGIN
 IF NEW.content_group NOT IN ('habitat','lookalikes','group_tags') OR NEW.status<>'running'
  OR (OLD.status='running' AND OLD.attempts=NEW.attempts) THEN RETURN NEW; END IF;
 -- Unknown prior execution is never a retryable failed job, even after lease expiry.
 IF EXISTS(SELECT 1 FROM internal.gemini_species_executions WHERE job_id=NEW.id AND state='dispatch_intent') THEN
  RAISE EXCEPTION 'gemini_species_execution_uncertain' USING ERRCODE='55000'; END IF;
 operation_name:=CASE NEW.content_group WHEN 'habitat' THEN 'scan_overview_enrichment'
  WHEN 'lookalikes' THEN 'scan_lookalike_enrichment' ELSE 'scan_group_tag_enrichment' END;
 SELECT * INTO policy FROM internal.ai_quota_policies WHERE operation=operation_name AND effective_plan='free' AND allowed;
 IF NOT FOUND THEN RAISE EXCEPTION 'gemini_species_assignment_missing' USING ERRCODE='55000'; END IF;
 model:=policy.model;
 SELECT revision INTO assigned FROM internal.gemini_assignment_revisions WHERE operation=operation_name
  AND effective_plan='free' AND policy_version=policy.policy_version AND requested_model=model;
 IF NOT COALESCE(internal.gemini_dispatch_open(model,assigned),FALSE) THEN
  RAISE EXCEPTION 'gemini_species_dispatch_closed' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.gemini_species_executions(job_id,attempt_count,requested_model,assignment_revision)
  VALUES(NEW.id,NEW.attempts,model,assigned);
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.bind_gemini_species_execution() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER bind_gemini_species_execution AFTER UPDATE ON public.species_enrichment_jobs
 FOR EACH ROW EXECUTE FUNCTION internal.bind_gemini_species_execution();

CREATE FUNCTION public.read_gemini_species_execution(p_job UUID,p_attempt INTEGER) RETURNS JSONB
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE saved internal.gemini_species_executions;
BEGIN
    PERFORM internal.require_service_role();
 SELECT e.* INTO saved FROM internal.gemini_species_executions e JOIN public.species_enrichment_jobs j ON j.id=e.job_id
  WHERE e.job_id=p_job AND e.attempt_count=p_attempt AND j.attempts=p_attempt AND j.status='running';
 IF NOT FOUND OR saved.state<>'ready' THEN RAISE EXCEPTION 'gemini_species_not_owned' USING ERRCODE='55000'; END IF;
 RETURN pg_catalog.jsonb_build_object('model',saved.requested_model,'owner_token',saved.owner_token);
END;
$$;
REVOKE ALL ON FUNCTION public.read_gemini_species_execution(UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_gemini_species_execution(UUID,INTEGER) TO service_role;

CREATE FUNCTION public.advance_gemini_species_execution(p_job UUID,p_attempt INTEGER,p_owner UUID,p_action TEXT,p_receipt JSONB DEFAULT NULL)
 RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE saved internal.gemini_species_executions; price RECORD;
BEGIN
    PERFORM internal.require_service_role();
 -- Job before execution matches the claim trigger's lock order.
 PERFORM 1 FROM public.species_enrichment_jobs WHERE id=p_job AND attempts=p_attempt AND status='running' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'gemini_species_not_owned' USING ERRCODE='55000'; END IF;
 SELECT * INTO saved FROM internal.gemini_species_executions WHERE job_id=p_job AND attempt_count=p_attempt FOR UPDATE;
 IF NOT FOUND OR p_owner IS NULL OR saved.owner_token IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'gemini_species_not_owned' USING ERRCODE='55000'; END IF;
 IF p_action='dispatch' THEN
  PERFORM 1 FROM internal.gemini_routing_revisions WHERE revision=saved.assignment_revision FOR SHARE;
  IF saved.state<>'ready' OR NOT internal.gemini_dispatch_open(saved.requested_model,saved.assignment_revision) THEN
   RAISE EXCEPTION 'gemini_species_dispatch_closed' USING ERRCODE='55000'; END IF;
  UPDATE internal.gemini_species_executions SET state='dispatch_intent',dispatch_intent_at=pg_catalog.clock_timestamp() WHERE job_id=p_job AND attempt_count=p_attempt;
 ELSIF p_action='not_invoked' THEN
  IF saved.state NOT IN ('ready','dispatch_intent','not_invoked') THEN RAISE EXCEPTION 'gemini_species_transition_invalid' USING ERRCODE='55000'; END IF;
  UPDATE internal.gemini_species_executions SET state='not_invoked',estimated_cost_microusd=0,settlement='not_invoked'
   WHERE job_id=p_job AND attempt_count=p_attempt;
 ELSIF p_action='receipt' THEN
  IF NOT internal.gemini_response_receipt_valid(p_receipt) OR saved.state NOT IN ('dispatch_intent','received') THEN RAISE EXCEPTION 'gemini_species_receipt_invalid' USING ERRCODE='22023'; END IF;
  IF saved.receipt IS NOT NULL THEN
   IF saved.receipt IS DISTINCT FROM p_receipt THEN RAISE EXCEPTION 'gemini_species_receipt_conflict' USING ERRCODE='23505'; END IF;
   RETURN TRUE;
  END IF;
  SELECT * INTO price FROM internal.price_gemini_receipt(p_receipt,saved.dispatch_intent_at);
  UPDATE internal.gemini_species_executions SET state='received',receipt=p_receipt,estimated_cost_microusd=price.cost,
   settlement=CASE WHEN price.cost IS NULL THEN 'unresolved' ELSE 'settled' END WHERE job_id=p_job AND attempt_count=p_attempt;
 ELSE RAISE EXCEPTION 'gemini_species_transition_invalid' USING ERRCODE='22023'; END IF;
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.advance_gemini_species_execution(UUID,INTEGER,UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.advance_gemini_species_execution(UUID,INTEGER,UUID,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.read_gemini_species_execution(uuid,integer)','Read the immutable model and ownership token of an already claimed background job.'),
 ('service_role','public.advance_gemini_species_execution(uuid,integer,uuid,text,jsonb)','Single owned background transport and content-free response accounting; uncertainty prevents retry.');

-- A stale completion cannot settle a replacement claim. An intent without a
-- response remains running/uncertain; it must never be made retryable here.
CREATE FUNCTION public.complete_gemini_species_job(target_job_id UUID,expected_attempt INTEGER,succeeded BOOLEAN,error_message TEXT DEFAULT NULL)
 RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE execution internal.gemini_species_executions;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM 1 FROM public.species_enrichment_jobs WHERE id=target_job_id AND attempts=expected_attempt
  AND status='running' AND content_group IN ('habitat','lookalikes','group_tags') FOR UPDATE;
 IF NOT FOUND THEN RETURN FALSE; END IF;
 SELECT * INTO execution FROM internal.gemini_species_executions WHERE job_id=target_job_id AND attempt_count=expected_attempt FOR UPDATE;
 IF NOT FOUND OR execution.state='dispatch_intent' THEN RETURN FALSE; END IF;
 PERFORM public.complete_species_enrichment_job(target_job_id,succeeded,error_message);
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_gemini_species_job(UUID,INTEGER,BOOLEAN,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_gemini_species_job(UUID,INTEGER,BOOLEAN,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.complete_gemini_species_job(uuid,integer,boolean,text)','Complete only the current owned background attempt, preserving uncertain provider liabilities.');

-- Photo jobs retain their exact policy/model pair; defaults remain legacy.
ALTER TABLE internal.observation_photo_moderations DROP CONSTRAINT observation_photo_moderations_model_check;
ALTER TABLE internal.observation_photo_moderations DROP CONSTRAINT observation_photo_moderations_policy_version_check;
ALTER TABLE internal.observation_photo_moderations ADD CONSTRAINT observation_photo_moderations_profile_check
 CHECK((model='gemini-2.5-flash' AND policy_version='photo_publication_v1') OR
       (model='gemini-3.5-flash-lite' AND policy_version='photo_publication_v2'));

CREATE FUNCTION public.authorize_gemini_photo_transport(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID)
 RETURNS UUID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts;
BEGIN
    PERFORM internal.require_service_role();
 PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
 SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
 IF NOT FOUND OR attempt.state<>'dispatched' OR attempt.lease_token IS DISTINCT FROM p_token
  OR attempt.dispatch_expires_at<=pg_catalog.clock_timestamp() THEN RAISE EXCEPTION 'gemini_photo_not_owned' USING ERRCODE='55000'; END IF;
 RETURN public.authorize_gemini_transport((attempt.quota->>'reservation_id')::UUID,p_owner,p_token,attempt.attempt_count);
END;
$$;
REVOKE ALL ON FUNCTION public.authorize_gemini_photo_transport(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.authorize_gemini_photo_transport(UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.authorize_gemini_photo_transport(uuid,uuid,uuid,uuid)','Final owned photo moderation transport check after the existing irreversible dispatch grant.');

-- Extend exact returned-result model contracts without changing stored outcomes.
DO $migration$
DECLARE source TEXT; signature TEXT; old TEXT; replacement TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY['internal.valid_publication_photo_result(jsonb)','internal.validate_protected_insight_chat_reply(jsonb)'] LOOP
  source:=pg_catalog.pg_get_functiondef(signature::REGPROCEDURE);
  old:=CASE WHEN signature LIKE '%photo%' THEN 'p_result' ELSE 'p_reply' END || '->>''model'' IS DISTINCT FROM ''gemini-2.5-flash''';
  replacement:=CASE WHEN signature LIKE '%photo%' THEN 'p_result' ELSE 'p_reply' END || '->>''model'' NOT IN (''gemini-2.5-flash'',''gemini-3.5-flash-lite'')';
  IF (length(source)-length(replace(source,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'gemini_special_contract_drift'; END IF;
  EXECUTE replace(source,old,replacement);
 END LOOP;
END;
$migration$;

DO $migration$
DECLARE source TEXT; old TEXT; replacement TEXT;
BEGIN
 source:=pg_catalog.pg_get_functiondef('internal.admit_publication_photo_moderation(uuid,uuid,uuid,uuid,uuid,text)'::REGPROCEDURE);
 old:='prepared:=internal.revalidate_observation_publication_intent';
 replacement:='PERFORM 1 FROM internal.gemini_routing_head WHERE singleton FOR SHARE; prepared:=internal.revalidate_observation_publication_intent';
 IF (length(source)-length(replace(source,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'gemini_photo_admission_drift'; END IF;
 source:=replace(source,old,replacement);
 old:=$old$INSERT INTO internal.observation_photo_moderations(operation_id,media_id,observation_id,analysis_id,owner_id,source)
        VALUES(p_operation,p_media,p_observation,(prepared#>>'{request,analysis_id}')::UUID,p_owner,source) RETURNING * INTO job;$old$;
 replacement:=$new$INSERT INTO internal.observation_photo_moderations(operation_id,media_id,observation_id,analysis_id,owner_id,source,model,policy_version)
        SELECT p_operation,p_media,p_observation,(prepared#>>'{request,analysis_id}')::UUID,p_owner,source,policy.model,
          CASE WHEN policy.model='gemini-3.5-flash-lite' THEN 'photo_publication_v2' ELSE 'photo_publication_v1' END
        FROM internal.ai_quota_policies policy WHERE policy.operation='observation_photo_publication_moderation' AND policy.effective_plan='free' AND policy.allowed
        RETURNING * INTO job;
        IF NOT FOUND THEN RAISE EXCEPTION 'gemini_photo_assignment_missing' USING ERRCODE='55000'; END IF;$new$;
 IF (length(source)-length(replace(source,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'gemini_photo_admission_drift'; END IF;
 EXECUTE replace(source,old,replacement);
 source:=pg_catalog.pg_get_functiondef('internal.prepare_publication_photo_execution(uuid,uuid,uuid,uuid,jsonb)'::REGPROCEDURE);
 old:=$old$'policy_sha256','b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9'$old$;
 replacement:=$new$'policy_sha256',CASE job.policy_version WHEN 'photo_publication_v1' THEN 'b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9' WHEN 'photo_publication_v2' THEN '16dd00259e8a7ea38f5fc2ec03a8b00bad5053c817facdcc45c2d4ffbe98fea8' END$new$;
 IF (length(source)-length(replace(source,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'gemini_photo_proof_drift'; END IF;
 EXECUTE replace(source,old,replacement);
END;
$migration$;
NOTIFY pgrst,'reload schema';
RESET lock_timeout;
RESET statement_timeout;
