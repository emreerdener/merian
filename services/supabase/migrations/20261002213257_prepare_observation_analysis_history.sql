SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Preparation only. Enrollment is closed until all RFC activation gates have
-- implementations and exact-candidate evidence. No existing scan is enrolled.
CREATE TABLE internal.observation_history_rollout (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    enrollment_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    minimum_reader INTEGER NOT NULL DEFAULT 7 CHECK (minimum_reader = 7)
);
INSERT INTO internal.observation_history_rollout(singleton) VALUES(TRUE);

CREATE TABLE internal.observation_histories (
    observation_id UUID PRIMARY KEY REFERENCES public.scans(id) ON DELETE CASCADE,
    selected_analysis_id UUID,
    selection_initialized BOOLEAN NOT NULL DEFAULT FALSE,
    state_revision INTEGER NOT NULL DEFAULT 0 CHECK (state_revision BETWEEN 0 AND 2147483646),
    active_projection JSONB,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CHECK (selection_initialized = (selected_analysis_id IS NOT NULL)),
    CHECK (active_projection IS NULL OR (
        pg_catalog.JSONB_TYPEOF(active_projection) = 'object'
        AND pg_catalog.OCTET_LENGTH(active_projection::TEXT) <= 32768
    ))
);

CREATE TABLE internal.observation_analysis_results (
    analysis_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL CHECK (ordinal BETWEEN 1 AND 2147483646),
    source_analysis_id UUID,
    request_digest TEXT NOT NULL CHECK (request_digest ~ '^[0-9a-f]{64}$'),
    result_snapshot JSONB NOT NULL CHECK (
        pg_catalog.JSONB_TYPEOF(result_snapshot) = 'object'
        AND pg_catalog.OCTET_LENGTH(result_snapshot::TEXT) <= 1048576
    ),
    evidence_manifest JSONB NOT NULL CHECK (
        pg_catalog.JSONB_TYPEOF(evidence_manifest) = 'object'
        AND pg_catalog.OCTET_LENGTH(evidence_manifest::TEXT) <= 1048576
    ),
    completed_at TIMESTAMPTZ NOT NULL,
    UNIQUE(observation_id, analysis_id),
    UNIQUE(observation_id, ordinal),
    FOREIGN KEY(observation_id, source_analysis_id)
        REFERENCES internal.observation_analysis_results(observation_id, analysis_id),
    CHECK (analysis_id IS DISTINCT FROM source_analysis_id)
);

ALTER TABLE internal.observation_histories ADD CONSTRAINT observation_history_selected_result_fk
    FOREIGN KEY(observation_id, selected_analysis_id)
    REFERENCES internal.observation_analysis_results(observation_id, analysis_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE internal.observation_analysis_authorities (
    observation_id UUID NOT NULL,
    analysis_id UUID PRIMARY KEY,
    review_revision INTEGER NOT NULL DEFAULT 0 CHECK (review_revision BETWEEN 0 AND 2147483646),
    review_snapshot JSONB NOT NULL CHECK (
        pg_catalog.JSONB_TYPEOF(review_snapshot) = 'object'
        AND pg_catalog.OCTET_LENGTH(review_snapshot::TEXT) <= 32768
    ),
    FOREIGN KEY(observation_id, analysis_id)
        REFERENCES internal.observation_analysis_results(observation_id, analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_analysis_authorities_observation_idx
    ON internal.observation_analysis_authorities(observation_id);

CREATE TABLE internal.observation_selection_receipts (
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    request_identity JSONB NOT NULL CHECK (pg_catalog.OCTET_LENGTH(request_identity::TEXT) <= 2048),
    receipt JSONB NOT NULL CHECK (pg_catalog.OCTET_LENGTH(receipt::TEXT) <= 4096),
    PRIMARY KEY(observation_id, operation_id)
);

-- All history lives outside exposed schemas. Even service code must use the
-- narrow guarded RPCs added with each implementation stage; no table grants.
REVOKE ALL ON TABLE internal.observation_history_rollout,
    internal.observation_histories, internal.observation_analysis_results,
    internal.observation_analysis_authorities, internal.observation_selection_receipts
    FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE internal.observation_history_rollout ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_histories ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_analysis_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_analysis_authorities ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_selection_receipts ENABLE ROW LEVEL SECURITY;

-- A local fixture may exercise storage as its database owner. API roles cannot
-- enroll through a direct write, and the deployment defaults remain closed.
CREATE FUNCTION internal.guard_observation_history_generation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE observation UUID := NEW.observation_id; generation_owner UUID;
BEGIN
    SELECT user_id INTO generation_owner FROM public.scans WHERE id = observation;
    PERFORM users.id FROM public.users AS users WHERE users.id = generation_owner FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'analysis_history_deleted' USING ERRCODE = 'P0002';
    END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || observation::TEXT, 0::BIGINT));
    PERFORM scan.id FROM public.scans AS scan
    WHERE scan.id = observation AND scan.user_id = generation_owner AND NOT scan.is_tombstoned
    FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = observation) THEN
        RAISE EXCEPTION 'analysis_history_deleted' USING ERRCODE = 'P0002';
    END IF;
    IF TG_TABLE_NAME = 'observation_histories' AND TG_OP = 'INSERT'
        AND (SELECT enrollment_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_history_generation() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER guard_observation_history_generation BEFORE INSERT OR UPDATE
ON internal.observation_histories FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER guard_observation_analysis_generation BEFORE INSERT OR UPDATE
ON internal.observation_analysis_results FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER guard_observation_authority_generation BEFORE INSERT OR UPDATE
ON internal.observation_analysis_authorities FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER guard_observation_selection_generation BEFORE INSERT OR UPDATE
ON internal.observation_selection_receipts FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();

CREATE FUNCTION internal.reject_observation_history_evidence_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.reject_observation_history_evidence_update() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER reject_observation_result_update BEFORE UPDATE ON internal.observation_analysis_results
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();
CREATE TRIGGER reject_observation_receipt_update BEFORE UPDATE ON internal.observation_selection_receipts
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Review changes on an inactive result also invalidate observation expectations:
-- that result may be the published one. Initial authority insertion is part of
-- completion/enrollment; only subsequent authority transitions advance here.
CREATE FUNCTION internal.advance_observation_authority_revision()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NEW.observation_id IS DISTINCT FROM OLD.observation_id OR NEW.analysis_id IS DISTINCT FROM OLD.analysis_id THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE = '22023';
    END IF;
    IF NEW.review_snapshot IS DISTINCT FROM OLD.review_snapshot THEN
        IF OLD.review_revision >= 2147483646 OR EXISTS (
            SELECT 1 FROM internal.observation_histories
            WHERE observation_id = NEW.observation_id AND state_revision >= 2147483646
        ) THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
        END IF;
        IF NEW.review_revision <> OLD.review_revision + 1 THEN
            RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE = '40001';
        END IF;
        UPDATE internal.observation_histories SET state_revision = state_revision + 1
        WHERE observation_id = NEW.observation_id;
    ELSIF NEW.review_revision IS DISTINCT FROM OLD.review_revision THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE = '40001';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.advance_observation_authority_revision() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER advance_observation_authority_revision BEFORE UPDATE ON internal.observation_analysis_authorities
FOR EACH ROW EXECUTE FUNCTION internal.advance_observation_authority_revision();

COMMENT ON TABLE internal.observation_histories IS
    'Release-held history storage. No enrollment RPC or live producer is enabled by this migration. Retention, explicit deletion, projection, private-media and native gates must land before enrollment.';
COMMENT ON TABLE internal.observation_analysis_results IS
    'Immutable owner-private analysis evidence; observation ownership is inherited through the parent, never accepted from a client body.';

-- Private history must not survive account detachment merely because its
-- observation remains as a restricted scientific tombstone. Active scientific
-- projection materialization must be implemented before enrollment opens.
CREATE FUNCTION internal.clear_detached_observation_history()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    DELETE FROM internal.observation_histories WHERE observation_id = NEW.id;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.clear_detached_observation_history() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER clear_detached_observation_history AFTER UPDATE OF user_id ON public.scans
FOR EACH ROW WHEN (OLD.user_id IS NOT NULL AND NEW.user_id IS NULL)
EXECUTE FUNCTION internal.clear_detached_observation_history();

RESET statement_timeout;
RESET lock_timeout;
