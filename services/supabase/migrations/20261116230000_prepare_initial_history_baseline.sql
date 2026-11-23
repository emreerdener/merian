SET lock_timeout='5s';
SET statement_timeout='2min';

-- Immutable ordinary completion becomes a real baseline, not a legacy import
-- and not a reanalysis child. This migration prepares readers; no gate opens.
ALTER TABLE internal.observation_analysis_results ADD COLUMN initial_evidence_proof JSONB;

CREATE FUNCTION internal.assert_sealed_initial_evidence(p_owner UUID,p_scan UUID)
RETURNS internal.ordinary_initial_evidence LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; contract JSONB; receipt JSONB; proof JSONB;
BEGIN
    SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=p_scan;
    IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.retired_at IS NOT NULL
        OR saved.sealed_at IS NULL OR saved.accepted_result IS NULL OR saved.allocated_at IS NULL
        OR saved.result_snapshot IS DISTINCT FROM saved.accepted_result
        OR saved.completion_response->'data' IS DISTINCT FROM saved.accepted_result THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    contract:=internal.initial_evidence_contract(saved.evidence_manifest,p_scan::TEXT,saved.generation::TEXT);
    proof:=jsonb_build_object('schema_version',1,'owner_id',p_owner,'scan_id',p_scan,
        'generation',saved.generation,'evidence_digest',saved.evidence_digest);
    IF contract->>'evidence_digest' IS DISTINCT FROM saved.evidence_digest
        OR saved.completion_response->'initial_evidence' IS DISTINCT FROM proof THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    receipt:=internal.ordinary_initial_evidence_receipt(saved);
    IF jsonb_array_length(receipt->'items') IS DISTINCT FROM jsonb_array_length(contract->'items')
        OR (SELECT count(*) FROM internal.ordinary_initial_evidence_objects WHERE scan_id=p_scan)<>jsonb_array_length(contract->'items')
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'items') x
            LEFT JOIN internal.ordinary_initial_evidence_objects o ON o.scan_id=p_scan AND o.media_id=(x->>'media_id')::UUID
            WHERE o.ready_at IS NULL OR x IS DISTINCT FROM jsonb_build_object('media_id',o.media_id,'item_index',o.item_index,
                'role',o.role,'role_index',o.role_index,'content_type',o.content_type,'byte_count',o.byte_count,'sha256',o.sha256))
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') WITH ORDINALITY r(value,n)
            LEFT JOIN jsonb_array_elements(contract->'items') WITH ORDINALITY c(value,n) USING(n)
            WHERE r.value-ARRAY['object_id','ready'] IS DISTINCT FROM c.value OR r.value->'ready' IS DISTINCT FROM 'true'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN saved;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_sealed_initial_evidence(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- The proof is stored in the immutable result row. The old eight-argument
-- serializer remains byte-identical for all earlier result versions.
CREATE FUNCTION internal.observation_result_snapshot(p_row internal.observation_analysis_results)
RETURNS TEXT LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
    SELECT CASE WHEN p_row.evidence_manifest->'schema_version'='7'::JSONB THEN
        jsonb_build_object('schema_version',8,'observation_id',p_row.observation_id,
            'analysis_id',p_row.analysis_id,'source_analysis_id',NULL,'request_digest',p_row.request_digest,
            'ordinal',p_row.ordinal,'completed_at_ms',floor(EXTRACT(EPOCH FROM p_row.completed_at)*1000),
            'result',p_row.result_snapshot,'evidence_manifest',p_row.evidence_manifest,
            'initial_evidence',p_row.initial_evidence_proof)::TEXT
    ELSE internal.observation_analysis_snapshot(p_row.observation_id,p_row.analysis_id,p_row.source_analysis_id,
        p_row.request_digest,p_row.ordinal,p_row.completed_at,p_row.result_snapshot,p_row.evidence_manifest) END;
$$;
REVOKE ALL ON FUNCTION internal.observation_result_snapshot(internal.observation_analysis_results) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO definition FROM pg_constraint
        WHERE conrelid='internal.observation_analysis_results'::regclass AND conname='observation_analysis_origin';
    anchor:='CASE';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_origin_drift'; END IF;
    definition:=replace(definition,anchor,$a$CASE WHEN evidence_manifest->'schema_version'='7'::JSONB THEN
        request_digest IS NOT NULL AND completed_at IS NOT NULL AND source_analysis_id IS NULL AND ordinal=1$a$);
    ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT observation_analysis_origin;
    EXECUTE 'ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_origin '||definition;
END;
$patch$;
ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_initial_proof CHECK(
    (CASE WHEN evidence_manifest->'schema_version'='7'::JSONB THEN
        initial_evidence_proof IS NOT NULL AND jsonb_typeof(initial_evidence_proof)='object'
        AND initial_evidence_proof ?& ARRAY['schema_version','owner_id','scan_id','generation','evidence_digest']
        AND initial_evidence_proof-ARRAY['schema_version','owner_id','scan_id','generation','evidence_digest']='{}'::JSONB
        AND initial_evidence_proof->'schema_version'='1'::JSONB
        AND initial_evidence_proof->>'scan_id'=observation_id::TEXT
        AND initial_evidence_proof->>'evidence_digest'=request_digest
        AND initial_evidence_proof->>'generation' NOT IN (analysis_id::TEXT,observation_id::TEXT)
        AND initial_evidence_proof->>'owner_id' NOT IN (analysis_id::TEXT,observation_id::TEXT,initial_evidence_proof->>'generation')
        AND octet_length(internal.observation_result_snapshot(observation_analysis_results))<=1048576
    ELSE initial_evidence_proof IS NULL END) IS TRUE);

CREATE FUNCTION internal.guard_initial_history_baseline()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; owner UUID;
BEGIN
    IF NEW.evidence_manifest->'schema_version' IS DISTINCT FROM '7'::JSONB THEN RETURN NEW; END IF;
    SELECT user_id INTO owner FROM public.scans WHERE id=NEW.observation_id AND NOT is_tombstoned;
    saved:=internal.assert_sealed_initial_evidence(owner,NEW.observation_id);
    IF NEW.source_analysis_id IS NOT NULL OR NEW.ordinal<>1
        OR NEW.request_digest IS DISTINCT FROM saved.evidence_digest
        OR NEW.completed_at IS DISTINCT FROM saved.sealed_at
        OR NEW.initial_evidence_proof IS DISTINCT FROM saved.completion_response->'initial_evidence'
        OR NEW.evidence_manifest IS DISTINCT FROM saved.evidence_manifest
        -- Keep the accepted taxonomy beside the original wire fields. Neither
        -- comes from the mutable scan or dictionary at enrollment time.
        OR NEW.result_snapshot IS DISTINCT FROM saved.result_snapshot||jsonb_build_object('species_id',saved.accepted_species_id)
        OR NEW.analysis_id IN (owner,NEW.observation_id,saved.generation)
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(internal.initial_evidence_contract(saved.evidence_manifest,
            saved.scan_id::TEXT,saved.generation::TEXT)->'items') x WHERE x->>'media_id'=NEW.analysis_id::TEXT) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_history_baseline() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_history_baseline BEFORE INSERT ON internal.observation_analysis_results
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_history_baseline();

CREATE FUNCTION internal.enroll_sealed_initial_history(p_owner UUID,p_observation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE scan public.scans; saved internal.ordinary_initial_evidence; history internal.observation_histories;
    baseline internal.observation_analysis_results; analysis UUID; result JSONB; review JSONB; projection JSONB;
BEGIN
    IF p_owner IS NULL OR p_observation IS NULL THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_observation::TEXT,0));
    SELECT * INTO scan FROM public.scans WHERE id=p_observation AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF (SELECT reader_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    saved:=internal.assert_sealed_initial_evidence(p_owner,p_observation);
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;
    IF FOUND THEN
        SELECT * INTO baseline FROM internal.observation_analysis_results WHERE observation_id=p_observation AND ordinal=1;
        IF NOT FOUND OR NOT history.selection_initialized OR baseline.evidence_manifest IS DISTINCT FROM saved.evidence_manifest
            OR baseline.initial_evidence_proof IS DISTINCT FROM saved.completion_response->'initial_evidence' THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        RETURN jsonb_build_object('schema_version',1,'owner_id',p_owner,'observation_id',p_observation,'baseline_analysis_id',baseline.analysis_id);
    END IF;
    IF (SELECT enrollment_enabled AND ordinary_initial_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    result:=saved.result_snapshot||jsonb_build_object('species_id',saved.accepted_species_id);
    review:=jsonb_build_object('ai_identification_review',scan.ai_identification_review,
        'confirmed_species_identity',scan.confirmed_species_identity,'confirmed_species_identity_revision',scan.confirmed_species_identity_revision,
        'confirmed_species_id',scan.confirmed_species_id,'user_identification_override',scan.user_identification_override,
        'user_confirmed_identification',scan.user_confirmed_identification,'user_review_state',scan.user_review_state);
    projection:=internal.observation_analysis_projection(result,review);
    analysis:=gen_random_uuid();
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||analysis::TEXT,0));
    IF analysis IN (p_owner,p_observation,saved.generation)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=analysis)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=analysis::TEXT)
        OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=analysis OR media_id=analysis OR object_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=analysis OR generation=analysis)
        OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence_objects WHERE media_id=analysis OR object_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(p_observation,FALSE);
    INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at,initial_evidence_proof)
        VALUES(analysis,p_observation,1,saved.evidence_digest,result,saved.evidence_manifest,saved.sealed_at,saved.completion_response->'initial_evidence');
    INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_revision,review_snapshot)
        VALUES(p_observation,analysis,0,review);
    UPDATE internal.observation_histories SET selected_analysis_id=analysis,selection_initialized=TRUE,state_revision=1,active_projection=projection
        WHERE observation_id=p_observation;
    RETURN jsonb_build_object('schema_version',1,'owner_id',p_owner,'observation_id',p_observation,'baseline_analysis_id',analysis);
END;
$$;
REVOKE ALL ON FUNCTION internal.enroll_sealed_initial_history(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    definition:=pg_get_functiondef('public.enroll_owned_observation_history(uuid,integer)'::regprocedure);
    anchor:=$a$    IF caller IS NULL OR p_observation IS NULL OR p_reader IS DISTINCT FROM 9 THEN$a$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_enrollment_drift'; END IF;
    definition:=replace(definition,anchor,$a$    IF p_reader=16 THEN RETURN internal.enroll_sealed_initial_history(caller,p_observation); END IF;
$a$||anchor);
    anchor:='    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_enrollment_drift'; END IF;
    EXECUTE replace(definition,anchor,$a$    IF EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=p_observation)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=p_observation::TEXT AND initial_evidence_generation IS NOT NULL) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
$a$||anchor);
    definition:=pg_get_functiondef('internal.fence_imported_observation_result()'::regprocedure);
    anchor:=$a$OLD.evidence_manifest->'schema_version'='3'::JSONB$a$;
    -- A genuine initial child has no reanalysis intent to retain its ID fence.
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_result_fence_drift'; END IF;
    EXECUTE replace(definition,anchor,$a$OLD.evidence_manifest->'schema_version' IN ('3'::JSONB,'7'::JSONB)$a$);
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;
