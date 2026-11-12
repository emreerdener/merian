-- HQ-334 recovery prerequisite: permanently deny old acquisition OIDs.
-- No held request, gate, cron or claim is cleared by this migration.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

DO $$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.retire_expired_observation_evidence()'::regprocedure) IS DISTINCT FROM 'beca3cc056e6e8e879c447de68f20cc4' THEN RAISE EXCEPTION 'legacy cleanup source drift'; END IF;
 IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='retire_expired_observation_evidence') <> 1 THEN RAISE EXCEPTION 'legacy cleanup overload drift'; END IF;
END $$;

CREATE FUNCTION internal.retire_expired_observation_evidence_worker_impl()
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
            AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations v WHERE v.analysis_id=e.analysis_id)
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
REVOKE ALL ON FUNCTION internal.retire_expired_observation_evidence_worker_impl() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.retire_expired_observation_evidence()
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'legacy_private_evidence_acquisition_denied' USING ERRCODE='42501'; END;
$$;
REVOKE ALL ON FUNCTION public.retire_expired_observation_evidence() FROM PUBLIC,anon,authenticated,service_role;

DO $$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.retire_expired_observation_video_evidence()'::regprocedure) IS DISTINCT FROM '1a0fe0f511beb1fcacc7f3ae5435dc82' THEN RAISE EXCEPTION 'legacy cleanup source drift'; END IF;
 IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='retire_expired_observation_video_evidence') <> 1 THEN RAISE EXCEPTION 'legacy cleanup overload drift'; END IF;
END $$;

CREATE FUNCTION internal.retire_expired_observation_video_evidence_worker_impl()
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE allocation internal.observation_video_evidence_allocations; binding internal.observation_analysis_source_bindings; removed INTEGER;
BEGIN
 PERFORM internal.require_service_role();
 IF (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN 0; END IF;
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations a WHERE a.expires_at<=clock_timestamp()
  AND EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=a.analysis_id)
  AND internal.observation_video_evidence_execution_clear(a.analysis_id)
  ORDER BY a.expires_at,a.analysis_id LIMIT 1;
 IF NOT FOUND THEN RETURN 0; END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=allocation.analysis_id;
 binding:=internal.lock_owned_observation_video_source_binding(allocation.owner_id,allocation.observation_id,allocation.analysis_id,binding.input_snapshot);
 IF NOT internal.observation_video_evidence_execution_clear(binding.analysis_id)
  OR (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN 0; END IF;
 -- A concurrent cleanup may have completed while this worker waited for locks.
 IF NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=binding.analysis_id) THEN RETURN 0; END IF;
 PERFORM internal.video_evidence_receipt(binding);
 DELETE FROM internal.observation_evidence_objects WHERE analysis_id=binding.analysis_id;
 GET DIAGNOSTICS removed=ROW_COUNT;
 RETURN removed;
EXCEPTION WHEN SQLSTATE 'P0002' THEN RETURN 0;
END;
$$;
REVOKE ALL ON FUNCTION internal.retire_expired_observation_video_evidence_worker_impl() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.retire_expired_observation_video_evidence()
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'legacy_private_evidence_acquisition_denied' USING ERRCODE='42501'; END;
$$;
REVOKE ALL ON FUNCTION public.retire_expired_observation_video_evidence() FROM PUBLIC,anon,authenticated,service_role;

DO $$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.claim_observation_evidence_erasure()'::regprocedure) IS DISTINCT FROM '6f5a74c21bed5ac438a96844abaa6df8' THEN RAISE EXCEPTION 'legacy cleanup source drift'; END IF;
 IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='claim_observation_evidence_erasure') <> 1 THEN RAISE EXCEPTION 'legacy cleanup overload drift'; END IF;
END $$;

CREATE FUNCTION internal.claim_observation_evidence_erasure_worker_impl()
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
REVOKE ALL ON FUNCTION internal.claim_observation_evidence_erasure_worker_impl() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.claim_observation_evidence_erasure()
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'legacy_private_evidence_acquisition_denied' USING ERRCODE='42501'; END;
$$;
REVOKE ALL ON FUNCTION public.claim_observation_evidence_erasure() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.require_observation_evidence_dispatch(p_dispatch_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE state internal.observation_evidence_worker_state%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO state FROM internal.observation_evidence_worker_state WHERE singleton FOR UPDATE;
    IF NOT FOUND OR p_dispatch_id IS NULL OR NOT state.enabled
       OR state.pending_request_id IS NULL OR state.pending_dispatch_id IS DISTINCT FROM p_dispatch_id
       OR state.approved_project IS NULL
       OR internal.observation_evidence_worker_transport(state.approved_project) IS NULL
       OR (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'private_evidence_dispatch_unavailable' USING ERRCODE='42501';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_observation_evidence_dispatch(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.retire_expired_observation_evidence_for_dispatch(p_dispatch_id UUID)
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.require_observation_evidence_dispatch(p_dispatch_id);
 RETURN internal.retire_expired_observation_evidence_worker_impl();
END;
$$;
REVOKE ALL ON FUNCTION public.retire_expired_observation_evidence_for_dispatch(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.retire_expired_observation_evidence_for_dispatch(UUID) TO service_role;

DELETE FROM internal.privileged_routine_grants WHERE role_name='service_role' AND routine_signature='public.retire_expired_observation_evidence()';
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES ('service_role','public.retire_expired_observation_evidence_for_dispatch(uuid)','Acquire private cleanup work only under the locked current dispatch; legacy entry permanently denied.');

CREATE FUNCTION public.retire_expired_observation_video_evidence_for_dispatch(p_dispatch_id UUID)
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.require_observation_evidence_dispatch(p_dispatch_id);
 RETURN internal.retire_expired_observation_video_evidence_worker_impl();
END;
$$;
REVOKE ALL ON FUNCTION public.retire_expired_observation_video_evidence_for_dispatch(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.retire_expired_observation_video_evidence_for_dispatch(UUID) TO service_role;

DELETE FROM internal.privileged_routine_grants WHERE role_name='service_role' AND routine_signature='public.retire_expired_observation_video_evidence()';
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES ('service_role','public.retire_expired_observation_video_evidence_for_dispatch(uuid)','Acquire private cleanup work only under the locked current dispatch; legacy entry permanently denied.');

CREATE FUNCTION public.claim_observation_evidence_erasure_for_dispatch(p_dispatch_id UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.require_observation_evidence_dispatch(p_dispatch_id);
 RETURN internal.claim_observation_evidence_erasure_worker_impl();
END;
$$;
REVOKE ALL ON FUNCTION public.claim_observation_evidence_erasure_for_dispatch(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_observation_evidence_erasure_for_dispatch(UUID) TO service_role;

DELETE FROM internal.privileged_routine_grants WHERE role_name='service_role' AND routine_signature='public.claim_observation_evidence_erasure()';
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES ('service_role','public.claim_observation_evidence_erasure_for_dispatch(uuid)','Acquire private cleanup work only under the locked current dispatch; legacy entry permanently denied.');

-- Exact-token finish remains available after gate closure or dispatch rotation.
RESET lock_timeout;
RESET statement_timeout;
