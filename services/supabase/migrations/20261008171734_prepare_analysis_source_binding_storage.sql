SET lock_timeout='5s';
SET statement_timeout='2min';

-- Cross-owner child-identity collision checks must not scan owner-prefixed indexes.
CREATE INDEX source_binding_quota_child ON internal.ai_quota_reservations(original_analysis_id) WHERE original_analysis_id IS NOT NULL;
CREATE INDEX source_binding_usage_child ON internal.complimentary_scan_usage(client_scan_id);
CREATE INDEX source_binding_ingestion_child ON public.scan_ingestion_intents(scan_id);

-- Private preparation only. No callable reservation or release routine exists.
-- Bindings are immutable history; occupancy is unique only while unresolved.
CREATE TABLE internal.observation_analysis_source_bindings (
    analysis_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    source_analysis_id UUID NOT NULL,
    input_snapshot JSONB NOT NULL CHECK(jsonb_typeof(input_snapshot)='object' AND octet_length(input_snapshot::TEXT)<=1044480),
    fingerprint_version INTEGER NOT NULL CHECK(fingerprint_version=1),
    fingerprint TEXT NOT NULL CHECK(fingerprint ~ '^[0-9a-f]{64}$'),
    CHECK(analysis_id<>observation_id AND source_analysis_id NOT IN (analysis_id,observation_id)),
    FOREIGN KEY(observation_id,source_analysis_id) REFERENCES internal.observation_analysis_results(observation_id,analysis_id) DEFERRABLE INITIALLY DEFERRED,
    UNIQUE(analysis_id,owner_id,observation_id,source_analysis_id)
);
CREATE INDEX observation_analysis_source_bindings_owner ON internal.observation_analysis_source_bindings(owner_id,observation_id,source_analysis_id);
CREATE INDEX observation_analysis_source_bindings_source ON internal.observation_analysis_source_bindings(observation_id,source_analysis_id,analysis_id);
CREATE TABLE internal.observation_analysis_source_occupancy (
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    source_analysis_id UUID NOT NULL,
    analysis_id UUID NOT NULL UNIQUE,
    PRIMARY KEY(owner_id,observation_id,source_analysis_id),
    FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
        REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_analysis_source_occupancy_observation ON internal.observation_analysis_source_occupancy(observation_id,source_analysis_id);
ALTER TABLE internal.observation_analysis_source_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_analysis_source_occupancy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_analysis_source_bindings,internal.observation_analysis_source_occupancy FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_source_storage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP='DELETE' THEN
        -- Preserve bindings/occupancy while their parent lives. Future terminal
        -- release requires a separately reviewed exact-proof transaction.
        IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
            AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP='UPDATE' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-analysis-source:' || NEW.observation_id::TEXT || ':' || NEW.source_analysis_id::TEXT,0::BIGINT));
    IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=NEW.observation_id AND analysis_id=NEW.source_analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_source_storage() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_source_binding BEFORE INSERT OR UPDATE OR DELETE
    ON internal.observation_analysis_source_bindings FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_source_storage();
CREATE TRIGGER guard_observation_source_occupancy BEFORE INSERT OR UPDATE OR DELETE
    ON internal.observation_analysis_source_occupancy FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_source_storage();

CREATE FUNCTION internal.validate_observation_source_binding()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF NEW.input_snapshot->>'observation_id' IS DISTINCT FROM NEW.observation_id::TEXT
        OR NEW.input_snapshot->>'analysis_id' IS DISTINCT FROM NEW.analysis_id::TEXT
        OR NEW.input_snapshot->>'source_analysis_id' IS DISTINCT FROM NEW.source_analysis_id::TEXT
        OR NEW.fingerprint IS DISTINCT FROM internal.observation_source_fingerprint(NEW.input_snapshot) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- An old child cannot be retrofitted into a fresh source binding. All
    -- writer coordination still has to be installed before any RPC opens.
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=NEW.analysis_id::TEXT)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=NEW.analysis_id::TEXT)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.validate_observation_source_binding() FROM PUBLIC,anon,authenticated,service_role;
-- Alphabetical trigger order: shared owner/source locking precedes validation.
CREATE TRIGGER validate_observation_source_binding BEFORE INSERT
    ON internal.observation_analysis_source_bindings FOR EACH ROW EXECUTE FUNCTION internal.validate_observation_source_binding();

CREATE FUNCTION internal.erase_observation_source_storage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_analysis_source_bindings WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.erase_observation_source_storage() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER erase_observation_source_storage AFTER INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.erase_observation_source_storage();

-- Keep the existing prepared-history ownership-transfer hold. No generic FK
-- reparenting may strand these explicit immutable owner identities.
DO $guard$
DECLARE definition TEXT; anchor CONSTANT TEXT:='    PERFORM internal.prepare_scan_ingestions_for_identity_merge(';
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.perform_ghost_profile_merge(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'Reviewed merge boundary changed';
    END IF;
    EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE owner_id=p_ghost_user_id) THEN
        RAISE EXCEPTION 'ghost_merge_source_history_requires_attention' USING ERRCODE='55000';
    END IF;
$body$ || anchor);
END;
$guard$;
COMMENT ON TABLE internal.observation_analysis_source_bindings IS
    'Private immutable source metadata binding; not reservation, admission, retirement or dispatch authority. No API writer.';
COMMENT ON TABLE internal.observation_analysis_source_occupancy IS
    'Private unresolved source uniqueness only. No release or callable reservation until all-writer fencing is reviewed.';
RESET statement_timeout;
RESET lock_timeout;
