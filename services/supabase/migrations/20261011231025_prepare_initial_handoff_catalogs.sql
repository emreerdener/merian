SET lock_timeout='5s';
SET statement_timeout='2min';

-- Empty trusted-owner catalogs; no runtime installer, seed or authority adoption.
CREATE FUNCTION internal.initial_handoff_catalog_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$ SELECT $json${"destination_backend":{"type":"object","properties":{"generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"provider":{"type":"string","max_bytes":128,"enum":["r2"]},"direct_endpoint":{"type":"string","max_bytes":256,"pattern":"^https://[0-9a-f]{32}\\.r2\\.cloudflarestorage\\.com$"},"private_bucket":{"type":"string","max_bytes":63,"pattern":"^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$"},"namespace":{"type":"string","max_bytes":128,"enum":["initial-analysis/v1"]},"credential_profile":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"}}},"installation":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"profile_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"copy_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verification_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"preparation_profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"qualification_harness_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"reviewed_source_revision":{"type":"string","max_bytes":40,"pattern":"^[0-9a-f]{40}$"},"evidence_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"installer_protocol":{"type":"string","max_bytes":128,"enum":["reviewed_database_owner_install_v1"]}}}}$json$::JSONB; $schema$;
CREATE FUNCTION internal.initial_handoff_catalog_digest(p_domain TEXT,p_text TEXT) RETURNS TEXT LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB;
BEGIN
 IF p_domain IS NULL OR p_domain NOT IN ('destination_backend','installation') OR p_text IS NULL OR octet_length(p_text)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.handoff.'||p_domain||E'.v1\n'||p_text,'UTF8'),'sha256'),'hex');
END; $$;
CREATE FUNCTION internal.parse_initial_handoff_catalog(p_kind TEXT,p_text TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB; shape JSONB;
BEGIN
 shape:=internal.initial_handoff_catalog_schema()->p_kind;
 IF shape IS NULL OR p_text IS NULL OR octet_length(p_text)>16384 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text OR NOT internal.initial_schema_matches(value,shape) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN value;
END; $$;
CREATE FUNCTION internal.initial_handoff_pair_matches(p_rule JSONB,p_pair JSONB) RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT p_pair->>'kind'=CASE WHEN p_rule->>'role' IN ('recording','video_audio') THEN 'audio' WHEN p_rule->>'role'='raw_video' THEN 'video' ELSE 'image' END
 AND (p_rule->'source_types') ? (p_pair->>'source_content_type')
 AND (p_rule->>'role' NOT IN ('recording','video_audio') OR p_rule->>'target_sample_rate'='16000');
$$;
-- One instance of each PROFILE rule at its declared ceilings. Conservative
-- association template only, not an actual runtime cohort or byte-validity proof.
CREATE FUNCTION internal.assert_initial_handoff_catalog_envelope(p_preparation TEXT,p_handoff TEXT,p_protocol TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE spec JSONB:=internal.parse_initial_media_profile(p_preparation)->'spec'; h JSONB:=internal.parse_initial_handoff_profile(p_handoff,p_protocol); rules JSONB:=spec->'rules'; pairs JSONB:=h#>'{cohort_limits,content_type_pairs}'; r JSONB; objects BIGINT:=0; bytes BIGINT:=0; source_total BIGINT:=0; output_total BIGINT:=0; cpu_total BIGINT:=0; heap_total BIGINT:=0; wall_total BIGINT:=0;
BEGIN
 IF jsonb_array_length(rules)>(spec->>'max_sources')::INTEGER OR jsonb_array_length(rules)>(h#>>'{cohort_limits,max_ordinals}')::INTEGER
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(rules) rule WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(pairs) pair WHERE internal.initial_handoff_pair_matches(rule,pair)))
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(pairs) pair WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rules) rule WHERE internal.initial_handoff_pair_matches(rule,pair))) THEN
  RAISE EXCEPTION 'initial_analysis_handoff_catalog_envelope_unsupported' USING ERRCODE='55000';
 END IF;
 FOR r IN SELECT * FROM jsonb_array_elements(rules) LOOP
  source_total:=source_total+(r#>>'{limits,source_bytes}')::BIGINT; output_total:=output_total+(r#>>'{limits,output_bytes}')::BIGINT;
  cpu_total:=cpu_total+(r#>>'{limits,cpu_ms}')::BIGINT; heap_total:=heap_total+(r#>>'{limits,heap_bytes}')::BIGINT; wall_total:=wall_total+(r#>>'{limits,wall_ms}')::BIGINT;
  objects:=objects+CASE WHEN r->>'role' IN ('recording','video_audio') THEN 2 ELSE 1 END;
  bytes:=bytes+CASE WHEN r->>'role' IN ('recording','video_audio') THEN (r#>>'{limits,source_bytes}')::BIGINT+(r#>>'{limits,output_bytes}')::BIGINT WHEN r->>'role'='raw_video' THEN (r#>>'{limits,source_bytes}')::BIGINT ELSE greatest((r#>>'{limits,source_bytes}')::BIGINT,(r#>>'{limits,output_bytes}')::BIGINT) END;
 END LOOP;
 IF source_total>(spec#>>'{limits,source_bytes}')::BIGINT OR output_total>(spec#>>'{limits,output_bytes}')::BIGINT OR cpu_total>(spec#>>'{limits,cpu_ms}')::BIGINT OR heap_total>(spec#>>'{limits,heap_bytes}')::BIGINT OR wall_total>(spec#>>'{limits,wall_ms}')::BIGINT
 OR objects>(h#>>'{cohort_limits,max_unique_objects}')::BIGINT OR bytes>(h#>>'{cohort_limits,max_unique_bytes}')::BIGINT OR 45000+wall_total+(h->>'total_ms')::BIGINT>=300000 THEN
  RAISE EXCEPTION 'initial_analysis_handoff_catalog_envelope_unsupported' USING ERRCODE='55000';
 END IF;
END; $$;
CREATE TABLE internal.initial_preparation_handoff_protocol_artifacts(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 canonical_artifact TEXT NOT NULL CHECK(internal.parse_initial_handoff_shape('protocol_artifact',canonical_artifact) IS NOT NULL),
 CHECK(digest=internal.initial_handoff_digest('protocol_artifact',canonical_artifact))
);
CREATE TABLE internal.initial_preparation_handoff_profiles(
 generation UUID PRIMARY KEY,
 digest TEXT NOT NULL UNIQUE CHECK(digest ~ '^[0-9a-f]{64}$'),
 canonical_profile TEXT NOT NULL,
 protocol_artifact_digest TEXT NOT NULL REFERENCES internal.initial_preparation_handoff_protocol_artifacts(digest),
 source_backend_generation UUID NOT NULL,
 source_backend_config_digest TEXT NOT NULL,
 destination_backend_generation UUID NOT NULL REFERENCES internal.initial_analysis_media_backends(generation),
 destination_backend_config_digest TEXT NOT NULL CHECK(destination_backend_config_digest ~ '^[0-9a-f]{64}$'),
 UNIQUE(generation,digest),
 FOREIGN KEY(source_backend_generation,source_backend_config_digest) REFERENCES internal.initial_preparation_source_backends(generation,configuration_digest),
 CHECK(digest=internal.initial_handoff_digest('profile',canonical_profile))
);
CREATE INDEX initial_handoff_profile_protocol ON internal.initial_preparation_handoff_profiles(protocol_artifact_digest);
CREATE INDEX initial_handoff_profile_source ON internal.initial_preparation_handoff_profiles(source_backend_generation,source_backend_config_digest);
CREATE INDEX initial_handoff_profile_destination ON internal.initial_preparation_handoff_profiles(destination_backend_generation);
CREATE TABLE internal.initial_preparation_handoff_installations(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 canonical_installation TEXT NOT NULL CHECK(internal.parse_initial_handoff_catalog('installation',canonical_installation) IS NOT NULL),
 profile_generation UUID NOT NULL,
 profile_digest TEXT NOT NULL,
 preparation_profile_digest TEXT NOT NULL REFERENCES internal.initial_preparation_profiles(digest),
 source_backend_generation UUID NOT NULL REFERENCES internal.initial_preparation_source_backends(generation),
 UNIQUE(digest,preparation_profile_digest,source_backend_generation),
 FOREIGN KEY(profile_generation,profile_digest) REFERENCES internal.initial_preparation_handoff_profiles(generation,digest),
 CHECK(digest=internal.initial_handoff_catalog_digest('installation',canonical_installation))
);
CREATE INDEX initial_handoff_install_profile ON internal.initial_preparation_handoff_installations(profile_generation,profile_digest);
CREATE INDEX initial_handoff_install_preparation ON internal.initial_preparation_handoff_installations(preparation_profile_digest);
CREATE INDEX initial_handoff_install_source ON internal.initial_preparation_handoff_installations(source_backend_generation);
CREATE TABLE internal.initial_preparation_handoff_eligibility(
 installation_digest TEXT PRIMARY KEY REFERENCES internal.initial_preparation_handoff_installations(digest),
 state TEXT NOT NULL CHECK(state IN ('eligible','revoked'))
);
CREATE FUNCTION internal.guard_initial_handoff_profile_insert() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$
DECLARE artifact TEXT; value JSONB; destination JSONB;
BEGIN
 SELECT canonical_artifact INTO artifact FROM internal.initial_preparation_handoff_protocol_artifacts WHERE digest=NEW.protocol_artifact_digest;
 value:=internal.parse_initial_handoff_profile(NEW.canonical_profile,artifact);
 IF value->>'generation' IS DISTINCT FROM NEW.generation::TEXT OR value->>'protocol_artifact_digest' IS DISTINCT FROM NEW.protocol_artifact_digest
 OR value->>'source_backend_generation' IS DISTINCT FROM NEW.source_backend_generation::TEXT OR value->>'source_backend_config_digest' IS DISTINCT FROM NEW.source_backend_config_digest
 OR value->>'destination_backend_generation' IS DISTINCT FROM NEW.destination_backend_generation::TEXT OR value->>'destination_backend_config_digest' IS DISTINCT FROM NEW.destination_backend_config_digest THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT jsonb_build_object('generation',b.generation,'provider',b.provider,'direct_endpoint',b.direct_endpoint,'private_bucket',b.private_bucket,'namespace',b.namespace,'credential_profile',b.credential_profile) INTO destination FROM internal.initial_analysis_media_backends b WHERE generation=NEW.destination_backend_generation;
 PERFORM internal.parse_initial_handoff_catalog('destination_backend',internal.initial_canonical(destination));
 IF internal.initial_handoff_catalog_digest('destination_backend',internal.initial_canonical(destination)) IS DISTINCT FROM NEW.destination_backend_config_digest THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION internal.guard_initial_handoff_installation_insert() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$
DECLARE value JSONB:=internal.parse_initial_handoff_catalog('installation',NEW.canonical_installation); profile internal.initial_preparation_handoff_profiles; artifact TEXT; preparation TEXT; h JSONB;
BEGIN
 SELECT * INTO profile FROM internal.initial_preparation_handoff_profiles WHERE generation=NEW.profile_generation AND digest=NEW.profile_digest;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 h:=profile.canonical_profile::JSONB;
 IF value->>'profile_generation' IS DISTINCT FROM NEW.profile_generation::TEXT OR value->>'profile_digest' IS DISTINCT FROM NEW.profile_digest
 OR value->>'preparation_profile_digest' IS DISTINCT FROM NEW.preparation_profile_digest OR value->>'source_backend_generation' IS DISTINCT FROM NEW.source_backend_generation::TEXT
 OR NEW.source_backend_generation IS DISTINCT FROM profile.source_backend_generation
 OR value->>'destination_backend_generation' IS DISTINCT FROM profile.destination_backend_generation::TEXT
 OR value->>'protocol_artifact_digest' IS DISTINCT FROM profile.protocol_artifact_digest
 OR value->>'copy_adapter_digest' IS DISTINCT FROM h->>'copy_adapter_digest' OR value->>'verification_adapter_digest' IS DISTINCT FROM h->>'verification_adapter_digest' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT canonical_artifact INTO artifact FROM internal.initial_preparation_handoff_protocol_artifacts WHERE digest=profile.protocol_artifact_digest;
 SELECT canonical_profile INTO preparation FROM internal.initial_preparation_profiles WHERE digest=NEW.preparation_profile_digest;
 PERFORM internal.assert_initial_handoff_catalog_envelope(preparation,profile.canonical_profile,artifact);
 RETURN NEW;
END; $$;
CREATE TRIGGER validate_initial_handoff_profile BEFORE INSERT ON internal.initial_preparation_handoff_profiles FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_handoff_profile_insert();
CREATE TRIGGER validate_initial_handoff_installation BEFORE INSERT ON internal.initial_preparation_handoff_installations FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_handoff_installation_insert();
ALTER TABLE internal.initial_preparation_selections ADD COLUMN handoff_installation_digest TEXT;
ALTER TABLE internal.initial_preparation_selections ADD CONSTRAINT initial_preparation_selection_handoff FOREIGN KEY(handoff_installation_digest,profile_digest,backend_generation) REFERENCES internal.initial_preparation_handoff_installations(digest,preparation_profile_digest,source_backend_generation);
CREATE INDEX initial_preparation_selection_handoff ON internal.initial_preparation_selections(handoff_installation_digest,profile_digest,backend_generation);
-- Existing whole-row permanent-mutation trigger forbids NULL enrichment and
-- DELETE/reinsert. No default/backfill, parallel selector or resolver adoption.
DO $catalogs$
DECLARE name TEXT;
BEGIN
 FOREACH name IN ARRAY ARRAY['initial_preparation_handoff_protocol_artifacts','initial_preparation_handoff_profiles','initial_preparation_handoff_installations'] LOOP
  EXECUTE format('CREATE TRIGGER guard_%I BEFORE UPDATE OR DELETE ON internal.%I FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation()',name,name);
 END LOOP;
 CREATE TRIGGER guard_initial_handoff_eligibility BEFORE UPDATE OR DELETE ON internal.initial_preparation_handoff_eligibility FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_eligibility();
 FOREACH name IN ARRAY ARRAY['initial_preparation_handoff_protocol_artifacts','initial_preparation_handoff_profiles','initial_preparation_handoff_installations','initial_preparation_handoff_eligibility'] LOOP
  EXECUTE format('ALTER TABLE internal.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON internal.%I FROM PUBLIC,anon,authenticated,service_role',name);
 END LOOP;
END; $catalogs$;
REVOKE ALL ON FUNCTION internal.initial_handoff_catalog_schema(),internal.initial_handoff_catalog_digest(TEXT,TEXT),internal.parse_initial_handoff_catalog(TEXT,TEXT),internal.initial_handoff_pair_matches(JSONB,JSONB),internal.assert_initial_handoff_catalog_envelope(TEXT,TEXT,TEXT),internal.guard_initial_handoff_profile_insert(),internal.guard_initial_handoff_installation_insert() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.initial_preparation_handoff_installations IS 'Immutable reviewed database-owner installation provenance. No runtime installer or seeded qualification. Declarations do not attest actual adapter bytes, cohort execution, or external storage qualification.';
RESET lock_timeout;
RESET statement_timeout;
