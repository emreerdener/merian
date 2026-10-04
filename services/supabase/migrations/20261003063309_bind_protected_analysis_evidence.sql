SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Independent preparation gate. V1 routines and native reader remain V1-only.
ALTER TABLE internal.observation_history_rollout ADD COLUMN protected_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- A receipt reference is an owner-private media UUID and verified content tuple,
-- never an object key, object UUID, URL or caller claim of storage readiness.
CREATE FUNCTION internal.assert_protected_analysis_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_manifest JSONB,p_initial BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE item JSONB; media UUID; seen UUID[]:='{}'::UUID[]; total_bytes BIGINT:=0; saved internal.observation_evidence_objects;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || p_analysis::TEXT,0::BIGINT));
    IF jsonb_typeof(p_manifest) IS DISTINCT FROM 'object' OR p_manifest-ARRAY['schema_version','items']<>'{}'
        OR p_manifest->'schema_version' IS DISTINCT FROM '2'::JSONB OR jsonb_typeof(p_manifest->'items') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(p_manifest->'items') NOT BETWEEN 1 AND 64 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(p_manifest->'items') LOOP
        IF item->>'kind'='description' THEN
            IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR item-ARRAY['kind','text']<>'{}'
                OR jsonb_typeof(item->'text') IS DISTINCT FROM 'string' OR char_length(item->>'text') NOT BETWEEN 1 AND 8192 OR btrim(item->>'text')='' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
        ELSIF item->>'kind'='image' THEN
            IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR NOT(item ?& ARRAY['kind','media_id','content_type','byte_count','sha256'])
                OR item-ARRAY['kind','media_id','content_type','byte_count','sha256']<>'{}'
                OR jsonb_typeof(item->'media_id') IS DISTINCT FROM 'string' OR item->>'media_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                OR item->>'content_type' IS NULL OR item->>'content_type' NOT IN ('image/jpeg','image/png','image/heic')
                OR jsonb_typeof(item->'byte_count') IS DISTINCT FROM 'number' OR item->>'byte_count' !~ '^[0-9]{1,8}$'
                OR (item->>'byte_count')::BIGINT NOT BETWEEN 1 AND 33554432
                OR jsonb_typeof(item->'sha256') IS DISTINCT FROM 'string' OR item->>'sha256' !~ '^[0-9a-f]{64}$' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            media:=(item->>'media_id')::UUID;
            IF media=ANY(seen) OR media IN (p_observation,p_analysis) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            seen:=array_append(seen,media); total_bytes:=total_bytes+(item->>'byte_count')::BIGINT;
            SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=media AND owner_id=p_owner
                AND observation_id=p_observation AND analysis_id=p_analysis FOR UPDATE;
            IF NOT FOUND OR saved.ready_at IS NULL OR (p_initial AND saved.expires_at<=clock_timestamp())
                OR saved.content_type IS DISTINCT FROM item->>'content_type' OR saved.byte_count::BIGINT IS DISTINCT FROM (item->>'byte_count')::BIGINT
                OR saved.sha256 IS DISTINCT FROM item->>'sha256' THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
        ELSE RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF cardinality(seen)=0 OR total_bytes>33554432 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis AND NOT(media_id=ANY(seen))) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_protected_analysis_evidence(UUID,UUID,UUID,JSONB,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.admit_protected_observation_analysis(p_owner UUID,p_input JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID; analysis UUID; source UUID; saved internal.observation_analysis_intents;
    admitted RECORD; field TEXT; previous_fence TEXT;
BEGIN
    IF jsonb_typeof(p_input) IS DISTINCT FROM 'object'
        OR NOT (p_input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
        OR p_input - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
        OR p_input->'schema_version' IS DISTINCT FROM '2'::JSONB OR octet_length(p_input::TEXT)>1048576
        OR p_input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB
        OR p_input->'history_protocol' IS DISTINCT FROM '8'::JSONB
        OR p_input->>'expected_processor_permission' IS NULL OR p_input->>'expected_processor_permission' NOT IN ('google_gemini','openai')
        OR jsonb_typeof(p_input->'request_digest') IS DISTINCT FROM 'string' OR p_input->>'request_digest' IS NULL OR p_input->>'request_digest' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['observation_id','analysis_id'] LOOP
        IF jsonb_typeof(p_input->field) IS DISTINCT FROM 'string' OR p_input->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF p_input->'source_analysis_id'<>'null'::JSONB AND (jsonb_typeof(p_input->'source_analysis_id') IS DISTINCT FROM 'string'
        OR p_input->>'source_analysis_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation:=(p_input->>'observation_id')::UUID; analysis:=(p_input->>'analysis_id')::UUID; source:=(p_input->>'source_analysis_id')::UUID;
    IF analysis=observation OR source IN (analysis,observation) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF EXISTS(SELECT 1 FROM public.scans WHERE id=analysis) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || analysis::TEXT,0::BIGINT));
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || analysis::TEXT,0::BIGINT));
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=analysis FOR UPDATE;
    IF FOUND THEN
        IF saved.owner_id<>p_owner OR saved.observation_id<>observation OR saved.input_snapshot<>p_input THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- Dispatched/ambiguous work is recovery-only, never another provider call.
        IF saved.state<>'admitted' THEN RETURN to_jsonb(saved)-'draft'; END IF;
    ELSE
        IF (SELECT (admission_enabled AND protected_analysis_enabled) FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=analysis)
            OR EXISTS(SELECT 1 FROM public.scans WHERE id=analysis)
            OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=analysis::TEXT)
            OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=analysis)
            OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=analysis)
            OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=analysis)
            OR (source IS NOT NULL AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=source AND observation_id=observation)) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        PERFORM internal.assert_protected_analysis_evidence(p_owner,observation,analysis,p_input->'evidence_manifest',TRUE);
        INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) VALUES(analysis,observation,p_owner,p_input);
    END IF;
    IF (SELECT (admission_enabled AND protected_analysis_enabled) FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_protected_analysis_evidence(p_owner,observation,analysis,p_input->'evidence_manifest',FALSE);
    previous_fence:=current_setting('merian.observation_analysis_admission',TRUE);
    PERFORM set_config('merian.observation_analysis_admission',p_owner::TEXT || ':' || analysis::TEXT,TRUE);
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(p_owner,'scan_identification',analysis,p_ip_hash,analysis,FALSE,
        (p_input->>'entitlement_protocol')::INTEGER,FALSE,'multimodal_photo_v1',p_input->>'expected_processor_permission',(p_input->>'identification_protocol')::INTEGER);
    PERFORM set_config('merian.observation_analysis_admission',COALESCE(previous_fence,''),TRUE);
    IF admitted.original_analysis_id IS DISTINCT FROM analysis OR admitted.reservation_state<>'reserved' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    UPDATE internal.observation_analysis_intents SET quota=to_jsonb(admitted) WHERE analysis_id=analysis RETURNING * INTO saved;
    RETURN to_jsonb(saved)-'draft';
END;
$$;

CREATE FUNCTION internal.append_protected_observation_analysis(p_user_id UUID, p_request JSONB)
RETURNS TEXT LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    observation UUID; analysis UUID; source_analysis UUID; resolved_species UUID;
    history internal.observation_histories; saved internal.observation_analysis_results;
    evidence JSONB; result JSONB; text_value TEXT;
    initial_authority JSONB := '{"confirmed_species_identity":null,"confirmed_species_identity_revision":0,"confirmed_species_id":null,"user_identification_override":null,"user_confirmed_identification":false,"user_review_state":"unreviewed","ai_identification_review":null}'::JSONB;
    projection JSONB; next_ordinal INTEGER; completion_time TIMESTAMPTZ; snapshot TEXT;
    scientific_name TEXT; needs_species BOOLEAN;
BEGIN
    IF p_user_id IS NULL OR pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object'
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','result_snapshot','evidence_manifest'])
        OR p_request - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','result_snapshot','evidence_manifest'] <> '{}'::JSONB
        OR p_request -> 'schema_version' IS DISTINCT FROM '2'::JSONB
        OR pg_catalog.OCTET_LENGTH(p_request::TEXT) > 1048576 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH text_value IN ARRAY ARRAY['observation_id','analysis_id','request_digest'] LOOP
        IF pg_catalog.JSONB_TYPEOF(p_request -> text_value) IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF (p_request ->> 'observation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR (p_request ->> 'analysis_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR (p_request ->> 'request_digest') !~ '^[0-9a-f]{64}$'
        OR (p_request -> 'source_analysis_id' <> 'null'::JSONB AND (
            pg_catalog.JSONB_TYPEOF(p_request -> 'source_analysis_id') IS DISTINCT FROM 'string'
            OR (p_request ->> 'source_analysis_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    analysis := (p_request ->> 'analysis_id')::UUID;
    source_analysis := (p_request ->> 'source_analysis_id')::UUID;
    IF analysis = source_analysis OR analysis = observation OR source_analysis = observation THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    -- Identity fencing precedes replay: deletion and account detachment win even
    -- over an already-stored result. Lock order matches selection and erasure.
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
    SELECT * INTO saved FROM internal.observation_analysis_results WHERE analysis_id=analysis;
    IF FOUND THEN
        IF saved.observation_id IS DISTINCT FROM observation OR saved.source_analysis_id IS DISTINCT FROM source_analysis
            OR saved.request_digest IS DISTINCT FROM p_request ->> 'request_digest'
            OR saved.result_snapshot IS DISTINCT FROM p_request -> 'result_snapshot'
            OR saved.evidence_manifest IS DISTINCT FROM p_request -> 'evidence_manifest' THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN internal.observation_analysis_snapshot(saved.observation_id,saved.analysis_id,saved.source_analysis_id,
            saved.request_digest,saved.ordinal,saved.completed_at,saved.result_snapshot,saved.evidence_manifest);
    END IF;
    IF (SELECT (append_enabled AND protected_analysis_enabled) FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF source_analysis IS NOT NULL AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=observation AND analysis_id=source_analysis) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    IF NOT history.selection_initialized AND source_analysis IS NOT NULL THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    evidence := p_request -> 'evidence_manifest'; result := p_request -> 'result_snapshot';
    PERFORM internal.assert_protected_analysis_evidence(p_user_id,observation,analysis,evidence,FALSE);
    -- Full Identify semantic validation belongs to the canonical Edge builder.
    -- This storage boundary additionally binds identity/taxonomy, excludes review
    -- authority, and uses the existing database primary/projection validators.
    IF pg_catalog.JSONB_TYPEOF(result) IS DISTINCT FROM 'object'
        OR result ->> 'scan_id' IS DISTINCT FROM observation::TEXT
        OR pg_catalog.JSONB_TYPEOF(result -> 'is_biological_subject') IS DISTINCT FROM 'boolean'
        OR pg_catalog.JSONB_TYPEOF(result -> 'is_live_capture') IS DISTINCT FROM 'boolean'
        OR pg_catalog.JSONB_TYPEOF(result -> 'confidence_score') IS DISTINCT FROM 'number'
        OR NOT (result ? 'species_id')
        OR result ?| ARRAY['ai_identification_review','confirmed_species_identity','confirmed_species_identity_revision',
            'confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state','entitlement'] THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF (result ->> 'confidence_score')::NUMERIC NOT BETWEEN 0 AND 1 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF result -> 'species_id' <> 'null'::JSONB THEN
        IF pg_catalog.JSONB_TYPEOF(result -> 'species_id') IS DISTINCT FROM 'string'
            OR (result ->> 'species_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        resolved_species := (result ->> 'species_id')::UUID;
    END IF;
    needs_species := (result ->> 'is_biological_subject')::BOOLEAN AND (
        result #>> '{primary_identification,resolution}' = 'species'
        OR (NOT (result ? 'primary_identification') AND NULLIF(pg_catalog.BTRIM(result ->> 'scientific_name'),'') IS NOT NULL));
    IF COALESCE(needs_species,FALSE) <> (resolved_species IS NOT NULL) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF resolved_species IS NOT NULL THEN
        SELECT dictionary.scientific_name INTO scientific_name FROM public.species_dictionary AS dictionary
            WHERE dictionary.id=resolved_species FOR SHARE;
        IF NOT FOUND OR pg_catalog.LOWER(pg_catalog.BTRIM(scientific_name)) IS DISTINCT FROM
            pg_catalog.LOWER(pg_catalog.BTRIM(result ->> 'scientific_name')) THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END IF;
    projection := internal.observation_analysis_projection(result,initial_authority);
    SELECT COALESCE(MAX(ordinal),0) INTO next_ordinal FROM internal.observation_analysis_results WHERE observation_id=observation;
    IF next_ordinal >= 2147483646 OR (NOT history.selection_initialized AND (
        NOT history.initial_selection_permitted OR next_ordinal <> 0 OR history.state_revision <> 0)) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    next_ordinal := next_ordinal + 1;
    completion_time := pg_catalog.DATE_TRUNC('milliseconds',pg_catalog.CLOCK_TIMESTAMP());
    snapshot := internal.observation_analysis_snapshot(observation,analysis,source_analysis,p_request ->> 'request_digest',
        next_ordinal,completion_time,result,evidence);
    IF pg_catalog.OCTET_LENGTH(snapshot) > 1048576 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
    VALUES(analysis,observation,next_ordinal,source_analysis,p_request ->> 'request_digest',result,evidence,completion_time);
    INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
    VALUES(observation,analysis,initial_authority);
    IF NOT history.selection_initialized THEN
        UPDATE internal.observation_histories SET selected_analysis_id=analysis,selection_initialized=TRUE,
            state_revision=1,active_projection=projection WHERE observation_id=observation;
        INSERT INTO internal.observation_history_reconciliation(observation_id,state_revision,selected_analysis_id,changed_analysis_id)
        VALUES(observation,1,analysis,analysis);
    END IF;
    -- Initialized observations only gain a child: no selection/review/credit
    -- changes and no reconciliation receipt that could reinstall old authority.
    RETURN snapshot;
END;
$$;

REVOKE ALL ON FUNCTION internal.admit_protected_observation_analysis(UUID,JSONB,TEXT),internal.append_protected_observation_analysis(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve V1 serialization byte-for-byte; V2 never masquerades as a V1 snapshot.
CREATE OR REPLACE FUNCTION internal.observation_analysis_snapshot(
    observation UUID, analysis UUID, source_analysis UUID, digest TEXT, ordinal INTEGER,
    completed TIMESTAMPTZ, result JSONB, evidence JSONB
) RETURNS TEXT LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT pg_catalog.JSONB_BUILD_OBJECT(
        'schema_version',CASE WHEN evidence->'schema_version'='2'::JSONB THEN 2 ELSE 1 END,'observation_id',observation,'analysis_id',analysis,
        'ordinal',ordinal,'source_analysis_id',source_analysis,'request_digest',digest,
        'completed_at_ms',pg_catalog.FLOOR(EXTRACT(EPOCH FROM completed) * 1000),
        'result',result,'evidence_manifest',evidence)::TEXT;
$$;

-- Alphabetically follows guard_observation_analysis_generation, which already
-- owns owner and observation-generation locks even on direct result INSERT.
CREATE OR REPLACE FUNCTION internal.guard_observation_media_binding()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
    IF NEW.evidence_manifest->'schema_version'='2'::JSONB THEN
        SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id AND observation_id=NEW.observation_id;
        IF NOT FOUND OR saved.state<>'draft' OR saved.input_snapshot->'schema_version' IS DISTINCT FROM '2'::JSONB
            OR saved.draft->'result_snapshot' IS DISTINCT FROM NEW.result_snapshot
            OR saved.input_snapshot->'evidence_manifest' IS DISTINCT FROM NEW.evidence_manifest
            OR current_setting('merian.observation_analysis_completion',TRUE) IS DISTINCT FROM saved.owner_id::TEXT || ':' || NEW.analysis_id::TEXT THEN
            RAISE EXCEPTION 'analysis_history_completion_required' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_protected_analysis_evidence(saved.owner_id,NEW.observation_id,NEW.analysis_id,NEW.evidence_manifest,FALSE);
    ELSIF EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;

-- Protect admitted/result evidence from independent expiry or receipt deletion.
-- Observation deletion/detachment always wins, including either cascade order.
CREATE FUNCTION internal.guard_bound_observation_evidence_delete()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM id FROM public.users WHERE id=OLD.owner_id FOR UPDATE;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || OLD.observation_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND user_id=OLD.owner_id AND NOT is_tombstoned)
        AND EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=OLD.observation_id)
        AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id)
        AND (EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=OLD.analysis_id AND state<>'failed_terminal')
            OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=OLD.analysis_id)) THEN
        RAISE EXCEPTION 'analysis_history_evidence_bound' USING ERRCODE='55000';
    END IF;
    RETURN OLD;
END;
$$;
CREATE TRIGGER guard_bound_observation_evidence_delete BEFORE DELETE ON internal.observation_evidence_objects FOR EACH ROW EXECUTE FUNCTION internal.guard_bound_observation_evidence_delete();

CREATE FUNCTION internal.retire_analysis_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP='DELETE' THEN
        DELETE FROM internal.observation_evidence_objects WHERE analysis_id=OLD.analysis_id;
        RETURN OLD;
    END IF;
    IF NEW.state='failed_terminal' AND OLD.state<>'failed_terminal' THEN
        DELETE FROM internal.observation_evidence_objects WHERE analysis_id=NEW.analysis_id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER retire_analysis_evidence AFTER DELETE OR UPDATE ON internal.observation_analysis_intents FOR EACH ROW EXECUTE FUNCTION internal.retire_analysis_evidence();

CREATE FUNCTION internal.expire_unbound_observation_evidence(p_media UUID)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects;
BEGIN
    SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=p_media;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    PERFORM id FROM public.users WHERE id=saved.owner_id FOR UPDATE;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || saved.observation_id::TEXT,0::BIGINT));
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || saved.analysis_id::TEXT,0::BIGINT));
    DELETE FROM internal.observation_evidence_objects WHERE media_id=p_media AND object_id=saved.object_id AND owner_id=saved.owner_id
        AND observation_id=saved.observation_id AND analysis_id=saved.analysis_id AND expires_at<=clock_timestamp()
        AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=saved.analysis_id)
        AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=saved.analysis_id);
    RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_bound_observation_evidence_delete(),internal.retire_analysis_evidence(),internal.expire_unbound_observation_evidence(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Extend shared completion, not the credit policy. Source anchors fail closed
-- on drift. Legacy V1 admissions/appends/reader decoding remain unchanged.
DO $patch$
DECLARE definition TEXT; fragment TEXT;
BEGIN
    definition:=pg_get_functiondef('internal.complete_observation_analysis(uuid,uuid,uuid)'::regprocedure);
    fragment:='    snapshot:=internal.append_observation_analysis(p_owner,saved.draft);';
    IF (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_media_source_drift'; END IF;
    EXECUTE replace(definition,fragment,$new$
    IF saved.input_snapshot->'schema_version'='2'::JSONB THEN
        snapshot:=internal.append_protected_observation_analysis(p_owner,saved.draft);
    ELSE snapshot:=internal.append_observation_analysis(p_owner,saved.draft); END IF;
$new$);
    definition:=pg_get_functiondef('internal.guard_funded_observation_evidence()'::regprocedure);
    fragment:='    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id) THEN';
    IF (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_media_source_drift'; END IF;
    EXECUTE replace(definition,fragment,'    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.analysis_id) OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id) THEN');
    -- Deny an entire mixed history to protocol 7, even if a cursor happens to
    -- avoid V2 rows. Ownership checks precede the compatibility disclosure.
    definition:=pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    fragment:='    FOR result_row IN SELECT * FROM internal.observation_analysis_results';
    IF (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_media_source_drift'; END IF;
    EXECUTE replace(definition,fragment,$new$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='2'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
$new$ || fragment);
END;
$patch$;

RESET statement_timeout;
RESET lock_timeout;
