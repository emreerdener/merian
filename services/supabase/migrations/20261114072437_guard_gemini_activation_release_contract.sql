SET lock_timeout='5s';
SET statement_timeout='5min';
ALTER TABLE internal.gemini_routing_revisions ADD CONSTRAINT gemini_routing_release_fk
 FOREIGN KEY(release_id) REFERENCES internal.gemini_activation_releases(id);

CREATE FUNCTION internal.gemini_assignment_manifest() RETURNS JSONB LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('policy',pg_catalog.to_jsonb(p)-'updated_at',
 'bindings',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(b) ORDER BY b.input_profile)
  FROM internal.identification_provider_bindings b WHERE b.operation=p.operation AND b.effective_plan=p.effective_plan
   AND b.model=p.model AND b.policy_version=p.policy_version),'[]'::JSONB)) ORDER BY p.operation,p.effective_plan)
 FROM internal.ai_quota_policies p;
$$;
REVOKE ALL ON FUNCTION internal.gemini_assignment_manifest() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.register_gemini_release(p_manifest TEXT) RETURNS UUID
 LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE m JSONB; config JSONB; saved internal.gemini_activation_releases; item JSONB; rid UUID;
BEGIN
 IF pg_catalog.octet_length(p_manifest)>65536 THEN RAISE EXCEPTION 'gemini_release_manifest_invalid' USING ERRCODE='22023'; END IF;
 m:=p_manifest::JSONB; config:=(m->>'configuration_text')::JSONB; rid:=(m->>'release_id')::UUID;
 IF pg_catalog.jsonb_typeof(m) IS DISTINCT FROM 'object'
  OR NOT m ?& ARRAY['version','release_id','target','backend_sha','configuration_digest','configuration_text','app','authorization','expected_previous_revision','window_start','window_end']
  OR m-ARRAY['version','release_id','target','backend_sha','configuration_digest','configuration_text','app','authorization','expected_previous_revision','window_start','window_end']<>'{}'::JSONB
  OR m->'version'<>'1'::JSONB OR pg_catalog.jsonb_typeof(config) IS DISTINCT FROM 'object'
  OR m->>'configuration_digest' IS DISTINCT FROM pg_catalog.encode(extensions.digest(pg_catalog.convert_to(m->>'configuration_text','UTF8'),'sha256'),'hex')
  OR config->'required_gates' IS DISTINCT FROM '{"candidate_validation":true,"exact_source":true,"migrations":true,"privileged_routines":true,"function_deployment":true,"authorization_smokes":true,"independent_holds":true}'::JSONB
  OR pg_catalog.jsonb_typeof(config->'required_functions') IS DISTINCT FROM 'object'
  OR (SELECT count(*) FROM pg_catalog.jsonb_object_keys(config->'required_functions'))<20
  OR NOT (config->'required_functions') ? 'gemini-release-smoke'
  OR pg_catalog.jsonb_typeof(config->'smoke_cases') IS DISTINCT FROM 'array'
  OR pg_catalog.jsonb_array_length(config->'smoke_cases')<8
  OR NOT (m->'authorization') @> '{"backend_deployment":true,"activation":true,"provider_smokes":true,"protective_suspension":true}'::JSONB
  OR pg_catalog.jsonb_typeof(m#>'{app,testflight_group}') IS DISTINCT FROM 'string'
  OR length(m#>>'{app,testflight_group}') NOT BETWEEN 1 AND 128
  OR (m#>>'{app,availability_checked_at}')::TIMESTAMPTZ>pg_catalog.clock_timestamp()
  OR (m#>>'{app,availability_checked_at}')::TIMESTAMPTZ<(m->>'window_start')::TIMESTAMPTZ-INTERVAL '7 days' THEN
  RAISE EXCEPTION 'gemini_release_manifest_invalid' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM internal.gemini_routing_head WHERE singleton FOR SHARE;
 SELECT * INTO saved FROM internal.gemini_activation_releases WHERE id=rid FOR UPDATE;
 IF FOUND THEN
  IF saved.manifest IS DISTINCT FROM p_manifest THEN RAISE EXCEPTION 'gemini_release_identity_conflict' USING ERRCODE='23505'; END IF;
  RETURN rid;
 END IF;
 PERFORM 1 FROM internal.gemini_routing_head WHERE singleton AND revision=(m->>'expected_previous_revision')::BIGINT FOR SHARE;
 IF NOT FOUND OR config->'assignments' IS DISTINCT FROM internal.gemini_assignment_manifest()
  OR pg_catalog.clock_timestamp()>=(m->>'window_end')::TIMESTAMPTZ THEN RAISE EXCEPTION 'gemini_release_stale' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.gemini_activation_releases(id,target,backend_sha,configuration_digest,manifest,app_version,app_build,app_source_fingerprint,
 authorization_reference,expected_previous_revision,window_start,window_end,spending_cap_microusd)
 VALUES(rid,m->>'target',m->>'backend_sha',m->>'configuration_digest',p_manifest,m#>>'{app,version}',m#>>'{app,build}',m#>>'{app,source_fingerprint}',
 m#>>'{authorization,reference}',(m->>'expected_previous_revision')::BIGINT,(m->>'window_start')::TIMESTAMPTZ,(m->>'window_end')::TIMESTAMPTZ,(m#>>'{authorization,spending_cap_microusd}')::BIGINT);
 FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(config->'smoke_cases') LOOP
  IF item-ARRAY['id','digest','model','reservation_microusd']<>'{}'::JSONB THEN RAISE EXCEPTION 'gemini_smoke_case_invalid' USING ERRCODE='22023'; END IF;
  INSERT INTO internal.gemini_release_smokes(release_id,case_id,case_digest,requested_model,reservation_microusd)
   VALUES(rid,item->>'id',item->>'digest',item->>'model',(item->>'reservation_microusd')::BIGINT);
 END LOOP;
 IF (SELECT sum(reservation_microusd) FROM internal.gemini_release_smokes WHERE release_id=rid)>(m#>>'{authorization,spending_cap_microusd}')::BIGINT THEN
  RAISE EXCEPTION 'gemini_smoke_budget_insufficient' USING ERRCODE='22023'; END IF;
 RETURN rid;
END;
$$;
REVOKE ALL ON FUNCTION internal.register_gemini_release(TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_gemini_release_smoke_scope(p_release UUID,p_case TEXT,p_functions JSONB) RETURNS TEXT
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE saved internal.gemini_activation_releases;
BEGIN
    PERFORM internal.require_service_role();
 SELECT * INTO saved FROM internal.gemini_activation_releases WHERE id=p_release;
 IF NOT FOUND OR saved.status NOT IN ('prepared','verified')
  OR pg_catalog.clock_timestamp()<saved.window_start OR pg_catalog.clock_timestamp()>=saved.window_end
  OR (saved.manifest::JSONB->>'configuration_text')::JSONB->'required_functions' IS DISTINCT FROM p_functions
  OR NOT EXISTS(SELECT 1 FROM internal.gemini_release_smokes WHERE release_id=p_release AND case_id=p_case) THEN
  RAISE EXCEPTION 'gemini_smoke_scope_invalid' USING ERRCODE='55000'; END IF;
 RETURN saved.configuration_digest;
END;
$$;
REVOKE ALL ON FUNCTION public.read_gemini_release_smoke_scope(UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_gemini_release_smoke_scope(UUID,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.read_gemini_release_smoke_scope(uuid,text,jsonb)','Bind the closed deployed smoke executor to the authorized release configuration and function identities.');

CREATE FUNCTION internal.verify_gemini_release(p_release UUID,p_functions JSONB,p_gates JSONB) RETURNS BOOLEAN
 LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE saved internal.gemini_activation_releases; evidence JSONB;
BEGIN
 PERFORM 1 FROM internal.gemini_routing_head WHERE singleton FOR SHARE;
 SELECT * INTO saved FROM internal.gemini_activation_releases WHERE id=p_release FOR UPDATE;
 IF NOT FOUND OR saved.status NOT IN ('prepared','verified') OR pg_catalog.clock_timestamp()>=saved.window_end
  OR (saved.manifest::JSONB->>'configuration_text')::JSONB->'required_functions' IS DISTINCT FROM p_functions
  OR (saved.manifest::JSONB->>'configuration_text')::JSONB->'required_gates' IS DISTINCT FROM p_gates
  OR (saved.manifest::JSONB->>'configuration_text')::JSONB->'assignments' IS DISTINCT FROM internal.gemini_assignment_manifest()
  OR EXISTS(SELECT 1 FROM internal.gemini_release_smokes WHERE release_id=p_release AND (state<>'passed' OR settlement<>'settled')) THEN
  RAISE EXCEPTION 'gemini_release_verification_failed' USING ERRCODE='55000'; END IF;
 evidence:=pg_catalog.jsonb_build_object('required_functions',p_functions,'technical_gates',p_gates,'independent_holds',internal.gemini_independent_holds());
 IF saved.verification IS NOT NULL AND saved.verification IS DISTINCT FROM evidence THEN RAISE EXCEPTION 'gemini_verification_conflict' USING ERRCODE='23505'; END IF;
 IF saved.verification IS NULL THEN
  UPDATE internal.gemini_activation_releases SET status='verified',verification=evidence WHERE id=p_release;
  INSERT INTO internal.gemini_release_events(release_id,kind,evidence) VALUES(p_release,'verified',evidence);
 END IF;
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.verify_gemini_release(UUID,JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

DO $migration$
DECLARE source TEXT; anchor TEXT;
BEGIN
 source:=pg_catalog.pg_get_functiondef('internal.activate_gemini_release(uuid,text,text,text,jsonb,jsonb)'::REGPROCEDURE);
 source:=replace(source,'release.manifest::JSONB->''required_functions''','(release.manifest::JSONB->>''configuration_text'')::JSONB->''required_functions''');
 source:=replace(source,'release.manifest::JSONB->''required_gates''','(release.manifest::JSONB->>''configuration_text'')::JSONB->''required_gates''');
 anchor:=' holds:=internal.gemini_independent_holds();';
 IF strpos(source,anchor)=0 THEN RAISE EXCEPTION 'gemini_activation_source_drift'; END IF;
 source:=replace(source,anchor,$new$ LOCK TABLE internal.ai_quota_policies,internal.identification_provider_bindings IN SHARE ROW EXCLUSIVE MODE;
 IF (release.manifest::JSONB->>'configuration_text')::JSONB->'assignments' IS DISTINCT FROM internal.gemini_assignment_manifest() THEN
  RAISE EXCEPTION 'gemini_assignment_manifest_changed' USING ERRCODE='55000'; END IF;
$new$ || anchor);
 EXECUTE source;
END;
$migration$;
NOTIFY pgrst,'reload schema';
RESET lock_timeout;
RESET statement_timeout;
