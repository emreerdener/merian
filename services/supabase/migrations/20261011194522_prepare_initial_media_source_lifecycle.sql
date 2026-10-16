SET lock_timeout='5s';
SET statement_timeout='2min';

-- Dormant metadata only. No profile, backend, selection, upload or grant is installed.
CREATE FUNCTION internal.initial_media_profile_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$ SELECT $json${"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"spec":{"type":"object","properties":{"profile_id":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"profile_version":{"type":"integer","minimum":1,"maximum":2147483647},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"focus_policy":{"type":"string","max_bytes":128,"enum":["input_v1_bounds"]},"runtime":{"type":"object","properties":{"engine":{"type":"string","max_bytes":128,"enum":["deno"]},"version":{"type":"string","max_bytes":64,"pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"},"platform":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"abi":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"protocol":{"type":"integer","minimum":1,"maximum":2147483647}}},"artifact":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":67108864}}},"identities":{"type":"object","properties":{"source":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"validator":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"transform":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"configuration":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"rules":{"type":"array","items":{"type":"object","properties":{"role":{"type":"string","max_bytes":128,"enum":["photo","recording","video_frame","video_audio","raw_video"]},"source_types":{"type":"array","items":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]},"max_items":5},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","video_frame_v1","initial_audio_v1"]},"target_sample_rate":{"type":"integer","minimum":8000,"maximum":192000,"nullable":true},"preserve_short_video_context":{"type":"boolean","nullable":true},"max_count":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"max_items":5},"max_sources":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"qualification":{"type":"object","properties":{"spec_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"evidence_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"harness_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_revision":{"type":"string","max_bytes":40,"pattern":"^[0-9a-f]{40}$"}}}}}$json$::JSONB; $schema$;
REVOKE ALL ON FUNCTION internal.initial_media_profile_schema() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.initial_media_assignment_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$ SELECT $json${"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"candidate_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"effective_tier":{"type":"string","max_bytes":128,"enum":["free","pro"]},"flash_fallback_used":{"type":"boolean"},"quota_model":{"type":"string","max_bytes":128},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"provider":{"type":"string","max_bytes":128,"enum":["gemini","openai"]},"binding":{"type":"string","max_bytes":128},"processor_permission":{"type":"string","max_bytes":128,"enum":["google_gemini","openai"]},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"provider_model":{"type":"string","max_bytes":128,"nullable":true},"effective_model":{"type":"string","max_bytes":128},"minimum_client_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_client_protocol":{"type":"integer","minimum":3,"maximum":3},"minimum_identification_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6},"asset_manifest_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"retention_owner":{"type":"string","max_bytes":128,"enum":["initial_engine_release_archive"]},"resolver_id":{"type":"string","max_bytes":128,"enum":["git_blob_sha256_v1"]},"preparation":{"type":"object","properties":{"kind":{"type":"string","max_bytes":128,"enum":["media_sources"]},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"selector_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_mapping":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"source":{"type":"object","properties":{"kind":{"type":"string","enum":["image","audio","video"],"max_bytes":128},"source_byte_count":{"type":"integer","minimum":1,"maximum":12582912},"source_sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"input_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"source_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"clip_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"frame_index":{"type":"integer","minimum":0,"maximum":149,"nullable":true},"focus_region":{"type":"object","properties":{"x":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"y":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"width":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"height":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"source":{"type":"string","enum":["vision_objectness"],"max_bytes":128}},"nullable":true},"transform":{"type":"string","enum":["identity_v1","initial_audio_v1","video_frame_v1"],"max_bytes":128},"source_content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"transform_parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"prepared_output":{"type":"object","properties":{"state":{"type":"string","enum":["unresolved"],"max_bytes":128}}}}},"role":{"type":"string","max_bytes":128,"enum":["photo","recording","video_frame","video_audio","raw_video"]},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"prepared_destination":{"type":"string","max_bytes":0,"enum":[],"nullable":true}}},"max_items":8},"backend_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"experiment":{"type":"string","max_bytes":0,"enum":[],"nullable":true},"variant":{"type":"string","max_bytes":128,"enum":["media_sources"]},"source_plan_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}}$json$::JSONB; $schema$;
REVOKE ALL ON FUNCTION internal.initial_media_assignment_schema() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.initial_media_contract_digest(p_domain TEXT,p_text TEXT) RETURNS TEXT
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
BEGIN
 IF p_domain NOT IN ('profile_spec','profile','installation','source_plan','backend') OR p_domain IS NULL OR p_text IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.media.'||p_domain||E'.v1\n'||p_text,'UTF8'),'sha256'),'hex');
END; $$;
CREATE FUNCTION internal.initial_source_role(p_source JSONB) RETURNS TEXT LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_source->>'kind'='video' THEN 'raw_video'
 WHEN p_source->>'kind'='audio' THEN CASE WHEN p_source->'clip_index'='null'::JSONB THEN 'recording' ELSE 'video_audio' END
 ELSE CASE WHEN p_source->'clip_index'='null'::JSONB THEN 'photo' ELSE 'video_frame' END END;
$$;
CREATE FUNCTION internal.initial_source_input_profile(p_plan JSONB) RETURNS TEXT LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_plan->>'route'='identify' THEN 'vision_compat_v1'
 WHEN (p_plan#>>'{capture,has_video}')::BOOLEAN THEN CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'sources') s WHERE s->>'kind'='audio') THEN 'multimodal_video_audio_v1' ELSE 'multimodal_video_frames_v1' END
 WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'sources') s WHERE s->>'kind'='image') THEN CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'sources') s WHERE s->>'kind'='audio') THEN 'multimodal_photo_audio_v1' ELSE 'multimodal_photo_v1' END ELSE 'multimodal_audio_v1' END;
$$;
CREATE FUNCTION internal.parse_initial_media_profile(p_text TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB; spec JSONB; rule JSONB; roles TEXT[]; expected TEXT[]; is_audio BOOLEAN; raw_video BOOLEAN; allowed TEXT[];
BEGIN
 IF p_text IS NULL OR octet_length(p_text)>65536 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text OR NOT internal.initial_schema_matches(value,internal.initial_media_profile_schema()) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 spec:=value->'spec';
 expected:=CASE spec->>'input_profile' WHEN 'vision_compat_v1' THEN ARRAY['photo'] WHEN 'multimodal_photo_v1' THEN ARRAY['photo'] WHEN 'multimodal_audio_v1' THEN ARRAY['recording'] WHEN 'multimodal_photo_audio_v1' THEN ARRAY['photo','recording'] WHEN 'multimodal_video_frames_v1' THEN ARRAY['raw_video','video_frame'] ELSE ARRAY['raw_video','video_audio','video_frame'] END;
 SELECT array_agg(r->>'role' ORDER BY r->>'role') INTO roles FROM jsonb_array_elements(spec->'rules') r;
 IF roles IS DISTINCT FROM expected OR ((spec->>'route'='identify') IS DISTINCT FROM (spec->>'input_profile'='vision_compat_v1'))
 OR value#>>'{qualification,spec_digest}' IS DISTINCT FROM internal.initial_media_contract_digest('profile_spec',internal.initial_canonical(spec)) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR rule IN SELECT r FROM jsonb_array_elements(spec->'rules') r LOOP
  is_audio:=rule->>'role' IN ('recording','video_audio'); raw_video:=rule->>'role'='raw_video';
  allowed:=CASE WHEN is_audio THEN ARRAY['audio/wav'] WHEN raw_video THEN ARRAY['video/mp4'] ELSE ARRAY['image/jpeg','image/png','image/webp','image/heic','image/heif'] END;
  IF jsonb_array_length(rule->'source_types')=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(rule->'source_types') t WHERE NOT(t=ANY(allowed)))
   OR (SELECT count(DISTINCT t) FROM jsonb_array_elements_text(rule->'source_types') t)<>jsonb_array_length(rule->'source_types')
   OR rule->>'transform' IS DISTINCT FROM (CASE WHEN is_audio THEN 'initial_audio_v1' WHEN rule->>'role'='video_frame' THEN 'video_frame_v1' ELSE 'identity_v1' END)
   OR (is_audio AND (rule->'target_sample_rate'='null'::JSONB OR rule->'preserve_short_video_context' IS DISTINCT FROM to_jsonb(rule->>'role'='video_audio')))
   OR (NOT is_audio AND (rule->'target_sample_rate'<>'null'::JSONB OR rule->'preserve_short_video_context'<>'null'::JSONB))
   OR (raw_video AND ((rule#>>'{limits,output_bytes}')::BIGINT<>0 OR (rule->>'max_count')::INTEGER<>1))
   OR (NOT raw_video AND (rule#>>'{limits,output_bytes}')::BIGINT=0) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 RETURN value;
END; $$;
CREATE FUNCTION internal.assert_initial_media_profile_matches(p_candidate TEXT,p_profile TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE plan JSONB; spec JSONB; source JSONB; rule JSONB; role TEXT; counts JSONB:='{}'::JSONB; n INTEGER; source_total BIGINT:=0; output_total BIGINT:=0; cpu_total BIGINT:=0; heap_total BIGINT:=0; wall_total BIGINT:=0;
BEGIN
 plan:=internal.parse_initial_media_source_candidate(p_candidate)->'source_plan'; spec:=internal.parse_initial_media_profile(p_profile)->'spec';
 IF plan->>'route' IS DISTINCT FROM spec->>'route' OR internal.initial_source_input_profile(plan) IS DISTINCT FROM spec->>'input_profile' OR jsonb_array_length(plan->'sources')>(spec->>'max_sources')::INTEGER THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 FOR source IN SELECT s FROM jsonb_array_elements(plan->'sources') s LOOP
  role:=internal.initial_source_role(source);
  SELECT r INTO rule FROM jsonb_array_elements(spec->'rules') r WHERE r->>'role'=role;
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  n:=COALESCE((counts->>role)::INTEGER,0)+1; counts:=jsonb_set(counts,ARRAY[role],to_jsonb(n));
  IF n>(rule->>'max_count')::INTEGER OR NOT (rule->'source_types' ? (source->>'source_content_type')) OR source->>'transform' IS DISTINCT FROM rule->>'transform'
   OR COALESCE(source#>'{transform_parameters,target_sample_rate}','null'::JSONB) IS DISTINCT FROM rule->'target_sample_rate'
   OR COALESCE(source#>'{transform_parameters,preserve_short_video_context}','null'::JSONB) IS DISTINCT FROM rule->'preserve_short_video_context'
   OR (source->>'source_byte_count')::BIGINT>(rule#>>'{limits,source_bytes}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  source_total:=source_total+(source->>'source_byte_count')::BIGINT; output_total:=output_total+(rule#>>'{limits,output_bytes}')::BIGINT;
  cpu_total:=cpu_total+(rule#>>'{limits,cpu_ms}')::BIGINT; heap_total:=heap_total+(rule#>>'{limits,heap_bytes}')::BIGINT; wall_total:=wall_total+(rule#>>'{limits,wall_ms}')::BIGINT;
 END LOOP;
 IF source_total>(spec#>>'{limits,source_bytes}')::BIGINT OR output_total>(spec#>>'{limits,output_bytes}')::BIGINT OR cpu_total>(spec#>>'{limits,cpu_ms}')::BIGINT OR heap_total>(spec#>>'{limits,heap_bytes}')::BIGINT OR wall_total>(spec#>>'{limits,wall_ms}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
END; $$;
CREATE FUNCTION internal.valid_initial_media_assignment_pair(p_candidate TEXT,p_assignment TEXT) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE c JSONB; a JSONB; mapping JSONB; ordinal INTEGER:=0;
BEGIN
 c:=internal.parse_initial_media_source_candidate(p_candidate);
 IF p_assignment IS NULL OR octet_length(p_assignment)>65536 THEN RETURN FALSE; END IF;
 BEGIN a:=p_assignment::JSONB; EXCEPTION WHEN OTHERS THEN RETURN FALSE; END;
 IF internal.initial_canonical(a) IS DISTINCT FROM p_assignment OR NOT internal.initial_schema_matches(a,internal.initial_media_assignment_schema()) THEN RETURN FALSE; END IF;
 IF a->>'candidate_digest' IS DISTINCT FROM internal.initial_preparation_digest('preparation-candidate',p_candidate)
 OR a->>'source_plan_digest' IS DISTINCT FROM internal.initial_media_contract_digest('source_plan',internal.initial_canonical(c->'source_plan'))
 OR a->>'route' IS DISTINCT FROM c#>>'{source_plan,route}' OR a->>'input_profile' IS DISTINCT FROM internal.initial_source_input_profile(c->'source_plan')
 OR jsonb_array_length(a#>'{preparation,source_mapping}')<>jsonb_array_length(c#>'{source_plan,sources}')
 OR (SELECT count(DISTINCT m->>'object_id') FROM jsonb_array_elements(a#>'{preparation,source_mapping}') m)<>jsonb_array_length(c#>'{source_plan,sources}') THEN RETURN FALSE; END IF;
 FOR mapping IN SELECT m FROM jsonb_array_elements(a#>'{preparation,source_mapping}') m LOOP
  IF (mapping->>'ordinal')::INTEGER<>ordinal OR mapping->'source' IS DISTINCT FROM c#>ARRAY['source_plan','sources',ordinal::TEXT]
   OR mapping->>'role' IS DISTINCT FROM internal.initial_source_role(c#>ARRAY['source_plan','sources',ordinal::TEXT]) THEN RETURN FALSE; END IF;
  ordinal:=ordinal+1;
 END LOOP;
 RETURN TRUE;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_media_contract_digest(TEXT,TEXT),internal.initial_source_role(JSONB),internal.initial_source_input_profile(JSONB),internal.parse_initial_media_profile(TEXT),internal.assert_initial_media_profile_matches(TEXT,TEXT),internal.valid_initial_media_assignment_pair(TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.initial_preparation_profiles(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 canonical_profile TEXT NOT NULL CHECK(internal.parse_initial_media_profile(canonical_profile) IS NOT NULL),
 CHECK(digest=internal.initial_media_contract_digest('profile',canonical_profile))
);
CREATE TABLE internal.initial_preparation_installations(
 digest TEXT PRIMARY KEY,
 target_kind TEXT NOT NULL CHECK(target_kind IN ('profile','backend')),
 target_digest TEXT NOT NULL CHECK(target_digest ~ '^[0-9a-f]{64}$'),
 evidence_digest TEXT NOT NULL CHECK(evidence_digest ~ '^[0-9a-f]{64}$'),
 reviewed_revision TEXT NOT NULL CHECK(reviewed_revision ~ '^[0-9a-f]{40}$'),
 installer_protocol TEXT NOT NULL CHECK(installer_protocol='reviewed_database_owner_install_v1'),
 UNIQUE(target_kind,target_digest,digest),
 CHECK(digest=internal.initial_media_contract_digest('installation',internal.initial_canonical(jsonb_build_object('target_kind',target_kind,'target_digest',target_digest,'evidence_digest',evidence_digest,'reviewed_revision',reviewed_revision,'installer_protocol',installer_protocol))))
);
CREATE TABLE internal.initial_preparation_profile_eligibility(
 profile_digest TEXT PRIMARY KEY REFERENCES internal.initial_preparation_profiles(digest),
 target_kind TEXT NOT NULL DEFAULT 'profile' CHECK(target_kind='profile'),
 installation_digest TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('eligible','revoked')),
 FOREIGN KEY(target_kind,profile_digest,installation_digest) REFERENCES internal.initial_preparation_installations(target_kind,target_digest,digest)
);
CREATE INDEX initial_preparation_profile_installation ON internal.initial_preparation_profile_eligibility(target_kind,profile_digest,installation_digest);
CREATE TABLE internal.initial_preparation_source_backends(
 generation UUID PRIMARY KEY,
 configuration_digest TEXT NOT NULL UNIQUE,
 provider TEXT NOT NULL CHECK(provider='r2'),
 direct_endpoint TEXT NOT NULL CHECK(direct_endpoint ~ '^https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com$'),
 private_bucket TEXT NOT NULL CHECK(private_bucket ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'),
 namespace TEXT NOT NULL CHECK(namespace='initial-preparation/v2'),
 credential_profile TEXT NOT NULL CHECK(credential_profile ~ '^[a-z][a-z0-9_]{0,63}$'),
 storage_protocol TEXT NOT NULL CHECK(storage_protocol='conditional_create_permanent_same_key_marker_v1'),
 UNIQUE(generation,configuration_digest),
 CHECK(configuration_digest=internal.initial_media_contract_digest('backend',internal.initial_canonical(jsonb_build_object('generation',generation,'provider',provider,'direct_endpoint',direct_endpoint,'private_bucket',private_bucket,'namespace',namespace,'credential_profile',credential_profile,'storage_protocol',storage_protocol))))
);
CREATE TABLE internal.initial_preparation_backend_eligibility(
 generation UUID PRIMARY KEY,
 configuration_digest TEXT NOT NULL,
 target_kind TEXT NOT NULL DEFAULT 'backend' CHECK(target_kind='backend'),
 installation_digest TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('eligible','revoked')),
 FOREIGN KEY(generation,configuration_digest) REFERENCES internal.initial_preparation_source_backends(generation,configuration_digest),
 FOREIGN KEY(target_kind,configuration_digest,installation_digest) REFERENCES internal.initial_preparation_installations(target_kind,target_digest,digest)
);
CREATE INDEX initial_preparation_backend_installation ON internal.initial_preparation_backend_eligibility(target_kind,configuration_digest,installation_digest);
CREATE TABLE internal.initial_preparation_selections(
 generation UUID PRIMARY KEY,
 profile_digest TEXT NOT NULL REFERENCES internal.initial_preparation_profiles(digest),
 backend_generation UUID NOT NULL REFERENCES internal.initial_preparation_source_backends(generation)
);
CREATE INDEX initial_preparation_selection_profile ON internal.initial_preparation_selections(profile_digest);
CREATE INDEX initial_preparation_selection_backend ON internal.initial_preparation_selections(backend_generation);
CREATE TABLE internal.initial_preparation_current_selection(
 input_profile TEXT PRIMARY KEY CHECK(input_profile IN ('vision_compat_v1','multimodal_photo_v1','multimodal_audio_v1','multimodal_photo_audio_v1','multimodal_video_frames_v1','multimodal_video_audio_v1')),
 generation UUID NOT NULL REFERENCES internal.initial_preparation_selections(generation)
);
CREATE INDEX initial_preparation_current_generation ON internal.initial_preparation_current_selection(generation);
CREATE FUNCTION internal.guard_initial_preparation_eligibility() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND OLD.state='eligible' AND NEW.state='revoked' AND to_jsonb(NEW)-'state'=to_jsonb(OLD)-'state' THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;
DO $catalogs$
DECLARE name TEXT;
BEGIN
 FOREACH name IN ARRAY ARRAY['initial_preparation_profiles','initial_preparation_installations','initial_preparation_source_backends','initial_preparation_selections'] LOOP
  EXECUTE format('CREATE TRIGGER guard_%I BEFORE UPDATE OR DELETE ON internal.%I FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation()',name,name);
 END LOOP;
 FOREACH name IN ARRAY ARRAY['initial_preparation_profile_eligibility','initial_preparation_backend_eligibility'] LOOP
  EXECUTE format('CREATE TRIGGER guard_%I BEFORE UPDATE OR DELETE ON internal.%I FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_eligibility()',name,name);
 END LOOP;
 FOREACH name IN ARRAY ARRAY['initial_preparation_profiles','initial_preparation_installations','initial_preparation_profile_eligibility','initial_preparation_source_backends','initial_preparation_backend_eligibility','initial_preparation_selections','initial_preparation_current_selection'] LOOP
  EXECUTE format('ALTER TABLE internal.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON internal.%I FROM PUBLIC,anon,authenticated,service_role',name);
 END LOOP;
END; $catalogs$;
REVOKE ALL ON FUNCTION internal.guard_initial_preparation_eligibility() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.valid_initial_preparation_pair(p_candidate TEXT,p_assignment TEXT) RETURNS BOOLEAN
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE c JSONB; a JSONB;
BEGIN
 IF p_candidate IS NULL OR octet_length(p_candidate)>1048576 OR p_assignment IS NULL OR octet_length(p_assignment)>65536 THEN RETURN FALSE; END IF;
 BEGIN c:=p_candidate::JSONB; a:=p_assignment::JSONB; EXCEPTION WHEN OTHERS THEN RETURN FALSE; END;
 IF c->>'variant'='media_sources' THEN RETURN internal.valid_initial_media_assignment_pair(p_candidate,p_assignment); END IF;
 PERFORM internal.parse_initial_preparation_candidate(p_candidate);
 RETURN internal.initial_canonical(a)=p_assignment AND internal.initial_schema_matches(a,internal.initial_assignment_schema_v2()) AND a->>'candidate_digest'=internal.initial_preparation_digest('preparation-candidate',p_candidate);
END; $$;
REVOKE ALL ON FUNCTION internal.valid_initial_preparation_pair(TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;
DO $pair$
DECLARE c RECORD; changed INTEGER:=0;
BEGIN
 FOR c IN SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid='internal.initial_analysis_preparation_intents'::REGCLASS AND contype='c' LOOP
  IF c.definition LIKE '%parse_initial_preparation_candidate(canonical_candidate)%' OR c.definition LIKE '%initial_assignment_schema_v2()%'
  THEN EXECUTE format('ALTER TABLE internal.initial_analysis_preparation_intents DROP CONSTRAINT %I',c.conname); changed:=changed+1; END IF;
 END LOOP;
 IF changed<>2 THEN RAISE EXCEPTION 'initial preparation pair constraint drift'; END IF;
END; $pair$;
ALTER TABLE internal.initial_analysis_preparation_intents ADD CONSTRAINT initial_preparation_closed_pair
 CHECK(internal.valid_initial_preparation_pair(canonical_candidate,canonical_assignment));
CREATE TABLE internal.initial_preparation_source_fences(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_operation_fences(scan_id),
 state TEXT NOT NULL CHECK(state IN ('allocated','retired')),
 execution_state TEXT NOT NULL DEFAULT 'unissued' CHECK(execution_state='unissued')
);
CREATE TABLE internal.initial_preparation_source_registry(
 object_id UUID PRIMARY KEY,
 scan_id UUID NOT NULL REFERENCES internal.initial_preparation_source_fences(scan_id),
 backend_generation UUID NOT NULL REFERENCES internal.initial_preparation_source_backends(generation),
 retired BOOLEAN NOT NULL DEFAULT FALSE,
 marker_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
 claim_token UUID,
 claim_expires_at TIMESTAMPTZ,
 UNIQUE(scan_id,object_id),
 CHECK((claim_token IS NULL)=(claim_expires_at IS NULL)),
 CHECK(retired OR (NOT marker_confirmed AND claim_token IS NULL)),
 CHECK(NOT marker_confirmed OR claim_token IS NULL)
);
CREATE INDEX initial_preparation_source_registry_backend ON internal.initial_preparation_source_registry(backend_generation);
CREATE INDEX initial_preparation_source_registry_cleanup ON internal.initial_preparation_source_registry(claim_expires_at,object_id) WHERE retired AND NOT marker_confirmed;
CREATE TABLE internal.initial_preparation_source_mapping(
 scan_id UUID NOT NULL REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE,
 ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 0 AND 7),
 object_id UUID NOT NULL UNIQUE,
 PRIMARY KEY(scan_id,ordinal),
 FOREIGN KEY(scan_id,object_id) REFERENCES internal.initial_preparation_source_registry(scan_id,object_id)
);
CREATE INDEX initial_preparation_source_mapping_registry ON internal.initial_preparation_source_mapping(scan_id,object_id);
DO $privacy$
DECLARE name TEXT;
BEGIN
 FOREACH name IN ARRAY ARRAY['initial_preparation_source_fences','initial_preparation_source_registry','initial_preparation_source_mapping'] LOOP
  EXECUTE format('ALTER TABLE internal.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON internal.%I FROM PUBLIC,anon,authenticated,service_role',name);
 END LOOP;
END; $privacy$;

CREATE FUNCTION internal.initial_preparation_sources_complete(p_scan UUID) RETURNS BOOLEAN
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; item JSONB; count_sources INTEGER;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'media_sources' THEN RETURN FALSE; END IF;
 IF NOT internal.valid_initial_media_assignment_pair(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
 a:=saved.canonical_assignment::JSONB; count_sources:=jsonb_array_length(a#>'{preparation,source_mapping}');
 IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan AND state='allocated' AND execution_state='unissued')
  OR (SELECT count(*) FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan)<>count_sources
  OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan)<>count_sources THEN RETURN FALSE; END IF;
 FOR item IN SELECT m FROM jsonb_array_elements(a#>'{preparation,source_mapping}') m LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping m JOIN internal.initial_preparation_source_registry r USING(scan_id,object_id)
   WHERE m.scan_id=p_scan AND m.ordinal=(item->>'ordinal')::INTEGER AND m.object_id=(item->>'object_id')::UUID
    AND r.backend_generation=(a#>>'{preparation,backend_generation}')::UUID AND NOT r.retired AND NOT r.marker_confirmed AND r.claim_token IS NULL) THEN RETURN FALSE; END IF;
 END LOOP;
 RETURN TRUE;
END; $$;
CREATE FUNCTION internal.require_initial_source_cohort() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE identity UUID; candidate TEXT;
BEGIN
 identity:=CASE WHEN TG_OP='DELETE' THEN OLD.scan_id ELSE NEW.scan_id END;
 SELECT canonical_candidate INTO candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
 IF candidate IS NULL THEN
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity AND state<>'retired') OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=identity AND NOT retired) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF candidate::JSONB->>'variant'='media_sources' THEN
  IF NOT internal.initial_preparation_sources_complete(identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER initial_source_intent_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_preparation_intents DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_source_cohort();
CREATE CONSTRAINT TRIGGER initial_source_mapping_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.initial_preparation_source_mapping DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_source_cohort();
CREATE CONSTRAINT TRIGGER initial_source_registry_cohort AFTER INSERT OR UPDATE ON internal.initial_preparation_source_registry DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_source_cohort();
CREATE CONSTRAINT TRIGGER initial_source_fence_cohort AFTER INSERT OR UPDATE ON internal.initial_preparation_source_fences DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_source_cohort();
CREATE FUNCTION internal.guard_initial_source_storage() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' THEN
  IF TG_TABLE_NAME='initial_preparation_source_fences' THEN
   IF NEW.scan_id=OLD.scan_id AND OLD.state='allocated' AND NEW.state='retired' AND NEW.execution_state=OLD.execution_state
    AND (EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
      OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL)
      OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents i WHERE i.scan_id=OLD.scan_id AND NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=i.owner_id))) THEN RETURN NEW; END IF;
  ELSIF TG_TABLE_NAME='initial_preparation_source_registry' THEN
   IF NEW.object_id=OLD.object_id AND NEW.scan_id=OLD.scan_id AND NEW.backend_generation=OLD.backend_generation AND NEW.retired THEN
    -- Retirement follows the already-terminal parent fence and never changes a
    -- lease or fabricates marker proof. Reads here acquire no outer row locks.
    IF NOT OLD.retired AND NOT NEW.marker_confirmed AND NEW.claim_token IS NULL
     AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id AND state='retired') THEN RETURN NEW; END IF;
    IF OLD.retired AND NOT OLD.marker_confirmed THEN
     -- An existing live lease cannot be replaced. Fresh claims are bounded.
     IF NOT NEW.marker_confirmed AND NEW.claim_token IS NOT NULL AND NEW.claim_token IS DISTINCT FROM OLD.claim_token
      AND (OLD.claim_expires_at IS NULL OR OLD.claim_expires_at<=clock_timestamp())
      AND NEW.claim_expires_at>clock_timestamp() AND NEW.claim_expires_at<=clock_timestamp()+INTERVAL '1 minute' THEN RETURN NEW; END IF;
     -- Only a live claim can be released or acknowledged; the RPC additionally
     -- compares its exact caller token. Database-owner legal transitions remain
     -- trusted metadata and do not prove a physical storage marker.
     IF OLD.claim_token IS NOT NULL AND OLD.claim_expires_at>clock_timestamp()
      AND NEW.claim_token IS NULL AND NEW.claim_expires_at IS NULL THEN RETURN NEW; END IF;
    END IF;
   END IF;
  END IF;
 ELSIF TG_OP='DELETE' AND TG_TABLE_NAME='initial_preparation_source_mapping' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.scan_id)
   AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id AND state='retired') THEN RETURN OLD; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;
CREATE TRIGGER guard_initial_preparation_source_fence BEFORE UPDATE OR DELETE ON internal.initial_preparation_source_fences FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_source_storage();
CREATE TRIGGER guard_initial_preparation_source_registry BEFORE UPDATE OR DELETE ON internal.initial_preparation_source_registry FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_source_storage();
CREATE TRIGGER guard_initial_preparation_source_mapping BEFORE UPDATE OR DELETE ON internal.initial_preparation_source_mapping FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_source_storage();
CREATE FUNCTION internal.retire_initial_preparation_source_objects(p_scan UUID) RETURNS VOID LANGUAGE PLPGSQL SET search_path='' AS $$
DECLARE object UUID;
BEGIN
 UPDATE internal.initial_preparation_source_fences SET state='retired' WHERE scan_id=p_scan AND state='allocated';
 FOR object IN SELECT object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE LOOP
  UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE object_id=object AND NOT retired;
 END LOOP;
END; $$;
CREATE FUNCTION internal.retire_initial_sources_before_erasure() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN
 IF OLD.canonical_candidate::JSONB->>'variant'='media_sources' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
   AND EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL) THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.retire_initial_preparation_source_objects(OLD.scan_id);
 END IF;
 RETURN OLD;
END; $$;
CREATE TRIGGER retire_initial_sources_before_erasure BEFORE DELETE ON internal.initial_analysis_preparation_intents FOR EACH ROW EXECUTE FUNCTION internal.retire_initial_sources_before_erasure();
REVOKE ALL ON FUNCTION internal.initial_preparation_sources_complete(UUID),internal.require_initial_source_cohort(),internal.guard_initial_source_storage(),internal.retire_initial_preparation_source_objects(UUID),internal.retire_initial_sources_before_erasure() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.resolve_initial_media_preparation_assignment(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_plan TEXT,p_fallback BOOLEAN,p_objects JSONB
) RETURNS TEXT LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE input JSONB; profile TEXT; policy internal.ai_quota_policies;
 binding internal.identification_provider_bindings; rollout internal.initial_analysis_rollout;
 accepted_protocol INTEGER; accepted_capability INTEGER; assignment JSONB; manifest JSONB; selection internal.initial_preparation_selections; profile_row internal.initial_preparation_profiles; profile_eligible internal.initial_preparation_profile_eligibility; backend_eligible internal.initial_preparation_backend_eligibility; installed internal.initial_preparation_installations; selected_generation UUID; mapping JSONB;
BEGIN
 input:=internal.parse_initial_media_source_candidate(p_candidate)->'source_plan';
 profile:=internal.initial_source_input_profile(input);
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
 PERFORM input_profile FROM internal.initial_preparation_current_selection WHERE input_profile=profile FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT generation INTO selected_generation FROM internal.initial_preparation_current_selection WHERE input_profile=profile;
 SELECT * INTO selection FROM internal.initial_preparation_selections WHERE generation=selected_generation;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO profile_eligible FROM internal.initial_preparation_profile_eligibility WHERE profile_digest=selection.profile_digest FOR SHARE NOWAIT;
 IF NOT FOUND OR profile_eligible.state<>'eligible' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO backend_eligible FROM internal.initial_preparation_backend_eligibility WHERE generation=selection.backend_generation FOR SHARE NOWAIT;
 IF NOT FOUND OR backend_eligible.state<>'eligible' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO profile_row FROM internal.initial_preparation_profiles WHERE digest=selection.profile_digest;
 SELECT * INTO installed FROM internal.initial_preparation_installations WHERE digest=profile_eligible.installation_digest;
 IF installed.evidence_digest IS DISTINCT FROM profile_row.canonical_profile::JSONB#>>'{qualification,evidence_digest}'
  OR installed.reviewed_revision IS DISTINCT FROM profile_row.canonical_profile::JSONB#>>'{qualification,source_revision}' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_media_profile_matches(p_candidate,profile_row.canonical_profile);
 IF jsonb_typeof(p_objects) IS DISTINCT FROM 'array' OR jsonb_array_length(p_objects)<>jsonb_array_length(input->'sources') THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_object('ordinal',n-1,'source',source,'role',internal.initial_source_role(source),'object_id',p_objects->(n::INTEGER-1),'prepared_destination',NULL) ORDER BY n) INTO mapping FROM jsonb_array_elements(input->'sources') WITH ORDINALITY s(source,n);
 assignment:=jsonb_build_object('version',2,'candidate_digest',internal.initial_preparation_digest('preparation-candidate',p_candidate),
  'route',input->>'route','operation','scan_identification','effective_plan',p_plan,
  'effective_tier',CASE WHEN p_plan='free' THEN 'free' ELSE 'pro' END,'flash_fallback_used',p_fallback,
  'quota_model',policy.model,'policy_version',policy.policy_version,'provider',binding.provider,'binding',binding.binding,
  'processor_permission',binding.processor_permission,'input_profile',profile,'provider_model',binding.provider_model,
  'effective_model',COALESCE(binding.provider_model,policy.model),'minimum_client_protocol',binding.minimum_client_protocol,
  'accepted_client_protocol',accepted_protocol,'minimum_identification_protocol',binding.minimum_identification_protocol,
  'accepted_identification_protocol',accepted_capability,'asset_manifest_digest',rollout.configuration_assets_digest,
  'retention_owner','initial_engine_release_archive','resolver_id','git_blob_sha256_v1',
  'variant','media_sources','source_plan_digest',internal.initial_media_contract_digest('source_plan',internal.initial_canonical(input)),
  'preparation',jsonb_build_object('kind','media_sources','profile_digest',selection.profile_digest,'installation_digest',profile_eligible.installation_digest,'selector_generation',selection.generation,'backend_generation',selection.backend_generation,'backend_installation_digest',backend_eligible.installation_digest,'source_mapping',mapping),'experiment',NULL);
 IF NOT internal.initial_schema_matches(assignment,internal.initial_media_assignment_schema()) THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT internal.valid_initial_media_assignment_pair(p_candidate,internal.initial_canonical(assignment)) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN internal.initial_canonical(assignment);
END;
$$;
REVOKE ALL ON FUNCTION internal.resolve_initial_media_preparation_assignment(UUID,UUID,TEXT,TEXT,BOOLEAN,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_media_response_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $$ SELECT '{"allocated":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"variant":{"type":"string","max_bytes":13,"enum":["media_sources"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"outcome":{"type":"string","max_bytes":9,"enum":["allocated","blocked"]},"candidate_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"candidate_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"effective_tier":{"type":"string","max_bytes":128,"enum":["free","pro"]},"flash_fallback_used":{"type":"boolean"},"quota_model":{"type":"string","max_bytes":128},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"provider":{"type":"string","max_bytes":128,"enum":["gemini","openai"]},"binding":{"type":"string","max_bytes":128},"processor_permission":{"type":"string","max_bytes":128,"enum":["google_gemini","openai"]},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"provider_model":{"type":"string","max_bytes":128,"nullable":true},"effective_model":{"type":"string","max_bytes":128},"minimum_client_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_client_protocol":{"type":"integer","minimum":3,"maximum":3},"minimum_identification_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6},"asset_manifest_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"retention_owner":{"type":"string","max_bytes":128,"enum":["initial_engine_release_archive"]},"resolver_id":{"type":"string","max_bytes":128,"enum":["git_blob_sha256_v1"]},"preparation":{"type":"object","properties":{"kind":{"type":"string","max_bytes":128,"enum":["media_sources"]},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"selector_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_mapping":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"source":{"type":"object","properties":{"kind":{"type":"string","enum":["image","audio","video"],"max_bytes":128},"source_byte_count":{"type":"integer","minimum":1,"maximum":12582912},"source_sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"input_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"source_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"clip_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"frame_index":{"type":"integer","minimum":0,"maximum":149,"nullable":true},"focus_region":{"type":"object","properties":{"x":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"y":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"width":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"height":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"source":{"type":"string","enum":["vision_objectness"],"max_bytes":128}},"nullable":true},"transform":{"type":"string","enum":["identity_v1","initial_audio_v1","video_frame_v1"],"max_bytes":128},"source_content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"transform_parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"prepared_output":{"type":"object","properties":{"state":{"type":"string","enum":["unresolved"],"max_bytes":128}}}}},"role":{"type":"string","max_bytes":128,"enum":["photo","recording","video_frame","video_audio","raw_video"]},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"prepared_destination":{"type":"string","max_bytes":0,"enum":[],"nullable":true}}},"max_items":8},"backend_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"experiment":{"type":"string","max_bytes":0,"enum":[],"nullable":true},"variant":{"type":"string","max_bytes":128,"enum":["media_sources"]},"source_plan_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"expires_at":{"type":"string","max_bytes":40,"pattern":"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.[0-9]{1,6})?(Z|[+-]\\d{2}:\\d{2})$"}}},"expired":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"variant":{"type":"string","max_bytes":13,"enum":["media_sources"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"outcome":{"type":"string","max_bytes":7,"enum":["expired"]}}}}'::JSONB; $$;
REVOKE ALL ON FUNCTION internal.initial_media_response_schema() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.initial_media_preparation_response(p_scan UUID) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; available BOOLEAN;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR NOT internal.initial_preparation_sources_complete(p_scan) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 a:=saved.canonical_assignment::JSONB;
 available:=EXISTS(SELECT 1 FROM internal.initial_preparation_profile_eligibility WHERE profile_digest=a#>>'{preparation,profile_digest}' AND installation_digest=a#>>'{preparation,installation_digest}' AND state='eligible')
 AND EXISTS(SELECT 1 FROM internal.initial_preparation_backend_eligibility WHERE generation=(a#>>'{preparation,backend_generation}')::UUID AND installation_digest=a#>>'{preparation,backend_installation_digest}' AND state='eligible');
 RETURN jsonb_build_object('version',2,'variant','media_sources','outcome',CASE WHEN available THEN 'allocated' ELSE 'blocked' END,'authority','none','candidate_digest',saved.candidate_digest,'assignment_digest',saved.assignment_digest,'assignment',a,'expires_at',saved.expires_at);
END; $$;
CREATE FUNCTION internal.create_initial_media_preparation(p_owner UUID,p_scan UUID,p_candidate TEXT) RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE candidate JSONB; saved internal.initial_analysis_preparation_intents; origin TIMESTAMPTZ; projected RECORD; objects JSONB; assignment TEXT; item JSONB;
BEGIN
 candidate:=internal.parse_initial_media_source_candidate(p_candidate);
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.owner_id IS DISTINCT FROM p_owner OR saved.canonical_candidate IS DISTINCT FROM p_candidate THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  IF clock_timestamp()>=saved.expires_at THEN PERFORM internal.cancel_initial_analysis(p_owner,p_scan); RETURN jsonb_build_object('version',2,'variant','media_sources','outcome','expired','authority','none'); END IF;
  RETURN internal.initial_media_preparation_response(p_scan);
 END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan) OR p_scan::TEXT ~ '^ac0[ab]0001-[0-9a-f]{4}-8' THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 origin:=clock_timestamp();
 SELECT * INTO projected FROM internal.resolve_fresh_quota_entitlement(p_owner,'scan_identification',p_scan,FALSE,origin);
 SELECT jsonb_agg(gen_random_uuid() ORDER BY n) INTO objects FROM generate_series(1,jsonb_array_length(candidate#>'{source_plan,sources}')) n;
 assignment:=internal.resolve_initial_media_preparation_assignment(p_owner,p_scan,p_candidate,projected.effective_plan,projected.flash_fallback_used,objects);
 IF clock_timestamp()>=origin+INTERVAL '300 seconds' THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);
 INSERT INTO internal.initial_analysis_preparation_intents(scan_id,owner_id,canonical_candidate,candidate_digest,canonical_assignment,assignment_digest,created_at,expires_at)
 VALUES(p_scan,p_owner,p_candidate,internal.initial_preparation_digest('preparation-candidate',p_candidate),assignment,internal.initial_preparation_digest('assignment',assignment),origin,origin+INTERVAL '300 seconds');
 INSERT INTO internal.initial_preparation_source_fences(scan_id,state) VALUES(p_scan,'allocated');
 -- The deterministic object order is shared with all retirement paths.
 FOR item IN SELECT m FROM jsonb_array_elements(assignment::JSONB#>'{preparation,source_mapping}') m ORDER BY (m->>'object_id')::UUID LOOP
  INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation) VALUES((item->>'object_id')::UUID,p_scan,(assignment::JSONB#>>'{preparation,backend_generation}')::UUID);
  INSERT INTO internal.initial_preparation_source_mapping(scan_id,ordinal,object_id) VALUES(p_scan,(item->>'ordinal')::INTEGER,(item->>'object_id')::UUID);
 END LOOP;
 RETURN internal.initial_media_preparation_response(p_scan);
END; $$;
CREATE FUNCTION internal.assert_initial_media_intent_insert(p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE projected RECORD; objects JSONB; expected TEXT;
BEGIN
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 SELECT * INTO projected FROM internal.resolve_fresh_quota_entitlement(p_owner,'scan_identification',p_scan,FALSE,clock_timestamp());
 SELECT jsonb_agg(m->'object_id' ORDER BY n) INTO objects FROM jsonb_array_elements(p_assignment::JSONB#>'{preparation,source_mapping}') WITH ORDINALITY s(m,n);
 expected:=internal.resolve_initial_media_preparation_assignment(p_owner,p_scan,p_candidate,projected.effective_plan,projected.flash_fallback_used,objects);
 IF expected IS DISTINCT FROM p_assignment THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_media_preparation_response(UUID),internal.create_initial_media_preparation(UUID,UUID,TEXT),internal.assert_initial_media_intent_insert(UUID,UUID,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;
DO $integration$
DECLARE definition TEXT; anchor TEXT; signature TEXT;
BEGIN
 SELECT pg_get_functiondef('public.create_initial_preparation_intent(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' candidate:=internal.parse_initial_preparation_candidate(p_candidate);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source create drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
 IF p_candidate IS NOT NULL AND octet_length(p_candidate)<=1048576 THEN
  BEGIN
   IF p_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.create_initial_media_preparation(p_owner,p_scan,p_candidate); END IF;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 END IF;
$body$||anchor);
 SELECT pg_get_functiondef('public.get_initial_preparation_status(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' RETURN jsonb_build_object(''version'',2,''outcome'',''prepared'',''candidate_digest'',saved.candidate_digest,';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source recovery drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
 IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.initial_media_preparation_response(p_scan); END IF;
$body$||anchor);
 SELECT pg_get_functiondef('public.get_initial_preparation_status(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='  RETURN jsonb_build_object(''version'',2,''outcome'',''expired'');';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source expiry response drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
  IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RETURN jsonb_build_object('version',2,'variant','media_sources','outcome','expired','authority','none'); END IF;
$body$||anchor);
 SELECT pg_get_functiondef('public.finalize_initial_preparation(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source finalizer drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
 IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
$body$||anchor);
 SELECT pg_get_functiondef('internal.guard_initial_preparation_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='  RETURN NEW;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source intent guard drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
  IF NEW.canonical_candidate::JSONB->>'variant'='media_sources' THEN
   PERFORM internal.assert_initial_media_intent_insert(NEW.owner_id,NEW.scan_id,NEW.canonical_candidate,NEW.canonical_assignment);
  END IF;
$body$||anchor);
 SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=E'   PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);\n   terminal:=''cancelled_pre_dispatch'';';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source C1 proof drift'; END IF;
 definition:=replace(definition,anchor,$body$
   PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
   IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='media_sources') AND
    (NOT internal.initial_preparation_sources_complete(p_scan) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)) THEN
    terminal:='cancelled_unknown';
   ELSE terminal:='cancelled_pre_dispatch'; END IF;
$body$);
 anchor:=' DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source C1 erasure drift'; END IF;
 EXECUTE replace(definition,anchor,E' PERFORM internal.retire_initial_preparation_source_objects(p_scan);\n'||anchor);
 SELECT pg_get_functiondef('internal.guard_initial_lifecycle_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' IF TG_OP=''INSERT'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source lifecycle guard drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id AND canonical_candidate::JSONB->>'variant'='media_sources')
   AND (NOT internal.initial_preparation_sources_complete(NEW.scan_id) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=NEW.scan_id)) THEN
   RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023'; END IF;
$body$);
 FOREACH signature IN ARRAY ARRAY['internal.erase_initial_analysis_for_scan_fence()','internal.fence_initial_analysis_on_scan_change()','internal.fence_initial_analysis_before_owner_delete()'] LOOP
  SELECT pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
  anchor:=CASE WHEN signature='internal.erase_initial_analysis_for_scan_fence()' THEN 'DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;' ELSE 'DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;' END;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial source strong erasure drift: %',signature; END IF;
  EXECUTE replace(definition,anchor,CASE WHEN signature='internal.erase_initial_analysis_for_scan_fence()' THEN 'PERFORM internal.retire_initial_preparation_source_objects(NEW.scan_id);' ELSE 'PERFORM internal.retire_initial_preparation_source_objects(identity);' END||E'\n '||anchor);
 END LOOP;
END; $integration$;

CREATE FUNCTION public.claim_initial_preparation_source_erasure() RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE object internal.initial_preparation_source_registry;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO object FROM internal.initial_preparation_source_registry WHERE retired AND NOT marker_confirmed AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp()) ORDER BY object_id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('version',1,'outcome','empty'); END IF;
 UPDATE internal.initial_preparation_source_registry SET claim_token=gen_random_uuid(),claim_expires_at=clock_timestamp()+INTERVAL '1 minute' WHERE object_id=object.object_id RETURNING * INTO object;
 RETURN jsonb_build_object('version',1,'outcome','claimed','object',jsonb_build_object('scan_id',object.scan_id,'object_id',object.object_id,'backend_generation',object.backend_generation,'claim_token',object.claim_token,'claim_expires_at',floor(extract(epoch FROM object.claim_expires_at)*1000)::BIGINT));
END; $$;
CREATE FUNCTION public.finish_initial_preparation_source_erasure(p_object UUID,p_claim UUID,p_success BOOLEAN) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 IF p_object IS NULL OR p_claim IS NULL OR p_success IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 UPDATE internal.initial_preparation_source_registry SET marker_confirmed=p_success,claim_token=NULL,claim_expires_at=NULL WHERE object_id=p_object AND retired AND NOT marker_confirmed AND claim_token=p_claim AND claim_expires_at>clock_timestamp();
 RETURN jsonb_build_object('version',1,'outcome',CASE WHEN NOT FOUND THEN 'stale' WHEN p_success THEN 'acknowledged' ELSE 'released' END);
END; $$;
REVOKE ALL ON FUNCTION public.claim_initial_preparation_source_erasure(),public.finish_initial_preparation_source_erasure(UUID,UUID,BOOLEAN) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_initial_preparation_source_erasure(),public.finish_initial_preparation_source_erasure(UUID,UUID,BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.claim_initial_preparation_source_erasure()','Dormant source-retirement metadata claim; no installed transport'),
 ('service_role','public.finish_initial_preparation_source_erasure(uuid,uuid,boolean)','Exact live token acknowledgement of permanent same-key marker; no physical erasure proof by SQL');
COMMENT ON TABLE internal.initial_preparation_installations IS 'Immutable database-owner reviewed installation receipt. No API installer, production fixtures or self-qualification. Actual reviewed evidence and separate target authorization are required before live population.';
COMMENT ON TABLE internal.initial_preparation_source_registry IS 'Permanent content-free source destination and irreversible retirement; private mappings/text/hashes erase separately. No grant or I/O. Conditional data creates and atomically replacing permanent same-key markers require separately qualified storage, including all late writes/copies and physical versions.';
COMMENT ON TABLE internal.initial_analysis_preparation_intents IS 'Inactive immutable discriminated no-media or unresolved-media candidate and complete server assignment; original 300-second lifetime. Media has fixed original-source destinations only and cannot finalize, fund, grant or invoke. Erasure retires source registry before private cascade; global fence remains.';
RESET lock_timeout;
RESET statement_timeout;
