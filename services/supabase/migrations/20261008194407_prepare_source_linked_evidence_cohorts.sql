SET lock_timeout='5s';
SET statement_timeout='2min';

-- Additive preparation only. Existing RPCs omit this column and retain their
-- NULL legacy linkage forever; no backfill or new upload authority is installed.
ALTER TABLE internal.observation_evidence_upload_cohorts
    ADD COLUMN binding_analysis_id UUID REFERENCES internal.observation_analysis_source_bindings(analysis_id) ON DELETE CASCADE,
    ADD CONSTRAINT observation_photo_cohort_binding_identity CHECK(binding_analysis_id IS NULL OR binding_analysis_id=analysis_id);
ALTER TABLE internal.observation_audio_evidence_upload_cohorts
    ADD COLUMN binding_analysis_id UUID REFERENCES internal.observation_analysis_source_bindings(analysis_id) ON DELETE CASCADE,
    ADD CONSTRAINT observation_audio_cohort_binding_identity CHECK(binding_analysis_id IS NULL OR binding_analysis_id=analysis_id);
CREATE INDEX observation_photo_cohort_binding ON internal.observation_evidence_upload_cohorts(binding_analysis_id) WHERE binding_analysis_id IS NOT NULL;
CREATE INDEX observation_audio_cohort_binding ON internal.observation_audio_evidence_upload_cohorts(binding_analysis_id) WHERE binding_analysis_id IS NOT NULL;

CREATE FUNCTION internal.observation_source_cohort_items(p_input JSONB,p_schema INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE items JSONB;
BEGIN
    -- Reuse the full immutable-input validator, including limits and media IDs.
    PERFORM internal.observation_source_fingerprint(p_input);
    IF p_schema IS NULL OR p_schema NOT IN (2,3)
        OR p_input->'schema_version' IS DISTINCT FROM to_jsonb(p_schema) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT jsonb_agg(item-'kind' ORDER BY ordinal) INTO items
        FROM jsonb_array_elements(p_input->'evidence_manifest'->'items') WITH ORDINALITY AS media(item,ordinal)
        WHERE item->>'kind' IN ('image','audio');
    IF items IS NULL THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    RETURN items;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_source_cohort_items(JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.validate_observation_source_cohort()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; expected JSONB; actual JSONB; version INTEGER;
BEGIN
    IF NEW.binding_analysis_id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.binding_analysis_id;
    IF NOT FOUND OR binding.analysis_id IS DISTINCT FROM NEW.analysis_id
        OR binding.owner_id IS DISTINCT FROM NEW.owner_id
        OR binding.observation_id IS DISTINCT FROM NEW.observation_id THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF TG_TABLE_NAME='observation_evidence_upload_cohorts' THEN
        version:=2; actual:=NEW.items;
    ELSE
        version:=3;
        actual:=jsonb_build_array(jsonb_build_object('media_id',NEW.media_id,'content_type',NEW.content_type,
            'byte_count',NEW.byte_count,'sha256',NEW.sha256));
    END IF;
    expected:=internal.observation_source_cohort_items(binding.input_snapshot,version);
    IF expected IS DISTINCT FROM actual THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- No late locks here. The future linked writer must first validate live
    -- occupancy under owner→parent→source→child locks. This is a storage backstop.
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.validate_observation_source_cohort() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER validate_observation_source_cohort BEFORE INSERT ON internal.observation_evidence_upload_cohorts
    FOR EACH ROW EXECUTE FUNCTION internal.validate_observation_source_cohort();
CREATE TRIGGER validate_observation_source_cohort BEFORE INSERT ON internal.observation_audio_evidence_upload_cohorts
    FOR EACH ROW EXECUTE FUNCTION internal.validate_observation_source_cohort();
COMMENT ON COLUMN internal.observation_evidence_upload_cohorts.binding_analysis_id IS
    'Immutable source link for future coordinated writers; existing NULL cohorts never upgrade. Not admission or upload authority.';
COMMENT ON COLUMN internal.observation_audio_evidence_upload_cohorts.binding_analysis_id IS
    'Immutable source link for future coordinated writers; existing NULL cohorts never upgrade. Not admission or upload authority.';
RESET statement_timeout;
RESET lock_timeout;
