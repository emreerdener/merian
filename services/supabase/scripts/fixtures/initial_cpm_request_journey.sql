-- Owned disposable database only. The original lease stays inside the fixture.
CREATE FUNCTION public.test_cpm_request_dispatch(binding JSONB, provenance JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a internal.initial_analysis_admissions; q internal.ai_quota_reservations; ack JSONB;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions;
 SELECT * INTO STRICT q FROM internal.ai_quota_reservations WHERE id=a.funding_binding_id;
 ack:=public.test_cpm_ack(NULL);
 IF binding IS DISTINCT FROM jsonb_build_object('owner_id',a.owner_id,'scan_id',a.scan_id,
  'submission_digest',a.submission_digest,'config_digest',a.configuration_digest,
  'funding_binding_id',a.funding_binding_id,'funding_binding_digest',a.funding_digest,
  'admission_receipt_id',ack->'admission_receipt_id','admission_receipt_digest',ack->'admission_receipt_digest') THEN
  RAISE EXCEPTION 'foreign prepared request' USING ERRCODE='ZX881';
 END IF;
 RETURN internal.commit_initial_analysis_dispatch(a.owner_id,a.scan_id,a.submission_digest,
  a.configuration_digest,a.funding_digest,a.assets_digest,q.lease_token,provenance);
END $$;

CREATE FUNCTION public.test_cpm_request_report(ref JSONB, usage_facts TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q internal.ai_quota_reservations;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT q FROM internal.ai_quota_reservations;
 RETURN internal.report_initial_analysis_usage((ref->>'owner_id')::uuid,(ref->>'scan_id')::uuid,
  ref->>'submission_digest',(ref->>'invocation_id')::uuid,q.lease_token,'draft',usage_facts);
END $$;

CREATE FUNCTION public.test_cpm_request_store(evidence JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ref JSONB:=evidence->'reference'; q internal.ai_quota_reservations;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO STRICT q FROM internal.ai_quota_reservations;
 RETURN internal.record_initial_analysis_result((ref->>'owner_id')::uuid,(ref->>'scan_id')::uuid,
  ref->>'submission_digest',(ref->>'invocation_id')::uuid,q.lease_token,(ref->>'result_evidence_id')::uuid,
  evidence->>'result_canonical',evidence->>'provenance_canonical',evidence->>'result_digest');
END $$;

CREATE FUNCTION public.test_cpm_request_recover(ref JSONB, digest TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.read_initial_analysis_result((ref->>'owner_id')::uuid,(ref->>'scan_id')::uuid,
  ref->>'submission_digest',(ref->>'result_evidence_id')::uuid,digest);
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_request_dispatch(jsonb,jsonb), public.test_cpm_request_report(jsonb,text),
 public.test_cpm_request_store(jsonb), public.test_cpm_request_recover(jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_request_dispatch(jsonb,jsonb), public.test_cpm_request_report(jsonb,text),
 public.test_cpm_request_store(jsonb), public.test_cpm_request_recover(jsonb,text) TO service_role;

CREATE FUNCTION public.test_cpm_request_complete(ref JSONB, digest TEXT, proof JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.complete_initial_analysis_cpm_v1((ref->>'owner_id')::uuid,(ref->>'scan_id')::uuid,
  ref->>'submission_digest',(ref->>'result_evidence_id')::uuid,digest,proof->>'retention_policy_digest',proof);
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_request_complete(jsonb,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_request_complete(jsonb,text,jsonb) TO service_role;
