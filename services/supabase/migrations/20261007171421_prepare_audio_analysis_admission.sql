SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN audio_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE;


-- Pure shape discriminator; full metadata and receipt validation follows below.
-- Imported schema-3 sentinels do not contain items and can never enter this path.
CREATE FUNCTION internal.is_audio_analysis_manifest(value JSONB)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT COALESCE(jsonb_typeof(value)='object' AND value->'schema_version'='3'::JSONB
   AND value ?& ARRAY['schema_version','items'] AND value-ARRAY['schema_version','items']='{}'::JSONB
   AND jsonb_typeof(value->'items')='array',FALSE);
$$;
REVOKE ALL ON FUNCTION internal.is_audio_analysis_manifest(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_audio_analysis_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_manifest JSONB,p_initial BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE item JSONB; media UUID; count_audio INTEGER:=0; text_units INTEGER:=0; units INTEGER;
    saved internal.observation_evidence_objects; cohort internal.observation_audio_evidence_upload_cohorts;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    IF NOT internal.is_audio_analysis_manifest(p_manifest) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF jsonb_array_length(p_manifest->'items') NOT BETWEEN 1 AND 64 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    SELECT * INTO cohort FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis FOR UPDATE;
    IF NOT FOUND OR cohort.owner_id<>p_owner OR cohort.observation_id<>p_observation
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(p_manifest->'items') LOOP
        IF item->>'kind'='description' THEN
            IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR NOT(item ?& ARRAY['kind','text']) OR item-ARRAY['kind','text']<>'{}'
                OR jsonb_typeof(item->'text') IS DISTINCT FROM 'string' OR char_length(item->>'text') NOT BETWEEN 1 AND 8192 OR btrim(item->>'text')='' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            SELECT COALESCE(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) INTO units FROM regexp_split_to_table(item->>'text','') c;
            text_units:=text_units+units;
            IF units>16384 OR text_units>32000 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        ELSIF item->>'kind'='audio' THEN
            count_audio:=count_audio+1;
            IF count_audio<>1 OR item IS DISTINCT FROM jsonb_build_object('kind','audio','media_id',cohort.media_id,
                'content_type','audio/wav','byte_count',cohort.byte_count,'sha256',cohort.sha256) THEN
                RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
            END IF;
            media:=cohort.media_id;
        ELSE RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    END LOOP;
    IF count_audio<>1 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=media FOR UPDATE;
    IF NOT FOUND OR saved.owner_id<>p_owner OR saved.observation_id<>p_observation OR saved.analysis_id<>p_analysis
        OR saved.object_id<>cohort.object_id OR saved.content_type<>cohort.content_type OR saved.byte_count<>cohort.byte_count
        OR saved.sha256<>cohort.sha256 OR saved.expires_at<>cohort.expires_at OR saved.ready_at IS NULL
        OR (p_initial AND cohort.expires_at<=clock_timestamp())
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis AND media_id<>media)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=cohort.object_id) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_audio_analysis_evidence(UUID,UUID,UUID,JSONB,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;


CREATE FUNCTION internal.admit_audio_observation_analysis(p_owner UUID,p_input JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID; analysis UUID; source UUID; saved internal.observation_analysis_intents;
    admitted RECORD; field TEXT; previous_fence TEXT;
BEGIN
    IF jsonb_typeof(p_input) IS DISTINCT FROM 'object'
        OR NOT (p_input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
        OR p_input - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
        OR p_input->'schema_version' IS DISTINCT FROM '3'::JSONB OR octet_length(p_input::TEXT)>1048576
        OR p_input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB
        OR p_input->'history_protocol' IS DISTINCT FROM '9'::JSONB
        OR p_input->>'expected_processor_permission' IS NULL OR p_input->>'expected_processor_permission'<>'google_gemini'
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
    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=analysis AND media_id=source) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
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
        IF (SELECT (admission_enabled AND protected_analysis_enabled AND audio_analysis_enabled) FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
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
        PERFORM internal.assert_audio_analysis_evidence(p_owner,observation,analysis,p_input->'evidence_manifest',TRUE);
        INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) VALUES(analysis,observation,p_owner,p_input);
    END IF;
    IF (SELECT (admission_enabled AND protected_analysis_enabled AND audio_analysis_enabled) FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_audio_analysis_evidence(p_owner,observation,analysis,p_input->'evidence_manifest',FALSE);
    previous_fence:=current_setting('merian.observation_analysis_admission',TRUE);
    PERFORM set_config('merian.observation_analysis_admission',p_owner::TEXT || ':' || analysis::TEXT,TRUE);
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(p_owner,'scan_identification',analysis,p_ip_hash,analysis,FALSE,
        (p_input->>'entitlement_protocol')::INTEGER,FALSE,'multimodal_audio_v1',p_input->>'expected_processor_permission',(p_input->>'identification_protocol')::INTEGER);
    PERFORM set_config('merian.observation_analysis_admission',COALESCE(previous_fence,''),TRUE);
    IF admitted.original_analysis_id IS DISTINCT FROM analysis OR admitted.reservation_state<>'reserved' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    UPDATE internal.observation_analysis_intents SET quota=to_jsonb(admitted) WHERE analysis_id=analysis RETURNING * INTO saved;
    RETURN to_jsonb(saved)-'draft';
END;
$$;

CREATE FUNCTION internal.append_audio_observation_analysis(p_user_id UUID, p_request JSONB)
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
        OR p_request -> 'schema_version' IS DISTINCT FROM '3'::JSONB
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
    IF (SELECT (append_enabled AND protected_analysis_enabled AND audio_analysis_enabled) FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
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
    PERFORM internal.assert_audio_analysis_evidence(p_user_id,observation,analysis,evidence,FALSE);
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

REVOKE ALL ON FUNCTION internal.admit_audio_observation_analysis(UUID,JSONB,TEXT),internal.append_audio_observation_analysis(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.guard_observation_upload_analysis()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||NEW.analysis_id::TEXT,0::BIGINT));
    -- Audio identity stays reserved even after expired receipt cleanup.
    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        IF NEW.input_snapshot->'schema_version' IS DISTINCT FROM '3'::JSONB THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        PERFORM internal.assert_audio_analysis_evidence(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot->'evidence_manifest',TRUE);
    ELSIF NEW.input_snapshot->'schema_version'='3'::JSONB THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        IF NEW.input_snapshot->'schema_version' IS DISTINCT FROM '2'::JSONB THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        PERFORM internal.assert_protected_analysis_evidence(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot->'evidence_manifest',TRUE);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.guard_observation_media_binding()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
    IF internal.is_audio_analysis_manifest(NEW.evidence_manifest) THEN
        SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id AND observation_id=NEW.observation_id;
        IF NOT FOUND OR saved.state<>'draft' OR saved.input_snapshot->'schema_version' IS DISTINCT FROM '3'::JSONB
            OR saved.draft->'result_snapshot' IS DISTINCT FROM NEW.result_snapshot
            OR saved.input_snapshot->'evidence_manifest' IS DISTINCT FROM NEW.evidence_manifest
            OR current_setting('merian.observation_analysis_completion',TRUE) IS DISTINCT FROM saved.owner_id::TEXT || ':' || NEW.analysis_id::TEXT THEN
            RAISE EXCEPTION 'analysis_history_completion_required' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_audio_analysis_evidence(saved.owner_id,NEW.observation_id,NEW.analysis_id,NEW.evidence_manifest,FALSE);
        RETURN NEW;
    ELSIF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
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

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$    IF p_input->'schema_version'='2'::JSONB THEN$old$;
BEGIN
 definition:=pg_get_functiondef('public.begin_owned_observation_analysis(uuid,jsonb,text)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_analysis_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$    IF p_input->'schema_version'='3'::JSONB THEN
        PERFORM internal.admit_audio_observation_analysis(p_owner,p_input,p_ip_hash);
    ELSIF p_input->'schema_version'='2'::JSONB THEN$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$AND (p_input->'schema_version'<>'2'::JSONB OR (protected_analysis_enabled AND media_enabled))$old$;
BEGIN
 definition:=pg_get_functiondef('public.begin_owned_observation_analysis(uuid,jsonb,text)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_analysis_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$AND (p_input->'schema_version'<>'2'::JSONB OR (protected_analysis_enabled AND media_enabled))
            AND (p_input->'schema_version'<>'3'::JSONB OR (protected_analysis_enabled AND media_enabled AND audio_analysis_enabled))$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$        IF evidence->'schema_version'='2'::JSONB THEN$old$;
BEGIN
 definition:=pg_get_functiondef('public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_analysis_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$        IF internal.is_audio_analysis_manifest(evidence) THEN
            PERFORM internal.assert_audio_analysis_evidence(p_owner,p_observation,p_analysis,evidence,FALSE);
            RETURN COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM internal.observation_evidence_objects e WHERE analysis_id=p_analysis AND owner_id=p_owner AND observation_id=p_observation),'[]'::JSONB);
        END IF;
        IF evidence->'schema_version'='2'::JSONB THEN$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$AND (saved.input_snapshot->'schema_version'<>'2'::JSONB OR (protected_analysis_enabled AND media_enabled))$old$;
BEGIN
 definition:=pg_get_functiondef('public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_analysis_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$AND (saved.input_snapshot->'schema_version'<>'2'::JSONB OR (protected_analysis_enabled AND media_enabled))
            AND (saved.input_snapshot->'schema_version'<>'3'::JSONB OR (protected_analysis_enabled AND media_enabled AND audio_analysis_enabled))$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$        IF saved.input_snapshot->'schema_version'='2'::JSONB THEN$old$;
BEGIN
 definition:=pg_get_functiondef('public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_analysis_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$        IF saved.input_snapshot->'schema_version'='3'::JSONB THEN
            PERFORM internal.assert_audio_analysis_evidence(p_owner,p_observation,p_analysis,saved.input_snapshot->'evidence_manifest',FALSE);
        END IF;
        IF saved.input_snapshot->'schema_version'='2'::JSONB THEN$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$    IF saved.input_snapshot->'schema_version'='2'::JSONB THEN$old$;
BEGIN
 definition:=pg_get_functiondef('internal.complete_observation_analysis(uuid,uuid,uuid)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_analysis_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$    IF saved.input_snapshot->'schema_version'='3'::JSONB THEN
        snapshot:=internal.append_audio_observation_analysis(p_owner,saved.draft);
    ELSIF saved.input_snapshot->'schema_version'='2'::JSONB THEN$new$);
END;
$patch$;


ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT observation_analysis_origin;

ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_origin CHECK ((
    CASE WHEN internal.is_audio_analysis_manifest(evidence_manifest) THEN
        request_digest IS NOT NULL AND completed_at IS NOT NULL
    WHEN evidence_manifest->'schema_version'='3'::JSONB THEN
        request_digest IS NULL AND completed_at IS NULL AND source_analysis_id IS NULL AND ordinal=1
        AND evidence_manifest ?& ARRAY['schema_version','origin','imported_at_ms','availability']
        AND evidence_manifest-ARRAY['schema_version','origin','imported_at_ms','availability']='{}'::JSONB
        AND evidence_manifest->>'origin'='saved_identification'
        AND evidence_manifest->>'availability'='unavailable'
        AND pg_catalog.jsonb_typeof(evidence_manifest->'imported_at_ms')='number'
        AND (evidence_manifest->>'imported_at_ms') ~ '^[0-9]{1,16}$'
        AND (evidence_manifest->>'imported_at_ms')::NUMERIC BETWEEN 0 AND 8640000000000000
    WHEN evidence_manifest->'schema_version' IN ('1'::JSONB,'2'::JSONB)
        THEN request_digest IS NOT NULL AND completed_at IS NOT NULL
    ELSE FALSE END) IS TRUE
);

CREATE OR REPLACE FUNCTION internal.observation_analysis_snapshot(
    observation UUID, analysis UUID, source_analysis UUID, digest TEXT, ordinal INTEGER,
    completed TIMESTAMPTZ, result JSONB, evidence JSONB
) RETURNS TEXT LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT pg_catalog.jsonb_build_object(
        'schema_version',CASE WHEN internal.is_audio_analysis_manifest(evidence) THEN 4
            WHEN evidence->'schema_version'='3'::JSONB THEN 3
            WHEN evidence->'schema_version'='2'::JSONB THEN 2 ELSE 1 END,
        'observation_id',observation,'analysis_id',analysis,'ordinal',ordinal,
        'source_analysis_id',source_analysis,'request_digest',digest,
        'completed_at_ms',pg_catalog.floor(EXTRACT(EPOCH FROM completed)*1000),
        'result',result,'evidence_manifest',evidence)::TEXT;
$$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$p_reader NOT IN (7,8,9)$old$;
BEGIN
 definition:=pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$p_reader NOT IN (7,8,9,10)$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$    IF p_reader<9 AND EXISTS$old$;
BEGIN
 definition:=pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$    IF p_reader<10 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND internal.is_audio_analysis_manifest(evidence_manifest)) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
    IF p_reader<9 AND EXISTS$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$(p_reader=9 AND result_row.evidence_manifest -> 'schema_version' = '3'::JSONB)$old$;
BEGIN
 definition:=pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$(p_reader>=9 AND result_row.evidence_manifest -> 'schema_version' = '3'::JSONB AND NOT internal.is_audio_analysis_manifest(result_row.evidence_manifest))
                OR (p_reader=10 AND internal.is_audio_analysis_manifest(result_row.evidence_manifest))$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$p_reader IS DISTINCT FROM 9$old$;
BEGIN
 definition:=pg_get_functiondef('public.get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$(p_reader IS NULL OR p_reader NOT IN (9,10))$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$    target := COALESCE(target,history.selected_analysis_id);$old$;
BEGIN
 definition:=pg_get_functiondef('public.get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$    IF p_reader<10 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND internal.is_audio_analysis_manifest(evidence_manifest)) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
    target := COALESCE(target,history.selected_analysis_id);$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$evidence_manifest->'schema_version'='3'::JSONB$old$;
BEGIN
 definition:=pg_get_functiondef('public.enroll_owned_observation_history(uuid,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$evidence_manifest->'schema_version'='3'::JSONB AND evidence_manifest->>'origin'='saved_identification' AND NOT internal.is_audio_analysis_manifest(evidence_manifest)$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$evidence_manifest->'schema_version'='3'::JSONB$old$;
BEGIN
 definition:=pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$evidence_manifest->'schema_version'='3'::JSONB AND evidence_manifest->>'origin'='saved_identification' AND NOT internal.is_audio_analysis_manifest(evidence_manifest)$new$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT:=$old$OLD.evidence_manifest->'schema_version'='3'::JSONB$old$;
BEGIN
 definition:=pg_get_functiondef('internal.fence_imported_observation_result()'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'audio_reader_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$OLD.evidence_manifest->'schema_version'='3'::JSONB AND OLD.evidence_manifest->>'origin'='saved_identification' AND NOT internal.is_audio_analysis_manifest(OLD.evidence_manifest)$new$);
END;
$patch$;

COMMENT ON COLUMN internal.observation_history_rollout.audio_analysis_enabled IS 'Default-off input3 audio admission/dispatch/append. Upload permission alone never authorizes inference.';
RESET statement_timeout;
RESET lock_timeout;
