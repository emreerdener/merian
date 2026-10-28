-- Inactive CPM allocation/recovery integration, under construction.
-- No profile, installation, selection, activation or write capability is seeded.
-- Existing intent, retirement and funding owners remain authoritative.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE FUNCTION internal.initial_cpm_photo_original_types_valid(p_types TEXT[]) RETURNS BOOLEAN
LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT COALESCE(array_ndims(p_types)=1 AND array_lower(p_types,1)=1
  AND cardinality(p_types) BETWEEN 1 AND 5
  AND p_types <@ ARRAY['image/jpeg','image/png','image/webp','image/heic','image/heif']::TEXT[]
  AND NOT EXISTS(SELECT 1 FROM unnest(p_types) t WHERE t IS NULL)
  AND cardinality(p_types)=(SELECT count(DISTINCT t) FROM unnest(p_types) t),FALSE);
$$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_original_types_valid(TEXT[]) FROM PUBLIC,anon,authenticated,service_role;

-- Server-only immutable configuration. This domain cannot use a legacy
-- transformation profile's installation target digest. Qualification and
-- installation are separate; the migration installs neither.
CREATE TABLE internal.initial_cpm_photo_profiles(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 resource_profile TEXT NOT NULL CHECK(resource_profile='P1-L1'),
 input_profile TEXT NOT NULL CHECK(input_profile IN ('vision_compat_v1','multimodal_photo_v1')),
 route TEXT NOT NULL CHECK(route IN ('identify','identify-multimodal')),
 output_language TEXT NOT NULL CHECK(octet_length(output_language)<=64 AND output_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
 composition_policy TEXT NOT NULL CHECK(composition_policy='cpm_photo_contexts_v1'),
 verifier_protocol TEXT NOT NULL CHECK(verifier_protocol='cpm_photo_full_bytes_v1'),
 verifier_build_digest TEXT NOT NULL CHECK(verifier_build_digest ~ '^[0-9a-f]{64}$'),
 original_content_types TEXT[] NOT NULL CHECK(internal.initial_cpm_photo_original_types_valid(original_content_types)),
 asset_manifest_digest TEXT NOT NULL REFERENCES internal.initial_analysis_configuration_assets(digest),
 evidence_digest TEXT NOT NULL CHECK(evidence_digest ~ '^[0-9a-f]{64}$'),
 reviewed_revision TEXT NOT NULL CHECK(reviewed_revision ~ '^[0-9a-f]{40}$'),
 CHECK((route='identify')=(input_profile='vision_compat_v1')),
 CHECK(digest=encode(extensions.digest(convert_to('merian.initial-analysis.cpm-photo-profile.v1'||E'\n'||
  internal.initial_canonical(jsonb_build_object('version',1,'resource_profile',resource_profile,
   'input_profile',input_profile,'route',route,'output_language',output_language,
   'composition_policy',composition_policy,'verifier_protocol',verifier_protocol,
   'verifier_build_digest',verifier_build_digest,'original_content_types',original_content_types,
   'asset_manifest_digest',asset_manifest_digest,'evidence_digest',evidence_digest,
   'reviewed_revision',reviewed_revision)),'UTF8'),'sha256'),'hex'))
);
CREATE INDEX initial_cpm_photo_profile_assets ON internal.initial_cpm_photo_profiles(asset_manifest_digest);
CREATE TABLE internal.initial_cpm_photo_profile_eligibility(
 profile_digest TEXT PRIMARY KEY REFERENCES internal.initial_cpm_photo_profiles(digest),
 target_kind TEXT NOT NULL DEFAULT 'profile' CHECK(target_kind='profile'),
 installation_digest TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('eligible','revoked')),
 FOREIGN KEY(target_kind,profile_digest,installation_digest)
  REFERENCES internal.initial_preparation_installations(target_kind,target_digest,digest)
);
CREATE INDEX initial_cpm_photo_profile_installation ON internal.initial_cpm_photo_profile_eligibility(target_kind,profile_digest,installation_digest);
CREATE TABLE internal.initial_cpm_photo_selections(
 generation UUID PRIMARY KEY,
 profile_digest TEXT NOT NULL REFERENCES internal.initial_cpm_photo_profiles(digest),
 backend_generation UUID NOT NULL REFERENCES internal.initial_preparation_source_backends(generation)
);
CREATE INDEX initial_cpm_photo_selection_profile ON internal.initial_cpm_photo_selections(profile_digest);
CREATE INDEX initial_cpm_photo_selection_backend ON internal.initial_cpm_photo_selections(backend_generation);
CREATE TABLE internal.initial_cpm_photo_current_selection(
 resource_profile TEXT PRIMARY KEY CHECK(resource_profile='P1-L1'),
 generation UUID NOT NULL REFERENCES internal.initial_cpm_photo_selections(generation)
);
CREATE INDEX initial_cpm_photo_current_generation ON internal.initial_cpm_photo_current_selection(generation);
CREATE TRIGGER initial_cpm_photo_profiles_immutable BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_profiles
 FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
CREATE TRIGGER initial_cpm_photo_selections_immutable BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_selections
 FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
CREATE TRIGGER initial_cpm_photo_profile_eligibility_irreversible BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_profile_eligibility
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_eligibility();

-- Private mappings disappear with the intent; every opaque destination remains
-- in the existing permanent source registry for retirement/cleanup. No old
-- source-only ordinal mapping is fabricated for AI or display destinations.
CREATE TABLE internal.initial_cpm_photo_role_mapping(
 scan_id UUID NOT NULL REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE,
 photo_ordinal INTEGER NOT NULL CHECK(photo_ordinal BETWEEN 0 AND 1),
 role TEXT NOT NULL CHECK(role IN ('source','ai','display')),
 reference_id UUID NOT NULL,
 object_id UUID NOT NULL UNIQUE,
 PRIMARY KEY(scan_id,photo_ordinal,role),
 UNIQUE(scan_id,reference_id),
 FOREIGN KEY(scan_id,object_id) REFERENCES internal.initial_preparation_source_registry(scan_id,object_id)
);

-- This reservation survives private erasure. Owner detachment does not release
-- its global liability. The allocation-only increment cannot issue any write
-- capability; future IO must replace this closed state contract with proved
-- monotonic issuance/closure before enabling a transfer path.
CREATE TABLE internal.initial_cpm_photo_capacity_reservations(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_operation_fences(scan_id),
 owner_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
 declared_retained_bytes BIGINT NOT NULL CHECK(declared_retained_bytes BETWEEN 1 AND 100663296),
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','released')),
 write_capability_state TEXT NOT NULL DEFAULT 'never_issued' CHECK(write_capability_state='never_issued')
);
-- The full owner index also serves ON DELETE SET NULL for released rows.
CREATE INDEX initial_cpm_photo_capacity_owner ON internal.initial_cpm_photo_capacity_reservations(owner_id);
INSERT INTO internal.ghost_profile_merge_reference_policies
 (source_schema,source_table,source_column,referenced_schema,referenced_table,referenced_column,strategy,execution_order,handler_key,purpose)
VALUES('internal','initial_cpm_photo_capacity_reservations','owner_id','public','users','id','preserve',910,NULL,
 'Hold identity transfer while original CPM capacity ownership remains; never reparent a reservation or disable unrelated empty-owner merges.');

CREATE FUNCTION internal.lock_initial_cpm_photo_capacity() RETURNS VOID
LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
BEGIN
 IF current_setting('transaction_isolation') IS DISTINCT FROM 'read committed' THEN
  RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 -- Outer owner/scan locks are acquired by the existing operation owner first.
 -- Fail-fast acquisition avoids introducing a wait cycle through another owner.
 IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-initial-cpm-capacity:v1',0::BIGINT)) THEN
  RAISE EXCEPTION 'initial_analysis_scope_busy' USING ERRCODE='55000'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.lock_initial_cpm_photo_capacity() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_initial_cpm_photo_capacity() RETURNS TRIGGER
LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE owner_pending BIGINT; global_pending BIGINT; owner_retained BIGINT; global_retained BIGINT;
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.owner_id IS NULL OR NEW.state IS DISTINCT FROM 'pending'
   OR NEW.write_capability_state IS DISTINCT FROM 'never_issued' THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.lock_initial_preparation_scope(NEW.owner_id,NEW.scan_id);
  PERFORM internal.lock_initial_cpm_photo_capacity();
  -- Each command below observes the snapshot after global serialization. Both
  -- the per-owner and global pending pools reserve192MiB for every intent.
  SELECT count(*) FILTER(WHERE owner_id=NEW.owner_id),count(*),
   COALESCE(sum(declared_retained_bytes) FILTER(WHERE owner_id=NEW.owner_id),0),
   COALESCE(sum(declared_retained_bytes),0)
   INTO owner_pending,global_pending,owner_retained,global_retained
   FROM internal.initial_cpm_photo_capacity_reservations WHERE state='pending';
  IF owner_pending>=2 OR global_pending>=16
   OR owner_retained+NEW.declared_retained_bytes>5368709120
   OR global_retained+NEW.declared_retained_bytes>53687091200 THEN
   RAISE EXCEPTION 'initial_analysis_capacity_unavailable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 ELSIF TG_OP='UPDATE' THEN
  PERFORM internal.lock_initial_cpm_photo_capacity();
  IF OLD.owner_id IS NOT NULL AND NEW.owner_id IS NULL
   AND to_jsonb(NEW)-'owner_id'=to_jsonb(OLD)-'owner_id'
   AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id) THEN RETURN NEW; END IF;
  IF OLD.state='pending' AND NEW.state='released'
   AND to_jsonb(NEW)-'state'=to_jsonb(OLD)-'state'
   AND OLD.write_capability_state='never_issued'
   AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id
    AND state='retired' AND execution_state='unissued' AND provider_barrier='blocked_pre_admission')
   AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=OLD.scan_id AND NOT retired)
   AND (OLD.owner_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
    OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
    OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL))
   AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=OLD.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=OLD.scan_id) THEN RETURN NEW; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_cpm_photo_capacity() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_capacity_guard BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_capacity_reservations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_photo_capacity();

DO $private$
DECLARE name TEXT;
BEGIN
 FOREACH name IN ARRAY ARRAY['initial_cpm_photo_profiles','initial_cpm_photo_profile_eligibility',
  'initial_cpm_photo_selections','initial_cpm_photo_current_selection','initial_cpm_photo_role_mapping',
  'initial_cpm_photo_capacity_reservations'] LOOP
  EXECUTE format('ALTER TABLE internal.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON internal.%I FROM PUBLIC,anon,authenticated,service_role',name);
 END LOOP;
END; $private$;

CREATE FUNCTION internal.resolve_initial_cpm_photo_assignment(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_plan TEXT,p_fallback BOOLEAN,p_origin TIMESTAMPTZ,p_objects JSONB
) RETURNS TEXT LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE candidate JSONB; content JSONB; config JSONB; assignment TEXT; manifest JSONB;
 rollout internal.initial_analysis_rollout; profile internal.initial_cpm_photo_profiles;
 selection internal.initial_cpm_photo_selections; eligible internal.initial_cpm_photo_profile_eligibility;
 installed internal.initial_preparation_installations; backend internal.initial_preparation_backend_eligibility;
 policy internal.ai_quota_policies; binding internal.identification_provider_bindings;
 accepted_protocol INTEGER; accepted_capability INTEGER; mapping JSONB; origin_ms BIGINT; selected_generation UUID;
BEGIN
 candidate:=internal.parse_initial_cpm_photo_candidate(p_candidate);
 content:=internal.parse_initial_cpm_photo_content(candidate->>'content_canonical');
 IF content->>'scan_id' IS DISTINCT FROM p_scan::TEXT OR p_origin IS NULL
  OR NOT isfinite(p_origin) OR date_trunc('milliseconds',p_origin)<>p_origin OR p_fallback IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 origin_ms:=floor(extract(epoch FROM p_origin)*1000)::BIGINT;
 SELECT * INTO rollout FROM internal.initial_analysis_rollout WHERE singleton FOR SHARE NOWAIT;
 IF rollout.initial_analysis_lifecycle_enabled IS DISTINCT FROM TRUE THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 SELECT a.manifest INTO manifest FROM internal.initial_analysis_configuration_assets a WHERE a.digest=rollout.configuration_assets_digest;
 IF manifest IS NULL OR manifest->>'retention_owner' IS DISTINCT FROM 'initial_engine_release_archive'
  OR manifest->>'resolver_id' IS DISTINCT FROM 'git_blob_sha256_v1' OR manifest->'schema_version' IS DISTINCT FROM '1'::JSONB
  OR COALESCE(manifest->>'repository_revision','') !~ '^[0-9a-f]{40}$'
  OR jsonb_typeof(manifest->'roots') IS DISTINCT FROM 'array' OR jsonb_typeof(manifest->'files') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 IF jsonb_array_length(manifest->'roots')=0 OR jsonb_array_length(manifest->'files')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'roots') root WHERE jsonb_typeof(root)<>'string' OR length(root#>>'{}')=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'files') file WHERE jsonb_typeof(file)<>'object'
   OR COALESCE(file->>'path','')='' OR COALESCE(file->>'sha256','') !~ '^[0-9a-f]{64}$') THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 SELECT s.generation INTO selected_generation FROM internal.initial_cpm_photo_current_selection s WHERE resource_profile='P1-L1' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT selection FROM internal.initial_cpm_photo_selections WHERE generation=selected_generation;
 SELECT * INTO STRICT profile FROM internal.initial_cpm_photo_profiles WHERE digest=selection.profile_digest;
 SELECT * INTO eligible FROM internal.initial_cpm_photo_profile_eligibility WHERE profile_digest=profile.digest FOR SHARE NOWAIT;
 IF NOT FOUND OR eligible.state<>'eligible' OR profile.asset_manifest_digest<>rollout.configuration_assets_digest THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT installed FROM internal.initial_preparation_installations WHERE digest=eligible.installation_digest;
 IF installed.target_kind<>'profile' OR installed.target_digest<>profile.digest
  OR installed.evidence_digest<>profile.evidence_digest OR installed.reviewed_revision<>profile.reviewed_revision THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO backend FROM internal.initial_preparation_backend_eligibility WHERE initial_preparation_backend_eligibility.generation=selection.backend_generation FOR SHARE NOWAIT;
 IF NOT FOUND OR backend.state<>'eligible' THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(content->'photos') p WHERE
  NOT ((p#>>'{source,declared_content_type}')=ANY(profile.original_content_types))
  OR p#>>'{ai,declared_content_type}'<>'image/jpeg' OR p#>>'{display,declared_content_type}'<>'image/jpeg') THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;

 -- Reuse the existing policy, provider, compatibility and current-consent
 -- owners. Projection is unfunded; a client recipe never selects entitlement.
 PERFORM operation FROM internal.ai_quota_policies WHERE operation='scan_identification' AND effective_plan=p_plan FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_quota_policy_missing' USING ERRCODE='P0001'; END IF;
 SELECT * INTO policy FROM internal.resolve_quota_policy('scan_identification',p_plan);
 PERFORM internal.assert_initial_admission_policy(policy);
 PERFORM operation FROM internal.identification_provider_bindings WHERE operation='scan_identification'
  AND effective_plan=p_plan AND model=policy.model AND policy_version=policy.policy_version AND input_profile=profile.input_profile FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE='P0001'; END IF;
 SELECT * INTO binding FROM internal.resolve_identification_provider_binding('scan_identification',p_plan,policy.model,policy.policy_version,profile.input_profile);
 accepted_protocol:=internal.require_identification_client_protocol(p_owner,'scan_identification',p_scan,profile.input_profile,
  (candidate#>>'{admission,client_protocol}')::INTEGER,FALSE,binding.minimum_client_protocol);
 accepted_capability:=internal.require_identification_capability(p_owner,'scan_identification',p_scan,profile.input_profile,
  (candidate#>>'{admission,identification_protocol}')::INTEGER,FALSE,binding.minimum_identification_protocol);
 IF candidate#>>'{admission,expected_processor_permission}' IS DISTINCT FROM binding.processor_permission THEN
  RAISE EXCEPTION 'ai_identification_preflight_changed' USING ERRCODE='P0001'; END IF;
 PERFORM config_key FROM internal.ai_consent_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM id FROM public.user_adult_eligibility_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM id FROM public.user_terms_acceptance_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM id FROM public.user_ai_consent_events WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM internal.require_identification_processor_consent(p_owner,binding.processor_permission);
 IF jsonb_typeof(p_objects) IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_objects)<>jsonb_array_length(content->'photos')*3 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_object('photo_ordinal',n-1,'role',r.role,
  'object_id',p_objects->((n::INTEGER-1)*3+r.position),'declaration',p->r.role) ORDER BY n,r.position)
  INTO mapping FROM jsonb_array_elements(content->'photos') WITH ORDINALITY photos(p,n)
  CROSS JOIN (VALUES('source',0),('ai',1),('display',2)) r(role,position);
 config:=jsonb_build_object('route',profile.route,'operation','scan_identification','effective_plan',p_plan,
  'effective_tier',CASE WHEN p_plan='free' THEN 'free' ELSE 'pro' END,'flash_fallback_used',p_fallback,
  'quota_model',policy.model,'policy_version',policy.policy_version,'provider',binding.provider,'binding',binding.binding,
  'processor_permission',binding.processor_permission,'input_profile',profile.input_profile,'provider_model',binding.provider_model,
  'effective_model',COALESCE(binding.provider_model,policy.model),'minimum_client_protocol',binding.minimum_client_protocol,
  'accepted_client_protocol',accepted_protocol,'minimum_identification_protocol',binding.minimum_identification_protocol,
  'accepted_identification_protocol',accepted_capability,'asset_manifest_digest',rollout.configuration_assets_digest,
  'retention_owner','initial_engine_release_archive','resolver_id','git_blob_sha256_v1','output_language',profile.output_language);
 assignment:=internal.initial_canonical(jsonb_build_object('version',1,'variant','client_prepared_photo',
  'candidate_digest',internal.initial_cpm_photo_digest('candidate',p_candidate),
  'content_digest',internal.initial_cpm_photo_digest('content',candidate->>'content_canonical'),
  'scan_id',p_scan,'package_id',content->>'package_id','created_at_ms',origin_ms,'expires_at_ms',origin_ms+1800000,
  'configuration',config,'preparation',jsonb_build_object('resource_profile','P1-L1','composition_policy',profile.composition_policy,
   'profile_digest',profile.digest,'installation_digest',eligible.installation_digest,'selector_generation',selection.generation,
   'backend_generation',selection.backend_generation,'backend_installation_digest',backend.installation_digest,
   'verifier_build_digest',profile.verifier_build_digest,'role_mapping',mapping)));
 PERFORM internal.parse_initial_cpm_photo_assignment(p_candidate,assignment);
 RETURN assignment;
END; $$;
REVOKE ALL ON FUNCTION internal.resolve_initial_cpm_photo_assignment(UUID,UUID,TEXT,TEXT,BOOLEAN,TIMESTAMPTZ,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cpm_photo_saved_profile_matches(p_candidate TEXT,p_assignment TEXT) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE a JSONB; c JSONB; profile internal.initial_cpm_photo_profiles;
 selection internal.initial_cpm_photo_selections; installed internal.initial_preparation_installations;
 backend internal.initial_preparation_source_backends; backend_install internal.initial_preparation_installations;
BEGIN
 a:=internal.parse_initial_cpm_photo_assignment(p_candidate,p_assignment);
 c:=(internal.parse_initial_cpm_photo_candidate(p_candidate)->>'content_canonical')::JSONB;
 SELECT * INTO profile FROM internal.initial_cpm_photo_profiles WHERE digest=a#>>'{preparation,profile_digest}';
 IF NOT FOUND THEN RETURN FALSE; END IF;
 SELECT * INTO selection FROM internal.initial_cpm_photo_selections WHERE generation=(a#>>'{preparation,selector_generation}')::UUID;
 IF NOT FOUND OR selection.profile_digest<>profile.digest OR selection.backend_generation::TEXT<>a#>>'{preparation,backend_generation}' THEN RETURN FALSE; END IF;
 SELECT * INTO installed FROM internal.initial_preparation_installations WHERE digest=a#>>'{preparation,installation_digest}';
 IF NOT FOUND OR installed.target_kind<>'profile' OR installed.target_digest<>profile.digest
  OR installed.evidence_digest<>profile.evidence_digest OR installed.reviewed_revision<>profile.reviewed_revision THEN RETURN FALSE; END IF;
 SELECT * INTO backend FROM internal.initial_preparation_source_backends WHERE generation=selection.backend_generation;
 IF NOT FOUND THEN RETURN FALSE; END IF;
 SELECT * INTO backend_install FROM internal.initial_preparation_installations WHERE digest=a#>>'{preparation,backend_installation_digest}';
 IF NOT FOUND OR backend_install.target_kind<>'backend' OR backend_install.target_digest<>backend.configuration_digest THEN RETURN FALSE; END IF;
 RETURN a#>>'{configuration,input_profile}'=profile.input_profile AND a#>>'{configuration,route}'=profile.route
  AND a#>>'{configuration,output_language}'=profile.output_language
  AND a#>>'{configuration,asset_manifest_digest}'=profile.asset_manifest_digest
  AND a#>>'{preparation,resource_profile}'=profile.resource_profile
  AND a#>>'{preparation,composition_policy}'=profile.composition_policy
  AND a#>>'{preparation,verifier_build_digest}'=profile.verifier_build_digest
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'photos') p WHERE
   NOT ((p#>>'{source,declared_content_type}')=ANY(profile.original_content_types))
   OR p#>>'{ai,declared_content_type}'<>'image/jpeg' OR p#>>'{display,declared_content_type}'<>'image/jpeg');
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_saved_profile_matches(TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cpm_photo_cohort_complete(p_scan UUID) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; member JSONB; members INTEGER; retained BIGINT;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo'
  OR NOT internal.initial_cpm_photo_saved_profile_matches(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
 a:=saved.canonical_assignment::JSONB; members:=jsonb_array_length(a#>'{preparation,role_mapping}');
 SELECT sum((m#>>'{declaration,byte_count}')::BIGINT) INTO retained FROM jsonb_array_elements(a#>'{preparation,role_mapping}') m;
 IF extract(epoch FROM saved.created_at)*1000<>(a->>'created_at_ms')::NUMERIC
  OR extract(epoch FROM saved.expires_at)*1000<>(a->>'expires_at_ms')::NUMERIC
  OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan
   AND state='allocated' AND execution_state='unissued' AND provider_barrier='blocked_pre_admission')
  OR NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan
   AND owner_id=saved.owner_id AND state='pending' AND write_capability_state='never_issued' AND declared_retained_bytes=retained)
  OR (SELECT count(*) FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan)<>members
  OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan)<>members
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan) THEN RETURN FALSE; END IF;
 FOR member IN SELECT m FROM jsonb_array_elements(a#>'{preparation,role_mapping}') m LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping m JOIN internal.initial_preparation_source_registry r USING(scan_id,object_id)
   WHERE m.scan_id=p_scan AND m.photo_ordinal=(member->>'photo_ordinal')::INTEGER AND m.role=member->>'role'
    AND m.reference_id::TEXT=member#>>'{declaration,reference_id}' AND m.object_id::TEXT=member->>'object_id'
    AND r.backend_generation::TEXT=a#>>'{preparation,backend_generation}' AND NOT r.retired AND NOT r.marker_confirmed AND r.claim_token IS NULL) THEN RETURN FALSE; END IF;
 END LOOP;
 RETURN TRUE;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_cohort_complete(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.require_initial_cpm_photo_cohort() RETURNS TRIGGER
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE identity UUID; candidate TEXT;
BEGIN
 identity:=CASE WHEN TG_OP='DELETE' THEN OLD.scan_id ELSE NEW.scan_id END;
 SELECT canonical_candidate INTO candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
 IF candidate IS NOT NULL AND candidate::JSONB->>'variant'='client_prepared_photo' THEN
  IF NOT internal.initial_cpm_photo_cohort_complete(identity) THEN
   RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=identity)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=identity AND state<>'released') THEN
  RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION internal.require_initial_cpm_photo_cohort() FROM PUBLIC,anon,authenticated,service_role;
CREATE CONSTRAINT TRIGGER initial_cpm_photo_intent_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_preparation_intents
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_cpm_photo_cohort();
CREATE CONSTRAINT TRIGGER initial_cpm_photo_mapping_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_role_mapping
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_cpm_photo_cohort();
CREATE CONSTRAINT TRIGGER initial_cpm_photo_capacity_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_capacity_reservations
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_cpm_photo_cohort();

CREATE FUNCTION internal.guard_initial_cpm_photo_mapping() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.scan_id)
  AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id AND state='retired') THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_cpm_photo_mapping() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_mapping_immutable BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_role_mapping
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_photo_mapping();


-- Raw inserts must resolve the same current eligibility, policy and entitlement
-- as the allocating owner. Saved recovery deliberately does not re-resolve it.
CREATE FUNCTION internal.assert_initial_cpm_photo_intent_insert(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT,p_origin TIMESTAMPTZ
) RETURNS VOID LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE projected RECORD; objects JSONB; expected TEXT; now_at TIMESTAMPTZ:=clock_timestamp();
BEGIN
 PERFORM internal.parse_initial_cpm_photo_assignment(p_candidate,p_assignment);
 IF p_origin IS NULL OR p_origin>now_at OR p_origin<now_at-INTERVAL '5 seconds' THEN
  RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 SELECT * INTO projected FROM internal.resolve_fresh_quota_entitlement(p_owner,'scan_identification',p_scan,FALSE,p_origin);
 SELECT jsonb_agg(m->'object_id' ORDER BY n) INTO objects
  FROM jsonb_array_elements(p_assignment::JSONB#>'{preparation,role_mapping}') WITH ORDINALITY v(m,n);
 expected:=internal.resolve_initial_cpm_photo_assignment(p_owner,p_scan,p_candidate,
  projected.effective_plan,projected.flash_fallback_used,p_origin,objects);
 IF expected IS DISTINCT FROM p_assignment THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_photo_intent_insert(UUID,UUID,TEXT,TEXT,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.valid_initial_preparation_pair(p_candidate text, p_assignment text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE c JSONB; a JSONB;
BEGIN
 IF p_candidate IS NULL OR octet_length(p_candidate)>1048576 OR p_assignment IS NULL OR octet_length(p_assignment)>65536 THEN RETURN FALSE; END IF;
 BEGIN c:=p_candidate::JSONB; a:=p_assignment::JSONB; EXCEPTION WHEN OTHERS THEN RETURN FALSE; END;
 IF c->>'variant'='client_prepared_photo' THEN
  PERFORM internal.parse_initial_cpm_photo_assignment(p_candidate,p_assignment); RETURN TRUE; END IF;
 IF c->>'variant'='media_sources' THEN RETURN internal.valid_initial_saved_media_assignment_pair(p_candidate,p_assignment); END IF;
 PERFORM internal.parse_initial_preparation_candidate(p_candidate);
 RETURN internal.initial_canonical(a)=p_assignment AND internal.initial_schema_matches(a,internal.initial_assignment_schema_v2()) AND a->>'candidate_digest'=internal.initial_preparation_digest('preparation-candidate',p_candidate);
END; $function$;


ALTER TABLE internal.initial_analysis_preparation_intents
 DROP CONSTRAINT initial_analysis_preparation_intents_check,
 DROP CONSTRAINT initial_analysis_preparation_intents_check1,
 DROP CONSTRAINT initial_analysis_preparation_intents_check2,
 ADD CONSTRAINT initial_analysis_preparation_intents_check CHECK(candidate_digest=
  CASE WHEN canonical_candidate::JSONB->>'variant'='client_prepared_photo'
   THEN internal.initial_cpm_photo_digest('candidate',canonical_candidate)
   ELSE internal.initial_preparation_digest('preparation-candidate',canonical_candidate) END),
 ADD CONSTRAINT initial_analysis_preparation_intents_check1 CHECK(assignment_digest=
  CASE WHEN canonical_candidate::JSONB->>'variant'='client_prepared_photo'
   THEN internal.initial_cpm_photo_digest('assignment',canonical_assignment)
   ELSE internal.initial_preparation_digest('assignment',canonical_assignment) END),
 ADD CONSTRAINT initial_analysis_preparation_intents_check2 CHECK(expires_at=created_at+
  CASE WHEN canonical_candidate::JSONB->>'variant'='client_prepared_photo'
   THEN INTERVAL '30 minutes' ELSE INTERVAL '300 seconds' END);

CREATE OR REPLACE FUNCTION internal.guard_initial_preparation_storage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE recovered JSONB;
BEGIN
 IF TG_OP='INSERT' THEN
  PERFORM internal.lock_initial_preparation_scope(NEW.owner_id,NEW.scan_id);
  PERFORM internal.assert_initial_preparation_unfunded(NEW.owner_id,NEW.scan_id);
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;

  IF NEW.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN
   PERFORM internal.assert_initial_cpm_photo_intent_insert(NEW.owner_id,NEW.scan_id,NEW.canonical_candidate,NEW.canonical_assignment,NEW.created_at);
  END IF;
  IF NEW.canonical_candidate::JSONB->>'variant'='media_sources' THEN
   PERFORM internal.assert_initial_media_intent_insert(NEW.owner_id,NEW.scan_id,NEW.canonical_candidate,NEW.canonical_assignment);
  END IF;
  RETURN NEW;
 ELSIF TG_OP='DELETE' THEN
  IF internal.initial_media_handoff_transfer_event('internal.initial_analysis_preparation_intents',to_jsonb(OLD),NULL) THEN RETURN OLD; END IF;
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
$function$;


CREATE OR REPLACE FUNCTION internal.require_initial_source_cohort()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE identity UUID; candidate TEXT;
BEGIN
 identity:=CASE WHEN TG_OP='DELETE' THEN OLD.scan_id ELSE NEW.scan_id END;
 SELECT canonical_candidate INTO candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
 IF candidate IS NULL THEN
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity AND state<>'retired') OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=identity AND NOT retired) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF candidate::JSONB->>'variant'='client_prepared_photo' THEN
  IF NOT internal.initial_cpm_photo_cohort_complete(identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF candidate::JSONB->>'variant'='media_sources' THEN
  IF NOT internal.initial_preparation_execution_coherent(identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END; $function$;


CREATE OR REPLACE FUNCTION internal.initial_preparation_sources_complete(p_scan uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; item JSONB; count_sources INTEGER;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF FOUND AND saved.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN RETURN internal.initial_cpm_photo_cohort_complete(p_scan); END IF;
 IF saved.scan_id IS NULL OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'media_sources' THEN RETURN FALSE; END IF;
 IF NOT internal.valid_initial_saved_media_assignment_pair(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
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
END; $function$;


CREATE OR REPLACE FUNCTION internal.can_cancel_initial_preparation(p_owner uuid, p_scan uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan AND state='allocated' AND provider_barrier='blocked_pre_admission')
  OR NOT (CASE WHEN EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='client_prepared_photo')
   THEN internal.initial_cpm_photo_cohort_complete(p_scan) ELSE internal.initial_preparation_execution_coherent(p_scan) END) THEN RETURN FALSE; END IF;
 BEGIN PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan); EXCEPTION WHEN invalid_parameter_value THEN RETURN FALSE; END;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN RETURN FALSE; END IF;
 RETURN TRUE;
END; $function$;


CREATE OR REPLACE FUNCTION internal.cancel_initial_analysis(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE owned_by UUID; scan_exists BOOLEAN; saved internal.initial_analysis_cancellations;
 submission internal.initial_analysis_submissions; admission internal.initial_analysis_admissions;
 quota internal.ai_quota_reservations; funding JSONB; allocation internal.complimentary_scan_usage;
 lifecycle TEXT; terminal TEXT:='cancelled_unknown'; classification TEXT; proven BOOLEAN:=FALSE; settlement JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO owned_by FROM public.scans WHERE id=p_scan FOR UPDATE;
 scan_exists:=FOUND;
 IF scan_exists AND owned_by IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 SELECT state INTO lifecycle FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;

 PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id<>p_owner) THEN
  RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_already_complete' USING ERRCODE='55000'; END IF;
 IF saved.scan_id IS NOT NULL THEN
  IF saved.dispatch IS DISTINCT FROM internal.initial_cancellation_dispatch(lifecycle) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',saved.dispatch);
 END IF;
 IF internal.initial_cancellation_dispatch(lifecycle) IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF submission.scan_id IS NULL THEN
  -- First-writer-wins namespace claim, never proof of absent legacy execution.
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
    AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner)
   OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
   OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan) THEN
   RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;

  IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner) THEN


   IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo')) THEN
    terminal:=CASE WHEN internal.can_cancel_initial_preparation(p_owner,p_scan) THEN 'cancelled_pre_dispatch' ELSE 'cancelled_unknown' END;
   ELSE PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan); terminal:='cancelled_pre_dispatch'; END IF;


  ELSIF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled)

   OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 ELSE
  SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
  SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admission.funding_binding_id AND user_id=p_owner FOR UPDATE;
  -- The owner is already locked. Do not take the usage row before the quota
  -- counter order; the existing settlement owner locks/rechecks it below.
  SELECT * INTO allocation FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan;
  funding:=jsonb_build_object('version',1,'original',jsonb_build_object(
   'reservation_id',quota.id,'request_id',quota.request_id,'original_analysis_id',quota.original_analysis_id,
   'operation',quota.operation,'attempt_count',quota.attempt_count,'effective_plan',quota.effective_plan,
   'effective_tier',quota.effective_tier,'entitlement_version',quota.entitlement_version,'policy_version',quota.policy_version,
   'model',quota.model,'complimentary_client_scan_id',quota.complimentary_client_scan_id,'flash_fallback_used',quota.flash_fallback_used));
  proven:=NOT internal.initial_admitted_settlement_blocked(p_scan)
   AND lifecycle='pending_pre_dispatch' AND admission.owner_id=p_owner AND quota.user_id=p_owner
   AND quota.request_id=p_scan AND quota.original_analysis_id=p_scan AND quota.operation='scan_identification'
   AND quota.attempt_count=1 AND quota.state='reserved' AND quota.committed_at IS NULL AND quota.failed_at IS NULL
   AND quota.refunded_at IS NULL AND quota.refund_count=0 AND quota.stale_recovery_count=0
   AND submission.funding_snapshot=funding
   AND admission.funding_digest=internal.initial_digest('funding',internal.initial_canonical(funding))
   AND ((quota.complimentary_client_scan_id IS NULL AND allocation.client_scan_id IS NULL)
    OR (quota.complimentary_client_scan_id=p_scan AND allocation.state='held'))
   AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
   AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
   AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan OR reservation_id=quota.id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan);
  IF proven IS TRUE THEN
   IF NOT internal.finalize_ai_quota_reservation_core(quota.id,p_owner,quota.lease_token,'refunded') THEN
    RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
   settlement:=internal.settle_complimentary_analysis(p_owner,p_scan,'cancelled_before_dispatch');
   IF (settlement->>'credit_released')::BOOLEAN IS DISTINCT FROM (quota.complimentary_client_scan_id IS NOT NULL) THEN
    RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
   terminal:='cancelled_pre_dispatch';
  ELSIF lifecycle='dispatch_authorized' THEN terminal:='cancelled_dispatched';
  END IF;
 END IF;
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan) ON CONFLICT(scan_id) DO NOTHING;
 IF lifecycle IS NULL THEN
  INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(p_scan,terminal);
 ELSE
  PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,'begin');
  UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal WHERE scan_id=p_scan;
  PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,'end');
 END IF;
 classification:=internal.initial_cancellation_dispatch(terminal);
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
  PERFORM internal.lock_initial_media_handoff_members(p_scan);
 END IF;
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
     PERFORM internal.retire_initial_preparation_source_objects(p_scan);
     IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan) THEN
         PERFORM internal.retire_initial_media_objects(p_scan);
     END IF;
     DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
     DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 ELSE
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 END IF;
 INSERT INTO internal.initial_analysis_cancellations(scan_id,owner_id,dispatch) VALUES(p_scan,p_owner,classification);
 RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',classification);
END;
$function$;


CREATE OR REPLACE FUNCTION internal.retire_initial_sources_before_erasure()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 -- Transfer has already retired the exact captured union. Calling the
 -- generic helper here would emit unregistered duplicate UPDATE statements.
 IF internal.initial_media_handoff_transfer_event('internal.initial_analysis_preparation_intents',to_jsonb(OLD),NULL) THEN RETURN OLD; END IF;
 IF OLD.canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo') THEN
  IF NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
   AND EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL) THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.retire_initial_preparation_source_objects(OLD.scan_id);
 END IF;
 RETURN OLD;
END; $function$;


CREATE OR REPLACE FUNCTION internal.retire_initial_preparation_source_objects(p_scan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE object UUID;
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan AND state='pending') THEN
  PERFORM internal.lock_initial_cpm_photo_capacity();
 END IF;
 PERFORM internal.advance_initial_cancellation_retirement(p_scan,'source','begin');
 UPDATE internal.initial_preparation_source_fences SET state='retired' WHERE scan_id=p_scan AND state='allocated';
 FOR object IN SELECT object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE LOOP
  UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE object_id=object AND NOT retired;
 END LOOP;
 PERFORM internal.advance_initial_cancellation_retirement(p_scan,'source','end');
 -- Closed never-issued proof is enforced again by the reservation guard.
 UPDATE internal.initial_cpm_photo_capacity_reservations SET state='released' WHERE scan_id=p_scan AND state='pending';
END; $function$;


CREATE FUNCTION internal.initial_cpm_photo_preparation_response(p_scan UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; response JSONB;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT internal.initial_cpm_photo_cohort_complete(p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 response:=jsonb_build_object('version',1,'variant','client_prepared_photo','outcome','allocated','authority','none',
  'assignment_canonical',saved.canonical_assignment,'assignment_digest',saved.assignment_digest);
 PERFORM internal.parse_initial_cpm_photo_recovery(saved.canonical_candidate,internal.initial_canonical(response),saved.canonical_assignment);
 RETURN response;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_preparation_response(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.create_initial_cpm_photo_preparation(p_owner UUID,p_scan UUID,p_candidate TEXT) RETURNS JSONB
LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE candidate JSONB; content JSONB; saved internal.initial_analysis_preparation_intents;
 projected RECORD; objects JSONB; assignment TEXT; origin TIMESTAMPTZ; item JSONB; retained BIGINT;
BEGIN
 candidate:=internal.parse_initial_cpm_photo_candidate(p_candidate);
 content:=internal.parse_initial_cpm_photo_content(candidate->>'content_canonical');
 IF content->>'scan_id' IS DISTINCT FROM p_scan::TEXT THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.owner_id IS DISTINCT FROM p_owner OR saved.canonical_candidate IS DISTINCT FROM p_candidate THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  IF clock_timestamp()>=saved.expires_at THEN
   PERFORM internal.cancel_initial_analysis(p_owner,p_scan);
   RETURN jsonb_build_object('version',1,'variant','client_prepared_photo','outcome','terminal_held',
    'authority','none','scan_id',p_scan,'reason','expired'); END IF;
  -- Before consulting current eligibility/configuration/capacity, return only
  -- the persisted original. A lost acknowledgement never starts another clock.
  RETURN internal.initial_cpm_photo_preparation_response(p_scan);
 END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR p_scan::TEXT ~ '^ac0[ab]0001-[0-9a-f]{4}-8' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 origin:=date_trunc('milliseconds',clock_timestamp());
 SELECT * INTO projected FROM internal.resolve_fresh_quota_entitlement(p_owner,'scan_identification',p_scan,FALSE,origin);
 SELECT jsonb_agg(gen_random_uuid() ORDER BY n) INTO objects FROM generate_series(1,3*jsonb_array_length(content->'photos')) n;
 assignment:=internal.resolve_initial_cpm_photo_assignment(p_owner,p_scan,p_candidate,projected.effective_plan,projected.flash_fallback_used,origin,objects);
 SELECT sum((m#>>'{declaration,byte_count}')::BIGINT) INTO retained FROM jsonb_array_elements(assignment::JSONB#>'{preparation,role_mapping}') m;
 -- The existing fresh-source guard requires its claim before the operation
 -- fence. All claims and capacity reservation still commit or roll back together.
 INSERT INTO internal.initial_preparation_source_fences(scan_id,state,provider_barrier) VALUES(p_scan,'allocated','blocked_pre_admission');
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);
 INSERT INTO internal.initial_cpm_photo_capacity_reservations(scan_id,owner_id,declared_retained_bytes) VALUES(p_scan,p_owner,retained);
 INSERT INTO internal.initial_analysis_preparation_intents(scan_id,owner_id,canonical_candidate,candidate_digest,
  canonical_assignment,assignment_digest,created_at,expires_at)
 VALUES(p_scan,p_owner,p_candidate,internal.initial_cpm_photo_digest('candidate',p_candidate),
  assignment,internal.initial_cpm_photo_digest('assignment',assignment),origin,origin+INTERVAL '30 minutes');
 FOR item IN SELECT m FROM jsonb_array_elements(assignment::JSONB#>'{preparation,role_mapping}') m ORDER BY (m->>'object_id')::UUID LOOP
  INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation)
   VALUES((item->>'object_id')::UUID,p_scan,(assignment::JSONB#>>'{preparation,backend_generation}')::UUID);
  INSERT INTO internal.initial_cpm_photo_role_mapping(scan_id,photo_ordinal,role,reference_id,object_id)
   VALUES(p_scan,(item->>'photo_ordinal')::INTEGER,item->>'role',(item#>>'{declaration,reference_id}')::UUID,(item->>'object_id')::UUID);
 END LOOP;
 RETURN internal.initial_cpm_photo_preparation_response(p_scan);
END; $$;
REVOKE ALL ON FUNCTION internal.create_initial_cpm_photo_preparation(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.create_initial_preparation_intent(p_owner uuid, p_scan uuid, p_candidate text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE candidate JSONB; saved internal.initial_analysis_preparation_intents; recovered JSONB;
 projected RECORD; assignment TEXT; origin TIMESTAMPTZ; fallback BOOLEAN; existing_input JSONB;
BEGIN
 PERFORM internal.require_service_role();

 IF p_candidate IS NOT NULL AND octet_length(p_candidate)<=1048576 THEN
  BEGIN
   IF p_candidate::JSONB->>'variant'='client_prepared_photo' THEN RETURN internal.create_initial_cpm_photo_preparation(p_owner,p_scan,p_candidate); END IF;
   IF p_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.create_initial_media_preparation(p_owner,p_scan,p_candidate); END IF;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 END IF;
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
$function$;


CREATE OR REPLACE FUNCTION public.get_initial_preparation_status(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; recovered JSONB;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);

 IF EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  RETURN internal.recover_initial_admitted_media(p_owner,p_scan);
 END IF;
 recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);
 IF recovered IS NOT NULL THEN RETURN recovered; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF clock_timestamp()>=saved.expires_at THEN
  PERFORM internal.cancel_initial_analysis(p_owner,p_scan);

  IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.checked_initial_media_preparation_response(jsonb_build_object('version',(saved.canonical_assignment::JSONB->>'version')::INTEGER,'variant','media_sources','outcome','expired','authority','none')); END IF;
  IF saved.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN
   RETURN jsonb_build_object('version',1,'variant','client_prepared_photo','outcome','terminal_held','authority','none','scan_id',p_scan,'reason','expired'); END IF;
  RETURN jsonb_build_object('version',2,'outcome','expired');
 END IF;

 IF saved.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN RETURN internal.initial_cpm_photo_preparation_response(p_scan); END IF;
 IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.initial_media_preparation_response(p_scan); END IF;
 RETURN jsonb_build_object('version',2,'outcome','prepared','candidate_digest',saved.candidate_digest,
  'assignment_digest',saved.assignment_digest,'expires_at',saved.expires_at);
END;
$function$;


CREATE OR REPLACE FUNCTION internal.guard_initial_preparation_execution_private()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; grant_value JSONB; now_ms BIGINT; issue_ms BIGINT; ctx JSONB;
BEGIN
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id AND state='retired') THEN RETURN OLD; END IF;
 ELSIF TG_OP='INSERT' THEN
  SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
  IF saved.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN
   RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;
  PERFORM internal.lock_initial_preparation_scope(saved.owner_id,NEW.scan_id);
  PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND state='allocated' AND provider_barrier='blocked_pre_admission') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  IF now_ms>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
  SELECT canonical_grant::JSONB INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=NEW.scan_id;
  IF TG_TABLE_NAME IN ('initial_preparation_source_verifications','initial_preparation_execution_grants') THEN
   PERFORM internal.lock_initial_preparation_eligibility(NEW.scan_id);
   IF saved.canonical_assignment::JSONB->>'version'='3' THEN ctx:=internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment); END IF;
   now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
   IF now_ms>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
   IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND execution_state='unissued') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
   IF TG_TABLE_NAME='initial_preparation_source_verifications' THEN PERFORM internal.validate_initial_execution_source(NEW.scan_id,NEW.canonical_receipt);
   ELSE
    IF ctx IS NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_qualification_unavailable' USING ERRCODE='55000'; END IF;
    IF now_ms+45000+internal.initial_preparation_cohort_wall(ctx->'assignment',ctx->'profile')+(ctx#>>'{assignment,handoff,profile,total_ms}')::BIGINT>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    PERFORM internal.validate_initial_execution_grant(NEW.scan_id,NEW.canonical_grant);
    issue_ms:=(NEW.canonical_grant::JSONB->>'issued_at_ms')::BIGINT;
    IF issue_ms>now_ms OR issue_ms<now_ms-5000 THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
   END IF;
  ELSE
   IF grant_value IS NULL OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND execution_state='issued') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
   IF TG_TABLE_NAME IN ('initial_preparation_output_manifests','initial_preparation_output_mapping') THEN
    IF now_ms>=(grant_value->>'registration_deadline_ms')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    IF TG_TABLE_NAME='initial_preparation_output_manifests' THEN PERFORM internal.validate_initial_execution_output(NEW.scan_id,NEW.canonical_request); END IF;
   ELSE
    IF now_ms>=(grant_value->>'outcome_deadline_ms')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    PERFORM internal.validate_initial_execution_outcome(NEW.scan_id,NEW.canonical_outcome);
   END IF;
  END IF;
  RETURN NEW;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $function$;


CREATE OR REPLACE FUNCTION internal.initial_preparation_execution_action(p_action text, p_owner uuid, p_scan uuid, p_assignment_digest text, p_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; fence internal.initial_preparation_source_fences; source_proof internal.initial_preparation_source_verifications; grant_value JSONB; output internal.initial_preparation_output_manifests; outcome TEXT; value JSONB; digest TEXT; now_ms BIGINT; expiry_ms BIGINT; wall BIGINT; profile JSONB; resolved JSONB; entries JSONB:='[]'::JSONB; item JSONB; prepared JSONB; object UUID; identity UUID; backend UUID; n INTEGER; reply_version INTEGER; ctx JSONB; handoff JSONB; admitted_recovery JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_action IS NULL OR p_action NOT IN ('sources','issue','output','outcome','status') OR p_owner IS NULL OR p_scan IS NULL OR p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  admitted_recovery:=internal.recover_initial_admitted_media(p_owner,p_scan);
  IF admitted_recovery#>>'{binding,assignment_digest}' IS DISTINCT FROM p_assignment_digest THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
  END IF;
  RETURN internal.initial_preparation_held_reply(2,'incoherent');
 END IF;

 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN RETURN internal.initial_preparation_held_reply(1,'missing'); END IF;
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 IF saved.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;
 reply_version:=CASE WHEN saved.canonical_assignment::JSONB->>'version'='3' THEN 2 ELSE 1 END;
 now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT; expiry_ms:=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT;
 IF now_ms>=expiry_ms THEN PERFORM internal.cancel_initial_analysis(p_owner,p_scan); RETURN internal.initial_preparation_held_reply(reply_version,'expired'); END IF;
 SELECT * INTO fence FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan;
 IF NOT internal.initial_preparation_execution_coherent(p_scan) THEN RETURN internal.initial_preparation_held_reply(reply_version,'incoherent'); END IF;
 SELECT * INTO source_proof FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT canonical_grant::JSONB INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT * INTO output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_outcome INTO outcome FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan;
 IF p_action='status' THEN
  RETURN jsonb_build_object('version',reply_version,'outcome','status','phase',CASE WHEN outcome IS NOT NULL THEN 'outcome_ready' WHEN output.scan_id IS NOT NULL THEN 'output_registered' WHEN grant_value IS NOT NULL THEN 'issued' WHEN source_proof.scan_id IS NOT NULL THEN 'verified' ELSE 'allocated' END,
   'source',source_proof.canonical_receipt::JSONB,'execution_reference',CASE WHEN grant_value IS NOT NULL THEN jsonb_build_object('grant_id',grant_value->'grant_id','source_digest',grant_value->'source_digest') END,'output',CASE WHEN output.scan_id IS NOT NULL THEN jsonb_build_object('request',output.canonical_request::JSONB,'resolved',output.canonical_resolved::JSONB) END,'result',outcome::JSONB,'server_now_ms',now_ms,'expires_at_ms',expiry_ms);
 END IF;
 IF fence.provider_barrier IS DISTINCT FROM 'blocked_pre_admission' OR NOT internal.can_cancel_initial_preparation(p_owner,p_scan) THEN RETURN internal.initial_preparation_held_reply(reply_version,'incoherent'); END IF;
 IF p_action='sources' THEN
  PERFORM internal.validate_initial_execution_source(p_scan,p_text);
  IF source_proof.scan_id IS NOT NULL THEN
   IF source_proof.canonical_receipt IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  ELSE
   PERFORM internal.lock_initial_preparation_eligibility(p_scan);
   IF fence.execution_state<>'unissued' THEN RETURN internal.initial_preparation_held_reply(reply_version,'preparation_issued'); END IF;
   INSERT INTO internal.initial_preparation_source_verifications(scan_id,canonical_receipt,digest) VALUES(p_scan,p_text,internal.initial_preparation_execution_digest('source_verification',p_text));
  END IF;
  RETURN jsonb_build_object('version',reply_version,'outcome','verified','receipt',p_text::JSONB,'digest',internal.initial_preparation_execution_digest('source_verification',p_text));
 ELSIF p_action='issue' THEN
  IF fence.execution_state='issued' THEN RETURN internal.initial_preparation_held_reply(reply_version,'preparation_issued'); END IF;
  IF source_proof.scan_id IS NULL OR source_proof.digest IS DISTINCT FROM p_text THEN RETURN internal.initial_preparation_held_reply(reply_version,'missing'); END IF;
  IF reply_version=1 THEN RETURN internal.initial_preparation_held_reply(2,'handoff_qualification_unavailable'); END IF;
  PERFORM internal.lock_initial_preparation_eligibility(p_scan);
  ctx:=internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment); handoff:=ctx#>'{assignment,handoff,profile}';
  SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
  wall:=internal.initial_preparation_cohort_wall(saved.canonical_assignment::JSONB,profile); now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  IF now_ms+45000+wall+(handoff->>'total_ms')::BIGINT>=expiry_ms THEN RETURN internal.initial_preparation_held_reply(reply_version,'budget'); END IF;
  grant_value:=jsonb_build_object('version',2,'handoff_profile_digest',saved.canonical_assignment::JSONB#>>'{handoff,profile_digest}','handoff_installation_digest',saved.canonical_assignment::JSONB#>>'{handoff,installation_digest}','protocol_artifact_digest',handoff->>'protocol_artifact_digest','handoff_total_ms',handoff->'total_ms','preparation_wall_ms',wall,'preparation_expires_at_ms',expiry_ms,'scan_id',p_scan,'assignment_digest',p_assignment_digest,'grant_id',gen_random_uuid(),'source_digest',source_proof.digest,'profile_digest',saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}','artifact_digest',profile#>>'{spec,artifact,sha256}',
   'issued_at_ms',now_ms,'execution_deadline_ms',now_ms+5000+wall,'registration_deadline_ms',now_ms+10000+wall,'outcome_deadline_ms',now_ms+45000+wall);
  INSERT INTO internal.initial_preparation_execution_grants(scan_id,canonical_grant) VALUES(p_scan,internal.initial_canonical(grant_value));
  UPDATE internal.initial_preparation_source_fences SET execution_state='issued' WHERE scan_id=p_scan;
  RETURN jsonb_build_object('version',reply_version,'outcome','granted','grant',grant_value,'server_now_ms',floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT,'expires_at_ms',expiry_ms);
 ELSIF p_action='output' THEN
  PERFORM internal.validate_initial_execution_output(p_scan,p_text);
  IF output.scan_id IS NOT NULL THEN
   IF output.canonical_request IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('version',reply_version,'outcome','registered','request',output.canonical_request::JSONB,'resolved',output.canonical_resolved::JSONB);
  END IF;
  IF grant_value IS NULL OR floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT>=(grant_value->>'registration_deadline_ms')::BIGINT THEN RETURN internal.initial_preparation_held_reply(reply_version,'phase_expired'); END IF;
  value:=p_text::JSONB; digest:=internal.initial_preparation_execution_digest('output_manifest',p_text);
  FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(value->'entries') WITH ORDINALITY v(e,i) LOOP
   prepared:=item->'prepared'; object:=NULL;
   IF prepared<>'null'::JSONB THEN
    IF (prepared->>'source_identity')::BOOLEAN THEN SELECT object_id INTO STRICT object FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan AND ordinal=n; ELSE object:=gen_random_uuid(); END IF;
   END IF;
   entries:=entries||jsonb_build_array(jsonb_build_object('ordinal',n,'object_id',object));
  END LOOP;
  resolved:=jsonb_build_object('version',1,'scan_id',p_scan,'assignment_digest',p_assignment_digest,'grant_id',grant_value->'grant_id','request_digest',digest,'entries',entries);
  INSERT INTO internal.initial_preparation_output_manifests(scan_id,canonical_request,request_digest,canonical_resolved) VALUES(p_scan,p_text,digest,internal.initial_canonical(resolved));
  backend:=(saved.canonical_assignment::JSONB#>>'{preparation,backend_generation}')::UUID;
  FOR identity IN SELECT id FROM (SELECT object_id id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan UNION SELECT (e->>'object_id')::UUID FROM jsonb_array_elements(entries) e WHERE e->>'object_id' IS NOT NULL) v ORDER BY id LOOP
   PERFORM object_id FROM internal.initial_preparation_source_registry WHERE object_id=identity FOR UPDATE;
   IF NOT FOUND THEN INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation) VALUES(identity,p_scan,backend);
   ELSIF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE object_id=identity AND scan_id=p_scan AND backend_generation=backend AND NOT retired) THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  END LOOP;
  FOR item IN SELECT e FROM jsonb_array_elements(entries) e WHERE e->>'object_id' IS NOT NULL ORDER BY (e->>'object_id')::UUID LOOP
   INSERT INTO internal.initial_preparation_output_mapping(scan_id,ordinal,object_id) VALUES(p_scan,(item->>'ordinal')::INTEGER,(item->>'object_id')::UUID);
  END LOOP;
  RETURN jsonb_build_object('version',reply_version,'outcome','registered','request',value,'resolved',resolved);
 ELSE
  PERFORM internal.validate_initial_execution_outcome(p_scan,p_text);
  IF outcome IS NOT NULL THEN
   IF outcome IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  ELSE
   IF floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT>=(grant_value->>'outcome_deadline_ms')::BIGINT THEN RETURN internal.initial_preparation_held_reply(reply_version,'phase_expired'); END IF;
   INSERT INTO internal.initial_preparation_outcomes(scan_id,canonical_outcome,digest) VALUES(p_scan,p_text,internal.initial_saved_execution_outcome_digest(p_scan,p_text));
  END IF;
  RETURN jsonb_build_object('version',reply_version,'outcome','outcome_ready','result',p_text::JSONB,'digest',internal.initial_saved_execution_outcome_digest(p_scan,p_text));
 END IF;
END; $function$;



CREATE OR REPLACE FUNCTION public.finalize_initial_preparation(p_owner uuid, p_scan uuid, p_ip_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; recovered JSONB; input JSONB; assignment JSONB;
 quota RECORD; funding JSONB; configuration JSONB; admitted internal.initial_analysis_admissions;
 old_admission TEXT; old_funding TEXT; old_compared TEXT; encoded TEXT;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);

 IF EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  RETURN internal.recover_initial_admitted_media(p_owner,p_scan);
 END IF;
 recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);
 IF recovered IS NOT NULL THEN RETURN recovered; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;

 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='client_prepared_photo') THEN
  RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;
 IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.admit_initial_analysis(p_owner uuid, p_scan uuid, p_canonical_input text, p_submission_digest text, p_assets_digest text, p_ip_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE input JSONB; profile TEXT; saved internal.initial_analysis_admissions; submission internal.initial_analysis_submissions;
 scan_owner UUID; scan_retired BOOLEAN; scan_exists BOOLEAN; enabled BOOLEAN; assets TEXT; quota RECORD; attempt internal.identification_provider_attempts;
 funding JSONB; configuration JSONB; previous_context TEXT; images INTEGER; audios INTEGER; videos INTEGER; fallback BOOLEAN;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL OR p_submission_digest IS NULL OR p_submission_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 input:=internal.parse_initial_input(p_canonical_input);
 IF internal.initial_digest('input',p_canonical_input)<>p_submission_digest THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id,is_tombstoned INTO scan_owner,scan_retired FROM public.scans WHERE id=p_scan FOR UPDATE;
 scan_exists:=FOUND;
 IF scan_exists AND (scan_owner IS DISTINCT FROM p_owner OR scan_retired) THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
  RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='client_prepared_photo') THEN
  RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 IF FOUND THEN
  IF submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
  SELECT * INTO saved FROM internal.initial_analysis_admissions WHERE scan_id=p_scan;
  IF saved.binding_version<>1 THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;

  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  IF saved.canonical_input IS DISTINCT FROM p_canonical_input OR saved.submission_digest IS DISTINCT FROM p_submission_digest THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  IF submission.input_snapshot IS DISTINCT FROM input OR submission.route IS DISTINCT FROM input->>'route'
   OR submission.ordered_descriptions IS DISTINCT FROM input->'ordered_descriptions'
   OR saved.configuration_digest IS DISTINCT FROM internal.initial_digest('configuration',internal.initial_canonical(submission.configuration_snapshot))
   OR saved.funding_digest IS DISTINCT FROM internal.initial_digest('funding',internal.initial_canonical(submission.funding_snapshot))
   OR saved.descriptions_digest IS DISTINCT FROM internal.initial_digest('descriptions',internal.initial_canonical(submission.ordered_descriptions))
   OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations q WHERE q.id=saved.funding_binding_id AND q.user_id=p_owner
     AND q.request_id=p_scan AND q.original_analysis_id=p_scan AND q.operation='scan_identification' AND q.attempt_count=1)
   OR (scan_exists AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan AND owner_id=p_owner)) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  -- Do not consult current defaults, consent, gates, quota expiry or caller's
  -- current asset bundle. Future dispatch resolves this saved configuration only.
  RETURN internal.initial_admission_response(saved,submission.route,'replay');
 END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 SELECT initial_analysis_lifecycle_enabled,configuration_assets_digest INTO enabled,assets FROM internal.initial_analysis_rollout WHERE singleton FOR SHARE;
 IF enabled IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 IF assets IS NULL OR p_assets_digest IS DISTINCT FROM assets THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 IF input->'experiment'<>'null'::JSONB OR p_scan::TEXT ~ '^ac0[ab]0001-[0-9a-f]{4}-8' THEN RAISE EXCEPTION 'initial_analysis_experiment_unavailable' USING ERRCODE='55000'; END IF;
 profile:=internal.initial_input_semantics(input);
 SELECT count(*) FILTER(WHERE v->>'kind'='image'),count(*) FILTER(WHERE v->>'kind'='audio'),count(*) FILTER(WHERE v->>'kind'='video')
 INTO images,audios,videos FROM jsonb_array_elements(input->'media') AS m(v);
 fallback:=videos=0 AND ((images+audios=1 AND jsonb_array_length(input->'ordered_descriptions')<=1)
   OR (images+audios=0 AND jsonb_array_length(input->'ordered_descriptions')=1));
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);
 previous_context:=current_setting('merian.initial_analysis_admission',TRUE);
 PERFORM set_config('merian.initial_analysis_admission',p_owner::TEXT||':'||p_scan::TEXT,TRUE);
 SELECT * INTO STRICT quota FROM public.reserve_identification_quota(p_owner,'scan_identification',p_scan,p_ip_hash,p_scan,fallback,
  (input#>>'{admission,client_protocol}')::INTEGER,FALSE,profile,input#>>'{admission,expected_processor_permission}',(input#>>'{admission,identification_protocol}')::INTEGER);
 PERFORM set_config('merian.initial_analysis_admission',COALESCE(previous_context,''),TRUE);
 IF quota.request_id IS DISTINCT FROM p_scan OR quota.original_analysis_id IS DISTINCT FROM p_scan OR quota.is_replay
  OR quota.attempt_count<>1 OR quota.reservation_state<>'reserved' OR quota.input_profile IS DISTINCT FROM profile THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT attempt FROM internal.identification_provider_attempts WHERE reservation_id=quota.reservation_id AND attempt_count=1;
 funding:=jsonb_build_object('version',1,'original',jsonb_build_object(
  'reservation_id',quota.reservation_id,'request_id',quota.request_id,'original_analysis_id',quota.original_analysis_id,
  'operation','scan_identification','attempt_count',quota.attempt_count,'effective_plan',quota.effective_plan,
  'effective_tier',quota.effective_tier,'entitlement_version',quota.entitlement_version,'policy_version',quota.policy_version,
  'model',quota.model,'complimentary_client_scan_id',quota.complimentary_client_scan_id,'flash_fallback_used',quota.flash_fallback_used));
 configuration:=jsonb_build_object('version',1,'asset_manifest_digest',assets,'retention_owner','initial_engine_release_archive',
  'resolver_id','git_blob_sha256_v1','assignment',jsonb_build_object('operation',attempt.operation,'effective_plan',attempt.effective_plan,
  'model',attempt.model,'policy_version',attempt.policy_version,'provider',attempt.provider,'binding',attempt.binding,
  'processor_permission',attempt.processor_permission,'input_profile',attempt.input_profile,'provider_model',attempt.provider_model,
  'minimum_client_protocol',attempt.minimum_client_protocol,'accepted_client_protocol',attempt.accepted_client_protocol,
  'minimum_identification_protocol',attempt.minimum_identification_protocol,'accepted_identification_protocol',attempt.accepted_identification_protocol),
  'model',quota.model,'effective_tier',quota.effective_tier,'experiment',NULL);
 INSERT INTO internal.initial_analysis_submissions(scan_id,owner_id,route,input_schema_version,input_snapshot,ordered_descriptions,configuration_snapshot,funding_snapshot)
 VALUES(p_scan,p_owner,input->>'route',1,input,input->'ordered_descriptions',configuration,funding);
 INSERT INTO internal.initial_analysis_admissions(scan_id,owner_id,canonical_input,submission_digest,configuration_digest,funding_digest,descriptions_digest,funding_binding_id,assets_digest)
 VALUES(p_scan,p_owner,p_canonical_input,p_submission_digest,internal.initial_digest('configuration',internal.initial_canonical(configuration)),
  internal.initial_digest('funding',internal.initial_canonical(funding)),internal.initial_digest('descriptions',internal.initial_canonical(input->'ordered_descriptions')),quota.reservation_id,assets)
 RETURNING * INTO saved;
 RETURN internal.initial_admission_response(saved,input->>'route','admitted');
 -- No catch-and-return around reservation: any later validation/storage error
 -- rolls back the quota, complimentary hold, fence, input and binding together.
END;
$function$;

CREATE OR REPLACE FUNCTION public.allocate_initial_analysis_media(p_owner uuid, p_scan uuid, p_submission_digest text, p_backend_generation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE submission internal.initial_analysis_submissions; saved internal.initial_analysis_media_cohorts;
 input JSONB; source_role JSONB; prepared_role JSONB; items JSONB:='[]'::JSONB; binding JSONB;
 source_object UUID; prepared_object UUID; position INTEGER:=0; objects INTEGER:=0; bytes BIGINT:=0; deadline BIGINT;
BEGIN
 PERFORM internal.require_service_role();
 IF p_backend_generation IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 submission:=internal.lock_initial_media_scope(p_owner,p_scan,p_submission_digest);
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='client_prepared_photo') THEN
  RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.binding->>'backend_generation' IS DISTINCT FROM p_backend_generation::TEXT THEN
   RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  RETURN internal.initial_media_response(p_scan,saved.binding,'replay');
 END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR NOT internal.initial_media_abandonable(p_scan)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled AND media_backend_generation=p_backend_generation) THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.initial_analysis_media_allocation_fences(scan_id,state) VALUES(p_scan,'allocated');
 deadline:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT+300000;
 FOR input IN SELECT * FROM jsonb_array_elements(submission.input_snapshot->'media') LOOP
  source_object:=gen_random_uuid();
  source_role:=jsonb_build_object('object_id',source_object,'content_type',input->'source_content_type','byte_count',input->'source_byte_count','sha256',input->'source_sha256');
  INSERT INTO internal.initial_analysis_media_registry(object_id,scan_id,backend_generation) VALUES(source_object,p_scan,p_backend_generation);
  objects:=objects+1; bytes:=bytes+(input->>'source_byte_count')::BIGINT;
  prepared_role:=NULL;
  IF input->>'kind'<>'video' THEN
   IF input->'content_type'=input->'source_content_type' AND input->'byte_count'=input->'source_byte_count' AND input->'sha256'=input->'source_sha256' THEN
    prepared_object:=source_object;
   ELSE
    prepared_object:=gen_random_uuid();
    INSERT INTO internal.initial_analysis_media_registry(object_id,scan_id,backend_generation) VALUES(prepared_object,p_scan,p_backend_generation);
    objects:=objects+1; bytes:=bytes+(input->>'byte_count')::BIGINT;
   END IF;
   prepared_role:=jsonb_build_object('object_id',prepared_object,'content_type',input->'content_type','byte_count',input->'byte_count','sha256',input->'sha256');
  END IF;
  items:=items||jsonb_build_array(jsonb_build_object('index',position,'input',input,'source',source_role,'prepared',prepared_role));
  position:=position+1;
 END LOOP;
 IF position>8 OR objects>10 OR bytes>28625792 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 binding:=jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,'submission_digest',p_submission_digest,
  'backend_generation',p_backend_generation,'expires_at',deadline,'items',items);
 binding:=binding||jsonb_build_object('manifest_digest',encode(extensions.digest(convert_to(E'merian.initial-analysis.media-allocation.v1\n'||internal.initial_canonical(binding),'UTF8'),'sha256'),'hex'));
 INSERT INTO internal.initial_analysis_media_cohorts(scan_id,owner_id,binding) VALUES(p_scan,p_owner,binding);
 RETURN internal.initial_media_response(p_scan,binding,'allocated');
END;
$function$;

CREATE OR REPLACE FUNCTION internal.initial_media_verification_action(p_action text, p_owner uuid, p_scan uuid, p_digest text, p_manifest text, p_token uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE binding JSONB; receipt JSONB; claim internal.initial_analysis_media_preparations;
 issued BIGINT; deadline BIGINT; object internal.initial_analysis_media_registry; expected_count INTEGER;
BEGIN
 IF p_action NOT IN ('claim','settle','read') OR p_action IS NULL OR (p_action='settle' AND p_token IS NULL) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 binding:=internal.lock_initial_media_binding(p_owner,p_scan,p_digest,p_manifest);
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='client_prepared_photo') THEN
  RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;
 IF binding IS NULL THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 SELECT * INTO claim FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
 SELECT v.receipt INTO receipt FROM internal.initial_analysis_media_verifications v WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN RETURN jsonb_build_object('version',1,'outcome','replay','receipt',receipt); END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan AND state='retired') THEN
  RETURN jsonb_build_object('version',1,'outcome','held','reason','retired'); END IF;
 IF p_action='read' THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 IF NOT internal.initial_media_pending(p_scan) THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','in_use'); END IF;
 -- All registry locks follow the outer lifecycle and private locks. Cleanup
 -- touches retired rows only; it never takes an outer lock in reverse order.
 expected_count:=0;
 FOR object IN SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE LOOP
  IF object.retired THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','retired'); END IF;
  IF object.backend_generation::TEXT IS DISTINCT FROM binding->>'backend_generation'
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(binding->'items') item
    CROSS JOIN LATERAL (VALUES(item->'source'),(item->'prepared')) AS roles(role) WHERE role->>'object_id'=object.object_id::TEXT) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  expected_count:=expected_count+1;
 END LOOP;
 IF expected_count<>(SELECT count(DISTINCT role->>'object_id') FROM jsonb_array_elements(binding->'items') item
  CROSS JOIN LATERAL (VALUES(item->'source'),(item->'prepared')) AS roles(role) WHERE role<>'null'::JSONB) THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 IF p_action='claim' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN
   RETURN jsonb_build_object('version',1,'outcome','held','reason','disabled'); END IF;
  issued:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  deadline:=least(issued+60000,(binding->>'expires_at')::BIGINT);
  IF deadline<=issued THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','expired'); END IF;
  IF claim.expires_at>issued THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','busy'); END IF;
  INSERT INTO internal.initial_analysis_media_preparations(scan_id,owner_id,token,issued_at,expires_at)
   VALUES(p_scan,p_owner,gen_random_uuid(),issued,deadline)
   ON CONFLICT(scan_id) DO UPDATE SET token=EXCLUDED.token,issued_at=EXCLUDED.issued_at,expires_at=EXCLUDED.expires_at RETURNING * INTO claim;
  RETURN jsonb_build_object('version',1,'outcome','claimed','binding',binding,'claim',jsonb_build_object('token',claim.token,'issued_at',claim.issued_at,'expires_at',claim.expires_at));
 END IF;
 IF claim.token IS DISTINCT FROM p_token OR claim.expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','stale'); END IF;
 -- A token alone is not durable proof of verification before expiry. Only a
 -- current claim inserts; an existing exact receipt already returned above.
 receipt:=jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,'submission_digest',p_digest,
  'manifest_digest',p_manifest,'backend_generation',binding->'backend_generation',
  'verified_at',floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT);
 INSERT INTO internal.initial_analysis_media_verifications(scan_id,owner_id,receipt) VALUES(p_scan,p_owner,receipt);
 RETURN jsonb_build_object('version',1,'outcome','verified','receipt',receipt);
END;
$function$;

CREATE OR REPLACE FUNCTION internal.guard_initial_lifecycle_fence()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id AND canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo')) THEN
   PERFORM internal.lock_initial_preparation_scope((SELECT owner_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id),NEW.scan_id);
   PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
  END IF;

  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id AND canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo'))
   AND NOT internal.can_cancel_initial_preparation((SELECT owner_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id),NEW.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023'; END IF;

  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=NEW.scan_id OR request_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=NEW.scan_id) THEN RETURN NEW; END IF;

  IF NEW.state='cancelled_unknown' OR (NEW.state='pending_pre_dispatch' AND EXISTS(
   SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=NEW.scan_id)) THEN RETURN NEW; END IF;
 ELSIF TG_OP='UPDATE' THEN
  IF OLD.state='pending_pre_dispatch' AND NEW.state='cancelled_pre_dispatch'
   AND internal.initial_admitted_settlement_blocked(OLD.scan_id)
   AND NOT internal.initial_cancellation_lifecycle_authorized(to_jsonb(OLD),to_jsonb(NEW)) THEN
   RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023';
  END IF;

  IF NEW.scan_id=OLD.scan_id AND
   ((OLD.state='pending_pre_dispatch' AND NEW.state IN ('cancelled_pre_dispatch','cancelled_unknown'))
    OR (OLD.state='dispatch_authorized' AND NEW.state='cancelled_dispatched')) THEN RETURN NEW; END IF;
 END IF;
 -- No callable or direct initial transition to dispatch_authorized exists.
 RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023';
END;
$function$;

-- Extend the existing private-erasure inventory and denial boundaries. These
-- installation-time patches require the exact predecessor anchor; they do not
-- expose dynamic SQL or create a second cancellation owner.
DO $cpm_c1_catalogs$
DECLARE definition TEXT; anchor TEXT; signature TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.initial_cancellation_private_catalog()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' (''internal.initial_preparation_source_mapping'',''intent'',8),';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'CPM private catalog drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n'||' (''internal.initial_cpm_photo_role_mapping'',''intent'',6),');
 SELECT pg_get_functiondef('internal.initial_cancellation_seal_catalog()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='        (''internal.initial_preparation_source_mapping''),';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'CPM seal catalog drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n'||'        (''internal.initial_cpm_photo_role_mapping''),');
 -- Legacy mappings keep their ordinal order. CPM has photo_ordinal and role,
 -- whose exact pair is unique; NULL legacy ordinals cannot establish its order.
 SELECT pg_get_functiondef('internal.capture_initial_cancellation_private_images(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$ORDER BY (to_jsonb(t)->>''ordinal'')::INTEGER$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'CPM image ordering drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$ordering$, (to_jsonb(t)->>''photo_ordinal'')::INTEGER, (to_jsonb(t)->>''role'') COLLATE "C"$ordering$);
 FOREACH signature IN ARRAY ARRAY['internal.capture_initial_admitted_cancellation_prestate(uuid,uuid)',
  'internal.lock_initial_merge_target_terminal(uuid,uuid)'] LOOP
  SELECT pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
  anchor:='    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'CPM cancellation mapping lock drift'; END IF;
  EXECUTE replace(definition,anchor,anchor||E'\n'||'    PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;');
 END LOOP;
END; $cpm_c1_catalogs$;
CREATE TRIGGER a0_initial_cancellation_private BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_role_mapping
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_private_member();
CREATE TRIGGER a0_initial_cancellation_private_truncate BEFORE TRUNCATE ON internal.initial_cpm_photo_role_mapping
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_private_member();
CREATE TRIGGER z9_initial_cancellation_private_after AFTER DELETE ON internal.initial_cpm_photo_role_mapping
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_private_member();
CREATE TRIGGER a00_initial_cancellation_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_cpm_photo_role_mapping
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal();
CREATE TRIGGER a00_initial_admission_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_cpm_photo_role_mapping
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_seal();
CREATE TRIGGER a000_initial_media_handoff_statement BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_cpm_photo_role_mapping
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_media_handoff_statement();
CREATE TRIGGER z999_initial_media_handoff_statement AFTER INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_role_mapping
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_media_handoff_statement();
CREATE TRIGGER a000_initial_media_handoff_row BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_role_mapping
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_domain_row();
CREATE TRIGGER z999_initial_media_handoff_row AFTER INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_role_mapping
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_domain_row();

-- The FK emits a child DELETE statement even for an empty mapping. Preserve
-- legacy handoff by accounting for that frame, while refusing all CPM rows.
DO $cpm_legacy_handoff$
DECLARE item RECORD; definition TEXT;
BEGIN
 FOR item IN SELECT * FROM (VALUES
 ('internal.assert_initial_media_handoff_cascade_catalog()',$needle$THEN 5 ELSE 1 END$needle$,$replacement$THEN 6 ELSE 1 END$replacement$,1),
 ('internal.assert_initial_media_handoff_cascade_catalog()',$needle$CASE WHEN expected=5 THEN ARRAY[$needle$,$replacement$CASE WHEN expected=6 THEN ARRAY[$replacement$,1),
 ('internal.assert_initial_media_handoff_cascade_catalog()',$needle$'internal.initial_preparation_source_mapping','internal.initial_preparation_source_verifications',$needle$,$replacement$'internal.initial_preparation_source_mapping','internal.initial_cpm_photo_role_mapping','internal.initial_preparation_source_verifications',$replacement$,1),
 ('internal.initial_media_handoff_snapshot_catalog()',$needle$WHEN name IN ('initial_preparation_source_registry','initial_analysis_media_registry') THEN 't.object_id'$needle$,$replacement$WHEN name='initial_cpm_photo_role_mapping' THEN 't.photo_ordinal,t.role COLLATE "C"'
            WHEN name IN ('initial_preparation_source_registry','initial_analysis_media_registry') THEN 't.object_id'$replacement$,1),
 ('internal.initial_media_handoff_snapshot_catalog()',$needle$('initial_analysis_preparation_intents',1),('initial_preparation_source_mapping',8),$needle$,$replacement$('initial_analysis_preparation_intents',1),('initial_preparation_source_mapping',8),
        ('initial_cpm_photo_role_mapping',6),$replacement$,1),
 ('internal.lock_initial_media_handoff_members(uuid)',$needle$    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;$needle$,$replacement$    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;$replacement$,1),
 ('internal.plan_initial_media_handoff_mutation(uuid,uuid,text,text,uuid,uuid,text)',$needle$FOREACH member IN ARRAY ARRAY['initial_analysis_preparation_intents','initial_preparation_source_mapping',$needle$,$replacement$FOREACH member IN ARRAY ARRAY['initial_analysis_preparation_intents','initial_preparation_source_mapping',
            'initial_cpm_photo_role_mapping',$replacement$,2),
 ('internal.plan_initial_media_handoff_mutation(uuid,uuid,text,text,uuid,uuid,text)',$needle$snapshot:=internal.capture_initial_media_handoff_snapshot(p_owner,p_scan);$needle$,$replacement$snapshot:=internal.capture_initial_media_handoff_snapshot(p_owner,p_scan);
    -- This compatibility frame never authorizes CPM handoff. Preserve existing
    -- event/byte/frame limits; the new child must be empty for legacy work.
    IF snapshot->'internal.initial_cpm_photo_role_mapping' IS DISTINCT FROM '[]'::JSONB THEN
        RAISE EXCEPTION 'initial_analysis_cpm_io_unavailable' USING ERRCODE='55000'; END IF;$replacement$,1),
 ('internal.initial_media_handoff_row_image(text,jsonb)',$needle$    ELSIF p_relation IN ('internal.initial_preparation_source_mapping','internal.initial_preparation_output_mapping') THEN$needle$,$replacement$    ELSIF p_relation='internal.initial_cpm_photo_role_mapping' THEN
        predicate:='t.scan_id=($1->>''scan_id'')::UUID AND t.photo_ordinal=($1->>''photo_ordinal'')::INTEGER AND t.role=($1->>''role'')';
    ELSIF p_relation IN ('internal.initial_preparation_source_mapping','internal.initial_preparation_output_mapping') THEN$replacement$,1)
 ) AS patches(signature,anchor,replacement,occurrences) LOOP
  SELECT pg_get_functiondef(item.signature::REGPROCEDURE) INTO STRICT definition;
  IF (length(definition)-length(replace(definition,item.anchor,'')))/length(item.anchor)<>item.occurrences THEN
   RAISE EXCEPTION 'CPM legacy handoff source drift: %',item.signature; END IF;
  EXECUTE replace(definition,item.anchor,item.replacement);
 END LOOP;
END; $cpm_legacy_handoff$;

-- No installation, provider call, write capability or activation is seeded.
RESET statement_timeout;
RESET lock_timeout;
