SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Inert audio storage foundation. No audio admission or provider execution.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN prepared_audio_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_audio_evidence_upload_cohorts (
    analysis_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    media_id UUID NOT NULL UNIQUE,
    object_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL CHECK(content_type='audio/wav'),
    byte_count INTEGER NOT NULL CHECK(byte_count BETWEEN 46 AND 2700000),
    sha256 TEXT NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (clock_timestamp()+INTERVAL '5 minutes'),
    CHECK(analysis_id<>observation_id AND media_id NOT IN (analysis_id,observation_id)),
    CHECK(object_id NOT IN (owner_id,observation_id,analysis_id,media_id))
);
CREATE INDEX observation_audio_evidence_cohorts_parent ON internal.observation_audio_evidence_upload_cohorts(observation_id);
CREATE INDEX observation_audio_evidence_cohorts_due ON internal.observation_audio_evidence_upload_cohorts(expires_at,analysis_id);
ALTER TABLE internal.observation_audio_evidence_upload_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_audio_evidence_upload_cohorts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_audio_upload_cohort BEFORE UPDATE ON internal.observation_audio_evidence_upload_cohorts
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_upload_cohort();
ALTER TABLE internal.observation_evidence_objects DROP CONSTRAINT observation_evidence_objects_content_type_check;
ALTER TABLE internal.observation_evidence_objects ADD CONSTRAINT observation_evidence_objects_content_type_check
    CHECK(content_type IN ('image/jpeg','image/png','image/heic','audio/mp4','video/mp4','audio/wav'));


CREATE OR REPLACE FUNCTION internal.reserve_observation_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_content_type TEXT,p_bytes INTEGER,p_sha256 TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects; candidate UUID; audio internal.observation_audio_evidence_upload_cohorts;
BEGIN
    IF p_analysis IS NULL OR p_media IS NULL OR p_analysis=p_observation OR p_media IN (p_analysis,p_observation)
        OR p_content_type IS NULL OR p_content_type NOT IN ('image/jpeg','image/png','image/heic','audio/mp4','video/mp4','audio/wav')
        OR p_bytes IS NULL OR p_bytes NOT BETWEEN 1 AND 33554432 OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    SELECT * INTO audio FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis;
    IF FOUND THEN
        IF audio.owner_id<>p_owner OR audio.observation_id<>p_observation OR audio.media_id<>p_media
            OR audio.content_type<>p_content_type OR audio.byte_count<>p_bytes OR audio.sha256<>p_sha256 THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF audio.expires_at<=clock_timestamp() OR
            (SELECT prepared_audio_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
    ELSIF p_content_type='audio/wav' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=p_media;
    IF FOUND THEN
        IF saved.observation_id<>p_observation OR saved.analysis_id<>p_analysis OR saved.owner_id<>p_owner
            OR saved.content_type<>p_content_type OR saved.byte_count<>p_bytes OR saved.sha256<>p_sha256 THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF saved.ready_at IS NULL AND saved.expires_at<=clock_timestamp() THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        RETURN to_jsonb(saved);
    END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-history-evidence:' || p_analysis::TEXT,0::BIGINT));
    -- Analysis intents are not implemented yet. Bind only an unused analysis
    -- identity; the future admitted producer must prove intent ownership too.
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis AND observation_id<>p_observation)
        OR (SELECT count(*) FROM internal.observation_evidence_objects WHERE observation_id=p_observation AND analysis_id=p_analysis)>=64 THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- Never reuse an opaque key retained by an erasure marker. The bounded
    -- allocator also serializes the exceedingly rare random-ID collision.
    FOR attempt IN 1..4 LOOP
        candidate := COALESCE(audio.object_id,gen_random_uuid());
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-history-object:' || candidate::TEXT,0::BIGINT));
        EXIT WHEN candidate NOT IN (p_owner,p_observation,p_analysis,p_media)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE object_id=candidate)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=candidate);
        IF audio.object_id IS NOT NULL OR attempt=4 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    END LOOP;
    INSERT INTO internal.observation_evidence_objects(media_id,observation_id,analysis_id,owner_id,content_type,byte_count,sha256,object_id)
    VALUES(p_media,p_observation,p_analysis,p_owner,p_content_type,p_bytes,p_sha256,candidate) RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;

CREATE OR REPLACE FUNCTION internal.guard_observation_upload_receipt()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE cohort internal.observation_evidence_upload_cohorts; audio internal.observation_audio_evidence_upload_cohorts;
BEGIN
    SELECT * INTO cohort FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id;
    IF FOUND THEN
        IF cohort.owner_id<>NEW.owner_id OR cohort.observation_id<>NEW.observation_id
            OR cohort.expires_at<=clock_timestamp() OR NOT EXISTS(
                SELECT 1 FROM pg_catalog.jsonb_array_elements(cohort.items) item
                WHERE item=jsonb_build_object('media_id',NEW.media_id,'content_type',NEW.content_type,
                    'byte_count',NEW.byte_count,'sha256',NEW.sha256)) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        NEW.expires_at:=cohort.expires_at;
    END IF;
    SELECT * INTO audio FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id;
    IF FOUND THEN
        IF cohort.analysis_id IS NOT NULL OR audio.owner_id<>NEW.owner_id OR audio.observation_id<>NEW.observation_id
            OR audio.media_id<>NEW.media_id OR audio.object_id<>NEW.object_id OR audio.content_type<>NEW.content_type
            OR audio.byte_count<>NEW.byte_count OR audio.sha256<>NEW.sha256 OR audio.expires_at<=clock_timestamp()
            OR EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=audio.object_id) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        NEW.expires_at:=audio.expires_at;
    ELSIF NEW.content_type='audio/wav' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.complete_observation_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis) AND
        ((SELECT prepared_audio_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
        OR NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis
            AND owner_id=p_owner AND observation_id=p_observation AND media_id=p_media AND object_id=p_object AND expires_at>clock_timestamp())) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.observation_evidence_objects
        WHERE media_id=p_media AND observation_id=p_observation AND analysis_id=p_analysis AND owner_id=p_owner AND object_id=p_object FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF saved.ready_at IS NULL THEN
        IF saved.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
        UPDATE internal.observation_evidence_objects SET ready_at=clock_timestamp() WHERE media_id=p_media RETURNING * INTO saved;
    END IF;
    RETURN to_jsonb(saved);
END;
$$;

CREATE OR REPLACE FUNCTION public.reserve_owned_observation_evidence_cohort(p_owner UUID,p_observation UUID,p_analysis UUID,p_items JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE item JSONB; total_bytes BIGINT:=0; seen UUID[]:='{}'::UUID[]; media UUID;
    saved internal.observation_evidence_upload_cohorts; receipts JSONB:='[]'::JSONB; receipt JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_observation IS NULL OR p_analysis IS NULL OR p_analysis=p_observation
        OR p_items IS NULL OR jsonb_typeof(p_items)<>'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(p_items) NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) LOOP
        IF jsonb_typeof(item)<>'object' OR item-ARRAY['media_id','content_type','byte_count','sha256']<>'{}'
            OR NOT(item ?& ARRAY['media_id','content_type','byte_count','sha256'])
            OR jsonb_typeof(item->'media_id') IS DISTINCT FROM 'string'
            OR (item->>'media_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            OR jsonb_typeof(item->'content_type') IS DISTINCT FROM 'string'
            OR (item->>'content_type') NOT IN ('image/jpeg','image/png')
            OR jsonb_typeof(item->'byte_count') IS DISTINCT FROM 'number'
            OR (item->>'byte_count') !~ '^[1-9][0-9]{0,6}$'
            OR jsonb_typeof(item->'sha256') IS DISTINCT FROM 'string'
            OR (item->>'sha256') !~ '^[0-9a-f]{64}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        media:=(item->>'media_id')::UUID;
        IF media IN (p_observation,p_analysis) OR media=ANY(seen) THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        seen:=array_append(seen,media);
        total_bytes:=total_bytes+(item->>'byte_count')::BIGINT;
    END LOOP;
    IF total_bytes>5242880 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO saved FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis;
    IF FOUND THEN
        IF saved.owner_id<>p_owner OR saved.observation_id<>p_observation OR saved.items<>p_items THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF saved.expires_at<=clock_timestamp() AND NOT EXISTS(
            SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
        -- Missing receipts mean cleanup won. Never allocate replacement keys.
        IF (SELECT count(*) FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)<>jsonb_array_length(p_items) THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
    ELSE
        IF EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)
            OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis)
            OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items)
        VALUES(p_analysis,p_observation,p_owner,p_items) RETURNING * INTO saved;
    END IF;
    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) LOOP
        receipt:=internal.reserve_observation_evidence(p_owner,p_observation,p_analysis,(item->>'media_id')::UUID,
            item->>'content_type',(item->>'byte_count')::INTEGER,item->>'sha256');
        receipts:=receipts||jsonb_build_array(receipt);
    END LOOP;
    RETURN receipts;
END;
$$;

CREATE OR REPLACE FUNCTION internal.guard_observation_upload_analysis()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||NEW.analysis_id::TEXT,0::BIGINT));
    -- Audio identity stays reserved even after expired receipt cleanup.
    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
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
    -- Audio identity stays reserved even after expired receipt cleanup.
    IF EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
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

CREATE OR REPLACE FUNCTION internal.fence_observation_upload_cohort()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_evidence_upload_cohorts WHERE observation_id=NEW.scan_id;
    DELETE FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;

-- Exact tuple is supplied only by trusted byte-verifying storage orchestration.
CREATE FUNCTION public.reserve_owned_observation_audio_evidence_cohort(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_bytes INTEGER,p_sha256 TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_audio_evidence_upload_cohorts;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT prepared_audio_evidence_enabled AND media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF p_analysis IS NULL OR p_media IS NULL OR p_analysis=p_observation OR p_media IN(p_observation,p_analysis)
        OR p_bytes IS NULL OR p_bytes NOT BETWEEN 46 AND 2700000 OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO saved FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis;
    IF FOUND THEN
        IF saved.owner_id<>p_owner OR saved.observation_id<>p_observation OR saved.media_id<>p_media
            OR saved.byte_count<>p_bytes OR saved.sha256<>p_sha256 THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF saved.expires_at<=clock_timestamp() OR NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects
            WHERE analysis_id=p_analysis AND media_id=p_media AND object_id=saved.object_id) THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
    ELSE
        IF EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,observation_id,owner_id,media_id,content_type,byte_count,sha256)
        VALUES(p_analysis,p_observation,p_owner,p_media,'audio/wav',p_bytes,p_sha256) RETURNING * INTO saved;
    END IF;
    RETURN internal.reserve_observation_evidence(p_owner,p_observation,p_analysis,p_media,'audio/wav',p_bytes,p_sha256);
END;
$$;

CREATE FUNCTION public.complete_owned_observation_audio_evidence_upload(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT prepared_audio_evidence_enabled AND media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    IF NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts
        WHERE analysis_id=p_analysis AND observation_id=p_observation AND owner_id=p_owner AND media_id=p_media AND object_id=p_object
            AND expires_at>clock_timestamp()) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN internal.complete_observation_evidence(p_owner,p_observation,p_analysis,p_media,p_object);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_audio_evidence_cohort(UUID,UUID,UUID,UUID,INTEGER,TEXT),
    public.complete_owned_observation_audio_evidence_upload(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_audio_evidence_cohort(UUID,UUID,UUID,UUID,INTEGER,TEXT),
    public.complete_owned_observation_audio_evidence_upload(UUID,UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.reserve_owned_observation_audio_evidence_cohort(uuid,uuid,uuid,uuid,integer,text)','Freeze one exact verified WAV cohort, opaque object and fixed deadline without inference admission.'),
('service_role','public.complete_owned_observation_audio_evidence_upload(uuid,uuid,uuid,uuid,uuid)','Acknowledge the original audio object after trusted write-once verification.');


CREATE OR REPLACE FUNCTION public.retire_expired_observation_evidence()
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE candidate RECORD; cohort internal.observation_evidence_upload_cohorts; retired INTEGER:=0; audio internal.observation_audio_evidence_upload_cohorts;
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RETURN 0;
    END IF;
    SELECT due.* INTO candidate FROM (
        SELECT c.owner_id,c.observation_id,c.analysis_id,NULL::UUID AS media_id,c.expires_at
        FROM internal.observation_evidence_upload_cohorts c
        WHERE c.expires_at<=clock_timestamp()
            AND internal.valid_observation_erasure_cohort_items(c.items)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=c.analysis_id
                AND (e.owner_id<>c.owner_id OR e.observation_id<>c.observation_id OR e.expires_at<>c.expires_at
                    OR NOT(c.items @> jsonb_build_array(jsonb_build_object('media_id',e.media_id,'content_type',e.content_type,'byte_count',e.byte_count,'sha256',e.sha256)))))
            AND EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=c.analysis_id)
        UNION ALL
        SELECT a.owner_id,a.observation_id,a.analysis_id,a.media_id,a.expires_at
        FROM internal.observation_audio_evidence_upload_cohorts a
        JOIN internal.observation_evidence_objects e ON e.analysis_id=a.analysis_id AND e.media_id=a.media_id
            AND e.owner_id=a.owner_id AND e.observation_id=a.observation_id AND e.object_id=a.object_id
            AND e.content_type=a.content_type AND e.byte_count=a.byte_count AND e.sha256=a.sha256 AND e.expires_at=a.expires_at
        WHERE a.expires_at<=clock_timestamp()
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects extra WHERE extra.analysis_id=a.analysis_id AND extra.media_id<>a.media_id)
        UNION ALL
        SELECT e.owner_id,e.observation_id,e.analysis_id,e.media_id,e.expires_at
        FROM internal.observation_evidence_objects e
        WHERE e.expires_at<=clock_timestamp()
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts c WHERE c.analysis_id=e.analysis_id)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts a WHERE a.analysis_id=e.analysis_id)
    ) due
    WHERE NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.analysis_id=due.analysis_id)
        AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.analysis_id=due.analysis_id)
        AND EXISTS(SELECT 1 FROM public.scans s WHERE s.id=due.observation_id AND s.user_id=due.owner_id AND NOT s.is_tombstoned)
        AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones t WHERE t.scan_id=due.observation_id)
    ORDER BY due.expires_at,due.analysis_id,due.media_id NULLS FIRST LIMIT 1;
    IF NOT FOUND THEN RETURN 0; END IF;

    PERFORM internal.lock_owned_observation_evidence(candidate.owner_id,candidate.observation_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||candidate.analysis_id::TEXT,0::BIGINT));
    IF (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=candidate.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=candidate.analysis_id) THEN
        RETURN 0;
    END IF;
    SELECT * INTO audio FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=candidate.analysis_id FOR UPDATE;
    IF FOUND THEN
        IF audio.owner_id<>candidate.owner_id OR audio.observation_id<>candidate.observation_id
            OR audio.media_id IS DISTINCT FROM candidate.media_id OR audio.expires_at>clock_timestamp() THEN RETURN 0; END IF;
        PERFORM media_id FROM internal.observation_evidence_objects WHERE analysis_id=audio.analysis_id FOR UPDATE;
        IF EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=audio.analysis_id
            AND (e.media_id<>audio.media_id OR e.owner_id<>audio.owner_id OR e.observation_id<>audio.observation_id
                OR e.object_id<>audio.object_id OR e.content_type<>audio.content_type OR e.byte_count<>audio.byte_count
                OR e.sha256<>audio.sha256 OR e.expires_at<>audio.expires_at)) THEN RETURN 0; END IF;
        DELETE FROM internal.observation_evidence_objects WHERE analysis_id=audio.analysis_id;
        GET DIAGNOSTICS retired=ROW_COUNT;
        -- Keep audio identity, bytes, object and expiry permanently until parent deletion.
        RETURN retired;
    END IF;
    SELECT * INTO cohort FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=candidate.analysis_id FOR UPDATE;
    IF candidate.media_id IS NULL THEN
        IF NOT FOUND OR cohort.owner_id<>candidate.owner_id OR cohort.observation_id<>candidate.observation_id
            OR cohort.expires_at>clock_timestamp() THEN RETURN 0; END IF;
        IF NOT internal.valid_observation_erasure_cohort_items(cohort.items) THEN RETURN 0; END IF;
        PERFORM media_id FROM internal.observation_evidence_objects WHERE analysis_id=candidate.analysis_id FOR UPDATE;
        -- Partial extant cohorts may be cleaned, but no unrelated receipt or
        -- altered deadline can be interpreted as part of the original set.
        IF EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=candidate.analysis_id
            AND (e.owner_id<>cohort.owner_id OR e.observation_id<>cohort.observation_id OR e.expires_at<>cohort.expires_at
                OR NOT(cohort.items @> jsonb_build_array(jsonb_build_object('media_id',e.media_id,'content_type',e.content_type,'byte_count',e.byte_count,'sha256',e.sha256))))) THEN
            RETURN 0;
        END IF;
        DELETE FROM internal.observation_evidence_objects WHERE analysis_id=candidate.analysis_id;
        GET DIAGNOSTICS retired=ROW_COUNT;
        -- Keep cohort/items/expiry. Missing receipts must never mint new keys.
    ELSE
        IF FOUND THEN RETURN 0; END IF;
        DELETE FROM internal.observation_evidence_objects
        WHERE media_id=candidate.media_id AND analysis_id=candidate.analysis_id
            AND owner_id=candidate.owner_id AND observation_id=candidate.observation_id AND expires_at<=clock_timestamp();
        GET DIAGNOSTICS retired=ROW_COUNT;
    END IF;
    RETURN retired;
EXCEPTION WHEN SQLSTATE 'P0002' THEN
    -- Parent/account deletion won after discovery; its cascade owns cleanup.
    RETURN 0;
END;
$$;

RESET statement_timeout;
RESET lock_timeout;
