SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Keep the immutable set and deadline after expired receipt cleanup. Neither a
-- lost upload response nor cleanup may turn an old analysis ID into new consent.
CREATE TABLE internal.observation_evidence_upload_cohorts (
    analysis_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    items JSONB NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 1 AND 5),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (clock_timestamp()+INTERVAL '5 minutes'),
    CHECK(analysis_id<>observation_id)
);
CREATE INDEX observation_evidence_upload_cohorts_parent ON internal.observation_evidence_upload_cohorts(observation_id);
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_evidence_upload_cohorts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_upload_cohort()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
END;
$$;
CREATE TRIGGER guard_observation_upload_cohort BEFORE UPDATE ON internal.observation_evidence_upload_cohorts
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_upload_cohort();

-- Also fence trusted primitive callers: a sealed cohort cannot grow through a
-- different entry point. The existing receipt update guard keeps this deadline.
CREATE FUNCTION internal.guard_observation_upload_receipt()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE cohort internal.observation_evidence_upload_cohorts;
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
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_observation_upload_receipt BEFORE INSERT ON internal.observation_evidence_objects
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_upload_receipt();

CREATE FUNCTION internal.fence_observation_upload_cohort()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_evidence_upload_cohorts WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER fence_observation_upload_cohort AFTER INSERT ON internal.scan_deletion_tombstones
FOR EACH ROW EXECUTE FUNCTION internal.fence_observation_upload_cohort();
REVOKE ALL ON FUNCTION internal.guard_observation_upload_cohort(),internal.guard_observation_upload_receipt(),
    internal.fence_observation_upload_cohort() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.reserve_owned_observation_evidence_cohort(p_owner UUID,p_observation UUID,p_analysis UUID,p_items JSONB)
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

CREATE FUNCTION public.complete_owned_observation_evidence_upload(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF NOT EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts
        WHERE analysis_id=p_analysis AND observation_id=p_observation AND owner_id=p_owner) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    RETURN internal.complete_observation_evidence(p_owner,p_observation,p_analysis,p_media,p_object);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_evidence_cohort(UUID,UUID,UUID,JSONB),
    public.complete_owned_observation_evidence_upload(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_evidence_cohort(UUID,UUID,UUID,JSONB),
    public.complete_owned_observation_evidence_upload(UUID,UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.reserve_owned_observation_evidence_cohort(uuid,uuid,uuid,jsonb)','Atomically freeze verified private reanalysis upload bytes, ordered cohort and deadline.'),
('service_role','public.complete_owned_observation_evidence_upload(uuid,uuid,uuid,uuid,uuid)','Acknowledge an exact cohort object only after trusted write-once byte verification.');
CREATE OR REPLACE FUNCTION internal.assert_protected_analysis_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_manifest JSONB,p_initial BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE item JSONB; media UUID; seen UUID[]:='{}'::UUID[]; total_bytes BIGINT:=0; saved internal.observation_evidence_objects; cohort internal.observation_evidence_upload_cohorts; image_items JSONB;
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
    SELECT * INTO cohort FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis;
    IF FOUND THEN
        SELECT jsonb_agg(value-'kind' ORDER BY ordinal) INTO image_items
        FROM pg_catalog.jsonb_array_elements(p_manifest->'items') WITH ORDINALITY AS entries(value,ordinal)
        WHERE value->>'kind'='image';
        IF cohort.owner_id<>p_owner OR cohort.observation_id<>p_observation OR cohort.items IS DISTINCT FROM image_items THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_protected_analysis_evidence(UUID,UUID,UUID,JSONB,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;


-- A cleaned-up photo cohort must not be rebound to description-only admission.
CREATE FUNCTION internal.guard_observation_upload_analysis()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||NEW.analysis_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        IF NEW.input_snapshot->'schema_version' IS DISTINCT FROM '2'::JSONB THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        PERFORM internal.assert_protected_analysis_evidence(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot->'evidence_manifest',TRUE);
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_observation_upload_analysis BEFORE INSERT ON internal.observation_analysis_intents
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_upload_analysis();
REVOKE ALL ON FUNCTION internal.guard_observation_upload_analysis() FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;
