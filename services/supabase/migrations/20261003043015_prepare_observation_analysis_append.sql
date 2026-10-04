SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN append_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Blank migrated history never establishes permission to choose an identity.
-- A future new-observation admission owner must prove creation eligibility when
-- inserting the history. Existing and legacy rows retain the false default.
ALTER TABLE internal.observation_histories
    ADD COLUMN initial_selection_permitted BOOLEAN NOT NULL DEFAULT FALSE;
CREATE FUNCTION internal.reject_observation_initial_selection_eligibility_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF NEW.initial_selection_permitted IS DISTINCT FROM OLD.initial_selection_permitted THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.reject_observation_initial_selection_eligibility_update() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER reject_observation_initial_selection_eligibility_update BEFORE UPDATE ON internal.observation_histories
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_initial_selection_eligibility_update();

-- This is a private storage primitive, NOT a funded completion orchestrator.
-- No API role has execution permission. A future orchestrator must validate its
-- admitted intent and provider result, call this inside the settlement transaction,
-- and only then return success. No live caller or settlement bypass is added here.
CREATE FUNCTION internal.append_observation_analysis(p_user_id UUID, p_request JSONB)
RETURNS TEXT LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    observation UUID; analysis UUID; source_analysis UUID; resolved_species UUID;
    history internal.observation_histories; saved internal.observation_analysis_results;
    evidence JSONB; result JSONB; item JSONB; descriptor JSONB; text_value TEXT;
    initial_authority JSONB := '{"confirmed_species_identity":null,"confirmed_species_identity_revision":0,"confirmed_species_id":null,"user_identification_override":null,"user_confirmed_identification":false,"user_review_state":"unreviewed","ai_identification_review":null}'::JSONB;
    projection JSONB; next_ordinal INTEGER; completion_time TIMESTAMPTZ; snapshot TEXT;
    scientific_name TEXT; needs_species BOOLEAN;
BEGIN
    IF p_user_id IS NULL OR pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object'
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','result_snapshot','evidence_manifest'])
        OR p_request - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','result_snapshot','evidence_manifest'] <> '{}'::JSONB
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
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
    IF (SELECT append_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
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
    IF pg_catalog.JSONB_TYPEOF(evidence) IS DISTINCT FROM 'object'
        OR NOT (evidence ?& ARRAY['schema_version','captured_media'])
        OR evidence - ARRAY['schema_version','captured_media'] <> '{}'::JSONB
        OR evidence -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR pg_catalog.JSONB_TYPEOF(evidence -> 'captured_media') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.JSONB_ARRAY_LENGTH(evidence -> 'captured_media') NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    -- Public CDN URLs, staging keys and signed URLs are NOT private evidence.
    -- No media variant can pass until protected promotion/read/cleanup exists.
    FOR item IN SELECT value FROM pg_catalog.JSONB_ARRAY_ELEMENTS(evidence -> 'captured_media') LOOP
        IF pg_catalog.JSONB_TYPEOF(item) IS DISTINCT FROM 'object'
            OR NOT (item ? 'description') OR item - 'description' <> '{}'::JSONB
            OR pg_catalog.JSONB_TYPEOF(item -> 'description') IS DISTINCT FROM 'object'
            OR NOT (item -> 'description' ? '_0') OR (item -> 'description') - '_0' <> '{}'::JSONB THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        descriptor := item #> '{description,_0}';
        IF pg_catalog.JSONB_TYPEOF(descriptor) IS DISTINCT FROM 'object'
            OR NOT (descriptor ? 'freeText') OR descriptor - 'freeText' <> '{}'::JSONB
            OR pg_catalog.JSONB_TYPEOF(descriptor -> 'freeText') IS DISTINCT FROM 'string'
            OR pg_catalog.CHAR_LENGTH(descriptor ->> 'freeText') NOT BETWEEN 1 AND 8192
            OR pg_catalog.BTRIM(descriptor ->> 'freeText') = '' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
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
REVOKE ALL ON FUNCTION internal.append_observation_analysis(UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION internal.append_observation_analysis(UUID, JSONB) IS
    'Closed description-only history append storage primitive; no endpoint, provider completion, funding settlement, enrollment or private media delivery. Exact result replay is fenced by current owner and deletion.';

RESET statement_timeout;
RESET lock_timeout;
