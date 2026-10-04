SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Private preparation only: no API grant, endpoint, scheduler or public publisher.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN community_authority_enabled BOOLEAN NOT NULL DEFAULT FALSE;
-- Fresh-insert proof cannot be forged by reopening/updating an older request.
CREATE TABLE internal.observation_community_creation_fences (
    request_id UUID PRIMARY KEY REFERENCES public.explore_community_requests(id) ON DELETE CASCADE,
    creation_transaction XID8 NOT NULL
);
ALTER TABLE internal.observation_community_creation_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_community_creation_fences FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.record_observation_community_creation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF (SELECT community_authority_enabled FROM internal.observation_history_rollout WHERE singleton) IS TRUE THEN
        INSERT INTO internal.observation_community_creation_fences VALUES(NEW.id,pg_catalog.pg_current_xact_id());
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.record_observation_community_creation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER record_observation_community_creation AFTER INSERT ON public.explore_community_requests
FOR EACH ROW EXECUTE FUNCTION internal.record_observation_community_creation();
CREATE TABLE internal.observation_community_bindings (
    -- Keep the binding/outbox after request deletion until authority is revoked.
    -- Parent observation deletion still cascades the complete private record.
    request_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    post_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    taxonomy_version_id UUID NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    bound_observation_revision INTEGER NOT NULL CHECK(bound_observation_revision BETWEEN 0 AND 2147483646),
    bound_review_revision INTEGER NOT NULL CHECK(bound_review_revision BETWEEN 0 AND 2147483646),
    FOREIGN KEY(observation_id,analysis_id) REFERENCES internal.observation_analysis_results(observation_id,analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_community_bindings_analysis_idx ON internal.observation_community_bindings(observation_id,analysis_id);
CREATE TABLE internal.observation_community_reconciliation (
    request_id UUID PRIMARY KEY REFERENCES internal.observation_community_bindings(request_id) ON DELETE CASCADE,
    source_revision INTEGER NOT NULL DEFAULT 1 CHECK(source_revision BETWEEN 1 AND 2147483646),
    applied_source_revision INTEGER NOT NULL DEFAULT 0 CHECK(applied_source_revision BETWEEN 0 AND source_revision),
    applied_review_revision INTEGER NOT NULL CHECK(applied_review_revision BETWEEN 0 AND 2147483646),
    superseded BOOLEAN NOT NULL DEFAULT FALSE
);
ALTER TABLE internal.observation_community_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_community_reconciliation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_community_bindings,internal.observation_community_reconciliation FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_community_binding_generation BEFORE INSERT OR UPDATE ON internal.observation_community_bindings
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_community_binding_update BEFORE UPDATE ON internal.observation_community_bindings
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- The future publisher must call this inside its new-request transaction after
-- approved, analysis-bound public snapshot creation. Never attach legacy requests.
CREATE FUNCTION internal.bind_observation_community_request(
    p_owner UUID,p_observation UUID,p_analysis UUID,p_request UUID,p_observation_revision INTEGER,p_review_revision INTEGER)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE history internal.observation_histories; authority internal.observation_analysis_authorities;
    evidence internal.observation_analysis_results; request public.explore_community_requests;
    binding internal.observation_community_bindings;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_observation IS NULL OR p_analysis IS NULL OR p_request IS NULL
        OR p_observation_revision IS NULL OR p_observation_revision NOT BETWEEN 0 AND 2147483646
        OR p_review_revision IS NULL OR p_review_revision NOT BETWEEN 0 AND 2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_observation::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=p_observation AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO binding FROM internal.observation_community_bindings WHERE request_id=p_request;
    IF FOUND THEN
        IF ROW(binding.owner_id,binding.observation_id,binding.analysis_id,binding.bound_observation_revision,binding.bound_review_revision)
            IS DISTINCT FROM ROW(p_owner,p_observation,p_analysis,p_observation_revision,p_review_revision) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN;
    END IF;
    IF (SELECT community_authority_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=p_observation AND analysis_id=p_analysis FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF NOT history.selection_initialized OR history.state_revision<>p_observation_revision OR authority.review_revision<>p_review_revision THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
    END IF;
    SELECT * INTO STRICT evidence FROM internal.observation_analysis_results WHERE observation_id=p_observation AND analysis_id=p_analysis;
    PERFORM internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    IF evidence.result_snapshot->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
        OR authority.review_snapshot->>'user_review_state'<>'unreviewed'
        OR NULLIF(authority.review_snapshot#>'{ai_identification_review,community}','null'::JSONB) IS NOT NULL THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
    END IF;
    -- Never wait on request while holding history locks: legacy consensus owns
    -- request first. Fresh publication already owns this row; contention retries.
    BEGIN
        SELECT * INTO request FROM public.explore_community_requests WHERE id=p_request FOR UPDATE NOWAIT;
    EXCEPTION WHEN lock_not_available THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END;
    IF NOT FOUND OR request.scan_id<>p_observation OR request.requested_by IS DISTINCT FROM p_owner
        OR request.status<>'needs_id' OR request.withdrawn_at IS NOT NULL
        OR NOT EXISTS(SELECT 1 FROM public.explore_posts WHERE id=request.post_id AND scan_id=p_observation AND user_id=p_owner) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM internal.observation_community_creation_fences
        WHERE request_id=p_request AND creation_transaction=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'analysis_history_community_requires_new_request' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.observation_community_bindings VALUES(p_request,p_observation,p_analysis,request.post_id,p_owner,
        request.taxonomy_version_id,request.requested_at,p_observation_revision,p_review_revision);
    INSERT INTO internal.observation_community_reconciliation(request_id,applied_review_revision) VALUES(p_request,p_review_revision);
    PERFORM internal.reconcile_observation_community_authority(p_owner,p_request);
END;
$$;
REVOKE ALL ON FUNCTION internal.bind_observation_community_request(UUID,UUID,UUID,UUID,INTEGER,INTEGER) FROM PUBLIC,anon,authenticated,service_role;

-- Bound request updates stay on the consensus lock path. No history/owner lock
-- is acquired here; projection happens in the private worker below.
DO $guard$
DECLARE definition TEXT; marker TEXT := E'BEGIN\n    IF TG_OP=';
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.guard_enrolled_community_request()'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'community_review_source_drift'; END IF;
    definition := replace(definition,marker,$patch$BEGIN
    IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM internal.observation_community_bindings WHERE request_id=OLD.id) THEN
        IF NOT EXISTS(SELECT 1 FROM internal.observation_community_bindings b WHERE b.request_id=NEW.id
            AND b.observation_id=NEW.scan_id AND b.owner_id=NEW.requested_by AND b.post_id=NEW.post_id
            AND b.taxonomy_version_id=NEW.taxonomy_version_id AND b.requested_at=NEW.requested_at) THEN
            RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
        END IF;
        IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.scan_id)
            OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=NEW.scan_id AND user_id=NEW.requested_by AND NOT is_tombstoned) THEN
            RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
        END IF;
        RETURN NEW;
    END IF;
    IF TG_OP=$patch$);
    EXECUTE definition;
    definition := pg_catalog.pg_get_functiondef('internal.sync_community_identification_review()'::REGPROCEDURE);
    marker := E'BEGIN\n    SELECT * INTO scan';
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'community_review_source_drift'; END IF;
    EXECUTE replace(definition,marker,E'BEGIN\n    IF EXISTS(SELECT 1 FROM internal.observation_community_bindings WHERE request_id=NEW.id) THEN RETURN NULL; END IF;\n    SELECT * INTO scan');
END;
$guard$;
DROP TRIGGER guard_enrolled_community_request ON public.explore_community_requests;
CREATE TRIGGER guard_enrolled_community_request BEFORE INSERT OR UPDATE OF id,scan_id,status,resolved_taxon_node_id,withdrawn_at,requested_by,post_id,taxonomy_version_id,requested_at ON public.explore_community_requests
FOR EACH ROW EXECUTE FUNCTION internal.guard_enrolled_community_request();

CREATE FUNCTION internal.enqueue_observation_community_authority()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    UPDATE internal.observation_community_reconciliation SET source_revision=source_revision+1
    WHERE request_id=CASE WHEN TG_OP='DELETE' THEN OLD.id ELSE NEW.id END;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.enqueue_observation_community_authority() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER zz_enqueue_observation_community_authority AFTER UPDATE OF status,resolved_taxon_node_id,withdrawn_at ON public.explore_community_requests
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.resolved_taxon_node_id IS DISTINCT FROM NEW.resolved_taxon_node_id OR OLD.withdrawn_at IS DISTINCT FROM NEW.withdrawn_at)
EXECUTE FUNCTION internal.enqueue_observation_community_authority();

CREATE TRIGGER zz_delete_observation_community_authority AFTER DELETE ON public.explore_community_requests
FOR EACH ROW EXECUTE FUNCTION internal.enqueue_observation_community_authority();

CREATE FUNCTION internal.reconcile_observation_community_authority(p_owner UUID,p_request UUID)
RETURNS TEXT LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_community_bindings; work internal.observation_community_reconciliation;
    authority internal.observation_analysis_authorities; evidence internal.observation_analysis_results;
    request public.explore_community_requests; taxon public.taxon_nodes;
    review JSONB; community JSONB; next_authority JSONB; materialized UUID;
    ai_revision INTEGER; species_revision INTEGER;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO binding FROM internal.observation_community_bindings WHERE request_id=p_request AND owner_id=p_owner;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||binding.observation_id::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=binding.observation_id AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=binding.observation_id) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    PERFORM observation_id FROM internal.observation_histories WHERE observation_id=binding.observation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=binding.observation_id AND analysis_id=binding.analysis_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    -- Consensus may hold this row before a notification FK waits on owner/scan.
    -- NOWAIT breaks that cycle. The caller must end this transaction and retry.
    BEGIN
        SELECT * INTO work FROM internal.observation_community_reconciliation WHERE request_id=p_request FOR UPDATE NOWAIT;
    EXCEPTION WHEN lock_not_available THEN RETURN 'pending'; END;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    IF work.superseded OR authority.review_revision<>work.applied_review_revision THEN
        UPDATE internal.observation_community_reconciliation SET superseded=TRUE,applied_source_revision=source_revision WHERE request_id=p_request;
        RETURN 'superseded';
    END IF;
    IF work.source_revision=work.applied_source_revision THEN RETURN 'current'; END IF;
    -- Do not lock request: its committed revision is serialized by the locked
    -- outbox. An in-flight request mutation cannot commit without updating it.
    SELECT * INTO request FROM public.explore_community_requests WHERE id=p_request;
    IF FOUND AND (request.scan_id<>binding.observation_id OR request.requested_by IS DISTINCT FROM p_owner
        OR request.post_id<>binding.post_id OR request.taxonomy_version_id<>binding.taxonomy_version_id
        OR request.requested_at<>binding.requested_at) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO STRICT evidence FROM internal.observation_analysis_results WHERE observation_id=binding.observation_id AND analysis_id=binding.analysis_id;
    PERFORM internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    review := NULLIF(authority.review_snapshot->'ai_identification_review','null'::JSONB);
    ai_revision := COALESCE((review->>'revision')::INTEGER,0);
    species_revision := (authority.review_snapshot->>'confirmed_species_identity_revision')::INTEGER;
    IF ai_revision>=999999999 OR species_revision IS NULL OR species_revision>=2147483646 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF request.status='resolved' AND request.withdrawn_at IS NULL THEN
        SELECT * INTO taxon FROM public.taxon_nodes WHERE id=request.resolved_taxon_node_id AND taxonomy_version_id=binding.taxonomy_version_id;
        IF NOT FOUND OR taxon.rank NOT IN ('species','genus') THEN RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023'; END IF;
        IF taxon.rank='species' THEN materialized := public.community_materialize_resolved_species(taxon.id); END IF;
        community := pg_catalog.jsonb_build_object('request_id',p_request,'rank',taxon.rank,
            'scientific_name',taxon.scientific_name,'common_name',taxon.common_name,'species_id',materialized);
    END IF;
    review := pg_catalog.jsonb_build_object('version',1,'revision',ai_revision+1,
        'state',CASE WHEN community IS NULL THEN 'awaiting_acceptance' ELSE 'clear' END,
        'origin_scan_id',COALESCE(review->>'origin_scan_id',binding.observation_id::TEXT),
        'origin_identification',COALESCE(NULLIF(review->'origin_identification','null'::JSONB),pg_catalog.jsonb_build_object(
            'scientific_name',evidence.result_snapshot#>>'{primary_identification,scientific_name}',
            'common_name',evidence.result_snapshot#>>'{primary_identification,common_name}')),
        'operation_id',NULL,'operation_digest',NULL,'community',community);
    next_authority := pg_catalog.jsonb_build_object('ai_identification_review',review,
        'confirmed_species_identity',NULL,'confirmed_species_identity_revision',species_revision+1,
        'confirmed_species_id',NULL,'user_identification_override',NULL,'user_confirmed_identification',FALSE,'user_review_state','unreviewed');
    PERFORM internal.observation_analysis_projection(evidence.result_snapshot,next_authority);
    UPDATE internal.observation_analysis_authorities SET review_revision=review_revision+1,review_snapshot=next_authority WHERE analysis_id=binding.analysis_id;
    UPDATE internal.observation_community_reconciliation SET applied_source_revision=source_revision,applied_review_revision=authority.review_revision+1 WHERE request_id=p_request;
    RETURN 'applied';
END;
$$;
REVOKE ALL ON FUNCTION internal.reconcile_observation_community_authority(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
RESET statement_timeout;
RESET lock_timeout;
