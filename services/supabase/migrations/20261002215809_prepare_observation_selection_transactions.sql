SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN selection_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- These are durable obligations, not awarded credits. Connected consumers must
-- reconcile current authority and compare revisions atomically before activation.
CREATE TABLE internal.observation_history_reconciliation (
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    state_revision INTEGER NOT NULL CHECK (state_revision BETWEEN 1 AND 2147483646),
    selected_analysis_id UUID NOT NULL,
    changed_analysis_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY(observation_id, state_revision),
    FOREIGN KEY(observation_id, selected_analysis_id)
        REFERENCES internal.observation_analysis_results(observation_id, analysis_id),
    FOREIGN KEY(observation_id, changed_analysis_id)
        REFERENCES internal.observation_analysis_results(observation_id, analysis_id)
);
REVOKE ALL ON TABLE internal.observation_history_reconciliation FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE internal.observation_history_reconciliation ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER guard_observation_reconciliation_generation BEFORE INSERT OR UPDATE
ON internal.observation_history_reconciliation FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();

-- Pure projection over explicitly chosen fields. Never update the immutable
-- original scan to reuse its policy, and never merge arbitrary result JSON into
-- authority. The existing validator remains the taxonomy/review policy owner.
CREATE FUNCTION internal.observation_analysis_projection(evidence JSONB, authority JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE candidate public.scans; projection JSONB;
BEGIN
    IF NOT internal.ai_identification_review_is_valid(
        NULLIF(authority -> 'ai_identification_review', 'null'::JSONB)
    ) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
    END IF;
    SELECT * INTO candidate FROM pg_catalog.JSONB_POPULATE_RECORD(NULL::public.scans,
        pg_catalog.JSONB_BUILD_OBJECT(
            'primary_identification', evidence -> 'primary_identification',
            'identification_provenance', evidence -> 'identification_provenance',
            'species_id', evidence -> 'species_id',
            'is_biological_subject', evidence -> 'is_biological_subject',
            'candidates', evidence -> 'candidates',
            'pet_identification', evidence -> 'pet_identification',
            'ai_identification_review', authority -> 'ai_identification_review',
            'confirmed_species_identity', authority -> 'confirmed_species_identity',
            'confirmed_species_identity_revision', authority -> 'confirmed_species_identity_revision',
            'confirmed_species_id', authority -> 'confirmed_species_id',
            'user_identification_override', authority -> 'user_identification_override',
            'user_confirmed_identification', authority -> 'user_confirmed_identification',
            'user_review_state', authority -> 'user_review_state'));
    projection := internal.scan_effective_identification(candidate);
    IF projection ->> 'source' = 'invalid' THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
    END IF;
    IF candidate.is_biological_subject IS FALSE THEN
        projection := projection || pg_catalog.JSONB_BUILD_OBJECT('rank','non_biological','species_id',NULL,'verified',FALSE);
    END IF;
    RETURN projection;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_analysis_projection(JSONB, JSONB) FROM PUBLIC, anon, authenticated, service_role;

-- Private service implementation, deliberately not an exposed RPC. Matching
-- native/read/public/credit gates and strict result producers must land first.
CREATE FUNCTION internal.select_observation_analysis(p_user_id UUID, p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE
    observation UUID; target UUID; operation UUID;
    expected_revision INTEGER; expected_review INTEGER;
    history internal.observation_histories;
    evidence internal.observation_analysis_results;
    authority internal.observation_analysis_authorities;
    saved internal.observation_selection_receipts;
    projection JSONB; receipt JSONB; next_revision INTEGER;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.JSONB_OBJECT_KEYS(p_request)) <> 6
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision']
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR COALESCE(p_request ->> 'observation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'analysis_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'operation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_observation_revision') IS DISTINCT FROM 'number'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_review_revision') IS DISTINCT FROM 'number'
        OR COALESCE(p_request ->> 'expected_observation_revision','') !~ '^[0-9]{1,10}$'
        OR COALESCE(p_request ->> 'expected_review_revision','') !~ '^[0-9]{1,10}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (p_request ->> 'expected_observation_revision')::BIGINT > 2147483646
        OR (p_request ->> 'expected_review_revision')::BIGINT > 2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    operation := (p_request ->> 'operation_id')::UUID;
    expected_revision := (p_request ->> 'expected_observation_revision')::INTEGER;
    expected_review := (p_request ->> 'expected_review_revision')::INTEGER;

    -- All mutations use owner -> observation advisory -> observation row ->
    -- history -> analysis/authority. No other owner's membership is disclosed.
    PERFORM users.id FROM public.users AS users WHERE users.id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || observation::TEXT,0::BIGINT));
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=observation AND scans.user_id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=observation)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=observation AND is_tombstoned) THEN
        RAISE EXCEPTION 'analysis_history_deleted' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO saved FROM internal.observation_selection_receipts
    WHERE observation_id=observation AND operation_id=operation;
    IF FOUND THEN
        IF saved.request_identity IS DISTINCT FROM p_request THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- Old receipts never reinstall old projections or outbox work.
        RETURN saved.receipt;
    END IF;
    IF (SELECT selection_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO evidence FROM internal.observation_analysis_results
    WHERE observation_id=observation AND analysis_id=target;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities
    WHERE observation_id=observation AND analysis_id=target FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    IF NOT history.selection_initialized OR history.state_revision <> expected_revision
        OR authority.review_revision <> expected_review THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
    END IF;
    IF history.state_revision >= 2147483646 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    next_revision := history.state_revision + 1;
    projection := internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    receipt := pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'operation_id',operation,
        'observation_id',observation,'previous_analysis_id',history.selected_analysis_id,
        'selected_analysis_id',target,'observation_revision',next_revision,'review_revision',authority.review_revision);
    UPDATE internal.observation_histories SET selected_analysis_id=target,state_revision=next_revision,active_projection=projection
    WHERE observation_id=observation;
    INSERT INTO internal.observation_selection_receipts(observation_id,operation_id,request_identity,receipt)
    VALUES(observation,operation,p_request,receipt);
    INSERT INTO internal.observation_history_reconciliation(observation_id,state_revision,selected_analysis_id,changed_analysis_id)
    VALUES(observation,next_revision,target,target);
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION internal.select_observation_analysis(UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role;

-- Validate and recompute from NEW authority within the same transaction. Inactive reviews still create a public authority
-- invalidation obligation and advance the parent revision.
CREATE OR REPLACE FUNCTION internal.advance_observation_authority_revision()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE history internal.observation_histories; projection JSONB;
BEGIN
    IF NEW.observation_id IS DISTINCT FROM OLD.observation_id OR NEW.analysis_id IS DISTINCT FROM OLD.analysis_id THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    IF NEW.review_snapshot IS NOT DISTINCT FROM OLD.review_snapshot THEN
        IF NEW.review_revision IS DISTINCT FROM OLD.review_revision THEN
            RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
        END IF;
        RETURN NEW;
    END IF;
    SELECT * INTO STRICT history FROM internal.observation_histories WHERE observation_id=NEW.observation_id FOR UPDATE;
    IF OLD.review_revision >= 2147483646 OR history.state_revision >= 2147483646 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF NEW.review_revision <> OLD.review_revision + 1 THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
    END IF;
    projection := history.active_projection;
    IF history.selected_analysis_id=NEW.analysis_id THEN
        SELECT internal.observation_analysis_projection(result_snapshot,NEW.review_snapshot) INTO projection
        FROM internal.observation_analysis_results WHERE observation_id=NEW.observation_id AND analysis_id=NEW.analysis_id;
    END IF;
    UPDATE internal.observation_histories SET state_revision=history.state_revision+1,active_projection=projection
    WHERE observation_id=NEW.observation_id;
    IF history.selection_initialized THEN
        INSERT INTO internal.observation_history_reconciliation(observation_id,state_revision,selected_analysis_id,changed_analysis_id)
        VALUES(NEW.observation_id,history.state_revision+1,history.selected_analysis_id,NEW.analysis_id);
    END IF;
    RETURN NEW;
END;
$$;
-- Run the generation guard first. API roles cannot write authorities directly;
-- the future review entry point must acquire the global locks before UPDATE.
DROP TRIGGER advance_observation_authority_revision ON internal.observation_analysis_authorities;
CREATE TRIGGER reproject_observation_authority_revision BEFORE UPDATE ON internal.observation_analysis_authorities
FOR EACH ROW EXECUTE FUNCTION internal.advance_observation_authority_revision();

COMMENT ON FUNCTION internal.select_observation_analysis(UUID, JSONB) IS
    'Release-held private selection transaction: current authority, CAS revision, replay receipt and durable reconciliation obligation; no public RPC or credit worker yet.';

RESET statement_timeout;
RESET lock_timeout;
