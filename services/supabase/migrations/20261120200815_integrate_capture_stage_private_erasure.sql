SET lock_timeout='5s';
SET statement_timeout='2min';

-- One existing dispatcher, two disjoint namespaces and durable registries.
-- No TTL retirement, additional request, gate activation or schedule change.
ALTER TABLE internal.initial_capture_audio_stage_erasure
    ADD COLUMN first_observed_at TIMESTAMPTZ,
    ADD COLUMN last_mark_failed BOOLEAN;
UPDATE internal.initial_capture_audio_stage_erasure SET first_observed_at=available_at;
ALTER TABLE internal.initial_capture_audio_stage_erasure ALTER COLUMN first_observed_at SET DEFAULT clock_timestamp();

CREATE FUNCTION public.claim_private_evidence_erasure_v4_for_dispatch(p_dispatch_id UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE candidate RECORD; saved internal.initial_capture_audio_stage_erasure; claim JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.require_observation_evidence_dispatch(p_dispatch_id);
    -- Oldest eligible work across both registries prevents a History backlog
    -- from starving capture-stage erasure. The dispatch lock serializes claims.
    SELECT * INTO candidate FROM (
        SELECT 'history'::TEXT AS kind,object_id,available_at FROM internal.observation_evidence_erasure
            WHERE erased_at IS NULL AND available_at<=clock_timestamp()
                AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp())
        UNION ALL
        SELECT 'capture_stage',object_id,available_at FROM internal.initial_capture_audio_stage_erasure
            WHERE erased_at IS NULL AND available_at<=clock_timestamp()
                AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp())
    ) due ORDER BY available_at,kind,object_id LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF candidate.kind='history' THEN
        claim:=internal.claim_observation_evidence_erasure_worker_impl();
        IF claim IS NULL THEN RETURN NULL; END IF;
        RETURN claim||jsonb_build_object('namespace','history','backend_sha256',NULL);
    END IF;
    SELECT * INTO saved FROM internal.initial_capture_audio_stage_erasure
        WHERE object_id=candidate.object_id AND erased_at IS NULL AND available_at<=clock_timestamp()
            AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp()) FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN NULL; END IF;
    UPDATE internal.initial_capture_audio_stage_erasure SET claim_token=gen_random_uuid(),claim_expires_at=clock_timestamp()+interval '60 seconds'
        WHERE object_id=saved.object_id RETURNING * INTO saved;
    RETURN jsonb_build_object('object_id',saved.object_id,'claim_token',saved.claim_token,'claim_expires_at',saved.claim_expires_at,
        'namespace','capture_stage','backend_sha256',saved.backend_sha256);
END;
$$;

-- The namespace/backend/token tuple is immutable settlement authority. Finishing
-- an existing claim remains allowed after pause; acquiring another does not.
CREATE FUNCTION public.finish_private_evidence_erasure_v4(p_namespace TEXT,p_object UUID,p_claim UUID,p_backend TEXT,p_success BOOLEAN)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_success IS NULL OR p_namespace IS NULL OR p_namespace NOT IN('history','capture_stage')
        OR p_object IS NULL OR p_claim IS NULL
        OR (p_namespace='history' AND p_backend IS NOT NULL)
        OR (p_namespace='capture_stage' AND (p_backend IS NULL OR p_backend !~ '^[0-9a-f]{64}$')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF p_namespace='history' THEN RETURN internal.finish_observation_evidence_erasure(p_object,p_claim,p_success); END IF;
    UPDATE internal.initial_capture_audio_stage_erasure
        SET erased_at=CASE WHEN p_success THEN clock_timestamp() ELSE NULL END,
            available_at=clock_timestamp()+interval '1 minute',claim_token=NULL,claim_expires_at=NULL,last_mark_failed=NOT p_success
        WHERE object_id=p_object AND backend_sha256=p_backend AND claim_token=p_claim
            AND claim_expires_at>clock_timestamp() AND erased_at IS NULL;
    RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_private_evidence_erasure_v4_for_dispatch(UUID),
    public.finish_private_evidence_erasure_v4(TEXT,UUID,UUID,TEXT,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_private_evidence_erasure_v4_for_dispatch(UUID),
    public.finish_private_evidence_erasure_v4(TEXT,UUID,UUID,TEXT,BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.claim_private_evidence_erasure_v4_for_dispatch(uuid)','Acquire one oldest typed private erasure claim across History and retired capture stages under the current dispatch fence.'),
 ('service_role','public.finish_private_evidence_erasure_v4(text,uuid,uuid,text,boolean)','Settle the exact namespace/backend/object/token without renewing its original private erasure lease.');

DO $constraint$
DECLARE saved RECORD;
BEGIN
 SELECT c.conname,pg_get_constraintdef(c.oid) definition INTO STRICT saved
 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attname='last_receipt_schema_version'
 WHERE c.conrelid='internal.observation_evidence_worker_state'::regclass AND c.contype='c' AND c.conkey=ARRAY[a.attnum];
 IF saved.definition IS DISTINCT FROM 'CHECK ((last_receipt_schema_version = ANY (ARRAY[2, 3])))' THEN
    RAISE EXCEPTION 'capture_stage_worker_receipt_constraint_drift'; END IF;
 EXECUTE format('ALTER TABLE internal.observation_evidence_worker_state DROP CONSTRAINT %I',saved.conname);
END;
$constraint$;
ALTER TABLE internal.observation_evidence_worker_state ADD CONSTRAINT evidence_worker_receipt_generation CHECK(last_receipt_schema_version IN(2,3,4));
CREATE OR REPLACE FUNCTION internal.valid_observation_evidence_worker_receipt(p_receipt JSONB,p_dispatch_id UUID)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF p_dispatch_id IS NULL OR p_receipt IS NULL OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object' THEN RETURN FALSE; END IF;
 IF jsonb_typeof(p_receipt->'dispatch_id') IS DISTINCT FROM 'string' OR p_receipt->>'dispatch_id' IS DISTINCT FROM p_dispatch_id::TEXT THEN RETURN FALSE; END IF;
 IF p_receipt->'schema_version' IN('3'::JSONB,'4'::JSONB) THEN
    RETURN internal.valid_composition_evidence_worker_counts(p_receipt-'schema_version'-'dispatch_id'); END IF;
 RETURN COALESCE(p_receipt->'schema_version'='2'::JSONB AND internal.valid_observation_evidence_worker_receipt(p_receipt-'schema_version'-'dispatch_id'),FALSE);
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_observation_evidence_worker_receipt(JSONB,UUID) FROM PUBLIC,anon,authenticated,service_role;
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.dispatch_observation_evidence_erasure()'::regprocedure);
 anchor:='valid_receipt AND receipt->>''schema_version''=''3''';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_stage_dispatch_receipt_drift'; END IF;
 EXECUTE replace(definition,anchor,'valid_receipt AND receipt->>''schema_version'' IN (''3'',''4'')');
 definition:=pg_get_functiondef('public.get_observation_evidence_erasure_health()'::regprocedure);
 anchor:='    queue JSONB; candidates JSONB; telemetry JSONB;';
 IF strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'capture_stage_health_declaration_drift'; END IF;
 definition:=replace(definition,anchor,anchor||' stage_queue JSONB;');
 anchor:='    RETURN jsonb_build_object(''schema_version'',1,''generated_at'',observed_at,''queue'',queue,''retirement'',candidates,''worker'',telemetry);';
 IF strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'capture_stage_health_return_drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
    SELECT jsonb_build_object('pending',count(*) FILTER(WHERE erased_at IS NULL),
        'claimable',count(*) FILTER(WHERE erased_at IS NULL AND available_at<=observed_at AND (claim_expires_at IS NULL OR claim_expires_at<=observed_at)),
        'deferred',count(*) FILTER(WHERE erased_at IS NULL AND available_at>observed_at AND (claim_expires_at IS NULL OR claim_expires_at<=observed_at)),
        'live_claims',count(*) FILTER(WHERE erased_at IS NULL AND claim_expires_at>observed_at),
        'expired_claims',count(*) FILTER(WHERE erased_at IS NULL AND claim_expires_at<=observed_at),
        'marker_failures',count(*) FILTER(WHERE erased_at IS NULL AND last_mark_failed IS TRUE),
        'unknown_age',count(*) FILTER(WHERE erased_at IS NULL AND first_observed_at IS NULL),
        'oldest_pending_age_seconds',greatest(0,extract(epoch FROM observed_at-min(first_observed_at) FILTER(WHERE erased_at IS NULL))),
        'oldest_due_age_seconds',greatest(0,extract(epoch FROM observed_at-min(available_at) FILTER(WHERE erased_at IS NULL AND available_at<=observed_at AND (claim_expires_at IS NULL OR claim_expires_at<=observed_at)))))
    INTO stage_queue FROM internal.initial_capture_audio_stage_erasure;
    RETURN jsonb_build_object('schema_version',2,'generated_at',observed_at,'queue',queue,'retirement',candidates,'worker',telemetry,'capture_stage',stage_queue);
$body$);
END;
$patch$;
COMMENT ON COLUMN internal.observation_evidence_worker_state.last_receipt_schema_version IS
 'Observed correlated terminal generation. Only V4 supports typed capture-stage cleanup; null/earlier generations remain unqualified. No receipt alone proves empty queues or physical erasure.';
RESET statement_timeout;
RESET lock_timeout;
