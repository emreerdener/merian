SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN private_evidence_erasure_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX observation_evidence_upload_cohorts_due
    ON internal.observation_evidence_upload_cohorts(expires_at,analysis_id);
CREATE INDEX observation_evidence_objects_analysis
    ON internal.observation_evidence_objects(analysis_id,expires_at,media_id);
CREATE INDEX observation_evidence_objects_due
    ON internal.observation_evidence_objects(expires_at,media_id);

-- Non-throwing immutable shape predicate shared by discovery and locked recheck.
CREATE FUNCTION internal.valid_observation_erasure_cohort_items(p_items JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN RETURN FALSE; END IF;
    IF jsonb_array_length(p_items) NOT BETWEEN 1 AND 5 THEN RETURN FALSE; END IF;
        IF EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(p_items) item
            WHERE CASE WHEN jsonb_typeof(item) IS DISTINCT FROM 'object' THEN TRUE ELSE
                NOT(item ?& ARRAY['media_id','content_type','byte_count','sha256'])
                OR item-ARRAY['media_id','content_type','byte_count','sha256']<>'{}'
                OR jsonb_typeof(item->'media_id') IS DISTINCT FROM 'string'
                OR (item->>'media_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                OR jsonb_typeof(item->'content_type') IS DISTINCT FROM 'string'
                OR (item->>'content_type') NOT IN ('image/jpeg','image/png')
                OR jsonb_typeof(item->'byte_count') IS DISTINCT FROM 'number'
                OR (item->>'byte_count') !~ '^[1-9][0-9]{0,6}$'
                OR jsonb_typeof(item->'sha256') IS DISTINCT FROM 'string'
                OR (item->>'sha256') !~ '^[0-9a-f]{64}$' END)
            OR (SELECT count(DISTINCT item->>'media_id') FROM pg_catalog.jsonb_array_elements(p_items) item)<>jsonb_array_length(p_items) THEN
            RETURN FALSE;
        END IF;
    RETURN (SELECT sum((item->>'byte_count')::BIGINT) FROM pg_catalog.jsonb_array_elements(p_items) item)<=5242880;
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_observation_erasure_cohort_items(JSONB) FROM PUBLIC,anon,authenticated,service_role;

-- One candidate, therefore one owner lock domain, per transaction. Discovery
-- deliberately takes no cohort lock before the canonical owner/scan locks.
CREATE FUNCTION public.retire_expired_observation_evidence()
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE candidate RECORD; cohort internal.observation_evidence_upload_cohorts; retired INTEGER:=0;
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
        SELECT e.owner_id,e.observation_id,e.analysis_id,e.media_id,e.expires_at
        FROM internal.observation_evidence_objects e
        WHERE e.expires_at<=clock_timestamp()
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts c WHERE c.analysis_id=e.analysis_id)
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

CREATE FUNCTION public.claim_observation_evidence_erasure()
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE claim JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN NULL; END IF;
    claim:=internal.claim_observation_evidence_erasure();
    IF claim IS NULL THEN RETURN NULL; END IF;
    RETURN jsonb_build_object('object_id',claim->'object_id','claim_token',claim->'claim_token','claim_expires_at',claim->'claim_expires_at');
END;
$$;

CREATE FUNCTION public.finish_observation_evidence_erasure(p_object UUID,p_claim UUID,p_success BOOLEAN)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    -- Gate rollback stops new I/O, never settlement of an existing exact lease.
    RETURN internal.finish_observation_evidence_erasure(p_object,p_claim,p_success);
END;
$$;
REVOKE ALL ON FUNCTION public.retire_expired_observation_evidence(),public.claim_observation_evidence_erasure(),
    public.finish_observation_evidence_erasure(UUID,UUID,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.retire_expired_observation_evidence(),public.claim_observation_evidence_erasure(),
    public.finish_observation_evidence_erasure(UUID,UUID,BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.retire_expired_observation_evidence()','Retire one expired unbound immutable cohort or one legacy receipt without renewing evidence.'),
('service_role','public.claim_observation_evidence_erasure()','Lease one opaque private-evidence erasure obligation under an independent closed gate.'),
('service_role','public.finish_observation_evidence_erasure(uuid,uuid,boolean)','Settle only the original unexpired private-evidence erasure claim after marker verification.');

RESET lock_timeout;
RESET statement_timeout;
