-- Disposable qualification fixture only. Never installed by a migration.
CREATE FUNCTION public.test_dispatch_provenance() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT '{"version":1,"provider":"gemini","binding":"gemini_baseline_v1","model":"gemini-2.5-flash","variant":"multimodal","operation":"scan_identification","policy_version":1,"prompt":"identify_vision_v1","schema":"merian_identify_v1","confidence":"unqualified","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":null,"timeout_ms":90000,"generation":{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}}'::JSONB
$$;

REVOKE ALL ON FUNCTION public.test_dispatch_provenance() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_initial_dispatch(p_scan UUID, p_fault TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a internal.initial_analysis_admissions; q internal.ai_quota_reservations; att internal.identification_provider_attempts; provenance JSONB; result JSONB;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=p_scan;
 SELECT * INTO STRICT q FROM internal.ai_quota_reservations WHERE id=a.funding_binding_id;
 SELECT * INTO STRICT att FROM internal.identification_provider_attempts WHERE reservation_id=q.id AND attempt_count=1;
 provenance:=public.test_dispatch_provenance()||jsonb_build_object('provider',att.provider,'binding',att.binding,
 'model',COALESCE(att.provider_model,att.model),'policy_version',att.policy_version,
 'variant',CASE WHEN att.input_profile='vision_compat_v1' THEN 'vision_compat' ELSE 'multimodal' END);
 IF p_fault='provenance' THEN provenance:=provenance||jsonb_build_object('model','unassigned'); END IF;
 IF p_fault='lease' THEN q.lease_token:=gen_random_uuid(); END IF;
 IF p_fault='configuration' THEN a.configuration_digest:=repeat('0',64); END IF;
 result:=internal.commit_initial_analysis_dispatch(a.owner_id,p_scan,a.submission_digest,a.configuration_digest,
 a.funding_digest,a.assets_digest,q.lease_token,provenance);
 IF result->>'outcome' IS DISTINCT FROM 'fresh' OR result->>'invocation_id' IS NULL THEN
 RAISE EXCEPTION USING ERRCODE='ZX801'; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.test_initial_dispatch(UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_initial_dispatch(UUID,TEXT) TO service_role;
