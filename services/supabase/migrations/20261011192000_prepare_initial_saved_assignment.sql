-- Inactive no-media v2 preparation identity and original funding only.
SET lock_timeout='5s';
SET statement_timeout='2min';

CREATE FUNCTION internal.initial_assignment_schema_v2() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$
 SELECT '{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"candidate_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"route":{"type":"string","max_bytes":128,"enum":["identify-describe","identify-multimodal"]},"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"effective_tier":{"type":"string","max_bytes":128,"enum":["free","pro"]},"flash_fallback_used":{"type":"boolean"},"quota_model":{"type":"string","max_bytes":128},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"provider":{"type":"string","max_bytes":128,"enum":["gemini","openai"]},"binding":{"type":"string","max_bytes":128},"processor_permission":{"type":"string","max_bytes":128,"enum":["google_gemini","openai"]},"input_profile":{"type":"string","max_bytes":128,"enum":["description_compat_v1","multimodal_text_v1"]},"provider_model":{"type":"string","max_bytes":128,"nullable":true},"effective_model":{"type":"string","max_bytes":128},"minimum_client_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_client_protocol":{"type":"integer","minimum":3,"maximum":3},"minimum_identification_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6},"asset_manifest_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"retention_owner":{"type":"string","max_bytes":128,"enum":["initial_engine_release_archive"]},"resolver_id":{"type":"string","max_bytes":128,"enum":["git_blob_sha256_v1"]},"preparation":{"type":"object","properties":{"kind":{"type":"string","max_bytes":128,"enum":["none"]},"profile":{"type":"string","max_bytes":0,"enum":[],"nullable":true},"options":{"type":"string","max_bytes":0,"enum":[],"nullable":true}}},"experiment":{"type":"string","max_bytes":0,"enum":[],"nullable":true}}}'::JSONB;
$schema$;
REVOKE ALL ON FUNCTION internal.initial_assignment_schema_v2() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_preparation_candidate_schema_v2() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$
 SELECT '{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"variant":{"type":"string","max_bytes":128,"enum":["no_media"]},"input":{"type":"object","properties":{"schema_version":{"type":"integer","minimum":1,"maximum":1},"route":{"type":"string","enum":["identify","identify-describe","identify-multimodal"],"max_bytes":128},"ordered_descriptions":{"type":"array","items":{"type":"string","max_bytes":65530},"max_items":64},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["image","audio","video"],"max_bytes":128},"content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_byte_count":{"type":"integer","minimum":1,"maximum":12582912},"source_sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"input_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"source_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"clip_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"frame_index":{"type":"integer","minimum":0,"maximum":149,"nullable":true},"focus_region":{"type":"object","properties":{"x":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"y":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"width":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"height":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"source":{"type":"string","enum":["vision_objectness"],"max_bytes":128}},"nullable":true},"transform":{"type":"string","enum":["identity_v1","initial_audio_v1","video_frame_v1"],"max_bytes":128},"source_content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"transform_parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}}}},"max_items":8},"owner_timeline":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["description","media"],"max_bytes":128},"index":{"type":"integer","minimum":0,"maximum":63}}},"max_items":128},"capture":{"type":"object","properties":{"has_video":{"type":"boolean"},"video_clip_count":{"type":"integer","minimum":0,"maximum":64},"declared_video_frame_count":{"type":"integer","minimum":0,"maximum":150},"video_inference_frame_count":{"type":"integer","minimum":0,"maximum":150}}},"context":{"type":"object","properties":{"depth_scale_text":{"type":"string","max_bytes":8192,"nullable":true},"semantic_location":{"type":"string","max_bytes":8192,"nullable":true},"weather_condition":{"type":"string","max_bytes":8192,"nullable":true},"device_locale":{"type":"string","max_bytes":8192,"nullable":true},"device_time_zone":{"type":"string","max_bytes":8192,"nullable":true},"device_region":{"type":"string","max_bytes":8192,"nullable":true},"time_of_day":{"type":"string","max_bytes":8192,"nullable":true},"gps_latitude":{"type":"decimal","minimum":"-90","maximum":"90","max_bytes":326,"nullable":true},"gps_longitude":{"type":"decimal","minimum":"-180","maximum":"180","max_bytes":326,"nullable":true},"gps_elevation":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"zoom_factor":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"estimated_size_cm":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"weather_temperature_f":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"current_month":{"type":"integer","minimum":1,"maximum":12,"nullable":true}}},"options":{"type":"object","properties":{"timestamp":{"type":"string","max_bytes":128,"nullable":true},"geoprivacy":{"type":"string","enum":["open","obscured","private"],"max_bytes":128,"nullable":true},"public_location_label":{"type":"string","max_bytes":512,"nullable":true},"preferred_goal":{"type":"object","properties":{"user_field_trip_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"item_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"}},"nullable":true},"observation_context":{"type":"object","nullable":true,"properties":{"free_text":{"type":"string","max_bytes":65530}}}}},"admission":{"type":"object","properties":{"client_protocol":{"type":"integer","minimum":3,"maximum":3},"identification_protocol":{"type":"integer","minimum":6,"maximum":6},"expected_processor_permission":{"type":"string","enum":["google_gemini","openai"],"max_bytes":32}}},"experiment":{"type":"object","nullable":true,"properties":{"kind":{"type":"string","enum":["audio_comparison","audio_prompt_comparison"],"max_bytes":64},"plan_sha256":{"type":"string","pattern":"^[0-9a-f]{64}$","max_bytes":64},"slot":{"type":"integer","minimum":0,"maximum":1000000}}}}}}}'::JSONB;
$schema$;
REVOKE ALL ON FUNCTION internal.initial_preparation_candidate_schema_v2() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_preparation_digest(p_domain TEXT,p_text TEXT) RETURNS TEXT
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
BEGIN
 IF p_domain IS NULL OR p_domain NOT IN ('preparation-candidate','assignment') OR p_text IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.'||p_domain||E'.v2\n'||p_text,'UTF8'),'sha256'),'hex');
END;
$$;
CREATE FUNCTION internal.parse_initial_preparation_candidate(p_text TEXT) RETURNS JSONB
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB;
BEGIN
 IF p_text IS NULL OR octet_length(p_text)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text
  OR NOT internal.initial_schema_matches(value,internal.initial_preparation_candidate_schema_v2()) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.parse_initial_input(internal.initial_canonical(value->'input'));
 IF value#>'{input,media}'<>'[]'::JSONB OR value#>>'{input,route}' NOT IN ('identify-describe','identify-multimodal')
  OR value#>'{input,experiment}'<>'null'::JSONB THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 RETURN value;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_preparation_digest(TEXT,TEXT),internal.parse_initial_preparation_candidate(TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.initial_analysis_preparation_intents(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_operation_fences(scan_id),
 owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 canonical_candidate TEXT NOT NULL CHECK(octet_length(canonical_candidate)<=1048576),
 candidate_digest TEXT NOT NULL CHECK(candidate_digest=internal.initial_preparation_digest('preparation-candidate',canonical_candidate)),
 canonical_assignment TEXT NOT NULL CHECK(octet_length(canonical_assignment)<=65536),
 assignment_digest TEXT NOT NULL CHECK(assignment_digest=internal.initial_preparation_digest('assignment',canonical_assignment)),
 created_at TIMESTAMPTZ NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL CHECK(expires_at=created_at+INTERVAL '300 seconds'),
 UNIQUE(scan_id,owner_id),
 CHECK(internal.parse_initial_preparation_candidate(canonical_candidate) IS NOT NULL),
 CHECK(internal.initial_canonical(canonical_assignment::JSONB)=canonical_assignment),
 CHECK(internal.initial_schema_matches(canonical_assignment::JSONB,internal.initial_assignment_schema_v2())),
 CHECK(canonical_assignment::JSONB->>'candidate_digest'=candidate_digest)
);
CREATE INDEX initial_analysis_preparation_intents_owner ON internal.initial_analysis_preparation_intents(owner_id,scan_id);
ALTER TABLE internal.initial_analysis_preparation_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_analysis_preparation_intents FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO internal.ghost_profile_merge_reference_policies
 (source_schema,source_table,source_column,referenced_schema,referenced_table,referenced_column,strategy,execution_order,handler_key,purpose)
VALUES('internal','initial_analysis_preparation_intents','owner_id','public','users','id','preserve',902,NULL,
 'Reject transfer while the original preparation intent exists; cancellation/erasure must retire it without rebinding ownership.');
ALTER TABLE internal.initial_analysis_admissions
 ADD COLUMN binding_version INTEGER NOT NULL DEFAULT 1 CHECK(binding_version IN (1,2)),
 ADD COLUMN preparation_candidate_digest TEXT,
 ADD COLUMN preparation_assignment_digest TEXT,
 ADD CONSTRAINT initial_admission_preparation_version CHECK(
  (binding_version=1 AND preparation_candidate_digest IS NULL AND preparation_assignment_digest IS NULL)
  OR (binding_version=2 AND preparation_candidate_digest ~ '^[0-9a-f]{64}$' AND preparation_candidate_digest IS NOT NULL
   AND preparation_assignment_digest ~ '^[0-9a-f]{64}$' AND preparation_assignment_digest IS NOT NULL));

-- All new catalog locks fail fast at FIRST acquisition. Shared selectors only
-- reenter these locks; existing v1 paths and their blocking semantics are intact.
CREATE FUNCTION internal.resolve_initial_preparation_assignment(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_plan TEXT,p_fallback BOOLEAN
) RETURNS TEXT LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE input JSONB; profile TEXT; policy internal.ai_quota_policies;
 binding internal.identification_provider_bindings; rollout internal.initial_analysis_rollout;
 accepted_protocol INTEGER; accepted_capability INTEGER; assignment JSONB; manifest JSONB;
BEGIN
 input:=internal.parse_initial_preparation_candidate(p_candidate)->'input';
 profile:=internal.initial_input_semantics(input);
 SELECT * INTO rollout FROM internal.initial_analysis_rollout WHERE singleton FOR SHARE NOWAIT;
 IF rollout.initial_analysis_lifecycle_enabled IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 SELECT a.manifest INTO manifest FROM internal.initial_analysis_configuration_assets a WHERE a.digest=rollout.configuration_assets_digest;
 IF manifest IS NULL OR manifest->>'retention_owner' IS DISTINCT FROM 'initial_engine_release_archive'
  OR manifest->>'resolver_id' IS DISTINCT FROM 'git_blob_sha256_v1'
  OR manifest->'schema_version' IS DISTINCT FROM '1'::JSONB
  OR COALESCE(manifest->>'repository_revision','') !~ '^[0-9a-f]{40}$'
  OR jsonb_typeof(manifest->'roots') IS DISTINCT FROM 'array'
  OR jsonb_typeof(manifest->'files') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 IF jsonb_array_length(manifest->'roots')=0 OR jsonb_array_length(manifest->'files')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'roots') root
   WHERE jsonb_typeof(root)<>'string' OR length(root#>>'{}')=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'files') file
   WHERE jsonb_typeof(file)<>'object' OR COALESCE(file->>'path','')=''
    OR COALESCE(file->>'sha256','') !~ '^[0-9a-f]{64}$') THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM operation FROM internal.ai_quota_policies WHERE operation='scan_identification' AND effective_plan=p_plan FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_quota_policy_missing' USING ERRCODE='P0001'; END IF;
 SELECT * INTO policy FROM internal.resolve_quota_policy('scan_identification',p_plan);
 PERFORM operation FROM internal.identification_provider_bindings WHERE operation='scan_identification' AND effective_plan=p_plan
  AND model=policy.model AND policy_version=policy.policy_version AND input_profile=profile FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE='P0001'; END IF;
 SELECT * INTO binding FROM internal.resolve_identification_provider_binding('scan_identification',p_plan,policy.model,policy.policy_version,profile);
 accepted_protocol:=internal.require_identification_client_protocol(p_owner,'scan_identification',p_scan,profile,
  (input#>>'{admission,client_protocol}')::INTEGER,FALSE,binding.minimum_client_protocol);
 accepted_capability:=internal.require_identification_capability(p_owner,'scan_identification',p_scan,profile,
  (input#>>'{admission,identification_protocol}')::INTEGER,FALSE,binding.minimum_identification_protocol);
 IF input#>>'{admission,expected_processor_permission}' IS DISTINCT FROM binding.processor_permission THEN
  RAISE EXCEPTION 'ai_identification_preflight_changed' USING ERRCODE='P0001'; END IF;
 PERFORM config_key FROM internal.ai_consent_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 -- Existing rows protect UPDATE/DELETE; immediate owner FKs serialize new rows
 -- and owner reassignment against the outer users UPDATE lock.
 PERFORM id FROM public.user_adult_eligibility_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM id FROM public.user_terms_acceptance_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM id FROM public.user_ai_consent_events WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM internal.require_identification_processor_consent(p_owner,binding.processor_permission);
 assignment:=jsonb_build_object('version',2,'candidate_digest',internal.initial_preparation_digest('preparation-candidate',p_candidate),
  'route',input->>'route','operation','scan_identification','effective_plan',p_plan,
  'effective_tier',CASE WHEN p_plan='free' THEN 'free' ELSE 'pro' END,'flash_fallback_used',p_fallback,
  'quota_model',policy.model,'policy_version',policy.policy_version,'provider',binding.provider,'binding',binding.binding,
  'processor_permission',binding.processor_permission,'input_profile',profile,'provider_model',binding.provider_model,
  'effective_model',COALESCE(binding.provider_model,policy.model),'minimum_client_protocol',binding.minimum_client_protocol,
  'accepted_client_protocol',accepted_protocol,'minimum_identification_protocol',binding.minimum_identification_protocol,
  'accepted_identification_protocol',accepted_capability,'asset_manifest_digest',rollout.configuration_assets_digest,
  'retention_owner','initial_engine_release_archive','resolver_id','git_blob_sha256_v1',
  'preparation',jsonb_build_object('kind','none','profile',NULL,'options',NULL),'experiment',NULL);
 IF NOT internal.initial_schema_matches(assignment,internal.initial_assignment_schema_v2()) THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 RETURN internal.initial_canonical(assignment);
END;
$$;
REVOKE ALL ON FUNCTION internal.resolve_initial_preparation_assignment(UUID,UUID,TEXT,TEXT,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.lock_initial_preparation_scope(p_owner UUID,p_scan UUID) RETURNS VOID
LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE owned_by UUID; retired BOOLEAN;
BEGIN
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id,is_tombstoned INTO owned_by,retired FROM public.scans WHERE id=p_scan FOR UPDATE;
 IF FOUND AND (owned_by IS DISTINCT FROM p_owner OR retired) THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
  RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan AND internal.initial_cancellation_dispatch(state) IS NOT NULL) THEN
  RAISE EXCEPTION 'initial_analysis_cancelled' USING ERRCODE='55000'; END IF;
END;
$$;
CREATE FUNCTION internal.assert_initial_preparation_unfunded(p_owner UUID,p_scan UUID) RETURNS VOID
LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id<>p_owner) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_initial_preparation_scope(UUID,UUID),internal.assert_initial_preparation_unfunded(UUID,UUID)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.assert_initial_preparation_assignment(
 p_owner UUID,p_scan UUID,p_plan TEXT,p_fallback BOOLEAN,p_base BOOLEAN
) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; actual TEXT;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner
  OR current_setting('merian.initial_preparation_funding',TRUE) IS DISTINCT FROM p_owner::TEXT||':'||p_scan::TEXT
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 IF NOT p_base THEN PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan); END IF;
 actual:=internal.resolve_initial_preparation_assignment(p_owner,p_scan,saved.canonical_candidate,p_plan,p_fallback);
 PERFORM pg_advisory_xact_lock(hashtextextended(p_owner::TEXT||':scan_identification:'||p_scan::TEXT,0::BIGINT));
 -- After all decision locks and the exact request wait; never use creation or
 -- transaction-start time as authority to begin new funding.
 IF clock_timestamp()>=saved.expires_at THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 IF actual IS DISTINCT FROM saved.canonical_assignment THEN
  RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE='55000'; END IF;
 IF p_base AND current_setting('merian.initial_preparation_compared',TRUE)
   IS DISTINCT FROM p_owner::TEXT||':'||p_scan::TEXT||':'||saved.assignment_digest THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 IF NOT p_base THEN
  PERFORM set_config('merian.initial_preparation_compared',p_owner::TEXT||':'||p_scan::TEXT||':'||saved.assignment_digest,TRUE);
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_preparation_assignment(UUID,UUID,TEXT,BOOLEAN,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

-- Retain exact v1 response bytes. New readers alone accept the v2 extension.
CREATE OR REPLACE FUNCTION internal.initial_admission_response(saved internal.initial_analysis_admissions,route TEXT,outcome TEXT)
RETURNS JSONB LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT jsonb_build_object('outcome',outcome,'binding',jsonb_build_object('version',saved.binding_version,
 'owner_id',saved.owner_id,'scan_id',saved.scan_id,'route',route,'submission_digest',saved.submission_digest,
 'configuration_digest',saved.configuration_digest,'funding_digest',saved.funding_digest,'descriptions_digest',saved.descriptions_digest,
 'funding_binding_id',saved.funding_binding_id,'assets_digest',saved.assets_digest)
 ||CASE WHEN saved.binding_version=2 THEN jsonb_build_object('candidate_digest',saved.preparation_candidate_digest,
 'assignment_digest',saved.preparation_assignment_digest) ELSE '{}'::JSONB END);
$$;

CREATE FUNCTION internal.recover_initial_preparation_admission(p_owner UUID,p_scan UUID) RETURNS JSONB
LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_admissions; submission internal.initial_analysis_submissions; candidate TEXT; configuration JSONB;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.binding_version<>2 OR saved.owner_id IS DISTINCT FROM p_owner OR submission.owner_id IS DISTINCT FROM p_owner THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 candidate:=internal.initial_canonical(jsonb_build_object('version',2,'variant','no_media','input',submission.input_snapshot));
 PERFORM internal.parse_initial_preparation_candidate(candidate);
 configuration:=submission.configuration_snapshot;
 IF saved.canonical_input IS DISTINCT FROM internal.initial_canonical(submission.input_snapshot)
  OR saved.submission_digest IS DISTINCT FROM internal.initial_digest('input',saved.canonical_input)
  OR saved.preparation_candidate_digest IS DISTINCT FROM internal.initial_preparation_digest('preparation-candidate',candidate)
  OR configuration->>'version' IS DISTINCT FROM '2'
  OR saved.preparation_assignment_digest IS DISTINCT FROM internal.initial_preparation_digest('assignment',internal.initial_canonical(configuration->'assignment'))
  OR configuration#>>'{assignment,candidate_digest}' IS DISTINCT FROM saved.preparation_candidate_digest
  OR NOT internal.initial_schema_matches(configuration->'assignment',internal.initial_assignment_schema_v2())
  OR saved.configuration_digest IS DISTINCT FROM internal.initial_digest('configuration',internal.initial_canonical(configuration))
  OR saved.funding_digest IS DISTINCT FROM internal.initial_digest('funding',internal.initial_canonical(submission.funding_snapshot))
  OR saved.descriptions_digest IS DISTINCT FROM internal.initial_digest('descriptions',internal.initial_canonical(submission.ordered_descriptions))
  OR submission.ordered_descriptions IS DISTINCT FROM submission.input_snapshot->'ordered_descriptions'
  OR submission.route IS DISTINCT FROM submission.input_snapshot->>'route'
  OR saved.assets_digest IS DISTINCT FROM configuration#>>'{assignment,asset_manifest_digest}'
  OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=saved.funding_binding_id AND user_id=p_owner
   AND request_id=p_scan AND original_analysis_id=p_scan AND operation='scan_identification' AND attempt_count=1) THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 RETURN internal.initial_admission_response(saved,submission.route,'replay');
END;
$$;
REVOKE ALL ON FUNCTION internal.recover_initial_preparation_admission(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.create_initial_preparation_intent(p_owner UUID,p_scan UUID,p_candidate TEXT) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE candidate JSONB; saved internal.initial_analysis_preparation_intents; recovered JSONB;
 projected RECORD; assignment TEXT; origin TIMESTAMPTZ; fallback BOOLEAN; existing_input JSONB;
BEGIN
 PERFORM internal.require_service_role();
 candidate:=internal.parse_initial_preparation_candidate(p_candidate);
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);
 IF recovered IS NOT NULL THEN
  SELECT input_snapshot INTO existing_input FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
  IF candidate->'input' IS DISTINCT FROM existing_input THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  RETURN recovered;
 END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
  IF saved.canonical_candidate IS DISTINCT FROM p_candidate THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  IF clock_timestamp()>=saved.expires_at THEN
   PERFORM internal.cancel_initial_analysis(p_owner,p_scan);
   RETURN jsonb_build_object('version',2,'outcome','expired');
  END IF;
  RETURN jsonb_build_object('version',2,'outcome','prepared','candidate_digest',saved.candidate_digest,
   'assignment_digest',saved.assignment_digest,'expires_at',saved.expires_at);
 END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR p_scan::TEXT ~ '^ac0[ab]0001-[0-9a-f]{4}-8' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 origin:=clock_timestamp();
 fallback:=jsonb_array_length(candidate#>'{input,ordered_descriptions}')=1;
 SELECT * INTO projected FROM internal.resolve_fresh_quota_entitlement(p_owner,'scan_identification',p_scan,fallback,origin);
 assignment:=internal.resolve_initial_preparation_assignment(p_owner,p_scan,p_candidate,projected.effective_plan,projected.flash_fallback_used);
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);
 INSERT INTO internal.initial_analysis_preparation_intents(scan_id,owner_id,canonical_candidate,candidate_digest,canonical_assignment,
  assignment_digest,created_at,expires_at) VALUES(p_scan,p_owner,p_candidate,internal.initial_preparation_digest('preparation-candidate',p_candidate),
  assignment,internal.initial_preparation_digest('assignment',assignment),origin,origin+INTERVAL '300 seconds') RETURNING * INTO saved;
 RETURN jsonb_build_object('version',2,'outcome','prepared','candidate_digest',saved.candidate_digest,
  'assignment_digest',saved.assignment_digest,'expires_at',saved.expires_at);
END;
$$;

CREATE FUNCTION public.get_initial_preparation_status(p_owner UUID,p_scan UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; recovered JSONB;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);
 IF recovered IS NOT NULL THEN RETURN recovered; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF clock_timestamp()>=saved.expires_at THEN
  PERFORM internal.cancel_initial_analysis(p_owner,p_scan);
  RETURN jsonb_build_object('version',2,'outcome','expired');
 END IF;
 RETURN jsonb_build_object('version',2,'outcome','prepared','candidate_digest',saved.candidate_digest,
  'assignment_digest',saved.assignment_digest,'expires_at',saved.expires_at);
END;
$$;

CREATE FUNCTION public.finalize_initial_preparation(p_owner UUID,p_scan UUID,p_ip_hash TEXT) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; recovered JSONB; input JSONB; assignment JSONB;
 quota RECORD; funding JSONB; configuration JSONB; admitted internal.initial_analysis_admissions;
 old_admission TEXT; old_funding TEXT; old_compared TEXT; encoded TEXT;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);
 IF recovered IS NOT NULL THEN RETURN recovered; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 IF clock_timestamp()>=saved.expires_at THEN
  PERFORM internal.cancel_initial_analysis(p_owner,p_scan);
  RETURN jsonb_build_object('version',2,'outcome','expired');
 END IF;
 input:=internal.parse_initial_preparation_candidate(saved.canonical_candidate)->'input';
 assignment:=saved.canonical_assignment::JSONB;
 -- First acquisition precedes the original core8's blocking reentrant lookup.
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 old_admission:=current_setting('merian.initial_analysis_admission',TRUE);
 old_funding:=current_setting('merian.initial_preparation_funding',TRUE);
 old_compared:=current_setting('merian.initial_preparation_compared',TRUE);
 PERFORM set_config('merian.initial_analysis_admission',p_owner::TEXT||':'||p_scan::TEXT,TRUE);
 PERFORM set_config('merian.initial_preparation_funding',p_owner::TEXT||':'||p_scan::TEXT,TRUE);
 -- The assertion inside core8 uses its actual fresh entitlement result. It runs
 -- before the first hold/epoch mutation; core4 checks again before mutation/replay.
 SELECT * INTO STRICT quota FROM public.reserve_identification_quota(p_owner,'scan_identification',p_scan,p_ip_hash,p_scan,
  jsonb_array_length(input->'ordered_descriptions')=1,(input#>>'{admission,client_protocol}')::INTEGER,FALSE,
  internal.initial_input_semantics(input),input#>>'{admission,expected_processor_permission}',(input#>>'{admission,identification_protocol}')::INTEGER);
 PERFORM set_config('merian.initial_analysis_admission',COALESCE(old_admission,''),TRUE);
 PERFORM set_config('merian.initial_preparation_funding',COALESCE(old_funding,''),TRUE);
 PERFORM set_config('merian.initial_preparation_compared',COALESCE(old_compared,''),TRUE);
 IF quota.request_id IS DISTINCT FROM p_scan OR quota.original_analysis_id IS DISTINCT FROM p_scan OR quota.is_replay
  OR quota.attempt_count<>1 OR quota.reservation_state<>'reserved' OR quota.model IS DISTINCT FROM assignment->>'effective_model'
  OR quota.effective_plan IS DISTINCT FROM assignment->>'effective_plan' OR quota.policy_version IS DISTINCT FROM (assignment->>'policy_version')::BIGINT
  OR quota.provider IS DISTINCT FROM assignment->>'provider' OR quota.binding IS DISTINCT FROM assignment->>'binding'
  OR quota.input_profile IS DISTINCT FROM assignment->>'input_profile' OR quota.flash_fallback_used IS DISTINCT FROM (assignment->>'flash_fallback_used')::BOOLEAN THEN
  RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE='55000'; END IF;
 funding:=jsonb_build_object('version',1,'original',jsonb_build_object('reservation_id',quota.reservation_id,'request_id',quota.request_id,
  'original_analysis_id',quota.original_analysis_id,'operation','scan_identification','attempt_count',quota.attempt_count,
  'effective_plan',quota.effective_plan,'effective_tier',quota.effective_tier,'entitlement_version',quota.entitlement_version,
  'policy_version',quota.policy_version,'model',quota.model,'complimentary_client_scan_id',quota.complimentary_client_scan_id,'flash_fallback_used',quota.flash_fallback_used));
 configuration:=jsonb_build_object('version',2,'assignment',assignment);
 encoded:=internal.initial_canonical(input);
 INSERT INTO internal.initial_analysis_submissions(scan_id,owner_id,route,input_schema_version,input_snapshot,ordered_descriptions,configuration_snapshot,funding_snapshot)
 VALUES(p_scan,p_owner,input->>'route',1,input,input->'ordered_descriptions',configuration,funding);
 INSERT INTO internal.initial_analysis_admissions(scan_id,owner_id,canonical_input,submission_digest,configuration_digest,funding_digest,
  descriptions_digest,funding_binding_id,assets_digest,binding_version,preparation_candidate_digest,preparation_assignment_digest)
 VALUES(p_scan,p_owner,encoded,internal.initial_digest('input',encoded),internal.initial_digest('configuration',internal.initial_canonical(configuration)),
  internal.initial_digest('funding',internal.initial_canonical(funding)),internal.initial_digest('descriptions',internal.initial_canonical(input->'ordered_descriptions')),
  quota.reservation_id,assignment->>'asset_manifest_digest',2,saved.candidate_digest,saved.assignment_digest) RETURNING * INTO admitted;
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 RETURN internal.initial_admission_response(admitted,input->>'route','admitted');
END;
$$;
REVOKE ALL ON FUNCTION public.create_initial_preparation_intent(UUID,UUID,TEXT),public.get_initial_preparation_status(UUID,UUID),
 public.finalize_initial_preparation(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_initial_preparation_intent(UUID,UUID,TEXT),public.get_initial_preparation_status(UUID,UUID),
 public.finalize_initial_preparation(UUID,UUID,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.create_initial_preparation_intent(uuid,uuid,text)','Inactive no-media v2 server-resolved preparation identity; no funding or execution grant'),
 ('service_role','public.get_initial_preparation_status(uuid,uuid)','Inactive exact no-media preparation/admission recovery; no grant'),
 ('service_role','public.finalize_initial_preparation(uuid,uuid,text)','Inactive no-media v2 saved-assignment comparison and original funding; no provider grant');
CREATE FUNCTION internal.guard_initial_preparation_storage() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE recovered JSONB;
BEGIN
 IF TG_OP='INSERT' THEN
  PERFORM internal.lock_initial_preparation_scope(NEW.owner_id,NEW.scan_id);
  PERFORM internal.assert_initial_preparation_unfunded(NEW.owner_id,NEW.scan_id);
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 ELSIF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
   OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL) THEN
   RETURN OLD;
  END IF;
  recovered:=internal.recover_initial_preparation_admission(OLD.owner_id,OLD.scan_id);
  IF recovered IS NOT NULL AND recovered#>>'{binding,candidate_digest}'=OLD.candidate_digest
   AND recovered#>>'{binding,assignment_digest}'=OLD.assignment_digest
   AND EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.scan_id AND owner_id=OLD.owner_id
    AND internal.initial_canonical(configuration_snapshot->'assignment')=OLD.canonical_assignment
    AND internal.initial_canonical(jsonb_build_object('version',2,'variant','no_media','input',input_snapshot))=OLD.canonical_candidate) THEN RETURN OLD; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_preparation_storage() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_preparation_storage BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_preparation_intents
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_storage();

-- Every replacement is exact-once against the already reviewed effective body.
DO $quota$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    quota_now := pg_catalog.CLOCK_TIMESTAMP();';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation core8 clock drift'; END IF;
 definition:=replace(definition,anchor,anchor||$body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id IN (p_request_id,p_original_analysis_id)) THEN
        IF p_request_id IS DISTINCT FROM p_original_analysis_id OR p_operation IS DISTINCT FROM 'scan_identification'
            OR p_internal_replay IS DISTINCT FROM FALSE OR current_setting('merian.initial_preparation_funding',TRUE)
            IS DISTINCT FROM p_user_id::TEXT||':'||p_request_id::TEXT THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_preparation_unfunded(p_user_id,p_request_id);
    END IF;
$body$);
 anchor:='        IF usage_changed THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation core8 mutation drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
        IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id) THEN
            PERFORM internal.assert_initial_preparation_assignment(p_user_id,p_request_id,resolved_plan,resolved_flash_fallback,FALSE);
        END IF;
$body$||anchor);
 SELECT pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    quota_now := pg_catalog.CLOCK_TIMESTAMP();';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation core4 clock drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id) THEN
        IF p_operation IS DISTINCT FROM 'scan_identification' THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_preparation_assignment(p_user_id,p_request_id,resolved_plan,
            (SELECT (canonical_assignment::JSONB->>'flash_fallback_used')::BOOLEAN FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id),TRUE);
    END IF;
$body$);
 SELECT pg_get_functiondef('public.admit_initial_analysis(uuid,uuid,text,text,text,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='  SELECT * INTO saved FROM internal.initial_analysis_admissions WHERE scan_id=p_scan;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation v1 replay drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
  IF saved.binding_version<>1 THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
$body$);
 SELECT pg_get_functiondef('internal.lock_initial_media_scope(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation M1 binding drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
 IF admission.binding_version<>1 THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
$body$);
END;
$quota$;

DO $privacy$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 -- No pending dispatch state is fabricated for preparation. C1 can prove the
 -- terminal no-funding variant only while the exact locked owner still exists.
 SELECT pg_get_functiondef('internal.guard_initial_lifecycle_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' IF TG_OP=''INSERT'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation lifecycle drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=NEW.scan_id OR request_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=NEW.scan_id) THEN RETURN NEW; END IF;
$body$);
 SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation C1 scope drift'; END IF;
 definition:=replace(definition,anchor,$body$
 PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id<>p_owner) THEN
  RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
$body$||anchor);
 anchor:='  IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation C1 fence drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n    AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner)');
 anchor:='  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation C1 gate drift'; END IF;
 definition:=replace(definition,anchor,$body$
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner) THEN
   PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
   terminal:='cancelled_pre_dispatch';
  ELSIF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled)
$body$);
 anchor:=' DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation C1 deletion drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;');

 SELECT pg_get_functiondef('internal.fence_initial_analysis_erasure(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation erasure fence drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n  OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan)');
 SELECT pg_get_functiondef('internal.erase_initial_analysis_for_scan_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation tombstone erasure drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;');
 SELECT pg_get_functiondef('internal.guard_initial_analysis_tombstone_scope()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='       AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation tombstone fast path drift'; END IF;
 definition:=replace(definition,anchor,'       AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id)'||E'\n       AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id) THEN');
 anchor:='    SELECT owner_id INTO owned_by FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation tombstone owner drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n    IF owned_by IS NULL THEN SELECT owner_id INTO owned_by FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id; END IF;');

 SELECT pg_get_functiondef('internal.guard_initial_analysis_scan_erasure_scope()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.id) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation scan guard drift'; END IF;
 EXECUTE replace(definition,anchor,'    IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.id)'||E'\n      OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.id) THEN');
 SELECT pg_get_functiondef('internal.fence_initial_analysis_on_scan_change()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation scan fence drift'; END IF;
 definition:=replace(definition,anchor,'    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity)'||E'\n      AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity) THEN');
 anchor:='    DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation scan erase drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n    DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;');

 SELECT pg_get_functiondef('internal.fence_initial_analysis_before_owner_delete()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions AS submission';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation raw delete guard drift'; END IF;
 definition:=replace(definition,anchor,'    IF EXISTS(SELECT 1 FROM (SELECT scan_id,owner_id FROM internal.initial_analysis_submissions UNION SELECT scan_id,owner_id FROM internal.initial_analysis_preparation_intents) AS submission');
 anchor:='    FOR identity IN SELECT scan_id FROM internal.initial_analysis_submissions WHERE owner_id=OLD.id ORDER BY scan_id LOOP';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation raw delete loop drift'; END IF;
 definition:=replace(definition,anchor,'    FOR identity IN SELECT scan_id FROM internal.initial_analysis_submissions WHERE owner_id=OLD.id UNION SELECT scan_id FROM internal.initial_analysis_preparation_intents WHERE owner_id=OLD.id ORDER BY scan_id LOOP');
 anchor:='        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation raw delete erase drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n        DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;');
 SELECT pg_get_functiondef('public.apply_user_tombstone(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    FOR observation IN SELECT s.scan_id FROM internal.initial_analysis_submissions s';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation supported detachment drift'; END IF;
 EXECUTE replace(definition,anchor,'    FOR observation IN SELECT s.scan_id FROM (SELECT scan_id,owner_id FROM internal.initial_analysis_submissions UNION SELECT scan_id,owner_id FROM internal.initial_analysis_preparation_intents) s');
END;
$privacy$;

COMMENT ON TABLE internal.initial_analysis_preparation_intents IS 'Inactive immutable no-media v2 candidate and server assignment; original 300-second lifetime. No funding/provider/preparation grant. Atomically promotes to v2 admission or erases through C1/strong deletion; global content-free fence remains.';
RESET statement_timeout;
RESET lock_timeout;
